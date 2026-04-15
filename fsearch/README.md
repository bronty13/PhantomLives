# fsearch

**Current release: 2.1.0**

File search utility for macOS and Linux. Searches configurable directory trees by filename pattern and/or text content, printing timestamps, file metadata, and matching lines with context.

## Quick Start

```bash
# Install (macOS)
./install.sh            # installs to ~/.local/bin
./install.sh --system   # installs to /usr/local/bin (sudo)

# Search for .py files containing 'import'
fsearch -n '\.py$' -g 'import'

# Search a custom path, case-insensitive, 5 lines of context
fsearch -p ~/projects -g 'api_key' -i -C 5

# List files containing 'password' (paths only)
fsearch -g 'password' -i -0

# JSON output for scripting
fsearch -g 'TODO' --format json | jq '.file'
```

## Features

- **Dual search modes** -- filename regex (`-n`) and/or content grep (`-g`)
- **Persistent configuration** -- `fsearch config set/get/reset` manages all defaults
- **Smart directory exclusions** -- skips `.git`, `node_modules`, `__pycache__`, etc. by default
- **Multiple output formats** -- pretty (coloured), plain (for piping), JSON (JSONL)
- **Inline match highlighting** -- matched text highlighted within each line
- **Date range filters** -- `--newer` / `--older` for modification time
- **Progress indicator** -- live spinner + scanned/matched counts on stderr while searching (configurable, off with `--no-progress`)
- **Max results** -- `-m N` to stop after N matches
- **File size display** -- `--size` to show human-readable file sizes
- **Large file skip** -- configurable max file size for content search (default 10M)
- **Cross-platform** -- macOS (bash 3.2, BSD stat) and Linux (GNU stat)

## Search Options

```
-n <pattern>      Filename regex (extended)
-g <pattern>      Content grep pattern
-p <path>         Search path (repeatable; overrides configured defaults)
-i                Case-insensitive matching
-d <num>          Max directory depth
-C <num>          Context lines around matches (default: 3)
-l <ext,...>      Include only these file extensions
-x <ext,...>      Exclude these file extensions
-E                Disable default directory exclusions
--newer <DATE>    Files modified after DATE (YYYY-MM-DD)
--older <DATE>    Files modified before DATE
-m <num>          Max file matches
-q                Suppress per-file header
-0                Print matching file paths only
--format <fmt>    Output: pretty (default), plain, json
--size            Show file size in output
--no-color        Disable colour
--no-progress     Disable progress indicator while searching
--version         Print version
-h, --help        Show help
```

## Configuration

All settings are managed via CLI subcommands -- no manual file editing required.

```bash
fsearch config                     # Show all settings
fsearch config get KEY             # Show one setting
fsearch config set KEY VALUE       # Change a setting
fsearch config reset KEY           # Reset to default
fsearch config path-add ~/notes    # Add a default search path
fsearch config path-remove ~/tmp   # Remove a default search path
fsearch config path                # Show config file location
```

### Available Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `DEFAULT_PATHS` | string | `~/Documents ~/Desktop ~/Downloads` | Space-separated search roots |
| `CONTEXT_LINES` | int | `3` | Lines of context around matches |
| `CASE_INSENSITIVE` | bool | `false` | Default case sensitivity |
| `EXCLUDE_DIRS` | string | `.git node_modules __pycache__ .venv vendor .DS_Store` | Directories to skip |
| `EXCLUDE_DIRS_ENABLED` | bool | `true` | Apply directory exclusions |
| `MAX_FILE_SIZE` | string | `10M` | Skip files larger than this |
| `MAX_RESULTS` | int | `0` | Max matches (0 = unlimited) |
| `COLOR` | bool | `true` | Colour output |
| `OUTPUT_FORMAT` | string | `pretty` | Default format |
| `SHOW_FILE_SIZE` | bool | `false` | Show file size in headers |
| `SHOW_SUMMARY` | bool | `true` | Show result count |
| `SHOW_PROGRESS` | bool | `true` | Show progress indicator while searching |

Config file location: `~/.config/fsearch/config.conf`

## Output Examples

### Pretty (default)

```
══╡ src/auth.py ╞
  created: 2026-03-01 10:30:00  |  modified: 2026-04-10 14:22:15
  match: content
────────────────────────────────────────────────────────────────────────────────
41-def validate_token(token):
42:    api_key = os.environ["API_KEY"]
43-    return hmac.compare_digest(token, api_key)
```

### JSON

```json
{"file":"src/auth.py","match_type":"content","created":"2026-03-01 10:30:00","modified":"2026-04-10 14:22:15","size":1842,"matches":[{"line":42,"text":"    api_key = os.environ[\"API_KEY\"]"}]}
```

### Plain

```
--- src/auth.py [content]
42:    api_key = os.environ["API_KEY"]
```

## Installation

```bash
# User-local (no sudo)
./install.sh

# System-wide
./install.sh --system

# Upgrade existing install
./install.sh --upgrade

# Uninstall
./install.sh --uninstall
```

## Requirements

- bash 3.2+ (macOS default or newer)
- `find`, `grep`, `file`, `stat` (standard on macOS and Linux)
- No external dependencies (`jq`, Python, etc.)

## Running Tests

```bash
bash test_fsearch.sh              # Run all tests
bash test_fsearch.sh --verbose    # Verbose output
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Matches found, or config command completed |
| 1 | Error (invalid arguments, no valid paths) |
| 2 | No matches found |
