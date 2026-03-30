#!/usr/bin/env bash
# ============================================================================
#
#  HOMEBREW AUTO-UPDATE DAEMON SCRIPT
#
#  File:        brew-autoupdate.sh
#  Version:     1.0.0
#  Author:      Generated with Claude Code
#  License:     MIT
#  Requires:    macOS, Homebrew, bash 3.2+
#
#  Description:
#    Automated Homebrew package maintenance script designed to run as a
#    macOS launchd daemon. Performs a complete update cycle:
#
#      1. brew update    - Fetches latest formulae/cask definitions
#      2. brew outdated  - Identifies packages needing upgrade
#      3. brew upgrade   - Installs newer versions of outdated packages
#      4. brew cleanup   - Removes stale downloads and old versions
#      5. brew autoremove - Removes orphaned dependencies
#      6. brew doctor    - Runs diagnostic health check
#      7. Log rotation   - Prunes logs exceeding retention thresholds
#
#  Logging Architecture:
#    Two-tier logging system provides both deep troubleshooting data and
#    long-term update history:
#
#    DETAIL LOGS (~/Library/Logs/brew-autoupdate/detail/)
#      - One file per run, named by timestamp: YYYY-MM-DD_HH-MM-SS.log
#      - Maximum verbosity: all brew output, config dumps, diagnostics
#      - Default retention: 90 days (configurable)
#      - Purpose: Troubleshooting errors, auditing what happened
#
#    SUMMARY LOGS (~/Library/Logs/brew-autoupdate/summary/)
#      - One file per day, named by date: YYYY-MM-DD.log
#      - High-level: start/stop, what was outdated, what changed, errors
#      - Default retention: 365 days (configurable)
#      - Purpose: Long-term record of package update history
#
#  Notifications:
#    Uses macOS native osascript to display Notification Center alerts.
#    - Error notifications: Always shown by default (configurable)
#    - Success notifications: Shown by default for testing; disable once
#      you've verified the daemon is working correctly
#
#  Concurrency:
#    A PID-based lock file (/tmp/brew-autoupdate.lock) prevents overlapping
#    runs. If the machine was asleep and multiple scheduled runs fire at
#    once, only one will execute. Stale locks from crashed runs are
#    automatically cleaned up.
#
#  Configuration:
#    All behavior is controlled by config.conf in the same directory as
#    this script. See that file for all available options and defaults.
#    Changes take effect on the next scheduled (or manual) run.
#
#  Exit Codes:
#    0 - Success (or skipped due to concurrent run)
#    1 - Fatal error (e.g., Homebrew not found)
#
# ============================================================================

# ----------------------------------------------------------------------------
# Shell Options
# ----------------------------------------------------------------------------
# -e: Exit immediately on command failure (within functions/pipelines)
# -u: Treat unset variables as errors
# -o pipefail: Return the exit code of the last failed command in a pipeline
# ----------------------------------------------------------------------------
set -euo pipefail

# ============================================================================
# PATH AND DIRECTORY SETUP
# ============================================================================
# SCRIPT_DIR: Resolved absolute path to this script's directory.
#   Used to locate config.conf which must live alongside this script.
#   The cd/pwd pattern handles symlinks correctly.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"

# LOG_DIR: macOS-standard log location under ~/Library/Logs/.
#   This directory is visible in Console.app and respects macOS conventions.
# ----------------------------------------------------------------------------
LOG_DIR="${HOME}/Library/Logs/brew-autoupdate"

# LOCK_FILE: PID lock to prevent concurrent executions.
#   Placed in /tmp so it's automatically cleaned on reboot.
# ----------------------------------------------------------------------------
LOCK_FILE="/tmp/brew-autoupdate.lock"

# Subdirectories for the two-tier logging system
DETAIL_LOG_DIR="${LOG_DIR}/detail"
SUMMARY_LOG_DIR="${LOG_DIR}/summary"

# Create log directories if they don't exist (idempotent)
mkdir -p "${DETAIL_LOG_DIR}" "${SUMMARY_LOG_DIR}"

# ============================================================================
# TIMESTAMP GENERATION
# ============================================================================
# TIMESTAMP: Used for detail log filenames (one per run)
# DATE_STAMP: Used for summary log filenames (one per day, appended to)
# ----------------------------------------------------------------------------
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
DATE_STAMP="$(date '+%Y-%m-%d')"
DETAIL_LOG="${DETAIL_LOG_DIR}/${TIMESTAMP}.log"
SUMMARY_LOG="${SUMMARY_LOG_DIR}/${DATE_STAMP}.log"

# ============================================================================
# DEFAULT CONFIGURATION VALUES
# ============================================================================
# These defaults are used if config.conf is missing or a particular key
# is not defined. They provide sensible out-of-the-box behavior.
# See config.conf for detailed descriptions of each option.
# ----------------------------------------------------------------------------
DETAIL_LOG_RETENTION_DAYS=90      # Days to keep verbose detail logs
SUMMARY_LOG_RETENTION_DAYS=365    # Days to keep summary update logs
NOTIFY_ON_EVERY_RUN=true          # macOS notification after each run
NOTIFY_ON_ERROR=true              # macOS notification on errors
AUTO_UPGRADE=true                 # Whether to run 'brew upgrade'
AUTO_CLEANUP=true                 # Whether to run 'brew cleanup'
CLEANUP_OLDER_THAN_DAYS=0         # brew cleanup --prune=N (0=default)
AUTO_REMOVE=true                  # Whether to run 'brew autoremove'
UPGRADE_CASKS=true                # Include cask (GUI app) upgrades
UPGRADE_CASKS_GREEDY=false        # Upgrade casks that auto-update themselves
BREW_PATH=""                      # Override path to brew binary
BREW_ENV=""                       # Extra env vars for brew commands

# ============================================================================
# CONFIGURATION FILE LOADER
# ============================================================================
# Safely parses config.conf using a whitelist approach:
#   - Only recognized KEY names are accepted (case statement whitelist)
#   - Comments (# ...) and blank lines are skipped
#   - Inline comments after values are stripped
#   - Whitespace is trimmed from keys and values
#   - Uses 'declare' to set variables (safer than eval)
#
# This approach avoids sourcing the file directly, which would allow
# arbitrary code execution if the config file were compromised.
# ----------------------------------------------------------------------------
if [[ -f "${CONFIG_FILE}" ]]; then
    while IFS='=' read -r key value; do
        key="$(echo "${key}" | xargs)"                      # Trim whitespace
        [[ -z "${key}" || "${key}" == \#* ]] && continue     # Skip blanks/comments
        value="$(echo "${value}" | sed 's/#.*//' | xargs)"   # Strip inline comments, trim
        case "${key}" in
            DETAIL_LOG_RETENTION_DAYS|SUMMARY_LOG_RETENTION_DAYS|\
            NOTIFY_ON_EVERY_RUN|NOTIFY_ON_ERROR|\
            AUTO_UPGRADE|AUTO_CLEANUP|CLEANUP_OLDER_THAN_DAYS|\
            AUTO_REMOVE|UPGRADE_CASKS|UPGRADE_CASKS_GREEDY|\
            BREW_PATH|BREW_ENV)
                declare "${key}=${value}"
                ;;
            # Unrecognized keys are silently ignored for forward-compatibility
        esac
    done < "${CONFIG_FILE}"
fi

# ============================================================================
# HOMEBREW BINARY RESOLUTION
# ============================================================================
# Locates the brew binary using a priority order:
#   1. BREW_PATH from config (explicit override)
#   2. /opt/homebrew/bin/brew (Apple Silicon default)
#   3. /usr/local/bin/brew (Intel Mac default)
#   4. PATH lookup via 'which' (fallback)
#
# launchd runs with a minimal environment, so we can't rely on PATH alone.
# After finding brew, we run 'brew shellenv' to set up the complete
# environment (HOMEBREW_PREFIX, HOMEBREW_CELLAR, PATH additions, etc).
# ----------------------------------------------------------------------------
if [[ -n "${BREW_PATH}" ]]; then
    BREW="${BREW_PATH}"
elif [[ -x /opt/homebrew/bin/brew ]]; then
    BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
    BREW=/usr/local/bin/brew
else
    BREW="$(which brew 2>/dev/null || true)"
fi

# Fatal exit if brew cannot be found - nothing else can proceed
if [[ -z "${BREW}" || ! -x "${BREW}" ]]; then
    osascript -e 'display notification "Homebrew not found! Auto-update cannot run." with title "Brew Auto-Update" subtitle "ERROR"' 2>/dev/null || true
    echo "FATAL: brew not found" >&2
    exit 1
fi

# Initialize the full Homebrew shell environment.
# This sets HOMEBREW_PREFIX, HOMEBREW_CELLAR, updates PATH, etc.
# Essential when running under launchd's minimal environment.
eval "$(${BREW} shellenv 2>/dev/null)" || true

# Apply any extra environment variables specified in config.
# Format: BREW_ENV="HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1"
if [[ -n "${BREW_ENV}" ]]; then
    for pair in ${BREW_ENV}; do
        export "${pair}"
    done
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# log_detail - Write a timestamped message to the DETAIL log only.
#   Also outputs to stdout (which is redirected to the detail log via exec).
#   Use for verbose/diagnostic information not needed in summaries.
# ----------------------------------------------------------------------------
log_detail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${DETAIL_LOG}"
}

# log_summary - Write a timestamped message to the SUMMARY log only.
#   Use for recording significant events (updates applied, errors).
#   Summary logs accumulate throughout the day (appended).
# ----------------------------------------------------------------------------
log_summary() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${SUMMARY_LOG}"
}

# log_both - Write a timestamped message to BOTH detail and summary logs.
#   Use for milestone events: start, stop, errors, package changes.
# ----------------------------------------------------------------------------
log_both() {
    log_detail "$*"
    log_summary "$*"
}

# Redirect all stdout and stderr to the detail log file.
# The tee command ensures output still goes to stdout (visible if run
# manually from terminal) while also being captured in the log file.
# This catches ALL output, including from brew commands.
# ----------------------------------------------------------------------------
exec > >(tee -a "${DETAIL_LOG}") 2>&1

# ============================================================================
# NOTIFICATION FUNCTION
# ============================================================================
# Uses macOS native osascript to post to Notification Center.
# This works even from launchd daemons as long as the agent runs in
# the user's GUI session (LimitLoadToSessionType = Aqua).
#
# Arguments:
#   $1 - title:    Bold text at top of notification (e.g., "Brew Auto-Update")
#   $2 - subtitle: Secondary text (e.g., "ERRORS DETECTED")
#   $3 - message:  Body text with details
#
# The '|| true' ensures notification failures never abort the script.
# ----------------------------------------------------------------------------
notify() {
    local title="$1"
    local subtitle="$2"
    local message="$3"
    osascript -e "display notification \"${message}\" with title \"${title}\" subtitle \"${subtitle}\"" 2>/dev/null || true
}

# ============================================================================
# LOCK FILE MANAGEMENT
# ============================================================================
# Prevents concurrent runs using a PID-based lock file.
#
# Behavior:
#   - If lock exists and the PID is still running -> skip this run (exit 0)
#   - If lock exists but PID is dead -> stale lock, remove and continue
#   - If no lock -> create lock with current PID
#
# The EXIT trap ensures the lock is always cleaned up, even on errors.
# Using /tmp means the lock is also cleaned on system reboot.
# ----------------------------------------------------------------------------
acquire_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid="$(cat "${LOCK_FILE}" 2>/dev/null || echo "")"
        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            log_both "SKIP: Another instance (PID ${lock_pid}) is already running."
            exit 0
        else
            log_detail "Stale lock file found (PID ${lock_pid} not running). Removing."
            rm -f "${LOCK_FILE}"
        fi
    fi
    echo $$ > "${LOCK_FILE}"
    trap 'rm -f "${LOCK_FILE}"' EXIT
}

# ============================================================================
# LOG ROTATION
# ============================================================================
# Removes log files older than the configured retention periods.
#
# Uses 'find -mtime' which checks file modification time:
#   - Detail logs: removed after DETAIL_LOG_RETENTION_DAYS (default 90)
#   - Summary logs: removed after SUMMARY_LOG_RETENTION_DAYS (default 365)
#
# The -print0 / read -d '' pattern handles filenames with spaces safely.
# Rotation runs at the end of each update cycle.
# ----------------------------------------------------------------------------
rotate_logs() {
    log_detail "--- Log rotation ---"

    local detail_deleted=0
    local summary_deleted=0

    # Find and delete detail logs exceeding retention period
    while IFS= read -r -d '' old_log; do
        rm -f "${old_log}"
        ((detail_deleted++))
    done < <(find "${DETAIL_LOG_DIR}" -name "*.log" -type f -mtime +"${DETAIL_LOG_RETENTION_DAYS}" -print0 2>/dev/null)

    # Find and delete summary logs exceeding retention period
    while IFS= read -r -d '' old_log; do
        rm -f "${old_log}"
        ((summary_deleted++))
    done < <(find "${SUMMARY_LOG_DIR}" -name "*.log" -type f -mtime +"${SUMMARY_LOG_RETENTION_DAYS}" -print0 2>/dev/null)

    log_detail "Rotated: ${detail_deleted} detail logs (>${DETAIL_LOG_RETENTION_DAYS}d), ${summary_deleted} summary logs (>${SUMMARY_LOG_RETENTION_DAYS}d)"
    [[ ${detail_deleted} -gt 0 || ${summary_deleted} -gt 0 ]] && \
        log_summary "Log rotation: removed ${detail_deleted} detail, ${summary_deleted} summary logs"
}

# ============================================================================
# MAIN UPDATE PROCESS
# ============================================================================
# Orchestrates the complete Homebrew maintenance cycle. Each step is
# independently error-handled - a failure in one step does not prevent
# subsequent steps from running. Errors are accumulated and reported
# at the end via both logging and macOS notifications.
# ----------------------------------------------------------------------------
main() {
    # Error accumulator - each failed step appends a description
    local errors=()
    local updated_formulae=()
    local updated_casks=()
    local run_start run_end duration

    # Record start time for duration calculation
    run_start="$(date +%s)"

    # --- Header: Log run metadata for debugging ---
    log_both "========================================="
    log_both "Brew Auto-Update starting"
    log_both "========================================="
    log_detail "Config: AUTO_UPGRADE=${AUTO_UPGRADE}, AUTO_CLEANUP=${AUTO_CLEANUP}, AUTO_REMOVE=${AUTO_REMOVE}"
    log_detail "Config: UPGRADE_CASKS=${UPGRADE_CASKS}, UPGRADE_CASKS_GREEDY=${UPGRADE_CASKS_GREEDY}"
    log_detail "Config: DETAIL_RETENTION=${DETAIL_LOG_RETENTION_DAYS}d, SUMMARY_RETENTION=${SUMMARY_LOG_RETENTION_DAYS}d"
    log_detail "Brew: ${BREW} ($(${BREW} --version 2>/dev/null | head -1))"
    log_detail "macOS: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"

    # Acquire exclusive lock (exits if another instance is running)
    acquire_lock

    # -----------------------------------------------------------------
    # STEP 1: brew update
    # -----------------------------------------------------------------
    # Fetches the newest version of Homebrew and all formulae/cask
    # definitions from the tap repositories. This does NOT install
    # anything - it just updates the local package index.
    # --verbose: Shows each file being updated for troubleshooting
    # -----------------------------------------------------------------
    log_both "--- brew update ---"
    if ! ${BREW} update --verbose 2>&1; then
        errors+=("brew update failed")
        log_both "ERROR: brew update failed"
    else
        log_both "brew update completed successfully"
    fi

    # -----------------------------------------------------------------
    # STEP 2: Check for outdated packages
    # -----------------------------------------------------------------
    # Lists packages where a newer version is available.
    # --verbose: Shows current and available versions
    # This is informational - logged for the summary record.
    # -----------------------------------------------------------------
    log_detail "--- Checking outdated packages ---"
    local outdated_output
    outdated_output="$(${BREW} outdated --verbose 2>&1)" || true
    log_detail "Outdated packages:\n${outdated_output}"

    if [[ -z "${outdated_output}" ]]; then
        log_both "No outdated packages found."
    else
        log_summary "Outdated: ${outdated_output}"
    fi

    # -----------------------------------------------------------------
    # STEP 3: brew upgrade
    # -----------------------------------------------------------------
    # Installs newer versions of all outdated packages.
    # Captures before/after package lists to detect what actually changed
    # (brew's own output can be noisy and hard to parse).
    #
    # Cask behavior:
    #   UPGRADE_CASKS=true  -> includes GUI applications
    #   UPGRADE_CASKS_GREEDY=true -> also upgrades casks that have their
    #     own auto-update mechanisms (e.g., Chrome, Firefox)
    # -----------------------------------------------------------------
    if [[ "${AUTO_UPGRADE}" == "true" ]]; then
        log_both "--- brew upgrade ---"

        # Snapshot package versions before upgrade for diff comparison
        local pre_list
        pre_list="$(${BREW} list --versions 2>/dev/null)" || true

        # Build upgrade arguments based on configuration
        local upgrade_args=("--verbose")
        if [[ "${UPGRADE_CASKS}" == "true" ]]; then
            upgrade_args+=("--greedy") && [[ "${UPGRADE_CASKS_GREEDY}" == "true" ]] || upgrade_args=("--verbose")
        fi

        # Execute upgrade, capturing output for logging
        local upgrade_output
        if upgrade_output="$(${BREW} upgrade "${upgrade_args[@]}" 2>&1)"; then
            log_detail "${upgrade_output}"
            log_both "brew upgrade completed successfully"
        else
            log_detail "${upgrade_output}"
            errors+=("brew upgrade had errors")
            log_both "WARNING: brew upgrade completed with errors"
        fi

        # Diff package lists to identify exactly what changed
        # Lines starting with '<' are removed versions, '>' are new versions
        local post_list
        post_list="$(${BREW} list --versions 2>/dev/null)" || true

        local changes
        changes="$(diff <(echo "${pre_list}") <(echo "${post_list}") 2>/dev/null | grep '^[<>]' || true)"
        if [[ -n "${changes}" ]]; then
            log_both "Package changes:"
            log_both "${changes}"
        fi
    else
        log_both "Auto-upgrade disabled, skipping."
    fi

    # -----------------------------------------------------------------
    # STEP 4: brew cleanup
    # -----------------------------------------------------------------
    # Removes old versions of installed formulae, stale lock files,
    # and outdated downloads from the Homebrew cache.
    #
    # CLEANUP_OLDER_THAN_DAYS: If set >0, passed as --prune=N to remove
    #   downloads older than N days. If 0, uses brew's default (120 days).
    # -----------------------------------------------------------------
    if [[ "${AUTO_CLEANUP}" == "true" ]]; then
        log_both "--- brew cleanup ---"
        local cleanup_args=("--verbose")
        if [[ "${CLEANUP_OLDER_THAN_DAYS}" -gt 0 ]]; then
            cleanup_args+=("--prune=${CLEANUP_OLDER_THAN_DAYS}")
        fi

        local cleanup_output
        if cleanup_output="$(${BREW} cleanup "${cleanup_args[@]}" 2>&1)"; then
            log_detail "${cleanup_output}"
            log_both "brew cleanup completed"
        else
            log_detail "${cleanup_output}"
            errors+=("brew cleanup had errors")
            log_both "WARNING: brew cleanup had errors"
        fi
    fi

    # -----------------------------------------------------------------
    # STEP 5: brew autoremove
    # -----------------------------------------------------------------
    # Removes formulae that were installed as dependencies but are no
    # longer required by any installed formula. Helps prevent accumulation
    # of orphaned packages over time.
    # -----------------------------------------------------------------
    if [[ "${AUTO_REMOVE}" == "true" ]]; then
        log_both "--- brew autoremove ---"
        local autoremove_output
        if autoremove_output="$(${BREW} autoremove --verbose 2>&1)"; then
            log_detail "${autoremove_output}"
            log_both "brew autoremove completed"
        else
            log_detail "${autoremove_output}"
            errors+=("brew autoremove had errors")
            log_both "WARNING: brew autoremove had errors"
        fi
    fi

    # -----------------------------------------------------------------
    # STEP 6: brew doctor (diagnostic)
    # -----------------------------------------------------------------
    # Runs Homebrew's self-diagnostic tool. Non-fatal - warnings are
    # logged to detail only. Common warnings include:
    #   - Unlinked kegs
    #   - Deprecated/disabled formulae
    #   - Unexpected files in Homebrew directories
    # These are logged for awareness but do not trigger error notifications.
    # -----------------------------------------------------------------
    log_detail "--- brew doctor ---"
    local doctor_output
    if doctor_output="$(${BREW} doctor 2>&1)"; then
        log_detail "${doctor_output}"
        log_detail "brew doctor: all clear"
    else
        log_detail "${doctor_output}"
        log_detail "brew doctor reported warnings (non-fatal)"
    fi

    # -----------------------------------------------------------------
    # STEP 7: Log rotation
    # -----------------------------------------------------------------
    # Clean up old logs according to configured retention periods.
    # Runs at the end of every cycle to keep disk usage bounded.
    # -----------------------------------------------------------------
    rotate_logs

    # -----------------------------------------------------------------
    # FINAL: Summary and notifications
    # -----------------------------------------------------------------
    run_end="$(date +%s)"
    duration=$(( run_end - run_start ))

    log_both "========================================="
    log_both "Brew Auto-Update finished in ${duration}s"
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_both "ERRORS (${#errors[@]}): ${errors[*]}"
    else
        log_both "Status: SUCCESS (no errors)"
    fi
    log_both "========================================="

    # --- macOS Notification Center alerts ---
    # Priority: errors take precedence over success notifications
    if [[ ${#errors[@]} -gt 0 && "${NOTIFY_ON_ERROR}" == "true" ]]; then
        notify "Brew Auto-Update" "ERRORS DETECTED" "$(printf '%s\n' "${errors[@]}" | head -3). Check logs: ${DETAIL_LOG}"
    elif [[ "${NOTIFY_ON_EVERY_RUN}" == "true" ]]; then
        if [[ -n "${outdated_output}" ]]; then
            notify "Brew Auto-Update" "Completed (${duration}s)" "Updates applied. See logs for details."
        else
            notify "Brew Auto-Update" "Completed (${duration}s)" "All packages up to date."
        fi
    fi
}

# ============================================================================
# ENTRY POINT
# ============================================================================
# Passes any command-line arguments to main() for potential future use.
# Currently no arguments are expected (all config is via config.conf).
# ----------------------------------------------------------------------------
main "$@"
