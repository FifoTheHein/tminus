import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late ProfileRepository profiles;
  late RuleRepository rules;
  late OverrideRepository overrides;
  late SettingsRepository settings;

  const focus = AlertProfile(
    id: 'focus',
    name: 'Focus',
    alerts: [AlertSpec(3, AlertStrength.alarm)],
    sound: SoundSettings(toneUri: 'content://tone/2', gradualVolume: false),
    ringsInQuietMode: true,
  );

  setUp(() {
    db = openTestDatabase();
    profiles = ProfileRepository(db);
    rules = RuleRepository(db);
    overrides = OverrideRepository(db);
    settings = SettingsRepository(db);
  });
  tearDown(() => db.close());

  group('ProfileRepository', () {
    test(
      'lists built-ins first, then saved profiles in creation order',
      () async {
        await profiles.save(focus);
        await profiles.save(focus.copyWith().copyWithId('later'));
        final all = await profiles.all();
        expect(all.map((p) => p.id), [
          'meeting',
          'quick',
          'important',
          'silent',
          'focus',
          'later',
        ]);
        expect(all[4], focus);
      },
    );

    test('save cannot make a user profile built-in', () async {
      await profiles.save(
        const AlertProfile(id: 'sneaky', name: 'S', alerts: [], builtIn: true),
      );
      expect((await profiles.byId('sneaky'))!.builtIn, isFalse);
    });

    test('editing a built-in keeps it built-in and in place', () async {
      await profiles.save(
        BuiltInProfiles.meeting.copyWith(
          alerts: const [AlertSpec(5, AlertStrength.alarm)],
        ),
      );
      final all = await profiles.all();
      expect(all.first.id, 'meeting');
      expect(all.first.builtIn, isTrue);
      expect(all.first.alerts, const [AlertSpec(5, AlertStrength.alarm)]);
    });

    test('built-ins cannot be deleted', () async {
      expect(() => profiles.delete('meeting'), throwsStateError);
    });

    test('deleting a profile removes every reference to it', () async {
      await profiles.save(focus);
      final sources = SourceRepository(db);
      await sources.save(
        const SourceConfig(
          id: 'work',
          name: 'Work',
          color: 1,
          kind: SourceKind.ics,
          defaultProfileId: 'focus',
        ),
      );
      await rules.save(
        KeywordRule(
          id: 'r1',
          position: 0,
          field: RuleField.title,
          pattern: 'x',
          profileId: 'focus',
        ),
      );
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k1',
          profileId: 'focus',
        ),
      );
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k2',
          profileId: 'focus',
          enabled: true,
        ),
      );
      await settings.setGlobalDefaultProfileId('focus');

      await profiles.delete('focus');

      expect(await profiles.byId('focus'), isNull);
      expect((await sources.byId('work'))!.defaultProfileId, isNull);
      expect(await rules.all(), isEmpty);
      expect(await overrides.find(OverrideScope.occurrence, 'k1'), isNull);
      expect(
        await overrides.find(OverrideScope.occurrence, 'k2'),
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k2',
          enabled: true,
        ),
      );
      expect(await settings.globalDefaultProfileId(), 'meeting');
    });

    test('watchAll emits the current list, then again after a save', () async {
      final seen = <int>[];
      final sub = profiles.watchAll().listen((l) => seen.add(l.length));
      await waitUntil(() => seen.isNotEmpty);
      await profiles.save(focus);
      await waitUntil(() => seen.length == 2);
      await sub.cancel();
      expect(seen, [4, 5]);
    });
  });

  group('unreadable profile and override rows (decision 15)', () {
    Future<void> setAlertsJson(String id, String json) => db.customStatement(
      'UPDATE profiles SET alerts_json = ? WHERE id = ?',
      [json, id],
    );

    const unreadableAlerts = [
      '[{"offsetMinutes":5,"strength":"loud"}]',
      'not json',
      '[{"offsetMinutes":-5,"strength":"alarm"}]',
      '{"offsetMinutes":5}',
      '[{"offsetMinutes":"5","strength":"alarm"}]',
    ];

    test('a user profile that cannot be read is left out', () async {
      await profiles.save(focus);
      for (final json in unreadableAlerts) {
        await setAlertsJson('focus', json);
        expect((await profiles.all()).map((p) => p.id), [
          'meeting',
          'quick',
          'important',
          'silent',
        ], reason: json);
        expect(await profiles.byId('focus'), isNull, reason: json);
      }
    });

    test('a user profile with unreadable sound JSON is left out', () async {
      await profiles.save(focus);
      await db.customStatement(
        "UPDATE profiles SET sound_json = '{\"vibrate\":\"yes\"}' "
        "WHERE id = 'focus'",
      );
      expect(await profiles.byId('focus'), isNull);
    });

    test('a built-in that cannot be read gives its definition', () async {
      await profiles.save(
        BuiltInProfiles.meeting.copyWith(
          alerts: const [AlertSpec(5, AlertStrength.alarm)],
        ),
      );
      for (final json in unreadableAlerts) {
        await setAlertsJson('meeting', json);
        expect(await profiles.byId('meeting'), BuiltInProfiles.meeting);
        expect((await profiles.all()).first, BuiltInProfiles.meeting);
      }
    });

    test('watchAll skips a profile that cannot be read', () async {
      await profiles.save(focus);
      await setAlertsJson('focus', 'not json');
      expect((await profiles.watchAll().first).map((p) => p.id), [
        'meeting',
        'quick',
        'important',
        'silent',
      ]);
    });

    test(
      'an override whose custom alerts cannot be read is left out',
      () async {
        const good = EventOverride(
          scope: OverrideScope.occurrence,
          target: 'good',
          customAlerts: [AlertSpec(2, AlertStrength.alarm)],
        );
        await overrides.save(good);
        for (final json in [
          'oops',
          '[{"offsetMinutes":-5,"strength":"alarm"}]',
          '[{"offsetMinutes":5,"strength":"loud"}]',
        ]) {
          await db.customStatement(
            'INSERT OR REPLACE INTO overrides '
            '(scope, target, custom_alerts_json) VALUES (?, ?, ?)',
            ['occurrence', 'bad', json],
          );
          expect(await overrides.all(), [good], reason: json);
          expect(await overrides.watchAll().first, [good], reason: json);
          expect(
            await overrides.find(OverrideScope.occurrence, 'bad'),
            isNull,
            reason: json,
          );
        }
      },
    );
  });

  group('RuleRepository', () {
    KeywordRule rule(String id, int position) => KeywordRule(
      id: id,
      position: position,
      field: RuleField.title,
      match: RuleMatch.regex,
      pattern: '^$id',
      profileId: 'quick',
    );

    test('round trip and position order', () async {
      await rules.save(rule('b', 1));
      await rules.save(rule('a', 0));
      expect(await rules.all(), [rule('a', 0), rule('b', 1)]);
    });

    test('reorder and delete', () async {
      await rules.save(rule('a', 0));
      await rules.save(rule('b', 1));
      await rules.save(rule('c', 2));
      await rules.reorder(['c', 'a', 'b']);
      expect((await rules.all()).map((r) => r.id), ['c', 'a', 'b']);
      await rules.delete('a');
      expect((await rules.all()).map((r) => r.id), ['c', 'b']);
    });
  });

  group('OverrideRepository', () {
    test('round trip with custom alerts', () async {
      const o = EventOverride(
        scope: OverrideScope.series,
        target: 'series-1',
        profileId: 'important',
        customAlerts: [AlertSpec(20, AlertStrength.headsUp)],
        enabled: true,
      );
      await overrides.save(o);
      expect(await overrides.find(OverrideScope.series, 'series-1'), o);
      expect(
        await overrides.find(OverrideScope.occurrence, 'series-1'),
        isNull,
      );
    });

    test('saving an empty override deletes the row', () async {
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k',
          enabled: false,
        ),
      );
      await overrides.save(
        const EventOverride(scope: OverrideScope.occurrence, target: 'k'),
      );
      expect(await overrides.all(), isEmpty);
    });

    test('setOccurrenceEnabled keeps the profile and custom alerts', () async {
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k',
          profileId: 'quick',
          customAlerts: [AlertSpec(2, AlertStrength.alarm)],
        ),
      );
      await overrides.setOccurrenceEnabled('k', false);
      expect(
        await overrides.find(OverrideScope.occurrence, 'k'),
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k',
          profileId: 'quick',
          customAlerts: [AlertSpec(2, AlertStrength.alarm)],
          enabled: false,
        ),
      );
      await overrides.setOccurrenceEnabled('fresh', true);
      expect(
        (await overrides.find(OverrideScope.occurrence, 'fresh'))!.enabled,
        isTrue,
      );
    });
  });

  group('SettingsRepository', () {
    test('skip filters default to all on and round trip', () async {
      expect(await settings.skipFilters(), const SkipFilters());
      await settings.setSkipFilters(const SkipFilters(tentative: false));
      expect(await settings.skipFilters(), const SkipFilters(tentative: false));
    });

    test('global default is Meeting until set', () async {
      expect(await settings.globalDefaultProfileId(), 'meeting');
      await settings.setGlobalDefaultProfileId('quick');
      expect(await settings.globalDefaultProfileId(), 'quick');
    });

    test('every quiet state round trips; none by default', () async {
      expect(await settings.quietState(), const QuietNone());
      final states = <QuietState>[
        MuteToday(DateTime.utc(2026, 10, 7, 5)),
        PausedUntil(DateTime.utc(2026, 10, 6, 12, 30)),
        Vacation(LocalDate(2026, 12, 20), LocalDate(2027, 1, 3)),
        const QuietNone(),
      ];
      for (final s in states) {
        await settings.setQuietState(s);
        expect(await settings.quietState(), s);
      }
    });

    test('an unreadable quiet row reads as none', () async {
      await db
          .into(db.quietStates)
          .insert(
            QuietStatesCompanion.insert(
              id: const Value(1),
              kind: QuietKind.vacation,
            ),
          );
      expect(await settings.quietState(), const QuietNone());
    });

    test('skip-filter text that is not JSON reads as all on', () async {
      await settings.setString(SettingsRepository.skipFiltersKey, 'garbage');
      expect(await settings.skipFilters(), const SkipFilters());
    });

    test('skip-filter JSON of the wrong shape reads as all on', () async {
      for (final json in [
        '{"allDay":"yes"}',
        '{"tentative":false,"free":1}',
        '[]',
        'null',
        '"on"',
      ]) {
        await settings.setString(SettingsRepository.skipFiltersKey, json);
        expect(await settings.skipFilters(), const SkipFilters(), reason: json);
      }
    });

    test('skip-filter JSON with missing keys keeps the others', () async {
      await settings.setString(
        SettingsRepository.skipFiltersKey,
        '{"tentative":false}',
      );
      expect(await settings.skipFilters(), const SkipFilters(tentative: false));
    });

    test('watchSkipFilters reads unreadable JSON as all on', () async {
      await settings.setString(SettingsRepository.skipFiltersKey, 'garbage');
      expect(await settings.watchSkipFilters().first, const SkipFilters());
    });

    test('an unknown quiet kind reads as none', () async {
      await db.customStatement(
        "INSERT INTO quiet_state (id, kind) VALUES (1, 'snooze')",
      );
      expect(await settings.quietState(), const QuietNone());
      expect(await settings.watchQuietState().first, const QuietNone());
    });

    test('watchQuietState emits the current state, then changes', () async {
      final mute = MuteToday(DateTime.utc(2026, 10, 7, 5));
      final seen = <QuietState>[];
      final sub = settings.watchQuietState().listen(seen.add);
      await waitUntil(() => seen.isNotEmpty);
      await settings.setQuietState(mute);
      await waitUntil(() => seen.length == 2);
      await sub.cancel();
      expect(seen, [const QuietNone(), mute]);
    });
  });
}

extension on AlertProfile {
  AlertProfile copyWithId(String id) => AlertProfile(
    id: id,
    name: name,
    alerts: alerts,
    sound: sound,
    ringsInQuietMode: ringsInQuietMode,
  );
}
