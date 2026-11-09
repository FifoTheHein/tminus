import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/replan_scheduler.dart';
import '../../app/sync_runner.dart';
import '../../core/model/event_override.dart';
import '../../core/model/quiet_state.dart';
import '../../core/rules/rules_engine.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/override_repository.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/sync/outcome_severity.dart';
import '../../core/sync/sync_service.dart';
import 'agenda_model.dart';

/// Pull-to-refresh's one-line result (Plan 5 decision 21); null = say nothing.
String? pullMessage(SyncReport r) {
  if (r.outcome == SyncRunOutcome.busy) {
    return 'Another sync is running. Try again in a minute.';
  }
  final failed = r.sources
      .where((s) => s.outcome.severity != OutcomeSeverity.ok)
      .length;
  if (failed == 0) return null;
  return failed == 1
      ? '1 calendar could not be read. See Sources.'
      : '$failed calendars could not be read. See Sources.';
}

/// What the Agenda shows and what its controls do. It reads through
/// [AgendaLoader] and never plans on its own; every edit that changes what
/// rings ends with a re-plan request, never with a fetching sync.
class AgendaController extends ChangeNotifier {
  AgendaController({
    required this.loader,
    required this.db,
    required this.overrides,
    required this.settings,
    required this.rulesEngine,
    required this.replan,
    required this.runSync,
    this.tick = const Duration(seconds: 30),
    this.debounce = const Duration(milliseconds: 100),
  });

  final AgendaLoader loader;
  final AppDatabase db;
  final OverrideRepository overrides;
  final SettingsRepository settings;
  final RulesEngine Function() rulesEngine;
  final ReplanScheduler replan;
  final SyncRunner runSync;

  /// How often the Agenda reloads on its own: the countdown, the now line and
  /// a quiet mode that ends all move with the clock.
  final Duration tick;

  /// How long writes must stay quiet before the Agenda reloads. A sync writes
  /// many rows, and one reload after them is enough.
  final Duration debounce;

  AgendaSnapshot? _snapshot;
  bool _failed = false;
  bool _disposed = false;
  StreamSubscription<Object?>? _updates;
  Timer? _ticker;
  Timer? _debounce;

  /// How many loads have started. Only the newest one is shown.
  var _loads = 0;

  /// Null until the first load has finished.
  AgendaSnapshot? get snapshot => _snapshot;

  /// The latest load threw: the screen offers **Try again**.
  bool get failed => _failed;

  /// Reloads on any table write in this isolate (and on AppLifecycle's
  /// refresh after a background sync), and every [tick] for the countdown,
  /// the now line and quiet modes that end.
  void start() {
    if (_disposed) return;
    _updates ??= db.tableUpdates().listen((_) => _soon());
    _ticker ??= Timer.periodic(tick, (_) => _soon());
    unawaited(reload());
  }

  void _soon() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(debounce, () => unawaited(reload()));
  }

  /// Loads the Agenda again. The load that started last is the one that
  /// shows: an older load that finishes after it is dropped, so it can never
  /// put back what an edit has just changed.
  Future<void> reload() async {
    final mine = ++_loads;
    AgendaSnapshot? loaded;
    var failed = false;
    try {
      loaded = await loader.load();
    } catch (e) {
      // The type only: an error message can carry a row's values.
      debugPrint('Loading the agenda failed: ${e.runtimeType}');
      failed = true;
    }
    if (_disposed || mine != _loads) return;
    if (loaded != null) _snapshot = loaded;
    _failed = failed;
    notifyListeners();
  }

  /// The toggle (Plan 5 decision 8). It writes `enabled` on the meeting key
  /// only when the wanted state is not the one the meeting has on its own, so
  /// switching an event back to what rules and quiet modes would do removes
  /// the override. The effective override's profile and custom alerts move to
  /// the meeting key with it (decision 9).
  Future<void> setOn(AgendaItem item, bool on) async {
    final snap = _snapshot;
    if (snap == null) return;
    // The same ordered keys for the natural state and for the write: they
    // must agree on which override is the one in effect.
    final keys = item.meeting.lookupKeys;
    final natural = rulesEngine()
        .resolve(item.meeting, snap.rules.withoutOccurrenceEnabled(keys))
        .alerts
        .isNotEmpty;
    final enabled = enabledToWrite(wantOn: on, naturalOn: natural);
    await overrides.rewriteFor(
      OverrideScope.occurrence,
      [item.meeting.key, ...keys],
      (e) => EventOverride(
        scope: OverrideScope.occurrence,
        target: item.meeting.key,
        profileId: e?.profileId,
        customAlerts: e?.customAlerts,
        enabled: enabled,
      ),
    );
    replan.request();
  }

  /// Runs a fetching sync and returns the line to show, if any.
  Future<String?> pullToRefresh() async =>
      pullMessage(await runSync(SyncTrigger.pullToRefresh));

  /// The banner's **End**. It records when the mode ended (through
  /// `setQuietStateAt`, on the Agenda's clock), so a quick-settings tap that
  /// is older than this cannot bring the mode back.
  Future<void> endQuiet() async {
    await settings.setQuietStateAt(
      const QuietNone(),
      changedAtUtc: loader.clock(),
    );
    replan.request();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_updates?.cancel());
    _ticker?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
