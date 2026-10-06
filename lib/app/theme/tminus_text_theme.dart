import 'package:flutter/material.dart';

import 'tminus_fonts.dart';

/// UI type scale (IBM Plex Sans) from the T-Minus design system.
///
/// Sizes are size/line-height in logical pixels; tracking is converted from
/// em to logical pixels. Roles the design system does not list keep the
/// Material 3 defaults, in IBM Plex Sans via ThemeData.fontFamily.
abstract final class TMinusTextTheme {
  static TextStyle _sans(
    double size,
    double lineHeight,
    FontWeight weight, {
    double trackingEm = 0,
  }) {
    return TextStyle(
      fontFamily: TMinusFonts.sans,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: trackingEm * size,
    );
  }

  static final TextTheme textTheme = TextTheme(
    headlineLarge: _sans(34, 40, FontWeight.w500, trackingEm: -0.02),
    displaySmall: _sans(32, 37, FontWeight.w500, trackingEm: -0.01),
    headlineMedium: _sans(28, 34, FontWeight.w500, trackingEm: -0.01),
    headlineSmall: _sans(26, 32, FontWeight.w500, trackingEm: -0.01),
    titleLarge: _sans(20, 26, FontWeight.w500),
    titleMedium: _sans(16, 20, FontWeight.w500),
    bodyLarge: _sans(16, 24, FontWeight.w400),
    bodyMedium: _sans(14, 20, FontWeight.w400),
    bodySmall: _sans(12, 16, FontWeight.w400),
    labelLarge: _sans(14, 20, FontWeight.w500),
    labelMedium: _sans(12, 16, FontWeight.w500),
  );
}
