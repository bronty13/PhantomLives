#!/bin/bash
# harvest_favorites.sh — copy newly-Favorited (♥) Apple Music tracks into
# "My Picks [PL]" (idempotent), via AppleScript. Local-only: no API token, no
# rate limits. Designed for a launchd agent surfaced in PurpleMirror's "Bots".
#
#   ./harvest_favorites.sh                 # single harvest pass (what launchd runs)
#   ./harvest_favorites.sh --install-agent [interval_secs]   # install hourly launchd agent
#   ./harvest_favorites.sh --uninstall-agent
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/harvest_favorites.applescript"
LABEL="com.bronty13.harvest-favorites"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="${HARVEST_LOG_DIR:-$HOME/Library/Logs/PhantomLives}"
LOG="$LOG_DIR/harvest-favorites.log"
ts() { date "+%Y-%m-%d %H:%M:%S"; }

install_agent() {
  local interval="${1:-3600}"
  mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$HERE/harvest_favorites.sh</string></array>
  <key>StartInterval</key><integer>$interval</integer>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$LOG_DIR/harvest-favorites.launchd.out.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/harvest-favorites.launchd.err.log</string>
</dict>
</plist>
PLIST_EOF
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "Installed agent $LABEL (every ${interval}s)."
}

uninstall_agent() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  rm -f "$PLIST" && echo "Uninstalled agent $LABEL."
}

case "${1:-}" in
  --install-agent)   install_agent "${2:-3600}"; exit $? ;;
  --uninstall-agent) uninstall_agent; exit $? ;;
esac

# --- single harvest pass ---
mkdir -p "$LOG_DIR"
if ! pgrep -xq Music; then
  echo "$(ts) SKIP: Music.app not running" >> "$LOG"
  exit 0
fi
result="$(osascript "$SCRIPT" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [[ "$result" == OK* ]]; then
  echo "$(ts) $result" >> "$LOG"; exit 0
else
  echo "$(ts) FAIL rc=$rc: $result" >> "$LOG"; exit 1
fi
