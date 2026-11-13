import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/meeting_occurrence.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/planner/meeting_planner.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/engine_event_recorder.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/agenda/agenda_model.dart';

import '../../core/fixtures.dart';
import '../../core/storage/test_database.dart';

/// A source that answers every fetch with the same meetings.
class _FakeSource implements CalendarSource {
  _FakeSource(this.id, this.occurrences);

  @override
  final String id;
  final List<EventOccurrence> occurrences;

  @override
  Future<SourceResult> fetch(FetchWindow window) async =>
      SourceFetched(occurrences);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // 09:27 on Tuesday 6 Oct 2026 in Johannesburg, which is UTC+2 all year.
  final now = DateTime.utc(2026, 10, 6, 7, 27);

  // Named so that their order by name (feed, phone) is not their rank order
  // (phone, feed).
  const feed = SourceConfig(
    id: 'feed',
    name: 'Acme feed',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.feed',
  );
  const phone = SourceConfig(
    id: 'phone',
    name: 'Phone calendar',
    color: 0xFF5BC489,
    kind: SourceKind.device,
    deviceCalendarId: '7',
  );

  late AppDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;
  late AlertHistoryRepository history;
  late SyncLogRepository syncLog;
  late SettingsRepository settings;
  late AppSettings appSettings;
  late RuleSetLoader ruleSets;
  late AgendaLoader loader;

  /// A Johannesburg wall-clock time in October 2026, as UTC.
  DateTime local(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 10, day, hour - 2, minute);

  RulesEngine rulesEngine() =>
      RulesEngine(zone: johannesburg, clock: () => now);

  /// A meeting of the `feed` source; its title is made from its uid.
  EventOccurrence feedOcc(
    String uid,
    DateTime start, {
    Duration length = const Duration(minutes: 30),
    String? title,
    bool allDay = false,
    String? joinUrl,
  }) => occ(
    sourceId: 'feed',
    uid: uid,
    start: start,
    length: length,
    title: title ?? 'Meeting $uid',
    allDay: allDay,
    joinUrl: joinUrl,
  );

  /// An item built by hand, for the functions that need no database.
  AgendaItem itemOf(EventOccurrence o) => AgendaItem(
    meeting: o,
    resolved: rulesEngine().resolve(o, RuleSet()),
    planned: const [],
    sources: const [],
  );

  Future<void> seed(
    SourceConfig source,
    List<EventOccurrence> occurrences,
  ) async {
    await sources.save(source);
    await cache.replaceForSource(source.id, occurrences);
  }

  setUp(() {
    initZones();
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    history = AlertHistoryRepository(db);
    syncLog = SyncLogRepository(db);
    settings = SettingsRepository(db);
    appSettings = AppSettings(settings);
    ruleSets = RuleSetLoader(
      profiles: ProfileRepository(db),
      rules: RuleRepository(db),
      overrides: OverrideRepository(db),
      settings: settings,
      sources: sources,
    );
    loader = AgendaLoader(
      planner: MeetingPlanner(
        sources: sources,
        occurrences: cache,
        links: MeetingLinkRepository(db),
        history: history,
        settings: settings,
        ruleSets: ruleSets,
        rulesEngine: rulesEngine,
      ),
      statuses: SourceStatusLoader(
        sources: sources,
        syncLog: syncLog,
        appSettings: appSettings,
        clock: () => now,
      ),
      settings: settings,
      appSettings: appSettings,
      zone: () => johannesburg,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  test('the agenda shows the alerts the sync planned', () async {
    const engineChannel = MethodChannel(AlarmEngine.methodChannelName);
    const syncChannel = MethodChannel(SyncPlatform.channelName);
    List<Map<Object?, Object?>>? applied;
    messenger.setMockMethodCallHandler(engineChannel, (call) async {
      switch (call.method) {
        case 'applyPlan':
          applied = ((call.arguments as Map)['alerts'] as List)
              .cast<Map<Object?, Object?>>();
          return {'armed': applied!.length, 'cancelled': 0, 'kept': 0};
        case 'drainEvents':
          return <Object?>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      syncChannel,
      (call) async => call.method == 'acquireLock' ? true : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(engineChannel, null);
      messenger.setMockMethodCallHandler(syncChannel, null);
    });

    // One is under way at 09:27, so its alerts are behind us but the plan
    // still lists them; one is later today and one is six days ahead.
    final meetings = [
      feedOcc('underway', local(6, 9), length: const Duration(hours: 1)),
      feedOcc('afternoon', local(6, 15)),
      feedOcc('monday', local(12, 9)),
    ];
    await sources.save(feed);
    final engine = AlarmEngine();
    final service = SyncService(
      sources: sources,
      occurrences: cache,
      links: MeetingLinkRepository(db),
      history: history,
      syncLog: syncLog,
      settings: settings,
      ruleSets: ruleSets,
      rulesEngine: rulesEngine,
      engine: engine,
      recorder: EngineEventRecorder(
        engine: engine,
        history: history,
        occurrences: cache,
      ),
      platform: SyncPlatform(),
      buildSource: (config, state, location) =>
          _FakeSource(config.id, meetings),
      zone: () => johannesburg,
      clock: () => now,
    );

    final report = await service.run(SyncTrigger.manual);
    final snapshot = await loader.load();

    // Three meetings with a heads-up and an alarm each: this is not two empty
    // lists agreeing.
    expect(report.outcome, SyncRunOutcome.ok);
    expect(applied, hasLength(6));
    final armed = {
      for (final a in applied!)
        (
          a['id'] as String,
          a['occurrenceKey'] as String,
          a['fireAtUtcMs'] as int,
        ),
    };
    final shown = {
      for (final day in snapshot.days)
        for (final item in day.items)
          for (final a in item.planned)
            (a.id, a.occurrenceKey, a.fireAtUtc.millisecondsSinceEpoch),
    };
    expect(shown, armed);
    // Each alert once: a set would hide a repeat.
    expect(
      snapshot.days.expand((d) => d.items).expand((i) => i.planned),
      hasLength(6),
    );
    expect(snapshot.days.map((d) => d.title), ['Today', 'Mon 12 Oct']);
    for (final day in snapshot.days) {
      for (final item in day.items) {
        expect(item.planned.map((a) => a.occurrenceKey).toSet(), {
          item.meeting.key,
        });
      }
    }
  });

  test(
    'a merged meeting appears once with both sources, time source first',
    () async {
      await seed(feed, [occ(sourceId: 'feed', uid: 'F1')]);
      await seed(phone, [occ(sourceId: 'phone', uid: '42')]);

      final snapshot = await loader.load();

      final item = snapshot.days.single.items.single;
      final meeting = item.meeting as MeetingOccurrence;
      expect(meeting.copies, hasLength(2));
      expect(meeting.timeSourceId, 'phone');
      expect(item.sources.map((s) => s.id), ['phone', 'feed']);
      expect(item.planned, hasLength(2));
      expect(item.planned.map((a) => a.occurrenceKey).toSet(), {meeting.key});
      expect(snapshot.upcoming, hasLength(1));
    },
  );

  test(
    'meetings group into Today, Tomorrow, then weekday dates, all-day first',
    () {
      final allDay = feedOcc(
        'all-day',
        local(6, 0),
        length: const Duration(hours: 24),
        allDay: true,
      );
      final early = feedOcc('early', local(6, 8, 30));
      final late = feedOcc('late', local(6, 10));
      final tomorrow = feedOcc('tomorrow', local(7, 9));
      final thursday = feedOcc('thursday', local(8, 14));
      // Nothing on Friday, so the list jumps from Thursday to Saturday.
      final saturday = feedOcc('saturday', local(10, 9));

      final days = groupByDay(
        [
          for (final o in [saturday, thursday, tomorrow, late, early, allDay])
            itemOf(o),
        ],
        now: now,
        zone: johannesburg,
      );

      expect(days.map((d) => d.title), [
        'Today',
        'Tomorrow',
        'Thu 8 Oct',
        'Sat 10 Oct',
      ]);
      expect(days.map((d) => d.label), [
        'TUE 6 OCT',
        'WED 7 OCT',
        'THU 8 OCT',
        'SAT 10 OCT',
      ]);
      expect(days.map((d) => d.date), [
        LocalDate(2026, 10, 6),
        LocalDate(2026, 10, 7),
        LocalDate(2026, 10, 8),
        LocalDate(2026, 10, 10),
      ]);
      expect(days.map((d) => d.items.map((i) => i.meeting.uid).toList()), [
        ['all-day', 'early', 'late'],
        ['tomorrow'],
        ['thursday'],
        ['saturday'],
      ]);

      // With nothing today, Today still leads the list and stays empty.
      final later = groupByDay(
        [itemOf(tomorrow), itemOf(saturday)],
        now: now,
        zone: johannesburg,
      );
      expect(later.map((d) => d.title), ['Today', 'Tomorrow', 'Sat 10 Oct']);
      expect(later.first.items, isEmpty);
    },
  );

  test("today's empty list still yields a Today day", () async {
    final days = groupByDay(const [], now: now, zone: johannesburg);
    expect(days.map((d) => d.title), ['Today']);
    expect(days.single.items, isEmpty);

    // The same through the loader, with nothing set up.
    final snapshot = await loader.load();
    expect(snapshot.days.map((d) => d.title), ['Today']);
    expect(snapshot.days.single.label, 'TUE 6 OCT');
    expect(snapshot.days.single.items, isEmpty);
    expect(snapshot.next, isNull);
    expect(snapshot.nextItem, isNull);
    expect(snapshot.upcoming, isEmpty);
    expect(snapshot.quiet, const QuietNone());
  });

  test(
    'past meetings are marked past; the next alert is the first future one',
    () async {
      final standup = feedOcc(
        'standup',
        local(6, 8, 45),
        length: const Duration(minutes: 15),
        title: 'Standup',
      );
      final sprint = feedOcc('sprint', local(6, 10), title: 'Sprint planning');
      await seed(feed, [standup, sprint]);

      final snapshot = await loader.load();

      final items = {
        for (final i in snapshot.days.single.items) i.meeting.uid: i,
      };
      expect(items['standup']!.isPast(now), isTrue);
      expect(items['sprint']!.isPast(now), isFalse);
      // The standup ended at 09:00, so the plan has dropped its alerts.
      expect(items['standup']!.planned, isEmpty);
      expect(snapshot.next!.offsetMinutes, 10);
      expect(snapshot.next!.fireAtUtc, local(6, 9, 50));
      expect(snapshot.nextItem, same(items['sprint']));
    },
  );

  test('a dismissed heads-up is dimmed; the alarm is not', () async {
    final sprint = feedOcc('sprint', local(6, 10));
    await seed(feed, [sprint]);

    var item = (await loader.load()).days.single.items.single;
    expect(item.planned.map((a) => a.offsetMinutes), [10, 1]);
    expect(item.dimmedOffsets(now), isEmpty);

    await history.record(
      AlertHistoryEntry(
        type: AlertEventType.dismissed,
        alertId: PlannedAlert.idFor(sprint.key, 10),
        occurrenceKey: sprint.key,
        startUtc: sprint.startUtc,
        atUtc: local(6, 9, 20),
      ),
    );

    item = (await loader.load()).days.single.items.single;
    expect(item.planned.map((a) => a.offsetMinutes), [1]);
    expect(item.dimmedOffsets(now), {10});
    expect(item.on, isTrue); // the alarm still rings
  });

  test(
    'the sync line counts enabled sources and reports the newest success',
    () async {
      const retired = SourceConfig(
        id: 'retired',
        name: 'Retired calendar',
        color: blue,
        kind: SourceKind.device,
        deviceCalendarId: '9',
        enabled: false,
      );
      await sources.save(feed);
      await sources.save(phone);
      await sources.save(retired);
      final fourMinutesAgo = now.subtract(const Duration(minutes: 4));
      await sources.updateSyncState(
        'feed',
        SourceSyncState(
          lastAttemptUtc: fourMinutesAgo,
          lastSuccessUtc: fourMinutesAgo,
        ),
      );
      await sources.updateSyncState(
        'phone',
        SourceSyncState(
          lastAttemptUtc: now.subtract(const Duration(minutes: 20)),
          lastSuccessUtc: now.subtract(const Duration(minutes: 20)),
        ),
      );
      // A source that is off does not count, however recent its success.
      await sources.updateSyncState(
        'retired',
        SourceSyncState(
          lastSuccessUtc: now.subtract(const Duration(minutes: 1)),
        ),
      );

      final sync = (await loader.load()).sync;

      expect(sync.sourceCount, 2);
      expect(sync.lastSyncedUtc, fourMinutesAgo);
      expect(sync.problems, isEmpty);
      expect(sync.stale, isFalse);
    },
  );

  test('a stale ICS source marks the snapshot stale', () async {
    final anHourAgo = now.subtract(const Duration(minutes: 61));
    final old = SourceSyncState(
      lastAttemptUtc: anHourAgo,
      lastSuccessUtc: anHourAgo,
    );

    // Only feeds go stale: the phone calendar is as old but is not stale.
    await sources.save(phone);
    await sources.updateSyncState('phone', old);
    expect((await loader.load()).sync.stale, isFalse);

    await sources.save(feed);
    await sources.updateSyncState('feed', old);
    final sync = (await loader.load()).sync;
    expect(sync.stale, isTrue);
    // Stale has its own banner; it is not a source with a problem.
    expect(sync.problems, isEmpty);
  });

  test('a red source is listed as a problem', () async {
    await sources.save(feed);
    await sources.updateSyncState(
      'feed',
      SourceSyncState(
        lastAttemptUtc: now.subtract(const Duration(minutes: 4)),
        lastSuccessUtc: now.subtract(const Duration(days: 2)),
        lastError: 'The link no longer works (HTTP 404).',
      ),
    );
    await syncLog.add(
      SyncLogEntry(
        sourceId: 'feed',
        atUtc: now.subtract(const Duration(minutes: 4)),
        outcome: SyncOutcome.httpError,
        message: 'The link no longer works (HTTP 404).',
      ),
    );

    final sync = (await loader.load()).sync;

    expect(sync.problems.map((p) => (p.config.id, p.health, p.line)), [
      ('feed', SourceHealth.error, 'The link no longer works (HTTP 404).'),
    ]);
    expect(sync.stale, isFalse);
  });

  test('enabledToWrite writes only when the wish differs from the natural '
      'state', () {
    expect(enabledToWrite(wantOn: true, naturalOn: true), isNull);
    expect(enabledToWrite(wantOn: true, naturalOn: false), isTrue);
    expect(enabledToWrite(wantOn: false, naturalOn: true), isFalse);
    expect(enabledToWrite(wantOn: false, naturalOn: false), isNull);
  });

  test(
    'restorePending and hasSources come from settings and sources',
    () async {
      var snapshot = await loader.load();
      expect(snapshot.hasSources, isFalse);
      expect(snapshot.restorePending, isFalse);

      // A source that is off still counts as a source: the Agenda then explains
      // itself instead of asking for a first calendar.
      await sources.save(feed.copyWith(enabled: false));
      await appSettings.setRestorePending(true);
      snapshot = await loader.load();
      expect(snapshot.hasSources, isTrue);
      expect(snapshot.restorePending, isTrue);
      expect(snapshot.sync.sourceCount, 0);

      await appSettings.setRestorePending(false);
      expect((await loader.load()).restorePending, isFalse);
    },
  );

  // Tests beyond the plan's list start here.

  test('alerts that already passed are dimmed and never the next alert', () async {
    // 09:00 to 10:00 is under way at 09:27: its heads-up and alarm are behind
    // us, but the plan keeps them until the meeting ends.
    final standup = feedOcc(
      'standup',
      local(6, 8, 45),
      length: const Duration(minutes: 15),
    );
    final underway = feedOcc(
      'underway',
      local(6, 9),
      length: const Duration(hours: 1),
    );
    final later = feedOcc('later', local(6, 10));
    await seed(feed, [standup, underway, later]);

    final snapshot = await loader.load();

    final items = {
      for (final i in snapshot.days.single.items) i.meeting.uid: i,
    };
    expect(items['underway']!.planned.map((a) => a.offsetMinutes), [10, 1]);
    expect(items['underway']!.dimmedOffsets(now), {10, 1});
    expect(items['later']!.dimmedOffsets(now), isEmpty);
    expect(snapshot.next!.occurrenceKey, later.key);
    expect(snapshot.next!.fireAtUtc, local(6, 9, 50));
    expect(snapshot.nextItem, same(items['later']));
    // Upcoming is every meeting that has not ended, the one under way included.
    expect(
      snapshot.upcoming.map((i) => i.meeting.uid),
      unorderedEquals(['underway', 'later']),
    );
  });

  test('only a meeting that has not started shows its switch', () async {
    // At 09:27: the standup has ended, the 09:00 meeting is under way with
    // both its alerts rung, and the 10:00 sprint planning is still ahead.
    final standup = feedOcc(
      'standup',
      local(6, 8, 45),
      length: const Duration(minutes: 15),
    );
    final underway = feedOcc(
      'underway',
      local(6, 9),
      length: const Duration(hours: 1),
    );
    final later = feedOcc('later', local(6, 10));
    final atNow = feedOcc('atNow', now);
    await seed(feed, [standup, underway, later, atNow]);

    final items = {
      for (final i in (await loader.load()).days.single.items) i.meeting.uid: i,
    };
    expect(items['standup']!.showsToggle(now), isFalse);
    expect(items['underway']!.showsToggle(now), isFalse);
    expect(items['atNow']!.showsToggle(now), isFalse);
    expect(items['later']!.showsToggle(now), isTrue);
    final justBefore = local(6, 10).subtract(const Duration(seconds: 1));
    expect(items['later']!.showsToggle(justBefore), isTrue);
    expect(items['later']!.showsToggle(local(6, 10)), isFalse);
  });

  test(
    'a quiet mode turns an item off and the snapshot carries the mode',
    () async {
      final sprint = feedOcc('sprint', local(6, 10));
      await seed(feed, [sprint]);
      final until = DateTime.utc(2026, 10, 7, 5); // 07:00 tomorrow
      await settings.setQuietState(MuteToday(until));

      final snapshot = await loader.load();

      expect(snapshot.quiet, MuteToday(until));
      final item = snapshot.days.single.items.single;
      expect(item.resolved.silenced, isTrue);
      expect(item.on, isFalse);
      expect(item.planned, isEmpty);
      expect(item.dimmedOffsets(now), isEmpty);
      expect(snapshot.next, isNull);
    },
  );

  test('the snapshot carries the rules, so the toggle finds the natural '
      'state', () async {
    final sprint = feedOcc('sprint', local(6, 10));
    await seed(feed, [sprint]);
    await OverrideRepository(db).save(
      EventOverride(
        scope: OverrideScope.occurrence,
        target: sprint.key,
        enabled: false,
      ),
    );

    final snapshot = await loader.load();

    // Switched off by hand ...
    final item = snapshot.days.single.items.single;
    expect(item.on, isFalse);
    expect(snapshot.rules.occurrenceOverride(sprint.key)?.enabled, isFalse);
    // ... but on by itself, so switching it back on writes nothing.
    final natural = rulesEngine()
        .resolve(
          item.meeting,
          snapshot.rules.withoutOccurrenceEnabled(item.meeting.lookupKeys),
        )
        .alerts
        .isNotEmpty;
    expect(natural, isTrue);
    expect(enabledToWrite(wantOn: true, naturalOn: natural), isNull);
  });

  test('warning and needs-setup sources are problems; fine and switched-off '
      'ones are not', () async {
    SourceConfig ics(String id, String name, {bool enabled = true}) =>
        SourceConfig(
          id: id,
          name: name,
          color: blue,
          kind: SourceKind.ics,
          secureStorageKey: 'ics-url.$id',
          enabled: enabled,
        );
    // The repository lists sources by name, so these come in this order.
    await sources.save(ics('red', 'A red feed'));
    await sources.save(ics('amber', 'B amber feed'));
    await sources.save(ics('setup', 'C new feed', enabled: false));
    await sources.save(ics('fine', 'D fine feed'));
    await sources.save(ics('off', 'E off feed', enabled: false));
    await appSettings.setSourceSetup('setup', SourceSetup.needsLink);
    final fourMinutesAgo = now.subtract(const Duration(minutes: 4));
    for (final (id, error, outcome) in [
      ('red', 'The link no longer works (HTTP 404).', SyncOutcome.httpError),
      (
        'amber',
        'Could not reach the calendar server.',
        SyncOutcome.networkError,
      ),
    ]) {
      await sources.updateSyncState(
        id,
        SourceSyncState(
          lastAttemptUtc: fourMinutesAgo,
          lastSuccessUtc: now.subtract(const Duration(hours: 5)),
          lastError: error,
        ),
      );
      await syncLog.add(
        SyncLogEntry(
          sourceId: id,
          atUtc: fourMinutesAgo,
          outcome: outcome,
          message: error,
        ),
      );
    }
    await sources.updateSyncState(
      'fine',
      SourceSyncState(
        lastAttemptUtc: fourMinutesAgo,
        lastSuccessUtc: fourMinutesAgo,
      ),
    );

    final sync = (await loader.load()).sync;

    expect(sync.problems.map((p) => (p.config.id, p.health)), [
      ('red', SourceHealth.error),
      ('amber', SourceHealth.warning),
      ('setup', SourceHealth.needsSetup),
    ]);
    expect(sync.sourceCount, 3); // red, amber and fine are on
    expect(sync.stale, isFalse);
  });

  test('a source that never synced leaves the last sync time empty', () async {
    await sources.save(feed);

    final sync = (await loader.load()).sync;

    expect(sync.sourceCount, 1);
    expect(sync.lastSyncedUtc, isNull);
    expect(sync.problems, isEmpty);
    expect(sync.stale, isFalse);
  });

  test('a meeting that began on an earlier day is left out', () {
    // 23:00 to 01:00 is in a window that starts at local midnight, but it
    // began yesterday.
    final overnight = itemOf(
      feedOcc('overnight', local(5, 23), length: const Duration(hours: 2)),
    );

    final days = groupByDay([overnight], now: now, zone: johannesburg);

    expect(days.map((d) => d.title), ['Today']);
    expect(days.single.items, isEmpty);
  });

  test('meetings that start together are ordered by key', () {
    final b = itemOf(feedOcc('b', local(6, 10)));
    final a = itemOf(feedOcc('a', local(6, 10)));

    final days = groupByDay([b, a], now: now, zone: johannesburg);

    expect(days.single.items.map((i) => i.meeting.uid), ['a', 'b']);
  });

  test('a meeting is past from the moment it ends', () {
    // Ends at 09:00 local, which is 07:00 UTC.
    final standup = itemOf(
      feedOcc('standup', local(6, 8, 45), length: const Duration(minutes: 15)),
    );

    expect(standup.isPast(DateTime.utc(2026, 10, 6, 6, 59, 59)), isFalse);
    expect(standup.isPast(DateTime.utc(2026, 10, 6, 7)), isTrue);
    expect(standup.isPast(DateTime.utc(2026, 10, 6, 7, 1)), isTrue);
  });

  test('a meeting with a join link is a Teams meeting', () {
    final teams = feedOcc(
      'teams',
      local(6, 10),
      joinUrl: 'https://teams.microsoft.com/l/meetup-join/abc',
    );

    expect(itemOf(teams).hasTeams, isTrue);
    expect(itemOf(feedOcc('room', local(6, 10))).hasTeams, isFalse);
  });
}
