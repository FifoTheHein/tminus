import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/app/di.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/planner/plan_builder.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/source_repository.dart';

import '../core/fixtures.dart';
import '../core/storage/test_database.dart';

void main() {
  tearDown(getIt.reset);

  test('nothing opens the database until it is asked for', () async {
    var opened = 0;
    configureDependencies(
      openDatabase: () {
        opened++;
        return openTestDatabase();
      },
    );
    expect(opened, 0);
    getIt<SourceRepository>();
    getIt<SourceRepository>();
    expect(opened, 1);
  });

  test('configureDependencies registers one AlarmEngine', () {
    configureDependencies(openDatabase: openTestDatabase);
    expect(getIt<AlarmEngine>(), same(getIt<AlarmEngine>()));
  });

  test('configureDependencies loads the time zone database', () {
    configureDependencies(openDatabase: openTestDatabase);
    expect(tz.timeZoneDatabase.isInitialized, isTrue);
    expect(getIt<RulesEngine>().zone, tz.local);
  });

  test('database → rules → plan, end to end', () async {
    configureDependencies(openDatabase: openTestDatabase);
    final now = DateTime.utc(2026, 10, 6, 6);

    await getIt<SourceRepository>().save(
      const SourceConfig(
        id: 'work',
        name: 'Work',
        color: blue,
        kind: SourceKind.ics,
        secureStorageKey: 'ics_url_work',
        defaultProfileId: 'important',
      ),
    );
    await getIt<RuleRepository>().save(
      KeywordRule(
        id: 'r1',
        position: 0,
        field: RuleField.title,
        pattern: 'standup',
        profileId: 'quick',
      ),
    );
    final standup = occ(
      uid: 'standup',
      title: 'Daily standup',
      start: DateTime.utc(2026, 10, 6, 6, 45),
    );
    final demo = occ(
      uid: 'demo',
      title: 'Client demo',
      start: DateTime.utc(2026, 10, 6, 12),
    );
    final tentative = occ(
      uid: 'talk',
      title: 'Tech talk',
      start: DateTime.utc(2026, 10, 6, 14),
      busyStatus: BusyStatus.tentative,
    );
    await getIt<OccurrenceRepository>().replaceForSource('work', [
      standup,
      demo,
      tentative,
    ]);
    await getIt<AlertHistoryRepository>().record(
      AlertHistoryEntry(
        type: AlertEventType.dismissed,
        alertId: PlannedAlert.idFor(demo.key, 30),
        occurrenceKey: demo.key,
        startUtc: demo.startUtc,
        atUtc: now,
      ),
    );

    final rules = await getIt<RuleSetLoader>().load();
    final engine = RulesEngine(zone: johannesburg, clock: () => now);
    final cached = await getIt<OccurrenceRepository>().between(
      now.subtract(const Duration(hours: 1)),
      now.add(const Duration(days: 7)),
    );
    final resolved = engine.resolveAll(cached, rules);
    final plan = buildPlan(
      resolved,
      now: now,
      acknowledgements: await getIt<AlertHistoryRepository>().acknowledgements(
        nowUtc: now,
      ),
    );

    expect(resolved.map((r) => r.explanation), [
      'Quick · rule: "standup"',
      'Important · source default',
      'Silent · tentative',
    ]);
    expect(plan.map((a) => (a.occurrenceKey, a.offsetMinutes)), [
      (standup.key, 1),
      (demo.key, 10),
      (demo.key, 2),
    ]);
  });
}
