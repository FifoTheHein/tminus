import 'package:flutter/material.dart';

import 'tminus_color_schemes.dart';
import 'tminus_colors.dart';
import 'tminus_fonts.dart';
import 'tminus_layout.dart';
import 'tminus_text_theme.dart';
import 'tminus_type.dart';

export 'tminus_color_schemes.dart';
export 'tminus_colors.dart';
export 'tminus_fonts.dart';
export 'tminus_layout.dart';
export 'tminus_text_theme.dart';
export 'tminus_type.dart';

/// Builds the T-Minus [ThemeData] for each brightness.
abstract final class TMinusTheme {
  static ThemeData dark() => _build(TMinusColorSchemes.dark, TMinusColors.dark);

  static ThemeData light() =>
      _build(TMinusColorSchemes.light, TMinusColors.light);

  static ThemeData _build(ColorScheme scheme, TMinusColors colors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: TMinusFonts.sans,
      textTheme: TMinusTextTheme.textTheme,
      scaffoldBackgroundColor: scheme.surface,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        modalBarrierColor: scheme.scrim.withValues(
          alpha: TMinusColorSchemes.scrimOpacity,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TMinusRadii.sheet),
          ),
        ),
      ),
      extensions: [colors, TMinusType.standard],
    );
  }
}

/// Shorthand for the T-Minus theme extensions.
extension TMinusThemeContext on BuildContext {
  TMinusColors get tminusColors => Theme.of(this).extension<TMinusColors>()!;

  TMinusType get tminusType => Theme.of(this).extension<TMinusType>()!;
}
