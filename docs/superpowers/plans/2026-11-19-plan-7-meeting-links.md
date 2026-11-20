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
- **The user's own Outlook feed** (checked 2026-11-19, read in the session, raw file only in the git-ignored `packages/ics_core/test/fixtures/private/`): 608 events; 502 hold a Teams link, 65 a Meet link, 1 a Zoom link, none a Webex link. All 65 Meet events are Google invites accepted into Outlook. Every one has the plain link `https://meet.google.com/<code>` as its whole `LOCATION`. Their `DESCRIPTION` holds it only inside Outlook Safe Links wrappers, as `https://meet.google.com/<code>?hs=224`, plus a `https://tel.meet/<code>?pin=...` "more phone numbers" link, which is not a join link. Five also have a plain link in `DESCRIPTION`. The description also shows the link as bare text without `https://` (`meet.google.com/<code>`), each time followed by its Safe Links wrapper; §1's `https`-only rule ignores the bare text, and the wrapper right after it gives the same link. The one Zoom event is a meeting the user declined (`Declined:` title, empty `LOCATION`), with its link plain and Safe-Links-wrapped in `DESCRIPTION`. So there is no real accepted Zoom or Webex invite to test against, and those tests rely on invented links in the published shapes. Today none of these 66 meetings gets a Join button.
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

Reviewer: a4e00dec7f995483f (review-worker, run 1)

### Steps

| Step | State | Evidence | Commit |
|-|-|-|-|
| Setup | done | branch claude/plan-7-meeting-links-2ec46f at 0b9e9d0 (origin/main + 3 plan-only commits); `@{u}` unset; gradle files present. Baseline: analyze "No issues found!"; flutter test +1266 "All tests passed!"; ics_core dart test +157 "All tests passed!"; gradle testDebugUnitTest BUILD SUCCESSFUL (79 of 84 tasks up to date, so test count not seen) | |
| W0.1 | done | Google secret iCal feed (address given by the user in chat, not recorded) at private/google-feed.ics, git-ignored (check-ignore .gitignore:51). 339 VEVENTs; Meet 246, Zoom 1, Webex 1 (bare text only), Teams 16. Meet: `X-GOOGLE-CONFERENCE` in 246/246, each value exactly one `https://meet.google.com/<l>-<l>-<l>`; `DESCRIPTION` plain in 246/246, no query, followed by an ICS-escaped `\n`; `LOCATION` never. Next to Meet: `tel.meet` (234), `support.google.com` (246). Zoom: `<sub>.zoom.us` only, `/j/<digits>` plain and in `href=`, other non-join paths beside it, query names `pwd` and others, one link followed by an ICS-escaped `\;`. Teams: `/l/meetup-join/` and `/meet/` on `teams.microsoft.com` (today's forms) in 5 events; 13 events hold only Mimecast-rewritten links (`url.za.m.mimecastprotect.com/...?domain=teams.microsoft.com`), where the Teams link itself is not in the text. | |
| W0.1b | done | Second Google feed (a colleague's, shared with consent; address not recorded) at private/google-feed-2.ics, git-ignored. 14953 VEVENTs: Meet 8123, Zoom 1432, Webex 62, Teams 578. Meet: `X-GOOGLE-CONFERENCE` 8121 (the other 56 values are old `hangouts.google.com`/`plus.google.com` links), DESCRIPTION plain, never a query, first link clean in 8121/8123. Zoom: `zoom.us` and `<sub>.zoom.us`, `/j/` 2376, `/w/` 4; non-join paths beside them (`/addon/invitation` 1076, `/hc/` 76, `/u/` 38, `/s/` 1); 1455 Zoom links sit inside Google redirects as `url?q=https://<sub>.zoom.us/j/<d>?pwd%3D...&sa=D...` (inner link plain, its `=` encoded, ends at `&`); first Zoom link in DESCRIPTION clean in 1339/1344 events; LOCATION is exactly the Zoom link in 332. Webex: `j.php?MTID=` 3, `/join/` 1; 62 `webex.com/msteams?confid=...` (Webex-from-Teams links in Teams invites, not Webex joins); 153 host-only mentions. Teams: `/l/meetup-join/` in 562 events, `/meet/<digits>` on teams.microsoft.com 23 and teams.live.com 6; 192 inside Google `url?q=` redirects; Mimecast wrappers in 7 events. No `&amp;` anywhere. | |
| W0.2 | skipped | user: phone "Not now, carry on" (2026-11-19). Phone Meet support recorded as unknown | |
| Gate 0 | done | 2026-11-19T23:42:42+0200. Decisions below (run 1, Gate 0) | |
| J1 | done (0b27fb1) | reviewed clean; D1-D19 caught; checked (with fix C2+C5): ics_core `dart analyze` issues only the 12 removed-function calls in T1's event_fields_test.dart; scrub_feed_test +4 all passed; diff only J1 OWNS + tool/scrub_feed.dart; no logging, no U+2014; model.dart doc comment only; main checkout clean. Parity with J2's Kotlin rules compared by the orchestrator and the reviewer: same decisions on fragment, port, bare webex.com, MTID first, case, trailing slash | 0b27fb1 |
| J2 | done | checked with fix C3 (`compileDebugUnitTestKotlin -x compileFlutterBuildDebug -q` exit 0, C4; android diff only the 3 OWNS files; main checkout clean; JoinActivity.kt:40 logs only the exception's class name, existing line); reviewed, no blocker; controls N1-N19 all caught | 5396892 |
| T1 | done (0b27fb1) | +353 pass; D1-D19 caught; ics_core `dart analyze` "No issues found!"; test diff: event_fields_test renamed calls + the C6 example only; teams_links.ics one line (C6); new meeting_links_test.dart and fixtures/meeting_links.ics (15 VEVENTs, CRLF); no U+2014, no real-data strings; main checkout clean | |
| T2 | done | compile exit 0 (C4); test diff additive only plus new MeetingServiceTest.kt (16 tests after the review fix); engine 255 tests pass; every control caught | 5396892 |
| W1 close | done | ics_core `dart test` +353 all passed; ics_core `dart analyze` clean; Kotlin engine 255 tests 0 failures (`-x compileFlutterBuildDebug`, C4); `flutter analyze` fails only on occurrence_mapping.dart until J3 (expected, recorded); review clean after one BLOCK (T1 row) settled; controls N1-N19 and D1-D19 all caught. Real-data compare of HEAD's `extractTeamsJoinUrl` with the new `extractJoinUrl` over the three private feeds (counts only, scripts deleted): 0 exceptions; every link found is named by `meetingServiceOf`; no old Teams link lost (C = 0). Outlook 608 events: Teams 501, Meet 65, Zoom 1; 1 old Teams result now Meet (the Meet link comes first in the text). Google (user) 339: Teams 3 unchanged, Meet 246, Zoom 1. Google 2, 14953: Teams 557 of 562 unchanged, 5 more found (teams.live.com `/meet/`), Meet 8121, Zoom 1418, Webex 2; 3 old Teams results now Meet (Google's conference property holds an auto-added Meet link), 2 give a different Teams link form (a longer Safe Links copy with an extra parameter, and a double-encoded copy replaced by the earlier clean link). Slowest event 27 ms. | 5396892 (Kotlin), 0b27fb1 (Dart) |
| J3 | done (c245e68) | reviewed clean; E1-E17 caught. Check: `flutter analyze`: 4 issues, all in T3's test files (hasTeams, TeamsBadge); lib diff only the 13 OWNS files (68+/33-), `diff --check` clean, lib/core/model untouched, no logging or U+2014 added; every old-string hit in test/ is in T3's OWNS; main checkout clean | |
| T3 | done (c245e68) | reviewed clean; E1-E17 caught (E10 as E10b); full flutter test +1294; `flutter analyze` "No issues found!"; test diff only the 10 OWNS files (479+/17-), `diff --check` clean; no U+2014 or real-data strings; no old strings left in test/; main checkout clean | |
| W2 close | done | `flutter analyze` clean; full `flutter test` +1294 all passed; full Gradle `:app:testDebugUnitTest` (no -x) 367 tests, 0 failures; ics_core unchanged since W1 (+353); review clean (J3, T3); controls E1-E17 all caught (E10 rewritten as E10b to compile); 304 sync re-expands the stored body, so cached meetings get new links on the first sync | c245e68 |
| J4 | done (390ef1b) | reviewed clean; doc-guard tests +7 passed (J4's run); listing 1914 -> 2147 of 4000 (recounted by the reviewer); README bullets and trademark paragraph identical to listing.md; every claim checked against the code; no phone Meet claim; privacy date 20 November 2026. Open (user's call): "Teams meetings come in through Outlook." could become "...through your calendar, for example Outlook." | |
| W3 close | done | review read every changed sentence against the code: clean; doc-guard tests +7 (J4's run; rerun in the final full suite) | 390ef1b |
| W4 | done | Pixel_9 AVD (API 36, `-gpu swiftshader_indirect`), RELEASE build of 390ef1b (signed with the upload key: this worktree has android/key.properties), a local-http fixture (10.0.2.2:8765) with one invented meeting per service plus an Outlook-style Meet. C1 PASS agenda badges Teams, Google Meet, Zoom, Webex, Google Meet. C2 PASS sheet Join texts; Outlook Meet's link location not shown; "Boardroom 2" and "Microsoft Teams Meeting" shown. C3 PASS Join on Zoom and Meet sheets starts ACTION_VIEW from the app (https, example.zoom.us /j/..., meet.google.com), Chrome opens it. C4 PASS alarm screen and notification "03:40-04:05 · Zoom", "04:40-05:05 · Google Meet" (no URL), Teams "02:40-03:05 · Teams". C5 PASS Join on the Zoom alarm screen starts ACTION_VIEW. C6 PASS no link or title in the app process's logcat. Not captured: heads-up text for Meet/Webex (alarm notifications were). Clock reset; emulator left running. | n/a |
| C7 (text first) | done | J1 fix C7 checked (loop order + doc comments only); T1 fix C7 checked (ics_core +385; fixture now 16 VEVENTs); J4 fix C7 checked (spec:134, roadmap:111). Test run: ics_core +385, `flutter analyze` clean, full `flutter test` +1294, pages_config_test 2 passed alone. Review clean. Controls F1-F4 all caught, none survived. Real-data effect: 15 past events change (3 Meet -> Teams, 12 Meet -> Zoom) | 6463375 |
| C8 (store text) | done | listing.md and README.md say "through your calendar, for example Outlook."; count 2174 of 4000 (recounted); README and listing bullets identical (19); listing's reviewer note matched; review clean | 34e617f |
| Push and PR | done | user's go 2026-11-20 ("Push and open PR"); `@{u}` was unset, origin/main an ancestor; pushed with an explicit refspec; PR https://github.com/FifoTheHein/tminus/pull/30 opened 2026-11-20T08:31:47+0200 against main; the repo has no CI (no .github/workflows) | ca6f280 |
| 1.0.2 release | todo | | |

### Sessions

| Session | Started | Ended | Check / note |
|-|-|-|-|
| plan | 2026-11-19T23:16:12+0200 | | Written in "tminus-59 · Plan 6 play readiness build" (Opus 5.5, effort medium; the skill asks for high, recorded, not switched) |
| run 1, C7 | 2026-11-20T07:03:57+0200 | 2026-11-20T07:43:19+0200 | Same session, after the user overturned the hybrid-invite order (C7). |
| run 1 | 2026-11-19T23:27:55+0200 | 2026-11-20T02:52:35+0200 | "Plan 7: Meet, Zoom and Webex join links" (Opus 5.5, effort high). Plan check passed (W0 and Setup are read-only scout jobs with no OWNS; J4 has no test author, so it goes out with the implementations). |

### Time log

| Job | Task | Agent id | Dispatched | Reported | Checked | Worker ms | Committed |
|-|-|-|-|-|-|-|-|
| Setup | overhead | a22e5919a4d715701 | 2026-11-19T23:28:21+0200 | 2026-11-19T23:46:32+0200 | 2026-11-19T23:46:32+0200 | 1090680 | n/a |
| J1 | plan-7-links | a38c6c8e425511f98 | 2026-11-19T23:43:40+0200 | 2026-11-20T00:07:23+0200 (partial: scrub_feed.dart unowned) | 2026-11-20T00:26:17+0200 (with fix C2+C5) | 1391018 | |
| J1 fix C2+C5 | plan-7-links | a38c6c8e425511f98 | 2026-11-20T00:08:30+0200 | 2026-11-20T00:25:00+0200 | | 953734 | |
| J1 check | overhead | adf13b0fbd9a5f6d2 | 2026-11-20T00:25:30+0200 | 2026-11-20T00:26:17+0200 | 2026-11-20T00:26:17+0200 | 138422 | n/a |
| T1 | plan-7-links | a7bcf7d8d7d158b3b | 2026-11-20T00:27:00+0200 | 2026-11-20T00:51:00+0200 (discloses a usage grep that showed 3 comment lines of meeting_links.dart; file not opened) | 2026-11-20T00:52:29+0200 | 1406629 | |
| T1 check | overhead | adf13b0fbd9a5f6d2 | 2026-11-20T00:51:30+0200 | 2026-11-20T00:52:29+0200 | 2026-11-20T00:52:29+0200 | 112035 | n/a |
| W1 review (Dart part) | overhead | a4e00dec7f995483f | 2026-11-20T00:52:40+0200 | 2026-11-20T00:57:00+0200: BLOCK T1 `_glued` row teams.microsoft.com (settled: row dropped); notes only otherwise; 19 controls D1-D19 named | | 246094 | |
| T1 fix (drop glued Teams row) | plan-7-links | a7bcf7d8d7d158b3b | 2026-11-20T00:58:00+0200 | 2026-11-20T00:59:30+0200 | 2026-11-20T01:00:30+0200 (analyze clean; row gone; CRLF) | 100923 | |
| W1 real-data compare (old vs new finder, counts only) | overhead | a6cfe9dd663a7a847 | 2026-11-20T00:58:30+0200 | 2026-11-20T01:06:00+0200: see W1 close evidence | | 130358 | n/a |
| J2 | plan-7-kotlin | a87dba8eadfb7b075 | 2026-11-19T23:43:40+0200 | 2026-11-19T23:57:22+0200 | 2026-11-20T00:02:49+0200 | 817009 | 5396892 |
| J2 check | overhead | adf13b0fbd9a5f6d2 | 2026-11-19T23:57:40+0200 | 2026-11-20T00:02:49+0200 | 2026-11-20T00:02:49+0200 | 311052 | n/a |
| T2 | plan-7-kotlin | a634fcdc50ce4011d | 2026-11-20T00:04:30+0200 | 2026-11-20T00:15:00+0200 | 2026-11-20T00:15:16+0200 | 650692 | |
| W1 test run 1 (Kotlin engine) | overhead | a22e5919a4d715701 | 2026-11-20T00:15:30+0200 | 2026-11-20T00:20:30+0200: BUILD SUCCESSFUL, engine 253 tests, 0 failures (MeetingServiceTest 14, AlertTextTest 12, NotificationFactoryTest 17, AlarmScreenModelTest 9) | | | |
| W1 review (Kotlin part) | overhead | a4e00dec7f995483f | 2026-11-20T00:16:00+0200 | 2026-11-20T00:19:00+0200: no blocker; WARN j.php MTID untested (to T2); 19 controls named | | 178598 | |
| T2 fix (review WARN + parity rows) | plan-7-kotlin | a634fcdc50ce4011d | 2026-11-20T00:19:30+0200 | 2026-11-20T00:21:30+0200 | 2026-11-20T00:22:33+0200 (compile exit 0; 16 @Test in MeetingServiceTest) | 169185 | |
| W1 test run 2 + controls N1-N19 (Kotlin) | overhead | a22e5919a4d715701 | 2026-11-20T00:22:40+0200 | 2026-11-20T01:10:00+0200: engine 255 tests 0 failures (MeetingServiceTest 16); N1-N19 each failed its expected tests (N11 now fails after T2's fix); none survived; N19 (AlertText at HEAD) keeps the old Teams test passing; restores hash-verified | | 2848210 | |
| W1 Kotlin verify + commit | overhead | adf13b0fbd9a5f6d2 | 2026-11-20T01:10:30+0200 | 2026-11-20T01:10:58+0200 | 2026-11-20T01:10:58+0200 (diff and hashes as after the controls) | 29138 | 5396892 |
| W1 Dart test run + controls D1-D19 | overhead | a22e5919a4d715701 | 2026-11-20T01:11:00+0200 | before 2026-11-20T01:19:50+0200 (not stamped on arrival): ics_core `dart test` +353 all passed; D1-D19 each failed its expected tests (plus extras); none survived; restores hash-verified | | | |
| W1 re-review (T1 fix + results) | overhead | a4e00dec7f995483f | before 2026-11-20T01:19:50+0200 | clean: BLOCK resolved, nothing new | | 15791 | |
| W1 Dart verify + commit | overhead | adf13b0fbd9a5f6d2 | before 2026-11-20T01:19:50+0200 | 2026-11-20T01:19:50+0200 | 2026-11-20T01:19:50+0200 (hashes and diff as after the controls; no private path staged) | 20659 | 0b27fb1 |
| J3 | plan-7-app | a8700cd91e406fe9c | 2026-11-20T01:19:00+0200 | before 2026-11-20T01:30:00+0200 (not stamped on arrival) | 2026-11-20T01:31:38+0200 | 609535 | |
| J3 check | overhead | adf13b0fbd9a5f6d2 | ~2026-11-20T01:30:00+0200 | 2026-11-20T01:31:38+0200 | 2026-11-20T01:31:38+0200 | 65339 | n/a |
| J4 | plan-7-docs | a4a8d815dd29f0d9d | ~2026-11-20T01:30:30+0200 (not stamped) | before 2026-11-20T01:50:52+0200 (not stamped; doc-guard tests +7 all passed; listing 1914 -> 2147 chars of 4000) | | | |
| J4 fix (privacy date) | plan-7-docs | a4a8d815dd29f0d9d | before 2026-11-20T01:50:52+0200 (not stamped) | before 2026-11-20T01:50:52+0200 (not stamped; date only; LF kept) | | | |
| W3 review (J4) | overhead | a4e00dec7f995483f | before 2026-11-20T01:50:52+0200 (not stamped) | clean (no BLOCK/WARN); one optional store-text wording for the user | | 68948 | |
| W2 review (T3) | overhead | a4e00dec7f995483f | ~2026-11-20T01:51:30+0200 | 2026-11-20T01:53:22+0200: clean (no BLOCK/WARN); E1-E16 mapped to real names; E17 added (location trim); note: rule_editor_test's `teams.example` fixture is an unrecognised link, harmless while `hasJoinLink` is `joinUrl != null` (left as is) | | 153536 | |
| T3 | plan-7-app | ac780763c477b2693 | 2026-11-20T01:31:45+0200 | before 2026-11-20T01:50:52+0200 (not stamped; discloses two greps that printed 4 lines of J3 files: the place icon row, the MeetingBadge declaration, the service getter, one usage) | | | |
| T3 check | overhead | adf13b0fbd9a5f6d2 | ~2026-11-20T01:48:00+0200 (not stamped) | 2026-11-20T01:50:52+0200 | 2026-11-20T01:50:52+0200 | 61376 | n/a |
| W2 test run + controls E1-E16 + full Gradle | overhead | a22e5919a4d715701 | 2026-11-20T01:51:00+0200 | 2026-11-20T02:09:43+0200: full `flutter test` +1294 all passed; E1-E9, E11-E16 each failed tests (none survived); E10 did not compile (re-sent as E10b); full Gradle `testDebugUnitTest` (no -x) 367 tests 0 failures; restores hash-verified | | 1122606 | |
| W2 controls E10b + E17 | overhead | a22e5919a4d715701 | 2026-11-20T02:09:50+0200 | before 2026-11-20T02:12:42+0200: E10b and E17 each failed their expected tests; none survived; hash restored | | 1236750 | |
| W2 + W3 verify and commits | overhead | adf13b0fbd9a5f6d2 | before 2026-11-20T02:12:42+0200 | 2026-11-20T02:12:42+0200 | 2026-11-20T02:12:42+0200 (all nine hashes as after the controls; lib 13 files 68+/33-, test 10 files 479+/17-) | 29337 | c245e68, 390ef1b |
| W4 emulator check | overhead | aa9db1a66606d498b | ~2026-11-20T02:11:30+0200 (not stamped) | 2026-11-20T02:52:07+0200 | 2026-11-20T02:52:07+0200 | 2355482 | n/a |
| W2 review (J3) | overhead | a4e00dec7f995483f | ~2026-11-20T01:32:00+0200 | clean (no BLOCK/WARN); explanation never persisted (verified); 16 controls E1-E16 named | | 76033 | |
| 304 re-expansion trace (review's open question) | overhead | a8bb468400f85ff7a | ~2026-11-20T01:34:00+0200 | answered: re-expanded every sync. A 304 re-runs `expandIcs` on the stored body (ics_feed_source.dart:130-142) and `replaceForSource` replaces the rows (sync_service.dart:454-463); phone calendars are re-read every fetching run. Only an EmptyFeedGuard keep leaves old rows. So existing meetings get their new links on the first sync after the update. | | | n/a |
| J2 fix C3 | plan-7-kotlin | a87dba8eadfb7b075 | 2026-11-20T00:04:30+0200 | 2026-11-20T00:06:00+0200 | 2026-11-20T00:07:45+0200 | 208531 | |
| W0.1b (second Google feed, given by the user in chat) | plan-7-data | aca896f9e65ecba6f | 2026-11-19T23:52:37+0200 | 2026-11-20T00:00:32+0200 (first try refused by the permission check; the orchestrator downloaded it after the user and the feed's owner approved; then two analysis runs) | 2026-11-20T00:00:32+0200 | 311816 | n/a |
| J1 fix C7 (text first) | plan-7-links | a7369783341caaf25 | 2026-11-20T07:04:30+0200 | 2026-11-20T07:08:36+0200 (analyze clean; loop order + 2 doc comments) | 2026-11-20T07:09:43+0200 | 240335 | |
| J1 fix C7 check | overhead | a05a8701c98e0efac | 2026-11-20T07:08:40+0200 | 2026-11-20T07:09:43+0200 (analyze clean; only the loop list and doc comments; no logging or U+2014; main checkout clean) | 2026-11-20T07:09:43+0200 | 47313 | n/a |
| T1 fix C7 (text-first tests) | plan-7-links | a7c750b57bf802c3e | 2026-11-20T07:09:43+0200 | 2026-11-20T07:29:57+0200 (ics_core +385; meeting_links group rewritten, 3 vevent and 2 expand_single tests; fixture 16 VEVENTs: google-conference-first renamed google-text-first, google-pasted-teams added; its own scratch run against HEAD's finder: 34 failures, all new-order tests) | 2026-11-20T07:31:26+0200 | 1200809 | |
| T1 fix C7 check | overhead | a28100d2102141aa3 | 2026-11-20T07:30:00+0200 | 2026-11-20T07:31:26+0200 (analyze clean; the 3 test files +267 passed; status exactly the expected 11 files, none untracked; fixture diff as reported; CRLF kept; no U+2014 or real-data strings; main checkout clean) | 2026-11-20T07:31:26+0200 | 74644 | n/a |
| C7/C8 test run | overhead | a22e5919a4d715701 | 2026-11-20T07:31:26+0200 | 2026-11-20T07:39:09+0200: ics_core `dart test` +385 all passed; `flutter analyze` "No issues found!"; full `flutter test` +1294 all passed (no_em_dash_test seen; pages_config_test not seen in the compact log, run alone next) | | 455388 | n/a |
| C7 pages_config run + controls F1-F4 | overhead | a22e5919a4d715701 | 2026-11-20T07:39:09+0200 | 2026-11-20T07:42:11+0200: pages_config_test alone 2 passed; F1 caught (34 failed), F2 caught (15), F3 caught (9), F4 caught (3); none survived; restores hash-verified; final `dart test` +385 | | 635218 (runner total) | n/a |
| C7 + C8 verify and commits | overhead | a04bb2fa88feb7bbe | 2026-11-20T07:42:30+0200 | 2026-11-20T07:43:19+0200 (11 files and both hashes as after the controls; author as the repo config, no trailer) | 2026-11-20T07:43:19+0200 | | 6463375, 34e617f |
| C7/C8 review | overhead | a4e00dec7f995483f | 2026-11-20T07:31:26+0200 | 2026-11-20T07:32:44+0200: clean (no BLOCK/WARN); only behaviour change is the order; app and Kotlin unaffected; no conference-first wording left outside this plan's §1/AC3 (superseded by C7); two tests whose names outlived text first are covered elsewhere (rename optional, left); controls F1-F4 named | | 66877 | n/a |
| J4 fix C7 (docs order) | plan-7-docs | a8850d9aad0c34265 | 2026-11-20T07:04:30+0200 | 2026-11-20T07:09:25+0200 (spec:134 and roadmap:111 only; no other doc states the order; flutter test left to the runner) | 2026-11-20T07:14:49+0200 | 291700 | |
| J4 fix C8 (store text) | plan-7-docs | a8850d9aad0c34265 | 2026-11-20T07:09:25+0200 | 2026-11-20T07:13:35+0200 (sentence in listing.md and README.md; count 2147 -> 2174; listing.md reviewer note at line ~135 brought in line, on the orchestrator's go) | 2026-11-20T07:14:49+0200 | 537506 (whole worker, C7 + C8) | |
| J4 fix C7 + C8 check | overhead | a59b313c9f4c175cc | 2026-11-20T07:13:35+0200 | 2026-11-20T07:14:49+0200 (diff only the 4 doc files' intended lines; listing recount 2174; README and listing 19 bullets identical; no U+2014 added; line endings kept; main checkout clean) | 2026-11-20T07:14:49+0200 | 71162 | n/a |
| W0.1 | plan-7-data | aca896f9e65ecba6f | 2026-11-19T23:36:13+0200 | 2026-11-19T23:42:30+0200 (with two follow-ups) | 2026-11-19T23:42:42+0200 (read-only survey; report is the evidence) | 364473 | n/a |

### Booked

| Task | Clock | Booked h | Last booking |
|-|-|-|-|

Decisions taken (each overturnable: say so and the next session acts on it):
- plan: the earliest link in a text wins, and Google's conference property comes first if Gate 0 keeps it. The first link in an invite is the organiser's.
- plan: the rule texts change to "meeting link" instead of listing four services, to stay short in the rule list.
- run 1 (from the session that started this run): WORKDIR is this run's own worktree, `C:\Projects\tminus\.claude\worktrees\plan-6-play-readiness-build-fe4abe`, on branch `claude/plan-7-meeting-links-2ec46f` cut from `claude/plan-7-meeting-links-plan` (0b9e9d0, which is `main` f84cc98 plus the three plan commits). It replaces the plan's `...\worktrees\plan-7-meeting-links` in every brief. Setup step 1 (worktree add) is skipped; steps 2-4 still run, and Setup's ACCEPTANCE "HEAD equals origin/main" reads "HEAD equals 0b9e9d0, whose only commits past origin/main touch this plan file".
- run 1: W0.1's Outlook half is answered by the Research section. The user's raw Outlook feed is at `<WORKDIR>\packages\ics_core\test\fixtures\private\outlook-feed.ics` (git-ignored, real data: never print values, never copy into git). W0.1 still needs Google's own export and W0.2 the user's phone; if the user cannot give them yet, Gate 0 is recorded with what is known (drop `X-GOOGLE-CONFERENCE`, phone Meet support documented as unknown) and Wave 1 goes on.
- run 1, Gate 0: **keep** the `conference:` parameter. `vevent.dart` passes the `X-GOOGLE-CONFERENCE` value as `conference:` (W0.1: present on every Google Meet event, always exactly the plain link).
- run 1, Gate 0: no §1 correction. Every join link the two real feeds hold is in a §1 form. The 13 Mimecast-rewritten Teams events carry only the host name in a `domain` query parameter, so no finder can recover their link; they stay without Join, as today (no work, and nothing to build: it would be guessing).
- run 1, Gate 0: Google's raw `DESCRIPTION` puts an ICS-escaped newline straight after the Meet link, and the Zoom link can be followed by an escaped `;`. T1's fixture `meeting_links.ics` copies both (with invented ids), so AC5 proves the link stops there after unescaping.
- run 1, Gate 0: W0.2 not run (user, 2026-11-19). J4's docs say phone calendars get a Meet link only when it is written in the event's description or location, and that an event made with Google's "Add Google Meet video conferencing" may not carry it on the phone (not checked). No reader job (§5).
- run 1, correction C1 (W0.1b): each service's link ends where its grammar ends. `/j/<digits>` stops at the first non-digit; a query is part of the link only when it starts with `?` right after the path. So `https://x.zoom.us/j/123&...` gives `https://x.zoom.us/j/123`. Teams keeps today's grammar (C2 aside).
- run 1, correction C2 (W0.1b): a plain link directly preceded by `q=` (Google's `https://www.google.com/url?q=https://...` redirect, inner link not percent-encoded) ends at the first `&`, and its percent-escapes are then decoded, so `...zoom.us/j/123?pwd%3Dabc&sa=D...` gives `...zoom.us/j/123?pwd=abc`. For all four services (1455 Zoom and 192 Teams such links in W0.1b; mostly after a clean link, but first in a few events).
- run 1, correction C3 (J2's report, Outlook Meet data): `AlertText.where` also skips a location that is itself a join link of the meeting's service (`MeetingService.of(location.trim()) == service`). Outlook Meet invites have the bare Meet link as LOCATION, and "Google Meet · https://meet..." would repeat it. Zoom's link location already contains "zoom". J3 applies the same rule wherever the app shows a location beside the service name.
- run 1, correction C4 (J2 check, reproduced by a scout): every Gradle task of `:app` compiles the Flutter app first (`compileFlutterBuildDebug`), which fails from J1 until J3 moves `occurrence_mapping.dart` off `extractTeamsJoinUrl`. Wave 1's Gradle checks therefore run with `-x compileFlutterBuildDebug`; the Wave 2 close runs the full Gradle suite without it.
- run 1, correction C5 (J1's report, reproduced by J1's analyze output): `packages/ics_core/tool/scrub_feed.dart` calls `extractTeamsJoinUrl` (lines 113 and 161) and was in no OWNS. It goes to J1's fix, keeping its Teams-only meaning: `meetingServiceOf(extractJoinUrl(...)) == MeetingService.teams`. The scrubber already replaces every description and location, so no Meet, Zoom or Webex text can leak into a fixture.
- run 1, correction C6 (J1's report): two old Teams tests used `https://zoom.us/j/1` as a "no link" example, which is now a real Zoom link (`event_fields_test.dart` "null when there is no Teams join link"; the `none` event of `fixtures/teams_links.ics`). Their meaning is "no join link gives null", so T1 changes that example to `https://zoom.us/download` (not a join link), and `packages/ics_core/test/fixtures/teams_links.ics` joins T1's OWNS for that one line.
- run 1, C1 clarified (J1's fix report): a `#fragment` right after the path is kept as part of the link (Kotlin's `of` ignores it, so both name the service; T2 pins `https://zoom.us/j/12345678901#success` -> Zoom). A word character glued to the end of a Zoom number, a Teams `/meet/` number or a Meet code (`/j/123abc`, `abc-defg-hijk`) gives no link rather than a cut one: cutting could link a different room. Both overturnable.
- run 1, W1 review BLOCK settled: "a Teams `/meet/` number" in the C1 clarification means the digit grammar of `teams.cloud.microsoft` and `teams.live.com` only. `teams.microsoft.com` keeps today's grammar (any path after `/meet/`), so `https://teams.microsoft.com/meet/3456789012345abc` stays a Teams link and T1 drops that `_glued` row. Narrowing it would change today's Teams behaviour (Review focus 5).
- run 1, kept after the real-data compare: §1's order stands for invites that hold both a Meet and a Teams link (4 events of about 15,900; 3 of them Google events whose conference property is a Meet link, likely auto-added by Google, with a Teams link in the text). They now get the Meet link. Raised to the user at the Wave 1 close; overturnable (the alternative: a Teams link in the text beats an auto-added conference Meet link). **Overturned by the user on 2026-11-20: see C7.**
- run 1, correction C7 (the user, 2026-11-20, after seeing the events): **text first**. `extractJoinUrl` searches DESCRIPTION, then LOCATION, then `X-GOOGLE-CONFERENCE`; inside one text the earliest link still wins. Google adds a Meet link to the conference property by itself, while the link in the text is the one the organiser wrote. Over the three private feeds this changes 15 events, all in the colleague's feed and all in the past: 3 Meet -> Teams (the three Google events above) and 12 Meet -> Zoom (2018-2021, Zoom link pasted into a Google event). The Outlook hybrid stays Meet (no conference property; its Meet link comes first in the text). Supersedes §1's order and AC3's "conference first".
- run 1, C8 (the user, 2026-11-20): the store text "Teams meetings come in through Outlook." becomes "Teams meetings come in through your calendar, for example Outlook." in docs/play/listing.md and README.md (kept identical), because Google feeds carry Teams meetings too. Goes to J4's worker after J4 fix C7, so two writers never hold docs at once.
- run 1, C3 for Teams (J3's report): C3 is service-agnostic, so a Teams meeting whose LOCATION is itself the bare Teams join link loses that raw-link place row on the event sheet (today it shows the URL). Kept, to match Kotlin's `where` and because a raw join link is not a place; a usual Outlook Teams location (`Microsoft Teams Meeting`) is unchanged. A narrow exception to Review focus 5, overturnable (J3's one-condition fix: `service != MeetingService.teams &&`).
- run 1, J4's report: docs/index.md stays unchanged (its one Teams line is still true; no new public claim). privacy.md's effective date moves to 20 November 2026, because the policy now names Google's conference property; the push/PR step moves it again if the merge is later. The spec header, roadmap Status block and README "Build status" change after the merge, as for Plan 6. J4 also widened spec §11's test list and roadmap §4's explanation example, both made false by this plan: kept.
- run 1: J4 also updates roadmap §2, which still lists `extractTeamsJoinUrl` as an `ics_core` export (J1's report).

Stopped at: Waves 0-4 built, checked, reviewed and committed (5396892, 0b27fb1, c245e68, 390ef1b); Wave 4 passed on the emulator. The user's C7 (text first) and C8 (store text) are built, checked, reviewed and committed (6463375, 34e617f); Wave 4 was not rerun for them (ics_core and docs only, no UI or Kotlin change). Pushed; PR https://github.com/FifoTheHein/tminus/pull/30 is open. Next: the user's review and merge; after the merge, the spec header, roadmap Status block and README "Build status", the privacy date if the merge is after 20 November 2026, then the 1.0.2 release steps (§7).

### Built differently from this plan

The code is authoritative; each entry is in "Decisions taken" above.
- WORKDIR was the run's own worktree `C:\Projects\tminus\.claude\worktrees\plan-6-play-readiness-build-fe4abe`, branch `claude/plan-7-meeting-links-2ec46f`, not `...\worktrees\plan-7-meeting-links`.
- Gate 0: a second Google feed (a colleague's, shared with consent) was surveyed as W0.1b; W0.2 (phone) was not run. `X-GOOGLE-CONFERENCE` is read, and (C7) searched last: DESCRIPTION, then LOCATION, then the conference property.
- C1/C2: each link ends where its own form ends; a plain link inside Google's `url?q=` redirect ends at `&` and is decoded once. A `#fragment` is kept; a word character glued to a number or Meet code gives no link. `teams.microsoft.com` keeps today's grammar.
- C3: a location that is itself the meeting's own join link is not shown, in Kotlin's `where` and on the event sheet, for every service including Teams.
- C4: Wave 1's Gradle checks ran with `-x compileFlutterBuildDebug`.
- C5/C6: `tool/scrub_feed.dart` moved to `extractJoinUrl` (Teams-only meaning kept); two old tests' "no link" example changed from `https://zoom.us/j/1` to `https://zoom.us/download`.
- J1 used one grammar per service plus a decode step instead of a regex pair per service. Kotlin's `MeetingService.of` is a hand-written parser, not a regex.
- J4 also widened spec §11 and roadmap §4; docs/index.md is unchanged; privacy.md's effective date is 20 November 2026.
- J4 ran alongside Wave 2 (no shared files, no test author).
- C7: the search order is DESCRIPTION, then LOCATION, then `X-GOOGLE-CONFERENCE` (the user overturned §1's conference-first order after seeing the hybrid invites). T1's fixture event `google-conference-first` is now `google-text-first`, and `google-pasted-teams` was added (16 VEVENTs).
- C8: the store text and README say Teams meetings come in "through your calendar, for example Outlook".
