import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ics_core/ics_core.dart';
import 'package:tminus/app/links.dart';

/// Where GitHub Pages serves `docs/` (Plan 6). What these tests read is what
/// goes online: the policy page, and the feed Play's reviewers add.
const _siteRoot = 'https://fifothehein.github.io/tminus';

/// The front matter of the Jekyll page at [path]: the `key: value` lines
/// between its first two `---` lines.
Map<String, String> _frontMatter(String path) {
  final lines = const LineSplitter().convert(File(path).readAsStringSync());
  expect(lines.first, '---', reason: '$path has no front matter');
  final end = lines.indexOf('---', 1);
  expect(end, greaterThan(0), reason: '$path: the front matter never ends');
  return {
    for (final line in lines.sublist(1, end))
      if (line.contains(':'))
        line.substring(0, line.indexOf(':')).trim(): line
            .substring(line.indexOf(':') + 1)
            .trim(),
  };
}

/// The meetings of the demo feed that fall in the 24 hours from [now].
List<IcsOccurrence> _demoDay(String feed, DateTime now) {
  final result = expandIcs(
    feed,
    windowStartUtc: now,
    windowEndUtc: now.add(const Duration(hours: 24)),
    deviceZone: 'Africa/Johannesburg',
  );
  expect(result.issues, isEmpty, reason: 'the feed has a broken VEVENT');
  return result.occurrences;
}

void main() {
  test("the privacy policy URL matches the page's permalink", () {
    final permalink = _frontMatter('docs/privacy.md')['permalink'];

    expect(permalink, isNotNull, reason: 'docs/privacy.md has no permalink');
    expect(privacyPolicyUrl, '$_siteRoot$permalink');
  });

  test('the policy page is finished and points at the issues page', () {
    final page = File('docs/privacy.md').readAsStringSync();

    expect(
      page,
      isNot(contains('<date>')),
      reason: 'the date is a placeholder',
    );
    // The whole link, not the start of a longer one.
    expect(page, contains(RegExp('${RegExp.escape(issuesUrl)}(?![\\w/-])')));
  });

  test('the demo feed parses and has a meeting in every two-hour window', () {
    final feed = File('docs/play/demo.ics').readAsStringSync();

    // From the top of an even hour, from the moment a meeting ends (the
    // longest wait there is), from just after that, in the middle of the day,
    // and across midnight, the new year and a month end. None is inside a
    // meeting: one that is running at the start of the window comes on top of
    // the twelve.
    for (final now in [
      DateTime.utc(2026, 11, 14, 10),
      DateTime.utc(2026, 11, 14, 10, 30),
      DateTime.utc(2026, 11, 14, 10, 45),
      DateTime.utc(2026, 11, 14, 13, 7),
      DateTime.utc(2026, 12, 31, 23, 59),
      DateTime.utc(2027, 3, 1, 1, 30),
    ]) {
      final starts = [for (final o in _demoDay(feed, now)) o.startUtc];

      expect(starts, hasLength(12), reason: '$now');
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i].difference(starts[i - 1]),
          const Duration(hours: 2),
          reason: '$now: meeting ${i + 1}',
        );
      }
      // A reviewer in any zone sees a meeting within two hours.
      expect(
        starts.first.difference(now),
        lessThan(const Duration(hours: 2)),
        reason: '$now',
      );
    }
  });

  test('the demo feed has no link and no Teams meeting, one Free meeting and '
      'one location', () {
    final feed = File('docs/play/demo.ics').readAsStringSync();
    final day = _demoDay(feed, DateTime.utc(2026, 11, 14));

    // No link anywhere, and nothing that points into Microsoft.
    expect(feed.toLowerCase(), isNot(contains('http')));
    expect(feed.toLowerCase(), isNot(contains('teams')));
    expect(day.map((o) => o.joinUrl), everyElement(isNull));
    // Stable ids, one per even hour.
    expect(day.map((o) => o.uid), [
      for (var hour = 0; hour < 24; hour += 2)
        'demo-${hour.toString().padLeft(2, '0')}@tminus.example',
    ]);
    // Each meeting is half an hour long.
    expect(
      day.map((o) => o.endUtc.difference(o.startUtc)),
      everyElement(const Duration(minutes: 30)),
    );
    // One shows as Free, for the Free skip filter, and one has a place.
    expect(day.where((o) => o.busyStatus == IcsBusyStatus.free), hasLength(1));
    expect(day.map((o) => o.location).whereType<String>(), ['Room 4']);
  });
}
