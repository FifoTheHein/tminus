import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Buy Me a Coffee link (spec 2026-11-27-buy-me-a-coffee-design.md). Google
// Play's Payments policy rejects donation links in an app, even indirect ones,
// so the link lives only on the website's home page and the GitHub repo. The
// app, the privacy policy it opens (and that page's template) and the Play
// listing text never carry it.

const _coffee = 'buymeacoffee';
const _coffeeUrl = 'https://buymeacoffee.com/fifothehein';

/// [path] as text. Latin-1 reads any byte, so the PNGs under `res/` do not
/// throw, and the ASCII marker is still found.
String _read(String path) => latin1.decode(File(path).readAsBytesSync());

/// The text of [html] from [start] to the end of [end].
String _slice(String html, String start, String end) {
  final from = html.indexOf(start);
  expect(from, isNot(-1), reason: 'no $start in the home page');
  final to = html.indexOf(end, from);
  expect(to, isNot(-1), reason: 'no $end after $start in the home page');
  return html.substring(from, to + end.length);
}

void main() {
  test('the app and the pages it opens never link to Buy Me a Coffee', () {
    final paths = [
      for (final root in ['lib', 'android/app/src/main'])
        for (final entity in Directory(root).listSync(recursive: true))
          if (entity is File) entity.path,
      'docs/privacy.md',
      'docs/_layouts/page.html',
      'docs/play/listing.md',
    ];

    expect(paths, contains('docs/privacy.md'));
    for (final path in paths) {
      expect(_read(path).toLowerCase(), isNot(contains(_coffee)), reason: path);
    }
  });

  test('the home page links Buy Me a Coffee in its footer and support '
      'section', () {
    final html = File('docs/index.html').readAsStringSync();

    expect(
      RegExp(RegExp.escape(_coffeeUrl)).allMatches(html),
      hasLength(2),
      reason: 'once in the footer and once in the support section',
    );
    expect(html, contains('id="support"'));
    expect(_slice(html, '<footer>', '</footer>'), contains(_coffeeUrl));
    expect(
      _slice(html, '<section id="support"', '</section>'),
      contains(_coffeeUrl),
    );
    expect(_slice(html, '<header', '</header>'), isNot(contains(_coffee)));
  });

  test('GitHub shows a Sponsor button for Buy Me a Coffee', () {
    final funding = const LineSplitter().convert(
      File('.github/FUNDING.yml').readAsStringSync(),
    );

    expect(funding, contains('buy_me_a_coffee: fifothehein'));
  });
}
