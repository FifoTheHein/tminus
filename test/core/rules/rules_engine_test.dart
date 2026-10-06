import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';

import '../fixtures.dart';
import 'rules_test_helpers.dart';

void main() {
  final plain = occ();
  final standup = occ(uid: 'standup', title: 'Daily standup');
  final tentative = occ(uid: 't', busyStatus: BusyStatus.tentative);
  final recurring = occ(uid: 'rec', seriesUid: 'series-1');
  final recurringTentative = occ(
    uid: 'rec2',
    seriesUid: 'series-2',
    busyStatus: BusyStatus.tentative,
  );
  final lunch = occ(uid: 'lunch', title: 'Lunch');
  final teams = occ(
    uid: 'teams',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/1',
  );

  final cases = <Case>[
    // 6. Global default
    Case(
      'global default',
      plain,
      RuleSet(),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
      profileId: 'meeting',
    ),
    Case(
      'global default set to Quick',
      plain,
      RuleSet(globalDefaultProfileId: 'quick'),
      'Quick · default',
      quickAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'unknown global default falls back to Meeting',
      plain,
      RuleSet(globalDefaultProfileId: 'deleted'),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'edited built-in replaces the constant',
      plain,
      RuleSet(profiles: [BuiltInProfiles.meeting.copyWith(alerts: custom)]),
      'Meeting · default',
      custom,
      step: ResolutionStep.globalDefault,
    ),

    // 5. Source default
    Case(
      'source default',
      plain,
      RuleSet(sourceDefaults: {'work': 'important'}),
      'Important · source default',
      importantAlerts,
      step: ResolutionStep.sourceDefault,
    ),
    Case(
      'source default of another source does not apply',
      plain,
      RuleSet(sourceDefaults: {'personal': 'important'}),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'unknown source default falls through',
      plain,
      RuleSet(sourceDefaults: {'work': 'deleted'}),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),

    // 4. Keyword rules
    Case(
      'keyword rule',
      standup,
      RuleSet(rules: [titleRule('standup', 'quick')]),
      'Quick · rule: "standup"',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rules run by position, not list order',
      standup,
      RuleSet(
        rules: [
          titleRule('daily', 'important', position: 1),
          titleRule('standup', 'quick', position: 0),
        ],
      ),
      'Quick · rule: "standup"',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rule with a deleted profile is skipped',
      standup,
      RuleSet(
        rules: [
          titleRule('standup', 'deleted', position: 0),
          titleRule('daily', 'important', position: 1),
        ],
      ),
      'Important · rule: "daily"',
      importantAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'hasJoinLink rule',
      teams,
      RuleSet(
        rules: [
          KeywordRule(
            id: 'j',
            position: 0,
            field: RuleField.hasJoinLink,
            profileId: 'quick',
          ),
        ],
      ),
      'Quick · rule: Teams link',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rule to Silent',
      lunch,
      RuleSet(rules: [titleRule('lunch', 'silent')]),
      'Silent · rule: "lunch"',
      const [],
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rule beats source default',
      standup,
      RuleSet(
        rules: [titleRule('standup', 'quick')],
        sourceDefaults: {'work': 'important'},
      ),
      'Quick · rule: "standup"',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),

    // 3. Skip filters
    Case(
      'skip all-day',
      occ(uid: 'ad', allDay: true),
      RuleSet(),
      'Silent · all-day',
      const [],
      step: ResolutionStep.skipFilter,
      profileId: 'silent',
    ),
    Case(
      'skip free',
      occ(uid: 'f', busyStatus: BusyStatus.free),
      RuleSet(),
      'Silent · free',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'skip tentative',
      tentative,
      RuleSet(),
      'Silent · tentative',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'skip cancelled',
      occ(uid: 'c', cancelled: true),
      RuleSet(),
      'Silent · cancelled',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'skip declined',
      occ(uid: 'd', declined: true),
      RuleSet(),
      'Silent · declined',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'tentative filter switched off',
      tentative,
      RuleSet(skipFilters: const SkipFilters(tentative: false)),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'skip filter beats keyword rule',
      occ(uid: 'ts', title: 'Standup', busyStatus: BusyStatus.tentative),
      RuleSet(rules: [titleRule('standup', 'quick')]),
      'Silent · tentative',
      const [],
      step: ResolutionStep.skipFilter,
    ),

    // 2. Series override
    Case(
      'series override beats skip filter',
      recurringTentative,
      RuleSet(overrides: [onSeries('series-2', profileId: 'important')]),
      'Important · series',
      importantAlerts,
      step: ResolutionStep.seriesOverride,
    ),
    Case(
      'series override off',
      recurring,
      RuleSet(overrides: [onSeries('series-1', enabled: false)]),
      'Off · series',
      const [],
      step: ResolutionStep.seriesOverride,
    ),
    Case(
      'series override does not touch one-off events',
      plain,
      RuleSet(overrides: [onSeries('series-1', profileId: 'quick')]),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),

    // 1. Occurrence override
    Case(
      'occurrence override beats series override',
      recurring,
      RuleSet(
        overrides: [
          onSeries('series-1', profileId: 'important'),
          onOcc(recurring, profileId: 'quick'),
        ],
      ),
      'Quick · this event',
      quickAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'agenda toggle off',
      plain,
      RuleSet(overrides: [onOcc(plain, enabled: false)]),
      'Off · this event',
      const [],
      step: ResolutionStep.occurrenceOverride,
      profileId: 'silent',
    ),
    Case(
      'agenda toggle on skips the skip filter',
      tentative,
      RuleSet(overrides: [onOcc(tentative, enabled: true)]),
      'Meeting · this event',
      meetingAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'toggle on ignores a rule that resolves to Silent',
      lunch,
      RuleSet(
        rules: [titleRule('lunch', 'silent')],
        overrides: [onOcc(lunch, enabled: true)],
      ),
      'Meeting · this event',
      meetingAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'custom alerts replace the named profile list',
      plain,
      RuleSet(
        overrides: [onOcc(plain, profileId: 'quick', customAlerts: custom)],
      ),
      'Quick · this event',
      custom,
      step: ResolutionStep.occurrenceOverride,
      profileId: 'quick',
    ),
    Case(
      'custom alerts without a profile use the lower step for sound',
      recurring,
      RuleSet(
        overrides: [
          onSeries('series-1', profileId: 'important'),
          onOcc(recurring, customAlerts: custom),
        ],
      ),
      'Custom · this event',
      custom,
      step: ResolutionStep.occurrenceOverride,
      profileId: 'important',
    ),
    Case(
      'empty override is ignored',
      plain,
      RuleSet(overrides: [onOcc(plain)]),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'override naming a deleted profile falls through',
      plain,
      RuleSet(overrides: [onOcc(plain, profileId: 'deleted')]),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
  ];

  RulesEngine engine() => RulesEngine(zone: johannesburg, clock: () => now);

  runCases(cases, engine);

  test('resolveAll keeps input order', () {
    final r = engine().resolveAll([
      standup,
      plain,
    ], RuleSet(rules: [titleRule('standup', 'quick')]));
    expect(r.map((e) => e.explanation), [
      'Quick · rule: "standup"',
      'Meeting · default',
    ]);
  });

  group('turned-on fallback to Meeting (decision 2)', () {
    test('uses the stored Meeting, not the constant', () {
      final edited = BuiltInProfiles.meeting.copyWith(
        alerts: const [AlertSpec(15, AlertStrength.alarm)],
        sound: const SoundSettings(vibrate: false),
      );
      final r = engine().resolve(
        plain,
        RuleSet(
          profiles: [edited],
          globalDefaultProfileId: 'silent',
          overrides: [onOcc(plain, enabled: true)],
        ),
      );
      expect(r.explanation, 'Meeting · this event');
      expect(r.alerts, const [AlertSpec(15, AlertStrength.alarm)]);
      expect(r.profile, edited);
      expect(r.profile.sound.vibrate, isFalse);
    });

    test('uses the constant when the stored Meeting has no alerts', () {
      final r = engine().resolve(
        plain,
        RuleSet(
          profiles: [BuiltInProfiles.meeting.copyWith(alerts: const [])],
          globalDefaultProfileId: 'silent',
          overrides: [onOcc(plain, enabled: true)],
        ),
      );
      expect(r.explanation, 'Meeting · this event');
      expect(r.alerts, meetingAlerts);
      expect(r.profile, BuiltInProfiles.meeting);
    });
  });

  group('Silent never has alerts (decision 16)', () {
    final loudSilent = BuiltInProfiles.silent.copyWith(
      alerts: const [AlertSpec(5, AlertStrength.alarm)],
    );

    test('a skip filter resolves to Silent with no alerts', () {
      final r = engine().resolve(tentative, RuleSet(profiles: [loudSilent]));
      expect(r.explanation, 'Silent · tentative');
      expect(r.alerts, isEmpty);
      expect(r.profile.alerts, isEmpty);
    });

    test('a default or rule naming Silent gives no alerts', () {
      final rules = [
        RuleSet(profiles: [loudSilent], globalDefaultProfileId: 'silent'),
        RuleSet(profiles: [loudSilent], sourceDefaults: {'work': 'silent'}),
        RuleSet(profiles: [loudSilent], rules: [titleRule('Sprint', 'silent')]),
        RuleSet(
          profiles: [loudSilent],
          overrides: [onOcc(plain, profileId: 'silent')],
        ),
      ];
      for (final rs in rules) {
        final r = engine().resolve(plain, rs);
        expect(r.profile.id, 'silent', reason: r.explanation);
        expect(r.alerts, isEmpty, reason: r.explanation);
      }
    });

    test('a turned-on event never picks Silent', () {
      final r = engine().resolve(
        plain,
        RuleSet(
          profiles: [loudSilent],
          globalDefaultProfileId: 'silent',
          overrides: [onOcc(plain, enabled: true)],
        ),
      );
      expect(r.explanation, 'Meeting · this event');
      expect(r.alerts, meetingAlerts);
    });
  });
}
