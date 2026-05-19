#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# xcodebuild requires full Xcode (not Command Line Tools). If the system
# xcode-select points at CLT but Xcode.app exists, use it for this build.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="MasterClipper"
BUNDLE_ID="com.bronty13.MasterClipper"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

# Regenerate Xcode project from project.yml
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

# Regenerate icon PNGs into the asset catalog. xcodebuild compiles the
# Assets.xcassets to Assets.car during the build and bakes the icon into the
# signed bundle. We must NOT drop a hand-built AppIcon.icns into Contents/
# afterwards — doing so would force a re-sign that strips Xcode's
# auto-generated provisioning profile association and breaks launch under
# taskgated-helper ("Unsatisfied entitlements", POSIX 163).
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
ASSET_ICONSET="Sources/MasterClipper/Resources/Assets.xcassets/AppIcon.appiconset"
for png in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
           icon_128x128.png icon_128x128@2x.png icon_256x256.png \
           icon_256x256@2x.png icon_512x512.png icon_512x512@2x.png; do
    if [ -f "$ICONSET_DIR/$png" ]; then
        cp "$ICONSET_DIR/$png" "$ASSET_ICONSET/$png"
    fi
done

# Update Info.plist version strings
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" \
    Sources/MasterClipper/App/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
    Sources/MasterClipper/App/Info.plist

# Update Version.swift
cat > Sources/MasterClipper/App/Version.swift << EOF
enum AppVersion {
    static let marketing = "$SHORT_VERSION"
    static let build = "$BUILD_NUMBER"
    static let display = "v\(AppVersion.marketing) (\(AppVersion.build))"
}
EOF

# Build in /tmp to avoid iCloud Drive issues
BUILD_DIR="$(mktemp -d)"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
CONTENTS="$APP_DIR/Contents"

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

# Copy the xcodebuild-signed bundle to the project directory.
#
# We do NOT re-sign here. xcodebuild's automatic signing has already produced
# a bundle with a valid embedded provisioning profile that grants the iCloud
# entitlements; any re-sign would have to perfectly reproduce the
# entitlements xcodebuild injected (including com.apple.application-identifier
# and com.apple.developer.team-identifier) OR Apple's taskgated-helper will
# reject the launch with "Unsatisfied entitlements" (POSIX 163).
#
# ditto --noextattr matters: when the project tree lives under
# ~/Documents/GitHub/… the iCloud File Provider re-attaches
# com.apple.FinderInfo to bundle contents at arbitrary times. Copying with
# --noextattr leaves no extended attributes for the File Provider to step on
# in the first place. The existing destination is removed up-front so a stale
# bundle never lingers.
DEST_APP="./$PRODUCT_NAME.app"
rm -rf "$DEST_APP"
ditto --noextattr "$SRC_APP" "$DEST_APP"

echo ""
echo "✓ Built: $DEST_APP"
echo "  Version: $SHORT_VERSION ($BUILD_NUMBER)"
echo "  Signature: $(codesign -dvv "$DEST_APP" 2>&1 | grep -E 'Authority|TeamIdentifier' | head -2 | tr '\n' ' ' | sed 's/  */ /g')"
