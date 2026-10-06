import 'package:ics_core/src/content_line.dart';
import 'package:ics_core/src/values.dart';
import 'package:rrule/rrule.dart';
import 'package:test/test.dart';

void main() {
  group('parseIcsTime', () {
    test('DATE-TIME with TZID keeps wall fields and the zone name', () {
      expect(
        parseIcsTime('20261012T084500', tzid: ' South Africa Standard Time '),
        IcsTime(
          wall: DateTime.utc(2026, 10, 12, 8, 45),
          isDate: false,
          isUtc: false,
          tzid: 'South Africa Standard Time',
        ),
      );
    });

    test('UTC DATE-TIME ignores any TZID', () {
      final t = parseIcsTime('20261012T064500Z', tzid: 'Ignored');
      expect(t.isUtc, isTrue);
      expect(t.tzid, isNull);
      expect(t.wall, DateTime.utc(2026, 10, 12, 6, 45));
    });

    test('DATE', () {
      final t = parseIcsTime('20261013');
      expect(t.isDate, isTrue);
      expect(t.wall, DateTime.utc(2026, 10, 13));
    });

    test('rejects impossible or malformed values', () {
      for (final bad in [
        '20261332',
        '20260230',
        '20261012T250000',
        '20261012T086000',
        '2026-10-12',
        '20261012T0845',
        '',
      ]) {
        expect(() => parseIcsTime(bad), throwsFormatException, reason: bad);
      }
    });
  });

  test('parseIcsTimes reads comma-separated values with the line TZID', () {
    final line = parseContentLine(
      'EXDATE;TZID=W. Europe Standard Time:20261013T090000,20261015T090000',
      1,
    )!;
    expect(parseIcsTimes(line).map((t) => (t.wall.day, t.tzid)), [
      (13, 'W. Europe Standard Time'),
      (15, 'W. Europe Standard Time'),
    ]);
  });

  group('parseIcsDuration', () {
    test('reads weeks, days, hours, minutes and seconds', () {
      expect(
        parseIcsDuration('PT1H30M'),
        const Duration(hours: 1, minutes: 30),
      );
      expect(parseIcsDuration('P1D'), const Duration(days: 1));
      expect(parseIcsDuration('P2W'), const Duration(days: 14));
      expect(
        parseIcsDuration('+P1DT2H3M4S'),
        const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
      );
    });

    test('rejects malformed and negative durations', () {
      for (final bad in ['soon', 'P', 'PT', '1H', '-PT15M']) {
        expect(() => parseIcsDuration(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('parseRrule', () {
    DateTime plusTwo(DateTime utc) => utc.add(const Duration(hours: 2));

    test('drops WKST=SU, which package:rrule rejects', () {
      final rule = parseRrule(
        'FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,TU;WKST=SU',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 12, 9)).take(3), [
        DateTime.utc(2026, 10, 12, 9),
        DateTime.utc(2026, 10, 13, 9),
        DateTime.utc(2026, 10, 19, 9),
      ]);
    });

    test('converts a UTC UNTIL to the event wall clock (inclusive)', () {
      // 07:00Z is 09:00 in UTC+2, so the 09:00 instance on the 8th is kept.
      final rule = parseRrule(
        'FREQ=DAILY;UNTIL=20261008T070000Z',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5, 9)).length, 4);
    });

    test('a local UNTIL is used as written', () {
      final rule = parseRrule(
        'RRULE:FREQ=DAILY;UNTIL=20261007T090000',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5, 9)).length, 3);
    });

    test('a DATE UNTIL on a timed event runs through that day', () {
      final rule = parseRrule(
        'FREQ=DAILY;UNTIL=20261006',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5, 9)).length, 2);
    });

    test('a DATE-TIME UNTIL on an all-day event keeps only its date', () {
      final rule = parseRrule(
        'FREQ=DAILY;UNTIL=20261007T235959Z',
        untilUtcToWall: plusTwo,
        startIsDate: true,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5)).length, 3);
    });

    test('rejects UNTIL with COUNT, and unknown values', () {
      expect(
        () => parseRrule(
          'FREQ=DAILY;COUNT=2;UNTIL=20261007',
          untilUtcToWall: plusTwo,
          startIsDate: false,
        ),
        throwsFormatException,
      );
      expect(
        () => parseRrule(
          'FREQ=SOMETIMES',
          untilUtcToWall: plusTwo,
          startIsDate: false,
        ),
        throwsFormatException,
      );
    });

    test('reads lowercase names and values, including UNTIL', () {
      final rule = parseRrule(
        'freq=weekly;byday=mo,we;until=20261021t070000z;wkst=su',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 12, 9)), [
        DateTime.utc(2026, 10, 12, 9),
        DateTime.utc(2026, 10, 14, 9),
        DateTime.utc(2026, 10, 19, 9),
        DateTime.utc(2026, 10, 21, 9),
      ]);
    });

    // Each of these makes package:rrule loop forever (or for millennia)
    // when asserts are off, as in a release build.
    void expectRejected(String rule) => expect(
      () => parseRrule(rule, untilUtcToWall: plusTwo, startIsDate: false),
      throwsFormatException,
      reason: rule,
    );

    test('rejects INTERVAL and COUNT below 1', () {
      expectRejected('FREQ=DAILY;INTERVAL=0');
      expectRejected('FREQ=WEEKLY;INTERVAL=-2;BYDAY=MO');
      expectRejected('FREQ=DAILY;COUNT=0');
      expectRejected('FREQ=DAILY;COUNT=-3');
      expectRejected('FREQ=DAILY;INTERVAL=x');
    });

    test('rejects HOURLY, MINUTELY and SECONDLY rules', () {
      expectRejected('FREQ=HOURLY');
      expectRejected('FREQ=MINUTELY;INTERVAL=15');
      expectRejected('FREQ=SECONDLY;COUNT=5');
    });

    test('rejects BYMONTH/BYMONTHDAY combinations that never match', () {
      expectRejected('FREQ=DAILY;BYMONTH=2;BYMONTHDAY=30');
      expectRejected('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-30');
      expectRejected('FREQ=MONTHLY;BYMONTHDAY=31;BYMONTH=4,6,9,11');
      expectRejected('FREQ=MONTHLY;BYMONTHDAY=32');
    });

    test('accepts BYMONTH/BYMONTHDAY combinations that sometimes match', () {
      for (final ok in [
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29',
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-29',
        'FREQ=MONTHLY;BYMONTHDAY=31;BYMONTH=4,5',
        'FREQ=MONTHLY;BYMONTHDAY=30,31;BYMONTH=6',
        'FREQ=MONTHLY;BYMONTHDAY=-31',
      ]) {
        expect(
          parseRrule(ok, untilUtcToWall: plusTwo, startIsDate: false),
          isA<RecurrenceRule>(),
          reason: ok,
        );
      }
    });
  });
}
