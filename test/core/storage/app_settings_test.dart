import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/sync/sync_service.dart';

import 'test_database.dart';

void main() {
  test('flags default off, round-trip, and merging defaults on', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final raw = SettingsRepository(db);
    final s = AppSettings(raw);

    expect(await s.onboardingDone(), isFalse);
    expect(await s.restorePending(), isFalse);
    expect(await s.installId(), isNull);
    expect(await s.mergeEnabled(), isTrue);
    expect(await s.sourceSetup('x'), SourceSetup.ready);

    await s.setOnboardingDone(true);
    await s.setRestorePending(true);
    await s.setInstallId('id-1');
    await s.setMergeEnabled(false);
    await s.setSourceSetup('x', SourceSetup.needsLink);

    expect(await s.onboardingDone(), isTrue);
    expect(await s.restorePending(), isTrue);
    expect(await s.installId(), 'id-1');
    expect(await raw.getString(SyncService.mergeEnabledKey), 'false');
    expect(await s.sourceSetup('x'), SourceSetup.needsLink);

    await s.setSourceSetup('x', SourceSetup.ready);
    expect(await raw.getString(AppSettings.sourceSetupKey('x')), '');
  });
}
