import 'package:flutter/material.dart';

import 'tminus_fonts.dart';

/// Numeral styles (IBM Plex Mono) from the T-Minus design system: countdowns,
/// time ranges, alert-chip offsets and the overline label.
///
/// Styles carry no colour, so they inherit it from the surrounding text.
@immutable
class TMinusType extends ThemeExtension<TMinusType> {
  const TMinusType({
    required this.countdownXL,
    required this.countdownXLUnit,
    required this.countdownL,
    required this.countdownLUnit,
    required this.timeLarge,
    required this.time,
    required this.chipNumeral,
    required this.overline,
  });

  /// Alarm-screen countdown: 120/114 · w500 · −5%.
  final TextStyle countdownXL;

  /// Unit after [countdownXL] ("min"): 40.
  final TextStyle countdownXLUnit;

  /// Agenda countdown: 64/64 · w500 · −4%.
  final TextStyle countdownL;

  /// Unit after [countdownL]: 24.
  final TextStyle countdownLUnit;

  /// Alarm time range: 18/24 · w400.
  final TextStyle timeLarge;

  /// Card time range: 12/16 · w400.
  final TextStyle time;

  /// Alert-chip offset: 12/16, w400 for heads-up. Use [chipNumeralFor] to get
  /// the w600 alarm weight.
  final TextStyle chipNumeral;

  /// Section labels such as "NEXT ALARM IN": 11/16 · w400 · +14% · uppercase.
  /// The text itself must be uppercased by the caller.
  final TextStyle overline;

  /// [chipNumeral] at w600 for alarm chips, w400 for heads-up chips.
  TextStyle chipNumeralFor({required bool alarm}) =>
      alarm ? chipNumeral.copyWith(fontWeight: FontWeight.w600) : chipNumeral;

  static TextStyle _mono(
    double size,
    double lineHeight,
    FontWeight weight, {
    double trackingEm = 0,
  }) {
    return TextStyle(
      fontFamily: TMinusFonts.mono,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: trackingEm * size,
    );
  }

  static final TMinusType standard = TMinusType(
    countdownXL: _mono(120, 114, FontWeight.w500, trackingEm: -0.05),
    countdownXLUnit: _mono(40, 40, FontWeight.w500),
    countdownL: _mono(64, 64, FontWeight.w500, trackingEm: -0.04),
    countdownLUnit: _mono(24, 24, FontWeight.w500),
    timeLarge: _mono(18, 24, FontWeight.w400),
    time: _mono(12, 16, FontWeight.w400),
    chipNumeral: _mono(12, 16, FontWeight.w400),
    overline: _mono(11, 16, FontWeight.w400, trackingEm: 0.14),
  );

  @override
  TMinusType copyWith({
    TextStyle? countdownXL,
    TextStyle? countdownXLUnit,
    TextStyle? countdownL,
    TextStyle? countdownLUnit,
    TextStyle? timeLarge,
    TextStyle? time,
    TextStyle? chipNumeral,
    TextStyle? overline,
  }) {
    return TMinusType(
      countdownXL: countdownXL ?? this.countdownXL,
      countdownXLUnit: countdownXLUnit ?? this.countdownXLUnit,
      countdownL: countdownL ?? this.countdownL,
      countdownLUnit: countdownLUnit ?? this.countdownLUnit,
      timeLarge: timeLarge ?? this.timeLarge,
      time: time ?? this.time,
      chipNumeral: chipNumeral ?? this.chipNumeral,
      overline: overline ?? this.overline,
    );
  }

  @override
  TMinusType lerp(TMinusType? other, double t) {
    if (other == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return TMinusType(
      countdownXL: l(countdownXL, other.countdownXL),
      countdownXLUnit: l(countdownXLUnit, other.countdownXLUnit),
      countdownL: l(countdownL, other.countdownL),
      countdownLUnit: l(countdownLUnit, other.countdownLUnit),
      timeLarge: l(timeLarge, other.timeLarge),
      time: l(time, other.time),
      chipNumeral: l(chipNumeral, other.chipNumeral),
      overline: l(overline, other.overline),
    );
  }
}
