import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/alarm_engine.dart';
import '../model/alert_history_entry.dart';
import '../storage/alert_history_repository.dart';
import '../storage/occurrence_repository.dart';

/// The one consumer of [AlarmEngine.events] and [AlarmEngine.drainEvents] in
/// an isolate (Plan 3: each event reaches Dart once, so a second consumer
/// would steal events from history). Records each event in `alert_history`
/// and re-broadcasts what it recorded on [recorded] for the UI (Plan 5).
///
/// The UI isolate calls [start]; the headless sync only calls [drainNow].
class EngineEventRecorder {
  EngineEventRecorder({
    required this.engine,
    required this.history,
    required this.occurrences,
  });

  final AlarmEngine engine;
  final AlertHistoryRepository history;
  final OccurrenceRepository occurrences;
  final _recorded = StreamController<AlertHistoryEntry>.broadcast();
  StreamSubscription<EngineEvent>? _live;

  /// Completes when the drain or live write started last has finished, whether
  /// it succeeded or failed. It never completes with an error, so one failure
  /// cannot hold up the work queued behind it.
  Future<void> _tail = Future<void>.value();

  /// Every entry this recorder inserted (duplicates are not repeated).
  Stream<AlertHistoryEntry> get recorded => _recorded.stream;

  bool get isListening => _live != null;

  /// Records live events from now on, then drains what queued while no
  /// Flutter engine was listening (spec §7). Safe to call twice. A first drain
  /// that fails is logged, not thrown, and the live subscription stays.
  Future<void> start() async {
    _live ??= engine.events.listen(
      (e) => unawaited(_recordLive(e)),
      onError: (Object e) =>
          debugPrint('Engine event stream failed: ${e.runtimeType}'),
    );
    try {
      await drainNow();
    } on MissingPluginException {
      // No native engine (widget tests, desktop).
    } on PlatformException catch (e) {
      debugPrint('drainEvents failed: ${e.code}');
    } catch (e) {
      // A database error, say. Logged by type only: an error message can carry
      // a row's values or a feed link.
      debugPrint('Draining the engine events failed: ${e.runtimeType}');
    }
  }

  /// Drains the native queue into history. Returns the rows this call
  /// recorded, which leaves out any that were already stored.
  ///
  /// Drains and live writes run one at a time, in the order they started. A
  /// drain that starts while another drain or a live event is still being
  /// written waits for it, then drains for itself, so when it returns every
  /// event delivered before the call is in history. The sync relies on that:
  /// it plans from history, and [start]'s first drain may still be writing.
  Future<List<AlertHistoryEntry>> drainNow() => _inOrder(_drain);

  /// Runs [action] once everything started before it has finished. A failure
  /// belongs to [action]'s caller alone: the chain moves on.
  Future<T> _inOrder<T>(Future<T> Function() action) async {
    final previous = _tail;
    final finished = Completer<void>();
    _tail = finished.future;
    try {
      await previous;
      return await action();
    } finally {
      finished.complete();
    }
  }

  Future<List<AlertHistoryEntry>> _drain() async {
    final inserted = <AlertHistoryEntry>[];
    for (final event in await engine.drainEvents()) {
      final entry = await _record(event);
      if (entry != null) inserted.add(entry);
    }
    return inserted;
  }

  Future<void> stop() async {
    await _live?.cancel();
    _live = null;
  }

  /// Records one live event. A failed write (a locked database, say) is logged
  /// and dropped, so it never becomes an unhandled error in the UI isolate and
  /// the subscription keeps recording the events that follow. The log line
  /// names the event type and the error type only: an error message can carry
  /// the row's values or a feed link. The write queues behind any drain or live
  /// write already in flight, so [drainNow] can wait for it.
  Future<void> _recordLive(EngineEvent e) async {
    try {
      await _inOrder(() => _record(e));
    } catch (error) {
      debugPrint(
        'Recording a ${e.type.name} event failed: ${error.runtimeType}',
      );
    }
  }

  /// The stored row, or null when it was already there.
  Future<AlertHistoryEntry?> _record(EngineEvent e) async {
    final entry = AlertHistoryEntry(
      type: AlertEventType.values.byName(e.type.name),
      alertId: e.alertId,
      occurrenceKey: e.occurrenceKey,
      startUtc: e.startUtc,
      atUtc: e.atUtc,
      snoozeUntilUtc: e.snoozeUntilUtc,
      title: (await occurrences.byKey(e.occurrenceKey))?.title,
    );
    if (!await history.record(entry)) return null;
    _recorded.add(entry);
    return entry;
  }
}
