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
