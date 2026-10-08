# Plan 4: Sources and Sync Implementation Plan

> **Execution (decided 2026-10-06): subagent-driven, using the orchestrator pattern.** Do not execute this plan inline. Run `/orchestrate` in plan mode on this plan to produce an orchestration plan (workers: `dev-worker`, `review-worker`, `deep-review`, `scout`), then run that orchestration plan with `/orchestrate <path>` in a fresh session. Each task here becomes one or more orchestrator jobs; its code and tests are the job's brief content. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn calendars into alarms without the app open: ICS feeds and phone calendars as sources, a sync that runs from WorkManager in a headless Flutter engine (periodic, on calendar change, 12 min before each meeting's first alert, and on app foreground), the spec §9 error table with its notifications, the empty-feed guard, missed-(system) detection, and a debug "fast alarms" source.

**Architecture:** Every sync, wherever it runs, is one Dart call: `SyncService.run(trigger)`. It drains engine events into history, fetches every enabled source in parallel (`IcsFeedSource` over `package:http` with conditional GET, `DeviceCalendarSource` over two new `alarm_engine` calls, `FastAlarmsSource` in debug builds), applies the empty-feed guard and stores each result, plans with Plan 2's `RulesEngine` and `buildPlan`, checks missed (system) alerts, calls `applyPlan`, and finally tells Kotlin the pre-alarm sync times and whether to watch the phone calendar. Kotlin's `SyncWorker` runs that call in a headless `FlutterEngine` (`HeadlessFlutterRunner` → Dart `syncMain()`). The UI isolate runs it directly on app foreground. A process-wide lock behind the new `tminus_sync` channel keeps two runs from overlapping. Feed stale and Feed broken notifications are worded in Dart and posted by Kotlin.

**Tech Stack:** Dart 3.13 / Flutter 3.47, `http` 1.6.0, `flutter_secure_storage` 11.2.0, `path_provider` 2.1.6, `ics_core` (Plan 1, workspace path dependency), drift (Plan 2); Kotlin 2.4.0, WorkManager 2.12.0 (`work-runtime`, `work-testing`), `androidx.concurrent:concurrent-futures` 1.3.0, Robolectric 4.17.

**Spec:** `docs/superpowers/specs/2026-10-06-tminus-design.md` (§5 sources, §7 sync triggers and pre-alarm sync, §9 error table, §10 secrets, §11 fast alarms). Binding cross-plan contract: `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` §2 (the `ics_core` API), §3 (the `alarm_engine` channel and engine rules) and §5. Copy: `docs/design-brief.md` §5 (Sources) and §10 (Feed stale / Feed broken notifications). Plans 1–3 in `docs/superpowers/plans/`, and especially Plan 3's "Decisions this plan makes", which this plan respects entry by entry.

## Global Constraints

- Application ID and Kotlin package root: `io.github.fifothehein.tminus`. New Kotlin goes in `android/app/src/main/kotlin/io/github/fifothehein/tminus/calendar/` and `.../sync/` (roadmap §1). New Dart goes in `lib/core/sources/` and `lib/core/sync/`, and the headless entry point in `lib/app/sync_main.dart` and `lib/main.dart`.
- `minSdk = 26`; `compileSdk = flutter.compileSdkVersion` (36) and `targetSdk = flutter.targetSdkVersion` (36). Do **not** raise compileSdk (Plan 3: SDK 37 is not installed). Pinned and checked on 2026-10-08: `androidx.work:work-runtime:2.12.0` (AAR `minCompileSdk=35`), `androidx.concurrent:concurrent-futures:1.3.0` (plain jar), `androidx.work:work-testing:2.12.0`. Dart: `http: ^1.6.0`, `flutter_secure_storage: ^11.2.0` (Android `minSdk 24`, uses `flutter.compileSdkVersion` since 11.1.0), `path_provider: ^2.1.6`, `ics_core` as `path: packages/ics_core`.
- No coroutines of our own (Plan 3). WorkManager brings `kotlinx.coroutines` transitively; `SyncWorker` is a `ListenableWorker` with `CallbackToFutureAdapter`.
- `lib/core/model/alert.dart` and `lib/core/model/planned_alert.dart` are the roadmap §3 contract. Never edit them, and never run `dart format` on them.
- `alarm_engine` stays exactly as roadmap §3 says. This plan only fills in the `queryDeviceCalendars` and `queryInstances` rows (Task 4). The new `tminus_sync` channel is this plan's own (Task 9); its names are in the roadmap after Task 9.
- **One consumer of engine events per isolate** (Plan 3's final note). `AlarmEngine` hands each event to the live stream or to `drainEvents`, whichever sees it first, so `EngineEventRecorder` is the only code that calls `drainEvents`, and the only code that records history. `SyncService` calls `recorder.drainNow()`, never `drainEvents` itself. Other code may listen to the broadcast `events` stream for UI refreshes (Plan 3's engine panel does), because listening takes nothing away from the recorder. The headless engine only drains; the UI isolate drains and listens.
- **The plan keeps listing an occurrence's alerts until 15 min after it ends** (Plan 2 decision 19, already in `buildPlan`). `SyncService` plans from the cached occurrences that end after `now − keepAfterEnd`, so the cache query never cuts that window short.
- Plan 3 behaviour this plan relies on and must not undo: boot recovery fires 30 s after boot; overdue and orphaned alerts ring if their event hasn't ended; `getHealth` has `ringingChannelEnabled`; `EngineEvents` supports several listeners (one per registered engine, so the headless engine's `AlarmEngineChannel` gets its own); pruning of Kotlin acks runs inside `applyPlan`, which every sync calls.
- An ICS link is a secret (spec §10). It lives only in flutter_secure_storage under `SourceConfig.secureStorageKey` (`ics-url.<sourceId>`). It must never appear in drift, a `SyncLogEntry`, a `SourceFailed` message, a notification or a log line. Exception messages from `http`/`dart:io` are never shown, because they can contain the URL.
- Times: occurrences and plans are UTC (`plainUtc`, Plan 2 decision 25). The device zone comes from Kotlin (`tminus_sync.deviceZone`) and is set as `tz.local` at startup and in the headless engine (`initDeviceZone`). Load the `latest_all` database (roadmap §2), as `configureDependencies` already does.
- Notification copy follows brief §10. Feed stale: title `Calendar hasn't synced for N h — alarms may be outdated`, text = source name, action **Sync now**. Feed broken: title `<Source name> feed link stopped working` (device sources: `<Source name>: calendar access was turned off` / `<Source name>: calendar was removed`), text = the failure message, action **Fix**.
- Gates at the end of **every** task, from the repo root `C:\Projects\tminus`: `flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`; and, if any Kotlin changed, the Kotlin unit tests → `BUILD SUCCESSFUL`.
- Kotlin unit test command. Git Bash: `cd /c/Projects/tminus/android && ./gradlew :app:testDebugUnitTest`. PowerShell: `cd C:\Projects\tminus\android; .\gradlew.bat :app:testDebugUnitTest`. Add `--tests "<fully.qualified.TestClass>"` to run one class. `android/gradlew` and `gradlew.bat` are git-ignored: a fresh worktree has none, so copy both from the main checkout's `android/` folder (or run `flutter build apk --debug` once, which writes them).
- Run `dart format` only on the files a task lists, never on `lib/` as a whole (the contract files must not be reformatted). Kotlin has no formatter step; copy the code as written.
- Commit messages follow the repo style: one imperative sentence-case line, no prefix.

## Review Focus

1. **A feed that answers 304 Not Modified after the window has moved.** The server says nothing changed, but meetings 7 days out have come into range since the last full download. Expected: the stored body is expanded again for the current window, so new occurrences appear without a full download. Pinned in Task 3 (`with stored validators and body, a 304 re-expands the stored body`) and Task 2 (`FeedBodyCache`).
2. **Two syncs at once** (pull-to-refresh in the UI while WorkManager runs a headless sync). Without a lock both runs would count the same empty feed, and the two-empty-results guard (spec §9) would clear the cache after one glitch. Expected: one waits for the other. A run that never gets the lock reports `busy` and changes nothing. Pinned in Task 9 (`the lock admits one owner until it is released or its lease runs out`, `detach releases the locks this engine took`) and Task 11 (`when another sync holds the lock the run waits, then reports busy`).
3. **The secret ICS link leaking** through an exception message (`ClientException('Failed: https://…/s3cr3t/…')`), a log entry or the database. Expected: every failure message is fixed text with at most an HTTP status; drift holds only the secure-storage key. Pinned in Task 3 (`a network failure never repeats the link`, plus the `failure()` helper that checks every message) and Task 12 (`an ICS source keeps its link in secure storage, not in drift`).
4. **An alert that never rang because the phone killed the app or was off.** Expected: a `missedSystem` history row once fireAt + 2 min has passed with no `fired` record. No row for an alert that was already past when it was planned (a meeting added 5 min before it starts), or for one whose meeting was dismissed-all or joined first. Pinned in Task 7 (`no fired record by fireAt + 2 min is missed (system)`, `future alerts are expected; past ones that were never expected are not`, `Dismiss all or Join before the alert time excuses it`) and Task 11 (`an armed alert with no fired record becomes missed (system)`).
5. **A phone calendar that disappears or loses permission.** Expected: the cached occurrences and their alarms stay, the source turns red, and one notification is posted, not one per sync. A moved instance of a recurring phone event keeps its key, so its acknowledgement and overrides follow it. Pinned in Task 5 (`a revoked permission and a removed calendar are reported`, `a moved instance of a series keeps the series key`) and Task 11 (`a broken link notifies once, and recovery withdraws the notice`).

---

## Decisions this plan makes

Decided with the user while planning (2026-10-07):

1. **A 304 re-expands the stored feed.** Each feed's last 200 body is kept in `<app support>/feeds/<sourceId>.ics` (`FeedBodyCache`). A conditional GET is sent only when that file and a validator (ETag or Last-Modified) both exist. On 304 the stored body is expanded for the current window. A body that fails to parse is never stored.
2. **Missed (system)**: only alerts that were still in the future when a plan armed them count. Such an alert is missed (system) when no `fired` record exists by fireAt + 2 min, unless its occurrence was dismissed-all or joined at or before its fire time. An alert that rang more than 2 min late counts too (it then has both rows). Detection runs at every sync. The rows' `atUtc` is the fire time, so finding the same miss twice stores one row.
3. **Syncs never overlap.** Both isolates run in the app process, so a lock in Kotlin (`SyncLock`, behind `tminus_sync.acquireLock`) is shared by both. A sync that finds the lock held polls every 500 ms for up to 60 s, then runs. If it never gets the lock it reports `busy` and changes nothing. The lock is a 5-min lease, and an engine's locks are released when that engine is torn down, so a killed sync cannot block the next one.
4. **A broken phone calendar is treated like a broken feed**: cache kept, source red, one notification ("<name>: calendar access was turned off" / "<name>: calendar was removed").
5. **Pre-alarm sync times are computed in Dart; Kotlin keeps one alarm.** Per occurrence: its earliest alert − 12 min, counting alerts already past, so an occurrence gets exactly one pre-alarm sync. Dart sends the future times after every sync. Kotlin stores them and keeps one exact allow-while-idle alarm (`setExactAndAllowWhileIdle`, inexact without exact-alarm access) for the next one. It re-arms after each fire, boot, app update, clock or zone change and app start. The pre-alarm sync is expedited and has no network condition, so phone calendars still refresh and the stale check still runs offline.
6. **Accepted links**: `https://` and `webcal://` (rewritten to `https://`). Plain `http://` is accepted but flagged `insecure` for Plan 5 to warn about. Links whose path ends in `.html` are rejected with a pointer to the `.ics` link (spec §5).
7. **Foreground sync**: at app start and on every resume, in the UI isolate, unless a sync from any isolate finished within the last 2 minutes. Pull-to-refresh (Plan 5) calls `SyncService.run` directly and always syncs.
8. **History lives with Plan 4.** `EngineEventRecorder` is the single consumer of engine events (Constraints) and re-broadcasts recorded rows on `recorded` for Plan 5's UI. Each sync prunes `alert_history` to 30 days and `sync_log` to 7 days.
9. **Feed stale and Feed broken notifications are per source.** Each source has one id per kind and posts alert-once. Broken is posted when a source first enters a notify-class failure (or a different one) and withdrawn when that source next syncs successfully. Stale is posted while the condition holds and withdrawn otherwise. **Sync now** queues an expedited sync. **Fix** opens the app with the intent extra `io.github.fifothehein.tminus.ROUTE = /sources/<id>` for Plan 5's router. Both use the app-defined group `io.github.fifothehein.tminus.SYNC` with a posted summary, like Plan 3's heads-up and Missed notifications.
10. **Amber or red.** Network error, timeout, HTTP 5xx, 408 and 429 are amber: the cache is kept and WorkManager retries with backoff. A new `SyncOutcome.serverError` value is appended for the HTTP cases. Every other 4xx (401, 403, 404, 410, …) is `httpError`: red, with one notification. A feed that will not parse is `parseError`: red, without a notification (spec §9). A link missing from secure storage is a new `linkMissing`: red, with a notification. `calendarAccessDenied` and `calendarMissing` are appended for phone sources.
11. **Fast alarms** (debug builds): a debug-panel button stores three events with fixed times under a `SourceKind.debug` source (`debug-fast-alarms`). Two start at +2 min, giving a coalesced alarm at +1 min with the Meeting profile. One starts at +12 min with a Teams link (heads-up at +2 min, alarm at +11 min). They go through the real sync, rules, plan and `applyPlan`. **Clear fast alarms** removes the source.
12. **Phone-calendar occurrences use the source's colour**, like ICS. `SourceAdmin.addDeviceSource` pre-fills it from the Android calendar's colour.

Made while planning (the spec is silent; flagged for review):

13. **`CalendarSource.fetch` takes a `FetchWindow`**, not spec §5's `DateTimeRange`. That type lives in `package:flutter/material.dart`, which `lib/core` does not import. `FetchWindow.around(now)` is spec §5's now − 1 h to now + 7 days.
14. **Phone-calendar keys mirror ICS keys.** uid = `ORIGINAL_ID` (a moved or edited instance of a series) else `EVENT_ID`. The original start = `ORIGINAL_INSTANCE_TIME` else `BEGIN`. `seriesUid` = that uid for anything with an RRULE/RDATE or an `ORIGINAL_ID`. A moved one-off event gets a new key, as a moved one-off ICS event does (Plan 1). All-day instances become local midnights in the device zone, as `ics_core` does. A blank title reads `(No title)`.
15. **`ics_core` also exports `extractTeamsJoinUrl`**, so phone events find Teams links the same way feeds do (additive to roadmap §2; Task 1 records it there).
16. **`READ_CALENDAR` is declared here but requested by Plan 5's UI.** Until then, device checks grant it with `adb shell pm grant`.
17. **The calendar watch** is a WorkManager content-URI trigger on `CalendarContract.Events.CONTENT_URI` (descendants included, 5 s update delay, 30 s max delay). It exists while an enabled phone source exists. `CalendarWatchWorker` only queues a sync and the next watch, and never boots Flutter. Calendar-change syncs are not expedited; one that arrives during a sync is queued after it.
18. **Background-sync queueing.** `runNow` uses unique work per trigger with `KEEP`: a pre-alarm or Sync-now request whose trigger is already queued or running is dropped, because that run is current. The exception is calendar change (decision 17).
19. **The headless engine** runs Dart `syncMain(List<String> args)` from `lib/main.dart` with the trigger name as its argument. It reports `ok`, `retry` or `busy` through `tminus_sync.finished`. `retry` makes the worker return `Result.retry()` (spec §9 backoff); anything else is success. Kotlin gives up after 8 min (WorkManager's limit is 10) and reports `retry`.
20. **Feed stale is checked only for ICS sources.** A phone calendar's freshness depends on the account's own sync, which the app cannot see. Its last success is the last time the provider was read.
21. **Disabled sources** are not fetched and not planned (their alarms are cancelled at the next sync). Their cached occurrences stay until a day after they end.
22. **An empty result that the guard keeps** (`emptyKept`) still counts as a successful fetch for staleness, because the feed answered.
23. **Debug panel controls for device testing** (debug builds only): **Fast alarms** / **Clear fast alarms**, **Sync now** (UI isolate), **Background sync** (WorkManager → headless engine), an ICS link field with **Add feed**, **Add phone calendar** (the first visible one) and **Remove all sources**. They are stand-ins until Plan 5's Sources tab, so the real feed (spec §12 checks) and phone calendars can be tried now.

Decided with the user after checking a real Outlook link while planning (2026-10-08):

24. **Server errors that last 24 h mean the link is broken.** Outlook does not answer an unknown published-calendar link with 401/403/404, as spec §9 assumes. It redirects to an error page, which `package:http` sees as HTTP 500 (curl, sending different headers, gets 417). So a 5xx stays amber at first. But once a source has had no success for 24 h (since its last success, or since its first logged sync if it never succeeded) and the latest failure is a server error, it is reported as `httpError`: red, with one Feed broken notification. The message reads "The calendar server has kept failing for over 24 h. The link may have been reset or unpublished." Network errors never escalate. Task 15 Step 7 records what a real reset link returns.

## File Structure

Dart (`lib/`):

| File | Responsibility | Task |
|---|---|---|
| `core/sources/calendar_source.dart` | `FetchWindow`, `CalendarSource`, `SourceResult` (`SourceFetched` / `SourceFailed`) | 1 |
| `core/sources/occurrence_mapping.dart` | `occurrenceFromIcs` (roadmap §2), `occurrenceFromDevice` | 1, 5 |
| `core/sync/outcome_severity.dart` | `OutcomeSeverity`, `SyncOutcome.severity / notifiesBroken / retries` | 1 |
| `core/sources/ics_url.dart` | `IcsUrl.check` (accepted / rejected, insecure flag), `IcsUrl.mask` | 2 |
| `core/sources/source_secrets.dart` | ICS links in flutter_secure_storage | 2 |
| `core/sources/feed_body_cache.dart` | Last 200 body per feed, atomic write | 2 |
| `core/sources/ics_feed_source.dart` | Conditional GET, 20 s timeout, status → outcome, expansion | 3 |
| `core/sources/device_calendar_api.dart` | `DeviceCalendar`, `DeviceInstance`, `queryDeviceCalendars` / `queryInstances` client | 5 |
| `core/sources/device_calendar_source.dart` | Phone calendar as a `CalendarSource` | 5 |
| `core/sync/engine_event_recorder.dart` | The one engine-event consumer → `alert_history` | 6 |
| `core/sync/missed_system.dart` | `ExpectedAlert`, `MissedSystemDetector` (spec §9 missed (system)) | 7 |
| `core/sync/pre_sync.dart` | `preSyncTimes` (spec §7 pre-alarm sync) | 7 |
| `core/sync/sync_platform.dart` | `tminus_sync` client, `SourceNoticeKind` | 10 |
| `core/sync/device_zone.dart` | `initDeviceZone` → `tz.local` | 10 |
| `core/sync/sync_service.dart` | `SyncTrigger`, `SyncRunOutcome`, `SyncReport`, `SyncService.run` | 11 |
| `core/sources/fast_alarms.dart` | Debug fast-alarms events and source | 12 |
| `core/sources/source_factory.dart` | `SourceConfig` → `CalendarSource` | 12 |
| `core/sources/source_admin.dart` | Add / re-link / remove sources, `IcsUrlException` | 12 |
| `core/sync/foreground_sync.dart` | App-foreground sync with the 2-min gap | 13 |
| `app/sync_main.dart` | `runHeadlessSync` | 13 |
| `main.dart` | Startup wiring; `@pragma('vm:entry-point') syncMain` | 13 |
| `app/di.dart` | Registers everything above | 13 |
| `features/token_preview/sync_debug_panel.dart` (+ `token_preview_screen.dart`) | Debug sync controls | 14 |

Kotlin (`android/app/src/main/kotlin/io/github/fifothehein/tminus/`):

| File | Responsibility | Task |
|---|---|---|
| `calendar/DeviceCalendarReader.kt` | `CalendarContract` calendars and instances; `DeviceCalendarException` | 4 |
| `engine/AlarmEngineChannel.kt` | + `queryDeviceCalendars`, `queryInstances` | 4 |
| `sync/SyncWorker.kt` | `ListenableWorker` around a `SyncRunner`; triggers, outcomes | 8, 13 |
| `sync/SyncScheduler.kt` | Periodic, run-now and calendar-watch WorkManager requests; `CalendarWatchWorker` | 8 |
| `sync/PreSyncScheduler.kt` | Pre-alarm times and alarm; `PreSyncReceiver`, `SyncBootReceiver` | 8 |
| `sync/SyncNotifications.kt` | Feed stale / broken notifications; `SyncActionReceiver` | 9 |
| `sync/SyncChannel.kt` | `tminus_sync` channel; `SyncLock` | 9 |
| `MainActivity.kt` | Registers `tminus_sync`, keeps the periodic sync and pre-sync alarm | 9 |
| `sync/HeadlessFlutterRunner.kt` | Headless FlutterEngine → Dart `syncMain` | 13 |

Also: `lib/core/storage/sync_log_repository.dart` (Task 11, `earliestForSource`), `pubspec.yaml` (Task 1), `packages/ics_core/lib/ics_core.dart` (Task 1), `lib/core/model/source_config.dart` and `sync_log_entry.dart` (Task 1, appended enum values), `android/app/build.gradle.kts` (Task 8), `AndroidManifest.xml` (Tasks 3, 4, 8, 9), the roadmap (Tasks 1, 4, 9). Dart tests mirror `lib/` under `test/`; Kotlin tests live in `android/app/src/test/kotlin/io/github/fifothehein/tminus/calendar/` and `.../sync/`.

---

### Task 1: Dependencies, the source contract and ICS mapping

**Files:**
- Modify: `pubspec.yaml` (dependencies), `pubspec.lock` (by `flutter pub get`)
- Modify: `packages/ics_core/lib/ics_core.dart` (export `extractTeamsJoinUrl`)
- Modify: `lib/core/model/source_config.dart` (append `SourceKind.debug`)
- Modify: `lib/core/model/sync_log_entry.dart` (append four `SyncOutcome` values)
- Create: `lib/core/sources/calendar_source.dart`, `lib/core/sources/occurrence_mapping.dart`, `lib/core/sync/outcome_severity.dart`
- Modify: `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` (§2 note)
- Test: `test/core/sources/occurrence_mapping_test.dart`, `test/core/sync/outcome_severity_test.dart`

**Interfaces:**
- Consumes: `ics_core`'s `IcsOccurrence`, `IcsBusyStatus`, `IcsWarning` (roadmap §2); `EventOccurrence`, `BusyStatus`, `OccurrenceWarning`, `SourceConfig`, `SyncOutcome`, `plainUtc` (Plan 2).
- Produces: `class FetchWindow(DateTime startUtc, DateTime endUtc)` with `factory FetchWindow.around(DateTime now)`, `lookBehind = 1 h`, `lookAhead = 7 days`; `abstract interface class CalendarSource { String get id; Future<SourceResult> fetch(FetchWindow window); }`; `sealed class SourceResult` with `SourceFetched(List<EventOccurrence> occurrences, {List<String> issues, bool notModified, String? httpEtag, String? httpLastModified})` and `SourceFailed(SyncOutcome outcome, String message)`; `EventOccurrence occurrenceFromIcs(IcsOccurrence o, SourceConfig source)`; `enum OutcomeSeverity { ok, warning, error }` and `extension SyncOutcomeSeverity on SyncOutcome { OutcomeSeverity get severity; bool get notifiesBroken; bool get retries; }`; `SourceKind.debug`; `SyncOutcome.serverError`, `.calendarAccessDenied`, `.calendarMissing`, `.linkMissing`; `extractTeamsJoinUrl(String? description, String? location)` exported from `package:ics_core/ics_core.dart`.

- [ ] **Step 1: Add the dependencies**

In `pubspec.yaml`, replace

```yaml
  flutter:
    sdk: flutter
  get_it: ^9.3.0
  go_router: ^18.0.2
  provider: ^6.1.5+1
```

with

```yaml
  flutter:
    sdk: flutter
  flutter_secure_storage: ^11.2.0
  get_it: ^9.3.0
  go_router: ^18.0.2
  http: ^1.6.0
  ics_core:
    path: packages/ics_core
  path_provider: ^2.1.6
  provider: ^6.1.5+1
```

Run: `flutter pub get`
Expected: `Got dependencies!` (`http` and `path_provider` move from transitive to direct; `flutter_secure_storage` and its platform packages are added).

- [ ] **Step 2: Write the failing tests**

`test/core/sources/occurrence_mapping_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ics_core/ics_core.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/occurrence_mapping.dart';

void main() {
  const work = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.work',
  );

  IcsOccurrence ics({
    bool recurring = false,
    IcsBusyStatus busy = IcsBusyStatus.busy,
    Set<IcsWarning> warnings = const {},
  }) => IcsOccurrence(
    uid: 'uid1',
    originalStartUtc: DateTime.utc(2026, 10, 12, 7),
    recurring: recurring,
    title: 'Sprint planning',
    location: 'Room 4',
    organizer: 'Thandi M.',
    description: 'Agenda',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/abc',
    startUtc: DateTime.utc(2026, 10, 12, 8),
    endUtc: DateTime.utc(2026, 10, 12, 9),
    allDay: false,
    busyStatus: busy,
    warnings: warnings,
  );

  test('an ICS occurrence maps field by field, with the source colour', () {
    final o = occurrenceFromIcs(ics(), work);
    expect(o.sourceId, 'work');
    expect(o.uid, 'uid1');
    expect(o.originalStartUtc, DateTime.utc(2026, 10, 12, 7));
    expect(o.seriesUid, isNull);
    expect(o.title, 'Sprint planning');
    expect(o.location, 'Room 4');
    expect(o.organizer, 'Thandi M.');
    expect(o.description, 'Agenda');
    expect(o.joinUrl, 'https://teams.microsoft.com/l/meetup-join/abc');
    expect(o.startUtc, DateTime.utc(2026, 10, 12, 8));
    expect(o.endUtc, DateTime.utc(2026, 10, 12, 9));
    expect(o.busyStatus, BusyStatus.busy);
    expect(o.declined, isFalse);
    expect(o.cancelled, isFalse);
    expect(o.calendarColor, 0xFF6AA0F5);
    expect(o.warnings, isEmpty);
    expect(o.key, 'work|uid1|2026-10-12T07:00:00.000Z');
  });

  test('a recurring instance gets its uid as seriesUid', () {
    expect(occurrenceFromIcs(ics(recurring: true), work).seriesUid, 'uid1');
  });

  test('both time-zone warnings become tzFallback', () {
    for (final w in IcsWarning.values) {
      expect(occurrenceFromIcs(ics(warnings: {w}), work).warnings, {
        OccurrenceWarning.tzFallback,
      });
    }
  });

  test('every busy status maps by name', () {
    for (final b in IcsBusyStatus.values) {
      expect(occurrenceFromIcs(ics(busy: b), work).busyStatus.name, b.name);
    }
  });

  test('the fetch window is one hour back and seven days ahead', () {
    final w = FetchWindow.around(DateTime.utc(2026, 10, 6, 8));
    expect(w.startUtc, DateTime.utc(2026, 10, 6, 7));
    expect(w.endUtc, DateTime.utc(2026, 10, 13, 8));
  });
}
```

`test/core/sync/outcome_severity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sync/outcome_severity.dart';

void main() {
  test('each outcome has the colour the error table gives it', () {
    expect(
      {for (final o in SyncOutcome.values) o: o.severity},
      {
        SyncOutcome.success: OutcomeSeverity.ok,
        SyncOutcome.notModified: OutcomeSeverity.ok,
        SyncOutcome.emptyKept: OutcomeSeverity.ok,
        SyncOutcome.networkError: OutcomeSeverity.warning,
        SyncOutcome.httpError: OutcomeSeverity.error,
        SyncOutcome.parseError: OutcomeSeverity.error,
        SyncOutcome.otherError: OutcomeSeverity.error,
        SyncOutcome.serverError: OutcomeSeverity.warning,
        SyncOutcome.calendarAccessDenied: OutcomeSeverity.error,
        SyncOutcome.calendarMissing: OutcomeSeverity.error,
        SyncOutcome.linkMissing: OutcomeSeverity.error,
      },
    );
  });

  test('only a lost link or calendar posts a Feed broken notification', () {
    expect(SyncOutcome.values.where((o) => o.notifiesBroken).toSet(), {
      SyncOutcome.httpError,
      SyncOutcome.calendarAccessDenied,
      SyncOutcome.calendarMissing,
      SyncOutcome.linkMissing,
    });
  });

  test('only temporary failures are retried', () {
    expect(SyncOutcome.values.where((o) => o.retries).toSet(), {
      SyncOutcome.networkError,
      SyncOutcome.serverError,
    });
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/core/sources/occurrence_mapping_test.dart test/core/sync/outcome_severity_test.dart`
Expected: compilation fails, e.g. `Error when reading 'lib/core/sources/calendar_source.dart'` and `Member not found: 'serverError'`.

- [ ] **Step 4: Append the enum values and export the Teams-link extractor**

In `lib/core/model/source_config.dart`, replace `enum SourceKind { ics, device }` with:

```dart
/// Stored by name, so appending is safe; never rename one.
enum SourceKind {
  ics,
  device,

  /// Debug builds only: the "fast alarms" source (spec §11, Plan 4).
  debug,
}
```

(`textEnum<SourceKind>` reads `SourceKind.values` at run time, so `app_database.g.dart` needs no regeneration. Nothing in the app switches over `SourceKind` yet.)

In `lib/core/model/sync_log_entry.dart`, replace

```dart
  parseError,
  otherError,
}
```

with

```dart
  parseError,
  otherError,

  /// HTTP 5xx, 408 or 429: the server is having trouble; retried (Plan 4).
  serverError,

  /// READ_CALENDAR is not granted (device sources).
  calendarAccessDenied,

  /// The Android calendar no longer exists (device sources).
  calendarMissing,

  /// The ICS URL is not in secure storage any more.
  linkMissing,
}
```

In `packages/ics_core/lib/ics_core.dart`, replace `export 'src/expand_ics.dart' show expandIcs;` with:

```dart
export 'src/event_fields.dart' show extractTeamsJoinUrl;
export 'src/expand_ics.dart' show expandIcs;
```

- [ ] **Step 5: Create the contract, the ICS mapping and the severities**

`lib/core/sources/calendar_source.dart`:

```dart
import '../model/event_occurrence.dart';
import '../model/sync_log_entry.dart';
import '../model/utc.dart';

/// The span a sync fetches: now − 1 h to now + 7 days (spec §5).
class FetchWindow {
  FetchWindow(DateTime startUtc, DateTime endUtc)
    : startUtc = plainUtc(startUtc),
      endUtc = plainUtc(endUtc);

  /// The spec §5 window around [now].
  factory FetchWindow.around(DateTime now) =>
      FetchWindow(now.subtract(lookBehind), now.add(lookAhead));

  static const lookBehind = Duration(hours: 1);
  static const lookAhead = Duration(days: 7);

  final DateTime startUtc;
  final DateTime endUtc;

  @override
  bool operator ==(Object other) =>
      other is FetchWindow &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc;

  @override
  int get hashCode => Object.hash(startUtc, endUtc);

  @override
  String toString() => 'FetchWindow($startUtc – $endUtc)';
}

/// One configured calendar, ready to fetch (spec §5). Implementations never
/// throw: every failure comes back as a [SourceFailed].
abstract interface class CalendarSource {
  String get id;
  Future<SourceResult> fetch(FetchWindow window);
}

sealed class SourceResult {
  const SourceResult();
}

/// The source answered with its current events.
class SourceFetched extends SourceResult {
  const SourceFetched(
    this.occurrences, {
    this.issues = const [],
    this.notModified = false,
    this.httpEtag,
    this.httpLastModified,
  });

  /// Occurrences overlapping the window, all with this source's id.
  final List<EventOccurrence> occurrences;

  /// Events that were skipped or looked odd; never contains a URL.
  final List<String> issues;

  /// The feed answered 304 and its stored copy was expanded again.
  final bool notModified;

  /// Conditional-GET validators to keep for the next fetch (ICS only).
  final String? httpEtag;
  final String? httpLastModified;
}

/// The source could not be read. The cached occurrences stay as they are.
class SourceFailed extends SourceResult {
  const SourceFailed(this.outcome, this.message)
    : assert(outcome != SyncOutcome.success);

  final SyncOutcome outcome;

  /// Shown in Sources and Health. Never contains an ICS URL (spec §10).
  final String message;
}
```

`lib/core/sources/occurrence_mapping.dart` (Task 5 adds the device mapping to this file):

```dart
import 'package:ics_core/ics_core.dart';

import '../model/event_occurrence.dart';
import '../model/source_config.dart';

/// Roadmap §2: `seriesUid = recurring ? uid : null`, both ICS warnings become
/// [OccurrenceWarning.tzFallback], never cancelled or declined (ICS feeds
/// carry neither). The colour is the source's.
EventOccurrence occurrenceFromIcs(IcsOccurrence o, SourceConfig source) =>
    EventOccurrence(
      sourceId: source.id,
      uid: o.uid,
      originalStartUtc: o.originalStartUtc,
      seriesUid: o.recurring ? o.uid : null,
      title: o.title,
      location: o.location,
      organizer: o.organizer,
      description: o.description,
      joinUrl: o.joinUrl,
      startUtc: o.startUtc,
      endUtc: o.endUtc,
      allDay: o.allDay,
      busyStatus: switch (o.busyStatus) {
        IcsBusyStatus.free => BusyStatus.free,
        IcsBusyStatus.tentative => BusyStatus.tentative,
        IcsBusyStatus.busy => BusyStatus.busy,
        IcsBusyStatus.oof => BusyStatus.oof,
        IcsBusyStatus.unknown => BusyStatus.unknown,
      },
      calendarColor: source.color,
      warnings: o.warnings.isEmpty ? const {} : {OccurrenceWarning.tzFallback},
    );
```

`lib/core/sync/outcome_severity.dart`:

```dart
import '../model/sync_log_entry.dart';

/// How a source looks after a sync: green, amber or red (brief §5, spec §9).
enum OutcomeSeverity { ok, warning, error }

extension SyncOutcomeSeverity on SyncOutcome {
  /// Network trouble and server errors are temporary (amber) and retried.
  /// A link or calendar that is gone, or a feed that will not parse, is red.
  OutcomeSeverity get severity => switch (this) {
    SyncOutcome.success ||
    SyncOutcome.notModified ||
    SyncOutcome.emptyKept => OutcomeSeverity.ok,
    SyncOutcome.networkError ||
    SyncOutcome.serverError => OutcomeSeverity.warning,
    SyncOutcome.httpError ||
    SyncOutcome.parseError ||
    SyncOutcome.otherError ||
    SyncOutcome.calendarAccessDenied ||
    SyncOutcome.calendarMissing ||
    SyncOutcome.linkMissing => OutcomeSeverity.error,
  };

  /// True for the failures that post one "Feed broken" notification when a
  /// source first enters them (spec §9; device sources by Plan 4's decision).
  bool get notifiesBroken => switch (this) {
    SyncOutcome.httpError ||
    SyncOutcome.calendarAccessDenied ||
    SyncOutcome.calendarMissing ||
    SyncOutcome.linkMissing => true,
    _ => false,
  };

  /// True when WorkManager should retry the sync with backoff (spec §9).
  bool get retries => severity == OutcomeSeverity.warning;
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `dart format lib/core/sources lib/core/sync lib/core/model/source_config.dart lib/core/model/sync_log_entry.dart packages/ics_core/lib/ics_core.dart test/core/sources test/core/sync`
Run: `flutter test test/core/sources/occurrence_mapping_test.dart test/core/sync/outcome_severity_test.dart`
Expected: `All tests passed!` (8 tests).

- [ ] **Step 7: Record the export in the roadmap**

In `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` §2, after the paragraph that starts `Plan 4 maps \`IcsOccurrence\` to \`EventOccurrence\``, add:

```markdown
`ics_core` also exports `String? extractTeamsJoinUrl(String? description, String? location)` (added by Plan 4), so device-calendar events find Teams links exactly as feeds do.
```

- [ ] **Step 8: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock packages/ics_core/lib/ics_core.dart lib/core/model/source_config.dart lib/core/model/sync_log_entry.dart lib/core/sources lib/core/sync test/core/sources test/core/sync docs/superpowers/plans/2026-10-06-tminus-roadmap.md
git commit -m "Add the calendar source contract, ICS mapping and sync outcome severities"
```

---

### Task 2: ICS links, secure storage and the stored feed body

**Files:**
- Create: `lib/core/sources/ics_url.dart`, `lib/core/sources/source_secrets.dart`, `lib/core/sources/feed_body_cache.dart`
- Test: `test/core/sources/ics_url_test.dart`, `test/core/sources/source_secrets_test.dart`, `test/core/sources/feed_body_cache_test.dart`

**Interfaces:**
- Consumes: `flutter_secure_storage` (Task 1).
- Produces: `sealed class IcsUrlCheck` with `IcsUrlAccepted(String url, {required bool insecure})` and `IcsUrlRejected(String message)`; `abstract final class IcsUrl { static IcsUrlCheck check(String input); static String mask(String url); }`; `class SourceSecrets([FlutterSecureStorage? storage])` with `static String keyFor(String sourceId)` (= `'ics-url.$sourceId'`), `Future<String?> readUrl(String key)`, `Future<void> writeUrl(String key, String url)`, `Future<void> delete(String key)`; `class FeedBodyCache(Future<Directory> Function() directory)` with `Future<String?> read(String sourceId)`, `Future<void> write(String sourceId, String body)`, `Future<void> delete(String sourceId)`.

- [ ] **Step 1: Write the failing tests**

`test/core/sources/ics_url_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sources/ics_url.dart';

void main() {
  const outlook =
      'https://outlook.office365.com/owa/calendar/abc123@example.com/s3cr3t/calendar.ics';

  String accepted(String input, {bool insecure = false}) {
    final r = IcsUrl.check(input);
    expect(r, isA<IcsUrlAccepted>(), reason: input);
    expect((r as IcsUrlAccepted).insecure, insecure, reason: input);
    return r.url;
  }

  String rejected(String input) {
    final r = IcsUrl.check(input);
    expect(r, isA<IcsUrlRejected>(), reason: input);
    return (r as IcsUrlRejected).message;
  }

  test('an https .ics link is accepted as it is, trimmed', () {
    expect(accepted('  $outlook \n'), outlook);
  });

  test('webcal:// becomes https://', () {
    expect(
      accepted('webcal://outlook.office365.com/owa/calendar/x/calendar.ics'),
      'https://outlook.office365.com/owa/calendar/x/calendar.ics',
    );
    expect(accepted('WEBCAL://example.com/a.ics'), 'https://example.com/a.ics');
  });

  test('http:// is accepted but flagged insecure', () {
    expect(
      accepted('http://example.com/cal.ics', insecure: true),
      'http://example.com/cal.ics',
    );
  });

  test(
    'the .html web page link is rejected with a pointer to the .ics one',
    () {
      expect(
        rejected('https://outlook.office365.com/owa/calendar/x/calendar.html'),
        contains('.ics'),
      );
    },
  );

  test('empty text, other schemes and host-less links are rejected', () {
    expect(rejected('   '), 'Paste the calendar link.');
    expect(rejected('ftp://example.com/a.ics'), contains('https://'));
    expect(rejected('calendar.ics'), contains('https://'));
    expect(rejected('https:///a.ics'), contains('https://'));
  });

  test('mask keeps the host and the last segment only', () {
    expect(IcsUrl.mask(outlook), 'outlook.office365.com/…/calendar.ics');
    expect(IcsUrl.mask('https://example.com/cal.ics'), 'example.com/cal.ics');
    expect(IcsUrl.mask('https://example.com/'), 'example.com');
    expect(
      IcsUrl.mask('https://example.com/a/b.ics?token=s3cr3t'),
      'example.com/…/b.ics',
    );
    expect(IcsUrl.mask('not a link'), '…');
    expect(IcsUrl.mask(outlook), isNot(contains('s3cr3t')));
  });
}
```

`test/core/sources/source_secrets_test.dart` (`setMockInitialValues` swaps in the package's in-memory test platform):

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sources/source_secrets.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a link is written, read back and deleted by its key', () async {
    final secrets = SourceSecrets();
    final key = SourceSecrets.keyFor('work');
    expect(key, 'ics-url.work');
    expect(await secrets.readUrl(key), isNull);
    await secrets.writeUrl(key, 'https://example.com/a.ics');
    expect(await secrets.readUrl(key), 'https://example.com/a.ics');
    await secrets.delete(key);
    expect(await secrets.readUrl(key), isNull);
  });
}
```

`test/core/sources/feed_body_cache_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';

void main() {
  late Directory dir;
  late FeedBodyCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('feeds');
    cache = FeedBodyCache(() async => dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('a body is stored per source and read back', () async {
    expect(await cache.read('work'), isNull);
    await cache.write('work', 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
    await cache.write('home', 'other');
    expect(await cache.read('work'), 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
    expect(await cache.read('home'), 'other');
  });

  test(
    'a new body replaces the old one and leaves no temporary file',
    () async {
      await cache.write('work', 'old');
      await cache.write('work', 'new');
      expect(await cache.read('work'), 'new');
      expect(dir.listSync().map((f) => f.uri.pathSegments.last), ['work.ics']);
    },
  );

  test('delete removes the body; deleting a missing one is fine', () async {
    await cache.write('work', 'x');
    await cache.delete('work');
    await cache.delete('work');
    expect(await cache.read('work'), isNull);
  });

  test('a source id cannot escape the directory', () async {
    await cache.write('../evil/id', 'x');
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), [
      '___evil_id.ics',
    ]);
  });

  test('the directory is created on first write', () async {
    final nested = Directory('${dir.path}${Platform.pathSeparator}feeds');
    final c = FeedBodyCache(() async => nested);
    await c.write('work', 'x');
    expect(await c.read('work'), 'x');
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/sources/ics_url_test.dart test/core/sources/source_secrets_test.dart test/core/sources/feed_body_cache_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sources/ics_url.dart'` (and the other two files).

- [ ] **Step 3: Implement**

`lib/core/sources/ics_url.dart`:

```dart
/// What [IcsUrl.check] makes of a pasted link.
sealed class IcsUrlCheck {
  const IcsUrlCheck();
}

class IcsUrlAccepted extends IcsUrlCheck {
  const IcsUrlAccepted(this.url, {required this.insecure});

  /// The link to store and fetch: trimmed, `webcal://` rewritten to `https://`.
  final String url;

  /// Plain `http://`: the secret link travels unencrypted. Plan 5 shows a
  /// warning when this is true.
  final bool insecure;
}

class IcsUrlRejected extends IcsUrlCheck {
  const IcsUrlRejected(this.message);
  final String message;
}

/// Rules for published-calendar links (spec §5, §10).
abstract final class IcsUrl {
  static IcsUrlCheck check(String input) {
    var text = input.trim();
    if (text.isEmpty) return const IcsUrlRejected('Paste the calendar link.');
    final lower = text.toLowerCase();
    if (lower.startsWith('webcal://')) {
      text = 'https://${text.substring('webcal://'.length)}';
    }
    final uri = Uri.tryParse(text);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        (scheme != 'https' && scheme != 'http') ||
        uri.host.isEmpty) {
      return const IcsUrlRejected(
        'That is not a calendar link. It should start with https://.',
      );
    }
    if (uri.path.toLowerCase().endsWith('.html')) {
      return const IcsUrlRejected(
        'That is the web page link. Copy the link that ends in .ics instead.',
      );
    }
    return IcsUrlAccepted(text, insecure: scheme == 'http');
  }

  /// `outlook.office365.com/…/calendar.ics`: the host and the last path
  /// segment only (brief §5). The secret parts never reach the screen.
  static String mask(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '…';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return uri.host;
    if (segments.length == 1) return '${uri.host}/${segments.single}';
    return '${uri.host}/…/${segments.last}';
  }
}
```

`lib/core/sources/source_secrets.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ICS links in flutter_secure_storage (spec §3, §10). A published link works
/// like a password, so it never goes into drift, logs or exports.
class SourceSecrets {
  SourceSecrets([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// The secure-storage key for [sourceId]'s link.
  static String keyFor(String sourceId) => 'ics-url.$sourceId';

  Future<String?> readUrl(String key) => _storage.read(key: key);

  Future<void> writeUrl(String key, String url) =>
      _storage.write(key: key, value: url);

  Future<void> delete(String key) => _storage.delete(key: key);
}
```

`lib/core/sources/feed_body_cache.dart`:

```dart
import 'dart:io';

/// The last full body of each ICS feed, so a `304 Not Modified` can be
/// expanded again for the current window (Plan 4 decision). Lives in the app's
/// private support directory, next to the database, which already holds the
/// same meeting details.
class FeedBodyCache {
  FeedBodyCache(this._directory);

  final Future<Directory> Function() _directory;

  Future<String?> read(String sourceId) async {
    final file = await _file(sourceId);
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// Writes to a temporary file and renames it, so a reader never sees half a
  /// feed.
  Future<void> write(String sourceId, String body) async {
    final file = await _file(sourceId);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> delete(String sourceId) async {
    final file = await _file(sourceId);
    if (await file.exists()) await file.delete();
  }

  Future<File> _file(String sourceId) async {
    final dir = await _directory();
    final safe = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.ics');
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `dart format lib/core/sources test/core/sources`
Run: `flutter test test/core/sources/ics_url_test.dart test/core/sources/source_secrets_test.dart test/core/sources/feed_body_cache_test.dart`
Expected: `All tests passed!` (12 tests).

- [ ] **Step 5: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 6: Commit**

```bash
git add lib/core/sources test/core/sources
git commit -m "Check ICS links, keep them in secure storage and store each feed's last body"
```

---

### Task 3: ICS feed source

**Files:**
- Create: `lib/core/sources/ics_feed_source.dart`
- Modify: `android/app/src/main/AndroidManifest.xml` (`INTERNET`)
- Test: `test/core/sources/ics_feed_source_test.dart`

**Interfaces:**
- Consumes: `CalendarSource`, `FetchWindow`, `SourceFetched`, `SourceFailed`, `occurrenceFromIcs` (Task 1); `SourceSecrets`, `FeedBodyCache` (Task 2); `expandIcs`, `IcsFormatException` (roadmap §2); `SourceSyncState.httpEtag/httpLastModified` (Plan 2).
- Produces: `class IcsFeedSource implements CalendarSource` with constructor `IcsFeedSource({required SourceConfig config, required SourceSyncState? previous, required http.Client client, required SourceSecrets secrets, required FeedBodyCache bodies, required String deviceZone, Duration timeout = const Duration(seconds: 20)})` and public fields of the same names. Outcomes: 200 → `SourceFetched` (body stored, validators from the response); 304 with a stored body → `SourceFetched(notModified: true)`; 5xx/408/429 → `serverError`; other 4xx → `httpError`; timeout or connection failure → `networkError`; unparseable body → `parseError`; no link → `linkMissing`; anything else → `otherError`.

- [ ] **Step 1: Write the failing test**

`test/core/sources/ics_feed_source_test.dart`. `failure()` checks every failure message for the link's secret parts:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/sources/ics_feed_source.dart';
import 'package:tminus/core/sources/source_secrets.dart';

const _secretUrl =
    'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics';

/// One meeting on 6 Oct 2026, 08:00–08:30 UTC.
const _feed =
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:standup\r\n'
    'DTSTART:20261006T080000Z\r\n'
    'DTEND:20261006T083000Z\r\n'
    'SUMMARY:Daily standup\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

/// The same feed with the meeting moved to 09:00.
final _movedFeed = _feed
    .replaceFirst('20261006T080000Z', '20261006T090000Z')
    .replaceFirst('20261006T083000Z', '20261006T093000Z');

void main() {
  const config = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: 0xFF6AA0F5,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.work',
  );
  final window = FetchWindow.around(DateTime.utc(2026, 10, 6, 7));
  late Directory dir;
  late FeedBodyCache bodies;
  late List<http.Request> requests;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'ics-url.work': _secretUrl});
    dir = await Directory.systemTemp.createTemp('feeds');
    bodies = FeedBodyCache(() async => dir);
    requests = [];
  });

  tearDown(() => dir.delete(recursive: true));

  IcsFeedSource source(
    Future<http.Response> Function(http.Request) handler, {
    SourceSyncState? previous,
    Duration timeout = const Duration(seconds: 20),
  }) => IcsFeedSource(
    config: config,
    previous: previous,
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    secrets: SourceSecrets(),
    bodies: bodies,
    deviceZone: 'Africa/Johannesburg',
    timeout: timeout,
  );

  SourceFailed failure(SourceResult r) {
    expect(r, isA<SourceFailed>());
    final f = r as SourceFailed;
    expect(f.message, isNot(contains('s3cr3t')));
    expect(f.message, isNot(contains('office365')));
    return f;
  }

  Future<SourceFailed> failWith(int status) async => failure(
    await source((_) async => http.Response('', status)).fetch(window),
  );

  test('a 200 is expanded, its validators kept and its body stored', () async {
    final r = await source(
      (_) async => http.Response(
        _feed,
        200,
        headers: {
          'etag': '"v1"',
          'last-modified': 'Mon, 05 Oct 2026 10:00:00 GMT',
        },
      ),
    ).fetch(window);

    expect(requests.single.url.toString(), _secretUrl);
    expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
    final fetched = r as SourceFetched;
    expect(fetched.notModified, isFalse);
    expect(fetched.httpEtag, '"v1"');
    expect(fetched.httpLastModified, 'Mon, 05 Oct 2026 10:00:00 GMT');
    expect(fetched.occurrences.single.title, 'Daily standup');
    expect(fetched.occurrences.single.sourceId, 'work');
    expect(fetched.occurrences.single.startUtc, DateTime.utc(2026, 10, 6, 8));
    expect(await bodies.read('work'), _feed);
  });

  test(
    'with stored validators and body, a 304 re-expands the stored body',
    () async {
      await bodies.write('work', _feed);
      final r = await source(
        (_) async => http.Response('', 304),
        previous: SourceSyncState(
          httpEtag: '"v1"',
          httpLastModified: 'Mon, 05 Oct 2026 10:00:00 GMT',
        ),
      ).fetch(window);

      expect(requests.single.headers['If-None-Match'], '"v1"');
      expect(
        requests.single.headers['If-Modified-Since'],
        'Mon, 05 Oct 2026 10:00:00 GMT',
      );
      final fetched = r as SourceFetched;
      expect(fetched.notModified, isTrue);
      expect(fetched.httpEtag, '"v1"');
      expect(fetched.httpLastModified, 'Mon, 05 Oct 2026 10:00:00 GMT');
      expect(fetched.occurrences.single.title, 'Daily standup');
    },
  );

  test('without a stored body the request is unconditional', () async {
    final r = await source(
      (_) async => http.Response(_movedFeed, 200),
      previous: SourceSyncState(httpEtag: '"v1"'),
    ).fetch(window);
    expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
    expect(
      (r as SourceFetched).occurrences.single.startUtc,
      DateTime.utc(2026, 10, 6, 9),
    );
  });

  test('a 304 to an unconditional request is unexpected', () async {
    expect((await failWith(304)).outcome, SyncOutcome.otherError);
  });

  test('5xx, 408 and 429 are temporary server errors', () async {
    for (final status in [500, 502, 503, 408, 429]) {
      final f = await failWith(status);
      expect(f.outcome, SyncOutcome.serverError, reason: '$status');
      expect(f.message, contains('HTTP $status'));
    }
  });

  test(
    '401, 403, 404, 410 and every other 4xx mean the link is broken',
    () async {
      for (final status in [401, 403, 404, 410, 400, 451]) {
        expect(
          (await failWith(status)).outcome,
          SyncOutcome.httpError,
          reason: '$status',
        );
      }
      expect(
        (await failWith(403)).message,
        'Link no longer works (HTTP 403). It may have been reset in Outlook.',
      );
    },
  );

  test('a network failure never repeats the link', () async {
    final client = failure(
      await source(
        (r) async => throw http.ClientException('Failed: $_secretUrl', r.url),
      ).fetch(window),
    );
    expect(client.outcome, SyncOutcome.networkError);
    final io = failure(
      await source(
        (_) async => throw const SocketException('Failed host lookup'),
      ).fetch(window),
    );
    expect(io.outcome, SyncOutcome.networkError);
  });

  test('a server that does not answer in time is a network error', () async {
    final never = Completer<http.Response>();
    final f = failure(
      await source(
        (_) => never.future,
        timeout: const Duration(milliseconds: 20),
      ).fetch(window),
    );
    expect(f.outcome, SyncOutcome.networkError);
    expect(f.message, contains('did not answer'));
  });

  test(
    'a body that is not a calendar is a parse error and is not stored',
    () async {
      await bodies.write('work', _feed);
      final f = failure(
        await source((_) async => http.Response('<html>Sign in</html>', 200))
            .fetch(window),
      );
      expect(f.outcome, SyncOutcome.parseError);
      expect(await bodies.read('work'), _feed);
    },
  );

  test('a link missing from secure storage fails without a request', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final f = failure(
      await source((_) async => http.Response(_feed, 200)).fetch(window),
    );
    expect(f.outcome, SyncOutcome.linkMissing);
    expect(requests, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/sources/ics_feed_source_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sources/ics_feed_source.dart'`.

- [ ] **Step 3: Implement `lib/core/sources/ics_feed_source.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:http/http.dart' as http;
import 'package:ics_core/ics_core.dart';

import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import 'calendar_source.dart';
import 'feed_body_cache.dart';
import 'occurrence_mapping.dart';
import 'source_secrets.dart';

/// A published ICS feed (spec §5): conditional GET with a 20 s timeout, the
/// link read from secure storage, and every failure mapped to the spec §9
/// table. Messages never contain the link.
class IcsFeedSource implements CalendarSource {
  IcsFeedSource({
    required this.config,
    required this.previous,
    required this.client,
    required this.secrets,
    required this.bodies,
    required this.deviceZone,
    this.timeout = const Duration(seconds: 20),
  });

  final SourceConfig config;

  /// The stored sync state; supplies the conditional-GET validators.
  final SourceSyncState? previous;

  /// IANA name of the device zone, for floating and all-day times.
  final String deviceZone;
  final Duration timeout;
  final http.Client client;
  final SourceSecrets secrets;
  final FeedBodyCache bodies;

  @override
  String get id => config.id;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    final key = config.secureStorageKey;
    final url = key == null ? null : await secrets.readUrl(key);
    if (url == null) {
      return const SourceFailed(
        SyncOutcome.linkMissing,
        'The saved calendar link is missing. Add the link again.',
      );
    }

    final etag = previous?.httpEtag;
    final lastModified = previous?.httpLastModified;
    final cached = etag != null || lastModified != null
        ? await bodies.read(id)
        : null;

    final http.Response response;
    try {
      response = await _get(url, cached == null ? null : (etag, lastModified));
    } on TimeoutException {
      return SourceFailed(
        SyncOutcome.networkError,
        'The calendar server did not answer within ${timeout.inSeconds} s.',
      );
    } on http.ClientException {
      return const SourceFailed(
        SyncOutcome.networkError,
        'Could not reach the calendar server.',
      );
    } on IOException {
      return const SourceFailed(
        SyncOutcome.networkError,
        'Could not reach the calendar server.',
      );
    } on ArgumentError {
      return const SourceFailed(
        SyncOutcome.linkMissing,
        'The saved calendar link is not valid. Add the link again.',
      );
    }

    final status = response.statusCode;
    if (status == 200) {
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final result = _expand(body, window);
      if (result is SourceFetched) {
        await bodies.write(id, body);
        return SourceFetched(
          result.occurrences,
          issues: result.issues,
          httpEtag: response.headers['etag'],
          httpLastModified: response.headers['last-modified'],
        );
      }
      return result;
    }
    if (status == 304 && cached != null) {
      final result = _expand(cached, window);
      if (result is SourceFetched) {
        return SourceFetched(
          result.occurrences,
          issues: result.issues,
          notModified: true,
          httpEtag: response.headers['etag'] ?? etag,
          httpLastModified: response.headers['last-modified'] ?? lastModified,
        );
      }
      return result;
    }
    return SourceFailed(_outcomeFor(status), _messageFor(status));
  }

  Future<http.Response> _get(String url, (String?, String?)? validators) async {
    final request = http.Request('GET', Uri.parse(url));
    request.headers['Accept'] = 'text/calendar, */*;q=0.5';
    if (validators != null) {
      final (etag, lastModified) = validators;
      if (etag != null) request.headers['If-None-Match'] = etag;
      if (lastModified != null) {
        request.headers['If-Modified-Since'] = lastModified;
      }
    }
    Future<http.Response> send() async =>
        http.Response.fromStream(await client.send(request));
    return send().timeout(timeout);
  }

  SourceResult _expand(String body, FetchWindow window) {
    try {
      final result = expandIcs(
        body,
        windowStartUtc: window.startUtc,
        windowEndUtc: window.endUtc,
        deviceZone: deviceZone,
      );
      return SourceFetched(
        [for (final o in result.occurrences) occurrenceFromIcs(o, config)],
        issues: [for (final i in result.issues) 'line ${i.line}: ${i.message}'],
      );
    } on IcsFormatException catch (e) {
      return SourceFailed(
        SyncOutcome.parseError,
        'The feed is not a calendar: ${e.message}',
      );
    } catch (_) {
      return const SourceFailed(
        SyncOutcome.parseError,
        'The feed could not be read.',
      );
    }
  }

  static SyncOutcome _outcomeFor(int status) => switch (status) {
    408 || 429 || >= 500 => SyncOutcome.serverError,
    >= 400 && < 500 => SyncOutcome.httpError,
    _ => SyncOutcome.otherError,
  };

  static String _messageFor(int status) => switch (status) {
    408 ||
    429 ||
    >= 500 => 'The calendar server had a problem (HTTP $status). Retrying.',
    401 || 403 =>
      'Link no longer works (HTTP $status). It may have been reset in Outlook.',
    404 || 410 =>
      'Link no longer works (HTTP $status). The calendar may have been unpublished.',
    >= 400 && < 500 => 'The calendar server refused the link (HTTP $status).',
    _ => 'Unexpected answer from the calendar server (HTTP $status).',
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart format lib/core/sources test/core/sources`
Run: `flutter test test/core/sources/ics_feed_source_test.dart`
Expected: `All tests passed!` (10 tests).

- [ ] **Step 5: Declare INTERNET**

Release builds need it (debug and profile builds already get it from their own manifests). In `android/app/src/main/AndroidManifest.xml`, replace

```xml
    <!-- Alarm engine (spec §7). READ_CALENDAR and INTERNET arrive with Plan 4. -->
```

with

```xml
    <!-- Alarm engine (spec §7). -->
```

and after `<uses-permission android:name="android.permission.VIBRATE" />` add:

```xml
    <!-- Sources and sync (Plan 4). READ_CALENDAR is asked for only when a device source is added. -->
    <uses-permission android:name="android.permission.INTERNET" />
```

- [ ] **Step 6: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`; Kotlin unit tests → `BUILD SUCCESSFUL` (only the manifest changed, but Robolectric reads the merged manifest).

- [ ] **Step 7: Commit**

```bash
git add lib/core/sources/ics_feed_source.dart test/core/sources/ics_feed_source_test.dart android/app/src/main/AndroidManifest.xml
git commit -m "Fetch ICS feeds with conditional GET and map every failure to a sync outcome"
```

---

### Task 4: Device calendar reader and the two `alarm_engine` calls

**Files:**
- Create: `android/app/src/main/kotlin/io/github/fifothehein/tminus/calendar/DeviceCalendarReader.kt`
- Modify: `android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/AlarmEngineChannel.kt` (imports, constructor, two methods, one catch)
- Modify: `android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/AlarmEngineChannelTest.kt` (the "unknown methods" test)
- Modify: `android/app/src/main/AndroidManifest.xml` (`READ_CALENDAR`)
- Modify: `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` (§3 table rows)
- Test: `android/app/src/test/kotlin/io/github/fifothehein/tminus/calendar/DeviceCalendarReaderTest.kt`, `.../calendar/CalendarChannelTest.kt`

**Interfaces:**
- Consumes: `AlarmEngineChannel`, `AlarmScheduler`, `PlanStore` (Plan 3).
- Produces: `class DeviceCalendarException(val code: String, message: String)`; `class DeviceCalendarReader(context, resolver = context.contentResolver, hasPermission = { READ_CALENDAR granted })` with `fun calendars(): List<Map<String, Any?>>` (`id`, `name`, `accountName`, `color` as opaque ARGB `Long`, `visible`) and `fun instances(calendarIds: List<String>, fromUtcMs: Long, toUtcMs: Long): List<Map<String, Any?>>` (`eventId`, `calendarId`, `beginMs`, `endMs`, `allDay`, `title`, `location`, `description`, `organizer`, `availability`, `selfAttendeeStatus`, `status`, `originalId`, `originalInstanceTimeMs`, `recurring`), throwing `PERMISSION_DENIED = "permission_denied"` or `CALENDAR_MISSING = "calendar_missing"`. `alarm_engine` methods `queryDeviceCalendars` (no arguments) and `queryInstances` (`{"calendarIds": [String], "fromUtcMs": int, "toUtcMs": int}`) return those lists; reader errors come back as `result.error(code)`, bad arguments as `bad_args`. `AlarmEngineChannel`'s internal constructor gains `calendar: DeviceCalendarReader = DeviceCalendarReader(context)` before `clock`, so existing positional calls with a trailing clock lambda still compile.

The provider query runs on the main thread, like every `alarm_engine` call. A 7-day instance query is a few milliseconds.

- [ ] **Step 1: Write the failing tests**

`android/app/src/test/kotlin/io/github/fifothehein/tminus/calendar/DeviceCalendarReaderTest.kt`. Robolectric has no calendar provider, so `FakeCalendarProvider` is registered under `CalendarContract.AUTHORITY` and filters instances by the selection arguments the way the real one does:

```kotlin
package io.github.fifothehein.tminus.calendar

import android.Manifest
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Instances
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** Stands in for the calendar provider: rows keyed by column name, filtered like the real one. */
class FakeCalendarProvider : ContentProvider() {
    val calendars = mutableListOf<Map<String, Any?>>()
    val instances = mutableListOf<Map<String, Any?>>()
    val instanceUris = mutableListOf<Uri>()

    override fun onCreate() = true

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, args: Array<String>?, sort: String?): Cursor {
        val columns = projection!!
        val rows = when (uri.pathSegments.first()) {
            "calendars" -> calendars
            "instances" -> {
                instanceUris += uri
                val ids = args!!.toSet()
                instances.filter { it[Instances.CALENDAR_ID].toString() in ids }
            }
            else -> emptyList()
        }
        return MatrixCursor(columns).apply { rows.forEach { row -> addRow(columns.map { row[it] }) } }
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<String>?) = 0
}

@RunWith(RobolectricTestRunner::class)
class DeviceCalendarReaderTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private lateinit var provider: FakeCalendarProvider
    private lateinit var reader: DeviceCalendarReader

    @Before
    fun setUp() {
        provider = Robolectric.buildContentProvider(FakeCalendarProvider::class.java).create(CalendarContract.AUTHORITY).get()
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        reader = DeviceCalendarReader(app)
        provider.calendars += mapOf(
            Calendars._ID to 3L,
            Calendars.CALENDAR_DISPLAY_NAME to "Work",
            Calendars.ACCOUNT_NAME to "me@example.com",
            Calendars.CALENDAR_COLOR to 0x6AA0F5, // no alpha, as some providers store it
            Calendars.VISIBLE to 1,
        )
    }

    private fun instance(
        eventId: Long,
        calendarId: Long = 3,
        originalId: String? = null,
        originalInstanceTime: Long? = null,
        rrule: String? = null,
        status: Int? = null,
    ) = mapOf(
        Instances.EVENT_ID to eventId,
        Instances.CALENDAR_ID to calendarId,
        Instances.BEGIN to 1_791_000_000_000L,
        Instances.END to 1_791_001_800_000L,
        Instances.ALL_DAY to 0,
        Instances.TITLE to "Sprint planning",
        Instances.EVENT_LOCATION to "Room 4",
        Instances.DESCRIPTION to "Join: https://teams.microsoft.com/l/meetup-join/abc",
        Instances.ORGANIZER to "thandi@example.com",
        Instances.AVAILABILITY to Instances.AVAILABILITY_TENTATIVE,
        Instances.SELF_ATTENDEE_STATUS to CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED,
        Instances.STATUS to status,
        Instances.ORIGINAL_ID to originalId,
        Instances.ORIGINAL_INSTANCE_TIME to originalInstanceTime,
        Instances.RRULE to rrule,
        Instances.RDATE to null,
    )

    @Test
    fun `calendars are listed with an opaque ARGB colour`() {
        assertEquals(
            listOf(mapOf("id" to "3", "name" to "Work", "accountName" to "me@example.com", "color" to 0xFF6AA0F5L, "visible" to true)),
            reader.calendars(),
        )
    }

    @Test
    fun `instances come back with every field the Dart mapping needs`() {
        provider.instances += instance(10, status = Instances.STATUS_CANCELED)
        val row = reader.instances(listOf("3"), 1_790_000_000_000L, 1_792_000_000_000L).single()
        assertEquals(
            mapOf(
                "eventId" to "10",
                "calendarId" to "3",
                "beginMs" to 1_791_000_000_000L,
                "endMs" to 1_791_001_800_000L,
                "allDay" to false,
                "title" to "Sprint planning",
                "location" to "Room 4",
                "description" to "Join: https://teams.microsoft.com/l/meetup-join/abc",
                "organizer" to "thandi@example.com",
                "availability" to Instances.AVAILABILITY_TENTATIVE,
                "selfAttendeeStatus" to CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED,
                "status" to Instances.STATUS_CANCELED,
                "originalId" to null,
                "originalInstanceTimeMs" to null,
                "recurring" to false,
            ),
            row,
        )
    }

    @Test
    fun `the window goes into the instances uri and only the asked calendars come back`() {
        provider.calendars += mapOf(
            Calendars._ID to 4L,
            Calendars.CALENDAR_DISPLAY_NAME to "Home",
            Calendars.ACCOUNT_NAME to null,
            Calendars.CALENDAR_COLOR to 0xFF33AA66.toInt(),
            Calendars.VISIBLE to 1,
        )
        provider.instances += instance(10)
        provider.instances += instance(11, calendarId = 4)
        val rows = reader.instances(listOf("3"), 100L, 200L)
        assertEquals(listOf("10"), rows.map { it["eventId"] })
        assertEquals(listOf("instances", "when", "100", "200"), provider.instanceUris.single().pathSegments)
    }

    @Test
    fun `series instances and moved exceptions are marked`() {
        provider.instances += instance(10, rrule = "FREQ=WEEKLY")
        provider.instances += instance(12, originalId = "10", originalInstanceTime = 1_790_990_000_000L)
        val (series, moved) = reader.instances(listOf("3"), 0L, Long.MAX_VALUE)
        assertEquals(true, series["recurring"])
        assertEquals(null, series["originalId"])
        assertEquals("10", moved["originalId"])
        assertEquals(1_790_990_000_000L, moved["originalInstanceTimeMs"])
    }

    @Test
    fun `a calendar that no longer exists is an error, not an empty list`() {
        val e = assertThrows(DeviceCalendarException::class.java) { reader.instances(listOf("3", "99"), 0L, 1L) }
        assertEquals(DeviceCalendarReader.CALENDAR_MISSING, e.code)
    }

    @Test
    fun `without READ_CALENDAR every call is refused`() {
        val denied = DeviceCalendarReader(app, hasPermission = { false })
        assertEquals(DeviceCalendarReader.PERMISSION_DENIED, assertThrows(DeviceCalendarException::class.java) { denied.calendars() }.code)
        assertEquals(
            DeviceCalendarReader.PERMISSION_DENIED,
            assertThrows(DeviceCalendarException::class.java) { denied.instances(listOf("3"), 0L, 1L) }.code,
        )
    }
}
```

`android/app/src/test/kotlin/io/github/fifothehein/tminus/calendar/CalendarChannelTest.kt`:

```kotlin
package io.github.fifothehein.tminus.calendar

import android.Manifest
import android.app.Application
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Instances
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.fifothehein.tminus.engine.AlarmEngineChannel
import io.github.fifothehein.tminus.engine.AlarmScheduler
import io.github.fifothehein.tminus.engine.PlanStore
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** The two calls Plan 4 adds to `alarm_engine` (roadmap §3). */
@RunWith(RobolectricTestRunner::class)
class CalendarChannelTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private lateinit var provider: FakeCalendarProvider
    private lateinit var channel: AlarmEngineChannel

    private class Recorded : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { this.errorCode = errorCode }
        override fun notImplemented() = throw AssertionError("not implemented")
    }

    private fun call(method: String, args: Any? = null): Recorded =
        Recorded().also { channel.onMethodCall(MethodCall(method, args), it) }

    @Before
    fun setUp() {
        provider = Robolectric.buildContentProvider(FakeCalendarProvider::class.java).create(CalendarContract.AUTHORITY).get()
        provider.calendars += mapOf(
            Calendars._ID to 3L,
            Calendars.CALENDAR_DISPLAY_NAME to "Work",
            Calendars.ACCOUNT_NAME to "me@example.com",
            Calendars.CALENDAR_COLOR to 0xFF6AA0F5.toInt(),
            Calendars.VISIBLE to 1,
        )
        provider.instances += mapOf(
            Instances.EVENT_ID to 10L,
            Instances.CALENDAR_ID to 3L,
            Instances.BEGIN to 1_000L,
            Instances.END to 2_000L,
            Instances.ALL_DAY to 0,
            Instances.TITLE to "Standup",
            Instances.AVAILABILITY to Instances.AVAILABILITY_BUSY,
            Instances.SELF_ATTENDEE_STATUS to 0,
        )
        val store = PlanStore(app).also { it.clear() }
        channel = AlarmEngineChannel(app, store, AlarmScheduler(app, store))
    }

    @Test
    fun `queryDeviceCalendars lists the calendars`() {
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        val calendars = call("queryDeviceCalendars").value as List<*>
        assertEquals("Work", (calendars.single() as Map<*, *>)["name"])
    }

    @Test
    fun `queryInstances passes the ids and window through`() {
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        val rows = call("queryInstances", mapOf("calendarIds" to listOf("3"), "fromUtcMs" to 0, "toUtcMs" to 5_000L)).value as List<*>
        assertEquals("Standup", (rows.single() as Map<*, *>)["title"])
        assertEquals(listOf("instances", "when", "0", "5000"), provider.instanceUris.single().pathSegments)
    }

    @Test
    fun `reader errors keep their code`() {
        shadowOf(app).denyPermissions(Manifest.permission.READ_CALENDAR)
        assertEquals("permission_denied", call("queryDeviceCalendars").errorCode)
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        val missing = call("queryInstances", mapOf("calendarIds" to listOf("99"), "fromUtcMs" to 0, "toUtcMs" to 1))
        assertEquals("calendar_missing", missing.errorCode)
    }

    @Test
    fun `bad queryInstances arguments are bad_args`() {
        shadowOf(app).grantPermissions(Manifest.permission.READ_CALENDAR)
        assertEquals("bad_args", call("queryInstances", mapOf("fromUtcMs" to 0, "toUtcMs" to 1)).errorCode)
        assertEquals("bad_args", call("queryInstances", mapOf("calendarIds" to emptyList<String>(), "fromUtcMs" to 0, "toUtcMs" to 1)).errorCode)
    }
}
```

In `android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/AlarmEngineChannelTest.kt`, the last test used `queryDeviceCalendars` as its unknown method. Replace

```kotlin
        assertTrue(call("queryDeviceCalendars").notImplemented)
```

with

```kotlin
        assertTrue(call("noSuchMethod").notImplemented)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd /c/Projects/tminus/android && ./gradlew :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.calendar.*"`
Expected: `BUILD FAILED`, `Unresolved reference 'DeviceCalendarReader'`.

- [ ] **Step 3: Implement `calendar/DeviceCalendarReader.kt`**

```kotlin
package io.github.fifothehein.tminus.calendar

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Instances
import androidx.core.content.ContextCompat

/** A failure the Dart side maps to a source state; [code] becomes the PlatformException code. */
class DeviceCalendarException(val code: String, message: String) : Exception(message)

/**
 * Reads the phone's calendars and their expanded instances (spec §5 `DeviceCalendarSource`).
 * Android has already expanded recurrence in `CalendarContract.Instances`. READ_CALENDAR is asked
 * for by the UI (Plan 5); without it every call throws [PERMISSION_DENIED].
 */
class DeviceCalendarReader(
    context: Context,
    private val resolver: ContentResolver = context.applicationContext.contentResolver,
    private val hasPermission: () -> Boolean = {
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
    },
) {
    /** Every calendar on the phone, by display name: `{id, name, accountName, color, visible}`. */
    fun calendars(): List<Map<String, Any?>> {
        requirePermission()
        val rows = mutableListOf<Map<String, Any?>>()
        resolver.query(Calendars.CONTENT_URI, CALENDAR_COLUMNS, null, null, "${Calendars.CALENDAR_DISPLAY_NAME} ASC")?.use { c ->
            while (c.moveToNext()) {
                rows += mapOf(
                    "id" to c.getLong(0).toString(),
                    "name" to (c.getString(1) ?: ""),
                    "accountName" to c.getString(2),
                    "color" to opaque(c.getInt(3)),
                    "visible" to (c.getInt(4) != 0),
                )
            }
        }
        return rows
    }

    /**
     * Instances of [calendarIds] overlapping [fromUtcMs, toUtcMs), by start. Throws
     * [CALENDAR_MISSING] if any calendar no longer exists, so the source turns red instead of
     * looking empty.
     */
    fun instances(calendarIds: List<String>, fromUtcMs: Long, toUtcMs: Long): List<Map<String, Any?>> {
        requirePermission()
        require(calendarIds.isNotEmpty()) { "calendarIds is empty" }
        val existing = calendars().map { it["id"] }.toSet()
        val missing = calendarIds.filterNot { it in existing }
        if (missing.isNotEmpty()) throw DeviceCalendarException(CALENDAR_MISSING, "Calendar ${missing.joinToString()} no longer exists")

        val uri = Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, fromUtcMs)
            ContentUris.appendId(it, toUtcMs)
        }.build()
        val selection = "${Instances.CALENDAR_ID} IN (${calendarIds.joinToString { "?" }})"
        val rows = mutableListOf<Map<String, Any?>>()
        resolver.query(uri, INSTANCE_COLUMNS, selection, calendarIds.toTypedArray(), "${Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext()) rows += instance(c)
        }
        return rows
    }

    private fun instance(c: Cursor): Map<String, Any?> = mapOf(
        "eventId" to c.getLong(0).toString(),
        "calendarId" to c.getLong(1).toString(),
        "beginMs" to c.getLong(2),
        "endMs" to c.getLong(3),
        "allDay" to (c.getInt(4) != 0),
        "title" to c.getString(5),
        "location" to c.getString(6),
        "description" to c.getString(7),
        "organizer" to c.getString(8),
        "availability" to c.getInt(9),
        "selfAttendeeStatus" to c.getInt(10),
        "status" to if (c.isNull(11)) null else c.getInt(11),
        "originalId" to c.getString(12)?.takeIf { it.isNotEmpty() },
        "originalInstanceTimeMs" to if (c.isNull(13)) null else c.getLong(13),
        "recurring" to (!c.getString(14).isNullOrEmpty() || !c.getString(15).isNullOrEmpty()),
    )

    private fun requirePermission() {
        if (!hasPermission()) throw DeviceCalendarException(PERMISSION_DENIED, "READ_CALENDAR is not granted")
    }

    /** Calendar colours are ARGB ints; some providers leave alpha at 0. */
    private fun opaque(color: Int): Long = (color.toLong() and 0xFFFFFFL) or 0xFF000000L

    companion object {
        const val PERMISSION_DENIED = "permission_denied"
        const val CALENDAR_MISSING = "calendar_missing"

        val CALENDAR_COLUMNS = arrayOf(
            Calendars._ID,
            Calendars.CALENDAR_DISPLAY_NAME,
            Calendars.ACCOUNT_NAME,
            Calendars.CALENDAR_COLOR,
            Calendars.VISIBLE,
        )

        val INSTANCE_COLUMNS = arrayOf(
            Instances.EVENT_ID,
            Instances.CALENDAR_ID,
            Instances.BEGIN,
            Instances.END,
            Instances.ALL_DAY,
            Instances.TITLE,
            Instances.EVENT_LOCATION,
            Instances.DESCRIPTION,
            Instances.ORGANIZER,
            Instances.AVAILABILITY,
            Instances.SELF_ATTENDEE_STATUS,
            Instances.STATUS,
            Instances.ORIGINAL_ID,
            Instances.ORIGINAL_INSTANCE_TIME,
            Instances.RRULE,
            Instances.RDATE,
        )
    }
}
```

- [ ] **Step 4: Add the two calls to `AlarmEngineChannel.kt`**

After `import io.flutter.plugin.common.MethodChannel` add:

```kotlin
import io.github.fifothehein.tminus.calendar.DeviceCalendarException
import io.github.fifothehein.tminus.calendar.DeviceCalendarReader
```

In the constructor, replace

```kotlin
    presenter: AlertPresenter = AndroidAlertPresenter(context, store),
    private val clock: () -> Long = System::currentTimeMillis,
```

with

```kotlin
    presenter: AlertPresenter = AndroidAlertPresenter(context, store),
    private val calendar: DeviceCalendarReader = DeviceCalendarReader(context),
    private val clock: () -> Long = System::currentTimeMillis,
```

In `onMethodCall`, replace

```kotlin
                "drainEvents" -> result.success(EventQueue(appContext).drain().map { it.toMap() })
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
```

with

```kotlin
                "drainEvents" -> result.success(EventQueue(appContext).drain().map { it.toMap() })
                // Plan 4: the device calendar source (roadmap §3 table).
                "queryDeviceCalendars" -> result.success(calendar.calendars())
                "queryInstances" -> result.success(queryInstances(call.mapArgs()))
                else -> result.notImplemented()
            }
        } catch (e: DeviceCalendarException) {
            result.error(e.code, e.message, null)
        } catch (e: IllegalArgumentException) {
```

Before `private fun testAlarm(args: Map<*, *>) {` add:

```kotlin
    private fun queryInstances(args: Map<*, *>): List<Map<String, Any?>> {
        val ids = (args["calendarIds"] as? List<*>)?.map { it as String } ?: throw IllegalArgumentException("calendarIds missing")
        val from = (args["fromUtcMs"] as? Number)?.toLong() ?: throw IllegalArgumentException("fromUtcMs missing")
        val to = (args["toUtcMs"] as? Number)?.toLong() ?: throw IllegalArgumentException("toUtcMs missing")
        return calendar.instances(ids, from, to)
    }

```

(A non-string id throws `ClassCastException`, which the existing catch maps to `bad_args`.)

- [ ] **Step 5: Declare READ_CALENDAR**

In `android/app/src/main/AndroidManifest.xml`, after `<uses-permission android:name="android.permission.INTERNET" />` add:

```xml
    <uses-permission android:name="android.permission.READ_CALENDAR" />
```

It is a runtime permission. Plan 5's UI asks for it when the user adds a phone calendar (decision 16).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd /c/Projects/tminus/android && ./gradlew :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.calendar.*" --tests "io.github.fifothehein.tminus.engine.AlarmEngineChannelTest"`
Expected: `BUILD SUCCESSFUL` (6 + 4 calendar tests, and the existing channel tests).

- [ ] **Step 7: Fill in the roadmap §3 rows**

In `docs/superpowers/plans/2026-10-06-tminus-roadmap.md`, replace the table row

```markdown
| `queryDeviceCalendars`, `queryInstances` | Plan 4 adds these | |
```

with

```markdown
| `queryDeviceCalendars` | — | `[{"id": String, "name": String, "accountName": String?, "color": int (opaque ARGB), "visible": bool}, …]`; error `permission_denied` |
| `queryInstances` | `{"calendarIds": [String], "fromUtcMs": int, "toUtcMs": int}` | `[{"eventId": String, "calendarId": String, "beginMs": int, "endMs": int, "allDay": bool, "title": String?, "location": String?, "description": String?, "organizer": String?, "availability": int, "selfAttendeeStatus": int, "status": int?, "originalId": String?, "originalInstanceTimeMs": int?, "recurring": bool}, …]` by begin; errors `permission_denied`, `calendar_missing` (Plan 4) |
```

- [ ] **Step 8: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`; full Kotlin unit tests → `BUILD SUCCESSFUL`.

- [ ] **Step 9: Commit**

```bash
git add android/app/src/main/kotlin/io/github/fifothehein/tminus/calendar android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/AlarmEngineChannel.kt android/app/src/main/AndroidManifest.xml android/app/src/test/kotlin/io/github/fifothehein/tminus/calendar android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/AlarmEngineChannelTest.kt docs/superpowers/plans/2026-10-06-tminus-roadmap.md
git commit -m "Read phone calendars and their instances over the alarm engine channel"
```

---

### Task 5: Device calendar source (Dart)

**Files:**
- Create: `lib/core/sources/device_calendar_api.dart`, `lib/core/sources/device_calendar_source.dart`
- Modify: `lib/core/sources/occurrence_mapping.dart` (imports; append `occurrenceFromDevice`)
- Test: `test/core/sources/device_calendar_source_test.dart`

**Interfaces:**
- Consumes: Task 4's channel calls; `AlarmEngine.methodChannelName` (Plan 3); `CalendarSource`, `SourceFetched`, `SourceFailed` (Task 1); `extractTeamsJoinUrl` (Task 1).
- Produces: `class DeviceCalendar({id, name, accountName, color, visible})` with `fromJson`; `class DeviceInstance` with `fromJson` and the constants `availabilityBusy = 0`, `availabilityFree = 1`, `availabilityTentative = 2`, `attendeeDeclined = 2`, `statusCancelled = 2`; `class DeviceCalendarApi({MethodChannel? channel})` with `Future<List<DeviceCalendar>> calendars()`, `Future<List<DeviceInstance>> instances({required List<String> calendarIds, required DateTime fromUtc, required DateTime toUtc})`, `static const permissionDenied = 'permission_denied'`, `static const calendarMissing = 'calendar_missing'`; `EventOccurrence occurrenceFromDevice(DeviceInstance i, SourceConfig source, tz.Location zone)` (decision 14); `class DeviceCalendarSource({required SourceConfig config, required DeviceCalendarApi api, required tz.Location zone}) implements CalendarSource`. Failures: `permission_denied` → `calendarAccessDenied` ("Calendar access was turned off."), `calendar_missing` or no `deviceCalendarId` → `calendarMissing`, any other code → `otherError`.

- [ ] **Step 1: Write the failing test**

`test/core/sources/device_calendar_source_test.dart` (instants: 1791273600000 = 2026-10-06 08:00 UTC):

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/event_occurrence.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/device_calendar_api.dart';
import 'package:tminus/core/sources/device_calendar_source.dart';

import '../fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(AlarmEngine.methodChannelName);
  final calls = <MethodCall>[];

  const phone = SourceConfig(
    id: 'phone',
    name: 'Work calendar',
    color: 0xFF33AA66,
    kind: SourceKind.device,
    deviceCalendarId: '3',
  );
  final window = FetchWindow(
    DateTime.utc(2026, 10, 6, 7),
    DateTime.utc(2026, 10, 13, 7),
  );

  Map<String, Object?> row({
    String eventId = '10',
    int beginMs = 1791273600000, // 2026-10-06 08:00 UTC
    int endMs = 1791275400000, // 08:30
    bool allDay = false,
    String? title = 'Sprint planning',
    String? location,
    String? description,
    int availability = DeviceInstance.availabilityBusy,
    int selfAttendeeStatus = 1,
    int? status,
    String? originalId,
    int? originalInstanceTimeMs,
    bool recurring = false,
  }) => {
    'eventId': eventId,
    'calendarId': '3',
    'beginMs': beginMs,
    'endMs': endMs,
    'allDay': allDay,
    'title': title,
    'location': location,
    'description': description,
    'organizer': 'thandi@example.com',
    'availability': availability,
    'selfAttendeeStatus': selfAttendeeStatus,
    'status': status,
    'originalId': originalId,
    'originalInstanceTimeMs': originalInstanceTimeMs,
    'recurring': recurring,
  };

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  DeviceCalendarSource source({SourceConfig config = phone}) =>
      DeviceCalendarSource(
        config: config,
        api: DeviceCalendarApi(),
        zone: johannesburg,
      );

  Future<List<EventOccurrence>> fetched(List<Map<String, Object?>> rows) async {
    answer((_) => rows);
    final r = await source().fetch(window);
    return (r as SourceFetched).occurrences;
  }

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('asks for this calendar over the fetch window', () async {
    await fetched([]);
    expect(calls.single.method, 'queryInstances');
    expect(calls.single.arguments, {
      'calendarIds': ['3'],
      'fromUtcMs': window.startUtc.millisecondsSinceEpoch,
      'toUtcMs': window.endUtc.millisecondsSinceEpoch,
    });
  });

  test('a one-off instance maps like an ICS one-off', () async {
    final o = (await fetched([
      row(
        location: 'Room 4',
        description: 'Join: https://teams.microsoft.com/l/meetup-join/abc',
      ),
    ])).single;
    expect(o.key, 'phone|10|2026-10-06T08:00:00.000Z');
    expect(o.seriesUid, isNull);
    expect(o.title, 'Sprint planning');
    expect(o.organizer, 'thandi@example.com');
    expect(o.joinUrl, 'https://teams.microsoft.com/l/meetup-join/abc');
    expect(o.startUtc, DateTime.utc(2026, 10, 6, 8));
    expect(o.endUtc, DateTime.utc(2026, 10, 6, 8, 30));
    expect(o.busyStatus, BusyStatus.busy);
    expect(o.declined, isFalse);
    expect(o.cancelled, isFalse);
    expect(o.calendarColor, 0xFF33AA66);
  });

  test('a moved instance of a series keeps the series key', () async {
    final series = (await fetched([row(recurring: true)])).single;
    final moved = (await fetched([
      row(
        eventId: '12',
        beginMs: 1791277200000, // moved to 09:00
        endMs: 1791279000000,
        originalId: '10',
        originalInstanceTimeMs: 1791273600000,
      ),
    ])).single;
    expect(series.seriesUid, '10');
    expect(moved.seriesUid, '10');
    expect(moved.key, series.key);
    expect(moved.startUtc, DateTime.utc(2026, 10, 6, 9));
  });

  test(
    'availability, declined and cancelled map to the skip-filter fields',
    () async {
      final rows = await fetched([
        row(eventId: '1', availability: DeviceInstance.availabilityFree),
        row(eventId: '2', availability: DeviceInstance.availabilityTentative),
        row(eventId: '3', availability: 9),
        row(eventId: '4', selfAttendeeStatus: DeviceInstance.attendeeDeclined),
        row(eventId: '5', status: DeviceInstance.statusCancelled),
      ]);
      expect(rows.map((o) => o.busyStatus).take(3), [
        BusyStatus.free,
        BusyStatus.tentative,
        BusyStatus.unknown,
      ]);
      expect(rows[3].declined, isTrue);
      expect(rows[4].cancelled, isTrue);
    },
  );

  test('an all-day instance starts at local midnight', () async {
    final o = (await fetched([
      row(
        allDay: true,
        beginMs: DateTime.utc(2026, 10, 7).millisecondsSinceEpoch,
        endMs: DateTime.utc(2026, 10, 8).millisecondsSinceEpoch,
      ),
    ])).single;
    expect(o.allDay, isTrue);
    expect(o.startUtc, DateTime.utc(2026, 10, 6, 22)); // 00:00 in Johannesburg
    expect(o.endUtc, DateTime.utc(2026, 10, 7, 22));
    expect(o.originalStartUtc, o.startUtc);
  });

  test(
    'a blank title reads "(No title)" and blank fields are dropped',
    () async {
      final o = (await fetched([row(title: '  ', location: ' ')])).single;
      expect(o.title, '(No title)');
      expect(o.location, isNull);
    },
  );

  test('a revoked permission and a removed calendar are reported', () async {
    answer((_) => throw PlatformException(code: 'permission_denied'));
    final denied = await source().fetch(window) as SourceFailed;
    expect(denied.outcome, SyncOutcome.calendarAccessDenied);

    answer((_) => throw PlatformException(code: 'calendar_missing'));
    final missing = await source().fetch(window) as SourceFailed;
    expect(missing.outcome, SyncOutcome.calendarMissing);

    answer((_) => throw PlatformException(code: 'engine_error'));
    expect(
      (await source().fetch(window) as SourceFailed).outcome,
      SyncOutcome.otherError,
    );
  });

  test('a source without a calendar id fails without a call', () async {
    answer((_) => []);
    final r = await source(
      config: const SourceConfig(
        id: 'phone',
        name: 'x',
        color: 0,
        kind: SourceKind.device,
      ),
    ).fetch(window);
    expect((r as SourceFailed).outcome, SyncOutcome.calendarMissing);
    expect(calls, isEmpty);
  });

  test('calendars() lists the phone calendars', () async {
    answer(
      (_) => [
        {
          'id': '3',
          'name': 'Work',
          'accountName': 'me@example.com',
          'color': 0xFF6AA0F5,
          'visible': true,
        },
      ],
    );
    final c = (await DeviceCalendarApi().calendars()).single;
    expect(calls.single.method, 'queryDeviceCalendars');
    expect(
      (c.id, c.name, c.accountName, c.color, c.visible),
      ('3', 'Work', 'me@example.com', 0xFF6AA0F5, true),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/sources/device_calendar_source_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sources/device_calendar_api.dart'`.

- [ ] **Step 3: Implement the channel client**

`lib/core/sources/device_calendar_api.dart`:

```dart
import 'package:flutter/services.dart';

import '../engine/alarm_engine.dart';

/// One calendar on the phone (`queryDeviceCalendars`).
class DeviceCalendar {
  const DeviceCalendar({
    required this.id,
    required this.name,
    this.accountName,
    required this.color,
    required this.visible,
  });

  factory DeviceCalendar.fromJson(Map<String, Object?> j) => DeviceCalendar(
    id: j['id'] as String,
    name: j['name'] as String,
    accountName: j['accountName'] as String?,
    color: j['color'] as int,
    visible: j['visible'] as bool,
  );

  final String id;
  final String name;
  final String? accountName;

  /// Opaque ARGB; pre-fills the colour when the user adds the source.
  final int color;
  final bool visible;
}

/// One row of `CalendarContract.Instances` (`queryInstances`).
class DeviceInstance {
  const DeviceInstance({
    required this.eventId,
    required this.calendarId,
    required this.beginMs,
    required this.endMs,
    required this.allDay,
    this.title,
    this.location,
    this.description,
    this.organizer,
    required this.availability,
    required this.selfAttendeeStatus,
    this.status,
    this.originalId,
    this.originalInstanceTimeMs,
    required this.recurring,
  });

  factory DeviceInstance.fromJson(Map<String, Object?> j) => DeviceInstance(
    eventId: j['eventId'] as String,
    calendarId: j['calendarId'] as String,
    beginMs: j['beginMs'] as int,
    endMs: j['endMs'] as int,
    allDay: j['allDay'] as bool,
    title: j['title'] as String?,
    location: j['location'] as String?,
    description: j['description'] as String?,
    organizer: j['organizer'] as String?,
    availability: j['availability'] as int,
    selfAttendeeStatus: j['selfAttendeeStatus'] as int,
    status: j['status'] as int?,
    originalId: j['originalId'] as String?,
    originalInstanceTimeMs: j['originalInstanceTimeMs'] as int?,
    recurring: j['recurring'] as bool,
  );

  static const availabilityBusy = 0;
  static const availabilityFree = 1;
  static const availabilityTentative = 2;
  static const attendeeDeclined = 2;
  static const statusCancelled = 2;

  final String eventId;
  final String calendarId;

  /// UTC ms. For all-day events these are UTC midnights of the dates.
  final int beginMs;
  final int endMs;
  final bool allDay;
  final String? title;
  final String? location;
  final String? description;
  final String? organizer;
  final int availability;
  final int selfAttendeeStatus;
  final int? status;

  /// Set on a moved or edited instance of a series: the series' event id and
  /// the instance's original start.
  final String? originalId;
  final int? originalInstanceTimeMs;

  /// The event has an RRULE or RDATE.
  final bool recurring;
}

/// The device-calendar calls Plan 4 adds to the `alarm_engine` channel
/// (roadmap §3). Errors arrive as [PlatformException]s with code
/// [permissionDenied] or [calendarMissing].
class DeviceCalendarApi {
  DeviceCalendarApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(AlarmEngine.methodChannelName);

  static const permissionDenied = 'permission_denied';
  static const calendarMissing = 'calendar_missing';

  final MethodChannel _channel;

  Future<List<DeviceCalendar>> calendars() async {
    final raw =
        await _channel.invokeListMethod<Object?>('queryDeviceCalendars') ??
        const [];
    return [
      for (final c in raw)
        DeviceCalendar.fromJson((c! as Map).cast<String, Object?>()),
    ];
  }

  Future<List<DeviceInstance>> instances({
    required List<String> calendarIds,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final raw =
        await _channel.invokeListMethod<Object?>('queryInstances', {
          'calendarIds': calendarIds,
          'fromUtcMs': fromUtc.millisecondsSinceEpoch,
          'toUtcMs': toUtc.millisecondsSinceEpoch,
        }) ??
        const [];
    return [
      for (final i in raw)
        DeviceInstance.fromJson((i! as Map).cast<String, Object?>()),
    ];
  }
}
```

- [ ] **Step 4: Add the device mapping**

In `lib/core/sources/occurrence_mapping.dart`, replace the imports

```dart
import 'package:ics_core/ics_core.dart';

import '../model/event_occurrence.dart';
import '../model/source_config.dart';
```

with

```dart
import 'package:ics_core/ics_core.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/event_occurrence.dart';
import '../model/source_config.dart';
import 'device_calendar_api.dart';
```

and append to the end of the file:

```dart
/// A `CalendarContract.Instances` row as an occurrence, keyed like ICS
/// (Plan 4 decision): uid is the series' event id for any instance of a
/// series (`ORIGINAL_ID` for a moved one), and the original start is
/// `ORIGINAL_INSTANCE_TIME`, else `BEGIN`. All-day instances arrive as UTC
/// midnights and become local midnights in [zone], as `ics_core` does.
EventOccurrence occurrenceFromDevice(
  DeviceInstance i,
  SourceConfig source,
  tz.Location zone,
) {
  DateTime instant(int ms) {
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    if (!i.allDay) return utc;
    return tz.TZDateTime(zone, utc.year, utc.month, utc.day);
  }

  final uid = i.originalId ?? i.eventId;
  final title = i.title?.trim() ?? '';
  return EventOccurrence(
    sourceId: source.id,
    uid: uid,
    originalStartUtc: instant(i.originalInstanceTimeMs ?? i.beginMs),
    seriesUid: i.recurring || i.originalId != null ? uid : null,
    title: title.isEmpty ? '(No title)' : title,
    location: _blankToNull(i.location),
    organizer: _blankToNull(i.organizer),
    description: _blankToNull(i.description),
    joinUrl: extractTeamsJoinUrl(i.description, i.location),
    startUtc: instant(i.beginMs),
    endUtc: instant(i.endMs),
    allDay: i.allDay,
    busyStatus: switch (i.availability) {
      DeviceInstance.availabilityBusy => BusyStatus.busy,
      DeviceInstance.availabilityFree => BusyStatus.free,
      DeviceInstance.availabilityTentative => BusyStatus.tentative,
      _ => BusyStatus.unknown,
    },
    declined: i.selfAttendeeStatus == DeviceInstance.attendeeDeclined,
    cancelled: i.status == DeviceInstance.statusCancelled,
    calendarColor: source.color,
  );
}

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s;
```

- [ ] **Step 5: Implement the source**

`lib/core/sources/device_calendar_source.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/source_config.dart';
import '../model/sync_log_entry.dart';
import 'calendar_source.dart';
import 'device_calendar_api.dart';
import 'occurrence_mapping.dart';

/// One Android calendar, read through `queryInstances` (spec §5).
class DeviceCalendarSource implements CalendarSource {
  DeviceCalendarSource({
    required this.config,
    required this.api,
    required this.zone,
  });

  final SourceConfig config;
  final DeviceCalendarApi api;

  /// The device zone, for all-day instances.
  final tz.Location zone;

  @override
  String get id => config.id;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    final calendarId = config.deviceCalendarId;
    if (calendarId == null) {
      return const SourceFailed(
        SyncOutcome.calendarMissing,
        'No phone calendar is chosen for this source.',
      );
    }
    try {
      final instances = await api.instances(
        calendarIds: [calendarId],
        fromUtc: window.startUtc,
        toUtc: window.endUtc,
      );
      return SourceFetched([
        for (final i in instances) occurrenceFromDevice(i, config, zone),
      ]);
    } on PlatformException catch (e) {
      return switch (e.code) {
        DeviceCalendarApi.permissionDenied => const SourceFailed(
          SyncOutcome.calendarAccessDenied,
          'Calendar access was turned off.',
        ),
        DeviceCalendarApi.calendarMissing => const SourceFailed(
          SyncOutcome.calendarMissing,
          'This calendar was removed from the phone.',
        ),
        _ => SourceFailed(
          SyncOutcome.otherError,
          'Could not read the phone calendar (${e.code}).',
        ),
      };
    } on MissingPluginException {
      return const SourceFailed(
        SyncOutcome.otherError,
        'Phone calendars are not available on this platform.',
      );
    }
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `dart format lib/core/sources test/core/sources`
Run: `flutter test test/core/sources`
Expected: `All tests passed!` (9 new tests, and Tasks 1–3's).

- [ ] **Step 7: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 8: Commit**

```bash
git add lib/core/sources test/core/sources
git commit -m "Turn phone calendar instances into occurrences keyed like feed events"
```

---

### Task 6: Engine event recorder

**Files:**
- Create: `lib/core/sync/engine_event_recorder.dart`
- Test: `test/core/sync/engine_event_recorder_test.dart`

**Interfaces:**
- Consumes: `AlarmEngine.events`, `AlarmEngine.drainEvents`, `EngineEvent` (Plan 3); `AlertHistoryRepository.record` (returns `false` for a duplicate), `OccurrenceRepository.byKey`, `AlertHistoryEntry`, `AlertEventType` (Plan 2).
- Produces: `class EngineEventRecorder({required AlarmEngine engine, required AlertHistoryRepository history, required OccurrenceRepository occurrences})` with public fields of those names, `Future<void> start()` (UI isolate: listen, then drain; never throws for a missing engine), `Future<List<AlertHistoryEntry>> drainNow()` (the rows that were new), `Future<void> stop()`, `bool get isListening`, `Stream<AlertHistoryEntry> get recorded` (broadcast; only newly inserted rows). Event `type` maps to `AlertEventType` by name; `title` is the cached occurrence's title, or null (test alarms, pruned occurrences).

This is the one consumer Plan 3's final decision asks for. Nothing else in the app may call `drainEvents` (Task 14 reroutes the engine debug panel's **Drain events**). Listening to the broadcast `events` stream for a UI refresh is fine.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/engine_event_recorder.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel(AlarmEngine.methodChannelName);
  const events = EventChannel(AlarmEngine.eventChannelName);

  late AppDatabase db;
  late AlertHistoryRepository history;
  late EngineEventRecorder recorder;
  late List<Map<String, Object?>> queued;
  final meeting = occ(uid: 'm1', title: 'Sprint planning');

  Map<String, Object?> json(String type, String alertId, int atMs) => {
    'type': type,
    'alertId': alertId,
    'occurrenceKey': meeting.key,
    'startUtcMs': meeting.startUtc.millisecondsSinceEpoch,
    'atUtcMs': atMs,
    'snoozeUntilUtcMs': type == 'snoozed' ? atMs + 60000 : null,
  };

  setUp(() async {
    db = openTestDatabase();
    history = AlertHistoryRepository(db);
    await SourceRepository(db).save(
      const SourceConfig(
        id: 'work',
        name: 'Work',
        color: blue,
        kind: SourceKind.ics,
      ),
    );
    await OccurrenceRepository(db).replaceForSource('work', [meeting]);
    queued = [];
    messenger.setMockMethodCallHandler(method, (call) async {
      if (call.method != 'drainEvents') return null;
      final drained = List.of(queued);
      queued.clear();
      return drained;
    });
    recorder = EngineEventRecorder(
      engine: AlarmEngine(),
      history: history,
      occurrences: OccurrenceRepository(db),
    );
  });

  tearDown(() async {
    await recorder.stop();
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(events, null);
    await db.close();
  });

  test('drainNow records queued events with the cached title', () async {
    queued.addAll([json('fired', 'a', 1000), json('snoozed', 'a', 2000)]);
    expect(await recorder.drainNow(), hasLength(2));
    final rows = await history.recent();
    expect(rows.map((r) => r.type), [
      AlertEventType.snoozed,
      AlertEventType.fired,
    ]);
    expect(rows.first.title, 'Sprint planning');
    expect(rows.first.snoozeUntilUtc, isNotNull);
    expect(queued, isEmpty);
  });

  test(
    'an event whose occurrence is not cached is recorded without a title',
    () async {
      queued.add({...json('fired', 't', 1000), 'occurrenceKey': 'test|1000'});
      await recorder.drainNow();
      expect((await history.recent()).single.title, isNull);
    },
  );

  test('start records live events and drains the queue, each once', () async {
    queued.add(json('fired', 'a', 1000));
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, sink) {
          sink.success(json('dismissed', 'a', 3000));
          sink.success(json('dismissed', 'a', 3000)); // repeated: dropped
        },
      ),
    );
    final recorded = <AlertHistoryEntry>[];
    recorder.recorded.listen(recorded.add);

    await recorder.start();
    await waitUntil(() => recorded.length == 2);

    expect(recorder.isListening, isTrue);
    expect(recorded.map((e) => e.type).toSet(), {
      AlertEventType.fired,
      AlertEventType.dismissed,
    });
    expect(await history.recent(), hasLength(2));
  });

  test('a row already stored by another isolate is not re-broadcast', () async {
    queued.add(json('fired', 'a', 1000));
    await history.record(
      AlertHistoryEntry(
        type: AlertEventType.fired,
        alertId: 'a',
        occurrenceKey: meeting.key,
        startUtc: meeting.startUtc,
        atUtc: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      ),
    );
    final recorded = <AlertHistoryEntry>[];
    recorder.recorded.listen(recorded.add);
    expect(await recorder.drainNow(), isEmpty);
    await pumpEventQueue();
    expect(recorded, isEmpty);
  });

  test('start without a native engine does not throw', () async {
    messenger.setMockMethodCallHandler(
      method,
      (call) async => throw MissingPluginException(),
    );
    await recorder.start();
    expect(recorder.isListening, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/sync/engine_event_recorder_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sync/engine_event_recorder.dart'`.

- [ ] **Step 3: Implement `lib/core/sync/engine_event_recorder.dart`**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/alarm_engine.dart';
import '../model/alert_history_entry.dart';
import '../storage/alert_history_repository.dart';
import '../storage/occurrence_repository.dart';

/// The one consumer of [AlarmEngine.events] and [AlarmEngine.drainEvents] in
/// an isolate (Plan 3: each event reaches Dart once, so a second consumer
/// would steal events from history). Records each event in `alert_history`
/// and re-broadcasts what it recorded on [recorded] for the UI (Plan 5).
///
/// The UI isolate calls [start]; the headless sync only calls [drainNow].
class EngineEventRecorder {
  EngineEventRecorder({
    required this.engine,
    required this.history,
    required this.occurrences,
  });

  final AlarmEngine engine;
  final AlertHistoryRepository history;
  final OccurrenceRepository occurrences;
  final _recorded = StreamController<AlertHistoryEntry>.broadcast();
  StreamSubscription<EngineEvent>? _live;

  /// Every entry this recorder inserted (duplicates are not repeated).
  Stream<AlertHistoryEntry> get recorded => _recorded.stream;

  bool get isListening => _live != null;

  /// Records live events from now on, then drains what queued while no
  /// Flutter engine was listening (spec §7). Safe to call twice.
  Future<void> start() async {
    _live ??= engine.events.listen(
      (e) => unawaited(_record(e)),
      onError: (Object e) => debugPrint('Engine event stream failed: $e'),
    );
    try {
      await drainNow();
    } on MissingPluginException {
      // No native engine (widget tests, desktop).
    } on PlatformException catch (e) {
      debugPrint('drainEvents failed: ${e.code}');
    }
  }

  /// Drains the native queue into history. Returns the rows that were new.
  Future<List<AlertHistoryEntry>> drainNow() async {
    final inserted = <AlertHistoryEntry>[];
    for (final event in await engine.drainEvents()) {
      final entry = await _record(event);
      if (entry != null) inserted.add(entry);
    }
    return inserted;
  }

  Future<void> stop() async {
    await _live?.cancel();
    _live = null;
  }

  /// The stored row, or null when it was already there.
  Future<AlertHistoryEntry?> _record(EngineEvent e) async {
    final entry = AlertHistoryEntry(
      type: AlertEventType.values.byName(e.type.name),
      alertId: e.alertId,
      occurrenceKey: e.occurrenceKey,
      startUtc: e.startUtc,
      atUtc: e.atUtc,
      snoozeUntilUtc: e.snoozeUntilUtc,
      title: (await occurrences.byKey(e.occurrenceKey))?.title,
    );
    if (!await history.record(entry)) return null;
    _recorded.add(entry);
    return entry;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart format lib/core/sync test/core/sync`
Run: `flutter test test/core/sync/engine_event_recorder_test.dart`
Expected: `All tests passed!` (5 tests).

- [ ] **Step 5: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 6: Commit**

```bash
git add lib/core/sync/engine_event_recorder.dart test/core/sync/engine_event_recorder_test.dart
git commit -m "Record engine events into alert history from one consumer"
```

---

### Task 7: Missed (system) detection and pre-alarm sync times

**Files:**
- Create: `lib/core/sync/missed_system.dart`, `lib/core/sync/pre_sync.dart`
- Test: `test/core/sync/missed_system_test.dart`

**Interfaces:**
- Consumes: `PlannedAlert`, `AlertHistoryEntry`, `AlertEventType.missedSystem`, `plainUtc` (Plans 2, 3).
- Produces: `class ExpectedAlert({id, occurrenceKey, fireAtUtc, startUtc, title})` with `factory ExpectedAlert.of(PlannedAlert a)`, `toJson`/`fromJson`, value equality; `class MissedCheck({required List<AlertHistoryEntry> missed, required List<ExpectedAlert> pending})`; `abstract final class MissedSystemDetector` with `static const grace = Duration(minutes: 2)`, `static MissedCheck check({required List<ExpectedAlert> expected, required List<AlertHistoryEntry> history, required DateTime now})`, `static List<ExpectedAlert> expectedAfterApply({required List<ExpectedAlert> pending, required List<PlannedAlert> plan, required DateTime now})`, `static String encode(List<ExpectedAlert>)`, `static List<ExpectedAlert> decode(String?)` (junk → empty); `const preSyncLead = Duration(minutes: 12)` and `List<DateTime> preSyncTimes(Iterable<PlannedAlert> plan, DateTime now)`.

Both are pure: decisions 2 and 5 in code, with no storage or channel.

- [ ] **Step 1: Write the failing test**

`test/core/sync/missed_system_test.dart` (the meeting starts 08:00; the alarm fires 07:59):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/alert.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/sync/missed_system.dart';
import 'package:tminus/core/sync/pre_sync.dart';

final _start = DateTime.utc(2026, 10, 6, 8);

PlannedAlert planned(
  String key,
  int offset, {
  DateTime? start,
  AlertStrength strength = AlertStrength.alarm,
}) {
  final s = start ?? _start;
  final fireAt = s.subtract(Duration(minutes: offset));
  return PlannedAlert(
    id: PlannedAlert.idFor(key, offset),
    occurrenceKey: key,
    fireAtUtc: fireAt,
    offsetMinutes: offset,
    strength: strength,
    sound: const SoundSettings(),
    event: EventSnapshot(
      title: 'Meeting $key',
      startUtc: s,
      endUtc: s.add(const Duration(minutes: 30)),
      color: 0xFF6AA0F5,
    ),
    coalesceGroup: PlannedAlert.groupFor(fireAt),
  );
}

AlertHistoryEntry event(AlertEventType type, PlannedAlert a, DateTime at) =>
    AlertHistoryEntry(
      type: type,
      alertId: a.id,
      occurrenceKey: a.occurrenceKey,
      startUtc: a.event.startUtc,
      atUtc: at,
    );

void main() {
  final alarm = planned('k1', 1); // fires 07:59
  final expected = ExpectedAlert.of(alarm);
  final fireAt = alarm.fireAtUtc;

  MissedCheck check(List<AlertHistoryEntry> history, DateTime now) =>
      MissedSystemDetector.check(
        expected: [expected],
        history: history,
        now: now,
      );

  group('check', () {
    test('an alert inside its 2 min grace stays pending', () {
      final r = check([], fireAt.add(const Duration(minutes: 2)));
      expect(r.missed, isEmpty);
      expect(r.pending, [expected]);
    });

    test('no fired record by fireAt + 2 min is missed (system)', () {
      final r = check([], fireAt.add(const Duration(minutes: 2, seconds: 1)));
      expect(r.pending, isEmpty);
      final m = r.missed.single;
      expect(m.type, AlertEventType.missedSystem);
      expect(m.alertId, alarm.id);
      expect(m.occurrenceKey, 'k1');
      expect(m.startUtc, _start);
      expect(m.atUtc, fireAt);
      expect(m.title, 'Meeting k1');
    });

    test('a fired record in time clears it', () {
      final r = check([
        event(
          AlertEventType.fired,
          alarm,
          fireAt.add(const Duration(seconds: 3)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, isEmpty);
      expect(r.pending, isEmpty);
    });

    test('an alert that rang more than 2 min late still counts', () {
      final r = check([
        event(
          AlertEventType.fired,
          alarm,
          fireAt.add(const Duration(minutes: 5)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, hasLength(1));
    });

    test('a fired record for another start does not count', () {
      final other = planned(
        'k1',
        1,
        start: _start.add(const Duration(days: 7)),
      );
      final r = check([
        event(AlertEventType.fired, other, fireAt),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, hasLength(1));
    });

    test('Dismiss all or Join before the alert time excuses it', () {
      final headsUp = planned('k1', 10);
      for (final type in [AlertEventType.dismissedAll, AlertEventType.joined]) {
        final r = check([
          event(type, headsUp, headsUp.fireAtUtc),
        ], fireAt.add(const Duration(hours: 1)));
        expect(r.missed, isEmpty, reason: type.name);
      }
    });

    test('an acknowledgement after the alert time does not excuse it', () {
      final r = check([
        event(
          AlertEventType.dismissedAll,
          alarm,
          fireAt.add(const Duration(minutes: 1)),
        ),
      ], fireAt.add(const Duration(hours: 1)));
      expect(r.missed, hasLength(1));
    });
  });

  group('expectedAfterApply', () {
    final now = DateTime.utc(2026, 10, 6, 7, 55);

    test(
      'future alerts are expected; past ones that were never expected are not',
      () {
        final r = MissedSystemDetector.expectedAfterApply(
          pending: const [],
          plan: [
            planned('k1', 10),
            planned('k1', 1),
          ], // 07:50 past, 07:59 future
          now: now,
        );
        expect(r, [ExpectedAlert.of(planned('k1', 1))]);
      },
    );

    test(
      'a pending alert still in the plan at the same time is carried over',
      () {
        final headsUp = planned('k1', 10);
        final r = MissedSystemDetector.expectedAfterApply(
          pending: [ExpectedAlert.of(headsUp)],
          plan: [headsUp, planned('k1', 1)],
          now: now,
        );
        expect(r.map((e) => e.id), [headsUp.id, planned('k1', 1).id]);
      },
    );

    test('a pending alert that was removed or moved is dropped', () {
      final headsUp = planned('k1', 10);
      final moved = planned(
        'k1',
        10,
        start: _start.subtract(const Duration(minutes: 1)),
      );
      final r = MissedSystemDetector.expectedAfterApply(
        pending: [ExpectedAlert.of(headsUp)],
        plan: [moved],
        now: now,
      );
      expect(r, isEmpty);
    });
  });

  test('expected alerts round-trip through JSON; junk reads as none', () {
    final list = [expected, ExpectedAlert.of(planned('k2', 10))];
    expect(
      MissedSystemDetector.decode(MissedSystemDetector.encode(list)),
      list,
    );
    expect(MissedSystemDetector.decode(null), isEmpty);
    expect(MissedSystemDetector.decode('{not json'), isEmpty);
    expect(MissedSystemDetector.decode('[{"id": 1}]'), isEmpty);
  });

  group('preSyncTimes', () {
    test('one time per occurrence, 12 min before its earliest alert', () {
      final now = DateTime.utc(2026, 10, 6, 6);
      final later = _start.add(const Duration(hours: 2));
      final times = preSyncTimes([
        planned('k1', 30, strength: AlertStrength.headsUp),
        planned('k1', 10, strength: AlertStrength.headsUp),
        planned('k1', 2),
        planned('k2', 1, start: later),
      ], now);
      expect(times, [
        DateTime.utc(2026, 10, 6, 7, 18), // 08:00 − 30 − 12
        DateTime.utc(2026, 10, 6, 9, 47), // 10:00 − 1 − 12
      ]);
    });

    test(
      'an occurrence whose first alert already passed gets no second pre-sync',
      () {
        final now = DateTime.utc(2026, 10, 6, 7, 40); // after the −30 alert
        expect(
          preSyncTimes([planned('k1', 30), planned('k1', 2)], now),
          isEmpty,
        );
      },
    );

    test('occurrences sharing a time share one entry', () {
      final now = DateTime.utc(2026, 10, 6, 6);
      expect(preSyncTimes([planned('a', 1), planned('b', 1)], now), [
        DateTime.utc(2026, 10, 6, 7, 47),
      ]);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/sync/missed_system_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sync/missed_system.dart'`.

- [ ] **Step 3: Implement**

`lib/core/sync/missed_system.dart`:

```dart
import 'dart:convert';

import '../model/alert_history_entry.dart';
import '../model/planned_alert.dart';
import '../model/utc.dart';

/// An alert a plan armed in the future, so a `fired` record is owed for it.
class ExpectedAlert {
  ExpectedAlert({
    required this.id,
    required this.occurrenceKey,
    required DateTime fireAtUtc,
    required DateTime startUtc,
    required this.title,
  }) : fireAtUtc = plainUtc(fireAtUtc),
       startUtc = plainUtc(startUtc);

  factory ExpectedAlert.of(PlannedAlert a) => ExpectedAlert(
    id: a.id,
    occurrenceKey: a.occurrenceKey,
    fireAtUtc: a.fireAtUtc,
    startUtc: a.event.startUtc,
    title: a.event.title,
  );

  factory ExpectedAlert.fromJson(Map<String, Object?> j) => ExpectedAlert(
    id: j['id'] as String,
    occurrenceKey: j['occurrenceKey'] as String,
    fireAtUtc: DateTime.fromMillisecondsSinceEpoch(
      j['fireAtUtcMs'] as int,
      isUtc: true,
    ),
    startUtc: DateTime.fromMillisecondsSinceEpoch(
      j['startUtcMs'] as int,
      isUtc: true,
    ),
    title: j['title'] as String,
  );

  final String id;
  final String occurrenceKey;
  final DateTime fireAtUtc;
  final DateTime startUtc;
  final String title;

  Map<String, Object?> toJson() => {
    'id': id,
    'occurrenceKey': occurrenceKey,
    'fireAtUtcMs': fireAtUtc.millisecondsSinceEpoch,
    'startUtcMs': startUtc.millisecondsSinceEpoch,
    'title': title,
  };

  /// Identity for carrying an alert over between syncs: a moved alert is a
  /// new expectation.
  String get _slot => '$id|${fireAtUtc.millisecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      other is ExpectedAlert &&
      other.id == id &&
      other.occurrenceKey == occurrenceKey &&
      other.fireAtUtc == fireAtUtc &&
      other.startUtc == startUtc &&
      other.title == title;

  @override
  int get hashCode =>
      Object.hash(id, occurrenceKey, fireAtUtc, startUtc, title);

  @override
  String toString() => 'ExpectedAlert($id, $fireAtUtc)';
}

class MissedCheck {
  const MissedCheck({required this.missed, required this.pending});

  /// `missedSystem` rows to record. `atUtc` is the alert's fire time, so the
  /// same miss found twice is one row (history de-duplicates).
  final List<AlertHistoryEntry> missed;

  /// Expected alerts whose grace period has not passed yet.
  final List<ExpectedAlert> pending;
}

/// Spec §9 "Alert time passed by > 2 min without a `fired` record → logged as
/// missed (system)", as Plan 4 defines it: only alerts that were still in the
/// future when a plan armed them count; an alert that rang more than 2 min
/// late counts too; an occurrence dismissed-all or joined before the alert's
/// time does not.
abstract final class MissedSystemDetector {
  static const grace = Duration(minutes: 2);

  /// Checks every expected alert whose fire time is more than [grace] ago.
  /// [history] must cover the expected alerts' occurrences (Plan 4 passes
  /// everything since a day before the oldest fire time).
  static MissedCheck check({
    required List<ExpectedAlert> expected,
    required List<AlertHistoryEntry> history,
    required DateTime now,
  }) {
    final missed = <AlertHistoryEntry>[];
    final pending = <ExpectedAlert>[];
    for (final e in expected) {
      final deadline = e.fireAtUtc.add(grace);
      if (!now.isAfter(deadline)) {
        pending.add(e);
        continue;
      }
      final firedInTime = history.any(
        (h) =>
            h.type == AlertEventType.fired &&
            h.alertId == e.id &&
            h.startUtc == e.startUtc &&
            !h.atUtc.isAfter(deadline),
      );
      final ackedBefore = history.any(
        (h) =>
            (h.type == AlertEventType.dismissedAll ||
                h.type == AlertEventType.joined) &&
            h.occurrenceKey == e.occurrenceKey &&
            h.startUtc == e.startUtc &&
            !h.atUtc.isAfter(e.fireAtUtc),
      );
      if (firedInTime || ackedBefore) continue;
      missed.add(
        AlertHistoryEntry(
          type: AlertEventType.missedSystem,
          alertId: e.id,
          occurrenceKey: e.occurrenceKey,
          startUtc: e.startUtc,
          atUtc: e.fireAtUtc,
          title: e.title,
        ),
      );
    }
    return MissedCheck(missed: missed, pending: pending);
  }

  /// What to expect after [plan] is applied at [now]: every future alert in
  /// it, plus [pending] alerts the plan still lists at the same time. Past
  /// alerts that were never expected (a meeting added after its first alert)
  /// are not armed by Kotlin, so nothing is owed for them.
  static List<ExpectedAlert> expectedAfterApply({
    required List<ExpectedAlert> pending,
    required List<PlannedAlert> plan,
    required DateTime now,
  }) {
    final carried = {for (final p in pending) p._slot};
    final result = <String, ExpectedAlert>{};
    for (final a in plan) {
      final e = ExpectedAlert.of(a);
      if (a.fireAtUtc.isAfter(now) || carried.contains(e._slot)) {
        result[e._slot] = e;
      }
    }
    return result.values.toList();
  }

  static String encode(List<ExpectedAlert> expected) =>
      jsonEncode([for (final e in expected) e.toJson()]);

  /// Unreadable text reads as nothing expected, never as an error.
  static List<ExpectedAlert> decode(String? json) {
    if (json == null) return const [];
    try {
      return [
        for (final e in jsonDecode(json) as List<Object?>)
          ExpectedAlert.fromJson((e! as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }
}
```

`lib/core/sync/pre_sync.dart`:

```dart
import '../model/planned_alert.dart';

/// Spec §7: a sync runs this long before each occurrence's earliest alert.
const preSyncLead = Duration(minutes: 12);

/// One time per occurrence: its earliest alert − [preSyncLead], counting
/// alerts that have already passed (the plan still lists them), so an
/// occurrence gets one pre-alarm sync, not one per alert. Only future times,
/// sorted, without duplicates.
List<DateTime> preSyncTimes(Iterable<PlannedAlert> plan, DateTime now) {
  final earliest = <String, DateTime>{};
  for (final a in plan) {
    final current = earliest[a.occurrenceKey];
    if (current == null || a.fireAtUtc.isBefore(current)) {
      earliest[a.occurrenceKey] = a.fireAtUtc;
    }
  }
  final times = {
    for (final t in earliest.values)
      if (t.subtract(preSyncLead).isAfter(now)) t.subtract(preSyncLead),
  }.toList()..sort();
  return times;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart format lib/core/sync test/core/sync`
Run: `flutter test test/core/sync/missed_system_test.dart`
Expected: `All tests passed!` (14 tests).

- [ ] **Step 5: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 6: Commit**

```bash
git add lib/core/sync/missed_system.dart lib/core/sync/pre_sync.dart test/core/sync/missed_system_test.dart
git commit -m "Detect missed (system) alerts and work out pre-alarm sync times"
```

---

### Task 8: Sync scheduling (WorkManager and the pre-alarm alarm)

**Files:**
- Modify: `android/app/build.gradle.kts` (WorkManager, concurrent-futures, work-testing)
- Create: `android/app/src/main/kotlin/io/github/fifothehein/tminus/sync/SyncWorker.kt`, `.../sync/SyncScheduler.kt`, `.../sync/PreSyncScheduler.kt`
- Modify: `android/app/src/main/AndroidManifest.xml` (two receivers)
- Test: `android/app/src/test/kotlin/io/github/fifothehein/tminus/sync/SyncSchedulingTest.kt`

**Interfaces:**
- Consumes: `TimeChangeReceiver.ACTION_EXACT_ALARM_PERMISSION_CHANGED`, `R.drawable.ic_stat_tminus` (Plan 3).
- Produces: `fun interface SyncRunner { fun run(trigger: String, done: (String) -> Unit): () -> Unit }` (returns a cancel function); `class SyncWorker(context, params, runner: SyncRunner) : ListenableWorker` with `KEY_TRIGGER = "trigger"`, triggers `TRIGGER_PERIODIC = "periodic"`, `TRIGGER_CALENDAR_CHANGE = "calendarChange"`, `TRIGGER_PRE_ALARM = "preAlarm"`, `TRIGGER_MANUAL = "manual"` (the names of Dart's `SyncTrigger` values), outcomes `OUTCOME_OK = "ok"`, `OUTCOME_RETRY = "retry"`, `OUTCOME_BUSY = "busy"`, `fun input(trigger): Data`, `fun resultFor(outcome): Result`, `CHANNEL_RUNNING = "sync_running"`; `class SyncScheduler(context, workManager = WorkManager.getInstance(context))` with `ensurePeriodic()`, `runNow(trigger: String, expedited: Boolean)`, `setCalendarWatch(enabled: Boolean)`, `internal rewatch()`, constants `PERIODIC = "tminus.sync.periodic"`, `CALENDAR_WATCH = "tminus.sync.calendarWatch"`, `fun nowName(trigger) = "tminus.sync.now.$trigger"`; `class CalendarWatchWorker : Worker`; `class PreSyncScheduler(context, clock)` with `setTimes(List<Long>)`, `times()`, `next()`, `armNext()`, `ACTION = "io.github.fifothehein.tminus.PRE_SYNC"`, `PREFS = "tminus_sync"`; `class PreSyncReceiver`; `class SyncBootReceiver` with `ACTIONS` (BOOT_COMPLETED, MY_PACKAGE_REPLACED, TIME_SET, TIMEZONE_CHANGED, exact-alarm permission changed).

`SyncWorker` gets its `(Context, WorkerParameters)` constructor, the one WorkManager's default factory calls, in Task 13, together with `HeadlessFlutterRunner`. Until then nothing enqueues work outside tests: `MainActivity` starts scheduling in Task 9, and a device run between Tasks 9 and 13 logs WorkManager's "Could not create Worker" for the sync and carries on.

- [ ] **Step 1: Add the dependencies**

In `android/app/build.gradle.kts`, after `implementation("androidx.compose.foundation:foundation")` add:

```kotlin
    // Plan 4 (checked on Google Maven, 2026-10-08): WorkManager 2.12.0 declares minCompileSdk=35;
    // concurrent-futures gives SyncWorker CallbackToFutureAdapter without coroutines of our own.
    implementation("androidx.work:work-runtime:2.12.0")
    implementation("androidx.concurrent:concurrent-futures:1.3.0")
```

and after `testImplementation("org.robolectric:robolectric:4.17")` add:

```kotlin
    testImplementation("androidx.work:work-testing:2.12.0")
```

- [ ] **Step 2: Write the failing test**

`android/app/src/test/kotlin/io/github/fifothehein/tminus/sync/SyncSchedulingTest.kt`. With `WorkManagerTestInitHelper`, work with no constraints runs as soon as it is queued, so a `WorkerFactory` gives every `SyncWorker` a runner that only records its trigger and never finishes. That keeps the work `RUNNING`, and no test boots Flutter.

```kotlin
package io.github.fifothehein.tminus.sync

import android.app.AlarmManager
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager

@RunWith(RobolectricTestRunner::class)
class SyncSchedulingTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val alarmManager: AlarmManager = app.getSystemService(AlarmManager::class.java)
    private lateinit var workManager: WorkManager
    private var now = 1_791_270_000_000L

    /** Queued SyncWorkers run at once in tests; this one records the trigger and never finishes. */
    private val started = mutableListOf<String>()
    private val factory = object : WorkerFactory() {
        override fun createWorker(context: Context, name: String, params: WorkerParameters): ListenableWorker? =
            if (name == SyncWorker::class.java.name) SyncWorker(context, params) { trigger, _ -> started += trigger; {} } else null
    }

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(factory).build(),
        )
        workManager = WorkManager.getInstance(app)
        app.getSharedPreferences(PreSyncScheduler.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun infos(name: String): List<WorkInfo> = workManager.getWorkInfosForUniqueWork(name).get()

    private fun preSyncAlarms() = shadowOf(alarmManager).scheduledAlarms
        .filter { shadowOf(it.operation).savedIntent.action == PreSyncScheduler.ACTION }

    /** Each test gets a new in-memory WorkManager database; close it so none leaks. */
    @After
    fun tearDown() {
        WorkManagerTestInitHelper.closeWorkDatabase()
    }

    @Test
    fun `periodic sync runs every 15 min with a network and is kept, not replaced`() {
        val scheduler = SyncScheduler(app, workManager)
        scheduler.ensurePeriodic()
        val first = infos(SyncScheduler.PERIODIC).single()
        scheduler.ensurePeriodic()
        val info = infos(SyncScheduler.PERIODIC).single()
        assertEquals(first.id, info.id)
        assertEquals(NetworkType.CONNECTED, info.constraints.requiredNetworkType)
        assertEquals(15 * 60_000L, info.periodicityInfo!!.repeatIntervalMillis)
    }

    @Test
    fun `runNow queues one sync per trigger with the trigger as input and no network condition`() {
        val scheduler = SyncScheduler(app, workManager)
        scheduler.runNow(SyncWorker.TRIGGER_PRE_ALARM, expedited = true)
        scheduler.runNow(SyncWorker.TRIGGER_PRE_ALARM, expedited = true)
        val info = infos(SyncScheduler.nowName(SyncWorker.TRIGGER_PRE_ALARM)).single()
        assertEquals(NetworkType.NOT_REQUIRED, info.constraints.requiredNetworkType)
        assertEquals(listOf(SyncWorker.TRIGGER_PRE_ALARM), started)
    }

    @Test
    fun `the calendar watch is a content trigger on Events and can be turned off`() {
        val scheduler = SyncScheduler(app, workManager)
        scheduler.setCalendarWatch(true)
        scheduler.setCalendarWatch(true)
        val info = infos(SyncScheduler.CALENDAR_WATCH).single()
        assertEquals(WorkInfo.State.ENQUEUED, info.state)
        val trigger = info.constraints.contentUriTriggers.single()
        assertEquals(CalendarContract.Events.CONTENT_URI, trigger.uri)
        assertTrue(trigger.isTriggeredForDescendants)
        scheduler.setCalendarWatch(false)
        assertEquals(WorkInfo.State.CANCELLED, infos(SyncScheduler.CALENDAR_WATCH).single().state)
    }

    @Test
    fun `a calendar change queues a sync and the next watch`() {
        val worker = TestListenableWorkerBuilder<CalendarWatchWorker>(app).build()
        assertEquals(ListenableWorker.Result.success(), worker.startWork().get())
        assertEquals(listOf(SyncWorker.TRIGGER_CALENDAR_CHANGE), started)
        assertEquals(WorkInfo.State.ENQUEUED, infos(SyncScheduler.CALENDAR_WATCH).single().state)
    }

    private fun worker(trigger: String?, runner: SyncRunner): SyncWorker {
        val builder = TestListenableWorkerBuilder<SyncWorker>(app).setWorkerFactory(
            object : WorkerFactory() {
                override fun createWorker(context: Context, name: String, params: WorkerParameters) =
                    SyncWorker(context, params, runner)
            },
        )
        if (trigger != null) builder.setInputData(SyncWorker.input(trigger))
        return builder.build() as SyncWorker
    }

    @Test
    fun `the worker runs its trigger and maps the outcome`() {
        val seen = mutableListOf<String>()
        val outcomes = mapOf(
            SyncWorker.OUTCOME_OK to ListenableWorker.Result.success(),
            SyncWorker.OUTCOME_BUSY to ListenableWorker.Result.success(),
            SyncWorker.OUTCOME_RETRY to ListenableWorker.Result.retry(),
        )
        for ((outcome, expected) in outcomes) {
            val w = worker(SyncWorker.TRIGGER_PERIODIC) { trigger, done -> seen += trigger; done(outcome); {} }
            assertEquals(outcome, expected, w.startWork().get())
        }
        assertEquals(List(3) { SyncWorker.TRIGGER_PERIODIC }, seen)
    }

    @Test
    fun `a worker without a trigger runs as manual, and stopping it cancels the run`() {
        var cancelled = false
        var trigger: String? = null
        val w = worker(null) { t, _ -> trigger = t; { cancelled = true } }
        w.startWork()
        assertEquals(SyncWorker.TRIGGER_MANUAL, trigger)
        w.onStopped()
        assertTrue(cancelled)
    }

    @Test
    fun `pre-sync keeps one alarm for the next future time`() {
        val pre = PreSyncScheduler(app) { now }
        pre.setTimes(listOf(now + 3 * MINUTE, now - MINUTE, now + MINUTE, now + MINUTE))
        assertEquals(listOf(now - MINUTE, now + MINUTE, now + 3 * MINUTE), pre.times())
        assertEquals(now + MINUTE, preSyncAlarms().single().triggerAtTime)

        now += 2 * MINUTE
        pre.armNext()
        assertEquals(now + MINUTE, preSyncAlarms().single().triggerAtTime)

        now += 2 * MINUTE
        pre.armNext()
        assertNull(pre.next())
        assertTrue(preSyncAlarms().isEmpty())
    }

    @Test
    fun `without exact-alarm access the pre-sync alarm is inexact, not dropped`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        PreSyncScheduler(app) { now }.setTimes(listOf(now + MINUTE))
        assertEquals(now + MINUTE, preSyncAlarms().single().triggerAtTime)
    }

    @Test
    fun `the pre-sync alarm starts an expedited sync and arms the next one`() {
        val real = System.currentTimeMillis()
        PreSyncScheduler(app).setTimes(listOf(real - 1_000, real + HOUR))
        PreSyncReceiver().onReceive(app, Intent(PreSyncScheduler.ACTION))
        assertEquals(listOf(SyncWorker.TRIGGER_PRE_ALARM), started)
        assertEquals(real + HOUR, preSyncAlarms().single().triggerAtTime)
    }

    @Test
    fun `boot, update and clock changes re-arm the pre-sync alarm`() {
        val real = System.currentTimeMillis()
        val pre = PreSyncScheduler(app)
        for (action in SyncBootReceiver.ACTIONS) {
            pre.setTimes(listOf(real + HOUR))
            shadowOf(alarmManager).scheduledAlarms.mapNotNull { it.operation }.forEach(alarmManager::cancel)
            SyncBootReceiver().onReceive(app, Intent(action))
            assertEquals(action, real + HOUR, preSyncAlarms().single().triggerAtTime)
        }
        SyncBootReceiver().onReceive(app, Intent(Intent.ACTION_SCREEN_ON))
    }

    @Test
    fun `the manifest registers the sync receivers`() {
        val pm = app.packageManager
        for (action in SyncBootReceiver.ACTIONS) {
            val found = pm.queryBroadcastReceivers(Intent(action).setPackage(app.packageName), 0).map { it.activityInfo.name }
            assertTrue(action, SyncBootReceiver::class.java.name in found)
        }
        assertFalse(pm.getReceiverInfo(ComponentName(app, PreSyncReceiver::class.java), 0).exported)
    }

    private companion object {
        const val MINUTE = 60_000L
        const val HOUR = 60 * MINUTE
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd /c/Projects/tminus/android && ./gradlew :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.sync.SyncSchedulingTest"`
Expected: `BUILD FAILED`, `Unresolved reference 'SyncWorker'` (and the other new classes).

- [ ] **Step 4: Implement**

`sync/SyncWorker.kt`:

```kotlin
package io.github.fifothehein.tminus.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.core.app.NotificationCompat
import androidx.work.Data
import androidx.work.ForegroundInfo
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import com.google.common.util.concurrent.ListenableFuture
import io.github.fifothehein.tminus.R

/**
 * Runs one sync (spec §7 "Sync triggers"): [SyncRunner] boots a headless FlutterEngine that runs
 * Dart `syncMain()` and reports an outcome. Every trigger (periodic, calendar change, pre-alarm,
 * Sync now) goes through here. `startWork` runs on the main thread, where a FlutterEngine must be
 * created.
 */
class SyncWorker(
    context: Context,
    params: WorkerParameters,
    private val runner: SyncRunner,
) : ListenableWorker(context, params) {
    @Volatile private var cancel: (() -> Unit)? = null

    override fun startWork(): ListenableFuture<Result> = CallbackToFutureAdapter.getFuture { completer ->
        val trigger = inputData.getString(KEY_TRIGGER) ?: TRIGGER_MANUAL
        cancel = runner.run(trigger) { outcome -> completer.set(resultFor(outcome)) }
        "SyncWorker($trigger)"
    }

    override fun onStopped() {
        cancel?.invoke()
    }

    /** Expedited work runs as a foreground service below Android 12; this is its notification. */
    override fun getForegroundInfoAsync(): ListenableFuture<ForegroundInfo> = CallbackToFutureAdapter.getFuture { completer ->
        completer.set(ForegroundInfo(RUNNING_NOTIFICATION_ID, runningNotification(applicationContext)))
        "SyncWorker foreground"
    }

    companion object {
        const val KEY_TRIGGER = "trigger"

        // Trigger names match Dart's SyncTrigger values.
        const val TRIGGER_PERIODIC = "periodic"
        const val TRIGGER_CALENDAR_CHANGE = "calendarChange"
        const val TRIGGER_PRE_ALARM = "preAlarm"
        const val TRIGGER_MANUAL = "manual"

        /** What Dart's `syncMain()` reports (SyncRunOutcome names). */
        const val OUTCOME_OK = "ok"
        const val OUTCOME_RETRY = "retry"
        const val OUTCOME_BUSY = "busy"

        const val CHANNEL_RUNNING = "sync_running"
        private const val RUNNING_NOTIFICATION_ID = 0x5301

        fun input(trigger: String): Data = Data.Builder().putString(KEY_TRIGGER, trigger).build()

        /** Temporary failures retry with WorkManager's backoff (spec §9); anything else is done. */
        fun resultFor(outcome: String): Result =
            if (outcome == OUTCOME_RETRY) Result.retry() else Result.success()

        private fun runningNotification(context: Context): android.app.Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_RUNNING, "Calendar sync in progress", NotificationManager.IMPORTANCE_MIN),
            )
            return NotificationCompat.Builder(context, CHANNEL_RUNNING)
                .setSmallIcon(R.drawable.ic_stat_tminus)
                .setContentTitle("Syncing calendars")
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setOngoing(true)
                .build()
        }
    }
}

/** Runs Dart `syncMain(trigger)` and calls `done` once with its outcome. Returns a cancel function. */
fun interface SyncRunner {
    fun run(trigger: String, done: (String) -> Unit): () -> Unit
}
```

`sync/SyncScheduler.kt`:

```kotlin
package io.github.fifothehein.tminus.sync

import android.content.Context
import android.provider.CalendarContract
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.time.Duration
import java.util.concurrent.TimeUnit

/** Every WorkManager request for sync (spec §7 "Sync triggers"). */
class SyncScheduler(
    context: Context,
    private val workManager: WorkManager = WorkManager.getInstance(context.applicationContext),
) {
    /** Every 15 min with a network; kept if already scheduled. App start calls this. */
    fun ensurePeriodic() {
        val request = PeriodicWorkRequest.Builder(SyncWorker::class.java, 15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .setInputData(SyncWorker.input(SyncWorker.TRIGGER_PERIODIC))
            .build()
        workManager.enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    /**
     * One sync as soon as possible, without a network condition: device calendars still refresh and
     * the stale-feed check still runs offline. Pre-alarm and Sync now are expedited. A request whose
     * trigger is already queued or running is dropped, except calendar changes, which queue one more
     * run after the current one so a change made during a sync is not missed.
     */
    fun runNow(trigger: String, expedited: Boolean) {
        val builder = OneTimeWorkRequest.Builder(SyncWorker::class.java)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .setInputData(SyncWorker.input(trigger))
        if (expedited) builder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        val policy = if (trigger == SyncWorker.TRIGGER_CALENDAR_CHANGE) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP
        workManager.enqueueUniqueWork(nowName(trigger), policy, builder.build())
    }

    /**
     * Watches `CalendarContract.Events` while a device source exists (spec §7): a change starts a
     * sync. Content-URI work runs once, so [CalendarWatchWorker] queues the next watch itself.
     */
    fun setCalendarWatch(enabled: Boolean) {
        if (enabled) {
            workManager.enqueueUniqueWork(CALENDAR_WATCH, ExistingWorkPolicy.KEEP, calendarWatchRequest())
        } else {
            workManager.cancelUniqueWork(CALENDAR_WATCH)
        }
    }

    /** From inside a running watch: the next watch starts when this one finishes. */
    internal fun rewatch() {
        workManager.enqueueUniqueWork(CALENDAR_WATCH, ExistingWorkPolicy.APPEND_OR_REPLACE, calendarWatchRequest())
    }

    private fun calendarWatchRequest(): OneTimeWorkRequest = OneTimeWorkRequest.Builder(CalendarWatchWorker::class.java)
        .setConstraints(
            Constraints.Builder()
                .addContentUriTrigger(CalendarContract.Events.CONTENT_URI, true)
                .setTriggerContentUpdateDelay(Duration.ofSeconds(5))
                .setTriggerContentMaxDelay(Duration.ofSeconds(30))
                .build(),
        )
        .build()

    companion object {
        const val PERIODIC = "tminus.sync.periodic"
        const val CALENDAR_WATCH = "tminus.sync.calendarWatch"
        private const val BACKOFF_SECONDS = 30L

        fun nowName(trigger: String) = "tminus.sync.now.$trigger"
    }
}

/** Fires when the phone's calendar changes: queues a sync and the next watch. Never boots Flutter. */
class CalendarWatchWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        SyncScheduler(applicationContext).run {
            runNow(SyncWorker.TRIGGER_CALENDAR_CHANGE, expedited = false)
            rewatch()
        }
        return Result.success()
    }
}
```

`sync/PreSyncScheduler.kt`:

```kotlin
package io.github.fifothehein.tminus.sync

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.github.fifothehein.tminus.engine.TimeChangeReceiver

/**
 * Pre-alarm sync (spec §7): Dart sends one time per occurrence (12 min before its earliest alert)
 * after each sync; this keeps one AlarmManager alarm for the next of them. Times live in the app's
 * credential-protected preferences, so they are re-armed at BOOT_COMPLETED (a sync cannot run
 * before the first unlock anyway).
 */
class PreSyncScheduler(
    context: Context,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val appContext: Context = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val alarmManager: AlarmManager = appContext.getSystemService(AlarmManager::class.java)

    fun setTimes(times: List<Long>) {
        prefs.edit().putString(KEY_TIMES, times.distinct().sorted().joinToString(",")).apply()
        armNext()
    }

    fun times(): List<Long> =
        prefs.getString(KEY_TIMES, "").orEmpty().split(',').mapNotNull { it.toLongOrNull() }

    /** The next stored time after now, or null. */
    fun next(): Long? = times().firstOrNull { it > clock() }

    /** Sets the alarm for [next], or cancels it when nothing is left. */
    fun armNext() {
        val at = next()
        if (at == null) {
            operation(PendingIntent.FLAG_NO_CREATE)?.let { alarmManager.cancel(it); it.cancel() }
            return
        }
        val operation = operation(PendingIntent.FLAG_UPDATE_CURRENT)!!
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Exact alarm refused for pre-alarm sync; using an inexact alarm", e)
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
        }
    }

    private fun operation(flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        appContext,
        REQUEST_CODE,
        Intent(appContext, PreSyncReceiver::class.java).setAction(ACTION),
        flags or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val ACTION = "io.github.fifothehein.tminus.PRE_SYNC"
        const val PREFS = "tminus_sync"
        private const val KEY_TIMES = "preSyncTimes"
        private const val REQUEST_CODE = 0x5201
        private const val TAG = "TMinusSync"
    }
}

/** The pre-alarm sync alarm: an expedited sync now, then the alarm for the next time. */
class PreSyncReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PreSyncScheduler.ACTION) return
        SyncScheduler(context).runNow(SyncWorker.TRIGGER_PRE_ALARM, expedited = true)
        PreSyncScheduler(context).armNext()
    }
}

/** Re-arms the pre-alarm sync alarm after a reboot, an app update or a clock change. */
class SyncBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        PreSyncScheduler(context).armNext()
    }

    companion object {
        val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            TimeChangeReceiver.ACTION_EXACT_ALARM_PERMISSION_CHANGED,
        )
    }
}
```

- [ ] **Step 5: Register the receivers**

In `android/app/src/main/AndroidManifest.xml`, after the `.engine.TimeChangeReceiver` element (before `<!-- Don't delete the meta-data below.`), add:

```xml
        <!-- Sync (Plan 4). WorkManager merges its own service and receivers. -->
        <receiver
            android:name=".sync.PreSyncReceiver"
            android:exported="false" />
        <receiver
            android:name=".sync.SyncBootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
                <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" />
            </intent-filter>
        </receiver>
```

`SyncBootReceiver` is not `directBootAware`: its times are in credential-protected preferences, and a sync cannot run before the first unlock anyway (Plan 3's engine receivers stay direct-boot aware). A spoofed broadcast only re-arms the pre-sync alarm, which is harmless.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd /c/Projects/tminus/android && ./gradlew :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.sync.SyncSchedulingTest"`
Expected: `BUILD SUCCESSFUL` (11 tests). The `@After` closes each test's in-memory WorkManager database; without it Robolectric logs a CloseGuard "resource was acquired … but never released" trace (harmless, but noise).

- [ ] **Step 7: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`; full Kotlin unit tests → `BUILD SUCCESSFUL`; `flutter build apk --debug` → `√ Built build\app\outputs\flutter-apk\app-debug.apk` (checks the WorkManager manifest merge).

- [ ] **Step 8: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/io/github/fifothehein/tminus/sync android/app/src/test/kotlin/io/github/fifothehein/tminus/sync
git commit -m "Schedule periodic, calendar-change and pre-alarm syncs with WorkManager"
```

---

### Task 9: The `tminus_sync` channel, the sync lock and source notifications

**Files:**
- Create: `android/app/src/main/kotlin/io/github/fifothehein/tminus/sync/SyncNotifications.kt`, `.../sync/SyncChannel.kt`
- Modify: `android/app/src/main/kotlin/io/github/fifothehein/tminus/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml` (one receiver)
- Modify: `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` (§3: the `tminus_sync` table)
- Test: `android/app/src/test/kotlin/io/github/fifothehein/tminus/sync/SyncChannelTest.kt`

**Interfaces:**
- Consumes: `SyncScheduler`, `PreSyncScheduler`, `SyncWorker` constants (Task 8); `MainActivity`, `R.drawable.ic_stat_tminus` (Plan 3).
- Produces: `class SyncLock(clock)` with `acquire(owner: String, leaseMs: Long): Boolean`, `release(owner: String)` and `companion val shared`; `class SyncChannel internal constructor(context, onFinished: ((String) -> Unit)?, lock, scheduler, preSync, notifications)` with `detach()` and `companion fun register(messenger, context, onFinished = null): SyncChannel`, `NAME = "tminus_sync"`; `class SyncNotifications(context)` with `ensureChannel()`, `post(kind, sourceId, title, text)`, `cancel(kind, sourceId)`, `CHANNEL_STATUS = "sync_status"`, `KIND_STALE = "stale"`, `KIND_BROKEN = "broken"`, `EXTRA_ROUTE = "io.github.fifothehein.tminus.ROUTE"`, `fun id(kind, sourceId)`; `class SyncActionReceiver` with `ACTION_SYNC_NOW` and `fun syncNow(context): PendingIntent`.

`tminus_sync` methods (Dart client in Task 10):

| Method | Arguments | Returns |
|---|---|---|
| `deviceZone` | — | IANA zone id (`TimeZone.getDefault().id`) |
| `acquireLock` | `{"owner": String, "leaseMs": int}` | `bool` |
| `releaseLock` | `{"owner": String}` | `null` |
| `configure` | `{"watchCalendars": bool, "preSyncTimesMs": [int]}` | `null`: keeps the periodic sync, sets the calendar watch, stores the pre-sync times |
| `requestSync` | `{"trigger": String}` | `null`: an expedited background sync (WorkManager → headless engine) |
| `postSourceNotice` | `{"kind": "stale"\|"broken", "sourceId", "title", "text"}` | `null` |
| `cancelSourceNotice` | `{"kind", "sourceId"}` | `null` |
| `finished` | `{"outcome": "ok"\|"retry"\|"busy"}` | `null`; only the headless engine's channel has a listener |

Errors: missing or wrong arguments → `bad_args`; anything else → `sync_error`.

- [ ] **Step 1: Write the failing test**

`android/app/src/test/kotlin/io/github/fifothehein/tminus/sync/SyncChannelTest.kt`:

```kotlin
package io.github.fifothehein.tminus.sync

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.fifothehein.tminus.MainActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
class SyncChannelTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private val notifications: NotificationManager = app.getSystemService(NotificationManager::class.java)
    private var now = 1_791_270_000_000L
    private val lock = SyncLock { now }
    private val finished = mutableListOf<String>()
    private val started = mutableListOf<String>()
    private lateinit var channel: SyncChannel

    private class Recorded : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var notImplemented = false
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { this.errorCode = errorCode }
        override fun notImplemented() { notImplemented = true }
    }

    private fun call(method: String, args: Map<String, Any?>? = null): Recorded =
        Recorded().also { channel.onMethodCall(MethodCall(method, args), it) }

    @Before
    fun setUp() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        val factory = object : WorkerFactory() {
            override fun createWorker(context: Context, name: String, params: WorkerParameters): ListenableWorker? =
                if (name == SyncWorker::class.java.name) SyncWorker(context, params) { t, _ -> started += t; {} } else null
        }
        WorkManagerTestInitHelper.initializeTestWorkManager(
            app,
            Configuration.Builder().setExecutor(SynchronousExecutor()).setWorkerFactory(factory).build(),
        )
        app.getSharedPreferences(PreSyncScheduler.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        channel = SyncChannel(app, { finished += it }, lock, SyncScheduler(app), PreSyncScheduler(app) { now })
    }

    /** Each test gets a new in-memory WorkManager database; close it so none leaks. */
    @After
    fun tearDown() {
        WorkManagerTestInitHelper.closeWorkDatabase()
    }

    @Test
    fun `deviceZone is the default zone's IANA id`() {
        assertEquals(TimeZone.getDefault().id, call("deviceZone").value)
    }

    @Test
    fun `the lock admits one owner until it is released or its lease runs out`() {
        assertEquals(true, call("acquireLock", mapOf("owner" to "a", "leaseMs" to 60_000)).value)
        assertEquals(false, call("acquireLock", mapOf("owner" to "b", "leaseMs" to 60_000)).value)
        assertEquals(true, call("acquireLock", mapOf("owner" to "a", "leaseMs" to 60_000)).value) // renew
        call("releaseLock", mapOf("owner" to "b")) // not the owner: no effect
        assertFalse(lock.acquire("b", 60_000))
        call("releaseLock", mapOf("owner" to "a"))
        assertTrue(lock.acquire("b", 60_000))
        now += 60_000
        assertTrue(lock.acquire("c", 60_000)) // b's lease ran out
    }

    @Test
    fun `detach releases the locks this engine took`() {
        call("acquireLock", mapOf("owner" to "a", "leaseMs" to 600_000))
        channel.detach()
        assertTrue(lock.acquire("b", 1_000))
    }

    @Test
    fun `configure schedules the periodic sync, the calendar watch and the pre-sync alarm`() {
        call("configure", mapOf("watchCalendars" to true, "preSyncTimesMs" to listOf(now + 60_000, now + 120_000L)))
        val wm = WorkManager.getInstance(app)
        assertEquals(1, wm.getWorkInfosForUniqueWork(SyncScheduler.PERIODIC).get().size)
        assertFalse(wm.getWorkInfosForUniqueWork(SyncScheduler.CALENDAR_WATCH).get().single().state.isFinished)
        val alarm = shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.single()
        assertEquals(now + 60_000, alarm.triggerAtTime)

        call("configure", mapOf("watchCalendars" to false, "preSyncTimesMs" to emptyList<Long>()))
        assertTrue(wm.getWorkInfosForUniqueWork(SyncScheduler.CALENDAR_WATCH).get().single().state.isFinished)
        assertTrue(shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.isEmpty())
    }

    @Test
    fun `a stale notice offers Sync now and a broken one offers Fix that opens the source`() {
        call("postSourceNotice", mapOf("kind" to "stale", "sourceId" to "work", "title" to "Calendar hasn't synced for 2 h — alarms may be outdated", "text" to "Work Outlook"))
        call("postSourceNotice", mapOf("kind" to "broken", "sourceId" to "home", "title" to "Home feed link stopped working", "text" to "Link no longer works (HTTP 404)."))

        val stale = shadowOf(notifications).getNotification(SyncNotifications.id("stale", "work"))
        assertEquals("Sync now", stale.actions.single().title)
        assertEquals(SyncNotifications.CHANNEL_STATUS, stale.channelId)
        assertTrue(stale.flags and android.app.Notification.FLAG_ONLY_ALERT_ONCE != 0)
        val sync = shadowOf(stale.actions.single().actionIntent).savedIntent
        SyncActionReceiver().onReceive(app, sync)
        assertEquals(listOf(SyncWorker.TRIGGER_MANUAL), started)

        val broken = shadowOf(notifications).getNotification(SyncNotifications.id("broken", "home"))
        assertEquals("Fix", broken.actions.single().title)
        val fix = shadowOf(broken.actions.single().actionIntent).savedIntent
        assertEquals(MainActivity::class.java.name, fix.component!!.className)
        assertEquals("/sources/home", fix.getStringExtra(SyncNotifications.EXTRA_ROUTE))
    }

    @Test
    fun `cancelling the last notice also removes the group summary`() {
        call("postSourceNotice", mapOf("kind" to "stale", "sourceId" to "work", "title" to "t", "text" to "x"))
        call("postSourceNotice", mapOf("kind" to "broken", "sourceId" to "work", "title" to "t", "text" to "x"))
        call("cancelSourceNotice", mapOf("kind" to "stale", "sourceId" to "work"))
        assertNull(shadowOf(notifications).getNotification(SyncNotifications.id("stale", "work")))
        assertEquals(2, notifications.activeNotifications.size) // broken + summary
        call("cancelSourceNotice", mapOf("kind" to "broken", "sourceId" to "work"))
        assertEquals(0, notifications.activeNotifications.size)
    }

    @Test
    fun `requestSync queues a background sync through WorkManager`() {
        call("requestSync", mapOf("trigger" to "manual"))
        assertEquals(listOf("manual"), started)
    }

    @Test
    fun `finished hands the outcome to the runner`() {
        call("finished", mapOf("outcome" to "retry"))
        assertEquals(listOf("retry"), finished)
    }

    @Test
    fun `bad arguments and unknown methods are reported`() {
        assertEquals("bad_args", call("acquireLock", mapOf("owner" to "a")).errorCode)
        assertEquals("bad_args", call("postSourceNotice", mapOf("kind" to "other", "sourceId" to "w", "title" to "t", "text" to "x")).errorCode)
        assertEquals("bad_args", call("configure", mapOf("watchCalendars" to true)).errorCode)
        assertTrue(call("nope").notImplemented)
    }

    @Test
    fun `Sync now ignores other actions and is not exported`() {
        SyncActionReceiver().onReceive(app, Intent("other"))
        assertTrue(started.isEmpty())
        assertFalse(app.packageManager.getReceiverInfo(ComponentName(app, SyncActionReceiver::class.java), 0).exported)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /c/Projects/tminus/android && ./gradlew :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.sync.SyncChannelTest"`
Expected: `BUILD FAILED`, `Unresolved reference 'SyncLock'` (and `SyncChannel`, `SyncNotifications`, `SyncActionReceiver`).

- [ ] **Step 3: Implement the notifications**

`sync/SyncNotifications.kt`:

```kotlin
package io.github.fifothehein.tminus.sync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import io.github.fifothehein.tminus.MainActivity
import io.github.fifothehein.tminus.R

/**
 * The "Feed stale" and "Feed broken" notifications (spec §8.10, §9; brief §10). One per source and
 * kind, alert-once, withdrawn when the source syncs again. Dart writes the text; this only posts it.
 */
class SyncNotifications(context: Context) {
    private val appContext: Context = context.applicationContext
    private val manager: NotificationManager = appContext.getSystemService(NotificationManager::class.java)

    fun ensureChannel() {
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_STATUS, "Calendar sync problems", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A calendar has stopped syncing, so alarms may be out of date"
            },
        )
    }

    /** [kind] is [KIND_STALE] (action Sync now) or [KIND_BROKEN] (action Fix). */
    fun post(kind: String, sourceId: String, title: String, text: String) {
        require(kind == KIND_STALE || kind == KIND_BROKEN) { "Unknown notice kind: $kind" }
        ensureChannel()
        val open = openSource(sourceId)
        val builder = NotificationCompat.Builder(appContext, CHANNEL_STATUS)
            .setSmallIcon(R.drawable.ic_stat_tminus)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(open)
            .setGroup(GROUP)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
        if (kind == KIND_STALE) {
            builder.addAction(0, "Sync now", SyncActionReceiver.syncNow(appContext))
        } else {
            builder.addAction(0, "Fix", open)
        }
        notify(id(kind, sourceId), builder.build())
        notify(SUMMARY_ID, summary())
    }

    fun cancel(kind: String, sourceId: String) {
        manager.cancel(id(kind, sourceId))
        val others = manager.activeNotifications.any { it.notification.group == GROUP && it.id != SUMMARY_ID }
        if (!others) manager.cancel(SUMMARY_ID)
    }

    private fun summary(): Notification = NotificationCompat.Builder(appContext, CHANNEL_STATUS)
        .setSmallIcon(R.drawable.ic_stat_tminus)
        .setContentTitle("Calendar sync problems")
        .setGroup(GROUP)
        .setGroupSummary(true)
        .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
        .setOnlyAlertOnce(true)
        .build()

    /** Opens the app; Plan 5's router reads [EXTRA_ROUTE] and shows the source. */
    private fun openSource(sourceId: String): PendingIntent = PendingIntent.getActivity(
        appContext,
        "open|$sourceId".hashCode(),
        Intent(appContext, MainActivity::class.java)
            .putExtra(EXTRA_ROUTE, "/sources/$sourceId")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun notify(id: Int, notification: Notification) {
        try {
            manager.notify(id, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Notifications are blocked", e)
        }
    }

    companion object {
        const val CHANNEL_STATUS = "sync_status"
        const val KIND_STALE = "stale"
        const val KIND_BROKEN = "broken"
        const val EXTRA_ROUTE = "io.github.fifothehein.tminus.ROUTE"
        private const val GROUP = "io.github.fifothehein.tminus.SYNC"
        private const val SUMMARY_ID = 0x5302
        private const val TAG = "TMinusSync"

        fun id(kind: String, sourceId: String): Int = "sync|$kind|$sourceId".hashCode()
    }
}

/** The Feed stale notification's Sync now button: an expedited sync. */
class SyncActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_SYNC_NOW) return
        SyncScheduler(context).runNow(SyncWorker.TRIGGER_MANUAL, expedited = true)
    }

    companion object {
        const val ACTION_SYNC_NOW = "io.github.fifothehein.tminus.SYNC_NOW"

        fun syncNow(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            0x5303,
            Intent(context, SyncActionReceiver::class.java).setAction(ACTION_SYNC_NOW),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
```

- [ ] **Step 4: Implement the lock and the channel**

`sync/SyncChannel.kt`:

```kotlin
package io.github.fifothehein.tminus.sync

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * One sync at a time across the UI isolate and the headless one (Plan 4 decision): both run in the
 * app process, so a process-wide lease is enough. A lease that is not released (a killed engine)
 * runs out by itself.
 */
class SyncLock(private val clock: () -> Long = System::currentTimeMillis) {
    private var owner: String? = null
    private var expiresAt = 0L

    @Synchronized
    fun acquire(owner: String, leaseMs: Long): Boolean {
        val now = clock()
        if (this.owner != null && this.owner != owner && now < expiresAt) return false
        this.owner = owner
        expiresAt = now + leaseMs
        return true
    }

    @Synchronized
    fun release(owner: String) {
        if (this.owner == owner) this.owner = null
    }

    companion object {
        val shared = SyncLock()
    }
}

/**
 * The `tminus_sync` MethodChannel (Plan 4): what Dart's sync needs from Android besides the alarm
 * engine. Registered on the app's engine (MainActivity) and on each headless sync engine.
 */
class SyncChannel internal constructor(
    context: Context,
    private val onFinished: ((String) -> Unit)?,
    private val lock: SyncLock = SyncLock.shared,
    private val scheduler: SyncScheduler = SyncScheduler(context),
    private val preSync: PreSyncScheduler = PreSyncScheduler(context),
    private val notifications: SyncNotifications = SyncNotifications(context),
) : MethodChannel.MethodCallHandler {
    private val held = mutableSetOf<String>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "deviceZone" -> result.success(TimeZone.getDefault().id)
                "acquireLock" -> {
                    val owner = call.string("owner")
                    val acquired = lock.acquire(owner, call.long("leaseMs"))
                    if (acquired) held += owner
                    result.success(acquired)
                }
                "releaseLock" -> {
                    val owner = call.string("owner")
                    lock.release(owner)
                    held -= owner
                    result.success(null)
                }
                "configure" -> {
                    scheduler.ensurePeriodic()
                    scheduler.setCalendarWatch(call.argument<Boolean>("watchCalendars") ?: false)
                    val times = call.argument<List<*>>("preSyncTimesMs") ?: throw IllegalArgumentException("preSyncTimesMs missing")
                    preSync.setTimes(times.map { (it as Number).toLong() })
                    result.success(null)
                }
                "requestSync" -> {
                    scheduler.runNow(call.string("trigger"), expedited = true)
                    result.success(null)
                }
                "postSourceNotice" -> {
                    notifications.post(call.string("kind"), call.string("sourceId"), call.string("title"), call.string("text"))
                    result.success(null)
                }
                "cancelSourceNotice" -> {
                    notifications.cancel(call.string("kind"), call.string("sourceId"))
                    result.success(null)
                }
                "finished" -> {
                    onFinished?.invoke(call.string("outcome"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", e.message, null)
        } catch (e: Exception) {
            Log.e(TAG, "tminus_sync.${call.method} failed", e)
            result.error("sync_error", e.message, null)
        }
    }

    /** Releases every lock this engine took; its Flutter engine is going away. */
    fun detach() {
        held.forEach(lock::release)
        held.clear()
    }

    private fun MethodCall.string(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("$key missing")

    private fun MethodCall.long(key: String): Long =
        argument<Number>(key)?.toLong() ?: throw IllegalArgumentException("$key missing")

    companion object {
        const val NAME = "tminus_sync"
        private const val TAG = "TMinusSync"

        /** [onFinished] receives `syncMain()`'s outcome; only the headless runner passes one. */
        fun register(messenger: BinaryMessenger, context: Context, onFinished: ((String) -> Unit)? = null): SyncChannel {
            val handler = SyncChannel(context.applicationContext, onFinished)
            MethodChannel(messenger, NAME).setMethodCallHandler(handler)
            return handler
        }
    }
}
```

- [ ] **Step 5: Register the Sync now receiver**

In `android/app/src/main/AndroidManifest.xml`, after the `.sync.PreSyncReceiver` element add:

```xml
        <receiver
            android:name=".sync.SyncActionReceiver"
            android:exported="false" />
```

- [ ] **Step 6: Wire `MainActivity`**

In `MainActivity.kt`, after `import io.github.fifothehein.tminus.engine.EngineActions` add:

```kotlin
import io.github.fifothehein.tminus.sync.PreSyncScheduler
import io.github.fifothehein.tminus.sync.SyncChannel
import io.github.fifothehein.tminus.sync.SyncScheduler
```

After `private var engineChannel: AlarmEngineChannel? = null` add:

```kotlin
    private var syncChannel: SyncChannel? = null
```

In `configureFlutterEngine`, after the `engineChannel = AlarmEngineChannel.register(...)` line add:

```kotlin
        syncChannel = SyncChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        SyncScheduler(this).ensurePeriodic() // spec §7: every 15 min with a network
        PreSyncScheduler(this).armNext() // a force stop drops this alarm too
```

In `cleanUpFlutterEngine`, replace

```kotlin
        engineChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
```

with

```kotlin
        engineChannel = null
        syncChannel?.detach() // releases a sync lock the UI isolate still held
        syncChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd /c/Projects/tminus/android && ./gradlew :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.sync.*"`
Expected: `BUILD SUCCESSFUL` (10 + 11 tests).

- [ ] **Step 8: Record the channel in the roadmap**

In `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` §3, after the paragraph that starts `Every event is also appended to the native queue file`, add:

```markdown
### `tminus_sync` channel (Plan 4 implements both sides)

MethodChannel `tminus_sync`: `deviceZone` → IANA id · `acquireLock {owner, leaseMs}` → bool · `releaseLock {owner}` · `configure {watchCalendars, preSyncTimesMs}` · `requestSync {trigger}` · `postSourceNotice {kind: stale|broken, sourceId, title, text}` · `cancelSourceNotice {kind, sourceId}` · `finished {outcome: ok|retry|busy}` (headless engine only). Registered on the app's engine and on every headless sync engine. A notice's Fix action opens `MainActivity` with the extra `io.github.fifothehein.tminus.ROUTE = /sources/<sourceId>`; Plan 5's router should honour it.
```

- [ ] **Step 9: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`; full Kotlin unit tests → `BUILD SUCCESSFUL`; `flutter build apk --debug` → `√ Built ...app-debug.apk`.

- [ ] **Step 10: Commit**

```bash
git add android/app/src/main/kotlin/io/github/fifothehein/tminus/sync android/app/src/main/kotlin/io/github/fifothehein/tminus/MainActivity.kt android/app/src/main/AndroidManifest.xml android/app/src/test/kotlin/io/github/fifothehein/tminus/sync/SyncChannelTest.kt docs/superpowers/plans/2026-10-06-tminus-roadmap.md
git commit -m "Add the sync channel with a cross-isolate lock and Feed stale and broken notifications"
```

---

### Task 10: Dart client for `tminus_sync` and the device zone

**Files:**
- Create: `lib/core/sync/sync_platform.dart`, `lib/core/sync/device_zone.dart`
- Test: `test/core/sync/sync_platform_test.dart`

**Interfaces:**
- Consumes: Task 9's channel.
- Produces: `enum SourceNoticeKind { stale, broken }`; `class SyncPlatform({MethodChannel? channel})` with `static const channelName = 'tminus_sync'`, `Future<String> deviceZone()`, `Future<bool> acquireLock(String owner, Duration lease)`, `Future<void> releaseLock(String owner)`, `Future<void> configure({required bool watchCalendars, required List<DateTime> preSyncTimes})`, `Future<void> postSourceNotice({required SourceNoticeKind kind, required String sourceId, required String title, required String text})`, `Future<void> cancelSourceNotice({required SourceNoticeKind kind, required String sourceId})`, `Future<void> requestSync(String trigger)`, `Future<void> finished(String outcome)`; `Future<String> initDeviceZone(SyncPlatform platform)` (sets `tz.local`; keeps it for an unknown zone or no native side; returns the zone in use).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:tminus/core/sync/device_zone.dart';
import 'package:tminus/core/sync/sync_platform.dart';

import '../fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(SyncPlatform.channelName);
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });

  setUp(initZones);

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
    tz.setLocalLocation(tz.UTC);
  });

  test(
    'every call uses the method names and argument keys Kotlin reads',
    () async {
      answer((call) => call.method == 'acquireLock' ? true : null);
      final p = SyncPlatform();
      expect(await p.acquireLock('o', const Duration(minutes: 5)), isTrue);
      await p.releaseLock('o');
      await p.configure(
        watchCalendars: true,
        preSyncTimes: [DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true)],
      );
      await p.postSourceNotice(
        kind: SourceNoticeKind.stale,
        sourceId: 'w',
        title: 't',
        text: 'x',
      );
      await p.cancelSourceNotice(kind: SourceNoticeKind.broken, sourceId: 'w');
      await p.requestSync('manual');
      await p.finished('ok');

      expect(calls.map((c) => [c.method, c.arguments]), [
        [
          'acquireLock',
          {'owner': 'o', 'leaseMs': 300000},
        ],
        [
          'releaseLock',
          {'owner': 'o'},
        ],
        [
          'configure',
          {
            'watchCalendars': true,
            'preSyncTimesMs': [1000],
          },
        ],
        [
          'postSourceNotice',
          {'kind': 'stale', 'sourceId': 'w', 'title': 't', 'text': 'x'},
        ],
        [
          'cancelSourceNotice',
          {'kind': 'broken', 'sourceId': 'w'},
        ],
        [
          'requestSync',
          {'trigger': 'manual'},
        ],
        [
          'finished',
          {'outcome': 'ok'},
        ],
      ]);
    },
  );

  test('initDeviceZone sets tz.local from the device', () async {
    answer((_) => 'Africa/Johannesburg');
    expect(await initDeviceZone(SyncPlatform()), 'Africa/Johannesburg');
    expect(tz.local.name, 'Africa/Johannesburg');
  });

  test('an unknown zone or a missing native side keeps tz.local', () async {
    final before = tz.local.name;
    answer((_) => 'Mars/Olympus_Mons');
    expect(await initDeviceZone(SyncPlatform()), before);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await initDeviceZone(SyncPlatform()), before);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/sync/sync_platform_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sync/device_zone.dart'`.

- [ ] **Step 3: Implement**

`lib/core/sync/sync_platform.dart`:

```dart
import 'package:flutter/services.dart';

/// Which notification [SyncPlatform.postSourceNotice] posts (brief §10).
enum SourceNoticeKind {
  /// "Feed stale", with Sync now.
  stale,

  /// "Feed broken", with Fix.
  broken,
}

/// Typed client for the `tminus_sync` channel (Plan 4): the device zone, the
/// cross-isolate sync lock, WorkManager and pre-alarm scheduling, the source
/// notifications and the headless engine's finish signal.
class SyncPlatform {
  SyncPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'tminus_sync';

  final MethodChannel _channel;

  /// The device's IANA zone, e.g. `Africa/Johannesburg`.
  Future<String> deviceZone() async =>
      (await _channel.invokeMethod<String>('deviceZone'))!;

  /// True when [owner] now holds the lock for [lease].
  Future<bool> acquireLock(String owner, Duration lease) async =>
      await _channel.invokeMethod<bool>('acquireLock', {
        'owner': owner,
        'leaseMs': lease.inMilliseconds,
      }) ??
      false;

  Future<void> releaseLock(String owner) =>
      _channel.invokeMethod<void>('releaseLock', {'owner': owner});

  /// After each sync: keeps the periodic sync, watches the phone calendar
  /// while a device source exists, and stores the pre-alarm sync times.
  Future<void> configure({
    required bool watchCalendars,
    required List<DateTime> preSyncTimes,
  }) => _channel.invokeMethod<void>('configure', {
    'watchCalendars': watchCalendars,
    'preSyncTimesMs': [for (final t in preSyncTimes) t.millisecondsSinceEpoch],
  });

  Future<void> postSourceNotice({
    required SourceNoticeKind kind,
    required String sourceId,
    required String title,
    required String text,
  }) => _channel.invokeMethod<void>('postSourceNotice', {
    'kind': kind.name,
    'sourceId': sourceId,
    'title': title,
    'text': text,
  });

  Future<void> cancelSourceNotice({
    required SourceNoticeKind kind,
    required String sourceId,
  }) => _channel.invokeMethod<void>('cancelSourceNotice', {
    'kind': kind.name,
    'sourceId': sourceId,
  });

  /// Queues a background sync through WorkManager, which runs it in a
  /// headless engine (debug panel, device checks). [trigger] is a
  /// `SyncTrigger` name.
  Future<void> requestSync(String trigger) =>
      _channel.invokeMethod<void>('requestSync', {'trigger': trigger});

  /// Headless engine only: tells `HeadlessFlutterRunner` the outcome.
  Future<void> finished(String outcome) =>
      _channel.invokeMethod<void>('finished', {'outcome': outcome});
}
```

`lib/core/sync/device_zone.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'sync_platform.dart';

/// Sets `tz.local` to the device zone (Plan 2 left it at UTC). Without a
/// native side (tests, desktop), or for a zone the database does not know,
/// `tz.local` stays as it is. Returns the zone now in use. The time-zone
/// database must already be loaded (`configureDependencies` does it).
Future<String> initDeviceZone(SyncPlatform platform) async {
  try {
    final id = await platform.deviceZone();
    tz.setLocalLocation(tz.getLocation(id));
  } on MissingPluginException {
    // Keep the current zone.
  } on PlatformException {
    // Keep the current zone.
  } on tz.LocationNotFoundException {
    // Keep the current zone.
  }
  return tz.local.name;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart format lib/core/sync test/core/sync`
Run: `flutter test test/core/sync/sync_platform_test.dart`
Expected: `All tests passed!` (3 tests).

- [ ] **Step 5: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 6: Commit**

```bash
git add lib/core/sync/sync_platform.dart lib/core/sync/device_zone.dart test/core/sync/sync_platform_test.dart
git commit -m "Add the Dart sync platform client and set the device time zone"
```

---

### Task 11: Sync service

**Files:**
- Create: `lib/core/sync/sync_service.dart`
- Modify: `lib/core/storage/sync_log_repository.dart` (add `earliestForSource`)
- Test: `test/core/sync/sync_service_test.dart`

**Interfaces:**
- Consumes: `CalendarSource`, `FetchWindow`, `SourceFetched`, `SourceFailed` (Task 1); `SyncOutcomeSeverity` (Task 1); `EngineEventRecorder.drainNow` (Task 6); `MissedSystemDetector`, `preSyncTimes` (Task 7); `SyncPlatform`, `SourceNoticeKind` (Task 10); `AlarmEngine.applyPlan`, `ApplyResult` (Plan 3); `SourceRepository`, `OccurrenceRepository`, `AlertHistoryRepository` (`acknowledgements`, `since`, `record`, `deleteBefore`), `SyncLogRepository` (`add`, `latestForSource`, `deleteBefore`; this task adds `Future<SyncLogEntry?> earliestForSource(String sourceId)`), `SettingsRepository` (`getString`, `setString`), `RuleSetLoader`, `RulesEngine`, `EmptyFeedGuard`, `buildPlan`, `keepAfterEnd` (Plan 2).
- Produces: `typedef SourceBuilder = CalendarSource Function(SourceConfig config, SourceSyncState? state, tz.Location zone)`; `enum SyncTrigger { periodic, calendarChange, preAlarm, manual, foreground, pullToRefresh, debug }` with `static SyncTrigger parse(String? name)` (unknown → `manual`); `enum SyncRunOutcome { ok, retry, busy }`; `class SourceSyncResult(String sourceId, SyncOutcome outcome, [String? message])`; `class SyncReport({trigger, outcome, sources, applied, planned, missedSystem})`; `class SyncService({required sources, occurrences, history, syncLog, settings, ruleSets, RulesEngine Function() rulesEngine, engine, recorder, platform, SourceBuilder buildSource, tz.Location Function()? zone, UtcClock? clock, Duration lockWait = 60 s, Duration lockPoll = 500 ms})` with public fields of those names, `Future<SyncReport> run(SyncTrigger trigger)`, `Future<DateTime?> lastFinished()`, `static String brokenTitle(SourceConfig, SyncOutcome)`, `static String staleTitle(Duration age)`, and the constants `lockLease` (5 min), `lastFinishedKey = 'sync.lastFinishedUtcMs'`, `expectedKey = 'sync.missedSystemExpected'`, `historyRetention` (30 days), `syncLogRetention` (7 days), `occurrenceRetention` (1 day), `serverErrorsBeforeBroken` (24 h), `staleAfter` (60 min), `staleHorizon` (2 h).

One run, in order (spec §7 "`syncMain()` does"):
1. Take the lock (decision 3); if it never frees, log a whole-run `otherError` and return `busy`.
2. `recorder.drainNow()`, so acknowledgements and `fired` rows are current.
3. Fetch every enabled source in parallel. Then, per source in name order: the empty-feed guard (`emptyKept` keeps the cache); the 24-h server-error escalation (decision 24); the sync state (a failure keeps `lastSuccessUtc`, the validators and the streak); a per-source `sync_log` row; and the Feed broken notice (decisions 9, 10).
4. Plan: cached occurrences of enabled sources that end after `now − keepAfterEnd`, resolved with a fresh `RulesEngine`, `buildPlan` with the history acknowledgements.
5. Missed (system): check the stored expectations, record the misses.
6. `applyPlan`. On failure Kotlin keeps its old plan (spec §9), the run reports `retry`, and the stored expectations keep only the still-pending ones.
7. `configure` (calendar watch, pre-alarm sync times), Feed stale notices, pruning, the whole-run `sync_log` row, `lastFinishedKey`.

The run reports `retry` when any source had a temporary failure or `applyPlan` failed; otherwise `ok`. Platform side effects (notices, `configure`) never fail a run.

- [ ] **Step 1: Write the failing test**

`test/core/sync/sync_service_test.dart`. It uses the real repositories on an in-memory database, the real `AlarmEngine` and `SyncPlatform` over mocked channels, and fake sources. `now` starts at 06:00 UTC; the cached meeting is 08:00–08:30 with the Meeting profile (heads-up 07:50, alarm 07:59):

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/planned_alert.dart';
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/rules/rules_engine.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/override_repository.dart';
import 'package:tminus/core/storage/profile_repository.dart';
import 'package:tminus/core/storage/rule_repository.dart';
import 'package:tminus/core/storage/rule_set_loader.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/storage/sync_log_repository.dart';
import 'package:tminus/core/sync/engine_event_recorder.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

class _FakeSource implements CalendarSource {
  _FakeSource(this.id, this._result);
  @override
  final String id;
  final SourceResult Function() _result;
  int fetches = 0;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    fetches++;
    return _result();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engineChannel = MethodChannel(AlarmEngine.methodChannelName);
  const syncChannel = MethodChannel(SyncPlatform.channelName);

  // 06:00 UTC on 6 Oct 2026; the work meeting starts at 08:00.
  late DateTime now;
  late AppDatabase db;
  late SourceRepository sources;
  late OccurrenceRepository cache;
  late AlertHistoryRepository history;
  late SyncLogRepository log;
  late SettingsRepository settings;
  late SyncService sync;
  late Map<String, SourceResult Function()> results;
  late Map<String, _FakeSource> built;
  late List<MethodCall> engineCalls;
  late List<MethodCall> syncCalls;
  late List<Map<String, Object?>> queuedEvents;
  late Object? Function(MethodCall) applyAnswer;
  late bool lockFree;

  const work = SourceConfig(
    id: 'work',
    name: 'Work Outlook',
    color: blue,
    kind: SourceKind.ics,
    secureStorageKey: 'ics-url.work',
  );
  final meeting = occ(uid: 'm1', title: 'Sprint planning'); // 08:00–08:30

  List<Map<Object?, Object?>> applied() =>
      ((engineCalls.lastWhere((c) => c.method == 'applyPlan').arguments
                  as Map)['alerts']
              as List)
          .cast<Map<Object?, Object?>>();

  List<MethodCall> syncCallsNamed(String method) =>
      syncCalls.where((c) => c.method == method).toList();

  setUp(() async {
    now = DateTime.utc(2026, 10, 6, 6);
    db = openTestDatabase();
    sources = SourceRepository(db);
    cache = OccurrenceRepository(db);
    history = AlertHistoryRepository(db);
    log = SyncLogRepository(db);
    settings = SettingsRepository(db);
    await sources.save(work);
    results = {
      'work': () => SourceFetched([meeting]),
    };
    built = {};
    engineCalls = [];
    syncCalls = [];
    queuedEvents = [];
    lockFree = true;
    applyAnswer = (call) => {
      'armed': ((call.arguments as Map)['alerts'] as List).length,
      'cancelled': 0,
      'kept': 0,
    };
    messenger.setMockMethodCallHandler(engineChannel, (call) async {
      engineCalls.add(call);
      return switch (call.method) {
        'applyPlan' => applyAnswer(call),
        'drainEvents' => () {
          final drained = List.of(queuedEvents);
          queuedEvents.clear();
          return drained;
        }(),
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(syncChannel, (call) async {
      syncCalls.add(call);
      return call.method == 'acquireLock' ? lockFree : null;
    });
    final engine = AlarmEngine();
    sync = SyncService(
      sources: sources,
      occurrences: cache,
      history: history,
      syncLog: log,
      settings: settings,
      ruleSets: RuleSetLoader(
        profiles: ProfileRepository(db),
        rules: RuleRepository(db),
        overrides: OverrideRepository(db),
        settings: settings,
        sources: sources,
      ),
      rulesEngine: () => RulesEngine(zone: johannesburg, clock: () => now),
      engine: engine,
      recorder: EngineEventRecorder(
        engine: engine,
        history: history,
        occurrences: cache,
      ),
      platform: SyncPlatform(),
      buildSource: (config, state, zone) =>
          built[config.id] = _FakeSource(config.id, results[config.id]!),
      zone: () => johannesburg,
      clock: () => now,
      lockWait: const Duration(milliseconds: 30),
      lockPoll: const Duration(milliseconds: 5),
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(engineChannel, null);
    messenger.setMockMethodCallHandler(syncChannel, null);
    await db.close();
  });

  test('a sync caches, plans, applies, schedules and logs', () async {
    final report = await sync.run(SyncTrigger.periodic);

    expect(report.outcome, SyncRunOutcome.ok);
    expect(report.sources.single.outcome, SyncOutcome.success);
    expect(await cache.byKey(meeting.key), meeting);

    // Meeting profile: heads-up 07:50 and alarm 07:59.
    expect(applied().map((a) => a['fireAtUtcMs']), [
      DateTime.utc(2026, 10, 6, 7, 50).millisecondsSinceEpoch,
      DateTime.utc(2026, 10, 6, 7, 59).millisecondsSinceEpoch,
    ]);
    expect(report.applied, const ApplyResult(armed: 2, cancelled: 0, kept: 0));

    final configure = syncCallsNamed('configure').single.arguments as Map;
    expect(configure['watchCalendars'], isFalse);
    expect(configure['preSyncTimesMs'], [
      DateTime.utc(2026, 10, 6, 7, 38).millisecondsSinceEpoch,
    ]);

    final state = (await sources.syncState('work'))!;
    expect(state.lastSuccessUtc, now);
    expect(state.lastError, isNull);
    // Newest first: the whole-run entry is written after the source's.
    expect((await log.recent()).map((e) => (e.sourceId, e.outcome)), [
      (null, SyncOutcome.success),
      ('work', SyncOutcome.success),
    ]);
    expect(await sync.lastFinished(), now);
    expect(syncCallsNamed('acquireLock'), hasLength(1));
    expect(syncCallsNamed('releaseLock'), hasLength(1));
  });

  test(
    'engine events are drained before planning, so a Dismiss all counts',
    () async {
      queuedEvents.add({
        'type': 'dismissedAll',
        'alertId': PlannedAlert.idFor(meeting.key, 10),
        'occurrenceKey': meeting.key,
        'startUtcMs': meeting.startUtc.millisecondsSinceEpoch,
        'atUtcMs': now.millisecondsSinceEpoch,
        'snoozeUntilUtcMs': null,
      });
      await sync.run(SyncTrigger.periodic);
      expect(applied(), isEmpty);
      expect((await history.recent()).single.type, AlertEventType.dismissedAll);
    },
  );

  test('a disabled source is neither fetched nor planned', () async {
    await sync.run(SyncTrigger.periodic);
    await sources.save(work.copyWith(enabled: false));
    built.clear();
    await sync.run(SyncTrigger.periodic);
    expect(built, isEmpty);
    expect(applied(), isEmpty);
  });

  test('a temporary failure keeps the cache and asks for a retry', () async {
    await sync.run(SyncTrigger.periodic);
    final firstSuccess = now;
    now = now.add(const Duration(minutes: 15));
    results['work'] = () => const SourceFailed(
      SyncOutcome.networkError,
      'Could not reach the calendar server.',
    );

    final report = await sync.run(SyncTrigger.periodic);

    expect(report.outcome, SyncRunOutcome.retry);
    expect(await cache.byKey(meeting.key), meeting);
    expect(applied(), hasLength(2));
    final state = (await sources.syncState('work'))!;
    expect(state.lastSuccessUtc, firstSuccess);
    expect(state.lastAttemptUtc, now);
    expect(state.lastError, 'Could not reach the calendar server.');
    expect(syncCallsNamed('postSourceNotice'), isEmpty);
  });

  test(
    'a broken link notifies once, and recovery withdraws the notice',
    () async {
      results['work'] = () => const SourceFailed(
        SyncOutcome.httpError,
        'Link no longer works (HTTP 404).',
      );
      final report = await sync.run(SyncTrigger.periodic);
      await sync.run(SyncTrigger.periodic);

      expect(report.outcome, SyncRunOutcome.ok); // red, but nothing to retry
      final posted = syncCallsNamed('postSourceNotice');
      expect(posted, hasLength(1));
      expect(posted.single.arguments, {
        'kind': 'broken',
        'sourceId': 'work',
        'title': 'Work Outlook feed link stopped working',
        'text': 'Link no longer works (HTTP 404).',
      });

      results['work'] = () => SourceFetched([meeting]);
      await sync.run(SyncTrigger.periodic);
      expect(
        syncCallsNamed('cancelSourceNotice').map((c) => c.arguments),
        anyElement(equals({'kind': 'broken', 'sourceId': 'work'})),
      );
    },
  );

  test('server errors with no success for 24 h become a broken link', () async {
    await sync.run(SyncTrigger.periodic); // success at 06:00
    results['work'] = () => const SourceFailed(
      SyncOutcome.serverError,
      'The calendar server had a problem (HTTP 500). Retrying.',
    );
    now = now.add(const Duration(hours: 23));
    final amber = await sync.run(SyncTrigger.periodic);
    expect(amber.sources.single.outcome, SyncOutcome.serverError);
    expect(amber.outcome, SyncRunOutcome.retry);
    expect(syncCallsNamed('postSourceNotice'), isEmpty);

    now = now.add(const Duration(hours: 1));
    final red = await sync.run(SyncTrigger.periodic);
    expect(red.sources.single.outcome, SyncOutcome.httpError);
    expect(red.sources.single.message, contains('over 24 h'));
    expect(red.outcome, SyncRunOutcome.ok);
    final notice = syncCallsNamed('postSourceNotice').single.arguments as Map;
    expect(notice['kind'], 'broken');
    expect(notice['title'], 'Work Outlook feed link stopped working');

    now = now.add(const Duration(minutes: 15));
    await sync.run(SyncTrigger.periodic);
    expect(syncCallsNamed('postSourceNotice'), hasLength(1));
  });

  test(
    'a source that never synced escalates 24 h after its first failure',
    () async {
      results['work'] = () =>
          const SourceFailed(SyncOutcome.serverError, 'HTTP 500');
      await sync.run(SyncTrigger.periodic);
      now = now.add(const Duration(hours: 24));
      final report = await sync.run(SyncTrigger.periodic);
      expect(report.sources.single.outcome, SyncOutcome.httpError);
    },
  );

  test('network errors never escalate, however long they last', () async {
    await sync.run(SyncTrigger.periodic);
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    now = now.add(const Duration(days: 3));
    final report = await sync.run(SyncTrigger.periodic);
    expect(report.sources.single.outcome, SyncOutcome.networkError);
  });

  test('device-source failures post their own broken titles', () {
    expect(
      SyncService.brokenTitle(work, SyncOutcome.calendarAccessDenied),
      'Work Outlook: calendar access was turned off',
    );
    expect(
      SyncService.brokenTitle(work, SyncOutcome.calendarMissing),
      'Work Outlook: calendar was removed',
    );
  });

  test('an empty feed is ignored once and accepted the second time', () async {
    await sync.run(SyncTrigger.periodic);
    results['work'] = () => const SourceFetched([]);

    final first = await sync.run(SyncTrigger.periodic);
    expect(first.sources.single.outcome, SyncOutcome.emptyKept);
    expect(await cache.countForSource('work'), 1);
    expect((await sources.syncState('work'))!.emptyStreak, 1);

    final second = await sync.run(SyncTrigger.periodic);
    expect(second.sources.single.outcome, SyncOutcome.success);
    expect(await cache.countForSource('work'), 0);
    expect(applied(), isEmpty);
  });

  test('an applyPlan failure is logged and retried', () async {
    applyAnswer = (_) => throw PlatformException(code: 'engine_error');
    final report = await sync.run(SyncTrigger.periodic);
    expect(report.outcome, SyncRunOutcome.retry);
    expect(report.applied, isNull);
    final run = (await log.recent()).firstWhere((e) => e.sourceId == null);
    expect(run.outcome, SyncOutcome.otherError);
    expect(run.message, contains('applyPlan failed (engine_error)'));
    expect(await settings.getString(SyncService.expectedKey), '[]');
  });

  test('an armed alert with no fired record becomes missed (system)', () async {
    await sync.run(SyncTrigger.periodic); // arms 07:50 and 07:59
    now = DateTime.utc(2026, 10, 6, 7, 55); // 07:50 + 5 min, nothing fired
    final report = await sync.run(SyncTrigger.periodic);

    expect(report.missedSystem, 1);
    final missed = (await history.recent()).single;
    expect(missed.type, AlertEventType.missedSystem);
    expect(missed.alertId, PlannedAlert.idFor(meeting.key, 10));
    expect(missed.atUtc, DateTime.utc(2026, 10, 6, 7, 50));
    expect(missed.title, 'Sprint planning');

    now = DateTime.utc(2026, 10, 6, 8, 5); // the 07:59 alarm fired in time
    queuedEvents.add({
      'type': 'fired',
      'alertId': PlannedAlert.idFor(meeting.key, 1),
      'occurrenceKey': meeting.key,
      'startUtcMs': meeting.startUtc.millisecondsSinceEpoch,
      'atUtcMs': DateTime.utc(2026, 10, 6, 7, 59).millisecondsSinceEpoch,
      'snoozeUntilUtcMs': null,
    });
    expect((await sync.run(SyncTrigger.periodic)).missedSystem, 0);
  });

  test('a stale feed with an alert due within 2 h posts Feed stale', () async {
    await sync.run(SyncTrigger.periodic); // last success 06:00
    now = DateTime.utc(2026, 10, 6, 7, 10); // 70 min later; heads-up at 07:50
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    await sync.run(SyncTrigger.periodic);

    final stale = syncCallsNamed('postSourceNotice').single.arguments as Map;
    expect(stale['kind'], 'stale');
    expect(
      stale['title'],
      "Calendar hasn't synced for 1 h — alarms may be outdated",
    );
    expect(stale['text'], 'Work Outlook');

    results['work'] = () => SourceFetched([meeting]);
    syncCalls.clear();
    await sync.run(SyncTrigger.periodic);
    expect(syncCallsNamed('postSourceNotice'), isEmpty);
    expect(
      syncCallsNamed('cancelSourceNotice').map((c) => c.arguments),
      anyElement(equals({'kind': 'stale', 'sourceId': 'work'})),
    );
  });

  test('stale data with nothing due soon posts nothing', () async {
    await sync.run(SyncTrigger.periodic);
    now = DateTime.utc(2026, 10, 6, 9); // the meeting is over
    results['work'] = () =>
        const SourceFailed(SyncOutcome.networkError, 'offline');
    await sync.run(SyncTrigger.periodic);
    expect(syncCallsNamed('postSourceNotice'), isEmpty);
  });

  test('a device source turns the calendar watch on', () async {
    await sources.save(
      const SourceConfig(
        id: 'phone',
        name: 'Phone',
        color: blue,
        kind: SourceKind.device,
        deviceCalendarId: '3',
      ),
    );
    results['phone'] = () => const SourceFetched([]);
    await sync.run(SyncTrigger.calendarChange);
    final configure = syncCallsNamed('configure').single.arguments as Map;
    expect(configure['watchCalendars'], isTrue);
  });

  test(
    'when another sync holds the lock the run waits, then reports busy',
    () async {
      lockFree = false;
      final report = await sync.run(SyncTrigger.manual);
      expect(report.outcome, SyncRunOutcome.busy);
      expect(built, isEmpty);
      expect(syncCallsNamed('acquireLock').length, greaterThan(1));
      expect(syncCallsNamed('releaseLock'), isEmpty);
      expect((await log.recent()).single.message, contains('another sync'));
    },
  );

  test('history and the sync log are pruned', () async {
    await history.record(
      AlertHistoryEntry(
        type: AlertEventType.fired,
        alertId: 'old',
        occurrenceKey: 'k',
        startUtc: now.subtract(const Duration(days: 40)),
        atUtc: now.subtract(const Duration(days: 40)),
      ),
    );
    await log.add(
      SyncLogEntry(
        atUtc: now.subtract(const Duration(days: 8)),
        outcome: SyncOutcome.success,
      ),
    );
    await sync.run(SyncTrigger.periodic);
    expect(await history.recent(), isEmpty);
    expect(
      (await log.recent()).every(
        (e) => e.atUtc.isAfter(now.subtract(const Duration(days: 7))),
      ),
      isTrue,
    );
  });

  test('an unknown trigger name reads as manual', () {
    expect(SyncTrigger.parse('preAlarm'), SyncTrigger.preAlarm);
    expect(SyncTrigger.parse('nope'), SyncTrigger.manual);
    expect(SyncTrigger.parse(null), SyncTrigger.manual);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/sync/sync_service_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sync/sync_service.dart'`.

- [ ] **Step 3: Add `earliestForSource` to the sync log**

In `lib/core/storage/sync_log_repository.dart`, before `/// Deletes entries logged before [cutoffUtc]. Returns the count.` add:

```dart
  /// The oldest entry still stored for [sourceId] (Plan 4: when a source
  /// that never synced started failing).
  Future<SyncLogEntry?> earliestForSource(String sourceId) =>
      (_db.select(_db.syncLog)
            ..where((l) => l.sourceId.equals(sourceId))
            ..orderBy([
              (l) => OrderingTerm.asc(l.atUtcMs),
              (l) => OrderingTerm.asc(l.id),
            ])
            ..limit(1))
          .map(_fromRow)
          .getSingleOrNull();

```

- [ ] **Step 4: Implement `lib/core/sync/sync_service.dart`**

```dart
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
import '../planner/plan_builder.dart';
import '../rules/rules_engine.dart';
import '../sources/calendar_source.dart';
import '../storage/alert_history_repository.dart';
import '../storage/occurrence_repository.dart';
import '../storage/rule_set_loader.dart';
import '../storage/settings_repository.dart';
import '../storage/source_repository.dart';
import '../storage/sync_log_repository.dart';
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

/// What started a sync (spec §7). The Kotlin side passes the first four by
/// name to the headless engine.
enum SyncTrigger {
  periodic,
  calendarChange,
  preAlarm,
  manual,
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
  });

  final SyncTrigger trigger;
  final SyncRunOutcome outcome;
  final List<SourceSyncResult> sources;

  /// Null when `applyPlan` failed or the run was [SyncRunOutcome.busy].
  final ApplyResult? applied;
  final int planned;

  /// New `missedSystem` history rows this run recorded.
  final int missedSystem;
}

/// `syncMain()`'s work (spec §7): fetch all sources → update the cache →
/// resolve rules → build the plan → `applyPlan` → log the result. Runs in the
/// headless engine (SyncWorker) and in the UI isolate (app foreground,
/// pull-to-refresh); a lock shared through Kotlin keeps two runs from
/// overlapping (Plan 4 decision).
class SyncService {
  SyncService({
    required this.sources,
    required this.occurrences,
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

  /// Server errors with no success for this long mean the link is gone
  /// (Plan 4 decision 24: Outlook answers a dead link with HTTP 500).
  static const serverErrorsBeforeBroken = Duration(hours: 24);

  /// Spec §9: "Feed stale > 60 min with an alert due within 2 h".
  static const staleAfter = Duration(minutes: 60);
  static const staleHorizon = Duration(hours: 2);

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
      await syncLog.add(
        SyncLogEntry(
          atUtc: clock(),
          outcome: SyncOutcome.otherError,
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
    final now = clock();
    final window = FetchWindow.around(now);

    // History first: the planner's acknowledgements and the missed (system)
    // check both read it.
    await _quietly(recorder.drainNow);

    final configs = [
      for (final s in await sources.all())
        if (s.enabled) s,
    ];
    final location = zone();
    final fetched = await Future.wait([
      for (final c in configs) _fetch(c, window, location),
    ]);
    final results = <SourceSyncResult>[];
    for (final (config, state, result) in fetched) {
      results.add(await _store(config, state, result, now));
    }

    final plan = await _plan(configs, window, now);
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
    await _staleNotices(configs, plan, now);

    await history.deleteBefore(now.subtract(historyRetention));
    await syncLog.deleteBefore(now.subtract(syncLogRetention));
    await occurrences.deleteEndedBefore(now.subtract(occurrenceRetention));

    final finished = clock();
    await syncLog.add(
      SyncLogEntry(
        atUtc: finished,
        outcome: applied == null ? SyncOutcome.otherError : SyncOutcome.success,
        message: applied == null
            ? '${trigger.name}: applyPlan failed ($applyError); the engine kept its previous plan'
            : '${trigger.name}: ${plan.length} alerts planned; armed ${applied.armed}, cancelled ${applied.cancelled}, kept ${applied.kept}',
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
    final last = (await syncLog.latestForSource(config.id))?.outcome;
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
        if (last != null && last.notifiesBroken) {
          await _quietly(
            () => platform.cancelSourceNotice(
              kind: SourceNoticeKind.broken,
              sourceId: config.id,
            ),
          );
        }
        return SourceSyncResult(config.id, outcome, message);

      case SourceFailed():
        final (:outcome, :message) = await _escalate(
          config,
          state,
          result,
          now,
        );
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
        if (outcome.notifiesBroken && last != outcome) {
          await _quietly(
            () => platform.postSourceNotice(
              kind: SourceNoticeKind.broken,
              sourceId: config.id,
              title: brokenTitle(config, outcome),
              text: message,
            ),
          );
        }
        return SourceSyncResult(config.id, outcome, message);
    }
  }

  /// A server error with no success for [serverErrorsBeforeBroken] (since
  /// the last success, or since the source's first logged sync if it never
  /// succeeded) is reported as a broken link. Network errors never are:
  /// being offline says nothing about the link.
  Future<({SyncOutcome outcome, String message})> _escalate(
    SourceConfig config,
    SourceSyncState? state,
    SourceFailed failure,
    DateTime now,
  ) async {
    final asIs = (outcome: failure.outcome, message: failure.message);
    if (failure.outcome != SyncOutcome.serverError) return asIs;
    final since =
        state?.lastSuccessUtc ??
        (await syncLog.earliestForSource(config.id))?.atUtc;
    if (since == null || now.difference(since) < serverErrorsBeforeBroken) {
      return asIs;
    }
    return (
      outcome: SyncOutcome.httpError,
      message:
          'The calendar server has kept failing for over '
          '${serverErrorsBeforeBroken.inHours} h. The link may have been '
          'reset or unpublished.',
    );
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

  Future<List<PlannedAlert>> _plan(
    List<SourceConfig> configs,
    FetchWindow window,
    DateTime now,
  ) async {
    final enabled = {for (final c in configs) c.id};
    final cached = await occurrences.between(
      now.subtract(keepAfterEnd),
      window.endUtc,
    );
    final rules = await ruleSets.load();
    final resolved = rulesEngine().resolveAll(
      cached.where((o) => enabled.contains(o.sourceId)),
      rules,
    );
    return buildPlan(
      resolved,
      now: now,
      acknowledgements: await history.acknowledgements(nowUtc: now),
    );
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

  /// Posts or withdraws each ICS source's Feed stale notification.
  Future<void> _staleNotices(
    List<SourceConfig> configs,
    List<PlannedAlert> plan,
    DateTime now,
  ) async {
    for (final c in configs.where((c) => c.kind == SourceKind.ics)) {
      final lastSuccess = (await sources.syncState(c.id))?.lastSuccessUtc;
      final age = lastSuccess == null ? null : now.difference(lastSuccess);
      final dueSoon = plan.any(
        (a) =>
            a.occurrenceKey.startsWith('${c.id}|') &&
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

  /// Platform side effects never fail a sync.
  static Future<void> _quietly(Future<Object?> Function() call) async {
    try {
      await call();
    } on MissingPluginException {
      // No native side (tests, desktop).
    } on PlatformException catch (e) {
      debugPrint('Sync side effect failed: ${e.code}');
    }
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `dart format lib/core/sync lib/core/storage/sync_log_repository.dart test/core/sync`
Run: `flutter test test/core/sync/sync_service_test.dart`
Expected: `All tests passed!` (18 tests). The lock test waits its 30 ms of real time.

- [ ] **Step 6: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 7: Commit**

```bash
git add lib/core/sync/sync_service.dart lib/core/storage/sync_log_repository.dart test/core/sync/sync_service_test.dart
git commit -m "Sync every source, plan, apply and report missed and stale alarms in one run"
```

---

### Task 12: Source admin, fast alarms and the source factory

**Files:**
- Create: `lib/core/sources/source_admin.dart`, `lib/core/sources/fast_alarms.dart`, `lib/core/sources/source_factory.dart`
- Test: `test/core/sources/source_admin_test.dart`

**Interfaces:**
- Consumes: `IcsUrl`, `SourceSecrets`, `FeedBodyCache` (Task 2); `IcsFeedSource` (Task 3); `DeviceCalendar`, `DeviceCalendarApi`, `DeviceCalendarSource` (Task 5); `SourceRepository`, `SettingsRepository` (Plan 2).
- Produces: `class IcsUrlException(String message)`; `class SourceAdmin({required sources, required secrets, required bodies, Random? random})` with `Future<({SourceConfig source, bool insecure})> addIcsSource({required String name, required int color, required String url, String? defaultProfileId})`, `Future<bool> updateIcsUrl(String sourceId, String url)`, `Future<SourceConfig> addDeviceSource({required DeviceCalendar calendar, String? name, int? color, String? defaultProfileId})`, `Future<void> delete(String sourceId)`; ids are `ics-<12 hex>` / `device-<12 hex>`; `class FastAlarms({required sources, required settings})` with `sourceId = 'debug-fast-alarms'`, `settingsKey = 'debug.fastAlarms'`, `color = 0xFFE89A5B`, `create(DateTime now)`, `clear()`, `occurrences(SourceConfig)`; `class FastAlarmsSource({required config, required fastAlarms}) implements CalendarSource`; `class SourceFactory({required client, required secrets, required bodies, required deviceCalendars, required fastAlarms})` with `CalendarSource create(SourceConfig config, SourceSyncState? state, {required tz.Location zone})`.

`SourceAdmin` does not sync. Its callers (Plan 5's Sources tab and onboarding, Task 14's debug panel) run `SyncService.run` afterwards.

- [ ] **Step 1: Write the failing test**

`test/core/sources/source_admin_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:tminus/core/model/source_config.dart';
import 'package:tminus/core/sources/calendar_source.dart';
import 'package:tminus/core/sources/device_calendar_api.dart';
import 'package:tminus/core/sources/device_calendar_source.dart';
import 'package:tminus/core/sources/fast_alarms.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/sources/ics_feed_source.dart';
import 'package:tminus/core/sources/source_admin.dart';
import 'package:tminus/core/sources/source_factory.dart';
import 'package:tminus/core/sources/source_secrets.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/occurrence_repository.dart';
import 'package:tminus/core/storage/settings_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';

import '../fixtures.dart';
import '../storage/test_database.dart';

void main() {
  late AppDatabase db;
  late SourceRepository sources;
  late Directory dir;
  late FeedBodyCache bodies;
  late SourceAdmin admin;
  final secrets = SourceSecrets();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = openTestDatabase();
    sources = SourceRepository(db);
    dir = await Directory.systemTemp.createTemp('feeds');
    bodies = FeedBodyCache(() async => dir);
    admin = SourceAdmin(sources: sources, secrets: secrets, bodies: bodies);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  group('SourceAdmin', () {
    test(
      'an ICS source keeps its link in secure storage, not in drift',
      () async {
        final added = await admin.addIcsSource(
          name: 'Work Outlook',
          color: blue,
          url:
              'webcal://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics',
        );
        final s = added.source;
        expect(added.insecure, isFalse);
        expect(s.id, startsWith('ics-'));
        expect(s.kind, SourceKind.ics);
        expect(s.secureStorageKey, SourceSecrets.keyFor(s.id));
        expect(await sources.byId(s.id), s);
        expect(
          await secrets.readUrl(s.secureStorageKey!),
          'https://outlook.office365.com/owa/calendar/s3cr3t/calendar.ics',
        );
        final row = await db.customSelect('SELECT * FROM sources').getSingle();
        expect(row.data.values.join(' '), isNot(contains('s3cr3t')));
      },
    );

    test('a plain http link is added and flagged insecure', () async {
      final added = await admin.addIcsSource(
        name: 'Home',
        color: blue,
        url: 'http://example.com/home.ics',
      );
      expect(added.insecure, isTrue);
    });

    test('a rejected link adds nothing', () async {
      await expectLater(
        admin.addIcsSource(
          name: 'Work',
          color: blue,
          url: 'https://outlook.office365.com/owa/calendar/x/calendar.html',
        ),
        throwsA(isA<IcsUrlException>()),
      );
      expect(await sources.all(), isEmpty);
    });

    test('two sources never share an id', () async {
      final a = await admin.addIcsSource(
        name: 'A',
        color: blue,
        url: 'https://a.example/a.ics',
      );
      final b = await admin.addIcsSource(
        name: 'B',
        color: blue,
        url: 'https://b.example/b.ics',
      );
      expect(a.source.id, isNot(b.source.id));
    });

    test(
      'a new link replaces the old one and forgets the validators and body',
      () async {
        final s = (await admin.addIcsSource(
          name: 'W',
          color: blue,
          url: 'https://a.example/a.ics',
        )).source;
        await sources.updateSyncState(
          s.id,
          SourceSyncState(
            lastSuccessUtc: DateTime.utc(2026, 10, 6),
            httpEtag: '"v1"',
            httpLastModified: 'x',
          ),
        );
        await bodies.write(s.id, 'old body');

        expect(
          await admin.updateIcsUrl(s.id, 'https://b.example/b.ics'),
          isFalse,
        );

        expect(
          await secrets.readUrl(s.secureStorageKey!),
          'https://b.example/b.ics',
        );
        final state = (await sources.syncState(s.id))!;
        expect(state.httpEtag, isNull);
        expect(state.httpLastModified, isNull);
        expect(state.lastSuccessUtc, DateTime.utc(2026, 10, 6));
        expect(await bodies.read(s.id), isNull);
      },
    );

    test(
      'a device source takes the calendar name and colour by default',
      () async {
        const calendar = DeviceCalendar(
          id: '3',
          name: 'Work',
          color: 0xFF33AA66,
          visible: true,
        );
        final s = await admin.addDeviceSource(calendar: calendar);
        expect(s.id, startsWith('device-'));
        expect(
          (s.kind, s.deviceCalendarId, s.name, s.color),
          (SourceKind.device, '3', 'Work', 0xFF33AA66),
        );
        final renamed = await admin.addDeviceSource(
          calendar: calendar,
          name: 'Phone',
          color: blue,
        );
        expect((renamed.name, renamed.color), ('Phone', blue));
      },
    );

    test(
      'delete removes the row, its occurrences, its link and its body',
      () async {
        final s = (await admin.addIcsSource(
          name: 'W',
          color: blue,
          url: 'https://a.example/a.ics',
        )).source;
        await OccurrenceRepository(db)
            .replaceForSource(s.id, [occ(sourceId: s.id)]);
        await bodies.write(s.id, 'body');

        await admin.delete(s.id);

        expect(await sources.byId(s.id), isNull);
        expect(await OccurrenceRepository(db).countForSource(s.id), 0);
        expect(await secrets.readUrl(s.secureStorageKey!), isNull);
        expect(await bodies.read(s.id), isNull);
      },
    );
  });

  group('FastAlarms', () {
    test(
      'three fixed events: a coalesced pair at +2 min and a Teams call at +12',
      () async {
        final fast = FastAlarms(
          sources: sources,
          settings: SettingsRepository(db),
        );
        final now = DateTime.utc(2026, 10, 6, 8, 0, 10, 500);
        await fast.create(now);

        final source = (await sources.byId(FastAlarms.sourceId))!;
        expect((source.kind, source.name), (SourceKind.debug, 'Fast alarms'));
        final fetched = await FastAlarmsSource(
          config: source,
          fastAlarms: fast,
        ).fetch(FetchWindow.around(now)) as SourceFetched;
        final events = fetched.occurrences;
        expect(events.map((o) => o.startUtc), [
          DateTime.utc(2026, 10, 6, 8, 2, 10),
          DateTime.utc(2026, 10, 6, 8, 2, 10),
          DateTime.utc(2026, 10, 6, 8, 12, 10),
        ]);
        expect(events.map((o) => o.joinUrl != null), [false, false, true]);
        expect(events.map((o) => o.key).toSet(), hasLength(3));

        // Later syncs see the same times.
        final again =
            await FastAlarmsSource(config: source, fastAlarms: fast).fetch(
              FetchWindow.around(now.add(const Duration(minutes: 1))),
            ) as SourceFetched;
        expect(again.occurrences, events);

        await fast.clear();
        expect(await sources.byId(FastAlarms.sourceId), isNull);
        expect(await fast.occurrences(source), isEmpty);
      },
    );
  });

  test('the factory builds the source type each kind needs', () {
    final factory = SourceFactory(
      client: MockClient((_) async => http.Response('', 200)),
      secrets: secrets,
      bodies: bodies,
      deviceCalendars: DeviceCalendarApi(),
      fastAlarms: FastAlarms(
        sources: sources,
        settings: SettingsRepository(db),
      ),
    );
    SourceConfig config(SourceKind kind) =>
        SourceConfig(id: kind.name, name: kind.name, color: blue, kind: kind);
    final ics = factory.create(
      config(SourceKind.ics),
      null,
      zone: johannesburg,
    );
    expect(ics, isA<IcsFeedSource>());
    expect((ics as IcsFeedSource).deviceZone, 'Africa/Johannesburg');
    expect(
      factory.create(config(SourceKind.device), null, zone: johannesburg),
      isA<DeviceCalendarSource>(),
    );
    expect(
      factory.create(config(SourceKind.debug), null, zone: johannesburg),
      isA<FastAlarmsSource>(),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/sources/source_admin_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sources/source_admin.dart'`.

- [ ] **Step 3: Implement**

`lib/core/sources/source_admin.dart`:

```dart
import 'dart:math';

import '../model/source_config.dart';
import '../storage/source_repository.dart';
import 'device_calendar_api.dart';
import 'feed_body_cache.dart';
import 'ics_url.dart';
import 'source_secrets.dart';

/// [IcsUrl.check] rejected a link.
class IcsUrlException implements Exception {
  const IcsUrlException(this.message);
  final String message;

  @override
  String toString() => 'IcsUrlException: $message';
}

/// Adds, re-links and removes sources (Plan 5's Sources tab and onboarding
/// call this, then run a sync). The ICS link goes to secure storage, never to
/// drift (spec §10).
class SourceAdmin {
  SourceAdmin({
    required this.sources,
    required this.secrets,
    required this.bodies,
    Random? random,
  }) : _random = random ?? Random.secure();

  final SourceRepository sources;
  final SourceSecrets secrets;
  final FeedBodyCache bodies;
  final Random _random;

  /// Throws [IcsUrlException] for a link [IcsUrl.check] rejects. Returns the
  /// source and whether the link is plain `http://` (Plan 5 warns).
  Future<({SourceConfig source, bool insecure})> addIcsSource({
    required String name,
    required int color,
    required String url,
    String? defaultProfileId,
  }) async {
    final link = _accepted(url);
    final id = _newId('ics');
    final key = SourceSecrets.keyFor(id);
    await secrets.writeUrl(key, link.url);
    final source = SourceConfig(
      id: id,
      name: name,
      color: color,
      kind: SourceKind.ics,
      secureStorageKey: key,
      defaultProfileId: defaultProfileId,
    );
    await sources.save(source);
    return (source: source, insecure: link.insecure);
  }

  /// A new link for an existing ICS source (e.g. after it was reset in
  /// Outlook). Forgets the old conditional-GET validators and stored body.
  /// Returns whether the link is plain `http://`.
  Future<bool> updateIcsUrl(String sourceId, String url) async {
    final link = _accepted(url);
    final source = await sources.byId(sourceId);
    final key = source?.secureStorageKey;
    if (source == null || source.kind != SourceKind.ics || key == null) {
      throw ArgumentError.value(sourceId, 'sourceId', 'not an ICS source');
    }
    await secrets.writeUrl(key, link.url);
    final state = await sources.syncState(sourceId);
    await sources.updateSyncState(
      sourceId,
      SourceSyncState(
        lastAttemptUtc: state?.lastAttemptUtc,
        lastSuccessUtc: state?.lastSuccessUtc,
        lastError: state?.lastError,
        emptyStreak: state?.emptyStreak ?? 0,
      ),
    );
    await bodies.delete(sourceId);
    return link.insecure;
  }

  /// A phone calendar as a source. Name and colour default to the
  /// calendar's own.
  Future<SourceConfig> addDeviceSource({
    required DeviceCalendar calendar,
    String? name,
    int? color,
    String? defaultProfileId,
  }) async {
    final source = SourceConfig(
      id: _newId('device'),
      name: name ?? calendar.name,
      color: color ?? calendar.color,
      kind: SourceKind.device,
      deviceCalendarId: calendar.id,
      defaultProfileId: defaultProfileId,
    );
    await sources.save(source);
    return source;
  }

  /// Removes the source, its cached occurrences, its link and its stored
  /// feed body.
  Future<void> delete(String sourceId) async {
    final source = await sources.byId(sourceId);
    await sources.delete(sourceId);
    final key = source?.secureStorageKey;
    if (key != null) await secrets.delete(key);
    await bodies.delete(sourceId);
  }

  IcsUrlAccepted _accepted(String url) => switch (IcsUrl.check(url)) {
    IcsUrlAccepted a => a,
    IcsUrlRejected(:final message) => throw IcsUrlException(message),
  };

  String _newId(String prefix) {
    final bytes = List.generate(6, (_) => _random.nextInt(256));
    return '$prefix-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
```

`lib/core/sources/fast_alarms.dart`:

```dart
import 'dart:convert';

import '../model/event_occurrence.dart';
import '../model/source_config.dart';
import '../storage/settings_repository.dart';
import '../storage/source_repository.dart';
import 'calendar_source.dart';

/// Debug-only "fast alarms" (spec §11): fake events a minute or two ahead
/// that go through the real sync, rules, plan and `applyPlan` path. Their
/// times are stored when created, so later syncs do not move them.
///
/// With the Meeting profile: two events start at +2 min (one coalesced alarm
/// at +1 min) and one with a Teams link starts at +12 min (heads-up at +2 min,
/// alarm at +11 min).
class FastAlarms {
  FastAlarms({required this.sources, required this.settings});

  static const sourceId = 'debug-fast-alarms';
  static const settingsKey = 'debug.fastAlarms';

  /// calendarOrange (dark), so fake events stand out from real calendars.
  static const color = 0xFFE89A5B;

  final SourceRepository sources;
  final SettingsRepository settings;

  /// Replaces any earlier fast alarms with three new events relative to [now].
  Future<void> create(DateTime now) async {
    final base = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );
    final soon = base.add(const Duration(minutes: 2));
    final later = base.add(const Duration(minutes: 12));
    final stamp = base.millisecondsSinceEpoch;
    final events = [
      _event('fast-$stamp-1', 'Fast alarm: standup', soon),
      _event('fast-$stamp-2', 'Fast alarm: 1:1', soon),
      _event(
        'fast-$stamp-3',
        'Fast alarm: Teams call',
        later,
        joinUrl: 'https://teams.microsoft.com/l/meetup-join/fast-alarms-test',
      ),
    ];
    await sources.save(
      const SourceConfig(
        id: sourceId,
        name: 'Fast alarms',
        color: color,
        kind: SourceKind.debug,
      ),
    );
    await settings.setString(settingsKey, jsonEncode(events));
  }

  /// Removes the source; its cached occurrences go with it.
  Future<void> clear() async {
    await sources.delete(sourceId);
    await settings.setString(settingsKey, '[]');
  }

  /// The stored events as occurrences of [source].
  Future<List<EventOccurrence>> occurrences(SourceConfig source) async {
    final json = await settings.getString(settingsKey);
    if (json == null) return const [];
    return [
      for (final e in jsonDecode(json) as List<Object?>)
        _occurrence((e! as Map).cast<String, Object?>(), source),
    ];
  }

  static Map<String, Object?> _event(
    String uid,
    String title,
    DateTime start, {
    String? joinUrl,
  }) => {
    'uid': uid,
    'title': title,
    'startUtcMs': start.millisecondsSinceEpoch,
    'endUtcMs': start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
    'joinUrl': joinUrl,
  };

  static EventOccurrence _occurrence(
    Map<String, Object?> e,
    SourceConfig source,
  ) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      e['startUtcMs'] as int,
      isUtc: true,
    );
    return EventOccurrence(
      sourceId: source.id,
      uid: e['uid'] as String,
      originalStartUtc: start,
      title: e['title'] as String,
      joinUrl: e['joinUrl'] as String?,
      startUtc: start,
      endUtc: DateTime.fromMillisecondsSinceEpoch(
        e['endUtcMs'] as int,
        isUtc: true,
      ),
      busyStatus: BusyStatus.busy,
      calendarColor: source.color,
    );
  }
}

/// The fast-alarms events as a [CalendarSource].
class FastAlarmsSource implements CalendarSource {
  FastAlarmsSource({required this.config, required this.fastAlarms});

  final SourceConfig config;
  final FastAlarms fastAlarms;

  @override
  String get id => config.id;

  @override
  Future<SourceResult> fetch(FetchWindow window) async {
    final all = await fastAlarms.occurrences(config);
    return SourceFetched([
      for (final o in all)
        if (o.endUtc.isAfter(window.startUtc) &&
            o.startUtc.isBefore(window.endUtc))
          o,
    ]);
  }
}
```

`lib/core/sources/source_factory.dart`:

```dart
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import '../model/source_config.dart';
import 'calendar_source.dart';
import 'device_calendar_api.dart';
import 'device_calendar_source.dart';
import 'fast_alarms.dart';
import 'feed_body_cache.dart';
import 'ics_feed_source.dart';
import 'source_secrets.dart';

/// Builds the [CalendarSource] for a stored [SourceConfig], once per sync.
class SourceFactory {
  SourceFactory({
    required this.client,
    required this.secrets,
    required this.bodies,
    required this.deviceCalendars,
    required this.fastAlarms,
  });

  final http.Client client;
  final SourceSecrets secrets;
  final FeedBodyCache bodies;
  final DeviceCalendarApi deviceCalendars;
  final FastAlarms fastAlarms;

  /// [state] supplies the ICS conditional-GET validators; [zone] is the
  /// device zone for floating and all-day times.
  CalendarSource create(
    SourceConfig config,
    SourceSyncState? state, {
    required tz.Location zone,
  }) => switch (config.kind) {
    SourceKind.ics => IcsFeedSource(
      config: config,
      previous: state,
      client: client,
      secrets: secrets,
      bodies: bodies,
      deviceZone: zone.name,
    ),
    SourceKind.device => DeviceCalendarSource(
      config: config,
      api: deviceCalendars,
      zone: zone,
    ),
    SourceKind.debug => FastAlarmsSource(
      config: config,
      fastAlarms: fastAlarms,
    ),
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart format lib/core/sources test/core/sources`
Run: `flutter test test/core/sources/source_admin_test.dart`
Expected: `All tests passed!` (9 tests).

- [ ] **Step 5: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 6: Commit**

```bash
git add lib/core/sources test/core/sources/source_admin_test.dart
git commit -m "Add, re-link and remove sources, and add the debug fast-alarms source"
```

---

### Task 13: Headless sync, foreground sync and app wiring

**Files:**
- Create: `android/app/src/main/kotlin/io/github/fifothehein/tminus/sync/HeadlessFlutterRunner.kt`
- Modify: `android/app/src/main/kotlin/io/github/fifothehein/tminus/sync/SyncWorker.kt` (the default constructor)
- Create: `lib/core/sync/foreground_sync.dart`, `lib/app/sync_main.dart`
- Modify: `lib/app/di.dart`, `lib/main.dart`
- Test: `test/core/sync/foreground_sync_test.dart`, `test/app/di_test.dart` (one new test)

**Interfaces:**
- Consumes: everything above. `AlarmEngineChannel.register` / `detach` (Plan 3); `SyncChannel.register` / `detach`, `SyncRunner`, `SyncWorker.OUTCOME_RETRY` (Tasks 8, 9); `SyncService`, `SyncTrigger`, `SyncRunOutcome` (Task 11); `initDeviceZone`, `SyncPlatform.finished` (Task 10); `EngineEventRecorder.start` (Task 6).
- Produces: `class HeadlessFlutterRunner(context, timeoutMs = TIMEOUT_MS) : SyncRunner` with `ENTRYPOINT = "syncMain"`, `TIMEOUT_MS = 8 min`; `SyncWorker(context, params)`; `class ForegroundSync({required SyncService sync, UtcClock? clock})` with `minGap = 2 min`, `start()`, `Future<SyncReport?> maybeSync()`, `dispose()`; `Future<void> runHeadlessSync(List<String> args)`; top-level `@pragma('vm:entry-point') Future<void> syncMain(List<String> args)` in `lib/main.dart`; DI registrations (lazy singletons) for `http.Client`, `SourceSecrets`, `FeedBodyCache` (`<application support>/feeds`), `DeviceCalendarApi`, `SyncPlatform`, `FastAlarms`, `SourceFactory`, `SourceAdmin`, `EngineEventRecorder`, `SyncService`, `ForegroundSync`.

The headless engine is created on the main thread (`ListenableWorker.startWork` runs there). It registers plugins itself (`FlutterEngine(context)` uses Flutter's generated registrant). It gets its own `alarm_engine` channel, whose `EngineEvents` listener Plan 3 supports alongside the app's, and its own `tminus_sync` channel. Dart has to call `DartPluginRegistrant.ensureInitialized()` because Flutter only does that for `main`. The entry point must be in `lib/main.dart`, the library the engine looks in by default, and `vm:entry-point` keeps release builds from tree-shaking it.

- [ ] **Step 1: Write the failing tests**

`test/core/sync/foreground_sync_test.dart`. The test binding takes lifecycle states one step at a time, so a resume is sent as the full path away and back:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sync/foreground_sync.dart';
import 'package:tminus/core/sync/sync_service.dart';

/// Only what ForegroundSync uses; the rest of SyncService is never called.
class _FakeSync implements SyncService {
  DateTime? finishedAt;
  final runs = <SyncTrigger>[];
  Future<void> gate = Future.value();

  @override
  Future<DateTime?> lastFinished() async => finishedAt;

  @override
  Future<SyncReport> run(SyncTrigger trigger) async {
    runs.add(trigger);
    await gate;
    return SyncReport(trigger: trigger, outcome: SyncRunOutcome.ok);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 6, 8);
  late _FakeSync sync;
  late ForegroundSync foreground;

  setUp(() {
    sync = _FakeSync();
    foreground = ForegroundSync(sync: sync, clock: () => now);
  });

  tearDown(() => foreground.dispose());

  test(
    'syncs when the last sync is older than 2 min, or there was none',
    () async {
      expect(await foreground.maybeSync(), isNotNull);
      sync.finishedAt = now.subtract(const Duration(minutes: 3));
      expect(await foreground.maybeSync(), isNotNull);
      expect(sync.runs, [SyncTrigger.foreground, SyncTrigger.foreground]);
    },
  );

  test('skips when a sync finished within 2 min', () async {
    sync.finishedAt = now.subtract(const Duration(seconds: 90));
    expect(await foreground.maybeSync(), isNull);
    expect(sync.runs, isEmpty);
  });

  test('a resume while a foreground sync runs joins it', () async {
    final release = Completer<void>();
    sync.gate = release.future;
    final first = foreground.maybeSync();
    final second = foreground.maybeSync();
    release.complete();
    expect(await first, same(await second));
    expect(sync.runs, hasLength(1));
  });

  test('start syncs at once and again when the app resumes', () async {
    foreground.start();
    await pumpEventQueue();
    expect(sync.runs, hasLength(1));
    sync.finishedAt = now.subtract(const Duration(minutes: 5));
    // The binding takes one lifecycle step at a time: away and back.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await pumpEventQueue();
    expect(sync.runs, hasLength(2));
  });
}
```

In `test/app/di_test.dart`, after `import 'package:tminus/core/storage/source_repository.dart';` add:

```dart
import 'package:tminus/core/sources/source_admin.dart';
import 'package:tminus/core/sources/source_factory.dart';
import 'package:tminus/core/sync/engine_event_recorder.dart';
import 'package:tminus/core/sync/foreground_sync.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';
```

and before `test('configureDependencies loads the time zone database', () {` add:

```dart
  test('the sync services share one engine and one event recorder', () {
    configureDependencies(openDatabase: openTestDatabase);
    final sync = getIt<SyncService>();
    expect(sync.engine, same(getIt<AlarmEngine>()));
    expect(sync.recorder, same(getIt<EngineEventRecorder>()));
    expect(getIt<EngineEventRecorder>().engine, same(getIt<AlarmEngine>()));
    expect(getIt<ForegroundSync>().sync, same(sync));
    expect(getIt<SyncPlatform>(), same(getIt<SyncPlatform>()));
    expect(getIt<SourceFactory>(), isNotNull);
    expect(getIt<SourceAdmin>(), isNotNull);
  });

```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/sync/foreground_sync_test.dart test/app/di_test.dart`
Expected: compilation fails, `Error when reading 'lib/core/sync/foreground_sync.dart'`.

- [ ] **Step 3: Implement the foreground sync**

`lib/core/sync/foreground_sync.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../rules/rules_engine.dart';
import 'sync_service.dart';

/// Spec §7 "App foreground": syncs in the UI isolate at app start and on
/// every resume, unless a sync (from any isolate) finished in the last
/// [minGap] (Plan 4 decision). Pull-to-refresh (Plan 5) calls
/// [SyncService.run] directly and always syncs.
class ForegroundSync {
  ForegroundSync({required this.sync, UtcClock? clock})
    : clock = clock ?? systemUtcNow;

  static const minGap = Duration(minutes: 2);

  final SyncService sync;
  final UtcClock clock;
  AppLifecycleListener? _listener;
  Future<SyncReport?>? _running;

  /// Syncs now if due, then again on each resume.
  void start() {
    _listener ??= AppLifecycleListener(onResume: () => unawaited(maybeSync()));
    unawaited(maybeSync());
  }

  /// Runs a foreground sync unless one finished within [minGap] or one
  /// started here is still running. Never throws.
  Future<SyncReport?> maybeSync() {
    return _running ??= _syncIfDue().whenComplete(() => _running = null);
  }

  Future<SyncReport?> _syncIfDue() async {
    try {
      final last = await sync.lastFinished();
      if (last != null && clock().difference(last) < minGap) return null;
      return await sync.run(SyncTrigger.foreground);
    } catch (e, s) {
      debugPrint('Foreground sync failed: $e\n$s');
      return null;
    }
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
```

- [ ] **Step 4: Register the services**

In `lib/app/di.dart`, replace the first line `import 'package:get_it/get_it.dart';` with:

```dart
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
```

after `import '../core/rules/rules_engine.dart';` add:

```dart
import '../core/sources/device_calendar_api.dart';
import '../core/sources/fast_alarms.dart';
import '../core/sources/feed_body_cache.dart';
import '../core/sources/source_admin.dart';
import '../core/sources/source_factory.dart';
import '../core/sources/source_secrets.dart';
```

after `import '../core/storage/sync_log_repository.dart';` add:

```dart
import '../core/sync/engine_event_recorder.dart';
import '../core/sync/foreground_sync.dart';
import '../core/sync/sync_platform.dart';
import '../core/sync/sync_service.dart';
```

and replace the end of `configureDependencies`

```dart
  // A factory, not a singleton: each engine reads `tz.local` as it is now.
  // Plan 4 sets `tz.local` from the device zone at startup; until then it
  // is UTC.
  getIt.registerFactory(() => RulesEngine(zone: tz.local));
}
```

with

```dart
  // A factory, not a singleton: each engine reads `tz.local` as it is now.
  // `initDeviceZone` sets it from the device at startup; until then it is UTC.
  getIt.registerFactory(() => RulesEngine(zone: tz.local));

  // Sources and sync (Plan 4).
  getIt.registerLazySingleton<http.Client>(
    http.Client.new,
    dispose: (c) => c.close(),
  );
  getIt.registerLazySingleton<SourceSecrets>(SourceSecrets.new);
  getIt.registerLazySingleton<FeedBodyCache>(
    () => FeedBodyCache(() async {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}${Platform.pathSeparator}feeds');
    }),
  );
  getIt.registerLazySingleton<DeviceCalendarApi>(DeviceCalendarApi.new);
  getIt.registerLazySingleton<SyncPlatform>(SyncPlatform.new);
  getIt.registerLazySingleton(
    () => FastAlarms(sources: getIt(), settings: getIt()),
  );
  getIt.registerLazySingleton(
    () => SourceFactory(
      client: getIt(),
      secrets: getIt(),
      bodies: getIt(),
      deviceCalendars: getIt(),
      fastAlarms: getIt(),
    ),
  );
  getIt.registerLazySingleton(
    () => SourceAdmin(sources: getIt(), secrets: getIt(), bodies: getIt()),
  );
  getIt.registerLazySingleton(
    () => EngineEventRecorder(
      engine: getIt(),
      history: getIt(),
      occurrences: getIt(),
    ),
    dispose: (r) => r.stop(),
  );
  getIt.registerLazySingleton(
    () => SyncService(
      sources: getIt(),
      occurrences: getIt(),
      history: getIt(),
      syncLog: getIt(),
      settings: getIt(),
      ruleSets: getIt(),
      rulesEngine: () => getIt<RulesEngine>(),
      engine: getIt(),
      recorder: getIt(),
      platform: getIt(),
      buildSource: (config, state, zone) =>
          getIt<SourceFactory>().create(config, state, zone: zone),
    ),
  );
  getIt.registerLazySingleton(
    () => ForegroundSync(sync: getIt()),
    dispose: (f) => f.dispose(),
  );
}
```

- [ ] **Step 5: Add the headless entry point and the startup wiring**

`lib/app/sync_main.dart`:

```dart
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';

import '../core/sync/device_zone.dart';
import '../core/sync/sync_platform.dart';
import '../core/sync/sync_service.dart';
import 'di.dart';

/// The headless engine's work (spec §7): `syncMain(args)` in lib/main.dart
/// calls this. [args] holds the trigger name `SyncWorker` passed. Always
/// reports an outcome through `tminus_sync.finished`, so the worker never
/// waits for its timeout.
Future<void> runHeadlessSync(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plugins with a Dart side (path_provider) register themselves only for
  // `main`; another entry point has to ask.
  DartPluginRegistrant.ensureInitialized();
  var outcome = SyncRunOutcome.retry;
  try {
    configureDependencies();
    await initDeviceZone(getIt<SyncPlatform>());
    final report = await getIt<SyncService>().run(
      SyncTrigger.parse(args.isEmpty ? null : args.first),
    );
    outcome = report.outcome;
  } catch (e, s) {
    debugPrint('Headless sync failed: $e\n$s');
  } finally {
    try {
      await getIt.reset(); // closes the database
    } catch (e) {
      debugPrint('Headless sync cleanup failed: $e');
    }
  }
  await SyncPlatform().finished(outcome.name);
}
```

Replace `lib/main.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'app/font_licenses.dart';
import 'app/sync_main.dart';
import 'core/sync/device_zone.dart';
import 'core/sync/engine_event_recorder.dart';
import 'core/sync/foreground_sync.dart';
import 'core/sync/sync_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  configureDependencies();
  await initDeviceZone(getIt<SyncPlatform>());
  // The one consumer of engine events in this isolate (Plan 3 note), started
  // before the first sync so history is current when it plans.
  unawaited(getIt<EngineEventRecorder>().start());
  getIt<ForegroundSync>().start();
  runApp(const TMinusApp());
}

/// The headless sync engine's entry point (`HeadlessFlutterRunner.ENTRYPOINT`).
/// It must stay in this library: the engine looks it up in the app's main
/// library, and `vm:entry-point` keeps release builds from tree-shaking it.
@pragma('vm:entry-point')
Future<void> syncMain(List<String> args) => runHeadlessSync(args);
```

`test/widget_test.dart` builds `TMinusApp` itself and never calls `main()`, so it is unaffected.

- [ ] **Step 6: Run the Dart tests to verify they pass**

Run: `dart format lib/core/sync lib/app lib/main.dart test/core/sync test/app`
Run: `flutter test test/core/sync/foreground_sync_test.dart test/app/di_test.dart`
Expected: `All tests passed!` (4 + 5 tests).

- [ ] **Step 7: Implement the Kotlin runner**

`sync/HeadlessFlutterRunner.kt`:

```kotlin
package io.github.fifothehein.tminus.sync

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.github.fifothehein.tminus.engine.AlarmEngineChannel

/**
 * Boots a FlutterEngine without a UI and runs Dart `syncMain(trigger)` in it (spec §3, §7). The
 * engine gets its own `alarm_engine` and `tminus_sync` channels; `syncMain` reports its outcome
 * through `tminus_sync.finished`, and the engine is destroyed. Call [run] on the main thread.
 */
class HeadlessFlutterRunner(
    private val context: Context,
    private val timeoutMs: Long = TIMEOUT_MS,
) : SyncRunner {
    override fun run(trigger: String, done: (String) -> Unit): () -> Unit {
        val main = Handler(Looper.getMainLooper())
        val token = Any()
        var engine: FlutterEngine? = null
        var alarm: AlarmEngineChannel? = null
        var sync: SyncChannel? = null
        var finished = false

        fun finish(outcome: String) {
            if (finished) return
            finished = true
            main.removeCallbacksAndMessages(token)
            alarm?.detach()
            sync?.detach()
            engine?.destroy()
            engine = null
            Log.i(TAG, "Headless sync ($trigger) finished: $outcome")
            done(outcome)
        }

        try {
            val e = FlutterEngine(context) // starts the Flutter loader and registers the plugins
            engine = e
            val messenger = e.dartExecutor.binaryMessenger
            alarm = AlarmEngineChannel.register(messenger, context)
            sync = SyncChannel.register(messenger, context) { outcome -> main.post { finish(outcome) } }
            val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(bundle, ENTRYPOINT), listOf(trigger))
            main.postAtTime({ finish(SyncWorker.OUTCOME_RETRY) }, token, SystemClock.uptimeMillis() + timeoutMs)
        } catch (e: Exception) {
            Log.e(TAG, "Headless sync ($trigger) could not start", e)
            finish(SyncWorker.OUTCOME_RETRY)
        }
        return { main.post { finish(SyncWorker.OUTCOME_RETRY) } }
    }

    companion object {
        /** The `@pragma('vm:entry-point')` function in lib/main.dart. */
        const val ENTRYPOINT = "syncMain"

        /** WorkManager stops a worker after 10 min; give up well before. */
        const val TIMEOUT_MS = 8 * 60 * 1000L
        private const val TAG = "TMinusSync"
    }
}
```

In `sync/SyncWorker.kt`, after the class header's closing `) : ListenableWorker(context, params) {` add:

```kotlin
    /** The constructor WorkManager's default factory calls. */
    constructor(context: Context, params: WorkerParameters) :
        this(context, params, HeadlessFlutterRunner(context.applicationContext))

```

Robolectric cannot load the Flutter engine, so the runner has no unit test. Step 9 runs it on a device, and the Task 8 tests cover the worker around it with a fake runner.

- [ ] **Step 8: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`; full Kotlin unit tests → `BUILD SUCCESSFUL`; `flutter build apk --debug` → `√ Built ...app-debug.apk`.

- [ ] **Step 9: Smoke-test the headless sync on a device**

With the reference emulator (API 36, see Task 15) or a phone connected:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
adb shell monkey -p io.github.fifothehein.tminus -c android.intent.category.LAUNCHER 1
```

Wait about 20 s, then run `adb logcat -d -s TMinusSync:* WM-WorkerWrapper:*`. Expected: the periodic work starts at once, because it is new and the emulator has a network. You should see `Starting work for io.github.fifothehein.tminus.sync.SyncWorker`, then `TMinusSync: Headless sync (periodic) finished: ok` a few seconds later, then `Worker result SUCCESS`. (Checked while planning, on an API 36 emulator: about 3 s from worker start to `ok`.)

- [ ] **Step 10: Commit**

```bash
git add android/app/src/main/kotlin/io/github/fifothehein/tminus/sync lib/core/sync/foreground_sync.dart lib/app/sync_main.dart lib/app/di.dart lib/main.dart test/core/sync/foreground_sync_test.dart test/app/di_test.dart
git commit -m "Run syncs in a headless Flutter engine from WorkManager and on app foreground"
```

---

### Task 14: Debug sync panel, and the engine panel's drain through the recorder

**Files:**
- Create: `lib/features/token_preview/sync_debug_panel.dart`
- Modify: `lib/features/token_preview/token_preview_screen.dart` (import; section 07)
- Modify: `lib/features/token_preview/engine_debug_panel.dart` (`_drain`)
- Modify: `test/features/token_preview/engine_debug_panel_test.dart` (in-memory database)
- Test: `test/features/token_preview/sync_debug_panel_test.dart`

**Interfaces:**
- Consumes: `SyncService.run`, `SyncTrigger.debug`, `SyncReport`, `SyncRunOutcome` (Task 11); `FastAlarms` (Task 12); `SourceAdmin`, `IcsUrlException` (Task 12); `DeviceCalendarApi` (Task 5); `SyncPlatform.requestSync` (Task 10); `EngineEventRecorder.drainNow` (Task 6); `AlertHistoryRepository.recent`, `SourceRepository.all` (Plan 2); `SyncOutcomeSeverity` (Task 1).
- Produces: `class SyncDebugPanel extends StatefulWidget` (key `syncDebugPanel`), shown under "07 · Sync (debug)" only when `kDebugMode`, with `static String describe(SyncReport r)` (e.g. `6 alerts planned · armed 4, kept 0, cancelled 0 · 1 missed (system) · work: networkError`, or `Another sync is running`). Buttons (decision 23): **Fast alarms**, **Clear fast alarms**, **Sync now**, **Background sync**, **History** (counts of the newest 20 `alert_history` rows by type), an **ICS link (debug)** field with **Add feed** (source name `Debug`), **Add phone calendar** (first visible calendar), **Remove all sources**.

The engine panel (Plan 3 Task 14) has a **Drain events** button that calls `AlarmEngine.drainEvents()` itself. That makes it a second consumer: it can take queued events before the recorder sees them, and those events never reach `alert_history`. This task sends that button through `EngineEventRecorder.drainNow()`. The panel's live `events` listener stays: the stream is broadcast, so listening takes nothing from the recorder.

- [ ] **Step 1: Write the failing test**

`test/features/token_preview/sync_debug_panel_test.dart`. Drift runs on real async I/O, so `tapAndWait` lets the tap's sync finish inside `runAsync`. `path_provider` has no platform side in widget tests, so the feed cache is re-registered on a temporary directory:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/app/di.dart';
import 'package:tminus/app/theme/tminus_theme.dart';
import 'package:tminus/core/engine/alarm_engine.dart';
import 'package:tminus/core/model/alert_history_entry.dart';
import 'package:tminus/core/model/sync_log_entry.dart';
import 'package:tminus/core/sources/fast_alarms.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';
import 'package:tminus/core/storage/alert_history_repository.dart';
import 'package:tminus/core/storage/source_repository.dart';
import 'package:tminus/core/sync/sync_platform.dart';
import 'package:tminus/core/sync/sync_service.dart';
import 'package:tminus/features/token_preview/sync_debug_panel.dart';

import '../../core/storage/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engine = MethodChannel(AlarmEngine.methodChannelName);
  const sync = MethodChannel(SyncPlatform.channelName);
  final syncCalls = <MethodCall>[];
  late List<Map<Object?, Object?>> applied;
  late Directory feeds;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    configureDependencies(openDatabase: openTestDatabase);
    // path_provider has no platform side in widget tests.
    feeds = Directory.systemTemp.createTempSync('feeds');
    getIt.unregister<FeedBodyCache>();
    getIt.registerSingleton(FeedBodyCache(() async => feeds));
    applied = [];
    messenger.setMockMethodCallHandler(engine, (call) async {
      switch (call.method) {
        case 'applyPlan':
          applied = ((call.arguments as Map)['alerts'] as List)
              .cast<Map<Object?, Object?>>();
          return {'armed': applied.length, 'cancelled': 0, 'kept': 0};
        case 'drainEvents':
          return <Object?>[];
        case 'queryDeviceCalendars':
          return [
            {
              'id': '3',
              'name': 'Work',
              'accountName': null,
              'color': 0xFF33AA66,
              'visible': true,
            },
          ];
        case 'queryInstances':
          return <Object?>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(sync, (call) async {
      syncCalls.add(call);
      return switch (call.method) {
        'acquireLock' => true,
        'deviceZone' => 'UTC',
        _ => null,
      };
    });
  });

  tearDown(() async {
    syncCalls.clear();
    messenger.setMockMethodCallHandler(engine, null);
    messenger.setMockMethodCallHandler(sync, null);
    await getIt.reset();
    feeds.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TMinusTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(child: SyncDebugPanel()),
        ),
      ),
    );
  }

  /// Taps [label] and lets the sync run on real async I/O (drift) until the
  /// panel's buttons are enabled again.
  Future<void> tapAndWait(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 300; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        final syncNow = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Sync now'),
        );
        if (syncNow.onPressed != null) return;
      }
    });
    await tester.pump();
  }

  testWidgets(
    'Fast alarms adds the debug source and syncs it into the engine',
    (tester) async {
      await pumpPanel(tester);
      await tapAndWait(tester, 'Fast alarms');

      // Meeting profile: heads-up and alarm for each of the three events.
      expect(applied, hasLength(6));
      expect(
        find.textContaining('Fast alarms added · 6 alerts planned'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(
          () => getIt<SourceRepository>().byId(FastAlarms.sourceId),
        ),
        isNotNull,
      );

      await tapAndWait(tester, 'Clear fast alarms');
      expect(applied, isEmpty);
      expect(
        find.textContaining('Fast alarms cleared · 0 alerts planned'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Background sync asks WorkManager for a headless run', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tapAndWait(tester, 'Background sync');
    expect(syncCalls.where((c) => c.method == 'requestSync').single.arguments, {
      'trigger': 'manual',
    });
    expect(
      find.text('Background sync queued (headless engine)'),
      findsOneWidget,
    );
  });

  testWidgets('a pasted link and the first phone calendar become sources', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.enterText(
      find.byKey(const Key('icsLinkField')),
      'calendar.html',
    );
    await tapAndWait(tester, 'Add feed');
    expect(find.textContaining('That is not a calendar link'), findsOneWidget);

    await tapAndWait(tester, 'Add phone calendar');
    expect(
      find.textContaining('Added Work · 0 alerts planned'),
      findsOneWidget,
    );

    await tapAndWait(tester, 'Remove all sources');
    expect(find.textContaining('Removed 1 sources'), findsOneWidget);
  });

  testWidgets('History counts the newest rows by type', (tester) async {
    await pumpPanel(tester);
    await tapAndWait(tester, 'History');
    expect(find.text('No alert history yet'), findsOneWidget);

    await tester.runAsync(() async {
      for (final (i, type) in [
        AlertEventType.fired,
        AlertEventType.missedSystem,
        AlertEventType.missedSystem,
      ].indexed) {
        await getIt<AlertHistoryRepository>().record(
          AlertHistoryEntry(
            type: type,
            alertId: 'a$i',
            occurrenceKey: 'k',
            startUtc: DateTime.utc(2026, 10, 6, 8),
            atUtc: DateTime.utc(2026, 10, 6, 7, 59, i),
          ),
        );
      }
    });
    await tapAndWait(tester, 'History');
    expect(
      find.text('Last 3 history rows: missedSystem 2, fired 1'),
      findsOneWidget,
    );
  });

  test('describe sums up a run in one line', () {
    expect(
      SyncDebugPanel.describe(
        const SyncReport(
          trigger: SyncTrigger.debug,
          outcome: SyncRunOutcome.busy,
        ),
      ),
      'Another sync is running',
    );
    expect(
      SyncDebugPanel.describe(
        const SyncReport(
          trigger: SyncTrigger.debug,
          outcome: SyncRunOutcome.retry,
          sources: [SourceSyncResult('work', SyncOutcome.networkError)],
          applied: ApplyResult(armed: 2, cancelled: 1, kept: 3),
          planned: 5,
          missedSystem: 1,
        ),
      ),
      '5 alerts planned · armed 2, kept 3, cancelled 1 · 1 missed (system) · work: networkError',
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/token_preview/sync_debug_panel_test.dart`
Expected: compilation fails, `Error when reading 'lib/features/token_preview/sync_debug_panel.dart'`.

- [ ] **Step 3: Implement `lib/features/token_preview/sync_debug_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../core/sources/device_calendar_api.dart';
import '../../core/sources/fast_alarms.dart';
import '../../core/sources/source_admin.dart';
import '../../core/storage/alert_history_repository.dart';
import '../../core/storage/source_repository.dart';
import '../../core/sync/outcome_severity.dart';
import '../../core/sync/sync_platform.dart';
import '../../core/sync/sync_service.dart';

/// Debug-only sync controls (spec §11 "fast alarms"), so Plan 4 can be tried
/// on a device before the Sources and Health screens (Plan 5) exist: fast
/// alarms, a pasted ICS link, the first phone calendar, and sync buttons.
class SyncDebugPanel extends StatefulWidget {
  const SyncDebugPanel({super.key = const Key('syncDebugPanel')});

  /// One line per run, e.g. `6 alerts planned · armed 4, kept 0, cancelled 0`.
  static String describe(SyncReport r) {
    if (r.outcome == SyncRunOutcome.busy) return 'Another sync is running';
    final applied = r.applied;
    final problems = [
      for (final s in r.sources)
        if (s.outcome.severity != OutcomeSeverity.ok)
          '${s.sourceId}: ${s.outcome.name}',
    ];
    return [
      '${r.planned} alerts planned',
      applied == null
          ? 'applyPlan failed'
          : 'armed ${applied.armed}, kept ${applied.kept}, cancelled ${applied.cancelled}',
      if (r.missedSystem > 0) '${r.missedSystem} missed (system)',
      ...problems,
    ].join(' · ');
  }

  @override
  State<SyncDebugPanel> createState() => _SyncDebugPanelState();
}

class _SyncDebugPanelState extends State<SyncDebugPanel> {
  final _link = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    String status;
    try {
      status = await action();
    } on PlatformException catch (e) {
      status = 'Failed: ${e.message ?? e.code}';
    } on MissingPluginException {
      status = 'Sync not available on this platform';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
  }

  Future<String> _sync() async => SyncDebugPanel.describe(
    await getIt<SyncService>().run(SyncTrigger.debug),
  );

  Future<String> _fastAlarms() async {
    await getIt<FastAlarms>().create(DateTime.now().toUtc());
    return 'Fast alarms added · ${await _sync()}';
  }

  Future<String> _clearFastAlarms() async {
    await getIt<FastAlarms>().clear();
    return 'Fast alarms cleared · ${await _sync()}';
  }

  Future<String> _addFeed() async {
    try {
      final added = await getIt<SourceAdmin>().addIcsSource(
        name: 'Debug',
        color: 0xFF6AA0F5,
        url: _link.text,
      );
      _link.clear();
      final warning = added.insecure ? ' (http: not encrypted)' : '';
      return 'Feed added$warning · ${await _sync()}';
    } on IcsUrlException catch (e) {
      return e.message;
    }
  }

  Future<String> _addPhoneCalendar() async {
    final List<DeviceCalendar> calendars;
    try {
      calendars = await getIt<DeviceCalendarApi>().calendars();
    } on PlatformException catch (e) {
      if (e.code != DeviceCalendarApi.permissionDenied) rethrow;
      return 'Calendar access not granted: adb shell pm grant '
          'io.github.fifothehein.tminus android.permission.READ_CALENDAR';
    }
    final visible = calendars.where((c) => c.visible).toList();
    if (visible.isEmpty) return 'No phone calendars';
    final source = await getIt<SourceAdmin>().addDeviceSource(
      calendar: visible.first,
    );
    return 'Added ${source.name} · ${await _sync()}';
  }

  Future<String> _removeAll() async {
    final all = await getIt<SourceRepository>().all();
    for (final s in all) {
      await getIt<SourceAdmin>().delete(s.id);
    }
    return 'Removed ${all.length} sources · ${await _sync()}';
  }

  /// Counts by type over the newest rows, e.g. after a force stop:
  /// `Last 5 history rows: missedSystem 3, fired 2`.
  Future<String> _history() async {
    final recent = await getIt<AlertHistoryRepository>().recent(limit: 20);
    if (recent.isEmpty) return 'No alert history yet';
    final counts = <String, int>{};
    for (final e in recent) {
      counts.update(e.type.name, (n) => n + 1, ifAbsent: () => 1);
    }
    final parts = [for (final c in counts.entries) '${c.key} ${c.value}'];
    return 'Last ${recent.length} history rows: ${parts.join(', ')}';
  }

  Future<String> _background() async {
    await getIt<SyncPlatform>().requestSync(SyncTrigger.manual.name);
    return 'Background sync queued (headless engine)';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: enabled ? () => _run(_fastAlarms) : null,
              child: const Text('Fast alarms'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => _run(_clearFastAlarms) : null,
              child: const Text('Clear fast alarms'),
            ),
            FilledButton.tonal(
              onPressed: enabled ? () => _run(_sync) : null,
              child: const Text('Sync now'),
            ),
            TextButton(
              onPressed: enabled ? () => _run(_background) : null,
              child: const Text('Background sync'),
            ),
            TextButton(
              onPressed: enabled ? () => _run(_history) : null,
              child: const Text('History'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('icsLinkField'),
          controller: _link,
          decoration: const InputDecoration(
            labelText: 'ICS link (debug)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: enabled ? () => _run(_addFeed) : null,
              child: const Text('Add feed'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => _run(_addPhoneCalendar) : null,
              child: const Text('Add phone calendar'),
            ),
            TextButton(
              onPressed: enabled ? () => _run(_removeAll) : null,
              child: const Text('Remove all sources'),
            ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: textTheme.bodySmall),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Show it on the token preview screen**

In `lib/features/token_preview/token_preview_screen.dart`, after `import 'engine_debug_panel.dart';` add:

```dart
import 'sync_debug_panel.dart';
```

and replace

```dart
            const _SectionLabel('06 · Engine (debug)'),
            const EngineDebugPanel(),
          ],
```

with

```dart
            const _SectionLabel('06 · Engine (debug)'),
            const EngineDebugPanel(),
            const _SectionLabel('07 · Sync (debug)'),
            const SyncDebugPanel(),
          ],
```

(`test/widget_test.dart` builds this screen with `kDebugMode` true. The panel touches no service until a button is tapped, so that test needs no database.)

- [ ] **Step 5: Drain through the recorder in the engine panel**

In `lib/features/token_preview/engine_debug_panel.dart`, after `import '../../core/model/alert.dart';` add:

```dart
import '../../core/sync/engine_event_recorder.dart';
```

and replace

```dart
  Future<String> _drain() async {
    final drained = await _engine.drainEvents();
    final events = [..._pending, ...drained];
    _pending.clear();
    if (events.isEmpty) return 'No new engine events';
    return 'Drained ${events.length}: ${events.map((e) => e.type.name).join(', ')}';
  }
```

with

```dart
  /// Drains through the recorder, the one caller of `drainEvents` (Plan 4),
  /// so what the panel drains still reaches `alert_history`.
  Future<String> _drain() async {
    final recorded = await getIt<EngineEventRecorder>().drainNow();
    final types = [
      for (final e in _pending) e.type.name,
      for (final e in recorded) e.type.name,
    ];
    _pending.clear();
    if (types.isEmpty) return 'No new engine events';
    return 'Drained ${types.length}: ${types.join(', ')}';
  }
```

In `test/features/token_preview/engine_debug_panel_test.dart`, after `import 'package:tminus/features/token_preview/engine_debug_panel.dart';` add:

```dart

import '../../core/storage/test_database.dart';
```

and in `setUp`, replace `configureDependencies();` with:

```dart
    // Drain events records through EngineEventRecorder into the database.
    configureDependencies(openDatabase: openTestDatabase);
```

The panel's existing tests then pass unchanged: "Drained 1: fired" now comes from the recorder's newly recorded row.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `dart format lib/features test/features`
Run: `flutter test test/features test/widget_test.dart`
Expected: `All tests passed!` (5 new panel tests; the engine panel and widget tests unchanged).

- [ ] **Step 7: Run the gates**

`flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`. No Kotlin changed.

- [ ] **Step 8: Commit**

```bash
git add lib/features/token_preview test/features/token_preview
git commit -m "Add debug sync controls and drain engine events only through the recorder"
```

---

### Task 15: Manual device verification

**Files:** none changed. Record results in the PR description: device (AVD name, API level and image, or phone model), Android version, and pass/fail per step.

**Reference device:** the API 36 Google APIs emulator from Plan 3 Task 15, with its PIN. Steps 1–5 were run while planning on that emulator and behaved as written.

Setup, once (Git Bash, repo root). `MSYS_NO_PATHCONV=1` stops Git Bash from rewriting `/sdcard/...` and `content://` arguments:

```bash
export MSYS_NO_PATHCONV=1
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant io.github.fifothehein.tminus android.permission.POST_NOTIFICATIONS
adb shell pm grant io.github.fifothehein.tminus android.permission.READ_CALENDAR
```

Useful while testing: `adb logcat -s TMinusSync:* TMinusEngine:* WM-WorkerWrapper:*` (sync lines, e.g. `Headless sync (calendarChange) finished: ok`), `adb shell dumpsys alarm | grep -A2 PRE_SYNC` (the pre-alarm sync alarm), and `adb shell dumpsys alarm | grep -c tminus.action.FIRE` (armed alerts). The debug panels are at the bottom of the home screen: scroll to "07 · Sync (debug)".

- [ ] **Step 1: Headless sync on first start**

`adb logcat -c`, then launch the app (`adb shell monkey -p io.github.fifothehein.tminus -c android.intent.category.LAUNCHER 1`). Expected within ~20 s: `Starting work for io.github.fifothehein.tminus.sync.SyncWorker`, `TMinusSync: Headless sync (periodic) finished: ok`, `Worker result SUCCESS`. Then tap **Background sync**: the same lines with `(manual)`.

- [ ] **Step 2: Fast alarms end to end**

Tap **Fast alarms**. The status reads `Fast alarms added · 6 alerts planned · armed 4, kept 0, cancelled 0`. The two +2 min heads-ups are already past, so they are listed but not armed. At +1 min the coalesced alarm rings, full-screen, "2 meetings starting": press **Dismiss all**. At +2 min a heads-up for "Fast alarm: Teams call" appears with **Join · Snooze · Dismiss all**: press **Dismiss all**, then **Sync now**. "Next 5 scheduled" (engine panel, **Refresh**) no longer lists the Teams call's +11 min alarm, and **History** counts `dismissedAll 2` among the rows. Finish with **Clear fast alarms**.

- [ ] **Step 3: Missed (system) after a force stop**

Tap **Fast alarms**, then at once `adb shell am force-stop io.github.fifothehein.tminus`. Wait 4 minutes, then launch the app. The overdue alerts ring now (Plan 3: overdue alerts ring if their event has not ended); stop them with a volume key. Scroll to the panel and tap **History**: it counts `missedSystem 3` (the two +1 min alarms and the +2 min heads-up). The foreground sync at launch recorded them, because the last sync was more than 2 min earlier. **Clear fast alarms**.

- [ ] **Step 4: Phone calendar, calendar-change sync and pre-alarm sync**

Create a local calendar and an event 30 min ahead:

```bash
adb shell "content insert --uri 'content://com.android.calendar/calendars?caller_is_syncadapter=true&account_name=tminus-test&account_type=LOCAL' --bind account_name:s:tminus-test --bind account_type:s:LOCAL --bind name:s:TMinusTest --bind calendar_displayName:s:TMinusTest --bind calendar_color:i:-11493898 --bind calendar_access_level:i:700 --bind ownerAccount:s:tminus-test --bind visible:i:1 --bind sync_events:i:1"
adb shell content query --uri content://com.android.calendar/calendars --projection _id:calendar_displayName
START=$(( $(date +%s) * 1000 + 30*60*1000 ))
adb shell "content insert --uri content://com.android.calendar/events --bind calendar_id:i:<id> --bind title:s:DeviceTest --bind dtstart:l:$START --bind dtend:l:$(( START + 1800000 )) --bind eventTimezone:s:UTC --bind availability:i:0"
```

(Use the `_id` the query printed for `<id>`, and the event's `_id` below; on a fresh emulator both are 1.) Tap **Add phone calendar**: `Added TMinusTest · 2 alerts planned …`. `dumpsys alarm | grep -A2 PRE_SYNC` shows an exact alarm (`exactAllowReason=policy_permission`) at the event's start − 10 min − 12 min.

Move the event: `adb shell "content update --uri content://com.android.calendar/events/<event id> --bind dtstart:l:<start + 10 min> --bind dtend:l:<end + 10 min>"`. Within ~30 s logcat shows `CalendarWatchWorker`, then `Headless sync (calendarChange) finished: ok`, and the PRE_SYNC alarm has moved by 10 min.

Move it again so that start − 22 min is about one minute away. At that time logcat shows `Starting work for … SyncWorker` and `Headless sync (preAlarm) finished: ok`.

- [ ] **Step 5: A removed calendar is reported once**

```bash
adb shell "content delete --uri 'content://com.android.calendar/calendars/<id>?caller_is_syncadapter=true&account_name=tminus-test&account_type=LOCAL'"
```

Within ~30 s a calendar-change sync runs and a notification "TMinusTest: calendar was removed" appears (`adb shell dumpsys notification --noredact | grep android.title`). Tap **Sync now** twice more: no second notification. Its **Fix** action opens the app. Tap **Remove all sources**.

- [ ] **Step 6: The real Outlook feed (spec §12 checks 2 and 3)**

Paste the published `.ics` link into **ICS link (debug)** and tap **Add feed**. Expected: `Feed added · N alerts planned …` with no source problem listed, and "Next 5 scheduled" shows real meetings at their local times. If a meeting has a Teams link, its heads-up shows **Join** (spec §12 check 3). Tap **Sync now** again: the status shows no problem for `Debug`. A 304 re-expands the stored body; the sync log records `notModified`. Then move a meeting in Outlook and tap **Sync now** every few minutes. Note how long the feed takes to show the new time; that is spec §12 check 2, "published-feed latency".

- [ ] **Step 7: A broken feed**

Tap **Remove all sources**. Paste `https://example.com/tminus-missing/calendar.ics` (it answers 404) and tap **Add feed**. Expected: the status lists `…: httpError`, and one "Debug feed link stopped working" notification appears with **Fix**. A second **Sync now** posts no second notification.

**Remove all sources**, then paste an unknown Outlook link: `https://outlook.office365.com/owa/calendar/00000000000000000000000000000000@example.com/0000000000000000000000000000000000/calendar.ics`. While planning, `package:http` saw HTTP 500 for it. Expected: `…: serverError`, amber, with no notification for the first 24 h (decision 24). If you can, also reset the published link in Outlook (Settings → Calendar → Shared calendars → reset links) and record what the old link returns. That shows whether decision 24's escalation or spec §9's 401/403/404 row is what catches it.

Finally paste a link ending in `.html`: the status reads "That is the web page link. Copy the link that ends in .ics instead." Then **Remove all sources**.

- [ ] **Step 8: Feed stale (optional, takes over an hour)**

Add the real feed (Step 6) when a meeting with an alert is 1–3 h away. Then turn on airplane mode: `adb shell cmd connectivity airplane-mode enable`. After 61 minutes, tap **Sync now**: a "Calendar hasn't synced for 1 h — alarms may be outdated" notification for `Debug` appears, with **Sync now**. Turn airplane mode off and tap **Sync now**: the notification is withdrawn. If this step is skipped, record "covered by Task 11 tests".

- [ ] **Step 9: Reboot keeps the pre-alarm sync**

With the Step 4 calendar and event in place (recreate them if needed, and **Add phone calendar**), run `adb reboot`, wait for boot, and unlock with the PIN. `dumpsys alarm | grep -A2 PRE_SYNC` lists the alarm again (`SyncBootReceiver` on `BOOT_COMPLETED`). Clean up with Step 5's delete and **Remove all sources**.

- [ ] **Step 10: Record the results**

Write one line per step (pass/fail, device, Android version) into the PR description. Any failure becomes a bug task before Plan 5 starts.

---

## Self-review

**Spec coverage** (§5, §7 sync triggers and pre-alarm sync, §9, §10, §11; roadmap Plan 4 row):
- `CalendarSource`, window now − 1 h to + 7 days: Task 1. `IcsFeedSource`: URL in secure storage, name, colour, conditional GET, 20 s timeout, `.ics` only: Tasks 2, 3, 12. `DeviceCalendarSource` over `CalendarContract.Instances`, `AVAILABILITY`, `SELF_ATTENDEE_STATUS`, `READ_CALENDAR` only for device sources: Tasks 4, 5 (the request itself is Plan 5's, decision 16). Roadmap §2 mapping (`seriesUid`, `tzFallback`, `cancelled`/`declined` false): Task 1.
- `SyncWorker` + headless `syncMain()`: Tasks 8, 13. Sync triggers: periodic 15 min with a network (Task 8, `MainActivity` in Task 9). Content-URI trigger on `Events.CONTENT_URI`, re-enqueued after each run, device sources only (Task 8; `configure` in Task 11). Pre-alarm sync, 12 min before each occurrence's earliest alert, expedited, failure leaves the alert to fire with the data it has (Tasks 7, 8, 11). App foreground in the UI isolate (Task 13); pull-to-refresh calls `SyncService.run` (Plan 5). `syncMain()` = fetch → cache → rules → plan → `applyPlan` → log: Task 11.
- §9 table. Network/5xx/timeout keep data, amber, retry with backoff: Tasks 1, 3, 8 (`resultFor`), 11. 5xx for 24 h with no success → broken (decision 24): Task 11. 401/403/404 red with one notification, alarms kept: Tasks 3, 9, 11. Whole feed won't parse keeps occurrences, red: Tasks 3, 11. One event won't parse is skipped and logged: `ics_core` issues → `SourceFetched.issues` → the sync-log message (Tasks 3, 11). Empty-feed guard: Task 11. Unknown TZID → ⚠: `tzFallback` mapping (Task 1). Missed (system): Tasks 7, 11. `applyPlan` failure keeps the old plan and retries: Task 11. Feed stale > 60 min with an alert due within 2 h: Task 11 (notification Task 9). Force stop → re-arm on start: Plan 3, plus the pre-sync alarm in Task 9.
- §10: URLs in secure storage, masked (`IcsUrl.mask` for Plan 5), never in logs or messages: Tasks 2, 3, 12. Export without links is Plan 5's.
- §11 fast alarms: Tasks 12, 14, 15.
- Plan 3 decisions respected: the plan keeps alerts until 15 min after the end (planning from `now − keepAfterEnd`, Task 11). One event consumer (Tasks 6, 14). Headless engine with its own `EngineEvents` listener (Task 13). Boot recovery at 30 s and overdue/orphaned alerts are untouched (Task 15 Step 3 relies on the overdue rule). `ringingChannelEnabled` is untouched. Pruning of Kotlin acks happens in `applyPlan`, which every sync calls.

**Placeholder scan:** no "TBD", "TODO" or "similar to Task N". Every code step embeds the file as it was compiled and run while planning, or gives the exact text of an edit. The `<id>` and `<event id>` in Task 15 are values an emulator prints, with the command that prints them.

**Type consistency:** checked across tasks. `SourceResult` / `SourceFetched(occurrences, issues, notModified, httpEtag, httpLastModified)` / `SourceFailed(outcome, message)` are used the same way in Tasks 3, 5, 11 and 12. `SourceBuilder` (Task 11) matches `SourceFactory.create(config, state, zone:)` in Task 13's DI. `EngineEventRecorder.drainNow()` returns `List<AlertHistoryEntry>` in Tasks 6, 11 and 14. Trigger names are the same in Kotlin (`SyncWorker.TRIGGER_*`) and Dart (`SyncTrigger`). Outcome names: `SyncRunOutcome.name` ↔ `SyncWorker.OUTCOME_*`. `tminus_sync` method names and argument keys are the same in `SyncChannel` (Task 9), `SyncPlatform` (Task 10) and `sync_platform_test`. Notice kinds `stale`/`broken` match `SyncNotifications.KIND_*`. `PreSyncScheduler.PREFS`, `SyncScheduler.nowName` and `CALENDAR_WATCH` are used the same way in Tasks 8 and 9.

**Verification while planning:** the whole plan was built and run before it was written down. `flutter analyze` was clean; `flutter test` and the full Kotlin unit suite passed. On the API 36 emulator: periodic, manual, calendar-change and pre-alarm headless syncs ran (`Headless sync (…) finished: ok`); the pre-alarm alarm was exact at start − first alert − 12 min; a moved phone event moved it; a removed calendar posted one "calendar was removed" notification; and a force stop produced `missedSystem 3`.
