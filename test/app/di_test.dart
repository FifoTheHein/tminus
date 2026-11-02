import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/app/app_lifecycle.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/health_monitor.dart';
import 'package:tminus/app/onboarding_gate.dart';
import 'package:tminus/app/replan_scheduler.dart';
import 'package:tminus/app/restore_guard.dart';
import 'package:tminus/app/sync_runner.dart';
import 'package:tminus/app/theme_mode_controller.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/planner/meeting_planner.dart';
import 'package:tminus/core/planner/plan_builder.dart';
import 'package:tminus/core/platform/ui_platform.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/sources/ics_link_probe.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sources/source_admin.dart';
import 'package:tminus/core/sources/source_factory.dart';
import 'package:tminus/core/sync/engine_event_recorder.dart';
import 'package:tminus/core/sync/foreground_sync.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/core/transfer/settings_transfer.dart';
import 'package:tminus/features/agenda/agenda_model.dart';

import '../core/fixtures.dart';
import '../core/storage/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engineChannel = MethodChannel(AlarmEngine.methodChannelName);
  const syncChannel = MethodChannel(SyncPlatform.channelName);

  tearDown(getIt.reset);

  /// A native side that lets a sync through: a free lock, the UTC zone, no
  /// waiting tile request and an engine that accepts any plan. Returns the
  /// calls it received (`engine.applyPlan`, `sync.acquireLock`, ...).
  ///
  /// It answers `installId` with [installId] (nothing when null, as before),
  /// and adds the alerts of each `applyPlan` to [plans].
  List<String> mockNativeSide({String? installId, List<List<Object?>>? plans}) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(engineChannel, (c) async {
      calls.add('engine.${c.method}');
      if (c.method == 'applyPlan') {
        plans?.add((c.arguments as Map)['alerts'] as List<Object?>);
      }
      return switch (c.method) {
        'applyPlan' => {'armed': 0, 'cancelled': 0, 'kept': 0},
        'drainEvents' => <Object?>[],
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(syncChannel, (c) async {
      calls.add('sync.${c.method}');
      return switch (c.method) {
        'installId' => installId,
        'acquireLock' => true,
        'deviceZone' => 'UTC',
        _ => null,
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(engineChannel, null);
      messenger.setMockMethodCallHandler(syncChannel, null);
    });
    return calls;
  }

  test('nothing opens the database until it is asked for', () async {
    var opened = 0;
    configureDependencies(
      openDatabase: () {
        opened++;
        return openTestDatabase();
      },
    );
    expect(opened, 0);
    getIt<SourceRepository>();
    getIt<SourceRepository>();
    expect(opened, 1);
  });

  test('configureDependencies registers one AlarmEngine', () {
    configureDependencies(openDatabase: openTestDatabase);
    expect(getIt<AlarmEngine>(), same(getIt<AlarmEngine>()));
  });

  test('the sync services share one engine and one event recorder', () {
    configureDependencies(openDatabase: openTestDatabase);
    final sync = getIt<SyncService>();
    expect(sync.engine, same(getIt<AlarmEngine>()));
    expect(sync.recorder, same(getIt<EngineEventRecorder>()));
    expect(getIt<EngineEventRecorder>().engine, same(getIt<AlarmEngine>()));
    expect(getIt<ForegroundSync>().sync, same(sync));
    expect(getIt<SyncPlatform>(), same(getIt<SyncPlatform>()));
    expect(getIt<SourceFactory>(), isNotNull);
    expect(getIt<SourceAdmin>(), isNotNull);
  });

  test('the sync rules engine reads the device zone when it plans', () {
    configureDependencies(openDatabase: openTestDatabase);
    final before = tz.local;
    addTearDown(() => tz.setLocalLocation(before));
    // Built before the phone changes zone, as the long-lived UI isolate's is.
    final sync = getIt<SyncService>();

    tz.setLocalLocation(tz.getLocation('America/New_York'));
    expect(sync.rulesEngine().zone.name, 'America/New_York');
    expect(sync.zone(), tz.local);

    // Read at each call, not captured once: a later change is picked up too.
    tz.setLocalLocation(tz.getLocation('Africa/Johannesburg'));
    expect(sync.rulesEngine().zone.name, 'Africa/Johannesburg');
    expect(sync.zone(), tz.local);
  });

  test('configureDependencies loads the time zone database', () {
    configureDependencies(openDatabase: openTestDatabase);
    expect(tz.timeZoneDatabase.isInitialized, isTrue);
    expect(getIt<RulesEngine>().zone, tz.local);
  });

  test('database → rules → plan, end to end', () async {
    configureDependencies(openDatabase: openTestDatabase);
    final now = DateTime.utc(2026, 10, 6, 6);

    await getIt<SourceRepository>().save(
      const SourceConfig(
        id: 'work',
        name: 'Work',
        color: blue,
        kind: SourceKind.ics,
        secureStorageKey: 'ics_url_work',
        defaultProfileId: 'important',
      ),
    );
    await getIt<RuleRepository>().save(
      KeywordRule(
        id: 'r1',
        position: 0,
        field: RuleField.title,
        pattern: 'standup',
        profileId: 'quick',
      ),
    );
    final standup = occ(
      uid: 'standup',
      title: 'Daily standup',
      start: DateTime.utc(2026, 10, 6, 6, 45),
    );
    final demo = occ(
      uid: 'demo',
      title: 'Client demo',
      start: DateTime.utc(2026, 10, 6, 12),
    );
    final tentative = occ(
      uid: 'talk',
      title: 'Tech talk',
      start: DateTime.utc(2026, 10, 6, 14),
      busyStatus: BusyStatus.tentative,
    );
    await getIt<OccurrenceRepository>().replaceForSource('work', [
      standup,
      demo,
      tentative,
    ]);
    await getIt<AlertHistoryRepository>().record(
      AlertHistoryEntry(
        type: AlertEventType.dismissed,
        alertId: PlannedAlert.idFor(demo.key, 30),
        occurrenceKey: demo.key,
        startUtc: demo.startUtc,
        atUtc: now,
      ),
    );

    final rules = await getIt<RuleSetLoader>().load();
    final engine = RulesEngine(zone: johannesburg, clock: () => now);
    final cached = await getIt<OccurrenceRepository>().between(
      now.subtract(const Duration(hours: 1)),
      now.add(const Duration(days: 7)),
    );
    final resolved = engine.resolveAll(cached, rules);
    final plan = buildPlan(
      resolved,
      now: now,
      acknowledgements: await getIt<AlertHistoryRepository>().acknowledgements(
        nowUtc: now,
      ),
    );

    expect(resolved.map((r) => r.explanation), [
      'Quick · rule: "standup"',
      'Important · source default',
      'Silent · tentative',
    ]);
    expect(plan.map((a) => (a.occurrenceKey, a.offsetMinutes)), [
      (standup.key, 1),
      (demo.key, 10),
      (demo.key, 2),
    ]);
  });

  test('every Plan 5 service resolves', () {
    var opened = 0;
    configureDependencies(
      openDatabase: () {
        opened++;
        return openTestDatabase();
      },
    );

    expect(getIt<SyncRunner>(), isNotNull);
    expect(getIt<ThemeModeController>(), isNotNull);
    expect(getIt<UiPlatform>(), isNotNull);
    expect(getIt<AppSettings>(), isNotNull);
    expect(getIt<OnboardingGate>(), isNotNull);
    expect(getIt<SourceStatusLoader>(), isNotNull);
    expect(getIt<MeetingPlanner>(), isNotNull);
    expect(getIt<ReplanScheduler>(), isNotNull);
    expect(getIt<AppLifecycle>(), isNotNull);
    expect(getIt<RestoreGuard>(), isNotNull);
    expect(getIt<HealthMonitor>(), isNotNull);
    expect(getIt<IcsLinkProbe>(), isNotNull);
    expect(getIt<SettingsTransfer>(), isNotNull);
    expect(getIt<AgendaLoader>(), isNotNull);
    // All of them, the transfer included, are built on the one database.
    expect(opened, 1);
  });

  // Beyond the plan's list.

  test('the Plan 5 services are wired to the registered instances', () {
    configureDependencies(openDatabase: openTestDatabase);
    final db = getIt<AppDatabase>();
    final platform = getIt<SyncPlatform>();
    final statuses = getIt<SourceStatusLoader>();

    // Only the registered SyncPlatform listens for the background-sync signal:
    // the channel has one handler, and a second platform that listened and then
    // cancelled would clear this one's.
    final lifecycle = getIt<AppLifecycle>();
    expect(lifecycle.platform, same(platform));
    expect(lifecycle.db, same(db));
    expect(lifecycle.replan, same(getIt<ReplanScheduler>()));

    final guard = getIt<RestoreGuard>();
    // One guard for the whole app: start-up and the syncs the screens ask for
    // share what it remembers about an unsafe restore.
    expect(getIt<RestoreGuard>(), same(guard));
    expect(guard.platform, same(platform));
    expect(guard.db, same(db));
    expect(guard.appSettings, same(getIt<AppSettings>()));
    expect(guard.sources, same(getIt<SourceRepository>()));
    expect(guard.admin, same(getIt<SourceAdmin>()));
    // The admin writes what it clears and what it re-points through the one
    // database, in one transaction.
    expect(getIt<SourceAdmin>().db, same(db));
    expect(
      getIt<SourceAdmin>().occurrences,
      same(getIt<OccurrenceRepository>()),
    );

    final monitor = getIt<HealthMonitor>();
    expect(monitor.engine, same(getIt<AlarmEngine>()));
    expect(monitor.statuses, same(statuses));

    final planner = getIt<MeetingPlanner>();
    expect(planner.sources, same(getIt<SourceRepository>()));
    expect(planner.occurrences, same(getIt<OccurrenceRepository>()));
    expect(planner.ruleSets, same(getIt<RuleSetLoader>()));
    final loader = getIt<AgendaLoader>();
    expect(loader.planner, same(planner));
    expect(loader.statuses, same(statuses));
    expect(loader.appSettings, same(getIt<AppSettings>()));
    // A loader for each screen controller.
    expect(getIt<AgendaLoader>(), isNot(same(loader)));
  });

  test('the registered theme controller stores the choice, and a new start '
      'loads it', () async {
    configureDependencies(openDatabase: openTestDatabase);
    expect(getIt<ThemeModeController>().mode, ThemeMode.system);

    getIt<ThemeModeController>().mode = ThemeMode.dark;
    // The setter does not wait for the write.
    await pumpEventQueue();
    expect(
      await getIt<SettingsRepository>().getString(
        ThemeModeController.settingsKey,
      ),
      'dark',
    );

    await getIt.resetLazySingleton<ThemeModeController>();
    final restarted = getIt<ThemeModeController>();
    expect(restarted.mode, ThemeMode.system);
    await restarted.load();
    expect(restarted.mode, ThemeMode.dark);
  });

  test('the sync runner runs the trigger it is given', () async {
    configureDependencies(openDatabase: openTestDatabase);
    final calls = mockNativeSide();

    final report = await getIt<SyncRunner>()(SyncTrigger.pullToRefresh);

    expect(report.trigger, SyncTrigger.pullToRefresh);
    expect(report.outcome, SyncRunOutcome.ok);
    expect(calls, contains('engine.applyPlan'));
    // No restore is unsafe, so the guard is not asked again: running it before
    // every sync could take a user's first source for an old backup.
    expect(calls, isNot(contains('sync.installId')));
  });

  test(
    'the re-plan scheduler plans from the cache and fetches nothing',
    () async {
      configureDependencies(openDatabase: openTestDatabase);
      final calls = mockNativeSide();

      getIt<ReplanScheduler>().request();
      await getIt<ReplanScheduler>().flush();

      expect(calls.where((c) => c == 'engine.applyPlan'), hasLength(1));
      // A run that fetches records when it finished; a re-plan does not, so it
      // never makes the next foreground sync skip.
      expect(
        await getIt<SettingsRepository>().getString(
          SyncService.lastFinishedKey,
        ),
        isNull,
      );
      // No restore is unsafe, so the re-plan does not ask the guard either.
      expect(calls, isNot(contains('sync.installId')));
    },
  );

  test('a sync the screens ask for waits while a restore is unsafe', () async {
    configureDependencies(openDatabase: openTestDatabase);
    final plans = <List<Object?>>[];
    final calls = mockNativeSide(installId: 'phone-B', plans: plans);
    final db = getIt<AppDatabase>();
    final app = getIt<AppSettings>();
    final sources = getIt<SourceRepository>();

    // A backup made on another phone: its feed is enabled and its cache holds a
    // meeting that has not started yet.
    await app.setInstallId('phone-A');
    await app.setOnboardingDone(true);
    await sources.save(
      const SourceConfig(
        id: 'ics-1',
        name: 'Work Outlook',
        color: blue,
        kind: SourceKind.ics,
        secureStorageKey: 'ics-url.ics-1',
      ),
    );
    await getIt<OccurrenceRepository>().replaceForSource('ics-1', [
      occ(
        sourceId: 'ics-1',
        uid: 'standup',
        start: DateTime.now().toUtc().add(const Duration(days: 1)),
      ),
    ]);
    // The last write of a restore fails, as in a locked or full database.
    await db.customStatement(
      'CREATE TRIGGER no_install_id BEFORE INSERT ON settings '
      "WHEN NEW.name = '${AppSettings.installIdKey}' "
      "BEGIN SELECT RAISE(ABORT, 'no'); END",
    );

    // Start-up found the restore and could not make it safe. The guard is the
    // registered one, which is what the sync below consults.
    final guard = getIt<RestoreGuard>();
    expect(await guard.run(), RestoreOutcome.unsafe);
    expect(guard.unsafe, isTrue);
    calls.clear();

    // A sync a screen asks for tries the guard again, finds it still cannot
    // finish, and plans, fetches and arms nothing.
    final waiting = await getIt<SyncRunner>()(SyncTrigger.manual);
    expect(waiting.outcome, SyncRunOutcome.busy);
    expect(waiting.trigger, SyncTrigger.manual);
    expect(calls, ['sync.installId']);

    // So does the re-plan an edit asks for: not once, because the scheduler
    // tries a busy run again, but never past the guard.
    calls.clear();
    getIt<ReplanScheduler>().request();
    await getIt<ReplanScheduler>().flush();
    expect(calls, isNotEmpty);
    expect(calls.toSet(), {'sync.installId'});
    expect(calls, isNot(contains('sync.acquireLock')));
    expect(calls.where((c) => c.startsWith('engine.')), isEmpty);
    expect(guard.unsafe, isTrue);

    // Whatever stopped the restore has passed: the next sync finishes it
    // first, then runs on the safe database.
    await db.customStatement('DROP TRIGGER no_install_id');
    calls.clear();
    plans.clear();
    final report = await getIt<SyncRunner>()(SyncTrigger.manual);

    expect(report.outcome, SyncRunOutcome.ok);
    expect(guard.unsafe, isFalse);
    expect((await sources.byId('ics-1'))!.enabled, isFalse);
    expect(await app.sourceSetup('ics-1'), SourceSetup.needsLink);
    expect(await app.installId(), 'phone-B');
    // The sync planned from the emptied cache, so nothing is armed from the
    // old phone's meeting, and the guard came before the lock.
    expect(plans, hasLength(1));
    expect(plans.single, isEmpty);
    expect(calls.indexOf('sync.installId'), isNonNegative);
    expect(
      calls.indexOf('sync.installId'),
      lessThan(calls.indexOf('sync.acquireLock')),
    );
  });
}
