import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/links.dart';

// The Buy Me a Coffee link (spec 2026-11-27-buy-me-a-coffee-design.md). Google
// Play's Payments policy rejects donation links in an app, even indirect ones,
// so the link lives only on the website's home page and the GitHub repo. The
// app, the privacy policy it opens (and that page's template) and the Play
// listing text never carry it.

const _coffeeUrl = 'https://buymeacoffee.com/fifothehein';

/// Buy Me a Coffee's domains and short links.
final _coffeeLink = RegExp(r'buymeacoffee|coff\.ee|bmc\.link');

/// A coffee link, or the words, with any spacing.
final _coffee = RegExp(
  r'buymeacoffee|coff\.ee|bmc\.link|buy\s*me\s*a\s*coffee',
  caseSensitive: false,
);

/// A link to the website or the GitHub repo, both of which now show the coffee
/// link. The `[^\s'"`)]*` takes the rest of the link.
final _ownSite = RegExp(
  r'https?://(fifothehein\.github\.io|github\.com/fifothehein)[^\s'
  "'"
  r'"`)<]*',
  caseSensitive: false,
);

/// Everything that ships in the app: its code, its Android resources, its
/// bundled assets and the parser package compiled into it.
const _appRoots = [
  'lib',
  'android/app/src/main',
  'assets',
  'packages/ics_core/lib',
];

/// [path] as text. Latin-1 reads any byte, so the PNGs under `res/` do not
/// throw, and the ASCII markers are still found.
String _read(String path) => latin1.decode(File(path).readAsBytesSync());

/// Every file under [_appRoots], with `/` as the separator.
List<String> _appFiles() => [
  for (final root in _appRoots)
    for (final entity in Directory(root).listSync(recursive: true))
      if (entity is File) entity.path.replaceAll(r'\', '/'),
];

/// The text of [html] from [start] to the end of [end].
String _slice(String html, String start, String end) {
  final from = html.indexOf(start);
  expect(from, isNot(-1), reason: 'no $start in the home page');
  final to = html.indexOf(end, from);
  expect(to, isNot(-1), reason: 'no $end after $start in the home page');
  return html.substring(from, to + end.length);
}

void main() {
  test('the app and the pages it opens never mention Buy Me a Coffee', () {
    final files = _appFiles();
    // The walk found the app's code, not an empty folder.
    expect(files, contains('lib/app/links.dart'));

    for (final path in [
      ...files,
      'docs/privacy.md',
      'docs/_layouts/page.html',
    ]) {
      expect(_read(path), isNot(contains(_coffee)), reason: path);
    }
  });

  test('the Play listing text never links Buy Me a Coffee', () {
    // listing.md names it once, in the note that says why it is left out.
    expect(
      _read('docs/play/listing.md').toLowerCase(),
      isNot(contains(_coffeeLink)),
    );
  });

  test('the app links the website and the repo only through the privacy '
      'policy and issues links', () {
    // A Website or Source button in the app would lead straight to the coffee
    // link: the rejected approach 3 of the spec.
    for (final path in _appFiles()) {
      for (final match in _ownSite.allMatches(_read(path))) {
        expect(
          [privacyPolicyUrl, issuesUrl],
          contains(match.group(0)),
          reason: '$path links ${match.group(0)}',
        );
      }
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

  test('FUNDING.yml names Buy Me a Coffee', () {
    final funding = const LineSplitter().convert(
      File('.github/FUNDING.yml').readAsStringSync(),
    );

    expect(funding, contains('buy_me_a_coffee: fifothehein'));
  });
}
