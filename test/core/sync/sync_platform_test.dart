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
