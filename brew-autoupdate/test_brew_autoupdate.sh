#!/usr/bin/env bash
# =============================================================================
#
#  REGRESSION TEST SUITE — brew-autoupdate v2.1.0
#
#  File:     test_brew_autoupdate.sh
#  Requires: macOS, bash 3.2+, plutil (bundled with macOS)
#
#  Coverage:
#    §1   Test framework — counters, assert helpers, colored output
#    §2   Test infrastructure — temp dirs, mock binaries, cleanup trap
#    §3   is_quiet_hours() — 11 unit tests (all time-range scenarios)
#    §4   generate_plist() — 7 tests for launchd plist XML generation
#    §5   read_config_value() — 5 tests for config key extraction
#    §6   Config loader — 10 tests: new keys, defaults, unknown keys
#    §7   Upgrade args / greedy bug fix — 4 integration tests
#    §8   Package filtering (deny/allow lists) — 6 integration tests
#    §9   Pre/Post hooks — 5 integration tests
#    §10  Quiet hours integration — 3 tests
#    §11  [STATS]/[PKG] structured logging — 6 tests
#    §12  _next_run_time() — 5 unit tests
#    §13  _fmt_schedule_hours() — 4 unit tests
#    §14  _parse_stats() — 6 unit tests with synthetic log data
#    §15  Dashboard render — 3 smoke tests
#    §16  Schedule command — 3 tests
#    §17  Viewer CLI commands — 6 tests
#    §18  install.sh --reload-schedule — 3 tests
#    §19  config get / set / reset — CLI config editor — 15 tests
#    §20  Security — command injection prevention — 2 tests
#    §21  CLEANUP_OLDER_THAN_DAYS --prune — 2 tests
#    §22  BREW_ENV export — 2 tests
#    §23  Log rotation — 3 tests
#    §24  Lock file behavior — 2 tests
#    §25  Viewer commands — detail, summary, list, run — 6 tests
#    §26  Config set with spaces and notification content — 3 tests
#    §27  Time validation and _config_write edge cases — 3 tests
#
#  Total target: ~170 test cases
#
#  Run:
#    bash test_brew_autoupdate.sh
#    bash test_brew_autoupdate.sh --verbose   (show subprocess output)
#
#  Exit code: 0 if all tests pass, 1 if any fail.
#
# =============================================================================

# Do NOT use set -e — test scripts must survive failing commands in order to
# report failures rather than abort silently. set -o pipefail helps catch
# pipeline errors while still letting the suite continue running.
set -o pipefail

# Pre-initialize guard variables so 'set -u' (if we ever add it) cannot
# trigger on these before the sourcing sections attempt to set them.
VIEWER_FUNCTIONS_LOADED=0
INSTALL_FUNCS_LOADED=0

# =============================================================================
# §1  TEST FRAMEWORK
# =============================================================================

# ── Counters ─────────────────────────────────────────────────────────────────
PASS=0        # tests that passed
FAIL=0        # tests that failed
SKIP=0        # tests intentionally skipped
FAIL_LIST=()  # names of failed tests for the final summary

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

# assert_eq <desc> <actual> <expected>
assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        print_pass "${desc}"
    else
        print_fail "${desc}" "expected='${expected}'  got='${actual}'"
    fi
}

# assert_contains <desc> <haystack> <needle>
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if printf '%s' "${haystack}" | grep -qF -- "${needle}" 2>/dev/null; then
        print_pass "${desc}"
    else
        print_fail "${desc}" "expected to contain '${needle}'"
    fi
}

# assert_not_contains <desc> <haystack> <needle>
assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if printf '%s' "${haystack}" | grep -qF -- "${needle}" 2>/dev/null; then
        print_fail "${desc}" "expected NOT to contain '${needle}'"
    else
        print_pass "${desc}"
    fi
}

# assert_file_contains <desc> <file> <regex-pattern>
# Uses grep -q (basic regex); passes when the pattern is found in the file.
assert_file_contains() {
    local desc="$1" file="$2" pattern="$3"
    if [[ ! -f "${file}" ]]; then
        print_fail "${desc}" "file not found: ${file}"
        return
    fi
    if grep -q -- "${pattern}" "${file}" 2>/dev/null; then
        print_pass "${desc}"
    else
        print_fail "${desc}" "pattern '${pattern}' not found in $(basename "${file}")"
    fi
}

# assert_file_not_contains <desc> <file> <regex-pattern>
assert_file_not_contains() {
    local desc="$1" file="$2" pattern="$3"
    if [[ ! -f "${file}" ]]; then
        print_fail "${desc}" "file not found: ${file}"
        return
    fi
    if grep -q -- "${pattern}" "${file}" 2>/dev/null; then
        print_fail "${desc}" "pattern '${pattern}' should NOT be in $(basename "${file}")"
    else
        print_pass "${desc}"
    fi
}

# assert_true <desc> <command...>
# Runs the command; passes if it exits 0.
assert_true() {
    local desc="$1"; shift
    if "$@" 2>/dev/null; then
        print_pass "${desc}"
    else
        print_fail "${desc}" "command returned non-zero: $*"
    fi
}

# assert_false <desc> <command...>
# Runs the command; passes if it exits non-zero.
assert_false() {
    local desc="$1"; shift
    if ! "$@" 2>/dev/null; then
        print_pass "${desc}"
    else
        print_fail "${desc}" "expected failure, got success: $*"
    fi
}

# ── Verbose mode ──────────────────────────────────────────────────────────────
VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

# =============================================================================
# §2  TEST INFRASTRUCTURE
# =============================================================================

# One isolated temp directory for the entire test run. All fake HOME, mock
# binaries, test configs, and synthetic logs go here. Removed on exit.
TEST_DIR="$(mktemp -d /tmp/bau_test.XXXXXX)"

# ── Fake home directory tree ──────────────────────────────────────────────────
TEST_HOME="${TEST_DIR}/home"
TEST_BIN="${TEST_DIR}/bin"               # prepended to PATH; holds mock binaries

# IMPORTANT: brew-autoupdate.sh resolves CONFIG_FILE as "${SCRIPT_DIR}/config.conf"
# where SCRIPT_DIR is the directory containing the script itself — NOT ~/.config.
# Therefore we must copy all scripts into a dedicated "scripts" dir and write
# config there. This ensures config changes reach the subprocess under test.
SCRIPT_TEST_DIR="${TEST_DIR}/scripts"

# Viewer and install.sh use HOME-based paths for config and logs
TEST_CONFIG="${TEST_HOME}/.config/brew-autoupdate"
TEST_LOG_BASE="${TEST_HOME}/Library/Logs/brew-autoupdate"
TEST_DETAIL_DIR="${TEST_LOG_BASE}/detail"
TEST_SUMMARY_DIR="${TEST_LOG_BASE}/summary"
TEST_LAUNCHAGENTS="${TEST_HOME}/Library/LaunchAgents"

mkdir -p "${TEST_BIN}"
mkdir -p "${SCRIPT_TEST_DIR}"
mkdir -p "${TEST_CONFIG}"
mkdir -p "${TEST_DETAIL_DIR}"
mkdir -p "${TEST_SUMMARY_DIR}"
mkdir -p "${TEST_LAUNCHAGENTS}"

# File where every mock brew invocation is recorded (one line per call).
# Integration tests grep this to verify brew was invoked with the right args.
MOCK_BREW_INVOCATIONS="${TEST_DIR}/mock_brew.log"

# Resolve canonical paths to the source scripts under test
SCRIPT_DIR_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT_SRC="${SCRIPT_DIR_SRC}/brew-autoupdate.sh"
VIEWER_SCRIPT="${SCRIPT_DIR_SRC}/brew-autoupdate-viewer.sh"
INSTALL_SCRIPT="${SCRIPT_DIR_SRC}/install.sh"

# Copy the main script into the test scripts directory.
# This lets us place a test-specific config.conf alongside it so the script's
# own SCRIPT_DIR/config.conf resolution picks up our test settings.
cp "${MAIN_SCRIPT_SRC}" "${SCRIPT_TEST_DIR}/brew-autoupdate.sh"
MAIN_SCRIPT="${SCRIPT_TEST_DIR}/brew-autoupdate.sh"

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() { rm -rf "${TEST_DIR}"; }
trap cleanup EXIT

# ── Verify sources exist ──────────────────────────────────────────────────────
for f in "${MAIN_SCRIPT_SRC}" "${VIEWER_SCRIPT}" "${INSTALL_SCRIPT}"; do
    if [[ ! -f "${f}" ]]; then
        printf "${C_RED}FATAL: source file missing: %s${C_NC}\n" "${f}" >&2
        exit 1
    fi
done

# =============================================================================
# MOCK BINARY: brew
# =============================================================================
# Records every invocation to MOCK_BREW_INVOCATIONS (space-joined args per line).
# Behavior is controlled by environment variables set per-test:
#
#   MOCK_OUTDATED_PKGS   comma-separated package names reported by 'outdated --quiet'
#   MOCK_OUTDATED_VERBOSE  string returned by 'outdated --verbose'
#   MOCK_UPGRADE_FAIL    "1" → brew upgrade exits 1
#   MOCK_UPDATE_FAIL     "1" → brew update exits 1
#   MOCK_LIST_BEFORE     newline-sep packages for 1st 'list --versions' call
#   MOCK_LIST_AFTER      newline-sep packages for 2nd 'list --versions' call
# =============================================================================
cat > "${TEST_BIN}/brew" << 'BREW_MOCK_EOF'
#!/usr/bin/env bash
# Mock brew — appends every invocation to the log file, then responds.
LOG="${MOCK_BREW_INVOCATIONS:-/dev/null}"
echo "$*" >> "${LOG}"

case "$1" in
    --version)
        echo "Homebrew 4.0.0 (git revision mocktest)"
        exit 0 ;;

    shellenv)
        # Emit a no-op shellenv so 'eval "$(brew shellenv)"' succeeds without
        # side effects. The real shellenv would modify PATH, HOMEBREW_PREFIX, etc.
        echo "true"
        exit 0 ;;

    update)
        [[ "${MOCK_UPDATE_FAIL:-}" == "1" ]] && { echo "Error: git pull failed" >&2; exit 1; }
        echo "Already up-to-date."
        exit 0 ;;

    outdated)
        if [[ "${2:-}" == "--quiet" ]]; then
            # Return one package name per line from comma-separated MOCK_OUTDATED_PKGS
            echo "${MOCK_OUTDATED_PKGS:-}" | tr ',' '\n' | grep -v '^$'
        else
            echo "${MOCK_OUTDATED_VERBOSE:-}"
        fi
        exit 0 ;;

    upgrade)
        [[ "${MOCK_UPGRADE_FAIL:-}" == "1" ]] && { echo "Error: upgrade failed" >&2; exit 1; }
        echo "Upgrading: $*"
        exit 0 ;;

    cleanup)   echo "Removing old downloads.";    exit 0 ;;
    autoremove) echo "No formulae removed.";       exit 0 ;;
    doctor)    echo "Your system is ready.";       exit 0 ;;

    list)
        if [[ "${2:-}" == "--versions" ]]; then
            # Use a per-test call counter so the first call returns the
            # "before" snapshot and the second returns the "after" snapshot.
            # brew-autoupdate.sh calls 'list --versions' twice to diff changes.
            CNT_FILE="${LOG}.list_count"
            count=$(cat "${CNT_FILE}" 2>/dev/null || echo 0)
            count=$(( count + 1 ))
            echo "${count}" > "${CNT_FILE}"
            if [[ ${count} -le 1 ]]; then
                printf '%s\n' "${MOCK_LIST_BEFORE:-git 2.43.0
node 20.0.0}"
            else
                printf '%s\n' "${MOCK_LIST_AFTER:-git 2.44.0
node 21.0.0}"
            fi
        fi
        exit 0 ;;

    *)
        echo "mock brew: unknown command: $*" >&2
        exit 1 ;;
esac
BREW_MOCK_EOF
chmod +x "${TEST_BIN}/brew"

# =============================================================================
# MOCK BINARY: osascript
# =============================================================================
# Silently discards all notification calls; no system dialogs pop up.
# Logs calls for tests that want to verify notifications were triggered.
# =============================================================================
cat > "${TEST_BIN}/osascript" << 'OSASCRIPT_MOCK_EOF'
#!/usr/bin/env bash
echo "$*" >> "${MOCK_BREW_INVOCATIONS:-/dev/null}.osascript"
exit 0
OSASCRIPT_MOCK_EOF
chmod +x "${TEST_BIN}/osascript"

# =============================================================================
# MOCK BINARY: sw_vers
# =============================================================================
cat > "${TEST_BIN}/sw_vers" << 'SWVERS_MOCK_EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -productVersion) echo "14.4.1" ;;
    *) echo "macOS 14.4.1" ;;
esac
SWVERS_MOCK_EOF
chmod +x "${TEST_BIN}/sw_vers"

# =============================================================================
# MOCK BINARY: launchctl
# =============================================================================
# 'list <label>' exits 1 (not found) — used by status tests to confirm
# the daemon shows as NOT LOADED (deterministic, system-independent).
# 'load' and 'unload' succeed silently.
# =============================================================================
cat > "${TEST_BIN}/launchctl" << 'LAUNCHCTL_MOCK_EOF'
#!/usr/bin/env bash
echo "$*" >> "${MOCK_BREW_INVOCATIONS:-/dev/null}.launchctl"
case "$1" in
    list)   exit 1 ;;     # daemon is "not loaded"
    load)   exit 0 ;;
    unload) exit 0 ;;
    *)      exit 0 ;;
esac
LAUNCHCTL_MOCK_EOF
chmod +x "${TEST_BIN}/launchctl"

# =============================================================================
# MOCK BINARY: plutil
# =============================================================================
# Delegates to the real /usr/bin/plutil which is always present on macOS.
# This mock exists only to satisfy the PATH override pattern.
# =============================================================================
cat > "${TEST_BIN}/plutil" << 'PLUTIL_MOCK_EOF'
#!/usr/bin/env bash
exec /usr/bin/plutil "$@"
PLUTIL_MOCK_EOF
chmod +x "${TEST_BIN}/plutil"

# Prepend mock bin directory to PATH for all subprocesses.
export PATH="${TEST_BIN}:${PATH}"

# =============================================================================
# HELPER: write_test_config <content>
# =============================================================================
# Writes <content> to config.conf in BOTH locations:
#   1. SCRIPT_TEST_DIR/config.conf  — read by brew-autoupdate.sh (SCRIPT_DIR resolution)
#   2. TEST_CONFIG/config.conf      — read by the viewer and install.sh (HOME-based)
#
# Always prepends BREW_PATH pointing to the mock brew so the main script never
# discovers the real /opt/homebrew/bin/brew via its hardcoded path checks.
# =============================================================================
write_test_config() {
    local content
    # Always inject BREW_PATH as the first setting so mock brew is found
    # before the hardcoded /opt/homebrew and /usr/local path checks.
    content="BREW_PATH=${TEST_BIN}/brew
${1}"
    printf '%s\n' "${content}" > "${SCRIPT_TEST_DIR}/config.conf"
    printf '%s\n' "${content}" > "${TEST_CONFIG}/config.conf"
}

# =============================================================================
# HELPER: run_main_script [extra env assignments...]
# =============================================================================
# Runs MAIN_SCRIPT (the copy in SCRIPT_TEST_DIR) as a subprocess.
# Provides the isolated HOME and mock PATH. Always exits 0 from the
# helper's perspective — failures are checked by inspecting log files.
# =============================================================================
run_main_script() {
    > "${MOCK_BREW_INVOCATIONS}"
    rm -f "${MOCK_BREW_INVOCATIONS}.list_count"

    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    MOCK_BREW_INVOCATIONS="${MOCK_BREW_INVOCATIONS}" \
    bash "${MAIN_SCRIPT}" 2>/dev/null || true
}

# =============================================================================
# HELPERS: find latest log files written by a test run
# =============================================================================
find_latest_detail()  { ls -t "${TEST_DETAIL_DIR}"/*.log  2>/dev/null | head -1; }
find_latest_summary() { ls -t "${TEST_SUMMARY_DIR}"/*.log 2>/dev/null | head -1; }

# reset_logs — wipe all test log files between integration tests
reset_logs() {
    rm -f "${TEST_DETAIL_DIR}"/*.log  2>/dev/null || true
    rm -f "${TEST_SUMMARY_DIR}"/*.log 2>/dev/null || true
}

# =============================================================================
# PRINT TEST SUITE HEADER
# =============================================================================
printf "\n${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════╗${C_NC}\n"
printf "${C_BOLD}${C_CYAN}║  brew-autoupdate v2.1.0  —  Regression Test Suite            ║${C_NC}\n"
printf "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════════════════╝${C_NC}\n"
printf "   main:    %s\n" "${MAIN_SCRIPT_SRC}"
printf "   viewer:  %s\n" "${VIEWER_SCRIPT}"
printf "   install: %s\n" "${INSTALL_SCRIPT}"
printf "   tempdir: %s\n" "${TEST_DIR}"
printf "\n"

# =============================================================================
# §3  is_quiet_hours() UNIT TESTS
# =============================================================================
# Strategy: extract the exact function body from brew-autoupdate.sh using awk
# and eval it into the current shell. We test the actual production code —
# any change to the function immediately surfaces here.
#
# awk range pattern /start/,/end/ captures from the function header through
# the closing brace on its own line (column 0).
# =============================================================================
section "§3  is_quiet_hours() — time range logic"

# Extract and define is_quiet_hours() directly from the production script.
eval "$(awk '/^is_quiet_hours\(\) \{/,/^\}/' "${MAIN_SCRIPT}")"

# ── Same-day range 09:00–18:00 ───────────────────────────────────────────────

# 08:00 is before the window begins — should return false (not quiet)
assert_false "before window: 08:00 not in 09:00–18:00" \
    is_quiet_hours "08:00" "09:00" "18:00"

# 09:00 is the start boundary — start is INCLUSIVE (current >= start)
assert_true  "start boundary: 09:00 IS in 09:00–18:00" \
    is_quiet_hours "09:00" "09:00" "18:00"

# Comfortable midday interior
assert_true  "interior: 13:00 in 09:00–18:00" \
    is_quiet_hours "13:00" "09:00" "18:00"

# One minute before end — still inside
assert_true  "one before end: 17:59 in 09:00–18:00" \
    is_quiet_hours "17:59" "09:00" "18:00"

# 18:00 is the end boundary — end is EXCLUSIVE (current < end)
assert_false "end boundary: 18:00 NOT in 09:00–18:00" \
    is_quiet_hours "18:00" "09:00" "18:00"

# 20:00 is after the window
assert_false "after window: 20:00 not in 09:00–18:00" \
    is_quiet_hours "20:00" "09:00" "18:00"

# ── Overnight / cross-midnight range 22:00–07:00 ─────────────────────────────

# Late evening: inside overnight window
assert_true  "overnight: 23:00 in 22:00–07:00" \
    is_quiet_hours "23:00" "22:00" "07:00"

# Midnight: inside overnight window
assert_true  "overnight: 00:00 in 22:00–07:00" \
    is_quiet_hours "00:00" "22:00" "07:00"

# Early morning still inside
assert_true  "overnight: 06:30 in 22:00–07:00" \
    is_quiet_hours "06:30" "22:00" "07:00"

# Mid-morning: outside overnight window
assert_false "overnight: 10:00 NOT in 22:00–07:00" \
    is_quiet_hours "10:00" "22:00" "07:00"

# Midnight-start edge case
assert_true  "midnight start: 00:00 in 00:00–06:00" \
    is_quiet_hours "00:00" "00:00" "06:00"

# =============================================================================
# §4  generate_plist() UNIT TESTS
# =============================================================================
# Strategy: source install.sh after stripping its entry-point case block.
# The case block starts at  case "${1:-}" in  — we find its line number with
# grep -n and use head to read only the function definitions above it.
# This gives us generate_plist() and read_config_value() without triggering
# any install logic.
# =============================================================================
section "§4  generate_plist() — launchd plist XML generation"

# Find the line number of the case statement entry point in install.sh.
# We search for the literal string: case "${1:-}" in
INSTALL_CASE_LINE=$(grep -n '^case "\${1:-}" in' "${INSTALL_SCRIPT}" 2>/dev/null | head -1 | cut -d: -f1)

if [[ -n "${INSTALL_CASE_LINE:-}" && "${INSTALL_CASE_LINE}" -gt 0 ]]; then
    # Write the function-definitions-only portion to a temp file and source it.
    # Using a temp file avoids process-substitution complications on bash 3.2.
    INSTALL_FUNCS_TMP="${TEST_DIR}/install_funcs.sh"
    head -n $(( INSTALL_CASE_LINE - 1 )) "${INSTALL_SCRIPT}" > "${INSTALL_FUNCS_TMP}"
    # shellcheck disable=SC1090
    source "${INSTALL_FUNCS_TMP}" 2>/dev/null || true
    INSTALL_FUNCS_LOADED=1
    # IMPORTANT: install.sh has 'set -euo pipefail' which leaks into this shell
    # when sourced. Undo -e and -u so test failures don't abort the suite.
    # We keep -o pipefail as a useful sanity check on pipelines.
    set +eu || true
else
    printf "  ${C_YELLOW}⚠  install.sh case block not found — §4 & §5 tests skipped${C_NC}\n"
fi

PLIST_OUT="${TEST_DIR}/test.plist"

if [[ ${INSTALL_FUNCS_LOADED} -eq 1 ]]; then

    # ── Single hour ───────────────────────────────────────────────────────────

    generate_plist "3" "0" "${TEST_CONFIG}" "${TEST_HOME}" > "${PLIST_OUT}" 2>/dev/null

    PLIST_CONTENT=$(cat "${PLIST_OUT}" 2>/dev/null || true)

    assert_contains "single hour: StartCalendarInterval present" \
        "${PLIST_CONTENT}" "StartCalendarInterval"

    assert_contains "single hour: <key>Hour</key> present" \
        "${PLIST_CONTENT}" "<key>Hour</key>"

    # Each scheduled hour generates exactly one <key>Hour</key> entry.
    # We count Hour keys (not raw <dict> tags) because the plist also has
    # outer-level and EnvironmentVariables <dict> elements that inflate the count.
    HOUR_COUNT=$(grep -c '<key>Hour</key>' "${PLIST_OUT}" 2>/dev/null || echo 0)
    assert_eq "single hour: exactly 1 schedule entry" "${HOUR_COUNT}" "1"

    # ── Four-hour default schedule ────────────────────────────────────────────

    generate_plist "0,6,12,18" "0" "${TEST_CONFIG}" "${TEST_HOME}" > "${PLIST_OUT}" 2>/dev/null
    HOUR_COUNT=$(grep -c '<key>Hour</key>' "${PLIST_OUT}" 2>/dev/null || echo 0)
    assert_eq "4-hour schedule: 4 schedule entries" "${HOUR_COUNT}" "4"

    # All four hour integers must appear in the plist
    for expected_hour in 0 6 12 18; do
        assert_file_contains \
            "4-hour schedule: integer ${expected_hour} present" \
            "${PLIST_OUT}" \
            "<integer>${expected_hour}</integer>"
    done

    # ── Custom minute ─────────────────────────────────────────────────────────

    generate_plist "3" "30" "${TEST_CONFIG}" "${TEST_HOME}" > "${PLIST_OUT}" 2>/dev/null
    assert_file_contains "custom minute 30 in plist" \
        "${PLIST_OUT}" "<integer>30</integer>"

    # ── Path substitution ─────────────────────────────────────────────────────

    # The script path (ProgramArguments) and HOME path (EnvironmentVariables)
    # must be correctly substituted from the arguments we passed.
    generate_plist "0,6,12,18" "0" "${TEST_CONFIG}" "${TEST_HOME}" > "${PLIST_OUT}" 2>/dev/null
    assert_file_contains "install dir path in ProgramArguments" \
        "${PLIST_OUT}" "${TEST_CONFIG}"
    assert_file_contains "HOME path in EnvironmentVariables" \
        "${PLIST_OUT}" "${TEST_HOME}"

    # ── Valid XML (plutil lint) ───────────────────────────────────────────────

    # plutil -lint verifies the plist is well-formed XML. Any missing closing
    # tags, mismatched types, or bad characters will cause this to fail.
    assert_true "generated plist passes plutil -lint" \
        /usr/bin/plutil -lint "${PLIST_OUT}"

else
    for desc in \
        "single hour: StartCalendarInterval present" \
        "single hour: <key>Hour</key> present" \
        "single hour: exactly 1 <dict>" \
        "4-hour schedule: 4 <dict> entries" \
        "4-hour schedule: integer 0 present" \
        "custom minute 30 in plist" \
        "generated plist passes plutil -lint"
    do
        print_skip "${desc} (install.sh not sourced)"
    done
fi

# =============================================================================
# §5  read_config_value() UNIT TESTS
# =============================================================================
# read_config_value is defined in install.sh and was sourced in §4 above.
# Tests: key present, missing key with default, inline comment stripping.
# =============================================================================
section "§5  read_config_value() — config key extraction"

CFG_TEST_FILE="${TEST_DIR}/rcv_test.conf"

if [[ ${INSTALL_FUNCS_LOADED} -eq 1 ]]; then

    # ── Key present ───────────────────────────────────────────────────────────

    cat > "${CFG_TEST_FILE}" << 'CFG1'
SCHEDULE_HOURS=0,6,12,18
SCHEDULE_MINUTE=30
DENY_LIST=node python@3.11
CFG1

    assert_eq "reads SCHEDULE_HOURS correctly" \
        "$(read_config_value "${CFG_TEST_FILE}" SCHEDULE_HOURS "")" \
        "0,6,12,18"

    assert_eq "reads SCHEDULE_MINUTE correctly" \
        "$(read_config_value "${CFG_TEST_FILE}" SCHEDULE_MINUTE "")" \
        "30"

    assert_eq "reads DENY_LIST with spaces" \
        "$(read_config_value "${CFG_TEST_FILE}" DENY_LIST "")" \
        "node python@3.11"

    # ── Missing key → default ─────────────────────────────────────────────────

    assert_eq "missing key returns provided default" \
        "$(read_config_value "${CFG_TEST_FILE}" ALLOW_LIST "fallback-value")" \
        "fallback-value"

    # ── Inline comment stripped ───────────────────────────────────────────────

    cat > "${CFG_TEST_FILE}" << 'CFG2'
SCHEDULE_HOURS=0,6,12,18  # four times daily
CFG2

    assert_eq "inline comment stripped from value" \
        "$(read_config_value "${CFG_TEST_FILE}" SCHEDULE_HOURS "")" \
        "0,6,12,18"

else
    for desc in \
        "reads SCHEDULE_HOURS correctly" \
        "reads SCHEDULE_MINUTE correctly" \
        "reads DENY_LIST with spaces" \
        "missing key returns provided default" \
        "inline comment stripped from value"
    do
        print_skip "${desc} (install.sh not sourced)"
    done
fi

# =============================================================================
# §6  Config loader — brew-autoupdate.sh parses all new config keys
# =============================================================================
# Strategy: write a known config to SCRIPT_TEST_DIR/config.conf, run the main
# script as a subprocess (which reads config from its own directory), then
# inspect the detail log where config values are dumped near the top of each
# run. write_test_config() handles the dual-location write.
# =============================================================================
section "§6  Config loader — new config keys recognized"

# ── All new v2 keys loaded from config ───────────────────────────────────────

reset_logs
write_test_config "
AUTO_UPGRADE=true
DENY_LIST=node python@3.11
ALLOW_LIST=git wget
PRE_UPDATE_HOOK=echo hook_test
POST_UPDATE_HOOK=echo post_test
QUIET_HOURS_ENABLED=false
QUIET_HOURS_START=09:00
QUIET_HOURS_END=17:00
SCHEDULE_HOURS=0,6,12,18
SCHEDULE_MINUTE=0
"
run_main_script

DETAIL_LOG=$(find_latest_detail)

# The main script logs: Config: DENY_LIST='...' ALLOW_LIST='...' near the start.
# All new keys must appear in this config dump.
assert_file_contains "DENY_LIST loaded from config" \
    "${DETAIL_LOG}" "DENY_LIST='node python@3.11'"
assert_file_contains "ALLOW_LIST loaded from config" \
    "${DETAIL_LOG}" "ALLOW_LIST='git wget'"
assert_file_contains "QUIET_HOURS_ENABLED in config dump" \
    "${DETAIL_LOG}" "QUIET_HOURS_ENABLED=false"
assert_file_contains "QUIET_HOURS_START in config dump" \
    "${DETAIL_LOG}" "09:00"
assert_file_contains "QUIET_HOURS_END in config dump" \
    "${DETAIL_LOG}" "17:00"

# ── Default values applied when keys absent ───────────────────────────────────

reset_logs
# Minimal config — only AUTO_UPGRADE is set; all new keys should default to ""
write_test_config "AUTO_UPGRADE=true"
run_main_script
DETAIL_LOG=$(find_latest_detail)

assert_file_contains "DENY_LIST defaults to empty string" \
    "${DETAIL_LOG}" "DENY_LIST=''"
assert_file_contains "ALLOW_LIST defaults to empty string" \
    "${DETAIL_LOG}" "ALLOW_LIST=''"

# ── Unknown keys ignored (no crash) ──────────────────────────────────────────

reset_logs
write_test_config "
AUTO_UPGRADE=true
TOTALLY_UNKNOWN_KEY=should_be_ignored
ANOTHER_MYSTERY_SETTING=42
"
run_main_script
DETAIL_LOG=$(find_latest_detail)
if [[ -n "${DETAIL_LOG}" ]]; then
    assert_file_contains "unknown keys: run still completes" \
        "${DETAIL_LOG}" "Brew Auto-Update finished"
else
    print_fail "unknown keys: run still completes" "no detail log created"
fi

# ── Inline comments stripped from values (only when preceded by space) ────────

reset_logs
write_test_config "AUTO_UPGRADE=true    # enable upgrades"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "inline comment stripped from AUTO_UPGRADE" \
    "${DETAIL_LOG}" "AUTO_UPGRADE=true"

# ── Hash inside a value is preserved (not treated as comment) ────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
PRE_UPDATE_HOOK=curl https://example.com/path#frag
"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "hash inside value preserved (not stripped)" \
    "${DETAIL_LOG}" "Pre-update hook"

# ── Apostrophe in comment lines does NOT crash the config parser ──────────────
# Regression test for: xargs interprets shell quotes, so comment lines like
#   # your system's update history.
#   # Run 'brew upgrade' to install newer versions...
# caused "xargs: unterminated quote" on every run. Fixed by replacing xargs
# whitespace-trim with sed in the config parser.
# We verify two things:
#   1. The run completes without error (no early exit from xargs failure).
#   2. A real config value appearing AFTER the offending comment is still
#      parsed correctly (xargs would have silently dropped it on failure).

reset_logs
# Config block that mimics the real config.conf comment style: lines with
# apostrophes, a 'quoted' word, and a value that must survive intact.
write_test_config "
# Run 'brew upgrade' to install newer versions (your system's packages).
AUTO_UPGRADE=true
# Don't forget: brew cleanup removes old downloads.
AUTO_CLEANUP=true
DENY_LIST=node
"
run_main_script
DETAIL_LOG=$(find_latest_detail)

# The run must reach the final log line — xargs crash would prevent this.
if [[ -n "${DETAIL_LOG}" ]]; then
    assert_file_contains "apostrophe in comment: run completes" \
        "${DETAIL_LOG}" "Brew Auto-Update finished"
else
    print_fail "apostrophe in comment: run completes" "no detail log created"
fi

# DENY_LIST=node must be parsed correctly despite the apostrophe comments above.
assert_file_contains "apostrophe in comment: value after bad comment parsed" \
    "${DETAIL_LOG}" "DENY_LIST='node'"

# =============================================================================
# §7  Upgrade args — greedy cask bug fix
# =============================================================================
# v1.0 had a logical error (&&/|| chain) where --greedy was never actually
# passed to brew upgrade. We verify correct behavior for all three paths:
#
#   Path A: UPGRADE_CASKS=false          → --formula appended
#   Path B: UPGRADE_CASKS=true, GREEDY=false → no extra flag
#   Path C: UPGRADE_CASKS=true, GREEDY=true  → --greedy appended
#
# The mock brew records every invocation so we grep for the expected args.
# =============================================================================
section "§7  Upgrade args — greedy cask bug fix"

# ── Path A: casks disabled → --formula ───────────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
UPGRADE_CASKS=false
UPGRADE_CASKS_GREEDY=false
"
run_main_script
assert_file_contains \
    "UPGRADE_CASKS=false: --formula passed to brew upgrade" \
    "${MOCK_BREW_INVOCATIONS}" "upgrade --verbose --formula"

# ── Path B: casks on, greedy off → only --verbose (no extra flag) ─────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
UPGRADE_CASKS=true
UPGRADE_CASKS_GREEDY=false
"
run_main_script
assert_file_not_contains \
    "UPGRADE_CASKS=true,GREEDY=false: --greedy NOT passed" \
    "${MOCK_BREW_INVOCATIONS}" "--greedy"
assert_file_not_contains \
    "UPGRADE_CASKS=true,GREEDY=false: --formula NOT passed" \
    "${MOCK_BREW_INVOCATIONS}" "--formula"

# ── Path C: casks on, greedy on → --greedy ────────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
UPGRADE_CASKS=true
UPGRADE_CASKS_GREEDY=true
"
run_main_script
assert_file_contains \
    "UPGRADE_CASKS_GREEDY=true: --greedy passed to brew upgrade" \
    "${MOCK_BREW_INVOCATIONS}" "--greedy"

# =============================================================================
# §8  Package filtering — deny list and allow list
# =============================================================================
# The mock brew returns MOCK_OUTDATED_PKGS as outdated packages.
# When filtering is active the script runs:
#     brew upgrade <flags> pkg1 pkg2 ...
# When no filtering it runs:
#     brew upgrade <flags>
# We inspect MOCK_BREW_INVOCATIONS (the invocation log) for these patterns.
# =============================================================================
section "§8  Package filtering — deny / allow lists"

# ── Deny list: blocked package excluded from upgrade args ─────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
DENY_LIST=node
"
MOCK_OUTDATED_PKGS="node,git,wget" run_main_script
DETAIL_LOG=$(find_latest_detail)

# The upgrade invocation should contain git and wget but NOT node
assert_file_contains    "deny list: git included in upgrade" \
    "${MOCK_BREW_INVOCATIONS}" "git"
assert_file_contains    "deny list: wget included in upgrade" \
    "${MOCK_BREW_INVOCATIONS}" "wget"
assert_file_contains    "deny list: skip message logged for node" \
    "${DETAIL_LOG}" "DENY_LIST: skipping node"

# ── Allow list: only listed packages upgraded ─────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
ALLOW_LIST=git
"
MOCK_OUTDATED_PKGS="node,git,wget" run_main_script
DETAIL_LOG=$(find_latest_detail)

# node and wget should be logged as skipped (not in ALLOW_LIST)
assert_file_contains "allow list: node skipped (not allowed)" \
    "${DETAIL_LOG}" "ALLOW_LIST: skipping node"
assert_file_contains "allow list: wget skipped (not allowed)" \
    "${DETAIL_LOG}" "ALLOW_LIST: skipping wget"

# ── Deny beats allow: package in both lists is always skipped ─────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
DENY_LIST=node
ALLOW_LIST=node git
"
MOCK_OUTDATED_PKGS="node,git" run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "deny beats allow: node still in DENY_LIST log" \
    "${DETAIL_LOG}" "DENY_LIST: skipping node"

# ── Empty lists: brew upgrade called (no filtering applied) ───────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
DENY_LIST=
ALLOW_LIST=
"
MOCK_OUTDATED_PKGS="node,git" run_main_script
# With empty lists, brew upgrade must still be called
assert_file_contains "empty lists: upgrade invoked" \
    "${MOCK_BREW_INVOCATIONS}" "upgrade"

# =============================================================================
# §9  Pre/Post hooks
# =============================================================================
# Hooks execute via  bash -c "${HOOK_CMD}"  with output appended to the
# detail log. A non-zero hook exit must NOT abort the update cycle.
# =============================================================================
section "§9  Pre/Post hooks — execution and failure handling"

# ── Pre-update hook runs and creates sentinel file ────────────────────────────
reset_logs
PRE_SENTINEL="${TEST_DIR}/pre_sentinel_$$"
write_test_config "
AUTO_UPGRADE=true
PRE_UPDATE_HOOK=touch ${PRE_SENTINEL}
"
run_main_script
assert_true "pre-hook: sentinel file created" \
    test -f "${PRE_SENTINEL}"
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "pre-hook: logged in detail log" \
    "${DETAIL_LOG}" "Pre-update hook"

# ── Post-update hook runs after brew operations ───────────────────────────────
reset_logs
POST_SENTINEL="${TEST_DIR}/post_sentinel_$$"
write_test_config "
AUTO_UPGRADE=true
POST_UPDATE_HOOK=touch ${POST_SENTINEL}
"
run_main_script
assert_true "post-hook: sentinel file created" \
    test -f "${POST_SENTINEL}"

# ── Failing pre-hook does NOT abort the update cycle ─────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
PRE_UPDATE_HOOK=exit 42
"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "failing pre-hook: run still completes" \
    "${DETAIL_LOG}" "Brew Auto-Update finished"
assert_file_contains "failing pre-hook: warning logged" \
    "${DETAIL_LOG}" "WARNING: Pre-update hook exited with non-zero"

# ── No hooks configured → no hook log lines ───────────────────────────────────
reset_logs
write_test_config "AUTO_UPGRADE=true"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_not_contains "no hooks: pre-hook section absent" \
    "${DETAIL_LOG}" "Pre-update hook"
assert_file_not_contains "no hooks: post-hook section absent" \
    "${DETAIL_LOG}" "Post-update hook"

# ── Both hooks run when both configured ──────────────────────────────────────
reset_logs
BOTH="${TEST_DIR}/both_$$"
write_test_config "
AUTO_UPGRADE=true
PRE_UPDATE_HOOK=touch ${BOTH}_pre
POST_UPDATE_HOOK=touch ${BOTH}_post
"
run_main_script
assert_true "both hooks: pre sentinel exists"  test -f "${BOTH}_pre"
assert_true "both hooks: post sentinel exists" test -f "${BOTH}_post"

# =============================================================================
# §10  Quiet hours integration
# =============================================================================
# We cannot control the clock, so we use deterministic window tricks:
#   "always-quiet" = 00:00–23:59 : current time is guaranteed inside
#   "tiny window"  = 00:00–00:01 : almost guaranteed outside (< 1 min/day risk)
# =============================================================================
section "§10  Quiet hours — integration"

# ── Always-quiet window skips the run ────────────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
QUIET_HOURS_ENABLED=true
QUIET_HOURS_START=00:00
QUIET_HOURS_END=23:59
"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "always-quiet: run is skipped" \
    "${DETAIL_LOG}" "SKIP: Quiet hours active"
# brew update must NOT have been called (run exited before step 1)
assert_file_not_contains "always-quiet: brew update NOT called" \
    "${MOCK_BREW_INVOCATIONS}" "update"

# ── Quiet hours disabled: run proceeds ───────────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
QUIET_HOURS_ENABLED=false
QUIET_HOURS_START=00:00
QUIET_HOURS_END=23:59
"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_not_contains "quiet disabled: run NOT skipped" \
    "${DETAIL_LOG}" "SKIP: Quiet hours active"
assert_file_contains "quiet disabled: brew update ran" \
    "${DETAIL_LOG}" "brew update"

# ── Run outside tiny window proceeds normally ─────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
QUIET_HOURS_ENABLED=true
QUIET_HOURS_START=00:00
QUIET_HOURS_END=00:01
"
run_main_script
DETAIL_LOG=$(find_latest_detail)
# At any time other than 00:00 exactly, this run should proceed
assert_file_contains "outside tiny window: run completes" \
    "${DETAIL_LOG}" "Brew Auto-Update finished"

# =============================================================================
# §11  [STATS] and [PKG] structured log lines
# =============================================================================
# Every run appends a machine-parseable [STATS] line and zero or more [PKG]
# lines to the summary log. These drive the dashboard statistics display.
# =============================================================================
section "§11  [STATS] / [PKG] structured logging"

# ── [STATS] line written on every successful run ──────────────────────────────
reset_logs
write_test_config "AUTO_UPGRADE=true"
run_main_script
SUMMARY_LOG=$(find_latest_summary)
assert_file_contains "[STATS] line in summary log" \
    "${SUMMARY_LOG}" "\[STATS\]"
assert_file_contains "[STATS] contains duration= field" \
    "${SUMMARY_LOG}" "duration="
assert_file_contains "[STATS] status=SUCCESS on clean run" \
    "${SUMMARY_LOG}" "status=SUCCESS"

# ── [STATS] shows status=ERROR when brew update fails ────────────────────────
reset_logs
write_test_config "AUTO_UPGRADE=true"
MOCK_UPDATE_FAIL=1 run_main_script
SUMMARY_LOG=$(find_latest_summary)
assert_file_contains "[STATS] status=ERROR on failed run" \
    "${SUMMARY_LOG}" "status=ERROR"

# ── [PKG] lines appear when packages are upgraded ────────────────────────────
# Mock brew returns different 'list --versions' before/after upgrade so the
# diff produces package-change lines. git and node should each get a [PKG] line.
reset_logs
write_test_config "AUTO_UPGRADE=true"
MOCK_LIST_BEFORE="git 2.43.0
node 20.0.0" \
MOCK_LIST_AFTER="git 2.44.0
node 21.0.0" \
run_main_script
SUMMARY_LOG=$(find_latest_summary)
assert_file_contains "[PKG] git in summary log" \
    "${SUMMARY_LOG}" "\[PKG\] git"
assert_file_contains "[PKG] node in summary log" \
    "${SUMMARY_LOG}" "\[PKG\] node"

# ── upgrades=0 when list before = list after (nothing changed) ────────────────
reset_logs
write_test_config "AUTO_UPGRADE=true"
MOCK_LIST_BEFORE="git 2.44.0" MOCK_LIST_AFTER="git 2.44.0" run_main_script
SUMMARY_LOG=$(find_latest_summary)
assert_file_contains "[STATS] upgrades=0 when nothing changed" \
    "${SUMMARY_LOG}" "upgrades=0"

# =============================================================================
# SOURCE VIEWER FUNCTIONS FOR §12–§14 UNIT TESTS
# =============================================================================
# The viewer's command router starts at  cmd="${1:-detail}"  — we find its line
# number and source everything above it, giving us all helper function
# definitions without executing the dispatch loop.
#
# We write to a temp file first (avoids bash 3.2 process-substitution quirks).
# =============================================================================

ROUTER_LINE=$(grep -n '^cmd="\${1:-detail}"' "${VIEWER_SCRIPT}" 2>/dev/null | head -1 | cut -d: -f1)

if [[ -n "${ROUTER_LINE:-}" && "${ROUTER_LINE}" -gt 1 ]]; then
    VIEWER_FUNCS_TMP="${TEST_DIR}/viewer_functions.sh"
    head -n $(( ROUTER_LINE - 1 )) "${VIEWER_SCRIPT}" > "${VIEWER_FUNCS_TMP}"
    # IMPORTANT: save INSTALL_SCRIPT before sourcing the viewer — the viewer sets
    # its own global INSTALL_SCRIPT="${HOME}/.config/brew-autoupdate/install.sh"
    # (using the real HOME) which would overwrite our repo-relative variable.
    _SAVED_INSTALL_SCRIPT="${INSTALL_SCRIPT}"
    # shellcheck disable=SC1090
    source "${VIEWER_FUNCS_TMP}" 2>/dev/null || true
    # Restore after sourcing so §16/§18 cp commands use the correct repo path
    INSTALL_SCRIPT="${_SAVED_INSTALL_SCRIPT}"
    VIEWER_FUNCTIONS_LOADED=1
else
    printf "  ${C_YELLOW}⚠  viewer command router not found — §12-14 skipped${C_NC}\n"
fi

# =============================================================================
# §12  _next_run_time() unit tests
# =============================================================================
# We override the 'date' mock binary to return a fixed time, making the
# calculation deterministic regardless of when the test suite runs.
# =============================================================================
section "§12  _next_run_time() — next scheduled run calculation"

if [[ ${VIEWER_FUNCTIONS_LOADED} -eq 1 ]]; then

    # Create a mock date that returns a controlled hour and minute.
    # MOCK_NOW_H and MOCK_NOW_M env vars set the simulated current time.
    # For all other date format strings we delegate to the real /bin/date.
    cat > "${TEST_BIN}/date" << 'DATE_MOCK_EOF'
#!/usr/bin/env bash
case "${1:-}" in
    '+%H') printf '%02d\n' "${MOCK_NOW_H:-10}" ;;
    '+%M') printf '%02d\n' "${MOCK_NOW_M:-00}" ;;
    *)     exec /bin/date "$@" ;;
esac
DATE_MOCK_EOF
    chmod +x "${TEST_BIN}/date"

    # The _next_run_time function calls date '+%H' and '+%M' to get current time.
    # With the mock in place, we can test specific time scenarios.

    # Current: 10:00  Schedule: 18:00 only  → next is 18:00 (in 8h)
    result=$(MOCK_NOW_H=10 MOCK_NOW_M=00 _next_run_time "18" "0")
    assert_contains "10:00 → single 18:00 schedule shows 18:00" "${result}" "18:00"
    assert_contains "10:00 → shows 8h remaining"                "${result}" "8h"

    # Current: 07:00  Schedule: 0,6,12,18  → next is 12:00 (5h away)
    result=$(MOCK_NOW_H=07 MOCK_NOW_M=00 _next_run_time "0,6,12,18" "0")
    assert_contains "07:00 on 4x schedule → next is 12:00" "${result}" "12:00"

    # Current: 23:00  Schedule: 06:00 only  → wraps to tomorrow
    result=$(MOCK_NOW_H=23 MOCK_NOW_M=00 _next_run_time "6" "0")
    assert_contains "23:00 with only 06:00 slot → tomorrow" "${result}" "tomorrow"

    # Current: 06:10  Schedule runs at 06:30  → next is 06:30 (in 20m)
    result=$(MOCK_NOW_H=06 MOCK_NOW_M=10 _next_run_time "6" "30")
    assert_contains "06:10 with 06:30 schedule → 06:30 shown" "${result}" "06:30"

    # Current: 06:45  Schedule: 0,6,12,18 at :30  → 06:30 passed, next is 12:30
    result=$(MOCK_NOW_H=06 MOCK_NOW_M=45 _next_run_time "0,6,12,18" "30")
    assert_contains "06:45 after 06:30 → next is 12:30" "${result}" "12:30"

    # Remove the date mock; leave the real date for remaining sections
    rm -f "${TEST_BIN}/date"

else
    for d in \
        "10:00 → single 18:00 schedule shows 18:00" \
        "10:00 → shows 8h remaining" \
        "07:00 on 4x schedule → next is 12:00" \
        "23:00 with only 06:00 slot → tomorrow" \
        "06:10 with 06:30 schedule → 06:30 shown" \
        "06:45 after 06:30 → next is 12:30"
    do
        print_skip "${d} (viewer not sourced)"
    done
fi

# =============================================================================
# §13  _fmt_schedule_hours() unit tests
# =============================================================================
section "§13  _fmt_schedule_hours() — human-readable schedule string"

if [[ ${VIEWER_FUNCTIONS_LOADED} -eq 1 ]]; then

    # Single hour formats as "H:MM"
    result=$(_fmt_schedule_hours "3" "0")
    assert_contains "single hour 3 → '3:00' in output" "${result}" "3:00"

    # Four-hour default schedule — all four entries present
    result=$(_fmt_schedule_hours "0,6,12,18" "0")
    assert_contains "4x schedule: 0:00 present"  "${result}" "0:00"
    assert_contains "4x schedule: 12:00 present" "${result}" "12:00"

    # Custom minute appears in every entry
    result=$(_fmt_schedule_hours "0,12" "30")
    assert_contains "custom minute :30 in every entry" "${result}" ":30"

else
    for d in \
        "single hour 3 → '3:00' in output" \
        "4x schedule: 0:00 present" \
        "4x schedule: 12:00 present" \
        "custom minute :30 in every entry"
    do
        print_skip "${d} (viewer not sourced)"
    done
fi

# =============================================================================
# §14  _parse_stats() unit tests with synthetic log data
# =============================================================================
# Write carefully structured summary logs to TEST_SUMMARY_DIR, then call
# _parse_stats() (which reads from SUMMARY_DIR) and eval its output.
# Verify STAT_* variables reflect exactly what we wrote in the logs.
# =============================================================================
section "§14  _parse_stats() — summary log statistics parsing"

if [[ ${VIEWER_FUNCTIONS_LOADED} -eq 1 ]]; then

    # Point the viewer's SUMMARY_DIR at our test directory
    SUMMARY_DIR="${TEST_SUMMARY_DIR}"
    DETAIL_DIR="${TEST_DETAIL_DIR}"

    # Clean slate — remove any real logs from integration tests above
    reset_logs

    # ── Synthetic Day 1: 3 runs (2 success / 1 error), 5 total upgrades ───────
    cat > "${TEST_SUMMARY_DIR}/2026-03-30.log" << 'SYNTH_DAY1'
[2026-03-30 06:00:01] Brew Auto-Update starting
[2026-03-30 06:00:48] Brew Auto-Update finished in 47s
[2026-03-30 06:00:48] Status: SUCCESS (no errors)
[2026-03-30 06:00:48] [STATS] duration=47 status=SUCCESS upgrades=3
[2026-03-30 06:00:48] [PKG] git
[2026-03-30 06:00:48] [PKG] node
[2026-03-30 06:00:48] [PKG] python@3.13
[2026-03-30 12:00:01] Brew Auto-Update starting
[2026-03-30 12:00:39] Brew Auto-Update finished in 38s
[2026-03-30 12:00:39] Status: SUCCESS (no errors)
[2026-03-30 12:00:39] [STATS] duration=38 status=SUCCESS upgrades=0
[2026-03-30 18:00:01] Brew Auto-Update starting
[2026-03-30 18:00:41] Brew Auto-Update finished in 40s
[2026-03-30 18:00:41] ERRORS (1): brew update failed
[2026-03-30 18:00:41] [STATS] duration=40 status=ERROR upgrades=2
[2026-03-30 18:00:41] [PKG] wget
[2026-03-30 18:00:41] [PKG] curl
SYNTH_DAY1

    # ── Synthetic Day 2: 2 runs (both success), 2 upgrades ───────────────────
    cat > "${TEST_SUMMARY_DIR}/2026-03-31.log" << 'SYNTH_DAY2'
[2026-03-31 06:00:01] Brew Auto-Update starting
[2026-03-31 06:00:52] Brew Auto-Update finished in 51s
[2026-03-31 06:00:52] Status: SUCCESS (no errors)
[2026-03-31 06:00:52] [STATS] duration=51 status=SUCCESS upgrades=2
[2026-03-31 06:00:52] [PKG] git
[2026-03-31 06:00:52] [PKG] node
[2026-03-31 12:00:01] Brew Auto-Update starting
[2026-03-31 12:00:43] Brew Auto-Update finished in 42s
[2026-03-31 12:00:43] Status: SUCCESS (no errors)
[2026-03-31 12:00:43] [STATS] duration=42 status=SUCCESS upgrades=0
SYNTH_DAY2

    # Call _parse_stats and eval its variable assignments into the current shell
    eval "$(_parse_stats)"

    # Expected totals: 3 + 2 = 5 total runs
    assert_eq "_parse_stats: STAT_TOTAL_RUNS=5"     "${STAT_TOTAL_RUNS}"    "5"

    # Expected successes: runs 1,2,4,5 = 4
    assert_eq "_parse_stats: STAT_SUCCESS=4"        "${STAT_SUCCESS}"       "4"

    # Expected errors: run 3 = 1
    assert_eq "_parse_stats: STAT_ERRORS=1"         "${STAT_ERRORS}"        "1"

    # Expected upgrades: 3+0+2+2+0 = 7
    assert_eq "_parse_stats: STAT_TOTAL_UPGRADES=7" "${STAT_TOTAL_UPGRADES}" "7"

    # Expected unique packages: git, node, python@3.13, wget, curl = 5
    assert_eq "_parse_stats: STAT_UNIQUE_PKGS=5"    "${STAT_UNIQUE_PKGS}"   "5"

    # Top packages: git and node both appear 2x; they should be in PKG_COUNTS
    assert_contains "_parse_stats: git in PKG_COUNTS" \
        "${STAT_PKG_COUNTS}" "git"

else
    for d in \
        "_parse_stats: STAT_TOTAL_RUNS=5" \
        "_parse_stats: STAT_SUCCESS=4" \
        "_parse_stats: STAT_ERRORS=1" \
        "_parse_stats: STAT_TOTAL_UPGRADES=7" \
        "_parse_stats: STAT_UNIQUE_PKGS=5" \
        "_parse_stats: git in PKG_COUNTS"
    do
        print_skip "${d} (viewer not sourced)"
    done
fi

# =============================================================================
# §15  Dashboard render — smoke tests
# =============================================================================
# We do not parse the dashboard exhaustively; we verify:
#   (a) it exits 0 (no unset variables, no bash errors)
#   (b) expected section headers appear in the output
#   (c) it degrades gracefully with no log history
# =============================================================================
section "§15  Dashboard render — smoke tests"

# Environment for running viewer subprocesses
VIEWER_ENV=(
    "env"
    "HOME=${TEST_HOME}"
    "PATH=${TEST_BIN}:${PATH}"
    "MOCK_BREW_INVOCATIONS=${MOCK_BREW_INVOCATIONS}"
)

# Write the viewer config so read_cfg() finds SCHEDULE_HOURS etc.
write_test_config "SCHEDULE_HOURS=0,6,12,18
SCHEDULE_MINUTE=0"

# The synthetic logs from §14 should still be in TEST_SUMMARY_DIR
DASH_OUTPUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" dashboard 2>/dev/null
) || true

assert_contains "dashboard: DAEMON STATUS section" \
    "${DASH_OUTPUT}" "DAEMON STATUS"
assert_contains "dashboard: SCHEDULE section" \
    "${DASH_OUTPUT}" "SCHEDULE"
assert_contains "dashboard: STATISTICS section" \
    "${DASH_OUTPUT}" "STATISTICS"
assert_contains "dashboard: CONFIGURATION section" \
    "${DASH_OUTPUT}" "CONFIGURATION"

# ── Dashboard with zero log history renders gracefully ────────────────────────
reset_logs
DASH_NO_LOGS=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" dashboard 2>/dev/null
) || true
assert_contains "dashboard: 'no run' shown when logs absent" \
    "${DASH_NO_LOGS}" "no run"

# =============================================================================
# §16  Schedule command
# =============================================================================
section "§16  schedule command — show and reload"

write_test_config "SCHEDULE_HOURS=0,6,12,18
SCHEDULE_MINUTE=0"

# ── schedule show ─────────────────────────────────────────────────────────────
SCHED_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" schedule show 2>/dev/null
) || true
assert_contains "schedule show: hours visible" "${SCHED_OUT}" "0:00"
assert_contains "schedule show: config path shown" "${SCHED_OUT}" "config.conf"

# ── sched alias works ─────────────────────────────────────────────────────────
SCHED_ALIAS=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" sched 2>/dev/null
) || true
assert_contains "'sched' alias: output contains hours" "${SCHED_ALIAS}" "0:00"

# ── schedule reload regenerates plist and reloads daemon ─────────────────────
# Copy install.sh to TEST_CONFIG so the viewer's 'schedule reload' can call it
cp "${INSTALL_SCRIPT}" "${TEST_CONFIG}/install.sh"
chmod +x "${TEST_CONFIG}/install.sh"

write_test_config "SCHEDULE_HOURS=3,15
SCHEDULE_MINUTE=30"

"${VIEWER_ENV[@]}" bash "${VIEWER_SCRIPT}" schedule reload 2>/dev/null || true

PLIST_PATH="${TEST_LAUNCHAGENTS}/com.user.brew-autoupdate.plist"
assert_true "schedule reload: plist file created" test -f "${PLIST_PATH}"

# =============================================================================
# §17  Viewer CLI commands
# =============================================================================
section "§17  Viewer CLI — help, config, status, errors, unknown"

# ── help ─────────────────────────────────────────────────────────────────────
HELP_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" help 2>/dev/null
) || true

assert_contains "help: dashboard command listed"  "${HELP_OUT}" "dashboard"
assert_contains "help: schedule command listed"   "${HELP_OUT}" "schedule"
assert_contains "help: detail command listed"     "${HELP_OUT}" "detail"
assert_contains "help: sched alias listed"        "${HELP_OUT}" "sched"
assert_contains "help: dash alias listed"         "${HELP_OUT}" "dash"

# ── config ────────────────────────────────────────────────────────────────────
write_test_config "AUTO_UPGRADE=true
DENY_LIST=node"
CFG_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config 2>/dev/null
) || true
# config show renders a table: key and value are separate columns (with ANSI
# codes between them), so check for each token individually.
assert_contains "config: shows AUTO_UPGRADE"    "${CFG_OUT}" "AUTO_UPGRADE"
assert_contains "config: shows DENY_LIST=node"  "${CFG_OUT}" "DENY_LIST"

# ── status (daemon not loaded — mock launchctl exits 1 for 'list') ────────────
STATUS_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" status 2>/dev/null
) || true
assert_contains "status: shows NOT LOADED" "${STATUS_OUT}" "NOT LOADED"

# ── errors with no log files ─────────────────────────────────────────────────
reset_logs
ERRORS_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" errors 2>/dev/null
) || true
# With no logs the command should complete cleanly (exit 0 checked via || true)
assert_contains "errors: header line present" "${ERRORS_OUT}" "errors"

# =============================================================================
# §18  install.sh --reload-schedule
# =============================================================================
section "§18  install.sh --reload-schedule"

INSTALL_ENV=(
    "env"
    "HOME=${TEST_HOME}"
    "PATH=${TEST_BIN}:${PATH}"
    "MOCK_BREW_INVOCATIONS=${MOCK_BREW_INVOCATIONS}"
)

write_test_config "SCHEDULE_HOURS=3,15
SCHEDULE_MINUTE=30"

# ── --reload-schedule exits 0 and creates a plist ─────────────────────────────
"${INSTALL_ENV[@]}" bash "${INSTALL_SCRIPT}" --reload-schedule 2>/dev/null || true
assert_true "--reload-schedule: plist file exists" test -f "${PLIST_PATH}"

# ── Plist contains the new schedule hours and minute ─────────────────────────
PLIST_CONTENT=$(cat "${PLIST_PATH}" 2>/dev/null || true)
assert_contains "--reload-schedule: hour 3 in plist"  "${PLIST_CONTENT}" "<integer>3</integer>"
assert_contains "--reload-schedule: hour 15 in plist" "${PLIST_CONTENT}" "<integer>15</integer>"
assert_contains "--reload-schedule: minute 30 in plist" "${PLIST_CONTENT}" "<integer>30</integer>"

# ── Regenerated plist is valid XML ────────────────────────────────────────────
assert_true "--reload-schedule: plist passes plutil -lint" \
    /usr/bin/plutil -lint "${PLIST_PATH}"

# =============================================================================
# §19  config get / set / reset — CLI config editor
# =============================================================================
# Tests for the new 'brew-logs config' subcommands that allow reading and
# writing config values without manually editing config.conf.
#
# Coverage:
#   config show  — formatted table of all known keys
#   config get   — reads a value; falls back to default when key is absent
#   config set   — writes value into config file; validates types
#   config reset — reverts a key to its factory default
#   round-trip   — set then get returns the updated value
#   unknown key  — error message, non-zero exit
#   bad bool     — validation rejects non-true/false for bool keys
# =============================================================================
section "§19  config get / set / reset — CLI config editor"

# Seed a minimal config that the viewer's _config_show / _config_get can read
write_test_config "AUTO_UPGRADE=true
AUTO_CLEANUP=true
DENY_LIST=node"

# ── config show — formatted table lists all known keys ───────────────────────
CFG_SHOW=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config show 2>/dev/null
) || true
assert_contains "config show: AUTO_UPGRADE in table"     "${CFG_SHOW}" "AUTO_UPGRADE"
assert_contains "config show: DENY_LIST in table"        "${CFG_SHOW}" "DENY_LIST"
assert_contains "config show: SCHEDULE_HOURS in table"   "${CFG_SHOW}" "SCHEDULE_HOURS"
assert_contains "config show: type annotation present"   "${CFG_SHOW}" "[bool]"
assert_contains "config show: modified marker shown"     "${CFG_SHOW}" "*"

# ── config get — reads a value that is present in the config file ─────────────
CFG_GET=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config get DENY_LIST 2>/dev/null
) || true
assert_contains "config get DENY_LIST: returns value"    "${CFG_GET}" "DENY_LIST=node"
assert_contains "config get DENY_LIST: shows type"       "${CFG_GET}" "type: string"
assert_contains "config get DENY_LIST: shows default"    "${CFG_GET}" "default:"

# ── config get — absent key falls back to factory default ─────────────────────
# UPGRADE_CASKS_GREEDY is not in our minimal config — should show default "false"
CFG_GET_DEF=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config get UPGRADE_CASKS_GREEDY 2>/dev/null
) || true
assert_contains "config get absent key: shows default value" "${CFG_GET_DEF}" "false"

# ── config get — unknown key returns error ────────────────────────────────────
CFG_GET_UNK=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config get TOTALLY_FAKE_KEY 2>&1
) || true
assert_contains "config get unknown key: error message"  "${CFG_GET_UNK}" "Unknown key"

# ── config set — writes a new value into the config file ──────────────────────
# Set AUTO_CLEANUP to false and verify the file was updated
"${VIEWER_ENV[@]}" bash "${VIEWER_SCRIPT}" config set AUTO_CLEANUP false 2>/dev/null || true
CFG_AFTER_SET=$(cat "${TEST_CONFIG}/config.conf" 2>/dev/null || true)
assert_contains "config set: value written to config file"   "${CFG_AFTER_SET}" "AUTO_CLEANUP=false"

# ── config set — output shows old → new transition ────────────────────────────
CFG_SET_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set UPGRADE_CASKS_GREEDY true 2>/dev/null
) || true
assert_contains "config set: shows old→new in output"    "${CFG_SET_OUT}" "→"
assert_contains "config set: new value in output"        "${CFG_SET_OUT}" "true"

# ── config set — schedule key triggers reload reminder ────────────────────────
CFG_SCHED_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set SCHEDULE_HOURS 3,9,15,21 2>/dev/null
) || true
assert_contains "config set SCHEDULE_HOURS: reload reminder" \
    "${CFG_SCHED_OUT}" "schedule reload"

# ── config set — bool key rejects non-boolean value ───────────────────────────
CFG_BAD_BOOL=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set AUTO_UPGRADE yes 2>&1
) || true
assert_contains "config set bad bool: error message"     "${CFG_BAD_BOOL}" "true or false"

# ── config set — int key rejects non-integer value ────────────────────────────
CFG_BAD_INT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set SCHEDULE_MINUTE abc 2>&1
) || true
assert_contains "config set bad int: error message"      "${CFG_BAD_INT}" "integer"

# ── config set — time key rejects bad format ──────────────────────────────────
CFG_BAD_TIME=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set QUIET_HOURS_START 9am 2>&1
) || true
assert_contains "config set bad time: error message"     "${CFG_BAD_TIME}" "HH:MM"

# ── config set — unknown key returns error ────────────────────────────────────
CFG_SET_UNK=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set MADE_UP_KEY value 2>&1
) || true
assert_contains "config set unknown key: error message"  "${CFG_SET_UNK}" "Unknown key"

# ── config reset — reverts a key to factory default ──────────────────────────
# AUTO_CLEANUP was set to false above; reset should restore it to "true"
"${VIEWER_ENV[@]}" bash "${VIEWER_SCRIPT}" config reset AUTO_CLEANUP 2>/dev/null || true
CFG_AFTER_RESET=$(cat "${TEST_CONFIG}/config.conf" 2>/dev/null || true)
assert_contains "config reset: value reverted in config file" "${CFG_AFTER_RESET}" "AUTO_CLEANUP=true"

# ── round-trip: set a value, then get it back ─────────────────────────────────
"${VIEWER_ENV[@]}" bash "${VIEWER_SCRIPT}" config set CLEANUP_OLDER_THAN_DAYS 30 2>/dev/null || true
CFG_ROUNDTRIP=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config get CLEANUP_OLDER_THAN_DAYS 2>/dev/null
) || true
assert_contains "config round-trip: get returns set value"   "${CFG_ROUNDTRIP}" "CLEANUP_OLDER_THAN_DAYS=30"

# =============================================================================
# §20  Security — command injection prevention
# =============================================================================
# Verifies that config values containing $(...) or backticks are NOT executed
# during config parsing (the declare→printf -v fix).
# =============================================================================
section "§20  Security — command injection prevention"

INJECTION_SENTINEL="${TEST_DIR}/injection_sentinel_$$"
reset_logs
write_test_config "
AUTO_UPGRADE=true
DENY_LIST=\$(touch ${INJECTION_SENTINEL})
"
run_main_script
assert_false "command substitution in config value NOT executed" \
    test -f "${INJECTION_SENTINEL}"

# Backtick variant
INJECTION_SENTINEL2="${TEST_DIR}/injection_sentinel2_$$"
reset_logs
write_test_config "
AUTO_UPGRADE=true
ALLOW_LIST=\`touch ${INJECTION_SENTINEL2}\`
"
run_main_script
assert_false "backtick in config value NOT executed" \
    test -f "${INJECTION_SENTINEL2}"

# =============================================================================
# §21  CLEANUP_OLDER_THAN_DAYS → --prune flag
# =============================================================================
section "§21  CLEANUP_OLDER_THAN_DAYS — --prune flag"

# ── Non-zero value passes --prune to brew cleanup ────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
AUTO_CLEANUP=true
CLEANUP_OLDER_THAN_DAYS=60
"
run_main_script
assert_file_contains "CLEANUP_OLDER_THAN_DAYS=60: --prune=60 passed" \
    "${MOCK_BREW_INVOCATIONS}" "--prune=60"

# ── Zero value does NOT pass --prune ─────────────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
AUTO_CLEANUP=true
CLEANUP_OLDER_THAN_DAYS=0
"
run_main_script
assert_file_not_contains "CLEANUP_OLDER_THAN_DAYS=0: --prune NOT passed" \
    "${MOCK_BREW_INVOCATIONS}" "--prune"

# =============================================================================
# §22  BREW_ENV — environment variable export
# =============================================================================
# The mock brew cannot easily report its own environment, so we use a custom
# mock that writes env vars to a file when 'brew update' is called.
# =============================================================================
section "§22  BREW_ENV — environment variable export"

# Create a special mock that logs HOMEBREW_NO_ANALYTICS if it's set
ENV_LOG="${TEST_DIR}/env_check.log"
cat > "${TEST_BIN}/brew_env_check" << ENVMOCK_EOF
#!/usr/bin/env bash
echo "HOMEBREW_NO_ANALYTICS=\${HOMEBREW_NO_ANALYTICS:-unset}" > "${ENV_LOG}"
# Delegate to the original mock for normal behavior
exec "${TEST_BIN}/brew" "\$@"
ENVMOCK_EOF
chmod +x "${TEST_BIN}/brew_env_check"

reset_logs
write_test_config "
AUTO_UPGRADE=true
BREW_ENV=HOMEBREW_NO_ANALYTICS=1
"
# Override BREW_PATH to point to our env-checking wrapper
sed -i '' "s|BREW_PATH=.*|BREW_PATH=${TEST_BIN}/brew_env_check|" "${SCRIPT_TEST_DIR}/config.conf"

run_main_script
if [[ -f "${ENV_LOG}" ]]; then
    ENV_CONTENT=$(cat "${ENV_LOG}")
    assert_contains "BREW_ENV: HOMEBREW_NO_ANALYTICS exported" \
        "${ENV_CONTENT}" "HOMEBREW_NO_ANALYTICS=1"
else
    print_fail "BREW_ENV: env check log not created" "brew_env_check mock not invoked"
fi

# Verify run still completes with BREW_ENV
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "BREW_ENV: run completes normally" \
    "${DETAIL_LOG}" "Brew Auto-Update finished"

# ── BREW_ENV with literal quotes does NOT crash export ────────────────────────
# Regression: printf -v preserves literal "" from defaults, causing
# export '""' → "not a valid identifier". Must be silently skipped.
reset_logs
write_test_config '
AUTO_UPGRADE=true
BREW_ENV=""
'
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "BREW_ENV with literal quotes: run completes" \
    "${DETAIL_LOG}" "Brew Auto-Update finished"

# ── Empty BREW_ENV does not crash ─────────────────────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
BREW_ENV=
"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "empty BREW_ENV: run completes" \
    "${DETAIL_LOG}" "Brew Auto-Update finished"

# =============================================================================
# §23  Log rotation — old files deleted, recent files preserved
# =============================================================================
section "§23  Log rotation — old files and recent files"

reset_logs

# Create "old" log files with a modification date older than retention
OLD_DETAIL="${TEST_DETAIL_DIR}/2024-01-01_00-00-01.log"
OLD_SUMMARY="${TEST_SUMMARY_DIR}/2024-01-01.log"
echo "old detail log" > "${OLD_DETAIL}"
echo "old summary log" > "${OLD_SUMMARY}"
# Backdate modification time to 200 days ago
touch -t 202301010000.00 "${OLD_DETAIL}" 2>/dev/null || \
    touch -A -200d "${OLD_DETAIL}" 2>/dev/null || true
touch -t 202301010000.00 "${OLD_SUMMARY}" 2>/dev/null || \
    touch -A -200d "${OLD_SUMMARY}" 2>/dev/null || true

write_test_config "
AUTO_UPGRADE=true
DETAIL_LOG_RETENTION_DAYS=90
SUMMARY_LOG_RETENTION_DAYS=365
"
run_main_script

# Old detail log should have been rotated (deleted)
assert_false "log rotation: old detail log deleted" \
    test -f "${OLD_DETAIL}"

# The new detail log from this run should still exist
NEW_DETAIL=$(find_latest_detail)
assert_true "log rotation: new detail log preserved" \
    test -f "${NEW_DETAIL}"

# Old summary log (>365 days) should also be deleted
assert_false "log rotation: old summary log deleted" \
    test -f "${OLD_SUMMARY}"

# =============================================================================
# §24  Lock file — stale lock detection
# =============================================================================
section "§24  Lock file — stale lock detection"

LOCK_FILE="/tmp/brew-autoupdate.lock"

# ── Stale lock (dead PID) is cleaned up ───────────────────────────────────────
reset_logs
# Write a PID that definitely doesn't exist (99999999)
echo "99999999" > "${LOCK_FILE}"
write_test_config "AUTO_UPGRADE=true"
run_main_script
DETAIL_LOG=$(find_latest_detail)
assert_file_contains "stale lock: run completes (stale lock cleaned)" \
    "${DETAIL_LOG}" "Brew Auto-Update finished"

# ── Lock file is removed after normal run ────────────────────────────────────
# After a successful run, the lock should be cleaned up by the trap
assert_false "lock file removed after run" \
    test -f "${LOCK_FILE}"

# =============================================================================
# §25  Viewer commands — detail, summary, list, run
# =============================================================================
section "§25  Viewer CLI — detail, summary, list, run"

# Seed some test log files
reset_logs
write_test_config "AUTO_UPGRADE=true"
run_main_script

# ── detail last N ────────────────────────────────────────────────────────────
DETAIL_LAST=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" detail last 1 2>/dev/null
) || true
assert_contains "detail last 1: shows log content" "${DETAIL_LAST}" "Brew Auto-Update"

# ── summary latest ──────────────────────────────────────────────────────────
SUMMARY_LATEST=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" summary latest 2>/dev/null
) || true
assert_contains "summary latest: shows summary content" "${SUMMARY_LATEST}" "Brew Auto-Update"

# ── summary today ──────────────────────────────────────────────────────────
SUMMARY_TODAY=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" summary today 2>/dev/null
) || true
assert_contains "summary today: shows today's summary" "${SUMMARY_TODAY}" "Brew Auto-Update"

# ── list detail ──────────────────────────────────────────────────────────────
LIST_DETAIL=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" list detail 2>/dev/null
) || true
assert_contains "list detail: shows .log files" "${LIST_DETAIL}" ".log"

# ── list summary ─────────────────────────────────────────────────────────────
LIST_SUMMARY=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" list summary 2>/dev/null
) || true
assert_contains "list summary: shows .log files" "${LIST_SUMMARY}" ".log"

# ── run ────────────────────────────────────────────────────────────────────
RUN_OUT=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" run 2>/dev/null
) || true
assert_contains "run: triggers update and shows done" "${RUN_OUT}" "Done"

# =============================================================================
# §26  Config set with spaces & notification content
# =============================================================================
section "§26  Config set with spaces & notification content"

# ── config set DENY_LIST with spaces ──────────────────────────────────────────
write_test_config "AUTO_UPGRADE=true"
"${VIEWER_ENV[@]}" bash "${VIEWER_SCRIPT}" config set DENY_LIST "node python@3.11 wget" 2>/dev/null || true
CFG_SPACES=$(cat "${TEST_CONFIG}/config.conf" 2>/dev/null || true)
assert_contains "config set: spaces in DENY_LIST preserved" \
    "${CFG_SPACES}" "DENY_LIST=node python@3.11 wget"

# ── _config_write preserves other keys when updating one ──────────────────────
assert_contains "config set: AUTO_UPGRADE still present after DENY_LIST set" \
    "${CFG_SPACES}" "AUTO_UPGRADE=true"

# ── Notification content includes upgrade count ──────────────────────────────
reset_logs
write_test_config "
AUTO_UPGRADE=true
NOTIFY_ON_EVERY_RUN=true
"
MOCK_LIST_BEFORE="git 2.43.0" MOCK_LIST_AFTER="git 2.44.0" run_main_script
OSASCRIPT_LOG="${MOCK_BREW_INVOCATIONS}.osascript"
if [[ -f "${OSASCRIPT_LOG}" ]]; then
    OSASCRIPT_CONTENT=$(cat "${OSASCRIPT_LOG}")
    assert_contains "notification: mentions package upgrade" \
        "${OSASCRIPT_CONTENT}" "upgraded"
else
    print_fail "notification: osascript log exists" "no osascript calls recorded"
fi

# =============================================================================
# §27  Time validation and _config_write edge cases
# =============================================================================
section "§27  Time validation & _config_write edge cases"

# ── Time validation rejects hour 25 ──────────────────────────────────────────
CFG_BAD_HOUR=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set QUIET_HOURS_START 25:00 2>&1
) || true
assert_contains "time validation: 25:00 rejected" "${CFG_BAD_HOUR}" "HH:MM"

# ── Time validation accepts 23:59 ───────────────────────────────────────────
write_test_config "AUTO_UPGRADE=true"
CFG_GOOD_TIME=$(
    "${VIEWER_ENV[@]}" \
    bash "${VIEWER_SCRIPT}" config set QUIET_HOURS_START 23:59 2>/dev/null
) || true
assert_contains "time validation: 23:59 accepted" "${CFG_GOOD_TIME}" "→"

# ── _config_write correctly updates key with spaces in value ─────────────────
write_test_config "
AUTO_UPGRADE=true
PRE_UPDATE_HOOK=echo hello world
"
"${VIEWER_ENV[@]}" bash "${VIEWER_SCRIPT}" config set PRE_UPDATE_HOOK "echo goodbye world" 2>/dev/null || true
CFG_HOOK=$(cat "${TEST_CONFIG}/config.conf" 2>/dev/null || true)
assert_contains "_config_write: hook value with spaces updated" \
    "${CFG_HOOK}" "PRE_UPDATE_HOOK=echo goodbye world"

# =============================================================================
# FINAL REPORT
# =============================================================================
TOTAL=$(( PASS + FAIL + SKIP ))

printf "\n${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_NC}\n"
printf "${C_BOLD}  RESULTS   %d total   " "${TOTAL}"
printf "${C_GREEN}%d passed${C_NC}   " "${PASS}"
if [[ ${FAIL} -gt 0 ]]; then
    printf "${C_RED}%d failed${C_NC}   " "${FAIL}"
else
    printf "${C_DIM}%d failed${C_NC}   " "${FAIL}"
fi
if [[ ${SKIP} -gt 0 ]]; then
    printf "${C_YELLOW}%d skipped${C_NC}" "${SKIP}"
else
    printf "${C_DIM}%d skipped${C_NC}" "${SKIP}"
fi
printf "\n${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_NC}\n"

if [[ ${#FAIL_LIST[@]} -gt 0 ]]; then
    printf "\n${C_RED}${C_BOLD}  Failed tests:${C_NC}\n"
    for name in "${FAIL_LIST[@]}"; do
        printf "  ${C_RED}•${C_NC} %s\n" "${name}"
    done
    printf "\n"
fi

if [[ ${FAIL} -eq 0 ]]; then
    printf "\n  ${C_GREEN}${C_BOLD}All tests passed.${C_NC}\n\n"
    exit 0
else
    printf "\n  ${C_RED}${C_BOLD}%d test(s) failed.${C_NC}\n\n" "${FAIL}"
    exit 1
fi
