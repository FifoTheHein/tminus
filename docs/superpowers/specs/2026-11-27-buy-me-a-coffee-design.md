# Buy Me a Coffee link: design

Approved 2026-11-27. A small change.

## Intent

Give people who like T-Minus an easy way to buy the developer a coffee
(https://buymeacoffee.com/fifothehein). It should be easy to find for someone
looking for it, but not intrusive.

## Hard constraint: nothing that could get the app flagged by Google Play

Google Play's Payments policy has been used to reject apps for donation links,
including indirect ones. StreetComplete's About screen first linked a GitHub page
that explained how to donate, then its homepage with a note that you could
donate from there. Play rejected both. WireGuard was pulled and came back only
after its donation link was removed. The looser external-link rules from
December 2025 cover US users only. So:

- The app gets no coffee link, button or text: not on the About card, not in
  onboarding, and not anywhere else.
- No page the app opens may carry the link. The app opens only the privacy
  policy (`privacyPolicyUrl`, from Settings and onboarding). That page is
  `docs/privacy.md`, drawn by `docs/_layouts/page.html`, which has its own
  footer. Both stay free of the link, and the page links nowhere else on the
  site either (a review found that its menu and back link put the home page,
  and so the coffee button, one tap away).
- The privacy policy names the GitHub issues page as the contact point, so the
  repo shows no Sponsor button: there is no `.github/FUNDING.yml`.
- The Play listing text (`docs/play/listing.md`) gets no mention of it.

## Approaches

1. **Website home page and GitHub repo only (picked).** It is visible to people
   who seek out the project. It cannot be reached from inside the app (see the
   privacy page below), only through the Play listing's Website field. A developer website with a support
   link is common and sits outside the app, so we accept that.
2. **A direct link on the About card (rejected).** It is the easiest to find, and
   the most likely to be flagged.
3. **A Website button on the About card that leads to the home page (rejected).**
   StreetComplete's version of this was rejected too.

## Design

1. **Home page, `docs/index.html`:**
   - Footer: a fourth link, `☕ Buy me a coffee`, after "Source on GitHub".
   - A closing section after `#join`, `id="support"`, in the same section style.
     It has an eyebrow, a heading, one paragraph and one secondary (outlined)
     button:
     - Eyebrow: `Support`
     - Heading: `Free, and staying that way.`
     - Text: `T-Minus has no ads, no subscriptions and no tracking. If it gets you to your meetings on time, you can buy me a coffee.`
     - Button: `☕ Buy me a coffee`, linking to https://buymeacoffee.com/fifothehein
   - It is not added to the header nav, the hero or anywhere above the fold.
   - It is a plain link styled with `site.css`. There is no Buy Me a Coffee widget
     or script (the page promises no analytics, and shareable HTML stays
     self-contained) and no QR code (most visitors are on a phone already).
2. **Privacy page:** the template keeps only its skip link. The brand in the
   header and the footer is plain text, and the menu, the "Back to T-Minus" link
   and the footer links are gone. Visitors who came from the home page use the
   browser's back button. `test/app/support_link_test.dart` fails if the
   template gains another link, if `privacy.md` gains a link, or if a
   Buy Me a Coffee link (its domain or the `coff.ee` and `bmc.link` short
   links) or the words "buy me a coffee" appear in `docs/privacy.md`,
   `docs/_layouts/page.html`, or anything that ships in the app (`lib/`,
   `android/app/src/main/`, `assets/`, `packages/ics_core/lib/`). It fails if
   a coffee link appears in `docs/play/listing.md`. It also fails if the app
   links the website or the repo anywhere other than `privacyPolicyUrl` and
   `issuesUrl`, because a Website or Source button would be the rejected
   approach 3.
3. **GitHub repo:** the README gets a short Support section that uses the same
   wording as the home page. It shows on the repo's Code tab, not on the issues
   page the privacy policy names. There is no `.github/FUNDING.yml`, and the
   test fails if one is added. Leave Settings > General > Features >
   Sponsorships off.
4. **Listing note:** `docs/play/listing.md` gets a one-line note saying that the
   home page's Support section is deliberately left out of the listing, because
   Play's Payments policy forbids donation links. This keeps the rule that the
   home page follows the listing honest.

## Calls made

- The text has no em dashes, as the app rule requires, and the site follows it too.
- The ☕ emoji is used as text, so no icon asset is needed.
- The link opens in the same tab, like the page's other external links.
