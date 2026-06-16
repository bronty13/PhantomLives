#!/usr/bin/env bash
# Runs the PurplePeek test suite (XCTest). `swift build` for the app uses the active
# Command Line Tools toolchain, which can't locate XCTest — so for tests we point
# DEVELOPER_DIR at the full Xcode install if it's present (xcode-select stays unchanged).
set -euo pipefail
cd "$(dirname "$0")"

XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
if [[ -d "$XCODE_DEV/usr/bin" ]]; then
    export DEVELOPER_DIR="$XCODE_DEV"
else
    echo "note: full Xcode not found — 'swift test' may fail to locate XCTest under Command Line Tools." >&2
fi

exec swift test "$@"
