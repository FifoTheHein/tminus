# Buy Me a Coffee link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a quiet Buy Me a Coffee link to the website home page and the GitHub repo, and keep it out of everything the app shows or opens.

**Architecture:** This is docs and static HTML only. A Dart test (`flutter test`) guards the Play boundary: no coffee link in the app, the privacy page or the Play listing text. It also checks that the home page carries the link.

**Tech Stack:** Static HTML/CSS (GitHub Pages, Jekyll), Markdown, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-27-buy-me-a-coffee-design.md`

## Global Constraints

- Link: `https://buymeacoffee.com/fifothehein`. FUNDING key: `buy_me_a_coffee: fifothehein`.
- No em dashes (U+2014) in any new text.
- No coffee link, button or text under `lib/`, `android/app/src/main/`, `docs/privacy.md`, `docs/_layouts/page.html` or in `docs/play/listing.md`'s listing text. The only exception is the one-line note in `listing.md` explaining the omission, which names no link.
- No third-party script, widget or image from Buy Me a Coffee. A plain `<a>` only.
- No new file under `docs/` (so `docs/_config.yml` and `pages_config_test.dart` need no change).
- Run `dart format` only on the new test file.

## Review Focus

1. Someone taps Privacy policy in the app, then follows a link on that page: they must never see a coffee link one tap away. The page's header and footer come from `page.html`, which the guard test covers.
2. The home page at phone width (375px): the footer row wraps and the support section's button stays inside the 16px gutter, with no horizontal scroll. Check by hand in the browser.
3. Dark and light themes: the support section uses existing tokens (`.alt` is not used, because `#join` above it is already `.alt`). Check both by hand.
4. Someone later adds the link to the app "for convenience": the guard test fails and names the file.
5. The README renders on GitHub: the Support section is plain Markdown, with no HTML GitHub strips.

---

### Task 1: Guard test for the Play boundary

**Files:**
- Create: `test/app/support_link_test.dart`

**Interfaces:**
- Produces: nothing used by other code.

- [ ] **Step 1: Write the tests**

`const _coffee = 'buymeacoffee';`

- `test('the app and the pages it opens never link to Buy Me a Coffee', ...)`: walk every file under `lib/` and `android/app/src/main/` (recursive, files only), plus `docs/privacy.md`, `docs/_layouts/page.html` and `docs/play/listing.md`. Read each as `latin1.decode(file.readAsBytesSync())`, so the PNGs under `res/` do not throw. For each, `expect(text.toLowerCase(), isNot(contains(_coffee)), reason: path)`.
- `test('the home page links Buy Me a Coffee in its footer and support section', ...)`: read `docs/index.html`, then:
  - `expect(RegExp(RegExp.escape('https://buymeacoffee.com/fifothehein')).allMatches(html).length, 2)`;
  - `expect(html, contains('id="support"'))`;
  - the `<footer>` slice (from `<footer>` to `</footer>`) contains the link;
  - the `<header` slice (from `<header` to `</header>`) does not.
- `test('GitHub shows a Sponsor button for Buy Me a Coffee', ...)`: `.github/FUNDING.yml` contains the line `buy_me_a_coffee: fifothehein`.

- [ ] **Step 2: Run it, expect the first test to pass and the other two to fail**

Run: `flutter test test/app/support_link_test.dart`
Expected: 1 pass, 2 fail (no link on the home page yet, no FUNDING.yml).

- [ ] **Step 3: Negative control for the guard**

Temporarily add `<!-- buymeacoffee -->` to `docs/_layouts/page.html` and run again. Expected: the first test fails with reason `docs/_layouts/page.html`. Revert.

### Task 2: Home page, README, FUNDING.yml and listing note

**Files:**
- Modify: `docs/index.html` (footer row; new section after `#join`)
- Modify: `docs/assets/site.css` (only if the section needs a rule: at most a `.support` block, reusing tokens)
- Create: `.github/FUNDING.yml`
- Modify: `README.md` (a `## Support` section before the closing issues line, ~line 130)
- Modify: `docs/play/listing.md` (a one-line note near the Website row, ~line 84)

- [ ] **Step 1: Footer link.** In `docs/index.html`'s `footer .row`, after "Source on GitHub", add `<a href="https://buymeacoffee.com/fifothehein">☕ Buy me a coffee</a>`.
- [ ] **Step 2: Support section.** After `</section>` of `#join`, add `<section id="support" aria-labelledby="support-title">` with `.wrap` > `.section-head`: eyebrow `Support`, `<h2 id="support-title">Free, and staying that way.</h2>`, `<p>T-Minus has no ads, no subscriptions and no tracking. If it gets you to your meetings on time, you can buy me a coffee.</p>`, then `<a class="btn secondary" href="https://buymeacoffee.com/fifothehein">☕ Buy me a coffee</a>`. Do not add it to the header nav.
- [ ] **Step 3: FUNDING.yml.** It holds the single line `buy_me_a_coffee: fifothehein`.
- [ ] **Step 4: README.** Add `## Support`, using the home page's paragraph followed by `[☕ Buy me a coffee](https://buymeacoffee.com/fifothehein)`.
- [ ] **Step 5: Listing note.** In `docs/play/listing.md`, add under the table: `The website's Support section (Buy Me a Coffee) is left out of the listing on purpose: Play's Payments policy rejects donation links.` It must not contain the string `buymeacoffee`.
- [ ] **Step 6: Run the tests.** Run `flutter test test/app/support_link_test.dart test/app/pages_config_test.dart test/no_em_dash_test.dart`. Expected: all pass.
- [ ] **Step 7: Check it in the browser.** Open `docs/index.html` at 375px and at desktop width, in light and dark. Expected: no horizontal scroll, the button sits inside the gutter, and the footer wraps cleanly.
- [ ] **Step 8: Full check and commit.** Run `flutter analyze` (expect `No issues found!`) and `flutter test`. Commit the spec, the plan, the test and the files above with `git commit -F <file>`, with no Claude trailers.
