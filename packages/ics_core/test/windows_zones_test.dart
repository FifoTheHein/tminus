import 'package:ics_core/src/zones/windows_zones.g.dart';
import 'package:ics_core/src/zones/zone_resolver.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../tool/gen_windows_zones.dart';

void main() {
  group('generator', () {
    const sample = '''
<supplementalData>
  <windowsZones>
    <mapTimezones otherVersion="7e11800" typeVersion="2021a">
      <mapZone other="Pacific Standard Time" territory="001" type="America/Los_Angeles"/>
      <mapZone other="Pacific Standard Time" territory="CA" type="America/Vancouver"/>
      <mapZone other="Pacific Standard Time" territory="US" type="America/Los_Angeles"/>
      <mapZone other="South Africa Standard Time" territory="001" type="Africa/Johannesburg"/>
      <mapZone type="Etc/UTC" territory="001" other="UTC"/>
    </mapTimezones>
  </windowsZones>
</supplementalData>
''';

    test('keeps only territory 001 rows, in any attribute order', () {
      expect(parseWindowsZones(sample), {
        'Pacific Standard Time': 'America/Los_Angeles',
        'South Africa Standard Time': 'Africa/Johannesburg',
        'UTC': 'Etc/UTC',
      });
    });

    test('renders a sorted const map with its source', () {
      final source = renderWindowsZones({
        'b': 'Etc/B',
        'a': 'Etc/A',
      }, source: 'https://example.com/x.xml');
      expect(source, contains('// Source: https://example.com/x.xml'));
      expect(source, contains('const Map<String, String> windowsToIana = {'));
      expect(source.indexOf('"a"'), lessThan(source.indexOf('"b"')));
    });
  });

  group('committed table', () {
    setUpAll(ensureTimeZonesLoaded);

    test('maps the zones T-Minus users meet most', () {
      expect(windowsToIana['Pacific Standard Time'], 'America/Los_Angeles');
      expect(
        windowsToIana['South Africa Standard Time'],
        'Africa/Johannesburg',
      );
      expect(windowsToIana['W. Europe Standard Time'], 'Europe/Berlin');
      expect(windowsToIana['GMT Standard Time'], 'Europe/London');
      expect(windowsToIana['UTC'], 'Etc/UTC');
    });

    test('is the full CLDR table', () {
      expect(windowsToIana.length, greaterThan(100));
    });

    test('every IANA target exists in the bundled timezone database', () {
      final missing = [
        for (final iana in windowsToIana.values.toSet())
          if (!tz.timeZoneDatabase.locations.containsKey(iana)) iana,
      ];
      expect(missing, isEmpty);
    });
  });
}
