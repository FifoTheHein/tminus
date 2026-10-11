import 'utc.dart';

/// Free/busy state of an occurrence, as reported by its source.
enum BusyStatus { free, tentative, busy, oof, unknown }

/// Why an occurrence's data is less certain than usual.
enum OccurrenceWarning {
  /// The time zone could not be mapped exactly; a fallback zone was used.
  tzFallback,
}

/// One concrete instance of a calendar event, as cached from a source.
///
/// All instants are UTC. [key] stays the same when a meeting is moved,
/// because it is built from [originalStartUtc], not [startUtc].
class EventOccurrence {
  EventOccurrence({
    required this.sourceId,
    required this.uid,
    required DateTime originalStartUtc,
    this.seriesUid,
    this.icalUid,
    required this.title,
    this.location,
    this.organizer,
    this.description,
    this.joinUrl,
    required DateTime startUtc,
    required DateTime endUtc,
    this.allDay = false,
    this.busyStatus = BusyStatus.unknown,
    this.declined = false,
    this.cancelled = false,
    required this.calendarColor,
    this.warnings = const {},
  }) : originalStartUtc = plainUtc(originalStartUtc),
       startUtc = plainUtc(startUtc),
       endUtc = plainUtc(endUtc);

  final String sourceId;
  final String uid;
  final DateTime originalStartUtc;

  /// Null for one-off events.
  final String? seriesUid;

  /// The event's iCalendar UID, when the source exposes it. An ICS feed copy
  /// always has it (it is [uid]); a phone copy has it only if the calendar
  /// provider fills a column the app reads. With [originalStartUtc] it is the
  /// strong key for recognising the same meeting in two sources (spec §13).
  final String? icalUid;
  final String title;
  final String? location;
  final String? organizer;
  final String? description;
  final String? joinUrl;
  final DateTime startUtc;
  final DateTime endUtc;
  final bool allDay;
  final BusyStatus busyStatus;

  /// Device source only; ICS feeds do not carry your response.
  final bool declined;

  /// Device source only; `ics_core` already drops ICS cancellations.
  final bool cancelled;

  /// ARGB, e.g. 0xFF6AA0F5.
  final int calendarColor;
  final Set<OccurrenceWarning> warnings;

  String get key => makeKey(sourceId, uid, originalStartUtc);

  /// `'$sourceId|$uid|<originalStartUtc as UTC ISO-8601>'` (roadmap §4),
  /// in whole milliseconds like every stored instant (decision 25).
  static String makeKey(String sourceId, String uid, DateTime originalStart) =>
      '$sourceId|$uid|${plainUtc(originalStart).toIso8601String()}';

  /// Keys to look overrides and acknowledgements up under, best first.
  ///
  /// A plain copy has only its own [key]. A `MeetingOccurrence` adds the keys
  /// of its copies, so what was recorded under any of them still applies.
  List<String> get lookupKeys => [key];

  /// Series uids to look series overrides up under, best first. Empty for a
  /// one-off event.
  List<String> get lookupSeriesUids => [?seriesUid];

  /// Sources in rank order, for the source default (§6 step 5).
  List<String> get sourceIds => [sourceId];

  EventOccurrence copyWith({
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
  }) => EventOccurrence(
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
  );

  /// A `MeetingOccurrence` is never equal to a plain copy, even with the same
  /// fields, so `==` stays symmetric.
  @override
  bool operator ==(Object other) =>
      other is EventOccurrence &&
      other.runtimeType == runtimeType &&
      other.sourceId == sourceId &&
      other.uid == uid &&
      other.originalStartUtc == originalStartUtc &&
      other.seriesUid == seriesUid &&
      other.icalUid == icalUid &&
      other.title == title &&
      other.location == location &&
      other.organizer == organizer &&
      other.description == description &&
      other.joinUrl == joinUrl &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc &&
      other.allDay == allDay &&
      other.busyStatus == busyStatus &&
      other.declined == declined &&
      other.cancelled == cancelled &&
      other.calendarColor == calendarColor &&
      other.warnings.length == warnings.length &&
      other.warnings.containsAll(warnings);

  @override
  int get hashCode => Object.hash(key, startUtc, endUtc, title);

  @override
  String toString() => 'EventOccurrence($key, "$title", $startUtc)';
}
