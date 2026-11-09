import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../core/engine/alarm_engine.dart';
import '../core/sync/source_status.dart';
import '../features/health/health_report.dart';

/// Keeps the Health checklist current for the whole app: the Health tab, the
/// Agenda banner and the navigation dot all read [report].
///
/// `AlarmEngine.openPermissionSettings` returns as soon as the settings screen
/// is open, so the refresh on resume is what picks up the user's change.
class HealthMonitor extends ChangeNotifier {
  HealthMonitor({
    required this.engine,
    required this.statuses,
    this.period = const Duration(minutes: 1),
  });

  final AlarmEngine engine;
  final SourceStatusLoader statuses;
  final Duration period;
  HealthReport? _report;
  Timer? _timer;
  AppLifecycleListener? _listener;
  bool _disposed = false;

  /// Null until the first [refresh] has finished.
  HealthReport? get report => _report;

  /// Refreshes now, on every resume, and every [period] while the app is
  /// resumed.
  void start() {
    if (_disposed) return;
    _listener ??= AppLifecycleListener(
      onResume: () {
        unawaited(refresh());
        _startTimer();
      },
      onPause: _stopTimer,
    );
    _startTimer();
    unawaited(refresh());
  }

  /// Reads the engine and the sources again and tells the listeners. Never
  /// throws: what cannot be read shows as the engine warning, or as no source
  /// rows.
  Future<void> refresh() async {
    if (_disposed) return;
    EngineHealth? health;
    try {
      health = await engine.getHealth();
    } on MissingPluginException {
      // No native side (desktop, plain widget tests): the report says so.
    } on PlatformException catch (e) {
      debugPrint('getHealth failed: ${e.code}');
    } catch (e) {
      // The type only: an error message can carry a row's values.
      debugPrint('Reading the alarm engine failed: ${e.runtimeType}');
    }
    var sources = const <SourceStatus>[];
    try {
      sources = await statuses.all();
    } catch (e) {
      debugPrint('Reading the sources failed: ${e.runtimeType}');
    }
    // A refresh still running when the monitor is disposed has nobody to tell.
    if (_disposed) return;
    _report = buildHealthReport(health, sources);
    notifyListeners();
  }

  void _startTimer() {
    _timer ??= Timer.periodic(period, (_) => unawaited(refresh()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    _listener?.dispose();
    _listener = null;
    super.dispose();
  }
}
