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

Limit 4000 characters. This text has 2174. It is plain text, with line breaks and bullets (•) for the lists.

```text
T-Minus turns your calendar meetings into alarms you can't miss, and can always stop.

ADD YOUR CALENDARS
• Pick a calendar already on your phone, for example from a Google, Samsung, Outlook or Exchange account, or paste a calendar link (Outlook, Google Calendar or any ICS link).
• Teams meetings come in through your calendar, for example Outlook.
• A meeting with a Teams, Google Meet, Zoom or Webex link gets a Join button. On a phone calendar, T-Minus finds the link when it is written in the meeting's description or location.
• Calendars are checked about every 15 minutes, and again shortly before each alarm.

ALERTS THAT GET STRONGER
• A heads-up notification first, then a full-screen alarm on the alarm volume.
• Out of the box: a heads-up 10 minutes before, an alarm 1 minute before.
• Meeting, Quick, Important and Silent profiles, or make your own.
• Keyword rules pick a profile by a meeting's title, organiser and more.
• All-day, free, tentative and cancelled meetings, and meetings you declined in a phone calendar, are skipped unless you change that.

QUIET WHEN YOU NEED IT
• Mute today, Pause or Vacation, plus a Mute today tile for quick settings.
• Meetings on the Important profile still ring during Mute today and Pause.

ALWAYS A WAY TO STOP
• Stop from the notification or the alarm screen. On the alarm screen, the volume keys stop it too.
• Snooze for 1 or 5 minutes, until 1 minute before, or until the meeting starts.

KNOW WHY IT WILL OR WON'T RING
• Every meeting shows its alerts and why.
• A meeting found in two calendars rings once.
• The Health tab checks permissions, battery settings and sync, and lists your next alarms.

PRIVATE
• No account, no ads, no analytics. Your calendar stays on your phone.
• Calendar links are stored encrypted and never backed up.
• T-Minus uses the internet only to fetch the calendar links you add.

Needs Android 8 or later.

Outlook and Teams are trademarks of Microsoft. Google Calendar and Google Meet are trademarks of Google. Zoom and Webex are trademarks of their owners. T-Minus is an independent app and is not affiliated with or endorsed by Microsoft, Google or the owners of Zoom and Webex.
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

The website's Support section (Buy Me a Coffee) is left out of the listing on purpose: Play's Payments policy rejects donation links. It also stays out of the app and the privacy policy page, and `test/app/support_link_test.dart` checks that.

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
| A Join button opens a meeting's Teams, Google Meet, Zoom or Webex link | `packages/ics_core/lib/src/meeting_links.dart` (`extractJoinUrl` finds the link, `meetingServiceOf` names its service), `NotificationFactory.kt` (the heads-up and ringing notifications of one meeting), `AlarmScreen.kt` (each meeting), `JoinActivity.kt` (the notifications and the alarm screen) and `android/.../ui/UiChannel.kt` (`openUrl`, the event sheet) open it with `ACTION_VIEW`; `lib/features/agenda/event_sheet.dart` (`_joinLabel`: Join Teams meeting, Join Google Meet, Join Zoom meeting, Join Webex meeting) |
| On a phone calendar, a link is found when it is written in the meeting's description or location | `lib/core/sources/occurrence_mapping.dart` (`occurrenceFromDevice` passes the description and the location to `extractJoinUrl`, and no conference), `android/.../calendar/DeviceCalendarReader.kt` (`INSTANCE_COLUMNS` has no conference or extended property) |
| A check about every 15 minutes, and one shortly before each alarm | `android/.../sync/SyncScheduler.kt` (periodic, 15 minutes), `PreSyncScheduler.kt` (12 minutes before the earliest alert) |
| Heads-up follows the sound settings | `NotificationFactory.kt` (the `heads_up` channel) |
| Alarm: alarm volume, vibration, full-screen alarm, ring timeout | `RingingService.kt` (`ALARM_ATTRIBUTES`, vibration, `restartTimeout`), `NotificationFactory.kt` (`setFullScreenIntent`), `AlarmActivity.kt`, `lib/core/model/alert.dart` (`SoundSettings`: two minutes) |
| Meeting profile: heads-up 10 minutes, alarm 1 minute; Quick, Important, Silent | `lib/core/model/alert_profile.dart` (`BuiltInProfiles`) |
| Own profiles: alert times, tone, vibration, volume ramp | `lib/features/alerts/profile_editor_screen.dart` |
| Keyword rules by title, location, organiser or description, or a meeting link (Teams, Google Meet, Zoom or Webex) | `lib/core/model/keyword_rule.dart` (`RuleField`, `hasJoinLink`), `lib/features/alerts/rule_editor_screen.dart` |
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

- The plan's short description is kept as written. The full description adds one sentence that says Teams meetings reach T-Minus through the user's own calendar, for example Outlook, because the app has no Teams connection of its own and Google feeds carry Teams meetings too.
- The last paragraph of the full description (the trademark and independence statement) is not in the plan. It is true, and it keeps the listing's use of the Outlook, Teams, Google Calendar, Google Meet, Zoom and Webex names to a plain description of what the app reads. It does not name the owners of Zoom and Webex, because nothing in the repository says who they are.
- Plan 7 widened the Join sentence from Teams to Teams, Google Meet, Zoom and Webex, and added the phone-calendar sentence after it. Whether a phone calendar holds the Meet link that Google Calendar adds with its video conferencing button was not checked on a phone, so the text says only where T-Minus looks (the description and the location).
- The volume keys stop an alarm only while the full-screen alarm is showing, and the text says so. When the phone is unlocked and in use, Android may show the alarm as a notification instead; its Stop button works, and opening T-Minus goes to the alarm screen.
- The full description was shortened in F6 (2026-11-18). The claims table (Where each claim comes from) is a superset of the text on purpose, so a row can name a claim the text no longer makes.
- Re-count the three fields if any of them is edited. The limits are 30, 80 and 4000 characters.
- The graphics sizes and formats in the table above are the plan's and Play's help as the plan read it. Check them in Play Console on the day, as for the Data safety answers.
