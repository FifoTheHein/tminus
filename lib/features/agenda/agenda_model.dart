import 'package:timezone/timezone.dart' as tz;

import '../../core/model/event_occurrence.dart';
import '../../core/model/local_date.dart';
import '../../core/model/meeting_occurrence.dart';
import '../../core/model/planned_alert.dart';
import '../../core/model/quiet_state.dart';
import '../../core/model/source_config.dart';
import '../../core/planner/meeting_planner.dart';
import '../../core/rules/resolved_occurrence.dart';
import '../../core/rules/rule_set.dart';
import '../../core/rules/rules_engine.dart';
import '../../core/storage/app_settings.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/sync/source_status.dart';
import '../../core/text/time_text.dart';

/// One meeting on the Agenda, with what the last plan holds for it.
class AgendaItem {
  AgendaItem({
    required this.meeting,
    required this.resolved,
    required this.planned,
    required this.sources,
  });

  /// A [MeetingOccurrence] when the meeting was found in several sources.
  final EventOccurrence meeting;
  final ResolvedOccurrence resolved;

  /// This meeting's alerts in the plan, by fire time. The plan keeps the alerts
  /// of a meeting that is under way, so some of them may be in the past.
  final List<PlannedAlert> planned;

  /// The meeting's sources in rank order, the time source first.
  final List<SourceConfig> sources;

  bool get on => resolved.alerts.isNotEmpty;

  bool isPast(DateTime now) => !meeting.endUtc.isAfter(now);

  /// Offsets the profile has but that will not ring: dismissed, or already
  /// past (the plan lists past alerts until the meeting ends, but the engine
  /// never arms them).
  Set<int> dimmedOffsets(DateTime now) {
    final live = {
      for (final a in planned)
        if (a.fireAtUtc.isAfter(now)) a.offsetMinutes,
    };
    return {
      for (final a in resolved.alerts)
        if (!live.contains(a.offsetMinutes)) a.offsetMinutes,
    };
  }

  /// "Teams" when there is a join link, else the location (brief §2).
  bool get hasTeams => meeting.joinUrl != null;
}

class AgendaDay {
  const AgendaDay({
    required this.date,
    required this.title,
    required this.label,
    required this.items,
  });

  final LocalDate date;

  /// `Today`, `Tomorrow`, `Thu 8 Oct`.
  final String title;

  /// `TUE 6 OCT`, shown on the right of Today and Tomorrow.
  final String label;
  final List<AgendaItem> items;
}

class AgendaSyncState {
  const AgendaSyncState({
    required this.lastSyncedUtc,
    required this.sourceCount,
    required this.problems,
    required this.stale,
  });

  /// The newest success among the enabled sources; null when none has synced.
  final DateTime? lastSyncedUtc;

  /// How many sources are enabled.
  final int sourceCount;

  /// Enabled sources whose health is warning or error, plus sources that need
  /// setup (mockup 6d's banner).
  final List<SourceStatus> problems;

  /// An enabled ICS source has not synced for over 60 min ("Feed stale").
  final bool stale;
}

class AgendaSnapshot {
  const AgendaSnapshot({
    required this.now,
    required this.days,
    required this.next,
    required this.nextItem,
    required this.quiet,
    required this.sync,
    required this.hasSources,
    required this.restorePending,
    required this.rules,
    required this.upcoming,
  });

  final DateTime now;
  final List<AgendaDay> days;

  /// The first alert in the plan that has not fired yet.
  final PlannedAlert? next;

  /// The item [next] belongs to.
  final AgendaItem? nextItem;
  final QuietState quiet;
  final AgendaSyncState sync;

  /// Any source exists, switched on or not.
  final bool hasSources;
  final bool restorePending;

  /// The rules the plan used, for the toggle's natural state (decision 8).
  final RuleSet rules;

  /// Every item that has not ended, for the rule preview.
  final List<AgendaItem> upcoming;
}

/// Today (always), then each later local day that has meetings, up to the
/// end of the fetch window. All-day meetings first, then by start, then key.
List<AgendaDay> groupByDay(
  List<AgendaItem> items, {
  required DateTime now,
  required tz.Location zone,
}) {
  final today = LocalDate.of(now, zone);
  final byDay = <LocalDate, List<AgendaItem>>{today: []};
  for (final i in items) {
    final d = LocalDate.of(i.meeting.startUtc, zone);
    // The window starts at local midnight, so a meeting that began on an
    // earlier day and runs past midnight is in it; it is not listed again.
    if (d.compareTo(today) < 0) continue;
    (byDay[d] ??= []).add(i);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final d in days)
      AgendaDay(
        date: d,
        title: TimeText.dayTitle(d, today),
        label: TimeText.dayUpper(d),
        items: byDay[d]!..sort(_byAllDayStartKey),
      ),
  ];
}

int _byAllDayStartKey(AgendaItem a, AgendaItem b) {
  if (a.meeting.allDay != b.meeting.allDay) return a.meeting.allDay ? -1 : 1;
  final s = a.meeting.startUtc.compareTo(b.meeting.startUtc);
  return s != 0 ? s : a.meeting.key.compareTo(b.meeting.key);
}

/// Plan 5 decision 8: write nothing when the wanted state is the natural one.
bool? enabledToWrite({required bool wantOn, required bool naturalOn}) =>
    wantOn == naturalOn ? null : wantOn;

/// Builds the Agenda from the same [MeetingPlanner] the sync uses, so it shows
/// the alerts the engine was given (Plan 5 decision 7). It writes nothing.
class AgendaLoader {
  AgendaLoader({
    required this.planner,
    required this.statuses,
    required this.settings,
    required this.appSettings,
    required this.zone,
    UtcClock? clock,
  }) : clock = clock ?? systemUtcNow;

  final MeetingPlanner planner;
  final SourceStatusLoader statuses;
  final SettingsRepository settings;
  final AppSettings appSettings;
  final tz.Location Function() zone;
  final UtcClock clock;

  Future<AgendaSnapshot> load() async {
    final now = clock();
    final location = zone();
    final today = LocalDate.of(now, location);
    final plan = await planner.load(
      now: now,
      fromUtc: today.startIn(location).toUtc(),
      toUtc: now.add(const Duration(days: 7)),
    );
    final byKey = <String, List<PlannedAlert>>{};
    for (final a in plan.alerts) {
      (byKey[a.occurrenceKey] ??= []).add(a);
    }
    final items = [
      for (final r in plan.resolved)
        AgendaItem(
          meeting: r.occurrence,
          resolved: r,
          planned: byKey[r.occurrence.key] ?? const [],
          sources: [for (final id in r.occurrence.sourceIds) ?plan.sources[id]],
        ),
    ];
    final itemByKey = {for (final i in items) i.meeting.key: i};
    final next = plan.alerts.where((a) => a.fireAtUtc.isAfter(now)).firstOrNull;

    final all = await statuses.all();
    final enabled = all.where((s) => s.config.enabled).toList();
    final synced = [for (final s in enabled) ?s.state?.lastSuccessUtc]..sort();
    return AgendaSnapshot(
      now: now,
      days: groupByDay(items, now: now, zone: location),
      next: next,
      nextItem: next == null ? null : itemByKey[next.occurrenceKey],
      quiet: await settings.quietState(),
      sync: AgendaSyncState(
        lastSyncedUtc: synced.lastOrNull,
        sourceCount: enabled.length,
        problems: [
          for (final s in all)
            if (s.health == SourceHealth.warning ||
                s.health == SourceHealth.error ||
                s.health == SourceHealth.needsSetup)
              s,
        ],
        stale: enabled.any((s) => s.health == SourceHealth.stale),
      ),
      hasSources: all.isNotEmpty,
      restorePending: await appSettings.restorePending(),
      rules: plan.rules,
      upcoming: [
        for (final i in items)
          if (!i.isPast(now)) i,
      ],
    );
  }
}
