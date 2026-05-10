#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="CloudKitSpike"
BUNDLE_ID="com.bronty13.PurpleLife.CloudKitSpike"

echo "Generating Xcode project..."
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi
xcodegen generate >/dev/null

BUILD_DIR="$(mktemp -d)"
echo "Compiling..."
xcodebuild -project "$PRODUCT_NAME.xcodeproj" \
    -scheme "$PRODUCT_NAME" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
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

echo ""
echo "✓ Built: $DEST_APP"
echo ""
echo "To run: open $DEST_APP"
echo ""
echo "First-run prerequisites:"
echo "  1. Sign in to iCloud in System Settings."
echo "  2. Have an Apple Developer account that owns the container"
echo "     iCloud.com.bronty13.PurpleLife (create at"
echo "     https://developer.apple.com/account → CloudKit Containers)."
echo "  3. Enable iCloud + CloudKit capability in the generated"
echo "     Xcode project's Signing & Capabilities pane the first time"
echo "     (Xcode does this automatically when the entitlements file is"
echo "     present and the developer team is selected)."
