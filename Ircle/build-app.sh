#!/bin/bash
# Builds Ircle.app from the Swift Package so the app activates its UI
# (WindowGroup requires a proper bundle / Info.plist on macOS), then installs
# it to /Applications and relaunches — per the PhantomLives install.sh standard.
#
# Opt-outs:  ./build-app.sh --no-install   (build only, don't deploy)
#            ./build-app.sh --no-open      (install without focus-stealing relaunch)
#            BUILD_ONLY=1 ./build-app.sh   (same as --no-install)
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"

# Version strings derived from git so every build after a commit is uniquely
# identifiable. User-facing version is "1.0.<commit-count>"; the build number
# carries the short SHA for diagnostic grepping. Override by exporting
# SHORT_VERSION / BUILD_NUMBER before invoking.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

echo "Building Ircle (configuration=$CONFIG, version=$SHORT_VERSION build $BUILD_NUMBER)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

# Assemble the .app in a tmp dir outside iCloud's reach, then `ditto
# --noextattr` it back so a stray FinderInfo xattr can't break codesign.
FINAL_APP_DIR="Ircle.app"
WORK_DIR="$(mktemp -d -t ircle-build)"
APP_DIR="$WORK_DIR/Ircle.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH/Ircle" "$MACOS/Ircle"

# Bundle Sparkle.framework (the in-app auto-updater). SwiftPM ships Sparkle as
# an xcframework; copy the macOS slice into Contents/Frameworks/ so the loader
# finds the framework and Sparkle's nested XPC services + Updater.app at the
# paths it hard-codes. Without this the symbols link but the .app dies at launch
# with a dyld error.
SPARKLE_SRC="$(find .build/artifacts/sparkle/Sparkle/Sparkle.xcframework -name 'Sparkle.framework' -type d -path '*macos-arm64_x86_64*' 2>/dev/null | head -1)"
if [ -z "$SPARKLE_SRC" ]; then
    echo "FATAL: Sparkle.framework not found under .build/artifacts. Run 'swift package resolve' first." >&2
    exit 1
fi
mkdir -p "$CONTENTS/Frameworks"
ditto --noextattr "$SPARKLE_SRC" "$CONTENTS/Frameworks/Sparkle.framework"
# SwiftPM executables only get @loader_path on LC_RPATH; Sparkle's install name
# is @rpath/Sparkle.framework/... but it lives in Contents/Frameworks/, so add
# the standard macOS-app rpath. Re-adding is harmless.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/Ircle" 2>/dev/null || true

# App icon: regenerate the .iconset each build (the generator is deterministic)
# and roll it into AppIcon.icns BEFORE codesign.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift Scripts/generate-icon.swift "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns"

# AppleScript dictionary: the .sdef declares the verbs the OS routes to the
# NSScriptCommand subclasses in AppleScriptCommands.swift. Paired with
# NSAppleScriptEnabled + OSAScriptingDefinition in Info.plist below.
if [ -f "Resources/Ircle.sdef" ]; then
    cp "Resources/Ircle.sdef" "$RESOURCES/Ircle.sdef"
fi

# In-app manual (rendered by ManualView via the lightweight Markdown reader).
if [ -f "Resources/Manual.md" ]; then
    cp "Resources/Manual.md" "$RESOURCES/Manual.md"
fi

# Sparkle config:
#  - SUFeedURL points at appcast.xml committed to the repo, served via
#    raw.githubusercontent.com.
#  - SUPublicEDKey is the EdDSA public half (shared PhantomLives fleet key,
#    exported as SPARKLE_PUBLIC_KEY in the dev shell). Routine builds without it
#    embed the placeholder, and UpdaterController declines to start the updater
#    (updates disabled) rather than crash — see UpdaterController.swift.
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/bronty13/PhantomLives/main/Ircle/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY}"

# HEREDOC without a quoted tag so $SHORT_VERSION / $BUILD_NUMBER expand.
# CFBundleIconFile is baked directly into the heredoc (avoids the silent-Set
# PlistBuddy gotcha — see docs/app-icon-standard.md).
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ircle</string>
    <key>CFBundleDisplayName</key><string>Ircle</string>
    <key>CFBundleIdentifier</key><string>com.phantomlives.Ircle</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Ircle</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleScriptEnabled</key><true/>
    <key>OSAScriptingDefinition</key><string>Ircle.sdef</string>
    <key>SUFeedURL</key><string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# Codesign: prefer a Developer ID Application cert if present, else ad-hoc.
# Override with CODESIGN_IDENTITY ("-" forces ad-hoc).
detect_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then echo "$CODESIGN_IDENTITY"; return; fi
    local devid
    devid=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"Developer ID Application:' \
        | head -1 \
        | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
    if [ -n "$devid" ]; then echo "$devid"; else echo "-"; fi
}
CODESIGN_ID="$(detect_codesign_identity)"

# Sign one path with the project identity + hardened runtime (+ timestamp with a
# real cert). Used for Sparkle's nested executables, which must be signed
# individually, inside-out, BEFORE the outer .app.
sign_helper() {
    local target="$1"
    if [ "$CODESIGN_ID" = "-" ]; then
        codesign --force --sign - --options runtime "$target" 2>/dev/null || true
    else
        codesign --force --sign "$CODESIGN_ID" --options runtime --timestamp "$target"
    fi
}

# Sparkle bundles nested executables (XPC services + Updater.app + Autoupdate)
# that must each be signed before the framework, and the framework before the
# outer .app — outside-in signing fails verification. Sign inside-out.
sign_sparkle() {
    local fw="$CONTENTS/Frameworks/Sparkle.framework"
    [ -d "$fw" ] || return 0
    find "$fw/Versions/B/XPCServices" -name '*.xpc' -mindepth 1 -maxdepth 1 2>/dev/null | while read -r xpc; do
        sign_helper "$xpc"
    done
    [ -d "$fw/Versions/B/Updater.app" ] && sign_helper "$fw/Versions/B/Updater.app"
    [ -f "$fw/Versions/B/Autoupdate" ] && sign_helper "$fw/Versions/B/Autoupdate"
    sign_helper "$fw"
}

# Strip extended attributes codesign refuses on (quarantine / FinderInfo /
# provenance / fileprovider), recursively + explicitly.
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
find "$APP_DIR" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

if [ "$CODESIGN_ID" = "-" ]; then
    echo "Signing ad-hoc (no Developer ID Application cert found)..."
    sign_sparkle
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
else
    echo "Signing with: $CODESIGN_ID"
    sign_sparkle
    codesign --force --sign "$CODESIGN_ID" --options runtime --timestamp "$APP_DIR"
    if codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>/tmp/ircle-codesign.log; then
        echo "Signature verified."
    else
        echo "WARNING: codesign verification failed:"; cat /tmp/ircle-codesign.log
    fi
fi

# Copy the signed bundle back into the project dir with --noextattr.
rm -rf "$FINAL_APP_DIR"
ditto --noextattr "$APP_DIR" "$FINAL_APP_DIR"
rm -rf "$WORK_DIR"

# Optional notarization + stapling. Gatekeeper warns "developer cannot be
# verified" on Macs the user hasn't run the app on before unless the bundle is
# notarized AND the ticket is stapled to the .app. Both are gated on the
# NOTARIZE_PROFILE env var so routine personal builds skip them; a release build
# (Scripts/release.sh) opts in and then asserts `stapler validate` afterward —
# so this block MUST produce a stapled bundle when NOTARIZE_PROFILE is set with
# a real Developer ID cert, or the release fails loudly. Setup is one-time per
# Mac — see RELEASING.md.
if [ -n "${NOTARIZE_PROFILE:-}" ]; then
    if [ "$CODESIGN_ID" = "-" ]; then
        echo "WARNING: NOTARIZE_PROFILE is set but the bundle is ad-hoc-signed."
        echo "Notary will reject it — skipping. Set CODESIGN_IDENTITY to a"
        echo "Developer ID Application cert and re-run."
    else
        echo "Notarizing with profile: $NOTARIZE_PROFILE"
        # notarytool wants a zip/dmg/pkg, not a raw .app. We zip via ditto so
        # the embedded signature is preserved bit-for-bit.
        NOTARIZE_ZIP="$(mktemp -t ircle-notarize).zip"
        ditto -c -k --keepParent "$FINAL_APP_DIR" "$NOTARIZE_ZIP"
        # `notarytool submit --wait` exits 0 whether Apple accepted or rejected
        # — the wait completed either way. `|| true` so a missing profile / auth
        # / network blip doesn't abort the whole script under `set -e`; we read
        # the verdict from the plist's <status> instead.
        xcrun notarytool submit "$NOTARIZE_ZIP" \
                --keychain-profile "$NOTARIZE_PROFILE" \
                --wait \
                --output-format plist > /tmp/notarize.plist 2>&1 || true
        rm -f "$NOTARIZE_ZIP"
        # A real submission writes a plist with :status/:id; a pre-flight
        # failure writes plain text PlistBuddy can't parse — detect that via its
        # exit code and mark SubmitFailed so the warning shows the raw error.
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
if [ "${NOTARIZE_OK:-0}" = "1" ]; then
    echo "(Notarized + stapled — Gatekeeper will accept this bundle on any Mac.)"
fi

# Auto-install: replace /Applications/Ircle.app and relaunch. Opt out with
# `--no-install` or `BUILD_ONLY=1`; `--no-open` installs without relaunch.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    INSTALL_SH="$(dirname "$0")/install.sh"
    if [ -x "$INSTALL_SH" ]; then
        echo ""
        "$INSTALL_SH" $INSTALL_FLAGS
    fi
fi
