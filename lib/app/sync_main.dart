import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import '../core/storage/app_database.dart';
import '../core/sync/sync_platform.dart';
import '../core/sync/sync_service.dart';
import 'di.dart';
import 'restore_guard.dart';

/// The headless engine's work (spec §7): `syncMain(args)` in lib/main.dart
/// calls this. [args] holds the trigger name `SyncWorker` passed.
///
/// A restored backup is made safe first, as `main` does: after a restore,
/// `SyncBootReceiver` or the periodic sync can start this run before the app
/// is ever opened, and it must not plan from the old phone's cache, read its
/// calendar ids or post a Feed broken notice for every feed. When that cannot
/// be done (`RestoreOutcome.unsafe`) the run syncs nothing and reports `retry`:
/// the guard's change was rolled back, so the cause is probably temporary (a
/// locked or full database), and WorkManager's retry (twice, after 30 s and
/// 60 s) runs the guard again soon. Reporting `ok` would count a one-shot
/// trigger as done, and leave a waiting quick-settings tile tap unapplied
/// until the next periodic sync.
///
/// Always reports an outcome through `tminus_sync.finished`, so the worker
/// never waits for its timeout: a run that throws for any reason (a failed
/// lock call, a database error) reports `retry`. Failures are logged by type
/// only, because an error message can carry a row's values or a feed link.
///
/// [openDatabase] is for tests, which pass an in-memory or temporary database.
Future<void> runHeadlessSync(
  List<String> args, {
  AppDatabase Function()? openDatabase,
}) async {
  var outcome = SyncRunOutcome.retry;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // Plugins with a Dart side (path_provider) register themselves only for
    // `main`; another entry point has to ask.
    DartPluginRegistrant.ensureInitialized();
    configureDependencies(openDatabase: openDatabase);
    // Never throws. Before anything plans or fetches.
    final restore = await getIt<RestoreGuard>().run();
    if (restore == RestoreOutcome.unsafe) {
      debugPrint('Headless sync skipped: a restored backup is not safe yet');
    } else {
      // SyncService.run sets tz.local from the device first.
      final report = await getIt<SyncService>().run(
        SyncTrigger.parse(args.isEmpty ? null : args.first),
      );
      outcome = report.outcome;
    }
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
