import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/features/alerts/profile_editor_screen.dart';
import 'package:tminus/features/common/alert_list_editor.dart';

import '../harness.dart';
import 'alerts_test_support.dart';

void main() {
  testWidgets("a built-in's name cannot be edited", (t) async {
    useTallWindow(t);
    final h = await pumpApp(t, location: '/alerts/profiles/quick');

    final field = t.widget<TextField>(find.byKey(const Key('profileName')));
    expect(field.controller!.text, 'Quick');
    expect(field.readOnly, isTrue);
    expect(find.text("Built-in profile names can't change"), findsOneWidget);

    // Whatever the field comes to hold, the built-in keeps its name.
    field.controller!.text = 'Renamed';
    await t.pump();
    await t.tap(find.byKey(const Key('saveProfile')));
    await t.pumpAndSettle();
    final saved = (await getIt<ProfileRepository>().byId('quick'))!;
    expect(saved.name, 'Quick');
    expect(saved.builtIn, isTrue);

    // The name of a profile the user makes can be typed.
    await h.go(t, '/alerts/profiles/new');
    expect(
      t.widget<TextField>(find.byKey(const Key('profileName'))).readOnly,
      isFalse,
    );
    expect(find.text("Built-in profile names can't change"), findsNothing);
    await h.dispose(t);
  });

  testWidgets('a new profile saves with its alerts and asks for a re-plan', (
    t,
  ) async {
    useTallWindow(t);
    final h = await pumpApp(t, location: '/alerts');
    await t.tap(find.byKey(const Key('newProfile')));
    await t.pumpAndSettle();

    expect(
      t.widget<ProfileEditorScreen>(find.byType(ProfileEditorScreen)).profileId,
      isNull,
    );
    // It starts with a heads-up at 10 and an alarm at 1, and has no name yet,
    // so there is nothing to save.
    expect(
      t.widget<AlertListEditor>(find.byType(AlertListEditor)).alerts,
      const [
        AlertSpec(10, AlertStrength.headsUp),
        AlertSpec(1, AlertStrength.alarm),
      ],
    );
    FilledButton save() =>
        t.widget<FilledButton>(find.byKey(const Key('saveProfile')));
    expect(save().onPressed, isNull);

    await t.enterText(find.byKey(const Key('profileName')), '  Focus block ');
    await t.pump();
    expect(save().onPressed, isNotNull);

    // The first alert moves to 15 minutes, and one more is added at the end.
    await t.tap(find.byKey(const ValueKey('alert-0-offset-15')));
    await t.pump();
    await t.tap(find.byKey(const Key('addAlert')));
    await t.pump();

    await t.tap(find.byKey(const Key('saveProfile')));
    await t.pumpAndSettle();

    // A new profile goes to the end of the list.
    final saved = (await getIt<ProfileRepository>().all()).last;
    expect(saved.id, matches(RegExp(r'^p-[0-9a-f]{12}$')));
    expect(saved.name, 'Focus block');
    expect(saved.builtIn, isFalse);
    expect(saved.alerts, const [
      AlertSpec(15, AlertStrength.headsUp),
      AlertSpec(1, AlertStrength.alarm),
      AlertSpec(5, AlertStrength.headsUp),
    ]);
    expect(saved.sound, const SoundSettings());
    expect(saved.ringsInQuietMode, isFalse);
    expect(h.replans, 1);
    // Back on the list, where the new profile is.
    expect(find.byType(ProfileEditorScreen), findsNothing);
    expect(find.byKey(Key('profileRow-${saved.id}')), findsOneWidget);
    await h.dispose(t);
  });

  testWidgets('picking a tone stores its uri; cancelling changes nothing', (
    t,
  ) async {
    useTallWindow(t);
    const chime = 'content://media/internal/audio/media/42';
    Object? answer = {'picked': true, 'uri': chime, 'title': 'Chime'};
    final h = await pumpApp(
      t,
      location: '/alerts/profiles/meeting',
      seed: (h) async {
        h.ui['pickAlarmTone'] = (_) => answer;
        h.ui['toneTitle'] = (c) => (c.arguments as Map)['uri'] == null
            ? 'Default alarm tone'
            : 'Chime';
      },
    );
    Finder tone() => find.byKey(const Key('profileTone'));
    Finder subtitle(String text) =>
        find.descendant(of: tone(), matching: find.text(text));
    Object? lastPickArguments() =>
        h.uiCalls.lastWhere((c) => c.method == 'pickAlarmTone').arguments;
    Future<String?> storedTone() async =>
        (await getIt<ProfileRepository>().byId('meeting'))!.sound.toneUri;
    Future<void> saveAndReopen() async {
      await t.tap(find.byKey(const Key('saveProfile')));
      await t.pumpAndSettle();
      await h.go(t, '/alerts/profiles/meeting');
    }

    // The default tone to begin with.
    expect(subtitle('Default alarm tone'), findsOneWidget);

    // A picked tone is shown and stored, and the other sound settings stay.
    await t.tap(tone());
    await t.pumpAndSettle();
    expect(lastPickArguments(), {'current': null});
    expect(subtitle('Chime'), findsOneWidget);
    await saveAndReopen();
    expect(await storedTone(), chime);
    expect(
      (await getIt<ProfileRepository>().byId('meeting'))!.sound,
      const SoundSettings(toneUri: chime),
    );
    expect(subtitle('Chime'), findsOneWidget);

    // Backing out of the picker changes nothing, and it was told the current
    // tone.
    answer = {'picked': false};
    await t.tap(tone());
    await t.pumpAndSettle();
    expect(lastPickArguments(), {'current': chime});
    expect(subtitle('Chime'), findsOneWidget);
    await saveAndReopen();
    expect(await storedTone(), chime);

    // Choosing the default tone stores no uri.
    answer = {'picked': true, 'uri': null, 'title': 'Default alarm tone'};
    await t.tap(tone());
    await t.pumpAndSettle();
    expect(subtitle('Default alarm tone'), findsOneWidget);
    await saveAndReopen();
    expect(await storedTone(), isNull);
    await h.dispose(t);
  });

  testWidgets('deleting a user profile asks first and then removes it', (
    t,
  ) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts/profiles/$focusBlockId',
      seed: (h) async {
        await getIt<ProfileRepository>().save(userProfile());
        // What uses the profile goes with it.
        await getIt<RuleRepository>().save(
          keywordRule('r-000000000001', 0, profileId: focusBlockId),
        );
        await getIt<SettingsRepository>().setGlobalDefaultProfileId(
          focusBlockId,
        );
      },
    );

    await t.tap(find.byKey(const Key('deleteProfile')));
    await t.pumpAndSettle();
    expect(find.text('Delete Focus block?'), findsOneWidget);
    expect(
      find.text(
        'Rules that use it are deleted, and calendars and events that use it '
        'go back to the default.',
      ),
      findsOneWidget,
    );

    // Cancel: the profile stays, and nothing is re-planned.
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await getIt<ProfileRepository>().byId(focusBlockId), isNotNull);
    expect(h.replans, 0);
    expect(find.byType(ProfileEditorScreen), findsOneWidget);

    // Delete: the profile, the rule that used it and the default go.
    await t.tap(find.byKey(const Key('deleteProfile')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmDeleteProfile')));
    await t.pumpAndSettle();
    expect(await getIt<ProfileRepository>().byId(focusBlockId), isNull);
    expect(await getIt<RuleRepository>().all(), isEmpty);
    expect(
      await getIt<SettingsRepository>().globalDefaultProfileId(),
      'meeting',
    );
    expect(h.replans, 1);
    expect(find.byType(ProfileEditorScreen), findsNothing);
    await h.dispose(t);
  });

  testWidgets('Silent has no alert editor and no quiet-mode switch', (t) async {
    useTallWindow(t);
    // A settings file can leave Silent stored with the quiet-mode flag on (an
    // import saves each profile as the file has it, and only Silent's alerts
    // are forced empty). The form holds that flag but has no switch to show or
    // clear it.
    final h = await pumpApp(
      t,
      location: '/alerts/profiles/silent',
      seed: (h) => getIt<ProfileRepository>().save(
        BuiltInProfiles.silent.copyWith(ringsInQuietMode: true),
      ),
    );
    expect(
      (await getIt<ProfileRepository>().byId('silent'))!.ringsInQuietMode,
      isTrue,
    );
    expect(find.byType(AlertListEditor), findsNothing);
    expect(find.text('Silent never rings.'), findsOneWidget);
    expect(find.byKey(const Key('ringsInQuietMode')), findsNothing);

    // Another built-in profile has both. This also starts the form again when
    // the router shows a different profile on the same page.
    await h.go(t, '/alerts/profiles/meeting');
    expect(find.byType(AlertListEditor), findsOneWidget);
    expect(find.text('Silent never rings.'), findsNothing);
    expect(find.byKey(const Key('ringsInQuietMode')), findsOneWidget);
    // A built-in profile cannot be deleted.
    expect(find.byKey(const Key('deleteProfile')), findsNothing);

    // Saving Silent writes no quiet-mode flag, whatever it was stored with:
    // Silent never rings, so there is nothing for the flag to let through.
    await h.go(t, '/alerts/profiles/silent');
    await t.tap(find.byKey(const Key('saveProfile')));
    await t.pumpAndSettle();
    final saved = (await getIt<ProfileRepository>().byId('silent'))!;
    expect(saved.ringsInQuietMode, isFalse);
    expect(saved.alerts, isEmpty);
    expect(saved.name, 'Silent');
    expect(saved.builtIn, isTrue);
    await h.dispose(t);
  });

  // Beyond the plan's list: each pins one thing the editor promises.

  testWidgets(
    'a stored ring timeout the dropdown does not offer is kept, and one '
    'outside 1 to 3600 seconds is brought inside',
    (t) async {
      useTallWindow(t);
      // Id, name, stored, shown, saved.
      const cases = [
        (
          'p-000000000090',
          'Ninety',
          Duration(seconds: 90),
          '90 s',
          Duration(seconds: 90),
        ),
        (
          'p-000000003600',
          'Hour',
          Duration(hours: 1),
          '60 min',
          Duration(hours: 1),
        ),
        (
          'p-000000000001',
          'One second',
          Duration(seconds: 1),
          '1 s',
          Duration(seconds: 1),
        ),
        (
          'p-000000007200',
          'Two hours',
          Duration(hours: 2),
          '60 min',
          Duration(hours: 1),
        ),
        ('p-000000000000', 'Zero', Duration.zero, '1 s', Duration(seconds: 1)),
      ];
      final h = await pumpApp(
        t,
        location: '/alerts',
        seed: (h) async {
          for (final (id, name, stored, _, _) in cases) {
            await getIt<ProfileRepository>().save(
              userProfile(
                id: id,
                name: name,
                sound: SoundSettings(ringTimeout: stored),
              ),
            );
          }
        },
      );

      for (final (id, _, _, shown, saved) in cases) {
        await h.go(t, '/alerts/profiles/$id');
        expect(
          find.descendant(
            of: find.byKey(const Key('ringTimeout')),
            matching: find.text(shown),
          ),
          findsOneWidget,
          reason: id,
        );
        await t.tap(find.byKey(const Key('saveProfile')));
        await t.pumpAndSettle();
        expect(
          (await getIt<ProfileRepository>().byId(id))!.sound.ringTimeout,
          saved,
          reason: id,
        );
      }
      await h.dispose(t);
    },
  );

  testWidgets('a name another profile has is refused, ignoring case', (
    t,
  ) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts/profiles/new',
      seed: (h) => getIt<ProfileRepository>().save(userProfile()),
    );
    FilledButton save() =>
        t.widget<FilledButton>(find.byKey(const Key('saveProfile')));
    Future<void> type(String name) async {
      await t.enterText(find.byKey(const Key('profileName')), name);
      await t.pump();
    }

    const taken = 'Another profile has this name.';
    for (final name in ['quick', '  Quick  ', 'FOCUS BLOCK']) {
      await type(name);
      expect(find.text(taken), findsOneWidget, reason: name);
      expect(save().onPressed, isNull, reason: name);
    }
    await type('Quicker');
    expect(find.text(taken), findsNothing);
    expect(save().onPressed, isNotNull);
    await type('');
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(save().onPressed, isNull);

    // A profile may take another case of its own name.
    await h.go(t, '/alerts/profiles/$focusBlockId');
    await type('FOCUS BLOCK');
    expect(find.text(taken), findsNothing);
    expect(save().onPressed, isNotNull);
    await h.dispose(t);
  });

  testWidgets('the sound settings and the quiet-mode switch are saved', (
    t,
  ) async {
    useTallWindow(t);
    final h = await pumpApp(
      t,
      location: '/alerts/profiles/$focusBlockId',
      seed: (h) => getIt<ProfileRepository>().save(userProfile()),
    );
    bool on(String key) => t.widget<SwitchListTile>(find.byKey(Key(key))).value;
    expect(on('profileVibrate'), isTrue);
    expect(on('profileGradual'), isTrue);
    expect(on('ringsInQuietMode'), isFalse);

    await t.tap(find.byKey(const Key('profileVibrate')));
    await t.pump();
    await t.tap(find.byKey(const Key('ringsInQuietMode')));
    await t.pump();
    await t.tap(find.byKey(const Key('ringTimeout')));
    await t.pumpAndSettle();
    await t.tap(find.text('5 min').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('saveProfile')));
    await t.pumpAndSettle();

    var saved = (await getIt<ProfileRepository>().byId(focusBlockId))!;
    expect(
      saved.sound,
      const SoundSettings(vibrate: false, ringTimeout: Duration(minutes: 5)),
    );
    expect(saved.ringsInQuietMode, isTrue);

    // The other switch, on the profile as it is now.
    await h.go(t, '/alerts/profiles/$focusBlockId');
    expect(on('profileVibrate'), isFalse);
    expect(on('ringsInQuietMode'), isTrue);
    await t.tap(find.byKey(const Key('profileGradual')));
    await t.pump();
    await t.tap(find.byKey(const Key('saveProfile')));
    await t.pumpAndSettle();

    saved = (await getIt<ProfileRepository>().byId(focusBlockId))!;
    expect(
      saved.sound,
      const SoundSettings(
        vibrate: false,
        gradualVolume: false,
        ringTimeout: Duration(minutes: 5),
      ),
    );
    expect(saved.ringsInQuietMode, isTrue);
    expect(h.replans, 2);
    await h.dispose(t);
  });

  testWidgets('a profile that is gone says so', (t) async {
    final h = await pumpApp(t, location: '/alerts/profiles/quick');
    expect(find.byKey(const Key('profileName')), findsOneWidget);

    await h.go(t, '/alerts/profiles/nope');

    expect(find.text('This profile was removed.'), findsOneWidget);
    expect(find.byKey(const Key('profileName')), findsNothing);
    expect(find.byKey(const Key('saveProfile')), findsNothing);
    await h.dispose(t);
  });
}
