#!/usr/bin/env bash
# Tests/smoke.sh — end-to-end smoke test for MacSearchReplace.
# Exercises the snr CLI (and indirectly the SnRCore library) against
# synthetic fixtures. Designed to run without Xcode / swift-testing.

set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SNR="$ROOT/.build/debug/snr"

pass=0; fail=0; failed_tests=()

ok()   { echo "[ok]   $1"; pass=$((pass+1)); }
bad()  { echo "[FAIL] $1: $2" >&2; fail=$((fail+1)); failed_tests+=("$1"); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "==> Building snr"
swift build --product snr 2>&1 | tail -3
[ -x "$SNR" ] || { echo "snr binary not at $SNR" >&2; exit 2; }

WORK="$(mktemp -d /tmp/snr-smoke.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
echo "==> Workspace: $WORK"
backup_root="$HOME/Library/Application Support/MacSearchReplace/Backups"

# 1. literal multi-file search
mkdir -p "$WORK/t1"
echo "alpha bravo charlie" > "$WORK/t1/a.txt"
echo "delta echo foxtrot"  > "$WORK/t1/b.txt"
echo "alpha is here too"   > "$WORK/t1/c.log"
out=$("$SNR" search "alpha" "$WORK/t1" 2>&1) || true
n=$(printf '%s\n' "$out" | grep -c "alpha" || true)
[ "$n" -ge 2 ] && ok "literal-search-multi-file" || bad "literal-search-multi-file" "n=$n out=$out"

# 2. regex anchored
out=$("$SNR" search -r '^delta' "$WORK/t1" 2>&1) || true
echo "$out" | grep -q "delta echo" && ok "regex-search-anchored" || bad "regex-search-anchored" "$out"

# 3. case-insensitive
out=$("$SNR" search -i "ALPHA" "$WORK/t1" 2>&1) || true
n=$(printf '%s\n' "$out" | grep -ci "alpha" || true)
[ "$n" -ge 2 ] && ok "case-insensitive-search" || bad "case-insensitive-search" "n=$n"

# 4. replace + backup
mkdir -p "$WORK/t4"
echo "hello world" > "$WORK/t4/x.txt"
echo "hello there" > "$WORK/t4/y.txt"
"$SNR" replace "hello" "GOODBYE" "$WORK/t4" >/dev/null 2>&1 || true
if grep -q "GOODBYE world" "$WORK/t4/x.txt" && grep -q "GOODBYE there" "$WORK/t4/y.txt"; then
    ok "replace-literal-multi-file"
else
    bad "replace-literal-multi-file" "x=$(cat "$WORK/t4/x.txt") y=$(cat "$WORK/t4/y.txt")"
fi
latest=$(ls -t "$backup_root" 2>/dev/null | head -1 || true)
[ -n "$latest" ] && [ -d "$backup_root/$latest" ] \
    && ok "backup-session-created" || bad "backup-session-created" "no session"

# 5. dry-run
mkdir -p "$WORK/t5"
echo "keep me" > "$WORK/t5/z.txt"
b=$(shasum "$WORK/t5/z.txt" | awk '{print $1}')
"$SNR" replace --dry-run "keep" "DROP" "$WORK/t5" >/dev/null 2>&1 || true
a=$(shasum "$WORK/t5/z.txt" | awk '{print $1}')
[ "$b" = "$a" ] && ok "dry-run-no-mutation" || bad "dry-run-no-mutation" "checksum changed"

# 6. regex backreference
mkdir -p "$WORK/t6"
echo "foo123bar foo456baz" > "$WORK/t6/r.txt"
"$SNR" replace -r 'foo([0-9]+)' 'NUM-$1' "$WORK/t6" >/dev/null 2>&1 || true
grep -q "NUM-123bar NUM-456baz" "$WORK/t6/r.txt" \
    && ok "regex-replace-backref" || bad "regex-replace-backref" "$(cat "$WORK/t6/r.txt")"

# 7. include glob
mkdir -p "$WORK/t7"
echo "needle" > "$WORK/t7/find.txt"
echo "needle" > "$WORK/t7/skip.log"
out=$("$SNR" search --include '*.txt' "needle" "$WORK/t7" 2>&1) || true
if echo "$out" | grep -q "find.txt" && ! echo "$out" | grep -q "skip.log"; then
    ok "include-glob-filter"
else bad "include-glob-filter" "$out"
fi

# 8. exclude glob
out=$("$SNR" search --exclude '*.log' "needle" "$WORK/t7" 2>&1) || true
if echo "$out" | grep -q "find.txt" && ! echo "$out" | grep -q "skip.log"; then
    ok "exclude-glob-filter"
else bad "exclude-glob-filter" "$out"
fi

# 9. snrscript v1
mkdir -p "$WORK/t9"
echo "alpha bravo" > "$WORK/t9/a.txt"
cat > "$WORK/t9/v1.snrscript" <<EOF
{"version":1,"name":"v1","roots":["$WORK/t9"],"include":["*.txt"],"exclude":[],"honorGitignore":false,"followSymlinks":false,
 "steps":[{"type":"literal","search":"alpha","replace":"ALPHA","caseInsensitive":false,"multiline":false,"counter":false,"interpolatePathTokens":false}]}
EOF
"$SNR" run "$WORK/t9/v1.snrscript" >/dev/null 2>&1 || true
grep -q "ALPHA bravo" "$WORK/t9/a.txt" \
    && ok "snrscript-v1-roundtrip" || bad "snrscript-v1-roundtrip" "$(cat "$WORK/t9/a.txt")"

# 10. snrscript v2 per-step roots
mkdir -p "$WORK/t10/sub1" "$WORK/t10/sub2"
echo "fooA barA" > "$WORK/t10/sub1/x.txt"
echo "fooB barB" > "$WORK/t10/sub2/y.txt"
cat > "$WORK/t10/v2.snrscript" <<EOF
{"version":2,"name":"v2","roots":["$WORK/t10"],"include":["*.txt"],"exclude":[],"honorGitignore":false,"followSymlinks":false,
 "steps":[
  {"type":"literal","search":"foo","replace":"FOO","caseInsensitive":false,"multiline":false,"counter":false,"interpolatePathTokens":false,"roots":["$WORK/t10/sub1"]},
  {"type":"literal","search":"bar","replace":"BAR","caseInsensitive":false,"multiline":false,"counter":false,"interpolatePathTokens":false,"roots":["$WORK/t10/sub2"]}]}
EOF
"$SNR" run "$WORK/t10/v2.snrscript" >/dev/null 2>&1 || true
s1=$(cat "$WORK/t10/sub1/x.txt"); s2=$(cat "$WORK/t10/sub2/y.txt")
[ "$s1" = "FOOA barA" ] && [ "$s2" = "fooB BARB" ] \
    && ok "snrscript-v2-per-step-roots" || bad "snrscript-v2-per-step-roots" "s1='$s1' s2='$s2'"

# 11. touch updates mtime
mkdir -p "$WORK/t11"
echo "xx" > "$WORK/t11/file.txt"
touch -t 200001010000 "$WORK/t11/file.txt"
b=$(stat -f %m "$WORK/t11/file.txt")
"$SNR" touch "$WORK/t11/file.txt" >/dev/null 2>&1 || true
a=$(stat -f %m "$WORK/t11/file.txt")
[ "$b" -lt "$a" ] && ok "touch-updates-mtime" || bad "touch-updates-mtime" "$b -> $a"

# 12. PDF search (optional)
if have cupsfilter; then
    mkdir -p "$WORK/t12"
    echo "Invoice number 42 contains a TODO marker." > "$WORK/t12/doc.txt"
    cupsfilter "$WORK/t12/doc.txt" > "$WORK/t12/doc.pdf" 2>/dev/null || true
    if [ -s "$WORK/t12/doc.pdf" ]; then
        out=$("$SNR" pdf "Invoice" "$WORK/t12" 2>&1) || true
        echo "$out" | grep -qi "Invoice" \
            && ok "pdf-search" || bad "pdf-search" "$out"
    else
        echo "[skip] pdf-search (cupsfilter empty)"
    fi
else
    echo "[skip] pdf-search (cupsfilter unavailable)"
fi

# 13. restore from backup
mkdir -p "$WORK/t13"
echo "canary value 12345" > "$WORK/t13/canary.txt"
"$SNR" replace "canary" "MUTATED" "$WORK/t13" >/dev/null 2>&1 || true
session=$(ls -t "$backup_root" 2>/dev/null | head -1)
"$SNR" restore "$backup_root/$session" >/dev/null 2>&1 || true
grep -q "canary value 12345" "$WORK/t13/canary.txt" \
    && ok "restore-from-backup" || bad "restore-from-backup" "$(cat "$WORK/t13/canary.txt")"

# 14. help renders
"$SNR" --help 2>&1 | grep -qi "snr" \
    && ok "help-text-renders" || bad "help-text-renders" "no help"

# 15. unknown subcommand exits non-zero
if "$SNR" garbage-subcommand >/dev/null 2>&1; then
    bad "unknown-subcommand-exits-nonzero" "exit was 0"
else
    ok "unknown-subcommand-exits-nonzero"
fi

echo
echo "==================================================="
echo "Passed: $pass   Failed: $fail"
if [ "$fail" -gt 0 ]; then
    echo "Failed tests:"
    for t in "${failed_tests[@]}"; do echo "  - $t"; done
    exit 1
fi
echo "All smoke tests passed."
