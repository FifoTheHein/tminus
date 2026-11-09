import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';

/// Status colours, for health and sync state only (brief "Visual direction").
/// Mapping a source's health to a tone is left to the source screens, so this
/// kit does not depend on the source status model.
enum StatusTone { ok, warn, error, neutral }

Color toneColor(BuildContext context, StatusTone t) {
  final c = context.tminusColors;
  return switch (t) {
    StatusTone.ok => c.statusOk,
    StatusTone.warn => c.statusWarn,
    StatusTone.error => c.statusError,
    StatusTone.neutral => c.tertiaryText,
  };
}

/// A small filled circle in a status colour.
class StatusDot extends StatelessWidget {
  const StatusDot(this.tone, {super.key, this.size = 8});

  final StatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: toneColor(context, tone),
      shape: BoxShape.circle,
    ),
  );
}
