import 'dart:convert';

import '../model/alert_history_entry.dart';
import '../model/planned_alert.dart';
import '../model/utc.dart';

/// An alert a plan armed in the future, so a `fired` record is owed for it.
class ExpectedAlert {
  ExpectedAlert({
    required this.id,
    required this.occurrenceKey,
    required DateTime fireAtUtc,
    required DateTime startUtc,
    required this.title,
  }) : fireAtUtc = plainUtc(fireAtUtc),
       startUtc = plainUtc(startUtc);

  factory ExpectedAlert.of(PlannedAlert a) => ExpectedAlert(
    id: a.id,
    occurrenceKey: a.occurrenceKey,
    fireAtUtc: a.fireAtUtc,
    startUtc: a.event.startUtc,
    title: a.event.title,
  );

  factory ExpectedAlert.fromJson(Map<String, Object?> j) => ExpectedAlert(
    id: j['id'] as String,
    occurrenceKey: j['occurrenceKey'] as String,
    fireAtUtc: DateTime.fromMillisecondsSinceEpoch(
      j['fireAtUtcMs'] as int,
      isUtc: true,
    ),
    startUtc: DateTime.fromMillisecondsSinceEpoch(
      j['startUtcMs'] as int,
      isUtc: true,
    ),
    title: j['title'] as String,
  );

  final String id;
  final String occurrenceKey;
  final DateTime fireAtUtc;
  final DateTime startUtc;
  final String title;

  Map<String, Object?> toJson() => {
    'id': id,
    'occurrenceKey': occurrenceKey,
    'fireAtUtcMs': fireAtUtc.millisecondsSinceEpoch,
    'startUtcMs': startUtc.millisecondsSinceEpoch,
    'title': title,
  };

  /// Identity for carrying an alert over between syncs: a moved alert is a
  /// new expectation.
  String get _slot => '$id|${fireAtUtc.millisecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      other is ExpectedAlert &&
      other.id == id &&
      other.occurrenceKey == occurrenceKey &&
      other.fireAtUtc == fireAtUtc &&
      other.startUtc == startUtc &&
      other.title == title;

  @override
  int get hashCode =>
      Object.hash(id, occurrenceKey, fireAtUtc, startUtc, title);

  @override
  String toString() => 'ExpectedAlert($id, $fireAtUtc)';
}

class MissedCheck {
  const MissedCheck({required this.missed, required this.pending});

  /// `missedSystem` rows to record. `atUtc` is the alert's fire time, so the
  /// same miss found twice is one row (history de-duplicates).
  final List<AlertHistoryEntry> missed;

  /// Expected alerts whose grace period has not passed yet.
  final List<ExpectedAlert> pending;
}

/// Spec §9 "Alert time passed by > 2 min without a `fired` record → logged as
/// missed (system)", as Plan 4 defines it: only alerts that were still in the
/// future when a plan armed them count; an alert that rang more than 2 min
/// late counts too; an occurrence dismissed-all or joined before the alert's
/// time does not; and an alert that never rang but that the engine already
/// logged as `missed` does not, because that row is already the record of the
/// miss.
abstract final class MissedSystemDetector {
  static const grace = Duration(minutes: 2);

  /// Checks every expected alert whose fire time is more than [grace] ago.
  /// [history] must cover the expected alerts' occurrences (Plan 4 passes
  /// everything since a day before the oldest fire time).
  ///
  /// An alert for which [history] holds an engine `missed` row and no `fired`
  /// record at all (the phone was off for the whole event) is neither reported
  /// nor kept pending. If it also has a `fired` record, the `missed` row only
  /// means the ring timed out unanswered, and the usual rules apply: a ring
  /// more than 2 min late is still missed (system).
  static MissedCheck check({
    required List<ExpectedAlert> expected,
    required List<AlertHistoryEntry> history,
    required DateTime now,
  }) {
    final missed = <AlertHistoryEntry>[];
    final pending = <ExpectedAlert>[];
    for (final e in expected) {
      // The engine logs `missed` itself when it finds an overdue alert whose
      // event has ended (the phone was off for the whole meeting, so the
      // alert never rang). That row already records the miss, and a second
      // one from here would count it twice. It excuses the alert only if no
      // `fired` record exists for it: the engine also logs `missed` when an
      // alert that did ring timed out unanswered, and one that rang more
      // than 2 min late is still missed (system). Both rows are matched like
      // a `fired` record, by alert and occurrence start, but with no time
      // limit: the engine writes `missed` whenever the phone comes back,
      // which is long after the grace period.
      final everFired = history.any(
        (h) =>
            h.type == AlertEventType.fired &&
            h.alertId == e.id &&
            h.startUtc == e.startUtc,
      );
      final engineMissed =
          !everFired &&
          history.any(
            (h) =>
                h.type == AlertEventType.missed &&
                h.alertId == e.id &&
                h.startUtc == e.startUtc,
          );
      if (engineMissed) continue;
      final deadline = e.fireAtUtc.add(grace);
      if (!now.isAfter(deadline)) {
        pending.add(e);
        continue;
      }
      final firedInTime = history.any(
        (h) =>
            h.type == AlertEventType.fired &&
            h.alertId == e.id &&
            h.startUtc == e.startUtc &&
            !h.atUtc.isAfter(deadline),
      );
      final ackedBefore = history.any(
        (h) =>
            (h.type == AlertEventType.dismissedAll ||
                h.type == AlertEventType.joined) &&
            h.occurrenceKey == e.occurrenceKey &&
            h.startUtc == e.startUtc &&
            !h.atUtc.isAfter(e.fireAtUtc),
      );
      if (firedInTime || ackedBefore) continue;
      missed.add(
        AlertHistoryEntry(
          type: AlertEventType.missedSystem,
          alertId: e.id,
          occurrenceKey: e.occurrenceKey,
          startUtc: e.startUtc,
          atUtc: e.fireAtUtc,
          title: e.title,
        ),
      );
    }
    return MissedCheck(missed: missed, pending: pending);
  }

  /// What to expect after [plan] is applied at [now]: every future alert in
  /// it, plus [pending] alerts the plan still lists at the same time. Past
  /// alerts that were never expected (a meeting added after its first alert)
  /// are not armed by Kotlin, so nothing is owed for them.
  static List<ExpectedAlert> expectedAfterApply({
    required List<ExpectedAlert> pending,
    required List<PlannedAlert> plan,
    required DateTime now,
  }) {
    final carried = {for (final p in pending) p._slot};
    final result = <String, ExpectedAlert>{};
    for (final a in plan) {
      final e = ExpectedAlert.of(a);
      if (a.fireAtUtc.isAfter(now) || carried.contains(e._slot)) {
        result[e._slot] = e;
      }
    }
    return result.values.toList();
  }

  static String encode(List<ExpectedAlert> expected) =>
      jsonEncode([for (final e in expected) e.toJson()]);

  /// Unreadable text reads as nothing expected, never as an error.
  static List<ExpectedAlert> decode(String? json) {
    if (json == null) return const [];
    try {
      return [
        for (final e in jsonDecode(json) as List<Object?>)
          ExpectedAlert.fromJson((e! as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }
}
