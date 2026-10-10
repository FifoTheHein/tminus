import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ICS links in flutter_secure_storage (spec §3, §10). A published link works
/// like a password, so it never goes into drift, logs or exports.
class SourceSecrets {
  SourceSecrets([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// The secure-storage key for [sourceId]'s link.
  static String keyFor(String sourceId) => 'ics-url.$sourceId';

  Future<String?> readUrl(String key) => _storage.read(key: key);

  Future<void> writeUrl(String key, String url) =>
      _storage.write(key: key, value: url);

  Future<void> delete(String key) => _storage.delete(key: key);
}
