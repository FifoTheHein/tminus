import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException, SocketException, TlsException;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:ics_core/ics_core.dart';

import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import 'calendar_source.dart';
import 'feed_body_cache.dart';
import 'occurrence_mapping.dart';
import 'source_secrets.dart';

/// A published ICS feed (spec §5): conditional GET with a 60 s timeout, the
/// link read from secure storage, and every failure mapped to the spec §9
/// table. Messages never contain the link, and a failure is logged by its type
/// and OS error number, never by its text.
class IcsFeedSource implements CalendarSource {
  IcsFeedSource({
    required this.config,
    required this.previous,
    required this.client,
    required this.secrets,
    required this.bodies,
    required this.deviceZone,
    this.timeout = const Duration(seconds: 60),
  });

  final SourceConfig config;

  /// The stored sync state; supplies the conditional-GET validators.
  final SourceSyncState? previous;

  /// IANA name of the device zone, for floating and all-day times.
  final String deviceZone;
  final Duration timeout;
  final http.Client client;
  final SourceSecrets secrets;
  final FeedBodyCache bodies;

  @override
  String get id => config.id;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    final url = await _readLink();
    if (url == null) {
      return const SourceFailed(
        SyncOutcome.linkMissing,
        'The saved calendar link is missing. Add the link again.',
      );
    }
    // Uri.parse would throw a FormatException that quotes the whole link.
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return const SourceFailed(
        SyncOutcome.linkMissing,
        'The saved calendar link is not valid. Add the link again.',
      );
    }

    final etag = previous?.httpEtag;
    final lastModified = previous?.httpLastModified;
    final cached = etag != null || lastModified != null
        ? await bodies.read(id)
        : null;

    final http.Response response;
    try {
      response = await _get(uri, cached == null ? null : (etag, lastModified));
    } on TimeoutException catch (e) {
      _logFailure(e);
      return SourceFailed(
        SyncOutcome.networkError,
        'The calendar server did not answer within ${timeout.inSeconds} s.',
      );
    } on http.ClientException catch (e) {
      _logFailure(e);
      return const SourceFailed(
        SyncOutcome.networkError,
        'Could not reach the calendar server.',
      );
    } on IOException catch (e) {
      _logFailure(e);
      return const SourceFailed(
        SyncOutcome.networkError,
        'Could not reach the calendar server.',
      );
    } on ArgumentError catch (e) {
      // dart:io refuses a link with no host or a scheme other than http(s),
      // and its message quotes the link.
      _logFailure(e);
      return const SourceFailed(
        SyncOutcome.linkMissing,
        'The saved calendar link is not valid. Add the link again.',
      );
    }

    final status = response.statusCode;
    if (status == 200) {
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final result = _expand(body, window);
      if (result is SourceFetched) {
        await bodies.write(id, body);
        return SourceFetched(
          result.occurrences,
          issues: result.issues,
          httpEtag: response.headers['etag'],
          httpLastModified: response.headers['last-modified'],
        );
      }
      return result;
    }
    if (status == 304 && cached != null) {
      final result = _expand(cached, window);
      if (result is SourceFetched) {
        return SourceFetched(
          result.occurrences,
          issues: result.issues,
          notModified: true,
          httpEtag: response.headers['etag'] ?? etag,
          httpLastModified: response.headers['last-modified'] ?? lastModified,
        );
      }
      return result;
    }
    return SourceFailed(_outcomeFor(status), _messageFor(status));
  }

  /// The saved link, or null when there is none or the secure store cannot be
  /// read (a Keystore failure, or encrypted preferences restored by Android
  /// auto-backup). The error is dropped on purpose: its text may quote the
  /// link, and a source never throws.
  Future<String?> _readLink() async {
    final key = config.secureStorageKey;
    if (key == null) return null;
    try {
      return await secrets.readUrl(key);
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> _get(Uri uri, (String?, String?)? validators) async {
    final request = http.Request('GET', uri);
    request.headers['Accept'] = 'text/calendar, */*;q=0.5';
    if (validators != null) {
      final (etag, lastModified) = validators;
      if (etag != null) request.headers['If-None-Match'] = etag;
      if (lastModified != null) {
        request.headers['If-Modified-Since'] = lastModified;
      }
    }
    Future<http.Response> send() async =>
        http.Response.fromStream(await client.send(request));
    return send().timeout(timeout);
  }

  SourceResult _expand(String body, FetchWindow window) {
    try {
      final result = expandIcs(
        body,
        windowStartUtc: window.startUtc,
        windowEndUtc: window.endUtc,
        deviceZone: deviceZone,
      );
      return SourceFetched(
        [for (final o in result.occurrences) occurrenceFromIcs(o, config)],
        issues: [for (final i in result.issues) 'line ${i.line}: ${i.message}'],
      );
    } on IcsFormatException catch (e) {
      return SourceFailed(
        SyncOutcome.parseError,
        'The feed is not a calendar: ${e.message}',
      );
    } catch (_) {
      return const SourceFailed(
        SyncOutcome.parseError,
        'The feed could not be read.',
      );
    }
  }

  static SyncOutcome _outcomeFor(int status) => switch (status) {
    408 || 429 || >= 500 => SyncOutcome.serverError,
    >= 400 && < 500 => SyncOutcome.httpError,
    _ => SyncOutcome.otherError,
  };

  static String _messageFor(int status) => switch (status) {
    408 ||
    429 ||
    >= 500 => 'The calendar server had a problem (HTTP $status). Retrying.',
    401 || 403 =>
      'Link no longer works (HTTP $status). It may have been reset in Outlook.',
    404 || 410 =>
      'Link no longer works (HTTP $status). The calendar may have been unpublished.',
    >= 400 && < 500 => 'The calendar server refused the link (HTTP $status).',
    _ => 'Unexpected answer from the calendar server (HTTP $status).',
  };

  /// Logs that a fetch failed and what failed, never why: the type of the
  /// failure and, when it carries one, the number of its operating system
  /// error, as in `HandshakeException, os error 1`. A failure's message, its
  /// uri, its host and its address can each give the link away, so none of
  /// them is read.
  static void _logFailure(Object error) {
    final os = switch (error) {
      SocketException(:final osError) => osError,
      TlsException(:final osError) => osError,
      _ => null,
    };
    final code = os == null ? '' : ', os error ${os.errorCode}';
    debugPrint('Fetching a calendar failed (${error.runtimeType}$code)');
  }
}
