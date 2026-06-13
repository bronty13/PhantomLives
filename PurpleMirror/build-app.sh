#!/bin/bash
# Builds PurpleMirror.app from the Swift Package, generates the icon from code,
# signs, and (by default) installs to /Applications + relaunches via install.sh.
# Opt out with --no-install / --no-open, or BUILD_ONLY=1.
#
# PurpleMirror is a menu-bar (LSUIElement) companion for sync-md-to-obsidian.sh.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

# Pre-build cleanup of " N.app" siblings iCloud File Provider may spawn.
shopt -s nullglob 2>/dev/null || true
for dup in PurpleMirror\ [0-9]*.app; do
    [ -d "$dup" ] && { echo "Pre-build cleanup: removing $dup"; rm -rf "$dup"; }
done

echo "Building PurpleMirror (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

WORK_DIR="$(mktemp -d -t purplemirror-build)"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_DIR="$WORK_DIR/PurpleMirror.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/PurpleMirror" "$MACOS/PurpleMirror"

# --- Icon: generate deterministically from code (no binary source of truth) ---
ICONSET="$WORK_DIR/AppIcon.iconset"
if swift Scripts/generate-icon.swift "$ICONSET" >/dev/null 2>&1 && [ -d "$ICONSET" ]; then
    if iconutil -c icns -o "$RESOURCES/AppIcon.icns" "$ICONSET" 2>/dev/null; then
        echo "Generated AppIcon.icns from Scripts/generate-icon.swift"
    else
        echo "warning: iconutil failed — bundle will use the generic icon" >&2
    fi
else
    echo "warning: icon generation failed — bundle will use the generic icon" >&2
fi

# --- Info.plist (LSUIElement = menu-bar-only, no Dock icon) ---
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PurpleMirror</string>
    <key>CFBundleDisplayName</key><string>PurpleMirror</string>
    <key>CFBundleIdentifier</key><string>com.bronty13.PurpleMirror</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PurpleMirror</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Robert Olen (SRKV8T38CD)}"
if [ "$DEVELOPER_ID" != "-" ] && \
   security find-identity -p codesigning -v 2>/dev/null | grep -q "$DEVELOPER_ID"; then
    echo "Signing with Developer ID: $DEVELOPER_ID"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_DIR"
    if codesign --verify --strict --verbose=2 "$APP_DIR" >/dev/null 2>&1; then
        echo "✓ Signature verified"
    else
        echo "⚠️  codesign --verify reported issues — see output above"
    fi
else
    echo "Developer ID '$DEVELOPER_ID' not in keychain — ad-hoc signing"
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
fi

FINAL_APP_DIR="PurpleMirror.app"
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"

xattr -w com.apple.metadata:com_apple_backup_excludeItem 'com.apple.backupd' "$FINAL_APP_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$FINAL_APP_DIR" 2>/dev/null || true

LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister'
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$FINAL_APP_DIR" >/dev/null 2>&1 || true

echo "Built $FINAL_APP_DIR"

if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    [[ " $* " =~ " --no-open " ]] && INSTALL_FLAGS="--no-open"
    INSTALL_SH="$(dirname "$0")/install.sh"
    [ -x "$INSTALL_SH" ] && { echo ""; "$INSTALL_SH" $INSTALL_FLAGS; }
fi
