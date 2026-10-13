import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/engine/alarm_engine.dart';
import '../core/rules/rules_engine.dart';
import '../core/sources/device_calendar_api.dart';
import '../core/sources/fast_alarms.dart';
import '../core/sources/feed_body_cache.dart';
import '../core/sources/source_admin.dart';
import '../core/sources/source_factory.dart';
import '../core/sources/source_secrets.dart';
import '../core/storage/alert_history_repository.dart';
import '../core/storage/app_database.dart';
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
import '../core/sync/sync_platform.dart';
import '../core/sync/sync_service.dart';
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

  getIt.registerLazySingleton<ThemeModeController>(ThemeModeController.new);
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
}
