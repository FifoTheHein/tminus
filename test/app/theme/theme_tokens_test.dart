import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/theme/tminus_theme.dart';

import '../../design_system_fixture.dart';

/// Builds a MaterialApp in [mode] and returns the ThemeData a widget sees.
Future<ThemeData> pumpTheme(WidgetTester tester, ThemeMode mode) async {
  late ThemeData theme;
  await tester.pumpWidget(
    MaterialApp(
      theme: TMinusTheme.light(),
      darkTheme: TMinusTheme.dark(),
      themeMode: mode,
      home: Builder(
        builder: (context) {
          theme = Theme.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return theme;
}

Map<String, Color> schemeTokens(ColorScheme s) => {
  'primary': s.primary,
  'onPrimary': s.onPrimary,
  'primaryContainer': s.primaryContainer,
  'onPrimaryContainer': s.onPrimaryContainer,
  'surface': s.surface,
  'onSurface': s.onSurface,
  'onSurfaceVariant': s.onSurfaceVariant,
  'surfaceContainerLow': s.surfaceContainerLow,
  'surfaceContainer': s.surfaceContainer,
  'surfaceContainerHigh': s.surfaceContainerHigh,
  'surfaceContainerHighest': s.surfaceContainerHighest,
  'outline': s.outline,
  'outlineVariant': s.outlineVariant,
  'error': s.error,
  'onError': s.onError,
  'errorContainer': s.errorContainer,
  'onErrorContainer': s.onErrorContainer,
  'inverseSurface': s.inverseSurface,
  'onInverseSurface': s.onInverseSurface,
  'scrim': s.scrim,
};

Map<String, Color> extensionTokens(TMinusColors c) => {
  'calendarBlue': c.calendarBlue,
  'calendarGreen': c.calendarGreen,
  'calendarPurple': c.calendarPurple,
  'calendarOrange': c.calendarOrange,
  'calendarPink': c.calendarPink,
  'calendarTeal': c.calendarTeal,
  'statusOk': c.statusOk,
  'statusOkContainer': c.statusOkContainer,
  'onStatusOkContainer': c.onStatusOkContainer,
  'statusWarn': c.statusWarn,
  'statusWarnContainer': c.statusWarnContainer,
  'onStatusWarnContainer': c.onStatusWarnContainer,
  'statusError': c.statusError,
  'headsUpChipBorder': c.headsUpChipBorder,
  'headsUpChipFg': c.headsUpChipFg,
  'alarmChipBg': c.alarmChipBg,
  'alarmChipFg': c.alarmChipFg,
  'tertiaryText': c.tertiaryText,
};

void main() {
  test('fixture parsed every design-system colour row', () {
    expect(designSystemColors, hasLength(38));
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    final isDark = mode == ThemeMode.dark;
    Color expected(String token) {
      final row = designSystemColors[token]!;
      return isDark ? row.dark : row.light;
    }

    group('${mode.name} theme', () {
      testWidgets('is Material 3 with the right brightness', (tester) async {
        final theme = await pumpTheme(tester, mode);
        expect(theme.useMaterial3, isTrue);
        expect(
          theme.colorScheme.brightness,
          isDark ? Brightness.dark : Brightness.light,
        );
        expect(theme.scaffoldBackgroundColor, expected('surface'));
      });

      testWidgets('key tokens match the design system', (tester) async {
        final theme = await pumpTheme(tester, mode);
        final c = theme.extension<TMinusColors>()!;
        // Spelled out so a failure names the token directly.
        expect(theme.colorScheme.primary, expected('primary'));
        expect(theme.colorScheme.surface, expected('surface'));
        expect(c.calendarBlue, expected('calendarBlue'));
        expect(c.calendarGreen, expected('calendarGreen'));
        expect(c.calendarPurple, expected('calendarPurple'));
        expect(c.calendarOrange, expected('calendarOrange'));
        expect(c.calendarPink, expected('calendarPink'));
        expect(c.calendarTeal, expected('calendarTeal'));
        expect(c.statusOk, expected('statusOk'));
        expect(c.statusOkContainer, expected('statusOkContainer'));
        expect(c.onStatusOkContainer, expected('onStatusOkContainer'));
        expect(c.statusWarn, expected('statusWarn'));
        expect(c.statusWarnContainer, expected('statusWarnContainer'));
        expect(c.onStatusWarnContainer, expected('onStatusWarnContainer'));
        expect(c.statusError, expected('statusError'));
      });

      testWidgets('every named colour token matches the design system', (
        tester,
      ) async {
        final theme = await pumpTheme(tester, mode);
        final actual = {
          ...schemeTokens(theme.colorScheme),
          ...extensionTokens(theme.extension<TMinusColors>()!),
        };
        expect(actual.keys.toSet(), designSystemColors.keys.toSet());
        for (final token in designSystemColors.keys) {
          expect(actual[token], expected(token), reason: token);
        }
      });

      testWidgets('tonal and nav-indicator roles use primaryContainer', (
        tester,
      ) async {
        final s = (await pumpTheme(tester, mode)).colorScheme;
        expect(s.secondaryContainer, s.primaryContainer);
        expect(s.onSecondaryContainer, s.onPrimaryContainer);
      });

      testWidgets('bottom sheets use surfaceContainerHigh, scrim 64%, '
          'sheet radius', (tester) async {
        final theme = await pumpTheme(tester, mode);
        final sheet = theme.bottomSheetTheme;
        expect(sheet.backgroundColor, expected('surfaceContainerHigh'));
        expect(
          sheet.modalBarrierColor,
          expected('scrim').withValues(alpha: 0.64),
        );
        expect(
          (sheet.shape! as RoundedRectangleBorder).borderRadius,
          const BorderRadius.vertical(top: Radius.circular(28)),
        );
      });

      testWidgets('TextTheme matches the UI type scale', (tester) async {
        final t = (await pumpTheme(tester, mode)).textTheme;
        // name: (size, line height, weight, tracking em)
        final scale =
            <String, (TextStyle?, double, double, FontWeight, double)>{
              'headlineLarge': (
                t.headlineLarge,
                34,
                40,
                FontWeight.w500,
                -0.02,
              ),
              'displaySmall': (t.displaySmall, 32, 37, FontWeight.w500, -0.01),
              'headlineMedium': (
                t.headlineMedium,
                28,
                34,
                FontWeight.w500,
                -0.01,
              ),
              'headlineSmall': (
                t.headlineSmall,
                26,
                32,
                FontWeight.w500,
                -0.01,
              ),
              'titleLarge': (t.titleLarge, 20, 26, FontWeight.w500, 0),
              'titleMedium': (t.titleMedium, 16, 20, FontWeight.w500, 0),
              'bodyLarge': (t.bodyLarge, 16, 24, FontWeight.w400, 0),
              'bodyMedium': (t.bodyMedium, 14, 20, FontWeight.w400, 0),
              'bodySmall': (t.bodySmall, 12, 16, FontWeight.w400, 0),
              'labelLarge': (t.labelLarge, 14, 20, FontWeight.w500, 0),
              'labelMedium': (t.labelMedium, 12, 16, FontWeight.w500, 0),
            };
        for (final MapEntry(key: name, value: v) in scale.entries) {
          final (style, size, line, weight, em) = v;
          expect(style!.fontFamily, 'IBMPlexSans', reason: name);
          expect(style.fontSize, size, reason: name);
          expect(style.height! * size, closeTo(line, 1e-9), reason: name);
          expect(style.fontWeight, weight, reason: name);
          expect(style.letterSpacing, closeTo(em * size, 1e-9), reason: name);
        }
        // Text colour still follows the scheme.
        expect(t.bodyLarge!.color, expected('onSurface'));
      });

      testWidgets('TMinusType matches the numeral styles', (tester) async {
        final type = (await pumpTheme(tester, mode)).extension<TMinusType>()!;
        // name: (style, size, line height, weight, tracking em)
        final scale = <String, (TextStyle, double, double, FontWeight, double)>{
          'countdownXL': (type.countdownXL, 120, 114, FontWeight.w500, -0.05),
          'countdownXLUnit': (type.countdownXLUnit, 40, 40, FontWeight.w500, 0),
          'countdownL': (type.countdownL, 64, 64, FontWeight.w500, -0.04),
          'countdownLUnit': (type.countdownLUnit, 24, 24, FontWeight.w500, 0),
          'timeLarge': (type.timeLarge, 18, 24, FontWeight.w400, 0),
          'time': (type.time, 12, 16, FontWeight.w400, 0),
          'chipNumeral': (type.chipNumeral, 12, 16, FontWeight.w400, 0),
          'overline': (type.overline, 11, 16, FontWeight.w400, 0.14),
        };
        for (final MapEntry(key: name, value: v) in scale.entries) {
          final (style, size, line, weight, em) = v;
          expect(style.fontFamily, 'IBMPlexMono', reason: name);
          expect(style.fontSize, size, reason: name);
          expect(style.height! * size, closeTo(line, 1e-9), reason: name);
          expect(style.fontWeight, weight, reason: name);
          expect(style.letterSpacing, closeTo(em * size, 1e-9), reason: name);
        }
        expect(type.chipNumeralFor(alarm: true).fontWeight, FontWeight.w600);
        expect(type.chipNumeralFor(alarm: false).fontWeight, FontWeight.w400);
      });
    });
  }

  test('spacing and radii match the design system', () {
    expect(
      [
        TMinusSpacing.xxs,
        TMinusSpacing.xs,
        TMinusSpacing.sm,
        TMinusSpacing.md,
        TMinusSpacing.lg,
        TMinusSpacing.xl,
        TMinusSpacing.xxl,
        TMinusSpacing.minTap,
      ],
      [4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 32.0, 48.0],
    );
    expect(
      [
        TMinusRadii.xs,
        TMinusRadii.sm,
        TMinusRadii.md,
        TMinusRadii.lg,
        TMinusRadii.xl,
        TMinusRadii.sheet,
        TMinusRadii.pill,
      ],
      [4.0, 8.0, 12.0, 16.0, 20.0, 28.0, 999.0],
    );
  });

  test('lerp between dark and light reaches each end', () {
    expect(
      TMinusColors.dark.lerp(TMinusColors.light, 1).calendarBlue,
      TMinusColors.light.calendarBlue,
    );
    expect(
      TMinusColors.dark.lerp(TMinusColors.light, 0).statusOk,
      TMinusColors.dark.statusOk,
    );
  });

  group('bundled fonts', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    for (final path in [
      'assets/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf',
      'assets/fonts/ibm-plex-sans/IBMPlexSans-Medium.ttf',
      'assets/fonts/ibm-plex-sans/IBMPlexSans-SemiBold.ttf',
      'assets/fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf',
      'assets/fonts/ibm-plex-mono/IBMPlexMono-Medium.ttf',
      'assets/fonts/ibm-plex-mono/IBMPlexMono-SemiBold.ttf',
      'assets/fonts/ibm-plex-sans/OFL.txt',
      'assets/fonts/ibm-plex-mono/OFL.txt',
    ]) {
      test('$path is in the asset bundle', () async {
        final data = await rootBundle.load(path);
        expect(data.lengthInBytes, greaterThan(0));
      });
    }
  });
}
