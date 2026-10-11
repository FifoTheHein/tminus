import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../engine/alarm_engine.dart';
import '../model/planned_alert.dart';
import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import '../planner/empty_feed_guard.dart';
import '../planner/meeting_merger.dart';
import '../planner/plan_builder.dart';
import '../rules/rules_engine.dart';
import '../sources/calendar_source.dart';
import '../storage/alert_history_repository.dart';
import '../storage/meeting_link_repository.dart';
import '../storage/occurrence_repository.dart';
import '../storage/rule_set_loader.dart';
import '../storage/settings_repository.dart';
import '../storage/source_repository.dart';
import '../storage/sync_log_repository.dart';
import 'device_zone.dart';
import 'engine_event_recorder.dart';
import 'missed_system.dart';
import 'outcome_severity.dart';
import 'pre_sync.dart';
import 'sync_platform.dart';

/// Builds the source to fetch for a stored config; `SourceFactory.create`
/// in the app, a fake in tests.
typedef SourceBuilder = CalendarSource Function(
  SourceConfig config,
  SourceSyncState? state,
  tz.Location zone,
);

/// What a run's planning step produced: the plan, the source that decides the
/// time of each planned meeting (by meeting key), and how many meetings were
/// made from two or more copies.
typedef _Planned = ({
  List<PlannedAlert> plan,
  Map<String, String> timeSource,
  int merged,
});

/// What started a sync (spec §7). The Kotlin side passes the first five by
/// name to the headless engine.
enum SyncTrigger {
  periodic,
  calendarChange,
  preAlarm,
  manual,

  /// The clock or the time zone changed (decision 28).
  timeChange,
  foreground,
  pullToRefresh,
  debug;

  /// An unknown or missing name reads as [manual].
  static SyncTrigger parse(String? name) =>
      SyncTrigger.values.asNameMap()[name] ?? SyncTrigger.manual;
}

/// How a run ended, as `syncMain()` reports it to WorkManager.
enum SyncRunOutcome {
  /// Done; nothing to retry.
  ok,

  /// A source had a temporary failure or `applyPlan` failed: retry with
  /// backoff (spec §9).
  retry,

  /// Another sync held the lock for the whole wait; that one is current.
  busy,
}

class SourceSyncResult {
  const SourceSyncResult(this.sourceId, this.outcome, [this.message]);
  final String sourceId;
  final SyncOutcome outcome;
  final String? message;

  @override
  String toString() => 'SourceSyncResult($sourceId, ${outcome.name})';
}

class SyncReport {
  const SyncReport({
    required this.trigger,
    required this.outcome,
    this.sources = const [],
    this.applied,
    this.planned = 0,
    this.missedSystem = 0,
    this.merged = 0,
  });

  final SyncTrigger trigger;
  final SyncRunOutcome outcome;
  final List<SourceSyncResult> sources;

  /// Null when `applyPlan` failed or the run was [SyncRunOutcome.busy].
  final ApplyResult? applied;
  final int planned;

  /// New `missedSystem` history rows this run recorded.
  final int missedSystem;

  /// Meetings this run planned from the copies of two or more sources
  /// (spec §13). Zero when merging is off.
  final int merged;
}

/// `syncMain()`'s work (spec §7): fetch all sources → update the cache →
/// merge the copies of one meeting → resolve rules → build the plan →
/// `applyPlan` → log the result. Runs in the headless engine (SyncWorker) and
/// in the UI isolate (app foreground, pull-to-refresh); a lock shared through
/// Kotlin keeps two runs from overlapping (Plan 4 decision).
class SyncService {
  SyncService({
    required this.sources,
    required this.occurrences,
    required this.links,
    required this.history,
    required this.syncLog,
    required this.settings,
    required this.ruleSets,
    required this.rulesEngine,
    required this.engine,
    required this.recorder,
    required this.platform,
    required this.buildSource,
    tz.Location Function()? zone,
    UtcClock? clock,
    this.lockWait = const Duration(seconds: 60),
    this.lockPoll = const Duration(milliseconds: 500),
  }) : zone = zone ?? (() => tz.local),
       clock = clock ?? systemUtcNow;

  final SourceRepository sources;
  final OccurrenceRepository occurrences;

  /// The remembered links from copies to their meetings (spec §13).
  final MeetingLinkRepository links;
  final AlertHistoryRepository history;
  final SyncLogRepository syncLog;
  final SettingsRepository settings;
  final RuleSetLoader ruleSets;

  /// A new engine per run, so it reads `tz.local` as it is now.
  final RulesEngine Function() rulesEngine;
  final AlarmEngine engine;
  final EngineEventRecorder recorder;
  final SyncPlatform platform;
  final SourceBuilder buildSource;

  /// The device zone; `tz.local` once `initDeviceZone` has run.
  final tz.Location Function() zone;
  final UtcClock clock;
  final Duration lockWait;
  final Duration lockPoll;

  /// Longer than any run can take (per-source fetches are capped at 20 s and
  /// run in parallel); a lock left by a killed engine runs out by itself.
  static const lockLease = Duration(minutes: 5);
  static const lastFinishedKey = 'sync.lastFinishedUtcMs';
  static const expectedKey = 'sync.missedSystemExpected';
  static const historyRetention = Duration(days: 30);
  static const syncLogRetention = Duration(days: 7);
  static const occurrenceRetention = Duration(days: 1);

  /// The setting that turns merging off (spec §13). Merging is on unless the
  /// stored value is exactly `'false'`, so a missing value keeps it on. Plan
  /// 5's Settings switch writes it; until then the debug panel does.
  static const mergeEnabledKey = 'merge.enabled';

  /// Server errors that have gone on this long, with no success in between,
  /// mean the link is gone (Plan 4 decision 24: Outlook answers a dead link
  /// with HTTP 500).
  static const serverErrorsBeforeBroken = Duration(hours: 24);

  /// Spec §9: "Feed stale > 60 min with an alert due within 2 h".
  static const staleAfter = Duration(minutes: 60);
  static const staleHorizon = Duration(hours: 2);

  /// Holds the outcome a source's Feed broken notice was posted for; empty
  /// or absent while none is up (decision 26).
  static String brokenNoticeKey(String sourceId) =>
      'sync.brokenNotice.$sourceId';

  /// Holds when a source's current run of server errors began, in epoch
  /// milliseconds: the first `serverError` since it last succeeded or was
  /// switched off (or ever, if neither). Empty or absent while it has none.
  /// Kept in settings,
  /// not read back from the sync log, for the reason decision 26 gives for
  /// the notice: the log is pruned after [syncLogRetention] and records an
  /// escalated failure as `httpError`, so a long outage would lose its start
  /// and slip back to amber.
  static String serverErrorSinceKey(String sourceId) =>
      'sync.serverErrorSince.$sourceId';

  final _random = Random();

  /// When the last run finished, from any isolate.
  Future<DateTime?> lastFinished() async {
    final ms = int.tryParse(await settings.getString(lastFinishedKey) ?? '');
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<SyncReport> run(SyncTrigger trigger) async {
    final owner =
        'sync-${clock().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
    if (!await _acquire(owner)) {
      // Nothing was synced and nothing changed: a skip, not a failure.
      await syncLog.add(
        SyncLogEntry(
          atUtc: clock(),
          outcome: SyncOutcome.skipped,
          message: '${trigger.name}: skipped, another sync was still running',
        ),
      );
      return SyncReport(trigger: trigger, outcome: SyncRunOutcome.busy);
    }
    try {
      return await _run(trigger);
    } finally {
      await _quietly(() => platform.releaseLock(owner));
    }
  }

  /// Waits up to [lockWait] of real time (not [clock]) for the lock.
  Future<bool> _acquire(String owner) async {
    final waited = Stopwatch()..start();
    while (true) {
      try {
        if (await platform.acquireLock(owner, lockLease)) return true;
      } on MissingPluginException {
        return true; // no native side: nothing else can be syncing
      }
      if (waited.elapsed >= lockWait) return false;
      await Future<void>.delayed(lockPoll);
    }
  }

  Future<SyncReport> _run(SyncTrigger trigger) async {
    // The phone may have changed zone since this isolate started; the rules
    // engine and the sources read `tz.local` (decision 28).
    await initDeviceZone(platform);
    final now = clock();
    final window = FetchWindow.around(now);

    // History first: the planner's acknowledgements and the missed (system)
    // check both read it.
    await _quietly(recorder.drainNow);

    final all = await sources.all();
    final configs = [
      for (final s in all)
        if (s.enabled) s,
    ];
    for (final s in all.where((s) => !s.enabled)) {
      await _withdrawNotices(s.id);
      await _endServerErrors(s.id);
    }
    final location = zone();
    final fetched = await Future.wait([
      for (final c in configs) _fetch(c, window, location),
    ]);
    final results = <SourceSyncResult>[];
    for (final (config, state, result) in fetched) {
      results.add(await _store(config, state, result, now));
    }

    final (:plan, :timeSource, :merged) = await _plan(configs, window, now);
    final missed = await _checkMissed(now);

    ApplyResult? applied;
    String? applyError;
    try {
      applied = await engine.applyPlan(plan);
    } on PlatformException catch (e) {
      applyError = e.code;
    } on MissingPluginException {
      applyError = 'no alarm engine';
    }
    await settings.setString(
      expectedKey,
      MissedSystemDetector.encode(
        applied == null
            ? missed.pending
            : MissedSystemDetector.expectedAfterApply(
                pending: missed.pending,
                plan: plan,
                now: now,
              ),
      ),
    );

    await _quietly(
      () => platform.configure(
        watchCalendars: configs.any((c) => c.kind == SourceKind.device),
        preSyncTimes: preSyncTimes(plan, now),
      ),
    );
    await _staleNotices(configs, plan, timeSource, now);

    await history.deleteBefore(now.subtract(historyRetention));
    await syncLog.deleteBefore(now.subtract(syncLogRetention));
    await occurrences.deleteEndedBefore(now.subtract(occurrenceRetention));
    await links.deleteEndedBefore(now.subtract(occurrenceRetention));

    final finished = clock();
    final mergedNote = merged > 0 ? ', $merged merged' : '';
    await syncLog.add(
      SyncLogEntry(
        atUtc: finished,
        outcome: applied == null ? SyncOutcome.otherError : SyncOutcome.success,
        message: applied == null
            ? '${trigger.name}: applyPlan failed ($applyError); the engine kept its previous plan$mergedNote'
            : '${trigger.name}: ${plan.length} alerts planned; armed ${applied.armed}, cancelled ${applied.cancelled}, kept ${applied.kept}$mergedNote',
        duration: finished.difference(now),
      ),
    );
    await settings.setString(
      lastFinishedKey,
      '${finished.millisecondsSinceEpoch}',
    );

    final retry = applied == null || results.any((r) => r.outcome.retries);
    return SyncReport(
      trigger: trigger,
      outcome: retry ? SyncRunOutcome.retry : SyncRunOutcome.ok,
      sources: results,
      applied: applied,
      planned: plan.length,
      missedSystem: missed.recorded,
      merged: merged,
    );
  }

  Future<(SourceConfig, SourceSyncState?, SourceResult)> _fetch(
    SourceConfig config,
    FetchWindow window,
    tz.Location zone,
  ) async {
    final state = await sources.syncState(config.id);
    SourceResult result;
    try {
      result = await buildSource(config, state, zone).fetch(window);
    } catch (e) {
      debugPrint('Source ${config.id} failed: ${e.runtimeType}');
      result = const SourceFailed(
        SyncOutcome.otherError,
        'Something went wrong while reading this calendar.',
      );
    }
    return (config, state, result);
  }

  /// Applies one source's result to the cache, its sync state, the log and
  /// its Feed broken notification (spec §9).
  Future<SourceSyncResult> _store(
    SourceConfig config,
    SourceSyncState? state,
    SourceResult result,
    DateTime now,
  ) async {
    // Not the last sync-log row: an amber failure in between would hide that
    // a notice is up (decision 26).
    final noticeKey = brokenNoticeKey(config.id);
    final notified = await settings.getString(noticeKey);
    switch (result) {
      case SourceFetched(occurrences: final fresh):
        final verdict = EmptyFeedGuard.evaluate(
          previousCount: await occurrences.countForSource(config.id),
          newCount: fresh.length,
          consecutiveEmpty: state?.emptyStreak ?? 0,
        );
        final kept = verdict.action == EmptyFeedAction.keepPrevious;
        if (!kept) {
          await occurrences.replaceForSource(config.id, fresh);
        }
        await _endServerErrors(config.id);
        await sources.updateSyncState(
          config.id,
          SourceSyncState(
            lastAttemptUtc: now,
            lastSuccessUtc: now,
            httpEtag: result.httpEtag,
            httpLastModified: result.httpLastModified,
            emptyStreak: verdict.consecutiveEmpty,
          ),
        );
        final outcome = kept
            ? SyncOutcome.emptyKept
            : result.notModified
            ? SyncOutcome.notModified
            : SyncOutcome.success;
        final message = kept
            ? 'The calendar came back empty; kept its events until it is empty twice in a row.'
            : result.issues.isEmpty
            ? null
            : '${result.issues.length} events skipped: ${result.issues.take(3).join('; ')}';
        await _log(config.id, now, outcome, message, fresh.length);
        if (notified != null && notified.isNotEmpty) {
          final withdrawn = await _quietly(
            () => platform.cancelSourceNotice(
              kind: SourceNoticeKind.broken,
              sourceId: config.id,
            ),
          );
          if (withdrawn) await settings.setString(noticeKey, '');
        }
        return SourceSyncResult(config.id, outcome, message);

      case SourceFailed():
        final (:outcome, :message) = await _escalate(config, result, now);
        await sources.updateSyncState(
          config.id,
          SourceSyncState(
            lastAttemptUtc: now,
            lastSuccessUtc: state?.lastSuccessUtc,
            lastError: message,
            httpEtag: state?.httpEtag,
            httpLastModified: state?.httpLastModified,
            emptyStreak: state?.emptyStreak ?? 0,
          ),
        );
        await _log(config.id, now, outcome, message, null);
        if (outcome.notifiesBroken && notified != outcome.name) {
          final posted = await _quietly(
            () => platform.postSourceNotice(
              kind: SourceNoticeKind.broken,
              sourceId: config.id,
              title: brokenTitle(config, outcome),
              text: message,
            ),
          );
          if (posted) await settings.setString(noticeKey, outcome.name);
        }
        return SourceSyncResult(config.id, outcome, message);
    }
  }

  /// A server error is reported as a broken link once the earliest server
  /// error since the source last succeeded (or ever, if it never has) is at
  /// least [serverErrorsBeforeBroken] old. Only a server error is ever
  /// escalated, and only server errors set the clock: a network error before
  /// or between them neither counts toward the time nor restarts it, because
  /// being offline says nothing about the link. Only a success, or the
  /// source being switched off, restarts it ([_endServerErrors]).
  Future<({SyncOutcome outcome, String message})> _escalate(
    SourceConfig config,
    SourceFailed failure,
    DateTime now,
  ) async {
    final asIs = (outcome: failure.outcome, message: failure.message);
    if (failure.outcome != SyncOutcome.serverError) return asIs;
    final key = serverErrorSinceKey(config.id);
    final began = int.tryParse(await settings.getString(key) ?? '');
    if (began == null) {
      // The first server error since the last success.
      await settings.setString(key, '${now.millisecondsSinceEpoch}');
      return asIs;
    }
    final since = DateTime.fromMillisecondsSinceEpoch(began, isUtc: true);
    if (now.difference(since) < serverErrorsBeforeBroken) return asIs;
    return (
      outcome: SyncOutcome.httpError,
      message:
          'The calendar server has kept failing for over '
          '${serverErrorsBeforeBroken.inHours} h. The link may have been '
          'reset or unpublished.',
    );
  }

  /// A success, or the source being switched off, ends its run of server
  /// errors; the next one starts the clock afresh (decision 24). A source
  /// that is switched back on does not inherit the old run.
  Future<void> _endServerErrors(String sourceId) async {
    final key = serverErrorSinceKey(sourceId);
    if ((await settings.getString(key) ?? '').isNotEmpty) {
      await settings.setString(key, '');
    }
  }

  /// The Feed broken title (brief §10, per source).
  static String brokenTitle(SourceConfig config, SyncOutcome outcome) =>
      switch (outcome) {
        SyncOutcome.calendarAccessDenied =>
          '${config.name}: calendar access was turned off',
        SyncOutcome.calendarMissing => '${config.name}: calendar was removed',
        _ => '${config.name} feed link stopped working',
      };

  /// The Feed stale title (brief §10).
  static String staleTitle(Duration age) =>
      "Calendar hasn't synced for ${age.inHours} h — alarms may be outdated";

  Future<void> _log(
    String sourceId,
    DateTime at,
    SyncOutcome outcome,
    String? message,
    int? count,
  ) => syncLog.add(
    SyncLogEntry(
      sourceId: sourceId,
      atUtc: at,
      outcome: outcome,
      message: message,
      occurrenceCount: count,
    ),
  );

  /// Reads the cached copies of the enabled sources, merges the copies of one
  /// meeting (spec §13), saves the link changes and plans the meetings. Also
  /// returns the source that decides each planned meeting's time, for the Feed
  /// stale check, and how many meetings were made from two or more copies.
  Future<_Planned> _plan(
    List<SourceConfig> configs,
    FetchWindow window,
    DateTime now,
  ) async {
    final enabled = {for (final c in configs) c.id};
    final cached = await occurrences.between(
      now.subtract(keepAfterEnd),
      window.endUtc,
    );

    // `_store` has already written this run's result to each source's sync
    // state, so a source that failed just now ranks below the healthy ones.
    final ranks = <String, SourceRank>{};
    for (final c in configs) {
      final state = await sources.syncState(c.id);
      ranks[c.id] = SourceRank(kind: c.kind, failing: state?.lastError != null);
    }
    final result = MeetingMerger.merge(
      copies: [
        for (final o in cached)
          if (enabled.contains(o.sourceId)) o,
      ],
      links: await links.all(),
      sources: ranks,
      enabled: await settings.getString(mergeEnabledKey) != 'false',
    );
    await links.apply(upsert: result.upsert, delete: result.delete);

    final rules = await ruleSets.load();
    final resolved = rulesEngine().resolveAll(result.meetings, rules);
    final plan = buildPlan(
      resolved,
      now: now,
      acknowledgements: await history.acknowledgements(nowUtc: now),
    );
    return (plan: plan, timeSource: result.timeSource, merged: result.merged);
  }

  Future<({List<ExpectedAlert> pending, int recorded})> _checkMissed(
    DateTime now,
  ) async {
    final expected = MissedSystemDetector.decode(
      await settings.getString(expectedKey),
    );
    if (expected.isEmpty) return (pending: expected, recorded: 0);
    final oldest = expected
        .map((e) => e.fireAtUtc)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final check = MissedSystemDetector.check(
      expected: expected,
      history: await history.since(oldest.subtract(const Duration(days: 1))),
      now: now,
    );
    var recorded = 0;
    for (final m in check.missed) {
      if (await history.record(m)) recorded++;
    }
    return (pending: check.pending, recorded: recorded);
  }

  /// Posts or withdraws each ICS source's Feed stale notification. An alert
  /// counts toward a source only if that source decides its meeting's time
  /// ([timeSource], spec §13): a stale feed whose meetings a healthy phone
  /// calendar times does not warn, and one that times a meeting under another
  /// source's key still does.
  Future<void> _staleNotices(
    List<SourceConfig> configs,
    List<PlannedAlert> plan,
    Map<String, String> timeSource,
    DateTime now,
  ) async {
    for (final c in configs.where((c) => c.kind == SourceKind.ics)) {
      final lastSuccess = (await sources.syncState(c.id))?.lastSuccessUtc;
      final age = lastSuccess == null ? null : now.difference(lastSuccess);
      final dueSoon = plan.any(
        (a) =>
            timeSource[a.occurrenceKey] == c.id &&
            a.fireAtUtc.isAfter(now) &&
            !a.fireAtUtc.isAfter(now.add(staleHorizon)),
      );
      if (age != null && age > staleAfter && dueSoon) {
        await _quietly(
          () => platform.postSourceNotice(
            kind: SourceNoticeKind.stale,
            sourceId: c.id,
            title: staleTitle(age),
            text: c.name,
          ),
        );
      } else {
        await _quietly(
          () => platform.cancelSourceNotice(
            kind: SourceNoticeKind.stale,
            sourceId: c.id,
          ),
        );
      }
    }
  }

  /// A disabled source keeps no notices (decision 27).
  Future<void> _withdrawNotices(String sourceId) async {
    for (final kind in SourceNoticeKind.values) {
      await _quietly(
        () => platform.cancelSourceNotice(kind: kind, sourceId: sourceId),
      );
    }
    await settings.setString(brokenNoticeKey(sourceId), '');
  }

  /// Platform side effects never fail a sync. Returns whether the call went
  /// through.
  static Future<bool> _quietly(Future<Object?> Function() call) async {
    try {
      await call();
      return true;
    } on MissingPluginException {
      // No native side (tests, desktop).
      return false;
    } on PlatformException catch (e) {
      debugPrint('Sync side effect failed: ${e.code}');
      return false;
    }
  }
}
