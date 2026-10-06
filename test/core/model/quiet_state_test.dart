import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';

import '../fixtures.dart';

void main() {
  setUpAll(initZones);

  group('LocalDate', () {
    test('of() uses the local date, not the UTC date', () {
      // 23:30 UTC on 5 Oct is 01:30 on 6 Oct in Johannesburg.
      expect(
        LocalDate.of(DateTime.utc(2026, 10, 5, 23, 30), johannesburg),
        LocalDate(2026, 10, 6),
      );
    });

    test('parse/toIso round trip, ordering, addDays across month end', () {
      final d = LocalDate.parse('2026-10-31');
      expect(d.toIso(), '2026-10-31');
      expect(d.addDays(1), LocalDate(2026, 11, 1));
      expect(LocalDate(2026, 10, 1) <= LocalDate(2026, 10, 1), isTrue);
      expect(LocalDate(2026, 10, 2) >= LocalDate(2026, 10, 3), isFalse);
      expect(() => LocalDate.parse('6/10/2026'), throwsFormatException);
    });
  });

  group('Mute today', () {
    test('ends at 07:00 on the next local day (Johannesburg)', () {
      final q = QuietState.muteToday(
        nowUtc: DateTime.utc(2026, 10, 6, 13),
        zone: johannesburg,
      );
      expect(q, MuteToday(DateTime.utc(2026, 10, 7, 5))); // 07:00 SAST
    });

    test('ends at 07:00 local across a DST change (London)', () {
      // Sat 24 Oct 2026 20:00 BST; clocks go back on Sun 25 Oct.
      final q = QuietState.muteToday(
        nowUtc: DateTime.utc(2026, 10, 24, 19),
        zone: london,
      );
      expect(q, MuteToday(DateTime.utc(2026, 10, 25, 7))); // 07:00 GMT
    });

    test('just after midnight still means the next day at 07:00', () {
      final q = QuietState.muteToday(
        nowUtc: DateTime.utc(2026, 10, 5, 22, 30), // 00:30 SAST on 6 Oct
        zone: johannesburg,
      );
      expect(q, MuteToday(DateTime.utc(2026, 10, 7, 5)));
    });
  });

  group('covers', () {
    final now = DateTime.utc(2026, 10, 6, 9);
    final pause = PausedUntil(DateTime.utc(2026, 10, 6, 12));

    test('pause covers events starting before its end, not at its end', () {
      bool c(DateTime s) => pause.covers(s, nowUtc: now, zone: johannesburg);
      expect(c(DateTime.utc(2026, 10, 6, 11, 59)), isTrue);
      expect(c(DateTime.utc(2026, 10, 6, 12)), isFalse);
    });

    test('an expired pause covers nothing', () {
      expect(
        pause.covers(
          DateTime.utc(2026, 10, 6, 11),
          nowUtc: DateTime.utc(2026, 10, 6, 12),
          zone: johannesburg,
        ),
        isFalse,
      );
      expect(
        pause.isActive(
          nowUtc: DateTime.utc(2026, 10, 6, 12),
          zone: johannesburg,
        ),
        isFalse,
      );
    });

    test('vacation covers whole local days, inclusive', () {
      final v = Vacation(LocalDate(2026, 10, 7), LocalDate(2026, 10, 9));
      bool c(DateTime s) => v.covers(s, nowUtc: now, zone: johannesburg);
      expect(c(DateTime.utc(2026, 10, 6, 21, 59)), isFalse); // 23:59 on 6th
      expect(c(DateTime.utc(2026, 10, 6, 22)), isTrue); // 00:00 on 7th
      expect(c(DateTime.utc(2026, 10, 9, 21, 59)), isTrue); // 23:59 on 9th
      expect(c(DateTime.utc(2026, 10, 9, 22)), isFalse); // 00:00 on 10th
      expect(v.isActive(nowUtc: now, zone: johannesburg), isTrue);
      expect(
        v.isActive(nowUtc: DateTime.utc(2026, 10, 10, 8), zone: johannesburg),
        isFalse,
      );
    });

    test('none covers nothing', () {
      expect(const QuietNone().covers(now, nowUtc: now, zone: london), isFalse);
    });
  });

  group('label', () {
    test('Paused until shows local HH:mm', () {
      expect(
        PausedUntil(DateTime.utc(2026, 10, 6, 12)).label(johannesburg),
        'Paused until 14:00',
      );
      expect(
        PausedUntil(DateTime.utc(2026, 7, 1, 12, 5)).label(london),
        'Paused until 13:05',
      );
    });

    test('Mute today and Vacation', () {
      expect(
        MuteToday(DateTime.utc(2026, 10, 7, 5)).label(london),
        'Mute today',
      );
      expect(
        Vacation(LocalDate(2026, 10, 7), LocalDate(2026, 10, 7)).label(london),
        'Vacation',
      );
    });
  });
}
