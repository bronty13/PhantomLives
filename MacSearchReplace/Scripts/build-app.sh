#!/usr/bin/env bash
#
# build-app.sh — build the SwiftPM executable and wrap it as a proper
# macOS .app bundle with Info.plist + bundled ripgrep, then ad-hoc codesign.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="MacSearchReplace"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG" --product "$APP_NAME"
swift build -c "$CONFIG" --product snr

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

echo "→ Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Apps/MacSearchReplace/SupportFiles/Info.plist" "$CONTENTS/Info.plist"

# Bundle the vendored ripgrep
if [[ -x "$ROOT/Apps/MacSearchReplace/Vendored/rg" ]]; then
    cp "$ROOT/Apps/MacSearchReplace/Vendored/rg" "$CONTENTS/MacOS/rg"
    chmod +x "$CONTENTS/MacOS/rg"
else
    echo "⚠ Vendored/rg not found — run Scripts/fetch-ripgrep.sh first"
fi

# Bundle the snr CLI alongside (for users who want to install it separately)
cp "$BIN_PATH/snr" "$CONTENTS/MacOS/snr"

echo "→ Ad-hoc codesigning"
codesign --force --deep --sign - "$APP_DIR"

echo "✓ Built $APP_DIR"
echo
echo "Run with:  open '$APP_DIR'"
echo "Quarantine clear:  xattr -dr com.apple.quarantine '$APP_DIR'"
