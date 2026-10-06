import 'component.dart';
import 'expander.dart';
import 'model.dart';
import 'vevent.dart';
import 'zones/zone_resolver.dart';

/// Parses [icsText] and returns every occurrence overlapping
/// `[windowStartUtc, windowEndUtc)`, sorted by start time.
///
/// Each VEVENT is handled on its own: one that cannot be used (no DTSTART,
/// a bad date, a broken RRULE, no END:VEVENT) becomes an [IcsIssue] and the
/// rest of the feed still parses. Cancelled events and instances are dropped.
///
/// [deviceZone] is the viewer's IANA zone; it places all-day and floating
/// events and is the last resort for unknown TZIDs.
///
/// Throws [IcsFormatException] when the text is not a VCALENDAR at all, and
/// [ArgumentError] if [deviceZone] is not an IANA name or the window is empty.
IcsResult expandIcs(
  String icsText, {
  required DateTime windowStartUtc,
  required DateTime windowEndUtc,
  required String deviceZone,
}) {
  final window = IcsWindow(windowStartUtc, windowEndUtc);
  final calendar = parseCalendar(icsText);
  final zones = ZoneResolver(
    deviceZone: deviceZone,
    vtimezones: {
      for (final c in calendar.children)
        if (c.name == 'VTIMEZONE' && c.first('TZID') != null)
          c.first('TZID')!.value.trim(): c,
    },
  );

  final issues = <IcsIssue>[];
  final events = <ParsedEvent>[];
  final overridesByUid = <String, List<ParsedEvent>>{};
  for (final c in calendar.children) {
    if (c.name != 'VEVENT') {
      continue;
    }
    try {
      if (!c.terminated) {
        throw const FormatException('VEVENT has no END:VEVENT');
      }
      final event = parseVevent(c);
      if (event.recurrenceId != null) {
        overridesByUid.putIfAbsent(event.uid, () => []).add(event);
      } else {
        events.add(event);
      }
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: uidOf(c), line: c.line, message: _describe(error)),
      );
    }
  }

  final occurrences = <IcsOccurrence>[];
  for (final event in events) {
    try {
      if (event.rrule == null) {
        occurrences.addAll(expandSingle(event, zones, window));
      } else {
        // Overrides belong to the first series with their UID.
        final overrides = overridesByUid.remove(event.uid) ?? const [];
        occurrences.addAll(expandSeries(event, overrides, zones, window));
      }
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: event.uid, line: event.line, message: _describe(error)),
      );
    }
  }
  for (final orphan in overridesByUid.values.expand((list) => list)) {
    try {
      occurrences.addAll(expandOrphanOverride(orphan, zones, window));
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: orphan.uid, line: orphan.line, message: _describe(error)),
      );
    }
  }

  occurrences.sort((a, b) {
    final byStart = a.startUtc.compareTo(b.startUtc);
    if (byStart != 0) {
      return byStart;
    }
    final byTitle = a.title.compareTo(b.title);
    return byTitle != 0 ? byTitle : a.uid.compareTo(b.uid);
  });
  issues.sort((a, b) => a.line.compareTo(b.line));
  return IcsResult(occurrences: occurrences, issues: issues);
}

String _describe(Object error) =>
    error is FormatException ? error.message : error.toString();
