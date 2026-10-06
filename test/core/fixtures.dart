import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/model/event_occurrence.dart';

/// Loads the IANA database once per test file. Safe to call repeatedly.
void initZones() {
  if (_zonesLoaded) return;
  tzdata.initializeTimeZones();
  _zonesLoaded = true;
}

var _zonesLoaded = false;

/// UTC+2 all year, no DST.
tz.Location get johannesburg {
  initZones();
  return tz.getLocation('Africa/Johannesburg');
}

/// DST zone: GMT in winter, BST (UTC+1) from 29 Mar 2026 to 25 Oct 2026.
tz.Location get london {
  initZones();
  return tz.getLocation('Europe/London');
}

const blue = 0xFF6AA0F5;

/// An occurrence with sensible defaults; override only what a test needs.
EventOccurrence occ({
  String sourceId = 'work',
  String uid = 'uid1',
  DateTime? start,
  DateTime? originalStart,
  Duration length = const Duration(minutes: 30),
  String? seriesUid,
  String title = 'Sprint planning',
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
  final s = start ?? DateTime.utc(2026, 10, 6, 8); // 10:00 in Johannesburg
  return EventOccurrence(
    sourceId: sourceId,
    uid: uid,
    originalStartUtc: originalStart ?? s,
    seriesUid: seriesUid,
    title: title,
    location: location,
    organizer: organizer,
    description: description,
    joinUrl: joinUrl,
    startUtc: s,
    endUtc: s.add(length),
    allDay: allDay,
    busyStatus: busyStatus,
    declined: declined,
    cancelled: cancelled,
    calendarColor: color,
  );
}
