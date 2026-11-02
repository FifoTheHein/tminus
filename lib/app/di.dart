import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/engine/alarm_engine.dart';
import '../core/planner/meeting_planner.dart';
import '../core/platform/ui_platform.dart';
import '../core/rules/rules_engine.dart';
import '../core/sources/device_calendar_api.dart';
import '../core/sources/fast_alarms.dart';
import '../core/sources/feed_body_cache.dart';
import '../core/sources/ics_link_probe.dart';
import '../core/sources/source_admin.dart';
import '../core/sources/source_factory.dart';
import '../core/sources/source_secrets.dart';
import '../core/storage/alert_history_repository.dart';
import '../core/storage/app_database.dart';
import '../core/storage/app_settings.dart';
import '../core/storage/meeting_link_repository.dart';
import '../core/storage/occurrence_repository.dart';
import '../core/storage/override_repository.dart';
import '../core/storage/profile_repository.dart';
import '../core/storage/rule_repository.dart';
import '../core/storage/rule_set_loader.dart';
import '../core/storage/settings_repository.dart';
import '../core/storage/source_repository.dart';
import '../core/storage/sync_log_repository.dart';
import '../core/sync/engine_event_recorder.dart';
import '../core/sync/foreground_sync.dart';
import '../core/sync/source_status.dart';
import '../core/sync/sync_platform.dart';
import '../core/sync/sync_service.dart';
import '../core/transfer/settings_transfer.dart';
import '../features/agenda/agenda_model.dart';
import 'app_lifecycle.dart';
import 'health_monitor.dart';
import 'onboarding_gate.dart';
import 'replan_scheduler.dart';
import 'restore_guard.dart';
import 'sync_runner.dart';
import 'theme_mode_controller.dart';

final GetIt getIt = GetIt.instance;

/// Registers app-wide services. Call once before [runApp].
///
/// Everything is lazy, so nothing opens the database until something asks
/// for it: widget tests that never touch storage need no database and no
/// path_provider. Tests that do use storage pass [openDatabase], e.g. an
/// in-memory `AppDatabase`. `getIt.reset()` closes the database if it was
/// opened.
void configureDependencies({AppDatabase Function()? openDatabase}) {
  if (!tz.timeZoneDatabase.isInitialized) tzdata.initializeTimeZones();

  // Given its settings, so the choice is stored (`ui.themeMode`) and `main`
  // can load it before the first frame.
  getIt.registerLazySingleton<ThemeModeController>(
    () => ThemeModeController(settings: () => getIt<SettingsRepository>()),
  );
  getIt.registerLazySingleton<AlarmEngine>(AlarmEngine.new);

  getIt.registerLazySingleton<AppDatabase>(
    openDatabase ?? AppDatabase.open,
    dispose: (db) => db.close(),
  );
  getIt.registerLazySingleton(() => SourceRepository(getIt()));
  getIt.registerLazySingleton(() => OccurrenceRepository(getIt()));
  getIt.registerLazySingleton(() => MeetingLinkRepository(getIt()));
  getIt.registerLazySingleton(() => ProfileRepository(getIt()));
  getIt.registerLazySingleton(() => RuleRepository(getIt()));
  getIt.registerLazySingleton(() => OverrideRepository(getIt()));
  getIt.registerLazySingleton(() => SettingsRepository(getIt()));
  getIt.registerLazySingleton(() => AlertHistoryRepository(getIt()));
  getIt.registerLazySingleton(() => SyncLogRepository(getIt()));
  getIt.registerLazySingleton(
    () => RuleSetLoader(
      profiles: getIt(),
      rules: getIt(),
      overrides: getIt(),
      settings: getIt(),
      sources: getIt(),
    ),
  );

  // A factory, not a singleton: each engine reads `tz.local` as it is now.
  // `initDeviceZone` sets it from the device at startup and before every
  // sync; until then it is UTC.
  getIt.registerFactory(() => RulesEngine(zone: tz.local));

  // Sources and sync (Plan 4).
  getIt.registerLazySingleton<http.Client>(
    http.Client.new,
    dispose: (c) => c.close(),
  );
  getIt.registerLazySingleton<SourceSecrets>(SourceSecrets.new);
  getIt.registerLazySingleton<FeedBodyCache>(
    () => FeedBodyCache(() async {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}${Platform.pathSeparator}feeds');
    }),
  );
  getIt.registerLazySingleton<DeviceCalendarApi>(DeviceCalendarApi.new);
  getIt.registerLazySingleton<SyncPlatform>(SyncPlatform.new);
  getIt.registerLazySingleton(
    () => FastAlarms(sources: getIt(), settings: getIt()),
  );
  getIt.registerLazySingleton(
    () => SourceFactory(
      client: getIt(),
      secrets: getIt(),
      bodies: getIt(),
      deviceCalendars: getIt(),
      fastAlarms: getIt(),
    ),
  );
  getIt.registerLazySingleton(
    () => SourceAdmin(
      sources: getIt(),
      secrets: getIt(),
      bodies: getIt(),
      platform: getIt(),
      settings: getIt(),
      occurrences: getIt(),
      db: getIt(),
    ),
  );
  getIt.registerLazySingleton<EngineEventRecorder>(
    () => EngineEventRecorder(
      engine: getIt(),
      history: getIt(),
      occurrences: getIt(),
    ),
    dispose: (r) => r.stop(),
  );
  getIt.registerLazySingleton(
    () => SyncService(
      sources: getIt(),
      occurrences: getIt(),
      links: getIt(),
      history: getIt(),
      syncLog: getIt(),
      settings: getIt(),
      ruleSets: getIt(),
      // A new RulesEngine per run: its factory reads `tz.local` when the run
      // asks, after `SyncService.run` has refreshed the device zone. `zone`
      // stays at its default (`tz.local`, read at call time) for the same
      // reason.
      rulesEngine: () => getIt<RulesEngine>(),
      engine: getIt(),
      recorder: getIt(),
      platform: getIt(),
      buildSource: (config, state, zone) =>
          getIt<SourceFactory>().create(config, state, zone: zone),
    ),
  );
  getIt.registerLazySingleton<ForegroundSync>(
    () => ForegroundSync(sync: getIt()),
    dispose: (f) => f.dispose(),
  );

  // The screens' services (Plan 5). Lazy like the rest, so the headless sync
  // engine, which calls this too, resolves only what it uses.
  getIt.registerLazySingleton<SyncRunner>(() => _screenSync);
  getIt.registerLazySingleton<UiPlatform>(UiPlatform.new);
  getIt.registerLazySingleton(() => AppSettings(getIt()));
  getIt.registerLazySingleton(
    () => OnboardingGate(getIt()),
    dispose: (g) => g.dispose(),
  );
  getIt.registerLazySingleton(
    () => SourceStatusLoader(
      sources: getIt(),
      syncLog: getIt(),
      appSettings: getIt(),
    ),
  );
  getIt.registerLazySingleton(
    () => MeetingPlanner(
      sources: getIt(),
      occurrences: getIt(),
      links: getIt(),
      history: getIt(),
      settings: getIt(),
      ruleSets: getIt(),
      rulesEngine: () => getIt<RulesEngine>(),
    ),
  );
  // Edits re-plan from the cache and fetch nothing.
  getIt.registerLazySingleton(
    () => ReplanScheduler(replan: () => _screenSync(SyncTrigger.edit)),
    dispose: (r) => r.dispose(),
  );
  // Listens through the one registered SyncPlatform: the channel has a single
  // method-call handler, and a second platform that listened and then
  // cancelled would clear this one's.
  getIt.registerLazySingleton(
    () => AppLifecycle(db: getIt(), platform: getIt(), replan: getIt()),
    dispose: (l) => l.dispose(),
  );
  getIt.registerLazySingleton(
    () => RestoreGuard(
      db: getIt(),
      platform: getIt(),
      appSettings: getIt(),
      sources: getIt(),
      admin: getIt(),
    ),
  );
  getIt.registerLazySingleton(
    () => HealthMonitor(engine: getIt(), statuses: getIt()),
    dispose: (m) => m.dispose(),
  );
  getIt.registerLazySingleton(
    () => IcsLinkProbe(client: getIt(), deviceZone: () => tz.local.name),
  );
  // Every repository it uses is built on the one registered AppDatabase, so an
  // import's writes join its transaction.
  getIt.registerLazySingleton(
    () => SettingsTransfer(
      db: getIt(),
      profiles: getIt(),
      rules: getIt(),
      settings: getIt(),
      sources: getIt(),
      appSettings: getIt(),
    ),
  );
  // A factory: each screen controller gets its own loader.
  getIt.registerFactory(
    () => AgendaLoader(
      planner: getIt(),
      statuses: getIt(),
      settings: getIt(),
      appSettings: getIt(),
      zone: () => tz.local,
    ),
  );
}

/// The sync behind [SyncRunner] (pull-to-refresh, Sync now, after adding or
/// re-linking a source) and behind the re-plan an edit asks for.
///
/// While a restore is unsafe ([RestoreGuard.unsafe]: the guard found a restored
/// backup and could not make it safe, so its sources are still enabled) neither
/// may plan or fetch. They run the guard again first, which finishes the
/// restore if whatever stopped it has passed, and answer `busy` while it has
/// not. That is the answer of a held sync lock, so a re-plan is tried again by
/// `ReplanScheduler` and the screens tell the user to try again.
///
/// The normal path does not call the guard at all. Running it before every sync
/// could mistake a user's first source for an old backup.
Future<SyncReport> _screenSync(SyncTrigger trigger) async {
  final guard = getIt<RestoreGuard>();
  if (guard.unsafe && await guard.run() == RestoreOutcome.unsafe) {
    return SyncReport(trigger: trigger, outcome: SyncRunOutcome.busy);
  }
  return getIt<SyncService>().run(trigger);
}
