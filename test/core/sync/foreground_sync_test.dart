import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sync/foreground_sync.dart';
import 'package:tminus/core/sync/sync_service.dart';

/// Only what ForegroundSync uses; the rest of SyncService is never called.
class _FakeSync implements SyncService {
  DateTime? finishedAt;
  final runs = <SyncTrigger>[];
  Future<void> gate = Future.value();

  /// When set, [lastFinished] throws it.
  Object? lastFinishedFailure;

  /// When set, [run] throws it (after recording the run).
  Object? runFailure;

  @override
  Future<DateTime?> lastFinished() async {
    final failure = lastFinishedFailure;
    if (failure != null) throw failure;
    return finishedAt;
  }

  @override
  Future<SyncReport> run(SyncTrigger trigger) async {
    runs.add(trigger);
    await gate;
    final failure = runFailure;
    if (failure != null) throw failure;
    return SyncReport(trigger: trigger, outcome: SyncRunOutcome.ok);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 6, 8);
  late _FakeSync sync;
  late ForegroundSync foreground;

  setUp(() {
    sync = _FakeSync();
    foreground = ForegroundSync(sync: sync, clock: () => now);
  });

  tearDown(() => foreground.dispose());

  test(
    'syncs when the last sync is older than 2 min, or there was none',
    () async {
      expect(await foreground.maybeSync(), isNotNull);
      sync.finishedAt = now.subtract(const Duration(minutes: 3));
      expect(await foreground.maybeSync(), isNotNull);
      expect(sync.runs, [SyncTrigger.foreground, SyncTrigger.foreground]);
    },
  );

  test('skips when a sync finished within 2 min', () async {
    sync.finishedAt = now.subtract(const Duration(seconds: 90));
    expect(await foreground.maybeSync(), isNull);
    expect(sync.runs, isEmpty);
  });

  test('a resume while a foreground sync runs joins it', () async {
    final release = Completer<void>();
    sync.gate = release.future;
    final first = foreground.maybeSync();
    final second = foreground.maybeSync();
    release.complete();
    expect(await first, same(await second));
    expect(sync.runs, hasLength(1));
  });

  test('a failing sync is logged and never thrown', () async {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);

    // A run that throws, with a feed link in its message.
    sync.runFailure = StateError(
      'GET https://calendar.example/s3cr3t/feed.ics failed',
    );
    expect(await foreground.maybeSync(), isNull);
    // The in-flight guard was cleared, so the next call runs again.
    expect(await foreground.maybeSync(), isNull);
    expect(sync.runs, hasLength(2));

    // Reading when the last sync finished can fail too (a database error);
    // nothing runs then.
    sync.lastFinishedFailure = StateError('no such table: s3cr3t');
    expect(await foreground.maybeSync(), isNull);
    expect(sync.runs, hasLength(2));

    // Only the error type is logged, never its message.
    final log = logged.join('\n');
    expect(log, contains('StateError'));
    expect(log, isNot(contains('s3cr3t')));
  });

  test('start syncs at once and again when the app resumes', () async {
    foreground.start();
    await pumpEventQueue();
    expect(sync.runs, hasLength(1));
    sync.finishedAt = now.subtract(const Duration(minutes: 5));
    // The binding takes one lifecycle step at a time: away and back.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await pumpEventQueue();
    expect(sync.runs, hasLength(2));
  });
}
