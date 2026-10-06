import 'package:drift/drift.dart';

import '../model/alert_history_entry.dart';
import '../planner/acknowledgements.dart';
import 'app_database.dart';

class AlertHistoryRepository {
  AlertHistoryRepository(this._db);

  final AppDatabase _db;

  /// How long an acknowledgement matters after the occurrence's start; the
  /// same window Kotlin prunes its ack store with (roadmap §3).
  static const ackWindow = Duration(hours: 24);

  /// Inserts [entry] unless the same (type, alertId, atUtc) is already stored
  /// (an event can arrive both live and from `drainEvents`). Returns true when
  /// a row was inserted.
  Future<bool> record(AlertHistoryEntry entry) => _db.transaction(() async {
    final at = entry.atUtc.millisecondsSinceEpoch;
    final duplicate =
        await (_db.select(_db.alertHistory)..where(
              (h) =>
                  h.type.equalsValue(entry.type) &
                  h.alertId.equals(entry.alertId) &
                  h.atUtcMs.equals(at),
            ))
            .getSingleOrNull();
    if (duplicate != null) return false;
    await _db
        .into(_db.alertHistory)
        .insert(
          AlertHistoryCompanion.insert(
            type: entry.type,
            alertId: entry.alertId,
            occurrenceKey: entry.occurrenceKey,
            startUtcMs: entry.startUtc.millisecondsSinceEpoch,
            atUtcMs: at,
            snoozeUntilUtcMs: Value(
              entry.snoozeUntilUtc?.millisecondsSinceEpoch,
            ),
            title: Value(entry.title),
          ),
        );
    return true;
  });

  /// Newest first.
  Future<List<AlertHistoryEntry>> recent({int limit = 100}) =>
      _recent(limit).map(_fromRow).get();

  Stream<List<AlertHistoryEntry>> watchRecent({int limit = 100}) =>
      _recent(limit).map(_fromRow).watch();

  /// Entries that happened at or after [sinceUtc], oldest first.
  Future<List<AlertHistoryEntry>> since(DateTime sinceUtc) =>
      (_db.select(_db.alertHistory)
            ..where(
              (h) => h.atUtcMs.isBiggerOrEqualValue(
                sinceUtc.millisecondsSinceEpoch,
              ),
            )
            ..orderBy([(h) => OrderingTerm.asc(h.atUtcMs)]))
          .map(_fromRow)
          .get();

  /// What the planner must drop (roadmap §3 "Engine rules"):
  /// `dismissedAll` / `joined` → (occurrenceKey, startUtc);
  /// `dismissed` → (alertId, startUtc). Snooze ids (`…:s`) are skipped; the
  /// planner never produces them. Only occurrences that started within
  /// [ackWindow] of [nowUtc], or start later, are returned.
  Future<Acknowledgements> acknowledgements({required DateTime nowUtc}) async {
    final cutoff = nowUtc.subtract(ackWindow).millisecondsSinceEpoch;
    final rows =
        await (_db.select(_db.alertHistory)..where(
              (h) =>
                  h.startUtcMs.isBiggerOrEqualValue(cutoff) &
                  h.type.isInValues([
                    AlertEventType.dismissed,
                    AlertEventType.dismissedAll,
                    AlertEventType.joined,
                  ]),
            ))
            .get();
    DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return Acknowledgements(
      occurrences: [
        for (final r in rows)
          if (r.type != AlertEventType.dismissed)
            (r.occurrenceKey, t(r.startUtcMs)),
      ],
      alerts: [
        for (final r in rows)
          if (r.type == AlertEventType.dismissed && !r.alertId.endsWith(':s'))
            (r.alertId, t(r.startUtcMs)),
      ],
    );
  }

  /// Deletes entries that happened before [cutoffUtc]. Returns the count.
  Future<int> deleteBefore(DateTime cutoffUtc) =>
      (_db.delete(_db.alertHistory)..where(
            (h) =>
                h.atUtcMs.isSmallerThanValue(cutoffUtc.millisecondsSinceEpoch),
          ))
          .go();

  SimpleSelectStatement<$AlertHistoryTable, AlertHistoryRow> _recent(
    int limit,
  ) => _db.select(_db.alertHistory)
    ..orderBy([
      (h) => OrderingTerm.desc(h.atUtcMs),
      (h) => OrderingTerm.desc(h.id),
    ])
    ..limit(limit);

  static AlertHistoryEntry _fromRow(AlertHistoryRow r) {
    DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return AlertHistoryEntry(
      type: r.type,
      alertId: r.alertId,
      occurrenceKey: r.occurrenceKey,
      startUtc: t(r.startUtcMs),
      atUtc: t(r.atUtcMs),
      snoozeUntilUtc: r.snoozeUntilUtcMs == null
          ? null
          : t(r.snoozeUntilUtcMs!),
      title: r.title,
    );
  }
}
