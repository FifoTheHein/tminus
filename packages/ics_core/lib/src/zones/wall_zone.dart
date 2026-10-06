import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../component.dart';
import '../values.dart';

/// Converts between wall-clock times and UTC instants for one zone.
///
/// Wall-clock times are carried in UTC [DateTime]s whose fields are the
/// local date and time (the same convention `package:rrule` uses).
abstract interface class WallZone {
  /// The real UTC instant for a wall-clock time in this zone.
  DateTime wallToUtc(DateTime wall);

  /// This zone's wall-clock time at a UTC instant.
  DateTime utcToWall(DateTime utc);
}

/// UTC itself: wall time and instant are the same.
class UtcZone implements WallZone {
  const UtcZone();

  @override
  DateTime wallToUtc(DateTime wall) => wall;

  @override
  DateTime utcToWall(DateTime utc) => utc.toUtc();
}

/// A zone from the IANA database (`package:timezone`).
///
/// A wall time inside a spring-forward gap moves forward by the gap
/// (02:30 becomes 03:30); an ambiguous fall-back time uses the first
/// instant (RFC 5545 §3.3.5), i.e. the offset in force before the change.
class IanaZone implements WallZone {
  IanaZone(this.location);

  final tz.Location location;

  @override
  DateTime wallToUtc(DateTime wall) => _instantOf(wall, utcToWall);

  @override
  DateTime utcToWall(DateTime utc) {
    final local = tz.TZDateTime.from(utc, location);
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
  }
}

/// One STANDARD or DAYLIGHT block of a VTIMEZONE.
class _Observance {
  const _Observance({
    required this.startWall,
    required this.offsetFrom,
    required this.offsetTo,
    this.rule,
  });

  /// DTSTART: the first onset, in the wall time in force before it.
  final DateTime startWall;
  final Duration offsetFrom;
  final Duration offsetTo;

  /// The yearly onset rule, or null for a single onset at [startWall].
  final RecurrenceRule? rule;
}

/// A zone computed from a feed's own VTIMEZONE definition.
///
/// Supports STANDARD/DAYLIGHT blocks with DTSTART, TZOFFSETFROM, TZOFFSETTO
/// and an optional yearly RRULE (which is what Outlook writes). RDATE is
/// not supported. Gaps and repeated hours are handled like [IanaZone].
class VtimezoneZone implements WallZone {
  VtimezoneZone._(this._observances);

  final List<_Observance> _observances;
  final Map<int, List<(DateTime, Duration)>> _onsetsByYear = {};

  /// Builds a zone from a VTIMEZONE component.
  ///
  /// Throws [FormatException] if it has no usable STANDARD/DAYLIGHT block.
  factory VtimezoneZone.fromComponent(Component vtimezone) {
    final observances = <_Observance>[];
    for (final block in vtimezone.children) {
      if (block.name != 'STANDARD' && block.name != 'DAYLIGHT') {
        continue;
      }
      final dtstart = block.first('DTSTART');
      final from = block.first('TZOFFSETFROM');
      final to = block.first('TZOFFSETTO');
      if (dtstart == null || from == null || to == null) {
        throw FormatException(
          '${block.name} block needs DTSTART, TZOFFSETFROM and TZOFFSETTO',
        );
      }
      final startWall = parseIcsTime(dtstart.value).wall;
      final offsetFrom = parseUtcOffset(from.value);
      final rrule = block.first('RRULE');
      observances.add(
        _Observance(
          startWall: startWall,
          offsetFrom: offsetFrom,
          offsetTo: parseUtcOffset(to.value),
          rule: rrule == null
              ? null
              : parseRrule(
                  rrule.value,
                  untilUtcToWall: (u) => u.add(offsetFrom),
                  startIsDate: false,
                ),
        ),
      );
    }
    if (observances.isEmpty) {
      throw const FormatException(
        'VTIMEZONE has no STANDARD or DAYLIGHT block',
      );
    }
    return VtimezoneZone._(observances);
  }

  /// The UTC offset in force at [utc].
  Duration offsetAt(DateTime utc) {
    (DateTime, Duration)? best;
    for (final year in [utc.year - 1, utc.year]) {
      for (final onset in _onsets(year)) {
        if (!onset.$1.isAfter(utc) &&
            (best == null || onset.$1.isAfter(best.$1))) {
          best = onset;
        }
      }
    }
    if (best != null) {
      return best.$2;
    }
    // Before every rule-based onset we looked at: use the latest single
    // onset that has happened, else the first block's TZOFFSETFROM.
    _Observance? latest;
    for (final o in _observances) {
      final onsetUtc = o.startWall.subtract(o.offsetFrom);
      if (!onsetUtc.isAfter(utc) &&
          (latest == null ||
              onsetUtc.isAfter(latest.startWall.subtract(latest.offsetFrom)))) {
        latest = o;
      }
    }
    return latest?.offsetTo ?? _observances.first.offsetFrom;
  }

  List<(DateTime, Duration)> _onsets(int year) =>
      _onsetsByYear.putIfAbsent(year, () {
        final from = DateTime.utc(year);
        final to = DateTime.utc(year + 1);
        final result = <(DateTime, Duration)>[];
        for (final o in _observances) {
          final walls = o.rule == null
              ? [o.startWall]
              : o.rule!
                    .getInstances(
                      start: o.startWall,
                      after: from,
                      includeAfter: true,
                      before: to,
                    )
                    .toList();
          for (final wall in walls) {
            if (!wall.isBefore(from) && wall.isBefore(to)) {
              result.add((wall.subtract(o.offsetFrom), o.offsetTo));
            }
          }
        }
        return result;
      });

  @override
  DateTime wallToUtc(DateTime wall) => _instantOf(wall, utcToWall);

  @override
  DateTime utcToWall(DateTime utc) => utc.toUtc().add(offsetAt(utc));
}

/// The UTC instant of [wall] in the zone [utcToWall] describes.
///
/// Tries the offsets in force a day either side of [wall] (read as UTC,
/// which is within a day of the real instant). Of those that map back to
/// [wall], the larger offset gives the earlier instant, which RFC 5545
/// §3.3.5 picks for a time repeated at a fall-back change. If neither does,
/// [wall] is in a spring-forward gap, and the offset from before the change
/// moves it forward by the gap.
DateTime _instantOf(DateTime wall, DateTime Function(DateTime) utcToWall) {
  Duration offsetAt(DateTime utc) => utcToWall(utc).difference(utc);
  const day = Duration(days: 1);
  final before = offsetAt(wall.subtract(day));
  final after = offsetAt(wall.add(day));
  for (final offset in before >= after ? [before, after] : [after, before]) {
    final utc = wall.subtract(offset);
    if (utcToWall(utc) == wall) {
      return utc;
    }
  }
  return wall.subtract(before);
}

final _offsetPattern = RegExp(r'^([+-])(\d{2})(\d{2})(\d{2})?$');

/// Parses a UTC-OFFSET value such as `+0200`, `-0700` or `+053000`.
Duration parseUtcOffset(String value) {
  final m = _offsetPattern.firstMatch(value.trim());
  if (m == null) {
    throw FormatException('Bad UTC offset: "$value"');
  }
  final d = Duration(
    hours: int.parse(m[2]!),
    minutes: int.parse(m[3]!),
    seconds: m[4] == null ? 0 : int.parse(m[4]!),
  );
  return m[1] == '-' ? -d : d;
}
