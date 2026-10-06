import 'package:flutter/painting.dart';

/// Colour token rows copied verbatim from the `renderVals()` script of
/// `T-Minus Design System.dc.html` (Claude Design project
/// b3ee1986-af3e-4399-9aeb-efd063edfd49). Format: t(name, dark, light, use).
///
/// This is the reference the theme is tested against. Update it only by
/// re-copying from the design file.
const String designSystemColorRows = r"""
          t('primary', '#B9CCE0', '#3D5A78', 'Switches on, now line, active nav, filled buttons'),
          t('onPrimary', '#111214', '#FFFFFF', 'Text/icons on primary'),
          t('primaryContainer', '#2E3A47', '#D3DEEA', 'Nav pill, tonal buttons, selected rows'),
          t('onPrimaryContainer', '#DDE7F2', '#16202B', 'Text on primaryContainer'),
          t('surface', '#111214', '#F4F5F7', 'App background'),
          t('onSurface', '#E6E7EA', '#16181B', 'Primary text'),
          t('onSurfaceVariant', '#9A9EA6', '#5E636B', 'Secondary text, time ranges'),
          t('surfaceContainerLow', '#16181B', '#FAFBFC', 'Skipped / empty-state cards'),
          t('surfaceContainer', '#1A1C20', '#FFFFFF', 'Event cards, nav bar, list groups'),
          t('surfaceContainerHigh', '#1E2125', '#E9ECF0', 'Bottom sheets'),
          t('surfaceContainerHighest', '#262A30', '#ECEEF1', 'Badges, nested cards, "Why" box'),
          t('outline', '#5E6470', '#9AA0A8', 'Field borders, heads-up chip border'),
          t('outlineVariant', '#24272C', '#DADDE2', 'Dividers'),
          t('error', '#FFB4AB', '#BA1A1A', 'Health problems, broken feeds'),
          t('onError', '#3A0B07', '#FFFFFF', 'Text on error'),
          t('errorContainer', '#2C1715', '#FFDAD6', 'Error banner, missed history row'),
          t('onErrorContainer', '#FFDAD5', '#410002', 'Text on errorContainer'),
          t('inverseSurface', '#E6E7EA', '#16181B', 'Alarm chip fill'),
          t('onInverseSurface', '#111214', '#FFFFFF', 'Alarm chip text'),
          t('scrim', '#040507', '#040507', 'Sheet backdrop at 64%')
          t('calendarBlue', '#6AA0F5', '#2F6FD6', 'Work Outlook (default)'),
          t('calendarGreen', '#5BC48A', '#1E8A52', 'Personal Google'),
          t('calendarPurple', '#B48CF0', '#7A4FC9', 'User-picked'),
          t('calendarOrange', '#E89A5B', '#B4621F', 'User-picked'),
          t('calendarPink', '#E07AA8', '#B23F75', 'User-picked'),
          t('calendarTeal', '#7FC7D9', '#2B8197', 'User-picked')
          t('statusOk', '#5BC48A', '#1E8A52', 'Check icons, synced dot'),
          t('statusOkContainer', '#132619', '#DDF3E5', '"All good" card'),
          t('onStatusOkContainer', '#C8F2D6', '#145C37', 'Text on ok container'),
          t('statusWarn', '#E8B04B', '#9A6A00', 'Stale feed, battery optimised'),
          t('statusWarnContainer', '#2A2210', '#FBEFCF', 'Feed-stale chip'),
          t('onStatusWarnContainer', '#F2CB7A', '#6B4A00', 'Text on warn container'),
          t('statusError', '#F07B6E', '#BA1A1A', 'Health tab dot (alias of error for icons)')
          t('headsUpChipBorder', '#5E6470', '#9AA0A8', 'Outline style = Heads-up'),
          t('headsUpChipFg', '#C9CDD4', '#3A3F46', 'Bell icon + offset'),
          t('alarmChipBg', '#E6E7EA', '#16181B', 'Solid style = Alarm'),
          t('alarmChipFg', '#111214', '#FFFFFF', 'Alarm icon + offset'),
          t('tertiaryText', '#80858F', '#6B7078', 'Reason line, meta captions')
""";

/// Parsed [designSystemColorRows]: token name → (dark, light).
final Map<String, ({Color dark, Color light})> designSystemColors = {
  for (final m in RegExp(
    r"t\('(\w+)', '#([0-9A-F]{6})', '#([0-9A-F]{6})'",
  ).allMatches(designSystemColorRows))
    m.group(1)!: (
      dark: Color(0xFF000000 | int.parse(m.group(2)!, radix: 16)),
      light: Color(0xFF000000 | int.parse(m.group(3)!, radix: 16)),
    ),
};
