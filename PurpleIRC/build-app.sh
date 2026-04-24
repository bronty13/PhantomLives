#!/bin/bash
# Builds PurpleIRC.app bundle from the Swift Package so the app activates its UI
# (WindowGroup requires a proper bundle / Info.plist on macOS).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
echo "Building (configuration=$CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="PurpleIRC.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/PurpleIRC" "$MACOS/PurpleIRC"

# App icon: regenerate the .iconset each build (the generator is deterministic,
# so this is fine) and let iconutil roll it into AppIcon.icns.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PurpleIRC</string>
    <key>CFBundleDisplayName</key><string>PurpleIRC</string>
    <key>CFBundleIdentifier</key><string>com.example.PurpleIRC</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PurpleIRC</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will launch it even without a dev cert.
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "Built $APP_DIR"
echo "Run with:  open $APP_DIR"
