#!/usr/bin/env bash
# ============================================================================
#
#  FSEARCH — File Search Utility
#
#  File:        fsearch.sh
#  Version:     2.1.0
#  Author:      Generated with Claude Code
#  License:     MIT
#  Requires:    bash 3.2+, find, grep, file, stat
#
#  Description:
#    Search files by name pattern and/or content across configurable
#    directory trees.  Supports persistent configuration via CLI
#    subcommands, smart directory exclusions, multiple output formats,
#    and inline match highlighting.
#
#  Configuration:
#    All defaults are stored in ~/.config/fsearch/config.conf and managed
#    via `fsearch config get|set|reset|path-add|path-remove`.  The config
#    file is never required — built-in defaults apply until overridden.
#
#  Exit Codes:
#    0 - Success (matches found, or config command completed)
#    1 - Error (invalid arguments, no valid paths, etc.)
#    2 - No matches found
#
# ============================================================================

set -euo pipefail

# ─── Version ────────────────────────────────────────────────────────────────

FSEARCH_VERSION="2.1.0"

# ─── Configuration system ──────────────────────────────────────────────────

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fsearch"
CONFIG_FILE="${CONFIG_DIR}/config.conf"

# Ordered list of all known config keys (used by config show)
_CONFIG_KEYS="DEFAULT_PATHS
CONTEXT_LINES
CASE_INSENSITIVE
EXCLUDE_DIRS
EXCLUDE_DIRS_ENABLED
MAX_FILE_SIZE
MAX_RESULTS
COLOR
OUTPUT_FORMAT
SHOW_FILE_SIZE
SHOW_SUMMARY
SHOW_PROGRESS"

# Returns the data type for a config key
_config_key_type() {
    case "${1}" in
        DEFAULT_PATHS|EXCLUDE_DIRS)
            echo "string" ;;
        CONTEXT_LINES|MAX_RESULTS)
            echo "int" ;;
        CASE_INSENSITIVE|EXCLUDE_DIRS_ENABLED|COLOR|SHOW_FILE_SIZE|SHOW_SUMMARY|SHOW_PROGRESS)
            echo "bool" ;;
        MAX_FILE_SIZE|OUTPUT_FORMAT)
            echo "string" ;;
        *)
            echo "unknown" ;;
    esac
}

# Returns the factory default value for a config key
_config_default() {
    case "${1}" in
        DEFAULT_PATHS)        echo "$HOME/Documents $HOME/Desktop $HOME/Downloads" ;;
        CONTEXT_LINES)        echo "3" ;;
        CASE_INSENSITIVE)     echo "false" ;;
        EXCLUDE_DIRS)         echo ".git node_modules __pycache__ .venv vendor .DS_Store" ;;
        EXCLUDE_DIRS_ENABLED) echo "true" ;;
        MAX_FILE_SIZE)        echo "10M" ;;
        MAX_RESULTS)          echo "0" ;;
        COLOR)                echo "true" ;;
        OUTPUT_FORMAT)        echo "pretty" ;;
        SHOW_FILE_SIZE)       echo "false" ;;
        SHOW_SUMMARY)         echo "true" ;;
        SHOW_PROGRESS)        echo "true" ;;
        *)                    echo "" ;;
    esac
}

# Read a config value from the config file; returns default if key is absent
_config_read() {
    local key="$1"
    local default
    default="$(_config_default "$key")"
    if [[ -f "$CONFIG_FILE" ]]; then
        local val
        val="$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d= -f2-)"
        if [[ -n "$val" ]]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

# Validate a proposed value for a key; print error and return 1 on failure
_config_validate() {
    local key="$1" value="$2"
    local ktype
    ktype="$(_config_key_type "$key")"
    case "$ktype" in
        unknown)
            printf 'Unknown config key: %s\nRun '\''fsearch config'\'' to see all valid keys.\n' "$key" >&2
            return 1 ;;
        bool)
            if [[ "$value" != "true" && "$value" != "false" ]]; then
                printf '%s requires true or false (got: '\''%s'\'')\n' "$key" "$value" >&2
                return 1
            fi ;;
        int)
            if ! printf '%s' "$value" | grep -qE '^[0-9]+$'; then
                printf '%s requires a non-negative integer (got: '\''%s'\'')\n' "$key" "$value" >&2
                return 1
            fi ;;
        string)
            if [[ "$key" == "OUTPUT_FORMAT" ]]; then
                case "$value" in
                    pretty|plain|json) : ;;
                    *) printf 'OUTPUT_FORMAT requires pretty, plain, or json (got: '\''%s'\'')\n' "$value" >&2
                       return 1 ;;
                esac
            fi
            if [[ "$key" == "MAX_FILE_SIZE" ]]; then
                if ! printf '%s' "$value" | grep -qE '^[0-9]+[KMG]?$'; then
                    printf 'MAX_FILE_SIZE requires a size like 10M, 500K, or 1G (got: '\''%s'\'')\n' "$value" >&2
                    return 1
                fi
            fi ;;
    esac
    return 0
}

# Write KEY=VALUE into config file (atomic: temp + mv)
_config_write() {
    local key="$1" new_value="$2"

    # Ensure config directory exists
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
    fi

    # If config file doesn't exist, create it with just this key
    if [[ ! -f "$CONFIG_FILE" ]]; then
        printf '# fsearch configuration\n# Managed via: fsearch config set KEY VALUE\n\n%s=%s\n' \
            "$key" "$new_value" > "$CONFIG_FILE"
        return
    fi

    local tmp found=0
    tmp="$(mktemp)" || { printf 'Cannot create temp file\n' >&2; return 1; }

    while IFS= read -r line; do
        if [[ "$line" == "${key}="* ]]; then
            printf '%s\n' "${key}=${new_value}" >> "$tmp"
            found=1
        else
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$CONFIG_FILE"

    if [[ $found -eq 0 ]]; then
        printf '%s\n' "${key}=${new_value}" >> "$tmp"
    fi

    mv "$tmp" "$CONFIG_FILE"
}

# ─── Config CLI subcommand handlers ────────────────────────────────────────

_config_show() {
    printf 'Configuration  %s\n' "$CONFIG_FILE"
    printf '────────────────────────────────────────────────────────────────\n'

    local key ktype value default
    for key in ${_CONFIG_KEYS}; do
        ktype="$(_config_key_type "$key")"
        default="$(_config_default "$key")"
        value="$(_config_read "$key")"

        local marker=""
        if [[ "$value" != "$default" ]]; then
            marker=" *"
        fi

        local display_value="${value:-<empty>}"
        if [[ ${#display_value} -gt 40 ]]; then
            display_value="${display_value:0:37}..."
        fi

        printf '  %-25s %-40s [%s]%s\n' "$key" "$display_value" "$ktype" "$marker"
    done

    printf '\n  * = differs from factory default\n'
    printf '  To change:  fsearch config set KEY VALUE\n'
    printf '  To reset:   fsearch config reset KEY\n'
}

_config_get() {
    local key="${1:-}"
    if [[ -z "$key" ]]; then
        printf 'Usage: fsearch config get KEY\n' >&2; return 1
    fi

    local ktype
    ktype="$(_config_key_type "$key")"
    if [[ "$ktype" == "unknown" ]]; then
        printf 'Unknown key: %s\nRun '\''fsearch config'\'' to see all valid keys.\n' "$key" >&2
        return 1
    fi

    local default value
    default="$(_config_default "$key")"
    value="$(_config_read "$key")"

    printf '%s=%s\n' "$key" "${value:-}"
    printf 'type: %s  |  default: %s\n' "$ktype" "${default:-<empty>}"
}

_config_set() {
    local key="${1:-}" new_value="${2:-}"
    if [[ -z "$key" ]]; then
        printf 'Usage: fsearch config set KEY VALUE\n' >&2; return 1
    fi

    _config_validate "$key" "$new_value" || return 1

    local old_value default
    default="$(_config_default "$key")"
    old_value="$(_config_read "$key")"

    _config_write "$key" "$new_value"

    printf '  %s: %s -> %s\n' "$key" "${old_value:-<empty>}" "${new_value:-<empty>}"
    printf '  Saved. Takes effect immediately.\n'
}

_config_reset() {
    local key="${1:-}"
    if [[ -z "$key" ]]; then
        printf 'Usage: fsearch config reset KEY\n' >&2; return 1
    fi

    local ktype
    ktype="$(_config_key_type "$key")"
    if [[ "$ktype" == "unknown" ]]; then
        printf 'Unknown key: %s\n' "$key" >&2; return 1
    fi

    local default
    default="$(_config_default "$key")"
    _config_set "$key" "$default"
}

_config_path_add() {
    local new_path="${1:-}"
    if [[ -z "$new_path" ]]; then
        printf 'Usage: fsearch config path-add PATH\n' >&2; return 1
    fi

    local current
    current="$(_config_read "DEFAULT_PATHS")"

    # Check for duplicates
    local p
    for p in $current; do
        if [[ "$p" == "$new_path" ]]; then
            printf '  Path already in DEFAULT_PATHS: %s\n' "$new_path"
            return 0
        fi
    done

    if [[ -n "$current" ]]; then
        _config_write "DEFAULT_PATHS" "${current} ${new_path}"
    else
        _config_write "DEFAULT_PATHS" "$new_path"
    fi
    printf '  Added: %s\n' "$new_path"
}

_config_path_remove() {
    local rm_path="${1:-}"
    if [[ -z "$rm_path" ]]; then
        printf 'Usage: fsearch config path-remove PATH\n' >&2; return 1
    fi

    local current new_paths="" found=false
    current="$(_config_read "DEFAULT_PATHS")"

    local p
    for p in $current; do
        if [[ "$p" == "$rm_path" ]]; then
            found=true
        else
            if [[ -n "$new_paths" ]]; then
                new_paths="${new_paths} ${p}"
            else
                new_paths="$p"
            fi
        fi
    done

    if [[ "$found" == false ]]; then
        printf '  Path not found in DEFAULT_PATHS: %s\n' "$rm_path" >&2
        return 1
    fi

    _config_write "DEFAULT_PATHS" "$new_paths"
    printf '  Removed: %s\n' "$rm_path"
}

cmd_config() {
    local subcmd="${1:-show}"
    shift 2>/dev/null || true
    case "$subcmd" in
        show|"")     _config_show ;;
        get)         _config_get "$@" ;;
        set)         _config_set "$@" ;;
        reset)       _config_reset "$@" ;;
        path-add)    _config_path_add "$@" ;;
        path-remove) _config_path_remove "$@" ;;
        path)        printf '%s\n' "$CONFIG_FILE" ;;
        *)
            printf 'Unknown config subcommand: %s\n' "$subcmd" >&2
            printf 'Usage: fsearch config [show|get KEY|set KEY VALUE|reset KEY|path-add PATH|path-remove PATH|path]\n' >&2
            return 1 ;;
    esac
}

# ─── Colour helpers ─────────────────────────────────────────────────────────

setup_colors() {
    local use_color="$1"
    if [[ "$use_color" == "true" && -t 1 ]]; then
        _tput() { command -v tput &>/dev/null && tput "$@" 2>/dev/null || true; }
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
}

# ─── Utility functions ──────────────────────────────────────────────────────

SCRIPT_NAME="$(basename "$0")"

die() {
    printf '%s: error: %s\n' "$SCRIPT_NAME" "$*" >&2
    exit 1
}

warn() {
    printf '%s: warning: %s\n' "$SCRIPT_NAME" "$*" >&2
}

info() {
    printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"
}

require_cmd() {
    command -v "$1" &>/dev/null || die "required command '$1' not found in PATH"
}

# Platform-aware file timestamps
# Returns "created: <ts>  |  modified: <ts>"
file_timestamps() {
    local file="$1"
    local created modified
    if stat --version &>/dev/null 2>&1; then
        # GNU stat (Linux)
        modified="$(stat --format='%y' "$file" 2>/dev/null | cut -d'.' -f1)"
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

# Human-readable file size
file_size_human() {
    local file="$1"
    local bytes
    if stat --version &>/dev/null 2>&1; then
        bytes="$(stat --format='%s' "$file" 2>/dev/null)"
    else
        bytes="$(stat -f '%z' "$file" 2>/dev/null)"
    fi
    bytes="${bytes:-0}"

    if [[ $bytes -ge 1073741824 ]]; then
        printf '%s.%sG' "$((bytes / 1073741824))" "$(( (bytes % 1073741824) * 10 / 1073741824 ))"
    elif [[ $bytes -ge 1048576 ]]; then
        printf '%s.%sM' "$((bytes / 1048576))" "$(( (bytes % 1048576) * 10 / 1048576 ))"
    elif [[ $bytes -ge 1024 ]]; then
        printf '%sK' "$((bytes / 1024))"
    else
        printf '%sB' "$bytes"
    fi
}

# Get raw file size in bytes
file_size_bytes() {
    local file="$1"
    if stat --version &>/dev/null 2>&1; then
        stat --format='%s' "$file" 2>/dev/null
    else
        stat -f '%z' "$file" 2>/dev/null
    fi
}

# Parse a size string like "10M" into bytes
parse_size() {
    local size="$1"
    local num unit
    num="$(printf '%s' "$size" | sed 's/[^0-9]//g')"
    unit="$(printf '%s' "$size" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')"

    case "$unit" in
        G) echo $(( num * 1073741824 )) ;;
        M) echo $(( num * 1048576 )) ;;
        K) echo $(( num * 1024 )) ;;
        *)  echo "$num" ;;
    esac
}

# Lowercase helper (bash 3.2 safe)
_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# ─── Usage ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
${C_BOLD}fsearch${C_RESET} v${FSEARCH_VERSION} — File search utility

${C_BOLD}Usage:${C_RESET}
  $SCRIPT_NAME [OPTIONS] [PATHS...]
  $SCRIPT_NAME config [SUBCOMMAND]

${C_BOLD}Search options (at least one of -n or -g is required):${C_RESET}
  -n <pattern>      Search file ${C_CYAN}n${C_RESET}ames matching this pattern (extended regex)
  -g <pattern>      ${C_CYAN}G${C_RESET}rep file contents for this pattern

${C_BOLD}Path options:${C_RESET}
  -p <path>         Add a search path (repeatable; overrides configured defaults)

${C_BOLD}Filter options:${C_RESET}
  -i                Case-insensitive matching (both -n and -g)
  -d <num>          Max directory depth (e.g. -d 1 for top-level only)
  -l <ext,...>      Limit content search to these file extensions
  -x <ext,...>      Exclude these extensions from content search
  -E                Disable default directory exclusions (.git, node_modules, etc.)
  --newer <DATE>    Only files modified after DATE (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
  --older <DATE>    Only files modified before DATE
  -m <num>          Stop after this many file matches

${C_BOLD}Output options:${C_RESET}
  -C <num>          Lines of context around content matches (default: from config)
  -q                Quiet: suppress the per-file header
  -0                Print only matching file paths, one per line
  --format <fmt>    Output format: pretty (default), plain, json
  --size            Show file size in output
  --no-color        Disable coloured output
  --no-progress     Disable progress indicator while searching

${C_BOLD}Config subcommands:${C_RESET}
  config             Show all settings with current values
  config get KEY     Show one key's value
  config set KEY V   Set a config key
  config reset KEY   Reset key to factory default
  config path-add P  Add a path to DEFAULT_PATHS
  config path-remove P  Remove a path from DEFAULT_PATHS
  config path        Show config file location

${C_BOLD}Other:${C_RESET}
  --version         Print version and exit
  -h, --help        Show this help and exit

${C_BOLD}Default search paths (configurable via 'fsearch config'):${C_RESET}
$(printf '  • %s\n' $(_config_read DEFAULT_PATHS))

${C_BOLD}Default excluded directories:${C_RESET}
$(printf '  • %s\n' $(_config_read EXCLUDE_DIRS))

${C_BOLD}Examples:${C_RESET}
  # Find all .sh files and grep for 'TODO' inside them
  $SCRIPT_NAME -n '\.sh$' -g 'TODO'

  # Search a custom path, case-insensitive, wider context
  $SCRIPT_NAME -p ~/projects -g 'api_key' -i -C 5

  # List filenames only for anything containing 'password'
  $SCRIPT_NAME -g 'password' -i -0

  # Search only .log and .txt files, limit to 10 results
  $SCRIPT_NAME -g 'ERROR' -l log,txt -m 10

  # JSON output for piping to jq
  $SCRIPT_NAME -g 'TODO' --format json | jq '.file'

  # Set default search paths
  $SCRIPT_NAME config set DEFAULT_PATHS "\$HOME/projects \$HOME/notes"
EOF
    exit 0
}

# ─── Long option pre-processor ──────────────────────────────────────────────
# Converts long options to short flags or sets variables directly, since
# bash's getopts does not support long options.

OPT_NEWER=""
OPT_OLDER=""
OPT_FORMAT=""
OPT_NO_COLOR=false
OPT_SHOW_SIZE=false
OPT_NO_PROGRESS=false

preprocess_args() {
    PROCESSED_ARGS=()
    # Subcommand: only detect 'config' as the FIRST argument
    if [[ $# -gt 0 && "$1" == "config" ]]; then
        shift
        cmd_config "$@"
        exit $?
    fi
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                printf 'fsearch %s\n' "$FSEARCH_VERSION"
                exit 0
                ;;
            --help)     PROCESSED_ARGS+=("-h") ;;
            --format)
                [[ $# -lt 2 ]] && die "--format requires an argument"
                OPT_FORMAT="$2"; shift ;;
            --format=*)
                OPT_FORMAT="${1#*=}" ;;
            --newer)
                [[ $# -lt 2 ]] && die "--newer requires a date argument"
                OPT_NEWER="$2"; shift ;;
            --newer=*)
                OPT_NEWER="${1#*=}" ;;
            --older)
                [[ $# -lt 2 ]] && die "--older requires a date argument"
                OPT_OLDER="$2"; shift ;;
            --older=*)
                OPT_OLDER="${1#*=}" ;;
            --no-color)    OPT_NO_COLOR=true ;;
            --size)        OPT_SHOW_SIZE=true ;;
            --no-progress) OPT_NO_PROGRESS=true ;;
            --)         PROCESSED_ARGS+=("$@"); break ;;
            *)          PROCESSED_ARGS+=("$1") ;;
        esac
        shift
    done
}

# ─── Argument parsing ──────────────────────────────────────────────────────

parse_args() {
    # Load config defaults
    local cfg_context cfg_case cfg_format cfg_color cfg_size cfg_summary cfg_progress
    cfg_context="$(_config_read CONTEXT_LINES)"
    cfg_case="$(_config_read CASE_INSENSITIVE)"
    cfg_color="$(_config_read COLOR)"
    cfg_format="$(_config_read OUTPUT_FORMAT)"
    cfg_size="$(_config_read SHOW_FILE_SIZE)"
    cfg_summary="$(_config_read SHOW_SUMMARY)"
    cfg_progress="$(_config_read SHOW_PROGRESS)"

    # Apply config defaults
    NAME_PATTERN=""
    GREP_PATTERN=""
    CUSTOM_PATHS=()
    CUSTOM_PATHS_SET=false
    CASE_FLAG=""
    CONTEXT_LINES="$cfg_context"
    INCLUDE_EXTS=()
    EXCLUDE_EXTS=()
    QUIET=false
    PATHS_ONLY=false
    MAX_DEPTH=""
    MAX_RESULTS="$(_config_read MAX_RESULTS)"
    DIR_EXCLUSIONS_ENABLED="$(_config_read EXCLUDE_DIRS_ENABLED)"
    OUTPUT_FORMAT="$cfg_format"
    SHOW_FILE_SIZE="$cfg_size"
    SHOW_SUMMARY="$cfg_summary"

    [[ "$cfg_case" == "true" ]] && CASE_FLAG="-i"
    [[ "$OPT_NO_COLOR" == "true" ]] && cfg_color="false"
    [[ -n "$OPT_FORMAT" ]] && OUTPUT_FORMAT="$OPT_FORMAT"
    [[ "$OPT_SHOW_SIZE" == "true" ]] && SHOW_FILE_SIZE="true"

    # Progress: on by default; disabled by --no-progress flag or config
    _PROGRESS_ENABLED="$cfg_progress"
    [[ "$OPT_NO_PROGRESS" == "true" ]] && _PROGRESS_ENABLED="false"

    # Validate output format
    case "$OUTPUT_FORMAT" in
        pretty|plain|json) : ;;
        *) die "invalid output format: $OUTPUT_FORMAT (use pretty, plain, or json)" ;;
    esac

    # Force no-color for non-pretty formats
    if [[ "$OUTPUT_FORMAT" != "pretty" ]]; then
        cfg_color="false"
    fi

    setup_colors "$cfg_color"

    # Parse short options
    set -- "${PROCESSED_ARGS[@]+"${PROCESSED_ARGS[@]}"}"

    while getopts ':n:g:p:id:C:l:x:q0m:Eh' opt; do
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
            i) CASE_FLAG="-i" ;;
            d)
                printf '%s' "$OPTARG" | grep -qE '^[0-9]+$' || die "-d requires a positive integer"
                MAX_DEPTH="$OPTARG"
                ;;
            C)
                printf '%s' "$OPTARG" | grep -qE '^[0-9]+$' || die "-C requires a non-negative integer"
                CONTEXT_LINES="$OPTARG"
                ;;
            l) IFS=',' read -ra INCLUDE_EXTS <<< "$OPTARG" ;;
            x) IFS=',' read -ra EXCLUDE_EXTS <<< "$OPTARG" ;;
            q) QUIET=true ;;
            0) PATHS_ONLY=true ;;
            m)
                printf '%s' "$OPTARG" | grep -qE '^[0-9]+$' || die "-m requires a non-negative integer"
                MAX_RESULTS="$OPTARG"
                ;;
            E) DIR_EXCLUSIONS_ENABLED="false" ;;
            h) usage ;;
            :) die "option -$OPTARG requires an argument" ;;
            \?) die "unknown option: -$OPTARG (see --help)" ;;
        esac
    done
    shift $((OPTIND - 1))

    # Remaining positional args: if no -n/-g given, first bare word is the
    # search term (content grep); the rest are paths.  If -n/-g already set,
    # all remaining args are paths (existing behaviour).
    for extra in "$@"; do
        if [[ -z "$NAME_PATTERN" && -z "$GREP_PATTERN" && ! "$extra" =~ ^[/~\.] ]]; then
            # Looks like a search term, not a path
            GREP_PATTERN="$extra"
        else
            if [[ "$CUSTOM_PATHS_SET" == false ]]; then
                CUSTOM_PATHS=()
                CUSTOM_PATHS_SET=true
            fi
            CUSTOM_PATHS+=("$extra")
        fi
    done

    if [[ -z "$NAME_PATTERN" && -z "$GREP_PATTERN" ]]; then
        usage
    fi

    # Resolve search paths
    if [[ ${#CUSTOM_PATHS[@]} -gt 0 ]]; then
        SEARCH_PATHS=("${CUSTOM_PATHS[@]}")
    else
        local cfg_paths
        cfg_paths="$(_config_read DEFAULT_PATHS)"
        SEARCH_PATHS=()
        for p in $cfg_paths; do
            SEARCH_PATHS+=("$p")
        done
    fi
}

# ─── Find command builder ──────────────────────────────────────────────────
# Builds the find command array directly in FIND_CMD (global), avoiding the
# echo/read pattern that breaks on paths with spaces.

FIND_CMD=()

build_find_cmd() {
    FIND_CMD=(find)

    # Add all valid search paths
    local sp
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

    FIND_CMD+=("${VALID_PATHS[@]}")

    # Max depth
    if [[ -n "$MAX_DEPTH" ]]; then
        FIND_CMD+=(-maxdepth "$MAX_DEPTH")
    fi

    # Directory exclusions (prune before descending — much faster)
    if [[ "$DIR_EXCLUSIONS_ENABLED" == "true" ]]; then
        local exclude_dirs
        exclude_dirs="$(_config_read EXCLUDE_DIRS)"
        local first=true
        local dir
        for dir in $exclude_dirs; do
            if [[ "$first" == true ]]; then
                FIND_CMD+=(\( -path "*/${dir}" -prune)
                first=false
            else
                FIND_CMD+=(-o -path "*/${dir}" -prune)
            fi
        done
        if [[ "$first" == false ]]; then
            FIND_CMD+=(\) -o)
        fi
    fi

    FIND_CMD+=(-type f)

    # Date filters
    if [[ -n "$OPT_NEWER" ]]; then
        if find /dev/null -newermt "2000-01-01" -print &>/dev/null; then
            # GNU find supports -newermt
            FIND_CMD+=(-newermt "$OPT_NEWER")
        else
            # BSD find: create reference file with touch -t
            local ref_file
            ref_file="$(mktemp)"
            # Convert YYYY-MM-DD [HH:MM:SS] to touch format YYYYMMDDHHmm.SS
            local ts
            ts="$(printf '%s' "$OPT_NEWER" | sed 's/[-: ]//g')"
            # Pad to 14 chars (YYYYMMDDHHmmSS)
            while [[ ${#ts} -lt 14 ]]; do ts="${ts}0"; done
            touch -t "${ts:0:12}.${ts:12:2}" "$ref_file" 2>/dev/null || {
                rm -f "$ref_file"
                die "invalid date format for --newer: $OPT_NEWER (use YYYY-MM-DD)"
            }
            FIND_CMD+=(-newer "$ref_file")
            # Store for cleanup
            _NEWER_REF="$ref_file"
        fi
    fi

    if [[ -n "$OPT_OLDER" ]]; then
        if find /dev/null -newermt "2000-01-01" -print &>/dev/null; then
            FIND_CMD+=(\! -newermt "$OPT_OLDER")
        else
            local ref_file
            ref_file="$(mktemp)"
            local ts
            ts="$(printf '%s' "$OPT_OLDER" | sed 's/[-: ]//g')"
            while [[ ${#ts} -lt 14 ]]; do ts="${ts}0"; done
            touch -t "${ts:0:12}.${ts:12:2}" "$ref_file" 2>/dev/null || {
                rm -f "$ref_file"
                die "invalid date format for --older: $OPT_OLDER (use YYYY-MM-DD)"
            }
            FIND_CMD+=(\! -newer "$ref_file")
            _OLDER_REF="$ref_file"
        fi
    fi

    FIND_CMD+=(-print0)
}

# ─── Extension filter ──────────────────────────────────────────────────────

ext_allowed() {
    local file="$1"
    local ext="${file##*.}"
    ext="$(_lower "$ext")"

    if [[ ${#INCLUDE_EXTS[@]} -gt 0 ]]; then
        local e
        for e in "${INCLUDE_EXTS[@]}"; do
            [[ "$(_lower "$e")" == "$ext" ]] && return 0
        done
        return 1
    fi

    if [[ ${#EXCLUDE_EXTS[@]} -gt 0 ]]; then
        local e
        for e in "${EXCLUDE_EXTS[@]}"; do
            [[ "$(_lower "$e")" == "$ext" ]] && return 1
        done
    fi

    return 0
}

# ─── Output formatters ─────────────────────────────────────────────────────

# Pretty: coloured header with timestamps, match type, grep output
print_file_header() {
    local file="$1"
    local reason="$2"
    printf '\n%s%s══╡ %s ╞%s\n' "$C_BOLD" "$C_CYAN" "$file" "$C_RESET"
    local ts_line
    ts_line="$(file_timestamps "$file")"
    if [[ "$SHOW_FILE_SIZE" == "true" ]]; then
        ts_line="${ts_line}  |  size: $(file_size_human "$file")"
    fi
    printf '  %s%s%s\n' "$C_DIM" "$ts_line" "$C_RESET"
    printf '  %smatch: %s%s\n' "$C_GREEN" "$reason" "$C_RESET"
    printf '%s%s%s\n' "$C_CYAN" "$(printf '─%.0s' {1..80})" "$C_RESET"
}

# JSON: one JSONL object per matching file
emit_result_json() {
    local file="$1"
    local reason="$2"
    local grep_output="$3"

    # Escape for JSON
    local esc_file esc_reason
    esc_file="$(printf '%s' "$file" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    esc_reason="$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')"

    local created modified
    if stat --version &>/dev/null 2>&1; then
        modified="$(stat --format='%y' "$file" 2>/dev/null | cut -d'.' -f1)"
        created="$(stat --format='%w' "$file" 2>/dev/null | cut -d'.' -f1)"
        [[ "$created" == "-" ]] && created=""
    else
        modified="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$file" 2>/dev/null)"
        created="$(stat -f '%SB' -t '%Y-%m-%d %H:%M:%S' "$file" 2>/dev/null)"
    fi

    local size_bytes
    size_bytes="$(file_size_bytes "$file")"

    # Build matches array from grep output
    local matches="[]"
    if [[ -n "$grep_output" ]]; then
        matches="["
        local first_match=true
        while IFS= read -r line; do
            # Match lines from grep -n have format: NUM:text
            # Context lines have format: NUM-text
            # Separator lines are --
            [[ "$line" == "--" ]] && continue
            local line_num="" line_text=""
            if printf '%s' "$line" | grep -qE '^[0-9]+[:-]'; then
                line_num="$(printf '%s' "$line" | sed 's/^\([0-9]*\)[:-].*/\1/')"
                line_text="$(printf '%s' "$line" | sed 's/^[0-9]*[:-]//')"
            else
                line_text="$line"
            fi
            local esc_text
            esc_text="$(printf '%s' "$line_text" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')"

            if [[ "$first_match" == true ]]; then
                first_match=false
            else
                matches="${matches},"
            fi

            if [[ -n "$line_num" ]]; then
                matches="${matches}{\"line\":${line_num},\"text\":\"${esc_text}\"}"
            else
                matches="${matches}{\"text\":\"${esc_text}\"}"
            fi
        done <<< "$grep_output"
        matches="${matches}]"
    fi

    printf '{"file":"%s","match_type":"%s","created":"%s","modified":"%s","size":%s,"matches":%s}\n' \
        "$esc_file" "$esc_reason" "${created:-}" "${modified:-}" "${size_bytes:-0}" "$matches"
}

# Plain: no colour, no decoration, simple grep-style output
emit_result_plain() {
    local file="$1"
    local reason="$2"
    local grep_output="$3"

    printf '%s %s [%s]' "---" "$file" "$reason"
    if [[ "$SHOW_FILE_SIZE" == "true" ]]; then
        printf ' [%s]' "$(file_size_human "$file")"
    fi
    printf '\n'

    if [[ -n "$grep_output" ]]; then
        printf '%s\n' "$grep_output"
    fi
}

# ─── Progress indicator ─────────────────────────────────────────────────────
# Writes a live progress line to stderr (does not touch stdout).
# Uses \r to overwrite itself so it does not appear in captured output.
# Only active when stderr is an interactive terminal.

_PROGRESS_ENABLED="false"   # set in parse_args after loading config
_PROGRESS_ACTIVE=false       # true once a progress line has been written
_PROGRESS_SCANNED=0          # total files examined (not just matches)
_SPINNER_CHARS="/-\\|"
_SPINNER_IDX=0

# Call once per file examined (inside run_search loop).
# Refreshes the display every 25 files to keep overhead negligible.
_progress_update() {
    [[ "$_PROGRESS_ENABLED" != "true" ]] && return
    [[ ! -t 2 ]] && return

    (( _PROGRESS_SCANNED++ )) || true
    (( _PROGRESS_SCANNED % 25 != 0 )) && return

    (( _SPINNER_IDX = (_SPINNER_IDX + 1) % 4 )) || true
    local spin="${_SPINNER_CHARS:$_SPINNER_IDX:1}"

    local term_width
    term_width="$(tput cols 2>/dev/null || printf '80')"

    local msg
    msg="$(printf ' %s  %d scanned  %d matched' "$spin" "$_PROGRESS_SCANNED" "$FILE_COUNT")"

    printf '\r%-*s' "$term_width" "$msg" >&2
    _PROGRESS_ACTIVE=true
}

# Erase the progress line before printing a result or summary.
_progress_clear() {
    [[ "$_PROGRESS_ACTIVE" != "true" ]] && return
    [[ ! -t 2 ]] && return
    local term_width
    term_width="$(tput cols 2>/dev/null || printf '80')"
    printf '\r%*s\r' "$term_width" "" >&2
    _PROGRESS_ACTIVE=false
}

# ─── Core search logic ─────────────────────────────────────────────────────

FILE_COUNT=0
MATCH_COUNT=0
MAX_FILE_SIZE_BYTES=0

check_filename_match() {
    local basename="$1"
    if [[ -n "$NAME_PATTERN" ]]; then
        if grep -qE $CASE_FLAG -- "$NAME_PATTERN" <<< "$basename" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

check_content_match() {
    local file="$1"

    # Extension filter
    if ! ext_allowed "$file"; then
        return 1
    fi

    # Readability check
    if [[ ! -r "$file" ]]; then
        warn "cannot read file: $file"
        return 1
    fi

    # Binary file check
    if file "$file" 2>/dev/null | grep -qiE '\bbinary\b|ELF |Mach-O |compiled|object code|archive|compressed|image data|audio|video|PDF'; then
        return 1
    fi

    # File size check
    if [[ $MAX_FILE_SIZE_BYTES -gt 0 ]]; then
        local fsize
        fsize="$(file_size_bytes "$file")"
        if [[ ${fsize:-0} -gt $MAX_FILE_SIZE_BYTES ]]; then
            return 1
        fi
    fi

    # Run grep (--color=always for inline match highlighting in pretty mode)
    local color_flag=""
    [[ "$OUTPUT_FORMAT" == "pretty" ]] && color_flag="--color=always"
    local output
    output="$(grep -nE $CASE_FLAG $color_flag -C "$CONTEXT_LINES" -- "$GREP_PATTERN" "$file" 2>/dev/null || true)"
    if [[ -n "$output" ]]; then
        printf '%s' "$output"
        return 0
    fi

    return 1
}

emit_result() {
    local file="$1"
    local reason="$2"
    local grep_output="$3"

    # Clear progress line before printing so it doesn't interleave with results
    _progress_clear

    case "$OUTPUT_FORMAT" in
        pretty)
            if [[ "$PATHS_ONLY" == true ]]; then
                printf '%s\n' "$file"
                return
            fi

            [[ "$QUIET" == false ]] && print_file_header "$file" "$reason"

            if [[ -n "$grep_output" ]]; then
                # Count individual match lines
                local hits
                hits="$(grep -cE $CASE_FLAG -- "$GREP_PATTERN" "$file" 2>/dev/null || true)"
                (( MATCH_COUNT += hits )) || true

                # Output already has --color=always from check_content_match
                printf '%s\n' "$grep_output"
            fi
            ;;
        plain)
            if [[ "$PATHS_ONLY" == true ]]; then
                printf '%s\n' "$file"
                return
            fi
            # Strip ANSI from grep output for plain mode
            emit_result_plain "$file" "$reason" "$grep_output"
            if [[ -n "$grep_output" ]]; then
                local hits
                hits="$(grep -cE $CASE_FLAG -- "$GREP_PATTERN" "$file" 2>/dev/null || true)"
                (( MATCH_COUNT += hits )) || true
            fi
            ;;
        json)
            emit_result_json "$file" "$reason" "$grep_output"
            if [[ -n "$grep_output" ]]; then
                local hits
                hits="$(grep -cE $CASE_FLAG -- "$GREP_PATTERN" "$file" 2>/dev/null || true)"
                (( MATCH_COUNT += hits )) || true
            fi
            ;;
    esac
}

run_search() {
    MAX_FILE_SIZE_BYTES="$(parse_size "$(_config_read MAX_FILE_SIZE)")"

    while IFS= read -r -d '' file; do
        _progress_update

        local name_hit=false
        local content_hit=false
        local grep_output=""
        local basename
        basename="$(basename "$file")"

        # Filename match
        if [[ -n "$NAME_PATTERN" ]]; then
            check_filename_match "$basename" && name_hit=true
        fi

        # Content match
        if [[ -n "$GREP_PATTERN" ]]; then
            grep_output="$(check_content_match "$file")" && content_hit=true
        fi

        # Emit if either matched
        if [[ "$name_hit" == true || "$content_hit" == true ]]; then
            (( FILE_COUNT++ )) || true

            local reason=""
            if   [[ "$name_hit" == true && "$content_hit" == true ]]; then reason="filename + content"
            elif [[ "$name_hit" == true ]];                             then reason="filename"
            else                                                             reason="content"
            fi

            emit_result "$file" "$reason" "$grep_output"

            # Max results check
            if [[ $MAX_RESULTS -gt 0 && $FILE_COUNT -ge $MAX_RESULTS ]]; then
                if [[ "$OUTPUT_FORMAT" == "pretty" && "$PATHS_ONLY" == false ]]; then
                    printf '\n%s(stopped after %d matches — max results reached)%s\n' \
                        "$C_YELLOW" "$MAX_RESULTS" "$C_RESET"
                fi
                break
            fi
        fi

    done < <("${FIND_CMD[@]}" 2>/dev/null)
}

# ─── Search banner ──────────────────────────────────────────────────────────

print_search_banner() {
    [[ "$OUTPUT_FORMAT" != "pretty" ]] && return
    [[ "$PATHS_ONLY" == "true" ]] && return
    info "Searching in: ${VALID_PATHS[*]}"
    [[ -n "$NAME_PATTERN" ]] && info "Filename pattern : $NAME_PATTERN"
    [[ -n "$GREP_PATTERN" ]] && info "Content pattern  : $GREP_PATTERN"
    [[ -n "$CASE_FLAG"    ]] && info "Case-insensitive : yes"
    [[ -n "$MAX_DEPTH"    ]] && info "Max depth        : $MAX_DEPTH"
    [[ "$DIR_EXCLUSIONS_ENABLED" == "true" ]] && info "Dir exclusions   : on"
    printf '\n'
}

# ─── Summary ────────────────────────────────────────────────────────────────

print_summary() {
    _progress_clear

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        return
    fi

    # In paths-only mode, only print "No matches found" — skip the decorative footer
    if [[ "$PATHS_ONLY" == true ]]; then
        if [[ $FILE_COUNT -eq 0 ]]; then
            printf 'No matches found.\n' >&2
        fi
        return
    fi

    if [[ "$OUTPUT_FORMAT" == "pretty" ]]; then
        printf '\n%s%s%s\n' "$C_CYAN" "$(printf '═%.0s' {1..80})" "$C_RESET"
    fi

    if [[ $FILE_COUNT -eq 0 ]]; then
        if [[ "$OUTPUT_FORMAT" == "pretty" ]]; then
            printf '%sNo matches found.%s\n' "$C_YELLOW" "$C_RESET"
        else
            printf 'No matches found.\n'
        fi
    elif [[ "$SHOW_SUMMARY" == "true" ]]; then
        if [[ "$OUTPUT_FORMAT" == "pretty" ]]; then
            printf '%s%d file(s) matched' "$C_GREEN" "$FILE_COUNT"
            [[ -n "$GREP_PATTERN" ]] && printf ', %d content hit(s)' "$MATCH_COUNT"
            printf '.%s\n' "$C_RESET"
        else
            printf '%d file(s) matched' "$FILE_COUNT"
            [[ -n "$GREP_PATTERN" ]] && printf ', %d content hit(s)' "$MATCH_COUNT"
            printf '.\n'
        fi
    fi
}

# ─── Cleanup ────────────────────────────────────────────────────────────────

cleanup() {
    [[ -n "${_NEWER_REF:-}" && -f "${_NEWER_REF}" ]] && rm -f "$_NEWER_REF"
    [[ -n "${_OLDER_REF:-}" && -f "${_OLDER_REF}" ]] && rm -f "$_OLDER_REF"
    return 0
}
trap cleanup EXIT

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    preprocess_args "$@"
    parse_args

    require_cmd find
    require_cmd grep

    build_find_cmd
    print_search_banner
    run_search
    print_summary

    # Exit code: 2 if no matches
    if [[ $FILE_COUNT -eq 0 ]]; then
        exit 2
    fi
}

main "$@"
