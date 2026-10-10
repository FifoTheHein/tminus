import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/sync/missed_system.dart';
import 'package:tminus/core/sync/pre_sync.dart';

final _start = DateTime.utc(2026, 10, 6, 8);

PlannedAlert planned(
  String key,
  int offset, {
  DateTime? start,
  AlertStrength strength = AlertStrength.alarm,
}) {
  final s = start ?? _start;
  final fireAt = s.subtract(Duration(minutes: offset));
  return PlannedAlert(
    id: PlannedAlert.idFor(key, offset),
    occurrenceKey: key,
    fireAtUtc: fireAt,
    offsetMinutes: offset,
    strength: strength,
    sound: const SoundSettings(),
    event: EventSnapshot(
      title: 'Meeting $key',
      startUtc: s,
      endUtc: s.add(const Duration(minutes: 30)),
      color: 0xFF6AA0F5,
    ),
    coalesceGroup: PlannedAlert.groupFor(fireAt),
  );
}

AlertHistoryEntry event(AlertEventType type, PlannedAlert a, DateTime at) =>
    AlertHistoryEntry(
      type: type,
      alertId: a.id,
      occurrenceKey: a.occurrenceKey,
      startUtc: a.event.startUtc,
      atUtc: at,
    );

void main() {
  final alarm = planned('k1', 1); // fires 07:59
  final expected = ExpectedAlert.of(alarm);
  final fireAt = alarm.fireAtUtc;

  MissedCheck check(List<AlertHistoryEntry> history, DateTime now) =>
      MissedSystemDetector.check(
        expected: [expected],
        history: history,
        now: now,
      );

  group('check', () {
    test('an alert inside its 2 min grace stays pending', () {
      final r = check([], fireAt.add(const Duration(minutes: 2)));
      expect(r.missed, isEmpty);
      expect(r.pending, [expected]);
    });

    test('no fired record by fireAt + 2 min is missed (system)', () {
      final r = check([], fireAt.add(const Duration(minutes: 2, seconds: 1)));
      expect(r.pending, isEmpty);
      final m = r.missed.single;
      expect(m.type, AlertEventType.missedSystem);
      expect(m.alertId, alarm.id);
      expect(m.occurrenceKey, 'k1');
      expect(m.startUtc, _start);
      expect(m.atUtc, fireAt);
      expect(m.title, 'Meeting k1');
    });

    test('a fired record in time clears it', () {
      final r = check([
        event(
          AlertEventType.fired,
          alarm,
          fireAt.add(const Duration(seconds: 3)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, isEmpty);
      expect(r.pending, isEmpty);
    });

    test('an alert that rang more than 2 min late still counts', () {
      final r = check([
        event(
          AlertEventType.fired,
          alarm,
          fireAt.add(const Duration(minutes: 5)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, hasLength(1));
    });

    test('a fired record for another start does not count', () {
      final other = planned(
        'k1',
        1,
        start: _start.add(const Duration(days: 7)),
      );
      final r = check([
        event(AlertEventType.fired, other, fireAt),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, hasLength(1));
    });

    test('Dismiss all or Join before the alert time excuses it', () {
      final headsUp = planned('k1', 10);
      for (final type in [AlertEventType.dismissedAll, AlertEventType.joined]) {
        final r = check([
          event(type, headsUp, headsUp.fireAtUtc),
        ], fireAt.add(const Duration(hours: 1)));
        expect(r.missed, isEmpty, reason: type.name);
      }
    });

    test('an acknowledgement after the alert time does not excuse it', () {
      final r = check([
        event(
          AlertEventType.dismissedAll,
          alarm,
          fireAt.add(const Duration(minutes: 1)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, hasLength(1));
    });

    test(
      'an alert the engine already recorded as missed is not reported again',
      () {
        // The phone was off for the whole meeting: the engine logged `missed`
        // when it came back, long after the 2 min grace.
        final overdue = check([
          event(
            AlertEventType.missed,
            alarm,
            fireAt.add(const Duration(hours: 2)),
          ),
        ], fireAt.add(const Duration(hours: 3)));
        expect(overdue.missed, isEmpty, reason: 'after the grace period');
        expect(overdue.pending, isEmpty, reason: 'after the grace period');

        // Inside the grace period it is not held back as pending either.
        final inGrace = check([
          event(
            AlertEventType.missed,
            alarm,
            fireAt.add(const Duration(seconds: 30)),
          ),
        ], fireAt.add(const Duration(minutes: 1)));
        expect(inGrace.missed, isEmpty, reason: 'inside the grace period');
        expect(inGrace.pending, isEmpty, reason: 'inside the grace period');

        // A row for another start of the same alert is another occurrence.
        final otherStart = planned(
          'k1',
          1,
          start: _start.add(const Duration(days: 7)),
        );
        final forOtherStart = check([
          event(AlertEventType.missed, otherStart, fireAt),
        ], fireAt.add(const Duration(hours: 1)));
        expect(forOtherStart.missed, hasLength(1), reason: 'another start');

        // A row for another alert of the same occurrence does not excuse it.
        final forOtherAlert = check([
          event(AlertEventType.missed, planned('k1', 10), fireAt),
        ], fireAt.add(const Duration(hours: 1)));
        expect(forOtherAlert.missed, hasLength(1), reason: 'another alert');
      },
    );

    test('a late ring that then timed out is still missed (system)', () {
      // The engine also logs `missed` when a ring times out unanswered, so a
      // `missed` row next to a `fired` record is not the phone-off case.
      final rangLate = check([
        event(
          AlertEventType.fired,
          alarm,
          fireAt.add(const Duration(minutes: 5)),
        ),
        event(
          AlertEventType.missed,
          alarm,
          fireAt.add(const Duration(minutes: 7)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(rangLate.pending, isEmpty);
      final m = rangLate.missed.single;
      expect(m.type, AlertEventType.missedSystem);
      expect(m.alertId, alarm.id);
      expect(m.atUtc, fireAt);

      // Rang in time and then timed out: nothing for the system to answer for.
      final rangInTime = check([
        event(
          AlertEventType.fired,
          alarm,
          fireAt.add(const Duration(seconds: 3)),
        ),
        event(
          AlertEventType.missed,
          alarm,
          fireAt.add(const Duration(minutes: 2, seconds: 3)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(rangInTime.missed, isEmpty, reason: 'rang in time');
      expect(rangInTime.pending, isEmpty, reason: 'rang in time');

      // A `fired` record for another start is not this alert ringing, so the
      // engine's `missed` row still excuses it.
      final otherStart = planned(
        'k1',
        1,
        start: _start.add(const Duration(days: 7)),
      );
      final firedForOtherStart = check([
        event(AlertEventType.fired, otherStart, fireAt),
        event(
          AlertEventType.missed,
          alarm,
          fireAt.add(const Duration(hours: 2)),
        ),
      ], fireAt.add(const Duration(hours: 3)));
      expect(firedForOtherStart.missed, isEmpty, reason: 'another start');
      expect(firedForOtherStart.pending, isEmpty, reason: 'another start');
    });
  });

  group('expectedAfterApply', () {
    final now = DateTime.utc(2026, 10, 6, 7, 55);

    test(
      'future alerts are expected; past ones that were never expected are not',
      () {
        final r = MissedSystemDetector.expectedAfterApply(
          pending: const [],
          plan: [
            planned('k1', 10),
            planned('k1', 1),
          ], // 07:50 past, 07:59 future
          now: now,
        );
        expect(r, [ExpectedAlert.of(planned('k1', 1))]);
      },
    );

    test(
      'a pending alert still in the plan at the same time is carried over',
      () {
        final headsUp = planned('k1', 10);
        final r = MissedSystemDetector.expectedAfterApply(
          pending: [ExpectedAlert.of(headsUp)],
          plan: [headsUp, planned('k1', 1)],
          now: now,
        );
        expect(r.map((e) => e.id), [headsUp.id, planned('k1', 1).id]);
      },
    );

    test('a pending alert that was removed or moved is dropped', () {
      final headsUp = planned('k1', 10);
      final moved = planned(
        'k1',
        10,
        start: _start.subtract(const Duration(minutes: 1)),
      );
      final r = MissedSystemDetector.expectedAfterApply(
        pending: [ExpectedAlert.of(headsUp)],
        plan: [moved],
        now: now,
      );
      expect(r, isEmpty);
    });
  });

  test('expected alerts round-trip through JSON; junk reads as none', () {
    final list = [expected, ExpectedAlert.of(planned('k2', 10))];
    expect(
      MissedSystemDetector.decode(MissedSystemDetector.encode(list)),
      list,
    );
    expect(MissedSystemDetector.decode(null), isEmpty);
    expect(MissedSystemDetector.decode('{not json'), isEmpty);
    expect(MissedSystemDetector.decode('[{"id": 1}]'), isEmpty);
  });

  group('preSyncTimes', () {
    test('one time per occurrence, 12 min before its earliest alert', () {
      final now = DateTime.utc(2026, 10, 6, 6);
      final later = _start.add(const Duration(hours: 2));
      final times = preSyncTimes([
        planned('k1', 30, strength: AlertStrength.headsUp),
        planned('k1', 10, strength: AlertStrength.headsUp),
        planned('k1', 2),
        planned('k2', 1, start: later),
      ], now);
      expect(times, [
        DateTime.utc(2026, 10, 6, 7, 18), // 08:00 − 30 − 12
        DateTime.utc(2026, 10, 6, 9, 47), // 10:00 − 1 − 12
      ]);
    });

    test(
      'an occurrence whose first alert already passed gets no second pre-sync',
      () {
        final now = DateTime.utc(2026, 10, 6, 7, 40); // after the −30 alert
        expect(
          preSyncTimes([planned('k1', 30), planned('k1', 2)], now),
          isEmpty,
        );
      },
    );

    test('occurrences sharing a time share one entry', () {
      final now = DateTime.utc(2026, 10, 6, 6);
      expect(preSyncTimes([planned('a', 1), planned('b', 1)], now), [
        DateTime.utc(2026, 10, 6, 7, 47),
      ]);
    });
  });
}
