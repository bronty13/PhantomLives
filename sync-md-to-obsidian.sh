#!/usr/bin/env bash
#
# sync-md-to-obsidian.sh — one-way mirror of this repo's Markdown files into
# an Obsidian vault, preserving directory structure.
#
# It is a *copy* mirror: edits made in Obsidian do NOT flow back to git.
# Files removed/renamed in the repo are removed from the mirror too.
#
# The mirror is written as a REAL folder inside the vault. Because Obsidian
# vaults commonly live under ~/Documents (iCloud-synced) and iCloud Drive
# strips symlinks, a real folder is the only thing that survives there. The
# sync is incremental (rsync --delete), so unchanged files are not rewritten
# each run — important for keeping iCloud churn (and ' 2'-dupe corruption) low.
#
# macOS TCC protects ~/Documents, so the launchd background agent needs
# Full Disk Access to write the mirror there. Grant it once (see README /
# docs/obsidian-sync.md). Interactive/manual runs work without it if the
# terminal already has Documents access.
#
# Usage:
#   ./sync-md-to-obsidian.sh                 Run the sync once.
#   ./sync-md-to-obsidian.sh --install-agent [interval_seconds]
#                                            Install + load a launchd agent
#                                            (default 3600s = hourly). The vault
#                                            in effect at install time (default
#                                            or $OBSIDIAN_VAULT) is BAKED into
#                                            the agent's plist EnvironmentVariables,
#                                            so the scheduled run targets it.
#   ./sync-md-to-obsidian.sh --uninstall-agent
#                                            Unload + remove the launchd agent.
#
# Override the vault location with $OBSIDIAN_VAULT (path to the vault root).
# To target an Obsidian-Sync / iCloud-container vault, install with e.g.:
#   OBSIDIAN_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/<Vault>" \
#     ./sync-md-to-obsidian.sh --install-agent
#
set -euo pipefail

# launchd gives agents a minimal PATH; make sure git/rsync are findable.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SRC="$HOME/dev/PhantomLives"
SCRIPT="$SRC/sync-md-to-obsidian.sh"
VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"
DEST="$VAULT/PhantomLives"

LABEL="com.phantomlives.obsidian-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/phantomlives-obsidian-sync.log"

install_agent() {
  local interval="${1:-3600}"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  run_sync   # seed the mirror immediately (interactive context has access)

  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OBSIDIAN_VAULT</key>
        <string>$VAULT</string>
    </dict>
    <key>StartInterval</key>
    <integer>$interval</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST_EOF

  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Installed launchd agent: $LABEL (every ${interval}s)"
  echo "  vault: $VAULT"
  echo "  plist: $PLIST"
  echo "  log:   $LOG"
  echo
  echo "IMPORTANT: grant Full Disk Access so the background agent can write to"
  echo "the iCloud-synced vault. System Settings ▸ Privacy & Security ▸ Full"
  echo "Disk Access ▸ + ▸ ⇧⌘G ▸ /bin ▸ select 'bash' ▸ enable it."
}

uninstall_agent() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed launchd agent: $LABEL"
}

run_sync() {
  if [[ ! -d "$VAULT" ]]; then
    echo "error: vault not found at: $VAULT" >&2
    echo "       set OBSIDIAN_VAULT=/path/to/your/vault and re-run." >&2
    exit 1
  fi
  mkdir -p "$DEST"
  cd "$SRC"

  # Mirror ONLY git-tracked .md files (skips node_modules/.build/build/ dep
  # checkouts, built .app bundles, .venv, and the nested standalone repos —
  # anything not in the git index). -0 handles paths with spaces safely.
  # rsync (no --delete here) skips unchanged files, so iCloud isn't churned.
  git ls-files -z '*.md' | rsync -0 -a --files-from=- "$SRC/" "$DEST/"

  # Prune: drop any .md in the mirror that's no longer tracked (handles
  # deletes/renames). --files-from can't do this, so reconcile by hand.
  local tracked existing
  tracked="$(mktemp)"; existing="$(mktemp)"
  git ls-files '*.md' | sort > "$tracked"
  ( cd "$DEST" && find . -name '*.md' -type f -print | sed 's|^\./||' ) | sort > "$existing"
  comm -13 "$tracked" "$existing" | while IFS= read -r f; do
    [[ -n "$f" ]] && rm -f "$DEST/$f"
  done
  find "$DEST" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  local count; count=$(wc -l < "$tracked" | tr -d ' ')
  rm -f "$tracked" "$existing"

  echo "$(date '+%Y-%m-%d %H:%M:%S')  Mirrored $count markdown files → $DEST"
}

case "${1:-}" in
  --install-agent)   install_agent "${2:-}";;
  --uninstall-agent) uninstall_agent;;
  "")                run_sync;;
  *) echo "usage: $0 [--install-agent [interval_seconds] | --uninstall-agent]" >&2; exit 2;;
esac
