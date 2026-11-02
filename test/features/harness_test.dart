import 'package:flutter/material.dart'
    show Brightness, MaterialApp, NavigationBar, SizedBox, Theme, ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/app/di.dart';
import 'package:tminus/app/replan_scheduler.dart';
import 'package:tminus/app/sync_runner.dart';
import 'package:tminus/app/theme_mode_controller.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/platform/ui_platform.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/sources/ics_link_probe.dart';
import 'package:tminus/core/sources/source_admin.dart';
import 'package:tminus/core/sources/source_secrets.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/agenda/agenda_model.dart';
import 'package:tminus/features/agenda/agenda_screen.dart';
import 'package:tminus/features/onboarding/onboarding_screen.dart';

import '../core/fixtures.dart' show blue;
import 'harness.dart';

/// A theme controller that notes whether anything was listening to it at the
/// moment its mode changed. The app listens as soon as it is built, so "nobody
/// was" means the mode changed before the first frame.
class _WatchedTheme extends ThemeModeController {
  _WatchedTheme() : super(settings: () => getIt<SettingsRepository>());

  /// Null until the mode has changed.
  bool? listenedToWhenChanged;

  @override
  void notifyListeners() {
    listenedToWhenChanged = hasListeners;
    super.notifyListeners();
  }
}

/// One event the day after the harness's default clock. It is in the past by
/// the time anyone runs the tests, so a probe on the real clock counts none.
const _feed = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:soon
DTSTART:20261007T080000Z
DTEND:20261007T083000Z
SUMMARY:Standup
END:VEVENT
END:VCALENDAR
''';

void main() {
  testWidgets(
    'the harness boots onboarded on the Agenda and records a pull-to-refresh sync',
    (t) async {
      final h = await pumpApp(t);
      expect(find.byType(AgendaScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      await getIt<SyncRunner>()(SyncTrigger.pullToRefresh);
      expect(h.syncs, [SyncTrigger.pullToRefresh]);
      await h.dispose(t);
    },
  );

  // Beyond the plan's list: each pins one thing that the screen tests of the
  // later waves rely on.

  testWidgets('the harness boots before onboarding when asked to', (t) async {
    final h = await pumpApp(t, onboarded: false);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(AgendaScreen), findsNothing);
    await h.dispose(t);
  });

  testWidgets(
    'the harness answers the platform channels and records the calls',
    (t) async {
      final h = await pumpApp(t);

      // tminus_ui: defaults, then an answer a test sets.
      expect((await getIt<UiPlatform>().deviceInfo()).manufacturer, 'Google');
      h.ui['deviceInfo'] = (_) => {
        'versionName': '2.0.0',
        'versionCode': 2,
        'manufacturer': 'samsung',
        'sdkInt': 34,
      };
      expect((await getIt<UiPlatform>().deviceInfo()).manufacturer, 'samsung');
      expect(h.uiCalls.map((c) => c.method), ['deviceInfo', 'deviceInfo']);

      // alarm_engine: a healthy engine, then the health a test sets.
      expect(
        (await getIt<AlarmEngine>().getHealth()).notificationsEnabled,
        true,
      );
      h.health = {...healthyEngine(), 'notificationsEnabled': false};
      expect(
        (await getIt<AlarmEngine>().getHealth()).notificationsEnabled,
        false,
      );
      expect(h.engineCalls.map((c) => c.method), ['getHealth', 'getHealth']);

      // tminus_sync: this install's id and an always free lock.
      expect(await getIt<SyncPlatform>().installId(), 'test-install');
      expect(
        await getIt<SyncPlatform>().acquireLock(
          'owner',
          const Duration(hours: 1),
        ),
        isTrue,
      );
      expect(h.syncCalls.map((c) => c.method), ['installId', 'acquireLock']);

      // flutter_secure_storage: a map, so no link reaches a real store.
      final secrets = getIt<SourceSecrets>();
      await secrets.writeUrl('key', 'https://example.test/c.ics');
      expect(h.secrets, {'key': 'https://example.test/c.ics'});
      expect(await secrets.readUrl('key'), 'https://example.test/c.ics');
      await secrets.delete('key');
      expect(h.secrets, isEmpty);
      expect(await secrets.readUrl('key'), isNull);
      await h.dispose(t);
    },
  );

  testWidgets('the harness fixes the clock and the zone and counts re-plans', (
    t,
  ) async {
    final h = await pumpApp(t, now: DateTime.utc(2026, 10, 6, 7, 27));
    expect(tz.local.name, 'Africa/Johannesburg');
    expect(getIt<RulesEngine>().zone.name, 'Africa/Johannesburg');
    expect(getIt<RulesEngine>().clock(), DateTime.utc(2026, 10, 6, 7, 27));
    // The screens' loaders read the same clock, and the Agenda the same zone.
    expect(
      getIt<SourceStatusLoader>().clock(),
      DateTime.utc(2026, 10, 6, 7, 27),
    );
    expect(getIt<AgendaLoader>().clock(), DateTime.utc(2026, 10, 6, 7, 27));
    expect(getIt<AgendaLoader>().zone().name, 'Africa/Johannesburg');
    h.now = DateTime.utc(2026, 10, 6, 9);
    expect(getIt<RulesEngine>().clock(), DateTime.utc(2026, 10, 6, 9));
    expect(getIt<SourceStatusLoader>().clock(), DateTime.utc(2026, 10, 6, 9));
    expect(getIt<AgendaLoader>().clock(), DateTime.utc(2026, 10, 6, 9));

    // The scheduler is the harness's: it counts a request instead of syncing.
    expect(h.replans, 0);
    getIt<ReplanScheduler>().request();
    await t.pump(const Duration(milliseconds: 1));
    expect(h.replans, 1);
    expect(h.syncs, isEmpty);

    // The zone goes back to UTC (the time-zone package's `UTC`, named
    // `Etc/UTC` in the version this app uses), whatever it was before.
    await h.dispose(t);
    expect(tz.local.name, tz.UTC.name);
    expect(getIt.isRegistered<AppDatabase>(), isFalse);
  });

  testWidgets('the harness checks links against the feeds it is given', (
    t,
  ) async {
    final h = await pumpApp(
      t,
      now: DateTime.utc(2026, 10, 6, 7, 27),
      feeds: MockClient((_) async => http.Response(_feed, 200)),
    );
    // Counted from the harness's clock, not the real one.
    final result = await getIt<IcsLinkProbe>().check(
      'https://example.test/c.ics',
    );
    expect(result, isA<ProbeFound>());
    expect((result as ProbeFound).eventsThisWeek, 1);
    await h.dispose(t);
  });

  testWidgets('the harness re-links a source without a platform directory', (
    t,
  ) async {
    final h = await pumpApp(
      t,
      seed: (h) => getIt<SourceRepository>().save(
        const SourceConfig(
          id: 'ics-1',
          name: 'Work Outlook',
          color: blue,
          kind: SourceKind.ics,
          secureStorageKey: 'ics-url.ics-1',
        ),
      ),
    );
    h.secrets['ics-url.ics-1'] = 'https://old.example/o.ics';
    h.feedBodies['ics-1'] = 'BEGIN:VCALENDAR';

    // A re-link ends by deleting the source's stored feed body. The real cache
    // looks its directory up through path_provider, which has no platform side
    // here: the delete would throw a MissingPluginException.
    final insecure = await getIt<SourceAdmin>().updateIcsUrl(
      'ics-1',
      'https://example.test/n.ics',
    );

    expect(insecure, isFalse);
    expect(h.secrets['ics-url.ics-1'], 'https://example.test/n.ics');
    expect(h.feedBodies, isEmpty);
    await h.dispose(t);
  });

  testWidgets('the harness loads the stored theme before the first frame', (
    t,
  ) async {
    final theme = _WatchedTheme();
    final h = await pumpApp(
      t,
      seed: (h) async {
        await getIt.unregister<ThemeModeController>();
        getIt.registerSingleton<ThemeModeController>(theme);
        await getIt<SettingsRepository>().setString(
          ThemeModeController.settingsKey,
          'dark',
        );
      },
    );

    // The stored choice reached the controller while nothing listened to it,
    // which is before the app was built.
    expect(theme.listenedToWhenChanged, isFalse);
    expect(theme.mode, ThemeMode.dark);
    expect(
      t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      Theme.of(t.element(find.byType(AgendaScreen))).brightness,
      Brightness.dark,
    );
    await h.dispose(t);
  });

  testWidgets('the harness boots again over a test that left the services '
      'registered', (t) async {
    // What a test that failed before its dispose leaves behind: the services
    // stay registered while the framework takes the app off the screen.
    final first = await pumpApp(t);
    await t.pumpWidget(const SizedBox());
    first.router.dispose();

    final h = await pumpApp(t);

    expect(find.byType(AgendaScreen), findsOneWidget);
    expect(h.db, isNot(same(first.db)));
    await h.dispose(t);
  });
}
