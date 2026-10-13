import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/platform/ui_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(UiPlatform.channelName);
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('calls use the names and argument keys Kotlin reads', () async {
    answer(
      (c) => switch (c.method) {
        'requestPermission' => 'permanentlyDenied',
        'pickAlarmTone' => {
          'picked': true,
          'uri': 'content://t/1',
          'title': 'Beep',
        },
        'toneTitle' => null,
        'openUrl' => true,
        'createDocument' => true,
        'openDocument' => '{}',
        'deviceInfo' => {
          'versionName': '1.0.0',
          'versionCode': 42,
          'manufacturer': 'samsung',
          'sdkInt': 36,
        },
        _ => null,
      },
    );
    final ui = UiPlatform();
    expect(
      await ui.requestPermission(UiPermission.calendar),
      PermissionResult.permanentlyDenied,
    );
    final tone = await ui.pickAlarmTone(current: 'content://t/0');
    expect((tone!.uri, tone.title), ('content://t/1', 'Beep'));
    expect(await ui.toneTitle(null), UiPlatform.defaultToneTitle);
    expect(await ui.openUrl('https://x'), isTrue);
    expect(await ui.createDocument(name: 'a.json', text: '{}'), isTrue);
    expect(await ui.openDocument(), '{}');
    final info = await ui.deviceInfo();
    expect(
      (info.versionName, info.versionCode, info.manufacturer, info.sdkInt),
      ('1.0.0', 42, 'samsung', 36),
    );

    expect(calls.map((c) => [c.method, c.arguments]), [
      [
        'requestPermission',
        {'kind': 'calendar'},
      ],
      [
        'pickAlarmTone',
        {'current': 'content://t/0'},
      ],
      [
        'toneTitle',
        {'uri': null},
      ],
      [
        'openUrl',
        {'url': 'https://x'},
      ],
      [
        'createDocument',
        {'name': 'a.json', 'text': '{}'},
      ],
      ['openDocument', null],
      ['deviceInfo', null],
    ]);
  });

  test(
    'a cancelled tone pick and an unknown permission answer are safe',
    () async {
      answer(
        (c) => switch (c.method) {
          'pickAlarmTone' => {'picked': false},
          'requestPermission' => 'something new',
          _ => null,
        },
      );
      final ui = UiPlatform();
      expect(await ui.pickAlarmTone(), isNull);
      expect(
        await ui.requestPermission(UiPermission.notifications),
        PermissionResult.denied,
      );
    },
  );

  test('a picked default tone has no uri', () async {
    answer((_) => {'picked': true, 'uri': null, 'title': 'Default alarm tone'});
    final tone = await UiPlatform().pickAlarmTone();
    expect(tone!.uri, isNull);
  });
}
