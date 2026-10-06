import '../model/alert.dart';

/// Settings screens `openPermissionSettings` can open (roadmap §3).
enum PermissionKind {
  notifications,
  fullScreenIntent,
  exactAlarm,
  batteryOptimization,
  alarmVolume,
}

/// What one `applyPlan` changed in AlarmManager.
class ApplyResult {
  const ApplyResult({
    required this.armed,
    required this.cancelled,
    required this.kept,
  });

  factory ApplyResult.fromJson(Map<String, Object?> j) => ApplyResult(
    armed: j['armed'] as int,
    cancelled: j['cancelled'] as int,
    kept: j['kept'] as int,
  );

  final int armed;
  final int cancelled;
  final int kept;

  @override
  bool operator ==(Object other) =>
      other is ApplyResult &&
      other.armed == armed &&
      other.cancelled == cancelled &&
      other.kept == kept;

  @override
  int get hashCode => Object.hash(armed, cancelled, kept);

  @override
  String toString() =>
      'ApplyResult(armed: $armed, cancelled: $cancelled, kept: $kept)';
}

/// One alert as the native engine has it scheduled.
class UpcomingAlert {
  const UpcomingAlert({
    required this.id,
    required this.fireAtUtc,
    required this.strength,
    required this.title,
  });

  factory UpcomingAlert.fromJson(Map<String, Object?> j) => UpcomingAlert(
    id: j['id'] as String,
    fireAtUtc: _utc(j['fireAtUtcMs'] as int),
    strength: AlertStrength.values.byName(j['strength'] as String),
    title: j['title'] as String,
  );

  final String id;
  final DateTime fireAtUtc;
  final AlertStrength strength;
  final String title;
}

/// The permission and scheduling state Health shows (spec §9).
class EngineHealth {
  const EngineHealth({
    required this.notificationsEnabled,
    required this.canUseFullScreenIntent,
    required this.canScheduleExactAlarms,
    required this.ignoringBatteryOptimizations,
    required this.alarmStreamMuted,
    required this.upcoming,
  });

  factory EngineHealth.fromJson(Map<String, Object?> j) => EngineHealth(
    notificationsEnabled: j['notificationsEnabled'] as bool,
    canUseFullScreenIntent: j['canUseFullScreenIntent'] as bool,
    canScheduleExactAlarms: j['canScheduleExactAlarms'] as bool,
    ignoringBatteryOptimizations: j['ignoringBatteryOptimizations'] as bool,
    alarmStreamMuted: j['alarmStreamMuted'] as bool,
    upcoming: [
      for (final u in j['upcoming'] as List<Object?>)
        UpcomingAlert.fromJson((u as Map).cast<String, Object?>()),
    ],
  );

  final bool notificationsEnabled;
  final bool canUseFullScreenIntent;
  final bool canScheduleExactAlarms;
  final bool ignoringBatteryOptimizations;
  final bool alarmStreamMuted;

  /// At most five, soonest first.
  final List<UpcomingAlert> upcoming;
}

enum EngineEventType { fired, snoozed, dismissed, dismissedAll, joined, missed }

/// One entry of the `alarm_engine/events` stream or the drained queue (roadmap §3).
class EngineEvent {
  const EngineEvent({
    required this.type,
    required this.alertId,
    required this.occurrenceKey,
    required this.startUtc,
    required this.atUtc,
    this.snoozeUntilUtc,
  });

  factory EngineEvent.fromJson(Map<String, Object?> j) {
    final snoozeUntil = j['snoozeUntilUtcMs'] as int?;
    return EngineEvent(
      type: EngineEventType.values.byName(j['type'] as String),
      alertId: j['alertId'] as String,
      occurrenceKey: j['occurrenceKey'] as String,
      startUtc: _utc(j['startUtcMs'] as int),
      atUtc: _utc(j['atUtcMs'] as int),
      snoozeUntilUtc: snoozeUntil == null ? null : _utc(snoozeUntil),
    );
  }

  final EngineEventType type;
  final String alertId;
  final String occurrenceKey;
  final DateTime startUtc;
  final DateTime atUtc;
  final DateTime? snoozeUntilUtc;

  /// Dart de-duplicates on (type, alertId, atUtcMs) (roadmap §3).
  String get dedupKey =>
      '${type.name}|$alertId|${atUtc.millisecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      other is EngineEvent &&
      other.type == type &&
      other.alertId == alertId &&
      other.occurrenceKey == occurrenceKey &&
      other.startUtc == startUtc &&
      other.atUtc == atUtc &&
      other.snoozeUntilUtc == snoozeUntilUtc;

  @override
  int get hashCode => Object.hash(
    type,
    alertId,
    occurrenceKey,
    startUtc,
    atUtc,
    snoozeUntilUtc,
  );
}

DateTime _utc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
