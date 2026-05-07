# Changelog

All notable changes to PurpleTracker are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
