/// Spacing scale from the T-Minus design system.
abstract final class TMinusSpacing {
  /// Chip gaps, icon-label.
  static const double xxs = 4.0;

  /// Card stack gap.
  static const double xs = 8.0;

  /// List side inset, row gap.
  static const double sm = 12.0;

  /// Card padding, sheet inset.
  static const double md = 16.0;

  /// Screen inset, section header.
  static const double lg = 20.0;

  /// Section break, alarm inset.
  static const double xl = 24.0;

  /// Bottom safe padding.
  static const double xxl = 32.0;

  /// Minimum touch target everywhere.
  static const double minTap = 48.0;
}

/// Corner radii from the T-Minus design system.
abstract final class TMinusRadii {
  /// NOW tag, calendar bar end.
  static const double xs = 4.0;

  /// Text fields, badges, status chips.
  static const double sm = 8.0;

  /// Inline fields.
  static const double md = 12.0;

  /// Event cards, list groups.
  static const double lg = 16.0;

  /// Status card, coalesced alarm card.
  static const double xl = 20.0;

  /// Bottom sheets (top corners only).
  static const double sheet = 28.0;

  /// Buttons, alert chips, switches.
  static const double pill = 999.0;
}
