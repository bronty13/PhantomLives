#!/bin/bash
#
# install-agent.sh — run PeekServer headless as a launchd LaunchAgent.
#
# PeekServer is a long-running server (not a periodic job), so the agent uses
# KeepAlive + RunAtLoad (relaunch on crash / at login) — NOT StartInterval.
# This is the "Phase 3: deploy to airy" piece from README.md: keep the review
# service up unattended on the runner that has the media attached.
#
# USAGE
#   ./install-agent.sh --install-agent      # write the plist + (re)bootstrap it
#   ./install-agent.sh --uninstall-agent    # bootout + remove the plist
#   ./install-agent.sh --status             # show launchd state + log tail hint
#   ./install-agent.sh --print-plist        # print the plist to stdout, do nothing else
#
# The plist points launchd at run.sh. Two headless gotchas it handles:
#   • PATH — launchd gives a minimal PATH (/usr/bin:/bin:…), so Homebrew ffmpeg
#     (video proxies) wouldn't be found. The agent exports a PATH that includes
#     /opt/homebrew/bin + /usr/local/bin so ffmpeg resolves (falls back to serving
#     originals if ffmpeg is genuinely absent).
#   • TCC — reading review folders on an external/again-protected volume needs
#     Full Disk Access on the launchd-spawned interpreter; --install-agent prints
#     the grant steps (same class of grant PurpleAttic + the obsidian agent need).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_SH="$DIR/run.sh"

LABEL="com.phantomlives.peekserver"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/phantomlives-peekserver.log"

# launchd's minimal PATH can't see Homebrew; prepend the usual brew prefixes so
# ffmpeg (and any brew-installed python3) resolve for video proxies.
AGENT_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Emit the LaunchAgent plist to stdout. Pure string generation — no side effects,
# so --print-plist can be inspected / unit-tested on any platform.
emit_plist() {
  cat <<PLIST_EOF
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
        <string>$RUN_SH</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$AGENT_PATH</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST_EOF
}

install_agent() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  [ -x "$RUN_SH" ] || { echo "error: $RUN_SH not found/executable" >&2; exit 1; }
  emit_plist > "$PLIST"

  # bootout any prior instance first, then bootstrap (idempotent re-install).
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"

  local port; port="$(grep -Eo '"port"[[:space:]]*:[[:space:]]*[0-9]+' "$DIR/config.json" 2>/dev/null | grep -Eo '[0-9]+' || echo 8788)"
  echo "Installed launchd agent: $LABEL"
  echo "  plist: $PLIST"
  echo "  log:   $LOG"
  echo "  URL:   http://$(hostname -s 2>/dev/null || echo localhost).local:${port}/  (open from any Mac/iPad)"
  echo
  echo "NOTE (Full Disk Access): if PeekServer serves folders on an external or"
  echo "TCC-protected volume, grant FDA to the interpreter the agent runs as"
  echo "(/bin/bash): System Settings ▸ Privacy & Security ▸ Full Disk Access ▸ +"
  echo "▸ ⇧⌘G ▸ /bin ▸ select 'bash' ▸ enable — then re-run --install-agent."
  echo "NOTE (video proxies): 'brew install ffmpeg' for smooth playback; without it"
  echo "PeekServer serves originals (no proxy). The agent's PATH already includes brew."
  echo "NOTE (reboot-safe): if roots live on an external drive, eject-externals.sh"
  echo "boots this agent out before unmounting so the eject can't be blocked."
}

uninstall_agent() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed launchd agent: $LABEL"
}

status() {
  if launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -E "state =|pid =" ; then
    echo "  (agent loaded) — log: tail -f \"$LOG\""
  else
    echo "$LABEL is not loaded. Install with: $0 --install-agent"
  fi
}

case "${1:-}" in
  --install-agent)   install_agent;;
  --uninstall-agent) uninstall_agent;;
  --status)          status;;
  --print-plist)     emit_plist;;
  *) echo "usage: $0 [--install-agent | --uninstall-agent | --status | --print-plist]" >&2; exit 2;;
esac
