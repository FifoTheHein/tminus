import 'model.dart';
import 'vevent.dart';
import 'zones/zone_resolver.dart';

/// The requested window: occurrences overlapping `[start, end)` are kept.
class IcsWindow {
  IcsWindow(DateTime start, DateTime end)
    : start = start.toUtc(),
      end = end.toUtc() {
    if (!this.end.isAfter(this.start)) {
      throw ArgumentError('windowEndUtc must be after windowStartUtc');
    }
  }

  final DateTime start;
  final DateTime end;

  /// True if `[startUtc, endUtc)` overlaps the window. A zero-length event
  /// counts if it starts inside the window.
  bool overlaps(DateTime startUtc, DateTime endUtc) =>
      startUtc.isBefore(end) &&
      (endUtc.isAfter(start) || !startUtc.isBefore(start));
}

/// Start, end and warnings of one concrete instance.
class _Timing {
  const _Timing(this.startUtc, this.endUtc, this.warnings);

  final DateTime startUtc;
  final DateTime endUtc;
  final Set<IcsWarning> warnings;
}

DateTime _date(DateTime wall) => DateTime.utc(wall.year, wall.month, wall.day);

/// Number of whole days an all-day event lasts (at least 1).
int _allDayLength(ParsedEvent e) {
  final startDate = _date(e.start.wall);
  int days;
  if (e.end != null) {
    days = _date(e.end!.wall).difference(startDate).inDays;
  } else if (e.duration != null) {
    days = (e.duration!.inMinutes / Duration.minutesPerDay).ceil();
  } else {
    days = 1;
  }
  return days < 1 ? 1 : days;
}

/// When [e] itself (DTSTART/DTEND/DURATION) happens.
_Timing _timingOf(ParsedEvent e, ZoneResolver zones) {
  if (e.allDay) {
    final startDate = _date(e.start.wall);
    return _Timing(
      zones.device.wallToUtc(startDate),
      zones.device.wallToUtc(startDate.add(Duration(days: _allDayLength(e)))),
      const {},
    );
  }
  final startZone = zones.forTime(e.start);
  final warnings = {if (startZone.warning != null) startZone.warning!};
  final startUtc = startZone.zone.wallToUtc(e.start.wall);
  var endUtc = startUtc;
  if (e.end != null) {
    final endZone = e.end!.isDate ? startZone : zones.forTime(e.end!);
    if (endZone.warning != null) {
      warnings.add(endZone.warning!);
    }
    endUtc = endZone.zone.wallToUtc(e.end!.wall);
  } else if (e.duration != null) {
    endUtc = startUtc.add(e.duration!);
  }
  if (endUtc.isBefore(startUtc)) {
    endUtc = startUtc;
  }
  return _Timing(startUtc, endUtc, warnings);
}

IcsOccurrence _occurrence(
  ParsedEvent e,
  _Timing timing, {
  required DateTime originalStartUtc,
  required bool recurring,
}) => IcsOccurrence(
  uid: e.uid,
  originalStartUtc: originalStartUtc,
  recurring: recurring,
  title: e.title,
  location: e.location,
  organizer: e.organizer,
  description: e.description,
  joinUrl: e.joinUrl,
  startUtc: timing.startUtc,
  endUtc: timing.endUtc,
  allDay: e.allDay,
  busyStatus: e.busyStatus,
  warnings: timing.warnings,
);

/// A one-off event (no RRULE, no RECURRENCE-ID): zero or one occurrence.
List<IcsOccurrence> expandSingle(
  ParsedEvent e,
  ZoneResolver zones,
  IcsWindow window,
) {
  if (e.cancelled) {
    return const [];
  }
  final timing = _timingOf(e, zones);
  if (!window.overlaps(timing.startUtc, timing.endUtc)) {
    return const [];
  }
  return [
    _occurrence(e, timing, originalStartUtc: timing.startUtc, recurring: false),
  ];
}
