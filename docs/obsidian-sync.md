# Obsidian Markdown sync (`sync-md-to-obsidian.sh`)

A repo-level utility (root of the repo, not a subproject) that mirrors every
git-tracked `.md` file in PhantomLives into an Obsidian vault for reading the
docs in Obsidian. Optionally self-installs a launchd agent that refreshes the
mirror on a schedule.

## What it does

- Copies the outer repo's **git-tracked** `.md` files (via
  `git ls-files '*.md'`, ~325 files) into a `PhantomLives/` folder inside the
  vault, preserving directory structure. Using the git index is what keeps the
  mirror clean: anything not tracked is skipped — `node_modules/`, SwiftPM
  `build/` & `.build/` dependency checkouts, built `.app` bundles, `.venv/`,
  and the two nested standalone repos (`video-analyzer/`, `ClipperInfo/`).
  (An earlier `--include='*.md'` filter approach was abandoned because it swept
  in 146 dependency/`build/` README files; only the git index is precise.)
- **One-way copy mirror.** Edits made in Obsidian do **not** flow back to git.
  → Don't author notes inside the mirrored folder.
- **Incremental.** rsync skips unchanged files and a prune pass removes `.md`
  that's no longer tracked (handles deletes/renames). Unchanged files are not
  rewritten each run — important because the vault is usually iCloud-synced and
  rewriting everything hourly would churn iCloud (and risk `' 2'`-dupe
  corruption — see `CLAUDE.md`).

## Where things live

| Thing | Path |
|---|---|
| Mirror (real folder inside the vault) | `<vault>/PhantomLives/` |
| launchd agent plist | `~/Library/LaunchAgents/com.phantomlives.obsidian-sync.plist` |
| Run log | `~/Library/Logs/phantomlives-obsidian-sync.log` |

The script's built-in default vault is `~/Documents/Obsidian Vault`; override
with the `OBSIDIAN_VAULT` env var (path to the vault root). **The vault in
effect at `--install-agent` time is baked into the agent's plist
`EnvironmentVariables`**, so the scheduled run targets it regardless of the
default — re-run `--install-agent` to repoint an existing agent.

To mirror into a vault that's synced by **Obsidian Sync** (the paid service) or
that lives in Obsidian's iCloud container — which is what actually reaches your
iPhone/iPad — install the agent against that vault's real path, e.g.:

```bash
OBSIDIAN_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/<Your Vault>" \
  ./sync-md-to-obsidian.sh --install-agent
```

Note: writing files into the vault folder is necessary but not sufficient for
Obsidian Sync — the desktop Obsidian app must be running and connected to your
Sync remote for it to push the mirrored files up; placing them in an
`iCloud~md~obsidian` vault also propagates them via iCloud. The repo's
`~/Documents/Obsidian Vault` is a *different* folder from any vault registered
in Obsidian — confirm the target matches the vault you actually open on your
devices (`~/Library/Application Support/obsidian/obsidian.json` lists them).

## Why a real folder + Full Disk Access (not a symlink)

The mirror is written as a **real folder** inside the vault. An earlier design
wrote the files to `~/Library/Application Support/` and symlinked them into the
vault — that **failed**: Obsidian vaults usually live under `~/Documents`,
which is iCloud-synced, and **iCloud Drive does not support symlinks — it
strips them on sync.** The symlink vanished within hours and Obsidian reported
"path not found." A real folder of plain Markdown syncs through iCloud fine.

The cost of writing directly into `~/Documents` is **TCC**: macOS protects
`~/Desktop`, `~/Documents`, and `~/Downloads`. An interactive terminal that's
already been granted Documents access can write there (so manual runs and the
install-time seed work), but a **launchd background agent** runs with no such
grant and is denied with `Operation not permitted`.

So the launchd agent needs **Full Disk Access**, granted once:

> System Settings ▸ Privacy & Security ▸ Full Disk Access ▸ **+** ▸ press
> **⇧⌘G** ▸ type `/bin` ▸ select **`bash`** ▸ enable the toggle.

(The agent runs `/bin/bash <script>`, so `/bin/bash` is the binary TCC
attributes the write to.) After granting, force a run to confirm:
`launchctl kickstart -k "gui/$(id -u)/com.phantomlives.obsidian-sync"` and
check the log shows a fresh "Mirrored N markdown files" line.

## Cross-Mac note

The script is committed to the repo; the launchd plist is **not** (it would
carry hardcoded `/Users/<name>/…` paths that break on the maintainer's other
Mac, which has a different username — see `docs/cross-mac-dev-setup.md`).
Instead the script generates the plist from `$HOME` at install time. On a new
machine, run `./sync-md-to-obsidian.sh --install-agent` once and grant Full
Disk Access there too.

## Usage

```bash
# Sync once, right now
./sync-md-to-obsidian.sh

# Install + load the launchd agent (default 3600s = hourly; also runs at login)
./sync-md-to-obsidian.sh --install-agent
./sync-md-to-obsidian.sh --install-agent 1800   # custom interval (30 min)

# Remove the agent (leaves the mirror in place)
./sync-md-to-obsidian.sh --uninstall-agent

# Point at a different vault
OBSIDIAN_VAULT="/path/to/vault" ./sync-md-to-obsidian.sh
```

### Operational commands

```bash
# Force the agent to run immediately
launchctl kickstart -k "gui/$(id -u)/com.phantomlives.obsidian-sync"

# Check the agent's state
launchctl print "gui/$(id -u)/com.phantomlives.obsidian-sync"

# Tail the log
cat ~/Library/Logs/phantomlives-obsidian-sync.log
```
