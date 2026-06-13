# PurpleMirror

A tiny macOS **menu-bar** app that monitors and controls the repo's
Obsidian Markdown sync (`sync-md-to-obsidian.sh` + its launchd agent
`com.phantomlives.obsidian-sync`). It's a thin GUI — the shell script stays the
single source of truth; PurpleMirror just drives and reports it.

> Background on the sync itself (vault setup, the Obsidian-Sync-only rule, the
> data-loss postmortem) lives in **`../docs/obsidian-setup.md`** and
> **`../docs/obsidian-sync.md`**. Read those before changing how the vault syncs.

## What it does

- **Menu-bar glyph** that reflects health at a glance:
  - `checkmark.icloud` — up to date (agent loaded, last run OK)
  - `arrow.triangle.2.circlepath` — syncing now
  - `exclamationmark.icloud` — auto-sync off (no agent installed)
  - `xmark.icloud` — last run failed
- **Status panel** (click the glyph): last sync time, files mirrored, auto-sync
  on/off + interval, last result, and the target vault.
- **Sync Now** — kickstarts the installed agent (honors its baked-in vault), or
  runs the script directly if no agent is installed.
- **Settings** — toggle automatic background sync (installs/uninstalls the
  launchd agent), change the interval (15 min / 30 min / 1 hr / 2 hr / 6 hr or a
  custom number of minutes), and view/choose the script path + target vault.
- **View Log** — tails `~/Library/Logs/phantomlives-obsidian-sync.log` with
  refresh, reveal-in-Finder, and open-in-Console.

## Build / run

```bash
./build-app.sh          # build + install to /Applications + relaunch (menu-bar)
./build-app.sh --no-install   # just build PurpleMirror.app here
BUILD_ONLY=1 ./build-app.sh   # build only
./run-tests.sh          # swift test (pure status-parsing logic)
```

It's an `LSUIElement` app — **no Dock icon**; look for the glyph in the menu bar.

## How it talks to the sync

| Action | Under the hood |
|---|---|
| Status | reads the agent plist (`StartInterval`, `OBSIDIAN_VAULT`), tails the log, and parses `launchctl print gui/<uid>/com.phantomlives.obsidian-sync` |
| Sync Now | `launchctl kickstart -k …` (or runs the script if no agent) |
| Change interval / enable / disable | re-runs `sync-md-to-obsidian.sh --install-agent <secs>` / `--uninstall-agent` with `OBSIDIAN_VAULT` set to the current vault |

Default script path: `~/dev/PhantomLives/sync-md-to-obsidian.sh` (configurable in
Settings).

## Notes

- **Not sandboxed** — it manages a launchd agent and reads `~/Library`, so the
  App Sandbox is intentionally off (like the other PhantomLives utility apps).
- **Auto-backup-on-launch standard: exempt.** PurpleMirror owns no user data
  beyond two recreatable preferences (script path + interval, in UserDefaults);
  there is nothing to back up. (Per CLAUDE.md rule #7, stated explicitly.)
- The icon is generated from `Scripts/generate-icon.swift` (no checked-in binary
  icon), per the repo's app-icon standard.
