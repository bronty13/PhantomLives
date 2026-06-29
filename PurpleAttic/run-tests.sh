#!/usr/bin/env bash
# Run the PurpleAttic test suite.
#
# `swift test` needs full Xcode for XCTest — the Command Line Tools toolchain ships no XCTest, so a
# plain `swift test` under CLT fails with "no such module 'XCTest'". This wrapper points
# DEVELOPER_DIR at Xcode (unless it's already selected) so the tests resolve. Mirrors the sibling
# subprojects' run-tests.sh. Pass-through args go to `swift test` (e.g. --filter RcloneServiceTests).
set -euo pipefail
cd "$(dirname "$0")"

DEV="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ -d "$DEV" ]; then
  export DEVELOPER_DIR="$DEV"
else
  echo "warning: $DEV not found; relying on the currently selected toolchain (xcode-select -p)." >&2
fi

exec swift test "$@"
