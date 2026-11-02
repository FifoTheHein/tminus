import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/sync/device_zone.dart';
import '../core/sync/engine_event_recorder.dart';
import '../core/sync/foreground_sync.dart';
import '../core/sync/sync_platform.dart';
import 'app_lifecycle.dart';
import 'di.dart';
import 'health_monitor.dart';
import 'onboarding_gate.dart';
import 'restore_guard.dart';
import 'theme_mode_controller.dart';

/// What `main` does between `configureDependencies` and `runApp`, in the order
/// that matters. Kept out of `main` so a test can pin that order.
///
/// 1. The device zone, then the restore check ([RestoreGuard]), before anything
///    that plans, fetches or watches: a restored database must not ring or
///    fetch (Plan 5 decision 4), and the router must not read its onboarding
///    flag before the check has had its say. Never throws.
/// 2. The theme and the onboarding flag, read before the first frame, so there
///    is no flash of the wrong theme or of the wrong first screen.
/// 3. The services that live as long as the app is open.
///
/// A restore that could not be made safe ([RestoreOutcome.unsafe]) left the old
/// phone's sources enabled, so nothing may sync until a later run of the guard
/// has finished the restore. The UI still starts, so the user is not locked
/// out. The start-up sync is skipped and the foreground sync is not started at
/// all, so no sync begins on its own. The guard remembers the failure
/// (`RestoreGuard.unsafe`): the syncs the screens ask for, and the re-plans
/// edits ask for, run it again first and plan and fetch nothing while it still
/// cannot finish the restore. The next start tries again as well.
Future<void> startServices() async {
  await initDeviceZone(getIt<SyncPlatform>());
  final restore = await getIt<RestoreGuard>().run();
  await getIt<ThemeModeController>().load();
  await getIt<OnboardingGate>().load();
  // The one consumer of engine events in this isolate (Plan 3 note), started
  // before the first sync so history is current when it plans. Not awaited:
  // its first drain is not needed for the first frame.
  unawaited(_startEventRecorder());
  getIt<AppLifecycle>().start();
  getIt<HealthMonitor>().start();
  if (restore == RestoreOutcome.unsafe) {
    debugPrint('Start-up sync skipped: a restored backup is not safe yet');
  } else {
    getIt<ForegroundSync>().start();
  }
}

/// Starts the event recorder and swallows what its first drain throws. That
/// drain reads and writes the database, and nothing awaits this call, so an
/// error would otherwise surface as an unhandled one. Logged by type only: an
/// error message can carry a row's values or a feed link.
Future<void> _startEventRecorder() async {
  try {
    await getIt<EngineEventRecorder>().start();
  } catch (e) {
    debugPrint('Starting the engine event recorder failed: ${e.runtimeType}');
  }
}
