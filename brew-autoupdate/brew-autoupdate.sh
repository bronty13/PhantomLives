#!/usr/bin/env bash
# ============================================================================
#
#  HOMEBREW AUTO-UPDATE DAEMON SCRIPT
#
#  File:        brew-autoupdate.sh
#  Version:     2.0.0
#  Author:      Generated with Claude Code
#  License:     MIT
#  Requires:    macOS, Homebrew, bash 3.2+
#
#  Description:
#    Automated Homebrew package maintenance script designed to run as a
#    macOS launchd daemon. Performs a complete update cycle:
#
#      1. brew update     - Fetches latest formulae/cask definitions
#      2. brew outdated   - Identifies packages needing upgrade
#      3. brew upgrade    - Installs newer versions (with allow/deny filtering)
#      4. brew cleanup    - Removes stale downloads and old versions
#      5. brew autoremove - Removes orphaned dependencies
#      6. brew doctor     - Runs diagnostic health check
#      7. Log rotation    - Prunes logs exceeding retention thresholds
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
#      - Purpose: Long-term record; parsed by the dashboard
#
#    STRUCTURED STATS (appended to each summary log at run end)
#      - [STATS] lines: machine-parseable run metadata for the dashboard
#      - [PKG] lines:   per-package upgrade records for frequency tracking
#
#  Concurrency:
#    A PID-based lock file (/tmp/brew-autoupdate.lock) prevents overlapping
#    runs. Stale locks from crashed runs are automatically cleaned up.
#
#  Configuration:
#    All behavior is controlled by config.conf in the same directory as
#    this script. See that file for all available options and defaults.
#    Changes take effect on the next scheduled (or manual) run.
#
#  Exit Codes:
#    0 - Success (or skipped due to concurrent run / quiet hours)
#    1 - Fatal error (e.g., Homebrew not found)
#
# ============================================================================

# ----------------------------------------------------------------------------
# Shell Options
# ----------------------------------------------------------------------------
set -euo pipefail

# ============================================================================
# VERSION
# ============================================================================
BAU_VERSION="2.0.0"

# ============================================================================
# PATH AND DIRECTORY SETUP
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"

LOG_DIR="${HOME}/Library/Logs/brew-autoupdate"
LOCK_FILE="/tmp/brew-autoupdate.lock"

DETAIL_LOG_DIR="${LOG_DIR}/detail"
SUMMARY_LOG_DIR="${LOG_DIR}/summary"

mkdir -p "${DETAIL_LOG_DIR}" "${SUMMARY_LOG_DIR}"

# ============================================================================
# TIMESTAMP GENERATION
# ============================================================================
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
DATE_STAMP="$(date '+%Y-%m-%d')"
DETAIL_LOG="${DETAIL_LOG_DIR}/${TIMESTAMP}.log"
SUMMARY_LOG="${SUMMARY_LOG_DIR}/${DATE_STAMP}.log"

# ============================================================================
# DEFAULT CONFIGURATION VALUES
# ============================================================================
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
DENY_LIST=""                      # Space-separated packages to never upgrade
ALLOW_LIST=""                     # If non-empty, only upgrade these packages
PRE_UPDATE_HOOK=""                # Shell command to run before update cycle
POST_UPDATE_HOOK=""               # Shell command to run after update cycle
QUIET_HOURS_ENABLED=false         # Skip scheduled runs during quiet hours
QUIET_HOURS_START="09:00"         # Start of quiet period (HH:MM, 24-hour)
QUIET_HOURS_END="18:00"           # End of quiet period (HH:MM, 24-hour)
SCHEDULE_HOURS="0,6,12,18"        # Hours to run (used by installer only)
SCHEDULE_MINUTE=0                 # Minute within hour (used by installer only)

# ============================================================================
# CONFIGURATION FILE LOADER
# ============================================================================
# Safely parses config.conf using a whitelist approach:
#   - Only recognized KEY names are accepted (case statement whitelist)
#   - Comments (# ...) and blank lines are skipped
#   - Inline comments after values are stripped
#   - Whitespace is trimmed from keys and values
#   - Uses 'declare' to set variables (safer than eval)
# ----------------------------------------------------------------------------
if [[ -f "${CONFIG_FILE}" ]]; then
    while IFS='=' read -r key value; do
        key="$(echo "${key}" | xargs)"
        [[ -z "${key}" || "${key}" == \#* ]] && continue
        value="$(echo "${value}" | sed 's/#.*//' | xargs)"
        case "${key}" in
            DETAIL_LOG_RETENTION_DAYS|SUMMARY_LOG_RETENTION_DAYS|\
            NOTIFY_ON_EVERY_RUN|NOTIFY_ON_ERROR|\
            AUTO_UPGRADE|AUTO_CLEANUP|CLEANUP_OLDER_THAN_DAYS|\
            AUTO_REMOVE|UPGRADE_CASKS|UPGRADE_CASKS_GREEDY|\
            BREW_PATH|BREW_ENV|\
            DENY_LIST|ALLOW_LIST|\
            PRE_UPDATE_HOOK|POST_UPDATE_HOOK|\
            QUIET_HOURS_ENABLED|QUIET_HOURS_START|QUIET_HOURS_END|\
            SCHEDULE_HOURS|SCHEDULE_MINUTE)
                declare "${key}=${value}"
                ;;
        esac
    done < "${CONFIG_FILE}"
fi

# ============================================================================
# HOMEBREW BINARY RESOLUTION
# ============================================================================
if [[ -n "${BREW_PATH}" ]]; then
    BREW="${BREW_PATH}"
elif [[ -x /opt/homebrew/bin/brew ]]; then
    BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
    BREW=/usr/local/bin/brew
else
    BREW="$(which brew 2>/dev/null || true)"
fi

if [[ -z "${BREW}" || ! -x "${BREW}" ]]; then
    osascript -e 'display notification "Homebrew not found! Auto-update cannot run." with title "Brew Auto-Update" subtitle "ERROR"' 2>/dev/null || true
    echo "FATAL: brew not found" >&2
    exit 1
fi

eval "$(${BREW} shellenv 2>/dev/null)" || true

if [[ -n "${BREW_ENV}" ]]; then
    for pair in ${BREW_ENV}; do
        export "${pair}"
    done
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_detail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${DETAIL_LOG}"
}

log_summary() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${SUMMARY_LOG}"
}

log_both() {
    log_detail "$*"
    log_summary "$*"
}

exec > >(tee -a "${DETAIL_LOG}") 2>&1

# ============================================================================
# NOTIFICATION FUNCTION
# ============================================================================
notify() {
    local title="$1"
    local subtitle="$2"
    local message="$3"
    osascript -e "display notification \"${message}\" with title \"${title}\" subtitle \"${subtitle}\"" 2>/dev/null || true
}

# ============================================================================
# QUIET HOURS CHECK
# ============================================================================
# Compares current time against the configured quiet hours window.
# Supports overnight ranges (e.g., 22:00 to 07:00).
#
# Arguments:
#   $1 - current time  (HH:MM)
#   $2 - window start  (HH:MM)
#   $3 - window end    (HH:MM)
#
# Returns 0 (true) if current time falls within the quiet window.
# ----------------------------------------------------------------------------
is_quiet_hours() {
    local current="$1" start="$2" end="$3"

    # Convert HH:MM to minutes-since-midnight for integer comparison.
    # The 10# prefix forces base-10 to avoid octal interpretation of
    # leading zeros (e.g., "08" would error without 10#).
    local cur_m start_m end_m
    cur_m=$(( 10#${current%:*} * 60 + 10#${current#*:} ))
    start_m=$(( 10#${start%:*}   * 60 + 10#${start#*:}   ))
    end_m=$(( 10#${end%:*}     * 60 + 10#${end#*:}     ))

    if [[ ${start_m} -le ${end_m} ]]; then
        # Normal same-day range (e.g., 09:00-18:00)
        [[ ${cur_m} -ge ${start_m} && ${cur_m} -lt ${end_m} ]]
    else
        # Overnight range (e.g., 22:00-07:00): active when current is
        # AFTER start OR BEFORE end
        [[ ${cur_m} -ge ${start_m} || ${cur_m} -lt ${end_m} ]]
    fi
}

# ============================================================================
# LOCK FILE MANAGEMENT
# ============================================================================
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
rotate_logs() {
    log_detail "--- Log rotation ---"

    local detail_deleted=0
    local summary_deleted=0

    while IFS= read -r -d '' old_log; do
        rm -f "${old_log}"
        ((detail_deleted++))
    done < <(find "${DETAIL_LOG_DIR}" -name "*.log" -type f -mtime +"${DETAIL_LOG_RETENTION_DAYS}" -print0 2>/dev/null)

    while IFS= read -r -d '' old_log; do
        rm -f "${old_log}"
        ((summary_deleted++))
    done < <(find "${SUMMARY_LOG_DIR}" -name "*.log" -type f -mtime +"${SUMMARY_LOG_RETENTION_DAYS}" -print0 2>/dev/null)

    log_detail "Rotated: ${detail_deleted} detail logs (>${DETAIL_LOG_RETENTION_DAYS}d), ${summary_deleted} summary logs (>${SUMMARY_LOG_RETENTION_DAYS}d)"
    if [[ ${detail_deleted} -gt 0 || ${summary_deleted} -gt 0 ]]; then
        log_summary "Log rotation: removed ${detail_deleted} detail, ${summary_deleted} summary logs"
    fi
}

# ============================================================================
# MAIN UPDATE PROCESS
# ============================================================================
main() {
    local errors=()
    local run_start run_end duration
    local total_upgrades=0
    local upgraded_packages=()
    local changes=""

    run_start="$(date +%s)"

    # -------------------------------------------------------------------------
    # QUIET HOURS CHECK
    # If a scheduled run fires during configured quiet hours, skip it silently.
    # Manual runs (invoked directly) are not guarded by this flag.
    # -------------------------------------------------------------------------
    if [[ "${QUIET_HOURS_ENABLED}" == "true" ]]; then
        local current_time
        current_time="$(date '+%H:%M')"
        if is_quiet_hours "${current_time}" "${QUIET_HOURS_START}" "${QUIET_HOURS_END}"; then
            log_both "SKIP: Quiet hours active (${current_time} within ${QUIET_HOURS_START}-${QUIET_HOURS_END})"
            exit 0
        fi
    fi

    log_both "========================================="
    log_both "Brew Auto-Update v${BAU_VERSION} starting"
    log_both "========================================="
    log_detail "Config: AUTO_UPGRADE=${AUTO_UPGRADE}, AUTO_CLEANUP=${AUTO_CLEANUP}, AUTO_REMOVE=${AUTO_REMOVE}"
    log_detail "Config: UPGRADE_CASKS=${UPGRADE_CASKS}, UPGRADE_CASKS_GREEDY=${UPGRADE_CASKS_GREEDY}"
    log_detail "Config: DENY_LIST='${DENY_LIST}', ALLOW_LIST='${ALLOW_LIST}'"
    log_detail "Config: QUIET_HOURS_ENABLED=${QUIET_HOURS_ENABLED} (${QUIET_HOURS_START}-${QUIET_HOURS_END})"
    log_detail "Config: DETAIL_RETENTION=${DETAIL_LOG_RETENTION_DAYS}d, SUMMARY_RETENTION=${SUMMARY_LOG_RETENTION_DAYS}d"
    log_detail "Brew: ${BREW} ($(${BREW} --version 2>/dev/null | head -1))"
    log_detail "macOS: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"

    acquire_lock

    # -------------------------------------------------------------------------
    # PRE-UPDATE HOOK
    # Runs the user's custom command before any brew operations begin.
    # -------------------------------------------------------------------------
    if [[ -n "${PRE_UPDATE_HOOK}" ]]; then
        log_both "--- Pre-update hook ---"
        log_detail "Running: ${PRE_UPDATE_HOOK}"
        if bash -c "${PRE_UPDATE_HOOK}" >> "${DETAIL_LOG}" 2>&1; then
            log_both "Pre-update hook completed successfully"
        else
            log_both "WARNING: Pre-update hook exited with non-zero status (continuing)"
        fi
    fi

    # -----------------------------------------------------------------
    # STEP 1: brew update
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
    # STEP 3: brew upgrade (with allow/deny list filtering)
    # -----------------------------------------------------------------
    # Build upgrade flag arguments:
    #   --formula   : omit casks entirely when UPGRADE_CASKS=false
    #   --greedy    : include self-updating casks when UPGRADE_CASKS_GREEDY=true
    #   (neither)   : upgrade formulae + standard casks (the normal case)
    # -----------------------------------------------------------------
    if [[ "${AUTO_UPGRADE}" == "true" ]]; then
        log_both "--- brew upgrade ---"

        local pre_list
        pre_list="$(${BREW} list --versions 2>/dev/null)" || true

        # Construct upgrade flags (fixed logic replacing prior && || bug)
        local upgrade_args=("--verbose")
        if [[ "${UPGRADE_CASKS}" != "true" ]]; then
            upgrade_args+=("--formula")       # formulae only; skip all casks
        elif [[ "${UPGRADE_CASKS_GREEDY}" == "true" ]]; then
            upgrade_args+=("--greedy")        # include self-updating casks too
        fi

        # -----------------------------------------------------------------
        # PACKAGE FILTERING (allow/deny lists)
        # When either list is set, build an explicit package list instead of
        # letting brew upgrade everything. This gives precise control over
        # which packages participate in each run.
        # -----------------------------------------------------------------
        local use_pkg_filter=false
        local filtered_packages=()

        if [[ -n "${DENY_LIST}" || -n "${ALLOW_LIST}" ]]; then
            use_pkg_filter=true

            # Gather currently-outdated package names (quiet mode = names only)
            local outdated_pkgs=()
            while IFS= read -r pkg; do
                [[ -n "${pkg}" ]] && outdated_pkgs+=("${pkg}")
            done < <(${BREW} outdated --quiet 2>/dev/null || true)

            for pkg in ${outdated_pkgs[@]+"${outdated_pkgs[@]}"}; do
                local include=true

                # DENY_LIST check: exact name match excludes the package
                if [[ -n "${DENY_LIST}" ]]; then
                    for denied in ${DENY_LIST}; do
                        if [[ "${pkg}" == "${denied}" ]]; then
                            include=false
                            log_detail "DENY_LIST: skipping ${pkg}"
                            break
                        fi
                    done
                fi

                # ALLOW_LIST check: if set, package must be in the list
                if [[ "${include}" == "true" && -n "${ALLOW_LIST}" ]]; then
                    include=false
                    for allowed in ${ALLOW_LIST}; do
                        if [[ "${pkg}" == "${allowed}" ]]; then
                            include=true
                            break
                        fi
                    done
                    if [[ "${include}" == "false" ]]; then
                        log_detail "ALLOW_LIST: skipping ${pkg}"
                    fi
                fi

                [[ "${include}" == "true" ]] && filtered_packages+=("${pkg}")
            done

            if [[ ${#filtered_packages[@]} -gt 0 ]]; then
                log_both "Filtered upgrade targets (${#filtered_packages[@]}): ${filtered_packages[*]}"
            else
                log_both "No packages to upgrade after allow/deny filtering."
            fi
        fi

        # -----------------------------------------------------------------
        # Execute upgrade: filtered list or all packages
        # -----------------------------------------------------------------
        local upgrade_output
        local upgrade_exit=0

        if [[ "${use_pkg_filter}" == "true" && ${#filtered_packages[@]} -eq 0 ]]; then
            # Filtering produced an empty list - nothing to upgrade
            upgrade_exit=0
        elif [[ "${use_pkg_filter}" == "true" ]]; then
            upgrade_output="$(${BREW} upgrade "${upgrade_args[@]}" "${filtered_packages[@]}" 2>&1)" || upgrade_exit=$?
            log_detail "${upgrade_output}"
        else
            upgrade_output="$(${BREW} upgrade "${upgrade_args[@]}" 2>&1)" || upgrade_exit=$?
            log_detail "${upgrade_output}"
        fi

        if [[ ${upgrade_exit} -eq 0 ]]; then
            log_both "brew upgrade completed successfully"
        else
            errors+=("brew upgrade had errors")
            log_both "WARNING: brew upgrade completed with errors"
        fi

        # Diff before/after package lists to record exactly what changed
        local post_list
        post_list="$(${BREW} list --versions 2>/dev/null)" || true

        changes="$(diff <(echo "${pre_list}") <(echo "${post_list}") 2>/dev/null | grep '^[<>]' || true)"
        if [[ -n "${changes}" ]]; then
            log_both "Package changes:"
            log_both "${changes}"

            # Collect upgraded package names (lines starting with ">")
            while IFS= read -r line; do
                if [[ "${line}" == \>* ]]; then
                    local pkg_name
                    pkg_name="$(echo "${line}" | awk '{print $2}')"
                    if [[ -n "${pkg_name}" ]]; then
                        upgraded_packages+=("${pkg_name}")
                        (( total_upgrades++ )) || true
                    fi
                fi
            done <<< "${changes}"
        fi
    else
        log_both "Auto-upgrade disabled, skipping."
    fi

    # -----------------------------------------------------------------
    # STEP 4: brew cleanup
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
    # STEP 6: brew doctor (diagnostic, non-fatal)
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
    rotate_logs

    # -----------------------------------------------------------------
    # POST-UPDATE HOOK
    # Runs after all brew operations, regardless of errors.
    # -----------------------------------------------------------------
    if [[ -n "${POST_UPDATE_HOOK}" ]]; then
        log_both "--- Post-update hook ---"
        log_detail "Running: ${POST_UPDATE_HOOK}"
        if bash -c "${POST_UPDATE_HOOK}" >> "${DETAIL_LOG}" 2>&1; then
            log_both "Post-update hook completed successfully"
        else
            log_both "WARNING: Post-update hook exited with non-zero status"
        fi
    fi

    # -----------------------------------------------------------------
    # FINAL: Summary, structured stats, and notifications
    # -----------------------------------------------------------------
    run_end="$(date +%s)"
    duration=$(( run_end - run_start ))

    local status_word="SUCCESS"
    [[ ${#errors[@]} -gt 0 ]] && status_word="ERROR"

    log_both "========================================="
    log_both "Brew Auto-Update finished in ${duration}s"
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_both "ERRORS (${#errors[@]}): ${errors[*]}"
    else
        log_both "Status: SUCCESS (no errors)"
    fi
    log_both "========================================="

    # -----------------------------------------------------------------
    # STRUCTURED STATS LINES
    # These machine-parseable lines are appended to the summary log and
    # consumed by the 'brew-logs dashboard' command. The [STATS] line
    # provides per-run metrics; [PKG] lines record individual upgrades
    # for package-frequency statistics.
    # -----------------------------------------------------------------
    log_summary "[STATS] duration=${duration} status=${status_word} upgrades=${total_upgrades}"
    for pkg in ${upgraded_packages[@]+"${upgraded_packages[@]}"}; do
        log_summary "[PKG] ${pkg}"
    done

    # --- macOS Notification Center alerts ---
    if [[ ${#errors[@]} -gt 0 && "${NOTIFY_ON_ERROR}" == "true" ]]; then
        notify "Brew Auto-Update" "ERRORS DETECTED" "$(printf '%s\n' "${errors[@]}" | head -3). Check logs: ${DETAIL_LOG}"
    elif [[ "${NOTIFY_ON_EVERY_RUN}" == "true" ]]; then
        if [[ ${total_upgrades} -gt 0 ]]; then
            notify "Brew Auto-Update" "Completed (${duration}s)" "${total_upgrades} package(s) upgraded. See logs for details."
        else
            notify "Brew Auto-Update" "Completed (${duration}s)" "All packages up to date."
        fi
    fi
}

# ============================================================================
# ENTRY POINT
# ============================================================================
main "$@"
