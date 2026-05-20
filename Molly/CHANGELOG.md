# Changelog

All notable changes to Molly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Molly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-05-20

### Added

- **Phase 3 — Scheduling engine + Reminders.**
- Migration `006_schedules.sql` adds `schedules` and `occurrences` tables. Five default schedules pre-seeded per spec: Fan Site Posting CoC/PoA (10 days before next month), Income update (3 days after month end), CoC release (weekly Mon + Thu), PoA release (weekly Wed + Fri).
- **No-cron Cadence engine** (`src/lib/cadence.ts`) modeled after `PurpleTracker/Sources/PurpleTracker/Models/Cadence.swift`. Six cadence kinds — `daily`, `weekly` (with day-of-week mask + everyN for biweekly), `monthly_dom` (clamped to end-of-month), `monthly_days_before_next`, `monthly_days_after_eom`, `every_n_days`. Pure functions: `nextOccurrencesAfter(cadence, from, count)`, `describeCadence(cadence)`, `isCadenceValid(cadence)`.
- **Occurrence materializer** (`src/data/occurrences.ts`) runs on app launch and every 30 minutes, populating occurrences for the next 60 days. Idempotent via `UNIQUE(schedule_id, due_at)` — re-runs no-op.
- **Reminders view** with two tabs: *Reminders* (Overdue / Today / Coming up next 7 days / Recently done) and *Schedules* (list + active toggle + edit + delete).
- **Schedule wizard** with cadence builder, weekday checkbox grid for weekly, three monthly flavors (Nth of month / N days before next month / N days after EOM), and a live "Next 5 dates" preview. No cron strings shown to the user, ever.
- **Satisfying check-off**: tap the circle → persona-tinted confetti burst (`CheckOffBurst` component, CSS-only, no canvas-confetti dep), 10-second **Undo** toast in the bottom-right.
- **Sidebar bell badge** showing combined overdue + today count for the active persona.
- **Home dashboard "today's reminders" widget** at the top, with one-click jump to the Reminders view.

## [0.2.2] — 2026-05-20

### Fixed

- **All database writes were blocked by ACL.** Tauri 2's `sql:default` capability set only grants `load` + `select`; the `execute` permission has to be added explicitly. This silently broke every customer save, site edit, taxonomy add, AND every clip imported via the MasterClipper wizard (which surfaced the error as "Command plugin:sql|execute not allowed by ACL"). Added `sql:allow-load` / `sql:allow-execute` / `sql:allow-select` / `sql:allow-close` to `capabilities/default.json`.

## [0.2.1] — 2026-05-20

### Fixed

- **Importer no longer appears stuck.** Large MasterClipper exports were silently grinding through SELECT+INSERT/UPDATE pairs with no UI feedback, so the screen sat on "⏳ Importing… don't close the app." indefinitely. Now:
  - `upsertClip` does `INSERT OR IGNORE` first and only falls back to a targeted UPDATE if the row already existed (fresh imports cost 1 IPC round-trip instead of 2).
  - The wizard shows a live counter (`Importing… 47 of 543 · 47 added, 0 updated`) plus a progress bar, and yields to the event loop every 25 rows so React can repaint.
  - The post-loop work runs in a `finally` block, so `setStage('done')` always fires — a thrown `logImport` or refresh callback can no longer trap the UI in the "running" state.
  - Per-row errors are captured and shown in an expandable list in the summary (instead of silently inflating the "skipped" count).

## [0.2.0] — 2026-05-20

### Added

- **Phase 2 — Calendar, MasterClipper import, Dashboard.**
- Migration `005_clips.sql` adds `clips` (PK = MasterClipper UID, so re-imports UPSERT cleanly) and a small `clip_imports` audit table for the "recent imports" widget.
- **MasterClipper CSV importer** (`src/views/Import/MasterClipperImport.tsx`): file picker → preview rows → per-source-persona mapping screen → bulk UPSERT → run summary (`{inserted, updated, skipped}`). Reads files via the webview's File API (no Tauri-side fs permission needed). Logs every run to `clip_imports`.
- **RFC 4180 CSV parser** (`src/lib/csv.ts`, ~60 lines) — quoted fields, embedded commas / newlines, CRLF, BOM. Avoids adding papaparse to the bundle.
- **Calendar view** (`src/views/Calendar/CalendarView.tsx`): month grid (6×7) with prev/next/today, persona-colored clip pills per day, click to open `ClipDetail`. Respects the active persona filter.
- **Clip detail modal** (`src/views/Calendar/ClipDetail.tsx`): all imported fields read-only + editable `mollyNotesHtml` (Tiptap) that is preserved across re-imports. Delete is two-tap.
- **Clips list view** with search, sort (`go_live` / `title` / `status` / `persona`), and an inline "📂 Import CSV" button that opens the wizard.
- **Home dashboard** widgets: MTD vs Prior MTD vs YTD vs all-time counts, per-persona breakdown bars, **reuse detection** (same `external_clip_id` OR same title within 14 days), recent-imports log. Filterable by active persona.
- `clipCounts`, `countByPersona`, `detectReuse`, `recentImports` data helpers in `src/data/clips.ts`.

### Changed

- Sidebar `Home` is now the dashboard (replaces the static welcome card).
- App.tsx wires `calendar` / `clips` view keys to real implementations.

## [0.1.0] — 2026-05-20

### Added

- **Phase 1 — Settings, Customers, Molly Helper.** First real feature drop on top of the Phase 0 shell.
- **Settings tabs**: Personas / Sites / Products / Interests / Backup.
- **Personas settings**: rename, redescribe, recolor (5 swatches per persona: primary / secondary / tint / accent / text). Edits live-update the active theme via `onPersonasChanged → refresh`.
- **Sites settings**: full CRUD with per-site color, short code, URL, username, free-form note, sort order, and an optional `loginGroup` flag for shared-login sites (e.g. OnlyFans CoC ↔ PoA). Grouped by persona; respects the active persona filter.
- **Preloaded sites** (per spec): 5 for CoC, 13 for PoA (NiteFlirt has four entries — main + Alice + Taylor + sluttysecrets). OnlyFans rows share `loginGroup = "of-shared"`.
- **Products / Interests settings**: identical CRUD pattern. Defaults preloaded: Phone, Cam, Customs, Physical-Panties/Pantyhose/Shoes Flats/Heels for products; Feet, Pantyhose, Panties, Humiliation for interests.
- **Customer tracker**:
  - UID format `YYYY-MM-DD-#####` (mirrors `MasterClipper/Sources/MasterClipper/Services/IDGeneratorService.swift`, computed in `src/lib/uid.ts`).
  - Fields: username, real name, 5 email slots, persona binding (or unbound for cross-persona contacts), multi-select product chips, multi-select interest chips, **rich-text notes** via Tiptap (StarterKit + Link + Placeholder).
  - List view with search across UID / username / real name and per-persona filter.
  - Detail editor with explicit Save (dirty-tracking) and ConfirmButton-guarded delete.
- **Molly Helper**: persona-grouped grid of clickable site cards. Top border tinted with each site's color; click **Open** to launch via `@tauri-apps/plugin-opener`; **Copy user** copies the saved username to clipboard. Shows `🔗 shared login` hint for sites in a login group.
- **Shared components**: `ColorPicker` (native `<input type="color">` + curated swatch row), `ChipMultiSelect`, `ConfirmButton` (two-tap guard), `RichTextNotes` (Tiptap with persona-themed lite-prose styling).
- **Migrations**: `002_sites.sql`, `003_taxonomy.sql`, `004_customers.sql` wired into the plugin's migration list in `src-tauri/src/lib.rs`.

### Changed

- `state/personas.ts` is now a thin hook over `data/personas.ts` (extracted CRUD), exposing a `refresh()` so persona edits propagate to the switcher immediately.
- App.tsx wires the new SettingsView / CustomerListView / MollyHelper routes; placeholder cards remain for the calendar / clips / income / expenses / reports areas.

## [0.0.1] — 2026-05-20

### Added

- **Phase 0 — Foundation.** Initial scaffold of the Molly app.
- Tauri 2 + React 19 + TypeScript + Tailwind CSS + Vite project layout.
- AI-generated app icon set (`.icns`, `.ico`, full PNG ladder).
- SQLite migration `001_init.sql` with `personas` and `app_settings` tables.
- Three preloaded personas (Curse Of Curves / Princess of Addiction / Sheer Attraction) with primary/secondary/tint/accent/text colors.
- **Persona switcher** in the top bar (`CoC` / `PoA` / `Sa` / `★ All`); the whole UI recolors via CSS custom properties.
- Fixed-width sidebar (240px) with `Ctrl+S` / `⌘+S` toggle. (Avoids `NavigationSplitView` — Tauri uses Flexbox, immune to that AppKit bug, but the convention still matches PhantomLives.)
- **Backup-on-launch service** (Rust port of `Timeliner/Services/BackupService.swift`):
  - Default location `~/Downloads/Molly backup/` (Mac) / `%USERPROFILE%\Downloads\Molly backup\` (Windows).
  - 14-day retention default (0 = keep forever).
  - 5-minute launch debounce.
  - Only trims archives matching `Molly-*.zip`; unrelated files are never touched.
  - **Test** (verify), **Restore** (with mandatory pre-restore safety archive), and **Reveal** actions.
- Settings → Backup UI with toggle, path picker, retention stepper, Run Backup Now, Reveal in Finder/Explorer, recent backups list with per-row Test/Restore/Reveal.
- `install.sh` follows the PhantomLives standard: quit running copy, `ditto --noextattr` to `/Applications/Molly.app`, relaunch (`--no-open` to suppress).
- `build-app.sh` runs `pnpm tauri build` then auto-chains into `install.sh` (`BUILD_ONLY=1` / `--no-install` escape hatches).
- `run-tests.sh` runs `cargo test --lib` against the Rust backend.
- Backup module unit tests: debounce, retention trim (only Molly-prefixed zips), target dir auto-create, listing order, missing database flag.
- GitHub Actions workflow `.github/workflows/release.yml` cross-builds signed `.dmg` and `.exe` on `v*` tag push via `tauri-action`.
- `tauri-plugin-updater` wired to a GitHub Releases `latest.json` endpoint (public key placeholder; replace before signed Phase 5 release).

### Notes

- Out of Phase 0 scope: calendar, MasterClipper import, scheduler/reminders, income, expenses, customers, Molly Helper, reports.
- The updater public key in `tauri.conf.json` is a placeholder — it must be replaced with a real key before publishing a signed update.
