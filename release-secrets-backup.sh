#!/usr/bin/env bash
# release-secrets-backup.sh — export this Mac's PhantomLives release secrets into a
# structured bundle you can hand-carry into a 1Password vault (and restore later with
# release-secrets-restore.sh).
#
# WHAT IT BACKS UP (whatever exists on this Mac):
#   1. Sparkle EdDSA private key        — IRREPLACEABLE. Lose it and no future build can
#                                         sign an update that already-installed apps trust.
#   2. Developer ID identity (.p12)     — cert + private key (re-downloadable from Apple, but
#                                         back it up so you never depend on that).
#   3. Signing / login keychain pws     — the ~/.config/purple-signing/*-pw unlock files.
#   4. gh auth token                    — for release uploads (recreatable).
#   5. Notary reference                 — Apple ID / Team ID / profile name. The app-specific
#                                         password is NOT machine-extractable; note it manually.
#
# SAFETY:
#   - Writes ONLY to the output dir (default ~/Downloads/…), never inside the repo.
#   - Refuses to write into a git work tree. chmod 700 dir / 600 files.
#   - Prints paths + confirmations only — never secret VALUES.
#   - Reminds you to DELETE the bundle once it's in 1Password.
#
# USAGE:
#   ./release-secrets-backup.sh [OUTPUT_DIR]
#   MIRROR_APP=PurpleMirror ./release-secrets-backup.sh     # app whose .build has Sparkle tools
set -euo pipefail

# ---- config / discovery -----------------------------------------------------
TS="$(date +%Y%m%d-%H%M%S)"
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
OUT_DEFAULT="$HOME/Downloads/phantomlives-release-secrets/${HOST}-${TS}"
OUT="${1:-$OUT_DEFAULT}"

CFG="$HOME/.config/purple-signing"
SIGN_KC="$HOME/Library/Keychains/purple-signing.keychain-db"
SIGN_KC_PW="$CFG/keychain-pw"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
LOGIN_KC_PW="$CFG/login-pw"

# Apple/release identity (public / reference values — safe to hard-code)
APPLE_ID_DEFAULT="robert.olen@icloud.com"
TEAM_ID_DEFAULT="SRKV8T38CD"
NOTARY_PROFILE_DEFAULT="PurpleDedup-Notary"
SPARKLE_PUBKEY_EXPECTED="2q4I3WNk7qQbidXEO/Jo/U3+t2ODS9x+e3/Wqt+ClQQ="

note() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- refuse to write inside the repo ----------------------------------------
REPO_TOP="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || true)"
OUT_ABS="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd || echo "$OUT")/$(basename "$OUT")"
if [ -n "$REPO_TOP" ]; then
  case "$OUT_ABS" in
    "$REPO_TOP"|"$REPO_TOP"/*)
      die "refusing to write secrets inside the git repo ($REPO_TOP). Pick an OUTPUT_DIR outside it." ;;
  esac
fi

mkdir -p "$OUT"; chmod 700 "$OUT"
echo "== PhantomLives release-secrets backup =="
echo "   host:   $HOST"
echo "   bundle: $OUT"
echo

MANIFEST="$OUT/manifest.env"
: > "$MANIFEST"; chmod 600 "$MANIFEST"
{
  echo "# PhantomLives release secrets — reference fields (non-file)."
  echo "# Store these as fields on the 1Password item; attach the files alongside."
  echo "BACKUP_HOST=$HOST"
  echo "BACKUP_DATE=$TS"
  echo "APPLE_ID=$APPLE_ID_DEFAULT"
  echo "TEAM_ID=$TEAM_ID_DEFAULT"
  echo "NOTARY_PROFILE=$NOTARY_PROFILE_DEFAULT"
  echo "SPARKLE_PUBLIC_KEY=$SPARKLE_PUBKEY_EXPECTED"
} >> "$MANIFEST"

BACKED_UP=(); MISSING=()

# ---- 1. Sparkle EdDSA private key (CRITICAL) --------------------------------
echo "-- Sparkle EdDSA private key --"
GK=""
MIRROR_APP="${MIRROR_APP:-PurpleMirror}"
for base in "$(dirname "$0")/$MIRROR_APP" "$(dirname "$0")"/*; do
  cand="$(find "$base/.build/artifacts/sparkle" -type f -name generate_keys 2>/dev/null | head -1)"
  [ -n "$cand" ] && { GK="$cand"; break; }
done
if [ -z "$GK" ]; then
  warn "generate_keys not found under any .build/artifacts/sparkle — run 'swift package resolve' in $MIRROR_APP first."
  MISSING+=("sparkle-ed25519-private.key (generate_keys tool missing)")
else
  [ -f "$LOGIN_KC_PW" ] && security unlock-keychain -p "$(cat "$LOGIN_KC_PW")" "$LOGIN_KC" 2>/dev/null || true
  if "$GK" -x "$OUT/sparkle-ed25519-private.key" 2>/tmp/pm-sparkle.err; then
    chmod 600 "$OUT/sparkle-ed25519-private.key"
    got="$("$GK" -p 2>/dev/null | tail -1)"
    if [ "$got" = "$SPARKLE_PUBKEY_EXPECTED" ]; then
      note "exported ✓  (public key matches canonical)"
    else
      warn "exported, but public key is '$got' — NOT the canonical key. Verify before trusting this backup."
    fi
    BACKED_UP+=("sparkle-ed25519-private.key")
  else
    warn "generate_keys -x failed: $(cat /tmp/pm-sparkle.err 2>/dev/null). (Login keychain locked? Run at the Mac's own Terminal.)"
    MISSING+=("sparkle-ed25519-private.key (export failed)")
  fi
fi

# ---- 2. Developer ID identity (.p12) ----------------------------------------
echo "-- Developer ID identity (.p12) --"
if [ -f "$SIGN_KC" ] && [ -f "$SIGN_KC_PW" ]; then
  security unlock-keychain -p "$(cat "$SIGN_KC_PW")" "$SIGN_KC" 2>/dev/null || true
  P12PW="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 28)"
  if security export -k "$SIGN_KC" -t identities -f pkcs12 -P "$P12PW" -o "$OUT/devid-identity.p12" 2>/tmp/pm-p12.err; then
    chmod 600 "$OUT/devid-identity.p12"
    echo "P12_PASSWORD=$P12PW" >> "$MANIFEST"
    note "exported ✓  (import password recorded in manifest.env as P12_PASSWORD)"
    BACKED_UP+=("devid-identity.p12")
  else
    warn "security export failed: $(cat /tmp/pm-p12.err 2>/dev/null). A keychain GUI prompt may need clicking — run at the Mac's own Terminal."
    MISSING+=("devid-identity.p12 (export failed)")
  fi
else
  warn "no signing keychain ($SIGN_KC) — skipping .p12."
  MISSING+=("devid-identity.p12 (signing keychain absent)")
fi

# ---- 3. Keychain-unlock password files --------------------------------------
echo "-- keychain unlock password files --"
for pair in "keychain-pw:signing-keychain-pw.txt" "login-pw:login-keychain-pw.txt"; do
  src="$CFG/${pair%%:*}"; dst="$OUT/${pair##*:}"
  if [ -f "$src" ]; then cp "$src" "$dst"; chmod 600 "$dst"; note "copied ${pair##*:} ✓"; BACKED_UP+=("${pair##*:}")
  else MISSING+=("${pair##*:} (not present on this Mac)"); fi
done

# ---- 4. gh auth token -------------------------------------------------------
echo "-- gh auth token --"
if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
  gh auth token > "$OUT/gh-token.txt"; chmod 600 "$OUT/gh-token.txt"
  note "exported ✓  (recreatable via 'gh auth login' — convenience only)"
  BACKED_UP+=("gh-token.txt")
else
  MISSING+=("gh-token.txt (gh not authenticated)")
fi

# ---- 5. Notary reference (app-specific pw is manual) ------------------------
cat > "$OUT/notary-reference.txt" <<EOF
notarytool credential profile: $NOTARY_PROFILE_DEFAULT
  Apple ID:  $APPLE_ID_DEFAULT
  Team ID:   $TEAM_ID_DEFAULT
  App-specific password: NOT machine-extractable — paste yours here in 1Password,
    or recreate any time at appleid.apple.com -> Sign-In and Security -> App-Specific Passwords.
Restore with:  xcrun notarytool store-credentials $NOTARY_PROFILE_DEFAULT \\
                 --apple-id $APPLE_ID_DEFAULT --team-id $TEAM_ID_DEFAULT
EOF
chmod 600 "$OUT/notary-reference.txt"; BACKED_UP+=("notary-reference.txt")

# ---- README + summary -------------------------------------------------------
cp "$(dirname "$0")/docs/release-secrets-backup.md" "$OUT/README-RESTORE.md" 2>/dev/null || \
  echo "See docs/release-secrets-backup.md in the repo for restore steps." > "$OUT/README-RESTORE.md"
chmod 600 "$OUT/README-RESTORE.md"

echo
echo "== Bundle ready: $OUT =="
echo "   Backed up:"; for f in "${BACKED_UP[@]}"; do echo "     ✓ $f"; done
if [ "${#MISSING[@]}" -gt 0 ]; then echo "   Not captured:"; for f in "${MISSING[@]}"; do echo "     - $f"; done; fi
cat <<EOF

   NEXT — put it in 1Password, then delete the bundle:
     1. Create a 1Password item "PhantomLives Release Secrets ($HOST)".
     2. Attach every file in the bundle as a document.
     3. Copy the KEY=VALUE lines from manifest.env into the item's fields
        (especially P12_PASSWORD — the .p12 is useless without it).
     4. Paste your notary app-specific password into the item (see notary-reference.txt).
     5. Securely delete the bundle:   rm -rfP "$OUT"

   Restore onto a fresh Mac:   ./release-secrets-restore.sh <bundle-dir>
EOF
