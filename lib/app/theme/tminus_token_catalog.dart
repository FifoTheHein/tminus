import 'package:flutter/material.dart';

import 'tminus_color_schemes.dart';
import 'tminus_colors.dart';

/// One named colour token with its dark and light values.
typedef ColorToken = ({String name, Color dark, Color light});

/// A titled group of colour tokens, as on the design-system sheet.
typedef ColorTokenGroup = ({String title, List<ColorToken> tokens});

/// Every colour token the design system names, grouped like the sheet.
///
/// Used by the token preview screen and to check that the native Android
/// export (res/values/tminus_colors.xml) carries the same values.
List<ColorTokenGroup> tminusColorTokenGroups() {
  const d = TMinusColorSchemes.dark;
  const l = TMinusColorSchemes.light;
  const dx = TMinusColors.dark;
  const lx = TMinusColors.light;

  ColorToken scheme(String name, Color Function(ColorScheme) pick) =>
      (name: name, dark: pick(d), light: pick(l));
  ColorToken ext(String name, Color Function(TMinusColors) pick) =>
      (name: name, dark: pick(dx), light: pick(lx));

  return [
    (
      title: 'Material roles',
      tokens: [
        scheme('primary', (s) => s.primary),
        scheme('onPrimary', (s) => s.onPrimary),
        scheme('primaryContainer', (s) => s.primaryContainer),
        scheme('onPrimaryContainer', (s) => s.onPrimaryContainer),
        scheme('surface', (s) => s.surface),
        scheme('onSurface', (s) => s.onSurface),
        scheme('onSurfaceVariant', (s) => s.onSurfaceVariant),
        scheme('surfaceContainerLow', (s) => s.surfaceContainerLow),
        scheme('surfaceContainer', (s) => s.surfaceContainer),
        scheme('surfaceContainerHigh', (s) => s.surfaceContainerHigh),
        scheme('surfaceContainerHighest', (s) => s.surfaceContainerHighest),
        scheme('outline', (s) => s.outline),
        scheme('outlineVariant', (s) => s.outlineVariant),
        scheme('error', (s) => s.error),
        scheme('onError', (s) => s.onError),
        scheme('errorContainer', (s) => s.errorContainer),
        scheme('onErrorContainer', (s) => s.onErrorContainer),
        scheme('inverseSurface', (s) => s.inverseSurface),
        scheme('onInverseSurface', (s) => s.onInverseSurface),
        scheme('scrim', (s) => s.scrim),
      ],
    ),
    (
      title: 'Calendar colours',
      tokens: [
        ext('calendarBlue', (c) => c.calendarBlue),
        ext('calendarGreen', (c) => c.calendarGreen),
        ext('calendarPurple', (c) => c.calendarPurple),
        ext('calendarOrange', (c) => c.calendarOrange),
        ext('calendarPink', (c) => c.calendarPink),
        ext('calendarTeal', (c) => c.calendarTeal),
      ],
    ),
    (
      title: 'Status (health & sync only)',
      tokens: [
        ext('statusOk', (c) => c.statusOk),
        ext('statusOkContainer', (c) => c.statusOkContainer),
        ext('onStatusOkContainer', (c) => c.onStatusOkContainer),
        ext('statusWarn', (c) => c.statusWarn),
        ext('statusWarnContainer', (c) => c.statusWarnContainer),
        ext('onStatusWarnContainer', (c) => c.onStatusWarnContainer),
        ext('statusError', (c) => c.statusError),
      ],
    ),
    (
      title: 'Alert strength',
      tokens: [
        ext('headsUpChipBorder', (c) => c.headsUpChipBorder),
        ext('headsUpChipFg', (c) => c.headsUpChipFg),
        ext('alarmChipBg', (c) => c.alarmChipBg),
        ext('alarmChipFg', (c) => c.alarmChipFg),
        ext('tertiaryText', (c) => c.tertiaryText),
      ],
    ),
  ];
}

/// `#RRGGBB` for an opaque colour.
String hexRgb(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
