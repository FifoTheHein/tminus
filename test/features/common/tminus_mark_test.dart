import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/features/agenda/agenda_widgets.dart';
import 'package:tminus/features/common/tminus_mark.dart';

import '../harness.dart';

void main() {
  testWidgets('the mark is a CustomPaint of the size it is given', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        // Centred, because the body of a Scaffold is tight and would stretch it.
        home: Scaffold(body: Center(child: TMinusMark(size: 32))),
      ),
    );

    final mark = find.byType(TMinusMark);
    expect(t.getSize(mark), const Size(32, 32));
    final paint = find.descendant(of: mark, matching: find.byType(CustomPaint));
    expect(paint, findsOneWidget);
    expect(t.widget<CustomPaint>(paint).painter, isNotNull);
  });

  testWidgets('the Agenda app bar draws the mark, 22 dp across', (t) async {
    final h = await pumpApp(t);

    final mark = find.descendant(
      of: find.byType(AgendaLogo),
      matching: find.byType(TMinusMark),
    );
    expect(mark, findsOneWidget);
    expect(t.getSize(mark), const Size(22, 22));
    await h.dispose(t);
  });

  testWidgets('the Welcome step draws the mark, 96 dp across', (t) async {
    final h = await pumpApp(t, onboarded: false);

    final mark = find.descendant(
      of: find.byKey(const Key('step-welcome')),
      matching: find.byType(TMinusMark),
    );
    expect(mark, findsOneWidget);
    expect(t.getSize(mark), const Size(96, 96));
    await h.dispose(t);
  });

  testWidgets('the About card in Settings draws the mark, 32 dp across', (
    t,
  ) async {
    // Tall enough for the whole page, so that the About card is built.
    t.view.physicalSize = const Size(2400, 4800);
    addTearDown(t.view.resetPhysicalSize);
    final h = await pumpApp(t, location: '/settings');

    final mark = find.byType(TMinusMark);
    expect(mark, findsOneWidget);
    expect(t.getSize(mark), const Size(32, 32));
    await h.dispose(t);
  });
}
