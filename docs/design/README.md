# T-Minus screen mockups

Exported from the Claude Design project ([open interactive version](https://claude.ai/design/p/b3ee1986-af3e-4399-9aeb-efd063edfd49)). Dark theme unless noted. 2x PNG, 420×880 pt frames.

| Screen | File |
|---|---|
| Agenda | [1a-agenda-dark.png](1a-agenda-dark.png) |
| Alarm (full screen) | [1b-alarm-dark.png](1b-alarm-dark.png) |
| Alarm, coalesced | [1c-alarm-coalesced.png](1c-alarm-coalesced.png) |
| Event detail sheet | [2a-event-detail.png](2a-event-detail.png) |
| Quiet modes sheet | [2b-quiet-modes.png](2b-quiet-modes.png) |
| Agenda, quiet mode | [2c-agenda-quiet.png](2c-agenda-quiet.png) |
| Alerts · Profiles | [3a-alerts-profiles.png](3a-alerts-profiles.png) |
| Profile editor | [3b-profile-editor.png](3b-profile-editor.png) |
| Alerts · Rules | [3c-alerts-rules.png](3c-alerts-rules.png) |
| Rule editor | [3d-rule-editor.png](3d-rule-editor.png) |
| Sources | [4a-sources.png](4a-sources.png) |
| Source detail (error) | [4b-source-detail.png](4b-source-detail.png) |
| Health, all good | [4c-health-ok.png](4c-health-ok.png) |
| Health, problem | [4d-health-problem.png](4d-health-problem.png) |
| Onboarding 1 · Welcome | [5a-onboarding-welcome.png](5a-onboarding-welcome.png) |
| Onboarding 2 · Add source | [5b-onboarding-add-source.png](5b-onboarding-add-source.png) |
| Onboarding 3 · Permissions | [5c-onboarding-permissions.png](5c-onboarding-permissions.png) |
| Onboarding 4 · Test alarm | [5d-onboarding-test-alarm.png](5d-onboarding-test-alarm.png) |
| Onboarding 5 · Done | [5e-onboarding-done.png](5e-onboarding-done.png) |
| Settings | [5f-settings.png](5f-settings.png) |
| Notifications | [6a-notifications.png](6a-notifications.png) |
| Agenda, empty day | [6b-agenda-empty.png](6b-agenda-empty.png) |
| Agenda, first sync | [6c-agenda-first-sync.png](6c-agenda-first-sync.png) |
| Agenda, source error | [6d-agenda-source-error.png](6d-agenda-source-error.png) |
| Agenda, light | [6e-agenda-light.png](6e-agenda-light.png) |
| Alarm, light | [6f-alarm-light.png](6f-alarm-light.png) |

## Changed since these mockups

The PNGs and the Claude Design project still show the original designs. The app differs from them in these places, and where they disagree, the app and `docs/design-brief.md` win:

- **Logo** (1a, 5a, 5f): the app shows the launcher icon's countdown mark (`TMinusMark`): a slate disc, a light-blue arc and a "T-" mark. It replaces the "T−" ring in the Agenda app bar, on the Welcome step and on the About card. The Play listing icon is [../play/icon-512.png](../play/icon-512.png).
- **Agenda switch** (the Agenda mockups): a meeting that has started has no on/off switch.
- **Phone calendar picker** (5b, and Sources → Add source): the calendars are grouped under account headings, with **Shared with you**, **Holidays and birthdays** and **On this phone only** groups and greyed **Not synced** rows. There is no mockup. The layout sketch is in `docs/superpowers/specs/2026-11-13-calendar-grouping-design.md` §6.
- **Settings** (5f) and Developer tools: the list ends above the system navigation bar.

## Design system

Colour tokens (dark + light), type scale, spacing, radii and components, named for Flutter `ThemeData`: [design-system.png](design-system.png)
