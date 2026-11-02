import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/onboarding_gate.dart';
import 'package:tminus/app/router.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/features/agenda/agenda_screen.dart';
import 'package:tminus/features/alerts/alerts_screen.dart';
import 'package:tminus/features/alerts/profile_editor_screen.dart';
import 'package:tminus/features/health/health_screen.dart';
import 'package:tminus/features/onboarding/onboarding_screen.dart';
import 'package:tminus/features/settings/settings_screen.dart';
import 'package:tminus/features/sources/add_source_screen.dart';
import 'package:tminus/features/sources/source_detail_screen.dart';
import 'package:tminus/features/sources/sources_screen.dart';

import '../core/storage/test_database.dart';

void main() {
  late GoRouter router;
  late OnboardingGate gate;

  Future<void> boot(
    WidgetTester t, {
    required bool onboarded,
    bool debugTools = true,
  }) async {
    configureDependencies(openDatabase: openTestDatabase);
    await getIt<AppSettings>().setOnboardingDone(onboarded);
    gate = OnboardingGate(getIt<AppSettings>());
    await gate.load();
    router = createRouter(gate: gate, debugTools: debugTools);
    await t.pumpWidget(
      MaterialApp.router(theme: TMinusTheme.dark(), routerConfig: router),
    );
    await t.pumpAndSettle();
  }

  /// The bottom bar's tab, not a screen title that reads the same.
  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  tearDown(() async {
    router.dispose();
    // The gate watches the database: stop it before the database closes.
    gate.dispose();
    await getIt.reset();
  });

  testWidgets('before onboarding every route goes to onboarding', (t) async {
    await boot(t, onboarded: false);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    router.go('/sources/ics-1');
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('after onboarding the app opens on the Agenda', (t) async {
    await boot(t, onboarded: true);
    expect(find.byType(AgendaScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a pushed source route opens that source', (t) async {
    await boot(t, onboarded: true);
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('pushRouteInformation', {
          'location': '/sources/ics-1',
          'state': null,
        }),
      ),
      (_) {},
    );
    await t.pumpAndSettle();
    final detail = t.widget<SourceDetailScreen>(
      find.byType(SourceDetailScreen),
    );
    expect(detail.sourceId, 'ics-1');
  });

  testWidgets('the platform initial route opens that source', (t) async {
    t.binding.platformDispatcher.defaultRouteNameTestValue = '/sources/ics-1';
    addTearDown(t.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    await boot(t, onboarded: true);
    expect(find.byType(SourceDetailScreen), findsOneWidget);
  });

  testWidgets('a route that is not a known route goes to the Agenda', (
    t,
  ) async {
    await boot(t, onboarded: true);
    router.go('/nope');
    await t.pumpAndSettle();
    expect(find.byType(AgendaScreen), findsOneWidget);
  });

  testWidgets('without debug tools the developer route goes to Settings', (
    t,
  ) async {
    await boot(t, onboarded: true, debugTools: false);
    router.go('/settings/developer');
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Design tokens'), findsNothing);
  });

  testWidgets('finishing onboarding moves to the Agenda', (t) async {
    await boot(t, onboarded: false);
    await getIt<AppSettings>().setOnboardingDone(true);
    await t.pumpAndSettle();
    expect(find.byType(AgendaScreen), findsOneWidget);
  });

  // Beyond the plan's list.

  testWidgets(
    'a restore finished while the app is open returns to onboarding',
    (t) async {
      await boot(t, onboarded: true);
      expect(find.byType(AgendaScreen), findsOneWidget);

      // What the restore guard does when it finishes a restore after the app
      // started: it clears the onboarding flag.
      await getIt<AppSettings>().setOnboardingDone(false);
      await t.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(AgendaScreen), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('a Fix route before onboarding is dropped, and stays dropped '
      'once onboarding is done', (t) async {
    t.binding.platformDispatcher.defaultRouteNameTestValue = '/sources/ics-1';
    addTearDown(t.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    await boot(t, onboarded: false);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(SourceDetailScreen), findsNothing);

    await getIt<AppSettings>().setOnboardingDone(true);
    await t.pumpAndSettle();

    // The Agenda, not the source the Fix action pointed at before onboarding.
    expect(find.byType(AgendaScreen), findsOneWidget);
    expect(find.byType(SourceDetailScreen), findsNothing);
  });

  testWidgets('a location the router does not know leaves the open screen for '
      'the Agenda', (t) async {
    await boot(t, onboarded: true);
    for (final unknown in [
      '/nope',
      '/health/extra',
      '/sources/ics-1/extra',
      '/Sources/ics-1',
    ]) {
      router.go('/health');
      await t.pumpAndSettle();
      expect(find.byType(HealthScreen), findsOneWidget, reason: unknown);

      router.go(unknown);
      await t.pumpAndSettle();
      expect(find.byType(AgendaScreen), findsOneWidget, reason: unknown);
      expect(find.byType(HealthScreen), findsNothing, reason: unknown);
    }
  });

  testWidgets('the root path goes to the Agenda', (t) async {
    await boot(t, onboarded: true);
    router.go('/health');
    await t.pumpAndSettle();
    router.go('/');
    await t.pumpAndSettle();
    expect(find.byType(AgendaScreen), findsOneWidget);
  });

  testWidgets('add is the Add source screen, never a source id', (t) async {
    await boot(t, onboarded: true);
    router.go('/sources/add');
    await t.pumpAndSettle();
    expect(find.byType(AddSourceScreen), findsOneWidget);
    expect(find.byType(SourceDetailScreen), findsNothing);
  });

  testWidgets('routes match case-sensitively, so New is a profile id', (
    t,
  ) async {
    await boot(t, onboarded: true);
    ProfileEditorScreen editor() =>
        t.widget<ProfileEditorScreen>(find.byType(ProfileEditorScreen));

    router.go('/alerts/profiles/new');
    await t.pumpAndSettle();
    expect(editor().profileId, isNull);

    router.go('/alerts/profiles/New');
    await t.pumpAndSettle();
    expect(editor().profileId, 'New');
  });

  testWidgets('a tab shows its screen, and its second tap goes back to its '
      'first screen', (t) async {
    await boot(t, onboarded: true);
    await t.tap(tab('Sources'));
    await t.pumpAndSettle();
    expect(find.byType(SourcesScreen), findsOneWidget);

    router.go('/sources/ics-1');
    await t.pumpAndSettle();
    expect(find.byType(SourceDetailScreen), findsOneWidget);

    // Another tab and back: the Sources tab is as it was left.
    await t.tap(tab('Agenda'));
    await t.pumpAndSettle();
    expect(find.byType(AgendaScreen), findsOneWidget);
    await t.tap(tab('Sources'));
    await t.pumpAndSettle();
    expect(find.byType(SourceDetailScreen), findsOneWidget);

    // The open tab again: back to its first screen.
    await t.tap(tab('Sources'));
    await t.pumpAndSettle();
    expect(find.byType(SourceDetailScreen), findsNothing);
    expect(find.byType(SourcesScreen), findsOneWidget);
  });

  testWidgets('the bar lists the four tabs in the brief order, and each opens '
      'its own screen', (t) async {
    await boot(t, onboarded: true);
    final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      [for (final d in bar.destinations) (d as NavigationDestination).label],
      ['Agenda', 'Alerts', 'Sources', 'Health'],
    );

    for (final (label, screen) in <(String, Type)>[
      ('Alerts', AlertsScreen),
      ('Sources', SourcesScreen),
      ('Health', HealthScreen),
      ('Agenda', AgendaScreen),
    ]) {
      await t.tap(tab(label));
      await t.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: label);
    }
  });
}
