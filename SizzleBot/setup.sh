#!/usr/bin/env bash
# SizzleBot — Ollama setup script
# Installs Ollama (via Homebrew), starts the server, and pulls the default model.
# Safe to re-run; all steps are idempotent.

set -euo pipefail

DEFAULT_MODEL="${1:-dolphin-mistral}"
OLLAMA_BIN="/opt/homebrew/bin/ollama"
BREW_BIN="/opt/homebrew/bin/brew"

log()  { echo "[SizzleBot] $*"; }
ok()   { echo "[SizzleBot] ✓ $*"; }
fail() { echo "[SizzleBot] ✗ $*" >&2; exit 1; }

# ── 1. Homebrew ──────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    log "Homebrew not found. Installing…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || fail "Homebrew install failed. Please install it manually: https://brew.sh"
fi
ok "Homebrew ready"

# ── 2. Ollama binary ─────────────────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
    log "Installing Ollama via Homebrew…"
    brew install ollama || fail "Ollama install failed"
fi
ok "Ollama binary: $(ollama --version 2>/dev/null | head -1)"

# ── 3. Start Ollama server ────────────────────────────────────────────────────
if ! pgrep -x ollama &>/dev/null; then
    log "Starting Ollama server…"
    ollama serve &>/dev/null &
    disown $!
    # Wait up to 10 s for the server to accept connections
    for i in $(seq 1 20); do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            break
        fi
        sleep 0.5
    done
fi

if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    ok "Ollama server is running on localhost:11434"
else
    fail "Ollama server did not start. Try running 'ollama serve' manually."
fi

# ── 4. Pull default model ─────────────────────────────────────────────────────
INSTALLED=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')

if echo "$INSTALLED" | grep -q "^${DEFAULT_MODEL}"; then
    ok "Model '${DEFAULT_MODEL}' already installed"
else
    log "Pulling model '${DEFAULT_MODEL}' — this may take a few minutes…"
    ollama pull "$DEFAULT_MODEL" || fail "Failed to pull model '${DEFAULT_MODEL}'"
    ok "Model '${DEFAULT_MODEL}' ready"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SizzleBot is ready. Open SizzleBot.xcodeproj"
echo "  and press Run in Xcode."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
