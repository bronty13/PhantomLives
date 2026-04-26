# Changelog

All notable changes to fsearch are documented in this file.

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
