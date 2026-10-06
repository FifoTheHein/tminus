import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('weekly RRULE with EXDATE (weekly_exdate.ics)', () {
    final week = expandFixture(
      'weekly_exdate.ics',
      from: DateTime.utc(2026, 10, 12),
      to: DateTime.utc(2026, 10, 17),
    );

    test('Mon–Fri standup minus three EXDATEs on two lines', () {
      expect(startsOf(week, 'standup@example.com'), [
        '2026-10-12T06:45:00.000Z',
        '2026-10-14T06:45:00.000Z',
      ]);
      expect(week.issues, isEmpty);
    });

    test('instances are recurring, keep their length and original start', () {
      final o = byUid(week, 'standup@example.com').first;
      expect(o.recurring, isTrue);
      expect(o.endUtc.difference(o.startUtc), const Duration(minutes: 15));
      expect(o.originalStartUtc, o.startUtc);
      expect(o.title, 'Daily standup');
      expect(o.busyStatus, IcsBusyStatus.busy);
    });

    test('UNTIL (UTC) ends the series on its last day', () {
      final r = expandFixture(
        'weekly_exdate.ics',
        from: DateTime.utc(2026, 12, 28),
        to: DateTime.utc(2027, 1, 9),
      );
      expect(startsOf(r, 'standup@example.com'), [
        '2026-12-28T06:45:00.000Z',
        '2026-12-29T06:45:00.000Z',
        '2026-12-30T06:45:00.000Z',
        '2026-12-31T06:45:00.000Z',
      ]);
    });

    test('all-day weekly series with COUNT and a DATE EXDATE', () {
      final r = expandFixture(
        'weekly_exdate.ics',
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 11, 30),
      );
      final leave = byUid(r, 'leave@example.com');
      expect(leave.map((o) => o.startUtc.toIso8601String()), [
        '2026-10-11T22:00:00.000Z',
        '2026-10-25T22:00:00.000Z',
        '2026-11-01T22:00:00.000Z',
      ]);
      expect(leave.every((o) => o.allDay), isTrue);
      expect(leave.first.endUtc, DateTime.utc(2026, 10, 12, 22));
    });
  });

  group('COUNT, INTERVAL and UNTIL (until_count.ics)', () {
    final r = expandFixture(
      'until_count.ics',
      from: DateTime.utc(2026, 9, 1),
      to: DateTime.utc(2026, 12, 1),
    );

    test('INTERVAL=2 with COUNT=3', () {
      expect(startsOf(r, 'review@example.com'), [
        '2026-10-01T12:00:00.000Z',
        '2026-10-15T12:00:00.000Z',
        '2026-10-29T12:00:00.000Z',
      ]);
    });

    test('COUNT counts from DTSTART even when the window starts later', () {
      final late = expandFixture(
        'until_count.ics',
        from: DateTime.utc(2026, 10, 10),
        to: DateTime.utc(2026, 12, 1),
      );
      expect(startsOf(late, 'review@example.com'), [
        '2026-10-15T12:00:00.000Z',
        '2026-10-29T12:00:00.000Z',
      ]);
    });

    test('a UTC UNTIL is compared in the event zone (last day kept)', () {
      expect(startsOf(r, 'checkin-utc@example.com'), [
        '2026-10-05T07:00:00.000Z',
        '2026-10-06T07:00:00.000Z',
        '2026-10-07T07:00:00.000Z',
        '2026-10-08T07:00:00.000Z',
      ]);
    });

    test('a local UNTIL is compared as written', () {
      expect(startsOf(r, 'checkin-local@example.com'), [
        '2026-10-05T08:00:00.000Z',
        '2026-10-06T08:00:00.000Z',
      ]);
    });

    test('a DATE UNTIL includes that whole day', () {
      expect(startsOf(r, 'checkin-date@example.com'), [
        '2026-10-05T09:00:00.000Z',
        '2026-10-06T09:00:00.000Z',
      ]);
    });
  });

  group('monthly BYDAY (monthly_byday.ics)', () {
    final r = expandFixture(
      'monthly_byday.ics',
      from: DateTime.utc(2026, 10, 1),
      to: DateTime.utc(2027, 1, 1),
    );

    test('2MO: second Monday', () {
      expect(startsOf(r, 'townhall@example.com'), [
        '2026-10-12T13:00:00.000Z',
        '2026-11-09T13:00:00.000Z',
        '2026-12-14T13:00:00.000Z',
      ]);
    });

    test('-1FR: last Friday', () {
      expect(startsOf(r, 'drinks@example.com'), [
        '2026-10-30T14:00:00.000Z',
        '2026-11-27T14:00:00.000Z',
        '2026-12-25T14:00:00.000Z',
      ]);
    });

    test('BYSETPOS=-1: last weekday of the month', () {
      expect(startsOf(r, 'report@example.com'), [
        '2026-10-30T06:00:00.000Z',
        '2026-11-30T06:00:00.000Z',
        '2026-12-31T06:00:00.000Z',
      ]);
    });
  });

  group(
    'organiser in a DST zone, viewer in Johannesburg (dst_organizer.ics)',
    () {
      final r = expandFixture(
        'dst_organizer.ics',
        from: DateTime.utc(2026, 10, 19),
        to: DateTime.utc(2026, 11, 10),
      );

      test('US Pacific meeting stays at 09:00 local across 1 Nov', () {
        expect(startsOf(r, 'us-sync@example.com'), [
          '2026-10-19T16:00:00.000Z',
          '2026-10-26T16:00:00.000Z',
          '2026-11-02T17:00:00.000Z',
          '2026-11-09T17:00:00.000Z',
        ]);
        final o = byUid(r, 'us-sync@example.com').last;
        expect(o.endUtc.difference(o.startUtc), const Duration(hours: 1));
        expect(o.organizer, 'Dana R.');
        expect(o.warnings, isEmpty);
      });

      test('European meeting stays at 09:00 local across 25 Oct', () {
        expect(startsOf(r, 'eu-sync@example.com'), [
          '2026-10-19T07:00:00.000Z',
          '2026-10-26T08:00:00.000Z',
          '2026-11-02T08:00:00.000Z',
          '2026-11-09T08:00:00.000Z',
        ]);
      });

      test('results are sorted by start time', () {
        final starts = r.occurrences.map((o) => o.startUtc).toList();
        expect(starts, [...starts]..sort());
      });
    },
  );

  test('a long-running daily series expands only inside the window', () {
    final r = expandIcs(
      calendar('''
BEGIN:VEVENT
UID:old-daily
SUMMARY:Since 2015
RRULE:FREQ=DAILY
DTSTART;TZID=South Africa Standard Time:20150105T080000
DTEND;TZID=South Africa Standard Time:20150105T081500
END:VEVENT'''),
      windowStartUtc: DateTime.utc(2026, 10, 12, 5),
      windowEndUtc: DateTime.utc(2026, 10, 14, 5),
      deviceZone: 'Africa/Johannesburg',
    );
    expect(startsOf(r, 'old-daily'), [
      '2026-10-12T06:00:00.000Z',
      '2026-10-13T06:00:00.000Z',
    ]);
  });

  test('a broken RRULE becomes an issue; other events still parse', () {
    final r = expandIcs(
      calendar('''
BEGIN:VEVENT
UID:good
SUMMARY:Good
DTSTART:20261013T090000Z
DTEND:20261013T100000Z
END:VEVENT
BEGIN:VEVENT
UID:bad-rrule
SUMMARY:Bad rule
RRULE:FREQ=SOMETIMES
DTSTART:20261013T110000Z
END:VEVENT'''),
      windowStartUtc: DateTime.utc(2026, 10, 12),
      windowEndUtc: DateTime.utc(2026, 10, 19),
      deviceZone: 'Africa/Johannesburg',
    );
    expect(r.occurrences.map((o) => o.uid), ['good']);
    expect(r.issues.single.uid, 'bad-rrule');
    expect(r.issues.single.line, 9);
  });

  test('a series with too many instances in the window becomes an issue', () {
    // 1440 instances a day for 8 days: past the 10,000 cap.
    final minutes = List.generate(60, (m) => '$m').join(',');
    final hours = List.generate(24, (h) => '$h').join(',');
    final r = expandIcs(
      calendar('''
BEGIN:VEVENT
UID:good
DTSTART:20261013T090000Z
END:VEVENT
BEGIN:VEVENT
UID:every-minute
DTSTART:20261012T000000Z
RRULE:FREQ=DAILY;BYHOUR=$hours;BYMINUTE=$minutes
END:VEVENT'''),
      windowStartUtc: DateTime.utc(2026, 10, 12),
      windowEndUtc: DateTime.utc(2026, 10, 20),
      deviceZone: 'Africa/Johannesburg',
    );
    expect(r.occurrences.map((o) => o.uid), ['good']);
    expect(r.issues.single.uid, 'every-minute');
    expect(r.issues.single.message, contains('10000'));
  });
}
