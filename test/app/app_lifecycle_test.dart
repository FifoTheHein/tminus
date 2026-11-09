import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;
import 'package:tminus/app/app_lifecycle.dart';
import 'package:tminus/app/replan_scheduler.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';

import '../core/storage/test_database.dart';

// The `tminus_sync` handler that carries the background-sync signal belongs to
// the channel, not to a SyncPlatform: a second platform that listened and then
// cancelled would clear the first one's handler. So each test here builds one
// SyncPlatform for one AppLifecycle, and a lifecycle that was started is
// disposed before the next test begins. A platform that is never listened to
// (the second test) touches no handler.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  testWidgets('a background sync signal refreshes every watcher', (t) async {
    // All of it runs through runAsync, not only the database calls. A widget
    // test's fake-async zone runs its microtasks only while the test body is
    // being driven from inside it, and an await that completes from outside
    // (cancelling a stream subscription does) ends that: every await after
    // it, such as closing the database, then never completes.
    final seen = <Object?>[];
    var before = 0;
    await t.runAsync(() async {
      final db = openTestDatabase();
      // tableUpdates fires on every markTablesUpdated; a watch query may skip
      // an emission whose rows did not change.
      final sub = db.tableUpdates().listen(seen.add);
      final lifecycle = AppLifecycle(
        db: db,
        platform: SyncPlatform(),
        replan: ReplanScheduler(replan: () async => null),
      )..start();
      await pumpEventQueue();
      before = seen.length;

      await messenger.handlePlatformMessage(
        SyncPlatform.channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('syncFinished', {
            'trigger': 'periodic',
            'outcome': 'ok',
          }),
        ),
        (_) {},
      );
      await pumpEventQueue();

      lifecycle.dispose();
      await sub.cancel();
      await db.close();
    });
    expect(seen.length, greaterThan(before));
  });

  test('onPause flushes a pending re-plan and checkpoints', () async {
    final db = openTestDatabase();
    var runs = 0;
    final lifecycle = AppLifecycle(
      db: db,
      platform: SyncPlatform(),
      replan: ReplanScheduler(
        replan: () async => runs++,
        delay: const Duration(hours: 1),
      ),
    );
    lifecycle.replan.request();
    // In-memory: the checkpoint is a no-op, and must not throw.
    await lifecycle.onPause();
    expect(runs, 1);
    await db.close();
  });

  // Beyond the plan's list.

  /// The binding takes one lifecycle step at a time.
  void walk(List<AppLifecycleState> states) {
    for (final state in states) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
  }

  test(
    'a pause runs a waiting re-plan and a resume refreshes every watcher',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seen = <Object?>[];
      final sub = db.tableUpdates().listen(seen.add);
      addTearDown(sub.cancel);
      var runs = 0;
      final lifecycle = AppLifecycle(
        db: db,
        platform: SyncPlatform(),
        replan: ReplanScheduler(
          replan: () async => runs++,
          delay: const Duration(hours: 1),
        ),
      )..start();
      addTearDown(lifecycle.dispose);

      lifecycle.replan.request();
      walk([
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await waitUntil(() => runs == 1);
      await pumpEventQueue(); // lets the checkpoint after the re-plan finish
      final before = seen.length;

      walk([
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await pumpEventQueue();
      expect(seen.length, greaterThan(before));
    },
  );

  test('a pause folds the write-ahead log into the main file', () async {
    final dir = await Directory.systemTemp.createTemp('tminus_checkpoint_');
    addTearDown(() => dir.delete(recursive: true));
    final main = File('${dir.path}/tminus.sqlite');
    // The same setup hook AppDatabase.open() passes to drift_flutter.
    final db = AppDatabase(
      NativeDatabase.createInBackground(
        main,
        setup: AppDatabase.configureConnection,
      ),
    );
    addTearDown(db.close);
    await SettingsRepository(db).setString('marker', 'kept');

    /// What a backup that copies only the main file, not the log, would hold.
    String? markerInMainFile(String copyName) {
      final copy = File('${dir.path}/$copyName.sqlite')
        ..writeAsBytesSync(main.readAsBytesSync());
      final raw = sqlite3.open(copy.path);
      try {
        final rows = raw.select(
          "SELECT value FROM settings WHERE name = 'marker'",
        );
        return rows.isEmpty ? null : rows.single['value'] as String;
      } on SqliteException {
        return null; // the table is still only in the log
      } finally {
        raw.close();
      }
    }

    expect(
      markerInMainFile('before'),
      isNull,
      reason: 'the write is in the log',
    );

    final lifecycle = AppLifecycle(
      db: db,
      platform: SyncPlatform(),
      replan: ReplanScheduler(replan: () async => null),
    );
    await lifecycle.onPause();

    expect(markerInMainFile('after'), 'kept');
  });
}
