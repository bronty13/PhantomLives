#!/bin/bash
# Push convex/ functions to the embedded Purple Space backend.
#
# Reads the same convex-config.json the app uses (creating it — secret +
# derived admin key — if this runs before first launch). If the app is
# running, functions hot-deploy into it; otherwise a temporary backend is
# spawned against the same data dir for the push and stopped after.
#
# Called automatically by build-app.sh; safe to re-run anytime:
#     npm run deploy-functions
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/fetch-backend.sh

APP_SUPPORT="$HOME/Library/Application Support/Purple Space"
CONFIG="$APP_SUPPORT/convex-config.json"
BIN="$PWD/resources/convex-local-backend"
DATA_DIR="$APP_SUPPORT/convex"
mkdir -p "$DATA_DIR"

# Ensure config exists (same shape src/main/convexBackend.ts writes).
if [ ! -f "$CONFIG" ]; then
    echo "Creating convex-config.json (new install)..."
    SECRET=$(openssl rand -hex 32)
    ADMIN_KEY=$("$BIN" keygen admin-key --instance-name purple-space --instance-secret "$SECRET" | tail -1)
    node -e '
      const [, path, secret, adminKey] = process.argv; // -e: argv[0] is node itself
      require("fs").writeFileSync(path, JSON.stringify({
        instanceName: "purple-space", instanceSecret: secret, adminKey,
        port: 47800, sitePort: 47801,
        backendTag: require("fs").readFileSync("resources/.backend-tag", "utf8").trim()
      }, null, 2));
    ' "$CONFIG" "$SECRET" "$ADMIN_KEY"
fi

PORT=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).port' "$CONFIG")
SITE_PORT=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).sitePort' "$CONFIG")
SECRET=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).instanceSecret' "$CONFIG")
ADMIN_KEY=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).adminKey' "$CONFIG")

up() { curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/version"; }

TEMP_PID=""
cleanup() {
    if [ -n "$TEMP_PID" ]; then
        kill "$TEMP_PID" 2>/dev/null || true
        wait "$TEMP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if ! up; then
    echo "Starting temporary backend for the push..."
    "$BIN" \
        --interface 127.0.0.1 \
        --port "$PORT" \
        --site-proxy-port "$SITE_PORT" \
        --convex-origin "http://127.0.0.1:${PORT}" \
        --convex-site "http://127.0.0.1:${SITE_PORT}" \
        --instance-name purple-space \
        --instance-secret "$SECRET" \
        --local-storage "$DATA_DIR/convex_local_storage" \
        --disable-beacon \
        "$DATA_DIR/convex_local_backend.sqlite3" \
        >/dev/null 2>&1 &
    TEMP_PID=$!
    for _ in $(seq 1 240); do
        up && break
        if ! kill -0 "$TEMP_PID" 2>/dev/null; then
            echo "error: temporary backend exited during startup" >&2
            exit 1
        fi
        sleep 0.25
    done
    if ! up; then echo "error: backend did not become ready" >&2; exit 1; fi
fi

# The CLI refuses self-hosted env vars alongside CONVEX_DEPLOYMENT, which a
# stray `convex dev` anonymous run may have written to .env.local. Strip it.
if [ -f .env.local ] && grep -q '^CONVEX_DEPLOYMENT=' .env.local; then
    sed -i '' '/^CONVEX_DEPLOYMENT=/d' .env.local
fi

echo "Deploying convex/ functions to http://127.0.0.1:${PORT} ..."
CONVEX_SELF_HOSTED_URL="http://127.0.0.1:${PORT}" \
CONVEX_SELF_HOSTED_ADMIN_KEY="$ADMIN_KEY" \
npx convex deploy --yes

echo "Functions deployed."
