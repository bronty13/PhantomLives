#!/bin/bash
#
# release-on-airy.sh — cut a formal release from the always-on runner (airy) over SSH,
# so a release doesn't tie up your workstation.
#
# It runs a subproject's own Scripts/release.sh on airy, after handling the two things
# that differ on a headless Mac:
#   1. KEYCHAINS. release.sh reads the Dev-ID cert via `security find-identity`, the
#      notarytool profile, and the Sparkle EdDSA key — all from keychains that are
#      LOCKED on a fresh SSH session. This wrapper unlocks the dedicated signing
#      keychain (purple-signing, set up per docs/dev-id-signing-airy.md — already in
#      the keychain search list, so find-identity sees the Dev-ID once it's unlocked)
#      and, if configured, the login keychain (where the notary profile + Sparkle key
#      live). No edit to any per-app release.sh is needed.
#   2. RELEASE ENV. SPARKLE_PUBLIC_KEY / NOTARIZE_PROFILE normally come from your shell
#      rc, but `ssh host cmd` is non-login/non-interactive and won't source it — so the
#      remote script sources ~/.zprofile + ~/.zshrc first.
#
# USAGE
#   AIRY_SSH=you@airy.local ./release-on-airy.sh <Subproject> [extra release.sh args]
#   ./release-on-airy.sh --print-remote <Subproject>   # print the remote script, don't connect
#
# ENV
#   AIRY_SSH         ssh target, e.g. you@airy.local  (required unless --print-remote)
#   AIRY_REPO        repo path on airy                (default: ~/dev/PhantomLives)
#   AIRY_BRANCH      branch to release from            (default: main — release.sh requires it)
#   SIGN_KC_PW_FILE  signing-keychain password file    (default: ~/.config/purple-signing/keychain-pw)
#   SIGN_KEYCHAIN    signing keychain                  (default: ~/Library/Keychains/purple-signing.keychain-db)
#   LOGIN_KC_PW_FILE if set, also unlock the login keychain (for notarytool + Sparkle reads)
set -euo pipefail

MODE=""
if [ "${1:-}" = "--print-remote" ]; then MODE="print"; shift; fi

SUBPROJECT="${1:-}"
[ -n "$SUBPROJECT" ] || { echo "usage: [AIRY_SSH=you@airy] $0 [--print-remote] <Subproject> [release.sh args]" >&2; exit 2; }
shift || true
EXTRA_ARGS=("$@")

AIRY_REPO="${AIRY_REPO:-\$HOME/dev/PhantomLives}"
AIRY_BRANCH="${AIRY_BRANCH:-main}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-\$HOME/Library/Keychains/purple-signing.keychain-db}"
SIGN_KC_PW_FILE="${SIGN_KC_PW_FILE:-\$HOME/.config/purple-signing/keychain-pw}"

# release.sh reads these as ENV VARS (not args). Forward any that are set in the
# caller's environment so `NOTARIZE_PROFILE=… ./release-on-airy.sh …` works, and they
# override what ~/.zprofile sets on airy.
PASSTHROUGH_ENV="GITHUB_REPO NOTARIZE_PROFILE SPARKLE_PUBLIC_KEY SHORT_VERSION BUILD_NUMBER ALLOW_DIRTY ALLOW_UNNOTARIZED"

# shell-quote a value as a single-quoted literal (safe for arbitrary content).
shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# Build the script that runs ON airy. Quote-safe: subproject, args, and forwarded env
# are embedded as single-quoted literals. Left unexpanded here ($HOME etc.) so they
# resolve on airy.
build_remote_script() {
  local args_str="" a
  for a in "${EXTRA_ARGS[@]:-}"; do
    [ -n "$a" ] && args_str+=" $(shq "$a")"
  done
  local exports="" v
  for v in $PASSTHROUGH_ENV; do
    if [ -n "${!v:-}" ]; then exports+="export $v=$(shq "${!v}")"$'\n'; fi
  done
  cat <<REMOTE
set -euo pipefail
# Load release env (SPARKLE_PUBLIC_KEY, NOTARIZE_PROFILE) — ssh non-login shell won't.
source "\$HOME/.zprofile" 2>/dev/null || true
source "\$HOME/.zshrc" 2>/dev/null || true
${exports}

cd "$AIRY_REPO"
echo "== airy: syncing $AIRY_BRANCH =="
git fetch origin "$AIRY_BRANCH" --quiet
git checkout "$AIRY_BRANCH" --quiet
git pull --ff-only origin "$AIRY_BRANCH" --quiet

# Unlock the dedicated signing keychain so find-identity/codesign work over SSH.
if [ -f "$SIGN_KC_PW_FILE" ] && [ -f "$SIGN_KEYCHAIN" ]; then
  echo "== airy: unlocking signing keychain =="
  security unlock-keychain -p "\$(cat "$SIGN_KC_PW_FILE")" "$SIGN_KEYCHAIN"
else
  echo "! signing keychain not set up ($SIGN_KEYCHAIN) — release.sh will look in the login keychain." >&2
fi
REMOTE
  # Optional login-keychain unlock (notary profile + Sparkle key live there).
  if [ -n "${LOGIN_KC_PW_FILE:-}" ]; then
    cat <<REMOTE
if [ -f "$LOGIN_KC_PW_FILE" ]; then
  echo "== airy: unlocking login keychain (notary + Sparkle) =="
  security unlock-keychain -p "\$(cat "$LOGIN_KC_PW_FILE")" "\$HOME/Library/Keychains/login.keychain-db"
fi
REMOTE
  fi
  cat <<REMOTE

REL="$SUBPROJECT/Scripts/release.sh"
[ -x "\$REL" ] || { echo "no executable \$REL on airy" >&2; exit 1; }
echo "== airy: \$REL$args_str =="
"\$REL"$args_str
REMOTE
}

REMOTE_SCRIPT="$(build_remote_script)"

if [ "$MODE" = "print" ]; then
  printf '%s\n' "$REMOTE_SCRIPT"
  exit 0
fi

[ -n "${AIRY_SSH:-}" ] || { echo "error: AIRY_SSH is unset (e.g. AIRY_SSH=you@airy.local)" >&2; exit 2; }

echo "→ releasing $SUBPROJECT on $AIRY_SSH"
# BatchMode: fail rather than hang on a password prompt (key auth only).
printf '%s' "$REMOTE_SCRIPT" | ssh -o BatchMode=yes "$AIRY_SSH" 'bash -s'
