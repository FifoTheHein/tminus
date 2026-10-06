# Plan 2: Domain, Storage, Rules and Planner Implementation Plan

> **Execution (decided 2026-10-06): subagent-driven, using the orchestrator pattern.** Do not execute this plan inline. Run `/orchestrate` in plan mode on this plan to produce an orchestration plan (workers: `dev-worker`, `review-worker`, `deep-review`, `scout`), then run that orchestration plan with `/orchestrate <path>` in a fresh session. Each task here becomes one or more orchestrator jobs; its code and tests are the job's brief content. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build T-Minus's pure-Dart core: the domain model, the drift database, profile resolution with quiet modes and explanations, and the planner that turns resolved occurrences into the `PlannedAlert` list the native engine arms.

**Architecture:** Plain immutable model classes in `lib/core/model`. A stateless `RulesEngine` (zone and clock injected) resolves each `EventOccurrence` against a `RuleSet` snapshot. A pure `buildPlan()` turns the results into `PlannedAlert`s. Drift stores everything in `lib/core/storage`, behind small repositories that map rows to domain objects. `RuleSetLoader` builds the `RuleSet` from storage. All of it is registered lazily in `get_it`. No UI, no network, no platform channel.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `timezone` 0.11.1, `drift` 2.35.1 + `drift_dev` 2.35.1 + `build_runner` 2.16.1, `sqlite3` 3.7.0 (it bundles SQLite through Dart build hooks), `drift_flutter` 0.3.1, `get_it` 9.3.

**Spec:** `docs/superpowers/specs/2026-10-06-tminus-design.md` (§5 data model, §6 rules/profiles/quiet modes/explainability/alarm behaviour, §9 empty-feed rule, §11 testing). **Binding contracts:** `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` §3 (shared files and engine rules) and §4 (domain summary). **Copy:** `docs/design-brief.md` (Agenda reason lines, Alerts tab, quiet modes).

## Global Constraints

- Dart SDK `^3.13.0` (pubspec), Flutter stable 3.47. Run every command from the repo root `C:\Projects\tminus` in **Git Bash**.
- Scope: `lib/core/model`, `lib/core/storage`, `lib/core/rules`, `lib/core/planner`, plus registration in `lib/app/di.dart`. No widgets, no HTTP, no `MethodChannel`.
- `lib/core/model/alert.dart` and `lib/core/model/planned_alert.dart` are **byte-for-byte** roadmap §3. Never edit them, and **never run `dart format` on them** (their long lines would be rewrapped). Run `dart format` only on the files a task lists, never on `lib/` as a whole.
- Built-in profile ids are exactly `meeting`, `quick`, `important`, `silent` (roadmap §4). Alerts per spec §6: Meeting = headsUp 10, alarm 1. Quick = alarm 1. Important = headsUp 30, headsUp 10, alarm 2, `ringsInQuietMode: true`. Silent = none.
- Explanation strings are exactly roadmap §4: `<Profile name> · <reason>` with U+00B7 MIDDLE DOT between single spaces. Reasons are `this event`, `series`, `all-day`, `free`, `tentative`, `cancelled`, `declined`, `rule: "<pattern>"`, `source default` and `default`. Other forms are `Off · this event`, `Silenced · Mute today`, `Silenced · Paused until HH:mm` (local time; with the day when the pause doesn't end today, decision 22) and `Silenced · Vacation`.
- Occurrence key = `'$sourceId|$uid|${originalStartUtc.toUtc().toIso8601String()}'`.
- Skip filters default to on (roadmap §5.3).
- The plan lists **every alert of an occurrence until the occurrence ends** (`endUtc > now`), including alerts whose `fireAtUtc` has passed. Kotlin never arms past alerts, but an `occurrenceKey` missing from the plan tells Kotlin the meeting is gone, and it then drops that occurrence's snoozes (roadmap §3 "Engine rules"). Ended occurrences are dropped entirely.
- The drift database never stores an ICS URL. Sources keep only a `secureStorageKey` (spec §3, §10).
- Instants are stored as INTEGER UTC milliseconds (`…UtcMs` columns). Model constructors normalise every `DateTime` with `plainUtc()`.
- `flutter analyze` reports "No issues found!" and `flutter test` passes at the end of every task.
- Code generation: `dart run build_runner build`. build_runner 2.16 removed `--delete-conflicting-outputs`. Passing it only prints "These options have been removed and were ignored", so leave it out.
- Generated `*.g.dart` files **are committed**, for three reasons. A fresh checkout (or Plan 4's headless sync build, or CI) then analyses and tests without a 1–3 minute codegen step. Schema changes show up in review as a diff of `app_database.g.dart`. And a later `drift_dev` upgrade cannot silently change the generated schema code without anyone seeing it.
- Commits use the repo's style (short imperative sentence) and end with the trailer `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Two alerts with the same offset in one profile** (e.g. a user adds headsUp −5 and alarm −5). Both would get the same `PlannedAlert.id`, and the engine would drop one at random. Expected: one alert per offset, and the alarm wins. Pinned in Task 7 ("duplicate offsets collapse…").
2. **A `TZDateTime` reaching the model** (Plan 4 builds times with `package:timezone`). `TZDateTime.toUtc()` returns another `TZDateTime`, which never `==` a plain `DateTime`, so equality and map keys would silently break. Expected: model constructors normalise to plain UTC. Pinned in Task 2 and Task 4.
3. **A profile is deleted while something still references it** (a rule, an override, a source default, the global default). Expected: resolution never crashes and falls through to the next step, and deletion cleans up the references. Pinned in Task 5 (deleted-profile cases) and Task 11 ("deleting a profile removes every reference").
4. **Stored settings that can't be read** (a vacation row with no dates, skip-filter JSON written by an older build with missing keys). Expected: these read as "no quiet mode" and "filter on", never as an exception inside the sync. Pinned in Task 2 and Task 11.
5. **The same engine event delivered twice** (live over the EventChannel, then again from `drainEvents`). Expected: one `alert_history` row. Pinned in Task 12 ("record de-duplicates").

## Decisions this plan makes (the spec is silent; flagged for review)

1. **Quiet modes judge an occurrence by its start.** Mute/Pause covers an occurrence when the mode has not ended yet (`now < until`) and the occurrence starts before `until`. A meeting starting exactly at `until` is outside the mode, so its heads-up still rings. Vacation covers occurrences whose start falls on a local date in `[firstDay, lastDay]`. Quiet modes only change occurrences that would have rung, so `Silent · tentative` and `Off · this event` keep their own explanation.
2. **An override with `enabled: true` and no profile** (the Agenda toggle switched on) skips the skip filters. It takes the first of these that has alerts: matching rules, then the source default, then the global default, then Meeting. Its explanation is `<that profile> · this event`. Without this, toggling on a tentative event would do nothing.
3. **Custom alerts without a profile** read `Custom · this event` (or `Custom · series`). The sound and `ringsInQuietMode` come from the profile the lower steps would pick.
4. **A series override with `enabled: false`** reads `Off · series`. Roadmap §4 only names the occurrence form.
5. **A `hasJoinLink` rule** reads `<Profile> · rule: Teams link`, because the pattern is ignored for that field.
6. **An empty pattern never matches** for text fields. Otherwise a half-typed rule would capture every event.
7. **Unknown profile ids are skipped, never fatal.** An override, rule or source default naming a deleted profile is treated as no match. An unknown global default falls back to Meeting.
8. **Single-Dismiss acknowledgements are keyed by `(alertId, occurrence startUtc)` in Dart**, not `(alertId, fireAtUtc)`. EngineEvent JSON (roadmap §3) has `startUtcMs` but no fire time. The pairs are equivalent: the id fixes the offset, and fireAt = start − offset. Acknowledgements older than start + 24 h are ignored, matching Kotlin's pruning.
9. **`EventOverride`, not `Override`**, so the class never reads like the `@override` annotation.
10. **Profile alerts are stored as JSON in `profiles.alerts_json`, not in a child table.** They are always read and written as a whole and never queried on their own, and their order is just list order. The same encoding serves `overrides.custom_alerts_json`.
11. **Settings live in a key/value `settings` table** (skip filters as JSON, global default id; Plan 5 adds the theme mode). The quiet mode has its own one-row `quiet_state` table, as spec §5 lists it.
12. **`sources` also stores sync bookkeeping** (`last_attempt_utc_ms`, `last_success_utc_ms`, `last_error`, `http_etag`, `http_last_modified`, `empty_streak`). Plan 4 needs these, and having them now means schema 1 needs no migration for them.
13. **Spec §11 "snooze options in the past are hidden"** is not in this plan. The options are computed by Kotlin's alarm screen (Plan 3), and Plan 2 has no snooze code.

**Accepted after the post-implementation deep review (2026-10-06):**

14. **Concurrent connections wait instead of failing.** `AppDatabase` sets `PRAGMA busy_timeout = 5000` and `PRAGMA journal_mode = WAL` on every connection, so the UI isolate and Plan 4's headless sync isolate can both write. `AlertHistoryRepository.record` uses `INSERT OR IGNORE` on the de-dup key, so a concurrent duplicate returns `false` instead of throwing.
15. **Stored rows that can't be read are skipped, never fatal.** A profile whose `alerts_json` can't be decoded (bad JSON, unknown strength, negative offset) is left out of the `RuleSet` unless its id is built in, in which case the built-in definition is used. An override whose `custom_alerts_json` can't be decoded is skipped. Resolution then falls through as for a deleted profile (decision 7). Skip-filter JSON that can't be read reads as all filters on, and an unknown quiet `kind` reads as no quiet mode.
16. **Silent never has alerts.** `ProfileRepository.save` stores `silent` with no alerts, and the rules engine treats Silent as having no alerts even if a stored row says otherwise (spec §6).
17. **An empty custom-alert list means no custom alerts.** An override whose `customAlerts` is `[]` behaves as if it had none: its profile (or the lower steps) decides, and the explanation never reads `Custom · …` with nothing to ring.
18. **Duplicate offsets collapse in the engine too.** `ResolvedOccurrence.alerts` keeps one alert per offset, and the alarm wins (the same rule as `buildPlan`, Review Focus 1), so the Agenda and Event detail list exactly what is planned.
19. **Occurrences stay in the plan until 15 minutes after they end.** `buildPlan` keeps an occurrence while `max(end, start) + 15 min > now`. Past alerts are still listed but never armed. This keeps snoozes alive for events with no duration (no DTEND) and for snoozes that run past the end.
20. **Impossible dates are rejected.** `LocalDate.parse` throws `FormatException` when the parsed date doesn't round-trip (e.g. `2026-13-45`, `2026-02-30`), so a corrupt vacation row reads as no quiet mode.
21. **Mute today keeps the spec's literal rule.** It always ends at 07:00 on the next local calendar day, even when set after midnight.
22. **The pause label says the day when the pause doesn't end today.** `Paused until 14:00` when it ends today (local), `Paused until Wed 09:00` when it ends within the next 6 local days, and `Paused until 14 Oct 09:00` beyond that. English names, no `intl`. Roadmap §4 is updated to match.
23. **`Vacation.isActive` stays "not ended yet".** It is true before `firstDay`, so nothing clears a scheduled vacation. Plan 5's banner copy handles the not-started case (e.g. "Vacation from 1 Dec").
24. **A re-delivered engine event keeps the first row.** `record` de-duplicates on the event's identity, and a later copy with different field values is ignored. Roadmap §3 delivers identical duplicates.
25. **Instants are normalised to whole milliseconds.** `plainUtc()` truncates sub-millisecond parts so an occurrence key is the same before and after a database round trip. `SourceSyncState` normalises its instants like every other model class.

## File Structure

```
lib/core/model/
  alert.dart                 contract (roadmap §3): AlertStrength, AlertSpec, SoundSettings
  planned_alert.dart         contract (roadmap §3): EventSnapshot, PlannedAlert, idFor, groupFor
  utc.dart                   plainUtc(): normalise any DateTime/TZDateTime to plain UTC
  event_occurrence.dart      BusyStatus, OccurrenceWarning, EventOccurrence (+ makeKey)
  alert_profile.dart         AlertProfile, BuiltInProfiles, alertsToJson/alertsFromJson, sameAlerts
  event_override.dart        OverrideScope, EventOverride
  skip_filters.dart          SkipFilters (+ JSON)
  source_config.dart         SourceKind, SourceConfig, SourceSyncState
  keyword_rule.dart          RuleField, RuleMatch, KeywordRule.matches
  local_date.dart            LocalDate (vacation days)
  quiet_state.dart           sealed QuietState: QuietNone | MuteToday | PausedUntil | Vacation
  alert_history_entry.dart   AlertEventType, AlertHistoryEntry
  sync_log_entry.dart        SyncOutcome, SyncLogEntry
lib/core/rules/
  rule_set.dart              RuleSet: profiles, overrides, rules, filters, defaults, quiet
  resolved_occurrence.dart   ResolutionStep, ResolvedOccurrence
  rules_engine.dart          RulesEngine.resolve / resolveAll, UtcClock
lib/core/planner/
  acknowledgements.dart      Acknowledgements (Dismiss all / Join / Dismiss)
  plan_builder.dart          buildPlan()
  empty_feed_guard.dart      EmptyFeedGuard.evaluate, EmptyFeedVerdict
lib/core/storage/
  tables.dart                drift tables (schema 1)
  app_database.dart          AppDatabase, MigrationStrategy, seeding
  app_database.g.dart        generated, committed
  profile_mapping.dart       profile row <-> domain
  source_repository.dart     sources + sync state
  occurrence_repository.dart occurrence cache
  profile_repository.dart    profiles (+ reference clean-up on delete)
  rule_repository.dart       keyword rules (+ reorder)
  override_repository.dart   overrides (+ Agenda toggle helper)
  settings_repository.dart   skip filters, global default, quiet state, strings
  alert_history_repository.dart  history, de-dup, acknowledgements()
  sync_log_repository.dart   sync log
  rule_set_loader.dart       RuleSetLoader.load() -> RuleSet
lib/app/di.dart              modified: lazy registration of all of the above
test/core/fixtures.dart      zones + occ() factory
test/core/model/*_test.dart, test/core/rules/*, test/core/planner/*, test/core/storage/*, test/app/di_test.dart
```

---

### Task 1: Shared contract files and their tests

**Files:**
- Create (or verify): `lib/core/model/alert.dart`, `lib/core/model/planned_alert.dart`
- Test: `test/core/model/planned_alert_contract_test.dart`

**Interfaces:**
- Consumes: roadmap §3 text.
- Produces: `AlertStrength {headsUp, alarm}`, `AlertSpec(int offsetMinutes, AlertStrength strength)`, `SoundSettings({String? toneUri, bool vibrate, bool gradualVolume, Duration ringTimeout})` with `toJson/fromJson`, `EventSnapshot({title, startUtc, endUtc, location?, joinUrl?, required int color})`, `PlannedAlert({id, occurrenceKey, fireAtUtc, offsetMinutes, strength, sound, event, coalesceGroup})`, `static String PlannedAlert.idFor(String occurrenceKey, int offsetMinutes)`, `static String PlannedAlert.groupFor(DateTime fireAtUtc)`, `toJson()/fromJson()`.

- [ ] **Step 1: Write the failing contract test**

The two hash values were checked against an independent FNV-1a 64-bit implementation. Plan 3 uses the same values.

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/planned_alert.dart';

void main() {
  group('PlannedAlert.idFor', () {
    test('matches known FNV-1a values (shared with Plan 3)', () {
      expect(PlannedAlert.idFor('a', 10), '0eee2d83f9209539');
      expect(
        PlannedAlert.idFor('src|uid1|2026-10-06T08:00:00.000Z', 10),
        '88116ba1896be5a4',
      );
    });

    test('is stable across calls', () {
      const key = 'work|abc|2026-10-06T08:00:00.000Z';
      expect(PlannedAlert.idFor(key, 1), PlannedAlert.idFor(key, 1));
    });

    test('differs for different offsets and keys', () {
      const key = 'work|abc|2026-10-06T08:00:00.000Z';
      final ids = {
        PlannedAlert.idFor(key, 0),
        PlannedAlert.idFor(key, 1),
        PlannedAlert.idFor(key, 10),
        PlannedAlert.idFor('work|abd|2026-10-06T08:00:00.000Z', 1),
      };
      expect(ids, hasLength(4));
    });

    test('is always 16 lowercase hex chars, never signed', () {
      final hex = RegExp(r'^[0-9a-f]{16}$');
      for (var i = 0; i < 500; i++) {
        final id = PlannedAlert.idFor('k$i', i % 60);
        expect(id, matches(hex), reason: 'k$i');
      }
    });
  });

  group('PlannedAlert.groupFor', () {
    test('formats the UTC minute', () {
      expect(
        PlannedAlert.groupFor(DateTime.utc(2026, 3, 9, 7, 5, 59)),
        '2026-03-09T07:05Z',
      );
    });

    test('converts local times to UTC first', () {
      final local = DateTime.utc(2026, 10, 6, 7, 59).toLocal();
      expect(PlannedAlert.groupFor(local), '2026-10-06T07:59Z');
    });

    test('same minute, same group; next minute, new group', () {
      final a = PlannedAlert.groupFor(DateTime.utc(2026, 10, 6, 8, 0, 0));
      final b = PlannedAlert.groupFor(DateTime.utc(2026, 10, 6, 8, 0, 59, 999));
      final c = PlannedAlert.groupFor(DateTime.utc(2026, 10, 6, 8, 1));
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  test('toJson/fromJson round trip survives jsonEncode', () {
    final start = DateTime.utc(2026, 10, 6, 8);
    const key = 'work|abc|2026-10-06T08:00:00.000Z';
    final fireAt = start.subtract(const Duration(minutes: 10));
    final alert = PlannedAlert(
      id: PlannedAlert.idFor(key, 10),
      occurrenceKey: key,
      fireAtUtc: fireAt,
      offsetMinutes: 10,
      strength: AlertStrength.headsUp,
      sound: const SoundSettings(
        toneUri: 'content://tone/1',
        vibrate: false,
        ringTimeout: Duration(seconds: 90),
      ),
      event: EventSnapshot(
        title: 'Sprint planning',
        startUtc: start,
        endUtc: start.add(const Duration(hours: 1)),
        location: 'Teams',
        joinUrl: 'https://teams.microsoft.com/l/meetup-join/x',
        color: 0xFF6AA0F5,
      ),
      coalesceGroup: PlannedAlert.groupFor(fireAt),
    );

    final json = jsonDecode(jsonEncode(alert.toJson())) as Map<String, Object?>;
    final back = PlannedAlert.fromJson(json);

    expect(json['strength'], 'headsUp');
    expect(back.id, alert.id);
    expect(back.occurrenceKey, key);
    expect(back.fireAtUtc, fireAt);
    expect(back.fireAtUtc.isUtc, isTrue);
    expect(back.offsetMinutes, 10);
    expect(back.strength, AlertStrength.headsUp);
    expect(back.sound, alert.sound);
    expect(back.event.title, 'Sprint planning');
    expect(back.event.startUtc, start);
    expect(back.event.endUtc, start.add(const Duration(hours: 1)));
    expect(back.event.location, 'Teams');
    expect(back.event.joinUrl, 'https://teams.microsoft.com/l/meetup-join/x');
    expect(back.event.color, 0xFF6AA0F5);
    expect(back.coalesceGroup, '2026-10-06T07:50Z');
    expect(back.toJson(), alert.toJson());
  });
}
```

- [ ] **Step 2: Run it to make sure it fails (unless Plan 3 already created the files)**

Run: `flutter test test/core/model/planned_alert_contract_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/model/alert.dart'" (or `planned_alert.dart`). If both files already exist (Plan 3 ran first), the test may already pass. Go to Step 3 anyway.

- [ ] **Step 3: Create the files from the roadmap, or verify the existing ones byte-for-byte**

If the files do not exist, extract them straight from the roadmap so there is no retyping:

```bash
R=docs/superpowers/plans/2026-10-06-tminus-roadmap.md
mkdir -p lib/core/model
[ -f lib/core/model/alert.dart ] || awk '/^### `lib\/core\/model\/alert.dart`/{f=1;next} f&&/^```dart/{p=1;next} p&&/^```$/{exit} p' $R > lib/core/model/alert.dart
[ -f lib/core/model/planned_alert.dart ] || awk '/^### `lib\/core\/model\/planned_alert.dart`/{f=1;next} f&&/^```dart/{p=1;next} p&&/^```$/{exit} p' $R > lib/core/model/planned_alert.dart
```

Then verify both (this also covers files Plan 3 created):

```bash
R=docs/superpowers/plans/2026-10-06-tminus-roadmap.md
awk '/^### `lib\/core\/model\/alert.dart`/{f=1;next} f&&/^```dart/{p=1;next} p&&/^```$/{exit} p' $R | diff --strip-trailing-cr - lib/core/model/alert.dart && echo "alert.dart SAME"
awk '/^### `lib\/core\/model\/planned_alert.dart`/{f=1;next} f&&/^```dart/{p=1;next} p&&/^```$/{exit} p' $R | diff --strip-trailing-cr - lib/core/model/planned_alert.dart && echo "planned_alert.dart SAME"
```

Expected: `alert.dart SAME` and `planned_alert.dart SAME`. If a diff appears in a file Plan 3 created, **do not edit it**. Stop and report the diff, because the roadmap is the contract. (Make sure the `idFor` body is the corrected one using `hex32(hash >> 32) + hex32(hash)`. An older roadmap draft used `toUnsigned(64)`, which printed negative ids such as `-77ee945e76941a5c`.)

For reference, the resulting files are:

```dart
enum AlertStrength { headsUp, alarm }

class AlertSpec {
  const AlertSpec(this.offsetMinutes, this.strength) : assert(offsetMinutes >= 0);
  final int offsetMinutes; // minutes before start
  final AlertStrength strength;

  @override
  bool operator ==(Object other) =>
      other is AlertSpec && other.offsetMinutes == offsetMinutes && other.strength == strength;
  @override
  int get hashCode => Object.hash(offsetMinutes, strength);
}

class SoundSettings {
  const SoundSettings({
    this.toneUri,
    this.vibrate = true,
    this.gradualVolume = true,
    this.ringTimeout = const Duration(minutes: 2),
  });
  final String? toneUri; // null = system default alarm tone
  final bool vibrate;
  final bool gradualVolume;
  final Duration ringTimeout;

  Map<String, Object?> toJson() => {
        'toneUri': toneUri,
        'vibrate': vibrate,
        'gradualVolume': gradualVolume,
        'ringTimeoutSec': ringTimeout.inSeconds,
      };

  factory SoundSettings.fromJson(Map<String, Object?> j) => SoundSettings(
        toneUri: j['toneUri'] as String?,
        vibrate: j['vibrate'] as bool,
        gradualVolume: j['gradualVolume'] as bool,
        ringTimeout: Duration(seconds: j['ringTimeoutSec'] as int),
      );

  @override
  bool operator ==(Object other) =>
      other is SoundSettings &&
      other.toneUri == toneUri &&
      other.vibrate == vibrate &&
      other.gradualVolume == gradualVolume &&
      other.ringTimeout == ringTimeout;
  @override
  int get hashCode => Object.hash(toneUri, vibrate, gradualVolume, ringTimeout);
}
```

```dart
import 'alert.dart';

/// What the native engine needs to ring and show an alert without Flutter.
class EventSnapshot {
  const EventSnapshot({
    required this.title,
    required this.startUtc,
    required this.endUtc,
    this.location,
    this.joinUrl,
    required this.color,
  });
  final String title;
  final DateTime startUtc;
  final DateTime endUtc;
  final String? location;
  final String? joinUrl;
  final int color; // ARGB, e.g. 0xFF6AA0F5

  Map<String, Object?> toJson() => {
        'title': title,
        'startUtcMs': startUtc.millisecondsSinceEpoch,
        'endUtcMs': endUtc.millisecondsSinceEpoch,
        'location': location,
        'joinUrl': joinUrl,
        'color': color,
      };

  factory EventSnapshot.fromJson(Map<String, Object?> j) => EventSnapshot(
        title: j['title'] as String,
        startUtc: DateTime.fromMillisecondsSinceEpoch(j['startUtcMs'] as int, isUtc: true),
        endUtc: DateTime.fromMillisecondsSinceEpoch(j['endUtcMs'] as int, isUtc: true),
        location: j['location'] as String?,
        joinUrl: j['joinUrl'] as String?,
        color: j['color'] as int,
      );
}

class PlannedAlert {
  const PlannedAlert({
    required this.id,
    required this.occurrenceKey,
    required this.fireAtUtc,
    required this.offsetMinutes,
    required this.strength,
    required this.sound,
    required this.event,
    required this.coalesceGroup,
  });

  final String id;            // PlannedAlert.idFor(occurrenceKey, offsetMinutes)
  final String occurrenceKey;
  final DateTime fireAtUtc;   // event.startUtc - offsetMinutes
  final int offsetMinutes;
  final AlertStrength strength;
  final SoundSettings sound;
  final EventSnapshot event;
  final String coalesceGroup; // PlannedAlert.groupFor(fireAtUtc)

  /// Stable id: FNV-1a 64-bit of "$occurrenceKey|$offsetMinutes", 16 lowercase hex chars.
  static String idFor(String occurrenceKey, int offsetMinutes) {
    var hash = 0xcbf29ce484222325; // 64-bit VM ints wrap on overflow
    for (final unit in '$occurrenceKey|$offsetMinutes'.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    // Print as unsigned: toRadixString on a negative int would emit a '-'.
    String hex32(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return hex32(hash >> 32) + hex32(hash);
  }

  /// Alerts in the same UTC minute share a group: "yyyy-MM-ddTHH:mmZ".
  static String groupFor(DateTime fireAtUtc) {
    final t = fireAtUtc.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}Z';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'occurrenceKey': occurrenceKey,
        'fireAtUtcMs': fireAtUtc.millisecondsSinceEpoch,
        'offsetMinutes': offsetMinutes,
        'strength': strength.name, // "headsUp" | "alarm"
        'sound': sound.toJson(),
        'event': event.toJson(),
        'coalesceGroup': coalesceGroup,
      };

  factory PlannedAlert.fromJson(Map<String, Object?> j) => PlannedAlert(
        id: j['id'] as String,
        occurrenceKey: j['occurrenceKey'] as String,
        fireAtUtc: DateTime.fromMillisecondsSinceEpoch(j['fireAtUtcMs'] as int, isUtc: true),
        offsetMinutes: j['offsetMinutes'] as int,
        strength: AlertStrength.values.byName(j['strength'] as String),
        sound: SoundSettings.fromJson((j['sound'] as Map).cast<String, Object?>()),
        event: EventSnapshot.fromJson((j['event'] as Map).cast<String, Object?>()),
        coalesceGroup: j['coalesceGroup'] as String,
      );
}
```

- [ ] **Step 4: Run the test and analyzer**

Run: `flutter test test/core/model/planned_alert_contract_test.dart && flutter analyze`
Expected: `+8: All tests passed!`, then `No issues found!`

- [ ] **Step 5: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!` (the existing widget and theme tests plus 8 new ones).

- [ ] **Step 6: Commit**

```bash
git add lib/core/model/alert.dart lib/core/model/planned_alert.dart test/core/model/planned_alert_contract_test.dart
git commit -m "Add shared alert and PlannedAlert contract with tests" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

(If Plan 3 already committed the two model files, `git add` just stages the test.)

---

### Task 2: Core domain model (occurrence, profiles, overrides, skip filters, sources)

**Files:**
- Modify: `pubspec.yaml` (add `timezone`)
- Create: `lib/core/model/utc.dart`, `lib/core/model/event_occurrence.dart`, `lib/core/model/alert_profile.dart`, `lib/core/model/event_override.dart`, `lib/core/model/skip_filters.dart`, `lib/core/model/source_config.dart`
- Test: `test/core/fixtures.dart`, `test/core/model/domain_model_test.dart`

**Interfaces:**
- Consumes: `AlertSpec`, `AlertStrength`, `SoundSettings` (Task 1).
- Produces:
  - `DateTime plainUtc(DateTime t)`
  - `enum BusyStatus { free, tentative, busy, oof, unknown }`, `enum OccurrenceWarning { tzFallback }`
  - `EventOccurrence({required String sourceId, required String uid, required DateTime originalStartUtc, String? seriesUid, required String title, String? location, String? organizer, String? description, String? joinUrl, required DateTime startUtc, required DateTime endUtc, bool allDay = false, BusyStatus busyStatus = BusyStatus.unknown, bool declined = false, bool cancelled = false, required int calendarColor, Set<OccurrenceWarning> warnings = const {}})`, `String get key`, `static String makeKey(String sourceId, String uid, DateTime originalStart)`, `copyWith({startUtc, endUtc, title, location, organizer, description, joinUrl, allDay, busyStatus, declined, cancelled, calendarColor, warnings})`, value equality.
  - `AlertProfile({required String id, required String name, required List<AlertSpec> alerts, SoundSettings sound = const SoundSettings(), bool ringsInQuietMode = false, bool builtIn = false})`, `copyWith({name, alerts, sound, ringsInQuietMode})`
  - `BuiltInProfiles.{meetingId, quickId, importantId, silentId, defaultId, meeting, quick, important, silent, all}`
  - `bool sameAlerts(List<AlertSpec>? a, List<AlertSpec>? b)`, `List<Map<String, Object?>> alertsToJson(List<AlertSpec>)`, `List<AlertSpec> alertsFromJson(List<Object?>)`
  - `enum OverrideScope { occurrence, series }`, `EventOverride({required OverrideScope scope, required String target, String? profileId, List<AlertSpec>? customAlerts, bool? enabled})`, `bool get isEmpty`
  - `SkipFilters({allDay, free, tentative, cancelled, declined} = true)`, `copyWith`, `toJson`, `SkipFilters.fromJson`
  - `enum SourceKind { ics, device }`, `SourceConfig({id, name, color, kind, deviceCalendarId?, secureStorageKey?, defaultProfileId?, enabled = true})` with `copyWith(..., clearDefaultProfile)`, `SourceSyncState({lastAttemptUtc?, lastSuccessUtc?, lastError?, httpEtag?, httpLastModified?, emptyStreak = 0})`
  - Test helpers: `initZones()`, `johannesburg`, `london`, `blue`, `occ({...})`

- [ ] **Step 1: Add the timezone package**

Run: `flutter pub add timezone:^0.11.1`
Expected: `+ timezone 0.11.1` and `Changed N dependencies!`. (0.11.1 is the current release, published 2026-06-29. API: `package:timezone/data/latest_all.dart` → `initializeTimeZones()`, `package:timezone/timezone.dart` → `getLocation`, `TZDateTime`, `local`, `setLocalLocation`, `timeZoneDatabase.isInitialized`.)

- [ ] **Step 2: Write the test fixtures**

`test/core/fixtures.dart` (used by every later test):

```dart
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/model/event_occurrence.dart';

/// Loads the IANA database once per test file. Safe to call repeatedly.
void initZones() {
  if (_zonesLoaded) return;
  tzdata.initializeTimeZones();
  _zonesLoaded = true;
}

var _zonesLoaded = false;

/// UTC+2 all year, no DST.
tz.Location get johannesburg {
  initZones();
  return tz.getLocation('Africa/Johannesburg');
}

/// DST zone: GMT in winter, BST (UTC+1) from 29 Mar 2026 to 25 Oct 2026.
tz.Location get london {
  initZones();
  return tz.getLocation('Europe/London');
}

const blue = 0xFF6AA0F5;

/// An occurrence with sensible defaults; override only what a test needs.
EventOccurrence occ({
  String sourceId = 'work',
  String uid = 'uid1',
  DateTime? start,
  DateTime? originalStart,
  Duration length = const Duration(minutes: 30),
  String? seriesUid,
  String title = 'Sprint planning',
  String? location,
  String? organizer,
  String? description,
  String? joinUrl,
  bool allDay = false,
  BusyStatus busyStatus = BusyStatus.busy,
  bool declined = false,
  bool cancelled = false,
  int color = blue,
}) {
  final s = start ?? DateTime.utc(2026, 10, 6, 8); // 10:00 in Johannesburg
  return EventOccurrence(
    sourceId: sourceId,
    uid: uid,
    originalStartUtc: originalStart ?? s,
    seriesUid: seriesUid,
    title: title,
    location: location,
    organizer: organizer,
    description: description,
    joinUrl: joinUrl,
    startUtc: s,
    endUtc: s.add(length),
    allDay: allDay,
    busyStatus: busyStatus,
    declined: declined,
    cancelled: cancelled,
    calendarColor: color,
  );
}
```

- [ ] **Step 3: Write the failing domain test**

`test/core/model/domain_model_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/skip_filters.dart';

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
```

- [ ] **Step 4: Run it to make sure it fails**

Run: `flutter test test/core/model/domain_model_test.dart`
Expected: FAIL to compile, e.g. "Error when reading 'lib/core/model/event_occurrence.dart': The system cannot find the file specified".

- [ ] **Step 5: Implement the model files**

`lib/core/model/utc.dart`:

```dart
/// Returns [t] as a plain UTC [DateTime].
///
/// `TZDateTime.toUtc()` returns another `TZDateTime`, and a `DateTime` never
/// equals a `TZDateTime`, even for the same instant. Every model constructor
/// that stores an instant runs it through this, so equality and map keys work
/// no matter where the value came from.
DateTime plainUtc(DateTime t) =>
    DateTime.fromMicrosecondsSinceEpoch(t.microsecondsSinceEpoch, isUtc: true);
```

`lib/core/model/event_occurrence.dart`:

```dart
import 'utc.dart';

/// Free/busy state of an occurrence, as reported by its source.
enum BusyStatus { free, tentative, busy, oof, unknown }

/// Why an occurrence's data is less certain than usual.
enum OccurrenceWarning {
  /// The time zone could not be mapped exactly; a fallback zone was used.
  tzFallback,
}

/// One concrete instance of a calendar event, as cached from a source.
///
/// All instants are UTC. [key] stays the same when a meeting is moved,
/// because it is built from [originalStartUtc], not [startUtc].
class EventOccurrence {
  EventOccurrence({
    required this.sourceId,
    required this.uid,
    required DateTime originalStartUtc,
    this.seriesUid,
    required this.title,
    this.location,
    this.organizer,
    this.description,
    this.joinUrl,
    required DateTime startUtc,
    required DateTime endUtc,
    this.allDay = false,
    this.busyStatus = BusyStatus.unknown,
    this.declined = false,
    this.cancelled = false,
    required this.calendarColor,
    this.warnings = const {},
  }) : originalStartUtc = plainUtc(originalStartUtc),
       startUtc = plainUtc(startUtc),
       endUtc = plainUtc(endUtc);

  final String sourceId;
  final String uid;
  final DateTime originalStartUtc;

  /// Null for one-off events.
  final String? seriesUid;
  final String title;
  final String? location;
  final String? organizer;
  final String? description;
  final String? joinUrl;
  final DateTime startUtc;
  final DateTime endUtc;
  final bool allDay;
  final BusyStatus busyStatus;

  /// Device source only; ICS feeds do not carry your response.
  final bool declined;

  /// Device source only; `ics_core` already drops ICS cancellations.
  final bool cancelled;

  /// ARGB, e.g. 0xFF6AA0F5.
  final int calendarColor;
  final Set<OccurrenceWarning> warnings;

  String get key => makeKey(sourceId, uid, originalStartUtc);

  /// `'$sourceId|$uid|<originalStartUtc as UTC ISO-8601>'` (roadmap §4).
  static String makeKey(String sourceId, String uid, DateTime originalStart) =>
      '$sourceId|$uid|${originalStart.toUtc().toIso8601String()}';

  EventOccurrence copyWith({
    DateTime? startUtc,
    DateTime? endUtc,
    String? title,
    String? location,
    String? organizer,
    String? description,
    String? joinUrl,
    bool? allDay,
    BusyStatus? busyStatus,
    bool? declined,
    bool? cancelled,
    int? calendarColor,
    Set<OccurrenceWarning>? warnings,
  }) => EventOccurrence(
    sourceId: sourceId,
    uid: uid,
    originalStartUtc: originalStartUtc,
    seriesUid: seriesUid,
    title: title ?? this.title,
    location: location ?? this.location,
    organizer: organizer ?? this.organizer,
    description: description ?? this.description,
    joinUrl: joinUrl ?? this.joinUrl,
    startUtc: startUtc ?? this.startUtc,
    endUtc: endUtc ?? this.endUtc,
    allDay: allDay ?? this.allDay,
    busyStatus: busyStatus ?? this.busyStatus,
    declined: declined ?? this.declined,
    cancelled: cancelled ?? this.cancelled,
    calendarColor: calendarColor ?? this.calendarColor,
    warnings: warnings ?? this.warnings,
  );

  @override
  bool operator ==(Object other) =>
      other is EventOccurrence &&
      other.sourceId == sourceId &&
      other.uid == uid &&
      other.originalStartUtc == originalStartUtc &&
      other.seriesUid == seriesUid &&
      other.title == title &&
      other.location == location &&
      other.organizer == organizer &&
      other.description == description &&
      other.joinUrl == joinUrl &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc &&
      other.allDay == allDay &&
      other.busyStatus == busyStatus &&
      other.declined == declined &&
      other.cancelled == cancelled &&
      other.calendarColor == calendarColor &&
      other.warnings.length == warnings.length &&
      other.warnings.containsAll(warnings);

  @override
  int get hashCode => Object.hash(key, startUtc, endUtc, title);

  @override
  String toString() => 'EventOccurrence($key, "$title", $startUtc)';
}
```

`lib/core/model/alert_profile.dart`:

```dart
import 'alert.dart';

/// A named list of alerts plus profile-wide sound settings (spec §6).
class AlertProfile {
  const AlertProfile({
    required this.id,
    required this.name,
    required this.alerts,
    this.sound = const SoundSettings(),
    this.ringsInQuietMode = false,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final List<AlertSpec> alerts;
  final SoundSettings sound;
  final bool ringsInQuietMode;
  final bool builtIn;

  AlertProfile copyWith({
    String? name,
    List<AlertSpec>? alerts,
    SoundSettings? sound,
    bool? ringsInQuietMode,
  }) => AlertProfile(
    id: id,
    name: name ?? this.name,
    alerts: alerts ?? this.alerts,
    sound: sound ?? this.sound,
    ringsInQuietMode: ringsInQuietMode ?? this.ringsInQuietMode,
    builtIn: builtIn,
  );

  @override
  bool operator ==(Object other) =>
      other is AlertProfile &&
      other.id == id &&
      other.name == name &&
      sameAlerts(other.alerts, alerts) &&
      other.sound == sound &&
      other.ringsInQuietMode == ringsInQuietMode &&
      other.builtIn == builtIn;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(alerts),
    sound,
    ringsInQuietMode,
    builtIn,
  );

  @override
  String toString() => 'AlertProfile($id, $name)';
}

/// Element-wise equality for alert lists (null equals only null).
bool sameAlerts(List<AlertSpec>? a, List<AlertSpec>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// JSON for an alert list, shared by profile and override storage:
/// `[{"offsetMinutes": 10, "strength": "headsUp"}, …]`.
List<Map<String, Object?>> alertsToJson(List<AlertSpec> alerts) => [
  for (final a in alerts)
    {'offsetMinutes': a.offsetMinutes, 'strength': a.strength.name},
];

List<AlertSpec> alertsFromJson(List<Object?> json) => [
  for (final raw in json.cast<Map<String, Object?>>())
    AlertSpec(
      raw['offsetMinutes'] as int,
      AlertStrength.values.byName(raw['strength'] as String),
    ),
];

/// The four built-in profiles from spec §6. The ids are part of the roadmap
/// contract (§4) and never change.
abstract final class BuiltInProfiles {
  static const meetingId = 'meeting';
  static const quickId = 'quick';
  static const importantId = 'important';
  static const silentId = 'silent';

  /// The global default when settings name none (spec §6).
  static const defaultId = meetingId;

  static const meeting = AlertProfile(
    id: meetingId,
    name: 'Meeting',
    alerts: [
      AlertSpec(10, AlertStrength.headsUp),
      AlertSpec(1, AlertStrength.alarm),
    ],
    builtIn: true,
  );

  static const quick = AlertProfile(
    id: quickId,
    name: 'Quick',
    alerts: [AlertSpec(1, AlertStrength.alarm)],
    builtIn: true,
  );

  static const important = AlertProfile(
    id: importantId,
    name: 'Important',
    alerts: [
      AlertSpec(30, AlertStrength.headsUp),
      AlertSpec(10, AlertStrength.headsUp),
      AlertSpec(2, AlertStrength.alarm),
    ],
    ringsInQuietMode: true,
    builtIn: true,
  );

  static const silent = AlertProfile(
    id: silentId,
    name: 'Silent',
    alerts: [],
    builtIn: true,
  );

  /// In display order: Meeting · Quick · Important · Silent.
  static const all = [meeting, quick, important, silent];
}
```

`lib/core/model/event_override.dart`:

```dart
import 'alert.dart';
import 'alert_profile.dart';

enum OverrideScope { occurrence, series }

/// A per-occurrence or per-series override (spec §5, §6).
///
/// [target] is an `EventOccurrence.key` for [OverrideScope.occurrence] and a
/// `seriesUid` for [OverrideScope.series]. [profileId], [customAlerts] and
/// [enabled] are independent; an override with all three null has no effect.
/// The Agenda toggle writes an occurrence override with only [enabled] set.
///
/// Named `EventOverride`, not `Override`, so it never reads like `@override`.
class EventOverride {
  const EventOverride({
    required this.scope,
    required this.target,
    this.profileId,
    this.customAlerts,
    this.enabled,
  });

  final OverrideScope scope;
  final String target;
  final String? profileId;

  /// Replaces the profile's alert list when non-null.
  final List<AlertSpec>? customAlerts;

  /// true = turned on, false = turned off, null = not set.
  final bool? enabled;

  bool get isEmpty =>
      profileId == null && customAlerts == null && enabled == null;

  @override
  bool operator ==(Object other) =>
      other is EventOverride &&
      other.scope == scope &&
      other.target == target &&
      other.profileId == profileId &&
      other.enabled == enabled &&
      sameAlerts(other.customAlerts, customAlerts);

  @override
  int get hashCode => Object.hash(
    scope,
    target,
    profileId,
    enabled,
    customAlerts == null ? null : Object.hashAll(customAlerts!),
  );

  @override
  String toString() =>
      'EventOverride(${scope.name}:$target, profile: $profileId, '
      'custom: $customAlerts, enabled: $enabled)';
}
```

`lib/core/model/skip_filters.dart`:

```dart
/// Resolution step 3 (spec §6): matching events resolve to Silent.
/// Every filter defaults to on (roadmap §5.3).
class SkipFilters {
  const SkipFilters({
    this.allDay = true,
    this.free = true,
    this.tentative = true,
    this.cancelled = true,
    this.declined = true,
  });

  final bool allDay;
  final bool free;
  final bool tentative;
  final bool cancelled;
  final bool declined;

  SkipFilters copyWith({
    bool? allDay,
    bool? free,
    bool? tentative,
    bool? cancelled,
    bool? declined,
  }) => SkipFilters(
    allDay: allDay ?? this.allDay,
    free: free ?? this.free,
    tentative: tentative ?? this.tentative,
    cancelled: cancelled ?? this.cancelled,
    declined: declined ?? this.declined,
  );

  Map<String, Object?> toJson() => {
    'allDay': allDay,
    'free': free,
    'tentative': tentative,
    'cancelled': cancelled,
    'declined': declined,
  };

  /// A missing key falls back to on, so JSON from older builds stays valid.
  factory SkipFilters.fromJson(Map<String, Object?> j) => SkipFilters(
    allDay: j['allDay'] as bool? ?? true,
    free: j['free'] as bool? ?? true,
    tentative: j['tentative'] as bool? ?? true,
    cancelled: j['cancelled'] as bool? ?? true,
    declined: j['declined'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      other is SkipFilters &&
      other.allDay == allDay &&
      other.free == free &&
      other.tentative == tentative &&
      other.cancelled == cancelled &&
      other.declined == declined;

  @override
  int get hashCode => Object.hash(allDay, free, tentative, cancelled, declined);
}
```

`lib/core/model/source_config.dart`:

```dart
enum SourceKind { ics, device }

/// A configured calendar source as stored in drift.
///
/// Never holds an ICS URL: a published ICS link works like a password
/// (spec §3, §10). The URL lives in flutter_secure_storage (Plan 4) under
/// [secureStorageKey]; this record only keeps that key.
class SourceConfig {
  const SourceConfig({
    required this.id,
    required this.name,
    required this.color,
    required this.kind,
    this.deviceCalendarId,
    this.secureStorageKey,
    this.defaultProfileId,
    this.enabled = true,
  });

  final String id;
  final String name;

  /// ARGB, e.g. 0xFF6AA0F5.
  final int color;
  final SourceKind kind;

  /// Android calendar id; set only for [SourceKind.device].
  final String? deviceCalendarId;

  /// Key of the ICS URL in secure storage; set only for [SourceKind.ics].
  final String? secureStorageKey;

  /// Resolution step 5 (spec §6); null = use the global default.
  final String? defaultProfileId;
  final bool enabled;

  SourceConfig copyWith({
    String? name,
    int? color,
    String? deviceCalendarId,
    String? secureStorageKey,
    String? defaultProfileId,
    bool clearDefaultProfile = false,
    bool? enabled,
  }) => SourceConfig(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    kind: kind,
    deviceCalendarId: deviceCalendarId ?? this.deviceCalendarId,
    secureStorageKey: secureStorageKey ?? this.secureStorageKey,
    defaultProfileId: clearDefaultProfile
        ? null
        : (defaultProfileId ?? this.defaultProfileId),
    enabled: enabled ?? this.enabled,
  );

  @override
  bool operator ==(Object other) =>
      other is SourceConfig &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.kind == kind &&
      other.deviceCalendarId == deviceCalendarId &&
      other.secureStorageKey == secureStorageKey &&
      other.defaultProfileId == defaultProfileId &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    color,
    kind,
    deviceCalendarId,
    secureStorageKey,
    defaultProfileId,
    enabled,
  );

  @override
  String toString() => 'SourceConfig($id, $name, ${kind.name})';
}

/// Per-source sync bookkeeping, kept next to [SourceConfig] in the same row.
/// Plan 4 writes it; Plan 5 shows it ("Synced 4 min ago", red/amber state).
class SourceSyncState {
  const SourceSyncState({
    this.lastAttemptUtc,
    this.lastSuccessUtc,
    this.lastError,
    this.httpEtag,
    this.httpLastModified,
    this.emptyStreak = 0,
  });

  final DateTime? lastAttemptUtc;
  final DateTime? lastSuccessUtc;

  /// Human-readable, never contains the URL. Null after a success.
  final String? lastError;

  /// Conditional-GET validators from the last 200 response (spec §5).
  final String? httpEtag;
  final String? httpLastModified;

  /// Consecutive empty results while the cache still had occurrences;
  /// input to `EmptyFeedGuard.evaluate` (spec §9).
  final int emptyStreak;

  @override
  bool operator ==(Object other) =>
      other is SourceSyncState &&
      other.lastAttemptUtc == lastAttemptUtc &&
      other.lastSuccessUtc == lastSuccessUtc &&
      other.lastError == lastError &&
      other.httpEtag == httpEtag &&
      other.httpLastModified == httpLastModified &&
      other.emptyStreak == emptyStreak;

  @override
  int get hashCode => Object.hash(
    lastAttemptUtc,
    lastSuccessUtc,
    lastError,
    httpEtag,
    httpLastModified,
    emptyStreak,
  );
}
```

- [ ] **Step 6: Run the tests and analyzer**

Run: `flutter test test/core/model/domain_model_test.dart && flutter analyze`
Expected: `+11: All tests passed!`, then `No issues found!`

- [ ] **Step 7: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 8: Commit**

```bash
dart format lib/core/model/utc.dart lib/core/model/event_occurrence.dart lib/core/model/alert_profile.dart lib/core/model/event_override.dart lib/core/model/skip_filters.dart lib/core/model/source_config.dart test/core
git add pubspec.yaml pubspec.lock lib/core/model test/core
git commit -m "Add domain model for occurrences, profiles, overrides and sources" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Keyword rules

**Files:**
- Create: `lib/core/model/keyword_rule.dart`
- Test: `test/core/model/keyword_rule_test.dart`

**Interfaces:**
- Consumes: `EventOccurrence` (Task 2), `occ()` fixture.
- Produces: `enum RuleField { title, location, organizer, description, hasJoinLink }`, `enum RuleMatch { contains, regex }`, `KeywordRule({required String id, required int position, required RuleField field, RuleMatch match = RuleMatch.contains, String pattern = '', required String profileId})`, `bool matches(EventOccurrence o)`, `bool get isValid`, `copyWith({position, field, match, pattern, profileId})`, value equality.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/keyword_rule.dart';

import '../fixtures.dart';

void main() {
  KeywordRule rule(
    RuleField field,
    String pattern, {
    RuleMatch match = RuleMatch.contains,
  }) => KeywordRule(
    id: 'r',
    position: 0,
    field: field,
    match: match,
    pattern: pattern,
    profileId: 'quick',
  );

  final event = occ(
    title: 'Daily Standup',
    location: 'Boardroom 2',
    organizer: 'Thandi M.',
    description: 'Agenda: blockers',
  );

  final cases = <(String, KeywordRule, bool)>[
    ('title contains, any case', rule(RuleField.title, 'STANDUP'), true),
    ('title contains, no match', rule(RuleField.title, 'retro'), false),
    ('location contains', rule(RuleField.location, 'boardroom'), true),
    ('organizer contains', rule(RuleField.organizer, 'thandi'), true),
    ('description contains', rule(RuleField.description, 'BLOCKERS'), true),
    ('empty pattern never matches', rule(RuleField.title, ''), false),
    (
      'regex, case-insensitive',
      rule(RuleField.title, r'^daily\s+stand', match: RuleMatch.regex),
      true,
    ),
    (
      'regex, no match',
      rule(RuleField.title, r'^standup', match: RuleMatch.regex),
      false,
    ),
    (
      'invalid regex does not throw, does not match',
      rule(RuleField.title, r'stand(up', match: RuleMatch.regex),
      false,
    ),
    ('hasJoinLink without link', rule(RuleField.hasJoinLink, 'ignored'), false),
  ];

  for (final (name, r, expected) in cases) {
    test(name, () => expect(r.matches(event), expected));
  }

  test('null field never matches', () {
    expect(rule(RuleField.location, 'x').matches(occ()), isFalse);
  });

  test('hasJoinLink ignores the pattern and matches any join URL', () {
    final teams = occ(joinUrl: 'https://teams.microsoft.com/l/meetup-join/1');
    expect(rule(RuleField.hasJoinLink, '').matches(teams), isTrue);
    expect(rule(RuleField.hasJoinLink, 'nomatch').matches(teams), isTrue);
  });

  test('isValid flags only an uncompilable regex', () {
    expect(
      rule(RuleField.title, 'a(', match: RuleMatch.regex).isValid,
      isFalse,
    );
    expect(rule(RuleField.title, 'a(').isValid, isTrue);
    expect(rule(RuleField.title, 'a+', match: RuleMatch.regex).isValid, isTrue);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/model/keyword_rule_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/model/keyword_rule.dart'".

- [ ] **Step 3: Implement**

The regex is compiled once, lazily. A `FormatException` from a bad pattern is caught, and the rule then never matches.

```dart
import 'event_occurrence.dart';

enum RuleField { title, location, organizer, description, hasJoinLink }

enum RuleMatch { contains, regex }

/// "Title contains *standup* → Quick" (spec §6).
///
/// Matching is case-insensitive. An invalid regex never throws; the rule
/// simply does not match. [RuleField.hasJoinLink] ignores [pattern] and
/// matches when the occurrence has a join URL. For every other field an
/// empty pattern never matches (otherwise a half-typed rule would capture
/// every event).
class KeywordRule {
  KeywordRule({
    required this.id,
    required this.position,
    required this.field,
    this.match = RuleMatch.contains,
    this.pattern = '',
    required this.profileId,
  });

  final String id;

  /// User-defined order; lower runs first.
  final int position;
  final RuleField field;
  final RuleMatch match;
  final String pattern;
  final String profileId;

  late final RegExp? _regex = _compile();

  RegExp? _compile() {
    if (match != RuleMatch.regex || pattern.isEmpty) return null;
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return null;
    }
  }

  /// False only for a regex rule whose pattern does not compile. The rule
  /// editor (Plan 5) uses this to show an error.
  bool get isValid =>
      field == RuleField.hasJoinLink ||
      match != RuleMatch.regex ||
      pattern.isEmpty ||
      _regex != null;

  bool matches(EventOccurrence o) {
    final String? value;
    switch (field) {
      case RuleField.hasJoinLink:
        return o.joinUrl != null;
      case RuleField.title:
        value = o.title;
      case RuleField.location:
        value = o.location;
      case RuleField.organizer:
        value = o.organizer;
      case RuleField.description:
        value = o.description;
    }
    if (value == null || pattern.isEmpty) return false;
    return switch (match) {
      RuleMatch.contains => value.toLowerCase().contains(pattern.toLowerCase()),
      RuleMatch.regex => _regex?.hasMatch(value) ?? false,
    };
  }

  KeywordRule copyWith({
    int? position,
    RuleField? field,
    RuleMatch? match,
    String? pattern,
    String? profileId,
  }) => KeywordRule(
    id: id,
    position: position ?? this.position,
    field: field ?? this.field,
    match: match ?? this.match,
    pattern: pattern ?? this.pattern,
    profileId: profileId ?? this.profileId,
  );

  @override
  bool operator ==(Object other) =>
      other is KeywordRule &&
      other.id == id &&
      other.position == position &&
      other.field == field &&
      other.match == match &&
      other.pattern == pattern &&
      other.profileId == profileId;

  @override
  int get hashCode =>
      Object.hash(id, position, field, match, pattern, profileId);

  @override
  String toString() =>
      'KeywordRule($id #$position ${field.name} ${match.name} "$pattern" '
      '→ $profileId)';
}
```

- [ ] **Step 4: Run the tests and analyzer**

Run: `flutter test test/core/model/keyword_rule_test.dart && flutter analyze`
Expected: `+13: All tests passed!`, then `No issues found!`

- [ ] **Step 5: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
dart format lib/core/model/keyword_rule.dart test/core/model/keyword_rule_test.dart
git add lib/core/model/keyword_rule.dart test/core/model/keyword_rule_test.dart
git commit -m "Add case-insensitive keyword rules that never throw on bad regex" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Local dates and quiet states

**Files:**
- Create: `lib/core/model/local_date.dart`, `lib/core/model/quiet_state.dart`
- Test: `test/core/model/quiet_state_test.dart`

**Interfaces:**
- Consumes: `plainUtc` (Task 2), `package:timezone`.
- Produces:
  - `LocalDate(int year, int month, int day)`, `LocalDate.of(DateTime instantUtc, tz.Location zone)`, `LocalDate.parse(String yyyyMmDd)`, `addDays(int)`, `startIn(tz.Location)`, `toIso()`, `<=`, `>=`, `compareTo`
  - `sealed class QuietState` with `factory QuietState.muteToday({required DateTime nowUtc, required tz.Location zone})`, `bool covers(DateTime startUtc, {required DateTime nowUtc, required tz.Location zone})`, `bool isActive({required DateTime nowUtc, required tz.Location zone})`, `String label(tz.Location zone)`
  - `QuietNone()`, `sealed QuietUntil` → `MuteToday(DateTime untilUtc)`, `PausedUntil(DateTime untilUtc)`, `Vacation(LocalDate firstDay, LocalDate lastDay)`

- [ ] **Step 1: Write the failing test**

Johannesburg is UTC+2 with no DST. London switches from BST to GMT on Sun 25 Oct 2026, which exercises "07:00 the next local day" across a DST change.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';

import '../fixtures.dart';

void main() {
  setUpAll(initZones);

  group('LocalDate', () {
    test('of() uses the local date, not the UTC date', () {
      // 23:30 UTC on 5 Oct is 01:30 on 6 Oct in Johannesburg.
      expect(
        LocalDate.of(DateTime.utc(2026, 10, 5, 23, 30), johannesburg),
        LocalDate(2026, 10, 6),
      );
    });

    test('parse/toIso round trip, ordering, addDays across month end', () {
      final d = LocalDate.parse('2026-10-31');
      expect(d.toIso(), '2026-10-31');
      expect(d.addDays(1), LocalDate(2026, 11, 1));
      expect(LocalDate(2026, 10, 1) <= LocalDate(2026, 10, 1), isTrue);
      expect(LocalDate(2026, 10, 2) >= LocalDate(2026, 10, 3), isFalse);
      expect(() => LocalDate.parse('6/10/2026'), throwsFormatException);
    });
  });

  group('Mute today', () {
    test('ends at 07:00 on the next local day (Johannesburg)', () {
      final q = QuietState.muteToday(
        nowUtc: DateTime.utc(2026, 10, 6, 13),
        zone: johannesburg,
      );
      expect(q, MuteToday(DateTime.utc(2026, 10, 7, 5))); // 07:00 SAST
    });

    test('ends at 07:00 local across a DST change (London)', () {
      // Sat 24 Oct 2026 20:00 BST; clocks go back on Sun 25 Oct.
      final q = QuietState.muteToday(
        nowUtc: DateTime.utc(2026, 10, 24, 19),
        zone: london,
      );
      expect(q, MuteToday(DateTime.utc(2026, 10, 25, 7))); // 07:00 GMT
    });

    test('just after midnight still means the next day at 07:00', () {
      final q = QuietState.muteToday(
        nowUtc: DateTime.utc(2026, 10, 5, 22, 30), // 00:30 SAST on 6 Oct
        zone: johannesburg,
      );
      expect(q, MuteToday(DateTime.utc(2026, 10, 7, 5)));
    });
  });

  group('covers', () {
    final now = DateTime.utc(2026, 10, 6, 9);
    final pause = PausedUntil(DateTime.utc(2026, 10, 6, 12));

    test('pause covers events starting before its end, not at its end', () {
      bool c(DateTime s) => pause.covers(s, nowUtc: now, zone: johannesburg);
      expect(c(DateTime.utc(2026, 10, 6, 11, 59)), isTrue);
      expect(c(DateTime.utc(2026, 10, 6, 12)), isFalse);
    });

    test('an expired pause covers nothing', () {
      expect(
        pause.covers(
          DateTime.utc(2026, 10, 6, 11),
          nowUtc: DateTime.utc(2026, 10, 6, 12),
          zone: johannesburg,
        ),
        isFalse,
      );
      expect(
        pause.isActive(
          nowUtc: DateTime.utc(2026, 10, 6, 12),
          zone: johannesburg,
        ),
        isFalse,
      );
    });

    test('vacation covers whole local days, inclusive', () {
      final v = Vacation(LocalDate(2026, 10, 7), LocalDate(2026, 10, 9));
      bool c(DateTime s) => v.covers(s, nowUtc: now, zone: johannesburg);
      expect(c(DateTime.utc(2026, 10, 6, 21, 59)), isFalse); // 23:59 on 6th
      expect(c(DateTime.utc(2026, 10, 6, 22)), isTrue); // 00:00 on 7th
      expect(c(DateTime.utc(2026, 10, 9, 21, 59)), isTrue); // 23:59 on 9th
      expect(c(DateTime.utc(2026, 10, 9, 22)), isFalse); // 00:00 on 10th
      expect(v.isActive(nowUtc: now, zone: johannesburg), isTrue);
      expect(
        v.isActive(nowUtc: DateTime.utc(2026, 10, 10, 8), zone: johannesburg),
        isFalse,
      );
    });

    test('none covers nothing', () {
      expect(const QuietNone().covers(now, nowUtc: now, zone: london), isFalse);
    });
  });

  group('label', () {
    test('Paused until shows local HH:mm', () {
      expect(
        PausedUntil(DateTime.utc(2026, 10, 6, 12)).label(johannesburg),
        'Paused until 14:00',
      );
      expect(
        PausedUntil(DateTime.utc(2026, 7, 1, 12, 5)).label(london),
        'Paused until 13:05',
      );
    });

    test('Mute today and Vacation', () {
      expect(
        MuteToday(DateTime.utc(2026, 10, 7, 5)).label(london),
        'Mute today',
      );
      expect(
        Vacation(LocalDate(2026, 10, 7), LocalDate(2026, 10, 7)).label(london),
        'Vacation',
      );
    });
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/model/quiet_state_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/model/local_date.dart'".

- [ ] **Step 3: Implement `LocalDate`**

```dart
import 'package:timezone/timezone.dart' as tz;

/// A calendar date with no time and no zone, e.g. a vacation day.
class LocalDate implements Comparable<LocalDate> {
  LocalDate(int year, int month, int day)
    : this._(DateTime.utc(year, month, day));

  LocalDate._(DateTime utcMidnight)
    : year = utcMidnight.year,
      month = utcMidnight.month,
      day = utcMidnight.day;

  /// The date [instantUtc] falls on in [zone].
  factory LocalDate.of(DateTime instantUtc, tz.Location zone) {
    final local = tz.TZDateTime.from(instantUtc, zone);
    return LocalDate(local.year, local.month, local.day);
  }

  /// Parses `yyyy-MM-dd`. Throws [FormatException] on anything else.
  factory LocalDate.parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) throw FormatException('Not a yyyy-MM-dd date', iso);
    return LocalDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  final int year;
  final int month;
  final int day;

  LocalDate addDays(int days) =>
      LocalDate._(DateTime.utc(year, month, day + days));

  /// Local midnight at the start of this date in [zone].
  tz.TZDateTime startIn(tz.Location zone) =>
      tz.TZDateTime(zone, year, month, day);

  @override
  int compareTo(LocalDate other) =>
      (year * 10000 + month * 100 + day) -
      (other.year * 10000 + other.month * 100 + other.day);

  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
```

- [ ] **Step 4: Implement `QuietState`**

Note `plainUtc` in `QuietUntil`. `tz.TZDateTime(...)` (from `muteToday`) is a `TZDateTime`, which would never `==` a plain `DateTime` (Review Focus 2).

```dart
import 'package:timezone/timezone.dart' as tz;

import 'local_date.dart';
import 'utc.dart';

/// The user's quiet mode (spec §6 "Quiet modes"). Only one is active at a
/// time; setting a new one replaces the old one.
///
/// An occurrence is "inside" a quiet mode when its **start** is inside it:
/// - [MuteToday] / [PausedUntil]: the mode has not ended yet (`now < until`)
///   and the occurrence starts before `until`. A meeting that starts exactly
///   at `until` is outside, so its heads-up still rings.
/// - [Vacation]: the occurrence starts on a local date from [Vacation.firstDay]
///   to [Vacation.lastDay], inclusive.
sealed class QuietState {
  const QuietState();

  /// Mute today: ends at 07:00 on the next local day.
  factory QuietState.muteToday({
    required DateTime nowUtc,
    required tz.Location zone,
  }) {
    final local = tz.TZDateTime.from(nowUtc, zone);
    final until = tz.TZDateTime(
      zone,
      local.year,
      local.month,
      local.day + 1,
      7,
    );
    return MuteToday(until);
  }

  /// True when an occurrence starting at [startUtc] is inside this mode.
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  });

  /// True while the mode still matters: now or later events can be covered.
  /// The Agenda banner (Plan 5) shows only while this is true.
  bool isActive({required DateTime nowUtc, required tz.Location zone});

  /// The text after "Silenced · ", e.g. `Mute today`, `Paused until 14:00`,
  /// `Vacation` (roadmap §4).
  String label(tz.Location zone);
}

final class QuietNone extends QuietState {
  const QuietNone();

  @override
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  }) => false;

  @override
  bool isActive({required DateTime nowUtc, required tz.Location zone}) => false;

  @override
  String label(tz.Location zone) => '';

  @override
  bool operator ==(Object other) => other is QuietNone;

  @override
  int get hashCode => 0;
}

/// Shared by [MuteToday] and [PausedUntil]: quiet until an instant.
sealed class QuietUntil extends QuietState {
  QuietUntil(DateTime untilUtc) : untilUtc = plainUtc(untilUtc);

  final DateTime untilUtc;

  @override
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  }) => nowUtc.isBefore(untilUtc) && startUtc.isBefore(untilUtc);

  @override
  bool isActive({required DateTime nowUtc, required tz.Location zone}) =>
      nowUtc.isBefore(untilUtc);
}

final class MuteToday extends QuietUntil {
  MuteToday(super.untilUtc);

  @override
  String label(tz.Location zone) => 'Mute today';

  @override
  bool operator ==(Object other) =>
      other is MuteToday && other.untilUtc == untilUtc;

  @override
  int get hashCode => Object.hash('mute', untilUtc);

  @override
  String toString() => 'MuteToday(until $untilUtc)';
}

final class PausedUntil extends QuietUntil {
  PausedUntil(super.untilUtc);

  @override
  String label(tz.Location zone) {
    final t = tz.TZDateTime.from(untilUtc, zone);
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Paused until ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  bool operator ==(Object other) =>
      other is PausedUntil && other.untilUtc == untilUtc;

  @override
  int get hashCode => Object.hash('pause', untilUtc);

  @override
  String toString() => 'PausedUntil($untilUtc)';
}

final class Vacation extends QuietState {
  Vacation(this.firstDay, this.lastDay)
    : assert(firstDay <= lastDay, 'firstDay must not be after lastDay');

  final LocalDate firstDay;
  final LocalDate lastDay;

  @override
  bool covers(
    DateTime startUtc, {
    required DateTime nowUtc,
    required tz.Location zone,
  }) {
    final day = LocalDate.of(startUtc, zone);
    return day >= firstDay && day <= lastDay;
  }

  @override
  bool isActive({required DateTime nowUtc, required tz.Location zone}) =>
      LocalDate.of(nowUtc, zone) <= lastDay;

  @override
  String label(tz.Location zone) => 'Vacation';

  @override
  bool operator ==(Object other) =>
      other is Vacation &&
      other.firstDay == firstDay &&
      other.lastDay == lastDay;

  @override
  int get hashCode => Object.hash('vacation', firstDay, lastDay);

  @override
  String toString() => 'Vacation($firstDay..$lastDay)';
}
```

- [ ] **Step 5: Run the tests and analyzer**

Run: `flutter test test/core/model/quiet_state_test.dart && flutter analyze`
Expected: `+11: All tests passed!`, then `No issues found!`

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
dart format lib/core/model/local_date.dart lib/core/model/quiet_state.dart test/core/model/quiet_state_test.dart
git add lib/core/model/local_date.dart lib/core/model/quiet_state.dart test/core/model/quiet_state_test.dart
git commit -m "Add quiet states: mute today, pause until and vacation" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Rules engine (resolution order and explanations)

**Files:**
- Create: `lib/core/rules/rule_set.dart`, `lib/core/rules/resolved_occurrence.dart`, `lib/core/rules/rules_engine.dart`
- Test: `test/core/rules/rules_test_helpers.dart`, `test/core/rules/rules_engine_test.dart`

**Interfaces:**
- Consumes: everything in `lib/core/model` from Tasks 2–4.
- Produces:
  - `RuleSet({List<AlertProfile> profiles = const [], List<EventOverride> overrides = const [], List<KeywordRule> rules = const [], SkipFilters skipFilters = const SkipFilters(), Map<String, String> sourceDefaults = const {}, String globalDefaultProfileId = 'meeting', QuietState quiet = const QuietNone()})`, `AlertProfile? profile(String id)` (built-ins are always present; stored profiles replace them by id), `EventOverride? occurrenceOverride(String key)`, `EventOverride? seriesOverride(String? seriesUid)`, `List<KeywordRule> rules` (sorted)
  - `enum ResolutionStep { occurrenceOverride, seriesOverride, skipFilter, keywordRule, sourceDefault, globalDefault }`
  - `ResolvedOccurrence({occurrence, profile, alerts, explanation, silenced, step})`
  - `typedef UtcClock = DateTime Function()`, `DateTime systemUtcNow()`
  - `RulesEngine({required tz.Location zone, UtcClock? clock})`, `ResolvedOccurrence resolve(EventOccurrence, RuleSet)`, `List<ResolvedOccurrence> resolveAll(Iterable<EventOccurrence>, RuleSet)`
  - Test helpers: `now`, `meetingAlerts`, `quickAlerts`, `importantAlerts`, `custom`, `titleRule()`, `onOcc()`, `onSeries()`, `Case`, `runCases()`

- [ ] **Step 1: Write the shared test helpers**

`test/core/rules/rules_test_helpers.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';

/// 08:00 SAST on Tue 6 Oct 2026. The default event starts at 10:00 SAST.
final now = DateTime.utc(2026, 10, 6, 6);

const meetingAlerts = [
  AlertSpec(10, AlertStrength.headsUp),
  AlertSpec(1, AlertStrength.alarm),
];
const quickAlerts = [AlertSpec(1, AlertStrength.alarm)];
const importantAlerts = [
  AlertSpec(30, AlertStrength.headsUp),
  AlertSpec(10, AlertStrength.headsUp),
  AlertSpec(2, AlertStrength.alarm),
];
const custom = [AlertSpec(5, AlertStrength.alarm)];

KeywordRule titleRule(
  String pattern,
  String profileId, {
  int position = 0,
  String? id,
}) => KeywordRule(
  id: id ?? 'r-$pattern',
  position: position,
  field: RuleField.title,
  pattern: pattern,
  profileId: profileId,
);

EventOverride onOcc(
  EventOccurrence o, {
  String? profileId,
  List<AlertSpec>? customAlerts,
  bool? enabled,
}) => EventOverride(
  scope: OverrideScope.occurrence,
  target: o.key,
  profileId: profileId,
  customAlerts: customAlerts,
  enabled: enabled,
);

EventOverride onSeries(
  String seriesUid, {
  String? profileId,
  List<AlertSpec>? customAlerts,
  bool? enabled,
}) => EventOverride(
  scope: OverrideScope.series,
  target: seriesUid,
  profileId: profileId,
  customAlerts: customAlerts,
  enabled: enabled,
);

class Case {
  Case(
    this.name,
    this.event,
    this.rules,
    this.explanation,
    this.alerts, {
    required this.step,
    this.silenced = false,
    this.profileId,
  });

  final String name;
  final EventOccurrence event;
  final RuleSet rules;
  final String explanation;
  final List<AlertSpec> alerts;
  final ResolutionStep step;
  final bool silenced;
  final String? profileId;
}

/// One test per case: resolves [Case.event] and checks every field.
void runCases(List<Case> cases, RulesEngine Function() engine) {
  for (final c in cases) {
    test(c.name, () {
      final r = engine().resolve(c.event, c.rules);
      expect(r.explanation, c.explanation);
      expect(r.alerts, c.alerts);
      expect(r.silenced, c.silenced);
      expect(r.step, c.step);
      expect(r.occurrence, same(c.event));
      if (c.profileId != null) expect(r.profile.id, c.profileId);
    });
  }
}
```

- [ ] **Step 2: Write the failing table-driven test**

`test/core/rules/rules_engine_test.dart` has one row per resolution step and per explanation form:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';

import '../fixtures.dart';
import 'rules_test_helpers.dart';

void main() {
  final plain = occ();
  final standup = occ(uid: 'standup', title: 'Daily standup');
  final tentative = occ(uid: 't', busyStatus: BusyStatus.tentative);
  final recurring = occ(uid: 'rec', seriesUid: 'series-1');
  final recurringTentative = occ(
    uid: 'rec2',
    seriesUid: 'series-2',
    busyStatus: BusyStatus.tentative,
  );
  final lunch = occ(uid: 'lunch', title: 'Lunch');
  final teams = occ(
    uid: 'teams',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/1',
  );

  final cases = <Case>[
    // 6. Global default
    Case(
      'global default',
      plain,
      RuleSet(),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
      profileId: 'meeting',
    ),
    Case(
      'global default set to Quick',
      plain,
      RuleSet(globalDefaultProfileId: 'quick'),
      'Quick · default',
      quickAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'unknown global default falls back to Meeting',
      plain,
      RuleSet(globalDefaultProfileId: 'deleted'),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'edited built-in replaces the constant',
      plain,
      RuleSet(profiles: [BuiltInProfiles.meeting.copyWith(alerts: custom)]),
      'Meeting · default',
      custom,
      step: ResolutionStep.globalDefault,
    ),

    // 5. Source default
    Case(
      'source default',
      plain,
      RuleSet(sourceDefaults: {'work': 'important'}),
      'Important · source default',
      importantAlerts,
      step: ResolutionStep.sourceDefault,
    ),
    Case(
      'source default of another source does not apply',
      plain,
      RuleSet(sourceDefaults: {'personal': 'important'}),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'unknown source default falls through',
      plain,
      RuleSet(sourceDefaults: {'work': 'deleted'}),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),

    // 4. Keyword rules
    Case(
      'keyword rule',
      standup,
      RuleSet(rules: [titleRule('standup', 'quick')]),
      'Quick · rule: "standup"',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rules run by position, not list order',
      standup,
      RuleSet(
        rules: [
          titleRule('daily', 'important', position: 1),
          titleRule('standup', 'quick', position: 0),
        ],
      ),
      'Quick · rule: "standup"',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rule with a deleted profile is skipped',
      standup,
      RuleSet(
        rules: [
          titleRule('standup', 'deleted', position: 0),
          titleRule('daily', 'important', position: 1),
        ],
      ),
      'Important · rule: "daily"',
      importantAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'hasJoinLink rule',
      teams,
      RuleSet(
        rules: [
          KeywordRule(
            id: 'j',
            position: 0,
            field: RuleField.hasJoinLink,
            profileId: 'quick',
          ),
        ],
      ),
      'Quick · rule: Teams link',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rule to Silent',
      lunch,
      RuleSet(rules: [titleRule('lunch', 'silent')]),
      'Silent · rule: "lunch"',
      const [],
      step: ResolutionStep.keywordRule,
    ),
    Case(
      'rule beats source default',
      standup,
      RuleSet(
        rules: [titleRule('standup', 'quick')],
        sourceDefaults: {'work': 'important'},
      ),
      'Quick · rule: "standup"',
      quickAlerts,
      step: ResolutionStep.keywordRule,
    ),

    // 3. Skip filters
    Case(
      'skip all-day',
      occ(uid: 'ad', allDay: true),
      RuleSet(),
      'Silent · all-day',
      const [],
      step: ResolutionStep.skipFilter,
      profileId: 'silent',
    ),
    Case(
      'skip free',
      occ(uid: 'f', busyStatus: BusyStatus.free),
      RuleSet(),
      'Silent · free',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'skip tentative',
      tentative,
      RuleSet(),
      'Silent · tentative',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'skip cancelled',
      occ(uid: 'c', cancelled: true),
      RuleSet(),
      'Silent · cancelled',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'skip declined',
      occ(uid: 'd', declined: true),
      RuleSet(),
      'Silent · declined',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'tentative filter switched off',
      tentative,
      RuleSet(skipFilters: const SkipFilters(tentative: false)),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'skip filter beats keyword rule',
      occ(uid: 'ts', title: 'Standup', busyStatus: BusyStatus.tentative),
      RuleSet(rules: [titleRule('standup', 'quick')]),
      'Silent · tentative',
      const [],
      step: ResolutionStep.skipFilter,
    ),

    // 2. Series override
    Case(
      'series override beats skip filter',
      recurringTentative,
      RuleSet(overrides: [onSeries('series-2', profileId: 'important')]),
      'Important · series',
      importantAlerts,
      step: ResolutionStep.seriesOverride,
    ),
    Case(
      'series override off',
      recurring,
      RuleSet(overrides: [onSeries('series-1', enabled: false)]),
      'Off · series',
      const [],
      step: ResolutionStep.seriesOverride,
    ),
    Case(
      'series override does not touch one-off events',
      plain,
      RuleSet(overrides: [onSeries('series-1', profileId: 'quick')]),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),

    // 1. Occurrence override
    Case(
      'occurrence override beats series override',
      recurring,
      RuleSet(
        overrides: [
          onSeries('series-1', profileId: 'important'),
          onOcc(recurring, profileId: 'quick'),
        ],
      ),
      'Quick · this event',
      quickAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'agenda toggle off',
      plain,
      RuleSet(overrides: [onOcc(plain, enabled: false)]),
      'Off · this event',
      const [],
      step: ResolutionStep.occurrenceOverride,
      profileId: 'silent',
    ),
    Case(
      'agenda toggle on skips the skip filter',
      tentative,
      RuleSet(overrides: [onOcc(tentative, enabled: true)]),
      'Meeting · this event',
      meetingAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'toggle on ignores a rule that resolves to Silent',
      lunch,
      RuleSet(
        rules: [titleRule('lunch', 'silent')],
        overrides: [onOcc(lunch, enabled: true)],
      ),
      'Meeting · this event',
      meetingAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'custom alerts replace the named profile list',
      plain,
      RuleSet(
        overrides: [onOcc(plain, profileId: 'quick', customAlerts: custom)],
      ),
      'Quick · this event',
      custom,
      step: ResolutionStep.occurrenceOverride,
      profileId: 'quick',
    ),
    Case(
      'custom alerts without a profile use the lower step for sound',
      recurring,
      RuleSet(
        overrides: [
          onSeries('series-1', profileId: 'important'),
          onOcc(recurring, customAlerts: custom),
        ],
      ),
      'Custom · this event',
      custom,
      step: ResolutionStep.occurrenceOverride,
      profileId: 'important',
    ),
    Case(
      'empty override is ignored',
      plain,
      RuleSet(overrides: [onOcc(plain)]),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'override naming a deleted profile falls through',
      plain,
      RuleSet(overrides: [onOcc(plain, profileId: 'deleted')]),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
  ];

  RulesEngine engine() => RulesEngine(zone: johannesburg, clock: () => now);

  runCases(cases, engine);

  test('resolveAll keeps input order', () {
    final r = engine().resolveAll([
      standup,
      plain,
    ], RuleSet(rules: [titleRule('standup', 'quick')]));
    expect(r.map((e) => e.explanation), [
      'Quick · rule: "standup"',
      'Meeting · default',
    ]);
  });
}
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `flutter test test/core/rules/rules_engine_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/rules/resolved_occurrence.dart'".

- [ ] **Step 4: Implement `RuleSet` and `ResolvedOccurrence`**

`lib/core/rules/rule_set.dart`:

```dart
import '../model/alert_profile.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/quiet_state.dart';
import '../model/skip_filters.dart';

/// Everything the rules engine needs besides the occurrence itself.
/// Built from storage by `loadRuleSet` (lib/core/storage/rule_set_loader.dart).
class RuleSet {
  RuleSet({
    List<AlertProfile> profiles = const [],
    List<EventOverride> overrides = const [],
    List<KeywordRule> rules = const [],
    this.skipFilters = const SkipFilters(),
    this.sourceDefaults = const {},
    this.globalDefaultProfileId = BuiltInProfiles.defaultId,
    this.quiet = const QuietNone(),
  }) : _profiles = {
         for (final p in BuiltInProfiles.all) p.id: p,
         // Stored profiles win, so an edited built-in replaces the constant.
         for (final p in profiles) p.id: p,
       },
       _occurrenceOverrides = {
         for (final o in overrides)
           if (o.scope == OverrideScope.occurrence && !o.isEmpty) o.target: o,
       },
       _seriesOverrides = {
         for (final o in overrides)
           if (o.scope == OverrideScope.series && !o.isEmpty) o.target: o,
       },
       rules = List.unmodifiable(<KeywordRule>[...rules]..sort(_byPosition));

  final Map<String, AlertProfile> _profiles;
  final Map<String, EventOverride> _occurrenceOverrides;
  final Map<String, EventOverride> _seriesOverrides;

  /// Sorted by position, then id.
  final List<KeywordRule> rules;
  final SkipFilters skipFilters;

  /// sourceId → default profile id (sources without one are absent).
  final Map<String, String> sourceDefaults;
  final String globalDefaultProfileId;
  final QuietState quiet;

  /// Null when [id] names no known profile (e.g. it was deleted).
  AlertProfile? profile(String id) => _profiles[id];

  EventOverride? occurrenceOverride(String occurrenceKey) =>
      _occurrenceOverrides[occurrenceKey];

  EventOverride? seriesOverride(String? seriesUid) =>
      seriesUid == null ? null : _seriesOverrides[seriesUid];

  static int _byPosition(KeywordRule a, KeywordRule b) {
    final byPos = a.position.compareTo(b.position);
    return byPos != 0 ? byPos : a.id.compareTo(b.id);
  }
}
```

`lib/core/rules/resolved_occurrence.dart`:

```dart
import '../model/alert.dart';
import '../model/alert_profile.dart';
import '../model/event_occurrence.dart';

/// The resolution step that decided an occurrence (spec §6), in order.
enum ResolutionStep {
  occurrenceOverride,
  seriesOverride,
  skipFilter,
  keywordRule,
  sourceDefault,
  globalDefault,
}

/// The rules engine's verdict for one occurrence.
class ResolvedOccurrence {
  const ResolvedOccurrence({
    required this.occurrence,
    required this.profile,
    required this.alerts,
    required this.explanation,
    required this.silenced,
    required this.step,
  });

  final EventOccurrence occurrence;

  /// Supplies sound settings and `ringsInQuietMode`. For "Off" results this is
  /// the Silent profile.
  final AlertProfile profile;

  /// What will actually be planned: the profile's alerts, or the override's
  /// custom alerts; empty when off, silent or silenced by a quiet mode.
  final List<AlertSpec> alerts;

  /// The grey reason line, e.g. `Quick · rule: "standup"` (roadmap §4).
  final String explanation;

  /// True when a quiet mode removed alerts that would otherwise ring.
  final bool silenced;
  final ResolutionStep step;

  @override
  String toString() =>
      'ResolvedOccurrence(${occurrence.key}, $explanation, $alerts)';
}
```

- [ ] **Step 5: Implement the engine (resolution only; Task 6 adds quiet modes)**

`lib/core/rules/rules_engine.dart`:

```dart
import 'package:timezone/timezone.dart' as tz;

import '../model/alert.dart';
import '../model/alert_profile.dart';
import '../model/event_occurrence.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import 'resolved_occurrence.dart';
import 'rule_set.dart';

/// Returns the current instant in UTC. Injected so tests are deterministic.
typedef UtcClock = DateTime Function();

DateTime systemUtcNow() => DateTime.now().toUtc();

/// Profile resolution, quiet modes and explanations (spec §6, roadmap §4).
///
/// Resolution order, first match wins:
/// 1. occurrence override, 2. series override, 3. skip filters,
/// 4. keyword rules by position, 5. source default, 6. global default.
/// Quiet modes are applied afterwards.
class RulesEngine {
  RulesEngine({required this.zone, UtcClock? clock})
    : clock = clock ?? systemUtcNow;

  /// The device's local zone; used for "Mute today", vacation days and the
  /// "Paused until HH:mm" text.
  final tz.Location zone;
  final UtcClock clock;

  List<ResolvedOccurrence> resolveAll(
    Iterable<EventOccurrence> occurrences,
    RuleSet rules,
  ) => [for (final o in occurrences) resolve(o, rules)];

  ResolvedOccurrence resolve(EventOccurrence o, RuleSet rules) {
    final occ = rules.occurrenceOverride(o.key);
    final ser = rules.seriesOverride(o.seriesUid);
    return _decide(o, rules, occ, ser).toResolved(o);
  }

  _Decision _decide(
    EventOccurrence o,
    RuleSet rules,
    EventOverride? occ,
    EventOverride? ser,
  ) {
    if (occ != null) {
      final d = _fromOverride(
        occ,
        'this event',
        ResolutionStep.occurrenceOverride,
        o,
        rules,
        lower: () => _decide(o, rules, null, ser),
      );
      if (d != null) return d;
    }
    if (ser != null) {
      final d = _fromOverride(
        ser,
        'series',
        ResolutionStep.seriesOverride,
        o,
        rules,
        lower: () => _decide(o, rules, null, null),
      );
      if (d != null) return d;
    }
    return _skipFilter(o, rules) ?? _fromRulesAndDefaults(o, rules);
  }

  /// Null when the override decides nothing (e.g. it names a deleted profile
  /// and sets nothing else), so resolution falls through to the next step.
  _Decision? _fromOverride(
    EventOverride ov,
    String reason,
    ResolutionStep step,
    EventOccurrence o,
    RuleSet rules, {
    required _Decision Function() lower,
  }) {
    if (ov.enabled == false) {
      return _Decision(BuiltInProfiles.silent, const [], step, 'Off · $reason');
    }
    final named = ov.profileId == null ? null : rules.profile(ov.profileId!);
    if (named != null) {
      return _Decision(
        named,
        ov.customAlerts ?? named.alerts,
        step,
        '${named.name} · $reason',
      );
    }
    if (ov.customAlerts != null) {
      final base = ov.enabled == true
          ? _turnedOnProfile(o, rules)
          : lower().profile;
      return _Decision(base, ov.customAlerts!, step, 'Custom · $reason');
    }
    if (ov.enabled == true) {
      final p = _turnedOnProfile(o, rules);
      return _Decision(p, p.alerts, step, '${p.name} · $reason');
    }
    return null;
  }

  /// An event switched on without naming a profile skips the skip filters
  /// and takes the first candidate that actually has alerts: matching rules,
  /// then the source default, then the global default, then Meeting.
  AlertProfile _turnedOnProfile(EventOccurrence o, RuleSet rules) {
    final candidates = <String?>[
      for (final r in rules.rules)
        if (r.matches(o)) r.profileId,
      rules.sourceDefaults[o.sourceId],
      rules.globalDefaultProfileId,
    ];
    for (final id in candidates) {
      final p = id == null ? null : rules.profile(id);
      if (p != null && p.alerts.isNotEmpty) return p;
    }
    return BuiltInProfiles.meeting;
  }

  _Decision? _skipFilter(EventOccurrence o, RuleSet rules) {
    final f = rules.skipFilters;
    final reason = switch (o) {
      _ when f.allDay && o.allDay => 'all-day',
      _ when f.free && o.busyStatus == BusyStatus.free => 'free',
      _ when f.tentative && o.busyStatus == BusyStatus.tentative => 'tentative',
      _ when f.cancelled && o.cancelled => 'cancelled',
      _ when f.declined && o.declined => 'declined',
      _ => null,
    };
    if (reason == null) return null;
    final silent = rules.profile(BuiltInProfiles.silentId)!;
    return _Decision(
      silent,
      silent.alerts,
      ResolutionStep.skipFilter,
      '${silent.name} · $reason',
    );
  }

  _Decision _fromRulesAndDefaults(EventOccurrence o, RuleSet rules) {
    for (final r in rules.rules) {
      final p = rules.profile(r.profileId);
      if (p != null && r.matches(o)) {
        final what = r.field == RuleField.hasJoinLink
            ? 'Teams link'
            : '"${r.pattern}"';
        return _Decision(
          p,
          p.alerts,
          ResolutionStep.keywordRule,
          '${p.name} · rule: $what',
        );
      }
    }
    final sourceDefault = rules.sourceDefaults[o.sourceId];
    final sp = sourceDefault == null ? null : rules.profile(sourceDefault);
    if (sp != null) {
      return _Decision(
        sp,
        sp.alerts,
        ResolutionStep.sourceDefault,
        '${sp.name} · source default',
      );
    }
    final gp =
        rules.profile(rules.globalDefaultProfileId) ??
        rules.profile(BuiltInProfiles.defaultId)!;
    return _Decision(
      gp,
      gp.alerts,
      ResolutionStep.globalDefault,
      '${gp.name} · default',
    );
  }
}

class _Decision {
  _Decision(this.profile, this.alerts, this.step, this.explanation);

  final AlertProfile profile;
  final List<AlertSpec> alerts;
  final ResolutionStep step;
  final String explanation;

  ResolvedOccurrence toResolved(EventOccurrence o) => ResolvedOccurrence(
    occurrence: o,
    profile: profile,
    alerts: List.unmodifiable(alerts),
    explanation: explanation,
    silenced: false,
    step: step,
  );
}
```

- [ ] **Step 6: Run the tests and analyzer**

Run: `flutter test test/core/rules/rules_engine_test.dart && flutter analyze`
Expected: `+32: All tests passed!`, then `No issues found!`

- [ ] **Step 7: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 8: Commit**

```bash
dart format lib/core/rules test/core/rules
git add lib/core/rules test/core/rules
git commit -m "Add rules engine with resolution order and explanations" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Quiet modes in the rules engine

**Files:**
- Modify: `lib/core/rules/rules_engine.dart` (imports; `resolve()`)
- Test: `test/core/rules/quiet_modes_test.dart`

**Interfaces:**
- Consumes: `QuietState` family (Task 4), `RulesEngine` (Task 5), rules test helpers.
- Produces: no new API. `resolve()` now returns `silenced: true`, `alerts: []` and `Silenced · <label>` when the quiet mode covers the occurrence and lets nothing through. Mute and Pause let through `ringsInQuietMode` profiles and occurrence overrides with `enabled == true`. Vacation lets through only occurrence overrides with `enabled == true`.

- [ ] **Step 1: Write the failing test**

`test/core/rules/quiet_modes_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';
import 'package:tminus/core/rules/rule_set.dart';
import 'package:tminus/core/rules/rules_engine.dart';

import '../fixtures.dart';
import 'rules_test_helpers.dart';

void main() {
  final plain = occ();
  final tentative = occ(uid: 't', busyStatus: BusyStatus.tentative);
  final recurring = occ(uid: 'rec', seriesUid: 'series-1');
  final noon = occ(uid: 'noon', start: DateTime.utc(2026, 10, 6, 12));

  final mute = MuteToday(DateTime.utc(2026, 10, 7, 5));
  final pause = PausedUntil(DateTime.utc(2026, 10, 6, 12)); // 14:00 SAST
  final vacation = Vacation(LocalDate(2026, 10, 6), LocalDate(2026, 10, 9));

  final cases = <Case>[
    // Quiet modes
    Case(
      'mute silences Meeting',
      plain,
      RuleSet(quiet: mute),
      'Silenced · Mute today',
      const [],
      step: ResolutionStep.globalDefault,
      silenced: true,
    ),
    Case(
      'mute lets Important through',
      plain,
      RuleSet(quiet: mute, sourceDefaults: {'work': 'important'}),
      'Important · source default',
      importantAlerts,
      step: ResolutionStep.sourceDefault,
    ),
    Case(
      'pause shows its local end time',
      plain,
      RuleSet(quiet: pause),
      'Silenced · Paused until 14:00',
      const [],
      step: ResolutionStep.globalDefault,
      silenced: true,
    ),
    Case(
      'pause does not cover an event starting at its end',
      noon,
      RuleSet(quiet: pause),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'expired pause silences nothing',
      plain,
      RuleSet(quiet: PausedUntil(DateTime.utc(2026, 10, 6, 5))),
      'Meeting · default',
      meetingAlerts,
      step: ResolutionStep.globalDefault,
    ),
    Case(
      'mute lets an occurrence turned on through',
      plain,
      RuleSet(quiet: mute, overrides: [onOcc(plain, enabled: true)]),
      'Meeting · this event',
      meetingAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'mute silences an occurrence override that only picks a profile',
      plain,
      RuleSet(
        quiet: mute,
        overrides: [onOcc(plain, profileId: 'quick')],
      ),
      'Silenced · Mute today',
      const [],
      step: ResolutionStep.occurrenceOverride,
      silenced: true,
    ),
    Case(
      'vacation silences Important too',
      plain,
      RuleSet(quiet: vacation, sourceDefaults: {'work': 'important'}),
      'Silenced · Vacation',
      const [],
      step: ResolutionStep.sourceDefault,
      silenced: true,
      profileId: 'important',
    ),
    Case(
      'vacation silences an Important series override',
      recurring,
      RuleSet(
        quiet: vacation,
        overrides: [onSeries('series-1', profileId: 'important')],
      ),
      'Silenced · Vacation',
      const [],
      step: ResolutionStep.seriesOverride,
      silenced: true,
    ),
    Case(
      'vacation lets an occurrence turned on through',
      plain,
      RuleSet(
        quiet: vacation,
        overrides: [onOcc(plain, profileId: 'quick', enabled: true)],
      ),
      'Quick · this event',
      quickAlerts,
      step: ResolutionStep.occurrenceOverride,
    ),
    Case(
      'quiet mode leaves Silent explanations alone',
      tentative,
      RuleSet(quiet: mute),
      'Silent · tentative',
      const [],
      step: ResolutionStep.skipFilter,
    ),
    Case(
      'quiet mode leaves Off explanations alone',
      plain,
      RuleSet(quiet: vacation, overrides: [onOcc(plain, enabled: false)]),
      'Off · this event',
      const [],
      step: ResolutionStep.occurrenceOverride,
    ),
  ];

  RulesEngine engine() => RulesEngine(zone: johannesburg, clock: () => now);

  runCases(cases, engine);

  test('vacation days follow the local zone (London, BST)', () {
    final london9 = occ(start: DateTime.utc(2026, 10, 9, 23, 30)); // 00:30 10th
    final v = Vacation(LocalDate(2026, 10, 6), LocalDate(2026, 10, 9));
    final londonEngine = RulesEngine(zone: london, clock: () => now);
    expect(londonEngine.resolve(london9, RuleSet(quiet: v)).silenced, isFalse);
    expect(engine().resolve(london9, RuleSet(quiet: v)).silenced, isFalse);
    final late9 = occ(start: DateTime.utc(2026, 10, 9, 22, 30)); // 23:30 BST
    expect(londonEngine.resolve(late9, RuleSet(quiet: v)).silenced, isTrue);
    // Same instant is 00:30 on the 10th in Johannesburg.
    expect(engine().resolve(late9, RuleSet(quiet: v)).silenced, isFalse);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/rules/quiet_modes_test.dart`
Expected: FAIL. The compile succeeds, but the silencing cases fail, e.g. `mute silences Meeting` with `Expected: 'Silenced · Mute today'  Actual: 'Meeting · default'`.

- [ ] **Step 3: Add the import**

In `lib/core/rules/rules_engine.dart`, after `import '../model/keyword_rule.dart';` add:

```dart
import '../model/quiet_state.dart';
```

- [ ] **Step 4: Replace `resolve()`**

Replace this method:

```dart
  ResolvedOccurrence resolve(EventOccurrence o, RuleSet rules) {
    final occ = rules.occurrenceOverride(o.key);
    final ser = rules.seriesOverride(o.seriesUid);
    return _decide(o, rules, occ, ser).toResolved(o);
  }
```

with:

```dart
  ResolvedOccurrence resolve(EventOccurrence o, RuleSet rules) {
    final occ = rules.occurrenceOverride(o.key);
    final ser = rules.seriesOverride(o.seriesUid);
    final d = _decide(o, rules, occ, ser);
    if (d.alerts.isEmpty) return d.toResolved(o);

    final quiet = rules.quiet;
    if (!quiet.covers(o.startUtc, nowUtc: clock(), zone: zone)) {
      return d.toResolved(o);
    }
    final turnedOn = occ?.enabled == true;
    final letThrough = switch (quiet) {
      QuietUntil() => turnedOn || d.profile.ringsInQuietMode,
      Vacation() => turnedOn,
      QuietNone() => true,
    };
    if (letThrough) return d.toResolved(o);
    return ResolvedOccurrence(
      occurrence: o,
      profile: d.profile,
      alerts: const [],
      explanation: 'Silenced · ${quiet.label(zone)}',
      silenced: true,
      step: d.step,
    );
  }
```

- [ ] **Step 5: Run the tests and analyzer**

Run: `flutter test test/core/rules && flutter analyze`
Expected: `+45: All tests passed!` (32 + 13), then `No issues found!`

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
dart format lib/core/rules/rules_engine.dart test/core/rules/quiet_modes_test.dart
git add lib/core/rules/rules_engine.dart test/core/rules/quiet_modes_test.dart
git commit -m "Apply quiet modes after profile resolution" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Planner

**Files:**
- Create: `lib/core/planner/acknowledgements.dart`, `lib/core/planner/plan_builder.dart`
- Test: `test/core/planner/plan_builder_test.dart`

**Interfaces:**
- Consumes: `PlannedAlert`, `EventSnapshot`, `AlertSpec` (Task 1), `ResolvedOccurrence` (Task 5).
- Produces:
  - `Acknowledgements({Iterable<(String occurrenceKey, DateTime startUtc)> occurrences = const [], Iterable<(String alertId, DateTime startUtc)> alerts = const []})`, `static final Acknowledgements empty`, `bool isOccurrenceAcked(String occurrenceKey, DateTime startUtc)`, `bool isAlertDismissed(String alertId, DateTime occurrenceStartUtc)`
  - `List<PlannedAlert> buildPlan(Iterable<ResolvedOccurrence> resolved, {required DateTime now, Acknowledgements? acknowledgements})`. This includes every alert (past ones too) of each occurrence with `endUtc > now`, except acked occurrences and dismissed alerts. Ended occurrences contribute nothing.

- [ ] **Step 1: Write the failing test**

These cover spec §11 Planner: stable ids across rebuilds, Dismiss-all, a moved meeting re-arms and coalescing. Under roadmap §3, past alerts of a meeting that has **not ended yet are kept**, so Kotlin keeps its snoozes, and every alert of an ended meeting is dropped. They also cover acks that still apply to a running meeting, single Dismiss, and duplicate offsets (Review Focus 1).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/planner/acknowledgements.dart';
import 'package:tminus/core/planner/plan_builder.dart';
import 'package:tminus/core/rules/resolved_occurrence.dart';

import '../fixtures.dart';

final now = DateTime.utc(2026, 10, 6, 6);

ResolvedOccurrence resolved(
  EventOccurrence o, {
  AlertProfile profile = BuiltInProfiles.meeting,
  List<AlertSpec>? alerts,
}) => ResolvedOccurrence(
  occurrence: o,
  profile: profile,
  alerts: alerts ?? profile.alerts,
  explanation: '${profile.name} · default',
  silenced: false,
  step: ResolutionStep.globalDefault,
);

void main() {
  final standup = occ(
    uid: 'standup',
    title: 'Daily standup',
    start: DateTime.utc(2026, 10, 6, 6, 45),
    location: 'Teams',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/1',
  );
  final planning = occ(uid: 'planning', start: DateTime.utc(2026, 10, 6, 8));

  test('fireAt = start − offset, with id, group, snapshot and sound', () {
    const loud = SoundSettings(toneUri: 'content://tone/9', vibrate: false);
    final profile = BuiltInProfiles.quick.copyWith(sound: loud);
    final plan = buildPlan([resolved(standup, profile: profile)], now: now);

    expect(plan, hasLength(1));
    final a = plan.single;
    expect(a.id, PlannedAlert.idFor(standup.key, 1));
    expect(a.occurrenceKey, standup.key);
    expect(a.fireAtUtc, DateTime.utc(2026, 10, 6, 6, 44));
    expect(a.offsetMinutes, 1);
    expect(a.strength, AlertStrength.alarm);
    expect(a.sound, loud);
    expect(a.coalesceGroup, '2026-10-06T06:44Z');
    expect(a.event.title, 'Daily standup');
    expect(a.event.startUtc, standup.startUtc);
    expect(a.event.endUtc, standup.endUtc);
    expect(a.event.location, 'Teams');
    expect(a.event.joinUrl, standup.joinUrl);
    expect(a.event.color, blue);
  });

  test('sorted by fireAt, then id', () {
    final twin = occ(uid: 'twin', start: DateTime.utc(2026, 10, 6, 8));
    final plan = buildPlan([
      resolved(planning),
      resolved(standup),
      resolved(twin),
    ], now: now);
    final times = plan.map((a) => a.fireAtUtc).toList();
    expect(times, [...times]..sort());
    final atSameMinute = plan.where(
      (a) => a.fireAtUtc == DateTime.utc(2026, 10, 6, 7, 50),
    );
    expect(
      atSameMinute.map((a) => a.id),
      [...atSameMinute.map((a) => a.id)]..sort(),
    );
  });

  test('ids are stable across rebuilds', () {
    final first = buildPlan([resolved(planning)], now: now);
    final again = buildPlan([
      resolved(planning.copyWith(title: 'Renamed')),
    ], now: now.add(const Duration(minutes: 5)));
    expect(again.map((a) => a.id), first.map((a) => a.id));
  });

  test('past alerts of an occurrence that has not ended are kept', () {
    // planning: 08:00–08:30; headsUp −10 at 07:50, alarm −1 at 07:59.
    // Kotlin needs the occurrenceKey in the plan to keep a snooze alive.
    final duringMeeting = buildPlan([
      resolved(planning),
    ], now: DateTime.utc(2026, 10, 6, 8, 15));
    expect(duringMeeting.map((a) => a.offsetMinutes), [10, 1]);
    expect(duringMeeting.map((a) => a.fireAtUtc), [
      DateTime.utc(2026, 10, 6, 7, 50),
      DateTime.utc(2026, 10, 6, 7, 59),
    ]);
    final oneMinuteBeforeEnd = buildPlan([
      resolved(planning),
    ], now: DateTime.utc(2026, 10, 6, 8, 29));
    expect(oneMinuteBeforeEnd, hasLength(2));
  });

  test('every alert of an occurrence that has ended is dropped', () {
    expect(
      buildPlan([resolved(planning)], now: DateTime.utc(2026, 10, 6, 8, 30)),
      isEmpty,
      reason: 'endUtc == now counts as ended',
    );
    final plan = buildPlan([
      resolved(planning),
      resolved(standup), // 06:45–07:15, ended
    ], now: DateTime.utc(2026, 10, 6, 7, 20));
    expect(plan.map((a) => a.occurrenceKey).toSet(), {planning.key});
  });

  test('acks still drop past alerts of a running occurrence', () {
    final now = DateTime.utc(2026, 10, 6, 8, 5);
    expect(
      buildPlan(
        [resolved(planning)],
        now: now,
        acknowledgements: Acknowledgements(
          occurrences: [(planning.key, planning.startUtc)],
        ),
      ),
      isEmpty,
    );
    final plan = buildPlan(
      [resolved(planning)],
      now: now,
      acknowledgements: Acknowledgements(
        alerts: [(PlannedAlert.idFor(planning.key, 10), planning.startUtc)],
      ),
    );
    expect(plan.map((a) => a.offsetMinutes), [1]);
  });

  test('occurrences with no alerts produce nothing', () {
    expect(
      buildPlan([
        resolved(planning, profile: BuiltInProfiles.silent),
      ], now: now),
      isEmpty,
    );
  });

  test('custom alerts in ResolvedOccurrence are what gets planned', () {
    final plan = buildPlan([
      resolved(planning, alerts: const [AlertSpec(15, AlertStrength.alarm)]),
    ], now: now);
    expect(plan.single.offsetMinutes, 15);
  });

  test('duplicate offsets collapse to one alert, preferring the alarm', () {
    final plan = buildPlan([
      resolved(
        planning,
        alerts: const [
          AlertSpec(5, AlertStrength.alarm),
          AlertSpec(5, AlertStrength.headsUp),
        ],
      ),
    ], now: now);
    expect(plan, hasLength(1));
    expect(plan.single.strength, AlertStrength.alarm);
  });

  group('acknowledgements', () {
    test('Dismiss all drops every alert of that occurrence', () {
      final acks = Acknowledgements(
        occurrences: [(planning.key, planning.startUtc)],
      );
      final plan = buildPlan(
        [resolved(planning), resolved(standup)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.occurrenceKey).toSet(), {standup.key});
    });

    test('a moved meeting re-arms after Dismiss all', () {
      final acks = Acknowledgements(
        occurrences: [(planning.key, planning.startUtc)],
      );
      final moved = planning.copyWith(
        startUtc: DateTime.utc(2026, 10, 6, 9),
        endUtc: DateTime.utc(2026, 10, 6, 9, 30),
      );
      final plan = buildPlan(
        [resolved(moved)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.fireAtUtc), [
        DateTime.utc(2026, 10, 6, 8, 50),
        DateTime.utc(2026, 10, 6, 8, 59),
      ]);
      expect(plan.first.id, PlannedAlert.idFor(planning.key, 10));
    });

    test('single Dismiss drops only that alert', () {
      final headsUpId = PlannedAlert.idFor(planning.key, 10);
      final acks = Acknowledgements(alerts: [(headsUpId, planning.startUtc)]);
      final plan = buildPlan(
        [resolved(planning)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.offsetMinutes), [1]);
    });

    test('single Dismiss re-arms when the meeting moves', () {
      final headsUpId = PlannedAlert.idFor(planning.key, 10);
      final acks = Acknowledgements(alerts: [(headsUpId, planning.startUtc)]);
      final moved = planning.copyWith(startUtc: DateTime.utc(2026, 10, 6, 9));
      final plan = buildPlan(
        [resolved(moved)],
        now: now,
        acknowledgements: acks,
      );
      expect(plan.map((a) => a.offsetMinutes), [10, 1]);
    });
  });

  test('alerts in the same UTC minute share a coalesce group', () {
    final other = occ(
      sourceId: 'personal',
      uid: 'x',
      start: DateTime.utc(2026, 10, 6, 8),
    );
    final plan = buildPlan([resolved(planning), resolved(other)], now: now);
    final groups = <String, List<String>>{};
    for (final a in plan) {
      groups.putIfAbsent(a.coalesceGroup, () => []).add(a.occurrenceKey);
    }
    expect(
      groups['2026-10-06T07:50Z'],
      unorderedEquals([planning.key, other.key]),
    );
    expect(
      groups['2026-10-06T07:59Z'],
      unorderedEquals([planning.key, other.key]),
    );
    expect(plan.map((a) => a.id).toSet(), hasLength(4));
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/planner/plan_builder_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/planner/acknowledgements.dart'".

- [ ] **Step 3: Implement `Acknowledgements`**

```dart
/// User acknowledgements the planner must respect (spec §6, roadmap §3
/// "Engine rules"). Built from `alert_history` by
/// `AlertHistoryRepository.acknowledgements()`.
///
/// - Dismiss all / Join: every alert of the occurrence is dropped while its
///   start is unchanged. Keyed by (occurrenceKey, startUtc), so a moved
///   meeting re-arms.
/// - Dismiss / Stop: one alert is dropped. Kotlin keys this by
///   (alertId, fireAtUtc). EngineEvent JSON carries `startUtcMs` but not the
///   fire time, so Dart keys it by (alertId, startUtc). The two are
///   equivalent: alertId fixes the offset, and fireAt = start − offset, so the
///   pair matches exactly when Kotlin's pair matches.
class Acknowledgements {
  Acknowledgements({
    Iterable<(String occurrenceKey, DateTime startUtc)> occurrences = const [],
    Iterable<(String alertId, DateTime startUtc)> alerts = const [],
  }) : _occurrences = {for (final (key, start) in occurrences) _k(key, start)},
       _alerts = {for (final (id, start) in alerts) _k(id, start)};

  static final empty = Acknowledgements();

  final Set<String> _occurrences;
  final Set<String> _alerts;

  bool isOccurrenceAcked(String occurrenceKey, DateTime startUtc) =>
      _occurrences.contains(_k(occurrenceKey, startUtc));

  bool isAlertDismissed(String alertId, DateTime occurrenceStartUtc) =>
      _alerts.contains(_k(alertId, occurrenceStartUtc));

  static String _k(String id, DateTime t) =>
      '$id|${t.toUtc().millisecondsSinceEpoch}';
}
```

- [ ] **Step 4: Implement `buildPlan`**

```dart
import '../model/alert.dart';
import '../model/planned_alert.dart';
import '../rules/resolved_occurrence.dart';
import 'acknowledgements.dart';

/// Turns resolved occurrences into the plan the native engine arms.
///
/// - fireAt = start − offset.
/// - Every alert of an occurrence is listed until the occurrence ends
///   (`endUtc > now`), even alerts whose fireAt has passed. Kotlin never arms
///   past alerts, but an occurrenceKey missing from the plan tells it the
///   meeting is gone, and it then drops that occurrence's snoozes (roadmap
///   §3 "Engine rules"). Occurrences that have ended are dropped entirely.
/// - Occurrences acked by Dismiss all / Join at the same start are dropped.
/// - Single alerts dismissed at the same start are dropped.
/// - Two alerts with the same offset would share an id, so only one is kept:
///   the alarm if either is an alarm.
/// - Sorted by fireAt, then id.
List<PlannedAlert> buildPlan(
  Iterable<ResolvedOccurrence> resolved, {
  required DateTime now,
  Acknowledgements? acknowledgements,
}) {
  final acks = acknowledgements ?? Acknowledgements.empty;
  final nowUtc = now.toUtc();
  final plan = <PlannedAlert>[];

  for (final r in resolved) {
    final o = r.occurrence;
    if (r.alerts.isEmpty) continue;
    if (!o.endUtc.isAfter(nowUtc)) continue;
    if (acks.isOccurrenceAcked(o.key, o.startUtc)) continue;

    final byOffset = <int, AlertSpec>{};
    for (final a in r.alerts) {
      final existing = byOffset[a.offsetMinutes];
      if (existing == null || a.strength == AlertStrength.alarm) {
        byOffset[a.offsetMinutes] = a;
      }
    }

    final snapshot = EventSnapshot(
      title: o.title,
      startUtc: o.startUtc,
      endUtc: o.endUtc,
      location: o.location,
      joinUrl: o.joinUrl,
      color: o.calendarColor,
    );

    for (final a in byOffset.values) {
      final fireAt = o.startUtc.subtract(Duration(minutes: a.offsetMinutes));
      final id = PlannedAlert.idFor(o.key, a.offsetMinutes);
      if (acks.isAlertDismissed(id, o.startUtc)) continue;
      plan.add(
        PlannedAlert(
          id: id,
          occurrenceKey: o.key,
          fireAtUtc: fireAt,
          offsetMinutes: a.offsetMinutes,
          strength: a.strength,
          sound: r.profile.sound,
          event: snapshot,
          coalesceGroup: PlannedAlert.groupFor(fireAt),
        ),
      );
    }
  }

  plan.sort((a, b) {
    final byTime = a.fireAtUtc.compareTo(b.fireAtUtc);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return plan;
}
```

- [ ] **Step 5: Run the tests and analyzer**

Run: `flutter test test/core/planner/plan_builder_test.dart && flutter analyze`
Expected: `+14: All tests passed!`, then `No issues found!`

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
dart format lib/core/planner test/core/planner
git add lib/core/planner test/core/planner
git commit -m "Build PlannedAlert plans with stable ids and acknowledgements" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Empty-feed guard

**Files:**
- Create: `lib/core/planner/empty_feed_guard.dart`
- Test: `test/core/planner/empty_feed_guard_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum EmptyFeedAction { accept, keepPrevious }`, `EmptyFeedVerdict(EmptyFeedAction action, int consecutiveEmpty)`, `EmptyFeedGuard.emptyResultsBeforeClearing == 2`, `static EmptyFeedVerdict EmptyFeedGuard.evaluate({required int previousCount, required int newCount, required int consecutiveEmpty})`. Plan 4 calls it after each successful fetch, applies the action, and stores `consecutiveEmpty` in `SourceSyncState.emptyStreak`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/planner/empty_feed_guard.dart';

void main() {
  EmptyFeedVerdict eval(int previous, int next, int streak) =>
      EmptyFeedGuard.evaluate(
        previousCount: previous,
        newCount: next,
        consecutiveEmpty: streak,
      );

  const accept0 = EmptyFeedVerdict(EmptyFeedAction.accept, 0);

  test('non-empty result is accepted and resets the counter', () {
    expect(eval(5, 3, 0), accept0);
    expect(eval(5, 3, 1), accept0);
    expect(eval(0, 3, 0), accept0);
  });

  test('empty after empty cache is accepted (nothing to lose)', () {
    expect(eval(0, 0, 0), accept0);
  });

  test('first empty result after some keeps the old occurrences', () {
    expect(
      eval(5, 0, 0),
      const EmptyFeedVerdict(EmptyFeedAction.keepPrevious, 1),
    );
  });

  test('second consecutive empty result clears', () {
    expect(eval(5, 0, 1), accept0);
  });

  test('a non-empty result in between restarts the count', () {
    var v = eval(5, 0, 0); // keep, streak 1
    v = eval(5, 4, v.consecutiveEmpty); // accept, streak 0
    v = eval(4, 0, v.consecutiveEmpty); // keep again
    expect(v, const EmptyFeedVerdict(EmptyFeedAction.keepPrevious, 1));
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/planner/empty_feed_guard_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/planner/empty_feed_guard.dart'".

- [ ] **Step 3: Implement**

```dart
/// What to do with a source's new fetch result (spec §9: "Feed returns 0
/// events where it previously had some → remove alarms only after two
/// consecutive empty results").
enum EmptyFeedAction {
  /// Replace the cached occurrences with the new result.
  accept,

  /// Keep the cached occurrences; the empty result may be a glitch.
  keepPrevious,
}

class EmptyFeedVerdict {
  const EmptyFeedVerdict(this.action, this.consecutiveEmpty);

  final EmptyFeedAction action;

  /// The counter to store for the source until its next fetch.
  final int consecutiveEmpty;

  @override
  bool operator ==(Object other) =>
      other is EmptyFeedVerdict &&
      other.action == action &&
      other.consecutiveEmpty == consecutiveEmpty;

  @override
  int get hashCode => Object.hash(action, consecutiveEmpty);

  @override
  String toString() => 'EmptyFeedVerdict(${action.name}, $consecutiveEmpty)';
}

/// Pure decision. Plan 4 calls [EmptyFeedGuard.evaluate] per source after a
/// successful fetch and stores [EmptyFeedVerdict.consecutiveEmpty] in
/// `sources.empty_streak`.
abstract final class EmptyFeedGuard {
  /// Empty results in a row needed before cached occurrences are dropped.
  static const emptyResultsBeforeClearing = 2;

  /// [previousCount]: occurrences currently cached for the source.
  /// [newCount]: occurrences in the new result.
  /// [consecutiveEmpty]: the stored counter.
  static EmptyFeedVerdict evaluate({
    required int previousCount,
    required int newCount,
    required int consecutiveEmpty,
  }) {
    if (newCount > 0 || previousCount == 0) {
      return const EmptyFeedVerdict(EmptyFeedAction.accept, 0);
    }
    final streak = consecutiveEmpty + 1;
    if (streak >= emptyResultsBeforeClearing) {
      return const EmptyFeedVerdict(EmptyFeedAction.accept, 0);
    }
    return EmptyFeedVerdict(EmptyFeedAction.keepPrevious, streak);
  }
}
```

- [ ] **Step 4: Run the tests and analyzer**

Run: `flutter test test/core/planner/empty_feed_guard_test.dart && flutter analyze`
Expected: `+5: All tests passed!`, then `No issues found!`

- [ ] **Step 5: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
dart format lib/core/planner/empty_feed_guard.dart test/core/planner/empty_feed_guard_test.dart
git add lib/core/planner/empty_feed_guard.dart test/core/planner/empty_feed_guard_test.dart
git commit -m "Add empty-feed guard: clear only after two empty results" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Drift database, schema 1, built-in seeding

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/model/alert_history_entry.dart`, `lib/core/model/sync_log_entry.dart`, `lib/core/storage/tables.dart`, `lib/core/storage/profile_mapping.dart`, `lib/core/storage/app_database.dart`
- Generate (and commit): `lib/core/storage/app_database.g.dart`
- Test: `test/core/storage/test_database.dart`, `test/core/storage/app_database_test.dart`

**Interfaces:**
- Consumes: model enums and classes from Tasks 2–4, `BuiltInProfiles`, `alertsToJson/alertsFromJson`.
- Produces:
  - `enum AlertEventType { fired, snoozed, dismissed, dismissedAll, joined, missed, missedSystem }`, `AlertHistoryEntry({type, alertId, occurrenceKey, startUtc, atUtc, snoozeUntilUtc?, title?})`
  - `enum SyncOutcome { success, notModified, emptyKept, networkError, httpError, parseError, otherError }`, `SyncLogEntry({sourceId?, atUtc, outcome, message?, occurrenceCount?, duration?})`
  - Tables (SQL names): `sources`, `occurrences`, `overrides`, `profiles`, `rules`, `quiet_state`, `alert_history`, `sync_log`, `settings`. Row classes `SourceRow`, `OccurrenceRow`, `OverrideRow`, `ProfileRow`, `RuleRow`, `QuietStateRow`, `AlertHistoryRow`, `SyncLogRow`, `SettingRow`. Enum `QuietKind { none, muteToday, pausedUntil, vacation }`.
  - `AppDatabase(QueryExecutor executor)`, `factory AppDatabase.open()` (drift_flutter, file `tminus.sqlite`), `schemaVersion == 1`, `Future<void> seedBuiltInProfiles()`
  - `ProfilesCompanion profileToCompanion(AlertProfile p, {required int position})`, `AlertProfile profileFromRow(ProfileRow r)`
  - Test helpers: `AppDatabase openTestDatabase()`, `Future<void> waitUntil(bool Function() condition, {Duration timeout})`

- [ ] **Step 1: Add the packages**

Run:

```bash
flutter pub add drift:^2.35.1 drift_flutter:^0.3.1 sqlite3:^3.7.0 dev:drift_dev:^2.35.1 dev:build_runner:^2.16.1
```

Expected: `Changed N dependencies!`. These versions were current on 2026-10-06. `drift_dev` 2.35.1 needs `drift >=2.30.0 <2.36.0`, and `build_runner` 2.16.1 and `drift_dev` both accept analyzer 13–14. `sqlite3` 3.x bundles SQLite through **build hooks**, and `sqlite3_flutter_libs` is end-of-life (`0.6.0+eol`, an empty package that `drift_flutter` still pulls in transitively). Do not add it yourself.

- [ ] **Step 2: Add the history and sync-log models**

`lib/core/model/alert_history_entry.dart`:

```dart
import 'utc.dart';

/// Engine event types (roadmap §3 EngineEvent `type`) plus [missedSystem],
/// which Plan 4 records when an alert's time passed by more than 2 min with
/// no `fired` record (spec §9).
enum AlertEventType {
  fired,
  snoozed,
  dismissed,
  dismissedAll,
  joined,
  missed,
  missedSystem,
}

/// One row of `alert_history`. Plan 4 maps each drained EngineEvent to one.
class AlertHistoryEntry {
  AlertHistoryEntry({
    required this.type,
    required this.alertId,
    required this.occurrenceKey,
    required DateTime startUtc,
    required DateTime atUtc,
    DateTime? snoozeUntilUtc,
    this.title,
  }) : startUtc = plainUtc(startUtc),
       atUtc = plainUtc(atUtc),
       snoozeUntilUtc = snoozeUntilUtc == null
           ? null
           : plainUtc(snoozeUntilUtc);

  final AlertEventType type;

  /// A `PlannedAlert.id`, or a snooze id ending in `:s`.
  final String alertId;
  final String occurrenceKey;

  /// The occurrence start the engine had when the event happened.
  final DateTime startUtc;

  /// When the event happened.
  final DateTime atUtc;
  final DateTime? snoozeUntilUtc;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is AlertHistoryEntry &&
      other.type == type &&
      other.alertId == alertId &&
      other.occurrenceKey == occurrenceKey &&
      other.startUtc == startUtc &&
      other.atUtc == atUtc &&
      other.snoozeUntilUtc == snoozeUntilUtc &&
      other.title == title;

  @override
  int get hashCode => Object.hash(
    type,
    alertId,
    occurrenceKey,
    startUtc,
    atUtc,
    snoozeUntilUtc,
    title,
  );

  @override
  String toString() => 'AlertHistoryEntry(${type.name}, $alertId, $atUtc)';
}
```

`lib/core/model/sync_log_entry.dart`:

```dart
import 'utc.dart';

/// Result of one source's sync attempt. Plan 4 may append values (stored by
/// name, so appending is safe); never rename one.
enum SyncOutcome {
  success,
  notModified,
  emptyKept,
  networkError,
  httpError,
  parseError,
  otherError,
}

class SyncLogEntry {
  SyncLogEntry({
    this.sourceId,
    required DateTime atUtc,
    required this.outcome,
    this.message,
    this.occurrenceCount,
    this.duration,
  }) : atUtc = plainUtc(atUtc);

  /// Null for a whole-run entry.
  final String? sourceId;
  final DateTime atUtc;
  final SyncOutcome outcome;

  /// Human-readable detail. Must never contain an ICS URL (spec §10).
  final String? message;
  final int? occurrenceCount;
  final Duration? duration;

  @override
  bool operator ==(Object other) =>
      other is SyncLogEntry &&
      other.sourceId == sourceId &&
      other.atUtc == atUtc &&
      other.outcome == outcome &&
      other.message == message &&
      other.occurrenceCount == occurrenceCount &&
      other.duration == duration;

  @override
  int get hashCode =>
      Object.hash(sourceId, atUtc, outcome, message, occurrenceCount, duration);

  @override
  String toString() => 'SyncLogEntry($sourceId, ${outcome.name}, $atUtc)';
}
```

- [ ] **Step 3: Write the test database helper and the failing database test**

`test/core/storage/test_database.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:tminus/core/storage/app_database.dart';

/// A fresh in-memory database. Close it in tearDown.
///
/// `closeStreamsSynchronously` keeps drift from leaving a timer behind when a
/// watch stream is cancelled, which Flutter's test binding reports as a
/// pending-timer failure.
AppDatabase openTestDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// Yields to the event loop until [condition] holds (for watch streams).
/// Fails after [timeout] instead of hanging.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
```

`test/core/storage/app_database_test.dart`:

```dart
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/profile_mapping.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('native SQLite loads under flutter test', () async {
    final row = await db
        .customSelect('SELECT sqlite_version() AS v')
        .getSingle();
    expect(row.read<String>('v'), matches(RegExp(r'^3\.\d+\.\d+$')));
  });

  test('schema version 1 with every table from spec §5', () async {
    expect(db.schemaVersion, 1);
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .get();
    expect(
      rows.map((r) => r.read<String>('name')),
      containsAll([
        'alert_history',
        'occurrences',
        'overrides',
        'profiles',
        'quiet_state',
        'rules',
        'settings',
        'sources',
        'sync_log',
      ]),
    );
  });

  test('built-in profiles are seeded in order', () async {
    final rows = await (db.select(
      db.profiles,
    )..orderBy([(p) => OrderingTerm.asc(p.position)])).get();
    expect(rows.map(profileFromRow).toList(), BuiltInProfiles.all);
  });

  test('seeding never overwrites an edited built-in', () async {
    await (db.update(db.profiles)..where((p) => p.id.equals('meeting'))).write(
      const ProfilesCompanion(name: Value('Work meeting')),
    );
    await db.seedBuiltInProfiles();
    final meeting = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals('meeting'))).getSingle();
    expect(meeting.name, 'Work meeting');
  });

  test(
    'foreign keys are on: deleting a source deletes its occurrences',
    () async {
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'work',
              name: 'Work',
              color: 0xFF6AA0F5,
              kind: SourceKind.ics,
            ),
          );
      await db
          .into(db.occurrences)
          .insert(
            OccurrencesCompanion.insert(
              occurrenceKey: 'work|a|2026-10-06T08:00:00.000Z',
              sourceId: 'work',
              uid: 'a',
              originalStartUtcMs: 0,
              title: 'x',
              startUtcMs: 0,
              endUtcMs: 1,
              allDay: false,
              busyStatus: BusyStatus.busy,
              declined: false,
              cancelled: false,
              calendarColor: 0,
            ),
          );
      await (db.delete(db.sources)..where((s) => s.id.equals('work'))).go();
      expect(await db.select(db.occurrences).get(), isEmpty);
    },
  );

  test('sources table has no column that could hold a URL', () async {
    final cols = await db.customSelect('PRAGMA table_info(sources)').get();
    final names = cols.map((c) => c.read<String>('name')).toList();
    expect(names, contains('secure_storage_key'));
    expect(names.where((n) => n.contains('url')), isEmpty);
  });
}
```

- [ ] **Step 4: Run it to make sure it fails**

Run: `flutter test test/core/storage/app_database_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/storage/app_database.dart'".

- [ ] **Step 5: Write the tables**

`lib/core/storage/tables.dart`:

```dart
import 'package:drift/drift.dart';

import '../model/alert_history_entry.dart';
import '../model/event_occurrence.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/source_config.dart';
import '../model/sync_log_entry.dart';

// Conventions for every table:
// - Instants are INTEGER milliseconds since the epoch, UTC, in columns ending
//   in `UtcMs`. Drift's own DateTime columns would read back as local time
//   and drop milliseconds; plain ints are explicit and match the channel JSON.
// - Enums are stored by name (`textEnum`), so appending a value is safe and
//   renaming one is a migration.
// - Row classes end in `Row` so they never clash with the domain classes.

/// Configured calendar sources (spec §5). Never stores an ICS URL; only the
/// key under which Plan 4 keeps it in flutter_secure_storage.
@DataClassName('SourceRow')
class Sources extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  TextColumn get kind => textEnum<SourceKind>()();
  TextColumn get deviceCalendarId => text().nullable()();
  TextColumn get secureStorageKey => text().nullable()();
  TextColumn get defaultProfileId => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get lastAttemptUtcMs => integer().nullable()();
  IntColumn get lastSuccessUtcMs => integer().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get httpEtag => text().nullable()();
  TextColumn get httpLastModified => text().nullable()();
  IntColumn get emptyStreak => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The occurrence cache: the latest good fetch per source (spec §5).
@DataClassName('OccurrenceRow')
@TableIndex(name: 'occurrences_start', columns: {#startUtcMs})
@TableIndex(name: 'occurrences_source', columns: {#sourceId})
class Occurrences extends Table {
  TextColumn get occurrenceKey => text()();
  TextColumn get sourceId =>
      text().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get uid => text()();
  IntColumn get originalStartUtcMs => integer()();
  TextColumn get seriesUid => text().nullable()();
  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  TextColumn get organizer => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get joinUrl => text().nullable()();
  IntColumn get startUtcMs => integer()();
  IntColumn get endUtcMs => integer()();
  BoolColumn get allDay => boolean()();
  TextColumn get busyStatus => textEnum<BusyStatus>()();
  BoolColumn get declined => boolean()();
  BoolColumn get cancelled => boolean()();
  IntColumn get calendarColor => integer()();

  /// Comma-separated [OccurrenceWarning] names; empty for none.
  TextColumn get warnings => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {occurrenceKey};
}

/// Per-occurrence and per-series overrides (spec §5). One row per target.
@DataClassName('OverrideRow')
class Overrides extends Table {
  TextColumn get scope => textEnum<OverrideScope>()();
  TextColumn get target => text()();
  TextColumn get profileId => text().nullable()();

  /// Alert list JSON (see `alertsToJson`), null = use the profile's list.
  TextColumn get customAlertsJson => text().nullable()();
  BoolColumn get enabled => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {scope, target};
}

/// Alert profiles, built-in and user-made (spec §6). Alerts are JSON, not a
/// child table: a profile's alerts are always read and written as a whole,
/// never queried on their own, their order is just list order, and the same
/// encoding serves `overrides.custom_alerts_json`.
@DataClassName('ProfileRow')
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get alertsJson => text()();
  TextColumn get soundJson => text()();
  BoolColumn get ringsInQuietMode => boolean()();
  BoolColumn get builtIn => boolean()();

  /// Display order in the Alerts tab.
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Keyword rules (spec §6), run in [position] order.
@DataClassName('RuleRow')
class KeywordRules extends Table {
  @override
  String get tableName => 'rules';

  TextColumn get id => text()();
  IntColumn get position => integer()();
  TextColumn get field => textEnum<RuleField>()();

  /// `match` is an SQL keyword, hence the longer name.
  TextColumn get matchType => textEnum<RuleMatch>()();
  TextColumn get pattern => text()();
  TextColumn get profileId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// How a [QuietStates] row is to be read.
enum QuietKind { none, muteToday, pausedUntil, vacation }

/// The current quiet mode: at most one row, id 1.
@DataClassName('QuietStateRow')
class QuietStates extends Table {
  @override
  String get tableName => 'quiet_state';

  /// Always 1; `SettingsRepository` is the only writer.
  IntColumn get id => integer()();
  TextColumn get kind => textEnum<QuietKind>()();
  IntColumn get untilUtcMs => integer().nullable()();

  /// `yyyy-MM-dd`, local dates, inclusive.
  TextColumn get firstDay => text().nullable()();
  TextColumn get lastDay => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Engine events drained from Kotlin (spec §7), plus `missedSystem` rows
/// Plan 4 adds. De-duplicated on (type, alertId, atUtcMs) (roadmap §3).
@DataClassName('AlertHistoryRow')
@TableIndex(name: 'alert_history_start', columns: {#startUtcMs})
class AlertHistory extends Table {
  @override
  String get tableName => 'alert_history';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<AlertEventType>()();
  TextColumn get alertId => text()();
  TextColumn get occurrenceKey => text()();
  IntColumn get startUtcMs => integer()();
  IntColumn get atUtcMs => integer()();
  IntColumn get snoozeUntilUtcMs => integer().nullable()();

  /// Event title at the time, so Health's timeline survives cache pruning.
  TextColumn get title => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {type, alertId, atUtcMs},
  ];
}

/// One row per source per sync attempt (spec §5, §9).
@DataClassName('SyncLogRow')
@TableIndex(name: 'sync_log_at', columns: {#atUtcMs})
class SyncLog extends Table {
  @override
  String get tableName => 'sync_log';

  IntColumn get id => integer().autoIncrement()();

  /// Null for a whole-run entry (e.g. "applyPlan failed").
  TextColumn get sourceId => text().nullable()();
  IntColumn get atUtcMs => integer()();
  TextColumn get outcome => textEnum<SyncOutcome>()();
  TextColumn get message => text().nullable()();
  IntColumn get occurrenceCount => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
}

/// Small key/value settings: skip filters (JSON), global default profile id,
/// and later the theme mode (Plan 5).
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}
```

- [ ] **Step 6: Write the profile mapping and the database**

`lib/core/storage/profile_mapping.dart`:

```dart
import 'dart:convert';

import '../model/alert.dart';
import '../model/alert_profile.dart';
import 'app_database.dart';

/// Row ↔ domain mapping for profiles. Shared by [AppDatabase] seeding and
/// `ProfileRepository`.
ProfilesCompanion profileToCompanion(AlertProfile p, {required int position}) =>
    ProfilesCompanion.insert(
      id: p.id,
      name: p.name,
      alertsJson: jsonEncode(alertsToJson(p.alerts)),
      soundJson: jsonEncode(p.sound.toJson()),
      ringsInQuietMode: p.ringsInQuietMode,
      builtIn: p.builtIn,
      position: position,
    );

AlertProfile profileFromRow(ProfileRow r) => AlertProfile(
  id: r.id,
  name: r.name,
  alerts: alertsFromJson(jsonDecode(r.alertsJson) as List<Object?>),
  sound: SoundSettings.fromJson(
    (jsonDecode(r.soundJson) as Map).cast<String, Object?>(),
  ),
  ringsInQuietMode: r.ringsInQuietMode,
  builtIn: r.builtIn,
);
```

`lib/core/storage/app_database.dart`. The model imports are used by the generated part file:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../model/alert_history_entry.dart';
import '../model/alert_profile.dart';
import '../model/event_occurrence.dart';
import '../model/event_override.dart';
import '../model/keyword_rule.dart';
import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import 'profile_mapping.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Sources,
    Occurrences,
    Overrides,
    Profiles,
    KeywordRules,
    QuietStates,
    AlertHistory,
    SyncLog,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Tests pass `DatabaseConnection(NativeDatabase.memory(),
  /// closeStreamsSynchronously: true)`.
  AppDatabase(super.executor);

  /// The on-device database (`tminus.sqlite` in the app's documents
  /// directory). Works in the UI isolate and in the headless sync isolate.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'tminus'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Schema 1 is the first release. Add `if (from < 2) { … }` steps
      // here when bumping [schemaVersion]; never edit a shipped step.
      throw UnsupportedError('No migration from schema $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await seedBuiltInProfiles();
    },
  );

  /// Inserts any missing built-in profile. Never overwrites an edited one.
  Future<void> seedBuiltInProfiles() async {
    await batch((b) {
      for (final (i, p) in BuiltInProfiles.all.indexed) {
        b.insert(
          profiles,
          profileToCompanion(p, position: i),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }
}
```

- [ ] **Step 7: Generate the drift code**

Run: `dart run build_runner build`
Expected: the first run compiles the builders (1–3 minutes on Windows) and ends with `Built with build_runner/aot in …s; wrote N outputs.` `lib/core/storage/app_database.g.dart` now exists. Do **not** add `--delete-conflicting-outputs`, because build_runner 2.16 ignores it with a warning.

- [ ] **Step 8: Run the tests (this also checks native SQLite under `flutter test`)**

Run: `flutter test test/core/storage/app_database_test.dart`
Expected: `+6: All tests passed!`. On the first run, the `sqlite3` build hook downloads its prebuilt, sha256-verified Windows DLL from the package's GitHub release into `.dart_tool/hooks_runner/shared/sqlite3/`, so the first run needs network access once. `NativeDatabase.memory()` then works with no further setup. This was verified on Windows 11 with Flutter 3.47: SQLite 3.53.4 loaded.

**Fallback if the hook can't download** (offline, proxy), which shows up as an error like "Failed to load dynamic library" or a hook download failure. Use Windows' own `winsqlite3.dll` for host builds only. Append this to `pubspec.yaml` (top level):

```yaml
hooks:
  user_defines:
    sqlite3:
      source:
        windows: system
        default: sqlite3
      name:
        windows: winsqlite3
```

Run `flutter pub get`, then re-run the test. Expected: `+6: All tests passed!` (verified: SQLite 3.51.1 from Windows 11's `C:\Windows\System32\winsqlite3.dll`). Android keeps the bundled SQLite because `default: sqlite3` still applies there.

- [ ] **Step 9: Analyze and run the whole suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` (generated code carries `// ignore_for_file: type=lint`), then `All tests passed!`

- [ ] **Step 10: Commit, including the generated file**

```bash
dart format lib/core/model/alert_history_entry.dart lib/core/model/sync_log_entry.dart lib/core/storage/tables.dart lib/core/storage/profile_mapping.dart lib/core/storage/app_database.dart test/core/storage
git add pubspec.yaml pubspec.lock lib/core/model/alert_history_entry.dart lib/core/model/sync_log_entry.dart lib/core/storage test/core/storage
git commit -m "Add drift database schema 1 with seeded built-in profiles" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

`git status` must show `lib/core/storage/app_database.g.dart` as committed. It is not gitignored. See Global Constraints for why generated files are committed.

---

### Task 10: Source and occurrence repositories

**Files:**
- Create: `lib/core/storage/source_repository.dart`, `lib/core/storage/occurrence_repository.dart`
- Test: `test/core/storage/cache_storage_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (Task 9), `SourceConfig`, `SourceSyncState`, `EventOccurrence`.
- Produces (Plans 4/5 rely on these exact signatures):
  - `SourceRepository(AppDatabase db)`:
    `Future<List<SourceConfig>> all()` (by name), `Stream<List<SourceConfig>> watchAll()`, `Future<SourceConfig?> byId(String id)`, `Future<void> save(SourceConfig s)` (config only; never resets sync state), `Future<void> delete(String id)` (cascades occurrences), `Future<SourceSyncState?> syncState(String id)`, `Stream<SourceSyncState?> watchSyncState(String id)`, `Future<void> updateSyncState(String id, SourceSyncState s)`
  - `OccurrenceRepository(AppDatabase db)`:
    `Future<void> replaceForSource(String sourceId, List<EventOccurrence> occurrences)` (one transaction; `ArgumentError` on a foreign occurrence), `Future<int> countForSource(String sourceId)`, `Future<List<EventOccurrence>> between(DateTime fromUtc, DateTime toUtc)` (overlap: ends after `from`, starts before `to`, sorted by start then key), `Stream<List<EventOccurrence>> watchBetween(DateTime fromUtc, DateTime toUtc)`, `Future<EventOccurrence?> byKey(String occurrenceKey)`, `Future<int> deleteEndedBefore(DateTime cutoffUtc)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import '../fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;

  const work = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics_url_work',
    defaultProfileId: 'meeting',
  );
  const phone = SourceConfig(
    id: 'personal',
    name: 'Personal Google',
    color: 0xFF5BC27A,
    kind: SourceKind.device,
    deviceCalendarId: '7',
  );

  setUp(() async {
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    await sources.save(work);
    await sources.save(phone);
  });
  tearDown(() => db.close());

  group('SourceRepository', () {
    test('round trip, sorted by name', () async {
      expect(await sources.all(), [phone, work]);
      expect(await sources.byId('work'), work);
    });

    test('save updates config but never resets sync state', () async {
      final state = SourceSyncState(
        lastAttemptUtc: DateTime.utc(2026, 10, 6, 6),
        lastSuccessUtc: DateTime.utc(2026, 10, 6, 6),
        httpEtag: '"abc"',
        httpLastModified: 'Tue, 06 Oct 2026 06:00:00 GMT',
        emptyStreak: 1,
      );
      await sources.updateSyncState('work', state);
      await sources.save(work.copyWith(name: 'Work'));
      expect((await sources.byId('work'))!.name, 'Work');
      expect(await sources.syncState('work'), state);
    });

    test('a new source starts with an empty sync state', () async {
      expect(await sources.syncState('personal'), const SourceSyncState());
    });

    test('delete removes the source and its occurrences', () async {
      await cache.replaceForSource('work', [occ(sourceId: 'work')]);
      await sources.delete('work');
      expect(await sources.byId('work'), isNull);
      expect(await cache.countForSource('work'), 0);
    });
  });

  group('OccurrenceRepository', () {
    final full = occ(
      sourceId: 'work',
      uid: 'full',
      seriesUid: 'series-1',
      title: 'Sprint planning',
      location: 'Teams',
      organizer: 'Thandi M.',
      description: 'Agenda',
      joinUrl: 'https://teams.microsoft.com/l/meetup-join/1',
      busyStatus: BusyStatus.tentative,
      declined: true,
      cancelled: true,
      color: 0xFF112233,
    ).copyWith(warnings: {OccurrenceWarning.tzFallback});

    test('round trips every field', () async {
      await cache.replaceForSource('work', [full]);
      expect(await cache.byKey(full.key), full);
    });

    test('replaceForSource swaps one source only', () async {
      await cache.replaceForSource('work', [occ(sourceId: 'work', uid: 'a')]);
      await cache.replaceForSource('personal', [
        occ(sourceId: 'personal', uid: 'p'),
      ]);
      await cache.replaceForSource('work', [
        occ(sourceId: 'work', uid: 'b'),
        occ(sourceId: 'work', uid: 'c'),
      ]);
      expect(await cache.countForSource('work'), 2);
      expect(await cache.countForSource('personal'), 1);
    });

    test('replaceForSource rejects another source\'s occurrence', () async {
      expect(
        () => cache.replaceForSource('work', [occ(sourceId: 'personal')]),
        throwsArgumentError,
      );
    });

    test('between returns overlapping occurrences sorted by start', () async {
      DateTime at(int h, [int m = 0]) => DateTime.utc(2026, 10, 6, h, m);
      await cache.replaceForSource('work', [
        occ(sourceId: 'work', uid: 'late', start: at(9)),
        occ(sourceId: 'work', uid: 'early', start: at(7)),
        occ(sourceId: 'work', uid: 'ended', start: at(5)), // ends 05:30
        occ(sourceId: 'work', uid: 'running', start: at(5, 45)), // ends 06:15
        occ(sourceId: 'work', uid: 'after', start: at(10)),
      ]);
      final got = await cache.between(at(6), at(10));
      expect(got.map((o) => o.uid), ['running', 'early', 'late']);
    });

    test('deleteEndedBefore prunes old occurrences', () async {
      await cache.replaceForSource('work', [
        occ(sourceId: 'work', uid: 'old', start: DateTime.utc(2026, 10, 1)),
        occ(sourceId: 'work', uid: 'new', start: DateTime.utc(2026, 10, 6)),
      ]);
      expect(await cache.deleteEndedBefore(DateTime.utc(2026, 10, 5)), 1);
      expect(await cache.countForSource('work'), 1);
    });
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/storage/cache_storage_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/storage/source_repository.dart'".

- [ ] **Step 3: Implement `SourceRepository`**

`save()` uses `insertOnConflictUpdate` with a companion that sets only the configuration columns, so the sync-state columns are never overwritten:

```dart
import 'package:drift/drift.dart';

import '../model/source_config.dart';
import 'app_database.dart';

class SourceRepository {
  SourceRepository(this._db);

  final AppDatabase _db;

  /// Sorted by name, then id.
  Future<List<SourceConfig>> all() => _ordered().map(_configFromRow).get();

  Stream<List<SourceConfig>> watchAll() =>
      _ordered().map(_configFromRow).watch();

  Future<SourceConfig?> byId(String id) =>
      _byId(id).map(_configFromRow).getSingleOrNull();

  /// Inserts or updates the configuration. Never touches the sync state.
  Future<void> save(SourceConfig s) => _db
      .into(_db.sources)
      .insertOnConflictUpdate(
        SourcesCompanion(
          id: Value(s.id),
          name: Value(s.name),
          color: Value(s.color),
          kind: Value(s.kind),
          deviceCalendarId: Value(s.deviceCalendarId),
          secureStorageKey: Value(s.secureStorageKey),
          defaultProfileId: Value(s.defaultProfileId),
          enabled: Value(s.enabled),
        ),
      );

  /// Deletes the source; its cached occurrences go with it (FK cascade).
  /// Plan 4 deletes the ICS URL from secure storage.
  Future<void> delete(String id) =>
      (_db.delete(_db.sources)..where((s) => s.id.equals(id))).go();

  Future<SourceSyncState?> syncState(String id) =>
      _byId(id).map(_syncFromRow).getSingleOrNull();

  Stream<SourceSyncState?> watchSyncState(String id) =>
      _byId(id).map(_syncFromRow).watchSingleOrNull();

  Future<void> updateSyncState(String id, SourceSyncState s) =>
      (_db.update(_db.sources)..where((r) => r.id.equals(id))).write(
        SourcesCompanion(
          lastAttemptUtcMs: Value(s.lastAttemptUtc?.millisecondsSinceEpoch),
          lastSuccessUtcMs: Value(s.lastSuccessUtc?.millisecondsSinceEpoch),
          lastError: Value(s.lastError),
          httpEtag: Value(s.httpEtag),
          httpLastModified: Value(s.httpLastModified),
          emptyStreak: Value(s.emptyStreak),
        ),
      );

  SimpleSelectStatement<$SourcesTable, SourceRow> _byId(String id) =>
      _db.select(_db.sources)..where((s) => s.id.equals(id));

  SimpleSelectStatement<$SourcesTable, SourceRow> _ordered() => _db.select(
    _db.sources,
  )..orderBy([(s) => OrderingTerm.asc(s.name), (s) => OrderingTerm.asc(s.id)]);

  static SourceConfig _configFromRow(SourceRow r) => SourceConfig(
    id: r.id,
    name: r.name,
    color: r.color,
    kind: r.kind,
    deviceCalendarId: r.deviceCalendarId,
    secureStorageKey: r.secureStorageKey,
    defaultProfileId: r.defaultProfileId,
    enabled: r.enabled,
  );

  static SourceSyncState _syncFromRow(SourceRow r) {
    DateTime? t(int? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return SourceSyncState(
      lastAttemptUtc: t(r.lastAttemptUtcMs),
      lastSuccessUtc: t(r.lastSuccessUtcMs),
      lastError: r.lastError,
      httpEtag: r.httpEtag,
      httpLastModified: r.httpLastModified,
      emptyStreak: r.emptyStreak,
    );
  }
}
```

- [ ] **Step 4: Implement `OccurrenceRepository`**

```dart
import 'package:drift/drift.dart';

import '../model/event_occurrence.dart';
import 'app_database.dart';

/// The occurrence cache (spec §5).
class OccurrenceRepository {
  OccurrenceRepository(this._db);

  final AppDatabase _db;

  /// Replaces every cached occurrence of [sourceId] in one transaction, so a
  /// reader never sees a half-written source. Throws [ArgumentError] if an
  /// occurrence belongs to another source.
  Future<void> replaceForSource(
    String sourceId,
    List<EventOccurrence> occurrences,
  ) {
    for (final o in occurrences) {
      if (o.sourceId != sourceId) {
        throw ArgumentError.value(
          o.key,
          'occurrences',
          'belongs to ${o.sourceId}, not $sourceId',
        );
      }
    }
    return _db.transaction(() async {
      await (_db.delete(
        _db.occurrences,
      )..where((r) => r.sourceId.equals(sourceId))).go();
      await _db.batch((b) {
        b.insertAll(
          _db.occurrences,
          occurrences.map(_toCompanion),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  Future<int> countForSource(String sourceId) {
    final count = _db.occurrences.occurrenceKey.count();
    return (_db.selectOnly(_db.occurrences)
          ..addColumns([count])
          ..where(_db.occurrences.sourceId.equals(sourceId)))
        .map((r) => r.read(count)!)
        .getSingle();
  }

  /// Occurrences overlapping [fromUtc, toUtc): they end after [fromUtc] and
  /// start before [toUtc]. Sorted by start, then key.
  Future<List<EventOccurrence>> between(DateTime fromUtc, DateTime toUtc) =>
      _between(fromUtc, toUtc).map(_fromRow).get();

  Stream<List<EventOccurrence>> watchBetween(
    DateTime fromUtc,
    DateTime toUtc,
  ) => _between(fromUtc, toUtc).map(_fromRow).watch();

  Future<EventOccurrence?> byKey(String occurrenceKey) =>
      (_db.select(_db.occurrences)
            ..where((r) => r.occurrenceKey.equals(occurrenceKey)))
          .map(_fromRow)
          .getSingleOrNull();

  /// Removes occurrences that ended before [cutoffUtc]. Returns the count.
  Future<int> deleteEndedBefore(DateTime cutoffUtc) =>
      (_db.delete(_db.occurrences)..where(
            (r) =>
                r.endUtcMs.isSmallerThanValue(cutoffUtc.millisecondsSinceEpoch),
          ))
          .go();

  SimpleSelectStatement<$OccurrencesTable, OccurrenceRow> _between(
    DateTime fromUtc,
    DateTime toUtc,
  ) => _db.select(_db.occurrences)
    ..where(
      (r) =>
          r.endUtcMs.isBiggerThanValue(fromUtc.millisecondsSinceEpoch) &
          r.startUtcMs.isSmallerThanValue(toUtc.millisecondsSinceEpoch),
    )
    ..orderBy([
      (r) => OrderingTerm.asc(r.startUtcMs),
      (r) => OrderingTerm.asc(r.occurrenceKey),
    ]);

  static OccurrencesCompanion _toCompanion(EventOccurrence o) =>
      OccurrencesCompanion.insert(
        occurrenceKey: o.key,
        sourceId: o.sourceId,
        uid: o.uid,
        originalStartUtcMs: o.originalStartUtc.millisecondsSinceEpoch,
        seriesUid: Value(o.seriesUid),
        title: o.title,
        location: Value(o.location),
        organizer: Value(o.organizer),
        description: Value(o.description),
        joinUrl: Value(o.joinUrl),
        startUtcMs: o.startUtc.millisecondsSinceEpoch,
        endUtcMs: o.endUtc.millisecondsSinceEpoch,
        allDay: o.allDay,
        busyStatus: o.busyStatus,
        declined: o.declined,
        cancelled: o.cancelled,
        calendarColor: o.calendarColor,
        warnings: Value(o.warnings.map((w) => w.name).join(',')),
      );

  static EventOccurrence _fromRow(OccurrenceRow r) {
    DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return EventOccurrence(
      sourceId: r.sourceId,
      uid: r.uid,
      originalStartUtc: t(r.originalStartUtcMs),
      seriesUid: r.seriesUid,
      title: r.title,
      location: r.location,
      organizer: r.organizer,
      description: r.description,
      joinUrl: r.joinUrl,
      startUtc: t(r.startUtcMs),
      endUtc: t(r.endUtcMs),
      allDay: r.allDay,
      busyStatus: r.busyStatus,
      declined: r.declined,
      cancelled: r.cancelled,
      calendarColor: r.calendarColor,
      warnings: {
        for (final name in r.warnings.split(','))
          if (name.isNotEmpty)
            ...OccurrenceWarning.values.where((w) => w.name == name),
      },
    );
  }
}
```

- [ ] **Step 5: Run the tests and analyzer**

Run: `flutter test test/core/storage/cache_storage_test.dart && flutter analyze`
Expected: `+9: All tests passed!`, then `No issues found!`

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
dart format lib/core/storage/source_repository.dart lib/core/storage/occurrence_repository.dart test/core/storage/cache_storage_test.dart
git add lib/core/storage/source_repository.dart lib/core/storage/occurrence_repository.dart test/core/storage/cache_storage_test.dart
git commit -m "Add source and occurrence cache repositories" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Profile, rule, override and settings repositories

**Files:**
- Create: `lib/core/storage/settings_repository.dart`, `lib/core/storage/profile_repository.dart`, `lib/core/storage/rule_repository.dart`, `lib/core/storage/override_repository.dart`
- Test: `test/core/storage/rules_storage_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `profileToCompanion/profileFromRow` (Task 9), `SourceRepository` (Task 10, in tests), model classes.
- Produces:
  - `SettingsRepository(AppDatabase db)`: `static const skipFiltersKey = 'skipFilters'`, `static const globalDefaultKey = 'globalDefaultProfileId'`, `Future<String?> getString(String name)`, `Stream<String?> watchString(String name)`, `Future<void> setString(String name, String value)`, `Future<SkipFilters> skipFilters()`, `Stream<SkipFilters> watchSkipFilters()`, `Future<void> setSkipFilters(SkipFilters)`, `Future<String> globalDefaultProfileId()`, `Future<void> setGlobalDefaultProfileId(String)`, `Future<QuietState> quietState()`, `Stream<QuietState> watchQuietState()`, `Future<void> setQuietState(QuietState)`
  - `ProfileRepository(AppDatabase db)`: `Future<List<AlertProfile>> all()`, `Stream<List<AlertProfile>> watchAll()`, `Future<AlertProfile?> byId(String id)`, `Future<void> save(AlertProfile)`, `Future<void> delete(String id)` (`StateError` for built-ins)
  - `RuleRepository(AppDatabase db)`: `Future<List<KeywordRule>> all()`, `Stream<List<KeywordRule>> watchAll()`, `Future<void> save(KeywordRule)`, `Future<void> delete(String id)`, `Future<void> reorder(List<String> idsInOrder)`
  - `OverrideRepository(AppDatabase db)`: `Future<List<EventOverride>> all()`, `Stream<List<EventOverride>> watchAll()`, `Future<EventOverride?> find(OverrideScope scope, String target)`, `Future<void> save(EventOverride)` (an empty override deletes the row), `Future<void> delete(OverrideScope scope, String target)`, `Future<void> setOccurrenceEnabled(String occurrenceKey, bool? enabled)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_profile.dart';
import 'package:tminus/core/model/event_override.dart';
import 'package:tminus/core/model/keyword_rule.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/model/skip_filters.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late ProfileRepository profiles;
  late RuleRepository rules;
  late OverrideRepository overrides;
  late SettingsRepository settings;

  const focus = AlertProfile(
    id: 'focus',
    name: 'Focus',
    alerts: [AlertSpec(3, AlertStrength.alarm)],
    sound: SoundSettings(toneUri: 'content://tone/2', gradualVolume: false),
    ringsInQuietMode: true,
  );

  setUp(() {
    db = openTestDatabase();
    profiles = ProfileRepository(db);
    rules = RuleRepository(db);
    overrides = OverrideRepository(db);
    settings = SettingsRepository(db);
  });
  tearDown(() => db.close());

  group('ProfileRepository', () {
    test(
      'lists built-ins first, then saved profiles in creation order',
      () async {
        await profiles.save(focus);
        await profiles.save(focus.copyWith().copyWithId('later'));
        final all = await profiles.all();
        expect(all.map((p) => p.id), [
          'meeting',
          'quick',
          'important',
          'silent',
          'focus',
          'later',
        ]);
        expect(all[4], focus);
      },
    );

    test('save cannot make a user profile built-in', () async {
      await profiles.save(
        const AlertProfile(id: 'sneaky', name: 'S', alerts: [], builtIn: true),
      );
      expect((await profiles.byId('sneaky'))!.builtIn, isFalse);
    });

    test('editing a built-in keeps it built-in and in place', () async {
      await profiles.save(
        BuiltInProfiles.meeting.copyWith(
          alerts: const [AlertSpec(5, AlertStrength.alarm)],
        ),
      );
      final all = await profiles.all();
      expect(all.first.id, 'meeting');
      expect(all.first.builtIn, isTrue);
      expect(all.first.alerts, const [AlertSpec(5, AlertStrength.alarm)]);
    });

    test('built-ins cannot be deleted', () async {
      expect(() => profiles.delete('meeting'), throwsStateError);
    });

    test('deleting a profile removes every reference to it', () async {
      await profiles.save(focus);
      final sources = SourceRepository(db);
      await sources.save(
        const SourceConfig(
          id: 'work',
          name: 'Work',
          color: 1,
          kind: SourceKind.ics,
          defaultProfileId: 'focus',
        ),
      );
      await rules.save(
        KeywordRule(
          id: 'r1',
          position: 0,
          field: RuleField.title,
          pattern: 'x',
          profileId: 'focus',
        ),
      );
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k1',
          profileId: 'focus',
        ),
      );
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k2',
          profileId: 'focus',
          enabled: true,
        ),
      );
      await settings.setGlobalDefaultProfileId('focus');

      await profiles.delete('focus');

      expect(await profiles.byId('focus'), isNull);
      expect((await sources.byId('work'))!.defaultProfileId, isNull);
      expect(await rules.all(), isEmpty);
      expect(await overrides.find(OverrideScope.occurrence, 'k1'), isNull);
      expect(
        await overrides.find(OverrideScope.occurrence, 'k2'),
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k2',
          enabled: true,
        ),
      );
      expect(await settings.globalDefaultProfileId(), 'meeting');
    });

    test('watchAll emits the current list, then again after a save', () async {
      final seen = <int>[];
      final sub = profiles.watchAll().listen((l) => seen.add(l.length));
      await waitUntil(() => seen.isNotEmpty);
      await profiles.save(focus);
      await waitUntil(() => seen.length == 2);
      await sub.cancel();
      expect(seen, [4, 5]);
    });
  });

  group('RuleRepository', () {
    KeywordRule rule(String id, int position) => KeywordRule(
      id: id,
      position: position,
      field: RuleField.title,
      match: RuleMatch.regex,
      pattern: '^$id',
      profileId: 'quick',
    );

    test('round trip and position order', () async {
      await rules.save(rule('b', 1));
      await rules.save(rule('a', 0));
      expect(await rules.all(), [rule('a', 0), rule('b', 1)]);
    });

    test('reorder and delete', () async {
      await rules.save(rule('a', 0));
      await rules.save(rule('b', 1));
      await rules.save(rule('c', 2));
      await rules.reorder(['c', 'a', 'b']);
      expect((await rules.all()).map((r) => r.id), ['c', 'a', 'b']);
      await rules.delete('a');
      expect((await rules.all()).map((r) => r.id), ['c', 'b']);
    });
  });

  group('OverrideRepository', () {
    test('round trip with custom alerts', () async {
      const o = EventOverride(
        scope: OverrideScope.series,
        target: 'series-1',
        profileId: 'important',
        customAlerts: [AlertSpec(20, AlertStrength.headsUp)],
        enabled: true,
      );
      await overrides.save(o);
      expect(await overrides.find(OverrideScope.series, 'series-1'), o);
      expect(
        await overrides.find(OverrideScope.occurrence, 'series-1'),
        isNull,
      );
    });

    test('saving an empty override deletes the row', () async {
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k',
          enabled: false,
        ),
      );
      await overrides.save(
        const EventOverride(scope: OverrideScope.occurrence, target: 'k'),
      );
      expect(await overrides.all(), isEmpty);
    });

    test('setOccurrenceEnabled keeps the profile and custom alerts', () async {
      await overrides.save(
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k',
          profileId: 'quick',
          customAlerts: [AlertSpec(2, AlertStrength.alarm)],
        ),
      );
      await overrides.setOccurrenceEnabled('k', false);
      expect(
        await overrides.find(OverrideScope.occurrence, 'k'),
        const EventOverride(
          scope: OverrideScope.occurrence,
          target: 'k',
          profileId: 'quick',
          customAlerts: [AlertSpec(2, AlertStrength.alarm)],
          enabled: false,
        ),
      );
      await overrides.setOccurrenceEnabled('fresh', true);
      expect(
        (await overrides.find(OverrideScope.occurrence, 'fresh'))!.enabled,
        isTrue,
      );
    });
  });

  group('SettingsRepository', () {
    test('skip filters default to all on and round trip', () async {
      expect(await settings.skipFilters(), const SkipFilters());
      await settings.setSkipFilters(const SkipFilters(tentative: false));
      expect(await settings.skipFilters(), const SkipFilters(tentative: false));
    });

    test('global default is Meeting until set', () async {
      expect(await settings.globalDefaultProfileId(), 'meeting');
      await settings.setGlobalDefaultProfileId('quick');
      expect(await settings.globalDefaultProfileId(), 'quick');
    });

    test('every quiet state round trips; none by default', () async {
      expect(await settings.quietState(), const QuietNone());
      final states = <QuietState>[
        MuteToday(DateTime.utc(2026, 10, 7, 5)),
        PausedUntil(DateTime.utc(2026, 10, 6, 12, 30)),
        Vacation(LocalDate(2026, 12, 20), LocalDate(2027, 1, 3)),
        const QuietNone(),
      ];
      for (final s in states) {
        await settings.setQuietState(s);
        expect(await settings.quietState(), s);
      }
    });

    test('an unreadable quiet row reads as none', () async {
      await db
          .into(db.quietStates)
          .insert(
            QuietStatesCompanion.insert(
              id: const Value(1),
              kind: QuietKind.vacation,
            ),
          );
      expect(await settings.quietState(), const QuietNone());
    });

    test('watchQuietState emits the current state, then changes', () async {
      final mute = MuteToday(DateTime.utc(2026, 10, 7, 5));
      final seen = <QuietState>[];
      final sub = settings.watchQuietState().listen(seen.add);
      await waitUntil(() => seen.isNotEmpty);
      await settings.setQuietState(mute);
      await waitUntil(() => seen.length == 2);
      await sub.cancel();
      expect(seen, [const QuietNone(), mute]);
    });
  });
}

extension on AlertProfile {
  AlertProfile copyWithId(String id) => AlertProfile(
    id: id,
    name: name,
    alerts: alerts,
    sound: sound,
    ringsInQuietMode: ringsInQuietMode,
  );
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/storage/rules_storage_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/storage/override_repository.dart'".

- [ ] **Step 3: Implement `SettingsRepository`**

```dart
import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/alert_profile.dart';
import '../model/local_date.dart';
import '../model/quiet_state.dart';
import '../model/skip_filters.dart';
import 'app_database.dart';

/// Skip filters, the global default profile, the quiet mode and free-form
/// string settings.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const skipFiltersKey = 'skipFilters';
  static const globalDefaultKey = 'globalDefaultProfileId';

  Future<String?> getString(String name) => _byName(name).getSingleOrNull();

  Stream<String?> watchString(String name) => _byName(name).watchSingleOrNull();

  Future<void> setString(String name, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(name: name, value: value),
      );

  Future<SkipFilters> skipFilters() async =>
      _decodeSkip(await getString(skipFiltersKey));

  Stream<SkipFilters> watchSkipFilters() =>
      watchString(skipFiltersKey).map(_decodeSkip);

  Future<void> setSkipFilters(SkipFilters filters) =>
      setString(skipFiltersKey, jsonEncode(filters.toJson()));

  /// Meeting unless the user picked another default.
  Future<String> globalDefaultProfileId() async =>
      await getString(globalDefaultKey) ?? BuiltInProfiles.defaultId;

  Future<void> setGlobalDefaultProfileId(String profileId) =>
      setString(globalDefaultKey, profileId);

  Future<QuietState> quietState() async =>
      _decodeQuiet(await _quietRow().getSingleOrNull());

  Stream<QuietState> watchQuietState() =>
      _quietRow().watchSingleOrNull().map(_decodeQuiet);

  Future<void> setQuietState(QuietState state) {
    final row = switch (state) {
      QuietNone() => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.none,
      ),
      MuteToday(:final untilUtc) => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.muteToday,
        untilUtcMs: Value(untilUtc.millisecondsSinceEpoch),
      ),
      PausedUntil(:final untilUtc) => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.pausedUntil,
        untilUtcMs: Value(untilUtc.millisecondsSinceEpoch),
      ),
      Vacation(:final firstDay, :final lastDay) => QuietStatesCompanion.insert(
        id: const Value(1),
        kind: QuietKind.vacation,
        firstDay: Value(firstDay.toIso()),
        lastDay: Value(lastDay.toIso()),
      ),
    };
    return _db
        .into(_db.quietStates)
        .insert(row, mode: InsertMode.insertOrReplace);
  }

  Selectable<String> _byName(String name) => (_db.select(
    _db.settings,
  )..where((s) => s.name.equals(name))).map((r) => r.value);

  SimpleSelectStatement<$QuietStatesTable, QuietStateRow> _quietRow() =>
      _db.select(_db.quietStates)..where((q) => q.id.equals(1));

  static SkipFilters _decodeSkip(String? json) => json == null
      ? const SkipFilters()
      : SkipFilters.fromJson((jsonDecode(json) as Map).cast<String, Object?>());

  /// A row that can't be read (e.g. a vacation with no dates) counts as
  /// "no quiet mode" rather than crashing the sync.
  static QuietState _decodeQuiet(QuietStateRow? r) {
    DateTime? until() => r?.untilUtcMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r!.untilUtcMs!, isUtc: true);
    switch (r?.kind) {
      case QuietKind.muteToday when until() != null:
        return MuteToday(until()!);
      case QuietKind.pausedUntil when until() != null:
        return PausedUntil(until()!);
      case QuietKind.vacation when r!.firstDay != null && r.lastDay != null:
        try {
          final first = LocalDate.parse(r.firstDay!);
          final last = LocalDate.parse(r.lastDay!);
          if (first <= last) return Vacation(first, last);
        } on FormatException {
          // Fall through to none.
        }
        return const QuietNone();
      default:
        return const QuietNone();
    }
  }
}
```

- [ ] **Step 4: Implement `ProfileRepository`**

```dart
import 'package:drift/drift.dart';

import '../model/alert_profile.dart';
import 'app_database.dart';
import 'profile_mapping.dart';
import 'settings_repository.dart';

class ProfileRepository {
  ProfileRepository(this._db);

  final AppDatabase _db;

  /// All profiles in display order (built-ins first, as seeded).
  Future<List<AlertProfile>> all() => _ordered().map(profileFromRow).get();

  Stream<List<AlertProfile>> watchAll() =>
      _ordered().map(profileFromRow).watch();

  Future<AlertProfile?> byId(String id) => (_db.select(
    _db.profiles,
  )..where((p) => p.id.equals(id))).map(profileFromRow).getSingleOrNull();

  /// Inserts or updates. A new profile goes to the end of the list. The
  /// stored `builtIn` flag always wins over [profile.builtIn], so a user
  /// profile can't become built-in and an edited built-in stays built-in.
  Future<void> save(AlertProfile profile) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(profile.id))).getSingleOrNull();
    if (existing == null) {
      final max = _db.profiles.position.max();
      final last = await (_db.selectOnly(
        _db.profiles,
      )..addColumns([max])).map((r) => r.read(max)).getSingle();
      await _db
          .into(_db.profiles)
          .insert(
            profileToCompanion(
              profile.copyWithBuiltIn(false),
              position: (last ?? -1) + 1,
            ),
          );
    } else {
      await _db
          .into(_db.profiles)
          .insertOnConflictUpdate(
            profileToCompanion(
              profile.copyWithBuiltIn(existing.builtIn),
              position: existing.position,
            ),
          );
    }
  });

  /// Deletes a user profile and every reference to it: source defaults are
  /// cleared, rules that target it are deleted, overrides drop the profile
  /// (and are deleted if nothing else is left), and a global default that
  /// named it goes back to Meeting. Throws [StateError] for a built-in.
  Future<void> delete(String id) => _db.transaction(() async {
    final row = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    if (row.builtIn) throw StateError('Built-in profile "$id" is fixed');

    await (_db.delete(_db.profiles)..where((p) => p.id.equals(id))).go();
    await (_db.update(_db.sources)..where((s) => s.defaultProfileId.equals(id)))
        .write(const SourcesCompanion(defaultProfileId: Value(null)));
    await (_db.delete(
      _db.keywordRules,
    )..where((r) => r.profileId.equals(id))).go();
    await (_db.update(_db.overrides)..where((o) => o.profileId.equals(id)))
        .write(const OverridesCompanion(profileId: Value(null)));
    await (_db.delete(_db.overrides)..where(
          (o) =>
              o.profileId.isNull() &
              o.customAlertsJson.isNull() &
              o.enabled.isNull(),
        ))
        .go();
    final settings = SettingsRepository(_db);
    if (await settings.globalDefaultProfileId() == id) {
      await settings.setGlobalDefaultProfileId(BuiltInProfiles.defaultId);
    }
  });

  SimpleSelectStatement<$ProfilesTable, ProfileRow> _ordered() =>
      _db.select(_db.profiles)..orderBy([
        (p) => OrderingTerm.asc(p.position),
        (p) => OrderingTerm.asc(p.id),
      ]);
}

extension on AlertProfile {
  AlertProfile copyWithBuiltIn(bool builtIn) => AlertProfile(
    id: id,
    name: name,
    alerts: alerts,
    sound: sound,
    ringsInQuietMode: ringsInQuietMode,
    builtIn: builtIn,
  );
}
```

- [ ] **Step 5: Implement `RuleRepository`**

```dart
import 'package:drift/drift.dart';

import '../model/keyword_rule.dart';
import 'app_database.dart';

class RuleRepository {
  RuleRepository(this._db);

  final AppDatabase _db;

  /// Sorted by position, then id.
  Future<List<KeywordRule>> all() => _ordered().map(_fromRow).get();

  Stream<List<KeywordRule>> watchAll() => _ordered().map(_fromRow).watch();

  Future<void> save(KeywordRule rule) =>
      _db.into(_db.keywordRules).insertOnConflictUpdate(_toCompanion(rule));

  Future<void> delete(String id) =>
      (_db.delete(_db.keywordRules)..where((r) => r.id.equals(id))).go();

  /// Sets each rule's position to its index in [idsInOrder] (drag to
  /// reorder). Ids not listed keep their position; unknown ids are ignored.
  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    for (final (i, id) in idsInOrder.indexed) {
      await (_db.update(_db.keywordRules)..where((r) => r.id.equals(id))).write(
        KeywordRulesCompanion(position: Value(i)),
      );
    }
  });

  SimpleSelectStatement<$KeywordRulesTable, RuleRow> _ordered() =>
      _db.select(_db.keywordRules)..orderBy([
        (r) => OrderingTerm.asc(r.position),
        (r) => OrderingTerm.asc(r.id),
      ]);

  static KeywordRulesCompanion _toCompanion(KeywordRule r) =>
      KeywordRulesCompanion.insert(
        id: r.id,
        position: r.position,
        field: r.field,
        matchType: r.match,
        pattern: r.pattern,
        profileId: r.profileId,
      );

  static KeywordRule _fromRow(RuleRow r) => KeywordRule(
    id: r.id,
    position: r.position,
    field: r.field,
    match: r.matchType,
    pattern: r.pattern,
    profileId: r.profileId,
  );
}
```

- [ ] **Step 6: Implement `OverrideRepository`**

```dart
import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/alert_profile.dart';
import '../model/event_override.dart';
import 'app_database.dart';

class OverrideRepository {
  OverrideRepository(this._db);

  final AppDatabase _db;

  Future<List<EventOverride>> all() =>
      _db.select(_db.overrides).map(_fromRow).get();

  Stream<List<EventOverride>> watchAll() =>
      _db.select(_db.overrides).map(_fromRow).watch();

  Future<EventOverride?> find(OverrideScope scope, String target) =>
      (_db.select(
            _db.overrides,
          )..where((o) => o.scope.equalsValue(scope) & o.target.equals(target)))
          .map(_fromRow)
          .getSingleOrNull();

  /// Upserts; an empty override (nothing set) deletes the row instead.
  Future<void> save(EventOverride o) {
    if (o.isEmpty) return delete(o.scope, o.target);
    return _db
        .into(_db.overrides)
        .insertOnConflictUpdate(
          OverridesCompanion.insert(
            scope: o.scope,
            target: o.target,
            profileId: Value(o.profileId),
            customAlertsJson: Value(
              o.customAlerts == null
                  ? null
                  : jsonEncode(alertsToJson(o.customAlerts!)),
            ),
            enabled: Value(o.enabled),
          ),
        );
  }

  Future<void> delete(OverrideScope scope, String target) => (_db.delete(
    _db.overrides,
  )..where((o) => o.scope.equalsValue(scope) & o.target.equals(target))).go();

  /// The Agenda toggle: sets or clears `enabled` on the occurrence override
  /// for [occurrenceKey], keeping any profile or custom alerts it has.
  Future<void> setOccurrenceEnabled(String occurrenceKey, bool? enabled) =>
      _db.transaction(() async {
        final existing = await find(OverrideScope.occurrence, occurrenceKey);
        await save(
          EventOverride(
            scope: OverrideScope.occurrence,
            target: occurrenceKey,
            profileId: existing?.profileId,
            customAlerts: existing?.customAlerts,
            enabled: enabled,
          ),
        );
      });

  static EventOverride _fromRow(OverrideRow r) => EventOverride(
    scope: r.scope,
    target: r.target,
    profileId: r.profileId,
    customAlerts: r.customAlertsJson == null
        ? null
        : alertsFromJson(jsonDecode(r.customAlertsJson!) as List<Object?>),
    enabled: r.enabled,
  );
}
```

- [ ] **Step 7: Run the tests and analyzer**

Run: `flutter test test/core/storage/rules_storage_test.dart && flutter analyze`
Expected: `+16: All tests passed!`, then `No issues found!`

- [ ] **Step 8: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 9: Commit**

```bash
dart format lib/core/storage/settings_repository.dart lib/core/storage/profile_repository.dart lib/core/storage/rule_repository.dart lib/core/storage/override_repository.dart test/core/storage/rules_storage_test.dart
git add lib/core/storage/settings_repository.dart lib/core/storage/profile_repository.dart lib/core/storage/rule_repository.dart lib/core/storage/override_repository.dart test/core/storage/rules_storage_test.dart
git commit -m "Add profile, rule, override and settings repositories" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Alert history (with acknowledgements) and sync log

**Files:**
- Create: `lib/core/storage/alert_history_repository.dart`, `lib/core/storage/sync_log_repository.dart`
- Test: `test/core/storage/history_storage_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `AlertHistoryEntry`, `SyncLogEntry` (Task 9), `Acknowledgements` (Task 7), `PlannedAlert.idFor` (Task 1).
- Produces:
  - `AlertHistoryRepository(AppDatabase db)`: `static const ackWindow = Duration(hours: 24)`, `Future<bool> record(AlertHistoryEntry)` (false when (type, alertId, atUtc) is already stored), `Future<List<AlertHistoryEntry>> recent({int limit = 100})` (newest first), `Stream<List<AlertHistoryEntry>> watchRecent({int limit = 100})`, `Future<List<AlertHistoryEntry>> since(DateTime sinceUtc)` (oldest first), `Future<Acknowledgements> acknowledgements({required DateTime nowUtc})`, `Future<int> deleteBefore(DateTime cutoffUtc)`
  - `SyncLogRepository(AppDatabase db)`: `Future<void> add(SyncLogEntry)`, `Future<List<SyncLogEntry>> recent({int limit = 50})`, `Future<SyncLogEntry?> latestForSource(String sourceId)`, `Future<int> deleteBefore(DateTime cutoffUtc)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late AlertHistoryRepository history;
  late SyncLogRepository syncLog;

  final now = DateTime.utc(2026, 10, 6, 6);
  final start = DateTime.utc(2026, 10, 6, 8);
  const key = 'work|abc|2026-10-06T08:00:00.000Z';
  final headsUpId = PlannedAlert.idFor(key, 10);

  AlertHistoryEntry entry(
    AlertEventType type, {
    String? alertId,
    DateTime? at,
    DateTime? startUtc,
    String? k,
  }) => AlertHistoryEntry(
    type: type,
    alertId: alertId ?? headsUpId,
    occurrenceKey: k ?? key,
    startUtc: startUtc ?? start,
    atUtc: at ?? DateTime.utc(2026, 10, 6, 7, 50),
  );

  setUp(() {
    db = openTestDatabase();
    history = AlertHistoryRepository(db);
    syncLog = SyncLogRepository(db);
  });
  tearDown(() => db.close());

  group('AlertHistoryRepository', () {
    test('record de-duplicates on (type, alertId, atUtc)', () async {
      expect(await history.record(entry(AlertEventType.fired)), isTrue);
      expect(await history.record(entry(AlertEventType.fired)), isFalse);
      expect(await history.record(entry(AlertEventType.dismissed)), isTrue);
      expect(await history.recent(), hasLength(2));
    });

    test('round trips every field; recent is newest first', () async {
      final snoozed = AlertHistoryEntry(
        type: AlertEventType.snoozed,
        alertId: headsUpId,
        occurrenceKey: key,
        startUtc: start,
        atUtc: DateTime.utc(2026, 10, 6, 7, 51),
        snoozeUntilUtc: DateTime.utc(2026, 10, 6, 7, 56),
        title: 'Sprint planning',
      );
      await history.record(entry(AlertEventType.fired));
      await history.record(snoozed);
      final recent = await history.recent();
      expect(recent.first, snoozed);
      expect(recent.last.type, AlertEventType.fired);
    });

    test('acknowledgements: Dismiss all and Join ack the occurrence', () async {
      await history.record(entry(AlertEventType.dismissedAll));
      await history.record(
        entry(
          AlertEventType.joined,
          k: 'work|j|2026-10-06T09:00:00.000Z',
          startUtc: DateTime.utc(2026, 10, 6, 9),
        ),
      );
      final acks = await history.acknowledgements(nowUtc: now);
      expect(acks.isOccurrenceAcked(key, start), isTrue);
      expect(
        acks.isOccurrenceAcked(
          'work|j|2026-10-06T09:00:00.000Z',
          DateTime.utc(2026, 10, 6, 9),
        ),
        isTrue,
      );
      expect(
        acks.isOccurrenceAcked(key, DateTime.utc(2026, 10, 6, 9)),
        isFalse,
        reason: 'moved meeting',
      );
      expect(acks.isAlertDismissed(headsUpId, start), isFalse);
    });

    test(
      'acknowledgements: single Dismiss acks one alert, not snoozes',
      () async {
        await history.record(entry(AlertEventType.dismissed));
        await history.record(
          entry(
            AlertEventType.dismissed,
            alertId: '${PlannedAlert.idFor(key, 1)}:s',
          ),
        );
        await history.record(
          entry(AlertEventType.fired, alertId: PlannedAlert.idFor(key, 1)),
        );
        final acks = await history.acknowledgements(nowUtc: now);
        expect(acks.isAlertDismissed(headsUpId, start), isTrue);
        expect(
          acks.isAlertDismissed(PlannedAlert.idFor(key, 1), start),
          isFalse,
        );
        expect(acks.isOccurrenceAcked(key, start), isFalse);
      },
    );

    test(
      'acknowledgements ignore occurrences that started over 24 h ago',
      () async {
        final old = DateTime.utc(2026, 10, 5, 5, 59);
        await history.record(entry(AlertEventType.dismissedAll, startUtc: old));
        final acks = await history.acknowledgements(nowUtc: now);
        expect(acks.isOccurrenceAcked(key, old), isFalse);
      },
    );

    test('since and deleteBefore', () async {
      await history.record(
        entry(AlertEventType.fired, at: DateTime.utc(2026, 9, 1)),
      );
      await history.record(
        entry(AlertEventType.fired, at: DateTime.utc(2026, 10, 6, 7)),
      );
      expect(await history.since(DateTime.utc(2026, 10, 1)), hasLength(1));
      expect(await history.deleteBefore(DateTime.utc(2026, 10, 1)), 1);
      expect(await history.recent(), hasLength(1));
    });
  });

  group('SyncLogRepository', () {
    test('add, recent, latestForSource, deleteBefore', () async {
      final a = SyncLogEntry(
        sourceId: 'work',
        atUtc: DateTime.utc(2026, 10, 6, 5),
        outcome: SyncOutcome.success,
        occurrenceCount: 23,
        duration: const Duration(milliseconds: 840),
      );
      final b = SyncLogEntry(
        sourceId: 'work',
        atUtc: DateTime.utc(2026, 10, 6, 6),
        outcome: SyncOutcome.networkError,
        message: 'Timed out after 20 s',
      );
      final run = SyncLogEntry(
        atUtc: DateTime.utc(2026, 10, 6, 6, 1),
        outcome: SyncOutcome.otherError,
        message: 'applyPlan failed',
      );
      await syncLog.add(a);
      await syncLog.add(b);
      await syncLog.add(run);
      expect(await syncLog.recent(), [run, b, a]);
      expect(await syncLog.latestForSource('work'), b);
      expect(await syncLog.latestForSource('personal'), isNull);
      expect(await syncLog.deleteBefore(DateTime.utc(2026, 10, 6, 5, 30)), 1);
    });
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/storage/history_storage_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/storage/alert_history_repository.dart'".

- [ ] **Step 3: Implement `AlertHistoryRepository`**

```dart
import 'package:drift/drift.dart';

import '../model/alert_history_entry.dart';
import '../planner/acknowledgements.dart';
import 'app_database.dart';

class AlertHistoryRepository {
  AlertHistoryRepository(this._db);

  final AppDatabase _db;

  /// How long an acknowledgement matters after the occurrence's start; the
  /// same window Kotlin prunes its ack store with (roadmap §3).
  static const ackWindow = Duration(hours: 24);

  /// Inserts [entry] unless the same (type, alertId, atUtc) is already stored
  /// (an event can arrive both live and from `drainEvents`). Returns true when
  /// a row was inserted.
  Future<bool> record(AlertHistoryEntry entry) => _db.transaction(() async {
    final at = entry.atUtc.millisecondsSinceEpoch;
    final duplicate =
        await (_db.select(_db.alertHistory)..where(
              (h) =>
                  h.type.equalsValue(entry.type) &
                  h.alertId.equals(entry.alertId) &
                  h.atUtcMs.equals(at),
            ))
            .getSingleOrNull();
    if (duplicate != null) return false;
    await _db
        .into(_db.alertHistory)
        .insert(
          AlertHistoryCompanion.insert(
            type: entry.type,
            alertId: entry.alertId,
            occurrenceKey: entry.occurrenceKey,
            startUtcMs: entry.startUtc.millisecondsSinceEpoch,
            atUtcMs: at,
            snoozeUntilUtcMs: Value(
              entry.snoozeUntilUtc?.millisecondsSinceEpoch,
            ),
            title: Value(entry.title),
          ),
        );
    return true;
  });

  /// Newest first.
  Future<List<AlertHistoryEntry>> recent({int limit = 100}) =>
      _recent(limit).map(_fromRow).get();

  Stream<List<AlertHistoryEntry>> watchRecent({int limit = 100}) =>
      _recent(limit).map(_fromRow).watch();

  /// Entries that happened at or after [sinceUtc], oldest first.
  Future<List<AlertHistoryEntry>> since(DateTime sinceUtc) =>
      (_db.select(_db.alertHistory)
            ..where(
              (h) => h.atUtcMs.isBiggerOrEqualValue(
                sinceUtc.millisecondsSinceEpoch,
              ),
            )
            ..orderBy([(h) => OrderingTerm.asc(h.atUtcMs)]))
          .map(_fromRow)
          .get();

  /// What the planner must drop (roadmap §3 "Engine rules"):
  /// `dismissedAll` / `joined` → (occurrenceKey, startUtc);
  /// `dismissed` → (alertId, startUtc). Snooze ids (`…:s`) are skipped; the
  /// planner never produces them. Only occurrences that started within
  /// [ackWindow] of [nowUtc], or start later, are returned.
  Future<Acknowledgements> acknowledgements({required DateTime nowUtc}) async {
    final cutoff = nowUtc.subtract(ackWindow).millisecondsSinceEpoch;
    final rows =
        await (_db.select(_db.alertHistory)..where(
              (h) =>
                  h.startUtcMs.isBiggerOrEqualValue(cutoff) &
                  h.type.isInValues([
                    AlertEventType.dismissed,
                    AlertEventType.dismissedAll,
                    AlertEventType.joined,
                  ]),
            ))
            .get();
    DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return Acknowledgements(
      occurrences: [
        for (final r in rows)
          if (r.type != AlertEventType.dismissed)
            (r.occurrenceKey, t(r.startUtcMs)),
      ],
      alerts: [
        for (final r in rows)
          if (r.type == AlertEventType.dismissed && !r.alertId.endsWith(':s'))
            (r.alertId, t(r.startUtcMs)),
      ],
    );
  }

  /// Deletes entries that happened before [cutoffUtc]. Returns the count.
  Future<int> deleteBefore(DateTime cutoffUtc) =>
      (_db.delete(_db.alertHistory)..where(
            (h) =>
                h.atUtcMs.isSmallerThanValue(cutoffUtc.millisecondsSinceEpoch),
          ))
          .go();

  SimpleSelectStatement<$AlertHistoryTable, AlertHistoryRow> _recent(
    int limit,
  ) => _db.select(_db.alertHistory)
    ..orderBy([
      (h) => OrderingTerm.desc(h.atUtcMs),
      (h) => OrderingTerm.desc(h.id),
    ])
    ..limit(limit);

  static AlertHistoryEntry _fromRow(AlertHistoryRow r) {
    DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return AlertHistoryEntry(
      type: r.type,
      alertId: r.alertId,
      occurrenceKey: r.occurrenceKey,
      startUtc: t(r.startUtcMs),
      atUtc: t(r.atUtcMs),
      snoozeUntilUtc: r.snoozeUntilUtcMs == null
          ? null
          : t(r.snoozeUntilUtcMs!),
      title: r.title,
    );
  }
}
```

- [ ] **Step 4: Implement `SyncLogRepository`**

```dart
import 'package:drift/drift.dart';

import '../model/sync_log_entry.dart';
import 'app_database.dart';

class SyncLogRepository {
  SyncLogRepository(this._db);

  final AppDatabase _db;

  Future<void> add(SyncLogEntry e) => _db
      .into(_db.syncLog)
      .insert(
        SyncLogCompanion.insert(
          sourceId: Value(e.sourceId),
          atUtcMs: e.atUtc.millisecondsSinceEpoch,
          outcome: e.outcome,
          message: Value(e.message),
          occurrenceCount: Value(e.occurrenceCount),
          durationMs: Value(e.duration?.inMilliseconds),
        ),
      );

  /// Newest first.
  Future<List<SyncLogEntry>> recent({int limit = 50}) =>
      (_db.select(_db.syncLog)
            ..orderBy([
              (l) => OrderingTerm.desc(l.atUtcMs),
              (l) => OrderingTerm.desc(l.id),
            ])
            ..limit(limit))
          .map(_fromRow)
          .get();

  Future<SyncLogEntry?> latestForSource(String sourceId) =>
      (_db.select(_db.syncLog)
            ..where((l) => l.sourceId.equals(sourceId))
            ..orderBy([
              (l) => OrderingTerm.desc(l.atUtcMs),
              (l) => OrderingTerm.desc(l.id),
            ])
            ..limit(1))
          .map(_fromRow)
          .getSingleOrNull();

  /// Deletes entries logged before [cutoffUtc]. Returns the count.
  Future<int> deleteBefore(DateTime cutoffUtc) =>
      (_db.delete(_db.syncLog)..where(
            (l) =>
                l.atUtcMs.isSmallerThanValue(cutoffUtc.millisecondsSinceEpoch),
          ))
          .go();

  static SyncLogEntry _fromRow(SyncLogRow r) => SyncLogEntry(
    sourceId: r.sourceId,
    atUtc: DateTime.fromMillisecondsSinceEpoch(r.atUtcMs, isUtc: true),
    outcome: r.outcome,
    message: r.message,
    occurrenceCount: r.occurrenceCount,
    duration: r.durationMs == null
        ? null
        : Duration(milliseconds: r.durationMs!),
  );
}
```

- [ ] **Step 5: Run the tests and analyzer**

Run: `flutter test test/core/storage/history_storage_test.dart && flutter analyze`
Expected: `+7: All tests passed!`, then `No issues found!`

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
dart format lib/core/storage/alert_history_repository.dart lib/core/storage/sync_log_repository.dart test/core/storage/history_storage_test.dart
git add lib/core/storage/alert_history_repository.dart lib/core/storage/sync_log_repository.dart test/core/storage/history_storage_test.dart
git commit -m "Add alert history with acknowledgements, and sync log" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: RuleSetLoader, DI registration and an end-to-end check

**Files:**
- Create: `lib/core/storage/rule_set_loader.dart`
- Modify: `lib/app/di.dart` (whole file replaced; the existing `ThemeModeController` registration is kept)
- Test: `test/app/di_test.dart` (the existing `test/widget_test.dart` must keep passing unchanged)

**Interfaces:**
- Consumes: all repositories (Tasks 10–12), `RuleSet` and `RulesEngine` (Tasks 5–6), `buildPlan` (Task 7).
- Produces:
  - `RuleSetLoader({required ProfileRepository profiles, required RuleRepository rules, required OverrideRepository overrides, required SettingsRepository settings, required SourceRepository sources})`, `Future<RuleSet> load()`
  - `void configureDependencies({AppDatabase Function()? openDatabase})`. Everything is lazy. `getIt<AppDatabase>()`, every repository and `getIt<RuleSetLoader>()` are lazy singletons. `getIt<RulesEngine>()` is a factory with `zone: tz.local`. `getIt.reset()` closes the database if it was opened.
  - Note for Plan 4: call `tz.setLocalLocation(tz.getLocation(<device IANA zone>))` at startup (UI and headless isolates) before asking for a `RulesEngine`. Until then `tz.local` is UTC.

- [ ] **Step 1: Write the failing test**

`test/app/di_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/app/di.dart';
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
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/app/di_test.dart`
Expected: FAIL to compile with "Error when reading 'lib/core/storage/rule_set_loader.dart'" (and "No named parameter with the name 'openDatabase'").

- [ ] **Step 3: Implement `RuleSetLoader`**

```dart
import '../rules/rule_set.dart';
import 'override_repository.dart';
import 'profile_repository.dart';
import 'rule_repository.dart';
import 'settings_repository.dart';
import 'source_repository.dart';

/// Reads everything the rules engine needs in one call. Plan 4's
/// `syncMain()` and Plan 5's Agenda both use this.
class RuleSetLoader {
  RuleSetLoader({
    required this.profiles,
    required this.rules,
    required this.overrides,
    required this.settings,
    required this.sources,
  });

  final ProfileRepository profiles;
  final RuleRepository rules;
  final OverrideRepository overrides;
  final SettingsRepository settings;
  final SourceRepository sources;

  Future<RuleSet> load() async {
    final (p, r, o, skip, globalDefault, quiet, s) = await (
      profiles.all(),
      rules.all(),
      overrides.all(),
      settings.skipFilters(),
      settings.globalDefaultProfileId(),
      settings.quietState(),
      sources.all(),
    ).wait;
    return RuleSet(
      profiles: p,
      rules: r,
      overrides: o,
      skipFilters: skip,
      globalDefaultProfileId: globalDefault,
      quiet: quiet,
      sourceDefaults: {
        for (final src in s)
          if (src.defaultProfileId != null) src.id: src.defaultProfileId!,
      },
    );
  }
}
```

- [ ] **Step 4: Replace `lib/app/di.dart`**

The registration stays lazy, so `test/widget_test.dart` (`setUp(configureDependencies)` / `tearDown(getIt.reset)`) never opens a database and never needs `path_provider`:

```dart
import 'package:get_it/get_it.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/rules/rules_engine.dart';
import '../core/storage/alert_history_repository.dart';
import '../core/storage/app_database.dart';
import '../core/storage/occurrence_repository.dart';
import '../core/storage/override_repository.dart';
import '../core/storage/profile_repository.dart';
import '../core/storage/rule_repository.dart';
import '../core/storage/rule_set_loader.dart';
import '../core/storage/settings_repository.dart';
import '../core/storage/source_repository.dart';
import '../core/storage/sync_log_repository.dart';
import 'theme_mode_controller.dart';

final GetIt getIt = GetIt.instance;

/// Registers app-wide services. Call once before [runApp].
///
/// Everything is lazy, so nothing opens the database until something asks
/// for it: widget tests that never touch storage need no database and no
/// path_provider. Tests that do use storage pass [openDatabase], e.g. an
/// in-memory `AppDatabase`. `getIt.reset()` closes the database if it was
/// opened.
void configureDependencies({AppDatabase Function()? openDatabase}) {
  if (!tz.timeZoneDatabase.isInitialized) tzdata.initializeTimeZones();

  getIt.registerLazySingleton<ThemeModeController>(ThemeModeController.new);

  getIt.registerLazySingleton<AppDatabase>(
    openDatabase ?? AppDatabase.open,
    dispose: (db) => db.close(),
  );
  getIt.registerLazySingleton(() => SourceRepository(getIt()));
  getIt.registerLazySingleton(() => OccurrenceRepository(getIt()));
  getIt.registerLazySingleton(() => ProfileRepository(getIt()));
  getIt.registerLazySingleton(() => RuleRepository(getIt()));
  getIt.registerLazySingleton(() => OverrideRepository(getIt()));
  getIt.registerLazySingleton(() => SettingsRepository(getIt()));
  getIt.registerLazySingleton(() => AlertHistoryRepository(getIt()));
  getIt.registerLazySingleton(() => SyncLogRepository(getIt()));
  getIt.registerLazySingleton(
    () => RuleSetLoader(
      profiles: getIt(),
      rules: getIt(),
      overrides: getIt(),
      settings: getIt(),
      sources: getIt(),
    ),
  );

  // A factory, not a singleton: each engine reads `tz.local` as it is now.
  // Plan 4 sets `tz.local` from the device zone at startup; until then it
  // is UTC.
  getIt.registerFactory(() => RulesEngine(zone: tz.local));
}
```

- [ ] **Step 5: Run the new test, the widget tests and the analyzer**

Run: `flutter test test/app/di_test.dart test/widget_test.dart && flutter analyze`
Expected: `All tests passed!` (3 DI tests plus the existing widget tests), then `No issues found!`

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!` This plan adds 148 tests: 8 + 11 + 13 + 11 + 32 + 13 + 14 + 5 + 6 + 9 + 16 + 7 + 3, on top of the existing ones.

- [ ] **Step 7: Commit**

```bash
dart format lib/core/storage/rule_set_loader.dart lib/app/di.dart test/app/di_test.dart
git add lib/core/storage/rule_set_loader.dart lib/app/di.dart test/app/di_test.dart
git commit -m "Register storage, rules and planner in get_it" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Self-review

**1. Spec coverage**

| Requirement | Task |
|---|---|
| Roadmap §3 contract files, `idFor` known values, `groupFor`, JSON round trip | 1 |
| Spec §5 `EventOccurrence` + `description`, `cancelled`, `sourceId`, key (roadmap §4) | 2 |
| Spec §6 profiles and built-ins (ids per roadmap §4) | 2 |
| Overrides (occurrence/series; profileId, customAlerts, enabled) | 2, 5 |
| Skip filters, default on (roadmap §5.3) | 2, 5 |
| Keyword rules: fields, contains/regex, case-insensitive, invalid regex safe, hasJoinLink | 3, 5 |
| Quiet modes: mute until 07:00 next local day, pause, vacation; let-through rules; Vacation silences Important | 4, 6 |
| Resolution order 1–6, first match wins | 5 |
| Explainability strings (every form in roadmap §4) | 5, 6 |
| Planner: fireAt, past alerts kept until the occurrence ends, ended occurrences dropped (roadmap §3), Dismiss all / Join ack by (key, start), moved meeting re-arms, single Dismiss, stable ids, coalesce groups, snapshot, sound, sort | 7 |
| Spec §9 empty-feed guard (two consecutive empties) | 8 (wiring: Plan 4) |
| Spec §5 drift tables: sources, occurrences, overrides, profiles, rules, quiet_state, alert_history, sync_log (+ settings) | 9 |
| No ICS URL in drift; secureStorageKey only (spec §10) | 9 (test asserts no `url` column) |
| schemaVersion 1 + MigrationStrategy; built-ins seeded | 9 |
| Typed repositories for Plans 4/5; acknowledgements query for the planner | 10, 11, 12 |
| Roadmap §3 Dart de-dup on (type, alertId, atUtcMs) | 12 |
| get_it registration that keeps widget tests green | 13 |
| Spec §11 Rules engine table-driven tests, Planner tests | 5, 6, 7, 8 |
| Spec §11 "snooze options in the past are hidden" | Not here: Kotlin alarm screen (Plan 3); see Decision 13 |

**2. Placeholder scan:** no "TBD", "TODO", "similar to" or undefined helpers. Every code step has the complete file. All code in this plan was compiled, analysed (`No issues found!`) and run (148 tests passing) in a scratch Flutter 3.47 package with the same dependency versions before it was written down.

**3. Type consistency:** `EmptyFeedGuard.evaluate`, `Acknowledgements.isAlertDismissed(alertId, occurrenceStartUtc)`, `RuleSet.seriesOverride(String?)`, `SourceSyncState.emptyStreak`, `AlertHistoryRepository.acknowledgements(nowUtc:)` and `configureDependencies(openDatabase:)` are spelled the same in their defining task, their Interfaces blocks and every later use.

**4. Review Focus:** each of the five lines has a pinning test in its owning task (7, 2/4, 5/11, 2/11, 12).
