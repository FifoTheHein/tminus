import 'model.dart';
import 'values.dart';
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

/// The UTC instant a RECURRENCE-ID or EXDATE value names.
DateTime _instantOf(IcsTime t, ZoneResolver zones) => t.isDate
    ? zones.device.wallToUtc(_date(t.wall))
    : zones.forTime(t).zone.wallToUtc(t.wall);

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

/// An override whose series is missing from the feed (e.g. you were invited
/// to one instance only): shown on its own, still marked recurring.
List<IcsOccurrence> expandOrphanOverride(
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
    _occurrence(
      e,
      timing,
      originalStartUtc: _instantOf(e.recurrenceId!, zones),
      recurring: true,
    ),
  ];
}

/// The most instances one series may have around the window. `rrule`
/// already stops at the window end; this bounds rules such as one with
/// BYHOUR and BYMINUTE lists that yield thousands of instances a day.
const maxInstancesPerSeries = 10000;

/// An RRULE series plus its RECURRENCE-ID overrides.
///
/// The rule is expanded in the event's own wall-clock zone, so a 09:00
/// meeting stays at 09:00 local time across DST changes, then each instance
/// is converted to UTC. EXDATEs remove instances; every override replaces
/// the instance whose original start it names (wherever the override now
/// lands); cancelled overrides just remove it. A cancelled series yields
/// nothing.
///
/// Throws [FormatException] (or whatever `package:rrule` throws) for a bad
/// rule, or one with more than [maxInstancesPerSeries] instances.
List<IcsOccurrence> expandSeries(
  ParsedEvent master,
  List<ParsedEvent> overrides,
  ZoneResolver zones,
  IcsWindow window,
) {
  if (master.cancelled) {
    return const [];
  }
  final allDay = master.allDay;
  final masterTiming = _timingOf(master, zones);
  final zone = allDay ? zones.device : zones.forTime(master.start).zone;
  final rule = parseRrule(
    master.rrule!,
    untilUtcToWall: zone.utcToWall,
    startIsDate: allDay,
  );
  final startWall = allDay ? _date(master.start.wall) : master.start.wall;
  final length = masterTiming.endUtc.difference(masterTiming.startUtc);
  final allDayDays = allDay ? _allDayLength(master) : 0;
  final margin = const Duration(days: 2);
  final afterWall = zone.utcToWall(window.start).subtract(length + margin);
  final beforeWall = zone.utcToWall(window.end).add(margin);

  final excluded = {for (final ex in master.exdates) _instantOf(ex, zones)};
  final overridden = {
    for (final o in overrides) _instantOf(o.recurrenceId!, zones),
  };

  final result = <IcsOccurrence>[];
  var iterated = 0;
  // A series that starts after the window has no instances in it (and
  // rrule asserts `before >= start`), but its overrides may move into it.
  final walls = beforeWall.isBefore(startWall)
      ? const <DateTime>[]
      : rule.getInstances(
          start: startWall,
          after: afterWall.isAfter(startWall) ? afterWall : null,
          includeAfter: true,
          before: beforeWall,
          includeBefore: true,
        );
  for (final wall in walls) {
    if (++iterated > maxInstancesPerSeries) {
      throw const FormatException(
        'RRULE has more than $maxInstancesPerSeries instances in the window',
      );
    }
    final startUtc = zone.wallToUtc(wall);
    if (excluded.contains(startUtc) || overridden.contains(startUtc)) {
      continue;
    }
    final endUtc = allDay
        ? zone.wallToUtc(wall.add(Duration(days: allDayDays)))
        : startUtc.add(length);
    if (!window.overlaps(startUtc, endUtc)) {
      continue;
    }
    result.add(
      _occurrence(
        master,
        _Timing(startUtc, endUtc, masterTiming.warnings),
        originalStartUtc: startUtc,
        recurring: true,
      ),
    );
  }

  for (final o in overrides) {
    if (o.cancelled) {
      continue;
    }
    final timing = _timingOf(o, zones);
    if (!window.overlaps(timing.startUtc, timing.endUtc)) {
      continue;
    }
    result.add(
      _occurrence(
        o,
        timing,
        originalStartUtc: _instantOf(o.recurrenceId!, zones),
        recurring: true,
      ),
    );
  }
  return result;
}
