import 'package:timezone/timezone.dart' as tz;

/// A calendar date with no time and no zone, e.g. a vacation day.
class LocalDate implements Comparable<LocalDate> {
  LocalDate(int year, int month, int day)
    : this._(DateTime.utc(year, month, day));

  LocalDate._(DateTime utcMidnight)
    : year = utcMidnight.year,
      month = utcMidnight.month,
      day = utcMidnight.day;

  /// The date [instantUtc] falls on in [zone].
  factory LocalDate.of(DateTime instantUtc, tz.Location zone) {
    final local = tz.TZDateTime.from(instantUtc, zone);
    return LocalDate(local.year, local.month, local.day);
  }

  /// Parses `yyyy-MM-dd`. Throws [FormatException] on anything else.
  factory LocalDate.parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) throw FormatException('Not a yyyy-MM-dd date', iso);
    return LocalDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  final int year;
  final int month;
  final int day;

  LocalDate addDays(int days) =>
      LocalDate._(DateTime.utc(year, month, day + days));

  /// Local midnight at the start of this date in [zone].
  tz.TZDateTime startIn(tz.Location zone) =>
      tz.TZDateTime(zone, year, month, day);

  @override
  int compareTo(LocalDate other) =>
      (year * 10000 + month * 100 + day) -
      (other.year * 10000 + other.month * 100 + other.day);

  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
