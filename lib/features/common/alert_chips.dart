import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert.dart';

/// `−10` with a real minus sign (U+2212), as the mockups print it. An alert at
/// the start of the meeting is `0`.
String offsetText(int minutes) => minutes == 0 ? '0' : '−$minutes';

/// One alert as a chip. Heads-up is an outline chip with a bell, an alarm is a
/// solid chip with an alarm icon (brief "Visual direction"). A [dimmed] chip is
/// an alert that was dismissed or has already passed.
class AlertChip extends StatelessWidget {
  const AlertChip(this.spec, {super.key, this.dimmed = false});

  final AlertSpec spec;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final alarm = spec.strength == AlertStrength.alarm;
    final colors = context.tminusColors;
    final fg = alarm ? colors.alarmChipFg : colors.headsUpChipFg;
    final chip = Container(
      key: Key(alarm ? 'alarmChip' : 'headsUpChip'),
      height: alarm ? 22 : 20,
      padding: const EdgeInsets.fromLTRB(5, 0, 7, 0),
      decoration: BoxDecoration(
        color: alarm ? colors.alarmChipBg : null,
        border: alarm ? null : Border.all(color: colors.headsUpChipBorder),
        borderRadius: BorderRadius.circular(TMinusRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            alarm ? Icons.alarm_rounded : Icons.notifications_outlined,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 3),
          Text(
            offsetText(spec.offsetMinutes),
            style: context.tminusType
                .chipNumeralFor(alarm: alarm)
                .copyWith(color: fg),
          ),
        ],
      ),
    );
    return Semantics(
      label: _spoken(spec),
      excludeSemantics: true,
      child: dimmed ? Opacity(opacity: 0.38, child: chip) : chip,
    );
  }
}

/// What a screen reader says for a chip, instead of the bare offset.
String _spoken(AlertSpec spec) {
  final what = spec.strength == AlertStrength.alarm ? 'Alarm' : 'Heads-up';
  final when = switch (spec.offsetMinutes) {
    0 => 'at start',
    1 => '1 minute before',
    final m => '$m minutes before',
  };
  return '$what $when';
}

/// A profile's or an event's alerts, in list order. [dimmedOffsets] names the
/// offsets (minutes before start) whose chips are drawn faded.
class AlertChips extends StatelessWidget {
  const AlertChips(this.alerts, {super.key, this.dimmedOffsets = const {}});

  final List<AlertSpec> alerts;
  final Set<int> dimmedOffsets;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final a in alerts)
          AlertChip(a, dimmed: dimmedOffsets.contains(a.offsetMinutes)),
      ],
    );
  }
}

/// Shown on a meeting that has a join link.
class TeamsBadge extends StatelessWidget {
  const TeamsBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      const _Badge(icon: Icons.videocam_rounded, label: 'Teams');
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = context.tminusColors.headsUpChipFg;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: TMinusSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: TMinusSpacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
