#!/bin/bash
# Builds PurpleSpeak.app from the Swift Package, then installs + relaunches
# via install.sh (PhantomLives install.sh standard). The .app form is required
# because SwiftUI WindowGroup + TCC grants + Launch Services all key off the
# bundle.
#
# Bundles `whisper-cli` (whisper.cpp) into Contents/Resources when it's
# available, so on-device transcription works out of the box. Without it the
# app still builds and runs; the Transcribe panel then guides the user to
# `brew install whisper-cpp` and rebuild.
#
# Opt-outs: --no-install (just build), --no-open (install without relaunch),
# BUILD_ONLY=1 (build only).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="PurpleSpeak"
BUNDLE_ID="com.bronty13.PurpleSpeak"

# Version strings derived from git so every build after a commit is uniquely
# identifiable. Override by exporting SHORT_VERSION / BUILD_NUMBER.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

# If xcode-select points at Command Line Tools but full Xcode exists, use it
# (swift build for a SwiftUI app needs the macOS SDK from Xcode).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

# Pre-build cleanup of " N.app" siblings iCloud File Provider may spawn.
shopt -s nullglob 2>/dev/null || true
for dup in "$APP "[0-9]*.app; do
    [ -d "$dup" ] && { echo "Pre-build cleanup: removing $dup"; rm -rf "$dup"; }
done

echo "Building $APP $SHORT_VERSION ($BUILD_NUMBER), config=$CONFIG..."
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Resolve whisper-cli to bundle (optional). Honor an explicit override, then
# fall back to PATH. whisper-cpp installs the binary as `whisper-cli`.
WHISPER_BIN="${WHISPER_BIN:-$(command -v whisper-cli 2>/dev/null || true)}"

# Assemble + sign in /tmp to avoid iCloud xattr races, then ditto back.
WORK_DIR="$(mktemp -d -t purplespeak-build)"
trap 'rm -rf "$WORK_DIR"' EXIT
APP_DIR="$WORK_DIR/$APP.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/$APP" "$MACOS/$APP"

if [ -n "${WHISPER_BIN:-}" ] && [ -x "$WHISPER_BIN" ]; then
    echo "Bundling whisper-cli: $WHISPER_BIN"
    cp "$WHISPER_BIN" "$RESOURCES/whisper-cli"
    chmod +x "$RESOURCES/whisper-cli"
    # whisper.cpp links against libwhisper/libggml dylibs (Homebrew) — copy
    # them in beside the binary and fix the rpath so the bundle is portable.
    WLIBDIR="$(dirname "$WHISPER_BIN")/../lib"
    if [ -d "$WLIBDIR" ]; then
        for dylib in "$WLIBDIR"/libwhisper*.dylib "$WLIBDIR"/libggml*.dylib; do
            [ -f "$dylib" ] && cp "$dylib" "$RESOURCES/" 2>/dev/null || true
        done
        install_name_tool -add_rpath "@executable_path" "$RESOURCES/whisper-cli" 2>/dev/null || true
    fi
else
    echo "note: whisper-cli not found — building without bundled transcription."
    echo "      Install it (brew install whisper-cpp) and rebuild to enable STT."
fi

# Icon: regenerate each build (deterministic).
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"
cp "$RESOURCES/AppIcon.icns" "Resources/AppIcon.icns" 2>/dev/null || true

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key><string>PurpleSpeak can transcribe recordings you choose; microphone access is only needed if you enable live dictation.</string>
</dict>
</plist>
PLIST

# Strip xattrs codesign refuses on, then sign.
xattr -cr "$APP_DIR" 2>/dev/null || true

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Robert Olen (SRKV8T38CD)}"
ENTITLEMENTS="Sources/PurpleSpeak/App/PurpleSpeak.entitlements"

sign_one() {
    local target="$1"
    if [ "$DEVELOPER_ID" != "-" ] && \
       security find-identity -p codesigning -v 2>/dev/null | grep -q "$DEVELOPER_ID"; then
        codesign --force --options runtime --timestamp \
                 --entitlements "$ENTITLEMENTS" \
                 --sign "$DEVELOPER_ID" "$target"
    else
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$target" 2>/dev/null || \
        codesign --force --sign - "$target" 2>/dev/null || true
    fi
}

# Sign bundled helpers FIRST (inside-out) so their signatures seal into the
# outer bundle's content hash.
if [ -f "$RESOURCES/whisper-cli" ]; then
    for dylib in "$RESOURCES"/*.dylib; do [ -f "$dylib" ] && sign_one "$dylib"; done
    sign_one "$RESOURCES/whisper-cli"
fi
sign_one "$APP_DIR"

if codesign --verify --strict --verbose=2 "$APP_DIR" >/dev/null 2>&1; then
    echo "✓ Signature verified"
else
    echo "⚠️  codesign --verify reported issues (ad-hoc build is fine for local use)"
fi

FINAL_APP_DIR="$APP.app"
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"

echo "Built $FINAL_APP_DIR"

# Auto-install + relaunch unless opted out.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    INSTALL_SH="$(dirname "$0")/install.sh"
    if [ -x "$INSTALL_SH" ]; then
        echo ""
        "$INSTALL_SH" $INSTALL_FLAGS
    fi
fi
