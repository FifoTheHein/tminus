// Makes a published Outlook ICS feed safe to commit as a test fixture.
//
// Usage (from packages/ics_core):
//   dart run tool/scrub_feed.dart <raw.ics> <scrubbed.ics>
//
// Keeps the structure the parser cares about (VTIMEZONEs, TZIDs, DTSTART/
// DTEND, RRULE, EXDATE, RECURRENCE-ID, STATUS, TRANSP, busy status) and
// replaces every piece of personal text. Properties not on the allowlist are
// dropped. A Teams join link is replaced by a synthetic link of the same
// shape so join-link extraction can still be tested.
import 'dart:io';

import 'package:ics_core/src/content_line.dart';
import 'package:ics_core/src/event_fields.dart';

/// Properties copied unchanged.
const keptProperties = {
  'BEGIN', 'END', 'VERSION', 'PRODID', 'METHOD', 'CALSCALE', //
  'TZID', 'TZOFFSETFROM', 'TZOFFSETTO', 'TZNAME', 'RDATE',
  'DTSTART', 'DTEND', 'DURATION', 'RRULE', 'EXDATE', 'RECURRENCE-ID',
  'STATUS', 'TRANSP', 'SEQUENCE', 'CLASS', 'PRIORITY', 'DTSTAMP',
  'CREATED', 'LAST-MODIFIED', 'ACTION', 'TRIGGER',
  'X-MICROSOFT-CDO-BUSYSTATUS', 'X-MICROSOFT-CDO-INTENDEDSTATUS',
  'X-MICROSOFT-CDO-ALLDAYEVENT', 'X-MICROSOFT-CDO-IMPORTANCE',
  'X-MICROSOFT-DISALLOW-COUNTER',
};

/// Result of [scrubFeed].
class ScrubResult {
  ScrubResult(
    this.text,
    this.events,
    this.eventsWithTeamsLink,
    this.eventsWithMeetLink,
    this.dropped,
  );

  /// The scrubbed feed, CRLF line endings, folded at 75 characters.
  final String text;

  /// Number of VEVENTs in the raw feed.
  final int events;

  /// VEVENTs whose raw DESCRIPTION or LOCATION held a Teams join link.
  final int eventsWithTeamsLink;

  /// VEVENTs with a newer-style `https://teams.microsoft.com/meet/…` link
  /// (also counted in [eventsWithTeamsLink]); reported to show the mix.
  final int eventsWithMeetLink;

  /// Names of properties that were dropped, with counts.
  final Map<String, int> dropped;
}

String _fnv(String s) {
  var hash = 0xcbf29ce484222325;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

String _fold(String line) {
  if (line.length <= 75) {
    return line;
  }
  final out = StringBuffer(line.substring(0, 75));
  for (var i = 75; i < line.length; i += 74) {
    final end = i + 74 < line.length ? i + 74 : line.length;
    out.write('\r\n ${line.substring(i, end)}');
  }
  return out.toString();
}

/// Scrubs [raw]. [capturedUtc] is written into the header so tests can pick
/// a window around the time the feed was captured.
ScrubResult scrubFeed(String raw, {required DateTime capturedUtc}) {
  final lines = unfoldLines(raw);
  final out = <String>[];
  final titles = <String, int>{};
  final places = <String, int>{};
  final people = <String, int>{};
  final dropped = <String, int>{};
  var events = 0;
  var withTeams = 0;
  var teamsInEvent = false;
  var linkNumber = 0;

  int numberFor(Map<String, int> map, String key) =>
      map.putIfAbsent(key, () => map.length + 1);
  String teamsUrl() =>
      'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SCRUBBED${++linkNumber}%40thread.v2/0?context=%7b%7d';

  // First pass: which raw events have a Teams link (per VEVENT).
  final eventHasTeams = <bool>[];
  var meetLinks = 0;
  String? description;
  String? location;
  for (final rawLine in lines) {
    final cl = parseContentLine(rawLine, 0);
    if (cl == null) {
      continue;
    }
    if (cl.name == 'BEGIN' && cl.value.trim().toUpperCase() == 'VEVENT') {
      description = null;
      location = null;
    } else if (cl.name == 'DESCRIPTION') {
      description = unescapeText(cl.value);
    } else if (cl.name == 'LOCATION') {
      location = unescapeText(cl.value);
    } else if (cl.name == 'END' && cl.value.trim().toUpperCase() == 'VEVENT') {
      eventHasTeams.add(extractTeamsJoinUrl(description, location) != null);
      if (_meetLink.hasMatch('$description $location')) {
        meetLinks++;
      }
    }
  }

  for (final rawLine in lines) {
    final cl = parseContentLine(rawLine, 0);
    if (cl == null) {
      continue;
    }
    final value = cl.value;
    switch (cl.name) {
      case 'BEGIN':
        out.add('BEGIN:${value.trim()}');
        if (value.trim().toUpperCase() == 'VCALENDAR') {
          out
            ..add('X-TMINUS-CAPTURED:${_utcStamp(capturedUtc)}')
            ..add(
              'X-TMINUS-RAW-TEAMS-EVENTS:'
              '${eventHasTeams.where((has) => has).length}',
            );
        } else if (value.trim().toUpperCase() == 'VEVENT') {
          teamsInEvent = events < eventHasTeams.length && eventHasTeams[events];
          events++;
          if (teamsInEvent) {
            withTeams++;
          }
        }
      case 'X-WR-CALNAME':
        out.add('X-WR-CALNAME:Scrubbed calendar');
      case 'UID':
        out.add('UID:uid-${_fnv(value.trim())}');
      case 'SUMMARY':
        final title = unescapeText(value).trim();
        final prefix = isCancelledTitle(title) ? 'Canceled: ' : '';
        out.add('SUMMARY:${prefix}Event ${numberFor(titles, title)}');
      case 'DESCRIPTION':
        out.add(
          teamsInEvent
              ? 'DESCRIPTION:Microsoft Teams meeting\\nJoin: <${teamsUrl()}>'
              : 'DESCRIPTION:Scrubbed description',
        );
      case 'LOCATION':
        final place = unescapeText(value).trim();
        if (place.isEmpty) {
          out.add('LOCATION:');
        } else if (extractTeamsJoinUrl(null, place) != null) {
          out.add('LOCATION:${teamsUrl()}');
        } else if (place.toLowerCase().contains('microsoft teams')) {
          out.add('LOCATION:Microsoft Teams Meeting');
        } else {
          out.add('LOCATION:Place ${numberFor(places, place)}');
        }
      case 'ORGANIZER' || 'ATTENDEE':
        final who = (cl.params['CN'] ?? value).trim().toLowerCase();
        final n = numberFor(people, who);
        final partstat = cl.params['PARTSTAT'];
        out.add(
          '${cl.name};CN="Person $n"'
          '${partstat == null ? '' : ';PARTSTAT=$partstat'}'
          ':mailto:person$n@example.com',
        );
      default:
        if (keptProperties.contains(cl.name)) {
          out.add(rawLine);
        } else {
          dropped[cl.name] = (dropped[cl.name] ?? 0) + 1;
        }
    }
  }
  final text = '${out.map(_fold).join('\r\n')}\r\n';
  return ScrubResult(text, events, withTeams, meetLinks, dropped);
}

String _utcStamp(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

final _meetLink = RegExp(
  r'https://teams\.microsoft\.com/meet/',
  caseSensitive: false,
);

final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

/// Email addresses left in [text] that are not @example.com.
List<String> leakedEmails(String text) => [
  for (final m in _email.allMatches(text))
    if (!m[0]!.toLowerCase().endsWith('@example.com')) m[0]!,
];

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/scrub_feed.dart <raw.ics> <scrubbed.ics>',
    );
    exit(64);
  }
  final raw = await File(args[0]).readAsString();
  final result = scrubFeed(raw, capturedUtc: DateTime.now().toUtc());
  final leaks = leakedEmails(result.text);
  if (leaks.isNotEmpty) {
    stderr.writeln(
      'Refusing to write: ${leaks.length} email address(es) survived scrubbing.',
    );
    exit(1);
  }
  await File(args[1]).writeAsString(result.text);
  stdout
    ..writeln('VEVENTs: ${result.events}')
    ..writeln('VEVENTs with a Teams join link: ${result.eventsWithTeamsLink}')
    ..writeln(
      'VEVENTs with a teams.microsoft.com/meet/ link: '
      '${result.eventsWithMeetLink}',
    )
    ..writeln('Dropped properties: ${result.dropped}')
    ..writeln('Wrote ${args[1]}');
}
