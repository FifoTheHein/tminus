/// An online meeting service whose join links [extractJoinUrl] recognises.
enum MeetingService {
  teams('Teams'),
  googleMeet('Google Meet'),
  zoom('Zoom'),
  webex('Webex');

  const MeetingService(this.label);

  /// The name shown to the user: `Teams`, `Google Meet`, `Zoom` or `Webex`.
  final String label;
}

/// The join link of a meeting, from [conference] (Google's own property),
/// then [description], then [location]; null if none holds one.
///
/// Recognises Microsoft Teams, Google Meet, Zoom and Webex links, `https`
/// only (see [meetingServiceOf]). Inside one text the earliest link wins,
/// whatever its service. A link is found as written (Outlook wraps it in
/// `<...>`, and its path is usually percent-encoded, which is kept as is) or
/// wrapped in another link and decoded: fully percent-encoded, as in Outlook
/// Safe Links, or plain right after `q=`, as in a Google redirect. A wrapped
/// link runs to the next `&`. A link ends at whitespace, `<`, `>`, `"` or `'`
/// (a Meet, Zoom or Webex link also where its form ends, unless a query
/// follows), and trailing sentence punctuation is removed.
///
/// A page of one of these services that is not a join link, such as
/// `https://zoom.us/download` or `https://meet.google.com/`, is ignored.
/// Never throws.
String? extractJoinUrl(
  String? description,
  String? location, {
  String? conference,
}) {
  for (final text in [conference, description, location]) {
    final url = text == null ? null : _firstLink(text);
    if (url != null) {
      return url;
    }
  }
  return null;
}

/// The service that [url] is a join link of, or null.
///
/// [url] is a link as [extractJoinUrl] returns it. Null, and any other URL
/// (another host or path on one of these services, `http`, extra text around
/// the link), gives null. Never throws.
MeetingService? meetingServiceOf(String? url) {
  if (url == null) {
    return null;
  }
  for (final (service, link) in _grammars) {
    final match = link.matchAsPrefix(url);
    if (match != null && match.end == url.length) {
      return service;
    }
  }
  return null;
}

// A link ends at whitespace, < > " or ' (written \x27 so that the pattern
// fits in a single-quoted string).
const _linkChar = r'[^\s<>"\x27]';

// The query and fragment of a link, if it has any.
const _query = '(?:[?#]$_linkChar*)?';

// One path segment of a link: up to the next / ? # or the end of the link.
const _segment = r'[^/?#\s<>"\x27]+';

// zoom.us, zoom.com and every subdomain of them.
const _zoomHost = r'(?:[a-z0-9-]+\.)*zoom\.(?:us|com)';

// Every subdomain of webex.com.
const _webexHost = r'(?:[a-z0-9-]+\.)+webex\.com';

// Only the forms below are join links. Anything else on these hosts is not:
// zoom.us/download, a bare meet.google.com, a Teams channel. Nor is tel.meet,
// which is Google's page of phone numbers for a Meet.
final _grammars = <(MeetingService, RegExp)>[
  (
    MeetingService.teams,
    _links([
      // The invite link and the newer /meet/ link, as Outlook writes them.
      r'teams\.microsoft\.com/(?:l/meetup-join|meet)/'
          '$_linkChar+',
      // The newer hosts, which only have /meet/<digits>.
      r'teams\.(?:cloud\.microsoft|live\.com)/meet/\d+(?!\w)'
          '$_query',
    ]),
  ),
  (
    MeetingService.googleMeet,
    _links([
      // meet.google.com/abc-defg-hij, with a query such as ?authuser=0.
      r'meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}(?![\w-])'
          '$_query',
    ]),
  ),
  (
    MeetingService.zoom,
    _links([
      // A meeting (/j/) or a webinar (/w/), with a query such as ?pwd=...
      '$_zoomHost/(?:j|w)/'
          r'\d+(?!\w)'
          '$_query',
      // A personal link.
      '$_zoomHost/my/$_segment$_query',
    ]),
  ),
  (
    MeetingService.webex,
    _links([
      // <site>/j.php?MTID=<id>, which may sit under a folder.
      '$_webexHost(?:/$_segment)*/'
          r'j\.php\?MTID=[\w-]+'
          '$_linkChar*',
      // A personal room.
      '$_webexHost/(?:meet|join)/$_segment$_query',
    ]),
  ),
];

RegExp _links(List<String> forms) =>
    RegExp('https://(?:${forms.join('|')})', caseSensitive: false);

// Where a link can start. A `plain` link is `https://` as written. Two kinds
// are wrapped in another link: `https%3A%2F%2F` (percent-encoded, as in Outlook
// Safe Links) and an `https://` right after `q=` (Google's redirect,
// `https://www.google.com/url?q=https://...`).
final _anchor = RegExp(
  r'(?<plain>(?<!q=)https://)|(?<=q=)https://|https%3A%2F%2F',
  caseSensitive: false,
);

// A wrapped link runs to the next `&`, where the next parameter of the wrapper
// starts.
final _wrappedLink = RegExp(r'[^\s<>"\x27&]+');

const _trailingPunctuation = '>)].,;:!?\'';

/// The earliest join link in [text], whether written plainly or wrapped in
/// another link, or null.
String? _firstLink(String text) {
  for (final anchor in _anchor.allMatches(text)) {
    final url = anchor.namedGroup('plain') != null
        ? _linkAt(text, anchor.start)
        : _wrappedLinkAt(text, anchor.start);
    if (url != null) {
      return url;
    }
  }
  return null;
}

/// The join link that is wrapped in another link and starts at [start] in
/// [text], percent-decoded, or null.
String? _wrappedLinkAt(String text, int start) {
  final wrapped = _wrappedLink.matchAsPrefix(text, start)?[0];
  if (wrapped == null) {
    return null;
  }
  // Malformed percent-encoding: a link that is encoded is skipped (its scheme
  // is still encoded, so no grammar takes it), a plain one after `q=` is used
  // as written.
  return _linkAt(_decode(wrapped) ?? wrapped, 0);
}

/// The join link that starts at [start] in [text], without trailing
/// punctuation, or null.
String? _linkAt(String text, int start) {
  for (final (_, link) in _grammars) {
    final match = link.matchAsPrefix(text, start);
    if (match == null) {
      continue;
    }
    final url = _trimTrailing(match[0]!);
    // Trimming can leave less than a link (`.../meet/.`): only return what
    // meetingServiceOf accepts, so the two never disagree.
    if (meetingServiceOf(url) != null) {
      return url;
    }
  }
  return null;
}

/// [encoded] with its percent-encoding removed; null if it is malformed.
String? _decode(String encoded) {
  try {
    return Uri.decodeComponent(encoded);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

String _trimTrailing(String url) {
  var end = url.length;
  while (end > 0 && _trailingPunctuation.contains(url[end - 1])) {
    end--;
  }
  return url.substring(0, end);
}
