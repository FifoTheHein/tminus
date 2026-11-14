# T-Minus: Meeting Alarm, Design Brief

The brief for designing the app's screens. Engine and architecture details are in `docs/superpowers/specs/2026-10-06-tminus-design.md`.

## Product in one line

An Android app that turns your work calendar (Outlook/Teams, later Google) into alarms you can't miss and can always stop.

## Who it's for

Busy professionals who live in back-to-back Teams meetings, including people with ADHD who rely on hard alerts. They currently use calendar alarm apps that are bloated, show ads, or ring and won't stop.

## Personality

- **Precise and calm.** It works like mission control's countdown: confident, never frantic, except during the few seconds it really needs your attention.
- **Trustworthy.** It always shows *what* will ring, *when* and *why*.
- **Focused.** No weather, no gamification, no clutter.
- **Plain punctuation.** App text never uses em dashes: use a colon, a comma, a full stop or parentheses instead. `test/no_em_dash_test.dart` enforces this.

## Visual direction

- Material 3, Android-native feel. **Dark theme first** (the user works in dark mode), with a full light theme too.
- The name "T-Minus" suggests countdown and launch: use a monospace or tabular numeral style for times and countdowns (e.g. `T-10`, `−01:00`).
- Each event's calendar colour is its main accent (a left colour bar or dot). Keep the app's own accent colour restrained so calendar colours stand out.
- Alert strength gets a consistent visual language everywhere:
  - **Heads-up** 🔔: outline or soft style
  - **Alarm** ⏰: solid, high-emphasis style
- Status colours (green, amber, red) are used **only** for health and sync state.
- App icon:
  - **As built (PR #18):** a slate disc with a light-blue 270° countdown arc (round ends) over a faint track, and a "T-" mark. It reads clearly at small sizes.
  - It is an adaptive icon with a monochrome layer for themed icons, and the Play listing copy is `docs/play/icon-512.png`.
  - The app shows the same mark (`TMinusMark`, PR #19) in the Agenda app bar, on the onboarding Welcome step and in Settings → About. It uses the dark colours in both themes, so it matches the home-screen icon.

## Navigation

Bottom navigation with 4 tabs: **Agenda · Alerts · Sources · Health**. Settings sits in the top-app-bar overflow menu.

The app draws edge to edge. Screens outside the tab bar (Settings, Developer tools, Onboarding) keep their last content above the system navigation bar.

## Screens

### 1. Onboarding (first run only)

1. **Welcome:** the value in one sentence.
2. **Add a source**, with two options:
   - **Paste an Outlook ICS link.** Show a hint with a small illustration of where to find it: Outlook → Settings → Calendar → Shared calendars → Publish → ICS. The app validates the link and shows "Found 23 events this week".
   - **Use a calendar on this phone.** Shows the phone's calendars with checkboxes, grouped under headings by account kind and account (Google, Samsung account, Outlook, and so on).
     - **Shared with you**, **Holidays and birthdays** and **On this phone only** get their own groups.
     - Calendars that are not synced are greyed out with a **Not synced** label, and a footnote explains how to turn sync on.
     - The layout and the rules are in `docs/superpowers/specs/2026-11-13-calendar-grouping-design.md` §4 and §6.
     - The same picker is used from the Sources tab.
3. **Permissions**, one per step, each with a one-line reason and an Allow button:
   - notifications
   - full-screen alarms
   - battery optimisation exemption
   - calendar access (only if a device calendar was chosen)
4. **Test alarm:** "Let's make sure it rings", which fires a real alarm in 5 seconds.
5. **Done:** goes to the Agenda.

### 2. Agenda (home)

**Header**
- A large countdown to the next alarm: "Next alarm in 23 min · Sprint planning".
- Sync status: "Synced 4 min ago" normally; an amber "Feed stale" chip when old.
- Quiet-mode button (a moon icon).

**List**
- Grouped as Today, Tomorrow, then each weekday up to 7 days ahead.
- A "now" line through today's list; past events are dimmed.

**Event card**
- Calendar colour bar
- Time range
- Title
- Location, or a "Teams" badge when there's a join link
- Alert chips, e.g. `🔔 −10` `⏰ −1`
- On/off toggle, shown only until the meeting starts. Every alert fires at or before the start, so after that the toggle could change nothing.
- A small grey reason line, e.g. "Quick · rule: standup", "Silent · tentative", "Silenced · Mute today"

**Other**
- Pull to refresh.
- **Banner** while quiet mode is active, e.g. "Muted until tomorrow 07:00 · End".
- **Banner** when Health has a red item, e.g. "Alarms may not ring. Fix in Health".

**States to design**
- Normal day
- A busy day with back-to-back meetings
- An empty day ("No meetings. Enjoy")
- First sync loading
- A source error
- Quiet mode active

### 3. Event detail (bottom sheet)

- Title, time, location, organiser, calendar name and colour.
- A large **Join Teams meeting** button when a link exists.
- **Alerts for this event:** a profile picker with a scope switch **This occurrence / Whole series** (series only for repeating events).
  - "Customise" opens an alert list editor for this event only.
- **Why:** "Using *Quick* because rule 'standup' matched the title."

### 4. Alerts tab

**Profiles**
- List: Meeting (default) · Quick · Important · Silent · user profiles. Each row shows its alert chips.
- **Profile editor:**
  - name
  - alert list: each row has "minutes before" (a stepper or chips for 0/1/2/5/10/15/30) and a strength toggle (Heads-up / Alarm); add and remove rows
  - tone picker, vibration toggle, gradual volume toggle, ring timeout
  - a "Rings during quiet mode" toggle

**Rules**
- **Skip filters** at the top, as toggles:
  - All-day events
  - Free
  - Tentative
  - Declined (device calendars only)
- **Keyword rules:** a drag-to-reorder list. Each row reads "Title contains *standup* → Quick".
- **Rule editor:**
  - field dropdown: Title / Location / Organizer / Description / Has Teams link
  - match: contains (with a "regex" advanced toggle)
  - text field
  - target profile
  - a **live preview** at the bottom: "Matches 3 upcoming events", with a list of them

### 5. Sources tab

- List of sources. Each row shows:
  - colour dot, name, type icon (link or phone)
  - "Synced 4 min ago" or the error state
  - default profile
- ICS URLs are always shown masked: `outlook.office365.com/…/calendar.ics`.
- Source detail: rename, colour, default profile, "Sync now", remove, and the last error with an explanation (e.g. "Link no longer works (HTTP 404). It may have been reset in Outlook.").
- An "Add source" FAB that uses the same flow as onboarding.

### 6. Health tab

- **Overall status card:** "All good. Alarms will ring" (green), or a summary of problems.
- **Checklist rows**, each with a status icon and a **Fix** button:
  - Notifications
  - Full-screen alarms
  - Exact alarms
  - Battery optimisation
  - Alarm channel not muted
  - Sync freshness, per source
- **Phone-maker tips** (expandable), e.g. Samsung: "Add T-Minus to Never sleeping apps".
- **Upcoming alarms (engine):** the next 5 alerts as the native engine has them scheduled, each with its time, strength icon and event.
- **History:** a timeline of fired, snoozed, dismissed, joined and missed alerts. Missed ones are highlighted.
- Buttons: **Test heads-up** · **Test alarm**.

### 7. Quiet modes (bottom sheet)

- **Mute today**
- **Pause until…** (time picker)
- **Vacation** (date range picker)
- A note: "Important events still ring (except Vacation)."
- Also used as the content of the **quick-settings tile**: "Mute today", on or off.

### 8. Settings

- Default profile
- Theme: System / Dark / Light
- Export / import settings (sources are exported without their links)
- About & privacy: "Your calendar never leaves your phone."

### 9. Alarm screen (full-screen, over the lock screen)

This screen will be built natively, so keep it simple and self-contained.
- The event's calendar colour as a background wash or accent.
- A large countdown: "Starts in 1 min" (or "Starting now" / "Started 2 min ago").
- Title, time range, location or Teams.
- **Primary button:** **Join** when there's a Teams link, otherwise **Dismiss**.
- **Snooze**, which expands to show: +1 min · +5 min · 1 min before start · At start (hide past options).
- **Dismiss all alerts for this event.**
- **Coalesced state:** two or three meetings starting at the same time appear as a stacked list, each with its own Join and Dismiss.
- Large touch targets. Readable at arm's length. No slide-to-dismiss gestures.

### 10. Notifications

| Notification | Contents |
|---|---|
| **Heads-up** | "In 10 min · Sprint planning · 10:00–10:30", with actions Join · Snooze · Dismiss all |
| **Ringing** (alongside the full-screen screen) | Actions Stop · Snooze · Join · Dismiss all |
| **Missed** | "Missed: Sprint planning (10:00)", with action Open |
| **Feed stale** | "Calendar hasn't synced for 1 h. Alarms may be outdated", with action Sync now |
| **Feed broken** | "Outlook feed link stopped working", with action Fix |

## Sample data for mockups

| Time | Title | Details | Profile |
|---|---|---|---|
| 08:45–09:00 | Daily standup | Teams | Quick |
| 10:00–11:00 | Sprint planning | Teams, organiser "Thandi M." | Meeting |
| 11:00–11:30 | 1:1 with Pieter | Teams, back-to-back | Meeting |
| 12:30–13:30 | Lunch | (none) | Silent by rule |
| 14:00–15:00 | Client demo | Boardroom 2 | Important |
| 16:00–16:30 | Optional: Tech talk | Tentative | Silent |
| All day | Public holiday | Tomorrow | Skipped |

Calendar colours: blue (Work Outlook), green (Personal Google).
