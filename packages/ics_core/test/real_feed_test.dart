// The user's real published Outlook feed, scrubbed by tool/scrub_feed.dart.
// Answers spec §12.3: does the feed carry Teams join links?
import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import 'support.dart';

DateTime _header(String text, String name) {
  final m = RegExp(
    '^$name:(\\d{8}T\\d{6}Z)\$',
    multiLine: true,
  ).firstMatch(text);
  final v = m![1]!;
  return DateTime.utc(
    int.parse(v.substring(0, 4)),
    int.parse(v.substring(4, 6)),
    int.parse(v.substring(6, 8)),
    int.parse(v.substring(9, 11)),
    int.parse(v.substring(11, 13)),
    int.parse(v.substring(13, 15)),
  );
}

void main() {
  final text = fixture('real_feed_scrubbed.ics');
  final captured = _header(text, 'X-TMINUS-CAPTURED');
  final rawTeamsEvents = int.parse(
    RegExp(
      r'^X-TMINUS-RAW-TEAMS-EVENTS:(\d+)$',
      multiLine: true,
    ).firstMatch(text)![1]!,
  );

  IcsResult expand(Duration before, Duration after) => expandIcs(
    text,
    windowStartUtc: captured.subtract(before),
    windowEndUtc: captured.add(after),
    deviceZone: 'Africa/Johannesburg',
  );

  // The app's own window (spec §5) and a wide one that sees the whole feed.
  final appWindow = expand(const Duration(hours: 1), const Duration(days: 7));
  final wide = expand(const Duration(days: 400), const Duration(days: 400));

  test('parses with zero issues', () {
    expect(wide.issues, isEmpty);
    expect(appWindow.issues, isEmpty);
  });

  test('yields occurrences', () {
    expect(wide.occurrences, isNotEmpty);
  });

  test('every occurrence is well formed', () {
    for (final o in wide.occurrences) {
      expect(o.endUtc.isBefore(o.startUtc), isFalse, reason: '$o');
      expect(o.startUtc.isUtc && o.endUtc.isUtc, isTrue, reason: '$o');
    }
  });

  test('Teams join links are found exactly when the raw feed had them '
      '(spec §12.3)', () {
    final linked = wide.occurrences.where((o) => o.joinUrl != null);
    expect(linked.isNotEmpty, rawTeamsEvents > 0);
  });
}
