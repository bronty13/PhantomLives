#!/bin/bash
# Run the apple-archiver test suite (stdlib only; no venv needed).
cd "$(dirname "$0")"
exec python3 test_apple_archiver.py
