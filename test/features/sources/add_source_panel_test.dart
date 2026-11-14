import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/common/color_palette_picker.dart';
import 'package:tminus/features/common/notice_banner.dart';
import 'package:tminus/features/common/status_tone.dart';
import 'package:tminus/features/sources/add_source_panel.dart';
import 'package:tminus/features/sources/add_source_screen.dart';
import 'package:tminus/features/sources/link_field.dart';
import 'package:tminus/features/sources/source_detail_screen.dart';

import '../harness.dart';
import 'source_test_support.dart';

http.Client _goodFeed() =>
    MockClient((_) async => http.Response(weekFeed, 200));

Finder _linkField() => find.byKey(const Key('icsLinkField'));

/// Types [link] (the result of an earlier check is forgotten by that) and asks
/// for the check.
Future<void> _check(WidgetTester t, String link) async {
  await t.enterText(_linkField(), link);
  await t.pump();
  await t.tap(find.byKey(const Key('checkLink')));
  await t.pumpAndSettle();
}

bool _canAdd(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('addCalendar'))).onPressed !=
    null;

bool _canAddSelected(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('addSelected'))).onPressed !=
    null;

Future<void> _choosePhoneCard(WidgetTester t) async {
  await t.tap(find.text('Use a calendar on this phone'));
  await t.pumpAndSettle();
}

Checkbox _boxOf(WidgetTester t, String calendarId) => t.widget<Checkbox>(
  find.descendant(
    of: find.byKey(Key('calendar-$calendarId')),
    matching: find.byType(Checkbox),
  ),
);

Finder _alreadyAddedIn(String calendarId) => find.descendant(
  of: find.byKey(Key('calendar-$calendarId')),
  matching: find.text('Already added'),
);

/// The panel alone, on a screen of its own, in the app's theme: how onboarding
/// hosts it. Call after `pumpApp`, which sets up the services it uses.
Future<List<SourceConfig>> _hostPanel(
  WidgetTester t, {
  bool onboarding = false,
}) async {
  final added = <SourceConfig>[];
  await t.pumpWidget(
    MaterialApp(
      theme: TMinusTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AddSourcePanel(onboarding: onboarding, onAdded: added.add),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return added;
}

/// Makes `queryDeviceCalendars` fail with [code] and a message that quotes the
/// secret link. The harness puts its own handlers back at the end of the test.
void _failCalendarRead(String code) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(AlarmEngine.methodChannelName),
        (call) async {
          if (call.method == 'queryDeviceCalendars') {
            throw PlatformException(code: code, message: 'read $secretLink');
          }
          return null;
        },
      );
}

void main() {
  testWidgets('an http link shows the insecure warning', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add', feeds: _goodFeed());

    await _check(t, 'http://example.test/c.ics');

    expect(find.byKey(const Key('probeFound')), findsOneWidget);
    expect(find.byKey(const Key('insecureWarning')), findsOneWidget);
    expect(find.text('This link is not encrypted (http)'), findsOneWidget);
    expect(
      find.text(
        'Anyone on your network can read your calendar. Use the https link if '
        'your calendar offers one.',
      ),
      findsOneWidget,
    );
    // Amber, like the rest of a source's sync health (run-log decision 12).
    final banner = find.byKey(const Key('insecureWarning'));
    expect(t.widget<NoticeBanner>(banner).tone, StatusTone.warn);
    final colors = Theme.of(t.element(banner)).extension<TMinusColors>()!;
    final surface = t.widget<Container>(
      find.descendant(of: banner, matching: find.byType(Container)).first,
    );
    expect(
      (surface.decoration! as BoxDecoration).color,
      colors.statusWarnContainer,
    );
    // It is a warning, not a block.
    expect(_canAdd(t), isTrue);

    // An https link has none.
    await _check(t, 'https://example.test/c.ics');
    expect(find.byKey(const Key('probeFound')), findsOneWidget);
    expect(find.byKey(const Key('insecureWarning')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('the calendar picker marks calendars that are already sources', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      seed: (h) async {
        h.deviceCalendars = [
          phoneCalendar('1', 'Work', account: 'me@work.test'),
          phoneCalendar('2', 'Personal', account: 'me@gmail.com'),
          phoneCalendar('3', 'Holidays'),
        ];
        await getIt<SourceRepository>().save(phoneSource(calendarId: '2'));
      },
    );

    // Choosing the phone asks for calendar access first.
    await _choosePhoneCard(t);
    expect(
      h.uiCalls.singleWhere((c) => c.method == 'requestPermission').arguments,
      {'kind': 'calendar'},
    );

    // The one that is a source: ticked, disabled and marked.
    expect(_boxOf(t, '2').value, isTrue);
    expect(_boxOf(t, '2').onChanged, isNull);
    expect(_alreadyAddedIn('2'), findsOneWidget);
    // The others can be chosen.
    for (final id in ['1', '3']) {
      expect(_boxOf(t, id).value, isFalse, reason: id);
      expect(_boxOf(t, id).onChanged, isNotNull, reason: id);
      expect(_alreadyAddedIn(id), findsNothing, reason: id);
    }
    expect(find.text('Already added'), findsOneWidget);
    // The account is in the heading of its group, not under the row. These
    // calendars have no account type, so they are in the Other groups.
    expect(find.text('OTHER · me@gmail.com'), findsOneWidget);

    // A calendar that is a source takes no taps.
    await t.tap(find.byKey(const Key('calendar-2')));
    await t.pump();
    expect(_canAddSelected(t), isFalse);
    await t.tap(find.byKey(const Key('calendar-1')));
    await t.pump();
    expect(_boxOf(t, '1').value, isTrue);
    expect(_canAddSelected(t), isTrue);
    await h.dispose(t);
  });

  testWidgets('calendar access permanently denied offers Open settings', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      seed: (h) async {
        h.ui['requestPermission'] = (_) => 'permanentlyDenied';
        h.deviceCalendars = [phoneCalendar('1', 'Work')];
      },
    );

    await _choosePhoneCard(t);

    expect(
      find.text('Calendar access is off. Turn it on in Settings.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);
    expect(find.byKey(const Key('calendar-1')), findsNothing);

    await t.tap(find.text('Open settings'));
    await t.pumpAndSettle();
    expect(h.uiCalls.map((c) => c.method), contains('openAppDetails'));
    await h.dispose(t);
  });

  // Beyond the plan's list from here on.

  testWidgets('the screen offers both ways and starts on the link', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add');

    expect(find.text('Add a calendar'), findsOneWidget);
    expect(find.text('Paste a calendar link'), findsOneWidget);
    expect(
      find.text('Outlook, Google Calendar or any ICS link'),
      findsOneWidget,
    );
    expect(find.text('Use a calendar on this phone'), findsOneWidget);
    expect(
      find.text('Google, Samsung, Outlook and other accounts'),
      findsOneWidget,
    );
    // The link card is open, with Outlook's path to the link.
    expect(
      find.text(
        'Outlook → Settings → Calendar → Shared calendars → Publish → ICS',
      ),
      findsOneWidget,
    );
    expect(_linkField(), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    // Choosing the other card closes this one.
    await _choosePhoneCard(t);
    expect(_linkField(), findsNothing);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    await t.tap(find.text('Paste a calendar link'));
    await t.pumpAndSettle();
    expect(_linkField(), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a calendar can be added only after its link checked out', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add', feeds: _goodFeed());
    expect(_canAdd(t), isFalse);
    expect(
      t.widget<OutlinedButton>(find.byKey(const Key('checkLink'))).onPressed,
      isNull,
    );

    // Typed, not checked.
    await t.enterText(_linkField(), secretLink);
    await t.pump();
    expect(_canAdd(t), isFalse);
    expect(
      t.widget<OutlinedButton>(find.byKey(const Key('checkLink'))).onPressed,
      isNotNull,
    );

    await t.tap(find.byKey(const Key('checkLink')));
    await t.pumpAndSettle();
    expect(find.text('Found 2 events this week'), findsOneWidget);
    expect(_canAdd(t), isTrue);

    // Changed after the check: the result is forgotten, and so is the button.
    await t.enterText(_linkField(), '$secretLink?x');
    await t.pump();
    expect(find.byKey(const Key('probeFound')), findsNothing);
    expect(_canAdd(t), isFalse);
    await h.dispose(t);
  });

  testWidgets('a link that does not check out says why and cannot be added', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: MockClient((_) async => http.Response('', 404)),
    );

    await _check(t, secretLink);

    expect(find.byKey(const Key('probeFailed')), findsOneWidget);
    expect(
      find.text(
        'Link no longer works (HTTP 404). The calendar may have been '
        'unpublished.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('probeFound')), findsNothing);
    expect(_canAdd(t), isFalse);
    // What the probe says never repeats the link.
    expect(
      find.descendant(
        of: find.byKey(const Key('probeFailed')),
        matching: find.textContaining(secretToken),
      ),
      findsNothing,
    );
    await h.dispose(t);
  });

  testWidgets('a web page link is turned down without a request', (t) async {
    tallScreen(t);
    var requests = 0;
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: MockClient((_) async {
        requests++;
        return http.Response(weekFeed, 200);
      }),
    );

    await _check(
      t,
      'https://outlook.office365.com/owa/calendar/x/calendar.html',
    );

    expect(
      find.text(
        'That is the web page link. Copy the link that ends in .ics instead.',
      ),
      findsOneWidget,
    );
    expect(requests, 0);
    expect(_canAdd(t), isFalse);
    await h.dispose(t);
  });

  testWidgets('typing fetches nothing, and Check fetches once', (t) async {
    tallScreen(t);
    final requested = <Uri>[];
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: MockClient((request) async {
        requested.add(request.url);
        return http.Response(weekFeed, 200);
      }),
    );

    // The half-typed link of a keystroke is not sent anywhere.
    for (final typed in ['h', 'https://', 'https://example.test/c.ics']) {
      await t.enterText(_linkField(), typed);
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(requested, isEmpty);

    await t.tap(find.byKey(const Key('checkLink')));
    await t.pumpAndSettle();
    expect(requested, [Uri.parse('https://example.test/c.ics')]);
    await h.dispose(t);
  });

  testWidgets('Done on the keyboard checks the link', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add', feeds: _goodFeed());

    await t.enterText(_linkField(), secretLink);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(find.text('Found 2 events this week'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the paste button fills the field and fetches nothing', (
    t,
  ) async {
    tallScreen(t);
    final platform = recordPlatformCalls(clipboard: '  $secretLink\n');
    final requested = <Uri>[];
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: MockClient((request) async {
        requested.add(request.url);
        return http.Response(weekFeed, 200);
      }),
    );

    await t.tap(find.byTooltip('Paste'));
    await t.pumpAndSettle();

    // Filled and trimmed, and no request went out: a one-time link would be
    // used up, and an http one would travel in clear before the warning.
    expect(t.widget<TextField>(_linkField()).controller!.text, secretLink);
    expect(requested, isEmpty);
    expect(find.byKey(const Key('probeChecking')), findsNothing);
    expect(find.byKey(const Key('probeFound')), findsNothing);
    expect(
      platform.where((c) => c.method == 'Clipboard.getData'),
      hasLength(1),
    );

    // The user asks for the check: one request.
    await t.tap(find.byKey(const Key('checkLink')));
    await t.pumpAndSettle();
    expect(find.text('Found 2 events this week'), findsOneWidget);
    expect(requested, [Uri.parse(secretLink)]);
    await h.dispose(t);
  });

  testWidgets(
    'adding a link saves the probed link, syncs once and opens the source',
    (t) async {
      tallScreen(t);
      final requested = <Uri>[];
      final h = await pumpApp(
        t,
        location: '/sources/add',
        feeds: MockClient((request) async {
          requested.add(request.url);
          return http.Response(weekFeed, 200);
        }),
      );
      // The name starts as Work Outlook.
      expect(
        t
            .widget<TextField>(find.byKey(const Key('newSourceName')))
            .controller!
            .text,
        'Work Outlook',
      );

      await _check(t, ' $secretLink ');
      await t.enterText(
        find.byKey(const Key('newSourceName')),
        '  Team rota  ',
      );
      await t.pump();
      await t.tap(find.byKey(const Key('addCalendar')));
      await t.pumpAndSettle();

      // One fetch (the check's), of the trimmed link; one source, with that
      // link in secure storage and nowhere else.
      expect(requested, [Uri.parse(secretLink)]);
      final added = (await getIt<SourceRepository>().all()).single;
      expect(added.name, 'Team rota');
      expect(added.kind, SourceKind.ics);
      expect(added.enabled, isTrue);
      expect(added.color, calendarPalette.first);
      expect(added.secureStorageKey, 'ics-url.${added.id}');
      expect(h.secrets, {'ics-url.${added.id}': secretLink});
      // Synced once, then its detail opens, with the link masked.
      expect(h.syncs, [SyncTrigger.manual]);
      expect(pathOf(h), '/sources/${added.id}');
      expect(find.byType(SourceDetailScreen), findsOneWidget);
      expect(find.text(maskedSecretLink), findsOneWidget);
      await h.dispose(t);
    },
  );

  testWidgets('an empty name becomes Work Outlook', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add', feeds: _goodFeed());

    await _check(t, secretLink);
    await t.enterText(find.byKey(const Key('newSourceName')), '   ');
    await t.pump();
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pumpAndSettle();

    expect((await getIt<SourceRepository>().all()).single.name, 'Work Outlook');
    await h.dispose(t);
  });

  testWidgets('a new calendar gets the first colour no source has', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: _goodFeed(),
      seed: (h) => getIt<SourceRepository>().save(
        icsSource(id: 'first', name: 'Aaa', color: calendarPalette[0]),
      ),
    );

    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pumpAndSettle();

    final added = (await getIt<SourceRepository>().all()).singleWhere(
      (s) => s.id != 'first',
    );
    expect(added.color, calendarPalette[1]);
    await h.dispose(t);
  });

  testWidgets('a new calendar that finds another sync running says so', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: _goodFeed(),
      seed: (h) async =>
          h.syncResult = (trigger) =>
              SyncReport(trigger: trigger, outcome: SyncRunOutcome.busy),
    );

    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pumpAndSettle();

    // Added all the same: it is fetched by the next sync, and the plan is
    // asked to follow the add from the cache.
    expect(await getIt<SourceRepository>().all(), hasLength(1));
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Another sync is running. Try again in a minute.'),
      ),
      findsOneWidget,
    );
    expect(h.replans, 1);
    expect(find.byType(SourceDetailScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a sync that fails after the add still adds the calendar', (
    t,
  ) async {
    tallScreen(t);
    final logs = captureLogs();
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: _goodFeed(),
      seed: (h) async =>
          h.syncResult = (_) => throw StateError('boom $secretLink'),
    );

    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pumpAndSettle();

    expect(await getIt<SourceRepository>().all(), hasLength(1));
    expect(find.byType(SourceDetailScreen), findsOneWidget);
    expect(logs.where((l) => l.contains('The sync after adding')), [
      'The sync after adding a calendar failed (StateError)',
    ]);
    expect(logs.join('\n'), isNot(contains(secretToken)));
    releaseLogs();
    await h.dispose(t);
  });

  testWidgets('a calendar that could not be added shows fixed text and keeps '
      'the form', (t) async {
    tallScreen(t);
    final logs = captureLogs();
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: _goodFeed(),
      seed: (h) async {
        // The store refuses to write, and its message quotes the link.
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(secureStorageChannel, (call) async {
              if (call.method == 'write') {
                throw PlatformException(
                  code: 'keystore',
                  message: 'could not store $secretLink',
                );
              }
              return null;
            });
      },
    );

    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Could not add the calendar.'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('could not store'), findsNothing);
    // Nothing was added, nothing was synced, and the button is back.
    expect(await getIt<SourceRepository>().all(), isEmpty);
    expect(h.syncs, isEmpty);
    expect(find.text('Adding…'), findsNothing);
    expect(_canAdd(t), isTrue);
    expect(logs.where((l) => l.contains('Could not add the calendar.')), [
      'Could not add the calendar. (keystore)',
    ]);
    expect(logs.join('\n'), isNot(contains(secretToken)));
    expect(logs.join('\n'), isNot(contains('could not store')));
    releaseLogs();
    await h.dispose(t);
  });

  testWidgets(
    'the whole add flow keeps the link out of the route, the database, the '
    'logs and the snackbars',
    (t) async {
      tallScreen(t);
      final logs = captureLogs();
      final platform = recordPlatformCalls();
      final stopSemantics = watchSemantics(t);
      final h = await pumpApp(t, location: '/sources/add', feeds: _goodFeed());

      await _check(t, secretLink);
      await t.tap(find.byKey(const Key('addCalendar')));
      await t.pumpAndSettle();

      // Secure storage holds it, and is the only place that does.
      expect(h.secrets.values, [secretLink]);
      for (final token in [secretToken, 'outlook.office365.com']) {
        expect(await dumpDatabase(h.db), isNot(contains(token)), reason: token);
        expect(logs.join('\n'), isNot(contains(token)), reason: token);
        for (final call in [...h.uiCalls, ...h.engineCalls, ...h.syncCalls]) {
          expect('${call.arguments}', isNot(contains(token)), reason: token);
        }
      }
      final route = h.router.routerDelegate.currentConfiguration;
      expect(route.uri.toString(), isNot(contains(secretToken)));
      expect(route.extra, isNull);
      // On the screen it is only the mask: the link, in whole or in part, is in
      // no text, no tooltip and no semantics label. Nothing was copied, and
      // nobody was told anything.
      expect(find.text(maskedSecretLink), findsOneWidget);
      for (final token in [secretToken, 'owa/calendar']) {
        expect(
          find.textContaining(token, skipOffstage: false, findRichText: true),
          findsNothing,
          reason: token,
        );
        expect(tooltipText(t), isNot(contains(token)), reason: token);
        expect(semanticsText(t), isNot(contains(token)), reason: token);
      }
      expect(platform.where((c) => c.method == 'Clipboard.setData'), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      stopSemantics();
      releaseLogs();
      await h.dispose(t);
    },
  );

  testWidgets('adding phone calendars adds each ticked one, syncs once and '
      'opens the first', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      seed: (h) async {
        h.deviceCalendars = [
          phoneCalendar('1', 'Work', color: 0xFF6AA0F5),
          phoneCalendar('2', 'Personal'),
          phoneCalendar('3', 'Holidays', color: 0xFFE89A5B),
        ];
      },
    );
    await _choosePhoneCard(t);
    expect(_canAddSelected(t), isFalse);

    await t.tap(find.byKey(const Key('calendar-1')));
    await t.tap(find.byKey(const Key('calendar-3')));
    await t.pump();
    await t.tap(find.byKey(const Key('addSelected')));
    await t.pumpAndSettle();

    // Each ticked calendar is a source, named and coloured as the phone has it.
    final sources = await getIt<SourceRepository>().all();
    expect(
      [
        for (final s in sources)
          (s.name, s.kind, s.deviceCalendarId, s.color, s.enabled),
      ],
      [
        ('Holidays', SourceKind.device, '3', 0xFFE89A5B, true),
        ('Work', SourceKind.device, '1', 0xFF6AA0F5, true),
      ],
    );
    // One sync for both, then the first one's detail.
    expect(h.syncs, [SyncTrigger.manual]);
    final work = sources.singleWhere((s) => s.name == 'Work');
    expect(pathOf(h), '/sources/${work.id}');
    expect(find.byType(SourceDetailScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a phone source that waits for its calendar does not mark that '
      'calendar as added', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      seed: (h) async {
        h.deviceCalendars = [phoneCalendar('2', 'Personal')];
        // After a restore: the old phone's calendar id, which means nothing
        // here (it may be another calendar's id on this phone).
        await getIt<SourceRepository>().save(
          phoneSource(calendarId: '2', enabled: false),
        );
        await getIt<AppSettings>().setSourceSetup(
          'device-1',
          SourceSetup.needsCalendar,
        );
      },
    );

    await _choosePhoneCard(t);

    expect(_boxOf(t, '2').value, isFalse);
    expect(_boxOf(t, '2').onChanged, isNotNull);
    expect(find.text('Already added'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('access that was denied can be asked for again', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/sources/add',
      seed: (h) async {
        h.ui['requestPermission'] = (_) => 'denied';
        h.deviceCalendars = [phoneCalendar('1', 'Work')];
      },
    );

    await _choosePhoneCard(t);

    expect(
      find.text(
        "T-Minus needs calendar access to read this phone's calendars.",
      ),
      findsOneWidget,
    );
    expect(find.text('Open settings'), findsNothing);
    expect(find.byKey(const Key('calendar-1')), findsNothing);

    // This time the user allows it.
    h.ui['requestPermission'] = (_) => 'granted';
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('calendar-1')), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(
      h.uiCalls.where((c) => c.method == 'requestPermission'),
      hasLength(2),
    );
    await h.dispose(t);
  });

  testWidgets('a calendar list the phone refuses reads as access denied', (
    t,
  ) async {
    tallScreen(t);
    final logs = captureLogs();
    final h = await pumpApp(
      t,
      location: '/sources/add',
      seed: (h) async => _failCalendarRead('permission_denied'),
    );

    await _choosePhoneCard(t);

    expect(
      find.text(
        "T-Minus needs calendar access to read this phone's calendars.",
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(
      logs.where((l) => l.contains('Reading the phone calendars failed')),
      ['Reading the phone calendars failed (permission_denied)'],
    );
    expect(logs.join('\n'), isNot(contains(secretToken)));
    releaseLogs();
    await h.dispose(t);
  });

  testWidgets('a calendar list that cannot be read says so and logs the code '
      'only', (t) async {
    tallScreen(t);
    final logs = captureLogs();
    final h = await pumpApp(
      t,
      location: '/sources/add',
      seed: (h) async => _failCalendarRead('boom'),
    );

    await _choosePhoneCard(t);

    expect(find.text("Could not read this phone's calendars."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(
      logs.where((l) => l.contains('Reading the phone calendars failed')),
      ['Reading the phone calendars failed (boom)'],
    );
    expect(logs.join('\n'), isNot(contains(secretToken)));
    releaseLogs();
    await h.dispose(t);
  });

  testWidgets('a phone with no calendars says so', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add');

    await _choosePhoneCard(t);

    expect(find.text('No calendars found on this phone.'), findsOneWidget);
    expect(find.byKey(const Key('addSelected')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('in onboarding the panel stays, says what was added and is '
      'ready for another', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, feeds: _goodFeed());
    final added = await _hostPanel(t, onboarding: true);

    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pumpAndSettle();

    // onAdded got the source, after its sync.
    expect([for (final s in added) s.name], ['Work Outlook']);
    expect(h.syncs, [SyncTrigger.manual]);
    expect(
      t.widget<Text>(find.byKey(const Key('addedNote'))).data,
      'Added Work Outlook. You can add another calendar, or continue.',
    );
    // The panel is blank again: the link is not left on a screen that stays.
    expect(t.widget<TextField>(_linkField()).controller!.text, isEmpty);
    expect(find.byKey(const Key('probeFound')), findsNothing);
    expect(_canAdd(t), isFalse);
    expect(
      find.textContaining(secretToken, skipOffstage: false, findRichText: true),
      findsNothing,
    );
    expect(
      t
          .widget<TextField>(find.byKey(const Key('newSourceName')))
          .controller!
          .text,
      'Work Outlook',
    );
    await h.dispose(t);
  });

  testWidgets('outside onboarding the note is short', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, feeds: _goodFeed());
    await _hostPanel(t);

    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pumpAndSettle();

    expect(
      t.widget<Text>(find.byKey(const Key('addedNote'))).data,
      'Added Work Outlook.',
    );
    await h.dispose(t);
  });

  testWidgets('phone calendars that were just added show as added', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      seed: (h) async {
        h.deviceCalendars = [
          phoneCalendar('1', 'Work'),
          phoneCalendar('3', 'Holidays'),
        ];
      },
    );
    final added = await _hostPanel(t, onboarding: true);
    await _choosePhoneCard(t);

    await t.tap(find.byKey(const Key('calendar-1')));
    await t.pump();
    await t.tap(find.byKey(const Key('addSelected')));
    await t.pumpAndSettle();

    expect([for (final s in added) s.deviceCalendarId], ['1']);
    expect(
      t.widget<Text>(find.byKey(const Key('addedNote'))).data,
      'Added Work. You can add another calendar, or continue.',
    );
    // The added one is a source now: ticked, disabled, marked; the other is
    // still free, and nothing is selected.
    expect(_boxOf(t, '1').value, isTrue);
    expect(_boxOf(t, '1').onChanged, isNull);
    expect(_alreadyAddedIn('1'), findsOneWidget);
    expect(_boxOf(t, '3').value, isFalse);
    expect(_canAddSelected(t), isFalse);
    expect(h.syncs, [SyncTrigger.manual]);
    await h.dispose(t);
  });

  testWidgets('the check result never repeats the link', (t) async {
    tallScreen(t);
    const missingLink =
        'https://outlook.office365.com/owa/calendar/s3cr3t/missing.ics';
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: MockClient(
        (request) async => request.url.path.endsWith('missing.ics')
            ? http.Response('', 404)
            : http.Response(weekFeed, 200),
      ),
    );
    // What the result says. The field is left out of the search: it holds the
    // link, as it must.
    Finder inResult(String text) => find.descendant(
      of: find.byType(LinkCheckResult),
      matching: find.textContaining(
        text,
        skipOffstage: false,
        findRichText: true,
      ),
    );

    const results = {
      secretLink: 'probeFound',
      secretHttpLink: 'probeFound',
      missingLink: 'probeFailed',
    };
    for (final MapEntry(key: link, value: shown) in results.entries) {
      await _check(t, link);
      expect(find.byKey(Key(shown)), findsOneWidget, reason: link);
      // The search is not blind: the field does hold the link.
      expect(find.textContaining(secretToken), findsOneWidget, reason: link);
      for (final text in [
        secretToken,
        'outlook.office365.com',
        'owa/calendar',
        'http://',
        'https://',
      ]) {
        expect(inResult(text), findsNothing, reason: '$shown for $link: $text');
      }
    }
    await h.dispose(t);
  });

  testWidgets('back while adding does not leave Add source', (t) async {
    tallScreen(t);
    late HeldSecureWrites held;
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: _goodFeed(),
      seed: (h) async => held = HeldSecureWrites(h),
    );
    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pump();
    expect(held.writes, 1);

    // Back, as the system sends it: refused while the calendar is being saved.
    await Navigator.of(t.element(find.byType(AddSourceScreen))).maybePop();
    await t.pumpAndSettle();
    expect(find.byType(AddSourceScreen), findsOneWidget);

    // The add finishes, and the new source's detail opens.
    held.release();
    await t.pumpAndSettle();
    expect(await getIt<SourceRepository>().all(), hasLength(1));
    expect(find.byType(SourceDetailScreen), findsOneWidget);
    expect(h.syncs, [SyncTrigger.manual]);
    await h.dispose(t);
  });

  testWidgets('back leaves Add source when nothing is being added', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, location: '/sources/add', feeds: _goodFeed());
    await _check(t, secretLink);

    // The control of the test above: the same Back does leave.
    await Navigator.of(t.element(find.byType(AddSourceScreen))).maybePop();
    await t.pumpAndSettle();

    expect(find.byType(AddSourceScreen), findsNothing);
    expect(await getIt<SourceRepository>().all(), isEmpty);
    expect(h.syncs, isEmpty);
    await h.dispose(t);
  });

  testWidgets('two quick taps on Add add one calendar and sync once', (
    t,
  ) async {
    tallScreen(t);
    late HeldSecureWrites held;
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: _goodFeed(),
      seed: (h) async => held = HeldSecureWrites(h),
    );
    await _check(t, secretLink);

    // Both taps land before a frame: the second finds the button as it was
    // drawn, still on.
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.tap(find.byKey(const Key('addCalendar')));
    held.release();
    await t.pumpAndSettle();

    expect(held.writes, 1);
    expect(await getIt<SourceRepository>().all(), hasLength(1));
    expect(h.secrets, hasLength(1));
    expect(h.syncs, [SyncTrigger.manual]);
    await h.dispose(t);
  });

  testWidgets('an edit while Add runs still saves the checked link', (t) async {
    tallScreen(t);
    late HeldSecureWrites held;
    final h = await pumpApp(
      t,
      location: '/sources/add',
      feeds: _goodFeed(),
      seed: (h) async => held = HeldSecureWrites(h),
    );
    await _check(t, secretLink);
    await t.tap(find.byKey(const Key('addCalendar')));
    await t.pump();
    expect(held.writes, 1);

    // The user changes the field while the calendar is being saved.
    await t.enterText(_linkField(), 'https://other.example.test/x.ics');
    await t.pump();
    held.release();
    await t.pumpAndSettle();

    // What was saved is what was checked, not what the field says now.
    expect(h.secrets.values, [secretLink]);
    expect(await getIt<SourceRepository>().all(), hasLength(1));
    await h.dispose(t);
  });

  test('the first colour no source has is the next one', () {
    expect(firstUnusedPaletteColour(const []), calendarPalette[0]);
    expect(firstUnusedPaletteColour([calendarPalette[0]]), calendarPalette[1]);
    expect(
      firstUnusedPaletteColour([calendarPalette[0], calendarPalette[2]]),
      calendarPalette[1],
    );
    // Not the next after the last one used: the first that is free.
    expect(firstUnusedPaletteColour([calendarPalette[1]]), calendarPalette[0]);
    // A phone calendar's own colour is not one of the six.
    expect(
      firstUnusedPaletteColour([0xFF123456, 0xFF654321]),
      calendarPalette[0],
    );
  });

  test('with every colour taken, the one used least comes next', () {
    final used = [
      ...calendarPalette,
      calendarPalette[0],
      calendarPalette[0],
      calendarPalette[1],
    ];
    // Used 3, 2, 1, 1, 1, 1 times: the first of the least used.
    expect(firstUnusedPaletteColour(used), calendarPalette[2]);
  });
}
