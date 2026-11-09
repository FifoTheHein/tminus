import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/di.dart';
import '../../app/health_monitor.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/engine/alarm_engine.dart';
import '../../core/model/alert.dart';
import '../../core/model/alert_history_entry.dart';
import '../../core/model/source_config.dart';
import '../../core/model/sync_log_entry.dart';
import '../../core/platform/ui_platform.dart';
import '../../core/rules/rules_engine.dart' show UtcClock, systemUtcNow;
import '../../core/storage/alert_history_repository.dart';
import '../../core/storage/source_repository.dart';
import '../../core/storage/sync_log_repository.dart';
import '../../core/text/time_text.dart';
import '../common/guarded.dart';
import '../common/notice_banner.dart';
import '../common/section_card.dart';
import '../common/status_tone.dart';
import 'health_report.dart';
import 'health_text.dart';
import 'maker_tips.dart';

/// The Health tab: whether alarms will ring (permissions and sync freshness,
/// with a Fix for each problem), what the engine has scheduled, what happened
/// to past alerts, and the sync log (spec §9, brief §6).
///
/// The checklist comes from the app-wide [HealthMonitor]. History and the sync
/// log watch the database: `missedSystem` rows are written by a sync, so they
/// never pass through the engine's events.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, this.clock = systemUtcNow});

  /// Where "today" and "last checked" are counted from. Tests pass a fixed one.
  final UtcClock clock;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  static const _testDelay = Duration(seconds: 5);
  static const _listLimit = 50;
  static const _upcomingShown = 5;

  late final HealthMonitor _monitor;
  late final AlarmEngine _engine;
  late final Stream<List<AlertHistoryEntry>> _history;
  late final Stream<List<SyncLogEntry>> _syncLog;
  late final Stream<List<SourceConfig>> _sources;

  /// The report the banner last saw, and when. The monitor keeps no time of its
  /// own, so the screen notes when a new report first reached it.
  HealthReport? _seenReport;
  DateTime? _seenAt;

  /// `Build.MANUFACTURER`; null until read, and when it cannot be.
  String? _manufacturer;

  @override
  void initState() {
    super.initState();
    _monitor = getIt<HealthMonitor>();
    _engine = getIt<AlarmEngine>();
    _history = getIt<AlertHistoryRepository>().watchRecent(limit: _listLimit);
    _syncLog = getIt<SyncLogRepository>().watchRecent(limit: _listLimit);
    _sources = getIt<SourceRepository>().watchAll();
    unawaited(_monitor.refresh());
    unawaited(_readManufacturer());
  }

  Future<void> _readManufacturer() async {
    try {
      final info = await getIt<UiPlatform>().deviceInfo();
      if (mounted) setState(() => _manufacturer = info.manufacturer);
    } on MissingPluginException {
      // No native side (tests, desktop): the tile keeps its general title.
    } on PlatformException catch (e) {
      debugPrint('deviceInfo failed: ${e.code}');
    } catch (e) {
      // The type only: an error message can carry a value.
      debugPrint('Reading the phone failed: ${e.runtimeType}');
    }
  }

  /// A Fix button: a settings screen, or the source that needs attention.
  Future<void> _fix(HealthItem item) async {
    switch (item.fix) {
      case HealthFix.permission:
        final kind = item.permission;
        if (kind == null) return;
        await guarded(
          context,
          () => _engine.openPermissionSettings(kind),
          failure: "Couldn't open the settings.",
        );
        // The settings screen is already open, so the resume refresh picks up
        // what the user changes there. This one catches a change made at once.
        unawaited(_monitor.refresh());
      case HealthFix.source:
        final id = item.sourceId;
        if (id == null) return;
        context.go('/sources/${Uri.encodeComponent(id)}');
      case HealthFix.none:
        return;
    }
  }

  Future<void> _test(AlertStrength strength) async {
    final messenger = ScaffoldMessenger.of(context);
    final started = await guarded<bool>(context, () async {
      await _engine.testAlarm(strength, delay: _testDelay);
      return true;
    }, failure: "Couldn't start the test.");
    if (started != true) return;
    final what = strength == AlertStrength.alarm ? 'alarm' : 'heads-up';
    messenger.showSnackBar(
      SnackBar(content: Text('A test $what rings in 5 seconds.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health'),
        actions: [
          PopupMenuButton<String>(
            key: const Key('healthMenu'),
            onSelected: (_) => unawaited(context.push<void>('/settings')),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _monitor.refresh,
        child: ListenableBuilder(
          listenable: _monitor,
          builder: (context, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              TMinusSpacing.lg,
              TMinusSpacing.xs,
              TMinusSpacing.lg,
              TMinusSpacing.xxl,
            ),
            children: _sections(),
          ),
        ),
      ),
    );
  }

  List<Widget> _sections() {
    final report = _monitor.report;
    final now = widget.clock();
    final zone = tz.local;
    if (!identical(report, _seenReport)) {
      _seenReport = report;
      _seenAt = now;
    }
    return [
      _overall(report, now),
      if (report != null) ...[
        const _Header('Checklist'),
        SectionCard(
          children: [
            for (final item in report.items)
              _CheckRow(item: item, onFix: () => unawaited(_fix(item))),
          ],
        ),
      ],
      const SizedBox(height: TMinusSpacing.xs),
      // Keyed, like the sync log below: the first report adds rows above them,
      // and neither the open tile nor the stream should start over for that.
      SectionCard(
        key: const ValueKey('makerTipsCard'),
        children: [_MakerTips(manufacturer: _manufacturer)],
      ),
      if (report != null) ...[
        const _Header('Upcoming alarms', caption: 'as scheduled by the engine'),
        SectionCard(children: _upcomingRows(report, now, zone)),
        const _ForceStopNote(),
      ],
      // The two actions that prove an alarm rings sit above the long lists, not
      // under fifty history rows and fifty sync-log rows.
      const SizedBox(height: TMinusSpacing.xl),
      _TestButtons(onTest: (strength) => unawaited(_test(strength))),
      const _Header('History'),
      _Watched<AlertHistoryEntry>(
        key: const ValueKey('history'),
        stream: _history,
        failure: "Couldn't read the history.",
        builder: (context, rows) => SectionCard(
          children: rows.isEmpty
              ? const [_Note('No alerts yet')]
              : [
                  for (var i = 0; i < rows.length; i++)
                    _HistoryRow(
                      key: ValueKey('history-row-$i'),
                      entry: rows[i],
                      zone: zone,
                    ),
                ],
        ),
      ),
      const _Header('Sync log'),
      _SyncLog(
        key: const ValueKey('syncLogSection'),
        rows: _syncLog,
        sources: _sources,
        zone: zone,
      ),
    ];
  }

  Widget _overall(HealthReport? report, DateTime now) {
    if (report == null) {
      return const NoticeBanner(
        key: Key('healthOverall'),
        tone: StatusTone.neutral,
        icon: Icons.hourglass_empty,
        title: 'Checking…',
      );
    }
    final (tone, icon) = switch (report.overall) {
      HealthLevel.ok => (StatusTone.ok, Icons.verified),
      HealthLevel.warning => (StatusTone.warn, Icons.warning_amber_rounded),
      HealthLevel.problem => (StatusTone.error, Icons.error),
    };
    return NoticeBanner(
      key: const Key('healthOverall'),
      tone: tone,
      icon: icon,
      title: report.headline,
      // Nothing to summarise when all is good: say how fresh that is instead.
      text: report.summary.isEmpty
          ? 'Last checked ${TimeText.ago(_seenAt!, now)}'
          : report.summary,
    );
  }

  List<Widget> _upcomingRows(
    HealthReport report,
    DateTime now,
    tz.Location zone,
  ) {
    if (report.upcoming.isEmpty) {
      // Without the engine's answer nothing can be said about what is armed.
      final unread = report.items.any((i) => i.id == 'engine');
      return [_Note(unread ? 'Could not be read' : 'Nothing scheduled')];
    }
    final shown = report.upcoming.take(_upcomingShown).toList();
    return [
      for (var i = 0; i < shown.length; i++)
        _UpcomingRow(
          key: ValueKey('upcoming-$i'),
          alert: shown[i],
          when: upcomingTime(shown[i].fireAtUtc, now, zone),
        ),
    ];
  }
}

/// A section title, with an optional caption at the right.
class _Header extends StatelessWidget {
  const _Header(this.title, {this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final caption = this.caption;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.xs,
        TMinusSpacing.md,
        TMinusSpacing.xs,
        TMinusSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: textTheme.titleSmall)),
          if (caption != null)
            Text(
              caption,
              style: textTheme.bodySmall?.copyWith(
                color: context.tminusColors.tertiaryText,
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of grey text on a card: an empty list, or a list that failed.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TMinusSpacing.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

StatusTone _toneOf(HealthLevel level) => switch (level) {
  HealthLevel.ok => StatusTone.ok,
  HealthLevel.warning => StatusTone.warn,
  HealthLevel.problem => StatusTone.error,
};

/// A checklist row: a status icon, the name, one line of detail (coloured
/// unless all is well) and, for a row that can be fixed, a Fix button.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.item, required this.onFix});

  final HealthItem item;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = toneColor(context, _toneOf(item.level));
    final (icon, label) = switch (item.level) {
      HealthLevel.ok => (Icons.check_circle, 'OK'),
      HealthLevel.warning => (Icons.warning, 'Warning'),
      HealthLevel.problem => (Icons.error, 'Problem'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.md,
        vertical: TMinusSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, semanticLabel: label),
          const SizedBox(width: TMinusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: textTheme.bodyLarge),
                Text(
                  item.detail,
                  style: textTheme.bodyMedium?.copyWith(
                    color: item.level == HealthLevel.ok
                        ? scheme.onSurfaceVariant
                        : color,
                  ),
                ),
              ],
            ),
          ),
          if (item.fix != HealthFix.none) ...[
            const SizedBox(width: TMinusSpacing.sm),
            FilledButton(
              key: Key('fix-${item.id}'),
              onPressed: onFix,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: scheme.surface,
              ),
              // A screen reader says which row, not just "Fix" seven times.
              child: Text('Fix', semanticsLabel: 'Fix ${item.title}'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The phone-maker tips: the device's own maker first (its name in the title),
/// then the others.
class _MakerTips extends StatelessWidget {
  const _MakerTips({required this.manufacturer});

  final String? manufacturer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ExpansionTile(
      key: const Key('makerTips'),
      leading: const Icon(Icons.smartphone),
      title: Text(makerTipsTitle(manufacturer)),
      // No divider lines above and below: the card already frames the tile.
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.fromLTRB(
        TMinusSpacing.md,
        0,
        TMinusSpacing.md,
        TMinusSpacing.md,
      ),
      children: [
        for (final tip in makerTips(manufacturer ?? ''))
          Padding(
            padding: const EdgeInsets.only(top: TMinusSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip.maker, style: textTheme.labelLarge),
                const SizedBox(height: TMinusSpacing.xxs),
                Text(
                  tip.tip,
                  style: textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The alert strength in the chips' own language: an outlined bell for a
/// heads-up, a solid clock for an alarm.
class _StrengthBadge extends StatelessWidget {
  const _StrengthBadge(this.strength);

  final AlertStrength strength;

  @override
  Widget build(BuildContext context) {
    final colors = context.tminusColors;
    final alarm = strength == AlertStrength.alarm;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: alarm ? colors.alarmChipBg : null,
        border: alarm ? null : Border.all(color: colors.headsUpChipBorder),
      ),
      child: Icon(
        alarm ? Icons.alarm_rounded : Icons.notifications_outlined,
        size: 16,
        color: alarm ? colors.alarmChipFg : colors.headsUpChipFg,
        semanticLabel: alarm ? 'Alarm' : 'Heads-up',
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.alert, required this.when});

  final UpcomingAlert alert;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.md,
        vertical: TMinusSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              when,
              style: context.tminusType.time.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _StrengthBadge(alert.strength),
          const SizedBox(width: TMinusSpacing.sm),
          Expanded(
            child: Text(
              alert.title,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// Always under the upcoming alarms (spec §9): Android drops a force-stopped
/// app's alarms, and nothing in the engine can tell.
class _ForceStopNote extends StatelessWidget {
  const _ForceStopNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TMinusSpacing.xs,
        TMinusSpacing.xs,
        TMinusSpacing.xs,
        0,
      ),
      child: Text(
        'If you force-stop T-Minus, Android cancels its alarms until you open '
        'it again.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.tminusColors.tertiaryText),
      ),
    );
  }
}

/// A database list that follows the rows as they are written. Until the first
/// answer it keeps its room free; a failed read says so in fixed text, and logs
/// the error's type only, because a message can carry a row's values.
class _Watched<T> extends StatelessWidget {
  const _Watched({
    super.key,
    required this.stream,
    required this.failure,
    required this.builder,
  });

  final Stream<List<T>> stream;
  final String failure;
  final Widget Function(BuildContext context, List<T> rows) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('$failure (${snapshot.error.runtimeType})');
          return SectionCard(children: [_Note(failure)]);
        }
        final rows = snapshot.data;
        if (rows == null) return const SizedBox(height: TMinusSpacing.xxl);
        return builder(context, rows);
      },
    );
  }
}

class _TestChip extends StatelessWidget {
  const _TestChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('history-test'),
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(TMinusRadii.xs),
      ),
      child: Text(
        'Test',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// A history row. A missed alert is highlighted: an error icon and the status
/// colour for what happened.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({super.key, required this.entry, required this.zone});

  final AlertHistoryEntry entry;
  final tz.Location zone;

  static IconData _iconOf(AlertEventType type) => switch (type) {
    AlertEventType.fired => Icons.notifications_active_outlined,
    AlertEventType.snoozed => Icons.snooze,
    AlertEventType.dismissed => Icons.close,
    AlertEventType.dismissedAll => Icons.done_all,
    AlertEventType.joined => Icons.videocam_outlined,
    AlertEventType.missed || AlertEventType.missedSystem => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tminusColors;
    final miss = isMissEntry(entry);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.md,
        vertical: TMinusSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            _iconOf(entry.type),
            key: miss ? const Key('history-miss') : null,
            color: miss ? colors.statusError : scheme.onSurfaceVariant,
            semanticLabel: miss ? 'Missed' : null,
          ),
          const SizedBox(width: TMinusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        historyTitle(entry),
                        style: textTheme.bodyLarge,
                      ),
                    ),
                    if (isTestEntry(entry)) ...[
                      const SizedBox(width: TMinusSpacing.xs),
                      const _TestChip(),
                    ],
                  ],
                ),
                Text(
                  historyText(entry, zone),
                  style: textTheme.bodyMedium?.copyWith(
                    color: miss ? colors.statusError : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: TMinusSpacing.sm),
          Text(
            weekdayTime(entry.atUtc, zone),
            style: context.tminusType.time.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sync log, with each row's source named from the sources as they are.
class _SyncLog extends StatelessWidget {
  const _SyncLog({
    super.key,
    required this.rows,
    required this.sources,
    required this.zone,
  });

  final Stream<List<SyncLogEntry>> rows;
  final Stream<List<SourceConfig>> sources;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    return _Watched<SourceConfig>(
      key: const ValueKey('syncLogSources'),
      stream: sources,
      failure: "Couldn't read the sync log.",
      builder: (context, configs) {
        final names = {for (final c in configs) c.id: c.name};
        return _Watched<SyncLogEntry>(
          key: const ValueKey('syncLog'),
          stream: rows,
          failure: "Couldn't read the sync log.",
          builder: (context, entries) => SectionCard(
            children: entries.isEmpty
                ? const [_Note('No syncs yet')]
                : [
                    for (var i = 0; i < entries.length; i++)
                      _SyncLogRow(
                        key: ValueKey('syncLog-row-$i'),
                        entry: entries[i],
                        // A whole-run row has no source; a row whose source is
                        // gone keeps its history without its name.
                        name: entries[i].sourceId == null
                            ? 'All calendars'
                            : names[entries[i].sourceId] ??
                                  'A removed calendar',
                        zone: zone,
                      ),
                  ],
          ),
        );
      },
    );
  }
}

class _SyncLogRow extends StatelessWidget {
  const _SyncLogRow({
    super.key,
    required this.entry,
    required this.name,
    required this.zone,
  });

  final SyncLogEntry entry;
  final String name;
  final tz.Location zone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tone = outcomeTone(entry.outcome);
    final message = entry.message;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TMinusSpacing.md,
        vertical: TMinusSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: textTheme.bodyLarge),
                Row(
                  children: [
                    StatusDot(tone),
                    const SizedBox(width: TMinusSpacing.xs),
                    Flexible(
                      child: Text(
                        outcomeText(entry.outcome),
                        style: textTheme.bodyMedium?.copyWith(
                          color: tone == StatusTone.ok
                              ? scheme.onSurfaceVariant
                              : toneColor(context, tone),
                        ),
                      ),
                    ),
                  ],
                ),
                if (message != null && message.isNotEmpty)
                  Text(
                    message,
                    style: textTheme.bodySmall?.copyWith(
                      color: context.tminusColors.tertiaryText,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: TMinusSpacing.sm),
          Text(
            weekdayTime(entry.atUtc, zone),
            style: context.tminusType.time.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// **Test heads-up** and **Test alarm**: a real one rings in five seconds.
/// The outline and the solid fill echo the two strengths everywhere else.
class _TestButtons extends StatelessWidget {
  const _TestButtons({required this.onTest});

  final void Function(AlertStrength strength) onTest;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('testHeadsUp'),
            onPressed: () => onTest(AlertStrength.headsUp),
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('Test heads-up'),
          ),
        ),
        const SizedBox(width: TMinusSpacing.sm),
        Expanded(
          child: FilledButton.icon(
            key: const Key('testAlarm'),
            onPressed: () => onTest(AlertStrength.alarm),
            icon: const Icon(Icons.alarm_rounded),
            label: const Text('Test alarm'),
          ),
        ),
      ],
    );
  }
}
