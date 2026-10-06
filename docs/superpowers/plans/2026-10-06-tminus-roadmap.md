# T-Minus Implementation Roadmap

**Spec:** `docs/superpowers/specs/2026-10-06-tminus-design.md` · **Design brief:** `docs/design-brief.md` · **Design system:** already implemented in `lib/app/theme/`.

The spec covers six subsystems, so it is split into six plans. Each one ends in working, tested software. Plans 1–3 are written now; 4–6 are written when their turn comes, against the code that exists by then.

| # | Plan | File | Depends on | Delivers |
|---|---|---|---|---|
| 1 | `ics_core` | `2026-10-06-plan-1-ics-core.md` | — | Pure Dart package: ICS text → occurrences in a window, with per-event error isolation |
| 2 | Domain, storage, rules, planner | `2026-10-06-plan-2-domain-rules-planner.md` | 1 (only for the field mapping notes) | Domain model, drift database, profile resolution, quiet modes, explanations, `PlannedAlert` plan building |
| 3 | Native alarm engine | `2026-10-06-plan-3-alarm-engine.md` | contract §3 only | Kotlin scheduling, ringing, Compose alarm screen, notifications, re-arm, `alarm_engine` channel + Dart client, debug test-alarm buttons |
| 4 | Sources + sync | written later | 1, 2, 3 | `IcsFeedSource`, `DeviceCalendarSource`, secure storage, `SyncWorker` + headless `syncMain()`, pre-alarm sync, error-handling table, empty-feed guard wiring, missed-(system) detection, debug fast-alarms source |
| 5 | UI | written later | 2, 4 | Agenda, event sheet, quiet sheet + quick-settings tile, Alerts, Sources, Health, Onboarding, Settings (incl. persisted theme mode) |
| 6 | Play readiness (phase 1.5) | written later | all | Privacy policy, store listing, Play declarations, FGS type decision |

Plans 2 and 3 share only the contract in §3 and can run in parallel after Plan 1 (or even alongside it).

**Execution (decided 2026-10-06):** every plan is built subagent-driven, using the orchestrator pattern (`/orchestrate`). One orchestrating session directs and checks and never writes code; `dev-worker`s build, test authors write tests from the acceptance criteria without reading the implementation, a `review-worker` reviews each wave's diff, and `scout`s run checks, tests and commits. For each plan (or for Plans 2 and 3 together, as parallel waves), run `/orchestrate` in plan mode first to turn it into an orchestration plan, then run that in a fresh session. No plan is executed inline.

## 1. Repository layout (from spec §4)

```
packages/ics_core/                 Plan 1 — pure Dart, no Flutter
lib/app/                           exists: bootstrap, DI, router, theme
lib/core/model/                    Plan 2 (contract files: Plan 2 or 3, whichever runs first)
lib/core/storage/                  Plan 2
lib/core/rules/                    Plan 2
lib/core/planner/                  Plan 2
lib/core/engine/                   Plan 3 (Dart side of alarm_engine)
lib/core/sources/, lib/core/sync/  Plan 4
lib/features/…                     Plan 5 (lib/features/token_preview exists)
android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/   Plan 3
android/app/src/main/kotlin/io/github/fifothehein/tminus/sync/     Plan 4
android/app/src/main/kotlin/io/github/fifothehein/tminus/calendar/ Plan 4
```

The root `pubspec.yaml` becomes a Dart pub workspace (`workspace: [packages/ics_core]`) in Plan 1; the app depends on `ics_core` from Plan 4 onwards.

## 2. `ics_core` public API (Plan 1 produces, Plan 4 consumes)

```dart
// packages/ics_core/lib/ics_core.dart
enum IcsBusyStatus { free, tentative, busy, oof, unknown }

/// Why an event's times are less certain than usual.
enum IcsWarning {
  /// TZID not in the Windows→IANA table and not an IANA name; used the feed's VTIMEZONE.
  tzFromVtimezone,
  /// No usable zone at all; used the device zone.
  tzFromDevice,
}

class IcsOccurrence {
  final String uid;
  final DateTime originalStartUtc; // the instance's RECURRENCE-ID / original DTSTART, UTC
  final bool recurring;            // true for any instance of an RRULE series (incl. overrides)
  final String title;              // SUMMARY, unescaped
  final String? location;
  final String? organizer;         // CN if present, else mailto address
  final String? description;
  final String? joinUrl;           // first https://teams.microsoft.com/l/meetup-join/... or https://teams.microsoft.com/meet/... in DESCRIPTION, then LOCATION
  final DateTime startUtc;
  final DateTime endUtc;
  final bool allDay;               // DATE values; start/end = local midnight in deviceZone, as UTC
  final IcsBusyStatus busyStatus;  // X-MICROSOFT-CDO-BUSYSTATUS, else TRANSP (TRANSPARENT→free), else unknown
  final Set<IcsWarning> warnings;
}

class IcsIssue {          // one skipped/odd VEVENT; the rest of the feed still parses
  final String? uid;
  final int line;         // 1-based line in the unfolded text where the VEVENT began
  final String message;
}

class IcsResult {
  final List<IcsOccurrence> occurrences; // sorted by startUtc, cancelled ones already dropped
  final List<IcsIssue> issues;
}

/// Throws [IcsFormatException] when the text is not a VCALENDAR at all (whole feed unusable).
IcsResult expandIcs(
  String icsText, {
  required DateTime windowStartUtc,
  required DateTime windowEndUtc,
  required String deviceZone, // IANA name, e.g. 'Africa/Johannesburg'
});

class IcsFormatException implements Exception { final String message; }
```

`ics_core` initialises `package:timezone`'s **`latest_all`** database (CLDR maps some Windows zones to old link names such as `Asia/Calcutta`). Plan 4 and anything else in the app should load `latest_all` too, not `latest`.

Plan 4 maps `IcsOccurrence` to `EventOccurrence`: `seriesUid = recurring ? uid : null`, both `IcsWarning`s → `OccurrenceWarning.tzFallback`, `cancelled = false`, `declined = false`.

## 3. Shared contract: alert model and `PlannedAlert` (Plans 2 and 3)

These two files are the only code Plans 2 and 3 share. Whichever plan runs first creates them **exactly as written here** and then runs `dart format` on them, as on all repo code. The other plan finds them present and must not change them; it compares them after formatting both sides, because the snippets below are not pre-formatted.

### `lib/core/model/alert.dart`

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

### `lib/core/model/planned_alert.dart`

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

> Note: Dart integers are 64-bit on the VM, so the FNV multiply wraps naturally. Known values (verified by running the code): `idFor('a', 10) == '0eee2d83f9209539'`, `idFor('src|uid1|2026-10-06T08:00:00.000Z', 10) == '88116ba1896be5a4'`. The Kotlin side never recomputes ids; it treats `id` as an opaque string and derives `PendingIntent` request codes from `id.hashCode()`.

### `alarm_engine` channel (Plan 3 implements both sides)

| Call (MethodChannel `alarm_engine`) | Arguments | Returns |
|---|---|---|
| `applyPlan` | `{"version": 1, "alerts": [PlannedAlert.toJson(), …]}` | `{"armed": int, "cancelled": int, "kept": int}` |
| `getHealth` | — | `{"notificationsEnabled": bool, "canUseFullScreenIntent": bool, "canScheduleExactAlarms": bool, "ignoringBatteryOptimizations": bool, "alarmStreamMuted": bool, "upcoming": [{"id", "fireAtUtcMs", "strength", "title"} × ≤5]}` |
| `testAlarm` | `{"strength": "headsUp"\|"alarm", "delaySec": int}` | `null` |
| `openPermissionSettings` | `{"kind": "notifications"\|"fullScreenIntent"\|"exactAlarm"\|"batteryOptimization"\|"alarmVolume"}` | `null` |
| `drainEvents` | — | `[EngineEvent JSON, …]` (queued while Flutter wasn't running; queue is cleared) |
| `queryDeviceCalendars`, `queryInstances` | Plan 4 adds these | |

EventChannel `alarm_engine/events` streams the same EngineEvent JSON live:
`{"type": "fired"|"snoozed"|"dismissed"|"dismissedAll"|"joined"|"missed", "alertId": String, "occurrenceKey": String, "startUtcMs": int, "atUtcMs": int, "snoozeUntilUtcMs": int?}`

A single `dismissed` event identifies the alert by `alertId` and the meeting's `startUtcMs`. Because `id = idFor(occurrenceKey, offsetMinutes)` and `fireAt = start − offset`, the pair (alertId, startUtcMs) names the same alert instance as Kotlin's (alertId, fireAtUtcMs). Dart keys single dismissals by (alertId, startUtcMs); no fire time is needed in the event.

Every event is also appended to the native queue file, so `drainEvents` returns everything Dart has not yet drained, whether or not it was also streamed live. Dart de-duplicates on `(type, alertId, atUtcMs)`.

### Engine rules both sides rely on

- **Kotlin is authoritative for acknowledgements.** On Dismiss all / Join, Kotlin stores `occurrenceKey|startUtcMs` in its ack store and from then on drops any alert in an incoming plan with that key *and* that start. If the start time changes, the pair no longer matches and the alerts re-arm (spec §6). Acks older than start + 24 h are pruned.
- On single **Dismiss**/**Stop**, Kotlin records `alertId|fireAtUtcMs` and does not re-arm that alert from a later plan.
- **The plan lists every alert of an occurrence until the occurrence ends**, including alerts whose `fireAtUtc` has passed. `applyPlan` never arms past alerts, but their presence tells Kotlin the meeting still exists. An `occurrenceKey` absent from a plan therefore means the meeting was cancelled, removed or has ended. (Without this, a snooze taken after an occurrence's last alert would be dropped on the next sync.)
- `applyPlan` never arms alerts whose `fireAtUtc` is in the past.
- **Snoozes** are created by Kotlin (id = original id + `":s"`), persisted alongside the plan, keep their strength, and survive `applyPlan` unless the new plan no longer contains their `occurrenceKey` (meeting cancelled) or the occurrence was acked.
- The Dart planner (Plan 2) also filters by the acknowledgements it has drained into `alert_history`, so both sides agree even before a drain.

## 4. Domain model summary (Plan 2 owns the code)

- `EventOccurrence` (spec §5) plus three fields the spec implies: `description` (rules match on it), `cancelled` (device source skip filter) and `sourceId`. Key = `'$sourceId|$uid|${originalStartUtc.toUtc().toIso8601String()}'`.
- Built-in profile ids: `meeting`, `quick`, `important`, `silent` with the alerts in spec §6 (`Important` = headsUp 30, headsUp 10, alarm 2, `ringsInQuietMode: true`).
- Overrides: scope `occurrence` (by key) or `series` (by `seriesUid`); each sets any of `profileId`, `customAlerts`, `enabled`. The agenda toggle writes an occurrence override with `enabled`. "Turned on with an occurrence override" (spec quiet modes) means `enabled == true`.
- Explanation strings have the form `<Profile name> · <reason>`, e.g. `Quick · rule: "standup"`, `Meeting · default`, `Silent · tentative`. Reasons by resolution step: `this event`, `series`, `all-day` / `free` / `tentative` / `cancelled` / `declined`, `rule: "<pattern>"`, `source default`, `default`. An event the agenda toggle turned off reads `Off · this event` (`Off · series` for a series override). Custom alerts read `Custom · this event` / `Custom · series`. A has-Teams-link rule reads `<Profile> · rule: Teams link`. When a quiet mode silences an event the whole line becomes `Silenced · Mute today`, `Silenced · Paused until 14:00` (local time) or `Silenced · Vacation`.

## 5. Decisions made while planning (the spec is silent; flagged for review)

1. **Notification "Snooze" option.** The ringing notification has one Snooze action, but the spec lists four snooze options. The notification picks **+5 min**; if the meeting starts sooner, **At start**; if it has already started, **+1 min**. The full-screen alarm screen offers all visible options.
2. **Pre-alarm sync and the quick-settings tile** move to Plans 4 and 5 respectively, because they need `SyncWorker` and quiet-state writes that do not exist in Plan 3.
3. **Skip filters default to on** (all-day, free, tentative, cancelled, declined), matching the brief's sample data.
4. **Kotlin JSON uses `org.json`** (built into Android, supported by Robolectric) rather than adding kotlinx.serialization.
5. **Exact-alarm permission below Android 13.** `USE_EXACT_ALARM` exists only from API 33, and minSdk is 26. Plan 3 also declares `SCHEDULE_EXACT_ALARM` with `android:maxSdkVersion="32"` (granted by default there) and falls back to an inexact alarm if exact scheduling is refused. Spec §7's permission table now has this row (added 2026-10-06); Health shows `canScheduleExactAlarms` from `getHealth`.
6. **Test alarms** (`testAlarm`) emit ordinary engine events with `occurrenceKey` starting `test|`. Plans 4 and 5 must keep them out of the missed-alert logic and label them "Test" in Health history.
7. **Coalesced alerts:** a group containing any `alarm` rings as an alarm; a new alert arriving while one rings joins the ringing session (Plan 3).
