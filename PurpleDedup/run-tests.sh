#!/usr/bin/env bash
# Runs the PurpleDedup test suite. With full Xcode active (`xcode-select -p` →
# /Applications/Xcode.app/...) plain `swift test` works directly. On a Command Line
# Tools-only machine the Testing.framework needs explicit -F / -rpath plumbing, which
# we add only in that case — applying those flags under Xcode breaks linking of the
# executable App target with `_Module_main` undefined symbol errors.
set -euo pipefail

cd "$(dirname "$0")"

ACTIVE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"

if [[ "$ACTIVE_DEV_DIR" == /Applications/Xcode*.app/* ]]; then
    exec swift test "$@"
fi

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
INTEROP_LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$INTEROP_LIB" \
        "$@"
else
    exec swift test "$@"
fi
