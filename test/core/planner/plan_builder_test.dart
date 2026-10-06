import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/planner/acknowledgements.dart';
import 'package:tminus/core/planner/plan_builder.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';

import '../fixtures.dart';

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

  test('every alert of an occurrence that has ended is dropped', () {
    expect(
      buildPlan([resolved(planning)], now: DateTime.utc(2026, 10, 6, 8, 30)),
      isEmpty,
      reason: 'endUtc == now counts as ended',
    );
    final plan = buildPlan([
      resolved(planning),
      resolved(standup), // 06:45–07:15, ended
    ], now: DateTime.utc(2026, 10, 6, 7, 20));
    expect(plan.map((a) => a.occurrenceKey).toSet(), {planning.key});
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
}
