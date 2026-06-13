#!/bin/bash
# Formal release for PurpleMirror. Run from EITHER Mac (Vortex or MB14) — it uses
# whatever Developer ID cert + notarytool profile + Sparkle key that machine has.
#
# PurpleMirror auto-updates via Sparkle 2. A "release" is a notarized + stapled,
# zipped, EdDSA-signed .app, attached to a tagged GitHub release and announced in
# appcast.xml — which is what makes existing installs offer the update.
#
# Required (one-time per machine — see RELEASING.md):
#   NOTARIZE_PROFILE   notarytool keychain profile (default: PurpleDedup-Notary,
#                      the shared PhantomLives profile). Override via env.
#   SPARKLE_PUBLIC_KEY EdDSA public key (shared across PhantomLives apps), in your
#                      shell rc. The matching PRIVATE key must be in this Mac's
#                      Keychain so sign_update can sign the zip.
# Optional: GITHUB_REPO (default bronty13/PhantomLives), ALLOW_DIRTY=1, ALLOW_UNNOTARIZED=1.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="PurpleMirror"
GITHUB_REPO="${GITHUB_REPO:-bronty13/PhantomLives}"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-PurpleDedup-Notary}"

die() { echo "FATAL: $*" >&2; exit 1; }
note() { echo "  • $*"; }

echo "== Pre-flight =="

DEVID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '"Developer ID Application:' | head -1 \
    | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')"
[ -n "$DEVID" ] || die "no Developer ID Application certificate in the login keychain (see RELEASING.md)."
note "signing identity: $DEVID"

if xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" >/dev/null 2>&1; then
    note "notary profile: $NOTARIZE_PROFILE ✓"
elif [ "${ALLOW_UNNOTARIZED:-0}" = "1" ]; then
    echo "  ! notary profile '$NOTARIZE_PROFILE' not found — ALLOW_UNNOTARIZED=1, continuing (zip WILL trip Gatekeeper)."
    NOTARIZE_PROFILE=""
else
    die "notarytool profile '$NOTARIZE_PROFILE' not found (per-machine, lives in login Keychain). See RELEASING.md.
       Emergency escape: ALLOW_UNNOTARIZED=1."
fi

gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run \`gh auth login\`."
note "gh authenticated ✓"

# Sparkle key present + the Keychain private half matches it (else installed apps reject the update).
if [ -z "${SPARKLE_PUBLIC_KEY:-}" ] || [ "${SPARKLE_PUBLIC_KEY}" = "PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY" ]; then
    die "SPARKLE_PUBLIC_KEY is unset/placeholder. Export the shared PhantomLives public key (see RELEASING.md)."
fi
swift package resolve >/dev/null 2>&1 || true
SPARKLE_BIN="$(find .build/artifacts/sparkle/Sparkle/bin -maxdepth 1 -type d 2>/dev/null | head -1)"
[ -x "$SPARKLE_BIN/sign_update" ] || die "Sparkle sign_update not found under .build/artifacts. Run \`swift package resolve\`."
KEYCHAIN_PUB="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
if [ "$KEYCHAIN_PUB" != "$SPARKLE_PUBLIC_KEY" ]; then
    die "Sparkle key mismatch — Keychain private key ≠ SPARKLE_PUBLIC_KEY; installed apps would reject the update.
         Keychain public half:  ${KEYCHAIN_PUB:-<none>}
         SPARKLE_PUBLIC_KEY:    $SPARKLE_PUBLIC_KEY
       Import the canonical private key (generate_keys -f) — see RELEASING.md."
fi
note "Sparkle public key set; Keychain private key matches ✓"

if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    [ "$BRANCH" = "main" ] || die "not on main (on '$BRANCH'). (ALLOW_DIRTY=1 to override.)"
    [ -z "$(git status --porcelain -- .)" ] || die "PurpleMirror has uncommitted changes:
$(git status --short -- . | sed 's/^/         /')
       Commit or stash first. (ALLOW_DIRTY=1 to override.)"
    git fetch origin main --quiet
    LOCAL="$(git rev-parse @)"; REMOTE="$(git rev-parse @{u} 2>/dev/null || echo none)"
    [ "$LOCAL" = "$REMOTE" ] || die "HEAD not pushed to origin/main. Push first. (ALLOW_DIRTY=1 to override.)"
    note "on main, clean, pushed ✓"
else
    echo "  ! ALLOW_DIRTY=1 — skipping clean-tree / pushed checks."
fi

COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.1.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"
RELEASE_TAG="purplemirror-v${SHORT_VERSION}"

echo; echo "== Releasing $APP $SHORT_VERSION (build $BUILD_NUMBER, tag $RELEASE_TAG) =="
if git rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null \
   || gh release view "$RELEASE_TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    die "release/tag $RELEASE_TAG already exists. Make a new commit (bumps version) first."
fi

OUT_DIR="$HOME/Downloads/$APP release"; mkdir -p "$OUT_DIR"
ZIP_NAME="${APP}-${SHORT_VERSION}.zip"; ZIP_PATH="$OUT_DIR/$ZIP_NAME"

echo; echo "== Build + notarize =="
SHORT_VERSION="$SHORT_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    CODESIGN_IDENTITY="$DEVID" NOTARIZE_PROFILE="$NOTARIZE_PROFILE" \
    SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
    ./build-app.sh --no-install

echo; echo "== Verify =="
NOTARIZED="no"
if [ -n "$NOTARIZE_PROFILE" ]; then
    xcrun stapler validate "$APP.app" >/dev/null 2>&1 \
        || die "stapler validate failed — not notarized/stapled. See /tmp/pm-notarize.plist."
    note "stapler validate ✓"
    if spctl -a -vvv -t exec "$APP.app" 2>&1 | grep -q 'accepted'; then
        note "spctl: accepted ✓"; NOTARIZED="yes"
    fi
fi

echo; echo "== Package =="
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP.app" "$ZIP_PATH"
echo "  Wrote $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"
SIGN_FRAGMENT="$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" 2>/tmp/pm-sign.err)" \
    || die "sign_update failed — EdDSA private key not in this Mac's Keychain. $(cat /tmp/pm-sign.err 2>/dev/null)"
note "EdDSA-signed: $SIGN_FRAGMENT"

echo; echo "== GitHub release =="
extract_section() {
    awk -v needle="$1" '
        /^## / { if (grab) exit; if (index($0, needle)) { grab=1; print; next } }
        grab { print }' CHANGELOG.md
}
NOTES_FILE="$(mktemp)"
if extract_section "$SHORT_VERSION" > "$NOTES_FILE" && [ -s "$NOTES_FILE" ]; then
    note "notes from CHANGELOG heading matching $SHORT_VERSION"
elif extract_section "[Unreleased]" > "$NOTES_FILE" && [ -s "$NOTES_FILE" ]; then
    note "notes from CHANGELOG [Unreleased]"
else
    printf '%s\n\n%s\n' "$APP $SHORT_VERSION" "See CHANGELOG.md." > "$NOTES_FILE"
fi
printf '\n\n---\nNotarized: %s\n' "$NOTARIZED" >> "$NOTES_FILE"
gh release create "$RELEASE_TAG" --repo "$GITHUB_REPO" \
    --title "$APP $SHORT_VERSION" --notes-file "$NOTES_FILE" \
    --target "$(git rev-parse HEAD)" "$ZIP_PATH#$ZIP_NAME"
rm -f "$NOTES_FILE"

echo; echo "== Appcast =="
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${ZIP_NAME}"
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
ITEM_FILE="$(mktemp)"
cat > "$ITEM_FILE" <<EOF
        <item>
            <title>$APP $SHORT_VERSION</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[See CHANGELOG.md for details.]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                ${SIGN_FRAGMENT}
                type="application/octet-stream" />
        </item>
EOF
awk -v itemfile="$ITEM_FILE" '
    function emit() { while ((getline line < itemfile) > 0) print line; close(itemfile); done=1 }
    /^[[:space:]]*<item>/ && !done { emit() }
    /<\/channel>/ && !done       { emit() }
    { print }
' appcast.xml > appcast.xml.new && mv appcast.xml.new appcast.xml
rm -f "$ITEM_FILE"
xmllint --noout appcast.xml 2>/dev/null || die "appcast.xml malformed after insert — NOT committing."
note "prepended <item> for $SHORT_VERSION ✓"

git add appcast.xml
git commit -q -m "$APP $SHORT_VERSION: appcast"
git push -q origin main
note "appcast committed + pushed — update is live"

echo; echo "== Done =="
echo "  Release:     https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
echo "  Notarized:   $NOTARIZED"
echo "  Auto-update: existing installs see $SHORT_VERSION on next launch (or within 24h)."
