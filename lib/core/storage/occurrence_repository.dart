import 'package:drift/drift.dart';

import '../model/event_occurrence.dart';
import 'app_database.dart';

/// The occurrence cache (spec §5).
class OccurrenceRepository {
  OccurrenceRepository(this._db);

  final AppDatabase _db;

  /// Replaces every cached occurrence of [sourceId] in one transaction, so a
  /// reader never sees a half-written source. Throws [ArgumentError] if an
  /// occurrence belongs to another source.
  Future<void> replaceForSource(
    String sourceId,
    List<EventOccurrence> occurrences,
  ) {
    for (final o in occurrences) {
      if (o.sourceId != sourceId) {
        throw ArgumentError.value(
          o.key,
          'occurrences',
          'belongs to ${o.sourceId}, not $sourceId',
        );
      }
    }
    return _db.transaction(() async {
      await (_db.delete(
        _db.occurrences,
      )..where((r) => r.sourceId.equals(sourceId))).go();
      await _db.batch((b) {
        b.insertAll(
          _db.occurrences,
          occurrences.map(_toCompanion),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  Future<int> countForSource(String sourceId) {
    final count = _db.occurrences.occurrenceKey.count();
    return (_db.selectOnly(_db.occurrences)
          ..addColumns([count])
          ..where(_db.occurrences.sourceId.equals(sourceId)))
        .map((r) => r.read(count)!)
        .getSingle();
  }

  /// Occurrences overlapping [fromUtc, toUtc): they end after [fromUtc] and
  /// start before [toUtc]. Sorted by start, then key.
  Future<List<EventOccurrence>> between(DateTime fromUtc, DateTime toUtc) =>
      _between(fromUtc, toUtc).map(_fromRow).get();

  Stream<List<EventOccurrence>> watchBetween(
    DateTime fromUtc,
    DateTime toUtc,
  ) => _between(fromUtc, toUtc).map(_fromRow).watch();

  Future<EventOccurrence?> byKey(String occurrenceKey) =>
      (_db.select(_db.occurrences)
            ..where((r) => r.occurrenceKey.equals(occurrenceKey)))
          .map(_fromRow)
          .getSingleOrNull();

  /// Removes occurrences that ended before [cutoffUtc]. Returns the count.
  Future<int> deleteEndedBefore(DateTime cutoffUtc) =>
      (_db.delete(_db.occurrences)..where(
            (r) =>
                r.endUtcMs.isSmallerThanValue(cutoffUtc.millisecondsSinceEpoch),
          ))
          .go();

  SimpleSelectStatement<$OccurrencesTable, OccurrenceRow> _between(
    DateTime fromUtc,
    DateTime toUtc,
  ) => _db.select(_db.occurrences)
    ..where(
      (r) =>
          r.endUtcMs.isBiggerThanValue(fromUtc.millisecondsSinceEpoch) &
          r.startUtcMs.isSmallerThanValue(toUtc.millisecondsSinceEpoch),
    )
    ..orderBy([
      (r) => OrderingTerm.asc(r.startUtcMs),
      (r) => OrderingTerm.asc(r.occurrenceKey),
    ]);

  static OccurrencesCompanion _toCompanion(EventOccurrence o) =>
      OccurrencesCompanion.insert(
        occurrenceKey: o.key,
        sourceId: o.sourceId,
        uid: o.uid,
        originalStartUtcMs: o.originalStartUtc.millisecondsSinceEpoch,
        seriesUid: Value(o.seriesUid),
        title: o.title,
        location: Value(o.location),
        organizer: Value(o.organizer),
        description: Value(o.description),
        joinUrl: Value(o.joinUrl),
        startUtcMs: o.startUtc.millisecondsSinceEpoch,
        endUtcMs: o.endUtc.millisecondsSinceEpoch,
        allDay: o.allDay,
        busyStatus: o.busyStatus,
        declined: o.declined,
        cancelled: o.cancelled,
        calendarColor: o.calendarColor,
        warnings: Value(o.warnings.map((w) => w.name).join(',')),
        icalUid: Value(o.icalUid),
      );

  static EventOccurrence _fromRow(OccurrenceRow r) {
    DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return EventOccurrence(
      sourceId: r.sourceId,
      uid: r.uid,
      originalStartUtc: t(r.originalStartUtcMs),
      seriesUid: r.seriesUid,
      icalUid: r.icalUid,
      title: r.title,
      location: r.location,
      organizer: r.organizer,
      description: r.description,
      joinUrl: r.joinUrl,
      startUtc: t(r.startUtcMs),
      endUtc: t(r.endUtcMs),
      allDay: r.allDay,
      busyStatus: r.busyStatus,
      declined: r.declined,
      cancelled: r.cancelled,
      calendarColor: r.calendarColor,
      warnings: {
        for (final name in r.warnings.split(','))
          if (name.isNotEmpty)
            ...OccurrenceWarning.values.where((w) => w.name == name),
      },
    );
  }
}
