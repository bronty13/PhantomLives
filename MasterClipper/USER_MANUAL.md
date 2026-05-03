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
| **Editing Queue** | Master/detail of clips not yet fully posted, by status: new / editing / to_post / posting |
| **Clips** | Master/detail of every clip. Sortable Table, filters, search |
| **Calendar** | Year / Quarter / Month / Week / Day. Auto-pops from clip go-live dates |
| **Posting Batch** | Drill-down site × persona posting wizard with focused per-clip windows |
| **Reports** | Full Clip / Posting Status / Category Usage / Calendar Rollup, exportable to 6 formats |
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

Per-clip workflow:

1. Paste raw transcription into **Description (raw transcription)** on the clip's edit form.
2. Click **Refine via Ollama** in the **Description (refined)** section.
3. Tokens stream into the refined field. Raw is never overwritten.
4. The first time refined is set, `[Refined YYYY-MM-DD]` is appended to the clip's notes.

If the configured model isn't installed, **Settings → Ollama** shows a one-click "Use \<first installed\>" banner so you don't have to type the model name.

**Reset to default** (in the prompt editor header) drops back to the strict proofread prompt anytime.

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

## Posting Batch

Drill-down wizard. Three stages with breadcrumb navigation at the top.

1. **Sites** — grid of (site, persona) cards. Each card shows pending count or a green "All posted" check.
2. **Queue** — pending clips for the chosen target. **Start posting** kicks off the first; **Open** on any row jumps straight to it.
3. **Posting** — focused view of one clip with **per-field copy buttons** (title / categories / keywords / performers / length / price / dates / filenames as one-line copy rows; description as multi-line scrollable copy panel). Posting notes textarea below saves into the clip_postings row. **Mark posted** + **Posted & next** (⌘↩) advance through the queue.

When a queue empties, falls back to the queue stage with an "all done" page and a **Next batch** button to jump to the next (site, persona) target.

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
