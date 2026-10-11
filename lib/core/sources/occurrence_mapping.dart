import 'package:ics_core/ics_core.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/event_occurrence.dart';
import '../model/source_config.dart';
import 'device_calendar_api.dart';

/// Roadmap §2: `seriesUid = recurring ? uid : null`, both ICS warnings become
/// [OccurrenceWarning.tzFallback], never cancelled or declined (ICS feeds
/// carry neither). The colour is the source's. [EventOccurrence.icalUid] is
/// the feed's UID, the strong key for merging with a copy from another source
/// (spec §13).
EventOccurrence occurrenceFromIcs(IcsOccurrence o, SourceConfig source) =>
    EventOccurrence(
      sourceId: source.id,
      uid: o.uid,
      originalStartUtc: o.originalStartUtc,
      seriesUid: o.recurring ? o.uid : null,
      icalUid: o.uid,
      title: o.title,
      location: o.location,
      organizer: o.organizer,
      description: o.description,
      joinUrl: o.joinUrl,
      startUtc: o.startUtc,
      endUtc: o.endUtc,
      allDay: o.allDay,
      busyStatus: switch (o.busyStatus) {
        IcsBusyStatus.free => BusyStatus.free,
        IcsBusyStatus.tentative => BusyStatus.tentative,
        IcsBusyStatus.busy => BusyStatus.busy,
        IcsBusyStatus.oof => BusyStatus.oof,
        IcsBusyStatus.unknown => BusyStatus.unknown,
      },
      calendarColor: source.color,
      warnings: o.warnings.isEmpty ? const {} : {OccurrenceWarning.tzFallback},
    );

/// A `CalendarContract.Instances` row as an occurrence, keyed like ICS
/// (Plan 4 decision): uid is the series' event id for any instance of a
/// series (`ORIGINAL_ID` for a moved one), and the original start is
/// `ORIGINAL_INSTANCE_TIME`, else `BEGIN`. All-day instances arrive as UTC
/// midnights and become local midnights in [zone], as `ics_core` does. A phone
/// copy has no [EventOccurrence.icalUid]: the calendar provider has no column
/// the app reads that holds it.
EventOccurrence occurrenceFromDevice(
  DeviceInstance i,
  SourceConfig source,
  tz.Location zone,
) {
  DateTime instant(int ms) {
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    if (!i.allDay) return utc;
    return tz.TZDateTime(zone, utc.year, utc.month, utc.day);
  }

  final uid = i.originalId ?? i.eventId;
  final title = i.title?.trim() ?? '';
  return EventOccurrence(
    sourceId: source.id,
    uid: uid,
    originalStartUtc: instant(i.originalInstanceTimeMs ?? i.beginMs),
    seriesUid: i.recurring || i.originalId != null ? uid : null,
    title: title.isEmpty ? '(No title)' : title,
    location: _blankToNull(i.location),
    organizer: _blankToNull(i.organizer),
    description: _blankToNull(i.description),
    joinUrl: extractTeamsJoinUrl(i.description, i.location),
    startUtc: instant(i.beginMs),
    endUtc: instant(i.endMs),
    allDay: i.allDay,
    busyStatus: switch (i.availability) {
      DeviceInstance.availabilityBusy => BusyStatus.busy,
      DeviceInstance.availabilityFree => BusyStatus.free,
      DeviceInstance.availabilityTentative => BusyStatus.tentative,
      _ => BusyStatus.unknown,
    },
    declined: i.selfAttendeeStatus == DeviceInstance.attendeeDeclined,
    cancelled: i.status == DeviceInstance.statusCancelled,
    calendarColor: source.color,
  );
}

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s;
