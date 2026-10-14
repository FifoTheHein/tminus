import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/sync/sync_service.dart';

/// Turns UI edits into re-plans (Plan 5 decision 2). Each [request] restarts
/// a short timer, so a burst of edits makes one run. At most one run is in
/// flight; requests during it make exactly one more. A run that finds the sync
/// lock taken is tried again, but only [_maxBusyRuns] times in a row; the next
/// request starts fresh.
class ReplanScheduler {
  ReplanScheduler({
    required this.replan,
    this.delay = const Duration(seconds: 1),
  });

  /// Each busy run has already waited out the lock wait, so this only bounds a
  /// lock that stays taken. Whatever the user does next (an edit, coming back
  /// to the app, a sync) plans from the current rules anyway.
  static const _maxBusyRuns = 3;

  /// `SyncService.run(SyncTrigger.edit)` in the app.
  final Future<Object?> Function() replan;
  final Duration delay;

  Timer? _timer;
  Future<void>? _running;
  bool _again = false;

  /// Busy results since the last request.
  int _busyRuns = 0;

  void request() {
    _timer?.cancel();
    _timer = Timer(delay, _fire);
  }

  /// Runs a pending request now, then waits for every run to finish. The
  /// app calls it when it goes to the background.
  Future<void> flush() async {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      _fire();
    }
    while (_running != null) {
      await _running;
    }
  }

  void dispose() => _timer?.cancel();

  void _fire() {
    _timer = null;
    _busyRuns = 0;
    if (_running != null) {
      _again = true;
      return;
    }
    _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      try {
        final report = await replan();
        // A run that never got the lock planned nothing: the sync that held
        // it may have read the rules before this edit. Go again, but not for
        // ever.
        if (report is SyncReport && report.outcome == SyncRunOutcome.busy) {
          if (++_busyRuns < _maxBusyRuns) {
            _again = true;
          } else {
            debugPrint('Re-planning stopped: the sync lock stayed taken');
          }
        }
      } catch (e) {
        // The type only: an error message can carry a row's values or a feed
        // link (Plan 5 constraint).
        debugPrint('Re-planning failed: ${e.runtimeType}');
      }
    } while (_again);
  }
}
