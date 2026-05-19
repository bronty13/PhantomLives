#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# xcodebuild requires full Xcode (not Command Line Tools). If the system
# xcode-select points at CLT but Xcode.app exists, use it for this build.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="PurpleLife"
BUNDLE_ID="com.bronty13.PurpleLife"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-0.1.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

# Regenerate Xcode project from project.yml
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

# Build in /tmp to avoid iCloud Drive xattr issues that can corrupt
# code signatures.
BUILD_DIR="$(mktemp -d)"

echo "Compiling..."
# Phase 4: build Debug + Automatic dev signing so the iCloud entitlement
# in PurpleLife.entitlements can be honored. Developer ID signing (which
# the script used pre-Phase-4) doesn't carry CloudKit entitlements; for
# personal multi-Mac use we want Apple Development with the development
# provisioning profile that includes iCloud + the container assignment
# (provisioned at developer.apple.com under team SRKV8T38CD).
#
# MARKETING_VERSION / CURRENT_PROJECT_VERSION are passed in here so they
# end up in Info.plist BEFORE codesign — modifying Info.plist post-build
# would invalidate the iCloud-bearing signature.
#
# The asset catalog handles AppIcon, so we no longer overwrite
# Resources/AppIcon.icns post-build.
xcodebuild -project $PRODUCT_NAME.xcodeproj \
    -scheme $PRODUCT_NAME \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -allowProvisioningUpdates \
    build \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    MARKETING_VERSION="$SHORT_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    ONLY_ACTIVE_ARCH=YES \
    | grep -E "error:|warning:|Build succeeded|Build FAILED" || true

SRC_APP="$BUILD_DIR/DerivedData/Build/Products/Debug/$PRODUCT_NAME.app"
if [ ! -d "$SRC_APP" ]; then
    echo "ERROR: Build failed — $SRC_APP not found"
    exit 1
fi

DEST_APP="./$PRODUCT_NAME.app"
rm -rf "$DEST_APP"
ditto --noextattr "$SRC_APP" "$DEST_APP"

# No post-build mods here — xcodebuild already produced a signed bundle
# with the right version (passed in via MARKETING_VERSION) and AppIcon
# (from the asset catalog). Modifying Info.plist or Resources after
# this point would invalidate the iCloud-bearing signature.
xattr -cr "$DEST_APP" || true
if ! codesign --verify "$DEST_APP" 2>/dev/null; then
    echo "WARNING: bundle signature is invalid; CloudKit may refuse to start."
fi

echo ""
echo "✓ Built: $DEST_APP"
echo "  Version: $SHORT_VERSION ($BUILD_NUMBER)"
