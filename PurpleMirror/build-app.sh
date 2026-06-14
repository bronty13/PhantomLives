#!/bin/bash
# Builds PurpleMirror.app from the Swift Package: embeds + signs Sparkle for
# in-app auto-updates, generates the icon from code, signs, and (by default)
# installs to /Applications + relaunches via install.sh.
# Opt out with --no-install / --no-open, or BUILD_ONLY=1.
#
# PurpleMirror is a menu-bar (LSUIElement) companion for sync-md-to-obsidian.sh.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.3.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

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

# --- Embed Sparkle.framework (in-app auto-updater) ---
# SwiftPM ships Sparkle as an xcframework binary target; copy the macOS slice
# into Contents/Frameworks/ so the loader + Sparkle's nested XPC services +
# Updater.app are found at the locations Sparkle hard-codes.
SPARKLE_SRC="$(find .build/artifacts/sparkle/Sparkle/Sparkle.xcframework -name 'Sparkle.framework' -type d -path '*macos-arm64_x86_64*' 2>/dev/null | head -1)"
if [ -z "$SPARKLE_SRC" ]; then
    echo "FATAL: Sparkle.framework not found under .build/artifacts. Run 'swift package resolve' first." >&2
    exit 1
fi
mkdir -p "$CONTENTS/Frameworks"
ditto --noextattr "$SPARKLE_SRC" "$CONTENTS/Frameworks/Sparkle.framework"
# SwiftPM executables only get @loader_path; Sparkle's install name is
# @rpath/Sparkle.framework/… but it lives in Contents/Frameworks/. Add the rpath.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/PurpleMirror" 2>/dev/null || true

# --- Icon: generate deterministically from code (no binary source of truth) ---
ICONSET="$WORK_DIR/AppIcon.iconset"
if swift Scripts/generate-icon.swift "$ICONSET" >/dev/null 2>&1 && [ -d "$ICONSET" ]; then
    iconutil -c icns -o "$RESOURCES/AppIcon.icns" "$ICONSET" 2>/dev/null \
        && echo "Generated AppIcon.icns" \
        || echo "warning: iconutil failed — generic icon" >&2
else
    echo "warning: icon generation failed — generic icon" >&2
fi

# --- Sparkle config (feed served via raw.githubusercontent — no Pages needed) ---
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/bronty13/PhantomLives/main/PurpleMirror/appcast.xml}"
# The matching PRIVATE key signs releases (sign_update). Without SPARKLE_PUBLIC_KEY
# set, the placeholder ships and Sparkle refuses untrusted updates — the safe
# default for personal builds. The release script sets it from the shared key.
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY}"

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
    <key>SUFeedURL</key><string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# --- Codesign (Sparkle nested executables inside-out, then the app) ---
detect_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then echo "$CODESIGN_IDENTITY"; return; fi
    local devid
    devid=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"Developer ID Application:' | head -1 \
        | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
    [ -n "$devid" ] && echo "$devid" || echo "-"
}
CODESIGN_ID="$(detect_codesign_identity)"

sign_one() {
    local target="$1"
    if [ "$CODESIGN_ID" = "-" ]; then
        codesign --force --sign - --options runtime "$target" 2>/dev/null || true
    else
        codesign --force --sign "$CODESIGN_ID" --options runtime --timestamp "$target"
    fi
}
sign_sparkle() {
    local fw="$CONTENTS/Frameworks/Sparkle.framework"
    [ -d "$fw" ] || return 0
    find "$fw/Versions/B/XPCServices" -name '*.xpc' -mindepth 1 -maxdepth 1 2>/dev/null | while read -r xpc; do
        echo "  Signing XPC: $(basename "$xpc")"; sign_one "$xpc"
    done
    [ -d "$fw/Versions/B/Updater.app" ] && { echo "  Signing Updater.app"; sign_one "$fw/Versions/B/Updater.app"; }
    [ -f "$fw/Versions/B/Autoupdate" ] && { echo "  Signing Autoupdate"; sign_one "$fw/Versions/B/Autoupdate"; }
    echo "  Signing Sparkle.framework"; sign_one "$fw"
}

# Strip detritus codesign refuses (quarantine / FinderInfo / fileprovider).
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

if [ "$CODESIGN_ID" = "-" ]; then
    echo "Signing ad-hoc (no Developer ID Application cert found)..."
    sign_sparkle
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
else
    echo "Signing with: $CODESIGN_ID"
    sign_sparkle
    codesign --force --sign "$CODESIGN_ID" --options runtime --timestamp "$APP_DIR"
    if codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null 2>&1; then
        echo "✓ Signature verified"
    else
        echo "⚠️  codesign --verify reported issues"
    fi
fi

FINAL_APP_DIR="PurpleMirror.app"
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"

xattr -w com.apple.metadata:com_apple_backup_excludeItem 'com.apple.backupd' "$FINAL_APP_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$FINAL_APP_DIR" 2>/dev/null || true

LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister'
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$FINAL_APP_DIR" >/dev/null 2>&1 || true

echo "Built $FINAL_APP_DIR"

# --- Optional notarization (gated on NOTARIZE=1; release.sh opts in) ---
# Plain `./build-app.sh` dev builds SKIP notarization even if NOTARIZE_PROFILE
# is set in the ambient shell env — notarization (a ~1-min network round-trip) is
# reserved for tagged releases via Scripts/release.sh, which sets NOTARIZE=1.
if [ "${NOTARIZE:-0}" = "1" ] && [ -n "${NOTARIZE_PROFILE:-}" ]; then
    if [ "$CODESIGN_ID" = "-" ]; then
        echo "WARNING: NOTARIZE_PROFILE set but bundle is ad-hoc-signed — notary will reject. Skipping."
    else
        echo "Notarizing with profile: $NOTARIZE_PROFILE"
        NOTARIZE_ZIP="$(mktemp -t purplemirror-notarize).zip"
        ditto -c -k --keepParent "$FINAL_APP_DIR" "$NOTARIZE_ZIP"
        xcrun notarytool submit "$NOTARIZE_ZIP" \
            --keychain-profile "$NOTARIZE_PROFILE" --wait \
            --output-format plist > /tmp/pm-notarize.plist 2>&1 || true
        rm -f "$NOTARIZE_ZIP"
        if /usr/libexec/PlistBuddy -c 'Print :status' /tmp/pm-notarize.plist >/tmp/pm-notarize.status 2>/dev/null; then
            NOTARIZE_STATUS="$(cat /tmp/pm-notarize.status)"
            NOTARIZE_ID="$(/usr/libexec/PlistBuddy -c 'Print :id' /tmp/pm-notarize.plist 2>/dev/null || echo '')"
        else
            NOTARIZE_STATUS="SubmitFailed"; NOTARIZE_ID=""
        fi
        rm -f /tmp/pm-notarize.status
        if [ "$NOTARIZE_STATUS" = "Accepted" ]; then
            echo "Notarization accepted (id $NOTARIZE_ID). Stapling…"
            xcrun stapler staple "$FINAL_APP_DIR" || echo "WARNING: stapler failed — notarized but ticket not embedded."
        else
            echo "WARNING: notarization did not succeed (status: $NOTARIZE_STATUS)."
            [ -z "$NOTARIZE_ID" ] && sed 's/^/           /' /tmp/pm-notarize.plist 2>/dev/null | head -4
        fi
    fi
fi

if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    [[ " $* " =~ " --no-open " ]] && INSTALL_FLAGS="--no-open"
    INSTALL_SH="$(dirname "$0")/install.sh"
    [ -x "$INSTALL_SH" ] && { echo ""; "$INSTALL_SH" $INSTALL_FLAGS; }
fi
