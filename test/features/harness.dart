import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/app/app.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/onboarding_gate.dart';
import 'package:tminus/app/replan_scheduler.dart';
import 'package:tminus/app/router.dart';
import 'package:tminus/app/sync_runner.dart';
import 'package:tminus/app/theme_mode_controller.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/platform/ui_platform.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/sources/ics_link_probe.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/agenda/agenda_model.dart';

import '../core/fixtures.dart';
import '../core/storage/test_database.dart';

/// The real app (router, DI, theme) over an in-memory database, with every
/// platform channel mocked, the feed bodies kept in memory, a fixed clock and
/// zone (Johannesburg), and fakes that record syncs and re-plans instead of
/// running them.
///
/// Boot it with [pumpApp] and end every test with `await h.dispose(t)`.
class Harness {
  late final AppDatabase db;
  late final GoRouter router;

  /// The clock of the rules engine, the source statuses and the Agenda. A test
  /// may move it; the next read sees the new time.
  late DateTime now;

  /// Every sync the screens asked `SyncRunner` for, in order.
  final syncs = <SyncTrigger>[];

  /// How many re-plans `ReplanScheduler` ran (it runs them at once here).
  var replans = 0;

  /// What a `SyncRunner` call answers.
  SyncReport Function(SyncTrigger) syncResult = (t) =>
      SyncReport(trigger: t, outcome: SyncRunOutcome.ok);

  /// Every call the platform channels received, in order.
  final engineCalls = <MethodCall>[];
  final uiCalls = <MethodCall>[];
  final syncCalls = <MethodCall>[];

  /// flutter_secure_storage contents (key → link).
  final secrets = <String, String>{};

  /// The stored feed bodies (source id → body) that `FeedBodyCache` reads,
  /// writes and deletes. In memory: the real cache writes files under the
  /// platform's support directory, which a widget test has no platform side for.
  final feedBodies = <String, String>{};

  /// What `alarm_engine.getHealth` answers.
  Map<String, Object?> health = healthyEngine();

  /// What `alarm_engine.queryDeviceCalendars` answers.
  List<Map<String, Object?>> deviceCalendars = [];

  /// Extra `tminus_ui` answers by method; unlisted methods get the defaults.
  final ui = <String, Object? Function(MethodCall)>{};

  Future<void> go(WidgetTester t, String location) async {
    router.go(location);
    await t.pumpAndSettle();
  }

  /// Unmounts the app, then closes the database and puts every global back.
  Future<void> dispose(WidgetTester t) async {
    // Unmount first: every controller then cancels its listeners and timers.
    await t.pumpWidget(const SizedBox());
    router.dispose();
    try {
      // Closing the database is real asynchronous work: like every other
      // database call that a widget test waits for outside a pump, it runs in
      // the real zone, where an await that completes from outside the test's
      // fake clock cannot hold the test up.
      await t.runAsync(getIt.reset);
    } finally {
      for (final c in _channels) {
        _messenger.setMockMethodCallHandler(c, null);
      }
      _messenger.setMockStreamHandler(_engineEvents, null);
      tz.setLocalLocation(tz.UTC);
    }
  }
}

Map<String, Object?> healthyEngine() => {
  'notificationsEnabled': true,
  'ringingChannelEnabled': true,
  'canUseFullScreenIntent': true,
  'canScheduleExactAlarms': true,
  'ignoringBatteryOptimizations': true,
  'alarmStreamMuted': false,
  'upcoming': <Object?>[],
};

final _messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// flutter_secure_storage 11's channel (the platform interface's
/// `MethodChannelFlutterSecureStorage`, which is the implementation in tests).
const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The engine's live event stream. Mocked so that a debug panel or the event
/// recorder can listen to it without a native side.
const _engineEvents = EventChannel(AlarmEngine.eventChannelName);

const _channels = [
  MethodChannel(AlarmEngine.methodChannelName),
  MethodChannel(SyncPlatform.channelName),
  MethodChannel(UiPlatform.channelName),
  _secureStorage,
];

/// The feed bodies in a map. Not a temporary directory: path_provider has no
/// platform side in a widget test, and real file I/O never completes inside the
/// fake-async zone that `pumpAndSettle` runs in. `SourceAdmin.updateIcsUrl`
/// ends with a `delete`, so a re-link test needs this.
class _MemoryBodies extends FeedBodyCache {
  _MemoryBodies(this._bodies)
    : super(() => throw UnsupportedError('The harness keeps bodies in memory'));

  final Map<String, String> _bodies;

  @override
  Future<String?> read(String sourceId) async => _bodies[sourceId];

  @override
  Future<void> write(String sourceId, String body) async {
    _bodies[sourceId] = body;
  }

  @override
  Future<void> delete(String sourceId) async {
    _bodies.remove(sourceId);
  }
}

/// Boots the app onto [location] and returns the harness.
///
/// [onboarded] sets the stored onboarding flag, [feeds] stands in for the
/// network of the link check, and [seed] fills the database (and may replace
/// registrations) before the first frame. The harness never calls
/// `HealthMonitor.start()` or `ForegroundSync.start()` (both start timers): a
/// test that needs a health report calls `await getIt<HealthMonitor>().refresh()`
/// and pumps.
///
/// Services that a test which failed before its `h.dispose(t)` left registered
/// are closed first, so one failure does not fail every later test with
/// "already registered".
Future<Harness> pumpApp(
  WidgetTester t, {
  String location = '/agenda',
  DateTime? now,
  bool onboarded = true,
  http.Client? feeds,
  Future<void> Function(Harness h)? seed,
}) async {
  if (getIt.isRegistered<AppDatabase>()) await t.runAsync(getIt.reset);
  initZones();
  tz.setLocalLocation(johannesburg);
  final h = Harness()..now = now ?? DateTime.utc(2026, 10, 6, 7, 27);
  configureDependencies(openDatabase: openTestDatabase);
  h.db = getIt<AppDatabase>();

  await getIt.unregister<FeedBodyCache>();
  getIt.registerSingleton<FeedBodyCache>(_MemoryBodies(h.feedBodies));
  await getIt.unregister<SyncRunner>();
  getIt.registerSingleton<SyncRunner>((trigger) async {
    h.syncs.add(trigger);
    return h.syncResult(trigger);
  });
  await getIt.unregister<ReplanScheduler>();
  getIt.registerSingleton(
    ReplanScheduler(replan: () async => h.replans++, delay: Duration.zero),
    dispose: (r) => r.dispose(),
  );
  // Quiet modes and "Silenced ·" depend on the rules engine's clock.
  await getIt.unregister<RulesEngine>();
  getIt.registerFactory(
    () => RulesEngine(zone: johannesburg, clock: () => h.now),
  );
  await getIt.unregister<SourceStatusLoader>();
  getIt.registerSingleton(
    SourceStatusLoader(
      sources: getIt(),
      syncLog: getIt(),
      appSettings: getIt(),
      clock: () => h.now,
    ),
  );
  await getIt.unregister<AgendaLoader>();
  getIt.registerFactory(
    () => AgendaLoader(
      planner: getIt(),
      statuses: getIt(),
      settings: getIt(),
      appSettings: getIt(),
      zone: () => johannesburg,
      clock: () => h.now,
    ),
  );
  if (feeds != null) {
    await getIt.unregister<IcsLinkProbe>();
    getIt.registerSingleton(
      IcsLinkProbe(
        client: feeds,
        deviceZone: () => 'Africa/Johannesburg',
        clock: () => h.now,
      ),
    );
  }

  _messenger.setMockMethodCallHandler(_channels[0], (c) async {
    h.engineCalls.add(c);
    return switch (c.method) {
      'applyPlan' => {'armed': 0, 'cancelled': 0, 'kept': 0},
      'getHealth' => h.health,
      'drainEvents' => <Object?>[],
      'queryDeviceCalendars' => h.deviceCalendars,
      'queryInstances' => <Object?>[],
      _ => null,
    };
  });
  _messenger.setMockMethodCallHandler(_channels[1], (c) async {
    h.syncCalls.add(c);
    return switch (c.method) {
      'installId' => 'test-install',
      'acquireLock' => true,
      'deviceZone' => 'Africa/Johannesburg',
      _ => null,
    };
  });
  _messenger.setMockMethodCallHandler(_channels[2], (c) async {
    h.uiCalls.add(c);
    final custom = h.ui[c.method];
    if (custom != null) return custom(c);
    return switch (c.method) {
      'deviceInfo' => {
        'versionName': '1.0.0',
        'versionCode': 1,
        'manufacturer': 'Google',
        'sdkInt': 36,
      },
      'requestPermission' => 'granted',
      'toneTitle' => 'Default alarm tone',
      _ => null,
    };
  });
  _messenger.setMockMethodCallHandler(_secureStorage, (c) async {
    final key = (c.arguments as Map?)?['key'] as String?;
    return switch (c.method) {
      'read' => h.secrets[key],
      'write' => h.secrets[key!] = (c.arguments as Map)['value'] as String,
      'delete' => h.secrets.remove(key),
      'containsKey' => h.secrets.containsKey(key),
      _ => null,
    };
  });
  _messenger.setMockStreamHandler(
    _engineEvents,
    MockStreamHandler.inline(
      onListen: (arguments, sink) {},
      onCancel: (arguments) {},
    ),
  );

  final app = getIt<AppSettings>();
  await app.setInstallId('test-install');
  await app.setOnboardingDone(onboarded);
  if (seed != null) await seed(h);
  // What `main` loads before the first frame.
  await getIt<ThemeModeController>().load();
  final gate = getIt<OnboardingGate>();
  await gate.load();
  h.router = createRouter(gate: gate);
  await t.pumpWidget(TMinusApp(router: h.router));
  h.router.go(location);
  await t.pumpAndSettle();
  return h;
}
