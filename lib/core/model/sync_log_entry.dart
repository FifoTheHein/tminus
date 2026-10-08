import 'utc.dart';

/// Result of one source's sync attempt. Plan 4 may append values (stored by
/// name, so appending is safe); never rename one.
enum SyncOutcome {
  success,
  notModified,
  emptyKept,
  networkError,
  httpError,
  parseError,
  otherError,

  /// HTTP 5xx, 408 or 429: the server is having trouble; retried (Plan 4).
  serverError,

  /// READ_CALENDAR is not granted (device sources).
  calendarAccessDenied,

  /// The Android calendar no longer exists (device sources).
  calendarMissing,

  /// The ICS URL is not in secure storage any more.
  linkMissing,

  /// A run that never got the sync lock and changed nothing (Plan 4).
  skipped,
}

class SyncLogEntry {
  SyncLogEntry({
    this.sourceId,
    required DateTime atUtc,
    required this.outcome,
    this.message,
    this.occurrenceCount,
    this.duration,
  }) : atUtc = plainUtc(atUtc);

  /// Null for a whole-run entry.
  final String? sourceId;
  final DateTime atUtc;
  final SyncOutcome outcome;

  /// Human-readable detail. Must never contain an ICS URL (spec §10).
  final String? message;
  final int? occurrenceCount;
  final Duration? duration;

  @override
  bool operator ==(Object other) =>
      other is SyncLogEntry &&
      other.sourceId == sourceId &&
      other.atUtc == atUtc &&
      other.outcome == outcome &&
      other.message == message &&
      other.occurrenceCount == occurrenceCount &&
      other.duration == duration;

  @override
  int get hashCode =>
      Object.hash(sourceId, atUtc, outcome, message, occurrenceCount, duration);

  @override
  String toString() => 'SyncLogEntry($sourceId, ${outcome.name}, $atUtc)';
}
