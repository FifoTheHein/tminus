import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/planned_alert.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel(AlarmEngine.methodChannelName);
  const events = EventChannel(AlarmEngine.eventChannelName);
  final calls = <MethodCall>[];

  void reply(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(events, null);
  });

  Map<String, Object?> eventJson(
    String type,
    String alertId,
    int atMs, {
    int? snoozeUntilMs,
  }) => {
    'type': type,
    'alertId': alertId,
    'occurrenceKey': 'src|$alertId|occ',
    'startUtcMs': 1790000060000,
    'atUtcMs': atMs,
    'snoozeUntilUtcMs': snoozeUntilMs,
  };

  PlannedAlert sampleAlert() {
    const key = 'src|uid1|2026-10-06T08:00:00.000Z';
    final start = DateTime.utc(2026, 10, 6, 8);
    final fireAt = start.subtract(const Duration(minutes: 1));
    return PlannedAlert(
      id: PlannedAlert.idFor(key, 1),
      occurrenceKey: key,
      fireAtUtc: fireAt,
      offsetMinutes: 1,
      strength: AlertStrength.alarm,
      sound: const SoundSettings(),
      event: EventSnapshot(
        title: 'Sprint planning',
        startUtc: start,
        endUtc: start.add(const Duration(hours: 1)),
        joinUrl: 'https://teams.microsoft.com/l/meetup-join/abc',
        color: 0xFF6AA0F5,
      ),
      coalesceGroup: PlannedAlert.groupFor(fireAt),
    );
  }

  test(
    'applyPlan sends version 1 with every alert as JSON and parses the counts',
    () async {
      reply((_) => {'armed': 1, 'cancelled': 2, 'kept': 3});
      final alert = sampleAlert();

      final result = await AlarmEngine().applyPlan([alert]);

      expect(result, const ApplyResult(armed: 1, cancelled: 2, kept: 3));
      expect(calls.single.method, 'applyPlan');
      expect(calls.single.arguments, {
        'version': 1,
        'alerts': [alert.toJson()],
      });
    },
  );

  test('getHealth parses the permission flags and the upcoming list', () async {
    reply(
      (_) => {
        'notificationsEnabled': true,
        'canUseFullScreenIntent': false,
        'canScheduleExactAlarms': true,
        'ignoringBatteryOptimizations': false,
        'alarmStreamMuted': true,
        'upcoming': [
          {
            'id': 'a',
            'fireAtUtcMs': 1790000000000,
            'strength': 'alarm',
            'title': 'Sprint planning',
          },
          {
            'id': 'b',
            'fireAtUtcMs': 1790000600000,
            'strength': 'headsUp',
            'title': 'Client demo',
          },
        ],
      },
    );

    final health = await AlarmEngine().getHealth();

    expect(health.notificationsEnabled, isTrue);
    expect(health.canUseFullScreenIntent, isFalse);
    expect(health.canScheduleExactAlarms, isTrue);
    expect(health.ignoringBatteryOptimizations, isFalse);
    expect(health.alarmStreamMuted, isTrue);
    expect(health.upcoming.map((u) => u.id), ['a', 'b']);
    expect(
      health.upcoming.first.fireAtUtc,
      DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true),
    );
    expect(health.upcoming.last.strength, AlertStrength.headsUp);
  });

  test('testAlarm sends the strength name and the delay in seconds', () async {
    reply((_) => null);
    final engine = AlarmEngine();
    await engine.testAlarm(AlertStrength.headsUp);
    await engine.testAlarm(
      AlertStrength.alarm,
      delay: const Duration(minutes: 1),
    );
    expect(calls.map((c) => c.arguments), [
      {'strength': 'headsUp', 'delaySec': 5},
      {'strength': 'alarm', 'delaySec': 60},
    ]);
  });

  test('openPermissionSettings sends each kind by name', () async {
    reply((_) => null);
    final engine = AlarmEngine();
    for (final kind in PermissionKind.values) {
      await engine.openPermissionSettings(kind);
    }
    expect(calls.map((c) => (c.arguments as Map)['kind']), [
      'notifications',
      'fullScreenIntent',
      'exactAlarm',
      'batteryOptimization',
      'alarmVolume',
    ]);
  });

  test(
    'drainEvents parses events and drops duplicates within and across drains',
    () async {
      var drain = 0;
      reply((_) {
        drain++;
        return drain == 1
            ? [
                eventJson('fired', 'a', 1),
                eventJson('fired', 'a', 1),
                eventJson('dismissed', 'a', 2),
              ]
            : [eventJson('dismissed', 'a', 2), eventJson('missed', 'b', 3)];
      });
      final engine = AlarmEngine();

      final first = await engine.drainEvents();
      final second = await engine.drainEvents();

      expect(first.map((e) => e.type), [
        EngineEventType.fired,
        EngineEventType.dismissed,
      ]);
      expect(second.map((e) => e.type), [EngineEventType.missed]);
      expect(
        first.first.atUtc,
        DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      );
    },
  );

  test('snoozed events carry snoozeUntilUtc', () async {
    reply((_) => [eventJson('snoozed', 'a', 5, snoozeUntilMs: 1790000300000)]);
    final event = (await AlarmEngine().drainEvents()).single;
    expect(
      event.snoozeUntilUtc,
      DateTime.fromMillisecondsSinceEpoch(1790000300000, isUtc: true),
    );
    expect(event.dedupKey, 'snoozed|a|5');
  });

  test(
    'events reach every listener once, and drain skips what was streamed',
    () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success(eventJson('fired', 'a', 1));
            sink.success(eventJson('fired', 'a', 1));
            sink.success(eventJson('dismissed', 'a', 2));
          },
        ),
      );
      reply((_) => [eventJson('fired', 'a', 1), eventJson('missed', 'b', 3)]);
      final engine = AlarmEngine();
      final first = <EngineEvent>[];
      final second = <EngineEvent>[];
      final s1 = engine.events.listen(first.add);
      final s2 = engine.events.listen(second.add);

      await pumpEventQueue();

      expect(first.map((e) => e.type), [
        EngineEventType.fired,
        EngineEventType.dismissed,
      ]);
      expect(second.map((e) => e.type), [
        EngineEventType.fired,
        EngineEventType.dismissed,
      ]);
      expect((await engine.drainEvents()).map((e) => e.alertId), ['b']);
      await s1.cancel();
      await s2.cancel();
    },
  );

  test('a platform error surfaces as PlatformException', () async {
    reply(
      (_) => throw PlatformException(
        code: 'bad_args',
        message: 'Unsupported plan version 2',
      ),
    );
    await expectLater(
      AlarmEngine().applyPlan(const []),
      throwsA(isA<PlatformException>()),
    );
  });
}
