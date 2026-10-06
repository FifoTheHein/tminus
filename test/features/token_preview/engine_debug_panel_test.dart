import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/features/token_preview/engine_debug_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(AlarmEngine.methodChannelName);
  final calls = <MethodCall>[];

  void mockEngine() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getHealth' => {
          'notificationsEnabled': true,
          'canUseFullScreenIntent': true,
          'canScheduleExactAlarms': true,
          'ignoringBatteryOptimizations': false,
          'alarmStreamMuted': false,
          'upcoming': [
            {
              'id': 'a',
              'fireAtUtcMs': 1790000000000,
              'strength': 'alarm',
              'title': 'Sprint planning',
            },
          ],
        },
        'drainEvents' => [
          {
            'type': 'fired',
            'alertId': 'a',
            'occurrenceKey': 'src|a|occ',
            'startUtcMs': 1790000060000,
            'atUtcMs': 1790000000000,
            'snoozeUntilUtcMs': null,
          },
        ],
        _ => null,
      };
    });
  }

  setUp(() {
    configureDependencies();
    mockEngine();
  });

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
    getIt.reset();
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
    expect(find.textContaining('battery optimised'), findsOneWidget);
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

  testWidgets('Drain events reports what was drained', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('Drain events'));
    await tester.pumpAndSettle();
    expect(find.text('Drained 1: fired'), findsOneWidget);
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
