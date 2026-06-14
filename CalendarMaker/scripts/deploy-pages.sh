#!/usr/bin/env bash
# Deploy the single-file CalendarMaker build to GitHub Pages so the user can keep
# one permanent bookmark and get updates just by refreshing.
#
# What it does:
#   1. builds dist/index.html
#   2. writes version.json (read by the in-app "update available" banner)
#   3. pushes index.html + version.json to the public Pages repo
#
# One-time setup (see docs/distribution.md):
#   - a PUBLIC repo to host the page (default: <you>/calendarmaker)
#   - GitHub Pages enabled on that repo: Settings → Pages → Deploy from branch →
#     main / root
#
# Usage:
#   ./scripts/deploy-pages.sh                 # deploy to the default repo
#   PAGES_REPO=me/calendarmaker ./scripts/deploy-pages.sh
set -euo pipefail

cd "$(dirname "$0")/.."

PAGES_REPO="${PAGES_REPO:-bronty13/calendarmaker}"
PAGES_DIR=".pages-deploy"   # gitignored local working clone of the Pages repo

VERSION="$(node -p "require('./package.json').version")"
RELEASED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "▶ Building CalendarMaker v$VERSION …"
npm run build

# Obtain / refresh a local clone of the Pages repo.
if [ ! -d "$PAGES_DIR/.git" ]; then
  echo "▶ Cloning $PAGES_REPO → $PAGES_DIR …"
  if ! gh repo clone "$PAGES_REPO" "$PAGES_DIR" 2>/dev/null; then
    echo "✗ Could not clone $PAGES_REPO."
    echo "  Create it first (one time):  gh repo create $PAGES_REPO --public --description 'CalendarMaker (hosted)'"
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
git -C "$PAGES_DIR" commit -m "Deploy CalendarMaker v$VERSION"
git -C "$PAGES_DIR" push

OWNER="${PAGES_REPO%%/*}"
NAME="${PAGES_REPO##*/}"
echo ""
echo "✓ Deployed v$VERSION"
echo "  Live (after Pages finishes, ~1 min): https://$OWNER.github.io/$NAME/"
echo "  Send that link once; the user bookmarks it and just refreshes to update."
