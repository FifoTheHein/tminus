import 'package:http/http.dart' as http;

import '../model/source_config.dart';
import '../rules/rules_engine.dart';
import 'calendar_source.dart';
import 'feed_body_cache.dart';
import 'ics_feed_source.dart';
import 'ics_url.dart';
import 'source_secrets.dart';

/// What [IcsLinkProbe.check] makes of a pasted link.
sealed class ProbeResult {
  const ProbeResult();
}

class ProbeFound extends ProbeResult {
  const ProbeFound({
    required this.url,
    required this.insecure,
    required this.eventsThisWeek,
  });

  /// The link to save (trimmed, `webcal://` → `https://`). Keep it in memory
  /// only, and hand it to `SourceAdmin`.
  final String url;

  /// Plain `http://`: the screen shows the not-encrypted warning.
  final bool insecure;

  /// Occurrences starting between now and 7 days from now.
  final int eventsThisWeek;
}

class ProbeFailed extends ProbeResult {
  const ProbeFailed(this.message);

  /// Fixed text, at most with an HTTP status or the timeout. Never the link.
  final String message;
}

/// Onboarding's and Add source's "Found 23 events this week": one real fetch
/// through [IcsFeedSource], with the link held in memory. Nothing is stored,
/// posted or logged.
class IcsLinkProbe {
  IcsLinkProbe({
    required this.client,
    required this.deviceZone,
    UtcClock? clock,
    this.timeout = const Duration(seconds: 20),
  }) : clock = clock ?? systemUtcNow;

  final http.Client client;

  /// IANA name of the device zone, for floating and all-day times.
  final String Function() deviceZone;
  final UtcClock clock;
  final Duration timeout;

  /// Never throws: whatever goes wrong comes back as a [ProbeFailed].
  Future<ProbeResult> check(String input) async {
    try {
      return await _check(input);
    } catch (_) {
      // A thrown error can quote the link, and nothing above the screen would
      // catch it. It is dropped unread: fixed text, nothing logged.
      return const ProbeFailed('Could not check the link.');
    }
  }

  Future<ProbeResult> _check(String input) async {
    final checked = IcsUrl.check(input);
    if (checked is IcsUrlRejected) return ProbeFailed(checked.message);
    final link = checked as IcsUrlAccepted;
    final now = clock();
    final source = IcsFeedSource(
      config: const SourceConfig(
        id: 'probe',
        name: 'probe',
        color: 0,
        kind: SourceKind.ics,
        secureStorageKey: 'probe',
      ),
      previous: null,
      client: client,
      secrets: _OneLink(link.url),
      bodies: _NoBodies(),
      deviceZone: deviceZone(),
      timeout: timeout,
    );
    final week = now.add(FetchWindow.lookAhead);
    return switch (await source.fetch(FetchWindow.around(now))) {
      SourceFetched(:final occurrences) => ProbeFound(
        url: link.url,
        insecure: link.insecure,
        eventsThisWeek: occurrences
            .where(
              (o) => !o.startUtc.isBefore(now) && o.startUtc.isBefore(week),
            )
            .length,
      ),
      SourceFailed(:final message) => ProbeFailed(message),
    };
  }
}

/// Serves one link from memory; the probe never touches secure storage.
class _OneLink extends SourceSecrets {
  _OneLink(this._url);
  final String _url;

  @override
  Future<String?> readUrl(String key) async => _url;

  @override
  Future<void> writeUrl(String key, String url) async =>
      throw UnsupportedError('The probe stores nothing');

  @override
  Future<void> delete(String key) async {}
}

/// No stored body: a probe always downloads, and keeps nothing on disk.
class _NoBodies extends FeedBodyCache {
  _NoBodies() : super(() => throw UnsupportedError('The probe stores nothing'));

  @override
  Future<String?> read(String sourceId) async => null;

  @override
  Future<void> write(String sourceId, String body) async {}

  @override
  Future<void> delete(String sourceId) async {}
}
