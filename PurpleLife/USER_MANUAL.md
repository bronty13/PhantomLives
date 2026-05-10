# PurpleLife User Manual

> **Phase 1 scaffold.** The app launches, performs a backup-on-launch, and shows a placeholder window. The real screens (Today, Sidebar, Table/Kanban/Calendar/Gallery, Detail, Schema editor, Quick switcher, Settings) arrive in Phase 2.

## Where your data lives

- **Internal**: `~/Library/Application Support/PurpleLife/`
  - `purplelife.sqlite` — single database, one `objects` table.
  - `settings.json` — preferences.
  - `attachments/` — file payloads (used from Phase 2 onward).
- **Backups**: `~/Downloads/PurpleLife backup/` — zip archives named `PurpleLife-YYYY-MM-DD-HHmmss.zip`.
- **Exports** (later phases): `~/Downloads/PurpleLife/`.

## Backup behavior

- Runs automatically on every launch.
- **Debounced**: a second launch within 5 minutes of a successful backup is a no-op — protects against backup-folder churn during a debugging session.
- **Retention**: archives older than 14 days are trimmed (only `PurpleLife-*.zip` files; nothing else in the directory is touched). Set `backupRetentionDays = 0` in `settings.json` to disable trimming.
- **Manual run**: the placeholder window has a "Run backup now" button. The full Settings → Backup pane lives at **PurpleLife → Settings…** (`⌘,`).

## Settings → Backup pane

`⌘,` opens Settings; the Backup tab shows:

- **Auto-backup** — toggle, directory picker (with the resolved path shown in monospaced caption), retention stepper (`0` = keep forever), "Run backup now", and the last-backup timestamp.
- **Recent backups** — list of `PurpleLife-*.zip` archives in the configured directory, newest-first, with three buttons per row:
  - **Test** — extract to a temp dir, validate the database, count rows. Non-destructive.
  - **Restore** — replace the current database with the selected backup. **A safety backup of the current state is written first** before any destructive change. Confirmation alert is mandatory.
  - **Reveal** — opens the file in Finder.
- **Last test result** — surfaces what the most recent Test reported (object count, file count, migrations applied).

## Versioning

Shown in the placeholder window. The format is `vMAJOR.MINOR.COMMITS (COMMITS.SHORTSHA)` — the commit count makes every successful build a strictly newer version, which keeps install-overwrite predictable.
