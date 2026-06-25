#!/usr/bin/env bash
# Deploy the single-file R-SICCI build to GitHub Pages so it lives at one
# bookmarkable URL that external participants/researchers can open in a browser.
#
# The SPA is fully client-side: hosting the static file transmits no participant
# answers anywhere (they are exported locally). Note two privacy caveats vs. the
# instrument's data-governance rules: (a) the survey content is publicly visible
# at the URL, and (b) GitHub Pages logs visitor IPs server-side.
#
# What it does:
#   1. builds dist/index.html (single self-contained file)
#   2. writes version.json (for a future in-app "update available" check)
#   3. pushes index.html + version.json to the public Pages repo
#
# One-time setup (auto-attempted below if the repo is missing):
#   gh repo create bronty13/rsicci --public --description 'R-SICCI survey (hosted)'
#   then enable Pages: Settings -> Pages -> Deploy from branch -> main / root
#   (The SOURCE stays in the PhantomLives monorepo; only the built artifact is
#    pushed to the separate Pages repo.)
#
# Usage:
#   ./scripts/deploy-pages.sh                 # deploy to the default repo
#   PAGES_REPO=me/rsicci ./scripts/deploy-pages.sh
set -euo pipefail

cd "$(dirname "$0")/.."

PAGES_REPO="${PAGES_REPO:-bronty13/rsicci}"
PAGES_DIR=".pages-deploy"   # gitignored local working clone of the Pages repo

VERSION="$(node -p "require('./package.json').version")"
RELEASED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "▶ Building R-SICCI v$VERSION …"
npm run build

# Obtain / refresh a local clone of the Pages repo; create it if it's missing.
if [ ! -d "$PAGES_DIR/.git" ]; then
  echo "▶ Cloning $PAGES_REPO → $PAGES_DIR …"
  if ! gh repo clone "$PAGES_REPO" "$PAGES_DIR" 2>/dev/null; then
    echo "▶ Repo not found — creating $PAGES_REPO …"
    gh repo create "$PAGES_REPO" --public --description 'R-SICCI survey (hosted, single-file SPA)'
    gh repo clone "$PAGES_REPO" "$PAGES_DIR"
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
git -C "$PAGES_DIR" commit -m "Deploy R-SICCI v$VERSION"
# `-u origin HEAD` makes the very first push work too (a freshly-created empty
# repo has an unborn branch with no upstream).
git -C "$PAGES_DIR" push -u origin HEAD

# Best-effort: enable Pages from main/root via the API (no-op if already on).
OWNER="${PAGES_REPO%%/*}"
NAME="${PAGES_REPO##*/}"
BRANCH="$(git -C "$PAGES_DIR" rev-parse --abbrev-ref HEAD)"
gh api -X POST "repos/$PAGES_REPO/pages" -f "source[branch]=$BRANCH" -f "source[path]=/" >/dev/null 2>&1 \
  && echo "▶ Enabled GitHub Pages ($BRANCH / root)." \
  || echo "▶ Pages may already be enabled (or enable it once: Settings → Pages → Deploy from branch → $BRANCH / root)."

echo ""
echo "✓ Deployed v$VERSION"
echo "  Live (after Pages finishes, ~1 min): https://$OWNER.github.io/$NAME/"
echo "  Bookmark that link; refresh to get future updates."
