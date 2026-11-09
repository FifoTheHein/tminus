import '../sync/sync_service.dart' show SyncService;
import 'settings_repository.dart';

/// Whether a source can be synced, or waits for the user (Plan 5
/// decision 13). Stored by its short name; never rename one.
enum SourceSetup {
  ready(''),
  needsLink('link'),
  needsCalendar('calendar');

  const SourceSetup(this.stored);
  final String stored;

  static SourceSetup parse(String? stored) => SourceSetup.values.firstWhere(
    (s) => s.stored == (stored ?? ''),
    orElse: () => SourceSetup.ready,
  );
}

/// Typed access to the settings Plan 5 adds. All live in the `settings`
/// table as strings, so the database (and a backup) carries them.
class AppSettings {
  AppSettings(this._settings);

  final SettingsRepository _settings;

  static const onboardingDoneKey = 'ui.onboardingDone';
  static const restorePendingKey = 'ui.restorePending';

  /// The install id this database was written under (decision 4).
  static const installIdKey = 'device.installId';
  static String sourceSetupKey(String sourceId) => 'source.setup.$sourceId';

  Future<bool> onboardingDone() => _flag(onboardingDoneKey);
  Stream<bool> watchOnboardingDone() => _watchFlag(onboardingDoneKey);
  Future<void> setOnboardingDone(bool v) => _setFlag(onboardingDoneKey, v);

  Future<bool> restorePending() => _flag(restorePendingKey);
  Stream<bool> watchRestorePending() => _watchFlag(restorePendingKey);
  Future<void> setRestorePending(bool v) => _setFlag(restorePendingKey, v);

  Future<String?> installId() async {
    final v = await _settings.getString(installIdKey);
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setInstallId(String id) => _settings.setString(installIdKey, id);

  Future<SourceSetup> sourceSetup(String sourceId) async =>
      SourceSetup.parse(await _settings.getString(sourceSetupKey(sourceId)));

  Future<void> setSourceSetup(String sourceId, SourceSetup setup) async {
    // Writes only to set a marker or clear one that is set, like the sync's
    // own markers, so a source that never needed setup gets no row.
    final current = await _settings.getString(sourceSetupKey(sourceId));
    if ((current ?? '') == setup.stored) return;
    await _settings.setString(sourceSetupKey(sourceId), setup.stored);
  }

  /// Plan 4b decision 5: off only when stored as `'false'`.
  Future<bool> mergeEnabled() async =>
      await _settings.getString(SyncService.mergeEnabledKey) != 'false';

  Future<void> setMergeEnabled(bool v) =>
      _settings.setString(SyncService.mergeEnabledKey, v ? 'true' : 'false');

  Future<bool> _flag(String key) async =>
      await _settings.getString(key) == 'true';

  Stream<bool> _watchFlag(String key) =>
      _settings.watchString(key).map((v) => v == 'true');

  Future<void> _setFlag(String key, bool v) =>
      _settings.setString(key, v ? 'true' : 'false');
}
