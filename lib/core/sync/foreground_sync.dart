import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../rules/rules_engine.dart';
import 'sync_service.dart';

/// Spec §7 "App foreground": syncs in the UI isolate at app start and on
/// every resume, unless a sync (from any isolate) finished in the last
/// [minGap] (Plan 4 decision). Pull-to-refresh (Plan 5) calls
/// [SyncService.run] directly and always syncs.
class ForegroundSync {
  ForegroundSync({required this.sync, UtcClock? clock})
    : clock = clock ?? systemUtcNow;

  static const minGap = Duration(minutes: 2);

  final SyncService sync;
  final UtcClock clock;
  AppLifecycleListener? _listener;
  Future<SyncReport?>? _running;

  /// Syncs now if due, then again on each resume.
  void start() {
    _listener ??= AppLifecycleListener(onResume: () => unawaited(maybeSync()));
    unawaited(maybeSync());
  }

  /// Runs a foreground sync unless one finished within [minGap] or one
  /// started here is still running. Never throws.
  Future<SyncReport?> maybeSync() {
    return _running ??= _syncIfDue().whenComplete(() => _running = null);
  }

  Future<SyncReport?> _syncIfDue() async {
    try {
      final last = await sync.lastFinished();
      if (last != null && clock().difference(last) < minGap) return null;
      return await sync.run(SyncTrigger.foreground);
    } catch (e) {
      // The type only: an error message can carry a row's values or a feed
      // link (Plan 4 constraint).
      debugPrint('Foreground sync failed: ${e.runtimeType}');
      return null;
    }
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
