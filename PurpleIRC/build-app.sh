#!/bin/bash
# Builds PurpleIRC.app bundle from the Swift Package so the app activates its UI
# (WindowGroup requires a proper bundle / Info.plist on macOS).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

# Version strings are derived from git so every build after a commit is
# uniquely identifiable. The user-facing version is "1.0.<commit-count>";
# the build number carries the short SHA for diagnostic grepping. Override
# either by exporting SHORT_VERSION / BUILD_NUMBER before invoking.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Build the .app bundle in a tmp directory OUTSIDE iCloud Drive's reach.
# PhantomLives lives under ~/Documents which is iCloud-synced; iCloud
# Drive re-attaches `com.apple.FinderInfo` to fresh files at arbitrary
# moments, and codesign --strict (required for notarisation) refuses to
# sign or verify any bundle carrying that xattr. Doing the assembly +
# sign + verify in /tmp sidesteps the race entirely; we then `ditto
# --noextattr` the finished bundle back into the project directory.
FINAL_APP_DIR="PurpleIRC.app"
WORK_DIR="$(mktemp -d -t purpleirc-build)"
APP_DIR="$WORK_DIR/PurpleIRC.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/PurpleIRC" "$MACOS/PurpleIRC"

# App icon: regenerate the .iconset each build (the generator is deterministic,
# so this is fine) and let iconutil roll it into AppIcon.icns.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

# AppleScript dictionary. The .sdef declares verbs the OS will route via
# Apple Events to NSScriptCommand subclasses (see AppleScriptCommands.swift).
# Combined with NSAppleScriptEnabled + OSAScriptingDefinition in Info.plist,
# this is what makes Script Editor's "Open Dictionary…" find PurpleIRC.
if [ -f "Resources/PurpleIRC.sdef" ]; then
    cp "Resources/PurpleIRC.sdef" "$RESOURCES/PurpleIRC.sdef"
fi

# HEREDOC without quoted tag so $SHORT_VERSION / $BUILD_NUMBER expand.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PurpleIRC</string>
    <key>CFBundleDisplayName</key><string>PurpleIRC</string>
    <key>CFBundleIdentifier</key><string>com.example.PurpleIRC</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PurpleIRC</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleScriptEnabled</key><true/>
    <key>OSAScriptingDefinition</key><string>PurpleIRC.sdef</string>
</dict>
</plist>
PLIST

# Sign the bundle. Prefer a real Developer ID Application certificate
# when one is available in the user's keychain — that's what makes the
# app distributable outside the Mac App Store and notarisation-eligible.
# Override the auto-detection by exporting CODESIGN_IDENTITY before
# running this script (e.g. CODESIGN_IDENTITY="-" forces ad-hoc; a
# specific common-name like "Developer ID Application: Jane Doe (XYZ)"
# pins to that one when multiple are installed).
#
# Auto-detect: prefer Developer ID Application, fall back to ad-hoc.
detect_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi
    # First valid Developer ID Application certificate, if any.
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

# Strip extended attributes before signing. swift build / cp pick up
# `com.apple.quarantine` / Finder info / resource forks from the
# source tree that codesign refuses to sign over ("resource fork,
# Finder information, or similar detritus not allowed"). iCloud
# Drive (PhantomLives lives under ~/Documents) ALSO re-attaches
# `com.apple.FinderInfo` and `com.apple.fileprovider.fpfs#P` at
# arbitrary times, so we delete the offenders explicitly in
# addition to the recursive clear.
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

if [ "$CODESIGN_ID" = "-" ]; then
    echo "Signing ad-hoc (no Developer ID Application cert found)..."
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
else
    echo "Signing with: $CODESIGN_ID"
    # --options runtime turns on the hardened runtime, which is required
    # for notarisation. --timestamp embeds an Apple-issued timestamp;
    # also notarisation-required. Without these flags the bundle still
    # signs but Apple will reject it from notary submission.
    codesign --force \
             --sign "$CODESIGN_ID" \
             --options runtime \
             --timestamp \
             "$APP_DIR"
    # Verify the signature actually took. Fail loudly so a CI build
    # doesn't ship an unsigned bundle silently. codesign --verify exits
    # non-zero on failure; capture the exit code rather than parsing
    # output (which varies across macOS versions).
    if codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>/tmp/codesign-verify.log; then
        echo "Signature verified."
    else
        echo "WARNING: codesign verification failed:"
        cat /tmp/codesign-verify.log
    fi
fi

# Copy the signed bundle back into the project directory using `ditto
# --noextattr` so iCloud Drive's eventual FinderInfo reattach doesn't
# disturb the embedded signature. The signed bundle is now in two
# places: the canonical /tmp build (where verification just succeeded
# under --strict) and the project-dir copy (where iCloud may stamp
# metadata, but the embedded signature itself stays valid because it
# only covers the bundle's contents, not its file-system metadata).
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"
rm -rf "$WORK_DIR"

# Optional notarization. Gatekeeper warns "developer cannot be verified" on
# Macs the user hasn't run the app on before unless the bundle is notarized
# AND the notarization ticket is stapled to the .app. Both are gated on the
# NOTARIZE_PROFILE env var so routine personal builds skip them; a release
# build (Scripts/release.sh) opts in. PurpleIRC has no in-app updater, so
# notarization is the ONLY thing that makes a downloaded copy open cleanly on
# someone else's Mac.
#
# Setup (one-time per dev machine — see RELEASING.md):
#   1. Create an app-specific password at https://appleid.apple.com/account/manage
#      under "App-Specific Passwords".
#   2. Store it in the keychain as a notarytool credential profile:
#      $ xcrun notarytool store-credentials "PurpleIRC-Notary" \
#          --apple-id you@example.com \
#          --team-id SRKV8T38CD \
#          --password <the app-specific password>
#   3. Build with NOTARIZE_PROFILE=PurpleIRC-Notary ./build-app.sh
if [ -n "${NOTARIZE_PROFILE:-}" ]; then
    if [ "$CODESIGN_ID" = "-" ]; then
        echo "WARNING: NOTARIZE_PROFILE is set but the bundle is ad-hoc-signed."
        echo "Notary will reject it — skipping. Set CODESIGN_IDENTITY to a"
        echo "Developer ID Application cert and re-run."
    else
        echo "Notarizing with profile: $NOTARIZE_PROFILE"
        # notarytool wants a zip/dmg/pkg, not a raw .app. We zip via ditto so
        # the embedded signature is preserved bit-for-bit.
        NOTARIZE_ZIP="$(mktemp -t purpleirc-notarize).zip"
        ditto -c -k --keepParent "$FINAL_APP_DIR" "$NOTARIZE_ZIP"
        # `notarytool submit --wait` exits 0 whether Apple accepted or
        # rejected the submission — the wait completed either way. Parse the
        # plist's <status> field to detect Invalid/Rejected verdicts; only
        # "Accepted" gets stapled. On rejection, fetch the detailed log so the
        # failure cause lands in /tmp/notarize.log.
        # `|| true`: a missing/unauthorized profile (or a network blip) makes
        # notarytool exit non-zero, which under `set -e` would abort the whole
        # script *before the install step* — a transient notary failure must
        # not block the local build/install. We capture the failure via the
        # plist's <status> instead and warn (below).
        xcrun notarytool submit "$NOTARIZE_ZIP" \
                --keychain-profile "$NOTARIZE_PROFILE" \
                --wait \
                --output-format plist > /tmp/notarize.plist 2>&1 || true
        rm -f "$NOTARIZE_ZIP"
        # On a real submission notarytool writes a plist with :status/:id. On a
        # pre-flight failure (bad/missing profile, auth, network) it writes a
        # plain-text error instead, and PlistBuddy fails to parse it — detect
        # that via PlistBuddy's exit code and mark it SubmitFailed so the
        # warning below shows the raw error rather than mis-parsing it.
        if /usr/libexec/PlistBuddy -c 'Print :status' /tmp/notarize.plist >/tmp/notarize.status 2>/dev/null; then
            NOTARIZE_STATUS="$(cat /tmp/notarize.status)"
            NOTARIZE_ID="$(/usr/libexec/PlistBuddy -c 'Print :id' /tmp/notarize.plist 2>/dev/null || echo '')"
        else
            NOTARIZE_STATUS="SubmitFailed"
            NOTARIZE_ID=""
        fi
        rm -f /tmp/notarize.status
        if [ "$NOTARIZE_STATUS" = "Accepted" ]; then
            echo "Notarization accepted (id $NOTARIZE_ID)."
            echo "Stapling ticket to ${FINAL_APP_DIR}…"
            if xcrun stapler staple "$FINAL_APP_DIR"; then
                NOTARIZE_OK=1
            else
                echo "WARNING: stapler failed — bundle is notarized but ticket isn't embedded."
            fi
        else
            echo "WARNING: notarization did not succeed (status: $NOTARIZE_STATUS)."
            if [ -z "$NOTARIZE_ID" ]; then
                # No submission id ⇒ the submit itself failed (bad/missing
                # profile, auth, network) rather than Apple rejecting the
                # bundle. Show the raw notarytool error so the cause is obvious.
                echo "         notarytool error:"
                sed 's/^/           /' /tmp/notarize.plist 2>/dev/null | head -4
                echo "         (Often: profile '$NOTARIZE_PROFILE' isn't stored on this"
                echo "          Mac — see RELEASING.md. The signed bundle was still built.)"
            else
                echo "         Apple rejected submission $NOTARIZE_ID. Fetching log to /tmp/notarize.log…"
                xcrun notarytool log "$NOTARIZE_ID" \
                    --keychain-profile "$NOTARIZE_PROFILE" \
                    /tmp/notarize.log 2>&1 || true
                echo "         Common cause: an executable in the bundle not signed"
                echo "         with --options runtime + --timestamp. See /tmp/notarize.log."
            fi
        fi
    fi
fi

echo "Built $FINAL_APP_DIR"
echo "Run with:  open $FINAL_APP_DIR"
if [ "${NOTARIZE_OK:-0}" = "1" ]; then
    echo "(Notarized + stapled — Gatekeeper will accept this bundle on any Mac.)"
fi

# Auto-install: replace /Applications/PurpleIRC.app and relaunch. Opt
# out with `--no-install` (CI builds, signature inspection) or
# `--no-open` (install without focus-stealing relaunch). Per the
# PhantomLives install.sh standard in CLAUDE.md.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    INSTALL_SH="$(dirname "$0")/install.sh"
    if [ -x "$INSTALL_SH" ]; then
        echo ""
        "$INSTALL_SH" $INSTALL_FLAGS
    fi
fi
