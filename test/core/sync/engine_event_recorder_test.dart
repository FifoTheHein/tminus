import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/engine_event_recorder.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

/// A history whose next [failures] writes throw, like a database that another
/// connection holds locked. The message carries a feed link on purpose: an
/// error message must never reach the log.
class _FlakyHistory extends AlertHistoryRepository {
  _FlakyHistory(super.db);

  int failures = 0;

  @override
  Future<bool> record(AlertHistoryEntry entry) async {
    if (failures > 0) {
      failures--;
      throw StateError('database is locked (https://example.test/s3cr3t.ics)');
    }
    return super.record(entry);
  }
}

/// A history whose first write waits until [release] is called, like a write
/// queued behind another connection. Later writes go straight through.
class _GatedHistory extends AlertHistoryRepository {
  _GatedHistory(super.db);

  final _released = Completer<void>();

  /// True once the first write has reached the gate.
  bool reached = false;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<bool> record(AlertHistoryEntry entry) async {
    if (!reached) {
      reached = true;
      await _released.future;
    }
    return super.record(entry);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel(AlarmEngine.methodChannelName);
  const events = EventChannel(AlarmEngine.eventChannelName);

  late AppDatabase db;
  late AlertHistoryRepository history;
  late EngineEventRecorder recorder;
  late List<Map<String, Object?>> queued;
  final meeting = occ(uid: 'm1', title: 'Sprint planning');

  Map<String, Object?> json(String type, String alertId, int atMs) => {
    'type': type,
    'alertId': alertId,
    'occurrenceKey': meeting.key,
    'startUtcMs': meeting.startUtc.millisecondsSinceEpoch,
    'atUtcMs': atMs,
    'snoozeUntilUtcMs': type == 'snoozed' ? atMs + 60000 : null,
  };

  setUp(() async {
    db = openTestDatabase();
    history = AlertHistoryRepository(db);
    await SourceRepository(db).save(
      const SourceConfig(
        id: 'work',
        name: 'Work',
        color: blue,
        kind: SourceKind.ics,
      ),
    );
    await OccurrenceRepository(db).replaceForSource('work', [meeting]);
    queued = [];
    messenger.setMockMethodCallHandler(method, (call) async {
      if (call.method != 'drainEvents') return null;
      final drained = List.of(queued);
      queued.clear();
      return drained;
    });
    recorder = EngineEventRecorder(
      engine: AlarmEngine(),
      history: history,
      occurrences: OccurrenceRepository(db),
    );
  });

  tearDown(() async {
    await recorder.stop();
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(events, null);
    await db.close();
  });

  test('drainNow records queued events with the cached title', () async {
    queued.addAll([json('fired', 'a', 1000), json('snoozed', 'a', 2000)]);
    expect(await recorder.drainNow(), hasLength(2));
    final rows = await history.recent();
    expect(rows.map((r) => r.type), [
      AlertEventType.snoozed,
      AlertEventType.fired,
    ]);
    expect(rows.first.title, 'Sprint planning');
    expect(rows.first.snoozeUntilUtc, isNotNull);
    expect(queued, isEmpty);
  });

  test(
    'an event whose occurrence is not cached is recorded without a title',
    () async {
      queued.add({...json('fired', 't', 1000), 'occurrenceKey': 'test|1000'});
      await recorder.drainNow();
      expect((await history.recent()).single.title, isNull);
    },
  );

  test('start records live events and drains the queue, each once', () async {
    queued.add(json('fired', 'a', 1000));
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, sink) {
          sink.success(json('dismissed', 'a', 3000));
          sink.success(json('dismissed', 'a', 3000)); // repeated: dropped
        },
      ),
    );
    final recorded = <AlertHistoryEntry>[];
    recorder.recorded.listen(recorded.add);

    await recorder.start();
    await waitUntil(() => recorded.length == 2);

    expect(recorder.isListening, isTrue);
    expect(recorded.map((e) => e.type).toSet(), {
      AlertEventType.fired,
      AlertEventType.dismissed,
    });
    expect(await history.recent(), hasLength(2));
  });

  test('a row already stored by another isolate is not re-broadcast', () async {
    queued.add(json('fired', 'a', 1000));
    await history.record(
      AlertHistoryEntry(
        type: AlertEventType.fired,
        alertId: 'a',
        occurrenceKey: meeting.key,
        startUtc: meeting.startUtc,
        atUtc: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      ),
    );
    final recorded = <AlertHistoryEntry>[];
    recorder.recorded.listen(recorded.add);
    expect(await recorder.drainNow(), isEmpty);
    await pumpEventQueue();
    expect(recorded, isEmpty);
  });

  test('start without a native engine does not throw', () async {
    messenger.setMockMethodCallHandler(
      method,
      (call) async => throw MissingPluginException(),
    );
    await recorder.start();
    expect(recorder.isListening, isTrue);
  });

  test('a failed write of a live event is logged, not thrown', () async {
    // The first write fails; the recorder under test replaces the shared one.
    final flaky = _FlakyHistory(db)..failures = 1;
    recorder = EngineEventRecorder(
      engine: AlarmEngine(),
      history: flaky,
      occurrences: OccurrenceRepository(db),
    );
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, eventSink) {
          sink = eventSink;
          sink.success(json('fired', 'a', 1000));
        },
      ),
    );
    final logged = <String>[];
    final realDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = realDebugPrint);
    final recorded = <AlertHistoryEntry>[];
    recorder.recorded.listen(recorded.add);
    final uncaught = <Object>[];

    // The live listener is created in this zone, so an error it lets escape
    // lands in the handler instead of the test's own zone.
    runZonedGuarded(
      () => unawaited(recorder.start()),
      (error, stack) => uncaught.add(error),
    );
    await waitUntil(() => logged.isNotEmpty || uncaught.isNotEmpty);

    expect(uncaught, isEmpty);
    expect(logged.single, allOf(contains('fired'), contains('StateError')));
    expect(logged.single, isNot(contains('s3cr3t')));
    expect(recorded, isEmpty);

    // The subscription kept running: the next event is recorded.
    sink.success(json('dismissed', 'a', 3000));
    await waitUntil(() => recorded.isNotEmpty || uncaught.isNotEmpty);

    expect(uncaught, isEmpty);
    expect(recorded.single.type, AlertEventType.dismissed);
    expect((await history.recent()).map((r) => r.type), [
      AlertEventType.dismissed,
    ]);
  });

  test('a drain that starts during another waits for it', () async {
    final gated = _GatedHistory(db);
    addTearDown(gated.release); // an expect that fails must not strand a write
    recorder = EngineEventRecorder(
      engine: AlarmEngine(),
      history: gated,
      occurrences: OccurrenceRepository(db),
    );
    final finished = <String>[];

    // The first drain takes the native queue, then stalls on its first write.
    queued.add(json('dismissed', 'a', 1000));
    final first = recorder.drainNow().whenComplete(() => finished.add('first'));
    await waitUntil(() => gated.reached);

    // The second starts while the first is writing. It must not report back
    // before the dismissal is in history, or a sync would plan without it.
    // What arrived since the first took the queue is the second's to record.
    queued.add(json('fired', 'b', 2000));
    final second = recorder.drainNow().whenComplete(
      () => finished.add('second'),
    );
    await pumpEventQueue();
    expect(finished, isEmpty);

    gated.release();
    expect((await first).map((e) => e.type), [AlertEventType.dismissed]);
    expect((await second).map((e) => e.type), [AlertEventType.fired]);
    expect(finished, ['first', 'second']);
    expect((await history.recent()).map((r) => r.type), [
      AlertEventType.fired,
      AlertEventType.dismissed,
    ]);
  });

  test(
    'a database failure in start\'s first drain is logged, not thrown',
    () async {
      final flaky = _FlakyHistory(db)..failures = 1;
      recorder = EngineEventRecorder(
        engine: AlarmEngine(),
        history: flaky,
        occurrences: OccurrenceRepository(db),
      );
      queued.add(json('fired', 'a', 1000));
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );
      final logged = <String>[];
      final realDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      addTearDown(() => debugPrint = realDebugPrint);

      await recorder.start(); // completes normally: the error does not escape

      expect(logged.single, contains('StateError'));
      expect(logged.single, isNot(contains('s3cr3t')));
      expect(recorder.isListening, isTrue);

      // The failed drain does not hold up the next one.
      queued.add(json('dismissed', 'a', 2000));
      expect(await recorder.drainNow(), hasLength(1));
    },
  );

  test('a drain waits for a live event that is still being written', () async {
    final gated = _GatedHistory(db);
    addTearDown(gated.release); // an expect that fails must not strand a write
    recorder = EngineEventRecorder(
      engine: AlarmEngine(),
      history: gated,
      occurrences: OccurrenceRepository(db),
    );
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, sink) => sink.success(json('dismissed', 'a', 1000)),
      ),
    );

    // The live dismissal reaches the recorder and stalls on its write.
    await recorder.start();
    await waitUntil(() => gated.reached);

    // Nothing is queued natively, because the engine handed the dismissal to
    // the live stream. A drain that did not wait for that write would report
    // back before the dismissal is in history.
    var drained = false;
    final drain = recorder.drainNow().whenComplete(() => drained = true);
    await pumpEventQueue();
    expect(drained, isFalse);

    gated.release();
    expect(await drain, isEmpty); // the live row is not this drain's
    expect((await history.recent()).map((r) => r.type), [
      AlertEventType.dismissed,
    ]);
  });
}
