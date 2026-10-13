import 'package:flutter_test/flutter_test.dart';
import 'package:ics_core/ics_core.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/device_calendar_api.dart';
import 'package:tminus/core/sources/occurrence_mapping.dart';

import '../fixtures.dart';

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

  test('an ICS copy carries its UID as icalUid', () {
    expect(occurrenceFromIcs(ics(), work).icalUid, 'uid1');
    // A recurring instance carries the series' UID, which is also its uid.
    final instance = occurrenceFromIcs(ics(recurring: true), work);
    expect(instance.icalUid, 'uid1');
    expect(instance.icalUid, instance.uid);
  });

  test('a phone copy has no icalUid', () {
    const phone = SourceConfig(
      id: 'phone',
      name: 'Outlook on the phone',
      color: 0xFF33AA66,
      kind: SourceKind.device,
      deviceCalendarId: '3',
    );
    final begin = DateTime.utc(2026, 10, 12, 8);
    DeviceInstance instance({
      String? originalId,
      int? originalInstanceTimeMs,
      bool recurring = false,
    }) => DeviceInstance(
      eventId: '10',
      calendarId: '3',
      beginMs: begin.millisecondsSinceEpoch,
      endMs: begin.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      allDay: false,
      title: 'Sprint planning',
      availability: DeviceInstance.availabilityBusy,
      selfAttendeeStatus: 1,
      originalId: originalId,
      originalInstanceTimeMs: originalInstanceTimeMs,
      recurring: recurring,
    );

    // A one-off, a series instance and a moved instance of a series.
    final copies = [
      occurrenceFromDevice(instance(), phone, johannesburg),
      occurrenceFromDevice(instance(recurring: true), phone, johannesburg),
      occurrenceFromDevice(
        instance(
          originalId: '9',
          originalInstanceTimeMs: begin
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ),
        phone,
        johannesburg,
      ),
    ];
    expect(copies.map((c) => c.icalUid), everyElement(isNull));
    expect(copies.map((c) => c.sourceId), everyElement('phone'));
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

  /// Whether the phone event with this title and calendar status maps to a
  /// cancelled occurrence.
  bool phoneEventCancelled(String? title, {int? status}) =>
      occurrenceFromDevice(
        DeviceInstance(
          eventId: '10',
          calendarId: '3',
          beginMs: DateTime.utc(2026, 10, 12, 8).millisecondsSinceEpoch,
          endMs: DateTime.utc(2026, 10, 12, 9).millisecondsSinceEpoch,
          allDay: false,
          title: title,
          availability: DeviceInstance.availabilityBusy,
          selfAttendeeStatus: 1,
          status: status,
          recurring: false,
        ),
        const SourceConfig(
          id: 'phone',
          name: 'Outlook on the phone',
          color: 0xFF33AA66,
          kind: SourceKind.device,
          deviceCalendarId: '3',
        ),
        johannesburg,
      ).cancelled;

  test('a phone event titled Canceled: is cancelled', () {
    for (final title in [
      'Canceled: Sprint planning',
      'Cancelled: Sprint planning',
      '  canceled: Sprint planning',
    ]) {
      expect(phoneEventCancelled(title), isTrue, reason: title);
    }
    // The calendar's own cancelled status still counts.
    expect(
      phoneEventCancelled(
        'Sprint planning',
        status: DeviceInstance.statusCancelled,
      ),
      isTrue,
    );
  });

  test('a phone title merely containing "cancelled" is not', () {
    for (final title in <String?>[
      'Sprint planning (cancelled?)',
      'Was cancelled: no, it is on',
      'Re: Canceled: thing',
      'Cancellation policy review',
      'Canceled',
      '',
      null,
    ]) {
      expect(phoneEventCancelled(title), isFalse, reason: '$title');
    }
  });
}
