import 'component.dart';
import 'content_line.dart';
import 'model.dart';

/// The unescaped, trimmed TEXT value of [line]; null if absent or blank.
String? textOf(ContentLine? line) {
  if (line == null) {
    return null;
  }
  final text = unescapeText(line.value).trim();
  return text.isEmpty ? null : text;
}

final _cancelledTitle = RegExp(r'^cancell?ed:', caseSensitive: false);

/// True for titles Outlook gives cancelled meetings: `Canceled: …` or
/// `Cancelled: …` (any case, after trimming).
bool isCancelledTitle(String title) => _cancelledTitle.hasMatch(title.trim());

/// X-MICROSOFT-CDO-BUSYSTATUS, else TRANSP:TRANSPARENT → free, else unknown.
///
/// Outlook's WORKINGELSEWHERE counts as busy.
IcsBusyStatus busyStatusOf(Component event) {
  final cdo = event
      .first('X-MICROSOFT-CDO-BUSYSTATUS')
      ?.value
      .trim()
      .toUpperCase();
  switch (cdo) {
    case 'FREE':
      return IcsBusyStatus.free;
    case 'TENTATIVE':
      return IcsBusyStatus.tentative;
    case 'BUSY' || 'WORKINGELSEWHERE':
      return IcsBusyStatus.busy;
    case 'OOF':
      return IcsBusyStatus.oof;
  }
  if (event.first('TRANSP')?.value.trim().toUpperCase() == 'TRANSPARENT') {
    return IcsBusyStatus.free;
  }
  return IcsBusyStatus.unknown;
}

/// ORGANIZER's CN parameter if present, else its address without `mailto:`.
String? organizerOf(ContentLine? line) {
  if (line == null) {
    return null;
  }
  final cn = line.params['CN']?.trim();
  if (cn != null && cn.isNotEmpty) {
    return cn;
  }
  final value = line.value.trim();
  final address = value.toLowerCase().startsWith('mailto:')
      ? value.substring(7)
      : value;
  return address.isEmpty ? null : address;
}

final _teamsDirect = RegExp(
  r'https://teams\.microsoft\.com/(?:l/meetup-join|meet)/[^\s<>"]+',
  caseSensitive: false,
);
final _teamsEncoded = RegExp(
  r'https%3A%2F%2Fteams\.microsoft\.com%2F(?:l%2Fmeetup-join|meet)%2F[^\s<>"&]+',
  caseSensitive: false,
);
const _trailingPunctuation = '>)].,;:!?\'';

/// The first Teams join URL in [description], then in [location].
///
/// Finds `https://teams.microsoft.com/l/meetup-join/…` or the newer
/// `https://teams.microsoft.com/meet/…` as written (Outlook
/// wraps it in `<…>`, and its path is usually percent-encoded, which is kept
/// as is), or fully percent-encoded inside another link such as a Safe Links
/// wrapper (decoded). Trailing `>` and sentence punctuation are removed.
String? extractTeamsJoinUrl(String? description, String? location) {
  for (final text in [description, location]) {
    if (text == null) {
      continue;
    }
    final direct = _teamsDirect.firstMatch(text);
    if (direct != null) {
      return _trimTrailing(direct[0]!);
    }
    final encoded = _teamsEncoded.firstMatch(text);
    if (encoded != null) {
      try {
        return _trimTrailing(Uri.decodeComponent(encoded[0]!));
      } on ArgumentError {
        // Malformed percent-encoding; keep looking.
      }
    }
  }
  return null;
}

String _trimTrailing(String url) {
  var end = url.length;
  while (end > 0 && _trailingPunctuation.contains(url[end - 1])) {
    end--;
  }
  return url.substring(0, end);
}
