import 'alert.dart';

/// A named list of alerts plus profile-wide sound settings (spec §6).
class AlertProfile {
  const AlertProfile({
    required this.id,
    required this.name,
    required this.alerts,
    this.sound = const SoundSettings(),
    this.ringsInQuietMode = false,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final List<AlertSpec> alerts;
  final SoundSettings sound;
  final bool ringsInQuietMode;
  final bool builtIn;

  AlertProfile copyWith({
    String? name,
    List<AlertSpec>? alerts,
    SoundSettings? sound,
    bool? ringsInQuietMode,
  }) => AlertProfile(
    id: id,
    name: name ?? this.name,
    alerts: alerts ?? this.alerts,
    sound: sound ?? this.sound,
    ringsInQuietMode: ringsInQuietMode ?? this.ringsInQuietMode,
    builtIn: builtIn,
  );

  @override
  bool operator ==(Object other) =>
      other is AlertProfile &&
      other.id == id &&
      other.name == name &&
      sameAlerts(other.alerts, alerts) &&
      other.sound == sound &&
      other.ringsInQuietMode == ringsInQuietMode &&
      other.builtIn == builtIn;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(alerts),
    sound,
    ringsInQuietMode,
    builtIn,
  );

  @override
  String toString() => 'AlertProfile($id, $name)';
}

/// Element-wise equality for alert lists (null equals only null).
bool sameAlerts(List<AlertSpec>? a, List<AlertSpec>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// JSON for an alert list, shared by profile and override storage:
/// `[{"offsetMinutes": 10, "strength": "headsUp"}, …]`.
List<Map<String, Object?>> alertsToJson(List<AlertSpec> alerts) => [
  for (final a in alerts)
    {'offsetMinutes': a.offsetMinutes, 'strength': a.strength.name},
];

List<AlertSpec> alertsFromJson(List<Object?> json) => [
  for (final raw in json.cast<Map<String, Object?>>())
    AlertSpec(
      raw['offsetMinutes'] as int,
      AlertStrength.values.byName(raw['strength'] as String),
    ),
];

/// The four built-in profiles from spec §6. The ids are part of the roadmap
/// contract (§4) and never change.
abstract final class BuiltInProfiles {
  static const meetingId = 'meeting';
  static const quickId = 'quick';
  static const importantId = 'important';
  static const silentId = 'silent';

  /// The global default when settings name none (spec §6).
  static const defaultId = meetingId;

  static const meeting = AlertProfile(
    id: meetingId,
    name: 'Meeting',
    alerts: [
      AlertSpec(10, AlertStrength.headsUp),
      AlertSpec(1, AlertStrength.alarm),
    ],
    builtIn: true,
  );

  static const quick = AlertProfile(
    id: quickId,
    name: 'Quick',
    alerts: [AlertSpec(1, AlertStrength.alarm)],
    builtIn: true,
  );

  static const important = AlertProfile(
    id: importantId,
    name: 'Important',
    alerts: [
      AlertSpec(30, AlertStrength.headsUp),
      AlertSpec(10, AlertStrength.headsUp),
      AlertSpec(2, AlertStrength.alarm),
    ],
    ringsInQuietMode: true,
    builtIn: true,
  );

  static const silent = AlertProfile(
    id: silentId,
    name: 'Silent',
    alerts: [],
    builtIn: true,
  );

  /// In display order: Meeting · Quick · Important · Silent.
  static const all = [meeting, quick, important, silent];
}
