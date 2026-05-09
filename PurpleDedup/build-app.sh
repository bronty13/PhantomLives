#!/bin/bash
# Builds PurpleDedup.app bundle from the Swift Package so the SwiftUI app can activate
# its UI (WindowGroup needs a proper bundle / Info.plist on macOS). Modeled on
# PurpleIRC/build-app.sh — the iCloud / xattr / codesign dance is identical because
# PhantomLives lives under ~/Documents which iCloud Drive re-stamps.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

# Version strings are derived from git so every build after a commit is uniquely
# identifiable. Override SHORT_VERSION / BUILD_NUMBER via env to pin a build manually.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
# IMPORTANT: build the CLI ("pdedup") FIRST and the GUI ("PurpleDedup") SECOND. On
# case-insensitive APFS volumes (the macOS default) two products with case-distinct
# names land at the same bin-path file — whichever links last wins. The CLI's product
# name was renamed away from "purplededup" precisely to avoid this collision, but the
# build order still matters as a defensive belt-and-braces.
# IMPORTANT: do NOT mask `swift build` failures. With `set -e` the script
# already aborts on non-zero exit, but earlier runs accidentally piped or
# trapped errors which let stale binaries get re-bundled while the source
# was failing to compile. We re-assert the exit-code check explicitly.
if ! swift build -c "$CONFIG" --product pdedup; then
    echo "FATAL: pdedup build failed — aborting before bundling stale code." >&2
    exit 1
fi
if ! swift build -c "$CONFIG" --product PurpleDedup; then
    echo "FATAL: PurpleDedup build failed — aborting before bundling stale code." >&2
    exit 1
fi

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Assemble the .app outside iCloud's reach so codesign --strict can verify cleanly,
# then ditto --noextattr the result back into the project dir.
FINAL_APP_DIR="PurpleDedup.app"
WORK_DIR="$(mktemp -d -t purplededup-build)"
APP_DIR="$WORK_DIR/PurpleDedup.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/PurpleDedup" "$MACOS/PurpleDedup"

# Bundle the CLI binary alongside the app so users can install it with a one-line
# symlink (see INSTALL.md). The binary works standalone — no .app dependency.
cp "$BIN_PATH/pdedup" "$MACOS/pdedup"

# App icon: regenerate the .iconset every build (the generator is deterministic, so
# this is fine) and let iconutil roll it into AppIcon.icns. The icon code itself
# lives in Scripts/generate-icon.swift.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

# Sanity-check that the GUI binary we just copied is actually a SwiftUI app, not the
# CLI accidentally renamed (case-insensitive APFS bit us once already). The CLI links
# ArgumentParser; the GUI links SwiftUI. Bail loudly if the wrong binary is in place.
if otool -L "$MACOS/PurpleDedup" 2>/dev/null | grep -q "ArgumentParser"; then
    echo "FATAL: $MACOS/PurpleDedup links ArgumentParser — looks like the CLI binary"
    echo "got copied in place of the GUI. Build order or product naming is wrong."
    exit 1
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PurpleDedup</string>
    <key>CFBundleDisplayName</key><string>PurpleDedup</string>
    <key>CFBundleIdentifier</key><string>com.bronty13.PurpleDedup</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PurpleDedup</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>PurpleDedup. Personal use.</string>
    <key>NSPhotoLibraryUsageDescription</key><string>PurpleDedup needs access to your Photos library so it can find duplicates inside it and queue them in a "Marked for Deletion in PurpleDedup" album that you finalise inside Photos.app. Without this access, Photos library entries appear read-only.</string>
</dict>
</plist>
PLIST

# Auto-detect Developer ID Application cert; fall back to ad-hoc.
detect_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi
    local devid
    devid=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"Developer ID Application:' \
        | head -1 \
        | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
    if [ -n "$devid" ]; then
        echo "$devid"
    else
        echo "-"
    fi
}

CODESIGN_ID="$(detect_codesign_identity)"

# Strip xattrs that codesign refuses ("resource fork, Finder information, or similar
# detritus not allowed"). iCloud Drive likes to re-stamp these at arbitrary moments,
# hence the explicit per-attribute deletions on top of the recursive clear.
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

ENTITLEMENTS_FILE="$(pwd)/PurpleDedup.entitlements"
ENTITLEMENTS_FLAGS=()
if [ -f "$ENTITLEMENTS_FILE" ]; then
    ENTITLEMENTS_FLAGS=(--entitlements "$ENTITLEMENTS_FILE")
    echo "Using entitlements: $ENTITLEMENTS_FILE"
else
    echo "WARNING: entitlements file not found — Photos access will fail on macOS 14+."
fi

if [ "$CODESIGN_ID" = "-" ]; then
    echo "Signing ad-hoc (no Developer ID Application cert found)..."
    codesign --force --sign - "${ENTITLEMENTS_FLAGS[@]}" "$APP_DIR" 2>/dev/null || true
else
    echo "Signing with: $CODESIGN_ID"
    codesign --force \
             --sign "$CODESIGN_ID" \
             --options runtime \
             --timestamp \
             "${ENTITLEMENTS_FLAGS[@]}" \
             "$APP_DIR"
    if codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>/tmp/codesign-verify.log; then
        echo "Signature verified."
    else
        echo "WARNING: codesign verification failed:"
        cat /tmp/codesign-verify.log
    fi
fi

rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"
rm -rf "$WORK_DIR"

# Optional notarization. Apple's Gatekeeper warns "developer cannot be verified"
# on Macs the user hasn't run the app on before unless the bundle is notarized
# AND the notarization ticket is stapled to the .app. Both are gated on the
# NOTARIZE_PROFILE env var so the routine personal builds skip them; CI / a
# release build can opt in.
#
# Setup (one-time):
#   1. Create an app-specific password at https://appleid.apple.com/account/manage
#      under "App-Specific Passwords".
#   2. Store it in the keychain as a notarytool credential profile:
#      $ xcrun notarytool store-credentials "PurpleDedup-Notary" \
#          --apple-id you@example.com \
#          --team-id SRKV8T38CD \
#          --password <the app-specific password>
#   3. Build with NOTARIZE_PROFILE=PurpleDedup-Notary ./build-app.sh
if [ -n "${NOTARIZE_PROFILE:-}" ]; then
    if [ "$CODESIGN_ID" = "-" ]; then
        echo "WARNING: NOTARIZE_PROFILE is set but the bundle is ad-hoc-signed."
        echo "Notary will reject it — skipping. Set CODESIGN_IDENTITY to a"
        echo "Developer ID Application cert and re-run."
    else
        echo "Notarizing with profile: $NOTARIZE_PROFILE"
        # notarytool wants a zip/dmg/pkg, not a raw .app. We zip via ditto so
        # the embedded signature is preserved bit-for-bit.
        NOTARIZE_ZIP="$WORK_DIR.zip"
        ditto -c -k --keepParent "$FINAL_APP_DIR" "$NOTARIZE_ZIP"
        if xcrun notarytool submit "$NOTARIZE_ZIP" \
                --keychain-profile "$NOTARIZE_PROFILE" \
                --wait \
                --output-format plist > /tmp/notarize.plist 2>&1; then
            echo "Notarization accepted."
            rm -f "$NOTARIZE_ZIP"
            echo "Stapling ticket to $FINAL_APP_DIR…"
            xcrun stapler staple "$FINAL_APP_DIR" || \
                echo "WARNING: stapler failed — bundle is notarized but ticket isn't embedded. Re-run staple after the next build."
        else
            echo "WARNING: notarization failed. See /tmp/notarize.plist for the verdict."
            cat /tmp/notarize.plist | head -40
            rm -f "$NOTARIZE_ZIP"
        fi
    fi
fi

echo "Built $FINAL_APP_DIR"
echo "Run with:  open $FINAL_APP_DIR"
echo "CLI:       $FINAL_APP_DIR/Contents/MacOS/pdedup --help"
if [ -n "${NOTARIZE_PROFILE:-}" ] && [ "$CODESIGN_ID" != "-" ]; then
    echo "(Notarized — Gatekeeper will accept this bundle on any Mac.)"
fi
