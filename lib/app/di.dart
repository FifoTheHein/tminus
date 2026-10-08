import 'package:get_it/get_it.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/engine/alarm_engine.dart';
import '../core/rules/rules_engine.dart';
import '../core/storage/alert_history_repository.dart';
import '../core/storage/app_database.dart';
import '../core/storage/occurrence_repository.dart';
import '../core/storage/override_repository.dart';
import '../core/storage/profile_repository.dart';
import '../core/storage/rule_repository.dart';
import '../core/storage/rule_set_loader.dart';
import '../core/storage/settings_repository.dart';
import '../core/storage/source_repository.dart';
import '../core/storage/sync_log_repository.dart';
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
  // Plan 4 sets `tz.local` from the device zone at startup; until then it
  // is UTC.
  getIt.registerFactory(() => RulesEngine(zone: tz.local));
}
