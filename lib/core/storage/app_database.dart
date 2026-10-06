import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../model/alert_history_entry.dart';
import '../model/alert_profile.dart';
import '../model/event_occurrence.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import 'profile_mapping.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Sources,
    Occurrences,
    Overrides,
    Profiles,
    KeywordRules,
    QuietStates,
    AlertHistory,
    SyncLog,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Tests pass `DatabaseConnection(NativeDatabase.memory(),
  /// closeStreamsSynchronously: true)`.
  AppDatabase(super.executor);

  /// The on-device database (`tminus.sqlite` in the app's documents
  /// directory). Works in the UI isolate and in the headless sync isolate.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'tminus'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Schema 1 is the first release. Add `if (from < 2) { … }` steps
      // here when bumping [schemaVersion]; never edit a shipped step.
      throw UnsupportedError('No migration from schema $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await seedBuiltInProfiles();
    },
  );

  /// Inserts any missing built-in profile. Never overwrites an edited one.
  Future<void> seedBuiltInProfiles() async {
    await batch((b) {
      for (final (i, p) in BuiltInProfiles.all.indexed) {
        b.insert(
          profiles,
          profileToCompanion(p, position: i),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }
}
