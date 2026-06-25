#!/usr/bin/env bash
# Run the full PII Redactor test suite (Node's built-in runner).
# Covers: detection engine, redactor, markdown renderer, CLI, sample data,
# and a build-integration check that rebuilds dist/ and asserts inlining.
set -euo pipefail
cd "$(dirname "$0")"
exec node --test tests/*.test.mjs
