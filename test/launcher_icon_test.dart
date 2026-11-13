import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the Android resources live, from the repository root.
const _res = 'android/app/src/main/res';

/// The legacy launcher icon at each density, in pixels.
const _legacySizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// The eight bytes every PNG file starts with.
const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// PNG colour type 6 is RGBA. The legacy icons need the alpha channel for the
/// transparent corners of their circular mask (Flutter's default icons are
/// palette PNGs, type 3), and the store icon is saved in the same format.
const _pngRgba = 6;

/// What the adaptive icon points each of its layers at.
const _layers = {
  'background': '@color/tminus_dark_primaryContainer',
  'foreground': '@drawable/ic_launcher_foreground',
  'monochrome': '@drawable/ic_launcher_monochrome',
};

/// The size and the viewport of both vector layers: the 108 dp canvas.
const _vectorSize = {
  'width': '108dp',
  'height': '108dp',
  'viewportWidth': '108',
  'viewportHeight': '108',
};

// The path data of the three shapes, the same in both vector layers: the track
// (a full circle), the arc (270 degrees of it, from 12 o'clock clockwise to
// 9 o'clock) and the T- mark (its bar, its stem and the minus).
const _trackPath = 'M54,28 A26,26 0 1,1 54,80 A26,26 0 1,1 54,28';
const _arcPath = 'M54,28 A26,26 0 1,1 28,54';
const _markPath =
    'M38.325,44.65h18.7v4.4h-18.7z M45.475,44.65h4.4v18.7h-4.4z '
    'M59.775,52.35h9.9v4.4h-9.9z';

const _white = '#FFFFFFFF';

/// Every attribute of the foreground's shapes, in drawing order: the track is
/// drawn first, then the arc over it, then the T- mark.
const _foregroundPaths = [
  // The track.
  {
    'pathData': _trackPath,
    'strokeColor': '@color/tminus_dark_surface',
    'strokeAlpha': '0.35',
    'strokeWidth': '9',
  },
  // The arc.
  {
    'pathData': _arcPath,
    'strokeColor': '@color/tminus_dark_primary',
    'strokeLineCap': 'round',
    'strokeWidth': '9',
  },
  // The T- mark.
  {'pathData': _markPath, 'fillColor': '@color/tminus_dark_onPrimaryContainer'},
];

/// Every attribute of the monochrome layer's shapes: the same three shapes in
/// opaque white, which the launcher tints, with the track fainter.
const _monochromePaths = [
  // The track.
  {
    'pathData': _trackPath,
    'strokeColor': _white,
    'strokeAlpha': '0.3',
    'strokeWidth': '9',
  },
  // The arc.
  {
    'pathData': _arcPath,
    'strokeColor': _white,
    'strokeLineCap': 'round',
    'strokeWidth': '9',
  },
  // The T- mark.
  {'pathData': _markPath, 'fillColor': _white},
];

final _xmlComment = RegExp(r'<!--.*?-->', dotAll: true);

/// An XML resource without its comments, so commented-out code does not count.
String _readXml(String path) =>
    File(path).readAsStringSync().replaceAll(_xmlComment, '');

/// The `android:drawable` of the adaptive icon's [layer], or null if none.
String? _layerDrawable(String adaptiveIcon, String layer) =>
    RegExp('<$layer\\s[^>]*android:drawable="([^"]+)"')
        .firstMatch(adaptiveIcon)
        ?.group(1);

/// Whether a `@drawable/name` or `@color/name` reference names a resource that
/// exists.
bool _resolves(String reference, String colorsXml) {
  final match = RegExp(r'^@(drawable|color)/(\w+)$').firstMatch(reference);
  if (match == null) return false;
  final name = match.group(2)!;
  return match.group(1) == 'drawable'
      ? File('$_res/drawable/$name.xml').existsSync()
      : colorsXml.contains('<color name="$name">');
}

/// The `android:` attributes of an element's start tag, without the prefix.
Map<String, String> _attributes(String startTag) => {
  for (final m in RegExp(r'android:(\w+)="([^"]*)"').allMatches(startTag))
    m.group(1)!: m.group(2)!,
};

/// The attributes of a vector drawable's `<vector>` element: its size and its
/// viewport.
Map<String, String> _vector(String xml) {
  final startTag = RegExp(r'<vector\b[^>]*>').firstMatch(xml)?.group(0);
  return startTag == null ? {} : _attributes(startTag);
}

/// The attributes of every `<path>` in a vector drawable, in drawing order.
List<Map<String, String>> _paths(String xml) => [
  for (final m in RegExp(r'<path\b[^>]*>').allMatches(xml))
    _attributes(m.group(0)!),
];

/// The width, height and colour type from the IHDR chunk of the PNG at [path].
({int width, int height, int colorType}) _pngHeader(String path) {
  expect(File(path).existsSync(), isTrue, reason: '$path is missing');
  final bytes = File(path).readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(26), reason: '$path is too short');
  // The signature, then the IHDR chunk: its length, "IHDR", the width, the
  // height, the bit depth and the colour type.
  expect(bytes.sublist(0, 8), _pngSignature, reason: '$path is not a PNG');
  expect(
    String.fromCharCodes(bytes.sublist(12, 16)),
    'IHDR',
    reason: '$path does not start with an IHDR chunk',
  );
  int uint32(int at) =>
      (bytes[at] << 24) |
      (bytes[at + 1] << 16) |
      (bytes[at + 2] << 8) |
      bytes[at + 3];
  return (width: uint32(16), height: uint32(20), colorType: bytes[25]);
}

/// The launcher icon, pinned to the chosen design. The adaptive icon points a
/// token background, the foreground and the monochrome layer at their
/// resources. Each vector layer holds three shapes in drawing order, and every
/// attribute of every shape is pinned on its own element: its exact path data,
/// colour, alpha, stroke width and line cap. The legacy PNGs and the Play Store
/// icon, which tool/gen_launcher_icon.py draws from the same geometry, are
/// checked for their size and format.
///
/// To change the icon, change the vectors, these pins and the script together.
void main() {
  test('the adaptive icon has a background, a foreground and a monochrome '
      'layer', () {
    final adaptiveIcon = _readXml('$_res/mipmap-anydpi-v26/ic_launcher.xml');
    final colorsXml = _readXml('$_res/values/tminus_colors.xml');
    expect(adaptiveIcon, contains('<adaptive-icon'));
    for (final entry in _layers.entries) {
      expect(
        _layerDrawable(adaptiveIcon, entry.key),
        entry.value,
        reason: 'the <${entry.key}> layer of the adaptive icon',
      );
      expect(
        _resolves(entry.value, colorsXml),
        isTrue,
        reason: '${entry.value} does not exist',
      );
    }
  });

  test('the foreground draws the track, the arc and the T- mark in the '
      'token colours', () {
    final foreground = _readXml('$_res/drawable/ic_launcher_foreground.xml');
    final colorsXml = _readXml('$_res/values/tminus_colors.xml');
    expect(
      _vector(foreground),
      _vectorSize,
      reason: 'the size and viewport of ic_launcher_foreground.xml',
    );
    expect(
      _paths(foreground),
      _foregroundPaths,
      reason:
          'ic_launcher_foreground.xml: the track, the arc and the T- mark, in '
          'drawing order, each with exactly these attributes',
    );
    for (final m in RegExp(r'@color/(\w+)').allMatches(foreground)) {
      expect(
        colorsXml,
        contains('<color name="${m.group(1)}">'),
        reason: '${m.group(0)} is not defined in tminus_colors.xml',
      );
    }
  });

  test('the monochrome layer draws the same shapes in opaque white, the track '
      'at alpha 0.3', () {
    final monochrome = _readXml('$_res/drawable/ic_launcher_monochrome.xml');
    expect(
      _vector(monochrome),
      _vectorSize,
      reason: 'the size and viewport of ic_launcher_monochrome.xml',
    );
    expect(
      _paths(monochrome),
      _monochromePaths,
      reason:
          'ic_launcher_monochrome.xml: the track, the arc and the T- mark, in '
          'drawing order, each with exactly these attributes',
    );
  });

  for (final entry in _legacySizes.entries) {
    test('mipmap-${entry.key}/ic_launcher.png is a ${entry.value} px square '
        'RGBA PNG', () {
      final png = _pngHeader('$_res/mipmap-${entry.key}/ic_launcher.png');
      expect((png.width, png.height), (entry.value, entry.value));
      expect(
        png.colorType,
        _pngRgba,
        reason: 'the circular mask needs an alpha channel',
      );
    });
  }

  test('docs/play/icon-512.png is a 512 px square RGBA PNG', () {
    final png = _pngHeader('docs/play/icon-512.png');
    expect((png.width, png.height), (512, 512));
    expect(png.colorType, _pngRgba, reason: 'the store icon is an RGBA PNG');
  });
}
