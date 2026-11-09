import '../../core/model/alert_profile.dart';
import '../../core/rules/resolved_occurrence.dart';

/// Why an event rings the way it does, as one sentence for the event sheet
/// (mockup 2a, brief §3).
///
/// It is read from the rules engine's own explanation line (`Quick · rule:
/// "standup"`, the Agenda's grey reason), so the card and the sheet always say
/// the same thing. The profile's name sits between `**` markers: [whyPieces]
/// splits the sentence so that the sheet can set that part in bold.
///
/// [sourceName] is the source whose default profile applied, for the
/// source-default case; null reads as "this calendar".
String whyText(ResolvedOccurrence r, {required String? sourceName}) {
  final name = _plain(r.profile.name);
  final generic = 'Using **$name**.';

  if (r.silenced) {
    final label = _after(r.explanation, 'Silenced') ?? r.explanation;
    return 'It would use **$name**, but quiet mode is on: ${_plain(label)}.';
  }

  return switch (r.step) {
    ResolutionStep.occurrenceOverride => _override(r, name, series: false),
    ResolutionStep.seriesOverride => _override(r, name, series: true),
    ResolutionStep.skipFilter => _skipFilter(r.explanation) ?? generic,
    ResolutionStep.keywordRule => _rule(r, name) ?? generic,
    ResolutionStep.sourceDefault =>
      "Using **$name**. It's the default profile for "
          '${_plain(sourceName ?? 'this calendar')}.',
    ResolutionStep.globalDefault =>
      "Using **$name** because no rule matched. It's your default profile.",
  };
}

/// One piece of a sentence from [whyText]. The [bold] pieces are the ones the
/// `**` markers wrapped.
typedef WhyPiece = ({String text, bool bold});

/// Splits a marked sentence at its `**` markers, in order, without empty
/// pieces.
List<WhyPiece> whyPieces(String marked) {
  final parts = marked.split('**');
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty) (text: parts[i], bold: i.isOdd),
  ];
}

/// The engine joins the profile (or `Off`, `Custom`, `Silenced`) and the reason
/// with this.
const _separator = ' · ';

/// What follows `<prefix> · ` in [explanation]; null when it does not start so.
String? _after(String explanation, String prefix) {
  final head = '$prefix$_separator';
  return explanation.startsWith(head)
      ? explanation.substring(head.length)
      : null;
}

/// What follows the last ` · `. The engine's own reasons (`this event`,
/// `all-day`, `free`, ...) never hold one, so this is safe where the first part
/// is the profile's name, which may.
String _lastPart(String explanation) {
  final at = explanation.lastIndexOf(_separator);
  return at < 0 ? explanation : explanation.substring(at + _separator.length);
}

/// User text (a profile's name, a rule's words, a source's name) goes between
/// the markers as it is, but a `**` of its own would switch the bold on or off.
/// A zero-width space between the asterisks keeps what the user typed on the
/// screen and out of the markup.
String _plain(String text) => text.replaceAll('**', '*\u200B*');

String _override(ResolvedOccurrence r, String name, {required bool series}) {
  // `Off · …` is the engine's own text for a switched-off event, and it is
  // always Silent. A user's profile that happens to be called "Off" is another
  // profile, so it reads as a choice. The same goes for "Custom".
  final off =
      r.profile.id == BuiltInProfiles.silentId &&
      _after(r.explanation, 'Off') != null;
  if (off) {
    return series
        ? 'You turned this series off.'
        : 'You turned this event off.';
  }
  final custom =
      r.profile.name != 'Custom' && _after(r.explanation, 'Custom') != null;
  if (custom) {
    return series
        ? 'You set custom alerts for the whole series.'
        : 'You set custom alerts for this event.';
  }
  return series
      ? 'You chose **$name** for the whole series.'
      : 'You chose **$name** for this event.';
}

String? _skipFilter(String explanation) => switch (_lastPart(explanation)) {
  'all-day' => 'All-day events are skipped (Alerts → Rules).',
  'free' => "It's marked free, and free events are skipped.",
  'tentative' => "It's tentative, and tentative events are skipped.",
  'cancelled' => 'It was cancelled.',
  'declined' => 'You declined it.',
  _ => null,
};

/// `rule: Teams link` or `rule: "<words>"`, after the profile's name. The words
/// are the user's, so they may hold ` · ` or a quote: they are everything
/// between the first quote and the last.
String? _rule(ResolvedOccurrence r, String name) {
  final rule = _after(r.explanation, r.profile.name);
  if (rule == null) return null;
  if (rule == 'rule: Teams link') {
    return 'Using **$name** because it has a Teams link.';
  }
  const open = 'rule: "';
  if (rule.length > open.length &&
      rule.startsWith(open) &&
      rule.endsWith('"')) {
    final words = rule.substring(open.length, rule.length - 1);
    return 'Using **$name** because the rule “${_plain(words)}” matched.';
  }
  return null;
}
