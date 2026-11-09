import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/health_monitor.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/features/health/health_report.dart';

/// Only what HealthMonitor uses; the rest of SourceStatusLoader is never
/// called.
class _FakeStatuses implements SourceStatusLoader {
  List<SourceStatus> statuses = const [];

  /// When set, [all] throws it.
  Object? failure;

  @override
  Future<List<SourceStatus>> all() async {
    final f = failure;
    if (f != null) throw f;
    return statuses;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(AlarmEngine.methodChannelName);
  final calls = <MethodCall>[];
  final now = DateTime.utc(2026, 10, 6, 9, 27);
  const work = SourceConfig(
    id: 'w',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.w',
  );
  late _FakeStatuses statuses;

  setUp(() {
    statuses = _FakeStatuses();
  });

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// Answers every `alarm_engine` call with [handler], and records it.
  void reply(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  int healthCalls() => calls.where((c) => c.method == 'getHealth').length;

  /// What the native `getHealth` answers: everything fine unless told.
  Map<String, Object?> healthJson({
    bool canUseFullScreenIntent = true,
    List<Map<String, Object?>> upcoming = const [],
  }) => {
    'notificationsEnabled': true,
    'ringingChannelEnabled': true,
    'canUseFullScreenIntent': canUseFullScreenIntent,
    'canScheduleExactAlarms': true,
    'ignoringBatteryOptimizations': true,
    'alarmStreamMuted': false,
    'upcoming': upcoming,
  };

  SourceStatus synced(SourceConfig config) => sourceStatusOf(
    config: config,
    state: SourceSyncState(
      lastSuccessUtc: now.subtract(const Duration(minutes: 4)),
    ),
    setup: SourceSetup.ready,
    now: now,
  );

  /// Captures what the monitor logs, and puts `debugPrint` back after.
  List<String> captureLog() {
    final logged = <String>[];
    final realDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = realDebugPrint);
    return logged;
  }

  HealthMonitor monitorOf({Duration? period}) => HealthMonitor(
    engine: AlarmEngine(),
    statuses: statuses,
    period: period ?? const Duration(minutes: 1),
  );

  test('refresh reads getHealth and notifies', () async {
    reply(
      (_) => healthJson(
        canUseFullScreenIntent: false,
        upcoming: [
          {
            'id': 'a',
            'fireAtUtcMs': 1790000000000,
            'strength': 'alarm',
            'title': 'Sprint planning',
          },
        ],
      ),
    );
    statuses.statuses = [synced(work)];
    final monitor = monitorOf();
    addTearDown(monitor.dispose);
    var notified = 0;
    monitor.addListener(() => notified++);
    expect(monitor.report, isNull);

    await monitor.refresh();

    expect(calls.map((c) => c.method), ['getHealth']);
    expect(notified, 1);
    final report = monitor.report!;
    expect(report.hasProblem, isTrue);
    expect(
      report.items.singleWhere((i) => i.id == 'fullScreen').level,
      HealthLevel.problem,
    );
    expect(report.items.last.id, 'source:w');
    expect(report.upcoming.single.title, 'Sprint planning');

    // Every refresh tells the listeners, so "Synced 4 min ago" moves on.
    await monitor.refresh();
    expect(calls, hasLength(2));
    expect(notified, 2);
  });

  test('a failing getHealth leaves a report with the engine warning', () async {
    final logged = captureLog();
    reply(
      (_) => throw PlatformException(
        code: 'unavailable',
        message: 'Failed for https://calendar.example/s3cr3t/feed.ics',
      ),
    );
    statuses.statuses = [synced(work)];
    final monitor = monitorOf();
    addTearDown(monitor.dispose);

    await monitor.refresh();

    final report = monitor.report!;
    expect(report.items.map((i) => i.id), ['engine', 'source:w']);
    expect(report.items.first.level, HealthLevel.warning);
    expect(report.overall, HealthLevel.warning);
    // The error's code is logged, never its message.
    final log = logged.join('\n');
    expect(log, contains('unavailable'));
    expect(log, isNot(contains('s3cr3t')));
  });

  test('a missing native side is not an error', () async {
    final logged = captureLog();
    reply((_) => throw MissingPluginException());
    final monitor = monitorOf();
    addTearDown(monitor.dispose);
    var notified = 0;
    monitor.addListener(() => notified++);

    await monitor.refresh();

    expect(monitor.report!.items.single.id, 'engine');
    expect(monitor.report!.overall, HealthLevel.warning);
    expect(notified, 1);
    expect(logged, isEmpty);
  });

  test('an answer that is not a health report gives the engine warning too, '
      'logged by type', () async {
    final logged = captureLog();
    reply((_) => null);
    statuses.statuses = [synced(work)];
    final monitor = monitorOf();
    addTearDown(monitor.dispose);

    await monitor.refresh();

    expect(monitor.report!.items.map((i) => i.id), ['engine', 'source:w']);
    expect(logged.join('\n'), contains('Reading the alarm engine failed'));
  });

  test('sources that cannot be read are logged by type and leave the engine '
      'rows', () async {
    final logged = captureLog();
    reply((_) => healthJson());
    statuses.failure = StateError('no such table: s3cr3t');
    final monitor = monitorOf();
    addTearDown(monitor.dispose);

    await monitor.refresh();

    expect(monitor.report!.items.map((i) => i.id), [
      'notifications',
      'fullScreen',
      'exactAlarms',
      'battery',
      'alarmChannel',
    ]);
    final log = logged.join('\n');
    expect(log, contains('StateError'));
    expect(log, isNot(contains('s3cr3t')));
  });

  test(
    'a refresh that finishes after dispose is dropped without an error',
    () async {
      final release = Completer<void>();
      reply((_) async {
        await release.future;
        return healthJson();
      });
      final monitor = monitorOf();
      var notified = 0;
      monitor.addListener(() => notified++);

      final running = monitor.refresh();
      monitor.dispose();
      release.complete();
      await running;

      expect(notified, 0);
      expect(monitor.report, isNull);
    },
  );

  testWidgets('start refreshes at once, every period and on resume, and stops '
      'while the app is paused or the monitor is disposed', (tester) async {
    // A frame is drawn when the app comes back, so there must be a tree.
    await tester.pumpWidget(const SizedBox.shrink());
    reply((_) => healthJson());
    final monitor = monitorOf(period: const Duration(minutes: 1));

    monitor.start();
    await tester.pump();
    expect(healthCalls(), 1);

    await tester.pump(const Duration(minutes: 1));
    expect(healthCalls(), 2);
    await tester.pump(const Duration(minutes: 1));
    expect(healthCalls(), 3);

    // The app goes to the background: the timer stops.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(minutes: 5));
    expect(healthCalls(), 3);

    // It comes back: one refresh at once, then every period again.
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(healthCalls(), 4);
    await tester.pump(const Duration(minutes: 1));
    expect(healthCalls(), 5);

    monitor.dispose();
    await tester.pump(const Duration(minutes: 5));
    expect(healthCalls(), 5);
  });
}
