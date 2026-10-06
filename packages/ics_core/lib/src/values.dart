import 'package:rrule/rrule.dart';

import 'content_line.dart';

/// A DATE or DATE-TIME value as written in the feed.
class IcsTime {
  const IcsTime({
    required this.wall,
    required this.isDate,
    required this.isUtc,
    this.tzid,
  });

  /// The written date/time fields, held in a UTC [DateTime] (no zone applied).
  final DateTime wall;

  /// A DATE value (no time part).
  final bool isDate;

  /// The value ended in `Z`.
  final bool isUtc;

  /// The TZID parameter, trimmed; null for UTC, DATE or floating values.
  final String? tzid;

  @override
  bool operator ==(Object other) =>
      other is IcsTime &&
      other.wall == wall &&
      other.isDate == isDate &&
      other.isUtc == isUtc &&
      other.tzid == tzid;

  @override
  int get hashCode => Object.hash(wall, isDate, isUtc, tzid);

  @override
  String toString() =>
      'IcsTime(${wall.toIso8601String()}, date: $isDate, utc: $isUtc, tzid: $tzid)';
}

final _dateTimePattern = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$',
);

/// Parses one DATE (`20261012`) or DATE-TIME (`20261012T090000`, `…Z`) value.
///
/// Throws [FormatException] for anything else, including impossible dates
/// such as `20261332` (Dart's own `DateTime.parse` would roll those over).
IcsTime parseIcsTime(String value, {String? tzid}) {
  final m = _dateTimePattern.firstMatch(value.trim());
  if (m == null) {
    throw FormatException('Bad date or date-time: "$value"');
  }
  final year = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final day = int.parse(m[3]!);
  final isDate = m[4] == null;
  final hour = isDate ? 0 : int.parse(m[4]!);
  final minute = isDate ? 0 : int.parse(m[5]!);
  var second = isDate ? 0 : int.parse(m[6]!);
  if (second == 60) {
    second = 59; // leap second
  }
  final daysInMonth = DateTime.utc(year, month + 1, 0).day;
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > daysInMonth ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    throw FormatException('Bad date or date-time: "$value"');
  }
  final isUtc = m[7] != null;
  final cleanTzid = tzid?.trim();
  return IcsTime(
    wall: DateTime.utc(year, month, day, hour, minute, second),
    isDate: isDate,
    isUtc: isUtc,
    tzid: isUtc || isDate || cleanTzid == null || cleanTzid.isEmpty
        ? null
        : cleanTzid,
  );
}

/// Parses a property such as DTSTART, DTEND, RECURRENCE-ID or EXDATE,
/// honouring its TZID parameter. EXDATE may hold several comma-separated values.
List<IcsTime> parseIcsTimes(ContentLine line) => [
  for (final part in line.value.split(','))
    if (part.trim().isNotEmpty) parseIcsTime(part, tzid: line.params['TZID']),
];

final _durationPattern = RegExp(
  r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
);

/// Parses a DURATION value such as `PT1H30M`, `P1D` or `P2W`.
///
/// Throws [FormatException] for malformed or negative durations.
Duration parseIcsDuration(String value) {
  final v = value.trim().toUpperCase();
  final m = _durationPattern.firstMatch(v);
  if (m == null || v.endsWith('P') || v.endsWith('T')) {
    throw FormatException('Bad DURATION: "$value"');
  }
  if (m[1] == '-') {
    throw FormatException('Negative DURATION: "$value"');
  }
  int part(int i) => m[i] == null ? 0 : int.parse(m[i]!);
  return Duration(
    days: part(2) * 7 + part(3),
    hours: part(4),
    minutes: part(5),
    seconds: part(6),
  );
}

/// Builds an `rrule` [RecurrenceRule] that works on wall-clock times.
///
/// `package:rrule` ignores time zones: it treats every [DateTime] as a
/// wall-clock value and drops the `Z` from UNTIL. So:
/// * a UTC UNTIL is converted to the event's wall clock with [untilUtcToWall];
/// * a DATE UNTIL on a timed event means "through the end of that day";
/// * a DATE-TIME UNTIL on an all-day event keeps only its date;
/// * WKST is dropped because `rrule` 0.2.18 rejects anything but MO (Outlook
///   writes WKST=SU). This only changes results for weekly rules with
///   INTERVAL > 1 whose BYDAY days straddle Sunday.
///
/// Rules `package:rrule` would expand forever, or for thousands of years,
/// once asserts are off (a release build) are rejected too: INTERVAL or
/// COUNT below 1, HOURLY/MINUTELY/SECONDLY frequencies (Outlook never
/// writes them) and BYMONTH/BYMONTHDAY pairs that never fall on a real date.
///
/// Throws [FormatException] if the rule is malformed or rejected.
RecurrenceRule parseRrule(
  String value, {
  required DateTime Function(DateTime untilUtc) untilUtcToWall,
  required bool startIsDate,
}) {
  var body = value.trim();
  if (body.toUpperCase().startsWith('RRULE:')) {
    body = body.substring(6);
  }
  String? until;
  var hasCount = false;
  final kept = <String>[];
  final values = <String, String>{};
  for (final part in body.split(';')) {
    if (part.trim().isEmpty) {
      continue;
    }
    final eq = part.indexOf('=');
    final key = (eq < 0 ? part : part.substring(0, eq)).trim().toUpperCase();
    if (key == 'WKST') {
      continue;
    }
    if (key == 'UNTIL') {
      until = eq < 0 ? '' : part.substring(eq + 1);
      continue;
    }
    if (key == 'COUNT') {
      hasCount = true;
    }
    if (eq >= 0) {
      values[key] = part.substring(eq + 1).trim().toUpperCase();
    }
    kept.add(part.trim());
  }
  if (until != null && hasCount) {
    throw const FormatException('RRULE has both UNTIL and COUNT');
  }
  _rejectEndless(values);
  final rule = RecurrenceRule.fromString('RRULE:${kept.join(';')}');
  if (until == null) {
    return rule;
  }
  final t = parseIcsTime(until);
  final DateTime wallUntil;
  if (startIsDate) {
    wallUntil = DateTime.utc(t.wall.year, t.wall.month, t.wall.day);
  } else if (t.isUtc) {
    wallUntil = untilUtcToWall(t.wall);
  } else if (t.isDate) {
    wallUntil = DateTime.utc(t.wall.year, t.wall.month, t.wall.day, 23, 59, 59);
  } else {
    wallUntil = t.wall;
  }
  return rule.copyWith(until: wallUntil);
}

/// Longest each month can be (February in a leap year).
const _maxDaysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/// Throws [FormatException] for the rules [parseRrule] refuses to expand.
void _rejectEndless(Map<String, String> values) {
  final freq = values['FREQ'];
  if (freq == 'HOURLY' || freq == 'MINUTELY' || freq == 'SECONDLY') {
    throw FormatException('RRULE FREQ=$freq is not supported');
  }
  for (final key in ['INTERVAL', 'COUNT']) {
    final raw = values[key];
    if (raw == null) {
      continue;
    }
    final n = int.tryParse(raw);
    if (n == null || n < 1) {
      throw FormatException('RRULE $key must be at least 1: "$raw"');
    }
  }
  final monthDays = _intList(values['BYMONTHDAY']);
  if (monthDays.isEmpty) {
    return;
  }
  final months = _intList(values['BYMONTH']);
  final maxDays = [
    for (final m in months.isEmpty ? [1] : months)
      if (m >= 1 && m <= 12) _maxDaysInMonth[m - 1],
  ];
  final matches = monthDays.any(
    (d) => d != 0 && maxDays.any((max) => d.abs() <= max),
  );
  if (!matches) {
    throw const FormatException('RRULE BYMONTH/BYMONTHDAY never match a date');
  }
}

/// The integers in a comma-separated list; unparsable items are skipped
/// (package:rrule reports those itself).
List<int> _intList(String? raw) => [
  for (final item in (raw ?? '').split(',')) ?int.tryParse(item.trim()),
];
