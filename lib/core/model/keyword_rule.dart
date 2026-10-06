import 'event_occurrence.dart';

enum RuleField { title, location, organizer, description, hasJoinLink }

enum RuleMatch { contains, regex }

/// "Title contains *standup* → Quick" (spec §6).
///
/// Matching is case-insensitive. An invalid regex never throws; the rule
/// simply does not match. [RuleField.hasJoinLink] ignores [pattern] and
/// matches when the occurrence has a join URL. For every other field an
/// empty pattern never matches (otherwise a half-typed rule would capture
/// every event).
class KeywordRule {
  KeywordRule({
    required this.id,
    required this.position,
    required this.field,
    this.match = RuleMatch.contains,
    this.pattern = '',
    required this.profileId,
  });

  final String id;

  /// User-defined order; lower runs first.
  final int position;
  final RuleField field;
  final RuleMatch match;
  final String pattern;
  final String profileId;

  late final RegExp? _regex = _compile();

  RegExp? _compile() {
    if (match != RuleMatch.regex || pattern.isEmpty) return null;
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return null;
    }
  }

  /// False only for a regex rule whose pattern does not compile. The rule
  /// editor (Plan 5) uses this to show an error.
  bool get isValid =>
      field == RuleField.hasJoinLink ||
      match != RuleMatch.regex ||
      pattern.isEmpty ||
      _regex != null;

  bool matches(EventOccurrence o) {
    final String? value;
    switch (field) {
      case RuleField.hasJoinLink:
        return o.joinUrl != null;
      case RuleField.title:
        value = o.title;
      case RuleField.location:
        value = o.location;
      case RuleField.organizer:
        value = o.organizer;
      case RuleField.description:
        value = o.description;
    }
    if (value == null || pattern.isEmpty) return false;
    return switch (match) {
      RuleMatch.contains => value.toLowerCase().contains(pattern.toLowerCase()),
      RuleMatch.regex => _regex?.hasMatch(value) ?? false,
    };
  }

  KeywordRule copyWith({
    int? position,
    RuleField? field,
    RuleMatch? match,
    String? pattern,
    String? profileId,
  }) => KeywordRule(
    id: id,
    position: position ?? this.position,
    field: field ?? this.field,
    match: match ?? this.match,
    pattern: pattern ?? this.pattern,
    profileId: profileId ?? this.profileId,
  );

  @override
  bool operator ==(Object other) =>
      other is KeywordRule &&
      other.id == id &&
      other.position == position &&
      other.field == field &&
      other.match == match &&
      other.pattern == pattern &&
      other.profileId == profileId;

  @override
  int get hashCode =>
      Object.hash(id, position, field, match, pattern, profileId);

  @override
  String toString() =>
      'KeywordRule($id #$position ${field.name} ${match.name} "$pattern" '
      '→ $profileId)';
}
