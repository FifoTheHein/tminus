---
title: Privacy policy
permalink: /privacy/
---

# T-Minus privacy policy

Effective 14 November 2026.

T-Minus turns the meetings in your calendars into alarms on your Android phone. It has no account, no server, no analytics, no ads and no crash reporting. Nobody, including the developer, receives your calendar or anything else from the app. If you installed T-Minus from Google Play, Android and Google Play may share crash reports and install statistics with the developer, as they do for every app, depending on your phone's settings. These come from Android and Google Play, not from the app.

## What the app reads

- **Calendar links you paste.** If you add a calendar by its published link (for example an Outlook or Google ICS link), the app stores the link in Android's encrypted storage on your phone, never in its database, and fetches it over the internet to read your meetings. The link works like a password, so the app shows it only masked and never writes it to its logs.
- **Calendars on your phone.** If you choose a calendar that is already on your phone, the app asks for the Calendar permission. It then lists the calendars on your phone (their names, accounts and colours) so you can pick one, and reads the events of the calendars you chose. It never changes your calendars.
- **Meetings.** From those calendars the app reads each meeting's title, time, location, organiser, description and Teams link, whether it shows you as busy or free, and whether it was cancelled or you declined it. It uses them to decide which meetings ring, to show them, and to open the Teams link when you tap Join.

## Where it is kept

Apart from the Android backup described below, everything the app stores stays on your phone. Meetings are kept in a cache, together with a history of the alarms of the last 30 days that includes each meeting's title. The cache is never included in a backup.

Android can back up the app's settings to your Google account, such as your alert profiles, rules, quiet mode, the names and colours of your calendars, and which meetings you switched on or off. On Android 9 and later the backup is made only if Android can encrypt it end to end. On Android 8 the backup is not end to end encrypted. When you move to a new phone with Android's transfer tool, the same settings are copied to it. The backup never contains your calendar links or your meetings. On a new phone the app asks you to add each calendar link again.

## What leaves your phone

- **Calendar fetches.** The app downloads each calendar link you added, directly from that calendar's server (for example Microsoft or Google). That server sees your phone's internet address, as with any download. The request carries only standard download details: the name and version of the software making the request, the kinds of file the app accepts and, when the app has downloaded the calendar before, the markers the server sent last time, so that it can answer that nothing changed. No account, device id or other information about you is sent. If a link starts with http:// instead of https://, the download is not encrypted; the app warns you about this when you add the link.
- **Links you open.** Join opens the meeting's Teams link in the Teams app or your browser, and the privacy policy link opens this page in your browser. Those apps and sites have their own privacy policies.
- **Settings export.** If you export your settings, the app writes a file where you choose. The file contains your settings, such as your alert profiles, rules and the names and colours of your calendars, but no calendar links and no meetings. It stays where you saved it, even after you uninstall the app.

## Permissions

| Permission | Why |
|---|---|
| Alarms and reminders (exact alarms) | To ring at the exact minute before a meeting. |
| Notifications and full-screen alerts | To show heads-up reminders and the full-screen alarm, including on the lock screen. |
| Calendar | Only if you choose a calendar on your phone: to list your calendars and read the events of the ones you chose. |
| Internet | Only to fetch the calendar links you added. |
| Network state | To wait for an internet connection before a scheduled sync. |
| Run at startup, wake lock, vibrate, foreground service | To set your alarms again after a restart and to ring, vibrate and keep ringing until you stop the alarm. |

## Deleting your data

Removing a calendar in the app deletes its link and its meetings at once, and the history of its alarms within 30 days. Uninstalling the app deletes everything it stored on your phone, but not a settings export you saved. To delete the app's Android backup, remove it in your Google account's backup settings.

## Children

T-Minus is a work tool and is not directed at children.

## Changes and contact

If this policy changes, the new version is published on this page with a new effective date. Questions: open an issue at https://github.com/FifoTheHein/tminus/issues.
