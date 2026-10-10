import '../model/planned_alert.dart';

/// Spec §7: a sync runs this long before each occurrence's earliest alert.
const preSyncLead = Duration(minutes: 12);

/// One time per occurrence: its earliest alert − [preSyncLead], counting
/// alerts that have already passed (the plan still lists them), so an
/// occurrence gets one pre-alarm sync, not one per alert. Only future times,
/// sorted, without duplicates.
List<DateTime> preSyncTimes(Iterable<PlannedAlert> plan, DateTime now) {
  final earliest = <String, DateTime>{};
  for (final a in plan) {
    final current = earliest[a.occurrenceKey];
    if (current == null || a.fireAtUtc.isBefore(current)) {
      earliest[a.occurrenceKey] = a.fireAtUtc;
    }
  }
  final times = {
    for (final t in earliest.values)
      if (t.subtract(preSyncLead).isAfter(now)) t.subtract(preSyncLead),
  }.toList()..sort();
  return times;
}
