import 'dart:async';

import 'package:flutter/material.dart';

import '../core/storage/settings_repository.dart';

/// Holds the user's System / Dark / Light choice and keeps it in settings
/// (`ui.themeMode`, Plan 5 decision 14).
class ThemeModeController extends ChangeNotifier {
  ThemeModeController({ThemeMode initial = ThemeMode.system, this._settings})
    : _mode = initial;

  static const settingsKey = 'ui.themeMode';

  /// Resolved on first use, so a controller in a test without a database
  /// never opens one.
  final SettingsRepository Function()? _settings;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  set mode(ThemeMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
    unawaited(_save(value));
  }

  /// Reads the stored choice; call once before `runApp`. Never throws.
  Future<void> load() async {
    try {
      final stored = await _settings?.call().getString(settingsKey);
      final m = ThemeMode.values.asNameMap()[stored];
      if (m != null && m != _mode) {
        _mode = m;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Reading the theme mode failed: ${e.runtimeType}');
    }
  }

  Future<void> _save(ThemeMode m) async {
    try {
      await _settings?.call().setString(settingsKey, m.name);
    } catch (e) {
      debugPrint('Saving the theme mode failed: ${e.runtimeType}');
    }
  }
}
