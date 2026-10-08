import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/planned_alert.dart';

PlannedAlert sampleAlert() {
  const key = 'src|uid1|2026-10-06T08:00:00.000Z';
  final start = DateTime.utc(2026, 10, 6, 8);
  final fireAt = start.subtract(const Duration(minutes: 1));
  return PlannedAlert(
    id: PlannedAlert.idFor(key, 1),
    occurrenceKey: key,
    fireAtUtc: fireAt,
    offsetMinutes: 1,
    strength: AlertStrength.alarm,
    sound: const SoundSettings(
      toneUri: 'content://media/internal/audio/media/7',
    ),
    event: EventSnapshot(
      title: 'Sprint planning',
      startUtc: start,
      endUtc: start.add(const Duration(hours: 1)),
      location: null,
      joinUrl: 'https://teams.microsoft.com/l/meetup-join/abc',
      color: 0xFF6AA0F5,
    ),
    coalesceGroup: PlannedAlert.groupFor(fireAt),
  );
}

void main() {
  group('PlannedAlert.idFor', () {
    test('matches the known values in roadmap §3', () {
      expect(PlannedAlert.idFor('a', 10), '0eee2d83f9209539');
      expect(
        PlannedAlert.idFor('src|uid1|2026-10-06T08:00:00.000Z', 10),
        '88116ba1896be5a4',
      );
    });

    test('is always 16 lowercase hex characters, never negative', () {
      final hex = RegExp(r'^[0-9a-f]{16}$');
      for (var i = 0; i < 500; i++) {
        final id = PlannedAlert.idFor(
          'src|uid$i|2026-10-06T08:00:00.000Z',
          i % 31,
        );
        expect(id, matches(hex), reason: 'uid$i');
      }
    });

    test('differs by offset', () {
      expect(PlannedAlert.idFor('k', 1), isNot(PlannedAlert.idFor('k', 10)));
    });
  });

  test('groupFor formats the UTC minute', () {
    expect(
      PlannedAlert.groupFor(DateTime.utc(2026, 10, 6, 7, 59, 30)),
      '2026-10-06T07:59Z',
    );
    expect(
      PlannedAlert.groupFor(DateTime.parse('2026-10-06T09:59:00+02:00')),
      '2026-10-06T07:59Z',
    );
  });

  test('PlannedAlert survives a JSON round trip', () {
    final alert = sampleAlert();
    final decoded = PlannedAlert.fromJson(
      (jsonDecode(jsonEncode(alert.toJson())) as Map).cast<String, Object?>(),
    );
    expect(decoded.toJson(), alert.toJson());
    expect(decoded.sound, alert.sound);
  });

  test('toJson uses the channel wire names', () {
    final json = sampleAlert().toJson();
    expect(json.keys, [
      'id',
      'occurrenceKey',
      'fireAtUtcMs',
      'offsetMinutes',
      'strength',
      'sound',
      'event',
      'coalesceGroup',
    ]);
    expect(json['strength'], 'alarm');
    expect((json['sound']! as Map)['ringTimeoutSec'], 120);
    expect(
      (json['event']! as Map)['startUtcMs'],
      DateTime.utc(2026, 10, 6, 8).millisecondsSinceEpoch,
    );
  });

  test('AlertSpec and SoundSettings compare by value', () {
    expect(
      const AlertSpec(10, AlertStrength.headsUp),
      const AlertSpec(10, AlertStrength.headsUp),
    );
    expect(const SoundSettings(), isNot(const SoundSettings(vibrate: false)));
  });
}
