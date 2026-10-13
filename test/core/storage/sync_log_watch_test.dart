import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late SyncLogRepository syncLog;

  setUp(() {
    db = openTestDatabase();
    syncLog = SyncLogRepository(db);
  });
  tearDown(() => db.close());

  /// A row for the work source, logged at 06:[minute] UTC on 6 Oct 2026.
  SyncLogEntry row(int minute, {SyncOutcome outcome = SyncOutcome.success}) =>
      SyncLogEntry(
        sourceId: 'work',
        atUtc: DateTime.utc(2026, 10, 6, 6, minute),
        outcome: outcome,
      );

  test('watchRecent emits again after a row is added', () async {
    final first = row(0);
    await syncLog.add(first);

    final seen = <List<SyncLogEntry>>[];
    final sub = syncLog.watchRecent().listen(seen.add);
    addTearDown(sub.cancel);
    await waitUntil(() => seen.isNotEmpty);

    final added = row(5, outcome: SyncOutcome.networkError);
    await syncLog.add(added);
    await waitUntil(() => seen.length == 2);

    expect(seen, [
      [first],
      [added, first],
    ]);
  });

  test('watchRecent keeps the newest rows up to the limit', () async {
    // Added out of time order, so only the logged time (not the order the
    // rows went in) puts the newest first.
    final oldest = row(0);
    final newest = row(20);
    final middle = row(10);
    await syncLog.add(oldest);
    await syncLog.add(newest);
    await syncLog.add(middle);

    expect(await syncLog.watchRecent(limit: 2).first, [newest, middle]);
  });
}
