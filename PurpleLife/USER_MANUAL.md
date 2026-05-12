# PurpleLife User Manual

A native macOS Life OS for tracking everything personal — planner, hobbies, contacts, reading, weight, photos — as configurable object types. Data lives locally in SQLite, mirrors across your Macs through CloudKit (end-to-end encrypted with `encryptedValues`), and is backed up nightly to a restorable zip.

## Where your data lives

| Location | Purpose |
|---|---|
| `~/Library/Application Support/PurpleLife/` | DB (`purplelife.sqlite`), `settings.json`, `schema.json`, `attachments/` |
| `~/Downloads/PurpleLife backup/` | Auto-backup zips named `PurpleLife-YYYY-MM-DD-HHmmss.zip` |
| `~/Downloads/PurpleLife/` | User-visible exports (reserved; exporter is queued) |

CloudKit holds the same data in your private database; on-disk files stay readable when iCloud's offline. **All on-disk files are encrypted at rest** — see "Your data is encrypted" below.

## Your data is encrypted

PurpleLife treats your data as private by default. Three layers:

- **At rest on this Mac.** `settings.json`, every attachment file, and the entire SQLite database (via SQLCipher) are encrypted under a 256-bit key. The key lives in the macOS Keychain by default; you can layer a passphrase on top via Settings → Security.
- **In transit.** Every byte that crosses the network goes over TLS to Apple's CloudKit servers.
- **In iCloud.** Each record's fields ride through CloudKit's end-to-end encryption (`encryptedValues`). Apple stores the bytes but cannot read them. Rich-text note bodies, including inline pasted images, are inside this encrypted blob — never as separate `CKAsset` files, which Apple holds keys for.

**Settings → Security** is where the lifecycle lives:

- **Add passphrase…** wraps the encryption key under a passphrase you choose. After this, "Lock now" clears the key from the Keychain and the next access requires you to type the passphrase.
- **Change passphrase…** re-wraps the key (millisecond operation; nothing is re-encrypted).
- **Remove passphrase…** reverts to Keychain-only protection. Data stays encrypted on disk; the app just opens silently again.
- **Lock now** clears the in-memory key + Keychain cache. Useful before walking away from the Mac.
- **Reset (destroys all data)** wipes the keystore. Use only if you've forgotten your passphrase and accept that data encrypted with the lost key is unrecoverable.

**There is no passphrase recovery.** If you forget the passphrase and the Keychain cache is gone (clean reinstall, new Mac without iCloud Keychain), the data on this Mac is permanently inaccessible. The other Macs syncing your iCloud account still hold the same data through their own keys; restore by signing in there.

The full whitepaper — threat model, primitives, known limitations — is in [`Docs/SECURITY.md`](Docs/SECURITY.md) in the source tree.

## Notes

The **Notes** type is a WYSIWYG journaling space. Click "Notes" in the sidebar to open the two-pane workspace: search + date-grouped list on the left, full editor on the right.

- **New note** — `+` in the toolbar or **⌘N**. The new note opens with today's date and an empty title.
- **Title + date + body**. Date controls the section a note lands in on the list. The body editor is rich text: **⌘B** bold, **⌘I** italic, **⌘U** underline, **⇧⌘X** strikethrough, **⌘⌥1/2/3** heading levels, **⌘⌥0** body, **⇧⌘7/8** bullet / numbered list, **⌘K** link. Paste a screenshot — it appears inline.
- **Autosave** — your edits flush 1.2 s after you stop typing, when you switch to another note, and when you leave the workspace. The footer shows **Saved** / **Unsaved…**.
- **Search** filters on both title and body text.
- **Right-click → Delete** removes a note. Undo (⌘Z) re-creates it with the same id and inbound links intact.

**Image-size policy** — pasted images wider than 1920 pixels are scaled down to 1920 wide; non-transparent images encode as JPEG @ 0.7 quality for storage efficiency. Compression isn't a privacy compromise; the bytes still travel through `encryptedValues` end-to-end. If a note grows too large to sync (CloudKit caps a record at ~1 MB), the editor shows a red banner with the byte count and keeps your edits intact so you can trim and try again.

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

## The five list views

Each type's records can be rendered five ways. The toolbar segment auto-hides views that don't apply (no select field → no kanban tab, no date field → no calendar tab, no attachment field → no gallery tab, non-numeric primary field → no charts tab).

- **Table** — generic spreadsheet over the type's fields. Empty primary fields show "Untitled" italic; other empty cells show "—". Double-click a row → object detail. Right-click → Open / Delete.
- **Kanban** — columns grouped by a select field. Cards show the primary title plus up to three supporting fields. Records whose value isn't one of the defined options collect into an "—" column. Double-click a card → detail.
- **Calendar** — month grid with prev/next/today nav. Records appear on the cell matching their `calendarDateKey` field. Up to 3 record titles per cell + overflow count.
- **Gallery** — adaptive grid of cards. Real attachment images render when the type has a `galleryAttachmentKey` field with a stored image; placeholder gradient otherwise. Rating badges overlay when the type has a rating field.
- **Charts** — line chart over time, available when the type's primary field is numeric AND the type has at least one date field. Time-range picker (7D / 30D / 90D / 1Y / All). Same-day duplicates collapse last-write-wins per calendar day. For Weight specifically, three overlay toggles appear in the toolbar: **Trend** (linear regression line), **7d avg** (moving-average dashed line), **Goal** (horizontal RuleMark at the goal weight set in Settings → Weight). Y-axis auto-scales with padding so the goal line stays in view.

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

## Schema editor (⇧⌘S)

`⇧⌘S` (or Window → Schema editor…). Split layout:

- **Types rail** — built-in vs custom badges, hidden indicator. Right-click a built-in to hide/show; right-click a custom type to delete. Right-click any type to export it as a `.purplelifeschema.json` file.
- **Field list** — rename / mark required / delete per field. The current primary-field is badged.
- **Field-type palette** — 12 kinds (text, long text, number, date, date+time, yes/no, select, multi-select, link, rating, URL, email, attachment). Click a tile to add a field, or drag it onto the field list. The drag preview tints the tile in the accent color so you can tell it's "active." A short field list shows a dashed drop-zone hint.
- **Reorder fields** via the per-row menu (`Move up` / `Move down`). The buttons are disabled at the array bounds.

Field deletes leave the data in `fields_json` blobs in place; a re-add of the same name doesn't lose history.

### Schema library

The toolbar's **Library** button (or **Browse library…** below the types rail) opens a searchable gallery of **575 ready-made schemas** spanning planning, home admin, finance, health, food, hobbies, media, travel, creative work, career, learning, relationships, pets & animals, nature observation, and a deliberate "Unusual & Niche" bucket (dream journal, cocktails, tarot readings, mushroom foraging, sleep paralysis episodes, fortune cookies, mishap log, lefse batches, sleep talking, doppelgängers, time capsules, Mandela effects, party stories, found pennies, and more — including a 50-state License Plate sighting tracker for road-trip games). Pick a category in the sidebar, free-text search across names / fields / keywords, preview the field list with view-defaults (primary / kanban / calendar / gallery) called out, and click **Import** to drop a clean copy into your workspace. Each import gets fresh ids, so you can import the same template twice (or import-edit-import) without collisions. Library entries always land as user-defined types — they're not built-ins, so you can rename, delete, or hack them up freely.

### Import / export

The toolbar's **More** menu carries import + export actions:

- **Import from file…** — pick one or more `.purplelifeschema.json` files. Every type in every file becomes a new user-defined type in your registry. Plural-name collisions get an "(imported)" suffix.
- **Export <selected type>…** — single-type export, named after the type's plural form.
- **Export multiple…** — opens a checklist sheet; pick the subset to bundle into one file.
- **Export all…** — writes every type (built-in + custom) into one `schemas-N.purplelifeschema.json`.
- **Reset built-ins to defaults…** — confirmation-gated. Restores Planner, Notes, People, Books, etc. to their bundled shape. Your records survive (record data keys by field key, not by field id, and field keys are stable). Custom types and hidden-flags are untouched. Undoable.

The `.purplelifeschema.json` envelope is plain JSON — any tool can open it. A bare array of `ObjectType` objects also imports for forward-compat. Same files round-trip across Macs (each import gets fresh ids on read, so re-importing won't collide with the version already synced through CloudKit).

## ⌘K Quick Switcher

`⌘K` opens a floating window with live FTS5 search across every record of every type. Title and all text-bearing field values are indexed (porter tokenizer, prefix-matched). Arrow keys to navigate, Enter to open, Escape to dismiss. The index is rebuilt on every launch (cheap) and maintained incrementally on every mutation.

## Quick capture (menu bar)

A small wand icon (`✨`) in the system menu bar opens a compact capture popover. Pick a type, type the title (or whatever the type's primary field is — Person uses "Name", Book uses "Title", etc.), and hit ⌘↩. The record lands in the database, the popover clears the title field for repeat capture, and a brief green "Saved to <type>" status confirms it. Esc closes the popover.

The type picker remembers your last choice and defaults there next time, so dropping in a string of planner items or weight entries is one keystroke per record.

## Keyboard shortcuts

- **⌘N** — New record of the currently-selected type. (No-op when Today is selected — Today doesn't have a type.)
- **⌘1 … ⌘9** — Jump to the Nth visible type in the sidebar.
- **⌘K** — Quick switcher (search every record across every type).
- **⇧⌘S** — Schema editor.
- **⌘Z** / **⇧⌘Z** — Undo / redo. Covers record creates, edits, deletes, and schema mutations (add/edit/delete a type, add/rename/delete a field, hide/show a built-in). Multiple steps are undone in order. Cross-Mac: an undo on this Mac propagates to your other Macs the same way any other change does.
- **⌘,** — Settings.

## Export (Records → toolbar)

Every type's records list has an Export menu in the toolbar (next to **New X**). Two groups of actions:

- **Save to file** — writes a single timestamped file to your export directory. **CSV** is RFC-4180 (commas / quotes / newlines escaped); columns are `id`, every field on the type, then `created_at` / `updated_at`. **Markdown** is the same data shaped as a Markdown table, with pipes and embedded newlines escaped. **HTML** is a styled standalone table that opens in any browser. **PDF** renders the HTML through WebKit (US-letter portrait).
- **Copy to clipboard** — same CSV or Markdown text, into the system clipboard. Useful for dropping a slice of your data into a spreadsheet or a chat without ever touching disk.

After a file save, Finder pops to the export directory with the new file selected.

Cell rendering follows the field type: select / multi-select resolve option ids to display names (multi-select joined by `|`); link fields resolve to the linked record's title; attachment fields render the original filename when known and the sha256 otherwise; missing fields render as empty cells.

The default export directory is `~/Downloads/PurpleLife/`. Override it in **Settings → Export**.

## Settings (`⌘,`)

Five tabs:

### Appearance

- **Appearance** — segmented picker: **Auto** (sync with macOS system setting — default), **Light**, **Dark**. Setting overrides the system appearance for PurpleLife only.
- **Theme** — grid of palette cards. Each card shows a miniature preview of the theme's chrome (sidebar / window background / card surface / accent). Selected theme gets an accent-colored ring + checkmark.

Built-in themes (all purple-rooted, so the brand voice carries regardless of choice):

- **Royal Purple** (default) — flagship oklch palette from the design handoff.
- **Lavender** — softer pastel; cooler surfaces, easier on the eyes for long sessions.
- **Plum** — deeper, more saturated; higher-chroma accents.
- **Heather** — warm mauve-leaning; pairs warm cream with rose-tinted accents.
- **High Contrast** — accessibility-focused; pure white/black surfaces with bold strokes and a saturated purple accent. Designed for low-vision users and bright environments.

Switching theme or appearance takes effect immediately across every open window — no relaunch needed.

#### Custom themes

Click **+ New theme** in the Custom themes section to open the **theme builder**. The new draft starts as a duplicate of whichever theme is currently selected, so you're tweaking from a sane base rather than from scratch.

The builder is a sheet split into two panes:

- **Editor (left)** — sections grouped by purpose: Surfaces (window background, sidebar, card), Text (primary / secondary / faint), Lines (card border, hairline, row hover), Accent (primary, soft). Each row has **two color pickers** side-by-side — Light then Dark — so you tune both halves of a slot in one place.
- **Preview (right)** — miniature rendering of PurpleLife's chrome (sidebar with mock type rows, main area with a header, two list rows, and a card). The preview has its own **Light / Dark toggle** at the top — independent of your actual appearance setting — so you can audit both halves of every slot before committing.

Actions in the footer:

- **Cancel** — close without saving.
- **Save** — write the draft back into your themes and switch to it immediately. If you're editing an existing theme, the entry is updated in place (the picker grid doesn't reorder).
- **Save as…** — clone the draft as a new theme with a fresh UUID and a name you supply. The original is unchanged. The new theme becomes active.
- **Delete** (only shown when editing an existing theme) — remove the theme. If it was active, the app falls back to the built-in it was based on (or Royal Purple if the base is unknown).

To **edit** an existing custom theme later, click the pencil icon on its card in the theme picker.

`settings.json` continues to accept hand-edited `userThemes` entries (each with `#AARRGGBB` hex strings per slot for both light and dark) if you'd rather author themes outside the app.

#### Sharing themes between Macs

Themes can travel as `.purplelifetheme.json` files.

- **Export** — right-click any theme card (built-in or custom) and choose **Export theme…**. A Save panel writes a single JSON file (defaults to `~/Downloads/PurpleLife/` or your configured export directory). The builder sheet has its own **Export…** button so you can ship a draft mid-edit without saving it locally first.
- **Import** — in the Custom themes section, click **Import…** and pick a `.purplelifetheme.json` file. The theme is added to your custom themes and immediately becomes active. Re-importing the same file produces a new entry (with a fresh internal id), so you can keep multiple copies for further tweaking.

### Backup

- **Auto-backup** — toggle (default on), directory picker (default `~/Downloads/PurpleLife backup`), retention stepper (`0` means keep forever), "Run backup now".
- **Recent backups** — newest-first list, per-row **Test** (non-destructive verify, reports object count + migrations) / **Restore** (with mandatory pre-restore safety backup + confirmation alert) / **Reveal** in Finder.

Backups run automatically on every launch, **debounced** to skip if the last successful backup is under 5 minutes old. Failures are logged via `NSLog` and never block app launch.

### Import

- **Smart Import — Weight (free-form text)** — opens a wizard. Paste any text containing dates and weights — CSV / spreadsheet copy-paste / plain English (`On 3/5/2024 I weighed 182 pounds`) all work. Five date formats recognized: ISO-8601, `MM/DD/YYYY`, `MM-DD-YYYY`, `Jan 15 2024`, `January 15, 2024`. Weight extraction uses plausibility bounds (50-700 lb) and lookarounds so year digits aren't matched as weights. Preview table per parsed row; rows that match an existing Weight day are flagged "dup" and pre-deselected. Imports use `source: "Imported"` for filter consistency.
- **WeightTracker CSV** — file picker that ingests a WeightTracker export. Header auto-detects lb vs kg; kg → pounds conversion is applied. Per-row errors collect into a report; the run never aborts on a single bad row.

### Export

- **Default export directory** — text field + Choose…, Reveal button. Files saved by the Records → Export menu land here. Default `~/Downloads/PurpleLife/`. Empty value reverts to the default.

### Weight

User profile values used by the Charts view's Goal-line overlay and the Statistics panel. Each field is optional — leaving any blank just means the dependent feature won't show.

- **Goal weight** (lb) — drives the Goal-line overlay on the Weight chart and the days-to-goal estimate in Statistics.
- **Starting weight** (lb) — optional override of the first-record value when computing total change. Leave blank to use the first record.
- **Height** (in) — required for BMI in the Statistics panel.
- **Forecast horizon** — stepper (1-365 days, default 30). Controls the projection horizon in the Statistics panel.

## Weight statistics (Records → Weight → toolbar)

When viewing the **Weight** type's records, a **Statistics** button appears in the toolbar (next to Export). It opens a sheet with four sections:

- **Overview** — starting / current / goal weight, total change, progress bar to goal.
- **Trend analysis** — weekly rate (rolling 4-week), regression slope (lb/day), R² consistency score, best and worst week.
- **BMI** (only if Height is set) — current / starting / goal BMI with category labels (underweight / healthy / overweight / obese).
- **Forecast** — projections at 7 / 14 / 30 / 60 / 90 days; estimated days to reach goal (when slope is downward and a goal is set).

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
