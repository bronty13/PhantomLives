#!/usr/bin/env bash
# ============================================================================
#
#  HOMEBREW AUTO-UPDATE LOG VIEWER
#
#  File:        brew-autoupdate-viewer.sh
#  Version:     1.0.0
#  Author:      Generated with Claude Code
#  License:     MIT
#  Requires:    macOS, bash 3.2+
#
#  Description:
#    Command-line interface for viewing and managing Homebrew Auto-Update
#    logs, checking daemon status, and triggering manual update runs.
#    Installed as 'brew-logs' in the Homebrew bin directory for easy access.
#
#  Usage:
#    brew-logs                         Show latest detail log
#    brew-logs summary                 Show latest summary log
#    brew-logs summary today           Today's summary
#    brew-logs detail last 5           Last 5 detail logs
#    brew-logs errors                  Show only errors from recent logs
#    brew-logs tail                    Live tail the most recent detail log
#    brew-logs status                  Show daemon status and stats
#    brew-logs list [detail|summary]   List all log files
#    brew-logs config                  Show current configuration
#    brew-logs run                     Trigger a manual run now
#    brew-logs help                    Show full help text
#
#  Command Aliases:
#    d=detail, s=summary, e=errors, t=tail, st=status,
#    ls=list, c=config, r=run, h=help
#
# ============================================================================

# ============================================================================
# DIRECTORY AND FILE PATH CONSTANTS
# ============================================================================
# These must match the paths used by brew-autoupdate.sh and the installer.
# LOG_DIR follows macOS convention: ~/Library/Logs/<app-name>/
# CONFIG_FILE lives alongside the main script in ~/.config/brew-autoupdate/
# PLIST_LABEL must match the launchd plist filename (minus .plist extension)
# ----------------------------------------------------------------------------
LOG_DIR="${HOME}/Library/Logs/brew-autoupdate"
DETAIL_DIR="${LOG_DIR}/detail"
SUMMARY_DIR="${LOG_DIR}/summary"
CONFIG_FILE="${HOME}/.config/brew-autoupdate/config.conf"
SCRIPT_FILE="${HOME}/.config/brew-autoupdate/brew-autoupdate.sh"
PLIST_LABEL="com.user.brew-autoupdate"
PLIST_FILE="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"

# ============================================================================
# TERMINAL COLOR CODES
# ============================================================================
# ANSI escape sequences for colorized terminal output.
# NC (No Color) resets formatting. These are used with echo -e.
# Colors degrade gracefully in non-color terminals (displayed as empty strings).
# ----------------------------------------------------------------------------
RED='\033[0;31m'       # Errors, not-loaded status
GREEN='\033[0;32m'     # Success, loaded status, no-errors-found
YELLOW='\033[1;33m'    # Warnings, empty results
CYAN='\033[0;36m'      # File headers, informational
BOLD='\033[1m'         # Section titles
NC='\033[0m'           # Reset to default terminal color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# latest_file - Returns the most recently modified .log file in a directory.
#   Uses ls -t (sort by modification time, newest first) and takes the first.
#   Returns empty string if no log files exist.
#
# Arguments:
#   $1 - Directory path to search for .log files
# ----------------------------------------------------------------------------
latest_file() {
    local dir="$1"
    ls -t "${dir}"/*.log 2>/dev/null | head -1
}

# ============================================================================
# COMMAND PARSING
# ============================================================================
# Default command is 'detail' (show latest detail log) when invoked with
# no arguments. The 'shift' consumes $1 so remaining args are available
# to subcommand handlers.
# ----------------------------------------------------------------------------
cmd="${1:-detail}"
shift 2>/dev/null || true

# ============================================================================
# COMMAND ROUTER
# ============================================================================
# Each case handles a subcommand with its own argument parsing.
# Commands support short aliases (d, s, e, t, st, ls, c, r, h) for
# quick terminal use.
# ----------------------------------------------------------------------------
case "${cmd}" in

    # ========================================================================
    # DETAIL LOG VIEWER
    # ========================================================================
    # Shows verbose detail log files (one per run).
    #
    # Subcommands:
    #   latest (default) - Show the most recent detail log
    #   last N           - Show the N most recent detail logs
    # ------------------------------------------------------------------------
    detail|d)
        subcmd="${1:-latest}"
        case "${subcmd}" in
            latest|last)
                count="${2:-1}"  # Default to 1 log if no count specified
                # Get the N most recent log files, sorted newest first
                files=($(ls -t "${DETAIL_DIR}"/*.log 2>/dev/null | head -"${count}"))
                if [[ ${#files[@]} -eq 0 ]]; then
                    echo -e "${YELLOW}No detail logs found.${NC}"
                    exit 0
                fi
                # Display each log with a colored header showing the filename
                for f in "${files[@]}"; do
                    echo -e "${CYAN}=== $(basename "${f}") ===${NC}"
                    cat "${f}"
                    echo
                done
                ;;
            *)
                echo "Usage: brew-logs detail [latest|last N]"
                ;;
        esac
        ;;

    # ========================================================================
    # SUMMARY LOG VIEWER
    # ========================================================================
    # Shows summary log files (one per day, containing high-level events).
    #
    # Subcommands:
    #   latest (default) - Show the most recent summary log
    #   today            - Show today's summary specifically
    #   last N           - Show the N most recent summary days
    #   <DATE>           - Fuzzy match: shows any log with DATE in filename
    #                      e.g., "brew-logs summary 2026-03" shows all March logs
    # ------------------------------------------------------------------------
    summary|s)
        subcmd="${1:-latest}"
        case "${subcmd}" in
            latest)
                f="$(latest_file "${SUMMARY_DIR}")"
                if [[ -z "${f}" ]]; then
                    echo -e "${YELLOW}No summary logs found.${NC}"
                    exit 0
                fi
                echo -e "${CYAN}=== $(basename "${f}") ===${NC}"
                cat "${f}"
                ;;
            today)
                # Summary logs are named YYYY-MM-DD.log, matching today's date
                f="${SUMMARY_DIR}/$(date '+%Y-%m-%d').log"
                if [[ -f "${f}" ]]; then
                    echo -e "${CYAN}=== Today's Summary ===${NC}"
                    cat "${f}"
                else
                    echo -e "${YELLOW}No summary for today yet.${NC}"
                fi
                ;;
            last)
                count="${2:-5}"  # Default to 5 days if no count specified
                files=($(ls -t "${SUMMARY_DIR}"/*.log 2>/dev/null | head -"${count}"))
                if [[ ${#files[@]} -eq 0 ]]; then
                    echo -e "${YELLOW}No summary logs found.${NC}"
                    exit 0
                fi
                for f in "${files[@]}"; do
                    echo -e "${CYAN}=== $(basename "${f}") ===${NC}"
                    cat "${f}"
                    echo
                done
                ;;
            *)
                # Wildcard match: treat the argument as a date/string filter
                # e.g., "2026-03" matches 2026-03-01.log, 2026-03-02.log, etc.
                files=($(ls "${SUMMARY_DIR}"/*"${subcmd}"*.log 2>/dev/null))
                if [[ ${#files[@]} -eq 0 ]]; then
                    echo -e "${YELLOW}No summary logs matching '${subcmd}'.${NC}"
                else
                    for f in "${files[@]}"; do
                        echo -e "${CYAN}=== $(basename "${f}") ===${NC}"
                        cat "${f}"
                        echo
                    done
                fi
                ;;
        esac
        ;;

    # ========================================================================
    # ERROR SEARCH
    # ========================================================================
    # Searches all detail logs for lines containing error/fail/warning.
    # Shows the 50 most recent matching lines across all log files.
    # Useful for quickly checking if anything has gone wrong recently
    # without reading through entire log files.
    # ------------------------------------------------------------------------
    errors|e)
        echo -e "${BOLD}Recent errors across all logs:${NC}"
        echo
        grep -i -h "error\|fail\|warning" "${DETAIL_DIR}"/*.log 2>/dev/null | tail -50 || echo -e "${GREEN}No errors found.${NC}"
        ;;

    # ========================================================================
    # LIVE TAIL
    # ========================================================================
    # Uses 'tail -f' to follow the most recent detail log in real-time.
    # Useful when watching a manual run (brew-logs run) in another terminal.
    # Press Ctrl+C to stop following.
    # ------------------------------------------------------------------------
    tail|t)
        f="$(latest_file "${DETAIL_DIR}")"
        if [[ -z "${f}" ]]; then
            echo -e "${YELLOW}No detail logs to tail.${NC}"
            exit 0
        fi
        echo -e "${CYAN}Tailing: ${f}${NC}"
        tail -f "${f}"
        ;;

    # ========================================================================
    # DAEMON STATUS
    # ========================================================================
    # Shows a dashboard of the auto-update system's health:
    #   - Whether the launchd daemon is loaded and running
    #   - Count of existing log files in each tier
    #   - Timestamp of the most recent run
    #   - Disk space consumed by logs
    # ------------------------------------------------------------------------
    status|st)
        echo -e "${BOLD}Brew Auto-Update Daemon Status${NC}"
        echo -e "─────────────────────────────────"

        # Check if the launchd job is loaded (registered with the system)
        if launchctl list "${PLIST_LABEL}" &>/dev/null; then
            echo -e "Daemon:  ${GREEN}LOADED${NC}"
            launchctl list "${PLIST_LABEL}" 2>/dev/null | head -5
        else
            echo -e "Daemon:  ${RED}NOT LOADED${NC}"
        fi
        echo

        # Log file statistics
        echo -e "${BOLD}Log statistics:${NC}"
        detail_count=$(ls "${DETAIL_DIR}"/*.log 2>/dev/null | wc -l | xargs)
        summary_count=$(ls "${SUMMARY_DIR}"/*.log 2>/dev/null | wc -l | xargs)
        echo "  Detail logs:  ${detail_count} files"
        echo "  Summary logs: ${summary_count} files"

        # Most recent run timestamp (extracted from detail log filename)
        latest_detail="$(latest_file "${DETAIL_DIR}")"
        if [[ -n "${latest_detail}" ]]; then
            echo -e "  Last run:     $(basename "${latest_detail}" .log | tr '_' ' ')"
        fi

        # Disk usage per log tier
        echo
        echo -e "${BOLD}Disk usage:${NC}"
        du -sh "${DETAIL_DIR}" 2>/dev/null | awk '{print "  Detail: " $1}'
        du -sh "${SUMMARY_DIR}" 2>/dev/null | awk '{print "  Summary: " $1}'
        ;;

    # ========================================================================
    # LOG FILE LISTING
    # ========================================================================
    # Lists all log files with sizes and dates (ls -lht format).
    # Can be filtered to show only 'detail' or 'summary' logs.
    # Default: show both.
    # ------------------------------------------------------------------------
    list|ls)
        logtype="${1:-both}"
        if [[ "${logtype}" == "detail" || "${logtype}" == "both" ]]; then
            echo -e "${BOLD}Detail logs:${NC}"
            ls -lht "${DETAIL_DIR}"/*.log 2>/dev/null || echo "  (none)"
            echo
        fi
        if [[ "${logtype}" == "summary" || "${logtype}" == "both" ]]; then
            echo -e "${BOLD}Summary logs:${NC}"
            ls -lht "${SUMMARY_DIR}"/*.log 2>/dev/null || echo "  (none)"
        fi
        ;;

    # ========================================================================
    # CONFIGURATION DISPLAY
    # ========================================================================
    # Shows the current active configuration by displaying all non-comment,
    # non-blank lines from config.conf. Useful for verifying settings
    # without opening the file in an editor.
    # ------------------------------------------------------------------------
    config|c)
        echo -e "${BOLD}Current configuration:${NC}"
        echo -e "─────────────────────────────────"
        if [[ -f "${CONFIG_FILE}" ]]; then
            grep -v '^\s*#' "${CONFIG_FILE}" | grep -v '^\s*$'
        else
            echo -e "${RED}Config file not found: ${CONFIG_FILE}${NC}"
        fi
        ;;

    # ========================================================================
    # MANUAL RUN TRIGGER
    # ========================================================================
    # Executes the update script immediately in the foreground.
    # Output is displayed in the terminal AND captured in log files.
    # The lock file mechanism prevents conflicts with scheduled runs.
    # ------------------------------------------------------------------------
    run|r)
        echo -e "${CYAN}Triggering manual brew auto-update...${NC}"
        bash "${SCRIPT_FILE}"
        echo -e "${GREEN}Done. Check logs with: brew-logs detail${NC}"
        ;;

    # ========================================================================
    # HELP TEXT
    # ========================================================================
    help|h|--help|-h)
        echo -e "${BOLD}Homebrew Auto-Update Log Viewer${NC}"
        echo
        echo "Usage: brew-logs <command> [options]"
        echo
        echo "Commands:"
        echo "  detail [latest|last N]     Show detail log(s) (default: latest)"
        echo "  summary [latest|today|last N|DATE]  Show summary log(s)"
        echo "  errors                     Show recent errors across all logs"
        echo "  tail                       Live tail the latest detail log"
        echo "  status                     Show daemon status and stats"
        echo "  list [detail|summary]      List all log files"
        echo "  config                     Show current configuration"
        echo "  run                        Trigger a manual update run"
        echo "  help                       Show this help"
        echo
        echo "Aliases: d=detail, s=summary, e=errors, t=tail, st=status,"
        echo "         ls=list, c=config, r=run, h=help"
        ;;

    # ========================================================================
    # UNKNOWN COMMAND HANDLER
    # ========================================================================
    *)
        echo "Unknown command: ${cmd}"
        echo "Run 'brew-logs help' for usage."
        exit 1
        ;;
esac
