import 'package:timezone/timezone.dart' as tz;

import '../../core/model/alert_history_entry.dart';
import '../../core/model/local_date.dart';
import '../../core/model/sync_log_entry.dart';
import '../../core/sync/outcome_severity.dart';
import '../../core/text/time_text.dart';
import '../common/status_tone.dart';

/// One line per sync-log outcome. Exhaustive on purpose: a new [SyncOutcome]
/// fails to compile here until it has its text.
String outcomeText(SyncOutcome o) => switch (o) {
  SyncOutcome.success => 'Synced',
  SyncOutcome.notModified => 'Synced (no changes)',
  SyncOutcome.emptyKept => 'Came back empty — kept the previous events',
  SyncOutcome.networkError => 'No connection',
  SyncOutcome.serverError => 'The calendar server had a problem',
  SyncOutcome.httpError => 'The link stopped working',
  SyncOutcome.parseError => "The feed couldn't be read",
  SyncOutcome.otherError => 'Something went wrong',
  SyncOutcome.calendarAccessDenied => 'Calendar access is off',
  SyncOutcome.calendarMissing => 'The calendar was removed',
  SyncOutcome.linkMissing => 'The link is missing',
  SyncOutcome.skipped => 'Skipped — another sync was running',
};

/// A skipped run changed nothing, so it is neutral grey rather than green.
StatusTone outcomeTone(SyncOutcome o) => o == SyncOutcome.skipped
    ? StatusTone.neutral
    : switch (o.severity) {
        OutcomeSeverity.ok => StatusTone.ok,
        OutcomeSeverity.warning => StatusTone.warn,
        OutcomeSeverity.error => StatusTone.error,
      };

/// What a history row says happened. The screen highlights the missed ones.
String historyText(AlertHistoryEntry e, tz.Location zone) => switch (e.type) {
  AlertEventType.fired => 'Rang',
  AlertEventType.snoozed =>
    e.snoozeUntilUtc == null
        ? 'Snoozed'
        : 'Snoozed until ${TimeText.hm(e.snoozeUntilUtc!, zone)}',
  AlertEventType.dismissed => 'Dismissed',
  AlertEventType.dismissedAll => 'Dismissed all',
  AlertEventType.joined => 'Joined',
  AlertEventType.missed => 'Missed — nobody answered',
  AlertEventType.missedSystem => "Missed — the phone didn't ring it",
};

/// Alarms from the Test buttons carry an occurrence key that starts `test|`.
bool isTestEntry(AlertHistoryEntry e) => e.occurrenceKey.startsWith('test|');

bool isMissEntry(AlertHistoryEntry e) =>
    e.type == AlertEventType.missed || e.type == AlertEventType.missedSystem;

/// The event's title. A test alarm has none (it is not in the cache), and an
/// event whose row was pruned before the entry was written has lost it too.
String historyTitle(AlertHistoryEntry e) {
  final title = e.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return isTestEntry(e) ? 'Test alarm' : 'Calendar event';
}

/// `Tue 09:50`: the weekday and the time in [zone], for rows that may be from
/// any day.
String weekdayTime(DateTime utc, tz.Location zone) {
  final local = tz.TZDateTime.from(utc, zone);
  return '${TimeText.weekdays[local.weekday - 1]} ${TimeText.hm(utc, zone)}';
}

/// `09:50` for an alarm that rings today, else `Tue 09:50`.
String upcomingTime(DateTime fireAtUtc, DateTime nowUtc, tz.Location zone) =>
    LocalDate.of(fireAtUtc, zone) == LocalDate.of(nowUtc, zone)
    ? TimeText.hm(fireAtUtc, zone)
    : weekdayTime(fireAtUtc, zone);
