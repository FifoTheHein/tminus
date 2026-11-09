# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

T-Minus is an Android-only meeting-alarm app. It turns Outlook/Teams calendars into alarms you can't miss and can always stop. It reads published ICS feeds and calendars already on the phone. The UI is Flutter (Dart); the alarm engine is native Kotlin (AlarmManager, a foreground service and a Compose alarm screen), so alarms ring without Flutter running.

- Spec: `docs/superpowers/specs/2026-10-06-tminus-design.md`. §13 covers meetings that appear in more than one source.
- Roadmap: `docs/superpowers/plans/2026-10-06-tminus-roadmap.md`. It lists Plans 1–6 and holds the shared contracts (§2 is the `ics_core` API, §3 is `PlannedAlert`), plus the Plan 6 (Play readiness) decisions.
- Plans: `docs/superpowers/plans/`. Where a plan has a "Built differently from this plan" section, the code is authoritative and that section explains why.
- Design brief and mockups: `docs/design-brief.md` and `docs/design/`. The design system is already in `lib/app/theme/`.

Toolchain: Flutter 3.47, Dart 3.13, minSdk 26. compileSdk and targetSdk are 36, and **compileSdk must not be raised**. If `checkDebugAarMetadata` complains about compileSdk 37, a dependency newer than the pins in `android/app/build.gradle.kts` slipped in. Pin it back down; the comments there record why each version was chosen.

## Commands

From the repo root:

```bash
flutter pub get                                   # resolves the app and packages/ics_core together (pub workspace)
flutter analyze                                   # also analyses packages/ics_core; must report "No issues found!"
flutter test                                      # app tests under test/ only (not ics_core's)
flutter test test/core/sync/sync_service_test.dart
flutter test test/core/rules/rules_engine_test.dart --plain-name "some test name"
flutter build apk --debug
dart run build_runner build                       # drift codegen; --delete-conflicting-outputs no longer exists in build_runner 2.16
```

`ics_core` (pure Dart, run inside `packages/ics_core`):

```bash
dart test
dart test test/expand_recurring_test.dart
dart analyze
dart run tool/gen_windows_zones.dart              # regenerates lib/src/zones/windows_zones.g.dart from CLDR
dart run tool/scrub_feed.dart <raw.ics> <scrubbed.ics>   # turns a real feed into a committable fixture
```

Kotlin (Robolectric unit tests, run inside `android/`):

```bash
./gradlew :app:testDebugUnitTest
./gradlew :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.engine.EngineReducerTest"
./gradlew :app:connectedDebugAndroidTest          # instrumented tests (re-arm receivers), needs a device or emulator
```

Use `.\gradlew.bat` in PowerShell. `gradlew`, `gradlew.bat`, `local.properties` and `gradle/wrapper/gradle-wrapper.jar` are git-ignored, so a new worktree has to copy them from the main checkout's `android/`. Robolectric is pinned to SDK 34 (`android/app/src/test/resources/robolectric.properties`), so the tests run the same way on JDK 17 and 21. Run only one Gradle build at a time.

Drift schema changes: bump `schemaVersion` in `lib/core/storage/app_database.dart` and add a new `if (from < N)` step in `onUpgrade`. Never edit a step that has shipped. Dump the **old** schema before you touch `tables.dart`, then dump the new one and regenerate the migration test helpers:

```bash
dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

Generated `*.g.dart` files are committed, so schema changes show up in review.

## Rules that are easy to break

- `lib/core/model/alert.dart` and `lib/core/model/planned_alert.dart` are the Dart↔Kotlin contract from roadmap §3, byte for byte. **Never edit them and never `dart format` them**, because formatting rewraps their lines. `test/core/model/planned_alert_contract_test.dart` checks them. So run `dart format` on the files you changed, never on `lib/` as a whole.
- **Never log error messages, URLs or event content.** Log `e.runtimeType`, or a `PlatformException`'s code, only. Feed links carry secret tokens (iCloud puts them in the path), and error messages can quote a link or a row's values. The one exception is `IcsFeedSource._logFailure`: it compares a `ClientException`'s message with a fixed list of known dart:io texts and logs only its own label for the match, never the message. `IcsUrl.mask` is the only way to show a link.
- ICS links live in `flutter_secure_storage` (`SourceSecrets`), never in the drift database.
- Load `package:timezone`'s `latest_all` data, not `latest`. CLDR maps some Windows zones to old link names such as `Asia/Calcutta`.
- Colour tokens are duplicated in `android/app/src/main/res/values/tminus_colors.xml` for the native alarm screen. `test/native_tokens_test.dart` fails if they drift apart from `lib/app/theme/`.
- Real calendar feeds stay out of git. Commit only scrubbed fixtures (see `scrub_feed.dart`); raw feeds belong in the git-ignored `packages/ics_core/test/fixtures/private/`.
- URL input fields need autocorrect and suggestions turned off. The Android keyboard otherwise rewrites `http://` to `https://`.
- App text never uses em dashes (U+2014): use a colon, a comma, a full stop or parentheses instead. This covers Dart strings, Kotlin strings and Android resources. `test/no_em_dash_test.dart` fails if one comes back.

## Architecture

The pipeline is: sources → occurrence cache → rules → planner → native engine.

1. **`packages/ics_core`** is pure Dart with no Flutter. `expandIcs(text, window, deviceZone)` parses a feed and expands RRULE, EXDATE and overrides into `IcsOccurrence`s inside a time window. It maps Windows TZIDs to IANA zones and isolates errors per VEVENT: a bad event becomes an `IcsIssue` and the rest of the feed still parses.
2. **`lib/core/sources/`**: each `CalendarSource` (`IcsFeedSource` or `DeviceCalendarSource`) fetches into a `SourceResult`. `IcsFeedSource` does a conditional GET and caches the last good body (`FeedBodyCache`). The device calendar is read natively by `DeviceCalendarReader.kt` over the `alarm_engine` channel. `fast_alarms.dart` is a debug-only source that creates meetings 1–2 minutes ahead.
3. **`lib/core/storage/`**: a drift database (`tables.dart`, `app_database.dart`) behind one repository class per table. `RuleSetLoader` assembles profiles, keyword rules, overrides and settings into a `RuleSet`.
4. **`lib/core/rules/`**: `RulesEngine` resolves each occurrence to an alert profile (spec §6 resolution order), applies quiet modes and produces the explanation text.
5. **`lib/core/planner/`**: `MeetingMerger` folds copies of the same meeting from different sources into one (spec §13; `meeting_links` keeps the keys sticky). `EmptyFeedGuard` stops a suddenly empty feed from wiping alarms. `buildPlan` turns the result into `PlannedAlert`s with stable ids.
6. **`lib/core/engine/alarm_engine.dart`** is the Dart client for the `alarm_engine` method and event channels: `applyPlan` and the engine events (fired, dismissed, snoozed, missed, and so on).
7. **Kotlin, `android/app/src/main/kotlin/io/github/fifothehein/tminus/`**:
   - `engine/`: `PlanStore` persists the plan as JSON in device-protected storage, so alarms work before the first unlock. `AlarmScheduler` diffs the stored plan against the new one and arms AlarmManager (`setAlarmClock` for alarms). `AlarmReceiver` starts `RingingService` (the foreground service), which shows `AlarmActivity` (Compose). `EngineReducer` is the pure state machine. `EventQueue` buffers engine events until Dart drains them. `BootReceiver` and `TimeChangeReceiver` re-arm from `PlanStore`.
   - `sync/`: `SyncWorker` (WorkManager) runs `HeadlessFlutterRunner`, which starts a headless Flutter engine at `syncMain`. `SyncChannel` is the `tminus_sync` channel (lock, notices, configure, finished). `PreSyncScheduler` schedules a sync shortly before each alarm.

**`SyncService.run(trigger)`** (`lib/core/sync/sync_service.dart`) ties it together. It takes the sync lock, reads the device zone, drains engine events into alert history (`EngineEventRecorder`), fetches all enabled sources in parallel and records each one's outcome, then plans, detects missed (system) alerts and calls `applyPlan`. It runs in two isolates:
- headless: `syncMain` in `lib/main.dart` → `runHeadlessSync` (`lib/app/sync_main.dart`). `syncMain` must stay in `main.dart` with `@pragma('vm:entry-point')`. It always reports an outcome through `tminus_sync.finished`, so the worker never waits for its timeout.
- UI: `main()` starts `EngineEventRecorder` (the only consumer of engine events in that isolate) and `ForegroundSync`.

If `applyPlan` fails, Kotlin keeps its previous plan and the run reports `retry`.

**DI** (`lib/app/di.dart`) is get_it, and everything is lazy. Tests call `configureDependencies(openDatabase: ...)` with an in-memory database (`test/core/storage/test_database.dart`), and `getIt.reset()` closes it. `RulesEngine` is registered as a factory because it captures `tz.local` when it is created.

Kotlin code is written to be testable without a device. Pure logic such as `EngineReducer`, `PlanDiff`, `Countdown` and `SnoozeOptions` is separate from the Android glue, and the Robolectric tests cover the receivers, services and channels.

## How work is run here

Every plan is built with `/orchestrate` in its lightweight form: one session directs the run with no gates and no fresh session per wave. `dev-worker`s build the tasks, `scout`s run every test and commit, a `review-worker` reviews each wave, and `deep-review` takes schema migrations and other high-risk jobs. Each new test has a negative control: revert the fix, confirm the test fails, then restore the fix. The tasks are grouped into waves by their dependencies, and tasks in the same wave never touch the same files. When a plan is built, record where the code differs from the plan in that plan's "Built differently" section.
