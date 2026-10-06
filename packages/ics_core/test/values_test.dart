import 'package:ics_core/src/content_line.dart';
import 'package:ics_core/src/values.dart';
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
  });
}
