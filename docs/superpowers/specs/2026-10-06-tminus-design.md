# T-Minus: Meeting Alarm — Design Spec

- **Date:** 2026-10-06
- **Status:** Approved in brainstorming, pending written-spec review
- **Store name:** T-Minus: Meeting Alarm · **Project/package:** `tminus`
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
- Asks for `READ_CALENDAR` only when the user adds this kind of source.

### `ics_core` (pure Dart package, no Flutter dependency)

- Parses VCALENDAR / VEVENT / VTIMEZONE and unfolds folded lines.
- Maps Windows TZIDs to IANA zones using the bundled CLDR `windowsZones` table. Falls back to the feed's VTIMEZONE definition, then to the device zone (and flags the event with a warning).
- Expands RRULE with the `rrule` package. Applies EXDATE, then RECURRENCE-ID overrides.
- Drops `STATUS:CANCELLED` events and titles prefixed `Canceled:` / `Cancelled:`.
- Reads `X-MICROSOFT-CDO-BUSYSTATUS` → `free | tentative | busy | oof`.
- Extracts the Teams join URL from DESCRIPTION/LOCATION by matching `https://teams.microsoft.com/l/meetup-join/...`.
- Parses each event separately: one malformed VEVENT is skipped and logged, and the rest of the feed still parses.

### `EventOccurrence`

| Field | Notes |
|---|---|
| `key` | `sourceId|uid|originalStartUtc`. Stays the same when a meeting is moved. |
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
| Important | headsUp −15, alarm −5, alarm 0 | **yes** |
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
- **Join:** opens `joinUrl` (Teams app, otherwise the browser) and counts as dismissing the occurrence.

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

1. `AlarmReceiver` starts `RingingService`, a foreground service of type `mediaPlayback`.
   - We must check this type against the Play foreground-service policy during implementation. If it's rejected, use `specialUse` with a declaration.
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
| `USE_EXACT_ALARM` | Core alarm/calendar function. Auto-granted and can't be revoked. |
| `USE_FULL_SCREEN_INTENT` | Android 14+ grants it to alarm apps. Checked with `canUseFullScreenIntent()`. |
| `POST_NOTIFICATIONS` | |
| `FOREGROUND_SERVICE` + the type permission | |
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

- No backend, analytics, ads or third-party SDKs that collect data. All data stays on the device.
- ICS URLs are kept in secure storage. They are shown masked, redacted from logs, and excluded from JSON export.
- Settings export/import is JSON with sources minus their URLs.
- Release builds turn off verbose logging.

## 11. Testing

- **`ics_core` unit tests** with fixture feeds: a scrubbed copy of the user's real published feed, plus handcrafted cases:
  - a weekly RRULE with EXDATE
  - a modified instance and a cancelled instance
  - Windows TZIDs
  - an organiser in a zone with daylight saving time
  - all-day and multi-day events
  - `Canceled:` titles
  - Teams link extraction
  - folded lines
- **Rules engine:** table-driven tests covering the full resolution order, quiet modes against `ringsInQuietMode`, Vacation silencing Important, and the explanation text.
- **Planner:**
  - the diff keeps stable IDs
  - Dismiss-all
  - a moved meeting re-arms
  - coalescing
  - snooze options in the past are hidden
  - the empty-feed guard
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
3. **Teams link in the feed:** confirm the "Can view all details" feed includes the Teams join URL in DESCRIPTION.
4. **Foreground service type:** confirm `mediaPlayback` is acceptable for alarm ringing under the current Play policy; otherwise use `specialUse`.
