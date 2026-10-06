import 'package:flutter/material.dart';

/// Holds the user's System / Dark / Light choice.
class ThemeModeController extends ChangeNotifier {
  ThemeModeController({ThemeMode initial = ThemeMode.system}) : _mode = initial;

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  set mode(ThemeMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
  }
}
