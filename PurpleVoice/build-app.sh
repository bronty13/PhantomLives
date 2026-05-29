#!/bin/bash
# Builds PurpleVoice.app from the Swift Package. Plain SwiftPM, no
# bundled binaries — ffmpeg is a runtime dependency the user installs
# via Homebrew. The .app form is required so SwiftUI WindowGroup,
# TCC grants, Spotlight, and Cmd+Tab all key off a stable bundle path
# in /Applications/.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-0.4.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

# Pre-build cleanup of " N.app" siblings iCloud File Provider may have
# spawned. Same pattern as SlackSucker / PurpleIRC.
shopt -s nullglob 2>/dev/null || true
for dup in PurpleVoice\ [0-9]*.app "PurpleVoice 2.app" \
           "PurpleVoice 3.app" "PurpleVoice 4.app"; do
    if [ -d "$dup" ]; then
        echo "Pre-build cleanup: removing $dup"
        rm -rf "$dup"
    fi
done

echo "Building (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Stage the bundle in /tmp to avoid iCloud File Provider xattr races on
# /Users/.../Documents/... — see CLAUDE.md "Cross-Mac dev setup".
WORK_DIR="$(mktemp -d -t purplevoice-build)"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_DIR="$WORK_DIR/PurpleVoice.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/PurpleVoice" "$MACOS/PurpleVoice"

# Optional AppIcon.icns — generated separately, checked in once it
# exists. Until then the .app gets the generic Swift icon (harmless).
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PurpleVoice</string>
    <key>CFBundleDisplayName</key><string>PurpleVoice</string>
    <key>CFBundleIdentifier</key><string>com.bronty13.PurpleVoice</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PurpleVoice</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Audio or Video</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>public.movie</string>
            </array>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -c  "$APP_DIR" 2>/dev/null || true

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Robert Olen (SRKV8T38CD)}"

if [ "$DEVELOPER_ID" != "-" ] && \
   security find-identity -p codesigning -v 2>/dev/null \
        | grep -q "$DEVELOPER_ID"; then
    echo "Signing with Developer ID: $DEVELOPER_ID"
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID" "$APP_DIR"
    if codesign --verify --strict --verbose=2 "$APP_DIR" >/dev/null 2>&1; then
        TEAM_ID=$(codesign -dv "$APP_DIR" 2>&1 | sed -n 's/^TeamIdentifier=//p')
        echo "✓ Signature verified (TeamIdentifier=${TEAM_ID:-unknown})"
    else
        echo "⚠️  codesign --verify reported issues — see output above"
    fi
else
    echo "Developer ID '$DEVELOPER_ID' not in keychain — ad-hoc signing"
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
fi

shopt -s nullglob 2>/dev/null || true
for dup in PurpleVoice\ [0-9]*.app; do
    if [ -d "$dup" ]; then
        echo "Removing duplicate bundle: $dup"
        rm -rf "$dup"
    fi
done

FINAL_APP_DIR="PurpleVoice.app"
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"

xattr -w com.apple.metadata:com_apple_backup_excludeItem 'com.apple.backupd' "$FINAL_APP_DIR" 2>/dev/null || true
xattr -w com.apple.fileprovider.ignore '1' "$FINAL_APP_DIR" 2>/dev/null || true
xattr -d com.apple.fileprovider.fpfs#P "$FINAL_APP_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$FINAL_APP_DIR" 2>/dev/null || true

LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister'
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$FINAL_APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built $FINAL_APP_DIR"
echo "Run with:  open $FINAL_APP_DIR"

# Auto-install: replace /Applications/PurpleVoice.app and relaunch.
# Opt out with `--no-install` or `--no-open`. Per the PhantomLives
# install.sh standard in CLAUDE.md.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    INSTALL_SH="$(dirname "$0")/install.sh"
    if [ -x "$INSTALL_SH" ]; then
        echo ""
        "$INSTALL_SH" $INSTALL_FLAGS
    fi
fi
