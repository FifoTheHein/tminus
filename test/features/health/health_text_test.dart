import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/features/common/status_tone.dart';
import 'package:tminus/features/health/health_text.dart';
import 'package:tminus/features/health/maker_tips.dart';

import '../../core/fixtures.dart';

void main() {
  initZones();
  final zone = johannesburg;

  AlertHistoryEntry entry(
    AlertEventType type, {
    String key = 'ics-1|sprint',
    DateTime? snoozeUntil,
    String? title,
  }) => AlertHistoryEntry(
    type: type,
    alertId: 'a1',
    occurrenceKey: key,
    startUtc: DateTime.utc(2026, 10, 6, 8),
    atUtc: DateTime.utc(2026, 10, 6, 7, 50),
    snoozeUntilUtc: snoozeUntil,
    title: title,
  );

  group('sync outcomes', () {
    test('every SyncOutcome has its text', () {
      const expected = {
        SyncOutcome.success: 'Synced',
        SyncOutcome.notModified: 'Synced (no changes)',
        SyncOutcome.emptyKept: 'Came back empty — kept the previous events',
        SyncOutcome.networkError: 'No connection',
        SyncOutcome.serverError: 'The calendar server had a problem',
        SyncOutcome.httpError: 'The link stopped working',
        SyncOutcome.parseError: "The feed couldn't be read",
        SyncOutcome.otherError: 'Something went wrong',
        SyncOutcome.calendarAccessDenied: 'Calendar access is off',
        SyncOutcome.calendarMissing: 'The calendar was removed',
        SyncOutcome.linkMissing: 'The link is missing',
        SyncOutcome.skipped: 'Skipped — another sync was running',
      };

      // A new outcome fails here until this table, like the screen, names it.
      expect(expected.keys.toSet(), SyncOutcome.values.toSet());
      for (final o in SyncOutcome.values) {
        expect(outcomeText(o), expected[o], reason: o.name);
      }
      // No two outcomes read the same, so a row says which one it is.
      expect(
        SyncOutcome.values.map(outcomeText).toSet(),
        hasLength(SyncOutcome.values.length),
      );
    });

    test('skipped is neutral and every other outcome follows its severity', () {
      const expected = {
        SyncOutcome.success: StatusTone.ok,
        SyncOutcome.notModified: StatusTone.ok,
        SyncOutcome.emptyKept: StatusTone.ok,
        SyncOutcome.networkError: StatusTone.warn,
        SyncOutcome.serverError: StatusTone.warn,
        SyncOutcome.httpError: StatusTone.error,
        SyncOutcome.parseError: StatusTone.error,
        SyncOutcome.otherError: StatusTone.error,
        SyncOutcome.calendarAccessDenied: StatusTone.error,
        SyncOutcome.calendarMissing: StatusTone.error,
        SyncOutcome.linkMissing: StatusTone.error,
        SyncOutcome.skipped: StatusTone.neutral,
      };

      expect(expected.keys.toSet(), SyncOutcome.values.toSet());
      for (final o in SyncOutcome.values) {
        expect(outcomeTone(o), expected[o], reason: o.name);
      }
    });
  });

  group('history', () {
    test('history texts say what happened', () {
      final expected = {
        AlertEventType.fired: 'Rang',
        AlertEventType.snoozed: 'Snoozed',
        AlertEventType.dismissed: 'Dismissed',
        AlertEventType.dismissedAll: 'Dismissed all',
        AlertEventType.joined: 'Joined',
        AlertEventType.missed: 'Missed — nobody answered',
        AlertEventType.missedSystem: "Missed — the phone didn't ring it",
      };

      expect(expected.keys.toSet(), AlertEventType.values.toSet());
      for (final type in AlertEventType.values) {
        expect(
          historyText(entry(type), zone),
          expected[type],
          reason: type.name,
        );
      }
    });

    test('a snooze says until when, in the phone\'s zone', () {
      // 08:05 UTC is 10:05 in Johannesburg.
      final snoozed = entry(
        AlertEventType.snoozed,
        snoozeUntil: DateTime.utc(2026, 10, 6, 8, 5),
      );

      expect(historyText(snoozed, zone), 'Snoozed until 10:05');
    });

    test('only missed and missedSystem are misses', () {
      for (final type in AlertEventType.values) {
        expect(
          isMissEntry(entry(type)),
          type == AlertEventType.missed || type == AlertEventType.missedSystem,
          reason: type.name,
        );
      }
    });

    test('only an occurrence key that starts test| is a test entry', () {
      expect(isTestEntry(entry(AlertEventType.fired, key: 'test|1')), isTrue);
      expect(
        isTestEntry(entry(AlertEventType.fired, key: 'ics-1|test|1')),
        isFalse,
      );
      expect(isTestEntry(entry(AlertEventType.fired, key: 'Test|1')), isFalse);
      expect(isTestEntry(entry(AlertEventType.fired)), isFalse);
    });

    test('a title is the event\'s, else Test alarm or Calendar event', () {
      expect(
        historyTitle(entry(AlertEventType.fired, title: ' Sprint planning ')),
        'Sprint planning',
      );
      // A test alarm is not in the cache, so it has no title.
      expect(
        historyTitle(entry(AlertEventType.fired, key: 'test|1')),
        'Test alarm',
      );
      // Not a test: it must not be called one.
      expect(historyTitle(entry(AlertEventType.fired)), 'Calendar event');
      expect(
        historyTitle(entry(AlertEventType.fired, title: '  ')),
        'Calendar event',
      );
    });
  });

  group('times', () {
    test('weekdayTime reads the weekday and the time in the zone', () {
      expect(weekdayTime(DateTime.utc(2026, 10, 6, 7, 50), zone), 'Tue 09:50');
      // 22:30 UTC on Tuesday is already Wednesday in Johannesburg.
      expect(weekdayTime(DateTime.utc(2026, 10, 6, 22, 30), zone), 'Wed 00:30');
    });

    test('upcomingTime leaves out the weekday for today only', () {
      // 09:27 on Tuesday 6 October in Johannesburg.
      final now = DateTime.utc(2026, 10, 6, 7, 27);

      expect(
        upcomingTime(DateTime.utc(2026, 10, 6, 7, 50), now, zone),
        '09:50',
      );
      expect(
        upcomingTime(DateTime.utc(2026, 10, 7, 6, 45), now, zone),
        'Wed 08:45',
      );
    });

    test('today is the zone\'s day, not the UTC day', () {
      // 00:30 on Tuesday 6 October in Johannesburg is still 5 October in UTC.
      final earlyToday = DateTime.utc(2026, 10, 5, 22, 30);
      final now = DateTime.utc(2026, 10, 6, 7, 27);
      expect(upcomingTime(earlyToday, now, zone), '00:30');

      // Two minutes before midnight there; the alarm two minutes later is
      // tomorrow there, though it is the same day in UTC.
      final lateNow = DateTime.utc(2026, 10, 6, 21, 58);
      final justAfter = DateTime.utc(2026, 10, 6, 22, 1);
      expect(upcomingTime(justAfter, lateNow, zone), 'Wed 00:01');
    });
  });

  group('phone-maker tips', () {
    List<String> makers(String manufacturer) =>
        makerTips(manufacturer).map((t) => t.maker).toList();

    test(
      'the device\'s maker comes first and the rest follow in table order',
      () {
        expect(makers('samsung'), [
          'Samsung',
          'Xiaomi',
          'OnePlus / OPPO / realme',
          'Huawei / Honor',
          'Other phones',
        ]);
        expect(makers('xiaomi'), [
          'Xiaomi',
          'Samsung',
          'OnePlus / OPPO / realme',
          'Huawei / Honor',
          'Other phones',
        ]);
        expect(makers('huawei'), [
          'Huawei / Honor',
          'Samsung',
          'Xiaomi',
          'OnePlus / OPPO / realme',
          'Other phones',
        ]);
      },
    );

    test('every spelling of a maker finds its tip', () {
      const spellings = {
        'Samsung': ['samsung', 'Samsung', 'SAMSUNG', '  samsung '],
        'Xiaomi': ['xiaomi', 'Xiaomi', 'redmi', 'Redmi', 'poco', 'POCO'],
        'OnePlus / OPPO / realme': [
          'oneplus',
          'OnePlus',
          'oppo',
          'OPPO',
          'realme',
          'Realme',
        ],
        'Huawei / Honor': ['huawei', 'HUAWEI', 'honor', 'HONOR'],
      };

      spellings.forEach((maker, names) {
        for (final name in names) {
          expect(makers(name).first, maker, reason: name);
        }
      });
    });

    test('a maker that is not listed gets the general tip first', () {
      for (final name in ['Google', 'motorola', '', 'honorable']) {
        expect(makers(name), [
          'Other phones',
          'Samsung',
          'Xiaomi',
          'OnePlus / OPPO / realme',
          'Huawei / Honor',
        ], reason: name);
      }
    });

    test('each tip reads as the brief gives it', () {
      final tips = {for (final t in makerTips('samsung')) t.maker: t.tip};

      expect(tips, {
        'Samsung':
            'Settings → Battery → Background usage limits → Never sleeping '
            'apps → add T-Minus.',
        'Xiaomi':
            'Settings → Apps → T-Minus: turn Autostart on, and set Battery '
            'saver to No restrictions.',
        'OnePlus / OPPO / realme':
            "Settings → Battery → T-Minus: Don't optimise, and allow "
            'Auto-launch.',
        'Huawei / Honor':
            'Settings → Battery → App launch → T-Minus → Manage manually, '
            'with every switch on.',
        'Other phones': 'Settings → Apps → T-Minus → Battery → Unrestricted.',
      });
    });

    test('the title names the maker, or says Phone-maker tips', () {
      expect(makerTipsTitle('samsung'), 'Samsung tips');
      expect(makerTipsTitle('Redmi'), 'Xiaomi tips');
      expect(makerTipsTitle('OPPO'), 'OnePlus / OPPO / realme tips');
      expect(makerTipsTitle('honor'), 'Huawei / Honor tips');
      expect(makerTipsTitle('Google'), 'Phone-maker tips');
      expect(makerTipsTitle(''), 'Phone-maker tips');
      // The phone has not been read yet, or could not be.
      expect(makerTipsTitle(null), 'Phone-maker tips');
    });
  });
}
