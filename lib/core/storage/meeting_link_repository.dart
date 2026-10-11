import 'package:drift/drift.dart';

import '../model/meeting_link.dart';
import 'app_database.dart';

/// The remembered links from copies to their meetings (spec §13).
class MeetingLinkRepository {
  MeetingLinkRepository(this._db);

  final AppDatabase _db;

  /// Every stored link, sorted by copy key.
  Future<List<MeetingLink>> all() => (_db.select(
    _db.meetingLinks,
  )..orderBy([(l) => OrderingTerm.asc(l.copyKey)])).map(_fromRow).get();

  /// Deletes the links of the copy keys in [delete], then upserts [upsert]
  /// (replacing a link with the same copy key), in one transaction: if any
  /// statement fails, none of the changes is kept. A copy key in both ends up
  /// with the upserted link.
  Future<void> apply({
    required List<MeetingLink> upsert,
    required Set<String> delete,
  }) {
    if (upsert.isEmpty && delete.isEmpty) return Future.value();
    return _db.transaction(() async {
      await _db.batch((b) {
        for (final copyKey in delete) {
          b.deleteWhere(_db.meetingLinks, (l) => l.copyKey.equals(copyKey));
        }
        b.insertAll(
          _db.meetingLinks,
          upsert.map(_toCompanion),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  /// Removes links whose copy ended before [cutoffUtc]. Returns the count.
  Future<int> deleteEndedBefore(DateTime cutoffUtc) =>
      (_db.delete(_db.meetingLinks)..where(
            (l) =>
                l.endUtcMs.isSmallerThanValue(cutoffUtc.millisecondsSinceEpoch),
          ))
          .go();

  static MeetingLinksCompanion _toCompanion(MeetingLink l) =>
      MeetingLinksCompanion.insert(
        copyKey: l.copyKey,
        meetingKey: l.meetingKey,
        sourceId: l.sourceId,
        uid: l.uid,
        oneOff: l.oneOff,
        endUtcMs: l.endUtc.millisecondsSinceEpoch,
        matchedBy: l.matchedBy,
      );

  static MeetingLink _fromRow(MeetingLinkRow r) => MeetingLink(
    copyKey: r.copyKey,
    meetingKey: r.meetingKey,
    sourceId: r.sourceId,
    uid: r.uid,
    oneOff: r.oneOff,
    endUtc: DateTime.fromMillisecondsSinceEpoch(r.endUtcMs, isUtc: true),
    matchedBy: r.matchedBy,
  );
}
