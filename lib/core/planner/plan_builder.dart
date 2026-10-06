import '../model/alert.dart';
import '../model/planned_alert.dart';
import '../rules/resolved_occurrence.dart';
import 'acknowledgements.dart';

/// Turns resolved occurrences into the plan the native engine arms.
///
/// - fireAt = start − offset.
/// - Every alert of an occurrence is listed until the occurrence ends
///   (`endUtc > now`), even alerts whose fireAt has passed. Kotlin never arms
///   past alerts, but an occurrenceKey missing from the plan tells it the
///   meeting is gone, and it then drops that occurrence's snoozes (roadmap
///   §3 "Engine rules"). Occurrences that have ended are dropped entirely.
/// - Occurrences acked by Dismiss all / Join at the same start are dropped.
/// - Single alerts dismissed at the same start are dropped.
/// - Two alerts with the same offset would share an id, so only one is kept:
///   the alarm if either is an alarm.
/// - Sorted by fireAt, then id.
List<PlannedAlert> buildPlan(
  Iterable<ResolvedOccurrence> resolved, {
  required DateTime now,
  Acknowledgements? acknowledgements,
}) {
  final acks = acknowledgements ?? Acknowledgements.empty;
  final nowUtc = now.toUtc();
  final plan = <PlannedAlert>[];

  for (final r in resolved) {
    final o = r.occurrence;
    if (r.alerts.isEmpty) continue;
    if (!o.endUtc.isAfter(nowUtc)) continue;
    if (acks.isOccurrenceAcked(o.key, o.startUtc)) continue;

    final byOffset = <int, AlertSpec>{};
    for (final a in r.alerts) {
      final existing = byOffset[a.offsetMinutes];
      if (existing == null || a.strength == AlertStrength.alarm) {
        byOffset[a.offsetMinutes] = a;
      }
    }

    final snapshot = EventSnapshot(
      title: o.title,
      startUtc: o.startUtc,
      endUtc: o.endUtc,
      location: o.location,
      joinUrl: o.joinUrl,
      color: o.calendarColor,
    );

    for (final a in byOffset.values) {
      final fireAt = o.startUtc.subtract(Duration(minutes: a.offsetMinutes));
      final id = PlannedAlert.idFor(o.key, a.offsetMinutes);
      if (acks.isAlertDismissed(id, o.startUtc)) continue;
      plan.add(
        PlannedAlert(
          id: id,
          occurrenceKey: o.key,
          fireAtUtc: fireAt,
          offsetMinutes: a.offsetMinutes,
          strength: a.strength,
          sound: r.profile.sound,
          event: snapshot,
          coalesceGroup: PlannedAlert.groupFor(fireAt),
        ),
      );
    }
  }

  plan.sort((a, b) {
    final byTime = a.fireAtUtc.compareTo(b.fireAtUtc);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return plan;
}
