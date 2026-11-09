import 'dart:async';
import 'dart:io'
    show HandshakeException, InternetAddress, OSError, SocketException;
import 'dart:math' show min;

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

/// What the http package throws when the socket under a request fails: a
/// ClientException that is also a SocketException, so a caller can catch
/// either. The package keeps the class private.
class _ClientSocketException extends http.ClientException
    implements SocketException {
  _ClientSocketException(super.message, Uri super.uri, {this.osError});

  @override
  final OSError? osError;

  @override
  InternetAddress? get address => null;

  @override
  int? get port => null;
}

/// How a client answers one request.
typedef _Answer = Future<http.Response> Function(http.Request request);

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

  /// A client that answers its nth request with the nth of [answers] (the last
  /// answer again to any request after that), and the requests it was asked, so
  /// that a request too many shows in the list.
  (http.Client, List<http.Request>) scripted(List<_Answer> answers) {
    final asked = <http.Request>[];
    final client = MockClient((request) {
      asked.add(request);
      return answers[min(asked.length, answers.length) - 1](request);
    });
    return (client, asked);
  }

  /// The feed answers, with one event in the next 7 days.
  Future<http.Response> feed(http.Request request) async =>
      http.Response(_feed, 200);

  _Answer status(int code) =>
      (request) async => http.Response('', code);

  /// The client throws what [thrown] builds from the request's url.
  _Answer throwing(Object Function(Uri url) thrown) =>
      (request) async => throw thrown(request.url);

  /// What the http package throws when dart:io reports a failure with [text]: a
  /// plain ClientException that keeps the text, here followed by a link.
  Object Function(Uri url) clientFailure(String text) =>
      (url) => http.ClientException('$text LEAK $secret', url);

  /// The line the log gets for a failed attempt that [what] names. The fetch is
  /// timed by a real stopwatch here, so the seconds can vary.
  Matcher failedAttempt(String what) =>
      matches('^Fetching a calendar failed \\($what, after \\d+ s\\)\$');

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
      // The fetch is timed by a real stopwatch here, so the seconds can vary.
      expect(logged, [
        matches(
          r'^Fetching a calendar failed \(ClientException: other, after \d+ s\)$',
        ),
      ]);
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

  group('a connection that was lost is tried once more', () {
    test(
      'a feed cut short is fetched again and the second answer is shown',
      () async {
        await _logging((logged) async {
          final (client, asked) = scripted([
            throwing(clientFailure('Connection closed while receiving data')),
            feed,
          ]);

          final r = await probe(client).check(secret);

          expect(r, isA<ProbeFound>());
          r as ProbeFound;
          expect((r.eventsThisWeek, r.insecure, r.url), (1, false, secret));
          expect(asked, hasLength(2));
          expect(asked.map((q) => q.url.toString()), [secret, secret]);
          // The first attempt logged its failure, and the retry adds nothing.
          expect(logged, [
            failedAttempt('ClientException: closed while receiving'),
          ]);
          for (final leak in leaks) {
            expect(logged.join('\n'), isNot(contains(leak)), reason: leak);
          }
        });
      },
    );

    test(
      'a connection closed before the headers, or a socket failure, is tried '
      'again too',
      () async {
        for (final (name, lost) in <(String, _Answer)>[
          (
            'closed before the headers',
            throwing(
              clientFailure(
                'Connection closed before full header was received',
              ),
            ),
          ),
          (
            'reset by the peer',
            throwing(
              (_) => SocketException(
                'LEAK $secret',
                osError: const OSError('LEAK', 104),
              ),
            ),
          ),
          (
            'reset, as the http package passes it on',
            throwing(
              (url) => _ClientSocketException(
                'LEAK $secret',
                url,
                osError: const OSError('LEAK', 104),
              ),
            ),
          ),
        ]) {
          final (client, asked) = scripted([lost, feed]);

          final r = await probe(client).check(secret);

          expect(r, isA<ProbeFound>(), reason: name);
          expect(asked, hasLength(2), reason: name);
        }
      },
    );

    test(
      'a connection lost twice in a row shows the failure after two requests',
      () async {
        await _logging((logged) async {
          final (client, asked) = scripted([
            throwing(clientFailure('Connection closed while receiving data')),
            throwing(
              clientFailure(
                'Connection closed before full header was received',
              ),
            ),
          ]);

          final r = await probe(client).check(secret);

          expect(
            (r as ProbeFailed).message,
            'Could not reach the calendar server.',
          );
          expect(asked, hasLength(2));
          // Each attempt logged its own failure, in order.
          expect(logged, [
            failedAttempt('ClientException: closed while receiving'),
            failedAttempt('ClientException: closed before headers'),
          ]);
          for (final leak in leaks) {
            expect(logged.join('\n'), isNot(contains(leak)), reason: leak);
          }
        });
      },
    );

    test(
      'the second answer is shown even when it is a failure of another kind',
      () async {
        final (client, asked) = scripted([
          throwing(clientFailure('Connection closed while receiving data')),
          status(404),
        ]);

        final r = await probe(client).check(secret);

        expect((r as ProbeFailed).message, contains('HTTP 404'));
        expect(asked, hasLength(2));
      },
    );
  });

  group('a failure that another try would not mend is not tried again', () {
    test('a timeout would only double the wait', () async {
      final never = Completer<http.Response>();
      final (client, asked) = scripted([(request) => never.future]);

      final r = await IcsLinkProbe(
        client: client,
        deviceZone: () => 'Africa/Johannesburg',
        clock: () => now,
        timeout: const Duration(milliseconds: 20),
      ).check(secret);

      expect((r as ProbeFailed).message, contains('did not answer'));
      expect(asked, hasLength(1));
    });

    test('an HTTP 404 or 500 is answered once', () async {
      for (final code in [404, 500]) {
        final (client, asked) = scripted([status(code)]);

        final r = await probe(client).check(secret);

        expect((r as ProbeFailed).message, contains('HTTP $code'));
        expect(asked, hasLength(1), reason: '$code');
      }
    });

    test('a feed that is not a calendar is fetched once', () async {
      final (client, asked) = scripted([
        (request) async => http.Response('not a calendar', 200),
      ]);

      final r = await probe(client).check(secret);

      expect(
        (r as ProbeFailed).message,
        startsWith('The feed is not a calendar'),
      );
      expect(asked, hasLength(1));
    });

    test('a failure that is not a lost connection is tried once', () async {
      for (final (name, failure) in <(String, _Answer)>[
        ('a text that is not known', throwing(clientFailure('Something else'))),
        (
          'a body that does not fit its length',
          throwing(clientFailure('Content size below specified contentLength')),
        ),
        ('a redirect loop', throwing(clientFailure('Redirect loop detected'))),
        (
          'a TLS failure',
          throwing(
            (_) => HandshakeException('LEAK $secret', const OSError('LEAK', 1)),
          ),
        ),
        (
          'a link that dart:io refuses',
          throwing((_) => ArgumentError.value(secret, 'uri', 'LEAK')),
        ),
      ]) {
        final (client, asked) = scripted([failure]);

        final r = await probe(client).check(secret);

        expect(r, isA<ProbeFailed>(), reason: name);
        expect(asked, hasLength(1), reason: name);
      }
    });
  });
}
