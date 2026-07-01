#!/bin/bash
# Builds PurplePeek.app from the Swift package (SwiftUI WindowGroup needs a real bundle /
# Info.plist to activate its UI), signs it with the Photos entitlements, and — unless opted
# out — installs it to /Applications and relaunches. Modeled on PurpleAttic/build-app.sh,
# minus the bundled CLI and Sparkle.
#
# Usage: ./build-app.sh                # build + install + relaunch
#        ./build-app.sh --no-install   # build only, leave /Applications alone
#        ./build-app.sh --no-open      # build + install, don't relaunch
#        BUILD_ONLY=1 ./build-app.sh   # same as --no-install
#        CONFIG=debug ./build-app.sh   # debug build
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building PurplePeek (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
if ! swift build -c "$CONFIG" --product PurplePeek; then
    echo "FATAL: PurplePeek build failed — aborting before bundling stale code." >&2; exit 1
fi

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

FINAL_APP_DIR="PurplePeek.app"
WORK_DIR="$(mktemp -d -t purplepeek-build)"
APP_DIR="$WORK_DIR/PurplePeek.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/PurplePeek" "$MACOS/PurplePeek"

# App icon — regenerate deterministically every build.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PurplePeek</string>
    <key>CFBundleDisplayName</key><string>PurplePeek</string>
    <key>CFBundleIdentifier</key><string>com.bronty13.PurplePeek</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PurplePeek</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>PurplePeek. Personal use.</string>
    <key>NSPhotoLibraryUsageDescription</key><string>PurplePeek reads your Photos library to mirror your existing albums and keywords while you triage media on disk.</string>
    <key>NSPhotoLibraryAddUsageDescription</key><string>PurplePeek imports the photos and videos you choose to keep into your Photos library.</string>
</dict>
</plist>
PLIST

# Belt-and-braces: ensure CFBundleIconFile is present (set-or-add; a bare Set silently
# no-ops when the key is absent — the PurpleArchive no-icon incident).
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist"

# Codesign identity: Developer ID if available, else ad-hoc.
detect_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then echo "$CODESIGN_IDENTITY"; return; fi
    # Over SSH, adhoc-sign by default: Developer ID codesign needs the login keychain (unreachable
    # over ssh → errSecInternalComponent), which would break remote build-app.sh. Adhoc needs no
    # keychain and is fine for dev/local installs (Dev-ID+notarize is release-only). FORCE_DEVID=1 overrides.
    if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${FORCE_DEVID:-}" ]; then echo "-"; return; fi
    local devid
    devid=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"Developer ID Application:' | head -1 \
        | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
    [ -n "$devid" ] && echo "$devid" || echo "-"
}
CODESIGN_ID="$(detect_codesign_identity)"

# Strip xattrs codesign refuses.
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

ENTITLEMENTS_FILE="$(pwd)/PurplePeek.entitlements"
ENTITLEMENTS_FLAGS=()
if [ -f "$ENTITLEMENTS_FILE" ]; then
    ENTITLEMENTS_FLAGS=(--entitlements "$ENTITLEMENTS_FILE")
    echo "Using entitlements: $ENTITLEMENTS_FILE"
else
    echo "WARNING: entitlements file not found — Photos access will fail on macOS 14+."
fi

if [ "$CODESIGN_ID" = "-" ]; then
    echo "Signing ad-hoc (no Developer ID Application cert found)..."
    codesign --force --sign - "${ENTITLEMENTS_FLAGS[@]}" "$APP_DIR" 2>/dev/null || true
else
    echo "Signing with: $CODESIGN_ID"
    codesign --force --sign "$CODESIGN_ID" --options runtime --timestamp \
             "${ENTITLEMENTS_FLAGS[@]}" "$APP_DIR"
    if codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>/tmp/codesign-verify.log; then
        echo "Signature verified."
    else
        echo "WARNING: codesign verification failed:"; cat /tmp/codesign-verify.log
    fi
fi

rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"
rm -rf "$WORK_DIR"

echo "Built $FINAL_APP_DIR"

# Auto-install + relaunch (PhantomLives standard). Opt out with --no-install / BUILD_ONLY=1.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    INSTALL_SH="$(dirname "$0")/install.sh"
    if [ -x "$INSTALL_SH" ]; then
        echo ""; "$INSTALL_SH" $INSTALL_FLAGS
    fi
fi
