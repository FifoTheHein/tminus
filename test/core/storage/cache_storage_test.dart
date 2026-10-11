import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import '../fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;

  const work = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics_url_work',
    defaultProfileId: 'meeting',
  );
  const phone = SourceConfig(
    id: 'personal',
    name: 'Personal Google',
    color: 0xFF5BC27A,
    kind: SourceKind.device,
    deviceCalendarId: '7',
  );

  setUp(() async {
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    await sources.save(work);
    await sources.save(phone);
  });
  tearDown(() => db.close());

  group('SourceRepository', () {
    test('round trip, sorted by name', () async {
      expect(await sources.all(), [phone, work]);
      expect(await sources.byId('work'), work);
    });

    test('save updates config but never resets sync state', () async {
      final state = SourceSyncState(
        lastAttemptUtc: DateTime.utc(2026, 10, 6, 6),
        lastSuccessUtc: DateTime.utc(2026, 10, 6, 6),
        httpEtag: '"abc"',
        httpLastModified: 'Tue, 06 Oct 2026 06:00:00 GMT',
        emptyStreak: 1,
      );
      await sources.updateSyncState('work', state);
      await sources.save(work.copyWith(name: 'Work'));
      expect((await sources.byId('work'))!.name, 'Work');
      expect(await sources.syncState('work'), state);
    });

    test('a new source starts with an empty sync state', () async {
      expect(await sources.syncState('personal'), SourceSyncState());
    });

    test('delete removes the source and its occurrences', () async {
      await cache.replaceForSource('work', [occ(sourceId: 'work')]);
      await sources.delete('work');
      expect(await sources.byId('work'), isNull);
      expect(await cache.countForSource('work'), 0);
    });
  });

  group('OccurrenceRepository', () {
    final full = occ(
      sourceId: 'work',
      uid: 'full',
      seriesUid: 'series-1',
      title: 'Sprint planning',
      location: 'Teams',
      organizer: 'Thandi M.',
      description: 'Agenda',
      joinUrl: 'https://teams.microsoft.com/l/meetup-join/1',
      busyStatus: BusyStatus.tentative,
      declined: true,
      cancelled: true,
      color: 0xFF112233,
    ).copyWith(warnings: {OccurrenceWarning.tzFallback});

    test('round trips every field', () async {
      await cache.replaceForSource('work', [full]);
      expect(await cache.byKey(full.key), full);
    });

    test('icalUid round-trips', () async {
      final withUid = occ(
        sourceId: 'work',
        uid: 'with',
      ).copyWith(icalUid: '040000008200E00074C5B7101A82E008');
      final without = occ(sourceId: 'work', uid: 'without');
      await cache.replaceForSource('work', [withUid, without]);

      // `==` compares icalUid, so these also show the other fields survived.
      expect(await cache.byKey(withUid.key), withUid);
      expect(await cache.byKey(without.key), without);
      expect(
        (await cache.byKey(withUid.key))!.icalUid,
        '040000008200E00074C5B7101A82E008',
      );
      expect((await cache.byKey(without.key))!.icalUid, isNull);

      final listed = await cache.between(
        DateTime.utc(2026, 10, 6),
        DateTime.utc(2026, 10, 7),
      );
      expect(
        {for (final o in listed) o.uid: o.icalUid},
        {'with': '040000008200E00074C5B7101A82E008', 'without': null},
      );
    });

    test('a key from a microsecond instant survives a round trip', () async {
      final o = occ(
        sourceId: 'work',
        uid: 'micro',
        start: DateTime.utc(2026, 10, 6, 8, 0, 0, 0, 123),
      );
      await cache.replaceForSource('work', [o]);
      final reloaded = (await cache.between(
        DateTime.utc(2026, 10, 6),
        DateTime.utc(2026, 10, 7),
      )).single;
      expect(reloaded.key, o.key);
      expect(await cache.byKey(o.key), o);
    });

    test('replaceForSource swaps one source only', () async {
      await cache.replaceForSource('work', [occ(sourceId: 'work', uid: 'a')]);
      await cache.replaceForSource('personal', [
        occ(sourceId: 'personal', uid: 'p'),
      ]);
      await cache.replaceForSource('work', [
        occ(sourceId: 'work', uid: 'b'),
        occ(sourceId: 'work', uid: 'c'),
      ]);
      expect(await cache.countForSource('work'), 2);
      expect(await cache.countForSource('personal'), 1);
    });

    test('replaceForSource rejects another source\'s occurrence', () async {
      expect(
        () => cache.replaceForSource('work', [occ(sourceId: 'personal')]),
        throwsArgumentError,
      );
    });

    test('between returns overlapping occurrences sorted by start', () async {
      DateTime at(int h, [int m = 0]) => DateTime.utc(2026, 10, 6, h, m);
      await cache.replaceForSource('work', [
        occ(sourceId: 'work', uid: 'late', start: at(9)),
        occ(sourceId: 'work', uid: 'early', start: at(7)),
        occ(sourceId: 'work', uid: 'ended', start: at(5)), // ends 05:30
        occ(sourceId: 'work', uid: 'running', start: at(5, 45)), // ends 06:15
        occ(sourceId: 'work', uid: 'after', start: at(10)),
      ]);
      final got = await cache.between(at(6), at(10));
      expect(got.map((o) => o.uid), ['running', 'early', 'late']);
    });

    test('deleteEndedBefore prunes old occurrences', () async {
      await cache.replaceForSource('work', [
        occ(sourceId: 'work', uid: 'old', start: DateTime.utc(2026, 10, 1)),
        occ(sourceId: 'work', uid: 'new', start: DateTime.utc(2026, 10, 6)),
      ]);
      expect(await cache.deleteEndedBefore(DateTime.utc(2026, 10, 5)), 1);
      expect(await cache.countForSource('work'), 1);
    });
  });
}
