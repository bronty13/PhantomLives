#!/usr/bin/env bash
# install.sh — Install fsearch on macOS
#
# Usage:
#   ./install.sh              # installs to ~/.local/bin  (no sudo)
#   ./install.sh --system     # installs to /usr/local/bin (requires sudo)
#   ./install.sh --uninstall  # removes fsearch and cleans up PATH entry

set -euo pipefail

TOOL_NAME="fsearch"
SCRIPT_FILE="fsearch.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/$SCRIPT_FILE"

USER_BIN="$HOME/.local/bin"
SYSTEM_BIN="/usr/local/bin"
INSTALL_DIR="$USER_BIN"   # default; overridden by --system

# ─── Colour helpers ─────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    C_RESET="\033[0m"; C_BOLD="\033[1m"
    C_GREEN="\033[32m"; C_YELLOW="\033[33m"
    C_RED="\033[31m";   C_CYAN="\033[36m"
else
    C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
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
        --system)    INSTALL_DIR="$SYSTEM_BIN" ;;
        --uninstall) MODE="uninstall" ;;
        --help|-h)
            cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  (none)        Install to ~/.local/bin  (user-local, no sudo required)
  --system      Install to /usr/local/bin (system-wide, requires sudo)
  --uninstall   Remove fsearch and PATH entry from shell config
  --help        Show this message
EOF
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

DEST="$INSTALL_DIR/$TOOL_NAME"

# ─── Shell config detection ──────────────────────────────────────────────────
# Returns the rc file(s) to update for the current user's shell(s).

detect_shell_configs() {
    local configs=()

    # Check SHELL env var first, then common rc files that exist
    case "${SHELL:-}" in
        */zsh)  configs+=("$HOME/.zshrc") ;;
        */bash) configs+=("$HOME/.bash_profile" "$HOME/.bashrc") ;;
    esac

    # Always check for additional files that exist and may be sourced
    for f in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
        # Add only if it exists and isn't already in the list
        if [[ -f "$f" ]]; then
            local already=false
            for existing in "${configs[@]+"${configs[@]}"}"; do
                [[ "$existing" == "$f" ]] && already=true && break
            done
            [[ "$already" == false ]] && configs+=("$f")
        fi
    done

    # Fallback: create .zshrc (macOS default since Catalina)
    if [[ ${#configs[@]} -eq 0 ]]; then
        configs+=("$HOME/.zshrc")
    fi

    printf '%s\n' "${configs[@]}"
}

PATH_SNIPPET='export PATH="$HOME/.local/bin:$PATH"'
PATH_MARKER="# fsearch PATH"

# ─── Install ─────────────────────────────────────────────────────────────────

do_install() {
    header "Installing $TOOL_NAME"

    # Verify source script exists
    [[ -f "$SOURCE" ]] || die "Source not found: $SOURCE\n       Run this script from inside the fsearch/ directory."

    # Create install dir
    if [[ ! -d "$INSTALL_DIR" ]]; then
        if [[ "$INSTALL_DIR" == "$SYSTEM_BIN" ]]; then
            info "Creating $INSTALL_DIR (sudo required)"
            sudo mkdir -p "$INSTALL_DIR"
        else
            mkdir -p "$INSTALL_DIR"
        fi
        success "Created $INSTALL_DIR"
    fi

    # Copy and chmod
    if [[ "$INSTALL_DIR" == "$SYSTEM_BIN" ]]; then
        sudo cp "$SOURCE" "$DEST"
        sudo chmod 755 "$DEST"
    else
        cp "$SOURCE" "$DEST"
        chmod 755 "$DEST"
    fi
    success "Installed $DEST"

    # ── PATH update (only needed for user-local installs) ────────────────────
    if [[ "$INSTALL_DIR" == "$USER_BIN" ]]; then

        # Check if ~/.local/bin is already on PATH
        if printf '%s' "$PATH" | tr ':' '\n' | grep -qxF "$USER_BIN"; then
            info "$USER_BIN is already in \$PATH — skipping shell config update"
        else
            mapfile -t shell_configs < <(detect_shell_configs)

            local updated=false
            for rc in "${shell_configs[@]}"; do
                # Skip if our snippet is already present
                if grep -qF "$PATH_MARKER" "$rc" 2>/dev/null; then
                    info "PATH entry already present in $rc"
                    continue
                fi

                # Create the file if it doesn't exist
                [[ -f "$rc" ]] || touch "$rc"

                printf '\n%s\n%s\n' "$PATH_MARKER" "$PATH_SNIPPET" >> "$rc"
                success "Added PATH entry to $rc"
                updated=true
            done

            if [[ "$updated" == true ]]; then
                printf '\n'
                warn "Restart your terminal (or run the command below) to update \$PATH:"
                printf '       source %s\n' "${shell_configs[0]}"
            fi
        fi
    fi

    # ── Verify ───────────────────────────────────────────────────────────────
    printf '\n'
    if command -v "$TOOL_NAME" &>/dev/null; then
        success "$TOOL_NAME is ready: $(command -v "$TOOL_NAME")"
    else
        info "After reloading your shell, verify with: which $TOOL_NAME"
    fi

    printf '\n'
    printf "${C_BOLD}Quick start:${C_RESET}\n"
    printf '  %-40s %s\n' "$TOOL_NAME -h"                         "show help"
    printf '  %-40s %s\n' "$TOOL_NAME -n '\\.sh\$' -g 'TODO'"    "find .sh files containing TODO"
    printf '  %-40s %s\n' "$TOOL_NAME -g 'password' -i -0"        "list files containing 'password'"
    printf '  %-40s %s\n' "$TOOL_NAME -p ~/projects -g 'api_key'" "search a custom path"
    printf '\n'
}

# ─── Uninstall ───────────────────────────────────────────────────────────────

do_uninstall() {
    header "Uninstalling $TOOL_NAME"

    local removed_any=false

    # Remove from both possible locations
    for loc in "$USER_BIN/$TOOL_NAME" "$SYSTEM_BIN/$TOOL_NAME"; do
        if [[ -f "$loc" ]]; then
            if [[ "$loc" == "$SYSTEM_BIN/$TOOL_NAME" ]]; then
                sudo rm "$loc"
            else
                rm "$loc"
            fi
            success "Removed $loc"
            removed_any=true
        fi
    done

    [[ "$removed_any" == false ]] && warn "$TOOL_NAME was not found in $USER_BIN or $SYSTEM_BIN"

    # Clean up PATH entries from all shell configs
    for rc in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
        [[ -f "$rc" ]] || continue
        if grep -qF "$PATH_MARKER" "$rc" 2>/dev/null; then
            # Remove the marker line and the export line that follows it
            local tmp
            tmp="$(mktemp)"
            grep -v -A1 "$PATH_MARKER" "$rc" | grep -v "^--$" > "$tmp" || true
            mv "$tmp" "$rc"
            success "Removed PATH entry from $rc"
        fi
    done

    printf '\n'
    success "Uninstall complete."
}

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "$MODE" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
esac
