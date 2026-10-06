import 'package:drift/drift.dart';

import '../model/source_config.dart';
import 'app_database.dart';

class SourceRepository {
  SourceRepository(this._db);

  final AppDatabase _db;

  /// Sorted by name, then id.
  Future<List<SourceConfig>> all() => _ordered().map(_configFromRow).get();

  Stream<List<SourceConfig>> watchAll() =>
      _ordered().map(_configFromRow).watch();

  Future<SourceConfig?> byId(String id) =>
      _byId(id).map(_configFromRow).getSingleOrNull();

  /// Inserts or updates the configuration. Never touches the sync state.
  Future<void> save(SourceConfig s) => _db
      .into(_db.sources)
      .insertOnConflictUpdate(
        SourcesCompanion(
          id: Value(s.id),
          name: Value(s.name),
          color: Value(s.color),
          kind: Value(s.kind),
          deviceCalendarId: Value(s.deviceCalendarId),
          secureStorageKey: Value(s.secureStorageKey),
          defaultProfileId: Value(s.defaultProfileId),
          enabled: Value(s.enabled),
        ),
      );

  /// Deletes the source; its cached occurrences go with it (FK cascade).
  /// Plan 4 deletes the ICS URL from secure storage.
  Future<void> delete(String id) =>
      (_db.delete(_db.sources)..where((s) => s.id.equals(id))).go();

  Future<SourceSyncState?> syncState(String id) =>
      _byId(id).map(_syncFromRow).getSingleOrNull();

  Stream<SourceSyncState?> watchSyncState(String id) =>
      _byId(id).map(_syncFromRow).watchSingleOrNull();

  Future<void> updateSyncState(String id, SourceSyncState s) =>
      (_db.update(_db.sources)..where((r) => r.id.equals(id))).write(
        SourcesCompanion(
          lastAttemptUtcMs: Value(s.lastAttemptUtc?.millisecondsSinceEpoch),
          lastSuccessUtcMs: Value(s.lastSuccessUtc?.millisecondsSinceEpoch),
          lastError: Value(s.lastError),
          httpEtag: Value(s.httpEtag),
          httpLastModified: Value(s.httpLastModified),
          emptyStreak: Value(s.emptyStreak),
        ),
      );

  SimpleSelectStatement<$SourcesTable, SourceRow> _byId(String id) =>
      _db.select(_db.sources)..where((s) => s.id.equals(id));

  SimpleSelectStatement<$SourcesTable, SourceRow> _ordered() => _db.select(
    _db.sources,
  )..orderBy([(s) => OrderingTerm.asc(s.name), (s) => OrderingTerm.asc(s.id)]);

  static SourceConfig _configFromRow(SourceRow r) => SourceConfig(
    id: r.id,
    name: r.name,
    color: r.color,
    kind: r.kind,
    deviceCalendarId: r.deviceCalendarId,
    secureStorageKey: r.secureStorageKey,
    defaultProfileId: r.defaultProfileId,
    enabled: r.enabled,
  );

  static SourceSyncState _syncFromRow(SourceRow r) {
    DateTime? t(int? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return SourceSyncState(
      lastAttemptUtc: t(r.lastAttemptUtcMs),
      lastSuccessUtc: t(r.lastSuccessUtcMs),
      lastError: r.lastError,
      httpEtag: r.httpEtag,
      httpLastModified: r.httpLastModified,
      emptyStreak: r.emptyStreak,
    );
  }
}
