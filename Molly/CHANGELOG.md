# Changelog

All notable changes to Molly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Molly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
