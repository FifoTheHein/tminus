# Plan 6: Play Readiness Implementation Plan

> **Execution: lightweight orchestrator, run locally.** This uses the orchestrate skill's agents (dev-worker, scout, review-worker, deep-review) and checks, with no Gate-0 stop, no fresh session per wave and no time booking. Waves follow dependencies. Tasks in one wave never share files, only one Gradle job runs at a time, each wave is committed, and every extra or fix test gets a negative control. Tasks marked **(user)** are done by the user in Play Console, in a browser or on the phone. The orchestrator tracks them and records their results; it does not do them.

**Goal:** A release build of T-Minus that is signed, tested and uploaded to the **Play internal testing** track, with every Play Console declaration filed, a public privacy policy whose claims are true of the code, and a store listing ready to publish. The plan also takes three follow-ups from the calendar-grouping work and moves the meeting cache out of Android's cloud backup, so the promise "Your calendar never leaves your phone" holds.

**Scope ends at internal testing** (roadmap, Plan 6 decision 1). The closed test (12 testers for 14 days, for personal accounts created after 2023-11-13) and the production release are a later step.

**Architecture of the changes:**
- **Ringing service type.** `RingingService` moves from `mediaPlayback` to `systemExempted` (Plan 6 decision 2).
- **Cache out of backup.** The three tables that a restore already throws away (`occurrences`, `alert_history`, `sync_log`) move into a second drift database, `tminus_cache.sqlite`. The backup rules do not list that file, so it is never backed up. Everything else stays in `tminus.sqlite`, which is still backed up.
- **Release build.** Signed with an upload key read from a git-ignored `android/key.properties`; Play App Signing holds the app signing key.
- **Public pages.** A privacy policy and a demo calendar feed for Play's reviewers, served by GitHub Pages from `docs/`.
- **Play paperwork.** Store listing copy and the answers for every declaration, kept in `docs/play/`.

**Tech stack:** Flutter 3.47, Dart 3.13, drift 2.35, Kotlin 2.4.0, androidx.core 1.18.0, Robolectric 4.17, all already in the repo. **No new Dart or Gradle dependency.** `tool/gen_feature_graphic.py` uses Pillow, as `tool/gen_launcher_icon.py` does.

**Spec:** `docs/superpowers/specs/2026-10-06-tminus-design.md` §2 (phase 1.5), §7 (permissions, FGS), §10 (security and privacy), §11 (manual device checklist). Grouping follow-ups: `docs/superpowers/specs/2026-11-13-calendar-grouping-design.md` §10. Binding: the roadmap's "Plan 6 decisions (agreed 2026-11-02…)" and "Changes merged after Plan 5", and roadmap §3 (`alarm_engine` contract; this plan adds one error code).

**Base:** `main` at `1d01901` (PR #22) or later. Plans 1–5, 4b and PRs #17–#22 are merged.

---

## Global Constraints

- Everything in CLAUDE.md applies, in particular:
  - never edit or `dart format` `lib/core/model/alert.dart` / `planned_alert.dart`;
  - `dart format` only the files you changed;
  - log `runtimeType` or a code, never a message, URL or event content;
  - no em dashes (U+2014) in app text;
  - compileSdk stays 36;
  - only one Gradle build at a time.
- **No secret enters git.** That means `android/key.properties`, any `*.jks` / `*.keystore`, any password, and the Play Console contact address. `android/.gitignore` already ignores the first two; Task 4 adds a test that fails if one is tracked.
- **Drift schema changes** follow CLAUDE.md: dump the **old** schema before touching tables, add an `if (from < 3)` step, never edit the `from < 2` step, then dump and regenerate the migration helpers. The new cache database gets its own schema folder (`drift_schemas/cache/`) and its own generated helpers (`test/generated_migrations/cache/`).
- **Alarms must never go silent because of this plan.** The cache move must not leave a moment in which a sync or an edit re-plan reads an empty cache while the old one still has meetings. An empty plan makes Kotlin cancel every alarm (roadmap §3, "an occurrenceKey absent from a plan means the meeting was cancelled").
- Public copy (privacy policy, store listing, declaration answers) follows the house style: plain sentences, no marketing superlatives, no em dashes. **Every factual claim must be true of the code at the commit it ships with.** Review Focus 3 checks this.
- **`SyncWorker` stays without a foreground-service type.** Its `ForegroundInfo` has no type, and it never calls `setForeground`. If a later change gives it a type or makes it long-running through `setForeground`, then `SystemForegroundService` needs that type in the manifest, the matching `FOREGROUND_SERVICE_<TYPE>` permission and its own Play Console declaration. On targetSdk 34+, an untyped foreground start on API 34+ throws.
- Gates at the end of **every** task, from the repo root:
  - `flutter analyze` → `No issues found!`
  - `flutter test` → `All tests passed!`
  - if any Kotlin, manifest or resource changed: `cd android && ./gradlew :app:testDebugUnitTest` → `BUILD SUCCESSFUL`
- Commit messages are one imperative, sentence-case line with no prefix.
- **Deep review** is required for Tasks 2, 3, 4 and 6: alarm delivery, the database, signing and the sync path.

## Review Focus

1. **The cache move loses no alarm.** On the first Plan 6 start of a phone with cached meetings, the Agenda and the next plan must hold exactly the meetings the Plan 5 build had, offline too. Expected: the legacy rows are copied into `tminus_cache.sqlite` before anything can read the cache, and are dropped from `tminus.sqlite` only after the copy committed. Pinned by Task 3 (`an upgraded database keeps every cached meeting and the plan is unchanged`, `a move interrupted after the copy finishes on the next open`, `two isolates opening at once copy once`) and Task 12 Step 3.
2. **The ringing service starts on every supported Android version.** `systemExempted` exists only from API 34, and the manifest type is new. Expected: API 34+ starts the service with `FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED`; API 26–33 start it without a type argument, so the platform uses the manifest's declaration. Pinned by Task 2's Robolectric tests on SDK 34 and 33, and by Task 11's emulator runs on API 26, 30, 33, 35 and 36.
3. **The privacy policy is true.** Expected:
   - no event content and no link is in any backed-up file (Task 3, Task 4's `BackupRulesTest`);
   - the only network traffic is the calendar fetches the user configured, plus the browser or Teams opening a join link or the policy page;
   - no analytics, ads or crash-reporting SDK is in the merged release manifest or `pubspec.lock` (Task 4 Step 5).
   Task 10's reviewer checks each sentence of `docs/privacy.md` against these.
4. **The release build behaves like the debug build.** R8 shrinks the release build, and debug-only code is gone from it. Expected: on a release build an alarm rings, a headless sync runs from WorkManager, the tile works, and a reboot re-arms. Pinned by Task 4 Step 6 (an emulator smoke test of the release APK) and Task 12.
5. **A calendar that stops syncing keeps its alarms and says so.** Expected: `queryInstances` refuses a calendar whose `SYNC_EVENTS` is 0 with `calendar_not_synced`. The source keeps its cached meetings, turns red and posts one "Feed broken" notice, as `calendar_missing` does. Pinned by Task 6.
6. **Signing material never reaches git**, and a release built without `key.properties` cannot reach Play. Expected: Gradle falls back to debug signing with a warning, and Play refuses debug-signed bundles. Pinned by Task 4 (`no signing material is tracked`) and Task 10 Step 4.

---

## Decisions

Agreed with the user (2026-11-02, recorded in the roadmap; 2026-11-14 in planning):

1. **Scope ends at Play internal testing.**
2. **`RingingService` uses `systemExempted`.** Android allows it for apps holding `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM`, and Play's FGS policy exempts the type from the use-case criteria. `mediaPlayback` is the fallback **if Play review rejects the type**. That would be a one-line manifest revert plus the old `foregroundType()`, so Task 2 keeps the change small enough to revert in one commit.
3. **The privacy policy lives on GitHub Pages** at `https://fifothehein.github.io/tminus/privacy/` (`docs/privacy.md`, Jekyll permalink `/privacy/`). The repo is public, and Pages builds from `main` `/docs`.
4. **The cache moves out of the backup** (user, 2026-11-14). `occurrences`, `alert_history` and `sync_log` move to `tminus_cache.sqlite`. A restore already clears exactly these three (Plan 5 decision 4, `RestoreGuard._makeSafe`), so a restore loses nothing it keeps today. The rest stays in `tminus.sqlite` and stays backed up: sources (names, colours, kinds, no links), profiles, rules, overrides, quiet state, settings and meeting links. Overrides and links hold occurrence keys (`sourceId|uid|start`) and iCal UIDs, which are opaque ids, not event content.
5. **Contact (user, 2026-11-14):** the policy and the listing send people to **GitHub issues** on the public repo (`https://github.com/FifoTheHein/tminus/issues`). Play Console requires an email, and **Play shows it publicly on the listing**, so the user picks an address meant for that. It goes only into Play Console, never into the repo.
6. **All three grouping follow-ups are in scope** (user, 2026-11-14): the "no longer synced" state (Task 6), the account kind in default source names (Task 7), and the stricter picker test (Task 7).
7. **A privacy policy link in Settings → About and on onboarding's Welcome privacy note** (user, 2026-11-14). That is all the "onboarding polish" Plan 6 plans. Anything the phone run (Task 12) finds becomes a fix task inside this plan.

Made while planning, where the spec, the roadmap and the code leave a choice (each can be overturned):

8. **Below API 34 the service starts without a type argument.** `ServiceCompat.startForeground(service, id, notification, type)` is called with the type only on API 34+. On API 26–33 it calls the two-argument `startForeground`, which uses the manifest type (API 29–33) or ignores types (26–28). Passing the API 34 constant to an older platform would rely on undocumented handling of an unknown bit.
9. **The 30 s boot-recovery delay stays.** `systemExempted` is not on Android 15's list of types barred from `BOOT_COMPLETED`, so the delay is probably no longer needed. But `refuseForeground` also covers OEM refusals, and removing the delay changes tested recovery paths. Task 12 Step 6 measures whether a ring due during the boot window starts at once with the new type. Removing `RECOVERY_DELAY_MS` is a follow-up if it does.
10. **The cache database is a second drift database, not an `ATTACH`.** In WAL mode SQLite commits across attached files are not atomic. drift's migrator and schema tools also assume one schema per database. No query joins a cache table with another table, so two databases cost nothing in queries. The few writes that touched both (a source's deletion, choosing another calendar, the restore) are re-ordered so that a crash between the two writes is harmless (Task 3).
11. **The legacy move runs in `CacheDatabase`'s `beforeOpen`.** It is idempotent: `INSERT OR IGNORE` copy, then drop. So it is safe when the UI isolate and a headless sync open at the same moment, and after a crash between copy and drop. Schema 3 of `tminus.sqlite` only renames the three tables to `legacy_occurrences`, `legacy_alert_history` and `legacy_sync_log`, and drops `occurrences`' foreign key in the process (SQLite keeps it on rename, so the step rebuilds the table).
12. **Release signing reads `android/key.properties`.** If the file is missing, the release build is signed with the debug key and Gradle prints a warning. That keeps `flutter run --release` working locally, and Play rejects debug-signed bundles, so a mistake cannot ship. The keystore lives outside the repo; `key.properties` gives an absolute `storeFile`.
13. **Versioning:** `pubspec.yaml` `version: <name>+<code>`. The first upload is `1.0.0+1`. Every upload to any track raises the build number by one, and the version name follows semver. `docs/play/release.md` holds the rule and the release steps.
14. **No Dart obfuscation.** The code holds no secrets, and readable stack traces matter more. R8 stays on for Kotlin and Java (Flutter's default). The release bundle includes native debug symbols (`ndk.debugSymbolLevel = "SYMBOL_TABLE"`), so Play's crash view can symbolicate the native code.
15. **No debug-build suffix.** Debug and Play builds keep one application id, so two copies can never ring the same meetings. The cost: switching the phone from a debug build to the Play build means uninstalling. Task 12 Step 1 exports settings first and imports them after.
16. **Reviewers get a demo feed:** `docs/play/demo.ics`, served at `https://fifothehein.github.io/tminus/play/demo.ics`. It holds twelve meetings that repeat daily (`RRULE:FREQ=DAILY`) at every even UTC hour, so a reviewer in any zone sees a meeting within two hours. There are no Teams links (no fake links into Microsoft). It is also the data for the screenshots, so no real meeting appears on the listing.
17. **Default names for phone calendars:**
    - The name is the calendar's own, unless another calendar on the phone or an existing source has the same name (trimmed, case-insensitive).
    - In that case it is `<name> (<kind>)`, where the kind is the picker's group label: `Google`, `Samsung account`, `Outlook`, `Exchange`, and `Phone` for phone-only calendars. Other kinds add no label.
    - If the name still clashes with an existing source, ` 2`, ` 3` and so on is added.
    - Choosing another calendar for a source keeps the source's name.
18. **A calendar that stops syncing is a failure, not an empty result.** `DeviceCalendarReader.instances` checks `Calendars.SYNC_EVENTS` for the asked calendars and throws `calendar_not_synced` for any that is 0. Dart maps that to a new `SyncOutcome.calendarNotSynced` (appended to the enum; stored by name), with error severity and one "Feed broken" notice, like `calendarMissing`. The cached meetings stay, so the alarms keep ringing from the last good data (spec §9: never lose an alarm because of bad data). The source detail offers **Choose another calendar**, as for a removed one.
19. **About's copy is corrected.** "Feeds are fetched directly from Outlook" becomes "Calendars are read directly from your calendar provider", because link help (PR #15) covers Google and other providers too.
20. **`full-backup-content` (API 26–30) gains `requireFlags="clientSideEncryption"`** on its includes, matching `disableIfNoEncryptionCapabilities="true"` on API 31+. On API 28–30 the database is then backed up only when Android can encrypt it end to end. Android ignores the flag on API 26–27, so the backup there may be unencrypted. This is accepted: after Task 3 the backup holds no meetings and no links, only settings, rules and source names.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` | `FOREGROUND_SERVICE_SYSTEM_EXEMPTED`, service type `systemExempted` | 2 |
| `android/.../engine/RingingService.kt` | `foregroundType()` by SDK; comments | 2 |
| `android/.../engine/EngineActions.kt`, `BootReceiver.kt`, `AlarmScheduler.kt` | Comments only (the type is no longer `mediaPlayback`) | 2 |
| `android/app/src/test/.../engine/RingingServiceTest.kt`, `RearmReceiversTest.kt` | Type tests on SDK 34 and 33; renamed refusal texts | 2 |
| `lib/core/storage/cache_tables.dart` (new) | `Occurrences` (no foreign key), `AlertHistory`, `SyncLog`, moved from `tables.dart` | 3 |
| `lib/core/storage/cache_database.dart` (new) | `CacheDatabase`, `open()`, the legacy move | 3 |
| `lib/core/storage/tables.dart`, `app_database.dart` | Drop the three tables; schema 3 renames them to `legacy_*` | 3 |
| `lib/core/storage/occurrence_repository.dart`, `alert_history_repository.dart`, `sync_log_repository.dart` | Built on `CacheDatabase`; `OccurrenceRepository.deleteForSource` | 3 |
| `lib/core/sources/source_admin.dart` | Delete a source's cache rows explicitly; re-ordered `updateDeviceCalendar` | 3 |
| `lib/app/restore_guard.dart`, `app_lifecycle.dart`, `di.dart` | Clear the cache first; refresh both databases; register `CacheDatabase` | 3 |
| `drift_schemas/drift_schema_v3.json`, `drift_schemas/cache/drift_schema_v1.json`, `test/generated_migrations/**` | Schema dumps and helpers | 3 |
| `android/app/build.gradle.kts` | Upload signing, native debug symbols | 4 |
| `android/app/src/main/res/xml/backup_rules.xml` | `requireFlags="clientSideEncryption"` | 4 |
| `android/app/src/test/.../BackupRulesTest.kt` | The cache file is never backed up; encryption flags | 4 |
| `test/no_signing_material_test.dart` (new) | No keystore or `key.properties` tracked | 4 |
| `docs/play/release.md` (new) | Versioning, keystore, build and upload steps, 16 KB check | 4 |
| `docs/privacy.md` (new), `docs/index.md` | The policy; the home page links it | 5 |
| `docs/play/demo.ics` (new) | Reviewer and screenshot feed | 5 |
| `lib/app/links.dart` (new) | `privacyPolicyUrl`, `issuesUrl` | 5 |
| `lib/features/settings/settings_screen.dart`, `lib/features/onboarding/onboarding_screen.dart` | Privacy policy links; About copy | 5 |
| `test/app/links_test.dart` (new) | The URL matches the page's permalink; the demo feed parses | 5 |
| `android/.../calendar/DeviceCalendarReader.kt` (+ its test) | `calendar_not_synced` | 6 |
| `lib/core/model/sync_log_entry.dart`, `lib/core/sync/outcome_severity.dart`, `lib/core/sources/device_calendar_api.dart`, `device_calendar_source.dart` | `calendarNotSynced` | 6 |
| `lib/features/health/health_text.dart`, `lib/features/sources/problem_card.dart`, `source_detail_screen.dart` | Its text, icon and action | 6 |
| `lib/features/sources/calendar_groups.dart` | `kindLabel` (for names), `defaultSourceName` | 7 |
| `lib/features/sources/add_source_panel.dart` | Pass the default name | 7 |
| `test/features/sources/calendar_picker_test.dart`, `calendar_groups_test.dart`, `add_source_panel_test.dart` | `isFalse`; naming tests | 7 |
| `docs/play/listing.md`, `docs/play/declarations.md` (new) | Listing copy; every Play Console answer | 8 |
| `tool/gen_feature_graphic.py` (new), `docs/play/feature-graphic.png` | 1024 × 500 feature graphic from the icon's geometry | 8 |
| Spec, roadmap, CLAUDE.md, README, design brief | Record what Plan 6 changed | 13 |

## Waves

| Wave | Tasks (parallel within a wave, no shared files) | Needs |
|---|---|---|
| 0 | 1 (scout: preflight); **A (user)**: trademark search; **B (user)**: Play Console account and app | — |
| 1 | 2 (Kotlin), 3, 5, 7 | 0 |
| 2 | 6 (Kotlin), 8 | 1. Task 6 runs Gradle, and Wave 1 already has Task 2's Gradle job. Task 6 also edits `sync_service_test.dart`, which Task 3 rewrites for the new database. Task 8 quotes Task 5's URLs. |
| 3 | 4 (Gradle: signing, backup rules, release smoke) | 2, and **C (user)**: the upload keystore |
| 4 | 9 (screenshots and video), 10 (user: upload and declarations) | 3; Task 5 Step 8's pages are live |
| 5 | 11 (emulators: API 26 to 36), 12 (user: the phone) | 4 (the Play build) |
| 6 | 13 (docs), then the PR | 5 |

Kotlin and Gradle work is in Waves 1, 2 and 3, one task per wave, so only one Gradle job runs at a time. Tasks 3, 5 and 7 run no Gradle job.

---

### Task 1: Preflight (scout)

**Deep review:** no. **Files:** none, unless a name below differs (then this plan's text, and commit `Record the current names in the Plan 6 plan`).

- [ ] **Step 1:** `git fetch origin main && git checkout main && git pull`. Confirm `1d01901` or later.
- [ ] **Step 2:** Check the names this plan uses:
  ```bash
  grep -n "foregroundType\|FOREGROUND_SERVICE_TYPE" android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/RingingService.kt
  grep -n "RECOVERY_DELAY_MS" android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/EngineActions.kt
  grep -n "schemaVersion" lib/core/storage/app_database.dart                       # 2
  grep -n "class Occurrences\|class AlertHistory\|class SyncLog\|references(Sources" lib/core/storage/tables.dart
  grep -n "db.occurrences\|db.alertHistory\|db.syncLog" lib/app/restore_guard.dart
  grep -n "Future<SourceConfig> addDeviceSource\|Future<void> updateDeviceCalendar\|Future<void> delete(" lib/core/sources/source_admin.dart
  grep -n "CALENDAR_MISSING\|SYNC_EVENTS" android/app/src/main/kotlin/io/github/fifothehein/tminus/calendar/DeviceCalendarReader.kt
  grep -n "CalendarGroupKind.google =>" lib/features/sources/calendar_picker.dart
  grep -n "isNot(isTrue)" test/features/sources/calendar_picker_test.dart        # lines 460 and 612
  grep -n "'About & privacy'\|licencesButton\|Feeds are " lib/features/settings/settings_screen.dart   # the copy is split over three lines
  grep -n "class _PrivacyNote" lib/features/onboarding/onboarding_screen.dart
  ```
- [ ] **Step 3:** Run the gates on `main` and record the counts (`flutter test` total, Gradle test total). If `main` is red, report it to the user before Wave 1.
- [ ] **Step 4:** Confirm that `tool/gen_launcher_icon.py` runs (`python3 tool/gen_launcher_icon.py --check` or its equivalent) and that Pillow is installed.

### Task A (user): Trademark search for "T-Minus"

**When:** Wave 0, because the listing name depends on it. **Output:** one line in the run log.

- [ ] Search for "T-Minus" and "TMinus" in software and app classes (Nice classes 9 and 42) in:
  - the USPTO trademark search (`tmsearch.uspto.gov`);
  - EUIPO eSearch;
  - the WIPO Global Brand Database;
  - your home country's register (for South Africa, CIPC).
- [ ] Search Google Play for "T-Minus" apps, and note any countdown or alarm app using the name.
- [ ] Record what you found. If a live registration covers calendar or alarm software, stop Task 8's listing name and choose a new one with the orchestrator. The app's in-code name (`T-Minus`) then changes in Task 13. This is not legal advice; for a real conflict, ask a trademark attorney.

### Task B (user): Play Console account and app

**When:** Wave 0. It can take days, because identity verification is involved.

- [ ] In Play Console, finish the developer account's **identity verification** (Android developer verification: an app on Play is registered automatically, but the account must be verified).
- [ ] **Create app:**
  - name `T-Minus: Meeting Alarm`, or the name Task A chose;
  - default language English (United Kingdom);
  - App;
  - Free;
  - accept the declarations.
- [ ] Check that the package name the first upload will register is `io.github.fifothehein.tminus`. **It can never change after the first upload.**
- [ ] Set the public **developer contact email**, an address meant for that (decision 5). Play shows it on the listing. Do not put it in the repo.
- [ ] Note whether the account is personal and created after 2023-11-13. It only matters for the later production step.

### Task C (user): The upload keystore

**When:** before Wave 3. Keep the keystore and its passwords **outside the repo, with a backup**. Losing the upload key means asking Google for a reset.

- [ ] PowerShell:
  ```powershell
  keytool -genkey -v -keystore $env:USERPROFILE\keys\tminus-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
  ```
- [ ] Create `C:\Projects\tminus\android\key.properties` (git-ignored):
  ```properties
  storeFile=C:\\Users\\<you>\\keys\\tminus-upload.jks
  storePassword=<password>
  keyAlias=upload
  keyPassword=<password>
  ```
- [ ] Back up the `.jks` and the passwords (a password manager, plus one offline copy).

---

### Task 2: The ringing service runs as `systemExempted`

**Deep review:** yes (alarm delivery).

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/RingingService.kt`, and the comments that name `mediaPlayback` in `EngineActions.kt`, `BootReceiver.kt` and `AlarmScheduler.kt`.
- Test: `android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/RingingServiceTest.kt`, plus `RearmReceiversTest.kt` (comments and texts only).

- [ ] **Step 1: Manifest.**
  - Replace `android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK` with `android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED`.
  - Set `RingingService`'s `android:foregroundServiceType="systemExempted"`.
  - Replace the comment above the service with: `<!-- systemExempted: allowed for apps holding USE_EXACT_ALARM / SCHEDULE_EXACT_ALARM (Plan 6 decision 2). mediaPlayback is the fallback if Play review rejects it. -->`.
- [ ] **Step 2: `foregroundType()`** becomes nullable, and the start call passes a type only when there is one (decision 8):
  ```kotlin
  /** The type to pass to startForeground, or null to use the manifest's (API 26-33, Plan 6 decision 8). */
  private fun foregroundType(): Int? =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED else null
  ```
  The `startForeground` seam keeps its signature `(Service, Int, Notification, Int) -> Unit`. `DEFAULT_START_FOREGROUND` becomes a lambda that calls `service.startForeground(id, notification)` when the type is `NO_TYPE` (a new private constant, `-2`, never a real type), and `ServiceCompat.startForeground(service, id, notification, type)` otherwise. The call site passes `foregroundType() ?: NO_TYPE`. The `IllegalStateException` / `SecurityException` handling stays: `ForegroundServiceTypeException` extends `IllegalStateException`, so a refused type still falls back to heads-up through `refuseForeground`.
- [ ] **Step 3: Comments.** Every comment that says Android 15+ refuses `mediaPlayback` at boot now says that **it refused the previous `mediaPlayback` type**, and that the delay stays as a guard (decision 9). The behaviour does not change: `RECOVERY_DELAY_MS`, `recoverAfterBoot` and `armRingingRetry` stay exactly as they are.
- [ ] **Step 4: Tests** (each new test gets a negative control):
  - `the service starts as systemExempted on Android 14 and later`, on `@Config(sdk = [34])`. The fake `startForeground` records `FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED`.
  - `below Android 14 the service starts with the manifest's type`, on `@Config(sdk = [33])`. The fake records `NO_TYPE`. If Robolectric's SDK 33 jar cannot be downloaded, the scout records that, and Task 11 covers the case on the API 33 emulator.
  - `the manifest declares systemExempted and its permission`: it reads the merged manifest through `PackageManager` (`ServiceInfo.foregroundServiceType` and `requestedPermissions`) and checks that `FOREGROUND_SERVICE_MEDIA_PLAYBACK` is absent.
  - The existing refusal tests keep passing. Their exception messages may keep the literal `mediaPlayback` text, because they model what older builds saw. Rename only the test names that claim the current type is `mediaPlayback`.
- [ ] **Step 5:** Run the gates, then commit `Run the ringing service as systemExempted`.

### Task 3: Move the meeting cache out of the backup

**Deep review:** yes (schema migration, two isolates, alarm safety).

**Files:**
- Create: `lib/core/storage/cache_tables.dart`, `lib/core/storage/cache_database.dart`, and `drift_schemas/cache/drift_schema_v1.json`.
- Modify:
  - `lib/core/storage/tables.dart`, `app_database.dart` and their generated `*.g.dart`;
  - `occurrence_repository.dart`, `alert_history_repository.dart`, `sync_log_repository.dart`;
  - `lib/core/sources/source_admin.dart`, `lib/core/sources/fast_alarms.dart` (its `delete` also relies on the cascade today: "its cached occurrences go with it");
  - `lib/app/restore_guard.dart`, `app_lifecycle.dart`, `di.dart`;
  - `test/core/storage/test_database.dart`;
  - every test that builds one of the three repositories directly (`grep -rln "OccurrenceRepository(\|AlertHistoryRepository(\|SyncLogRepository(" test`).
- Generated: `drift_schemas/drift_schema_v3.json`, `test/generated_migrations/**`, `test/generated_migrations/cache/**`.
- Test: `test/core/storage/cache_database_test.dart` (new), `test/core/storage/app_database_test.dart` (its migration tests: v1 → v3 and v2 → v3), `test/core/storage/cache_storage_test.dart`, `test/app/restore_guard_test.dart`, `test/core/sources/source_admin_test.dart`, `test/app/app_lifecycle_test.dart`.

- [ ] **Step 1: Dump schema 2 first:** `dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/`. Confirm `drift_schema_v2.json` is unchanged (`git diff --exit-code drift_schemas/`).
- [ ] **Step 2: `cache_tables.dart`.** Move `Occurrences`, `AlertHistory` and `SyncLog` (with their `@TableIndex`es and `@DataClassName`s) out of `tables.dart` without changing their columns. The one exception: `Occurrences.sourceId` loses `.references(Sources, …)`, because SQLite has no foreign keys across files. The table names and the generated row classes (`Occurrence`, `AlertHistoryData` or whatever the generator names them today) must stay the same, so the repositories' mapping code does not change.
- [ ] **Step 3: `CacheDatabase`.**
  ```dart
  @DriftDatabase(tables: [Occurrences, AlertHistory, SyncLog])
  class CacheDatabase extends _$CacheDatabase {
    CacheDatabase(super.executor, {this.legacy});

    /// `tminus_cache.sqlite` next to `tminus.sqlite`. Not listed in the backup
    /// rules, so Android never backs it up (Plan 6 decision 4).
    factory CacheDatabase.open({required AppDatabase legacy}) => CacheDatabase(
      driftDatabase(name: 'tminus_cache', native: const DriftNativeOptions(setup: AppDatabase.configureConnection)),
      legacy: legacy,
    );

    /// The database whose schema-3 `legacy_*` tables are moved here on open.
    final AppDatabase? legacy;

    @override
    int get schemaVersion => 1;

    @override
    MigrationStrategy get migration => MigrationStrategy(
      onCreate: (m) => m.createAll(),
      beforeOpen: (_) async {
        await customStatement('PRAGMA busy_timeout = ${AppDatabase.busyTimeoutMs}');
        await customStatement('PRAGMA journal_mode = WAL');
        final from = legacy;
        if (from != null) await LegacyCacheMove(from: from, to: this).run();
      },
    );

    Future<void> checkpoint() async {
      await customSelect('PRAGMA wal_checkpoint(PASSIVE)').get();
    }
  }
  ```
  `LegacyCacheMove.run()` (in the same file) does the following:
  1. For each of `legacy_occurrences`, `legacy_alert_history` and `legacy_sync_log` that exists in `from` (`sqlite_master`), it reads the rows in pages of 500 ordered by rowid. It inserts them with `INSERT OR IGNORE` and the same column list into the cache table, all inside **one** cache transaction. A row already there wins: it can only be newer, because nothing writes the legacy tables any more.
  2. After that transaction commits, it drops the three legacy tables in **one** `from` transaction, re-checking that each exists (another isolate may have dropped it already).
  3. Errors propagate. A failed move fails the open, so nothing plans from a half-empty cache. The next open tries again.
- [ ] **Step 4: Schema 3 of `tminus.sqlite`.** `schemaVersion => 3`, and `AppDatabase`'s table list drops the three tables. The new step:
  ```dart
  if (from < 3) {
    // Plan 6 decision 4: the cache moves to tminus_cache.sqlite. Rename only;
    // CacheDatabase copies the rows and drops these (decision 11).
    // occurrences is rebuilt without its foreign key, which SQLite would keep
    // on a rename and which would then cascade from sources.
    await customStatement('CREATE TABLE legacy_occurrences AS SELECT * FROM occurrences');
    await customStatement('DROP TABLE occurrences');
    await customStatement('ALTER TABLE alert_history RENAME TO legacy_alert_history');
    await customStatement('ALTER TABLE sync_log RENAME TO legacy_sync_log');
    await customStatement('DROP INDEX IF EXISTS alert_history_start');
    await customStatement('DROP INDEX IF EXISTS sync_log_at');
  }
  ```
  `CREATE TABLE … AS SELECT` keeps the column names and values, but not the constraints. That's enough for a table that is only read and dropped. The snippet shows the statements, not the final shape; the step must also meet these rules:
  - **One transaction, safe to run twice.** The `from < 2` step's comment explains why: drift stores the new version only after `onUpgrade` returns, and both isolates may upgrade the same file at once. So each statement runs only if `sqlite_master` shows it is still needed (for example, the copy runs only while `occurrences` exists and `legacy_occurrences` does not), and the first statement in the transaction is a write, as that comment requires.
  - **The shipped `from < 2` step keeps working without being changed in meaning.** It calls `m.addColumn(occurrences, occurrences.icalUid)` and `m.createTable(meetingLinks)`, and `occurrences` is no longer one of `AppDatabase`'s tables. Use drift's generated per-version schema classes (`dart run drift_dev make-migrations`, or `schema steps`, which writes `Schema2` with typed tables), so the step reads `schema.occurrences` from schema 2 and still compiles. If that tool cannot be used with this setup, the fallback is to replace only the `occurrences` calls with the exact SQL they ran today (`ALTER TABLE occurrences ADD COLUMN ical_uid TEXT`). Record the choice in "Built differently". Either way, `app_database_test.dart`'s v1 → v2 tests must still pass, with v1 → v3 tests added.

  Dump schema 3 (`drift_schemas/drift_schema_v3.json`), dump the cache schema into `drift_schemas/cache/`, and regenerate both helper sets.
- [ ] **Step 5: Repositories and callers.**
  - `OccurrenceRepository`, `AlertHistoryRepository` and `SyncLogRepository` take a `CacheDatabase`.
  - `OccurrenceRepository` gains `Future<int> deleteForSource(String sourceId)`.
  - `SourceAdmin.delete` calls `occurrences.deleteForSource(id)` after `sources.delete(id)`, replacing the lost cascade. It takes `{bool clearCache = true}` for Step 6. `FastAlarms`' `delete` does the same, through `OccurrenceRepository`. A crash between the two leaves cache rows for a source that no longer exists. The planner reads only enabled sources' copies, so those rows plan nothing, and `deleteEndedBefore` prunes them.
  - `SourceAdmin.updateDeviceCalendar` clears the source's cache rows **before** its main transaction, not inside it. A crash in between leaves the old calendar's source with an empty cache. That plans nothing for it until the next fetch refills it, the same as a new source.
- [ ] **Step 6: `RestoreGuard._makeSafe`.** The guard runs before anything opens `CacheDatabase`, at both entry points (`start_services.dart`, `sync_main.dart`). Keep it that way, and keep the race it already handles: the UI isolate and a headless sync can both reach `_makeSafe`, and the one that comes second must find the first one's work and touch nothing.
  - **Inside** the existing transaction, after the install-id check, replace the three `db.delete(db.occurrences / alertHistory / syncLog)` calls with `DROP TABLE IF EXISTS` for `legacy_occurrences`, `legacy_alert_history` and `legacy_sync_log`. A pre-Plan-6 backup's cached meetings are then gone in the same commit as the new install id, and `LegacyCacheMove` finds nothing to move. The `sync.%` settings delete stays where it is.
  - **After** the transaction, and only when it returned `RestoreOutcome.restored`, delete every row of the three cache tables through `CacheDatabase`. A restored phone normally has no cache file, because it is never backed up or transferred. This covers a cache left from using the app on this phone before the restore. It is safe after the commit: the restore leaves every source disabled, so no sync in another isolate can be filling the cache.
  - **Never** clear the cache before the transaction or when the outcome is `normal`. Clearing it there would wipe a cache that the first guard's sync has already filled.
  - **`_makeSafe` must not open `CacheDatabase` before its transaction.** Today it deletes the debug source first, with `admin.delete(s.id)`. After Step 5 that would open the cache database, and with it `LegacyCacheMove`. A second isolate could then copy the restored backup's legacy rows into the cache after the first guard's post-commit clear. So the guard calls `admin.delete(s.id, clearCache: false)`; the post-commit clear covers the debug source's rows. Nothing else in `RestoreGuard.run` may touch an `OccurrenceRepository`, `AlertHistoryRepository` or `SyncLogRepository` before the transaction.
- [ ] **Step 7: `AppLifecycle` and DI.**
  - `AppLifecycle` marks both databases' tables updated, on a resume and on the background-sync signal.
  - `AppLifecycle` checkpoints only `tminus.sqlite` on pause, because only it is backed up.
  - `di.dart` registers `CacheDatabase` lazily: `openCacheDatabase?.call() ?? CacheDatabase.open(legacy: getIt<AppDatabase>())`, with `dispose: (db) => db.close()`.
  - `configureDependencies` gains `CacheDatabase Function()? openCacheDatabase`. When a test passes `openDatabase` without `openCacheDatabase`, an in-memory `CacheDatabase` with no legacy source is used, so the screen tests' harness does not change.
  - `test_database.dart` adds `openTestCacheDatabase()`.
- [ ] **Step 8: Tests** (named as below; each beyond the migration helpers' generated ones gets a negative control):
  - `an upgraded database keeps every cached meeting and the plan is unchanged`. Build a schema-2 database with sources, occurrences, history and a sync log (through the generated v2 helpers). Open it at v3 with a `CacheDatabase` on top. The cache holds the same rows, the legacy tables are gone, and `MeetingPlanner.load` gives the same alerts as before the move.
  - `a move interrupted after the copy finishes on the next open`. The copy commits, the drop throws (a fake), and the reopen finds every row once and drops the tables.
  - `two isolates opening at once copy once`. Two `CacheDatabase`s over one cache file (a temp-dir file, not `:memory:`) and one main file, opened together: every row exists once.
  - `a fresh install has no legacy tables and an empty cache`.
  - `v1 to v3 and v2 to v3 migrate and validate`. These are `verifier.migrateAndValidate` with `validateDropped: false` straight after the upgrade, because the `legacy_*` tables exist until the cache opens. Then open the `CacheDatabase` and validate again with the strict options the file already uses (`validateDropped: true`).
  - `running the schema 3 step twice changes nothing`: the second-isolate case of the `from < 2` step, repeated for the new step.
  - `deleting a source deletes its cached meetings` (`source_admin_test.dart`).
  - `choosing another calendar clears the old calendar's meetings` (the existing test, kept green with the new order).
  - `a restore drops the legacy tables with the new install id` (`restore_guard_test.dart`): a schema-2 backup restored onto Plan 6 leaves no `legacy_*` table and an empty cache, and the move copies nothing.
  - `a restore clears a cache left on this phone`.
  - `a guard that finds the restore already done leaves the cache alone`: the second-isolate case, where the cache holds rows a sync wrote after the first guard committed.
  - `the restore opens the cache only after its transaction`: a `CacheDatabase` fake that records when it is opened.
  - `a resume refreshes the watchers of both databases` (`app_lifecycle_test.dart`).
  - The existing `BackupRulesTest` keeps passing unchanged. Task 4 adds the cache file assertion.
- [ ] **Step 9:** Run the gates, then commit `Move the meeting cache into a database that is never backed up`.

### Task 4: The release build: signing, backup rules and a release smoke test

**Deep review:** yes (signing material, backup rules).

**Files:**
- Modify: `android/app/build.gradle.kts`, `android/app/src/main/res/xml/backup_rules.xml`, `android/app/src/test/kotlin/io/github/fifothehein/tminus/BackupRulesTest.kt`
- Create: `test/no_signing_material_test.dart`, `docs/play/release.md`

- [ ] **Step 1: Signing** (decision 12), at the top of `build.gradle.kts`:
  ```kotlin
  import java.util.Properties

  // Upload signing (Plan 6 decision 12). android/key.properties is git-ignored and names a
  // keystore outside the repo. Without it a release is debug-signed, which Play refuses.
  val uploadKey = Properties().apply {
      rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
  }
  ```
  Inside `android { }`:
  ```kotlin
  signingConfigs {
      if (!uploadKey.isEmpty) create("upload") {
          storeFile = file(uploadKey.getProperty("storeFile"))
          storePassword = uploadKey.getProperty("storePassword")
          keyAlias = uploadKey.getProperty("keyAlias")
          keyPassword = uploadKey.getProperty("keyPassword")
      }
  }
  buildTypes {
      release {
          signingConfig = if (uploadKey.isEmpty) {
              logger.warn("android/key.properties is missing: the release build is debug-signed and Play will refuse it.")
              signingConfigs.getByName("debug")
          } else signingConfigs.getByName("upload")
          ndk { debugSymbolLevel = "SYMBOL_TABLE" } // decision 14
      }
  }
  ```
  This replaces the template's `// TODO: Add your own signing config` block.
- [ ] **Step 2: Backup rules** (decision 20). `backup_rules.xml`'s two includes gain `requireFlags="clientSideEncryption"`. `BackupRulesTest` gains:
  - `the cache database is never backed up`: `tminus_cache.sqlite` and its `-wal` are outside both rule files, for `cloud-backup` and `device-transfer`;
  - `backups below Android 12 need encryption`.
- [ ] **Step 3: `test/no_signing_material_test.dart`.** It runs `git ls-files` and fails if any tracked path matches `key.properties`, `*.jks`, `*.keystore` or `*.p12` (`*.p12` is new, so the scout adds it to `android/.gitignore` too). It is skipped with a reason when `git` is not on the PATH.
- [ ] **Step 4: Build.** `flutter build appbundle --release` (with Task C's `key.properties`), then `flutter build apk --release`.
  - Check that the bundle is signed with the upload key: `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab` shows the upload certificate, not `CN=Android Debug`.
- [ ] **Step 5: What is in the release.** Every result goes in the run log.
  - Read the merged release manifest (`build/app/intermediates/merged_manifests/release/…/AndroidManifest.xml`). Record every `uses-permission`. Expected:
    - `USE_EXACT_ALARM`;
    - `SCHEDULE_EXACT_ALARM` (max 32);
    - `USE_FULL_SCREEN_INTENT`;
    - `POST_NOTIFICATIONS`;
    - `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SYSTEM_EXEMPTED`;
    - `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `VIBRATE`;
    - `INTERNET`, `READ_CALENDAR`;
    - `ACCESS_NETWORK_STATE` (WorkManager), and the app's own `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (protection level signature).

    Checked before building, on 2026-11-14 (a local release build of `main` at `1d01901`, read from the APK with aapt2 36.0.0): exactly this list, plus `FOREGROUND_SERVICE_MEDIA_PLAYBACK` where Task 2 puts `FOREGROUND_SERVICE_SYSTEM_EXEMPTED`.
  - Any `com.google.android.gms.permission.AD_ID` fails the task: Data safety and the policy say no advertising id.
  - List every `<service>` with an `android:foregroundServiceType`. Expected: only `RingingService` (`systemExempted`).
    - **Checked on 2026-11-14** (the same build). WorkManager's `SystemForegroundService` is merged with **no** type, so it needs no Play declaration and no `tools:remove`. `SyncWorker` builds `ForegroundInfo(id, notification)` (type 0) and never calls `setForeground`. `SyncScheduler` uses `setExpedited(RUN_AS_NON_EXPEDITED_WORK_REQUEST)`. On API 31+ that work runs as a JobScheduler job; on API 26–30 it runs in `SystemForegroundService` with no type, which those versions allow.
    - Re-check after Task 2: still only `RingingService` has a type.
    - Other services in that build, all untyped: `QuietTileService` (exported, guarded by `BIND_QUICK_SETTINGS_TILE`), `SystemJobService` (exported, guarded by `BIND_JOB_SERVICE`) and `androidx.room.MultiInstanceInvalidationService`.
    - Exported components in that build: `MainActivity`, `BootReceiver`, `TimeChangeReceiver`, `SyncBootReceiver`, the two guarded services above, and WorkManager's `DiagnosticsReceiver` and `ProfileInstallReceiver` (both guarded by `android.permission.DUMP`). Any new exported component in the release manifest needs a reason in the run log.
  - `grep -n "firebase\|crashlytics\|analytics\|ads" pubspec.lock` → nothing.
- [ ] **Step 6: 16 KB pages.** Run in Git Bash on the build machine. Tools:
  - `zipalign` from Android SDK build-tools **35.0.0 or later** (older versions have no `-P`);
  - the bundletool jar (from its GitHub releases);
  - `llvm-readelf` from the NDK the build uses (`$ANDROID_HOME/ndk/<version>/toolchains/llvm/prebuilt/windows-x86_64/bin/`).

  Work in a scratch folder outside the repo:
  ```bash
  S=$(mktemp -d)
  java -jar bundletool.jar build-apks --bundle=build/app/outputs/bundle/release/app-release.aab --output="$S/tminus.apks" --mode=universal
  unzip -o "$S/tminus.apks" universal.apk -d "$S" && zipalign -c -P 16 -v 4 "$S/universal.apk" | tail -3
  for so in $(unzip -l "$S/universal.apk" | awk '/arm64-v8a.*\.so$/{print $4}'); do unzip -p "$S/universal.apk" "$so" > "$S/lib.so"; echo "$so $(llvm-readelf -l "$S/lib.so" | awk '/LOAD/{print $NF}' | sort -u | tr '\n' ' ')"; done
  ```
  Expected: `Verification successful`, and every arm64 `.so` (Flutter's engine, `libapp.so` and sqlite3's library) has LOAD alignment `0x4000` or more. Any library at `0x1000` blocks the upload. Record its package and version, and fix it by upgrading within the repo's pins, or stop and ask.
- [ ] **Step 7: Release smoke test on the API 36 emulator** (decision 14: R8 is on). `adb uninstall io.github.fifothehein.tminus`, `adb install build/app/outputs/flutter-apk/app-release.apk`. Then:
  1. onboarding with the demo feed. Until Task 5's docs are on `main` (Task 5 Step 8), use the branch's raw file: `https://raw.githubusercontent.com/FifoTheHein/tminus/<branch>/docs/play/demo.ics`. The repo is public, so this is https and needs no token. After that, use `https://fifothehein.github.io/tminus/play/demo.ics`;
  2. the test alarm rings full screen and stops;
  3. Sources → the demo calendar → **Sync now** runs (or pull to refresh on the Agenda), and Health's sync log shows it;
  4. `adb shell cmd jobscheduler run -f io.github.fifothehein.tminus <job id>`, or wait for the periodic sync: a headless sync runs (`HeadlessFlutterRunner` log line, Health's sync log);
  5. the Mute today tile toggles;
  6. `adb reboot`: after the reboot, Health's upcoming alarms are still listed.
  7. Developer tools do not appear in Settings.
  8. `adb logcat --pid=$(adb shell pidof io.github.fifothehein.tminus)` shows no event title, URL or link. Record any `ClassNotFoundException` or `NoSuchMethodError`: each one needs an R8 keep rule (`android/app/proguard-rules.pro`, created only if needed).
- [ ] **Step 8: `docs/play/release.md`.** Write down:
  - versioning (decision 13);
  - the keystore and the backup rule (Task C), and what to do if the upload key is lost (Play Console → App integrity → request an upload key reset);
  - the build commands;
  - the Step 6 check;
  - uploading the AAB and `mapping.txt` (Play takes the mapping from the bundle; check it in App bundle explorer);
  - the switch from a debug build to the Play build: export settings, uninstall, install, import (decision 15).
- [ ] **Step 9:** Run the gates (Kotlin too), then commit `Sign release builds with the upload key and require encrypted backups`.

### Task 5: Privacy policy, demo feed and the links in the app

**Deep review:** no (no secrets; but Review Focus 3 checks the policy).

**Files:**
- Create: `docs/privacy.md`, `docs/play/demo.ics`, `lib/app/links.dart`, `test/app/links_test.dart`
- Modify: `docs/index.md`, `lib/features/settings/settings_screen.dart`, `lib/features/onboarding/onboarding_screen.dart`, `test/features/settings/settings_screen_test.dart`, `test/features/onboarding/onboarding_test.dart`

- [ ] **Step 1: `lib/app/links.dart`:**
  ```dart
  /// Public pages the app links to (Plan 6). Both open in the browser through
  /// `tminus_ui.openUrl`, which accepts https only.
  const privacyPolicyUrl = 'https://fifothehein.github.io/tminus/privacy/';
  const issuesUrl = 'https://github.com/FifoTheHein/tminus/issues';
  ```
- [ ] **Step 2: `docs/privacy.md`.** Front matter `title: Privacy policy` and `permalink: /privacy/`. Then this text. Replace `<date>` with the date the page is merged.

  > # T-Minus privacy policy
  >
  > Effective <date>.
  >
  > T-Minus turns the meetings in your calendars into alarms on your Android phone. It has no account, no server, no analytics, no ads and no crash reporting. Nobody, including the developer, receives your calendar or anything else from the app.
  >
  > ## What the app reads
  >
  > - **Calendar links you paste.** If you add a calendar by its published link (for example an Outlook or Google ICS link), the app stores the link in Android's encrypted storage on your phone, never in its database, and fetches it over the internet to read your meetings. The link works like a password, so the app shows it only masked and never writes it to its logs.
  > - **Calendars on your phone.** If you choose a calendar that is already on your phone, the app asks for the Calendar permission and reads that calendar's events. It never changes your calendars.
  > - **Meetings.** From those calendars the app reads each meeting's title, time, location, organiser, description and Teams link, so it can decide which meetings ring, show them, and open the Teams link when you tap Join.
  >
  > ## Where it is kept
  >
  > Everything stays on your phone. Meetings are kept in a cache that is never included in a backup and is cleared when you remove a calendar or uninstall the app.
  >
  > Android can back up the app's settings to your Google account, end to end encrypted: your alert profiles, rules, quiet mode, the names and colours of your calendars, and which meetings you switched on or off. The backup never contains your calendar links or your meetings. On a new phone the app asks you to add each calendar link again.
  >
  > ## What leaves your phone
  >
  > - **Calendar fetches.** The app downloads each calendar link you added, directly from that calendar's server (for example Microsoft or Google). That server sees your phone's internet address, as with any download. Nothing else is sent.
  > - **Links you open.** Join opens the meeting's Teams link in the Teams app or your browser, and the privacy policy link opens this page in your browser. Those apps and sites have their own privacy policies.
  > - **Settings export.** If you export your settings, the app writes a file where you choose. The file contains no calendar links and no meetings.
  >
  > ## Permissions
  >
  > | Permission | Why |
  > |---|---|
  > | Alarms and reminders (exact alarms) | To ring at the exact minute before a meeting. |
  > | Notifications and full-screen alerts | To show heads-up reminders and the full-screen alarm, including on the lock screen. |
  > | Calendar | Only if you choose a calendar on your phone, to read its events. |
  > | Internet | Only to fetch the calendar links you added. |
  > | Run at startup, wake lock, vibrate, foreground service | To set your alarms again after a restart and to ring, vibrate and keep ringing until you stop the alarm. |
  >
  > ## Deleting your data
  >
  > Removing a calendar in the app deletes its link and its meetings. Uninstalling the app deletes everything it stored on your phone. To delete the app's Android backup, remove it in your Google account's backup settings.
  >
  > ## Children
  >
  > T-Minus is a work tool and is not directed at children.
  >
  > ## Changes and contact
  >
  > If this policy changes, the new version is published on this page with a new effective date. Questions: open an issue at https://github.com/FifoTheHein/tminus/issues.

- [ ] **Step 3: `docs/index.md`.** Replace "The privacy policy will be published on this site before the app is released." with `Read the [privacy policy](privacy/).`
- [ ] **Step 4: `docs/play/demo.ics`** (decision 16). One `VCALENDAR` with `PRODID:-//T-Minus//Demo//EN` and twelve `VEVENT`s. Each has:
  - `DTSTART:20260101T<HH>0000Z` for HH = 00, 02, …, 22;
  - `DURATION:PT30M` and `RRULE:FREQ=DAILY`;
  - a stable `UID:demo-<HH>@tminus.example`.

  Titles are neutral and varied, for example "Team stand-up", "Design review", "1:1 with Sam", "Sprint planning" and "Customer call". One has `TRANSP:TRANSPARENT`, to show the Free skip filter, and one has `LOCATION:Room 4`. No `DESCRIPTION` contains a link.
- [ ] **Step 5: The links.**
  - **Settings → About & privacy:** a `TextButton` `Privacy policy` (`Key('privacyPolicyButton')`) next to **Licences**. It calls `getIt<UiPlatform>().openUrl(privacyPolicyUrl)`, and on `false` shows the snackbar `Could not open the privacy policy.`. Change the card's second line to "No account, no servers, no analytics. Calendars are read directly from your calendar provider and stored only on this device." (decision 19).
  - **Onboarding Welcome, `_PrivacyNote`:** the same link as a `TextButton` `Privacy policy` (`Key('onboardingPrivacyPolicy')`) under the note, with the same failure snackbar.
- [ ] **Step 6: Tests:**
  - `the privacy policy URL matches the page's permalink` reads `docs/privacy.md`'s front matter.
  - `the demo feed parses and has a meeting in every two-hour window`: `expandIcs` over the next 24 h from a few fixed `now`s gives twelve occurrences, all two hours apart.
  - `About opens the privacy policy` and `onboarding opens the privacy policy` mock `tminus_ui.openUrl` and assert the URL.
  - `a failed open shows the snackbar`.
  - `settings_screen_test.dart`'s About copy check (about line 648) changes to the new sentence.
  - `test/no_em_dash_test.dart` stays green.
- [ ] **Step 7:** Run the gates, then commit `Publish the privacy policy and a demo feed, and link the policy in the app`.
- [ ] **Step 8: Put the two pages online early**, once **both Task 5 and Task 3 are committed**. The policy says the meeting cache is never backed up, which becomes true only with Task 3. Open a small PR to `main` containing only `docs/privacy.md`, `docs/play/demo.ics` and the `docs/index.md` link, and merge it. Then check that `https://fifothehein.github.io/tminus/privacy/` and `…/play/demo.ics` load, and that the feed downloads as `text/calendar`. Merge the plan branch with `main` afterwards; the files are identical, so there is no conflict. The app code stays on the plan branch until Task 13's PR.

### Task 6: Say when a phone calendar stops syncing

**Deep review:** yes (the sync path and alarm safety).

**Files:**
- Modify:
  - `android/app/src/main/kotlin/io/github/fifothehein/tminus/calendar/DeviceCalendarReader.kt`;
  - `lib/core/model/sync_log_entry.dart`, `lib/core/sync/outcome_severity.dart`;
  - `lib/core/sources/device_calendar_api.dart`, `device_calendar_source.dart`;
  - `lib/features/health/health_text.dart`;
  - `lib/features/sources/problem_card.dart`, `source_detail_screen.dart`;
  - `lib/core/sync/sync_service.dart` (the notice text).
- Test: `android/app/src/test/kotlin/io/github/fifothehein/tminus/calendar/DeviceCalendarReaderTest.kt`, `test/core/sources/device_calendar_source_test.dart`, `test/core/sync/sync_service_test.dart`, `test/features/health/health_text_test.dart`, `test/features/sources/problem_card_test.dart`, `test/features/sources/source_detail_screen_test.dart`

- [ ] **Step 1: Kotlin.**
  - `instances()` already calls `calendars()` to find the missing ids, and each row already carries `"syncEvents"` (PR #20; a null column reads as synced). Keep those rows. After the missing check, throw `DeviceCalendarException(CALENDAR_NOT_SYNCED, "A calendar is not synced")` if any asked calendar's row has `syncEvents == false`. No second query is needed.
  - The message names no calendar id; ids are opaque, but keep it fixed.
  - Add `const val CALENDAR_NOT_SYNCED = "calendar_not_synced"`.
- [ ] **Step 2: Dart.**
  - `DeviceCalendarApi.calendarNotSynced = 'calendar_not_synced'`.
  - `SyncOutcome.calendarNotSynced`, appended after `skipped`, with the doc comment `/// The Android calendar's sync is off (device sources, Plan 6 decision 18).`
  - `DeviceCalendarSource` maps the code to `SourceFailed(SyncOutcome.calendarNotSynced, 'This calendar is no longer synced on this phone.')`.
  - `OutcomeSeverity`: `error`, and `notifiesBroken` is `true`.
  - `health_text.dart`: `'The calendar stopped syncing'`.
  - `problem_card.dart`:
    - title `Calendar is not syncing`;
    - icon `Icons.sync_disabled`;
    - body `Turn on sync for this calendar in your phone's account settings, or choose another calendar.`
  - `source_detail_screen.dart`: treat `calendarNotSynced` like `calendarMissing` where it offers **Choose calendar** (`Key('chooseCalendar')`, about line 830 today).
  - `sync_service.dart`: the Feed broken notice text switch (about line 559) has a `_` arm that says "feed link stopped working". Add `SyncOutcome.calendarNotSynced => '${config.name}: calendar is not syncing'`, or the phone source's notice would talk about a feed link.
- [ ] **Step 3: Tests** (negative control for each):
  - `a calendar whose sync is off is refused` (Robolectric, a provider row with `SYNC_EVENTS = 0`);
  - `a synced calendar still returns its instances`;
  - `a not-synced calendar keeps its cached meetings and turns the source red`: `SyncService` with a fake API throwing the code; the cache and the plan are unchanged, the log row is `calendarNotSynced`, and one Feed broken notice is posted, once, with the text `<name>: calendar is not syncing`;
  - the text, icon and action tests for the three widgets.
- [ ] **Step 4: Roadmap §3.** The `queryInstances` row's errors become `permission_denied`, `calendar_missing` (Plan 4), `calendar_not_synced` (Plan 6). This is the one contract edit; it is made in this task's commit.
- [ ] **Step 5:** Run the gates (Kotlin too), then commit `Say when a phone calendar stops syncing and keep its alarms`.

### Task 7: Account kind in default names, and a stricter picker test

**Deep review:** no.

**Files:**
- Modify: `lib/features/sources/calendar_groups.dart`, `add_source_panel.dart` (`calendar_picker.dart` does not change)
- Test: `test/features/sources/calendar_groups_test.dart`, `calendar_picker_test.dart`, `add_source_panel_test.dart`

- [ ] **Step 1:** The picker's private `_kindWords` (`calendar_picker.dart`) stays as it is; it names every group for the headings ("Other", "Shared with you", "On this phone only"…). Add a separate public `String? kindLabel(CalendarGroupKind kind)` to `calendar_groups.dart`, for source names only. It returns `Google`, `Samsung account`, `Outlook` and `Exchange` (the same words as `_kindWords`), `Phone` for `phoneOnly`, and `null` for `other`, `shared` and `holidays`.
- [ ] **Step 2: A pure `defaultSourceName`** (decision 17):
  ```dart
  /// The name a new phone-calendar source gets (Plan 6 decision 17).
  String defaultSourceName(
    DeviceCalendar calendar, {
    required List<DeviceCalendar> phoneCalendars,
    required Iterable<String> existingSourceNames,
  });
  ```
  - An empty or blank calendar name reads as `Phone calendar`.
  - Comparison is trimmed and case-insensitive.
  - The kind comes from the calendar's group (`groupCalendars`' rules), so a shared or holiday calendar gets no label.
- [ ] **Step 3:** `AddSourcePanel` passes `name: defaultSourceName(…)` to `SourceAdmin.addDeviceSource` for each picked calendar. When several are picked at once, each one's name counts as existing for the next.
- [ ] **Step 4: Tests:**
  - a unique name is kept;
  - two "My calendar"s, Google and Samsung, become `My calendar (Google)` and `My calendar (Samsung account)`;
  - a clash with an existing source adds the kind;
  - a clash that remains adds ` 2`;
  - picking two clashing calendars at once gives two different names;
  - a blank name becomes `Phone calendar`;
  - an `other` kind gets no label but still a ` 2` if needed.
  - In `calendar_picker_test.dart` lines 460 and 612, `isNot(isTrue)` becomes `isFalse`. Negative control: make the row enabled and see both fail.
- [ ] **Step 5:** Run the gates, then commit `Name phone calendars by account kind when names clash`.

### Task 8: Store listing, declarations and the feature graphic

**Deep review:** no (but Task 10's reviewer reads it against the code).

**Files:**
- Create: `docs/play/listing.md`, `docs/play/declarations.md`, `tool/gen_feature_graphic.py`, `docs/play/feature-graphic.png`
- Test: `test/launcher_icon_test.dart` gains `the feature graphic is 1024 by 500`.

- [ ] **Step 1: `docs/play/listing.md`:**
  - **App name** (30 max): `T-Minus: Meeting Alarm` (22), or Task A's choice.
  - **Short description** (80 max): `Meeting alarms you can't miss, from Outlook, Teams and phone calendars.` (71)
  - **Full description** (4000 max), plain text, written from spec §1:
    - what it does;
    - the two ways to add a calendar;
    - alerts and alarms with escalating strengths, profiles and keyword rules;
    - quiet modes and the Mute today tile;
    - always stoppable from the notification, the full screen and the volume keys;
    - Health shows why something will or won't ring;
    - meetings found in two calendars ring once;
    - no account, no ads, no analytics, and your calendar stays on your phone;
    - Android 8 and later.

    No competitor names, no "best", no em dashes.
  - **Category:** Productivity. **Tags:** chosen in Play Console from its list (alarm, calendar, productivity).
  - **Contact:** website `https://fifothehein.github.io/tminus/`; email set in Play Console only (decision 5).
  - **Graphics:**
    - icon `docs/play/icon-512.png`;
    - feature graphic `docs/play/feature-graphic.png`;
    - 4 to 8 phone screenshots from Task 9, at 1080 × 2400 or the emulator's native size, which Play accepts.
- [ ] **Step 2: `docs/play/declarations.md`.** One section per Play Console App content item, each with the answer to enter and why:
  - **Privacy policy:** `https://fifothehein.github.io/tminus/privacy/`.
  - **App access:** "All or some functionality is restricted". Instructions: "Open the app, tap Get started, choose Add a published link, paste `https://fifothehein.github.io/tminus/play/demo.ics`, tap Check, then Add calendar. Allow notifications. A demo meeting starts every two hours; Health → Upcoming alarms lists them, and the onboarding test alarm rings within seconds. With the default profile, each demo meeting rings a heads-up 10 minutes before it and a full-screen alarm 1 minute before it, so the phone rings every two hours. To stop it, use Mute today (Agenda header or the quick-settings tile), or remove the calendar in Sources."
  - **Ads:** No.
  - **Content rating:** the IARC questionnaire. Category Utility/Productivity. No violence, sexual content, language, drugs or gambling. No user interaction between users, no sharing of location, no purchases.
  - **Target audience:** 18 and over, not designed for children, so no Families policy applies.
  - **Data safety:** no data collected, no data shared. This is the plan's reading of Play's rules; Task 10's reviewer checks it against Play Console's Data safety help on the day the form is filled in, and records any change here. Every question about collection is answered "No", because the app sends nothing to the developer or third parties (Play counts only data transmitted off the device by the app to the developer or others; calendar fetches go to the user's own provider, at the user's request). "Is all of the user data collected by your app encrypted in transit?" does not apply. Data deletion: no account, so no deletion request mechanism is needed; uninstall removes everything.
  - **Government app, Financial features, Health, News:** No.
  - **Advertising ID:** No (Task 4 Step 5 confirms the merged manifest has no `AD_ID`).
  - **Exact alarms:** core functionality "alarm / calendar". Text: "T-Minus is a meeting alarm app. Its core function is ringing an alarm at an exact minute before each calendar meeting, as set by the user, so the alarm must fire on time even in Doze."
  - **Full-screen intent:** "core functionality: alarm". Text: "The app's alarms ring full screen, on the lock screen, at the time the user set before a meeting, like an alarm clock. Users can always stop them from the screen, the notification or the volume keys."
  - **Foreground service, type `systemExempted`:**
    - Description: "When a meeting alarm fires, a foreground service plays the alarm sound on the alarm stream, vibrates and keeps the full-screen alarm alive until the user stops or snoozes it, or the ring timeout ends."
    - Impact if deferred: "The alarm would ring late, after the meeting has started."
    - Impact if interrupted: "The alarm would stop ringing before the user noticed it, and they would miss the meeting."
    - Video: Task 9's link.
  - **Calendar permission:** no Play declaration (not a restricted permission). The policy explains it.
  - **If review rejects `USE_EXACT_ALARM`:** switch to `SCHEDULE_EXACT_ALARM` on every API level. That means removing `android:maxSdkVersion`, adding a Health and onboarding prompt (`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`) and handling `canScheduleExactAlarms() == false`, which Health already reports. That is a new task, not built in Plan 6.
  - **If review rejects `systemExempted`:** revert Task 2's commit (decision 2) and declare `mediaPlayback` with the same texts and video.
- [ ] **Step 3: `tool/gen_feature_graphic.py`.**
  - It imports the icon geometry from `tool/gen_launcher_icon.py`; it does not copy it.
  - It draws a 1024 × 500 PNG: the slate background from the theme tokens, the countdown mark at the left third, and "T-Minus" and "Meeting alarms you can't miss" in IBM Plex Sans (`assets/fonts/ibm-plex-sans/`) at the right.
  - It writes `docs/play/feature-graphic.png`.
  - The text is drawn with the bundled font, so the output is reproducible on any machine with Pillow.
- [ ] **Step 4:** Run the gates, then commit `Write the store listing and Play declarations and draw the feature graphic`.

### Task 9: Screenshots and the FGS video (scout, on the emulator)

**Deep review:** no. **Files:** `docs/play/screenshots/*.png`.

- [ ] **Step 1:** Install the release APK (Task 4) on the API 36 Pixel emulator, dark theme. Onboard with the demo feed. Wait until a meeting is 5–20 minutes away; adjust the emulator clock only through `adb shell cmd alarm set-time`, never by editing the feed.
- [ ] **Step 2:** Capture with `adb exec-out screencap -p > docs/play/screenshots/<n>-<name>.png`:
  1. the Agenda with countdown and chips;
  2. the event sheet showing why it rings;
  3. the full-screen alarm (test alarm);
  4. Alerts → Profiles;
  5. the quiet sheet;
  6. Health all green.

  Then 7 and 8: the Agenda and the alarm in the light theme. Check each for anything personal (no real names, no account emails in the calendar picker); retake if needed.
- [ ] **Step 3: The FGS video.** `adb shell screenrecord --time-limit 60 /sdcard/fgs.mp4`: Health → **Test alarm**: the alarm rings full screen in about five seconds, then Stop. A second clip shows a scheduled demo meeting's alarm firing on the lock screen, with the notification's Stop. Pull the files. The **user** uploads them to YouTube as **unlisted** and puts the link into `docs/play/declarations.md`.
- [ ] **Step 4:** Commit `Add the store screenshots`.

### Task 10 (user, with a review-worker first): Upload and declarations

- [ ] **Step 1: Review first.** A `review-worker` reads `docs/privacy.md`, `listing.md` and `declarations.md` against the code at `HEAD`, sentence by sentence (Review Focus 3). For example: the backup contents against `data_extraction_rules.xml`, `backup_rules.xml` and the tables in `tminus.sqlite`; the permission table against Task 4's merged manifest; the "no crash reporting" claim against `pubspec.lock`. Every false or unprovable sentence is fixed before Step 2.
- [ ] **Step 2:** Check that Task 5 Step 8's pages are live: the policy and the demo feed load in a browser, and the policy is the version the reviewer approved in Step 1. If Step 1 changed the policy, publish the change the same way: a small docs-only PR to `main`.
- [ ] **Step 3: Store listing.** Enter Task 8's copy and graphics, and Task 9's screenshots.
- [ ] **Step 4: Upload.** Testing → Internal testing → Create release:
  - Accept Play App Signing (Google holds the app signing key; ours is the upload key).
  - Upload `app-release.aab` with version `1.0.0+1`.
  - Release notes: "First internal test build."
  - A debug-signed bundle is refused here. If that happens, `key.properties` was missing (Review Focus 6).
- [ ] **Step 5: App content.** Answer every item from `docs/play/declarations.md`, including the FGS declaration with the video link. Record the date of each.
- [ ] **Step 6: Testers.** Add your own Google account (and any others) to the internal testing list, then open the opt-in link on the phone.
- [ ] **Step 7: Record** the review results and any rejection text in the run log. A rejection of `USE_EXACT_ALARM`, the full-screen intent or `systemExempted` follows `declarations.md`'s fallback section, as a new task.
- [ ] **Step 8: Pre-launch report.** When Play's pre-launch report is ready (Release → Testing → Pre-launch report), record its crashes, ANRs and accessibility warnings. Each crash or ANR becomes a fix task.

### Task 11: The ringing service across Android versions (scout, emulators)

**Deep review:** no. **Files:** none (run log only).

On system images for **API 26, 30, 33, 35 and 36** (create the AVDs if missing; use `-gpu swiftshader_indirect` as in Plan 5 decision 45), install the release APK and check:

- [ ] **Step 1:** The onboarding test alarm rings full screen, with sound on the alarm stream, and stops from the screen, the notification and a volume key.
- [ ] **Step 2:** `adb shell dumpsys activity services io.github.fifothehein.tminus | grep -i "foregroundServiceType\|types="` while it rings. API 34+ shows `systemExempted`; below 34 the service is in the foreground with the manifest's type.
- [ ] **Step 3:** A demo meeting's alarm (via `adb shell cmd alarm set-time` 1 minute before its alert) rings from Doze: `adb shell dumpsys deviceidle force-idle` first.
- [ ] **Step 4 (API 35 and 36):** Set the clock so an alarm falls 10 s after a reboot, then `adb reboot`. Record whether it rings at once, or 30 s later through boot recovery (decision 9), and whether logcat shows `refused the foreground`.
- [ ] **Step 5:** Record a line per API level. Any failure to ring is a stop: report to the user before Task 12.

### Task 12 (user): The phone, from the Play build

**Files:** none (run log). On the user's phone (the Samsung S24 used for the grouping checks), installed **from Play internal testing**. Steps 2–9 also close Plan 5's blocked steps.

- [ ] **Step 1: Switch from the debug build** (decision 15).
  - On the debug build: Settings → **Export**, save the file.
  - Uninstall the debug build. Its signature differs, so Play cannot update over it.
  - Install from the internal testing link.
  - Onboarding, then Settings → **Import**. Re-link each feed and re-pick each phone calendar.
- [ ] **Step 2: https with the real feed** (Plan 5 decision 46). Add the real published Outlook link. "Found N events this week", and the first sync fills the Agenda. Also a Google ICS link if you use one.
- [ ] **Step 3: Cache safety.** Note the Agenda's meetings. Airplane mode. Force-stop and reopen the app: the same meetings, the same chips. Toggle one meeting: Health's upcoming alarms change within about 2 s.
- [ ] **Step 4: The tile from the lock screen** (with your PIN set): pull down quick settings on the lock screen, tap **Mute today**. Unlock: the Agenda shows the mute. Tap again: ended.
- [ ] **Step 5: The spec §11 checklist** on the Play build:
  - locked;
  - silent;
  - DND (the alarm rings, a heads-up respects it);
  - `adb shell dumpsys deviceidle force-idle`, then an alarm rings;
  - reboot before unlock: an alarm due 2 min after the reboot rings on the lock screen;
  - reboot after unlock;
  - a time zone change;
  - the app swiped away from recents;
  - Samsung's "Put unused apps to sleep" and battery settings, as Health's maker tips describe.
- [ ] **Step 6: Boot window** (decision 9). An alarm due within 30 s of a reboot: record whether it rang at once or 30 s later.
- [ ] **Step 7: Full-screen intent.** Health shows full-screen alerts allowed. If Play has not approved the declaration yet and Android 14+ shows it off, Health's fix opens the setting. Record which.
- [ ] **Step 8: Backup without the cache** (Plan 5 decision 47).
  - `adb shell bmgr enable true`, then `adb shell bmgr list transports`. The Google transport (`com.google.android.gms/.backup.BackupTransportService`) must be the selected one: Settings → Google → Backup on, with the phone signed in.
  - `adb shell bmgr backupnow io.github.fifothehein.tminus`. The output must end with `Backup finished with result: Success`.
  - Uninstall, then reinstall from Play (restore runs on install).
  - Expected: profiles, rules and source names are back. Every feed shows **needs link** and every phone calendar **needs calendar**. The Agenda is empty until a calendar is set up, and Health's history is empty.
  - `adb shell run-as` cannot read a release build, so check with the app only.
- [ ] **Step 9: Device transfer** (`is_device_transfer`, not run in Plan 5), if a second phone is at hand: Smart Switch or Google's transfer to the second phone. Same expectations as Step 8.
- [ ] **Step 10: The new pieces.** In the phone's account settings, turn off sync for a phone calendar you added. Within a sync, the source is red with "Calendar is not syncing" and one notification. The alarms stay. Turn sync back on: green again.
  - Add a second calendar whose name clashes with an existing one: its default name has the kind.
  - About and onboarding open the privacy policy.
- [ ] **Step 11:** Record a line per step: PASS, FAIL or BLOCKED with the reason. Each FAIL becomes a fix task in this plan, with the usual gates and a negative control.

### Task 13: Record what Plan 6 changed

**Deep review:** no.

**Files:**
- the spec (§7 permissions and Firing: `systemExempted`; §10: the cache is not backed up; §12 check 4 marked done);
- the roadmap (Plan 6 row → this file; decisions 2 and 3 marked done; §3 already edited by Task 6; the follow-ups list cleared of the three items);
- CLAUDE.md (two databases: which tables live where, and that `tminus_cache.sqlite` is never backed up; the release-build and `key.properties` rules);
- README (status);
- this plan's "Built differently" section and run log.

- [ ] Run the gates, then commit `Record what Plan 6 built`. Open the PR to `main`, with Task 11's and Task 12's results in the description.

---

## Self-review

The roadmap's Plan 6 decisions and items, and where each is handled:

| Item | Task |
|---|---|
| Decision 1: internal testing only | Goal, Task 10 |
| Decision 2: `systemExempted`, `mediaPlayback` fallback | Task 2; fallback in Task 8 `declarations.md` |
| Decision 3: policy on Pages | Task 5 |
| Decision 4, exact alarms: eligible, kept; `SCHEDULE_EXACT_ALARM` fallback | Task 8 (declaration, fallback), Task 10 |
| Decision 4, full-screen intent declaration | Task 8, Task 10, Task 12 Step 7 |
| Decision 4, FGS declaration and video | Task 8, Task 9 Step 3, Task 10 |
| Decision 4, target API 36 | Already 36; Task 4 Step 5 reads the merged manifest |
| Decision 4, closed testing | Out of scope (Goal) |
| Item 5: upload keystore | Task C, Task 4 |
| Item 5: launcher icon (done in #18) | Task 4 Step 7 and Task 10 check it in the release build and on the listing |
| Item 5: 16 KB pages | Task 4 Step 6 |
| Item 5: R8 and logging on a release build | Task 4 Steps 5 and 7 |
| Item 5: version scheme | Decision 13, Task 4 Step 8 |
| Item 5: device checklist on the Play build | Task 12 |
| Item 5: developer verification | Task B |
| Item 6: the three grouping follow-ups | Tasks 6 and 7 |
| Spec phase 1.5: trademark search | Task A |
| Spec phase 1.5: onboarding polish | Task 5 (privacy link), Task 12 (fix tasks) |
| Spec §10: release builds turn off verbose logging | Already true: no `Log.d`/`Log.v`, and Dart logs only types and codes. Task 4 Step 7 checks logcat on the release build |
| Plan 5 blocked steps | https: Task 12 Step 2. Tile on the lock screen: Step 4. Pre-Plan-5 backup and API 30: Task 11 (API 30), Task 12 Step 8. `is_device_transfer`: Step 9. Next week's instance and a 5xx over 24 h stay untested: they need a faked clock, and Plan 4's unit tests cover their logic |

## Not covered

- The closed test, production access and the production release.
- Removing `RECOVERY_DELAY_MS`: a follow-up if Tasks 11 and 12 show `systemExempted` starts at boot (decision 9).
- A debug build that installs beside the Play build (decision 15).
- Localisation of the listing and the app.

## Built differently from this plan

**Task 2** (38f22bd):
- `NO_TYPE` is `internal`, not private, so the SDK 33 test can name it.
- `onStartCommand` also catches `IllegalArgumentException` (a type the manifest does not declare, e.g. a half-done revert) and sends it to `refuseForeground`, like the other two refusals (deep review).
- `refuseForeground` logs the exception's class only, not the exception (CLAUDE.md's logging rule); the phrase `refused the foreground` is kept for Task 11's logcat check.
- Tests beyond Step 4:
  - the SDK tests also assert the Robolectric shadow's foreground type;
  - the manifest test also asserts `USE_EXACT_ALARM`;
  - a `SecurityException` refusal and an `IllegalArgumentException` refusal each fall back to a heads-up;
  - the refusal log holds no message or trace.
- RingingService's class KDoc and `refuseForeground` KDoc are reworded too.
- Decision 2 says the fallback is "a one-line manifest revert plus the old `foregroundType()`". It is two manifest lines plus the function; reverting 38f22bd does it in one step.

**Task 2b** (6669ad8, not in the plan; R14):
- Every main-code Kotlin `Log.*` call that passed an exception now logs only the class name, keeping its wording: 11 lines in 10 files.
- `AlarmEngineChannel` answers `bad_args` and `engine_error` with a null message; the codes are unchanged, and Dart reads only codes. The Developer tools panel now shows the code where it showed the message.
- RingingService's tone fallback logs list positions, not tone URIs.
- 14 ShadowLog and channel tests plant a secret in each error and check it never reaches a log or Dart. Shared helpers live in `LoggedErrors.kt` and `RefusingShadows.kt`.
- Left alone: the Flutter-generated `GeneratedPluginRegistrant.java`; one em dash in a pre-existing test fixture (`SyncChannelTest.kt:134`).

**Task 3** (3b246a4):
- **The `from < 2` step** uses drift's generated `Schema2` classes (`dart run drift_dev schema steps drift_schemas/ lib/core/storage/schema_versions.dart`, a generated 1140-line file: never edit or format it), not the exact-SQL fallback. It also gains one guard (R15): `ical_uid` is added only when `occurrences` exists and lacks it. CLAUDE.md says never edit a shipped step; this guard keeps the step's meaning for every file it shipped for. It stops a file whose v3 step already ran from failing every open.
- **`LegacyCacheMove`** runs as three separate transactions:
  1. a `from` transaction reads the existence checks and every 500-row page into memory;
  2. one cache transaction inserts them with `INSERT OR IGNORE`, together with a `cache_values` marker `storage.legacyMoved`;
  3. a `from` transaction drops each legacy table that still exists and deletes the old settings row.

  The plan paged the reads inside one cache transaction. In that shape, a table dropped by the other isolate between check and read fails the open, and drift cannot nest one database's transaction inside another's. The marker is checked before the read and again inside the copy transaction, so a stalled second isolate cannot bring back a meeting the first one's sync removed. Column lists come from `PRAGMA table_info`, intersected with the cache table's columns.
- **R9:** `sync.missedSystemExpected`, which holds upcoming meeting titles, moves from `settings` into a `cache_values` table in the cache database. `SyncService` takes the cache values, and the legacy move carries the old row over.
- **R16:** `tminus.sqlite` gets `secure_delete = ON`. It is compacted once after the move (`VACUUM`, then `wal_checkpoint(TRUNCATE)`), with best-effort retries until the `settings` marker `storage.compactedV3` is set. The pause checkpoint is `TRUNCATE`, so it can wait up to the 5 s busy timeout while a headless sync writes. Upgraded phones' backups then hold no old meeting bytes.
- **Screens:** Agenda, Sources and Source detail listened only to `AppDatabase.tableUpdates()`; they now also listen to the cache (a plan gap). `runHeadlessSync` and `configureDependencies` take `openCacheDatabase`. A test that passes only `openDatabase` gets an in-memory cache.
- **Not built:** `CacheDatabase.checkpoint()` (the cache is never backed up).
- **Failures and deletes:**
  - A failed cache open stays failed until the process restarts, because drift caches it. Nothing plans meanwhile, so Kotlin keeps its alarms.
  - `RestoreGuard`'s post-commit cache clear is try/caught and keeps the outcome `restored`.
  - `SourceAdmin._cleanUp` catches everything, and the cache step runs last in `delete`, so a cache error cannot skip deleting the link.
  - `updateDeviceCalendar` clears the old calendar's cache before its transaction. If that transaction fails, the source keeps its old calendar with an empty cache until the next fetch.

**Task 6** (12f102b):
- The card body for the new cause comes from a new pure `problemBody(status)` in `problem_card.dart`, which the detail screen now calls. The plan put the text under problem_card, but the screen used to pass the status line as the body. A source still waiting for its calendar keeps its old body.
- The button stays `Choose calendar`, where decision 18's prose says "Choose another calendar".
- `test/core/sync/outcome_severity_test.dart` was missing from the plan's file list. Its two exhaustive tables now name `calendarNotSynced`.
- Extra tests beyond Step 3:
  - one of several asked calendars being off refuses the whole ask (a source only ever asks for one);
  - a calendar that is off but not asked for does not matter;
  - a missing calendar is reported before a not-synced one;
  - the notice is withdrawn on recovery, and a new spell posts a new one.
- A not-synced phone source gets one Feed broken notice and no Feed stale notices afterwards (those cover link sources only), as `calendarMissing` does.

**Task 8** (af0e747):
- The App access text differs from the plan's draft, because the code does:
  - the real flow is Get started, Paste a calendar link, ICS link, Check, Add calendar, Continue, permissions, Ring a test alarm;
  - the 12:00 UTC demo meeting is free and skipped by default;
  - Mute today is reached through the moon (Quiet modes) button, and the tile is left out;
  - "a full-screen alarm" became "an alarm", and Health lists the next five alerts.

  A 469-character short form was added.
- **Listing:**
  - Health shows whether alarms can ring, while the Agenda and the event sheet show why a meeting rings;
  - the volume keys stop an alarm only on the full-screen alarm;
  - keyword rules match words, or whether a meeting has a Teams link;
  - Join appears only for meetings with a link;
  - a trademark and independence paragraph was added.
- **Declarations:**
  - the FGS description says what the service does: sound, vibration, wake lock, and the ringing notification with its full-screen intent;
  - a `USE_FULL_SCREEN_INTENT` fallback, R12 in the `SCHEDULE_EXACT_ALARM` fallback, and a manifest reference table were added;
  - the FGS video is a placeholder line until Task 9.
- **Feature graphic:** `tool/gen_feature_graphic.py` loads `gen_launcher_icon.py` by path and draws with its geometry and colour tokens. Its `check_vectors()` stop does not notice a change to one of two equal `strokeWidth` lines, so `test/launcher_icon_test.dart` stays the exact guard. That test also pins the graphic as a 24-bit RGB PNG.
- **R18, the user's choice:** `docs/_config.yml` keeps everything but `index.md`, `privacy.md` and `play/demo.ics` out of the Pages site, and `test/app/pages_config_test.dart` fails on any new docs/ file that is neither public nor excluded. Not done (optional review notes): the test does not reject a top-level `include:` key or a nested `exclude:`.

**Task 5** (b01e7d3):
- **The privacy policy's text differs from Step 2.** The review found sentences that were not true of the code, and they were replaced:
  - the Calendar permission also lists the phone's calendars;
  - meetings include busy/free, declined and cancelled;
  - the cache holds a 30-day alarm history with titles;
  - the backup is end to end encrypted from Android 9, not on Android 8;
  - device transfer copies the same settings;
  - what a calendar fetch sends, and that http links are not encrypted;
  - the export file holds settings and outlives an uninstall;
  - a Network state row is added to the permissions table;
  - Google Play's own crash and install statistics are mentioned.

  Task 10's review checks the committed text, not the plan's.
- The effective date is 14 November 2026 (R6).
- The About card puts the name and version on their own row, with Privacy policy and Licences side by side in a `Wrap` below it. In one row they overflowed the 360 dp test by 104 px.
- Each screen has its own `_openPrivacyPolicy` (10 lines); `links.dart` holds constants only.
- `demo.ics` has a `DTSTAMP` on every VEVENT (RFC 5545), CRLF line endings committed as such (R8), and demo-00 is "Morning planning".
- Extra tests: the policy page is finished and names the issues page; the demo feed has no links, one Free and one located meeting; an open that throws shows one snackbar and logs only the code. The onboarding large-text test also checks that the Welcome heading stays inside the page.

**Task 7** (51a4842):
- `AddSourcePanel._addDevice` reads the phone's calendars a second time (`DeviceCalendarApi.calendars()`) to find clashes with calendars that were not ticked. The picker's `onAdd` hands over only the ticked ones, and `calendar_picker.dart` does not change. If that read fails, names are worked out from the ticked list, the add goes on, and only the code or type is logged.
- `defaultSourceName` returns the trimmed name, not only compares it trimmed. A blank name both reads and compares as `Phone calendar`.
- `existingSourceNames` is every source's name: link and phone sources, enabled or not.
- The kind comes from `groupCalendars` run over the whole phone with the calendar in it once, so it follows the grouping rules exactly.
- 13 tests beyond Step 4's list; a comment beside the first `isFalse` says why it is stricter than `isNot(isTrue)`.
- The debug-only sync panel (`lib/features/token_preview/sync_debug_panel.dart`) still adds phone calendars under their own name.

**Task 4** (7416baf):
- Built as two jobs (R20): a dev-worker did Steps 1-3 and 8, and a scout did the release builds and checks of Steps 4-7.
- `build.gradle.kts` warns with `logger.quiet`, not `warn`, because Flutter runs Gradle with `-q`. The warning shows only for release tasks.
- A `key.properties` that lacks an entry fails the build. The error names only the missing entries, never a value.
- `ndk { debugSymbolLevel = "SYMBOL_TABLE" }` keeps native symbols for Play's crash reports.
- `BackupRulesTest` also covers the `-shm` file and the included folders. `android/.gitignore` also ignores `*.p12` and `.kotlin/` (R13).
- `release.md` checks the APK with apksigner and adds a "what is in the release" section.
- The 16 KB check ran without bundletool (R21), and the smoke test used a local http feed (R22).
- The privacy policy's device-transfer sentence now says the settings "can be copied" (deep review): it is unconfirmed whether Android 9-11 include `requireFlags` files in a phone-to-phone transfer.
- The smoke test's tile finding became F1, and its ANRs became follow-up R24.

**F1** (48a1351, not in the plan; R25):
- Task 4's release smoke test reported that a second tap on the Mute today tile asked for Mute again. The tile was found to have no defect: `QuietStore.display()` and `actionForTap()` already follow a waiting or in-flight request (Plan 5 decision 18). The emulator's second run shows correct operation. The first run's log was lost.
- No production change. `QuietTapSequenceTest.kt` adds six tests that drive the real tile service, store, channel and scheduler, including every order of seven taps and syncs (about 15 s).
- The only code path that matches the symptom is a taken request lost to a killed run, which is recorded as follow-up R26.

**F2** (785e70b, not in the plan; R28):
- Task 11's reboot step on API 36 twice saw no ring for an alarm due during the boot. The redo was not valid evidence: its alarm had rung and been dismissed in the Doze step, and both the planner and the engine keep a dismissal for 24 h.
- While reproducing the sequence, a real loss was found: boot recovery arms an overdue alarm for the end of the 30 s window, a headless sync's `applyPlan` then fires it at once (`reconcile`) and cancels that recovery alarm, and if Android refuses the service start (Android 12+ refuses a background foreground-service start once the boot allow-list ends), the presenter only posted a heads-up and armed nothing.
- `AndroidAlertPresenter` now arms the same single retry that `RingingService.refuseForeground` arms (30 s, through AlarmManager); the retry's own presenter passes `retryRefusedStart = false`, so a refused retry is not retried again. `BootRecoveryAcrossSyncTest` adds 4 tests. Deep review: ship.

## Run log

Bookmark for the run. Stamps are local time (+0200).

**Run session:** "Plan 6: build Play readiness", started 2026-11-14T22:45:22+0200 on Opus 5.5, effort high, branch `claude/plan-6-play-readiness-build-fe4abe` from `main` cb3ae71.

**Run session 2:** "tminus-59 · Plan 6 play readiness build", resumed 2026-11-18T11:08:47+0200 on Opus 5.5, effort medium (the skill asks for high; recorded, not switched). Bookmark on resume: HEAD edef728, which the run log did not record (R32). Task 11 had no row; Tasks 12 and 13 not started.

**Stopped at** 2026-11-18T13:13:44+0200 (R41, the user restarts the desktop app). Done this session: F3 and F3a (0e637c6), the 1.0.1 release build, Task 11 on API 36 and API 35. Next, in order: (1) decide F4 and the Agenda check (R42); (2) Task 11 legs API 33, 30, 26 (AVDs ready); (3) in Play Console, the new Sign-in text (R33) and the 1.0.1 upload (R35; the user's Chrome would not connect to session 2, so check Claude in Chrome first, or use the built-in browser with the user's sign-in); (4) Task 10 Steps 7-8; (5) Task 12 on the phone; (6) Task 13 and the PR. The branch is not pushed.

**Decisions taken while running** (each can be overturned):
- R1. The plan is run in its lightweight form (Execution line). It has no orchestrate template sections, so each task's **Files** list stands for its `OWNS` and its Gates for its `ACCEPTANCE`. No time booking.
- R2. Wave 1 does not wait for Tasks A and B. Nothing in Tasks 2, 3, 5 or 7 depends on them. Task A gates Task 8's listing name, Task B gates Task 10, Task C gates Task 4.
- R3. Task 1 Step 1 runs as `git fetch` plus an ancestry check: the worktree cannot check out `main`, which the main checkout holds.
- R4. Each task's dev-worker writes the tests its plan step names, in the same job; the plan defines no separate test-author jobs. Each new test's negative control is run by the worker, then re-run by the test runner where the reviewer names it.
- R5. While a wave runs, workers run only their own targeted `flutter test` files; only the Kotlin task runs Gradle. The full suite runs once per task as its acceptance, through the scouts.
- R7. (User, 2026-11-15) An emulator check runs once Wave 1 is committed, on the Pixel_9 AVD (API 36, `-gpu swiftshader_indirect`), by a scout. Debug builds:
  - install `main`'s build and fill the cache with the debug fast-alarms source, then install the Wave 1 build over it, which upgrades the database in place: the Agenda and Health's upcoming alarms keep the same meetings (Review Focus 1);
  - an alarm rings and `dumpsys activity services` shows `systemExempted`;
  - About and onboarding show the privacy policy link;
  - a second calendar with a clashing name gets the kind label, if the emulator has a phone calendar to pick.

  The plan's own emulator steps (Task 4 Step 7, Tasks 9 and 11) still run on the release build.
- R8. `docs/play/demo.ics` is committed with CRLF line endings (RFC 5545), staged with `git -c core.autocrlf=false add` and checked with `git ls-files --eol` (`i/crlf`). The repo has `core.autocrlf=true` and no `.gitattributes`, so a plain add would store LF.
- R9. (Task 5 review, blocker B1) `sync.missedSystemExpected` holds each upcoming alarm's meeting title and lives in `settings` in the backed-up `tminus.sqlite`. It moves into a key-value table in `CacheDatabase` as part of Task 3, with `LegacyCacheMove` moving the old row on upgrade. Without this, the policy's backup sentence and Review Focus 3 would be false.
- R10. The privacy policy's wording changes from the plan's Step 2 text (Task 5 review: A to I). Task 5 Step 8 publishes the pages only after Tasks 3 (with R9) and 4 are committed, because the backup sentences depend on both.
- R11. Task 2's deep review stands in for its standard review; the deep reviewer re-reviews the fix. Task 2 is committed alone (its seven android/ files), so decision 2's one-commit revert holds.
- R12. (Task 2 deep review) Task 8's `declarations.md` fallback section must say: falling back from `USE_EXACT_ALARM` to `SCHEDULE_EXACT_ALARM` makes `systemExempted`'s prerequisite on API 34+ a permission the user can revoke, so that fallback also needs the `mediaPlayback` fallback (or a ring path that works without the grant).
- R13. Kotlin 2.x leaves an untracked `android/.kotlin/` folder after a Gradle build. Task 4, which already edits `android/.gitignore`, also adds `.kotlin/` there.
- R14. (Task 2 fix) Other Kotlin sites still pass an exception object to `Log` (JoinActivity, AndroidAlertPresenter, AlarmEngineChannel, PlanStore, EventQueue, CrashSilencer, SyncNotifications, NotificationFactory, PreSyncScheduler, AlarmScheduler). An exception's message can quote a join link or event text, against CLAUDE.md's logging rule and the release logcat check (Task 4 Step 7). A fix job, "Task 2b", makes them log the class name only. It runs after Task 2 is committed, as its own commit, by the same worker in Wave 1's Gradle slot.
- R15. (Task 3 deep review) The shipped `from < 2` step gains one guard: it adds `ical_uid` only when `occurrences` exists and lacks the column. CLAUDE.md says never edit a shipped step. This edit keeps the step's meaning for every input it ever ran on and stops a file that already ran the v3 step from failing every open. The user can overturn it.
- R16. (Task 3 deep review) `tminus.sqlite` gets `secure_delete = ON`, a one-time best-effort `VACUUM` plus `wal_checkpoint(TRUNCATE)` after the legacy move, and a TRUNCATE checkpoint on pause, so no meeting text stays in the backed-up file's free pages or WAL.
- R17. Task 8 (Wave 2) starts while Task 3's fix is still running. It shares no file with Task 3 and needs only Task 5's committed URLs and Task A's name. Task 6 waits for Task 3, because both edit `sync_service.dart`, `sync_service_test.dart` and `source_detail_screen.dart`.
- R18. (User, 2026-11-15) GitHub Pages publishes only the public pages: `docs/_config.yml` excludes everything under docs/ except `index.md`, `privacy.md` and `play/demo.ics`, and a test pins that. Built in Task 8, it goes into Task 5 Step 8's docs-only PR, so it takes effect when the pages go online.
- R20. Task 4 is split in two jobs. A dev-worker does Steps 1, 2, 3 and 8 (Gradle signing, backup rules and their test, the signing-material test, release.md). A scout then does Steps 4 to 7 (release builds, signature check, merged manifest, 16 KB check, emulator smoke test). Builds and smoke tests are test runs, which scouts do.
- R21. The 16 KB check (Step 6) runs without bundletool, which is not on this machine and would be a download. It reads LOAD alignment with the NDK's `llvm-readelf` on the AAB's and the release APK's arm64 `.so` files, and runs `zipalign -c -P 16` on the release APK.
- R22. The release smoke test (Step 7) serves the demo feed over local http (10.0.2.2:8765, as the emulator check did), not from the branch's raw GitHub URL. That URL would need a push, and the Pages copy is not live yet.
- R23. Follow-up, not built in Plan 6: on Windows, Robolectric tests that rename a temp file over the target (PlanStore `state.json`, EventQueue `events.jsonl`) fail about once in ten full runs with `AccessDeniedException`, likely an indexer or antivirus lock. On Android a rename over the target is atomic, so the app is not affected. A retry in the test helper, or a move with `REPLACE_EXISTING`, would remove the flake.
- R24. Follow-up, not built in Plan 6: the engine's AlarmManager calls (`setExactAndAllowWhileIdle`, `setAlarmClock`) run on the main looper from the method channel. When system_server is slow, a Binder call can block input for more than 5 s and show an ANR, as on the overloaded emulator. Moving `applyPlan`'s scheduling to a background thread would remove that risk. Task 12 on the phone shows whether it matters on real hardware.
- R25. A defect found by Task 4's smoke test becomes a fix job inside this plan (decision 7's rule for Task 12, applied early): F1, the Mute today tile's second tap.
- R26. Follow-up, not built in Plan 6 (F1 review): a tile request that a sync has taken but not applied is lost if that run is killed or throws between `takeQuietRequest` and `setQuietStateAt`, and any later run's `configure` clears it. Plan 5 decision 18 accepts this. The fix would make the take an acknowledged hand-off: Dart confirms after `setQuietStateAt`, and Kotlin queues an unconfirmed request again when the next run starts or when `IN_FLIGHT_MS` passes. The in-flight age would also count from the take, not from the tap.
- R27. Follow-up, not built in Plan 6 (Task 9): on a phone set to 12-hour time, the native alarm screen and notifications follow the phone's setting (`AlertText.forDevice`, `DateFormat.is24HourFormat`), while the Flutter screens always show 24-hour times. The emulator showed "9:46 PM-10:16 PM" on the alarm beside 21:45 on the Agenda. One rule for both would remove the mismatch. The store screenshots are taken in 24-hour mode.
- R28. (Task 11) A defect found on the emulator becomes fix job F2 (R25's rule): an alarm lost when Android refuses the ringing service start from a sync. Built and committed in Plan 6.
- R29. Follow-up, not built in Plan 6 (F2 deep review): decision 9's "nothing rings inside the boot window" does not hold when a sync, a clock change or an app start lands in the window: `reconcile` fires overdue alerts at once (EngineActions.kt ~80-85), and `applyPlan`'s kept re-arm moves in-window alerts back to their real time (AlarmScheduler.kt ~36). The alarm still rings (at once, or through F2's retry). A boot-window end kept in PlanStore, honoured by `reconcile` and `applyPlan`, would restore the rule; Task 11 Step 4 and Task 12 Step 6 decide whether it matters.
- R30. Follow-up, harmless: PlanDiff drops an overdue alert of an occurrence the plan no longer lists but leaves its alarm armed (PlanDiff.kt ~44); it fires once and does nothing.
- R31. Follow-up: counts-only `Log.i` lines in `EngineActions.reconcile`/`recoverAfterBoot` and `AlarmReceiver` retry would let a device run tell which path rang an alarm after a reboot. Also, a retry does not check whether the event has ended, so a meeting that ends inside the 30 s still rings once.
- R32. (Session 2) edef728 ("List the phone calendar first and open neither way at the start", version 1.0.1+2) was committed at 08:43 on 2026-11-18 after the run log's last entry, with no recorded check or review. It is treated as fix job F3: a scout re-runs the full gates on it and the review-worker reviews its diff before any 1.0.1 build is released.
- R33. (Session 2) Play Console's App content, Sign-in details still hold the 469-character text for 1.0.0, which does not say to tap "Paste a calendar link" first. Before 1.0.1 is uploaded or sent for review, the user replaces it with the 497-character short form from `declarations.md` (or the 918-character full form). The old text still works on 1.0.0.
- R34. (Session 2) Task 11 left no per-API record. It runs again in full on the 1.0.1 release APK (the build testers get next), on API 26, 30, 33, 35 and 36. The 1.0.1 bundle goes to internal testing only after Task 11 passes and R33 is done.
- R35. (User, 2026-11-18) The orchestrator may use Play Console in the user's Chrome to correct the Sign-in text (R33) and upload 1.0.1 when it is ready. The final Release / Send for review click is confirmed with the user first.
- R36. (F3 review) F3a adds one semantics test for the add-calendar cards' checked state before the 1.0.1 build, because the cards are now the only way into either path. A dev-worker writes it in `add_source_panel_test.dart` only, with `checked: false` at line 409 as its negative control. The missing expanded flag is left as a note: the cards are usable with TalkBack, and adding it is a UI change outside this plan.
- R37. (Session 2) Negative controls and test runs go to the scout test runner, never to a dev-worker, as R4 implied for earlier waves. F3a's brief broke this rule and the worker rightly declined. Its controls run through the runner.
- R38. (Task 11, API 36) Step 4 counts as a pass. The 70 s from the alarm's time to the ring is the emulator's: Android delivered `BOOT_COMPLETED` 50 s after `sys.boot_completed` on the software GPU, and the app rang 17 s after its receiver ran, inside decision 9's 30 s recovery window. The heads-up instead of the full screen is Android's own rule for a full-screen intent while the screen is on and unlocked. Task 12 Step 6 times the boot window on the phone.
- R39. (Task 11, API 35) Step 5 makes a failure to ring a stop before Task 12. Before reporting it as a defect, the API 35 leg's Step 4 runs again with a log streamed from the moment adb reconnects and a wait of up to 6 minutes after `sys.boot_completed`, and the Step 3 ANR is reproduced with its trace read from `dumpsys dropbox` (`data_app_anr`). Legs 33, 30 and 26 wait for that result. The first rerun scout (12:45) stopped before starting: another session's Transport `vstest.console` run (started 12:45:44) was busy, and the scout's one-test-run rule held. The rerun waits for it to exit, which also keeps the host's CPU free for the boot timing.
- R40. (Task 11, API 35) The second rerun (12:49) was blocked by a "Pixel Launcher isn't responding" dialog that came back after every Wait, so neither part ran. The tablet Play image on the software GPU overloads the system (SystemUI, the launcher and Google apps all stop responding), which also weakens the first leg's findings. The next try boots with `-memory 4096 -cores 4`, and the scout may tap Close app on another app's "isn't responding" dialog, never on T-Minus's. If the image still cannot run cleanly, a lighter API 35 phone image (`google_apis`, x86_64) is the fallback, after the user's go-ahead for that download.
- R41. (User, 2026-11-18) Pause after the third API 35 try so the user can restart the Claude desktop app (Claude in Chrome would not connect to this session). The run log is committed before the pause.
- R42. (Task 11, API 35) R24 is no longer only a risk: on the emulator the engine's AlarmManager calls on the main thread caused an input ANR (from `TimeChangeReceiver`) and, at boot, a background ANR that killed the process 10 s after it re-armed 150 alerts. The alarm still rang, because the boot-recovery alarm was already armed. Proposed fix job F4 (overturnable, decided at the next session's start): move the scheduling in `AlarmScheduler` and the receivers off the main thread (a `goAsync()` receiver with a background executor; the method channel replies when done), with a deep review and Robolectric tests. Also check whether the Agenda shows a dismissed alarm as the next alarm (the "Product demo" mismatch); if so, a small fix job. Legs 33, 30 and 26 wait for this decision.
- R6. The policy's effective date is written as 14 November 2026, and updated if Task 5 Step 8's pages PR merges on a later day.
- R19. R7's emulator check moves to after Wave 2, so it also covers Task 6 and does not compete with Task 6's Gradle runs (one Gradle build at a time).

**Wave 1 closed 2026-11-16T00:12.**
- Commits: 51a4842 (Task 7), b01e7d3 (Task 5), 38f22bd (Task 2), 6669ad8 (Task 2b), 3b246a4 (Task 3).
- Evidence on the final content: full `flutter analyze` clean and full `flutter test` +1248 all passed (Task 3's last check, same content as 3b246a4 plus Task 8's uncommitted files); Kotlin suite 323 tests, 0 failures (Task 2b's fresh `--rerun-tasks` run; Task 3 changed no Kotlin).
- No negative control survived.
- Wave 2: Task 8 in progress (R17); Task 6 dispatched 2026-11-16T00:12.

**Wave 2 closed 2026-11-16T05:02.**
- Commits: af0e747 (Task 8), 12f102b (Task 6).
- Evidence on 12f102b's content: full `flutter analyze` clean, full `flutter test` +1257 all passed, Kotlin `--rerun-tasks` 328 tests, 0 failures.
- No negative control survived.
- Next: the emulator check (R7, R19), then Wave 3 (Task 4; Task C is done).

**Emulator check (R7, R19), 2026-11-16 05:05 to 05:30**, on the Pixel_9 AVD (API 36). Debug builds: `main` at cb3ae71 and the branch at d3b1d5f.
- **The old build installs and onboards with the demo feed** (served over local http at 10.0.2.2:8765). Check found 84 events this week and showed the http warning, and the test alarm rang. An earlier copy installed on 2026-11-09 had to be uninstalled first. The old build's first cold start after boot showed two "isn't responding" dialogs (System UI, then T-Minus) before it came up. It was not investigated: the emulator had just booted on a software GPU.
- **The cache upgrade keeps every meeting: PASS.** After `adb install -r` of the new build, the Agenda is identical: Team stand-up 04:00 (past), Design review 06:00, 1:1 with Sam 08:00, Sprint planning 10:00. Health's upcoming alarms are identical too: 05:50, 05:59, 07:50, 07:59, 09:50. `app_flutter` now holds `tminus_cache.sqlite`, and `tminus.sqlite` went from 172032 to 65536 bytes.
- **systemExempted while ringing: PASS.** During the test alarm, `RingingService` shows `isForeground=true types=0x00000400`. No "refused the foreground" appears in logcat. Stop ends the service.
- **Privacy links: PASS.** Settings, About & privacy shows Privacy policy and Licences, and Privacy policy opens Chrome. After `pm clear`, the Welcome screen shows the Privacy policy link.
- **Naming check: NOT RUN.** The image has no calendar provider; Task 12 on the phone covers it.
- **Logcat: PASS.** No demo.ics, no meeting title, and no 10.0.2.2 from the app's process; the 10.0.2.2 lines are the emulator's DHCP.
- The emulator is left running with the new debug build at fresh data.

**Wave 3 closed 2026-11-17.**
- Commits: 7416baf (Task 4), 48a1351 (F1).
- Evidence: Kotlin `--rerun-tasks` 336 tests, 0 failures, on the content of both commits (F1's worker run); `flutter analyze` clean and the docs tests +21 at Task 4's commit; full `flutter test` +1260 on Task 4's code before its doc-only fixes.
- No negative control survived.
- Next: Task 5 Step 8 (the docs-only pages PR, needs the user's go-ahead), Task 9 (screenshots), then Tasks 10 and 11.

| Step | State | Evidence | Commit |
|---|---|---|---|
| Task 1 preflight | done 2026-11-14T23:14. Step 3 on cb3ae71: `flutter analyze` No issues found; `flutter test` +1179 All tests passed; `:app:testDebugUnitTest` BUILD SUCCESSFUL, 303 tests, 0 failures (results land in `<worktree>/build/app/test-results/`, not `android/app/build`) | Step 1: HEAD = origin/main = cb3ae71, 1d01901 is an ancestor. Step 2: every name the plan uses exists (RingingService.kt:283 `foregroundType()` returns MEDIA_PLAYBACK from API 29, else 0; EngineActions.kt:186 `RECOVERY_DELAY_MS`; schemaVersion 2; tables.dart:53/168/194 with the one `references(Sources` at :56; restore_guard.dart:195-197; source_admin.dart:146/208/231; DeviceCalendarReader.kt:115 `CALENDAR_MISSING`, `syncEvents` at :50/:126; calendar_picker.dart:369; calendar_picker_test.dart:460/612; settings_screen.dart:348/658/701; onboarding_screen.dart:708; sync_service.dart:563 `_ =>` arm; source_detail_screen.dart:830/833). No plan text needed changing. Step 4: Python 3.12.10, Pillow 10.3.0. `gen_launcher_icon.py` has no check mode (a `--help` run rewrote its PNGs with identical bytes, no diff). Tools: build-tools 35.0.0 and 36.0.0, NDK 26.3/27.0/28.2, AVDs Pixel_9 and Android10_x86_64, no adb device attached. Step 3 not run first time: two java daemons from another session were alive. | |
| Task A (user) | done 2026-11-14. Registers searched at the user's request; the user ran CIPC (its free search needs a CAPTCHA): no records match. Listing name stays `T-Minus: Meeting Alarm` | USPTO, WIPO Global Brand Database (EUIPO data to 2026-11-13, UK, AU, NZ, JP and others; no South Africa) and Google Play: no live T-MINUS / TMINUS / T MINUS registration for software, alarms or calendars. Live exact marks are in other classes (golf 28, beer 32, clothing 25, UK events 35/41). Nearest composites: T-MINUS ZERO (US 98229637, pending, class 9 video game software), T-MINUSTHEDAY (US reg 8405886, class 42 greeting-card and event site that names "a calendar and reminders platform"), T-MINUS10 (finance). Dead: TMINUS 85704883 (mobile app, abandoned), T-MINUS COUNTDOWN CLOCK 78419994 (abandoned). Play has "T-Minus Zero: Launch Schedule" and "T-Minus - Overtime Tracker"; no meeting alarm with the name. Not legal advice. | |
| Task B (user) | done: identity verification under way 2026-11-14, confirmed complete by the user 2026-11-17 | | |
| Task C (user) | done 2026-11-14: keystore outside the repo (`%USERPROFILE%\keys\tminus-upload.jks`, alias `upload`), worktree `android/key.properties` filled in by the user and git-ignored (`!!`). Task 4 Step 4 proves the signature | | |
| Task 2 (Wave 1) | reported 2026-11-15T08:48:06 (worker 2072 s); checked 2026-11-15T08:56:03 (filtered Gradle BUILD SUCCESSFUL; RingingServiceTest 27/27 incl. the three new tests, RearmReceiversTest 10/10; only OWNS files under android/; no em dash; main checkout clean; the first check scout's report never arrived and it was stopped); deep review 2026-11-15T13:20: ship with fixes. No blocker for alarm delivery on API 26-36 (API 29-33 parse `systemExempted` as the compiled integer 0x400; Android 15's boot-start ban does not list the type). Warning: no test for the `SecurityException` refusal, which `systemExempted` makes reachable. Notes: `IllegalArgumentException` (type not in the manifest) is not caught; a garbled AlarmScheduler comment; `FOREGROUND_SERVICE_IMMEDIATE` on the ringing notification would be a cheap guard (NotificationFactory.kt, follow-up). Fix brief sent 13:21; fix plus a log-only-the-class change reported; checked (full Kotlin suite 309 tests, 0 failures; no em dash; RingingService.kt SHA-256 99B1A611...); deep re-review: ship. **Done 2026-11-15T13:45** | Worker: filtered Gradle BUILD SUCCESSFUL (RingingServiceTest 27, RearmReceiversTest 10), full 306 tests 0 failures; Robolectric SDK 33 ran; controls A-D each failed the matching new test, restore verified by SHA-256. Worker notes: one flake in 11 runs (`AccessDeniedException` on `state.json` in `PlanStore.writeLocked`, an existing test, a Windows file lock); `ServiceCompat` below API 34 masks the type to 8 bits and passes `FOREGROUND_SERVICE_TYPE_MANIFEST` (-1) through, a simpler alternative to `NO_TYPE` (for the deep review; kept as built). | 38f22bd |
| Task 4 (Wave 3), Steps 4-7 | release scout reported about 07:30. **Pass:** the AAB and APK are signed with the upload key (CN=Heinrich Nel, SHA-256 76:9C:...:E8:BD; the debug APK shows CN=Android Debug for contrast) with no missing-key line; permissions exactly the expected list (no MEDIA_PLAYBACK, no AD_ID); only RingingService is typed (0x400); exported components as expected; no analytics in pubspec.lock; zipalign 16 KB verified, every arm64 .so at 0x4000 or 0x10000 in the APK and the AAB; release install; onboarding with the demo feed over local http; the test alarm full screen (0x400); Sync now; reboot keeps the upcoming alarms; no R8 crash; no title, URL or link in the app's logs. **Open:** the tile's second click did not end Mute today; the headless sync could not be forced (job id not found); Settings did not render because of two input-dispatch ANRs on MainActivity while the emulator was loaded (SystemUI and GMS were also ANRing). Investigation:
- **Settings:** shows no Developer tools in the release build (PASS).
- **Headless sync from WorkManager:** ran in the release build, `TMinusSync: Headless sync (periodic) finished: ok` and four `(quietTile)` runs (PASS). `cmd jobscheduler run` cannot find WorkManager's job because the job lives in the `androidx.work.systemjobscheduler` namespace.
- **ANR trace:** the main thread was blocked in a Binder call to `AlarmManager.setExactAndAllowWhileIdle` while the emulator's system_server was overloaded (System UI and GMS were also not responding; launch took about 14 s on the software GPU). The call is pre-existing (the engine arms alarms on the main looper); follow-up R24.
- **Tile:** the scout read a second tap as asking for Mute again instead of End, in two runs, so it went to fix job F1. F1's diagnosis (2026-11-17) does not support that reading. In the second run, each tap came 12 to 32 s after the previous headless run had finished, and the tile and the Agenda show End, Mute, End, Mute, which is correct. The first run's log was lost when the emulator rebooted. Its data fits a request taken by a run that was killed before it applied the request (Plan 5 decision 18 accepts that loss). F1 made no production change; it adds six tap-order tests (see F1 below). Task 12 Step 4 re-checks the tile on the phone. | Release scout's builds, logs and screenshots in the session scratchpad. | 7416baf |
| Task 4 (Wave 3), Steps 1-3 and 8 | dispatched 2026-11-16T05:32 (R20); reported about 06:35; check dispatched | Worker: full flutter test +1260, analyze clean, Kotlin `--rerun-tasks` 330 tests 0 failures; key.properties checked for existence only. Departures for review: `logger.quiet` (Flutter runs Gradle with -q, so `warn` would never show), shown only for release tasks; a guard that fails the build if key.properties lacks an entry (naming entries only); BackupRulesTest also covers `-shm` and included folders; release.md uses apksigner for the APK and adds a "what is in the release" section. Controls: 7 Kotlin and 9 Dart, each failing its target; a fresh clone without key.properties builds debug and runs the tests. Checked: full analyze clean; flutter test +1260; Kotlin `--rerun-tasks` 330 tests, 0 failures on the second run. The first run failed once, in EventQueueTest `the queue keeps only the newest events`: a Windows `AccessDeniedException` renaming events.jsonl.tmp, the same pre-existing test flake class as PlanStore's state.json. It did not recur; follow-up below. No em dash, only placeholder secrets in release.md, main clean. Deep review and the Steps 4-7 release scout dispatched in parallel. Deep review: ship, no blockers or warnings. Review Focus 6 holds: Play refuses a debug-signed or wrong-key bundle, and no path prints a key.properties value. Departures accepted. Notes taken as doc fixes: the 16 KB date sentence, the `$ANDROID_HOME` fallback, the ISO-8859-1 and BOM note. The policy's device-transfer sentence is softened to "can be copied", because whether Android 9-11 includes `requireFlags` files in a phone-to-phone transfer is unconfirmed. Its suggested controls are covered by the worker's: a staged keystore in a throwaway repo, a folder include, and dropping `requireFlags`. Commit check 2026-11-17: `flutter analyze` clean; the five Dart tests that read docs/ +21 all passed; `key.properties` git-ignored (exit code only); exactly seven files staged; the hashes match the reviewed files. **Done 2026-11-17.** | 7416baf |
| F1 (Wave 3, R25) | dispatched 2026-11-16 (paused by usage limits); reported 2026-11-17: no defect, the brief's hypothesis is false (`display()` already reads a waiting or in-flight request); six new tests in `QuietTapSequenceTest.kt`, no production change. Review: close as no defect; the only matching path is the accepted decision-18 loss of a taken request (R26). Controls checked by the scout: dropping the in-flight branch, keeping the in-flight marker in `mirror()`, and dropping the tile's append policy each failed exactly the expected tests; restores hash-checked; quiet tests 19/19 green after. **Done 2026-11-17.** | Worker: quiet 19/19; full Kotlin `--rerun-tasks` 336 tests, 0 failures (after one EventQueueTest `AccessDeniedException` flake, R23); mutations M1-M5 each failed new tests (M5, drawing before storing, fails only the not-listening test). Emulator evidence: second run's taps were 12-32 s after the previous run finished, each run 4.5-8.3 s; the first run's log was lost. | 48a1351 |
| Task 9 (scout) | 2026-11-17: release APK built and signed with the upload key (not the debug key); installed on the Pixel_9 AVD (API 36); onboarded from the live Pages feed, source named "Team calendar"; clock moved only with `cmd alarm set-time`. Eight screenshots, 1080x2424 RGB without alpha: Agenda, event sheet, full-screen alarm, Profiles, Quiet modes, Health (dark), then Agenda and alarm (light). First set rejected on review: the wifi icons showed "!", the heads-up covered the top of the alarm, and the alarm showed 12-hour times beside the Agenda's 24-hour ones (R27). Retaken in 24-hour mode with System UI demo mode and the heads-up swiped away; the time setting, auto time and demo mode were put back. Known blemish: in the light Agenda the -1 alarm chips of Support triage and Roadmap review are greyed, because the clock moves for the video had already rung those alarms; retake later if it matters. FGS clips (not in git): `fgs1.mp4` 11.8 s (Health, Test alarm, full screen, Stop) and `fgs2.mp4` 96.1 s (a demo meeting's alarm on the locked screen, stopped from the notification). The user uploads them unlisted and puts the link in declarations.md. | Scout reports; screenshots viewed by the orchestrator. | |
| Task 10 Steps 2-6 (user, with the orchestrator in the built-in browser) | 2026-11-17/18. YouTube: both FGS clips unlisted (Shorts Aiv6mkO4RCM, MZqW6pTWOaI), links in declarations.md (9123dde). Play Console app created 2026-11-17 ("T-Minus: Meeting Alarm", io.github.fifothehein.tminus, en-GB, App, Free; the user approved the three declarations; automatic protection left on). Store listing text from listing.md, graphics uploaded by the user, saved with "Don't label assets" (the user's choice); category Productivity; contact email the user's Gmail, website the Pages home. App content: privacy policy URL; Ads No; Advertising ID No; Government No; Financial none; Health none; Data safety no data collected or shared; Sign-in details Yes with the 469-character demo-calendar instructions (the user's choice); target audience 18 and over and the IARC rating (both entered by the user). After the upload Play asked for two more: Exact alarms (Alarm clock) and Full-screen intent (Alarm clock, pre-grant at install: Yes). No foreground service declaration was asked for (`systemExempted`). The bundle was rebuilt after F2 (785e70b; 18 Nov 06:52, upload key) and released by the user to internal testing on 18 Nov 06:56 as 1 (1.0.0), notes "First internal test build."; testers list "T-Minus internal testers" (the user's Gmail); track Active; testers see the temporary name 'io.github.fifothehein.tminus (unreviewed)' until a review. Not sent for review: Play locks "Send app for review" until a closed test exists, and a personal account needs 12 testers for 14 days before production. Step 7 (review result) and Step 8 (pre-launch report) are pending. Closed testing - Alpha set up the same day at the user's request (all countries, the same testers list, feedback to the GitHub issues page, the same bundle, notes "First closed test build."), so "Submit 16 changes for review" is available to the user. First install on the S24 from the internal link (about 07:10) failed in the Play Store with "Something went wrong on our end" (server side; Android got no install request); a later retry installed it. | Play Console pages read back after each save. | |
| Task 10 upload bundle (scout) | 2026-11-17 at edbe98b: `flutter build appbundle --release` found `bundleRelease` up to date, so `build/app/outputs/bundle/release/app-release.aab` (66883295 bytes) is the Task 4 bundle of 2026-11-16 07:04. Gradle's up-to-date check means its inputs are unchanged, and only tests and docs changed since. It is signed with the upload key (SHA-256 76:9C:...:E8:BD, the same as Task 4's check), with no debug-signing line; pubspec `1.0.0+1`; `mapping.txt` beside it. Task 11 was started on the user's go-ahead to download the API 26 and API 33 images. | | |
| F3 (R32, session 2) | running. Check scout (full analyze, flutter test, ics_core dart test, em dash) and review-worker both dispatched 2026-11-18T11:11:47 on edef728. Review reported 11:14:18 (129 s): no blockers. One warning: no test pins what the cards announce to TalkBack (`Semantics(checked: selected)`, add_source_panel.dart:406-409), and `checked: false` passes every test; it becomes F3a, a semantics test (R36). Notes kept, not built: the cards announce no expanded state; no large-text test with a card open; switching phone, link, phone asks for calendar access again (as before); listing.md:35 names the link card first. Checked true: both callers (Sources, onboarding) get the change; nothing asks for calendar access or reads the phone before the phone tap; Continue waits for a source and Skip still works; URL field autocorrect and suggestions off; no new log line; no em dash; contract files untouched; declarations.md labels and order match the app, counts 918 (LF) and 497 correct, and the text still works on 1.0.0. Six negative controls named (lines 81 x2, 444, the card order, 145, 297) for the test runner. Check reported 2026-11-18 about 11:20 (548 s): HEAD edef728; worktree shows only this plan modified; main checkout clean; `flutter analyze` No issues found; full `flutter test` +1265 All tests passed; ics_core `dart test` +157 All tests passed; no em dash in edef728's 30 added lines. (The scout started a stray root-level `dart test` during the Flutter run and killed it; its ics_core result is from a clean rerun.) **Checked 11:21.** F3a dispatched 11:21:16 (dev-worker), reported about 11:42 (1284 s): one test in `add_source_panel_test.dart`, "the two ways are announced as a mutually exclusive pair, and the tapped one as checked" (both cards in the exclusive group; checked exactly true or false, never none; first, after phone, after link, after phone again). Analyze clean, file formatted, CRLF kept, lib/ untouched. It ran no test and no control, because the dev-worker role forbids both: the brief was wrong to ask (R37). Test runner dispatched 11:43:10: the new test unmodified, then F3a's controls C1-C3 and the review's R1-R6, with a scratchpad restore and sha256 proof after each. Runner reported about 11:58 (914 s): unmodified, `add_source_panel_test.dart` +42 and `onboarding_test.dart` +35 all passed, the new test included. Every control failed its named tests: C1 (`checked: false`), C2 (no exclusive group) and C3 (`checked: null`) fail the new test; R1 to R6 fail every test the review named, and R1, R2, R3 and R6 fail extra tests in the same area. Every restore matched the baseline sha256 (C1 checked directly); the final rerun matched run 0; main checkout clean. **No control survived.** F3a sent to the review-worker for re-review; re-review about 12:05: approve, no blockers or warnings (the lookup reads the merged node TalkBack focuses; `stopSemantics()` outside `addTearDown` follows calendar_picker_test's pattern). **F3 and F3a done 2026-11-18.** Commit scout dispatched | | edef728 |
| 1.0.1 release build (scout) | 2026-11-18, reported 12:02, at df75447 (commits 0e637c6 F3a, df75447 run log): `flutter build apk --release` (68570176 bytes) and `flutter build appbundle --release` (`app-release.aab` 66883732 bytes, `mapping.txt` beside it); both signed with the upload key (CN=Heinrich Nel, SHA-256 76:9C:...:E8:BD); `aapt2` shows versionCode 2, versionName 1.0.1; the tree stayed clean. APK copy sha256 AB732C2C... in the session scratchpad for Task 11 | | 0e637c6, df75447 |
| Task 11 (scout, emulators; R34) | waiting for F3, then the 1.0.1 release APK. On resume (2026-11-18): AVDs Pixel_9 (API 36), T11_API30, T11_API35, Android10_x86_64; system images android-29, 30, 34, 35, 36. No API 26 or API 33 image is installed, so those two levels need a download. The user approved the download 2026-11-18; setup scout dispatched 11:24:21, reported about 11:30: installed `android-26;google_apis;x86_64` 16.0.0 (no Play Store x86_64 image is offered for API 26) and `android-33;google_apis_playstore;x86_64` 9.0.0; AVDs T11_API26 and T11_API33 created on `pixel_6` like T11_API30, not booted yet. The levels run one at a time, one scout each, on the 1.0.1 APK (sha256 AB732C2C...), onboarded from the live Pages demo feed: API 36 (Pixel_9) dispatched 2026-11-18T12:03; then API 35 (T11_API35, a tablet Play image), 33, 30 and 26.<br>**API 36** (reported 12:21, 1095 s; 1.0.1 release APK, onboarded from the Pages feed with "Paste a calendar link" first, Check found 84 events): Step 1 PASS (test alarm full screen; `usage=USAGE_ALARM`; stopped by Dismiss, by the notification's Stop and by Volume down, each time the service ended). Step 2 PASS (`isForeground=true types=0x00000400`). Step 3 PASS (deep idle forced, "Project sync" alarm rang at 15:59:00 from `ALARM_MANAGER_ALARM_CLOCK`). Step 4 PASS with a note (R38): clock set 70 s before the 17:59 alarm, then reboot; `sys.boot_completed` at 17:58:54, but `BootReceiver` ran only at 17:59:44 and re-armed 150 alerts at 17:59:53; the overdue alarm rang through boot recovery at 18:00:10 (`BOOT_COMPLETED` allow-list), as a heads-up on the unlocked launcher; no `refused the foreground`. Logcat privacy PASS (no feed URL, no title, in the app's or the whole log). Other: one "System UI isn't responding" at first launch (no app ANR); Health warns that battery optimisation may delay alarms (left as is).<br>**API 35** (T11_API35, Pixel Tablet image; reported 12:44, 1335 s; Check found 84 events, 77 meetings with alarms): Step 1 PASS (full screen, `USAGE_ALARM`; Dismiss, Stop and Volume down each ended the service, Volume down in 1.4 s). Step 2 PASS (`types=0x00000400`). Step 3: the "Product demo" alarm rang in forced deep idle 1 s after its time (PASS), but the alarm screen's Dismiss did not stop it and Android showed "T-Minus isn't responding"; the notification's Stop ended it. Step 4 **FAIL as observed**: clock set 50 s before the 19:59 alarm, reboot; the device clock passed the alarm during the 3-minute boot (`BOOT_COMPLETED` at 20:01:09); in the scout's look about 40 s later the app had no process, no `BootReceiver` or "Re-armed" line and no alarm in `dumpsys alarm`, and nothing rang. On API 36 the receiver ran 50 s after boot, so the look may have come before the broadcast arrived (R39). Logcat privacy PASS on the post-boot log (the reboot cleared the earlier log). Odd but correct: the ringing screen says "Starts in 1 min", which is right for the alarm 1 minute before the meeting. SystemUI and Google apps also showed "isn't responding" after the boot.<br>**API 35, third try** (R40; booted with `-memory 4096 -cores 4`, reported about 13:15; two system dialogs closed: Pixel Launcher and System UI). Step 4 PASS, late: clock 70 s before the 19:59 "Retrospective" alarm, reboot at 13:03:50; `BOOT_COMPLETED` 19:58:53, the app's process for `BootReceiver` started 19:59:34, "Re-armed 150 alerts" 19:59:53 (after the alarm time), then Android killed that process with a background ANR at 20:00:03 ("No response to onStartJob"); `AlarmReceiver` started a new process at 20:00:32 and the alarm rang as a heads-up on the unlocked launcher (FGS allowed, `ALARM_MANAGER_ALARM_CLOCK`; "Audio focus denied; ringing anyway"), 92 s after its time; no `refused the foreground`. Step 3 dismiss PASS: an alarm in forced deep idle rang at 21:59:00 on time, full screen, and the screen's Dismiss stopped it within 5 s with no ANR. The ANR traces (`dumpsys dropbox`): (a) the first leg's MainActivity input timeout, main thread blocked in a Binder call `AlarmManager.setExactAndAllowWhileIdle` from `TimeChangeReceiver.onReceive`, which is R24; (b) the first leg's AlarmActivity input timeout, main thread waiting in `HardwareRenderer.setStopped` (the software GPU); (c) the boot kill above. Open: the Agenda listed "Product demo" 18:00 as the next alarm while `dumpsys alarm` had no alarm for it; that meeting's alarm was stopped in the first leg's Step 3, so the plan may have dropped it as dismissed while the Agenda still shows it (R42) | Scout screenshots and logs in the session scratchpad `t11-api36\` and `t11-api35\` | |
| Task 10 Steps 7-8 and the 1.0.1 upload (user) | waiting: R33 (new Sign-in text) and Task 11 first; Play's review result and pre-launch report not in yet | | |
| Task 10 Step 1 (review-worker) | 2026-11-17: privacy.md, listing.md and declarations.md read sentence by sentence against 06ff5ce. privacy.md is correct as published (no second pages PR); four optional completeness notes are kept for its next revision: the dart:io default headers and redirects, the Check button's fetch, the pre-alarm sync and restart rows in the permissions table, and the settings export in the "stays on your phone" sentence. One warning, fixed: the exact-alarm text left out the pre-alarm calendar refresh (PreSyncScheduler) and now names it, shortened to 484 characters. Notes fixed: the FGS text says it vibrates only if the profile asks (352 characters); Android 8 and 9 have no service types; the manifest table cites Task 4's release build; the listing's evidence table no longer says "only once Task 3/4 is committed"; the short description reads "for Outlook, Teams and phone calendar meetings" (78 characters), since Teams is not a source. Everything else checked true: the backup contents, no analytics or ads, the export contents, every App access label, the demo feed, the feature claims and every stated character count. | Review report; the merged release manifest of 2026-11-16 matches the permissions table row for row. | |
| Task 6 (Wave 2) | dispatched 2026-11-16T00:12 (paused by the usage limit); reported; `test/core/sync/outcome_severity_test.dart` added to its files (a plan gap: its two exhaustive tables must name the new outcome); checked (full analyze clean, full flutter test +1257, Kotlin `--rerun-tasks` 328 tests 0 failures with DeviceCalendarReaderTest 14/14, contract files unchanged, no Log call in the reader, no em dash, main clean); deep review 2026-11-16T05:00: ship, no blocker or warning (the cache and the plan stay unchanged on the failure; one notice per spell; only one calendar per ask; null SYNC_EVENTS still reads as synced). Its three suggested controls match the worker's D1, D3 and D10, which failed as expected. Commit scout dispatched 05:01 | Worker: full `flutter test` +1257 all passed, analyze clean, Kotlin 328 tests 0 failures (`--rerun-tasks`); 5 Kotlin and 14 Dart controls plus one for outcome_severity_test, each failing its target. **Done 2026-11-16T05:02.** | 12f102b |
| Task 8 (Wave 2, started early: R17) | dispatched 2026-11-15T18:45 (paused by the usage limit); reported about 23:30; checked (launcher_icon_test +11 all passed, analyze clean, graphic regenerates byte-identical 967726c3..., no em dash, only its five files); review sent | Worker corrected the plan's draft where the code differs (button labels, the free 12:00 UTC demo meeting, the moon button, volume keys only on the full-screen alarm, Health vs the why text, the FGS description) and added R12, a full-screen-intent fallback and a manifest table. Review: approve after three one-sentence fixes (keyword rules match words, not a Teams link's text; Join only for meetings with a link; without the full-screen grant an alarm still rings). Fix brief sent with the optional notes and the icon-drift control. The user chose to publish only the public pages (R18), so `docs/_config.yml` was added to Task 8. Fix reported: W1-W3, N2, N3, N5 (bit depth 8) in, counts restated; the icon-drift control showed `check_vectors()` (inherited from gen_launcher_icon.py) misses a change to one of two equal `strokeWidth` lines, and `launcher_icon_test.dart` is the exact guard. Final check (18 tests, analyze clean, graphic byte-identical) and re-review: approve. **Done 2026-11-16T00:21.** | af0e747 |
| Task 2b (Wave 1, R14) | dispatched 2026-11-15T13:46:31 to Task 2's worker (paused by the usage limit); reported about 18:25; check scout dispatched | Worker: 11 log lines in 10 files now log the class only; 11 ShadowLog tests with planted secrets; full Kotlin suite 320 tests, 0 failures; all 11 old calls put back at once fail exactly the 11 new tests. Left alone: `DeviceCalendarReader` has no log call; `AlarmEngineChannel` sends `e.message` to Dart as the PlatformException message (channel contract; the Dart side must log the code only); `RingingService` logs ringtone URIs on a tone fallback. Checked about 18:37 (only Task 2b's android/ files changed; 32 result files, 320 tests, 0 failures, written after the last edit, Gradle up to date on the re-run; no throwable or message left in a main-code Log call; main checkout clean). Reviewed: approve; every Dart catch of an `alarm_engine` PlatformException logs the code only. Its two follow-ups were taken into Task 2b: a fixed message for `engine_error`/`bad_args`, and tone indices instead of URIs in RingingService's fallback log; plus the missing CrashSilencer control. Follow-ups checked (323 tests, 0 failures) and re-reviewed: approve; nothing in Dart reads those messages. **Done 2026-11-15T18:44.** | 6669ad8 |
| Task 3 (Wave 1) | reported 2026-11-15T18:21:39 (paused twice by usage limits; R9 added 13:10); checked about 18:35 (full `flutter analyze` clean, full `flutter test` +1239 all passed, schema dumps regenerate byte-identical, v1/v2 dumps unchanged, alert.dart and planned_alert.dart unchanged, no em dash, main checkout clean). Deep review about 18:55: ship with fixes. It confirmed Review Focus 1: no path reads the cache before the move, in either isolate. BLOCK: upgraded phones keep meeting text in `tminus.sqlite`'s free pages and WAL (both backed up). WARN: the `from < 2` step fails if it runs after the v3 step committed (a two-isolate v1 open, or a crash before user_version is stored, which never heals). Notes taken: `_cleanUp` order, a "moved" marker. Fix brief sent; fix reported (secure_delete, one-time VACUUM + TRUNCATE with a `storage.compactedV3` marker, TRUNCATE on pause, the R15 guard, `_cleanUp` catching everything with the cache step last, a `storage.legacyMoved` copy marker; 7 tests, every control failing its target); checked (full analyze clean, full test +1248, generated files byte-identical, contract files untouched); deep re-review: ship (note: the TRUNCATE pause checkpoint can wait up to 5 s). **Done 2026-11-16T00:12.** | Worker: full `flutter analyze` clean, full `flutter test` +1239 all passed (30 new tests of its own); about 35 negative controls, each failing as expected, restores hash-checked. Plan gaps it fixed: the Agenda, Sources and Source detail screens listened only to `AppDatabase` updates and now also listen to the cache; `SyncService` takes the cache values. | 3b246a4 |
| Task 5 (Wave 1) | reported 2026-11-15T08:50:33 (worker 2210 s); checked 2026-11-15T08:54:27 (targeted tests +71 all passed, analyze clean on its six Dart files, only OWNS files changed, no em dash, main checkout clean); reviewed 2026-11-15T13:10: 2 blockers, 8 warnings, 5 notes. Fix brief sent 13:12 (policy sentences A-I, onboarding large-text check, links.dart comment, demo title, five controls). Blocker B1 (meeting titles in `sync.missedSystemExpected`, a backed-up settings row) went to Task 3 (R9). Fix reported about 13:40 (policy A-I, demo title, links.dart comments; two tests tightened after the reviewer's controls passed on them); fix checked (targeted +71, analyze clean, no em dash, demo.ics all CRLF); re-review sent Step 8 (2026-11-17, the user approved): docs-only PR FifoTheHein/tminus#25 (caa9f0e, the four files byte-identical to this branch, demo.ics stored CRLF) merged as adb4a23; the Pages build of adb4a23 finished; `/`, `/privacy/` and `/play/demo.ics` load (200; the feed is `text/calendar` with CRLF lines), and `/superpowers/`, `/design/`, `/design-brief.html`, `/play/listing.html`, `/play/declarations.html`, `/play/release.html` and `/play/feature-graphic.png` return 404. `main` merged back into this branch (06ff5ce, no file change). | Worker: targeted tests +71 all passed, analyze clean, format unchanged; 10 controls on links_test and 8 on the widget tests, each failing as expected (one first passed and the assertion was tightened). Worker flagged policy sentences that are not fully true (backup encryption on API 26-27, the Network state permission missing from the table, the calendar list read before a pick, an export file outliving an uninstall, Play's own vitals); these go to the review. Re-review: approve; its two optional "such as" wordings taken. **Done 2026-11-15T13:36**, Step 8 (pages online) waits for Tasks 3 and 4 (R10). | b01e7d3 |
| Task 7 (Wave 1) | reported 2026-11-15T08:58:24 (worker 2692 s); checked 2026-11-15T13:12 (targeted +109 all passed, analyze clean, calendar_picker.dart unchanged, no em dash, main clean; the check paused on the 5-hour usage limit 09:00-13:10); reviewed about 13:15: approve, no blockers or warnings; all six departures accepted (second phone read, trimmed name, blank as `Phone calendar`, every source counts, kind from `groupCalendars` over the whole phone, extra tests). Note: the debug-only sync panel still adds phone calendars without a name. Worktree controls, all failing as expected, restores hash-checked: removing `names.add(source.name)` (add_source_panel_test.dart:843), returning the ticked list instead of the second read (:766), enabling a not-synced row in the picker (calendar_picker_test.dart:448 and :614); restored run +109 all passed. Commit scout dispatched 2026-11-15T13:22:17 | Worker: targeted tests +109 all passed (89 before, +20), analyze clean; 15 pure, 6 panel and 3 picker controls run in a scratch copy, each failing as expected. Departure for review: the panel reads the phone's calendars a second time (`DeviceCalendarApi.calendars()`) to see clashes with calendars that were not ticked, because the picker's `onAdd` passes only the ticked ones and `calendar_picker.dart` may not change; a failed read falls back to the ticked list. **Done 2026-11-15T13:23.** | 51a4842 |
