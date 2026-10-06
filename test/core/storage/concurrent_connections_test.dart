import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';

import 'test_database.dart';

void main() {
  group('two connections to one file (decision 14)', () {
    late Directory dir;
    late AppDatabase a;
    late AppDatabase b;

    // Two AppDatabase instances on one file are the point of this group.
    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    tearDownAll(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
    );

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tminus_concurrency_');
      final file = File('${dir.path}/tminus.sqlite');
      // The same setup hook AppDatabase.open() passes to drift_flutter.
      a = AppDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: AppDatabase.configureConnection,
        ),
      );
      b = AppDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: AppDatabase.configureConnection,
        ),
      );
    });

    tearDown(() async {
      await a.close();
      await b.close();
      dir.deleteSync(recursive: true);
    });

    test('concurrent record calls never throw; one inserts per pair', () async {
      final historyA = AlertHistoryRepository(a);
      final historyB = AlertHistoryRepository(b);
      for (var i = 0; i < 30; i++) {
        final e = AlertHistoryEntry(
          type: AlertEventType.fired,
          alertId: 'alert$i',
          occurrenceKey: 'work|abc|2026-10-06T08:00:00.000Z',
          startUtc: DateTime.utc(2026, 10, 6, 8),
          atUtc: DateTime.utc(2026, 10, 6, 7, 50),
        );
        final results = await Future.wait([
          historyA.record(e),
          historyB.record(e),
        ]);
        expect(results.where((r) => r), hasLength(1), reason: 'pair $i');
      }
      expect(await historyA.recent(limit: 100), hasLength(30));
    });

    test('every connection uses WAL and a busy timeout', () async {
      for (final db in [a, b]) {
        final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
        expect(mode.data.values.single, 'wal');
        final timeout = await db
            .customSelect('PRAGMA busy_timeout')
            .getSingle();
        expect(timeout.data.values.single, 5000);
      }
    });
  });

  test('an in-memory database also gets the busy timeout', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final timeout = await db.customSelect('PRAGMA busy_timeout').getSingle();
    expect(timeout.data.values.single, 5000);
  });
}
