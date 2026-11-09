import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/features/agenda/why_text.dart';

import '../../core/fixtures.dart';

void main() {
  // 09:27 on Tuesday 6 Oct 2026 in Johannesburg (UTC+2). The fixture's meeting
  // starts at 10:00.
  final now = DateTime.utc(2026, 10, 6, 7, 27);

  /// What the sheet says for [o] under [rules]. The meeting goes through the
  /// real rules engine, so the sentences are read from the explanations the
  /// engine writes and not from copies of them.
  String why(EventOccurrence o, RuleSet rules, {String? sourceName}) {
    final engine = RulesEngine(zone: johannesburg, clock: () => now);
    return whyText(engine.resolve(o, rules), sourceName: sourceName);
  }

  EventOverride occurrenceOverride(
    EventOccurrence o, {
    String? profileId,
    List<AlertSpec>? custom,
    bool? enabled,
  }) => EventOverride(
    scope: OverrideScope.occurrence,
    target: o.key,
    profileId: profileId,
    customAlerts: custom,
    enabled: enabled,
  );

  EventOverride seriesOverride(
    EventOccurrence o, {
    String? profileId,
    List<AlertSpec>? custom,
    bool? enabled,
  }) => EventOverride(
    scope: OverrideScope.series,
    target: o.seriesUid!,
    profileId: profileId,
    customAlerts: custom,
    enabled: enabled,
  );

  const ownAlerts = [AlertSpec(5, AlertStrength.alarm)];
  const teams = 'https://teams.microsoft.com/l/meetup-join/abc';

  group('one sentence per case of the plan', () {
    test('a quiet mode that silences it says what it would have used', () {
      final o = occ();

      expect(
        why(o, RuleSet(quiet: MuteToday(DateTime.utc(2026, 10, 7, 5)))),
        'It would use **Meeting**, but quiet mode is on: Mute today.',
      );
      expect(
        why(o, RuleSet(quiet: PausedUntil(DateTime.utc(2026, 10, 6, 12)))),
        'It would use **Meeting**, but quiet mode is on: Paused until 14:00.',
      );
      expect(
        why(
          o,
          RuleSet(
            quiet: Vacation(LocalDate(2026, 10, 6), LocalDate(2026, 10, 8)),
          ),
        ),
        'It would use **Meeting**, but quiet mode is on: Vacation.',
      );
    });

    test('an occurrence turned off by hand', () {
      final o = occ();
      final rules = RuleSet(overrides: [occurrenceOverride(o, enabled: false)]);

      expect(why(o, rules), 'You turned this event off.');
    });

    test('an occurrence with alerts of its own', () {
      final o = occ();
      final rules = RuleSet(
        overrides: [occurrenceOverride(o, custom: ownAlerts)],
      );

      expect(why(o, rules), 'You set custom alerts for this event.');
    });

    test('an occurrence with a profile chosen for it', () {
      final o = occ();
      final rules = RuleSet(
        overrides: [occurrenceOverride(o, profileId: BuiltInProfiles.quickId)],
      );

      expect(why(o, rules), 'You chose **Quick** for this event.');
    });

    test('a series turned off', () {
      final o = occ(seriesUid: 'weekly');
      final rules = RuleSet(overrides: [seriesOverride(o, enabled: false)]);

      expect(why(o, rules), 'You turned this series off.');
    });

    test('a series with alerts of its own', () {
      final o = occ(seriesUid: 'weekly');
      final rules = RuleSet(overrides: [seriesOverride(o, custom: ownAlerts)]);

      expect(why(o, rules), 'You set custom alerts for the whole series.');
    });

    test('a series with a profile chosen for it', () {
      final o = occ(seriesUid: 'weekly');
      final rules = RuleSet(
        overrides: [seriesOverride(o, profileId: BuiltInProfiles.importantId)],
      );

      expect(why(o, rules), 'You chose **Important** for the whole series.');
    });

    test('a skipped all-day event points at the rules', () {
      expect(
        why(occ(allDay: true), RuleSet()),
        'All-day events are skipped (Alerts → Rules).',
      );
    });

    test('a skipped free event', () {
      expect(
        why(occ(busyStatus: BusyStatus.free), RuleSet()),
        "It's marked free, and free events are skipped.",
      );
    });

    test('a skipped tentative event', () {
      expect(
        why(occ(busyStatus: BusyStatus.tentative), RuleSet()),
        "It's tentative, and tentative events are skipped.",
      );
    });

    test('a skipped cancelled event', () {
      expect(why(occ(cancelled: true), RuleSet()), 'It was cancelled.');
    });

    test('a skipped declined event', () {
      expect(why(occ(declined: true), RuleSet()), 'You declined it.');
    });

    test('a rule on the Teams link', () {
      final rules = RuleSet(
        rules: [
          KeywordRule(
            id: 'r-teams',
            position: 0,
            field: RuleField.hasJoinLink,
            profileId: BuiltInProfiles.quickId,
          ),
        ],
      );

      expect(
        why(occ(joinUrl: teams), rules),
        'Using **Quick** because it has a Teams link.',
      );
    });

    test('a rule on words', () {
      final rules = RuleSet(
        rules: [
          KeywordRule(
            id: 'r-sprint',
            position: 0,
            field: RuleField.title,
            pattern: 'sprint',
            profileId: BuiltInProfiles.importantId,
          ),
        ],
      );

      expect(
        why(occ(), rules),
        'Using **Important** because the rule “sprint” matched.',
      );
    });

    test('the default profile of a source names the source', () {
      final rules = RuleSet(sourceDefaults: {'work': BuiltInProfiles.quickId});

      expect(
        why(occ(sourceId: 'work'), rules, sourceName: 'Work Outlook'),
        "Using **Quick**. It's the default profile for Work Outlook.",
      );
      // Nothing to name: it still reads as a sentence.
      expect(
        why(occ(sourceId: 'work'), rules, sourceName: null),
        "Using **Quick**. It's the default profile for this calendar.",
      );
    });

    test('the global default profile', () {
      expect(
        why(occ(), RuleSet()),
        "Using **Meeting** because no rule matched. It's your default profile.",
      );
      expect(
        why(
          occ(),
          RuleSet(globalDefaultProfileId: BuiltInProfiles.importantId),
        ),
        "Using **Important** because no rule matched. It's your default "
        'profile.',
      );
    });
  });

  // Beyond the plan's list: the sentences read the engine's explanation line,
  // which holds text a user typed, so these pin what the plan's table leaves
  // open.
  group('text a user typed', () {
    AlertProfile named(String id, String name) => AlertProfile(
      id: id,
      name: name,
      alerts: const [AlertSpec(5, AlertStrength.headsUp)],
    );

    test(
      'a profile that is called Off or Custom is a choice, not a switch',
      () {
        final o = occ();
        final rules = RuleSet(
          profiles: [named('p-off', 'Off'), named('p-custom', 'Custom')],
          overrides: [occurrenceOverride(o, profileId: 'p-off')],
        );
        expect(why(o, rules), 'You chose **Off** for this event.');

        final other = RuleSet(
          profiles: [named('p-off', 'Off'), named('p-custom', 'Custom')],
          overrides: [occurrenceOverride(o, profileId: 'p-custom')],
        );
        expect(why(o, other), 'You chose **Custom** for this event.');
      },
    );

    test('words that hold a dot or a quote are quoted whole', () {
      final rules = RuleSet(
        rules: [
          KeywordRule(
            id: 'r-odd',
            position: 0,
            field: RuleField.title,
            pattern: 'a · "b"',
            profileId: BuiltInProfiles.quickId,
          ),
        ],
      );

      expect(
        why(occ(title: 'Talk: a · "b" later'), rules),
        'Using **Quick** because the rule “a · "b"” matched.',
      );
    });

    test('a profile name that holds a dot still leads its rule sentence', () {
      final rules = RuleSet(
        profiles: [named('p-work', 'Work · Important')],
        rules: [
          KeywordRule(
            id: 'r-sprint',
            position: 0,
            field: RuleField.title,
            pattern: 'sprint',
            profileId: 'p-work',
          ),
        ],
      );

      expect(
        why(occ(), rules),
        'Using **Work · Important** because the rule “sprint” matched.',
      );
    });

    test('a ** in a name does not switch the bold on or off', () {
      final rules = RuleSet(
        profiles: [named('p-star', 'A**B')],
        globalDefaultProfileId: 'p-star',
      );

      final pieces = whyPieces(why(occ(), rules));

      // The whole name is bold, and the asterisks are still on the screen.
      expect(
        [
          for (final p in pieces)
            if (p.bold) p.text,
        ],
        ['A*\u200B*B'],
      );
      expect(pieces.map((p) => p.text).join(), contains('A*\u200B*B because'));
    });

    test('an explanation it does not know still gets a sentence', () {
      final o = occ();
      ResolvedOccurrence resolved(ResolutionStep step, String explanation) =>
          ResolvedOccurrence(
            occurrence: o,
            profile: BuiltInProfiles.silent,
            alerts: const [],
            explanation: explanation,
            silenced: false,
            step: step,
          );

      expect(
        whyText(
          resolved(ResolutionStep.skipFilter, 'Silent · something new'),
          sourceName: null,
        ),
        'Using **Silent**.',
      );
      expect(
        whyText(
          resolved(ResolutionStep.keywordRule, 'Silent · rule: something new'),
          sourceName: null,
        ),
        'Using **Silent**.',
      );
    });
  });

  group('whyPieces', () {
    test('splits at the markers and marks the wrapped part', () {
      expect(whyPieces('Using **Quick** because it has a Teams link.'), [
        (text: 'Using ', bold: false),
        (text: 'Quick', bold: true),
        (text: ' because it has a Teams link.', bold: false),
      ]);
    });

    test('keeps a sentence without markers whole and drops empty pieces', () {
      expect(whyPieces('You declined it.'), [
        (text: 'You declined it.', bold: false),
      ]);
      expect(whyPieces('**Quick** first'), [
        (text: 'Quick', bold: true),
        (text: ' first', bold: false),
      ]);
    });
  });
}
