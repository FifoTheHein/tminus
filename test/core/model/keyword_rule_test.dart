import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/keyword_rule.dart';

import '../fixtures.dart';

void main() {
  KeywordRule rule(
    RuleField field,
    String pattern, {
    RuleMatch match = RuleMatch.contains,
  }) => KeywordRule(
    id: 'r',
    position: 0,
    field: field,
    match: match,
    pattern: pattern,
    profileId: 'quick',
  );

  final event = occ(
    title: 'Daily Standup',
    location: 'Boardroom 2',
    organizer: 'Thandi M.',
    description: 'Agenda: blockers',
  );

  final cases = <(String, KeywordRule, bool)>[
    ('title contains, any case', rule(RuleField.title, 'STANDUP'), true),
    ('title contains, no match', rule(RuleField.title, 'retro'), false),
    ('location contains', rule(RuleField.location, 'boardroom'), true),
    ('organizer contains', rule(RuleField.organizer, 'thandi'), true),
    ('description contains', rule(RuleField.description, 'BLOCKERS'), true),
    ('empty pattern never matches', rule(RuleField.title, ''), false),
    (
      'regex, case-insensitive',
      rule(RuleField.title, r'^daily\s+stand', match: RuleMatch.regex),
      true,
    ),
    (
      'regex, no match',
      rule(RuleField.title, r'^standup', match: RuleMatch.regex),
      false,
    ),
    (
      'invalid regex does not throw, does not match',
      rule(RuleField.title, r'stand(up', match: RuleMatch.regex),
      false,
    ),
    ('hasJoinLink without link', rule(RuleField.hasJoinLink, 'ignored'), false),
  ];

  for (final (name, r, expected) in cases) {
    test(name, () => expect(r.matches(event), expected));
  }

  test('null field never matches', () {
    expect(rule(RuleField.location, 'x').matches(occ()), isFalse);
  });

  test('hasJoinLink ignores the pattern and matches any join URL', () {
    final teams = occ(joinUrl: 'https://teams.microsoft.com/l/meetup-join/1');
    expect(rule(RuleField.hasJoinLink, '').matches(teams), isTrue);
    expect(rule(RuleField.hasJoinLink, 'nomatch').matches(teams), isTrue);
  });

  test('isValid flags only an uncompilable regex', () {
    expect(
      rule(RuleField.title, 'a(', match: RuleMatch.regex).isValid,
      isFalse,
    );
    expect(rule(RuleField.title, 'a(').isValid, isTrue);
    expect(rule(RuleField.title, 'a+', match: RuleMatch.regex).isValid, isTrue);
  });
}
