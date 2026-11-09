import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';

/// The dark theme's six `calendar*` tokens as ARGB, in picker order. A source
/// stores one of these values, and both themes draw the stored value.
const calendarPalette = <int>[
  0xFF6AA0F5, // calendarBlue
  0xFF5BC48A, // calendarGreen
  0xFFB48CF0, // calendarPurple
  0xFFE89A5B, // calendarOrange
  0xFFE07AA8, // calendarPink
  0xFF7FC7D9, // calendarTeal
];

/// Six colour swatches with a ring around the chosen one (mockup 4b).
/// [selected] is an ARGB value; one that is not in [calendarPalette] marks
/// nothing.
class ColorPalettePicker extends StatelessWidget {
  const ColorPalettePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: TMinusSpacing.xxs,
      runSpacing: TMinusSpacing.xxs,
      children: [
        for (var i = 0; i < calendarPalette.length; i++)
          _Swatch(
            argb: calendarPalette[i],
            label: 'Colour ${i + 1}',
            selected: calendarPalette[i] == selected,
            onTap: () => onChanged(calendarPalette[i]),
          ),
      ],
    );
  }
}

/// A 44 dp circle (the coloured disc, with the ring when chosen) inside a
/// [TMinusSpacing.minTap] hit area.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.argb,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const double _circle = 44;
  static const double _disc = 32;

  final int argb;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkResponse(
        key: ValueKey('colour-$argb'),
        onTap: onTap,
        radius: TMinusSpacing.minTap / 2,
        child: SizedBox.square(
          dimension: TMinusSpacing.minTap,
          child: Center(
            child: Container(
              width: _circle,
              height: _circle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected ? Border.all(color: ring, width: 2) : null,
              ),
              child: Container(
                width: _disc,
                height: _disc,
                decoration: BoxDecoration(
                  color: Color(argb),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
