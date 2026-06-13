# PurpleMirror

A tiny macOS **menu-bar** app that monitors and controls PhantomLives's
**background launchd jobs** — the Obsidian Markdown sync
(`sync-md-to-obsidian.sh` / `com.phantomlives.obsidian-sync`) **and** PurpleAttic's
photo-archive jobs (e.g. Rachel's hourly sync, `com.bronty13.rachel-photo-sync`).
It's a thin GUI — each script/plist stays the single source of truth; PurpleMirror
just drives and reports them.

It **auto-discovers** jobs: every launchd agent in `~/Library/LaunchAgents` whose
label is under `com.phantomlives.*` or `com.bronty13.*` shows up as a row, so new
jobs added later appear automatically with no relaunch.

> Background on the Obsidian sync (vault setup, the Obsidian-Sync-only rule, the
> data-loss postmortem) lives in **`../docs/obsidian-setup.md`** and
> **`../docs/obsidian-sync.md`**. Read those before changing how the vault syncs.

## What it does

- **Menu-bar glyph** = the **worst** job's health at a glance:
  - `checkmark.icloud` — all good (agents loaded, last runs OK)
  - `arrow.triangle.2.circlepath` — a job is running now
  - `exclamationmark.icloud` — attention (a job's auto-run is off, or a recognized
    log-level hiccup like a skipped/failed pull)
  - `xmark.icloud` — a job's last run failed
- **Status panel** (click the glyph): one row per job — health, last-activity time,
  and a tailored one-line digest. Known jobs are parsed specially (Obsidian →
  "Mirrored N files"; Rachel → "Staged N new" / "No new items" / "Pull failed
  (exit N)"); unknown jobs show their last log line. Each row has **Run Now** and
  **View Log**.
- **Settings** — pick a job, then: toggle its automatic background run
  (load/unload its launchd agent), change its interval (15 min / 30 min / 1 hr /
  2 hr / 6 hr or a custom number of minutes), Run Now, and see its log/script/label
  paths.
- **Job Logs window** — pick any job from the toolbar and tail its log with a
  **Live tail** toggle (auto-follows new lines every 1.5s), manual refresh,
  reveal-in-Finder, and open-in-Console.
- **Failure alerts** — posts a macOS notification (naming the job) when a run
  fails, once per failed run, alongside the menu-bar glyph.
- **Auto-update** via **Sparkle 2** — a "Check for Updates…" item + automatic
  daily background checks. Releases are notarized + EdDSA-signed and announced in
  `appcast.xml`; cut one with `./Scripts/release.sh` (see `RELEASING.md`).

## Build / run

```bash
./build-app.sh          # build + install to /Applications + relaunch (menu-bar)
./build-app.sh --no-install   # just build PurpleMirror.app here
BUILD_ONLY=1 ./build-app.sh   # build only
./run-tests.sh          # swift test (pure status-parsing / plist / registry logic)
```

It's an `LSUIElement` app — **no Dock icon**; look for the glyph in the menu bar.

## How it talks to the jobs

Discovery scans the `~/Library/LaunchAgents` **directory** (so the transient
`application.*` GUI jobs in `launchctl list` never appear). Each discovered agent
gets a *profile* that picks its display name, log path, log parser, and scheduling
backend:

| Action | Script-managed job (Obsidian) | Plist-managed job (Rachel, and any unknown agent) |
|---|---|---|
| Status | tail log + parse `launchctl print gui/<uid>/<label>` | same |
| Run Now | `launchctl kickstart -k …` (or runs the script if not loaded) | `launchctl kickstart -k …` (bootstraps first if needed) |
| Enable / disable | `… --install-agent <secs>` / `--uninstall-agent` (carries `OBSIDIAN_VAULT`) | `launchctl bootstrap` / `bootout` |
| Change interval | `… --install-agent <secs>` | **rewrites only the plist's `StartInterval`** (atomic, with a `.bak` restored if the reload fails), then bootout+bootstrap |

The plist-managed interval edit deliberately touches **only** `StartInterval` —
args, env, and log paths are preserved verbatim — so an operational backup plist
can't be left in a broken state.

## Notes

- **Not sandboxed** — it manages launchd agents and reads `~/Library`, so the App
  Sandbox is intentionally off (like the other PhantomLives utility apps).
- **Auto-backup-on-launch standard: exempt.** PurpleMirror owns no user data
  beyond recreatable preferences; there is nothing to back up. (Per CLAUDE.md rule
  #7, stated explicitly.)
- The icon is generated from `Scripts/generate-icon.swift` (no checked-in binary
  icon), per the repo's app-icon standard.
