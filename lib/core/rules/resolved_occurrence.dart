import '../model/alert.dart';
import '../model/alert_profile.dart';
import '../model/event_occurrence.dart';

/// The resolution step that decided an occurrence (spec §6), in order.
enum ResolutionStep {
  occurrenceOverride,
  seriesOverride,
  skipFilter,
  keywordRule,
  sourceDefault,
  globalDefault,
}

/// The rules engine's verdict for one occurrence.
class ResolvedOccurrence {
  const ResolvedOccurrence({
    required this.occurrence,
    required this.profile,
    required this.alerts,
    required this.explanation,
    required this.silenced,
    required this.step,
  });

  final EventOccurrence occurrence;

  /// Supplies sound settings and `ringsInQuietMode`. For "Off" results this is
  /// the Silent profile.
  final AlertProfile profile;

  /// What will actually be planned: the profile's alerts, or the override's
  /// custom alerts; empty when off, silent or silenced by a quiet mode.
  final List<AlertSpec> alerts;

  /// The grey reason line, e.g. `Quick · rule: "standup"` (roadmap §4).
  final String explanation;

  /// True when a quiet mode removed alerts that would otherwise ring.
  final bool silenced;
  final ResolutionStep step;

  @override
  String toString() =>
      'ResolvedOccurrence(${occurrence.key}, $explanation, $alerts)';
}
