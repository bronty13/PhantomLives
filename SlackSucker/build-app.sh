#!/bin/bash
# Builds SlackSucker.app from the Swift Package. Bundles `slackdump` into
# Resources/ so end users don't need a separate install. The `.app` form
# is required because SwiftUI WindowGroup, LSUIElement, and TCC grants
# all key off the bundle.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

# Version strings derived from git so every build after a commit is uniquely
# identifiable. Override either by exporting SHORT_VERSION / BUILD_NUMBER.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

# Pre-build cleanup of " N.app" siblings iCloud File Provider may have
# spawned. Same pattern as messages-exporter-gui / PurpleIRC.
shopt -s nullglob 2>/dev/null || true
for dup in SlackSucker\ [0-9]*.app "SlackSucker 2.app" \
           "SlackSucker 3.app" "SlackSucker 4.app"; do
    if [ -d "$dup" ]; then
        echo "Pre-build cleanup: removing $dup"
        rm -rf "$dup"
    fi
done

echo "Building (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Resolve the slackdump binary to bundle. Honor an explicit override, then
# fall back to whatever `which slackdump` finds. Bailing out here is the
# right behavior — without slackdump the .app has nothing to drive.
SLACKDUMP_BIN="${SLACKDUMP_BIN:-$(command -v slackdump 2>/dev/null || true)}"
if [ -z "${SLACKDUMP_BIN:-}" ] || [ ! -x "$SLACKDUMP_BIN" ]; then
    echo "error: slackdump binary not found." >&2
    echo "       Install it (\`brew install slackdump\`) or set SLACKDUMP_BIN=/path/to/slackdump." >&2
    exit 1
fi
echo "Bundling slackdump: $SLACKDUMP_BIN"

# Build + sign in /tmp to avoid iCloud File Provider xattr races. See
# messages-exporter-gui/build-app.sh for the full rationale.
WORK_DIR="$(mktemp -d -t slacksucker-build)"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_DIR="$WORK_DIR/SlackSucker.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/SlackSucker" "$MACOS/SlackSucker"
cp "$SLACKDUMP_BIN" "$RESOURCES/slackdump"
chmod +x "$RESOURCES/slackdump"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SlackSucker</string>
    <key>CFBundleDisplayName</key><string>SlackSucker</string>
    <key>CFBundleIdentifier</key><string>com.bronty13.SlackSucker</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>SlackSucker</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -c  "$APP_DIR" 2>/dev/null || true

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Robert Olen (SRKV8T38CD)}"

# Sign the bundled slackdump FIRST so its signature is sealed into the
# outer bundle's content hash. Re-signing here strips Homebrew's ad-hoc
# signature and re-attaches one in our identity so the same TCC entry
# covers both the host app and the helper.
if [ "$DEVELOPER_ID" != "-" ] && \
   security find-identity -p codesigning -v 2>/dev/null \
        | grep -q "$DEVELOPER_ID"; then
    echo "Signing with Developer ID: $DEVELOPER_ID"
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID" "$RESOURCES/slackdump"
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
    codesign --force --sign - "$RESOURCES/slackdump" 2>/dev/null || true
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
fi

shopt -s nullglob 2>/dev/null || true
for dup in SlackSucker\ [0-9]*.app; do
    if [ -d "$dup" ]; then
        echo "Removing duplicate bundle: $dup"
        rm -rf "$dup"
    fi
done

FINAL_APP_DIR="SlackSucker.app"
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
