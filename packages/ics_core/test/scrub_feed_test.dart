import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import '../tool/scrub_feed.dart';

const raw = r'''
BEGIN:VCALENDAR
METHOD:PUBLISH
PRODID:Microsoft Exchange Server 2010
VERSION:2.0
X-WR-CALNAME:Alex Doe Calendar
BEGIN:VTIMEZONE
TZID:South Africa Standard Time
BEGIN:STANDARD
DTSTART:16010101T000000
TZOFFSETFROM:+0200
TZOFFSETTO:+0200
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
UID:040000008200E00074C5B7101A82E00800000000SECRET
SUMMARY:Salary review with Thandi
DESCRIPTION:Private notes\nClick here to join the meeting<https://teams.mi
 crosoft.com/l/meetup-join/19%3ameeting_REALID%40thread.v2/0?context=%7b%22
 Tid%22%3a%22real-tenant%22%7d>
LOCATION:Microsoft Teams Meeting
ORGANIZER;CN="Thandi Mokoena":mailto:thandi.mokoena@contoso.co.za
ATTENDEE;CN="Pieter V";PARTSTAT=ACCEPTED:mailto:pieter@contoso.co.za
X-ALT-DESC;FMTTYPE=text/html:<html>Private notes</html>
RRULE:FREQ=WEEKLY;UNTIL=20261231T080000Z;INTERVAL=1;BYDAY=TU;WKST=SU
EXDATE;TZID=South Africa Standard Time:20261013T100000
DTSTART;TZID=South Africa Standard Time:20261006T100000
DTEND;TZID=South Africa Standard Time:20261006T103000
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
END:VEVENT
BEGIN:VEVENT
UID:040000008200E00074C5B7101A82E00800000000SECRET
RECURRENCE-ID;TZID=South Africa Standard Time:20261020T100000
SUMMARY:Canceled: Salary review with Thandi
DTSTART;TZID=South Africa Standard Time:20261020T100000
DTEND;TZID=South Africa Standard Time:20261020T103000
END:VEVENT
BEGIN:VEVENT
UID:dentist-1
SUMMARY:Dentist
LOCATION:12 Long Street\, Cape Town
DTSTART;TZID=South Africa Standard Time:20261015T080000
DTEND;TZID=South Africa Standard Time:20261015T090000
END:VEVENT
END:VCALENDAR
''';

void main() {
  final result = scrubFeed(raw, capturedUtc: DateTime.utc(2026, 10, 6, 12));

  test('removes names, addresses, notes, places and real ids', () {
    for (final secret in [
      'Thandi',
      'Pieter',
      'Alex Doe',
      'Salary',
      'Private notes',
      'contoso',
      'REALID',
      'real-tenant',
      'SECRET',
      'Long Street',
      'Dentist',
    ]) {
      expect(result.text, isNot(contains(secret)), reason: secret);
    }
    expect(leakedEmails(result.text), isEmpty);
  });

  test('keeps zones, rules, exceptions, overrides and busy status', () {
    for (final kept in [
      'TZID:South Africa Standard Time',
      'RRULE:FREQ=WEEKLY;UNTIL=20261231T080000Z;INTERVAL=1;BYDAY=TU;WKST=SU',
      'EXDATE;TZID=South Africa Standard Time:20261013T100000',
      'RECURRENCE-ID;TZID=South Africa Standard Time:20261020T100000',
      'X-MICROSOFT-CDO-BUSYSTATUS:BUSY',
      'SUMMARY:Canceled: Event 2',
    ]) {
      expect(result.text, contains(kept), reason: kept);
    }
  });

  test('records capture time and the raw Teams link count', () {
    expect(result.text, contains('X-TMINUS-CAPTURED:20261006T120000Z'));
    expect(result.text, contains('X-TMINUS-RAW-TEAMS-EVENTS:1'));
    expect(result.events, 3);
    expect(result.eventsWithTeamsLink, 1);
    expect(result.eventsWithMeetLink, 0);
    expect(result.dropped, {'X-ALT-DESC': 1});
  });

  test(
    'the scrubbed feed parses the same way, with a synthetic Teams link',
    () {
      IcsResult run(String text) => expandIcs(
        text,
        windowStartUtc: DateTime.utc(2026, 10, 1),
        windowEndUtc: DateTime.utc(2026, 10, 31),
        deviceZone: 'Africa/Johannesburg',
      );
      final before = run(raw);
      final after = run(result.text);
      expect(after.issues, isEmpty);
      expect(
        after.occurrences.map((o) => o.startUtc),
        before.occurrences.map((o) => o.startUtc),
      );
      expect(
        after.occurrences.first.joinUrl,
        startsWith(
          'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SCRUBBED',
        ),
      );
      expect(after.occurrences.first.organizer, 'Person 1');
    },
  );
}
