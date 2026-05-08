# USER MANUAL — PurpleTracker

PurpleTracker assigns every unit of work a permanent **Matter ID** and tracks
everything around it: type, status, time, attachments, file-store paths,
external-system references, notes, resolution, lessons learned, and exports.

---

## Matter IDs

A Matter ID looks like `2026-05-07-00001`:

- `YYYY-MM-DD` is the date the matter was created.
- `#####` is a zero-padded sequence number that **resets to `00001` every day**
  and increments for each matter created that day.
- The ID is shown in large monospaced text wherever the matter appears, with
  a copy button beside it (the `MatterIDBadge` component).

The allocator is transactional: if the matter insert fails, the sequence
number is released — there are no gaps within a day.

---

## Creating a matter

1. Click **New Matter** in the sidebar (or `⌘N`).
2. Fill in **Title** and pick a **Type**. Type drives the row colour.
3. Status defaults to the first lifecycle value (**New**).
4. Save. The Matter ID is allocated at save-time.

The matter immediately gets:

- A row in the matter list, colour-coded by type.
- Default file-store paths rendered from the templates in Settings.
- An empty notes log, time log, and attachments list.

---

## Status lifecycle

Default order: **New → In-Progress → Complete → Post-Mortem → Closed**.

- **Auto-bump:** when you log the first time entry against a matter that is
  in the *first* lifecycle value (typically "New"), the status is bumped to
  the *second* value (typically "In-Progress"). The rule keys off the lifecycle
  position, so renaming the values is safe.
- **Manual transitions:** all other transitions happen via the status menu in
  the matter detail header.
- **Cadenced matters** (see below) automatically spawn the next instance when
  they reach the *last* lifecycle value (typically "Closed").

You can rename, reorder, or add status values in **Settings → Status**.

---

## Description, Notes, Resolution, Lessons Learned

These four fields are markdown with embedded continuous spell-checking.
Auto-correction is off by default — toggle it in **Settings → General**.

The **Notes** tab also keeps a separate timestamped log: each entry has its
own creation time, last-modified time, and can be edited or deleted
independently.

---

## Time tracking

- The **Time** tab shows a single Start/Stop button. Only one timer can be
  running globally — starting a new one stops the previous one and records
  its time entry.
- The active timer is persisted to `settings.json`, so it survives a quit
  and you'll be prompted to resume on the next launch.
- The per-matter view lists every time entry with start, stop, duration,
  and an optional note.
- The **Time → Weekly** view (sidebar) shows a global cross-matter weekly
  timesheet — sums per matter per ISO week.

---

## Attachments

Drop a file onto the **Attachments** tab (or click **Add**). PurpleTracker:

1. Reads the file into memory.
2. Computes **MD5**, **SHA1**, and **SHA256** with CryptoKit.
3. Stores the bytes as a SQLite BLOB along with the filename, size, MIME, and
   all three hashes.

When you preview, open, or export an attachment, **SHA1 is recomputed and
compared** with the stored value. A mismatch:

- raises a non-blocking red banner on the row,
- sets `last_verify_ok = false` in the database,
- still lets you open the file (you may want to inspect it).

A green check on the row means the most recent verification matched.

---

## File-store paths

Every matter has a **primary** and **secondary** file-store path. Defaults:

- Primary: `~/Library/CloudStorage/OneDrive-defiSOLUTIONS/<currentYear>/<YYYY-MM-DD Title>`
- Secondary: `~/Downloads/<Title>`

Both are rendered from templates you can edit in **Settings → File Store**.
Variables: `{year}`, `{date}` (matter creation date), `{title}` (sanitised for
the filesystem), `{matterId}`.

Each path has:

- **Create** — `mkdir -p` the folder if missing.
- **Reveal** — open it in Finder via `NSWorkspace.activateFileViewerSelecting`.

---

## External references

Three slots, each with a configurable label, a number/identifier, and a URL.
Defaults:

- `defi SUPPORT (SNOW)`
- `Azure DevOps (ADO)`
- `Client Reference`

Edit the labels in **Settings → External Refs**. Each row in the matter
detail has a launch button that opens the URL in your browser.

---

## Cadenced Activities

A type marked **cadenced** (default: "Cadenced Activities") gets a repeat rule:

| Kind             | Next due date                |
|------------------|------------------------------|
| Daily            | +1 day                       |
| Weekly           | +7 days                      |
| Bi-weekly        | +14 days                     |
| Monthly          | +1 month                     |
| Quarterly        | +3 months                    |
| Semi-annually    | +6 months                    |
| Annually         | +1 year                      |
| Custom (every N) | +N days (you set N)          |

When you transition a cadenced matter to the *last* lifecycle value
(typically "Closed"), `CadenceService` creates the next instance:

- new Matter ID,
- due date pushed forward by the cadence,
- title / type / external refs / time-tracking code copied,
- fresh notes / time / attachments,
- linked to the original via `parent_matter_id`.

---

## Exports

Each matter detail has an **Export** menu:

- **Markdown** — the full record as a `.md` file.
- **PDF** — the same content rendered to PDF via `NSPrintOperation`.
- **Word (`.docx`)** — a minimal hand-built WordprocessingML document.
- **Copy report to clipboard** — the markdown form, on the pasteboard.
- **Copy brief to clipboard** — `MatterID • Title • Date Opened • Status`.

Default export folder: `~/Downloads/PurpleTracker/` (configurable in Settings).

---

## Backups

PurpleTracker follows the PhantomLives auto-backup-on-launch standard:

- A backup runs **on every launch** (debounced: at most one per 5 minutes).
- Backups are zips of the database file plus settings, named
  `PurpleTracker-YYYY-MM-DD-HHmmss.zip`.
- Default location: `~/Downloads/PurpleTracker backup/`.
- Default retention: **30 days**. Set retention to `0` to keep forever.

**Settings → Backup** exposes:

- Enable / disable, change folder.
- **Backup now** — runs immediately, ignoring the debounce.
- **Recent backups** list with **Verify** (zip integrity + sanity-counts the
  `matter`, `attachment`, and `time_entry` rows in the embedded DB),
  **Restore** (creates a mandatory pre-restore safety backup first), and
  **Reveal in Finder**.

---

## Settings overview

- **General** — auto-correct toggle, default export folder, current year override.
- **Types** — add / rename / delete / recolor; flag any type as cadenced.
- **Status** — add / rename / reorder lifecycle values.
- **External Refs** — relabel the three external systems.
- **File Store** — edit the primary & secondary path templates.
- **Backup** — toggle, folder, retention (default 30 days), Backup Now,
  Recent Backups list with Verify / Restore / Reveal.
- **People** — import the ADP IMP UserFeed CSV, browse the roster, toggle
  auto-import on launch.
- **Initiatives** — manage the strategic-initiative tag list.
- **Goals** — manage the team/quarterly-goal tag list.

---

## Priority, Initiatives & Goals

**Priority** is a fixed five-level pick:

| Level | Color  |
|------:|:-------|
| P1 Critical | red    |
| P2 High     | orange |
| P3 Medium   | amber (default) |
| P4 Low      | green  |
| P5 Tech Debt | slate |

It's shown as a prominent pill in the Matter detail header (next to the
Status pill) and as a small `P#` badge on every list row. New Matters open
at **P3 Medium**. Cadenced successors inherit the predecessor's priority.

**Initiatives** are a configurable list of strategic initiatives a Matter
can be tagged against. Defaults seeded on first run cover the team's
current strategic themes (Meet all client commitments, Grow Originations
ARR, Optimize operations, etc.). Manage the list under
**Settings → Initiatives**.

**Goals** are a parallel configurable list for team / quarterly goals
(Checkmarx Onboarding, Optimize SentinelOne, etc.). Manage the list under
**Settings → Goals**.

Tag a Matter from the Overview tab using the **Tag** menus next to each
section. Tags are many-to-many — a Matter can carry any number of
Initiatives and Goals, and an Initiative or Goal can be applied to any
number of Matters. Tags carry forward when a cadenced Matter spawns its
successor, and are included in markdown / PDF / DOCX exports.

---

## Keyboard shortcuts

---

## People, Requestor & Interested Parties

PurpleTracker keeps a local roster of company people sourced from the daily
**ADP IMP UserFeed** CSV that lands in `~/Downloads/` as
`ADP_IMP_UserFeed_YYYY-MM-DD.csv`.

**Importing:**

- *Auto on launch* (default ON) — Settings → People → "Auto-import latest ADP
  file on launch". On every launch, the newest matching file in `~/Downloads/`
  is imported if its filename hasn't been imported before. Filename is the
  dedupe key, so you only pay the cost once per ADP rotation.
- *Manual* — Settings → People → **Import CSV…** to pick any file, or
  **Import Latest from Downloads** to grab the newest one immediately.
- All imports upsert by Associate ID, so you can re-import any time —
  job titles, names, departments, and position status are refreshed.

**Using on a Matter:**

- **Requestor** — one slot per Matter. Searchable picker; click the field to
  see the top 50 active people, or start typing to narrow.
- **Interested Parties** — five slots per Matter, all pickers over the
  People roster.
- **External Interested Parties** — five free-text slots for contacts who
  aren't on the company roster (auditors, vendor reps, client SMEs, etc.).
- The matter list shows a small `person.2` badge with a count whenever any
  IP slot is populated. Search matches Requestor + IP names (resolved) and
  External IP free text.
- Cadenced Matters carry every Requestor / IP slot forward to the successor.

---

## Troubleshooting

- **"App can't be opened because it is from an unidentified developer."** —
  right-click the app → **Open** the first time (the build is ad-hoc signed).
- **Attachment shows a red exclamation mark** — SHA1 didn't match. Open the
  file and check whether it has been altered or corrupted; re-add it if it's
  the version you want to keep.
- **Backup didn't run** — check **Settings → Backup**; the auto-backup is
  debounced to at most one per 5 minutes per launch.
