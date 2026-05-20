#!/usr/bin/env bash
# Run Molly's Rust unit tests (backup module debounce / retention /
# auto-dir / list ordering, plus future modules).
#
# Frontend has no tests yet — Phase 0 ships the shell only.

set -euo pipefail
cd "$(dirname "$0")/src-tauri"
exec cargo test --lib "$@"
