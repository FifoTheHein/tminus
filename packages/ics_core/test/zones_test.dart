import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:ics_core/src/values.dart';
import 'package:ics_core/src/zones/wall_zone.dart';
import 'package:ics_core/src/zones/zone_resolver.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as small_db;
import 'package:timezone/timezone.dart' as tz;

/// Outlook's own VTIMEZONE for US Pacific time, under a custom name.
const customPacific = '''
BEGIN:VCALENDAR
BEGIN:VTIMEZONE
TZID:Customized Time Zone
BEGIN:STANDARD
DTSTART:16010101T020000
TZOFFSETFROM:-0700
TZOFFSETTO:-0800
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T020000
TZOFFSETFROM:-0800
TZOFFSETTO:-0700
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VTIMEZONE
TZID:Fixed Plus Three
BEGIN:STANDARD
DTSTART:16010101T000000
TZOFFSETFROM:+0300
TZOFFSETTO:+0300
END:STANDARD
END:VTIMEZONE
BEGIN:VTIMEZONE
TZID:Broken Zone
END:VTIMEZONE
END:VCALENDAR
''';

void main() {
  ensureTimeZonesLoaded(); // group bodies below call tz.getLocation

  test('reloads the full database if other code loaded the smaller one', () {
    small_db.initializeTimeZones();
    expect(tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta'), isFalse);
    ensureTimeZonesLoaded();
    expect(tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta'), isTrue);
  });

  group('IanaZone', () {
    final la = IanaZone(tz.getLocation('America/Los_Angeles'));

    test('converts wall time to UTC on both sides of a DST change', () {
      expect(
        la.wallToUtc(DateTime.utc(2026, 10, 26, 9)),
        DateTime.utc(2026, 10, 26, 16),
      );
      expect(
        la.wallToUtc(DateTime.utc(2026, 11, 2, 9)),
        DateTime.utc(2026, 11, 2, 17),
      );
    });

    test('a wall time in the spring-forward gap moves forward', () {
      expect(
        la.wallToUtc(DateTime.utc(2026, 3, 8, 2, 30)),
        DateTime.utc(2026, 3, 8, 10, 30),
      );
    });

    test('converts UTC back to wall time', () {
      expect(
        la.utcToWall(DateTime.utc(2026, 11, 2, 17)),
        DateTime.utc(2026, 11, 2, 9),
      );
    });
  });

  group('VtimezoneZone', () {
    final cal = parseCalendar(customPacific);
    Component zoneNamed(String id) =>
        cal.children.firstWhere((c) => c.first('TZID')!.value == id);

    test('computes offsets from STANDARD/DAYLIGHT rules', () {
      final zone = VtimezoneZone.fromComponent(
        zoneNamed('Customized Time Zone'),
      );
      expect(
        zone.wallToUtc(DateTime.utc(2026, 10, 13, 9)),
        DateTime.utc(2026, 10, 13, 16),
      );
      expect(
        zone.wallToUtc(DateTime.utc(2026, 11, 10, 9)),
        DateTime.utc(2026, 11, 10, 17),
      );
      expect(
        zone.wallToUtc(DateTime.utc(2027, 1, 15, 9)),
        DateTime.utc(2027, 1, 15, 17),
      );
      expect(
        zone.utcToWall(DateTime.utc(2026, 7, 1, 16)),
        DateTime.utc(2026, 7, 1, 9),
      );
    });

    test('a single STANDARD block without RRULE is a fixed offset', () {
      final zone = VtimezoneZone.fromComponent(zoneNamed('Fixed Plus Three'));
      expect(
        zone.wallToUtc(DateTime.utc(2026, 10, 13, 9)),
        DateTime.utc(2026, 10, 13, 6),
      );
    });

    test('a VTIMEZONE with no blocks is rejected', () {
      expect(
        () => VtimezoneZone.fromComponent(zoneNamed('Broken Zone')),
        throwsFormatException,
      );
    });

    test('parseUtcOffset reads signed hours, minutes and seconds', () {
      expect(parseUtcOffset('+0200'), const Duration(hours: 2));
      expect(parseUtcOffset('-0730'), -const Duration(hours: 7, minutes: 30));
      expect(
        parseUtcOffset('+053045'),
        const Duration(hours: 5, minutes: 30, seconds: 45),
      );
      expect(() => parseUtcOffset('2'), throwsFormatException);
    });
  });

  group('ZoneResolver', () {
    final cal = parseCalendar(customPacific);
    ZoneResolver resolver() => ZoneResolver(
      deviceZone: 'Africa/Johannesburg',
      vtimezones: {for (final c in cal.children) c.first('TZID')!.value: c},
    );
    final wall = DateTime.utc(2026, 10, 13, 10);

    DateTime utcFor(ResolvedZone r) => r.zone.wallToUtc(wall);

    test('1. Windows name → IANA, no warning', () {
      final r = resolver().resolve('W. Europe Standard Time');
      expect(r.warning, isNull);
      expect(utcFor(r), DateTime.utc(2026, 10, 13, 8));
    });

    test('2. IANA name used directly, no warning', () {
      final r = resolver().resolve('Europe/London');
      expect(r.warning, isNull);
      expect(utcFor(r), DateTime.utc(2026, 10, 13, 9));
    });

    test('3. otherwise the feed VTIMEZONE, with tzFromVtimezone', () {
      final r = resolver().resolve('Customized Time Zone');
      expect(r.warning, IcsWarning.tzFromVtimezone);
      expect(utcFor(r), DateTime.utc(2026, 10, 13, 17));
    });

    test('4. otherwise the device zone, with tzFromDevice', () {
      for (final id in ['Mars Standard Time', 'Broken Zone']) {
        final r = resolver().resolve(id);
        expect(r.warning, IcsWarning.tzFromDevice, reason: id);
        expect(utcFor(r), DateTime.utc(2026, 10, 13, 8), reason: id);
      }
    });

    test('UTC, floating and DATE values', () {
      final z = resolver();
      final utc = z.forTime(parseIcsTime('20261013T100000Z'));
      expect(
        (utcFor(utc), utc.warning),
        (DateTime.utc(2026, 10, 13, 10), null),
      );
      final floating = z.forTime(parseIcsTime('20261013T100000'));
      expect(
        (utcFor(floating), floating.warning),
        (DateTime.utc(2026, 10, 13, 8), null),
      );
      final date = z.forTime(parseIcsTime('20261013'));
      expect(date.zone, same(z.device));
      expect(date.warning, isNull);
    });

    test('rejects a device zone that is not an IANA name', () {
      expect(
        () => ZoneResolver(deviceZone: 'SAST', vtimezones: const {}),
        throwsArgumentError,
      );
    });
  });
}
