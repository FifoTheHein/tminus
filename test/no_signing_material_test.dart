import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Signing material never reaches git (Plan 6, decision 12). Release builds are
// signed with an upload key that `android/key.properties` points at: that file
// holds the keystore's passwords, and the keystore lives outside the repository.
// `android/.gitignore` ignores both, and this test fails if git tracks one
// anyway, for example after `git add -f` or a keystore dropped into a folder the
// ignore rules do not cover.

/// Lower-case names that are signing material in any folder: the properties file
/// that holds the keystore passwords. Names are compared in lower case, because
/// Windows treats `Key.Properties` and `key.properties` as one file.
const _signingFileNames = {'key.properties'};

/// Lower-case file extensions of keystores: Java and Android keystores, and
/// PKCS#12 files.
const _signingExtensions = ['.jks', '.keystore', '.p12'];

bool _isSigningMaterial(String path) {
  final name = path.split(RegExp(r'[\\/]')).last.toLowerCase();
  return _signingFileNames.contains(name) ||
      _signingExtensions.any(name.endsWith);
}

/// The paths in [tracked] that are signing material, in their given order. The
/// paths are as `git ls-files` prints them, relative to the repository root with
/// `/` between folders, and a `\` is read as a separator too.
List<String> signingMaterial(Iterable<String> tracked) => [
  for (final path in tracked)
    if (_isSigningMaterial(path)) path,
];

/// Why the scan cannot run here, or null when [git] can be started. The scan
/// needs `git` on the PATH, as every contributor's machine has it, and it is
/// skipped with this reason where it is not.
String? _gitUnavailable([String git = 'git']) {
  try {
    final result = Process.runSync(git, ['--version']);
    return result.exitCode == 0
        ? null
        : '$git --version exited with ${result.exitCode}';
  } on ProcessException {
    return 'git is not on the PATH';
  }
}

String _decode(Object? bytes) =>
    utf8.decode(bytes as List<int>, allowMalformed: true);

/// Every path git tracks (the index, so files that are only staged count too),
/// relative to the repository root whatever the current folder is.
List<String> _trackedPaths() {
  final result = Process.runSync(
    'git',
    ['ls-files', '-z', '--full-name', '--', ':/'],
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  if (result.exitCode != 0) {
    fail(
      'git ls-files failed with exit code ${result.exitCode}: '
      '${_decode(result.stderr)}',
    );
  }
  return [
    for (final path in _decode(result.stdout).split('\u0000'))
      if (path.isNotEmpty) path,
  ];
}

void main() {
  final gitSkip = _gitUnavailable();

  test('the matcher names key.properties and every keystore type', () {
    final tracked = [
      'pubspec.yaml',
      'android/key.properties',
      'key.properties',
      'android/app/Key.Properties',
      r'android\key.properties',
      'android/app/build.gradle.kts',
      'android/key.properties.example',
      'android/gradle.properties',
      'keys/tminus-upload.jks',
      'keys/UPLOAD.JKS',
      'android/app/release.keystore',
      'old keys/debug.Keystore',
      'certs/legacy.p12',
      'certs/LEGACY.P12',
      r'android\app\windows.jks',
      'docs/play/release.md',
      'lib/keystore_page.dart',
      'docs/jks',
      'docs/legacy.p12.md',
    ];
    expect(signingMaterial(tracked), [
      'android/key.properties',
      'key.properties',
      'android/app/Key.Properties',
      r'android\key.properties',
      'keys/tminus-upload.jks',
      'keys/UPLOAD.JKS',
      'android/app/release.keystore',
      'old keys/debug.Keystore',
      'certs/legacy.p12',
      'certs/LEGACY.P12',
      r'android\app\windows.jks',
    ]);
    expect(signingMaterial(const <String>[]), isEmpty);
  });

  test('the scan is skipped with a reason when git cannot be started', () {
    expect(_gitUnavailable('tminus-no-such-git'), 'git is not on the PATH');
  });

  test('no signing material is tracked', () {
    final tracked = _trackedPaths();
    // A scan of the wrong folder, or of nothing, must not pass by accident.
    expect(
      tracked,
      contains('pubspec.yaml'),
      reason: 'git ls-files must list the whole repository',
    );
    expect(
      signingMaterial(tracked),
      isEmpty,
      reason:
          'git tracks signing material. Run `git rm --cached` on each path, '
          'ignore it in android/.gitignore and, if it was ever pushed, treat '
          'the key as exposed (docs/play/release.md says what to do).',
    );
  }, skip: gitSkip);
}
