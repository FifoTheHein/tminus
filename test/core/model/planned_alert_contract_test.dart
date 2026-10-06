import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/planned_alert.dart';

void main() {
  group('PlannedAlert.idFor', () {
    test('matches known FNV-1a values (shared with Plan 3)', () {
      expect(PlannedAlert.idFor('a', 10), '0eee2d83f9209539');
      expect(
        PlannedAlert.idFor('src|uid1|2026-10-06T08:00:00.000Z', 10),
        '88116ba1896be5a4',
      );
    });

    test('is stable across calls', () {
      const key = 'work|abc|2026-10-06T08:00:00.000Z';
      expect(PlannedAlert.idFor(key, 1), PlannedAlert.idFor(key, 1));
    });

    test('differs for different offsets and keys', () {
      const key = 'work|abc|2026-10-06T08:00:00.000Z';
      final ids = {
        PlannedAlert.idFor(key, 0),
        PlannedAlert.idFor(key, 1),
        PlannedAlert.idFor(key, 10),
        PlannedAlert.idFor('work|abd|2026-10-06T08:00:00.000Z', 1),
      };
      expect(ids, hasLength(4));
    });

    test('is always 16 lowercase hex chars, never signed', () {
      final hex = RegExp(r'^[0-9a-f]{16}$');
      for (var i = 0; i < 500; i++) {
        final id = PlannedAlert.idFor('k$i', i % 60);
        expect(id, matches(hex), reason: 'k$i');
      }
    });
  });

  group('PlannedAlert.groupFor', () {
    test('formats the UTC minute', () {
      expect(
        PlannedAlert.groupFor(DateTime.utc(2026, 3, 9, 7, 5, 59)),
        '2026-03-09T07:05Z',
      );
    });

    test('converts local times to UTC first', () {
      final local = DateTime.utc(2026, 10, 6, 7, 59).toLocal();
      expect(PlannedAlert.groupFor(local), '2026-10-06T07:59Z');
    });

    test('same minute, same group; next minute, new group', () {
      final a = PlannedAlert.groupFor(DateTime.utc(2026, 10, 6, 8, 0, 0));
      final b = PlannedAlert.groupFor(DateTime.utc(2026, 10, 6, 8, 0, 59, 999));
      final c = PlannedAlert.groupFor(DateTime.utc(2026, 10, 6, 8, 1));
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  test('toJson/fromJson round trip survives jsonEncode', () {
    final start = DateTime.utc(2026, 10, 6, 8);
    const key = 'work|abc|2026-10-06T08:00:00.000Z';
    final fireAt = start.subtract(const Duration(minutes: 10));
    final alert = PlannedAlert(
      id: PlannedAlert.idFor(key, 10),
      occurrenceKey: key,
      fireAtUtc: fireAt,
      offsetMinutes: 10,
      strength: AlertStrength.headsUp,
      sound: const SoundSettings(
        toneUri: 'content://tone/1',
        vibrate: false,
        ringTimeout: Duration(seconds: 90),
      ),
      event: EventSnapshot(
        title: 'Sprint planning',
        startUtc: start,
        endUtc: start.add(const Duration(hours: 1)),
        location: 'Teams',
        joinUrl: 'https://teams.microsoft.com/l/meetup-join/x',
        color: 0xFF6AA0F5,
      ),
      coalesceGroup: PlannedAlert.groupFor(fireAt),
    );

    final json = jsonDecode(jsonEncode(alert.toJson())) as Map<String, Object?>;
    final back = PlannedAlert.fromJson(json);

    expect(json['strength'], 'headsUp');
    expect(back.id, alert.id);
    expect(back.occurrenceKey, key);
    expect(back.fireAtUtc, fireAt);
    expect(back.fireAtUtc.isUtc, isTrue);
    expect(back.offsetMinutes, 10);
    expect(back.strength, AlertStrength.headsUp);
    expect(back.sound, alert.sound);
    expect(back.event.title, 'Sprint planning');
    expect(back.event.startUtc, start);
    expect(back.event.endUtc, start.add(const Duration(hours: 1)));
    expect(back.event.location, 'Teams');
    expect(back.event.joinUrl, 'https://teams.microsoft.com/l/meetup-join/x');
    expect(back.event.color, 0xFF6AA0F5);
    expect(back.coalesceGroup, '2026-10-06T07:50Z');
    expect(back.toJson(), alert.toJson());
  });
}
