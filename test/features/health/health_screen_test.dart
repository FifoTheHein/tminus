import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/features/common/notice_banner.dart';
import 'package:tminus/features/common/status_tone.dart';
import 'package:tminus/features/health/health_screen.dart';
import 'package:tminus/features/settings/settings_screen.dart';
import 'package:tminus/features/sources/source_detail_screen.dart';

import '../../core/fixtures.dart' show blue;
import '../harness.dart';

const _work = SourceConfig(
  id: 'ics-1',
  name: 'Work Outlook',
  color: blue,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.ics-1',
);

const _samsungTip =
    'Settings → Battery → Background usage limits → Never sleeping apps → '
    'add T-Minus.';
const _xiaomiTip =
    'Settings → Apps → T-Minus: turn Autostart on, and set Battery saver to '
    'No restrictions.';
const _generalTip = 'Settings → Apps → T-Minus → Battery → Unrestricted.';
const _forceStopNote =
    'If you force-stop T-Minus, Android cancels its alarms until you open it '
    'again.';
const _missedSystemText = "Missed: the phone didn't ring it";

/// A history row. Tuesday 6 October 2026, 09:50 in Johannesburg, by default.
AlertHistoryEntry _historyEntry(
  AlertEventType type, {
  String alertId = 'a1',
  String key = 'ics-1|sprint',
  String? title = 'Sprint planning',
  DateTime? at,
}) => AlertHistoryEntry(
  type: type,
  alertId: alertId,
  occurrenceKey: key,
  startUtc: DateTime.utc(2026, 10, 6, 8),
  atUtc: at ?? DateTime.utc(2026, 10, 6, 7, 50),
  title: title,
);

/// A phone-sized screen tall enough for the whole page, so that nothing is
/// built lazily out of sight and every button can be tapped.
void _tallScreen(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// How many times the screen has asked the engine for its health.
int _healthCalls(Harness h) =>
    h.engineCalls.where((c) => c.method == 'getHealth').length;

/// Lets the database's watch streams deliver, and the frames that follow draw,
/// until [finder] matches (or 50 turns have passed: the caller's `expect` then
/// fails). A write made from the test comes from outside the widget test's
/// fake-async zone, so it needs real turns of the event loop and then a pump.
Future<void> _untilFound(WidgetTester t, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await t.runAsync(() => pumpEventQueue(times: 5));
    await t.pump();
  }
  await t.pumpAndSettle();
}

/// Answers the engine as the harness does, except that [method] fails like a
/// platform error whose message must never reach the screen or the log.
void _failEngine(Harness h, String method) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(AlarmEngine.methodChannelName),
        (call) async {
          h.engineCalls.add(call);
          if (call.method == method) {
            throw PlatformException(
              code: 'no_settings',
              message: 'https://secret.example/feed.ics',
            );
          }
          return call.method == 'getHealth' ? h.health : null;
        },
      );
}

/// Runs [body] with everything the app logs collected into the list it is
/// given. The log hook goes back before the test body ends, not in a
/// tear-down: the framework checks that it is back before tear-downs run.
Future<void> _logging(Future<void> Function(List<String> logged) body) async {
  final logged = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => logged.add(message ?? '');
  try {
    await body(logged);
  } finally {
    debugPrint = original;
  }
}

Map<String, Object?> _upcoming(
  String id,
  DateTime at,
  String strength,
  String title,
) => {
  'id': id,
  'fireAtUtcMs': at.millisecondsSinceEpoch,
  'strength': strength,
  'title': title,
};

void main() {
  testWidgets('all good shows the green headline', (t) async {
    _tallScreen(t);
    final h = await pumpApp(t, location: '/health');

    final card = find.byKey(const Key('healthOverall'));
    expect(
      find.descendant(
        of: card,
        matching: find.text('All good. Alarms will ring'),
      ),
      findsOneWidget,
    );
    expect(t.widget<NoticeBanner>(card).tone, StatusTone.ok);
    // With nothing to summarise the card says how fresh the check is.
    expect(
      find.descendant(of: card, matching: find.text('Last checked just now')),
      findsOneWidget,
    );
    // Every engine row is listed, and nothing offers a Fix.
    for (final title in const [
      'Notifications',
      'Full-screen alarms',
      'Exact alarms',
      'Battery optimisation',
      'Alarm channel',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.widgetWithText(FilledButton, 'Fix'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a missing permission shows Fix that opens its settings', (
    t,
  ) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        h.health = {...healthyEngine(), 'canUseFullScreenIntent': false};
      },
    );

    // Only the row that is wrong offers it.
    expect(find.widgetWithText(FilledButton, 'Fix'), findsOneWidget);
    await t.tap(find.byKey(const Key('fix-fullScreen')));
    await t.pumpAndSettle();

    final opened = h.engineCalls.where(
      (c) => c.method == 'openPermissionSettings',
    );
    expect(opened.map((c) => c.arguments), [
      {'kind': 'fullScreenIntent'},
    ]);
    await h.dispose(t);
  });

  testWidgets("a failing source's Fix opens the source", (t) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        final sources = getIt<SourceRepository>();
        await sources.save(
          const SourceConfig(
            id: 'ics-9',
            name: 'Team rota',
            color: blue,
            kind: SourceKind.ics,
            secureStorageKey: 'ics-url.ics-9',
          ),
        );
        await sources.updateSyncState(
          'ics-9',
          SourceSyncState(
            lastAttemptUtc: DateTime.utc(2026, 10, 6, 7, 20),
            lastError: 'The link stopped working',
          ),
        );
      },
    );

    // The row says what is wrong, and the card counts it as a problem.
    expect(find.text('Sync · Team rota'), findsOneWidget);
    expect(find.text('The link stopped working'), findsOneWidget);
    expect(
      t.widget<NoticeBanner>(find.byKey(const Key('healthOverall'))).tone,
      StatusTone.error,
    );

    await t.tap(find.byKey(const Key('fix-source:ics-9')));
    await t.pumpAndSettle();

    final detail = t.widget<SourceDetailScreen>(
      find.byType(SourceDetailScreen),
    );
    expect(detail.sourceId, 'ics-9');
    await h.dispose(t);
  });

  testWidgets(
    'missedSystem rows written straight into the database appear and are '
    'highlighted',
    (t) async {
      _tallScreen(t);
      final h = await pumpApp(t, location: '/health');
      expect(find.text('No alerts yet'), findsOneWidget);
      expect(find.byKey(const Key('history-miss')), findsNothing);

      // What a sync does: a row goes straight into the table, and no engine
      // event announces it.
      await t.runAsync(
        () => getIt<AlertHistoryRepository>().record(
          _historyEntry(AlertEventType.missedSystem),
        ),
      );
      await _untilFound(t, find.byKey(const Key('history-miss')));

      expect(find.text('No alerts yet'), findsNothing);
      expect(find.text('Sprint planning'), findsOneWidget);
      expect(find.text('Tue 09:50'), findsOneWidget);
      expect(find.text(_missedSystemText), findsOneWidget);
      // Highlighted: an error icon and the status colour for what happened.
      final colors = t.element(find.byType(HealthScreen)).tminusColors;
      expect(
        t.widget<Icon>(find.byKey(const Key('history-miss'))).color,
        colors.statusError,
      );
      expect(
        t.widget<Text>(find.text(_missedSystemText)).style?.color,
        colors.statusError,
      );
      await h.dispose(t);
    },
  );

  testWidgets('test alarms are labelled Test', (t) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        final history = getIt<AlertHistoryRepository>();
        // Newest first: the meeting rang at 09:45, the test at 09:20.
        await history.record(
          _historyEntry(
            AlertEventType.fired,
            at: DateTime.utc(2026, 10, 6, 7, 45),
          ),
        );
        await history.record(
          _historyEntry(
            AlertEventType.fired,
            alertId: 'test-1',
            key: 'test|1',
            title: null,
            at: DateTime.utc(2026, 10, 6, 7, 20),
          ),
        );
      },
    );

    final meetingRow = find.byKey(const Key('history-row-0'));
    final testRow = find.byKey(const Key('history-row-1'));
    expect(
      find.descendant(of: meetingRow, matching: find.text('Sprint planning')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: meetingRow, matching: find.text('Test')),
      findsNothing,
    );
    expect(
      find.descendant(of: testRow, matching: find.text('Test alarm')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: testRow, matching: find.text('Test')),
      findsOneWidget,
    );
    // The one chip on the page is the test's.
    expect(find.byKey(const Key('history-test')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a skipped run is listed in grey with its text', (t) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        await getIt<SourceRepository>().save(_work);
        final log = getIt<SyncLogRepository>();
        await log.add(
          SyncLogEntry(
            sourceId: 'ics-1',
            atUtc: DateTime.utc(2026, 10, 6, 7, 20),
            outcome: SyncOutcome.success,
          ),
        );
        await log.add(
          SyncLogEntry(
            atUtc: DateTime.utc(2026, 10, 6, 7, 25),
            outcome: SyncOutcome.skipped,
            message: 'manual: skipped, another sync was still running',
          ),
        );
      },
    );

    final skipped = find.byKey(const Key('syncLog-row-0'));
    final synced = find.byKey(const Key('syncLog-row-1'));
    const text = 'Skipped: another sync was running';
    expect(
      find.descendant(of: skipped, matching: find.text(text)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: skipped,
        matching: find.text('manual: skipped, another sync was still running'),
      ),
      findsOneWidget,
    );
    // Neutral grey for the dot and the words, where a good sync is green.
    final colors = t.element(find.byType(HealthScreen)).tminusColors;
    expect(
      t
          .widget<StatusDot>(
            find.descendant(of: skipped, matching: find.byType(StatusDot)),
          )
          .tone,
      StatusTone.neutral,
    );
    expect(
      t
          .widget<Text>(find.descendant(of: skipped, matching: find.text(text)))
          .style
          ?.color,
      colors.tertiaryText,
    );
    expect(
      t
          .widget<StatusDot>(
            find.descendant(of: synced, matching: find.byType(StatusDot)),
          )
          .tone,
      StatusTone.ok,
    );
    await h.dispose(t);
  });

  testWidgets("the device maker's tips come first", (t) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        h.ui['deviceInfo'] = (_) => {
          'versionName': '1.0.0',
          'versionCode': 1,
          'manufacturer': 'samsung',
          'sdkInt': 34,
        };
      },
    );

    expect(find.text('Samsung tips'), findsOneWidget);
    await t.tap(find.text('Samsung tips'));
    await t.pumpAndSettle();

    final samsung = find.text(_samsungTip);
    final xiaomi = find.text(_xiaomiTip);
    expect(samsung, findsOneWidget);
    expect(xiaomi, findsOneWidget);
    expect(t.getTopLeft(samsung).dy, lessThan(t.getTopLeft(xiaomi).dy));
    await h.dispose(t);
  });

  testWidgets('Test alarm asks the engine for an alarm in 5 seconds', (
    t,
  ) async {
    _tallScreen(t);
    final h = await pumpApp(t, location: '/health');

    await t.tap(find.byKey(const Key('testAlarm')));
    await t.pumpAndSettle();

    final asked = h.engineCalls.where((c) => c.method == 'testAlarm');
    expect(asked.map((c) => c.arguments), [
      {'strength': 'alarm', 'delaySec': 5},
    ]);
    expect(find.text('A test alarm rings in 5 seconds.'), findsOneWidget);
    await h.dispose(t);
  });

  // Beyond the plan's list. Each pins one thing the screen promises.

  testWidgets('a Fix refreshes the checklist afterwards', (t) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        h.health = {...healthyEngine(), 'canScheduleExactAlarms': false};
      },
    );
    expect(find.byKey(const Key('fix-exactAlarms')), findsOneWidget);

    // The user turns it on in the settings screen that Fix opens; nothing
    // else tells the app until it is next resumed.
    h.health = healthyEngine();
    await t.tap(find.byKey(const Key('fix-exactAlarms')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('fix-exactAlarms')), findsNothing);
    expect(
      t.widget<NoticeBanner>(find.byKey(const Key('healthOverall'))).tone,
      StatusTone.ok,
    );
    await h.dispose(t);
  });

  testWidgets('an engine that cannot be read has no Fix and no schedule', (
    t,
  ) async {
    _tallScreen(t);
    // An answer with none of the fields: the report falls back to its warning.
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        h.health = {};
      },
    );

    expect(find.text('Alarm engine'), findsOneWidget);
    expect(find.text('Could not be checked'), findsOneWidget);
    expect(
      t.widget<NoticeBanner>(find.byKey(const Key('healthOverall'))).tone,
      StatusTone.warn,
    );
    // There is nothing to open, so no Fix: not for a warning as such.
    expect(find.widgetWithText(FilledButton, 'Fix'), findsNothing);
    // And "nothing scheduled" would be a claim the app cannot make.
    expect(find.text('Could not be read'), findsOneWidget);
    expect(find.text('Nothing scheduled'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('with nothing scheduled the page says so and still warns about '
      'a force-stop', (t) async {
    _tallScreen(t);
    final h = await pumpApp(t, location: '/health');

    expect(find.text('Nothing scheduled'), findsOneWidget);
    expect(find.text(_forceStopNote), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('upcoming alarms show their time, strength and title, at most '
      'five', (t) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      seed: (h) async {
        h.health = {
          ...healthyEngine(),
          'upcoming': [
            _upcoming(
              'a1',
              DateTime.utc(2026, 10, 6, 7, 50),
              'alarm',
              'Sprint planning',
            ),
            _upcoming(
              'a2',
              DateTime.utc(2026, 10, 6, 8, 45),
              'headsUp',
              'Client demo',
            ),
            _upcoming(
              'a3',
              DateTime.utc(2026, 10, 7, 6, 45),
              'headsUp',
              'Daily standup',
            ),
            _upcoming(
              'a4',
              DateTime.utc(2026, 10, 7, 7),
              'alarm',
              'Daily standup',
            ),
            _upcoming(
              'a5',
              DateTime.utc(2026, 10, 7, 8),
              'headsUp',
              'One-to-one',
            ),
            _upcoming('a6', DateTime.utc(2026, 10, 7, 9), 'alarm', 'Retro'),
          ],
        };
      },
    );
    // The screen alone, on the harness's clock (Tuesday 09:27 there), so that
    // "today" does not depend on when the test runs.
    await t.pumpWidget(
      MaterialApp(
        theme: TMinusTheme.light(),
        home: HealthScreen(clock: () => h.now),
      ),
    );
    await t.pumpAndSettle();

    Finder inRow(int i, Finder what) => find.descendant(
      of: find.byKey(ValueKey('upcoming-$i')),
      matching: what,
    );
    expect(find.text('Upcoming alarms'), findsOneWidget);
    expect(find.text('as scheduled by the engine'), findsOneWidget);
    // Today has no weekday; another day has one.
    expect(inRow(0, find.text('09:50')), findsOneWidget);
    expect(inRow(1, find.text('10:45')), findsOneWidget);
    expect(inRow(2, find.text('Wed 08:45')), findsOneWidget);
    expect(inRow(4, find.text('Wed 10:00')), findsOneWidget);
    expect(inRow(0, find.text('Sprint planning')), findsOneWidget);
    expect(inRow(1, find.text('Client demo')), findsOneWidget);
    // A solid clock for an alarm, an outlined bell for a heads-up.
    expect(inRow(0, find.byIcon(Icons.alarm_rounded)), findsOneWidget);
    expect(inRow(0, find.byIcon(Icons.notifications_outlined)), findsNothing);
    expect(inRow(1, find.byIcon(Icons.notifications_outlined)), findsOneWidget);
    expect(inRow(1, find.byIcon(Icons.alarm_rounded)), findsNothing);
    // The sixth is not shown.
    expect(find.byKey(const ValueKey('upcoming-5')), findsNothing);
    expect(find.text('Retro'), findsNothing);
    expect(find.text('Nothing scheduled'), findsNothing);
    expect(find.text(_forceStopNote), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the all-good card says how long ago the check was', (t) async {
    final h = await pumpApp(t);
    Widget screen() => MaterialApp(
      theme: TMinusTheme.light(),
      home: HealthScreen(clock: () => h.now),
    );
    await t.pumpWidget(screen());
    await t.pumpAndSettle();
    expect(find.text('Last checked just now'), findsOneWidget);

    // Nothing is checked again, but the screen is drawn again 5 minutes later.
    h.now = h.now.add(const Duration(minutes: 5));
    await t.pumpWidget(screen());

    expect(find.text('Last checked 5 min ago'), findsOneWidget);
    expect(find.text('Last checked just now'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('Test heads-up asks the engine for a heads-up in 5 seconds', (
    t,
  ) async {
    _tallScreen(t);
    final h = await pumpApp(t, location: '/health');

    await t.tap(find.byKey(const Key('testHeadsUp')));
    await t.pumpAndSettle();

    final asked = h.engineCalls.where((c) => c.method == 'testAlarm');
    expect(asked.map((c) => c.arguments), [
      {'strength': 'headsUp', 'delaySec': 5},
    ]);
    expect(find.text('A test heads-up rings in 5 seconds.'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the test buttons come before the History header', (t) async {
    _tallScreen(t);
    final h = await pumpApp(t, location: '/health');

    // The whole page is laid out on the tall screen, so positions compare.
    expect(find.text('History'), findsOneWidget);
    final history = t.getTopLeft(find.text('History')).dy;
    expect(
      t.getTopLeft(find.byKey(const Key('testHeadsUp'))).dy,
      lessThan(history),
    );
    expect(
      t.getTopLeft(find.byKey(const Key('testAlarm'))).dy,
      lessThan(history),
    );
    await h.dispose(t);
  });

  testWidgets('a missed and a missedSystem row for one alert are both shown', (
    t,
  ) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        final history = getIt<AlertHistoryRepository>();
        // The ring timed out unanswered, and the sync found the alert late.
        await history.record(
          _historyEntry(
            AlertEventType.missed,
            at: DateTime.utc(2026, 10, 6, 7, 55),
          ),
        );
        await history.record(_historyEntry(AlertEventType.missedSystem));
      },
    );

    expect(find.byKey(const Key('history-miss')), findsNWidgets(2));
    expect(find.text('Missed: nobody answered'), findsOneWidget);
    expect(find.text(_missedSystemText), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the sync log names each source, or says who it is not', (
    t,
  ) async {
    _tallScreen(t);
    final h = await pumpApp(
      t,
      location: '/health',
      seed: (h) async {
        await getIt<SourceRepository>().save(_work);
        final log = getIt<SyncLogRepository>();
        await log.add(
          SyncLogEntry(
            sourceId: 'gone',
            atUtc: DateTime.utc(2026, 10, 6, 7, 20),
            outcome: SyncOutcome.httpError,
          ),
        );
        await log.add(
          SyncLogEntry(
            sourceId: 'ics-1',
            atUtc: DateTime.utc(2026, 10, 6, 7, 25),
            outcome: SyncOutcome.success,
            occurrenceCount: 12,
          ),
        );
        await log.add(
          SyncLogEntry(
            atUtc: DateTime.utc(2026, 10, 6, 7, 25, 30),
            outcome: SyncOutcome.success,
            message: 'manual: 12 alerts planned; armed 2, cancelled 0, kept 10',
          ),
        );
      },
    );

    Finder inRow(int i, Finder what) => find.descendant(
      of: find.byKey(ValueKey('syncLog-row-$i')),
      matching: what,
    );
    // A whole-run row has no source.
    expect(inRow(0, find.text('All calendars')), findsOneWidget);
    expect(
      inRow(
        0,
        find.text('manual: 12 alerts planned; armed 2, cancelled 0, kept 10'),
      ),
      findsOneWidget,
    );
    // A row of a source that is there carries its name and its time.
    expect(inRow(1, find.text('Work Outlook')), findsOneWidget);
    expect(inRow(1, find.text('Synced')), findsOneWidget);
    expect(inRow(1, find.text('Tue 09:25')), findsOneWidget);
    // One whose source was deleted keeps its row, without the name.
    expect(inRow(2, find.text('A removed calendar')), findsOneWidget);
    expect(inRow(2, find.text('The link stopped working')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('pulling down reads the engine again', (t) async {
    final h = await pumpApp(t, location: '/health');
    final before = _healthCalls(h);

    await t.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await t.pumpAndSettle();

    expect(_healthCalls(h), greaterThan(before));
    await h.dispose(t);
  });

  testWidgets('the overflow menu opens Settings', (t) async {
    final h = await pumpApp(t, location: '/health');

    await t.tap(find.byKey(const Key('healthMenu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a phone that is not on the list gets the general tip first', (
    t,
  ) async {
    _tallScreen(t);
    // The harness's phone is a Google one.
    final h = await pumpApp(t, location: '/health');

    expect(find.text('Phone-maker tips'), findsOneWidget);
    await t.tap(find.text('Phone-maker tips'));
    await t.pumpAndSettle();

    final general = find.text(_generalTip);
    final samsung = find.text(_samsungTip);
    expect(general, findsOneWidget);
    expect(samsung, findsOneWidget);
    expect(t.getTopLeft(general).dy, lessThan(t.getTopLeft(samsung).dy));
    await h.dispose(t);
  });

  testWidgets('a phone that cannot be read keeps the general title and logs '
      'only the code', (t) async {
    await _logging((logged) async {
      _tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/health',
        seed: (h) async {
          h.ui['deviceInfo'] = (_) => throw PlatformException(
            code: 'no_activity',
            message: 'https://secret.example/feed.ics',
          );
        },
      );

      expect(find.text('Phone-maker tips'), findsOneWidget);
      expect(logged.any((l) => l.contains('no_activity')), isTrue);
      expect(logged.any((l) => l.contains('secret.example')), isFalse);
      await h.dispose(t);
    });
  });

  testWidgets('a Fix that cannot open the settings says so in fixed text', (
    t,
  ) async {
    await _logging((logged) async {
      _tallScreen(t);
      final h = await pumpApp(
        t,
        location: '/health',
        seed: (h) async {
          h.health = {...healthyEngine(), 'canUseFullScreenIntent': false};
        },
      );
      _failEngine(h, 'openPermissionSettings');

      await t.tap(find.byKey(const Key('fix-fullScreen')));
      await t.pumpAndSettle();

      expect(find.text("Couldn't open the settings."), findsOneWidget);
      expect(find.textContaining('secret.example'), findsNothing);
      expect(logged.any((l) => l.contains('no_settings')), isTrue);
      expect(logged.any((l) => l.contains('secret.example')), isFalse);
      await h.dispose(t);
    });
  });

  testWidgets('a test alarm that cannot start says so and does not promise '
      'one', (t) async {
    await _logging((logged) async {
      _tallScreen(t);
      final h = await pumpApp(t, location: '/health');
      _failEngine(h, 'testAlarm');

      await t.tap(find.byKey(const Key('testAlarm')));
      await t.pumpAndSettle();

      expect(find.text("Couldn't start the test."), findsOneWidget);
      expect(find.text('A test alarm rings in 5 seconds.'), findsNothing);
      expect(find.textContaining('secret.example'), findsNothing);
      expect(logged.any((l) => l.contains('no_settings')), isTrue);
      expect(logged.any((l) => l.contains('secret.example')), isFalse);

      // A messenger shows one snack bar at a time and queues the next behind
      // it, so a promise made after the failure would only show once the
      // failure's own 4 seconds were up, which is after everything above.
      // Let them pass, then look again.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text("Couldn't start the test."), findsNothing);
      expect(find.text('A test alarm rings in 5 seconds.'), findsNothing);
      await h.dispose(t);
    });
  });
}
