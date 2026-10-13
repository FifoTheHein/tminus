import 'package:timezone/timezone.dart' as tz;

import '../model/local_date.dart';

/// 24-hour, English time strings for the screens (Plan 5 decision 19).
/// Instants are UTC; [tz.Location] is the device zone (`tz.local`).
abstract final class TimeText {
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `09:50`.
  static String hm(DateTime utc, tz.Location zone) {
    final t = tz.TZDateTime.from(utc, zone);
    return '${_two(t.hour)}:${_two(t.minute)}';
  }

  /// `10:00–11:00` (en dash).
  static String range(DateTime startUtc, DateTime endUtc, tz.Location zone) =>
      '${hm(startUtc, zone)}–${hm(endUtc, zone)}';

  /// `Tue 6 Oct`.
  static String day(LocalDate d) {
    final weekday = DateTime.utc(d.year, d.month, d.day).weekday;
    return '${weekdays[weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  /// `TUE 6 OCT`, the Agenda's right-hand day label.
  static String dayUpper(LocalDate d) => day(d).toUpperCase();

  /// `Today`, `Tomorrow`, else [day].
  static String dayTitle(LocalDate d, LocalDate today) {
    if (d == today) return 'Today';
    if (d == today.addDays(1)) return 'Tomorrow';
    return day(d);
  }

  /// `just now`, `4 min ago`, `1 h ago`, `2 days ago`.
  static String ago(DateTime pastUtc, DateTime nowUtc) {
    final d = nowUtc.difference(pastUtc);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    final days = d.inDays;
    return days == 1 ? '1 day ago' : '$days days ago';
  }

  /// Agenda header: `23 min`, `1 h 05`, or `Wed 09:50` from 24 h on. Rounds
  /// up to whole minutes, so an alert 30 s away reads `1 min`.
  static String countdown(
    DateTime targetUtc,
    DateTime nowUtc,
    tz.Location zone,
  ) {
    final seconds = targetUtc.difference(nowUtc).inSeconds;
    final minutes = seconds <= 0 ? 0 : (seconds + 59) ~/ 60;
    if (minutes < 60) return '$minutes min';
    if (minutes < 24 * 60) return '${minutes ~/ 60} h ${_two(minutes % 60)}';
    final t = tz.TZDateTime.from(targetUtc, zone);
    return '${weekdays[t.weekday - 1]} ${hm(targetUtc, zone)}';
  }
}
