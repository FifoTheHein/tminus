import 'dart:io' show sleep;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

import '../model/alert_profile.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/meeting_link.dart';
import '../model/source_config.dart';
import 'profile_mapping.dart';
import 'schema_versions.dart' show Schema2;
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// The on-device database `tminus.sqlite`. Since schema 3 it no longer holds
/// the occurrence cache, the alert history and the sync log: those are in
/// `CacheDatabase`, which the backup rules leave out (Plan 6 decision 4). This
/// is the part that is backed up: sources (no links), profiles, rules,
/// overrides, quiet state, settings and meeting links.
@DriftDatabase(
  tables: [
    Sources,
    Overrides,
    Profiles,
    KeywordRules,
    QuietStates,
    Settings,
    MeetingLinks,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Tests pass `DatabaseConnection(NativeDatabase.memory(),
  /// closeStreamsSynchronously: true)`. A file-backed executor should pass
  /// [configureConnection] as its `setup` so the pragmas also cover the
  /// schema check and migrations that run before [MigrationStrategy.beforeOpen].
  AppDatabase(super.executor);

  /// The on-device database (`tminus.sqlite` in the app's documents
  /// directory). Works in the UI isolate and in the headless sync isolate.
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: 'tminus',
      native: const DriftNativeOptions(setup: configureConnection),
    ),
  );

  /// How long a connection waits for another connection's write lock before
  /// failing with `SQLITE_BUSY` (decision 14).
  static const busyTimeoutMs = 5000;

  /// Pragmas every connection needs so the UI isolate and the headless sync
  /// isolate can both write (decision 14): wait for a lock instead of failing,
  /// and use WAL so readers never block the writer. On `:memory:` the journal
  /// mode stays `memory`, which is fine.
  ///
  /// Also `secure_delete`: SQLite then zeroes what a delete or a dropped table
  /// frees, where it otherwise leaves the old bytes in the file's free pages.
  /// This file is backed up, so what it once held (the cache of a build before
  /// Plan 6 was in it) must not outlive its deletion (Plan 6 decision 4).
  static void configureConnection(CommonDatabase raw) {
    raw.execute('PRAGMA busy_timeout = $busyTimeoutMs');
    raw.execute('PRAGMA secure_delete = ON');
    // Switching to WAL can fail with SQLITE_BUSY without waiting on the busy
    // timeout while another connection is opening the same file, so retry
    // for up to the same timeout.
    final deadline = DateTime.now().add(
      const Duration(milliseconds: busyTimeoutMs),
    );
    while (true) {
      try {
        raw.execute('PRAGMA journal_mode = WAL');
        return;
      } on SqliteException catch (e) {
        if (e.resultCode != SqlError.SQLITE_BUSY ||
            DateTime.now().isAfter(deadline)) {
          rethrow;
        }
        sleep(const Duration(milliseconds: 10));
      }
    }
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Drift calls this when the stored version is newer than this build's
      // too, and would then stamp the older version over a schema it does not
      // know. Refuse instead, as this callback did while it had no step.
      if (from > to) {
        throw UnsupportedError('Downgrade from schema $from to $to');
      }
      // Schema 1 was the first release. Each `if (from < N) { … }` step
      // takes a database older than N up to N. Add the next one when bumping
      // [schemaVersion]; never edit a shipped step.
      if (from < 2) {
        // Meeting links and `occurrences.ical_uid` (spec §13).
        //
        // Drift runs this callback outside any transaction and stores the new
        // version only after it returns, and the UI isolate and the headless
        // sync isolate may both open a schema 1 file at once. So the step is
        // one transaction (an interrupted run leaves nothing half done) and
        // safe to run again: every statement is IF NOT EXISTS, and the column
        // is added only if the table is there and lacks it.
        //
        // Drift (2.34 and later) starts a transaction with BEGIN IMMEDIATE, so
        // the write lock is taken right there, from a clean state, and the
        // busy timeout makes a second connection wait for the first to
        // commit instead of failing. When it gets in, the work is done:
        // the first statement and the indexes do nothing and the guard finds
        // the column. The first statement is also a write on purpose. If a
        // transaction here were ever deferred, a read first (`PRAGMA
        // table_info`) would pin a snapshot, and the later ALTER could not
        // upgrade it to the write lock: SQLite fails that at once with
        // SQLITE_BUSY, without waiting, and drift then refuses every later
        // query on that connection.
        //
        // `occurrences` is not one of this database's tables since schema 3,
        // so the column is added through schema 2's own description of the
        // table (`schema_versions.dart`, generated from drift_schemas/).
        //
        // Plan 6 run-log decision R15: the column is added only while the table
        // exists. A file whose schema 3 step has already committed has no
        // `occurrences` any more, and adding a column to it fails. That is what
        // a second isolate finds when two open a schema 1 file at once, and
        // what a run finds again and again after a crash between that commit
        // and drift storing the version. It changes nothing for a file that
        // still has the table.
        final schema2 = Schema2(database: this);
        await transaction(() async {
          await m.createTable(meetingLinks);
          final columns = await _columnNames('occurrences');
          if (columns.isNotEmpty && !columns.contains('ical_uid')) {
            await m.addColumn(schema2.occurrences, schema2.occurrences.icalUid);
          }
          await m.createIndex(meetingLinksSourceUid);
          await m.createIndex(meetingLinksMeetingKey);
        });
      }
      if (from < 3) {
        // The occurrence cache, the alert history and the sync log move to
        // `tminus_cache.sqlite`, which the backup rules leave out (Plan 6
        // decision 4). This step only sets their tables aside as `legacy_*`;
        // `CacheDatabase` copies the rows and drops them (decision 11), and
        // `RestoreGuard` drops them from a restored backup.
        //
        // The same rules as the schema 2 step. One transaction, because drift
        // stores the new version only after this callback returns and both
        // isolates may upgrade the same file at once. Safe to run again: the
        // second connection waits for the first one's commit and then finds
        // nothing left to do, because every statement below runs only while
        // `sqlite_master` shows it is still needed. The first statement is a
        // write, for the reason given above: it drops an index that exists
        // whenever there is work to do, and when there is none nothing after
        // it writes.
        await transaction(() async {
          await customStatement('DROP INDEX IF EXISTS alert_history_start');
          await customStatement('DROP INDEX IF EXISTS sync_log_at');
          final tables = await _tableNames();
          if (tables.contains('occurrences')) {
            // Rebuilt instead of renamed: SQLite keeps the foreign key to
            // `sources` on a rename, and its cascade would then delete the
            // copies that are waiting to be moved when a source is removed.
            // `CREATE TABLE … AS SELECT` keeps the names and the values but
            // not the constraints, which is enough for a table that is only
            // read and then dropped.
            if (!tables.contains('legacy_occurrences')) {
              await customStatement(
                'CREATE TABLE legacy_occurrences AS SELECT * FROM occurrences',
              );
            }
            await customStatement('DROP TABLE occurrences');
          }
          if (tables.contains('alert_history') &&
              !tables.contains('legacy_alert_history')) {
            await customStatement(
              'ALTER TABLE alert_history RENAME TO legacy_alert_history',
            );
          }
          if (tables.contains('sync_log') &&
              !tables.contains('legacy_sync_log')) {
            await customStatement(
              'ALTER TABLE sync_log RENAME TO legacy_sync_log',
            );
          }
        });
      }
    },
    beforeOpen: (details) async {
      // Repeats [configureConnection] for executors opened without it.
      await customStatement('PRAGMA busy_timeout = $busyTimeoutMs');
      await customStatement('PRAGMA secure_delete = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA foreign_keys = ON');
      await seedBuiltInProfiles();
    },
  );

  /// The columns of [table], none if the table does not exist.
  Future<List<String>> _columnNames(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return [for (final r in rows) r.read<String>('name')];
  }

  /// The tables that exist in the file now, whatever this class declares.
  Future<Set<String>> _tableNames() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    return {for (final r in rows) r.read<String>('name')};
  }

  /// Folds the write-ahead log into the main file and empties the log (Plan 5
  /// decision 4: a backup copies the main file, and Plan 6 decision 4 says it
  /// must hold nothing that was deleted, which the old frames of the log would
  /// keep). It waits up to [busyTimeoutMs] for readers to finish. If they do
  /// not, the pragma reports it in its result and not as an error, so this
  /// falls back to what it could fold in, silently. A no-op on `:memory:`.
  Future<void> checkpoint() async {
    await customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
  }

  /// Inserts any missing built-in profile. Never overwrites an edited one.
  Future<void> seedBuiltInProfiles() async {
    await batch((b) {
      for (final (i, p) in BuiltInProfiles.all.indexed) {
        b.insert(
          profiles,
          profileToCompanion(p, position: i),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }
}
