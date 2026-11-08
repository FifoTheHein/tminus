import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/device_calendar_api.dart';
import 'package:tminus/core/sources/device_calendar_source.dart';
import 'package:tminus/core/sources/fast_alarms.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/sources/ics_feed_source.dart';
import 'package:tminus/core/sources/source_admin.dart';
import 'package:tminus/core/sources/source_factory.dart';
import 'package:tminus/core/sources/source_secrets.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

const _secretUrl =
    'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';

/// A secure store that cannot delete, as after a Keystore failure. The
/// platform error names the link, to prove a failure is never logged with its
/// message.
class _UndeletableSecrets extends SourceSecrets {
  @override
  Future<void> delete(String key) async => throw PlatformException(
    code: 'keystore',
    message: 'Could not delete the value stored for $_secretUrl',
  );
}

/// A source table that cannot save a row, as after a full disk or a locked
/// database. The error names a link, to prove it is never logged.
class _SaveFails extends SourceRepository {
  _SaveFails(super.db);

  @override
  Future<void> save(SourceConfig s) async =>
      throw StateError('The row for $_secretUrl could not be saved');
}

/// A settings store that cannot write one source's setup marker, as when the
/// last step of choosing a calendar or of re-linking fails.
class _MarkerWriteFails extends SettingsRepository {
  _MarkerWriteFails(super.db, this.sourceId);

  final String sourceId;

  @override
  Future<void> setString(String name, String value) async {
    if (name == AppSettings.sourceSetupKey(sourceId)) {
      throw StateError('the setup marker could not be written');
    }
    await super.setString(name, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const syncChannel = MethodChannel(SyncPlatform.channelName);
  final syncCalls = <MethodCall>[];
  late AppDatabase db;
  late SourceRepository sources;
  late SettingsRepository settings;
  late Directory dir;
  late FeedBodyCache bodies;
  late SourceAdmin admin;
  final secrets = SourceSecrets();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    messenger.setMockMethodCallHandler(syncChannel, (call) async {
      syncCalls.add(call);
      return null;
    });
    db = openTestDatabase();
    sources = SourceRepository(db);
    settings = SettingsRepository(db);
    dir = await Directory.systemTemp.createTemp('feeds');
    bodies = FeedBodyCache(() async => dir);
    admin = SourceAdmin(
      sources: sources,
      secrets: secrets,
      bodies: bodies,
      platform: SyncPlatform(),
      settings: settings,
      occurrences: OccurrenceRepository(db),
      db: db,
    );
  });

  tearDown(() async {
    syncCalls.clear();
    messenger.setMockMethodCallHandler(syncChannel, null);
    await db.close();
    await dir.delete(recursive: true);
  });

  group('SourceAdmin', () {
    test(
      'an ICS source keeps its link in secure storage, not in drift',
      () async {
        final added = await admin.addIcsSource(
          name: 'Work Outlook',
          color: blue,
          url:
              'webcal://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics',
        );
        final s = added.source;
        expect(added.insecure, isFalse);
        expect(s.id, startsWith('ics-'));
        expect(s.kind, SourceKind.ics);
        expect(s.secureStorageKey, SourceSecrets.keyFor(s.id));
        expect(await sources.byId(s.id), s);
        expect(
          await secrets.readUrl(s.secureStorageKey!),
          'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics',
        );
        final row = await db.customSelect('SELECT * FROM sources').getSingle();
        expect(row.data.values.join(' '), isNot(contains('s3cr3t')));
      },
    );

    test('a plain http link is added and flagged insecure', () async {
      final added = await admin.addIcsSource(
        name: 'Home',
        color: blue,
        url: 'http://example.com/home.ics',
      );
      expect(added.insecure, isTrue);
    });

    test('a rejected link adds nothing', () async {
      await expectLater(
        admin.addIcsSource(
          name: 'Work',
          color: blue,
          url: 'https://outlook.office365.com/owa/calendar/x/calendar.html',
        ),
        throwsA(isA<IcsUrlException>()),
      );
      expect(await sources.all(), isEmpty);
    });

    SourceAdmin adminOver(SourceRepository rows, SourceSecrets store) =>
        SourceAdmin(
          sources: rows,
          secrets: store,
          bodies: bodies,
          platform: SyncPlatform(),
          settings: settings,
          occurrences: OccurrenceRepository(db),
          db: db,
        );

    test('a row that cannot be saved leaves no secret', () async {
      await expectLater(
        adminOver(
          _SaveFails(db),
          secrets,
        ).addIcsSource(name: 'Work', color: blue, url: _secretUrl),
        throwsA(isA<StateError>()),
      );

      // The link went to secure storage first, and was taken out again: with
      // no row nothing would ever delete it.
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
      expect(await sources.all(), isEmpty);
    });

    test(
      'a link that cannot be deleted does not hide why the row was not saved',
      () async {
        final logged = <String>[];
        final realDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
        addTearDown(() => debugPrint = realDebugPrint);

        await expectLater(
          adminOver(
            _SaveFails(db),
            _UndeletableSecrets(),
          ).addIcsSource(name: 'Work', color: blue, url: _secretUrl),
          // The save's own error, not the store's.
          throwsA(isA<StateError>()),
        );

        expect(await sources.all(), isEmpty);
        // The failed clean-up is logged by its type; its message names the
        // link.
        expect(logged.join('\n'), contains('PlatformException'));
        expect(logged.join('\n'), isNot(contains('s3cr3t')));
      },
    );

    test('two sources never share an id', () async {
      final a = await admin.addIcsSource(
        name: 'A',
        color: blue,
        url: 'https://a.example/a.ics',
      );
      final b = await admin.addIcsSource(
        name: 'B',
        color: blue,
        url: 'https://b.example/b.ics',
      );
      expect(a.source.id, isNot(b.source.id));
    });

    test(
      'a new link replaces the old one and forgets the validators and body',
      () async {
        final s = (await admin.addIcsSource(
          name: 'W',
          color: blue,
          url: 'https://a.example/a.ics',
        )).source;
        await sources.updateSyncState(
          s.id,
          SourceSyncState(
            lastSuccessUtc: DateTime.utc(2026, 10, 6),
            httpEtag: '"v1"',
            httpLastModified: 'x',
          ),
        );
        await bodies.write(s.id, 'old body');

        expect(
          await admin.updateIcsUrl(s.id, 'https://b.example/b.ics'),
          isFalse,
        );

        expect(
          await secrets.readUrl(s.secureStorageKey!),
          'https://b.example/b.ics',
        );
        final state = (await sources.syncState(s.id))!;
        expect(state.httpEtag, isNull);
        expect(state.httpLastModified, isNull);
        expect(state.lastSuccessUtc, DateTime.utc(2026, 10, 6));
        expect(await bodies.read(s.id), isNull);
      },
    );

    test('a new link restarts the 24 h escalation clock', () async {
      final s = (await admin.addIcsSource(
        name: 'W',
        color: blue,
        url: 'https://a.example/a.ics',
      )).source;
      // The old link has been answering with server errors since the 5th.
      final since = SyncService.serverErrorSinceKey(s.id);
      await settings.setString(
        since,
        '${DateTime.utc(2026, 10, 5).millisecondsSinceEpoch}',
      );

      await admin.updateIcsUrl(s.id, 'https://b.example/b.ics');

      expect(await settings.getString(since), isEmpty);
    });

    test(
      'a device source takes the calendar name and colour by default',
      () async {
        const calendar = DeviceCalendar(
          id: '3',
          name: 'Work',
          color: 0xFF33AA66,
          visible: true,
        );
        final s = await admin.addDeviceSource(calendar: calendar);
        expect(s.id, startsWith('device-'));
        expect(
          (s.kind, s.deviceCalendarId, s.name, s.color),
          (SourceKind.device, '3', 'Work', 0xFF33AA66),
        );
        final renamed = await admin.addDeviceSource(
          calendar: calendar,
          name: 'Phone',
          color: blue,
        );
        expect((renamed.name, renamed.color), ('Phone', blue));
      },
    );

    test('delete removes the row, its occurrences, its link, its body and its notices', () async {
      final s = (await admin.addIcsSource(
        name: 'W',
        color: blue,
        url: 'https://a.example/a.ics',
      )).source;
      await OccurrenceRepository(db)
          .replaceForSource(s.id, [occ(sourceId: s.id)]);
      await bodies.write(s.id, 'body');
      final since = SyncService.serverErrorSinceKey(s.id);
      final noticeUp = SyncService.brokenNoticeKey(s.id);
      await settings.setString(since, '1790000000000');
      await settings.setString(noticeUp, 'httpError');

      await admin.delete(s.id);

      expect(await sources.byId(s.id), isNull);
      expect(await OccurrenceRepository(db).countForSource(s.id), 0);
      expect(await secrets.readUrl(s.secureStorageKey!), isNull);
      expect(await bodies.read(s.id), isNull);
      expect(await settings.getString(since), isEmpty);
      expect(await settings.getString(noticeUp), isEmpty);
      expect(
        syncCalls
            .where((c) => c.method == 'cancelSourceNotice')
            .map((c) => c.arguments)
            .toSet(),
        {
          {'kind': 'stale', 'sourceId': s.id},
          {'kind': 'broken', 'sourceId': s.id},
        },
      );
    });

    test(
      'a secure storage failure during delete still withdraws the notices',
      () async {
        final failing = SourceAdmin(
          sources: sources,
          secrets: _UndeletableSecrets(),
          bodies: bodies,
          platform: SyncPlatform(),
          settings: settings,
          occurrences: OccurrenceRepository(db),
          db: db,
        );
        final s = (await failing.addIcsSource(
          name: 'W',
          color: blue,
          url: _secretUrl,
        )).source;
        await bodies.write(s.id, 'body');
        final since = SyncService.serverErrorSinceKey(s.id);
        final noticeUp = SyncService.brokenNoticeKey(s.id);
        await settings.setString(since, '1790000000000');
        await settings.setString(noticeUp, 'httpError');
        final logged = <String>[];
        final realDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
        addTearDown(() => debugPrint = realDebugPrint);

        await failing.delete(s.id);

        expect(await sources.byId(s.id), isNull);
        expect(await bodies.read(s.id), isNull);
        expect(await settings.getString(since), isEmpty);
        expect(await settings.getString(noticeUp), isEmpty);
        expect(
          syncCalls
              .where((c) => c.method == 'cancelSourceNotice')
              .map((c) => c.arguments)
              .toSet(),
          {
            {'kind': 'stale', 'sourceId': s.id},
            {'kind': 'broken', 'sourceId': s.id},
          },
        );
        // The failure is logged by its type; its message names the link.
        expect(logged.join('\n'), contains('PlatformException'));
        expect(logged.join('\n'), isNot(contains('s3cr3t')));
      },
    );

    Future<SourceConfig> addWork() async => (await admin.addIcsSource(
      name: 'W',
      color: blue,
      url: 'https://a.example/a.ics',
    )).source;

    test('re-linking a source that needs its link enables it and clears the marker', () async {
      final app = AppSettings(settings);
      final s = await addWork();
      // As after a restore: switched off and waiting for its link.
      await sources.save(s.copyWith(enabled: false));
      await app.setSourceSetup(s.id, SourceSetup.needsLink);

      await admin.updateIcsUrl(s.id, 'https://b.example/b.ics');

      expect((await sources.byId(s.id))!.enabled, isTrue);
      expect(await app.sourceSetup(s.id), SourceSetup.ready);
      expect(
        await secrets.readUrl(s.secureStorageKey!),
        'https://b.example/b.ics',
      );
    });

    test('re-linking a ready source leaves enabled as it was', () async {
      final off = await addWork();
      await sources.save(off.copyWith(enabled: false));
      final on = await addWork();

      await admin.updateIcsUrl(off.id, 'https://b.example/b.ics');
      await admin.updateIcsUrl(on.id, 'https://b.example/b.ics');

      expect((await sources.byId(off.id))!.enabled, isFalse);
      expect((await sources.byId(on.id))!.enabled, isTrue);
      // A source that never needed setup gets no marker row.
      expect(
        await settings.getString(AppSettings.sourceSetupKey(off.id)),
        isNull,
      );
    });

    test("choosing a calendar sets its id, enables the source, clears the marker, the old error and the old calendar's cached events", () async {
      final app = AppSettings(settings);
      final cache = OccurrenceRepository(db);
      final withCache = SourceAdmin(
        sources: sources,
        secrets: secrets,
        bodies: bodies,
        platform: SyncPlatform(),
        settings: settings,
        occurrences: cache,
        db: db,
      );
      const old = DeviceCalendar(
        id: '3',
        name: 'Work',
        color: 0xFF33AA66,
        visible: true,
      );
      const picked = DeviceCalendar(
        id: '7',
        name: 'Calendar',
        color: 0xFF112233,
        visible: true,
      );
      final s = await withCache.addDeviceSource(calendar: old, name: 'Phone');
      // As after a restore: switched off and waiting for a calendar, with
      // the old phone's error and cached events still on it.
      await sources.save(s.copyWith(enabled: false));
      await app.setSourceSetup(s.id, SourceSetup.needsCalendar);
      await sources.updateSyncState(
        s.id,
        SourceSyncState(
          lastAttemptUtc: DateTime.utc(2026, 10, 6, 8),
          lastSuccessUtc: DateTime.utc(2026, 10, 6, 7),
          lastError: 'The calendar on this phone is gone.',
          emptyStreak: 2,
        ),
      );
      await cache.replaceForSource(s.id, [occ(sourceId: s.id)]);

      await withCache.updateDeviceCalendar(s.id, picked);

      final after = (await sources.byId(s.id))!;
      expect(after.deviceCalendarId, '7');
      expect(after.enabled, isTrue);
      expect(after.name, 'Phone');
      expect(await app.sourceSetup(s.id), SourceSetup.ready);
      final state = (await sources.syncState(s.id))!;
      expect(state.lastError, isNull);
      expect(state.emptyStreak, 0);
      expect(state.lastAttemptUtc, DateTime.utc(2026, 10, 6, 8));
      expect(state.lastSuccessUtc, DateTime.utc(2026, 10, 6, 7));
      expect(await cache.countForSource(s.id), 0);
    });

    test('setEnabled refuses while setup is pending', () async {
      final app = AppSettings(settings);
      final feed = await addWork();
      const calendar = DeviceCalendar(
        id: '3',
        name: 'Work',
        color: 0xFF33AA66,
        visible: true,
      );
      final phone = await admin.addDeviceSource(calendar: calendar);
      await sources.save(feed.copyWith(enabled: false));
      await sources.save(phone.copyWith(enabled: false));
      await app.setSourceSetup(feed.id, SourceSetup.needsLink);
      await app.setSourceSetup(phone.id, SourceSetup.needsCalendar);

      await expectLater(admin.setEnabled(feed.id, true), throwsStateError);
      await expectLater(admin.setEnabled(phone.id, true), throwsStateError);
      expect((await sources.byId(feed.id))!.enabled, isFalse);
      expect((await sources.byId(phone.id))!.enabled, isFalse);

      // Once the setup is done it switches on, and off again.
      await app.setSourceSetup(feed.id, SourceSetup.ready);
      await admin.setEnabled(feed.id, true);
      expect((await sources.byId(feed.id))!.enabled, isTrue);
      await admin.setEnabled(feed.id, false);
      expect((await sources.byId(feed.id))!.enabled, isFalse);
    });

    test('edit renames, recolours and clears the default profile', () async {
      final s = (await admin.addIcsSource(
        name: 'W',
        color: blue,
        url: 'https://a.example/a.ics',
        defaultProfileId: 'quick',
      )).source;

      await admin.edit(s.id, name: 'Work Outlook', color: 0xFF5BC489);
      var after = (await sources.byId(s.id))!;
      expect(after.name, 'Work Outlook');
      expect(after.color, 0xFF5BC489);
      expect(after.defaultProfileId, 'quick');

      await admin.edit(s.id, defaultProfileId: 'important');
      expect((await sources.byId(s.id))!.defaultProfileId, 'important');

      await admin.edit(s.id, clearDefaultProfile: true);
      after = (await sources.byId(s.id))!;
      expect(after.defaultProfileId, isNull);
      expect(after.name, 'Work Outlook');

      // Editing never touches the link, and an unknown id changes nothing.
      expect(after.secureStorageKey, s.secureStorageKey);
      expect(
        await secrets.readUrl(s.secureStorageKey!),
        'https://a.example/a.ics',
      );
      await admin.edit('nope', name: 'X');
      expect(await sources.byId('nope'), isNull);
    });

    test('delete clears the setup marker', () async {
      final app = AppSettings(settings);
      final s = await addWork();
      await app.setSourceSetup(s.id, SourceSetup.needsLink);

      await admin.delete(s.id);

      expect(await app.sourceSetup(s.id), SourceSetup.ready);
      expect(
        await settings.getString(AppSettings.sourceSetupKey(s.id)),
        isEmpty,
      );
    });

    test('choosing a calendar changes nothing when the marker cannot be cleared', () async {
      final app = AppSettings(settings);
      final cache = OccurrenceRepository(db);
      const old = DeviceCalendar(
        id: '3',
        name: 'Work',
        color: 0xFF33AA66,
        visible: true,
      );
      const picked = DeviceCalendar(
        id: '7',
        name: 'Calendar',
        color: 0xFF112233,
        visible: true,
      );
      final s = await admin.addDeviceSource(calendar: old, name: 'Phone');
      // As after a restore: switched off and waiting for a calendar, with the
      // old phone's error and cached events still on it.
      await sources.save(s.copyWith(enabled: false));
      await app.setSourceSetup(s.id, SourceSetup.needsCalendar);
      await sources.updateSyncState(
        s.id,
        SourceSyncState(
          lastSuccessUtc: DateTime.utc(2026, 10, 6, 7),
          lastError: 'The calendar on this phone is gone.',
          emptyStreak: 2,
        ),
      );
      await cache.replaceForSource(s.id, [occ(sourceId: s.id)]);
      final failing = SourceAdmin(
        sources: sources,
        secrets: secrets,
        bodies: bodies,
        platform: SyncPlatform(),
        settings: _MarkerWriteFails(db, s.id),
        occurrences: cache,
        db: db,
      );

      // Every step before the marker works, and then clearing it fails.
      await expectLater(
        failing.updateDeviceCalendar(s.id, picked),
        throwsStateError,
      );

      // None of it stays: the source is not enabled with its marker still set.
      final after = (await sources.byId(s.id))!;
      expect((after.enabled, after.deviceCalendarId), (false, '3'));
      expect(await app.sourceSetup(s.id), SourceSetup.needsCalendar);
      final state = (await sources.syncState(s.id))!;
      expect(
        (state.lastError, state.emptyStreak),
        ('The calendar on this phone is gone.', 2),
      );
      expect(await cache.countForSource(s.id), 1);
    });

    test('re-linking changes nothing but the link when the marker cannot be cleared', () async {
      final app = AppSettings(settings);
      final s = await addWork();
      // As after a restore: switched off and waiting for its link, with the old
      // link's validators, body and server errors still on it.
      await sources.save(s.copyWith(enabled: false));
      await app.setSourceSetup(s.id, SourceSetup.needsLink);
      await sources.updateSyncState(
        s.id,
        SourceSyncState(
          httpEtag: '"v1"',
          httpLastModified: 'x',
          lastError: 'The link no longer works (HTTP 404).',
        ),
      );
      await bodies.write(s.id, 'old body');
      final since = SyncService.serverErrorSinceKey(s.id);
      await settings.setString(since, '1790000000000');
      final failing = SourceAdmin(
        sources: sources,
        secrets: secrets,
        bodies: bodies,
        platform: SyncPlatform(),
        settings: _MarkerWriteFails(db, s.id),
        occurrences: OccurrenceRepository(db),
        db: db,
      );

      // Every step before the marker works, and then clearing it fails.
      await expectLater(
        failing.updateIcsUrl(s.id, 'https://b.example/b.ics'),
        throwsStateError,
      );

      // The link went to secure storage first, which no transaction covers,
      // so trying again writes it once more.
      expect(
        await secrets.readUrl(s.secureStorageKey!),
        'https://b.example/b.ics',
      );
      // Nothing else stays: the source is not enabled with its marker still set.
      expect((await sources.byId(s.id))!.enabled, isFalse);
      expect(await app.sourceSetup(s.id), SourceSetup.needsLink);
      final state = (await sources.syncState(s.id))!;
      expect(state.httpEtag, '"v1"');
      expect(state.lastError, 'The link no longer works (HTTP 404).');
      expect(await settings.getString(since), '1790000000000');
      expect(await bodies.read(s.id), 'old body');
    });
  });

  group('FastAlarms', () {
    test(
      'three fixed events: a coalesced pair at +2 min and a Teams call at +12',
      () async {
        final fast = FastAlarms(
          sources: sources,
          settings: SettingsRepository(db),
        );
        final now = DateTime.utc(2026, 10, 6, 8, 0, 10, 500);
        await fast.create(now);

        final source = (await sources.byId(FastAlarms.sourceId))!;
        expect((source.kind, source.name), (SourceKind.debug, 'Fast alarms'));
        final fetched = await FastAlarmsSource(
          config: source,
          fastAlarms: fast,
        ).fetch(FetchWindow.around(now)) as SourceFetched;
        final events = fetched.occurrences;
        expect(events.map((o) => o.startUtc), [
          DateTime.utc(2026, 10, 6, 8, 2, 10),
          DateTime.utc(2026, 10, 6, 8, 2, 10),
          DateTime.utc(2026, 10, 6, 8, 12, 10),
        ]);
        expect(events.map((o) => o.joinUrl != null), [false, false, true]);
        expect(events.map((o) => o.key).toSet(), hasLength(3));

        // Later syncs see the same times.
        final again =
            await FastAlarmsSource(config: source, fastAlarms: fast).fetch(
              FetchWindow.around(now.add(const Duration(minutes: 1))),
            ) as SourceFetched;
        expect(again.occurrences, events);

        await fast.clear();
        expect(await sources.byId(FastAlarms.sourceId), isNull);
        expect(await fast.occurrences(source), isEmpty);
      },
    );
  });

  test('the factory builds the source type each kind needs', () {
    final factory = SourceFactory(
      client: MockClient((_) async => http.Response('', 200)),
      secrets: secrets,
      bodies: bodies,
      deviceCalendars: DeviceCalendarApi(),
      fastAlarms: FastAlarms(
        sources: sources,
        settings: SettingsRepository(db),
      ),
    );
    SourceConfig config(SourceKind kind) =>
        SourceConfig(id: kind.name, name: kind.name, color: blue, kind: kind);
    final state = SourceSyncState(httpEtag: '"v1"', httpLastModified: 'x');
    final ics = factory.create(
      config(SourceKind.ics),
      state,
      zone: johannesburg,
    );
    expect(ics, isA<IcsFeedSource>());
    expect((ics as IcsFeedSource).deviceZone, 'Africa/Johannesburg');
    expect(ics.previous, same(state));
    expect(
      factory.create(config(SourceKind.device), null, zone: johannesburg),
      isA<DeviceCalendarSource>(),
    );
    expect(
      factory.create(config(SourceKind.debug), null, zone: johannesburg),
      isA<FastAlarmsSource>(),
    );
  });
}
