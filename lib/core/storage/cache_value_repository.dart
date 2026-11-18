import 'cache_database.dart';

/// Key/value pairs in the cache database (`cache_values`): what the app keeps
/// that carries the same content as the cache and so must not be backed up.
/// The same shape as `SettingsRepository`, but in the file that is never backed
/// up (Plan 6 decision 4).
class CacheValueRepository {
  CacheValueRepository(this._db);

  final CacheDatabase _db;

  Future<String?> getString(String name) => (_db.select(
    _db.cacheValues,
  )..where((r) => r.name.equals(name))).map((r) => r.value).getSingleOrNull();

  Future<void> setString(String name, String value) => _db
      .into(_db.cacheValues)
      .insertOnConflictUpdate(
        CacheValuesCompanion.insert(name: name, value: value),
      );
}
