import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/sources/device_calendar_api.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/agenda/agenda_screen.dart';
import 'package:tminus/features/health/health_screen.dart';
import 'package:tminus/features/onboarding/onboarding_screen.dart';
import 'package:tminus/features/sources/add_source_panel.dart';

import '../../core/fixtures.dart' show blue, occ;
import '../harness.dart';

const _ics = SourceConfig(
  id: 'ics-1',
  name: 'Work Outlook',
  color: blue,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.ics-1',
);

const _phone = SourceConfig(
  id: 'device-1',
  name: 'Personal',
  color: 0xFF5BC48A,
  kind: SourceKind.device,
  deviceCalendarId: '4',
);

/// The link of the tests. Nothing that must keep it out looks for more than
/// [_token], its one unusual path segment.
const _link = 'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';
const _token = 's3cr3t';

/// One event in the days after the harness's clock, so that a probe finds a
/// feed that works.
const _feed = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:a
DTSTART:20261006T100000Z
DTEND:20261006T103000Z
SUMMARY:Sprint planning
END:VEVENT
END:VCALENDAR
''';

/// What the engine's `queryDeviceCalendars` says when the permission is
/// missing, with a message that must never reach the screen or the log.
PlatformException _noCalendarAccess() => PlatformException(
  code: DeviceCalendarApi.permissionDenied,
  message: 'no access for https://secret.example/feed.ics',
);

/// Boots the app before onboarding, on a surface tall enough that nothing a
/// test taps is below the fold.
Future<Harness> _boot(
  WidgetTester t, {
  Future<void> Function(Harness h)? seed,
  http.Client? feeds,
}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  return pumpApp(t, onboarded: false, seed: seed, feeds: feeds);
}

/// Lets the database's watch streams deliver, and the frames that follow draw.
/// A write made from the test comes from outside the widget test's fake-async
/// zone, so it needs real turns of the event loop and then a pump.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => pumpEventQueue(times: 5));
    await t.pump();
  }
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

/// On the Permissions step, from a freshly booted app.
Future<void> _toPermissions(WidgetTester t) async {
  await _tap(t, 'getStarted');
  await _tap(t, 'skip');
}

/// On the test alarm step, from a freshly booted app.
Future<void> _toTestAlarm(WidgetTester t) async {
  await _toPermissions(t);
  await _tap(t, 'continue');
}

/// Taps **Ring a test alarm** and lets the engine call finish, which starts the
/// countdown at this moment of the test's fake clock.
Future<void> _ring(WidgetTester t) async {
  await t.tap(find.byKey(const Key('ringTestAlarm')));
  await t.pump();
  await t.pump();
}

/// The app comes back to the front, as after a settings screen.
Future<void> _resume(WidgetTester t) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
  }
  await t.pumpAndSettle();
}

/// The system Back button, as the engine reports it: a `popRoute` on the
/// navigation channel, which goes through the router and the navigator like
/// the real one.
Future<void> _systemBack(WidgetTester t) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await t.pump();
}

/// Records `SystemNavigator.pop`, which is what the system Back button comes to
/// when nothing in the app takes it: the app closes. Without this the call has
/// no platform to go to.
List<MethodCall> _recordExits() {
  final exits = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') exits.add(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return exits;
}

String _stepLabel(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('stepLabel'))).data!;

/// Which of the five segments of the progress strip are filled.
List<bool> _filled(WidgetTester t) {
  final scheme = Theme.of(t.element(find.byType(OnboardingScreen))).colorScheme;
  return [
    for (var i = 1; i <= 5; i++)
      (t.widget<Container>(find.byKey(Key('progress-$i'))).decoration!
                  as BoxDecoration)
              .color ==
          scheme.primary,
  ];
}

bool _canPress(WidgetTester t, String key) =>
    t.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

/// Whether [id]'s row reads "Allowed" (and so has no button).
bool _allowed(WidgetTester t, String id) {
  final row = find.byKey(Key('permission-$id'));
  expect(row, findsOneWidget, reason: id);
  final tick = find.descendant(of: row, matching: find.text('Allowed'));
  final button = find.byKey(Key('allow-$id'));
  expect(
    tick.evaluate().length + button.evaluate().length,
    1,
    reason: '$id has either the tick or the button',
  );
  return tick.evaluate().isNotEmpty;
}

/// The settings screens the engine was asked to open, by kind.
List<Object?> _opened(Harness h) => [
  for (final c in h.engineCalls)
    if (c.method == 'openPermissionSettings') c.arguments,
];

/// Answers the engine as the harness does, except for the methods in [custom]:
/// each of those is called with the call and may throw. Every call is recorded
/// in `h.engineCalls` as before.
void _engine(Harness h, Map<String, Object? Function(MethodCall)> custom) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(AlarmEngine.methodChannelName),
        (call) async {
          h.engineCalls.add(call);
          final answer = custom[call.method];
          if (answer != null) return answer(call);
          return switch (call.method) {
            'getHealth' => h.health,
            'queryDeviceCalendars' => h.deviceCalendars,
            _ => null,
          };
        },
      );
}

/// Runs [body] with everything the app logs collected into the list it is
/// given. The log hook goes back before the test body ends, not in a
/// tear-down: the framework checks that it is back before tear-downs run.
Future<void> _logging(Future<void> Function(List<String> logged) body) async {
  final logged = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => logged.add(message ?? '');
  try {
    await body(logged);
  } finally {
    debugPrint = original;
  }
}

Finder _snack(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

/// Waits out the snack bar that is up (they show one at a time, so one that is
/// queued behind it shows only now), so that "nothing else was said" can be
/// asked of what is on the screen afterwards.
Future<void> _waitOutSnackBar(WidgetTester t) async {
  // Let it finish sliding in first: its time on screen starts then.
  await t.pumpAndSettle();
  await t.pump(const Duration(seconds: 5));
  await t.pumpAndSettle();
}

/// Every row of every table, as text.
Future<String> _dump(WidgetTester t, AppDatabase db) async {
  final out = StringBuffer();
  await t.runAsync(() async {
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    for (final table in tables) {
      final name = table.read<String>('name');
      for (final row in await db.customSelect('SELECT * FROM "$name"').get()) {
        out.writeln('$name: ${row.data}');
      }
    }
  });
  return out.toString();
}

/// An `AppSettings` whose first [failures] writes of "onboarding is done" fail,
/// with a message that quotes a feed link.
class _FlakyFinish extends AppSettings {
  _FlakyFinish(super.settings, {required this.failures});

  int failures;

  @override
  Future<void> setOnboardingDone(bool v) {
    if (v && failures > 0) {
      failures--;
      return Future.error(StateError('could not write https://secret.example'));
    }
    return super.setOnboardingDone(v);
  }
}

/// An `AppSettings` whose watch on the onboarding flag answers [lag] late, as a
/// database stream does after a write: the router's gate hears of a change a
/// moment after it was stored. (The test's in-memory database answers at once.)
class _LateFlag extends AppSettings {
  _LateFlag(super.settings, {required this.lag});

  final Duration lag;

  @override
  Stream<bool> watchOnboardingDone() =>
      super.watchOnboardingDone().asyncMap((done) async {
        await Future<void>.delayed(lag);
        return done;
      });
}

void main() {
  testWidgets('the steps move forward and back with the progress strip', (
    t,
  ) async {
    final h = await _boot(t);

    // Welcome: no strip, no Back, and the way on.
    expect(find.byKey(const Key('step-welcome')), findsOneWidget);
    expect(find.text("Meetings you can't miss"), findsOneWidget);
    expect(
      find.text(
        "T-Minus turns your calendar into alarms you can't miss, and can "
        'always stop.',
      ),
      findsOneWidget,
    );
    expect(find.text('Your calendar never leaves your phone.'), findsOneWidget);
    expect(find.byKey(const Key('stepLabel')), findsNothing);
    expect(find.byKey(const Key('back')), findsNothing);
    await _tap(t, 'getStarted');

    expect(find.byKey(const Key('step-calendar')), findsOneWidget);
    expect(find.text('Add your calendar'), findsOneWidget);
    expect(find.text('You can add more later in Sources.'), findsOneWidget);
    expect(_stepLabel(t), 'STEP 2 OF 5');
    expect(_filled(t), [true, true, false, false, false]);

    await _tap(t, 'skip');
    expect(find.byKey(const Key('step-permissions')), findsOneWidget);
    expect(find.text('Alarms need a few permissions.'), findsOneWidget);
    expect(_stepLabel(t), 'STEP 3 OF 5');
    expect(_filled(t), [true, true, true, false, false]);

    await _tap(t, 'continue');
    expect(find.byKey(const Key('step-testAlarm')), findsOneWidget);
    expect(find.text("Let's make sure it rings"), findsOneWidget);
    expect(_stepLabel(t), 'STEP 4 OF 5');
    expect(_filled(t), [true, true, true, true, false]);

    // Back, all the way to the welcome step.
    await _tap(t, 'back');
    expect(_stepLabel(t), 'STEP 3 OF 5');
    expect(_filled(t), [true, true, true, false, false]);
    await _tap(t, 'back');
    expect(_stepLabel(t), 'STEP 2 OF 5');
    expect(_filled(t), [true, true, false, false, false]);
    await _tap(t, 'back');
    expect(find.byKey(const Key('step-welcome')), findsOneWidget);
    expect(find.byKey(const Key('stepLabel')), findsNothing);

    // And forward to the end: the whole strip, and nothing to go back to.
    await _tap(t, 'getStarted');
    await _tap(t, 'skip');
    await _tap(t, 'continue');
    await _tap(t, 'skip');
    expect(find.byKey(const Key('step-done')), findsOneWidget);
    expect(find.text("You're set."), findsOneWidget);
    expect(_stepLabel(t), 'STEP 5 OF 5');
    expect(_filled(t), [true, true, true, true, true]);
    expect(find.byKey(const Key('back')), findsNothing);
    // Skipping the test did not ring anything.
    expect(h.engineCalls.where((c) => c.method == 'testAlarm'), isEmpty);
    await h.dispose(t);
  });

  testWidgets('Continue on Add your calendar waits for a source, and Skip '
      'moves on', (t) async {
    final h = await _boot(t);
    await _tap(t, 'getStarted');

    // Nothing to continue with yet.
    expect(find.byType(AddSourcePanel), findsOneWidget);
    expect(_canPress(t, 'continue'), isFalse);
    await t.tap(find.byKey(const Key('continue')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('step-calendar')), findsOneWidget);

    // Skip for now moves on all the same, and Back comes back to the wait.
    await _tap(t, 'skip');
    expect(find.byKey(const Key('step-permissions')), findsOneWidget);
    await _tap(t, 'back');
    expect(find.byKey(const Key('step-calendar')), findsOneWidget);
    expect(_canPress(t, 'continue'), isFalse);

    // A source appears (the panel adds one, or a restore leaves some).
    await t.runAsync(() => getIt<SourceRepository>().save(_ics));
    await _settle(t);
    expect(_canPress(t, 'continue'), isTrue);

    await _tap(t, 'continue');
    expect(find.byKey(const Key('step-permissions')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('a restored install says the calendars come from the backup', (
    t,
  ) async {
    final h = await _boot(
      t,
      seed: (h) async {
        // What a restore leaves: the old phone's calendars, switched off and
        // waiting for their link or calendar.
        final sources = getIt<SourceRepository>();
        await sources.save(_ics.copyWith(enabled: false));
        await sources.save(_phone.copyWith(enabled: false));
        final settings = getIt<AppSettings>();
        await settings.setSourceSetup('ics-1', SourceSetup.needsLink);
        await settings.setSourceSetup('device-1', SourceSetup.needsCalendar);
        await settings.setRestorePending(true);
      },
    );
    await _tap(t, 'getStarted');
    await _settle(t);

    expect(
      find.text(
        "You have 2 calendars from your backup. You'll re-link them in "
        'Sources after setup.',
      ),
      findsOneWidget,
    );
    // The panel that adds a calendar is not offered; Continue is.
    expect(find.byType(AddSourcePanel), findsNothing);
    expect(_canPress(t, 'continue'), isTrue);
    await _tap(t, 'continue');
    expect(find.byKey(const Key('step-permissions')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the calendar row appears only with a phone source', (t) async {
    final h = await _boot(t, seed: (h) => getIt<SourceRepository>().save(_ics));
    await _tap(t, 'getStarted');
    await _settle(t);
    await _tap(t, 'continue');

    // A feed alone needs no permission to read.
    expect(find.byKey(const Key('permission-notifications')), findsOneWidget);
    expect(find.byKey(const Key('permission-battery')), findsOneWidget);
    expect(find.byKey(const Key('permission-calendar')), findsNothing);
    expect(find.text('Calendar access'), findsNothing);

    // A phone calendar is a source: the row is there, with its reason.
    await _tap(t, 'back');
    await t.runAsync(() => getIt<SourceRepository>().save(_phone));
    await _settle(t);
    await _tap(t, 'continue');
    expect(find.byKey(const Key('permission-calendar')), findsOneWidget);
    expect(find.text('Calendar access'), findsOneWidget);
    expect(
      find.text("So T-Minus can read your phone's calendars."),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('Allow notifications requests the runtime permission', (t) async {
    final h = await _boot(
      t,
      seed: (h) async {
        h.health = {...healthyEngine(), 'notificationsEnabled': false};
      },
    );
    await _toPermissions(t);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('So alerts can appear.'), findsOneWidget);
    expect(find.byKey(const Key('allow-notifications')), findsOneWidget);
    expect(
      find.text('Without notifications no alarm can be shown.'),
      findsOneWidget,
    );

    // The user taps Allow, and says yes in the system dialog.
    h.ui['requestPermission'] = (_) {
      h.health = {...h.health, 'notificationsEnabled': true};
      return 'granted';
    };
    await _tap(t, 'allow-notifications');

    final asked = h.uiCalls.where((c) => c.method == 'requestPermission');
    expect(asked.map((c) => c.arguments), [
      {'kind': 'notifications'},
    ]);
    // The row now shows what the engine says: a tick and "Allowed".
    expect(_allowed(t, 'notifications'), isTrue);
    expect(find.byKey(const Key('notificationsWarning')), findsNothing);
    // Granted: there is no settings screen to send the user to.
    expect(_opened(h), isEmpty);
    await h.dispose(t);
  });

  testWidgets('the test alarm asks the engine for an alarm in 5 seconds', (
    t,
  ) async {
    final h = await _boot(t);
    await _toTestAlarm(t);
    expect(
      t.widget<Text>(find.byKey(const Key('testNumber'))).data,
      '5',
      reason: 'ready to start',
    );
    expect(find.text('READY'), findsOneWidget);
    expect(h.engineCalls.where((c) => c.method == 'testAlarm'), isEmpty);

    await _ring(t);

    final asked = h.engineCalls.where((c) => c.method == 'testAlarm');
    expect(asked.map((c) => c.arguments), [
      {'strength': 'alarm', 'delaySec': 5},
    ]);
    expect(find.text('Ringing in 5 seconds…'), findsOneWidget);

    // The countdown: 5, 4, 3, 2, 1, and then the question.
    for (final left in [4, 3, 2, 1]) {
      await t.pump(const Duration(seconds: 1));
      expect(t.widget<Text>(find.byKey(const Key('testNumber'))).data, '$left');
      expect(find.text('Ringing in 5 seconds…'), findsOneWidget);
    }
    expect(find.byKey(const Key('itRang')), findsNothing);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Did it ring?'), findsOneWidget);
    expect(find.byKey(const Key('itRang')), findsOneWidget);
    expect(find.byKey(const Key('itDidntRing')), findsOneWidget);
    // One request was enough.
    expect(h.engineCalls.where((c) => c.method == 'testAlarm'), hasLength(1));

    // It rang: on to the last step, with onboarding not finished by it.
    await _tap(t, 'itRang');
    expect(find.byKey(const Key('step-done')), findsOneWidget);
    expect(
      await t.runAsync(() => getIt<AppSettings>().onboardingDone()),
      false,
    );
    await h.dispose(t);
  });

  testWidgets('Go to Agenda finishes onboarding and lands on the Agenda', (
    t,
  ) async {
    final h = await _boot(t);
    await _toTestAlarm(t);
    await _tap(t, 'skip');
    expect(find.text('Go to Agenda'), findsOneWidget);

    await t.tap(find.byKey(const Key('goToAgenda')));
    await _settle(t);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(AgendaScreen), findsOneWidget);
    expect(await t.runAsync(() => getIt<AppSettings>().onboardingDone()), true);
    await h.dispose(t);
  });

  testWidgets("It didn't ring finishes onboarding and opens Health", (t) async {
    final h = await _boot(t);
    await _toTestAlarm(t);
    await _ring(t);
    await t.pump(const Duration(seconds: 5));
    expect(find.text("It didn't ring"), findsOneWidget);

    await t.tap(find.byKey(const Key('itDidntRing')));
    await _settle(t);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HealthScreen), findsOneWidget);
    expect(find.byType(AgendaScreen), findsNothing);
    expect(h.router.routerDelegate.currentConfiguration.uri.path, '/health');
    expect(await t.runAsync(() => getIt<AppSettings>().onboardingDone()), true);
    await h.dispose(t);
  });

  // Beyond the plan's list from here on.

  testWidgets("It didn't ring opens Health even when the router hears of the "
      'finished onboarding late', (t) async {
    final h = await _boot(
      t,
      seed: (h) async {
        // The gate is built after the seed, on this.
        final late = _LateFlag(
          getIt<SettingsRepository>(),
          lag: const Duration(milliseconds: 500),
        );
        await getIt.unregister<AppSettings>();
        getIt.registerSingleton<AppSettings>(late);
      },
    );
    await _toTestAlarm(t);
    await _ring(t);
    await t.pump(const Duration(seconds: 5));

    await t.tap(find.byKey(const Key('itDidntRing')));
    await _settle(t);

    // A `go` made while the gate still said "not done" would have been sent
    // back to onboarding.
    expect(find.byType(HealthScreen), findsOneWidget);
    expect(h.router.routerDelegate.currentConfiguration.uri.path, '/health');

    // And the news that reaches the gate afterwards leaves it there.
    await t.pump(const Duration(seconds: 1));
    await _settle(t);
    expect(find.byType(HealthScreen), findsOneWidget);
    expect(find.byType(AgendaScreen), findsNothing);
    await h.dispose(t);
  });

  test('the lines that count calendars and meetings follow the number', () {
    expect(
      restoredText(1),
      "You have 1 calendar from your backup. You'll re-link it in Sources "
      'after setup.',
    );
    expect(
      restoredText(3),
      "You have 3 calendars from your backup. You'll re-link them in Sources "
      'after setup.',
    );
    expect(
      alarmedMeetingsText(0),
      'No meetings in the next 7 days have alarms.',
    );
    expect(alarmedMeetingsText(1), '1 meeting in the next 7 days has alarms.');
    expect(
      alarmedMeetingsText(12),
      '12 meetings in the next 7 days have alarms.',
    );
  });

  testWidgets('a restore marker with no calendars left is the ordinary step', (
    t,
  ) async {
    final h = await _boot(
      t,
      seed: (h) => getIt<AppSettings>().setRestorePending(true),
    );
    await _tap(t, 'getStarted');
    await _settle(t);

    // "You have 0 calendars from your backup" would help nobody.
    expect(find.byType(AddSourcePanel), findsOneWidget);
    expect(find.byKey(const Key('restoredCard')), findsNothing);
    expect(_canPress(t, 'continue'), isFalse);
    await h.dispose(t);
  });

  testWidgets('a phone that is set up shows every permission as allowed', (
    t,
  ) async {
    final h = await _boot(t);
    await _toPermissions(t);

    // Read from the engine when the step opened (the harness never starts the
    // Health monitor): a tick each, and no button, no warning.
    expect(_allowed(t, 'notifications'), isTrue);
    expect(_allowed(t, 'battery'), isTrue);
    expect(find.text('Allowed'), findsNWidgets(2));
    expect(find.text('Allow'), findsNothing);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text("So Android doesn't delay alarms."), findsOneWidget);
    // Full-screen alarms are offered only while they are not allowed.
    expect(find.byKey(const Key('permission-fullScreen')), findsNothing);
    expect(find.byKey(const Key('notificationsWarning')), findsNothing);
    expect(h.engineCalls.where((c) => c.method == 'getHealth'), isNotEmpty);
    await h.dispose(t);
  });

  testWidgets('Battery opens its settings and reads Allowed when the app is '
      'back', (t) async {
    final h = await _boot(
      t,
      seed: (h) async {
        h.health = {...healthyEngine(), 'ignoringBatteryOptimizations': false};
      },
    );
    await _toPermissions(t);
    expect(_allowed(t, 'battery'), isFalse);

    await _tap(t, 'allow-battery');
    expect(_opened(h), [
      {'kind': 'batteryOptimization'},
    ]);
    // The settings screen is open: the user is not back yet.
    expect(_allowed(t, 'battery'), isFalse);

    // The user exempts the app there, and comes back.
    h.health = healthyEngine();
    await _resume(t);

    expect(_allowed(t, 'battery'), isTrue);
    await h.dispose(t);
  });

  testWidgets('Full-screen alarms are offered while they are off, and go '
      'once they are on', (t) async {
    final h = await _boot(
      t,
      seed: (h) async {
        h.health = {...healthyEngine(), 'canUseFullScreenIntent': false};
      },
    );
    await _toPermissions(t);

    expect(find.text('Full-screen alarms'), findsOneWidget);
    expect(
      find.text('So an alarm fills the screen, even when locked.'),
      findsOneWidget,
    );
    expect(_allowed(t, 'fullScreen'), isFalse);
    await _tap(t, 'allow-fullScreen');
    expect(_opened(h), [
      {'kind': 'fullScreenIntent'},
    ]);

    h.health = healthyEngine();
    await _resume(t);

    expect(find.byKey(const Key('permission-fullScreen')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a refusal sends the user to the notification settings only '
      'where asking again cannot help', (t) async {
    final h = await _boot(
      t,
      seed: (h) async {
        h.health = {...healthyEngine(), 'notificationsEnabled': false};
      },
    );
    await _toPermissions(t);

    // Refused once on a recent Android: Allow asks again, nothing else opens.
    h.ui['requestPermission'] = (_) => 'denied';
    await _tap(t, 'allow-notifications');
    expect(_opened(h), isEmpty);
    expect(find.byKey(const Key('allow-notifications')), findsOneWidget);

    // Android will not ask again: the app's notification settings.
    h.ui['requestPermission'] = (_) => 'permanentlyDenied';
    await _tap(t, 'allow-notifications');
    expect(_opened(h), [
      {'kind': 'notifications'},
    ]);

    // Before Android 13 there is no dialog: a refusal means the switch is off.
    h.ui['requestPermission'] = (_) => 'denied';
    h.ui['deviceInfo'] = (_) => {
      'versionName': '1.0.0',
      'versionCode': 1,
      'manufacturer': 'Google',
      'sdkInt': 30,
    };
    await _tap(t, 'allow-notifications');
    expect(_opened(h), [
      {'kind': 'notifications'},
      {'kind': 'notifications'},
    ]);
    await h.dispose(t);
  });

  testWidgets('without notifications the warning shows and Continue still '
      'works', (t) async {
    final h = await _boot(
      t,
      seed: (h) async {
        h.health = {...healthyEngine(), 'notificationsEnabled': false};
        h.ui['requestPermission'] = (_) => 'denied';
      },
    );
    await _toPermissions(t);
    await _tap(t, 'allow-notifications');

    expect(find.byKey(const Key('notificationsWarning')), findsOneWidget);
    expect(_canPress(t, 'continue'), isTrue);
    await _tap(t, 'continue');
    expect(find.byKey(const Key('step-testAlarm')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('the calendar row asks for access, then offers Open settings, '
      'and follows the user back', (t) async {
    await _logging((logged) async {
      var access = false;
      final h = await _boot(
        t,
        seed: (h) async {
          await getIt<SourceRepository>().save(_phone);
          // The phone's calendars are refused until the permission is given.
          _engine(h, {
            'queryDeviceCalendars': (_) {
              if (!access) throw _noCalendarAccess();
              return <Object?>[];
            },
          });
        },
      );
      await _tap(t, 'getStarted');
      await _settle(t);
      await _tap(t, 'continue');

      // Nobody asked yet: the row is there with its button.
      expect(find.text('Calendar access'), findsOneWidget);
      expect(_allowed(t, 'calendar'), isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('permission-calendar')),
          matching: find.text('Allow'),
        ),
        findsOneWidget,
      );

      // Refused once: asking again is still possible.
      h.ui['requestPermission'] = (_) => 'denied';
      await _tap(t, 'allow-calendar');
      expect(
        h.uiCalls.where((c) => c.method == 'requestPermission').map((c) {
          return c.arguments;
        }),
        [
          {'kind': 'calendar'},
        ],
      );
      expect(_allowed(t, 'calendar'), isFalse);
      expect(find.text('Open settings'), findsNothing);

      // Refused for good: the row sends the user to the app's settings.
      h.ui['requestPermission'] = (_) => 'permanentlyDenied';
      await _tap(t, 'allow-calendar');
      expect(find.text('Open settings'), findsOneWidget);
      expect(h.uiCalls.where((c) => c.method == 'openAppDetails'), isEmpty);
      await _tap(t, 'allow-calendar');
      expect(
        h.uiCalls.where((c) => c.method == 'openAppDetails'),
        hasLength(1),
      );
      // It did not ask a third time.
      expect(
        h.uiCalls.where((c) => c.method == 'requestPermission'),
        hasLength(2),
      );

      // The user turns it on there and comes back.
      access = true;
      await _resume(t);
      expect(_allowed(t, 'calendar'), isTrue);
      expect(find.text('Open settings'), findsNothing);

      // And takes it away again: the row notices when the app comes back.
      access = false;
      await _resume(t);
      expect(_allowed(t, 'calendar'), isFalse);
      expect(find.text('Allow'), findsOneWidget);

      // What the phone said about the refusals stayed out of the log.
      expect(logged.join('\n'), isNot(contains('secret.example')));
      await h.dispose(t);
    });
  });

  testWidgets('a permission that cannot be asked for says so in fixed text and '
      'logs only the code', (t) async {
    await _logging((logged) async {
      final h = await _boot(
        t,
        seed: (h) async {
          h.health = {
            ...healthyEngine(),
            'notificationsEnabled': false,
            'ignoringBatteryOptimizations': false,
          };
          h.ui['requestPermission'] = (_) => throw PlatformException(
            code: 'busy',
            message: 'https://secret.example/feed.ics',
          );
          _engine(h, {
            'openPermissionSettings': (_) => throw PlatformException(
              code: 'no_settings',
              message: 'https://secret.example/feed.ics',
            ),
          });
        },
      );
      await _toPermissions(t);

      await _tap(t, 'allow-notifications');
      expect(_snack("Couldn't ask for the permission."), findsOneWidget);
      await _waitOutSnackBar(t);
      // Nothing else was said, in this or any other text.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('secret'), findsNothing);

      await _tap(t, 'allow-battery');
      expect(_snack("Couldn't open the settings."), findsOneWidget);
      await _waitOutSnackBar(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('secret'), findsNothing);

      expect(logged.where((l) => l.startsWith("Couldn't")), [
        "Couldn't ask for the permission. (busy)",
        "Couldn't open the settings. (no_settings)",
      ]);
      expect(logged.join('\n'), isNot(contains('secret')));
      await h.dispose(t);
    });
  });

  testWidgets('a test alarm the engine cannot start says so and can be tried '
      'again', (t) async {
    await _logging((logged) async {
      var failing = true;
      final h = await _boot(
        t,
        seed: (h) async {
          _engine(h, {
            'testAlarm': (_) {
              if (failing) {
                throw PlatformException(
                  code: 'no_alarm',
                  message: 'https://secret.example/feed.ics',
                );
              }
              return null;
            },
          });
        },
      );
      await _toTestAlarm(t);

      await _ring(t);
      expect(_snack("Couldn't start the test alarm."), findsOneWidget);
      await _waitOutSnackBar(t);
      expect(find.byType(SnackBar), findsNothing);
      // Nothing is counting, and the step is as it was.
      expect(find.byKey(const Key('testStatus')), findsNothing);
      expect(t.widget<Text>(find.byKey(const Key('testNumber'))).data, '5');
      expect(_canPress(t, 'ringTestAlarm'), isTrue);
      expect(_canPress(t, 'back'), isTrue);
      expect(logged.where((l) => l.startsWith("Couldn't")), [
        "Couldn't start the test alarm. (no_alarm)",
      ]);
      expect(logged.join('\n'), isNot(contains('secret')));

      // The next try works.
      failing = false;
      await _ring(t);
      expect(find.text('Ringing in 5 seconds…'), findsOneWidget);
      expect(h.engineCalls.where((c) => c.method == 'testAlarm'), hasLength(2));
      await h.dispose(t);
    });
  });

  testWidgets('the test step cannot be left while the alarm is on its way', (
    t,
  ) async {
    final h = await _boot(t);
    await _toTestAlarm(t);
    expect(_canPress(t, 'back'), isTrue);
    expect(find.byKey(const Key('skip')), findsOneWidget);

    await _ring(t);
    // Counting down: no way back, no way to skip, and no second alarm.
    expect(_canPress(t, 'back'), isFalse);
    expect(find.byKey(const Key('skip')), findsNothing);
    expect(_canPress(t, 'ringTestAlarm'), isFalse);

    // The question has two answers and nothing else.
    await t.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('back')), findsNothing);
    expect(find.byKey(const Key('skip')), findsNothing);
    expect(find.byKey(const Key('ringTestAlarm')), findsNothing);
    await h.dispose(t);
  });

  testWidgets('two quick taps on Ring a test alarm ask the engine once', (
    t,
  ) async {
    final h = await _boot(t);
    await _toTestAlarm(t);

    // Both taps land before a frame: the second finds the button as it was
    // drawn, still on.
    await t.tap(find.byKey(const Key('ringTestAlarm')));
    await t.tap(find.byKey(const Key('ringTestAlarm')));
    await t.pump();
    await t.pump();

    expect(h.engineCalls.where((c) => c.method == 'testAlarm'), hasLength(1));
    await h.dispose(t);
  });

  testWidgets('leaving during the countdown leaves no timer behind', (t) async {
    final h = await _boot(t);
    await _toTestAlarm(t);
    await _ring(t);
    expect(find.text('Ringing in 5 seconds…'), findsOneWidget);

    // The test binding fails a test that ends with a timer still running.
    await h.dispose(t);
  });

  testWidgets('the last step counts the meetings that have alarms', (t) async {
    final h = await _boot(
      t,
      seed: (h) async {
        await getIt<SourceRepository>().save(_ics);
        // The clock is 09:27 on Tuesday 6 October 2026 in Johannesburg.
        await getIt<OccurrenceRepository>().replaceForSource('ics-1', [
          occ(
            sourceId: 'ics-1',
            uid: 'later-today',
            title: 'Client demo',
            start: DateTime.utc(2026, 10, 6, 12),
          ),
          occ(
            sourceId: 'ics-1',
            uid: 'tomorrow',
            title: 'Standup',
            start: DateTime.utc(2026, 10, 7, 8),
          ),
          // Silent: a tentative meeting makes no alarm.
          occ(
            sourceId: 'ics-1',
            uid: 'maybe',
            title: 'Optional talk',
            start: DateTime.utc(2026, 10, 6, 13),
            busyStatus: BusyStatus.tentative,
          ),
          // Over already.
          occ(
            sourceId: 'ics-1',
            uid: 'earlier',
            title: 'Breakfast',
            start: DateTime.utc(2026, 10, 6, 5),
          ),
        ]);
      },
    );
    await _toTestAlarm(t);
    await _tap(t, 'skip');
    await _settle(t);

    expect(
      find.descendant(
        of: find.byKey(const Key('alarmed')),
        matching: find.text('2 meetings in the next 7 days have alarms.'),
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets('a finish that cannot be written says so and can be tried '
      'again', (t) async {
    await _logging((logged) async {
      final h = await _boot(
        t,
        seed: (h) async {
          final flaky = _FlakyFinish(getIt<SettingsRepository>(), failures: 1);
          await getIt.unregister<AppSettings>();
          getIt.registerSingleton<AppSettings>(flaky);
        },
      );
      await _toTestAlarm(t);
      await _tap(t, 'skip');

      await _tap(t, 'goToAgenda');
      expect(_snack("Couldn't finish the setup."), findsOneWidget);
      await _waitOutSnackBar(t);
      expect(find.byType(SnackBar), findsNothing);
      // Still here, with the button back.
      expect(find.byKey(const Key('step-done')), findsOneWidget);
      expect(_canPress(t, 'goToAgenda'), isTrue);
      expect(logged.where((l) => l.startsWith("Couldn't")), [
        "Couldn't finish the setup. (StateError)",
      ]);
      expect(logged.join('\n'), isNot(contains('secret')));

      await t.tap(find.byKey(const Key('goToAgenda')));
      await _settle(t);
      expect(find.byType(AgendaScreen), findsOneWidget);
      await h.dispose(t);
    });
  });

  testWidgets('system Back on Permissions goes back to Add your calendar and '
      'does not leave onboarding', (t) async {
    final h = await _boot(t);
    final exits = _recordExits();
    await _toPermissions(t);
    expect(_stepLabel(t), 'STEP 3 OF 5');

    await _systemBack(t);

    // Still onboarding, one step back; the app was not closed.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byKey(const Key('step-calendar')), findsOneWidget);
    expect(_stepLabel(t), 'STEP 2 OF 5');
    expect(exits, isEmpty);
    await h.dispose(t);
  });

  testWidgets('system Back goes back one step at a time and closes the app '
      'only from the first step', (t) async {
    final h = await _boot(t);
    final exits = _recordExits();
    await _toTestAlarm(t);
    expect(_stepLabel(t), 'STEP 4 OF 5');

    // The test step, not yet started, is left like any other.
    await _systemBack(t);
    expect(_stepLabel(t), 'STEP 3 OF 5');
    await _systemBack(t);
    expect(_stepLabel(t), 'STEP 2 OF 5');
    await _systemBack(t);
    expect(find.byKey(const Key('step-welcome')), findsOneWidget);
    expect(find.byKey(const Key('stepLabel')), findsNothing);
    expect(exits, isEmpty, reason: 'nothing closed the app on the way');

    // The first step has nothing to go back to: Back closes the app, as it
    // would anywhere else in it.
    await _systemBack(t);
    expect(exits, hasLength(1));
    await h.dispose(t);
  });

  testWidgets('system Back does nothing while the test alarm is on its way', (
    t,
  ) async {
    final h = await _boot(t);
    final exits = _recordExits();
    await _toTestAlarm(t);
    await _ring(t);

    // Counting down: it neither leaves the step nor closes the app, and the
    // countdown goes on.
    await _systemBack(t);
    expect(find.byKey(const Key('step-testAlarm')), findsOneWidget);
    expect(find.text('Ringing in 5 seconds…'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(t.widget<Text>(find.byKey(const Key('testNumber'))).data, '3');
    await _systemBack(t);
    expect(find.byKey(const Key('step-testAlarm')), findsOneWidget);
    expect(find.text('Ringing in 5 seconds…'), findsOneWidget);

    // Waiting for the answer: the same, and the answer is still wanted.
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Did it ring?'), findsOneWidget);
    await _systemBack(t);
    expect(find.text('Did it ring?'), findsOneWidget);
    expect(find.byKey(const Key('itRang')), findsOneWidget);
    expect(exits, isEmpty);

    await _tap(t, 'itRang');
    expect(find.byKey(const Key('step-done')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('system Back on the last step stays there until Go to Agenda', (
    t,
  ) async {
    final h = await _boot(t);
    final exits = _recordExits();
    await _toTestAlarm(t);
    await _tap(t, 'skip');
    expect(find.byKey(const Key('step-done')), findsOneWidget);

    // Done is not left by accident: it neither goes back to the test nor
    // closes the app with the setup unfinished.
    await _systemBack(t);
    expect(find.byKey(const Key('step-done')), findsOneWidget);
    expect(_stepLabel(t), 'STEP 5 OF 5');
    expect(exits, isEmpty);

    // And the button still finishes it.
    await t.tap(find.byKey(const Key('goToAgenda')));
    await _settle(t);
    expect(find.byType(AgendaScreen), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('every step fits a small phone at a large text size', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
    final h = await pumpApp(
      t,
      onboarded: false,
      seed: (h) async {
        // The longest Permissions step there is: every row, and the warning.
        h.health = {
          ...healthyEngine(),
          'notificationsEnabled': false,
          'canUseFullScreenIntent': false,
          'ignoringBatteryOptimizations': false,
        };
        await getIt<SourceRepository>().save(_phone);
      },
    );

    /// The step's main button is on the screen, with no overflow reported on
    /// the way (the test binding fails a test that has one).
    void expectOnScreen(String key) {
      final rect = t.getRect(find.byKey(Key(key)));
      expect(rect.bottom, lessThanOrEqualTo(640), reason: key);
      expect(rect.right, lessThanOrEqualTo(360), reason: key);
    }

    expectOnScreen('getStarted');
    await _tap(t, 'getStarted');
    await _settle(t);
    expectOnScreen('continue');
    expectOnScreen('skip');
    await _tap(t, 'continue');
    expect(find.byKey(const Key('permission-calendar')), findsOneWidget);
    expect(find.byKey(const Key('permission-fullScreen')), findsOneWidget);
    expectOnScreen('continue');
    await _tap(t, 'continue');
    expectOnScreen('ringTestAlarm');
    await _ring(t);
    await t.pump(const Duration(seconds: 5));
    expectOnScreen('itRang');
    expectOnScreen('itDidntRing');
    await _tap(t, 'itRang');
    expectOnScreen('goToAgenda');
    await h.dispose(t);
  });

  testWidgets('adding a calendar here keeps the panel, enables Continue and '
      'keeps the link out of everything else', (t) async {
    await _logging((logged) async {
      final h = await _boot(
        t,
        feeds: MockClient((_) async => http.Response(_feed, 200)),
      );
      await _tap(t, 'getStarted');

      await t.enterText(find.byKey(const Key('icsLinkField')), _link);
      await t.pump();
      await _tap(t, 'checkLink');
      await _tap(t, 'addCalendar');
      await _settle(t);

      // The panel says what was added, in the onboarding words, and stays.
      expect(
        t.widget<Text>(find.byKey(const Key('addedNote'))).data,
        'Added Work Outlook. You can add another calendar, or continue.',
      );
      expect(find.byKey(const Key('step-calendar')), findsOneWidget);
      expect(h.syncs, [SyncTrigger.manual]);
      // Continue follows the source that now exists.
      expect(_canPress(t, 'continue'), isTrue);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('icsLinkField')))
            .controller!
            .text,
        isEmpty,
      );

      // The link is in secure storage and nowhere else.
      expect(h.secrets.values, [_link]);
      expect(await _dump(t, h.db), isNot(contains(_token)));
      expect(logged.join('\n'), isNot(contains(_token)));
      expect(find.byType(SnackBar), findsNothing);
      final route = h.router.routerDelegate.currentConfiguration;
      expect(route.uri.toString(), '/onboarding');
      expect(route.extra, isNull);
      await h.dispose(t);
    });
  });
}
