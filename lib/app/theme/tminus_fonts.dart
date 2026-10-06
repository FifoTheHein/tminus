/// Font families bundled as assets (see pubspec.yaml). Never fetched at
/// runtime: the app promises not to contact any servers.
abstract final class TMinusFonts {
  /// UI text.
  static const String sans = 'IBMPlexSans';

  /// Times, offsets, countdowns and chip numerals.
  static const String mono = 'IBMPlexMono';
}
