#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="ElectronicDetective"
BUNDLE_ID="com.bronty13.ElectronicDetective"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

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

# Stamp version into the BUILT bundle's Info.plist *inside /tmp* — well away
# from iCloud Drive's file-provider, which re-adds FinderInfo/provenance
# xattrs to anything it sees and breaks codesign mid-flight.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" \
    "$SRC_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$SRC_APP/Contents/Info.plist"

# Sign in /tmp so the signing surface is clean. Once signed, ditto with
# --noextattr copies the bundle into the (potentially iCloud-synced) project
# directory without dragging xattrs along; xattrs that file-provider later
# adds to the bundle ROOT don't invalidate the signature of files INSIDE it.
xattr -cr "$SRC_APP"
CERT="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | awk '{print $2}' || echo "")"
if [ -n "$CERT" ]; then
    echo "Signing with Developer ID: $CERT"
    codesign --sign "$CERT" --options runtime --timestamp --force "$SRC_APP"
else
    echo "No Developer ID found — using ad-hoc signing"
    codesign --sign - --force "$SRC_APP"
fi
codesign --verify --strict "$SRC_APP"

DEST_APP="./$PRODUCT_NAME.app"
rm -rf "$DEST_APP"
ditto --noextattr "$SRC_APP" "$DEST_APP"

echo ""
echo "✓ Built: $DEST_APP"
echo "  Version: $SHORT_VERSION ($BUILD_NUMBER)"
