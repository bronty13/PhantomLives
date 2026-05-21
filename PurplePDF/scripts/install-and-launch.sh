#!/usr/bin/env bash
# Build, install to /Applications, and launch Purple PDF.
# Builds for the host architecture only (fast iteration).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="Purple PDF"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="/Applications"

echo "==> Building renderer/main/preload"
npm run build

echo "==> Packaging .app (host arch, no dmg, no sign)"
# --dir produces an unpacked .app without a .dmg / signing dance
npx electron-builder --mac --dir --config.mac.identity=null --config.mac.target=dir

# electron-builder writes mac (arm64 -> mac-arm64, x64 -> mac)
SRC_APP=""
for d in "dist/mac-arm64" "dist/mac" "dist/mac-x64" "dist/mac-universal"; do
  if [[ -d "$ROOT/$d/$APP_BUNDLE" ]]; then
    SRC_APP="$ROOT/$d/$APP_BUNDLE"
    break
  fi
done
if [[ -z "$SRC_APP" ]]; then
  echo "ERROR: built .app not found under dist/" >&2
  ls -la dist/ || true
  exit 1
fi
echo "    built: $SRC_APP"

echo "==> Installing to $INSTALL_DIR"
# Quit any running instance first so the rsync/replace succeeds
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
sleep 1

DEST="$INSTALL_DIR/$APP_BUNDLE"
if [[ -d "$DEST" ]]; then
  if ! rm -rf "$DEST" 2>/dev/null; then
    echo "    (need sudo to replace existing $DEST)"
    sudo rm -rf "$DEST"
  fi
fi
if ! cp -R "$SRC_APP" "$DEST" 2>/dev/null; then
  echo "    (need sudo to copy into $INSTALL_DIR)"
  sudo cp -R "$SRC_APP" "$DEST"
fi
# Strip Gatekeeper quarantine so it launches cleanly when ad-hoc signed
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching"
open "$DEST"

echo "==> Done. Installed at $DEST"
