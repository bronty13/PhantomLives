#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# xcodebuild requires full Xcode (not Command Line Tools). If the system
# xcode-select points at CLT but Xcode.app exists, use it for this build.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCT_NAME="PurpleReel"
BUNDLE_ID="com.bronty13.PurpleReel"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-0.1.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building $PRODUCT_NAME $SHORT_VERSION ($BUILD_NUMBER)..."

# Regenerate icon PNGs into the asset catalog. Required so the .app
# bundle picks up changes to Scripts/generate-icon.swift without a
# manual round-trip.
echo "Generating icon assets..."
swift Scripts/generate-icon.swift Sources/PurpleReel/Resources/Assets.xcassets/AppIcon.appiconset >/dev/null

# Regenerate SHORTCUTS.md from the canonical Swift source so the
# Markdown reference and the in-app cheat sheet can't drift apart.
echo "Regenerating SHORTCUTS.md..."
swift Scripts/generate-shortcuts-md.swift >/dev/null

# Regenerate Xcode project from project.yml
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
else
    echo "ERROR: xcodegen not on PATH. Install with: brew install xcodegen" >&2
    exit 1
fi

# Update Version.swift + Info.plist with git-derived numbers so the
# About pane and bundle metadata stay in sync without manual edits.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" \
    Sources/PurpleReel/App/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
    Sources/PurpleReel/App/Info.plist

cat > Sources/PurpleReel/App/Version.swift << EOF
enum AppVersion {
    static let marketing = "$SHORT_VERSION"
    static let build = "$BUILD_NUMBER"
    static let display = "v\(AppVersion.marketing) (\(AppVersion.build))"
}
EOF

# Build in /tmp to dodge iCloud Drive xattrs that can corrupt the
# signed bundle.
BUILD_DIR="$(mktemp -d)"

echo "Compiling..."
xcodebuild -project $PRODUCT_NAME.xcodeproj \
    -scheme $PRODUCT_NAME \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -allowProvisioningUpdates \
    build \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    MARKETING_VERSION="$SHORT_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
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
