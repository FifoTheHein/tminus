import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/features/common/alert_chips.dart';
import 'package:tminus/features/common/alert_list_editor.dart';
import 'package:tminus/features/common/color_palette_picker.dart';
import 'package:tminus/features/common/guarded.dart';
import 'package:tminus/features/common/ids.dart';
import 'package:tminus/features/common/profile_radio_list.dart';

Widget _host(Widget child) => MaterialApp(
  theme: TMinusTheme.dark(),
  home: Scaffold(body: child),
);

void main() {
  test('offsets read with a real minus sign', () {
    expect(offsetText(10), '−10');
    expect(offsetText(0), '0');
  });

  testWidgets('a heads-up is an outline chip and an alarm a solid one', (
    t,
  ) async {
    await t.pumpWidget(
      _host(
        const AlertChips([
          AlertSpec(10, AlertStrength.headsUp),
          AlertSpec(1, AlertStrength.alarm),
        ]),
      ),
    );
    expect(find.byKey(const Key('headsUpChip')), findsOneWidget);
    expect(find.byKey(const Key('alarmChip')), findsOneWidget);
    expect(find.text('−10'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);

    // Each chip is the one for its own alert, and its look follows the strength.
    expect(
      find.descendant(
        of: find.byKey(const Key('headsUpChip')),
        matching: find.text('−10'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('alarmChip')),
        matching: find.text('−1'),
      ),
      findsOneWidget,
    );
    BoxDecoration lookOf(String chipKey) =>
        t.widget<Container>(find.byKey(Key(chipKey))).decoration!
            as BoxDecoration;
    final colors = TMinusColors.dark; // the host's theme is TMinusTheme.dark()
    // Solid: filled with the alarm colour, no outline.
    final alarm = lookOf('alarmChip');
    expect(alarm.color, colors.alarmChipBg);
    expect(alarm.border, isNull);
    // Outline: a border in the heads-up colour, no fill.
    final headsUp = lookOf('headsUpChip');
    expect(headsUp.color, isNull);
    expect(
      headsUp.border,
      isA<Border>().having(
        (b) => b.top.color,
        'colour',
        colors.headsUpChipBorder,
      ),
    );
  });

  testWidgets('the palette reports the tapped colour', (t) async {
    int? picked;
    await t.pumpWidget(
      _host(
        ColorPalettePicker(
          selected: calendarPalette.first,
          onChanged: (c) => picked = c,
        ),
      ),
    );
    await t.tap(find.byKey(ValueKey('colour-${calendarPalette[2]}')));
    expect(picked, calendarPalette[2]);
  });

  test('the palette is the dark theme\'s six calendar colours', () {
    expect(calendarPalette, [
      for (final c in TMinusColors.dark.calendarColors) c.toARGB32(),
    ]);
  });

  testWidgets(
    'the profile list marks the selection and shows No alerts for Silent',
    (t) async {
      String? picked;
      await t.pumpWidget(
        _host(
          ProfileRadioList(
            profiles: BuiltInProfiles.all,
            selectedId: 'meeting',
            onSelected: (id) => picked = id,
          ),
        ),
      );
      expect(find.text('No alerts'), findsOneWidget);

      // The chosen row is marked with a filled radio and the container fill,
      // and no other row is.
      Finder inRow(String id, Finder what) => find.descendant(
        of: find.byKey(ValueKey('profile-$id')),
        matching: what,
      );
      expect(
        inRow('meeting', find.byIcon(Icons.radio_button_checked)),
        findsOneWidget,
      );
      expect(
        inRow('quick', find.byIcon(Icons.radio_button_unchecked)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      Color? fillOf(String id) {
        final ink = t.widget<Ink>(inRow(id, find.byType(Ink)));
        return (ink.decoration! as BoxDecoration).color;
      }

      final scheme = Theme.of(
        t.element(find.byKey(const ValueKey('profile-meeting'))),
      ).colorScheme;
      expect(fillOf('meeting'), scheme.secondaryContainer);
      expect(fillOf('quick'), isNull);

      await t.tap(find.text('Quick'));
      expect(picked, 'quick');
    },
  );

  testWidgets('the alert list editor adds, edits and removes rows', (t) async {
    var alerts = const [AlertSpec(10, AlertStrength.headsUp)];
    await t.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (c, set) => AlertListEditor(
            alerts: alerts,
            onChanged: (a) => set(() => alerts = a),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('addAlert')));
    await t.pump();
    expect(alerts, hasLength(2));
    await t.tap(find.byKey(const ValueKey('alert-1-strength-alarm')));
    await t.tap(find.byKey(const ValueKey('alert-1-offset-2')));
    await t.pump();
    expect(alerts[1], const AlertSpec(2, AlertStrength.alarm));
    await t.tap(find.byKey(const ValueKey('alert-0-remove')));
    await t.pump();
    expect(alerts, [const AlertSpec(2, AlertStrength.alarm)]);
  });

  test('ids are a prefix and 12 hex digits', () {
    expect(newId('p', Random(1)), matches(RegExp(r'^p-[0-9a-f]{12}$')));
  });

  testWidgets('a failing action shows the fixed text, never the error', (
    t,
  ) async {
    late BuildContext ctx;
    await t.pumpWidget(
      _host(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // Catch what the action logs. debugPrint goes back as soon as the call
    // returns, because testWidgets checks it when the test body ends.
    final logged = <String>[];
    final realDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    final int? r;
    try {
      r = await guarded<int>(
        ctx,
        () async => throw StateError('https://secret.example/calendar.ics'),
        failure: 'Could not save.',
      );
    } finally {
      debugPrint = realDebugPrint;
    }
    await t.pump();
    expect(r, isNull);
    expect(find.text('Could not save.'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    // The log names the error's type and nothing of its message.
    expect(logged, ['Could not save. (StateError)']);
  });
}
