import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/planner/acknowledgements.dart';
import 'package:tminus/core/planner/plan_builder.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';

import '../fixtures.dart';
import '../rules/rules_test_helpers.dart' show meetingOf;

final now = DateTime.utc(2026, 10, 6, 6);

ResolvedOccurrence resolved(
  EventOccurrence o, {
  AlertProfile profile = BuiltInProfiles.meeting,
  List<AlertSpec>? alerts,
}) => ResolvedOccurrence(
  occurrence: o,
  profile: profile,
  alerts: alerts ?? profile.alerts,
  explanation: '${profile.name} · default',
  silenced: false,
  step: ResolutionStep.globalDefault,
);

void main() {
  final standup = occ(
    uid: 'standup',
    title: 'Daily standup',
    start: DateTime.utc(2026, 10, 6, 6, 45),
    location: 'Teams',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/1',
  );
  final planning = occ(uid: 'planning', start: DateTime.utc(2026, 10, 6, 8));

  test('fireAt = start − offset, with id, group, snapshot and sound', () {
    const loud = SoundSettings(toneUri: 'content://tone/9', vibrate: false);
    final profile = BuiltInProfiles.quick.copyWith(sound: loud);
    final plan = buildPlan([resolved(standup, profile: profile)], now: now);

    expect(plan, hasLength(1));
    final a = plan.single;
    expect(a.id, PlannedAlert.idFor(standup.key, 1));
    expect(a.occurrenceKey, standup.key);
    expect(a.fireAtUtc, DateTime.utc(2026, 10, 6, 6, 44));
    expect(a.offsetMinutes, 1);
    expect(a.strength, AlertStrength.alarm);
    expect(a.sound, loud);
    expect(a.coalesceGroup, '2026-10-06T06:44Z');
    expect(a.event.title, 'Daily standup');
    expect(a.event.startUtc, standup.startUtc);
    expect(a.event.endUtc, standup.endUtc);
    expect(a.event.location, 'Teams');
    expect(a.event.joinUrl, standup.joinUrl);
    expect(a.event.color, blue);
  });

  test('sorted by fireAt, then id', () {
    final twin = occ(uid: 'twin', start: DateTime.utc(2026, 10, 6, 8));
    final plan = buildPlan([
      resolved(planning),
      resolved(standup),
      resolved(twin),
    ], now: now);
    final times = plan.map((a) => a.fireAtUtc).toList();
    expect(times, [...times]..sort());
    final atSameMinute = plan.where(
      (a) => a.fireAtUtc == DateTime.utc(2026, 10, 6, 7, 50),
    );
    expect(
      atSameMinute.map((a) => a.id),
      [...atSameMinute.map((a) => a.id)]..sort(),
    );
  });

  test('ids are stable across rebuilds', () {
    final first = buildPlan([resolved(planning)], now: now);
    final again = buildPlan([
      resolved(planning.copyWith(title: 'Renamed')),
    ], now: now.add(const Duration(minutes: 5)));
    expect(again.map((a) => a.id), first.map((a) => a.id));
  });

  test('past alerts of an occurrence that has not ended are kept', () {
    // planning: 08:00–08:30; headsUp −10 at 07:50, alarm −1 at 07:59.
    // Kotlin needs the occurrenceKey in the plan to keep a snooze alive.
    final duringMeeting = buildPlan([
      resolved(planning),
    ], now: DateTime.utc(2026, 10, 6, 8, 15));
    expect(duringMeeting.map((a) => a.offsetMinutes), [10, 1]);
    expect(duringMeeting.map((a) => a.fireAtUtc), [
      DateTime.utc(2026, 10, 6, 7, 50),
      DateTime.utc(2026, 10, 6, 7, 59),
    ]);
    final oneMinuteBeforeEnd = buildPlan([
      resolved(planning),
    ], now: DateTime.utc(2026, 10, 6, 8, 29));
    expect(oneMinuteBeforeEnd, hasLength(2));
  });

  test('every alert of an occurrence that ended 15 min ago is dropped', () {
    // Decision 19: kept while max(end, start) + 15 min > now.
    expect(
      buildPlan([resolved(planning)], now: DateTime.utc(2026, 10, 6, 8, 45)),
      isEmpty,
      reason: 'endUtc + 15 min == now counts as gone',
    );
    final plan = buildPlan([
      resolved(planning),
      resolved(standup), // 06:45–07:15, gone at 07:30
    ], now: DateTime.utc(2026, 10, 6, 7, 30));
    expect(plan.map((a) => a.occurrenceKey).toSet(), {planning.key});
  });

  group('kept until 15 min after the end (decision 19)', () {
    test('a normal event 14 minutes after its end is kept', () {
      // planning ends 08:30.
      final plan = buildPlan([
        resolved(planning),
      ], now: DateTime.utc(2026, 10, 6, 8, 44));
      expect(plan.map((a) => a.offsetMinutes), [10, 1]);
    });

    test('an event that has just ended is kept', () {
      expect(
        buildPlan([resolved(planning)], now: DateTime.utc(2026, 10, 6, 8, 30)),
        hasLength(2),
      );
    });

    final zeroLength = occ(
      uid: 'zero',
      start: DateTime.utc(2026, 10, 6, 8),
      length: Duration.zero,
    );

    test('a zero-length event 10 minutes after its start is kept', () {
      final plan = buildPlan([
        resolved(zeroLength),
      ], now: DateTime.utc(2026, 10, 6, 8, 10));
      expect(plan.map((a) => a.offsetMinutes), [10, 1]);
    });

    test('a zero-length event 15 minutes after its start is dropped', () {
      expect(
        buildPlan([
          resolved(zeroLength),
        ], now: DateTime.utc(2026, 10, 6, 8, 15)),
        isEmpty,
      );
    });

    test('an end before the start counts from the start', () {
      final backwards = occ(
        uid: 'backwards',
        start: DateTime.utc(2026, 10, 6, 8),
        length: const Duration(minutes: -30),
      );
      expect(
        buildPlan([resolved(backwards)], now: DateTime.utc(2026, 10, 6, 8, 14)),
        hasLength(2),
      );
      expect(
        buildPlan([resolved(backwards)], now: DateTime.utc(2026, 10, 6, 8, 15)),
        isEmpty,
      );
    });
  });

  test('acks still drop past alerts of a running occurrence', () {
    final now = DateTime.utc(2026, 10, 6, 8, 5);
    expect(
      buildPlan(
        [resolved(planning)],
        now: now,
        acknowledgements: Acknowledgements(
          occurrences: [(planning.key, planning.startUtc)],
        ),
      ),
      isEmpty,
    );
    final plan = buildPlan(
      [resolved(planning)],
      now: now,
      acknowledgements: Acknowledgements(
        alerts: [(PlannedAlert.idFor(planning.key, 10), planning.startUtc)],
      ),
    );
    expect(plan.map((a) => a.offsetMinutes), [1]);
  });

  test('occurrences with no alerts produce nothing', () {
    expect(
      buildPlan([
        resolved(planning, profile: BuiltInProfiles.silent),
      ], now: now),
      isEmpty,
    );
  });

  test('custom alerts in ResolvedOccurrence are what gets planned', () {
    final plan = buildPlan([
      resolved(planning, alerts: const [AlertSpec(15, AlertStrength.alarm)]),
    ], now: now);
    expect(plan.single.offsetMinutes, 15);
  });

  test('duplicate offsets collapse to one alert, preferring the alarm', () {
    final plan = buildPlan([
      resolved(
        planning,
        alerts: const [
          AlertSpec(5, AlertStrength.alarm),
          AlertSpec(5, AlertStrength.headsUp),
        ],
      ),
    ], now: now);
    expect(plan, hasLength(1));
    expect(plan.single.strength, AlertStrength.alarm);
  });

  group('acknowledgements', () {
    test('Dismiss all drops every alert of that occurrence', () {
      final acks = Acknowledgements(
        occurrences: [(planning.key, planning.startUtc)],
      );
      final plan = buildPlan(
        [resolved(planning), resolved(standup)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.occurrenceKey).toSet(), {standup.key});
    });

    test('a moved meeting re-arms after Dismiss all', () {
      final acks = Acknowledgements(
        occurrences: [(planning.key, planning.startUtc)],
      );
      final moved = planning.copyWith(
        startUtc: DateTime.utc(2026, 10, 6, 9),
        endUtc: DateTime.utc(2026, 10, 6, 9, 30),
      );
      final plan = buildPlan(
        [resolved(moved)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.fireAtUtc), [
        DateTime.utc(2026, 10, 6, 8, 50),
        DateTime.utc(2026, 10, 6, 8, 59),
      ]);
      expect(plan.first.id, PlannedAlert.idFor(planning.key, 10));
    });

    test('single Dismiss drops only that alert', () {
      final headsUpId = PlannedAlert.idFor(planning.key, 10);
      final acks = Acknowledgements(alerts: [(headsUpId, planning.startUtc)]);
      final plan = buildPlan(
        [resolved(planning)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.offsetMinutes), [1]);
    });

    test('single Dismiss re-arms when the meeting moves', () {
      final headsUpId = PlannedAlert.idFor(planning.key, 10);
      final acks = Acknowledgements(alerts: [(headsUpId, planning.startUtc)]);
      final moved = planning.copyWith(startUtc: DateTime.utc(2026, 10, 6, 9));
      final plan = buildPlan(
        [resolved(moved)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.offsetMinutes), [10, 1]);
    });
  });

  test('alerts in the same UTC minute share a coalesce group', () {
    final other = occ(
      sourceId: 'personal',
      uid: 'x',
      start: DateTime.utc(2026, 10, 6, 8),
    );
    final plan = buildPlan([resolved(planning), resolved(other)], now: now);
    final groups = <String, List<String>>{};
    for (final a in plan) {
      groups.putIfAbsent(a.coalesceGroup, () => []).add(a.occurrenceKey);
    }
    expect(
      groups['2026-10-06T07:50Z'],
      unorderedEquals([planning.key, other.key]),
    );
    expect(
      groups['2026-10-06T07:59Z'],
      unorderedEquals([planning.key, other.key]),
    );
    expect(plan.map((a) => a.id).toSet(), hasLength(4));
  });

  group('a meeting found in several sources (spec §13)', () {
    // Ranked best first: the phone copy decides the time. All three start at
    // 08:00, so the Meeting profile's alerts are due at 07:50 and 07:59.
    final phone = occ(
      sourceId: 'phone',
      uid: 'p1',
      start: DateTime.utc(2026, 10, 6, 8),
    );
    final feed = occ(
      sourceId: 'feed',
      uid: 'f1',
      start: DateTime.utc(2026, 10, 6, 8),
    );
    final work = occ(
      sourceId: 'work',
      uid: 'w1',
      start: DateTime.utc(2026, 10, 6, 8),
    );
    // The key a source that has since gone gave the meeting. No copy has it.
    final meetingKey = EventOccurrence.makeKey(
      'gone',
      'm1',
      phone.originalStartUtc,
    );
    final meeting = meetingOf([phone, feed, work], meetingKey: meetingKey);

    test(
      'Dismiss all under a copy key drops the meeting at the same start',
      () {
        // The last copy's key is the one furthest down the lookup list.
        final plan = buildPlan(
          [resolved(meeting), resolved(standup)],
          now: now,
          acknowledgements: Acknowledgements(
            occurrences: [(work.key, meeting.startUtc)],
          ),
        );
        expect(plan.map((a) => a.occurrenceKey).toSet(), {standup.key});
      },
    );

    test(
      'Dismiss all under a copy key does not drop the meeting at a different '
      'start',
      () {
        final plan = buildPlan(
          [resolved(meeting)],
          now: now,
          acknowledgements: Acknowledgements(
            occurrences: [(work.key, DateTime.utc(2026, 10, 6, 7))],
          ),
        );
        expect(plan.map((a) => a.offsetMinutes), [10, 1]);
      },
    );

    test('Dismiss all under the meeting key drops the meeting', () {
      final plan = buildPlan(
        [resolved(meeting), resolved(standup)],
        now: now,
        acknowledgements: Acknowledgements(
          occurrences: [(meetingKey, meeting.startUtc)],
        ),
      );
      expect(plan.map((a) => a.occurrenceKey).toSet(), {standup.key});
    });

    test("a single dismissal under a copy key's alert id drops that offset "
        'only', () {
      final plan = buildPlan(
        [resolved(meeting)],
        now: now,
        acknowledgements: Acknowledgements(
          alerts: [(PlannedAlert.idFor(work.key, 10), meeting.startUtc)],
        ),
      );
      expect(plan.map((a) => a.offsetMinutes), [1]);
      expect(plan.single.id, PlannedAlert.idFor(meetingKey, 1));
    });

    test("a single dismissal under the meeting key's alert id drops that "
        'offset only', () {
      final plan = buildPlan(
        [resolved(meeting)],
        now: now,
        acknowledgements: Acknowledgements(
          alerts: [(PlannedAlert.idFor(meetingKey, 10), meeting.startUtc)],
        ),
      );
      expect(plan.map((a) => a.offsetMinutes), [1]);
    });

    test("a meeting's alerts are keyed by the meeting key", () {
      final plan = buildPlan([resolved(meeting)], now: now);
      expect(plan.map((a) => a.occurrenceKey).toSet(), {meetingKey});
      expect(plan.map((a) => a.id), [
        PlannedAlert.idFor(meetingKey, 10),
        PlannedAlert.idFor(meetingKey, 1),
      ]);
      for (final copy in [phone, feed, work]) {
        expect(
          plan.map((a) => a.id),
          isNot(contains(PlannedAlert.idFor(copy.key, 10))),
          reason: 'no alert id is built from ${copy.key}',
        );
      }
    });
  });
}
