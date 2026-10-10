import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/engine_event_recorder.dart';
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
  /// sources; a null [zone] leaves `SyncService.zone` at its default.
  SyncService newSync({
    RulesEngine Function()? rulesEngine,
    tz.Location Function()? zone,
    SourceBuilder? buildSource,
  }) {
    final engine = AlarmEngine();
    return SyncService(
      sources: sources,
      occurrences: cache,
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
      lockWait: const Duration(milliseconds: 30),
      lockPoll: const Duration(milliseconds: 5),
    );
  }

  setUp(() async {
    initZones();
    now = DateTime.utc(2026, 10, 6, 6);
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
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
      "Calendar hasn't synced for 1 h — alarms may be outdated",
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
}
