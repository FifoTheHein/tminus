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
  /// `Vacation` (roadmap §4).
  String label(tz.Location zone);
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
  String label(tz.Location zone) => '';

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
  String label(tz.Location zone) => 'Mute today';

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

  @override
  String label(tz.Location zone) {
    final t = tz.TZDateTime.from(untilUtc, zone);
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Paused until ${two(t.hour)}:${two(t.minute)}';
  }

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
  String label(tz.Location zone) => 'Vacation';

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
