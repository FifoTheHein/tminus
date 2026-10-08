import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'app/font_licenses.dart';
import 'app/sync_main.dart';
import 'core/sync/device_zone.dart';
import 'core/sync/engine_event_recorder.dart';
import 'core/sync/foreground_sync.dart';
import 'core/sync/sync_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  configureDependencies();
  await initDeviceZone(getIt<SyncPlatform>());
  // The one consumer of engine events in this isolate (Plan 3 note), started
  // before the first sync so history is current when it plans. Not awaited, so
  // the first frame does not wait for the database.
  unawaited(_startEventRecorder());
  getIt<ForegroundSync>().start();
  runApp(const TMinusApp());
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

/// The headless sync engine's entry point (`HeadlessFlutterRunner.ENTRYPOINT`).
/// It must stay in this library: the engine looks it up in the app's main
/// library, and `vm:entry-point` keeps release builds from tree-shaking it.
@pragma('vm:entry-point')
Future<void> syncMain(List<String> args) => runHeadlessSync(args);
