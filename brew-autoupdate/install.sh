#!/usr/bin/env bash
# ============================================================================
#
#  HOMEBREW AUTO-UPDATE INSTALLER
#
#  File:     install.sh
#  Version:  1.0.0
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
#      4. Generates a user-specific launchd plist from the template
#      5. Sets file permissions (scripts executable, config readable)
#      6. Symlinks the viewer as 'brew-logs' in Homebrew's bin directory
#      7. Creates log directories under ~/Library/Logs/
#      8. Loads the launchd daemon for automatic scheduling
#      9. Optionally runs a verification test
#
#  Usage:
#    bash install.sh              # Standard install
#    bash install.sh --uninstall  # Remove everything
#    bash install.sh --reinstall  # Uninstall then install fresh
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
#    ~/.config/brew-autoupdate/config.conf               Configuration file
#    ~/Library/LaunchAgents/com.user.brew-autoupdate.plist  Daemon schedule
#    ~/Library/Logs/brew-autoupdate/detail/               Detail log dir
#    ~/Library/Logs/brew-autoupdate/summary/              Summary log dir
#    $(brew --prefix)/bin/brew-logs                       Symlink to viewer
#
# ============================================================================

# ----------------------------------------------------------------------------
# Shell Options
# ----------------------------------------------------------------------------
set -euo pipefail

# ============================================================================
# TERMINAL FORMATTING
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# INSTALLATION PATHS
# ============================================================================
# SOURCE_DIR: Where this installer and the source files are located.
#   Resolved from the installer script's own location.
# INSTALL_DIR: Where scripts and config are installed.
#   ~/.config/ is the XDG standard for user configuration on Unix systems.
# PLIST_LABEL: Unique identifier for the launchd daemon job.
# ----------------------------------------------------------------------------
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.config/brew-autoupdate"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
LOG_DIR="${HOME}/Library/Logs/brew-autoupdate"
PLIST_LABEL="com.user.brew-autoupdate"
PLIST_FILE="${LAUNCH_AGENTS_DIR}/${PLIST_LABEL}.plist"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print a formatted status message with a colored prefix
info()    { echo -e "${CYAN}[INFO]${NC}    $*"; }
success() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; }

# Print a section header with visual separation
section() {
    echo
    echo -e "${BOLD}── $* ──${NC}"
}

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================
# Verifies that we're running on macOS with Homebrew installed.
# These are hard requirements - the script cannot function without them.
# ----------------------------------------------------------------------------
check_prerequisites() {
    section "Checking prerequisites"

    # Verify macOS (Darwin kernel)
    if [[ "$(uname -s)" != "Darwin" ]]; then
        error "This tool is designed for macOS only."
        error "Detected OS: $(uname -s)"
        exit 1
    fi
    success "macOS detected ($(sw_vers -productVersion))"

    # Verify Homebrew is installed and accessible
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

    # Verify source files exist alongside this installer
    local required_files=("brew-autoupdate.sh" "brew-autoupdate-viewer.sh" "config.conf" "com.user.brew-autoupdate.plist")
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

    # --- Create directories ---
    # ~/.config/brew-autoupdate/  - scripts and configuration
    # ~/Library/LaunchAgents/     - macOS daemon definitions (usually exists)
    # ~/Library/Logs/brew-autoupdate/{detail,summary}/  - log storage
    # ------------------------------------------------------------------------
    info "Creating directories..."
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${LAUNCH_AGENTS_DIR}"
    mkdir -p "${LOG_DIR}/detail"
    mkdir -p "${LOG_DIR}/summary"
    success "Directories created"

    # --- Copy scripts ---
    # Always overwrite scripts on install/upgrade to get latest fixes.
    # ------------------------------------------------------------------------
    info "Installing scripts..."
    cp "${SOURCE_DIR}/brew-autoupdate.sh" "${INSTALL_DIR}/brew-autoupdate.sh"
    cp "${SOURCE_DIR}/brew-autoupdate-viewer.sh" "${INSTALL_DIR}/brew-autoupdate-viewer.sh"
    success "Scripts installed to ${INSTALL_DIR}/"

    # --- Copy config (preserve existing) ---
    # If the user already has a config, don't overwrite their customizations.
    # Instead, copy the new default as config.conf.new for reference.
    # ------------------------------------------------------------------------
    if [[ -f "${INSTALL_DIR}/config.conf" ]]; then
        warn "Existing config.conf found - preserving your customizations"
        cp "${SOURCE_DIR}/config.conf" "${INSTALL_DIR}/config.conf.new"
        info "New default config saved as config.conf.new for reference"
    else
        cp "${SOURCE_DIR}/config.conf" "${INSTALL_DIR}/config.conf"
        success "Default config.conf installed"
    fi

    # --- Set file permissions ---
    # Scripts need execute permission. Config is read-only for the owner.
    # ------------------------------------------------------------------------
    info "Setting permissions..."
    chmod 755 "${INSTALL_DIR}/brew-autoupdate.sh"
    chmod 755 "${INSTALL_DIR}/brew-autoupdate-viewer.sh"
    chmod 644 "${INSTALL_DIR}/config.conf"
    success "Permissions set"

    # --- Generate launchd plist ---
    # The plist template contains placeholders for user-specific paths.
    # We replace them with the actual HOME directory and install location
    # so the plist works for any user, not just the original author.
    # ------------------------------------------------------------------------
    info "Generating launchd plist..."
    sed \
        -e "s|HOME_PLACEHOLDER|${HOME}|g" \
        -e "s|INSTALL_DIR_PLACEHOLDER|${HOME}|g" \
        "${SOURCE_DIR}/com.user.brew-autoupdate.plist" > "${PLIST_FILE}"
    # Remove the XML comment block at the top (launchd doesn't like comments before the XML declaration)
    # Actually, we need to ensure the XML declaration is first. The template has comments before it.
    # Extract from <?xml onwards
    local temp_plist
    temp_plist="$(mktemp)"
    sed -n '/<?xml/,$p' "${PLIST_FILE}" > "${temp_plist}"
    mv "${temp_plist}" "${PLIST_FILE}"
    chmod 644 "${PLIST_FILE}"
    success "Plist installed to ${PLIST_FILE}"

    # --- Validate plist syntax ---
    # plutil is macOS's built-in plist validation tool. Catches XML errors
    # before we try to load the daemon (which would fail silently).
    # ------------------------------------------------------------------------
    info "Validating plist..."
    if plutil -lint "${PLIST_FILE}" &>/dev/null; then
        success "Plist validation passed"
    else
        error "Plist validation FAILED:"
        plutil -lint "${PLIST_FILE}"
        exit 1
    fi

    # --- Create brew-logs symlink ---
    # Symlinks the viewer script into Homebrew's bin directory so it's
    # accessible as just 'brew-logs' from any terminal.
    # Uses -sf (force) to update existing symlinks cleanly.
    # ------------------------------------------------------------------------
    info "Creating 'brew-logs' command..."
    ln -sf "${INSTALL_DIR}/brew-autoupdate-viewer.sh" "${BREW_PREFIX}/bin/brew-logs"
    success "'brew-logs' command available in PATH"

    # --- Load the launchd daemon ---
    # Unload first (ignoring errors if not loaded) then load with -w flag.
    # The -w flag marks the job as "not disabled", ensuring it persists
    # across reboots and isn't affected by launchctl disable commands.
    # ------------------------------------------------------------------------
    section "Starting daemon"
    info "Loading launchd daemon..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true
    launchctl load -w "${PLIST_FILE}"

    # Verify the daemon loaded successfully
    if launchctl list "${PLIST_LABEL}" &>/dev/null; then
        success "Daemon loaded and scheduled"
    else
        error "Daemon failed to load. Check: launchctl list ${PLIST_LABEL}"
        exit 1
    fi
}

# ============================================================================
# UNINSTALLATION
# ============================================================================
# Removes all installed components. Log files are preserved by default
# (they may contain useful historical data). Use rm -rf on the log
# directory manually if you want to remove them too.
# ----------------------------------------------------------------------------
do_uninstall() {
    section "Uninstalling Homebrew Auto-Update"

    # Stop and unload the daemon first (before removing its plist)
    info "Unloading daemon..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true
    success "Daemon unloaded"

    # Remove the launchd plist
    if [[ -f "${PLIST_FILE}" ]]; then
        rm -f "${PLIST_FILE}"
        success "Removed ${PLIST_FILE}"
    fi

    # Remove the brew-logs symlink
    local brew_logs_link="${BREW_PREFIX:-/opt/homebrew}/bin/brew-logs"
    if [[ -L "${brew_logs_link}" ]]; then
        rm -f "${brew_logs_link}"
        success "Removed brew-logs symlink"
    fi

    # Remove scripts and config directory
    if [[ -d "${INSTALL_DIR}" ]]; then
        rm -rf "${INSTALL_DIR}"
        success "Removed ${INSTALL_DIR}/"
    fi

    # Preserve logs but inform the user
    warn "Log files preserved at: ${LOG_DIR}/"
    warn "To remove logs too: rm -rf \"${LOG_DIR}\""

    echo
    success "Uninstall complete."
}

# ============================================================================
# POST-INSTALL VERIFICATION
# ============================================================================
# Optionally runs a test update cycle to verify everything works end-to-end.
# Shows real-time output so the user can see brew commands executing.
# ----------------------------------------------------------------------------
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
# Displays a summary of what was installed and how to use it.
# Shown after successful installation.
# ----------------------------------------------------------------------------
show_summary() {
    section "Installation complete"
    echo
    echo -e "${BOLD}Schedule:${NC} Runs at 12 AM, 6 AM, 12 PM, 6 PM daily"
    echo
    echo -e "${BOLD}Installed files:${NC}"
    echo "  ${INSTALL_DIR}/brew-autoupdate.sh"
    echo "  ${INSTALL_DIR}/brew-autoupdate-viewer.sh"
    echo "  ${INSTALL_DIR}/config.conf"
    echo "  ${PLIST_FILE}"
    echo
    echo -e "${BOLD}Log locations:${NC}"
    echo "  Detail:  ${LOG_DIR}/detail/   (90-day retention)"
    echo "  Summary: ${LOG_DIR}/summary/  (365-day retention)"
    echo
    echo -e "${BOLD}Quick commands:${NC}"
    echo "  brew-logs              View latest detail log"
    echo "  brew-logs summary      View latest summary"
    echo "  brew-logs errors       Check for recent errors"
    echo "  brew-logs status       Check daemon status"
    echo "  brew-logs run          Trigger manual update"
    echo "  brew-logs config       View current settings"
    echo "  brew-logs help         Full command reference"
    echo
    echo -e "${BOLD}Configuration:${NC}"
    echo "  Edit: ${INSTALL_DIR}/config.conf"
    echo "  Changes take effect on next run (no restart needed)"
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
    echo -e "${BOLD}Homebrew Auto-Update Installer${NC}"
    echo
    echo "Usage: bash install.sh [option]"
    echo
    echo "Options:"
    echo "  (none)        Install or upgrade"
    echo "  --uninstall   Remove all components (preserves logs)"
    echo "  --reinstall   Full uninstall + fresh install"
    echo "  --help        Show this help"
    echo
    echo "For more information, see README.md"
}

# ============================================================================
# ENTRY POINT
# ============================================================================
# Routes to the appropriate action based on command-line argument.
# Default (no argument) is a standard install.
# ----------------------------------------------------------------------------
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
