import 'alert.dart';

/// What the native engine needs to ring and show an alert without Flutter.
class EventSnapshot {
  const EventSnapshot({
    required this.title,
    required this.startUtc,
    required this.endUtc,
    this.location,
    this.joinUrl,
    required this.color,
  });
  final String title;
  final DateTime startUtc;
  final DateTime endUtc;
  final String? location;
  final String? joinUrl;
  final int color; // ARGB, e.g. 0xFF6AA0F5

  Map<String, Object?> toJson() => {
        'title': title,
        'startUtcMs': startUtc.millisecondsSinceEpoch,
        'endUtcMs': endUtc.millisecondsSinceEpoch,
        'location': location,
        'joinUrl': joinUrl,
        'color': color,
      };

  factory EventSnapshot.fromJson(Map<String, Object?> j) => EventSnapshot(
        title: j['title'] as String,
        startUtc: DateTime.fromMillisecondsSinceEpoch(j['startUtcMs'] as int, isUtc: true),
        endUtc: DateTime.fromMillisecondsSinceEpoch(j['endUtcMs'] as int, isUtc: true),
        location: j['location'] as String?,
        joinUrl: j['joinUrl'] as String?,
        color: j['color'] as int,
      );
}

class PlannedAlert {
  const PlannedAlert({
    required this.id,
    required this.occurrenceKey,
    required this.fireAtUtc,
    required this.offsetMinutes,
    required this.strength,
    required this.sound,
    required this.event,
    required this.coalesceGroup,
  });

  final String id;            // PlannedAlert.idFor(occurrenceKey, offsetMinutes)
  final String occurrenceKey;
  final DateTime fireAtUtc;   // event.startUtc - offsetMinutes
  final int offsetMinutes;
  final AlertStrength strength;
  final SoundSettings sound;
  final EventSnapshot event;
  final String coalesceGroup; // PlannedAlert.groupFor(fireAtUtc)

  /// Stable id: FNV-1a 64-bit of "$occurrenceKey|$offsetMinutes", 16 lowercase hex chars.
  static String idFor(String occurrenceKey, int offsetMinutes) {
    var hash = 0xcbf29ce484222325; // 64-bit VM ints wrap on overflow
    for (final unit in '$occurrenceKey|$offsetMinutes'.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    // Print as unsigned: toRadixString on a negative int would emit a '-'.
    String hex32(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return hex32(hash >> 32) + hex32(hash);
  }

  /// Alerts in the same UTC minute share a group: "yyyy-MM-ddTHH:mmZ".
  static String groupFor(DateTime fireAtUtc) {
    final t = fireAtUtc.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}Z';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'occurrenceKey': occurrenceKey,
        'fireAtUtcMs': fireAtUtc.millisecondsSinceEpoch,
        'offsetMinutes': offsetMinutes,
        'strength': strength.name, // "headsUp" | "alarm"
        'sound': sound.toJson(),
        'event': event.toJson(),
        'coalesceGroup': coalesceGroup,
      };

  factory PlannedAlert.fromJson(Map<String, Object?> j) => PlannedAlert(
        id: j['id'] as String,
        occurrenceKey: j['occurrenceKey'] as String,
        fireAtUtc: DateTime.fromMillisecondsSinceEpoch(j['fireAtUtcMs'] as int, isUtc: true),
        offsetMinutes: j['offsetMinutes'] as int,
        strength: AlertStrength.values.byName(j['strength'] as String),
        sound: SoundSettings.fromJson((j['sound'] as Map).cast<String, Object?>()),
        event: EventSnapshot.fromJson((j['event'] as Map).cast<String, Object?>()),
        coalesceGroup: j['coalesceGroup'] as String,
      );
}
