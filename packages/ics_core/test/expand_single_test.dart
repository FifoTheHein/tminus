import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final from = DateTime.utc(2026, 10, 12);
  final to = DateTime.utc(2026, 10, 19);

  group('time zones (windows_tzids.ics)', () {
    final r = expandFixture(
      'windows_tzids.ics',
      from: from,
      to: DateTime.utc(2026, 11, 15),
    );
    IcsOccurrence one(String uid) => byUid(r, uid).single;

    test('no issues', () => expect(r.issues, isEmpty));

    test('Windows TZID → IANA (Berlin, still on summer time)', () {
      expect(one('berlin').startUtc, DateTime.utc(2026, 10, 13, 8));
      expect(one('berlin').endUtc, DateTime.utc(2026, 10, 13, 9));
      expect(one('berlin').warnings, isEmpty);
    });

    test('IANA TZID used directly', () {
      expect(one('london').startUtc, DateTime.utc(2026, 10, 13, 9));
    });

    test('quoted Windows TZID mapped to an old IANA link name', () {
      expect(one('india').startUtc, DateTime.utc(2026, 10, 13, 4, 30));
    });

    test('custom TZID computed from the feed VTIMEZONE, flagged', () {
      expect(one('custom-oct').startUtc, DateTime.utc(2026, 10, 13, 16));
      expect(one('custom-nov').startUtc, DateTime.utc(2026, 11, 10, 17));
      expect(one('custom-oct').warnings, {IcsWarning.tzFromVtimezone});
    });

    test('unknown TZID with no VTIMEZONE uses the device zone, flagged', () {
      expect(one('unknown').startUtc, DateTime.utc(2026, 10, 13, 8));
      expect(one('unknown').warnings, {IcsWarning.tzFromDevice});
    });

    test('UTC and floating times; floating is not flagged', () {
      expect(one('utc').startUtc, DateTime.utc(2026, 10, 13, 10));
      expect(one('floating').startUtc, DateTime.utc(2026, 10, 13, 8));
      expect(one('floating').warnings, isEmpty);
    });

    test('DTSTART and DTEND may use different zones', () {
      expect(one('mixed').startUtc, DateTime.utc(2026, 10, 13, 16));
      expect(one('mixed').endUtc, DateTime.utc(2026, 10, 13, 17));
    });

    test('one-off events are not recurring; original start = start', () {
      expect(one('berlin').recurring, isFalse);
      expect(one('berlin').originalStartUtc, one('berlin').startUtc);
    });
  });

  group('all-day, multi-day and lengths (all_day_multi_day.ics)', () {
    final r = expandFixture('all_day_multi_day.ics', from: from, to: to);
    IcsOccurrence one(String uid) => byUid(r, uid).single;

    test('an all-day event spans local midnight to midnight, as UTC', () {
      final o = one('holiday');
      expect(o.allDay, isTrue);
      expect(o.startUtc, DateTime.utc(2026, 10, 12, 22));
      expect(o.endUtc, DateTime.utc(2026, 10, 13, 22));
      expect(o.busyStatus, IcsBusyStatus.free);
    });

    test('a multi-day all-day event keeps its length', () {
      expect(one('conference').startUtc, DateTime.utc(2026, 10, 13, 22));
      expect(one('conference').endUtc, DateTime.utc(2026, 10, 16, 22));
      expect(one('conference').busyStatus, IcsBusyStatus.oof);
    });

    test('an all-day event with no DTEND lasts one day', () {
      expect(
        one('no-end').endUtc.difference(one('no-end').startUtc),
        const Duration(days: 1),
      );
    });

    test('a timed event can span days', () {
      expect(one('offsite').allDay, isFalse);
      expect(one('offsite').startUtc, DateTime.utc(2026, 10, 15, 7));
      expect(one('offsite').endUtc, DateTime.utc(2026, 10, 16, 15));
    });

    test('DURATION sets the end', () {
      expect(one('duration').endUtc, DateTime.utc(2026, 10, 15, 10, 30));
    });

    test('no DTEND and no DURATION means zero length', () {
      expect(one('zero').endUtc, one('zero').startUtc);
    });

    test('all-day events follow the device zone', () {
      final london = expandFixture(
        'all_day_multi_day.ics',
        from: from,
        to: to,
        deviceZone: 'Europe/London',
      );
      expect(
        byUid(london, 'holiday').single.startUtc,
        DateTime.utc(2026, 10, 12, 23),
      );
    });
  });

  group('window semantics: overlap with [start, end)', () {
    String event(String start, String end) => calendar('''
BEGIN:VEVENT
UID:w
SUMMARY:W
DTSTART:$start
DTEND:$end
END:VEVENT''');
    List<IcsOccurrence> run(String start, String end) => expandIcs(
      event(start, end),
      windowStartUtc: DateTime.utc(2026, 10, 13, 10),
      windowEndUtc: DateTime.utc(2026, 10, 13, 12),
      deviceZone: 'Africa/Johannesburg',
    ).occurrences;

    test('ending exactly at the window start is out', () {
      expect(run('20261013T090000Z', '20261013T100000Z'), isEmpty);
    });

    test('starting exactly at the window end is out', () {
      expect(run('20261013T120000Z', '20261013T130000Z'), isEmpty);
    });

    test('started before the window and still running is in', () {
      expect(run('20261013T090000Z', '20261013T103000Z'), hasLength(1));
    });

    test('a zero-length event at the window start is in', () {
      expect(run('20261013T100000Z', '20261013T100000Z'), hasLength(1));
    });

    test(
      'DTEND before DTSTART gives a zero-length event, not a dropped one',
      () {
        final o = run('20261013T110000Z', '20261013T100000Z').single;
        expect(o.endUtc, o.startUtc);
      },
    );

    test('an empty window is an error', () {
      expect(
        () => expandIcs(
          event('20261013T100000Z', '20261013T110000Z'),
          windowStartUtc: DateTime.utc(2026, 10, 13),
          windowEndUtc: DateTime.utc(2026, 10, 13),
          deviceZone: 'Africa/Johannesburg',
        ),
        throwsArgumentError,
      );
    });
  });

  test('cancelled events and Canceled:/Cancelled: titles are dropped', () {
    final r = expandFixture('canceled_titles.ics', from: from, to: to);
    expect(r.occurrences.map((o) => o.uid), ['k1', 'k2']);
    expect(r.issues, isEmpty);
  });

  group('Teams links (teams_links.ics)', () {
    final r = expandFixture('teams_links.ics', from: from, to: to);
    String? link(String uid) => byUid(r, uid).single.joinUrl;

    test('Outlook description link, without the closing >', () {
      expect(
        link('outlook-desc'),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA1ZTI4%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d',
      );
    });

    test('location link without the trailing full stop', () {
      expect(
        link('location-only'),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_LOC%40thread.v2/0?context=%7b%7d',
      );
    });

    test('Safe Links wrapper is decoded', () {
      expect(
        link('safelinks'),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SAFE%40thread.v2/0',
      );
    });

    test('description wins over location; none gives null', () {
      expect(link('both'), contains('meeting_DESC'));
      expect(link('none'), isNull);
    });

    test('organizer, location and description come through', () {
      final o = byUid(r, 'outlook-desc').single;
      expect(o.organizer, 'Thandi M.');
      expect(o.location, 'Microsoft Teams Meeting');
      expect(
        o.description,
        contains('Join on your computer, mobile app or room device'),
      );
      expect(o.busyStatus, IcsBusyStatus.busy);
    });
  });

  group('folded lines (folded_lines.ics)', () {
    test('unfolds names, parameters, values and URLs', () {
      final o = expandFixture(
        'folded_lines.ics',
        from: from,
        to: to,
      ).occurrences.single;
      expect(o.uid, 'folded@example.com');
      expect(o.title, 'Quarterly planning: goals, risks and next steps');
      expect(o.organizer, 'Thandi M.');
      expect(o.location, 'Room 4; Building B');
      expect(o.description, startsWith('Agenda:\n1. Goals\n2. Risks\n3. Join'));
      expect(
        o.joinUrl,
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_FOLD%40thread.v2/0?context=%7b%7d',
      );
      expect(o.endUtc, DateTime.utc(2026, 10, 14, 8));
    });

    test('CRLF and LF files give the same result', () {
      final lf = fixture('folded_lines.ics').replaceAll('\r\n', '\n');
      IcsResult run(String text) => expandIcs(
        text,
        windowStartUtc: from,
        windowEndUtc: to,
        deviceZone: 'Africa/Johannesburg',
      );
      expect(run(lf.replaceAll('\n', '\r\n')).occurrences, run(lf).occurrences);
    });
  });

  group('error isolation (malformed.ics)', () {
    final r = expandFixture('malformed.ics', from: from, to: to);

    test('good events still come through', () {
      expect(r.occurrences.map((o) => o.uid), ['good-1', 'good-2']);
    });

    test('each bad VEVENT becomes one issue with its UID and line', () {
      expect(r.issues, const [
        IcsIssue(
          uid: 'bad-no-start',
          line: 9,
          message: 'VEVENT has no DTSTART',
        ),
        IcsIssue(
          uid: 'bad-date',
          line: 14,
          message: 'Bad date or date-time: "20261345T250000"',
        ),
        IcsIssue(
          uid: 'bad-duration',
          line: 19,
          message: 'Bad DURATION: "soon"',
        ),
        IcsIssue(
          uid: 'truncated',
          line: 31,
          message: 'VEVENT has no END:VEVENT',
        ),
      ]);
    });

    test('text that is not a calendar throws IcsFormatException', () {
      expect(
        () => expandIcs(
          '<html><body>Sign in</body></html>',
          windowStartUtc: from,
          windowEndUtc: to,
          deviceZone: 'Africa/Johannesburg',
        ),
        throwsA(isA<IcsFormatException>()),
      );
    });
  });
}
