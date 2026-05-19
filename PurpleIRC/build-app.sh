#!/bin/bash
# Builds PurpleIRC.app bundle from the Swift Package so the app activates its UI
# (WindowGroup requires a proper bundle / Info.plist on macOS).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

# Version strings are derived from git so every build after a commit is
# uniquely identifiable. The user-facing version is "1.0.<commit-count>";
# the build number carries the short SHA for diagnostic grepping. Override
# either by exporting SHORT_VERSION / BUILD_NUMBER before invoking.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Build the .app bundle in a tmp directory OUTSIDE iCloud Drive's reach.
# PhantomLives lives under ~/Documents which is iCloud-synced; iCloud
# Drive re-attaches `com.apple.FinderInfo` to fresh files at arbitrary
# moments, and codesign --strict (required for notarisation) refuses to
# sign or verify any bundle carrying that xattr. Doing the assembly +
# sign + verify in /tmp sidesteps the race entirely; we then `ditto
# --noextattr` the finished bundle back into the project directory.
FINAL_APP_DIR="PurpleIRC.app"
WORK_DIR="$(mktemp -d -t purpleirc-build)"
APP_DIR="$WORK_DIR/PurpleIRC.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/PurpleIRC" "$MACOS/PurpleIRC"

# App icon: regenerate the .iconset each build (the generator is deterministic,
# so this is fine) and let iconutil roll it into AppIcon.icns.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

# AppleScript dictionary. The .sdef declares verbs the OS will route via
# Apple Events to NSScriptCommand subclasses (see AppleScriptCommands.swift).
# Combined with NSAppleScriptEnabled + OSAScriptingDefinition in Info.plist,
# this is what makes Script Editor's "Open Dictionary…" find PurpleIRC.
if [ -f "Resources/PurpleIRC.sdef" ]; then
    cp "Resources/PurpleIRC.sdef" "$RESOURCES/PurpleIRC.sdef"
fi

# HEREDOC without quoted tag so $SHORT_VERSION / $BUILD_NUMBER expand.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PurpleIRC</string>
    <key>CFBundleDisplayName</key><string>PurpleIRC</string>
    <key>CFBundleIdentifier</key><string>com.example.PurpleIRC</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PurpleIRC</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleScriptEnabled</key><true/>
    <key>OSAScriptingDefinition</key><string>PurpleIRC.sdef</string>
</dict>
</plist>
PLIST

# Sign the bundle. Prefer a real Developer ID Application certificate
# when one is available in the user's keychain — that's what makes the
# app distributable outside the Mac App Store and notarisation-eligible.
# Override the auto-detection by exporting CODESIGN_IDENTITY before
# running this script (e.g. CODESIGN_IDENTITY="-" forces ad-hoc; a
# specific common-name like "Developer ID Application: Jane Doe (XYZ)"
# pins to that one when multiple are installed).
#
# Auto-detect: prefer Developer ID Application, fall back to ad-hoc.
detect_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi
    # First valid Developer ID Application certificate, if any.
    local devid
    devid=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"Developer ID Application:' \
        | head -1 \
        | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
    if [ -n "$devid" ]; then
        echo "$devid"
    else
        echo "-"
    fi
}

CODESIGN_ID="$(detect_codesign_identity)"

# Strip extended attributes before signing. swift build / cp pick up
# `com.apple.quarantine` / Finder info / resource forks from the
# source tree that codesign refuses to sign over ("resource fork,
# Finder information, or similar detritus not allowed"). iCloud
# Drive (PhantomLives lives under ~/Documents) ALSO re-attaches
# `com.apple.FinderInfo` and `com.apple.fileprovider.fpfs#P` at
# arbitrary times, so we delete the offenders explicitly in
# addition to the recursive clear.
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

if [ "$CODESIGN_ID" = "-" ]; then
    echo "Signing ad-hoc (no Developer ID Application cert found)..."
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
else
    echo "Signing with: $CODESIGN_ID"
    # --options runtime turns on the hardened runtime, which is required
    # for notarisation. --timestamp embeds an Apple-issued timestamp;
    # also notarisation-required. Without these flags the bundle still
    # signs but Apple will reject it from notary submission.
    codesign --force \
             --sign "$CODESIGN_ID" \
             --options runtime \
             --timestamp \
             "$APP_DIR"
    # Verify the signature actually took. Fail loudly so a CI build
    # doesn't ship an unsigned bundle silently. codesign --verify exits
    # non-zero on failure; capture the exit code rather than parsing
    # output (which varies across macOS versions).
    if codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>/tmp/codesign-verify.log; then
        echo "Signature verified."
    else
        echo "WARNING: codesign verification failed:"
        cat /tmp/codesign-verify.log
    fi
fi

# Copy the signed bundle back into the project directory using `ditto
# --noextattr` so iCloud Drive's eventual FinderInfo reattach doesn't
# disturb the embedded signature. The signed bundle is now in two
# places: the canonical /tmp build (where verification just succeeded
# under --strict) and the project-dir copy (where iCloud may stamp
# metadata, but the embedded signature itself stays valid because it
# only covers the bundle's contents, not its file-system metadata).
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"
rm -rf "$WORK_DIR"

echo "Built $FINAL_APP_DIR"
echo "Run with:  open $FINAL_APP_DIR"
