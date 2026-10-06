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

    test('parse rejects impossible dates (decision 20)', () {
      for (final iso in [
        '2026-13-45',
        '2026-02-30',
        '2026-00-10',
        '2026-04-31',
      ]) {
        expect(() => LocalDate.parse(iso), throwsFormatException, reason: iso);
      }
      expect(LocalDate.parse('2028-02-29'), LocalDate(2028, 2, 29));
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
        PausedUntil(DateTime.utc(2026, 10, 6, 12))
            .label(johannesburg, nowUtc: DateTime.utc(2026, 10, 6, 9)),
        'Paused until 14:00',
      );
      expect(
        PausedUntil(DateTime.utc(2026, 7, 1, 12, 5))
            .label(london, nowUtc: DateTime.utc(2026, 7, 1, 9)),
        'Paused until 13:05',
      );
    });

    test('Mute today and Vacation', () {
      final now = DateTime.utc(2026, 10, 6, 9);
      expect(
        MuteToday(DateTime.utc(2026, 10, 7, 5)).label(london, nowUtc: now),
        'Mute today',
      );
      expect(
        Vacation(
          LocalDate(2026, 10, 7),
          LocalDate(2026, 10, 7),
        ).label(london, nowUtc: now),
        'Vacation',
      );
    });

    group('Paused until names the day when it is not today (decision 22)', () {
      // Tue 6 Oct 2026 08:00 SAST.
      final now = DateTime.utc(2026, 10, 6, 6);
      String jhb(DateTime untilUtc) =>
          PausedUntil(untilUtc).label(johannesburg, nowUtc: now);

      test('today: time only, up to local midnight', () {
        expect(jhb(DateTime.utc(2026, 10, 6, 12)), 'Paused until 14:00');
        expect(jhb(DateTime.utc(2026, 10, 6, 21, 59)), 'Paused until 23:59');
      });

      test('tomorrow: weekday and time', () {
        expect(jhb(DateTime.utc(2026, 10, 6, 22)), 'Paused until Wed 00:00');
        expect(jhb(DateTime.utc(2026, 10, 7, 7)), 'Paused until Wed 09:00');
      });

      test('six local days ahead: weekday and time', () {
        expect(jhb(DateTime.utc(2026, 10, 12, 7)), 'Paused until Mon 09:00');
        expect(
          jhb(DateTime.utc(2026, 10, 12, 21, 59)),
          'Paused until Mon 23:59',
        );
      });

      test('seven local days ahead: day, month and time', () {
        expect(
          jhb(DateTime.utc(2026, 10, 12, 22)),
          'Paused until 13 Oct 00:00',
        );
        expect(jhb(DateTime.utc(2026, 10, 13, 7)), 'Paused until 13 Oct 09:00');
        expect(
          jhb(DateTime.utc(2026, 11, 2, 7, 5)),
          'Paused until 2 Nov 09:05',
        );
      });

      test('every weekday name', () {
        final names = [
          for (var d = 1; d <= 6; d++)
            jhb(DateTime.utc(2026, 10, 6 + d, 7)).split(' ')[2],
        ];
        expect(names, ['Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon']);
      });

      test('counts local dates, not 24-hour periods, across DST (London)', () {
        // Sat 24 Oct 2026 00:30 BST; clocks go back on Sun 25 Oct.
        final now = DateTime.utc(2026, 10, 23, 23, 30);
        String ldn(DateTime untilUtc) =>
            PausedUntil(untilUtc).label(london, nowUtc: now);
        // Fri 30 Oct 23:59 GMT: six local dates on, though over 7 × 24 h.
        expect(
          ldn(DateTime.utc(2026, 10, 30, 23, 59)),
          'Paused until Fri 23:59',
        );
        // Sat 31 Oct 00:00 GMT: seven local dates on.
        expect(ldn(DateTime.utc(2026, 10, 31)), 'Paused until 31 Oct 00:00');
        // Sun 25 Oct 09:00 GMT, the day the clocks go back.
        expect(ldn(DateTime.utc(2026, 10, 25, 9)), 'Paused until Sun 09:00');
      });
    });
  });
}
