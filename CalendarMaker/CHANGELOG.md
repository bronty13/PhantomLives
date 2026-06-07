# Changelog

All notable changes to CalendarMaker are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is
[SemVer](https://semver.org/).

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
