#!/usr/bin/env bash
# =============================================================================
#
#   MESSAGES EXPORTER INSTALLER
#
#   File:        install.sh
#   Version:     1.0.0
#   Author:      Generated with Claude Code
#   License:     MIT
#   Requires:    macOS, bash 3.2+, Homebrew
#
#   Description:
#     Installs messages-exporter on a fresh Mac. Steps:
#       1. Install brew dependencies (exiftool, ffmpeg)
#       2. Create a dedicated Python venv at ~/.venvs/messages-exporter
#       3. Install Python dependencies (Pillow, pillow-heif, emoji) in the venv
#       4. Install the script to ~/.local/bin/export_messages (or
#          /usr/local/bin with --system). The installed copy has the venv's
#          python baked into its shebang so it is self-contained.
#
#   Usage:
#     ./install.sh              Install to ~/.local/bin (default, no sudo)
#     ./install.sh --system     Install to /usr/local/bin (requires sudo)
#     ./install.sh --upgrade    Re-run install to refresh script and deps
#     ./install.sh --uninstall  Remove the installed script and the venv
#     ./install.sh --help       Show this help
#
# =============================================================================

set -euo pipefail

# ─── Constants ───────────────────────────────────────────────────────────────

TOOL_NAME="messages-exporter"
TOOL_CMD="export_messages"
SCRIPT_FILE="export_messages.py"
REQ_FILE="requirements.txt"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SCRIPT_DIR}/${SCRIPT_FILE}"
REQUIREMENTS="${SCRIPT_DIR}/${REQ_FILE}"

VENV_DIR="${HOME}/.venvs/${TOOL_NAME}"
USER_BIN="${HOME}/.local/bin"
SYSTEM_BIN="/usr/local/bin"
INSTALL_DIR="${USER_BIN}"   # overridden by --system

# Read version from the script's __version__ line.
TOOL_VERSION="$(grep -m1 '^__version__' "${SOURCE}" 2>/dev/null \
                | sed -E "s/^__version__ = ['\"](.+)['\"].*/\1/" \
                || echo 'unknown')"

# ─── Color helpers ──────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    C_RESET="\033[0m"; C_BOLD="\033[1m"
    C_GREEN="\033[32m"; C_YELLOW="\033[33m"
    C_RED="\033[31m";   C_CYAN="\033[36m"; C_DIM="\033[2m"
else
    C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_DIM=""
fi

info()  { printf "${C_CYAN}==>${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}✓${C_RESET}   %s\n" "$*"; }
warn()  { printf "${C_YELLOW}!${C_RESET}   %s\n" "$*" >&2; }
fail()  { printf "${C_RED}✗${C_RESET}   %s\n" "$*" >&2; exit 1; }

# ─── Arg parsing ────────────────────────────────────────────────────────────

MODE="install"

print_help() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)    INSTALL_DIR="${SYSTEM_BIN}"; shift ;;
        --upgrade)   MODE="upgrade"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        -h|--help)   print_help ;;
        *)           fail "Unknown option: $1 (try --help)" ;;
    esac
done

# ─── Precondition checks ────────────────────────────────────────────────────

require_macos() {
    [[ "$OSTYPE" == darwin* ]] || fail "This tool is macOS-only (current OS: $OSTYPE)."
}

require_brew() {
    command -v brew >/dev/null 2>&1 || fail \
        "Homebrew is required. Install from https://brew.sh and re-run this script."
}

require_python3() {
    command -v python3 >/dev/null 2>&1 || fail \
        "python3 not found. macOS ships with /usr/bin/python3 — run once to install the CLT."
}

# ─── Uninstall ──────────────────────────────────────────────────────────────

do_uninstall() {
    info "Uninstalling ${TOOL_NAME}..."
    local removed=0
    for bin_dir in "${USER_BIN}" "${SYSTEM_BIN}"; do
        local target="${bin_dir}/${TOOL_CMD}"
        if [[ -e "${target}" ]]; then
            if [[ "${bin_dir}" == "${SYSTEM_BIN}" ]]; then
                sudo rm -f "${target}"
            else
                rm -f "${target}"
            fi
            ok "Removed ${target}"
            removed=1
        fi
    done
    if [[ -d "${VENV_DIR}" ]]; then
        rm -rf "${VENV_DIR}"
        ok "Removed venv ${VENV_DIR}"
        removed=1
    fi
    [[ ${removed} -eq 0 ]] && warn "Nothing to remove."
    info "Brew packages (exiftool, ffmpeg) were left in place; uninstall them manually if unwanted."
    exit 0
}

# ─── Install / upgrade ──────────────────────────────────────────────────────

install_brew_deps() {
    info "Installing brew dependencies (exiftool, ffmpeg)..."
    local pkgs=()
    command -v exiftool >/dev/null 2>&1 || pkgs+=(exiftool)
    command -v ffmpeg   >/dev/null 2>&1 || pkgs+=(ffmpeg)
    if (( ${#pkgs[@]} == 0 )); then
        ok "exiftool and ffmpeg already installed"
    else
        brew install "${pkgs[@]}"
        ok "Installed: ${pkgs[*]}"
    fi
}

setup_venv() {
    if [[ -d "${VENV_DIR}" ]]; then
        info "Refreshing venv at ${VENV_DIR}"
    else
        info "Creating venv at ${VENV_DIR}"
        mkdir -p "$(dirname "${VENV_DIR}")"
        python3 -m venv "${VENV_DIR}"
    fi
    "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
    "${VENV_DIR}/bin/pip" install --quiet -r "${REQUIREMENTS}"
    ok "Python dependencies installed in venv"
}

install_script() {
    local target="${INSTALL_DIR}/${TOOL_CMD}"
    info "Installing ${TOOL_CMD} to ${target}"

    # Build the installed copy: real script body with a venv shebang baked in.
    local tmp
    tmp="$(mktemp -t "${TOOL_CMD}.XXXXXX")"
    {
        printf '#!%s\n' "${VENV_DIR}/bin/python3"
        # Skip the script's own shebang line (#!/usr/bin/env python3).
        tail -n +2 "${SOURCE}"
    } > "${tmp}"
    chmod +x "${tmp}"

    if [[ "${INSTALL_DIR}" == "${SYSTEM_BIN}" ]]; then
        sudo install -m 0755 "${tmp}" "${target}"
    else
        mkdir -p "${INSTALL_DIR}"
        install -m 0755 "${tmp}" "${target}"
    fi
    rm -f "${tmp}"
    ok "Installed ${target}"
}

ensure_path() {
    # /usr/local/bin is normally on PATH; ~/.local/bin often is not.
    [[ "${INSTALL_DIR}" == "${SYSTEM_BIN}" ]] && return
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) return ;;
    esac
    warn "${INSTALL_DIR} is not on your PATH."
    printf "    Add this to your ~/.zshrc (or ~/.bash_profile):\n"
    printf "        ${C_BOLD}export PATH=\"%s:\$PATH\"${C_RESET}\n" "${INSTALL_DIR}"
}

fda_reminder() {
    cat <<EOF

${C_BOLD}Full Disk Access (one-time)${C_RESET}
The exporter reads ~/Library/Messages/chat.db, which requires Full Disk
Access. Grant it to the Terminal app you'll run ${TOOL_CMD} from:

  System Settings  →  Privacy & Security  →  Full Disk Access  →  [+]
  Add: Terminal.app (or Warp, iTerm, etc.) — then quit and relaunch.

EOF
}

do_install() {
    info "${TOOL_NAME} v${TOOL_VERSION} — installing to ${INSTALL_DIR}"
    require_macos
    require_python3
    require_brew
    [[ -f "${SOURCE}"       ]] || fail "Missing ${SOURCE}"
    [[ -f "${REQUIREMENTS}" ]] || fail "Missing ${REQUIREMENTS}"

    install_brew_deps
    setup_venv
    install_script
    ensure_path
    fda_reminder

    ok "Done. Verify with:  ${C_BOLD}${TOOL_CMD} --version${C_RESET}"
}

# ─── Dispatch ───────────────────────────────────────────────────────────────

case "${MODE}" in
    uninstall) do_uninstall ;;
    install|upgrade) do_install ;;
esac
