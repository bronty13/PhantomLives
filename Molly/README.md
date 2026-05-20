# Molly

Molly is the central hub for a content creator's day — personas, clips, schedules, customers, income and expenses, all in one cute little app. It runs on **macOS** and **Windows**, with the same database format on both, so a Windows export can be opened on a Mac dev machine and vice-versa.

> **Phase 5.** Full data export → Slack DM workflow, dev-only import, auto-update UI wired to a real minisign pubkey. All five planned phases are now shipped (see [roadmap](#roadmap)).

## Quick start (Mac dev)

```sh
brew install rust pnpm librsvg     # one-time
cd Molly
pnpm install
pnpm tauri dev                     # hot-reload dev build

./build-app.sh                     # production .app, installs to /Applications/
```

## Quick start (Windows user)

Install the `.exe` from the latest [GitHub Release](https://github.com/bronty13/PhantomLives/releases). The installer is signed; Windows SmartScreen should accept it without warnings. Updates are checked automatically on launch and applied from Settings → Updates.

## Personas

The three preloaded personas are:

| Code  | Name                    | Primary color |
|-------|-------------------------|--------------|
| `CoC` | Curse Of Curves         | Baby pink `#FFC0CB` |
| `PoA` | Princess of Addiction   | Red `#C8102E` |
| `Sa`  | Sheer Attraction        | Tan `#D2B48C` |

Switch personas with the chips in the top bar. The whole UI recolors. Pick **★ All** for the cross-persona view.

## Default file locations

Per the PhantomLives convention:

- **App data** (database + attachments): `~/Library/Application Support/Molly/` (Mac), `%APPDATA%\com.phantomlives.molly\` (Windows).
- **User-visible exports**: `~/Downloads/Molly/` (auto-created; configurable in Settings).
- **Backups** (auto-on-launch + Run Now): `~/Downloads/Molly backup/` (auto-created; configurable in Settings → Backup).

## Backup

Molly zips its app-data directory on launch into `~/Downloads/Molly backup/Molly-YYYY-MM-DD-HHmmss.zip`. Default retention is 14 days; set to `0` to keep forever. A 5-minute debounce prevents repeated debug relaunches from filling the folder. From Settings → Backup you can:

- Run a backup now (ignores the debounce).
- Pick a different backup directory.
- Adjust retention.
- **Test** an archive (verifies the database is present and counts entries).
- **Restore** an archive — a safety pre-restore archive is written first.
- **Reveal** any archive in Finder / Explorer.

## Tests

```sh
./run-tests.sh           # backup module: debounce, retention trim, listing
```

## Roadmap

| Phase | Scope |
|-------|-------|
| 0     | App shell, icon, persona theming, backup-on-launch, CI release pipeline. |
| 1     | Settings (personas/sites/products/interests) + Customer tracker + Molly Helper. |
| 2     | Calendar + MasterClipper import + dashboard widgets. |
| 3     | Scheduling engine + reminders + check-off. |
| 4     | Income (adhoc + per-site) + expenses (one-off + recurring) + reports. |
| 5     | Full export → dev / import on dev / auto-update polish. *(this build)* |

## Layout

```
Molly/
  src/             React + TypeScript frontend
  src-tauri/       Rust backend (DB, backup, updater, file ops)
    icons/         AI-generated app icon set
    migrations/    SQLite migrations
  install.sh       Mac: replace /Applications/Molly.app + relaunch
  build-app.sh     Mac: build + install + relaunch
  .github/workflows/release.yml   Tagged builds → signed .dmg + .exe
```
