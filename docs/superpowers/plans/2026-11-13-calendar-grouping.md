# Calendar grouping in the phone calendar picker: Implementation Plan

> **Execution: lightweight orchestrator, run locally** - the orchestrate skill's agents (dev-worker, scout, review-worker, deep-review) and checks, with no Gate-0 stop, no fresh session per wave and no time booking; waves by dependency, no shared files within a wave, one Flutter or Gradle job at a time on this machine, commit each part, a negative control for every new test.

**Goal:** The **Use a calendar on this phone** picker groups the phone's calendars under headings by account kind and account, sets apart shared, holiday and phone-only calendars, and marks calendars that are not synced.

**Architecture:** `DeviceCalendarReader.calendars()` (Kotlin) adds five raw columns to each map. `DeviceCalendar` (Dart) carries them. A new pure function `groupCalendars` in `lib/features/sources/calendar_groups.dart` applies every grouping rule. `CalendarPicker` renders the groups, the not-synced state and the footnote. Nothing is persisted.

**Tech Stack:** Dart 3.13 / Flutter 3.47, Kotlin, Robolectric 4.17 (SDK 34). No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-13-calendar-grouping-design.md` (§4 rules, §5 contract, §6 UI, §7 accessibility, §8 tests). Workers read the sections their brief names.

**Worktree:** `C:\Projects\tminus\.claude\worktrees\spec-calendar-grouping-e06b35` · branch `claude/spec-calendar-grouping-e06b35` · base `2475f4c` (the spec commit, on `main` `d700734`).

## Global Constraints

- **Do not raise compileSdk** (36). No new Dart package, no new Gradle dependency.
- Never edit or `dart format` `lib/core/model/alert.dart` or `lib/core/model/planned_alert.dart`. Run `dart format` only on files the job owns.
- **Never log** calendar names, account names, owner addresses or exception messages. Log `e.runtimeType` or a `PlatformException`'s code only.
- `ownerAccount` is an email address: held in memory only, never stored, never shown in the UI.
- App text never uses em dashes (U+2014). `test/no_em_dash_test.dart` enforces it.
- Commits: author and committer `Heinrich J Nel <38792842+FifoTheHein@users.noreply.github.com>` (repo-local config), message passed with `git commit -F <file>`, **no** Co-Authored-By, Claude-Session or "Generated with" lines.
- One Flutter or Gradle job at a time across the machine. Another session (Plan 6) may build: the runner checks for running `java`/`dart`/`flutter` processes from other checkouts before each build and waits if one is running.
- Fixture data uses `example.com` style addresses and invented calendar names. No real calendar data in git.

## Review Focus

1. A provider that leaves every new column null (old Samsung builds, the Robolectric fake): reader gives the §5 defaults, grouping still works. Pinned in T1 and T2.
2. An account with a null or empty `accountName`: heading shows the kind only, no trailing ` · `. Pinned in T2 (`accountName` null in the group) and T3 (heading text).
3. Two accounts whose names differ only in case, same type: Android treats them as two accounts; so does `groupCalendars` (exact match). Pinned in T2.
4. A calendar that is both already added and not synced, in `pickOne`: not tappable, label **Already added, not synced**. Pinned in T3.
5. The footnote appears only when a not-synced row exists, and never for an empty list or an access error. Pinned in T3.

---

## 1. Facts nobody may re-argue

- Kotlin passes raw facts, Dart groups (spec §2, approach A).
- Group by kind, then by account; an account is (`accountType`, `accountName`) with exact string match.
- Rules, order and labels are spec §4, §6 and §7 exactly. Outlook, Exchange, Samsung and Other never produce Shared or Holidays.
- Not-synced rows are shown, greyed, labelled and unchoosable in both `pickMany` and `pickOne`.
- No drift schema change, no persisted field. No deep-review job (no migration, money or security surface; the logging rule is in every brief and the review-worker checks it).
- **Plan decision (spec gap):** in **Holidays and birthdays**, a row whose `accountType` is `LOCAL` hides its account line (`local.samsungbirthday` means nothing to the user). Every other Shared or Holidays row shows it when non-empty.
- **Plan decision:** accounts with a null or empty `accountName` sort after named accounts of the same kind.

## 2. Standing rules for this plan

- `WORKDIR` for every job: `C:\Projects\tminus\.claude\worktrees\spec-calendar-grouping-e06b35`. Every git command is `git -C <WORKDIR> ...`; every path is absolute.
- Flutter commands run from `WORKDIR`; Gradle from `WORKDIR\android` with `.\gradlew.bat`.
- Existing tests that use `Key('calendar-<id>')`, **Already added** and **Add selected** must keep passing unchanged.

## 3. How the parts connect

| Name | Kind | Shape | Owner job | On failure |
|-|-|-|-|-|
| `queryDeviceCalendars` map keys | channel | existing `id, name, accountName, color, visible` plus `accountType: String?`, `ownerAccount: String?`, `accessLevel: Int?`, `syncEvents: Boolean`, `primary: Boolean?` | J1 | null column: `accountType`/`ownerAccount`/`accessLevel`/`primary` null, `syncEvents` true |
| `DeviceCalendarReader.CALENDAR_COLUMNS` | Kotlin val | existing five then `ACCOUNT_TYPE, OWNER_ACCOUNT, CALENDAR_ACCESS_LEVEL, SYNC_EVENTS, IS_PRIMARY` | J1 | - |
| `DeviceCalendar` | Dart class | `const DeviceCalendar({required String id, required String name, String? accountName, required int color, required bool visible, String? accountType, String? ownerAccount, int? accessLevel, bool syncEvents = true, bool? primary})`, fields of the same names | J2 | `fromJson`: absent key gives the default |
| `CalendarGroupKind` | Dart enum | `google, samsung, outlook, exchange, other, shared, holidays, phoneOnly` (this is also the §4.3 order of kinds) | J2 | - |
| `CalendarGroup` | Dart class | `const CalendarGroup({required CalendarGroupKind kind, String? accountName, required List<DeviceCalendar> calendars})`; `bool showAccountLineFor(DeviceCalendar c)`: true only for `shared`, and for `holidays` when `c.accountType != 'LOCAL'`, and only when `c.accountName` is non-empty | J2 | - |
| `groupCalendars` | Dart function | `List<CalendarGroup> groupCalendars(List<DeviceCalendar> calendars)` in `lib/features/sources/calendar_groups.dart`; special groups have `accountName == null` | J2 | empty input gives `[]` |
| Account-type strings | constants | `com.google`, `com.osp.app.signin`, `com.microsoft.office.outlook.USER_ACCOUNT`, `com.android.exchange`, `com.google.android.gm.exchange`, `com.samsung.android.exchange`, `LOCAL`; `local.samsungbirthday` | J2 | unknown or null type: `other` |
| Heading text | UI copy | `GOOGLE · <acct>`, `SAMSUNG ACCOUNT · <acct>`, `OUTLOOK · <acct>`, `EXCHANGE · <acct>`, `OTHER · <acct>`, `SHARED WITH YOU`, `HOLIDAYS AND BIRTHDAYS`, `ON THIS PHONE ONLY`; ` · <acct>` left out when the account name is null or empty; the account part is never upper-cased | J3 | - |
| Heading semantics | a11y | `Semantics(header: true)`, label `Google, <acct>` / `Samsung account, <acct>` / `Outlook, <acct>` / `Exchange, <acct>` / `Other, <acct>` / `Shared with you` / `Holidays and birthdays` / `On this phone only` | J3 | - |
| Row trailing labels | UI copy | `Already added`, `Not synced`, `Already added, not synced` | J3 | - |
| Footnote | UI copy | `Key('notSyncedNote')`, text `Calendars marked Not synced have no events on this phone. Turn on sync for them in their calendar app, then come back.` | J3 | shown only when a not-synced row exists |
| Choice card subtitle | UI copy | `Google, Samsung, Outlook and other accounts` | J3 | - |
| Row key | widget | unchanged `Key('calendar-<id>')` | J3 | - |
| `phoneCalendar(...)` test helper | test support | gains optional `String? accountType, String? owner, int? access, bool syncEvents = true, bool? primary`, written into the map under the §3 keys | T3 | - |

## 4. Acceptance criteria -> tests

| AC | Test | Test author | Impl |
|-|-|-|-|
| AC1 reader maps the five columns | `DeviceCalendarReaderTest`: `calendars carry account type, owner, access, sync and primary` | T1 | J1 |
| AC2 null columns give defaults, no throw | `DeviceCalendarReaderTest`: `missing calendar columns fall back to defaults` | T1 | J1 |
| AC3 `SYNC_EVENTS = 0` is false, `IS_PRIMARY = 1` true | `DeviceCalendarReaderTest`: `sync off and primary are read as booleans` | T1 | J1 |
| AC4 channel passes the keys | `CalendarChannelTest`: `queryDeviceCalendars passes the grouping columns through` | T1 | J1 |
| AC5 `fromJson` with and without new keys | `device_calendar_source_test.dart`: `calendars() reads the grouping fields` and `calendars() defaults absent grouping fields` | T2 | J2 |
| AC6 kinds by account type, unknown and null to Other | `calendar_groups_test.dart` group `kinds` | T2 | J2 |
| AC7 Google and Samsung with the same account name split | `calendar_groups_test.dart`: `same account name, different type, gives two groups` | T2 | J2 |
| AC8 Shared rules (spec §4.2 list, incl. primary never shared, access 0 and null) | `calendar_groups_test.dart` group `shared` | T2 | J2 |
| AC9 Holidays (Google holiday, Google contacts, Samsung birthday), Outlook at 200 stays | `calendar_groups_test.dart` group `holidays` | T2 | J2 |
| AC10 other LOCAL to phone only | `calendar_groups_test.dart`: `local calendars are phone only` | T2 | J2 |
| AC11 group order, account sort, row sort (primary, fallback, name, id), null account last, case-differing names are two accounts | `calendar_groups_test.dart` group `order` | T2 | J2 |
| AC12 `showAccountLineFor`, empty groups left out, empty input | `calendar_groups_test.dart` group `shape` | T2 | J2 |
| AC13 headings in order, header semantics, null account heading | `calendar_picker_test.dart`: `headings follow the group order` and `headings are announced as headers` | T3 | J3 |
| AC14 two "My calendar" under different headings | `calendar_picker_test.dart`: `the two My calendars sit under different headings` | T3 | J3 |
| AC15 not-synced row: label, disabled, never reaches onAdd; footnote only then | `calendar_picker_test.dart`: `a not-synced calendar cannot be added` and `the footnote shows only with a not-synced calendar` | T3 | J3 |
| AC16 already added and not synced label | `calendar_picker_test.dart`: `already added and not synced says both` | T3 | J3 |
| AC17 pickOne ignores a not-synced row | `calendar_picker_test.dart`: `pickOne ignores a not-synced calendar` | T3 | J3 |
| AC18 account line only in Shared and non-LOCAL Holidays rows | `calendar_picker_test.dart`: `only shared and holiday rows show their account` | T3 | J3 |
| AC19 subtitle copy | `calendar_picker_test.dart` or `add_source_panel_test.dart` existing subtitle check updated: `Google, Samsung, Outlook and other accounts` | T3 | J3 |

## 5. Out of scope - do not build, do not propose

- Telling a source that its calendar stopped syncing (spec follow-up).
- Changing a device source's default name.
- Collapsing groups, a search box, live refresh of sync state.
- Any change to `instances()`, `DeviceCalendarSource`, sync, planner or drift.
- Grouping by calendar name for Outlook, Samsung or Exchange.

## 6. Waves

### Setup (scout)

```
## S - worktree ready for Flutter and Gradle
AGENT: scout   TASK: setup   SKILL: none
WORKDIR: C:\Projects\tminus\.claude\worktrees\spec-calendar-grouping-e06b35
OWNS: android\gradlew, android\gradlew.bat, android\local.properties, android\gradle\wrapper\gradle-wrapper.jar (all git-ignored copies)
DOES:
  1. Copy those four files from C:\Projects\tminus\android\ into WORKDIR\android\ (same relative paths).
  2. List running java.exe / dart.exe / flutter processes with their command lines; report any whose path is not WORKDIR.
  3. If none from another checkout: `flutter pub get` in WORKDIR.
ACCEPTANCE:
  git -C WORKDIR status --short   -> only the untracked plan file
  git -C WORKDIR log -1 --format=%h  -> 2475f4c (or the plan commit after it)
  flutter pub get                 -> "Got dependencies" / no error
```

### Wave 1 - contract and grouping

Implementations J1 and J2 together; then T1 after J1 passes Check, T2 after J2. No shared files.

```
## J1 - reader returns the grouping columns
AGENT: dev-worker   TASK: J1   SKILL: none   WORKDIR: (above)
OWNS:  android\app\src\main\kotlin\io\github\fifothehein\tminus\calendar\DeviceCalendarReader.kt
       docs\superpowers\plans\2026-10-06-tminus-roadmap.md   (the §3 `queryDeviceCalendars` row only)
READS: spec §3, §5; CLAUDE.md; the OWNS files; AlarmEngineChannel.kt
CONTEXT: §3 rows `queryDeviceCalendars map keys` and `CALENDAR_COLUMNS`. Read each new column null-safely
  (`isNull(i)` before `getInt`/`getString`): providers and the Robolectric fake leave columns null.
  Keep the sort order and `instances()` behaviour unchanged. Update the KDoc on `calendars()`.
DOES: 1. Add the columns and map keys. 2. Update the roadmap §3 row to list the new keys and defaults.
ACCEPTANCE: (runner) `.\gradlew.bat :app:compileDebugUnitTestKotlin` in WORKDIR\android -> BUILD SUCCESSFUL
            git -C WORKDIR status --short -> only OWNS (+ plan)
NEVER: log calendar or account values; touch tests.
```

```
## J2 - DeviceCalendar fields and groupCalendars
AGENT: dev-worker   TASK: J2   SKILL: none   WORKDIR: (above)
OWNS:  lib\core\sources\device_calendar_api.dart
       lib\features\sources\calendar_groups.dart   (new)
READS: spec §4, §5; section 1 and 3 of this plan; the OWNS files; lib\features\sources\calendar_picker.dart (read only)
CONTEXT: §1 facts; §3 rows DeviceCalendar, CalendarGroupKind, CalendarGroup, groupCalendars, account-type strings.
  Shared check (Google only): owner and account compared trimmed and lower-cased; person owner = contains '@'
  and does not end with '.calendar.google.com'; group owner = ends with '@group.calendar.google.com' and
  (accessLevel ?? 0) < 700; primary (primary == true, or primary == null and owner equals account) is never shared.
  Holidays: Google owner ends with '#holiday@group.v.calendar.google.com' or '#contacts@group.v.calendar.google.com';
  LOCAL with accountName == 'local.samsungbirthday'. Checks run Holidays, Shared, phone only, account group.
  Row order: primary (as above) first, then name lower-cased, then id. Account order inside a kind: accountName
  lower-cased, null or empty last. No Flutter widget imports in calendar_groups.dart.
DOES: 1. Extend DeviceCalendar and fromJson. 2. Write calendar_groups.dart. 3. `dart format` the two files.
ACCEPTANCE: (runner) `flutter analyze` -> No issues found!
            git -C WORKDIR status --short -> only OWNS (+ plan)
NEVER: change CalendarPicker; log anything.
```

```
## T1 - reader and channel tests (test author)
AGENT: dev-worker   TASK: J1   WORKDIR: (above)
OWNS:  android\app\src\test\kotlin\io\github\fifothehein\tminus\calendar\DeviceCalendarReaderTest.kt
       android\app\src\test\kotlin\io\github\fifothehein\tminus\calendar\CalendarChannelTest.kt
READS: acceptance criteria and CONTEXT only - not DeviceCalendarReader.kt. The two test files, spec §5.
CONTEXT: §3 row `queryDeviceCalendars map keys`. The FakeCalendarProvider returns null for any column a row omits.
DOES: AC1-AC4 as named in plan §4. Use `Calendars.*` constants for column names and example.com values.
ACCEPTANCE: (runner) `.\gradlew.bat :app:compileDebugUnitTestKotlin` -> BUILD SUCCESSFUL
```

```
## T2 - DeviceCalendar and grouping tests (test author)
AGENT: dev-worker   TASK: J2   WORKDIR: (above)
OWNS:  test\core\sources\device_calendar_source_test.dart   (add tests only)
       test\features\sources\calendar_groups_test.dart       (new)
READS: acceptance criteria and CONTEXT only - not device_calendar_api.dart's or calendar_groups.dart's bodies
       (the section-3 shapes are the interface). Spec §4.
CONTEXT: §1, §3 rows DeviceCalendar..account-type strings, the J2 CONTEXT rules above (they are the acceptance criteria).
DOES: AC5-AC12, table-driven where it helps; Review Focus 1-3.
ACCEPTANCE: (runner) `flutter analyze` -> No issues found!
```

**Wave 1 close** (scouts): `flutter analyze` -> No issues found!; runner `flutter test test/core/sources test/features/sources/calendar_groups_test.dart` -> all pass; runner Gradle `:app:testDebugUnitTest --tests "io.github.fifothehein.tminus.calendar.*"` -> BUILD SUCCESSFUL; review-worker on the wave diff; each named negative control; commit J1+T1 and J2+T2 as two commits.

### Wave 2 - the picker

```
## J3 - grouped picker
AGENT: dev-worker   TASK: J3   SKILL: none   WORKDIR: (above)
OWNS:  lib\features\sources\calendar_picker.dart
       lib\features\sources\add_source_panel.dart   (the choice card subtitle only)
READS: spec §4.4, §6, §7; docs\design-brief.md; lib\app\theme\*; calendar_groups.dart; the OWNS files
CONTEXT: §3 rows CalendarGroup, groupCalendars, heading text, heading semantics, trailing labels, footnote,
  subtitle, row key. Heading: context.tminusType.overline, scheme.onSurfaceVariant, Text.rich (kind upper,
  account as is), one line, ellipsis; top padding TMinusSpacing.md except the first, bottom TMinusSpacing.xxs.
  Not-synced row: name in scheme.onSurfaceVariant, dot at opacity 0.38 and excluded from semantics, checkbox
  disabled (ticked only if already added), onTap null in both modes. Row semantics merged: name, account if
  shown, trailing label. Footnote: bodySmall, tertiaryText, TMinusSpacing.sm above, above Add selected.
DOES: 1. Render groups. 2. Not-synced state and footnote. 3. Subtitle. 4. `dart format` the two files.
ACCEPTANCE: (runner) `flutter analyze` -> No issues found!
NEVER: change selection, takenIds, onAdd/onPick contracts or the access states.
```

```
## T3 - picker widget tests (test author)
AGENT: dev-worker   TASK: J3   WORKDIR: (above)
OWNS:  test\features\sources\calendar_picker_test.dart   (new)
       test\features\sources\source_test_support.dart     (phoneCalendar helper only)
       test\features\sources\add_source_panel_test.dart   (only if an existing subtitle assertion needs the new text)
READS: acceptance criteria and CONTEXT only - not calendar_picker.dart. Existing tests in test\features\sources
       for the harness (channel mock, configureDependencies(openDatabase: openTestDatabase), tearDown(getIt.reset)).
CONTEXT: §3 rows heading text, heading semantics, trailing labels, footnote, subtitle, row key, phoneCalendar helper.
DOES: AC13-AC19; Review Focus 2, 4, 5. Pump CalendarPicker.pickMany / pickOne directly inside a MaterialApp with
  the app theme (TMinusTheme) and a mocked `alarm_engine` channel plus granted calendar permission, as existing tests do.
ACCEPTANCE: (runner) `flutter analyze` -> No issues found!
```

**Wave 2 close** (scouts): `flutter analyze` -> No issues found!; runner `flutter test` (full app suite; the picker is used by onboarding and source detail) -> all pass; review-worker; negative controls; commit J3+T3.

### Finish

- A scout reports `git -C WORKDIR log --oneline 2475f4c..HEAD` and `git status --short`.
- Record differences in "Built differently from this plan" below.
- Push, PR and installing on the phone wait for the user's go.

## 7. Orchestrator-only steps

- Booking: report-only; TASK lines are labels, nothing is written.
- Overhead task: none.
- Push and PR: on the user's go only. Installing the APK on the phone: on the user's go only.

## 8. Run log (bookmark)

Reviewer: ab1186ed1c674e825 · Test runner: ade476834df91999b

| Step | State | Evidence | Commit |
|-|-|-|-|
| Setup | done | gradle files copied, pub get ok, no other build running | 563ec61 (plan) |
| J1 | done | compile BUILD SUCCESSFUL (check scout), diff matches brief, main checkout clean | |
| T1 | done | 4 new tests + ARGB map fix; runner: calendar.* 14/14 pass (Gradle BUILD SUCCESSFUL) | 9eb594c (J1+T1); J2+T2 444d066 |
| J2 | done | analyze clean (check scout), code read against spec §4, main checkout clean | |
| T2 | done | 2 + 38 tests, analyze clean; runner: test/core/sources + calendar_groups_test 137/137 pass | |
| W1 close | done | analyze clean; Dart 137/137; Kotlin calendar.* 14/14; review: no BLOCK/WARN, 2 NOTEs; 9/9 negative controls FAIL as expected (C1-C9), restores proven by sha256 + `git diff --quiet HEAD` | 9eb594c, 444d066 |
| J3 | done | analyze clean (check scout), diff read, no em dash, no new logging | |
| T3 | done | 10 tests + phoneCalendar + 2 forced assertion edits; fix pins pickOne enabled state (re-reviewed); runner: full `flutter test` +1156 all pass, picker 10/10 after fix | (wave 2 commit) |
| W2 close | done | analyze clean; full suite +1156; test/features/sources +175 after fix; review: no BLOCK/WARN, 3 NOTEs (one fixed); 15/15 negative controls FAIL as expected (W2-C1..C15), restores proven by sha256 | (wave 2 commit) |
| Finish | done | Built differently written; push, PR and phone install wait for the user | |

| Session | Started | Ended | Note |
|-|-|-|-|
| plan + run | 2026-11-13T20:38:32+0200 | 2026-11-13T21:46:15+0200 | lightweight, one session |

| Job | Agent id | Dispatched | Reported | Checked | Committed |
|-|-|-|-|-|-|
| Setup | a4170b92a00b1fb5b | 2026-11-13T20:40:31+0200 | done | done | 563ec61 |
| J1 | a7917e74252b2044d | 2026-11-13T20:42:08+0200 | 2026-11-13T20:51:00+0200 | 2026-11-13T20:52:12+0200 | |
| T1 | a0ef3606d692cc475 | 2026-11-13T20:52:12+0200 | | | |
| J2 | aa0b8a1e88bc3b673 | 2026-11-13T20:42:08+0200 | 2026-11-13T20:54:10+0200 | 2026-11-13T20:56:29+0200 | |
| T2 | a0e18cbe4567d2e50 | 2026-11-13T20:56:29+0200 | | | |
| J3 | af116aec10d0f93b3 | 2026-11-13T20:56:29+0200 | 2026-11-13T21:10:30+0200 | 2026-11-13T21:12:47+0200 | |
| T3 | a968c239ef544008b | 2026-11-13T21:12:47+0200 | | | |

Decisions taken (overturnable):
- W1/J2 - Two accounts of one kind whose names differ only in case stay in arrival order (stable tie-break by arrival index). Tests must not assert an order between them beyond that.
- W1/J2 - A blank (whitespace-only) owner or account counts as absent; null equals null is not primary; a Google calendar with a person owner and no account name is Shared (the literal rule).
- W1/J2 - Google owner suffix checks run on the trimmed, lower-cased owner; account types and `local.samsungbirthday` match exactly.
- W1 - Plan gap: the existing `calendars are listed with an opaque ARGB colour` test compares whole maps, so it must list the five new keys. T1 (owner of the test file) updates its expected map; "add tests only" is relaxed for that one assertion.
- W1 - J3 dispatched once J2 passed Check, before the wave 1 close: it owns no wave 1 file and needs only J2's interface. If the wave 1 review changes that interface, J3 gets a fix brief.
- W2/J3 - Heading semantics use `container: true`; rows are `MergeSemantics(Semantics(enabled: !disabled, ...))` like ListTile, so tappable pickOne rows now report an enabled state; the trailing label is capped at 120 dp; the not-synced dot is dimmed through its colour alpha (0.38), not an `Opacity` widget; the footnote string is a private const.
- W2 - Review NOTE accepted and fixed: `pickOne ignores a not-synced calendar` now pins the enabled state of a synced row (true) and a not-synced row (not true). The reviewer's optional tightening of the blocked-row check from `isNot(isTrue)` to `isFalse` is not taken in this run (would interrupt the hash-proven controls); a candidate follow-up.
- W2 - Review NOTE accepted, no change: the `_chosen` not-synced guard is defence in depth with no test of its own (the UI makes it unreachable).
- W2 - T3 may update existing assertions in add_source_panel_test.dart, source_detail_screen_test.dart and onboarding_test.dart that break only because of spec'd changes (account line moved into the heading, new subtitle). Each such edit is listed in its report.
- W1/J2 - `CalendarGroup.accountName` passes the provider value through: null and '' are both "no account name" for the heading, and (type, null) and (type, '') are two groups.

## Built differently from this plan

The code on `claude/spec-calendar-grouping-e06b35` is authoritative. Each item is in "Decisions taken" above.

- **`CalendarGroup.showAccountLineFor(c)`** is a per-row method (plan §3), not the `showAccountLine` field spec §5 names, because Holidays shows the line for Google rows but not for Samsung's LOCAL birthday calendar.
- **Grouping edge cases** (J2): accounts tied by a case-insensitive name keep arrival order; a blank owner or account counts as absent; Google owner suffixes match in any case; null and empty account names stay distinct groups, both shown as the kind word alone.
- **Semantics** (J3): headings are `Semantics(container: true, header: true)` over an excluded `Text.rich`; rows are `MergeSemantics(Semantics(enabled: !disabled))`, like ListTile, so pickOne rows (no checkbox) report enabled or not.
- **Layout** (J3): the trailing label is capped at 120 dp; the not-synced dot is dimmed through its colour alpha (0.38), not an `Opacity` widget; the footnote also shows in pickOne (after the last group).
- **Tests**: the existing `calendars are listed with an opaque ARGB colour` expectation lists the five new keys; `add_source_panel_test.dart` checks `OTHER · me@gmail.com` (the account moved into the heading) and the new subtitle.
- **Not covered by a test**: the `_chosen` not-synced guard (the UI makes it unreachable). The pickOne blocked-row check is `isNot(isTrue)`, not `isFalse`.
- **Not run**: the manual check on the S24 (spec §8, "On the phone"). It needs a debug build installed, which waits for the user.
