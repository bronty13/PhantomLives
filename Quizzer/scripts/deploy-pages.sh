#!/usr/bin/env bash
# Deploy the single-file Quizzer *creator* to GitHub Pages so you keep one
# permanent bookmark and get updates just by refreshing — and so your saved
# quizzes/wheels (IndexedDB, keyed to the page origin) survive every update.
#
# Only the CREATOR is hosted. Deployed quizzes/wheels are per-activity files the
# creator downloads for you to hand out; they are not published here.
#
# What it does:
#   1. asserts APP_VERSION (src/shared/appMeta.ts) == package.json version
#   2. builds the full pipeline → dist/index.html (the creator, single file)
#   3. restores the committed template stubs the build regenerated (keeps the
#      outer PhantomLives working tree clean — see README "two-bundle architecture")
#   4. writes version.json (read by the in-app "update available" banner)
#   5. pushes index.html + version.json to the public Pages repo
#
# One-time setup (see docs/distribution.md):
#   - a PUBLIC repo to host the page (default: <you>/quizzer)
#   - GitHub Pages enabled on it: Settings → Pages → Deploy from branch →
#     main / root
#
# Usage:
#   ./scripts/deploy-pages.sh                 # deploy to the default repo
#   PAGES_REPO=me/quizzer ./scripts/deploy-pages.sh
set -euo pipefail

cd "$(dirname "$0")/.."

PAGES_REPO="${PAGES_REPO:-bronty13/quizzer}"
PAGES_DIR=".pages-deploy"   # gitignored local working clone of the Pages repo

VERSION="$(node -p "require('./package.json').version")"
APP_VERSION="$(node -e "const fs=require('fs');const m=fs.readFileSync('src/shared/appMeta.ts','utf8').match(/APP_VERSION\s*=\s*'([^']+)'/);process.stdout.write(m?m[1]:'')")"
RELEASED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Guard: the in-app update banner compares APP_VERSION against version.json
# (derived from package.json). If they drift, the banner lies — so refuse.
if [ "$VERSION" != "$APP_VERSION" ]; then
  echo "✗ Version mismatch: package.json is $VERSION but src/shared/appMeta.ts APP_VERSION is $APP_VERSION."
  echo "  Make them equal (bump both), then re-run."
  exit 1
fi

echo "▶ Building Quizzer v$VERSION …"
npm run build

# The full build regenerates the committed player/wheel template stubs into built
# blobs. Restore them so the outer repo's working tree stays clean and the
# check:stubs guardrail passes. (The Pages repo only ever gets dist/index.html.)
echo "▶ Restoring template stubs …"
npm run restore:stubs

# Obtain / refresh a local clone of the Pages repo.
if [ ! -d "$PAGES_DIR/.git" ]; then
  echo "▶ Cloning $PAGES_REPO → $PAGES_DIR …"
  if ! gh repo clone "$PAGES_REPO" "$PAGES_DIR" 2>/dev/null; then
    echo "✗ Could not clone $PAGES_REPO."
    echo "  Create it first (one time):  gh repo create $PAGES_REPO --public --description 'Quizzer (hosted creator)'"
    echo "  then enable Pages: Settings → Pages → Deploy from branch → main / root"
    exit 1
  fi
else
  git -C "$PAGES_DIR" pull --ff-only || true
fi

echo "▶ Staging files …"
cp dist/index.html "$PAGES_DIR/index.html"
printf '{\n  "version": "%s",\n  "released": "%s"\n}\n' "$VERSION" "$RELEASED" > "$PAGES_DIR/version.json"
touch "$PAGES_DIR/.nojekyll"   # serve files verbatim (no Jekyll processing)

git -C "$PAGES_DIR" add -A
if git -C "$PAGES_DIR" diff --cached --quiet; then
  echo "✓ Nothing changed — already up to date."
  exit 0
fi
git -C "$PAGES_DIR" commit -m "Deploy Quizzer v$VERSION"
git -C "$PAGES_DIR" push

OWNER="${PAGES_REPO%%/*}"
NAME="${PAGES_REPO##*/}"
echo ""
echo "✓ Deployed v$VERSION"
echo "  Live (after Pages finishes, ~1 min): https://$OWNER.github.io/$NAME/"
echo "  Bookmark that link once; just refresh to get future updates."
