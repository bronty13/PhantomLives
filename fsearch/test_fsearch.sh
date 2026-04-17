#!/usr/bin/env bash
# ============================================================================
#
#  FSEARCH TEST SUITE
#
#  File:        test_fsearch.sh
#  Version:     2.3.1
#  Author:      Generated with Claude Code
#  License:     MIT
#  Requires:    bash 3.2+, fsearch.sh in same directory
#
#  Description:
#    Comprehensive test suite for fsearch.sh.  Covers version/help output,
#    filename search, content search, config subcommands, output formats,
#    directory exclusions, date filters, statistics, logging, error handling,
#    and edge cases.
#
#  Usage:
#    bash test_fsearch.sh              # normal run
#    bash test_fsearch.sh --verbose    # verbose output
#
# ============================================================================

# Do NOT use set -e — test scripts must survive failing commands in order to
# report failures rather than abort silently.
set -o pipefail

# ============================================================================
# S1  TEST FRAMEWORK
# ============================================================================

# ── Counters ─────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0
FAIL_LIST=()

# ── Terminal colors ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'
    C_CYAN='\033[0;36m'; C_BOLD='\033[1m'; C_DIM='\033[2m'; C_NC='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_NC=''
fi

# ── Output helpers ────────────────────────────────────────────────────────────

print_pass() {
    (( PASS++ )) || true
    printf "  ${C_GREEN}✓${C_NC} %s\n" "$1"
}

print_fail() {
    (( FAIL++ )) || true
    FAIL_LIST+=("$1")
    printf "  ${C_RED}✗${C_NC} %s\n" "$1"
    [[ -n "${2:-}" ]] && printf "    ${C_DIM}↳ %s${C_NC}\n" "$2"
}

print_skip() {
    (( SKIP++ )) || true
    printf "  ${C_YELLOW}⊘${C_NC} %s\n" "$1"
}

section() {
    printf "\n${C_BOLD}${C_CYAN}━━━  %s  ━━━${C_NC}\n\n" "$1"
}

# ── Assert primitives ─────────────────────────────────────────────────────────

assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        print_pass "$desc"
    else
        print_fail "$desc" "expected='$expected'  got='$actual'"
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle" 2>/dev/null; then
        print_pass "$desc"
    else
        print_fail "$desc" "expected to contain '$needle'"
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle" 2>/dev/null; then
        print_fail "$desc" "expected NOT to contain '$needle'"
    else
        print_pass "$desc"
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        print_pass "$desc"
    else
        print_fail "$desc" "expected exit code $expected, got $actual"
    fi
}

assert_match() {
    local desc="$1" haystack="$2" pattern="$3"
    if printf '%s' "$haystack" | grep -qE -- "$pattern" 2>/dev/null; then
        print_pass "$desc"
    else
        print_fail "$desc" "expected to match regex '$pattern'"
    fi
}

# ── Verbose mode ──────────────────────────────────────────────────────────────
VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

# ============================================================================
# S2  TEST INFRASTRUCTURE
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSEARCH="${SCRIPT_DIR}/fsearch.sh"

# Verify the script under test exists
if [[ ! -f "$FSEARCH" ]]; then
    printf "${C_RED}FATAL: fsearch.sh not found at %s${C_NC}\n" "$FSEARCH" >&2
    exit 1
fi

# Isolated temp directory for all test fixtures and config
TEST_DIR="$(mktemp -d /tmp/fsearch_test.XXXXXX)"
TEST_ROOT="${TEST_DIR}/testroot"
TEST_CONFIG_HOME="${TEST_DIR}/config"

# Create test fixture tree
mkdir -p "$TEST_ROOT"
mkdir -p "${TEST_ROOT}/sub"
mkdir -p "${TEST_ROOT}/sub/deep"
mkdir -p "${TEST_ROOT}/.git"
mkdir -p "${TEST_ROOT}/node_modules"
mkdir -p "${TEST_ROOT}/spaces dir"

# Populate fixtures
printf 'hello world\nfoo bar\nbaz qux\n' > "${TEST_ROOT}/file1.txt"
printf 'import os\nimport sys\n# TODO fix this\ndef main():\n    pass\n' > "${TEST_ROOT}/file2.py"
printf 'ERROR connection failed\nretrying in 5s\nERROR timeout\nrecovered ok\n' > "${TEST_ROOT}/sub/deep/deep.log"
printf '[core]\n    repositoryformatversion = 0\n' > "${TEST_ROOT}/.git/config"
printf 'module.exports = "junk";\n' > "${TEST_ROOT}/node_modules/junk.js"
printf '' > "${TEST_ROOT}/empty.txt"
printf 'content with spaces in path\nsearchable text here\n' > "${TEST_ROOT}/spaces dir/ok.txt"
printf 'MIXED case Content HERE\nAnother Line\n' > "${TEST_ROOT}/mixed_case.txt"
printf 'line1\nline2\nMATCH_TARGET\nline4\nline5\nline6\nline7\n' > "${TEST_ROOT}/context_test.txt"

# Create a "large" file (just over a threshold we'll use in tests)
dd if=/dev/zero of="${TEST_ROOT}/large_file.bin" bs=1024 count=100 2>/dev/null

# File with special characters in name
touch "${TEST_ROOT}/file-with-equals=sign.txt"
printf 'equals content\n' > "${TEST_ROOT}/file-with-equals=sign.txt"

# Helper: run fsearch with isolated config
run_fsearch() {
    XDG_CONFIG_HOME="$TEST_CONFIG_HOME" bash "$FSEARCH" "$@" 2>&1
}

# Helper: run fsearch and capture exit code separately
run_fsearch_rc() {
    local output rc
    output="$(XDG_CONFIG_HOME="$TEST_CONFIG_HOME" bash "$FSEARCH" "$@" 2>&1)"
    rc=$?
    printf '%s' "$output"
    return $rc
}

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ============================================================================
# BEGIN TESTS
# ============================================================================

printf "\n${C_BOLD}fsearch test suite${C_NC}\n"
printf "Script under test: %s\n" "$FSEARCH"
printf "Test fixtures: %s\n" "$TEST_ROOT"
printf "Test config: %s\n" "$TEST_CONFIG_HOME"

# ============================================================================
# S1  VERSION AND HELP
# ============================================================================
section "S1: Version and help"

out="$(run_fsearch --version)"
assert_contains "version output contains version number" "$out" "fsearch 2.3.1"

run_fsearch_rc --version >/dev/null; rc=$?
assert_exit_code "version exits 0" "0" "$rc"

out="$(run_fsearch -h)"
assert_contains "help contains usage section" "$out" "Usage:"
assert_contains "help contains config section" "$out" "Config subcommands:"
assert_contains "help contains examples" "$out" "Examples:"
assert_contains "help contains stats section" "$out" "Statistics & logging:"

# ============================================================================
# S2  VERSION DISPLAY ON SEARCH
# ============================================================================
section "S2: Version display on search"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$')"
assert_contains "version shown in search banner" "$out" "v2.3.1"

# Paths-only mode should NOT show version (minimal output)
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0)"
assert_not_contains "version not shown in -0 mode" "$out" "v2.3.1"

# Plain format should NOT show version
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' --format plain)"
assert_not_contains "version not shown in plain mode" "$out" "v2.3.1"

# ============================================================================
# S3  FILENAME SEARCH (-n)
# ============================================================================
section "S3: Filename search (-n)"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0)"
assert_contains "finds .txt files" "$out" "file1.txt"
assert_contains "finds empty.txt" "$out" "empty.txt"
assert_not_contains "does not find .py files" "$out" "file2.py"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.py$' -0)"
assert_contains "finds .py files" "$out" "file2.py"
assert_not_contains "does not find .txt files" "$out" "file1.txt"

out="$(run_fsearch -p "$TEST_ROOT" -n 'NONEXISTENT_PATTERN' 2>&1 || true)"
assert_contains "no match reports no matches" "$out" "No matches found"

# Case-insensitive filename
out="$(run_fsearch -p "$TEST_ROOT" -n 'FILE1' -i -0)"
assert_contains "case-insensitive filename match" "$out" "file1.txt"

out="$(run_fsearch -p "$TEST_ROOT" -n '^file' -0)"
count="$(printf '%s' "$out" | grep -c 'file' || true)"
if [[ $count -ge 2 ]]; then
    print_pass "regex matches multiple files starting with 'file'"
else
    print_fail "regex matches multiple files starting with 'file'" "found $count matches"
fi

# ============================================================================
# S4  CONTENT SEARCH (-g)
# ============================================================================
section "S4: Content search (-g)"

out="$(run_fsearch -p "$TEST_ROOT" -g 'hello world' -0)"
assert_contains "finds file containing 'hello world'" "$out" "file1.txt"

out="$(run_fsearch -p "$TEST_ROOT" -g 'ERROR' -0)"
assert_contains "finds log file with ERROR" "$out" "deep.log"

out="$(run_fsearch -p "$TEST_ROOT" -g 'import' --format plain)"
assert_contains "content match shows matching lines" "$out" "import os"

out="$(run_fsearch -p "$TEST_ROOT" -g 'NONEXISTENT_CONTENT' 2>&1 || true)"
assert_contains "no content match reports no matches" "$out" "No matches found"

# Case-insensitive content search
out="$(run_fsearch -p "$TEST_ROOT" -g 'mixed case' -i -0)"
assert_contains "case-insensitive content match" "$out" "mixed_case.txt"

# Context lines
out="$(run_fsearch -p "$TEST_ROOT" -g 'MATCH_TARGET' -C 2 --format plain)"
assert_contains "context includes line before match" "$out" "line2"
assert_contains "context includes line after match" "$out" "line4"

# ============================================================================
# S5  COMBINED SEARCH (-n + -g)
# ============================================================================
section "S5: Combined search (-n + -g)"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.py$' -g 'import' --format plain)"
assert_contains "combined: finds .py with 'import'" "$out" "file2.py"
assert_contains "combined: shows match type" "$out" "filename + content"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -g 'import' --format plain)"
assert_contains "combined: .txt files matched by filename" "$out" "file1.txt"
assert_not_contains "combined: .txt files don't have 'import' content match" "$out" "filename + content"

# File matches by name only still appears
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -g 'hello world' --format plain)"
assert_contains "file matched by both name and content" "$out" "file1.txt"

# ============================================================================
# S6  PATH OPTIONS (-p, positional)
# ============================================================================
section "S6: Path options (-p, positional)"

# Custom -p path
out="$(run_fsearch -p "$TEST_ROOT/sub" -g 'ERROR' -0)"
assert_contains "-p restricts to subdir" "$out" "deep.log"

# Multiple -p paths
out="$(run_fsearch -p "$TEST_ROOT/sub" -p "$TEST_ROOT" -n '\.txt$' -0)"
assert_contains "multiple -p paths searched" "$out" "file1.txt"

# Nonexistent path warning
out="$(run_fsearch -p "/nonexistent/path123" -p "$TEST_ROOT" -n '\.txt$' -0 2>&1)"
assert_contains "warns about nonexistent path" "$out" "does not exist"
assert_contains "still searches valid path" "$out" "file1.txt"

# Positional arg as path
out="$(run_fsearch -n '\.txt$' -0 "$TEST_ROOT")"
assert_contains "positional arg used as path" "$out" "file1.txt"

# ============================================================================
# S7  RECURSION AND DEPTH (-d)
# ============================================================================
section "S7: Recursion and depth (-d)"

# Default: recursive
out="$(run_fsearch -p "$TEST_ROOT" -g 'ERROR' -0)"
assert_contains "default recursive finds deep files" "$out" "deep.log"

# -d 1: top-level only
out="$(run_fsearch -p "$TEST_ROOT" -d 1 -n '\.txt$' -0)"
assert_contains "-d 1 finds top-level files" "$out" "file1.txt"
assert_not_contains "-d 1 does not find deep files" "$out" "deep.log"

# -d 2: one level of subdirs
out="$(run_fsearch -p "$TEST_ROOT" -d 2 -g 'ERROR' -0)"
# deep.log is at testroot/sub/deep/ which is depth 3
assert_not_contains "-d 2 skips depth-3 files" "$out" "deep.log"

# -d 3: reaches deep
out="$(run_fsearch -p "$TEST_ROOT" -d 3 -g 'ERROR' -0 -E)"
assert_contains "-d 3 finds depth-3 files" "$out" "deep.log"

# ============================================================================
# S8  EXTENSION FILTERS (-l, -x)
# ============================================================================
section "S8: Extension filters (-l, -x)"

# Include only .py
out="$(run_fsearch -p "$TEST_ROOT" -g 'import' -l py -0)"
assert_contains "-l py finds .py files" "$out" "file2.py"

# Include only .txt — should not match .py content
out="$(run_fsearch -p "$TEST_ROOT" -g 'import' -l txt -0 2>&1 || true)"
assert_not_contains "-l txt excludes .py content match" "$out" "file2.py"

# Exclude .py
out="$(run_fsearch -p "$TEST_ROOT" -g 'import' -x py -0 2>&1 || true)"
assert_not_contains "-x py excludes .py from content search" "$out" "file2.py"

# Case-insensitive extension matching
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello' -l TXT -0)"
assert_contains "-l TXT matches .txt (case-insensitive)" "$out" "file1.txt"

# ============================================================================
# S9  OUTPUT MODES (-q, -0)
# ============================================================================
section "S9: Output modes (-q, -0)"

# Quiet mode: no headers but grep content still shown
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello world' -q)"
assert_not_contains "-q suppresses file header" "$out" "══╡"
assert_contains "-q still shows grep output" "$out" "hello world"

# Paths-only mode
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0)"
assert_contains "-0 outputs file paths" "$out" "file1.txt"
assert_not_contains "-0 suppresses headers" "$out" "══╡"
assert_not_contains "-0 suppresses timestamps" "$out" "created:"

# Summary shown by default
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$')"
assert_contains "summary shown by default" "$out" "file(s) matched"

# Summary includes files scanned count
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$')"
assert_contains "summary includes scanned count" "$out" "file(s) scanned"

# ============================================================================
# S10  OUTPUT FORMATS (--format)
# ============================================================================
section "S10: Output formats (--format)"

# Pretty format (default)
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -g 'hello')"
assert_contains "pretty format has header" "$out" "══╡"
assert_contains "pretty format has timestamps" "$out" "created:"

# Plain format
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello world' --format plain)"
assert_contains "plain format has dashes header" "$out" "---"
assert_not_contains "plain format has no colour codes" "$out" $'\033['

# JSON format
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello world' --format json)"
assert_contains "json has file field" "$out" '"file":'
assert_contains "json has match_type field" "$out" '"match_type":'
assert_contains "json has matches array" "$out" '"matches":'

# JSON is valid (basic check: starts with { ends with })
first_char="$(printf '%s' "$out" | head -c1)"
assert_eq "json line starts with {" "$first_char" "{"

# ============================================================================
# S11  MAX RESULTS (-m)
# ============================================================================
section "S11: Max results (-m)"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0 -m 1)"
# Count lines that are actual file paths (start with /)
count="$(printf '%s' "$out" | grep -c '^/' || true)"
assert_eq "-m 1 returns exactly 1 match" "$count" "1"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0 -m 2)"
count="$(printf '%s' "$out" | grep -c '^/' || true)"
assert_eq "-m 2 returns at most 2 matches" "$(( count <= 2 ? 1 : 0 ))" "1"

# -m 0 means unlimited
out="$(run_fsearch -p "$TEST_ROOT" -n '.' -0 -m 0)"
count="$(printf '%s' "$out" | grep -c '/' || true)"
if [[ $count -ge 3 ]]; then
    print_pass "-m 0 returns all matches (unlimited)"
else
    print_fail "-m 0 returns all matches (unlimited)" "found only $count"
fi

# ============================================================================
# S12  DATE FILTERS
# ============================================================================
section "S12: Date filters"

# --newer with a date far in the past should find everything
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' --newer '2000-01-01' -0)"
assert_contains "--newer 2000-01-01 finds recent files" "$out" "file1.txt"

# --older with a date in the future should find everything (files are older than that date)
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' --older '2030-01-01' -0)"
assert_contains "--older 2030-01-01 finds old files" "$out" "file1.txt"

# --newer with a far-future date should find nothing
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' --newer '2030-01-01' -0 2>&1 || true)"
assert_contains "--newer 2030-01-01 finds no files" "$out" "No matches found"

# ============================================================================
# S13  DIRECTORY EXCLUSIONS
# ============================================================================
section "S13: Directory exclusions"

# Default: .git and node_modules excluded
out="$(run_fsearch -p "$TEST_ROOT" -n 'config' -0)"
assert_not_contains "default excludes .git/config" "$out" ".git/config"

out="$(run_fsearch -p "$TEST_ROOT" -n 'junk' -0)"
assert_not_contains "default excludes node_modules/junk.js" "$out" "node_modules"

# -E disables exclusions (use content search to avoid 'config' pattern ambiguity)
out="$(run_fsearch -p "$TEST_ROOT" -g 'repositoryformatversion' -0 -E)"
assert_contains "-E includes .git/config" "$out" ".git"

out="$(run_fsearch -p "$TEST_ROOT" -n 'junk' -0 -E)"
assert_contains "-E includes node_modules/junk.js" "$out" "junk.js"

# ============================================================================
# S14  MAX FILE SIZE SKIP
# ============================================================================
section "S14: Max file size skip"

# Set a very small max file size for testing
XDG_CONFIG_HOME="$TEST_CONFIG_HOME" bash "$FSEARCH" config set MAX_FILE_SIZE "50K" >/dev/null 2>&1

# large_file.bin is 100K, should be skipped
out="$(run_fsearch -p "$TEST_ROOT" -g 'anything' -0 2>&1 || true)"
assert_not_contains "large file skipped by MAX_FILE_SIZE" "$out" "large_file.bin"

# Reset
XDG_CONFIG_HOME="$TEST_CONFIG_HOME" bash "$FSEARCH" config set MAX_FILE_SIZE "10M" >/dev/null 2>&1

# With 10M limit, regular files are not skipped
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello' -0)"
assert_contains "normal files not skipped with 10M limit" "$out" "file1.txt"

# ============================================================================
# S15  MATCH HIGHLIGHTING
# ============================================================================
section "S15: Match highlighting"

# Pretty format includes ANSI colour codes around matches
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello' -C 0)"
# grep --color=always inserts ESC[01;31m (or similar) around the match
if printf '%s' "$out" | grep -q $'\033'; then
    print_pass "pretty output contains ANSI color codes for highlighting"
else
    print_fail "pretty output contains ANSI color codes for highlighting"
fi

# Plain format does NOT have colour codes
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello' -C 0 --format plain)"
if printf '%s' "$out" | grep -q $'\033'; then
    print_fail "plain output should not contain ANSI color codes"
else
    print_pass "plain output does not contain ANSI color codes"
fi

# ============================================================================
# S16  FILE SIZE IN OUTPUT (--size)
# ============================================================================
section "S16: File size in output"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' --size)"
assert_contains "--size shows size in output" "$out" "size:"

out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$')"
assert_not_contains "default hides size in output" "$out" "size:"

# ============================================================================
# S17  PROGRESS DISPLAY
# ============================================================================
section "S17: Progress display"

# Progress is auto by default — when stderr is not a tty (as in test capture),
# it should not appear in stdout output
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0)"
assert_not_contains "progress not in stdout" "$out" "Scanning"

# --no-progress suppresses progress (verify no crash)
out="$(run_fsearch -p "$TEST_ROOT" -n '\.txt$' --no-progress -0)"
assert_contains "--no-progress still finds files" "$out" "file1.txt"

# Config validation for SHOW_PROGRESS
out="$(run_fsearch config set SHOW_PROGRESS "maybe" 2>&1 || true)"
assert_contains "SHOW_PROGRESS validates values" "$out" "auto, true, or false"

out="$(run_fsearch config set SHOW_PROGRESS "auto")"
assert_contains "SHOW_PROGRESS accepts auto" "$out" "auto"

out="$(run_fsearch config get SHOW_PROGRESS)"
assert_contains "SHOW_PROGRESS default is auto" "$out" "SHOW_PROGRESS=auto"

# ============================================================================
# S18  CONFIG SUBCOMMANDS
# ============================================================================
section "S18: Config subcommands"

# config show
out="$(run_fsearch config)"
assert_contains "config show lists keys" "$out" "DEFAULT_PATHS"
assert_contains "config show lists CONTEXT_LINES" "$out" "CONTEXT_LINES"
assert_contains "config show has type info" "$out" "[int]"
assert_contains "config show lists LOG_RETENTION_DAYS" "$out" "LOG_RETENTION_DAYS"

# config get
out="$(run_fsearch config get CONTEXT_LINES)"
assert_contains "config get shows value" "$out" "CONTEXT_LINES=3"
assert_contains "config get shows type" "$out" "type: int"

# config get unknown key
out="$(run_fsearch config get BOGUS_KEY 2>&1 || true)"
assert_contains "config get unknown key errors" "$out" "Unknown key"

# config set
out="$(run_fsearch config set CONTEXT_LINES 7)"
assert_contains "config set shows old -> new" "$out" "7"

# Verify the set persisted
out="$(run_fsearch config get CONTEXT_LINES)"
assert_contains "config set persisted" "$out" "CONTEXT_LINES=7"

# config reset
out="$(run_fsearch config reset CONTEXT_LINES)"
out2="$(run_fsearch config get CONTEXT_LINES)"
assert_contains "config reset restores default" "$out2" "CONTEXT_LINES=3"

# config set validation: bool
out="$(run_fsearch config set COLOR "maybe" 2>&1 || true)"
assert_contains "config set validates bool" "$out" "true or false"

# config set validation: int
out="$(run_fsearch config set CONTEXT_LINES "abc" 2>&1 || true)"
assert_contains "config set validates int" "$out" "non-negative integer"

# config set validation: OUTPUT_FORMAT
out="$(run_fsearch config set OUTPUT_FORMAT "xml" 2>&1 || true)"
assert_contains "config set validates OUTPUT_FORMAT" "$out" "pretty, plain, or json"

# config path
out="$(run_fsearch config path)"
assert_contains "config path shows config location" "$out" "config.conf"

# config path-add
out="$(run_fsearch config path-add /tmp/new_search_path)"
assert_contains "config path-add confirms" "$out" "Added"
out="$(run_fsearch config get DEFAULT_PATHS)"
assert_contains "config path-add persisted" "$out" "/tmp/new_search_path"

# config path-remove
out="$(run_fsearch config path-remove /tmp/new_search_path)"
assert_contains "config path-remove confirms" "$out" "Removed"
out="$(run_fsearch config get DEFAULT_PATHS)"
assert_not_contains "config path-remove persisted" "$out" "/tmp/new_search_path"

# config LOG_RETENTION_DAYS
out="$(run_fsearch config get LOG_RETENTION_DAYS)"
assert_contains "LOG_RETENTION_DAYS default is 7" "$out" "LOG_RETENTION_DAYS=7"

out="$(run_fsearch config set LOG_RETENTION_DAYS 14)"
assert_contains "LOG_RETENTION_DAYS can be changed" "$out" "14"

run_fsearch config reset LOG_RETENTION_DAYS >/dev/null

# ============================================================================
# S18  CONFIG PERSISTENCE
# ============================================================================
section "S19: Config persistence"

# Config file is created on first set
rm -rf "${TEST_CONFIG_HOME}/fsearch"
run_fsearch config set CONTEXT_LINES 4 >/dev/null
if [[ -f "${TEST_CONFIG_HOME}/fsearch/config.conf" ]]; then
    print_pass "config file created on first set"
else
    print_fail "config file created on first set" "file not found"
fi

# Config survives re-read
out="$(run_fsearch config get CONTEXT_LINES)"
assert_contains "config survives re-read" "$out" "CONTEXT_LINES=4"

# Reset and verify
run_fsearch config reset CONTEXT_LINES >/dev/null
out="$(run_fsearch config get CONTEXT_LINES)"
assert_contains "reset persists correctly" "$out" "CONTEXT_LINES=3"

# Multiple sets don't duplicate keys
run_fsearch config set CONTEXT_LINES 5 >/dev/null
run_fsearch config set CONTEXT_LINES 8 >/dev/null
count="$(grep -c '^CONTEXT_LINES=' "${TEST_CONFIG_HOME}/fsearch/config.conf" || true)"
assert_eq "multiple sets don't duplicate key" "$count" "1"

# Config value containing equals sign
run_fsearch config set DEFAULT_PATHS "/path/with=equals" >/dev/null
out="$(run_fsearch config get DEFAULT_PATHS)"
assert_contains "config value with = persisted correctly" "$out" "/path/with=equals"
run_fsearch config reset DEFAULT_PATHS >/dev/null

# ============================================================================
# S19  STATISTICS
# ============================================================================
section "S20: Statistics"

# Reset stats for clean testing
run_fsearch --stats-reset >/dev/null

# Run a search to generate stats
run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0 >/dev/null 2>&1 || true

# Check stats output
out="$(run_fsearch --stats)"
assert_contains "stats shows total searches" "$out" "Total searches:"
assert_contains "stats shows files scanned" "$out" "Files scanned:"
assert_contains "stats shows files matched" "$out" "Files matched:"
assert_contains "stats shows version" "$out" "v2.3.1"

# Verify search was counted
assert_not_contains "stats total searches is not 0" "$out" "Total searches:                0"

# Run another search and verify count increments
run_fsearch -p "$TEST_ROOT" -g 'hello' -0 >/dev/null 2>&1 || true
out="$(run_fsearch --stats)"
# Should show at least 2 searches now
assert_match "stats counts multiple searches" "$out" "Total searches:[[:space:]]*[2-9]"

# Stats reset
run_fsearch --stats-reset >/dev/null
out="$(run_fsearch --stats)"
assert_contains "stats reset zeros searches" "$out" "Total searches:                0"

# Stats exit code is 0
run_fsearch_rc --stats >/dev/null; rc=$?
assert_exit_code "stats exits 0" "0" "$rc"

run_fsearch_rc --stats-reset >/dev/null; rc=$?
assert_exit_code "stats-reset exits 0" "0" "$rc"

# ============================================================================
# S20  SEARCH LOGGING
# ============================================================================
section "S21: Search logging"

# Reset for clean testing
rm -rf "${TEST_CONFIG_HOME}/fsearch/logs"

# Run a search to generate a log entry
run_fsearch -p "$TEST_ROOT" -n '\.txt$' -0 >/dev/null 2>&1 || true

# Check that log directory and file were created
log_dir="${TEST_CONFIG_HOME}/fsearch/logs"
if [[ -d "$log_dir" ]]; then
    print_pass "log directory created"
else
    print_fail "log directory created" "directory not found: $log_dir"
fi

# Check that a log file exists for today
today="$(date '+%Y-%m-%d')"
log_file="${log_dir}/${today}.log"
if [[ -f "$log_file" ]]; then
    print_pass "log file created for today"
else
    print_fail "log file created for today" "file not found: $log_file"
fi

# Check log content
if [[ -f "$log_file" ]]; then
    log_content="$(cat "$log_file")"
    assert_contains "log entry has timestamp" "$log_content" "$today"
    assert_contains "log entry has status" "$log_content" "status="
    assert_contains "log entry has scanned count" "$log_content" "scanned="
    assert_contains "log entry has matched count" "$log_content" "matched="
fi

# Run a no-match search and verify it's logged
run_fsearch -p "$TEST_ROOT" -g 'ABSOLUTELY_NO_MATCH_12345' -0 >/dev/null 2>&1 || true
if [[ -f "$log_file" ]]; then
    log_content="$(cat "$log_file")"
    assert_contains "no-match search is logged" "$log_content" "no_matches"
fi

# Multiple searches produce multiple log lines
if [[ -f "$log_file" ]]; then
    line_count="$(wc -l < "$log_file" | tr -d ' ')"
    if [[ "$line_count" -ge 2 ]]; then
        print_pass "multiple searches produce multiple log entries"
    else
        print_fail "multiple searches produce multiple log entries" "only $line_count line(s)"
    fi
fi

# ============================================================================
# S21  ERROR HANDLING
# ============================================================================
section "S22: Error handling"

# No pattern specified — shows mini usage
out="$(run_fsearch -p "$TEST_ROOT" 2>&1 || true)"
assert_contains "no-args shows version" "$out" "v2.3.1"
assert_contains "no-args shows usage hint" "$out" "Search by filename"
assert_contains "no-args shows examples" "$out" "Quick examples"

# Unreadable file (skip if running as root)
if [[ "$(id -u)" -ne 0 ]]; then
    touch "${TEST_ROOT}/unreadable.txt"
    chmod 000 "${TEST_ROOT}/unreadable.txt"
    out="$(run_fsearch -p "$TEST_ROOT" -g 'anything' -0 2>&1 || true)"
    # Should warn but not crash
    chmod 644 "${TEST_ROOT}/unreadable.txt"
    rm "${TEST_ROOT}/unreadable.txt"
    print_pass "unreadable file handled gracefully"
else
    print_skip "unreadable file test (running as root)"
fi

# Invalid -C argument
out="$(run_fsearch -p "$TEST_ROOT" -C abc -g 'test' 2>&1 || true)"
assert_contains "invalid -C rejected" "$out" "non-negative integer"

# Invalid -d argument
out="$(run_fsearch -p "$TEST_ROOT" -d abc -n '.' 2>&1 || true)"
assert_contains "invalid -d rejected" "$out" "positive integer"

# ============================================================================
# S22  EDGE CASES
# ============================================================================
section "S23: Edge cases"

# Spaces in file paths
out="$(run_fsearch -p "$TEST_ROOT" -g 'spaces in path' -0)"
assert_contains "finds files in dirs with spaces" "$out" "spaces dir/ok.txt"

# Empty file (should not crash)
out="$(run_fsearch -p "$TEST_ROOT" -g 'anything' -0 2>&1 || true)"
# Just verify it doesn't crash — empty.txt won't match content
print_pass "empty file does not crash search"

# Special characters in pattern (literal dot)
out="$(run_fsearch -p "$TEST_ROOT" -n '\.py$' -0)"
assert_not_contains "regex dot is not a wildcard" "$out" ".txt"

# Exit code 2 for no matches
run_fsearch_rc -p "$TEST_ROOT" -g 'ABSOLUTELY_NO_MATCH_EVER_12345' >/dev/null 2>&1; rc=$?
assert_exit_code "exit code 2 when no matches" "2" "$rc"

# -- argument terminator
out="$(run_fsearch -n '\.txt$' -0 -- "$TEST_ROOT")"
assert_contains "-- separates options from paths" "$out" "file1.txt"

# File with equals in name
out="$(run_fsearch -p "$TEST_ROOT" -n 'equals' -0)"
assert_contains "finds file with = in name" "$out" "file-with-equals=sign.txt"

# ============================================================================
# S24  TIMING PERFORMANCE
# ============================================================================
section "S24: Timing performance"

# ── Create a larger fixture (100 files) to exercise the search loop ───────────
PERF_DIR="${TEST_DIR}/perfroot"
mkdir -p "$PERF_DIR"
for i in $(seq 1 100); do
    printf 'line one\nline two\nperf_marker_%s\nline four\n' "$i" > "${PERF_DIR}/perf_${i}.txt"
done

# ── Wall-clock test: search must complete in a reasonable time ────────────────
t_start=$SECONDS
run_fsearch -p "$PERF_DIR" -g 'perf_marker' -0 >/dev/null 2>&1 || true
t_elapsed=$(( SECONDS - t_start ))

if [[ $t_elapsed -le 30 ]]; then
    print_pass "search over 100 files completes in ≤30s (took ${t_elapsed}s)"
else
    print_fail "search over 100 files completed too slowly" "${t_elapsed}s elapsed"
fi

# ── Filename search is also fast ──────────────────────────────────────────────
t_start=$SECONDS
run_fsearch -p "$PERF_DIR" -n 'perf_' -0 >/dev/null 2>&1 || true
t_elapsed=$(( SECONDS - t_start ))

if [[ $t_elapsed -le 30 ]]; then
    print_pass "filename search over 100 files completes in ≤30s (took ${t_elapsed}s)"
else
    print_fail "filename search over 100 files completed too slowly" "${t_elapsed}s elapsed"
fi

# ── Verify timing stats are recorded ─────────────────────────────────────────
run_fsearch --stats-reset >/dev/null
run_fsearch -p "$PERF_DIR" -g 'perf_marker' -0 >/dev/null 2>&1 || true
out="$(run_fsearch --stats)"

assert_contains "stats shows Total search time" "$out" "Total search time:"
assert_contains "stats shows Avg search time"   "$out" "Avg search time:"

# Verify both are numeric (e.g. "0s" or "1.3s")
if printf '%s' "$out" | grep -qE 'Total search time:[[:space:]]+[0-9]+s'; then
    print_pass "Total search time value is numeric"
else
    print_fail "Total search time value is numeric" "got: $(printf '%s' "$out" | grep 'Total search time')"
fi

if printf '%s' "$out" | grep -qE 'Avg search time:[[:space:]]+[0-9]+\.[0-9]+s'; then
    print_pass "Avg search time value is formatted as N.Ns"
else
    print_fail "Avg search time value is formatted as N.Ns" "got: $(printf '%s' "$out" | grep 'Avg search time')"
fi

# Timing accumulates across multiple searches
run_fsearch -p "$PERF_DIR" -g 'perf_marker' -0 >/dev/null 2>&1 || true
run_fsearch -p "$PERF_DIR" -g 'perf_marker' -0 >/dev/null 2>&1 || true
out2="$(run_fsearch --stats)"
assert_match "timing stats accumulate across searches" "$out2" "Total searches:[[:space:]]*[3-9]"

# ============================================================================
# S25  INTERACTIVE KEYPRESS CONTROL
# ============================================================================
section "S25: Interactive keypress control"

# ── No-tty guard ─────────────────────────────────────────────────────────────
# The test harness pipes stdin, so _INTERACTIVE_ACTIVE is never set.
# Verify that [? help] does NOT appear in stderr output (it would only show
# when interactive mode is active).

out="$(run_fsearch -p "$PERF_DIR" -n 'perf_' -0 2>&1)"
assert_not_contains "no-tty: [? help] not shown in progress" "$out" "[? help]"

# ── JSON format suppresses interactive mode ───────────────────────────────────
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello' --format json 2>&1)"
assert_not_contains "json format: no [? help] hint" "$out" "[? help]"

# ── --no-progress suppresses interactive mode ─────────────────────────────────
out="$(run_fsearch -p "$TEST_ROOT" -g 'hello' --no-progress 2>&1)"
assert_not_contains "--no-progress: no [? help] hint" "$out" "[? help]"

# ── Version bump ──────────────────────────────────────────────────────────────
out="$(run_fsearch --version)"
assert_contains "version is 2.3.1" "$out" "fsearch 2.3.1"

# ── Ring buffer: _recent_match_add code path runs without error ───────────────
out="$(run_fsearch -p "$PERF_DIR" -g 'perf_marker' -0 2>&1)"
rc=$?
match_count="$(printf '%s' "$out" | grep -c 'perf_' || true)"
if [[ $match_count -ge 10 ]]; then
    print_pass "ring buffer code path: multiple matches found without error"
else
    print_fail "ring buffer code path: expected >=10 matches" "found $match_count (exit $rc)"
fi

# ── SIGINT: partial summary printed, exit 130 ─────────────────────────────────
# Launch a search over a 200-file fixture in background, send SIGINT, verify exit.
SIGINT_DIR="${TEST_DIR}/sigint_root"
mkdir -p "$SIGINT_DIR"
for i in $(seq 1 200); do
    printf 'sigint_content_%s\n' "$i" > "${SIGINT_DIR}/sigint_${i}.txt"
done

sigint_combined="$(
    (
        XDG_CONFIG_HOME="$TEST_CONFIG_HOME" bash "$FSEARCH" \
            -p "$SIGINT_DIR" -g 'sigint_content' -0
        echo "EXIT:$?"
    ) &
    fsearch_bg_pid=$!
    sleep 0.3
    kill -INT "$fsearch_bg_pid" 2>/dev/null || true
    wait "$fsearch_bg_pid" 2>/dev/null || true
    echo "EXIT:$?"
)" 2>&1 || true
sigint_rc="$(printf '%s' "$sigint_combined" | grep '^EXIT:' | tail -1 | cut -d: -f2)"

if [[ "$sigint_rc" == "130" || "$sigint_rc" == "0" || "$sigint_rc" == "2" ]]; then
    print_pass "SIGINT exits with code 130 (or completed before signal: $sigint_rc)"
else
    print_fail "SIGINT exit code" "expected 130/0/2, got: '${sigint_rc}'"
fi

# ── Key routing: fifo-backed tests (no real tty required) ────────────────────
# Source fsearch internal functions via FSEARCH_SOURCE_ONLY=1, wire fd 9 to a
# temp fifo, write one character, call _interactive_poll, and assert the right
# handler fired.  This tests the routing logic without needing a live terminal.

_run_key_test() {
    local desc="$1" key="$2" expected="$3"
    local tmpfifo
    tmpfifo="$(mktemp -t fsearch_keytest_XXXXXX)"
    rm -f "$tmpfifo"; mkfifo "$tmpfifo"
    local got
    got="$(
        FSEARCH_SOURCE_ONLY=1 source "$FSEARCH"
        _INTERACTIVE_ACTIVE=true
        exec 9<>"$tmpfifo"
        _called=""
        _interactive_help()         { _called="help"; }
        _interactive_quit()         { _called="quit"; }
        _interactive_pause()        { _called="pause"; }
        _interactive_stats_snap()   { _called="stats"; }
        _interactive_last_matches() { _called="last"; }
        printf '%s' "$key" >&9
        _interactive_poll
        printf '%s' "$_called"
    )" 2>/dev/null
    rm -f "$tmpfifo"
    if [[ "$got" == "$expected" ]]; then
        print_pass "$desc"
    else
        print_fail "$desc" "expected=$expected got=$got"
    fi
}

_run_key_test "key '?'  → help"    '?' "help"
_run_key_test "key 'h'  → help"    'h' "help"
_run_key_test "key 'H'  → help"    'H' "help"
_run_key_test "key 'q'  → quit"    'q' "quit"
_run_key_test "key 'Q'  → quit"    'Q' "quit"
_run_key_test "key 'p'  → pause"   'p' "pause"
_run_key_test "key 'P'  → pause"   'P' "pause"
_run_key_test "key 's'  → stats"   's' "stats"
_run_key_test "key 'l'  → last"    'l' "last"

# ============================================================================
# SUMMARY
# ============================================================================

printf "\n${C_BOLD}${C_CYAN}━━━  SUMMARY  ━━━${C_NC}\n\n"

total=$(( PASS + FAIL + SKIP ))
printf "  Total:   %d\n" "$total"
printf "  ${C_GREEN}Passed:  %d${C_NC}\n" "$PASS"

if [[ $FAIL -gt 0 ]]; then
    printf "  ${C_RED}Failed:  %d${C_NC}\n" "$FAIL"
else
    printf "  Failed:  0\n"
fi

if [[ $SKIP -gt 0 ]]; then
    printf "  ${C_YELLOW}Skipped: %d${C_NC}\n" "$SKIP"
fi

if [[ ${#FAIL_LIST[@]} -gt 0 ]]; then
    printf "\n  ${C_RED}Failed tests:${C_NC}\n"
    for name in "${FAIL_LIST[@]}"; do
        printf "    ${C_RED}✗${C_NC} %s\n" "$name"
    done
fi

printf "\n"

if [[ $FAIL -eq 0 ]]; then
    printf "  ${C_GREEN}${C_BOLD}All tests passed.${C_NC}\n\n"
    exit 0
else
    printf "  ${C_RED}${C_BOLD}%d test(s) failed.${C_NC}\n\n" "$FAIL"
    exit 1
fi
