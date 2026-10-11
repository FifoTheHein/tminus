import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sources/fast_alarms.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/token_preview/sync_debug_panel.dart';

import '../../core/storage/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engine = MethodChannel(AlarmEngine.methodChannelName);
  const sync = MethodChannel(SyncPlatform.channelName);
  final syncCalls = <MethodCall>[];
  late List<Map<Object?, Object?>> applied;
  late Directory feeds;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    configureDependencies(openDatabase: openTestDatabase);
    // path_provider has no platform side in widget tests.
    feeds = Directory.systemTemp.createTempSync('feeds');
    await getIt.unregister<FeedBodyCache>();
    getIt.registerSingleton(FeedBodyCache(() async => feeds));
    applied = [];
    messenger.setMockMethodCallHandler(engine, (call) async {
      switch (call.method) {
        case 'applyPlan':
          applied = ((call.arguments as Map)['alerts'] as List)
              .cast<Map<Object?, Object?>>();
          return {'armed': applied.length, 'cancelled': 0, 'kept': 0};
        case 'drainEvents':
          return <Object?>[];
        case 'queryDeviceCalendars':
          return [
            {
              'id': '3',
              'name': 'Work',
              'accountName': null,
              'color': 0xFF33AA66,
              'visible': true,
            },
          ];
        case 'queryInstances':
          return <Object?>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(sync, (call) async {
      syncCalls.add(call);
      return switch (call.method) {
        'acquireLock' => true,
        'deviceZone' => 'UTC',
        _ => null,
      };
    });
  });

  tearDown(() async {
    syncCalls.clear();
    messenger.setMockMethodCallHandler(engine, null);
    messenger.setMockMethodCallHandler(sync, null);
    await getIt.reset();
    feeds.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TMinusTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(child: SyncDebugPanel()),
        ),
      ),
    );
  }

  /// Taps [label] and lets the work behind it finish, until the panel's
  /// buttons are enabled again. The feed folder is real file I/O, which the
  /// test's fake clock never completes by itself, so each wait is a real delay
  /// followed by a pump that carries the fake clock's microtasks on. Fails if
  /// the panel is still busy after 10 s.
  Future<void> tapAndWait(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
    final waited = Stopwatch()..start();
    while (true) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final syncNow = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sync now'),
      );
      if (syncNow.onPressed != null) break;
      if (waited.elapsed >= const Duration(seconds: 10)) {
        fail('"$label" left the panel still busy after 10 s');
      }
    }
    await tester.pump();
  }

  testWidgets(
    'Fast alarms adds the debug source and syncs it into the engine',
    (tester) async {
      await pumpPanel(tester);
      await tapAndWait(tester, 'Fast alarms');

      // Meeting profile: heads-up and alarm for each of the three events.
      expect(applied, hasLength(6));
      expect(
        find.textContaining('Fast alarms added · 6 alerts planned'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(
          () => getIt<SourceRepository>().byId(FastAlarms.sourceId),
        ),
        isNotNull,
      );

      await tapAndWait(tester, 'Clear fast alarms');
      expect(applied, isEmpty);
      expect(
        find.textContaining('Fast alarms cleared · 0 alerts planned'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Background sync asks WorkManager for a headless run', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tapAndWait(tester, 'Background sync');
    expect(syncCalls.where((c) => c.method == 'requestSync').single.arguments, {
      'trigger': 'manual',
    });
    expect(
      find.text('Background sync queued (headless engine)'),
      findsOneWidget,
    );
  });

  testWidgets('a pasted link and the first phone calendar become sources', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.enterText(
      find.byKey(const Key('icsLinkField')),
      'calendar.html',
    );
    await tapAndWait(tester, 'Add feed');
    expect(find.textContaining('That is not a calendar link'), findsOneWidget);

    await tapAndWait(tester, 'Add phone calendar');
    expect(
      find.textContaining('Added Work · 0 alerts planned'),
      findsOneWidget,
    );

    await tapAndWait(tester, 'Remove all sources');
    expect(find.textContaining('Removed 1 sources'), findsOneWidget);
  });

  testWidgets('the ICS link field is a URL field with no autocorrect', (
    tester,
  ) async {
    await pumpPanel(tester);
    final field = tester.widget<TextField>(
      find.byKey(const Key('icsLinkField')),
    );
    expect(field.keyboardType, TextInputType.url);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.textInputAction, TextInputAction.done);
  });

  testWidgets('History counts the newest rows by type', (tester) async {
    await pumpPanel(tester);
    await tapAndWait(tester, 'History');
    expect(find.text('No alert history yet'), findsOneWidget);

    await tester.runAsync(() async {
      for (final (i, type) in [
        AlertEventType.fired,
        AlertEventType.missedSystem,
        AlertEventType.missedSystem,
      ].indexed) {
        await getIt<AlertHistoryRepository>().record(
          AlertHistoryEntry(
            type: type,
            alertId: 'a$i',
            occurrenceKey: 'k',
            startUtc: DateTime.utc(2026, 10, 6, 8),
            atUtc: DateTime.utc(2026, 10, 6, 7, 59, i),
          ),
        );
      }
    });
    await tapAndWait(tester, 'History');
    expect(
      find.text('Last 3 history rows: missedSystem 2, fired 1'),
      findsOneWidget,
    );
  });

  group('Merge duplicates', () {
    final mergeSwitch = find.byKey(const Key('mergeDuplicatesSwitch'));

    /// The `merge.enabled` row, read outside the test's fake async zone.
    Future<String?> storedSetting(WidgetTester tester) async {
      final stored = await tester.runAsync(
        () =>
            getIt<SettingsRepository>().getString(SyncService.mergeEnabledKey),
      );
      return stored;
    }

    testWidgets('writes merge.enabled and syncs', (tester) async {
      await pumpPanel(tester);
      expect(tester.widget<SwitchListTile>(mergeSwitch).value, isTrue);

      await tapAndWait(tester, 'Merge duplicates');
      expect(await storedSetting(tester), 'false');
      expect(tester.widget<SwitchListTile>(mergeSwitch).value, isFalse);
      expect(
        find.textContaining('Merge duplicates off · 0 alerts planned'),
        findsOneWidget,
      );

      await tapAndWait(tester, 'Merge duplicates');
      expect(await storedSetting(tester), 'true');
      expect(tester.widget<SwitchListTile>(mergeSwitch).value, isTrue);
      expect(
        find.textContaining('Merge duplicates on · 0 alerts planned'),
        findsOneWidget,
      );
    });

    testWidgets('shows the stored setting after any action', (tester) async {
      await pumpPanel(tester);
      await tapAndWait(tester, 'History');
      expect(tester.widget<SwitchListTile>(mergeSwitch).value, isTrue);

      await tester.runAsync(
        () => getIt<SettingsRepository>().setString(
          SyncService.mergeEnabledKey,
          'false',
        ),
      );
      await tapAndWait(tester, 'History');
      expect(tester.widget<SwitchListTile>(mergeSwitch).value, isFalse);
    });
  });

  test('describe shows how many meetings were merged', () {
    expect(
      SyncDebugPanel.describe(
        const SyncReport(
          trigger: SyncTrigger.debug,
          outcome: SyncRunOutcome.ok,
          applied: ApplyResult(armed: 2, cancelled: 0, kept: 0),
          planned: 2,
          merged: 3,
        ),
      ),
      '2 alerts planned · armed 2, kept 0, cancelled 0 · merged 3',
    );
    expect(
      SyncDebugPanel.describe(
        const SyncReport(
          trigger: SyncTrigger.debug,
          outcome: SyncRunOutcome.ok,
          applied: ApplyResult(armed: 2, cancelled: 0, kept: 0),
          planned: 2,
        ),
      ),
      '2 alerts planned · armed 2, kept 0, cancelled 0',
    );
  });

  test('describe sums up a run in one line', () {
    expect(
      SyncDebugPanel.describe(
        const SyncReport(
          trigger: SyncTrigger.debug,
          outcome: SyncRunOutcome.busy,
        ),
      ),
      'Another sync is running',
    );
    expect(
      SyncDebugPanel.describe(
        const SyncReport(
          trigger: SyncTrigger.debug,
          outcome: SyncRunOutcome.retry,
          sources: [SourceSyncResult('work', SyncOutcome.networkError)],
          applied: ApplyResult(armed: 2, cancelled: 1, kept: 3),
          planned: 5,
          missedSystem: 1,
        ),
      ),
      '5 alerts planned · armed 2, kept 3, cancelled 1 · 1 missed (system) · work: networkError',
    );
  });
}
