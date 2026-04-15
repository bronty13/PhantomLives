#!/usr/bin/env bash
# ============================================================================
#
#  FSEARCH INSTALLER
#
#  File:        install.sh
#  Version:     2.0.0
#  Author:      Generated with Claude Code
#  License:     MIT
#  Requires:    macOS or Linux, bash 3.2+
#
#  Description:
#    Installs fsearch to ~/.local/bin (user-local, no sudo) or
#    /usr/local/bin (system-wide, requires sudo).  Updates shell config
#    files to include the install directory in PATH.  Supports upgrade
#    and uninstall modes.
#
#  Usage:
#    ./install.sh              Install to ~/.local/bin (default)
#    ./install.sh --system     Install to /usr/local/bin (requires sudo)
#    ./install.sh --upgrade    Upgrade an existing install
#    ./install.sh --uninstall  Remove fsearch and clean up PATH entries
#    ./install.sh --help       Show this message
#
# ============================================================================

set -euo pipefail

# ─── Constants ───────────────────────────────────────────────────────────────

TOOL_NAME="fsearch"
TOOL_VERSION="2.0.0"
SCRIPT_FILE="fsearch.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SCRIPT_DIR}/${SCRIPT_FILE}"

USER_BIN="${HOME}/.local/bin"
SYSTEM_BIN="/usr/local/bin"
CONFIG_DIR="${HOME}/.config/fsearch"
INSTALL_DIR="${USER_BIN}"   # overridden by --system

# ─── Colour helpers ─────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    C_RESET="\033[0m"; C_BOLD="\033[1m"
    C_GREEN="\033[32m"; C_YELLOW="\033[33m"
    C_RED="\033[31m";   C_CYAN="\033[36m"; C_DIM="\033[2m"
else
    C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_DIM=""
fi

info()    { printf "${C_CYAN}  →${C_RESET} %s\n" "$*"; }
success() { printf "${C_GREEN}  ✓${C_RESET} %s\n" "$*"; }
warn()    { printf "${C_YELLOW}  ⚠${C_RESET} %s\n" "$*" >&2; }
die()     { printf "${C_RED}  ✗ error:${C_RESET} %s\n" "$*" >&2; exit 1; }
header()  { printf "\n${C_BOLD}%s${C_RESET}\n" "$*"; }

# ─── Argument parsing ────────────────────────────────────────────────────────

MODE="install"
for arg in "$@"; do
    case "$arg" in
        --system)    INSTALL_DIR="${SYSTEM_BIN}" ;;
        --upgrade)   MODE="upgrade" ;;
        --uninstall) MODE="uninstall" ;;
        --help|-h)
            cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  (none)        Install to ~/.local/bin  (user-local, no sudo required)
  --system      Install to /usr/local/bin (system-wide, requires sudo)
  --upgrade     Upgrade an existing install in-place
  --uninstall   Remove fsearch and PATH entry from shell configs
  --help        Show this message
EOF
            exit 0 ;;
        *) die "Unknown argument: $arg (see --help)" ;;
    esac
done

DEST="${INSTALL_DIR}/${TOOL_NAME}"

# ─── Shell config detection ──────────────────────────────────────────────────
# Returns the rc files to update for PATH configuration.

detect_shell_configs() {
    local configs=()

    case "${SHELL:-}" in
        */zsh)  configs+=("${HOME}/.zshrc") ;;
        */bash) configs+=("${HOME}/.bash_profile" "${HOME}/.bashrc") ;;
    esac

    local f
    for f in "${HOME}/.zshrc" "${HOME}/.bash_profile" "${HOME}/.bashrc" "${HOME}/.profile"; do
        [[ -f "$f" ]] || continue
        local already=false
        local existing
        for existing in "${configs[@]+"${configs[@]}"}"; do
            [[ "$existing" == "$f" ]] && already=true && break
        done
        [[ "$already" == false ]] && configs+=("$f")
    done

    [[ ${#configs[@]} -eq 0 ]] && configs+=("${HOME}/.zshrc")

    printf '%s\n' "${configs[@]}"
}

PATH_SNIPPET='export PATH="$HOME/.local/bin:$PATH"'
PATH_MARKER="# fsearch PATH"

# ─── Installed version detector ──────────────────────────────────────────────

installed_version() {
    local loc="$1"
    if [[ -f "$loc" ]]; then
        grep -m1 '^FSEARCH_VERSION=' "$loc" 2>/dev/null | cut -d'"' -f2 || echo "unknown"
    else
        echo "none"
    fi
}

# ─── Install / Upgrade ───────────────────────────────────────────────────────

do_install() {
    local is_upgrade="${1:-false}"

    if [[ "$is_upgrade" == true ]]; then
        header "Upgrading ${TOOL_NAME}"
        local current_ver
        current_ver="$(installed_version "${DEST}")"
        info "Current: ${current_ver}  →  New: ${TOOL_VERSION}"
    else
        header "Installing ${TOOL_NAME} v${TOOL_VERSION}"
    fi

    # Verify source exists
    [[ -f "${SOURCE}" ]] || die "Source not found: ${SOURCE}\n  Run from inside the fsearch/ directory."

    # Create install directory
    if [[ ! -d "${INSTALL_DIR}" ]]; then
        if [[ "${INSTALL_DIR}" == "${SYSTEM_BIN}" ]]; then
            info "Creating ${INSTALL_DIR} (sudo required)"
            sudo mkdir -p "${INSTALL_DIR}"
        else
            mkdir -p "${INSTALL_DIR}"
        fi
        success "Created ${INSTALL_DIR}"
    fi

    # Copy and set permissions
    if [[ "${INSTALL_DIR}" == "${SYSTEM_BIN}" ]]; then
        sudo cp "${SOURCE}" "${DEST}"
        sudo chmod 755 "${DEST}"
    else
        cp "${SOURCE}" "${DEST}"
        chmod 755 "${DEST}"
    fi
    success "Installed ${DEST}"

    # Create config directory (but not the file — defaults apply until user runs config set)
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        mkdir -p "${CONFIG_DIR}"
        success "Created config directory ${CONFIG_DIR}"
    fi

    # PATH update (only needed for user-local installs)
    if [[ "${INSTALL_DIR}" == "${USER_BIN}" ]]; then
        if printf '%s' "${PATH}" | tr ':' '\n' | grep -qxF "${USER_BIN}"; then
            info "${USER_BIN} is already in \$PATH — skipping shell config update"
        else
            local shell_configs updated=false rc
            while IFS= read -r rc; do
                shell_configs+=("$rc")
            done < <(detect_shell_configs)

            for rc in "${shell_configs[@]}"; do
                if grep -qF "${PATH_MARKER}" "${rc}" 2>/dev/null; then
                    info "PATH entry already present in ${rc}"
                    continue
                fi
                [[ -f "${rc}" ]] || touch "${rc}"
                printf '\n%s\n%s\n' "${PATH_MARKER}" "${PATH_SNIPPET}" >> "${rc}"
                success "Added PATH entry to ${rc}"
                updated=true
            done

            if [[ "${updated}" == true ]]; then
                printf '\n'
                warn "Restart your terminal (or source your shell config) to update \$PATH"
            fi
        fi
    fi

    # Verify
    printf '\n'
    if command -v "${TOOL_NAME}" &>/dev/null; then
        success "${TOOL_NAME} is ready: $(command -v "${TOOL_NAME}")"
    else
        info "After reloading your shell, verify with: which ${TOOL_NAME}"
    fi

    printf '\n'
    printf "${C_BOLD}Quick start:${C_RESET}\n"
    printf '  %-44s %s\n' "${TOOL_NAME} -h"                          "show help"
    printf '  %-44s %s\n' "${TOOL_NAME} -n '\\.sh\$' -g 'TODO'"     "find .sh files containing TODO"
    printf '  %-44s %s\n' "${TOOL_NAME} -g 'password' -i -0"         "list files containing 'password'"
    printf '  %-44s %s\n' "${TOOL_NAME} config"                       "show all settings"
    printf '  %-44s %s\n' "${TOOL_NAME} config path-add ~/projects"   "add a search path"
    printf '\n'
}

# ─── Uninstall ───────────────────────────────────────────────────────────────

do_uninstall() {
    header "Uninstalling ${TOOL_NAME}"

    local removed_any=false

    # Remove binary from both possible locations
    local loc
    for loc in "${USER_BIN}/${TOOL_NAME}" "${SYSTEM_BIN}/${TOOL_NAME}"; do
        if [[ -f "${loc}" ]]; then
            if [[ "${loc}" == "${SYSTEM_BIN}/${TOOL_NAME}" ]]; then
                sudo rm "${loc}"
            else
                rm "${loc}"
            fi
            success "Removed ${loc}"
            removed_any=true
        fi
    done

    [[ "${removed_any}" == false ]] && warn "${TOOL_NAME} was not found in ${USER_BIN} or ${SYSTEM_BIN}"

    # Offer to remove config directory
    if [[ -d "${CONFIG_DIR}" ]]; then
        printf '\n'
        printf '  Remove configuration directory %s? [y/N] ' "${CONFIG_DIR}"
        local answer
        read -r answer
        case "${answer}" in
            [Yy]|[Yy][Ee][Ss])
                rm -rf "${CONFIG_DIR}"
                success "Removed ${CONFIG_DIR}"
                ;;
            *)
                info "Keeping ${CONFIG_DIR}"
                ;;
        esac
    fi

    # Clean up PATH entries from all shell configs
    local rc
    for rc in "${HOME}/.zshrc" "${HOME}/.bash_profile" "${HOME}/.bashrc" "${HOME}/.profile"; do
        [[ -f "${rc}" ]] || continue
        if grep -qF "${PATH_MARKER}" "${rc}" 2>/dev/null; then
            local tmp
            tmp="$(mktemp)"
            grep -v -A1 "${PATH_MARKER}" "${rc}" | grep -v "^--$" > "${tmp}" || true
            mv "${tmp}" "${rc}"
            success "Removed PATH entry from ${rc}"
        fi
    done

    printf '\n'
    success "Uninstall complete."
}

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "${MODE}" in
    install)   do_install false ;;
    upgrade)   do_install true ;;
    uninstall) do_uninstall ;;
esac
