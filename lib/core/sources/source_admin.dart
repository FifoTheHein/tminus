import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../model/source_config.dart';
import '../storage/app_database.dart';
import '../storage/app_settings.dart';
import '../storage/occurrence_repository.dart';
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

/// Adds, re-links, edits and removes sources (Plan 5's Sources tab and
/// onboarding call this, then run a sync). The ICS link goes to secure
/// storage, never to drift (spec §10).
class SourceAdmin {
  SourceAdmin({
    required this.sources,
    required this.secrets,
    required this.bodies,
    required this.platform,
    required this.settings,
    required this.occurrences,
    required this.db,
    Random? random,
  }) : _random = random ?? Random.secure();

  final SourceRepository sources;
  final SourceSecrets secrets;
  final FeedBodyCache bodies;

  /// Withdraws a removed source's notices (decision 27).
  final SyncPlatform platform;

  /// Holds the markers the sync service keeps per source: when its server
  /// errors began and which Feed broken notice is up. A new link resets the
  /// first; a removal clears both. Also holds the setup marker of a source
  /// that waits for its link or calendar (see [AppSettings.sourceSetupKey]).
  final SettingsRepository settings;

  /// [updateDeviceCalendar] empties the old calendar's cached events through
  /// it. Required, so a re-pointed source can never keep them.
  final OccurrenceRepository occurrences;

  /// The database that [sources], [occurrences] and [settings] write to.
  /// [updateIcsUrl] and [updateDeviceCalendar] change several of its tables
  /// and do it in one transaction on it.
  final AppDatabase db;
  final Random _random;
  late final AppSettings _app = AppSettings(settings);

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
  /// Outlook, or after a restore or import). Forgets the old conditional-GET
  /// validators and stored body, and restarts the 24 h server-error
  /// escalation. A source that was waiting for its link is enabled. Returns
  /// whether the link is plain `http://`.
  ///
  /// The link goes to secure storage first. Every database change then happens
  /// in one transaction, so a failure leaves the source as it was, never
  /// enabled with its setup marker still set. The new link stays, and trying
  /// again writes it once more.
  Future<bool> updateIcsUrl(String sourceId, String url) async {
    final link = _accepted(url);
    final source = await sources.byId(sourceId);
    final key = source?.secureStorageKey;
    if (source == null || source.kind != SourceKind.ics || key == null) {
      throw ArgumentError.value(sourceId, 'sourceId', 'not an ICS source');
    }
    await secrets.writeUrl(key, link.url);
    await db.transaction(() async {
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
      // The new link starts a new run of server errors: the old link's must
      // not count toward reporting it broken.
      await _clearSetting(SyncService.serverErrorSinceKey(sourceId));
      if (await _app.sourceSetup(sourceId) == SourceSetup.needsLink) {
        await sources.save(source.copyWith(enabled: true));
        await _app.setSourceSetup(sourceId, SourceSetup.ready);
      }
    });
    // A file, so outside the transaction. The validators are gone by now, so a
    // body that stays behind is never used.
    await bodies.delete(sourceId);
    return link.insecure;
  }

  /// Points a phone-calendar source at a calendar on this phone (after a
  /// restore or import, Plan 5 decision 4) and enables it. Throws
  /// [ArgumentError] for a source that is not a phone one. All of it happens
  /// in one transaction, so a failure leaves the source as it was, never
  /// enabled with its setup marker still set.
  Future<void> updateDeviceCalendar(
    String sourceId,
    DeviceCalendar calendar,
  ) async {
    final source = await sources.byId(sourceId);
    if (source == null || source.kind != SourceKind.device) {
      throw ArgumentError.value(sourceId, 'sourceId', 'not a phone source');
    }
    await db.transaction(() async {
      // The old calendar's events must not survive as this source's cache: the
      // empty-feed guard would keep them if the new calendar is empty.
      await occurrences.replaceForSource(sourceId, const []);
      final state = await sources.syncState(sourceId);
      await sources.updateSyncState(
        sourceId,
        SourceSyncState(
          lastAttemptUtc: state?.lastAttemptUtc,
          lastSuccessUtc: state?.lastSuccessUtc,
        ),
      );
      await sources.save(
        source.copyWith(deviceCalendarId: calendar.id, enabled: true),
      );
      await _app.setSourceSetup(sourceId, SourceSetup.ready);
    });
  }

  /// The source's On switch. A source still waiting for its link or calendar
  /// cannot be switched on: it would only fail.
  Future<void> setEnabled(String sourceId, bool enabled) async {
    final source = await sources.byId(sourceId);
    if (source == null) return;
    if (enabled && await _app.sourceSetup(sourceId) != SourceSetup.ready) {
      throw StateError('Source $sourceId needs setup first');
    }
    await sources.save(source.copyWith(enabled: enabled));
  }

  /// Renames or recolours a source and sets or clears its default profile.
  /// Arguments left out keep their value; pass [clearDefaultProfile] to remove
  /// the default profile. Never touches the link.
  Future<void> edit(
    String sourceId, {
    String? name,
    int? color,
    String? defaultProfileId,
    bool clearDefaultProfile = false,
  }) async {
    final source = await sources.byId(sourceId);
    if (source == null) return;
    await sources.save(
      source.copyWith(
        name: name,
        color: color,
        defaultProfileId: defaultProfileId,
        clearDefaultProfile: clearDefaultProfile,
      ),
    );
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
  /// body, the sync and setup markers kept for it and its Feed stale and Feed
  /// broken notices (a Fix that opens a removed source would lead nowhere).
  /// Once the row is gone each of the rest is tried on its own, so a step that
  /// fails (a Keystore error, say) is logged and leaves the others done.
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
    await _cleanUp(
      'setup marker',
      () => _clearSetting(AppSettings.sourceSetupKey(sourceId)),
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
