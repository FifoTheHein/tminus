import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/meeting_occurrence.dart';

import '../fixtures.dart';
import '../rules/rules_test_helpers.dart' show meetingOf;

void main() {
  // Ranked best first: the phone copy decides the time.
  final phone = occ(sourceId: 'phone', uid: 'p1', seriesUid: 'phone-series');
  final feed = occ(sourceId: 'feed', uid: 'f1', seriesUid: 'feed-series');
  final work = occ(sourceId: 'work', uid: 'w1'); // a one-off: no series
  // The key a source that has since gone gave the meeting. No copy has it.
  final meetingKey = EventOccurrence.makeKey(
    'gone',
    'm1',
    phone.originalStartUtc,
  );

  group('lookups', () {
    test('lookupKeys start with the meeting key and hold no duplicates', () {
      final meeting = meetingOf([phone, feed, work], meetingKey: meetingKey);
      expect(meeting.key, meetingKey);
      expect(meeting.lookupKeys, [meetingKey, phone.key, feed.key, work.key]);

      // A new meeting takes its top-ranked copy's key, which is listed once.
      final fresh = meetingOf([phone, feed]);
      expect(fresh.key, phone.key);
      expect(fresh.lookupKeys, [phone.key, feed.key]);

      // When the ranking has since changed, the meeting key is still first
      // and the copy that holds it is not listed again.
      final reranked = meetingOf([phone, feed], meetingKey: feed.key);
      expect(reranked.lookupKeys, [feed.key, phone.key]);
    });

    test("lookupSeriesUids hold the copies' series uids in rank order, "
        'without gaps or duplicates', () {
      final meeting = meetingOf([
        occ(sourceId: 'phone', uid: 'p1', seriesUid: 'series-a'),
        occ(sourceId: 'feed', uid: 'f1', seriesUid: 'series-b'),
        occ(sourceId: 'work', uid: 'w1'), // a one-off: no series
        occ(sourceId: 'archive', uid: 'a1', seriesUid: 'series-a'),
      ]);
      expect(meeting.lookupSeriesUids, ['series-a', 'series-b']);
      expect(meetingOf([work]).lookupSeriesUids, isEmpty);
    });

    test("sourceIds list the copies' sources in rank order without "
        'duplicates', () {
      final meeting = meetingOf([
        occ(sourceId: 'phone', uid: 'p1'),
        occ(sourceId: 'feed', uid: 'f1'),
        occ(sourceId: 'phone', uid: 'p2'),
      ]);
      expect(meeting.sourceIds, ['phone', 'feed']);
    });

    test('a plain copy looks up only itself', () {
      expect(phone.lookupKeys, [phone.key]);
      expect(phone.lookupSeriesUids, ['phone-series']);
      expect(phone.sourceIds, ['phone']);
      expect(work.lookupSeriesUids, isEmpty);
    });
  });

  group('copyWith', () {
    test('copyWith keeps a MeetingOccurrence and its meeting fields', () {
      final top = phone.copyWith(icalUid: 'ical-1');
      final meeting = meetingOf([top, feed, work], meetingKey: meetingKey);
      // Typed as the base class, the way the rules and the planner hold it.
      final EventOccurrence held = meeting;
      final later = DateTime.utc(2026, 10, 6, 9);

      final moved = held.copyWith(
        startUtc: later,
        endUtc: later.add(const Duration(minutes: 30)),
        title: 'Renamed',
      );

      expect(
        moved,
        isA<MeetingOccurrence>()
            .having((m) => m.meetingKey, 'meetingKey', meetingKey)
            .having((m) => m.key, 'key', meetingKey)
            .having((m) => m.copies, 'copies', meeting.copies)
            .having((m) => m.timeSourceId, 'timeSourceId', 'phone')
            .having((m) => m.seriesUid, 'seriesUid', 'phone-series')
            .having((m) => m.icalUid, 'icalUid', 'ical-1')
            .having((m) => m.lookupKeys, 'lookupKeys', meeting.lookupKeys)
            .having((m) => m.sourceIds, 'sourceIds', meeting.sourceIds)
            .having((m) => m.startUtc, 'startUtc', later)
            .having((m) => m.title, 'title', 'Renamed'),
      );
      expect(held.copyWith(), meeting, reason: 'no field is dropped');
    });
  });

  group('equality', () {
    MeetingOccurrence build({
      String? key,
      List<EventOccurrence>? copies,
      String? timeSourceId,
    }) => MeetingOccurrence(
      sourceId: phone.sourceId,
      uid: phone.uid,
      originalStartUtc: phone.originalStartUtc,
      seriesUid: phone.seriesUid,
      title: phone.title,
      startUtc: phone.startUtc,
      endUtc: phone.endUtc,
      calendarColor: phone.calendarColor,
      meetingKey: key ?? meetingKey,
      copies: copies ?? [phone, feed],
      timeSourceId: timeSourceId ?? 'phone',
    );

    test('meetings with equal fields and copies are equal and hash alike', () {
      final a = build();
      final b = build();
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('meetings differing in meeting key, copies or time source are not '
        'equal', () {
      final original = build();
      expect(
        build(key: 'other|m2|2026-10-06T08:00:00.000Z') == original,
        isFalse,
      );
      expect(
        build(copies: [phone]) == original,
        isFalse,
        reason: 'fewer copies',
      );
      expect(
        build(copies: [phone, work]) == original,
        isFalse,
        reason: 'a different copy',
      );
      expect(
        build(copies: [feed, phone]) == original,
        isFalse,
        reason: 'another rank order',
      );
      expect(build(timeSourceId: 'feed') == original, isFalse);
    });

    test('a meeting never equals a plain copy with the same fields', () {
      final meeting = meetingOf([phone], meetingKey: phone.key);
      expect(meeting.key, phone.key);
      expect(meeting == phone, isFalse);
      expect(phone == meeting, isFalse);
    });
  });

  group('construction', () {
    test('copies are copied in, so the caller cannot change a meeting '
        'afterwards', () {
      final list = [phone, feed];
      final meeting = meetingOf(list);
      list.add(work);
      expect(meeting.copies, [phone, feed]);
      expect(() => meeting.copies.add(work), throwsUnsupportedError);
    });

    test('a meeting needs at least one copy', () {
      expect(
        () => MeetingOccurrence(
          sourceId: phone.sourceId,
          uid: phone.uid,
          originalStartUtc: phone.originalStartUtc,
          title: phone.title,
          startUtc: phone.startUtc,
          endUtc: phone.endUtc,
          calendarColor: phone.calendarColor,
          meetingKey: meetingKey,
          copies: const [],
          timeSourceId: phone.sourceId,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
