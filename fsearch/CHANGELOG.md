# Changelog

All notable changes to fsearch are documented in this file.

## [2.1.0] - 2026-04-14

### Features

- **Progress indicator** — live spinner with files-scanned and matches-found counts written to stderr while searching. Active by default; disable with `--no-progress` or `fsearch config set SHOW_PROGRESS false`. Only displayed when stderr is an interactive terminal, so piped/scripted use is unaffected.
- **New config key `SHOW_PROGRESS`** (bool, default `true`) — persists the progress preference across invocations.

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
