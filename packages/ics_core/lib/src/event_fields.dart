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
