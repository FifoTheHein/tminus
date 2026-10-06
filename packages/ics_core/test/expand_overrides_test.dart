import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final r = expandFixture(
    'modified_cancelled.ics',
    from: DateTime.utc(2026, 10, 5),
    to: DateTime.utc(2026, 11, 8),
  );
  final series = byUid(r, 'oneonone@example.com');

  test('no issues', () => expect(r.issues, isEmpty));

  test('the series shows the plain, moved and moved-in instances only', () {
    expect(series.map((o) => (o.startUtc.toIso8601String(), o.title)), [
      ('2026-10-06T08:00:00.000Z', '1:1 with Pieter'),
      ('2026-10-14T12:00:00.000Z', '1:1 with Pieter (moved)'),
      ('2026-11-06T07:00:00.000Z', '1:1 with Pieter (early)'),
    ]);
  });

  test('a moved instance keeps its original start (RECURRENCE-ID)', () {
    final moved = series[1];
    expect(moved.originalStartUtc, DateTime.utc(2026, 10, 13, 8));
    expect(moved.recurring, isTrue);
    expect(moved.endUtc, DateTime.utc(2026, 10, 14, 12, 30));
  });

  test('an override takes its own fields, not the series fields', () {
    expect(series[1].organizer, isNull);
    expect(series[0].organizer, 'Thandi M.');
  });

  test('STATUS:CANCELLED and Canceled: overrides remove their instance', () {
    final originals = series.map((o) => o.originalStartUtc).toSet();
    expect(originals, isNot(contains(DateTime.utc(2026, 10, 20, 8))));
    expect(originals, isNot(contains(DateTime.utc(2026, 10, 27, 8))));
  });

  test('an instance moved out of the window disappears', () {
    expect(
      series.map((o) => o.originalStartUtc),
      isNot(contains(DateTime.utc(2026, 11, 3, 8))),
    );
    final later = expandFixture(
      'modified_cancelled.ics',
      from: DateTime.utc(2026, 11, 12),
      to: DateTime.utc(2026, 11, 13),
    );
    expect(
      byUid(later, 'oneonone@example.com').single.originalStartUtc,
      DateTime.utc(2026, 11, 3, 8),
    );
  });

  test('an instance moved into the window appears (UTC RECURRENCE-ID)', () {
    expect(series.last.originalStartUtc, DateTime.utc(2026, 11, 10, 8));
  });

  test('the instance an override replaced does not also appear', () {
    final nov = expandFixture(
      'modified_cancelled.ics',
      from: DateTime.utc(2026, 11, 9),
      to: DateTime.utc(2026, 11, 11),
    );
    expect(byUid(nov, 'oneonone@example.com'), isEmpty);
  });

  test('an override without its series is shown on its own, recurring', () {
    final guest = byUid(r, 'guest@example.com').single;
    expect(guest.recurring, isTrue);
    expect(guest.startUtc, DateTime.utc(2026, 10, 15, 11));
    expect(guest.originalStartUtc, DateTime.utc(2026, 10, 15, 11));
  });

  test('a cancelled series drops its overrides too', () {
    expect(byUid(r, 'cancelled-series@example.com'), isEmpty);
  });

  test('a series that starts after the window keeps an override moved in', () {
    final r = expandIcs(
      calendar('''
BEGIN:VEVENT
UID:later
SUMMARY:Series
DTSTART;TZID=Europe/London:20261201T090000
RRULE:FREQ=WEEKLY;COUNT=4
END:VEVENT
BEGIN:VEVENT
UID:later
SUMMARY:Moved early
RECURRENCE-ID;TZID=Europe/London:20261201T090000
DTSTART;TZID=Europe/London:20261005T090000
END:VEVENT'''),
      windowStartUtc: DateTime.utc(2026, 10, 1),
      windowEndUtc: DateTime.utc(2026, 10, 8),
      deviceZone: 'Africa/Johannesburg',
    );
    expect(r.issues, isEmpty);
    final moved = r.occurrences.single;
    expect(moved.title, 'Moved early');
    expect(moved.startUtc, DateTime.utc(2026, 10, 5, 8));
    expect(moved.originalStartUtc, DateTime.utc(2026, 12, 1, 9));
  });
}
