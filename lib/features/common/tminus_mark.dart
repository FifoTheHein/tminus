import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';

/// The launcher icon, [size] dp across. It always uses the dark scheme's
/// colours, in the light theme too, so that it looks exactly like the icon on
/// the home screen.
class TMinusMark extends StatelessWidget {
  const TMinusMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: const _TMinusMarkPainter(),
      ),
    );
  }
}

/// The geometry mirrors the launcher icon: see tool/gen_launcher_icon.py.
class _TMinusMarkPainter extends CustomPainter {
  const _TMinusMarkPainter();

  // Units are those of the icon's 108 unit canvas. A launcher shows the inner
  // 72 of them (units 18 to 90), which is what is drawn, scaled to the size.
  static const _visibleFrom = 18.0;
  static const _visibleSize = 72.0;
  static const _centre = Offset(54, 54);
  static const _radius = 26.0; // of the track, and of the arc's centre line
  static const _stroke = 9.0; // the width of both
  static const _trackAlpha = 0.35;
  static const _arcStart = -math.pi / 2; // 12 o'clock
  static const _arcSweep = 3 * math.pi / 2; // clockwise to 9 o'clock

  // The T- mark: the bar, the stem and the minus.
  static const _markRects = [
    Rect.fromLTWH(38.325, 44.65, 18.7, 4.4),
    Rect.fromLTWH(45.475, 44.65, 4.4, 18.7),
    Rect.fromLTWH(59.775, 52.35, 9.9, 4.4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final colours = TMinusColorSchemes.dark;
    canvas
      ..scale(size.shortestSide / _visibleSize)
      ..translate(-_visibleFrom, -_visibleFrom);

    // The disc is the visible area clipped to a circle, as the legacy PNGs
    // are. Nothing else reaches past it, so no clip is needed.
    canvas.drawCircle(
      _centre,
      _visibleSize / 2,
      Paint()..color = colours.primaryContainer,
    );

    Paint stroke(Color color, {StrokeCap cap = StrokeCap.butt}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = cap
      ..color = color;

    canvas.drawCircle(
      _centre,
      _radius,
      stroke(colours.surface.withValues(alpha: _trackAlpha)),
    );
    canvas.drawArc(
      Rect.fromCircle(center: _centre, radius: _radius),
      _arcStart,
      _arcSweep,
      false,
      stroke(colours.primary, cap: StrokeCap.round),
    );

    final mark = Paint()..color = colours.onPrimaryContainer;
    for (final rect in _markRects) {
      canvas.drawRect(rect, mark);
    }
  }

  @override
  bool shouldRepaint(_TMinusMarkPainter old) => false;
}
