# Changelog

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
