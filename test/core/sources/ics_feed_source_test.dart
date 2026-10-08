import 'dart:async';
import 'dart:io';

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
    Duration timeout = const Duration(seconds: 20),
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
