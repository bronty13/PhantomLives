#!/usr/bin/env bash
# fsearch.sh — File search utility
# Searches predefined (or user-specified) paths by filename pattern and/or
# text content, then prints filename, timestamps, and matching lines with context.

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────

# Edit this list to add your own default search roots.
PREDEFINED_PATHS=(
    "$HOME/Documents"
    "$HOME/Desktop"
    "$HOME/Downloads"
)

DEFAULT_CONTEXT_LINES=3
SCRIPT_NAME="$(basename "$0")"

# ─── Colour helpers ─────────────────────────────────────────────────────────

_tput() { command -v tput &>/dev/null && tput "$@" 2>/dev/null || true; }
if [[ -t 1 ]]; then
    C_RESET="$(_tput sgr0)"
    C_BOLD="$(_tput bold)"
    C_CYAN="$(_tput setaf 6)"
    C_GREEN="$(_tput setaf 2)"
    C_YELLOW="$(_tput setaf 3)"
    C_RED="$(_tput setaf 1)"
    C_DIM="$(_tput dim)"
else
    C_RESET="" C_BOLD="" C_CYAN="" C_GREEN="" C_YELLOW="" C_RED="" C_DIM=""
fi

# ─── Utility functions ───────────────────────────────────────────────────────

die() {
    printf '%s%s: error: %s%s\n' "$C_RED" "$SCRIPT_NAME" "$*" "$C_RESET" >&2
    exit 1
}

warn() {
    printf '%s%s: warning: %s%s\n' "$C_YELLOW" "$SCRIPT_NAME" "$*" "$C_RESET" >&2
}

info() {
    printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"
}

require_cmd() {
    command -v "$1" &>/dev/null || die "required command '$1' not found in PATH"
}

# ─── Platform-aware stat ─────────────────────────────────────────────────────
# Returns "created: <ts>  modified: <ts>" for a given file.

file_timestamps() {
    local file="$1"
    local created modified
    if stat --version &>/dev/null 2>&1; then
        # GNU stat (Linux)
        modified="$(stat --format='%y' "$file" 2>/dev/null | cut -d'.' -f1)"
        # Birth time is often unavailable on Linux; fall back gracefully
        created="$(stat --format='%w' "$file" 2>/dev/null | cut -d'.' -f1)"
        [[ "$created" == "-" || -z "$created" ]] && created="(unavailable)"
    else
        # BSD stat (macOS)
        modified="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$file" 2>/dev/null)"
        created="$(stat -f '%SB' -t '%Y-%m-%d %H:%M:%S' "$file" 2>/dev/null)"
        [[ -z "$created" ]] && created="(unavailable)"
    fi
    printf 'created: %s  |  modified: %s' "${created:-unknown}" "${modified:-unknown}"
}

# ─── Header printed above each matching file ────────────────────────────────

print_file_header() {
    local file="$1"
    local reason="$2"   # "filename match" | "content match" | "both"
    printf '\n%s%s══╡ %s ╞%s\n' "$C_BOLD" "$C_CYAN" "$file" "$C_RESET"
    printf '  %s%s%s\n'  "$C_DIM" "$(file_timestamps "$file")" "$C_RESET"
    printf '  %smatch: %s%s\n' "$C_GREEN" "$reason" "$C_RESET"
    printf '%s%s%s\n' "$C_CYAN" "$(printf '─%.0s' {1..80})" "$C_RESET"
}

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
${C_BOLD}Usage:${C_RESET}
  $SCRIPT_NAME [OPTIONS]

${C_BOLD}Search options (at least one of -n or -g is required):${C_RESET}
  -n <pattern>   Search file ${C_CYAN}n${C_RESET}ames matching this pattern (grep extended regex)
  -g <pattern>   ${C_CYAN}G${C_RESET}rep file contents for this pattern

${C_BOLD}Path options:${C_RESET}
  -p <path>      Add a search path (repeatable; replaces predefined list on
                 first use — subsequent -p flags add to the custom list)
  -r             Recurse into subdirectories (default: on)
  -R             Disable recursion (top-level files only)

${C_BOLD}Grep options:${C_RESET}
  -i             Case-insensitive matching (applies to both -n and -g)
  -C <num>       Lines of context around content matches (default: $DEFAULT_CONTEXT_LINES)
  -l <ext,...>   Limit content search to these file extensions, e.g. txt,log,py
  -x <ext,...>   Exclude these extensions from content search

${C_BOLD}Output options:${C_RESET}
  -q             Quiet: suppress the per-file header (just show grep output)
  -0             Print only matching file paths, one per line (no content)
  -s             Summary line at the end (file count, match count)

${C_BOLD}Other:${C_RESET}
  -h             Show this help and exit

${C_BOLD}Predefined search paths (used when no -p is given):${C_RESET}
$(printf '  • %s\n' "${PREDEFINED_PATHS[@]}")

${C_BOLD}Examples:${C_RESET}
  # Find all .sh files and grep for 'TODO' inside them
  $SCRIPT_NAME -n '\.sh$' -g 'TODO'

  # Search a custom path, case-insensitive, wider context
  $SCRIPT_NAME -p ~/projects -g 'api_key' -i -C 5

  # List filenames only for anything containing 'password'
  $SCRIPT_NAME -g 'password' -i -0

  # Search only .log and .txt files
  $SCRIPT_NAME -g 'ERROR' -l log,txt
EOF
    exit 0
}

# ─── Argument parsing ────────────────────────────────────────────────────────

NAME_PATTERN=""
GREP_PATTERN=""
CUSTOM_PATHS=()
RECURSE=true
CASE_FLAG=""
CONTEXT_LINES="$DEFAULT_CONTEXT_LINES"
INCLUDE_EXTS=()
EXCLUDE_EXTS=()
QUIET=false
PATHS_ONLY=false
SHOW_SUMMARY=false
CUSTOM_PATHS_SET=false

while getopts ':n:g:p:rRiC:l:x:q0sh' opt; do
    case "$opt" in
        n) NAME_PATTERN="$OPTARG" ;;
        g) GREP_PATTERN="$OPTARG" ;;
        p)
            if [[ "$CUSTOM_PATHS_SET" == false ]]; then
                CUSTOM_PATHS=()
                CUSTOM_PATHS_SET=true
            fi
            CUSTOM_PATHS+=("$OPTARG")
            ;;
        r) RECURSE=true ;;
        R) RECURSE=false ;;
        i) CASE_FLAG="-i" ;;
        C)
            [[ "$OPTARG" =~ ^[0-9]+$ ]] || die "-C requires a non-negative integer"
            CONTEXT_LINES="$OPTARG"
            ;;
        l) IFS=',' read -ra INCLUDE_EXTS <<< "$OPTARG" ;;
        x) IFS=',' read -ra EXCLUDE_EXTS <<< "$OPTARG" ;;
        q) QUIET=true ;;
        0) PATHS_ONLY=true ;;
        s) SHOW_SUMMARY=true ;;
        h) usage ;;
        :) die "option -$OPTARG requires an argument" ;;
        \?) die "unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

# Remaining positional args treated as extra paths
for extra in "$@"; do
    if [[ "$CUSTOM_PATHS_SET" == false ]]; then
        CUSTOM_PATHS=()
        CUSTOM_PATHS_SET=true
    fi
    CUSTOM_PATHS+=("$extra")
done

[[ -z "$NAME_PATTERN" && -z "$GREP_PATTERN" ]] && die "specify at least -n <pattern> or -g <pattern> (see -h)"

# Resolve which paths to search
if [[ ${#CUSTOM_PATHS[@]} -gt 0 ]]; then
    SEARCH_PATHS=("${CUSTOM_PATHS[@]}")
else
    SEARCH_PATHS=("${PREDEFINED_PATHS[@]}")
fi

# ─── Dependency checks ───────────────────────────────────────────────────────

require_cmd find
require_cmd grep

# ─── Validate search paths ───────────────────────────────────────────────────

VALID_PATHS=()
for sp in "${SEARCH_PATHS[@]}"; do
    if [[ ! -e "$sp" ]]; then
        warn "path does not exist, skipping: $sp"
    elif [[ ! -r "$sp" ]]; then
        warn "path is not readable, skipping: $sp"
    else
        VALID_PATHS+=("$sp")
    fi
done
[[ ${#VALID_PATHS[@]} -eq 0 ]] && die "no valid search paths remain"

# ─── Build find command ──────────────────────────────────────────────────────

build_find_cmd() {
    local -a cmd=(find)
    cmd+=("${VALID_PATHS[@]}")

    if [[ "$RECURSE" == false ]]; then
        cmd+=(-maxdepth 1)
    fi

    cmd+=(-type f)

    echo "${cmd[@]}"
}

# ─── Extension filter helpers ────────────────────────────────────────────────

ext_allowed() {
    local file="$1"
    local ext="${file##*.}"
    ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

    if [[ ${#INCLUDE_EXTS[@]} -gt 0 ]]; then
        for e in "${INCLUDE_EXTS[@]}"; do
            local el
            el="$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')"
            [[ "$el" == "$ext" ]] && return 0
        done
        return 1
    fi

    if [[ ${#EXCLUDE_EXTS[@]} -gt 0 ]]; then
        for e in "${EXCLUDE_EXTS[@]}"; do
            local el
            el="$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')"
            [[ "$el" == "$ext" ]] && return 1
        done
    fi

    return 0
}

# ─── Core search logic ───────────────────────────────────────────────────────

FILE_COUNT=0
MATCH_COUNT=0

run_search() {
    local -a find_cmd
    read -ra find_cmd <<< "$(build_find_cmd)"

    # Collect all candidate files (safely handles spaces in names via NUL)
    while IFS= read -r -d '' file; do
        local name_hit=false
        local content_hit=false

        # ── Filename match ──────────────────────────────────────────────────
        if [[ -n "$NAME_PATTERN" ]]; then
            local basename
            basename="$(basename "$file")"
            if grep -qE $CASE_FLAG -- "$NAME_PATTERN" <<< "$basename" 2>/dev/null; then
                name_hit=true
            fi
        fi

        # ── Content match ───────────────────────────────────────────────────
        local grep_output=""
        if [[ -n "$GREP_PATTERN" ]]; then
            # Skip if extension filter rejects this file
            if ! ext_allowed "$file"; then
                :
            elif [[ ! -r "$file" ]]; then
                warn "cannot read file: $file"
            elif file "$file" 2>/dev/null | grep -qiE '\bbinary\b|ELF |Mach-O |compiled|object code|archive|compressed|image data|audio|video|PDF'; then
                :  # skip binary files silently
            else
                grep_output="$(grep -nE $CASE_FLAG -C "$CONTEXT_LINES" -- "$GREP_PATTERN" "$file" 2>/dev/null || true)"
                [[ -n "$grep_output" ]] && content_hit=true
            fi
        fi

        # ── Output ──────────────────────────────────────────────────────────
        if [[ "$name_hit" == true || "$content_hit" == true ]]; then
            (( FILE_COUNT++ ))

            if [[ "$PATHS_ONLY" == true ]]; then
                printf '%s\n' "$file"
                continue
            fi

            local reason=""
            if   [[ "$name_hit" == true && "$content_hit" == true ]]; then reason="filename + content"
            elif [[ "$name_hit" == true ]];                             then reason="filename"
            else                                                             reason="content"
            fi

            [[ "$QUIET" == false ]] && print_file_header "$file" "$reason"

            if [[ -n "$grep_output" ]]; then
                # Count individual match lines (not context lines)
                local hits
                hits="$(grep -cE $CASE_FLAG -- "$GREP_PATTERN" "$file" 2>/dev/null || true)"
                (( MATCH_COUNT += hits ))

                # Colour the match lines
                printf '%s\n' "$grep_output" | while IFS= read -r line; do
                    if printf '%s\n' "$line" | grep -qE $CASE_FLAG -- "$GREP_PATTERN" 2>/dev/null; then
                        printf '%s%s%s\n' "$C_YELLOW" "$line" "$C_RESET"
                    else
                        printf '%s\n' "$line"
                    fi
                done
            fi
        fi

    done < <("${find_cmd[@]}" -print0 2>/dev/null)
}

# ─── Run ─────────────────────────────────────────────────────────────────────

info "Searching in: ${VALID_PATHS[*]}"
[[ -n "$NAME_PATTERN" ]] && info "Filename pattern : $NAME_PATTERN"
[[ -n "$GREP_PATTERN" ]] && info "Content pattern  : $GREP_PATTERN"
[[ -n "$CASE_FLAG"    ]] && info "Case-insensitive : yes"
printf '\n'

run_search

# ─── Summary ─────────────────────────────────────────────────────────────────

if [[ "$PATHS_ONLY" == false ]]; then
    printf '\n%s%s%s\n' "$C_CYAN" "$(printf '═%.0s' {1..80})" "$C_RESET"
fi

if [[ "$SHOW_SUMMARY" == true || "$FILE_COUNT" -eq 0 ]]; then
    if [[ "$FILE_COUNT" -eq 0 ]]; then
        printf '%sNo matches found.%s\n' "$C_YELLOW" "$C_RESET"
    else
        printf '%s%d file(s) matched' "$C_GREEN" "$FILE_COUNT"
        [[ -n "$GREP_PATTERN" ]] && printf ', %d content hit(s)' "$MATCH_COUNT"
        printf '.%s\n' "$C_RESET"
    fi
fi
