import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/restore_guard.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/meeting_link.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';

import '../core/fixtures.dart';
import '../core/storage/test_database.dart';
import 'restore_guard_fakes.dart';

/// A settings store that cannot store the install id, as when the last write
/// of a restore fails. The message names a link, to prove a failure is only
/// ever logged by its type.
class _IdWriteFails extends SettingsRepository {
  _IdWriteFails(super.db);

  @override
  Future<void> setString(String name, String value) async {
    if (name == AppSettings.installIdKey) {
      throw StateError('no write for https://calendar.example/s3cr3t/feed.ics');
    }
    await super.setString(name, value);
  }
}

/// A settings store that lets another guard finish the restore at the moment
/// this one has read the old install id and not yet started to make the
/// database safe: the first read of the id returns what was stored before it,
/// and then [afterFirstRead] runs. Do not `expect` inside it: the guard under
/// test would swallow the failure as a failed check and start normally.
class _AnotherGuardFinishesFirst extends SettingsRepository {
  _AnotherGuardFinishesFirst(super.db, this.afterFirstRead);

  final Future<void> Function() afterFirstRead;
  var _fired = false;

  @override
  Future<String?> getString(String name) async {
    final stored = await super.getString(name);
    if (name == AppSettings.installIdKey && !_fired) {
      _fired = true;
      await afterFirstRead();
    }
    return stored;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const syncChannel = MethodChannel(SyncPlatform.channelName);

  late AppDatabase db;
  late SourceRepository sources;
  late SettingsRepository raw;
  late AppSettings app;
  late String deviceId;
  late bool neverUpdated;

  /// The native methods the guard asked for, in order.
  late List<String> calls;

  const ics = SourceConfig(
    id: 'ics-1',
    name: 'Work Outlook',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.ics-1',
  );
  const phone = SourceConfig(
    id: 'device-1',
    name: 'Personal',
    color: blue,
    kind: SourceKind.device,
    deviceCalendarId: '3',
  );
  const fast = SourceConfig(
    id: 'debug-fast-alarms',
    name: 'Fast alarms',
    color: blue,
    kind: SourceKind.debug,
  );

  // SourceAdmin needs secrets, bodies and platform; the guard only calls
  // delete for the debug source, so the test builds a real one over fakes.
  RestoreGuard guard() => RestoreGuard(
    db: db,
    platform: SyncPlatform(),
    appSettings: app,
    sources: sources,
    admin: fakeAdmin(db),
  );

  setUp(() async {
    db = openTestDatabase();
    sources = SourceRepository(db);
    raw = SettingsRepository(db);
    app = AppSettings(raw);
    deviceId = 'device-A';
    neverUpdated = false;
    calls = [];
    messenger.setMockMethodCallHandler(syncChannel, (c) async {
      calls.add(c.method);
      return switch (c.method) {
        'installId' => deviceId,
        'neverUpdated' => neverUpdated,
        _ => null,
      };
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(syncChannel, null);
    await db.close();
  });

  test('a fresh install stores the id and changes nothing else', () async {
    expect(await guard().run(), RestoreOutcome.firstStart);
    expect(await app.installId(), 'device-A');
    expect(await app.onboardingDone(), isFalse);
  });

  test(
    'an upgrade keeps every source enabled and marks onboarding done',
    () async {
      await sources.save(ics);
      await OccurrenceRepository(db)
          .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
      expect(await guard().run(), RestoreOutcome.firstStart);
      expect((await sources.byId('ics-1'))!.enabled, isTrue);
      expect(await app.sourceSetup('ics-1'), SourceSetup.ready);
      expect(await app.onboardingDone(), isTrue);
      expect(await OccurrenceRepository(db).countForSource('ics-1'), 1);
    },
  );

  test('the same device again is normal', () async {
    await app.setInstallId('device-A');
    await sources.save(ics);
    expect(await guard().run(), RestoreOutcome.normal);
    expect((await sources.byId('ics-1'))!.enabled, isTrue);
  });

  test('a restore disables sources and clears device state', () async {
    await app.setInstallId('device-OLD');
    await app.setOnboardingDone(true);
    await sources.save(ics);
    await sources.save(phone);
    await sources.save(fast);
    // What the old phone's fetches left on the sources.
    await sources.updateSyncState(
      'ics-1',
      SourceSyncState(
        lastAttemptUtc: DateTime.utc(2026, 10, 6, 7, 30),
        lastSuccessUtc: DateTime.utc(2026, 10, 6, 7),
        lastError: 'HTTP 410',
        httpEtag: '"v1"',
        httpLastModified: 'Tue, 06 Oct 2026 07:00:00 GMT',
        emptyStreak: 2,
      ),
    );
    await sources.updateSyncState(
      'device-1',
      SourceSyncState(lastSuccessUtc: DateTime.utc(2026, 10, 6, 7)),
    );
    await OccurrenceRepository(db)
        .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
    await AlertHistoryRepository(db).record(
      AlertHistoryEntry(
        type: AlertEventType.dismissedAll,
        alertId: 'a',
        occurrenceKey: 'k',
        startUtc: DateTime.utc(2026, 10, 6, 8),
        atUtc: DateTime.utc(2026, 10, 6, 7),
      ),
    );
    await SyncLogRepository(db).add(
      SyncLogEntry(
        atUtc: DateTime.utc(2026, 10, 6),
        outcome: SyncOutcome.success,
      ),
    );
    await raw.setString('sync.lastFinishedUtcMs', '1');
    await raw.setString('sync.missedSystemExpected', '[]');
    await OverrideRepository(db).save(
      const EventOverride(
        scope: OverrideScope.series,
        target: 's',
        profileId: 'quick',
      ),
    );

    expect(await guard().run(), RestoreOutcome.restored);

    expect((await sources.byId('ics-1'))!.enabled, isFalse);
    expect(await app.sourceSetup('ics-1'), SourceSetup.needsLink);
    expect((await sources.byId('device-1'))!.enabled, isFalse);
    expect(await app.sourceSetup('device-1'), SourceSetup.needsCalendar);
    expect(await sources.byId('debug-fast-alarms'), isNull);
    // The old phone's sync state goes with it, for every kept source.
    for (final id in ['ics-1', 'device-1']) {
      final state = (await sources.syncState(id))!;
      expect(state.lastError, isNull, reason: id);
      expect(state.lastSuccessUtc, isNull, reason: id);
      expect(state.lastAttemptUtc, isNull, reason: id);
      expect(state.httpEtag, isNull, reason: id);
      expect(state.httpLastModified, isNull, reason: id);
      expect(state.emptyStreak, 0, reason: id);
    }
    expect(await OccurrenceRepository(db).countForSource('ics-1'), 0);
    expect(await AlertHistoryRepository(db).recent(), isEmpty);
    expect(await SyncLogRepository(db).recent(), isEmpty);
    expect(await raw.getString('sync.lastFinishedUtcMs'), isNull);
    expect(await raw.getString('sync.missedSystemExpected'), isNull);
    expect(await OverrideRepository(db).all(), hasLength(1)); // kept
    expect(await app.restorePending(), isTrue);
    expect(await app.onboardingDone(), isFalse);
    expect(await app.installId(), 'device-A');
    expect(await guard().run(), RestoreOutcome.normal); // only once
  });

  test('no native side means a normal start', () async {
    messenger.setMockMethodCallHandler(syncChannel, null);
    expect(await guard().run(), RestoreOutcome.normal);
  });

  // Beyond the plan's list.

  /// Captures what the code under test logs until the test ends.
  List<String> captureLog() {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);
    return logged;
  }

  test(
    'a restore keeps what the user set up and clears only the device state',
    () async {
      await app.setInstallId('device-OLD');
      await app.setOnboardingDone(true);
      await sources.save(ics.copyWith(defaultProfileId: 'important'));
      await sources.save(phone);
      await OccurrenceRepository(db)
          .replaceForSource('device-1', [occ(sourceId: 'device-1')]);

      // What the user set up: all of it stays.
      await ProfileRepository(db).save(
        const AlertProfile(id: 'p-0123456789ab', name: 'Mine', alerts: []),
      );
      await RuleRepository(db).save(
        KeywordRule(
          id: 'r-0123456789ab',
          position: 0,
          field: RuleField.title,
          pattern: 'standup',
          profileId: 'quick',
        ),
      );
      await OverrideRepository(db).save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'meeting-key',
          enabled: false,
        ),
      );
      await raw.setSkipFilters(const SkipFilters(allDay: false));
      await raw.setGlobalDefaultProfileId('quick');
      await raw.setString('ui.themeMode', 'dark');
      await app.setMergeEnabled(false);
      final muteUntil = DateTime.utc(2026, 10, 7, 5);
      final mutedAt = DateTime.utc(2026, 10, 6, 6);
      await raw.setQuietStateAt(MuteToday(muteUntil), changedAtUtc: mutedAt);
      final link = MeetingLink(
        copyKey: 'ics-1|u1|2026-10-06T08:00:00.000Z',
        meetingKey: 'ics-1|u1|2026-10-06T08:00:00.000Z',
        sourceId: 'ics-1',
        uid: 'u1',
        oneOff: true,
        endUtc: DateTime.utc(2026, 10, 6, 9),
        matchedBy: MeetingMatch.uid,
      );
      await MeetingLinkRepository(db).apply(upsert: [link], delete: {});

      // What describes the old phone: all of it goes.
      await raw.setString('sync.lastFinishedUtcMs', '1');
      await raw.setString('sync.missedSystemExpected', '[]');
      await raw.setString('sync.brokenNotice.ics-1', 'linkMissing');
      await raw.setString('sync.serverErrorSince.ics-1', '1');

      expect(await guard().run(), RestoreOutcome.restored);

      expect(await raw.getString('sync.lastFinishedUtcMs'), isNull);
      expect(await raw.getString('sync.missedSystemExpected'), isNull);
      expect(await raw.getString('sync.brokenNotice.ics-1'), isNull);
      expect(await raw.getString('sync.serverErrorSince.ics-1'), isNull);
      expect(await OccurrenceRepository(db).countForSource('device-1'), 0);

      final kept = await sources.byId('ics-1');
      expect(kept!.defaultProfileId, 'important');
      expect(kept.secureStorageKey, 'ics-url.ics-1');
      expect(
        (await ProfileRepository(db).all()).map((p) => p.id),
        contains('p-0123456789ab'),
      );
      expect(await RuleRepository(db).all(), hasLength(1));
      expect(await OverrideRepository(db).all(), hasLength(1));
      expect((await raw.skipFilters()).allDay, isFalse);
      expect(await raw.globalDefaultProfileId(), 'quick');
      expect(await raw.getString('ui.themeMode'), 'dark');
      expect(await app.mergeEnabled(), isFalse);
      expect(await raw.quietState(), MuteToday(muteUntil));
      expect(await raw.quietChangedAt(), mutedAt);
      expect(await MeetingLinkRepository(db).all(), [link]);
    },
  );

  test('a restore that cannot store the new id changes nothing', () async {
    final logged = captureLog();
    await app.setInstallId('device-OLD');
    await app.setOnboardingDone(true);
    await sources.save(ics);
    await OccurrenceRepository(db)
        .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
    await raw.setString('sync.lastFinishedUtcMs', '1');

    final failing = RestoreGuard(
      db: db,
      platform: SyncPlatform(),
      appSettings: AppSettings(_IdWriteFails(db)),
      sources: sources,
      admin: fakeAdmin(db),
    );
    expect(await failing.run(), RestoreOutcome.unsafe);

    expect((await sources.byId('ics-1'))!.enabled, isTrue);
    expect(await app.sourceSetup('ics-1'), SourceSetup.ready);
    expect(await OccurrenceRepository(db).countForSource('ics-1'), 1);
    expect(await raw.getString('sync.lastFinishedUtcMs'), '1');
    expect(await app.restorePending(), isFalse);
    expect(await app.onboardingDone(), isTrue);
    expect(await app.installId(), 'device-OLD');
    // Only the type is logged, never the message with the link in it.
    expect(logged.join('\n'), contains('StateError'));
    expect(logged.join('\n'), isNot(contains('s3cr3t')));

    // The next start does the whole restore.
    expect(await guard().run(), RestoreOutcome.restored);
    expect((await sources.byId('ics-1'))!.enabled, isFalse);
    expect(await app.installId(), 'device-A');
  });

  test('a restore that cannot be finished is reported unsafe', () async {
    final logged = captureLog();
    await app.setInstallId('device-OLD');
    await app.setOnboardingDone(true);
    await sources.save(ics);
    await OccurrenceRepository(db)
        .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
    await raw.setString('sync.lastFinishedUtcMs', '1');
    final oldState = SourceSyncState(
      lastSuccessUtc: DateTime.utc(2026, 10, 6, 7),
      lastError: 'HTTP 410',
      emptyStreak: 2,
    );
    await sources.updateSyncState('ics-1', oldState);

    final failing = RestoreGuard(
      db: db,
      platform: SyncPlatform(),
      appSettings: AppSettings(_IdWriteFails(db)),
      sources: sources,
      admin: fakeAdmin(db),
    );

    /// The restore is all or nothing: the sync state it clears is rolled back
    /// with the rest, and the source still waits to be synced as before.
    /// [onboarded] is the onboarding flag the database had before the run.
    Future<void> expectNothingChanged({bool onboarded = true}) async {
      expect((await sources.byId('ics-1'))!.enabled, isTrue);
      expect(await app.sourceSetup('ics-1'), SourceSetup.ready);
      expect(await OccurrenceRepository(db).countForSource('ics-1'), 1);
      expect(await raw.getString('sync.lastFinishedUtcMs'), '1');
      expect(await sources.syncState('ics-1'), oldState);
      expect(await app.restorePending(), isFalse);
      expect(await app.onboardingDone(), onboarded);
    }

    // Another installation's id: a backup restored here.
    expect(await failing.run(), RestoreOutcome.unsafe);
    await expectNothingChanged();
    expect(await app.installId(), 'device-OLD');

    // A backup from before the id existed, on a phone where the app was never
    // updated and onboarding was never done, is a restore as well, and fails
    // the same way. (With onboarding done it would be this phone's own.)
    await raw.setString(AppSettings.installIdKey, '');
    await app.setOnboardingDone(false);
    neverUpdated = true;
    expect(await failing.run(), RestoreOutcome.unsafe);
    await expectNothingChanged(onboarded: false);
    expect(await app.installId(), isNull);
    // Only the type is logged, never the message with the link in it.
    expect(logged.join('\n'), contains('StateError'));
    expect(logged.join('\n'), isNot(contains('s3cr3t')));
  });

  test('a restore another guard already finished is not done twice', () async {
    await app.setInstallId('device-OLD');
    await app.setOnboardingDone(true);
    await sources.save(ics);
    await sources.save(phone);
    await OccurrenceRepository(db)
        .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);

    // The app's guard and a headless sync's both find this restore. The slower
    // one has read the old id when the other finishes the restore, the user
    // links the feed again and a sync fills the cache. Only then does the
    // slower one reach its transaction.
    late RestoreOutcome other;
    final slower = RestoreGuard(
      db: db,
      platform: SyncPlatform(),
      appSettings: AppSettings(
        _AnotherGuardFinishesFirst(db, () async {
          other = await guard().run();
          await sources.save(ics);
          await app.setSourceSetup('ics-1', SourceSetup.ready);
          await app.setRestorePending(false);
          await app.setOnboardingDone(true);
          await OccurrenceRepository(db)
              .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
          await raw.setString('sync.lastFinishedUtcMs', '2');
        }),
      ),
      sources: sources,
      admin: fakeAdmin(db),
    );

    // It does nothing, and does not claim a restore it did not do.
    expect(await slower.run(), RestoreOutcome.normal);
    expect(other, RestoreOutcome.restored);

    // What the first guard did stands, and so does what the user set up since.
    expect(await app.installId(), 'device-A');
    expect((await sources.byId('device-1'))!.enabled, isFalse);
    expect(await app.sourceSetup('device-1'), SourceSetup.needsCalendar);
    expect((await sources.byId('ics-1'))!.enabled, isTrue);
    expect(await app.sourceSetup('ics-1'), SourceSetup.ready);
    expect(await OccurrenceRepository(db).countForSource('ics-1'), 1);
    expect(await raw.getString('sync.lastFinishedUtcMs'), '2');
    expect(await app.restorePending(), isFalse);
    expect(await app.onboardingDone(), isTrue);
  });

  test(
    'a backup from before Plan 5 on a fresh install is treated as a restore',
    () async {
      // The build that made the backup stored no install id, and the app was
      // installed here and never updated: sources but no id is a restore, not
      // an upgrade.
      neverUpdated = true;
      await sources.save(ics);
      await sources.save(phone);
      await sources.save(fast);
      await sources.updateSyncState(
        'ics-1',
        SourceSyncState(
          lastSuccessUtc: DateTime.utc(2026, 10, 6, 7),
          lastError: 'HTTP 410',
          emptyStreak: 2,
        ),
      );
      await OccurrenceRepository(db)
          .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
      await raw.setString('sync.lastFinishedUtcMs', '1');
      expect(await app.installId(), isNull);

      expect(await guard().run(), RestoreOutcome.restored);

      expect((await sources.byId('ics-1'))!.enabled, isFalse);
      expect(await app.sourceSetup('ics-1'), SourceSetup.needsLink);
      expect((await sources.byId('device-1'))!.enabled, isFalse);
      expect(await app.sourceSetup('device-1'), SourceSetup.needsCalendar);
      expect(await sources.byId('debug-fast-alarms'), isNull);
      expect(await OccurrenceRepository(db).countForSource('ics-1'), 0);
      expect(await raw.getString('sync.lastFinishedUtcMs'), isNull);
      expect((await sources.syncState('ics-1'))!.lastError, isNull);
      expect(await app.restorePending(), isTrue);
      expect(await app.onboardingDone(), isFalse);
      expect(await app.installId(), 'device-A');
      expect(await guard().run(), RestoreOutcome.normal); // only once
    },
  );

  test('an installation whose first start could not store the id, onboarded since, is not a restore', () async {
    // A fresh Plan 5 install whose first start failed to store the id, and
    // that the user has set up since: sources and no id, on a phone where the
    // app was never updated, look like a backup from before the id existed.
    // The onboarding that was done here says they are this phone's own.
    neverUpdated = true;
    await app.setOnboardingDone(true);
    await sources.save(ics);
    await sources.save(phone);
    await sources.save(fast);
    await sources.updateSyncState(
      'ics-1',
      SourceSyncState(
        lastSuccessUtc: DateTime.utc(2026, 10, 6, 7),
        lastError: 'HTTP 410',
        emptyStreak: 2,
      ),
    );
    await OccurrenceRepository(db)
        .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
    await raw.setString('sync.lastFinishedUtcMs', '1');
    expect(await app.installId(), isNull);

    // Not a restore: the id is stored and nothing else changes.
    expect(await guard().run(), RestoreOutcome.firstStart);

    expect((await sources.byId('ics-1'))!.enabled, isTrue);
    expect(await app.sourceSetup('ics-1'), SourceSetup.ready);
    expect((await sources.byId('device-1'))!.enabled, isTrue);
    expect(await app.sourceSetup('device-1'), SourceSetup.ready);
    expect(await sources.byId('debug-fast-alarms'), isNotNull);
    expect(await OccurrenceRepository(db).countForSource('ics-1'), 1);
    expect(await raw.getString('sync.lastFinishedUtcMs'), '1');
    expect((await sources.syncState('ics-1'))!.lastError, 'HTTP 410');
    expect(await app.restorePending(), isFalse);
    expect(await app.onboardingDone(), isTrue);
    expect(await app.installId(), 'device-A');
    // The update question comes last and is not asked at all here.
    expect(calls, contains('installId'));
    expect(calls, isNot(contains('neverUpdated')));
  });

  test('an upgraded install with sources is still an upgrade', () async {
    // The native side says the app was updated here, so a database with sources
    // and no id is this phone's own, from the build before.
    neverUpdated = false;
    await sources.save(ics);
    await sources.save(phone);
    await OccurrenceRepository(db)
        .replaceForSource('ics-1', [occ(sourceId: 'ics-1')]);
    await sources.updateSyncState(
      'ics-1',
      SourceSyncState(
        lastSuccessUtc: DateTime.utc(2026, 10, 6, 7),
        lastError: 'HTTP 410',
      ),
    );

    expect(await guard().run(), RestoreOutcome.firstStart);

    expect((await sources.byId('ics-1'))!.enabled, isTrue);
    expect(await app.sourceSetup('ics-1'), SourceSetup.ready);
    expect((await sources.byId('device-1'))!.enabled, isTrue);
    expect(await app.sourceSetup('device-1'), SourceSetup.ready);
    expect(await OccurrenceRepository(db).countForSource('ics-1'), 1);
    expect((await sources.syncState('ics-1'))!.lastError, 'HTTP 410');
    expect(await app.restorePending(), isFalse);
    expect(await app.onboardingDone(), isTrue);
    expect(await app.installId(), 'device-A');
  });

  test(
    'a fresh install that was never updated is still a first start',
    () async {
      // Every fresh install is one the app was never updated on: without
      // sources there is nothing to restore.
      neverUpdated = true;
      expect(await guard().run(), RestoreOutcome.firstStart);
      expect(await app.installId(), 'device-A');
      expect(await app.restorePending(), isFalse);
      expect(await app.onboardingDone(), isFalse);
      // The update question is asked only when there are sources.
      expect(calls, contains('installId'));
      expect(calls, isNot(contains('neverUpdated')));
    },
  );

  test('an empty id from the native side changes nothing', () async {
    deviceId = '';
    await app.setInstallId('device-OLD');
    await app.setOnboardingDone(true);
    await sources.save(ics);
    expect(await guard().run(), RestoreOutcome.normal);
    expect((await sources.byId('ics-1'))!.enabled, isTrue);
    expect(await app.onboardingDone(), isTrue);
    expect(await app.installId(), 'device-OLD');
  });

  test(
    'a native error is a normal start and only its code is logged',
    () async {
      final logged = captureLog();
      messenger.setMockMethodCallHandler(
        syncChannel,
        (c) async => throw PlatformException(
          code: 'unavailable',
          message: 'no id for https://calendar.example/s3cr3t/feed.ics',
        ),
      );
      await app.setInstallId('device-OLD');
      await sources.save(ics);

      expect(await guard().run(), RestoreOutcome.normal);

      expect((await sources.byId('ics-1'))!.enabled, isTrue);
      expect(await app.installId(), 'device-OLD');
      expect(logged.join('\n'), contains('unavailable'));
      expect(logged.join('\n'), isNot(contains('s3cr3t')));
    },
  );
}
