import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/core/sources/ics_link_probe.dart';

import '../fixtures.dart';

const _feed = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:a
DTSTART:20261006T080000Z
DTEND:20261006T083000Z
SUMMARY:Sprint planning
END:VEVENT
BEGIN:VEVENT
UID:b
DTSTART:20261020T080000Z
DTEND:20261020T083000Z
SUMMARY:Later
END:VEVENT
END:VCALENDAR
''';

/// Read with the probe's clock at 06:00Z: one event began half an hour ago,
/// one begins right now, one begins two hours from now.
const _feedAroundNow = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:under-way
DTSTART:20261006T053000Z
DTEND:20261006T063000Z
SUMMARY:Already started
END:VEVENT
BEGIN:VEVENT
UID:starts-now
DTSTART:20261006T060000Z
DTEND:20261006T063000Z
SUMMARY:Starts now
END:VEVENT
BEGIN:VEVENT
UID:starts-later
DTSTART:20261006T080000Z
DTEND:20261006T083000Z
SUMMARY:Starts later
END:VEVENT
END:VCALENDAR
''';

void main() {
  setUp(initZones);
  final now = DateTime.utc(2026, 10, 6, 6);
  const secret =
      'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';

  IcsLinkProbe probe(http.Client client) => IcsLinkProbe(
    client: client,
    deviceZone: () => 'Africa/Johannesburg',
    clock: () => now,
  );

  test('a working link counts the events of the next 7 days', () async {
    final r = await probe(MockClient((_) async => http.Response(_feed, 200)))
        .check(' $secret ');
    expect(r, isA<ProbeFound>());
    r as ProbeFound;
    expect((r.eventsThisWeek, r.insecure, r.url), (1, false, secret));
  });

  test('webcal is fetched over https and http is flagged insecure', () async {
    final seen = <Uri>[];
    final client = MockClient((req) async {
      seen.add(req.url);
      return http.Response(_feed, 200);
    });
    await probe(client).check('webcal://example.com/c.ics');
    expect(seen.single.scheme, 'https');
    final r =
        await probe(client).check('http://example.com/c.ics') as ProbeFound;
    expect(r.insecure, isTrue);
  });

  test('a rejected link is not fetched', () async {
    var fetched = false;
    final r = await probe(
      MockClient((_) async {
        fetched = true;
        return http.Response('', 200);
      }),
    ).check('https://outlook.office365.com/owa/calendar/x/calendar.html');
    expect(fetched, isFalse);
    expect((r as ProbeFailed).message, contains('.ics'));
  });

  test('a failing probe never repeats the link', () async {
    for (final client in [
      MockClient((_) async => http.Response('', 404)),
      MockClient((_) async => throw http.ClientException('Failed: $secret')),
      MockClient((_) async => http.Response('not a calendar', 200)),
    ]) {
      final r = await probe(client).check(secret) as ProbeFailed;
      expect(r.message, isNot(contains('s3cr3t')));
      expect(r.message, isNot(contains('outlook.office365.com')));
    }
  });

  test('a client that throws anything else gives fixed text', () async {
    // One Error and one Exception, so a catch narrowed to either lets one out.
    for (final thrown in <Object>[
      StateError('boom $secret'),
      FormatException('boom $secret'),
    ]) {
      final r = await probe(MockClient((_) async => throw thrown))
          .check(secret);
      expect(r, isA<ProbeFailed>());
      final message = (r as ProbeFailed).message;
      expect(message, 'Could not check the link.');
      expect(message, isNot(contains('s3cr3t')));
      expect(message, isNot(contains('outlook.office365.com')));
    }
  });

  test(
    'an event already under way is not counted, one starting now is',
    () async {
      final r = await probe(
        MockClient((_) async => http.Response(_feedAroundNow, 200)),
      ).check(secret);
      expect(r, isA<ProbeFound>());
      expect((r as ProbeFound).eventsThisWeek, 2);
    },
  );
}
