# Changelog

All notable changes to CalendarMaker are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is
[SemVer](https://semver.org/).

## 0.3.2 — 2026-06-14

### Changed
- **Book grid now uses compact 3-char abbreviations** (Genesis → `Gen`,
  1 Samuel → `1Sa`, Philippians → `Phi`) so far more books fit per row — the whole
  Old Testament fits in ~6 rows. Each button keeps the **full book name as a hover
  tooltip and accessible (screen-reader) label**, so abbreviations that collide
  (Phi-lippians/Phi-lemon, Jud-ges/Jud-e) are still disambiguable.

### Tests
- +1 (book buttons display the abbreviation but expose the full accessible name).
  52 total.

## 0.3.1 — 2026-06-14

### Changed
- **Much faster Bible verse picker** (both the day-level picker and the
  whole-month Sayings & Verses picker). The old three cascading dropdowns are
  replaced by a **Bible-study-style** picker:
  - **Type-ahead jump box** — type a reference (`John 3:16`, `1 Jo 5 4`,
    `Phil 4:13`) and press **Enter** to grab it instantly.
  - **Tap drill-down** — a grid of **books** (grouped Old/New Testament; filtered
    live as you type a name like `phil` → Philippians / Philemon), then a grid of
    **chapters**, then a grid of **verses**. A **breadcrumb** (Book › Chapter ›
    Verse) lets you jump back a level with one click.
- New shared component `BibleVersePicker` powers both pickers.

### Tests
- +4 (type-ahead full-reference commit, prefix filtering, tap drill-down, and
  numbered-book parsing like `1 Jo`). 51 total.

## 0.3.0 — 2026-06-14

### Added
- **Bible verses & sayings as per-day items.** Click any day and add a **Bible
  Verse** (via a Book → Chapter → Verse picker over the full embedded NASB) or a
  **Saying** (a searchable list of the seeded + your custom sayings, with a
  Random button). Both are first-class item types alongside Prayer, Praise, etc.,
  and carry a reference (e.g. `John 3:16`) or attribution.
- **Two verse display modes**, toggled per calendar in the editor toolbar:
  - **Separate Calendar** (default) — verses/sayings are kept off the main grid
    and printed on their own landscape **"Scripture & Sayings"** calendar page.
    Export order is configurable for Both mode: *Calendar → Scripture → Detail*
    (default) or *Calendar → Detail → Scripture*.
  - **Force in Cells** — verses/sayings are plastered at the top of each day cell
    (shrink-to-fit), and the colored list dots are suppressed for a cleaner look.
    Remaining space still shows other items if they fit (the overflow guarantee
    is preserved — a reserved block height is subtracted before packing).
- **Enhanced sayings editor** in Settings — inline **click-to-edit** for each of
  your custom sayings (text + attribution), a collapsible built-in sayings
  reference, and an inline "Add new saying" form. Edit/Delete per entry, saved
  immediately.

### Changed
- The detail view now appends a verse/saying's reference inline (e.g.
  `Bible Verse: For God so loved… — John 3:16`).
- All 10 built-in themes gained `bibleVerse` and `saying` styles.
- The bundle-level **footer/grid filler** ("monthly" saying/verse inserter) stays
  as an option, unchanged.

### Tests
- +9 (4 fit/overflow tests for force mode + invariants; 5 PDF tests for the verse
  calendar page across modes/orderings). 47 total.

### Notes
- Embedded fonts ship only normal/bold faces, so verse *italic* is a preview-only
  visual cue — the PDF renders verses in the theme's normal weight.

## 0.2.2 — 2026-06-07

### Fixed
- **Home verse/saying "another" only worked sometimes.** The reroll was a tiny ↻
  glyph in the card corner that was easy to miss. The **whole feature card is now
  clickable** (keyboard-accessible too) with a clearer "↻ another" affordance, and
  rerolling a verse now **always lands on a different verse** (excludes the current
  one). Saying reroll already excluded the current one.

### Tests
- +2 (verse reroll always returns a valid non-empty verse; never returns the
  excluded reference). 37 total.

## 0.2.1 — 2026-06-07

### Fixed
- **Blank/stuck "Loading…" screen when opened from `file://`** (the shipped
  distribution mode). Chromium browsers (Vivaldi, Brave, Chrome) **hang
  `indexedDB.open` on the opaque `file://` origin**, so the app never finished
  loading. Storage moved from IndexedDB to **`localStorage`** (with an in-memory
  fallback); all stored data is small so this is ample. The `storage/db.ts` API
  is unchanged (still async). Verified rendering in headless Chromium from
  `file://`.

### Hardened
- The startup load is wrapped in try/catch/finally so a storage failure can never
  hang the loading screen, and a new **ErrorBoundary** shows a message instead of
  a blank page if any render throws.

## 0.2.0 — 2026-06-07

### Added
- **Personalized home greeting** — a time-of-day greeting ("Good morning, Jan")
  on the home screen, using a configurable **name** in Settings (default `Jan`).
- **Custom sayings** — add your own sayings in Settings; they join the seeded pool
  for the home-screen card and the Sayings & Verses picker. Stored in IndexedDB
  (new `sayings` store, DB v2, additive/guarded); add/delete with live save.

### Changed
- Saying selection now draws from `sayingPool = seeded + custom`. `getRandomSaying`
  / `rerollSaying` take the pool explicitly.

### Tests
- +6 (greeting time-of-day + name fallback; sayings pool combine/random/reroll/empty).
  Smoke test now asserts the greeting renders. 35 total.

## 0.1.0 — 2026-06-07

Initial release.

### Added
- Self-contained offline SPA (React + TypeScript + Vite + `vite-plugin-singlefile`)
  that builds to a single `dist/index.html` and ships as `CalendarMaker-app.zip`.
- Named calendar **bundles**: create (title + month/year wizard, defaulting to
  next month), open, delete, and import/export as `.cmcal.json` (IndexedDB store).
- **Day editor** with six styled item types (Prayer, Praise, Birthday, Life
  Event, Church Event, Reminder).
- **Overflow guarantee**: the month grid can never overflow. Items that don't fit
  are kept, flagged detail-only (⊘ + distinct color), and the user picks which
  items take the limited month-grid slots ("Pin to month"). Shared jsPDF text
  metrics make the live editor warning exact and the on-screen preview WYSIWYG.
- **US holiday catalog** (federal + observances + Christian liturgical, with
  Easter computus); per-calendar one-by-one toggles.
- **Sayings & verses** fillers in the footer band or grid free space; verse
  random/picker, saying random.
- **Home screen** random verse + saying cards (per-item Settings toggles).
- **10 built-in themes** plus a full theme manager (create/duplicate/edit/delete;
  per-item-type fonts & colors). **Embedded OFL TTFs** (Latin-subset) used for
  both the preview and the PDF, so print matches screen on any machine.
- **PDF export**: Month (landscape), Detail (portrait, paginated), or Both.
- Tests: 29 across grid math, holiday/easter resolution, the fit/overflow
  invariant, PDF build (all modes), bundle IO, seed data, and a jsdom UI smoke
  test (create → overflow → holidays).
