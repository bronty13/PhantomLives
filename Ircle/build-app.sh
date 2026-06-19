#!/bin/bash
# Builds Ircle.app from the Swift Package so the app activates its UI
# (WindowGroup requires a proper bundle / Info.plist on macOS), then installs
# it to /Applications and relaunches — per the PhantomLives install.sh standard.
#
# Opt-outs:  ./build-app.sh --no-install   (build only, don't deploy)
#            ./build-app.sh --no-open      (install without focus-stealing relaunch)
#            BUILD_ONLY=1 ./build-app.sh   (same as --no-install)
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

# Version strings derived from git so every build after a commit is uniquely
# identifiable. User-facing version is "1.0.<commit-count>"; the build number
# carries the short SHA for diagnostic grepping. Override by exporting
# SHORT_VERSION / BUILD_NUMBER before invoking.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building Ircle (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Assemble the .app in a tmp dir outside iCloud's reach, then `ditto
# --noextattr` it back so a stray FinderInfo xattr can't break codesign.
FINAL_APP_DIR="Ircle.app"
WORK_DIR="$(mktemp -d -t ircle-build)"
APP_DIR="$WORK_DIR/Ircle.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH/Ircle" "$MACOS/Ircle"

# Bundle Sparkle.framework (the in-app auto-updater). SwiftPM ships Sparkle as
# an xcframework; copy the macOS slice into Contents/Frameworks/ so the loader
# finds the framework and Sparkle's nested XPC services + Updater.app at the
# paths it hard-codes. Without this the symbols link but the .app dies at launch
# with a dyld error.
SPARKLE_SRC="$(find .build/artifacts/sparkle/Sparkle/Sparkle.xcframework -name 'Sparkle.framework' -type d -path '*macos-arm64_x86_64*' 2>/dev/null | head -1)"
if [ -z "$SPARKLE_SRC" ]; then
    echo "FATAL: Sparkle.framework not found under .build/artifacts. Run 'swift package resolve' first." >&2
    exit 1
fi
mkdir -p "$CONTENTS/Frameworks"
ditto --noextattr "$SPARKLE_SRC" "$CONTENTS/Frameworks/Sparkle.framework"
# SwiftPM executables only get @loader_path on LC_RPATH; Sparkle's install name
# is @rpath/Sparkle.framework/... but it lives in Contents/Frameworks/, so add
# the standard macOS-app rpath. Re-adding is harmless.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/Ircle" 2>/dev/null || true

# App icon: regenerate the .iconset each build (the generator is deterministic)
# and roll it into AppIcon.icns BEFORE codesign.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

# AppleScript dictionary: the .sdef declares the verbs the OS routes to the
# NSScriptCommand subclasses in AppleScriptCommands.swift. Paired with
# NSAppleScriptEnabled + OSAScriptingDefinition in Info.plist below.
if [ -f "Resources/Ircle.sdef" ]; then
    cp "Resources/Ircle.sdef" "$RESOURCES/Ircle.sdef"
fi

# Sparkle config:
#  - SUFeedURL points at appcast.xml committed to the repo, served via
#    raw.githubusercontent.com.
#  - SUPublicEDKey is the EdDSA public half (shared PhantomLives fleet key,
#    exported as SPARKLE_PUBLIC_KEY in the dev shell). Routine builds without it
#    embed the placeholder, and UpdaterController declines to start the updater
#    (updates disabled) rather than crash — see UpdaterController.swift.
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/bronty13/PhantomLives/main/Ircle/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY}"

# HEREDOC without a quoted tag so $SHORT_VERSION / $BUILD_NUMBER expand.
# CFBundleIconFile is baked directly into the heredoc (avoids the silent-Set
# PlistBuddy gotcha — see docs/app-icon-standard.md).
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ircle</string>
    <key>CFBundleDisplayName</key><string>Ircle</string>
    <key>CFBundleIdentifier</key><string>com.phantomlives.Ircle</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Ircle</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleScriptEnabled</key><true/>
    <key>OSAScriptingDefinition</key><string>Ircle.sdef</string>
    <key>SUFeedURL</key><string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# Codesign: prefer a Developer ID Application cert if present, else ad-hoc.
# Override with CODESIGN_IDENTITY ("-" forces ad-hoc).
detect_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then echo "$CODESIGN_IDENTITY"; return; fi
    local devid
    devid=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"Developer ID Application:' \
        | head -1 \
        | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
    if [ -n "$devid" ]; then echo "$devid"; else echo "-"; fi
}
CODESIGN_ID="$(detect_codesign_identity)"

# Sign one path with the project identity + hardened runtime (+ timestamp with a
# real cert). Used for Sparkle's nested executables, which must be signed
# individually, inside-out, BEFORE the outer .app.
sign_helper() {
    local target="$1"
    if [ "$CODESIGN_ID" = "-" ]; then
        codesign --force --sign - --options runtime "$target" 2>/dev/null || true
    else
        codesign --force --sign "$CODESIGN_ID" --options runtime --timestamp "$target"
    fi
}

# Sparkle bundles nested executables (XPC services + Updater.app + Autoupdate)
# that must each be signed before the framework, and the framework before the
# outer .app — outside-in signing fails verification. Sign inside-out.
sign_sparkle() {
    local fw="$CONTENTS/Frameworks/Sparkle.framework"
    [ -d "$fw" ] || return 0
    find "$fw/Versions/B/XPCServices" -name '*.xpc' -mindepth 1 -maxdepth 1 2>/dev/null | while read -r xpc; do
        sign_helper "$xpc"
    done
    [ -d "$fw/Versions/B/Updater.app" ] && sign_helper "$fw/Versions/B/Updater.app"
    [ -f "$fw/Versions/B/Autoupdate" ] && sign_helper "$fw/Versions/B/Autoupdate"
    sign_helper "$fw"
}

# Strip extended attributes codesign refuses on (quarantine / FinderInfo /
# provenance / fileprovider), recursively + explicitly.
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

if [ "$CODESIGN_ID" = "-" ]; then
    echo "Signing ad-hoc (no Developer ID Application cert found)..."
    sign_sparkle
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
else
    echo "Signing with: $CODESIGN_ID"
    sign_sparkle
    codesign --force --sign "$CODESIGN_ID" --options runtime --timestamp "$APP_DIR"
    if codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>/tmp/ircle-codesign.log; then
        echo "Signature verified."
    else
        echo "WARNING: codesign verification failed:"; cat /tmp/ircle-codesign.log
    fi
fi

# Copy the signed bundle back into the project dir with --noextattr.
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"
rm -rf "$WORK_DIR"

echo "Built $FINAL_APP_DIR"

# Auto-install: replace /Applications/Ircle.app and relaunch. Opt out with
# `--no-install` or `BUILD_ONLY=1`; `--no-open` installs without relaunch.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    INSTALL_SH="$(dirname "$0")/install.sh"
    if [ -x "$INSTALL_SH" ]; then
        echo ""
        "$INSTALL_SH" $INSTALL_FLAGS
    fi
fi
