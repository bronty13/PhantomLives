# Changelog

## 2026-05-05 — Status auto-recompute fix, click-to-copy IDs, file-audit hardening

- **Status-recompute bug fix.** `PostingService.markPosted` was writing posting rows directly via `row.save(db)`, bypassing the clip-status recompute that lives inside `DatabaseService.upsertPosting`. Result: clips with postings created via the batch flow stayed in `to_post` even after the first scoped site was marked posted. `markPosted` now routes through `upsertPosting`, which triggers status recompute + history-row writes. Backfilled via `v9_recompute_clip_status` migration.
- **Excluded clips auto-promote to production.** `computeStatus` now returns `production` when `postingExcluded == true` — there's nothing to post, so the clip is "done" pipeline-wise and shouldn't sit in `to_post`. Same auto-promotion when the clip's persona has no scoped sites (e.g. `Shr` / `N/A` without site assignments) and editing is complete. Backfilled via `v10_status_for_excluded_and_no_scope`.
- **Click-to-copy clip IDs.** New reusable `ClipIDLabel` view replaces every visible `Text(clip.id)` in the editor sticky header, Clips list, Editing Queue, Posting Queue, Posting Batch queue rows, posting window header, and bulk audit clip banner. Tap any ID to copy; brief "Copied" pill flashes. Two callsites kept as plain Text because they live inside parent `Button` rows (audit-report card, workflow summary list).
- **Posting workflow refinements**:
  - **Skip for now** button — advances without marking posted; the clip stays in the queue. `advanceAfter` now correctly walks past the current clip (was picking `pendingClips.first`, which was the same clip when nothing had been removed).
  - Counter math fix: position is now `(batchStartCount − pending) + currentClipIndexInPending + 1`, so both Mark posted and Skip advance the counter by exactly one.
  - **Show queue list** button + `PostingQueueListSheet` — modal sheet listing every pending clip in order with click-to-copy ID / title / production filename, plus bulk-copy buttons (Titles / Filenames / Markdown table) for sites that allow uploading multiple clips at once.
  - **Editable price** field in the schedule strip — saves on submit, on Mark posted, on disappear. Mark posted is gated on the price being set (zero allowed for free clips); inline orange hint appears when empty.
  - **Title copy button** next to the title in both the posting window header and the clip editor's sticky header.
  - **Posting notes mirror to clip notes** — when posting notes are saved, they're appended to `clip.notes` as `[Posted <siteCode> YYYY-MM-DD] <text>` so the editor's main Notes field surfaces every posting context together.
  - Per-clip identity (`.id(clip.id)`) on `PostingClipWindow` so `@State` (priceDraft, notes, picked categories) doesn't carry across clips on Posted-and-next.
  - Header font bumps — counter `.caption` → `.callout`, current-clip title in breadcrumb `.headline` → `.title3.weight(.semibold)`.
- **File-audit hardening**:
  - **Sandbox dropped** — `com.apple.security.app-sandbox` is gone, leaving just `com.apple.security.network.client` (Ollama). The audit calls `FileManager.fileExists(atPath:)` with string paths, which the sandbox refused for user-selected URLs (the bookmark-grant only carries via the URL, not the string), so audit rows stayed red even after the user picked the right folder.
  - **`isDirectory` is now multi-pass** — exact literal → URL standardisation → Unicode NFC normalisation → whitespace-trimmed fallback. Catches volume-name NFC/NFD differences (common on external drives) and round-trip whitespace mismatches.
  - **`expand()` preserves trailing/leading spaces** in filenames — macOS allows them and we've seen real folder names like `...MILF ` (trailing space) that would otherwise mismatch after trimming. Only `\n`, `\r`, `\t`, NUL are stripped now.
  - **Pickers save `URL.standardizedFileURL.path`** — so subsequent existence checks match the volume's canonical form.
- **Description-refine action on the Description (raw only) audit row.** New purple inline pill with **Refine** button — streams Ollama with the configured model + prompt, runs `cleanRefineOutput` for quote-stripping + paragraph-format normalisation, persists to `clip.descriptionRefined`, appends `[Refined YYYY-MM-DD]` to notes, re-audits. Same wiring in both the per-clip sheet and the workflow.

## 2026-05-04 — Posting workflow refinements, exclusion flag, uppercase categories

- **Skip in posting workflow** — new **Skip for now** button in `PostingClipWindow` advances to the next clip without marking the current one posted. The clip stays in the queue so the user can come back to it later.
- **Price required to post** — Mark posted / Posted & next are disabled until the price is set (zero is allowed for free clips). Inline orange hint appears in the action bar when the price is empty so the gate is obvious.
- **Editable price in the posting window** — Price moved into the schedule strip as a TextField with `$` prefix; saves on submit, on Mark posted / Posted & next, and on view dismissal. Persists via `appState.updateClip` so the rest of the app sees the new price immediately.
- **Posting Queue: Price column** — added between Length and ID, sortable (nils last via a dedicated `priceCentsKeyPosting` key extension).
- **Per-clip "do not post" flag** — new clip columns (`posting_excluded`, `exclusion_reason`, `exclusion_notes`) plus a configurable `exclusion_reasons` table seeded with **Custom**, **Not Posted - Sent Individually**, **Other - Please specify**. New **Posting status** section in the editor: toggle, reason dropdown (filtered to non-archived reasons), free-text notes. Excluded clips are filtered out of `PostingService.clipsNotPosted` (per-site batches) and the Posting Queue.
- **Posting settings tab** — new **Settings → Posting** tab for managing the exclusion-reason dropdown (label CRUD, archive toggle, sort order).
- **Categories are uppercase** — v8 migration uppercases every existing category name and dedupes case-collisions onto the lowest-id row, re-pointing `clip_categories` links and deleting the duplicates. Going forward, `DatabaseService.ensureCategory(named:)` and the categories settings tab uppercase on input — every code path that creates a category lands on the same canonical row.
- **DB migration**:
  - `v8_categories_uppercase_and_exclusions` — three things in one migration: uppercase + dedupe categories, add the exclusion columns to `clips`, create + seed `exclusion_reasons`.
- **PostingClipWindow header redesign** — persona-coloured banner with big persona pill (gradient, drop shadow, code + display name), title, clip ID, full Production folder path with **Reveal** + **Open clip in editor** buttons, thumbnail filename row, and MD5 / SHA-1 / SHA-256 rows (each with copy-to-clipboard).
- **PostingClipWindow body slim-down** — Description (refined) is read-only; Categorization is editable via `CategoryChipPicker` and persists every change immediately; schedule strip shows Length / Price (editable) / Content date / Go-Live date. Removed Keywords, Performers, Clip filename, Preview filename, and the raw-description block.

## 2026-05-04 — File-verification flow, queues, transcripts, hashes

- **Verify files** — per-clip file audit (button in the editor's "Editing (post-production)" section) opens a sheet checking nine things: FCP project folder, Production folder, Main MP4 (`<Title>.mp4`), Reduced MP4 (`<Title>_reduced.mp4`, only required when main is over threshold), Thumbnail frames (`<Title>_frame_NN.png`), FCP bundle (`<Title>.fcpbundle`), Description, Video transcription, File hashes. Each row reports OK / warn / missing / N/A with file size, detail line, and a Reveal button.
- **All-checks-passed banner** — when nothing's broken, the sheet leads with a tall green "All checks passed" card so the user can see at a glance that the clip is done.
- **Self-correcting rename suggestions** — when an expected file is missing, the audit scans the parent folder for files of the right type, picks the closest match by `FuzzyMatch.similarity` (Levenshtein), and offers a single-click rename. **Fix all** in the footer applies every rename in one pass.
- **Inline action pills on audit rows.** Each row that can be fixed in place exposes the relevant action: **Choose…** for the FCP folder when the path isn't set or reachable, **Reduce now** on a missing reduced MP4, **Capture / Re-capture** on the Thumbnail frames row (above the picker), **Generate / Re-generate** on the Video transcription row, **Compute / Re-compute** on the File hashes row.
- **Bulk file-verification workflow** — toolbar button on both Editing Queue and Posting Queue walks every visible clip through the audit sheet one at a time. Header has a segmented `All clips · Only with issues` filter (preflight audits every clip on open), a progress bar, Previous / Skip / Next / Finish buttons, and a summary at the end with click-through to clips still needing work. Pickers and audit caches are keyed per clip ID so selections survive Previous / Next / re-audit.
- **`ClipReduceService`** — `AVAssetExportSession` (HEVC at source resolution → H.264 1080p → 720p → 540p) iteratively re-encodes the main MP4 down to a `<Title>_reduced.mp4` companion until under the configured threshold. No ffmpeg dependency.
- **`FrameCaptureService`** — `AVAssetImageGenerator` pulls N stills from the production MP4: frame 1 from the 1–9 s window (catches the title card), frames 2–N evenly distributed across the rest of the clip in random samples. Output: `<Title>_frame_01.png` … `<Title>_frame_NN.png`.
- **Visual thumbnail picker** — captured frames render as a wrapping `LazyVGrid` of preview tiles. Click any tile to select it; the chosen frame is promoted to `<Title>.png` in Production (overwriting any prior copy) and any `<Title>.png` mirror in the FCP folder is cleaned up. The picked frame's filename is stored on `clip.thumbnailFilename` so it survives across sessions.
- **`TranscriptionService`** — shells out to the sibling `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` (MLX Whisper) with `-i ... -o - -f txt -m turbo -q`, captures stdout, normalises CR/LF/tabs into a single continuous paragraph, and stores the result on `clip.transcript`. Disabled with a hint when `transcribe.py` isn't installed.
- **`HashService`** — streams the main and reduced MP4 through MD5 / SHA-1 / SHA-256 in a single 4 MB-chunked pass via CryptoKit. Persists hex digests + sizes + ISO timestamp onto the clip; **Recompute hashes** button in the editor's new **Integrity** section (with click-to-copy on every digest) and an audit-row equivalent.
- **Posting Queue** — new sidebar section parallel to the Editing Queue, defaulting to `to_post + posting` status. Posting-progress column shows per-site pills (`✓ c4s · ○ mv · ✓ nf`) plus an `X/N` count. Sidebar gets count badges for both Editing Queue and Posting Queue.
- **Path defaults** — Settings → File Locations now lets you configure Production base + pattern (default `~/Dropbox/Sallie Content/Clips`, `{date} {title}`) and FCP base + pattern (default `/Volumes/PRO-G40/`, `Content Working/{date} Session/{title}`). `wand.and.rays` button on each folder row in the editor sets the path to the configured default. One-time backfill (`pathBackfillV1Done`) runs at first launch, populating the columns for every Production-status clip whose paths are empty; "Run backfill now" button forces a re-run.
- **Per-report exports + Reveal.** Full Clip / Weekly / Posting Status / Category Usage / Clip Audit each get their own `ReportExportMenu` (Markdown / PDF / CSV) that auto-reveals in Finder after save and surfaces a persistent **Reveal** button next to the menu. Distinct from the toolbar Export which still dumps the full clip dataset.
- **Weekly report** — three-week go-live window (Last / This / Next), plus a "Not in production" list of active clips that haven't reached the Production stage. Anchor date shifts with chevrons. Exportable to MD / PDF / CSV.
- **DB migrations**:
  - `v5_clip_categories_order` — `clip_categories.position` for ordered categories per clip.
  - `v6_clip_transcript` — `clips.transcript` text column.
  - `v7_clip_hashes` — `clips.{mp4,reduced}_{md5,sha1,sha256,size_bytes}` + `hashes_computed_at`.
- **Settings additions**: `largeFileThresholdMB` (default 950), `numFramesToCapture` (default 15), `defaultProductionBase`, `defaultProductionPattern`, `defaultFCPBase`, `defaultFCPPattern`, `pathBackfillV1Done`.

## 2026-05-04 — Audit, delete, simpler UI, date pickers

- **Clip audit** — new `ClipAuditService` with seven checks: clip ID exists, persona is set + resolves, title exists and isn't a placeholder, refined description set, ≥ 1 category, content date set, go-live date set.
  - **Per-clip banner** at the top of `ClipEditView`. Orange triangle + each open issue listed when failing; green checkmark "all checks passed" when clean. Recomputes live from the in-edit `draft` + selected categories — no save / refresh cycle needed.
  - **Bulk audit report** in `Reports → Clip Audit`. Lists every failing clip as a clickable card; click navigates to the clip editor with focus pre-applied. "Hide clean" toggle, running tally, Re-run button.
- **Delete records** — three discoverable paths:
  - Toolbar **trash button** in the Clips list (⌘⌫ keyboard shortcut, disabled when nothing's selected).
  - Right-click context menu (was already there).
  - **Delete clip…** button in the clip editor footer.
  - All three open the same confirmation alert quoting the clip's title before deleting. `ON DELETE CASCADE` cleans up postings, category links, and history rows.
- **Date pickers** for `contentDate` and `goLiveDate`. macOS native compact `DatePicker` when set; "Set date" button + "Not set" label when nil; `×` icon to clear back to nil. Also wired into the New Clip sheet (toggle + picker, default off = "Use today"). Storage stays as ISO `YYYY-MM-DD` strings.
- **Inline category creation** in `CategoryChipPicker`. Type a new category name and hit Return — the row is inserted via `DatabaseService.ensureCategory(named:)` and immediately selected on the clip. Existing-name match is case-insensitive (won't create duplicates).
- **Editing Queue: persona filter + sortable columns**. Filter bar gets a Persona dropdown next to the status chips. Every column is now a sortable `KeyPathComparator` — `Recorded` and `Go-Live` use a custom `OptionalStringComparator` that sinks nils to the end regardless of direction. New `Go-Live` column added.
- **Simpler clip editor**. Removed Identity → "Clip ID" duplicate label (it's in the sticky header), External Clip ID, Tracking Tag; removed Categorization → Keywords / Performers; removed the Files section entirely. Eight fields gone. Underlying columns preserved — imports still populate them, exports still emit them, search still indexes them.
- **Strict refine improvements**:
  - **Strip wrapping quotes** from Ollama output (straight + smart `"…"` and `'…'`). Up to 3 nested wraps peeled.
  - **Paragraph format normalisation**: trims, collapses 2+ spaces to one, collapses 3+ newlines to a single paragraph break, **joins single in-paragraph newlines with spaces** so sentence-per-line input becomes flowing prose. Idempotent.
  - Both run as a single `OllamaService.cleanRefineOutput(...)` post-processing pass after streaming completes.

## 2026-05-03 — Polish pass

- **Mobile-friendly HTML export.** Cards now pre-render as static HTML (no JSON.parse / no `atob`) so the file works in iOS Files preview, iMessage Quick Look, and any environment that limits JavaScript. JS layer is a progressive enhancement that adds live filter on top.
- **Auto-save in clip editor.** Pending edits flush on `.onDisappear` (selection change, sidebar nav, window close). Dirty/clean state shown in the footer with a coloured icon. The explicit Save button (⌘S) and Discard buttons disable when there are no unsaved changes.
- **Strict word-for-word refine prompt.** Default Ollama prompt rewritten with five worked examples and explicit "do not paraphrase / swap synonyms / restructure" rules. Temperature dropped 0.4 → 0.0 (greedy decoding) and `top_p` raised to 1.0 for the proofread workload. Auto-migration: any user still on a legacy default gets the new prompt on next launch; customised prompts are left alone. **Reset to default** button next to the prompt editor.
- **Persona pills got cutesy.** Heart icon, gradient fill, soft shadow. Extracted to a shared `PersonaPill` view. Used in Clips list, Editing Queue, Calendar dots, and the clip-editor sticky header.
- **Sticky title in clip editor.** Title is now `.title2.weight(.semibold)` (~22 pt) and lives outside the ScrollView so it never scrolls away. Truncates with "…" + tooltip on hover; never shrinks.
- **Title columns in Clips list and Editing Queue.** Title is now column 1 with `.title3.weight(.semibold)` (20 pt) and `min: 240–260, ideal: 460–520`. Other columns trimmed to free space.
- **Light / Dark / Auto** appearance picker in Settings → General. Saved as `colorScheme` in `settings.json`; applied via `.preferredColorScheme(...)`.
- **ColorPicker for accent + persona colours.** Replaces the old hex text fields. Hex string is still stored.
- **Default persona colours updated.** CoC = `#FFB6C1` (light pink), PoA = `#B22222` (sunset dark red). v4 migration only overwrites if the previous defaults are still in place.
- **Calendar auto-populates from clip go-live dates.** No manual link step needed. Display-only synthesised events (negative IDs) are merged into `eventsByDate` if no `calendar_events` row links to the clip yet.
- **Dashboard cards are clickable.** Each top-stat card (Clips / Fully posted / Partial / Not posted / No site scope) navigates to the Clips section with a matching posting-completeness filter pre-applied. New "Posting" filter dropdown in the Clips list.
- **Mark as historical** import option + per-clip context-menu action. Bulk-marks every persona-scope site as posted, posted_date defaulting to `goLiveDate ?? contentDate ?? today`. Status auto-recomputes to `production`.
- **Wipe / Reset clip data** in Settings → Backup. Runs a safety backup first, then deletes clips / postings / categories / history / calendar events while preserving personas, sites, categories, and rules.
- **Backup verify (Test) + restore.** Each backup row gets Test / Restore / Reveal buttons. Test extracts to a temp dir, opens the SQLite, returns a sheet with row counts and migrations applied. Restore confirms with an alert, runs a safety backup of current state, replaces support-dir contents, reopens the GRDB pool, and reloads `AppState`.
- **History capture.** Every field-level change to a clip — including title rename, status auto-transition, posting toggle, category set update — appends to `clip_history`. Visible in the clip editor as a collapsible "Change history" section.
- **Posting batch refactor — drill-down wizard.** Sites grid → site queue → focused per-clip posting window. Per-(site, persona) targets (so Clips4Sale [CoC] and Clips4Sale [PoA] are separate batches with their own login flows). Each clip opens an inline window with per-field copy buttons, posting-notes textarea, "Mark posted" + "Posted & next" (⌘↩).
- **Editing pipeline.** New status enum: `new` → `editing` → `to_post` → `posting` → `production`, all auto-derived from data + posting state. New columns `fcp_project_folder`, `production_folder`. New "Editing Queue" sidebar section. Per-stage hints on the clip editor explain what's needed to advance.
- **Clip ID format** changed to `YYYY-MM-DD-#####` (was `YYYYMMDD####`). 5-digit suffix gives 99 999 clips/day before expansion.
- **App icon redrawn** as a hand-painted clapperboard with violet→indigo gradient and diagonal stripes on the open snap. CFBundleIconFile now correctly set in Info.plist.
- **Smarter import.**
  - Single-sheet workbooks auto-route the largest sheet to Clips (no more "all sheets routed to Skip" dead-ends).
  - Header detection picks the row with the most populated text-ish cells in the first 15 rows (handles xlsx files with merged-title preambles).
  - "Mark as historical" toggle on the Preview step.
  - New `descriptionRefined` mapping target (was missing). New aliases for `Title (NEW)` / `Description Transcribe` / `Description Corrected` / `Session`.
  - Categories cleanup: strips voice-transcription preambles ("So, the categories are…", "cat shoes , flats", "categories chastity , …").
  - Persona normalization: `COC`/`coc`/`CoC` → `CoC`, etc.
  - Hero "Continue with \<sheet\> → Mapping" card on the Sheets step makes the recommended path obvious.

## 2026-05-03 — Phase 13 — Backup + polish

- `BackupService.runIfEnabled` triggers at app launch; throttle stored in `settings.lastBackupAt`. Auto-backup zip lands in `~/Downloads/MasterClipper backup/` with rolling retention by day count (0 = keep forever).
- `BackupSettingsTab` — toggle, dir picker, retention stepper, Run Now, recent backups list.
- `wipeAllClipData()` deletes clip / posting / history / calendar / price rows while keeping personas / sites / categories / rules. Always runs a backup first.

## 2026-05-03 — Phases 10–11 — Exports + Reports

- `ExportService` — CSV (RFC 4180), Markdown (full + per-clip), XLSX & DOCX via manual OOXML to a temp dir + `/usr/bin/zip`, PDF via `CGContext(consumer:)` + `NSGraphicsContext`.
- `HtmlExportService` — single self-contained `.html`. Now mobile-first, static-first (see top of changelog).
- `ReportService` — `postingStatus`, `categoryUsage`, `calendarRollup` aggregations.
- `ReportsRootView` — sidebar with four reports + ⌘-menu Export submenu.
- `ClipExportSheet` — per-clip toolbar action: plain-text / Markdown / PDF.
- `ImportExportTab` — default export directory + duplicate strategy + include-notes-in-search.

## 2026-05-03 — Phase 9 — Calendar

- `CalendarService.generateYear(_:rules:)` — walks Jan 1 → Dec 31, inserts blank `(date, persona)` rows for every weekday matching enabled rules.
- `CalendarRulesTab` — per-persona × weekday checkbox grid + year stepper + Generate button.
- `CalendarRootView` — segmented Year / Quarter / Month / Week / Day picker. Click-through navigation, "Today" jump, mini-month grids in Year/Quarter, full grid in Month, vertical week stack, full event cards on Day.
- Events render as `Title[Persona]` with persona-color dots and category line.

## 2026-05-03 — Phase 8 — Ollama refine

- `OllamaService` — streamed `/api/chat`, decoupled refine method.
- `OllamaSetup` — detects ollama in PATH, auto-starts `ollama serve` when needed, polls `/api/tags`.
- `AppState.init()` runs setup + connection in the background and falls back to the first installed model if the configured one isn't available.
- `OllamaSettingsTab` — base URL, model picker (live from `/api/tags`), refine prompt template editor with `Reset to default`, Test refine pane with streamed output.
- `ClipEditView` Refine button — streamed tokens, error display, history stamp on first refine.

## 2026-05-03 — Phase 7 — Smart Import (MVP cutoff)

- `XLSXReader` — hand-rolled. `/usr/bin/unzip -p` + `XMLParser` for sharedStrings / workbook / rels / sheet XML. Resolves shared-string references, pads cells by A1 column ref.
- `FuzzyMatch` — Levenshtein + alias dictionary; threshold ≥ 0.78. Punctuation (incl. parens) stripped during normalize so `Title (NEW)` matches `title new`.
- `ImportService` — orchestrator: xlsx / csv / tsv / pasted text. `commitClips`, `commitCalendarEvents`. Dup detection on `external_clip_id` then `(title, content_date)`.
- Dates parse ISO, US, EU, month-name, Excel serials. Lengths parse `mm:ss`, `hh:mm:ss`, fractional days, `7m49s`.
- `ImportWizardView` — 5-step wizard with hero recommended-action card, mapping table, preview, commit + historical toggle.

## 2026-05-03 — Phase 6 — Posting workflow

- `PostingService.clipsNotPosted(toSiteId:personaScope:)`, `markPosted`.
- `PostingBatchView` initially built as a single split view; later refactored to drill-down (Sites → Queue → Posting window) per user feedback.
- `PostingClipWindow` (formerly sheet) — per-field copy buttons, posting-notes textarea, Mark posted + Posted & next (⌘↩).

## 2026-05-03 — Phases 4–5 — Clip CRUD + Settings

- `ClipListView` master/detail with sortable Table, AND-token search across title / description / keywords / id / external id / notes, filters for persona / status / archived / posting (added later).
- `ClipDetailView` + `ClipEditView` — full editable form, sticky header, status badge, posting grid, change-history disclosure, auto-save on disappear.
- `NewClipView` sheet, auto ID via `IDGeneratorService`.
- `Personas / Categories / Sites` settings tabs with full CRUD.
- `AppState` mutation methods, `SearchService` AND-token LIKE.

## 2026-05-03 — Phases 2–3 — Models, DB, Settings, App shell

- 11 GRDB tables on v1: `personas`, `sites`, `categories`, `clips`, `clip_categories`, `clip_postings`, `id_sequences`, `calendar_events`, `calendar_rules`, `prices`, plus `grdb_migrations`.
- Seed data: 4 personas, 5 sites with persona scopes, calendar rules CoC=Mon+Thu / PoA=Wed+Fri.
- Models, `SettingsStore`, `DatabaseService`, `IDGeneratorService`, `AppState`, app shell, theme system, app menu commands, `DurationFormatter`.

## 2026-05-03 — Phase 1 — Skeleton

- Initial scaffold. XcodeGen `project.yml`. `build-app.sh` (auto-version from git, ad-hoc + Developer ID signing, builds in `/tmp`). Empty-window app launches.

## Schema migrations (cumulative)

| Migration | Effect |
|---|---|
| `v1_initial` | All 11 tables created with current columns. Seeded personas / sites / calendar_rules. |
| `v2_clip_history` | Added `clip_history` table for per-field change tracking. |
| `v3_editing_pipeline` | Added `clips.fcp_project_folder` + `clips.production_folder`. Remapped legacy status strings to the new pipeline. Migrated old `status='archived'` → `archived = 1`, `status = 'new'`. |
| `v4_persona_color_refresh` | Updated default persona colours: CoC `#7A4FFF` → `#FFB6C1` (light pink), PoA `#E9508C` → `#B22222` (sunset dark red). Idempotent — leaves user-customised colours alone. |
