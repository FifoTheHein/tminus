import 'package:flutter/material.dart';

/// Material 3 colour roles from the T-Minus design system ("Material roles").
///
/// The design system only names the roles below. Secondary and tertiary roles
/// alias the primary family so Material widgets that read them (navigation
/// indicator, tonal buttons) use the steel primary, as the design shows.
/// Roles the design system leaves out fall back to Flutter's defaults.
abstract final class TMinusColorSchemes {
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFB9CCE0),
    onPrimary: Color(0xFF111214),
    primaryContainer: Color(0xFF2E3A47),
    onPrimaryContainer: Color(0xFFDDE7F2),
    secondary: Color(0xFFB9CCE0),
    onSecondary: Color(0xFF111214),
    secondaryContainer: Color(0xFF2E3A47),
    onSecondaryContainer: Color(0xFFDDE7F2),
    tertiary: Color(0xFFB9CCE0),
    onTertiary: Color(0xFF111214),
    tertiaryContainer: Color(0xFF2E3A47),
    onTertiaryContainer: Color(0xFFDDE7F2),
    surface: Color(0xFF111214),
    onSurface: Color(0xFFE6E7EA),
    onSurfaceVariant: Color(0xFF9A9EA6),
    surfaceContainerLow: Color(0xFF16181B),
    surfaceContainer: Color(0xFF1A1C20),
    surfaceContainerHigh: Color(0xFF1E2125),
    surfaceContainerHighest: Color(0xFF262A30),
    outline: Color(0xFF5E6470),
    outlineVariant: Color(0xFF24272C),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF3A0B07),
    errorContainer: Color(0xFF2C1715),
    onErrorContainer: Color(0xFFFFDAD5),
    inverseSurface: Color(0xFFE6E7EA),
    onInverseSurface: Color(0xFF111214),
    scrim: Color(0xFF040507),
  );

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF3D5A78),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD3DEEA),
    onPrimaryContainer: Color(0xFF16202B),
    secondary: Color(0xFF3D5A78),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD3DEEA),
    onSecondaryContainer: Color(0xFF16202B),
    tertiary: Color(0xFF3D5A78),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD3DEEA),
    onTertiaryContainer: Color(0xFF16202B),
    surface: Color(0xFFF4F5F7),
    onSurface: Color(0xFF16181B),
    onSurfaceVariant: Color(0xFF5E636B),
    surfaceContainerLow: Color(0xFFFAFBFC),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceContainerHigh: Color(0xFFE9ECF0),
    surfaceContainerHighest: Color(0xFFECEEF1),
    outline: Color(0xFF9AA0A8),
    outlineVariant: Color(0xFFDADDE2),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    inverseSurface: Color(0xFF16181B),
    onInverseSurface: Color(0xFFFFFFFF),
    scrim: Color(0xFF040507),
  );

  /// Bottom-sheet backdrop opacity applied to [ColorScheme.scrim].
  static const double scrimOpacity = 0.64;
}
