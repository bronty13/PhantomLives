#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# xcodebuild requires full Xcode (not Command Line Tools). If xcode-select
# points at CLT but Xcode.app exists, use it for this build.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="PurpleMark"
BUNDLE_ID="com.bronty13.PurpleMark"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

# Regenerate the Xcode project from project.yml.
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

# Generate the app icon.
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
    echo "ERROR: Build failed — $SRC_APP not found"
    exit 1
fi

DEST_APP="./$PRODUCT_NAME.app"
rm -rf "$DEST_APP"
ditto --noextattr "$SRC_APP" "$DEST_APP"

# Stamp version strings into the BUILT bundle's plists (app + extensions).
QL_APPEX="$DEST_APP/Contents/PlugIns/PurpleMarkQuickLook.appex"
THUMB_APPEX="$DEST_APP/Contents/PlugIns/PurpleMarkThumbnail.appex"
for plist in "$DEST_APP/Contents/Info.plist" "$QL_APPEX/Contents/Info.plist" "$THUMB_APPEX/Contents/Info.plist"; do
    [ -f "$plist" ] || continue
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist" 2>/dev/null || true
done

# Install the icon (ditto --noextattr so no FinderInfo xattr trips codesign).
ditto --noextattr "$ICNS_PATH" "$DEST_APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" \
    "$DEST_APP/Contents/Info.plist" 2>/dev/null || true

# Code sign inside-out: framework → appex → app. Developer ID if available,
# otherwise ad-hoc (local dev).
# Bundle the Spotlight metadata importer into Contents/Library/Spotlight/ so
# Spotlight indexes the contents of .md files.
SPOTLIGHT_SRC="$BUILD_DIR/DerivedData/Build/Products/Release/PurpleMark.mdimporter"
SPOTLIGHT_DST="$DEST_APP/Contents/Library/Spotlight/PurpleMark.mdimporter"
if [ -d "$SPOTLIGHT_SRC" ]; then
    mkdir -p "$DEST_APP/Contents/Library/Spotlight"
    ditto --noextattr "$SPOTLIGHT_SRC" "$SPOTLIGHT_DST"
fi

# Allow an explicit identity override (release.sh passes CODESIGN_IDENTITY).
CERT="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | awk '{print $2}' || echo "")}"
FRAMEWORK="$DEST_APP/Contents/Frameworks/PurpleMarkRenderCore.framework"
SPARKLE_FW="$DEST_APP/Contents/Frameworks/Sparkle.framework"
APP_ENT="Sources/PurpleMark/App/PurpleMark.entitlements"
QL_ENT="Sources/PurpleMarkQuickLook/PurpleMarkQuickLook.entitlements"
THUMB_ENT="Sources/PurpleMarkThumbnail/PurpleMarkThumbnail.entitlements"

xattr -cr "$DEST_APP"

# Build the codesign argv once: Developer ID gets hardened runtime + a secure
# timestamp; ad-hoc (local dev) gets neither.
if [ -n "$CERT" ]; then
    echo "Signing with Developer ID: $CERT"
    SIGN=(codesign --force --options runtime --timestamp -s "$CERT")
else
    echo "No Developer ID found — using ad-hoc signing"
    SIGN=(codesign --force -s -)
fi

# Sparkle's nested helpers must be signed inside-out before the framework.
if [ -d "$SPARKLE_FW" ]; then
    SV="$SPARKLE_FW/Versions/Current"
    for xpc in "$SV/XPCServices/"*.xpc; do
        [ -d "$xpc" ] && "${SIGN[@]}" "$xpc"
    done
    [ -d "$SV/Updater.app" ] && "${SIGN[@]}" "$SV/Updater.app"
    [ -f "$SV/Autoupdate" ] && "${SIGN[@]}" "$SV/Autoupdate"
    "${SIGN[@]}" "$SPARKLE_FW"
fi

"${SIGN[@]}" "$FRAMEWORK"
[ -d "$SPOTLIGHT_DST" ] && "${SIGN[@]}" "$SPOTLIGHT_DST"
"${SIGN[@]}" --entitlements "$QL_ENT" "$QL_APPEX"
"${SIGN[@]}" --entitlements "$THUMB_ENT" "$THUMB_APPEX"
"${SIGN[@]}" --entitlements "$APP_ENT" "$DEST_APP"

echo ""
echo "✓ Built: $DEST_APP"
echo "  Version: $SHORT_VERSION ($BUILD_NUMBER)"

# Auto-install: replace /Applications/PurpleMark.app and relaunch. Opt out with
# `--no-install` (CI / signature inspection) or `--no-open` (no focus steal).
# Per the install.sh standard in CLAUDE.md.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    if [ -x "$(dirname "$0")/install.sh" ]; then
        echo ""
        "$(dirname "$0")/install.sh" $INSTALL_FLAGS
    fi
fi
