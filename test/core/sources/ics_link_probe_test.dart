import 'package:flutter/foundation.dart' show debugPrint;
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

/// Runs [body] with everything the app logs collected into the list it is
/// given. The log hook goes back before the test body ends, not in a
/// tear-down: the framework checks that it is back before tear-downs run.
Future<void> _logging(Future<void> Function(List<String> logged) body) async {
  final logged = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => logged.add(message ?? '');
  try {
    await body(logged);
  } finally {
    debugPrint = original;
  }
}

void main() {
  setUp(initZones);
  final now = DateTime.utc(2026, 10, 6, 6);
  const secret =
      'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';

  /// What the failures below carry in their messages. None of it may be logged.
  const leaks = ['LEAK', 's3cr3t', 'office365', 'https'];

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

  test('a failure nothing else catches is logged by its type only', () async {
    // One Error and one Exception, as above. The FormatException carries the
    // link as its source, which its text then repeats.
    for (final (thrown, line) in <(Object, String)>[
      (StateError('LEAK $secret'), 'Checking a link failed (StateError)'),
      (
        FormatException('LEAK $secret', secret),
        'Checking a link failed (FormatException)',
      ),
    ]) {
      await _logging((logged) async {
        await probe(MockClient((_) async => throw thrown)).check(secret);
        expect(logged, [line]);
        for (final leak in leaks) {
          expect(logged.join('\n'), isNot(contains(leak)), reason: leak);
        }
      });
    }
  });

  test('a server that cannot be reached is logged by what failed', () async {
    await _logging((logged) async {
      final r = await probe(
        MockClient(
          (req) async => throw http.ClientException('LEAK $secret', req.url),
        ),
      ).check(secret);
      expect(
        (r as ProbeFailed).message,
        'Could not reach the calendar server.',
      );
      expect(logged, ['Fetching a calendar failed (ClientException)']);
      for (final leak in leaks) {
        expect(logged.join('\n'), isNot(contains(leak)), reason: leak);
      }
    });
  });

  test('the probe waits 60 s for the server unless told otherwise', () {
    final defaulted = probe(MockClient((_) async => http.Response('', 200)));
    expect(defaulted.timeout, const Duration(seconds: 60));
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
