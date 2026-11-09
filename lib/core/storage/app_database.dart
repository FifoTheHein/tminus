import 'dart:io' show sleep;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

import '../model/alert_history_entry.dart';
import '../model/alert_profile.dart';
import '../model/event_occurrence.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/meeting_link.dart';
import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import 'profile_mapping.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Sources,
    Occurrences,
    Overrides,
    Profiles,
    KeywordRules,
    QuietStates,
    AlertHistory,
    SyncLog,
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
  static void configureConnection(CommonDatabase raw) {
    raw.execute('PRAGMA busy_timeout = $busyTimeoutMs');
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
  int get schemaVersion => 2;

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
        // is added only if it is missing.
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
        await transaction(() async {
          await m.createTable(meetingLinks);
          if (!await _hasColumn('occurrences', 'ical_uid')) {
            await m.addColumn(occurrences, occurrences.icalUid);
          }
          await m.createIndex(meetingLinksSourceUid);
          await m.createIndex(meetingLinksMeetingKey);
        });
      }
    },
    beforeOpen: (details) async {
      // Repeats [configureConnection] for executors opened without it.
      await customStatement('PRAGMA busy_timeout = $busyTimeoutMs');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA foreign_keys = ON');
      await seedBuiltInProfiles();
    },
  );

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  /// Folds the write-ahead log into the main file without waiting for readers
  /// (Plan 5 decision 4: a backup copies the main file, so it should be
  /// nearly complete). A no-op on `:memory:`.
  Future<void> checkpoint() async {
    await customSelect('PRAGMA wal_checkpoint(PASSIVE)').get();
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
