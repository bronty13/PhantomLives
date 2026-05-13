#!/bin/bash
# Builds MessagesExporterGUI.app from the Swift Package so the app activates its UI
# (WindowGroup requires a proper bundle / Info.plist on macOS).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

# Version strings derived from git so every build after a commit is uniquely
# identifiable. Override either by exporting SHORT_VERSION / BUILD_NUMBER.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

# Cleanup pass BEFORE the build: kill any " N.app" duplicates iCloud File
# Provider may have spawned since the last build, AND kill the destination
# bundle itself if Launch Services has it open. We want a fresh slate so
# the post-build copy can't collide with a stale sibling — past sessions
# repeatedly saw `open MessagesExporterGUI.app` launching a phantom copy
# instead of the freshly-signed bundle.
shopt -s nullglob 2>/dev/null || true
for dup in MessagesExporterGUI\ [0-9]*.app "MessagesExporterGUI 2.app" \
           "MessagesExporterGUI 3.app" "MessagesExporterGUI 4.app"; do
    if [ -d "$dup" ]; then
        echo "Pre-build cleanup: removing $dup"
        rm -rf "$dup"
    fi
done

echo "Building (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Assemble + sign the .app outside the iCloud-synced project tree, then ditto
# --noextattr the result back. iCloud's File Provider re-attaches FinderInfo /
# fileprovider.fpfs#P xattrs at arbitrary moments — including in the window
# between `xattr -cr` and `codesign`, which makes codesign fail with "resource
# fork, Finder information, or similar detritus not allowed". Doing the whole
# strip + sign + verify in /tmp sidesteps the race; same pattern as
# PurpleIRC/PurpleDedup/PurpleLife.
WORK_DIR="$(mktemp -d -t messages-exporter-gui-build)"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_DIR="$WORK_DIR/MessagesExporterGUI.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/MessagesExporterGUI" "$MACOS/MessagesExporterGUI"

# App icon: regenerate the .iconset each build (the generator is deterministic,
# so this is fine) and let iconutil roll it into AppIcon.icns.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

# HEREDOC without quoted tag so $SHORT_VERSION / $BUILD_NUMBER expand.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MessagesExporterGUI</string>
    <key>CFBundleDisplayName</key><string>Messages Exporter</string>
    <key>CFBundleIdentifier</key><string>com.bronty13.MessagesExporterGUI</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>MessagesExporterGUI</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Strip Finder xattrs codesign rejects. `xattr -cr` skips the bundle dir
# itself on some macOS versions, so explicitly clear the root too.
xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -c  "$APP_DIR" 2>/dev/null || true

# Code-sign. With a Developer ID Application certificate, TCC keys grants
# on (team ID, bundle ID) — so a rebuild preserves the user's Full Disk
# Access permission rather than rotating the cdhash and creating a new
# Privacy entry. Ad-hoc signing (the legacy fallback) is fine for fresh
# checkouts that don't have the cert installed; the app will still launch
# but FDA must be re-granted on every rebuild.
#
# Override DEVELOPER_ID to a different cert, or set it to "-" to force
# ad-hoc. The default matches the maintainer's installed cert.
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Robert Olen (SRKV8T38CD)}"

if [ "$DEVELOPER_ID" != "-" ] && \
   security find-identity -p codesigning -v 2>/dev/null \
        | grep -q "$DEVELOPER_ID"; then
    echo "Signing with Developer ID: $DEVELOPER_ID"
    # --options runtime enables Hardened Runtime, required for notarization
    # and a no-op outside it. --timestamp embeds a trusted timestamp so the
    # signature stays verifiable after the cert eventually expires.
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID" "$APP_DIR"
    # Strict verify is safe here because we're still in /tmp, not iCloud.
    if codesign --verify --strict --verbose=2 "$APP_DIR" >/dev/null 2>&1; then
        TEAM_ID=$(codesign -dv "$APP_DIR" 2>&1 | sed -n 's/^TeamIdentifier=//p')
        echo "✓ Signature verified (TeamIdentifier=${TEAM_ID:-unknown})"
    else
        echo "⚠️  codesign --verify reported issues — see output above"
    fi
else
    echo "Developer ID '$DEVELOPER_ID' not in keychain — ad-hoc signing"
    echo "    (FDA must be re-granted after every rebuild in this mode)"
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
fi

# Wipe Finder-created "MessagesExporterGUI 2.app" / "MessagesExporterGUI 3.app"
# duplicates. macOS auto-renames .app bundles when an old copy is pinned (e.g.
# previously launched and still listed in TCC); the duplicates accumulate
# distinct cdhashes and pollute System Settings → Privacy & Security → Full
# Disk Access with stale entries that no longer match the live binary.
shopt -s nullglob 2>/dev/null || true
for dup in MessagesExporterGUI\ [0-9]*.app; do
    if [ -d "$dup" ]; then
        echo "Removing duplicate bundle: $dup"
        rm -rf "$dup"
    fi
done

# Move the signed bundle back into the project dir. `ditto --noextattr` strips
# any xattrs the copy would otherwise pick up; iCloud may still re-attach
# FinderInfo to the destination later, but the embedded signature is what
# launch / TCC validate against, and that was sealed in /tmp.
FINAL_APP_DIR="MessagesExporterGUI.app"
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"

# Discourage iCloud Drive from spawning " 2.app" / " 3.app" sibling copies
# of our freshly-signed bundle. The File Provider attaches these xattrs to
# treat the file as cloud-managed; setting them off (and adding the local-
# only marker) keeps the bundle pinned on this device and ignored by the
# upload/conflict-resolution loop that produces the duplicates. Spotlight
# kMDItemSupportFileType=MDSystemFile suppresses the .app from indexing,
# which also keeps Launch Services from registering the duplicates as
# launchable. All best-effort: failures are non-fatal.
xattr -w com.apple.metadata:com_apple_backup_excludeItem 'com.apple.backupd' "$FINAL_APP_DIR" 2>/dev/null || true
xattr -w com.apple.fileprovider.ignore '1' "$FINAL_APP_DIR" 2>/dev/null || true
xattr -d com.apple.fileprovider.fpfs#P "$FINAL_APP_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$FINAL_APP_DIR" 2>/dev/null || true

# Re-register with Launch Services so subsequent `open MessagesExporterGUI.app`
# resolves to *this* bundle, not a phantom cached entry. Without this step,
# previously-deleted " 2.app"/" 3.app" copies can keep getting hit because
# their cdhash is still in the LS database until a full re-register clears it.
LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister'
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$FINAL_APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built $FINAL_APP_DIR"
echo "Run with:  open $FINAL_APP_DIR"
