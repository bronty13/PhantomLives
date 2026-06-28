# PurpleMirror

A tiny macOS **menu-bar** app that monitors and controls PhantomLives's
**background launchd jobs** — the Obsidian Markdown sync
(`sync-md-to-obsidian.sh` / `com.phantomlives.obsidian-sync`) **and** PurpleAttic's
per-source archive jobs (`com.bronty13.external-photo-sync.<id>` /
`external-messages-sync.<id>`). It's a thin GUI — each script/plist stays the
single source of truth; PurpleMirror just drives and reports them.

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
  "Mirrored N files"; external archives → "Staged N new" / "No new items" /
  "Pull failed (exit N)"); unknown jobs show their last log line. Each row has
  **Run Now** and **View Log**.
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

| Action | Script-managed job (Obsidian) | Plist-managed job (external archives, and any unknown agent) |
|---|---|---|
| Status | tail log + parse `launchctl print gui/<uid>/<label>` | same |
| Run Now | `launchctl kickstart -k …` (or runs the script if not loaded) | `launchctl kickstart -k …` (bootstraps first if needed) |
| Enable / disable | `… --install-agent <secs>` / `--uninstall-agent` (carries `OBSIDIAN_VAULT`) | `launchctl bootstrap` / `bootout` |
| Change interval | `… --install-agent <secs>` | **rewrites only the plist's `StartInterval`** (atomic, with a `.bak` restored if the reload fails), then bootout+bootstrap |

The plist-managed interval edit deliberately touches **only** `StartInterval` —
args, env, and log paths are preserved verbatim — so an operational backup plist
can't be left in a broken state.

## Remote hosts (monitor another Mac over SSH)

PurpleMirror can also watch the launchd jobs on a **remote** Mac — e.g. a dedicated
always-on "runner" that owns the scheduled archive jobs — so one instance (on Vortex
*or* MB14) shows local and remote jobs together. Add a host under **Settings ▸ Hosts**
(SSH user / host / optional identity file) and hit **Test connection**; its jobs appear
grouped by host (e.g. "Runner · Photos").

- The remote Mac needs **Remote Login** enabled and this Mac's SSH public key in its
  `~/.ssh/authorized_keys`. Connections are **key-only** (`BatchMode=yes` — a missing key
  fails fast rather than prompting) and bounded by `ConnectTimeout`; SSH ControlMaster
  multiplexing keeps the many small status calls cheap.
- **Status, logs, Run Now, and schedule editing** (enable/disable + change interval) all work for
  remote jobs. The plist interval edit uses `plutil -replace … -integer` over ssh (only
  `StartInterval` is touched, with a backup restored if the reload fails); script-managed jobs
  (e.g. the Obsidian sync) carry their env inlined into the remote command since ssh doesn't
  forward it.
- An unreachable/asleep host degrades gracefully: it's detected live (mid-session, via ssh's
  connect-failure exit), shown in a menu **offline banner** with a "last seen" time, keeps its
  jobs (not dropped), and is retried with **backoff** (every tick when healthy → ~once a minute
  when down) so it never burns a connect-timeout on each refresh. Per-host concurrent refresh
  means a slow host can't stall the others.
- **Quick-connect shortcuts:** each remote host row in Settings ▸ Hosts has buttons to **SSH**
  (opens Terminal via `ssh://`), **SMB** (opens file sharing in Finder via `smb://`), and **Screen
  Sharing** (opens VNC via `vnc://`). SMB/VNC require File Sharing / Screen Sharing enabled on the
  remote Mac.
- Everything is additive — a default install with only the local Mac behaves exactly as before.

### Fleet (mesh) — every node sees every other

Rather than adding each Mac as a remote host on each instance, define the set **once** in a fleet
file placed on every node; each node auto-meshes with the rest.

- The file is `~/Library/Application Support/PurpleMirror/fleet.json` (see `fleet.example.json`).
  It is **local-only and must NOT be committed** — it carries LAN IPs/usernames and this repo is
  public. Distribute it peer-to-peer over SSH (e.g. `scp`), not through the repo. `fleet.json` and
  `hosts.json` are in `.gitignore` as a guard.
- Each node identifies **itself** by `~/Library/Application Support/PurpleMirror/node-id` (a file
  containing that machine's fleet `id`), falling back to matching `computerName` against
  `scutil --get ComputerName`. The other machines become remote hosts automatically.
- Each machine still needs **Remote Login** on and the *others'* SSH public keys in its
  `~/.ssh/authorized_keys` (a full mesh is N×N directed SSH links). Fleet hosts that aren't yet
  reachable simply show offline until that's set up.
- Fleet hosts appear with a **FLEET** badge and are read-only in Settings ▸ Hosts (edit `fleet.json`
  to change them); manually-added hosts are merged in and deduped by ssh target.

## Notes

- **Not sandboxed** — it manages launchd agents and reads `~/Library`, so the App
  Sandbox is intentionally off (like the other PhantomLives utility apps).
- **Auto-backup-on-launch standard: exempt.** PurpleMirror owns no user data
  beyond recreatable preferences; there is nothing to back up. (Per CLAUDE.md rule
  #7, stated explicitly.)
- The icon is generated from `Scripts/generate-icon.swift` (no checked-in binary
  icon), per the repo's app-icon standard.
