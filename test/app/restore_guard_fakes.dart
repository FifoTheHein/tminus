import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/sources/source_admin.dart';
import 'package:tminus/core/sources/source_secrets.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';

/// Secure storage in a map, so no Keystore is needed.
class MapSecrets extends SourceSecrets {
  final links = <String, String>{};

  @override
  Future<String?> readUrl(String key) async => links[key];

  @override
  Future<void> writeUrl(String key, String url) async => links[key] = url;

  @override
  Future<void> delete(String key) async => links.remove(key);
}

/// A real [SourceAdmin] over [db]: secrets in a map, feed bodies in a temp
/// directory (made only if something is stored or removed, and deleted when
/// the test ends), and a [SyncPlatform] whose missing native side the admin
/// already tolerates. Call it from inside a test or `setUp`.
SourceAdmin fakeAdmin(AppDatabase db) {
  Directory? feeds;
  addTearDown(() async {
    final dir = feeds;
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  });
  return SourceAdmin(
    sources: SourceRepository(db),
    secrets: MapSecrets(),
    bodies: FeedBodyCache(
      () async => feeds ??= await Directory.systemTemp.createTemp(
        'tminus_restore_feeds_',
      ),
    ),
    platform: SyncPlatform(),
    settings: SettingsRepository(db),
    occurrences: OccurrenceRepository(db),
    db: db,
  );
}
