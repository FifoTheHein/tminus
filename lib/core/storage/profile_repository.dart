import 'package:drift/drift.dart';

import '../model/alert_profile.dart';
import 'app_database.dart';
import 'profile_mapping.dart';
import 'settings_repository.dart';

class ProfileRepository {
  ProfileRepository(this._db);

  final AppDatabase _db;

  /// All profiles in display order (built-ins first, as seeded). A row that
  /// can't be read is left out, or read as its built-in definition
  /// (decision 15).
  Future<List<AlertProfile>> all() async => _readable(await _ordered().get());

  Stream<List<AlertProfile>> watchAll() => _ordered().watch().map(_readable);

  /// Null when [id] is unknown or its row can't be read (unless built in).
  Future<AlertProfile?> byId(String id) async {
    final row = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    return row == null ? null : readableProfileFromRow(row);
  }

  /// Inserts or updates. A new profile goes to the end of the list. The
  /// stored `builtIn` flag always wins over [profile.builtIn], so a user
  /// profile can't become built-in and an edited built-in stays built-in.
  Future<void> save(AlertProfile profile) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(profile.id))).getSingleOrNull();
    if (existing == null) {
      final max = _db.profiles.position.max();
      final last = await (_db.selectOnly(
        _db.profiles,
      )..addColumns([max])).map((r) => r.read(max)).getSingle();
      await _db
          .into(_db.profiles)
          .insert(
            profileToCompanion(
              profile.copyWithBuiltIn(false),
              position: (last ?? -1) + 1,
            ),
          );
    } else {
      await _db
          .into(_db.profiles)
          .insertOnConflictUpdate(
            profileToCompanion(
              profile.copyWithBuiltIn(existing.builtIn),
              position: existing.position,
            ),
          );
    }
  });

  /// Deletes a user profile and every reference to it: source defaults are
  /// cleared, rules that target it are deleted, overrides drop the profile
  /// (and are deleted if nothing else is left), and a global default that
  /// named it goes back to Meeting. Throws [StateError] for a built-in.
  Future<void> delete(String id) => _db.transaction(() async {
    final row = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    if (row.builtIn) throw StateError('Built-in profile "$id" is fixed');

    await (_db.delete(_db.profiles)..where((p) => p.id.equals(id))).go();
    await (_db.update(_db.sources)..where((s) => s.defaultProfileId.equals(id)))
        .write(const SourcesCompanion(defaultProfileId: Value(null)));
    await (_db.delete(
      _db.keywordRules,
    )..where((r) => r.profileId.equals(id))).go();
    await (_db.update(_db.overrides)..where((o) => o.profileId.equals(id)))
        .write(const OverridesCompanion(profileId: Value(null)));
    await (_db.delete(_db.overrides)..where(
          (o) =>
              o.profileId.isNull() &
              o.customAlertsJson.isNull() &
              o.enabled.isNull(),
        ))
        .go();
    final settings = SettingsRepository(_db);
    if (await settings.globalDefaultProfileId() == id) {
      await settings.setGlobalDefaultProfileId(BuiltInProfiles.defaultId);
    }
  });

  static List<AlertProfile> _readable(List<ProfileRow> rows) => [
    for (final r in rows) ?readableProfileFromRow(r),
  ];

  SimpleSelectStatement<$ProfilesTable, ProfileRow> _ordered() =>
      _db.select(_db.profiles)..orderBy([
        (p) => OrderingTerm.asc(p.position),
        (p) => OrderingTerm.asc(p.id),
      ]);
}

extension on AlertProfile {
  AlertProfile copyWithBuiltIn(bool builtIn) => AlertProfile(
    id: id,
    name: name,
    alerts: alerts,
    sound: sound,
    ringsInQuietMode: ringsInQuietMode,
    builtIn: builtIn,
  );
}
