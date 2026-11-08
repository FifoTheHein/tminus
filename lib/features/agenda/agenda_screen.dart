import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/di.dart';
import '../../app/health_monitor.dart';
import '../../app/replan_scheduler.dart';
import '../../app/sync_runner.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/model/local_date.dart';
import '../../core/rules/rules_engine.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/override_repository.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/sync/source_status.dart';
import '../../core/text/time_text.dart';
import '../common/guarded.dart';
import '../common/notice_banner.dart';
import '../common/source_tone.dart';
import '../common/status_tone.dart';
import '../quiet/quiet_sheet.dart';
import 'agenda_controller.dart';
import 'agenda_model.dart';
import 'agenda_widgets.dart';
import 'event_sheet.dart';

/// The home tab: what rings next, what is coming and why (spec §8, brief §2).
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late final AgendaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AgendaController(
      loader: getIt<AgendaLoader>(),
      db: getIt<AppDatabase>(),
      overrides: getIt<OverrideRepository>(),
      settings: getIt<SettingsRepository>(),
      rulesEngine: () => getIt<RulesEngine>(),
      replan: getIt<ReplanScheduler>(),
      runSync: getIt<SyncRunner>(),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final snap = _controller.snapshot;
        return Scaffold(
          appBar: _appBar(context, snap),
          body: _body(context, snap),
        );
      },
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, AgendaSnapshot? snap) {
    final scheme = Theme.of(context).colorScheme;
    final quiet =
        snap != null && snap.quiet.isActive(nowUtc: snap.now, zone: tz.local);
    return AppBar(
      // 20 dp in, the 22 dp mark, then 10 dp before the title (mockup 1a).
      leadingWidth: TMinusSpacing.lg + AgendaLogo.size,
      leading: const Padding(
        padding: EdgeInsets.only(left: TMinusSpacing.lg),
        child: Center(child: AgendaLogo()),
      ),
      titleSpacing: 10,
      title: const Text('Agenda'),
      actions: [
        IconButton(
          isSelected: quiet,
          icon: const Icon(Icons.bedtime_outlined),
          selectedIcon: const Icon(Icons.bedtime),
          style: quiet
              ? IconButton.styleFrom(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                )
              : null,
          tooltip: 'Quiet modes',
          onPressed: () => showQuietSheet(context),
        ),
        PopupMenuButton<String>(
          onSelected: (_) => context.push('/settings'),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'settings', child: Text('Settings')),
          ],
        ),
      ],
    );
  }

  Widget _body(BuildContext context, AgendaSnapshot? snap) {
    if (_controller.failed) {
      return AgendaMessage(
        title: "Couldn't load the agenda.",
        actionLabel: 'Try again',
        onAction: _controller.reload,
      );
    }
    // The first load is a few milliseconds of local reads: nothing to show yet.
    if (snap == null) return const SizedBox.shrink();
    if (!snap.hasSources) {
      return AgendaMessage(
        icon: Icons.calendar_month_outlined,
        title: 'Add a calendar to get started',
        actionLabel: 'Add a calendar',
        onAction: () => context.go('/sources/add'),
      );
    }
    // A source that failed, or that waits for a link, is explained by its
    // banner; a spinner that never ends would only hide that.
    final firstSync =
        snap.sync.lastSyncedUtc == null &&
        snap.sync.sourceCount > 0 &&
        snap.sync.problems.isEmpty &&
        snap.days.every((d) => d.items.isEmpty);
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _banners(context, snap)),
          if (firstSync)
            const SliverToBoxAdapter(child: FirstSyncView())
          else ...[
            SliverToBoxAdapter(
              child: AgendaHeader(
                key: const Key('agendaHeader'),
                snapshot: snap,
                zone: tz.local,
              ),
            ),
            SliverList(delegate: SliverChildListDelegate(_rows(context, snap))),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: TMinusSpacing.xxl)),
        ],
      ),
    );
  }

  /// Pull to refresh: one fetching sync, and a line when it says something.
  Future<void> _refresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = await guarded(
      context,
      _controller.pullToRefresh,
      failure: 'Could not refresh.',
    );
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Restore, Health, sources, then quiet mode (plan: Banners, in this order).
  Widget _banners(BuildContext context, AgendaSnapshot snap) {
    final monitor = getIt<HealthMonitor>();
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final banners = <Widget>[
          if (snap.restorePending)
            NoticeBanner(
              key: const Key('restoreBanner'),
              tone: StatusTone.neutral,
              icon: Icons.restore,
              title: 'Restored from a backup',
              text: 'Re-link your calendar feeds and choose your phone calendars.',
              actionLabel: 'Open Sources',
              onAction: () => context.go('/sources'),
            ),
          if (monitor.report?.hasProblem ?? false)
            NoticeBanner(
              key: const Key('healthBanner'),
              tone: StatusTone.error,
              icon: Icons.error_outline,
              title: 'Alarms may not ring — fix in Health',
              actionLabel: 'Fix',
              onAction: () => context.go('/health'),
            ),
          if (snap.sync.problems.isNotEmpty)
            _problemBanner(context, snap.sync.problems),
          if (snap.quiet.isActive(nowUtc: snap.now, zone: tz.local))
            NoticeBanner(
              key: const Key('quietBanner'),
              tone: StatusTone.neutral,
              icon: Icons.bedtime,
              title: quietBannerText(snap.quiet, snap.now, tz.local),
              actionLabel: 'End',
              onAction: () => unawaited(
                guarded(
                  context,
                  _controller.endQuiet,
                  failure: 'Could not end quiet mode.',
                ),
              ),
            ),
        ];
        if (banners.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            TMinusSpacing.sm,
            TMinusSpacing.xs,
            TMinusSpacing.sm,
            0,
          ),
          child: Column(
            children: [
              for (final b in banners)
                Padding(
                  padding: const EdgeInsets.only(bottom: TMinusSpacing.xs),
                  child: b,
                ),
            ],
          ),
        );
      },
    );
  }

  /// One source with a problem names it and opens it; several give a count and
  /// open the list (mockup 6d). The tone is the worst of them.
  Widget _problemBanner(BuildContext context, List<SourceStatus> problems) {
    final worst = problems.any((p) => toneOf(p.health) == StatusTone.error)
        ? StatusTone.error
        : StatusTone.warn;
    final one = problems.length == 1 ? problems.single : null;
    return NoticeBanner(
      key: const Key('problemBanner'),
      tone: worst,
      icon: Icons.sync_problem,
      title: one == null
          ? '${problems.length} calendars have problems'
          : '${one.config.name}: ${one.line}',
      actionLabel: 'View',
      onAction: () => context.go(
        one == null
            ? '/sources'
            : '/sources/${Uri.encodeComponent(one.config.id)}',
      ),
    );
  }

  /// A header and the cards of each day. Today gets the now line, and an empty
  /// card when it has no timed meeting.
  List<Widget> _rows(BuildContext context, AgendaSnapshot snap) {
    final zone = tz.local;
    final today = LocalDate.of(snap.now, zone);
    final tomorrow = today.addDays(1);
    final next = snap.next;
    final nothingRings =
        next == null || LocalDate.of(next.fireAtUtc, zone) != today;
    final rows = <Widget>[];
    for (final day in snap.days) {
      final isToday = day.date == today;
      rows.add(
        DayHeader(
          title: day.title,
          label: isToday || day.date == tomorrow ? day.label : null,
        ),
      );
      final hasTimed = day.items.any((i) => !i.meeting.allDay);
      if (isToday && !hasTimed) {
        rows.add(
          EmptyDayCard(key: const Key('emptyDay'), nothingRings: nothingRings),
        );
      }
      // The line goes before the first meeting that is neither over nor
      // all-day (those come first and belong to the whole day), or at the end
      // when everything today is over.
      var lineAt = -1;
      if (isToday && hasTimed) {
        final upcoming = day.items.indexWhere(
          (i) => !i.meeting.allDay && !i.isPast(snap.now),
        );
        lineAt = upcoming < 0 ? day.items.length : upcoming;
      }
      for (var i = 0; i <= day.items.length; i++) {
        if (i == lineAt) {
          rows.add(
            NowLine(
              key: const Key('nowLine'),
              time: TimeText.hm(snap.now, zone),
            ),
          );
        }
        if (i < day.items.length) rows.add(_card(context, snap, day.items[i]));
      }
    }
    return rows;
  }

  Widget _card(BuildContext context, AgendaSnapshot snap, AgendaItem item) {
    return AgendaCard(
      key: Key('agenda-card-${item.meeting.key}'),
      item: item,
      now: snap.now,
      zone: tz.local,
      onToggle: (on) => unawaited(
        guarded(
          context,
          () => _controller.setOn(item, on),
          failure: 'Could not change this event.',
        ),
      ),
      onTap: () => showEventSheet(context, item),
    );
  }
}
