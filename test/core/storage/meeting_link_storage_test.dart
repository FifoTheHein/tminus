import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/meeting_link.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import '../fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late MeetingLinkRepository links;

  setUp(() {
    db = openTestDatabase();
    links = MeetingLinkRepository(db);
  });
  tearDown(() => db.close());

  final eight = DateTime.utc(2026, 10, 6, 8);

  // The link for the copy `sourceId|uid|2026-10-06T08:00:00.000Z`. Unless
  // given, the meeting key is the feed copy of 'sprint'.
  MeetingLink link(
    String sourceId,
    String uid, {
    String? meeting,
    DateTime? end,
    bool oneOff = true,
    MeetingMatch matchedBy = MeetingMatch.fingerprint,
  }) => MeetingLink(
    copyKey: EventOccurrence.makeKey(sourceId, uid, eight),
    meetingKey: meeting ?? EventOccurrence.makeKey('work', 'sprint', eight),
    sourceId: sourceId,
    uid: uid,
    oneOff: oneOff,
    endUtc: end ?? eight.add(const Duration(minutes: 30)),
    matchedBy: matchedBy,
  );

  test('apply upserts and deletes in one transaction', () async {
    final phone = link('phone', '9', matchedBy: MeetingMatch.uid);
    final feed = link(
      'work',
      'sprint',
      end: DateTime.utc(2026, 10, 6, 8, 30, 15, 250),
    );
    final other = link(
      'work',
      'review',
      meeting: EventOccurrence.makeKey('work', 'review', eight),
      matchedBy: MeetingMatch.remembered,
    );
    await links.apply(upsert: [feed, other, phone], delete: {});

    // Sorted by copy key, every field kept (milliseconds too).
    final firstRead = await links.all();
    expect(firstRead, [phone, other, feed]);
    // Each link's own match, read through the field and not through ==.
    expect(firstRead.map((l) => l.matchedBy), [
      MeetingMatch.uid,
      MeetingMatch.remembered,
      MeetingMatch.fingerprint,
    ]);
    final stored = await db
        .customSelect('SELECT DISTINCT matched_by FROM meeting_links')
        .get();
    expect(stored.map((r) => r.read<String>('matched_by')).toSet(), {
      'uid',
      'fingerprint',
      'remembered',
    }, reason: 'the match is stored by name');

    // One call upserts (replacing the feed's link) and deletes.
    final moved = link(
      'work',
      'sprint',
      meeting: phone.copyKey,
      end: DateTime.utc(2026, 10, 6, 9),
      matchedBy: MeetingMatch.remembered,
    );
    final debug = link('debug', 'x');
    await links.apply(upsert: [moved, debug], delete: {phone.copyKey});
    final secondRead = await links.all();
    expect(secondRead, [debug, other, moved]);
    expect(secondRead.map((l) => l.matchedBy), [
      MeetingMatch.fingerprint, // debug
      MeetingMatch.remembered, // other
      MeetingMatch.remembered, // moved, replacing the feed's fingerprint
    ]);

    // A statement in the middle fails: the delete and the upsert before it
    // must not stick. The trigger fails the insert of one copy key.
    await db.customStatement(
      'CREATE TRIGGER fail_poison BEFORE INSERT ON meeting_links '
      "WHEN NEW.copy_key LIKE 'poison|%' "
      "BEGIN SELECT RAISE(ABORT, 'poisoned'); END",
    );
    final before = await links.all();
    await expectLater(
      links.apply(
        upsert: [link('work', 'fresh'), link('poison', 'x')],
        delete: {other.copyKey},
      ),
      throwsA(
        predicate<Object>(
          (e) => '$e'.contains('poisoned'),
          'the failure raised by the trigger',
        ),
      ),
    );
    expect(await links.all(), before);
  });

  test(
    'a key in both upsert and delete ends up with the upserted link',
    () async {
      // Same copy key and the same fields: the two links differ only in how
      // they were matched. So the checks below can hold only if that is
      // compared by ==, stored, and read back.
      final old = link('work', 'sprint', matchedBy: MeetingMatch.fingerprint);
      final rematched = link(
        'work',
        'sprint',
        matchedBy: MeetingMatch.remembered,
      );
      expect(rematched, isNot(old));

      await links.apply(upsert: [old], delete: {});
      expect((await links.all()).single.matchedBy, MeetingMatch.fingerprint);

      await links.apply(upsert: [rematched], delete: {old.copyKey});

      final stored = (await links.all()).single;
      expect(stored, rematched);
      expect(stored, isNot(old));
      expect(stored.matchedBy, MeetingMatch.remembered);
    },
  );

  test('deleteEndedBefore keeps links of copies that end later', () async {
    final cutoff = DateTime.utc(2026, 10, 7, 8);
    final longGone = link(
      'work',
      'a',
      end: cutoff.subtract(const Duration(days: 3)),
    );
    final justBefore = link(
      'work',
      'b',
      end: cutoff.subtract(const Duration(milliseconds: 1)),
    );
    final atCutoff = link('work', 'c', end: cutoff);
    final later = link('phone', 'd', end: cutoff.add(const Duration(hours: 5)));
    await links.apply(
      upsert: [longGone, justBefore, atCutoff, later],
      delete: {},
    );

    expect(await links.deleteEndedBefore(cutoff), 2);
    expect(await links.all(), [later, atCutoff]);
  });

  test('deleting a source keeps its links', () async {
    final sources = SourceRepository(db);
    final cache = OccurrenceRepository(db);
    await sources.save(
      const SourceConfig(
        id: 'work',
        name: 'Work Outlook',
        color: 0xFF6AA0F5,
        kind: SourceKind.ics,
        secureStorageKey: 'ics_url_work',
      ),
    );
    final copy = occ(sourceId: 'work', uid: 'sprint', start: eight);
    await cache.replaceForSource('work', [copy]);
    final kept = link('work', 'sprint', end: copy.endUtc);
    await links.apply(upsert: [kept], delete: {});

    await sources.delete('work');

    expect(await cache.countForSource('work'), 0, reason: 'the cache cascades');
    expect(await links.all(), [kept], reason: 'the link does not');
  });

  test('a link can name a source that does not exist', () async {
    // Foreign keys are on (see app_database_test); links have none.
    final orphan = link('removed', 'sprint');
    await links.apply(upsert: [orphan], delete: {});
    expect(await links.all(), [orphan]);

    final references = await db
        .customSelect('PRAGMA foreign_key_list(meeting_links)')
        .get();
    expect(references, isEmpty);
  });
}
