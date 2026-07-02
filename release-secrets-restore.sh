#!/usr/bin/env bash
# release-secrets-restore.sh — rehydrate a Mac's PhantomLives release secrets from a bundle
# produced by release-secrets-backup.sh (which you keep in 1Password). Inverse of the backup.
#
# Run this on the TARGET Mac, at its own Terminal (login-keychain writes need the GUI session).
# It is idempotent-ish: re-importing a key that already matches is harmless.
#
# USAGE:
#   ./release-secrets-restore.sh <bundle-dir>
#   MIRROR_APP=PurpleMirror ./release-secrets-restore.sh <bundle-dir>
#
# Steps (each skipped if its file is absent from the bundle):
#   1. Sparkle EdDSA key  -> login keychain (generate_keys -f), verify pubkey.
#   2. Dev-ID .p12        -> dedicated purple-signing keychain (see docs/dev-id-signing-airy.md).
#   3. keychain pw files  -> ~/.config/purple-signing/{keychain-pw,login-pw}.
#   4. gh token           -> gh auth login --with-token.
#   5. notarytool profile -> interactive store-credentials (prompts for app-specific pw).
set -euo pipefail

BUNDLE="${1:?usage: release-secrets-restore.sh <bundle-dir>}"
[ -d "$BUNDLE" ] || { echo "no such bundle dir: $BUNDLE" >&2; exit 1; }
# shellcheck source=/dev/null disable=SC1091
[ -f "$BUNDLE/manifest.env" ] && source "$BUNDLE/manifest.env" || true

CFG="$HOME/.config/purple-signing"
SIGN_KC="$HOME/Library/Keychains/purple-signing.keychain-db"
MIRROR_APP="${MIRROR_APP:-PurpleMirror}"
SPARKLE_PUBKEY_EXPECTED="${SPARKLE_PUBLIC_KEY:-2q4I3WNk7qQbidXEO/Jo/U3+t2ODS9x+e3/Wqt+ClQQ=}"
note() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
mkdir -p "$CFG"; chmod 700 "$CFG"

echo "== Restoring PhantomLives release secrets from: $BUNDLE =="

# ---- 1. Sparkle key ---------------------------------------------------------
if [ -f "$BUNDLE/sparkle-ed25519-private.key" ]; then
  echo "-- Sparkle EdDSA key --"
  GK="$(find "$(dirname "$0")/$MIRROR_APP/.build/artifacts/sparkle" -type f -name generate_keys 2>/dev/null | head -1)"
  [ -z "$GK" ] && { ( cd "$(dirname "$0")/$MIRROR_APP" && swift package resolve >/dev/null 2>&1 ) || true; \
                    GK="$(find "$(dirname "$0")/$MIRROR_APP/.build/artifacts/sparkle" -type f -name generate_keys 2>/dev/null | head -1)"; }
  if [ -n "$GK" ]; then
    "$GK" -f "$BUNDLE/sparkle-ed25519-private.key"
    got="$("$GK" -p 2>/dev/null | tail -1)"
    if [ "$got" = "$SPARKLE_PUBKEY_EXPECTED" ]; then note "imported ✓  (pubkey matches canonical)"
    else warn "imported but pubkey '$got' != expected '$SPARKLE_PUBKEY_EXPECTED'"; fi
  else warn "generate_keys not found; resolve $MIRROR_APP and re-run."; fi
fi

# ---- 2. Dev-ID identity -----------------------------------------------------
if [ -f "$BUNDLE/devid-identity.p12" ]; then
  echo "-- Developer ID .p12 -> purple-signing keychain --"
  KCPW="$(cat "$BUNDLE/signing-keychain-pw.txt" 2>/dev/null || true)"
  [ -z "$KCPW" ] && { KCPW="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 28)"; warn "no signing-keychain-pw.txt in bundle — generated a fresh keychain password."; }
  if [ ! -f "$SIGN_KC" ]; then
    security create-keychain -p "$KCPW" "$SIGN_KC"
    security set-keychain-settings "$SIGN_KC"
  fi
  security unlock-keychain -p "$KCPW" "$SIGN_KC"
  security import "$BUNDLE/devid-identity.p12" -k "$SIGN_KC" -P "${P12_PASSWORD:?P12_PASSWORD missing from manifest.env}" \
    -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPW" "$SIGN_KC" >/dev/null
  # shellcheck disable=SC2046  # intentional: each existing keychain must be a separate arg
  security list-keychains -d user -s "$SIGN_KC" $(security list-keychains -d user | sed 's/"//g')
  printf '%s' "$KCPW" > "$CFG/keychain-pw"; chmod 600 "$CFG/keychain-pw"
  security find-identity -v -p codesigning "$SIGN_KC" | grep "Developer ID Application" && note "imported ✓"
fi

# ---- 3. login keychain pw file ----------------------------------------------
if [ -f "$BUNDLE/login-keychain-pw.txt" ]; then
  cp "$BUNDLE/login-keychain-pw.txt" "$CFG/login-pw"; chmod 600 "$CFG/login-pw"
  note "login-pw restored ✓"
fi

# ---- 4. gh token ------------------------------------------------------------
if [ -f "$BUNDLE/gh-token.txt" ] && command -v gh >/dev/null 2>&1; then
  echo "-- gh auth --"
  if gh auth login --with-token < "$BUNDLE/gh-token.txt"; then note "gh authenticated ✓"
  else warn "gh token rejected — run 'gh auth login' manually."; fi
fi

# ---- 5. notarytool profile (interactive) ------------------------------------
echo "-- notarytool profile (interactive: needs your app-specific password) --"
echo "   Run this now (prompts for the app-specific password from 1Password):"
echo "     xcrun notarytool store-credentials ${NOTARY_PROFILE:-PurpleDedup-Notary} \\"
echo "       --apple-id ${APPLE_ID:-robert.olen@icloud.com} --team-id ${TEAM_ID:-SRKV8T38CD}"

echo
echo "== Restore complete (bar the notarytool step above). Verify a release path with: =="
echo "   AIRY_SSH=... LOGIN_KC_PW_FILE=$CFG/login-pw ./release-on-airy.sh $MIRROR_APP  (see docs/releasing-on-airy.md)"
