# Changelog

All notable changes to CalendarMaker are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is
[SemVer](https://semver.org/).

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
