import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/source_status.dart';

import '../storage/test_database.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 9, 27);
  const work = SourceConfig(
    id: 'w',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.w',
  );
  const phone = SourceConfig(
    id: 'p',
    name: 'Personal',
    color: 0xFF5BC489,
    kind: SourceKind.device,
    deviceCalendarId: '3',
  );

  late AppDatabase db;
  late SourceRepository sources;
  late SyncLogRepository syncLog;
  late AppSettings appSettings;
  late SourceStatusLoader loader;

  setUp(() {
    db = openTestDatabase();
    sources = SourceRepository(db);
    syncLog = SyncLogRepository(db);
    appSettings = AppSettings(SettingsRepository(db));
    loader = SourceStatusLoader(
      sources: sources,
      syncLog: syncLog,
      appSettings: appSettings,
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  test('the loader joins each source with its state, latest log row and '
      'setup', () async {
    // Saved work first, but the repository lists by name, so the phone comes
    // first.
    await sources.save(work);
    await sources.save(phone);

    final workState = SourceSyncState(
      lastAttemptUtc: now.subtract(const Duration(minutes: 4)),
      lastSuccessUtc: now.subtract(const Duration(days: 2)),
      lastError: 'The link no longer works (HTTP 404).',
    );
    await sources.updateSyncState(work.id, workState);
    await syncLog.add(
      SyncLogEntry(
        sourceId: work.id,
        atUtc: now.subtract(const Duration(days: 2)),
        outcome: SyncOutcome.success,
        occurrenceCount: 23,
      ),
    );
    final latest = SyncLogEntry(
      sourceId: work.id,
      atUtc: now.subtract(const Duration(minutes: 4)),
      outcome: SyncOutcome.httpError,
      message: 'The link no longer works (HTTP 404).',
    );
    await syncLog.add(latest);
    // The marker outranks the failure above: the source waits for a new link.
    await appSettings.setSourceSetup(work.id, SourceSetup.needsLink);

    final statuses = await loader.all();

    expect(statuses.map((s) => s.config), [phone, work]);

    final phoneStatus = statuses[0];
    expect(phoneStatus.state, SourceSyncState());
    expect(phoneStatus.latest, isNull);
    expect(phoneStatus.setup, SourceSetup.ready);
    expect(phoneStatus.health, SourceHealth.ok);
    expect(phoneStatus.line, 'Not synced yet');

    final workStatus = statuses[1];
    expect(workStatus.state, workState);
    expect(workStatus.latest, latest);
    expect(workStatus.setup, SourceSetup.needsLink);
    expect(workStatus.health, SourceHealth.needsSetup);
    expect(workStatus.line, 'Needs its link');
  });

  test('byId returns the status of just that source', () async {
    await sources.save(work);
    await sources.save(phone);
    final workState = SourceSyncState(
      lastAttemptUtc: now.subtract(const Duration(minutes: 4)),
      lastSuccessUtc: now.subtract(const Duration(minutes: 4)),
    );
    await sources.updateSyncState(work.id, workState);
    final latest = SyncLogEntry(
      sourceId: work.id,
      atUtc: now.subtract(const Duration(minutes: 4)),
      outcome: SyncOutcome.success,
      occurrenceCount: 12,
    );
    await syncLog.add(latest);

    final workStatus = await loader.byId(work.id);
    expect(workStatus, isNotNull);
    expect(workStatus!.config, work);
    expect(workStatus.state, workState);
    expect(workStatus.latest, latest);
    expect(workStatus.setup, SourceSetup.ready);
    expect(workStatus.health, SourceHealth.ok);
    // The loader's clock reads `now`, four minutes after the success.
    expect(workStatus.line, 'Synced 4 min ago');

    // The other source has no log row of its own, so it must not get this one.
    final phoneStatus = await loader.byId(phone.id);
    expect(phoneStatus, isNotNull);
    expect(phoneStatus!.config, phone);
    expect(phoneStatus.latest, isNull);
    expect(phoneStatus.line, 'Not synced yet');
  });

  test('byId returns null for an unknown id', () async {
    await sources.save(work);

    expect(await loader.byId('missing'), isNull);
  });
}
