import 'event_occurrence.dart';

/// A meeting found in one or more calendar sources, merged into one
/// occurrence (spec §13).
///
/// The inherited fields hold the merged values: [sourceId], [uid],
/// [originalStartUtc], [seriesUid], the times and the colour come from the
/// time source (the top-ranked copy), and the other fields are filled in from
/// the next copies as the spec's "Which copy wins" table says.
///
/// [key] is the sticky [meetingKey], so plan ids, `occurrenceKey` and the
/// history all use it. The rules engine and the planner also look overrides,
/// acknowledgements and source defaults up under every copy, through
/// [lookupKeys], [lookupSeriesUids] and [sourceIds].
class MeetingOccurrence extends EventOccurrence {
  MeetingOccurrence({
    required super.sourceId,
    required super.uid,
    required super.originalStartUtc,
    super.seriesUid,
    super.icalUid,
    required super.title,
    super.location,
    super.organizer,
    super.description,
    super.joinUrl,
    required super.startUtc,
    required super.endUtc,
    super.allDay,
    super.busyStatus,
    super.declined,
    super.cancelled,
    required super.calendarColor,
    super.warnings,
    required this.meetingKey,
    required List<EventOccurrence> copies,
    required this.timeSourceId,
  }) : assert(copies.isNotEmpty, 'a meeting has at least one copy'),
       copies = List.unmodifiable(copies);

  /// The sticky key the meeting is planned under. It stays the same when the
  /// ranking changes and when a source leaves.
  final String meetingKey;

  /// The meeting's copies in rank order. The first is the time source.
  final List<EventOccurrence> copies;

  /// The source of the copy that decides the time. It is [sourceId] too.
  final String timeSourceId;

  @override
  String get key => meetingKey;

  /// The meeting key, then each copy's own key, without duplicates (the
  /// meeting often takes its top-ranked copy's key).
  @override
  List<String> get lookupKeys =>
      <String>{meetingKey, for (final c in copies) c.key}.toList();

  /// The copies' series uids in rank order, without gaps or duplicates.
  @override
  List<String> get lookupSeriesUids =>
      <String>{for (final c in copies) ?c.seriesUid}.toList();

  /// The copies' sources in rank order, without duplicates.
  @override
  List<String> get sourceIds =>
      <String>{for (final c in copies) c.sourceId}.toList();

  /// Returns a [MeetingOccurrence] with the same [meetingKey], [copies] and
  /// [timeSourceId], never a plain copy. Like the base, it cannot clear a
  /// nullable field.
  @override
  MeetingOccurrence copyWith({
    DateTime? startUtc,
    DateTime? endUtc,
    String? icalUid,
    String? title,
    String? location,
    String? organizer,
    String? description,
    String? joinUrl,
    bool? allDay,
    BusyStatus? busyStatus,
    bool? declined,
    bool? cancelled,
    int? calendarColor,
    Set<OccurrenceWarning>? warnings,
  }) => MeetingOccurrence(
    sourceId: sourceId,
    uid: uid,
    originalStartUtc: originalStartUtc,
    seriesUid: seriesUid,
    icalUid: icalUid ?? this.icalUid,
    title: title ?? this.title,
    location: location ?? this.location,
    organizer: organizer ?? this.organizer,
    description: description ?? this.description,
    joinUrl: joinUrl ?? this.joinUrl,
    startUtc: startUtc ?? this.startUtc,
    endUtc: endUtc ?? this.endUtc,
    allDay: allDay ?? this.allDay,
    busyStatus: busyStatus ?? this.busyStatus,
    declined: declined ?? this.declined,
    cancelled: cancelled ?? this.cancelled,
    calendarColor: calendarColor ?? this.calendarColor,
    warnings: warnings ?? this.warnings,
    meetingKey: meetingKey,
    copies: copies,
    timeSourceId: timeSourceId,
  );

  @override
  bool operator ==(Object other) =>
      other is MeetingOccurrence &&
      super == other &&
      other.meetingKey == meetingKey &&
      other.timeSourceId == timeSourceId &&
      _sameCopies(other.copies);

  bool _sameCopies(List<EventOccurrence> others) {
    if (others.length != copies.length) return false;
    for (var i = 0; i < copies.length; i++) {
      if (others[i] != copies[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    key,
    startUtc,
    endUtc,
    title,
    timeSourceId,
    Object.hashAll(copies),
  );

  @override
  String toString() =>
      'MeetingOccurrence($key, "$title", $startUtc, copies: ${copies.length})';
}
