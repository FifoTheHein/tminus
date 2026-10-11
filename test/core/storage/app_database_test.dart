import 'package:drift/drift.dart' hide isNull;
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
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_mapping.dart';
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

  test('every table from spec §5 exists', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .get();
    expect(
      rows.map((r) => r.read<String>('name')),
      containsAll([
        'alert_history',
        'occurrences',
        'overrides',
        'profiles',
        'quiet_state',
        'rules',
        'settings',
        'sources',
        'sync_log',
      ]),
    );
  });

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

  test(
    'foreign keys are on: deleting a source deletes its occurrences',
    () async {
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'work',
              name: 'Work',
              color: 0xFF6AA0F5,
              kind: SourceKind.ics,
            ),
          );
      await db
          .into(db.occurrences)
          .insert(
            OccurrencesCompanion.insert(
              occurrenceKey: 'work|a|2026-10-06T08:00:00.000Z',
              sourceId: 'work',
              uid: 'a',
              originalStartUtcMs: 0,
              title: 'x',
              startUtcMs: 0,
              endUtcMs: 1,
              allDay: false,
              busyStatus: BusyStatus.busy,
              declined: false,
              cancelled: false,
              calendarColor: 0,
            ),
          );
      await (db.delete(db.sources)..where((s) => s.id.equals('work'))).go();
      expect(await db.select(db.occurrences).get(), isEmpty);
    },
  );

  test('sources table has no column that could hold a URL', () async {
    final cols = await db.customSelect('PRAGMA table_info(sources)').get();
    final names = cols.map((c) => c.read<String>('name')).toList();
    expect(names, contains('secure_storage_key'));
    expect(names.where((n) => n.contains('url')), isEmpty);
  });

  group('schema 2', () {
    final verifier = SchemaVerifier(GeneratedHelper());
    const strict = ValidationOptions(validateDropped: true);

    // The migrated database and the one from setUp are both an AppDatabase.
    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    tearDownAll(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
    );

    test('a fresh database is schema 2', () async {
      expect(db.schemaVersion, 2);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);

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
      final columns = await db
          .customSelect('PRAGMA table_info(occurrences)')
          .get();
      expect(columns.map((c) => c.read<String>('name')), contains('ical_uid'));

      // Links hold no reference to sources, so they outlive a deleted source.
      final keys = await db
          .customSelect('PRAGMA foreign_key_list(meeting_links)')
          .get();
      expect(keys, isEmpty);

      // Created from scratch, it is exactly the schema dumped in
      // drift_schemas/, so a change to tables.dart needs a new version.
      await verifier.migrateAndValidate(db, 2, options: strict);
    });

    test('schema 1 upgrades to 2 keeping sources, occurrences, overrides and '
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
      await verifier.migrateAndValidate(migrated, 2, options: strict);

      final version = await migrated
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 2);

      // Everything installed before the upgrade is still there.
      final sources = SourceRepository(migrated);
      expect(await sources.all(), [work]);
      expect(await sources.syncState('work'), syncState);
      final cache = OccurrenceRepository(migrated);
      expect(await cache.countForSource('work'), 1);
      expect(await cache.byKey(copy.key), copy);
      expect(
        await OverrideRepository(migrated).all(),
        unorderedEquals([occurrenceOverride, seriesOverride]),
      );
      expect(await AlertHistoryRepository(migrated).recent(), [dismissed]);

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
        // leaves behind, and what a second connection finds.
        final schema = await verifier.schemaAt(2);
        addTearDown(schema.close);
        schema.rawDatabase.execute('PRAGMA user_version = 1');

        final migrated = AppDatabase(schema.newConnection());
        addTearDown(migrated.close);
        await verifier.migrateAndValidate(migrated, 2, options: strict);

        final version = await migrated
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 2);
      },
    );

    test('a downgrade is refused and leaves the stored version', () async {
      // A schema 3 file, opened by a build that only knows schema 2.
      final schema = await verifier.schemaAt(2);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      raw.execute('PRAGMA user_version = 3');

      final opened = AppDatabase(schema.newConnection());
      addTearDown(opened.close);
      await expectLater(
        opened.customSelect('SELECT 1').get(),
        throwsA(
          predicate<Object>(
            (e) => '$e'.contains('Downgrade from schema 3 to 2'),
            'the refusal of the downgrade',
          ),
        ),
      );

      // Drift stores its own version after the upgrade callback returns.
      expect(raw.select('PRAGMA user_version').single['user_version'], 3);
    });
  });
}
