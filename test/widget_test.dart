import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/app.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';

import 'design_system_fixture.dart';

void main() {
  setUp(configureDependencies);
  tearDown(getIt.reset);

  Brightness brightnessOf(WidgetTester tester) =>
      Theme.of(tester.element(find.text('Design tokens'))).brightness;

  Color alarmChipFill(WidgetTester tester) {
    final chip = tester.widget<Container>(find.byKey(const Key('alarmChip')));
    return (chip.decoration! as BoxDecoration).color!;
  }

  testWidgets('home shows the token preview with a sample event card', (
    tester,
  ) async {
    await tester.pumpWidget(const TMinusApp());
    await tester.pumpAndSettle();

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
  });

  testWidgets('theme mode switches between System, Dark and Light', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const TMinusApp());
    await tester.pumpAndSettle();
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
  });
}
