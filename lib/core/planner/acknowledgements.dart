/// User acknowledgements the planner must respect (spec §6, roadmap §3
/// "Engine rules"). Built from `alert_history` by
/// `AlertHistoryRepository.acknowledgements()`.
///
/// - Dismiss all / Join: every alert of the occurrence is dropped while its
///   start is unchanged. Keyed by (occurrenceKey, startUtc), so a moved
///   meeting re-arms.
/// - Dismiss / Stop: one alert is dropped. Kotlin keys this by
///   (alertId, fireAtUtc). EngineEvent JSON carries `startUtcMs` but not the
///   fire time, so Dart keys it by (alertId, startUtc). The two are
///   equivalent: alertId fixes the offset, and fireAt = start − offset, so the
///   pair matches exactly when Kotlin's pair matches.
class Acknowledgements {
  Acknowledgements({
    Iterable<(String occurrenceKey, DateTime startUtc)> occurrences = const [],
    Iterable<(String alertId, DateTime startUtc)> alerts = const [],
  }) : _occurrences = {for (final (key, start) in occurrences) _k(key, start)},
       _alerts = {for (final (id, start) in alerts) _k(id, start)};

  static final empty = Acknowledgements();

  final Set<String> _occurrences;
  final Set<String> _alerts;

  bool isOccurrenceAcked(String occurrenceKey, DateTime startUtc) =>
      _occurrences.contains(_k(occurrenceKey, startUtc));

  bool isAlertDismissed(String alertId, DateTime occurrenceStartUtc) =>
      _alerts.contains(_k(alertId, occurrenceStartUtc));

  static String _k(String id, DateTime t) =>
      '$id|${t.toUtc().millisecondsSinceEpoch}';
}
