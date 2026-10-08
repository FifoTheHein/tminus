import 'dart:io';

/// The last full body of each ICS feed, so a `304 Not Modified` can be
/// expanded again for the current window (Plan 4 decision). Lives in the app's
/// private support directory, next to the database, which already holds the
/// same meeting details.
class FeedBodyCache {
  FeedBodyCache(this._directory);

  final Future<Directory> Function() _directory;

  Future<String?> read(String sourceId) async {
    final file = await _file(sourceId);
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// Writes to a temporary file and renames it, so a reader never sees half a
  /// feed.
  Future<void> write(String sourceId, String body) async {
    final file = await _file(sourceId);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> delete(String sourceId) async {
    final file = await _file(sourceId);
    if (await file.exists()) await file.delete();
  }

  Future<File> _file(String sourceId) async {
    final dir = await _directory();
    final safe = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.ics');
  }
}
