import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/replan_scheduler.dart';
import 'package:tminus/core/sync/sync_service.dart';

void main() {
  test('three quick requests run one re-plan', () async {
    var runs = 0;
    final s = ReplanScheduler(
      replan: () async => runs++,
      delay: const Duration(milliseconds: 20),
    );
    s.request();
    s.request();
    s.request();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, 1);
  });

  test('a request during a run causes exactly one more run', () async {
    var runs = 0;
    final gate = Completer<void>();
    final s = ReplanScheduler(
      replan: () async {
        runs++;
        if (runs == 1) await gate.future;
        return null;
      },
      delay: Duration.zero,
    );
    s.request();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    s.request();
    s.request();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    gate.complete();
    await s.flush();
    expect(runs, 2);
  });

  test('a busy re-plan is tried again', () async {
    var runs = 0;
    final s = ReplanScheduler(
      replan: () async {
        runs++;
        return SyncReport(
          trigger: SyncTrigger.edit,
          outcome: runs == 1 ? SyncRunOutcome.busy : SyncRunOutcome.ok,
        );
      },
      delay: Duration.zero,
    );
    s.request();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await s.flush();
    expect(runs, 2);
  });

  test('flush runs a pending request at once', () async {
    var runs = 0;
    final s = ReplanScheduler(
      replan: () async => runs++,
      delay: const Duration(hours: 1),
    );
    s.request();
    await s.flush();
    expect(runs, 1);
  });

  test('a failing re-plan is logged and the next request still runs', () async {
    var runs = 0;
    final s = ReplanScheduler(
      replan: () async {
        runs++;
        if (runs == 1) throw StateError('db locked');
        return null;
      },
      delay: Duration.zero,
    );
    s.request();
    await s.flush();
    s.request();
    await s.flush();
    expect(runs, 2);
  });

  // Beyond the plan's list.

  test('three busy re-plans in a row stop the retries', () async {
    var runs = 0;
    final s = ReplanScheduler(
      replan: () async {
        runs++;
        // Busy for ever, but for the tenth run: without a limit that shows as
        // ten runs here, not as a test that never ends.
        return SyncReport(
          trigger: SyncTrigger.edit,
          outcome: runs < 10 ? SyncRunOutcome.busy : SyncRunOutcome.ok,
        );
      },
      delay: Duration.zero,
    );
    s.request();
    await s.flush();
    expect(runs, 3);

    // The next request starts fresh: three more runs, then it stops again.
    s.request();
    await s.flush();
    expect(runs, 6);
  });

  test('a failing re-plan logs only the exception type', () async {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);

    final s = ReplanScheduler(
      // A message that names a feed link, as a real failure could.
      replan: () async =>
          throw StateError('GET https://calendar.example/s3cr3t/feed.ics'),
      delay: Duration.zero,
    );
    s.request();
    await s.flush();

    final log = logged.join('\n');
    expect(log, contains('StateError'));
    expect(log, isNot(contains('s3cr3t')));
  });

  test('dispose drops a waiting request', () async {
    var runs = 0;
    final s = ReplanScheduler(
      replan: () async => runs++,
      delay: const Duration(milliseconds: 10),
    );
    s.request();
    s.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, 0);
  });
}
