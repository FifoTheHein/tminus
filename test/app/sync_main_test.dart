import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/app/di.dart';
import 'package:tminus/app/sync_main.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';

import '../core/fixtures.dart';

/// `runHeadlessSync` closes its database when it finishes, and these tests read
/// the database afterwards. This one ignores that close; the test closes it.
class _KeptOpenDatabase extends AppDatabase {
  _KeptOpenDatabase()
    : super(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );

  @override
  Future<void> close() async {}

  Future<void> closeForReal() => super.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engineChannel = MethodChannel(AlarmEngine.methodChannelName);
  const syncChannel = MethodChannel(SyncPlatform.channelName);

  const ics = SourceConfig(
    id: 'ics-1',
    name: 'Work Outlook',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.ics-1',
  );

  late _KeptOpenDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;
  late AppSettings app;

  /// The install id the native side reports: this phone's.
  late String thisPhone;

  /// What the native side received, in order: `engine.applyPlan`,
  /// `sync.acquireLock`, and so on.
  late List<String> calls;

  /// The alerts of each `applyPlan`, and the outcome of each `finished`.
  late List<List<Object?>> plans;
  late List<Object?> reported;

  setUp(() {
    db = _KeptOpenDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    app = AppSettings(SettingsRepository(db));
    thisPhone = 'phone-B';
    calls = [];
    plans = [];
    reported = [];
    messenger.setMockMethodCallHandler(engineChannel, (c) async {
      calls.add('engine.${c.method}');
      switch (c.method) {
        case 'applyPlan':
          plans.add((c.arguments as Map)['alerts'] as List<Object?>);
          return {'armed': 0, 'cancelled': 0, 'kept': 0};
        case 'drainEvents':
          return <Object?>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(syncChannel, (c) async {
      calls.add('sync.${c.method}');
      switch (c.method) {
        case 'installId':
          return thisPhone;
        case 'acquireLock':
          return true;
        case 'deviceZone':
          return 'UTC';
        case 'finished':
          reported.add((c.arguments as Map)['outcome']);
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(engineChannel, null);
    messenger.setMockMethodCallHandler(syncChannel, null);
    tz.setLocalLocation(tz.UTC);
    await db.closeForReal();
  });

  /// A database that came from a backup made on another phone: it holds that
  /// phone's install id, one enabled feed and a meeting of the feed in the
  /// cache.
  Future<void> seedBackupFromAnotherPhone() async {
    await app.setInstallId('phone-A');
    await app.setOnboardingDone(true);
    await sources.save(ics);
    await cache.replaceForSource('ics-1', [
      occ(
        sourceId: 'ics-1',
        uid: 'standup',
        start: DateTime.now().toUtc().add(const Duration(days: 1)),
      ),
    ]);
  }

  Future<int> cachedMeetings() async =>
      (await cache.between(DateTime.utc(2000), DateTime.utc(2100))).length;

  test(
    'a headless run after a restore disables the sources before it syncs',
    () async {
      await seedBackupFromAnotherPhone();

      await runHeadlessSync(['periodic'], openDatabase: () => db);

      // The restore was made safe first: the feed is off and asks for its link,
      // and the old phone's meetings are gone.
      expect((await sources.byId('ics-1'))!.enabled, isFalse);
      expect(await app.sourceSetup('ics-1'), SourceSetup.needsLink);
      expect(await app.installId(), 'phone-B');
      expect(await cachedMeetings(), 0);
      // So the sync that followed had nothing to fetch or arm, and posted no
      // Feed broken notice for the feed it could not read.
      expect(plans, hasLength(1));
      expect(plans.single, isEmpty);
      expect(calls, isNot(contains('sync.postSourceNotice')));
      expect(reported, ['ok']);
      // And it came first: the install id is read before the lock is taken.
      expect(calls, contains('sync.installId'));
      expect(calls, contains('sync.acquireLock'));
      expect(
        calls.indexOf('sync.installId'),
        lessThan(calls.indexOf('sync.acquireLock')),
      );
    },
  );

  // Beyond the plan's list.

  test('a restore that cannot be made safe skips the sync and asks for a '
      'retry', () async {
    await seedBackupFromAnotherPhone();
    // The last write of the restore fails, as in a locked or full database.
    await db.customStatement(
      'CREATE TRIGGER no_install_id BEFORE INSERT ON settings '
      "WHEN NEW.name = '${AppSettings.installIdKey}' "
      "BEGIN SELECT RAISE(ABORT, 'no'); END",
    );

    await runHeadlessSync(['periodic'], openDatabase: () => db);

    // Nothing was planned or armed from the backup's data, and WorkManager is
    // asked to try again.
    expect(calls.where((c) => c.startsWith('engine.')), isEmpty);
    expect(calls, isNot(contains('sync.acquireLock')));
    expect(reported, ['retry']);
    // The restore was rolled back whole, so the next start finds it again.
    expect((await sources.byId('ics-1'))!.enabled, isTrue);
    expect(await app.installId(), 'phone-A');
    expect(await cachedMeetings(), 1);
  });

  test(
    'a run on the phone the database was written on syncs as before',
    () async {
      await app.setInstallId(thisPhone);

      await runHeadlessSync(['manual'], openDatabase: () => db);

      expect(calls, contains('sync.acquireLock'));
      expect(plans, hasLength(1));
      expect(reported, ['ok']);
    },
  );

  test('a run that throws reports retry once and cleans up', () async {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);

    // The database cannot be opened. The message names a link on purpose: a
    // failure must only ever be logged by its type.
    await runHeadlessSync(
      ['periodic'],
      openDatabase: () =>
          throw StateError('no open for https://calendar.example/s3cr3t.ics'),
    );

    // WorkManager is told once, so the worker never waits for its timeout, and
    // asked to try again.
    expect(reported, ['retry']);
    expect(calls.where((c) => c == 'sync.finished'), hasLength(1));
    // Nothing was locked, planned or armed, and the services are gone, so the
    // next run in this engine starts clean.
    expect(calls, isNot(contains('sync.acquireLock')));
    expect(calls.where((c) => c.startsWith('engine.')), isEmpty);
    expect(getIt.isRegistered<AppDatabase>(), isFalse);
    expect(logged.join('\n'), contains('StateError'));
    expect(logged.join('\n'), isNot(contains('s3cr3t')));
  });
}
