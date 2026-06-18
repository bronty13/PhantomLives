#!/usr/bin/env bash
# Deploy the single-file NFEditor build to GitHub Pages so it lives at one
# bookmarkable URL and updates for users on refresh (the in-app banner nudges them).
#
# What it does:
#   1. builds dist/index.html (single self-contained file)
#   2. writes version.json (read by the in-app "update available" banner)
#   3. pushes index.html + version.json to the public Pages repo
#
# One-time setup:
#   - a PUBLIC repo to host the page (default: bronty13/nfeditor)
#       gh repo create bronty13/nfeditor --public --description 'NFEditor (hosted)'
#   - enable Pages on it: Settings -> Pages -> Deploy from branch -> main / root
#   (NFEditor's SOURCE stays in the PhantomLives monorepo; only the built artifact
#    is pushed to the separate Pages repo. NFEditor and the sibling CalendarMaker use
#    distinct repos AND distinct localStorage key prefixes, so they never collide.)
#
# Usage:
#   ./scripts/deploy-pages.sh                 # deploy to the default repo
#   PAGES_REPO=me/nfeditor ./scripts/deploy-pages.sh
set -euo pipefail

cd "$(dirname "$0")/.."

PAGES_REPO="${PAGES_REPO:-bronty13/nfeditor}"
PAGES_DIR=".pages-deploy"   # gitignored local working clone of the Pages repo

VERSION="$(node -p "require('./package.json').version")"
RELEASED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "▶ Building NFEditor v$VERSION …"
npm run build

# Obtain / refresh a local clone of the Pages repo.
if [ ! -d "$PAGES_DIR/.git" ]; then
  echo "▶ Cloning $PAGES_REPO → $PAGES_DIR …"
  if ! gh repo clone "$PAGES_REPO" "$PAGES_DIR" 2>/dev/null; then
    echo "✗ Could not clone $PAGES_REPO."
    echo "  Create it first (one time):  gh repo create $PAGES_REPO --public --description 'NFEditor (hosted)'"
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
git -C "$PAGES_DIR" commit -m "Deploy NFEditor v$VERSION"
# `-u origin HEAD` makes the very first push work too (a freshly-created empty repo
# has an unborn branch with no upstream); later pushes are no-ops on the upstream.
git -C "$PAGES_DIR" push -u origin HEAD

OWNER="${PAGES_REPO%%/*}"
NAME="${PAGES_REPO##*/}"
echo ""
echo "✓ Deployed v$VERSION"
echo "  Live (after Pages finishes, ~1 min): https://$OWNER.github.io/$NAME/"
echo "  Bookmark that link; refresh to get future updates."
