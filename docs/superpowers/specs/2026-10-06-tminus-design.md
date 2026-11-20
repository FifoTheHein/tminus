# T-Minus: Meeting Alarm — Design Spec

- **Date:** 2026-10-06
- **Status:** Approved, and built through Plan 6 (2026-11-18). Phase 1.5 (Play readiness, Plan 6) is built, and the app is on Google Play internal testing. Later changes that refine this spec: the calendar picker grouping (`2026-11-13-calendar-grouping-design.md`) and the list in the roadmap's "Changes merged after Plan 5".
- **Store name:** T-Minus: Meeting Alarm · **Project/package:** `tminus` · **Application ID:** `io.github.fifothehein.tminus`
- **Platform:** Android (Flutter UI + native Kotlin alarm engine). iOS is backlog.

## 1. Purpose

A focused, reliable, ad-free app that turns calendar events — primarily Microsoft Teams / Outlook meetings — into alarms that cannot be missed and can always be stopped.

Built for personal use first, with architecture and Play policy compliance kept ready for a later public Play Store release.

### Why (competitive gap)

| App | Lesson |
|---|---|
| zzappbros Calendar Alarm Clock (currently used, paid) | Good snooze/customisation, but bloated (weather, stopwatch); reviews report alarms that cannot be stopped from the notification, alarms not always set, ads after paying. |
| Calendar Alarm (iOS) | Focused: several alarms per event, offsets, calendar colour, long-press custom timing. |
| D-Day Alarm (OkSoft) | Rich alarm toolkit, but calendar is secondary. |

T-Minus wins on: **reliability, always-stoppable alarms, clarity about why something will or won't ring, no ads.**

### Goals

1. Every eligible meeting produces its alerts on time, including when the phone is locked, silent, in Doze or has been rebooted.
2. Every ringing alarm can be stopped from the notification, the full-screen UI or the volume keys.
3. The user can always see why an event will or won't ring and what is scheduled.
4. Cancelled or moved meetings update their alarms before they ring whenever a network is available.

### Non-goals (v1)

Alarm clock / wake-up alarms, weather, timers, home-screen widget, iOS, Microsoft Graph API, backend/server, accounts, analytics, ads, monetisation.

## 2. Phasing

| Phase | Scope |
|---|---|
| **1 — v1 (personal)** | ICS feed source + device calendar source, rules/profiles, escalating alerts, native alarm engine, Agenda/Alerts/Sources/Health screens, quiet modes, onboarding. |
| **1.5 — Play readiness** | Privacy policy, store listing, Play declarations (`USE_EXACT_ALARM`, full-screen intent, foreground service type), trademark search for "T-Minus" in software, onboarding polish. |
| **2 — Google Calendar** | Mostly delivered by the device calendar source. Phase 2 only checks multi-account Google setups and any gaps. |
| **Backlog** | Home-screen widget, iOS (AlarmKit), Wear OS, travel-time-aware alerts, Microsoft Graph source, monetisation (never ads). |

## 3. Key decisions

| Decision | Choice | Reason |
|---|---|---|
| UI framework | **Flutter** (Dart) | The user knows Dart and Flutter. React Native was considered: its ical.js library parses ICS better, but language familiarity matters more. We close the ICS gap with our own tested `ics_core` package. |
| Alarm engine | **Native Kotlin** behind a platform channel | The parts that must never fail (scheduling, ringing, reboot re-arm) must not depend on a Dart background isolate starting up. Native code gives full control over escalation and notification actions. |
| Alarm UI | **Native Jetpack Compose activity** | Starting the Flutter engine from cold takes 1–2 s and can fail when memory is low. The ringing screen is the one place that is unacceptable. |
| Calendar sources | **ICS feed + device calendar**, both behind one `CalendarSource` interface | It's not yet known whether the Intune policy allows Outlook to sync to the device calendar. The device source gives instant updates and Google calendars almost for free. |
| Sync runtime | **Kotlin `SyncWorker`** (WorkManager) that boots a headless FlutterEngine running Dart `syncMain()` | One code path for every trigger. No coupling to a plugin's internal workers. |
| State / navigation | `provider` + `go_router` + `get_it` | Matches the user's existing Flutter projects. |
| Persistence | `drift` (SQLite) in Dart; JSON plan file in device-protected storage in Kotlin | Kotlin can re-arm alarms after a reboot, even before the phone is unlocked, without starting Flutter. |
| Secrets | `flutter_secure_storage` for ICS URLs | A published ICS URL acts like a password: anyone holding it can read meeting details. |

## 4. Architecture

```
┌──────────────────────── Flutter (Dart) ────────────────────────┐
│  UI: Onboarding · Agenda · Alerts · Sources · Health · Settings│
│  Sources ──► Occurrences ──► Rules engine ──► Planner ──┐      │
│  (ics_core, device)   (drift cache)  (profiles, quiet)   │      │
└──────────────────────────────────────────────────────────┼──────┘
                       platform channel `alarm_engine`     │ applyPlan / events
┌──────────────────────── Kotlin ──────────────────────────▼──────┐
│ PlanStore (JSON, device-protected) ─ AlarmScheduler (diff)      │
│ AlarmManager: setAlarmClock (alarm) / setExactAndAllowWhileIdle │
│ AlarmReceiver ─► RingingService (FGS) ─► AlarmActivity (Compose)│
│ BootReceiver / TimeChangeReceiver ─► re-arm from PlanStore      │
│ SyncWorker (WorkManager) ─► headless FlutterEngine syncMain()   │
│ DeviceCalendarReader (CalendarContract.Instances)               │
└─────────────────────────────────────────────────────────────────┘
```

### Proposed repository layout

```
tminus/
  packages/ics_core/            # pure Dart: parse, TZ map, recurrence expansion
  lib/
    app/                        # bootstrap, DI (get_it), router (go_router), theme
    core/
      sources/                  # CalendarSource, IcsFeedSource, DeviceCalendarSource
      storage/                  # drift database, DAOs
      rules/                    # profile resolution, quiet modes
      planner/                  # occurrences × profiles → PlannedAlert list
      engine/                   # Dart side of the alarm_engine channel
      sync/                     # syncMain() entrypoint, sync orchestration
    features/
      onboarding/ agenda/ alerts/ sources/ health/ settings/ quiet/
  android/app/src/main/kotlin/.../
    engine/  AlarmEngineChannel, PlanStore, AlarmScheduler, AlarmReceiver,
             RingingService, AlarmActivity, NotificationFactory, BootReceiver,
             TimeChangeReceiver, PreSyncReceiver, QuietTileService
    sync/    SyncWorker, HeadlessFlutterRunner
    calendar/DeviceCalendarReader
```

## 5. Data model & sources

### `CalendarSource`

```dart
abstract interface class CalendarSource {
  String get id;
  Future<SourceResult> fetch(DateTimeRange window); // occurrences or typed error
}
```

The window is **now − 1 h to now + 7 days**.

**`IcsFeedSource`**
- Stores a URL (in secure storage), a name and a colour.
- Uses conditional GET (ETag / If-Modified-Since) when the server supports it, with a 20 s timeout.
- Only the `.ics` link is used. The `.html` link is ignored.

**`DeviceCalendarSource`**
- Stores an Android calendar ID.
- Reads `CalendarContract.Instances` natively through the channel. Android has already expanded recurrence there.
- Provides `AVAILABILITY` (busy/free/tentative) and `SELF_ATTENDEE_STATUS` (declined).
- Finds the join link in the event's description and location only. It reads no conference property, so a Meet link is found only when it is written in one of those two. An event made in Google Calendar with Meet added may not carry the link on the phone (not checked).
- Asks for `READ_CALENDAR` only when the user adds this kind of source.
- The user picks the calendar from a list grouped by account kind and account. Shared, holiday and phone-only calendars are set apart, and calendars that are not synced are greyed out (`2026-11-13-calendar-grouping-design.md`).

### `ics_core` (pure Dart package, no Flutter dependency)

- Parses VCALENDAR / VEVENT / VTIMEZONE and unfolds folded lines.
- Maps Windows TZIDs to IANA zones using the bundled CLDR `windowsZones` table. Falls back to the feed's VTIMEZONE definition, then to the device zone (and flags the event with a warning).
- Expands RRULE with the `rrule` package. Applies EXDATE, then RECURRENCE-ID overrides.
- Drops `STATUS:CANCELLED` events and titles prefixed `Canceled:` / `Cancelled:`.
- Reads `X-MICROSOFT-CDO-BUSYSTATUS` → `free | tentative | busy | oof`.
- Extracts one join link per meeting, a Microsoft Teams, Google Meet, Zoom or Webex link (`extractJoinUrl`). `meetingServiceOf` names the service from the link's host and path.
  - It looks in Google's `X-GOOGLE-CONFERENCE` property first (ICS feeds only), then DESCRIPTION, then LOCATION. Inside one text the earliest link wins, whatever its service.
  - It recognises these forms, `https` only: Teams `teams.microsoft.com/l/meetup-join/...` and `teams.microsoft.com/meet/...`, and `/meet/<digits>` on `teams.cloud.microsoft` and `teams.live.com`; Google Meet `meet.google.com/xxx-xxxx-xxx`; Zoom `/j/<digits>`, `/my/<name>` and `/w/<digits>` on `zoom.us`, `zoom.com` and their subdomains; Webex `j.php?MTID=<id>`, `/meet/<id>` and `/join/<id>` on subdomains of `webex.com`. Any other page on those hosts, such as `zoom.us/download`, is not a join link.
  - A link inside an Outlook Safe Links or Google redirect wrapper (`https://www.google.com/url?q=...`) is unwrapped and decoded.
- Parses each event separately: one malformed VEVENT is skipped and logged, and the rest of the feed still parses.

### `EventOccurrence`

| Field | Notes |
|---|---|
| `key` | `sourceId|uid|originalStartUtc`. Stays the same when a meeting is moved. A meeting found in several sources is merged under one meeting key (§13). |
| `seriesUid` | Null for one-off events. |
| `title`, `location`, `organizer`, `joinUrl` | |
| `startUtc`, `endUtc`, `allDay` | All times stored in UTC. |
| `busyStatus` | `free / tentative / busy / oof / unknown`. |
| `declined` | Device source only. ICS feeds do not carry your response. |
| `calendarColor` | |
| `warnings` | e.g. `tzFallback`. |

### Stored in drift

- `sources`
- `occurrences` (cache)
- `overrides` (scope: `occurrence` by key, or `series` by `seriesUid`)
- `profiles`
- `rules`
- `quiet_state`
- `alert_history` (fired / snoozed / dismissed / joined / missed)
- `sync_log`

Since Plan 6, the cache tables (`occurrences`, `alert_history` and `sync_log`, plus a small `cache_values` table) are in a second drift database, `tminus_cache.sqlite`. The other tables stay in `tminus.sqlite` (§10).

## 6. Rules & alert profiles

### Alert profile

- A name plus a list of alerts. Each alert has:
  - an offset in minutes before start (≥ 0)
  - a strength:
    - `headsUp`: a high-priority notification with sound. It respects silent mode.
    - `alarm`: full screen, uses the alarm audio stream, and rings until acted on or until it times out.
- Profile-wide sound settings: tone (system alarm tone or custom file), vibration, gradual volume, ring timeout (default 2 min).
- A `ringsInQuietMode` flag.

### Built-in profiles

| Profile | Alerts | `ringsInQuietMode` |
|---|---|---|
| Meeting (global default) | headsUp −10, alarm −1 | no |
| Quick | alarm −1 | no |
| Important | headsUp −30, headsUp −10, alarm −2 | **yes** |
| Silent | none (event still listed) | n/a |

### Resolution order

The first match decides the profile:

1. Occurrence override
2. Series override
3. Skip filters: all-day, busyStatus free/tentative, cancelled, declined → Silent. Each filter can be switched on or off.
4. Keyword rules, in user-defined order. Each rule has:
   - a field: title / location / organizer / description / hasJoinLink
   - a match type: contains or regex, case-insensitive
   - a target profile
5. The source's default profile
6. The global default (Meeting)

### Quiet modes

Applied after the profile is resolved:

| Mode | Lets through |
|---|---|
| Mute today (until 07:00 the next day), Pause until… (presets plus a time picker) | Profiles with `ringsInQuietMode`, and events turned on with an occurrence override |
| Vacation (date range) | Only events turned on with an occurrence override; **Important is silenced too** |

Quiet modes can be set from the Agenda header and from the "Mute today" quick-settings tile.

### Explainability

Every planned occurrence records the step that decided it, e.g. `Quick · rule: "standup"`. The Agenda and the Event detail screen show this.

### Alarm behaviour

- **Dismiss vs Dismiss all:**
  - **Dismiss** (or **Stop** on the notification) ends only the current alert. Later alerts for the same occurrence still fire. For example, dismissing the −10 heads-up still leaves the −1 alarm.
  - **Dismiss all** and **Join** cancel every remaining alert for that occurrence.
  - The acknowledgement is stored as (key, startUtc).
  - If the start time changes, the occurrence's alerts are re-armed.
- **Smart snooze:** the options are +1 min, +5 min, "1 min before start" and "at start".
  - Options already in the past are hidden.
  - A snoozed alert keeps its strength.
- **Coalescing:** alerts firing within the same minute merge into one notification or screen that lists every event.
  - Each event has its own Join / Dismiss.
  - The screen adds **Snooze all** and **Dismiss all**. Dismiss all acts as Dismiss all for every listed occurrence.
  - The coalesced notification shows "N meetings starting", with actions Stop · Snooze all · Dismiss all.
- **Join:** opens `joinUrl` (a Teams, Google Meet, Zoom or Webex link) with Android's `ACTION_VIEW`: the service's own app when it is installed, otherwise the browser. It counts as dismissing the occurrence.

## 7. Alarm engine (Kotlin)

### Channel `alarm_engine`

| Direction | Calls / events |
|---|---|
| Dart → Kotlin | `applyPlan(List<PlannedAlert>)` · `getHealth()` · `testAlarm(strength)` · `openPermissionSettings(kind)` · `queryDeviceCalendars()` · `queryInstances(calendarIds, window)` |
| Kotlin → Dart (event stream) | `fired`, `snoozed`, `dismissed`, `dismissedAll`, `joined`, `missed` |

When Flutter isn't running, Kotlin writes these events to a native queue file. Dart drains the queue into `alert_history` on its next start.

### `PlannedAlert`

- `id`: a stable hash of (occurrenceKey, offset)
- `occurrenceKey`
- `fireAtUtc`
- `strength`
- sound settings
- a snapshot of the event (title, start, end, location, joinUrl, colour)
- `coalesceGroup`

The snapshot lets an alarm ring and show its screen without Flutter.

### Scheduling

- `PlanStore` keeps the current plan as JSON in **device-protected storage**.
- `applyPlan` writes the new plan atomically (temp file + rename) and diffs it by `id` + `fireAtUtc`. Only changed alerts are cancelled or added.
- `alarm` strength uses `AlarmManager.setAlarmClock()`. Its show-intent opens the Agenda.
- `headsUp` strength uses `setExactAndAllowWhileIdle()`.
- **Pre-alarm sync:** for each occurrence, an exact alarm fires 12 min before that occurrence's earliest alert. `PreSyncReceiver` then enqueues an expedited `SyncWorker`.
  - If the sync fails, the alert still fires with the data it already has.

### Firing

1. `AlarmReceiver` starts `RingingService`, a foreground service of type `systemExempted` (`FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED`, `0x400`).
   - Android allows this type for apps that hold `USE_EXACT_ALARM` or `SCHEDULE_EXACT_ALARM`, and Play's foreground-service policy exempts it from the use-case criteria (Plan 6 decision 2).
   - The type exists from Android 14 (API 34), and the service passes it only there. Below API 34 it starts the service with no type argument, so Android uses the type in the manifest (API 29 to 33) or has no service types (API 26 to 28) (Plan 6 decision 8).
   - If Play review rejects `systemExempted`, the fallback is `mediaPlayback`: the manifest's type and type permission, and the type that `RingingService` passes, change back together (Plan 6 decision 2). `docs/play/declarations.md` has the steps and the Play Console text.
2. The service:
   - plays audio with `AudioAttributes.USAGE_ALARM`, ramping volume up gradually
   - vibrates and holds a partial wake lock
   - stops on its own at the timeout and logs `missed` (user did not respond), plus a "Missed" notification
3. The service posts a notification with `setFullScreenIntent` pointing at `AlarmActivity` (Compose, `showWhenLocked`, `turnScreenOn`).
4. Android shows at most **3 actions** on a notification, so:
   - The ringing notification shows **Stop · Snooze · Join** when the event has a link, otherwise **Stop · Snooze · Dismiss all**.
   - The full-screen `AlarmActivity` always offers every action.
   - Volume keys in `AlarmActivity` act like Stop.
   - The 4-action ringing notification in mockup `6a` is superseded by this rule.
5. `headsUp` alerts post on a high-importance channel with Join (if link) · Snooze · Dismiss all. There's no full-screen screen and no foreground service.

### Re-arm triggers

These triggers reload `PlanStore` and re-schedule everything:
- `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`
- `TIME_SET`, `TIMEZONE_CHANGED`
- `MY_PACKAGE_REPLACED`
- `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`

### Sync triggers (all run `SyncWorker` → headless `syncMain()`)

- Periodic, every 15 min, requiring a network connection
- Content-URI trigger on `CalendarContract.Events.CONTENT_URI`, re-enqueued after each run (device sources only)
- Pre-alarm sync (see above)
- App foreground, and pull-to-refresh (run directly in the UI isolate)

`syncMain()` does: fetch all sources → update the cache → resolve rules → build the plan → `applyPlan` → log the result.

### Permissions (manifest)

| Permission | Notes |
|---|---|
| `INTERNET` | |
| `USE_EXACT_ALARM` | Core alarm/calendar function. Auto-granted and can't be revoked. Exists only from Android 13 (API 33). |
| `SCHEDULE_EXACT_ALARM` (`android:maxSdkVersion="32"`) | Exact alarms on Android 12 and below, where `USE_EXACT_ALARM` doesn't exist; granted by default there. If exact scheduling is ever refused, fall back to an inexact alarm and show it in Health. |
| `USE_FULL_SCREEN_INTENT` | Android 14+ grants it to alarm apps. Checked with `canUseFullScreenIntent()`. |
| `POST_NOTIFICATIONS` | |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SYSTEM_EXEMPTED` | For `RingingService`, whose type is `systemExempted` (see Firing). Normal permissions, granted at install. |
| `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `VIBRATE` | |
| `READ_CALENDAR` | Requested at runtime, only for device sources. |

For battery optimisation, the app opens `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`. It does **not** declare `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, which Play restricts.

- **minSdk:** 26
- **targetSdk:** latest stable

## 8. Screens

Material 3, dark theme first, with a light theme too; calendar colours used as accents. Bottom navigation: **Agenda · Alerts · Sources · Health**; Settings sits in the overflow menu. Full content is in `docs/design-brief.md`.

**Approved mockups:** `docs/design/` (26 screens plus `design-system.png`), and the [Claude Design project](https://claude.ai/design/p/b3ee1986-af3e-4399-9aeb-efd063edfd49). Where a mockup and this spec disagree on behaviour, the spec wins; where they disagree on visuals, the mockup wins.

**Theme implementation:**
- Material 3 `ColorScheme` and `TextTheme`, plus two `ThemeExtension`s:
  - `TMinusColors`: calendar, status and alert-chip tokens
  - `TMinusType`: countdown, time and chip numerals
- Spacing and corner radii come from the `TMinusSpacing` / `TMinusRadii` constants, using the token names on the design-system sheet.
- The native Compose `AlarmActivity` uses the same hex values.
- **Fonts:** IBM Plex Sans (UI) and IBM Plex Mono (times, countdowns, chips).
  - They're **bundled as app assets**, not fetched at runtime with `google_fonts`. That keeps the promise "no servers, your calendar never leaves your phone" and works offline at first launch.
- **Icon and logo:**
  - The launcher icon is an adaptive icon: a slate disc, a 270° countdown arc and a T- mark, with a monochrome layer.
  - The app draws the same mark with `TMinusMark`.
- **Edge to edge:** targetSdk 36 draws behind the system bars. Every screen keeps its last content above the navigation bar, including screens outside the tab bar such as Settings, Developer tools and Onboarding.

1. Onboarding: welcome → add source → permissions → test alarm → done
2. Agenda (home)
3. Event detail sheet
4. Alerts tab: Profiles and Rules
5. Sources tab
6. Health tab
7. Quiet-mode sheet and quick-settings tile
8. Settings
9. Native alarm screen (Compose)
10. Notifications: heads-up, ringing, missed, feed-stale, feed-broken

## 9. Error handling

The rule: never lose an alarm because of bad data, and never fail silently.

| Failure | Behaviour |
|---|---|
| Network error, 5xx or timeout | Keep the last good data; WorkManager retries with backoff; the source turns amber. |
| 401 / 403 / 404 | Link reset or calendar unpublished. The source turns red and one notification is sent; existing alarms are kept. |
| Whole feed won't parse | Keep the previous occurrences; the source turns red. |
| One event won't parse | Skip and log that event; the rest of the feed is applied. |
| Feed returns 0 events where it previously had some | Remove alarms only after **two consecutive** empty results. |
| Unknown TZID | Use the feed's VTIMEZONE, then the device zone; the event shows ⚠. |
| Notifications or full-screen permission lost | Health turns red and the Agenda shows a banner. |
| Alert time passed by > 2 min without a `fired` record | Logged as `missed (system)` and shown in Health. This reveals phones that kill background apps. |
| `applyPlan` channel failure | Kotlin keeps the old plan; Dart retries on the next sync. |
| Custom tone file missing | Fall back to the default alarm tone. |
| User force-stops the app | Android cancels its alarms. Health explains this, and the app re-arms on the next start. |
| Feed stale > 60 min with an alert due within 2 h | A "Feed stale" notification is shown. |

## 10. Security & privacy

- No backend, analytics, ads or third-party SDKs that collect data. All data stays on the device, apart from what Android's own backup copies (below).
- ICS URLs are kept in secure storage. They are shown masked, redacted from logs, and excluded from JSON export.
- Settings export/import is JSON with sources minus their URLs.
- Release builds turn off verbose logging.
- **Two databases, and only one is backed up (Plan 6 decisions 4 and 10).**
  - `tminus.sqlite` holds sources (names, colours and kinds, no links), profiles, rules, overrides, quiet state, settings and meeting links. Android backs it up. Overrides and meeting links hold occurrence keys and iCal UIDs, which are opaque ids, not event content.
  - `tminus_cache.sqlite` is a second drift database for the cache: `occurrences`, `alert_history` and `sync_log`, plus `cache_values`, a small table for values that carry meeting text (such as the titles of the alerts the last plan expects to ring). It is never backed up, so no meeting title, location, join link or alert history leaves the phone in an Android backup.
  - It is a second database, not an `ATTACH`, because SQLite commits across attached files are not atomic in WAL mode. No query joins a cache table with another table.
  - A phone that cached meetings before Plan 6 keeps them. The first open copies the old rows into the cache database before anything can read the cache, and drops them from `tminus.sqlite` only after the copy committed (Plan 6 decision 11). A sync that planned from an empty cache would send an empty plan, and an empty plan cancels every alarm.
  - `tminus.sqlite` runs with `secure_delete` on, and an upgraded phone compacts it once after the move. So no old meeting text stays in the free pages or the write-ahead log of the file that is backed up.
- **The backup rules list only the database.** `backup_rules.xml` (Android 11 and below) and `data_extraction_rules.xml` (Android 12 and later) include `tminus.sqlite` and its `-wal` file, and nothing else. Every other file stays out by default: the secure-storage preferences that hold the ICS links, the feed bodies, the plan and its acknowledgements, the event queue, the sync preferences and the cache database.
  - The cloud backup includes the database only when it can be encrypted end to end. Android 12 and later check this with `disableIfNoEncryptionCapabilities`. On Android 9 to 11 the includes carry `requireFlags="clientSideEncryption"` (Plan 6 decision 20).
  - Android 8 ignores that flag, so a backup there may not be encrypted. It holds no meetings and no links, only settings, rules and source names.
- The public privacy policy is `docs/privacy.md`, published at https://fifothehein.github.io/tminus/privacy/.

## 11. Testing

- **`ics_core` unit tests** with fixture feeds: a scrubbed copy of the user's real published feed, plus handcrafted cases:
  - a weekly RRULE with EXDATE
  - a modified instance and a cancelled instance
  - Windows TZIDs
  - an organiser in a zone with daylight saving time
  - all-day and multi-day events
  - `Canceled:` titles
  - join link extraction (Teams, Google Meet, Zoom and Webex)
  - folded lines
- **Rules engine:** table-driven tests covering the full resolution order, quiet modes against `ringsInQuietMode`, Vacation silencing Important, and the explanation text.
- **Planner:**
  - the diff keeps stable IDs
  - Dismiss-all
  - a moved meeting re-arms
  - coalescing
  - snooze options in the past are hidden
  - the empty-feed guard
- **Multi-source meetings (§13):** pure merge tests (matching, ranking, sticky keys, splits) and `SyncService` tests with an ICS feed and a phone calendar holding the same meetings.
- **Kotlin:** Robolectric tests for `PlanStore` (atomic write, diff) and `AlarmScheduler`; instrumented tests for the boot and time-change receivers.
- **Manual device checklist:**
  - locked, silent, DND
  - forced Doze (`adb shell dumpsys deviceidle force-idle`)
  - reboot (before and after unlock)
  - time zone change
  - app swiped away
  - a Samsung device
- **Debug-only "fast alarms" mode:** creates fake events 1–2 min ahead to exercise the full flow.
- **Dogfooding:** 2 weeks alongside the current paid app, comparing results with Health's history.

## 12. To verify early in implementation

1. **Intune and the device calendar:**
   - Does the Outlook Android app's "Sync calendars" work on the user's phone?
   - This decides the primary source but changes no code.
2. **Published-feed latency:** measure how long Outlook takes to update the published ICS feed after a meeting change. This sets expectations for the pre-alarm sync.
3. **Teams link in the feed:** confirm the "Can view all details" feed includes the Teams join URL in DESCRIPTION. **Done in Plan 1** (`packages/ics_core/test/real_feed_test.dart`): the published Outlook feed carries Teams links in DESCRIPTION. **Widened in Plan 7 (2026-11-19)** to Google Meet, Zoom and Webex, checked against real feeds:
   - One Outlook feed: a Google invite accepted into Outlook has its Meet link as the whole LOCATION, and in DESCRIPTION mostly inside Outlook Safe Links wrappers.
   - Two Google Calendar feeds: nearly every Meet meeting has its link, as the plain link, in `X-GOOGLE-CONFERENCE` and in DESCRIPTION. Zoom links are in DESCRIPTION (sometimes also the whole LOCATION), many of them inside Google redirects (`https://www.google.com/url?q=...`). Only a handful of real Webex join links turned up, so the Webex forms rest mostly on published descriptions of Webex links.
   - Not recoverable: when a mail-security service rewrites a Teams link, the new link holds only the host name (`...?domain=teams.microsoft.com`), so no link can be found. Those meetings get no Join button, as before.
   - Phone calendars were not checked. Whether Android's calendar store holds the Meet link that Google Calendar adds with its video conferencing button is not known (§5).
4. **Foreground service type:** confirm `mediaPlayback` is acceptable for alarm ringing under the current Play policy; otherwise use `specialUse`. *Superseded (2026-11-02):* Plan 6 moves `RingingService` to `systemExempted`, with `mediaPlayback` as the fallback (roadmap, Plan 6 decision 2). **Done (2026-11-18):** `RingingService` is a `systemExempted` service, and it was checked on the release build in three ways.
   - Release smoke test (Plan 6, Task 4): on an API 36 emulator the release build rang the test alarm full screen with the service in the foreground as `systemExempted` (`0x400`). The merged release manifest has one typed service, `RingingService`.
   - Emulators on API 26, 30, 33, 35 and 36 (Task 11), with the 1.0.1 release APK: the alarm rang on every level, and stopped from the screen, from the notification and from a volume key. API 35 and 36 show `0x400`. On API 26, 30 and 33 the dump shows the service in the foreground. On API 35's first leg, Android showed "T-Minus isn't responding" and Dismiss on the alarm screen did not stop one alarm (the notification's Stop did). The traces show the alarm screen stuck in the emulator's software renderer, and the main thread blocked in an AlarmManager call, which is follow-up issue #26. On the third try Dismiss worked with no ANR.
   - The user's phone, a Samsung S24 with the build from Play internal testing (Task 12): the user reports that every check passed.
   - Play Console accepted the bundle and asked for no foreground service declaration for `systemExempted`. Play's review result is not in yet. If it rejects the type, the fallback in §7 applies.

## 13. Meetings in more than one source

*Added 2026-10-09, agreed with the user in brainstorming. Plan: `docs/superpowers/plans/2026-10-09-plan-4b-multi-source-meetings.md`.*

The same meeting can reach T-Minus through two sources. For example, the Outlook calendar might be added once as a published ICS link and once as the Exchange-synced phone calendar, or the same feed might be added twice. Each source is fetched, cached and checked on its own (§5, §9), so without merging every alert rings twice. **A meeting present in several sources is merged into one meeting with one set of alerts.**

### Terms

- **Copy:** one cached `EventOccurrence` from one source. Its key stays `sourceId|uid|originalStartUtc` (§5), and the cache, the empty-feed guard, the sync log and Feed stale/broken stay per source and per copy, exactly as before.
- **Meeting:** one or more copies of the same meeting from different sources, merged into one occurrence. Rules, the plan, acknowledgements, overrides, alert history and the Agenda all work on meetings.
- **Meeting key:** the key a meeting uses everywhere outside the cache. A meeting with one copy and no stored link uses that copy's key, so nothing changes for anyone who has each meeting in only one source.

### Recognising the same meeting

1. **Different sources only.** Two copies from the same source are never merged, even when identical. If a source has two copies with the same fingerprint or strong key, that value is ambiguous and is not used to merge either of them.
2. **Strong key:** (iCal UID, original start). ICS copies carry the iCal UID. Phone copies carry it only if the provider exposes it in a column the app reads (Plan 4b Task 1 checks this on the user's phone; Google's adapter is reported to leave `UID_2445` empty).
3. **Fingerprint:** (normalised title, original start, all-day).
   - The title is normalised by trimming it, dropping a leading `Canceled:` / `Cancelled:`, collapsing whitespace and lower-casing it.
   - Untitled copies (empty or `(No title)`) have no fingerprint.
   - The **original** start is used, not the current start. Both sources already key a moved instance of a series on it (ICS `RECURRENCE-ID`, phone `ORIGINAL_INSTANCE_TIME`, Plan 4 decision 14). So a moved instance still matches while the published feed lags behind the phone.
4. **Remembered links.** Once copies are merged, a link from each copy's key to the meeting key is stored (`meeting_links`). Linked copies stay together on later syncs even if their times now differ.
   - A one-off copy whose key changed because it moved (its original start is its start) finds its meeting again by (source, uid). Phone `EVENT_ID` and ICS `UID` survive an edit. So a one-off meeting moved on the phone stays one meeting while the feed still shows the old time.
   - Links are only stored for meetings that have, or had, two or more copies.
   - Links are pruned a day after the copy ends. They do not reference the `sources` table, so a deleted source's links outlive it on purpose (see Splitting below).
5. A copy that could join more than one meeting joins none and stays on its own.

**Known risk:** a false fingerprint match is remembered. That means two genuinely different meetings with the same title and original start in two different calendars. If one of them later moves, only the winning copy's time rings. Until it moves, the false merge costs nothing, because both would ring in the same minute anyway (§6 coalescing). The setting below is the escape hatch.

### Which copy wins

Copies are ranked:

1. copies from sources whose last fetch succeeded, before copies from failing sources (`lastError` set, amber or red), so a phone calendar whose access was revoked cannot hold a frozen time over a fresh feed;
2. phone calendar, then ICS feed, then debug (phone calendars are fresher: published feeds lag, §12 check 2);
3. the copy whose key is the meeting key;
4. source id.

| Field | Rule |
|---|---|
| start, end, all-day, warnings, title, `seriesUid`, colour | From the top-ranked copy (the **time source**). |
| Join link, location, organiser, description | First non-null in rank order (Outlook's phone sync may leave out the body; the feed has the Teams, Google Meet, Zoom or Webex link). |
| Busy status | First that is not `unknown`. |
| Declined, cancelled | True if any copy says so (only phone copies know). |
| Source default profile (§6 step 5) | First source in rank order that has one. |
| Occurrence and series overrides (§6 steps 1–2) | The override on the meeting key first, then on each copy's key, then on each copy's `seriesUid`, in rank order. |

**Removal:** a meeting lasts while any enabled source lists it (union). If the phone copy disappears but the feed still lists the meeting, the alerts stay until the feed drops it too. That is no worse than today, and it is safe when Intune or an account re-sync empties the phone calendar.

### Keys, acknowledgements, overrides and history

- **A new meeting** (copies merged for the first time) takes the key of its top-ranked copy. Acknowledgements and overrides recorded under any copy's own key still apply (they are looked up under every copy key). So a Dismiss all or an override set on the feed's copy before the phone calendar was added keeps working. The one thing lost at that moment is a snooze running on the other copy's key: Kotlin drops it, because that key leaves the plan (roadmap §3 engine rules).
- **The meeting key is sticky.** It stays the same on later syncs whatever the ranking does, and after a **split**. A split is a source being removed or disabled, or its copy disappearing (deleted, or the empty-feed guard clearing it); in each case the remaining copies keep the meeting key through their stored links. So Kotlin's acknowledgements (key + start), single dismissals, snoozes and missed-(system) expectations continue unchanged. A broken source keeps its cached copies (§9), so a broken source does not split anything; it only loses rank.
- **Dismiss all / Join** is keyed (meeting key, start) as before (§6). A merged meeting whose time source changes to a different start re-arms, like any moved meeting.
- **Alert history** rows carry the meeting key. Rows from before a merge keep their copy keys and still count through the alias lookup above.
- **Setting `merge.enabled`** (default on; the Settings switch is Plan 5's) turns merging off. Copies are then planned under their own keys, as before this section. A meeting that was dismissed while merged can then ring once. Stored links are kept, so turning merging back on restores the same meeting keys.

### Where merging happens

`SyncService.run` (Plan 4): drain events → fetch every enabled source → per source, apply the empty-feed guard and store the result (unchanged) → read the cache for enabled sources → **merge** → rules → `buildPlan` → missed (system) → `applyPlan` → configure. Merging reads the cache, never a raw fetch result, so a source's empty or failed fetch affects only that source's copies.

- **Empty-feed guard:** still per source. When a source's copies are cleared, its meetings continue from their other copies under the same key.
- **Feed stale (§9):** an alert counts toward an ICS source's "alert due within 2 h" only if that source is the meeting's time source. A stale feed whose meetings are timed by a healthy phone calendar does not warn.
- **Feed broken:** unchanged. It is per source, and the failing source's copies lose rank.
- **Missed (system):** unchanged. Expectations carry the meeting key, which survives a split.
- **Agenda (Plan 5):** runs the same pure merge on the cache with the stored links (read-only), so it shows each meeting once, exactly as planned, and can list the sources it came from.
