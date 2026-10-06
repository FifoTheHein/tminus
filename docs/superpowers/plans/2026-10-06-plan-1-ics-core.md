# Plan 1: `ics_core` Implementation Plan

> **Execution (decided 2026-10-06): subagent-driven, using the orchestrator pattern.** Do not execute this plan inline. Run `/orchestrate` in plan mode on this plan to produce an orchestration plan (workers: `dev-worker`, `review-worker`, `deep-review`, `scout`), then run that orchestration plan with `/orchestrate <path>` in a fresh session. Each task here becomes one or more orchestrator jobs; its code and tests are the job's brief content. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `packages/ics_core`, a pure Dart package that turns ICS feed text into the event occurrences inside a time window, exactly as roadmap §2 defines `expandIcs()`, with per-event error isolation.

**Architecture:** The root `pubspec.yaml` becomes a Dart pub workspace containing `packages/ics_core`. The package is a pipeline of small units: unfold and tokenise content lines → build the component tree → parse values (dates, durations, RRULEs) → resolve time zones (CLDR Windows→IANA table, IANA, the feed's VTIMEZONE, then the device zone) → read event fields → expand each event in its own wall-clock zone and convert to UTC → filter to the window, apply EXDATE and RECURRENCE-ID overrides, sort. Only `expandIcs` and the roadmap §2 model types are public; everything else lives under `lib/src/`.

**Tech Stack:** Dart 3.13 (Flutter 3.47 SDK), `rrule` 0.2.18 (wall-clock recurrence expansion), `timezone` 0.11.1 (IANA database, `latest_all` variant), `test` 1.31.x, `lints` 6.x. Dart pub workspaces.

**Spec:** `docs/superpowers/specs/2026-10-06-tminus-design.md` (§5 "ics_core", §9, §10, §11, §12.3). **Binding contract:** `docs/superpowers/plans/2026-10-06-tminus-roadmap.md` §2 (public API, produced exactly). Read both before starting.

## Global Constraints

- `packages/ics_core` is pure Dart: no `flutter` or `flutter_test` dependency and no `package:flutter` import anywhere in it.
- Dart SDK constraint `^3.13.0` in both pubspecs (the app is on Flutter 3.47.0 / Dart 3.13.0).
- Root `pubspec.yaml` has `workspace: [packages/ics_core]`; the package has `resolution: workspace`. Always run `flutter pub get` **at the repo root**, never `dart pub get` inside the package.
- Dependency versions: `rrule: ^0.2.18`, `timezone: ^0.11.1`; dev: `test: ^1.31.1`, `lints: ^6.1.0`. Do not raise `test` to 1.32: the workspace shares one resolution and `flutter_test` pins `test_api` 0.7.12, which only `test` 1.31.1 accepts.
- The public API is roadmap §2, exactly: `IcsBusyStatus { free, tentative, busy, oof, unknown }`, `IcsWarning { tzFromVtimezone, tzFromDevice }`, `IcsOccurrence`, `IcsIssue`, `IcsResult`, `expandIcs(String icsText, {required DateTime windowStartUtc, required DateTime windowEndUtc, required String deviceZone})`, `IcsFormatException`. Same field names, types and meanings. `lib/ics_core.dart` exports nothing else.
- Window semantics: keep occurrences overlapping `[windowStartUtc, windowEndUtc)`. (The app's window is now − 1 h to now + 7 days, spec §5; tests pass explicit windows.)
- Spec §9: one bad VEVENT is skipped and reported; the rest of the feed still parses. Text with no `BEGIN:VCALENDAR` throws `IcsFormatException`.
- Spec §10: an ICS URL is a secret. Never write the user's feed URL into any file, commit message or log, and never commit the raw feed.
- Fixture `.ics` files: copy them byte for byte. Lines that start with a single space are folded continuations; do not trim or re-indent them.
- `dart analyze` in `packages/ics_core`, and `flutter analyze` plus `flutter test` at the repo root, must stay clean after every task.
- Commits: sentence-case imperative subject (like `Add T-Minus theme from the design system`), a short wrapped body, and the Co-Authored-By trailer your session specifies.

## Review Focus

Inputs the spec implies but does not spell out, most likely to bite first. Each has a test in the task that owns the code.

1. **A truncated download** (the connection drops mid-feed): the events before the cut still come through and the cut VEVENT becomes one `IcsIssue`. Tests: Task 3 (`a truncated feed keeps the unterminated VEVENT`), Task 8 (`malformed.ics`, uid `truncated`).
2. **An HTML sign-in or error page served with HTTP 200**: `expandIcs` throws `IcsFormatException`, so Plan 4 keeps the last good data instead of wiping alarms. Tests: Task 3, Task 8.
3. **Another part of the app loads the smaller `timezone` database** (`latest` instead of `latest_all`): `ics_core` reloads the full one, so Windows zones that CLDR maps to old link names (e.g. "India Standard Time" → `Asia/Calcutta`) still resolve without a warning. Test: Task 6.
4. **A third-party invite whose DTEND is before DTSTART**: the occurrence is kept with zero length at DTSTART (the alarm still rings), never dropped and never negative. Test: Task 8.
5. **A VEVENT with no UID**: it gets a stable stand-in UID built from DTSTART and SUMMARY, so the occurrence key (and any dismissal) survives every re-sync. Test: Task 7.

## Decisions this plan makes (the spec is silent)

- `rrule` 0.2.18 ignores time zones and strips the `Z` from UNTIL. We expand in the event's wall-clock zone ourselves and convert a UTC UNTIL to that wall clock first. It also rejects `WKST` other than `MO` (Outlook writes `WKST=SU`), so WKST is dropped; this only changes weekly rules with INTERVAL > 1 whose BYDAY days straddle Sunday. BYSETPOS works (tested).
- `rrule` does not add a DTSTART that does not match the rule as an extra first instance (RFC 5545 says it should count). Outlook always writes a matching DTSTART, so this is accepted.
- RDATE (in VEVENT and VTIMEZONE) is not supported.
- `X-MICROSOFT-CDO-BUSYSTATUS:WORKINGELSEWHERE` → `busy`. Unknown values fall through to the TRANSP rule.
- Missing SUMMARY → `title == ''`. Missing UID → `'no-uid:<DTSTART value>|<title>'`.
- An override (RECURRENCE-ID) is a complete event: it does not inherit fields from its series. With no DTEND and no DURATION it has zero length, like any other event.
- An override whose series is missing from the feed is shown on its own with `recurring: true`.
- A cancelled series (`STATUS:CANCELLED` or a `Canceled:` title on the master) also drops all its overrides.
- DTEND before DTSTART → zero length.
- A Teams link percent-encoded inside another URL (Outlook Safe Links) is decoded.
- `deviceZone` that is not an IANA name, or an empty window, throws `ArgumentError` (a programming error in the caller, not bad feed data).
- An all-day event uses DATE values only. `X-MICROSOFT-CDO-ALLDAYEVENT:TRUE` on DATE-TIME values is not treated as all-day.

## File Structure

```
pubspec.yaml                                   Modify: add the workspace
pubspec.lock                                   Modified by `flutter pub get`
.gitignore                                     Modify (Task 11): ignore raw feeds
packages/ics_core/
  pubspec.yaml                                 Package manifest (resolution: workspace)
  analysis_options.yaml                        package:lints/recommended.yaml
  lib/ics_core.dart                            Public library: exports expandIcs + model only
  lib/src/model.dart                           Roadmap §2 types, value equality
  lib/src/content_line.dart                    Unfolding, NAME;PARAM=..:value parsing, TEXT unescaping
  lib/src/component.dart                       BEGIN/END tree, IcsFormatException for non-calendars
  lib/src/values.dart                          DATE/DATE-TIME, DURATION, RRULE preparation for package:rrule
  lib/src/zones/windows_zones.g.dart           GENERATED Windows→IANA const map (CLDR, territory 001)
  lib/src/zones/wall_zone.dart                 Wall-clock⇄UTC for UTC, IANA and VTIMEZONE-defined zones
  lib/src/zones/zone_resolver.dart             TZID resolution order + warnings, tz database loading
  lib/src/event_fields.dart                    Title cancel check, busy status, organizer, Teams URL
  lib/src/vevent.dart                          VEVENT → ParsedEvent (values parsed, no zones applied)
  lib/src/expander.dart                        Window, one-off / series / override expansion
  lib/src/expand_ics.dart                      expandIcs(): orchestration and per-event isolation
  tool/gen_windows_zones.dart                  Downloads CLDR windowsZones.xml, writes windows_zones.g.dart
  tool/scrub_feed.dart                         Scrubs a real feed into a committable fixture
  test/support.dart                            Fixture loading helpers
  test/*_test.dart                             One test file per unit (see tasks)
  test/fixtures/*.ics                          Handcrafted fixtures (spec §11) + scrubbed real feed
```

---

### Task 1: Workspace and the public model

**Files:**
- Modify: `pubspec.yaml` (root, after the `environment:` block)
- Modify: `pubspec.lock` (by `flutter pub get`)
- Create: `packages/ics_core/pubspec.yaml`
- Create: `packages/ics_core/analysis_options.yaml`
- Create: `packages/ics_core/lib/ics_core.dart`
- Create: `packages/ics_core/lib/src/model.dart`
- Test: `packages/ics_core/test/model_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces (roadmap §2, exact): `enum IcsBusyStatus { free, tentative, busy, oof, unknown }`; `enum IcsWarning { tzFromVtimezone, tzFromDevice }`; `class IcsOccurrence` with a const constructor taking named `uid`, `originalStartUtc`, `recurring`, `title`, `location?`, `organizer?`, `description?`, `joinUrl?`, `startUtc`, `endUtc`, `allDay`, `busyStatus`, `warnings = const {}`, plus `==`/`hashCode` (warnings compared as sets); `class IcsIssue({String? uid, required int line, required String message})` with value equality; `class IcsResult({required List<IcsOccurrence> occurrences, required List<IcsIssue> issues})`; `class IcsFormatException implements Exception { const IcsFormatException(this.message); final String message; }`.

How the workspace behaves (verified in a scratch copy of this repo while writing this plan): `flutter pub get` at the root resolves the app and `ics_core` together into the single root `pubspec.lock` and `.dart_tool/package_config.json` (the package gets only a small `.dart_tool/` folder, already ignored by the root `.gitignore`). `flutter test` at the root still runs only `test/`. `flutter analyze` at the root also analyses `packages/ics_core`, using the package's own `analysis_options.yaml`. `dart test` inside `packages/ics_core` uses the root resolution.

- [ ] **Step 1: Make the root a pub workspace**

In `pubspec.yaml`, directly after these existing lines:

```yaml
environment:
  sdk: ^3.13.0
```

insert:

```yaml

# Dart pub workspace: packages/ics_core shares this lockfile and resolution.
workspace:
  - packages/ics_core
```

- [ ] **Step 2: Create the package manifest and lints**

`packages/ics_core/pubspec.yaml`:

```yaml
name: ics_core
description: Parses ICS calendar feeds and expands occurrences in a time window.
publish_to: none
version: 0.1.0
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  rrule: ^0.2.18
  timezone: ^0.11.1

dev_dependencies:
  lints: ^6.1.0
  test: ^1.31.1
```

`packages/ics_core/analysis_options.yaml`:

```yaml
include: package:lints/recommended.yaml
```

- [ ] **Step 3: Resolve the workspace**

Run (repo root): `flutter pub get`
Expected: ends with `Changed NN dependencies!` (new entries include `rrule 0.2.18`, `timezone 0.11.1`, `test 1.31.1`, `lints 6.1.0`) and no error. If pub reports that `test` cannot be resolved, check that the constraint is `^1.31.1` (see Global Constraints).

- [ ] **Step 4: Write the failing test**

`packages/ics_core/test/model_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

void main() {
  IcsOccurrence sample({Set<IcsWarning> warnings = const {}}) => IcsOccurrence(
    uid: 'u1',
    originalStartUtc: DateTime.utc(2026, 10, 12, 7),
    recurring: true,
    title: 'Standup',
    location: 'Room 1',
    organizer: 'Thandi M.',
    description: 'Daily',
    joinUrl: 'https://teams.microsoft.com/l/meetup-join/abc',
    startUtc: DateTime.utc(2026, 10, 12, 7),
    endUtc: DateTime.utc(2026, 10, 12, 7, 15),
    allDay: false,
    busyStatus: IcsBusyStatus.busy,
    warnings: warnings,
  );

  test('IcsOccurrence has value equality, including warnings in any order', () {
    final a = sample(
      warnings: {IcsWarning.tzFromDevice, IcsWarning.tzFromVtimezone},
    );
    final b = sample(
      warnings: {IcsWarning.tzFromVtimezone, IcsWarning.tzFromDevice},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(sample(), isNot(a));
  });

  test('IcsOccurrence defaults to no warnings', () {
    expect(sample().warnings, isEmpty);
  });

  test('IcsIssue has value equality', () {
    expect(
      const IcsIssue(uid: 'x', line: 3, message: 'bad'),
      const IcsIssue(uid: 'x', line: 3, message: 'bad'),
    );
    expect(const IcsIssue(line: 3, message: 'bad').uid, isNull);
  });

  test('IcsFormatException carries its message', () {
    const e = IcsFormatException('nope');
    expect(e.message, 'nope');
    expect(e.toString(), contains('nope'));
  });

  test('enums match the roadmap contract', () {
    expect(IcsBusyStatus.values.map((v) => v.name), [
      'free',
      'tentative',
      'busy',
      'oof',
      'unknown',
    ]);
    expect(IcsWarning.values.map((v) => v.name), [
      'tzFromVtimezone',
      'tzFromDevice',
    ]);
  });
}
```

- [ ] **Step 5: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/model_test.dart`
Expected: FAIL, compilation error: `lib/ics_core.dart` does not exist (`Error when reading ... ics_core.dart`).

- [ ] **Step 6: Write the model**

`packages/ics_core/lib/src/model.dart`:

```dart
/// Busy state an event shows in Outlook.
enum IcsBusyStatus { free, tentative, busy, oof, unknown }

/// Why an event's times are less certain than usual.
enum IcsWarning {
  /// TZID not in the Windows→IANA table and not an IANA name; used the feed's VTIMEZONE.
  tzFromVtimezone,

  /// No usable zone at all; used the device zone.
  tzFromDevice,
}

/// One occurrence of an event inside the requested window.
class IcsOccurrence {
  const IcsOccurrence({
    required this.uid,
    required this.originalStartUtc,
    required this.recurring,
    required this.title,
    this.location,
    this.organizer,
    this.description,
    this.joinUrl,
    required this.startUtc,
    required this.endUtc,
    required this.allDay,
    required this.busyStatus,
    this.warnings = const {},
  });

  final String uid;

  /// The instance's RECURRENCE-ID / original DTSTART, UTC.
  final DateTime originalStartUtc;

  /// True for any instance of an RRULE series (incl. overrides).
  final bool recurring;

  /// SUMMARY, unescaped.
  final String title;
  final String? location;

  /// CN if present, else mailto address.
  final String? organizer;
  final String? description;

  /// First Teams join link (https://teams.microsoft.com/l/meetup-join/... or
  /// https://teams.microsoft.com/meet/...) in DESCRIPTION, then LOCATION.
  final String? joinUrl;
  final DateTime startUtc;
  final DateTime endUtc;

  /// DATE values; start/end = local midnight in deviceZone, as UTC.
  final bool allDay;

  /// X-MICROSOFT-CDO-BUSYSTATUS, else TRANSP (TRANSPARENT→free), else unknown.
  final IcsBusyStatus busyStatus;
  final Set<IcsWarning> warnings;

  @override
  bool operator ==(Object other) =>
      other is IcsOccurrence &&
      other.uid == uid &&
      other.originalStartUtc == originalStartUtc &&
      other.recurring == recurring &&
      other.title == title &&
      other.location == location &&
      other.organizer == organizer &&
      other.description == description &&
      other.joinUrl == joinUrl &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc &&
      other.allDay == allDay &&
      other.busyStatus == busyStatus &&
      other.warnings.length == warnings.length &&
      other.warnings.containsAll(warnings);

  @override
  int get hashCode => Object.hash(
    uid,
    originalStartUtc,
    recurring,
    title,
    location,
    organizer,
    description,
    joinUrl,
    startUtc,
    endUtc,
    allDay,
    busyStatus,
    Object.hashAllUnordered(warnings),
  );

  @override
  String toString() =>
      'IcsOccurrence($uid, "$title", ${startUtc.toIso8601String()} to '
      '${endUtc.toIso8601String()}, original ${originalStartUtc.toIso8601String()}, '
      'recurring: $recurring, allDay: $allDay, busy: ${busyStatus.name}, '
      'warnings: ${warnings.map((w) => w.name).toList()})';
}

/// One skipped/odd VEVENT; the rest of the feed still parses.
class IcsIssue {
  const IcsIssue({this.uid, required this.line, required this.message});

  final String? uid;

  /// 1-based line in the unfolded text where the VEVENT began.
  final int line;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is IcsIssue &&
      other.uid == uid &&
      other.line == line &&
      other.message == message;

  @override
  int get hashCode => Object.hash(uid, line, message);

  @override
  String toString() => 'IcsIssue(line $line, uid: $uid, $message)';
}

/// What `expandIcs` returns.
class IcsResult {
  const IcsResult({required this.occurrences, required this.issues});

  /// Sorted by startUtc, cancelled ones already dropped.
  final List<IcsOccurrence> occurrences;
  final List<IcsIssue> issues;
}

/// The text is not a VCALENDAR at all (whole feed unusable).
class IcsFormatException implements Exception {
  const IcsFormatException(this.message);

  final String message;

  @override
  String toString() => 'IcsFormatException: $message';
}
```

`packages/ics_core/lib/ics_core.dart` (Task 8 replaces this file):

```dart
/// ICS text → event occurrences in a time window. Pure Dart (no Flutter).
library;

export 'src/model.dart';
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd packages/ics_core && dart test test/model_test.dart`
Expected: `All tests passed!`

- [ ] **Step 8: Check the app is unaffected**

Run, one at a time:
- `cd packages/ics_core && dart analyze` → `No issues found!`
- (repo root) `flutter analyze` → `No issues found!`
- (repo root) `flutter test` → `All tests passed!`

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock packages/ics_core
git commit -m "Add ics_core package in a pub workspace" -m "The root pubspec becomes a Dart pub workspace holding packages/ics_core, a pure Dart package. This adds its public model from roadmap section 2: IcsOccurrence, IcsIssue, IcsResult, IcsWarning, IcsBusyStatus and IcsFormatException, with value equality."
```

---

### Task 2: Content lines (unfolding, parameters, unescaping)

**Files:**
- Create: `packages/ics_core/lib/src/content_line.dart`
- Test: `packages/ics_core/test/content_line_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class ContentLine { const ContentLine(String name, Map<String, String> params, String value, int line); final String name /* upper-case */; final Map<String, String> params /* keys upper-case, quotes removed */; final String value /* raw */; final int line /* 1-based, unfolded */; }`; `List<String> unfoldLines(String text)`; `ContentLine? parseContentLine(String raw, int line)`; `String unescapeText(String value)`.

- [ ] **Step 1: Write the failing test**

`packages/ics_core/test/content_line_test.dart`:

```dart
import 'package:ics_core/src/content_line.dart';
import 'package:test/test.dart';

void main() {
  group('unfoldLines', () {
    test('joins CRLF + space continuations', () {
      expect(unfoldLines('SUMMARY:Quarterly pl\r\n anning\r\nUID:1\r\n'), [
        'SUMMARY:Quarterly planning',
        'UID:1',
        '',
      ]);
    });

    test(
      'joins LF + tab continuations and removes only one whitespace char',
      () {
        expect(unfoldLines('DESCRIPTION:a\n\t b\nUID:1'), [
          'DESCRIPTION:a b',
          'UID:1',
        ]);
      },
    );

    test('accepts bare CR line breaks and drops a byte-order mark', () {
      expect(unfoldLines('\uFEFFBEGIN:VCALENDAR\rEND:VCALENDAR'), [
        'BEGIN:VCALENDAR',
        'END:VCALENDAR',
      ]);
    });
  });

  group('parseContentLine', () {
    test('splits name, parameters and value', () {
      final l = parseContentLine(
        'DTSTART;TZID=South Africa Standard Time:20261012T084500',
        7,
      )!;
      expect(l.name, 'DTSTART');
      expect(l.params, {'TZID': 'South Africa Standard Time'});
      expect(l.value, '20261012T084500');
      expect(l.line, 7);
    });

    test('quoted parameter values may contain ; and :', () {
      final l = parseContentLine(
        'ORGANIZER;CN="Thandi M.; Ops: SA";SENT-BY="mailto:pa@example.com":mailto:thandi@example.com',
        1,
      )!;
      expect(l.params['CN'], 'Thandi M.; Ops: SA');
      expect(l.params['SENT-BY'], 'mailto:pa@example.com');
      expect(l.value, 'mailto:thandi@example.com');
    });

    test(
      'names and parameter keys are upper-cased; the value keeps colons',
      () {
        final l = parseContentLine('location;x-param=1:http://x:80/a', 1)!;
        expect(l.name, 'LOCATION');
        expect(l.params, {'X-PARAM': '1'});
        expect(l.value, 'http://x:80/a');
      },
    );

    test('blank and colon-less lines are null', () {
      expect(parseContentLine('', 1), isNull);
      expect(parseContentLine('JUSTTEXT', 1), isNull);
      expect(parseContentLine(':novalue', 1), isNull);
    });
  });

  group('unescapeText', () {
    test(r'handles \\ \; \, \n \N', () {
      expect(unescapeText(r'a\\b\;c\,d\ne\Nf'), 'a\\b;c,d\ne\nf');
    });

    test('leaves unknown escapes and a trailing backslash alone', () {
      expect(unescapeText(r'C:\temp\'), r'C:\temp\');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/content_line_test.dart`
Expected: FAIL, compilation error: `lib/src/content_line.dart` not found.

- [ ] **Step 3: Implement**

`packages/ics_core/lib/src/content_line.dart`:

```dart
/// One unfolded iCalendar content line: `NAME;PARAM=VALUE:value`.
class ContentLine {
  const ContentLine(this.name, this.params, this.value, this.line);

  /// Property name, upper-case.
  final String name;

  /// Parameter names upper-case; values with their double quotes removed.
  final Map<String, String> params;

  /// Raw value after the first unquoted colon (not unescaped).
  final String value;

  /// 1-based line number in the unfolded text.
  final int line;
}

/// Splits [text] into unfolded lines (RFC 5545 §3.1).
///
/// Accepts CRLF, LF or CR line breaks. A line starting with a space or tab
/// continues the previous line (that one whitespace character is removed).
/// A leading byte-order mark is dropped. Blank lines are kept so line
/// numbers stay stable.
List<String> unfoldLines(String text) {
  var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.startsWith('﻿')) {
    normalized = normalized.substring(1);
  }
  final lines = <String>[];
  for (final raw in normalized.split('\n')) {
    if (lines.isNotEmpty && (raw.startsWith(' ') || raw.startsWith('\t'))) {
      lines[lines.length - 1] = lines.last + raw.substring(1);
    } else {
      lines.add(raw);
    }
  }
  return lines;
}

/// Parses one unfolded line. Returns null for blank or malformed lines
/// (no name, or no unquoted colon).
ContentLine? parseContentLine(String raw, int line) {
  final n = raw.length;
  var i = 0;
  while (i < n && raw[i] != ';' && raw[i] != ':') {
    i++;
  }
  if (i == 0 || i >= n) {
    return null;
  }
  final name = raw.substring(0, i).trim().toUpperCase();
  final params = <String, String>{};
  while (i < n && raw[i] == ';') {
    i++;
    final keyStart = i;
    while (i < n && raw[i] != '=' && raw[i] != ';' && raw[i] != ':') {
      i++;
    }
    final key = raw.substring(keyStart, i).trim().toUpperCase();
    final value = StringBuffer();
    if (i < n && raw[i] == '=') {
      i++;
      var inQuotes = false;
      while (i < n) {
        final c = raw[i];
        if (c == '"') {
          inQuotes = !inQuotes;
        } else if (!inQuotes && (c == ';' || c == ':')) {
          break;
        } else {
          value.write(c);
        }
        i++;
      }
    }
    if (key.isNotEmpty) {
      params[key] = value.toString();
    }
  }
  if (i >= n || raw[i] != ':' || name.isEmpty) {
    return null;
  }
  return ContentLine(name, params, raw.substring(i + 1), line);
}

/// Unescapes a TEXT value: `\\` `\;` `\,` `\n` `\N`.
String unescapeText(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c == r'\' && i + 1 < value.length) {
      final next = value[i + 1];
      switch (next) {
        case 'n' || 'N':
          out.write('\n');
          i++;
        case r'\' || ';' || ',':
          out.write(next);
          i++;
        default:
          out.write(c);
      }
    } else {
      out.write(c);
    }
  }
  return out.toString();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/ics_core && dart test test/content_line_test.dart && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/ics_core/lib/src/content_line.dart packages/ics_core/test/content_line_test.dart
git commit -m "Parse ICS content lines in ics_core" -m "Unfolds CRLF, LF or CR lines continued with a space or tab, splits NAME;PARAM=VALUE:value with quoted parameter values, and unescapes TEXT values."
```

---

### Task 3: Component tree and the not-a-calendar error

**Files:**
- Create: `packages/ics_core/lib/src/component.dart`
- Test: `packages/ics_core/test/component_test.dart`

**Interfaces:**
- Consumes: `unfoldLines`, `parseContentLine`, `ContentLine` (Task 2); `IcsFormatException` (Task 1).
- Produces: `class Component { Component(String name, int line); final String name; final int line; final List<ContentLine> properties; final List<Component> children; bool terminated; ContentLine? first(String name); Iterable<ContentLine> all(String name); }`; `Component parseCalendar(String icsText)` (throws `IcsFormatException` when there is no `BEGIN:VCALENDAR`).

- [ ] **Step 1: Write the failing test**

`packages/ics_core/test/component_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:test/test.dart';

void main() {
  test('builds the VCALENDAR tree with line numbers of the unfolded text', () {
    final cal = parseCalendar(
      [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'BEGIN:VTIMEZONE',
        'TZID:Custom',
        'BEGIN:STANDARD',
        'TZOFFSETTO:+0200',
        'END:STANDARD',
        'END:VTIMEZONE',
        'BEGIN:VEVENT',
        'SUMMARY:Folded',
        '  title',
        'UID:1',
        'END:VEVENT',
        'END:VCALENDAR',
      ].join('\r\n'),
    );
    expect(cal.name, 'VCALENDAR');
    expect(cal.first('VERSION')!.value, '2.0');
    expect(cal.children.map((c) => c.name), ['VTIMEZONE', 'VEVENT']);
    final tz = cal.children.first;
    expect(tz.children.single.name, 'STANDARD');
    expect(tz.children.single.first('TZOFFSETTO')!.value, '+0200');
    final event = cal.children.last;
    expect(event.line, 9);
    expect(event.first('SUMMARY')!.value, 'Folded title');
    expect(event.first('UID')!.line, 11);
    expect(event.terminated, isTrue);
  });

  test('all() returns every property with the name', () {
    final cal = parseCalendar(
      'BEGIN:VCALENDAR\nBEGIN:VEVENT\nEXDATE:20261012\nEXDATE:20261013\nEND:VEVENT\nEND:VCALENDAR',
    );
    expect(cal.children.single.all('EXDATE').map((p) => p.value), [
      '20261012',
      '20261013',
    ]);
  });

  test('a truncated feed keeps the unterminated VEVENT, marked as such', () {
    final cal = parseCalendar(
      'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:ok\nEND:VEVENT\nBEGIN:VEVENT\nUID:cut',
    );
    expect(cal.children.map((c) => c.terminated), [true, false]);
  });

  test('text before BEGIN:VCALENDAR is ignored', () {
    final cal = parseCalendar('garbage\nX:1\nBEGIN:VCALENDAR\nEND:VCALENDAR');
    expect(cal.properties, isEmpty);
  });

  test('text without BEGIN:VCALENDAR throws IcsFormatException', () {
    expect(
      () => parseCalendar('<html>Not found</html>'),
      throwsA(isA<IcsFormatException>()),
    );
    expect(() => parseCalendar(''), throwsA(isA<IcsFormatException>()));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/component_test.dart`
Expected: FAIL, compilation error: `lib/src/component.dart` not found.

- [ ] **Step 3: Implement**

`packages/ics_core/lib/src/component.dart`:

```dart
import 'content_line.dart';
import 'model.dart';

/// A BEGIN/END block such as VCALENDAR, VEVENT, VTIMEZONE or STANDARD.
class Component {
  Component(this.name, this.line);

  /// Upper-case component name, e.g. `VEVENT`.
  final String name;

  /// 1-based line in the unfolded text where `BEGIN:` appeared.
  final int line;
  final List<ContentLine> properties = [];
  final List<Component> children = [];

  /// False when the text ended (or an outer END came) before this block's END.
  bool terminated = false;

  /// The first property called [name], or null.
  ContentLine? first(String name) {
    for (final p in properties) {
      if (p.name == name) {
        return p;
      }
    }
    return null;
  }

  /// Every property called [name], in order.
  Iterable<ContentLine> all(String name) =>
      properties.where((p) => p.name == name);
}

/// Unfolds [icsText] and builds the component tree of its first VCALENDAR.
///
/// Throws [IcsFormatException] if there is no `BEGIN:VCALENDAR`.
/// Unterminated blocks are kept with [Component.terminated] false so the
/// caller can report them; lines outside the calendar are ignored.
Component parseCalendar(String icsText) {
  final lines = unfoldLines(icsText);
  Component? root;
  final stack = <Component>[];
  for (var index = 0; index < lines.length; index++) {
    final cl = parseContentLine(lines[index], index + 1);
    if (cl == null) {
      continue;
    }
    if (cl.name == 'BEGIN') {
      final component = Component(cl.value.trim().toUpperCase(), cl.line);
      if (stack.isEmpty) {
        if (root != null || component.name != 'VCALENDAR') {
          continue;
        }
        root = component;
      } else {
        stack.last.children.add(component);
      }
      stack.add(component);
    } else if (cl.name == 'END') {
      final name = cl.value.trim().toUpperCase();
      final at = stack.lastIndexWhere((c) => c.name == name);
      if (at < 0) {
        continue;
      }
      stack[at].terminated = true;
      stack.removeRange(at, stack.length);
      if (stack.isEmpty) {
        break;
      }
    } else if (stack.isNotEmpty) {
      stack.last.properties.add(cl);
    }
  }
  if (root == null) {
    throw const IcsFormatException('Not an iCalendar feed: no BEGIN:VCALENDAR');
  }
  return root;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/ics_core && dart test test/component_test.dart && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/ics_core/lib/src/component.dart packages/ics_core/test/component_test.dart
git commit -m "Build the ICS component tree in ics_core" -m "Builds VCALENDAR, VEVENT, VTIMEZONE and nested blocks with unfolded line numbers. Unterminated blocks from a truncated download are kept and marked; text with no BEGIN:VCALENDAR throws IcsFormatException."
```

---

### Task 4: Values: dates, durations and RRULE preparation

**Files:**
- Create: `packages/ics_core/lib/src/values.dart`
- Test: `packages/ics_core/test/values_test.dart`

**Interfaces:**
- Consumes: `ContentLine` (Task 2); `package:rrule` `RecurrenceRule` (`RecurrenceRule.fromString(String)`, `copyWith({DateTime? until})`, `getInstances({required DateTime start, DateTime? after, bool includeAfter, DateTime? before, bool includeBefore})`; every `DateTime` passed to it must be `isUtc` and is treated as a wall-clock value).
- Produces: `class IcsTime { const IcsTime({required DateTime wall, required bool isDate, required bool isUtc, String? tzid}); }` with value equality (`wall` is a UTC `DateTime` holding the written fields); `IcsTime parseIcsTime(String value, {String? tzid})`; `List<IcsTime> parseIcsTimes(ContentLine line)`; `Duration parseIcsDuration(String value)`; `RecurrenceRule parseRrule(String value, {required DateTime Function(DateTime untilUtc) untilUtcToWall, required bool startIsDate})`. All throw `FormatException` on bad input.

`package:rrule` facts this task relies on (read from rrule 0.2.18's source while planning): it strips the `Z` from UNTIL and compares UNTIL as a wall-clock time; it throws `FormatException` for `WKST` other than `MO`; COUNT counts from `start` even when `after` is given; BYSETPOS and `BYDAY=2MO` / `-1FR` work. Dart's `DateTime.tryParse('20261306T120000')` silently rolls over to 2027-01-06, which is why `parseIcsTime` validates ranges itself.

- [ ] **Step 1: Write the failing test**

`packages/ics_core/test/values_test.dart`:

```dart
import 'package:ics_core/src/content_line.dart';
import 'package:ics_core/src/values.dart';
import 'package:test/test.dart';

void main() {
  group('parseIcsTime', () {
    test('DATE-TIME with TZID keeps wall fields and the zone name', () {
      expect(
        parseIcsTime('20261012T084500', tzid: ' South Africa Standard Time '),
        IcsTime(
          wall: DateTime.utc(2026, 10, 12, 8, 45),
          isDate: false,
          isUtc: false,
          tzid: 'South Africa Standard Time',
        ),
      );
    });

    test('UTC DATE-TIME ignores any TZID', () {
      final t = parseIcsTime('20261012T064500Z', tzid: 'Ignored');
      expect(t.isUtc, isTrue);
      expect(t.tzid, isNull);
      expect(t.wall, DateTime.utc(2026, 10, 12, 6, 45));
    });

    test('DATE', () {
      final t = parseIcsTime('20261013');
      expect(t.isDate, isTrue);
      expect(t.wall, DateTime.utc(2026, 10, 13));
    });

    test('rejects impossible or malformed values', () {
      for (final bad in [
        '20261332',
        '20260230',
        '20261012T250000',
        '20261012T086000',
        '2026-10-12',
        '20261012T0845',
        '',
      ]) {
        expect(() => parseIcsTime(bad), throwsFormatException, reason: bad);
      }
    });
  });

  test('parseIcsTimes reads comma-separated values with the line TZID', () {
    final line = parseContentLine(
      'EXDATE;TZID=W. Europe Standard Time:20261013T090000,20261015T090000',
      1,
    )!;
    expect(parseIcsTimes(line).map((t) => (t.wall.day, t.tzid)), [
      (13, 'W. Europe Standard Time'),
      (15, 'W. Europe Standard Time'),
    ]);
  });

  group('parseIcsDuration', () {
    test('reads weeks, days, hours, minutes and seconds', () {
      expect(
        parseIcsDuration('PT1H30M'),
        const Duration(hours: 1, minutes: 30),
      );
      expect(parseIcsDuration('P1D'), const Duration(days: 1));
      expect(parseIcsDuration('P2W'), const Duration(days: 14));
      expect(
        parseIcsDuration('+P1DT2H3M4S'),
        const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
      );
    });

    test('rejects malformed and negative durations', () {
      for (final bad in ['soon', 'P', 'PT', '1H', '-PT15M']) {
        expect(() => parseIcsDuration(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('parseRrule', () {
    DateTime plusTwo(DateTime utc) => utc.add(const Duration(hours: 2));

    test('drops WKST=SU, which package:rrule rejects', () {
      final rule = parseRrule(
        'FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,TU;WKST=SU',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 12, 9)).take(3), [
        DateTime.utc(2026, 10, 12, 9),
        DateTime.utc(2026, 10, 13, 9),
        DateTime.utc(2026, 10, 19, 9),
      ]);
    });

    test('converts a UTC UNTIL to the event wall clock (inclusive)', () {
      // 07:00Z is 09:00 in UTC+2, so the 09:00 instance on the 8th is kept.
      final rule = parseRrule(
        'FREQ=DAILY;UNTIL=20261008T070000Z',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5, 9)).length, 4);
    });

    test('a local UNTIL is used as written', () {
      final rule = parseRrule(
        'RRULE:FREQ=DAILY;UNTIL=20261007T090000',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5, 9)).length, 3);
    });

    test('a DATE UNTIL on a timed event runs through that day', () {
      final rule = parseRrule(
        'FREQ=DAILY;UNTIL=20261006',
        untilUtcToWall: plusTwo,
        startIsDate: false,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5, 9)).length, 2);
    });

    test('a DATE-TIME UNTIL on an all-day event keeps only its date', () {
      final rule = parseRrule(
        'FREQ=DAILY;UNTIL=20261007T235959Z',
        untilUtcToWall: plusTwo,
        startIsDate: true,
      );
      expect(rule.getInstances(start: DateTime.utc(2026, 10, 5)).length, 3);
    });

    test('rejects UNTIL with COUNT, and unknown values', () {
      expect(
        () => parseRrule(
          'FREQ=DAILY;COUNT=2;UNTIL=20261007',
          untilUtcToWall: plusTwo,
          startIsDate: false,
        ),
        throwsFormatException,
      );
      expect(
        () => parseRrule(
          'FREQ=SOMETIMES',
          untilUtcToWall: plusTwo,
          startIsDate: false,
        ),
        throwsFormatException,
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/values_test.dart`
Expected: FAIL, compilation error: `lib/src/values.dart` not found.

- [ ] **Step 3: Implement**

`packages/ics_core/lib/src/values.dart`:

```dart
import 'package:rrule/rrule.dart';

import 'content_line.dart';

/// A DATE or DATE-TIME value as written in the feed.
class IcsTime {
  const IcsTime({
    required this.wall,
    required this.isDate,
    required this.isUtc,
    this.tzid,
  });

  /// The written date/time fields, held in a UTC [DateTime] (no zone applied).
  final DateTime wall;

  /// A DATE value (no time part).
  final bool isDate;

  /// The value ended in `Z`.
  final bool isUtc;

  /// The TZID parameter, trimmed; null for UTC, DATE or floating values.
  final String? tzid;

  @override
  bool operator ==(Object other) =>
      other is IcsTime &&
      other.wall == wall &&
      other.isDate == isDate &&
      other.isUtc == isUtc &&
      other.tzid == tzid;

  @override
  int get hashCode => Object.hash(wall, isDate, isUtc, tzid);

  @override
  String toString() =>
      'IcsTime(${wall.toIso8601String()}, date: $isDate, utc: $isUtc, tzid: $tzid)';
}

final _dateTimePattern = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$',
);

/// Parses one DATE (`20261012`) or DATE-TIME (`20261012T090000`, `…Z`) value.
///
/// Throws [FormatException] for anything else, including impossible dates
/// such as `20261332` (Dart's own `DateTime.parse` would roll those over).
IcsTime parseIcsTime(String value, {String? tzid}) {
  final m = _dateTimePattern.firstMatch(value.trim());
  if (m == null) {
    throw FormatException('Bad date or date-time: "$value"');
  }
  final year = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final day = int.parse(m[3]!);
  final isDate = m[4] == null;
  final hour = isDate ? 0 : int.parse(m[4]!);
  final minute = isDate ? 0 : int.parse(m[5]!);
  var second = isDate ? 0 : int.parse(m[6]!);
  if (second == 60) {
    second = 59; // leap second
  }
  final daysInMonth = DateTime.utc(year, month + 1, 0).day;
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > daysInMonth ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    throw FormatException('Bad date or date-time: "$value"');
  }
  final isUtc = m[7] != null;
  final cleanTzid = tzid?.trim();
  return IcsTime(
    wall: DateTime.utc(year, month, day, hour, minute, second),
    isDate: isDate,
    isUtc: isUtc,
    tzid: isUtc || isDate || cleanTzid == null || cleanTzid.isEmpty
        ? null
        : cleanTzid,
  );
}

/// Parses a property such as DTSTART, DTEND, RECURRENCE-ID or EXDATE,
/// honouring its TZID parameter. EXDATE may hold several comma-separated values.
List<IcsTime> parseIcsTimes(ContentLine line) => [
  for (final part in line.value.split(','))
    if (part.trim().isNotEmpty) parseIcsTime(part, tzid: line.params['TZID']),
];

final _durationPattern = RegExp(
  r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
);

/// Parses a DURATION value such as `PT1H30M`, `P1D` or `P2W`.
///
/// Throws [FormatException] for malformed or negative durations.
Duration parseIcsDuration(String value) {
  final v = value.trim().toUpperCase();
  final m = _durationPattern.firstMatch(v);
  if (m == null || v.endsWith('P') || v.endsWith('T')) {
    throw FormatException('Bad DURATION: "$value"');
  }
  if (m[1] == '-') {
    throw FormatException('Negative DURATION: "$value"');
  }
  int part(int i) => m[i] == null ? 0 : int.parse(m[i]!);
  return Duration(
    days: part(2) * 7 + part(3),
    hours: part(4),
    minutes: part(5),
    seconds: part(6),
  );
}

/// Builds an `rrule` [RecurrenceRule] that works on wall-clock times.
///
/// `package:rrule` ignores time zones: it treats every [DateTime] as a
/// wall-clock value and drops the `Z` from UNTIL. So:
/// * a UTC UNTIL is converted to the event's wall clock with [untilUtcToWall];
/// * a DATE UNTIL on a timed event means "through the end of that day";
/// * a DATE-TIME UNTIL on an all-day event keeps only its date;
/// * WKST is dropped because `rrule` 0.2.18 rejects anything but MO (Outlook
///   writes WKST=SU). This only changes results for weekly rules with
///   INTERVAL > 1 whose BYDAY days straddle Sunday.
///
/// Throws [FormatException] if the rule is malformed.
RecurrenceRule parseRrule(
  String value, {
  required DateTime Function(DateTime untilUtc) untilUtcToWall,
  required bool startIsDate,
}) {
  var body = value.trim();
  if (body.toUpperCase().startsWith('RRULE:')) {
    body = body.substring(6);
  }
  String? until;
  var hasCount = false;
  final kept = <String>[];
  for (final part in body.split(';')) {
    if (part.trim().isEmpty) {
      continue;
    }
    final eq = part.indexOf('=');
    final key = (eq < 0 ? part : part.substring(0, eq)).trim().toUpperCase();
    if (key == 'WKST') {
      continue;
    }
    if (key == 'UNTIL') {
      until = eq < 0 ? '' : part.substring(eq + 1);
      continue;
    }
    if (key == 'COUNT') {
      hasCount = true;
    }
    kept.add(part.trim());
  }
  if (until != null && hasCount) {
    throw const FormatException('RRULE has both UNTIL and COUNT');
  }
  final rule = RecurrenceRule.fromString('RRULE:${kept.join(';')}');
  if (until == null) {
    return rule;
  }
  final t = parseIcsTime(until);
  final DateTime wallUntil;
  if (startIsDate) {
    wallUntil = DateTime.utc(t.wall.year, t.wall.month, t.wall.day);
  } else if (t.isUtc) {
    wallUntil = untilUtcToWall(t.wall);
  } else if (t.isDate) {
    wallUntil = DateTime.utc(t.wall.year, t.wall.month, t.wall.day, 23, 59, 59);
  } else {
    wallUntil = t.wall;
  }
  return rule.copyWith(until: wallUntil);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/ics_core && dart test test/values_test.dart && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/ics_core/lib/src/values.dart packages/ics_core/test/values_test.dart
git commit -m "Parse ICS dates, durations and recurrence rules" -m "Strict DATE and DATE-TIME parsing (no silent roll-over), DURATION, and RRULE preparation for package:rrule: a UTC UNTIL is converted to the event wall clock, a DATE UNTIL covers its whole day, and WKST is dropped because rrule rejects WKST=SU."
```

---

### Task 5: Windows → IANA table from CLDR

**Files:**
- Create: `packages/ics_core/tool/gen_windows_zones.dart`
- Create (generated): `packages/ics_core/lib/src/zones/windows_zones.g.dart`
- Test: `packages/ics_core/test/windows_zones_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (the test also uses `package:timezone`).
- Produces: `const Map<String, String> windowsToIana` in `lib/src/zones/windows_zones.g.dart` (Windows zone name → IANA name, CLDR rows with `territory="001"`); in the tool, `Map<String, String> parseWindowsZones(String xml)` and `String renderWindowsZones(Map<String, String> zones, {required String source})`.

Task 6 creates `ensureTimeZonesLoaded()` in `zone_resolver.dart`. This task's test needs it, so Step 1 creates a minimal `zone_resolver.dart` holding only that function; Task 6 replaces the whole file.

- [ ] **Step 1: Write the failing test and the loader it uses**

`packages/ics_core/lib/src/zones/zone_resolver.dart` (temporary; Task 6 replaces it):

```dart
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Loads the full IANA database (`latest_all`) unless it is already loaded.
void ensureTimeZonesLoaded() {
  if (!tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta')) {
    tzdata.initializeTimeZones();
  }
}
```

`packages/ics_core/test/windows_zones_test.dart`:

```dart
import 'package:ics_core/src/zones/windows_zones.g.dart';
import 'package:ics_core/src/zones/zone_resolver.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../tool/gen_windows_zones.dart';

void main() {
  group('generator', () {
    const sample = '''
<supplementalData>
  <windowsZones>
    <mapTimezones otherVersion="7e11800" typeVersion="2021a">
      <mapZone other="Pacific Standard Time" territory="001" type="America/Los_Angeles"/>
      <mapZone other="Pacific Standard Time" territory="CA" type="America/Vancouver"/>
      <mapZone other="Pacific Standard Time" territory="US" type="America/Los_Angeles"/>
      <mapZone other="South Africa Standard Time" territory="001" type="Africa/Johannesburg"/>
      <mapZone type="Etc/UTC" territory="001" other="UTC"/>
    </mapTimezones>
  </windowsZones>
</supplementalData>
''';

    test('keeps only territory 001 rows, in any attribute order', () {
      expect(parseWindowsZones(sample), {
        'Pacific Standard Time': 'America/Los_Angeles',
        'South Africa Standard Time': 'Africa/Johannesburg',
        'UTC': 'Etc/UTC',
      });
    });

    test('renders a sorted const map with its source', () {
      final source = renderWindowsZones({
        'b': 'Etc/B',
        'a': 'Etc/A',
      }, source: 'https://example.com/x.xml');
      expect(source, contains('// Source: https://example.com/x.xml'));
      expect(source, contains('const Map<String, String> windowsToIana = {'));
      expect(source.indexOf('"a"'), lessThan(source.indexOf('"b"')));
    });
  });

  group('committed table', () {
    setUpAll(ensureTimeZonesLoaded);

    test('maps the zones T-Minus users meet most', () {
      expect(windowsToIana['Pacific Standard Time'], 'America/Los_Angeles');
      expect(
        windowsToIana['South Africa Standard Time'],
        'Africa/Johannesburg',
      );
      expect(windowsToIana['W. Europe Standard Time'], 'Europe/Berlin');
      expect(windowsToIana['GMT Standard Time'], 'Europe/London');
      expect(windowsToIana['UTC'], 'Etc/UTC');
    });

    test('is the full CLDR table', () {
      expect(windowsToIana.length, greaterThan(100));
    });

    test('every IANA target exists in the bundled timezone database', () {
      final missing = [
        for (final iana in windowsToIana.values.toSet())
          if (!tz.timeZoneDatabase.locations.containsKey(iana)) iana,
      ];
      expect(missing, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/windows_zones_test.dart`
Expected: FAIL, compilation error: `tool/gen_windows_zones.dart` and `windows_zones.g.dart` not found.

- [ ] **Step 3: Write the generator**

`packages/ics_core/tool/gen_windows_zones.dart`:

```dart
// Generates lib/src/zones/windows_zones.g.dart from the CLDR windowsZones table.
//
// Usage (from packages/ics_core):
//   dart run tool/gen_windows_zones.dart            # downloads from [sourceUrl]
//   dart run tool/gen_windows_zones.dart some.xml   # uses a local copy
import 'dart:convert';
import 'dart:io';

const sourceUrl =
    'https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/windowsZones.xml';
const outputPath = 'lib/src/zones/windows_zones.g.dart';

final _mapZone = RegExp(r'<mapZone\s([^>]*?)/?>');
final _attribute = RegExp(r'(\w+)="([^"]*)"');

/// Windows zone name → IANA zone, from the territory "001" (default) rows.
Map<String, String> parseWindowsZones(String xml) {
  final result = <String, String>{};
  for (final m in _mapZone.allMatches(xml)) {
    final attrs = {
      for (final a in _attribute.allMatches(m[1]!))
        a[1]!: a[2]!.replaceAll('&amp;', '&'),
    };
    final other = attrs['other'];
    final type = attrs['type'];
    if (attrs['territory'] == '001' && other != null && type != null) {
      result[other] = type.split(' ').first;
    }
  }
  return result;
}

/// The Dart source for the generated file, keys sorted.
String renderWindowsZones(Map<String, String> zones, {required String source}) {
  final out = StringBuffer()
    ..writeln(
      '// GENERATED by tool/gen_windows_zones.dart. Do not edit by hand.',
    )
    ..writeln('// Source: $source')
    ..writeln(
      '// Rows: territory="001" (the default IANA zone per Windows zone).',
    )
    ..writeln()
    ..writeln(
      '/// Windows time zone name → IANA zone name (CLDR windowsZones).',
    )
    ..writeln('const Map<String, String> windowsToIana = {');
  final keys = zones.keys.toList()..sort();
  for (final k in keys) {
    out.writeln(
      "  ${jsonEncode(k).replaceAll(r'$', r'\$')}: "
      "${jsonEncode(zones[k]).replaceAll(r'$', r'\$')},",
    );
  }
  out.writeln('};');
  return out.toString();
}

Future<void> main(List<String> args) async {
  final String xml;
  final String source;
  if (args.isNotEmpty) {
    xml = await File(args.first).readAsString();
    source = '${args.first} (local copy of $sourceUrl)';
  } else {
    stdout.writeln('Downloading $sourceUrl');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(sourceUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln('HTTP ${response.statusCode} from $sourceUrl');
        exit(1);
      }
      xml = await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
    source = sourceUrl;
  }
  final zones = parseWindowsZones(xml);
  if (zones.length < 100) {
    stderr.writeln('Only ${zones.length} zones parsed; refusing to write.');
    exit(1);
  }
  await File(outputPath)
      .writeAsString(renderWindowsZones(zones, source: source));
  stdout.writeln('Wrote ${zones.length} zones to $outputPath');
}
```

- [ ] **Step 4: Tell the user where the table comes from**

Before downloading anything, tell the user (no need to wait for a reply unless they object):

> To map Outlook's Windows time zone names to IANA zones I'm downloading the Unicode CLDR `windowsZones` table from https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/windowsZones.xml and generating a committed Dart map from its territory "001" rows.

- [ ] **Step 5: Generate the table**

Run: `cd packages/ics_core && dart run tool/gen_windows_zones.dart && dart format lib/src/zones/windows_zones.g.dart`
Expected: `Downloading https://raw.githubusercontent.com/...windowsZones.xml`, then `Wrote N zones to lib/src/zones/windows_zones.g.dart` with N around 140, then `Formatted 1 file`. Open the file and check that it starts with the `GENERATED` header and contains `"Pacific Standard Time": "America/Los_Angeles",`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/ics_core && dart test test/windows_zones_test.dart && dart analyze`
Expected: `All tests passed!` then `No issues found!`
If `every IANA target exists in the bundled timezone database` fails, CLDR names a zone newer than the `timezone` package's tz data. Do not hand-edit the generated file: stop and report the missing names to the user.

- [ ] **Step 7: Commit**

```bash
git add packages/ics_core/tool/gen_windows_zones.dart packages/ics_core/lib/src/zones/windows_zones.g.dart packages/ics_core/lib/src/zones/zone_resolver.dart packages/ics_core/test/windows_zones_test.dart
git commit -m "Generate the Windows to IANA zone table from CLDR" -m "tool/gen_windows_zones.dart downloads unicode-org/cldr windowsZones.xml and writes a const map from its territory 001 rows. A test checks that every target exists in the timezone package's latest_all database."
```

---

### Task 6: Time zones: wall-clock conversion and TZID resolution

**Files:**
- Create: `packages/ics_core/lib/src/zones/wall_zone.dart`
- Replace: `packages/ics_core/lib/src/zones/zone_resolver.dart`
- Test: `packages/ics_core/test/zones_test.dart`

**Interfaces:**
- Consumes: `Component`, `parseCalendar` (Task 3); `IcsTime`, `parseIcsTime`, `parseRrule` (Task 4); `windowsToIana` (Task 5); `IcsWarning` (Task 1); `package:timezone` (`tz.getLocation`, `tz.TZDateTime(location, y, m, d, h, mi, s)`, `tz.TZDateTime.from(utc, location)`, `tz.LocationNotFoundException`, `tz.timeZoneDatabase.locations`).
- Produces: `abstract interface class WallZone { DateTime wallToUtc(DateTime wall); DateTime utcToWall(DateTime utc); }`; `class UtcZone`, `class IanaZone(tz.Location)`, `class VtimezoneZone` with `factory VtimezoneZone.fromComponent(Component)` (throws `FormatException`) and `Duration offsetAt(DateTime utc)`; `Duration parseUtcOffset(String)`; `class ResolvedZone { const ResolvedZone(WallZone zone, [IcsWarning? warning]); }`; `void ensureTimeZonesLoaded()`; `class ZoneResolver({required String deviceZone, required Map<String, Component> vtimezones})` with `final IanaZone device`, `ResolvedZone forTime(IcsTime)` and `ResolvedZone resolve(String tzid)`. The constructor throws `ArgumentError` for a non-IANA `deviceZone`.

Resolution order (document it in the code, as below): Windows name → IANA (no warning); IANA name used directly (no warning); the feed's VTIMEZONE with that TZID (`IcsWarning.tzFromVtimezone`); the device zone (`IcsWarning.tzFromDevice`). `Z` values are UTC. Floating values (no TZID, no `Z`) and DATE values use the device zone with no warning. The `latest_all` database is needed because CLDR maps some zones to old link names (`Asia/Calcutta`, `Asia/Katmandu`, `Europe/Kiev`, …) that the default `latest` database lacks; this was checked while planning.

- [ ] **Step 1: Write the failing test**

`packages/ics_core/test/zones_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:ics_core/src/values.dart';
import 'package:ics_core/src/zones/wall_zone.dart';
import 'package:ics_core/src/zones/zone_resolver.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as small_db;
import 'package:timezone/timezone.dart' as tz;

/// Outlook's own VTIMEZONE for US Pacific time, under a custom name.
const customPacific = '''
BEGIN:VCALENDAR
BEGIN:VTIMEZONE
TZID:Customized Time Zone
BEGIN:STANDARD
DTSTART:16010101T020000
TZOFFSETFROM:-0700
TZOFFSETTO:-0800
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T020000
TZOFFSETFROM:-0800
TZOFFSETTO:-0700
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VTIMEZONE
TZID:Fixed Plus Three
BEGIN:STANDARD
DTSTART:16010101T000000
TZOFFSETFROM:+0300
TZOFFSETTO:+0300
END:STANDARD
END:VTIMEZONE
BEGIN:VTIMEZONE
TZID:Broken Zone
END:VTIMEZONE
END:VCALENDAR
''';

void main() {
  ensureTimeZonesLoaded(); // group bodies below call tz.getLocation

  test('reloads the full database if other code loaded the smaller one', () {
    small_db.initializeTimeZones();
    expect(tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta'), isFalse);
    ensureTimeZonesLoaded();
    expect(tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta'), isTrue);
  });

  group('IanaZone', () {
    final la = IanaZone(tz.getLocation('America/Los_Angeles'));

    test('converts wall time to UTC on both sides of a DST change', () {
      expect(
        la.wallToUtc(DateTime.utc(2026, 10, 26, 9)),
        DateTime.utc(2026, 10, 26, 16),
      );
      expect(
        la.wallToUtc(DateTime.utc(2026, 11, 2, 9)),
        DateTime.utc(2026, 11, 2, 17),
      );
    });

    test('a wall time in the spring-forward gap moves forward', () {
      expect(
        la.wallToUtc(DateTime.utc(2026, 3, 8, 2, 30)),
        DateTime.utc(2026, 3, 8, 10, 30),
      );
    });

    test('converts UTC back to wall time', () {
      expect(
        la.utcToWall(DateTime.utc(2026, 11, 2, 17)),
        DateTime.utc(2026, 11, 2, 9),
      );
    });
  });

  group('VtimezoneZone', () {
    final cal = parseCalendar(customPacific);
    Component zoneNamed(String id) =>
        cal.children.firstWhere((c) => c.first('TZID')!.value == id);

    test('computes offsets from STANDARD/DAYLIGHT rules', () {
      final zone = VtimezoneZone.fromComponent(
        zoneNamed('Customized Time Zone'),
      );
      expect(
        zone.wallToUtc(DateTime.utc(2026, 10, 13, 9)),
        DateTime.utc(2026, 10, 13, 16),
      );
      expect(
        zone.wallToUtc(DateTime.utc(2026, 11, 10, 9)),
        DateTime.utc(2026, 11, 10, 17),
      );
      expect(
        zone.wallToUtc(DateTime.utc(2027, 1, 15, 9)),
        DateTime.utc(2027, 1, 15, 17),
      );
      expect(
        zone.utcToWall(DateTime.utc(2026, 7, 1, 16)),
        DateTime.utc(2026, 7, 1, 9),
      );
    });

    test('a single STANDARD block without RRULE is a fixed offset', () {
      final zone = VtimezoneZone.fromComponent(zoneNamed('Fixed Plus Three'));
      expect(
        zone.wallToUtc(DateTime.utc(2026, 10, 13, 9)),
        DateTime.utc(2026, 10, 13, 6),
      );
    });

    test('a VTIMEZONE with no blocks is rejected', () {
      expect(
        () => VtimezoneZone.fromComponent(zoneNamed('Broken Zone')),
        throwsFormatException,
      );
    });

    test('parseUtcOffset reads signed hours, minutes and seconds', () {
      expect(parseUtcOffset('+0200'), const Duration(hours: 2));
      expect(parseUtcOffset('-0730'), -const Duration(hours: 7, minutes: 30));
      expect(
        parseUtcOffset('+053045'),
        const Duration(hours: 5, minutes: 30, seconds: 45),
      );
      expect(() => parseUtcOffset('2'), throwsFormatException);
    });
  });

  group('ZoneResolver', () {
    final cal = parseCalendar(customPacific);
    ZoneResolver resolver() => ZoneResolver(
      deviceZone: 'Africa/Johannesburg',
      vtimezones: {for (final c in cal.children) c.first('TZID')!.value: c},
    );
    final wall = DateTime.utc(2026, 10, 13, 10);

    DateTime utcFor(ResolvedZone r) => r.zone.wallToUtc(wall);

    test('1. Windows name → IANA, no warning', () {
      final r = resolver().resolve('W. Europe Standard Time');
      expect(r.warning, isNull);
      expect(utcFor(r), DateTime.utc(2026, 10, 13, 8));
    });

    test('2. IANA name used directly, no warning', () {
      final r = resolver().resolve('Europe/London');
      expect(r.warning, isNull);
      expect(utcFor(r), DateTime.utc(2026, 10, 13, 9));
    });

    test('3. otherwise the feed VTIMEZONE, with tzFromVtimezone', () {
      final r = resolver().resolve('Customized Time Zone');
      expect(r.warning, IcsWarning.tzFromVtimezone);
      expect(utcFor(r), DateTime.utc(2026, 10, 13, 17));
    });

    test('4. otherwise the device zone, with tzFromDevice', () {
      for (final id in ['Mars Standard Time', 'Broken Zone']) {
        final r = resolver().resolve(id);
        expect(r.warning, IcsWarning.tzFromDevice, reason: id);
        expect(utcFor(r), DateTime.utc(2026, 10, 13, 8), reason: id);
      }
    });

    test('UTC, floating and DATE values', () {
      final z = resolver();
      final utc = z.forTime(parseIcsTime('20261013T100000Z'));
      expect(
        (utcFor(utc), utc.warning),
        (DateTime.utc(2026, 10, 13, 10), null),
      );
      final floating = z.forTime(parseIcsTime('20261013T100000'));
      expect(
        (utcFor(floating), floating.warning),
        (DateTime.utc(2026, 10, 13, 8), null),
      );
      final date = z.forTime(parseIcsTime('20261013'));
      expect(date.zone, same(z.device));
      expect(date.warning, isNull);
    });

    test('rejects a device zone that is not an IANA name', () {
      expect(
        () => ZoneResolver(deviceZone: 'SAST', vtimezones: const {}),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/zones_test.dart`
Expected: FAIL, compilation error: `lib/src/zones/wall_zone.dart` not found.

- [ ] **Step 3: Implement wall-clock zones**

`packages/ics_core/lib/src/zones/wall_zone.dart`:

```dart
import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../component.dart';
import '../values.dart';

/// Converts between wall-clock times and UTC instants for one zone.
///
/// Wall-clock times are carried in UTC [DateTime]s whose fields are the
/// local date and time (the same convention `package:rrule` uses).
abstract interface class WallZone {
  /// The real UTC instant for a wall-clock time in this zone.
  DateTime wallToUtc(DateTime wall);

  /// This zone's wall-clock time at a UTC instant.
  DateTime utcToWall(DateTime utc);
}

/// UTC itself: wall time and instant are the same.
class UtcZone implements WallZone {
  const UtcZone();

  @override
  DateTime wallToUtc(DateTime wall) => wall;

  @override
  DateTime utcToWall(DateTime utc) => utc.toUtc();
}

/// A zone from the IANA database (`package:timezone`).
///
/// A wall time inside a spring-forward gap moves forward by the gap
/// (02:30 becomes 03:30); an ambiguous fall-back time uses the first
/// (daylight) offset. This is `TZDateTime`'s behaviour.
class IanaZone implements WallZone {
  IanaZone(this.location);

  final tz.Location location;

  @override
  DateTime wallToUtc(DateTime wall) {
    final local = tz.TZDateTime(
      location,
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    );
    return DateTime.fromMillisecondsSinceEpoch(
      local.millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  @override
  DateTime utcToWall(DateTime utc) {
    final local = tz.TZDateTime.from(utc, location);
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
  }
}

/// One STANDARD or DAYLIGHT block of a VTIMEZONE.
class _Observance {
  const _Observance({
    required this.startWall,
    required this.offsetFrom,
    required this.offsetTo,
    this.rule,
  });

  /// DTSTART: the first onset, in the wall time in force before it.
  final DateTime startWall;
  final Duration offsetFrom;
  final Duration offsetTo;

  /// The yearly onset rule, or null for a single onset at [startWall].
  final RecurrenceRule? rule;
}

/// A zone computed from a feed's own VTIMEZONE definition.
///
/// Supports STANDARD/DAYLIGHT blocks with DTSTART, TZOFFSETFROM, TZOFFSETTO
/// and an optional yearly RRULE (which is what Outlook writes). RDATE is
/// not supported.
class VtimezoneZone implements WallZone {
  VtimezoneZone._(this._observances);

  final List<_Observance> _observances;
  final Map<int, List<(DateTime, Duration)>> _onsetsByYear = {};

  /// Builds a zone from a VTIMEZONE component.
  ///
  /// Throws [FormatException] if it has no usable STANDARD/DAYLIGHT block.
  factory VtimezoneZone.fromComponent(Component vtimezone) {
    final observances = <_Observance>[];
    for (final block in vtimezone.children) {
      if (block.name != 'STANDARD' && block.name != 'DAYLIGHT') {
        continue;
      }
      final dtstart = block.first('DTSTART');
      final from = block.first('TZOFFSETFROM');
      final to = block.first('TZOFFSETTO');
      if (dtstart == null || from == null || to == null) {
        throw FormatException(
          '${block.name} block needs DTSTART, TZOFFSETFROM and TZOFFSETTO',
        );
      }
      final startWall = parseIcsTime(dtstart.value).wall;
      final offsetFrom = parseUtcOffset(from.value);
      final rrule = block.first('RRULE');
      observances.add(
        _Observance(
          startWall: startWall,
          offsetFrom: offsetFrom,
          offsetTo: parseUtcOffset(to.value),
          rule: rrule == null
              ? null
              : parseRrule(
                  rrule.value,
                  untilUtcToWall: (u) => u.add(offsetFrom),
                  startIsDate: false,
                ),
        ),
      );
    }
    if (observances.isEmpty) {
      throw const FormatException(
        'VTIMEZONE has no STANDARD or DAYLIGHT block',
      );
    }
    return VtimezoneZone._(observances);
  }

  /// The UTC offset in force at [utc].
  Duration offsetAt(DateTime utc) {
    (DateTime, Duration)? best;
    for (final year in [utc.year - 1, utc.year]) {
      for (final onset in _onsets(year)) {
        if (!onset.$1.isAfter(utc) &&
            (best == null || onset.$1.isAfter(best.$1))) {
          best = onset;
        }
      }
    }
    if (best != null) {
      return best.$2;
    }
    // Before every rule-based onset we looked at: use the latest single
    // onset that has happened, else the first block's TZOFFSETFROM.
    _Observance? latest;
    for (final o in _observances) {
      final onsetUtc = o.startWall.subtract(o.offsetFrom);
      if (!onsetUtc.isAfter(utc) &&
          (latest == null ||
              onsetUtc.isAfter(latest.startWall.subtract(latest.offsetFrom)))) {
        latest = o;
      }
    }
    return latest?.offsetTo ?? _observances.first.offsetFrom;
  }

  List<(DateTime, Duration)> _onsets(int year) =>
      _onsetsByYear.putIfAbsent(year, () {
        final from = DateTime.utc(year);
        final to = DateTime.utc(year + 1);
        final result = <(DateTime, Duration)>[];
        for (final o in _observances) {
          final walls = o.rule == null
              ? [o.startWall]
              : o.rule!
                    .getInstances(
                      start: o.startWall,
                      after: from,
                      includeAfter: true,
                      before: to,
                    )
                    .toList();
          for (final wall in walls) {
            if (!wall.isBefore(from) && wall.isBefore(to)) {
              result.add((wall.subtract(o.offsetFrom), o.offsetTo));
            }
          }
        }
        return result;
      });

  @override
  DateTime wallToUtc(DateTime wall) {
    final guess = offsetAt(wall);
    final utc = wall.subtract(guess);
    final actual = offsetAt(utc);
    return actual == guess ? utc : wall.subtract(actual);
  }

  @override
  DateTime utcToWall(DateTime utc) => utc.toUtc().add(offsetAt(utc));
}

final _offsetPattern = RegExp(r'^([+-])(\d{2})(\d{2})(\d{2})?$');

/// Parses a UTC-OFFSET value such as `+0200`, `-0700` or `+053000`.
Duration parseUtcOffset(String value) {
  final m = _offsetPattern.firstMatch(value.trim());
  if (m == null) {
    throw FormatException('Bad UTC offset: "$value"');
  }
  final d = Duration(
    hours: int.parse(m[2]!),
    minutes: int.parse(m[3]!),
    seconds: m[4] == null ? 0 : int.parse(m[4]!),
  );
  return m[1] == '-' ? -d : d;
}
```

- [ ] **Step 4: Implement the resolver (replace the whole file)**

`packages/ics_core/lib/src/zones/zone_resolver.dart`:

```dart
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../component.dart';
import '../model.dart';
import '../values.dart';
import 'wall_zone.dart';
import 'windows_zones.g.dart';

/// A zone plus the warning its resolution earned, if any.
class ResolvedZone {
  const ResolvedZone(this.zone, [this.warning]);

  final WallZone zone;
  final IcsWarning? warning;
}

/// Loads the full IANA database (`latest_all`) unless it is already loaded.
///
/// `latest_all` is needed because CLDR maps some Windows zones to old link
/// names such as `Asia/Calcutta`, which the smaller `latest` database lacks.
/// The check looks for such a link rather than keeping a flag, so it reloads
/// if other code later replaces the global database with a smaller one.
void ensureTimeZonesLoaded() {
  if (!tz.timeZoneDatabase.locations.containsKey('Asia/Calcutta')) {
    tzdata.initializeTimeZones();
  }
}

/// Picks the zone for each DATE-TIME in a feed.
///
/// Resolution order for a TZID:
/// 1. A Windows zone name (CLDR windowsZones, territory 001) → its IANA zone.
/// 2. An IANA zone name used directly.
/// 3. The feed's own VTIMEZONE with that TZID → [IcsWarning.tzFromVtimezone].
/// 4. The device zone → [IcsWarning.tzFromDevice].
///
/// Values ending in `Z` are UTC. Floating values (no TZID, no `Z`) and DATE
/// values use the device zone with no warning.
class ZoneResolver {
  ZoneResolver({required String deviceZone, required this.vtimezones})
    : device = IanaZone(_location(deviceZone));

  /// The feed's VTIMEZONE components by TZID.
  final Map<String, Component> vtimezones;
  final Map<String, ResolvedZone> _cache = {};

  /// The viewer's zone.
  final IanaZone device;

  static tz.Location _location(String deviceZone) {
    ensureTimeZonesLoaded();
    try {
      return tz.getLocation(deviceZone);
    } on tz.LocationNotFoundException {
      throw ArgumentError.value(
        deviceZone,
        'deviceZone',
        'is not an IANA time zone name',
      );
    }
  }

  /// The zone for one parsed value.
  ResolvedZone forTime(IcsTime time) {
    if (time.isUtc) {
      return const ResolvedZone(UtcZone());
    }
    if (time.isDate || time.tzid == null) {
      return ResolvedZone(device);
    }
    return resolve(time.tzid!);
  }

  /// The zone for a TZID, following the resolution order above.
  ResolvedZone resolve(String tzid) =>
      _cache.putIfAbsent(tzid, () => _resolveUncached(tzid.trim()));

  ResolvedZone _resolveUncached(String tzid) {
    final iana = windowsToIana[tzid] ?? tzid;
    try {
      return ResolvedZone(IanaZone(tz.getLocation(iana)));
    } on tz.LocationNotFoundException {
      // Not a known name; try the feed's definition.
    }
    final vtimezone = vtimezones[tzid];
    if (vtimezone != null) {
      try {
        return ResolvedZone(
          VtimezoneZone.fromComponent(vtimezone),
          IcsWarning.tzFromVtimezone,
        );
      } on FormatException {
        // Unusable definition; fall through to the device zone.
      }
    }
    return ResolvedZone(device, IcsWarning.tzFromDevice);
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/ics_core && dart test test/zones_test.dart test/windows_zones_test.dart && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/ics_core/lib/src/zones packages/ics_core/test/zones_test.dart
git commit -m "Resolve ICS time zones in ics_core" -m "Converts between wall-clock time and UTC for UTC, IANA and VTIMEZONE-defined zones. A TZID resolves as a Windows name, then an IANA name, then the feed's VTIMEZONE (tzFromVtimezone), then the device zone (tzFromDevice). Floating and DATE values use the device zone without a warning."
```

---

### Task 7: Event fields and VEVENT parsing

**Files:**
- Create: `packages/ics_core/lib/src/event_fields.dart`
- Create: `packages/ics_core/lib/src/vevent.dart`
- Test: `packages/ics_core/test/event_fields_test.dart`
- Test: `packages/ics_core/test/vevent_test.dart`

**Interfaces:**
- Consumes: `ContentLine`, `unescapeText`, `parseContentLine` (Task 2); `Component`, `parseCalendar` (Task 3); `IcsTime`, `parseIcsTimes`, `parseIcsDuration` (Task 4); `IcsBusyStatus` (Task 1).
- Produces: `String? textOf(ContentLine?)`; `bool isCancelledTitle(String)`; `IcsBusyStatus busyStatusOf(Component)`; `String? organizerOf(ContentLine?)`; `String? extractTeamsJoinUrl(String? description, String? location)`; `class ParsedEvent` (fields `line`, `uid`, `start`, `end?`, `duration?`, `recurrenceId?`, `rrule?`, `exdates`, `cancelled`, `title`, `location?`, `description?`, `organizer?`, `joinUrl?`, `busyStatus`, getter `allDay`); `String? uidOf(Component)`; `ParsedEvent parseVevent(Component)` (throws `FormatException`).

- [ ] **Step 1: Write the failing tests**

`packages/ics_core/test/event_fields_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:ics_core/src/content_line.dart';
import 'package:ics_core/src/event_fields.dart';
import 'package:test/test.dart';

Component event(List<String> lines) => parseCalendar(
  [
    'BEGIN:VCALENDAR',
    'BEGIN:VEVENT',
    ...lines,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n'),
).children.single;

void main() {
  group('isCancelledTitle', () {
    test('matches Canceled:/Cancelled: in any case after trimming', () {
      for (final t in [
        'Canceled: Design review',
        'Cancelled: Budget',
        '  CANCELLED: Budget sync',
        'cancelled:lowercase',
      ]) {
        expect(isCancelledTitle(t), isTrue, reason: t);
      }
    });

    test('does not match other titles', () {
      for (final t in [
        'Cancellation policy review',
        'Re: Canceled: thing',
        'Canceled',
        '',
      ]) {
        expect(isCancelledTitle(t), isFalse, reason: t);
      }
    });
  });

  group('busyStatusOf', () {
    test('reads X-MICROSOFT-CDO-BUSYSTATUS', () {
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:FREE'])),
        IcsBusyStatus.free,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE'])),
        IcsBusyStatus.tentative,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:BUSY'])),
        IcsBusyStatus.busy,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:OOF'])),
        IcsBusyStatus.oof,
      );
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:WORKINGELSEWHERE'])),
        IcsBusyStatus.busy,
      );
    });

    test('the CDO value wins over TRANSP', () {
      expect(
        busyStatusOf(
          event(['TRANSP:TRANSPARENT', 'X-MICROSOFT-CDO-BUSYSTATUS:BUSY']),
        ),
        IcsBusyStatus.busy,
      );
    });

    test('falls back to TRANSP:TRANSPARENT → free, else unknown', () {
      expect(busyStatusOf(event(['TRANSP:TRANSPARENT'])), IcsBusyStatus.free);
      expect(busyStatusOf(event(['TRANSP:OPAQUE'])), IcsBusyStatus.unknown);
      expect(
        busyStatusOf(event(['X-MICROSOFT-CDO-BUSYSTATUS:ODD'])),
        IcsBusyStatus.unknown,
      );
    });
  });

  group('organizerOf', () {
    test('prefers the quoted CN', () {
      expect(
        organizerOf(
          parseContentLine(
            'ORGANIZER;CN="Thandi M.":mailto:thandi@example.com',
            1,
          ),
        ),
        'Thandi M.',
      );
    });

    test('else the address without mailto:', () {
      expect(
        organizerOf(parseContentLine('ORGANIZER:MAILTO:pieter@example.com', 1)),
        'pieter@example.com',
      );
      expect(organizerOf(null), isNull);
    });
  });

  group('textOf', () {
    test('unescapes and trims; blank is null', () {
      expect(
        textOf(parseContentLine(r'LOCATION: Room 4\; Building B ', 1)),
        'Room 4; Building B',
      );
      expect(textOf(parseContentLine('LOCATION:  ', 1)), isNull);
    });
  });

  group('extractTeamsJoinUrl', () {
    const url =
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA1ZTI4%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d';

    test('finds the Outlook <...> link and strips the >', () {
      expect(
        extractTeamsJoinUrl(
          'Microsoft Teams meeting\nClick here to join the meeting<$url>\nMeeting ID: 1',
          null,
        ),
        url,
      );
    });

    test('strips trailing sentence punctuation', () {
      expect(extractTeamsJoinUrl('Join at $url.', null), url);
      expect(extractTeamsJoinUrl('(join: $url)', null), url);
    });

    test('decodes a link percent-encoded inside a Safe Links wrapper', () {
      expect(
        extractTeamsJoinUrl(
          '<https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_SAFE%2540thread.v2%2F0&data=05%7C01>',
          null,
        ),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SAFE%40thread.v2/0',
      );
    });

    test('skips a link with broken percent-encoding and keeps looking', () {
      expect(
        extractTeamsJoinUrl(
          'https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F%zz',
          'https://teams.microsoft.com/l/meetup-join/loc',
        ),
        'https://teams.microsoft.com/l/meetup-join/loc',
      );
    });

    test('finds the newer /meet/ link', () {
      const meet = 'https://teams.microsoft.com/meet/3456789012345?p=AbCdEfGh';
      expect(
        extractTeamsJoinUrl('Join the meeting now <$meet>
Meeting ID: 345', null),
        meet,
      );
      expect(
        extractTeamsJoinUrl(
          '<https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fmeet%2F3456789012345%3Fp%3DAbCd&data=05>',
          null,
        ),
        'https://teams.microsoft.com/meet/3456789012345?p=AbCd',
      );
    });

    test('a Teams page that is not a join link is ignored', () {
      expect(
        extractTeamsJoinUrl(
          'Help: https://teams.microsoft.com/meeting-options/?x=1 and https://teams.microsoft.com/l/channel/19%3a1',
          null,
        ),
        isNull,
      );
    });

    test('DESCRIPTION first, then LOCATION', () {
      expect(extractTeamsJoinUrl('no link', '$url;'), url);
      expect(
        extractTeamsJoinUrl(
          url,
          'https://teams.microsoft.com/l/meetup-join/other',
        ),
        url,
      );
    });

    test('null when there is no Teams join link', () {
      expect(
        extractTeamsJoinUrl(
          'https://zoom.us/j/1 https://teams.microsoft.com/',
          'Microsoft Teams Meeting',
        ),
        isNull,
      );
      expect(extractTeamsJoinUrl(null, null), isNull);
    });
  });
}
```

`packages/ics_core/test/vevent_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:ics_core/src/component.dart';
import 'package:ics_core/src/vevent.dart';
import 'package:test/test.dart';

Component event(List<String> lines) => parseCalendar(
  [
    'BEGIN:VCALENDAR',
    'BEGIN:VEVENT',
    ...lines,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n'),
).children.single;

void main() {
  test('reads every field the expander needs', () {
    final e = parseVevent(
      event([
        'UID:abc',
        r'SUMMARY:Sprint planning\, Q4',
        'DTSTART;TZID=W. Europe Standard Time:20261013T090000',
        'DTEND;TZID=W. Europe Standard Time:20261013T100000',
        'RRULE:FREQ=WEEKLY;BYDAY=TU',
        'EXDATE;TZID=W. Europe Standard Time:20261020T090000,20261027T090000',
        'EXDATE;TZID=W. Europe Standard Time:20261103T090000',
        'LOCATION:Room 2',
        r'DESCRIPTION:Join<https://teams.microsoft.com/l/meetup-join/x>\nThanks',
        'ORGANIZER;CN="Thandi M.":mailto:thandi@example.com',
        'X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE',
      ]),
    );
    expect(e.uid, 'abc');
    expect(e.line, 2);
    expect(e.title, 'Sprint planning, Q4');
    expect(e.start.tzid, 'W. Europe Standard Time');
    expect(e.end!.wall, DateTime.utc(2026, 10, 13, 10));
    expect(e.rrule, 'FREQ=WEEKLY;BYDAY=TU');
    expect(e.exdates.map((t) => t.wall.day), [20, 27, 3]);
    expect(e.location, 'Room 2');
    expect(
      e.description,
      'Join<https://teams.microsoft.com/l/meetup-join/x>\nThanks',
    );
    expect(e.joinUrl, 'https://teams.microsoft.com/l/meetup-join/x');
    expect(e.organizer, 'Thandi M.');
    expect(e.busyStatus, IcsBusyStatus.tentative);
    expect(e.cancelled, isFalse);
    expect(e.allDay, isFalse);
    expect(e.recurrenceId, isNull);
  });

  test('STATUS:CANCELLED or a Canceled: title marks it cancelled', () {
    expect(
      parseVevent(event(['UID:a', 'DTSTART:20261013', 'status:cancelled']))
          .cancelled,
      isTrue,
    );
    expect(
      parseVevent(event(['UID:a', 'DTSTART:20261013', 'SUMMARY:Canceled: x']))
          .cancelled,
      isTrue,
    );
  });

  test('reads RECURRENCE-ID and DURATION', () {
    final e = parseVevent(
      event([
        'UID:a',
        'RECURRENCE-ID;TZID=Europe/London:20261013T090000',
        'DTSTART;TZID=Europe/London:20261014T090000',
        'DURATION:PT45M',
      ]),
    );
    expect(e.recurrenceId!.wall, DateTime.utc(2026, 10, 13, 9));
    expect(e.duration, const Duration(minutes: 45));
  });

  test('a missing SUMMARY is an empty title', () {
    expect(parseVevent(event(['UID:a', 'DTSTART:20261013'])).title, '');
  });

  test('a missing UID gets a stable stand-in from DTSTART and SUMMARY', () {
    List<String> lines() => ['SUMMARY:No uid', 'DTSTART:20261013T090000Z'];
    final a = parseVevent(event(lines()));
    final b = parseVevent(event(lines()));
    expect(a.uid, 'no-uid:20261013T090000Z|No uid');
    expect(a.uid, b.uid);
  });

  test('no DTSTART, a bad DTEND or a bad DURATION throw FormatException', () {
    expect(() => parseVevent(event(['UID:a'])), throwsFormatException);
    expect(
      () => parseVevent(
        event(['UID:a', 'DTSTART:20261013T090000Z', 'DTEND:tomorrow']),
      ),
      throwsFormatException,
    );
    expect(
      () => parseVevent(
        event(['UID:a', 'DTSTART:20261013T090000Z', 'DURATION:1h']),
      ),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/ics_core && dart test test/event_fields_test.dart test/vevent_test.dart`
Expected: FAIL, compilation errors: `lib/src/event_fields.dart` and `lib/src/vevent.dart` not found.

- [ ] **Step 3: Implement event fields**

`packages/ics_core/lib/src/event_fields.dart`:

```dart
import 'component.dart';
import 'content_line.dart';
import 'model.dart';

/// The unescaped, trimmed TEXT value of [line]; null if absent or blank.
String? textOf(ContentLine? line) {
  if (line == null) {
    return null;
  }
  final text = unescapeText(line.value).trim();
  return text.isEmpty ? null : text;
}

final _cancelledTitle = RegExp(r'^cancell?ed:', caseSensitive: false);

/// True for titles Outlook gives cancelled meetings: `Canceled: …` or
/// `Cancelled: …` (any case, after trimming).
bool isCancelledTitle(String title) => _cancelledTitle.hasMatch(title.trim());

/// X-MICROSOFT-CDO-BUSYSTATUS, else TRANSP:TRANSPARENT → free, else unknown.
///
/// Outlook's WORKINGELSEWHERE counts as busy.
IcsBusyStatus busyStatusOf(Component event) {
  final cdo = event
      .first('X-MICROSOFT-CDO-BUSYSTATUS')
      ?.value
      .trim()
      .toUpperCase();
  switch (cdo) {
    case 'FREE':
      return IcsBusyStatus.free;
    case 'TENTATIVE':
      return IcsBusyStatus.tentative;
    case 'BUSY' || 'WORKINGELSEWHERE':
      return IcsBusyStatus.busy;
    case 'OOF':
      return IcsBusyStatus.oof;
  }
  if (event.first('TRANSP')?.value.trim().toUpperCase() == 'TRANSPARENT') {
    return IcsBusyStatus.free;
  }
  return IcsBusyStatus.unknown;
}

/// ORGANIZER's CN parameter if present, else its address without `mailto:`.
String? organizerOf(ContentLine? line) {
  if (line == null) {
    return null;
  }
  final cn = line.params['CN']?.trim();
  if (cn != null && cn.isNotEmpty) {
    return cn;
  }
  final value = line.value.trim();
  final address = value.toLowerCase().startsWith('mailto:')
      ? value.substring(7)
      : value;
  return address.isEmpty ? null : address;
}

final _teamsDirect = RegExp(
  r'https://teams\.microsoft\.com/(?:l/meetup-join|meet)/[^\s<>"]+',
  caseSensitive: false,
);
final _teamsEncoded = RegExp(
  r'https%3A%2F%2Fteams\.microsoft\.com%2F(?:l%2Fmeetup-join|meet)%2F[^\s<>"&]+',
  caseSensitive: false,
);
const _trailingPunctuation = '>)].,;:!?\'';

/// The first Teams join URL in [description], then in [location].
///
/// Finds `https://teams.microsoft.com/l/meetup-join/…` or the newer
/// `https://teams.microsoft.com/meet/…` as written (Outlook
/// wraps it in `<…>`, and its path is usually percent-encoded, which is kept
/// as is), or fully percent-encoded inside another link such as a Safe Links
/// wrapper (decoded). Trailing `>` and sentence punctuation are removed.
String? extractTeamsJoinUrl(String? description, String? location) {
  for (final text in [description, location]) {
    if (text == null) {
      continue;
    }
    final direct = _teamsDirect.firstMatch(text);
    if (direct != null) {
      return _trimTrailing(direct[0]!);
    }
    final encoded = _teamsEncoded.firstMatch(text);
    if (encoded != null) {
      try {
        return _trimTrailing(Uri.decodeComponent(encoded[0]!));
      } on ArgumentError {
        // Malformed percent-encoding; keep looking.
      }
    }
  }
  return null;
}

String _trimTrailing(String url) {
  var end = url.length;
  while (end > 0 && _trailingPunctuation.contains(url[end - 1])) {
    end--;
  }
  return url.substring(0, end);
}
```

- [ ] **Step 4: Implement VEVENT parsing**

`packages/ics_core/lib/src/vevent.dart`:

```dart
import 'component.dart';
import 'event_fields.dart';
import 'model.dart';
import 'values.dart';

/// One VEVENT, with its values parsed but no zones applied yet.
class ParsedEvent {
  const ParsedEvent({
    required this.line,
    required this.uid,
    required this.start,
    this.end,
    this.duration,
    this.recurrenceId,
    this.rrule,
    this.exdates = const [],
    required this.cancelled,
    required this.title,
    this.location,
    this.description,
    this.organizer,
    this.joinUrl,
    required this.busyStatus,
  });

  /// Line where `BEGIN:VEVENT` appeared.
  final int line;
  final String uid;
  final IcsTime start;
  final IcsTime? end;
  final Duration? duration;
  final IcsTime? recurrenceId;

  /// The raw RRULE value, if any.
  final String? rrule;
  final List<IcsTime> exdates;

  /// STATUS:CANCELLED or a `Canceled:` / `Cancelled:` title.
  final bool cancelled;
  final String title;
  final String? location;
  final String? description;
  final String? organizer;
  final String? joinUrl;
  final IcsBusyStatus busyStatus;

  bool get allDay => start.isDate;
}

/// The UID of [event], or null if it has none.
String? uidOf(Component event) {
  final uid = event.first('UID')?.value.trim();
  return uid == null || uid.isEmpty ? null : uid;
}

/// Parses one VEVENT. Throws [FormatException] if it cannot be used.
///
/// A missing UID gets a stable stand-in built from DTSTART and SUMMARY.
ParsedEvent parseVevent(Component event) {
  final dtstart = event.first('DTSTART');
  if (dtstart == null) {
    throw const FormatException('VEVENT has no DTSTART');
  }
  final start = parseIcsTimes(dtstart).firstOrNull;
  if (start == null) {
    throw const FormatException('DTSTART is empty');
  }
  final dtend = event.first('DTEND');
  final durationLine = event.first('DURATION');
  final recurrenceLine = event.first('RECURRENCE-ID');
  final title = textOf(event.first('SUMMARY')) ?? '';
  final location = textOf(event.first('LOCATION'));
  final description = textOf(event.first('DESCRIPTION'));
  final status = event.first('STATUS')?.value.trim().toUpperCase();
  return ParsedEvent(
    line: event.line,
    uid: uidOf(event) ?? 'no-uid:${dtstart.value.trim()}|$title',
    start: start,
    end: dtend == null ? null : parseIcsTimes(dtend).firstOrNull,
    duration: durationLine == null
        ? null
        : parseIcsDuration(durationLine.value),
    recurrenceId: recurrenceLine == null
        ? null
        : parseIcsTimes(recurrenceLine).firstOrNull,
    rrule: event.first('RRULE')?.value,
    exdates: [for (final ex in event.all('EXDATE')) ...parseIcsTimes(ex)],
    cancelled: status == 'CANCELLED' || isCancelledTitle(title),
    title: title,
    location: location,
    description: description,
    organizer: organizerOf(event.first('ORGANIZER')),
    joinUrl: extractTeamsJoinUrl(description, location),
    busyStatus: busyStatusOf(event),
  );
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/ics_core && dart test test/event_fields_test.dart test/vevent_test.dart && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/ics_core/lib/src/event_fields.dart packages/ics_core/lib/src/vevent.dart packages/ics_core/test/event_fields_test.dart packages/ics_core/test/vevent_test.dart
git commit -m "Read VEVENT fields in ics_core" -m "Cancelled titles, busy status (CDO, then TRANSP), organizer CN or address, and the first Teams join URL (meetup-join or meet) in DESCRIPTION then LOCATION, including Outlook's <...> wrapping and Safe Links. parseVevent collects DTSTART, DTEND, DURATION, RRULE, EXDATE and RECURRENCE-ID, with a stable stand-in UID when one is missing."
```

---

### Task 8: `expandIcs` for one-off events

**Files:**
- Create: `packages/ics_core/lib/src/expander.dart`
- Create: `packages/ics_core/lib/src/expand_ics.dart`
- Replace: `packages/ics_core/lib/ics_core.dart`
- Create: `packages/ics_core/test/support.dart`
- Create fixtures: `packages/ics_core/test/fixtures/windows_tzids.ics`, `all_day_multi_day.ics`, `canceled_titles.ics`, `teams_links.ics`, `folded_lines.ics`, `malformed.ics`
- Test: `packages/ics_core/test/expand_single_test.dart`

**Interfaces:**
- Consumes: `parseCalendar` (Task 3); `ZoneResolver`, `ResolvedZone` (Task 6); `ParsedEvent`, `parseVevent`, `uidOf` (Task 7); model types (Task 1).
- Produces: public `IcsResult expandIcs(String icsText, {required DateTime windowStartUtc, required DateTime windowEndUtc, required String deviceZone})`; in `expander.dart`: `class IcsWindow(DateTime start, DateTime end)` with `bool overlaps(DateTime startUtc, DateTime endUtc)` (throws `ArgumentError` for an empty window), private helpers `_Timing`, `_date`, `_allDayLength`, `_timingOf`, `_occurrence`, and `List<IcsOccurrence> expandSingle(ParsedEvent, ZoneResolver, IcsWindow)`. Test helpers in `test/support.dart`: `fixture`, `expandFixture`, `calendar`, `byUid`, `startsOf`.

In this task, events with an RRULE and RECURRENCE-ID overrides are skipped on purpose; Tasks 9 and 10 add them. None of this task's fixtures contain either.

- [ ] **Step 1: Add the fixtures**

Create each file under `packages/ics_core/test/fixtures/` with exactly this content.

`windows_tzids.ics`:

```text
BEGIN:VCALENDAR
METHOD:PUBLISH
PRODID:Microsoft Exchange Server 2010
VERSION:2.0
X-WR-CALNAME:Calendar
BEGIN:VTIMEZONE
TZID:Customized Time Zone
BEGIN:STANDARD
DTSTART:16010101T020000
TZOFFSETFROM:-0700
TZOFFSETTO:-0800
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T020000
TZOFFSETFROM:-0800
TZOFFSETTO:-0700
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
UID:berlin
SUMMARY:Berlin review
DTSTART;TZID=W. Europe Standard Time:20261013T100000
DTEND;TZID=W. Europe Standard Time:20261013T110000
END:VEVENT
BEGIN:VEVENT
UID:london
SUMMARY:London sync
DTSTART;TZID=Europe/London:20261013T100000
DTEND;TZID=Europe/London:20261013T103000
END:VEVENT
BEGIN:VEVENT
UID:india
SUMMARY:Pune handover
DTSTART;TZID="India Standard Time":20261013T100000
DTEND;TZID="India Standard Time":20261013T110000
END:VEVENT
BEGIN:VEVENT
UID:custom-oct
SUMMARY:Custom zone before DST ends
DTSTART;TZID=Customized Time Zone:20261013T090000
DTEND;TZID=Customized Time Zone:20261013T100000
END:VEVENT
BEGIN:VEVENT
UID:custom-nov
SUMMARY:Custom zone after DST ends
DTSTART;TZID=Customized Time Zone:20261110T090000
DTEND;TZID=Customized Time Zone:20261110T100000
END:VEVENT
BEGIN:VEVENT
UID:unknown
SUMMARY:Unknown zone
DTSTART;TZID=Mars Standard Time:20261013T100000
DTEND;TZID=Mars Standard Time:20261013T110000
END:VEVENT
BEGIN:VEVENT
UID:utc
SUMMARY:UTC call
DTSTART:20261013T100000Z
DTEND:20261013T110000Z
END:VEVENT
BEGIN:VEVENT
UID:floating
SUMMARY:Floating time
DTSTART:20261013T100000
DTEND:20261013T110000
END:VEVENT
BEGIN:VEVENT
UID:mixed
SUMMARY:Starts in LA, ends in Johannesburg
DTSTART;TZID=Pacific Standard Time:20261013T090000
DTEND;TZID=South Africa Standard Time:20261013T190000
END:VEVENT
END:VCALENDAR
```

`all_day_multi_day.ics`:

```text
BEGIN:VCALENDAR
VERSION:2.0
PRODID:Microsoft Exchange Server 2010
BEGIN:VEVENT
UID:holiday
SUMMARY:Public holiday
DTSTART;VALUE=DATE:20261013
DTEND;VALUE=DATE:20261014
TRANSP:TRANSPARENT
X-MICROSOFT-CDO-BUSYSTATUS:FREE
X-MICROSOFT-CDO-ALLDAYEVENT:TRUE
END:VEVENT
BEGIN:VEVENT
UID:conference
SUMMARY:Conference
DTSTART;VALUE=DATE:20261014
DTEND;VALUE=DATE:20261017
X-MICROSOFT-CDO-BUSYSTATUS:OOF
END:VEVENT
BEGIN:VEVENT
UID:no-end
SUMMARY:Pay day
DTSTART;VALUE=DATE:20261016
END:VEVENT
BEGIN:VEVENT
UID:offsite
SUMMARY:Offsite
DTSTART;TZID=South Africa Standard Time:20261015T090000
DTEND;TZID=South Africa Standard Time:20261016T170000
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
END:VEVENT
BEGIN:VEVENT
UID:duration
SUMMARY:Workshop
DTSTART;TZID=South Africa Standard Time:20261015T110000
DURATION:PT1H30M
END:VEVENT
BEGIN:VEVENT
UID:zero
SUMMARY:Reminder
DTSTART;TZID=South Africa Standard Time:20261015T120000
END:VEVENT
END:VCALENDAR
```

`canceled_titles.ics`:

```text
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:c1
SUMMARY:Canceled: Design review
DTSTART;TZID=South Africa Standard Time:20261013T100000
DTEND;TZID=South Africa Standard Time:20261013T110000
END:VEVENT
BEGIN:VEVENT
UID:c2
SUMMARY:  CANCELLED: Budget sync
DTSTART;TZID=South Africa Standard Time:20261013T110000
DTEND;TZID=South Africa Standard Time:20261013T120000
END:VEVENT
BEGIN:VEVENT
UID:c3
SUMMARY:cancelled:lowercase
DTSTART;TZID=South Africa Standard Time:20261013T120000
DTEND;TZID=South Africa Standard Time:20261013T130000
END:VEVENT
BEGIN:VEVENT
UID:c4
SUMMARY:Retro
STATUS:CANCELLED
DTSTART;TZID=South Africa Standard Time:20261013T130000
DTEND;TZID=South Africa Standard Time:20261013T140000
END:VEVENT
BEGIN:VEVENT
UID:k1
SUMMARY:Cancellation policy review
STATUS:CONFIRMED
DTSTART;TZID=South Africa Standard Time:20261013T140000
DTEND;TZID=South Africa Standard Time:20261013T150000
END:VEVENT
BEGIN:VEVENT
UID:k2
SUMMARY:Re: Canceled: thing
DTSTART;TZID=South Africa Standard Time:20261013T150000
DTEND;TZID=South Africa Standard Time:20261013T160000
END:VEVENT
END:VCALENDAR
```

`teams_links.ics` (the DESCRIPTION is folded mid-word on purpose; every continuation line starts with exactly one space):

```text
BEGIN:VCALENDAR
VERSION:2.0
PRODID:Microsoft Exchange Server 2010
BEGIN:VEVENT
UID:outlook-desc
SUMMARY:Sprint planning
DESCRIPTION:\n___________________________________________________________________
 _____________\nMicrosoft Teams meeting\nJoin on your computer\, mobile ap
 p or room device\nClick here to join the meeting<https://teams.microsoft.com
 /l/meetup-join/19%3ameeting_NjA1ZTI4%40thread.v2/0?context=%7b%22Tid%22%3a
 %22t%22%7d>\nMeeting ID: 123 456 789\nPasscode: abc123\n
LOCATION:Microsoft Teams Meeting
ORGANIZER;CN="Thandi M.":mailto:thandi@example.com
DTSTART;TZID=South Africa Standard Time:20261013T100000
DTEND;TZID=South Africa Standard Time:20261013T110000
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
END:VEVENT
BEGIN:VEVENT
UID:location-only
SUMMARY:Location link
LOCATION:https://teams.microsoft.com/l/meetup-join/19%3ameeting_LOC%40thread.v2/0?context=%7b%7d.
DTSTART;TZID=South Africa Standard Time:20261013T110000
DTEND;TZID=South Africa Standard Time:20261013T113000
END:VEVENT
BEGIN:VEVENT
UID:safelinks
SUMMARY:Safe Links
DESCRIPTION:Join: <https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_SAFE%2540thread.v2%2F0&data=05%7C01>
DTSTART;TZID=South Africa Standard Time:20261013T120000
DTEND;TZID=South Africa Standard Time:20261013T123000
END:VEVENT
BEGIN:VEVENT
UID:both
SUMMARY:Description wins
DESCRIPTION:<https://teams.microsoft.com/l/meetup-join/19%3ameeting_DESC%40thread.v2/0>
LOCATION:https://teams.microsoft.com/l/meetup-join/19%3ameeting_OTHER%40thread.v2/0
DTSTART;TZID=South Africa Standard Time:20261013T130000
DTEND;TZID=South Africa Standard Time:20261013T133000
END:VEVENT
BEGIN:VEVENT
UID:none
SUMMARY:In person
DESCRIPTION:Bring snacks. Zoom backup: https://zoom.us/j/1
LOCATION:Boardroom
DTSTART;TZID=South Africa Standard Time:20261013T140000
DTEND;TZID=South Africa Standard Time:20261013T150000
END:VEVENT
END:VCALENDAR
```

`folded_lines.ics`:

```text
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:folded@examp
 le.com
SUMMARY:Quarterly planning: goals\, ri
 sks and next steps
ORGANIZER;CN="Than
 di M.":mailto:thandi@example.com
LOCATION:Room 4\; Building B
DESCRIPTION:Agenda:\n1. Goals\n2. Risks\N3. Join<https://teams.microsof
 t.com/l/meetup-join/19%3ameeting_FOLD%40thread.v2/0?context=%7b%7d>
DTSTART;TZID=South Africa Standard Time:20261014T090000
DTEND;TZID=South Africa Stand
 ard Time:20261014T100000
END:VEVENT
END:VCALENDAR
```

`malformed.ics` (ends mid-VEVENT on purpose, like a cut-off download):

```text
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:good-1
SUMMARY:Good one
DTSTART;TZID=South Africa Standard Time:20261013T090000
DTEND;TZID=South Africa Standard Time:20261013T100000
END:VEVENT
BEGIN:VEVENT
UID:bad-no-start
SUMMARY:No start
DTEND;TZID=South Africa Standard Time:20261013T100000
END:VEVENT
BEGIN:VEVENT
UID:bad-date
SUMMARY:Bad date
DTSTART;TZID=South Africa Standard Time:20261345T250000
END:VEVENT
BEGIN:VEVENT
UID:bad-duration
SUMMARY:Bad duration
DTSTART;TZID=South Africa Standard Time:20261013T120000
DURATION:soon
END:VEVENT
BEGIN:VEVENT
UID:good-2
SUMMARY:Good two
DTSTART;TZID=South Africa Standard Time:20261013T130000
DTEND;TZID=South Africa Standard Time:20261013T140000
END:VEVENT
BEGIN:VEVENT
UID:truncated
SUMMARY:Download cut off here
DTSTART;TZID=South Africa Standard Time:20261013T150000
```

- [ ] **Step 2: Write the test helpers and the failing test**

`packages/ics_core/test/support.dart`:

```dart
import 'dart:io';

import 'package:ics_core/ics_core.dart';

/// Reads `test/fixtures/<name>` (tests run from the package root).
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Expands a fixture for a viewer in Johannesburg (UTC+2, no DST).
IcsResult expandFixture(
  String name, {
  required DateTime from,
  required DateTime to,
  String deviceZone = 'Africa/Johannesburg',
}) => expandIcs(
  fixture(name),
  windowStartUtc: from,
  windowEndUtc: to,
  deviceZone: deviceZone,
);

/// Wraps VEVENT lines in a minimal VCALENDAR.
String calendar(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${body.trim().replaceAll('\n', '\r\n')}\r\nEND:VCALENDAR\r\n';

/// The occurrences of one UID.
List<IcsOccurrence> byUid(IcsResult r, String uid) =>
    r.occurrences.where((o) => o.uid == uid).toList();

/// Start times of one UID, as UTC ISO strings, for compact assertions.
List<String> startsOf(IcsResult r, String uid) => [
  for (final o in byUid(r, uid)) o.startUtc.toIso8601String(),
];
```

`packages/ics_core/test/expand_single_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final from = DateTime.utc(2026, 10, 12);
  final to = DateTime.utc(2026, 10, 19);

  group('time zones (windows_tzids.ics)', () {
    final r = expandFixture(
      'windows_tzids.ics',
      from: from,
      to: DateTime.utc(2026, 11, 15),
    );
    IcsOccurrence one(String uid) => byUid(r, uid).single;

    test('no issues', () => expect(r.issues, isEmpty));

    test('Windows TZID → IANA (Berlin, still on summer time)', () {
      expect(one('berlin').startUtc, DateTime.utc(2026, 10, 13, 8));
      expect(one('berlin').endUtc, DateTime.utc(2026, 10, 13, 9));
      expect(one('berlin').warnings, isEmpty);
    });

    test('IANA TZID used directly', () {
      expect(one('london').startUtc, DateTime.utc(2026, 10, 13, 9));
    });

    test('quoted Windows TZID mapped to an old IANA link name', () {
      expect(one('india').startUtc, DateTime.utc(2026, 10, 13, 4, 30));
    });

    test('custom TZID computed from the feed VTIMEZONE, flagged', () {
      expect(one('custom-oct').startUtc, DateTime.utc(2026, 10, 13, 16));
      expect(one('custom-nov').startUtc, DateTime.utc(2026, 11, 10, 17));
      expect(one('custom-oct').warnings, {IcsWarning.tzFromVtimezone});
    });

    test('unknown TZID with no VTIMEZONE uses the device zone, flagged', () {
      expect(one('unknown').startUtc, DateTime.utc(2026, 10, 13, 8));
      expect(one('unknown').warnings, {IcsWarning.tzFromDevice});
    });

    test('UTC and floating times; floating is not flagged', () {
      expect(one('utc').startUtc, DateTime.utc(2026, 10, 13, 10));
      expect(one('floating').startUtc, DateTime.utc(2026, 10, 13, 8));
      expect(one('floating').warnings, isEmpty);
    });

    test('DTSTART and DTEND may use different zones', () {
      expect(one('mixed').startUtc, DateTime.utc(2026, 10, 13, 16));
      expect(one('mixed').endUtc, DateTime.utc(2026, 10, 13, 17));
    });

    test('one-off events are not recurring; original start = start', () {
      expect(one('berlin').recurring, isFalse);
      expect(one('berlin').originalStartUtc, one('berlin').startUtc);
    });
  });

  group('all-day, multi-day and lengths (all_day_multi_day.ics)', () {
    final r = expandFixture('all_day_multi_day.ics', from: from, to: to);
    IcsOccurrence one(String uid) => byUid(r, uid).single;

    test('an all-day event spans local midnight to midnight, as UTC', () {
      final o = one('holiday');
      expect(o.allDay, isTrue);
      expect(o.startUtc, DateTime.utc(2026, 10, 12, 22));
      expect(o.endUtc, DateTime.utc(2026, 10, 13, 22));
      expect(o.busyStatus, IcsBusyStatus.free);
    });

    test('a multi-day all-day event keeps its length', () {
      expect(one('conference').startUtc, DateTime.utc(2026, 10, 13, 22));
      expect(one('conference').endUtc, DateTime.utc(2026, 10, 16, 22));
      expect(one('conference').busyStatus, IcsBusyStatus.oof);
    });

    test('an all-day event with no DTEND lasts one day', () {
      expect(
        one('no-end').endUtc.difference(one('no-end').startUtc),
        const Duration(days: 1),
      );
    });

    test('a timed event can span days', () {
      expect(one('offsite').allDay, isFalse);
      expect(one('offsite').startUtc, DateTime.utc(2026, 10, 15, 7));
      expect(one('offsite').endUtc, DateTime.utc(2026, 10, 16, 15));
    });

    test('DURATION sets the end', () {
      expect(one('duration').endUtc, DateTime.utc(2026, 10, 15, 10, 30));
    });

    test('no DTEND and no DURATION means zero length', () {
      expect(one('zero').endUtc, one('zero').startUtc);
    });

    test('all-day events follow the device zone', () {
      final london = expandFixture(
        'all_day_multi_day.ics',
        from: from,
        to: to,
        deviceZone: 'Europe/London',
      );
      expect(
        byUid(london, 'holiday').single.startUtc,
        DateTime.utc(2026, 10, 12, 23),
      );
    });
  });

  group('window semantics: overlap with [start, end)', () {
    String event(String start, String end) => calendar('''
BEGIN:VEVENT
UID:w
SUMMARY:W
DTSTART:$start
DTEND:$end
END:VEVENT''');
    List<IcsOccurrence> run(String start, String end) => expandIcs(
      event(start, end),
      windowStartUtc: DateTime.utc(2026, 10, 13, 10),
      windowEndUtc: DateTime.utc(2026, 10, 13, 12),
      deviceZone: 'Africa/Johannesburg',
    ).occurrences;

    test('ending exactly at the window start is out', () {
      expect(run('20261013T090000Z', '20261013T100000Z'), isEmpty);
    });

    test('starting exactly at the window end is out', () {
      expect(run('20261013T120000Z', '20261013T130000Z'), isEmpty);
    });

    test('started before the window and still running is in', () {
      expect(run('20261013T090000Z', '20261013T103000Z'), hasLength(1));
    });

    test('a zero-length event at the window start is in', () {
      expect(run('20261013T100000Z', '20261013T100000Z'), hasLength(1));
    });

    test(
      'DTEND before DTSTART gives a zero-length event, not a dropped one',
      () {
        final o = run('20261013T110000Z', '20261013T100000Z').single;
        expect(o.endUtc, o.startUtc);
      },
    );

    test('an empty window is an error', () {
      expect(
        () => expandIcs(
          event('20261013T100000Z', '20261013T110000Z'),
          windowStartUtc: DateTime.utc(2026, 10, 13),
          windowEndUtc: DateTime.utc(2026, 10, 13),
          deviceZone: 'Africa/Johannesburg',
        ),
        throwsArgumentError,
      );
    });
  });

  test('cancelled events and Canceled:/Cancelled: titles are dropped', () {
    final r = expandFixture('canceled_titles.ics', from: from, to: to);
    expect(r.occurrences.map((o) => o.uid), ['k1', 'k2']);
    expect(r.issues, isEmpty);
  });

  group('Teams links (teams_links.ics)', () {
    final r = expandFixture('teams_links.ics', from: from, to: to);
    String? link(String uid) => byUid(r, uid).single.joinUrl;

    test('Outlook description link, without the closing >', () {
      expect(
        link('outlook-desc'),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA1ZTI4%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d',
      );
    });

    test('location link without the trailing full stop', () {
      expect(
        link('location-only'),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_LOC%40thread.v2/0?context=%7b%7d',
      );
    });

    test('Safe Links wrapper is decoded', () {
      expect(
        link('safelinks'),
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SAFE%40thread.v2/0',
      );
    });

    test('description wins over location; none gives null', () {
      expect(link('both'), contains('meeting_DESC'));
      expect(link('none'), isNull);
    });

    test('organizer, location and description come through', () {
      final o = byUid(r, 'outlook-desc').single;
      expect(o.organizer, 'Thandi M.');
      expect(o.location, 'Microsoft Teams Meeting');
      expect(
        o.description,
        contains('Join on your computer, mobile app or room device'),
      );
      expect(o.busyStatus, IcsBusyStatus.busy);
    });
  });

  group('folded lines (folded_lines.ics)', () {
    test('unfolds names, parameters, values and URLs', () {
      final o = expandFixture(
        'folded_lines.ics',
        from: from,
        to: to,
      ).occurrences.single;
      expect(o.uid, 'folded@example.com');
      expect(o.title, 'Quarterly planning: goals, risks and next steps');
      expect(o.organizer, 'Thandi M.');
      expect(o.location, 'Room 4; Building B');
      expect(o.description, startsWith('Agenda:\n1. Goals\n2. Risks\n3. Join'));
      expect(
        o.joinUrl,
        'https://teams.microsoft.com/l/meetup-join/19%3ameeting_FOLD%40thread.v2/0?context=%7b%7d',
      );
      expect(o.endUtc, DateTime.utc(2026, 10, 14, 8));
    });

    test('CRLF and LF files give the same result', () {
      final lf = fixture('folded_lines.ics').replaceAll('\r\n', '\n');
      IcsResult run(String text) => expandIcs(
        text,
        windowStartUtc: from,
        windowEndUtc: to,
        deviceZone: 'Africa/Johannesburg',
      );
      expect(run(lf.replaceAll('\n', '\r\n')).occurrences, run(lf).occurrences);
    });
  });

  group('error isolation (malformed.ics)', () {
    final r = expandFixture('malformed.ics', from: from, to: to);

    test('good events still come through', () {
      expect(r.occurrences.map((o) => o.uid), ['good-1', 'good-2']);
    });

    test('each bad VEVENT becomes one issue with its UID and line', () {
      expect(r.issues, const [
        IcsIssue(
          uid: 'bad-no-start',
          line: 9,
          message: 'VEVENT has no DTSTART',
        ),
        IcsIssue(
          uid: 'bad-date',
          line: 14,
          message: 'Bad date or date-time: "20261345T250000"',
        ),
        IcsIssue(
          uid: 'bad-duration',
          line: 19,
          message: 'Bad DURATION: "soon"',
        ),
        IcsIssue(
          uid: 'truncated',
          line: 31,
          message: 'VEVENT has no END:VEVENT',
        ),
      ]);
    });

    test('text that is not a calendar throws IcsFormatException', () {
      expect(
        () => expandIcs(
          '<html><body>Sign in</body></html>',
          windowStartUtc: from,
          windowEndUtc: to,
          deviceZone: 'Africa/Johannesburg',
        ),
        throwsA(isA<IcsFormatException>()),
      );
    });
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/expand_single_test.dart`
Expected: FAIL, compilation error: `expandIcs` is not defined (`Method not found: 'expandIcs'`).

- [ ] **Step 4: Implement the window and one-off expansion**

`packages/ics_core/lib/src/expander.dart`:

```dart
import 'model.dart';
import 'vevent.dart';
import 'zones/zone_resolver.dart';

/// The requested window: occurrences overlapping `[start, end)` are kept.
class IcsWindow {
  IcsWindow(DateTime start, DateTime end)
    : start = start.toUtc(),
      end = end.toUtc() {
    if (!this.end.isAfter(this.start)) {
      throw ArgumentError('windowEndUtc must be after windowStartUtc');
    }
  }

  final DateTime start;
  final DateTime end;

  /// True if `[startUtc, endUtc)` overlaps the window. A zero-length event
  /// counts if it starts inside the window.
  bool overlaps(DateTime startUtc, DateTime endUtc) =>
      startUtc.isBefore(end) &&
      (endUtc.isAfter(start) || !startUtc.isBefore(start));
}

/// Start, end and warnings of one concrete instance.
class _Timing {
  const _Timing(this.startUtc, this.endUtc, this.warnings);

  final DateTime startUtc;
  final DateTime endUtc;
  final Set<IcsWarning> warnings;
}

DateTime _date(DateTime wall) => DateTime.utc(wall.year, wall.month, wall.day);

/// Number of whole days an all-day event lasts (at least 1).
int _allDayLength(ParsedEvent e) {
  final startDate = _date(e.start.wall);
  int days;
  if (e.end != null) {
    days = _date(e.end!.wall).difference(startDate).inDays;
  } else if (e.duration != null) {
    days = (e.duration!.inMinutes / Duration.minutesPerDay).ceil();
  } else {
    days = 1;
  }
  return days < 1 ? 1 : days;
}

/// When [e] itself (DTSTART/DTEND/DURATION) happens.
_Timing _timingOf(ParsedEvent e, ZoneResolver zones) {
  if (e.allDay) {
    final startDate = _date(e.start.wall);
    return _Timing(
      zones.device.wallToUtc(startDate),
      zones.device.wallToUtc(startDate.add(Duration(days: _allDayLength(e)))),
      const {},
    );
  }
  final startZone = zones.forTime(e.start);
  final warnings = {if (startZone.warning != null) startZone.warning!};
  final startUtc = startZone.zone.wallToUtc(e.start.wall);
  var endUtc = startUtc;
  if (e.end != null) {
    final endZone = e.end!.isDate ? startZone : zones.forTime(e.end!);
    if (endZone.warning != null) {
      warnings.add(endZone.warning!);
    }
    endUtc = endZone.zone.wallToUtc(e.end!.wall);
  } else if (e.duration != null) {
    endUtc = startUtc.add(e.duration!);
  }
  if (endUtc.isBefore(startUtc)) {
    endUtc = startUtc;
  }
  return _Timing(startUtc, endUtc, warnings);
}

IcsOccurrence _occurrence(
  ParsedEvent e,
  _Timing timing, {
  required DateTime originalStartUtc,
  required bool recurring,
}) => IcsOccurrence(
  uid: e.uid,
  originalStartUtc: originalStartUtc,
  recurring: recurring,
  title: e.title,
  location: e.location,
  organizer: e.organizer,
  description: e.description,
  joinUrl: e.joinUrl,
  startUtc: timing.startUtc,
  endUtc: timing.endUtc,
  allDay: e.allDay,
  busyStatus: e.busyStatus,
  warnings: timing.warnings,
);

/// A one-off event (no RRULE, no RECURRENCE-ID): zero or one occurrence.
List<IcsOccurrence> expandSingle(
  ParsedEvent e,
  ZoneResolver zones,
  IcsWindow window,
) {
  if (e.cancelled) {
    return const [];
  }
  final timing = _timingOf(e, zones);
  if (!window.overlaps(timing.startUtc, timing.endUtc)) {
    return const [];
  }
  return [
    _occurrence(e, timing, originalStartUtc: timing.startUtc, recurring: false),
  ];
}
```

- [ ] **Step 5: Implement `expandIcs`**

`packages/ics_core/lib/src/expand_ics.dart`:

```dart
import 'component.dart';
import 'expander.dart';
import 'model.dart';
import 'vevent.dart';
import 'zones/zone_resolver.dart';

/// Parses [icsText] and returns every occurrence overlapping
/// `[windowStartUtc, windowEndUtc)`, sorted by start time.
///
/// Each VEVENT is handled on its own: one that cannot be used (no DTSTART,
/// a bad date, a broken RRULE, no END:VEVENT) becomes an [IcsIssue] and the
/// rest of the feed still parses. Cancelled events and instances are dropped.
///
/// [deviceZone] is the viewer's IANA zone; it places all-day and floating
/// events and is the last resort for unknown TZIDs.
///
/// Throws [IcsFormatException] when the text is not a VCALENDAR at all, and
/// [ArgumentError] if [deviceZone] is not an IANA name or the window is empty.
IcsResult expandIcs(
  String icsText, {
  required DateTime windowStartUtc,
  required DateTime windowEndUtc,
  required String deviceZone,
}) {
  final window = IcsWindow(windowStartUtc, windowEndUtc);
  final calendar = parseCalendar(icsText);
  final zones = ZoneResolver(
    deviceZone: deviceZone,
    vtimezones: {
      for (final c in calendar.children)
        if (c.name == 'VTIMEZONE' && c.first('TZID') != null)
          c.first('TZID')!.value.trim(): c,
    },
  );

  final issues = <IcsIssue>[];
  final events = <ParsedEvent>[];
  for (final c in calendar.children) {
    if (c.name != 'VEVENT') {
      continue;
    }
    try {
      if (!c.terminated) {
        throw const FormatException('VEVENT has no END:VEVENT');
      }
      final event = parseVevent(c);
      // RECURRENCE-ID overrides are applied from Task 10 on.
      if (event.recurrenceId == null) {
        events.add(event);
      }
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: uidOf(c), line: c.line, message: _describe(error)),
      );
    }
  }

  final occurrences = <IcsOccurrence>[];
  for (final event in events) {
    if (event.rrule != null) {
      continue; // Recurring series are expanded from Task 9 on.
    }
    try {
      occurrences.addAll(expandSingle(event, zones, window));
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: event.uid, line: event.line, message: _describe(error)),
      );
    }
  }

  occurrences.sort((a, b) {
    final byStart = a.startUtc.compareTo(b.startUtc);
    if (byStart != 0) {
      return byStart;
    }
    final byTitle = a.title.compareTo(b.title);
    return byTitle != 0 ? byTitle : a.uid.compareTo(b.uid);
  });
  issues.sort((a, b) => a.line.compareTo(b.line));
  return IcsResult(occurrences: occurrences, issues: issues);
}

String _describe(Object error) =>
    error is FormatException ? error.message : error.toString();
```

`packages/ics_core/lib/ics_core.dart` (replace the whole file):

```dart
/// ICS text → event occurrences in a time window.
///
/// Pure Dart (no Flutter). The single entry point is [expandIcs].
///
/// Time zones: a TZID is resolved as a Windows zone name (CLDR windowsZones,
/// territory 001), then as an IANA name, then from the feed's own VTIMEZONE
/// ([IcsWarning.tzFromVtimezone]), then as the device zone
/// ([IcsWarning.tzFromDevice]). UTC values (`Z`) are UTC. Floating values
/// (no TZID, no `Z`) and all-day DATE values use the device zone, with no
/// warning. Recurrences are expanded in the event's own wall-clock zone, then
/// converted to UTC, so local meeting times survive DST changes.
library;

export 'src/expand_ics.dart' show expandIcs;
export 'src/model.dart';
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/ics_core && dart test && dart analyze`
Expected: `All tests passed!` (every test file so far) then `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/ics_core/lib packages/ics_core/test
git commit -m "Expand one-off ICS events with expandIcs" -m "expandIcs parses the feed, resolves zones and returns sorted occurrences that overlap the window. Covers Windows, IANA, VTIMEZONE, unknown, UTC and floating times, all-day and multi-day events, DURATION, zero-length events, cancelled titles, Teams links and folded lines. A malformed or truncated VEVENT becomes an IcsIssue and the rest still parses."
```

---

### Task 9: Recurring series (RRULE, UNTIL, COUNT, INTERVAL, BYDAY, EXDATE, DST)

**Files:**
- Modify: `packages/ics_core/lib/src/expander.dart`
- Modify: `packages/ics_core/lib/src/expand_ics.dart`
- Create fixtures: `packages/ics_core/test/fixtures/weekly_exdate.ics`, `until_count.ics`, `monthly_byday.ics`, `dst_organizer.ics`
- Test: `packages/ics_core/test/expand_recurring_test.dart`

**Interfaces:**
- Consumes: `parseRrule`, `IcsTime` (Task 4); `ZoneResolver.forTime`, `WallZone.wallToUtc/utcToWall` (Task 6); Task 8's private helpers in `expander.dart`.
- Produces: `DateTime _instantOf(IcsTime, ZoneResolver)` (private) and `List<IcsOccurrence> expandSeries(ParsedEvent master, ZoneResolver zones, IcsWindow window)`. Task 10 adds an `overrides` parameter to `expandSeries`.

The series is expanded with `package:rrule` on wall-clock times in the DTSTART zone (the device zone for all-day series), and each instance is converted to UTC afterwards. That is what keeps a 09:00 Los Angeles meeting at 09:00 local time when US daylight saving ends on 1 Nov 2026 (16:00Z before, 17:00Z after), while the viewer in Johannesburg has no DST. Expanding in UTC would keep 16:00Z and ring an hour early. The `after`/`before` bounds get a 2-day margin plus the event length, and every instance is then checked exactly with `IcsWindow.overlaps`.

- [ ] **Step 1: Add the fixtures**

Create each file under `packages/ics_core/test/fixtures/` with exactly this content.

`weekly_exdate.ics`:

```text
BEGIN:VCALENDAR
METHOD:PUBLISH
PRODID:Microsoft Exchange Server 2010
VERSION:2.0
BEGIN:VTIMEZONE
TZID:South Africa Standard Time
BEGIN:STANDARD
DTSTART:16010101T000000
TZOFFSETFROM:+0200
TZOFFSETTO:+0200
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T000000
TZOFFSETFROM:+0200
TZOFFSETTO:+0200
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
UID:standup@example.com
SUMMARY:Daily standup
RRULE:FREQ=WEEKLY;UNTIL=20261231T064500Z;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR;WKST=SU
EXDATE;TZID=South Africa Standard Time:20261013T084500,20261015T084500
EXDATE;TZID=South Africa Standard Time:20261016T084500
DTSTART;TZID=South Africa Standard Time:20260907T084500
DTEND;TZID=South Africa Standard Time:20260907T090000
CLASS:PUBLIC
PRIORITY:5
TRANSP:OPAQUE
STATUS:CONFIRMED
SEQUENCE:0
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
END:VEVENT
BEGIN:VEVENT
UID:leave@example.com
SUMMARY:Leave day
RRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO
EXDATE;VALUE=DATE:20261019
DTSTART;VALUE=DATE:20261012
DTEND;VALUE=DATE:20261013
X-MICROSOFT-CDO-BUSYSTATUS:OOF
END:VEVENT
END:VCALENDAR
```

`until_count.ics`:

```text
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:review@example.com
SUMMARY:Sprint review
RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TH;COUNT=3
DTSTART;TZID=South Africa Standard Time:20261001T140000
DTEND;TZID=South Africa Standard Time:20261001T150000
END:VEVENT
BEGIN:VEVENT
UID:checkin-utc@example.com
SUMMARY:Daily check-in (UTC until)
RRULE:FREQ=DAILY;UNTIL=20261008T070000Z
DTSTART;TZID=South Africa Standard Time:20261005T090000
DTEND;TZID=South Africa Standard Time:20261005T091500
END:VEVENT
BEGIN:VEVENT
UID:checkin-local@example.com
SUMMARY:Daily check-in (local until)
RRULE:FREQ=DAILY;UNTIL=20261007T090000
DTSTART;TZID=South Africa Standard Time:20261005T100000
DTEND;TZID=South Africa Standard Time:20261005T101500
END:VEVENT
BEGIN:VEVENT
UID:checkin-date@example.com
SUMMARY:Daily check-in (date until)
RRULE:FREQ=DAILY;UNTIL=20261006
DTSTART;TZID=South Africa Standard Time:20261005T110000
DTEND;TZID=South Africa Standard Time:20261005T111500
END:VEVENT
END:VCALENDAR
```

`monthly_byday.ics`:

```text
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:townhall@example.com
SUMMARY:Town hall
RRULE:FREQ=MONTHLY;BYDAY=2MO
DTSTART;TZID=South Africa Standard Time:20261012T150000
DTEND;TZID=South Africa Standard Time:20261012T160000
END:VEVENT
BEGIN:VEVENT
UID:drinks@example.com
SUMMARY:Month-end drinks
RRULE:FREQ=MONTHLY;INTERVAL=1;BYDAY=-1FR
DTSTART;TZID=South Africa Standard Time:20261030T160000
DTEND;TZID=South Africa Standard Time:20261030T170000
END:VEVENT
BEGIN:VEVENT
UID:report@example.com
SUMMARY:Last-workday report
RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1
DTSTART;TZID=South Africa Standard Time:20261030T080000
DTEND;TZID=South Africa Standard Time:20261030T083000
END:VEVENT
END:VCALENDAR
```

`dst_organizer.ics`:

```text
BEGIN:VCALENDAR
METHOD:PUBLISH
PRODID:Microsoft Exchange Server 2010
VERSION:2.0
BEGIN:VTIMEZONE
TZID:Pacific Standard Time
BEGIN:STANDARD
DTSTART:16010101T020000
TZOFFSETFROM:-0700
TZOFFSETTO:-0800
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T020000
TZOFFSETFROM:-0800
TZOFFSETTO:-0700
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VTIMEZONE
TZID:W. Europe Standard Time
BEGIN:STANDARD
DTSTART:16010101T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T020000
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
UID:us-sync@example.com
SUMMARY:US sync
ORGANIZER;CN="Dana R.":mailto:dana@example.com
RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO;WKST=SU
DTSTART;TZID=Pacific Standard Time:20261019T090000
DTEND;TZID=Pacific Standard Time:20261019T100000
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
END:VEVENT
BEGIN:VEVENT
UID:eu-sync@example.com
SUMMARY:EU sync
RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO;WKST=SU
DTSTART;TZID=W. Europe Standard Time:20261019T090000
DTEND;TZID=W. Europe Standard Time:20261019T093000
END:VEVENT
END:VCALENDAR
```

- [ ] **Step 2: Write the failing test**

`packages/ics_core/test/expand_recurring_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('weekly RRULE with EXDATE (weekly_exdate.ics)', () {
    final week = expandFixture(
      'weekly_exdate.ics',
      from: DateTime.utc(2026, 10, 12),
      to: DateTime.utc(2026, 10, 17),
    );

    test('Mon–Fri standup minus three EXDATEs on two lines', () {
      expect(startsOf(week, 'standup@example.com'), [
        '2026-10-12T06:45:00.000Z',
        '2026-10-14T06:45:00.000Z',
      ]);
      expect(week.issues, isEmpty);
    });

    test('instances are recurring, keep their length and original start', () {
      final o = byUid(week, 'standup@example.com').first;
      expect(o.recurring, isTrue);
      expect(o.endUtc.difference(o.startUtc), const Duration(minutes: 15));
      expect(o.originalStartUtc, o.startUtc);
      expect(o.title, 'Daily standup');
      expect(o.busyStatus, IcsBusyStatus.busy);
    });

    test('UNTIL (UTC) ends the series on its last day', () {
      final r = expandFixture(
        'weekly_exdate.ics',
        from: DateTime.utc(2026, 12, 28),
        to: DateTime.utc(2027, 1, 9),
      );
      expect(startsOf(r, 'standup@example.com'), [
        '2026-12-28T06:45:00.000Z',
        '2026-12-29T06:45:00.000Z',
        '2026-12-30T06:45:00.000Z',
        '2026-12-31T06:45:00.000Z',
      ]);
    });

    test('all-day weekly series with COUNT and a DATE EXDATE', () {
      final r = expandFixture(
        'weekly_exdate.ics',
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 11, 30),
      );
      final leave = byUid(r, 'leave@example.com');
      expect(leave.map((o) => o.startUtc.toIso8601String()), [
        '2026-10-11T22:00:00.000Z',
        '2026-10-25T22:00:00.000Z',
        '2026-11-01T22:00:00.000Z',
      ]);
      expect(leave.every((o) => o.allDay), isTrue);
      expect(leave.first.endUtc, DateTime.utc(2026, 10, 12, 22));
    });
  });

  group('COUNT, INTERVAL and UNTIL (until_count.ics)', () {
    final r = expandFixture(
      'until_count.ics',
      from: DateTime.utc(2026, 9, 1),
      to: DateTime.utc(2026, 12, 1),
    );

    test('INTERVAL=2 with COUNT=3', () {
      expect(startsOf(r, 'review@example.com'), [
        '2026-10-01T12:00:00.000Z',
        '2026-10-15T12:00:00.000Z',
        '2026-10-29T12:00:00.000Z',
      ]);
    });

    test('COUNT counts from DTSTART even when the window starts later', () {
      final late = expandFixture(
        'until_count.ics',
        from: DateTime.utc(2026, 10, 10),
        to: DateTime.utc(2026, 12, 1),
      );
      expect(startsOf(late, 'review@example.com'), [
        '2026-10-15T12:00:00.000Z',
        '2026-10-29T12:00:00.000Z',
      ]);
    });

    test('a UTC UNTIL is compared in the event zone (last day kept)', () {
      expect(startsOf(r, 'checkin-utc@example.com'), [
        '2026-10-05T07:00:00.000Z',
        '2026-10-06T07:00:00.000Z',
        '2026-10-07T07:00:00.000Z',
        '2026-10-08T07:00:00.000Z',
      ]);
    });

    test('a local UNTIL is compared as written', () {
      expect(startsOf(r, 'checkin-local@example.com'), [
        '2026-10-05T08:00:00.000Z',
        '2026-10-06T08:00:00.000Z',
      ]);
    });

    test('a DATE UNTIL includes that whole day', () {
      expect(startsOf(r, 'checkin-date@example.com'), [
        '2026-10-05T09:00:00.000Z',
        '2026-10-06T09:00:00.000Z',
      ]);
    });
  });

  group('monthly BYDAY (monthly_byday.ics)', () {
    final r = expandFixture(
      'monthly_byday.ics',
      from: DateTime.utc(2026, 10, 1),
      to: DateTime.utc(2027, 1, 1),
    );

    test('2MO: second Monday', () {
      expect(startsOf(r, 'townhall@example.com'), [
        '2026-10-12T13:00:00.000Z',
        '2026-11-09T13:00:00.000Z',
        '2026-12-14T13:00:00.000Z',
      ]);
    });

    test('-1FR: last Friday', () {
      expect(startsOf(r, 'drinks@example.com'), [
        '2026-10-30T14:00:00.000Z',
        '2026-11-27T14:00:00.000Z',
        '2026-12-25T14:00:00.000Z',
      ]);
    });

    test('BYSETPOS=-1: last weekday of the month', () {
      expect(startsOf(r, 'report@example.com'), [
        '2026-10-30T06:00:00.000Z',
        '2026-11-30T06:00:00.000Z',
        '2026-12-31T06:00:00.000Z',
      ]);
    });
  });

  group(
    'organiser in a DST zone, viewer in Johannesburg (dst_organizer.ics)',
    () {
      final r = expandFixture(
        'dst_organizer.ics',
        from: DateTime.utc(2026, 10, 19),
        to: DateTime.utc(2026, 11, 10),
      );

      test('US Pacific meeting stays at 09:00 local across 1 Nov', () {
        expect(startsOf(r, 'us-sync@example.com'), [
          '2026-10-19T16:00:00.000Z',
          '2026-10-26T16:00:00.000Z',
          '2026-11-02T17:00:00.000Z',
          '2026-11-09T17:00:00.000Z',
        ]);
        final o = byUid(r, 'us-sync@example.com').last;
        expect(o.endUtc.difference(o.startUtc), const Duration(hours: 1));
        expect(o.organizer, 'Dana R.');
        expect(o.warnings, isEmpty);
      });

      test('European meeting stays at 09:00 local across 25 Oct', () {
        expect(startsOf(r, 'eu-sync@example.com'), [
          '2026-10-19T07:00:00.000Z',
          '2026-10-26T08:00:00.000Z',
          '2026-11-02T08:00:00.000Z',
          '2026-11-09T08:00:00.000Z',
        ]);
      });

      test('results are sorted by start time', () {
        final starts = r.occurrences.map((o) => o.startUtc).toList();
        expect(starts, [...starts]..sort());
      });
    },
  );

  test('a long-running daily series expands only inside the window', () {
    final r = expandIcs(
      calendar('''
BEGIN:VEVENT
UID:old-daily
SUMMARY:Since 2015
RRULE:FREQ=DAILY
DTSTART;TZID=South Africa Standard Time:20150105T080000
DTEND;TZID=South Africa Standard Time:20150105T081500
END:VEVENT'''),
      windowStartUtc: DateTime.utc(2026, 10, 12, 5),
      windowEndUtc: DateTime.utc(2026, 10, 14, 5),
      deviceZone: 'Africa/Johannesburg',
    );
    expect(startsOf(r, 'old-daily'), [
      '2026-10-12T06:00:00.000Z',
      '2026-10-13T06:00:00.000Z',
    ]);
  });

  test('a broken RRULE becomes an issue; other events still parse', () {
    final r = expandIcs(
      calendar('''
BEGIN:VEVENT
UID:good
SUMMARY:Good
DTSTART:20261013T090000Z
DTEND:20261013T100000Z
END:VEVENT
BEGIN:VEVENT
UID:bad-rrule
SUMMARY:Bad rule
RRULE:FREQ=SOMETIMES
DTSTART:20261013T110000Z
END:VEVENT'''),
      windowStartUtc: DateTime.utc(2026, 10, 12),
      windowEndUtc: DateTime.utc(2026, 10, 19),
      deviceZone: 'Africa/Johannesburg',
    );
    expect(r.occurrences.map((o) => o.uid), ['good']);
    expect(r.issues.single.uid, 'bad-rrule');
    expect(r.issues.single.line, 9);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/expand_recurring_test.dart`
Expected: FAIL: series tests find no occurrences (e.g. `Expected: ['2026-10-12T06:45:00.000Z', ...] Actual: []`) because Task 8 skips RRULE events, and `a broken RRULE becomes an issue` finds no issue.

- [ ] **Step 4: Add series expansion to `expander.dart`**

Add this import after `import 'model.dart';`:

```dart
import 'values.dart';
```

Insert this function directly above `IcsOccurrence _occurrence(`:

```dart
/// The UTC instant a RECURRENCE-ID or EXDATE value names.
DateTime _instantOf(IcsTime t, ZoneResolver zones) => t.isDate
    ? zones.device.wallToUtc(_date(t.wall))
    : zones.forTime(t).zone.wallToUtc(t.wall);
```

Append this function at the end of the file:

```dart
/// An RRULE series.
///
/// The rule is expanded in the event's own wall-clock zone, so a 09:00
/// meeting stays at 09:00 local time across DST changes, then each instance
/// is converted to UTC. EXDATEs remove instances. A cancelled series yields
/// nothing.
///
/// Throws [FormatException] (or whatever `package:rrule` throws) for a bad rule.
List<IcsOccurrence> expandSeries(
  ParsedEvent master,
  ZoneResolver zones,
  IcsWindow window,
) {
  if (master.cancelled) {
    return const [];
  }
  final allDay = master.allDay;
  final masterTiming = _timingOf(master, zones);
  final zone = allDay ? zones.device : zones.forTime(master.start).zone;
  final rule = parseRrule(
    master.rrule!,
    untilUtcToWall: zone.utcToWall,
    startIsDate: allDay,
  );
  final startWall = allDay ? _date(master.start.wall) : master.start.wall;
  final length = masterTiming.endUtc.difference(masterTiming.startUtc);
  final allDayDays = allDay ? _allDayLength(master) : 0;
  final margin = const Duration(days: 2);
  final afterWall = zone.utcToWall(window.start).subtract(length + margin);
  final beforeWall = zone.utcToWall(window.end).add(margin);

  final excluded = {for (final ex in master.exdates) _instantOf(ex, zones)};

  final result = <IcsOccurrence>[];
  for (final wall in rule.getInstances(
    start: startWall,
    after: afterWall.isAfter(startWall) ? afterWall : null,
    includeAfter: true,
    before: beforeWall,
    includeBefore: true,
  )) {
    final startUtc = zone.wallToUtc(wall);
    if (excluded.contains(startUtc)) {
      continue;
    }
    final endUtc = allDay
        ? zone.wallToUtc(wall.add(Duration(days: allDayDays)))
        : startUtc.add(length);
    if (!window.overlaps(startUtc, endUtc)) {
      continue;
    }
    result.add(
      _occurrence(
        master,
        _Timing(startUtc, endUtc, masterTiming.warnings),
        originalStartUtc: startUtc,
        recurring: true,
      ),
    );
  }

  return result;
}
```

- [ ] **Step 5: Route RRULE events to `expandSeries` in `expand_ics.dart`**

Replace this block:

```dart
  final occurrences = <IcsOccurrence>[];
  for (final event in events) {
    if (event.rrule != null) {
      continue; // Recurring series are expanded from Task 9 on.
    }
    try {
      occurrences.addAll(expandSingle(event, zones, window));
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: event.uid, line: event.line, message: _describe(error)),
      );
    }
  }
```

with:

```dart
  final occurrences = <IcsOccurrence>[];
  for (final event in events) {
    try {
      occurrences.addAll(
        event.rrule == null
            ? expandSingle(event, zones, window)
            : expandSeries(event, zones, window),
      );
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: event.uid, line: event.line, message: _describe(error)),
      );
    }
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/ics_core && dart format lib && dart test && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/ics_core/lib/src packages/ics_core/test
git commit -m "Expand recurring ICS series in their own zone" -m "RRULEs are expanded with package:rrule on wall-clock times in the event's zone and converted to UTC afterwards, so meetings keep their local time across DST changes. Covers UNTIL in UTC, local and DATE form, COUNT, INTERVAL, monthly BYDAY (2MO, -1FR), BYSETPOS, EXDATE with TZID and several values, all-day series, and a broken RRULE as an IcsIssue."
```

---

### Task 10: RECURRENCE-ID overrides

**Files:**
- Modify: `packages/ics_core/lib/src/expander.dart`
- Replace: `packages/ics_core/lib/src/expand_ics.dart`
- Create fixture: `packages/ics_core/test/fixtures/modified_cancelled.ics`
- Test: `packages/ics_core/test/expand_overrides_test.dart`

**Interfaces:**
- Consumes: everything in `expander.dart` from Tasks 8 and 9.
- Produces: `List<IcsOccurrence> expandSeries(ParsedEvent master, List<ParsedEvent> overrides, ZoneResolver zones, IcsWindow window)` (new `overrides` parameter) and `List<IcsOccurrence> expandOrphanOverride(ParsedEvent, ZoneResolver, IcsWindow)`.

Rules: every override removes the series instance whose original start (RECURRENCE-ID, compared as a UTC instant, whether written with TZID or `Z`) it names, wherever the override itself now lands. A non-cancelled override is then emitted on its own times and fields if it overlaps the window, with `originalStartUtc` = its RECURRENCE-ID. So an override can move an instance into the window, move it out, rename it, or (with `STATUS:CANCELLED` or a `Canceled:` title) remove it. Overrides may appear before their series in the file.

- [ ] **Step 1: Add the fixture**

`packages/ics_core/test/fixtures/modified_cancelled.ics`:

```text
BEGIN:VCALENDAR
METHOD:PUBLISH
PRODID:Microsoft Exchange Server 2010
VERSION:2.0
BEGIN:VEVENT
UID:oneonone@example.com
RECURRENCE-ID;TZID=South Africa Standard Time:20261013T100000
SUMMARY:1:1 with Pieter (moved)
DTSTART;TZID=South Africa Standard Time:20261014T140000
DTEND;TZID=South Africa Standard Time:20261014T143000
SEQUENCE:1
END:VEVENT
BEGIN:VEVENT
UID:oneonone@example.com
SUMMARY:1:1 with Pieter
ORGANIZER;CN="Thandi M.":mailto:thandi@example.com
LOCATION:Microsoft Teams Meeting
RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=TU;WKST=SU
DTSTART;TZID=South Africa Standard Time:20261006T100000
DTEND;TZID=South Africa Standard Time:20261006T103000
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
END:VEVENT
BEGIN:VEVENT
UID:oneonone@example.com
RECURRENCE-ID;TZID=South Africa Standard Time:20261020T100000
SUMMARY:1:1 with Pieter
STATUS:CANCELLED
DTSTART;TZID=South Africa Standard Time:20261020T100000
DTEND;TZID=South Africa Standard Time:20261020T103000
END:VEVENT
BEGIN:VEVENT
UID:oneonone@example.com
RECURRENCE-ID;TZID=South Africa Standard Time:20261027T100000
SUMMARY:Canceled: 1:1 with Pieter
DTSTART;TZID=South Africa Standard Time:20261027T100000
DTEND;TZID=South Africa Standard Time:20261027T103000
END:VEVENT
BEGIN:VEVENT
UID:oneonone@example.com
RECURRENCE-ID;TZID=South Africa Standard Time:20261103T100000
SUMMARY:1:1 with Pieter
DTSTART;TZID=South Africa Standard Time:20261112T100000
DTEND;TZID=South Africa Standard Time:20261112T103000
END:VEVENT
BEGIN:VEVENT
UID:oneonone@example.com
RECURRENCE-ID:20261110T080000Z
SUMMARY:1:1 with Pieter (early)
DTSTART;TZID=South Africa Standard Time:20261106T090000
DTEND;TZID=South Africa Standard Time:20261106T093000
END:VEVENT
BEGIN:VEVENT
UID:guest@example.com
RECURRENCE-ID;TZID=South Africa Standard Time:20261015T130000
SUMMARY:Guest session
DTSTART;TZID=South Africa Standard Time:20261015T130000
DTEND;TZID=South Africa Standard Time:20261015T140000
END:VEVENT
BEGIN:VEVENT
UID:cancelled-series@example.com
SUMMARY:Old weekly
STATUS:CANCELLED
RRULE:FREQ=WEEKLY;BYDAY=WE
DTSTART;TZID=South Africa Standard Time:20261007T090000
DTEND;TZID=South Africa Standard Time:20261007T093000
END:VEVENT
BEGIN:VEVENT
UID:cancelled-series@example.com
RECURRENCE-ID;TZID=South Africa Standard Time:20261014T090000
SUMMARY:Old weekly
DTSTART;TZID=South Africa Standard Time:20261014T100000
DTEND;TZID=South Africa Standard Time:20261014T103000
END:VEVENT
END:VCALENDAR
```

- [ ] **Step 2: Write the failing test**

`packages/ics_core/test/expand_overrides_test.dart`:

```dart
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final r = expandFixture(
    'modified_cancelled.ics',
    from: DateTime.utc(2026, 10, 5),
    to: DateTime.utc(2026, 11, 8),
  );
  final series = byUid(r, 'oneonone@example.com');

  test('no issues', () => expect(r.issues, isEmpty));

  test('the series shows the plain, moved and moved-in instances only', () {
    expect(series.map((o) => (o.startUtc.toIso8601String(), o.title)), [
      ('2026-10-06T08:00:00.000Z', '1:1 with Pieter'),
      ('2026-10-14T12:00:00.000Z', '1:1 with Pieter (moved)'),
      ('2026-11-06T07:00:00.000Z', '1:1 with Pieter (early)'),
    ]);
  });

  test('a moved instance keeps its original start (RECURRENCE-ID)', () {
    final moved = series[1];
    expect(moved.originalStartUtc, DateTime.utc(2026, 10, 13, 8));
    expect(moved.recurring, isTrue);
    expect(moved.endUtc, DateTime.utc(2026, 10, 14, 12, 30));
  });

  test('an override takes its own fields, not the series fields', () {
    expect(series[1].organizer, isNull);
    expect(series[0].organizer, 'Thandi M.');
  });

  test('STATUS:CANCELLED and Canceled: overrides remove their instance', () {
    final originals = series.map((o) => o.originalStartUtc).toSet();
    expect(originals, isNot(contains(DateTime.utc(2026, 10, 20, 8))));
    expect(originals, isNot(contains(DateTime.utc(2026, 10, 27, 8))));
  });

  test('an instance moved out of the window disappears', () {
    expect(
      series.map((o) => o.originalStartUtc),
      isNot(contains(DateTime.utc(2026, 11, 3, 8))),
    );
    final later = expandFixture(
      'modified_cancelled.ics',
      from: DateTime.utc(2026, 11, 12),
      to: DateTime.utc(2026, 11, 13),
    );
    expect(
      byUid(later, 'oneonone@example.com').single.originalStartUtc,
      DateTime.utc(2026, 11, 3, 8),
    );
  });

  test('an instance moved into the window appears (UTC RECURRENCE-ID)', () {
    expect(series.last.originalStartUtc, DateTime.utc(2026, 11, 10, 8));
  });

  test('the instance an override replaced does not also appear', () {
    final nov = expandFixture(
      'modified_cancelled.ics',
      from: DateTime.utc(2026, 11, 9),
      to: DateTime.utc(2026, 11, 11),
    );
    expect(byUid(nov, 'oneonone@example.com'), isEmpty);
  });

  test('an override without its series is shown on its own, recurring', () {
    final guest = byUid(r, 'guest@example.com').single;
    expect(guest.recurring, isTrue);
    expect(guest.startUtc, DateTime.utc(2026, 10, 15, 11));
    expect(guest.originalStartUtc, DateTime.utc(2026, 10, 15, 11));
  });

  test('a cancelled series drops its overrides too', () {
    expect(byUid(r, 'cancelled-series@example.com'), isEmpty);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/expand_overrides_test.dart`
Expected: FAIL: the series test shows the unmodified Tuesday instances (Oct 13, 20, 27, Nov 3 at 08:00Z) instead of the moved ones, and the orphan `guest@example.com` test finds nothing.

- [ ] **Step 4: Add override handling to `expander.dart`**

Insert this function directly above the `/// An RRULE series.` doc comment:

```dart
/// An override whose series is missing from the feed (e.g. you were invited
/// to one instance only): shown on its own, still marked recurring.
List<IcsOccurrence> expandOrphanOverride(
  ParsedEvent e,
  ZoneResolver zones,
  IcsWindow window,
) {
  if (e.cancelled) {
    return const [];
  }
  final timing = _timingOf(e, zones);
  if (!window.overlaps(timing.startUtc, timing.endUtc)) {
    return const [];
  }
  return [
    _occurrence(
      e,
      timing,
      originalStartUtc: _instantOf(e.recurrenceId!, zones),
      recurring: true,
    ),
  ];
}
```

Then replace the whole `expandSeries` function, from its doc comment `/// An RRULE series.` to the end of the file, with:

```dart
/// An RRULE series plus its RECURRENCE-ID overrides.
///
/// The rule is expanded in the event's own wall-clock zone, so a 09:00
/// meeting stays at 09:00 local time across DST changes, then each instance
/// is converted to UTC. EXDATEs remove instances; every override replaces
/// the instance whose original start it names (wherever the override now
/// lands); cancelled overrides just remove it. A cancelled series yields
/// nothing.
///
/// Throws [FormatException] (or whatever `package:rrule` throws) for a bad rule.
List<IcsOccurrence> expandSeries(
  ParsedEvent master,
  List<ParsedEvent> overrides,
  ZoneResolver zones,
  IcsWindow window,
) {
  if (master.cancelled) {
    return const [];
  }
  final allDay = master.allDay;
  final masterTiming = _timingOf(master, zones);
  final zone = allDay ? zones.device : zones.forTime(master.start).zone;
  final rule = parseRrule(
    master.rrule!,
    untilUtcToWall: zone.utcToWall,
    startIsDate: allDay,
  );
  final startWall = allDay ? _date(master.start.wall) : master.start.wall;
  final length = masterTiming.endUtc.difference(masterTiming.startUtc);
  final allDayDays = allDay ? _allDayLength(master) : 0;
  final margin = const Duration(days: 2);
  final afterWall = zone.utcToWall(window.start).subtract(length + margin);
  final beforeWall = zone.utcToWall(window.end).add(margin);

  final excluded = {for (final ex in master.exdates) _instantOf(ex, zones)};
  final overridden = {
    for (final o in overrides) _instantOf(o.recurrenceId!, zones),
  };

  final result = <IcsOccurrence>[];
  for (final wall in rule.getInstances(
    start: startWall,
    after: afterWall.isAfter(startWall) ? afterWall : null,
    includeAfter: true,
    before: beforeWall,
    includeBefore: true,
  )) {
    final startUtc = zone.wallToUtc(wall);
    if (excluded.contains(startUtc) || overridden.contains(startUtc)) {
      continue;
    }
    final endUtc = allDay
        ? zone.wallToUtc(wall.add(Duration(days: allDayDays)))
        : startUtc.add(length);
    if (!window.overlaps(startUtc, endUtc)) {
      continue;
    }
    result.add(
      _occurrence(
        master,
        _Timing(startUtc, endUtc, masterTiming.warnings),
        originalStartUtc: startUtc,
        recurring: true,
      ),
    );
  }

  for (final o in overrides) {
    if (o.cancelled) {
      continue;
    }
    final timing = _timingOf(o, zones);
    if (!window.overlaps(timing.startUtc, timing.endUtc)) {
      continue;
    }
    result.add(
      _occurrence(
        o,
        timing,
        originalStartUtc: _instantOf(o.recurrenceId!, zones),
        recurring: true,
      ),
    );
  }
  return result;
}
```

- [ ] **Step 5: Wire overrides into `expandIcs` (replace the whole file)**

`packages/ics_core/lib/src/expand_ics.dart`:

```dart
import 'component.dart';
import 'expander.dart';
import 'model.dart';
import 'vevent.dart';
import 'zones/zone_resolver.dart';

/// Parses [icsText] and returns every occurrence overlapping
/// `[windowStartUtc, windowEndUtc)`, sorted by start time.
///
/// Each VEVENT is handled on its own: one that cannot be used (no DTSTART,
/// a bad date, a broken RRULE, no END:VEVENT) becomes an [IcsIssue] and the
/// rest of the feed still parses. Cancelled events and instances are dropped.
///
/// [deviceZone] is the viewer's IANA zone; it places all-day and floating
/// events and is the last resort for unknown TZIDs.
///
/// Throws [IcsFormatException] when the text is not a VCALENDAR at all, and
/// [ArgumentError] if [deviceZone] is not an IANA name or the window is empty.
IcsResult expandIcs(
  String icsText, {
  required DateTime windowStartUtc,
  required DateTime windowEndUtc,
  required String deviceZone,
}) {
  final window = IcsWindow(windowStartUtc, windowEndUtc);
  final calendar = parseCalendar(icsText);
  final zones = ZoneResolver(
    deviceZone: deviceZone,
    vtimezones: {
      for (final c in calendar.children)
        if (c.name == 'VTIMEZONE' && c.first('TZID') != null)
          c.first('TZID')!.value.trim(): c,
    },
  );

  final issues = <IcsIssue>[];
  final events = <ParsedEvent>[];
  final overridesByUid = <String, List<ParsedEvent>>{};
  for (final c in calendar.children) {
    if (c.name != 'VEVENT') {
      continue;
    }
    try {
      if (!c.terminated) {
        throw const FormatException('VEVENT has no END:VEVENT');
      }
      final event = parseVevent(c);
      if (event.recurrenceId != null) {
        overridesByUid.putIfAbsent(event.uid, () => []).add(event);
      } else {
        events.add(event);
      }
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: uidOf(c), line: c.line, message: _describe(error)),
      );
    }
  }

  final occurrences = <IcsOccurrence>[];
  for (final event in events) {
    try {
      if (event.rrule == null) {
        occurrences.addAll(expandSingle(event, zones, window));
      } else {
        // Overrides belong to the first series with their UID.
        final overrides = overridesByUid.remove(event.uid) ?? const [];
        occurrences.addAll(expandSeries(event, overrides, zones, window));
      }
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: event.uid, line: event.line, message: _describe(error)),
      );
    }
  }
  for (final orphan in overridesByUid.values.expand((list) => list)) {
    try {
      occurrences.addAll(expandOrphanOverride(orphan, zones, window));
    } on Object catch (error) {
      issues.add(
        IcsIssue(uid: orphan.uid, line: orphan.line, message: _describe(error)),
      );
    }
  }

  occurrences.sort((a, b) {
    final byStart = a.startUtc.compareTo(b.startUtc);
    if (byStart != 0) {
      return byStart;
    }
    final byTitle = a.title.compareTo(b.title);
    return byTitle != 0 ? byTitle : a.uid.compareTo(b.uid);
  });
  issues.sort((a, b) => a.line.compareTo(b.line));
  return IcsResult(occurrences: occurrences, issues: issues);
}

String _describe(Object error) =>
    error is FormatException ? error.message : error.toString();
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/ics_core && dart format lib && dart test && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/ics_core/lib/src packages/ics_core/test
git commit -m "Apply RECURRENCE-ID overrides in ics_core" -m "An override replaces the instance it names, wherever it now lands: it can move an instance into or out of the window, change its title, or remove it when cancelled. Overrides without their series are shown on their own; a cancelled series drops its overrides too."
```

---

### Task 11: Real-feed fixture (scrubbed) and spec §12.3

**Files:**
- Modify: `.gitignore`
- Create: `packages/ics_core/tool/scrub_feed.dart`
- Test: `packages/ics_core/test/scrub_feed_test.dart`
- Create (from the user's feed): `packages/ics_core/test/fixtures/real_feed_scrubbed.ics`
- Test: `packages/ics_core/test/real_feed_test.dart`
- Never committed: `packages/ics_core/test/fixtures/private/feed.raw.ics`

**Interfaces:**
- Consumes: `unfoldLines`, `parseContentLine`, `unescapeText` (Task 2); `isCancelledTitle`, `extractTeamsJoinUrl` (Task 7); `expandIcs` (Tasks 8–10).
- Produces: in `tool/scrub_feed.dart`: `ScrubResult scrubFeed(String raw, {required DateTime capturedUtc})` (`ScrubResult` has `text`, `events`, `eventsWithTeamsLink`, `eventsWithMeetLink`, `dropped`) and `List<String> leakedEmails(String text)`. The scrubbed feed carries two header lines the real-feed test reads: `X-TMINUS-CAPTURED:<UTC stamp>` and `X-TMINUS-RAW-TEAMS-EVENTS:<n>`.

The scrubber keeps an allowlist of structural properties (VTIMEZONE blocks, TZIDs, DTSTART/DTEND/DURATION, RRULE, EXDATE, RECURRENCE-ID, STATUS, TRANSP, busy status, …) unchanged and rewrites SUMMARY (keeping a `Canceled:` prefix), DESCRIPTION, LOCATION, ORGANIZER, ATTENDEE, UID (hashed, so series and overrides still match) and X-WR-CALNAME. Every other property is dropped and counted. A Teams link becomes a synthetic `https://teams.microsoft.com/l/meetup-join/19%3ameeting_SCRUBBED<n>%40thread.v2/0?context=%7b%7d`. It refuses to write output that still contains an email address outside `@example.com`.

- [ ] **Step 1: Ignore raw feeds**

Append to the root `.gitignore`:

```gitignore

# Raw (unscrubbed) ICS feeds are secrets (spec §10): never commit them.
packages/ics_core/test/fixtures/private/
*.raw.ics
```

- [ ] **Step 2: Write the failing scrubber test**

`packages/ics_core/test/scrub_feed_test.dart`:

```dart
import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import '../tool/scrub_feed.dart';

const raw = r'''
BEGIN:VCALENDAR
METHOD:PUBLISH
PRODID:Microsoft Exchange Server 2010
VERSION:2.0
X-WR-CALNAME:Alex Doe Calendar
BEGIN:VTIMEZONE
TZID:South Africa Standard Time
BEGIN:STANDARD
DTSTART:16010101T000000
TZOFFSETFROM:+0200
TZOFFSETTO:+0200
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
UID:040000008200E00074C5B7101A82E00800000000SECRET
SUMMARY:Salary review with Thandi
DESCRIPTION:Private notes\nClick here to join the meeting<https://teams.mi
 crosoft.com/l/meetup-join/19%3ameeting_REALID%40thread.v2/0?context=%7b%22
 Tid%22%3a%22real-tenant%22%7d>
LOCATION:Microsoft Teams Meeting
ORGANIZER;CN="Thandi Mokoena":mailto:thandi.mokoena@contoso.co.za
ATTENDEE;CN="Pieter V";PARTSTAT=ACCEPTED:mailto:pieter@contoso.co.za
X-ALT-DESC;FMTTYPE=text/html:<html>Private notes</html>
RRULE:FREQ=WEEKLY;UNTIL=20261231T080000Z;INTERVAL=1;BYDAY=TU;WKST=SU
EXDATE;TZID=South Africa Standard Time:20261013T100000
DTSTART;TZID=South Africa Standard Time:20261006T100000
DTEND;TZID=South Africa Standard Time:20261006T103000
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
END:VEVENT
BEGIN:VEVENT
UID:040000008200E00074C5B7101A82E00800000000SECRET
RECURRENCE-ID;TZID=South Africa Standard Time:20261020T100000
SUMMARY:Canceled: Salary review with Thandi
DTSTART;TZID=South Africa Standard Time:20261020T100000
DTEND;TZID=South Africa Standard Time:20261020T103000
END:VEVENT
BEGIN:VEVENT
UID:dentist-1
SUMMARY:Dentist
LOCATION:12 Long Street\, Cape Town
DTSTART;TZID=South Africa Standard Time:20261015T080000
DTEND;TZID=South Africa Standard Time:20261015T090000
END:VEVENT
END:VCALENDAR
''';

void main() {
  final result = scrubFeed(raw, capturedUtc: DateTime.utc(2026, 10, 6, 12));

  test('removes names, addresses, notes, places and real ids', () {
    for (final secret in [
      'Thandi',
      'Pieter',
      'Alex Doe',
      'Salary',
      'Private notes',
      'contoso',
      'REALID',
      'real-tenant',
      'SECRET',
      'Long Street',
      'Dentist',
    ]) {
      expect(result.text, isNot(contains(secret)), reason: secret);
    }
    expect(leakedEmails(result.text), isEmpty);
  });

  test('keeps zones, rules, exceptions, overrides and busy status', () {
    for (final kept in [
      'TZID:South Africa Standard Time',
      'RRULE:FREQ=WEEKLY;UNTIL=20261231T080000Z;INTERVAL=1;BYDAY=TU;WKST=SU',
      'EXDATE;TZID=South Africa Standard Time:20261013T100000',
      'RECURRENCE-ID;TZID=South Africa Standard Time:20261020T100000',
      'X-MICROSOFT-CDO-BUSYSTATUS:BUSY',
      'SUMMARY:Canceled: Event 2',
    ]) {
      expect(result.text, contains(kept), reason: kept);
    }
  });

  test('records capture time and the raw Teams link count', () {
    expect(result.text, contains('X-TMINUS-CAPTURED:20261006T120000Z'));
    expect(result.text, contains('X-TMINUS-RAW-TEAMS-EVENTS:1'));
    expect(result.events, 3);
    expect(result.eventsWithTeamsLink, 1);
    expect(result.eventsWithMeetLink, 0);
    expect(result.dropped, {'X-ALT-DESC': 1});
  });

  test(
    'the scrubbed feed parses the same way, with a synthetic Teams link',
    () {
      IcsResult run(String text) => expandIcs(
        text,
        windowStartUtc: DateTime.utc(2026, 10, 1),
        windowEndUtc: DateTime.utc(2026, 10, 31),
        deviceZone: 'Africa/Johannesburg',
      );
      final before = run(raw);
      final after = run(result.text);
      expect(after.issues, isEmpty);
      expect(
        after.occurrences.map((o) => o.startUtc),
        before.occurrences.map((o) => o.startUtc),
      );
      expect(
        after.occurrences.first.joinUrl,
        startsWith(
          'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SCRUBBED',
        ),
      );
      expect(after.occurrences.first.organizer, 'Person 1');
    },
  );
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/ics_core && dart test test/scrub_feed_test.dart`
Expected: FAIL, compilation error: `tool/scrub_feed.dart` not found.

- [ ] **Step 4: Write the scrubber**

`packages/ics_core/tool/scrub_feed.dart`:

```dart
// Makes a published Outlook ICS feed safe to commit as a test fixture.
//
// Usage (from packages/ics_core):
//   dart run tool/scrub_feed.dart <raw.ics> <scrubbed.ics>
//
// Keeps the structure the parser cares about (VTIMEZONEs, TZIDs, DTSTART/
// DTEND, RRULE, EXDATE, RECURRENCE-ID, STATUS, TRANSP, busy status) and
// replaces every piece of personal text. Properties not on the allowlist are
// dropped. A Teams join link is replaced by a synthetic link of the same
// shape so join-link extraction can still be tested.
import 'dart:io';

import 'package:ics_core/src/content_line.dart';
import 'package:ics_core/src/event_fields.dart';

/// Properties copied unchanged.
const keptProperties = {
  'BEGIN', 'END', 'VERSION', 'PRODID', 'METHOD', 'CALSCALE', //
  'TZID', 'TZOFFSETFROM', 'TZOFFSETTO', 'TZNAME', 'RDATE',
  'DTSTART', 'DTEND', 'DURATION', 'RRULE', 'EXDATE', 'RECURRENCE-ID',
  'STATUS', 'TRANSP', 'SEQUENCE', 'CLASS', 'PRIORITY', 'DTSTAMP',
  'CREATED', 'LAST-MODIFIED', 'ACTION', 'TRIGGER',
  'X-MICROSOFT-CDO-BUSYSTATUS', 'X-MICROSOFT-CDO-INTENDEDSTATUS',
  'X-MICROSOFT-CDO-ALLDAYEVENT', 'X-MICROSOFT-CDO-IMPORTANCE',
  'X-MICROSOFT-DISALLOW-COUNTER',
};

/// Result of [scrubFeed].
class ScrubResult {
  ScrubResult(
    this.text,
    this.events,
    this.eventsWithTeamsLink,
    this.eventsWithMeetLink,
    this.dropped,
  );

  /// The scrubbed feed, CRLF line endings, folded at 75 characters.
  final String text;

  /// Number of VEVENTs in the raw feed.
  final int events;

  /// VEVENTs whose raw DESCRIPTION or LOCATION held a Teams join link.
  final int eventsWithTeamsLink;

  /// VEVENTs with a newer-style `https://teams.microsoft.com/meet/…` link
  /// (also counted in [eventsWithTeamsLink]); reported to show the mix.
  final int eventsWithMeetLink;

  /// Names of properties that were dropped, with counts.
  final Map<String, int> dropped;
}

String _fnv(String s) {
  var hash = 0xcbf29ce484222325;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

String _fold(String line) {
  if (line.length <= 75) {
    return line;
  }
  final out = StringBuffer(line.substring(0, 75));
  for (var i = 75; i < line.length; i += 74) {
    final end = i + 74 < line.length ? i + 74 : line.length;
    out.write('\r\n ${line.substring(i, end)}');
  }
  return out.toString();
}

/// Scrubs [raw]. [capturedUtc] is written into the header so tests can pick
/// a window around the time the feed was captured.
ScrubResult scrubFeed(String raw, {required DateTime capturedUtc}) {
  final lines = unfoldLines(raw);
  final out = <String>[];
  final titles = <String, int>{};
  final places = <String, int>{};
  final people = <String, int>{};
  final dropped = <String, int>{};
  var events = 0;
  var withTeams = 0;
  var teamsInEvent = false;
  var linkNumber = 0;

  int numberFor(Map<String, int> map, String key) =>
      map.putIfAbsent(key, () => map.length + 1);
  String teamsUrl() =>
      'https://teams.microsoft.com/l/meetup-join/19%3ameeting_SCRUBBED${++linkNumber}%40thread.v2/0?context=%7b%7d';

  // First pass: which raw events have a Teams link (per VEVENT).
  final eventHasTeams = <bool>[];
  var meetLinks = 0;
  String? description;
  String? location;
  for (final rawLine in lines) {
    final cl = parseContentLine(rawLine, 0);
    if (cl == null) {
      continue;
    }
    if (cl.name == 'BEGIN' && cl.value.trim().toUpperCase() == 'VEVENT') {
      description = null;
      location = null;
    } else if (cl.name == 'DESCRIPTION') {
      description = unescapeText(cl.value);
    } else if (cl.name == 'LOCATION') {
      location = unescapeText(cl.value);
    } else if (cl.name == 'END' && cl.value.trim().toUpperCase() == 'VEVENT') {
      eventHasTeams.add(extractTeamsJoinUrl(description, location) != null);
      if (_meetLink.hasMatch('$description $location')) {
        meetLinks++;
      }
    }
  }

  for (final rawLine in lines) {
    final cl = parseContentLine(rawLine, 0);
    if (cl == null) {
      continue;
    }
    final value = cl.value;
    switch (cl.name) {
      case 'BEGIN':
        out.add('BEGIN:${value.trim()}');
        if (value.trim().toUpperCase() == 'VCALENDAR') {
          out
            ..add('X-TMINUS-CAPTURED:${_utcStamp(capturedUtc)}')
            ..add(
              'X-TMINUS-RAW-TEAMS-EVENTS:'
              '${eventHasTeams.where((has) => has).length}',
            );
        } else if (value.trim().toUpperCase() == 'VEVENT') {
          teamsInEvent = events < eventHasTeams.length && eventHasTeams[events];
          events++;
          if (teamsInEvent) {
            withTeams++;
          }
        }
      case 'X-WR-CALNAME':
        out.add('X-WR-CALNAME:Scrubbed calendar');
      case 'UID':
        out.add('UID:uid-${_fnv(value.trim())}');
      case 'SUMMARY':
        final title = unescapeText(value).trim();
        final prefix = isCancelledTitle(title) ? 'Canceled: ' : '';
        out.add('SUMMARY:${prefix}Event ${numberFor(titles, title)}');
      case 'DESCRIPTION':
        out.add(
          teamsInEvent
              ? 'DESCRIPTION:Microsoft Teams meeting\\nJoin: <${teamsUrl()}>'
              : 'DESCRIPTION:Scrubbed description',
        );
      case 'LOCATION':
        final place = unescapeText(value).trim();
        if (place.isEmpty) {
          out.add('LOCATION:');
        } else if (extractTeamsJoinUrl(null, place) != null) {
          out.add('LOCATION:${teamsUrl()}');
        } else if (place.toLowerCase().contains('microsoft teams')) {
          out.add('LOCATION:Microsoft Teams Meeting');
        } else {
          out.add('LOCATION:Place ${numberFor(places, place)}');
        }
      case 'ORGANIZER' || 'ATTENDEE':
        final who = (cl.params['CN'] ?? value).trim().toLowerCase();
        final n = numberFor(people, who);
        final partstat = cl.params['PARTSTAT'];
        out.add(
          '${cl.name};CN="Person $n"'
          '${partstat == null ? '' : ';PARTSTAT=$partstat'}'
          ':mailto:person$n@example.com',
        );
      default:
        if (keptProperties.contains(cl.name)) {
          out.add(rawLine);
        } else {
          dropped[cl.name] = (dropped[cl.name] ?? 0) + 1;
        }
    }
  }
  final text = '${out.map(_fold).join('\r\n')}\r\n';
  return ScrubResult(text, events, withTeams, meetLinks, dropped);
}

String _utcStamp(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

final _meetLink = RegExp(
  r'https://teams\.microsoft\.com/meet/',
  caseSensitive: false,
);

final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

/// Email addresses left in [text] that are not @example.com.
List<String> leakedEmails(String text) => [
  for (final m in _email.allMatches(text))
    if (!m[0]!.toLowerCase().endsWith('@example.com')) m[0]!,
];

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/scrub_feed.dart <raw.ics> <scrubbed.ics>',
    );
    exit(64);
  }
  final raw = await File(args[0]).readAsString();
  final result = scrubFeed(raw, capturedUtc: DateTime.now().toUtc());
  final leaks = leakedEmails(result.text);
  if (leaks.isNotEmpty) {
    stderr.writeln(
      'Refusing to write: ${leaks.length} email address(es) survived scrubbing.',
    );
    exit(1);
  }
  await File(args[1]).writeAsString(result.text);
  stdout
    ..writeln('VEVENTs: ${result.events}')
    ..writeln('VEVENTs with a Teams join link: ${result.eventsWithTeamsLink}')
    ..writeln(
      'VEVENTs with a teams.microsoft.com/meet/ link: '
      '${result.eventsWithMeetLink}',
    )
    ..writeln('Dropped properties: ${result.dropped}')
    ..writeln('Wrote ${args[1]}');
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/ics_core && dart test test/scrub_feed_test.dart && dart analyze`
Expected: `All tests passed!` then `No issues found!`

- [ ] **Step 6: Commit the scrubber**

```bash
git add .gitignore packages/ics_core/tool/scrub_feed.dart packages/ics_core/test/scrub_feed_test.dart
git commit -m "Add a scrubber for real ICS feeds" -m "tool/scrub_feed.dart keeps a feed's structure (zones, rules, exceptions, overrides, busy status) and replaces all personal text, ids and links, keeping a synthetic Teams link where the real feed had one. Raw feeds are git-ignored."
```

- [ ] **Step 7: Ask the user for their feed, then stop and wait**

Send the user this message and wait for their answer:

> I need your published Outlook calendar feed to test `ics_core` against real data (Outlook → Settings → Calendar → Shared calendars → Publish a calendar → "Can view all details" → copy the **ICS** link). The link works like a password, so either:
> 1. save the `.ics` file yourself as `packages/ics_core/test/fixtures/private/feed.raw.ics` (that folder is git-ignored), or
> 2. paste the link here and I'll download it to that path.
>
> Only a scrubbed copy, with every title, description, location, person, address, UID and link replaced, is committed. I'll show you that copy before committing it, and I'll delete the raw file at the end.

- [ ] **Step 8: Put the raw feed in the ignored folder**

If the user pasted the link, run (repo root), with the link in place of `<ICS link from the user>`:

```bash
mkdir -p packages/ics_core/test/fixtures/private
curl -sS --fail --max-time 30 -o packages/ics_core/test/fixtures/private/feed.raw.ics "<ICS link from the user>"
```

Do not repeat the link anywhere else: not in files, commit messages or your report.
Then run: `git check-ignore -v packages/ics_core/test/fixtures/private/feed.raw.ics`
Expected: a line naming `.gitignore` and the `packages/ics_core/test/fixtures/private/` rule. Also run `git status --short` and confirm that nothing under `private/` is listed.
If curl fails (HTTP 401/403/404), tell the user that the link was rejected and ask for a fresh one. Do not retry in a loop.

- [ ] **Step 9: Scrub it**

Run: `cd packages/ics_core && dart run tool/scrub_feed.dart test/fixtures/private/feed.raw.ics test/fixtures/real_feed_scrubbed.ics`
Expected: four report lines (`VEVENTs: N`, `VEVENTs with a Teams join link: T`, `VEVENTs with a teams.microsoft.com/meet/ link: M`, `Dropped properties: {...}`), then `Wrote test/fixtures/real_feed_scrubbed.ics`. Note N, T and M for the report in Step 13. If it prints `Refusing to write`, an address survived. Find which property carried it, add that property to the scrubber's rewritten set with a test in `scrub_feed_test.dart`, and run again.

- [ ] **Step 10: Have the user check the scrubbed copy**

Run: `grep -inE "[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}" packages/ics_core/test/fixtures/real_feed_scrubbed.ics | grep -vi "@example.com"`
Expected: no output.
Show the user the first 80 lines of `real_feed_scrubbed.ics` and the `Dropped properties` line. Ask them to confirm it contains nothing private (names, company terms, rooms). Wait for a yes before committing anything from the feed.

- [ ] **Step 11: Write the real-feed test**

`packages/ics_core/test/real_feed_test.dart`:

```dart
// The user's real published Outlook feed, scrubbed by tool/scrub_feed.dart.
// Answers spec §12.3: does the feed carry Teams join links?
import 'package:ics_core/ics_core.dart';
import 'package:test/test.dart';

import 'support.dart';

DateTime _header(String text, String name) {
  final m = RegExp(
    '^$name:(\\d{8}T\\d{6}Z)\$',
    multiLine: true,
  ).firstMatch(text);
  final v = m![1]!;
  return DateTime.utc(
    int.parse(v.substring(0, 4)),
    int.parse(v.substring(4, 6)),
    int.parse(v.substring(6, 8)),
    int.parse(v.substring(9, 11)),
    int.parse(v.substring(11, 13)),
    int.parse(v.substring(13, 15)),
  );
}

void main() {
  final text = fixture('real_feed_scrubbed.ics');
  final captured = _header(text, 'X-TMINUS-CAPTURED');
  final rawTeamsEvents = int.parse(
    RegExp(
      r'^X-TMINUS-RAW-TEAMS-EVENTS:(\d+)$',
      multiLine: true,
    ).firstMatch(text)![1]!,
  );

  IcsResult expand(Duration before, Duration after) => expandIcs(
    text,
    windowStartUtc: captured.subtract(before),
    windowEndUtc: captured.add(after),
    deviceZone: 'Africa/Johannesburg',
  );

  // The app's own window (spec §5) and a wide one that sees the whole feed.
  final appWindow = expand(const Duration(hours: 1), const Duration(days: 7));
  final wide = expand(const Duration(days: 400), const Duration(days: 400));

  test('parses with zero issues', () {
    expect(wide.issues, isEmpty);
    expect(appWindow.issues, isEmpty);
  });

  test('yields occurrences', () {
    expect(wide.occurrences, isNotEmpty);
  });

  test('every occurrence is well formed', () {
    for (final o in wide.occurrences) {
      expect(o.endUtc.isBefore(o.startUtc), isFalse, reason: '$o');
      expect(o.startUtc.isUtc && o.endUtc.isUtc, isTrue, reason: '$o');
    }
  });

  test('Teams join links are found exactly when the raw feed had them '
      '(spec §12.3)', () {
    final linked = wide.occurrences.where((o) => o.joinUrl != null);
    expect(linked.isNotEmpty, rawTeamsEvents > 0);
  });
}
```

- [ ] **Step 12: Run it**

Run: `cd packages/ics_core && dart test test/real_feed_test.dart`
Expected: `All tests passed!`
If `parses with zero issues` fails, the real feed contains something the handcrafted fixtures missed. Use superpowers:systematic-debugging. Reproduce the failing VEVENT as a minimal handcrafted case in the test file of the unit that owns the bug (e.g. `values_test.dart`, `expand_recurring_test.dart`), with invented names, then fix the code and rerun the whole suite. Never paste raw feed text into a test.

- [ ] **Step 13: Report spec §12.3 to the user**

Tell the user, filling in the numbers from Step 9 and the test run:

> **Spec §12.3 (Teams link in the feed):** your published feed has N events; T of them carry a Teams join link in DESCRIPTION or LOCATION, and `expandIcs` extracts it. M of those T use the newer `teams.microsoft.com/meet/` style; the rest use `/l/meetup-join/`.

If T is 0, say plainly that the feed does not carry join links. The Agenda's Teams badge and the alarm screen's Join button (spec §8) would then never appear for this source, and the device-calendar source matters more. If the feed shows a Teams link shape that neither pattern matches, report it with a scrubbed example.

- [ ] **Step 14: Commit the fixture and test, then delete the raw feed**

```bash
git add packages/ics_core/test/fixtures/real_feed_scrubbed.ics packages/ics_core/test/real_feed_test.dart
git status --short
git commit -m "Test ics_core against a scrubbed real Outlook feed" -m "A scrubbed copy of the user's published feed parses with no issues and yields occurrences. Teams join links are found exactly when the raw feed had them, which answers spec section 12.3."
rm -rf packages/ics_core/test/fixtures/private
```

Before committing, check that `git status --short` lists only those two files as staged and nothing under `private/`.

- [ ] **Step 15: Final verification**

Run, one at a time:
- `cd packages/ics_core && dart format --set-exit-if-changed lib tool test` → `Formatted N files (0 changed)`
- `cd packages/ics_core && dart analyze` → `No issues found!`
- `cd packages/ics_core && dart test` → `All tests passed!`
- (repo root) `flutter analyze` → `No issues found!`
- (repo root) `flutter test` → `All tests passed!`
- `git status --short` → clean (the ignored `private/` folder is gone).

---

## Self-review

**Spec coverage** (spec §5 "ics_core", §9, §11, §12.3; roadmap §2):
- Parses VCALENDAR/VEVENT/VTIMEZONE, unfolds folded lines → Tasks 2, 3, 6; `folded_lines.ics` (Task 8).
- CLDR windowsZones table, then VTIMEZONE, then device zone with a warning → Tasks 5, 6; `windows_tzids.ics` (Task 8).
- RRULE via `rrule`, then EXDATE, then RECURRENCE-ID overrides → Tasks 4, 9, 10.
- Drops `STATUS:CANCELLED` and `Canceled:`/`Cancelled:` titles → Task 7; `canceled_titles.ics` (Task 8); cancelled overrides (Task 10).
- `X-MICROSOFT-CDO-BUSYSTATUS` → free/tentative/busy/oof, TRANSP fallback → Task 7.
- Teams join URL from DESCRIPTION/LOCATION → Task 7; `teams_links.ics` (Task 8).
- Per-event error isolation, whole-feed `IcsFormatException` → Tasks 3, 8 (`malformed.ics`), 9 (broken RRULE).
- §11 fixtures: weekly RRULE + EXDATE (Task 9), modified and cancelled instance (Task 10), Windows TZIDs (Task 8), organiser in a DST zone (Task 9), all-day and multi-day (Task 8), `Canceled:` titles (Task 8), Teams links (Task 8), folded lines (Task 8), scrubbed real feed (Task 11).
- §12.3 answered and reported → Task 11, Step 13.
- Roadmap §2 types and signature reproduced exactly → Task 1 (model), Task 8 (`expandIcs`); `lib/ics_core.dart` exports only these.

**Placeholder scan:** every code step has complete code. The only values filled in at run time are the user's feed (Task 11) and the numbers in the §12.3 report; the real-feed test reads its expectations from the scrubbed file's header, so its code is fixed.

**Type consistency:** `expandSeries` has three parameters in Task 9 and gains `overrides` in Task 10, which also replaces `expand_ics.dart` whole, so both call sites change together. `ensureTimeZonesLoaded` is created in Task 5 (minimal) and kept, with the same signature, when Task 6 replaces `zone_resolver.dart`. `IcsWindow`, `ZoneResolver`, `ParsedEvent` and `IcsTime` names match across tasks.

**Review Focus:** each of the five items has a test in its owning task (Tasks 3, 6, 7, 8).
