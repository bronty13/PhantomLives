#!/usr/bin/env bash
# ============================================================================
#
#  HOMEBREW AUTO-UPDATE INSTALLER
#
#  File:     install.sh
#  Version:  2.1.0
#  Author:   Generated with Claude Code
#  License:  MIT
#  Requires: macOS, Homebrew, bash 3.2+
#
#  Description:
#    Installs the Homebrew Auto-Update system on macOS. This script:
#
#      1. Verifies prerequisites (macOS, Homebrew)
#      2. Creates configuration directory (~/.config/brew-autoupdate/)
#      3. Copies the update script, viewer script, and config file
#      4. Copies this installer (for 'brew-logs schedule reload')
#      5. Generates a launchd plist from the schedule in config.conf
#      6. Sets file permissions (scripts executable, config readable)
#      7. Symlinks the viewer as 'brew-logs' in Homebrew's bin directory
#      8. Creates log directories under ~/Library/Logs/
#      9. Loads the launchd daemon for automatic scheduling
#     10. Optionally runs a verification test
#
#  Usage:
#    bash install.sh              # Standard install
#    bash install.sh --uninstall  # Remove everything
#    bash install.sh --reinstall  # Uninstall then install fresh
#    bash install.sh --reload-schedule  # Regenerate plist from config
#    bash install.sh --help       # Show help
#
#  Idempotency:
#    Safe to run multiple times. Existing config.conf is PRESERVED
#    (not overwritten) to avoid losing user customizations. Use
#    --reinstall to force a fresh config.
#
#  What gets installed where:
#    ~/.config/brew-autoupdate/brew-autoupdate.sh        Main update script
#    ~/.config/brew-autoupdate/brew-autoupdate-viewer.sh Log viewer script
#    ~/.config/brew-autoupdate/install.sh                This installer (for schedule reload)
#    ~/.config/brew-autoupdate/config.conf               Configuration file
#    ~/Library/LaunchAgents/com.user.brew-autoupdate.plist  Daemon schedule
#    ~/Library/Logs/brew-autoupdate/detail/               Detail log dir
#    ~/Library/Logs/brew-autoupdate/summary/              Summary log dir
#    $(brew --prefix)/bin/brew-logs                       Symlink to viewer
#
# ============================================================================

set -euo pipefail

# ============================================================================
# VERSION
# ============================================================================
BAU_VERSION="2.1.0"

# ============================================================================
# TERMINAL FORMATTING
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================================
# INSTALLATION PATHS
# ============================================================================
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.config/brew-autoupdate"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
LOG_DIR="${HOME}/Library/Logs/brew-autoupdate"
PLIST_LABEL="com.user.brew-autoupdate"
PLIST_FILE="${LAUNCH_AGENTS_DIR}/${PLIST_LABEL}.plist"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
info()    { echo -e "${CYAN}[INFO]${NC}    $*"; }
success() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; }

section() {
    echo
    echo -e "${BOLD}── $* ──${NC}"
}

# read_config_value - extract a value from a config file
#   $1 = config file path
#   $2 = key name
#   $3 = default value
read_config_value() {
    local cfg="$1" key="$2" default="${3:-}"
    if [[ -f "${cfg}" ]]; then
        local val
        val=$(grep "^${key}=" "${cfg}" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/[[:space:]]#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
        echo "${val:-${default}}"
    else
        echo "${default}"
    fi
}

# ============================================================================
# PLIST GENERATION
# ============================================================================
# Generates the launchd plist XML based on the schedule from config.conf.
# Called during install AND by --reload-schedule.
#
# Arguments:
#   $1 = SCHEDULE_HOURS  (comma-separated, e.g. "0,6,12,18")
#   $2 = SCHEDULE_MINUTE (integer, e.g. "0")
#   $3 = install dir     (path to brew-autoupdate.sh)
#   $4 = home dir        (used for log paths and HOME env var)
# ----------------------------------------------------------------------------
generate_plist() {
    local schedule_hours="${1:-0,6,12,18}"
    local schedule_minute="${2:-0}"
    local install_dir="${3:-${INSTALL_DIR}}"
    local home_dir="${4:-${HOME}}"

    # Validate schedule_hours is not empty
    if [[ -z "${schedule_hours}" ]]; then
        echo "ERROR: SCHEDULE_HOURS is empty; falling back to default 0,6,12,18" >&2
        schedule_hours="0,6,12,18"
    fi

    cat <<PLIST_HEADER
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Unique identifier for this launchd job. -->
    <key>Label</key>
    <string>com.user.brew-autoupdate</string>

    <!-- The command to execute at each scheduled time. -->
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${install_dir}/brew-autoupdate.sh</string>
    </array>

    <!-- Run schedule: each <dict> defines one run time (Hour + Minute). -->
    <!-- Edit SCHEDULE_HOURS in config.conf, then run: brew-logs schedule reload -->
    <key>StartCalendarInterval</key>
    <array>
PLIST_HEADER

    # Generate one <dict> entry per scheduled hour
    IFS=',' read -ra hours <<< "${schedule_hours}"
    for h in "${hours[@]}"; do
        h=$(echo "${h}" | xargs)    # trim whitespace
        [[ -z "${h}" ]] && continue
        printf '        <dict>\n'
        printf '            <key>Hour</key>\n'
        printf '            <integer>%d</integer>\n' "${h}"
        printf '            <key>Minute</key>\n'
        printf '            <integer>%d</integer>\n' "${schedule_minute}"
        printf '        </dict>\n'
    done

    cat <<PLIST_FOOTER
    </array>

    <!-- launchd-level stdout/stderr (catches pre-script errors) -->
    <key>StandardOutPath</key>
    <string>${home_dir}/Library/Logs/brew-autoupdate/launchd-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${home_dir}/Library/Logs/brew-autoupdate/launchd-stderr.log</string>

    <!-- Resource priority: background, low I/O, nice=10 -->
    <key>LowPriorityIO</key>
    <true/>

    <key>Nice</key>
    <integer>10</integer>

    <key>ProcessType</key>
    <string>Background</string>

    <!-- Minimal environment for launchd (no shell profile is loaded) -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${home_dir}</string>
    </dict>
</dict>
</plist>
PLIST_FOOTER
}

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================
check_prerequisites() {
    section "Checking prerequisites"

    if [[ "$(uname -s)" != "Darwin" ]]; then
        error "This tool is designed for macOS only."
        error "Detected OS: $(uname -s)"
        exit 1
    fi
    success "macOS detected ($(sw_vers -productVersion))"

    if command -v brew &>/dev/null; then
        BREW_PREFIX="$(brew --prefix)"
        success "Homebrew found at ${BREW_PREFIX}"
    elif [[ -x /opt/homebrew/bin/brew ]]; then
        BREW_PREFIX="/opt/homebrew"
        success "Homebrew found at ${BREW_PREFIX} (not in PATH, will configure)"
    elif [[ -x /usr/local/bin/brew ]]; then
        BREW_PREFIX="/usr/local"
        success "Homebrew found at ${BREW_PREFIX} (not in PATH, will configure)"
    else
        error "Homebrew is not installed."
        error "Install it first: https://brew.sh"
        exit 1
    fi

    # Verify required source files exist alongside this installer.
    # Note: com.user.brew-autoupdate.plist is no longer required —
    # the plist is generated dynamically from config.conf.
    local required_files=("brew-autoupdate.sh" "brew-autoupdate-viewer.sh" "config.conf")
    for f in "${required_files[@]}"; do
        if [[ ! -f "${SOURCE_DIR}/${f}" ]]; then
            error "Missing required file: ${f}"
            error "Ensure all files are in the same directory as install.sh"
            exit 1
        fi
    done
    success "All source files present"
}

# ============================================================================
# INSTALLATION
# ============================================================================
do_install() {
    section "Installing Homebrew Auto-Update"

    info "Creating directories..."
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${LAUNCH_AGENTS_DIR}"
    mkdir -p "${LOG_DIR}/detail"
    mkdir -p "${LOG_DIR}/summary"
    success "Directories created"

    info "Installing scripts..."
    cp "${SOURCE_DIR}/brew-autoupdate.sh"        "${INSTALL_DIR}/brew-autoupdate.sh"
    cp "${SOURCE_DIR}/brew-autoupdate-viewer.sh" "${INSTALL_DIR}/brew-autoupdate-viewer.sh"
    # Copy the installer itself so 'brew-logs schedule reload' can call it
    cp "${SOURCE_DIR}/install.sh"                "${INSTALL_DIR}/install.sh"
    success "Scripts installed to ${INSTALL_DIR}/"

    if [[ -f "${INSTALL_DIR}/config.conf" ]]; then
        warn "Existing config.conf found - preserving your customizations"
        cp "${SOURCE_DIR}/config.conf" "${INSTALL_DIR}/config.conf.new"
        info "New default config saved as config.conf.new for reference"
    else
        cp "${SOURCE_DIR}/config.conf" "${INSTALL_DIR}/config.conf"
        success "Default config.conf installed"
    fi

    info "Setting permissions..."
    chmod 755 "${INSTALL_DIR}/brew-autoupdate.sh"
    chmod 755 "${INSTALL_DIR}/brew-autoupdate-viewer.sh"
    chmod 755 "${INSTALL_DIR}/install.sh"
    chmod 644 "${INSTALL_DIR}/config.conf"
    success "Permissions set"

    # -----------------------------------------------------------------
    # Generate the launchd plist from schedule in config.conf
    # This replaces the old template-substitution approach and
    # supports fully customizable schedules.
    # -----------------------------------------------------------------
    info "Reading schedule from config.conf..."
    local sched_hours sched_minute
    sched_hours=$(read_config_value "${INSTALL_DIR}/config.conf" SCHEDULE_HOURS "0,6,12,18")
    sched_minute=$(read_config_value "${INSTALL_DIR}/config.conf" SCHEDULE_MINUTE "0")
    info "Schedule: hours=[${sched_hours}]  minute=${sched_minute}"

    info "Generating launchd plist..."
    generate_plist "${sched_hours}" "${sched_minute}" "${INSTALL_DIR}" "${HOME}" > "${PLIST_FILE}"
    chmod 644 "${PLIST_FILE}"
    success "Plist installed to ${PLIST_FILE}"

    info "Validating plist..."
    if plutil -lint "${PLIST_FILE}" &>/dev/null; then
        success "Plist validation passed"
    else
        error "Plist validation FAILED:"
        plutil -lint "${PLIST_FILE}"
        exit 1
    fi

    info "Creating 'brew-logs' command..."
    ln -sf "${INSTALL_DIR}/brew-autoupdate-viewer.sh" "${BREW_PREFIX}/bin/brew-logs"
    success "'brew-logs' command available in PATH"

    section "Starting daemon"
    info "Loading launchd daemon..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true
    launchctl load -w "${PLIST_FILE}"

    if launchctl list "${PLIST_LABEL}" &>/dev/null; then
        success "Daemon loaded and scheduled"
    else
        error "Daemon failed to load. Check: launchctl list ${PLIST_LABEL}"
        exit 1
    fi
}

# ============================================================================
# RELOAD SCHEDULE ONLY
# ============================================================================
# Called by 'brew-logs schedule reload'. Regenerates and reloads the plist
# from the current config.conf without touching any other installed files.
# ----------------------------------------------------------------------------
do_reload_schedule() {
    section "Reloading schedule"

    # When called from INSTALL_DIR (via brew-logs), SOURCE_DIR == INSTALL_DIR
    local config_path="${INSTALL_DIR}/config.conf"
    if [[ ! -f "${config_path}" ]]; then
        error "config.conf not found at ${config_path}"
        exit 1
    fi

    local sched_hours sched_minute
    sched_hours=$(read_config_value "${config_path}" SCHEDULE_HOURS "0,6,12,18")
    sched_minute=$(read_config_value "${config_path}" SCHEDULE_MINUTE "0")

    info "SCHEDULE_HOURS=${sched_hours}  SCHEDULE_MINUTE=${sched_minute}"

    info "Unloading current daemon..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true
    success "Daemon unloaded"

    info "Regenerating plist..."
    generate_plist "${sched_hours}" "${sched_minute}" "${INSTALL_DIR}" "${HOME}" > "${PLIST_FILE}"
    chmod 644 "${PLIST_FILE}"

    info "Validating plist..."
    if plutil -lint "${PLIST_FILE}" &>/dev/null; then
        success "Plist validation passed"
    else
        error "Plist validation FAILED:"
        plutil -lint "${PLIST_FILE}"
        exit 1
    fi

    info "Loading daemon with new schedule..."
    launchctl load -w "${PLIST_FILE}"

    if launchctl list "${PLIST_LABEL}" &>/dev/null; then
        # Format schedule for display
        local sched_display=""
        IFS=',' read -ra hrs <<< "${sched_hours}"
        local mm; printf -v mm '%02d' "${sched_minute}"
        for h in "${hrs[@]}"; do
            h=$(echo "${h}" | xargs)
            [[ -n "${h}" ]] && sched_display+="$(printf '%d:%s' "${h}" "${mm}")  "
        done
        success "Daemon reloaded with new schedule"
        success "Runs at: ${sched_display}"
    else
        error "Daemon failed to load. Check: launchctl list ${PLIST_LABEL}"
        exit 1
    fi
}

# ============================================================================
# UNINSTALLATION
# ============================================================================
do_uninstall() {
    section "Uninstalling Homebrew Auto-Update"

    echo
    read -r -p "Remove brew-autoupdate and all its files? [y/N] " confirm
    echo
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        info "Uninstall cancelled."
        exit 0
    fi

    info "Unloading daemon..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true
    success "Daemon unloaded"

    if [[ -f "${PLIST_FILE}" ]]; then
        rm -f "${PLIST_FILE}"
        success "Removed ${PLIST_FILE}"
    fi

    local brew_logs_link="${BREW_PREFIX:-/opt/homebrew}/bin/brew-logs"
    if [[ -L "${brew_logs_link}" ]]; then
        rm -f "${brew_logs_link}"
        success "Removed brew-logs symlink"
    fi

    if [[ -d "${INSTALL_DIR}" ]]; then
        rm -rf "${INSTALL_DIR}"
        success "Removed ${INSTALL_DIR}/"
    fi

    warn "Log files preserved at: ${LOG_DIR}/"
    warn "To remove logs too: rm -rf \"${LOG_DIR}\""

    echo
    success "Uninstall complete."
}

# ============================================================================
# POST-INSTALL VERIFICATION
# ============================================================================
do_verify() {
    section "Verification"
    echo
    read -p "Run a test update now to verify? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        info "Running test update (this may take a minute)..."
        echo
        bash "${INSTALL_DIR}/brew-autoupdate.sh"
        echo
        success "Test complete. Check results with: brew-logs detail"
    else
        info "Skipped. The daemon will run automatically at the next scheduled time."
    fi
}

# ============================================================================
# POST-INSTALL SUMMARY
# ============================================================================
show_summary() {
    local sched_hours sched_minute
    sched_hours=$(read_config_value "${INSTALL_DIR}/config.conf" SCHEDULE_HOURS "0,6,12,18")
    sched_minute=$(read_config_value "${INSTALL_DIR}/config.conf" SCHEDULE_MINUTE "0")

    # Build human-readable schedule
    local sched_display=""
    local mm; printf -v mm '%02d' "${sched_minute}"
    IFS=',' read -ra hrs <<< "${sched_hours}"
    for h in "${hrs[@]}"; do
        h=$(echo "${h}" | xargs)
        [[ -n "${h}" ]] && sched_display+="$(printf '%d:%s' "${h}" "${mm}")  "
    done

    section "Installation complete"
    echo
    echo -e "${BOLD}Schedule:${NC} ${sched_display}"
    echo -e "  ${DIM}(edit SCHEDULE_HOURS in config.conf, then run: brew-logs schedule reload)${NC}"
    echo
    echo -e "${BOLD}Installed files:${NC}"
    echo "  ${INSTALL_DIR}/brew-autoupdate.sh"
    echo "  ${INSTALL_DIR}/brew-autoupdate-viewer.sh"
    echo "  ${INSTALL_DIR}/install.sh"
    echo "  ${INSTALL_DIR}/config.conf"
    echo "  ${PLIST_FILE}"
    echo
    echo -e "${BOLD}Log locations:${NC}"
    echo "  Detail:  ${LOG_DIR}/detail/   (90-day retention)"
    echo "  Summary: ${LOG_DIR}/summary/  (365-day retention)"
    echo
    echo -e "${BOLD}Quick commands:${NC}"
    echo "  brew-logs dashboard    Graphical status & statistics console"
    echo "  brew-logs              View latest detail log"
    echo "  brew-logs summary      View latest summary"
    echo "  brew-logs errors       Check for recent errors"
    echo "  brew-logs status       Check daemon status"
    echo "  brew-logs run          Trigger manual update"
    echo "  brew-logs schedule     Show current schedule"
    echo "  brew-logs config       View current settings"
    echo "  brew-logs help         Full command reference"
    echo
    echo -e "${BOLD}Configuration:${NC}"
    echo "  Edit: ${INSTALL_DIR}/config.conf"
    echo "  Changes take effect on next run (no restart needed)"
    echo "  Schedule changes need: brew-logs schedule reload"
    echo
    echo -e "${BOLD}Daemon management:${NC}"
    echo "  Stop:    launchctl unload ${PLIST_FILE}"
    echo "  Start:   launchctl load -w ${PLIST_FILE}"
    echo "  Status:  launchctl list ${PLIST_LABEL}"
    echo
}

# ============================================================================
# USAGE / HELP
# ============================================================================
show_help() {
    echo -e "${BOLD}Homebrew Auto-Update Installer${NC}  v${BAU_VERSION}"
    echo
    echo "Usage: bash install.sh [option]"
    echo
    echo "Options:"
    echo "  (none)             Install or upgrade"
    echo "  --uninstall        Remove all components (preserves logs)"
    echo "  --reinstall        Full uninstall + fresh install"
    echo "  --reload-schedule  Regenerate plist from config.conf schedule"
    echo "  --help             Show this help"
    echo
    echo "For more information, see README.md"
}

# ============================================================================
# ENTRY POINT
# ============================================================================
echo -e "${BOLD}Homebrew Auto-Update${NC}  v${BAU_VERSION}"
case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --uninstall)
        check_prerequisites
        do_uninstall
        ;;
    --reinstall)
        check_prerequisites
        do_uninstall
        echo
        do_install
        show_summary
        do_verify
        ;;
    --reload-schedule)
        # Called by 'brew-logs schedule reload'
        # Minimal prerequisites: just needs macOS + the plist label target
        if [[ "$(uname -s)" != "Darwin" ]]; then
            error "macOS only."
            exit 1
        fi
        do_reload_schedule
        ;;
    "")
        check_prerequisites
        do_install
        show_summary
        do_verify
        ;;
    *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
