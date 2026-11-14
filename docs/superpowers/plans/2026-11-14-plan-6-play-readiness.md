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
| `lib/features/sources/calendar_groups.dart` | `kindLabel` (moved from the picker), `defaultSourceName` | 7 |
| `lib/features/sources/calendar_picker.dart`, `add_source_panel.dart` | Use `kindLabel`; pass the default name | 7 |
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
  grep -n "'About & privacy'\|licencesButton\|Feeds are fetched" lib/features/settings/settings_screen.dart
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
  - `lib/core/sources/source_admin.dart`;
  - `lib/app/restore_guard.dart`, `app_lifecycle.dart`, `di.dart`;
  - `test/core/storage/test_database.dart`;
  - every test that builds one of the three repositories directly (`grep -rln "OccurrenceRepository(\|AlertHistoryRepository(\|SyncLogRepository(" test`).
- Generated: `drift_schemas/drift_schema_v3.json`, `test/generated_migrations/**`, `test/generated_migrations/cache/**`.
- Test: `test/core/storage/cache_database_test.dart` (new), `test/core/storage/migration_test.dart` (v2 → v3), `test/app/restore_guard_test.dart`, `test/core/sources/source_admin_test.dart`, `test/app/app_lifecycle_test.dart`.

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

    Future<void> checkpoint() => customSelect('PRAGMA wal_checkpoint(PASSIVE)').get();
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
  - `SourceAdmin.delete` calls `occurrences.deleteForSource(id)` after `sources.delete(id)`, replacing the lost cascade. A crash between the two leaves cache rows for a source that no longer exists. The planner reads only enabled sources' copies, so those rows plan nothing, and `deleteEndedBefore` prunes them.
  - `SourceAdmin.updateDeviceCalendar` clears the source's cache rows **before** its main transaction, not inside it. A crash in between leaves the old calendar's source with an empty cache. That plans nothing for it until the next fetch refills it, the same as a new source.
- [ ] **Step 6: `RestoreGuard._makeSafe`.** The guard runs before anything opens `CacheDatabase`, at both entry points (`start_services.dart`, `sync_main.dart`). Keep it that way, and keep the race it already handles: the UI isolate and a headless sync can both reach `_makeSafe`, and the one that comes second must find the first one's work and touch nothing.
  - **Inside** the existing transaction, after the install-id check, replace the three `db.delete(db.occurrences / alertHistory / syncLog)` calls with `DROP TABLE IF EXISTS` for `legacy_occurrences`, `legacy_alert_history` and `legacy_sync_log`. A pre-Plan-6 backup's cached meetings are then gone in the same commit as the new install id, and `LegacyCacheMove` finds nothing to move. The `sync.%` settings delete stays where it is.
  - **After** the transaction, and only when it returned `RestoreOutcome.restored`, delete every row of the three cache tables through `CacheDatabase`. A restored phone normally has no cache file, because it is never backed up or transferred. This covers a cache left from using the app on this phone before the restore. It is safe after the commit: the restore leaves every source disabled, so no sync in another isolate can be filling the cache.
  - **Never** clear the cache before the transaction or when the outcome is `normal`. Clearing it there would wipe a cache that the first guard's sync has already filled.
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
    - whatever WorkManager adds (`ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE` for its own service).
  - Any `com.google.android.gms.permission.AD_ID` fails the task: Data safety and the policy say no advertising id.
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
  3. **Sync now** runs, and Health's sync log shows it;
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
  - `lib/features/sources/problem_card.dart`, `source_detail_screen.dart`.
- Test: `android/app/src/test/kotlin/io/github/fifothehein/tminus/calendar/DeviceCalendarReaderTest.kt`, `test/core/sources/device_calendar_source_test.dart`, `test/core/sync/sync_service_test.dart`, `test/features/health/health_text_test.dart`, `test/features/sources/problem_card_test.dart`, `test/features/sources/source_detail_screen_test.dart`

- [ ] **Step 1: Kotlin.**
  - `instances()` already reads the existing calendar ids. It now also reads `Calendars.SYNC_EVENTS` for the asked ids, and after the missing check throws `DeviceCalendarException(CALENDAR_NOT_SYNCED, "A calendar is not synced")` if any asked calendar has `SYNC_EVENTS == 0`.
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
  - `source_detail_screen.dart`: treat `calendarNotSynced` like `calendarMissing` where it offers **Choose another calendar** (line 830 today).
- [ ] **Step 3: Tests** (negative control for each):
  - `a calendar whose sync is off is refused` (Robolectric, a provider row with `SYNC_EVENTS = 0`);
  - `a synced calendar still returns its instances`;
  - `a not-synced calendar keeps its cached meetings and turns the source red`: `SyncService` with a fake API throwing the code; the cache and the plan are unchanged, the log row is `calendarNotSynced`, and one Feed broken notice is posted, once;
  - the text, icon and action tests for the three widgets.
- [ ] **Step 4: Roadmap §3.** The `queryInstances` row's errors become `permission_denied`, `calendar_missing` (Plan 4), `calendar_not_synced` (Plan 6). This is the one contract edit; it is made in this task's commit.
- [ ] **Step 5:** Run the gates (Kotlin too), then commit `Say when a phone calendar stops syncing and keep its alarms`.

### Task 7: Account kind in default names, and a stricter picker test

**Deep review:** no.

**Files:**
- Modify: `lib/features/sources/calendar_groups.dart`, `calendar_picker.dart`, `add_source_panel.dart`
- Test: `test/features/sources/calendar_groups_test.dart`, `calendar_picker_test.dart`, `add_source_panel_test.dart`

- [ ] **Step 1:** Move the picker's kind-label function to `calendar_groups.dart` as the public `String? kindLabel(CalendarGroupKind kind)`. It returns `Google`, `Samsung account`, `Outlook`, `Exchange`, `Phone` for `phoneOnly`, and `null` for the others. The picker's headings keep the words they show today, because the heading builder keeps its own text for the kinds that have no label.
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
  - **Data safety:** no data collected, no data shared. Every question about collection is answered "No", because the app sends nothing to the developer or third parties (Play counts only data transmitted off the device by the app to the developer or others; calendar fetches go to the user's own provider, at the user's request). "Is all of the user data collected by your app encrypted in transit?" does not apply. Data deletion: no account, so no deletion request mechanism is needed; uninstall removes everything.
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
- [ ] **Step 3: The FGS video.** `adb shell screenrecord --time-limit 60 /sdcard/fgs.mp4`: Settings → Test alarm (or Health → Test alarm), the alarm rings full screen, then Stop. A second clip shows a scheduled demo meeting's alarm firing on the lock screen, with the notification's Stop. Pull the files. The **user** uploads them to YouTube as **unlisted** and puts the link into `docs/play/declarations.md`.
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

(Filled in while building.)

## Run log

(Filled in while building.)
