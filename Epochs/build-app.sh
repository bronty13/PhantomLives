#!/usr/bin/env bash
# Epochs build → install → relaunch, the PhantomLives .app default.
#   ./build-app.sh                build + install to /Applications + relaunch
#   ./build-app.sh --no-install   build only (package, don't install)
#   ./build-app.sh --no-open      build + install, don't relaunch
#   BUILD_ONLY=1 ./build-app.sh   alias for --no-install
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DO_INSTALL=1
OPEN_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --no-install) DO_INSTALL=0 ;;
    --no-open) OPEN_FLAG="--no-open" ;;
  esac
done
[[ "${BUILD_ONLY:-0}" == "1" ]] && DO_INSTALL=0

# First-run dependency install.
if [[ ! -d node_modules ]]; then
  echo "Installing dependencies…"
  npm install
fi

echo "Type-checking…"
npm run typecheck

echo "Running tests…"
npm test

echo "Building renderer + main (electron-vite)…"
npm run build

echo "Packaging ${PWD##*/}.app (electron-builder --dir)…"
npx electron-builder --mac dir

if [[ "${DO_INSTALL}" -eq 1 ]]; then
  ./install.sh ${OPEN_FLAG}
else
  echo "Built (not installed). Bundle is under dist/."
fi
