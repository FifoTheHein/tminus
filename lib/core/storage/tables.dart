import 'package:drift/drift.dart';

import '../model/alert_history_entry.dart';
import '../model/event_occurrence.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/meeting_link.dart';
import '../model/source_config.dart';
import '../model/sync_log_entry.dart';

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

/// The occurrence cache: the latest good fetch per source (spec §5).
@DataClassName('OccurrenceRow')
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS occurrences_start ON occurrences (start_utc_ms)',
)
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS occurrences_source ON occurrences (source_id)',
)
class Occurrences extends Table {
  TextColumn get occurrenceKey => text()();
  TextColumn get sourceId =>
      text().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get uid => text()();
  IntColumn get originalStartUtcMs => integer()();
  TextColumn get seriesUid => text().nullable()();
  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  TextColumn get organizer => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get joinUrl => text().nullable()();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();
  BoolColumn get allDay => boolean()();
  TextColumn get busyStatus => textEnum<BusyStatus>()();
  BoolColumn get declined => boolean()();
  BoolColumn get cancelled => boolean()();
  IntColumn get calendarColor => integer()();

  /// Comma-separated [OccurrenceWarning] names; empty for none.
  TextColumn get warnings => text().withDefault(const Constant(''))();

  /// The event's iCalendar UID where the source has one; null otherwise and
  /// for rows cached before schema 2. Declared last, because a column added
  /// by a migration is appended to the table.
  TextColumn get icalUid => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {occurrenceKey};
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

/// Engine events drained from Kotlin (spec §7), plus `missedSystem` rows
/// Plan 4 adds. De-duplicated on (type, alertId, atUtcMs) (roadmap §3).
@DataClassName('AlertHistoryRow')
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS alert_history_start '
  'ON alert_history (start_utc_ms)',
)
class AlertHistory extends Table {
  @override
  String get tableName => 'alert_history';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<AlertEventType>()();
  TextColumn get alertId => text()();
  TextColumn get occurrenceKey => text()();
  IntColumn get startUtcMs => integer()();
  IntColumn get atUtcMs => integer()();
  IntColumn get snoozeUntilUtcMs => integer().nullable()();

  /// Event title at the time, so Health's timeline survives cache pruning.
  TextColumn get title => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {type, alertId, atUtcMs},
  ];
}

/// One row per source per sync attempt (spec §5, §9).
@DataClassName('SyncLogRow')
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS sync_log_at ON sync_log (at_utc_ms)',
)
class SyncLog extends Table {
  @override
  String get tableName => 'sync_log';

  IntColumn get id => integer().autoIncrement()();

  /// Null for a whole-run entry (e.g. "applyPlan failed").
  TextColumn get sourceId => text().nullable()();
  IntColumn get atUtcMs => integer()();
  TextColumn get outcome => textEnum<SyncOutcome>()();
  TextColumn get message => text().nullable()();
  IntColumn get occurrenceCount => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
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
