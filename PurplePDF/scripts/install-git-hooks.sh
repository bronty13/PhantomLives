#!/usr/bin/env bash
# Install the auto-bump pre-commit hook into the repo's .git/hooks dir.
# Re-run this script after cloning the repo.
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
cat > "$HOOK_DIR/pre-commit" <<HOOK
#!/usr/bin/env bash
# Purple PDF: auto-bump patch + prepend changelog entry.
# Set SKIP_BUMP=1 to bypass (useful for release commits).
set -e
SCRIPT="$PROJECT_ROOT/scripts/bump-and-log.mjs"
if command -v node >/dev/null 2>&1 && [ -f "\$SCRIPT" ]; then
  node "\$SCRIPT" || true
fi
HOOK
chmod +x "$HOOK_DIR/pre-commit"
echo "Installed pre-commit hook at $HOOK_DIR/pre-commit"
echo "  -> runs $PROJECT_ROOT/scripts/bump-and-log.mjs"
