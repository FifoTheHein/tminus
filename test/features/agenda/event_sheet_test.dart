import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/replan_scheduler.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/platform/ui_platform.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/features/agenda/agenda_model.dart';
import 'package:tminus/features/agenda/event_sheet.dart';
import 'package:tminus/features/agenda/event_sheet_controller.dart';

import '../../core/fixtures.dart';
import '../../core/storage/test_database.dart';
import '../harness.dart';

// These tests open the sheet from a test host: the first Scaffold of the
// running app. They never go through an Agenda card, which belongs to another
// task, so every finder here looks inside the sheet only.

const _work = SourceConfig(
  id: 'work',
  name: 'Work Outlook',
  color: blue,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.work',
);
const _phone = SourceConfig(
  id: 'phone',
  name: 'Phone calendar',
  color: 0xFF5BC489,
  kind: SourceKind.device,
  deviceCalendarId: '7',
);
const _feed = SourceConfig(
  id: 'feed',
  name: 'Acme feed',
  color: blue,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.feed',
);
const _teams = 'https://teams.microsoft.com/l/meetup-join/abc';

/// An hour-long meeting on 6 Oct 2026, the day of the harness's clock, at
/// [hour]:00 in Johannesburg (UTC+2 all year).
EventOccurrence _meeting(
  String uid, {
  String sourceId = 'work',
  String title = 'Sprint planning',
  int hour = 10,
  String? seriesUid,
  String? joinUrl,
  String? organizer,
  String? location,
}) => occ(
  sourceId: sourceId,
  uid: uid,
  title: title,
  start: DateTime.utc(2026, 10, 6, hour - 2),
  length: const Duration(hours: 1),
  seriesUid: seriesUid,
  joinUrl: joinUrl,
  organizer: organizer,
  location: location,
);

/// A phone copy and a feed copy of one meeting. The planner merges them into a
/// meeting that sits on the phone's key, because a phone ranks before a feed;
/// the feed's key is the copy key.
final _phoneCopy = _meeting('42', sourceId: 'phone');
final _feedCopy = _meeting('F1', sourceId: 'feed');
final _mergedSources = {
  _phone: [_phoneCopy],
  _feed: [_feedCopy],
};

EventOverride _occurrence(
  String target, {
  String? profileId,
  List<AlertSpec>? customAlerts,
  bool? enabled,
}) => EventOverride(
  scope: OverrideScope.occurrence,
  target: target,
  profileId: profileId,
  customAlerts: customAlerts,
  enabled: enabled,
);

EventOverride _series(String target, {String? profileId}) => EventOverride(
  scope: OverrideScope.series,
  target: target,
  profileId: profileId,
);

Future<void> _save(EventOverride o) => getIt<OverrideRepository>().save(o);

Future<EventOverride?> _stored(OverrideScope scope, String target) =>
    getIt<OverrideRepository>().find(scope, target);

/// The Agenda item of the meeting [uid], built by the loader the Agenda uses.
Future<AgendaItem> _itemOf(String uid) async {
  final snapshot = await getIt<AgendaLoader>().load();
  return snapshot.days
      .expand((d) => d.items)
      .singleWhere((i) => i.meeting.uid == uid);
}

/// Opens the sheet over the running app, from the first Scaffold (the shell's,
/// which is on the root navigator) or from [host]. The sheet is not awaited: its
/// future completes when it is closed.
Future<void> _show(
  WidgetTester t,
  AgendaItem item, {
  BuildContext? host,
}) async {
  unawaited(
    showEventSheet(host ?? t.element(find.byType(Scaffold).first), item),
  );
  await t.pumpAndSettle();
  expect(find.byType(EventSheet), findsOneWidget);
}

/// Boots the app on a tall screen, so that the whole sheet is on it, over
/// [sources] and their cached meetings, and builds the item of the meeting
/// [uid]. [seed] runs before the first frame.
Future<({Harness h, AgendaItem item})> _boot(
  WidgetTester t, {
  required Map<SourceConfig, List<EventOccurrence>> sources,
  String uid = 'sprint',
  Future<void> Function(Harness h)? seed,
}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final h = await pumpApp(
    t,
    seed: (h) async {
      for (final entry in sources.entries) {
        await getIt<SourceRepository>().save(entry.key);
        await getIt<OccurrenceRepository>().replaceForSource(
          entry.key.id,
          entry.value,
        );
      }
      await seed?.call(h);
    },
  );
  return (h: h, item: await _itemOf(uid));
}

/// [_boot], then opens the sheet on the item.
Future<({Harness h, AgendaItem item})> _open(
  WidgetTester t, {
  required Map<SourceConfig, List<EventOccurrence>> sources,
  String uid = 'sprint',
  Future<void> Function(Harness h)? seed,
}) async {
  final booted = await _boot(t, sources: sources, uid: uid, seed: seed);
  await _show(t, booted.item);
  return booted;
}

final _sheet = find.byType(EventSheet);

Finder _inSheet(Finder f) => find.descendant(of: _sheet, matching: f);

/// A profile's row in the radio list.
Finder _row(String profileId) =>
    _inSheet(find.byKey(ValueKey('profile-$profileId')));

/// The filled radio of that profile's row.
Finder _checked(String profileId) => find.descendant(
  of: _row(profileId),
  matching: find.byIcon(Icons.radio_button_checked),
);

final _anyChecked = find.descendant(
  of: _sheet,
  matching: find.byIcon(Icons.radio_button_checked),
);
final _resetButton = find.byKey(const Key('resetOverride'));
final _joinButton = find.byKey(const Key('joinButton'));
final _failureBanner = find.byKey(const Key('sheetFailure'));

/// The text of a sheet `Text` with this key.
String? _textOf(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(Key(key))).data;

/// The WHY sentence as the reader sees it, without markers.
String _whySentence(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('whyText'))).textSpan!.toPlainText();

List<ButtonSegment<SheetScope>> _segments(WidgetTester t) => t
    .widget<SegmentedButton<SheetScope>>(
      _inSheet(find.byType(SegmentedButton<SheetScope>)),
    )
    .segments;

/// An override store whose writes fail with an error whose message must never
/// reach the screen or the log.
class _FailingOverrides extends OverrideRepository {
  _FailingOverrides(super.db);

  @override
  Future<void> rewriteFor(
    OverrideScope scope,
    List<String> targets,
    EventOverride Function(EventOverride? effective) change,
  ) => Future.error(StateError('secret detail'));
}

/// Runs [body] with everything the app logs through `debugPrint` collected into
/// the list it is given. The hook goes back before the test body ends, not in a
/// tear-down: the framework checks that it is back before tear-downs run.
Future<void> _logging(Future<void> Function(List<String> logs) body) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
  try {
    await body(logs);
  } finally {
    debugPrint = original;
  }
}

void main() {
  testWidgets(
    'choosing Quick for this occurrence writes the meeting key and asks for a '
    're-plan',
    (t) async {
      final (:h, :item) = await _open(
        t,
        sources: {
          _work: [_meeting('sprint')],
        },
      );
      // What resolution picked is marked until something is chosen.
      expect(_checked('meeting'), findsOneWidget);
      expect(h.replans, 0);

      await t.tap(_row('quick'));
      await t.pumpAndSettle();

      expect(
        await _stored(OverrideScope.occurrence, item.meeting.key),
        _occurrence(item.meeting.key, profileId: 'quick'),
      );
      expect(h.replans, 1);
      expect(_checked('quick'), findsOneWidget);
      expect(_checked('meeting'), findsNothing);
      await h.dispose(t);
    },
  );

  testWidgets('Whole series writes the series uid and is disabled for a '
      'one-off', (t) async {
    final weekly = _meeting('weekly', seriesUid: 'series-1');
    final once = _meeting('once', title: 'One-off review', hour: 14);
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [weekly, once],
      },
      uid: 'weekly',
    );
    expect(_segments(t).map((s) => s.enabled), [true, true]);

    await t.tap(_inSheet(find.text('Whole series')));
    await t.pumpAndSettle();
    expect(
      _inSheet(find.text('Customise for the whole series')),
      findsOneWidget,
    );

    await t.tap(_row('important'));
    await t.pumpAndSettle();

    expect(
      await _stored(OverrideScope.series, 'series-1'),
      _series('series-1', profileId: 'important'),
    );
    expect(await _stored(OverrideScope.occurrence, item.meeting.key), isNull);
    expect(h.replans, 1);

    // A one-off has no series to switch to.
    Navigator.of(t.element(_sheet)).pop();
    await t.pumpAndSettle();
    await _show(t, await _itemOf('once'));
    expect(_segments(t).map((s) => s.enabled), [true, false]);
    await t.tap(_inSheet(find.text('Whole series')));
    await t.pumpAndSettle();
    expect(_inSheet(find.text('Customise for this event')), findsOneWidget);
    expect(_inSheet(find.text('Customise for the whole series')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('reset clears the profile on every lookup key and keeps the '
      'toggle', (t) async {
    final (:h, :item) = await _open(
      t,
      sources: _mergedSources,
      uid: '42',
      seed: (h) async {
        // The meeting key holds a profile and the toggle, the copy key another
        // profile.
        await _save(
          _occurrence(_phoneCopy.key, profileId: 'important', enabled: false),
        );
        await _save(_occurrence(_feedCopy.key, profileId: 'quick'));
      },
    );
    expect(item.meeting.lookupKeys, [_phoneCopy.key, _feedCopy.key]);
    expect(_checked('important'), findsOneWidget);
    expect(_resetButton, findsOneWidget);

    await t.tap(_resetButton);
    await t.pumpAndSettle();

    expect(
      await _stored(OverrideScope.occurrence, _phoneCopy.key),
      _occurrence(_phoneCopy.key, enabled: false),
    );
    expect(await _stored(OverrideScope.occurrence, _feedCopy.key), isNull);
    expect(h.replans, 1);
    expect(_resetButton, findsNothing);
    await h.dispose(t);
  });

  testWidgets('choosing a profile keeps an enabled:false that sat on a copy '
      'key', (t) async {
    final (:h, :item) = await _open(
      t,
      sources: _mergedSources,
      uid: '42',
      seed: (h) async => _save(_occurrence(_feedCopy.key, enabled: false)),
    );
    expect(item.meeting.key, _phoneCopy.key);
    // Switched off by hand, so resolution picked Silent.
    expect(_checked('silent'), findsOneWidget);

    await t.tap(_row('quick'));
    await t.pumpAndSettle();

    // It moved to the meeting key, with the new profile.
    expect(
      await _stored(OverrideScope.occurrence, _phoneCopy.key),
      _occurrence(_phoneCopy.key, profileId: 'quick', enabled: false),
    );
    expect(await _stored(OverrideScope.occurrence, _feedCopy.key), isNull);
    expect(_checked('quick'), findsOneWidget);
    expect(h.replans, 1);
    await h.dispose(t);
  });

  testWidgets('a merged meeting lists both sources, time source first', (
    t,
  ) async {
    final (:h, :item) = await _open(t, sources: _mergedSources, uid: '42');

    expect(item.sources.map((s) => s.id), ['phone', 'feed']);
    expect(_textOf(t, 'sheetSource'), 'Phone calendar');
    expect(_textOf(t, 'sheetSources'), 'In: Phone calendar, Acme feed');
    await h.dispose(t);
  });

  testWidgets('Join opens the link through tminus_ui', (t) async {
    final (:h, item: _) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint', joinUrl: _teams)],
      },
      seed: (h) async => h.ui['openUrl'] = (_) => true,
    );

    await t.tap(_joinButton);
    await t.pumpAndSettle();

    expect(
      [
        for (final c in h.uiCalls)
          if (c.method == 'openUrl') c.arguments,
      ],
      [
        {'url': _teams},
      ],
    );
    expect(_failureBanner, findsNothing);
    await h.dispose(t);
  });

  testWidgets('a failed join says so', (t) async {
    // The harness answers `openUrl` with nothing, which is "no app took it".
    final (:h, item: _) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint', joinUrl: _teams)],
      },
    );

    await t.tap(_joinButton);
    await t.pumpAndSettle();

    expect(h.uiCalls.map((c) => c.method), contains('openUrl'));
    expect(_failureBanner, findsOneWidget);
    expect(find.text('Could not open the Teams link.'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('customising saves the edited alert list', (t) async {
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
    );

    await t.tap(find.byKey(const Key('customiseButton')));
    await t.pumpAndSettle();
    // The editor starts from the chosen profile: Meeting, −10 and −1.
    expect(find.byKey(const ValueKey('alert-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('alert-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('alert-2')), findsNothing);

    await t.tap(find.byKey(const Key('addAlert')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('alert-2-offset-15')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customAlertsSave')));
    await t.pumpAndSettle();

    expect(
      await _stored(OverrideScope.occurrence, item.meeting.key),
      _occurrence(
        item.meeting.key,
        customAlerts: const [
          AlertSpec(10, AlertStrength.headsUp),
          AlertSpec(1, AlertStrength.alarm),
          AlertSpec(15, AlertStrength.headsUp),
        ],
      ),
    );
    expect(h.replans, 1);
    // An alert list of its own is the Custom row, and it is the choice.
    expect(_checked('custom'), findsOneWidget);
    await h.dispose(t);
  });

  // Beyond the plan's list.

  testWidgets('the sheet shows the source, title, time, organiser, place and '
      'series of the meeting', (t) async {
    final h = (await _open(
      t,
      sources: {
        _work: [
          _meeting(
            'sprint',
            organizer: 'Thandi M.',
            location: 'Boardroom 2',
            seriesUid: 'weekly',
            joinUrl: _teams,
          ),
        ],
      },
    )).h;

    expect(_textOf(t, 'sheetSource'), 'Work Outlook');
    expect(_textOf(t, 'sheetTitle'), 'Sprint planning');
    // U+00B7 between the day and the times, an en dash between the times.
    expect(_textOf(t, 'sheetTime'), 'Tue 6 Oct · 10:00–11:00');
    expect(_inSheet(find.text('Organiser · Thandi M.')), findsOneWidget);
    expect(_inSheet(find.text('Boardroom 2')), findsOneWidget);
    expect(_inSheet(find.text('Part of a series')), findsOneWidget);
    expect(_inSheet(find.text('Join Teams meeting')), findsOneWidget);
    expect(_inSheet(find.text('Alerts for this event')), findsOneWidget);
    // One source: nothing to list.
    expect(find.byKey(const Key('sheetSources')), findsNothing);
    // The dot is the calendar's colour.
    expect(
      _inSheet(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == const Color(blue),
        ),
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('a one-off meeting with nothing else shows only its source, '
      'title and time', (t) async {
    final h = (await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
    )).h;

    expect(_textOf(t, 'sheetTitle'), 'Sprint planning');
    expect(_textOf(t, 'sheetTime'), 'Tue 6 Oct · 10:00–11:00');
    expect(_joinButton, findsNothing);
    expect(_inSheet(find.text('Part of a series')), findsNothing);
    expect(_inSheet(find.textContaining('Organiser')), findsNothing);
    expect(find.byKey(const Key('sheetSources')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('the WHY card gives the reason from when the sheet opened and '
      'says so after a change', (t) async {
    final h = (await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
    )).h;
    const reason =
        "Using Meeting because no rule matched — it's your default profile.";
    expect(_whySentence(t), reason);
    expect(find.byKey(const Key('whyStale')), findsNothing);
    // Only the profile's name is bold.
    final whyText = t.widget<Text>(find.byKey(const Key('whyText')));
    final spans = (whyText.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(
      [
        for (final s in spans)
          if (s.style?.fontWeight == FontWeight.w600) s.text,
      ],
      ['Meeting'],
    );

    await t.tap(_row('quick'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('whyStale')), findsOneWidget);
    expect(find.text('Updated — close to see the new reason.'), findsOneWidget);
    // The sentence is still the one from when the sheet opened.
    expect(_whySentence(t), reason);
    await h.dispose(t);
  });

  testWidgets('the WHY card names the source whose default decided, not the '
      'time source', (t) async {
    final h = (await _open(
      t,
      sources: {
        _phone: [_phoneCopy],
        _feed.copyWith(defaultProfileId: 'important'): [_feedCopy],
      },
      uid: '42',
    )).h;

    expect(
      _whySentence(t),
      "Using Important — it's the default profile for Acme feed.",
    );
    expect(_checked('important'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a toggle on the meeting key hides a profile on a copy key, as '
      'it does for the rules engine', (t) async {
    final h = (await _open(
      t,
      sources: _mergedSources,
      uid: '42',
      seed: (h) async {
        await _save(_occurrence(_phoneCopy.key, enabled: true));
        await _save(_occurrence(_feedCopy.key, profileId: 'important'));
      },
    )).h;

    // The engine reads the first row only: the profile is never used, so the
    // sheet neither marks it nor offers to reset it.
    expect(_checked('meeting'), findsOneWidget);
    expect(_checked('important'), findsNothing);
    expect(_resetButton, findsNothing);
    await h.dispose(t);
  });

  testWidgets('resetting an override the sheet opened on marks no profile', (
    t,
  ) async {
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
      seed: (h) async =>
          _save(_occurrence(_meeting('sprint').key, profileId: 'important')),
    );
    expect(_checked('important'), findsOneWidget);

    await t.tap(_resetButton);
    await t.pumpAndSettle();

    expect(await _stored(OverrideScope.occurrence, item.meeting.key), isNull);
    expect(h.replans, 1);
    // The profile that was chosen is no longer the one in effect, and the
    // sheet does not resolve again to find the automatic one.
    expect(_anyChecked, findsNothing);
    expect(_resetButton, findsNothing);
    expect(find.byKey(const Key('whyStale')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('resetting a change made in the sheet marks the profile '
      'resolution picked', (t) async {
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
    );
    await t.tap(_row('quick'));
    await t.pumpAndSettle();
    expect(_checked('quick'), findsOneWidget);

    await t.tap(_resetButton);
    await t.pumpAndSettle();

    expect(await _stored(OverrideScope.occurrence, item.meeting.key), isNull);
    expect(_checked('meeting'), findsOneWidget);
    expect(_checked('quick'), findsNothing);
    expect(h.replans, 2);
    await h.dispose(t);
  });

  testWidgets('choosing a profile drops the custom alerts, and a list of its '
      'own is the Custom row', (t) async {
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
      seed: (h) async => _save(
        _occurrence(
          _meeting('sprint').key,
          customAlerts: const [AlertSpec(5, AlertStrength.alarm)],
        ),
      ),
    );
    expect(_checked('custom'), findsOneWidget);
    expect(_resetButton, findsOneWidget);

    await t.tap(_row('quick'));
    await t.pumpAndSettle();

    expect(
      await _stored(OverrideScope.occurrence, item.meeting.key),
      _occurrence(item.meeting.key, profileId: 'quick'),
    );
    expect(_checked('quick'), findsOneWidget);
    expect(_row('custom'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a profile with its own custom list shows as Custom', (t) async {
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
    );
    // Quick, then a list of its own on top of it. The override keeps the
    // profile, for the sound, and the list is what rings.
    await t.tap(_row('quick'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customiseButton')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('addAlert')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customAlertsSave')));
    await t.pumpAndSettle();

    // What is stored is the profile and the list.
    expect(
      await _stored(OverrideScope.occurrence, item.meeting.key),
      _occurrence(
        item.meeting.key,
        profileId: 'quick',
        customAlerts: const [
          AlertSpec(1, AlertStrength.alarm),
          AlertSpec(5, AlertStrength.headsUp),
        ],
      ),
    );
    // The sheet marks the Custom row, with the list that rings. Quick's own row
    // keeps Quick's one alarm and is not marked.
    expect(_checked('custom'), findsOneWidget);
    expect(_checked('quick'), findsNothing);
    Finder chip(String profileId, String key) =>
        find.descendant(of: _row(profileId), matching: find.byKey(Key(key)));
    expect(chip('custom', 'alarmChip'), findsOneWidget);
    expect(chip('custom', 'headsUpChip'), findsOneWidget);
    expect(chip('quick', 'alarmChip'), findsOneWidget);
    expect(chip('quick', 'headsUpChip'), findsNothing);

    // Tapping Quick clears the list again.
    await t.tap(_row('quick'));
    await t.pumpAndSettle();

    expect(
      await _stored(OverrideScope.occurrence, item.meeting.key),
      _occurrence(item.meeting.key, profileId: 'quick'),
    );
    expect(_checked('quick'), findsOneWidget);
    expect(_row('custom'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('Reset to automatic in Whole series clears only the series '
      'override', (t) async {
    final weekly = _meeting('weekly', seriesUid: 'series-1');
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [weekly],
      },
      uid: 'weekly',
      seed: (h) async {
        await _save(_occurrence(weekly.key, profileId: 'quick'));
        await _save(_series('series-1', profileId: 'important'));
      },
    );
    expect(_checked('quick'), findsOneWidget);

    await t.tap(_inSheet(find.text('Whole series')));
    await t.pumpAndSettle();
    expect(_checked('important'), findsOneWidget);

    await t.tap(_resetButton);
    await t.pumpAndSettle();

    expect(await _stored(OverrideScope.series, 'series-1'), isNull);
    expect(
      await _stored(OverrideScope.occurrence, item.meeting.key),
      _occurrence(weekly.key, profileId: 'quick'),
    );
    expect(h.replans, 1);
    expect(_anyChecked, findsNothing);
    await h.dispose(t);
  });

  testWidgets('an empty alert list cannot be saved', (t) async {
    final (:h, :item) = await _open(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
    );
    await t.tap(find.byKey(const Key('customiseButton')));
    await t.pumpAndSettle();

    // Meeting has two alerts; the second one moves up to the first row.
    await t.tap(find.byKey(const ValueKey('alert-0-remove')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('alert-0-remove')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('alert-0')), findsNothing);
    expect(
      t.widget<TextButton>(find.byKey(const Key('customAlertsSave'))).onPressed,
      isNull,
    );
    await t.tap(find.byKey(const Key('customAlertsCancel')));
    await t.pumpAndSettle();
    expect(await _stored(OverrideScope.occurrence, item.meeting.key), isNull);
    expect(h.replans, 0);
    await h.dispose(t);
  });

  testWidgets('a failed write shows fixed text, logs only its type and asks '
      'for no re-plan', (t) async {
    await _logging((logs) async {
      final (:h, :item) = await _open(
        t,
        sources: {
          _work: [_meeting('sprint')],
        },
        seed: (h) async {
          await getIt.unregister<OverrideRepository>();
          getIt.registerLazySingleton<OverrideRepository>(
            () => _FailingOverrides(getIt()),
          );
        },
      );

      await t.tap(_row('quick'));
      await t.pumpAndSettle();

      expect(_failureBanner, findsOneWidget);
      expect(find.text('Could not save the change.'), findsOneWidget);
      expect(find.textContaining('secret detail'), findsNothing);
      expect(logs, contains('Could not save the change. (StateError)'));
      expect(logs.where((l) => l.contains('secret detail')), isEmpty);
      expect(h.replans, 0);
      expect(await _stored(OverrideScope.occurrence, item.meeting.key), isNull);
      await h.dispose(t);
    });
  });

  testWidgets('a join that throws shows the same text, logs only the code, '
      'and a later join clears it', (t) async {
    await _logging((logs) async {
      final h = (await _open(
        t,
        sources: {
          _work: [_meeting('sprint', joinUrl: _teams)],
        },
        seed: (h) async => h.ui['openUrl'] = (_) => throw PlatformException(
          code: 'no_activity',
          message: 'private detail',
        ),
      )).h;

      await t.tap(_joinButton);
      await t.pumpAndSettle();

      expect(find.text('Could not open the Teams link.'), findsOneWidget);
      expect(find.textContaining('private detail'), findsNothing);
      expect(logs, contains('Could not open the Teams link. (no_activity)'));
      expect(logs.where((l) => l.contains('private detail')), isEmpty);

      h.ui['openUrl'] = (_) => true;
      await t.tap(_joinButton);
      await t.pumpAndSettle();
      expect(_failureBanner, findsNothing);
      await h.dispose(t);
    });
  });

  // The host is the Agenda's own Scaffold, which is inside the Agenda tab's
  // navigator. The first Scaffold, the shell's, is already on the root
  // navigator, so opening from it would prove nothing.
  testWidgets('the sheet opens on the root navigator, over the tab bar', (
    t,
  ) async {
    final (:h, :item) = await _boot(
      t,
      sources: {
        _work: [_meeting('sprint')],
      },
    );
    final host = t.element(find.byType(Scaffold).last);
    expect(
      Navigator.of(host),
      isNot(same(Navigator.of(host, rootNavigator: true))),
      reason: 'the host must be inside a tab for this test to mean anything',
    );

    await _show(t, item, host: host);

    final inSheet = t.element(find.byType(EventSheet));
    expect(
      Navigator.of(inSheet),
      same(Navigator.of(inSheet, rootNavigator: true)),
    );
    await h.dispose(t);
  });

  test('a write that finishes after the sheet was closed does not touch the '
      'controller', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final meeting = occ();
    var replans = 0;
    final replan = ReplanScheduler(
      replan: () async => replans++,
      delay: Duration.zero,
    );
    addTearDown(replan.dispose);
    final controller = EventSheetController(
      item: AgendaItem(
        meeting: meeting,
        resolved: RulesEngine(
          zone: johannesburg,
          clock: () => DateTime.utc(2026, 10, 6, 7, 27),
        ).resolve(meeting, RuleSet()),
        planned: const [],
        sources: const [],
      ),
      overrides: OverrideRepository(db),
      profiles: ProfileRepository(db),
      replan: replan,
      ui: UiPlatform(),
    );

    // The sheet is closed while the write is under way.
    final write = controller.chooseProfile(BuiltInProfiles.quickId);
    controller.dispose();
    await write; // a notification after dispose would throw here

    expect(
      await OverrideRepository(db).find(OverrideScope.occurrence, meeting.key),
      _occurrence(meeting.key, profileId: 'quick'),
    );
    await pumpEventQueue();
    expect(replans, 1);
  });
}
