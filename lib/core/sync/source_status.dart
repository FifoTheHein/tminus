import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import '../rules/rules_engine.dart';
import '../storage/app_settings.dart';
import '../storage/source_repository.dart';
import '../storage/sync_log_repository.dart';
import '../text/time_text.dart';
import 'outcome_severity.dart';
import 'sync_service.dart' show SyncService;

/// How a source looks in Sources, Health and the Agenda header (brief §5,
/// spec §9). Only these use the status colours.
enum SourceHealth { ok, stale, warning, error, off, needsSetup }

class SourceStatus {
  const SourceStatus({
    required this.config,
    required this.state,
    required this.latest,
    required this.setup,
    required this.health,
    required this.line,
  });

  final SourceConfig config;
  final SourceSyncState? state;

  /// The source's newest sync-log row; decides amber versus red.
  final SyncLogEntry? latest;
  final SourceSetup setup;
  final SourceHealth health;

  /// The grey (or coloured) line under the name. Never contains a link.
  final String line;
}

SourceStatus sourceStatusOf({
  required SourceConfig config,
  SourceSyncState? state,
  SyncLogEntry? latest,
  required SourceSetup setup,
  required DateTime now,
}) {
  SourceStatus s(SourceHealth h, String line) => SourceStatus(
    config: config,
    state: state,
    latest: latest,
    setup: setup,
    health: h,
    line: line,
  );
  switch (setup) {
    case SourceSetup.needsLink:
      return s(SourceHealth.needsSetup, 'Needs its link');
    case SourceSetup.needsCalendar:
      return s(SourceHealth.needsSetup, 'Choose its calendar on this phone');
    case SourceSetup.ready:
      break;
  }
  if (!config.enabled) return s(SourceHealth.off, 'Off');
  final error = state?.lastError;
  if (error != null) {
    final severity = latest?.outcome.severity ?? OutcomeSeverity.error;
    return s(
      severity == OutcomeSeverity.warning
          ? SourceHealth.warning
          : SourceHealth.error,
      error,
    );
  }
  final last = state?.lastSuccessUtc;
  if (last == null) return s(SourceHealth.ok, 'Not synced yet');
  final ago = TimeText.ago(last, now);
  // Feed stale is checked for ICS sources only (Plan 4 decision 20).
  if (config.kind == SourceKind.ics &&
      now.difference(last) > SyncService.staleAfter) {
    return s(SourceHealth.stale, 'Feed stale · synced $ago');
  }
  return s(SourceHealth.ok, 'Synced $ago');
}

class SourceStatusLoader {
  SourceStatusLoader({
    required this.sources,
    required this.syncLog,
    required this.appSettings,
    UtcClock? clock,
  }) : clock = clock ?? systemUtcNow;

  final SourceRepository sources;
  final SyncLogRepository syncLog;
  final AppSettings appSettings;
  final UtcClock clock;

  /// Every source, in name order, debug sources included.
  Future<List<SourceStatus>> all() async {
    final now = clock();
    return [for (final c in await sources.all()) await _status(c, now)];
  }

  Future<SourceStatus?> byId(String id) async {
    final c = await sources.byId(id);
    return c == null ? null : _status(c, clock());
  }

  Future<SourceStatus> _status(SourceConfig c, DateTime now) async =>
      sourceStatusOf(
        config: c,
        state: await sources.syncState(c.id),
        latest: await syncLog.latestForSource(c.id),
        setup: await appSettings.sourceSetup(c.id),
        now: now,
      );
}
