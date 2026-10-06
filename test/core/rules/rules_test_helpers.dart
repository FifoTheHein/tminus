import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';

/// 08:00 SAST on Tue 6 Oct 2026. The default event starts at 10:00 SAST.
final now = DateTime.utc(2026, 10, 6, 6);

const meetingAlerts = [
  AlertSpec(10, AlertStrength.headsUp),
  AlertSpec(1, AlertStrength.alarm),
];
const quickAlerts = [AlertSpec(1, AlertStrength.alarm)];
const importantAlerts = [
  AlertSpec(30, AlertStrength.headsUp),
  AlertSpec(10, AlertStrength.headsUp),
  AlertSpec(2, AlertStrength.alarm),
];
const custom = [AlertSpec(5, AlertStrength.alarm)];

KeywordRule titleRule(
  String pattern,
  String profileId, {
  int position = 0,
  String? id,
}) => KeywordRule(
  id: id ?? 'r-$pattern',
  position: position,
  field: RuleField.title,
  pattern: pattern,
  profileId: profileId,
);

EventOverride onOcc(
  EventOccurrence o, {
  String? profileId,
  List<AlertSpec>? customAlerts,
  bool? enabled,
}) => EventOverride(
  scope: OverrideScope.occurrence,
  target: o.key,
  profileId: profileId,
  customAlerts: customAlerts,
  enabled: enabled,
);

EventOverride onSeries(
  String seriesUid, {
  String? profileId,
  List<AlertSpec>? customAlerts,
  bool? enabled,
}) => EventOverride(
  scope: OverrideScope.series,
  target: seriesUid,
  profileId: profileId,
  customAlerts: customAlerts,
  enabled: enabled,
);

class Case {
  Case(
    this.name,
    this.event,
    this.rules,
    this.explanation,
    this.alerts, {
    required this.step,
    this.silenced = false,
    this.profileId,
  });

  final String name;
  final EventOccurrence event;
  final RuleSet rules;
  final String explanation;
  final List<AlertSpec> alerts;
  final ResolutionStep step;
  final bool silenced;
  final String? profileId;
}

/// One test per case: resolves [Case.event] and checks every field.
void runCases(List<Case> cases, RulesEngine Function() engine) {
  for (final c in cases) {
    test(c.name, () {
      final r = engine().resolve(c.event, c.rules);
      expect(r.explanation, c.explanation);
      expect(r.alerts, c.alerts);
      expect(r.silenced, c.silenced);
      expect(r.step, c.step);
      expect(r.occurrence, same(c.event));
      if (c.profileId != null) expect(r.profile.id, c.profileId);
    });
  }
}
