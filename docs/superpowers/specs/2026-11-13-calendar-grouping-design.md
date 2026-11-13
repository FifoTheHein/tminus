# T-Minus: Group phone calendars in the picker — Design Spec

- **Date:** 2026-11-13
- **Status:** Agreed in brainstorming, pending written-spec review
- **Touches:** Sources → Add a calendar → **Use a calendar on this phone** (`CalendarPicker`), both its `pickMany` form (Add source, also used by onboarding) and its `pickOne` form (choosing a calendar again for a restored source).
- **Builds on:** spec §5 (`DeviceCalendarSource`), roadmap §3 (`alarm_engine` channel), Plan 4 decision 18 (**Already added**).

## 1. Purpose

The phone calendar picker is one flat list of every calendar on the phone, sorted by display name, with the account name in small grey text under each row. On a phone with several accounts that list is long and the rows look alike, so it is easy to add the wrong calendar.

### Why (the incident)

The user added an event in Samsung Calendar and it never reached T-Minus. Samsung Calendar had saved it to the Samsung account calendar, and only the Google calendars had been added as sources. On the user's phone (Galaxy S24, about 50 calendars) the picker showed:

- **Two calendars called "My calendar"**, one in the Samsung account and one that lives only on the phone, sorted next to each other and told apart only by the grey account line.
- The Samsung account and one Google account have the **same account name** (the same email address), so the account line did not separate them either.
- Around 30 Google calendars across three Google accounts, mixed together alphabetically.
- 24 calendars that are **not synced** to the phone at all (mostly colleagues' Google calendars and subscribed calendars). Adding one gives a source that never has events.

### Goals

1. Each calendar sits under a heading that says which kind of account it belongs to and which account, so the two "My calendar"s cannot be confused.
2. Other people's calendars are set apart from the user's own, where Android says so.
3. Holiday and birthday calendars are set apart, since they are rarely what an alarm is for.
4. A calendar with no events on the phone (not synced) is shown, marked and cannot be chosen, so the user is never left wondering why a calendar is missing or silent.

### Non-goals

- No change to what a device source stores, how it syncs or how its events become alarms.
- No guessing from calendar **names** (for example "Birthdays", "holidays"). Names are in the user's language and the user's own words; rules built on them break silently.
- No turning sync on from T-Minus. Sync belongs to the account's own app.
- No search box, no collapsing groups (see §9).
- No change to the Sources tab list itself, only the picker.

### Anti-goals (would make this a failure even if it works)

- A calendar the user wants is hidden or hard to find because of a wrong guess. When in doubt, a calendar stays in its account group.
- A calendar is labelled **Shared with you** when it is the user's own.
- Calendar names, account emails or owner addresses appear in logs, committed fixtures or anything persisted.

## 2. Approaches

| Approach | Trade-off | Verdict |
|---|---|---|
| **A. Kotlin passes raw facts, Dart groups** | Kotlin adds columns to the existing map; one pure Dart function owns every rule and is tested without a device. The owner address crosses the channel (it already does for `accountName`). | **Chosen.** All grouping rules in one place, unit-testable, matches how the reader already works (it returns rows, not decisions). |
| B. Kotlin classifies, sends a `group` label | The owner address never leaves Kotlin, but the rules are split across two languages and the Dart labels and order still live in Dart. Harder to test the whole picture. | Rejected. |
| C. Group by `accountName` only, Dart side, no channel change | No contract change. Cannot separate the Samsung account from a Google account with the same email, cannot detect not-synced, shared, holidays. | Rejected: does not fix the incident. |

Grouping depth was also decided: **by kind, then by account** (one heading per account) rather than by kind only. With three Google accounts a single "Google" group is about 20 to 30 mixed rows, which is the problem we are fixing.

## 3. What Android tells us (checked on the S24)

Metadata only was read, with `adb shell content query --user 0 --uri content://com.android.calendar/calendars`. No calendar names or emails are recorded here.

| Column (`CalendarContract.Calendars`) | Seen on the device | Use |
|---|---|---|
| `ACCOUNT_TYPE` | `com.google`, `com.osp.app.signin` (Samsung account), `com.microsoft.office.outlook.USER_ACCOUNT` (Outlook app), `LOCAL` | Kind of account (§4.1). |
| `ACCOUNT_NAME` | An email per account; the Samsung account shares one with a Google account. `LOCAL` rows use `My calendar` and `local.samsungbirthday`. | Account heading; with `ACCOUNT_TYPE` it identifies an account. |
| `OWNER_ACCOUNT` | Equal to `ACCOUNT_NAME` for each account's main calendar; a person's email for colleagues' calendars; `…@group.calendar.google.com` for Google secondary calendars; `…@import.calendar.google.com` for calendars subscribed by link; `…#holiday@group.v.calendar.google.com` for Google holidays. The Outlook app reports `OWNER_ACCOUNT == ACCOUNT_NAME` for **every** calendar, including a colleague's. | Shared and holiday detection, Google only (§4.2). |
| `CALENDAR_ACCESS_LEVEL` | 700 (owner), 600 (editor), 200 (free/busy). Colleagues' Google calendars often show 700 (delegated). | Google group-calendar ownership (§4.2). |
| `SYNC_EVENTS` | 0 on 24 of 50 calendars, all Google. | Not synced (§4.4). |
| `VISIBLE` | 0 on many unsynced calendars and on 3 synced ones. | Not used for grouping (§4.4). Already in the contract. |
| `IS_PRIMARY` | 1 on each account's main calendar. | Sort order inside a group (§4.3). |

No Google contacts-birthday calendar (`#contacts@group.v.calendar.google.com`) was present on this phone, but other phones have one, so the rules cover it.

## 4. Grouping rules

### 4.1 Kind of account

| `ACCOUNT_TYPE` | Kind | Heading |
|---|---|---|
| `com.google` | Google | `GOOGLE · <account name>` |
| `com.osp.app.signin` | Samsung | `SAMSUNG ACCOUNT · <account name>` |
| `com.microsoft.office.outlook.USER_ACCOUNT` | Outlook | `OUTLOOK · <account name>` |
| `com.android.exchange`, `com.google.android.gm.exchange`, `com.samsung.android.exchange` | Exchange | `EXCHANGE · <account name>` |
| `LOCAL` | Phone only | see §4.2 |
| anything else, or null | Other | `OTHER · <account name>` |

An **account** is the pair (`ACCOUNT_TYPE`, `ACCOUNT_NAME`), never the name alone. This is what puts the Samsung "My calendar" and a Google account with the same email under different headings.

The kind word is in the overline style, upper case; the account name after the `·` keeps its own case (§6). A null or empty account name shows the heading without `· <account name>`.

### 4.2 Special groups

Each calendar lands in exactly one group. Checked in this order, first match wins:

1. **Holidays and birthdays**
   - Google, `OWNER_ACCOUNT` ends with `#holiday@group.v.calendar.google.com` or `#contacts@group.v.calendar.google.com`.
   - `LOCAL` with `ACCOUNT_NAME == local.samsungbirthday` (Samsung's "Contacts' important dates").
2. **Shared with you** (Google only)
   - `OWNER_ACCOUNT` differs from `ACCOUNT_NAME` (compared case-insensitively, trimmed), **and** either
     - the owner is a person's address: it contains `@` and does not end with `.calendar.google.com` (this excludes `@group.calendar.google.com`, `@group.v.calendar.google.com` and `@import.calendar.google.com`), or
     - the owner ends with `@group.calendar.google.com` and `CALENDAR_ACCESS_LEVEL < 700` (someone else's group calendar the user can only read or edit).
   - A person's calendar is shared whatever its access level: colleagues who delegate often give 700.
   - `@import.calendar.google.com` calendars are calendars the user subscribed to by link; they stay in the account group.
   - Null `OWNER_ACCOUNT` is never shared.
   - A primary calendar (`IS_PRIMARY == 1`) is never shared, even if its owner differs (for example a Workspace alias). This guards the anti-goal.
   - `CALENDAR_ACCESS_LEVEL` is passed through as is; 0 (`CAL_ACCESS_NONE`) and null count as below 700.
3. **On this phone only**: every other `LOCAL` calendar.
4. Otherwise the calendar's **account group** (§4.1).

Outlook, Exchange, Samsung and Other accounts never produce **Shared with you** or **Holidays and birthdays**: Android does not tell us which of their calendars are someone else's or a holiday list (the Outlook app reports the same owner for all of them). Their read-only calendars stay under their account heading. This is deliberate (anti-goal: never mislabel). The two holiday and birthday rules in step 1 are the complete list: no other account type or name is matched.

### 4.3 Order

Groups, top to bottom:

1. Google accounts, by account name (case-insensitive).
2. Samsung accounts, by account name.
3. Outlook, then Exchange, then Other accounts; each kind by account name.
4. **Shared with you**
5. **Holidays and birthdays**
6. **On this phone only**

Inside a group: the primary calendar first (`IS_PRIMARY == 1`; if the column is null, `OWNER_ACCOUNT == ACCOUNT_NAME` stands in), then by display name (case-insensitive), then by id so the order is stable.

Rows in **Shared with you** and **Holidays and birthdays** come from several accounts, so they keep the grey account line under the name (as every row has today). Rows in an account group drop it: the heading says it. **On this phone only** rows drop it too (`My calendar` and `local.samsungbirthday` mean nothing to the user).

A group with no calendars is left out.

### 4.4 Not synced, hidden, already added

- **Not synced** (`SYNC_EVENTS == 0`): the row stays in its group, greyed (as an **Already added** row is today), with a trailing **Not synced** label, and cannot be ticked (`pickMany`) or picked (`pickOne`). A null `SYNC_EVENTS` counts as synced. If sync is turned on in the account's app, the row becomes available the next time the picker opens; there is no live refresh.
- When at least one row is not synced, one line sits under the list, above **Add selected**: "Calendars marked Not synced have no events on this phone. Turn on sync for them in their calendar app, then come back." (No em dash; `test/no_em_dash_test.dart` covers it.)
- **Hidden** (`VISIBLE == 0`) but synced: shown like any other row. It has events; hiding is a calendar-app display choice.
- **Already added** (decision 18) is unchanged: checked, disabled, **Already added** label. If the calendar is also not synced, already added wins for the checkbox (checked, disabled) and the label reads **Already added, not synced**, so the user sees why that source is quiet.
- `pickOne` blocks not-synced rows too: re-pointing a restored source at a calendar with no events would leave it silent. The user turns sync on and chooses again.
- Already-added and not-synced rows stay in their group in their normal sort position; nothing moves to the bottom.

## 5. Channel and contract changes

### `alarm_engine` · `queryDeviceCalendars` (roadmap §3)

Each map gains five keys. Existing keys and the error codes are unchanged.

| Key | Type | From | Missing or null |
|---|---|---|---|
| `accountType` | `String?` | `Calendars.ACCOUNT_TYPE` | null |
| `ownerAccount` | `String?` | `Calendars.OWNER_ACCOUNT` | null |
| `accessLevel` | `int?` | `Calendars.CALENDAR_ACCESS_LEVEL` | null |
| `syncEvents` | `bool` | `Calendars.SYNC_EVENTS != 0` | `true` |
| `primary` | `bool?` | `Calendars.IS_PRIMARY != 0` | null |

- `DeviceCalendarReader.CALENDAR_COLUMNS` gains the five columns. `calendars()` reads them null-safely (`isNull` before `getInt`), because providers leave columns empty and the Robolectric fake returns null for any column a test row omits.
- The sort order (`CALENDAR_DISPLAY_NAME ASC`) stays; Dart re-sorts.
- `instances()` still calls `calendars()` for its missing-calendar check; the extra columns cost nothing there. It does **not** start refusing not-synced calendars.
- Update the roadmap §3 row for `queryDeviceCalendars` and the KDoc on `calendars()` to list the new keys.

### Dart

- `DeviceCalendar` gains `accountType`, `ownerAccount`, `accessLevel`, `syncEvents` (default `true`) and `primary`, all optional in the constructor so existing test fakes still compile. `fromJson` reads them with the defaults above when a key is absent.
- New pure function, its own file `lib/features/sources/calendar_groups.dart`:
  - `enum CalendarGroupKind { google, samsung, outlook, exchange, other, shared, holidays, phoneOnly }`
  - `class CalendarGroup { kind; accountName (null for the three special groups); calendars; showAccountLine }`
  - `List<CalendarGroup> groupCalendars(List<DeviceCalendar> calendars)`: §4.1 to §4.3, no Flutter imports beyond what `DeviceCalendar` needs.
  - Heading text is built in the widget from `kind` and `accountName`, so the function stays free of strings the UI owns.
- `CalendarPicker` renders groups from `groupCalendars(_calendars)`. Selection, `takenIds`, `onAdd`, `onPick` and the access states are unchanged.

### Privacy

- `ownerAccount` is an email address. Like `accountName` it is held in memory for the picker only: never logged, never stored, never sent anywhere. `groupCalendars` reads it and the widget never shows it.
- No new persisted field. Debug output (`sync_debug_panel.dart`) is unchanged and must not print the new fields.

## 6. UI

Follows `docs/design-brief.md` (calm, dark first, calendar colour is the accent, status colours only for health) and the design system in `lib/app/theme/`.

```
┌ Use a calendar on this phone                    (●) ┐
│                                                      │
│ GOOGLE · alex@example.com                            │  ← overline, onSurfaceVariant
│ [ ] ●  alex@example.com                              │  ← primary first
│ [ ] ●  Family                                        │
│ [ ] ●  Book club                                     │
│                                                      │
│ GOOGLE · alex@work.example                           │
│ [✓] ●  alex@work.example           Already added     │
│ [ ] ●  Team planning                                 │
│                                                      │
│ SAMSUNG ACCOUNT · alex@example.com                   │
│ [ ] ●  My calendar                                   │  ← the one the event went to
│                                                      │
│ OUTLOOK · alex@corp.example                          │
│ [ ] ●  Calendar                                      │
│ [ ] ●  Birthdays                                     │  ← stays here (§4.2)
│                                                      │
│ SHARED WITH YOU                                      │
│ [ ] ●  Sam Lee                                       │
│        alex@work.example                             │  ← account line kept
│  ·  ◌  Pat Kim                       Not synced      │  ← greyed, no checkbox action
│        alex@work.example                             │
│                                                      │
│ HOLIDAYS AND BIRTHDAYS                               │
│ [ ] ●  Public holidays                               │
│        alex@work.example                             │
│ [ ] ●  Contacts' important dates                     │
│                                                      │
│ ON THIS PHONE ONLY                                   │
│ [ ] ●  My calendar                                   │
│                                                      │
│ Calendars marked Not synced have no events on this   │
│ phone. Turn on sync for them in their calendar app,  │
│ then come back.                                      │
│                                     [ Add selected ] │
└──────────────────────────────────────────────────────┘
```

- **Heading:** `context.tminusType.overline` in `scheme.onSurfaceVariant`, as the Agenda's `NEXT ALARM IN`. Kind word upper case; `· <account name>` in the same style but not upper-cased (`Text.rich`), one line, ellipsis at the end if long. Top padding `TMinusSpacing.md` (none above the first heading), bottom `TMinusSpacing.xxs`. Heading is not tappable.
- **Rows:** today's `_CalendarRow`, unchanged except: the account line shows only when the group says so; a not-synced row uses `scheme.onSurfaceVariant` for the name, the calendar dot at reduced opacity (0.38), a disabled checkbox showing unticked (checked if already added, §4.4), `onTap: null`, and the trailing label **Not synced** in `bodySmall` / `tertiaryText` like **Already added**.
- **Footnote:** `bodySmall` in `tertiaryText`, `TMinusSpacing.sm` above it.
- The choice card subtitle "Google, Samsung, Exchange accounts" becomes "Google, Samsung, Outlook and other accounts".
- No status colours, no new tokens, no new icons. Light theme works from the same tokens.
- `pickOne` (source detail, choose again) shows the same groups without checkboxes; a not-synced row is not tappable.

## 7. Accessibility

- Each heading is wrapped in `Semantics(header: true)` so TalkBack heading navigation jumps group to group. Its label reads the kind and account in sentence form, for example "Google, alex@example.com" (the overline upper-casing is visual only).
- Each row is one merged semantics node: name, then account if shown, then state. Not synced reads as "My calendar, not synced, unavailable"; already added as "…, already added". The disabled state is announced by the disabled checkbox / `onTap: null`, not only by colour.
- Greyed text keeps the contrast the **Already added** row already has (`onSurfaceVariant` on the card surface, WCAG AA for body text in both themes). The calendar dot is decoration and is excluded from semantics.
- Touch targets stay `TMinusSpacing.minTap` (48 dp). Headings do not shrink the row height.
- Large font (200%): headings wrap or ellipsize, never overlap the rows; rows grow vertically as today.

## 8. Testing

Every new test gets a negative control: revert the change it guards, see it fail, restore.

### Kotlin (Robolectric, `DeviceCalendarReaderTest`, `CalendarChannelTest`)

- `calendars()` maps the five new columns from a fake provider row.
- A row that omits them (as the existing `setUp` row does) gives `accountType = null`, `ownerAccount = null`, `accessLevel = null`, `syncEvents = true`, `primary = null`, without throwing.
- `SYNC_EVENTS = 0` gives `syncEvents = false`; `IS_PRIMARY = 1` gives `primary = true`.
- `CalendarChannelTest`: `queryDeviceCalendars` passes the new keys through.

### Dart unit

- `device_calendar_api_test`: `fromJson` with and without the new keys (defaults as §5).
- `calendar_groups_test` (new), table-driven, all fixtures use `example.com` style addresses:
  - each `ACCOUNT_TYPE` in §4.1 lands in its kind; an unknown and a null type land in Other;
  - Google and Samsung accounts with the **same account name** give two groups (the incident);
  - shared: person owner at 200 and at 700; group owner at 200, 600, 0 and null access shared; group owner at 700 not shared; import owner not shared; owner equal to account in different case not shared; null owner not shared; primary calendar with a person owner not shared;
  - holidays: Google `#holiday@…` and `#contacts@…`; `LOCAL` `local.samsungbirthday`;
  - Outlook calendars at access 200 stay in the Outlook group;
  - other `LOCAL` calendars land in On this phone only;
  - group order §4.3, accounts sorted case-insensitively; primary first, null primary falls back to owner equals account, then name, then id;
  - `showAccountLine` is true only for Shared and Holidays;
  - empty groups are left out; an empty input gives an empty list.

### Widget (`test/features/sources/`, new `calendar_picker_test.dart` or in `add_source_panel_test.dart`)

- Headings render in §4.3 order with the right text and `isHeader` semantics.
- Two "My calendar" rows appear under different headings.
- A not-synced row: label shown, checkbox disabled, tapping does nothing, it never reaches `onAdd`; the footnote shows only when such a row exists.
- Already added and not synced together shows **Already added, not synced**.
- `pickOne`: tapping a not-synced row does not call `onPick`.
- Existing picker tests (access states, Add selected, already added) still pass.
- `test/no_em_dash_test.dart` covers the new strings.

### On the phone (manual, after the build)

On the S24: the Samsung **My calendar** sits under **SAMSUNG ACCOUNT**, the phone-only one under **ON THIS PHONE ONLY**; colleagues' Google calendars are under **SHARED WITH YOU**; the 24 unsynced calendars are greyed; TalkBack heading navigation moves between groups.

## 9. Migration and compatibility

- **No database migration.** Device sources store `deviceCalendarId` (`tables.dart`, `SourceConfig`), plus their own name and colour. None of the new fields is persisted, so `schemaVersion` does not change. Checked against `SourceAdmin.addDeviceSource` / `updateDeviceCalendar`, which copy only `id`, `name` and `color` from `DeviceCalendar`.
- **Channel:** Dart and Kotlin ship in one APK, so there is no mixed-version case. The Dart defaults (§5) still make an old-shaped map safe.
- **Backups and restore:** unaffected. A restored source still waits for its calendar; `pickOne` now shows groups.
- `sync_debug_panel.dart` keeps using `visible`; unchanged.

## 10. Left to the builder

- Exact widget structure (a flat list of heading and row widgets inside the existing `Column`, or a small `_GroupHeader` widget) as long as §6 and §7 hold.
- Whether the widget test lives in a new file or in `add_source_panel_test.dart`.

### Decisions made while writing (flagged for review)

- Order puts **Outlook / Exchange / Other** accounts right after Samsung, before **Shared with you** (they are the user's own accounts).
- A separate **Holidays and birthdays** group, Google and Samsung birthdays only.
- Not-synced rows stay where they sort; there is a single footnote rather than a per-row hint.
- Choice card subtitle changes to "Google, Samsung, Outlook and other accounts".
- No collapse, no search: grouping is enough for about 50 calendars, and collapsing risks hiding the one the user wants.
- A primary calendar is never **Shared with you**, whatever its owner.
- `pickOne` blocks not-synced rows, like `pickMany`.
- A row both already added and not synced keeps the checked, disabled box.

### Follow-ups (not in this change)

- A device source added from a not-synced-later calendar (sync turned off after adding) silently goes empty. The source detail or Health could say "This calendar is no longer synced". Needs `syncEvents` on the sync path, which this spec leaves alone.
- Two sources both named "My calendar" are still possible; the add flow could default the source name to include the account kind.
