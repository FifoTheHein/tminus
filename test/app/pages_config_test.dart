import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// What GitHub Pages publishes (Plan 6). It builds `docs/` with Jekyll, and with
// no config it serves every file in it, the plans and specs included.
// `docs/_config.yml` keeps everything but the public pages out of the site.

/// The pages the site serves, as paths under `docs/`: the home page, the
/// privacy policy and the demo feed that Play's reviewers add. A new public page
/// is added here, and is left out of the `exclude:` list.
const _publicPages = ['index.md', 'privacy.md', 'play/demo.ics'];

/// A relative path of plain names. The `exclude:` entries must look like this,
/// because the test compares them as text and does not read Jekyll's globs.
final _plainPath = RegExp(r'^(?!.*\.\.)\w[\w.\-/]*$');

/// The entries of the `exclude:` list in `docs/_config.yml`, each without a
/// trailing slash. It reads only what that file uses: a block list under a
/// top-level `exclude:` key, one `- entry` per line, with comments and blank
/// lines allowed. Any other shape fails the test, because a list that is read
/// wrongly would let it pass by accident.
List<String> _excludes() {
  final entries = <String>[];
  var inExclude = false;
  final lines = const LineSplitter().convert(
    File('docs/_config.yml').readAsStringSync(),
  );
  for (final line in lines) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    if (!text.startsWith('- ')) {
      // A key. Only `exclude:` is read, and only as a block list.
      inExclude = text == 'exclude:';
      if (text.startsWith('exclude:') && !inExclude) {
        fail('docs/_config.yml: write exclude as a block list of "- entry"');
      }
      continue;
    }
    if (!inExclude) continue;
    var entry = text.substring(2).split(' #').first.trim();
    final quoted =
        entry.length >= 2 &&
        (entry.startsWith("'") || entry.startsWith('"')) &&
        entry.endsWith(entry[0]);
    if (quoted) entry = entry.substring(1, entry.length - 1);
    if (entry.endsWith('/')) entry = entry.substring(0, entry.length - 1);
    expect(
      entry,
      matches(_plainPath),
      reason: 'the exclude entry "$entry" is not a plain relative path',
    );
    entries.add(entry);
  }
  expect(entries, isNotEmpty, reason: 'docs/_config.yml excludes nothing');
  return entries;
}

/// Whether `exclude:` keeps [path] out of the site: an entry names the path
/// itself or a folder that holds it.
bool _excluded(String path, List<String> entries) =>
    entries.any((e) => path == e || path.startsWith('$e/'));

/// The entries that could keep [path] out of the site in some Jekyll version.
/// Besides the rule of [_excluded], some versions take an entry as a plain
/// prefix of the path, so that `design` would also catch `design-brief.md`. The
/// public pages must be safe from both readings.
List<String> _mayExclude(String path, List<String> entries) => [
  for (final e in entries)
    if (path.startsWith(e)) e,
];

/// Jekyll never publishes a file or a folder whose name starts with `.`, `_`,
/// `#` or `~`, or ends with `~`, whatever the config says. `docs/_config.yml`
/// is one.
bool _neverPublished(String path) => path
    .split('/')
    .any((name) => '._#~'.contains(name[0]) || name.endsWith('~'));

void main() {
  test('the site publishes only the public pages', () {
    final entries = _excludes();

    for (final page in _publicPages) {
      expect(
        File('docs/$page').existsSync(),
        isTrue,
        reason: 'docs/$page is missing',
      );
      expect(
        _mayExclude(page, entries),
        isEmpty,
        reason: 'docs/_config.yml would keep docs/$page out of the site',
      );
    }
    for (final path in const [
      'superpowers',
      'superpowers/specs/2026-10-06-tminus-design.md',
      'design',
      'design/design-system.png',
      'design-brief.md',
      'play/listing.md',
      'play/declarations.md',
      'play/release.md',
      'play/icon-512.png',
      'play/feature-graphic.png',
      'play/screenshots',
      'play/screenshots/1-agenda.png',
    ]) {
      expect(
        _excluded(path, entries),
        isTrue,
        reason: 'docs/_config.yml does not keep docs/$path out of the site',
      );
    }
  });

  test('every other file under docs is kept out of the site', () {
    final entries = _excludes();
    final files = [
      for (final entity in Directory('docs').listSync(recursive: true))
        if (entity is File)
          entity.path.replaceAll(r'\', '/').replaceFirst('docs/', ''),
    ];

    final published = [
      for (final file in files)
        if (!_neverPublished(file) && !_excluded(file, entries)) file,
    ];

    expect(
      published,
      unorderedEquals(_publicPages),
      reason:
          'GitHub Pages would publish exactly these files. Add each new file '
          'that is not a public page to the exclude list in docs/_config.yml.',
    );
  });
}
