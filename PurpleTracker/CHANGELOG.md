# Changelog

All notable changes to PurpleTracker are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] — Notes Workspace (WYSIWYG)

### Added
- **Notes** sidebar section with user-configurable Note Types. Seeds with
  defaults: Staff, Architecture, Team, SCRUM, Third Party.
- **WYSIWYG rich-text editor** (NSTextView-backed) with bold / italic /
  underline / strikethrough, H1–H3 + Body styles, bullet & numbered lists,
  hyperlinks, text color, and clear-formatting. Bodies are persisted as RTF.
- **Per-type note lists** grouped by date with search across title and body.
- **Settings → Note Types** tab to add, rename, reorder, and delete types.
  Deletion is blocked when notes still reference the type.
- Migration `v8_notes_workspace` adds `note_type` + `generic_note` tables and
  seeds the five default types.

## [1.4.0] — Third Parties (Vendors)

### Added
- **Third Parties sidebar section** — manages a roster of vendors / 3rd-party
  suppliers separate from Matters. Click "+ New Vendor" or use the All-Vendors
  Report menu for cross-vendor exports.
- **Vendor detail tabs:** Overview · Contacts (Sales / Escalation / Technical)
  · Products (repeatable list) · Budget & Actuals (per-year matrix) · Contracts
  · Invoices · Other Files · Contract Summary · Costing Summary · Exit Strategy
  · Notes · Linked Matters.
- **1–5 star rating** with optional rating note.
- **Reseller picker** — Cyber One / CDW / Other (free-text when "Other").
- **Budget & Actuals matrix** — year range is a single global setting in
  Settings → Third Parties (defaults to 2026–2035). Each row shows Budget,
  optional manual Actual override, and the computed Effective Actual.
- **Invoices** are first-class rows. Adding one with backdated date drops
  into the correct year automatically. Optional file attachment per invoice.
  Effective Actual = manual override if set, otherwise sum of invoices.
- **Notes** with add/edit/delete and per-note file attachments. Timestamped.
- **BLOB attachments** (contracts / invoices / notes / other) stored inside the
  SQLite DB with SHA1 integrity, matching the existing Matter attachment model.
- **Matter ↔ Vendor link** — Matter Overview tab now has a "Third Party"
  selector. Vendor detail shows the linked Matters and lets you jump to them.
- **Single-vendor reports** — Markdown or PDF, Summary or Full.
- **All-vendors reports** — Markdown or PDF, Basic (name/contact/rating/reseller
  table) or Detailed (full sheets concatenated).
- **Settings → Third Parties** — configure the budget/actuals year range.

### Schema
- Migration `v6_third_parties` adds `vendor`, `vendor_contact`,
  `vendor_product`, `vendor_year_amount`, `vendor_invoice`, `vendor_note`, and
  `vendor_attachment` tables. `matter.vendor_id` is added with
  `ON DELETE SET NULL` so vendor hard-delete is safe.

## [1.3.0] — Mega-release: dashboards, palette, trash, and more

### Added
- **Today dashboard** — sun icon at the top of the sidebar. Shows Overdue,
  Due Today, Due This Week, and In-Progress (no due date) at a glance.
- **Time Dashboard** — Swift Charts of hours per day and per Type for the
  last 7 / 14 / 30 / 90 days.
- **Analytics dashboard** — open vs. closed counts plus charts by Type,
  Priority, and Initiative.
- **Capacity dashboard** — open Matter counts per Requestor; spot
  bottlenecks across the team in seconds.
- **⌘K Command Palette** — fuzzy search across Matters, people, and
  quick actions. Use ↑/↓ then return.
- **Saved Searches** — save the current search bar query as a sidebar
  pin via Tools → "Save Current Search…".
- **Bulk actions on the Matter list** — select multiple rows (⌘-click /
  shift-click), right-click for Set Priority, Set Status, Move to Trash.
- **Soft-delete with Trash** — deletes are now reversible. Trashed Matters
  live in a new sidebar bin and are permanently purged 30 days later.
- **Per-Matter audit log (History tab)** — every status, priority, type, or
  title change, plus delete / restore, is recorded with a timestamp.
- **Subtasks tab** — lightweight checklist on each Matter; the row badge
  shows `done/total` progress.
- **Linked Matters tab** — relate Matters with `depends_on` (directional)
  or `related` (informational); click a chip to jump to that Matter.
- **Menu-bar mini timer** — `⏱ HH:MM — Title` always visible while the
  timer runs; click the menu-bar item to stop or start.
- **Stop-with-note prompt** — clicking Stop on the global timer banner now
  asks for an optional one-line note that gets stored on the time entry.
- **Open primary store in editor** — Overview tab now has an "Open in"
  menu next to Reveal: Finder, VS Code (`vscode://`), Obsidian (`obsidian://`).
- **OneDrive / file-store status indicator** — shows whether the primary or
  secondary path exists, how many files it contains, and last-modified time.
- **Calendar (.ics) export** — Tools → "Export Calendar (.ics)…" writes a
  one-VEVENT-per-open-due-Matter file you can subscribe to from Calendar.
- **URL autofill** — paste a SNOW or ADO URL into an external link field
  and the corresponding Number field is populated automatically (only when
  the Number field is empty).
- **Email intake** — drag a `.eml` onto the sidebar to create a Matter with
  the email's Subject as the Title and From + body as the description.
- **Integrity check** — Tools → "Run Integrity Check…" re-hashes every
  attachment BLOB (SHA1) and reports any mismatches plus dangling person
  FKs and orphaned subtasks.
- **Time-by-tag Markdown reports** — Tools menu can copy a Markdown table
  of hours per Initiative or per Goal (time evenly split across tags).
- **Keyboard shortcuts** — ⌘K Command Palette · ⌘⇧1..4 jump to dashboards ·
  ⌘⇧Space toggle the active timer.
- **Created audit event seeded** for every new Matter so the History tab
  always has a starting point.
- **Dark-mode tuned palette** — pill backgrounds use a higher opacity in
  dark mode for better contrast.

### Schema
- Migration v5 adds: `matter.deleted_at`, plus tables `subtask`,
  `matter_link`, `audit_event`, `saved_search`. All foreign keys cascade
  on Matter deletion.

### Notes
- The 30-day Trash purge runs once on launch (after `BackupService`).
- Touch Bar support is intentionally not provided (deprecated on M-series).

## [1.2.1] — Tidy `~/Downloads/` layout

### Changed
- Everything PurpleTracker writes to `~/Downloads/` is now under a single
  `~/Downloads/PurpleTracker/` umbrella. New defaults:
  - **Backups:** `~/Downloads/PurpleTracker/Backup/`
    (was `~/Downloads/PurpleTracker backup/`)
  - **Exports:** `~/Downloads/PurpleTracker/Exports/`
    (was `~/Downloads/PurpleTracker/`)
  - **Secondary file store template:**
    `~/Downloads/PurpleTracker/Files/{title}`
    (was `~/Downloads/PurpleTracker/{title}`)
- One-shot migration on launch: any zips under the legacy
  `~/Downloads/PurpleTracker backup/` folder are moved into the new
  `Backup/` sub-folder; the empty legacy folder is then removed. Customised
  paths are left alone.

## [1.2.0] — Initiatives, Goals, Priority

### Added
- **Priority** — fixed five-level pick (P1 Critical, P2 High, P3 Medium,
  P4 Low, P5 Tech Debt), prominently shown as a color-coded pill in the
  Matter detail header and as a `P#` badge on every list row. New Matters
  default to **P3 Medium**. Priority carries forward to the next instance
  for cadenced Matters.
- **Initiatives** — configurable many-to-many tagging. Manage the master
  list under **Settings → Initiatives**. Tag any Matter with one or more
  Initiatives from the Matter's Overview tab. Default seeds:
  - Meet all client commitments
  - Grow Originations ARR
  - Optimize operations
  - Develop plans for new sources of revenue
  - Grow client base opportunistically
  - Increase revenue per client
  - Market expansion
  - Acquisitions
- **Goals** — configurable many-to-many tagging, parallel to Initiatives.
  Manage under **Settings → Goals**. Default seeds:
  - Checkmarx Onboarding
  - Disaster Recovery Business Continuity Risk Goal
  - Information Security Team Goal
  - Mimecast Expansion
  - Optimize Assurance
  - Optimize SentinelOne
  - Support All defi Initiatives
- Markdown / PDF / DOCX exports now include the Matter's Priority,
  Initiatives, and Goals.
- Cadenced Matters carry their Priority and their Initiative + Goal tags
  forward when spawning the next instance.

### Schema (v4)
- `matter` gains `priority TEXT NOT NULL DEFAULT 'P3 Medium'` plus an
  `idx_matter_priority` index.
- New tables `initiative(id, name, sort_order)` and
  `goal(id, name, sort_order)`.
- Join tables `matter_initiative(matter_id, initiative_id)` and
  `matter_goal(matter_id, goal_id)` with composite PKs and `ON DELETE
  CASCADE` from both sides.

## [1.1.0] — People, Interested Parties, app icon

### Added
- **People roster** — new `person` table keyed on Associate ID, populated
  from the daily ADP IMP UserFeed CSV
  (`~/Downloads/ADP_IMP_UserFeed_YYYY-MM-DD.csv`).
  - Settings → **People** lets you import a specific file or "Import Latest
    from Downloads", and shows totals + last-imported timestamp.
  - **Auto-import on launch** (default ON, toggleable in Settings → People):
    on every launch, scans `~/Downloads/` for the newest matching file and
    imports it if the filename hasn't been imported before.
  - Re-imports are upserts on Associate ID; titles, names, departments, and
    position status are refreshed each time.
- **Requestor** on every Matter — searchable picker over the People roster.
  Display is `Name (Title)`. Stored as a stable Associate ID FK.
- **Interested Parties** — five fixed slots per Matter, each a People-roster
  picker. Carry forward to the next instance for cadenced Matters.
- **External Interested Parties** — five free-text slots per Matter for
  contacts who aren't in the company roster. Carry forward for cadenced
  Matters.
- **Cross-Matter search** now also matches Requestor + Internal IP names
  (resolved via the People roster) and External IP free text.
- **Matter list IP badge** — `person.2.fill` glyph with a count appears on
  any row where one or more IP slot is populated.
- **PersonPicker dropdown without typing** — focusing the picker shows the
  top 50 active people sorted by last name, so users can browse without
  typing. Typed queries still use the prefix → contains scoring.
- **App icon** — Big-Sur-style purple squircle with a white "PT" monogram and
  a small accent dot. Generator script lives at `Resources/make_icon.py`.
- **Test coverage:** new tests for CRLF/BOM CSV handling, the real ADP
  UserFeed parse, External IP rendering in exports, IP carry-forward across
  cadenced successors, and the latest-ADP-file scan helper.

### Changed
- `RequestorPicker` is now a thin wrapper around a generalized `PersonPicker`
  (one component drives all six person slots on a Matter).
- Export Markdown header now includes **Requestor**, and References
  enumerates **Interested Parties** and **External Interested Parties**.
- Default secondary file-store template is `~/Downloads/PurpleTracker/{title}`
  (was `~/Downloads/{title}`); existing user customisations are preserved.

### Fixed
- **CSV parser CRLF bug** — Swift treats `\r\n` as a single grapheme cluster,
  so the original `Character`-based `parseCSV` silently swallowed every
  Windows line ending and collapsed the entire file into one row. Parser now
  iterates `Unicode.Scalar`, strips an optional UTF-8 BOM, and tolerates lone
  `\r` (classic Mac) endings. Regression tests guard the fix.
- Cleaned the three `result of 'try?' is unused` warnings in
  `OverviewTab.pathRow`, `PurpleTrackerApp` New-Matter command, and
  `SidebarView` New-Matter menu.

### Schema
- Migration `v2_people_and_requestor` — added `person` table, indexes on
  `(last_name, first_name)` and `position_status`, and `requestor_associate_id`
  on `matter`.
- Migration `v3_interested_parties` — added 10 columns to `matter`:
  `interested_party{1..5}_associate_id` (FK person.id) and
  `external_interested_party{1..5}` (free text).

## [1.0.0] — initial release

### Added
- **Matter ID allocator** — every record gets a primary key in the form
  `YYYY-MM-DD-#####` (zero-padded, sequence resets daily starting at `00001`).
  Allocation runs inside the same write-transaction as the matter insert so a
  failed insert releases the sequence.
- **Matter record** with title, type, multi-tier status (New → In-Progress →
  Complete → Post-Mortem → Closed), markdown description / notes / resolution /
  lessons, due date, time-tracking code, three external system links, primary &
  secondary file-store paths, attachments, time entries, and timestamped notes.
- **Configurable types & status** in Settings, each with its own color. Type
  color drives the matter list row & detail header so the kind of work is
  visible at a glance.
- **Spell-checked markdown editor** (`SpellCheckTextEditor`) — `NSTextView`-backed
  with continuous spell-checking on by default; auto-correction toggle in Settings.
- **Time tracking** — single global timer button on each matter; first time
  entry against a New matter auto-bumps it to In-Progress. Per-matter time
  detail and a global cross-matter weekly timesheet (sums hours per matter
  per ISO week).
- **Attachments** stored as SQLite BLOBs with MD5, SHA1, and SHA256 computed
  on ingest. SHA1 is recomputed on access; mismatch surfaces a non-blocking
  alert and flags the row.
- **File store paths** — primary defaults to
  `~/Library/CloudStorage/OneDrive-defiSOLUTIONS/<currentYear>/<YYYY-MM-DD Title>`,
  secondary defaults to `~/Downloads/<Title>`. Templates, year, and sanitisation
  are configurable. "Create" makes the directory; "Reveal" opens it in Finder.
- **External references** — three configurable label / number / URL slots.
  Defaults: `defi SUPPORT (SNOW)`, `Azure DevOps (ADO)`, `Client Reference`.
  Each row has a launch button that opens the URL.
- **Cadenced Activities** — type flagged as cadenced gets a repeat rule (Daily,
  Weekly, Bi-weekly, Monthly, Quarterly, Semi-annually, Annually, or Custom
  every N days). Closing a cadenced matter spawns the next instance with a new
  Matter ID, due date pushed forward, copied refs, and a `parent_matter_id` link.
- **Exports** — Markdown, PDF, Word `.docx`, or copy-to-clipboard for the full
  record report; "Copy brief" for `MatterID • Title • Date Opened • Status`.
- **Auto-backup on launch** per the PhantomLives standard, with a 30-day default
  retention. Settings tab exposes Backup Now, Verify, Restore (with mandatory
  pre-restore safety backup), and Reveal in Finder.
- **Settings tabs:** General, Types, Status, External Refs, File Store, Backup.
- **Test suite** (22 tests across 8 test cases) covering the Matter ID allocator
  (incl. rollback releases sequence), MD5/SHA1/SHA256 hash vectors and
  mismatch detection, all cadence kinds, backup retention & ordering, file-store
  template rendering, exports, migration idempotency, and status auto-transition.

### Notes
- Built on macOS 14, Swift 5.10, SwiftUI, GRDB 6 (vendored under `Vendor/GRDB`).
- Database lives at `~/Library/Application Support/PurpleTracker/purpletracker.sqlite`.
- Backups land in `~/Downloads/PurpleTracker backup/` by default.
- Exports land in `~/Downloads/PurpleTracker/` by default.
