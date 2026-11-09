import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/features/alerts/rule_text.dart';

import 'alerts_test_support.dart';

void main() {
  test('a title rule reads like a sentence', () {
    expect(
      ruleText(keywordRule('r-1', 0, pattern: 'standup'), 'Quick'),
      'Title contains standup → Quick',
    );
  });

  test('a location rule reads like a sentence', () {
    expect(
      ruleText(
        keywordRule('r-1', 0, field: RuleField.location, pattern: 'Boardroom'),
        'Important',
      ),
      'Location contains Boardroom → Important',
    );
  });

  test('an organizer rule reads like a sentence', () {
    expect(
      ruleText(
        keywordRule('r-1', 0, field: RuleField.organizer, pattern: 'HR'),
        'Quick',
      ),
      'Organizer contains HR → Quick',
    );
  });

  test('a description rule reads like a sentence', () {
    expect(
      ruleText(
        keywordRule('r-1', 0, field: RuleField.description, pattern: 'offsite'),
        'Meeting',
      ),
      'Description contains offsite → Meeting',
    );
  });

  test('a Teams-link rule has no pattern in its sentence', () {
    // A pattern kept from an earlier field is not part of what the rule does.
    expect(
      ruleText(
        keywordRule('r-1', 0, field: RuleField.hasJoinLink, pattern: 'left'),
        'Silent',
      ),
      'Has Teams link → Silent',
    );
  });

  test('a regular expression rule says matches, not contains', () {
    expect(
      ruleText(
        keywordRule('r-1', 0, match: RuleMatch.regex, pattern: r'^Stand\w+'),
        'Quick',
      ),
      r'Title matches ^Stand\w+ → Quick',
    );
  });

  test('every field has its own label', () {
    expect(
      [for (final f in RuleField.values) ruleFieldLabel(f)],
      ['Title', 'Location', 'Organizer', 'Description', 'Has Teams link'],
    );
  });
}
