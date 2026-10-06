import 'package:get_it/get_it.dart';

import 'theme_mode_controller.dart';

final GetIt getIt = GetIt.instance;

/// Registers app-wide services. Call once before [runApp].
void configureDependencies() {
  getIt.registerLazySingleton<ThemeModeController>(ThemeModeController.new);
}
