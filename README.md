<p align="center">
  <img src="docs/play/icon-512.png" alt="T-Minus app icon" width="96" height="96">
</p>

<h1 align="center">T-Minus: Meeting Alarm</h1>

<p align="center">Meeting alarms you can't miss, for Outlook, Teams and phone calendar meetings.</p>

<p align="center">
  <img src="docs/play/feature-graphic.png" alt="T-Minus: the countdown mark, the name T-Minus and the line Meeting alarms you can't miss" width="100%">
</p>

<p align="center">
  <img src="docs/play/screenshots/1-agenda.png" alt="The Agenda, with the time to the next alarm and each meeting's alerts" width="200">
  <img src="docs/play/screenshots/2-event-sheet.png" alt="A meeting's sheet, with its alerts and why it rings" width="200">
  <img src="docs/play/screenshots/3-alarm.png" alt="The full-screen alarm" width="200">
  <img src="docs/play/screenshots/4-profiles.png" alt="Alerts, showing the alert profiles" width="200">
</p>

<p align="center">
  <img src="docs/play/screenshots/5-quiet-sheet.png" alt="The quiet modes sheet" width="200">
  <img src="docs/play/screenshots/6-health.png" alt="Health, with the checklist and the upcoming alarms" width="200">
  <img src="docs/play/screenshots/7-agenda-light.png" alt="The Agenda in the light theme" width="200">
  <img src="docs/play/screenshots/8-alarm-light.png" alt="The full-screen alarm in the light theme" width="200">
</p>

T-Minus turns your calendar meetings into alarms you can't miss, and can always stop.

## Add your calendars

- Pick a calendar already on your phone, for example from a Google, Samsung, Outlook or Exchange account, or paste a calendar link (Outlook, Google Calendar or any ICS link).
- Teams meetings come in through your calendar, for example Outlook.
- A meeting with a Teams, Google Meet, Zoom or Webex link gets a Join button. On a phone calendar, T-Minus finds the link when it is written in the meeting's description or location.
- Calendars are checked about every 15 minutes, and again shortly before each alarm.

## Alerts that get stronger

- A heads-up notification first, then a full-screen alarm on the alarm volume.
- Out of the box: a heads-up 10 minutes before, an alarm 1 minute before.
- Meeting, Quick, Important and Silent profiles, or make your own.
- Keyword rules pick a profile by a meeting's title, organiser and more.
- All-day, free, tentative and cancelled meetings, and meetings you declined in a phone calendar, are skipped unless you change that.

## Quiet when you need it

- Mute today, Pause or Vacation, plus a Mute today tile for quick settings.
- Meetings on the Important profile still ring during Mute today and Pause.

## Always a way to stop

- Stop from the notification or the alarm screen. On the alarm screen, the volume keys stop it too.
- Snooze for 1 or 5 minutes, until 1 minute before, or until the meeting starts.

## Know why it will or won't ring

- Every meeting shows its alerts and why.
- A meeting found in two calendars rings once.
- The Health tab checks permissions, battery settings and sync, and lists your next alarms.

## Private

- No account, no ads, no analytics. Your calendar stays on your phone.
- Calendar links are stored encrypted and never backed up.
- T-Minus uses the internet only to fetch the calendar links you add.

Needs Android 8 or later.

Outlook and Teams are trademarks of Microsoft. Google Calendar and Google Meet are trademarks of Google. Zoom and Webex are trademarks of their owners. T-Minus is an independent app and is not affiliated with or endorsed by Microsoft, Google or the owners of Zoom and Webex.

## Availability

T-Minus is in a closed test on Google Play (version 1.0.2, 20 November 2026). It is not on the public Play Store yet.

To become a tester:

1. Join the [t-minus-testers group](https://groups.google.com/g/t-minus-testers) with the Google account your phone's Play Store uses.
2. Open the [opt-in page](https://play.google.com/apps/testing/io.github.fifothehein.tminus), tap **Become a tester**, then install T-Minus from Google Play.

Access can take a few minutes to come through after you join the group.

Bugs and questions go to [GitHub issues](https://github.com/FifoTheHein/tminus/issues). [The privacy policy](https://fifothehein.github.io/tminus/privacy/) is on GitHub Pages.

## For developers

T-Minus is an Android app. The UI is Flutter (Dart), and the alarm engine is native Kotlin (AlarmManager, a foreground service and a Compose alarm screen), so alarms ring without Flutter running. It reads published ICS feeds and calendars already on the phone, so Google calendars synced to the phone already work. Phase 2 only checks setups with several Google accounts and fills any gaps. Commands, the architecture and the rules that are easy to break are in [CLAUDE.md](CLAUDE.md).

### Build status

Plans 1 to 7 are built:

- Plan 1: the ICS parser (`ics_core`).
- Plan 2: the domain model, storage, rules and planner.
- Plan 3: the native alarm engine.
- Plan 4: sources and sync.
- Plan 4b: merging of meetings found in more than one source.
- Plan 5: the app screens.
- Plan 6: Play readiness (a signed release build, the privacy policy and a demo feed on GitHub Pages, the store listing and Play declarations, the `systemExempted` ringing service, and the meeting cache moved out of Android's backup).
- Plan 7: join links for Google Meet, Zoom and Webex (the Join button, the Agenda badge and the "Has meeting link" keyword rule work for them as they do for Teams, and the app names the meeting service).

Between Plans 5 and 6, the phone calendar picker started to group calendars by account, and the app got its own launcher icon and in-app logo.

Version 1.0.2 (build 3), which carries Plan 7, was published on Google Play internal testing on 20 November 2026 and promoted the same day to the closed testing track (Alpha), together with an updated full description (`docs/play/listing.md`) that names Google Meet, Zoom and Webex. Alpha's testers are a Google Group. Internal testing was paused the same day, so releases now go to Alpha ([docs/play/release.md](docs/play/release.md)). The app is not in production: the production release is a later step.

### Documents

- Implementation roadmap: [docs/superpowers/plans/2026-10-06-tminus-roadmap.md](docs/superpowers/plans/2026-10-06-tminus-roadmap.md)
- Design spec: [docs/superpowers/specs/2026-10-06-tminus-design.md](docs/superpowers/specs/2026-10-06-tminus-design.md)
- Play readiness (Plan 6): [docs/superpowers/plans/2026-11-14-plan-6-play-readiness.md](docs/superpowers/plans/2026-11-14-plan-6-play-readiness.md)
- Join links (Plan 7): [docs/superpowers/plans/2026-11-19-plan-7-meeting-links.md](docs/superpowers/plans/2026-11-19-plan-7-meeting-links.md)
- Calendar picker grouping: [spec](docs/superpowers/specs/2026-11-13-calendar-grouping-design.md) · [plan](docs/superpowers/plans/2026-11-13-calendar-grouping.md)
- Design brief (screens and visuals): [docs/design-brief.md](docs/design-brief.md)
- Mockups and design system: [docs/design/](docs/design/README.md) · [Claude Design project](https://claude.ai/design/p/b3ee1986-af3e-4399-9aeb-efd063edfd49)
- Releasing (versioning, signing, checks, upload to Play): [docs/play/release.md](docs/play/release.md)
