import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/meeting_link.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/sources/ics_feed_source.dart';
import 'package:tminus/core/sources/source_secrets.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
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
import 'package:tminus/core/sync/missed_system.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

class _FakeSource implements CalendarSource {
  _FakeSource(this.id, this._result);
  @override
  final String id;
  final SourceResult Function() _result;
  int fetches = 0;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    fetches++;
    return _result();
  }
}

/// Every source's link, from its id: nothing reaches secure storage.
class _Links extends SourceSecrets {
  @override
  Future<String?> readUrl(String key) async =>
      'https://${key.substring('ics-url.'.length)}.example/c.ics';
}

/// The feed bodies in a map, so a test can see which ones are left.
class _Bodies extends FeedBodyCache {
  _Bodies() : super(() => throw UnsupportedError('kept in memory'));

  final kept = <String, String>{};

  @override
  Future<String?> read(String sourceId) async => kept[sourceId];

  @override
  Future<void> write(String sourceId, String body) async {
    kept[sourceId] = body;
  }

  @override
  Future<void> delete(String sourceId) async {
    kept.remove(sourceId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engineChannel = MethodChannel(AlarmEngine.methodChannelName);
  const syncChannel = MethodChannel(SyncPlatform.channelName);

  // 06:00 UTC on 6 Oct 2026; the work meeting starts at 08:00.
  late DateTime now;
  late AppDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;
  late MeetingLinkRepository links;
  late AlertHistoryRepository history;
  late SyncLogRepository log;
  late SettingsRepository settings;
  late SyncService sync;
  late Map<String, SourceResult Function()> results;
  late Map<String, _FakeSource> built;
  late List<MethodCall> engineCalls;
  late List<MethodCall> syncCalls;
  late List<Map<String, Object?>> queuedEvents;
  late Object? Function(MethodCall) applyAnswer;
  late bool lockFree;
  late String? deviceZone;
  late Map<String, Object?>? quietRequest;

  const work = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.work',
  );
  final meeting = occ(uid: 'm1', title: 'Sprint planning'); // 08:00–08:30

  List<Map<Object?, Object?>> applied() =>
      ((engineCalls.lastWhere((c) => c.method == 'applyPlan').arguments
                  as Map)['alerts']
              as List)
          .cast<Map<Object?, Object?>>();

  List<MethodCall> syncCallsNamed(String method) =>
      syncCalls.where((c) => c.method == method).toList();

  /// A service over the test database and the mocked channels. Unless told
  /// otherwise it plans in Johannesburg and fetches from the shared fake
  /// sources; a null [zone] leaves `SyncService.zone` at its default. It waits
  /// [lockWait] of real time for the sync lock, which a test of the wait itself
  /// widens.
  SyncService newSync({
    RulesEngine Function()? rulesEngine,
    tz.Location Function()? zone,
    SourceBuilder? buildSource,
    Duration lockWait = const Duration(milliseconds: 30),
  }) {
    final engine = AlarmEngine();
    return SyncService(
      sources: sources,
      occurrences: cache,
      links: links,
      history: history,
      syncLog: log,
      settings: settings,
      ruleSets: RuleSetLoader(
        profiles: ProfileRepository(db),
        rules: RuleRepository(db),
        overrides: OverrideRepository(db),
        settings: settings,
        sources: sources,
      ),
      rulesEngine:
          rulesEngine ??
          () => RulesEngine(zone: johannesburg, clock: () => now),
      engine: engine,
      recorder: EngineEventRecorder(
        engine: engine,
        history: history,
        occurrences: cache,
      ),
      platform: SyncPlatform(),
      buildSource:
          buildSource ??
          (config, state, location) =>
              built[config.id] = _FakeSource(config.id, results[config.id]!),
      zone: zone,
      clock: () => now,
      lockWait: lockWait,
      lockPoll: const Duration(milliseconds: 5),
    );
  }

  setUp(() async {
    initZones();
    now = DateTime.utc(2026, 10, 6, 6);
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    links = MeetingLinkRepository(db);
    history = AlertHistoryRepository(db);
    log = SyncLogRepository(db);
    settings = SettingsRepository(db);
    await sources.save(work);
    results = {
      'work': () => SourceFetched([meeting]),
    };
    built = {};
    engineCalls = [];
    syncCalls = [];
    queuedEvents = [];
    lockFree = true;
    deviceZone = null;
    quietRequest = null;
    applyAnswer = (call) => {
      'armed': ((call.arguments as Map)['alerts'] as List).length,
      'cancelled': 0,
      'kept': 0,
    };
    messenger.setMockMethodCallHandler(engineChannel, (call) async {
      engineCalls.add(call);
      return switch (call.method) {
        'applyPlan' => applyAnswer(call),
        'drainEvents' => () {
          final drained = List.of(queuedEvents);
          queuedEvents.clear();
          return drained;
        }(),
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(syncChannel, (call) async {
      syncCalls.add(call);
      return switch (call.method) {
        'acquireLock' => lockFree,
        'deviceZone' => deviceZone,
        'takeQuietRequest' => quietRequest,
        _ => null,
      };
    });
    sync = newSync(zone: () => johannesburg);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(engineChannel, null);
    messenger.setMockMethodCallHandler(syncChannel, null);
    tz.setLocalLocation(tz.UTC);
    await db.close();
  });

  test('a sync caches, plans, applies, schedules and logs', () async {
    final report = await sync.run(SyncTrigger.periodic);

    expect(report.outcome, SyncRunOutcome.ok);
    expect(report.sources.single.outcome, SyncOutcome.success);
    expect(await cache.byKey(meeting.key), meeting);

    // Meeting profile: heads-up 07:50 and alarm 07:59.
    expect(applied().map((a) => a['fireAtUtcMs']), [
      DateTime.utc(2026, 10, 6, 7, 50).millisecondsSinceEpoch,
      DateTime.utc(2026, 10, 6, 7, 59).millisecondsSinceEpoch,
    ]);
    expect(report.applied, const ApplyResult(armed: 2, cancelled: 0, kept: 0));

    final configure = syncCallsNamed('configure').single.arguments as Map;
    expect(configure['watchCalendars'], isFalse);
    expect(configure['preSyncTimesMs'], [
      DateTime.utc(2026, 10, 6, 7, 38).millisecondsSinceEpoch,
    ]);

    final state = (await sources.syncState('work'))!;
    expect(state.lastSuccessUtc, now);
    expect(state.lastError, isNull);
    // Newest first: the whole-run entry is written after the source's.
    expect((await log.recent()).map((e) => (e.sourceId, e.outcome)), [
      (null, SyncOutcome.success),
      ('work', SyncOutcome.success),
    ]);
    expect(await sync.lastFinished(), now);
    expect(syncCallsNamed('acquireLock'), hasLength(1));
    expect(syncCallsNamed('releaseLock'), hasLength(1));
  });

  test(
    'engine events are drained before planning, so a Dismiss all counts',
    () async {
      queuedEvents.add({
        'type': 'dismissedAll',
        'alertId': PlannedAlert.idFor(meeting.key, 10),
        'occurrenceKey': meeting.key,
        'startUtcMs': meeting.startUtc.millisecondsSinceEpoch,
        'atUtcMs': now.millisecondsSinceEpoch,
        'snoozeUntilUtcMs': null,
      });
      await sync.run(SyncTrigger.periodic);
      expect(applied(), isEmpty);
      expect((await history.recent()).single.type, AlertEventType.dismissedAll);
    },
  );

  test('a disabled source is neither fetched nor planned', () async {
    await sync.run(SyncTrigger.periodic);
    await sources.save(work.copyWith(enabled: false));
    built.clear();
    await sync.run(SyncTrigger.periodic);
    expect(built, isEmpty);
    expect(applied(), isEmpty);
  });

  test('a temporary failure keeps the cache and asks for a retry', () async {
    await sync.run(SyncTrigger.periodic);
    final firstSuccess = now;
    now = now.add(const Duration(minutes: 15));
    results['work'] = () => const SourceFailed(
      SyncOutcome.networkError,
      'Could not reach the calendar server.',
    );

    final report = await sync.run(SyncTrigger.periodic);

    expect(report.outcome, SyncRunOutcome.retry);
    expect(await cache.byKey(meeting.key), meeting);
    expect(applied(), hasLength(2));
    final state = (await sources.syncState('work'))!;
    expect(state.lastSuccessUtc, firstSuccess);
    expect(state.lastAttemptUtc, now);
    expect(state.lastError, 'Could not reach the calendar server.');
    expect(syncCallsNamed('postSourceNotice'), isEmpty);
  });

  test(
    'a broken link notifies once, and recovery withdraws the notice',
    () async {
      results['work'] = () => const SourceFailed(
        SyncOutcome.httpError,
        'Link no longer works (HTTP 404).',
      );
      final report = await sync.run(SyncTrigger.periodic);
      await sync.run(SyncTrigger.periodic);

      expect(report.outcome, SyncRunOutcome.ok); // red, but nothing to retry
      final posted = syncCallsNamed('postSourceNotice');
      expect(posted, hasLength(1));
      expect(posted.single.arguments, {
        'kind': 'broken',
        'sourceId': 'work',
        'title': 'Work Outlook feed link stopped working',
        'text': 'Link no longer works (HTTP 404).',
      });

      results['work'] = () => SourceFetched([meeting]);
      await sync.run(SyncTrigger.periodic);
      expect(
        syncCallsNamed('cancelSourceNotice').map((c) => c.arguments),
        anyElement(equals({'kind': 'broken', 'sourceId': 'work'})),
      );
    },
  );

  test('an amber failure between broken and success neither hides nor repeats the notice', () async {
    // Decision 26: the notice is tracked in settings, not read back from
    // the last sync-log row, which would be the amber one here.
    for (final outcome in [
      SyncOutcome.httpError,
      SyncOutcome.networkError,
      SyncOutcome.httpError,
    ]) {
      results['work'] = () => SourceFailed(outcome, 'x');
      await sync.run(SyncTrigger.periodic);
    }
    expect(syncCallsNamed('postSourceNotice'), hasLength(1));

    results['work'] = () => const SourceFailed(SyncOutcome.networkError, 'x');
    await sync.run(SyncTrigger.periodic);
    results['work'] = () => SourceFetched([meeting]);
    syncCalls.clear();
    await sync.run(SyncTrigger.periodic);
    expect(
      syncCallsNamed('cancelSourceNotice').map((c) => c.arguments),
      anyElement(equals({'kind': 'broken', 'sourceId': 'work'})),
    );
    expect(await settings.getString(SyncService.brokenNoticeKey('work')), '');

    // Broken again after recovering: a new notice.
    results['work'] = () => const SourceFailed(SyncOutcome.httpError, 'x');
    await sync.run(SyncTrigger.periodic);
    expect(syncCallsNamed('postSourceNotice'), hasLength(1));
  });

  test('a disabled source keeps no notices', () async {
    results['work'] = () => const SourceFailed(SyncOutcome.httpError, 'x');
    await sync.run(SyncTrigger.periodic);
    // A server error on top leaves the start of its run behind.
    results['work'] = () => const SourceFailed(SyncOutcome.serverError, 'x');
    await sync.run(SyncTrigger.periodic);
    final serverErrorSince = SyncService.serverErrorSinceKey('work');
    expect(await settings.getString(serverErrorSince), isNotEmpty);

    await sources.save(work.copyWith(enabled: false));
    syncCalls.clear();
    await sync.run(SyncTrigger.periodic);
    expect(
      syncCallsNamed('cancelSourceNotice').map((c) => c.arguments).toSet(),
      {
        {'kind': 'stale', 'sourceId': 'work'},
        {'kind': 'broken', 'sourceId': 'work'},
      },
    );
    expect(await settings.getString(SyncService.brokenNoticeKey('work')), '');
    expect(await settings.getString(serverErrorSince), '');
  });

  test('each run reads the device zone before it plans', () async {
    // The isolate started while the phone was in Johannesburg; the phone has
    // since flown to New York. The service is wired as the app wires it
    // (decision 28): a run builds its rules engine with `tz.local` as it is
    // then, and `zone` stays at its default, so nothing but reading the
    // device zone first can move the plan to New York.
    tz.setLocalLocation(johannesburg);
    deviceZone = 'America/New_York';
    final traveller = newSync(
      rulesEngine: () => RulesEngine(zone: tz.local, clock: () => now),
      // A floating 10:00 on 7 Oct, read in the zone the run hands the source.
      buildSource: (config, state, location) => _FakeSource(
        config.id,
        () => SourceFetched([
          occ(
            uid: 'standup',
            title: 'Standup',
            start: tz.TZDateTime(location, 2026, 10, 7, 10),
          ),
        ]),
      ),
    );

    await traveller.run(SyncTrigger.timeChange);

    expect(tz.local.name, 'America/New_York');
    // 10:00 in New York (UTC-4 in October) is 14:00 UTC; the Meeting
    // profile's heads-up and alarm are 10 min and 1 min before it. Read in
    // Johannesburg it would be 08:00 UTC, with alerts at 07:50 and 07:59.
    expect(applied().map((a) => a['fireAtUtcMs']), [
      DateTime.utc(2026, 10, 7, 13, 50).millisecondsSinceEpoch,
      DateTime.utc(2026, 10, 7, 13, 59).millisecondsSinceEpoch,
    ]);
    expect(syncCalls.map((c) => c.method).take(2), [
      'acquireLock',
      'deviceZone',
    ]);
  });

  test('server errors with no success for 24 h become a broken link', () async {
    await sync.run(SyncTrigger.periodic); // success at 06:00
    results['work'] = () => const SourceFailed(
      SyncOutcome.serverError,
      'The calendar server had a problem (HTTP 500). Retrying.',
    );
    now = now.add(const Duration(hours: 2)); // the first server error, 08:00
    await sync.run(SyncTrigger.periodic);

    // 23.5 h into the server errors, though 25.5 h since the last success:
    // the 24 h run from the first server error, so still amber.
    now = now.add(const Duration(hours: 23, minutes: 30));
    final amber = await sync.run(SyncTrigger.periodic);
    expect(amber.sources.single.outcome, SyncOutcome.serverError);
    expect(amber.outcome, SyncRunOutcome.retry);
    expect(syncCallsNamed('postSourceNotice'), isEmpty);

    now = now.add(const Duration(minutes: 30)); // 24 h of server errors
    final red = await sync.run(SyncTrigger.periodic);
    expect(red.sources.single.outcome, SyncOutcome.httpError);
    expect(red.sources.single.message, contains('over 24 h'));
    expect(red.outcome, SyncRunOutcome.ok);
    final notice = syncCallsNamed('postSourceNotice').single.arguments as Map;
    expect(notice['kind'], 'broken');
    expect(notice['title'], 'Work Outlook feed link stopped working');

    now = now.add(const Duration(minutes: 15));
    await sync.run(SyncTrigger.periodic);
    expect(syncCallsNamed('postSourceNotice'), hasLength(1));
  });

  test(
    'a source that never synced escalates 24 h after its first failure',
    () async {
      results['work'] = () =>
          const SourceFailed(SyncOutcome.serverError, 'HTTP 500');
      await sync.run(SyncTrigger.periodic);
      now = now.add(const Duration(hours: 24));
      final report = await sync.run(SyncTrigger.periodic);
      expect(report.sources.single.outcome, SyncOutcome.httpError);
    },
  );

  test(
    'an offline spell before a server error does not count toward 24 h',
    () async {
      await sync.run(SyncTrigger.periodic); // last success: 06:00 on the 6th
      results['work'] = () =>
          const SourceFailed(SyncOutcome.networkError, 'offline');
      for (var day = 0; day < 3; day++) {
        now = now.add(const Duration(days: 1));
        await sync.run(SyncTrigger.periodic);
      }

      // Back online three days after the last success, the server answers 503.
      results['work'] = () => const SourceFailed(
        SyncOutcome.serverError,
        'The calendar server had a problem (HTTP 503). Retrying.',
      );
      final first = await sync.run(SyncTrigger.periodic);
      expect(first.sources.single.outcome, SyncOutcome.serverError);
      expect(first.outcome, SyncRunOutcome.retry);
      expect(syncCallsNamed('postSourceNotice'), isEmpty);

      // The 24 h run from that first server error, not from the last success.
      now = now.add(const Duration(hours: 23));
      final amber = await sync.run(SyncTrigger.periodic);
      expect(amber.sources.single.outcome, SyncOutcome.serverError);
      now = now.add(const Duration(hours: 1));
      final red = await sync.run(SyncTrigger.periodic);
      expect(red.sources.single.outcome, SyncOutcome.httpError);
      expect(syncCallsNamed('postSourceNotice'), hasLength(1));
    },
  );

  test(
    'a network error between server errors does not restart the 24 h',
    () async {
      await sync.run(SyncTrigger.periodic); // success at 06:00
      results['work'] = () =>
          const SourceFailed(SyncOutcome.serverError, 'HTTP 500');
      now = now.add(const Duration(hours: 2)); // the first server error, 08:00
      await sync.run(SyncTrigger.periodic);

      results['work'] = () =>
          const SourceFailed(SyncOutcome.networkError, 'offline');
      now = now.add(const Duration(hours: 12));
      await sync.run(SyncTrigger.periodic);

      results['work'] = () =>
          const SourceFailed(SyncOutcome.serverError, 'HTTP 500');
      now = now.add(const Duration(hours: 12)); // 24 h after the first one
      final report = await sync.run(SyncTrigger.periodic);
      expect(report.sources.single.outcome, SyncOutcome.httpError);
    },
  );

  test('a success starts the 24 h over', () async {
    await sync.run(SyncTrigger.periodic); // success at 06:00
    results['work'] = () =>
        const SourceFailed(SyncOutcome.serverError, 'HTTP 500');
    now = now.add(const Duration(hours: 2)); // the first server error, 08:00
    await sync.run(SyncTrigger.periodic);

    results['work'] = () => SourceFetched([meeting]);
    now = now.add(const Duration(hours: 1)); // the server recovers, 09:00
    await sync.run(SyncTrigger.periodic);

    // 25 h after the first server error but 24 h after the recovery: the
    // first server error of a new run, so amber.
    results['work'] = () =>
        const SourceFailed(SyncOutcome.serverError, 'HTTP 500');
    now = now.add(const Duration(hours: 24));
    final report = await sync.run(SyncTrigger.periodic);
    expect(report.sources.single.outcome, SyncOutcome.serverError);
    expect(report.outcome, SyncRunOutcome.retry);
  });

  test('network errors never escalate, however long they last', () async {
    await sync.run(SyncTrigger.periodic);
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    now = now.add(const Duration(days: 3));
    final report = await sync.run(SyncTrigger.periodic);
    expect(report.sources.single.outcome, SyncOutcome.networkError);
  });

  test('device-source failures post their own broken titles', () {
    expect(
      SyncService.brokenTitle(work, SyncOutcome.calendarAccessDenied),
      'Work Outlook: calendar access was turned off',
    );
    expect(
      SyncService.brokenTitle(work, SyncOutcome.calendarMissing),
      'Work Outlook: calendar was removed',
    );
  });

  test('an empty feed is ignored once and accepted the second time', () async {
    await sync.run(SyncTrigger.periodic);
    results['work'] = () => const SourceFetched([]);

    final first = await sync.run(SyncTrigger.periodic);
    expect(first.sources.single.outcome, SyncOutcome.emptyKept);
    expect(await cache.countForSource('work'), 1);
    expect((await sources.syncState('work'))!.emptyStreak, 1);

    final second = await sync.run(SyncTrigger.periodic);
    expect(second.sources.single.outcome, SyncOutcome.success);
    expect(await cache.countForSource('work'), 0);
    expect(applied(), isEmpty);
  });

  test('an applyPlan failure is logged and retried', () async {
    applyAnswer = (_) => throw PlatformException(code: 'engine_error');
    final report = await sync.run(SyncTrigger.periodic);
    expect(report.outcome, SyncRunOutcome.retry);
    expect(report.applied, isNull);
    final run = (await log.recent()).firstWhere((e) => e.sourceId == null);
    expect(run.outcome, SyncOutcome.otherError);
    expect(run.message, contains('applyPlan failed (engine_error)'));
    expect(await settings.getString(SyncService.expectedKey), '[]');
  });

  test('an armed alert with no fired record becomes missed (system)', () async {
    await sync.run(SyncTrigger.periodic); // arms 07:50 and 07:59
    now = DateTime.utc(2026, 10, 6, 7, 55); // 07:50 + 5 min, nothing fired
    final report = await sync.run(SyncTrigger.periodic);

    expect(report.missedSystem, 1);
    final missed = (await history.recent()).single;
    expect(missed.type, AlertEventType.missedSystem);
    expect(missed.alertId, PlannedAlert.idFor(meeting.key, 10));
    expect(missed.atUtc, DateTime.utc(2026, 10, 6, 7, 50));
    expect(missed.title, 'Sprint planning');

    now = DateTime.utc(2026, 10, 6, 8, 5); // the 07:59 alarm fired in time
    queuedEvents.add({
      'type': 'fired',
      'alertId': PlannedAlert.idFor(meeting.key, 1),
      'occurrenceKey': meeting.key,
      'startUtcMs': meeting.startUtc.millisecondsSinceEpoch,
      'atUtcMs': DateTime.utc(2026, 10, 6, 7, 59).millisecondsSinceEpoch,
      'snoozeUntilUtcMs': null,
    });
    expect((await sync.run(SyncTrigger.periodic)).missedSystem, 0);
  });

  test('a stale feed with an alert due within 2 h posts Feed stale', () async {
    await sync.run(SyncTrigger.periodic); // last success 06:00
    now = DateTime.utc(2026, 10, 6, 7, 10); // 70 min later; heads-up at 07:50
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    await sync.run(SyncTrigger.periodic);

    final stale = syncCallsNamed('postSourceNotice').single.arguments as Map;
    expect(stale['kind'], 'stale');
    expect(
      stale['title'],
      "Calendar hasn't synced for 1 h. Alarms may be outdated",
    );
    expect(stale['text'], 'Work Outlook');

    results['work'] = () => SourceFetched([meeting]);
    syncCalls.clear();
    await sync.run(SyncTrigger.periodic);
    expect(syncCallsNamed('postSourceNotice'), isEmpty);
    expect(
      syncCallsNamed('cancelSourceNotice').map((c) => c.arguments),
      anyElement(equals({'kind': 'stale', 'sourceId': 'work'})),
    );
  });

  test('stale data with nothing due soon posts nothing', () async {
    await sync.run(SyncTrigger.periodic);
    now = DateTime.utc(2026, 10, 6, 9); // the meeting is over
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    await sync.run(SyncTrigger.periodic);
    expect(syncCallsNamed('postSourceNotice'), isEmpty);
  });

  test('a device source turns the calendar watch on', () async {
    await sources.save(
      const SourceConfig(
        id: 'phone',
        name: 'Phone',
        color: blue,
        kind: SourceKind.device,
        deviceCalendarId: '3',
      ),
    );
    results['phone'] = () => const SourceFetched([]);
    await sync.run(SyncTrigger.calendarChange);
    final configure = syncCallsNamed('configure').single.arguments as Map;
    expect(configure['watchCalendars'], isTrue);
  });

  test(
    'when another sync holds the lock the run waits, then reports busy',
    () async {
      // The wait is real time. The default 30 ms can be used up by the first
      // attempt alone on a loaded machine, which would leave no second one to
      // count, so this test waits long enough for many.
      sync = newSync(
        zone: () => johannesburg,
        lockWait: const Duration(milliseconds: 500),
      );
      lockFree = false;
      final report = await sync.run(SyncTrigger.manual);
      expect(report.outcome, SyncRunOutcome.busy);
      expect(built, isEmpty);
      expect(syncCallsNamed('acquireLock').length, greaterThan(1));
      expect(syncCallsNamed('releaseLock'), isEmpty);
      final skipped = (await log.recent()).single;
      expect(skipped.outcome, SyncOutcome.skipped);
      expect(skipped.message, contains('another sync'));
    },
  );

  test('history and the sync log are pruned', () async {
    await history.record(
      AlertHistoryEntry(
        type: AlertEventType.fired,
        alertId: 'old',
        occurrenceKey: 'k',
        startUtc: now.subtract(const Duration(days: 40)),
        atUtc: now.subtract(const Duration(days: 40)),
      ),
    );
    await log.add(
      SyncLogEntry(
        atUtc: now.subtract(const Duration(days: 8)),
        outcome: SyncOutcome.success,
      ),
    );
    await sync.run(SyncTrigger.periodic);
    expect(await history.recent(), isEmpty);
    expect(
      (await log.recent()).every(
        (e) => e.atUtc.isAfter(now.subtract(const Duration(days: 7))),
      ),
      isTrue,
    );
  });

  test('an unknown trigger name reads as manual', () {
    expect(SyncTrigger.parse('preAlarm'), SyncTrigger.preAlarm);
    expect(SyncTrigger.parse('timeChange'), SyncTrigger.timeChange);
    expect(SyncTrigger.parse('nope'), SyncTrigger.manual);
    expect(SyncTrigger.parse(null), SyncTrigger.manual);
  });

  // Meetings in more than one source (spec §13). The same Outlook calendar
  // reaches the app twice: as the published feed ('work') and as the phone
  // calendar. The phone's id sorts after the feed's, so only its kind, never
  // its id, can put it first in the ranking.
  const phone = SourceConfig(
    id: 'work-phone',
    name: 'Work (phone)',
    color: blue,
    kind: SourceKind.device,
    deviceCalendarId: '3',
  );

  // `meeting` as the phone calendar holds it: another uid, the same title and
  // original start. The phone copy ranks first, so a merged meeting takes its
  // key.
  final phoneCopy = occ(
    sourceId: phone.id,
    uid: 'e7',
    title: 'Sprint planning',
  );

  /// Adds the phone calendar as a second source, holding [phoneCopy].
  Future<void> addPhone() async {
    await sources.save(phone);
    results[phone.id] = () => SourceFetched([phoneCopy]);
  }

  int utcMs(int hour, int minute) =>
      DateTime.utc(2026, 10, 6, hour, minute).millisecondsSinceEpoch;

  List<Object?> appliedIds() => applied().map((a) => a['id']).toList();

  List<Object?> appliedTimes() =>
      applied().map((a) => a['fireAtUtcMs']).toList();

  Set<Object?> appliedKeys() =>
      applied().map((a) => a['occurrenceKey']).toSet();

  /// Which meeting each stored link puts its copy in.
  Future<Map<String, String>> linked() async => {
    for (final l in await links.all()) l.copyKey: l.meetingKey,
  };

  /// The message of the newest whole-run entry in the sync log.
  Future<String?> lastRunMessage() async =>
      (await log.recent()).firstWhere((e) => e.sourceId == null).message;

  Future<List<ExpectedAlert>> expectedAlerts() async =>
      MissedSystemDetector.decode(
        await settings.getString(SyncService.expectedKey),
      );

  test('a single source merges nothing and logs no merged count', () async {
    final report = await sync.run(SyncTrigger.periodic);

    expect(report.merged, 0);
    expect(appliedKeys(), {meeting.key});
    expect(await links.all(), isEmpty);
    expect(
      await lastRunMessage(),
      'periodic: 2 alerts planned; armed 2, cancelled 0, kept 0',
    );
  });

  test('an ICS feed and a phone calendar holding the same meeting plan one set of alerts', () async {
    await addPhone();
    final report = await sync.run(SyncTrigger.periodic);

    // One heads-up and one alarm, not two of each, under the phone copy's key.
    expect(appliedKeys(), {phoneCopy.key});
    expect(appliedTimes(), [utcMs(7, 50), utcMs(7, 59)]);
    expect(appliedIds(), [
      PlannedAlert.idFor(phoneCopy.key, 10),
      PlannedAlert.idFor(phoneCopy.key, 1),
    ]);
    expect(report.planned, 2);
    expect(report.merged, 1);
    expect(report.applied, const ApplyResult(armed: 2, cancelled: 0, kept: 0));

    // Each source still caches its own copy under its own key.
    expect(await cache.byKey(meeting.key), meeting);
    expect(await cache.byKey(phoneCopy.key), phoneCopy);

    // Both copies are remembered as one meeting.
    expect(await linked(), {
      meeting.key: phoneCopy.key,
      phoneCopy.key: phoneCopy.key,
    });
    expect(
      await lastRunMessage(),
      'periodic: 2 alerts planned; armed 2, cancelled 0, kept 0, 1 merged',
    );
  });

  test(
    'removing the phone source keeps the meeting key and its alert ids',
    () async {
      await addPhone();
      await sync.run(SyncTrigger.periodic);
      final before = appliedIds();

      // The source's cached copy goes with it, but its links stay: they do not
      // point at the sources table.
      await sources.delete(phone.id);
      final report = await sync.run(SyncTrigger.periodic);

      expect(await cache.byKey(phoneCopy.key), isNull);
      expect(appliedIds(), before);
      expect(appliedKeys(), {phoneCopy.key});
      expect(appliedTimes(), [utcMs(7, 50), utcMs(7, 59)]);
      expect(report.merged, 0); // the feed's copy is all that is left
      expect(await linked(), {
        meeting.key: phoneCopy.key,
        phoneCopy.key: phoneCopy.key,
      });
    },
  );

  test(
    'Dismiss all before a source is removed still holds afterwards',
    () async {
      await addPhone();
      await sync.run(SyncTrigger.periodic);
      queuedEvents.add({
        'type': 'dismissedAll',
        'alertId': PlannedAlert.idFor(phoneCopy.key, 10),
        'occurrenceKey': phoneCopy.key,
        'startUtcMs': phoneCopy.startUtc.millisecondsSinceEpoch,
        'atUtcMs': now.millisecondsSinceEpoch,
        'snoozeUntilUtcMs': null,
      });
      await sync.run(SyncTrigger.periodic);
      expect(applied(), isEmpty);

      // The feed's copy is alone now. It is planned under the meeting key,
      // which is the one the dismissal was recorded for: under its own key it
      // would ring again.
      await sources.delete(phone.id);
      await sync.run(SyncTrigger.periodic);
      expect(applied(), isEmpty);
    },
  );

  test('a phone calendar cleared by the empty-feed guard leaves its meetings to the feed under the same key', () async {
    await addPhone();
    await sync.run(SyncTrigger.periodic);
    final before = appliedIds();
    SyncOutcome phoneOutcome(SyncReport r) =>
        r.sources.firstWhere((s) => s.sourceId == phone.id).outcome;

    // The first empty answer is ignored, so the phone's copy still counts.
    results[phone.id] = () => const SourceFetched([]);
    final first = await sync.run(SyncTrigger.periodic);
    expect(phoneOutcome(first), SyncOutcome.emptyKept);
    expect(await cache.countForSource(phone.id), 1);
    expect(first.merged, 1);
    expect(appliedIds(), before);

    // The second one clears it. The feed carries the meeting on, under the
    // key it had.
    final second = await sync.run(SyncTrigger.periodic);
    expect(phoneOutcome(second), SyncOutcome.success);
    expect(await cache.countForSource(phone.id), 0);
    expect(second.merged, 0);
    expect(appliedIds(), before);
    expect(appliedKeys(), {phoneCopy.key});

    // When the phone calendar fills up again, the meeting is back under it.
    results[phone.id] = () => SourceFetched([phoneCopy]);
    final third = await sync.run(SyncTrigger.periodic);
    expect(third.merged, 1);
    expect(appliedIds(), before);
  });

  test(
    'a phone source whose access was revoked loses the time to a healthy feed',
    () async {
      // A series instance, so that moving it keeps its key.
      EventOccurrence instance(String sourceId, String uid, {int hour = 8}) =>
          occ(
            sourceId: sourceId,
            uid: uid,
            title: 'Sprint planning',
            seriesUid: 'series',
            start: DateTime.utc(2026, 10, 6, hour),
            originalStart: DateTime.utc(2026, 10, 6, 8),
          );
      await addPhone();
      results['work'] = () => SourceFetched([instance('work', 'm1')]);
      results[phone.id] = () => SourceFetched([instance(phone.id, 'e7')]);
      await sync.run(SyncTrigger.periodic);
      expect(appliedTimes(), [utcMs(7, 50), utcMs(7, 59)]);

      // The meeting moves to 09:00. The feed shows the move. The phone
      // calendar can no longer be read, and its cached copy is still at 08:00.
      results['work'] = () => SourceFetched([instance('work', 'm1', hour: 9)]);
      results[phone.id] = () => const SourceFailed(
        SyncOutcome.calendarAccessDenied,
        'Calendar access was turned off.',
      );
      final report = await sync.run(SyncTrigger.periodic);

      expect(appliedTimes(), [utcMs(8, 50), utcMs(8, 59)]);
      // The meeting is the same one, so what was recorded for it still holds.
      expect(appliedKeys(), {phoneCopy.key});
      expect(report.merged, 1);
    },
  );

  test('a stale feed whose meeting is timed by a healthy phone calendar posts no Feed stale', () async {
    // The phone calendar could not be read when the two were first merged,
    // so the meeting took the feed's key.
    await addPhone();
    results[phone.id] = () => const SourceFailed(
      SyncOutcome.calendarAccessDenied,
      'Calendar access was turned off.',
    );
    await cache.replaceForSource(phone.id, [phoneCopy]);
    await sync.run(SyncTrigger.periodic);
    expect(appliedKeys(), {meeting.key});

    // Now the phone calendar is back and the feed fails, 70 min after its
    // last success, with the heads-up due in 40 min.
    now = DateTime.utc(2026, 10, 6, 7, 10);
    results[phone.id] = () => SourceFetched([phoneCopy]);
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    syncCalls.clear();
    await sync.run(SyncTrigger.periodic);

    // The meeting is still planned under the feed's key, with its alerts
    // still ahead. The phone calendar decides its time, so the feed being
    // stale puts nothing at risk.
    expect(appliedKeys(), {meeting.key});
    expect(appliedTimes(), [utcMs(7, 50), utcMs(7, 59)]);
    expect(syncCallsNamed('postSourceNotice'), isEmpty);
    expect(
      syncCallsNamed('cancelSourceNotice').map((c) => c.arguments),
      anyElement(equals({'kind': 'stale', 'sourceId': 'work'})),
    );
  });

  test('a stale feed timing its own meeting still posts Feed stale', () async {
    await addPhone();
    await sync.run(SyncTrigger.periodic); // merged under the phone copy's key
    expect(appliedKeys(), {phoneCopy.key});

    // The phone calendar goes, so the feed decides the time of the meeting,
    // which is still planned under the key it had. The feed then fails, 70 min
    // after its last success, with the heads-up due in 40 min.
    await sources.delete(phone.id);
    now = DateTime.utc(2026, 10, 6, 7, 10);
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    syncCalls.clear();
    await sync.run(SyncTrigger.periodic);

    expect(appliedKeys(), {phoneCopy.key});
    final stale = syncCallsNamed('postSourceNotice').single.arguments as Map;
    expect(stale['kind'], 'stale');
    expect(stale['sourceId'], 'work');
    expect(
      stale['title'],
      "Calendar hasn't synced for 1 h. Alarms may be outdated",
    );
    expect(stale['text'], 'Work Outlook');
  });

  test('with merge.enabled false both copies are planned', () async {
    await addPhone();
    await sync.run(SyncTrigger.periodic);
    expect(appliedKeys(), {phoneCopy.key});
    final merged = await linked();

    await settings.setString(SyncService.mergeEnabledKey, 'false');
    final unmerged = await sync.run(SyncTrigger.periodic);

    // As before merging existed: each copy under its own key, with its own
    // alerts.
    expect(appliedKeys(), {meeting.key, phoneCopy.key});
    expect(applied(), hasLength(4));
    expect(unmerged.planned, 4);
    expect(unmerged.merged, 0);
    expect(await lastRunMessage(), isNot(contains('merged')));
    // The links stay, so turning merging back on finds the same meeting.
    expect(await linked(), merged);

    await settings.setString(SyncService.mergeEnabledKey, 'true');
    final restored = await sync.run(SyncTrigger.periodic);
    expect(appliedKeys(), {phoneCopy.key});
    expect(applied(), hasLength(2));
    expect(restored.merged, 1);
  });

  test('merging stays on for any stored value but exactly false', () async {
    await addPhone();
    for (final value in ['true', '', 'False', 'FALSE', ' false', '0', 'off']) {
      await settings.setString(SyncService.mergeEnabledKey, value);
      final report = await sync.run(SyncTrigger.periodic);
      expect(report.merged, 1, reason: 'stored value "$value"');
    }
    await settings.setString(SyncService.mergeEnabledKey, 'false');
    expect((await sync.run(SyncTrigger.periodic)).merged, 0);
  });

  test(
    'links persist between runs and are pruned a day after the copy ends',
    () async {
      await addPhone();
      await sync.run(SyncTrigger.periodic);
      final merged = await linked();
      expect(merged, {
        meeting.key: phoneCopy.key,
        phoneCopy.key: phoneCopy.key,
      });

      // A later run keeps them.
      now = now.add(const Duration(minutes: 15));
      await sync.run(SyncTrigger.periodic);
      expect(await linked(), merged);

      // Both copies end at 08:30. A minute short of a day later the links are
      // still there, and a minute past it they are gone.
      final ended = meeting.endUtc;
      now = ended
          .add(const Duration(days: 1))
          .subtract(const Duration(minutes: 1));
      await sync.run(SyncTrigger.periodic);
      expect(await linked(), merged);

      now = ended.add(const Duration(days: 1, minutes: 1));
      await sync.run(SyncTrigger.periodic);
      expect(await linked(), isEmpty);
    },
  );

  test(
    'no missed (system) row when a merged meeting splits before its alert',
    () async {
      await addPhone();
      await sync.run(SyncTrigger.periodic);
      final armed = await expectedAlerts();
      expect(armed.map((e) => (e.id, e.occurrenceKey)), [
        (PlannedAlert.idFor(phoneCopy.key, 10), phoneCopy.key),
        (PlannedAlert.idFor(phoneCopy.key, 1), phoneCopy.key),
      ]);

      // The phone calendar goes before either alert is due. The meeting keeps
      // its key, so the alerts the engine holds are the ones still expected.
      await sources.delete(phone.id);
      now = DateTime.utc(2026, 10, 6, 6, 30);
      final split = await sync.run(SyncTrigger.periodic);
      expect(split.missedSystem, 0);
      expect(await expectedAlerts(), armed);

      // The engine rings both, under the ids it was given.
      for (final (offset, firedAt) in [
        (10, DateTime.utc(2026, 10, 6, 7, 50)),
        (1, DateTime.utc(2026, 10, 6, 7, 59)),
      ]) {
        queuedEvents.add({
          'type': 'fired',
          'alertId': PlannedAlert.idFor(phoneCopy.key, offset),
          'occurrenceKey': phoneCopy.key,
          'startUtcMs': meeting.startUtc.millisecondsSinceEpoch,
          'atUtcMs': firedAt.millisecondsSinceEpoch,
          'snoozeUntilUtcMs': null,
        });
      }
      now = DateTime.utc(2026, 10, 6, 8, 5);
      final after = await sync.run(SyncTrigger.periodic);

      expect(after.missedSystem, 0);
      expect(
        (await history.recent()).map((h) => h.type),
        isNot(contains(AlertEventType.missedSystem)),
      );
    },
  );

  test('disabling the phone source splits the meeting, and enabling it joins the same meeting again', () async {
    await addPhone();
    await sync.run(SyncTrigger.periodic);
    final before = appliedIds();

    // A disabled source keeps its cached copies, but they no longer count.
    await sources.save(phone.copyWith(enabled: false));
    final split = await sync.run(SyncTrigger.periodic);
    expect(split.merged, 0);
    expect(appliedIds(), before);

    await sources.save(phone);
    final joined = await sync.run(SyncTrigger.periodic);
    expect(joined.merged, 1);
    expect(appliedIds(), before);
  });

  test('a link the merger drops is deleted from storage', () async {
    // The phone calendar holds a second event like the feed's meeting. From an
    // earlier run, all three copies are linked to the meeting, which one
    // source cannot have two copies of.
    await addPhone();
    final twin = occ(sourceId: phone.id, uid: 'e8', title: 'Sprint planning');
    results[phone.id] = () => SourceFetched([phoneCopy, twin]);
    MeetingLink linkTo(EventOccurrence c) => MeetingLink(
      copyKey: c.key,
      meetingKey: meeting.key,
      sourceId: c.sourceId,
      uid: c.uid,
      oneOff: true,
      endUtc: c.endUtc,
      matchedBy: MeetingMatch.remembered,
    );
    await links.apply(
      upsert: [linkTo(meeting), linkTo(phoneCopy), linkTo(twin)],
      delete: {},
    );

    final report = await sync.run(SyncTrigger.periodic);

    // The twin is turned away: it is planned on its own, under its own key,
    // and its link is gone.
    expect(await linked(), {
      meeting.key: meeting.key,
      phoneCopy.key: meeting.key,
    });
    expect(appliedKeys(), {meeting.key, twin.key});
    expect(report.merged, 1);
  });

  // Runs that only re-plan, and the quick-settings tile (Plan 5 decisions 2
  // and 3).
  test(
    'an edit run fetches nothing, plans from the cache and keeps lastFinished',
    () async {
      await sync.run(SyncTrigger.periodic);
      final finished = await settings.getString(SyncService.lastFinishedKey);
      built.clear();
      now = now.add(const Duration(minutes: 5));

      final report = await sync.run(SyncTrigger.edit);

      expect(built, isEmpty);
      expect(report.sources, isEmpty);
      expect(report.outcome, SyncRunOutcome.ok);
      expect(applied(), hasLength(2));
      expect(await settings.getString(SyncService.lastFinishedKey), finished);
      expect(
        (await log.recent()).where(
          (e) => e.message?.startsWith('edit:') ?? false,
        ),
        isEmpty,
      );
    },
  );

  test('an edit run whose applyPlan fails is logged', () async {
    applyAnswer = (_) => throw PlatformException(code: 'apply_failed');
    await sync.run(SyncTrigger.edit);
    expect(
      (await log.recent()).first.message,
      startsWith('edit: applyPlan failed (apply_failed)'),
    );
  });

  test('a busy edit run writes no sync-log row', () async {
    lockFree = false;
    final report = await sync.run(SyncTrigger.edit);
    expect(report.outcome, SyncRunOutcome.busy);
    // A run that only re-plans leaves a row only when applyPlan failed; the
    // skipped row is for the runs that fetch.
    expect(await log.recent(), isEmpty);
  });

  test(
    'an edit run neither posts nor withdraws a Feed broken notice',
    () async {
      // The link is broken and its notice is up.
      results['work'] = () => const SourceFailed(
        SyncOutcome.httpError,
        'The link no longer works (HTTP 404).',
      );
      await sync.run(SyncTrigger.periodic);
      final noticeKey = SyncService.brokenNoticeKey('work');
      expect(await settings.getString(noticeKey), 'httpError');

      // The feed would answer now. An edit run does not ask it, so it sees no
      // recovery and leaves the notice up.
      results['work'] = () => SourceFetched([meeting]);
      syncCalls.clear();
      await sync.run(SyncTrigger.edit);

      expect(
        syncCallsNamed('postSourceNotice')
            .where((c) => (c.arguments as Map)['kind'] == 'broken'),
        isEmpty,
      );
      expect(
        syncCallsNamed('cancelSourceNotice')
            .where((c) => (c.arguments as Map)['kind'] == 'broken'),
        isEmpty,
      );
      expect(await settings.getString(noticeKey), 'httpError');
    },
  );

  test('an edit run does not post a Feed broken notice for a source that now fails', () async {
    await sync.run(SyncTrigger.periodic); // the feed answers: no notice

    // The feed would fail now. An edit run does not ask it, so there is no
    // failure to post a notice for.
    results['work'] = () => const SourceFailed(
      SyncOutcome.httpError,
      'The link no longer works (HTTP 404).',
    );
    syncCalls.clear();
    await sync.run(SyncTrigger.edit);

    expect(
      syncCallsNamed('postSourceNotice')
          .where((c) => (c.arguments as Map)['kind'] == 'broken'),
      isEmpty,
    );
  });

  test('an edit run withdraws the notices of a disabled source', () async {
    results['work'] = () => const SourceFailed(SyncOutcome.httpError, 'x');
    await sync.run(SyncTrigger.periodic);
    // A server error on top leaves the start of its run behind.
    results['work'] = () => const SourceFailed(SyncOutcome.serverError, 'x');
    await sync.run(SyncTrigger.periodic);
    final serverErrorSince = SyncService.serverErrorSinceKey('work');
    expect(await settings.getString(serverErrorSince), isNotEmpty);
    expect(
      await settings.getString(SyncService.brokenNoticeKey('work')),
      'httpError',
    );

    await sources.save(work.copyWith(enabled: false));
    syncCalls.clear();
    await sync.run(SyncTrigger.edit);

    expect(
      syncCallsNamed('cancelSourceNotice').map((c) => c.arguments).toSet(),
      {
        {'kind': 'stale', 'sourceId': 'work'},
        {'kind': 'broken', 'sourceId': 'work'},
      },
    );
    expect(await settings.getString(SyncService.brokenNoticeKey('work')), '');
    expect(await settings.getString(serverErrorSince), '');
  });

  test('a waiting tile request is applied before planning', () async {
    await sync.run(SyncTrigger.periodic);
    quietRequest = {'action': 'mute', 'atMs': now.millisecondsSinceEpoch};
    await sync.run(SyncTrigger.quietTile);
    expect(await settings.quietState(), isA<MuteToday>());
    expect(applied(), isEmpty); // Meeting does not ring in quiet mode
    expect(syncCallsNamed('takeQuietRequest'), hasLength(2)); // every run asks
  });

  test('an end request clears any quiet mode', () async {
    // Fills the cache: quietTile runs do not fetch.
    await sync.run(SyncTrigger.periodic);
    await settings.setQuietState(
      QuietState.muteToday(nowUtc: now, zone: johannesburg),
    );
    quietRequest = {'action': 'end', 'atMs': now.millisecondsSinceEpoch};
    await sync.run(SyncTrigger.quietTile);
    expect(await settings.quietState(), const QuietNone());
    expect(applied(), hasLength(2));
  });

  test('a tile request older than an in-app quiet change is dropped', () async {
    await settings.setQuietStateAt(const QuietNone(), changedAtUtc: now);
    quietRequest = {
      'action': 'mute',
      'atMs': now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
    };
    await sync.run(SyncTrigger.quietTile);
    expect(await settings.quietState(), const QuietNone());
  });

  test('a tile request newer than the last in-app change is applied', () async {
    await settings.setQuietStateAt(
      const QuietNone(),
      changedAtUtc: now.subtract(const Duration(seconds: 1)),
    );
    quietRequest = {'action': 'mute', 'atMs': now.millisecondsSinceEpoch};
    await sync.run(SyncTrigger.quietTile);
    expect(await settings.quietState(), isA<MuteToday>());

    // The request applied is itself a change, stamped with its own time. A
    // tap in between (newer than the in-app change, older than the mute) is
    // dropped; it is an end tap so that applying it would show as QuietNone.
    quietRequest = {
      'action': 'end',
      'atMs': now
          .subtract(const Duration(milliseconds: 500))
          .millisecondsSinceEpoch,
    };
    await sync.run(SyncTrigger.quietTile);
    expect(await settings.quietState(), isA<MuteToday>());

    // A later tap is newer than the mute and wins.
    quietRequest = {
      'action': 'end',
      'atMs': now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
    };
    await sync.run(SyncTrigger.quietTile);
    expect(await settings.quietState(), const QuietNone());
  });

  test('configure tells the tile when quiet ends and what to show', () async {
    await settings.setQuietState(
      QuietState.muteToday(nowUtc: now, zone: johannesburg),
    );
    await sync.run(SyncTrigger.edit);
    final args = syncCallsNamed('configure').last.arguments as Map;
    // 07:00 on 7 Oct in Johannesburg = 05:00 UTC.
    expect(
      args['quietUntilMs'],
      DateTime.utc(2026, 10, 7, 5).millisecondsSinceEpoch,
    );
    expect(args['quietText'], 'Until 07:00');
  });

  test('a vacation that has not started does not show on the tile', () async {
    await settings.setQuietState(
      Vacation(LocalDate(2026, 10, 12), LocalDate(2026, 10, 16)),
    );
    await sync.run(SyncTrigger.edit);
    final args = syncCallsNamed('configure').last.arguments as Map;
    expect(args['quietUntilMs'], isNull);
    expect(args['quietText'], isNull);
  });

  test('the tile for a vacation in progress ends after its last local day and reads Vacation', () {
    // `now` is 08:00 on 6 Oct in Johannesburg, inside the vacation.
    final vacation = Vacation(LocalDate(2026, 10, 5), LocalDate(2026, 10, 9));
    // Local midnight after the 9th: 00:00 on 10 Oct is 22:00 UTC on the 9th.
    final end = DateTime.utc(2026, 10, 9, 22);

    expect(SyncService.quietEnd(vacation, johannesburg, now), end);
    expect(SyncService.quietTileText(vacation, johannesburg, now), 'Vacation');

    // The last minute of the 9th is still covered, and the end is not.
    final lastMinute = end.subtract(const Duration(minutes: 1));
    expect(SyncService.quietEnd(vacation, johannesburg, lastMinute), end);
    expect(SyncService.quietEnd(vacation, johannesburg, end), isNull);
    expect(SyncService.quietTileText(vacation, johannesburg, end), isNull);
  });

  test(
    'the tile for a pause in progress ends at its end and reads Paused until',
    () {
      // `now` is 08:00 on 6 Oct in Johannesburg; the pause ends at 14:00.
      final until = DateTime.utc(2026, 10, 6, 12);
      final pause = PausedUntil(until);

      expect(SyncService.quietEnd(pause, johannesburg, now), until);
      expect(
        SyncService.quietTileText(pause, johannesburg, now),
        'Paused until 14:00',
      );

      // At its end it no longer shows.
      expect(SyncService.quietEnd(pause, johannesburg, until), isNull);
      expect(SyncService.quietTileText(pause, johannesburg, until), isNull);
    },
  );

  test('quietTile and edit parse by name and do not fetch', () {
    expect(SyncTrigger.parse('quietTile'), SyncTrigger.quietTile);
    expect(SyncTrigger.edit.fetches, isFalse);
    expect(SyncTrigger.quietTile.fetches, isFalse);
    expect(
      SyncTrigger.values.where((t) => t.fetches),
      hasLength(SyncTrigger.values.length - 2),
    );
  });

  test(
    'a source removed while its fetch runs leaves no body or notice and does '
    'not fail the run',
    () async {
      // Two feeds fetch over a client that answers when the test says so: one
      // will answer with a calendar, whose body the fetch stores, the other
      // with an error that would post a "Feed broken" notice. A third source
      // answers at once.
      const team = SourceConfig(
        id: 'team',
        name: 'Team rota',
        color: blue,
        kind: SourceKind.ics,
        secureStorageKey: 'ics-url.team',
      );
      const other = SourceConfig(
        id: 'other',
        name: 'Other',
        color: blue,
        kind: SourceKind.ics,
        secureStorageKey: 'ics-url.other',
      );
      await sources.save(team);
      await sources.save(other);
      const feed = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:m1
DTSTART:20261006T080000Z
DTEND:20261006T083000Z
SUMMARY:Sprint planning
END:VEVENT
END:VCALENDAR
''';
      final bodies = _Bodies();
      final answers = {
        'work.example': Completer<http.Response>(),
        'team.example': Completer<http.Response>(),
      };
      // Completes once both feeds have been asked for: both fetches are under
      // way.
      final bothAsked = Completer<void>();
      var asked = 0;
      final client = MockClient((request) {
        if (++asked == 2) bothAsked.complete();
        return answers[request.url.host]!.future;
      });
      final service = newSync(
        buildSource: (config, state, location) => config.id == 'other'
            ? _FakeSource(
                'other',
                () => SourceFetched([occ(sourceId: 'other', uid: 'o1')]),
              )
            : IcsFeedSource(
                config: config,
                previous: state,
                client: client,
                secrets: _Links(),
                bodies: bodies,
                deviceZone: location.name,
              ),
      );

      final run = service.run(SyncTrigger.manual);
      await bothAsked.future;

      // Both are removed while they fetch, as SourceAdmin.delete does it: the
      // row (its cached events go with it) and the stored body.
      for (final id in ['work', 'team']) {
        await sources.delete(id);
        await bodies.delete(id);
      }
      answers['work.example']!.complete(http.Response(feed, 200));
      answers['team.example']!.complete(http.Response('', 404));
      final report = await run;

      // The run went on with the source that is still there...
      expect(report.outcome, SyncRunOutcome.ok);
      expect([for (final r in report.sources) r.sourceId], ['other']);
      expect(await cache.countForSource('other'), 1);
      // ... and nothing of the removed ones was kept or announced.
      expect(bodies.kept, isEmpty);
      expect(syncCallsNamed('postSourceNotice'), isEmpty);
      expect(await cache.countForSource('work'), 0);
      for (final id in ['work', 'team']) {
        expect(
          await settings.getString(SyncService.brokenNoticeKey(id)),
          isNull,
          reason: id,
        );
        expect(
          await settings.getString(SyncService.serverErrorSinceKey(id)),
          isNull,
          reason: id,
        );
      }
      expect([
        for (final e in await log.recent())
          if (e.sourceId != null && e.sourceId != 'other') e.sourceId,
      ], isEmpty);
    },
  );
}
