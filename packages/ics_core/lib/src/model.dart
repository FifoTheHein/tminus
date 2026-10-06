/// Busy state an event shows in Outlook.
enum IcsBusyStatus { free, tentative, busy, oof, unknown }

/// Why an event's times are less certain than usual.
enum IcsWarning {
  /// TZID not in the Windows→IANA table and not an IANA name; used the feed's VTIMEZONE.
  tzFromVtimezone,

  /// No usable zone at all; used the device zone.
  tzFromDevice,
}

/// One occurrence of an event inside the requested window.
class IcsOccurrence {
  const IcsOccurrence({
    required this.uid,
    required this.originalStartUtc,
    required this.recurring,
    required this.title,
    this.location,
    this.organizer,
    this.description,
    this.joinUrl,
    required this.startUtc,
    required this.endUtc,
    required this.allDay,
    required this.busyStatus,
    this.warnings = const {},
  });

  final String uid;

  /// The instance's RECURRENCE-ID / original DTSTART, UTC.
  final DateTime originalStartUtc;

  /// True for any instance of an RRULE series (incl. overrides).
  final bool recurring;

  /// SUMMARY, unescaped.
  final String title;
  final String? location;

  /// CN if present, else mailto address.
  final String? organizer;
  final String? description;

  /// First Teams join link (https://teams.microsoft.com/l/meetup-join/... or
  /// https://teams.microsoft.com/meet/...) in DESCRIPTION, then LOCATION.
  final String? joinUrl;
  final DateTime startUtc;
  final DateTime endUtc;

  /// DATE values; start/end = local midnight in deviceZone, as UTC.
  final bool allDay;

  /// X-MICROSOFT-CDO-BUSYSTATUS, else TRANSP (TRANSPARENT→free), else unknown.
  final IcsBusyStatus busyStatus;
  final Set<IcsWarning> warnings;

  @override
  bool operator ==(Object other) =>
      other is IcsOccurrence &&
      other.uid == uid &&
      other.originalStartUtc == originalStartUtc &&
      other.recurring == recurring &&
      other.title == title &&
      other.location == location &&
      other.organizer == organizer &&
      other.description == description &&
      other.joinUrl == joinUrl &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc &&
      other.allDay == allDay &&
      other.busyStatus == busyStatus &&
      other.warnings.length == warnings.length &&
      other.warnings.containsAll(warnings);

  @override
  int get hashCode => Object.hash(
    uid,
    originalStartUtc,
    recurring,
    title,
    location,
    organizer,
    description,
    joinUrl,
    startUtc,
    endUtc,
    allDay,
    busyStatus,
    Object.hashAllUnordered(warnings),
  );

  @override
  String toString() =>
      'IcsOccurrence($uid, "$title", ${startUtc.toIso8601String()} to '
      '${endUtc.toIso8601String()}, original ${originalStartUtc.toIso8601String()}, '
      'recurring: $recurring, allDay: $allDay, busy: ${busyStatus.name}, '
      'warnings: ${warnings.map((w) => w.name).toList()})';
}

/// One skipped/odd VEVENT; the rest of the feed still parses.
class IcsIssue {
  const IcsIssue({this.uid, required this.line, required this.message});

  final String? uid;

  /// 1-based line in the unfolded text where the VEVENT began.
  final int line;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is IcsIssue &&
      other.uid == uid &&
      other.line == line &&
      other.message == message;

  @override
  int get hashCode => Object.hash(uid, line, message);

  @override
  String toString() => 'IcsIssue(line $line, uid: $uid, $message)';
}

/// What `expandIcs` returns.
class IcsResult {
  const IcsResult({required this.occurrences, required this.issues});

  /// Sorted by startUtc, cancelled ones already dropped.
  final List<IcsOccurrence> occurrences;
  final List<IcsIssue> issues;
}

/// The text is not a VCALENDAR at all (whole feed unusable).
class IcsFormatException implements Exception {
  const IcsFormatException(this.message);

  final String message;

  @override
  String toString() => 'IcsFormatException: $message';
}
