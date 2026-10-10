import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import '../core/sync/sync_platform.dart';
import '../core/sync/sync_service.dart';
import 'di.dart';

/// The headless engine's work (spec §7): `syncMain(args)` in lib/main.dart
/// calls this. [args] holds the trigger name `SyncWorker` passed.
///
/// Always reports an outcome through `tminus_sync.finished`, so the worker
/// never waits for its timeout: a run that throws for any reason (a failed
/// lock call, a database error) reports `retry`. Failures are logged by type
/// only, because an error message can carry a row's values or a feed link.
Future<void> runHeadlessSync(List<String> args) async {
  var outcome = SyncRunOutcome.retry;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // Plugins with a Dart side (path_provider) register themselves only for
    // `main`; another entry point has to ask.
    DartPluginRegistrant.ensureInitialized();
    configureDependencies();
    // SyncService.run sets tz.local from the device first.
    final report = await getIt<SyncService>().run(
      SyncTrigger.parse(args.isEmpty ? null : args.first),
    );
    outcome = report.outcome;
  } catch (e) {
    debugPrint('Headless sync failed: ${e.runtimeType}');
  } finally {
    try {
      await getIt.reset(); // closes the database
    } catch (e) {
      debugPrint('Headless sync cleanup failed: ${e.runtimeType}');
    }
  }
  try {
    await SyncPlatform().finished(outcome.name);
  } catch (e) {
    debugPrint('Headless sync could not report its outcome: ${e.runtimeType}');
  }
}
