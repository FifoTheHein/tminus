import '../rules/rule_set.dart';
import 'override_repository.dart';
import 'profile_repository.dart';
import 'rule_repository.dart';
import 'settings_repository.dart';
import 'source_repository.dart';

/// Reads everything the rules engine needs in one call. Plan 4's
/// `syncMain()` and Plan 5's Agenda both use this.
class RuleSetLoader {
  RuleSetLoader({
    required this.profiles,
    required this.rules,
    required this.overrides,
    required this.settings,
    required this.sources,
  });

  final ProfileRepository profiles;
  final RuleRepository rules;
  final OverrideRepository overrides;
  final SettingsRepository settings;
  final SourceRepository sources;

  Future<RuleSet> load() async {
    final (p, r, o, skip, globalDefault, quiet, s) = await (
      profiles.all(),
      rules.all(),
      overrides.all(),
      settings.skipFilters(),
      settings.globalDefaultProfileId(),
      settings.quietState(),
      sources.all(),
    ).wait;
    return RuleSet(
      profiles: p,
      rules: r,
      overrides: o,
      skipFilters: skip,
      globalDefaultProfileId: globalDefault,
      quiet: quiet,
      sourceDefaults: {
        for (final src in s)
          if (src.defaultProfileId != null) src.id: src.defaultProfileId!,
      },
    );
  }
}
