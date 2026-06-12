#!/usr/bin/env bash
#
# PurpleMark release: build → notarize → DMG → Sparkle-sign → GitHub release →
# appcast. Mirrors PurpleIRC/Scripts/release.sh. Run from the PurpleMark dir.
#
# One-time per-Mac setup (see RELEASING.md):
#   - "Developer ID Application: Robert Olen (SRKV8T38CD)" cert in the login keychain
#   - a notarytool keychain profile (default: PurpleDedup-Notary)
#   - the shared Sparkle EdDSA *private* key in the login keychain
#   - `gh auth login`
#
# Env overrides:
#   NOTARIZE_PROFILE   notarytool keychain profile      (default PurpleDedup-Notary)
#   GITHUB_REPO        release repo                     (default bronty13/PhantomLives)
#   ALLOW_DIRTY=1      skip clean/pushed checks (dev experiments only)
#   ALLOW_UNNOTARIZED=1 skip notarization (Gatekeeper will warn; emergencies only)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="PurpleMark"
BUNDLE_ID="com.bronty13.PurpleMark"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-PurpleDedup-Notary}"
GITHUB_REPO="${GITHUB_REPO:-bronty13/PhantomLives}"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ] \
   && ! /usr/bin/xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

say() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- pre-flight
say "Pre-flight checks"

DEVID="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*\) ([0-9A-F]+) .*/\1/')"
[ -n "$DEVID" ] || die "No 'Developer ID Application' certificate in the login keychain. See RELEASING.md."

command -v gh >/dev/null || die "GitHub CLI 'gh' not found."
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run 'gh auth login'."

if [ "${ALLOW_UNNOTARIZED:-0}" != "1" ]; then
    xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" >/dev/null 2>&1 \
        || die "notarytool profile '$NOTARIZE_PROFILE' not found. Create it (see RELEASING.md) or set NOTARIZE_PROFILE."
fi

if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "Not on main."
    [ -z "$(git status --porcelain)" ] || die "Working tree dirty — commit/stash first (or ALLOW_DIRTY=1)."
    git fetch -q origin main
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "HEAD not pushed to origin/main."
fi

# ---------------------------------------------------------------- version
COMMIT_COUNT="$(git rev-list --count HEAD)"
SHORT_SHA="$(git rev-parse --short HEAD)"
SHORT_VERSION="${SHORT_VERSION:-1.1.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"
RELEASE_TAG="purplemark-v${SHORT_VERSION}"
say "Releasing $APP $SHORT_VERSION ($BUILD_NUMBER) → tag $RELEASE_TAG"

# ---------------------------------------------------------------- Sparkle bin
say "Resolving Sparkle tools"
SPM_DIR="$PWD/.build/spm"
xcodebuild -project "$APP.xcodeproj" -scheme "$APP" \
    -clonedSourcePackagesDirPath "$SPM_DIR" -resolvePackageDependencies >/dev/null
SIGN_UPDATE="$(find "$SPM_DIR/artifacts" -name sign_update -type f 2>/dev/null | head -1)"
[ -x "$SIGN_UPDATE" ] || die "Sparkle's sign_update tool not found under $SPM_DIR/artifacts."

# ---------------------------------------------------------------- build + sign
say "Building + signing (Developer ID, hardened runtime)"
SHORT_VERSION="$SHORT_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    CODESIGN_IDENTITY="$DEVID" ./build-app.sh --no-install

APP_PATH="$PWD/$APP.app"
[ -d "$APP_PATH" ] || die "Build did not produce $APP_PATH."
codesign --verify --deep --strict "$APP_PATH" || die "Signature verification failed."

OUT_DIR="$PWD/dist"
mkdir -p "$OUT_DIR"
DMG_NAME="$APP-$SHORT_VERSION.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

# ---------------------------------------------------------------- DMG
say "Building DMG"
STAGING="$(mktemp -d)/dmg"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/$APP.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
codesign --force --timestamp -s "$DEVID" "$DMG_PATH"

# ---------------------------------------------------------------- notarize
if [ "${ALLOW_UNNOTARIZED:-0}" != "1" ]; then
    say "Notarizing DMG (this can take a few minutes)"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait \
        || die "Notarization failed — check 'xcrun notarytool log' with the submission id above."
    xcrun stapler staple "$DMG_PATH" || die "Stapling the DMG failed."
    xcrun stapler validate "$DMG_PATH" || die "Stapler validation failed."
    spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" 2>&1 | grep -q "accepted" \
        && echo "Gatekeeper: accepted" || echo "Gatekeeper: (DMG check inconclusive; app inside is notarized)"
else
    echo "ALLOW_UNNOTARIZED=1 — skipping notarization."
fi

# ---------------------------------------------------------------- Sparkle sign
say "Signing the DMG for Sparkle (EdDSA)"
SIGN_FRAGMENT="$("$SIGN_UPDATE" "$DMG_PATH")"
[ -n "$SIGN_FRAGMENT" ] || die "sign_update produced no signature — is the Sparkle private key in your keychain?"
echo "  $SIGN_FRAGMENT"

# ---------------------------------------------------------------- GitHub release
say "Creating GitHub release $RELEASE_TAG"
NOTES_FILE="$(mktemp)"
{
    echo "$APP $SHORT_VERSION"
    echo
    echo "See [CHANGELOG.md](https://github.com/$GITHUB_REPO/blob/main/PurpleMark/CHANGELOG.md) for details."
} > "$NOTES_FILE"

gh release create "$RELEASE_TAG" \
    --repo "$GITHUB_REPO" \
    --title "$APP $SHORT_VERSION" \
    --notes-file "$NOTES_FILE" \
    --target "$(git rev-parse HEAD)" \
    "$DMG_PATH#$DMG_NAME"

# ---------------------------------------------------------------- appcast
say "Updating appcast.xml"
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$DMG_NAME"
PUBDATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
ITEM="        <item>
            <title>$APP $SHORT_VERSION</title>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[See CHANGELOG.md for details.]]></description>
            <enclosure
                url=\"$DOWNLOAD_URL\"
                ${SIGN_FRAGMENT}
                type=\"application/octet-stream\" />
        </item>"

# Insert the new <item> right after the <!-- ITEMS --> marker (newest first).
python3 - "$ITEM" <<'PY'
import sys, io
item = sys.argv[1]
path = "appcast.xml"
xml = io.open(path, encoding="utf-8").read()
marker = "<!-- ITEMS -->"
if marker not in xml:
    raise SystemExit("appcast.xml is missing the <!-- ITEMS --> marker")
xml = xml.replace(marker, marker + "\n" + item, 1)
io.open(path, "w", encoding="utf-8").write(xml)
print("appcast.xml updated")
PY

xmllint --noout appcast.xml || die "appcast.xml is not valid XML."

git add appcast.xml
git commit -q -m "$APP $SHORT_VERSION: appcast"
git push

say "Done. $APP $SHORT_VERSION released; appcast pushed. Users will be offered the update."
