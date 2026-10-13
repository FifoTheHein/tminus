import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/quiet_state.dart';
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

  group('an empty custom-alert list means none (decision 17)', () {
    runCases([
      Case(
        'occurrence: profile with empty custom alerts uses the profile',
        plain,
        RuleSet(
          overrides: [onOcc(plain, profileId: 'quick', customAlerts: [])],
        ),
        'Quick · this event',
        quickAlerts,
        step: ResolutionStep.occurrenceOverride,
      ),
      Case(
        'occurrence: only empty custom alerts falls through',
        plain,
        RuleSet(overrides: [onOcc(plain, customAlerts: [])]),
        'Meeting · default',
        meetingAlerts,
        step: ResolutionStep.globalDefault,
      ),
      Case(
        'occurrence: turned on with empty custom alerts',
        plain,
        RuleSet(
          globalDefaultProfileId: 'quick',
          overrides: [onOcc(plain, enabled: true, customAlerts: [])],
        ),
        'Quick · this event',
        quickAlerts,
        step: ResolutionStep.occurrenceOverride,
      ),
      Case(
        'series: profile with empty custom alerts uses the profile',
        recurring,
        RuleSet(
          overrides: [
            onSeries('series-1', profileId: 'important', customAlerts: []),
          ],
        ),
        'Important · series',
        importantAlerts,
        step: ResolutionStep.seriesOverride,
      ),
      Case(
        'series: only empty custom alerts falls through',
        recurring,
        RuleSet(overrides: [onSeries('series-1', customAlerts: [])]),
        'Meeting · default',
        meetingAlerts,
        step: ResolutionStep.globalDefault,
      ),
    ], engine);
  });

  group('duplicate offsets collapse (decision 18)', () {
    test('custom alerts keep one alert per offset, the alarm winning', () {
      final r = engine().resolve(
        plain,
        RuleSet(
          overrides: [
            onOcc(
              plain,
              customAlerts: const [
                AlertSpec(5, AlertStrength.headsUp),
                AlertSpec(10, AlertStrength.headsUp),
                AlertSpec(5, AlertStrength.alarm),
              ],
            ),
          ],
        ),
      );
      expect(r.explanation, 'Custom · this event');
      expect(r.alerts, const [
        AlertSpec(5, AlertStrength.alarm),
        AlertSpec(10, AlertStrength.headsUp),
      ]);
      expect(
        () => r.alerts.add(const AlertSpec(1, AlertStrength.alarm)),
        throwsUnsupportedError,
      );
    });

    test('a profile with duplicate offsets collapses too', () {
      final r = engine().resolve(
        plain,
        RuleSet(
          profiles: [
            BuiltInProfiles.quick.copyWith(
              alerts: const [
                AlertSpec(1, AlertStrength.alarm),
                AlertSpec(1, AlertStrength.headsUp),
                AlertSpec(1, AlertStrength.alarm),
              ],
            ),
          ],
          globalDefaultProfileId: 'quick',
        ),
      );
      expect(r.alerts, const [AlertSpec(1, AlertStrength.alarm)]);
    });
  });

  group('a meeting found in several sources (spec §13)', () {
    // Ranked best first: the phone copy decides the time.
    final phone = occ(sourceId: 'phone', uid: 'p1', seriesUid: 'phone-series');
    final feed = occ(sourceId: 'feed', uid: 'f1', seriesUid: 'feed-series');
    final work = occ(sourceId: 'work', uid: 'w1', seriesUid: 'work-series');
    // The key a source that has since gone gave the meeting. No copy has it.
    final meetingKey = EventOccurrence.makeKey(
      'gone',
      'm1',
      phone.originalStartUtc,
    );
    final meeting = meetingOf([phone, feed, work], meetingKey: meetingKey);

    test('an occurrence override on a copy key applies to the meeting', () {
      // The last copy's key is the one furthest down the lookup list.
      final r = engine().resolve(
        meeting,
        RuleSet(overrides: [onOcc(work, profileId: 'quick')]),
      );
      expect(r.explanation, 'Quick · this event');
      expect(r.alerts, quickAlerts);
      expect(r.step, ResolutionStep.occurrenceOverride);
      expect(r.occurrence, same(meeting));
    });

    test('an override on the meeting key beats one on a copy key', () {
      final r = engine().resolve(
        meeting,
        RuleSet(
          overrides: [
            onOcc(feed, profileId: 'quick'),
            onOcc(meeting, profileId: 'important'),
          ],
        ),
      );
      expect(r.explanation, 'Important · this event');
      expect(r.alerts, importantAlerts);
      expect(r.step, ResolutionStep.occurrenceOverride);
    });

    test("of two copy keys, the better ranked copy's override wins", () {
      final r = engine().resolve(
        meeting,
        RuleSet(
          overrides: [
            onOcc(work, profileId: 'quick'),
            onOcc(feed, profileId: 'important'),
          ],
        ),
      );
      expect(r.explanation, 'Important · this event');
      expect(r.alerts, importantAlerts);
    });

    test("a series override on any copy's seriesUid applies", () {
      // The last copy's series is the one furthest down the lookup list.
      final r = engine().resolve(
        meeting,
        RuleSet(overrides: [onSeries('work-series', profileId: 'important')]),
      );
      expect(r.explanation, 'Important · series');
      expect(r.alerts, importantAlerts);
      expect(r.step, ResolutionStep.seriesOverride);
      expect(r.occurrence, same(meeting));
    });

    test("of two series overrides, the better ranked copy's wins", () {
      final r = engine().resolve(
        meeting,
        RuleSet(
          overrides: [
            onSeries('work-series', profileId: 'quick'),
            onSeries('feed-series', profileId: 'important'),
          ],
        ),
      );
      expect(r.explanation, 'Important · series');
      expect(r.alerts, importantAlerts);
    });

    test(
      'the source default comes from the first ranked source that has one',
      () {
        // The phone has none, the feed has Important and work has Quick.
        final r = engine().resolve(
          meeting,
          RuleSet(sourceDefaults: {'feed': 'important', 'work': 'quick'}),
        );
        expect(r.explanation, 'Important · source default');
        expect(r.alerts, importantAlerts);
        expect(r.step, ResolutionStep.sourceDefault);
      },
    );

    test('a meeting turned on takes the default of the first ranked source '
        'that has one', () {
      final r = engine().resolve(
        meeting,
        RuleSet(
          sourceDefaults: {'feed': 'important', 'work': 'quick'},
          globalDefaultProfileId: 'silent',
          overrides: [onOcc(meeting, enabled: true)],
        ),
      );
      expect(r.explanation, 'Important · this event');
      expect(r.alerts, importantAlerts);
    });
  });

  test('withoutOccurrenceEnabled drops only enabled on the given keys', () {
    final a = occ(uid: 'a');
    final b = occ(uid: 'b');
    final c = occ(uid: 'c');
    final edited = BuiltInProfiles.meeting.copyWith(alerts: custom);
    final quiet = MuteToday(DateTime.utc(2026, 10, 7, 5));
    final rules = RuleSet(
      profiles: [edited],
      overrides: [
        onOcc(a, profileId: 'quick', enabled: false),
        onOcc(b, enabled: true),
        onOcc(c, enabled: false),
        onSeries('series-1', enabled: false),
      ],
      rules: [titleRule('standup', 'quick')],
      skipFilters: const SkipFilters(tentative: false),
      sourceDefaults: {'work': 'important'},
      globalDefaultProfileId: 'quick',
      quiet: quiet,
    );

    final natural = rules.withoutOccurrenceEnabled([
      a.key,
      b.key,
      'no-such-key',
    ]);

    // An override with a profile keeps it; only the toggle goes.
    expect(natural.occurrenceOverride(a.key), onOcc(a, profileId: 'quick'));
    // An override with only the toggle disappears.
    expect(natural.occurrenceOverride(b.key), isNull);
    // Keys that were not given keep their override, and so do series ones.
    expect(natural.occurrenceOverride(c.key), onOcc(c, enabled: false));
    expect(
      natural.seriesOverride('series-1'),
      onSeries('series-1', enabled: false),
    );
    // Everything else comes across unchanged.
    expect(natural.rules, rules.rules);
    expect(natural.skipFilters, rules.skipFilters);
    expect(natural.sourceDefaults, {'work': 'important'});
    expect(natural.globalDefaultProfileId, 'quick');
    expect(natural.quiet, quiet);
    expect(natural.profile('meeting'), edited);
    // The rule set it came from is not changed.
    expect(
      rules.occurrenceOverride(a.key),
      onOcc(a, profileId: 'quick', enabled: false),
    );
    expect(rules.occurrenceOverride(b.key), onOcc(b, enabled: true));

    // What the Agenda toggle compares against: a tentative event that a skip
    // filter silences, switched on, falls back to the filter without it.
    final toggled = RuleSet(overrides: [onOcc(tentative, enabled: true)]);
    expect(
      engine().resolve(tentative, toggled).explanation,
      'Meeting · this event',
    );
    expect(
      engine()
          .resolve(
            tentative,
            toggled.withoutOccurrenceEnabled(tentative.lookupKeys),
          )
          .explanation,
      'Silent · tentative',
    );
  });

  test('the natural state drops the overrides on the other lookup keys', () {
    // A meeting no copy has the key of any more, with one copy. Its lookup
    // keys are the meeting key (A) and the copy's key (B).
    final copy = occ(sourceId: 'phone', uid: 'p1');
    final meetingKey = EventOccurrence.makeKey(
      'gone',
      'm1',
      copy.originalStartUtc,
    );
    final meeting = meetingOf([copy], meetingKey: meetingKey);
    expect(meeting.lookupKeys, [meetingKey, copy.key]);
    // A is switched off. B holds a profile chosen while merging was off. B is
    // listed first on purpose: only the order of the keys decides.
    final rules = RuleSet(
      globalDefaultProfileId: 'silent',
      overrides: [
        onOcc(copy, profileId: 'meeting'),
        onOcc(meeting, enabled: false),
      ],
    );
    // B's override alone would turn the meeting on.
    expect(
      engine()
          .resolve(
            meeting,
            RuleSet(
              globalDefaultProfileId: 'silent',
              overrides: [onOcc(copy, profileId: 'meeting')],
            ),
          )
          .explanation,
      'Meeting · this event',
    );

    final natural = rules.withoutOccurrenceEnabled(meeting.lookupKeys);

    // Clearing the toggle through rewriteFor leaves A with nothing set, which
    // deletes it, and deletes B too. So the rules are the plain ones, and the
    // meeting follows the default, Silent.
    final afterRewrite = RuleSet(globalDefaultProfileId: 'silent');
    final got = engine().resolve(meeting, natural);
    final want = engine().resolve(meeting, afterRewrite);
    expect(got.explanation, want.explanation);
    expect(got.alerts, want.alerts);
    expect(got.explanation, 'Silent · default');
    expect(got.alerts, isEmpty);
    expect(natural.occurrenceOverride(meetingKey), isNull);
    expect(natural.occurrenceOverride(copy.key), isNull);
  });

  test('the natural state keeps the override in effect wherever it sits', () {
    // Nothing on the meeting key. The first copy's override is in effect, and
    // the second copy's, listed first here on purpose, is not.
    final first = occ(sourceId: 'phone', uid: 'p1');
    final second = occ(sourceId: 'feed', uid: 'f1');
    final meetingKey = EventOccurrence.makeKey(
      'gone',
      'm1',
      first.originalStartUtc,
    );
    final meeting = meetingOf([first, second], meetingKey: meetingKey);
    expect(meeting.lookupKeys, [meetingKey, first.key, second.key]);
    final rules = RuleSet(
      overrides: [
        onOcc(second, profileId: 'important'),
        onOcc(first, profileId: 'quick', enabled: false),
      ],
    );

    final natural = rules.withoutOccurrenceEnabled(meeting.lookupKeys);

    // The first copy's profile stays, without its toggle. The second copy's
    // override is gone.
    final r = engine().resolve(meeting, natural);
    expect(r.explanation, 'Quick · this event');
    expect(r.alerts, quickAlerts);
    expect(natural.occurrenceOverride(second.key), isNull);
  });
}
