import 'package:flutter_test/flutter_test.dart';
import 'package:ics_core/ics_core.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/occurrence_mapping.dart';

void main() {
  const work = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.work',
  );

  IcsOccurrence ics({
    bool recurring = false,
    IcsBusyStatus busy = IcsBusyStatus.busy,
    Set<IcsWarning> warnings = const {},
  }) => IcsOccurrence(
    uid: 'uid1',
    originalStartUtc: DateTime.utc(2026, 10, 12, 7),
    recurring: recurring,
    title: 'Sprint planning',
    location: 'Room 4',
    organizer: 'Thandi M.',
    description: 'Agenda',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/abc',
    startUtc: DateTime.utc(2026, 10, 12, 8),
    endUtc: DateTime.utc(2026, 10, 12, 9),
    allDay: false,
    busyStatus: busy,
    warnings: warnings,
  );

  test('an ICS occurrence maps field by field, with the source colour', () {
    final o = occurrenceFromIcs(ics(), work);
    expect(o.sourceId, 'work');
    expect(o.uid, 'uid1');
    expect(o.originalStartUtc, DateTime.utc(2026, 10, 12, 7));
    expect(o.seriesUid, isNull);
    expect(o.title, 'Sprint planning');
    expect(o.location, 'Room 4');
    expect(o.organizer, 'Thandi M.');
    expect(o.description, 'Agenda');
    expect(o.joinUrl, 'https://teams.microsoft.com/l/meetup-join/abc');
    expect(o.startUtc, DateTime.utc(2026, 10, 12, 8));
    expect(o.endUtc, DateTime.utc(2026, 10, 12, 9));
    expect(o.busyStatus, BusyStatus.busy);
    expect(o.declined, isFalse);
    expect(o.cancelled, isFalse);
    expect(o.calendarColor, 0xFF6AA0F5);
    expect(o.warnings, isEmpty);
    expect(o.key, 'work|uid1|2026-10-12T07:00:00.000Z');
  });

  test('a recurring instance gets its uid as seriesUid', () {
    expect(occurrenceFromIcs(ics(recurring: true), work).seriesUid, 'uid1');
  });

  test('both time-zone warnings become tzFallback', () {
    for (final w in IcsWarning.values) {
      expect(occurrenceFromIcs(ics(warnings: {w}), work).warnings, {
        OccurrenceWarning.tzFallback,
      });
    }
  });

  test('every busy status maps by name', () {
    for (final b in IcsBusyStatus.values) {
      expect(occurrenceFromIcs(ics(busy: b), work).busyStatus.name, b.name);
    }
  });

  test('the fetch window is one hour back and seven days ahead', () {
    final w = FetchWindow.around(DateTime.utc(2026, 10, 6, 8));
    expect(w.startUtc, DateTime.utc(2026, 10, 6, 7));
    expect(w.endUtc, DateTime.utc(2026, 10, 13, 8));
  });
}
