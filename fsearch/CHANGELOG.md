# Changelog

All notable changes to fsearch are documented in this file.

## [2.3.1] - 2026-04-16

### Bug Fixes

- **Interactive keypress control: fd 9 opened read-only** — `_interactive_setup` used `exec 9</dev/tty`, opening the tty read-only. `stty` silently failed to apply `min 0 time 0` non-blocking settings through a read-only fd, so every keypress was missed. Fixed by opening read-write: `exec 9<>/dev/tty`.
- **`_interactive_poll` two-step read pattern** — The `read -t 0 -n 1` availability check followed by a separate blocking `read -n 1` fallback was unreliable on macOS because the stty settings never took effect (see above). Simplified to a single `read -r -n 1 -s key <&9`; with `stty min 0 time 0` correctly applied, this returns immediately when no key is pressed.
- **`_interactive_pause` loop** — Same two-step read issue as `_interactive_poll`; simplified to a single `read -r -n 1 -s key <&9`.

### Testing

- Added `FSEARCH_SOURCE_ONLY=1` source guard at the bottom of `fsearch.sh`, allowing the test suite to source internal functions without running `main`.
- Replaced the `print_skip` placeholder in S25 with nine fifo-backed key routing tests covering all key bindings (`?`, `h`, `H`, `q`, `Q`, `p`, `P`, `s`, `l`).

## [2.3.0] - 2026-04-16

### Features

- **Interactive keypress control** -- While the progress spinner is active (stdin is a tty, `--no-progress` not given, format is not JSON), the following keys are recognised:
  - `p` — pause / resume the search
  - `q` — quit immediately, print partial summary, record stats, exit 2
  - `s` — one-line stats snapshot (scanned / matched / hits) without pausing
  - `l` — display last 5 matched file paths from a ring buffer
  - `?` or `h` — show the key reference
  - The spinner line gains a dimmed `[? help]` suffix for discoverability.
  - Completely suppressed in pipes, CI, `--no-progress`, `--format json/plain`.
- **Improved Ctrl+C** -- SIGINT now restores terminal state, clears the progress line, prints a partial match summary to stderr, records partial stats/log, and exits 130 (128 + SIGNO 2) instead of leaving the terminal in raw mode.

### Architecture

- `_interactive_setup` / `_interactive_teardown` — tty raw-mode lifecycle (`stty -g` save + restore); guarded by `[[ -t 0 ]]` and `SHOW_PROGRESS=true`.
- `_interactive_poll` — `read -r -t 0 -n 1 -s` non-blocking poll called every 10 files at the existing progress update point; zero overhead when no key pressed (`|| true` handles bash 3.2 exit-1 on no-data).
- `_recent_match_add` / `_RECENT_MATCH_BUF` — manual 5-slot ring buffer (index-arithmetic, no `mapfile`) compatible with bash 3.2.
- `_sigint_handler` — registered via `trap _sigint_handler INT`; idempotently tears down interactive state before printing summary.
- `_SEARCH_START_TIME` — global set in `main` so `_interactive_quit` and `_sigint_handler` can compute partial elapsed duration for stats recording.
- `_progress_update` — uses a separate visible-length variable for padding arithmetic so the dimmed `[? help]` color codes don't skew `_PROGRESS_LAST_LEN`.

### Test Suite

- **~154 tests across 25 sections** (up from 148 across 24).
- **New section S25 (Interactive keypress control)**: no-tty guard, JSON suppression, `--no-progress` suppression, version 2.3.0 assertion, ring-buffer code path, SIGINT exit-130 check. Interactive p/q/s/l/? keys marked `skip` (require a real tty — see README for manual verification steps).
- Updated all version string assertions from `2.2.0` to `2.3.0`.

## [2.2.0] - 2026-04-16

### Performance

- **Batched stats writes** -- `_stats_record` now reads all cumulative stats in a single scan of `stats.conf` and writes them back in one atomic operation (temp file + mv). Replaces the previous approach of 5 sequential read/write cycles per search (one per stat key). Reduces post-search file I/O by ~80%.
- **No-fork hit counting** -- `_count_hits_from_output` now uses bash `=~` pattern matching to identify match lines instead of forking a `grep` subprocess per output line. Eliminates one process fork per matching line on result sets with many hits.

### Features

- **Timing statistics** -- Every search now records its wall-clock duration. `--stats` shows two new fields: `Total search time` (cumulative seconds) and `Avg search time` (per-search average with one decimal place). Stored as `TOTAL_SEARCH_TIME_S` in `stats.conf`. Existing stats files are handled gracefully (missing key defaults to 0).

### Bug Fixes

- **install.sh: PATH not added on fresh macOS** -- The installer now writes the PATH export to `~/.zprofile` for macOS zsh users instead of `~/.zshrc`. `~/.zprofile` is sourced for every login shell (new Terminal window), making the PATH available immediately after opening a new terminal without any manual sourcing.
- **install.sh: `source` command printed after PATH update** -- The installer now prints the exact `source <file>` command to activate the PATH immediately in the current session, rather than a generic "restart your terminal" message.
- **install.sh: BSD-incompatible `sed ,+N` in uninstall** -- Replaced `sed "/${PATH_MARKER}/,+1d"` (GNU sed only) with a portable bash loop that removes the marker line and the following PATH export line. Fixes uninstall on macOS.
- **install.sh: `~/.zprofile` now covered in uninstall sweep** -- The uninstall PATH cleanup now includes `~/.zprofile` in its scan, matching the updated install path.
- **execute permissions** -- `install.sh` and `fsearch.sh` are now tracked as executable in git (`chmod +x`). Running `./install.sh` no longer requires a manual `chmod` after cloning.

### Test Suite

- **148 tests across 24 sections** (up from 126 tests across 22 sections).
- **New section S24 (Timing performance)**: wall-clock bounds tests for content and filename search over 100-file fixture; assertions that `Total search time` and `Avg search time` appear in `--stats` output with correct numeric format; accumulation check across multiple searches.
- Updated all version string assertions from `2.1.0` to `2.2.0`.

### Documentation

- README updated with timing stats fields in the Statistics section and output example.
- README install section notes that `bash install.sh` works without requiring the file to be executable first.

## [2.1.0] - 2026-04-15

### Bug Fixes

- **`--` argument handling** -- Fixed `preprocess_args` so `--` correctly terminates option parsing and passes remaining arguments as paths without duplication.
- **Unquoted `$CASE_FLAG` expansions** -- All `grep` invocations now use `${CASE_FLAG:+"$CASE_FLAG"}` to safely handle the empty-string case, eliminating shellcheck warnings and fragile word-splitting behaviour.
- **JSON escaping** -- Replaced incomplete `sed`-based escaping with `_json_escape()` function that handles backslashes, double quotes, tabs, carriage returns, backspaces, form feeds, and embedded newlines.
- **Triple grep per file** -- Eliminated redundant `grep -c` re-invocations in `emit_result()`. Match counts are now extracted from the existing grep output via `_count_hits_from_output()`, halving the number of grep forks per matching file.
- **`file` command performance** -- Replaced per-file `file` fork with fast null-byte detection (`head -c 512 | grep -qP '\x00'`). Falls back to `file` on systems without `grep -P`. Significant speedup on large directory trees.
- **`stat` detection caching** -- Platform detection for GNU vs BSD `stat` now runs once at startup (`_STAT_IS_GNU`) instead of on every call to `file_timestamps`, `file_size_human`, and `file_size_bytes`.
- **Install script PATH cleanup** -- Replaced brittle `grep -v -A1` uninstall logic with `sed` block delete for reliable removal of PATH marker and export line.

### Features

- **Version display on every search** -- The search banner now shows `fsearch v2.1.0` at the top of pretty-format output. Suppressed in `-0` (paths-only) and non-pretty formats to keep machine-parseable output clean.
- **Cumulative statistics** -- Persistent stats stored in `~/.config/fsearch/stats.conf` tracking total searches, files scanned, files matched, content hits, errors, and first/last search timestamps. View with `--stats`, reset with `--stats-reset`.
- **Search logging** -- Every search is logged to `~/.config/fsearch/logs/YYYY-MM-DD.log` with timestamp, patterns, paths, result counts, duration, and error details. One file per day.
- **Log retention management** -- Logs older than `LOG_RETENTION_DAYS` (default: 7, configurable) are automatically purged on each search run. Statistics persist independently.
- **`LOG_RETENTION_DAYS` config key** -- New integer config key controlling how many days of detailed search logs to retain.
- **Files scanned count in summary** -- The result summary now includes the total number of files scanned (e.g., "3 file(s) matched, 5 content hit(s) (142 file(s) scanned).").
- **Error counting** -- Errors (unreadable files, etc.) are tracked per-search and recorded in both statistics and logs.

### Architecture

- **`_json_escape()` function** -- Centralised JSON string escaping used by all JSON output paths.
- **`_is_binary()` function** -- Extracted binary detection into a dedicated function with fast-path null-byte check and `file`-command fallback.
- **`_bytes_to_human()` function** -- Extracted from `file_size_human()` for reuse in stats display.
- **`_count_hits_from_output()` function** -- Counts match lines from grep output by parsing `NUM:` prefixes, avoiding re-grep.
- **Platform detection at startup** -- `_STAT_IS_GNU` and `_HAS_GREP_P` flags set once and reused throughout.

### Test Suite

- **126 tests across 22 sections** (up from 98 tests across 19 sections).
- **New sections**: S2 (version display), S19 (statistics), S20 (search logging).
- **New edge case tests**: `--` argument terminator, files with `=` in name, config values containing `=`, scanned count in summary.
- **Fixed section numbering** -- Comments and section headers now use consistent S1-S22 numbering.
- **Removed unused `run_fsearch_exit` helper**.

### Documentation

- README updated with statistics, logging, and new config key documentation.
- Output examples updated to show version banner and scanned count.
- Install script quick-start updated with `--stats` example.

## [2.0.0] - 2026-04-14

### Features

- **Persistent configuration system** -- All defaults (search paths, context lines, excluded directories, output format, etc.) are stored in `~/.config/fsearch/config.conf` and managed via `fsearch config get|set|reset|path-add|path-remove`. No manual file editing required.
- **Smart directory exclusions** -- `.git`, `node_modules`, `__pycache__`, `.venv`, `vendor`, and `.DS_Store` are pruned from search by default. Configurable via `config set EXCLUDE_DIRS` or disabled per-search with `-E`.
- **Depth control (`-d N`)** -- Granular `find -maxdepth` control replaces the binary `-r`/`-R` toggle.
- **Max results (`-m N`)** -- Stop after N file matches for exploratory searches.
- **Inline match highlighting** -- `grep --color=always` highlights the matched substring within each line, replacing the v1 approach of colouring entire lines yellow.
- **File size display (`--size`)** -- Human-readable file size (B/K/M/G) shown alongside timestamps in output headers. Opt-in via flag or `config set SHOW_FILE_SIZE true`.
- **Max file size skip** -- Files exceeding `MAX_FILE_SIZE` (default 10M) are skipped during content search. Prevents hanging on huge logs or binaries.
- **Date range filters (`--newer`/`--older`)** -- Filter files by modification time. Supports both GNU (`-newermt`) and BSD (`touch -t` reference file) find.
- **Output formats (`--format pretty|plain|json`)** -- Pretty (default, coloured), plain (no colour/decoration, good for piping), JSON (one JSONL object per file match, pipeable to `jq`).
- **Long option support** -- `--format`, `--newer`, `--older`, `--version`, `--no-color`, `--size` alongside short flags.
- **`--version` flag** -- Prints version and exits.
- **Summary always shown** -- Result count prints by default (configurable via `SHOW_SUMMARY`).

### Architecture

- **Config system** -- key=value config file with type-aware validation (bool, int, string), atomic writes via temp file + mv, ordered key list for `config show`.
- **Find command builder** -- Builds the find command array directly in a global variable, fixing a v1 bug where `echo`/`read -ra` broke on paths containing spaces.
- **Decomposed search logic** -- `run_search()` calls `check_filename_match()`, `check_content_match()`, and `emit_result()` as separate functions.
- **Directory pruning** -- Excluded dirs are integrated into `find` as `-path ... -prune` predicates, avoiding descent into irrelevant trees (much faster than post-filtering).
- **Cleanup trap** -- Temp files from date filter reference files are cleaned up on exit.

### Project

- **Formal header** -- Boxed header with File, Version, Author, License, Requires, Description, Exit Codes.
- **Versioning** -- `FSEARCH_VERSION="2.0.0"` constant, synced to CHANGELOG and README.
- **Comprehensive test suite** -- `test_fsearch.sh` with ~80 test cases across 19 sections.

## [1.0.0] - 2026-04-14

### Initial Release

- File search by name pattern (`-n`) and/or content (`-g`) with extended regex.
- Predefined search paths (hardcoded) with `-p` override.
- Case-insensitive matching (`-i`).
- Configurable context lines (`-C`).
- Extension include/exclude filters (`-l`/`-x`).
- Output modes: quiet (`-q`), paths-only (`-0`), summary (`-s`).
- Recursion toggle (`-r`/`-R`).
- Binary file detection and skip.
- Platform-aware timestamps (macOS BSD stat / Linux GNU stat).
- Coloured terminal output with tput.
- macOS installer (`install.sh`) with PATH setup and uninstall support.
