import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the app's text lives, and the file types that hold it under each. The
/// Android manifest is in `android/app/src/main`, so its labels are read too.
const _roots = {
  'lib': ['.dart'],
  'packages/ics_core/lib': ['.dart'],
  'android/app/src/main': ['.kt', '.xml'],
};

/// U+2014, built from its code point so that this file holds none itself.
final _emDash = String.fromCharCode(0x2014);

/// The same character written as an escape: `\u2014` or `\u{2014}` in Dart and
/// Kotlin, `&#8212;`, `&#x2014;` or `&mdash;` in XML.
final _escaped = RegExp(
  r'\\u\{?0*2014\}?|&#0*8212;|&#x0*2014;|&mdash;',
  caseSensitive: false,
);

final _xmlComment = RegExp(r'<!--.*?-->', dotAll: true);

/// A line that is only a comment: `//` (so `///` too), `/*`, or the `*` that
/// starts the body lines of a block comment.
bool _isCommentLine(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('/*') || t.startsWith('*');
}

/// The lines of [text], the contents of the file at [path], that hold an em
/// dash outside a comment, each as `path:line: the line`.
List<String> _emDashLines(String path, String text) {
  final xml = path.endsWith('.xml');
  // An XML comment can span lines, so it is blanked out first, keeping the
  // line count.
  final code = xml
      ? text.replaceAllMapped(
          _xmlComment,
          (m) => '\n' * '\n'.allMatches(m[0]!).length,
        )
      : text;
  final lines = const LineSplitter().convert(code);
  return [
    for (var i = 0; i < lines.length; i++)
      if ((xml || !_isCommentLine(lines[i])) &&
          (lines[i].contains(_emDash) || _escaped.hasMatch(lines[i])))
        '$path:${i + 1}: ${lines[i].trim()}',
  ];
}

/// App text has no em dashes (U+2014). Where a sentence wants a break it uses
/// a colon, a comma, a full stop or parentheses.
///
/// This reads the code that puts text on the screen or into a notification and
/// names every file:line that holds one. It is a line-based check, not a
/// parser: a line that starts a comment is skipped, and so is an XML comment,
/// but a comment at the end of a code line is read as code, so reword it. An
/// escaped em dash counts as well.
void main() {
  test('no text in the app holds an em dash', () {
    final found = <String>[];
    for (final root in _roots.keys) {
      final extensions = _roots[root]!;
      final dir = Directory(root);
      expect(
        dir.existsSync(),
        isTrue,
        reason: '$root is missing: run the tests from the repository root',
      );
      final files = [
        for (final entry in dir.listSync(recursive: true))
          if (entry is File && extensions.any(entry.path.endsWith)) entry,
      ];
      expect(files, isNotEmpty, reason: 'no $extensions files under $root');
      for (final file in files) {
        found.addAll(
          _emDashLines(
            file.path.replaceAll(r'\', '/'),
            file.readAsStringSync(),
          ),
        );
      }
    }
    found.sort();
    if (found.isNotEmpty) {
      fail(
        'App text must not hold an em dash (U+2014). Use a colon, a comma, a '
        'full stop or parentheses instead:\n'
        '${found.map((line) => '  $line').join('\n')}',
      );
    }
  });
}
