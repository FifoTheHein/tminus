import 'utc.dart';

/// How a copy came to belong to its meeting (spec §13). Stored by name, so
/// appending a value is safe and renaming one is a migration.
enum MeetingMatch {
  /// The copies share an iCal UID and an original start.
  uid,

  /// The copies share a normalised title, an original start and the all-day
  /// flag.
  fingerprint,

  /// Kept together by a link stored on an earlier sync, whatever their times
  /// are now.
  remembered,
}

/// A remembered link from one copy to the meeting it belongs to (spec §13):
/// one row of `meeting_links`.
///
/// Links are only stored for meetings that have, or had, two or more copies.
/// They hold no reference to the sources table, so they outlive a deleted
/// source and the copies that remain keep the meeting key through them. They
/// are pruned a day after the copy ends.
class MeetingLink {
  MeetingLink({
    required this.copyKey,
    required this.meetingKey,
    required this.sourceId,
    required this.uid,
    required this.oneOff,
    required DateTime endUtc,
    required this.matchedBy,
  }) : endUtc = plainUtc(endUtc);

  /// `EventOccurrence.key` of one copy; the primary key.
  final String copyKey;

  /// The sticky key the meeting is planned under.
  final String meetingKey;
  final String sourceId;

  /// The copy's `uid`, to find a one-off again after it moved: its key
  /// changed, its (source, uid) did not.
  final String uid;

  /// The copy has no `seriesUid`.
  final bool oneOff;

  /// The copy's end, for pruning.
  final DateTime endUtc;
  final MeetingMatch matchedBy;

  @override
  bool operator ==(Object other) =>
      other is MeetingLink &&
      other.copyKey == copyKey &&
      other.meetingKey == meetingKey &&
      other.sourceId == sourceId &&
      other.uid == uid &&
      other.oneOff == oneOff &&
      other.endUtc == endUtc &&
      other.matchedBy == matchedBy;

  @override
  int get hashCode => Object.hash(
    copyKey,
    meetingKey,
    sourceId,
    uid,
    oneOff,
    endUtc,
    matchedBy,
  );

  @override
  String toString() =>
      'MeetingLink($copyKey -> $meetingKey, ${matchedBy.name})';
}
