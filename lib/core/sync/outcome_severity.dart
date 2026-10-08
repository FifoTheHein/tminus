import '../model/sync_log_entry.dart';

/// How a source looks after a sync: green, amber or red (brief §5, spec §9).
enum OutcomeSeverity { ok, warning, error }

extension SyncOutcomeSeverity on SyncOutcome {
  /// Network trouble and server errors are temporary (amber) and retried.
  /// A link or calendar that is gone, or a feed that will not parse, is red.
  /// A skipped run changed nothing, so it counts as ok.
  OutcomeSeverity get severity => switch (this) {
    SyncOutcome.success ||
    SyncOutcome.notModified ||
    SyncOutcome.emptyKept ||
    SyncOutcome.skipped => OutcomeSeverity.ok,
    SyncOutcome.networkError ||
    SyncOutcome.serverError => OutcomeSeverity.warning,
    SyncOutcome.httpError ||
    SyncOutcome.parseError ||
    SyncOutcome.otherError ||
    SyncOutcome.calendarAccessDenied ||
    SyncOutcome.calendarMissing ||
    SyncOutcome.linkMissing => OutcomeSeverity.error,
  };

  /// True for the failures that post one "Feed broken" notification when a
  /// source first enters them (spec §9; device sources by Plan 4's decision).
  bool get notifiesBroken => switch (this) {
    SyncOutcome.httpError ||
    SyncOutcome.calendarAccessDenied ||
    SyncOutcome.calendarMissing ||
    SyncOutcome.linkMissing => true,
    _ => false,
  };

  /// True when WorkManager should retry the sync with backoff (spec §9).
  bool get retries => severity == OutcomeSeverity.warning;
}
