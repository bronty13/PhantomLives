# Changelog

All notable changes to Molly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Molly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
