#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# xcodebuild needs full Xcode (not CLT). If xcode-select points at CLT but
# Xcode.app exists, use it for this build.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="PurpleArchive"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

# App icon.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
ICNS_PATH="$(mktemp -d)/AppIcon.icns"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

# Build in /tmp to avoid iCloud xattr issues that corrupt code signatures.
BUILD_DIR="$(mktemp -d)"
echo "Compiling..."
xcodebuild -project "$PRODUCT_NAME.xcodeproj" \
    -scheme "$PRODUCT_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    | grep -E "error:|warning: .*\.swift|BUILD SUCCEEDED|BUILD FAILED" | grep -v prebuilt-modules || true

SRC_APP="$BUILD_DIR/DerivedData/Build/Products/Release/$PRODUCT_NAME.app"
if [ ! -d "$SRC_APP" ]; then
    echo "ERROR: Build failed — $SRC_APP not found"; exit 1
fi

DEST_APP="./$PRODUCT_NAME.app"
rm -rf "$DEST_APP"
ditto --noextattr "$SRC_APP" "$DEST_APP"

# Stamp the git-derived version into the BUILT bundle's plists (app + every
# app-extension; source plists stay pristine).
PLIST="$DEST_APP/Contents/Info.plist"
QL_APPEX="$DEST_APP/Contents/PlugIns/PurpleArchiveQuickLook.appex"
THUMB_APPEX="$DEST_APP/Contents/PlugIns/PurpleArchiveThumbnail.appex"
FINDER_APPEX="$DEST_APP/Contents/PlugIns/PurpleArchiveFinderSync.appex"
for plist in "$PLIST" \
    "$QL_APPEX/Contents/Info.plist" \
    "$THUMB_APPEX/Contents/Info.plist" \
    "$FINDER_APPEX/Contents/Info.plist"; do
    [ -f "$plist" ] || continue
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist" 2>/dev/null || true
done

# Install icon.
ditto --noextattr "$ICNS_PATH" "$DEST_APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" "$PLIST" 2>/dev/null || true

# Bundle the `parc` CLI at Contents/Helpers/parc. The SwiftPM build is
# self-contained (ArchiveKit + vendored C libs static-linked), so it just drops
# in — no rpath wrangling. Users symlink it to their PATH (see USER_MANUAL.md).
echo "Bundling parc CLI..."
swift build -c release --product parc >/dev/null 2>&1 || true
PARC_BIN="$(swift build -c release --product parc --show-bin-path 2>/dev/null)/parc"
if [ -x "$PARC_BIN" ]; then
    mkdir -p "$DEST_APP/Contents/Helpers"
    ditto --noextattr "$PARC_BIN" "$DEST_APP/Contents/Helpers/parc"
else
    echo "  (warning: parc build not found — CLI not bundled)"
fi

# Code sign: Developer ID (hardened runtime + timestamp) if available, else ad-hoc.
CERT="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | awk '{print $2}' || echo "")}"
APP_ENT="Sources/PurpleArchive/App/PurpleArchive.entitlements"
QL_ENT="Sources/PurpleArchiveQuickLook/QuickLook.entitlements"
THUMB_ENT="Sources/PurpleArchiveThumbnail/Thumbnail.entitlements"
FINDER_ENT="Sources/PurpleArchiveFinderSync/FinderSync.entitlements"
SPARKLE_FW="$DEST_APP/Contents/Frameworks/Sparkle.framework"
ARCHIVEKIT_FW="$DEST_APP/Contents/Frameworks/ArchiveKit.framework"
xattr -cr "$DEST_APP"
if [ -n "$CERT" ]; then
    echo "Signing with Developer ID: $CERT"
    SIGN=(codesign --force --options runtime --timestamp -s "$CERT")
else
    echo "No Developer ID found — using ad-hoc signing"
    SIGN=(codesign --force --options runtime -s -)
fi
# Sign inside-out: frameworks → app-extensions → app.
# Sparkle's nested helpers first.
if [ -d "$SPARKLE_FW" ]; then
    SV="$SPARKLE_FW/Versions/Current"
    for xpc in "$SV/XPCServices/"*.xpc; do
        [ -d "$xpc" ] && "${SIGN[@]}" "$xpc"
    done
    [ -d "$SV/Updater.app" ] && "${SIGN[@]}" "$SV/Updater.app"
    [ -f "$SV/Autoupdate" ] && "${SIGN[@]}" "$SV/Autoupdate"
    "${SIGN[@]}" "$SPARKLE_FW"
fi
[ -d "$ARCHIVEKIT_FW" ] && "${SIGN[@]}" "$ARCHIVEKIT_FW"
# Bundled CLI.
[ -f "$DEST_APP/Contents/Helpers/parc" ] && "${SIGN[@]}" "$DEST_APP/Contents/Helpers/parc"
# App-extensions (each with its own entitlements).
[ -d "$QL_APPEX" ]     && "${SIGN[@]}" --entitlements "$QL_ENT" "$QL_APPEX"
[ -d "$THUMB_APPEX" ]  && "${SIGN[@]}" --entitlements "$THUMB_ENT" "$THUMB_APPEX"
[ -d "$FINDER_APPEX" ] && "${SIGN[@]}" --entitlements "$FINDER_ENT" "$FINDER_APPEX"
# The app last.
"${SIGN[@]}" --entitlements "$APP_ENT" "$DEST_APP"

echo ""
echo "✓ Built: $DEST_APP"
echo "  Version: $SHORT_VERSION ($BUILD_NUMBER)"

# Auto-install + relaunch unless opted out.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    [[ " $* " =~ " --no-open " ]] && INSTALL_FLAGS="--no-open"
    if [ -x "$(dirname "$0")/install.sh" ]; then
        echo ""
        "$(dirname "$0")/install.sh" $INSTALL_FLAGS
    fi
fi
