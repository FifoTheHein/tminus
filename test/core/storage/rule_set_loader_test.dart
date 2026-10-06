import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late RuleSetLoader loader;

  setUp(() {
    db = openTestDatabase();
    loader = RuleSetLoader(
      profiles: ProfileRepository(db),
      rules: RuleRepository(db),
      overrides: OverrideRepository(db),
      settings: SettingsRepository(db),
      sources: SourceRepository(db),
    );
  });
  tearDown(() => db.close());

  group('unreadable rows are skipped (decision 15)', () {
    test('a user profile that cannot be read is not in the RuleSet', () async {
      await ProfileRepository(db).save(
        const AlertProfile(
          id: 'focus',
          name: 'Focus',
          alerts: [AlertSpec(3, AlertStrength.alarm)],
        ),
      );
      await RuleRepository(db).save(
        KeywordRule(
          id: 'r1',
          position: 0,
          field: RuleField.title,
          pattern: 'x',
          profileId: 'focus',
        ),
      );
      for (final json in [
        '[{"offsetMinutes":5,"strength":"loud"}]',
        'not json',
        '[{"offsetMinutes":-5,"strength":"alarm"}]',
      ]) {
        await db.customStatement(
          "UPDATE profiles SET alerts_json = ? WHERE id = 'focus'",
          [json],
        );
        final rules = await loader.load();
        expect(rules.profile('focus'), isNull, reason: json);
        expect(rules.rules, hasLength(1), reason: json);
      }
    });

    test('a built-in that cannot be read loads its definition', () async {
      await db.customStatement(
        "UPDATE profiles SET alerts_json = 'not json' WHERE id = 'important'",
      );
      final rules = await loader.load();
      expect(rules.profile('important'), BuiltInProfiles.important);
    });

    test('an override that cannot be read is not in the RuleSet', () async {
      await OverrideRepository(db).save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'good',
          enabled: false,
        ),
      );
      await db.customStatement(
        'INSERT INTO overrides (scope, target, custom_alerts_json) '
        "VALUES ('occurrence', 'bad', 'oops')",
      );
      final rules = await loader.load();
      expect(rules.occurrenceOverride('bad'), isNull);
      expect(rules.occurrenceOverride('good')!.enabled, isFalse);
    });
  });
}
