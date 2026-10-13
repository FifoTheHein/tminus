import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/theme_mode_controller.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/settings_repository.dart';

import '../core/storage/test_database.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = openTestDatabase();
    settings = SettingsRepository(db);
  });
  tearDown(() => db.close());

  /// Captures what the controller logs, and puts `debugPrint` back after.
  List<String> captureLog() {
    final logged = <String>[];
    final realDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = realDebugPrint);
    return logged;
  }

  test('load reads the stored mode', () async {
    await settings.setString(ThemeModeController.settingsKey, 'dark');
    final controller = ThemeModeController(settings: () => settings);
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.load();

    expect(controller.mode, ThemeMode.dark);
    expect(notified, 1);
  });

  test('setting the mode stores it', () async {
    final controller = ThemeModeController(settings: () => settings);
    var notified = 0;
    controller.addListener(() => notified++);

    controller.mode = ThemeMode.light;
    expect(controller.mode, ThemeMode.light);
    expect(notified, 1);

    // The write is not awaited by the setter: wait for it to land.
    await settings
        .watchString(ThemeModeController.settingsKey)
        .firstWhere((v) => v == 'light')
        .timeout(const Duration(seconds: 2));

    // A second controller on the same database starts from the stored mode.
    final next = ThemeModeController(settings: () => settings);
    await next.load();
    expect(next.mode, ThemeMode.light);

    // Setting the same mode again changes nothing and tells nobody.
    controller.mode = ThemeMode.light;
    expect(notified, 1);
  });

  test('an unknown stored name keeps the current mode', () async {
    await settings.setString(ThemeModeController.settingsKey, 'sepia');
    final controller = ThemeModeController(
      initial: ThemeMode.light,
      settings: () => settings,
    );
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.load();

    expect(controller.mode, ThemeMode.light);
    expect(notified, 0);
  });

  test('a failing store is logged, not thrown', () async {
    final logged = captureLog();
    final controller = ThemeModeController(
      settings: () => throw StateError('x'),
    );

    await controller.load();
    expect(controller.mode, ThemeMode.system);

    controller.mode = ThemeMode.dark;
    await pumpEventQueue();

    // The choice still applies for this run.
    expect(controller.mode, ThemeMode.dark);
    // Each failure is logged by its type alone, never by its message.
    expect(logged, [
      'Reading the theme mode failed: StateError',
      'Saving the theme mode failed: StateError',
    ]);
  });
}
