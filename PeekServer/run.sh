#!/bin/bash
# Run PeekServer. Pure stdlib — needs only python3 (Command Line Tools) + macOS sips/qlmanage.
#   ./run.sh                 # serve using config.json (or defaults)
#   PEEKSERVER_CONFIG=x ./run.sh
set -euo pipefail
cd "$(dirname "$0")"
exec /usr/bin/env python3 -m peekserver "$@"
