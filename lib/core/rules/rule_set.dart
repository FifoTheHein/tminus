import '../model/alert_profile.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/quiet_state.dart';
import '../model/skip_filters.dart';

/// Everything the rules engine needs besides the occurrence itself.
/// Built from storage by `loadRuleSet` (lib/core/storage/rule_set_loader.dart).
class RuleSet {
  RuleSet({
    List<AlertProfile> profiles = const [],
    List<EventOverride> overrides = const [],
    List<KeywordRule> rules = const [],
    this.skipFilters = const SkipFilters(),
    this.sourceDefaults = const {},
    this.globalDefaultProfileId = BuiltInProfiles.defaultId,
    this.quiet = const QuietNone(),
  }) : _profiles = {
         for (final p in BuiltInProfiles.all) p.id: p,
         // Stored profiles win, so an edited built-in replaces the constant.
         // Silent never has alerts, whatever its row says (decision 16).
         for (final p in profiles)
           p.id: p.id == BuiltInProfiles.silentId && p.alerts.isNotEmpty
               ? p.copyWith(alerts: const [])
               : p,
       },
       _occurrenceOverrides = {
         for (final o in overrides)
           if (o.scope == OverrideScope.occurrence && !o.isEmpty) o.target: o,
       },
       _seriesOverrides = {
         for (final o in overrides)
           if (o.scope == OverrideScope.series && !o.isEmpty) o.target: o,
       },
       rules = List.unmodifiable(<KeywordRule>[...rules]..sort(_byPosition));

  final Map<String, AlertProfile> _profiles;
  final Map<String, EventOverride> _occurrenceOverrides;
  final Map<String, EventOverride> _seriesOverrides;

  /// Sorted by position, then id.
  final List<KeywordRule> rules;
  final SkipFilters skipFilters;

  /// sourceId → default profile id (sources without one are absent).
  final Map<String, String> sourceDefaults;
  final String globalDefaultProfileId;
  final QuietState quiet;

  /// Null when [id] names no known profile (e.g. it was deleted).
  AlertProfile? profile(String id) => _profiles[id];

  EventOverride? occurrenceOverride(String occurrenceKey) =>
      _occurrenceOverrides[occurrenceKey];

  EventOverride? seriesOverride(String? seriesUid) =>
      seriesUid == null ? null : _seriesOverrides[seriesUid];

  /// The occurrence override on the first of [keys] that has one. Pass an
  /// occurrence's `lookupKeys`, best first (spec §13).
  EventOverride? occurrenceOverrideFor(List<String> keys) {
    for (final key in keys) {
      final found = _occurrenceOverrides[key];
      if (found != null) return found;
    }
    return null;
  }

  /// The series override on the first of [uids] that has one. Pass an
  /// occurrence's `lookupSeriesUids`, best first.
  EventOverride? seriesOverrideFor(List<String> uids) {
    for (final uid in uids) {
      final found = _seriesOverrides[uid];
      if (found != null) return found;
    }
    return null;
  }

  /// The default profile id of the first of [sourceIds] that has one. Pass an
  /// occurrence's `sourceIds`, in rank order. A default naming a deleted
  /// profile still counts as that source's default; the engine then falls
  /// through to the global default, as it does for a single source.
  String? sourceDefaultFor(List<String> sourceIds) {
    for (final id in sourceIds) {
      final found = sourceDefaults[id];
      if (found != null) return found;
    }
    return null;
  }

  static int _byPosition(KeywordRule a, KeywordRule b) {
    final byPos = a.position.compareTo(b.position);
    return byPos != 0 ? byPos : a.id.compareTo(b.id);
  }
}
