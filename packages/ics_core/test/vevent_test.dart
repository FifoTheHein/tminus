import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:ics_core/src/vevent.dart';
import 'package:test/test.dart';

Component event(List<String> lines) => parseCalendar(
  [
    'BEGIN:VCALENDAR',
    'BEGIN:VEVENT',
    ...lines,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n'),
).children.single;

void main() {
  test('reads every field the expander needs', () {
    final e = parseVevent(
      event([
        'UID:abc',
        r'SUMMARY:Sprint planning\, Q4',
        'DTSTART;TZID=W. Europe Standard Time:20261013T090000',
        'DTEND;TZID=W. Europe Standard Time:20261013T100000',
        'RRULE:FREQ=WEEKLY;BYDAY=TU',
        'EXDATE;TZID=W. Europe Standard Time:20261020T090000,20261027T090000',
        'EXDATE;TZID=W. Europe Standard Time:20261103T090000',
        'LOCATION:Room 2',
        r'DESCRIPTION:Join<https://teams.microsoft.com/l/meetup-join/x>\nThanks',
        'ORGANIZER;CN="Thandi M.":mailto:thandi@example.com',
        'X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE',
      ]),
    );
    expect(e.uid, 'abc');
    expect(e.line, 2);
    expect(e.title, 'Sprint planning, Q4');
    expect(e.start.tzid, 'W. Europe Standard Time');
    expect(e.end!.wall, DateTime.utc(2026, 10, 13, 10));
    expect(e.rrule, 'FREQ=WEEKLY;BYDAY=TU');
    expect(e.exdates.map((t) => t.wall.day), [20, 27, 3]);
    expect(e.location, 'Room 2');
    expect(
      e.description,
      'Join<https://teams.microsoft.com/l/meetup-join/x>\nThanks',
    );
    expect(e.joinUrl, 'https://teams.microsoft.com/l/meetup-join/x');
    expect(e.organizer, 'Thandi M.');
    expect(e.busyStatus, IcsBusyStatus.tentative);
    expect(e.cancelled, isFalse);
    expect(e.allDay, isFalse);
    expect(e.recurrenceId, isNull);
  });

  test('STATUS:CANCELLED or a Canceled: title marks it cancelled', () {
    expect(
      parseVevent(event(['UID:a', 'DTSTART:20261013', 'status:cancelled']))
          .cancelled,
      isTrue,
    );
    expect(
      parseVevent(event(['UID:a', 'DTSTART:20261013', 'SUMMARY:Canceled: x']))
          .cancelled,
      isTrue,
    );
  });

  test('reads RECURRENCE-ID and DURATION', () {
    final e = parseVevent(
      event([
        'UID:a',
        'RECURRENCE-ID;TZID=Europe/London:20261013T090000',
        'DTSTART;TZID=Europe/London:20261014T090000',
        'DURATION:PT45M',
      ]),
    );
    expect(e.recurrenceId!.wall, DateTime.utc(2026, 10, 13, 9));
    expect(e.duration, const Duration(minutes: 45));
  });

  test('a missing SUMMARY is an empty title', () {
    expect(parseVevent(event(['UID:a', 'DTSTART:20261013'])).title, '');
  });

  test('a missing UID gets a stable stand-in from DTSTART and SUMMARY', () {
    List<String> lines() => ['SUMMARY:No uid', 'DTSTART:20261013T090000Z'];
    final a = parseVevent(event(lines()));
    final b = parseVevent(event(lines()));
    expect(a.uid, 'no-uid:20261013T090000Z|No uid');
    expect(a.uid, b.uid);
  });

  test('no DTSTART, a bad DTEND or a bad DURATION throw FormatException', () {
    expect(() => parseVevent(event(['UID:a'])), throwsFormatException);
    expect(
      () => parseVevent(
        event(['UID:a', 'DTSTART:20261013T090000Z', 'DTEND:tomorrow']),
      ),
      throwsFormatException,
    );
    expect(
      () => parseVevent(
        event(['UID:a', 'DTSTART:20261013T090000Z', 'DURATION:1h']),
      ),
      throwsFormatException,
    );
  });
}
