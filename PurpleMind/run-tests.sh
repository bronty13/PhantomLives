#!/usr/bin/env bash
# Run PurpleMind's full test suite — Rust (cargo) + frontend (vitest).
#
# Rust covers: backup debounce/retention/list/verify/auto-create (CLAUDE.md
# mandate), fsutil downloads_subdir contract, camelCase boundary contract,
# migration smoke (every shipped migration applies cleanly to a fresh
# in-memory SQLite), and migration immutability (hashes frozen post-ship).
#
# Frontend (vitest): pure-function units — auto-layout, markdown-outline
# round-trip, and map (de)serialize round-trip.

set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Rust tests"
(cd src-tauri && cargo test --lib "$@")

echo
echo "▶ Frontend tests"
pnpm test
