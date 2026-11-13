import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/health_monitor.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/agenda/agenda_model.dart';
import 'package:tminus/features/agenda/agenda_screen.dart';
import 'package:tminus/features/agenda/agenda_widgets.dart';
import 'package:tminus/features/agenda/event_sheet.dart';
import 'package:tminus/features/common/alert_chips.dart';
import 'package:tminus/features/common/notice_banner.dart';
import 'package:tminus/features/common/status_tone.dart';
import 'package:tminus/features/settings/settings_screen.dart';
import 'package:tminus/features/sources/add_source_screen.dart';

import '../../core/fixtures.dart';
import '../harness.dart';

/// Fails every toggle write, as a database that is locked or full would.
class _FailingOverrides extends OverrideRepository {
  _FailingOverrides(super.db);

  @override
  Future<void> rewriteFor(
    OverrideScope scope,
    List<String> targets,
    EventOverride Function(EventOverride? effective) change,
  ) => Future.error(StateError('could not write https://example.test/a.ics'));
}

/// A loader that throws while [failing] says so.
class _FlakyLoader extends AgendaLoader {
  _FlakyLoader({
    required this.failing,
    required super.planner,
    required super.statuses,
    required super.settings,
    required super.appSettings,
    required super.zone,
    super.clock,
  });

  final bool Function() failing;

  @override
  Future<AgendaSnapshot> load() async {
    if (failing()) {
      throw StateError('could not read https://example.test/secret.ics');
    }
    return super.load();
  }
}

void main() {
  // 09:27 on Tuesday 6 Oct 2026 in Johannesburg (UTC+2 all year): the brief's
  // sample day, with the standup over and the sprint planning 23 min from its
  // heads-up.
  final now = DateTime.utc(2026, 10, 6, 7, 27);
  final fourMinutesAgo = now.subtract(const Duration(minutes: 4));

  const work = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.work',
  );
  const rota = SourceConfig(
    id: 'rota',
    name: 'Team rota',
    color: 0xFF5BC489,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.rota',
  );

  /// A Johannesburg wall-clock time in October 2026, as UTC.
  DateTime local(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 10, day, hour - 2, minute);

  const teams = 'https://teams.microsoft.com/l/meetup-join/abc';
  final standup = occ(
    uid: 'standup',
    title: 'Daily standup',
    start: local(6, 8, 45),
    length: const Duration(minutes: 15),
    joinUrl: teams,
  );
  final sprint = occ(
    uid: 'sprint',
    title: 'Sprint planning',
    start: local(6, 10),
    length: const Duration(hours: 1),
    joinUrl: teams,
    organizer: 'Thandi M.',
  );
  final pieter = occ(
    uid: 'pieter',
    title: '1:1 with Pieter',
    start: local(6, 11),
    length: const Duration(minutes: 30),
    joinUrl: teams,
  );
  final lunch = occ(
    uid: 'lunch',
    title: 'Lunch',
    start: local(6, 12, 30),
    length: const Duration(hours: 1),
  );
  final demo = occ(
    uid: 'demo',
    title: 'Client demo',
    start: local(6, 14),
    length: const Duration(hours: 1),
    location: 'Boardroom 2',
  );
  final talk = occ(
    uid: 'talk',
    title: 'Optional: Tech talk',
    start: local(6, 16),
    length: const Duration(minutes: 30),
    busyStatus: BusyStatus.tentative,
  );
  final holiday = occ(
    uid: 'holiday',
    title: 'Public holiday',
    start: local(7, 0),
    length: const Duration(hours: 24),
    allDay: true,
  );
  final sampleDay = [standup, sprint, pieter, lunch, demo, talk, holiday];

  /// The `work` feed in the cache, with [meetings], synced four minutes ago
  /// unless [state] says otherwise.
  Future<void> seedFeed(
    List<EventOccurrence> meetings, {
    SourceSyncState? state,
  }) async {
    final sources = getIt<SourceRepository>();
    await sources.save(work);
    await sources.updateSyncState(
      'work',
      state ??
          SourceSyncState(
            lastAttemptUtc: fourMinutesAgo,
            lastSuccessUtc: fourMinutesAgo,
          ),
    );
    await getIt<OccurrenceRepository>().replaceForSource('work', meetings);
  }

  /// A tall screen, so that every card of the sample day is built (a list only
  /// builds what is on the screen and a little more).
  void tallScreen(WidgetTester t) {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 2000);
    addTearDown(t.view.reset);
  }

  /// Lets what a write set going finish: the Agenda reloads 100 ms after the
  /// last one. It all runs on the test's fake clock.
  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 150));
    await t.pumpAndSettle();
  }

  /// Lets a navigation happen and its screen show, without waiting for that
  /// screen to go quiet.
  Future<void> navigate(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  /// Where the app is now after a `go`. A pushed route does not change it.
  String where(Harness h) =>
      h.router.routerDelegate.currentConfiguration.uri.path;

  Finder cardOf(EventOccurrence meeting) =>
      find.byKey(Key('agenda-card-${meeting.key}'));

  Finder toggleOf(EventOccurrence meeting) =>
      find.byKey(Key('agenda-toggle-${meeting.key}'));

  Finder inHeader(Finder what) => find.descendant(
    of: find.byKey(const Key('agendaHeader')),
    matching: what,
  );

  /// The colour of the dot before "Synced 4 min ago".
  StatusTone syncTone(WidgetTester t) =>
      t.widget<StatusDot>(inHeader(find.byType(StatusDot))).tone;

  testWidgets('shows each meeting with its time, title, chips and reason', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));

    // The sprint planning, the card the brief draws in full.
    Finder inSprint(Finder what) =>
        find.descendant(of: cardOf(sprint), matching: what);
    expect(cardOf(sprint), findsOneWidget);
    expect(inSprint(find.text('10:00–11:00')), findsOneWidget);
    expect(inSprint(find.text('Sprint planning')), findsOneWidget);
    expect(inSprint(find.text('−10')), findsOneWidget);
    expect(inSprint(find.text('−1')), findsOneWidget);
    expect(inSprint(find.byKey(const Key('headsUpChip'))), findsOneWidget);
    expect(inSprint(find.byKey(const Key('alarmChip'))), findsOneWidget);
    expect(inSprint(find.text('Meeting · default')), findsOneWidget);
    expect(inSprint(find.byType(TeamsBadge)), findsOneWidget);
    expect(t.widget<Switch>(toggleOf(sprint)).value, isTrue);

    // A room instead of Teams, and the Important-style card without a badge.
    Finder inDemo(Finder what) =>
        find.descendant(of: cardOf(demo), matching: what);
    expect(inDemo(find.text('14:00–15:00')), findsOneWidget);
    expect(inDemo(find.text('Boardroom 2')), findsOneWidget);
    expect(inDemo(find.byType(TeamsBadge)), findsNothing);

    // A tentative meeting is Silent: no chips, the toggle off, the reason why.
    Finder inTalk(Finder what) =>
        find.descendant(of: cardOf(talk), matching: what);
    expect(inTalk(find.text('Silent · tentative')), findsOneWidget);
    expect(inTalk(find.byType(AlertChips)), findsNothing);
    expect(t.widget<Switch>(toggleOf(talk)).value, isFalse);

    // An all-day event has no time range, and belongs to tomorrow.
    expect(
      find.descendant(of: cardOf(holiday), matching: find.text('All day')),
      findsOneWidget,
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('TUE 6 OCT'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('WED 7 OCT'), findsOneWidget);

    // All fine: no banner and no stale chip.
    expect(find.byType(NoticeBanner), findsNothing);
    expect(find.byKey(const Key('feedStaleChip')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('the header counts down to the next alert', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));

    expect(inHeader(find.text('NEXT ALARM IN')), findsOneWidget);
    expect(inHeader(find.text('23')), findsOneWidget);
    expect(inHeader(find.text('min')), findsOneWidget);
    expect(inHeader(find.text('Sprint planning')), findsOneWidget);
    expect(inHeader(find.text('heads-up 09:50')), findsOneWidget);
    expect(inHeader(find.text('Synced 4 min ago · 1 source')), findsOneWidget);
    expect(syncTone(t), StatusTone.ok);
    await h.dispose(t);
  });

  testWidgets('the header names an alarm as an alarm', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) async {
        await seedFeed(sampleDay);
        // Quick has only the alarm, one minute before: 09:59.
        await getIt<OverrideRepository>().save(
          EventOverride(
            scope: OverrideScope.occurrence,
            target: sprint.key,
            profileId: 'quick',
          ),
        );
      },
    );

    expect(inHeader(find.text('32')), findsOneWidget);
    expect(inHeader(find.text('min')), findsOneWidget);
    expect(inHeader(find.text('alarm 09:59')), findsOneWidget);
    expect(inHeader(find.text('heads-up 09:50')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a meeting that has started has no switch; a later one does', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));

    // The standup started (and ended) before 09:27; everything it had has
    // rung, so there is nothing left to switch.
    expect(cardOf(standup), findsOneWidget);
    expect(toggleOf(standup), findsNothing);
    expect(toggleOf(sprint), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the past standup is dimmed and the now line sits after it', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));

    // The standup ended at 09:00; its card fades, the sprint planning's does
    // not.
    final faded = t.widget<Opacity>(
      find.byKey(ValueKey('agenda-past-${standup.key}')),
    );
    expect(faded.opacity, lessThan(0.6));
    expect(faded.opacity, greaterThan(0.2));
    expect(find.byKey(ValueKey('agenda-past-${sprint.key}')), findsNothing);

    final line = find.byKey(const Key('nowLine'));
    expect(
      find.descendant(of: line, matching: find.text('NOW 09:27')),
      findsOneWidget,
    );
    expect(t.getTopLeft(cardOf(standup)).dy, lessThan(t.getTopLeft(line).dy));
    expect(t.getTopLeft(line).dy, lessThan(t.getTopLeft(cardOf(sprint)).dy));
    await h.dispose(t);
  });

  testWidgets('an empty day says No meetings. Enjoy', (t) async {
    tallScreen(t);
    // Nothing today; the only meeting is the standup tomorrow.
    final tomorrowsStandup = occ(
      uid: 'standup-2',
      title: 'Daily standup',
      start: local(7, 8, 45),
      length: const Duration(minutes: 15),
    );
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) => seedFeed([tomorrowsStandup]),
    );

    final empty = find.byKey(const Key('emptyDay'));
    expect(empty, findsOneWidget);
    expect(
      find.descendant(of: empty, matching: find.text('No meetings. Enjoy')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: empty,
        matching: find.text('Nothing will ring today.'),
      ),
      findsOneWidget,
    );
    // Nothing is over or to come today, so there is no line to draw.
    expect(find.byKey(const Key('nowLine')), findsNothing);
    // The next alert is tomorrow's, 23 h 08 away.
    expect(inHeader(find.text('23 h 08')), findsOneWidget);
    expect(cardOf(tomorrowsStandup), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('no sources shows Add a calendar', (t) async {
    final h = await pumpApp(t, now: now);

    expect(find.text('Add a calendar to get started'), findsOneWidget);
    final add = find.widgetWithText(FilledButton, 'Add a calendar');
    expect(add, findsOneWidget);
    expect(find.byKey(const Key('agendaHeader')), findsNothing);

    await t.tap(add);
    await navigate(t);

    expect(where(h), '/sources/add');
    expect(find.byType(AddSourceScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a stale feed shows the Feed stale chip', (t) async {
    final anHourAgo = now.subtract(const Duration(minutes: 61));
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) => seedFeed(
        const [],
        state: SourceSyncState(
          lastAttemptUtc: anHourAgo,
          lastSuccessUtc: anHourAgo,
        ),
      ),
    );

    final chip = find.byKey(const Key('feedStaleChip'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Feed stale')),
      findsOneWidget,
    );
    expect(inHeader(find.text('Synced 1 h ago · 1 source')), findsOneWidget);
    expect(syncTone(t), StatusTone.warn);
    // A stale feed is not a failing one: no banner.
    expect(find.byType(NoticeBanner), findsNothing);
    await h.dispose(t);
  });

  testWidgets('the quiet banner ends quiet mode', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) async {
        await seedFeed(sampleDay);
        // Until 07:00 tomorrow.
        await getIt<SettingsRepository>().setQuietState(
          MuteToday(DateTime.utc(2026, 10, 7, 5)),
        );
      },
    );
    final banner = find.byKey(const Key('quietBanner'));
    final appBar = find.byType(AppBar);
    Finder inSprint(Finder what) =>
        find.descendant(of: cardOf(sprint), matching: what);

    expect(
      find.descendant(
        of: banner,
        matching: find.text('Muted until tomorrow 07:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.bedtime)),
      findsOneWidget,
    );
    // What the mode does to a meeting: muted, the toggle off, the reason.
    expect(inSprint(find.text('muted')), findsOneWidget);
    expect(inSprint(find.text('Silenced · Mute today')), findsOneWidget);
    expect(inSprint(find.byKey(const Key('alarmChip'))), findsNothing);
    expect(t.widget<Switch>(toggleOf(sprint)).value, isFalse);

    await t.tap(find.descendant(of: banner, matching: find.text('End')));
    await settle(t);

    expect(await getIt<SettingsRepository>().quietState(), const QuietNone());
    expect(h.replans, 1);
    expect(banner, findsNothing);
    expect(
      find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.bedtime_outlined),
      ),
      findsOneWidget,
    );
    expect(inSprint(find.text('muted')), findsNothing);
    expect(inSprint(find.byKey(const Key('alarmChip'))), findsOneWidget);
    expect(t.widget<Switch>(toggleOf(sprint)).value, isTrue);
    await h.dispose(t);
  });

  testWidgets('the health banner shows when the monitor reports a problem', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));
    final banner = find.byKey(const Key('healthBanner'));
    expect(banner, findsNothing);

    h.health = {...healthyEngine(), 'notificationsEnabled': false};
    await getIt<HealthMonitor>().refresh();
    await t.pump();

    expect(
      find.descendant(
        of: banner,
        matching: find.text('Alarms may not ring. Fix in Health'),
      ),
      findsOneWidget,
    );
    expect(t.widget<NoticeBanner>(banner).tone, StatusTone.error);

    // Fixed in the settings: the banner goes.
    h.health = healthyEngine();
    await getIt<HealthMonitor>().refresh();
    await t.pump();
    expect(banner, findsNothing);
    await h.dispose(t);
  });

  testWidgets('pull to refresh runs a pullToRefresh sync and reports a busy '
      'one', (t) async {
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));
    h.syncResult = (trigger) =>
        SyncReport(trigger: trigger, outcome: SyncRunOutcome.busy);

    await t.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await t.pumpAndSettle();

    expect(h.syncs, [SyncTrigger.pullToRefresh]);
    expect(
      find.text('Another sync is running. Try again in a minute.'),
      findsOneWidget,
    );
    expect(h.replans, 0);
    await h.dispose(t);
  });

  testWidgets('tapping a card does not throw', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));

    await t.tap(cardOf(sprint));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(t.takeException(), isNull);
    // The tap opens the event sheet.
    expect(find.byType(EventSheet), findsOneWidget);
    await h.dispose(t);
  });

  // Tests beyond the plan's list start here.

  testWidgets('the toggle writes the override, asks for a re-plan and shows '
      'the new state', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));
    expect(t.widget<Switch>(toggleOf(sprint)).value, isTrue);

    await t.tap(toggleOf(sprint));
    await settle(t);

    expect(await getIt<OverrideRepository>().all(), [
      EventOverride(
        scope: OverrideScope.occurrence,
        target: sprint.key,
        enabled: false,
      ),
    ]);
    expect(h.replans, 1);
    expect(h.syncs, isEmpty); // an edit re-plans; it fetches nothing
    expect(t.widget<Switch>(toggleOf(sprint)).value, isFalse);
    expect(
      find.descendant(
        of: cardOf(sprint),
        matching: find.text('Off · this event'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardOf(sprint),
        matching: find.byKey(const Key('alarmChip')),
      ),
      findsNothing,
    );

    // And back: nothing is left stored.
    await t.tap(toggleOf(sprint));
    await settle(t);

    expect(await getIt<OverrideRepository>().all(), isEmpty);
    expect(t.widget<Switch>(toggleOf(sprint)).value, isTrue);
    await h.dispose(t);
  });

  testWidgets('a toggle that cannot be written says so in fixed words and asks '
      'for no re-plan', (t) async {
    tallScreen(t);
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) async {
        await seedFeed(sampleDay);
        await getIt.unregister<OverrideRepository>();
        getIt.registerSingleton<OverrideRepository>(
          _FailingOverrides(getIt<AppDatabase>()),
        );
      },
    );

    await t.tap(toggleOf(sprint));
    await settle(t);

    expect(find.text('Could not change this event.'), findsOneWidget);
    // Never the error's own words, which could carry a link.
    expect(find.textContaining('example.test'), findsNothing);
    expect(find.textContaining('could not write'), findsNothing);
    expect(h.replans, 0);
    expect(t.widget<Switch>(toggleOf(sprint)).value, isTrue);
    await h.dispose(t);
  });

  testWidgets('days after tomorrow are named by their date, with no label, and '
      'a day without meetings is not listed', (t) async {
    tallScreen(t);
    final retro = occ(uid: 'retro', title: 'Retro', start: local(8, 14));
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) => seedFeed([sprint, retro]),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Thu 8 Oct'), findsOneWidget);
    expect(find.text('THU 8 OCT'), findsNothing);
    // Wednesday has nothing on it.
    expect(find.text('Tomorrow'), findsNothing);
    expect(find.text('Wed 7 Oct'), findsNothing);
    expect(cardOf(retro), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a time zone that was guessed is marked on its card only', (
    t,
  ) async {
    tallScreen(t);
    final guessed = sprint.copyWith(warnings: {OccurrenceWarning.tzFallback});
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) => seedFeed([guessed, pieter]),
    );

    expect(
      find.descendant(
        of: cardOf(guessed),
        matching: find.byTooltip('Time zone guessed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardOf(pieter),
        matching: find.byTooltip('Time zone guessed'),
      ),
      findsNothing,
    );
    await h.dispose(t);
  });

  testWidgets('the now line goes after the all-day events and the meetings '
      'that are over', (t) async {
    tallScreen(t);
    final offsite = occ(
      uid: 'offsite',
      title: 'Offsite',
      start: local(6, 0),
      length: const Duration(hours: 24),
      allDay: true,
    );
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) => seedFeed([offsite, standup, sprint]),
    );

    final line = t.getTopLeft(find.byKey(const Key('nowLine'))).dy;

    // An all-day event is not over until the day is, and it is listed first:
    // the line does not go above it, or above the standup that is over.
    expect(t.getTopLeft(cardOf(offsite)).dy, lessThan(line));
    expect(t.getTopLeft(cardOf(standup)).dy, lessThan(line));
    expect(line, lessThan(t.getTopLeft(cardOf(sprint)).dy));
    await h.dispose(t);
  });

  testWidgets('when everything today is over the now line comes last', (
    t,
  ) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed([standup]));

    final line = find.byKey(const Key('nowLine'));
    expect(line, findsOneWidget);
    expect(t.getTopLeft(cardOf(standup)).dy, lessThan(t.getTopLeft(line).dy));
    expect(find.byKey(const Key('emptyDay')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('an all-day event alone still leaves the day empty', (t) async {
    tallScreen(t);
    final holidayToday = occ(
      uid: 'holiday-today',
      title: 'Public holiday',
      start: local(6, 0),
      length: const Duration(hours: 24),
      allDay: true,
    );
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed([holidayToday]));

    // Mockup 6b: "No meetings — enjoy", with the skipped holiday under it.
    final empty = find.byKey(const Key('emptyDay'));
    expect(empty, findsOneWidget);
    expect(find.byKey(const Key('nowLine')), findsNothing);
    expect(
      t.getTopLeft(empty).dy,
      lessThan(t.getTopLeft(cardOf(holidayToday)).dy),
    );
    expect(
      find.descendant(
        of: cardOf(holidayToday),
        matching: find.text('Silent · all-day'),
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('with nothing to ring the header says so', (t) async {
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(const []));

    expect(inHeader(find.text('No alarms in the next 7 days')), findsOneWidget);
    expect(inHeader(find.text('NEXT ALARM IN')), findsNothing);
    expect(find.byKey(const Key('emptyDay')), findsOneWidget);
    expect(find.text('Nothing will ring today.'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the countdown follows the clock: the Agenda reloads every 30 '
      'seconds', (t) async {
    tallScreen(t);
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));
    expect(inHeader(find.text('23')), findsOneWidget);
    expect(inHeader(find.text('Synced 4 min ago · 1 source')), findsOneWidget);

    // 09:40: the heads-up at 09:50 is 10 minutes away.
    h.now = DateTime.utc(2026, 10, 6, 7, 40);
    await t.pump(const Duration(seconds: 31));

    expect(inHeader(find.text('10')), findsOneWidget);
    expect(inHeader(find.text('23')), findsNothing);
    expect(inHeader(find.text('Synced 17 min ago · 1 source')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('nowLine')),
        matching: find.text('NOW 09:40'),
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('while the first sync runs it says so instead of showing an '
      'empty day', (t) async {
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(const []));
    expect(find.byKey(const Key('emptyDay')), findsOneWidget);

    // The source has never synced. (The bar moves for 30 s, so this test pumps
    // for a set time rather than until things settle.)
    await getIt<SourceRepository>().updateSyncState('work', SourceSyncState());
    await t.pump(const Duration(milliseconds: 150));

    expect(find.text('Syncing your calendar…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('agendaHeader')), findsNothing);
    expect(find.byKey(const Key('emptyDay')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('the first-sync bar stops after 30 seconds, so that the screen '
      'can settle', (t) async {
    final h = await pumpApp(t, now: now, seed: (h) => seedFeed(const []));
    await getIt<SourceRepository>().updateSyncState('work', SourceSyncState());
    await t.pump(const Duration(milliseconds: 150));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await t.pump(FirstSyncView.barLifetime);

    // Still syncing as far as the screen knows, but nothing moves any more.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Syncing your calendar…'), findsOneWidget);
    await t.pumpAndSettle();
    await h.dispose(t);
  });

  testWidgets('a source that failed its first sync gets its banner, not a '
      'spinner that never ends', (t) async {
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) => seedFeed(
        const [],
        state: SourceSyncState(
          lastAttemptUtc: fourMinutesAgo,
          lastError: 'The link no longer works (HTTP 404).',
        ),
      ),
    );

    expect(find.text('Syncing your calendar…'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('problemBanner')),
        matching: find.text(
          'Work Outlook: The link no longer works (HTTP 404).',
        ),
      ),
      findsOneWidget,
    );
    expect(inHeader(find.text('Not synced yet')), findsOneWidget);
    expect(syncTone(t), StatusTone.neutral);
    await h.dispose(t);
  });

  testWidgets('a load that fails says so in fixed words, and Try again loads '
      'it', (t) async {
    tallScreen(t);
    var failing = true;
    final h = await pumpApp(
      t,
      now: now,
      seed: (h) async {
        await seedFeed(sampleDay);
        await getIt.unregister<AgendaLoader>();
        getIt.registerFactory<AgendaLoader>(
          () => _FlakyLoader(
            failing: () => failing,
            planner: getIt(),
            statuses: getIt(),
            settings: getIt(),
            appSettings: getIt(),
            zone: () => johannesburg,
            clock: () => h.now,
          ),
        );
      },
    );

    expect(find.text("Couldn't load the agenda."), findsOneWidget);
    expect(find.textContaining('example.test'), findsNothing);
    expect(find.byKey(const Key('agendaHeader')), findsNothing);

    failing = false;
    await t.tap(find.widgetWithText(FilledButton, 'Try again'));
    await settle(t);

    expect(find.text("Couldn't load the agenda."), findsNothing);
    expect(cardOf(sprint), findsOneWidget);
    await h.dispose(t);
  });

  group('banners', () {
    /// `work` with a failed sync, as a 404 leaves it.
    final broken = SourceSyncState(
      lastAttemptUtc: fourMinutesAgo,
      lastSuccessUtc: now.subtract(const Duration(days: 2)),
      lastError: 'The link no longer works (HTTP 404).',
    );

    testWidgets('one source with a problem is named, and View opens it', (
      t,
    ) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        now: now,
        seed: (h) => seedFeed(sampleDay, state: broken),
      );

      final banner = find.byKey(const Key('problemBanner'));
      expect(
        find.descendant(
          of: banner,
          matching: find.text(
            'Work Outlook: The link no longer works (HTTP 404).',
          ),
        ),
        findsOneWidget,
      );
      expect(t.widget<NoticeBanner>(banner).tone, StatusTone.error);

      await t.tap(find.descendant(of: banner, matching: find.text('View')));
      await navigate(t);

      expect(where(h), '/sources/work');
      await h.dispose(t);
    });

    testWidgets('several sources with problems give a count, in the worst '
        "tone, and View opens the list", (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        now: now,
        seed: (h) async {
          // One amber (the network is down) and one red (a 404).
          await seedFeed(
            sampleDay,
            state: SourceSyncState(
              lastAttemptUtc: fourMinutesAgo,
              lastSuccessUtc: fourMinutesAgo,
              lastError: 'Could not reach the calendar server.',
            ),
          );
          await getIt<SyncLogRepository>().add(
            SyncLogEntry(
              sourceId: 'work',
              atUtc: fourMinutesAgo,
              outcome: SyncOutcome.networkError,
              message: 'Could not reach the calendar server.',
            ),
          );
          await getIt<SourceRepository>().save(rota);
          await getIt<SourceRepository>().updateSyncState('rota', broken);
        },
      );

      final banner = find.byKey(const Key('problemBanner'));
      expect(
        find.descendant(
          of: banner,
          matching: find.text('2 calendars have problems'),
        ),
        findsOneWidget,
      );
      expect(t.widget<NoticeBanner>(banner).tone, StatusTone.error);
      expect(
        inHeader(find.text('Synced 4 min ago · 2 sources')),
        findsOneWidget,
      );
      expect(syncTone(t), StatusTone.error);

      await t.tap(find.descendant(of: banner, matching: find.text('View')));
      await navigate(t);

      expect(where(h), '/sources');
      await h.dispose(t);
    });

    testWidgets('a temporary problem is amber', (t) async {
      final h = await pumpApp(
        t,
        now: now,
        seed: (h) async {
          await seedFeed(
            const [],
            state: SourceSyncState(
              lastAttemptUtc: fourMinutesAgo,
              lastSuccessUtc: fourMinutesAgo,
              lastError: 'Could not reach the calendar server.',
            ),
          );
          await getIt<SyncLogRepository>().add(
            SyncLogEntry(
              sourceId: 'work',
              atUtc: fourMinutesAgo,
              outcome: SyncOutcome.networkError,
              message: 'Could not reach the calendar server.',
            ),
          );
        },
      );

      expect(
        t.widget<NoticeBanner>(find.byKey(const Key('problemBanner'))).tone,
        StatusTone.warn,
      );
      await h.dispose(t);
    });

    testWidgets('a restored backup says so, and Open Sources opens Sources', (
      t,
    ) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        now: now,
        seed: (h) async {
          await seedFeed(sampleDay);
          await getIt<AppSettings>().setRestorePending(true);
        },
      );

      final banner = find.byKey(const Key('restoreBanner'));
      expect(
        find.descendant(
          of: banner,
          matching: find.text('Restored from a backup'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.text(
            'Re-link your calendar feeds and choose your phone calendars.',
          ),
        ),
        findsOneWidget,
      );

      await t.tap(
        find.descendant(of: banner, matching: find.text('Open Sources')),
      );
      await navigate(t);

      expect(where(h), '/sources');
      await h.dispose(t);
    });

    testWidgets('the Fix action of the health banner opens Health', (t) async {
      tallScreen(t);
      final h = await pumpApp(t, now: now, seed: (h) => seedFeed(sampleDay));
      h.health = {...healthyEngine(), 'notificationsEnabled': false};
      await getIt<HealthMonitor>().refresh();
      await t.pump();

      await t.tap(
        find.descendant(
          of: find.byKey(const Key('healthBanner')),
          matching: find.text('Fix'),
        ),
      );
      await navigate(t);

      expect(where(h), '/health');
      await h.dispose(t);
    });

    testWidgets('the banners come in the order restore, Health, sources, '
        'quiet mode', (t) async {
      tallScreen(t);
      final h = await pumpApp(
        t,
        now: now,
        seed: (h) async {
          await seedFeed(sampleDay, state: broken);
          await getIt<AppSettings>().setRestorePending(true);
          await getIt<SettingsRepository>().setQuietState(
            MuteToday(DateTime.utc(2026, 10, 7, 5)),
          );
        },
      );
      h.health = {...healthyEngine(), 'notificationsEnabled': false};
      await getIt<HealthMonitor>().refresh();
      await t.pump();

      final tops = [
        for (final key in [
          'restoreBanner',
          'healthBanner',
          'problemBanner',
          'quietBanner',
        ])
          t.getTopLeft(find.byKey(Key(key))).dy,
      ];

      expect(tops, [...tops]..sort());
      expect(tops.toSet(), hasLength(4));
      // And all of them are above the header.
      expect(
        tops.last,
        lessThan(t.getTopLeft(find.byKey(const Key('agendaHeader'))).dy),
      );
      await h.dispose(t);
    });
  });

  group('app bar', () {
    testWidgets('the moon is outlined until a quiet mode is on', (t) async {
      final h = await pumpApp(t, now: now, seed: (h) => seedFeed(const []));
      final appBar = find.byType(AppBar);

      expect(
        find.descendant(of: appBar, matching: find.text('Agenda')),
        findsOneWidget,
      );
      expect(find.byTooltip('Quiet modes'), findsOneWidget);
      expect(
        find.descendant(
          of: appBar,
          matching: find.byIcon(Icons.bedtime_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: appBar, matching: find.byIcon(Icons.bedtime)),
        findsNothing,
      );

      await getIt<SettingsRepository>().setQuietState(
        MuteToday(DateTime.utc(2026, 10, 7, 5)),
      );
      await settle(t);

      expect(
        find.descendant(of: appBar, matching: find.byIcon(Icons.bedtime)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: appBar,
          matching: find.byIcon(Icons.bedtime_outlined),
        ),
        findsNothing,
      );
      await h.dispose(t);
    });

    testWidgets('the overflow menu opens Settings', (t) async {
      final h = await pumpApp(t, now: now, seed: (h) => seedFeed(const []));

      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      await t.tap(find.text('Settings'));
      await navigate(t);

      // Settings is a top-level route that the menu pushes. It covers the
      // Agenda, which stays alive under it so that Back returns to it. (The
      // router's `uri` does not follow a push: `where(h)` would still say
      // /agenda.)
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(AgendaScreen), findsNothing);
      expect(find.byType(AgendaScreen, skipOffstage: false), findsOneWidget);
      await h.dispose(t);
    });
  });

  group('quietBannerText', () {
    // 09:27 on Tue 6 Oct 2026 in Johannesburg.
    String text(QuietState q) => quietBannerText(q, now, johannesburg);

    test('a mute or a pause says when it ends: today, tomorrow or a date', () {
      expect(
        text(MuteToday(DateTime.utc(2026, 10, 7, 5))),
        'Muted until tomorrow 07:00',
      );
      expect(
        text(MuteToday(DateTime.utc(2026, 10, 6, 12))),
        'Muted until today 14:00',
      );
      expect(
        text(PausedUntil(DateTime.utc(2026, 10, 6, 12))),
        'Paused until today 14:00',
      );
      expect(
        text(PausedUntil(DateTime.utc(2026, 10, 7, 7))),
        'Paused until tomorrow 09:00',
      );
      expect(
        text(PausedUntil(DateTime.utc(2026, 10, 9, 7))),
        'Paused until Fri 9 Oct 09:00',
      );
    });

    test('a vacation says when it starts, and when it ends once it has', () {
      LocalDate day(int d) => LocalDate(2026, 10, d);

      expect(text(Vacation(day(12), day(16))), 'Vacation from Mon 12 Oct');
      // From tomorrow is still to come; from today is under way.
      expect(text(Vacation(day(7), day(9))), 'Vacation from Wed 7 Oct');
      expect(text(Vacation(day(6), day(8))), 'Vacation until Thu 8 Oct');
      expect(text(Vacation(day(4), day(9))), 'Vacation until Fri 9 Oct');
    });

    test('no quiet mode has no text', () {
      expect(text(const QuietNone()), '');
    });
  });
}
