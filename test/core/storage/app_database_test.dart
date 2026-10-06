import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/profile_mapping.dart';

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

  test('schema version 1 with every table from spec §5', () async {
    expect(db.schemaVersion, 1);
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
}
