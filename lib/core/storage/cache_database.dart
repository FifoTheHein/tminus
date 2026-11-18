import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../model/alert_history_entry.dart';
import '../model/event_occurrence.dart';
import '../model/sync_log_entry.dart';
import 'app_database.dart' show AppDatabase, SettingsCompanion;
import 'cache_tables.dart';

export 'cache_tables.dart';

part 'cache_database.g.dart';

/// The cache database (`tminus_cache.sqlite`): the occurrence cache, the alert
/// history, the sync log and the few values that carry the same content
/// ([CacheValues]). Everything else stays in `tminus.sqlite` ([AppDatabase]).
///
/// Plan 6 decision 4: the rules that back the app up list `tminus.sqlite` and
/// not this file, so no meeting title, location, join link or alert history is
/// ever backed up. A restore already throws these three tables away
/// (`RestoreGuard`), so a restore loses nothing it kept before.
///
/// Like [AppDatabase], it opens in the UI isolate and in the headless sync
/// isolate, and both may do it at the same moment.
///
/// The first query on it reads [legacy] (see [LegacyCacheMove]), so nothing may
/// start that query inside a transaction of [legacy] that has to finish first:
/// the two would wait for each other.
@DriftDatabase(tables: [Occurrences, AlertHistory, SyncLog, CacheValues])
class CacheDatabase extends _$CacheDatabase {
  /// Tests pass `DatabaseConnection(NativeDatabase.memory(),
  /// closeStreamsSynchronously: true)`, and a [legacy] database where they test
  /// the move. A file-backed executor should pass
  /// [AppDatabase.configureConnection] as its `setup`.
  CacheDatabase(super.executor, {this.legacy});

  /// `tminus_cache.sqlite` next to `tminus.sqlite`. Not listed in the backup
  /// rules, so Android never backs it up (Plan 6 decision 4).
  factory CacheDatabase.open({required AppDatabase legacy}) => CacheDatabase(
    driftDatabase(
      name: 'tminus_cache',
      native: const DriftNativeOptions(setup: AppDatabase.configureConnection),
    ),
    legacy: legacy,
  );

  /// The database whose schema 3 `legacy_*` tables are moved here on open.
  /// Null where there is nothing to move (a fresh database in a test).
  final AppDatabase? legacy;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (_) async {
      // Repeats AppDatabase.configureConnection for executors opened without
      // it.
      await customStatement(
        'PRAGMA busy_timeout = ${AppDatabase.busyTimeoutMs}',
      );
      await customStatement('PRAGMA journal_mode = WAL');
      // Before the open finishes, so before anything can read the cache: a sync
      // or an edit that planned from it must never see it without the meetings
      // the previous build had cached (an empty plan cancels every alarm).
      final from = legacy;
      if (from != null) await LegacyCacheMove(from: from, to: this).run();
    },
  );
}

/// A legacy table and the cache table that takes over its rows.
typedef _Legacy = ({String name, TableInfo<Table, Object?> cache});

/// The rows read from a legacy table: the columns both tables have, and each
/// row's values in that order.
typedef _Rows = ({
  TableInfo<Table, Object?> cache,
  List<String> columns,
  List<List<Object?>> rows,
});

/// Moves the rows that schema 3 of `tminus.sqlite` left in
/// `legacy_occurrences`, `legacy_alert_history` and `legacy_sync_log` into the
/// cache database, then drops those tables (Plan 6 decisions 4, 10 and 11). It
/// moves one more thing with them: the `settings` row that held the alerts the
/// last plan expected to ring ([CacheValues.expectedAlertsKey]), which carries
/// meeting titles and so must not stay in the backed-up file. That row is
/// copied into `cache_values` and deleted, just as the tables are copied and
/// dropped.
///
/// It runs in [CacheDatabase]'s `beforeOpen`, so before anything reads the
/// cache, and a build that has cached meetings keeps every one of them, offline
/// too. It is safe to run in two isolates at once and again after a crash at
/// any point:
/// - The legacy tables and the setting are read in one transaction on the old
///   database, so another isolate cannot drop one between the check that it
///   exists and the read of its rows (it drops them only after its own copy has
///   committed).
/// - The copy is one cache transaction of `INSERT OR IGNORE`, so a row that is
///   already there stays as it is (it can only be newer: nothing writes the
///   legacy tables or the setting any more) and a second copy adds nothing.
/// - The same transaction writes [CacheValues.legacyMovedKey], and the copy is
///   skipped when that is already there, checked once more inside the
///   transaction, which holds the cache's write lock. So an isolate that read
///   the old tables and then stalled cannot copy after another one has copied
///   and a sync has removed a meeting from the cache: its `INSERT OR IGNORE`
///   would put that meeting back. A crash after the copy makes the next open go
///   straight to the drop.
/// - The legacy tables are dropped and the setting is deleted in one
///   transaction on the old database, only after the copy has committed, and
///   each table only if it still exists. A crash between the two leaves them
///   for the next open to drop.
///
/// What the old database held is still in its file after that: a drop frees the
/// pages and does not erase them, and neither does the write-ahead log, and
/// both are backed up. So, once the tables are gone, the move compacts the
/// file: `VACUUM`, then a `TRUNCATE` checkpoint of the log. That is best
/// effort. A failure, or a log a reader kept from truncating, is logged by type
/// and does not fail the open, and the `settings` row [compactedKey] is written
/// only when both worked, so every later open tries again until they do. A
/// connection set up by `AppDatabase.configureConnection` zeroes the pages that
/// later deletes free, so only what a build before Plan 6 left behind needs
/// this.
///
/// The two databases are never in one transaction at a time: drift resolves a
/// transaction through one zone slot, so a query on one database inside a
/// transaction of the other would not be part of the first one's transaction.
///
/// Errors propagate. A failed move fails the open, so nothing plans from a
/// half-empty cache. Drift remembers a failed open and fails every later query
/// on that [CacheDatabase], so the next process (or the next headless sync,
/// which starts with a new one) tries again.
class LegacyCacheMove {
  LegacyCacheMove({required this.from, required this.to});

  /// The database that holds the `legacy_*` tables and the old setting.
  final AppDatabase from;

  /// The cache database that receives their rows.
  final CacheDatabase to;

  /// How many rows are read, and then inserted, at a time.
  static const pageSize = 500;

  /// The `settings` row, in the file it describes, that says `tminus.sqlite`
  /// has been compacted since the cache left it. It travels with a backup of
  /// that file, so a file restored from a build before Plan 6 has none and is
  /// compacted at its first open.
  static const compactedKey = 'storage.compactedV3';

  /// Smaller than any rowid.
  static const _beforeFirstRowid = -0x8000000000000000;

  late final List<_Legacy> _tables = [
    (name: 'legacy_occurrences', cache: to.occurrences),
    (name: 'legacy_alert_history', cache: to.alertHistory),
    (name: 'legacy_sync_log', cache: to.syncLog),
  ];

  Future<void> run() async {
    // The usual case, from the second start on: nothing to move and no lock.
    if ((await _present()).isNotEmpty || await _expectedAlerts() != null) {
      await _move();
    }
    await _compactOnce();
  }

  Future<void> _move() async {
    // A copy that has committed, here or in an isolate that has crashed since,
    // is not made again.
    if (!await _copied()) {
      final moved = await from.transaction(() async {
        final present = await _present();
        return (
          tables: [
            for (final t in _tables)
              if (present.contains(t.name)) await _read(t),
          ],
          expectedAlerts: await _expectedAlerts(),
        );
      });
      // Another isolate finished between the two checks.
      if (moved.tables.isEmpty && moved.expectedAlerts == null) return;

      await to.transaction(() async {
        // Checked again here: this transaction holds the cache's write lock, so
        // another isolate's copy has either committed (and so has its marker)
        // or comes after this one.
        if (await _copied()) return;
        for (final m in moved.tables) {
          await _copy(m);
        }
        final expected = moved.expectedAlerts;
        if (expected != null) {
          await _insertValue(CacheValues.expectedAlertsKey, expected);
        }
        await _insertValue(CacheValues.legacyMovedKey, '1');
      });
    }

    // The copy has committed, so the tables and the setting can go. Another
    // isolate may have dropped some of them already.
    await from.transaction(() async {
      final present = await _present();
      for (final t in _tables) {
        if (present.contains(t.name)) {
          await from.customStatement('DROP TABLE ${t.name}');
        }
      }
      await (from.delete(
        from.settings,
      )..where((s) => s.name.equals(CacheValues.expectedAlertsKey))).go();
    });
  }

  /// Compacts `tminus.sqlite` unless that has been done since the cache left
  /// it (see [compactedKey]). Never throws.
  Future<void> _compactOnce() async {
    try {
      if (await _compacted()) return;
      // Outside any transaction: `VACUUM` cannot run inside one. It rewrites
      // every page, so none of the free pages with old bytes survives.
      await from.customStatement('VACUUM');
      // The rewritten pages are in the log until this folds them in and empties
      // it, and the log also holds the frames from before. `busy` is 1 when a
      // reader kept it from doing that: the old frames are still there.
      final log = await from
          .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
          .getSingle();
      if (log.read<int>('busy') != 0) return;
      await from
          .into(from.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(name: compactedKey, value: '1'),
          );
    } catch (e) {
      debugPrint('Compacting the main database failed: ${e.runtimeType}');
    }
  }

  Future<bool> _compacted() async =>
      await (from.select(
        from.settings,
      )..where((s) => s.name.equals(compactedKey))).getSingleOrNull() !=
      null;

  /// Whether the legacy rows have been copied into the cache.
  Future<bool> _copied() async =>
      await (to.select(to.cacheValues)
            ..where((r) => r.name.equals(CacheValues.legacyMovedKey)))
          .getSingleOrNull() !=
      null;

  /// `INSERT OR IGNORE`, so a value that is already there stays.
  Future<void> _insertValue(String name, String value) => to.customStatement(
    'INSERT OR IGNORE INTO ${to.cacheValues.actualTableName} '
    '(name, value) VALUES (?, ?)',
    [name, value],
  );

  /// The old setting that held the expected alerts, or null.
  Future<String?> _expectedAlerts() =>
      (from.select(from.settings)
            ..where((s) => s.name.equals(CacheValues.expectedAlertsKey)))
          .map((s) => s.value)
          .getSingleOrNull();

  /// The names of the legacy tables that exist in [from] now.
  Future<Set<String>> _present() async {
    final rows = await from
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = {for (final r in rows) r.read<String>('name')};
    return {
      for (final t in _tables)
        if (names.contains(t.name)) t.name,
    };
  }

  /// Every row of a legacy table in rowid order, a page at a time. Only the
  /// columns the cache table has are read: a column the cache dropped is not
  /// moved, and one it added gets its default.
  Future<_Rows> _read(_Legacy t) async {
    final wanted = {for (final c in t.cache.$columns) c.name};
    final info = await from.customSelect('PRAGMA table_info(${t.name})').get();
    final columns = [
      for (final r in info)
        if (wanted.contains(r.read<String>('name'))) r.read<String>('name'),
    ];
    final rows = <List<Object?>>[];
    var after = _beforeFirstRowid;
    while (true) {
      final page = await from
          .customSelect(
            'SELECT rowid AS legacy_rowid, ${columns.join(', ')} '
            'FROM ${t.name} WHERE rowid > ? ORDER BY rowid LIMIT $pageSize',
            variables: [Variable<int>(after)],
          )
          .get();
      for (final r in page) {
        rows.add([for (final c in columns) r.data[c]]);
      }
      if (page.length < pageSize) break;
      after = page.last.read<int>('legacy_rowid');
    }
    return (cache: t.cache, columns: columns, rows: rows);
  }

  /// Inserts what [_read] returned into the cache table, a page at a time.
  Future<void> _copy(_Rows moved) async {
    final sql =
        'INSERT OR IGNORE INTO ${moved.cache.actualTableName} '
        '(${moved.columns.join(', ')}) '
        'VALUES (${List.filled(moved.columns.length, '?').join(', ')})';
    for (var i = 0; i < moved.rows.length; i += pageSize) {
      final page = moved.rows.skip(i).take(pageSize);
      await to.batch((b) {
        for (final row in page) {
          b.customStatement(sql, row);
        }
      });
    }
  }
}
