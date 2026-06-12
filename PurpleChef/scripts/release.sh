#!/bin/bash
# Purple Chef release — macOS side + tag that triggers the Windows CI build.
#
#   scripts/release.sh            # release the version in package.json
#   scripts/release.sh 1.2.3      # same, but assert package.json says 1.2.3
#
# What it does (in order):
#   1. Pre-flight: clean pushed main, version/CHANGELOG consistency, tests,
#      typecheck, Developer ID cert, notarization credentials, gh auth.
#   2. `npm run dist:mac` — universal2 .app, Developer-ID-signed, notarized
#      via scripts/notarize.cjs (NOTARIZE_PROFILE keychain profile), stapled,
#      packed into DMG + ZIP.
#   3. Verify: codesign --strict, Gatekeeper spctl assess, staple the DMG.
#   4. Tag `purplechef-v<version>` and push it — GitHub Actions
#      (.github/workflows/release-purplechef.yml) builds the Windows NSIS
#      installer and publishes the release once it's attached.
#   5. Create/reuse the draft GitHub release and upload the mac artifacts.
#
# See RELEASING.md for the one-time machine setup.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Purple Chef"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
fail() { echo "❌ $1" >&2; exit 1; }

PKG_VERSION=$(node -p "require('./package.json').version")
VERSION="${1:-$PKG_VERSION}"
[ "$VERSION" = "$PKG_VERSION" ] || fail "package.json says $PKG_VERSION but you asked for $VERSION — bump first."
TAG="purplechef-v${VERSION}"

grep -q "^## ${VERSION} " CHANGELOG.md || grep -q "^## ${VERSION}$" CHANGELOG.md \
  || fail "CHANGELOG.md has no '## ${VERSION}' entry — write the changelog first."

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || fail "releases cut from main only (on '$BRANCH')."
[ -z "$(git status --porcelain -- .)" ] || fail "PurpleChef working tree is dirty — commit first."
git fetch origin main --quiet
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || fail "local main != origin/main — push (or pull) first."
git rev-parse "refs/tags/${TAG}" >/dev/null 2>&1 && fail "tag ${TAG} already exists."

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || fail "no 'Developer ID Application' identity in the keychain."
if [ -z "${NOTARIZE_PROFILE:-}" ] && [ -z "${APPLE_ID:-}" ]; then
  fail "no notarization credentials: export NOTARIZE_PROFILE (notarytool keychain profile) or the APPLE_ID trio."
fi
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated (gh auth login)."

echo "==> Pre-flight: tests + typecheck"
npm test
npm run typecheck

# ---------------------------------------------------------------------------
# Build, sign, notarize, staple
# ---------------------------------------------------------------------------
echo "==> Building universal2 DMG (sign + notarize via afterSign hook)"
rm -rf dist
npm run dist:mac

APP="dist/mac-universal/${APP_NAME}.app"
DMG="dist/${APP_NAME}-${VERSION}-universal.dmg"
ZIP="dist/${APP_NAME}-${VERSION}-universal-mac.zip"
[ -d "$APP" ] || fail "built app not found at $APP"
[ -f "$DMG" ] || fail "DMG not found at $DMG"
[ -f "$ZIP" ] || fail "ZIP not found at $ZIP"

echo "==> Verifying signature + notarization"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Stapling the DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# ---------------------------------------------------------------------------
# Tag → CI (Windows) + upload mac artifacts
# ---------------------------------------------------------------------------
echo "==> Tagging ${TAG} and pushing (triggers the Windows CI build)"
git tag -a "$TAG" -m "${APP_NAME} ${VERSION}"
git push origin "refs/tags/${TAG}"

echo "==> Creating/reusing the draft release and uploading mac artifacts"
if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --draft --title "${APP_NAME} ${TAG}" --notes \
"${APP_NAME} ${VERSION} — the cooking showdown, for macOS and Windows.

**macOS:** download \`${APP_NAME}-${VERSION}-universal.dmg\` below (Apple Silicon + Intel, signed & notarized).
**Windows:** download the \`${APP_NAME} Setup ${VERSION}.exe\` installer. It is not code-signed yet, so SmartScreen may warn on first run — click **More info → Run anyway**.

See CHANGELOG.md for what's new." \
    2>/dev/null || true   # CI's create-release job may have won the race; uploads below still land.
fi
gh release upload "$TAG" "$DMG" "$ZIP" --clobber
[ -f "dist/${APP_NAME}-${VERSION}-universal.dmg.blockmap" ] \
  && gh release upload "$TAG" "dist/${APP_NAME}-${VERSION}-universal.dmg.blockmap" --clobber
[ -f "dist/latest-mac.yml" ] && gh release upload "$TAG" "dist/latest-mac.yml" --clobber

cat <<EOF

✅ macOS side done: ${DMG} (notarized + stapled) uploaded to ${TAG}.

GitHub Actions is now building the Windows installer; the workflow flips the
release from draft → published once it's attached. Watch it with:

    gh run list --workflow release-purplechef.yml
    gh release view ${TAG}
EOF
