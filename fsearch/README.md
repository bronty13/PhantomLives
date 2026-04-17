# fsearch

**Current release: 2.3.1**

File search utility for macOS and Linux. Searches configurable directory trees by filename pattern and/or text content, printing timestamps, file metadata, and matching lines with context. Tracks cumulative search statistics and maintains detailed search logs.

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

# View search statistics
fsearch --stats
```

## Features

- **Dual search modes** -- filename regex (`-n`) and/or content grep (`-g`)
- **Persistent configuration** -- `fsearch config set/get/reset` manages all defaults
- **Smart directory exclusions** -- skips `.git`, `node_modules`, `__pycache__`, etc. by default
- **Multiple output formats** -- pretty (coloured), plain (for piping), JSON (JSONL)
- **Inline match highlighting** -- matched text highlighted within each line
- **Date range filters** -- `--newer` / `--older` for modification time
- **Max results** -- `-m N` to stop after N matches
- **File size display** -- `--size` to show human-readable file sizes
- **Large file skip** -- configurable max file size for content search (default 10M)
- **Interactive search control** -- press `?` while a search is running to see available keys; `p` pauses/resumes, `q` quits with partial summary, `s` shows a live stats snapshot, `l` shows the last 5 matched files. Active only when stdin is a terminal. No-op in pipes, CI, `--no-progress`, and JSON/plain output.
- **Improved Ctrl+C** -- restores terminal state and prints a partial match summary before exiting (exit code 130).
- **Cross-platform** -- macOS (bash 3.2, BSD stat) and Linux (GNU stat)
- **Cumulative statistics** -- tracks searches, files scanned, matches found (`--stats`)
- **Search logging** -- detailed per-search logs with automatic 7-day retention
- **Version display** -- version shown in every search banner

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
--version         Print version
-h, --help        Show help
```

## Interactive Keys (during search)

When the progress spinner is visible (stdin is a terminal, `--no-progress` not set,
output format is not JSON), the following keys are active:

| Key   | Action                                       |
|-------|----------------------------------------------|
| `?`   | Show key reference                           |
| `p`   | Pause / resume search                        |
| `q`   | Quit search, print partial summary           |
| `s`   | Live stats snapshot (scanned / matched / hits) |
| `l`   | Show last 5 matched files                    |

The spinner line also shows a `[? help]` hint to make the feature discoverable.
These keys are completely suppressed in non-tty contexts (pipes, CI, scripts).

## Statistics & Logging

fsearch tracks cumulative search statistics and maintains detailed search logs.

### Statistics

```bash
fsearch --stats           # Show cumulative statistics
fsearch --stats-reset     # Reset all statistics to zero
```

Statistics tracked:
- Total searches run
- Total files scanned
- Total files matched
- Total content hits
- Total errors
- Total search time (seconds) and average search time per run
- First and last search timestamps
- Log file count and size

### Search Logging

Every search is logged to `~/.config/fsearch/logs/` with one file per day. Each log entry records:
- Timestamp
- Search status (success, no_matches, partial_error)
- Name and content patterns used
- Paths searched
- Files scanned, matched, and content hits
- Error count and details
- Search duration

Log retention is configurable:
```bash
fsearch config get LOG_RETENTION_DAYS     # Default: 7
fsearch config set LOG_RETENTION_DAYS 14  # Keep 14 days
```

Logs older than the retention period are automatically purged on each search. Statistics are cumulative and persist independently of log rotation.

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
| `LOG_RETENTION_DAYS` | int | `7` | Days to keep detailed search logs |

Config file location: `~/.config/fsearch/config.conf`

## Output Examples

### Pretty (default)

```
fsearch v2.2.0
Searching in: ~/projects
Content pattern  : api_key

══╡ src/auth.py ╞
  created: 2026-03-01 10:30:00  |  modified: 2026-04-10 14:22:15
  match: content
────────────────────────────────────────────────────────────────────────────────
41-def validate_token(token):
42:    api_key = os.environ["API_KEY"]
43-    return hmac.compare_digest(token, api_key)

════════════════════════════════════════════════════════════════════════════════
1 file(s) matched, 1 content hit(s) (42 file(s) scanned).
```

### JSON

```json
{"file":"src/auth.py","match_type":"content","created":"2026-03-01 10:30:00","modified":"2026-04-10 14:22:15","size":1842,"matches":[{"line":42,"text":"    api_key = os.environ[\"API_KEY\"]"}]}
```

### Plain

```
--- src/auth.py [content]
42:    api_key = os.environ["API_KEY"]
1 file(s) matched, 1 content hit(s) (42 file(s) scanned).
```

### Statistics

```
fsearch v2.2.0 — Cumulative Statistics
────────────────────────────────────────────────────────────────
  Total searches:                147
  Files scanned:                 24831
  Files matched:                 412
  Content hits:                  1893
  Errors:                        3
  Total search time:             38s
  Avg search time:               0.2s
────────────────────────────────────────────────────────────────
  First search:                  2026-04-01 09:15:22
  Last search:                   2026-04-16 09:44:10
  Stats file:                    ~/.config/fsearch/stats.conf
  Log files:                     7 file(s), 12K
────────────────────────────────────────────────────────────────
  Reset: fsearch --stats-reset
```

## Installation

```bash
# User-local (no sudo)
./install.sh
# or, if the file is not yet executable after cloning:
bash install.sh

# System-wide
./install.sh --system

# Upgrade existing install
./install.sh --upgrade

# Uninstall
./install.sh --uninstall
```

> **macOS note:** The installer writes the PATH entry to `~/.zprofile`, which is sourced for every new Terminal window. After installing, either open a new terminal or run the `source` command printed by the installer to activate `fsearch` immediately.

## Requirements

- bash 3.2+ (macOS default or newer)
- `find`, `grep`, `file`, `stat` (standard on macOS and Linux)
- No external dependencies (`jq`, Python, etc.)

## Running Tests

```bash
bash test_fsearch.sh              # Run all tests (~154 tests across 25 sections)
bash test_fsearch.sh --verbose    # Verbose output
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Matches found, or config/stats command completed |
| 1 | Error (invalid arguments, no valid paths) |
| 2 | No matches found |
