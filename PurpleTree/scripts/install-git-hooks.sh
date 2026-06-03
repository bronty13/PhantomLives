#!/usr/bin/env bash
# Install the auto-bump pre-commit hook into the repo's .git/hooks dir.
# Re-run this script after cloning the repo.
#
# Unlike a single-project hook, this installs a *dispatching* pre-commit
# that runs every `*/scripts/bump-and-log.mjs` found under the repo root.
# Each bump script no-ops unless the staged change set touches its own
# subproject, so this is safe to share across PurpleTree, PurplePDF, and
# any future sibling — installing from any one of them yields the same
# universal hook rather than clobbering another project's.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_ROOT="$(cd "$PROJECT_ROOT" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$GIT_ROOT" ]; then
  echo "Not inside a git repository (cwd=$PROJECT_ROOT)" >&2
  exit 1
fi
HOOK_DIR="$GIT_ROOT/.git/hooks"
mkdir -p "$HOOK_DIR"
cat > "$HOOK_DIR/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# PhantomLives: per-subproject auto-bump patch + prepend changelog entry.
# Runs every subproject's bump-and-log.mjs; each no-ops unless its own
# files are staged. Set SKIP_BUMP=1 to bypass (useful for release commits).
set -e
[ "${SKIP_BUMP:-0}" = "1" ] && exit 0
command -v node >/dev/null 2>&1 || exit 0
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$GIT_ROOT" ] && exit 0
for SCRIPT in "$GIT_ROOT"/*/scripts/bump-and-log.mjs; do
  [ -f "$SCRIPT" ] && node "$SCRIPT" || true
done
HOOK
chmod +x "$HOOK_DIR/pre-commit"
echo "Installed dispatching pre-commit hook at $HOOK_DIR/pre-commit"
echo "  -> runs every <subproject>/scripts/bump-and-log.mjs under $GIT_ROOT"
