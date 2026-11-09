import '../model/planned_alert.dart';
import '../model/source_config.dart';
import '../rules/resolved_occurrence.dart';
import '../rules/rule_set.dart';
import '../rules/rules_engine.dart';
import '../storage/alert_history_repository.dart';
import '../storage/meeting_link_repository.dart';
import '../storage/occurrence_repository.dart';
import '../storage/rule_set_loader.dart';
import '../storage/settings_repository.dart';
import '../storage/source_repository.dart';
import '../sync/sync_service.dart' show SyncService;
import 'meeting_merger.dart';
import 'plan_builder.dart';

/// What the cache plans to right now (Plan 5 decision 7).
class MeetingPlan {
  const MeetingPlan({
    required this.merge,
    required this.resolved,
    required this.alerts,
    required this.rules,
    required this.sources,
  });

  final MergeResult merge;

  /// One per meeting, in `merge.meetings` order.
  final List<ResolvedOccurrence> resolved;

  /// Exactly what `applyPlan` gets (sorted by fire time, then id).
  final List<PlannedAlert> alerts;
  final RuleSet rules;

  /// The enabled sources by id, in name order.
  final Map<String, SourceConfig> sources;
}

/// Ranks as spec §13 defines them: a source whose last fetch failed ranks
/// below a healthy one.
Map<String, SourceRank> sourceRanks(
  Iterable<SourceConfig> enabled,
  Map<String, SourceSyncState?> states,
) => {
  for (final s in enabled)
    s.id: SourceRank(kind: s.kind, failing: states[s.id]?.lastError != null),
};

/// The one planning path. `SyncService` uses it and then stores the link
/// changes; the Agenda uses it read-only, so both show the same meetings,
/// keys and alerts.
class MeetingPlanner {
  MeetingPlanner({
    required this.sources,
    required this.occurrences,
    required this.links,
    required this.history,
    required this.settings,
    required this.ruleSets,
    required this.rulesEngine,
  });

  final SourceRepository sources;
  final OccurrenceRepository occurrences;
  final MeetingLinkRepository links;
  final AlertHistoryRepository history;
  final SettingsRepository settings;
  final RuleSetLoader ruleSets;

  /// A new engine per load: it reads `tz.local` as it is now.
  final RulesEngine Function() rulesEngine;

  /// Plans the cached copies of enabled sources that overlap
  /// [fromUtc, toUtc). Writes nothing.
  Future<MeetingPlan> load({
    required DateTime now,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final enabled = {
      for (final s in await sources.all())
        if (s.enabled) s.id: s,
    };
    final states = {
      for (final id in enabled.keys) id: await sources.syncState(id),
    };
    final copies = [
      for (final o in await occurrences.between(fromUtc, toUtc))
        if (enabled.containsKey(o.sourceId)) o,
    ];
    final merge = MeetingMerger.merge(
      copies: copies,
      links: await links.all(),
      sources: sourceRanks(enabled.values, states),
      enabled: await settings.getString(SyncService.mergeEnabledKey) != 'false',
    );
    final rules = await ruleSets.load();
    final resolved = rulesEngine().resolveAll(merge.meetings, rules);
    return MeetingPlan(
      merge: merge,
      resolved: resolved,
      alerts: buildPlan(
        resolved,
        now: now,
        acknowledgements: await history.acknowledgements(nowUtc: now),
      ),
      rules: rules,
      sources: enabled,
    );
  }
}
