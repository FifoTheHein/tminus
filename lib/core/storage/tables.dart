import 'package:drift/drift.dart';

import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/meeting_link.dart';
import '../model/source_config.dart';

// Conventions for every table:
// - Instants are INTEGER milliseconds since the epoch, UTC, in columns ending
//   in `UtcMs`. Drift's own DateTime columns would read back as local time
//   and drop milliseconds; plain ints are explicit and match the channel JSON.
// - Enums are stored by name (`textEnum`), so appending a value is safe and
//   renaming one is a migration.
// - Row classes end in `Row` so they never clash with the domain classes.
// - Indexes are `CREATE INDEX IF NOT EXISTS`, like drift's tables, so two
//   connections opening a new file at once both finish `onCreate`
//   (decision 14).
//
// The occurrence cache, the alert history and the sync log are not here: since
// schema 3 they live in `cache_tables.dart`, in a second database that is never
// backed up (Plan 6 decision 4).

/// Configured calendar sources (spec §5). Never stores an ICS URL; only the
/// key under which Plan 4 keeps it in flutter_secure_storage.
@DataClassName('SourceRow')
class Sources extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  TextColumn get kind => textEnum<SourceKind>()();
  TextColumn get deviceCalendarId => text().nullable()();
  TextColumn get secureStorageKey => text().nullable()();
  TextColumn get defaultProfileId => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get lastAttemptUtcMs => integer().nullable()();
  IntColumn get lastSuccessUtcMs => integer().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get httpEtag => text().nullable()();
  TextColumn get httpLastModified => text().nullable()();
  IntColumn get emptyStreak => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-occurrence and per-series overrides (spec §5). One row per target.
@DataClassName('OverrideRow')
class Overrides extends Table {
  TextColumn get scope => textEnum<OverrideScope>()();
  TextColumn get target => text()();
  TextColumn get profileId => text().nullable()();

  /// Alert list JSON (see `alertsToJson`), null = use the profile's list.
  TextColumn get customAlertsJson => text().nullable()();
  BoolColumn get enabled => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {scope, target};
}

/// Alert profiles, built-in and user-made (spec §6). Alerts are JSON, not a
/// child table: a profile's alerts are always read and written as a whole,
/// never queried on their own, their order is just list order, and the same
/// encoding serves `overrides.custom_alerts_json`.
@DataClassName('ProfileRow')
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get alertsJson => text()();
  TextColumn get soundJson => text()();
  BoolColumn get ringsInQuietMode => boolean()();
  BoolColumn get builtIn => boolean()();

  /// Display order in the Alerts tab.
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Keyword rules (spec §6), run in [position] order.
@DataClassName('RuleRow')
class KeywordRules extends Table {
  @override
  String get tableName => 'rules';

  TextColumn get id => text()();
  IntColumn get position => integer()();
  TextColumn get field => textEnum<RuleField>()();

  /// `match` is an SQL keyword, hence the longer name.
  TextColumn get matchType => textEnum<RuleMatch>()();
  TextColumn get pattern => text()();
  TextColumn get profileId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// How a [QuietStates] row is to be read.
enum QuietKind { none, muteToday, pausedUntil, vacation }

/// The current quiet mode: at most one row, id 1.
@DataClassName('QuietStateRow')
class QuietStates extends Table {
  @override
  String get tableName => 'quiet_state';

  /// Always 1; `SettingsRepository` is the only writer.
  IntColumn get id => integer()();
  TextColumn get kind => textEnum<QuietKind>()();
  IntColumn get untilUtcMs => integer().nullable()();

  /// `yyyy-MM-dd`, local dates, inclusive.
  TextColumn get firstDay => text().nullable()();
  TextColumn get lastDay => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small key/value settings: skip filters (JSON), global default profile id,
/// and later the theme mode (Plan 5).
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

/// Remembered links from a copy to its meeting (spec §13), one row per copy.
/// Added in schema 2.
///
/// Deliberately no foreign key to [Sources]: links outlive a deleted source,
/// so the copies that remain keep the meeting key, and with it the
/// acknowledgements and history recorded under it. They are pruned a day
/// after the copy ends (`MeetingLinkRepository.deleteEndedBefore`).
@DataClassName('MeetingLinkRow')
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS meeting_links_source_uid '
  'ON meeting_links (source_id, uid)',
)
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS meeting_links_meeting_key '
  'ON meeting_links (meeting_key)',
)
class MeetingLinks extends Table {
  /// `EventOccurrence.key` of the copy.
  TextColumn get copyKey => text()();

  /// The sticky key the meeting is planned under.
  TextColumn get meetingKey => text()();

  /// The copy's source. Not a reference, see above.
  TextColumn get sourceId => text()();

  /// The copy's uid, to find a one-off again after it moved.
  TextColumn get uid => text()();

  /// The copy has no series uid.
  BoolColumn get oneOff => boolean()();

  /// The copy's end, for pruning.
  IntColumn get endUtcMs => integer()();
  TextColumn get matchedBy => textEnum<MeetingMatch>()();

  @override
  Set<Column<Object>> get primaryKey => {copyKey};
}
