import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/theme/tminus_token_catalog.dart';

/// The native Compose alarm screen must use the same hex values as Flutter.
void main() {
  final xml = File('android/app/src/main/res/values/tminus_colors.xml')
      .readAsStringSync();
  final native = {
    for (final m in RegExp(
      r'<color name="tminus_(dark|light)_(\w+)">#([0-9A-F]{6})</color>',
    ).allMatches(xml))
      '${m.group(1)}.${m.group(2)}': '#${m.group(3)}',
  };

  final flutter = {
    for (final group in tminusColorTokenGroups())
      for (final t in group.tokens) ...{
        'dark.${t.name}': hexRgb(t.dark),
        'light.${t.name}': hexRgb(t.light),
      },
  };

  test('tminus_colors.xml has exactly the Flutter colour tokens', () {
    expect(native.keys.toSet(), flutter.keys.toSet());
  });

  test('tminus_colors.xml values match the Flutter theme', () {
    for (final key in flutter.keys) {
      expect(native[key], flutter[key], reason: key);
    }
  });
}
