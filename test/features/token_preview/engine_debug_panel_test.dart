import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/features/token_preview/engine_debug_panel.dart';

import '../../core/storage/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(AlarmEngine.methodChannelName);
  const events = EventChannel(AlarmEngine.eventChannelName);
  final calls = <MethodCall>[];
  var upcoming = <Map<String, Object?>>[];
  var drained = <Map<String, Object?>>[];
  var ringingChannelEnabled = true;
  MockStreamHandlerEventSink? eventSink;

  Map<String, Object?> event(String type) => {
    'type': type,
    'alertId': 'a',
    'occurrenceKey': 'src|a|occ',
    'startUtcMs': 1790000060000,
    'atUtcMs': 1790000000000,
    'snoozeUntilUtcMs': null,
  };

  void mockEngine() {
    upcoming = [
      {
        'id': 'a',
        'fireAtUtcMs': 1790000000000,
        'strength': 'alarm',
        'title': 'Sprint planning',
      },
    ];
    drained = [event('fired')];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getHealth' => {
          'notificationsEnabled': true,
          'ringingChannelEnabled': ringingChannelEnabled,
          'canUseFullScreenIntent': true,
          'canScheduleExactAlarms': true,
          'ignoringBatteryOptimizations': false,
          'alarmStreamMuted': false,
          'upcoming': upcoming,
        },
        'drainEvents' => drained,
        _ => null,
      };
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          eventSink = sink;
        },
        onCancel: (arguments) {
          eventSink = null;
        },
      ),
    );
  }

  int healthCalls() => calls.where((c) => c.method == 'getHealth').length;

  setUp(() {
    ringingChannelEnabled = true;
    // Drain events records through EngineEventRecorder into the database.
    configureDependencies(openDatabase: openTestDatabase);
    mockEngine();
  });

  tearDown(() async {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(events, null);
    eventSink = null;
    // Closes the in-memory database the drain opened.
    await getIt.reset();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TMinusTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(child: EngineDebugPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the next scheduled alerts and the health flags', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(find.text('Next 5 scheduled'), findsOneWidget);
    expect(find.textContaining('Alarm · Sprint planning'), findsOneWidget);
    expect(find.textContaining('notifications on'), findsOneWidget);
    expect(find.textContaining('ringing channel on'), findsOneWidget);
    expect(find.textContaining('battery optimised'), findsOneWidget);
  });

  testWidgets('flags a blocked ringing channel', (tester) async {
    ringingChannelEnabled = false;
    await pumpPanel(tester);
    expect(find.textContaining('notifications on'), findsOneWidget);
    expect(find.textContaining('ringing channel OFF'), findsOneWidget);
  });

  testWidgets('Test alarm asks for an alarm after the chosen delay', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.tap(find.text('1 min'));
    await tester.pump();
    await tester.tap(find.text('Test alarm'));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((c) => c.method == 'testAlarm').arguments, {
      'strength': 'alarm',
      'delaySec': 60,
    });
    expect(find.text('Alarm in 1 min'), findsOneWidget);
  });

  testWidgets('Test heads-up asks for a heads-up in 5 s by default', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.tap(find.text('Test heads-up'));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((c) => c.method == 'testAlarm').arguments, {
      'strength': 'headsUp',
      'delaySec': 5,
    });
    expect(find.text('Heads-up in 5 s'), findsOneWidget);
  });

  testWidgets('an engine event reloads the scheduled alerts', (tester) async {
    await pumpPanel(tester);
    expect(find.textContaining('Alarm · Sprint planning'), findsOneWidget);
    expect(healthCalls(), 1);

    upcoming = []; // the alarm fired, so nothing is scheduled any more
    // Platform messages are delivered outside the test's fake async zone.
    await tester.runAsync(() async {
      eventSink!.success({
        'type': 'fired',
        'alertId': 'a',
        'occurrenceKey': 'src|a|occ',
        'startUtcMs': 1790000060000,
        'atUtcMs': 1790000000000,
        'snoozeUntilUtcMs': null,
      });
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(healthCalls(), 2);
    expect(find.text('Nothing scheduled'), findsOneWidget);
  });

  testWidgets('returning to the app reloads the scheduled alerts', (
    tester,
  ) async {
    await pumpPanel(tester);
    upcoming = [];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(healthCalls(), 2);
    expect(find.text('Nothing scheduled'), findsOneWidget);
  });

  testWidgets('Drain events reports what was drained', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('Drain events'));
    await tester.pumpAndSettle();
    expect(find.text('Drained 1: fired'), findsOneWidget);
  });

  testWidgets('Drain events goes through the recorder into alert history', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.tap(find.text('Drain events'));
    await tester.pumpAndSettle();
    expect(find.text('Drained 1: fired'), findsOneWidget);

    // The recorder is the one caller of drainEvents, so the drained event is
    // stored by it rather than lost to the panel.
    final stored = await tester.runAsync(
      () => getIt<AlertHistoryRepository>().recent(),
    );
    expect(stored, hasLength(1));
    expect(stored!.single.type, AlertEventType.fired);
    expect(stored.single.alertId, 'a');
    expect(stored.single.occurrenceKey, 'src|a|occ');
  });

  testWidgets('Drain events includes the events already seen live', (
    tester,
  ) async {
    await pumpPanel(tester);
    // The engine de-duplicates: events the live stream delivered are dropped when
    // drained again, so the panel itself must remember them. The native side still
    // returns the same two events (same dedup keys) from drainEvents, and the
    // recorder hands back only the rows it newly stored, which is none here.
    final live = [event('fired'), event('dismissed')];
    drained = live;
    await tester.runAsync(() async {
      for (final e in live) {
        eventSink!.success(e);
      }
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drain events'));
    await tester.pumpAndSettle();
    expect(find.text('Drained 2: fired, dismissed'), findsOneWidget);

    await tester.tap(find.text('Drain events'));
    await tester.pumpAndSettle();
    expect(find.text('No new engine events'), findsOneWidget);
  });

  testWidgets(
    'without the native engine the panel says so instead of crashing',
    (tester) async {
      // What a platform without the Kotlin side does (desktop, plain widget tests).
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw MissingPluginException(),
      );
      await pumpPanel(tester);
      expect(find.text('Engine unavailable'), findsOneWidget);
      await tester.tap(find.text('Test alarm'));
      await tester.pumpAndSettle();
      expect(
        find.text('Engine not available on this platform'),
        findsOneWidget,
      );
    },
  );
}
