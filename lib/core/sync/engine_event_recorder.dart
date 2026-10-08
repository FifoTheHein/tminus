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

  /// Every entry this recorder inserted (duplicates are not repeated).
  Stream<AlertHistoryEntry> get recorded => _recorded.stream;

  bool get isListening => _live != null;

  /// Records live events from now on, then drains what queued while no
  /// Flutter engine was listening (spec §7). Safe to call twice.
  Future<void> start() async {
    _live ??= engine.events.listen(
      (e) => unawaited(_recordLive(e)),
      onError: (Object e) => debugPrint('Engine event stream failed: $e'),
    );
    try {
      await drainNow();
    } on MissingPluginException {
      // No native engine (widget tests, desktop).
    } on PlatformException catch (e) {
      debugPrint('drainEvents failed: ${e.code}');
    }
  }

  /// Drains the native queue into history. Returns the rows that were new.
  Future<List<AlertHistoryEntry>> drainNow() async {
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
  /// the row's values or a feed link.
  Future<void> _recordLive(EngineEvent e) async {
    try {
      await _record(e);
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
