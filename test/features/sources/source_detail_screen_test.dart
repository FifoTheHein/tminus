import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/core/engine/engine_models.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sources/source_admin.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/common/color_palette_picker.dart';
import 'package:tminus/features/sources/source_detail_screen.dart';
import 'package:tminus/features/sources/sources_screen.dart';

import '../../core/fixtures.dart' show occ;
import '../harness.dart';
import 'source_test_support.dart';

const _error404 =
    'Link no longer works (HTTP 404). The calendar may have been unpublished.';

http.Client _goodFeed() =>
    MockClient((_) async => http.Response(weekFeed, 200));

/// An ICS source whose last sync ended in [outcome] with [error].
Future<void> _seedFailing(
  SourceConfig source, {
  required SyncOutcome outcome,
  String error = _error404,
  DateTime? lastWorked,
}) async {
  await getIt<SourceRepository>().save(source);
  await getIt<SourceRepository>().updateSyncState(
    source.id,
    SourceSyncState(lastSuccessUtc: lastWorked, lastError: error),
  );
  await getIt<SyncLogRepository>().add(
    SyncLogEntry(
      sourceId: source.id,
      atUtc: DateTime.utc(2026, 10, 6, 7, 20),
      outcome: outcome,
      message: error,
    ),
  );
}

/// A restored feed: off, with its marker set, and no link.
Future<void> _seedNeedsLink() async {
  await getIt<SourceRepository>().save(icsSource(enabled: false));
  await getIt<AppSettings>().setSourceSetup('ics-1', SourceSetup.needsLink);
}

/// Opens the re-link dialog, types [link] and checks it.
Future<void> _checkInDialog(WidgetTester t, String link) async {
  await t.tap(find.byKey(const Key('pasteNewLink')));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('icsLinkField')), link);
  await t.pump();
  await t.tap(find.byKey(const Key('checkLink')));
  await t.pumpAndSettle();
}

bool _saveIsOn(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('relinkSave'))).onPressed !=
    null;

Finder _inAppBar(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));

/// A `SourceAdmin` whose edits fail, with a message that quotes a name.
class _FailingEdits extends SourceAdmin {
  _FailingEdits()
    : super(
        sources: getIt(),
        secrets: getIt(),
        bodies: getIt(),
        platform: getIt(),
        settings: getIt(),
        occurrences: getIt(),
        db: getIt(),
      );

  @override
  Future<void> edit(
    String sourceId, {
    String? name,
    int? color,
    String? defaultProfileId,
    bool clearDefaultProfile = false,
  }) async => throw StateError('could not rename to $name');
}

void main() {
  testWidgets('the source detail shows only the masked link', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        h.secrets['ics-url.ics-1'] = secretLink;
        await getIt<SourceRepository>().save(icsSource());
      },
    );

    expect(find.byKey(const Key('maskedLink')), findsOneWidget);
    expect(find.text(maskedSecretLink), findsOneWidget);
    // The link is in no text on the screen, whatever kind of text, and not in
    // what is behind it either.
    expect(find.textContaining(secretToken), findsNothing);
    expect(
      find.textContaining(secretToken, skipOffstage: false, findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('owa/calendar', skipOffstage: false),
      findsNothing,
    );
    // Nor in the route.
    final route = h.router.routerDelegate.currentConfiguration;
    expect(route.uri.toString(), isNot(contains(secretToken)));
    expect(route.extra, isNull);
    await h.dispose(t);
  });

  testWidgets('an unknown source id says the source was removed', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/gone-1');

    expect(find.byKey(const Key('sourceGone')), findsOneWidget);
    expect(find.text('This source was removed.'), findsOneWidget);
    expect(find.byKey(const Key('problemCard')), findsNothing);
    expect(find.byKey(const Key('syncNow')), findsNothing);

    await t.tap(find.text('Back to Sources'));
    await t.pumpAndSettle();
    expect(find.byType(SourcesScreen), findsOneWidget);
    expect(find.byType(SourceDetailScreen), findsNothing);
    await h.dispose(t);
  });

  testWidgets(
    're-linking saves the link, enables a source that needed it and runs a '
    'manual sync',
    (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        feeds: _goodFeed(),
        seed: (h) => _seedNeedsLink(),
      );
      // Before: the source waits for a link, so it is off and locked.
      expect(find.text("Paste this calendar's link"), findsOneWidget);
      expect(find.text('Needs its link'), findsOneWidget);
      expect(find.text(linkMissingText), findsOneWidget);
      expect(
        t
            .widget<SwitchListTile>(find.byKey(const Key('enabledSwitch')))
            .onChanged,
        isNull,
      );
      expect(find.text('Finish setting it up first'), findsOneWidget);

      await _checkInDialog(t, freshLink);
      expect(find.byKey(const Key('probeFound')), findsOneWidget);
      await t.tap(find.byKey(const Key('relinkSave')));
      await t.pumpAndSettle();

      // The link is in secure storage, the source is on, the marker is gone,
      // and one manual sync was asked for.
      expect(h.secrets['ics-url.ics-1'], freshLink);
      expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isTrue);
      expect(
        await getIt<AppSettings>().sourceSetup('ics-1'),
        SourceSetup.ready,
      );
      expect(h.syncs, [SyncTrigger.manual]);
      // On the screen: no dialog, no card, the new link masked, a free switch.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('problemCard')), findsNothing);
      expect(find.text(maskedFreshLink), findsOneWidget);
      expect(
        t.widget<SwitchListTile>(find.byKey(const Key('enabledSwitch'))).value,
        isTrue,
      );
      expect(
        t
            .widget<SwitchListTile>(find.byKey(const Key('enabledSwitch')))
            .onChanged,
        isNotNull,
      );
      await h.dispose(t);
    },
  );

  // Beyond the plan's list from here on.

  testWidgets(
    're-linking keeps the link out of the database, the logs, the route, the '
    'clipboard and the screen',
    (t) async {
      tallScreen(t);
      final logs = captureLogs();
      final platform = recordPlatformCalls();
      final stopSemantics = watchSemantics(t);
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        feeds: _goodFeed(),
        seed: (h) async {
          h.secrets['ics-url.ics-1'] = secretLink;
          await _seedFailing(icsSource(), outcome: SyncOutcome.httpError);
        },
      );
      // Before: the old link, masked.
      expect(find.text(maskedSecretLink), findsOneWidget);

      await _checkInDialog(t, freshLink);
      await t.tap(find.byKey(const Key('relinkSave')));
      await t.pumpAndSettle();

      expect(h.secrets['ics-url.ics-1'], freshLink);
      for (final token in [
        freshToken,
        secretToken,
        'outlook.office365.com',
        'fresh.example.test',
      ]) {
        expect(await dumpDatabase(h.db), isNot(contains(token)), reason: token);
        expect(logs.join('\n'), isNot(contains(token)), reason: token);
        for (final call in [...h.uiCalls, ...h.engineCalls, ...h.syncCalls]) {
          expect('${call.arguments}', isNot(contains(token)), reason: token);
        }
      }
      final route = h.router.routerDelegate.currentConfiguration;
      expect(route.uri.toString(), isNot(contains(freshToken)));
      expect(route.extra, isNull);
      // Once the dialog is gone only the new link's mask shows: the old one is
      // replaced, and neither link, in whole or in part, is in a text, a
      // tooltip or a semantics label.
      expect(find.text(maskedFreshLink), findsOneWidget);
      expect(find.text(maskedSecretLink), findsNothing);
      for (final token in [freshToken, secretToken, 'owa/calendar']) {
        expect(
          find.textContaining(token, skipOffstage: false, findRichText: true),
          findsNothing,
          reason: token,
        );
        expect(tooltipText(t), isNot(contains(token)), reason: token);
        expect(semanticsText(t), isNot(contains(token)), reason: token);
      }
      // Nothing was copied, and nobody was told anything.
      expect(platform.where((c) => c.method == 'Clipboard.setData'), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      stopSemantics();
      releaseLogs();
      await h.dispose(t);
    },
  );

  testWidgets('the re-link dialog saves only a link that checked out', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      feeds: _goodFeed(),
      seed: (h) => _seedNeedsLink(),
    );
    await t.tap(find.byKey(const Key('pasteNewLink')));
    await t.pumpAndSettle();
    // The title says whose link this is.
    expect(find.text('New link for Work Outlook'), findsOneWidget);
    expect(_saveIsOn(t), isFalse);

    // Typed, not checked.
    await t.enterText(find.byKey(const Key('icsLinkField')), freshLink);
    await t.pump();
    expect(_saveIsOn(t), isFalse);

    await t.tap(find.byKey(const Key('checkLink')));
    await t.pumpAndSettle();
    expect(find.text('Found 2 events this week'), findsOneWidget);
    expect(_saveIsOn(t), isTrue);

    // Changed after the check: the result is forgotten, and so is the Save.
    await t.enterText(
      find.byKey(const Key('icsLinkField')),
      'https://example.test/other.ics',
    );
    await t.pump();
    expect(find.byKey(const Key('probeFound')), findsNothing);
    expect(_saveIsOn(t), isFalse);
    await h.dispose(t);
  });

  testWidgets('a link that does not check out says why and cannot be saved', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      feeds: MockClient((_) async => http.Response('', 404)),
      seed: (h) => _seedNeedsLink(),
    );

    await _checkInDialog(t, freshLink);

    expect(find.byKey(const Key('probeFailed')), findsOneWidget);
    expect(find.text(_error404), findsOneWidget);
    expect(find.byKey(const Key('probeFound')), findsNothing);
    expect(_saveIsOn(t), isFalse);
    // What the probe says never repeats the link (the field itself shows what
    // the user typed, so only the result is looked at).
    expect(
      find.descendant(
        of: find.byKey(const Key('probeFailed')),
        matching: find.textContaining(freshToken),
      ),
      findsNothing,
    );
    await h.dispose(t);
  });

  testWidgets('an http link shows the insecure warning in the re-link dialog', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      feeds: _goodFeed(),
      seed: (h) => _seedNeedsLink(),
    );

    await _checkInDialog(t, 'http://example.test/c.ics');

    expect(find.byKey(const Key('insecureWarning')), findsOneWidget);
    expect(find.text('This link is not encrypted (http)'), findsOneWidget);
    // It is a warning, not a block: the link can still be saved.
    expect(_saveIsOn(t), isTrue);
    await h.dispose(t);
  });

  testWidgets('cancelling the re-link dialog changes nothing', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      feeds: _goodFeed(),
      seed: (h) async {
        h.secrets['ics-url.ics-1'] = secretLink;
        await _seedNeedsLink();
      },
    );

    await _checkInDialog(t, freshLink);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(h.secrets['ics-url.ics-1'], secretLink);
    expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isFalse);
    expect(
      await getIt<AppSettings>().sourceSetup('ics-1'),
      SourceSetup.needsLink,
    );
    expect(h.syncs, isEmpty);
    await h.dispose(t);
  });

  testWidgets(
    'a link that cannot be saved shows fixed text, logs the code only and '
    'keeps the dialog',
    (t) async {
      tallScreen(t);
      final logs = captureLogs();
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        feeds: _goodFeed(),
        seed: (h) => _seedNeedsLink(),
      );
      // The store refuses to write, and its message quotes the link.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
            if (call.method == 'write') {
              throw PlatformException(
                code: 'keystore',
                message: 'could not store $freshLink',
              );
            }
            return null;
          });

      await _checkInDialog(t, freshLink);
      await t.tap(find.byKey(const Key('relinkSave')));
      await t.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Could not save the link.'),
        ),
        findsOneWidget,
      );
      // The store's message, which quotes the link, is nowhere on the screen.
      expect(find.textContaining('could not store'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining(freshToken),
        ),
        findsNothing,
      );
      // The dialog stays, so the user can try again, and nothing changed.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_saveIsOn(t), isTrue);
      expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isFalse);
      expect(h.syncs, isEmpty);
      expect(logs.where((l) => l.contains('Could not save the link.')), [
        'Could not save the link. (keystore)',
      ]);
      expect(logs.join('\n'), isNot(contains(freshToken)));
      expect(logs.join('\n'), isNot(contains('could not store')));
      releaseLogs();
      await h.dispose(t);
    },
  );

  testWidgets('the problem card names the cause and says when it last worked', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => _seedFailing(
        icsSource(name: 'Team rota'),
        outcome: SyncOutcome.httpError,
        lastWorked: DateTime.utc(2026, 10, 4, 16, 2),
      ),
    );

    expect(find.byKey(const Key('problemCard')), findsOneWidget);
    expect(find.text('Link no longer works'), findsOneWidget);
    expect(find.text(_error404), findsOneWidget);
    // 16:02 UTC in the harness's zone (Johannesburg, UTC+2).
    expect(find.text('Last worked Sun 4 Oct 18:02'), findsOneWidget);
    expect(find.byKey(const Key('pasteNewLink')), findsOneWidget);
    expect(find.byKey(const Key('howToFindIt')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a source that never worked says nothing about when', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => _seedFailing(icsSource(), outcome: SyncOutcome.httpError),
    );

    expect(find.byKey(const Key('problemCard')), findsOneWidget);
    expect(find.textContaining('Last worked'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a source with nothing wrong has no problem card', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        h.secrets['ics-url.ics-1'] = secretLink;
        await getIt<SourceRepository>().save(icsSource());
        await getIt<SourceRepository>().updateSyncState(
          'ics-1',
          SourceSyncState(lastSuccessUtc: DateTime.utc(2026, 10, 6, 7, 20)),
        );
      },
    );

    expect(find.byKey(const Key('problemCard')), findsNothing);
    expect(find.byKey(const Key('maskedLink')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('How to find it shows the Outlook path', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => _seedFailing(icsSource(), outcome: SyncOutcome.httpError),
    );

    await t.tap(find.byKey(const Key('howToFindIt')));
    await t.pumpAndSettle();

    expect(
      t.widget<Text>(find.byKey(const Key('findLinkPath'))).data,
      'Outlook → Settings → Calendar → Shared calendars → Publish → ICS',
    );
    expect(find.text('Copy the link that ends in .ics.'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a link that cannot be read shows Link missing', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );

    // Nothing in secure storage for this source.
    expect(find.text(linkMissingText), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a secure store that fails shows Link missing and logs the code '
      'only', (t) async {
    tallScreen(t);
    final logs = captureLogs();
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(secureStorageChannel, (call) async {
              throw PlatformException(
                code: 'keystore',
                message: 'cannot read $secretLink',
              );
            });
      },
    );

    expect(find.text(linkMissingText), findsOneWidget);
    expect(logs.where((l) => l.contains('Reading the saved link failed')), [
      'Reading the saved link failed (keystore)',
    ]);
    expect(logs.join('\n'), isNot(contains(secretToken)));
    expect(find.textContaining(secretToken, skipOffstage: false), findsNothing);
    releaseLogs();
    await h.dispose(t);
  });

  testWidgets('a phone source shows its calendar and account', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/device-1',
      seed: (h) async {
        h.deviceCalendars = [
          phoneCalendar('3', 'Holidays'),
          phoneCalendar('4', 'Personal', account: 'me@gmail.com'),
        ];
        await getIt<SourceRepository>().save(phoneSource());
      },
    );

    expect(
      t.widget<Text>(find.byKey(const Key('calendarLine'))).data,
      'Personal · me@gmail.com',
    );
    // A phone source has no link.
    expect(find.byKey(const Key('maskedLink')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a phone source whose calendar is gone says so', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/device-1',
      seed: (h) async {
        h.deviceCalendars = [phoneCalendar('3', 'Holidays')];
        await getIt<SourceRepository>().save(phoneSource());
      },
    );

    expect(
      t.widget<Text>(find.byKey(const Key('calendarLine'))).data,
      'Not on this phone',
    );
    await h.dispose(t);
  });

  testWidgets('calendar access permanently denied offers Open settings', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/device-1',
      seed: (h) async {
        h.ui['requestPermission'] = (_) => 'permanentlyDenied';
        await getIt<SourceRepository>().save(phoneSource());
        await getIt<SourceRepository>().updateSyncState(
          'device-1',
          SourceSyncState(lastError: 'Calendar access was turned off.'),
        );
        await getIt<SyncLogRepository>().add(
          SyncLogEntry(
            sourceId: 'device-1',
            atUtc: DateTime.utc(2026, 10, 6, 7, 20),
            outcome: SyncOutcome.calendarAccessDenied,
            message: 'Calendar access was turned off.',
          ),
        );
      },
    );
    expect(find.text('Calendar access is off'), findsOneWidget);
    expect(find.text('Calendar access was turned off.'), findsOneWidget);
    expect(find.byKey(const Key('openSettings')), findsNothing);

    await t.tap(find.byKey(const Key('allowAccess')));
    await t.pumpAndSettle();

    // Android will not ask again: say so, and offer the settings instead.
    expect(
      find.text('Calendar access is off. Turn it on in Settings.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('allowAccess')), findsNothing);
    expect(h.syncs, isEmpty);
    final asked = h.uiCalls.singleWhere((c) => c.method == 'requestPermission');
    expect(asked.arguments, {'kind': 'calendar'});

    await t.tap(find.byKey(const Key('openSettings')));
    await t.pumpAndSettle();
    expect(h.uiCalls.map((c) => c.method), contains('openAppDetails'));
    await h.dispose(t);
  });

  testWidgets('Allow access asks for the permission and syncs once it is '
      'granted', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/device-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(phoneSource());
        await getIt<SourceRepository>().updateSyncState(
          'device-1',
          SourceSyncState(lastError: 'Calendar access was turned off.'),
        );
        await getIt<SyncLogRepository>().add(
          SyncLogEntry(
            sourceId: 'device-1',
            atUtc: DateTime.utc(2026, 10, 6, 7, 20),
            outcome: SyncOutcome.calendarAccessDenied,
          ),
        );
      },
    );

    await t.tap(find.byKey(const Key('allowAccess')));
    await t.pumpAndSettle();

    final asked = h.uiCalls.singleWhere((c) => c.method == 'requestPermission');
    expect(asked.arguments, {'kind': 'calendar'});
    expect(h.syncs, [SyncTrigger.manual]);
    expect(h.uiCalls.map((c) => c.method), isNot(contains('openAppDetails')));
    await h.dispose(t);
  });

  testWidgets('choosing a calendar for a restored phone source enables it', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/device-1',
      seed: (h) async {
        h.deviceCalendars = [
          phoneCalendar('4', 'Personal', account: 'me@gmail.com'),
          phoneCalendar('5', 'Holidays', color: 0xFFE89A5B),
        ];
        // After a restore: the old phone's calendar id, off, marker set.
        await getIt<SourceRepository>().save(
          phoneSource(calendarId: '9', enabled: false),
        );
        await getIt<AppSettings>().setSourceSetup(
          'device-1',
          SourceSetup.needsCalendar,
        );
      },
    );
    expect(find.text('Choose this calendar on this phone'), findsOneWidget);
    expect(
      t
          .widget<SwitchListTile>(find.byKey(const Key('enabledSwitch')))
          .onChanged,
      isNull,
    );

    await t.tap(find.byKey(const Key('chooseCalendar')));
    await t.pumpAndSettle();
    // The sheet asks for access first, then lists the phone's calendars.
    expect(
      h.uiCalls.singleWhere((c) => c.method == 'requestPermission').arguments,
      {'kind': 'calendar'},
    );
    expect(find.text('Choose a calendar'), findsOneWidget);
    expect(find.byKey(const Key('calendar-4')), findsOneWidget);
    expect(find.byKey(const Key('calendar-5')), findsOneWidget);
    expect(h.syncs, isEmpty);

    await t.tap(find.byKey(const Key('calendar-4')));
    await t.pumpAndSettle();

    final source = (await getIt<SourceRepository>().byId('device-1'))!;
    expect(source.deviceCalendarId, '4');
    expect(source.enabled, isTrue);
    expect(
      await getIt<AppSettings>().sourceSetup('device-1'),
      SourceSetup.ready,
    );
    expect(h.syncs, [SyncTrigger.manual]);
    // On the screen: the sheet and the card are gone, and the calendar shows.
    expect(find.text('Choose a calendar'), findsNothing);
    expect(find.byKey(const Key('problemCard')), findsNothing);
    expect(
      t.widget<Text>(find.byKey(const Key('calendarLine'))).data,
      'Personal · me@gmail.com',
    );
    expect(
      t.widget<SwitchListTile>(find.byKey(const Key('enabledSwitch'))).value,
      isTrue,
    );
    await h.dispose(t);
  });

  testWidgets('a phone calendar that was removed offers Choose calendar and '
      'marks the other sources\' calendars', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/device-2',
      seed: (h) async {
        h.deviceCalendars = [
          phoneCalendar('3', 'Holidays'),
          phoneCalendar('4', 'Personal'),
        ];
        final sources = getIt<SourceRepository>();
        await sources.save(phoneSource());
        await sources.save(
          phoneSource(id: 'device-2', name: 'Birthdays', calendarId: '8'),
        );
        await sources.updateSyncState(
          'device-2',
          SourceSyncState(
            lastError: 'This calendar was removed from the phone.',
          ),
        );
        await getIt<SyncLogRepository>().add(
          SyncLogEntry(
            sourceId: 'device-2',
            atUtc: DateTime.utc(2026, 10, 6, 7, 20),
            outcome: SyncOutcome.calendarMissing,
          ),
        );
      },
    );
    expect(find.text('Calendar was removed'), findsOneWidget);

    await t.tap(find.byKey(const Key('chooseCalendar')));
    await t.pumpAndSettle();

    // 'device-1' reads calendar 4 already: it is listed, and cannot be chosen
    // again.
    expect(
      find.descendant(
        of: find.byKey(const Key('calendar-4')),
        matching: find.text('Already added'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('calendar-3')),
        matching: find.text('Already added'),
      ),
      findsNothing,
    );
    await t.tap(find.byKey(const Key('calendar-4')));
    await t.pumpAndSettle();
    expect(find.text('Choose a calendar'), findsOneWidget);
    expect(h.syncs, isEmpty);
    await h.dispose(t);
  });

  testWidgets('removing a source asks first, deletes it and asks for a '
      're-plan', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        h.secrets['ics-url.ics-1'] = secretLink;
        await getIt<SourceRepository>().save(icsSource(name: 'Team rota'));
      },
    );

    await t.tap(find.byKey(const Key('removeSource')));
    await t.pumpAndSettle();

    // Asked first: nothing has happened yet.
    expect(find.text('Remove Team rota?'), findsOneWidget);
    expect(find.text('Its alarms are cancelled now.'), findsOneWidget);
    expect(await getIt<SourceRepository>().byId('ics-1'), isNotNull);
    expect(h.replans, 0);

    await t.tap(find.byKey(const Key('confirmRemove')));
    await t.pumpAndSettle();

    expect(await getIt<SourceRepository>().byId('ics-1'), isNull);
    expect(h.secrets, isEmpty);
    expect(h.replans, 1);
    // The list is where the user lands, and nothing was fetched.
    expect(find.byType(SourcesScreen), findsOneWidget);
    expect(find.byType(SourceDetailScreen), findsNothing);
    expect(find.text('This source was removed.'), findsNothing);
    expect(h.syncs, isEmpty);
    await h.dispose(t);
  });

  testWidgets('declining the removal keeps the source', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );

    await t.tap(find.byKey(const Key('removeSource')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SourceDetailScreen), findsOneWidget);
    expect(await getIt<SourceRepository>().byId('ics-1'), isNotNull);
    expect(h.replans, 0);
    await h.dispose(t);
  });

  testWidgets('a source that is removed while its detail is open says so', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );
    expect(find.byKey(const Key('sourceGone')), findsNothing);

    // Removed from elsewhere (an import's counterpart, a restore, a second
    // window).
    await getIt<SourceAdmin>().delete('ics-1');
    await t.pumpAndSettle();

    expect(find.byKey(const Key('sourceGone')), findsOneWidget);
    expect(find.text('This source was removed.'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('Sync now reports this source\'s failure message', (t) async {
    tallScreen(t);
    const message =
        'The calendar server did not answer within 20 s. Try again later.';
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        h.syncResult = (trigger) => SyncReport(
          trigger: trigger,
          outcome: SyncRunOutcome.retry,
          sources: const [
            SourceSyncResult('other', SyncOutcome.httpError, 'Not this one.'),
            SourceSyncResult('ics-1', SyncOutcome.networkError, message),
          ],
        );
      },
    );

    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();

    expect(h.syncs, [SyncTrigger.manual]);
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text(message)),
      findsOneWidget,
    );
    expect(find.text('Not this one.'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('Sync now says Synced. when this source came through', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        h.syncResult = (trigger) => SyncReport(
          trigger: trigger,
          outcome: SyncRunOutcome.ok,
          sources: const [SourceSyncResult('ics-1', SyncOutcome.success)],
          applied: const ApplyResult(armed: 1, cancelled: 0, kept: 0),
        );
      },
    );

    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();

    expect(h.syncs, [SyncTrigger.manual]);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Synced.'),
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('Sync now says when another sync is running', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        h.syncResult = (trigger) =>
            SyncReport(trigger: trigger, outcome: SyncRunOutcome.busy);
      },
    );

    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Another sync is running. Try again in a minute.'),
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('a sync that throws shows fixed text and logs the type only', (
    t,
  ) async {
    tallScreen(t);
    final logs = captureLogs();
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        h.syncResult = (_) => throw StateError('boom $secretLink');
      },
    );

    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Could not sync this calendar.'),
      ),
      findsOneWidget,
    );
    expect(logs.where((l) => l.contains('Could not sync this calendar.')), [
      'Could not sync this calendar. (StateError)',
    ]);
    expect(logs.join('\n'), isNot(contains(secretToken)));
    // The button is back, so the user can try again.
    expect(
      t.widget<OutlinedButton>(find.byKey(const Key('syncNow'))).onPressed,
      isNotNull,
    );
    releaseLogs();
    await h.dispose(t);
  });

  testWidgets('a source that is off cannot be synced', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource(enabled: false)),
    );

    expect(
      t.widget<OutlinedButton>(find.byKey(const Key('syncNow'))).onPressed,
      isNull,
    );
    await h.dispose(t);
  });

  testWidgets(
    'switching a source on fetches it, and switching it off re-plans',
    (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        seed: (h) => getIt<SourceRepository>().save(icsSource(enabled: false)),
      );
      SwitchListTile toggle() =>
          t.widget<SwitchListTile>(find.byKey(const Key('enabledSwitch')));
      expect(toggle().value, isFalse);
      expect(toggle().onChanged, isNotNull);

      await t.tap(find.byKey(const Key('enabledSwitch')));
      await t.pumpAndSettle();

      // Off, it was not fetched: switching it on does that.
      expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isTrue);
      expect(toggle().value, isTrue);
      expect(h.syncs, [SyncTrigger.manual]);
      expect(h.replans, 0);

      await t.tap(find.byKey(const Key('enabledSwitch')));
      await t.pumpAndSettle();

      // Switching off only re-plans: the alarms of the source go.
      expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isFalse);
      expect(toggle().value, isFalse);
      expect(h.syncs, [SyncTrigger.manual]);
      expect(h.replans, 1);
      await h.dispose(t);
    },
  );

  testWidgets('renaming saves the trimmed name and asks for a re-plan', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );
    expect(
      t
          .widget<TextField>(find.byKey(const Key('sourceNameField')))
          .controller!
          .text,
      'Work Outlook',
    );

    await t.enterText(
      find.byKey(const Key('sourceNameField')),
      '  Team rota  ',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect((await getIt<SourceRepository>().byId('ics-1'))!.name, 'Team rota');
    // Submitting and then leaving the field saves once.
    expect(h.replans, 1);
    expect(_inAppBar('Team rota'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('an empty name is put back and nothing is saved', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );

    await t.enterText(find.byKey(const Key('sourceNameField')), '   ');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(
      t
          .widget<TextField>(find.byKey(const Key('sourceNameField')))
          .controller!
          .text,
      'Work Outlook',
    );
    expect(
      (await getIt<SourceRepository>().byId('ics-1'))!.name,
      'Work Outlook',
    );
    expect(h.replans, 0);
    await h.dispose(t);
  });

  testWidgets('a name that could not be saved is put back with fixed text', (
    t,
  ) async {
    tallScreen(t);
    final logs = captureLogs();
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        await getIt.unregister<SourceAdmin>();
        getIt.registerSingleton<SourceAdmin>(_FailingEdits());
      },
    );

    await t.enterText(find.byKey(const Key('sourceNameField')), 'Team rota');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Could not save the change.'),
      ),
      findsOneWidget,
    );
    // The field shows the name that is saved, and nothing was re-planned.
    expect(
      t
          .widget<TextField>(find.byKey(const Key('sourceNameField')))
          .controller!
          .text,
      'Work Outlook',
    );
    expect(h.replans, 0);
    expect(logs.where((l) => l.contains('Could not save the change.')), [
      'Could not save the change. (StateError)',
    ]);
    expect(logs.join('\n'), isNot(contains('Team rota')));
    releaseLogs();
    await h.dispose(t);
  });

  testWidgets('choosing a colour saves it and asks for a re-plan', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );

    await t.tap(find.byKey(ValueKey('colour-${calendarPalette[2]}')));
    await t.pumpAndSettle();

    expect(
      (await getIt<SourceRepository>().byId('ics-1'))!.color,
      calendarPalette[2],
    );
    expect(h.replans, 1);
    await h.dispose(t);
  });

  testWidgets('the default profile choice is saved and asks for a re-plan', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) => getIt<SourceRepository>().save(icsSource()),
    );
    // No profile of its own: the global default's name is in the first entry.
    expect(find.text('Default profile (Meeting)'), findsOneWidget);

    await t.tap(find.byKey(const Key('defaultProfile')));
    await t.pumpAndSettle();
    await t.tap(find.text('Quick').last);
    await t.pumpAndSettle();

    expect(
      (await getIt<SourceRepository>().byId('ics-1'))!.defaultProfileId,
      'quick',
    );
    expect(h.replans, 1);
    expect(find.text('Quick'), findsOneWidget);

    // The first entry hands the choice back to the global default.
    await t.tap(find.byKey(const Key('defaultProfile')));
    await t.pumpAndSettle();
    await t.tap(find.text('Default profile (Meeting)').last);
    await t.pumpAndSettle();

    expect(
      (await getIt<SourceRepository>().byId('ics-1'))!.defaultProfileId,
      isNull,
    );
    expect(h.replans, 2);
    await h.dispose(t);
  });

  testWidgets('Sync now says when the alarms could not be updated', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        // The calendar was read; the engine refused the plan (`applied` is null).
        h.syncResult = (trigger) => SyncReport(
          trigger: trigger,
          outcome: SyncRunOutcome.retry,
          sources: const [SourceSyncResult('ics-1', SyncOutcome.success)],
        );
      },
    );

    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Synced, but the alarms could not be updated.'),
      ),
      findsOneWidget,
    );
    expect(find.text('Synced.'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('Sync now says it could not sync a source the run left out', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        await getIt<SourceRepository>().save(icsSource());
        // Another source was synced; this one is not in the report.
        h.syncResult = (trigger) => SyncReport(
          trigger: trigger,
          outcome: SyncRunOutcome.ok,
          sources: const [SourceSyncResult('other', SyncOutcome.success)],
          applied: const ApplyResult(armed: 1, cancelled: 0, kept: 0),
        );
      },
    );

    await t.tap(find.byKey(const Key('syncNow')));
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Could not sync this calendar.'),
      ),
      findsOneWidget,
    );
    expect(find.text('Synced.'), findsNothing);
    await h.dispose(t);
  });

  testWidgets(
    'a removal confirmed after the screen moved to another source deletes '
    'neither',
    (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        seed: (h) async {
          h.secrets['ics-url.ics-1'] = secretLink;
          h.secrets['ics-url.ics-2'] = freshLink;
          await getIt<SourceRepository>().save(icsSource());
          await getIt<SourceRepository>().save(
            icsSource(id: 'ics-2', name: 'Team rota'),
          );
        },
      );
      await t.tap(find.byKey(const Key('removeSource')));
      await t.pumpAndSettle();
      expect(find.text('Remove Work Outlook?'), findsOneWidget);

      // A Fix notification for the other source arrives while the question is
      // open: go_router keeps this screen and gives it the other source.
      await h.go(t, '/sources/ics-2');
      expect(_inAppBar('Team rota'), findsOneWidget);
      expect(find.text('Remove Work Outlook?'), findsOneWidget);

      await t.tap(find.byKey(const Key('confirmRemove')));
      await t.pumpAndSettle();

      // The question was about Work Outlook, which is not on screen any more,
      // and Team rota, which is, was never asked about. Neither goes.
      expect(await getIt<SourceRepository>().byId('ics-1'), isNotNull);
      expect(await getIt<SourceRepository>().byId('ics-2'), isNotNull);
      expect(
        h.secrets.keys,
        unorderedEquals(['ics-url.ics-1', 'ics-url.ics-2']),
      );
      expect(h.replans, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(_inAppBar('Team rota'), findsOneWidget);
      await h.dispose(t);
    },
  );

  testWidgets(
    'a calendar chosen after the screen moved to another source changes '
    'neither',
    (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources/device-1',
        seed: (h) async {
          h.deviceCalendars = [phoneCalendar('4', 'Personal')];
          final sources = getIt<SourceRepository>();
          await sources.save(phoneSource(calendarId: '9', enabled: false));
          await sources.save(
            phoneSource(
              id: 'device-2',
              name: 'Birthdays',
              calendarId: '8',
              enabled: false,
            ),
          );
          final app = getIt<AppSettings>();
          await app.setSourceSetup('device-1', SourceSetup.needsCalendar);
          await app.setSourceSetup('device-2', SourceSetup.needsCalendar);
        },
      );
      await t.tap(find.byKey(const Key('chooseCalendar')));
      await t.pumpAndSettle();
      expect(find.text('Choose a calendar'), findsOneWidget);

      // Another source is opened while the sheet is up.
      await h.go(t, '/sources/device-2');
      expect(_inAppBar('Birthdays'), findsOneWidget);
      expect(find.text('Choose a calendar'), findsOneWidget);

      await t.tap(find.byKey(const Key('calendar-4')));
      await t.pumpAndSettle();

      // The calendar was picked for Personal, which is not on screen any more,
      // and Birthdays was not asked: neither source changes.
      for (final (id, calendarId) in [('device-1', '9'), ('device-2', '8')]) {
        final source = (await getIt<SourceRepository>().byId(id))!;
        expect(source.deviceCalendarId, calendarId, reason: id);
        expect(source.enabled, isFalse, reason: id);
        expect(
          await getIt<AppSettings>().sourceSetup(id),
          SourceSetup.needsCalendar,
          reason: id,
        );
      }
      expect(h.syncs, isEmpty);
      expect(find.text('Choose a calendar'), findsNothing);
      await h.dispose(t);
    },
  );

  testWidgets('back while saving does not close the dialog', (t) async {
    tallScreen(t);
    late HeldSecureWrites held;
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      feeds: _goodFeed(),
      seed: (h) async {
        await _seedNeedsLink();
        held = HeldSecureWrites(h);
      },
    );
    await _checkInDialog(t, freshLink);
    await t.tap(find.byKey(const Key('relinkSave')));
    await t.pump();
    expect(held.writes, 1);

    // Back, as the system sends it: refused while the link is being saved.
    await Navigator.of(t.element(find.byType(AlertDialog))).maybePop();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // The save finishes, closes the dialog itself, and the caller syncs.
    held.release();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.secrets['ics-url.ics-1'], freshLink);
    expect(h.syncs, [SyncTrigger.manual]);
    await h.dispose(t);
  });

  testWidgets('back closes the dialog when nothing is being saved', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      feeds: _goodFeed(),
      seed: (h) => _seedNeedsLink(),
    );
    await _checkInDialog(t, freshLink);

    // The control of the test above: the same Back does close it.
    await Navigator.of(t.element(find.byType(AlertDialog))).maybePop();
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(h.secrets, isEmpty);
    expect(h.syncs, isEmpty);
    await h.dispose(t);
  });

  testWidgets('two quick taps on Save save the link once and sync once', (
    t,
  ) async {
    tallScreen(t);
    late HeldSecureWrites held;
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      feeds: _goodFeed(),
      seed: (h) async {
        await _seedNeedsLink();
        held = HeldSecureWrites(h);
      },
    );
    await _checkInDialog(t, freshLink);

    // Both taps land before a frame: the second finds the button as it was
    // drawn, still on.
    await t.tap(find.byKey(const Key('relinkSave')));
    await t.tap(find.byKey(const Key('relinkSave')));
    held.release();
    await t.pumpAndSettle();

    expect(held.writes, 1);
    expect(h.secrets['ics-url.ics-1'], freshLink);
    expect(h.syncs, [SyncTrigger.manual]);
    expect(find.byType(AlertDialog), findsNothing);
    await h.dispose(t);
  });

  testWidgets(
    'a check answered after the dialog closed changes nothing and does not '
    'throw',
    (t) async {
      tallScreen(t);
      final answer = Completer<http.Response>();
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        feeds: MockClient((_) => answer.future),
        seed: (h) => _seedNeedsLink(),
      );
      await t.tap(find.byKey(const Key('pasteNewLink')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('icsLinkField')), freshLink);
      await t.pump();
      await t.tap(find.byKey(const Key('checkLink')));
      await t.pump();
      expect(find.byKey(const Key('probeChecking')), findsOneWidget);

      // The user gives up while the answer is on its way.
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      answer.complete(http.Response(weekFeed, 200));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(h.secrets, isEmpty);
      expect(h.syncs, isEmpty);
      await h.dispose(t);
    },
  );

  testWidgets(
    're-linking when another sync runs says so and asks for a re-plan',
    (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        feeds: _goodFeed(),
        seed: (h) async {
          await _seedNeedsLink();
          h.syncResult = (trigger) =>
              SyncReport(trigger: trigger, outcome: SyncRunOutcome.busy);
        },
      );

      await _checkInDialog(t, freshLink);
      await t.tap(find.byKey(const Key('relinkSave')));
      await t.pumpAndSettle();

      // Saved all the same; the fetch has to wait for the next sync, and the
      // plan follows the change from the cache.
      expect(h.secrets['ics-url.ics-1'], freshLink);
      expect(h.syncs, [SyncTrigger.manual]);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'Another sync is running. Try again in a minute.',
          ),
        ),
        findsOneWidget,
      );
      expect(h.replans, 1);
      await h.dispose(t);
    },
  );

  testWidgets(
    'switching a source on when another sync runs says so and asks for a '
    're-plan',
    (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/sources/ics-1',
        seed: (h) async {
          await getIt<SourceRepository>().save(icsSource(enabled: false));
          h.syncResult = (trigger) =>
              SyncReport(trigger: trigger, outcome: SyncRunOutcome.busy);
        },
      );

      await t.tap(find.byKey(const Key('enabledSwitch')));
      await t.pumpAndSettle();

      expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isTrue);
      expect(h.syncs, [SyncTrigger.manual]);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'Another sync is running. Try again in a minute.',
          ),
        ),
        findsOneWidget,
      );
      // The switch changes what rings, and the sync that would have planned it
      // did not run.
      expect(h.replans, 1);
      await h.dispose(t);
    },
  );

  testWidgets(
    'a sync that throws after choosing a calendar still asks for a re-plan',
    (t) async {
      tallScreen(t);
      final logs = captureLogs();
      final h = await pumpApp(
        t,
        location: '/sources/device-1',
        seed: (h) async {
          h.deviceCalendars = [phoneCalendar('4', 'Personal')];
          // After a restore: the old phone's calendar id, and events cached
          // from it.
          await getIt<SourceRepository>().save(
            phoneSource(calendarId: '9', enabled: false),
          );
          await getIt<AppSettings>().setSourceSetup(
            'device-1',
            SourceSetup.needsCalendar,
          );
          await getIt<OccurrenceRepository>().replaceForSource('device-1', [
            occ(sourceId: 'device-1'),
          ]);
          // The sync fails before it plans anything.
          h.syncResult = (_) => throw StateError('boom');
        },
      );
      expect(await getIt<OccurrenceRepository>().countForSource('device-1'), 1);

      await t.tap(find.byKey(const Key('chooseCalendar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('calendar-4')));
      await t.pumpAndSettle();

      // The new calendar is saved and the old one's events are gone, but the
      // sync that would have planned from the new one threw. The plan is asked
      // to follow from the cache: otherwise the old calendar's alarms stay
      // armed.
      final source = (await getIt<SourceRepository>().byId('device-1'))!;
      expect(source.deviceCalendarId, '4');
      expect(source.enabled, isTrue);
      expect(await getIt<OccurrenceRepository>().countForSource('device-1'), 0);
      expect(h.syncs, [SyncTrigger.manual]);
      expect(h.replans, 1);
      expect(logs.where((l) => l.contains('Syncing a source failed')), [
        'Syncing a source failed (StateError)',
      ]);
      releaseLogs();
      await h.dispose(t);
    },
  );

  testWidgets('another source id shows that source', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/ics-1',
      seed: (h) async {
        h.secrets['ics-url.ics-1'] = 'https://one.example/a/calendar.ics';
        h.secrets['ics-url.ics-2'] = 'https://two.example/b/calendar.ics';
        await getIt<SourceRepository>().save(icsSource());
        await getIt<SourceRepository>().save(
          icsSource(id: 'ics-2', name: 'Team rota'),
        );
      },
    );
    expect(_inAppBar('Work Outlook'), findsOneWidget);
    expect(find.text('one.example/…/calendar.ics'), findsOneWidget);

    // A Fix notification for another source while this one is open: go_router
    // keeps the page, so the same screen gets another id.
    await h.go(t, '/sources/ics-2');

    expect(_inAppBar('Team rota'), findsOneWidget);
    expect(_inAppBar('Work Outlook'), findsNothing);
    expect(find.text('two.example/…/calendar.ics'), findsOneWidget);
    expect(find.text('one.example/…/calendar.ics'), findsNothing);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('sourceNameField')))
          .controller!
          .text,
      'Team rota',
    );
    await h.dispose(t);
  });
}
