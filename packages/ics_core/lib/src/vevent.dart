import 'component.dart';
import 'event_fields.dart';
import 'model.dart';
import 'values.dart';

/// One VEVENT, with its values parsed but no zones applied yet.
class ParsedEvent {
  const ParsedEvent({
    required this.line,
    required this.uid,
    required this.start,
    this.end,
    this.duration,
    this.recurrenceId,
    this.rrule,
    this.exdates = const [],
    required this.cancelled,
    required this.title,
    this.location,
    this.description,
    this.organizer,
    this.joinUrl,
    required this.busyStatus,
  });

  /// Line where `BEGIN:VEVENT` appeared.
  final int line;
  final String uid;
  final IcsTime start;
  final IcsTime? end;
  final Duration? duration;
  final IcsTime? recurrenceId;

  /// The raw RRULE value, if any.
  final String? rrule;
  final List<IcsTime> exdates;

  /// STATUS:CANCELLED or a `Canceled:` / `Cancelled:` title.
  final bool cancelled;
  final String title;
  final String? location;
  final String? description;
  final String? organizer;
  final String? joinUrl;
  final IcsBusyStatus busyStatus;

  bool get allDay => start.isDate;
}

/// The UID of [event], or null if it has none.
String? uidOf(Component event) {
  final uid = event.first('UID')?.value.trim();
  return uid == null || uid.isEmpty ? null : uid;
}

/// Parses one VEVENT. Throws [FormatException] if it cannot be used.
///
/// A missing UID gets a stable stand-in built from DTSTART and SUMMARY.
ParsedEvent parseVevent(Component event) {
  final dtstart = event.first('DTSTART');
  if (dtstart == null) {
    throw const FormatException('VEVENT has no DTSTART');
  }
  final start = parseIcsTimes(dtstart).firstOrNull;
  if (start == null) {
    throw const FormatException('DTSTART is empty');
  }
  final dtend = event.first('DTEND');
  final durationLine = event.first('DURATION');
  final recurrenceLine = event.first('RECURRENCE-ID');
  final title = textOf(event.first('SUMMARY')) ?? '';
  final location = textOf(event.first('LOCATION'));
  final description = textOf(event.first('DESCRIPTION'));
  final status = event.first('STATUS')?.value.trim().toUpperCase();
  return ParsedEvent(
    line: event.line,
    uid: uidOf(event) ?? 'no-uid:${dtstart.value.trim()}|$title',
    start: start,
    end: dtend == null ? null : parseIcsTimes(dtend).firstOrNull,
    duration: durationLine == null
        ? null
        : parseIcsDuration(durationLine.value),
    recurrenceId: recurrenceLine == null
        ? null
        : parseIcsTimes(recurrenceLine).firstOrNull,
    rrule: event.first('RRULE')?.value,
    exdates: [for (final ex in event.all('EXDATE')) ...parseIcsTimes(ex)],
    cancelled: status == 'CANCELLED' || isCancelledTitle(title),
    title: title,
    location: location,
    description: description,
    organizer: organizerOf(event.first('ORGANIZER')),
    joinUrl: extractTeamsJoinUrl(description, location),
    busyStatus: busyStatusOf(event),
  );
}
