# Plan 4b: Meetings in More Than One Source

> **Execution: subagent-driven, using the orchestrator pattern** (roadmap "Execution"). Do not execute this plan inline. Run `/orchestrate` in plan mode on this file to produce an orchestration plan (workers: `dev-worker`, `review-worker`, `deep-review`, `scout`), then run that plan with `/orchestrate <path>` in a fresh session. Test authors write each task's tests from its **Acceptance** list without reading the implementation. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A meeting present in more than one calendar source rings once. Its acknowledgements, overrides and history carry across the merge and survive the sources splitting again.

**Spec:** `docs/superpowers/specs/2026-10-06-tminus-design.md` §13 (authoritative), with §5, §6 and §9. Binding contracts: roadmap §3 (`PlannedAlert`, `alarm_engine`, engine rules) and Plan 4's decisions (`docs/superpowers/plans/2026-10-06-plan-4-sources-sync.md`, including "Built differently").

**Base:** `main` once FifoTheHein/tminus#7 (Plan 4) is merged. Until then, branch `plan-4-sources-sync`. Everything below names Plan 4's code as built on that branch.

**Architecture:** The cache stays per source, and each cached row is a *copy*. A new pure function, `MeetingMerger.merge`, turns the enabled sources' copies, plus the stored `meeting_links`, into *meetings*. A meeting is an `EventOccurrence` whose `key` is the sticky meeting key and which knows its copies' keys, `seriesUid`s and source ids. `RulesEngine` and `buildPlan` look overrides and acknowledgements up under all of those keys, so a one-copy meeting behaves exactly as today. `SyncService._plan` calls the merger between the cache read and the rules engine, then saves the link changes it returns. Kotlin does not change: it only ever sees the meeting key.

## Global Constraints

- Plan 4's global constraints all apply: gates, `dart format` scope, no edits to `alert.dart` / `planned_alert.dart`, one engine-event consumer, the ICS link as a secret, UTC everywhere, and the commit style.
- **No Kotlin changes** except Task 6 (and only if Task 1 finds a UID column). `alarm_engine` stays as roadmap §3 says; Task 6 may append one nullable field to `queryInstances` rows.
- **Behaviour for single-source users must not change.** Every existing test in `rules_engine_test`, `plan_builder_test` and `sync_service_test` passes unchanged. That is a gate for Tasks 3 and 5.
- `MeetingMerger` is pure: no I/O, no clock, and deterministic for the same input in any order. Plan 5's Agenda calls it too (read-only).
- Gates at the end of every task, from the repo root: `flutter analyze` → `No issues found!`; `flutter test` → `All tests passed!`; the Kotlin unit tests if Kotlin changed (Task 6 only).

## Decisions (agreed with the user, 2026-10-09)

1. **Matching:** fingerprint plus remembered links, and the iCal UID as a strong key where a copy has one (spec §13). Copies merge only across different sources.
2. **Ranking:** healthy before failing, then phone before ICS before debug, then the copy holding the meeting key, then source id. The rest of the fields are filled in rank order (spec §13 table).
3. **Removal:** union. A meeting lasts while any enabled source lists it.
4. **Sticky meeting key:** a new meeting takes its top-ranked copy's key. Lookups also try every copy's own key and `seriesUid`. The key survives splits.
5. **Setting `merge.enabled`**, default on. Plan 5 adds the switch.
6. **Phone UID:** the design works without it. Task 1 probes the user's phone. Task 6 runs only if the probe finds a column holding the ICS UID.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `drift_schemas/drift_schema_v1.json`, `drift_schemas/drift_schema_v2.json` | Schema dumps for migration tests | 2 |
| `lib/core/storage/tables.dart` | + `MeetingLinks` table, + `Occurrences.icalUid` | 2 |
| `lib/core/storage/app_database.dart` | `schemaVersion` 2, `from < 2` step | 2 |
| `lib/core/model/meeting_link.dart` | `MeetingLink`, `MeetingMatch` | 2 |
| `lib/core/storage/meeting_link_repository.dart` | Read all links, apply changes, prune | 2 |
| `lib/core/model/event_occurrence.dart` | + `icalUid`; + `lookupKeys`, `lookupSeriesUids`, `sourceIds` getters | 2, 3 |
| `lib/core/model/meeting_occurrence.dart` | `MeetingOccurrence extends EventOccurrence` | 3 |
| `lib/core/sources/occurrence_mapping.dart` | ICS copies set `icalUid = uid` | 2 |
| `lib/core/rules/rule_set.dart`, `lib/core/rules/rules_engine.dart` | Override and source-default lookups over the lookup lists | 3 |
| `lib/core/planner/acknowledgements.dart`, `lib/core/planner/plan_builder.dart` | Ack and dismiss lookups over the lookup keys | 3 |
| `lib/core/planner/meeting_merger.dart` | `MeetingMerger.merge`, `MergeResult`, `SourceRank` | 4 |
| `lib/core/sync/sync_service.dart` | Merge in `_plan`, save links, Feed stale by time source, `SyncReport.merged` | 5 |
| `lib/app/di.dart` | Register `MeetingLinkRepository` | 5 |
| `lib/features/token_preview/sync_debug_panel.dart` | Show `merged N` in the status line | 5 |
| `calendar/DeviceCalendarReader.kt`, `lib/core/sources/device_calendar_api.dart`, `occurrence_mapping.dart` | Read the UID column (conditional) | 6 |
| roadmap §3 `queryInstances` row, roadmap §4 | Contract notes | 5, 6 |

Tests mirror `lib/` under `test/`: `test/core/planner/meeting_merger_test.dart` is new. The others extend existing files.

---

### Task 1: Probe the phone for the iCal UID (manual, user)

**Files:** none. Record the result in this plan under "Probe result" and in the PR description.

The cloud container has no emulator, and only the user's phone has an Outlook/Exchange account. Run from Git Bash with the phone connected (`export MSYS_NO_PATHCONV=1`). The `adb shell` user can read the calendar provider (Plan 4 Task 15 uses it).

- [x] **Step 1:** List the calendars and note the `_id` and `account_type` of the Outlook-synced one:
  ```bash
  adb shell content query --uri content://com.android.calendar/calendars --projection _id:calendar_displayName:account_name:account_type
  ```
- [x] **Step 2:** Pick a meeting that is also in the published feed (a one-off and an instance of a recurring meeting), then dump its candidate columns. Replace `<id>` and `<word>`:
  ```bash
  adb shell "content query --uri content://com.android.calendar/events --projection _id:title:dtstart:original_id:original_instance_time:uid2445:_sync_id:original_sync_id:sync_data1:sync_data2:sync_data3:sync_data4:sync_data5:sync_data6:sync_data7:sync_data8:sync_data9:sync_data10 --where \"calendar_id=<id> AND title LIKE '%<word>%'\""
  adb shell "content query --uri content://com.android.calendar/extendedproperties --projection event_id:name:value --where \"event_id=<event _id>\""
  ```
  If the provider refuses a column, drop it from the projection and note which one.
- [ ] *(not done: the cached feed could not be read over `adb`; see "Probe result")* **Step 3:** Open the published `.ics` file, find the same meeting's `SUMMARY`, and read its `UID:` line. Unfold it first: a line starting with a space continues the previous line. Outlook UIDs look like `040000008200E00074C5B7101A82E008…`.
- [x] **Step 4:** Record which column, if any, equals the feed UID: exactly, case-insensitively, or with a prefix/suffix. Note whether it is filled for both the one-off and the recurring instance, and whether `original_instance_time` equals the feed's `RECURRENCE-ID` for a moved instance. **No match → Task 6 is skipped.** Do not paste titles or UIDs into the PR, only column names and yes/no.

**Probe result (2026-10-10, the user's phone, Android 16 / One UI, Outlook app sync):** **no column holds the iCal UID, so Task 6 is skipped.**

- The probe was a read-only script that printed counts and yes/no only, never titles or UID values. The user ran the final pass themselves.
- The Outlook-synced calendars have account type `com.microsoft.office.outlook.USER_ACCOUNT` (the Outlook app's own sync adapter, not Samsung's Exchange adapter). There are 5 calendars and one holds events: 798 rows, of which 20 are series masters, 603 are exceptions or instances and 175 are one-offs.
- The provider allows every candidate column on `Events` (`uid2445`, `_sync_id`, `original_sync_id`, `sync_data1`–`10`). On `Instances` it allows `uid2445`, `_sync_id` and `original_sync_id`, and refuses `sync_data*`.
- `uid2445` is empty on every row, in Events and in Instances.
- `_sync_id`, `sync_data1`, `sync_data3` and `sync_data7` (exceptions only) are filled on most rows, and `original_sync_id` on every exception. None of their values starts with the Outlook GOID prefix `040000008200E00074C5B7101A82E008`, and none is a long hex string. They are the adapter's own ids.
- No exact comparison with the feed's UIDs was possible, because the app's cached feed file was not readable over `adb`. The verdict rests on the pattern check.
- The `extendedproperties` table returned no rows for these events.
- Step 2's command names the column `original_instance_time`. The provider calls it `originalInstanceTime` and refuses the whole query on the wrong name. The probe asked for `originalInstanceTime`, but it did not compare it with the feed's `RECURRENCE-ID`, because no feed was readable. Plan 4 decision 14 already relies on the two being equal.

---

### Task 2: Schema 2: `meeting_links` and `occurrences.ical_uid`

**Files:** `tables.dart`, `app_database.dart`, `meeting_link.dart`, `meeting_link_repository.dart`, `event_occurrence.dart` (field only), `occurrence_repository.dart`, `occurrence_mapping.dart`, `drift_schemas/`, tests.

- [x] **Step 1 (before touching `tables.dart`):** dump schema 1: `dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/`. Do this first, because once the tables change, v1 can't be dumped any more.
- [x] **Step 2:** `EventOccurrence` gains `final String? icalUid` (constructor, `copyWith` and `==`; `hashCode` stays as it is). `occurrenceFromIcs` sets it to `o.uid`; `occurrenceFromDevice` leaves it null. `Occurrences` gains a nullable `icalUid` text column; `OccurrenceRepository` reads and writes it.
- [x] **Step 3:** The table, model and repository:
  ```dart
  enum MeetingMatch { uid, fingerprint, remembered } // stored by name; append only

  class MeetingLink {
    final String copyKey;    // EventOccurrence.key of one copy (primary key)
    final String meetingKey; // the sticky key the meeting is planned under
    final String sourceId;
    final String uid;        // the copy's uid, for one-off re-matching
    final bool oneOff;       // copy.seriesUid == null
    final DateTime endUtc;   // the copy's end; pruning
    final MeetingMatch matchedBy;
  }
  ```
  - Table `meeting_links`: PK `copy_key`, plus indexes `(source_id, uid)` and `(meeting_key)`. **No foreign key to `sources`**, because links must outlive a deleted source (spec §13).
  - Repository methods: `all()`; `apply({required List<MeetingLink> upsert, required Set<String> delete})` in one transaction; `deleteEndedBefore(DateTime)`.
- [x] **Step 4:** Set `schemaVersion = 2`. Replace the `throw` in `onUpgrade` with an `if (from < 2)` step that adds the column and creates the table, and keep the comment's rule: shipped steps are never edited. Dump v2 and generate the migration test helpers (`drift_dev schema generate drift_schemas/ test/generated_migrations/`).

**Acceptance (tests):**
- `app_database_test`: `schema 1 upgrades to 2 keeping sources, occurrences, overrides and history` (SchemaVerifier); `a fresh database is schema 2`.
- `cache_storage_test`: `icalUid round-trips`.
- `occurrence_mapping_test`: `an ICS copy carries its UID as icalUid`; `a phone copy has no icalUid`.
- New `meeting_link_storage_test`: `apply upserts and deletes in one transaction`; `deleteEndedBefore keeps links of copies that end later`; `deleting a source keeps its links`.

---

### Task 3: Lookups over a meeting's copies

**Files:** `event_occurrence.dart`, `meeting_occurrence.dart`, `rule_set.dart`, `rules_engine.dart`, `acknowledgements.dart`, `plan_builder.dart`, tests.

- [x] **Step 1:** Add the lookup getters to `EventOccurrence`, with defaults for a plain copy:
  ```dart
  /// Keys to look overrides and acknowledgements up under, best first.
  List<String> get lookupKeys => [key];
  List<String> get lookupSeriesUids => [?seriesUid];
  /// Sources in rank order, for the source default (§6 step 5).
  List<String> get sourceIds => [sourceId];
  ```
- [x] **Step 2:** Add `MeetingOccurrence extends EventOccurrence`. Its fields are the merged values, plus `meetingKey`, `copies` (in rank order) and `timeSourceId`. It overrides `key` (→ `meetingKey`), `lookupKeys` (meeting key, then each copy key, de-duplicated), `lookupSeriesUids` (copies' non-null `seriesUid`s in rank order, de-duplicated), `sourceIds`, `==`, `hashCode` and `copyWith` (which must keep the meeting fields; nothing in the rules or plan path may turn a meeting back into a plain copy).
- [x] **Step 3:** `RuleSet` gains `occurrenceOverrideFor(List<String> keys)` and `seriesOverrideFor(List<String> uids)`, each returning the first match, and `sourceDefaultFor(List<String> sourceIds)`, returning the first that has a default. `RulesEngine` uses them wherever it now reads `o.key`, `o.seriesUid` or `sourceDefaults[o.sourceId]` (`resolve`, `_turnedOnProfile`, `_fromRulesAndDefaults`).
- [x] **Step 4:** `Acknowledgements` gains `isAnyOccurrenceAcked(Iterable<String> keys, DateTime start)`. `buildPlan` drops an occurrence if any `lookupKeys` entry is acked at `o.startUtc`. It drops an alert if `idFor(k, offset)` is dismissed at `o.startUtc` for any `k` in `lookupKeys`. Ids and `occurrenceKey` stay `idFor(o.key, …)` / `o.key`.

**Acceptance (tests):**
- `rules_engine_test`:
  - `an occurrence override on a copy key applies to the meeting`
  - `an override on the meeting key beats one on a copy key`
  - `a series override on any copy's seriesUid applies`
  - `the source default comes from the first ranked source that has one`
  - all existing tests unchanged and green.
- `plan_builder_test`:
  - `Dismiss all under a copy key drops the meeting at the same start`
  - `… but not at a different start`
  - `a single dismissal under a copy key's alert id drops that offset only`
  - `a meeting's alerts are keyed by the meeting key`
- `meeting_occurrence_test` (new, small): `lookupKeys start with the meeting key and hold no duplicates`.

---

### Task 4: `MeetingMerger` (pure)

**Files:** `lib/core/planner/meeting_merger.dart`, `test/core/planner/meeting_merger_test.dart`.

```dart
class SourceRank {
  const SourceRank({required this.kind, required this.failing});
  final SourceKind kind;
  final bool failing; // last fetch failed (SourceSyncState.lastError != null)
}

class MergeResult {
  final List<EventOccurrence> meetings;   // plain copies and MeetingOccurrences; keys unique
  final List<MeetingLink> upsert;
  final Set<String> delete;               // copy keys whose links are dropped
  final Map<String, String> timeSource;   // meeting key → sourceId of its time
  int get merged;                         // meetings with ≥ 2 copies
}

abstract final class MeetingMerger {
  static MergeResult merge({
    required List<EventOccurrence> copies,  // enabled sources only
    required List<MeetingLink> links,
    required Map<String, SourceRank> sources,
    bool enabled = true,
  });
  static String? fingerprint(EventOccurrence c); // null for untitled copies
}
```

Algorithm. It is deterministic, and the input order must not matter, so sort the copies by key first.

1. **Off:** if `enabled` is false, return the copies unchanged, with no link changes and `timeSource[key] = sourceId`.
2. **Seed** groups from the links. A copy belongs to meeting `m` when:
   - its key has a link to `m`; else
   - its own key equals some linked `meetingKey` `m`; else
   - it is a one-off (`seriesUid == null`) whose `(sourceId, uid)` has a one-off link to `m` (if several, the earliest `endUtc`, then the lowest `meetingKey`).

   The first rule that applies decides, so a copy is seeded into at most one meeting.

   Within a group keep one copy per source, in this order: the one whose key is `m`, then the one with a direct link, then the lowest key. Eject the others: they are treated as unlinked, and their direct links go into `delete`.
3. **Match** the unlinked copies in rank order, then by key.
   - Compute each copy's strong key `(icalUid, originalStartUtc)` and its fingerprint.
   - A value shared by two copies of the *same* source is ambiguous and is not used.
   - A copy joins the one group (seeded, or formed earlier in this pass) that has no copy from its source and has a member with an equal strong key or fingerprint.
   - With no candidate group it starts a new group. With more than one candidate it stays alone.
4. **Rank** within a group by (failing, kind: device < ics < debug, holds the meeting key, sourceId).
5. **Key:** a seeded group keeps `m`. A new group with two or more copies takes its top-ranked copy's key. A lone, unlinked copy keeps its own key and gets no link.
6. **Fields:** as in the spec §13 table. `timeSource[m]` is the top-ranked copy's `sourceId`. A group of one copy whose key is not `m` (a split) is emitted as a `MeetingOccurrence` so that it plans under `m`.
7. **Links:** for every group with two or more copies, or a seeded `m`, upsert one link per copy. `matchedBy` is `uid` / `fingerprint` for this pass's match, and `remembered` for a seeded one.

**Acceptance (tests, `meeting_merger_test`):**
- Matching
  - `an ICS and a phone copy with the same title and original start merge`
  - `titles match after trimming, case-folding, collapsing spaces and dropping Canceled:`
  - `different titles do not merge`
  - `untitled copies never merge on fingerprint`
  - `all-day and timed copies at the same instant do not merge`
  - `two copies in the same source never merge`
  - `a fingerprint shared by two copies of one source merges neither`
  - `the same feed added twice merges by UID`
  - `a strong key merges copies whose titles differ`
  - `a copy matching two meetings joins neither`
  - `a third source joins an existing meeting`
- Moves
  - `a moved series instance still merges while the feed shows the old time`
  - `a moved one-off stays merged through its remembered link`
  - `without a link a moved one-off does not merge`
- Ranking and fields
  - `the phone copy decides the time`
  - `a failing phone source loses to a healthy feed`
  - `the Join link, location and busy status fill in from the next copy`
  - `declined or cancelled on any copy marks the meeting`
  - `the colour comes from the time source`
- Keys and links
  - `a new meeting takes its top-ranked copy's key`
  - `the meeting key stays when the ranking changes`
  - `after a split the remaining copy keeps the meeting key`
  - `a copy whose key is a meeting key joins that meeting`
  - `meeting keys are unique for any input` (table of mixed cases)
  - `links are written for every copy of a merged meeting and none for lone copies`
  - `an ejected duplicate's link is deleted`
- Off and determinism
  - `with merging off, copies pass through unchanged`
  - `the result does not depend on input order`

---

### Task 5: Wire it into `SyncService`

**Files:** `sync_service.dart`, `di.dart`, `sync_debug_panel.dart`, `test/core/sync/sync_service_test.dart`, roadmap §4.

- [x] **Step 1:** `SyncService` takes a `MeetingLinkRepository links` and adds the constant `static const mergeEnabledKey = 'merge.enabled'`. Merging is off only when the stored value is `'false'`.
- [x] **Step 2:** In `_plan`:
  1. Read the cache as today, filtered to enabled sources.
  2. Build `sources` ranks from `configs` and `sources.syncState(id)` (`failing = lastError != null`; `_store` has already written this run's state).
  3. Call `MeetingMerger.merge`, then `links.apply(upsert:, delete:)`.
  4. Resolve and plan `result.meetings`.
  5. Return the plan and `result.timeSource`.

  `_run` calls `links.deleteEndedBefore(now − occurrenceRetention)` next to `occurrences.deleteEndedBefore`.
- [x] **Step 3:** `_staleNotices` replaces `a.occurrenceKey.startsWith('${c.id}|')` with `timeSource[a.occurrenceKey] == c.id`.
- [x] **Step 4:** `SyncReport.merged` (`int`, default 0); the run's sync-log message appends `, N merged` when N > 0. The debug panel's status line shows it, and the panel gets a **Merge duplicates** on/off control that writes `merge.enabled` (debug builds only, a stand-in for Plan 5's switch, like Plan 4 decision 23). In DI, register the repository and pass it in, in both the UI isolate and the headless one.
- [x] **Step 5:** Roadmap §4: one line saying that occurrences reach rules and the planner as meetings (spec §13), that `occurrenceKey` in plans and history is the meeting key, and that Plan 5's Agenda must call `MeetingMerger.merge` with `MeetingLinkRepository.all()`.

**Acceptance (tests, `sync_service_test`, with fake sources):**
- `an ICS feed and a phone calendar holding the same meeting plan one set of alerts`
- `removing the phone source keeps the meeting key and its alert ids`
- `Dismiss all before a source is removed still holds afterwards`
- `a phone calendar cleared by the empty-feed guard leaves its meetings to the feed under the same key`
- `a phone source whose access was revoked loses the time to a healthy feed`
- `a stale feed whose meeting is timed by a healthy phone calendar posts no Feed stale`
- `a stale feed timing its own meeting still posts Feed stale`
- `with merge.enabled false both copies are planned`
- `links persist between runs and are pruned a day after the copy ends`
- `no missed (system) row when a merged meeting splits before its alert`
- every existing test unchanged and green.

---

### Task 6 (only if Task 1 found a column): Read the phone's iCal UID

**Files:** `DeviceCalendarReader.kt` (+ test), `device_calendar_api.dart`, `occurrence_mapping.dart`, roadmap §3 `queryInstances` row.

- [ ] *(skipped: Task 1 found no UID column, run-log decision 1)* Project the column Task 1 found, and send it as `"icalUid": String?`. Normalise it the way Task 1 recorded (for example, upper-case it, or strip a prefix). Empty becomes null. The column comes from `Instances` if the provider allows it there, otherwise from one `Events` query by event id (record which one). `DeviceInstance.icalUid` → `EventOccurrence.icalUid`.
- **Acceptance:**
  - Kotlin: `instances carry the iCal UID when the provider has one`, `an empty UID is sent as null`.
  - Dart: `a phone copy carries the iCal UID`.
  - Merger (extend Task 4's file): `a phone and an ICS copy with the same UID merge even when titles differ`.

---

### Task 7: Manual device verification

Record each step's result in the PR description, as in Plan 4 Task 15.

- [x] **Step 1:** Add the real published feed (debug **Add feed**) and the Outlook-synced phone calendar (**Add phone calendar**, or Plan 5's picker). **Sync now**. The status reads `… merged N`. "Next 5 scheduled" lists each meeting once, and `dumpsys alarm | grep -c tminus.action.FIRE` is about half of the count with merging off (turn **Merge duplicates** off, **Sync now**, count, then turn it back on).
- [x] **Step 2:** Move a meeting that starts within the next few hours in Outlook. When the phone calendar updates (a calendar-change sync), the alarm moves to the new time and does not also stay at the old time, even though the feed still lags.
- [x] **Step 3:** Use **Dismiss all** on a merged meeting's heads-up, then **Remove all sources** except the phone calendar, then **Sync now**. That meeting does not ring again.
- [x] **Step 4:** Revoke `READ_CALENDAR` (Plan 4 Task 15 Step 15). The feed's copy now decides the time. No meeting is lost, and no duplicate appears.

**Device results (2026-10-11):** Pixel_9 AVD, Android 16 (API 36), debug build of f470d2f, installed with `install -r` over the Plan 4 build and its data. The app started with no crash and its first headless sync finished `ok`, so the schema 1 → 2 upgrade ran on a device. The real Outlook feed and phone calendar were not used. The run used a synthetic fixture instead: three meetings (A, B, C) served as an ICS feed from the host at `http://10.0.2.2:8765/merge.ics`, plus the same three meetings at the same UTC times in a local `TMinusTest` phone calendar.

- Step 1: pass.
  - Adding both sources gave `6 alerts planned · … · merged 3`, and "Next 5 scheduled" listed each meeting once.
  - With **Merge duplicates** off: `12 alerts planned`, and the duplicates showed. Back on: `6 alerts planned · … · merged 3`.
  - `dumpsys alarm | grep -c tminus.action.FIRE` gave 13 / 18 / 17. That grep also counts alarm-history lines, and the alerts were firing while it was taken, so the app's planned-alert counts (6 against 12) are the measure.
- Step 3: pass.
  - Meeting A's heads-up fired while merging was off, so its notification read "2 meetings starting" and listed A twice, once for each copy. That is expected with merging off.
  - **Dismiss all** was pressed after merging was back on (History: `dismissedAll 2`). So the acknowledgements were stored under the two *copy* keys.
  - The phone copy of A was then deleted. The deletion takes the place of "Remove all sources except the phone calendar", which the debug panel cannot do. It split the meeting (`merged 2`).
  - A was no longer planned, and it did not ring at its start. This also shows that acknowledgements stored under copy keys hold for the meeting.
- Step 2: pass. Moving the phone copy of B 10 minutes later started a calendar-change sync (`finished: ok`). B was then listed once, at the new time, and not also at the feed's old time.
- Step 4: pass.
  - With `READ_CALENDAR` revoked, the status read `… merged 2 · device-…: calendarAccessDenied`, and one "TMinusTest: calendar access was turned off" notification appeared.
  - B went back to the feed's (old) time, listed once, and C stayed.
  - With the permission granted again, B returned to the phone's new time.
- The emulator's cold boot was slow (System UI and the app showed "isn't responding" once, and the scout tapped **Wait**). No app crash was logged.

---

## Review Focus

1. **A single-source user sees no change.** Keys, ids, explanations and plans are identical to Plan 4, because every existing test passes unchanged.
2. **Unique meeting keys.** Two meetings sharing a key would merge their alert ids in Kotlin and silently drop one. Pinned by `meeting keys are unique for any input`.
3. **Splits keep acknowledgements.** A dismissed meeting must not re-ring when a source is removed, disabled or emptied. Pinned in Task 5.
4. **A stale or failing copy never decides the time over a healthy one.** Pinned in Tasks 4 and 5.
5. **Determinism.** The Agenda (Plan 5) and the sync must agree, because the merger is pure and order-independent. Pinned in Task 4.

## Notes for Plan 5

- The Agenda and the event sheet must show meetings, not copies: call `MeetingMerger.merge(copies, await links.all(), ranks, enabled: …)` on the cached copies of enabled sources. The event sheet can list `MeetingOccurrence.copies` as "In: Outlook (phone), Work feed".
- Overrides written from the UI go on the **meeting key**. Clearing an override should also clear any override on the copy keys (`lookupKeys`), otherwise it seems to come back.
- The Settings switch writes `merge.enabled` (`'true'` / `'false'`) and then runs a sync.
- `SourceAdmin.addDeviceSource` could warn when the same Android calendar is already a source. A duplicate is harmless after this plan but pointless.
- **History titles after a split (found in the Task 5 review).** `EngineEventRecorder._record` fills a history row's title from `occurrences.byKey(occurrenceKey)`. After a split whose meeting key no longer belongs to any cached copy (for example, the phone source was removed and the feed's copy now plans under the phone copy's key), `fired`, `dismissedAll` and `snoozed` rows get a null title. Acknowledgements are unaffected, because they match on key and start. Either look the title up through a link whose `meetingKey` is the event's key, or carry the title in the engine event.

## Not covered

- A phone copy titled `Canceled: …` without `STATUS_CANCELED` is not marked cancelled by `occurrenceFromDevice`, unlike ICS (`isCancelledTitle`). That gap predates this plan; merging only ORs the flag. Worth a small Plan 5 fix.
- Unmerging a single false match from the UI (only the global switch exists).

---

## Run log (orchestrated, 2026-10-10)

Run with `/orchestrate` in a lightweight form, as Plan 4 was: one session directed the whole run, with no Gate-0 stop, no fresh session per wave and no time booking. `dev-worker`s built one task each, together with that task's tests. `scout`s did the setup, re-ran each acceptance and every test run, ran the negative controls and the commits, and did the device work. One `review-worker` reviewed every wave, and `deep-review` took Task 2's schema migration.

**Baseline** (branch `claude/plan-4b-impl-9b39a6`, cut from `plan-4b-multi-source-design` at 718ec2c): `flutter analyze` → No issues found; `flutter test` → 371 passed; `./gradlew :app:testDebugUnitTest` → 241 passed, 0 failed.

**Waves:** 1 = Task 2 (+ deep review); 2 = Task 3; 3 = Task 4; 4 = Task 5; 5 = Task 7 (device). Each wave depends on the one before it. Tasks 2 and 3 both own `event_occurrence.dart`, and Task 6 is skipped.

**Decisions taken while running** (each can be overturned):

1. **Task 6 is skipped.** The Task 1 probe found no column holding the iCal UID (see "Probe result"). Phone copies keep `icalUid == null` and merge on fingerprint and remembered links.
2. **Each `dev-worker` writes its own task's tests** from the task's Acceptance list, in the same job, as in Plan 4. There is no separate test-author job. Every extra or fix test gets a negative control.
3. **Task 2: refuse downgrades.** Step 4 replaces `onUpgrade`'s `throw` with a `from < 2` step. A `from > to` throw stays as the first line, because drift 2.35 calls `onUpgrade` on a downgrade too and would otherwise re-stamp the stored version (deep-review finding).
4. **Task 2: the upgrade step writes first.** It runs in one transaction that starts with `createTable` (`IF NOT EXISTS`). The column is added only if it is missing. The deep review saw a risk of `SQLITE_BUSY` when two isolates migrate at once, but drift 2.35 opens every native transaction with `BEGIN IMMEDIATE` (`lib/src/sqlite3/database.dart:72`), so a second isolate already waits on `busy_timeout` and the order is only a defence if a transaction is ever deferred. No test covers it, because no ordering fails today.
5. **Task 3: lookups take the first match.** The source default comes from the first ranked source that has an entry in `sourceDefaults`, even if that entry names a deleted profile, which then falls to the global default. Occurrence overrides likewise use the first key in `lookupKeys` that has one. This follows spec §13 ("first in rank order"), and a single source behaves exactly as before.
6. **Task 3: `EventOccurrence ==` also compares `runtimeType`**, so a plain copy never equals a `MeetingOccurrence`. Plain copies compare as before. As a result, Task 4 emits a lone copy with no stored link as the plain `EventOccurrence`, and a one-copy `MeetingOccurrence` only after a split, when the meeting key differs from the copy's key.
7. **Task 3: `MeetingOccurrence` guards.** It needs at least one copy (an assert), and its copies are copied into an unmodifiable list. Task 4 must set `timeSourceId == sourceId == copies.first.sourceId`.
8. **Task 4: canonical order.** The merger sorts copies once, by (failing, kind, source id, key), and returns meetings sorted by key and `upsert` sorted by copy key. With merging off, the copies come back sorted by key and de-duplicated, not in input order. `buildPlan` sorts its own output, so nothing downstream depends on the order.
9. **Task 4: a copy turned away from a meeting falls through.** When another copy of its source holds its place in a meeting, it tries its next option before it is matched as unlinked: first its own link, then its own key being a meeting key, then the one-off link. The plan says such copies are "treated as unlinked", but read literally that can emit two meetings under one key. The review confirmed that unique keys need this.
10. **Task 4: links.** `delete` holds only the links of copies present in this run that end up in no linked meeting. Links of absent copies are never touched, so a split keeps its key. Every copy of every linked meeting has its link upserted on every run, so `endUtc` stays current. A source missing from the ranks ranks last, as failing and debug. An empty iCal UID is not a strong key.
11. **Task 4: `matchedBy`.** It is `remembered` if a stored link placed the copy, `uid` if another member shares its usable strong key, and otherwise `fingerprint`.
12. **Known limit (Task 4).** If the link table is inconsistent, a copy holding key `m` can sit in another meeting while other copies keep meeting `m`. Both meetings' `lookupKeys` then contain `m`, so a Dismiss all under `m` silences both when they start together. Normal runs cannot produce this, because a copy that holds `m` is never turned away from `m`.

**Steps:**

| Step | State | Evidence / commit |
|---|---|---|
| Setup + baseline | done | Gradle files copied, `pub get`, baseline above |
| Task 1 probe | done | Probe result above. Task 6 skipped |
| W1 Task 2 | done | analyze clean; `flutter test` 383 passed; review and deep review clean after 2 fixes (downgrade refused, write-first upgrade step) and 1 test fix (the `matchedBy` control survived); 14 negative controls all killed, restore proven by sha256. Commit 223dbd2 |
| W2 Task 3 | done | analyze clean; `flutter test` 406 passed (+23); existing rules, planner and sync tests unchanged (test diff is insertions only); review clean (notes became decisions 5–7); 23 negative controls all killed, restore proven by sha256. Commit 5fcb04a |
| W3 Task 4 | done | analyze clean; `flutter test` 455 passed (+49: 28 plan tests and 21 extras, including a 300-round fuzz test); review clean apart from one test gap (seeding order), fixed with a test; 78 negative controls all caught. R25 was caught by the merging-off test; the input-order test is not meant to catch it. Restore proven by sha256. Commit a7f383e |
| W4 Task 5 | done | analyze clean; `flutter test` 472 passed (+17: the 10 plan tests and 4 extras in `sync_service_test`, 3 in `sync_debug_panel_test`); the setup of existing tests only gained lines; review clean (history-title gap moved to Notes for Plan 5); 23 negative controls all caught, restore proven by sha256 |
| Final gates | done | On f470d2f: `flutter analyze` → No issues found; `flutter test` → 472 passed; `./gradlew :app:testDebugUnitTest` → 241 tests, 0 failures, 0 errors; `flutter build apk --debug` → built |
| Task 7 device check | done (emulator) | See "Device results (2026-10-11)" under Task 7 |
