import 'package:drift/drift.dart';

import '../model/sync_log_entry.dart';
import 'app_database.dart';

class SyncLogRepository {
  SyncLogRepository(this._db);

  final AppDatabase _db;

  Future<void> add(SyncLogEntry e) => _db
      .into(_db.syncLog)
      .insert(
        SyncLogCompanion.insert(
          sourceId: Value(e.sourceId),
          atUtcMs: e.atUtc.millisecondsSinceEpoch,
          outcome: e.outcome,
          message: Value(e.message),
          occurrenceCount: Value(e.occurrenceCount),
          durationMs: Value(e.duration?.inMilliseconds),
        ),
      );

  /// Newest first.
  Future<List<SyncLogEntry>> recent({int limit = 50}) =>
      (_db.select(_db.syncLog)
            ..orderBy([
              (l) => OrderingTerm.desc(l.atUtcMs),
              (l) => OrderingTerm.desc(l.id),
            ])
            ..limit(limit))
          .map(_fromRow)
          .get();

  Future<SyncLogEntry?> latestForSource(String sourceId) =>
      (_db.select(_db.syncLog)
            ..where((l) => l.sourceId.equals(sourceId))
            ..orderBy([
              (l) => OrderingTerm.desc(l.atUtcMs),
              (l) => OrderingTerm.desc(l.id),
            ])
            ..limit(1))
          .map(_fromRow)
          .getSingleOrNull();

  /// The oldest entry still stored for [sourceId] (Plan 4: when a source
  /// that never synced started failing).
  Future<SyncLogEntry?> earliestForSource(String sourceId) =>
      (_db.select(_db.syncLog)
            ..where((l) => l.sourceId.equals(sourceId))
            ..orderBy([
              (l) => OrderingTerm.asc(l.atUtcMs),
              (l) => OrderingTerm.asc(l.id),
            ])
            ..limit(1))
          .map(_fromRow)
          .getSingleOrNull();

  /// Deletes entries logged before [cutoffUtc]. Returns the count.
  Future<int> deleteBefore(DateTime cutoffUtc) =>
      (_db.delete(_db.syncLog)..where(
            (l) =>
                l.atUtcMs.isSmallerThanValue(cutoffUtc.millisecondsSinceEpoch),
          ))
          .go();

  static SyncLogEntry _fromRow(SyncLogRow r) => SyncLogEntry(
    sourceId: r.sourceId,
    atUtc: DateTime.fromMillisecondsSinceEpoch(r.atUtcMs, isUtc: true),
    outcome: r.outcome,
    message: r.message,
    occurrenceCount: r.occurrenceCount,
    duration: r.durationMs == null
        ? null
        : Duration(milliseconds: r.durationMs!),
  );
}
