#!/bin/bash
# Tests for release-on-airy.sh via --print-remote (no SSH, no side effects — runs anywhere).
set -uo pipefail
cd "$(dirname "$0")/.."
WRAP=./release-on-airy.sh
fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

OUT="$($WRAP --print-remote PurpleMirror)"
check "sources zprofile for release env" 'grep -q "source \"\$HOME/.zprofile\"" <<<"$OUT"'
# Regression: the zsh rc files must be sourced BEFORE `set -euo pipefail`, else a zsh-ism
# or unset-var ref in them aborts the whole release under bash strict mode (real-run bug).
check "sources rc files before strict mode" \
  '[ "$(grep -n "source \"\$HOME/.zshrc\"" <<<"$OUT" | head -1 | cut -d: -f1)" -lt \
     "$(grep -n "^set -euo pipefail" <<<"$OUT" | head -1 | cut -d: -f1)" ]'
check "syncs main before releasing"       'grep -q "git pull --ff-only origin \"main\"" <<<"$OUT"'
check "unlocks the signing keychain"       'grep -q "unlock-keychain.*purple-signing.keychain-db" <<<"$OUT"'
check "invokes the subproject release.sh"  'grep -q "PurpleMirror/Scripts/release.sh" <<<"$OUT"'
check "no login-keychain unlock by default" '! grep -q "login.keychain-db" <<<"$OUT"'

OUT2="$(LOGIN_KC_PW_FILE=/x/login-pw $WRAP --print-remote Ircle)"
check "unlocks login keychain when configured" 'grep -q "login.keychain-db" <<<"$OUT2"'

# release.sh consumes ALLOW_DIRTY as an ENV var → must be an export, not a positional arg.
OUT3="$(ALLOW_DIRTY=1 $WRAP --print-remote PurpleIRC --no-install)"
check "forwards ALLOW_DIRTY as an export"   'grep -q "^export ALLOW_DIRTY=" <<<"$OUT3"'
check "keeps --no-install as a positional"  'grep -qF "\"\$REL\" '\''--no-install'\''" <<<"$OUT3"'
check "does not pass ALLOW_DIRTY as an arg" "! grep -qE \"release.sh.* 'ALLOW_DIRTY=1'\" <<<\"\$OUT3\""

# quote-injection safety: a nasty value stays a single literal.
OUT4="$(SHORT_VERSION="1.0'; rm -rf /" $WRAP --print-remote PurpleMark)"
check "quotes hostile env safely" "grep -qF \"rm -rf /'\" <<<\"\$OUT4\""

# usage error without a subproject.
$WRAP --print-remote >/dev/null 2>&1; check "usage error exits 2" '[ $? -eq 2 ]'
# AIRY_SSH required for a real run.
(unset AIRY_SSH; $WRAP PurpleMirror >/dev/null 2>&1); check "missing AIRY_SSH exits 2" '[ $? -eq 2 ]'

exit $fail
