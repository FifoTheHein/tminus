import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/sources/ics_feed_source.dart';
import 'package:tminus/core/sources/source_secrets.dart';

const _secretUrl =
    'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';

/// One meeting on 6 Oct 2026, 08:00–08:30 UTC.
const _feed =
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:standup\r\n'
    'DTSTART:20261006T080000Z\r\n'
    'DTEND:20261006T083000Z\r\n'
    'SUMMARY:Daily standup\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

/// The same feed with the meeting moved to 09:00.
final _movedFeed = _feed
    .replaceFirst('20261006T080000Z', '20261006T090000Z')
    .replaceFirst('20261006T083000Z', '20261006T093000Z');

/// A secure store that cannot be read, as after a Keystore failure or an
/// Android auto-backup restore of the encrypted preferences. The platform
/// error names the link, to prove the failure message never repeats it.
class _UnreadableSecrets extends SourceSecrets {
  @override
  Future<String?> readUrl(String key) async => throw PlatformException(
    code: 'keystore',
    message: 'Could not decrypt the value stored for $_secretUrl',
  );
}

/// What the http package throws when the socket under a request fails: a
/// ClientException that is also a SocketException, so a caller can catch
/// either. The package keeps the class private.
class _ClientSocketException extends http.ClientException
    implements SocketException {
  _ClientSocketException(
    super.message,
    Uri super.uri, {
    this.osError,
    this.address,
    this.port,
  });

  @override
  final OSError? osError;

  @override
  final InternetAddress? address;

  @override
  final int? port;
}

/// What the failures below carry in their message, uri, host or address. None
/// of it may reach the log.
const _leak = 'LEAK https://secret.example/x.ics';
const _hostAddress = '203.0.113.7';
const _leaks = ['LEAK', 'secret', 's3cr3t', 'office365', 'https', _hostAddress];

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
  const config = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.work',
  );
  final window = FetchWindow.around(DateTime.utc(2026, 10, 6, 7));
  late Directory dir;
  late FeedBodyCache bodies;
  late List<http.Request> requests;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'ics-url.work': _secretUrl});
    dir = await Directory.systemTemp.createTemp('feeds');
    bodies = FeedBodyCache(() async => dir);
    requests = [];
  });

  tearDown(() => dir.delete(recursive: true));

  IcsFeedSource source(
    Future<http.Response> Function(http.Request) handler, {
    SourceSyncState? previous,
    Duration timeout = const Duration(seconds: 60),
    SourceSecrets? secrets,
  }) => IcsFeedSource(
    config: config,
    previous: previous,
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    secrets: secrets ?? SourceSecrets(),
    bodies: bodies,
    deviceZone: 'Africa/Johannesburg',
    timeout: timeout,
  );

  SourceFailed failure(SourceResult r) {
    expect(r, isA<SourceFailed>());
    final f = r as SourceFailed;
    expect(f.message, isNot(contains('s3cr3t')));
    expect(f.message, isNot(contains('office365')));
    return f;
  }

  Future<SourceFailed> failWith(int status) async => failure(
    await source((_) async => http.Response('', status)).fetch(window),
  );

  /// Fetches while the client throws what [thrown] builds from the request's
  /// url, and checks that [line] is all that was logged and that nothing of
  /// the exception's message, uri, host or address is in it. Returns the
  /// failure the fetch reported.
  Future<SourceFailed> fetchLogging(
    Object Function(Uri url) thrown,
    String line,
  ) async {
    late SourceFailed failed;
    await _logging((logged) async {
      failed = failure(
        await source((r) async => throw thrown(r.url)).fetch(window),
      );
      expect(logged, [line]);
      for (final leak in _leaks) {
        expect(logged.join('\n'), isNot(contains(leak)), reason: leak);
      }
    });
    return failed;
  }

  test('a 200 is expanded, its validators kept and its body stored', () async {
    final r = await source(
      (_) async => http.Response(
        _feed,
        200,
        headers: {
          'etag': '"v1"',
          'last-modified': 'Mon, 05 Oct 2026 10:00:00 GMT',
        },
      ),
    ).fetch(window);

    expect(requests.single.url.toString(), _secretUrl);
    expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
    final fetched = r as SourceFetched;
    expect(fetched.notModified, isFalse);
    expect(fetched.httpEtag, '"v1"');
    expect(fetched.httpLastModified, 'Mon, 05 Oct 2026 10:00:00 GMT');
    expect(fetched.occurrences.single.title, 'Daily standup');
    expect(fetched.occurrences.single.sourceId, 'work');
    expect(fetched.occurrences.single.startUtc, DateTime.utc(2026, 10, 6, 8));
    expect(await bodies.read('work'), _feed);
  });

  test(
    'with stored validators and body, a 304 re-expands the stored body',
    () async {
      await bodies.write('work', _feed);
      final r = await source(
        (_) async => http.Response('', 304),
        previous: SourceSyncState(
          httpEtag: '"v1"',
          httpLastModified: 'Mon, 05 Oct 2026 10:00:00 GMT',
        ),
      ).fetch(window);

      expect(requests.single.headers['If-None-Match'], '"v1"');
      expect(
        requests.single.headers['If-Modified-Since'],
        'Mon, 05 Oct 2026 10:00:00 GMT',
      );
      final fetched = r as SourceFetched;
      expect(fetched.notModified, isTrue);
      expect(fetched.httpEtag, '"v1"');
      expect(fetched.httpLastModified, 'Mon, 05 Oct 2026 10:00:00 GMT');
      expect(fetched.occurrences.single.title, 'Daily standup');
    },
  );

  test('without a stored body the request is unconditional', () async {
    final r = await source(
      (_) async => http.Response(_movedFeed, 200),
      previous: SourceSyncState(httpEtag: '"v1"'),
    ).fetch(window);
    expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
    expect(
      (r as SourceFetched).occurrences.single.startUtc,
      DateTime.utc(2026, 10, 6, 9),
    );
  });

  test('a 304 to an unconditional request is unexpected', () async {
    expect((await failWith(304)).outcome, SyncOutcome.otherError);
  });

  test('5xx, 408 and 429 are temporary server errors', () async {
    for (final status in [500, 502, 503, 408, 429]) {
      final f = await failWith(status);
      expect(f.outcome, SyncOutcome.serverError, reason: '$status');
      expect(f.message, contains('HTTP $status'));
    }
  });

  test(
    '401, 403, 404, 410 and every other 4xx mean the link is broken',
    () async {
      for (final status in [401, 403, 404, 410, 400, 451]) {
        expect(
          (await failWith(status)).outcome,
          SyncOutcome.httpError,
          reason: '$status',
        );
      }
      expect(
        (await failWith(403)).message,
        'Link no longer works (HTTP 403). It may have been reset in Outlook.',
      );
    },
  );

  test('a network failure never repeats the link', () async {
    final client = failure(
      await source(
        (r) async => throw http.ClientException('Failed: $_secretUrl', r.url),
      ).fetch(window),
    );
    expect(client.outcome, SyncOutcome.networkError);
    final io = failure(
      await source(
        (_) async => throw const SocketException('Failed host lookup'),
      ).fetch(window),
    );
    expect(io.outcome, SyncOutcome.networkError);
  });

  test('a server that does not answer in time is a network error', () async {
    final never = Completer<http.Response>();
    final f = failure(
      await source(
        (_) => never.future,
        timeout: const Duration(milliseconds: 20),
      ).fetch(window),
    );
    expect(f.outcome, SyncOutcome.networkError);
    expect(f.message, contains('did not answer'));
  });

  test('the fetch timeout is 60 s unless a caller sets another', () {
    final defaulted = IcsFeedSource(
      config: config,
      previous: null,
      client: MockClient((_) async => http.Response(_feed, 200)),
      secrets: SourceSecrets(),
      bodies: bodies,
      deviceZone: 'Africa/Johannesburg',
    );
    expect(defaulted.timeout, const Duration(seconds: 60));
  });

  group('a failed fetch is logged by what failed, never by its text', () {
    test('a timeout is logged as a TimeoutException', () async {
      final f = await fetchLogging(
        (_) => TimeoutException(_leak, const Duration(seconds: 60)),
        'Fetching a calendar failed (TimeoutException)',
      );
      expect(f.outcome, SyncOutcome.networkError);
      expect(f.message, contains('did not answer'));
    });

    test('a client exception is logged as a ClientException', () async {
      final f = await fetchLogging(
        (url) => http.ClientException(_leak, url),
        'Fetching a calendar failed (ClientException)',
      );
      expect(f.outcome, SyncOutcome.networkError);
      expect(f.message, 'Could not reach the calendar server.');
    });

    test('a socket failure is logged with its OS error number', () async {
      final f = await fetchLogging(
        (_) => SocketException(
          _leak,
          osError: const OSError(_leak, 7),
          address: InternetAddress(_hostAddress),
          port: 443,
        ),
        'Fetching a calendar failed (SocketException, os error 7)',
      );
      expect(f.outcome, SyncOutcome.networkError);
      expect(f.message, 'Could not reach the calendar server.');
    });

    test('a TLS failure is logged with its OS error number', () async {
      final f = await fetchLogging(
        (_) => const HandshakeException(_leak, OSError(_leak, 1)),
        'Fetching a calendar failed (HandshakeException, os error 1)',
      );
      expect(f.outcome, SyncOutcome.networkError);
      expect(f.message, 'Could not reach the calendar server.');
    });

    test('a socket failure wrapped by the http package keeps its OS error '
        'number', () async {
      final f = await fetchLogging(
        (url) => _ClientSocketException(
          _leak,
          url,
          osError: const OSError(_leak, 7),
          address: InternetAddress(_hostAddress),
          port: 443,
        ),
        'Fetching a calendar failed (_ClientSocketException, os error 7)',
      );
      expect(f.outcome, SyncOutcome.networkError);
    });

    test('a failure without an OS error is logged by its type alone', () async {
      await fetchLogging(
        (url) => HttpException(_leak, uri: url),
        'Fetching a calendar failed (HttpException)',
      );
      await fetchLogging(
        (_) => SocketException(_leak, address: InternetAddress(_hostAddress)),
        'Fetching a calendar failed (SocketException)',
      );
      await fetchLogging(
        (_) => const HandshakeException(_leak),
        'Fetching a calendar failed (HandshakeException)',
      );
    });

    test('a link that dart:io refuses is logged as an ArgumentError', () async {
      final f = await fetchLogging(
        (_) => ArgumentError.value(_secretUrl, 'uri', _leak),
        'Fetching a calendar failed (ArgumentError)',
      );
      expect(f.outcome, SyncOutcome.linkMissing);
      expect(
        f.message,
        'The saved calendar link is not valid. Add the link again.',
      );
    });
  });

  test(
    'a body that is not a calendar is a parse error and is not stored',
    () async {
      await bodies.write('work', _feed);
      final f = failure(
        await source((_) async => http.Response('<html>Sign in</html>', 200))
            .fetch(window),
      );
      expect(f.outcome, SyncOutcome.parseError);
      expect(await bodies.read('work'), _feed);
    },
  );

  test('a link missing from secure storage fails without a request', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final f = failure(
      await source((_) async => http.Response(_feed, 200)).fetch(window),
    );
    expect(f.outcome, SyncOutcome.linkMissing);
    expect(requests, isEmpty);
  });

  test('an unreadable secure store is reported as a missing link', () async {
    final f = failure(
      await source(
        (_) async => http.Response(_feed, 200),
        secrets: _UnreadableSecrets(),
      ).fetch(window),
    );
    expect(f.outcome, SyncOutcome.linkMissing);
    expect(
      f.message,
      'The saved calendar link is missing. Add the link again.',
    );
    expect(requests, isEmpty);
  });

  test(
    'a malformed saved link fails as linkMissing without a request',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'ics-url.work': 'https://host:port/s3cr3t/calendar.ics',
      });
      final f = failure(
        await source((_) async => http.Response(_feed, 200)).fetch(window),
      );
      expect(f.outcome, SyncOutcome.linkMissing);
      expect(
        f.message,
        'The saved calendar link is not valid. Add the link again.',
      );
      expect(requests, isEmpty);
    },
  );
}
