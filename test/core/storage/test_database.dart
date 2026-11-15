import 'dart:async' show FutureOr;
import 'dart:convert' show latin1;
import 'dart:io' show File;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/cache_database.dart';
import 'package:tminus/core/sync/missed_system.dart';

/// A fresh in-memory database. Close it in tearDown.
///
/// `closeStreamsSynchronously` keeps drift from leaving a timer behind when a
/// watch stream is cancelled, which Flutter's test binding reports as a
/// pending-timer failure.
AppDatabase openTestDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// A fresh in-memory cache database (occurrences, alert history, sync log).
/// Close it in tearDown. Pass [legacy] to test the move of the rows that schema
/// 3 of the main database set aside; most tests have nothing to move.
CacheDatabase openTestCacheDatabase({AppDatabase? legacy}) => CacheDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  legacy: legacy,
);

/// Yields to the event loop until [condition] holds (for watch streams).
/// Fails after [timeout] instead of hanging.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// The names of the tables of [db] that have a text cell containing [text]: for
/// the tests that show a piece of event content never reaches the file that is
/// backed up.
Future<List<String>> tablesHolding(
  DatabaseConnectionUser db,
  String text,
) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  final found = <String>[];
  for (final t in tables) {
    final name = t.read<String>('name');
    final rows = await db.customSelect('SELECT * FROM "$name"').get();
    final holds = rows.any(
      (r) => r.data.values.any((v) => v is String && v.contains(text)),
    );
    if (holds) found.add(name);
  }
  return found;
}

/// Which of [probes] are in the bytes of [file]: free pages, old log frames and
/// all, not only what the database can still read. None if there is no such
/// file (a log that was never made or has been removed). For the tests that
/// show content does not reach the files that are backed up.
List<String> bytesHolding(File file, Iterable<String> probes) {
  if (!file.existsSync()) return const [];
  final text = latin1.decode(file.readAsBytesSync());
  return [
    for (final p in probes)
      if (text.contains(p)) p,
  ];
}

/// What a Plan 5 build (schema 2) held in `sources`, in the three tables that
/// schema 3 sets aside and in the `settings` row of the alerts its last plan
/// expected to ring (Plan 6 decision 4), as the statements that put it into a
/// schema 2 database and as the same rows in domain objects, to compare with
/// once the cache database has moved them. Every column of every row is set to
/// something, or to null for some of the rows, so a column that a move forgets
/// shows.
class Schema2Cache {
  /// [meetings] cached meetings, alternating between the `work` and `phone`
  /// sources, one an hour from [start]. Each title is [titlePrefix] and the
  /// meeting's number: a test that looks for the titles in the bytes of a file
  /// gives it a prefix that nothing else holds.
  factory Schema2Cache({int meetings = 6, String titlePrefix = 'Meeting'}) {
    final sources = const [
      SourceConfig(
        id: 'work',
        name: 'Work Outlook',
        color: 0xFF6AA0F5,
        kind: SourceKind.ics,
        secureStorageKey: 'ics-url.work',
        defaultProfileId: 'meeting',
      ),
      SourceConfig(
        id: 'phone',
        name: 'Personal',
        color: 0xFF5BC489,
        kind: SourceKind.device,
        deviceCalendarId: '3',
      ),
    ];
    final cached = <EventOccurrence>[
      for (var i = 0; i < meetings; i++)
        () {
          final at = start.add(Duration(hours: i));
          return EventOccurrence(
            sourceId: i.isEven ? 'work' : 'phone',
            uid: 'uid$i',
            // Every third meeting was moved: its key keeps the original time.
            originalStartUtc: i % 3 == 0
                ? at.subtract(const Duration(minutes: 30))
                : at,
            seriesUid: i % 4 == 0 ? 'series-$i' : null,
            icalUid: i % 2 == 0 ? 'ical-$i' : null,
            title: '$titlePrefix $i',
            location: i % 3 == 1 ? 'Room $i' : null,
            organizer: i % 2 == 0 ? 'Thandi M.' : null,
            description: i % 5 == 0 ? 'Agenda $i' : null,
            joinUrl: i % 4 == 2
                ? 'https://teams.microsoft.com/l/meetup-join/$i'
                : null,
            startUtc: at,
            endUtc: at.add(const Duration(minutes: 30)),
            allDay: i % 13 == 12,
            busyStatus: BusyStatus.values[i % BusyStatus.values.length],
            declined: i % 7 == 3,
            cancelled: i % 11 == 4,
            calendarColor: 0xFF6AA0F5 + i,
            warnings: i % 6 == 0 ? {OccurrenceWarning.tzFallback} : const {},
          );
        }(),
    ];
    // Only for as many meetings as there are: the first meeting was dismissed,
    // the second fired and was snoozed.
    final history = <AlertHistoryEntry>[
      if (cached.isNotEmpty)
        AlertHistoryEntry(
          type: AlertEventType.dismissedAll,
          alertId: 'alert-0',
          occurrenceKey: cached[0].key,
          startUtc: cached[0].startUtc,
          atUtc: cached[0].startUtc.subtract(const Duration(minutes: 5)),
          title: cached[0].title,
        ),
      if (cached.length > 1) ...[
        AlertHistoryEntry(
          type: AlertEventType.fired,
          alertId: 'alert-1',
          occurrenceKey: cached[1].key,
          startUtc: cached[1].startUtc,
          atUtc: cached[1].startUtc.subtract(const Duration(minutes: 10)),
        ),
        AlertHistoryEntry(
          type: AlertEventType.snoozed,
          alertId: 'alert-1',
          occurrenceKey: cached[1].key,
          startUtc: cached[1].startUtc,
          atUtc: cached[1].startUtc.subtract(const Duration(minutes: 9)),
          snoozeUntilUtc: cached[1].startUtc.subtract(
            const Duration(minutes: 4),
          ),
          title: cached[1].title,
        ),
      ],
    ];
    final log = <SyncLogEntry>[
      SyncLogEntry(
        sourceId: 'work',
        atUtc: start.subtract(const Duration(minutes: 30)),
        outcome: SyncOutcome.success,
        occurrenceCount: meetings,
        duration: const Duration(milliseconds: 120),
      ),
      SyncLogEntry(
        sourceId: 'phone',
        atUtc: start.subtract(const Duration(minutes: 20)),
        outcome: SyncOutcome.calendarMissing,
        message: 'The calendar on this phone is gone.',
      ),
      SyncLogEntry(
        atUtc: start.subtract(const Duration(minutes: 10)),
        outcome: SyncOutcome.otherError,
        message: 'sync: applyPlan failed',
      ),
    ];
    // The first two alerts of the second and third meetings, as the last sync
    // left them for the next one to check.
    final expected = <ExpectedAlert>[
      for (final m in cached.skip(2).take(2))
        ExpectedAlert(
          id: PlannedAlert.idFor(m.key, 10),
          occurrenceKey: m.key,
          fireAtUtc: m.startUtc.subtract(const Duration(minutes: 10)),
          startUtc: m.startUtc,
          title: m.title,
        ),
    ];
    return Schema2Cache._(sources, cached, history, log, expected);
  }

  Schema2Cache._(
    this.sources,
    this.meetings,
    this.history,
    this.log,
    this.expectedAlerts,
  );

  /// The first meeting starts here; the sync log is from just before it.
  static final start = DateTime.utc(2026, 10, 6, 8);

  final List<SourceConfig> sources;
  final List<EventOccurrence> meetings;
  final List<AlertHistoryEntry> history;
  final List<SyncLogEntry> log;

  /// The alerts a Plan 5 build's last sync expected to ring. Each has the
  /// meeting's title in it.
  final List<ExpectedAlert> expectedAlerts;

  /// The `settings` value of [expectedAlerts], as the build wrote it.
  String get expectedAlertsJson => MissedSystemDetector.encode(expectedAlerts);

  /// The name of that `settings` row.
  static const expectedAlertsKey = 'sync.missedSystemExpected';

  /// Runs the statements that put the rows into a schema 2 database through
  /// [execute], which takes the SQL and its arguments. `sqlite3`'s
  /// `Database.execute` and drift's `customStatement` both fit.
  Future<void> insertInto(
    FutureOr<void> Function(String sql, List<Object?> args) execute,
  ) async {
    for (final s in sources) {
      await execute(
        'INSERT INTO sources (id, name, color, kind, device_calendar_id, '
        'secure_storage_key, default_profile_id, enabled) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
        [
          s.id,
          s.name,
          s.color,
          s.kind.name,
          s.deviceCalendarId,
          s.secureStorageKey,
          s.defaultProfileId,
        ],
      );
    }
    for (final o in meetings) {
      await execute(
        'INSERT INTO occurrences (occurrence_key, source_id, uid, '
        'original_start_utc_ms, series_uid, title, location, organizer, '
        'description, join_url, start_utc_ms, end_utc_ms, all_day, '
        'busy_status, declined, cancelled, calendar_color, warnings, '
        'ical_uid) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          o.key,
          o.sourceId,
          o.uid,
          o.originalStartUtc.millisecondsSinceEpoch,
          o.seriesUid,
          o.title,
          o.location,
          o.organizer,
          o.description,
          o.joinUrl,
          o.startUtc.millisecondsSinceEpoch,
          o.endUtc.millisecondsSinceEpoch,
          o.allDay ? 1 : 0,
          o.busyStatus.name,
          o.declined ? 1 : 0,
          o.cancelled ? 1 : 0,
          o.calendarColor,
          o.warnings.map((w) => w.name).join(','),
          o.icalUid,
        ],
      );
    }
    for (final h in history) {
      await execute(
        'INSERT INTO alert_history (type, alert_id, occurrence_key, '
        'start_utc_ms, at_utc_ms, snooze_until_utc_ms, title) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          h.type.name,
          h.alertId,
          h.occurrenceKey,
          h.startUtc.millisecondsSinceEpoch,
          h.atUtc.millisecondsSinceEpoch,
          h.snoozeUntilUtc?.millisecondsSinceEpoch,
          h.title,
        ],
      );
    }
    for (final e in log) {
      await execute(
        'INSERT INTO sync_log (source_id, at_utc_ms, outcome, message, '
        'occurrence_count, duration_ms) VALUES (?, ?, ?, ?, ?, ?)',
        [
          e.sourceId,
          e.atUtc.millisecondsSinceEpoch,
          e.outcome.name,
          e.message,
          e.occurrenceCount,
          e.duration?.inMilliseconds,
        ],
      );
    }
    await execute('INSERT INTO settings (name, value) VALUES (?, ?)', [
      expectedAlertsKey,
      expectedAlertsJson,
    ]);
  }

  /// The history, newest first, as `AlertHistoryRepository.recent` returns it.
  List<AlertHistoryEntry> get historyNewestFirst =>
      history.reversed.toList()..sort((a, b) => b.atUtc.compareTo(a.atUtc));

  /// The log, newest first, as `SyncLogRepository.recent` returns it.
  List<SyncLogEntry> get logNewestFirst =>
      log.reversed.toList()..sort((a, b) => b.atUtc.compareTo(a.atUtc));
}
