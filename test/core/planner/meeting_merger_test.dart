import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/meeting_link.dart';
import 'package:tminus/core/model/meeting_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/planner/meeting_merger.dart';

import '../fixtures.dart';

const phoneRank = SourceRank(kind: SourceKind.device, failing: false);
const failingPhoneRank = SourceRank(kind: SourceKind.device, failing: true);
const feedRank = SourceRank(kind: SourceKind.ics, failing: false);
const failingFeedRank = SourceRank(kind: SourceKind.ics, failing: true);
const debugRank = SourceRank(kind: SourceKind.debug, failing: false);

/// The phone calendar, three feeds and a debug source, all healthy.
const ranks = <String, SourceRank>{
  'phone': phoneRank,
  'feed': feedRank,
  'feed2': feedRank,
  'work': feedRank,
  'debug': debugRank,
};

final t0 = DateTime.utc(2026, 10, 6, 8); // 10:00 in Johannesburg
final t1 = DateTime.utc(2026, 10, 6, 9);
final t2 = DateTime.utc(2026, 10, 6, 10);

/// A copy of the same meeting by default ('Budget review' at [t0]). Pass
/// [icalUid] for what a feed copy always has: the UID is its own uid.
EventOccurrence copy(
  String sourceId,
  String uid, {
  String title = 'Budget review',
  DateTime? start,
  DateTime? originalStart,
  Duration length = const Duration(minutes: 30),
  String? seriesUid,
  String? icalUid,
  String? location,
  String? organizer,
  String? description,
  String? joinUrl,
  bool allDay = false,
  BusyStatus busyStatus = BusyStatus.busy,
  bool declined = false,
  bool cancelled = false,
  int color = blue,
}) {
  final c = occ(
    sourceId: sourceId,
    uid: uid,
    start: start ?? t0,
    originalStart: originalStart,
    length: length,
    seriesUid: seriesUid,
    title: title,
    location: location,
    organizer: organizer,
    description: description,
    joinUrl: joinUrl,
    allDay: allDay,
    busyStatus: busyStatus,
    declined: declined,
    cancelled: cancelled,
    color: color,
  );
  return icalUid == null ? c : c.copyWith(icalUid: icalUid);
}

/// The link the merger stores for [c] in the meeting [meetingKey].
MeetingLink linkOf(
  EventOccurrence c,
  String meetingKey, {
  MeetingMatch matchedBy = MeetingMatch.remembered,
}) => MeetingLink(
  copyKey: c.key,
  meetingKey: meetingKey,
  sourceId: c.sourceId,
  uid: c.uid,
  oneOff: c.seriesUid == null,
  endUtc: c.endUtc,
  matchedBy: matchedBy,
);

MergeResult run(
  List<EventOccurrence> copies, {
  List<MeetingLink> links = const [],
  Map<String, SourceRank> sources = ranks,
  bool enabled = true,
}) => MeetingMerger.merge(
  copies: copies,
  links: links,
  sources: sources,
  enabled: enabled,
);

/// The one meeting in [r], which must be a [MeetingOccurrence].
MeetingOccurrence theMeeting(MergeResult r) {
  expect(r.meetings, hasLength(1));
  final meeting = r.meetings.single;
  expect(meeting, isA<MeetingOccurrence>());
  return meeting as MeetingOccurrence;
}

/// The meeting in [r] planned under [key].
EventOccurrence meetingWithKey(MergeResult r, String key) =>
    r.meetings.singleWhere((m) => m.key == key);

/// The keys of the copies that [m] stands for.
List<String> copyKeys(EventOccurrence m) =>
    m is MeetingOccurrence ? [for (final c in m.copies) c.key] : [m.key];

/// Nothing merged: every copy comes back as itself, with no link written.
void expectAlone(MergeResult r, List<EventOccurrence> copies, {String? why}) {
  expect(r.meetings, hasLength(copies.length), reason: why);
  for (final c in copies) {
    expect(
      r.meetings.where((m) => identical(m, c)),
      hasLength(1),
      reason: '${why ?? ''} ${c.key} stays a plain copy',
    );
  }
  expect(r.upsert, isEmpty, reason: why);
  expect(r.delete, isEmpty, reason: why);
  expect(r.merged, 0, reason: why);
}

/// What must hold for any input.
void expectSane(
  MergeResult r,
  List<EventOccurrence> copies, {
  String reason = '',
}) {
  final inputKeys = {for (final c in copies) c.key};
  final keys = [for (final m in r.meetings) m.key];
  expect(keys.toSet(), hasLength(keys.length), reason: '$reason: unique keys');
  expect(keys, [...keys]..sort(), reason: '$reason: meetings in key order');

  final planned = [for (final m in r.meetings) ...copyKeys(m)];
  expect(planned.toSet(), hasLength(planned.length), reason: '$reason: once');
  expect(planned.toSet(), inputKeys, reason: '$reason: every copy planned');

  expect(r.timeSource.keys.toList(), keys, reason: '$reason: time sources');
  for (final m in r.meetings) {
    if (m is MeetingOccurrence) {
      final first = m.copies.first.sourceId;
      expect(m.timeSourceId, first, reason: '$reason: ${m.key} time source');
      expect(m.sourceId, first, reason: '$reason: ${m.key} source');
      expect(r.timeSource[m.key], first, reason: '$reason: ${m.key} map');
      final sources = {for (final c in m.copies) c.sourceId};
      expect(sources, hasLength(m.copies.length), reason: '$reason: sources');
    } else {
      expect(r.timeSource[m.key], m.sourceId, reason: '$reason: ${m.key}');
    }
  }

  final upserted = [for (final l in r.upsert) l.copyKey];
  expect(upserted.toSet(), hasLength(upserted.length), reason: reason);
  expect(r.delete.intersection(upserted.toSet()), isEmpty, reason: reason);
  expect(r.delete.difference(inputKeys), isEmpty, reason: reason);
  expect(r.delete.toList(), [...r.delete]..sort(), reason: reason);
  expect(upserted, [...upserted]..sort(), reason: '$reason: links in order');
  for (final l in r.upsert) {
    final meeting = r.meetings.singleWhere(
      (m) => copyKeys(m).contains(l.copyKey),
    );
    expect(l.meetingKey, meeting.key, reason: '$reason: ${l.copyKey} link');
  }
}

/// [a] and [b] are the same result, down to the order of every list.
void expectSameResult(MergeResult a, MergeResult b, {String? why}) {
  expect(a.meetings, b.meetings, reason: why);
  expect(a.upsert, b.upsert, reason: why);
  expect(a.delete.toList(), b.delete.toList(), reason: why);
  expect(a.timeSource.entries.map((e) => '${e.key}=${e.value}'), [
    for (final e in b.timeSource.entries) '${e.key}=${e.value}',
  ], reason: why);
  expect(a.merged, b.merged, reason: why);
}

void main() {
  group('Matching', () {
    test('an ICS and a phone copy with the same title and original start '
        'merge', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');

      final r = run([f, p]);

      final meeting = theMeeting(r);
      expect(meeting.copies, [p, f]);
      expect(meeting.key, p.key);
      expect(r.merged, 1);
      expect(r.timeSource, {p.key: 'phone'});
      expect(
        r.upsert.map((l) => l.matchedBy),
        everyElement(MeetingMatch.fingerprint),
      );
    });

    test('titles match after trimming, case-folding, collapsing spaces and '
        'dropping Canceled:', () {
      final p = copy('phone', 'p1', title: 'Weekly sync');
      const equivalent = [
        '  Weekly sync  ',
        'WEEKLY SYNC',
        'Weekly    sync',
        'Weekly\tsync',
        'Canceled: Weekly sync',
        'Cancelled: Weekly sync',
        'CANCELED:Weekly sync',
        '  cancelled:   WEEKLY   Sync ',
      ];
      for (final title in equivalent) {
        final f = copy('feed', 'f1', icalUid: 'f1', title: title);
        expect(
          MeetingMerger.fingerprint(f),
          MeetingMerger.fingerprint(p),
          reason: '"$title" has the same fingerprint',
        );
        expect(run([p, f]).merged, 1, reason: '"$title" merges');
      }

      const different = [
        'Weekly sync 2',
        'Re: Weekly sync',
        'Weekly sync Canceled:',
        'Canceled Weekly sync',
        'Weekly sync (Canceled: moved)',
      ];
      for (final title in different) {
        final f = copy('feed', 'f1', icalUid: 'f1', title: title);
        expect(
          MeetingMerger.fingerprint(f),
          isNot(MeetingMerger.fingerprint(p)),
          reason: '"$title" has another fingerprint',
        );
        expectAlone(run([p, f]), [p, f], why: '"$title"');
      }
    });

    test('different titles do not merge', () {
      final p = copy('phone', 'p1', title: 'Budget review');
      final f = copy('feed', 'f1', icalUid: 'f1', title: 'Budget planning');

      expectAlone(run([p, f]), [p, f]);
    });

    test('untitled copies never merge on fingerprint', () {
      final p = copy('phone', 'p1', title: '(No title)');
      expect(MeetingMerger.fingerprint(p), isNull);

      for (final title in [
        '',
        '(No title)',
        '   ',
        '(NO TITLE)',
        'Canceled:',
      ]) {
        final f = copy('feed', 'f1', icalUid: 'f1', title: title);
        expect(MeetingMerger.fingerprint(f), isNull, reason: '"$title"');
        expectAlone(run([p, f]), [p, f], why: '"$title"');
      }
    });

    test('all-day and timed copies at the same instant do not merge', () {
      final midnight = DateTime.utc(2026, 10, 7);
      final timed = copy('phone', 'p1', title: 'Offsite', start: midnight);
      final allDay = copy(
        'feed',
        'f1',
        icalUid: 'f1',
        title: 'Offsite',
        start: midnight,
        allDay: true,
      );
      expect(
        MeetingMerger.fingerprint(timed),
        isNot(MeetingMerger.fingerprint(allDay)),
      );
      expectAlone(run([timed, allDay]), [timed, allDay]);

      // Two all-day copies of the same day do merge.
      final phoneAllDay = copy(
        'phone',
        'p1',
        title: 'Offsite',
        start: midnight,
        allDay: true,
      );
      expect(run([phoneAllDay, allDay]).merged, 1);
    });

    test('two copies in the same source never merge', () {
      // Identical twins in one source.
      final a = copy('phone', 'a');
      final b = copy('phone', 'b');
      expectAlone(run([a, b]), [a, b], why: 'twins');

      // The same iCal UID twice in one source.
      final u1 = copy('feed', 'u1', icalUid: 'U', title: 'One');
      final u2 = copy('feed', 'u2', icalUid: 'U', title: 'Two');
      expectAlone(run([u1, u2]), [u1, u2], why: 'one UID twice');

      // A copy does not join a meeting that already has a copy from its
      // source, even when it matches another copy of that meeting. Here the
      // phone copy and f1 merge by UID, and f2 has the phone copy's title.
      final p = copy('phone', 'p1', title: 'Y', icalUid: 'U1');
      final f1 = copy('feed', 'f1', title: 'X', icalUid: 'U1');
      final f2 = copy('feed', 'f2', title: 'Y', icalUid: 'U2');
      final r = run([f2, f1, p]);
      expect(r.meetings, hasLength(2));
      expect(copyKeys(meetingWithKey(r, p.key)), [p.key, f1.key]);
      expect(meetingWithKey(r, f2.key), same(f2));
    });

    test('a fingerprint shared by two copies of one source merges neither', () {
      final p1 = copy('phone', 'p1');
      final p2 = copy('phone', 'p2');
      final f = copy('feed', 'f1', icalUid: 'f1');
      expectAlone(run([p1, p2, f]), [p1, p2, f], why: 'twins on the phone');

      final f2 = copy('feed', 'f2', icalUid: 'f2');
      expectAlone(run([p1, f, f2]), [p1, f, f2], why: 'twins in the feed');

      expectAlone(run([p1, p2, f, f2]), [
        p1,
        p2,
        f,
        f2,
      ], why: 'twins on both sides');
    });

    test('the same feed added twice merges by UID', () {
      final a = copy('feed', 'ev1', icalUid: 'ev1');
      final b = copy('feed2', 'ev1', icalUid: 'ev1');

      final r = run([b, a]);

      final meeting = theMeeting(r);
      expect(meeting.copies, [a, b], reason: 'source id: feed before feed2');
      expect(meeting.key, a.key);
      expect(r.upsert.map((l) => l.matchedBy), [
        MeetingMatch.uid,
        MeetingMatch.uid,
      ]);

      // Two instances of one series merge instance by instance.
      EventOccurrence instance(String sourceId, DateTime original) => copy(
        sourceId,
        'series',
        seriesUid: 'series',
        icalUid: 'series',
        start: original,
        originalStart: original,
      );
      final a1 = instance('feed', t0);
      final a2 = instance('feed', t1);
      final b1 = instance('feed2', t0);
      final b2 = instance('feed2', t1);
      final series = run([a1, a2, b1, b2]);
      expect(series.meetings, hasLength(2));
      expect(copyKeys(meetingWithKey(series, a1.key)), [a1.key, b1.key]);
      expect(copyKeys(meetingWithKey(series, a2.key)), [a2.key, b2.key]);
    });

    test('a strong key merges copies whose titles differ', () {
      final p = copy('phone', 'p1', title: 'Budget review', icalUid: 'U');
      final f = copy('feed', 'U', title: 'Q4 budget', icalUid: 'U');

      final r = run([p, f]);

      final meeting = theMeeting(r);
      expect(meeting.copies, [p, f]);
      expect(r.upsert.map((l) => l.matchedBy), [
        MeetingMatch.uid,
        MeetingMatch.uid,
      ]);

      // The same UID at another original start is another instance.
      final later = copy(
        'feed',
        'U',
        title: 'Q4 budget',
        icalUid: 'U',
        start: t1,
      );
      expectAlone(run([p, later]), [p, later], why: 'another original start');
    });

    test('a copy matching two meetings joins neither', () {
      const sources = <String, SourceRank>{
        'a': feedRank,
        'b': feedRank,
        'd': feedRank,
        'e': feedRank,
        'z': feedRank,
      };
      // Sync (a and b) merge by title, Standup (d and e) by title and UID.
      final a1 = copy('a', 'a1', title: 'Sync');
      final b1 = copy('b', 'b1', title: 'Sync');
      final d1 = copy('d', 'd1', title: 'Standup', icalUid: 'U');
      final e1 = copy('e', 'e1', title: 'Standup', icalUid: 'U');
      // c has the title of the first and the UID of the second.
      final c = copy('z', 'c1', title: 'Sync', icalUid: 'U');

      final r = run([c, e1, d1, b1, a1], sources: sources);

      expect(r.meetings, hasLength(3));
      expect(copyKeys(meetingWithKey(r, a1.key)), [a1.key, b1.key]);
      expect(copyKeys(meetingWithKey(r, d1.key)), [d1.key, e1.key]);
      expect(meetingWithKey(r, c.key), same(c));
      expect(r.merged, 2);
      expect(r.upsert.map((l) => l.copyKey), isNot(contains(c.key)));
    });

    test('a third source joins an existing meeting', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final w = copy('work', 'w1', icalUid: 'w1');
      final m = p.key;

      final r = run([w, f, p], links: [linkOf(p, m), linkOf(f, m)]);

      final meeting = theMeeting(r);
      expect(meeting.key, m);
      expect(meeting.copies, [p, f, w]);
      expect(r.merged, 1);
      expect(r.upsert, [
        linkOf(f, m),
        linkOf(p, m),
        linkOf(w, m, matchedBy: MeetingMatch.fingerprint),
      ]);
    });
  });

  group('Moves', () {
    test('a moved series instance still merges while the feed shows the old '
        'time', () {
      final original = DateTime.utc(2026, 10, 7, 8);
      final moved = DateTime.utc(2026, 10, 7, 9, 30);
      final p = copy(
        'phone',
        'series1',
        title: 'Weekly sync',
        seriesUid: 'series1',
        originalStart: original,
        start: moved,
      );
      final f = copy(
        'feed',
        'series1',
        title: 'Weekly sync',
        seriesUid: 'series1',
        icalUid: 'series1',
        originalStart: original,
        start: original,
      );

      final r = run([f, p]);

      final meeting = theMeeting(r);
      expect(meeting.copies, [p, f]);
      expect(meeting.startUtc, moved);
      expect(meeting.endUtc, moved.add(const Duration(minutes: 30)));
      expect(meeting.originalStartUtc, original);
      expect(r.timeSource, {p.key: 'phone'});
    });

    test('a moved one-off stays merged through its remembered link', () {
      final p1 = copy('phone', 'ev1', start: t0);
      final f = copy('feed', 'fx', icalUid: 'fx', start: t0);
      final first = run([p1, f]);
      final m = p1.key;
      expect(theMeeting(first).key, m);

      // The phone moves the one-off: its original start is its start, so its
      // key changes. The feed still shows the old time.
      final p2 = copy('phone', 'ev1', start: t2);
      expect(p2.key, isNot(p1.key));

      final r = run([p2, f], links: first.upsert);

      final meeting = theMeeting(r);
      expect(meeting.key, m, reason: 'the meeting keeps its key');
      expect(meeting.copies, [p2, f]);
      expect(meeting.startUtc, t2);
      expect(meeting.originalStartUtc, t2, reason: 'the time source decides');
      expect(meeting.uid, 'ev1');
      expect(r.timeSource, {m: 'phone'});
      expect(r.upsert.map((l) => l.copyKey), contains(p2.key));
      expect(r.delete, isEmpty);
    });

    test('without a link a moved one-off does not merge', () {
      final f = copy('feed', 'fx', icalUid: 'fx', start: t0);
      final p2 = copy('phone', 'ev1', start: t2);

      expectAlone(run([p2, f]), [p2, f]);
    });
  });

  group('Ranking and fields', () {
    test('the phone copy decides the time', () {
      final original = t0;
      final p = copy(
        'phone',
        's1',
        seriesUid: 's1',
        originalStart: original,
        start: t1,
        length: const Duration(minutes: 45),
      );
      final f = copy(
        'feed',
        's1',
        seriesUid: 's1',
        icalUid: 's1',
        originalStart: original,
        start: t0,
      );

      for (final input in [
        [p, f],
        [f, p],
      ]) {
        final r = run(input);
        final meeting = theMeeting(r);
        expect(meeting.startUtc, t1);
        expect(meeting.endUtc, t1.add(const Duration(minutes: 45)));
        expect(meeting.sourceId, 'phone');
        expect(meeting.timeSourceId, 'phone');
        expect(r.timeSource, {p.key: 'phone'});
      }
    });

    test('a failing phone source loses to a healthy feed', () {
      final p = copy(
        'phone',
        's1',
        seriesUid: 's1',
        originalStart: t0,
        start: t1,
      );
      final f = copy(
        'feed',
        's1',
        seriesUid: 's1',
        icalUid: 's1',
        originalStart: t0,
        start: t0,
      );

      final r = run([p, f], sources: {...ranks, 'phone': failingPhoneRank});

      final meeting = theMeeting(r);
      expect(meeting.copies, [f, p]);
      expect(meeting.startUtc, t0, reason: 'the feed decides the time');
      expect(meeting.timeSourceId, 'feed');
      expect(r.timeSource, {f.key: 'feed'});

      // Health outranks kind: a healthy debug source beats a failing feed.
      final d = copy('debug', 'd1');
      final g = copy('feed', 'g1', icalUid: 'g1');
      final other = run([g, d], sources: {...ranks, 'feed': failingFeedRank});
      expect(theMeeting(other).copies, [d, g]);
    });

    test('the Join link, location and busy status fill in from the next '
        'copy', () {
      const join = 'https://teams.microsoft.com/l/meetup-join/1';

      // Outlook's phone sync may leave out the body and the Join link: the
      // phone copy has none of the optional fields, and the feed has them all.
      final p = copy('phone', 'p1', busyStatus: BusyStatus.unknown);
      final f = copy(
        'feed',
        'f1',
        icalUid: 'f1',
        title: 'BUDGET REVIEW',
        joinUrl: join,
        location: 'Room 4',
        organizer: 'Pat',
        description: 'Agenda',
        busyStatus: BusyStatus.busy,
      );
      final filled = theMeeting(run([p, f]));
      expect(filled.joinUrl, join);
      expect(filled.location, 'Room 4');
      expect(filled.organizer, 'Pat');
      expect(filled.description, 'Agenda');
      expect(filled.busyStatus, BusyStatus.busy);
      expect(filled.title, p.title, reason: 'the title is the time source');

      // A value on the top copy is kept.
      final p2 = copy(
        'phone',
        'p2',
        joinUrl: 'https://phone.example/join',
        location: 'Phone room',
        organizer: 'Phone Pat',
        description: 'Phone agenda',
        busyStatus: BusyStatus.tentative,
      );
      final f2 = copy(
        'feed',
        'f2',
        icalUid: 'f2',
        joinUrl: join,
        location: 'Feed room',
        organizer: 'Feed Pat',
        description: 'Feed agenda',
        busyStatus: BusyStatus.busy,
      );
      final kept = theMeeting(run([p2, f2]));
      expect(kept.joinUrl, 'https://phone.example/join');
      expect(kept.location, 'Phone room');
      expect(kept.organizer, 'Phone Pat');
      expect(kept.description, 'Phone agenda');
      expect(kept.busyStatus, BusyStatus.tentative);

      // The first copy that has a value wins, not the last one that has.
      final p3 = copy('phone', 'p3', busyStatus: BusyStatus.unknown);
      final f3 = copy(
        'feed',
        'f3',
        icalUid: 'f3',
        location: 'Feed room',
        busyStatus: BusyStatus.oof,
      );
      final w3 = copy(
        'work',
        'w3',
        icalUid: 'w3',
        joinUrl: 'https://work.example/join',
        location: 'Work room',
        busyStatus: BusyStatus.free,
      );
      final chain = theMeeting(run([w3, f3, p3]));
      expect(chain.location, 'Feed room');
      expect(chain.joinUrl, 'https://work.example/join');
      expect(chain.busyStatus, BusyStatus.oof);

      // No copy has a status: it stays unknown.
      final u1 = copy('phone', 'u1', busyStatus: BusyStatus.unknown);
      final u2 = copy(
        'feed',
        'u2',
        icalUid: 'u2',
        busyStatus: BusyStatus.unknown,
      );
      expect(theMeeting(run([u1, u2])).busyStatus, BusyStatus.unknown);
    });

    test('declined or cancelled on any copy marks the meeting', () {
      EventOccurrence phoneCopy({
        bool declined = false,
        bool cancelled = false,
      }) => copy('phone', 'p1', declined: declined, cancelled: cancelled);
      EventOccurrence feedCopy({
        bool declined = false,
        bool cancelled = false,
      }) => copy(
        'feed',
        'f1',
        icalUid: 'f1',
        declined: declined,
        cancelled: cancelled,
      );

      MeetingOccurrence merge(EventOccurrence p, EventOccurrence f) =>
          theMeeting(run([f, p]));

      final none = merge(phoneCopy(), feedCopy());
      expect(none.declined, isFalse);
      expect(none.cancelled, isFalse);

      // The top copy (the phone) says so.
      expect(merge(phoneCopy(declined: true), feedCopy()).declined, isTrue);
      expect(merge(phoneCopy(cancelled: true), feedCopy()).cancelled, isTrue);

      // Only a lower-ranked copy says so.
      final declined = merge(phoneCopy(), feedCopy(declined: true));
      expect(declined.declined, isTrue);
      expect(declined.cancelled, isFalse);
      final cancelled = merge(phoneCopy(), feedCopy(cancelled: true));
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.declined, isFalse);
    });

    test('the colour comes from the time source', () {
      final p = copy('phone', 'p1', color: 0xFF111111);
      final f = copy('feed', 'f1', icalUid: 'f1', color: 0xFF222222);

      expect(theMeeting(run([p, f])).calendarColor, 0xFF111111);

      final failing = run(
        [p, f],
        sources: {...ranks, 'phone': failingPhoneRank},
      );
      expect(theMeeting(failing).calendarColor, 0xFF222222);
    });
  });

  group('Keys and links', () {
    test("a new meeting takes its top-ranked copy's key", () {
      void expectKey(
        String why,
        List<EventOccurrence> copies,
        EventOccurrence top, {
        Map<String, SourceRank> sources = ranks,
      }) {
        final r = run(copies, sources: sources);
        expect(theMeeting(r).key, top.key, reason: why);
        expect(r.upsert, hasLength(copies.length), reason: why);
        expect(r.upsert.map((l) => l.meetingKey), everyElement(top.key));
      }

      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final w = copy('work', 'w1', icalUid: 'w1');
      final d = copy('debug', 'd1');
      expectKey('phone before feed', [f, p], p);
      expectKey('feed before work, by source id', [w, f], f);
      expectKey('feed before debug', [d, f], f);
      expectKey(
        'a healthy feed before a failing phone',
        [p, f],
        f,
        sources: {...ranks, 'phone': failingPhoneRank},
      );
    });

    test('the meeting key stays when the ranking changes', () {
      // The phone copy was moved, so the two copies show different times.
      final p = copy(
        'phone',
        's1',
        seriesUid: 's1',
        originalStart: t0,
        start: t1,
      );
      final f = copy(
        'feed',
        's1',
        seriesUid: 's1',
        icalUid: 's1',
        originalStart: t0,
        start: t0,
      );

      // The phone decides, then it fails: the feed decides, the key stays.
      final healthy = run([p, f]);
      expect(theMeeting(healthy).key, p.key);
      final failing = run(
        [p, f],
        links: healthy.upsert,
        sources: {...ranks, 'phone': failingPhoneRank},
      );
      final later = theMeeting(failing);
      expect(later.key, p.key);
      expect(later.meetingKey, p.key);
      expect(later.startUtc, t0, reason: 'the feed decides the time now');
      expect(failing.timeSource, {p.key: 'feed'});
      expect(later.copies, [f, p]);

      // The feed decides, then the phone recovers: the phone decides, the key
      // stays with the feed's copy although the phone ranks first again.
      final first = run([p, f], sources: {...ranks, 'phone': failingPhoneRank});
      expect(theMeeting(first).key, f.key);
      final recovered = run([p, f], links: first.upsert);
      final back = theMeeting(recovered);
      expect(back.key, f.key);
      expect(back.startUtc, t1, reason: 'the phone decides the time again');
      expect(recovered.timeSource, {f.key: 'phone'});
      expect(back.copies, [p, f]);
    });

    test('after a split the remaining copy keeps the meeting key', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final merged = run([p, f]);
      final m = p.key;

      // The phone calendar is removed or disabled: the feed's copy is planned
      // under the key the phone's copy gave the meeting.
      final feedOnly = run([f], links: merged.upsert);
      final meeting = theMeeting(feedOnly);
      expect(meeting.key, m);
      expect(meeting.meetingKey, m);
      expect(meeting.copies, [f]);
      expect(meeting.timeSourceId, 'feed');
      expect(feedOnly.timeSource, {m: 'feed'});
      expect(feedOnly.merged, 0);
      expect(feedOnly.upsert, [linkOf(f, m)]);
      expect(feedOnly.delete, isEmpty);

      // The feed is removed instead: the phone's copy holds the key already,
      // so it is planned as it is.
      final phoneOnly = run([p], links: merged.upsert);
      expect(phoneOnly.meetings.single, same(p));
      expect(phoneOnly.timeSource, {m: 'phone'});
      expect(phoneOnly.upsert, [linkOf(p, m)]);

      // The meeting was keyed by the feed's copy (the phone was failing): the
      // phone's copy is planned under that key when it is the one left.
      final failingPhone = {...ranks, 'phone': failingPhoneRank};
      final keyedByFeed = run([p, f], sources: failingPhone);
      expect(theMeeting(keyedByFeed).key, f.key);
      final left = run([p], links: keyedByFeed.upsert);
      final remaining = theMeeting(left);
      expect(remaining.key, f.key);
      expect(remaining.copies, [p]);
      expect(remaining.timeSourceId, 'phone');
      expect(left.timeSource, {f.key: 'phone'});
    });

    test('a copy whose key is a meeting key joins that meeting', () {
      // The meeting was keyed by the phone's copy. That copy's own link is
      // gone, and so was the copy for a while. The feed's link names it.
      final p = copy('phone', 'p1', title: 'Standup');
      final f = copy('feed', 'f1', icalUid: 'f1', title: 'Daily sync');
      final m = p.key;

      final r = run([f, p], links: [linkOf(f, m)]);

      final meeting = theMeeting(r);
      expect(meeting.key, m);
      expect(meeting.copies, [p, f]);
      expect(r.upsert, [linkOf(f, m), linkOf(p, m)]);
      expect(r.delete, isEmpty);

      // Without the link they are two meetings: the titles differ.
      expectAlone(run([f, p]), [f, p]);
    });

    test('meeting keys are unique for any input', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final w = copy('work', 'w1', icalUid: 'w1');
      final merged = run([p, f]);
      final gone = EventOccurrence.makeKey('gone', 'g1', t0);

      // One source twice in a meeting, one of them holding the meeting key.
      final p1 = copy('phone', 'x1', title: 'Alpha');
      final p2 = copy('phone', 'x2', title: 'Beta');
      final f1 = copy('feed', 'y1', icalUid: 'y1', title: 'Gamma');

      // A copy linked to one meeting, the key of another, the third source
      // linked to the first copy's key.
      final t = copy('phone', 't1', title: 'Alpha');
      final k = copy('phone', 'k1', title: 'Beta');
      final z = copy('feed', 'z1', icalUid: 'z1', title: 'Gamma');

      final cases = <(String, List<EventOccurrence>, List<MeetingLink>)>[
        ('nothing', [], []),
        ('lone copies', [copy('phone', 'a', title: 'A'), f], []),
        ('a merged pair', [p, f], []),
        ('a three-way merge', [w, f, p], []),
        ('a split under the phone key', [f], merged.upsert),
        (
          'a split under the feed key',
          [p],
          [linkOf(f, f.key), linkOf(p, f.key)],
        ),
        ('a link to a meeting nobody has', [f], [linkOf(f, gone)]),
        (
          'a key holder with no link of its own',
          [copy('phone', 'h1', title: 'Standup'), f],
          [linkOf(f, copy('phone', 'h1', title: 'Standup').key)],
        ),
        (
          'one source twice in a meeting',
          [p1, p2, f1],
          [linkOf(p1, p1.key), linkOf(p2, p1.key), linkOf(f1, p1.key)],
        ),
        (
          'neither duplicate holds the key',
          [p1, p2, f1],
          [linkOf(p1, gone), linkOf(p2, gone), linkOf(f1, gone)],
        ),
        (
          'a copy turned away holds another meeting key',
          [t, k, z],
          [linkOf(t, k.key), linkOf(k, k.key), linkOf(z, t.key)],
        ),
        (
          'links that name each other',
          [p, f, w],
          [linkOf(p, f.key), linkOf(f, p.key)],
        ),
        ('a copy listed twice', [p, p, f], []),
        (
          'a linked copy and a matching new one',
          [f, copy('phone', 'n1')],
          [linkOf(f, gone)],
        ),
        (
          'two linked meetings and a copy matching both',
          [
            copy('phone', 'm1', title: 'Sync'),
            copy('feed', 'm2', icalUid: 'm2', title: 'Sync'),
            copy('work', 'm3', icalUid: 'm3', title: 'Sync'),
          ],
          [
            linkOf(copy('phone', 'm1', title: 'Sync'), gone),
            linkOf(
              copy('feed', 'm2', icalUid: 'm2', title: 'Sync'),
              EventOccurrence.makeKey('gone', 'g2', t0),
            ),
          ],
        ),
      ];

      for (final (name, copies, links) in cases) {
        expectSane(run(copies, links: links), copies, reason: name);
      }
      // Merging off is sane too.
      expectSane(run([p, f], enabled: false), [p, f], reason: 'merging off');
    });

    test('links are written for every copy of a merged meeting and none for '
        'lone copies', () {
      final p = copy('phone', 'p1'); // a one-off
      final f = copy(
        'feed',
        'f1',
        seriesUid: 'f1',
        icalUid: 'f1',
        length: const Duration(minutes: 90),
      );
      final lone = copy('work', 'w1', icalUid: 'w1', title: 'Something else');

      final r = run([lone, f, p]);

      final m = p.key;
      expect(r.upsert, [
        MeetingLink(
          copyKey: f.key,
          meetingKey: m,
          sourceId: 'feed',
          uid: 'f1',
          oneOff: false,
          endUtc: f.endUtc,
          matchedBy: MeetingMatch.fingerprint,
        ),
        MeetingLink(
          copyKey: p.key,
          meetingKey: m,
          sourceId: 'phone',
          uid: 'p1',
          oneOff: true,
          endUtc: p.endUtc,
          matchedBy: MeetingMatch.fingerprint,
        ),
      ]);
      expect(r.delete, isEmpty);
      expect(meetingWithKey(r, lone.key), same(lone));
      expect(r.merged, 1);
    });

    test("an ejected duplicate's link is deleted", () {
      // The phone has two copies in one meeting. p1 holds the meeting key and
      // p2 is a stale duplicate with a link of its own.
      final p1 = copy('phone', 'p1', title: 'Budget review');
      final p2 = copy('phone', 'p2', title: 'Other title');
      final f1 = copy('feed', 'f1', icalUid: 'f1');
      final m = p1.key;

      final r = run(
        [f1, p2, p1],
        links: [linkOf(p1, m), linkOf(p2, m), linkOf(f1, m)],
      );

      expect(r.delete, {p2.key});
      expect(r.meetings, hasLength(2));
      final meeting = meetingWithKey(r, m);
      expect(copyKeys(meeting), [p1.key, f1.key]);
      expect(meetingWithKey(r, p2.key), same(p2));
      expect(r.upsert, [linkOf(f1, m), linkOf(p1, m)]);

      // Neither copy holds the key: the lowest key stays.
      final gone = EventOccurrence.makeKey('gone', 'g1', t0);
      final other = run(
        [p1, p2, f1],
        links: [linkOf(p1, gone), linkOf(p2, gone), linkOf(f1, gone)],
      );
      expect(other.delete, {p2.key});
      expect(copyKeys(meetingWithKey(other, gone)), [p1.key, f1.key]);
      expect(meetingWithKey(other, p2.key), same(p2));
    });
  });

  group('Off and determinism', () {
    test('with merging off, copies pass through unchanged', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final w = copy('work', 'w1', icalUid: 'w1', title: 'Else');
      // Stored links are kept, and not used.
      final links = [linkOf(p, p.key), linkOf(f, p.key)];

      for (final input in [
        [f, p, w],
        [p, w, f],
      ]) {
        final r = run(input, links: links, enabled: false);

        expect(r.meetings, hasLength(3));
        expect(r.meetings[0], same(f));
        expect(r.meetings[1], same(p));
        expect(r.meetings[2], same(w));
        expect(r.upsert, isEmpty);
        expect(r.delete, isEmpty);
        expect(r.timeSource, {f.key: 'feed', p.key: 'phone', w.key: 'work'});
        expect(r.merged, 0);
      }
    });

    test('the result does not depend on input order', () {
      final scenario = _mixedScenario();
      final base = run(
        scenario.copies,
        links: scenario.links,
        sources: scenario.sources,
      );
      expectSane(base, scenario.copies, reason: 'the scenario');
      expect(base.merged, 6, reason: 'the scenario merges six meetings');
      expect(base.delete, isNotEmpty, reason: 'and ejects a duplicate');

      final random = Random(7);
      for (var i = 0; i < 40; i++) {
        final copies = [...scenario.copies]..shuffle(random);
        final links = [...scenario.links]..shuffle(random);
        final r = run(copies, links: links, sources: scenario.sources);
        expectSameResult(r, base, why: 'permutation $i');
      }

      // The same holds with merging off.
      final off = run(scenario.copies, enabled: false);
      final offShuffled = run(
        [...scenario.copies]..shuffle(random),
        enabled: false,
      );
      expectSameResult(offShuffled, off, why: 'merging off');
    });
  });

  // Extra tests: not in the plan's Acceptance list. They pin the binding
  // points the plan leaves to the merger, and the choices it made.
  group('Extra: binding points and corner cases', () {
    test('a lone copy is emitted as the plain instance and keeps its key', () {
      final solo = copy('phone', 'solo', title: 'Solo');

      final r = run([solo]);

      expect(r.meetings.single, same(solo));
      expect(r.meetings.single.key, solo.key);
      expect(r.upsert, isEmpty);
      expect(r.delete, isEmpty);
      expect(r.timeSource, {solo.key: 'phone'});
      expect(r.merged, 0);
    });

    test('every MeetingOccurrence is built from its top-ranked copy, and its '
        'time source is that copy source', () {
      final p = copy(
        'phone',
        'p-s1',
        seriesUid: 'phone-series',
        originalStart: t0,
        start: t1,
        location: 'Phone room',
        color: 0xFF111111,
      ).copyWith(warnings: {OccurrenceWarning.tzFallback});
      final f = copy(
        'feed',
        'f-s1',
        seriesUid: 'feed-series',
        icalUid: 'ical-1',
        originalStart: t0,
        start: t0,
        location: 'Feed room',
        color: 0xFF222222,
      );
      final w = copy('work', 'w1', icalUid: 'w1', originalStart: t0, start: t0);
      final failing = {...ranks, 'phone': failingPhoneRank};

      final results = <(String, MergeResult, String)>[
        ('a pair', run([p, f]), 'phone'),
        ('a pair with a failing phone', run([p, f], sources: failing), 'feed'),
        ('a triple', run([w, f, p]), 'phone'),
        (
          'a split',
          run([f], links: [linkOf(p, p.key), linkOf(f, p.key)]),
          'feed',
        ),
      ];
      for (final (name, r, timeSource) in results) {
        final meeting = r.meetings.whereType<MeetingOccurrence>().single;
        final top = meeting.copies.first;
        expect(top.sourceId, timeSource, reason: name);
        expect(meeting.timeSourceId, timeSource, reason: name);
        expect(meeting.timeSourceId, meeting.sourceId, reason: name);
        expect(meeting.sourceId, top.sourceId, reason: name);
        expect(meeting.uid, top.uid, reason: name);
        expect(meeting.originalStartUtc, top.originalStartUtc, reason: name);
        expect(meeting.seriesUid, top.seriesUid, reason: name);
        expect(meeting.icalUid, top.icalUid, reason: name);
        expect(meeting.startUtc, top.startUtc, reason: name);
        expect(meeting.endUtc, top.endUtc, reason: name);
        expect(meeting.allDay, top.allDay, reason: name);
        expect(meeting.warnings, top.warnings, reason: name);
        expect(meeting.calendarColor, top.calendarColor, reason: name);
        expect(meeting.location, top.location, reason: name);
        expect(r.timeSource[meeting.key], timeSource, reason: name);
      }
    });

    test('a single copy kept under a key that is not its own is a '
        'MeetingOccurrence, and merged counts only meetings of two or more '
        'copies', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final solo = copy('work', 'w1', icalUid: 'w1', title: 'Solo');
      final other = copy('work', 'w2', icalUid: 'w2', title: 'Other');
      final other2 = copy('feed', 'f2', icalUid: 'f2', title: 'Other');

      // f stays under the phone copy's key, p is gone.
      final r = run(
        [f, solo, other, other2],
        links: [linkOf(p, p.key), linkOf(f, p.key)],
      );

      final kept = meetingWithKey(r, p.key);
      expect(kept, isA<MeetingOccurrence>());
      expect((kept as MeetingOccurrence).copies, [f]);
      expect(meetingWithKey(r, solo.key), same(solo));
      expect(copyKeys(meetingWithKey(r, other2.key)), [other2.key, other.key]);
      expect(
        r.merged,
        1,
        reason: 'the kept copy and the lone one do not count',
      );
    });

    test('the ranking is healthy, then phone, feed, debug, then the key '
        'holder, then source id', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final f2 = copy('feed2', 'f2', icalUid: 'f2');
      final w = copy('work', 'w1', icalUid: 'w1');
      final d = copy('debug', 'd1');

      List<EventOccurrence> order(
        List<EventOccurrence> copies, {
        List<MeetingLink> links = const [],
        Map<String, SourceRank> sources = ranks,
      }) => theMeeting(run(copies, links: links, sources: sources)).copies;

      expect(order([d, w, f, p]), [p, f, w, d], reason: 'kind, then source id');
      expect(order([f2, f]), [f, f2], reason: 'feed before feed2');
      expect(order([d, p], sources: {...ranks, 'phone': failingPhoneRank}), [
        d,
        p,
      ], reason: 'a failing phone after a healthy debug source');
      expect(order([w, f, p], sources: {...ranks, 'phone': failingPhoneRank}), [
        f,
        w,
        p,
      ], reason: 'a failing phone last');

      // The key holder comes before a source with a lower id.
      expect(order([f, w], links: [linkOf(w, w.key), linkOf(f, w.key)]), [
        w,
        f,
      ], reason: 'the work copy holds the meeting key');
      // But not before a better kind.
      expect(order([f, p], links: [linkOf(f, f.key), linkOf(p, f.key)]), [
        p,
        f,
      ], reason: 'kind comes before the key holder');
    });

    test('a source missing from the ranks ranks after every listed source', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');

      final r = run([p, f], sources: {'feed': feedRank});

      expect(theMeeting(r).copies, [f, p]);
    });

    test('a strong key shared by two copies of one source merges neither', () {
      final p = copy('phone', 'p1', title: 'One', icalUid: 'U');
      final w1 = copy('work', 'w1', title: 'Two', icalUid: 'U');
      final w2 = copy('work', 'w2', title: 'Three', icalUid: 'U');

      expectAlone(run([p, w1, w2]), [p, w1, w2]);

      // With one copy in each source the UID merges them.
      expect(run([p, w1]).merged, 1);
    });

    test('untitled copies can still merge by a strong key', () {
      final p = copy('phone', 'p1', title: '(No title)', icalUid: 'U');
      final f = copy('feed', 'U', title: '', icalUid: 'U');

      expect(theMeeting(run([p, f])).copies, [p, f]);
    });

    test('a copy that matched two meetings is not a candidate for later '
        'copies', () {
      const sources = <String, SourceRank>{
        'a': feedRank,
        'b': feedRank,
        'd': feedRank,
        'e': feedRank,
        'z': feedRank,
        'zz': feedRank,
      };
      final a1 = copy('a', 'a1', title: 'Sync');
      final b1 = copy('b', 'b1', title: 'Sync');
      final d1 = copy('d', 'd1', title: 'Standup', icalUid: 'U');
      final e1 = copy('e', 'e1', title: 'Standup', icalUid: 'U');
      final c = copy('z', 'c1', title: 'Sync', icalUid: 'U');
      // w matches Sync only; c also matches Sync, but c stayed alone.
      final w = copy('zz', 'w1', title: 'Sync');

      final r = run([a1, b1, c, d1, e1, w], sources: sources);

      expect(copyKeys(meetingWithKey(r, a1.key)), [a1.key, b1.key, w.key]);
      expect(copyKeys(meetingWithKey(r, d1.key)), [d1.key, e1.key]);
      expect(meetingWithKey(r, c.key), same(c));
    });

    test('a link names a one-off by source and uid, but only for one-offs', () {
      final f = copy('feed', 'f1', icalUid: 'f1');
      final m = f.key;
      final oldKey = EventOccurrence.makeKey('phone', 'e1', t0);
      MeetingLink old({required bool oneOff}) => MeetingLink(
        copyKey: oldKey,
        meetingKey: m,
        sourceId: 'phone',
        uid: 'e1',
        oneOff: oneOff,
        endUtc: t1,
        matchedBy: MeetingMatch.fingerprint,
      );

      // A one-off with the linked source and uid follows the link.
      final moved = copy('phone', 'e1', title: 'Unrelated', start: t2);
      final follows = run([f, moved], links: [old(oneOff: true), linkOf(f, m)]);
      expect(copyKeys(meetingWithKey(follows, m)), [moved.key, f.key]);

      // A series copy with the same source and uid does not.
      final series = copy(
        'phone',
        'e1',
        title: 'Unrelated',
        seriesUid: 'e1',
        start: t2,
      );
      final notSeries = run(
        [f, series],
        links: [old(oneOff: true), linkOf(f, m)],
      );
      expect(meetingWithKey(notSeries, series.key), same(series));
      expect(copyKeys(meetingWithKey(notSeries, m)), [f.key]);

      // A link that is not a one-off link is not followed either.
      final notOneOff = run(
        [f, moved],
        links: [old(oneOff: false), linkOf(f, m)],
      );
      expect(meetingWithKey(notOneOff, moved.key), same(moved));
    });

    test('several one-off links for one source and uid: the earliest end '
        'wins, then the lowest meeting key', () {
      final c = copy('phone', 'e1', title: 'Unrelated', start: t2);
      MeetingLink link(DateTime original, String meetingKey, DateTime end) =>
          MeetingLink(
            copyKey: EventOccurrence.makeKey('phone', 'e1', original),
            meetingKey: meetingKey,
            sourceId: 'phone',
            uid: 'e1',
            oneOff: true,
            endUtc: end,
            matchedBy: MeetingMatch.fingerprint,
          );
      final early = DateTime.utc(2026, 10, 5, 8);
      final late = DateTime.utc(2026, 10, 5, 9);

      MeetingOccurrence meetingOf(List<MeetingLink> links) =>
          theMeeting(run([c], links: links));

      expect(
        meetingOf([
          link(DateTime.utc(2026, 10, 4), 'meeting-a', late),
          link(DateTime.utc(2026, 10, 3), 'meeting-z', early),
        ]).meetingKey,
        'meeting-z',
        reason: 'the earliest end, although its key is higher',
      );
      expect(
        meetingOf([
          link(DateTime.utc(2026, 10, 4), 'meeting-z', early),
          link(DateTime.utc(2026, 10, 3), 'meeting-b', early),
        ]).meetingKey,
        'meeting-b',
        reason: 'the same end: the lowest meeting key',
      );
    });

    test('a copy with a link to the meeting is kept over one with a lower '
        'key', () {
      final m = EventOccurrence.makeKey('gone', 'm1', t0);
      // pLow is a one-off that moved, so only its old link finds the meeting.
      final pLow = copy('phone', 'e1', title: 'Unrelated', start: t1);
      final pHigh = copy('phone', 'e2', title: 'Else', icalUid: null);
      final oldLow = MeetingLink(
        copyKey: EventOccurrence.makeKey('phone', 'e1', t0),
        meetingKey: m,
        sourceId: 'phone',
        uid: 'e1',
        oneOff: true,
        endUtc: t1,
        matchedBy: MeetingMatch.fingerprint,
      );
      expect(pLow.key.compareTo(pHigh.key), lessThan(0));

      final r = run([pLow, pHigh], links: [oldLow, linkOf(pHigh, m)]);

      final kept = meetingWithKey(r, m) as MeetingOccurrence;
      expect(kept.copies, [pHigh]);
      expect(meetingWithKey(r, pLow.key), same(pLow));
      expect(r.delete, isEmpty);
    });

    test('a copy turned away from a meeting joins the meeting whose key it '
        'holds', () {
      final t = copy('phone', 't1', title: 'Alpha');
      final w = copy('phone', 'w1', title: 'Beta');
      final z = copy('feed', 'z1', icalUid: 'z1', title: 'Gamma');
      // t is linked to w's meeting, which w holds, so t is turned away. z is
      // linked to a meeting keyed by t's own key, which t holds.
      final r = run(
        [z, w, t],
        links: [linkOf(t, w.key), linkOf(w, w.key), linkOf(z, t.key)],
      );

      expect(r.meetings, hasLength(2));
      expect(copyKeys(meetingWithKey(r, t.key)), [t.key, z.key]);
      expect(meetingWithKey(r, w.key), same(w));
      expect(r.upsert, [linkOf(z, t.key), linkOf(t, t.key), linkOf(w, w.key)]);
      expect(
        r.delete,
        isEmpty,
        reason: "t's old link is replaced, not just dropped",
      );
    });

    test("a copy's own link decides before its key and its one-off "
        'link', () {
      // A copy is tried in its own link's meeting first, then in the meeting
      // its own key names, then in the meeting its (source, uid) was linked to.
      // The two halves pin both neighbours, which fixes the whole order.

      // Own link before own key. p is linked to f's meeting, and p's own key is
      // also the key of a meeting, because w is linked to it. The link decides.
      final p = copy('phone', 'p1', title: 'Alpha');
      final f = copy('feed', 'f1', icalUid: 'f1', title: 'Beta');
      final w = copy('work', 'w1', icalUid: 'w1', title: 'Gamma');
      final byLink = run(
        [w, f, p],
        links: [linkOf(p, f.key), linkOf(f, f.key), linkOf(w, p.key)],
      );

      expect(copyKeys(meetingWithKey(byLink, f.key)), [
        p.key,
        f.key,
      ], reason: "p's own link puts it in f's meeting");
      final alone = meetingWithKey(byLink, p.key);
      expect(alone, isA<MeetingOccurrence>());
      expect(copyKeys(alone), [w.key], reason: "w stays under p's key");
      expect(byLink.meetings, hasLength(2));
      expect(byLink.timeSource, {f.key: 'phone', p.key: 'work'});
      expect(byLink.upsert, [
        linkOf(f, f.key),
        linkOf(p, f.key),
        linkOf(w, p.key),
      ]);
      expect(byLink.delete, isEmpty);

      // Own key before the one-off link. c is a one-off that moved, and an old
      // link says its (source, uid) belongs to another meeting. But c has no
      // link of its own and its key is the key of the meeting d is linked to.
      final c = copy('phone', 'e1', title: 'Alpha', start: t1);
      final d = copy('feed', 'f2', icalUid: 'f2', title: 'Beta');
      final old = MeetingLink(
        copyKey: EventOccurrence.makeKey('phone', 'e1', t0),
        meetingKey: EventOccurrence.makeKey('gone', 'm2', t0),
        sourceId: 'phone',
        uid: 'e1',
        oneOff: true,
        endUtc: t1,
        matchedBy: MeetingMatch.fingerprint,
      );
      final byKey = run([d, c], links: [old, linkOf(d, c.key)]);

      expect(
        byKey.meetings,
        hasLength(1),
        reason: "c goes to the meeting its key names, not to its old link's",
      );
      final meeting = theMeeting(byKey);
      expect(meeting.key, c.key);
      expect(meeting.copies, [c, d]);
      expect(byKey.upsert, [linkOf(d, c.key), linkOf(c, c.key)]);
      expect(byKey.delete, isEmpty);
    });

    test('a link is left alone when its copy is absent', () {
      final solo = copy('phone', 'solo', title: 'Solo');
      final stale = MeetingLink(
        copyKey: EventOccurrence.makeKey('feed', 'gone', t0),
        meetingKey: EventOccurrence.makeKey('phone', 'gone', t0),
        sourceId: 'feed',
        uid: 'gone',
        oneOff: true,
        endUtc: t1,
        matchedBy: MeetingMatch.uid,
      );

      final r = run([solo], links: [stale]);

      expectAlone(r, [solo]);
      expectAlone(run([], links: [stale]), []);
    });

    test('copies repeated under one key are planned once, whichever comes '
        'first', () {
      final first = copy('phone', 'p1', title: 'A');
      final second = copy('phone', 'p1', title: 'B');
      expect(second.key, first.key);

      expect(run([first, second]).meetings.single, same(first));
      expect(run([second, first]).meetings.single, same(first));
    });

    test('the fingerprint ignores the current start and the source, and '
        'keeps the original start and the all-day flag', () {
      final a = copy('phone', 'p1', originalStart: t0, start: t1);
      final b = copy('feed', 'f1', originalStart: t0, start: t0);
      expect(MeetingMerger.fingerprint(a), MeetingMerger.fingerprint(b));
      expect(MeetingMerger.fingerprint(a), isNotNull);

      final c = copy('feed', 'f1', originalStart: t1, start: t1);
      expect(MeetingMerger.fingerprint(c), isNot(MeetingMerger.fingerprint(a)));
      final d = copy('feed', 'f1', originalStart: t0, allDay: true);
      expect(MeetingMerger.fingerprint(d), isNot(MeetingMerger.fingerprint(b)));
    });

    test('links record how each copy matched', () {
      MeetingMatch matchOf(MergeResult r, EventOccurrence c) =>
          r.upsert.singleWhere((l) => l.copyKey == c.key).matchedBy;

      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final byTitle = run([p, f]);
      expect(matchOf(byTitle, p), MeetingMatch.fingerprint);
      expect(matchOf(byTitle, f), MeetingMatch.fingerprint);

      final u = copy('phone', 'p2', title: 'One', icalUid: 'U');
      final v = copy('feed', 'U', title: 'Two', icalUid: 'U');
      final byUid = run([u, v]);
      expect(matchOf(byUid, u), MeetingMatch.uid);
      expect(matchOf(byUid, v), MeetingMatch.uid);

      final w = copy('work', 'w1', icalUid: 'w1');
      final joined = run(
        [p, f, w],
        links: [linkOf(p, p.key), linkOf(f, p.key)],
      );
      expect(matchOf(joined, p), MeetingMatch.remembered);
      expect(matchOf(joined, f), MeetingMatch.remembered);
      expect(matchOf(joined, w), MeetingMatch.fingerprint);
    });

    test('the inputs are not changed', () {
      final p = copy('phone', 'p1');
      final f = copy('feed', 'f1', icalUid: 'f1');
      final copies = [f, p];
      final links = [linkOf(f, p.key), linkOf(p, p.key)];

      run(copies, links: links);

      expect(copies, [f, p]);
      expect(links, [linkOf(f, p.key), linkOf(p, p.key)]);
    });

    test('an empty iCal UID is no strong key', () {
      final p = copy('phone', 'p1', title: 'One', icalUid: '');
      final f = copy('feed', 'f1', title: 'Two', icalUid: '');

      expectAlone(run([p, f]), [p, f]);
    });

    test('a copy that joined a meeting brings its own UID to it', () {
      // w matches f by UID only, and f joined by title.
      final p = copy('phone', 'p1', title: 'One');
      final f = copy('feed', 'f1', icalUid: 'U', title: 'One');
      final w = copy('work', 'w1', icalUid: 'U', title: 'Two');

      expect(theMeeting(run([w, f, p])).copies, [p, f, w]);
    });

    test('fuzz: random inputs keep every invariant and give the same result '
        'in any order', () {
      final random = Random(2026);
      const sourceIds = ['phone', 'feed', 'work', 'debug'];
      const kinds = {
        'phone': SourceKind.device,
        'feed': SourceKind.ics,
        'work': SourceKind.ics,
        'debug': SourceKind.debug,
      };
      const titles = [
        'Sync',
        ' sync ',
        'Canceled: Sync',
        'Standup',
        '',
        '(No title)',
      ];
      final starts = [t0, t1, t2];

      for (var round = 0; round < 300; round++) {
        final sources = {
          for (final id in sourceIds)
            id: SourceRank(kind: kinds[id]!, failing: random.nextInt(4) == 0),
        };

        final copies = <EventOccurrence>[];
        final seen = <String>{};
        final count = 2 + random.nextInt(9);
        for (var i = 0; i < count; i++) {
          final sourceId = sourceIds[random.nextInt(sourceIds.length)];
          final uid = 'e${random.nextInt(4)}';
          final original = starts[random.nextInt(starts.length)];
          final isFeed = kinds[sourceId] == SourceKind.ics;
          final c = copy(
            sourceId,
            uid,
            title: titles[random.nextInt(titles.length)],
            originalStart: original,
            start: random.nextBool() ? original : original.add(_hour),
            seriesUid: random.nextBool() ? null : uid,
            allDay: random.nextInt(8) == 0,
            icalUid: isFeed
                ? uid
                : (random.nextInt(3) == 0 ? 'e${random.nextInt(4)}' : null),
          );
          if (seen.add(c.key)) copies.add(c);
        }

        final meetingKeys = [
          for (final c in copies) c.key,
          EventOccurrence.makeKey('gone', 'g1', t0),
          EventOccurrence.makeKey('gone', 'g2', t1),
        ];
        final links = <MeetingLink>[];
        final linked = <String>{};
        final linkCount = random.nextInt(7);
        for (var i = 0; i < linkCount; i++) {
          final present = random.nextInt(10) < 7;
          final EventOccurrence from = copies[random.nextInt(copies.length)];
          final sourceId = present
              ? from.sourceId
              : sourceIds[random.nextInt(sourceIds.length)];
          final uid = present ? from.uid : 'e${random.nextInt(4)}';
          final copyKey = present
              ? from.key
              : EventOccurrence.makeKey(
                  sourceId,
                  uid,
                  starts[random.nextInt(starts.length)],
                );
          if (!linked.add(copyKey)) continue;
          links.add(
            MeetingLink(
              copyKey: copyKey,
              meetingKey: meetingKeys[random.nextInt(meetingKeys.length)],
              sourceId: sourceId,
              uid: uid,
              oneOff: random.nextBool(),
              endUtc: starts[random.nextInt(starts.length)].add(_hour),
              matchedBy: MeetingMatch.values[random.nextInt(3)],
            ),
          );
        }

        final why = 'round $round';
        final r = run(copies, links: links, sources: sources);
        expectSane(r, copies, reason: why);

        for (var i = 0; i < 2; i++) {
          final shuffled = run(
            [...copies]..shuffle(random),
            links: [...links]..shuffle(random),
            sources: sources,
          );
          expectSameResult(shuffled, r, why: '$why, order $i');
        }

        // A second run with the links just written keeps every linked copy
        // in the meeting it was linked to.
        final again = run(copies, links: r.upsert, sources: sources);
        expectSane(again, copies, reason: '$why, second run');
        for (final l in r.upsert) {
          final meeting = again.meetings.singleWhere(
            (m) => copyKeys(m).contains(l.copyKey),
          );
          expect(meeting.key, l.meetingKey, reason: '$why, ${l.copyKey} stays');
        }
      }
    });
  });
}

const _hour = Duration(hours: 1);

/// A mix of everything the merger decides, with its links and ranks: a
/// three-way merge by title, a merge by UID across different titles, a split
/// kept by a link, a moved one-off found again by its link, a duplicate
/// ejected from a meeting, a copy that matches two meetings, twins in one
/// source, and a failing source.
({
  List<EventOccurrence> copies,
  List<MeetingLink> links,
  Map<String, SourceRank> sources,
})
_mixedScenario() {
  final gone = EventOccurrence.makeKey('gone', 'g1', t0);

  // Three-way merge by title.
  final m1p = copy('phone', 'm1p', title: 'Budget review');
  final m1f = copy('feed', 'm1f', icalUid: 'm1f', title: 'Budget review');
  final m1w = copy('work', 'm1w', icalUid: 'm1w', title: 'Budget review');

  // A merge by UID: the titles differ.
  final m2p = copy('phone', 'm2p', title: 'Standup', icalUid: 'U2', start: t1);
  final m2f = copy('feed', 'U2', title: 'Daily sync', icalUid: 'U2', start: t1);

  // A split: the phone copy that keyed the meeting is gone.
  final m3f = copy('feed', 'm3f', icalUid: 'm3f', title: 'Planning', start: t2);

  // A moved one-off: found again by its old link.
  final m4old = copy('phone', 'm4', title: 'Review', start: t1);
  final m4p = copy('phone', 'm4', title: 'Review', start: t2);
  final m4f = copy('feed', 'm4f', icalUid: 'm4f', title: 'Review', start: t1);

  // A duplicate ejected from a meeting.
  final m5a = copy('work', 'm5a', icalUid: 'm5a', title: 'Retro');
  final m5b = copy('work', 'm5b', icalUid: 'm5b', title: 'Retro 2');
  final m5f = copy('feed2', 'm5f', icalUid: 'm5f', title: 'Retro');

  // A copy that matches two meetings by different keys.
  final g1p = copy('phone', 'g1p', title: 'Sync', start: t2);
  final g1f = copy('feed', 'g1f', icalUid: 'g1f', title: 'Sync', start: t2);
  final g2w = copy('work', 'g2w', icalUid: 'UU', title: 'Offsite', start: t2);
  final g2f = copy('feed2', 'UU', icalUid: 'UU', title: 'Offsite', start: t2);
  final both = copy('debug', 'both', icalUid: 'UU', title: 'Sync', start: t2);

  // Twins in one source and a copy that matches them, and a lone copy.
  final twinP = copy('phone', 'twinP', title: 'Twins', start: t2);
  final twinA = copy(
    'work',
    'twinA',
    icalUid: 'twinA',
    title: 'Twins',
    start: t2,
  );
  final twinB = copy(
    'work',
    'twinB',
    icalUid: 'twinB',
    title: 'Twins',
    start: t2,
  );
  final solo = copy('phone', 'solo', title: 'Solo', start: t2);

  final copies = [
    m1p, m1f, m1w, m2p, m2f, m3f, m4p, m4f, m5a, m5b, m5f, //
    g1p, g1f, g2w, g2f, both, twinP, twinA, twinB, solo,
  ];
  final links = [
    linkOf(m3f, gone),
    linkOf(m4old, m4old.key),
    linkOf(m4f, m4old.key),
    linkOf(m5a, m5a.key),
    linkOf(m5b, m5a.key),
    linkOf(m5f, m5a.key),
  ];
  const sources = <String, SourceRank>{
    'phone': phoneRank,
    'feed': feedRank,
    'feed2': failingFeedRank,
    'work': feedRank,
    'debug': debugRank,
  };
  return (copies: copies, links: links, sources: sources);
}
