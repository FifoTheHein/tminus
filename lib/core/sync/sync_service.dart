import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../engine/alarm_engine.dart';
import '../model/planned_alert.dart';
import '../model/quiet_state.dart';
import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import '../model/utc.dart';
import '../planner/empty_feed_guard.dart';
import '../planner/meeting_planner.dart';
import '../planner/plan_builder.dart';
import '../rules/rules_engine.dart';
import '../sources/calendar_source.dart';
import '../sources/ics_feed_source.dart';
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

/// What started a sync (spec §7). The Kotlin side passes [periodic],
/// [calendarChange], [preAlarm], [manual], [timeChange] and [quietTile] by
/// name to the headless engine, never by position.
enum SyncTrigger {
  periodic,
  calendarChange,
  preAlarm,
  manual,

  /// The clock or the time zone changed (decision 28).
  timeChange,
  foreground,
  pullToRefresh,
  debug,

  /// A UI edit (Plan 5 decision 2): plan from the cache, fetch nothing.
  edit,

  /// The quick-settings tile (Plan 5 decision 3): apply its request and plan
  /// from the cache.
  quietTile;

  /// False for the runs that only re-plan.
  bool get fetches => this != edit && this != quietTile;

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
///
/// A trigger whose [SyncTrigger.fetches] is false (a UI edit, the quick-settings
/// tile) skips the fetch and plans from the cache. Every run takes a waiting
/// tile request first and plans through [MeetingPlanner], the one planning
/// path the Agenda uses too.
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

  /// Plans exactly as the Agenda does; this service then stores the link
  /// changes the plan found.
  late final MeetingPlanner _planner = MeetingPlanner(
    sources: sources,
    occurrences: occurrences,
    links: links,
    history: history,
    settings: settings,
    ruleSets: ruleSets,
    rulesEngine: rulesEngine,
  );

  /// When the last run that fetched finished, from any isolate. A run that only
  /// re-plans (a [SyncTrigger] with [SyncTrigger.fetches] false) does not move
  /// it, so a foreground fetch is never skipped because of one.
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
      // Nothing was synced and nothing changed: a skip, not a failure. A run
      // that only re-plans leaves no row for it, as it leaves none when it
      // succeeds.
      if (trigger.fetches) {
        await syncLog.add(
          SyncLogEntry(
            atUtc: clock(),
            outcome: SyncOutcome.skipped,
            message: '${trigger.name}: skipped, another sync was still running',
          ),
        );
      }
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
    final location = zone();
    await _applyQuietRequest(location);

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
    final results = <SourceSyncResult>[];
    if (trigger.fetches) {
      final fetched = await Future.wait([
        for (final c in configs) _fetch(c, window, location),
      ]);
      for (final (config, state, result, source) in fetched) {
        // A source that was removed while the fetches ran has no result.
        final stored = await _store(config, state, result, source, now);
        if (stored != null) results.add(stored);
      }
    }

    final (:plan, :timeSource, :merged) = await _plan(window, now);
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

    final quiet = await settings.quietState();
    await _quietly(
      () => platform.configure(
        watchCalendars: configs.any((c) => c.kind == SourceKind.device),
        preSyncTimes: preSyncTimes(plan, now),
        quietUntil: quietEnd(quiet, location, now),
        quietText: quietTileText(quiet, location, now),
      ),
    );
    await _staleNotices(configs, plan, timeSource, now);

    await history.deleteBefore(now.subtract(historyRetention));
    await syncLog.deleteBefore(now.subtract(syncLogRetention));
    await occurrences.deleteEndedBefore(now.subtract(occurrenceRetention));
    await links.deleteEndedBefore(now.subtract(occurrenceRetention));

    final finished = clock();
    final mergedNote = merged > 0 ? ', $merged merged' : '';
    // A run that only re-plans writes a row when `applyPlan` failed, so that
    // edits do not crowd the sync log, and does not move `lastFinished`.
    if (trigger.fetches || applied == null) {
      await syncLog.add(
        SyncLogEntry(
          atUtc: finished,
          outcome: applied == null
              ? SyncOutcome.otherError
              : SyncOutcome.success,
          message: applied == null
              ? '${trigger.name}: applyPlan failed ($applyError); the engine kept its previous plan$mergedNote'
              : '${trigger.name}: ${plan.length} alerts planned; armed ${applied.armed}, cancelled ${applied.cancelled}, kept ${applied.kept}$mergedNote',
          duration: finished.difference(now),
        ),
      );
    }
    if (trigger.fetches) {
      await settings.setString(
        lastFinishedKey,
        '${finished.millisecondsSinceEpoch}',
      );
    }

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

  /// The source is kept with its result: a source that was removed while it
  /// fetched may have left its feed body behind ([_store]).
  Future<(SourceConfig, SourceSyncState?, SourceResult, CalendarSource?)>
  _fetch(SourceConfig config, FetchWindow window, tz.Location zone) async {
    final state = await sources.syncState(config.id);
    CalendarSource? source;
    SourceResult result;
    try {
      source = buildSource(config, state, zone);
      result = await source.fetch(window);
    } catch (e) {
      debugPrint('Source ${config.id} failed: ${e.runtimeType}');
      result = const SourceFailed(
        SyncOutcome.otherError,
        'Something went wrong while reading this calendar.',
      );
    }
    return (config, state, result, source);
  }

  /// Applies one source's result to the cache, its sync state, the log and
  /// its Feed broken notification (spec §9). Returns null for a source that
  /// was removed while its fetch ran: nothing of it is stored.
  Future<SourceSyncResult?> _store(
    SourceConfig config,
    SourceSyncState? state,
    SourceResult result,
    CalendarSource? source,
    DateTime now,
  ) async {
    // The removal deleted the source's rows, markers, notices and feed body
    // while the fetch was under way. Storing the result would fail on the
    // missing row (failing the whole run), post a notice nobody can fix and
    // write markers that nothing would clear; and the fetch may have written
    // the feed body after the removal deleted it.
    if (await sources.byId(config.id) == null) {
      await _dropFeedBody(source);
      return null;
    }
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
      "Calendar hasn't synced for ${age.inHours} h. Alarms may be outdated";

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

  /// Plans the cached copies of the enabled sources through [MeetingPlanner]
  /// (merging the copies of one meeting, spec §13) and saves the link changes
  /// it found. Also returns the source that decides each planned meeting's
  /// time, for the Feed stale check, and how many meetings were made from two
  /// or more copies.
  ///
  /// The planner reads the enabled sources itself, from the same repository
  /// and with the same test that [_run] uses for its `configs`. A source
  /// switched on or off in the app while this run is going is planned as it
  /// is now, not as it was when the run began. `_store` has already written
  /// this run's result to each source's sync state, so a source that failed
  /// just now ranks below the healthy ones.
  Future<_Planned> _plan(FetchWindow window, DateTime now) async {
    final p = await _planner.load(
      now: now,
      fromUtc: now.subtract(keepAfterEnd),
      toUtc: window.endUtc,
    );
    await links.apply(upsert: p.merge.upsert, delete: p.merge.delete);
    return (
      plan: p.alerts,
      timeSource: p.merge.timeSource,
      merged: p.merge.merged,
    );
  }

  /// A tile tap waits in Kotlin until a run takes it; every run takes it
  /// first, so its plan already reflects the tap (Plan 5 decision 3).
  Future<void> _applyQuietRequest(tz.Location location) async {
    final QuietRequest? request;
    try {
      request = await platform.takeQuietRequest();
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('Taking the quiet request failed: ${e.code}');
      return;
    }
    if (request == null) return;
    // A change made in the app after the tap wins over the tap.
    final changed = await settings.quietChangedAt();
    if (changed != null && changed.isAfter(request.atUtc)) return;
    await settings.setQuietStateAt(
      request.mute
          ? QuietState.muteToday(nowUtc: request.atUtc, zone: location)
          : const QuietNone(),
      changedAtUtc: request.atUtc,
    );
  }

  /// When the tile stops showing "on": the end of a mute or pause, or local
  /// midnight after a vacation's last day. Null unless a quiet mode covers
  /// [now] (a vacation that starts next week does not).
  static DateTime? quietEnd(QuietState q, tz.Location zone, DateTime now) {
    if (!q.covers(now, nowUtc: now, zone: zone)) return null;
    return switch (q) {
      QuietUntil(:final untilUtc) => untilUtc,
      Vacation(:final lastDay) => plainUtc(lastDay.addDays(1).startIn(zone)),
      QuietNone() => null,
    };
  }

  /// The tile's subtitle: `Until 07:00`, `Paused until 14:00`, `Vacation`.
  /// Null unless a quiet mode covers [now].
  static String? quietTileText(QuietState q, tz.Location zone, DateTime now) {
    if (!q.covers(now, nowUtc: now, zone: zone)) return null;
    if (q is MuteToday) {
      final t = tz.TZDateTime.from(q.untilUtc, zone);
      String two(int v) => v.toString().padLeft(2, '0');
      return 'Until ${two(t.hour)}:${two(t.minute)}';
    }
    return q.label(zone, nowUtc: now);
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

  /// Takes the feed body of a source that was removed during its fetch out
  /// again. Only the ICS source that wrote it knows the cache that holds it.
  /// A body that cannot be deleted is logged by type and never fails the run.
  Future<void> _dropFeedBody(CalendarSource? source) async {
    if (source is! IcsFeedSource) return;
    try {
      await source.bodies.delete(source.id);
    } catch (e) {
      debugPrint('Dropping a removed feed body failed: ${e.runtimeType}');
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
