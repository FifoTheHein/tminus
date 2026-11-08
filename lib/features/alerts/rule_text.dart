import '../../core/model/keyword_rule.dart';

/// A rule's field as the rule rows and the rule editor print it.
String ruleFieldLabel(RuleField field) => switch (field) {
  RuleField.title => 'Title',
  RuleField.location => 'Location',
  RuleField.organizer => 'Organizer',
  RuleField.description => 'Description',
  RuleField.hasJoinLink => 'Has Teams link',
};

/// "Title contains standup → Quick" (brief §4). A Teams-link rule has no
/// pattern, so it reads "Has Teams link → Quick".
String ruleText(KeywordRule r, String profileName) {
  final field = ruleFieldLabel(r.field);
  if (r.field == RuleField.hasJoinLink) return '$field → $profileName';
  final how = r.match == RuleMatch.regex ? 'matches' : 'contains';
  return '$field $how ${r.pattern} → $profileName';
}
