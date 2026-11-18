import 'package:drift/drift.dart';

import '../model/alert_history_entry.dart';
import '../model/event_occurrence.dart';
import '../model/sync_log_entry.dart';

// The tables of `tminus_cache.sqlite` (Plan 6 decision 4): the occurrence
// cache, the alert history, the sync log and a few values that carry the same
// content. A restore already throws the first three away, and the backup rules
// do not list the file, so none of it is ever backed up. The three moved here
// from `tables.dart` without changing a column, so the conventions there
// (milliseconds in `…UtcMs` columns, enums by name, row classes ending in
// `Row`, `IF NOT EXISTS` indexes) hold here as well.

/// The occurrence cache: the latest good fetch per source (spec §5).
///
/// Deliberately no foreign key to `sources`: SQLite has no foreign keys across
/// files. Whoever removes a source removes its rows with
/// `OccurrenceRepository.deleteForSource`. Rows left behind for a source that
/// no longer exists plan nothing, because the planner reads only enabled
/// sources' copies, and `deleteEndedBefore` prunes them.
@DataClassName('OccurrenceRow')
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS occurrences_start ON occurrences (start_utc_ms)',
)
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS occurrences_source ON occurrences (source_id)',
)
class Occurrences extends Table {
  TextColumn get occurrenceKey => text()();
  TextColumn get sourceId => text()();
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
  /// for rows cached before schema 2 of `tminus.sqlite`. Declared last, because
  /// a column added by a migration is appended to the table, and the rows moved
  /// here from the old table keep that order.
  TextColumn get icalUid => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {occurrenceKey};
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

/// Small key/value pairs that hold what the cache holds, in another shape.
/// Today one: the alerts the last plan expects to ring, which carry meeting
/// titles and so belong in a file that is never backed up, not in `settings`.
/// Same shape as `settings`; `CacheValueRepository` reads and writes it.
@DataClassName('CacheValueRow')
class CacheValues extends Table {
  /// The alerts the last applied plan expects to ring, as
  /// `MissedSystemDetector.encode` writes them, for the missed (system) check
  /// of the next sync. Each carries the meeting's title. A build before Plan 6
  /// kept it in `settings` under this same name, in the backed-up file, and
  /// `LegacyCacheMove` moves that row here.
  static const expectedAlertsKey = 'sync.missedSystemExpected';

  /// Written in the same transaction as the copy of what a build before Plan 6
  /// had cached (`LegacyCacheMove`), so it is there exactly when that copy is.
  /// Whoever finds it does not copy again: an isolate that stalled between
  /// reading the old tables and writing here would otherwise bring back a
  /// meeting that a sync has removed since.
  static const legacyMovedKey = 'storage.legacyMoved';

  @override
  String get tableName => 'cache_values';

  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}
