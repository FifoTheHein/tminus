import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../model/source_config.dart';
import '../storage/settings_repository.dart';
import '../storage/source_repository.dart';
import '../sync/sync_platform.dart';
import '../sync/sync_service.dart' show SyncService;
import 'device_calendar_api.dart';
import 'feed_body_cache.dart';
import 'ics_url.dart';
import 'source_secrets.dart';

/// [IcsUrl.check] rejected a link.
class IcsUrlException implements Exception {
  const IcsUrlException(this.message);
  final String message;

  @override
  String toString() => 'IcsUrlException: $message';
}

/// Adds, re-links and removes sources (Plan 5's Sources tab and onboarding
/// call this, then run a sync). The ICS link goes to secure storage, never to
/// drift (spec §10).
class SourceAdmin {
  SourceAdmin({
    required this.sources,
    required this.secrets,
    required this.bodies,
    required this.platform,
    required this.settings,
    Random? random,
  }) : _random = random ?? Random.secure();

  final SourceRepository sources;
  final SourceSecrets secrets;
  final FeedBodyCache bodies;

  /// Withdraws a removed source's notices (decision 27).
  final SyncPlatform platform;

  /// Holds the markers the sync service keeps per source: when its server
  /// errors began and which Feed broken notice is up. A new link resets the
  /// first; a removal clears both.
  final SettingsRepository settings;
  final Random _random;

  /// Throws [IcsUrlException] for a link [IcsUrl.check] rejects. Returns the
  /// source and whether the link is plain `http://` (Plan 5 warns).
  Future<({SourceConfig source, bool insecure})> addIcsSource({
    required String name,
    required int color,
    required String url,
    String? defaultProfileId,
  }) async {
    final link = _accepted(url);
    final id = _newId('ics');
    final key = SourceSecrets.keyFor(id);
    await secrets.writeUrl(key, link.url);
    final source = SourceConfig(
      id: id,
      name: name,
      color: color,
      kind: SourceKind.ics,
      secureStorageKey: key,
      defaultProfileId: defaultProfileId,
    );
    await sources.save(source);
    return (source: source, insecure: link.insecure);
  }

  /// A new link for an existing ICS source (e.g. after it was reset in
  /// Outlook). Forgets the old conditional-GET validators and stored body, and
  /// restarts the 24 h server-error escalation. Returns whether the link is
  /// plain `http://`.
  Future<bool> updateIcsUrl(String sourceId, String url) async {
    final link = _accepted(url);
    final source = await sources.byId(sourceId);
    final key = source?.secureStorageKey;
    if (source == null || source.kind != SourceKind.ics || key == null) {
      throw ArgumentError.value(sourceId, 'sourceId', 'not an ICS source');
    }
    await secrets.writeUrl(key, link.url);
    final state = await sources.syncState(sourceId);
    await sources.updateSyncState(
      sourceId,
      SourceSyncState(
        lastAttemptUtc: state?.lastAttemptUtc,
        lastSuccessUtc: state?.lastSuccessUtc,
        lastError: state?.lastError,
        emptyStreak: state?.emptyStreak ?? 0,
      ),
    );
    await bodies.delete(sourceId);
    // The new link starts a new run of server errors: the old link's must not
    // count toward reporting it broken.
    await _clearSetting(SyncService.serverErrorSinceKey(sourceId));
    return link.insecure;
  }

  /// A phone calendar as a source. Name and colour default to the
  /// calendar's own.
  Future<SourceConfig> addDeviceSource({
    required DeviceCalendar calendar,
    String? name,
    int? color,
    String? defaultProfileId,
  }) async {
    final source = SourceConfig(
      id: _newId('device'),
      name: name ?? calendar.name,
      color: color ?? calendar.color,
      kind: SourceKind.device,
      deviceCalendarId: calendar.id,
      defaultProfileId: defaultProfileId,
    );
    await sources.save(source);
    return source;
  }

  /// Removes the source, its cached occurrences, its link, its stored feed
  /// body, the sync markers kept for it and its Feed stale and Feed broken
  /// notices (a Fix that opens a removed source would lead nowhere). Once the
  /// row is gone each of the rest is tried on its own, so a step that fails (a
  /// Keystore error, say) is logged and leaves the others done.
  Future<void> delete(String sourceId) async {
    final source = await sources.byId(sourceId);
    await sources.delete(sourceId);
    final key = source?.secureStorageKey;
    if (key != null) await _cleanUp('secure link', () => secrets.delete(key));
    await _cleanUp('feed body', () => bodies.delete(sourceId));
    for (final kind in SourceNoticeKind.values) {
      await _cleanUp('notice', () => _cancelNotice(kind, sourceId));
    }
    await _cleanUp(
      'server-error marker',
      () => _clearSetting(SyncService.serverErrorSinceKey(sourceId)),
    );
    await _cleanUp(
      'broken-notice marker',
      () => _clearSetting(SyncService.brokenNoticeKey(sourceId)),
    );
  }

  /// Runs one cleanup step of [delete]. A failure is logged by type only (an
  /// exception's message can name the link) and does not stop the steps after
  /// it.
  Future<void> _cleanUp(String step, Future<void> Function() run) async {
    try {
      await run();
    } on Exception catch (e) {
      debugPrint('Removing a source: $step failed (${e.runtimeType})');
    }
  }

  Future<void> _cancelNotice(SourceNoticeKind kind, String sourceId) async {
    try {
      await platform.cancelSourceNotice(kind: kind, sourceId: sourceId);
    } on MissingPluginException {
      // No native side (tests, desktop).
    } on PlatformException {
      // The notice may linger; the source is gone either way.
    }
  }

  /// Empties a settings key. Writes only when it is set, as the sync service
  /// does, so a source that never failed gets no row.
  Future<void> _clearSetting(String key) async {
    if ((await settings.getString(key) ?? '').isNotEmpty) {
      await settings.setString(key, '');
    }
  }

  IcsUrlAccepted _accepted(String url) => switch (IcsUrl.check(url)) {
    IcsUrlAccepted a => a,
    IcsUrlRejected(:final message) => throw IcsUrlException(message),
  };

  String _newId(String prefix) {
    final bytes = List.generate(6, (_) => _random.nextInt(256));
    return '$prefix-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
