# Obsidian Markdown sync (`sync-md-to-obsidian.sh`)

A repo-level utility (root of the repo, not a subproject) that mirrors every
git-tracked `.md` file in PhantomLives into an Obsidian vault for reading the
docs in Obsidian. Optionally self-installs a launchd agent that refreshes the
mirror on a schedule.

## What it does

- Copies the outer repo's git-tracked `.md` files (sourced via
  `git ls-files '*.md'`, ~319 files) into the vault, preserving directory
  structure. Because it uses the git index, it automatically skips
  `node_modules/`, `.build/`, `.venv/` clutter **and** the two nested
  standalone repos (`video-analyzer/`, `ClipperInfo/`).
- **One-way copy mirror.** Edits made in Obsidian do **not** flow back to git.
  The mirror is rebuilt from scratch each run, so files deleted or renamed in
  the repo disappear from the vault too. → Don't author notes inside the
  mirrored folder; they get wiped on the next sync.

## Where things live

| Thing | Path |
|---|---|
| Real mirror (the actual copied files) | `~/Library/Application Support/phantomlives-obsidian/PhantomLives/` |
| Vault-visible folder (symlink → mirror) | `<vault>/PhantomLives` |
| launchd agent plist | `~/Library/LaunchAgents/com.phantomlives.obsidian-sync.plist` |
| Run log | `~/Library/Logs/phantomlives-obsidian-sync.log` |

Default vault is `~/Documents/Obsidian Vault`; override with the
`OBSIDIAN_VAULT` env var (path to the vault root).

## Why a symlink instead of writing straight into the vault (the TCC fix)

macOS TCC protects `~/Desktop`, `~/Documents`, and `~/Downloads`. An
**interactive** terminal that's already been granted Documents access can
write there, but a **launchd background agent** runs in a different context
with no such grant — every write into `~/Documents/Obsidian Vault/` is denied
with `Operation not permitted`.

Rather than grant Full Disk Access to `/bin/bash` (broad, fiddly, and
unreliable for launchd-spawned processes), the script writes the real mirror
to a non-protected location under `~/Library/Application Support/` and exposes
it inside the vault via a **symlink**. Obsidian follows the symlink, so the
vault shows a normal `PhantomLives` folder, while the background agent only
ever writes outside the TCC-protected Documents folder. No permission prompt
is ever required.

The symlink is created once during `--install-agent`, which runs in the
interactive (already-granted) context. The recurring launchd runs only touch
the non-protected mirror path.

## Cross-Mac note

The script is committed to the repo; the launchd plist is **not** (it would
carry hardcoded `/Users/<name>/…` paths that break on the maintainer's other
Mac, which has a different username — see `docs/cross-mac-dev-setup.md`).
Instead the script generates the plist from `$HOME` at install time. On a new
machine, run `./sync-md-to-obsidian.sh --install-agent` once and it sets up
the symlink + agent locally.

## Usage

```bash
# Sync once, right now
./sync-md-to-obsidian.sh

# Install + load the launchd agent (default 3600s = hourly; also runs at login)
./sync-md-to-obsidian.sh --install-agent
./sync-md-to-obsidian.sh --install-agent 1800   # custom interval (30 min)

# Remove the agent (leaves the mirror + symlink in place)
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
