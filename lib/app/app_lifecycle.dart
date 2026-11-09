import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../core/storage/app_database.dart';
import '../core/sync/sync_platform.dart';
import 'replan_scheduler.dart';

/// Keeps the open UI current and the database safe to back up (Plan 5
/// decisions 4 and 6).
/// - drift tells watchers only about writes made in this isolate, so when a
///   headless sync finishes, and on every resume, every table is marked as
///   updated and each screen re-reads.
/// - On pause a waiting re-plan runs, then a passive WAL checkpoint folds the
///   log into the main file that backup copies.
///
/// The signal arrives through the `tminus_sync` channel's one method-call
/// handler, which [SyncPlatform.backgroundSyncFinished] sets on its first
/// listener and clears when the last one cancels. So this class listens
/// through the one [SyncPlatform] it is given and keeps that subscription
/// until [dispose]: a listener on another instance that cancelled would clear
/// the handler for this one too.
class AppLifecycle {
  AppLifecycle({
    required this.db,
    required this.platform,
    required this.replan,
  });

  final AppDatabase db;
  final SyncPlatform platform;
  final ReplanScheduler replan;
  AppLifecycleListener? _listener;
  StreamSubscription<String>? _signal;

  void start() {
    _listener ??= AppLifecycleListener(
      onResume: () => unawaited(refresh()),
      onPause: () => unawaited(onPause()),
    );
    _signal ??= platform.backgroundSyncFinished.listen(
      (_) => unawaited(refresh()),
    );
  }

  /// Marks every table as updated, so every watcher reads again.
  Future<void> refresh() async {
    try {
      db.markTablesUpdated(db.allTables);
    } catch (e) {
      debugPrint('Refreshing the screens failed: ${e.runtimeType}');
    }
  }

  /// Runs a waiting re-plan, then checkpoints the WAL. Never throws.
  Future<void> onPause() async {
    await replan.flush();
    try {
      await db.checkpoint();
    } catch (e) {
      debugPrint('WAL checkpoint failed: ${e.runtimeType}');
    }
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
    unawaited(_signal?.cancel());
    _signal = null;
  }
}
