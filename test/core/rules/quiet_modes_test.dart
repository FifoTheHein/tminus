import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';

import '../fixtures.dart';
import 'rules_test_helpers.dart';

void main() {
  final plain = occ();
  final tentative = occ(uid: 't', busyStatus: BusyStatus.tentative);
  final recurring = occ(uid: 'rec', seriesUid: 'series-1');
  final noon = occ(uid: 'noon', start: DateTime.utc(2026, 10, 6, 12));

  final mute = MuteToday(DateTime.utc(2026, 10, 7, 5));
  final pause = PausedUntil(DateTime.utc(2026, 10, 6, 12)); // 14:00 SAST
  final vacation = Vacation(LocalDate(2026, 10, 6), LocalDate(2026, 10, 9));

  final cases = <Case>[
    // Quiet modes
    Case(
      'mute silences Meeting',
      plain,
      RuleSet(quiet: mute),
      'Silenced · Mute today',
      const [],
      step: ResolutionStep.globalDefault,
      silenced: true,
    ),
    Case(
      'mute lets Important through',
      plain,
      RuleSet(quiet: mute, sourceDefaults: {'work': 'important'}),
      'Important · source default',
      importantAlerts,
      step: ResolutionStep.sourceDefault,
    ),
    Case(
      'pause shows its local end time',
      plain,
      RuleSet(quiet: pause),
      'Silenced · Paused until 14:00',
      const [],
      step: ResolutionStep.globalDefault,
      silenced: true,
    ),
    Case(
      'a pause ending on another day names the day (decision 22)',
      plain,
      RuleSet(quiet: PausedUntil(DateTime.utc(2026, 10, 7, 7))),
      'Silenced · Paused until Wed 09:00',
      const [],
      step: ResolutionStep.globalDefault,
      silenced: true,
    ),
    Case(
      'pause does not cover an event starting at its end',
      noon,
      RuleSet(quiet: pause),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'expired pause silences nothing',
      plain,
      RuleSet(quiet: PausedUntil(DateTime.utc(2026, 10, 6, 5))),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'mute lets an occurrence turned on through',
      plain,
      RuleSet(quiet: mute, overrides: [onOcc(plain, enabled: true)]),
      'Meeting · this event',
      meetingAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'mute silences an occurrence override that only picks a profile',
      plain,
      RuleSet(
        quiet: mute,
        overrides: [onOcc(plain, profileId: 'quick')],
      ),
      'Silenced · Mute today',
      const [],
      step: ResolutionStep.occurrenceOverride,
      silenced: true,
    ),
    Case(
      'vacation silences Important too',
      plain,
      RuleSet(quiet: vacation, sourceDefaults: {'work': 'important'}),
      'Silenced · Vacation',
      const [],
      step: ResolutionStep.sourceDefault,
      silenced: true,
      profileId: 'important',
    ),
    Case(
      'vacation silences an Important series override',
      recurring,
      RuleSet(
        quiet: vacation,
        overrides: [onSeries('series-1', profileId: 'important')],
      ),
      'Silenced · Vacation',
      const [],
      step: ResolutionStep.seriesOverride,
      silenced: true,
    ),
    Case(
      'vacation lets an occurrence turned on through',
      plain,
      RuleSet(
        quiet: vacation,
        overrides: [onOcc(plain, profileId: 'quick', enabled: true)],
      ),
      'Quick · this event',
      quickAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'quiet mode leaves Silent explanations alone',
      tentative,
      RuleSet(quiet: mute),
      'Silent · tentative',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'quiet mode leaves Off explanations alone',
      plain,
      RuleSet(quiet: vacation, overrides: [onOcc(plain, enabled: false)]),
      'Off · this event',
      const [],
      step: ResolutionStep.occurrenceOverride,
    ),
  ];

  RulesEngine engine() => RulesEngine(zone: johannesburg, clock: () => now);

  runCases(cases, engine);

  test('vacation days follow the local zone (London, BST)', () {
    final london9 = occ(start: DateTime.utc(2026, 10, 9, 23, 30)); // 00:30 10th
    final v = Vacation(LocalDate(2026, 10, 6), LocalDate(2026, 10, 9));
    final londonEngine = RulesEngine(zone: london, clock: () => now);
    expect(londonEngine.resolve(london9, RuleSet(quiet: v)).silenced, isFalse);
    expect(engine().resolve(london9, RuleSet(quiet: v)).silenced, isFalse);
    final late9 = occ(start: DateTime.utc(2026, 10, 9, 22, 30)); // 23:30 BST
    expect(londonEngine.resolve(late9, RuleSet(quiet: v)).silenced, isTrue);
    // Same instant is 00:30 on the 10th in Johannesburg.
    expect(engine().resolve(late9, RuleSet(quiet: v)).silenced, isFalse);
  });
}
