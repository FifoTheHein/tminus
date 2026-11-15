import 'dart:io';

import 'package:drift/drift.dart'
    show
        ApplyInterceptor,
        ApplyInterceptorConnection,
        DatabaseConnection,
        QueryExecutor,
        QueryInterceptor,
        TransactionExecutor,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/planner/meeting_planner.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/cache_database.dart';
import 'package:tminus/core/storage/cache_value_repository.dart';
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/missed_system.dart';

import '../../generated_migrations/cache/schema.dart' as cache_schemas;
import '../../generated_migrations/schema.dart' as main_schemas;
import '../fixtures.dart';
import 'test_database.dart';

/// Makes the drop of a legacy table fail, as a process that is killed between
/// the copy and the drop would.
class _DropsFail extends QueryInterceptor {
  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.startsWith('DROP TABLE legacy_')) {
      throw StateError('the move was interrupted');
    }
    return executor.runCustom(statement, args);
  }
}

/// Calls [beforeRead] when the move is about to read the legacy occurrences,
/// which is after it has found that they exist.
class _BeforeTheRead extends QueryInterceptor {
  _BeforeTheRead(this.beforeRead);

  final void Function() beforeRead;
  bool _done = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (!_done &&
        statement.startsWith('PRAGMA table_info(legacy_occurrences)')) {
      _done = true;
      beforeRead();
    }
    return executor.runSelect(statement, args);
  }
}

/// Runs [afterCommit] once, after the first transaction on the connection has
/// committed: a second isolate that stalls just after it has read the old
/// tables.
class _AfterTheFirstCommit extends QueryInterceptor {
  _AfterTheFirstCommit(this.afterCommit);

  final Future<void> Function() afterCommit;
  bool _done = false;

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    if (!_done) {
      _done = true;
      await afterCommit();
    }
  }
}

/// Breaks the compaction of the main database one way or the other. The message
/// of the failure names a link on purpose: a failure must only ever be logged
/// by its type.
class _BreaksCompaction extends QueryInterceptor {
  _BreaksCompaction({required this.vacuumFails});

  /// `VACUUM` throws. Otherwise the checkpoint runs but says the log was busy.
  final bool vacuumFails;

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (vacuumFails && statement == 'VACUUM') {
      throw StateError('no vacuum for https://calendar.example/s3cr3t.ics');
    }
    return executor.runCustom(statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (!vacuumFails &&
        statement.startsWith('PRAGMA wal_checkpoint(TRUNCATE)')) {
      return [
        {'busy': 1, 'log': 4, 'checkpointed': 2},
      ];
    }
    return rows;
  }
}

void main() {
  final mainSchemas = SchemaVerifier(main_schemas.GeneratedHelper());
  final cacheSchemas = SchemaVerifier(cache_schemas.GeneratedHelper());
  const strict = ValidationOptions(validateDropped: true);

  // Two connections of one kind on one file is the point of some tests here.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  DatabaseConnection memory() => DatabaseConnection(
    NativeDatabase.memory(),
    closeStreamsSynchronously: true,
  );

  /// The names of the legacy tables that exist in [raw] now.
  List<String> legacyTablesIn(InitializedSchema schema) => [
    for (final r in schema.rawDatabase.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name LIKE 'legacy_%' ORDER BY name",
    ))
      r['name'] as String,
  ];

  /// A schema 2 database holding [fixture], as a Plan 5 build left it.
  Future<InitializedSchema> schema2With(Schema2Cache fixture) async {
    final schema = await mainSchemas.schemaAt(2);
    addTearDown(schema.close);
    await fixture.insertInto(
      (sql, args) => schema.rawDatabase.execute(sql, args),
    );
    return schema;
  }

  final everything = (DateTime.utc(2000), DateTime.utc(2100));

  /// What the cache database holds, in the order the repositories return it.
  Future<({List<Object?> meetings, List<Object?> history, List<Object?> log})>
  contentsOf(CacheDatabase cache) async => (
    meetings: await OccurrenceRepository(cache)
        .between(everything.$1, everything.$2),
    history: await AlertHistoryRepository(cache).recent(limit: 100000),
    log: await SyncLogRepository(cache).recent(limit: 100000),
  );

  Future<void> expectHolds(CacheDatabase cache, Schema2Cache fixture) async {
    final contents = await contentsOf(cache);
    expect(contents.meetings, fixture.meetings);
    expect(contents.history, fixture.historyNewestFirst);
    expect(contents.log, fixture.logNewestFirst);
    expect(
      await CacheValueRepository(cache)
          .getString(Schema2Cache.expectedAlertsKey),
      fixture.expectedAlertsJson,
    );
  }

  /// What the main database's `settings` holds under the expected alerts' name.
  Future<String?> expectedAlertsSetting(AppDatabase main) =>
      SettingsRepository(main).getString(Schema2Cache.expectedAlertsKey);

  /// The `tminus.sqlite` of a Plan 5 build, in [dir]: schema 2, [fixture]'s
  /// rows and the free pages that build left behind. It rewrote a source's
  /// cached meetings at every sync, so the pages of the rows it replaced went
  /// to the free list with their text in them, and nothing erased them.
  Future<File> plan5File(Directory dir, Schema2Cache fixture) async {
    final file = File('${dir.path}/tminus.sqlite');
    final old = main_schemas.GeneratedHelper().databaseForVersion(
      NativeDatabase(file),
      2,
    );
    await fixture.insertInto((sql, args) => old.customStatement(sql, args));
    for (var i = 0; i < 300; i++) {
      await old.customStatement(
        'INSERT INTO occurrences (occurrence_key, source_id, uid, '
        'original_start_utc_ms, title, description, start_utc_ms, end_utc_ms, '
        'all_day, busy_status, declined, cancelled, calendar_color) '
        "VALUES (?, 'work', ?, 1, ?, ?, 1, 2, 0, 'busy', 0, 0, 1)",
        [
          'work|stale-$i|k',
          'stale-$i',
          'Stale meeting from an earlier sync $i',
          'Agenda of a stale meeting that a later sync replaced ' * 4,
        ],
      );
    }
    await old.customStatement(
      "DELETE FROM occurrences WHERE uid LIKE 'stale-%'",
    );
    await old.close();
    return file;
  }

  /// What must not be in either backed-up file once the cache has moved: the
  /// meetings' titles and join links, the expected alerts and the rows that
  /// [plan5File] freed.
  List<String> meetingBytes(Schema2Cache fixture) => [
    for (final m in fixture.meetings) ...[
      m.title,
      if (m.joinUrl != null) m.joinUrl!,
    ],
    fixture.expectedAlertsJson,
    'Stale meeting from an earlier sync',
  ];

  /// Captures what the code under test logs until the test ends.
  List<String> captureLog() {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);
    return logged;
  }

  test('a fresh install has no legacy tables and an empty cache', () async {
    final main = openTestDatabase();
    addTearDown(main.close);
    final cache = openTestCacheDatabase(legacy: main);
    addTearDown(cache.close);

    // The first query opens the cache, which looks for something to move.
    final contents = await contentsOf(cache);

    expect(contents.meetings, isEmpty);
    expect(contents.history, isEmpty);
    expect(contents.log, isEmpty);
    final legacy = await main
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name LIKE 'legacy_%'",
        )
        .get();
    expect(legacy, isEmpty);
  });

  test('a fresh cache database is schema 1', () async {
    final cache = openTestCacheDatabase();
    addTearDown(cache.close);
    expect(cache.schemaVersion, 1);
    final version = await cache.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 1);

    // The three tables the old database held and the one for the values that
    // go with them, and none of anything else.
    final tables = await cache
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    expect(tables.map((r) => r.data['name']), [
      'alert_history',
      'cache_values',
      'occurrences',
      'sync_log',
    ]);
    // `ical_uid` is declared last, where the migration put it.
    final columns = await cache
        .customSelect('PRAGMA table_info(occurrences)')
        .get();
    expect(columns.last.data['name'], 'ical_uid');
    // No foreign key to the sources of another database.
    final keys = await cache
        .customSelect('PRAGMA foreign_key_list(occurrences)')
        .get();
    expect(keys, isEmpty);

    // Created from scratch, it is exactly the schema dumped in
    // drift_schemas/cache/, so a change to cache_tables.dart needs a new
    // version.
    await cacheSchemas.migrateAndValidate(cache, 1, options: strict);
  });

  test('an upgraded database keeps every cached meeting and the plan is '
      'unchanged', () async {
    initZones();
    final fixture = Schema2Cache();
    final now = Schema2Cache.start.subtract(const Duration(hours: 3));

    /// What the cache plans to: the alerts `applyPlan` would get.
    Future<List<Object?>> planFrom(
      AppDatabase main,
      CacheDatabase cache,
    ) async {
      final settings = SettingsRepository(main);
      final sources = SourceRepository(main);
      final planner = MeetingPlanner(
        sources: sources,
        occurrences: OccurrenceRepository(cache),
        links: MeetingLinkRepository(main),
        history: AlertHistoryRepository(cache),
        settings: settings,
        ruleSets: RuleSetLoader(
          profiles: ProfileRepository(main),
          rules: RuleRepository(main),
          overrides: OverrideRepository(main),
          settings: settings,
          sources: sources,
        ),
        rulesEngine: () => RulesEngine(zone: johannesburg, clock: () => now),
      );
      final plan = await planner.load(
        now: now,
        fromUtc: now.subtract(const Duration(minutes: 15)),
        toUtc: now.add(const Duration(days: 7)),
      );
      return [for (final a in plan.alerts) a.toJson()];
    }

    // The plan the build before this one made from these rows: the same rows
    // put straight into databases that never had anything to move.
    final reference = openTestDatabase();
    addTearDown(reference.close);
    final referenceCache = openTestCacheDatabase();
    addTearDown(referenceCache.close);
    for (final s in fixture.sources) {
      await SourceRepository(reference).save(s);
      await OccurrenceRepository(referenceCache).replaceForSource(s.id, [
        for (final o in fixture.meetings)
          if (o.sourceId == s.id) o,
      ]);
    }
    for (final h in fixture.history) {
      await AlertHistoryRepository(referenceCache).record(h);
    }
    final expectedPlan = await planFrom(reference, referenceCache);
    expect(expectedPlan, isNotEmpty);

    // The upgraded database, with a cache database on top that opens as the
    // planner first reads it.
    final schema = await schema2With(fixture);
    final upgraded = AppDatabase(schema.newConnection());
    addTearDown(upgraded.close);
    final cache = CacheDatabase(memory(), legacy: upgraded);
    addTearDown(cache.close);

    expect(await planFrom(upgraded, cache), expectedPlan);

    // Every cached row came over with every column, and the old tables are
    // gone.
    await expectHolds(cache, fixture);
    expect(legacyTablesIn(schema), isEmpty);
    final oldTables = await upgraded
        .customSelect(
          'SELECT name FROM sqlite_master WHERE name IN '
          "('occurrences', 'alert_history', 'sync_log')",
        )
        .get();
    expect(oldTables, isEmpty);
  });

  test('an upgrade moves the expected alerts into the cache', () async {
    // The alerts the last sync expected to ring carry the meetings' titles. A
    // Plan 5 build kept them in `settings`, which is backed up.
    final fixture = Schema2Cache();
    final title = fixture.expectedAlerts.first.title;
    final schema = await schema2With(fixture);
    final upgraded = AppDatabase(schema.newConnection());
    addTearDown(upgraded.close);
    expect(
      await expectedAlertsSetting(upgraded),
      fixture.expectedAlertsJson,
      reason: 'before the move',
    );
    expect(await tablesHolding(upgraded, title), contains('settings'));
    final cache = CacheDatabase(memory(), legacy: upgraded);
    addTearDown(cache.close);

    // The first use of the cache moves them.
    final values = CacheValueRepository(cache);
    expect(
      await values.getString(Schema2Cache.expectedAlertsKey),
      fixture.expectedAlertsJson,
    );
    expect(
      MissedSystemDetector.decode(
        await values.getString(Schema2Cache.expectedAlertsKey),
      ),
      fixture.expectedAlerts,
    );

    // And the backed-up file holds neither the setting nor a title.
    expect(await expectedAlertsSetting(upgraded), isNull);
    expect(await tablesHolding(upgraded, title), isEmpty);
  });

  test('after the move the backed-up files hold no meeting bytes', () async {
    // What a backup copies is the database file and its write-ahead log. A drop
    // frees pages and does not erase them, and the log keeps old frames, so
    // the move compacts the file once the cache has left it.
    final fixture = Schema2Cache(titlePrefix: 'Zephyr programme review');
    final dir = Directory.systemTemp.createTempSync('tminus_bytes_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final mainFile = await plan5File(dir, fixture);
    final log = File('${mainFile.path}-wal');
    final probes = meetingBytes(fixture);
    // The file really holds them before, or the test proves nothing.
    expect(bytesHolding(mainFile, probes), unorderedEquals(probes));

    final upgraded = AppDatabase(
      NativeDatabase(mainFile, setup: AppDatabase.configureConnection),
    );
    addTearDown(upgraded.close);
    final cache = CacheDatabase(memory(), legacy: upgraded);
    addTearDown(cache.close);
    await expectHolds(cache, fixture);

    expect(bytesHolding(mainFile, probes), isEmpty);
    expect(bytesHolding(log, probes), isEmpty);
    expect(
      await SettingsRepository(upgraded)
          .getString(LegacyCacheMove.compactedKey),
      '1',
    );
  });

  test(
    'a compaction that fails or finds the log busy does not fail the open and '
    'is tried again',
    () async {
      for (final vacuumFails in [true, false]) {
        final how = vacuumFails ? 'the vacuum fails' : 'the log is busy';
        final fixture = Schema2Cache(titlePrefix: 'Zephyr programme review');
        final dir = Directory.systemTemp.createTempSync('tminus_bytes_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final mainFile = await plan5File(dir, fixture);
        final logged = captureLog();

        // The open and the move are fine. The marker is not written, and only
        // the type of the failure is logged.
        final failing = AppDatabase(
          NativeDatabase(
            mainFile,
            setup: AppDatabase.configureConnection,
          ).interceptWith(_BreaksCompaction(vacuumFails: vacuumFails)),
        );
        final cache = CacheDatabase(memory(), legacy: failing);
        addTearDown(cache.close);
        addTearDown(failing.close);
        await expectHolds(cache, fixture);
        expect(
          await SettingsRepository(failing)
              .getString(LegacyCacheMove.compactedKey),
          isNull,
          reason: how,
        );
        if (vacuumFails) {
          expect(logged.join('\n'), contains('StateError'));
          expect(logged.join('\n'), isNot(contains('s3cr3t')));
          expect(
            bytesHolding(mainFile, meetingBytes(fixture)),
            isNotEmpty,
            reason: 'nothing was compacted',
          );
        }
        await cache.close();
        await failing.close();

        // The next open tries again, and this time it works.
        final again = AppDatabase(
          NativeDatabase(mainFile, setup: AppDatabase.configureConnection),
        );
        addTearDown(again.close);
        final cacheAgain = CacheDatabase(memory(), legacy: again);
        addTearDown(cacheAgain.close);
        await cacheAgain.customSelect('SELECT 1').get();
        expect(
          await SettingsRepository(again)
              .getString(LegacyCacheMove.compactedKey),
          '1',
          reason: how,
        );
        expect(
          bytesHolding(mainFile, meetingBytes(fixture)),
          isEmpty,
          reason: how,
        );
        expect(
          bytesHolding(File('${mainFile.path}-wal'), meetingBytes(fixture)),
          isEmpty,
          reason: how,
        );
      }
    },
  );

  test(
    'a move that finds its marker copies nothing and drops the tables',
    () async {
      final fixture = Schema2Cache();
      final schema = await schema2With(fixture);
      final dir = Directory.systemTemp.createTempSync('tminus_move_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cacheFile = File('${dir.path}/tminus_cache.sqlite');
      NativeDatabase cacheFileDatabase() =>
          NativeDatabase(cacheFile, setup: AppDatabase.configureConnection);

      // A cache that says the copy has been made, and has been synced since: it
      // holds no meetings, and a newer value for the expected alerts.
      final prepared = CacheDatabase(cacheFileDatabase());
      final values = CacheValueRepository(prepared);
      await values.setString(CacheValues.legacyMovedKey, '1');
      await values.setString(Schema2Cache.expectedAlertsKey, '[]');
      await prepared.close();

      // The old tables are still there, as after a crash before the drop, or
      // restored from a backup of another phone.
      final upgraded = AppDatabase(schema.newConnection());
      addTearDown(upgraded.close);
      final cache = CacheDatabase(cacheFileDatabase(), legacy: upgraded);
      addTearDown(cache.close);

      final contents = await contentsOf(cache);

      expect(contents.meetings, isEmpty);
      expect(contents.history, isEmpty);
      expect(contents.log, isEmpty);
      expect(
        await CacheValueRepository(cache)
            .getString(Schema2Cache.expectedAlertsKey),
        '[]',
      );
      expect(legacyTablesIn(schema), isEmpty);
      expect(await expectedAlertsSetting(upgraded), isNull);
    },
  );

  test('a second isolate that stalled after its read does not bring back a '
      'removed meeting', () async {
    final fixture = Schema2Cache();
    final dir = Directory.systemTemp.createTempSync('tminus_stall_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final mainFile = await plan5File(dir, fixture);
    final cacheFile = File('${dir.path}/tminus_cache.sqlite');
    NativeDatabase mainConnection() =>
        NativeDatabase(mainFile, setup: AppDatabase.configureConnection);
    NativeDatabase cacheConnection() =>
        NativeDatabase(cacheFile, setup: AppDatabase.configureConnection);

    // The first isolate opens while the second one waits between its read of
    // the old tables and its copy. Then a sync of the first one finds the
    // work calendar's meetings gone.
    Future<void> firstIsolateMovesAndSyncs() async {
      final main = AppDatabase(mainConnection());
      final cache = CacheDatabase(cacheConnection(), legacy: main);
      await cache.customSelect('SELECT 1').get();
      await OccurrenceRepository(cache).deleteForSource('work');
      await cache.close();
      await main.close();
    }

    final second = AppDatabase(
      mainConnection().interceptWith(
        _AfterTheFirstCommit(firstIsolateMovesAndSyncs),
      ),
    );
    addTearDown(second.close);
    final secondCache = CacheDatabase(cacheConnection(), legacy: second);
    addTearDown(secondCache.close);

    final contents = await contentsOf(secondCache);

    expect(contents.meetings, [
      for (final m in fixture.meetings)
        if (m.sourceId != 'work') m,
    ]);
  });

  test('a move interrupted after the copy finishes on the next open', () async {
    final fixture = Schema2Cache();
    final schema = await schema2With(fixture);
    final dir = Directory.systemTemp.createTempSync('tminus_move_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cacheFile = File('${dir.path}/tminus_cache.sqlite');
    NativeDatabase cacheFileDatabase() =>
        NativeDatabase(cacheFile, setup: AppDatabase.configureConnection);

    // The first open copies and commits, and then the drop fails.
    final interrupted = AppDatabase(
      schema.newConnection().interceptWith(_DropsFail()),
    );
    final firstCache = CacheDatabase(cacheFileDatabase(), legacy: interrupted);
    await expectLater(
      firstCache.customSelect('SELECT 1').get(),
      throwsA(isA<StateError>()),
    );
    await firstCache.close();
    await interrupted.close();
    expect(legacyTablesIn(schema), [
      'legacy_alert_history',
      'legacy_occurrences',
      'legacy_sync_log',
    ]);
    // The setting stays with them until the next open has checked the copy.
    final stillThere = AppDatabase(schema.newConnection());
    expect(await expectedAlertsSetting(stillThere), fixture.expectedAlertsJson);
    await stillThere.close();

    // The next open, in another process or the next headless sync, finds the
    // copy done and the old tables still there: it must add nothing a second
    // time, and drop them.
    final reopened = AppDatabase(schema.newConnection());
    addTearDown(reopened.close);
    final secondCache = CacheDatabase(cacheFileDatabase(), legacy: reopened);
    addTearDown(secondCache.close);

    await expectHolds(secondCache, fixture);
    expect(legacyTablesIn(schema), isEmpty);
    expect(await expectedAlertsSetting(reopened), isNull);
  });

  test('a copy that fails leaves the old tables for the next open', () async {
    final fixture = Schema2Cache();
    final schema = await schema2With(fixture);
    final dir = Directory.systemTemp.createTempSync('tminus_move_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cacheFile = File('${dir.path}/tminus_cache.sqlite');
    NativeDatabase cacheFileDatabase() =>
        NativeDatabase(cacheFile, setup: AppDatabase.configureConnection);

    // A cache file that refuses every meeting, as a full disk would refuse a
    // write.
    final prepared = CacheDatabase(cacheFileDatabase());
    await prepared.customStatement(
      'CREATE TRIGGER no_meetings BEFORE INSERT ON occurrences BEGIN '
      "SELECT RAISE(ABORT, 'the cache cannot be written'); END",
    );
    await prepared.close();

    // The first open cannot write the cache. The old tables are the only copy
    // of the meetings, so nothing may drop them.
    final failing = AppDatabase(schema.newConnection());
    final stuck = CacheDatabase(cacheFileDatabase(), legacy: failing);
    await expectLater(
      stuck.customSelect('SELECT 1').get(),
      throwsA(
        predicate<Object>(
          (e) => '$e'.contains('the cache cannot be written'),
          'the refusal of the write',
        ),
      ),
    );
    await stuck.close();
    await failing.close();
    expect(legacyTablesIn(schema), [
      'legacy_alert_history',
      'legacy_occurrences',
      'legacy_sync_log',
    ]);
    expect(
      schema.rawDatabase.select('SELECT * FROM legacy_occurrences'),
      hasLength(fixture.meetings.length),
    );
    // So is the setting: it is as much the only copy as they are.
    final stillThere = AppDatabase(schema.newConnection());
    expect(await expectedAlertsSetting(stillThere), fixture.expectedAlertsJson);
    await stillThere.close();

    // The next open can write, and every row arrives.
    final unblocked = CacheDatabase(cacheFileDatabase());
    await unblocked.customStatement('DROP TRIGGER no_meetings');
    await unblocked.close();
    final reopened = AppDatabase(schema.newConnection());
    addTearDown(reopened.close);
    final cache = CacheDatabase(cacheFileDatabase(), legacy: reopened);
    addTearDown(cache.close);

    await expectHolds(cache, fixture);
    expect(legacyTablesIn(schema), isEmpty);
  });

  test(
    'a row that is already in the cache wins over the one set aside',
    () async {
      final fixture = Schema2Cache();
      final schema = await schema2With(fixture);
      final dir = Directory.systemTemp.createTempSync('tminus_move_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cacheFile = File('${dir.path}/tminus_cache.sqlite');
      NativeDatabase cacheFileDatabase() =>
          NativeDatabase(cacheFile, setup: AppDatabase.configureConnection);

      // Another isolate has copied and has since fetched this meeting again,
      // with a new title, and synced again, with other alerts to expect.
      final other = CacheDatabase(cacheFileDatabase());
      final newer = fixture.meetings.first.copyWith(
        title: 'Moved to the board',
      );
      await OccurrenceRepository(other)
          .replaceForSource(newer.sourceId, [newer]);
      await CacheValueRepository(other)
          .setString(Schema2Cache.expectedAlertsKey, '[]');
      await other.close();

      final upgraded = AppDatabase(schema.newConnection());
      addTearDown(upgraded.close);
      final cache = CacheDatabase(cacheFileDatabase(), legacy: upgraded);
      addTearDown(cache.close);

      final contents = await contentsOf(cache);
      // The newer row stays, and the rest of the old rows are added to it.
      expect(contents.meetings.first, newer);
      expect(contents.meetings.skip(1), fixture.meetings.skip(1));
      expect(contents.meetings, hasLength(fixture.meetings.length));
      expect(
        await CacheValueRepository(cache)
            .getString(Schema2Cache.expectedAlertsKey),
        '[]',
      );
      expect(await expectedAlertsSetting(upgraded), isNull);
    },
  );

  test('two isolates opening at once copy once', () async {
    final fixture = Schema2Cache(meetings: 40);
    // Several rounds, because the interleaving of the two opens is up to the
    // scheduler.
    for (var round = 0; round < 4; round++) {
      final dir = Directory.systemTemp.createTempSync('tminus_two_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final mainFile = File('${dir.path}/tminus.sqlite');
      final cacheFile = File('${dir.path}/tminus_cache.sqlite');

      // A schema 2 file with the cache's rows in it, as a Plan 5 build left it.
      final old = main_schemas.GeneratedHelper().databaseForVersion(
        NativeDatabase(mainFile),
        2,
      );
      await fixture.insertInto((sql, args) => old.customStatement(sql, args));
      await old.close();

      // What each isolate has: its own connection to each file, set up as
      // `AppDatabase.open` and `CacheDatabase.open` set them up.
      final mains = [
        for (var i = 0; i < 2; i++)
          AppDatabase(
            NativeDatabase.createInBackground(
              mainFile,
              setup: AppDatabase.configureConnection,
            ),
          ),
      ];
      final caches = [
        for (final m in mains)
          CacheDatabase(
            NativeDatabase.createInBackground(
              cacheFile,
              setup: AppDatabase.configureConnection,
            ),
            legacy: m,
          ),
      ];
      // Closed here when the test fails half way, so that nothing holds the
      // files when their directory is deleted.
      addTearDown(() async {
        for (final c in caches) {
          await c.close();
        }
        for (final m in mains) {
          await m.close();
        }
      });

      // Both open together: the upgrade of the main file, the creation of the
      // cache file and the move all race.
      await Future.wait([
        for (final c in caches) c.customSelect('SELECT 1').get(),
      ]);

      for (final c in caches) {
        await expectHolds(c, fixture);
      }
      final counts = await caches.first
          .customSelect(
            'SELECT (SELECT count(*) FROM occurrences) AS meetings, '
            '(SELECT count(*) FROM alert_history) AS history, '
            '(SELECT count(*) FROM sync_log) AS log, '
            '(SELECT count(*) FROM cache_values) AS cache_values',
          )
          .getSingle();
      expect(counts.data, {
        'meetings': fixture.meetings.length,
        'history': fixture.history.length,
        'log': fixture.log.length,
        // The expected alerts, and the marker of the copy: once each.
        'cache_values': 2,
      });
      expect(await expectedAlertsSetting(mains.first), isNull);
      final legacy = await mains.first
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name LIKE 'legacy_%'",
          )
          .get();
      expect(legacy, isEmpty, reason: 'round $round');

      for (final c in caches) {
        await c.close();
      }
      for (final m in mains) {
        await m.close();
      }
    }
  });

  test('the move reads the old tables where no other isolate can drop them', () async {
    // An isolate that has copied drops the legacy tables. Another one that has
    // found them but not yet read them must not find them gone: it would fail
    // to open. So it reads them in a transaction, which keeps every other
    // connection from writing, and a drop is a write.
    final fixture = Schema2Cache();
    final dir = Directory.systemTemp.createTempSync('tminus_read_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final mainFile = File('${dir.path}/tminus.sqlite');
    final old = main_schemas.GeneratedHelper().databaseForVersion(
      NativeDatabase(mainFile),
      2,
    );
    await fixture.insertInto((sql, args) => old.customStatement(sql, args));
    await old.close();

    // Another connection to the file, which does not wait for a lock.
    final other = sqlite3.open(mainFile.path);
    addTearDown(other.close);
    other.execute('PRAGMA busy_timeout = 0');
    var dropped = false;
    var kept = false;
    void dropBehindTheRead() {
      try {
        other.execute('DROP TABLE legacy_occurrences');
        dropped = true;
      } on SqliteException {
        kept = true; // the database is locked
      }
    }

    final upgraded = AppDatabase(
      NativeDatabase(
        mainFile,
        setup: AppDatabase.configureConnection,
      ).interceptWith(_BeforeTheRead(dropBehindTheRead)),
    );
    addTearDown(upgraded.close);
    final cache = CacheDatabase(memory(), legacy: upgraded);
    addTearDown(cache.close);

    await expectHolds(cache, fixture);

    expect(kept, isTrue, reason: 'the table was locked against a drop');
    expect(dropped, isFalse);
  });

  test('the move copies tables of more than one page', () async {
    // 1,100 meetings are three pages of 500, and so are a history and a log
    // that long.
    final fixture = Schema2Cache(meetings: 1100);
    final schema = await schema2With(fixture);
    final upgraded = AppDatabase(schema.newConnection());
    addTearDown(upgraded.close);
    // Past the three rows each the fixture has of those two.
    for (var i = 0; i < 1100; i++) {
      schema.rawDatabase.execute(
        'INSERT INTO alert_history (type, alert_id, occurrence_key, '
        'start_utc_ms, at_utc_ms) VALUES (?, ?, ?, ?, ?)',
        ['fired', 'bulk-$i', 'k', 1, 1000 + i],
      );
      schema.rawDatabase.execute(
        'INSERT INTO sync_log (source_id, at_utc_ms, outcome) '
        'VALUES (?, ?, ?)',
        ['work', 1000 + i, 'success'],
      );
    }
    final cache = CacheDatabase(memory(), legacy: upgraded);
    addTearDown(cache.close);

    final counts = await cache
        .customSelect(
          'SELECT (SELECT count(*) FROM occurrences) AS meetings, '
          '(SELECT count(*) FROM alert_history) AS history, '
          '(SELECT count(*) FROM sync_log) AS log',
        )
        .getSingle();
    expect(counts.data, {
      'meetings': 1100,
      'history': fixture.history.length + 1100,
      'log': fixture.log.length + 1100,
    });
    // The rows are the right ones, first and last.
    final meetings = await OccurrenceRepository(cache)
        .between(everything.$1, everything.$2);
    expect(meetings.first, fixture.meetings.first);
    expect(meetings.last, fixture.meetings.last);
    // Auto-increment ids carry over, so the next one cannot clash with them.
    final next = AlertHistoryEntry(
      type: AlertEventType.fired,
      alertId: 'after-the-move',
      occurrenceKey: 'k',
      startUtc: Schema2Cache.start,
      atUtc: Schema2Cache.start,
    );
    expect(await AlertHistoryRepository(cache).record(next), isTrue);
    expect(
      await AlertHistoryRepository(cache).recent(limit: 100000),
      contains(next),
    );
  });
}
