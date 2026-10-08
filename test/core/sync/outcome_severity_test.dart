import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sync/outcome_severity.dart';

void main() {
  test('each outcome has the colour the error table gives it', () {
    expect(
      {for (final o in SyncOutcome.values) o: o.severity},
      {
        SyncOutcome.success: OutcomeSeverity.ok,
        SyncOutcome.notModified: OutcomeSeverity.ok,
        SyncOutcome.emptyKept: OutcomeSeverity.ok,
        SyncOutcome.networkError: OutcomeSeverity.warning,
        SyncOutcome.httpError: OutcomeSeverity.error,
        SyncOutcome.parseError: OutcomeSeverity.error,
        SyncOutcome.otherError: OutcomeSeverity.error,
        SyncOutcome.serverError: OutcomeSeverity.warning,
        SyncOutcome.calendarAccessDenied: OutcomeSeverity.error,
        SyncOutcome.calendarMissing: OutcomeSeverity.error,
        SyncOutcome.linkMissing: OutcomeSeverity.error,
        SyncOutcome.skipped: OutcomeSeverity.ok,
      },
    );
  });

  test('only a lost link or calendar posts a Feed broken notification', () {
    expect(SyncOutcome.values.where((o) => o.notifiesBroken).toSet(), {
      SyncOutcome.httpError,
      SyncOutcome.calendarAccessDenied,
      SyncOutcome.calendarMissing,
      SyncOutcome.linkMissing,
    });
  });

  test('only temporary failures are retried', () {
    expect(SyncOutcome.values.where((o) => o.retries).toSet(), {
      SyncOutcome.networkError,
      SyncOutcome.serverError,
    });
  });

  test('a skipped run is ok, never retried and never notifies', () {
    expect(SyncOutcome.skipped.severity, OutcomeSeverity.ok);
    expect(SyncOutcome.skipped.retries, isFalse);
    expect(SyncOutcome.skipped.notifiesBroken, isFalse);
  });
}
