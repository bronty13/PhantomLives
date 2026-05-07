# Changelog

All notable changes to Timeliner are documented here. The version number is
auto-derived from git's commit count (`1.0.<count>`), so this log groups
changes by feature rather than by exact bundle version.

## 1.1.x — Phase 2 (post-MVP, on the same `main` branch)

The MVP shipped at commit `20017c6`; everything below was added on top
of it as part of the Phase 2 work plan, and is included in the current
build.

### Added

- **Sample data** — Timeliner now ships with two curated true-crime
  sample cases bundled as JSON resources: *Murder of Madeline Soto*
  (150 events, 43 people) and *Murder of Harmony Montgomery* (42
  events, 28 people, body never recovered). On first launch (empty
  database, never-seen-samples flag false) all samples are auto-
  installed so the app isn't empty. Deleting a sample doesn't trigger
  a silent re-install; **Settings → General → Restore Sample Data…**
  is the explicit re-add path. Sample case IDs are prefixed `sample-`
  so the restore flow never touches user-authored cases.
  - The Codable layer is intentionally lenient and accepts both shapes
    seen in the curated sources (`name` vs `title`, `timeline_events`
    vs `events`, `people_involved` vs `people`, `description` vs
    `notes`, etc.) so adding new sample cases doesn't require a
    schema-conversion pass on the source JSON.
- **Polymorphic attachments** — first-class attachments on cases,
  events, and people. File bytes stored as BLOBs in the SQLite database
  (so they're carried by every backup zip). 25 MB per-file cap; image
  files automatically get a 256-pt JPEG thumbnail.
- **Horizontal pan/zoom timeline** — Canvas-rendered alternate timeline
  view per case. Drag to pan, scroll/magnify to zoom, click an event
  dot to edit, double-click empty space to add an event at that
  in-time position.
- **Cross-case combined timeline** — sidebar section that merges any
  selected subset of cases onto a single horizontal axis with
  deterministic per-case color coding.
- **PDF export** (⌘⇧P) — renders the same HTML pipeline used by the
  HTML exporter through `WKWebView`, paginated to US-letter portrait.
- **Anniversary reminders** — opt-in `UNUserNotificationCenter`
  calendar-anniversary reminders for important events. Configurable
  importance floor, lookahead window, and notification hour. Asks for
  authorization only when the user enables the feature and points to
  System Settings if the user previously denied.
- **Custom theme builder** — new sheet under Settings → Themes lets
  users clone a built-in theme and edit gradient stops, accent, card,
  sidebar, and track colors with a live preview card.
- **Per-slot font customization** — Settings → Fonts. Override family
  (system / system-mono / system-serif / system-rounded / custom
  PostScript name), size, and weight independently for event title,
  event body, date column, and sidebar slots.

### Changed

- **Schema bumped to v2** (`v2_attachments_blob`). The v1 attachments
  table (created but never user-facing) is dropped and replaced with a
  polymorphic shape — `parent_type` ('case' / 'event' / 'person') +
  `parent_id`, `data` BLOB, optional `thumbnail_data` BLOB, `position`
  for user-controlled ordering. Safe drop because the v1 UI never
  shipped.
- **Sidebar grew from 5 sections to 6** — added "Cross-case Timeline".
- **Settings grew from 7 tabs to 9** — added "Fonts" and
  "Notifications" tabs.
- `AppState.deleteCase` now manually cascades attachment rows, since
  the polymorphic `attachments` table can't enforce a real FK against
  three different parent tables.

### Tests

- Added migration test asserting the polymorphic attachments table
  has the expected columns + BLOB type and accepts insertion against
  all three parent kinds.
- Added `SampleDataServiceTests` (6 tests): both bundled JSON
  resources load + decode to the documented counts (Madeline Soto
  case_001 / 43 people / 150 events, Harmony Montgomery / 28+ people /
  42+ events with the merged outcome footer present), role-category →
  PersonRole mapping is exhaustive, category → Importance mapping is
  correct, lenient date parser handles year-only / year-month /
  full-date / with-time inputs, and the case-status string heuristic
  maps conviction wording to `closed`.

## 1.0.0 — Phase 1 MVP

Initial public build at commit `20017c6`. Establishes the core domain
model, the on-disk database, the timeline UI, and the auto-backup-on-
launch convention.

### Added

- **Cases** — CRUD with status (active / cold / closed) and pinning.
  Status reflected in sidebar icon and case-card badge.
- **Events** — date + optional end-date range, markdown description, source
  URL, four-level importance flag (low / medium / high / critical).
- **Tags** — hex-colored chips, per-event tagging via the editor sheet,
  filter pills in the timeline view, dedicated Tags settings tab.
- **People** — six built-in roles (suspect / victim / witness / attorney
  / detective / other) with customizable chip colors, per-event linking.
- **Vertical chronological timeline** — year/month section headers,
  importance pip indicator, tag and person chips, double-click to edit.
- **Filters** — date-range, tag set, importance set, plain-text query.
  All filters compose; "Clear" resets them in one click.
- **Cross-case search** — ranked across cases, events, people, tags.
- **Themes** — Default / Midnight / Ocean / Forest / Sunset / Rose, with
  a preview swatch in Settings → Themes.
- **Standalone HTML export** — single self-contained file per case (inline
  CSS + JS), drops at `~/Downloads/Timeliner/<Title>-<timestamp>.html`.
  XSS-escaped, no external dependencies.
- **Auto-backup-on-launch** — debounced (skip if last run < 5 min old),
  retention-trimmed, default location `~/Downloads/Timeliner backup/`,
  default 14-day retention. Verify-and-restore UI in Settings → Backup.
- **Custom app icon** — programmatically generated clock-and-pins icon via
  `Scripts/generate-icon.swift` at build time.
- **Settings scene** — seven tabs at MVP: General, Appearance, Themes,
  Tags, People Roles, Export, Backup. (Two more added in 1.1.x.)
- **Tests** — migration round-trips, Codable round-trips, search ranking,
  HTML export self-containment + XSS escaping, BackupService retention
  trim + auto-mkdir + sort order.
