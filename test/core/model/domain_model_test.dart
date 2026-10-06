import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/model/source_config.dart';

import '../fixtures.dart';

void main() {
  group('EventOccurrence', () {
    test('makeKey uses the UTC ISO original start', () {
      final local = DateTime.utc(2026, 10, 6, 8).toLocal();
      expect(
        EventOccurrence.makeKey('work', 'abc', local),
        'work|abc|2026-10-06T08:00:00.000Z',
      );
    });

    test('key survives a move because it uses the original start', () {
      final o = occ(start: DateTime.utc(2026, 10, 6, 8));
      final moved = o.copyWith(
        startUtc: DateTime.utc(2026, 10, 6, 9),
        endUtc: DateTime.utc(2026, 10, 6, 9, 30),
      );
      expect(moved.key, o.key);
      expect(moved.startUtc, DateTime.utc(2026, 10, 6, 9));
      expect(moved, isNot(o));
    });

    test('a TZDateTime input equals the same plain UTC instant', () {
      final zoned = tz.TZDateTime(johannesburg, 2026, 10, 6, 10);
      final a = occ(start: zoned);
      final b = occ(start: DateTime.utc(2026, 10, 6, 8));
      expect(a.startUtc, isNot(isA<tz.TZDateTime>()));
      expect(a, b);
      expect(a.key, b.key);
    });

    test('normalises every instant to UTC', () {
      final o = occ(start: DateTime.utc(2026, 10, 6, 8).toLocal());
      expect(o.startUtc.isUtc, isTrue);
      expect(o.endUtc.isUtc, isTrue);
      expect(o.originalStartUtc.isUtc, isTrue);
    });
  });

  group('SourceSyncState (decision 25)', () {
    test('TZDateTime instants equal the same plain UTC instants', () {
      final utc = DateTime.utc(2026, 10, 6, 8);
      final zoned = tz.TZDateTime.from(utc, johannesburg);
      final a = SourceSyncState(lastAttemptUtc: zoned, lastSuccessUtc: zoned);
      final b = SourceSyncState(lastAttemptUtc: utc, lastSuccessUtc: utc);
      expect(a.lastAttemptUtc, isNot(isA<tz.TZDateTime>()));
      expect(a.lastSuccessUtc, isNot(isA<tz.TZDateTime>()));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('BuiltInProfiles (spec §6)', () {
    test('ids, names and order', () {
      expect(BuiltInProfiles.all.map((p) => p.id), [
        'meeting',
        'quick',
        'important',
        'silent',
      ]);
      expect(BuiltInProfiles.all.map((p) => p.name), [
        'Meeting',
        'Quick',
        'Important',
        'Silent',
      ]);
      expect(BuiltInProfiles.all.every((p) => p.builtIn), isTrue);
      expect(BuiltInProfiles.defaultId, 'meeting');
    });

    test('alerts and ringsInQuietMode', () {
      expect(BuiltInProfiles.meeting.alerts, const [
        AlertSpec(10, AlertStrength.headsUp),
        AlertSpec(1, AlertStrength.alarm),
      ]);
      expect(BuiltInProfiles.quick.alerts, const [
        AlertSpec(1, AlertStrength.alarm),
      ]);
      expect(BuiltInProfiles.important.alerts, const [
        AlertSpec(30, AlertStrength.headsUp),
        AlertSpec(10, AlertStrength.headsUp),
        AlertSpec(2, AlertStrength.alarm),
      ]);
      expect(BuiltInProfiles.silent.alerts, isEmpty);
      expect(BuiltInProfiles.important.ringsInQuietMode, isTrue);
      expect(BuiltInProfiles.meeting.ringsInQuietMode, isFalse);
      expect(BuiltInProfiles.quick.ringsInQuietMode, isFalse);
      expect(
        BuiltInProfiles.meeting.sound.ringTimeout,
        const Duration(minutes: 2),
      );
    });
  });

  test('alert list JSON round trip', () {
    const alerts = [
      AlertSpec(30, AlertStrength.headsUp),
      AlertSpec(0, AlertStrength.alarm),
    ];
    final json = jsonDecode(jsonEncode(alertsToJson(alerts))) as List<Object?>;
    expect(json.first, {'offsetMinutes': 30, 'strength': 'headsUp'});
    expect(alertsFromJson(json), alerts);
  });

  group('EventOverride', () {
    test('isEmpty only when nothing is set', () {
      const empty = EventOverride(scope: OverrideScope.occurrence, target: 'k');
      expect(empty.isEmpty, isTrue);
      expect(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k',
          enabled: false,
        ).isEmpty,
        isFalse,
      );
    });

    test('equality compares custom alerts element-wise', () {
      const a = EventOverride(
        scope: OverrideScope.series,
        target: 's',
        customAlerts: [AlertSpec(5, AlertStrength.alarm)],
      );
      const b = EventOverride(
        scope: OverrideScope.series,
        target: 's',
        customAlerts: [AlertSpec(5, AlertStrength.alarm)],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SkipFilters', () {
    test('all default to on', () {
      expect(const SkipFilters().toJson().values, everyElement(isTrue));
    });

    test('JSON round trip, and missing keys default to on', () {
      const f = SkipFilters(free: false, declined: false);
      expect(SkipFilters.fromJson(f.toJson()), f);
      expect(
        SkipFilters.fromJson(const {'free': false}),
        const SkipFilters(free: false),
      );
    });
  });
}
