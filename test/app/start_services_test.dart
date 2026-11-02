import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/health_monitor.dart';
import 'package:tminus/app/onboarding_gate.dart';
import 'package:tminus/app/restore_guard.dart';
import 'package:tminus/app/start_services.dart';
import 'package:tminus/app/theme_mode_controller.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';

import '../core/fixtures.dart';
import '../core/storage/test_database.dart';
import '../features/harness.dart' show healthyEngine;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engineChannel = MethodChannel(AlarmEngine.methodChannelName);
  const syncChannel = MethodChannel(SyncPlatform.channelName);
  const engineEvents = EventChannel(AlarmEngine.eventChannelName);

  const ics = SourceConfig(
    id: 'ics-1',
    name: 'Work Outlook',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.ics-1',
  );

  /// What the native side received, in order: `sync.deviceZone`,
  /// `sync.installId`, `engine.getHealth`, `events.listen`, and so on.
  late List<String> calls;

  /// The alerts of each `applyPlan`.
  late List<List<Object?>> plans;

  /// While set and not completed, the native side does not answer `installId`.
  Completer<void>? idAnswer;

  setUp(() {
    calls = [];
    plans = [];
    idAnswer = null;
    configureDependencies(openDatabase: openTestDatabase);
    messenger.setMockMethodCallHandler(engineChannel, (c) async {
      calls.add('engine.${c.method}');
      switch (c.method) {
        case 'applyPlan':
          plans.add((c.arguments as Map)['alerts'] as List<Object?>);
          return {'armed': 0, 'cancelled': 0, 'kept': 0};
        case 'getHealth':
          return healthyEngine();
        case 'drainEvents':
          return <Object?>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(syncChannel, (c) async {
      calls.add('sync.${c.method}');
      switch (c.method) {
        case 'installId':
          await idAnswer?.future;
          return 'phone-B';
        case 'acquireLock':
          return true;
      }
      return null;
    });
    messenger.setMockStreamHandler(
      engineEvents,
      MockStreamHandler.inline(
        onListen: (arguments, sink) => calls.add('events.listen'),
      ),
    );
  });

  tearDown(() async {
    final waiting = idAnswer;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    await getIt.reset();
    messenger.setMockMethodCallHandler(engineChannel, null);
    messenger.setMockMethodCallHandler(syncChannel, null);
    messenger.setMockStreamHandler(engineEvents, null);
  });

  /// A database that came from a backup made on another phone: it holds that
  /// phone's install id, one enabled feed and a meeting of the feed in the
  /// cache. The native side reports this phone as `phone-B`.
  Future<void> seedBackupFromAnotherPhone() async {
    final app = getIt<AppSettings>();
    await app.setInstallId('phone-A');
    await app.setOnboardingDone(true);
    await getIt<SourceRepository>().save(ics);
    await getIt<OccurrenceRepository>().replaceForSource('ics-1', [
      occ(
        sourceId: 'ics-1',
        uid: 'standup',
        start: DateTime.now().toUtc().add(const Duration(days: 1)),
      ),
    ]);
  }

  test('start-up checks the restore before anything else', () async {
    await seedBackupFromAnotherPhone();
    // The native side holds the install id back, so the restore check cannot
    // finish until the test lets it.
    final answer = Completer<void>();
    idAnswer = answer;

    final started = startServices();
    await pumpEventQueue();

    // Only the zone and the id were asked for. Nothing that plans, fetches or
    // watches has started: no lock, no engine call, no event stream.
    expect(calls, [
      'sync.deviceZone',
      'sync.installId',
    ], reason: 'nothing may start while the restore check is still waiting');
    // Nor has the onboarding flag been read: the seed stores it as done, so a
    // gate loaded before the restore check would already say so.
    expect(getIt<OnboardingGate>().done, isFalse);

    answer.complete();
    await started;
    await waitUntil(
      () => calls.contains('sync.releaseLock'),
      timeout: const Duration(seconds: 10),
    );

    // Everything else came after the id was asked for.
    final asked = calls.indexOf('sync.installId');
    for (final later in [
      'sync.acquireLock',
      'engine.drainEvents',
      'engine.getHealth',
      'events.listen',
    ]) {
      expect(calls, contains(later));
      expect(calls.indexOf(later), greaterThan(asked), reason: later);
    }
    // So the first sync found the restored database: the feed is off, and
    // nothing is armed from the old phone's meeting.
    expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isFalse);
    expect(plans, hasLength(1));
    expect(plans.single, isEmpty);
  });

  test('start-up skips the sync when the restore is unsafe', () async {
    await seedBackupFromAnotherPhone();
    // The last write of a restore fails, as in a locked or full database.
    await getIt<AppDatabase>().customStatement(
      'CREATE TRIGGER no_install_id BEFORE INSERT ON settings '
      "WHEN NEW.name = '${AppSettings.installIdKey}' "
      "BEGIN SELECT RAISE(ABORT, 'no'); END",
    );

    await startServices();

    // The guard remembers, for the syncs the screens ask for later.
    expect(getIt<RestoreGuard>().unsafe, isTrue);
    // The rest of start-up ran, so the user is not locked out: the health
    // monitor has its first report and the event recorder has drained.
    await waitUntil(
      () =>
          getIt<HealthMonitor>().report != null &&
          calls.contains('engine.drainEvents'),
      timeout: const Duration(seconds: 10),
    );
    await pumpEventQueue(times: 100);
    expect(getIt<OnboardingGate>().done, isTrue);
    // But no sync began: no lock was asked for and nothing was armed. That
    // matters because the database still holds the old phone's enabled feed.
    expect(calls, isNot(contains('sync.acquireLock')));
    expect(calls, isNot(contains('engine.applyPlan')));
    expect((await getIt<SourceRepository>().byId('ics-1'))!.enabled, isTrue);
  });

  test('start-up loads the theme and listens for background syncs', () async {
    // A database written on this phone, with the user's theme choice in it.
    await getIt<AppSettings>().setInstallId('phone-B');
    await getIt<SettingsRepository>().setString(
      ThemeModeController.settingsKey,
      'dark',
    );

    await startServices();

    // The stored choice is in place before the first frame is built.
    expect(getIt<ThemeModeController>().mode, ThemeMode.dark);

    // Let the start-up sync finish, so that its own writes cannot be taken for
    // the signal below.
    await waitUntil(
      () => calls.contains('sync.releaseLock'),
      timeout: const Duration(seconds: 10),
    );
    await pumpEventQueue();
    final seen = <Object?>[];
    final updates = getIt<AppDatabase>().tableUpdates().listen(seen.add);
    await pumpEventQueue();
    expect(seen, isEmpty, reason: 'nothing else is writing now');

    // A headless sync finishing tells the open app, which makes every screen
    // read the database again: drift only knows the writes of this isolate.
    await messenger.handlePlatformMessage(
      SyncPlatform.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('syncFinished', {
          'trigger': 'periodic',
          'outcome': 'ok',
        }),
      ),
      (_) {},
    );
    await pumpEventQueue();
    expect(seen, isNotEmpty);
    await updates.cancel();
  });
}
