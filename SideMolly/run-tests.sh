#!/usr/bin/env bash
# Run SideMolly's full test suite — Rust (cargo) + frontend (vitest).
#
# Rust covers: backup debounce/retention/list/verify/auto-create
# (CLAUDE.md mandate), fsutil downloads_subdir contract, camelCase
# boundary contract, migration smoke (every shipped migration applies
# cleanly to a fresh in-memory SQLite).
#
# Frontend (vitest): pure-function units. Phase 0 has just a smoke test;
# Phase 1 onward adds bundle-verify and manifest-parse tests.

set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Rust tests"
(cd src-tauri && cargo test --lib "$@")

echo
echo "▶ Frontend tests"
pnpm test
