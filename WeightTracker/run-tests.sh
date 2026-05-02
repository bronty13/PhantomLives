#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
INTEROP_LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    swift test \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xswiftc -L -Xswiftc "$INTEROP_LIB" \
        -Xlinker -rpath -Xlinker "$INTEROP_LIB"
else
    swift test
fi
