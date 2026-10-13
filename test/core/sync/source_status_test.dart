import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/sync/source_status.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 9, 27);
  const ics = SourceConfig(
    id: 'w',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.w',
  );
  const phone = SourceConfig(
    id: 'p',
    name: 'Personal',
    color: 0xFF5BC489,
    kind: SourceKind.device,
    deviceCalendarId: '3',
  );

  SourceStatus status(
    SourceConfig c, {
    SourceSyncState? state,
    SyncLogEntry? latest,
    SourceSetup setup = SourceSetup.ready,
  }) => sourceStatusOf(
    config: c,
    state: state,
    latest: latest,
    setup: setup,
    now: now,
  );

  test('a fresh success is ok and reads "Synced N min ago"', () {
    final s = status(
      ics,
      state: SourceSyncState(
        lastSuccessUtc: now.subtract(const Duration(minutes: 4)),
      ),
    );
    expect((s.health, s.line), (SourceHealth.ok, 'Synced 4 min ago'));
  });

  test('an ICS source with no success for over 60 min is stale; a phone one '
      'is not', () {
    final old = SourceSyncState(
      lastSuccessUtc: now.subtract(const Duration(minutes: 61)),
    );
    expect(status(ics, state: old).health, SourceHealth.stale);
    expect(status(ics, state: old).line, 'Feed stale · synced 1 h ago');
    expect(status(phone, state: old).health, SourceHealth.ok);
  });

  test(
    'a failure takes its colour from the latest outcome and shows the message',
    () {
      final failed = SourceSyncState(
        lastSuccessUtc: now.subtract(const Duration(days: 2)),
        lastError: 'The link no longer works (HTTP 404).',
      );
      final red = status(
        ics,
        state: failed,
        latest: SyncLogEntry(
          sourceId: 'w',
          atUtc: now,
          outcome: SyncOutcome.httpError,
        ),
      );
      expect(
        (red.health, red.line),
        (SourceHealth.error, 'The link no longer works (HTTP 404).'),
      );
      final amber = status(
        ics,
        state: failed,
        latest: SyncLogEntry(
          sourceId: 'w',
          atUtc: now,
          outcome: SyncOutcome.networkError,
        ),
      );
      expect(amber.health, SourceHealth.warning);
    },
  );

  test('setup wins over everything, then off', () {
    expect(
      status(ics.copyWith(enabled: false), setup: SourceSetup.needsLink).line,
      'Needs its link',
    );
    expect(
      status(
        phone.copyWith(enabled: false),
        setup: SourceSetup.needsCalendar,
      ).line,
      'Choose its calendar on this phone',
    );
    expect(status(ics.copyWith(enabled: false)).health, SourceHealth.off);
    expect(status(ics.copyWith(enabled: false)).line, 'Off');
  });

  test('never synced reads "Not synced yet"', () {
    expect(status(ics).line, 'Not synced yet');
    expect(status(ics).health, SourceHealth.ok);
  });
}
