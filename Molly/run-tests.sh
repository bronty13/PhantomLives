#!/usr/bin/env bash
# Run Molly's full test suite — Rust (cargo) + frontend (vitest).
#
# Rust covers: backup behavior, camelCase contract for every Tauri
# boundary struct, migration smoke (in-memory SQLite applies every
# shipped migration), history/log BLOB round-trip, fsutil path contract.
#
# Frontend covers (1.7.3+): pure-function units — money parser,
# US-phone formatter, cadence engine, UID date-key formatter. No DOM /
# component tests yet (see OUT_OF_SCOPE.md for the Phase 8.5 stance on
# wider e2e coverage).

set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Rust tests"
(cd src-tauri && cargo test --lib "$@")

echo
echo "▶ Frontend tests"
pnpm test
