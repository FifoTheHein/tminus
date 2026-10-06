import 'package:flutter/material.dart';

/// T-Minus colours that have no Material 3 role: calendar colours, status
/// colours (health and sync only) and alert-strength chip tokens.
@immutable
class TMinusColors extends ThemeExtension<TMinusColors> {
  const TMinusColors({
    required this.calendarBlue,
    required this.calendarGreen,
    required this.calendarPurple,
    required this.calendarOrange,
    required this.calendarPink,
    required this.calendarTeal,
    required this.statusOk,
    required this.statusOkContainer,
    required this.onStatusOkContainer,
    required this.statusWarn,
    required this.statusWarnContainer,
    required this.onStatusWarnContainer,
    required this.statusError,
    required this.headsUpChipBorder,
    required this.headsUpChipFg,
    required this.alarmChipBg,
    required this.alarmChipFg,
    required this.tertiaryText,
  });

  /// Work Outlook (default).
  final Color calendarBlue;

  /// Personal Google.
  final Color calendarGreen;
  final Color calendarPurple;
  final Color calendarOrange;
  final Color calendarPink;
  final Color calendarTeal;

  /// Check icons, synced dot.
  final Color statusOk;

  /// "All good" card.
  final Color statusOkContainer;
  final Color onStatusOkContainer;

  /// Stale feed, battery optimised.
  final Color statusWarn;

  /// Feed-stale chip.
  final Color statusWarnContainer;
  final Color onStatusWarnContainer;

  /// Health tab dot.
  final Color statusError;

  /// Outline style = Heads-up.
  final Color headsUpChipBorder;

  /// Bell icon + offset on a heads-up chip.
  final Color headsUpChipFg;

  /// Solid style = Alarm.
  final Color alarmChipBg;

  /// Alarm icon + offset on an alarm chip.
  final Color alarmChipFg;

  /// Reason line, meta captions.
  final Color tertiaryText;

  static const TMinusColors dark = TMinusColors(
    calendarBlue: Color(0xFF6AA0F5),
    calendarGreen: Color(0xFF5BC48A),
    calendarPurple: Color(0xFFB48CF0),
    calendarOrange: Color(0xFFE89A5B),
    calendarPink: Color(0xFFE07AA8),
    calendarTeal: Color(0xFF7FC7D9),
    statusOk: Color(0xFF5BC48A),
    statusOkContainer: Color(0xFF132619),
    onStatusOkContainer: Color(0xFFC8F2D6),
    statusWarn: Color(0xFFE8B04B),
    statusWarnContainer: Color(0xFF2A2210),
    onStatusWarnContainer: Color(0xFFF2CB7A),
    statusError: Color(0xFFF07B6E),
    headsUpChipBorder: Color(0xFF5E6470),
    headsUpChipFg: Color(0xFFC9CDD4),
    alarmChipBg: Color(0xFFE6E7EA),
    alarmChipFg: Color(0xFF111214),
    tertiaryText: Color(0xFF80858F),
  );

  static const TMinusColors light = TMinusColors(
    calendarBlue: Color(0xFF2F6FD6),
    calendarGreen: Color(0xFF1E8A52),
    calendarPurple: Color(0xFF7A4FC9),
    calendarOrange: Color(0xFFB4621F),
    calendarPink: Color(0xFFB23F75),
    calendarTeal: Color(0xFF2B8197),
    statusOk: Color(0xFF1E8A52),
    statusOkContainer: Color(0xFFDDF3E5),
    onStatusOkContainer: Color(0xFF145C37),
    statusWarn: Color(0xFF9A6A00),
    statusWarnContainer: Color(0xFFFBEFCF),
    onStatusWarnContainer: Color(0xFF6B4A00),
    statusError: Color(0xFFBA1A1A),
    headsUpChipBorder: Color(0xFF9AA0A8),
    headsUpChipFg: Color(0xFF3A3F46),
    alarmChipBg: Color(0xFF16181B),
    alarmChipFg: Color(0xFFFFFFFF),
    tertiaryText: Color(0xFF6B7078),
  );

  /// The calendar colours in picker order.
  List<Color> get calendarColors => [
    calendarBlue,
    calendarGreen,
    calendarPurple,
    calendarOrange,
    calendarPink,
    calendarTeal,
  ];

  @override
  TMinusColors copyWith({
    Color? calendarBlue,
    Color? calendarGreen,
    Color? calendarPurple,
    Color? calendarOrange,
    Color? calendarPink,
    Color? calendarTeal,
    Color? statusOk,
    Color? statusOkContainer,
    Color? onStatusOkContainer,
    Color? statusWarn,
    Color? statusWarnContainer,
    Color? onStatusWarnContainer,
    Color? statusError,
    Color? headsUpChipBorder,
    Color? headsUpChipFg,
    Color? alarmChipBg,
    Color? alarmChipFg,
    Color? tertiaryText,
  }) {
    return TMinusColors(
      calendarBlue: calendarBlue ?? this.calendarBlue,
      calendarGreen: calendarGreen ?? this.calendarGreen,
      calendarPurple: calendarPurple ?? this.calendarPurple,
      calendarOrange: calendarOrange ?? this.calendarOrange,
      calendarPink: calendarPink ?? this.calendarPink,
      calendarTeal: calendarTeal ?? this.calendarTeal,
      statusOk: statusOk ?? this.statusOk,
      statusOkContainer: statusOkContainer ?? this.statusOkContainer,
      onStatusOkContainer: onStatusOkContainer ?? this.onStatusOkContainer,
      statusWarn: statusWarn ?? this.statusWarn,
      statusWarnContainer: statusWarnContainer ?? this.statusWarnContainer,
      onStatusWarnContainer:
          onStatusWarnContainer ?? this.onStatusWarnContainer,
      statusError: statusError ?? this.statusError,
      headsUpChipBorder: headsUpChipBorder ?? this.headsUpChipBorder,
      headsUpChipFg: headsUpChipFg ?? this.headsUpChipFg,
      alarmChipBg: alarmChipBg ?? this.alarmChipBg,
      alarmChipFg: alarmChipFg ?? this.alarmChipFg,
      tertiaryText: tertiaryText ?? this.tertiaryText,
    );
  }

  @override
  TMinusColors lerp(TMinusColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TMinusColors(
      calendarBlue: l(calendarBlue, other.calendarBlue),
      calendarGreen: l(calendarGreen, other.calendarGreen),
      calendarPurple: l(calendarPurple, other.calendarPurple),
      calendarOrange: l(calendarOrange, other.calendarOrange),
      calendarPink: l(calendarPink, other.calendarPink),
      calendarTeal: l(calendarTeal, other.calendarTeal),
      statusOk: l(statusOk, other.statusOk),
      statusOkContainer: l(statusOkContainer, other.statusOkContainer),
      onStatusOkContainer: l(onStatusOkContainer, other.onStatusOkContainer),
      statusWarn: l(statusWarn, other.statusWarn),
      statusWarnContainer: l(statusWarnContainer, other.statusWarnContainer),
      onStatusWarnContainer: l(
        onStatusWarnContainer,
        other.onStatusWarnContainer,
      ),
      statusError: l(statusError, other.statusError),
      headsUpChipBorder: l(headsUpChipBorder, other.headsUpChipBorder),
      headsUpChipFg: l(headsUpChipFg, other.headsUpChipFg),
      alarmChipBg: l(alarmChipBg, other.alarmChipBg),
      alarmChipFg: l(alarmChipFg, other.alarmChipFg),
      tertiaryText: l(tertiaryText, other.tertiaryText),
    );
  }
}
