#!/usr/bin/env bash
#
# sync-md-to-obsidian.sh — one-way mirror of this repo's tracked Markdown
# files into an Obsidian vault, preserving directory structure.
#
# It is a *copy* mirror: edits made in Obsidian do NOT flow back to git.
# The mirror is rebuilt from scratch each run, so files you delete or rename
# in the repo disappear from the vault too.
#
# TCC note: macOS protects ~/Documents, so a launchd background agent cannot
# write there (only interactive, already-granted apps can). To stay fully
# automated WITHOUT a Full Disk Access grant, the real mirror is written to a
# non-protected location and exposed inside the vault via a symlink. Obsidian
# follows the symlink, so the vault shows a normal "PhantomLives" folder.
#
# Usage:
#   ./sync-md-to-obsidian.sh                 Run the sync once.
#   ./sync-md-to-obsidian.sh --install-agent [interval_seconds]
#                                            Create the vault symlink, then
#                                            install + load a launchd agent
#                                            (default 3600s = hourly).
#   ./sync-md-to-obsidian.sh --uninstall-agent
#                                            Unload + remove the launchd agent
#                                            (leaves the mirror + symlink).
#
# Override the vault location with $OBSIDIAN_VAULT (path to the vault root).
#
set -euo pipefail

# launchd gives agents a minimal PATH; make sure git/rsync are findable.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SRC="$HOME/dev/PhantomLives"
SCRIPT="$SRC/sync-md-to-obsidian.sh"

# Real mirror — outside any TCC-protected folder, so launchd can write it.
TARGET="$HOME/Library/Application Support/phantomlives-obsidian/PhantomLives"
# Symlink inside the vault that points at the real mirror.
VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"
LINK="$VAULT/PhantomLives"

LABEL="com.phantomlives.obsidian-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/phantomlives-obsidian-sync.log"

# Create (or repair) the vault symlink. Requires Documents access, so this
# only succeeds from an interactive/granted context — which is exactly when
# --install-agent is run. Best-effort: never fail the sync over it.
ensure_link() {
  [[ -d "$VAULT" ]] || { echo "note: vault not found at '$VAULT' — skipping symlink." >&2; return 0; }
  # Replace a pre-existing real directory (e.g. from an earlier copy mirror).
  if [[ -e "$LINK" && ! -L "$LINK" ]]; then
    rm -rf "$LINK"
  fi
  if [[ ! -L "$LINK" ]]; then
    ln -s "$TARGET" "$LINK" && echo "Linked vault → mirror: $LINK"
  fi
}

install_agent() {
  local interval="${1:-3600}"
  mkdir -p "$TARGET" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  ensure_link || true
  run_sync   # seed the mirror immediately

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

  # Reload cleanly if it was already installed.
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Installed launchd agent: $LABEL (every ${interval}s)"
  echo "  plist: $PLIST"
  echo "  log:   $LOG"
}

uninstall_agent() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed launchd agent: $LABEL"
}

run_sync() {
  cd "$SRC"

  # Rebuild the mirror from scratch so deletes/renames stay in sync.
  rm -rf "$TARGET"
  mkdir -p "$TARGET"

  # Only tracked .md files in the outer repo (skips node_modules/.build/.venv
  # and the nested standalone repos). -z/-0 handles paths with spaces safely.
  git ls-files -z '*.md' | rsync -0 -a --files-from=- "$SRC/" "$TARGET/"

  local count
  count=$(git ls-files '*.md' | wc -l | tr -d ' ')
  echo "$(date '+%Y-%m-%d %H:%M:%S')  Mirrored $count markdown files → $TARGET"
}

case "${1:-}" in
  --install-agent)   install_agent "${2:-}";;
  --uninstall-agent) uninstall_agent;;
  "")                run_sync;;
  *) echo "usage: $0 [--install-agent [interval_seconds] | --uninstall-agent]" >&2; exit 2;;
esac
