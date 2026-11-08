import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/features/alerts/profile_editor_screen.dart';
import 'package:tminus/features/alerts/rule_editor_screen.dart';

import '../harness.dart';
import 'alerts_test_support.dart';

/// A settings store whose skip-filter writes fail.
class _FailingSettings extends SettingsRepository {
  _FailingSettings(super.db);

  @override
  Future<void> setSkipFilters(SkipFilters filters) =>
      throw StateError('the disk is full');
}

void main() {
  testWidgets(
    'the profiles tab lists the built-ins with their chips and marks the default',
    (t) async {
      useTallWindow(t);
      final h = await pumpApp(
        t,
        location: '/alerts',
        seed: (h) async {
          await getIt<ProfileRepository>().save(userProfile());
          final rules = getIt<RuleRepository>();
          await rules.save(keywordRule('r-000000000001', 0));
          await rules.save(keywordRule('r-000000000002', 1, pattern: 'sync'));
          await rules.save(
            keywordRule(
              'r-000000000003',
              2,
              pattern: 'client',
              profileId: 'important',
            ),
          );
        },
      );

      Finder row(String id) => find.byKey(Key('profileRow-$id'));
      Finder inRow(String id, Finder what) =>
          find.descendant(of: row(id), matching: what);
      int chips(String id, String key) =>
          t.widgetList(inRow(id, find.byKey(Key(key)))).length;

      // The built-ins in their order, then the user's own, each with its name.
      const rows = [
        ('meeting', 'Meeting'),
        ('quick', 'Quick'),
        ('important', 'Important'),
        ('silent', 'Silent'),
        (focusBlockId, 'Focus block'),
      ];
      for (final (id, name) in rows) {
        expect(inRow(id, find.text(name)), findsOneWidget, reason: id);
      }
      final tops = [for (final (id, _) in rows) t.getTopLeft(row(id)).dy];
      expect(tops, orderedEquals([...tops]..sort()));

      // Chips: Meeting −10 and −1, Quick −1, Important −30, −10 and −2.
      expect(chips('meeting', 'headsUpChip'), 1);
      expect(chips('meeting', 'alarmChip'), 1);
      expect(inRow('meeting', find.text('−10')), findsOneWidget);
      expect(inRow('meeting', find.text('−1')), findsOneWidget);
      expect(chips('quick', 'headsUpChip'), 0);
      expect(chips('quick', 'alarmChip'), 1);
      expect(chips('important', 'headsUpChip'), 2);
      expect(chips('important', 'alarmChip'), 1);
      expect(inRow('important', find.text('−30')), findsOneWidget);
      expect(inRow('important', find.text('−2')), findsOneWidget);
      expect(chips(focusBlockId, 'headsUpChip'), 1);
      expect(chips(focusBlockId, 'alarmChip'), 0);

      // Silent has no alerts to show.
      expect(inRow('silent', find.text('No alerts')), findsOneWidget);
      expect(find.text('No alerts'), findsOneWidget);
      expect(chips('silent', 'headsUpChip') + chips('silent', 'alarmChip'), 0);

      // What each profile is used for.
      expect(inRow('meeting', find.textContaining('Used by')), findsNothing);
      expect(inRow('quick', find.text('Used by 2 rules')), findsOneWidget);
      expect(
        inRow('important', find.text('Used by 1 rule · rings in quiet mode')),
        findsOneWidget,
      );
      expect(
        inRow('silent', find.text('Shown in Agenda only')),
        findsOneWidget,
      );
      expect(inRow(focusBlockId, find.text('Your profile')), findsOneWidget);

      // Meeting is the default until the user picks another one.
      expect(find.byKey(const Key('defaultBadge')), findsOneWidget);
      expect(
        inRow('meeting', find.byKey(const Key('defaultBadge'))),
        findsOneWidget,
      );
      await getIt<SettingsRepository>().setGlobalDefaultProfileId('important');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('defaultBadge')), findsOneWidget);
      expect(
        inRow('important', find.byKey(const Key('defaultBadge'))),
        findsOneWidget,
      );
      await h.dispose(t);
    },
  );

  // Beyond the plan's list: each pins one thing the screen promises.

  testWidgets('a tap on a profile opens that profile in the editor', (t) async {
    useTallWindow(t);
    final h = await pumpApp(t, location: '/alerts');

    await t.tap(find.byKey(const Key('profileRow-quick')));
    await t.pumpAndSettle();

    expect(
      t.widget<ProfileEditorScreen>(find.byType(ProfileEditorScreen)).profileId,
      'quick',
    );
    expect(
      t
          .widget<TextField>(find.byKey(const Key('profileName')))
          .controller!
          .text,
      'Quick',
    );
    await h.dispose(t);
  });

  testWidgets('a tap on a rule opens that rule in the editor', (t) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts',
      seed: (h) async {
        final rules = getIt<RuleRepository>();
        await rules.save(keywordRule('r-000000000001', 0));
        await rules.save(keywordRule('r-000000000002', 1, pattern: 'lunch'));
      },
    );
    await t.tap(find.text('Rules'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('rule-r-000000000002')));
    await t.pumpAndSettle();

    expect(
      t.widget<RuleEditorScreen>(find.byType(RuleEditorScreen)).ruleId,
      'r-000000000002',
    );
    expect(
      t
          .widget<TextField>(find.byKey(const Key('rulePattern')))
          .controller!
          .text,
      'lunch',
    );
    await h.dispose(t);
  });

  testWidgets('the floating button follows the tab', (t) async {
    useTallWindow(t);
    final h = await pumpApp(t, location: '/alerts');
    expect(find.byKey(const Key('newProfile')), findsOneWidget);
    expect(find.byKey(const Key('newRule')), findsNothing);

    await t.tap(find.text('Rules'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('newRule')), findsOneWidget);
    expect(find.byKey(const Key('newProfile')), findsNothing);

    await t.tap(find.byKey(const Key('newRule')));
    await t.pumpAndSettle();
    expect(
      t.widget<RuleEditorScreen>(find.byType(RuleEditorScreen)).ruleId,
      isNull,
    );
    await h.dispose(t);
  });

  testWidgets(
    'a skip filter switch writes the filters and asks for a re-plan',
    (t) async {
      useTallWindow(t);
      final h = await pumpApp(t, location: '/alerts');
      await t.tap(find.text('Rules'));
      await t.pumpAndSettle();

      const keys = [
        'skip-allDay',
        'skip-free',
        'skip-tentative',
        'skip-cancelled',
        'skip-declined',
      ];
      bool on(String key) =>
          t.widget<SwitchListTile>(find.byKey(Key(key))).value;
      for (final key in keys) {
        expect(on(key), isTrue, reason: key);
      }
      // Only Declined says it works for phone calendars alone.
      expect(find.text('Phone calendars only'), findsOneWidget);
      expect(h.replans, 0);

      await t.tap(find.byKey(const Key('skip-free')));
      await t.pumpAndSettle();

      expect(on('skip-free'), isFalse);
      expect(on('skip-allDay'), isTrue);
      expect(
        await getIt<SettingsRepository>().skipFilters(),
        const SkipFilters(free: false),
      );
      expect(h.replans, 1);

      await t.tap(find.byKey(const Key('skip-declined')));
      await t.pumpAndSettle();

      expect(
        await getIt<SettingsRepository>().skipFilters(),
        const SkipFilters(free: false, declined: false),
      );
      expect(h.replans, 2);
      await h.dispose(t);
    },
  );

  testWidgets(
    'a skip filter that cannot be saved says so in fixed words and goes back',
    (t) async {
      useTallWindow(t);
      final h = await pumpApp(
        t,
        location: '/alerts',
        seed: (h) async {
          await getIt.unregister<SettingsRepository>();
          getIt.registerSingleton<SettingsRepository>(_FailingSettings(h.db));
        },
      );
      await t.tap(find.text('Rules'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('skip-tentative')));
      await t.pumpAndSettle();

      expect(find.text('Could not save the change.'), findsOneWidget);
      // The error's own words are never shown.
      expect(find.textContaining('disk is full'), findsNothing);
      // The switch shows what is stored, and nothing was re-planned.
      expect(
        t.widget<SwitchListTile>(find.byKey(const Key('skip-tentative'))).value,
        isTrue,
      );
      expect(h.replans, 0);
      await h.dispose(t);
    },
  );

  testWidgets('rule rows read like sentences', (t) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts',
      seed: (h) async {
        final rules = getIt<RuleRepository>();
        await rules.save(keywordRule('r-000000000001', 0));
        await rules.save(
          keywordRule(
            'r-000000000002',
            1,
            field: RuleField.location,
            match: RuleMatch.regex,
            pattern: r'Room \d',
            profileId: 'important',
          ),
        );
        await rules.save(
          keywordRule(
            'r-000000000003',
            2,
            field: RuleField.hasJoinLink,
            pattern: '',
            profileId: 'silent',
          ),
        );
      },
    );
    await t.tap(find.text('Rules'));
    await t.pumpAndSettle();

    expect(find.text('Title contains standup → Quick'), findsOneWidget);
    expect(find.text(r'Location matches Room \d → Important'), findsOneWidget);
    expect(find.text('Has Teams link → Silent'), findsOneWidget);
    // Each row shows its place in the order the rules run.
    for (final (id, place) in [
      ('r-000000000001', '1'),
      ('r-000000000002', '2'),
      ('r-000000000003', '3'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('rule-$id')),
          matching: find.text(place),
        ),
        findsOneWidget,
        reason: id,
      );
    }
    expect(find.text('Keyword rules'), findsOneWidget);
    expect(find.textContaining('No rules yet'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('without rules the tab says how rules work', (t) async {
    useTallWindow(t);
    final h = await pumpApp(t, location: '/alerts');
    await t.tap(find.text('Rules'));
    await t.pumpAndSettle();

    expect(
      find.text(
        'No rules yet. Rules pick a profile by title, location, organiser or '
        'Teams link.',
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('dragging a rule saves the new order', (t) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts',
      seed: (h) async {
        final rules = getIt<RuleRepository>();
        await rules.save(keywordRule('r-000000000001', 0));
        await rules.save(
          keywordRule(
            'r-000000000002',
            1,
            pattern: 'lunch',
            profileId: 'silent',
          ),
        );
        await rules.save(
          keywordRule(
            'r-000000000003',
            2,
            pattern: 'client',
            profileId: 'important',
          ),
        );
      },
    );
    await t.tap(find.text('Rules'));
    await t.pumpAndSettle();

    final first = find.byKey(const ValueKey('rule-r-000000000001'));
    final second = find.byKey(const ValueKey('rule-r-000000000002'));
    // Drag the first rule three quarters of a row down, a little at a time:
    // its far edge is then past the middle of the second row, so it takes the
    // second place and the third rule stays where it is.
    final rowHeight = t.getSize(first).height;
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(const Key('ruleHandle-r-000000000001'))),
    );
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.75 / 8));
      await t.pump();
    }
    await gesture.up();
    await t.pumpAndSettle();

    expect(
      [for (final r in await getIt<RuleRepository>().all()) r.id],
      ['r-000000000002', 'r-000000000001', 'r-000000000003'],
    );
    // The list shows the same order, with the places renumbered.
    expect(t.getTopLeft(second).dy, lessThan(t.getTopLeft(first).dy));
    expect(
      find.descendant(of: second, matching: find.text('1')),
      findsOneWidget,
    );
    expect(h.replans, 1);
    await h.dispose(t);
  });
}
