import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/planner/meeting_planner.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/meeting_link_repository.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_service.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

void main() {
  late AppDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;
  late SettingsRepository settings;
  late MeetingPlanner planner;
  final now = DateTime.utc(2026, 10, 6, 6);

  const feed = SourceConfig(
    id: 'feed',
    name: 'Work feed',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.feed',
  );
  const phone = SourceConfig(
    id: 'phone',
    name: 'Outlook (phone)',
    color: blue,
    kind: SourceKind.device,
    deviceCalendarId: '7',
  );

  Future<MeetingPlan> load() => planner.load(
    now: now,
    fromUtc: now.subtract(const Duration(minutes: 15)),
    toUtc: now.add(const Duration(days: 7)),
  );

  setUp(() async {
    initZones();
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    settings = SettingsRepository(db);
    planner = MeetingPlanner(
      sources: sources,
      occurrences: cache,
      links: MeetingLinkRepository(db),
      history: AlertHistoryRepository(db),
      settings: settings,
      ruleSets: RuleSetLoader(
        profiles: ProfileRepository(db),
        rules: RuleRepository(db),
        overrides: OverrideRepository(db),
        settings: settings,
        sources: sources,
      ),
      rulesEngine: () => RulesEngine(zone: johannesburg, clock: () => now),
    );
    await sources.save(feed);
    await sources.save(phone);
    await cache.replaceForSource('feed', [occ(sourceId: 'feed', uid: 'F1')]);
    await cache.replaceForSource('phone', [occ(sourceId: 'phone', uid: '42')]);
  });

  tearDown(() => db.close());

  test('one resolved entry per meeting, in merge order', () async {
    final p = await load();
    expect(p.merge.meetings, hasLength(1)); // same title and start: merged
    expect(
      p.resolved.map((r) => r.occurrence.key),
      p.merge.meetings.map((m) => m.key),
    );
    expect(p.alerts.map((a) => a.occurrenceKey).toSet(), {
      p.merge.meetings.single.key,
    });
  });

  test('with merge.enabled false both copies are planned', () async {
    await settings.setString(SyncService.mergeEnabledKey, 'false');
    final p = await load();
    expect(p.merge.meetings, hasLength(2));
    expect(p.alerts.map((a) => a.occurrenceKey).toSet(), hasLength(2));
  });

  test('disabled sources are left out', () async {
    await sources.save(phone.copyWith(enabled: false));
    final p = await load();
    expect(p.sources.keys, ['feed']);
    expect(p.merge.meetings.single.sourceId, 'feed');
  });

  test('a failing source ranks below a healthy one', () async {
    final ranks = sourceRanks(
      [feed, phone],
      {
        'feed': null,
        'phone': SourceSyncState(lastError: 'Calendar access was turned off.'),
      },
    );
    expect(ranks['phone']!.failing, isTrue);
    expect(ranks['feed']!.failing, isFalse);
  });

  test('load writes no links', () async {
    final p = await load();
    // The two copies merged, so there are links the sync would store ...
    expect(p.merge.upsert, isNotEmpty);
    // ... and the planner, which the Agenda uses read-only, stored none.
    expect(await MeetingLinkRepository(db).all(), isEmpty);
  });
}
