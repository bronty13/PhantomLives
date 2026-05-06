# MasterClipper — User Manual

A personal-use macOS app for tracking video clip metadata through the Production → Post-Production → Delivery pipeline. Single window, fully local, with smart import, local-LLM description refinement, calendar generation, posting workflow, and rich exports.

## Quickstart

```bash
cd ~/Documents/GitHub/PhantomLives/MasterClipper
xcodegen generate
./build-app.sh
open MasterClipper.app
```

## File locations

| What | Where |
|---|---|
| SQLite database | `~/Library/Application Support/MasterClipper/masterclipper.sqlite` |
| Settings JSON | `~/Library/Application Support/MasterClipper/settings.json` |
| Auto-backups | `~/Downloads/MasterClipper backup/MasterClipper-YYYY-MM-dd-HHmmss.zip` |
| Exports | `~/Downloads/MasterClipper/` |

All paths are user-overridable in **Settings → Backup** and **Settings → Import / Export**.

## Sidebar tour

| Section | Purpose |
|---|---|
| **Dashboard** | Top stats (clickable filters), per-target posting progress bars, full clip × site posting matrix |
| **Editing Queue** | Master/detail of clips in `new` / `editing` / `to_post`. Toolbar: **Run File Verification**. Count badge in sidebar. |
| **Posting Queue** | Master/detail of clips in `to_post` / `posting`, with per-site posting-progress pills. Toolbar: **Run File Verification**. Count badge in sidebar. |
| **Clips** | Master/detail of every clip. Sortable Table, filters, search |
| **Calendar** | Year / Quarter / Month / Week / Day. Auto-pops from clip go-live dates |
| **Posting Batch** | Drill-down site × persona posting wizard with focused per-clip windows |
| **Reports** | Full Clip / Weekly / Posting Status / Category Usage / Calendar Rollup / Clip Audit. Each report has its own MD / PDF / CSV export menu with auto-reveal. |
| **C4S Historical** | Snapshot of the most recent Clips4Sale on-demand storefront export per store (CoC + PoA). Sortable grid + per-row detail. Each import wholly replaces the chosen store's rows. |
| **Import** | 5-step smart-import wizard for xlsx / csv / tsv / pasted text |

## The workflow pipeline

```
new → editing → to_post → posting → production
```

Status is **auto-derived** from data + posting state — there's no manual status picker. The badge on each clip reflects the current state, and a hint under it explains what's needed to advance.

| Status | Trigger |
|---|---|
| **new** | Clip exists, no editing fields touched, no postings |
| **editing** | At least one of (FCP project folder / production folder / length) is filled, but not all three |
| **to_post** | All three editing fields filled, no scope sites posted yet |
| **posting** | At least one persona-scope site is marked posted (but not all) |
| **production** | Every persona-scope site is marked posted |

`archived` lives on a separate Bool column and isn't part of the pipeline.

## Personas

Configurable in **Settings → Personas**. Defaults:

| Code | Display | Default colour |
|---|---|---|
| **CoC** | Curse Of Curves | `#FFB6C1` (light pink) |
| **PoA** | Princess Of Addiction | `#B22222` (sunset dark red) |
| **Shr** | Sheer Addiction | `#3CB6C1` (teal) |
| **N/A** | Not Applicable | `#888888` (grey) |

The persona colour is used everywhere clips appear — list pills, calendar dots, dashboard cards, posting batch sidebar, and the editor's sticky header. Pick a different colour with the `ColorPicker` and every record belonging to that persona repaints across the app.

## Sites

Configurable in **Settings → Sites**. Each site has a code, display name, and **persona scope** (which personas use it). Defaults:

| Code | Site | Persona scope |
|---|---|---|
| c4s | Clips4Sale | CoC, PoA |
| mv | ManyVids | CoC |
| nf | NiteFlirt | CoC, PoA |
| iwc | IWantClips | PoA |
| lf | LoyalFans | PoA |

Posting batches expand each (site, persona scope) into separate (site, persona) targets — Clips4Sale [CoC] and Clips4Sale [PoA] run as independent batches with their own login flows.

## Categories

Configurable in **Settings → Categories**. Used as multi-select chips on each clip. New categories also auto-create on import (any unrecognised tag in the source data becomes a category).

**Categories are uppercase.** As of the v8 migration, every existing category name was uppercased and case-collisions were merged onto the lowest-id row (with `clip_categories` links re-pointed). Going forward, every code path that creates a category — `DatabaseService.ensureCategory(named:)`, the inline picker, the settings tab, import — uppercases on input so they all land on the same canonical row.

You can also create a new category **directly from any clip** without leaving the editor: under the chip picker, type a new name in the "Create new category — type and press Return" field. Case-insensitive duplicates are detected and reused. New categories appear in **Settings → Categories** automatically.

### Cleaning up unused categories

Imports often grow the category table faster than the clip table — every unique tag on every imported row becomes a Category, but most of them only ever appear once. The **Archive unused (N)…** button at the top right of **Settings → Categories** reports how many active categories aren't currently attached to *any* clip; one click + confirmation flips them all to `archived = 1` in a single transaction.

Archived categories are hidden from the inline picker, the chip-based filters, and the import auto-suggest. They stay in the Categories table (flip the **Archived** toggle on a row to bring it back), and `ensureCategory` un-archives on re-use — so if a future import or the historical-categories backfill ever re-attaches an archived category to a clip, it auto-revives back into the picker without manual intervention.

## Clip ID format

Every clip has a primary key `YYYY-MM-DD-#####`, e.g. `2026-05-03-00042`. The date prefix is the clip's **Content Date** if known, else today. The 5-digit suffix is per-day (atomic UPSERT against `id_sequences`).

The legacy `#` field from any imported spreadsheet is preserved on each clip as `external_clip_id`.

## Calendar release rules

Each persona has a per-weekday checkbox in **Settings → Calendar Rules**. Defaults:

| Persona | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
|---|---|---|---|---|---|---|---|
| CoC | ✓ | | | ✓ | | | |
| PoA | | | ✓ | | ✓ | | |
| Shr | | | | | | | |
| N/A | | | | | | | |

The **Generate Year** button materialises blank `(date, persona)` events for every weekday matching enabled rules.

The calendar **also** auto-populates from clip `goLiveDate`s — no manual link needed. Clips appear on their go-live date with title and persona color.

## Description refinement (Ollama)

If `ollama` is installed (`brew install ollama`), the app auto-starts `ollama serve` on launch. **Settings → Ollama** lets you pick a model (auto-detected from `/api/tags`), edit the prompt template, and run a "Test refine" inline.

The default prompt is a **strict word-for-word proofreader** — it will only fix spelling, punctuation, and grammar; it will not rephrase, swap synonyms, reorder sentences, or improve style. Temperature is 0 (greedy decoding) so the output is reproducible. Five worked examples in the prompt anchor the LLM to the desired behaviour.

After streaming completes, the app post-processes the result to:
- **Strip wrapping quotes** (`"…"` / `'…'`, smart and straight)
- **Normalise paragraph format**: trim each line, collapse multi-space runs, **join single in-paragraph newlines with spaces** (sentence-per-line input becomes flowing prose), and collapse 3+ newlines to a single paragraph break

Per-clip workflow:

1. Paste raw transcription into **Description (raw transcription)** on the clip's edit form.
2. Click **Refine via Ollama** in the **Description (refined)** section.
3. Tokens stream into the refined field. Raw is never overwritten.
4. The first time refined is set, `[Refined YYYY-MM-DD]` is appended to the clip's notes.

If the configured model isn't installed, **Settings → Ollama** shows a one-click "Use \<first installed\>" banner so you don't have to type the model name.

**Reset to default** (in the prompt editor header) drops back to the strict proofread prompt anytime.

## Clip audit

**Reports → Clip Audit** runs a seven-point checklist against every non-archived clip:

1. Clip ID exists
2. Persona is set (and resolves to a known persona record)
3. Title exists and isn't a placeholder ("Untitled" / "TBD" / under 3 chars)
4. Refined description is non-empty
5. At least one category selected
6. Content date is set
7. Go-Live date is set

Failing clips show as orange-bordered cards with the open issues listed. Click any card to jump to its editor; clean clips drop off the list. Re-run from the header any time to refresh.

The clip editor also shows a **live audit banner** at the top of the form. Orange when issues are open, green when clean. Recomputes as you edit — fix the missing field and the banner clears immediately.

## Verify files (per-clip)

The clip editor's "Editing (post-production)" section has a **Verify files** button that opens a sheet checking nine things:

1. **FCP project folder** exists *(warn-only — drive may not be mounted)*
2. **Production folder** exists *(missing here is concerning — likely a typo)*
3. **Main MP4** (`<Title>.mp4`) — under threshold, OR over threshold with a reduced version present
4. **Reduced MP4** (`<Title>_reduced.mp4`) — required only when main is over threshold
5. **Thumbnail frames** (`<Title>_frame_NN.png`) — N captured per the **Frames to capture per clip** setting
6. **FCP bundle** (`<Title>.fcpbundle`)
7. **Description** (refined preferred, raw acceptable)
8. **Video transcription** (whisper transcript stored on the clip)
9. **File hashes** (MD5 / SHA-1 / SHA-256 for main + reduced)

When everything's clean, the sheet leads with a tall green **All checks passed** banner.

Each row that can be fixed surfaces an inline action pill — these run in place without leaving the audit:

| Row | Action when broken |
|---|---|
| FCP project folder | **Choose…** — NSOpenPanel to pick the folder |
| Main MP4 | **Push from FCP** — moves the rendered MP4 from the FCP folder into Production with the canonical name (creates Production folder if missing) |
| Main MP4 (over threshold, no reduced) | **Reduce now** — `<Title>_reduced.mp4` re-encode |
| Reduced MP4 | **Reduce now** if missing |
| Thumbnail frames | **Capture / Re-capture** N frames + visual frame picker (`LazyVGrid` of preview tiles) — click a tile, click **Use as thumbnail** to promote it to `<Title>.png` |
| Video transcription | **Generate / Re-generate** via `transcribe.py` |
| File hashes | **Compute / Re-compute** MD5 / SHA-1 / SHA-256 |

Self-correcting **rename suggestions** appear when an expected file is missing but a similarly-named file is in the same folder (Levenshtein-matched). Single-click rename, plus **Fix all** in the footer.

## Bulk file-verification workflow

Run the audit across an entire queue at once:

- **Run File Verification** toolbar button on **Editing Queue** and **Posting Queue**.
- The sheet walks every visible (filtered) clip one at a time. Header has:
  - Segmented filter — **All clips** vs **Only with issues** (preflight audits every clip on open and remembers which ones had issues).
  - Progress bar.
  - Per-clip status counts.
- Footer: **Stop workflow / Previous / Skip / Next** (or **Finish** on the last one).
- All inline pills work the same as the per-clip sheet — fix things in place, then advance.
- Final **Workflow complete** screen shows initially clean / fixed during run / skipped / still has issues, with click-through to clips still needing work.

## Video transcription

The clip editor's **Video Transcription (auto-generated)** section runs MLX Whisper via the sibling `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py`:

- Default model: `turbo`. Uses `-q` for quiet output, captures stdout.
- Whisper's per-segment line breaks are collapsed into a single continuous paragraph before storage.
- The transcript field is editable — your edits persist with autosave like any other field.
- Disabled with a hint when `transcribe.py` isn't installed.

Also available as an inline action on the **Video transcription** audit row (Generate / Re-generate).

## Thumbnails

Production thumbnails come from frame captures of the main MP4:

- **Capture N frames** (default 15, configurable in Settings → File Locations). Frame 1 is sampled from the 1–9 s window so it usually catches the title card; frames 2–N are evenly distributed across the rest of the clip in random samples. All N write to `<Title>_frame_NN.png` in Production.
- **Pick the canonical thumbnail** — the audit's Thumbnail-frames row shows a `LazyVGrid` of every captured frame as a clickable preview tile. Click a tile to select it; click **Use as thumbnail** to promote it. The chosen frame:
  1. Is copied to `<Title>.png` in Production (overwriting any prior copy).
  2. Has its filename stored on `clip.thumbnailFilename` so the picker remembers across sessions.
  3. Causes any stale `<Title>.png` mirror in the FCP folder to be cleaned up — Production stays the single source of truth.
- The chosen filename also surfaces on the editor's **Thumbnail** row in the Editing section, with a Reveal button.

## File integrity (hashes)

The clip editor's **Integrity** section shows MD5 / SHA-1 / SHA-256 fingerprints for both the main and reduced MP4, with file size and last-computed timestamp. Click any digest's copy icon to put it on the clipboard.

Hashes are streamed in 4 MB chunks via CryptoKit — multi-GB clips don't blow memory and the UI stays responsive. The **Recompute hashes** button (and the audit's **Compute / Re-compute** action on the **File hashes** row) hashes both files in one background pass and persists the digests + sizes + ISO timestamp.

## Deleting clips

Three ways:

- **Toolbar trash button** in the Clips list (⌘⌫). Disabled when no clip is selected.
- **Right-click → Delete** on any row in the table.
- **Delete clip…** button in the clip editor footer.

All three open a confirmation alert quoting the clip's title. Postings, category links, and history rows cascade-delete with the clip. Run a backup first if you're not sure (or restore from the last auto-backup if you change your mind).

## Smart import

Open the **Import** sidebar item (or use ⇧⌘I).

1. **Source** — file picker (`.xlsx`, `.csv`, `.tsv`) or paste delimited text.
2. **Sheets** (xlsx only) — auto-routes each sheet by name. The recommended sheet (the one that goes to "Clips") shows up in a hero card with a single **Continue → Mapping** button. Other sheets list below with per-sheet routing pickers.
3. **Mapping** — every source column gets a target field dropdown, pre-populated by fuzzy-match. Set columns you don't need to "— ignore —". Sample value from the data shown next to each header.
4. **Preview** — first 30 rows of mapped data.
5. **Commit** — duplicate detection on `external_clip_id` then `(title, content_date)`. Inserted / skipped / failed counts reported with a per-error log.

### "Treat as historical" toggle

On the Preview step. When checked, every imported clip is bulk-marked posted to every site in its persona scope, with `posted_date = goLiveDate ?? contentDate ?? today`, and auto-advances to **Production** status.

Use this for one-time imports of clips you've already published. For new clips that still need work, leave it off — they'll land in `new` and progress through the pipeline as you fill in editing fields and post them.

### Per-clip "Mark as historical"

Right-click any clip in the Clips list → **"Mark as historical (all scope sites posted)"**. Same logic, applied to one clip at a time. Useful for cleaning up a clip that should have been historical but wasn't.

## Excluding clips from posting

Mark any clip as **do not post** from the editor's **Posting status** section: toggle the switch on, pick a reason from the dropdown (default options: **Custom**, **Not Posted - Sent Individually**, **Other - Please specify**), optionally fill in free-text notes.

Excluded clips:
- **Auto-promote to `production`** — there's nothing to post, so they're "done" pipeline-wise. No need to manually shuffle their status.
- **Are filtered out** of every per-site posting batch (`PostingService.clipsNotPosted`) and the **Posting Queue** sidebar section.
- Still appear in the Editing Queue, the Clips list, and the Calendar — exclusion is a posting-only concern.

Same auto-promotion happens for clips whose persona has no scoped sites at all (e.g. `Shr` / `N/A` when no site is configured for them) once editing is complete. There's literally nothing to post, so they graduate straight to `production`.

The dropdown of available reasons is configured in **Settings → Posting** (label CRUD, archive toggle, sort order). Reasons are stored as strings on the clip, so renaming a reason in Settings doesn't retroactively change clips already tagged with the old label.

## Posting Batch

Drill-down wizard. Three stages with breadcrumb navigation at the top.

1. **Sites** — grid of (site, persona) cards. Each card shows pending count or a green "All posted" check.
2. **Queue** — pending clips for the chosen target. **Start posting** kicks off the first; **Open** on any row jumps straight to it.
3. **Posting** — focused per-clip window with persona-coloured banner. Pinned at the top: title (with copy-to-clipboard button), clip ID (click-to-copy), full Production folder path (with **Reveal** + **Open clip in editor**), thumbnail filename, and MD5 / SHA-1 / SHA-256 file hashes (each click-to-copy). Below: read-only refined description (with copy), editable categories, schedule strip with editable Price field, and a Posting notes textarea.

   **Posting notes are saved twice** — to the per-(clip, site) `clip_postings.notes` column AND mirrored to the clip's main Notes field as `[Posted <siteCode> YYYY-MM-DD] <text>`, so the editor's Notes section surfaces every posting context together.

   Action bar: **Copy all (markdown)**, **Skip for now** (advance without marking — clip stays in queue for later), **Mark posted** (⌘S), **Posted & next** (⌘↩). Mark posted is disabled until the price is set — zero is allowed for free clips.

The breadcrumb header has a **Show queue list** button (numbered-list icon) — opens a sheet with every pending clip in order. Each row has click-to-copy ID / title / production filename. Footer has bulk-copy buttons (Titles / Filenames / Markdown table) for sites that allow uploading multiple clips at once.

The position indicator (`Clip N of M`) is computed as "clips already posted + offset of current clip in remaining list + 1" so both Mark posted and Skip advance the counter by exactly one.

When a queue empties, falls back to the queue stage with an "all done" page and a **Next batch** button to jump to the next (site, persona) target.

Excluded clips (see [Excluding clips from posting](#excluding-clips-from-posting) above) never appear in any of these queues.

## File locations & path defaults

**Settings → File Locations** configures the path templates used by the editor's path-helper buttons (`wand.and.rays`) and the one-time backfill:

| Field | Default |
|---|---|
| Production base | `~/Dropbox/Sallie Content/Clips` |
| Production pattern | `{date} {title}` |
| FCP base | `/Volumes/PRO-G40/` |
| FCP pattern | `Content Working/{date} Session/{title}` |
| Large-file threshold | 950 MB |
| Frames to capture per clip | 15 |

Placeholders `{date}` (clip's content date, falling back to go-live date) and `{title}` (sanitised — `/` `\` `:` → `-`) are substituted into the pattern.

The first time the app launches after this feature shipped, **a one-time backfill** populates the FCP and Production columns for every clip in `production` status whose path is currently empty. **Run backfill now** in Settings forces a re-run any time.

## Reports

The Reports section has six panels, each with its own export menu (Markdown / PDF / CSV) that auto-reveals the saved file in Finder. A persistent **Reveal** button appears next to the menu after the first save.

| Report | Shows |
|---|---|
| **Full Clip Report** | Sortable table of every clip — ID / Persona / Title / Status / Length / Go-Live |
| **Weekly Report** | Three-week go-live window (Last / This / Next) plus a "Not in production" list. Anchor date shifts with chevrons. |
| **Posting Status** | One row per (clip, scoped site) with posted/pending state and posted date. "Hide already-posted" filter. |
| **Category Usage** | Per-category clip counts. |
| **Calendar Rollup** | Per-(month, persona) event counts for a selected year. |
| **Clip Audit** | The 7-point clip checklist as bulk cards (separate from the per-clip Verify files audit). Clickable into the editor. |
| **Information Needed** | Every clip in `new` / `editing` status that's missing a description, categories, or go-live date. Each card shows ID — Title [Persona], Description (or `Blank`), Categories (or `None Defined`). **Copy for creator** button packages the list into a clipboard payload prefixed with `Please confirm/provide the following:` for sending to the creator. |

The toolbar **Export…** menu at the top of the Reports section is distinct — it dumps the *full clip dataset* in any format. The per-report menus only export that report's view.

## C4S Historical

A separate sidebar section that holds the **most recent on-demand Clips4Sale storefront export** per store. The C4S admin page can produce a `.xlsx` or "`.csv`" export of every clip in your store with status / sales / 6-month income; this section stores the snapshot in `c4s_historical` so you can analyse it without leaving the app.

**Schema is one row per C4S clip per store.** Columns mirror the C4S export (status, clip ID, tracking tag, title, description, categories, keywords, three filenames, performers, price, sales count, last-6-months income) plus a `store` key (`CoC` | `PoA`) and an `imported_at` timestamp.

**Import (Cmd-I):** opens a sheet with

- **Source file** — pick the `.xlsx` or `.csv`. The C4S "csv" is actually pipe-delimited with quoted fields and embedded newlines inside descriptions; the importer parses both formats. The picker also accepts files with no extension and content-sniffs them via the ZIP magic.
- **Store** — segmented control (CoC / PoA). Auto-pre-selects from filename prefixes like `COC_…` or `POA_…`. The orange banner reads `All N existing CoC rows will be replaced.`
- **Preview** — shows the parsed row count and the first three rows so you can sanity-check before committing.
- **Replace `<Store>` rows** — wraps the delete + insert in a single transaction. The other store's rows are untouched.

**Browse:** the body is a `HSplitView` — sortable table on the left (Store / Title / Status / C4S ID / Price / Sales / Income / Categories), detail panel on the right showing the persona-coloured store pill, full description, category and keyword chips, file row, and tracking tag. Top toolbar: store filter (All / CoC / PoA with counts), free-text search across title / description / keywords / categories / clip-id / performers, **Import…** button.

**Use case:** the Dashboard and Reports show your clip pipeline; this section shows the *posted reality* on Clips4Sale. The two sides won't always match (clips you've delisted on C4S, clips C4S has under review, etc.), so this snapshot is the source of truth for "what does my storefront look like right now". You re-run the import as often as you want; older snapshots aren't kept.

### Backfill categories on historical clips

The toolbar's **Backfill categories…** button (enabled once you have a snapshot) opens a planner that fills in categories on production clips that have none — using the categories *already assigned to the same clip on the storefront* as the source of truth. Useful right after a historical import: those clips come in with title and persona but no category metadata.

The matcher uses **title only** — your `external_clip_id` is a legacy sequence number, not the real C4S clip ID, so it can't join. Titles are normalized (lowercased, apostrophes / commas stripped, whitespace collapsed) before comparing.

The sheet groups proposals into four buckets, each with per-row checkboxes:

| Bucket | Score | Default | Notes |
|---|---|---|---|
| **Exact** | 1.00 | ✓ | Same title after normalization. Safe. |
| **Strong fuzzy** | ≥ 0.92 | ✓ | Likely the same clip — typo / punctuation drift. Eyeball before running. |
| **Maybe** | 0.75–0.92 | ✗ | Could be the same clip with a reworded title — tick the ones you accept. |
| **Cannot match** | < 0.75 | (n/a) | Copyable list. Mostly customs / delisted clips. |

Each match row shows persona pill, source title → C4S title, and a chip preview of every category that would be applied. An orange `(store: X)` flag appears if the best candidate sits in the *other* store (rare; review carefully). The category list is built as `c4s.categories + c4s.keywords` (in that order), uppercased, deduped by first occurrence, position preserved.

**Run** wraps every category-ensure + `clip_categories` insert in one transaction. Clips that already have categories at commit time are silently skipped — backfill never overwrites.

## Exports

| From | Output |
|---|---|
| **Reports → Export menu** | CSV / Markdown / XLSX / DOCX / PDF / **HTML** (mobile-friendly cards) |
| **Clips → Export Clip… toolbar** | Per-clip plain text (iMessage-friendly) / Markdown / PDF |

The **HTML export** pre-renders every clip as a static card in the document body — no JSON parsing or `<script>` payloads. Self-contained file works in any browser, on any device. Filter / search bar at the top is a JS progressive enhancement; if JS is blocked (e.g. iOS Files preview), all cards remain visible and the user can use Find-on-Page.

All file pickers default to `~/Downloads/MasterClipper/`.

## Backup, test, and restore

**Settings → Backup**:

- **Auto-backup at launch** — runs every time you open the app (throttled to 60 s). The zip contains `masterclipper.sqlite` + `settings.json`. Filenames stored on each clip are *not* vaulted (no media files).
- **Retention** — sliding window in days; `0` = keep every backup forever.
- **Run backup now** — fire one on demand.
- **Each backup row** has:
  - **Test** — non-destructive: extracts to a temp dir, opens the SQLite, returns a sheet showing migrations applied + clip / posting / persona / site / category / event counts + sample of file paths.
  - **Restore** — destructive: pre-flight verifies the archive, runs a safety backup of the current state, replaces support-dir contents with the archive, reopens the GRDB pool, reloads `AppState`. The safety backup is reported in the toast so you can roll forward again.
  - **Reveal** — opens the backup in Finder.

## Reset clip data

**Settings → Backup → "Backup & wipe all clip data"**. Confirmation alert. Runs a backup first, then deletes every row from `clips`, `clip_postings`, `clip_categories`, `clip_history`, `calendar_events`, `prices`, and `id_sequences`. Personas, sites, categories, and calendar rules are kept.

For a full nuclear reset (also resetting personas / sites / rules to seeds): quit the app, delete `~/Library/Application Support/MasterClipper/`, relaunch.

## Auto-save

Every clip edit auto-saves when you navigate away — different clip, different sidebar section, window close. The footer shows three states:

- **Pencil + orange** "Unsaved — auto-saves on navigation" while you're typing
- **Checkmark + green** "Saved \<time\>" when in sync with the database
- **Triangle + red** error message if the actual write failed

The explicit Save (⌘S) and Discard buttons disable when there are no unsaved changes.

## Search

The Clips list search bar runs an AND-token LIKE across `title`, `description_raw`, `description_refined`, `keywords`, `performers`, `tracking_tag`, `external_clip_id`, `id`, and (when enabled in Settings → Import / Export) `notes`.

## Title rename tracking

Changing a clip's title appends to `notes`:

```
[Renamed YYYY-MM-DD: "old title" → "new title"]
```

This makes title history searchable and survives subsequent edits.

## Change history

Every per-field change to a clip lands in `clip_history` — title rename, status auto-transition, posting toggle, category-set update. Visible at the bottom of every clip's edit form in a "Change history" disclosure (collapsed by default, with a row count).

## Light / Dark / System

**Settings → General → Mode** segmented picker. "Match system" / "Light" / "Dark". Applied via `.preferredColorScheme(...)` on the root window.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New Clip |
| ⌘S | Save current clip (also auto-saves on navigation) |
| ⌘↩ | Posted & next (in Posting window) |
| ⇧⌘I | Open Import wizard |
| ⌥⌘E | Export CSV |
| ⇧⌘P | Export PDF report |
| ⇧⌘H | Full Data Export (HTML) |
| Esc | Back to queue (from Posting window) |
