import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/app.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/health_monitor.dart';
import 'package:tminus/app/onboarding_gate.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/features/agenda/agenda_screen.dart';
import 'package:tminus/features/health/health_report.dart';

import 'core/storage/test_database.dart';
import 'design_system_fixture.dart';
import 'features/harness.dart';

/// A monitor whose report is set by the test, and which never reads the engine
/// or starts a timer.
class _FixedHealthMonitor extends HealthMonitor {
  _FixedHealthMonitor(this._fixed) : super(engine: getIt(), statuses: getIt());

  HealthReport? _fixed;

  @override
  HealthReport? get report => _fixed;

  void show(HealthReport? report) {
    _fixed = report;
    notifyListeners();
  }
}

HealthReport _report(HealthLevel level) => HealthReport(
  items: [
    HealthItem(
      id: 'notifications',
      title: 'Notifications',
      detail: 'Notifications are off',
      level: level,
    ),
  ],
  overall: level,
  headline: 'Alarms may not ring',
  summary: '1 problem. Fix it below.',
);

void main() {
  Brightness brightnessOf(WidgetTester tester) =>
      Theme.of(tester.element(find.text('Design tokens'))).brightness;

  Color alarmChipFill(WidgetTester tester) {
    final chip = tester.widget<Container>(find.byKey(const Key('alarmChip')));
    return (chip.decoration! as BoxDecoration).color!;
  }

  // The token preview is no longer the home screen: it is Settings →
  // Developer tools, and these tests open it there.
  testWidgets(
    'the developer tools show the token preview with a sample event card',
    (tester) async {
      final h = await pumpApp(tester, location: '/settings/developer');

      expect(find.text('Design tokens'), findsOneWidget);
      expect(find.text('primary'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('calendarBlue'), 300);
      expect(find.text('calendarBlue'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('sampleEventCard')),
        300,
      );
      expect(find.byKey(const Key('headsUpChip')), findsOneWidget);
      expect(find.byKey(const Key('alarmChip')), findsOneWidget);
      await h.dispose(tester);
    },
  );

  testWidgets('theme mode switches between System, Dark and Light', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final h = await pumpApp(tester, location: '/settings/developer');
    expect(brightnessOf(tester), Brightness.light); // System follows platform

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);
    expect(
      Theme.of(tester.element(find.text('Design tokens'))).colorScheme.primary,
      designSystemColors['primary']!.dark,
    );
    await tester.scrollUntilVisible(find.byKey(const Key('alarmChip')), 300);
    expect(alarmChipFill(tester), designSystemColors['alarmChipBg']!.dark);

    await tester.scrollUntilVisible(find.text('Light'), -300);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);
    await tester.scrollUntilVisible(find.byKey(const Key('alarmChip')), 300);
    expect(alarmChipFill(tester), designSystemColors['alarmChipBg']!.light);
    expect(
      Theme.of(tester.element(find.byKey(const Key('alarmChip'))))
          .extension<TMinusColors>()!
          .alarmChipFg,
      designSystemColors['alarmChipFg']!.light,
    );
    await h.dispose(tester);
  });

  testWidgets(
    'the Health tab shows a red dot when the monitor reports a problem',
    (tester) async {
      final h = await pumpApp(
        tester,
        seed: (h) async {
          await getIt.unregister<HealthMonitor>();
          getIt.registerSingleton<HealthMonitor>(
            _FixedHealthMonitor(_report(HealthLevel.problem)),
            dispose: (m) => m.dispose(),
          );
        },
      );

      final dot = find.byKey(const Key('healthDot'));
      expect(dot, findsOneWidget);
      final colors = Theme.of(tester.element(dot)).extension<TMinusColors>()!;
      expect(tester.widget<Badge>(dot).backgroundColor, colors.statusError);
      await h.dispose(tester);
    },
  );

  // Beyond the plan's list.

  testWidgets('the Health dot is green, amber or red with the report, and '
      'absent without one', (tester) async {
    late _FixedHealthMonitor monitor;
    final h = await pumpApp(
      tester,
      seed: (h) async {
        await getIt.unregister<HealthMonitor>();
        monitor = _FixedHealthMonitor(null);
        getIt.registerSingleton<HealthMonitor>(
          monitor,
          dispose: (m) => m.dispose(),
        );
      },
    );
    final dot = find.byKey(const Key('healthDot'));
    expect(dot, findsNothing);

    monitor.show(_report(HealthLevel.ok));
    await tester.pump();
    final colors = Theme.of(tester.element(dot)).extension<TMinusColors>()!;
    expect(tester.widget<Badge>(dot).backgroundColor, colors.statusOk);

    monitor.show(_report(HealthLevel.warning));
    await tester.pump();
    expect(tester.widget<Badge>(dot).backgroundColor, colors.statusWarn);

    monitor.show(_report(HealthLevel.problem));
    await tester.pump();
    expect(tester.widget<Badge>(dot).backgroundColor, colors.statusError);

    monitor.show(null);
    await tester.pump();
    expect(dot, findsNothing);
    await h.dispose(tester);
  });

  // The harness always hands the app its own router. This is the path `main`
  // takes: the app builds its router from the registered gate.
  testWidgets('the app without a given router uses the registered gate', (
    tester,
  ) async {
    configureDependencies(openDatabase: openTestDatabase);
    addTearDown(getIt.reset);
    await getIt<AppSettings>().setOnboardingDone(true);
    await getIt<OnboardingGate>().load();

    await tester.pumpWidget(const TMinusApp());
    await tester.pumpAndSettle();

    expect(find.byType(AgendaScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // Off the screen before the reset: the app disposes the router it built,
    // and that router listens to the gate the reset disposes.
    await tester.pumpWidget(const SizedBox());
  });
}
