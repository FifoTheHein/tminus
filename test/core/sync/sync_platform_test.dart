import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/sync/device_zone.dart';
import 'package:tminus/core/sync/sync_platform.dart';

import '../fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(SyncPlatform.channelName);
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });

  setUp(initZones);

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
    tz.setLocalLocation(tz.UTC);
  });

  test(
    'every call uses the method names and argument keys Kotlin reads',
    () async {
      answer((call) => call.method == 'acquireLock' ? true : null);
      final p = SyncPlatform();
      expect(await p.acquireLock('o', const Duration(minutes: 5)), isTrue);
      await p.releaseLock('o');
      await p.configure(
        watchCalendars: true,
        preSyncTimes: [DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true)],
      );
      await p.postSourceNotice(
        kind: SourceNoticeKind.stale,
        sourceId: 'w',
        title: 't',
        text: 'x',
      );
      await p.cancelSourceNotice(kind: SourceNoticeKind.broken, sourceId: 'w');
      await p.requestSync('manual');
      await p.finished('ok');

      expect(calls.map((c) => [c.method, c.arguments]), [
        [
          'acquireLock',
          {'owner': 'o', 'leaseMs': 300000},
        ],
        [
          'releaseLock',
          {'owner': 'o'},
        ],
        [
          'configure',
          {
            'watchCalendars': true,
            'preSyncTimesMs': [1000],
            'quietUntilMs': null,
            'quietText': null,
          },
        ],
        [
          'postSourceNotice',
          {'kind': 'stale', 'sourceId': 'w', 'title': 't', 'text': 'x'},
        ],
        [
          'cancelSourceNotice',
          {'kind': 'broken', 'sourceId': 'w'},
        ],
        [
          'requestSync',
          {'trigger': 'manual'},
        ],
        [
          'finished',
          {'outcome': 'ok'},
        ],
      ]);
    },
  );

  test('installId returns the native id', () async {
    answer((c) => c.method == 'installId' ? 'id-1' : null);
    expect(await SyncPlatform().installId(), 'id-1');
    expect(calls.single.method, 'installId');
  });

  test('takeQuietRequest reads the action and its time', () async {
    answer(
      (c) => c.method == 'takeQuietRequest'
          ? {'action': 'mute', 'atMs': 1000}
          : null,
    );
    final r = await SyncPlatform().takeQuietRequest();
    expect(r!.mute, isTrue);
    expect(r.atUtc, DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true));
    answer((_) => null);
    expect(await SyncPlatform().takeQuietRequest(), isNull);
  });

  test('a malformed quiet request reads as null', () async {
    const malformed = <Map<String, Object?>>[
      {'action': 'mute', 'atMs': '1000'},
      {'action': 'mute', 'atMs': 1000.5},
      {'action': 'mute', 'atMs': null},
      {'action': 'mute'},
      {'action': 'pause', 'atMs': 1000},
      {'action': null, 'atMs': 1000},
      {'atMs': 1000},
    ];
    for (final reply in malformed) {
      answer((c) => c.method == 'takeQuietRequest' ? reply : null);
      expect(
        await SyncPlatform().takeQuietRequest(),
        isNull,
        reason: 'reply $reply',
      );
    }

    // The guard lets a well-formed end request through.
    answer(
      (c) => c.method == 'takeQuietRequest'
          ? {'action': 'end', 'atMs': 1000}
          : null,
    );
    final end = await SyncPlatform().takeQuietRequest();
    expect(end!.mute, isFalse);
    expect(end.atUtc, DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true));
  });

  test('a reply that is not a map reads as null', () async {
    // The reply comes from another process: a wrong shape drops the request
    // rather than throwing into the sync that asked.
    const replies = <Object?>[
      'mute',
      <Object?>['mute', 1000],
    ];
    for (final reply in replies) {
      answer((c) => c.method == 'takeQuietRequest' ? reply : null);
      expect(
        await SyncPlatform().takeQuietRequest(),
        isNull,
        reason: 'reply $reply',
      );
    }
  });

  test('a map that is not keyed by strings reads as null', () async {
    answer(
      (c) => c.method == 'takeQuietRequest'
          ? <Object?, Object?>{1: 'mute', 2: 1000}
          : null,
    );
    expect(await SyncPlatform().takeQuietRequest(), isNull);
  });

  test('configure sends the quiet end and text', () async {
    answer((_) => null);
    await SyncPlatform().configure(
      watchCalendars: false,
      preSyncTimes: const [],
      quietUntil: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
      quietText: 'Until 07:00',
    );
    expect(calls.single.arguments, {
      'watchCalendars': false,
      'preSyncTimesMs': <int>[],
      'quietUntilMs': 5000,
      'quietText': 'Until 07:00',
    });
  });

  test(
    'a syncFinished call from Kotlin reaches backgroundSyncFinished',
    () async {
      final platform = SyncPlatform();
      final seen = <String>[];
      final sub = platform.backgroundSyncFinished.listen(seen.add);
      await messenger.handlePlatformMessage(
        SyncPlatform.channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('syncFinished', {
            'trigger': 'periodic',
            'outcome': 'ok',
          }),
        ),
        (_) {},
      );
      expect(seen, ['periodic']);
      await sub.cancel();
    },
  );

  test('initDeviceZone sets tz.local from the device', () async {
    answer((_) => 'Africa/Johannesburg');
    expect(await initDeviceZone(SyncPlatform()), 'Africa/Johannesburg');
    expect(tz.local.name, 'Africa/Johannesburg');
  });

  test(
    'an unknown zone, no answer or a missing native side keeps tz.local',
    () async {
      final before = tz.local.name;
      answer((_) => 'Mars/Olympus_Mons');
      expect(await initDeviceZone(SyncPlatform()), before);
      answer((_) => null);
      expect(await initDeviceZone(SyncPlatform()), before);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await initDeviceZone(SyncPlatform()), before);
    },
  );
}
