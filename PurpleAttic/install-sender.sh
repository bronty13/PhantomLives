#!/usr/bin/env bash
#
# install-sender.sh — set up PurpleAttic SENDER mode on a *source* Mac (e.g. a small-disk
# second Mac on a different iCloud account). The sender exports this Mac's Photos to an
# external SSD and rsyncs them over SSH to a PurpleAttic receiver ("Vortex"). It is
# export-only and NEVER purges.
#
# What it does:
#   1. Ensures osxphotos + exiftool are present (offers to install).
#   2. Builds the `pattic` CLI (release) and installs it to ~/.local/bin/pattic.
#   3. Writes a starter ~/Library/Application Support/PurpleAttic/sender.json (you then edit).
#   4. Generates an SSH key for unattended rsync and prints how to authorize it on the receiver.
#   5. (optional) Installs a launchd agent that runs `pattic agent run` on an interval.
#
# Usage:
#   ./install-sender.sh                         # build + install pattic, scaffold config + key
#   ./install-sender.sh --install-agent [secs]  # also load the hourly launchd agent (default 3600)
#   ./install-sender.sh --uninstall-agent       # remove the launchd agent
#
# This script is intentionally separate from the core build-app.sh / install.sh — it touches
# none of the receiver-side archive/purge machinery.
set -euo pipefail

LABEL="com.bronty13.purpleattic-sender"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
BIN_DIR="$HOME/.local/bin"
PATTIC="$BIN_DIR/pattic"
CONFIG="$HOME/Library/Application Support/PurpleAttic/sender.json"
LOG_DIR="$HOME/Library/Logs/PurpleAttic"
SSH_KEY="$HOME/.ssh/purpleattic_sender"
INTERVAL="${2:-3600}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1;35m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

uninstall_agent() {
  if [[ -f "$PLIST" ]]; then
    launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    ok "Removed launchd agent ($LABEL)."
  else
    warn "No launchd agent installed."
  fi
}

if [[ "${1:-}" == "--uninstall-agent" ]]; then
  uninstall_agent; exit 0
fi

# 1. Toolchain ---------------------------------------------------------------
say "1. Checking toolchain (osxphotos, exiftool)…"
if ! command -v osxphotos >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/osxphotos" ]]; then
  warn "osxphotos not found."
  read -r -p "    Install it now via pipx? [y/N] " a
  if [[ "$a" =~ ^[Yy]$ ]]; then
    command -v pipx >/dev/null 2>&1 || brew install pipx
    pipx install osxphotos
  else
    warn "Skipping — install later with: pipx install osxphotos"
  fi
else ok "osxphotos present."; fi

if ! command -v exiftool >/dev/null 2>&1; then
  warn "exiftool not found."
  read -r -p "    Install it now via Homebrew? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] && brew install exiftool || warn "Skipping — install later with: brew install exiftool"
else ok "exiftool present."; fi

# 2. Build + install pattic --------------------------------------------------
say "2. Building pattic (release)…"
( cd "$SCRIPT_DIR" && swift build -c release --product pattic )
mkdir -p "$BIN_DIR"
cp -f "$(cd "$SCRIPT_DIR" && swift build -c release --show-bin-path)/pattic" "$PATTIC"
ok "Installed pattic → $PATTIC"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "Add $BIN_DIR to your PATH (e.g. in ~/.zshrc)."; esac

# 3. Scaffold config ---------------------------------------------------------
say "3. Sender config…"
if [[ -f "$CONFIG" ]]; then
  ok "Config already exists: $CONFIG (leaving it alone)."
else
  "$PATTIC" agent init >/dev/null
  ok "Wrote starter config: $CONFIG"
  warn "EDIT IT before first run: set stagingRoot (your SSD), remote.host/user/remotePath, and enable remote."
fi

# 4. SSH key for unattended rsync -------------------------------------------
say "4. SSH key for the receiver…"
if [[ -f "$SSH_KEY" ]]; then
  ok "Key already exists: $SSH_KEY"
else
  ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "purpleattic-sender@$(hostname -s)" >/dev/null
  ok "Generated $SSH_KEY"
fi
echo "    Authorize it on the receiver (Vortex) — run on THIS Mac once you know the receiver's user@host:"
echo "      ssh-copy-id -i \"$SSH_KEY.pub\" <user>@<vortex-host>"
echo "    …then set \"identityFile\": \"$SSH_KEY\" in $CONFIG"

# 5. Optional launchd agent --------------------------------------------------
if [[ "${1:-}" == "--install-agent" ]]; then
  say "5. Installing launchd agent (every ${INTERVAL}s)…"
  mkdir -p "$LOG_DIR" "$(dirname "$PLIST")"
  # PATH carries Homebrew + pipx bin dirs so osxphotos/exiftool resolve under launchd.
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>${PATTIC}</string><string>agent</string><string>run</string></array>
  <key>StartInterval</key><integer>${INTERVAL}</integer>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>${HOME}</string>
    <key>PATH</key><string>${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>StandardOutPath</key><string>${LOG_DIR}/sender.out.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/sender.err.log</string>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
PLISTEOF
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  ok "Loaded $LABEL (runs every ${INTERVAL}s; logs in $LOG_DIR)."
else
  say "5. launchd agent: skipped (re-run with --install-agent [seconds] to schedule)."
fi

cat <<NEXT

$(say "Next steps on this (sender) Mac:")
  • Attach the external SSD and (recommended) MOVE the Photos library onto it +
    set Photos → Settings → iCloud → "Download Originals to this Mac". That frees the
    internal drive and lets every original export with no iCloud-download dance.
  • Grant Full Disk Access to:  $PATTIC
      System Settings → Privacy & Security → Full Disk Access
  • Edit $CONFIG  (stagingRoot, remote.*).
  • Authorize the SSH key on the receiver (see step 4).
  • Dry-run first:   pattic agent plan      &&   pattic agent run --dry-run
  • Full backup:     pattic agent run        (first run = everything; later runs = new only)
  • Schedule it:     ./install-sender.sh --install-agent 3600
NEXT
