# Plan 7: Join buttons for Google Meet, Zoom and Webex

> **Execution: lightweight orchestrator, run locally** (CLAUDE.md, "How work is run here"). The orchestrate skill's agents (`dev-worker`, `scout`, `review-worker`, `deep-review`) and checks, with no Gate-0 stop and no fresh session per wave. Waves follow dependencies, and no two jobs in a wave share a file. One Flutter or Gradle job runs at a time on this machine. Each part is committed, and every new test gets a negative control run by a scout.

Planned 2026-11-19 · Repo `C:\Projects\tminus` · Worktree `C:\Projects\tminus\.claude\worktrees\plan-7-meeting-links` · Branch `claude/plan-7-meeting-links` from `main` f84cc98 · Run with `/orchestrate <path to this file>`.

**Goal:** a meeting whose calendar entry holds a Google Meet, Zoom or Webex join link gets the same Join button, badge and keyword-rule match that a Teams meeting gets today, and the app names the right service everywhere it now says "Teams".

**Architecture:** the plumbing is already generic. Each meeting carries one `joinUrl` (`EventOccurrence`, `MeetingOccurrence`, `EventSnapshot` in the frozen Dart↔Kotlin contract), the keyword rule field is `RuleField.hasJoinLink`, and Join hands the link to Android with `ACTION_VIEW` (`JoinActivity.openJoinUrl`, `UiChannel` `openUrl`). Only two things are Teams-only:
- the link finder `extractTeamsJoinUrl` in `packages/ics_core/lib/src/event_fields.dart`, which both the feed parser (`vevent.dart:93`) and the phone-calendar mapping (`occurrence_mapping.dart:70`) call;
- the word "Teams" in about a dozen Dart widgets and texts and in Kotlin's `AlertText.where`.

This plan widens the finder to four services. It adds one pure function that names the service from a link, in Dart and in Kotlin, and replaces the fixed "Teams" texts with that name. No schema change and no contract change.

**Tech stack:** Dart 3.13 / Flutter 3.47, Kotlin, Robolectric (SDK 34). No new dependency.

**Size:** more than a day: four link grammars with tests, two languages, about 15 Dart and Kotlin files, docs and store text, plus a data check that needs the user's calendar and phone. So it runs as a plan, not a single session.

## Research behind this plan (2026-11-19)

The web search did not settle the exact formats, so Wave 0 checks them against real data before anything is built.

- **Google Meet in Google's ICS feeds:** a project that parses Google feeds reports that the Meet join text sits inside `DESCRIPTION`, sometimes with HTML markup ([rebellinnen-kalender #56](https://github.com/verein-amazone/rebellinnen-kalender/issues/56)). No source confirmed an `X-GOOGLE-CONFERENCE` property.
- **Google Meet on the phone:** the Google Calendar API keeps a Meet link in the event's structured `conferenceData`, not in description or location ([keeper.sh #1021](https://github.com/ridafkih/keeper.sh/issues/1021)). So Android's calendar store may not hold the link at all for an event created with "Add Google Meet video conferencing". `DeviceCalendarReader` reads no extended property today.
- **Link shapes** ([Recall.ai meeting URLs](https://docs.recall.ai/docs/meeting-urls)):
  - Meet: `meet.google.com/xxx-xxxx-xxx`;
  - Zoom: `<sub>.zoom.us/j/<digits>` (also `zoom.com`, an optional `pwd` query), personal `/my/<name>`, webinar `/w/<id>`;
  - Webex: `<sub>.webex.com/<path>/j.php?MTID=<id>` and personal rooms `<sub>.webex.com/meet/<id>` or `/join/<id>`;
  - Teams also uses `teams.cloud.microsoft/meet/<digits>` and, for personal accounts, `teams.live.com/meet/<digits>`. Today's finder misses both.
- **The user's own Outlook feed** (checked 2026-11-19, read in the session, raw file only in the git-ignored `packages/ics_core/test/fixtures/private/`): 608 events; 502 hold a Teams link, 65 a Meet link, 1 a Zoom link, none a Webex link. All 65 Meet events are Google invites accepted into Outlook. Every one has the plain link `https://meet.google.com/<code>` as its whole `LOCATION`. Their `DESCRIPTION` holds it only inside Outlook Safe Links wrappers, as `https://meet.google.com/<code>?hs=224`, plus a `https://tel.meet/<code>?pin=...` "more phone numbers" link, which is not a join link. Five also have a plain link in `DESCRIPTION`. The Zoom event has its link plain and Safe-Links-wrapped in `DESCRIPTION`. Today none of these 66 meetings gets a Join button.
- **Zoom and Webex** add-ins usually write the link into `LOCATION` and the body ([Zoom community](https://community.zoom.com/meetings-2/inconsistent-zoom-meeting-urls-prevent-teams-rooms-from-joining-meetings-81408), [Cisco community](https://community.cisco.com/t5/collaboration-knowledge-base/join-meeting-url-format/ta-p/3609454)).

## Global constraints

- **Do not raise compileSdk** (36). No new Dart package, no new Gradle dependency.
- Never edit or `dart format` `lib/core/model/alert.dart` or `lib/core/model/planned_alert.dart`. `joinUrl` stays a `String?`; no provider field enters the contract. Run `dart format` only on files the job owns.
- **Never log** a join link, a URL, a title or an exception message. Log `e.runtimeType` or a `PlatformException`'s code only.
- App text never uses em dashes (U+2014); `test/no_em_dash_test.dart` enforces it.
- Real calendar data stays out of git. Wave 0's raw files go only to the git-ignored `packages/ics_core/test/fixtures/private/`. Committed fixtures use invented ids such as `abc-defg-hij`, `https://example.zoom.us/j/12345678901`, `https://example.webex.com/meet/someone`.
- Commits: author and committer `Heinrich J Nel <38792842+FifoTheHein@users.noreply.github.com>` (repo-local config), message passed with `git commit -F <file>`, **no** Co-Authored-By, Claude-Session, "Generated with" or session-link lines.
- One Flutter or Gradle job at a time across the machine. The runner checks for `java`, `dart` or `flutter` processes from other checkouts before each build and waits if one is running.

## Review focus

1. A link that only looks like a join link is not one: `https://zoom.us/`, `https://zoom.us/download`, `https://www.webex.com/`, `https://meet.google.com/` with no code, `https://teams.microsoft.com/l/channel/...`. Pinned in T1.
2. A meeting holding two kinds of link gets exactly one, by the order in §1. Pinned in T1.
3. A Safe Links or Google redirect (`https://www.google.com/url?q=https%3A%2F%2Fmeet.google.com...`) wrapper is unwrapped for every service, as it is for Teams today. Pinned in T1.
4. Dart's and Kotlin's service names agree for every link in the §3 test table. Pinned in T1 and T2 from the same table.
5. A Teams meeting looks exactly as it does today, apart from the two rule texts §1 changes. Pinned by the unchanged Teams tests in T3 and T2.

---

## 1. Facts nobody may re-argue

- Services in scope: **Microsoft Teams, Google Meet, Zoom, Webex** (user, 2026-11-19).
- One join link per meeting, as today. Search order: Google's own conference property if Wave 0 finds one (`X-GOOGLE-CONFERENCE`), then `DESCRIPTION`, then `LOCATION`. Inside one text, the **earliest** link by position wins, whatever its service. (Plan decision: the first link in an invite is the one the organiser meant. Overturnable.)
- The service is derived from the link's host every time it is needed. It is never stored, and it never enters the Dart↔Kotlin contract.
- Recognised links (case-insensitive host, `https` only):
  - Teams: today's two forms on `teams.microsoft.com`, plus `/meet/<digits>` on `teams.cloud.microsoft` and `teams.live.com`;
  - Meet: `https://meet.google.com/<3>-<4>-<3>` (letters), with an optional query;
  - Zoom: host `zoom.us`, `zoom.com` or any subdomain of them, with path `/j/<digits>`, `/my/<name>` or `/w/<digits>`, and an optional query;
  - Webex: any subdomain of `webex.com`, with path `.../j.php?MTID=<id>`, `/meet/<id>` or `/join/<id>`.
  Anything else on those hosts is not a join link.
- Percent-encoded links inside a wrapper (Outlook Safe Links, Google's `url?q=`) are found and decoded for all four services, like Teams today. Trailing `>` and sentence punctuation are trimmed, like Teams today. HTML in `DESCRIPTION` (Google) ends a link at `<`, `"` or `'`.
- Service names shown to the user: **Teams**, **Google Meet**, **Zoom**, **Webex**.
- Texts (the old one, then the new one):
  - Agenda badge: `Teams`, then the service name.
  - Event sheet button: `Join Teams meeting`, then `Join Teams meeting`, `Join Google Meet`, `Join Zoom meeting` or `Join Webex meeting`.
  - Join failure: `Could not open the Teams link.`, then `Could not open the meeting link.`
  - Rule field label: `Has Teams link`, then `Has meeting link`.
  - Rule explanation (rules engine): `rule: Teams link`, then `rule: meeting link`. The explanation is computed on every plan and never stored, so no old value needs reading.
  - Why text: `...because it has a Teams link.`, then `...because it has a meeting link.`
  - The Alerts screen's rule help text: "Teams link" becomes "meeting link (Teams, Google Meet, Zoom or Webex)".
  - Kotlin `AlertText.where`: `Teams` becomes the service name. A location that already contains the service's name (`Microsoft Teams Meeting`, `Zoom`, `Google Meet`, `Webex`) is not repeated.
- The phone-calendar scope depends on Wave 0 (Gate 0). If Android's calendar store does not hold the Meet link, phone calendars still get Zoom, Webex and Teams links from description and location, and Meet only where the link is in the text. That limit is then written into the docs, and reading Google's extended properties stays out of scope (§5).
- No drift schema change, no migration, no contract change. No deep-review job: no money, migration or security surface. Opening the link is unchanged (`ACTION_VIEW`, `https` only), and the review-worker checks the logging rule.

## 2. Standing rules for this plan

- `WORKDIR` for every job: `C:\Projects\tminus\.claude\worktrees\plan-7-meeting-links`. Every git command is `git -C <WORKDIR> ...`; every path is absolute.
- Flutter commands run from `WORKDIR`; `dart test` for ics_core from `WORKDIR\packages\ics_core`; Gradle from `WORKDIR\android` with `.\gradlew.bat`.
- No em dash and no logged link: `test/no_em_dash_test.dart` runs in every Flutter close, and the review-worker reads every new log line.
- Every existing Teams test keeps its link and its meaning. A test whose expected text changes because of §1's texts changes only that string.
- `TASK:` lines are labels (report-only plan, §7).

## 3. How the parts connect

| Name | Kind | Shape | Owner job | On failure |
|-|-|-|-|-|
| `MeetingService` | Dart enum, `packages/ics_core/lib/src/meeting_links.dart`, exported from `ics_core.dart` | `teams, googleMeet, zoom, webex`; `String get label` returns `Teams`, `Google Meet`, `Zoom`, `Webex` | J1 | - |
| `meetingServiceOf` | Dart function, same file, exported | `MeetingService? meetingServiceOf(String? url)`: the service of a link the finder would return; null for null or any other link | J1 | null, never throws |
| `extractJoinUrl` | Dart function, same file, exported; replaces `extractTeamsJoinUrl` | `String? extractJoinUrl(String? description, String? location, {String? conference})`: searches `conference`, then `description`, then `location`; the earliest recognised link in each text | J1 | null, never throws (malformed percent-encoding is skipped, as today) |
| `extractTeamsJoinUrl` | removed | callers move to `extractJoinUrl` (`vevent.dart` in J1, `occurrence_mapping.dart` in J3) | J1, J3 | - |
| `X-GOOGLE-CONFERENCE` | ICS property read by `vevent.dart` | its value is passed as `conference:`, **only if Gate 0 confirms it exists** | J1 | absent: `conference` is null |
| `MeetingService` (Kotlin) | `android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/MeetingService.kt` | `enum class MeetingService(val label: String) { TEAMS("Teams"), GOOGLE_MEET("Google Meet"), ZOOM("Zoom"), WEBEX("Webex"); companion object { fun of(url: String?): MeetingService? } }`, the same host and path rules as `meetingServiceOf` | J2 | null |
| `AlertText.where` | Kotlin, existing | the service's label instead of `"Teams"`; the location is skipped when it contains the label (ignoring case) or, for Teams, `Teams` | J2 | no link: location only, as today |
| `AgendaItem.service` | Dart getter, `lib/features/agenda/agenda_model.dart`; replaces `hasTeams` | `MeetingService? get service => meetingServiceOf(meeting.joinUrl)` | J3 | null: no badge, no Join |
| `MeetingBadge` | Dart widget, `lib/features/common/alert_chips.dart`; replaces `TeamsBadge` | `const MeetingBadge({super.key, required MeetingService service})`, icon `Icons.videocam_rounded`, label `service.label` | J3 | - |
| Join button text | `lib/features/agenda/event_sheet.dart` | `Join Teams meeting`, `Join Google Meet`, `Join Zoom meeting`, `Join Webex meeting` | J3 | - |
| Shared test table | both test authors | the same 21 links and expected services: 5 Teams (today's 2 forms, `teams.cloud.microsoft`, `teams.live.com`, a Safe Links wrap), 4 Meet (plain, with `?authuser=0`, a Google `url?q=` wrap, HTML `href="...">`), 5 Zoom (`us06web.zoom.us/j/..?pwd=`, `zoom.us/my/name`, `zoom.com/j/..`, `/w/..`, a Safe Links wrap), 3 Webex (`j.php?MTID=`, `/meet/`, `/join/`), 4 not links (`https://zoom.us/download`, `https://www.webex.com/`, `https://meet.google.com/`, `https://tel.meet/abc-defg-hij?pin=1234`); the Meet rows include Outlook's form, a Safe Links wrap of `https://meet.google.com/abc-defg-hij?hs=224` | T1 writes it in Dart, T2 copies the same rows into Kotlin | - |

## 4. Acceptance criteria → tests

| AC | Test (scenario) | Test author | Implementation |
|-|-|-|-|
| AC1 Every link in the shared table is found, with the right service; the three non-links give null | `meeting_links_test.dart`: table-driven `extractJoinUrl` and `meetingServiceOf` | T1 | J1 |
| AC2 Wrapped and HTML-embedded links are found and decoded; trailing punctuation trimmed | `meeting_links_test.dart`: Safe Links Zoom and Webex, Google `url?q=` Meet, `href="https://meet.google.com/abc-defg-hij">` | T1 | J1 |
| AC3 Two links in one text: the earliest wins; description before location; conference first (if Gate 0 keeps it) | `meeting_links_test.dart`: order cases | T1 | J1 |
| AC4 Existing Teams behaviour is unchanged | `event_fields_test.dart` Teams group moved to `extractJoinUrl`, every old expectation kept | T1 | J1 |
| AC5 A feed event carries its Meet, Zoom or Webex link through expansion | `expand_single_test.dart` on a new committed fixture `meeting_links.ics` (invented ids; one VEVENT per service, one with two links, one Google-style HTML description) | T1 | J1 |
| AC6 Kotlin names the service the same way, and `where` shows it without repeating the location | `MeetingServiceTest.kt` (the shared table), `AlertTextTest.kt` (Zoom with location `Zoom`, Meet with `Boardroom 2`) | T2 | J2 |
| AC7 Notifications and the alarm screen show the service name | `NotificationFactoryTest.kt` body `10:00–10:30 · Zoom`; `AlarmScreenModelTest.kt` `where` `Google Meet` | T2 | J2 |
| AC8 A phone-calendar instance with a Zoom link in its location gets the link | `occurrence_mapping_test.dart` | T3 | J3 |
| AC9 The Agenda shows the service badge; the event sheet shows the service's Join text and the new failure text | `agenda_screen_test.dart`, `event_sheet_test.dart`, `agenda_model_test.dart` | T3 | J3 |
| AC10 Rule texts: `Has meeting link`, `rule: meeting link`, `because it has a meeting link.` A Zoom meeting matches a `hasJoinLink` rule | `rule_text_test.dart`, `rule_editor_test.dart`, `alerts_screen_test.dart`, `why_text_test.dart`, `rules_engine_test.dart`, `keyword_rule_test.dart` | T3 | J3 |

## 5. Out of scope: do not build, do not propose

- Any service other than the four: Skype, GoTo, BlueJeans, Jitsi, Whereby, Chime, Slack huddles, dial-in numbers.
- Teams government hosts (`gov.teams.microsoft.us`, `dod.teams.microsoft.us`) and Zoom for Government (`zoomgov.com`).
- Reading Google's structured conference data: the Calendar API, a Google sign-in, or Android calendar extended properties. If Gate 0 shows the phone store lacks Meet links, that stays a documented limit, and a later plan may take it up.
- More than one join link per meeting, or letting the user choose which.
- Storing the service, any schema or contract change.
- New icons per service or brand logos. All four use the same video icon; no trademarked artwork.
- Changes to the demo feed (`docs/play/demo.ics`; `links_test` pins it).
- The Play release, store-text upload and review. Those are §7 steps for the user.

## 6. Waves

### Setup (scout)

1. `git -C C:\Projects\tminus fetch origin`, then `git -C C:\Projects\tminus worktree add -b claude/plan-7-meeting-links C:\Projects\tminus\.claude\worktrees\plan-7-meeting-links origin/main`.
2. `git -C <WORKDIR> branch --unset-upstream` (no upstream until the push in §7).
3. Copy `gradlew`, `gradlew.bat`, `local.properties` and `gradle/wrapper/gradle-wrapper.jar` from `C:\Projects\tminus\android\` (git-ignored, CLAUDE.md).
4. Baseline: `flutter pub get`, `flutter analyze`, `flutter test`, `dart test` in `packages/ics_core`, `.\gradlew.bat :app:testDebugUnitTest`, one at a time.

ACCEPTANCE: branch name; `HEAD` equals `origin/main`; `@{u}` unset; analyze `No issues found!`; each suite's summary line passing.

### Wave 0: what the real data looks like (user + scout, read-only)

#### W0.1: Google, Zoom and Webex in a Google ICS feed

Outlook feeds are already answered (see Research: the user's own feed). This job covers Google's own ICS export only.

AGENT: scout, with the user · TASK: plan-7-data
- The user puts in `C:\Projects\tminus\.claude\worktrees\plan-7-meeting-links\packages\ics_core\test\fixtures\private\` (git-ignored) a Google Calendar ICS export, or the secret iCal address saved to a file. It holds at least one event with "Add Google Meet video conferencing", and if possible one with a Zoom link and one with a Webex link.
- The scout reports, **without printing any value**:
  - the property names of each such VEVENT;
  - for each of `DESCRIPTION`, `LOCATION`, `X-GOOGLE-CONFERENCE` and any other `X-` property: whether it contains `meet.google.com`, `zoom.us` or `webex.com`, and whether the link is plain, percent-encoded or inside HTML (`href=`).
- ACCEPTANCE: a table, property by service, holding `plain`, `encoded`, `html` or `absent`; `git -C <WORKDIR> status --short` empty (private/ is ignored).

#### W0.2: Google Meet in Android's calendar store

AGENT: scout, with the user · TASK: plan-7-data
- The user connects the phone and names one upcoming Google event that has Meet.
- The scout, read-only over `adb -s <serial>`, uses `content query` on `content://com.android.calendar/instances/when/<begin>/<end>` with a projection of `title, description, eventLocation, event_id`, and on `content://com.android.calendar/extendedproperties` with a `where event_id=<id>`. Find the event by the title the user gives, but **never print the title, the description or any value**.
- It reports, for that event: whether `description`, `eventLocation` or any extended property (by `name` only) contains `meet.google.com`.
- ACCEPTANCE: one line per column or property name: `contains meet link: yes` or `no`.

#### Gate 0

Evidence:
- [ ] W0.1 table: where Meet, Zoom and Webex links sit in Google's feed.
- [ ] W0.2: whether the phone store holds the Meet link, and in which column or property.

Decisions due:
- Keep or drop the `conference:` parameter and `X-GOOGLE-CONFERENCE` (J1).
- If W0.2 finds the link in an extended property, the orchestrator records it and asks the user whether to add a reader job. That would be a later plan (§5); this plan does not grow by itself.
- Any link form the data shows that §1 lacks becomes a correction under "Decisions taken", before Wave 1 goes out.

### Wave 1: the link finder (Dart) and the service name (Kotlin)

Implementations first: J1, J2. Then, as each passes Check, its test author: T1 (after J1), T2 (after J2). No file is owned by two of them.

#### J1: Find Meet, Zoom and Webex links in ics_core

```
AGENT:   dev-worker
TASK:    plan-7-links
SKILL:   none
WORKDIR: C:\Projects\tminus\.claude\worktrees\plan-7-meeting-links

OWNS:  packages/ics_core/lib/src/meeting_links.dart (new)
       packages/ics_core/lib/src/event_fields.dart
       packages/ics_core/lib/src/vevent.dart
       packages/ics_core/lib/src/model.dart (doc comment on joinUrl only)
       packages/ics_core/lib/ics_core.dart
READS: packages/ics_core/** ; plan §1, §3

CONTEXT: §1 facts (services, order, recognised links, wrappers, HTML); §3 rows MeetingService,
  meetingServiceOf, extractJoinUrl, extractTeamsJoinUrl (removed), X-GOOGLE-CONFERENCE (Gate 0 decision pasted here).

DOES:
  1. Move the Teams finder into meeting_links.dart and widen it to the four services as §1 says, one
     regex pair (plain, percent-encoded) per service. Keep today's trailing-punctuation trim, and stop
     a link at < " ' and whitespace.
  2. Add MeetingService and meetingServiceOf; export them and extractJoinUrl; drop extractTeamsJoinUrl
     and its export. event_fields.dart keeps its other functions.
  3. vevent.dart calls extractJoinUrl(description, location, conference: <X-GOOGLE-CONFERENCE value
     if Gate 0 kept it, else omitted>).
  4. Update model.dart's joinUrl doc comment to name the four services.

ACCEPTANCE (run it, paste the real output):
  cd packages/ics_core; dart analyze                    -> No issues found!
  cd packages/ics_core; dart test test/event_fields_test.dart  -> fails only where it calls the removed
                                                            extractTeamsJoinUrl (T1 moves those tests)
  git -C <WORKDIR> status --short                       -> only the OWNS files

NEVER: change lib/ or android/; write tests (T1 does); log anything.
```

#### J2: Name the service in Kotlin

```
AGENT:   dev-worker
TASK:    plan-7-kotlin
SKILL:   none
WORKDIR: C:\Projects\tminus\.claude\worktrees\plan-7-meeting-links

OWNS:  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/MeetingService.kt (new)
       android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/AlertText.kt
       android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/JoinActivity.kt (doc comment only)
READS: android/app/src/main/** ; plan §1, §3

CONTEXT: §1 facts (recognised links, service names, the where text); §3 rows MeetingService (Kotlin),
  AlertText.where. The link has already been found and decoded by Dart; Kotlin only names its service
  from the host and path. Mirror meetingServiceOf's rules exactly.

DOES:
  1. MeetingService.kt with of(url) as §3 says; https only, case-insensitive host.
  2. AlertText.where uses MeetingService.of(e.joinUrl)?.label. A link of no known service (not
     expected, but possible from an older plan) still shows nothing extra, as no link does today.
  3. JoinActivity's comment says the service's app opens the link when installed, otherwise the browser.

ACCEPTANCE:
  cd android; .\gradlew.bat :app:compileDebugUnitTestKotlin -q   -> BUILD SUCCESSFUL
  git -C <WORKDIR> status --short                                 -> only the OWNS files

NEVER: change EngineJson, EngineModel or the channel; write tests (T2 does); log a link.
```

#### T1: ics_core tests for the finder

```
AGENT:   dev-worker (test author)
TASK:    plan-7-links
OWNS:  packages/ics_core/test/meeting_links_test.dart (new)
       packages/ics_core/test/event_fields_test.dart
       packages/ics_core/test/vevent_test.dart
       packages/ics_core/test/expand_single_test.dart
       packages/ics_core/test/fixtures/meeting_links.ics (new; invented ids, CRLF lines like the other fixtures)
READS: acceptance criteria and CONTEXT only, not meeting_links.dart, event_fields.dart or vevent.dart
CONTEXT: §1 facts; §3 rows MeetingService, meetingServiceOf, extractJoinUrl and the shared test table; §4 AC1-AC5.
DOES: write AC1-AC5. Move the existing extractTeamsJoinUrl tests to extractJoinUrl with every old expectation kept (AC4).
ACCEPTANCE: cd packages/ics_core; dart analyze -> No issues found!  (a compile check, not a test run)
```

#### T2: Kotlin tests for the service name

```
AGENT:   dev-worker (test author)
TASK:    plan-7-kotlin
OWNS:  android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/MeetingServiceTest.kt (new)
       android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/AlertTextTest.kt
       android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/NotificationFactoryTest.kt
       android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/AlarmScreenModelTest.kt
READS: acceptance criteria and CONTEXT only, not MeetingService.kt or AlertText.kt
CONTEXT: §1 facts; §3 rows MeetingService (Kotlin), AlertText.where, the shared test table (as decoded links; Kotlin never sees wrappers, so wrapped rows use their decoded form); §4 AC6-AC7.
DOES: write AC6-AC7; keep every existing Teams expectation.
ACCEPTANCE: cd android; .\gradlew.bat :app:compileDebugUnitTestKotlin -q -> BUILD SUCCESSFUL
```

**Wave 1 close** (through scouts):
- `dart analyze` and `dart test` in `packages/ics_core` -> all passed.
- `.\gradlew.bat :app:testDebugUnitTest --tests "io.github.fifothehein.tminus.engine.*"` -> 0 failures.
- `flutter analyze` is expected to fail on `occurrence_mapping.dart` (the removed `extractTeamsJoinUrl`) until J3. That is recorded, not fixed here.
- Review: `review-worker` on the wave diff; `deep-review`: none.
- Negative controls: each one the reviewer names, at least one per service regex, run by the test runner.
- Commit J1+T1 and J2+T2 as two commits.

### Wave 2: the app's texts (Dart)

Implementation first: J3. Then T3.

#### J3: Service names in the app

```
AGENT:   dev-worker
TASK:    plan-7-app
OWNS:  lib/core/sources/occurrence_mapping.dart
       lib/core/rules/rules_engine.dart
       lib/core/platform/ui_platform.dart (doc comment only)
       lib/core/sources/fast_alarms.dart (doc comment only; the debug Teams meeting stays)
       lib/features/agenda/agenda_model.dart
       lib/features/agenda/agenda_widgets.dart
       lib/features/agenda/event_sheet.dart
       lib/features/agenda/why_text.dart
       lib/features/alerts/alerts_screen.dart
       lib/features/alerts/rule_editor_screen.dart
       lib/features/alerts/rule_text.dart
       lib/features/common/alert_chips.dart
       lib/features/token_preview/token_preview_screen.dart
READS: lib/** ; packages/ics_core/lib/ics_core.dart (exports only); plan §1, §3
CONTEXT: §1 texts table; §3 rows extractJoinUrl, meetingServiceOf, MeetingService, AgendaItem.service, MeetingBadge, Join button text.
DOES: as the §1 texts table says. occurrence_mapping calls extractJoinUrl(i.description, i.location). `hasTeams` and `TeamsBadge` are replaced by `service` and `MeetingBadge`; rename local `teams` variables in rule_editor_screen to `linkRule`.
ACCEPTANCE: flutter analyze -> No issues found! (test files may still name hasTeams/TeamsBadge; analyze reports them, T3 fixes them, and the scout lists them)
            git -C <WORKDIR> status --short -> only the OWNS files
NEVER: touch lib/core/model/alert.dart or planned_alert.dart; dart format outside OWNS.
```

#### T3: App tests

```
AGENT:   dev-worker (test author)
TASK:    plan-7-app
OWNS:  test/core/sources/occurrence_mapping_test.dart, test/core/rules/rules_engine_test.dart,
       test/core/model/keyword_rule_test.dart, test/features/agenda/agenda_model_test.dart,
       test/features/agenda/agenda_screen_test.dart, test/features/agenda/event_sheet_test.dart,
       test/features/agenda/why_text_test.dart, test/features/alerts/alerts_screen_test.dart,
       test/features/alerts/rule_editor_test.dart, test/features/alerts/rule_text_test.dart
READS: acceptance criteria and CONTEXT only, not the J3 OWNS files
CONTEXT: §1 texts table; §3 rows AgendaItem.service, MeetingBadge, Join button text; §4 AC8-AC10.
DOES: write AC8-AC10; update the strings §1 changes; keep every Teams case.
ACCEPTANCE: flutter analyze -> No issues found!
```

**Wave 2 close**: `flutter analyze` clean; full `flutter test` (shared infrastructure changed: ics_core's export); review; negative controls; commit J3+T3.

### Wave 3: docs and store text

#### J4: Docs

```
AGENT:   dev-worker
TASK:    plan-7-docs
OWNS:  docs/superpowers/specs/2026-10-06-tminus-design.md (§5 link extraction, §6 Join, §12.3 note, §13 merge row wording),
       docs/play/listing.md, docs/privacy.md, docs/index.md, docs/design-brief.md, README.md,
       docs/superpowers/plans/2026-10-06-tminus-roadmap.md (a Plan 7 row)
READS: everything; plan §1, §5, and the Gate 0 evidence (pasted)
DOES:
  - Say "Teams, Google Meet, Zoom or Webex link" where the docs say "Teams link", with Gate 0's phone limit if any.
  - listing.md: one bullet in ADD YOUR CALENDARS. Recount the full description (limit 4000) and the claims table. Add Zoom, Webex and Google Meet to the trademark paragraph, with plain wording.
  - privacy.md: the meeting fields read, and that Join opens the service's app or browser. This page is public on Pages once merged.
  - README: the listing bullet, verbatim from listing.md (R49 style).
ACCEPTANCE: flutter test test/no_em_dash_test.dart test/app/pages_config_test.dart test/app/links_test.dart -> all passed
            git -C <WORKDIR> status --short -> only the OWNS files
NEVER: claim phone-calendar Meet support Gate 0 did not show.
```

**Wave 3 close**: review-worker reads every changed sentence against the code at HEAD; commit.

### Wave 4: on a device (scout)

- A release build on the Pixel_9 emulator (`-gpu swiftshader_indirect`), with a local-http fixture feed holding one meeting per service (invented links).
- Agenda badges, event sheet Join texts, heads-up and alarm `where` text.
- Join on a Zoom and a Meet meeting starts an `ACTION_VIEW` for the link (`dumpsys activity` intent data, scrubbed in the report), on both the event sheet and the alarm screen.
- Screenshots in the scratchpad, not in git.
- ACCEPTANCE: one PASS or FAIL line per check; any FAIL becomes a fix job.

## 7. Orchestrator-only steps

Each waits for the user's go.

- Booking: report-only. `TASK:` lines are labels; nothing is written anywhere.
- Overhead task: none, reported unbooked.
- Push (check `@{u}`, explicit refspec) and the PR to `main`, with Gate 0's findings and Wave 4's results. No Claude attribution.
- After the merge: version `1.0.2+3`, a release bundle, upload to internal testing (the user uploads it; the browser tool caps uploads at 10 MB), and the store text from listing.md sent for review in Play Console.

## 8. Bookmark: the orchestrator edits this section only

Reviewer: (none yet)

### Steps

| Step | State | Evidence | Commit |
|-|-|-|-|
| Setup | todo | | |
| W0.1 | todo | | |
| W0.2 | todo | | |
| Gate 0 | todo | | |
| J1 | todo | | |
| J2 | todo | | |
| T1 | todo | | |
| T2 | todo | | |
| W1 close | todo | | |
| J3 | todo | | |
| T3 | todo | | |
| W2 close | todo | | |
| J4 | todo | | |
| W3 close | todo | | |
| W4 | todo | | |
| Push and PR | todo | | |
| 1.0.2 release | todo | | |

### Sessions

| Session | Started | Ended | Check / note |
|-|-|-|-|
| plan | 2026-11-19T23:16:12+0200 | | Written in "tminus-59 · Plan 6 play readiness build" (Opus 5.5, effort medium; the skill asks for high, recorded, not switched) |

### Time log

| Job | Task | Agent id | Dispatched | Reported | Checked | Worker ms | Committed |
|-|-|-|-|-|-|-|-|

### Booked

| Task | Clock | Booked h | Last booking |
|-|-|-|-|

Decisions taken (each overturnable: say so and the next session acts on it):
- plan: the earliest link in a text wins, and Google's conference property comes first if Gate 0 keeps it. The first link in an invite is the organiser's.
- plan: the rule texts change to "meeting link" instead of listing four services, to stay short in the rule list.

Stopped at: plan written, not run. Next: Setup.
