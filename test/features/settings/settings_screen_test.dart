import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme_mode_controller.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/core/transfer/settings_transfer.dart';
import 'package:tminus/features/settings/developer_tools_screen.dart';
import 'package:tminus/features/settings/settings_screen.dart';
import 'package:tminus/features/token_preview/sync_debug_panel.dart';
import 'package:tminus/features/token_preview/token_preview_screen.dart';

import '../../core/fixtures.dart' show blue;
import '../harness.dart';

const _focus = AlertProfile(
  id: 'p-focus',
  name: 'Focus',
  alerts: [
    AlertSpec(3, AlertStrength.alarm),
    AlertSpec(15, AlertStrength.headsUp),
  ],
);

/// A profile that is on the phone before an import and not in the file.
const _old = AlertProfile(
  id: 'p-old',
  name: 'Old',
  alerts: [AlertSpec(5, AlertStrength.headsUp)],
);

/// A calendar that is on the phone before an import, and stays.
const _kept = SourceConfig(
  id: 'ics-keep',
  name: 'Keep me',
  color: blue,
  kind: SourceKind.ics,
  secureStorageKey: 'ics-url.ics-keep',
);

Map<String, Object?> _profileJson(AlertProfile p) => {
  'id': p.id,
  'name': p.name,
  'alerts': alertsToJson(p.alerts),
  'sound': p.sound.toJson(),
  'ringsInQuietMode': p.ringsInQuietMode,
};

/// A settings file as `SettingsTransfer` reads it: the four built-in profiles
/// and Focus, two rules, two calendars, Focus as the default, merging off. A
/// [themeMode] of null is a file that says nothing about the theme.
String _settingsFile({String? themeMode = 'dark'}) => jsonEncode({
  'format': 'tminus-settings',
  'version': 1,
  'exportedAtUtc': '2026-10-11T08:00:00.000Z',
  'profiles': [
    for (final p in [...BuiltInProfiles.all, _focus]) _profileJson(p),
  ],
  'rules': [
    {
      'id': 'r-1',
      'position': 0,
      'field': 'title',
      'match': 'contains',
      'pattern': 'standup',
      'profileId': 'p-focus',
    },
    {
      'id': 'r-2',
      'position': 1,
      'field': 'hasJoinLink',
      'match': 'contains',
      'pattern': '',
      'profileId': 'quick',
    },
  ],
  'skipFilters': const SkipFilters(tentative: false).toJson(),
  'globalDefaultProfileId': 'p-focus',
  'themeMode': themeMode,
  'mergeEnabled': false,
  'sources': [
    {
      'name': 'Work Outlook',
      'color': blue,
      'kind': 'ics',
      'defaultProfileId': null,
    },
    {
      'name': 'Phone',
      'color': 0xFF5BC489,
      'kind': 'device',
      'defaultProfileId': 'p-focus',
    },
  ],
});

/// What is on the phone before an import: a profile and a rule of its own,
/// which the file replaces, a calendar, which stays, and the profile of its
/// own as the default.
Future<void> _seedLocalState() async {
  await getIt<ProfileRepository>().save(_old);
  await getIt<RuleRepository>().save(
    KeywordRule(
      id: 'r-old',
      position: 0,
      field: RuleField.title,
      pattern: 'old',
      profileId: 'p-old',
    ),
  );
  await getIt<SourceRepository>().save(_kept);
  await getIt<SettingsRepository>().setGlobalDefaultProfileId('p-old');
}

/// The real transfer, except that a test can make it fail or hold an import
/// back, and count the imports it was asked for.
class _ScriptedTransfer extends SettingsTransfer {
  _ScriptedTransfer()
    : super(
        db: getIt(),
        profiles: getIt(),
        rules: getIt(),
        settings: getIt(),
        sources: getIt(),
        appSettings: getIt(),
      );

  Object? exportError;
  Object? importError;
  Completer<void>? importGate;
  var imports = 0;

  @override
  Future<String> exportJson({required DateTime nowUtc}) async {
    final error = exportError;
    if (error != null) throw error;
    return super.exportJson(nowUtc: nowUtc);
  }

  @override
  Future<void> import(TransferFile file) async {
    imports++;
    await importGate?.future;
    final error = importError;
    if (error != null) throw error;
    await super.import(file);
  }
}

/// Puts a [_ScriptedTransfer] where the screen looks for the transfer. Call it
/// from a `pumpApp` seed.
Future<_ScriptedTransfer> _scriptedTransfer() async {
  await getIt.unregister<SettingsTransfer>();
  final transfer = _ScriptedTransfer();
  getIt.registerSingleton<SettingsTransfer>(transfer);
  return transfer;
}

/// The app settings, except that the merge switch cannot be read. The error
/// carries what a database error could say, a profile name and a pattern, in
/// its text.
class _UnreadableAppSettings extends AppSettings {
  _UnreadableAppSettings(super.settings);

  @override
  Future<bool> mergeEnabled() async =>
      throw StateError('LEAK Work Outlook "standup"');
}

/// Runs [body] with everything the app logs through `debugPrint` collected
/// into the list it is given. The hook goes back before the test body ends,
/// not in a tear-down: the framework checks that it is back before it runs the
/// tear-downs, and fails a test that left it changed.
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

/// Opens Settings on a screen tall enough for the whole page, so that nothing
/// has to be scrolled to be tapped.
Future<Harness> _pumpSettings(
  WidgetTester t, {
  Future<void> Function(Harness harness)? seed,
}) {
  t.view.physicalSize = const Size(2400, 4800);
  addTearDown(t.view.resetPhysicalSize);
  return pumpApp(t, location: '/settings', seed: seed);
}

/// Lets what a tap started finish: the frames, the database writes, and the
/// timer of a re-plan request, which fires when the clock moves.
Future<void> _settle(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.pump(const Duration(milliseconds: 1));
}

Future<String?> _stored(WidgetTester t, String key) async =>
    await t.runAsync<String?>(() => getIt<SettingsRepository>().getString(key));

/// Every row of the tables an import writes to, as the database holds them.
Future<Map<String, List<Map<String, Object?>>>> _dump(
  WidgetTester t,
  Harness h,
) async {
  final tables = <String, List<Map<String, Object?>>>{};
  await t.runAsync(() async {
    for (final table in const [
      'profiles',
      'rules',
      'sources',
      'settings',
      'overrides',
    ]) {
      final rows = await h.db
          .customSelect('SELECT * FROM $table ORDER BY 1, 2')
          .get();
      tables[table] = [for (final row in rows) row.data];
    }
  });
  return tables;
}

ListTile _tile(WidgetTester t, String title) =>
    t.widget<ListTile>(find.widgetWithText(ListTile, title));

int _calls(Harness h, String method) =>
    h.uiCalls.where((c) => c.method == method).length;

void main() {
  final mergeSwitch = find.byKey(const Key('mergeSwitch'));

  testWidgets('the theme choice is stored', (t) async {
    final h = await _pumpSettings(t);
    final selector = find.byKey(const Key('themeSelector'));
    expect(t.widget<SegmentedButton<ThemeMode>>(selector).selected, {
      ThemeMode.system,
    });

    await t.tap(find.text('Dark'));
    await _settle(t);

    expect(getIt<ThemeModeController>().mode, ThemeMode.dark);
    expect(t.widget<SegmentedButton<ThemeMode>>(selector).selected, {
      ThemeMode.dark,
    });
    expect(
      t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(await _stored(t, ThemeModeController.settingsKey), 'dark');

    await t.tap(find.text('Light'));
    await _settle(t);

    expect(
      t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(await _stored(t, ThemeModeController.settingsKey), 'light');
    await h.dispose(t);
  });

  testWidgets('choosing a default profile writes it and asks for a re-plan', (
    t,
  ) async {
    final h = await _pumpSettings(t);
    // Meeting is the default until another is chosen.
    expect(find.text('Meeting'), findsOneWidget);

    await t.tap(find.text('Default profile'));
    await _settle(t);
    for (final id in ['meeting', 'quick', 'important', 'silent']) {
      expect(find.byKey(ValueKey('profile-$id')), findsOneWidget, reason: id);
    }
    await t.tap(find.byKey(const ValueKey('profile-quick')));
    await _settle(t);

    expect(find.byKey(const ValueKey('profile-quick')), findsNothing);
    expect(
      await _stored(t, SettingsRepository.globalDefaultKey),
      BuiltInProfiles.quickId,
    );
    expect(h.replans, 1);
    // The row shows the new name.
    expect(find.text('Quick'), findsOneWidget);
    expect(find.text('Meeting'), findsNothing);
    await h.dispose(t);
  });

  testWidgets('turning merging off stores false and asks for a re-plan', (
    t,
  ) async {
    final h = await _pumpSettings(t);
    expect(t.widget<SwitchListTile>(mergeSwitch).value, isTrue);
    expect(
      find.text('Merge meetings found in more than one calendar'),
      findsOneWidget,
    );
    expect(
      find.text(
        'A meeting in both your Outlook feed and your phone calendar rings '
        'once.',
      ),
      findsOneWidget,
    );

    await t.tap(mergeSwitch);
    await _settle(t);

    expect(await _stored(t, SyncService.mergeEnabledKey), 'false');
    expect(t.widget<SwitchListTile>(mergeSwitch).value, isFalse);
    expect(h.replans, 1);

    await t.tap(mergeSwitch);
    await _settle(t);

    expect(await _stored(t, SyncService.mergeEnabledKey), 'true');
    expect(t.widget<SwitchListTile>(mergeSwitch).value, isTrue);
    expect(h.replans, 2);
    await h.dispose(t);
  });

  testWidgets('export writes a dated JSON file without links', (t) async {
    Map<Object?, Object?>? created;
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        // The link is in secure storage, which is where the source's key points.
        await getIt<SourceRepository>().save(
          const SourceConfig(
            id: 'ics-1',
            name: 'Work Outlook',
            color: blue,
            kind: SourceKind.ics,
            secureStorageKey: 'ics-url.ics-1',
          ),
        );
        harness.secrets['ics-url.ics-1'] =
            'https://calendar.example/s3cr3t/feed.ics';
        await getIt<SourceRepository>().save(
          const SourceConfig(
            id: 'device-1',
            name: 'Phone',
            color: blue,
            kind: SourceKind.device,
            deviceCalendarId: '7',
          ),
        );
        harness.ui['createDocument'] = (call) {
          created = call.arguments as Map<Object?, Object?>;
          return true;
        };
      },
    );

    // The file is named for the date on the phone. The two dates guard against
    // the test running across midnight.
    final before = LocalDate.of(DateTime.now().toUtc(), tz.local);
    await t.tap(find.text('Export settings'));
    await _settle(t);
    final after = LocalDate.of(DateTime.now().toUtc(), tz.local);

    expect(created, isNotNull);
    final sent = created!;
    expect([
      SettingsTransfer.fileName(before),
      SettingsTransfer.fileName(after),
    ], contains(sent['name']));
    final text = sent['text'] as String;
    for (final forbidden in [
      'ics-url',
      'secureStorageKey',
      'deviceCalendarId',
      'https://',
      'calendar.example',
      's3cr3t',
      'ics-1',
      'device-1',
      '"7"',
    ]) {
      expect(text, isNot(contains(forbidden)), reason: forbidden);
    }
    final doc = jsonDecode(text) as Map<String, dynamic>;
    expect(doc['format'], 'tminus-settings');
    final exported = (doc['sources'] as List).cast<Map<String, dynamic>>();
    expect(
      exported.map((s) => s['name']),
      unorderedEquals(['Work Outlook', 'Phone']),
    );
    expect(find.text('Settings exported.'), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('importing a file that is not ours says so and changes nothing', (
    t,
  ) async {
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        await _seedLocalState();
        // The text of the file must not come back on the screen.
        harness.ui['openDocument'] = (_) =>
            '{"format": "something else", "LEAK": "Work Outlook"}';
      },
    );
    final before = await _dump(t, h);

    await t.tap(find.text('Import settings'));
    await _settle(t);

    expect(find.text('This is not a T-Minus settings file.'), findsOneWidget);
    expect(find.textContaining('LEAK'), findsNothing);
    // It never gets as far as asking.
    expect(find.text('Import'), findsNothing);

    await t.tap(find.text('OK'));
    await _settle(t);

    expect(await _dump(t, h), before);
    expect(h.replans, 0);
    expect(find.byType(SnackBar), findsNothing);
    expect(_tile(t, 'Import settings').enabled, isTrue);
    await h.dispose(t);
  });

  testWidgets(
    'importing a valid file asks first, then replaces and asks for a re-plan',
    (t) async {
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          await _seedLocalState();
          harness.ui['openDocument'] = (_) => _settingsFile();
        },
      );
      final before = await _dump(t, h);
      expect(find.text('Old'), findsOneWidget); // the default profile now

      await t.tap(find.text('Import settings'));
      await _settle(t);

      // It asks first, with the file's counts, and nothing has changed yet.
      expect(
        find.text(
          "Replace your profiles, rules and settings with this file's "
          '5 profiles and 2 rules? It adds 2 calendars, which need their link '
          'or calendar before they sync. Your current calendars stay.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(await _dump(t, h), before);
      expect(h.replans, 0);

      await t.tap(find.text('Import'));
      await _settle(t);

      // Profiles: the file's, and the one of its own is gone with its rule.
      final profiles = (await t.runAsync(
        () => getIt<ProfileRepository>().all(),
      ))!;
      expect(profiles.map((p) => p.id), [
        'meeting',
        'quick',
        'important',
        'silent',
        'p-focus',
      ]);
      final rules = (await t.runAsync(() => getIt<RuleRepository>().all()))!;
      expect(rules.map((r) => r.id), ['r-1', 'r-2']);
      // Settings: the file's.
      expect(await _stored(t, SettingsRepository.globalDefaultKey), 'p-focus');
      expect(await _stored(t, SyncService.mergeEnabledKey), 'false');
      expect(await _stored(t, ThemeModeController.settingsKey), 'dark');
      // Calendars: the one that was there stays, and the file's two are added
      // once, switched off and waiting for their link or calendar.
      final sources = (await t.runAsync(
        () => getIt<SourceRepository>().all(),
      ))!;
      expect(
        sources.map((s) => s.name),
        unorderedEquals(['Keep me', 'Work Outlook', 'Phone']),
      );
      expect(sources.singleWhere((s) => s.id == 'ics-keep'), _kept);
      final added = sources.where((s) => s.id != 'ics-keep').toList();
      expect(added.every((s) => !s.enabled), isTrue);
      final setups = await t.runAsync(
        () async => {
          for (final s in added)
            s.kind: await getIt<AppSettings>().sourceSetup(s.id),
        },
      );
      expect(setups, {
        SourceKind.ics: SourceSetup.needsLink,
        SourceKind.device: SourceSetup.needsCalendar,
      });

      // What the transfer leaves to the screen: the theme, the re-plan, and a
      // screen that shows the new settings.
      expect(getIt<ThemeModeController>().mode, ThemeMode.dark);
      expect(
        t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(h.replans, 1);
      expect(
        find.text(
          'Settings imported. Finish setting up the new calendars in Sources.',
        ),
        findsOneWidget,
      );
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Old'), findsNothing);
      expect(t.widget<SwitchListTile>(mergeSwitch).value, isFalse);
      expect(_tile(t, 'Import settings').enabled, isTrue);
      await h.dispose(t);
    },
  );

  testWidgets('the version comes from the device', (t) async {
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        harness.ui['deviceInfo'] = (_) => {
          'versionName': '2.3.4',
          'versionCode': 57,
          'manufacturer': 'samsung',
          'sdkInt': 34,
        };
      },
    );

    expect(
      t.widget<Text>(find.byKey(const Key('appVersion'))).data,
      'v2.3.4 (57)',
    );
    expect(_calls(h, 'deviceInfo'), greaterThan(0));
    await h.dispose(t);
  });

  testWidgets('Developer tools opens the token preview', (t) async {
    final h = await _pumpSettings(t);

    await t.tap(find.text('Developer tools'));
    await t.pumpAndSettle();

    expect(find.byType(DeveloperToolsScreen), findsOneWidget);
    expect(find.byType(TokenPreviewScreen), findsOneWidget);
    expect(find.text('Design tokens'), findsOneWidget);
    await h.dispose(t);
  });

  group('at the end of the list, on a phone with a navigation bar', () {
    // A phone-sized screen (360 x 780 dp) with a 48 dp three-button navigation
    // bar, which the edge-to-edge app draws behind. Settings and Developer
    // tools sit outside the shell, so nothing else keeps them clear of it.
    const navBar = 48.0;
    const screenHeight = 780.0;

    void phoneWithNavBar(WidgetTester t) {
      t.view.devicePixelRatio = 3;
      t.view.physicalSize = const Size(1080, screenHeight * 3);
      t.view.padding = const FakeViewPadding(bottom: navBar * 3);
      t.view.viewPadding = const FakeViewPadding(bottom: navBar * 3);
      addTearDown(t.view.reset);
    }

    Future<void> scrollToEnd(WidgetTester t, Finder list) async {
      for (var i = 0; i < 12; i++) {
        await t.drag(list, const Offset(0, -2000));
        await t.pumpAndSettle();
      }
    }

    testWidgets('the last Settings card ends above the bar', (t) async {
      phoneWithNavBar(t);
      final h = await pumpApp(t, location: '/settings');

      await scrollToEnd(t, find.byType(SingleChildScrollView).first);

      final lastCard = find.ancestor(
        of: find.text('Developer tools'),
        matching: find.byType(Material),
      );
      expect(
        t.getRect(lastCard.first).bottom,
        lessThanOrEqualTo(screenHeight - navBar),
      );
      await h.dispose(t);
    });

    testWidgets('the last Developer tools panel ends above the bar', (t) async {
      phoneWithNavBar(t);
      final h = await pumpApp(t, location: '/settings/developer');

      await scrollToEnd(t, find.byType(ListView).first);

      expect(
        t.getRect(find.byType(SyncDebugPanel)).bottom,
        lessThanOrEqualTo(screenHeight - navBar),
      );
      await h.dispose(t);
    });
  });

  // Beyond the plan's list.

  testWidgets('the page keeps its sections and its copy', (t) async {
    final h = await _pumpSettings(t);

    for (final text in [
      'Alerts',
      'Calendars',
      'Appearance',
      'Backup',
      'About & privacy',
      'Used when no rule matches',
      'Theme',
      'System',
      'Dark',
      'Light',
      'Export settings',
      'Profiles, rules and sources (without their links)',
      'Import settings',
      "You'll paste links again after import",
      'Your calendar never leaves your phone.',
      'No account, no servers, no analytics. Feeds are fetched directly from '
          'Outlook and stored only on this device.',
      'T-Minus',
      'Licences',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    await h.dispose(t);
  });

  testWidgets('the merge switch starts from the stored setting', (t) async {
    final h = await _pumpSettings(
      t,
      seed: (_) => getIt<AppSettings>().setMergeEnabled(false),
    );

    expect(t.widget<SwitchListTile>(mergeSwitch).value, isFalse);
    await h.dispose(t);
  });

  testWidgets('a stored default profile that is gone shows Meeting', (t) async {
    final h = await _pumpSettings(
      t,
      seed: (_) =>
          getIt<SettingsRepository>().setGlobalDefaultProfileId('p-gone'),
    );

    // The rules engine falls back to Meeting, so the row and the dialog say so.
    expect(find.text('Meeting'), findsOneWidget);
    await t.tap(find.text('Default profile'));
    await _settle(t);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-meeting')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
    await h.dispose(t);
  });

  testWidgets(
    'backing out of the default profile dialog, or choosing the same profile, '
    'writes nothing',
    (t) async {
      final h = await _pumpSettings(t);

      await t.tap(find.text('Default profile'));
      await _settle(t);
      await t.tap(find.text('Cancel'));
      await _settle(t);

      await t.tap(find.text('Default profile'));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('profile-meeting')));
      await _settle(t);

      expect(find.byType(AlertDialog), findsNothing);
      expect(await _stored(t, SettingsRepository.globalDefaultKey), isNull);
      expect(h.replans, 0);
      await h.dispose(t);
    },
  );

  testWidgets('a second tap on Import while one is running is ignored', (
    t,
  ) async {
    // The first run waits at the system file dialog until the test lets it go.
    final picked = Completer<String?>();
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        harness.ui['openDocument'] = (_) => picked.future;
      },
    );

    // Two taps in one frame: the screen has not been rebuilt in between, so
    // only the controller can tell the second one apart.
    await t.tap(find.text('Import settings'));
    await t.tap(find.text('Import settings'));
    await _settle(t);

    expect(_calls(h, 'openDocument'), 1);
    // And the rows stay off until the run ends.
    expect(_tile(t, 'Import settings').enabled, isFalse);
    expect(_tile(t, 'Export settings').enabled, isFalse);

    picked.complete(null); // the user backs out
    await _settle(t);

    expect(_tile(t, 'Import settings').enabled, isTrue);
    expect(_tile(t, 'Export settings').enabled, isTrue);
    expect(_calls(h, 'openDocument'), 1);
    await h.dispose(t);
  });

  testWidgets('an import that is writing cannot be started again', (t) async {
    late _ScriptedTransfer transfer;
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        await _seedLocalState();
        transfer = await _scriptedTransfer();
        // The import waits here after it has been confirmed.
        transfer.importGate = Completer<void>();
        harness.ui['openDocument'] = (_) => _settingsFile();
      },
    );

    await t.tap(find.text('Import settings'));
    await _settle(t);
    await t.tap(find.text('Import'));
    await _settle(t);

    // The confirmed import is running, and the Backup rows are off.
    expect(transfer.imports, 1);
    expect(_tile(t, 'Import settings').enabled, isFalse);
    expect(_tile(t, 'Export settings').enabled, isFalse);
    await t.tap(find.text('Import settings'));
    await t.tap(find.text('Export settings'));
    await _settle(t);
    expect(_calls(h, 'openDocument'), 1);
    expect(_calls(h, 'createDocument'), 0);

    transfer.importGate!.complete();
    await _settle(t);

    // It ran once: the file's two calendars were added once.
    expect(transfer.imports, 1);
    final sources = (await t.runAsync(() => getIt<SourceRepository>().all()))!;
    expect(sources, hasLength(3));
    expect(h.replans, 1);
    expect(_tile(t, 'Import settings').enabled, isTrue);
    expect(_tile(t, 'Export settings').enabled, isTrue);
    await h.dispose(t);
  });

  testWidgets('a failed import shows fixed text, logs only the type and '
      'changes nothing else', (t) async {
    await _logging((logged) async {
      late _ScriptedTransfer transfer;
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          transfer = await _scriptedTransfer();
          // What a database error could say: a profile name and a pattern.
          transfer.importError = StateError('LEAK Work Outlook "standup"');
          harness.ui['openDocument'] = (_) => _settingsFile();
        },
      );

      await t.tap(find.text('Import settings'));
      await _settle(t);
      await t.tap(find.text('Import'));
      await _settle(t);

      expect(find.text('Could not import the settings.'), findsOneWidget);
      expect(find.textContaining('LEAK'), findsNothing);
      expect(logged.join('\n'), contains('StateError'));
      expect(logged.join('\n'), isNot(contains('LEAK')));
      // The theme and the re-plan wait for an import that happened.
      expect(getIt<ThemeModeController>().mode, ThemeMode.system);
      expect(h.replans, 0);
      expect(_tile(t, 'Import settings').enabled, isTrue);
      await h.dispose(t);
    });
  });

  testWidgets(
    'a file the system calls too large is refused with its own text',
    (t) async {
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          await _seedLocalState();
          harness.ui['openDocument'] = (_) =>
              throw PlatformException(code: 'too_large');
        },
      );
      final before = await _dump(t, h);

      await t.tap(find.text('Import settings'));
      await _settle(t);

      expect(
        find.text('That file is too large to be a settings file.'),
        findsOneWidget,
      );
      await t.tap(find.text('OK'));
      await _settle(t);
      expect(await _dump(t, h), before);
      expect(h.replans, 0);
      expect(_tile(t, 'Import settings').enabled, isTrue);
      await h.dispose(t);
    },
  );

  testWidgets('a file dialog that fails says so in fixed text', (t) async {
    await _logging((logged) async {
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          harness.ui['openDocument'] = (_) => throw PlatformException(
            code: 'io_error',
            message: 'LEAK /storage/emulated/0/Download/calendar.json',
          );
        },
      );

      await t.tap(find.text('Import settings'));
      await _settle(t);

      expect(find.text('Could not import the settings.'), findsOneWidget);
      expect(find.textContaining('LEAK'), findsNothing);
      expect(logged.join('\n'), contains('io_error'));
      expect(logged.join('\n'), isNot(contains('LEAK')));
      expect(_tile(t, 'Import settings').enabled, isTrue);
      await h.dispose(t);
    });
  });

  testWidgets('backing out of the file dialog changes nothing', (t) async {
    // `openDocument` answers null by default: the user cancelled.
    final h = await _pumpSettings(t, seed: (_) => _seedLocalState());
    final before = await _dump(t, h);

    await t.tap(find.text('Import settings'));
    await _settle(t);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(await _dump(t, h), before);
    expect(h.replans, 0);
    expect(_tile(t, 'Import settings').enabled, isTrue);
    await h.dispose(t);
  });

  testWidgets('backing out of the confirmation changes nothing', (t) async {
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        await _seedLocalState();
        harness.ui['openDocument'] = (_) => _settingsFile();
      },
    );
    final before = await _dump(t, h);

    await t.tap(find.text('Import settings'));
    await _settle(t);
    await t.tap(find.text('Cancel'));
    await _settle(t);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(await _dump(t, h), before);
    expect(h.replans, 0);
    expect(getIt<ThemeModeController>().mode, ThemeMode.system);
    expect(_tile(t, 'Import settings').enabled, isTrue);
    await h.dispose(t);
  });

  testWidgets('a file that says nothing about the theme leaves it alone', (
    t,
  ) async {
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        harness.ui['openDocument'] = (_) => _settingsFile(themeMode: null);
      },
    );
    await t.tap(find.text('Light'));
    await _settle(t);

    await t.tap(find.text('Import settings'));
    await _settle(t);
    await t.tap(find.text('Import'));
    await _settle(t);

    expect(
      find.text(
        'Settings imported. Finish setting up the new calendars in Sources.',
      ),
      findsOneWidget,
    );
    expect(getIt<ThemeModeController>().mode, ThemeMode.light);
    expect(await _stored(t, ThemeModeController.settingsKey), 'light');
    await h.dispose(t);
  });

  testWidgets('cancelling the save dialog says nothing', (t) async {
    final h = await _pumpSettings(
      t,
      seed: (harness) async {
        harness.ui['createDocument'] = (_) => false;
      },
    );

    await t.tap(find.text('Export settings'));
    await _settle(t);

    expect(_calls(h, 'createDocument'), 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(_tile(t, 'Export settings').enabled, isTrue);
    await h.dispose(t);
  });

  testWidgets('a save dialog that fails says so in fixed text', (t) async {
    await _logging((logged) async {
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          harness.ui['createDocument'] = (_) => throw PlatformException(
            code: 'io_error',
            message: 'LEAK /storage/emulated/0/Download/tminus-settings.json',
          );
        },
      );

      await t.tap(find.text('Export settings'));
      await _settle(t);

      expect(find.text('Could not export the settings.'), findsOneWidget);
      expect(find.text('Settings exported.'), findsNothing);
      expect(find.textContaining('LEAK'), findsNothing);
      expect(logged.join('\n'), contains('io_error'));
      expect(logged.join('\n'), isNot(contains('LEAK')));
      expect(_tile(t, 'Export settings').enabled, isTrue);
      await h.dispose(t);
    });
  });

  testWidgets('an export that cannot read the settings says so in fixed text', (
    t,
  ) async {
    await _logging((logged) async {
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          final transfer = await _scriptedTransfer();
          transfer.exportError = StateError('LEAK Work Outlook "standup"');
        },
      );

      await t.tap(find.text('Export settings'));
      await _settle(t);

      expect(find.text('Could not export the settings.'), findsOneWidget);
      expect(find.textContaining('LEAK'), findsNothing);
      expect(logged.join('\n'), contains('StateError'));
      expect(logged.join('\n'), isNot(contains('LEAK')));
      expect(_calls(h, 'createDocument'), 0);
      await h.dispose(t);
    });
  });

  testWidgets('the exported file is named for the date on the phone', (
    t,
  ) async {
    final h = await pumpApp(t);
    String? name;
    h.ui['createDocument'] = (call) {
      name = (call.arguments as Map)['name'] as String;
      return true;
    };
    final controller = SettingsController(
      profiles: getIt(),
      settings: getIt(),
      appSettings: getIt(),
      transfer: getIt(),
      ui: getIt(),
      theme: getIt(),
      replan: getIt(),
      // 22:30 UTC on the 6th is half past midnight on the 7th in Johannesburg.
      clock: () => DateTime.utc(2026, 10, 6, 22, 30),
    );

    expect(await controller.exportSettings(), isTrue);

    expect(name, 'tminus-settings-2026-10-07.json');
    controller.dispose();
    await h.dispose(t);
  });

  testWidgets('a device that cannot say its version leaves the line out', (
    t,
  ) async {
    await _logging((logged) async {
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          harness.ui['deviceInfo'] = (_) =>
              throw PlatformException(code: 'unavailable', message: 'LEAK');
        },
      );

      // The rest of the page is there.
      expect(find.text('T-Minus'), findsOneWidget);
      expect(find.text('Default profile'), findsOneWidget);
      expect(find.byKey(const Key('appVersion')), findsNothing);
      expect(logged.join('\n'), contains('unavailable'));
      expect(logged.join('\n'), isNot(contains('LEAK')));
      await h.dispose(t);
    });
  });

  // The loading of the page logs through its own helper, not through `guarded`
  // (which logs the actions): a platform error by its code, any other error by
  // its type. The test above reaches the code; this one reaches the type.
  testWidgets('a settings read that fails is logged by its type, not its '
      'text', (t) async {
    await _logging((logged) async {
      final h = await _pumpSettings(
        t,
        seed: (harness) async {
          await getIt.unregister<AppSettings>();
          getIt.registerSingleton<AppSettings>(
            _UnreadableAppSettings(getIt<SettingsRepository>()),
          );
        },
      );

      final log = logged.join('\n');
      expect(log, isNot(contains('LEAK')));
      expect(log, contains('Loading the settings failed: StateError'));
      // Nothing of the error reaches the screen, and what could still be read
      // is there: the page and the version.
      expect(find.textContaining('LEAK'), findsNothing);
      expect(find.text('Default profile'), findsOneWidget);
      expect(find.byKey(const Key('appVersion')), findsOneWidget);
      await h.dispose(t);
    });
  });

  test('the confirmation counts what the file holds, in the right grammar', () {
    const head = "Replace your profiles, rules and settings with this file's ";
    expect(
      importConfirmText(
        const TransferSummary(
          profiles: 5,
          rules: 2,
          icsSources: 1,
          phoneSources: 1,
        ),
      ),
      '${head}5 profiles and 2 rules? It adds 2 calendars, which need their '
      'link or calendar before they sync. Your current calendars stay.',
    );
    expect(
      importConfirmText(
        const TransferSummary(
          profiles: 1,
          rules: 1,
          icsSources: 0,
          phoneSources: 1,
        ),
      ),
      '${head}1 profile and 1 rule? It adds 1 calendar, which needs its link '
      'or calendar before it syncs. Your current calendars stay.',
    );
    // A file with no calendars does not talk about them.
    expect(
      importConfirmText(
        const TransferSummary(
          profiles: 4,
          rules: 0,
          icsSources: 0,
          phoneSources: 0,
        ),
      ),
      '${head}4 profiles and 0 rules? Your current calendars stay.',
    );
  });

  test(
    'the message after an import points at Sources only for new calendars',
    () {
      TransferSummary withCalendars(int ics, int phone) => TransferSummary(
        profiles: 4,
        rules: 0,
        icsSources: ics,
        phoneSources: phone,
      );

      expect(
        importedText(withCalendars(1, 1)),
        'Settings imported. Finish setting up the new calendars in Sources.',
      );
      expect(
        importedText(withCalendars(0, 1)),
        'Settings imported. Finish setting up the new calendar in Sources.',
      );
      expect(importedText(withCalendars(0, 0)), 'Settings imported.');
    },
  );
}
