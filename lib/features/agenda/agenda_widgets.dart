import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/theme/tminus_theme.dart';
import '../../core/model/alert.dart';
import '../../core/model/event_occurrence.dart';
import '../../core/model/local_date.dart';
import '../../core/model/quiet_state.dart';
import '../../core/sync/source_status.dart';
import '../../core/text/time_text.dart';
import '../common/alert_chips.dart';
import '../common/status_tone.dart';
import '../common/tminus_mark.dart';
import 'agenda_model.dart';

/// How far a meeting that is over fades (design system: event card, "past").
const pastCardOpacity = 0.42;

/// The quiet banner's text (mockup 2c).
String quietBannerText(QuietState q, DateTime now, tz.Location zone) {
  final today = LocalDate.of(now, zone);
  String when(DateTime utc) {
    final d = LocalDate.of(utc, zone);
    final hm = TimeText.hm(utc, zone);
    if (d == today) return 'today $hm';
    if (d == today.addDays(1)) return 'tomorrow $hm';
    return '${TimeText.day(d)} $hm';
  }

  return switch (q) {
    MuteToday(:final untilUtc) => 'Muted until ${when(untilUtc)}',
    PausedUntil(:final untilUtc) => 'Paused until ${when(untilUtc)}',
    Vacation(:final firstDay, :final lastDay) =>
      firstDay >= today.addDays(1)
          ? 'Vacation from ${TimeText.day(firstDay)}'
          : 'Vacation until ${TimeText.day(lastDay)}',
    QuietNone() => '',
  };
}

/// The T-Minus mark in the app bar.
class AgendaLogo extends StatelessWidget {
  const AgendaLogo({super.key});

  /// The mark is 22 dp across in the mockups.
  static const size = 22.0;

  @override
  Widget build(BuildContext context) => const TMinusMark(size: size);
}

/// "NEXT ALARM IN 23 min · Sprint planning · heads-up 09:50", and the sync
/// line under it (mockups 1a, 6e).
class AgendaHeader extends StatelessWidget {
  const AgendaHeader({super.key, required this.snapshot, required this.zone});

  final AgendaSnapshot snapshot;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = snapshot;
    final next = s.next;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.lg,
        TMinusSpacing.lg,
        TMinusSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (next == null)
            Text(
              'No alarms in the next 7 days',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: scheme.onSurface),
            )
          else ...[
            Text(
              'NEXT ALARM IN',
              style: context.tminusType.overline.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: TMinusSpacing.xxs),
            _Countdown(text: TimeText.countdown(next.fireAtUtc, s.now, zone)),
            const SizedBox(height: TMinusSpacing.xs),
            _NextLine(
              title: s.nextItem?.meeting.title ?? next.event.title,
              color: Color(
                s.nextItem?.meeting.calendarColor ?? next.event.color,
              ),
              when:
                  '${next.strength == AlertStrength.alarm ? 'alarm' : 'heads-up'} '
                  '${TimeText.hm(next.fireAtUtc, zone)}',
            ),
          ],
          const SizedBox(height: TMinusSpacing.sm),
          _SyncLine(sync: s.sync, now: s.now),
        ],
      ),
    );
  }
}

/// `23 min` with the number large and the unit small; anything longer
/// (`1 h 05`, `Wed 09:50`) is one piece of text. It shrinks rather than runs
/// off a narrow screen.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.text});

  final String text;

  static const _unit = ' min';

  @override
  Widget build(BuildContext context) {
    final type = context.tminusType;
    final color = Theme.of(context).colorScheme.onSurface;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: text.endsWith(_unit)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  text.substring(0, text.length - _unit.length),
                  style: type.countdownL.copyWith(color: color),
                ),
                const SizedBox(width: TMinusSpacing.xs),
                Text('min', style: type.countdownLUnit.copyWith(color: color)),
              ],
            )
          : Text(text, style: type.countdownL.copyWith(color: color)),
    );
  }
}

/// A calendar-colour dot, the meeting's title and when the alert fires. A long
/// title is cut short so that the alert time stays.
class _NextLine extends StatelessWidget {
  const _NextLine({
    required this.title,
    required this.color,
    required this.when,
  });

  final String title;
  final Color color;

  /// `heads-up 09:50` or `alarm 09:59`.
  final String when;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bodyLarge = Theme.of(context).textTheme.bodyLarge;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: TMinusSpacing.xs),
        // The texts share a baseline; the dot stays centred on the line.
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bodyLarge?.copyWith(color: scheme.onSurface),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TMinusSpacing.xs,
                ),
                child: Text(
                  '·',
                  style: bodyLarge?.copyWith(
                    color: context.tminusColors.tertiaryText,
                  ),
                ),
              ),
              Text(
                when,
                style: context.tminusType.time.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A dot in the sync state's colour, "Synced 4 min ago · 2 sources", and the
/// amber chip when a feed is stale. Status colours are for health and sync
/// state, and this is where the Agenda shows the sync state.
class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.sync, required this.now});

  final AgendaSyncState sync;
  final DateTime now;

  StatusTone get _tone {
    if (sync.lastSyncedUtc == null) return StatusTone.neutral;
    final broken = sync.problems.any(
      (p) =>
          p.health == SourceHealth.error || p.health == SourceHealth.needsSetup,
    );
    if (broken) return StatusTone.error;
    if (sync.stale || sync.problems.isNotEmpty) return StatusTone.warn;
    return StatusTone.ok;
  }

  @override
  Widget build(BuildContext context) {
    final last = sync.lastSyncedUtc;
    final count = sync.sourceCount == 1
        ? '1 source'
        : '${sync.sourceCount} sources';
    return Wrap(
      spacing: TMinusSpacing.xs,
      runSpacing: TMinusSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(_tone),
            const SizedBox(width: TMinusSpacing.xs),
            Text(
              last == null
                  ? 'Not synced yet'
                  : 'Synced ${TimeText.ago(last, now)} · $count',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (sync.stale) const FeedStaleChip(key: Key('feedStaleChip')),
      ],
    );
  }
}

/// The amber "Feed stale" chip (design system: status chip).
class FeedStaleChip extends StatelessWidget {
  const FeedStaleChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tminusColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.xs,
        vertical: TMinusSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.statusWarnContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.sm),
        border: Border.all(color: colors.statusWarn.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync_problem, size: 14, color: colors.statusWarn),
          const SizedBox(width: TMinusSpacing.xxs),
          Text(
            'Feed stale',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onStatusWarnContainer),
          ),
        ],
      ),
    );
  }
}

/// "Today" and "TUE 6 OCT" (the date only on Today and Tomorrow, where the
/// title does not already say it).
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.title, this.label});

  final String title;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = label;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TMinusSpacing.lg,
          TMinusSpacing.xl,
          TMinusSpacing.lg,
          TMinusSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (date != null)
              Text(
                date,
                style: context.tminusType.overline.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `NOW 09:27` and a line across the list, between the meetings that are over
/// and the ones to come.
class NowLine extends StatelessWidget {
  const NowLine({super.key, required this.time});

  /// `09:27`.
  final String time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.sm,
        TMinusSpacing.xxs,
        TMinusSpacing.sm,
        TMinusSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(TMinusRadii.xs),
            ),
            child: Text(
              'NOW $time',
              style: context.tminusType.time.copyWith(
                color: scheme.onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Container(height: 2, color: scheme.primary)),
        ],
      ),
    );
  }
}

/// Today with nothing on it (mockup 6b). [nothingRings] is false when an alert
/// still fires today, for a meeting just after midnight.
class EmptyDayCard extends StatelessWidget {
  const EmptyDayCard({super.key, required this.nothingRings});

  final bool nothingRings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.sm,
        0,
        TMinusSpacing.sm,
        TMinusSpacing.xs,
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(TMinusRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TMinusSpacing.md,
            vertical: 40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wb_sunny_outlined, size: 36, color: scheme.outline),
              const SizedBox(height: TMinusSpacing.md),
              Text(
                'No meetings. Enjoy',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
              ),
              if (nothingRings) ...[
                const SizedBox(height: TMinusSpacing.xxs),
                Text(
                  'Nothing will ring today.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One meeting (mockups 1a, 2c, 6e): its colour bar, time, title, where it is
/// or "Teams", what will ring and why, and the toggle. A tap opens the sheet.
class AgendaCard extends StatelessWidget {
  const AgendaCard({
    super.key,
    required this.item,
    required this.now,
    required this.zone,
    required this.onToggle,
    required this.onTap,
  });

  final AgendaItem item;
  final DateTime now;
  final tz.Location zone;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  /// The switch's width, its inset from the right and a gap before the text.
  static const _switchSpace = 52.0 + 14.0 + TMinusSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final colors = context.tminusColors;
    final meeting = item.meeting;
    final on = item.on;
    final location = meeting.location;
    final alerts = item.resolved.alerts;

    final meta = <Widget>[
      if (item.hasTeams)
        const TeamsBadge()
      else if (location != null && location.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      if (meeting.warnings.contains(OccurrenceWarning.tzFallback))
        Tooltip(
          message: 'Time zone guessed',
          child: Icon(
            Icons.warning_amber,
            size: 16,
            color: colors.tertiaryText,
          ),
        ),
      if (item.resolved.silenced)
        const MutedChip()
      else if (alerts.isNotEmpty)
        AlertChips(alerts, dimmedOffsets: item.dimmedOffsets(now)),
    ];

    final card = Material(
      color: on ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(TMinusRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        // The card is as wide as its row; the bar and the switch sit on it.
        fit: StackFit.passthrough,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                18,
                TMinusSpacing.sm,
                _switchSpace,
                TMinusSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meeting.allDay
                        ? 'All day'
                        : TimeText.range(
                            meeting.startUtc,
                            meeting.endUtc,
                            zone,
                          ),
                    style: context.tminusType.time.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TMinusSpacing.xxs),
                  Text(
                    meeting.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: on ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: TMinusSpacing.xs),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: meta,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    item.resolved.explanation,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.tertiaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: TMinusSpacing.sm,
            bottom: TMinusSpacing.sm,
            width: 4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(meeting.calendarColor),
                  borderRadius: BorderRadius.circular(TMinusRadii.xs),
                ),
              ),
            ),
          ),
          if (item.showsToggle(now))
            Positioned(
              top: 6,
              right: 14,
              child: Semantics(
                label: 'Alerts for ${meeting.title}',
                child: Switch(
                  key: Key('agenda-toggle-${meeting.key}'),
                  value: on,
                  onChanged: onToggle,
                ),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.sm,
        0,
        TMinusSpacing.sm,
        TMinusSpacing.xs,
      ),
      child: item.isPast(now)
          ? Opacity(
              key: ValueKey('agenda-past-${meeting.key}'),
              opacity: pastCardOpacity,
              child: card,
            )
          : card,
    );
  }
}

/// The dashed "muted" chip a quiet mode puts where the alert chips were (design
/// system: alert chip, silenced).
class MutedChip extends StatelessWidget {
  const MutedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tminusColors;
    return Semantics(
      label: 'Muted by quiet mode',
      excludeSemantics: true,
      child: CustomPaint(
        painter: _DashedPillPainter(colors.headsUpChipBorder),
        child: Container(
          height: 20,
          padding: const EdgeInsets.fromLTRB(5, 0, 7, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 14,
                color: colors.tertiaryText,
              ),
              const SizedBox(width: 3),
              Text(
                'muted',
                style: context.tminusType.chipNumeral.copyWith(
                  color: colors.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedPillPainter extends CustomPainter {
  const _DashedPillPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 6) {
        canvas.drawPath(metric.extractPath(at, at + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillPainter old) => old.color != color;
}

/// A centred message with one button: no calendar yet, or the Agenda would not
/// load.
class AgendaMessage extends StatelessWidget {
  const AgendaMessage({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.icon,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TMinusSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 48, color: scheme.outline),
              const SizedBox(height: TMinusSpacing.md),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: TMinusSpacing.lg),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// The first sync is still running: a progress bar and placeholder cards
/// (mockup 6c). Nothing else on the screen can be known yet.
///
/// The bar moves for [barLifetime] and then goes. A first sync that takes longer
/// still says it is syncing, but a bar that never stops is only motion, and a
/// screen with an animation that never ends cannot be waited on in a widget
/// test (`pumpAndSettle`).
class FirstSyncView extends StatefulWidget {
  const FirstSyncView({super.key});

  static const barLifetime = Duration(seconds: 30);

  @override
  State<FirstSyncView> createState() => _FirstSyncViewState();
}

class _FirstSyncViewState extends State<FirstSyncView> {
  late final Timer _timer;
  var _moving = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(FirstSyncView.barLifetime, () {
      if (mounted) setState(() => _moving = false);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.lg,
            TMinusSpacing.xs,
            TMinusSpacing.lg,
            0,
          ),
          // The bar is 4 dp high; the gap keeps the layout where it was.
          child: _moving
              ? const ClipRRect(
                  borderRadius: BorderRadius.all(
                    Radius.circular(TMinusRadii.pill),
                  ),
                  child: LinearProgressIndicator(),
                )
              : const SizedBox(height: 4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.lg,
            TMinusSpacing.xl,
            TMinusSpacing.lg,
            0,
          ),
          child: Text(
            'FIRST SYNC',
            style: context.tminusType.overline.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.lg,
            TMinusSpacing.xxs,
            TMinusSpacing.lg,
            0,
          ),
          child: Text(
            'Syncing your calendar…',
            style: textTheme.headlineSmall?.copyWith(color: scheme.onSurface),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.lg,
            TMinusSpacing.xs,
            TMinusSpacing.lg,
            TMinusSpacing.xl,
          ),
          child: Text(
            'Alarms are set as soon as each event is read.',
            style: textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const _SkeletonCard(widths: [80, 200, 120]),
        const _SkeletonCard(widths: [80, 170, 140]),
        const _SkeletonCard(widths: [80, 230, 100]),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.widths});

  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.sm,
        0,
        TMinusSpacing.sm,
        TMinusSpacing.xs,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(TMinusSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(TMinusRadii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, w) in widths.indexed) ...[
              if (i > 0) const SizedBox(height: TMinusSpacing.sm),
              Container(
                width: w,
                height: 12,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(TMinusRadii.pill),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
