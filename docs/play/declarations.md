# Play Console declarations

The answer to enter for each item Play Console asks for under **App content**, and for its permission and foreground service declarations, with the reason for each. The store listing is in [listing.md](listing.md).

Every factual sentence was checked against the code when this file was written (Plan 6, Task 8). Task 10's reviewer reads it against the code again before anything is entered, and records here any change that Play Console's own wording forces. Task 10 records the date each answer was filed in the plan's run log.

Where Play's policy is quoted, it is quoted as read on 2026-11-02 (roadmap, Plan 6 decision 4). Play changes its forms. If a form asks something this file does not answer, the reviewer decides, enters the answer and writes it down here.

## Privacy policy

Enter: `https://fifothehein.github.io/tminus/privacy/`

The page is `docs/privacy.md` (Jekyll permalink `/privacy/`), published from `main` by GitHub Pages. `test/app/links_test.dart` pins the URL in the app to the page's permalink. The page must be live before the form is saved (Plan 6 Task 5 Step 8). The same URL is used in the Data safety form.

## App access

**Answer:** All or some functionality is restricted.

**Why:** Nothing is behind a sign-in, because the app has no accounts. But the app shows nothing until a calendar is added, and a reviewer has no calendar link of ours, so the form needs instructions. They point at a public demo calendar, `docs/play/demo.ics`, served at `https://fifothehein.github.io/tminus/play/demo.ics`. It holds twelve 30-minute meetings that repeat daily, one at every even hour UTC, so a reviewer in any time zone sees a meeting within two hours. It has no Teams links.

**Instruction name:** Demo calendar. **Username and password:** leave empty, there is no sign-in.

**Instructions** (the text to enter). It has 886 characters.

```text
No sign-in is needed. The app reads a calendar link, so please use this public demo calendar.
1. Tap Get started.
2. Paste https://fifothehein.github.io/tminus/play/demo.ics into the ICS link field, tap Check, then Add calendar, then Continue.
3. On the permissions step, allow Notifications (and Full-screen alarms, if listed), then tap Continue.
4. Tap Ring a test alarm. After 5 seconds an alarm rings full screen. Tap Dismiss, then It rang, then Go to Agenda.
A demo meeting starts every 2 hours (at even hours UTC). With the default profile each one gives a heads-up 10 minutes before it and an alarm 1 minute before it. Health > Upcoming alarms lists the next five alerts. The 12:00 UTC meeting is marked free, so it is skipped on purpose.
To stop the demo alarms, tap the moon button at the top of the Agenda and choose Mute today, or open the calendar in Sources and tap Remove.
```

**A shorter form**, if the field limits the text (the reviewer checks the limit when entering it). It has 469 characters.

```text
No sign-in. Tap Get started. Paste https://fifothehein.github.io/tminus/play/demo.ics into the ICS link field, tap Check, Add calendar, Continue. Allow Notifications, tap Continue, then Ring a test alarm: an alarm rings in 5 seconds, tap Dismiss. A demo meeting starts every 2 hours (even hours UTC): heads-up 10 min before, alarm 1 min before. Health > Upcoming alarms lists the next alerts. Stop: moon button in Agenda > Mute today, or Remove the calendar in Sources.
```

How this text differs from the plan's draft, and why:

- The plan said "choose Add a published link". The app has no such label. The add-calendar step shows two cards, "Paste a calendar link" (already selected) and "Use a calendar on this phone", and the link field is labelled "ICS link".
- The plan stopped after Add calendar. The step needs Continue, the permissions step and the test alarm, which the text now gives.
- The plan said "so the phone rings every two hours". That is not true of the demo feed. The meeting at 12:00 UTC ("Focus time") is marked free, and the default settings skip free meetings, so there is no alarm at that hour. The text now says so.
- The plan said "Mute today (Agenda header or the quick-settings tile)". The button at the top of the Agenda is the moon icon, named Quiet modes, and it opens a sheet that holds Mute today. The quick-settings tile is also called Mute today, but a reviewer would have to add it to their quick settings first, so the text leaves it out.
- The heads-up 10 minutes and alarm 1 minute are true of the default profile, Meeting. The plan's "full-screen alarm" is now "an alarm": a scheduled alarm fills the screen when the phone is locked or T-Minus is open, but Android may show it as a notification while the phone is in use elsewhere. "Lists them" is now "lists the next five alerts", because Health shows only the next five.

## Ads

**Answer:** No, the app does not contain ads.

**Why:** `pubspec.lock` and `android/app/build.gradle.kts` hold no advertising library, and the privacy policy says there are no ads. Task 4 Step 5 checks the merged release manifest for an advertising permission.

## Content rating

**Answer:** Complete the IARC questionnaire. Category: Utility, Productivity, Communication or Other, whichever entry the list gives for utility and productivity apps. Answers:

- Violence, sexual content, bad language, controlled substances and gambling: No to each.
- Users can interact or share content with each other: No. There are no accounts and nothing is shared between users.
- The app shares the user's location with others: No. The app has no location permission.
- The app sells digital goods or has purchases: No. It is free.
- The app contains ads: No.

**Why:** The app turns the user's own calendar entries into alarms and has no content of its own. The rating the questionnaire returns goes in the plan's run log.

## Target audience and content

**Answer:** Target age group 18 and over only. The app is not designed for children and does not appeal to them, so no Families policy applies.

**Why:** T-Minus is a work tool for meetings, and the privacy policy says it is not directed at children.

## Data safety

**Answer:** No data collected and no data shared. Answer No to "Does your app collect or share any of the required user data types?" The form then has no data types to fill in. Account creation: none, because the app has no accounts.

**Why (the plan's reading of Play's rules):** The app sends nothing to the developer and nothing to any third party. It has no server and no analytics, advertising or crash-reporting library. Play counts data that an app transmits off the device. The only thing the app transmits is the download of each calendar link the user added. That goes to the user's own calendar provider, at the user's request, and carries only the standard details of a download (`docs/privacy.md`, "What leaves your phone"). Events read from a phone calendar stay on the phone. The settings backup is made by Android, to the user's own Google account, and holds no calendar link and no meeting. "Is all of the user data collected by your app encrypted in transit?" does not apply, because no data is collected.

**Data deletion:** There is no account, so no deletion request mechanism is needed. Removing a calendar deletes its link and its meetings at once. Uninstalling the app removes everything it stored on the phone. A settings export file the user saved, and the Android backup, stay until the user removes them (`docs/privacy.md`, "Deleting your data").

**Task 10's reviewer checks this answer against Play Console's Data safety help on the day the form is filled in, and records any change here.** The points to look at:

- Whether the download of a calendar link counts as collection or sharing. What the request sends is listed in `docs/privacy.md`.
- Links that start with `http://` are downloaded without encryption, and the app warns the user when one is added. If the download counted as collection, "encrypted in transit" would not be true for them.
- The Android backup of the app's settings to the user's Google account: end to end encrypted from Android 9, no links, no meetings.
- The settings export file the user saves where they choose.
- Google Play's own crash and install statistics. They come from Android and Play, not from the app, and the privacy policy says so.

## Government apps, Financial features, Health, News apps

**Answer:** No to each: the app is not a government app, has no financial features, has no health features and is not a news app.

**Why:** The app's **Health** tab is the alarm checklist (notifications, full-screen alarms, exact alarms, battery settings, alarm volume and calendar sync). It is not a health feature, and the reviewer should not mistake the tab's name for one.

## Advertising ID

**Answer:** The app does not use an advertising ID.

**Why:** The app's manifest does not declare `com.google.android.gms.permission.AD_ID`, and neither `pubspec.lock` nor `android/app/build.gradle.kts` names an advertising or analytics library. Task 4 Step 5 reads the merged release manifest. Any `AD_ID` there fails that task.

## Exact alarms (`USE_EXACT_ALARM`)

**Answer:** Core functionality: alarm clock and calendar event notifications.

**Text** (438 characters):

```text
T-Minus is a meeting alarm app. Its core function is ringing an alarm, and showing a reminder, at an exact minute before each calendar meeting, as set by the user, so the alarm must fire on time, even in Doze. The app uses setAlarmClock for alarms and setExactAndAllowWhileIdle for heads-up reminders. It holds USE_EXACT_ALARM on Android 13 and later, and SCHEDULE_EXACT_ALARM on Android 12 and 12L, where the system grants it by default.
```

**Why:** Play restricts `USE_EXACT_ALARM` to apps whose "core, user-facing functionality genuinely requires precise timing, like dedicated alarm, timer, or calendar applications with event notifications". T-Minus is an alarm app for calendar meetings. If exact scheduling is ever refused, the app falls back to an inexact alarm and Health shows it (the Exact alarms row).

## Full-screen intent (`USE_FULL_SCREEN_INTENT`)

**Answer:** Core functionality: alarm.

**Text** (272 characters):

```text
The app's alarms open full screen, including over the lock screen, at the time the user set before a meeting, like an alarm clock. The user can stop an alarm from the full-screen alarm, from its notification, or with the volume keys while the full-screen alarm is showing.
```

**Why:** On Android 14 and later the permission is granted automatically only to apps whose core function is setting an alarm (or calls), and the app must submit this declaration to be eligible (roadmap, Plan 6 decision 4). The app checks `canUseFullScreenIntent` in onboarding and in Health, and says when it is off.

## Foreground service: `systemExempted`

**Declare** one foreground service type, `systemExempted`, for `RingingService` (manifest `android:foregroundServiceType="systemExempted"`, permission `FOREGROUND_SERVICE_SYSTEM_EXEMPTED`). It is the only service with a type. WorkManager's `SystemForegroundService` is merged without one and `SyncWorker` never calls `setForeground`, so neither needs a declaration (Plan 6 Global Constraints; Task 4 Step 5 checks the merged manifest again).

**Description** (319 characters):

```text
When a meeting alarm fires, a foreground service plays the alarm sound on the alarm audio stream, vibrates, holds a wake lock and shows the ringing notification with its full-screen alarm, until the user stops or snoozes the alarm or the ring timeout (2 minutes by default) ends. It runs only while an alarm is ringing.
```

**Impact if the system defers the task** (57 characters):

```text
The alarm would ring late, after the meeting has started.
```

**Impact if the system interrupts the task** (89 characters):

```text
The alarm would stop ringing before the user noticed it, and they would miss the meeting.
```

Video: (link added after Task 9)

The line above is a placeholder. The user uploads Task 9's recordings to YouTube as unlisted, and puts the link on that line (Task 9 Step 3). Do not enter the foreground service declaration without it.

**Why:** Android allows `systemExempted` for apps that hold `USE_EXACT_ALARM` or `SCHEDULE_EXACT_ALARM`. Play's Device and Network Abuse policy says `systemExempted` and `shortService` are exempt from its use-case criteria (roadmap, Plan 6 decision 4). The service starts only when an alarm fires: one the user set or snoozed, or a test alarm the user asked for. The user can stop it from the notification, from the full-screen alarm and, while that is showing, with the volume keys, and the ring timeout stops it otherwise. On Android 14 and later it starts with the type `systemExempted`. On Android 8 to 13 it starts without a type argument and uses the manifest's (Plan 6 decision 8).

## Calendar permission (`READ_CALENDAR`)

**Answer:** No Play declaration.

**Why:** `READ_CALENDAR` is not a restricted permission, so Play Console has no form for it. The app asks for it at runtime, and only when the user chooses a calendar on the phone. The privacy policy explains it.

## If review rejects `USE_EXACT_ALARM`

Switch to `SCHEDULE_EXACT_ALARM` on every API level. That means removing `android:maxSdkVersion` from it, adding a prompt in onboarding and handling `canScheduleExactAlarms() == false`. Health already has an Exact alarms row for that case: it reports a warning, and its Fix button opens `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`. The new task adds the onboarding prompt and decides whether a missing grant should be a problem instead of a warning. That is a new task, not built in Plan 6.

**It also needs the `mediaPlayback` fallback below, or a ring path that works without the grant.** On Android 14 and later (API 34 and up), `systemExempted` is allowed because the app holds an exact-alarm permission. `USE_EXACT_ALARM` cannot be revoked by the user, so today that prerequisite always holds. `SCHEDULE_EXACT_ALARM` can be revoked, in Android's Alarms and reminders setting. With only that permission, the type's prerequisite becomes a grant the user can take away. When it is gone, Android refuses the foreground start, `RingingService` shows a heads-up notification instead of ringing (`refuseForeground`), and the alarm does not ring. The new task must therefore also do one of two things: take the `mediaPlayback` fallback, or give the service a way to ring that does not depend on the grant.

## If review rejects `USE_FULL_SCREEN_INTENT`

Nothing in the app changes. Without Play's approval, Android 14 and later do not grant the permission by default, and the user has to allow full-screen alarms by hand. Onboarding (the Full-screen alarms row) and Health (the Full-screen alarms row) check `canUseFullScreenIntent` and open the setting. Until it is allowed, an alarm still rings and vibrates, but shows as a notification instead of full screen, and Health says so. Task 12 Step 7 records which case the phone shows.

## If review rejects `systemExempted`

Revert Task 2's commit, `Run the ringing service as systemExempted` (Plan 6 decision 2). The manifest then declares `mediaPlayback` and the permission `FOREGROUND_SERVICE_MEDIA_PLAYBACK` again. Revert the manifest and `foregroundType()` together, which one commit does: if they name different types, Android refuses the start, and `RingingService` falls back to a heads-up instead of ringing. Declare `mediaPlayback` in Play Console with the same texts and the same video. Android 15 and later refuse a `mediaPlayback` start inside a boot broadcast. The 30-second boot recovery (`RECOVERY_DELAY_MS`) stays whichever type is used (Plan 6 decision 9), and it is what covers that refusal.

## Manifest reference

The permissions the app's own manifest declares, and where each is explained. The two marked "merged" are added by libraries and come from the plan's read of a local release build on 2026-11-14 (before Task 2). Task 4 Step 5 reads the merged release manifest again and records the list in the run log. The listing and the privacy policy's permission table must agree with it.

| Permission | Why the app has it | Declaration |
|---|---|---|
| `USE_EXACT_ALARM` | Ring at the exact minute (Android 13 and later) | Exact alarms |
| `SCHEDULE_EXACT_ALARM` (up to SDK 32) | The same on Android 12 and 12L, where the system grants it by default | Exact alarms |
| `USE_FULL_SCREEN_INTENT` | The full-screen alarm | Full-screen intent |
| `POST_NOTIFICATIONS` | Heads-ups and the ringing notification | None (runtime permission) |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SYSTEM_EXEMPTED` | `RingingService` | Foreground service |
| `RECEIVE_BOOT_COMPLETED` | Set the alarms again after a restart | None |
| `WAKE_LOCK` | Keep the CPU awake while an alarm rings | None |
| `VIBRATE` | Vibrate while an alarm rings | None |
| `INTERNET` | Fetch the calendar links the user added | None |
| `READ_CALENDAR` | Read the phone calendars the user chose | None |
| `ACCESS_NETWORK_STATE` (merged, from WorkManager) | Wait for a connection before a scheduled sync | None |
| `io.github.fifothehein.tminus.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (merged, signature level) | Keeps the app's own dynamic receivers private | None |

Not declared, on purpose: `AD_ID`, `QUERY_ALL_PACKAGES`, and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Play restricts it, so the app opens the battery settings screen instead, spec section 7).
