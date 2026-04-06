#!/usr/bin/env bash
# ============================================================================
#
#  HOMEBREW AUTO-UPDATE LOG VIEWER
#
#  File:        brew-autoupdate-viewer.sh
#  Version:     2.1.0
#  Author:      Generated with Claude Code
#  License:     MIT
#  Requires:    macOS, bash 3.2+
#
#  Description:
#    Command-line interface for viewing and managing Homebrew Auto-Update
#    logs, checking daemon status, triggering manual updates, managing
#    the run schedule, and displaying a graphical console dashboard.
#    Installed as 'brew-logs' in the Homebrew bin directory for easy access.
#
#  Usage:
#    brew-logs                         Show latest detail log
#    brew-logs dashboard               Graphical status/stats dashboard
#    brew-logs summary                 Show latest summary log
#    brew-logs summary today           Today's summary
#    brew-logs detail last 5           Last 5 detail logs
#    brew-logs errors                  Show only errors from recent logs
#    brew-logs tail                    Live tail the most recent detail log
#    brew-logs status                  Show daemon status and stats
#    brew-logs list [detail|summary]   List all log files
#    brew-logs config                  Show current configuration
#    brew-logs schedule                Show current schedule
#    brew-logs schedule reload         Apply schedule changes from config
#    brew-logs run                     Trigger a manual run now
#    brew-logs help                    Show full help text
#
#  Command Aliases:
#    dash=dashboard, d=detail, s=summary, e=errors, t=tail, st=status,
#    ls=list, c=config, sched=schedule, r=run, h=help
#
# ============================================================================

# ============================================================================
# VERSION
# ============================================================================
BAU_VERSION="2.1.0"

# ============================================================================
# DIRECTORY AND FILE PATH CONSTANTS
# ============================================================================
LOG_DIR="${HOME}/Library/Logs/brew-autoupdate"
DETAIL_DIR="${LOG_DIR}/detail"
SUMMARY_DIR="${LOG_DIR}/summary"
CONFIG_FILE="${HOME}/.config/brew-autoupdate/config.conf"
SCRIPT_FILE="${HOME}/.config/brew-autoupdate/brew-autoupdate.sh"
INSTALL_SCRIPT="${HOME}/.config/brew-autoupdate/install.sh"
PLIST_LABEL="com.user.brew-autoupdate"
PLIST_FILE="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"

# ============================================================================
# TERMINAL COLOR CODES
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================================
# VERSION HEADER
# ============================================================================
# Prints a single dim line showing the tool name and version.
# Called once before every command's output so the version is always visible.
# Skipped by cmd_dashboard(), which incorporates the version into its own
# full-screen title bar instead.
print_version_header() {
    echo -e "${DIM}brew-logs v${BAU_VERSION}  ·  Homebrew Auto-Update${NC}"
}

# ============================================================================
# GENERAL HELPER FUNCTIONS
# ============================================================================

# latest_file - Returns the most recently modified .log file in a directory.
latest_file() {
    local dir="$1"
    ls -t "${dir}"/*.log 2>/dev/null | head -1
}

# read_cfg - Read a single value from config.conf by key name.
#   $1 = key name
#   $2 = default value if key not found
read_cfg() {
    local key="$1" default="${2:-}"
    if [[ -f "${CONFIG_FILE}" ]]; then
        local val
        val=$(grep "^${key}=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/[[:space:]]#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
        echo "${val:-${default}}"
    else
        echo "${default}"
    fi
}

# ============================================================================
# DASHBOARD RENDERING ENGINE
# ============================================================================
# Draws a full-terminal-width console dashboard with Unicode box-drawing
# characters. Width adapts to the current terminal size (min 72 cols).
#
# Layout sections (top to bottom):
#   Header     - title + timestamp
#   Status     - daemon health, last run info, schedule, quiet hours
#   Recent     - table of last N runs parsed from summary logs
#   Statistics - cumulative totals from [STATS] lines in summary logs
#   Top Pkgs   - bar chart of most-frequently upgraded packages
#   Config     - current key settings at a glance
# ============================================================================

# ---------------------------------------------------------------------------
# Dashboard width globals (set by _dash_init)
# ---------------------------------------------------------------------------
_W=80       # terminal width in columns
_IW=76      # inner width  = _W - 4  (accounts for "║ " + " ║")

_dash_init() {
    _W=$(tput cols 2>/dev/null || echo 80)
    [[ ${_W} -lt 72 ]] && _W=72
    _IW=$(( _W - 4 ))
}

# ---------------------------------------------------------------------------
# Border-line drawing functions
# ---------------------------------------------------------------------------
_dash_top() {
    printf '╔'
    local i; for ((i=0; i<_W-2; i++)); do printf '═'; done
    printf '╗\n'
}
_dash_div() {
    printf '╠'
    local i; for ((i=0; i<_W-2; i++)); do printf '═'; done
    printf '╣\n'
}
_dash_bot() {
    printf '╚'
    local i; for ((i=0; i<_W-2; i++)); do printf '═'; done
    printf '╝\n'
}
_dash_thin() {
    # Thin horizontal rule inside a section (does NOT span borders)
    local i; printf '║ '
    for ((i=0; i<_IW; i++)); do printf '─'; done
    printf ' ║\n'
}

# _dash_row <plain-text> [<colored-text>]
#   Renders one content row with left/right borders.
#   If a second argument is provided, it is used for display (may contain
#   ANSI codes); the first argument (plain) is used only for length calculation.
#   If only one argument is given, it is used for both.
_dash_row() {
    local plain="${1:-}"
    local colored="${2:-${plain}}"
    local vlen=${#plain}
    local pad=$(( _IW - vlen ))
    [[ ${pad} -lt 0 ]] && pad=0
    printf "║ %b%*s ║\n" "${colored}" "${pad}" ""
}

_dash_blank() {
    printf "║ %*s ║\n" "${_IW}" ""
}

# _dash_kv <key> <plain-value> [<colored-value>]
#   Renders a labelled key-value row: "  KEY    value"
_dash_kv() {
    local key="$1" plain_val="$2" colored_val="${3:-$2}"
    local label_w=20
    local content_plain
    printf -v content_plain "  %-${label_w}s%s" "${key}" "${plain_val}"
    local content_colored
    printf -v content_colored "  ${BOLD}%-${label_w}s${NC}%b" "${key}" "${colored_val}"
    _dash_row "${content_plain}" "${content_colored}"
}

# ---------------------------------------------------------------------------
# Statistics parser — reads all summary logs and extracts structured data
# ---------------------------------------------------------------------------
# Outputs shell variable assignments sourced by cmd_dashboard:
#   STAT_TOTAL_RUNS, STAT_SUCCESS, STAT_ERRORS, STAT_TOTAL_DURATION,
#   STAT_TOTAL_UPGRADES, STAT_UNIQUE_PKGS
#   STAT_RUNS_RAW   (tab-separated run records for recent-runs table)
#   STAT_PKG_COUNTS (sorted "count name" lines for bar chart)
# ---------------------------------------------------------------------------
_parse_stats() {
    if ! ls "${SUMMARY_DIR}"/*.log &>/dev/null; then
        cat <<'EOF'
STAT_TOTAL_RUNS=0
STAT_SUCCESS=0
STAT_ERRORS=0
STAT_TOTAL_DURATION=0
STAT_TOTAL_UPGRADES=0
STAT_UNIQUE_PKGS=0
STAT_RUNS_RAW=""
STAT_PKG_COUNTS=""
EOF
        return
    fi

    # ------------------------------------------------------------------
    # Parse [STATS] lines for run-level metrics (new structured format):
    #   [2026-03-31 12:00:48] [STATS] duration=47 status=SUCCESS upgrades=3
    # ------------------------------------------------------------------
    local stats_data
    stats_data=$(grep -h "\[STATS\]" "${SUMMARY_DIR}"/*.log 2>/dev/null || true)

    local total_runs=0 total_success=0 total_errors=0
    local total_duration=0 total_upgrades=0

    if [[ -n "${stats_data}" ]]; then
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            local dur stat upg
            dur=$(echo "${line}"    | grep -o 'duration=[0-9]*'  | cut -d= -f2)
            stat=$(echo "${line}"   | grep -o 'status=[A-Z]*'    | cut -d= -f2)
            upg=$(echo "${line}"    | grep -o 'upgrades=[0-9]*'  | cut -d= -f2)
            (( total_runs++ ))        || true
            (( total_duration += ${dur:-0} )) || true
            (( total_upgrades += ${upg:-0} )) || true
            if [[ "${stat}" == "SUCCESS" ]]; then
                (( total_success++ )) || true
            else
                (( total_errors++ ))  || true
            fi
        done <<< "${stats_data}"
    else
        # Fallback: count older-format runs via "Brew Auto-Update starting"
        total_runs=$(grep -ch "Brew Auto-Update starting" "${SUMMARY_DIR}"/*.log 2>/dev/null \
                     | awk '{s+=$1} END {print s+0}')
        total_success=$(grep -ch "Status: SUCCESS" "${SUMMARY_DIR}"/*.log 2>/dev/null \
                        | awk '{s+=$1} END {print s+0}')
        total_errors=$(( total_runs - total_success ))

        # Estimate duration from "finished in Xs" lines
        total_duration=$(grep -h "finished in [0-9]*s" "${SUMMARY_DIR}"/*.log 2>/dev/null \
                         | grep -o '[0-9]*s' | tr -d 's' \
                         | awk '{s+=$1} END {print s+0}')

        # Count upgrade events from diff ">" lines
        total_upgrades=$(grep -hc '^\[.*\] > \|^> ' "${SUMMARY_DIR}"/*.log 2>/dev/null \
                         | awk '{s+=$1} END {print s+0}' || echo 0)
    fi

    # ------------------------------------------------------------------
    # Build recent-runs table (last 8 runs, newest first)
    # Each record: TIMESTAMP|DURATION|STATUS|UPGRADES
    # Prefer [STATS] lines; fall back to plain-text parsing
    # ------------------------------------------------------------------
    local runs_raw=""
    if [[ -n "${stats_data}" ]]; then
        # Extract per-run records from all summary logs (cat all, grep STATS)
        runs_raw=$(cat "${SUMMARY_DIR}"/*.log 2>/dev/null \
            | awk '
                /\[STATS\]/ {
                    ts  = substr($1,2) " " substr($2,1,length($2)-1)
                    dur = "?"; stat = "?"; upg = 0
                    n = split($0, a, " ")
                    for (i=1; i<=n; i++) {
                        if (a[i] ~ /^duration=/)  { dur  = substr(a[i], 10) }
                        if (a[i] ~ /^status=/)    { stat = substr(a[i], 8)  }
                        if (a[i] ~ /^upgrades=/)  { upg  = substr(a[i], 10) }
                    }
                    print ts "|" dur "|" stat "|" upg
                }
            ' | tail -8 | awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}')
    else
        # Fallback: pair "starting" + "finished in Xs" + "Status:" lines
        runs_raw=$(cat "${SUMMARY_DIR}"/*.log 2>/dev/null \
            | awk '
                /Brew Auto-Update starting/ {
                    ts = substr($1,2) " " substr($2,1,length($2)-1)
                    dur = "?"; stat = "?"; upg = 0
                }
                /finished in [0-9]+s/ {
                    match($0, /[0-9]+s/)
                    dur = substr($0, RSTART, RLENGTH-1)
                }
                /Status: SUCCESS/ && dur != "?" {
                    stat = "SUCCESS"
                    print ts "|" dur "|" stat "|" upg
                    ts=""; dur="?"; stat="?"; upg=0
                }
                /^.*\] ERRORS/ && dur != "?" {
                    stat = "ERROR"
                    print ts "|" dur "|" stat "|" upg
                    ts=""; dur="?"; stat="?"; upg=0
                }
            ' | tail -8 | awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}')
    fi

    # ------------------------------------------------------------------
    # Package frequency counts from [PKG] lines
    # ------------------------------------------------------------------
    local pkg_counts=""
    pkg_counts=$(grep -h "\[PKG\]" "${SUMMARY_DIR}"/*.log 2>/dev/null \
                 | awk '{print $NF}' \
                 | sort | uniq -c | sort -rn | head -8 || true)

    # Count unique packages
    local unique_pkgs=0
    if [[ -n "${pkg_counts}" ]]; then
        unique_pkgs=$(echo "${pkg_counts}" | wc -l | tr -d ' ')
    else
        # Fallback: count unique ">" diff-output package names
        unique_pkgs=$(grep -h '^\[.*\] > \|^> ' "${SUMMARY_DIR}"/*.log 2>/dev/null \
                      | sed 's/^\[.*\] > //' | sed 's/^> //' | awk '{print $1}' \
                      | sort -u | wc -l | tr -d ' ' || echo 0)
    fi

    # Output as shell assignments (will be eval'd by caller)
    printf 'STAT_TOTAL_RUNS=%d\n'     "${total_runs}"
    printf 'STAT_SUCCESS=%d\n'        "${total_success}"
    printf 'STAT_ERRORS=%d\n'         "${total_errors}"
    printf 'STAT_TOTAL_DURATION=%d\n' "${total_duration}"
    printf 'STAT_TOTAL_UPGRADES=%d\n' "${total_upgrades}"
    printf 'STAT_UNIQUE_PKGS=%d\n'    "${unique_pkgs}"
    # Use printf %q for safe multi-line variable quoting
    printf "STAT_RUNS_RAW=%s\n"       "$(printf '%q' "${runs_raw}")"
    printf "STAT_PKG_COUNTS=%s\n"     "$(printf '%q' "${pkg_counts}")"
}

# ---------------------------------------------------------------------------
# Next-run-time calculator
# ---------------------------------------------------------------------------
# Given SCHEDULE_HOURS (e.g. "0,6,12,18") and SCHEDULE_MINUTE (e.g. "0"),
# returns a human-readable string like "18:00  (in 2h 13m)" or
# "tomorrow at 00:00".
# ---------------------------------------------------------------------------
_next_run_time() {
    local hours_str="${1:-0,6,12,18}"
    local minute="${2:-0}"

    local now_h now_m
    now_h=$(date '+%H' | sed 's/^0*//')
    now_m=$(date '+%M' | sed 's/^0*//')
    now_h=${now_h:-0}
    now_m=${now_m:-0}

    # Sort the scheduled hours numerically
    local sorted_hours
    sorted_hours=$(echo "${hours_str}" | tr ',' '\n' | grep -v '^$' | sort -n)

    local next_h="" next_day=false
    while IFS= read -r h; do
        h=$(echo "${h}" | tr -d ' ')
        [[ -z "${h}" ]] && continue
        if [[ ${h} -gt ${now_h} ]] || [[ ${h} -eq ${now_h} && ${minute} -gt ${now_m} ]]; then
            next_h="${h}"
            break
        fi
    done <<< "${sorted_hours}"

    if [[ -z "${next_h}" ]]; then
        next_h=$(echo "${sorted_hours}" | head -1 | tr -d ' ')
        next_day=true
    fi

    local next_hh next_mm
    printf -v next_hh '%02d' "${next_h}"
    printf -v next_mm '%02d' "${minute}"

    if [[ "${next_day}" == "true" ]]; then
        echo "tomorrow at ${next_hh}:${next_mm}"
        return
    fi

    local diff_h diff_m
    diff_h=$(( next_h - now_h ))
    diff_m=$(( minute - now_m ))
    if [[ ${diff_m} -lt 0 ]]; then
        (( diff_h-- )) || true
        (( diff_m += 60 )) || true
    fi

    local time_str=""
    [[ ${diff_h} -gt 0 ]] && time_str="${diff_h}h "
    [[ ${diff_m} -gt 0 ]] && time_str+="${diff_m}m"
    [[ -z "${time_str}" ]] && time_str="now"

    echo "${next_hh}:${next_mm}  (in ${time_str})"
}

# ---------------------------------------------------------------------------
# Render a bar chart row for a package
#   $1 = package name (plain string for length)
#   $2 = count
#   $3 = max count (for proportional scaling)
#   $4 = bar max width
# ---------------------------------------------------------------------------
_dash_pkg_bar() {
    local name="$1" count="$2" max_count="$3" bar_max="$4"
    [[ ${max_count} -eq 0 ]] && max_count=1

    local bar_len=$(( count * bar_max / max_count ))
    [[ ${bar_len} -lt 1 ]] && bar_len=1

    local bar=""
    local i; for ((i=0; i<bar_len; i++)); do bar+="█"; done

    # Build plain and colored versions for _dash_row
    local name_col=18
    local plain_line count_col
    printf -v count_col '%*d' "$(( bar_max + 2 ))" "${count}"
    printf -v plain_line "  %-${name_col}s %-${bar_max}s %s×" \
        "${name}" "${bar}" "${count}"

    local colored_line
    printf -v colored_line "  ${CYAN}%-${name_col}s${NC} ${GREEN}%-${bar_max}s${NC} ${DIM}%s×${NC}" \
        "${name}" "${bar}" "${count}"

    _dash_row "${plain_line}" "${colored_line}"
}

# ---------------------------------------------------------------------------
# Format a schedule hours string for display:  "0,6,12,18" -> "0:00  6:00  12:00  18:00"
# ---------------------------------------------------------------------------
_fmt_schedule_hours() {
    local hours_str="$1" minute="${2:-0}"
    local mm; printf -v mm '%02d' "${minute}"
    echo "${hours_str}" | tr ',' '\n' | grep -v '^$' | \
        awk -v mm="${mm}" '{printf "%d:%s  ", $1, mm}' | sed 's/  $//'
}

# ---------------------------------------------------------------------------
# THE DASHBOARD COMMAND
# ---------------------------------------------------------------------------
cmd_dashboard() {
    _dash_init

    # --- Load config values ---
    local sched_hours sched_minute quiet_enabled quiet_start quiet_end
    local auto_upgrade auto_cleanup auto_remove upgrade_casks greedy
    local notify_every notify_err deny_list allow_list
    sched_hours=$(  read_cfg SCHEDULE_HOURS   "0,6,12,18")
    sched_minute=$( read_cfg SCHEDULE_MINUTE  "0")
    quiet_enabled=$(read_cfg QUIET_HOURS_ENABLED "false")
    quiet_start=$(  read_cfg QUIET_HOURS_START   "09:00")
    quiet_end=$(    read_cfg QUIET_HOURS_END     "18:00")
    auto_upgrade=$( read_cfg AUTO_UPGRADE    "true")
    auto_cleanup=$( read_cfg AUTO_CLEANUP    "true")
    auto_remove=$(  read_cfg AUTO_REMOVE     "true")
    upgrade_casks=$(read_cfg UPGRADE_CASKS   "true")
    greedy=$(       read_cfg UPGRADE_CASKS_GREEDY "false")
    notify_every=$( read_cfg NOTIFY_ON_EVERY_RUN "true")
    notify_err=$(   read_cfg NOTIFY_ON_ERROR "true")
    deny_list=$(    read_cfg DENY_LIST  "")
    allow_list=$(   read_cfg ALLOW_LIST "")

    # --- Daemon status ---
    local daemon_status daemon_color
    if launchctl list "${PLIST_LABEL}" &>/dev/null; then
        daemon_status="● ACTIVE"
        daemon_color="${GREEN}● ACTIVE${NC}"
    else
        daemon_status="○ NOT LOADED"
        daemon_color="${RED}○ NOT LOADED${NC}"
    fi

    # --- Last run info ---
    local last_run_ts="none" last_run_dur="—" last_run_stat="—" last_run_stat_color="—"
    local latest_summary
    latest_summary=$(latest_file "${SUMMARY_DIR}")
    if [[ -n "${latest_summary}" ]]; then
        local last_stats_line
        last_stats_line=$(grep "\[STATS\]" "${latest_summary}" 2>/dev/null | tail -1)
        if [[ -n "${last_stats_line}" ]]; then
            last_run_ts=$(echo "${last_stats_line}" \
                          | awk '{print substr($1,2) " " substr($2,1,length($2)-1)}')
            last_run_dur=$(echo "${last_stats_line}" | grep -o 'duration=[0-9]*' | cut -d= -f2)s
            local last_stat_raw
            last_stat_raw=$(echo "${last_stats_line}" | grep -o 'status=[A-Z]*' | cut -d= -f2)
            if [[ "${last_stat_raw}" == "SUCCESS" ]]; then
                last_run_stat="✓ OK"
                last_run_stat_color="${GREEN}✓ OK${NC}"
            else
                last_run_stat="✗ ERROR"
                last_run_stat_color="${RED}✗ ERROR${NC}"
            fi
        else
            # Fallback: extract from filenames / plain log lines
            last_run_ts=$(basename "${latest_summary}" .log)
            local dur_line
            dur_line=$(grep "finished in" "${latest_summary}" 2>/dev/null | tail -1)
            if [[ -n "${dur_line}" ]]; then
                last_run_dur=$(echo "${dur_line}" | grep -o '[0-9]*s' | tail -1)
                if grep -q "Status: SUCCESS" "${latest_summary}" 2>/dev/null; then
                    last_run_stat="✓ OK"
                    last_run_stat_color="${GREEN}✓ OK${NC}"
                else
                    last_run_stat="✗ ERROR"
                    last_run_stat_color="${RED}✗ ERROR${NC}"
                fi
            fi
        fi
    fi

    # --- Next run time ---
    local next_run
    next_run=$(_next_run_time "${sched_hours}" "${sched_minute}")

    # --- Formatted schedule ---
    local sched_fmt
    sched_fmt=$(_fmt_schedule_hours "${sched_hours}" "${sched_minute}")

    # --- Parse statistics (eval output to set STAT_* vars) ---
    eval "$(_parse_stats)"

    local avg_dur=0
    [[ ${STAT_TOTAL_RUNS} -gt 0 ]] && avg_dur=$(( STAT_TOTAL_DURATION / STAT_TOTAL_RUNS ))

    local success_pct="—"
    if [[ ${STAT_TOTAL_RUNS} -gt 0 ]]; then
        success_pct=$(awk "BEGIN { printf \"%.1f%%\", ${STAT_SUCCESS}*100/${STAT_TOTAL_RUNS} }")
    fi

    # --- Package data for bar chart ---
    local top_pkg_name top_pkg_max=0
    if [[ -n "${STAT_PKG_COUNTS}" ]]; then
        top_pkg_max=$(echo "${STAT_PKG_COUNTS}" | head -1 | awk '{print $1}')
    fi
    local bar_max=$(( _IW - 24 ))   # name col(18) + spaces(4) + count(2)
    [[ ${bar_max} -gt 30 ]] && bar_max=30
    [[ ${bar_max} -lt 10 ]] && bar_max=10

    # ===========================================================================
    # RENDER
    # ===========================================================================
    local now_str
    now_str=$(date '+%Y-%m-%d  %H:%M:%S')

    _dash_top

    # Header
    local title="  BREW AUTO-UPDATE DASHBOARD  v${BAU_VERSION}"
    local ts_label="Updated: ${now_str}"
    local header_plain="${title}$(printf '%*s' $(( _IW - ${#title} - ${#ts_label} )) '')${ts_label}"
    local header_colored="${BOLD}${CYAN}${title}${NC}$(printf '%*s' $(( _IW - ${#title} - ${#ts_label} )) '')${DIM}${ts_label}${NC}"
    _dash_row "${header_plain}" "${header_colored}"

    _dash_div

    # ── STATUS ──────────────────────────────────────────────────────────────
    local sect_plain="  DAEMON STATUS"
    local sect_colored="  ${BOLD}DAEMON STATUS${NC}"
    _dash_row "${sect_plain}" "${sect_colored}"
    _dash_thin

    local status_plain="  Status          ${daemon_status}"
    local status_colored="  ${BOLD}Status          ${NC}${daemon_color}"
    _dash_row "${status_plain}" "${status_colored}"

    _dash_kv "  Last run" "${last_run_ts}   ${last_run_stat}" \
                          "${last_run_ts}   ${last_run_stat_color}"

    _dash_kv "  Duration" "${last_run_dur}"

    _dash_blank

    local sect2_plain="  SCHEDULE"
    local sect2_colored="  ${BOLD}SCHEDULE${NC}"
    _dash_row "${sect2_plain}" "${sect2_colored}"
    _dash_thin

    _dash_kv "  Runs at" "${sched_fmt}"
    _dash_kv "  Next run" "${next_run}"

    local qh_label qh_color
    if [[ "${quiet_enabled}" == "true" ]]; then
        qh_label="enabled  (${quiet_start} – ${quiet_end})"
        qh_color="${YELLOW}enabled  (${quiet_start} – ${quiet_end})${NC}"
    else
        qh_label="disabled"
        qh_color="${DIM}disabled${NC}"
    fi
    _dash_kv "  Quiet hours" "${qh_label}" "${qh_color}"

    _dash_div

    # ── RECENT RUNS ─────────────────────────────────────────────────────────
    local sect3_plain="  RECENT RUNS"
    local sect3_colored="  ${BOLD}RECENT RUNS${NC}"
    _dash_row "${sect3_plain}" "${sect3_colored}"
    _dash_thin

    if [[ -z "${STAT_RUNS_RAW}" ]]; then
        _dash_kv "" "(no run history found)"
    else
        # Column widths
        local ts_w=19 dur_w=6 stat_w=8

        # Header row
        local hdr_plain
        printf -v hdr_plain "  %-${ts_w}s %-${dur_w}s %-${stat_w}s %s" \
            "Date / Time" "Dur" "Status" "Packages"
        local hdr_colored
        printf -v hdr_colored "  ${DIM}%-${ts_w}s %-${dur_w}s %-${stat_w}s %s${NC}" \
            "Date / Time" "Dur" "Status" "Packages"
        _dash_row "${hdr_plain}" "${hdr_colored}"

        # Data rows
        while IFS='|' read -r r_ts r_dur r_stat r_upg; do
            [[ -z "${r_ts}" ]] && continue
            local r_dur_fmt="${r_dur}s"
            local r_stat_plain r_stat_color r_upg_plain
            if [[ "${r_stat}" == "SUCCESS" ]]; then
                r_stat_plain="✓ OK"
                r_stat_color="${GREEN}✓ OK${NC}"
            else
                r_stat_plain="✗ ERR"
                r_stat_color="${RED}✗ ERR${NC}"
            fi
            if [[ "${r_upg}" -gt 0 ]] 2>/dev/null; then
                r_upg_plain="${r_upg} updated"
            else
                r_upg_plain="none"
            fi

            local row_plain
            printf -v row_plain "  %-${ts_w}s %-${dur_w}s %-${stat_w}s %s" \
                "${r_ts}" "${r_dur_fmt}" "${r_stat_plain}" "${r_upg_plain}"
            local row_colored
            printf -v row_colored "  %-${ts_w}s ${DIM}%-${dur_w}s${NC} %-${stat_w}b %s" \
                "${r_ts}" "${r_dur_fmt}" "${r_stat_color}" "${r_upg_plain}"
            _dash_row "${row_plain}" "${row_colored}"
        done <<< "${STAT_RUNS_RAW}"
    fi

    _dash_div

    # ── STATISTICS ──────────────────────────────────────────────────────────
    local stat_hdr_plain="  CUMULATIVE STATISTICS  (${STAT_TOTAL_RUNS} total runs)"
    local stat_hdr_colored="  ${BOLD}CUMULATIVE STATISTICS${NC}  ${DIM}(${STAT_TOTAL_RUNS} total runs)${NC}"
    _dash_row "${stat_hdr_plain}" "${stat_hdr_colored}"
    _dash_thin

    local s1_plain="  Success: ${STAT_SUCCESS} (${success_pct})    Errors: ${STAT_ERRORS}    Avg duration: ${avg_dur}s"
    local s1_colored="  ${GREEN}Success: ${STAT_SUCCESS}${NC} ${DIM}(${success_pct})${NC}    ${RED}Errors: ${STAT_ERRORS}${NC}    ${DIM}Avg duration: ${avg_dur}s${NC}"
    _dash_row "${s1_plain}" "${s1_colored}"

    local s2_plain="  Total upgrades: ${STAT_TOTAL_UPGRADES}    Unique packages: ${STAT_UNIQUE_PKGS}"
    local s2_colored="  ${CYAN}Total upgrades: ${STAT_TOTAL_UPGRADES}${NC}    ${DIM}Unique packages: ${STAT_UNIQUE_PKGS}${NC}"
    _dash_row "${s2_plain}" "${s2_colored}"

    _dash_div

    # ── TOP PACKAGES ────────────────────────────────────────────────────────
    local top_plain="  TOP PACKAGES BY UPDATE FREQUENCY"
    local top_colored="  ${BOLD}TOP PACKAGES BY UPDATE FREQUENCY${NC}"
    _dash_row "${top_plain}" "${top_colored}"
    _dash_thin

    if [[ -z "${STAT_PKG_COUNTS}" ]]; then
        _dash_kv "" "(no package data yet)"
    else
        while IFS= read -r pkg_line; do
            [[ -z "${pkg_line}" ]] && continue
            local p_count p_name
            p_count=$(echo "${pkg_line}" | awk '{print $1}')
            p_name=$(echo "${pkg_line}"  | awk '{print $2}')
            _dash_pkg_bar "${p_name}" "${p_count}" "${top_pkg_max}" "${bar_max}"
        done <<< "${STAT_PKG_COUNTS}"
    fi

    _dash_div

    # ── CONFIGURATION ───────────────────────────────────────────────────────
    local cfg_plain="  CONFIGURATION"
    local cfg_colored="  ${BOLD}CONFIGURATION${NC}"
    _dash_row "${cfg_plain}" "${cfg_colored}"
    _dash_thin

    # Boolean indicators
    _bool_indicator() {
        local val="$1"
        if [[ "${val}" == "true" ]]; then echo "✓"; else echo "✗"; fi
    }
    _bool_color() {
        local val="$1"
        if [[ "${val}" == "true" ]]; then echo "${GREEN}✓${NC}"; else echo "${RED}✗${NC}"; fi
    }

    local flags_plain="  upgrade:$(_bool_indicator "${auto_upgrade}")  cleanup:$(_bool_indicator "${auto_cleanup}")  autoremove:$(_bool_indicator "${auto_remove}")  casks:$(_bool_indicator "${upgrade_casks}")  greedy:$(_bool_indicator "${greedy}")"
    local flags_colored="  upgrade:$(_bool_color "${auto_upgrade}")  cleanup:$(_bool_color "${auto_cleanup}")  autoremove:$(_bool_color "${auto_remove}")  casks:$(_bool_color "${upgrade_casks}")  greedy:$(_bool_color "${greedy}")"
    _dash_row "${flags_plain}" "${flags_colored}"

    local deny_disp="${deny_list:-(none)}"
    local allow_disp="${allow_list:-(none)}"
    local lists_plain="  deny list: ${deny_disp}   allow list: ${allow_disp}"
    local lists_colored="  ${DIM}deny list:${NC} ${YELLOW}${deny_disp}${NC}   ${DIM}allow list:${NC} ${YELLOW}${allow_disp}${NC}"
    _dash_row "${lists_plain}" "${lists_colored}"

    local notify_label
    if [[ "${notify_every}" == "true" && "${notify_err}" == "true" ]]; then
        notify_label="all runs + errors"
    elif [[ "${notify_err}" == "true" ]]; then
        notify_label="errors only"
    else
        notify_label="disabled"
    fi
    _dash_kv "  Notifications" "${notify_label}"

    _dash_blank
    local tip_plain="  brew-logs help  for all commands   |   brew-logs schedule reload  to apply schedule changes"
    local tip_colored="  ${DIM}brew-logs help  for all commands   |   brew-logs schedule reload  to apply schedule changes${NC}"
    _dash_row "${tip_plain}" "${tip_colored}"

    _dash_bot
}

# ---------------------------------------------------------------------------
# SCHEDULE COMMAND
# ---------------------------------------------------------------------------
cmd_schedule() {
    local subcmd="${1:-show}"

    case "${subcmd}" in
        show|"")
            local hours minute
            hours=$(read_cfg SCHEDULE_HOURS "0,6,12,18")
            minute=$(read_cfg SCHEDULE_MINUTE "0")
            local sched_fmt next_run
            sched_fmt=$(_fmt_schedule_hours "${hours}" "${minute}")
            next_run=$(_next_run_time "${hours}" "${minute}")

            echo -e "${BOLD}Current Schedule${NC}"
            echo -e "────────────────────────────────────────"
            echo -e "  ${BOLD}Hours:${NC}    ${sched_fmt}"
            echo -e "  ${BOLD}Minute:${NC}   :$(printf '%02d' "${minute}")"
            echo -e "  ${BOLD}Next run:${NC} ${next_run}"
            echo
            echo -e "  ${DIM}Edit SCHEDULE_HOURS / SCHEDULE_MINUTE in:${NC}"
            echo -e "  ${CYAN}${CONFIG_FILE}${NC}"
            echo -e "  ${DIM}Then run:${NC} brew-logs schedule reload"
            ;;

        reload)
            echo -e "${CYAN}[INFO]${NC}    Reading schedule from config..."
            local hours minute
            hours=$(read_cfg SCHEDULE_HOURS "0,6,12,18")
            minute=$(read_cfg SCHEDULE_MINUTE "0")
            echo -e "${CYAN}[INFO]${NC}    SCHEDULE_HOURS=${hours}  SCHEDULE_MINUTE=${minute}"

            # Use the installed install.sh if available; otherwise do it inline
            if [[ -f "${INSTALL_SCRIPT}" ]]; then
                echo -e "${CYAN}[INFO]${NC}    Regenerating plist via install.sh..."
                bash "${INSTALL_SCRIPT}" --reload-schedule
            else
                echo -e "${YELLOW}[WARN]${NC}    install.sh not found at ${INSTALL_SCRIPT}"
                echo -e "${YELLOW}[WARN]${NC}    Regenerating plist inline..."
                _inline_plist_reload "${hours}" "${minute}"
            fi
            ;;

        *)
            echo "Usage: brew-logs schedule [show|reload]"
            ;;
    esac
}

# Inline plist regeneration used when install.sh is absent.
_inline_plist_reload() {
    local hours="${1:-0,6,12,18}"
    local minute="${2:-0}"

    # Validate schedule_hours is not empty
    if [[ -z "${hours}" ]]; then
        echo -e "${RED}[ERROR]${NC}   SCHEDULE_HOURS is empty; falling back to default 0,6,12,18"
        hours="0,6,12,18"
    fi

    # Unload daemon
    echo -e "${CYAN}[INFO]${NC}    Unloading daemon..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true

    # Write new plist
    echo -e "${CYAN}[INFO]${NC}    Writing ${PLIST_FILE}..."
    {
        cat <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.brew-autoupdate</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${HOME}/.config/brew-autoupdate/brew-autoupdate.sh</string>
    </array>

    <key>StartCalendarInterval</key>
    <array>
PLIST_EOF
        IFS=',' read -ra hour_arr <<< "${hours}"
        for h in "${hour_arr[@]}"; do
            h=$(echo "${h}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -z "${h}" ]] && continue
            printf '        <dict>\n'
            printf '            <key>Hour</key>\n'
            printf '            <integer>%d</integer>\n' "${h}"
            printf '            <key>Minute</key>\n'
            printf '            <integer>%d</integer>\n' "${minute}"
            printf '        </dict>\n'
        done
        cat <<PLIST_EOF2
    </array>

    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/brew-autoupdate/launchd-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/brew-autoupdate/launchd-stderr.log</string>

    <key>LowPriorityIO</key>
    <true/>

    <key>Nice</key>
    <integer>10</integer>

    <key>ProcessType</key>
    <string>Background</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
PLIST_EOF2
    } > "${PLIST_FILE}"

    chmod 644 "${PLIST_FILE}"

    if plutil -lint "${PLIST_FILE}" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC}      Plist validated"
    else
        echo -e "${RED}[ERROR]${NC}   Plist validation failed"
        plutil -lint "${PLIST_FILE}"
        return 1
    fi

    launchctl load -w "${PLIST_FILE}"
    if launchctl list "${PLIST_LABEL}" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC}      Daemon reloaded with new schedule"
        local sched_fmt
        sched_fmt=$(_fmt_schedule_hours "${hours}" "${minute}")
        echo -e "${GREEN}[OK]${NC}      Runs at: ${sched_fmt}"
    else
        echo -e "${RED}[ERROR]${NC}   Daemon failed to load"
        return 1
    fi
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================
# All known config keys, their types, and factory defaults live here.
# These are the single source of truth used by get/set/reset/show.
# ----------------------------------------------------------------------------

# Returns the data type for a config key: bool | int | time | string | unknown
_config_key_type() {
    case "${1}" in
        NOTIFY_ON_EVERY_RUN|NOTIFY_ON_ERROR|AUTO_UPGRADE|AUTO_CLEANUP|\
        AUTO_REMOVE|UPGRADE_CASKS|UPGRADE_CASKS_GREEDY|QUIET_HOURS_ENABLED)
            echo "bool" ;;
        DETAIL_LOG_RETENTION_DAYS|SUMMARY_LOG_RETENTION_DAYS|\
        CLEANUP_OLDER_THAN_DAYS|SCHEDULE_MINUTE)
            echo "int" ;;
        QUIET_HOURS_START|QUIET_HOURS_END)
            echo "time" ;;
        SCHEDULE_HOURS|DENY_LIST|ALLOW_LIST|PRE_UPDATE_HOOK|POST_UPDATE_HOOK|\
        BREW_PATH|BREW_ENV)
            echo "string" ;;
        *)
            echo "unknown" ;;
    esac
}

# Returns the factory default value for a config key
_config_default() {
    case "${1}" in
        DETAIL_LOG_RETENTION_DAYS)  echo "90" ;;
        SUMMARY_LOG_RETENTION_DAYS) echo "365" ;;
        NOTIFY_ON_EVERY_RUN)        echo "true" ;;
        NOTIFY_ON_ERROR)            echo "true" ;;
        AUTO_UPGRADE)               echo "true" ;;
        AUTO_CLEANUP)               echo "true" ;;
        CLEANUP_OLDER_THAN_DAYS)    echo "0" ;;
        AUTO_REMOVE)                echo "true" ;;
        UPGRADE_CASKS)              echo "true" ;;
        UPGRADE_CASKS_GREEDY)       echo "false" ;;
        DENY_LIST)                  echo "" ;;
        ALLOW_LIST)                 echo "" ;;
        PRE_UPDATE_HOOK)            echo "" ;;
        POST_UPDATE_HOOK)           echo "" ;;
        QUIET_HOURS_ENABLED)        echo "false" ;;
        QUIET_HOURS_START)          echo "09:00" ;;
        QUIET_HOURS_END)            echo "18:00" ;;
        SCHEDULE_HOURS)             echo "0,6,12,18" ;;
        SCHEDULE_MINUTE)            echo "0" ;;
        BREW_PATH)                  echo "" ;;
        BREW_ENV)                   echo "" ;;
        *)                          echo "" ;;
    esac
}

# Ordered list of all known keys used by 'config show'
_CONFIG_KEYS="DETAIL_LOG_RETENTION_DAYS SUMMARY_LOG_RETENTION_DAYS
NOTIFY_ON_EVERY_RUN NOTIFY_ON_ERROR
AUTO_UPGRADE AUTO_CLEANUP CLEANUP_OLDER_THAN_DAYS AUTO_REMOVE
UPGRADE_CASKS UPGRADE_CASKS_GREEDY
DENY_LIST ALLOW_LIST
PRE_UPDATE_HOOK POST_UPDATE_HOOK
QUIET_HOURS_ENABLED QUIET_HOURS_START QUIET_HOURS_END
SCHEDULE_HOURS SCHEDULE_MINUTE
BREW_PATH BREW_ENV"

# Validate a proposed value for a key; print error and return 1 on failure
_config_validate() {
    local key="${1}" value="${2}"
    local type
    type=$(_config_key_type "${key}")
    case "${type}" in
        unknown)
            echo -e "${RED}Unknown key: ${key}${NC}" >&2
            echo -e "${DIM}Run 'brew-logs config' to see all valid keys.${NC}" >&2
            return 1 ;;
        bool)
            if [[ "${value}" != "true" && "${value}" != "false" ]]; then
                echo -e "${RED}${key} requires true or false (got: '${value}')${NC}" >&2
                return 1
            fi ;;
        int)
            if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}${key} requires a non-negative integer (got: '${value}')${NC}" >&2
                return 1
            fi ;;
        time)
            if ! [[ "${value}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                echo -e "${RED}${key} requires HH:MM format (00:00–23:59), e.g. 09:00 (got: '${value}')${NC}" >&2
                return 1
            fi ;;
        string) : ;;    # any value accepted
    esac
    return 0
}

# Write KEY=VALUE into CONFIG_FILE in-place. Replaces an existing KEY= line;
# appends the key at the end if it is not yet present in the file.
# Uses a temp file + mv for an atomic update with no partial-write risk.
_config_write() {
    local key="${1}" new_value="${2}"
    local tmp found=0
    tmp=$(mktemp) || { echo -e "${RED}Cannot create temp file${NC}" >&2; return 1; }

    while IFS= read -r line; do
        # Match lines that start with KEY= (not commented-out copies)
        if [[ "${line}" == "${key}="* ]]; then
            printf '%s\n' "${key}=${new_value}" >> "${tmp}"
            found=1
        else
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${CONFIG_FILE}"

    # Key absent from file entirely — add it at the end
    if [[ ${found} -eq 0 ]]; then
        printf '%s\n' "${key}=${new_value}" >> "${tmp}"
    fi

    mv "${tmp}" "${CONFIG_FILE}"
}

# ── config show ───────────────────────────────────────────────────────────────
# Displays every known key with its current value, type, and a '*' marker
# when the value differs from the factory default.
_config_show() {
    echo -e "${BOLD}Configuration${NC}  ${DIM}${CONFIG_FILE}${NC}"
    echo -e "────────────────────────────────────────────────────────────────"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${RED}Config file not found: ${CONFIG_FILE}${NC}"
        return
    fi

    local key type value default changed=0
    for key in ${_CONFIG_KEYS}; do
        type=$(_config_key_type "${key}")
        default=$(_config_default "${key}")
        value=$(read_cfg "${key}" "${default}")

        local marker=""
        if [[ "${value}" != "${default}" ]]; then
            marker=" ${YELLOW}*${NC}"
            changed=1
        fi

        # Truncate long values (hook commands, paths) to keep the table tidy
        local display_value="${value:-<empty>}"
        if [[ ${#display_value} -gt 30 ]]; then
            display_value="${display_value:0:27}..."
        fi

        printf "  ${BOLD}%-30s${NC} ${CYAN}%-30s${NC} ${DIM}[%s]${NC}%b\n" \
            "${key}" "${display_value}" "${type}" "${marker}"
    done

    echo
    if [[ ${changed} -eq 1 ]]; then
        echo -e "  ${DIM}${YELLOW}*${NC}${DIM} = differs from factory default${NC}"
    fi
    echo -e "  ${DIM}To change:  brew-logs config set KEY VALUE${NC}"
    echo -e "  ${DIM}To reset:   brew-logs config reset KEY${NC}"
}

# ── config get ────────────────────────────────────────────────────────────────
_config_get() {
    local key="${1:-}"
    if [[ -z "${key}" ]]; then
        echo -e "${RED}Usage: brew-logs config get KEY${NC}" >&2; return 1
    fi

    local type
    type=$(_config_key_type "${key}")
    if [[ "${type}" == "unknown" ]]; then
        echo -e "${RED}Unknown key: ${key}${NC}" >&2
        echo -e "${DIM}Run 'brew-logs config' to see all valid keys.${NC}" >&2
        return 1
    fi

    local default value
    default=$(_config_default "${key}")
    value=$(read_cfg "${key}" "${default}")

    printf '%s=%s\n' "${key}" "${value:-}"
    echo -e "${DIM}type: ${type}  |  default: ${default:-<empty>}${NC}"
}

# ── config set ────────────────────────────────────────────────────────────────
_config_set() {
    local key="${1:-}" new_value="${2:-}"
    if [[ -z "${key}" ]]; then
        echo -e "${RED}Usage: brew-logs config set KEY VALUE${NC}" >&2; return 1
    fi

    _config_validate "${key}" "${new_value}" || return 1

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${RED}Config file not found: ${CONFIG_FILE}${NC}" >&2; return 1
    fi

    local old_value default
    default=$(_config_default "${key}")
    old_value=$(read_cfg "${key}" "${default}")

    _config_write "${key}" "${new_value}"

    echo -e "  ${BOLD}${key}${NC}: ${DIM}${old_value:-<empty>}${NC} → ${GREEN}${new_value:-<empty>}${NC}"
    if [[ "${key}" == "SCHEDULE_HOURS" || "${key}" == "SCHEDULE_MINUTE" ]]; then
        echo -e "  ${YELLOW}Schedule change — run 'brew-logs schedule reload' to apply.${NC}"
    else
        echo -e "  ${DIM}Saved. Takes effect on next run (no restart needed).${NC}"
    fi
}

# ── config reset ──────────────────────────────────────────────────────────────
_config_reset() {
    local key="${1:-}"
    if [[ -z "${key}" ]]; then
        echo -e "${RED}Usage: brew-logs config reset KEY${NC}" >&2; return 1
    fi

    if [[ "$(_config_key_type "${key}")" == "unknown" ]]; then
        echo -e "${RED}Unknown key: ${key}${NC}" >&2; return 1
    fi

    _config_set "${key}" "$(_config_default "${key}")"
}

# ── cmd_config — subcommand dispatcher ────────────────────────────────────────
cmd_config() {
    local subcmd="${1:-show}"
    shift 2>/dev/null || true
    case "${subcmd}" in
        show|"")  _config_show ;;
        get)      _config_get "$@" ;;
        set)      _config_set "$@" ;;
        reset)    _config_reset "$@" ;;
        *)
            echo -e "${RED}Unknown config subcommand: ${subcmd}${NC}" >&2
            echo "Usage: brew-logs config [show | get KEY | set KEY VALUE | reset KEY]"
            return 1 ;;
    esac
}

# ============================================================================
# COMMAND PARSING
# ============================================================================
cmd="${1:-detail}"
shift 2>/dev/null || true

# ============================================================================
# COMMAND ROUTER
# ============================================================================
# Print the version header for every command except `dashboard`, which renders
# its own full-screen title bar that already contains the version string.
case "${cmd}" in
    dashboard|dash) ;;               # version shown inside cmd_dashboard title
    *)  print_version_header ;;      # all other commands get the dim header line
esac

case "${cmd}" in

    # ========================================================================
    # GRAPHICAL DASHBOARD
    # ========================================================================
    dashboard|dash)
        cmd_dashboard
        ;;

    # ========================================================================
    # DETAIL LOG VIEWER
    # ========================================================================
    detail|d)
        subcmd="${1:-latest}"
        case "${subcmd}" in
            latest|last)
                count="${2:-1}"
                files=($(ls -t "${DETAIL_DIR}"/*.log 2>/dev/null | head -"${count}"))
                if [[ ${#files[@]} -eq 0 ]]; then
                    echo -e "${YELLOW}No detail logs found.${NC}"
                    exit 0
                fi
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
                f="${SUMMARY_DIR}/$(date '+%Y-%m-%d').log"
                if [[ -f "${f}" ]]; then
                    echo -e "${CYAN}=== Today's Summary ===${NC}"
                    cat "${f}"
                else
                    echo -e "${YELLOW}No summary for today yet.${NC}"
                fi
                ;;
            last)
                count="${2:-5}"
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
    errors|e)
        echo -e "${BOLD}Recent errors across all logs:${NC}"
        echo
        grep -i -h "error\|fail\|warning" "${DETAIL_DIR}"/*.log 2>/dev/null | tail -50 || echo -e "${GREEN}No errors found.${NC}"
        ;;

    # ========================================================================
    # LIVE TAIL
    # ========================================================================
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
    status|st)
        echo -e "${BOLD}Brew Auto-Update Daemon Status${NC}"
        echo -e "─────────────────────────────────"

        if launchctl list "${PLIST_LABEL}" &>/dev/null; then
            echo -e "Daemon:  ${GREEN}LOADED${NC}"
            launchctl list "${PLIST_LABEL}" 2>/dev/null | head -5
        else
            echo -e "Daemon:  ${RED}NOT LOADED${NC}"
        fi
        echo

        echo -e "${BOLD}Log statistics:${NC}"
        detail_count=$(ls "${DETAIL_DIR}"/*.log 2>/dev/null | wc -l | tr -d ' ')
        summary_count=$(ls "${SUMMARY_DIR}"/*.log 2>/dev/null | wc -l | tr -d ' ')
        echo "  Detail logs:  ${detail_count} files"
        echo "  Summary logs: ${summary_count} files"

        latest_detail="$(latest_file "${DETAIL_DIR}")"
        if [[ -n "${latest_detail}" ]]; then
            echo -e "  Last run:     $(basename "${latest_detail}" .log | tr '_' ' ')"
        fi

        echo
        echo -e "${BOLD}Disk usage:${NC}"
        du -sh "${DETAIL_DIR}" 2>/dev/null | awk '{print "  Detail: " $1}'
        du -sh "${SUMMARY_DIR}" 2>/dev/null | awk '{print "  Summary: " $1}'
        ;;

    # ========================================================================
    # LOG FILE LISTING
    # ========================================================================
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
    # CONFIGURATION VIEW / EDIT
    # ========================================================================
    config|c)
        cmd_config "$@"
        ;;

    # ========================================================================
    # SCHEDULE MANAGEMENT
    # ========================================================================
    schedule|sched)
        cmd_schedule "$@"
        ;;

    # ========================================================================
    # MANUAL RUN TRIGGER
    # ========================================================================
    run|r)
        echo -e "${CYAN}Triggering manual brew auto-update...${NC}"
        PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:${PATH}" \
            bash "${SCRIPT_FILE}"
        echo -e "${GREEN}Done. Check logs with: brew-logs detail${NC}"
        ;;

    # ========================================================================
    # HELP TEXT
    # ========================================================================
    help|h|--help|-h)
        echo -e "${BOLD}Homebrew Auto-Update Log Viewer${NC}  ${DIM}v${BAU_VERSION}${NC}"
        echo
        echo "Usage: brew-logs <command> [options]"
        echo
        echo "Commands:"
        echo "  dashboard                      Graphical status & stats console"
        echo "  detail [latest|last N]         Show detail log(s) (default: latest)"
        echo "  summary [latest|today|last N|DATE]  Show summary log(s)"
        echo "  errors                         Show recent errors across all logs"
        echo "  tail                           Live tail the latest detail log"
        echo "  status                         Show daemon status and log stats"
        echo "  list [detail|summary]          List all log files"
        echo "  config                         Show all configuration values"
        echo "  config get KEY                 Show current value for KEY"
        echo "  config set KEY VALUE           Set KEY to VALUE in config.conf"
        echo "  config reset KEY               Reset KEY to its factory default"
        echo "  schedule [show|reload]         Show or reload the run schedule"
        echo "  run                            Trigger a manual update now"
        echo "  help                           Show this help"
        echo
        echo "Aliases: dash=dashboard, d=detail, s=summary, e=errors, t=tail,"
        echo "         st=status, ls=list, c=config, sched=schedule, r=run, h=help"
        echo
        echo "Examples:"
        echo "  brew-logs dashboard            Full graphical dashboard"
        echo "  brew-logs detail last 3        Last 3 verbose run logs"
        echo "  brew-logs summary today        Today's summary"
        echo "  brew-logs config               Show all settings"
        echo "  brew-logs config set AUTO_UPGRADE false"
        echo "  brew-logs config get DENY_LIST"
        echo "  brew-logs config reset UPGRADE_CASKS_GREEDY"
        echo "  brew-logs schedule reload      Apply schedule from config.conf"
        echo "  brew-logs run                  Run update now (foreground)"
        ;;

    # ========================================================================
    # UNKNOWN COMMAND
    # ========================================================================
    *)
        echo "Unknown command: ${cmd}"
        echo "Run 'brew-logs help' for usage."
        exit 1
        ;;
esac
