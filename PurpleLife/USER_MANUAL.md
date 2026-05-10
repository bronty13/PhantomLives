# PurpleLife User Manual

A native macOS Life OS for tracking everything personal — planner, hobbies, contacts, reading, weight, photos — as configurable object types. Data lives locally in SQLite, mirrors across your Macs through CloudKit (end-to-end encrypted with `encryptedValues`), and is backed up nightly to a restorable zip.

## Where your data lives

| Location | Purpose |
|---|---|
| `~/Library/Application Support/PurpleLife/` | DB (`purplelife.sqlite`), `settings.json`, `schema.json`, `attachments/` |
| `~/Downloads/PurpleLife backup/` | Auto-backup zips named `PurpleLife-YYYY-MM-DD-HHmmss.zip` |
| `~/Downloads/PurpleLife/` | User-visible exports (reserved; exporter is queued) |

CloudKit holds the same data in your private database; on-disk files stay readable without iCloud.

## The window

Single window split into:

1. **Sidebar (left)** — **Today** at the top, then your object **Types** (People, Books, Cameras, Photo Shoots, WoW Characters, Photos, Planner, Weight by default). Sidebar bottom shows live **sync status** with a "Sync now" button.
2. **Detail pane (right)** — Today, or a type's records in one of four view styles, or the Object detail when a row is double-clicked.

## Today

The first screen you see on launch. Each panel is one **saved query** — there are no hard-coded modules. The seeded panels are:

- **Today's planner** — Planner Items where Status = Pending, sorted by date ascending.
- **Latest weight** — Weight, most recent by date.
- **Currently reading** — Books where Status = Reading.
- **Recent people** — recent People.
- **Updated in the last 7 days** — anything modified in the rolling 7-day window.

Click **Edit panels** in the toolbar to add / edit / delete / reorder. Each panel can be scoped to a type, filtered by a field equality / "within N days" / "field is set" / no filter, sorted by any field of the type, limited to N rows. **Restore defaults** re-adds any deleted built-in panels.

Double-click a card on Today to open the record's detail.

## Object types

Each type defines a set of **fields**, plus optional hints that drive the four views:

| Hint | Used by |
|---|---|
| `primaryFieldKey` | The "title" cell in every view |
| `kanbanGroupKey` | Defaults the kanban column-by-field selection |
| `calendarDateKey` | Defaults the calendar's date-source field |
| `galleryAttachmentKey` | Picks the field whose image is shown in gallery cards |

### Built-in types (seeded on first launch)

- **Planner Item** — title, date, status (Pending / Doing / Done / Cancelled), project, notes.
- **Person** — display name, first/last name, email, phone, relationship, notes.
- **Book** — title, author, status (Want to read / Reading / Finished / Abandoned), started, finished, rating, cover image, notes.
- **Camera** — model, brand, kind, purchased, serial, photo, notes.
- **Photo Shoot** — title, date/time, location, camera (link), status, cover photo, notes.
- **WoW Character** — name, class, level, realm, faction, status, notes.
- **Photo** — title, taken, camera (link), shoot (link), rating, kind, image, notes.
- **Weight** — date, pounds, body-fat %, source, notes.

User-defined types are unrestricted. Built-ins can be hidden from the sidebar but not deleted.

## The four list views

Each type's records can be rendered four ways. The toolbar segment auto-hides views that don't apply (no select field → no kanban tab, no date field → no calendar tab, no attachment field → no gallery tab).

- **Table** — generic spreadsheet over the type's fields. Empty primary fields show "Untitled" italic; other empty cells show "—". Double-click a row → object detail. Right-click → Open / Delete.
- **Kanban** — columns grouped by a select field. Cards show the primary title plus up to three supporting fields. Records whose value isn't one of the defined options collect into an "—" column. Double-click a card → detail.
- **Calendar** — month grid with prev/next/today nav. Records appear on the cell matching their `calendarDateKey` field. Up to 3 record titles per cell + overflow count.
- **Gallery** — adaptive grid of cards. Real attachment images render when the type has a `galleryAttachmentKey` field with a stored image; placeholder gradient otherwise. Rating badges overlay when the type has a rating field.

The toolbar **+** button creates a new record and opens it in the detail sheet immediately so you can fill in fields without landing on a blank row.

## Object detail

Double-click a row → editor sheet with one input per field kind:

- text / URL / email → `TextField`
- long text → `TextEditor` (multi-line)
- number → numeric `TextField`
- date / date+time → native `DatePicker`
- yes/no → `Toggle`
- select → menu picker
- multi-select → wrapping chip cluster (click to toggle)
- rating → 5 toggleable stars
- **link** → popover record picker with search-as-you-type across every type, grouped by type with sticky headers, "Clear link" footer
- **attachment** → file picker, real thumbnail preview with dimensions / size / Reveal-in-Finder

Click **Done** to save.

## Schema editor

`⇧⌘S` (or Window → Schema editor…). Split layout:

- **Types rail** — built-in vs custom badges, hidden indicator. Right-click a built-in to hide/show; right-click a custom type to delete.
- **Field list** — rename / mark required / delete per field. The current primary-field is badged.
- **Field-type palette** — 12 kinds (text, long text, number, date, date+time, yes/no, select, multi-select, link, rating, URL, email, attachment). Click to add a field of that kind. Duplicate-name protection (`New text`, `New text 2`, …).

Field deletes leave the data in `fields_json` blobs in place; a re-add of the same name doesn't lose history.

## ⌘K Quick Switcher

`⌘K` opens a floating window with live FTS5 search across every record of every type. Title and all text-bearing field values are indexed (porter tokenizer, prefix-matched). Arrow keys to navigate, Enter to open, Escape to dismiss. The index is rebuilt on every launch (cheap) and maintained incrementally on every mutation.

## Settings (`⌘,`)

Two tabs:

### Backup

- **Auto-backup** — toggle (default on), directory picker (default `~/Downloads/PurpleLife backup`), retention stepper (`0` means keep forever), "Run backup now".
- **Recent backups** — newest-first list, per-row **Test** (non-destructive verify, reports object count + migrations) / **Restore** (with mandatory pre-restore safety backup + confirmation alert) / **Reveal** in Finder.

Backups run automatically on every launch, **debounced** to skip if the last successful backup is under 5 minutes old. Failures are logged via `NSLog` and never block app launch.

### Import

- **WeightTracker CSV** — file picker that ingests a WeightTracker export. Header auto-detects lb vs kg; kg → pounds conversion is applied. Per-row errors collect into a report; the run never aborts on a single bad row.

## CloudKit sync

The sidebar footer shows live status:

- **Setting up sync…** — first-launch bootstrap, account check, custom-zone ensure, initial pull, push of local-only rows.
- **Synced** — idle, last sync timestamp captured.
- **Syncing…** — pull in progress.
- **Sync error: …** — last error message; the service retries automatically.
- **Sign in to iCloud** — your Mac has no iCloud account; the app stays fully usable locally.
- **Sync off** — iCloud entitlement not provisioned or container not assigned; local-only mode.

The **"Sync now"** button forces a pull on demand. Pushes happen automatically on every mutation; a 30-second poll keeps the local DB current while the app is in the foreground.

**Encryption**: the JSON blob holding all field values is stored on CloudKit's servers via `CKRecord.encryptedValues`. Apple cannot decrypt it — the keys live only inside your iCloud Keychain trust circle, not on Apple's servers. Plaintext columns on the same record (`type_id`, `parent_id`, `created_at`, `updated_at`) are still server-readable.

**Conflict resolution**: deterministic last-write-wins by `updated_at`. Same-field offline edits on two Macs reconcile when both reconnect.

## Attachments

Files referenced by `.attachment` fields live at:

```
~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>
```

Content-addressed: the same file referenced by multiple records de-duplicates on disk. Deleting a reference only prunes the file when the last reference is gone. The metadata table (`attachments`) handles cascading deletes when a parent record is removed.

Files travel inside backup zips automatically. CloudKit sync of attachment **content** (via `CKAsset`) is queued; today only the sha256 ref syncs through the JSON blob.

## Versioning

Shown in the Today header. Format: `vMAJOR.MINOR.COMMITS (COMMITS.SHORTSHA)`. The commit count makes every successful build a strictly newer version, which keeps install-overwrite predictable.

## Known limitations (as of v0.1.x)

- CloudKit sync is poll-based (30 s in foreground). Real-time silent-push subscriptions are queued.
- CloudKit asset sync isn't wired — attachments stay local; the metadata ref syncs but the file itself doesn't (yet).
- No undo for mutations (deletes are confirmed; rest are immediate).
- No keyboard shortcuts for new-record-per-type (use the toolbar **+** or `⌘K` quick capture).
- No export pipeline yet (CSV / Markdown / PDF). Restoring from a backup zip is the supported "get your data out" path until then.
- Schema versioning across synced peers isn't reconciled — running different schema versions on two Macs can create user-visible drift; for now keep both Macs on the same build.
