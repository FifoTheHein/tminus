# Play Store listing: T-Minus: Meeting Alarm

The copy and settings to enter under Play Console's **Main store listing**, with the graphics. The answers for **App content** are in [declarations.md](declarations.md).

House style: plain sentences, no marketing superlatives, no competitor names, no em dashes. British English, to match the app and the default listing language (English, United Kingdom).

Every factual sentence below was checked against the code when this file was written. The table at the end names where each claim comes from. Task 10's reviewer reads the file against the code again before anything is entered in Play Console.

## App name

Limit 30 characters. This text has 22.

```text
T-Minus: Meeting Alarm
```

The trademark search (Plan 6, Task A) found no live registration of T-MINUS, TMINUS or T MINUS for software, alarms or calendars, so the name stays. The nearest marks are composites, listed in the plan's run log. It is not legal advice.

## Short description

Limit 80 characters. This text has 78.

```text
Meeting alarms you can't miss, for Outlook, Teams and phone calendar meetings.
```

## Full description

Limit 4000 characters. This text has 3384. It is plain text, with line breaks and hyphens for the lists.

```text
T-Minus turns the meetings in your calendars into alarms on your Android phone. It is for people who spend much of the day in meetings.

ADD YOUR CALENDARS
- Choose a calendar that is already on your phone, for example one from a Google, Samsung, Outlook or Exchange account. T-Minus asks for the Calendar permission only for this.
- Or paste a calendar link. Outlook, Google Calendar and any other ICS link work, and T-Minus checks a link before it adds it.
- Teams meetings come in through your Outlook calendar. When a meeting has a Teams link, a Join button opens it.
- T-Minus checks your calendars about every 15 minutes, and again shortly before each alarm.

ALERTS THAT GET STRONGER
- A heads-up is a notification before the meeting. It follows your phone's sound settings.
- An alarm rings on the alarm volume and opens a full-screen alarm over the lock screen. It rings until you stop it, snooze it, or its ring timeout (2 minutes unless you change it) ends.
- Out of the box, the Meeting profile gives a heads-up 10 minutes before a meeting and an alarm 1 minute before. Quick, Important and Silent profiles are built in, and you can make your own, with your own alert times, tone, vibration and volume ramp.
- Keyword rules pick a profile by words in a meeting's title, location, organiser or description, or by whether it has a Teams link.
- All-day, free, tentative, cancelled and declined meetings are skipped unless you switch that filter off. The declined filter works for phone calendars only.
- Change the alerts of a single meeting, or of a whole series, from its details.

QUIET WHEN YOU NEED IT
- Mute today silences alerts until 07:00 the next day. Pause silences them for 1, 2 or 4 hours, or until a time you pick. Vacation silences them for the dates you choose.
- A meeting on a profile that rings in quiet mode (Important does) still rings during Mute today and Pause. During Vacation only meetings you switched on yourself ring.
- A Mute today tile for quick settings turns it on and off.

ALWAYS A WAY TO STOP
- You can stop an alarm from its notification or from the full-screen alarm. While the full-screen alarm is showing, the volume keys stop it too.
- Snooze for 1 or 5 minutes, until 1 minute before the meeting, or until it starts.
- Alerts that fall in the same minute share one notification and one alarm screen. The alarm screen has a Dismiss button for each meeting, and a Join button for each one with a Teams link.

KNOW WHY IT WILL OR WON'T RING
- Every meeting in the Agenda shows its alerts and says why, for example that a rule matched, or that it is skipped because it is free.
- A meeting found in two of your calendars rings once. You can switch this off in Settings.
- The Health tab checks notifications, full-screen alarms, exact alarms, battery settings, the alarm volume and each calendar's sync, with a Fix button for each problem. It also lists your next alarms and keeps a history.

PRIVATE
- No account, no ads and no analytics. Your calendar stays on your phone.
- Calendar links are kept in encrypted storage and are never part of a backup.
- T-Minus uses the internet only to fetch the calendar links you add.

T-Minus needs Android 8 or later.

Outlook and Teams are trademarks of Microsoft. Google Calendar is a trademark of Google. T-Minus is an independent app and is not affiliated with or endorsed by either company.
```

## Store settings

| Setting | Value |
|---|---|
| App or game | App |
| Free or paid | Free |
| Category | Productivity |
| Tags | Chosen in Play Console from its list (alarm, calendar, productivity) |
| Default language | English (United Kingdom) |

## Contact details

| Field | Value |
|---|---|
| Website | `https://fifothehein.github.io/tminus/` |
| Email | Entered in Play Console only. Play shows it publicly on the listing, so it is an address meant for that, and it never goes into the repository (Plan 6 decision 5). |
| Phone | None |

The privacy policy URL is entered under App content, not here (see declarations.md).

## Graphics

| Asset | File | Format | Made by |
|---|---|---|---|
| App icon | `docs/play/icon-512.png` | 512 x 512 px, 32-bit PNG with an alpha channel | `tool/gen_launcher_icon.py` |
| Feature graphic | `docs/play/feature-graphic.png` | 1024 x 500 px, 24-bit PNG with no alpha channel (colour type 2) | `tool/gen_feature_graphic.py` |
| Phone screenshots | `docs/play/screenshots/*.png` (Task 9) | 4 to 8 images at 1080 x 2400 or the emulator's native size, as JPEG or 24-bit PNG with no alpha channel | the emulator |

- The feature graphic follows the icon. It loads the icon script's geometry and colour tokens, so run `python tool/gen_feature_graphic.py` again after any change to the icon, and commit the new PNG. Running it twice writes the same bytes.
- `test/launcher_icon_test.dart` pins the size and the format of both PNGs.
- Screenshots come from `adb exec-out screencap -p`. If a screenshot has an alpha channel, remove it before upload (Task 9 checks each file).
- The screenshots use the demo calendar (`docs/play/demo.ics`), so no real meeting appears on the listing.

## Where each claim comes from

Names are files and symbols, not line numbers, so the table stays true when code moves.

| Claim | Where |
|---|---|
| The two ways to add a calendar; Outlook, Google Calendar and any ICS link; the link check | `lib/features/sources/add_source_panel.dart` (the two cards, the Check button), `lib/features/sources/link_help.dart` (`LinkProvider`), `lib/core/sources/ics_link_probe.dart` |
| Google, Samsung, Outlook and Exchange accounts | `lib/features/sources/calendar_groups.dart` (`CalendarGroupKind`, `kindLabel`) |
| The Calendar permission is asked for only with a phone calendar | `lib/features/sources/calendar_picker.dart`, `lib/features/onboarding/onboarding_controller.dart`, `lib/features/sources/source_detail_screen.dart` (the three places that ask); the manifest comment on `READ_CALENDAR` |
| A Join button opens a meeting's Teams link | `NotificationFactory.kt` (the heads-up and ringing notifications of one meeting), `AlarmScreen.kt` (each meeting), `lib/features/agenda/event_sheet.dart` (Join Teams meeting) |
| A check about every 15 minutes, and one shortly before each alarm | `android/.../sync/SyncScheduler.kt` (periodic, 15 minutes), `PreSyncScheduler.kt` (12 minutes before the earliest alert) |
| Heads-up follows the sound settings | `NotificationFactory.kt` (the `heads_up` channel) |
| Alarm: alarm volume, vibration, full-screen alarm, ring timeout | `RingingService.kt` (`ALARM_ATTRIBUTES`, vibration, `restartTimeout`), `NotificationFactory.kt` (`setFullScreenIntent`), `AlarmActivity.kt`, `lib/core/model/alert.dart` (`SoundSettings`: two minutes) |
| Meeting profile: heads-up 10 minutes, alarm 1 minute; Quick, Important, Silent | `lib/core/model/alert_profile.dart` (`BuiltInProfiles`) |
| Own profiles: alert times, tone, vibration, volume ramp | `lib/features/alerts/profile_editor_screen.dart` |
| Keyword rules by title, location, organiser or description, or a Teams link | `lib/core/model/keyword_rule.dart` (`RuleField`), `lib/features/alerts/rule_editor_screen.dart` |
| Skipped meetings, all five filters on by default, declined for phone calendars only | `lib/core/model/skip_filters.dart`, `lib/core/rules/rules_engine.dart`, `lib/features/alerts/alerts_screen.dart` |
| Alerts of one meeting or a series | `lib/features/agenda/event_sheet.dart` |
| Mute today, Pause, Vacation, what still rings, the tile | `lib/features/quiet/quiet_sheet.dart`, `lib/core/rules/rules_engine.dart` (`resolve`), `android/.../quiet/QuietTileService.kt` |
| Stop from the notification, the full-screen alarm and the volume keys | `NotificationFactory.kt` (`ringing`), `AlarmActivity.kt` (`dispatchKeyEvent`, only while the full-screen alarm is showing), `AlarmScreen.kt` |
| Snooze options | `android/.../engine/SnoozeOptions.kt` |
| Alerts in the same minute share one notification and screen | `lib/core/planner/plan_builder.dart` (`coalesceGroup`), `NotificationFactory.kt` (`coalesced`), `AlarmScreen.kt` (`CoalescedActions`) |
| The Agenda shows each meeting's alerts and why | `lib/features/agenda/agenda_widgets.dart` (`AgendaCard`), `lib/features/agenda/why_text.dart` |
| A meeting in two calendars rings once; the switch in Settings | spec section 13, `lib/core/planner/meeting_merger.dart`, `lib/features/settings/settings_screen.dart` (`mergeSwitch`, on by default) |
| What Health checks, upcoming alarms, history | `lib/features/health/health_report.dart`, `lib/features/health/health_screen.dart` |
| No account, ads or analytics; the internet is used only for the calendar links | `pubspec.lock` and `android/app/build.gradle.kts` hold no analytics, advertising or crash-reporting library; `http.Client` is used only by `lib/core/sources/ics_feed_source.dart` and `ics_link_probe.dart`; [the privacy policy](../privacy.md) |
| Links are stored encrypted and are never backed up | `lib/core/sources/source_secrets.dart` (secure storage); `android/app/src/main/res/xml/backup_rules.xml` and `data_extraction_rules.xml` list only the database files. Meetings stay out of a backup because of Task 3 (3b246a4): the cache database (`tminus_cache.sqlite`), the move of the expected-alerts key `sync.missedSystemExpected` (it holds meeting titles) out of the backed-up settings table (run-log R9), and the one-off compaction of `tminus.sqlite` after the upgrade, so that no meeting text stays in its free pages or WAL (R16). The backup is end to end encrypted from Android 9 (declarations.md and the policy) because Task 4 (7416baf) puts `requireFlags="clientSideEncryption"` on the backup rules for Android 9 to 11 (decision 20) |
| Android 8 and later | `android/app/build.gradle.kts` (`minSdk = 26`) |

## Notes for Task 10's reviewer

- The plan's short description is kept as written. The full description adds one sentence that says Teams meetings reach T-Minus through the Outlook calendar, because the app has no Teams connection of its own.
- The last paragraph of the full description (the trademark and independence statement) is not in the plan. It is true, and it keeps the listing's use of the Outlook, Teams and Google Calendar names to a plain description of what the app reads.
- The volume keys stop an alarm only while the full-screen alarm is showing, and the text says so. When the phone is unlocked and in use, Android may show the alarm as a notification instead; its Stop button works, and opening T-Minus goes to the alarm screen.
- Re-count the three fields if any of them is edited. The limits are 30, 80 and 4000 characters.
- The graphics sizes and formats in the table above are the plan's and Play's help as the plan read it. Check them in Play Console on the day, as for the Data safety answers.
