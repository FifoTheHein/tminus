import 'utc.dart';

/// Engine event types (roadmap §3 EngineEvent `type`) plus [missedSystem],
/// which Plan 4 records when an alert's time passed by more than 2 min with
/// no `fired` record (spec §9).
enum AlertEventType {
  fired,
  snoozed,
  dismissed,
  dismissedAll,
  joined,
  missed,
  missedSystem,
}

/// One row of `alert_history`. Plan 4 maps each drained EngineEvent to one.
class AlertHistoryEntry {
  AlertHistoryEntry({
    required this.type,
    required this.alertId,
    required this.occurrenceKey,
    required DateTime startUtc,
    required DateTime atUtc,
    DateTime? snoozeUntilUtc,
    this.title,
  }) : startUtc = plainUtc(startUtc),
       atUtc = plainUtc(atUtc),
       snoozeUntilUtc = snoozeUntilUtc == null
           ? null
           : plainUtc(snoozeUntilUtc);

  final AlertEventType type;

  /// A `PlannedAlert.id`, or a snooze id ending in `:s`.
  final String alertId;
  final String occurrenceKey;

  /// The occurrence start the engine had when the event happened.
  final DateTime startUtc;

  /// When the event happened.
  final DateTime atUtc;
  final DateTime? snoozeUntilUtc;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is AlertHistoryEntry &&
      other.type == type &&
      other.alertId == alertId &&
      other.occurrenceKey == occurrenceKey &&
      other.startUtc == startUtc &&
      other.atUtc == atUtc &&
      other.snoozeUntilUtc == snoozeUntilUtc &&
      other.title == title;

  @override
  int get hashCode => Object.hash(
    type,
    alertId,
    occurrenceKey,
    startUtc,
    atUtc,
    snoozeUntilUtc,
    title,
  );

  @override
  String toString() => 'AlertHistoryEntry(${type.name}, $alertId, $atUtc)';
}
