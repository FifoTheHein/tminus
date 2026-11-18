import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/meeting_link.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/cache_database.dart';
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_mapping.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import '../../generated_migrations/schema.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('native SQLite loads under flutter test', () async {
    final row = await db
        .customSelect('SELECT sqlite_version() AS v')
        .getSingle();
    expect(row.read<String>('v'), matches(RegExp(r'^3\.\d+\.\d+$')));
  });

  test(
    'every table of the main database exists, and not the cache tables',
    () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
          )
          .get();
      final names = rows.map((r) => r.read<String>('name')).toList();
      expect(
        names,
        containsAll([
          'meeting_links',
          'overrides',
          'profiles',
          'quiet_state',
          'rules',
          'settings',
          'sources',
        ]),
      );
      // The occurrence cache, the alert history and the sync log are in the
      // cache database, which the backup rules leave out (Plan 6 decision 4).
      expect(
        names.where(
          (n) =>
              n.contains('occurrences') ||
              n.contains('alert_history') ||
              n.contains('sync_log'),
        ),
        isEmpty,
      );
    },
  );

  test('built-in profiles are seeded in order', () async {
    final rows = await (db.select(
      db.profiles,
    )..orderBy([(p) => OrderingTerm.asc(p.position)])).get();
    expect(rows.map(profileFromRow).toList(), BuiltInProfiles.all);
  });

  test('seeding never overwrites an edited built-in', () async {
    await (db.update(db.profiles)..where((p) => p.id.equals('meeting'))).write(
      const ProfilesCompanion(name: Value('Work meeting')),
    );
    await db.seedBuiltInProfiles();
    final meeting = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals('meeting'))).getSingle();
    expect(meeting.name, 'Work meeting');
  });

  test('foreign keys are on', () async {
    // No table has a foreign key since the occurrences moved to the cache
    // database, which has none to sources, but the pragma stays for the next
    // table that needs one.
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });

  test('a deleted row leaves no bytes behind in the file', () async {
    // The file is backed up, and a delete that only frees the page leaves what
    // the row held in it. The connection zeroes it (`secure_delete`).
    final dir = Directory.systemTemp.createTempSync('tminus_secure_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/tminus.sqlite');
    final database = AppDatabase(
      NativeDatabase(file, setup: AppDatabase.configureConnection),
    );
    addTearDown(database.close);
    const secret = 'Quarterly results rehearsal for the Zephyr programme';
    await SettingsRepository(database).setString('probe', secret);
    await database.checkpoint();
    expect(bytesHolding(file, [secret]), [
      secret,
    ], reason: 'the row is in the file before');

    await (database.delete(
      database.settings,
    )..where((s) => s.name.equals('probe'))).go();
    await database.checkpoint();

    expect(bytesHolding(file, [secret]), isEmpty);
  });

  test('sources table has no column that could hold a URL', () async {
    final cols = await db.customSelect('PRAGMA table_info(sources)').get();
    final names = cols.map((c) => c.read<String>('name')).toList();
    expect(names, contains('secure_storage_key'));
    expect(names.where((n) => n.contains('url')), isEmpty);
  });

  group('schema 3', () {
    final verifier = SchemaVerifier(GeneratedHelper());
    const strict = ValidationOptions(validateDropped: true);

    // Straight after the upgrade the cache's old tables are still there, set
    // aside as `legacy_*` until the cache database has moved their rows, so
    // only what the schema has is checked. Once they are gone the check is
    // strict.
    const afterUpgrade = ValidationOptions(validateDropped: false);

    // The migrated database and the one from setUp are both an AppDatabase.
    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    tearDownAll(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
    );

    DatabaseConnection memory() => DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    );

    Future<int> storedVersion(AppDatabase database) async {
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      return version.read<int>('user_version');
    }

    test('a fresh database is schema 3', () async {
      expect(db.schemaVersion, 3);
      expect(await storedVersion(db), 3);

      final entities = await db
          .customSelect('SELECT name FROM sqlite_master')
          .get();
      expect(
        entities.map((r) => r.read<String>('name')),
        containsAll([
          'meeting_links',
          'meeting_links_source_uid',
          'meeting_links_meeting_key',
        ]),
      );

      // Links hold no reference to sources, so they outlive a deleted source.
      final keys = await db
          .customSelect('PRAGMA foreign_key_list(meeting_links)')
          .get();
      expect(keys, isEmpty);

      // Created from scratch, it is exactly the schema dumped in
      // drift_schemas/, so a change to tables.dart needs a new version.
      await verifier.migrateAndValidate(db, 3, options: strict);
    });

    test('v1 to v3 and v2 to v3 migrate and validate', () async {
      for (final from in [1, 2]) {
        final schema = await verifier.schemaAt(from);
        addTearDown(schema.close);
        final migrated = AppDatabase(schema.newConnection());
        addTearDown(migrated.close);

        // Straight after the upgrade the cache's tables are set aside.
        await verifier.migrateAndValidate(migrated, 3, options: afterUpgrade);
        expect(await storedVersion(migrated), 3, reason: 'from schema $from');

        // The cache database moves their rows and drops them, and then nothing
        // but schema 3 is left.
        final cache = CacheDatabase(memory(), legacy: migrated);
        addTearDown(cache.close);
        await cache.customSelect('SELECT 1').get();
        await verifier.migrateAndValidate(migrated, 3, options: strict);
      }
    });

    test('schema 1 upgrades to 3 keeping sources, occurrences, overrides and '
        'history', () async {
      final schema = await verifier.schemaAt(1);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      List<String> columnsOf(String table) => [
        for (final r in raw.select('PRAGMA table_info($table)'))
          r['name'] as String,
      ];

      // Really schema 1: none of the schema 2 additions exist yet.
      expect(raw.select('PRAGMA user_version').single['user_version'], 1);
      expect(columnsOf('occurrences'), isNot(contains('ical_uid')));
      expect(columnsOf('meeting_links'), isEmpty);

      // Rows as an installed schema 1 app holds them. Instants are ms,
      // enums are stored by name.
      const work = SourceConfig(
        id: 'work',
        name: 'Work Outlook',
        color: 0xFF6AA0F5,
        kind: SourceKind.ics,
        secureStorageKey: 'ics_url_work',
        defaultProfileId: 'meeting',
      );
      final attempted = DateTime.utc(2026, 10, 6, 6, 5);
      final succeeded = DateTime.utc(2026, 10, 6, 6);
      final syncState = SourceSyncState(
        lastAttemptUtc: attempted,
        lastSuccessUtc: succeeded,
        httpEtag: '"abc"',
        httpLastModified: 'Tue, 06 Oct 2026 06:00:00 GMT',
        emptyStreak: 1,
      );
      raw.execute(
        'INSERT INTO sources (id, name, color, kind, secure_storage_key, '
        'default_profile_id, enabled, last_attempt_utc_ms, '
        'last_success_utc_ms, http_etag, http_last_modified, empty_streak) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          work.id,
          work.name,
          work.color,
          'ics',
          work.secureStorageKey,
          work.defaultProfileId,
          1,
          attempted.millisecondsSinceEpoch,
          succeeded.millisecondsSinceEpoch,
          syncState.httpEtag,
          syncState.httpLastModified,
          syncState.emptyStreak,
        ],
      );

      final start = DateTime.utc(2026, 10, 6, 8);
      final copy = EventOccurrence(
        sourceId: 'work',
        uid: 'uid1',
        originalStartUtc: start,
        seriesUid: 'series-1',
        title: 'Sprint planning',
        location: 'Room 4',
        organizer: 'Thandi M.',
        description: 'Agenda',
        joinUrl: 'https://teams.microsoft.com/l/meetup-join/1',
        startUtc: start.add(const Duration(hours: 1)),
        endUtc: start.add(const Duration(hours: 1, minutes: 30)),
        busyStatus: BusyStatus.tentative,
        cancelled: true,
        calendarColor: 0xFF6AA0F5,
        warnings: {OccurrenceWarning.tzFallback},
      );
      raw.execute(
        'INSERT INTO occurrences (occurrence_key, source_id, uid, '
        'original_start_utc_ms, series_uid, title, location, organizer, '
        'description, join_url, start_utc_ms, end_utc_ms, all_day, '
        'busy_status, declined, cancelled, calendar_color, warnings) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          copy.key,
          copy.sourceId,
          copy.uid,
          copy.originalStartUtc.millisecondsSinceEpoch,
          copy.seriesUid,
          copy.title,
          copy.location,
          copy.organizer,
          copy.description,
          copy.joinUrl,
          copy.startUtc.millisecondsSinceEpoch,
          copy.endUtc.millisecondsSinceEpoch,
          0,
          'tentative',
          0,
          1,
          copy.calendarColor,
          'tzFallback',
        ],
      );

      final occurrenceOverride = EventOverride(
        scope: OverrideScope.occurrence,
        target: copy.key,
        enabled: false,
      );
      const seriesOverride = EventOverride(
        scope: OverrideScope.series,
        target: 'series-1',
        profileId: 'meeting',
      );
      raw.execute(
        'INSERT INTO overrides (scope, target, profile_id, enabled) '
        "VALUES ('occurrence', ?, NULL, 0), ('series', 'series-1', ?, NULL)",
        [copy.key, 'meeting'],
      );

      final dismissed = AlertHistoryEntry(
        type: AlertEventType.dismissedAll,
        alertId: 'alert-1',
        occurrenceKey: copy.key,
        startUtc: copy.startUtc,
        atUtc: copy.startUtc.subtract(const Duration(minutes: 5)),
        title: copy.title,
      );
      raw.execute(
        'INSERT INTO alert_history (type, alert_id, occurrence_key, '
        'start_utc_ms, at_utc_ms, title) VALUES (?, ?, ?, ?, ?, ?)',
        [
          'dismissedAll',
          dismissed.alertId,
          dismissed.occurrenceKey,
          dismissed.startUtc.millisecondsSinceEpoch,
          dismissed.atUtc.millisecondsSinceEpoch,
          dismissed.title,
        ],
      );

      final migrated = AppDatabase(schema.newConnection());
      addTearDown(migrated.close);
      await verifier.migrateAndValidate(migrated, 3, options: afterUpgrade);
      expect(await storedVersion(migrated), 3);

      // The schema 2 step ran before the schema 3 one: the cached copy that
      // was set aside has the column schema 2 added, with no value yet.
      expect(columnsOf('legacy_occurrences'), contains('ical_uid'));

      // The cache database moves the cached rows, and nothing but schema 3 is
      // left in the main database.
      final cacheDb = CacheDatabase(memory(), legacy: migrated);
      addTearDown(cacheDb.close);
      final cache = OccurrenceRepository(cacheDb);
      expect(await cache.countForSource('work'), 1);
      await verifier.migrateAndValidate(migrated, 3, options: strict);

      // Everything installed before the upgrade is still there.
      final sources = SourceRepository(migrated);
      expect(await sources.all(), [work]);
      expect(await sources.syncState('work'), syncState);
      expect(await cache.byKey(copy.key), copy);
      expect(
        await OverrideRepository(migrated).all(),
        unorderedEquals([occurrenceOverride, seriesOverride]),
      );
      expect(await AlertHistoryRepository(cacheDb).recent(), [dismissed]);

      // The cached copy has no iCal UID yet. The new column and table work.
      expect((await cache.byKey(copy.key))!.icalUid, isNull);
      final withUid = copy.copyWith(icalUid: 'ical-1');
      await cache.replaceForSource('work', [withUid]);
      expect((await cache.byKey(withUid.key))!.icalUid, 'ical-1');
      final links = MeetingLinkRepository(migrated);
      expect(await links.all(), isEmpty);
      final link = MeetingLink(
        copyKey: copy.key,
        meetingKey: copy.key,
        sourceId: 'work',
        uid: copy.uid,
        oneOff: false,
        endUtc: copy.endUtc,
        matchedBy: MeetingMatch.uid,
      );
      await links.apply(upsert: [link], delete: {});
      expect(await links.all(), [link]);
    });

    test(
      'the upgrade to schema 2 can run again on a database that already has it',
      () async {
        // What a run that stopped just before drift stored the new version
        // leaves behind, and what a second connection finds. This build goes on
        // to schema 3 from there.
        final schema = await verifier.schemaAt(2);
        addTearDown(schema.close);
        schema.rawDatabase.execute('PRAGMA user_version = 1');

        final migrated = AppDatabase(schema.newConnection());
        addTearDown(migrated.close);
        await verifier.migrateAndValidate(migrated, 3, options: afterUpgrade);

        expect(await storedVersion(migrated), 3);
      },
    );

    test('a schema 1 file whose schema 3 step already ran opens', () async {
      // What a second isolate finds when two open a schema 1 file at once and
      // the first has been through both steps, and what every run finds after
      // a crash between the commit of the schema 3 step and drift storing the
      // version: the shape of schema 3 with the version of schema 1. The column
      // that the schema 2 step adds has no table to go to.
      final schema = await verifier.schemaAt(3);
      addTearDown(schema.close);
      schema.rawDatabase.execute('PRAGMA user_version = 1');

      final migrated = AppDatabase(schema.newConnection());
      addTearDown(migrated.close);
      await verifier.migrateAndValidate(migrated, 3, options: strict);

      expect(await storedVersion(migrated), 3);
    });

    test('running the schema 3 step twice changes nothing', () async {
      // The second-isolate case of the schema 2 step, repeated for this one: a
      // run that stopped just before drift stored the new version, or a second
      // connection that opened the file at the same time, finds the step done
      // and the stored version still 2.
      final schema = await verifier.schemaAt(2);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      final fixture = Schema2Cache();
      await fixture.insertInto((sql, args) => raw.execute(sql, args));

      /// The tables, indexes and rows of the main file, as a comparable value.
      List<Object?> snapshot() => [
        for (final r in raw.select(
          'SELECT type, name FROM sqlite_master '
          "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
        ))
          '${r['type']} ${r['name']}',
        for (final table in [
          'legacy_occurrences',
          'legacy_alert_history',
          'legacy_sync_log',
        ])
          if (raw
              .select("SELECT 1 FROM sqlite_master WHERE name = '$table'")
              .isNotEmpty)
            raw.select('SELECT * FROM $table ORDER BY rowid').toList(),
      ];

      final first = AppDatabase(schema.newConnection());
      await first.customSelect('SELECT 1').get();
      await first.close();
      final done = snapshot();
      expect(done, contains('table legacy_occurrences'));
      expect(done, isNot(contains('table occurrences')));
      expect(raw.select('SELECT * FROM legacy_occurrences').length, 6);

      raw.execute('PRAGMA user_version = 2');
      final second = AppDatabase(schema.newConnection());
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();

      expect(snapshot(), done);
      expect(await storedVersion(second), 3);

      // And after the cache database has moved the rows and dropped the
      // legacy tables there is nothing left to set aside, and nothing fails.
      final cache = CacheDatabase(memory(), legacy: second);
      addTearDown(cache.close);
      await cache.customSelect('SELECT 1').get();
      final moved = snapshot();
      expect(moved, isNot(contains('table legacy_occurrences')));
      raw.execute('PRAGMA user_version = 2');
      await second.close();
      final third = AppDatabase(schema.newConnection());
      addTearDown(third.close);
      await third.customSelect('SELECT 1').get();

      expect(snapshot(), moved);
      expect(await storedVersion(third), 3);
    });

    test('a downgrade is refused and leaves the stored version', () async {
      // A schema 4 file, opened by a build that only knows schema 3.
      final schema = await verifier.schemaAt(3);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      raw.execute('PRAGMA user_version = 4');

      final opened = AppDatabase(schema.newConnection());
      addTearDown(opened.close);
      await expectLater(
        opened.customSelect('SELECT 1').get(),
        throwsA(
          predicate<Object>(
            (e) => '$e'.contains('Downgrade from schema 4 to 3'),
            'the refusal of the downgrade',
          ),
        ),
      );

      // Drift stores its own version after the upgrade callback returns.
      expect(raw.select('PRAGMA user_version').single['user_version'], 4);
    });
  });
}
