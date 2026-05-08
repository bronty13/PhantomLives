#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# xcodebuild requires full Xcode (not Command Line Tools). If the system
# xcode-select points at CLT but Xcode.app exists, use it for this build.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="Timeliner"
BUNDLE_ID="com.bronty13.Timeliner"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

# Regenerate Xcode project from project.yml
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

# Generate icon
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
ICNS_PATH="$(mktemp -d)/AppIcon.icns"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

# Version strings: NOT written to source files. The source Info.plist
# carries placeholders (0.0.0 / 0.unknown) and Version.swift reads from
# Bundle.main at runtime. The real values are stamped into the BUILT
# bundle's Info.plist after ditto, below — that way `git status` stays
# clean across builds and the monorepo's commit count never pollutes
# tracked Timeliner files.

# Build in /tmp to avoid iCloud Drive xattr issues that can corrupt code signatures
BUILD_DIR="$(mktemp -d)"

echo "Compiling..."
xcodebuild -project $PRODUCT_NAME.xcodeproj \
    -scheme $PRODUCT_NAME \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    ONLY_ACTIVE_ARCH=YES \
    | grep -E "error:|warning:|Build succeeded|Build FAILED" || true

SRC_APP="$BUILD_DIR/DerivedData/Build/Products/Release/$PRODUCT_NAME.app"
if [ ! -d "$SRC_APP" ]; then
    echo "ERROR: Build failed — $SRC_APP not found"
    exit 1
fi

DEST_APP="./$PRODUCT_NAME.app"
rm -rf "$DEST_APP"
ditto --noextattr "$SRC_APP" "$DEST_APP"

# Stamp the real version strings into the BUILT bundle's Info.plist.
# Source Info.plist carries 0.0.0 / 0.unknown placeholders; xcodebuild
# bakes those into the .app, and we overwrite them here. Keeps the
# tracked source plist pristine across builds.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" \
    "$DEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$DEST_APP/Contents/Info.plist"

# Install icon. Use ditto --noextattr so macOS doesn't carry a FinderInfo xattr
# from the source ICNS into the bundle — codesign --verify --strict will reject
# the bundle if any file inside has com.apple.FinderInfo, even with hardened
# runtime + Developer ID signing.
ditto --noextattr "$ICNS_PATH" "$DEST_APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" \
    "$DEST_APP/Contents/Info.plist" 2>/dev/null || true

# Code sign
CERT="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | awk '{print $2}' || echo "")"
if [ -n "$CERT" ]; then
    echo "Signing with Developer ID: $CERT"
    xattr -cr "$DEST_APP"
    codesign --sign "$CERT" --options runtime --timestamp --deep --force "$DEST_APP"
else
    echo "No Developer ID found — using ad-hoc signing"
    xattr -cr "$DEST_APP"
    codesign --sign - --deep --force "$DEST_APP"
fi

echo ""
echo "✓ Built: $DEST_APP"
echo "  Version: $SHORT_VERSION ($BUILD_NUMBER)"
