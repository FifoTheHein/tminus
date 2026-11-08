import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/replan_scheduler.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/meeting_occurrence.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/planner/meeting_planner.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/app_settings.dart';
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/source_status.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/agenda/agenda_controller.dart';
import 'package:tminus/features/agenda/agenda_model.dart';

import '../../core/fixtures.dart';
import '../../core/storage/test_database.dart';

/// A loader that can be held while it is loading and told to throw. It reads
/// the database as soon as a load starts, like the real one, and then waits
/// for its gate.
class _GatedLoader extends AgendaLoader {
  _GatedLoader(AgendaLoader real)
    : super(
        planner: real.planner,
        statuses: real.statuses,
        settings: real.settings,
        appSettings: real.appSettings,
        zone: real.zone,
        clock: real.clock,
      );

  /// While true a load waits for its gate after it has read the database.
  bool hold = false;

  /// Thrown by the next loads when set.
  Object? failWith;

  /// Per load, in the order the loads started: complete when it has read the
  /// database, and the gate that lets it finish.
  final reading = <Completer<void>>[];
  final gates = <Completer<void>>[];

  @override
  Future<AgendaSnapshot> load() async {
    final error = failWith;
    if (error != null) throw error;
    final read = Completer<void>();
    final gate = Completer<void>();
    reading.add(read);
    gates.add(gate);
    final snapshot = await super.load();
    read.complete();
    if (hold) await gate.future;
    return snapshot;
  }
}

/// Fails every toggle write, as a database that is locked or full would.
class _FailingOverrides extends OverrideRepository {
  _FailingOverrides(super.db);

  @override
  Future<void> rewriteFor(
    OverrideScope scope,
    List<String> targets,
    EventOverride Function(EventOverride? effective) change,
  ) => Future.error(StateError('the database is locked'));
}

void main() {
  // 09:27 on Tuesday 6 Oct 2026 in Johannesburg, which is UTC+2 all year.
  final now = DateTime.utc(2026, 10, 6, 7, 27);

  // Named so that their order by name (feed, phone) is not their rank order
  // (phone, feed).
  const feed = SourceConfig(
    id: 'feed',
    name: 'Acme feed',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.feed',
  );
  const phone = SourceConfig(
    id: 'phone',
    name: 'Phone calendar',
    color: 0xFF5BC489,
    kind: SourceKind.device,
    deviceCalendarId: '7',
  );

  late AppDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;
  late OverrideRepository overrides;
  late SettingsRepository settings;
  late AgendaLoader loader;
  late ReplanScheduler replan;
  var replans = 0;
  final syncs = <SyncTrigger>[];
  late SyncReport Function(SyncTrigger) syncResult;

  /// A Johannesburg wall-clock time in October 2026, as UTC.
  DateTime local(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 10, day, hour - 2, minute);

  RulesEngine rulesEngine() =>
      RulesEngine(zone: johannesburg, clock: () => now);

  /// A meeting of the `feed` source; its title is made from its uid.
  EventOccurrence feedOcc(String uid, DateTime start) =>
      occ(sourceId: 'feed', uid: uid, start: start, title: 'Meeting $uid');

  Future<void> seed(
    SourceConfig source,
    List<EventOccurrence> occurrences,
  ) async {
    await sources.save(source);
    await cache.replaceForSource(source.id, occurrences);
  }

  /// A controller on the real database. Its debounce is zero, so a write is
  /// seen on the next turn of the event loop, and its tick is long.
  AgendaController controllerFor([AgendaLoader? use]) {
    final c = AgendaController(
      loader: use ?? loader,
      db: db,
      overrides: overrides,
      settings: settings,
      rulesEngine: rulesEngine,
      replan: replan,
      runSync: (trigger) async {
        syncs.add(trigger);
        return syncResult(trigger);
      },
      tick: const Duration(hours: 1),
      debounce: Duration.zero,
    );
    addTearDown(c.dispose);
    return c;
  }

  AgendaItem onlyItem(AgendaController c) =>
      c.snapshot!.days.single.items.single;

  setUp(() {
    initZones();
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    overrides = OverrideRepository(db);
    settings = SettingsRepository(db);
    final appSettings = AppSettings(settings);
    final ruleSets = RuleSetLoader(
      profiles: ProfileRepository(db),
      rules: RuleRepository(db),
      overrides: overrides,
      settings: settings,
      sources: sources,
    );
    loader = AgendaLoader(
      planner: MeetingPlanner(
        sources: sources,
        occurrences: cache,
        links: MeetingLinkRepository(db),
        history: AlertHistoryRepository(db),
        settings: settings,
        ruleSets: ruleSets,
        rulesEngine: rulesEngine,
      ),
      statuses: SourceStatusLoader(
        sources: sources,
        syncLog: SyncLogRepository(db),
        appSettings: appSettings,
        clock: () => now,
      ),
      settings: settings,
      appSettings: appSettings,
      zone: () => johannesburg,
      clock: () => now,
    );
    replans = 0;
    replan = ReplanScheduler(
      replan: () async => replans++,
      delay: Duration.zero,
    );
    syncs.clear();
    syncResult = (t) => SyncReport(trigger: t, outcome: SyncRunOutcome.ok);
  });

  tearDown(() async {
    replan.dispose();
    await db.close();
  });

  test('toggling a meeting off writes enabled false on the meeting key and '
      'asks for a re-plan', () async {
    final sprint = feedOcc('sprint', local(6, 10));
    await seed(feed, [sprint]);
    final c = controllerFor();
    await c.reload();
    expect(onlyItem(c).on, isTrue);

    await c.setOn(onlyItem(c), false);
    await replan.flush();

    expect(await overrides.all(), [
      EventOverride(
        scope: OverrideScope.occurrence,
        target: sprint.key,
        enabled: false,
      ),
    ]);
    expect(replans, 1);
    expect(syncs, isEmpty); // a re-plan, never a fetching sync
  });

  test('toggling it back on removes the override', () async {
    final sprint = feedOcc('sprint', local(6, 10));
    await seed(feed, [sprint]);
    final c = controllerFor();
    await c.reload();
    await c.setOn(onlyItem(c), false);
    await c.reload();
    expect(onlyItem(c).on, isFalse);
    expect(onlyItem(c).resolved.explanation, 'Off · this event');

    await c.setOn(onlyItem(c), true);

    // On is what the meeting does by itself, so nothing is left to store.
    expect(await overrides.all(), isEmpty);
    await c.reload();
    expect(onlyItem(c).on, isTrue);
  });

  test('a meeting silenced by Mute today switched on is turned on', () async {
    final sprint = feedOcc('sprint', local(6, 10));
    await seed(feed, [sprint]);
    // Until 07:00 tomorrow. The Meeting profile does not ring in a quiet mode.
    await settings.setQuietState(MuteToday(DateTime.utc(2026, 10, 7, 5)));
    final c = controllerFor();
    await c.reload();
    expect(onlyItem(c).resolved.silenced, isTrue);
    expect(onlyItem(c).on, isFalse);

    await c.setOn(onlyItem(c), true);

    expect(
      (await overrides.find(OverrideScope.occurrence, sprint.key))?.enabled,
      isTrue,
    );
    await c.reload();
    expect(onlyItem(c).on, isTrue); // it rings through the quiet mode
  });

  test('a copy-key override moves to the meeting key when the toggle is '
      'used', () async {
    // One meeting from two sources: the phone copy ranks first, so the
    // meeting takes its key, and the feed copy's key is a copy key.
    await seed(feed, [occ(sourceId: 'feed', uid: 'F1')]);
    await seed(phone, [occ(sourceId: 'phone', uid: '42')]);
    final c = controllerFor();
    await c.reload();
    final meeting = onlyItem(c).meeting as MeetingOccurrence;
    expect(meeting.copies, hasLength(2));
    final copyKey = meeting.lookupKeys.firstWhere((k) => k != meeting.key);
    await overrides.save(
      EventOverride(
        scope: OverrideScope.occurrence,
        target: copyKey,
        profileId: 'quick',
      ),
    );
    await c.reload();
    expect(onlyItem(c).resolved.profile.id, 'quick');

    await c.setOn(onlyItem(c), false);

    expect(
      await overrides.find(OverrideScope.occurrence, meeting.key),
      EventOverride(
        scope: OverrideScope.occurrence,
        target: meeting.key,
        profileId: 'quick',
        enabled: false,
      ),
    );
    expect(await overrides.find(OverrideScope.occurrence, copyKey), isNull);
    expect(await overrides.all(), hasLength(1));
  });

  test('pullMessage says busy, how many calendars failed, or nothing', () {
    SyncReport report(SyncRunOutcome outcome, [List<SyncOutcome>? results]) =>
        SyncReport(
          trigger: SyncTrigger.pullToRefresh,
          outcome: outcome,
          sources: [
            for (final (i, o) in (results ?? const <SyncOutcome>[]).indexed)
              SourceSyncResult('source-$i', o),
          ],
        );

    expect(
      pullMessage(report(SyncRunOutcome.busy)),
      'Another sync is running. Try again in a minute.',
      reason: 'busy',
    );
    expect(
      pullMessage(
        report(SyncRunOutcome.ok, [SyncOutcome.success, SyncOutcome.httpError]),
      ),
      '1 calendar could not be read. See Sources.',
      reason: 'one failed',
    );
    expect(
      pullMessage(
        report(SyncRunOutcome.retry, [
          SyncOutcome.networkError,
          SyncOutcome.success,
          SyncOutcome.parseError,
        ]),
      ),
      '2 calendars could not be read. See Sources.',
      reason: 'two failed',
    );
    expect(
      pullMessage(
        report(SyncRunOutcome.ok, [
          SyncOutcome.success,
          SyncOutcome.notModified,
          SyncOutcome.emptyKept,
          SyncOutcome.skipped,
        ]),
      ),
      isNull,
      reason: 'none failed',
    );
    expect(
      pullMessage(report(SyncRunOutcome.ok)),
      isNull,
      reason: 'no sources',
    );
  });

  test('a table write reloads the snapshot', () async {
    final sprint = feedOcc('sprint', local(6, 10));
    await seed(feed, [sprint]);
    final c = controllerFor()..start();
    await waitUntil(() => c.snapshot != null);
    expect(onlyItem(c).on, isTrue);

    await overrides.save(
      EventOverride(
        scope: OverrideScope.occurrence,
        target: sprint.key,
        enabled: false,
      ),
    );

    await waitUntil(() => onlyItem(c).on == false);
  });

  // Tests beyond the plan's list start here.

  test('pulling to refresh runs a pullToRefresh sync and returns its line, '
      'and is not a re-plan', () async {
    syncResult = (t) => SyncReport(trigger: t, outcome: SyncRunOutcome.busy);
    final c = controllerFor();

    expect(
      await c.pullToRefresh(),
      'Another sync is running. Try again in a minute.',
    );

    expect(syncs, [SyncTrigger.pullToRefresh]);
    await replan.flush();
    expect(replans, 0);
  });

  test('ending quiet mode stores it with the time of the change on the '
      "Agenda's clock and asks for a re-plan", () async {
    await settings.setQuietState(MuteToday(DateTime.utc(2026, 10, 7, 5)));
    final c = controllerFor();

    await c.endQuiet();
    await replan.flush();

    expect(await settings.quietState(), const QuietNone());
    // Recorded, so that a quick-settings tap older than this is dropped.
    expect(await settings.quietChangedAt(), now);
    expect(replans, 1);
  });

  test('the toggle carries the custom alerts of a copy key to the meeting '
      'key too', () async {
    await seed(feed, [occ(sourceId: 'feed', uid: 'F1')]);
    await seed(phone, [occ(sourceId: 'phone', uid: '42')]);
    final c = controllerFor();
    await c.reload();
    final meeting = onlyItem(c).meeting;
    final copyKey = meeting.lookupKeys.firstWhere((k) => k != meeting.key);
    const custom = [AlertSpec(5, AlertStrength.alarm)];
    await overrides.save(
      EventOverride(
        scope: OverrideScope.occurrence,
        target: copyKey,
        customAlerts: custom,
      ),
    );
    await c.reload();

    await c.setOn(onlyItem(c), false);

    expect(
      await overrides.find(OverrideScope.occurrence, meeting.key),
      EventOverride(
        scope: OverrideScope.occurrence,
        target: meeting.key,
        customAlerts: custom,
        enabled: false,
      ),
    );
    expect(await overrides.find(OverrideScope.occurrence, copyKey), isNull);
  });

  test('the natural state and the write agree when two lookup keys hold '
      'overrides', () async {
    // The default profile rings nothing, so on its own the meeting is off and
    // only an override can turn it on.
    await settings.setGlobalDefaultProfileId(BuiltInProfiles.silentId);
    await seed(feed, [occ(sourceId: 'feed', uid: 'F1')]);
    await seed(phone, [occ(sourceId: 'phone', uid: '42')]);
    final c = controllerFor();
    await c.reload();
    final meeting = onlyItem(c).meeting;
    final copyKey = meeting.lookupKeys.firstWhere((k) => k != meeting.key);
    // The meeting key comes first, so its override is the one in effect: off.
    // The copy key's profile sits behind it, and would ring if it were found
    // first.
    expect(meeting.lookupKeys, [meeting.key, copyKey]);
    await overrides.save(
      EventOverride(
        scope: OverrideScope.occurrence,
        target: meeting.key,
        enabled: false,
      ),
    );
    await overrides.save(
      EventOverride(
        scope: OverrideScope.occurrence,
        target: copyKey,
        profileId: BuiltInProfiles.meetingId,
      ),
    );
    await c.reload();
    expect(onlyItem(c).on, isFalse);
    expect(onlyItem(c).resolved.explanation, 'Off · this event');

    await c.setOn(onlyItem(c), true);

    // Without the override the meeting stays off, so `enabled: true` is what
    // gets written, on the meeting key alone. Reading the keys in another
    // order finds the copy key's profile first, takes it for what the meeting
    // does by itself, writes nothing and leaves the meeting off.
    expect(
      await overrides.find(OverrideScope.occurrence, meeting.key),
      EventOverride(
        scope: OverrideScope.occurrence,
        target: meeting.key,
        enabled: true,
      ),
    );
    expect(await overrides.find(OverrideScope.occurrence, copyKey), isNull);
    expect(await overrides.all(), hasLength(1));
    await c.reload();
    expect(onlyItem(c).on, isTrue);
  });

  test('a toggle that cannot be written asks for no re-plan and says so to '
      'its caller', () async {
    await seed(feed, [feedOcc('sprint', local(6, 10))]);
    final c = AgendaController(
      loader: loader,
      db: db,
      overrides: _FailingOverrides(db),
      settings: settings,
      rulesEngine: rulesEngine,
      replan: replan,
      runSync: (t) async => SyncReport(trigger: t, outcome: SyncRunOutcome.ok),
      tick: const Duration(hours: 1),
      debounce: Duration.zero,
    );
    addTearDown(c.dispose);
    await c.reload();

    await expectLater(c.setOn(onlyItem(c), false), throwsStateError);

    await replan.flush();
    expect(replans, 0);
  });

  test(
    'an older load that finishes late never replaces a newer snapshot',
    () async {
      final sprint = feedOcc('sprint', local(6, 10));
      await seed(feed, [sprint]);
      final gated = _GatedLoader(loader)..hold = true;
      final c = controllerFor(gated);

      // The first load reads the meeting while it is on, and is held.
      final first = c.reload();
      await gated.reading[0].future;
      await overrides.save(
        EventOverride(
          scope: OverrideScope.occurrence,
          target: sprint.key,
          enabled: false,
        ),
      );
      // The second reads it switched off, and finishes first.
      final second = c.reload();
      await gated.reading[1].future;
      gated.gates[1].complete();
      await second;
      expect(onlyItem(c).on, isFalse);

      gated.gates[0].complete();
      await first;

      expect(onlyItem(c).on, isFalse);
    },
  );

  test('a load that throws shows as failed and logs only the error type, and '
      'the next load clears it', () async {
    await seed(feed, [feedOcc('sprint', local(6, 10))]);
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);
    final gated = _GatedLoader(loader)
      ..failWith = StateError('could not read https://example.test/secret.ics');
    final c = controllerFor(gated);
    var told = 0;
    c.addListener(() => told++);

    await c.reload();

    expect(c.failed, isTrue);
    expect(c.snapshot, isNull);
    expect(told, 1);
    expect(logged, hasLength(1));
    expect(logged.single, contains('StateError'));
    expect(logged.single, isNot(contains('secret')));
    expect(logged.single, isNot(contains('example.test')));

    gated.failWith = null;
    await c.reload();

    expect(c.failed, isFalse);
    expect(c.snapshot, isNotNull);
  });

  test('a load that finishes after dispose tells nobody', () async {
    await seed(feed, [feedOcc('sprint', local(6, 10))]);
    final gated = _GatedLoader(loader)..hold = true;
    final c = controllerFor(gated);
    var told = 0;
    c.addListener(() => told++);
    final pending = c.reload();
    await gated.reading[0].future;

    c.dispose();
    gated.gates[0].complete();
    // Notifying a disposed ChangeNotifier throws.
    await pending;

    expect(told, 0);
  });
}
