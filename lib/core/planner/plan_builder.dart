import '../model/alert_profile.dart';
import '../model/planned_alert.dart';
import '../rules/resolved_occurrence.dart';
import 'acknowledgements.dart';

/// Turns resolved occurrences into the plan the native engine arms.
///
/// - fireAt = start − offset.
/// - Every alert of an occurrence is listed until [keepAfterEnd] after the
///   occurrence ends (`max(end, start) + 15 min > now`, decision 19), even
///   alerts whose fireAt has passed. Kotlin never arms past alerts, but an
///   occurrenceKey missing from the plan tells it the meeting is gone, and it
///   then drops that occurrence's snoozes (roadmap §3 "Engine rules"). The
///   grace period keeps snoozes alive for events with no duration and for
///   snoozes that run past the end. Later, the occurrence is dropped
///   entirely.
/// - Occurrences acked by Dismiss all / Join at the same start are dropped.
/// - Single alerts dismissed at the same start are dropped.
/// - Acks are looked up under every key in the occurrence's `lookupKeys`, so
///   one recorded under a copy's key still holds for a meeting (spec §13). Ids
///   and `occurrenceKey` always use the occurrence's own key.
/// - Two alerts with the same offset would share an id, so only one is kept:
///   the alarm if either is an alarm.
/// - Sorted by fireAt, then id.
/// How long an occurrence stays in the plan after it ends (decision 19).
const keepAfterEnd = Duration(minutes: 15);

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
    final end = o.endUtc.isAfter(o.startUtc) ? o.endUtc : o.startUtc;
    if (!end.add(keepAfterEnd).isAfter(nowUtc)) continue;
    final keys = o.lookupKeys;
    if (acks.isAnyOccurrenceAcked(keys, o.startUtc)) continue;

    // The engine already collapses duplicates; this guard covers a
    // ResolvedOccurrence built elsewhere.
    final alerts = onePerOffset(r.alerts);

    final snapshot = EventSnapshot(
      title: o.title,
      startUtc: o.startUtc,
      endUtc: o.endUtc,
      location: o.location,
      joinUrl: o.joinUrl,
      color: o.calendarColor,
    );

    for (final a in alerts) {
      final fireAt = o.startUtc.subtract(Duration(minutes: a.offsetMinutes));
      final id = PlannedAlert.idFor(o.key, a.offsetMinutes);
      final dismissed = keys.any(
        (k) => acks.isAlertDismissed(
          PlannedAlert.idFor(k, a.offsetMinutes),
          o.startUtc,
        ),
      );
      if (dismissed) continue;
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
