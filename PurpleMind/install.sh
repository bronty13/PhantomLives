#!/usr/bin/env bash
# install.sh — Mac side of the PhantomLives install convention.
# Replaces /Applications/PurpleMind.app with the freshly-built bundle and
# relaunches it so TCC entitlements stay anchored to a stable cdhash.
#
# Usage:
#   ./install.sh            # quit + replace + relaunch
#   ./install.sh --no-open  # quit + replace, but do not relaunch

set -euo pipefail

NO_OPEN=0
for arg in "$@"; do
  case "$arg" in
    --no-open) NO_OPEN=1 ;;
    *) ;;
  esac
done

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_APP="$PROJECT_DIR/src-tauri/target/release/bundle/macos/PurpleMind.app"
INSTALL_PATH="/Applications/PurpleMind.app"

if [ ! -d "$LOCAL_APP" ]; then
  echo "❌ No build found at $LOCAL_APP"
  echo "   Run ./build-app.sh first."
  exit 1
fi

# 1. Quit running copy so /Applications/ is free to overwrite.
osascript -e 'tell application "PurpleMind" to quit' >/dev/null 2>&1 || true
sleep 1

# 2. Replace.
if [ -d "$INSTALL_PATH" ]; then
  rm -rf "$INSTALL_PATH"
fi
# `ditto --noextattr` strips File Provider xattrs that break codesign
# when the project lives under iCloud-synced ~/Documents.
ditto --noextattr "$LOCAL_APP" "$INSTALL_PATH"

# 3. Relaunch (unless suppressed).
if [ "$NO_OPEN" -eq 0 ]; then
  open "$INSTALL_PATH"
fi

echo "✅ PurpleMind installed to $INSTALL_PATH"
