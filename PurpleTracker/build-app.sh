#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="PurpleTracker"
BUNDLE_ID="com.bronty13.PurpleTracker"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.1.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
ICNS_PATH="$(mktemp -d)/AppIcon.icns"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" \
    Sources/PurpleTracker/App/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
    Sources/PurpleTracker/App/Info.plist

cat > Sources/PurpleTracker/App/Version.swift << EOF
enum AppVersion {
    static let marketing = "$SHORT_VERSION"
    static let build = "$BUILD_NUMBER"
    static let display = "v\(AppVersion.marketing) (\(AppVersion.build))"
}
EOF

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

ditto --noextattr "$ICNS_PATH" "$DEST_APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" \
    "$DEST_APP/Contents/Info.plist" 2>/dev/null || true

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
