import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/keyword_rule.dart';

/// A window tall enough for every row of the Alerts screens to be on screen, so
/// a test can tap whatever it finds.
void useTallWindow(WidgetTester t) {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// The id of the profile that [userProfile] makes.
const focusBlockId = 'p-0a1b2c3d4e5f';

/// A profile of the user's own, not a built-in one.
AlertProfile userProfile({
  String id = focusBlockId,
  String name = 'Focus block',
  List<AlertSpec> alerts = const [AlertSpec(5, AlertStrength.headsUp)],
  SoundSettings sound = const SoundSettings(),
  bool ringsInQuietMode = false,
}) => AlertProfile(
  id: id,
  name: name,
  alerts: alerts,
  sound: sound,
  ringsInQuietMode: ringsInQuietMode,
);

/// A keyword rule; a title rule that contains `standup` unless told otherwise.
KeywordRule keywordRule(
  String id,
  int position, {
  RuleField field = RuleField.title,
  RuleMatch match = RuleMatch.contains,
  String pattern = 'standup',
  String profileId = BuiltInProfiles.quickId,
}) => KeywordRule(
  id: id,
  position: position,
  field: field,
  match: match,
  pattern: pattern,
  profileId: profileId,
);
