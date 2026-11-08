import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/features/alerts/rule_editor_screen.dart';

import '../../core/fixtures.dart';
import '../harness.dart';
import 'alerts_test_support.dart';

const _feed = SourceConfig(
  id: 'feed',
  name: 'Work Outlook',
  color: blue,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.feed',
);

/// The harness's clock is 09:27 on Tuesday 6 Oct 2026 in Johannesburg, which is
/// UTC+2 all year. Three meetings are still to come, one has ended.
final _meetings = [
  occ(
    sourceId: 'feed',
    uid: 'daily',
    title: 'Daily standup',
    start: DateTime.utc(2026, 10, 6, 8, 45),
  ),
  occ(
    sourceId: 'feed',
    uid: 'sprint',
    title: 'Sprint planning',
    start: DateTime.utc(2026, 10, 6, 10),
    joinUrl: 'https://teams.example/j/1',
  ),
  occ(
    sourceId: 'feed',
    uid: 'early',
    title: 'Early standup',
    start: DateTime.utc(2026, 10, 6, 5),
  ),
  occ(
    sourceId: 'feed',
    uid: 'client',
    title: 'Client demo',
    start: DateTime.utc(2026, 10, 7, 12),
  ),
];

void main() {
  FilledButton save(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(const Key('saveRule')));
  Future<void> type(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const Key('rulePattern')), text);
    await t.pump();
  }

  Future<void> chooseField(WidgetTester t, String label) async {
    await t.tap(find.byKey(const Key('ruleField')));
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  const invalid = 'This pattern is not a valid regular expression.';

  testWidgets('an invalid regex disables Save', (t) async {
    useTallWindow(t);
    final h = await pumpApp(t, location: '/alerts/rules/new');

    // As plain text, a lone bracket is fine.
    await type(t, 'stand(');
    expect(find.text(invalid), findsNothing);
    expect(save(t).onPressed, isNotNull);

    // As a regular expression it is not.
    await t.tap(find.byKey(const Key('ruleRegex')));
    await t.pump();
    expect(find.text(invalid), findsOneWidget);
    expect(save(t).onPressed, isNull);

    // Fixing the pattern brings Save back.
    await type(t, 'stand(up)');
    expect(find.text(invalid), findsNothing);
    expect(save(t).onPressed, isNotNull);
    await h.dispose(t);
  });

  testWidgets('the preview counts matching upcoming meetings', (t) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts/rules/new',
      seed: (h) async {
        await getIt<SourceRepository>().save(_feed);
        await getIt<OccurrenceRepository>().replaceForSource('feed', _meetings);
      },
    );
    String count() =>
        t.widget<Text>(find.byKey(const Key('rulePreviewCount'))).data!;

    // Nothing typed yet: an empty pattern matches nothing.
    expect(count(), 'Matches 0 upcoming events');

    // One meeting still to come has "standup" in its title. The one that
    // ended before now is not counted.
    await type(t, 'standup');
    expect(count(), 'Matches 1 upcoming event');
    expect(find.text('Daily standup'), findsOneWidget);
    expect(find.text('Tue 6 Oct 10:45'), findsOneWidget);
    expect(find.text('Early standup'), findsNothing);

    await type(t, 'planning');
    expect(count(), 'Matches 1 upcoming event');
    expect(find.text('Sprint planning'), findsOneWidget);
    expect(find.text('Tue 6 Oct 12:00'), findsOneWidget);
    expect(find.text('Daily standup'), findsNothing);

    await type(t, 'zzz');
    expect(count(), 'Matches 0 upcoming events');

    // Two words with a bar between them are plain text until the regular
    // expression switch is on.
    await type(t, 'sprint|daily');
    expect(count(), 'Matches 0 upcoming events');
    await t.tap(find.byKey(const Key('ruleRegex')));
    await t.pump();
    expect(count(), 'Matches 2 upcoming events');
    expect(find.text('Daily standup'), findsOneWidget);
    expect(find.text('Sprint planning'), findsOneWidget);

    // A Teams-link rule matches the meeting that has a link.
    await chooseField(t, 'Has Teams link');
    expect(find.byKey(const Key('rulePattern')), findsNothing);
    expect(count(), 'Matches 1 upcoming event');
    expect(find.text('Sprint planning'), findsOneWidget);

    // The meetings are read once, when the editor opens: a meeting that arrives
    // later is not in the preview.
    await getIt<OccurrenceRepository>().replaceForSource('feed', [
      ..._meetings,
      occ(
        sourceId: 'feed',
        uid: 'late',
        title: 'Late standup',
        start: DateTime.utc(2026, 10, 7, 8),
      ),
    ]);
    await chooseField(t, 'Title');
    await type(t, 'standup');
    expect(count(), 'Matches 1 upcoming event');
    expect(find.text('Late standup'), findsNothing);
    await h.dispose(t);
  });

  // Beyond the plan's list: each pins one thing the editor promises.

  testWidgets('the preview lists at most five of the meetings', (t) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts/rules/new',
      seed: (h) async {
        await getIt<SourceRepository>().save(_feed);
        await getIt<OccurrenceRepository>().replaceForSource('feed', [
          for (var i = 1; i <= 7; i++)
            occ(
              sourceId: 'feed',
              uid: 'standup$i',
              title: 'Standup $i',
              start: DateTime.utc(2026, 10, 7, 6 + i),
            ),
        ]);
      },
    );

    await type(t, 'standup');

    expect(
      t.widget<Text>(find.byKey(const Key('rulePreviewCount'))).data,
      'Matches 7 upcoming events',
    );
    expect(find.textContaining('Standup '), findsNWidgets(5));
    await h.dispose(t);
  });

  testWidgets('a new rule saves with an r- id, the next place and a re-plan', (
    t,
  ) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts',
      seed: (h) async {
        final rules = getIt<RuleRepository>();
        await rules.save(
          keywordRule(
            'r-000000000001',
            0,
            pattern: 'lunch',
            profileId: 'silent',
          ),
        );
        // A gap in the places: the new rule goes after the last one.
        await rules.save(
          keywordRule(
            'r-000000000002',
            7,
            pattern: 'client',
            profileId: 'important',
          ),
        );
      },
    );
    await t.tap(find.text('Rules'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('newRule')));
    await t.pumpAndSettle();

    // A new rule starts as "Title contains … → Quick", and has no text yet,
    // so there is nothing to save.
    expect(
      t
          .widget<DropdownButton<RuleField>>(find.byKey(const Key('ruleField')))
          .value,
      RuleField.title,
    );
    expect(
      t.widget<SwitchListTile>(find.byKey(const Key('ruleRegex'))).value,
      isFalse,
    );
    expect(
      t.widget<ChoiceChip>(find.byKey(const Key('ruleProfile-quick'))).selected,
      isTrue,
    );
    expect(find.byKey(const Key('deleteRule')), findsNothing);
    expect(save(t).onPressed, isNull);

    await type(t, 'stand(up)');
    await t.tap(find.byKey(const Key('ruleRegex')));
    await t.pump();
    await t.tap(find.byKey(const Key('ruleProfile-important')));
    await t.pump();
    expect(save(t).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('saveRule')));
    await t.pumpAndSettle();

    final rules = await getIt<RuleRepository>().all();
    expect(rules, hasLength(3));
    final saved = rules.last;
    expect(saved.id, matches(RegExp(r'^r-[0-9a-f]{12}$')));
    expect(saved.position, 8);
    expect(saved.field, RuleField.title);
    expect(saved.match, RuleMatch.regex);
    expect(saved.pattern, 'stand(up)');
    expect(saved.profileId, 'important');
    expect(h.replans, 1);
    // Back on the list, where the rule reads as a sentence.
    expect(find.byType(RuleEditorScreen), findsNothing);
    expect(find.text('Title matches stand(up) → Important'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('editing a rule keeps its id and its place', (t) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts/rules/r-000000000002',
      seed: (h) async {
        final rules = getIt<RuleRepository>();
        await rules.save(keywordRule('r-000000000001', 0));
        await rules.save(
          keywordRule(
            'r-000000000002',
            1,
            field: RuleField.location,
            pattern: 'Boardroom',
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

    // The form shows the stored rule.
    expect(
      t
          .widget<DropdownButton<RuleField>>(find.byKey(const Key('ruleField')))
          .value,
      RuleField.location,
    );
    expect(
      t
          .widget<TextField>(find.byKey(const Key('rulePattern')))
          .controller!
          .text,
      'Boardroom',
    );
    expect(
      t
          .widget<ChoiceChip>(find.byKey(const Key('ruleProfile-silent')))
          .selected,
      isTrue,
    );

    await type(t, 'Boardroom 2');
    await t.tap(find.byKey(const Key('ruleProfile-meeting')));
    await t.pump();
    await t.tap(find.byKey(const Key('saveRule')));
    await t.pumpAndSettle();

    final rules = await getIt<RuleRepository>().all();
    expect(
      [for (final r in rules) r.id],
      ['r-000000000001', 'r-000000000002', 'r-000000000003'],
    );
    expect(
      rules[1],
      keywordRule(
        'r-000000000002',
        1,
        field: RuleField.location,
        pattern: 'Boardroom 2',
        profileId: 'meeting',
      ),
    );
    expect(h.replans, 1);
    expect(find.byType(RuleEditorScreen), findsNothing);
    await h.dispose(t);
  });

  testWidgets('deleting a rule removes it and asks for a re-plan', (t) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts/rules/r-000000000002',
      seed: (h) async {
        final rules = getIt<RuleRepository>();
        await rules.save(keywordRule('r-000000000001', 0));
        await rules.save(keywordRule('r-000000000002', 1, pattern: 'lunch'));
      },
    );

    await t.tap(find.byKey(const Key('deleteRule')));
    await t.pumpAndSettle();

    expect(
      [for (final r in await getIt<RuleRepository>().all()) r.id],
      ['r-000000000001'],
    );
    expect(h.replans, 1);
    expect(find.byType(RuleEditorScreen), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a Teams-link rule has no pattern and is not a regex', (t) async {
    useTallWindow(t);
    final h = await pumpApp(t, location: '/alerts/rules/new');

    // Text and the regular-expression switch left over from another field are
    // not saved with a Teams-link rule.
    await type(t, 'standup');
    await t.tap(find.byKey(const Key('ruleRegex')));
    await t.pump();
    await chooseField(t, 'Has Teams link');
    expect(find.byKey(const Key('rulePattern')), findsNothing);
    expect(find.byKey(const Key('ruleRegex')), findsNothing);
    expect(save(t).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('saveRule')));
    await t.pumpAndSettle();

    final saved = (await getIt<RuleRepository>().all()).single;
    expect(saved.field, RuleField.hasJoinLink);
    expect(saved.match, RuleMatch.contains);
    expect(saved.pattern, '');
    expect(saved.profileId, 'quick');
    await h.dispose(t);
  });

  testWidgets('a rule that is gone says so', (t) async {
    final h = await pumpApp(t, location: '/alerts/rules/nope');

    expect(find.text('This rule was removed.'), findsOneWidget);
    expect(find.byKey(const Key('saveRule')), findsNothing);
    await h.dispose(t);
  });
}
