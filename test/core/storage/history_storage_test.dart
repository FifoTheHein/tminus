import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late AlertHistoryRepository history;
  late SyncLogRepository syncLog;

  final now = DateTime.utc(2026, 10, 6, 6);
  final start = DateTime.utc(2026, 10, 6, 8);
  const key = 'work|abc|2026-10-06T08:00:00.000Z';
  final headsUpId = PlannedAlert.idFor(key, 10);

  AlertHistoryEntry entry(
    AlertEventType type, {
    String? alertId,
    DateTime? at,
    DateTime? startUtc,
    String? k,
  }) => AlertHistoryEntry(
    type: type,
    alertId: alertId ?? headsUpId,
    occurrenceKey: k ?? key,
    startUtc: startUtc ?? start,
    atUtc: at ?? DateTime.utc(2026, 10, 6, 7, 50),
  );

  setUp(() {
    db = openTestDatabase();
    history = AlertHistoryRepository(db);
    syncLog = SyncLogRepository(db);
  });
  tearDown(() => db.close());

  group('AlertHistoryRepository', () {
    test('record de-duplicates on (type, alertId, atUtc)', () async {
      expect(await history.record(entry(AlertEventType.fired)), isTrue);
      expect(await history.record(entry(AlertEventType.fired)), isFalse);
      expect(await history.record(entry(AlertEventType.dismissed)), isTrue);
      expect(await history.recent(), hasLength(2));
    });

    test('round trips every field; recent is newest first', () async {
      final snoozed = AlertHistoryEntry(
        type: AlertEventType.snoozed,
        alertId: headsUpId,
        occurrenceKey: key,
        startUtc: start,
        atUtc: DateTime.utc(2026, 10, 6, 7, 51),
        snoozeUntilUtc: DateTime.utc(2026, 10, 6, 7, 56),
        title: 'Sprint planning',
      );
      await history.record(entry(AlertEventType.fired));
      await history.record(snoozed);
      final recent = await history.recent();
      expect(recent.first, snoozed);
      expect(recent.last.type, AlertEventType.fired);
    });

    test('acknowledgements: Dismiss all and Join ack the occurrence', () async {
      await history.record(entry(AlertEventType.dismissedAll));
      await history.record(
        entry(
          AlertEventType.joined,
          k: 'work|j|2026-10-06T09:00:00.000Z',
          startUtc: DateTime.utc(2026, 10, 6, 9),
        ),
      );
      final acks = await history.acknowledgements(nowUtc: now);
      expect(acks.isOccurrenceAcked(key, start), isTrue);
      expect(
        acks.isOccurrenceAcked(
          'work|j|2026-10-06T09:00:00.000Z',
          DateTime.utc(2026, 10, 6, 9),
        ),
        isTrue,
      );
      expect(
        acks.isOccurrenceAcked(key, DateTime.utc(2026, 10, 6, 9)),
        isFalse,
        reason: 'moved meeting',
      );
      expect(acks.isAlertDismissed(headsUpId, start), isFalse);
    });

    test(
      'acknowledgements: single Dismiss acks one alert, not snoozes',
      () async {
        await history.record(entry(AlertEventType.dismissed));
        await history.record(
          entry(
            AlertEventType.dismissed,
            alertId: '${PlannedAlert.idFor(key, 1)}:s',
          ),
        );
        await history.record(
          entry(AlertEventType.fired, alertId: PlannedAlert.idFor(key, 1)),
        );
        final acks = await history.acknowledgements(nowUtc: now);
        expect(acks.isAlertDismissed(headsUpId, start), isTrue);
        expect(
          acks.isAlertDismissed(PlannedAlert.idFor(key, 1), start),
          isFalse,
        );
        expect(acks.isOccurrenceAcked(key, start), isFalse);
      },
    );

    test(
      'acknowledgements ignore occurrences that started over 24 h ago',
      () async {
        final old = DateTime.utc(2026, 10, 5, 5, 59);
        await history.record(entry(AlertEventType.dismissedAll, startUtc: old));
        final acks = await history.acknowledgements(nowUtc: now);
        expect(acks.isOccurrenceAcked(key, old), isFalse);
      },
    );

    test('since and deleteBefore', () async {
      await history.record(
        entry(AlertEventType.fired, at: DateTime.utc(2026, 9, 1)),
      );
      await history.record(
        entry(AlertEventType.fired, at: DateTime.utc(2026, 10, 6, 7)),
      );
      expect(await history.since(DateTime.utc(2026, 10, 1)), hasLength(1));
      expect(await history.deleteBefore(DateTime.utc(2026, 10, 1)), 1);
      expect(await history.recent(), hasLength(1));
    });
  });

  group('SyncLogRepository', () {
    test('add, recent, latestForSource, deleteBefore', () async {
      final a = SyncLogEntry(
        sourceId: 'work',
        atUtc: DateTime.utc(2026, 10, 6, 5),
        outcome: SyncOutcome.success,
        occurrenceCount: 23,
        duration: const Duration(milliseconds: 840),
      );
      final b = SyncLogEntry(
        sourceId: 'work',
        atUtc: DateTime.utc(2026, 10, 6, 6),
        outcome: SyncOutcome.networkError,
        message: 'Timed out after 20 s',
      );
      final run = SyncLogEntry(
        atUtc: DateTime.utc(2026, 10, 6, 6, 1),
        outcome: SyncOutcome.otherError,
        message: 'applyPlan failed',
      );
      await syncLog.add(a);
      await syncLog.add(b);
      await syncLog.add(run);
      expect(await syncLog.recent(), [run, b, a]);
      expect(await syncLog.latestForSource('work'), b);
      expect(await syncLog.latestForSource('personal'), isNull);
      expect(await syncLog.deleteBefore(DateTime.utc(2026, 10, 6, 5, 30)), 1);
    });
  });
}
