import 'package:timezone/timezone.dart' as tz;

import 'local_date.dart';
import 'utc.dart';

/// The user's quiet mode (spec §6 "Quiet modes"). Only one is active at a
/// time; setting a new one replaces the old one.
///
/// An occurrence is "inside" a quiet mode when its **start** is inside it:
/// - [MuteToday] / [PausedUntil]: the mode has not ended yet (`now < until`)
///   and the occurrence starts before `until`. A meeting that starts exactly
///   at `until` is outside, so its heads-up still rings.
/// - [Vacation]: the occurrence starts on a local date from [Vacation.firstDay]
///   to [Vacation.lastDay], inclusive.
sealed class QuietState {
  const QuietState();

  /// Mute today: ends at 07:00 on the next local day.
  factory QuietState.muteToday({
    required DateTime nowUtc,
    required tz.Location zone,
  }) {
    final local = tz.TZDateTime.from(nowUtc, zone);
    final until = tz.TZDateTime(
      zone,
      local.year,
      local.month,
      local.day + 1,
      7,
    );
    return MuteToday(until);
  }

  /// True when an occurrence starting at [startUtc] is inside this mode.
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  });

  /// True while the mode still matters: now or later events can be covered.
  /// The Agenda banner (Plan 5) shows only while this is true.
  bool isActive({required DateTime nowUtc, required tz.Location zone});

  /// The text after "Silenced · ", e.g. `Mute today`, `Paused until 14:00`,
  /// `Paused until Wed 09:00`, `Vacation` (roadmap §4). [nowUtc] decides
  /// whether a pause's end needs its day (decision 22).
  String label(tz.Location zone, {required DateTime nowUtc});
}

final class QuietNone extends QuietState {
  const QuietNone();

  @override
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  }) => false;

  @override
  bool isActive({required DateTime nowUtc, required tz.Location zone}) => false;

  @override
  String label(tz.Location zone, {required DateTime nowUtc}) => '';

  @override
  bool operator ==(Object other) => other is QuietNone;

  @override
  int get hashCode => 0;
}

/// Shared by [MuteToday] and [PausedUntil]: quiet until an instant.
sealed class QuietUntil extends QuietState {
  QuietUntil(DateTime untilUtc) : untilUtc = plainUtc(untilUtc);

  final DateTime untilUtc;

  @override
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  }) => nowUtc.isBefore(untilUtc) && startUtc.isBefore(untilUtc);

  @override
  bool isActive({required DateTime nowUtc, required tz.Location zone}) =>
      nowUtc.isBefore(untilUtc);
}

final class MuteToday extends QuietUntil {
  MuteToday(super.untilUtc);

  @override
  String label(tz.Location zone, {required DateTime nowUtc}) => 'Mute today';

  @override
  bool operator ==(Object other) =>
      other is MuteToday && other.untilUtc == untilUtc;

  @override
  int get hashCode => Object.hash('mute', untilUtc);

  @override
  String toString() => 'MuteToday(until $untilUtc)';
}

final class PausedUntil extends QuietUntil {
  PausedUntil(super.untilUtc);

  /// `Paused until 14:00` when the pause ends today (local),
  /// `Paused until Wed 09:00` when it ends 1–6 local dates from today, and
  /// `Paused until 14 Oct 09:00` otherwise (decision 22). Days are counted
  /// by local date, so a DST change never moves the boundary.
  @override
  String label(tz.Location zone, {required DateTime nowUtc}) {
    final t = tz.TZDateTime.from(untilUtc, zone);
    final today = LocalDate.of(nowUtc, zone);
    final days = DateTime.utc(
      t.year,
      t.month,
      t.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}';
    final when = switch (days) {
      0 => time,
      >= 1 && <= 6 => '${_weekdays[t.weekday - 1]} $time',
      _ => '${t.day} ${_months[t.month - 1]} $time',
    };
    return 'Paused until $when';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
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

  @override
  bool operator ==(Object other) =>
      other is PausedUntil && other.untilUtc == untilUtc;

  @override
  int get hashCode => Object.hash('pause', untilUtc);

  @override
  String toString() => 'PausedUntil($untilUtc)';
}

final class Vacation extends QuietState {
  Vacation(this.firstDay, this.lastDay)
    : assert(firstDay <= lastDay, 'firstDay must not be after lastDay');

  final LocalDate firstDay;
  final LocalDate lastDay;

  @override
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  }) {
    final day = LocalDate.of(startUtc, zone);
    return day >= firstDay && day <= lastDay;
  }

  @override
  bool isActive({required DateTime nowUtc, required tz.Location zone}) =>
      LocalDate.of(nowUtc, zone) <= lastDay;

  @override
  String label(tz.Location zone, {required DateTime nowUtc}) => 'Vacation';

  @override
  bool operator ==(Object other) =>
      other is Vacation &&
      other.firstDay == firstDay &&
      other.lastDay == lastDay;

  @override
  int get hashCode => Object.hash('vacation', firstDay, lastDay);

  @override
  String toString() => 'Vacation($firstDay..$lastDay)';
}
