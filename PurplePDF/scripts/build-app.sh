#!/usr/bin/env bash
# Build Purple PDF on macOS (universal2 .dmg).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Regenerating icons"
python3 build/make_icon.py

echo "==> Installing dependencies"
npm install --silent

echo "==> Building (mac, universal)"
npm run dist:mac

echo "==> Done. Artifacts in ./dist"
ls -lh dist/ || true
