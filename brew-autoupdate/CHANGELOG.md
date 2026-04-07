# Changelog

All notable changes to Homebrew Auto-Update are documented in this file.

## [2.2.0] - 2026-04-07

### Features

- **Log severity system** -- All log messages now include a severity tag (`[DEBUG]`, `[INFO]`, `[WARN]`, `[ERROR]`, `[CRITICAL]`). A new `LOG_LEVEL` config key controls the minimum severity written to logs. Set to `DEBUG` for maximum verbosity when troubleshooting, or `ERROR` to minimize log noise. Structured `[STATS]` and `[PKG]` lines are always written regardless of level to preserve dashboard data.
- **Config export/import** -- New `brew-logs config export [FILE]` and `brew-logs config import FILE` commands enable configuration backup, transfer between systems, and multi-machine deployment. Exports include a system metadata header (hostname, macOS version, architecture, tool version). Imports validate each key before writing and report applied/skipped/errored counts.

### Bug Fixes

- **Fix dashboard right-border misalignment** -- Replaced `${#plain}` character counting with `wc -m` based visible-width measurement that correctly handles multi-byte Unicode characters (box-drawing glyphs, check marks, bullets). Dashboard content rows are now measured and padded to exactly `_IW` visible columns.
- **Fix dashboard header crash on narrow terminals** -- The header row gap between title and timestamp is now clamped to a minimum of 1, preventing negative-width `printf` errors when terminal width is close to the minimum 72 columns.

### Improvements

- **New config type: `loglevel`** -- The config validation system now recognizes `LOG_LEVEL` as a dedicated `loglevel` type, accepting only `DEBUG|INFO|WARN|ERROR|CRITICAL` (case-insensitive). Invalid values are rejected with a clear error message.
- **`LOG_LEVEL` in config show/get/set** -- `LOG_LEVEL` appears in `brew-logs config` output, supports `get`/`set`/`reset`, and is included in config exports.

### Tests

- Added §28: LOG_LEVEL severity filtering (5 tests) -- verifies INFO/DEBUG/ERROR level filtering and that STATS lines bypass filtering.
- Added §29: Config export/import (8 tests) -- verifies export file creation, content, metadata header, import application, and unknown-key skipping.
- Added §30: LOG_LEVEL config validation (3 tests) -- verifies valid/invalid levels and config show listing.
- Added §31: Dashboard width border alignment (2 tests) -- verifies all content and border rows have correct right-side borders.
- Updated test for pre-update hook warning message to match new severity-tagged format.
- Total test target: ~191 cases (up from ~173).

### Documentation

- Updated README with LOG_LEVEL, config export/import features, and new settings reference.
- Updated User Manual with new Log Level and Config Export/Import sections, updated TOC, config types table, command reference, and alphabetical command index.
- Updated config.conf with LOG_LEVEL section and inline documentation.
- Updated version references across all scripts and docs to 2.2.0.

## [2.1.2] - 2026-04-06

### Bug Fixes

- **Fix dashboard right-border breakage on narrow terminals** -- Updated dashboard row rendering to clip overlong lines to panel width, preventing wrapped content from splitting the right border.

### Documentation

- Updated version references in scripts and docs for the 2.1.2 release.

## [2.1.1] - 2026-04-06

### Bug Fixes

- **Fix lock acquisition race condition** -- Reworked lock creation in `brew-autoupdate.sh` to use atomic `noclobber` writes, preventing overlapping runs when two processes start simultaneously.
- **Fix quiet-hours behavior for manual runs** -- Added `--manual-run` support in `brew-autoupdate.sh` and updated `brew-logs run` to use it so user-triggered runs are no longer skipped by quiet hours.
- **Fix misleading success output in `brew-logs run`** -- The viewer now checks exit status and returns non-zero with an explicit failure message when the update script fails.
- **Fix literal `\n` in outdated-package detail logging** -- Replaced escaped newline logging with explicit line logging for consistent readability.

### Tests

- Added quiet-hours integration test proving `--manual-run` bypasses quiet-hour skips.
- Added lock behavior test for active lock PID skip path (no brew commands executed).
- Added viewer run failure-path test to verify non-zero exit and user-facing failure message.

## [2.1.0] - 2026-04-06

### Security

- **Fix command injection in config parser** -- Replaced `declare "${key}=${value}"` with `printf -v` to prevent execution of `$(...)` or backtick command substitutions embedded in config values.
- **Fix AppleScript injection in notifications** -- Double quotes in package names or error messages are now escaped before being passed to `osascript`, preventing malformed or injected AppleScript.

### Bug Fixes

- **Fix log rotation abort under `set -e`** -- Replaced `((counter++))` with `$(( counter + 1 ))` to prevent silent script termination when the counter increments from 0 (which bash treats as falsy under `errexit`).
- **Fix config comment stripping breaking values containing `#`** -- Changed inline comment stripping from `s/#.*//` to `s/[[:space:]]#.*//` so that `#` characters within values (URLs, API tokens, env vars) are preserved. A `#` is now only treated as a comment when preceded by whitespace. Fixed in all three files: `brew-autoupdate.sh`, `brew-autoupdate-viewer.sh`, and `install.sh`.
- **Fix `tac` fallback producing wrong sort order on stock macOS** -- Replaced `tac 2>/dev/null || tail -8` with a portable `awk` reverse that works on macOS without GNU coreutils. The dashboard recent-runs table now correctly shows newest-first on all systems.
- **Fix time validation accepting invalid hours 24-29** -- Tightened the `_config_validate` time regex from `^[0-2][0-9]:[0-5][0-9]$` to `^([01][0-9]|2[0-3]):[0-5][0-9]$` so that times like `29:59` are correctly rejected.
- **Fix `_config_write` grep regex injection** -- Replaced `grep -q "^${key}="` with a bash pattern match (`[[ "${line}" == "${key}="* ]]`) to avoid treating config key names as regex patterns.
- **Fix non-integer `CLEANUP_OLDER_THAN_DAYS` crash** -- Added integer validation before the `-gt` comparison so non-numeric values no longer cause a bash error under `set -e`.
- **Remove all `xargs` usage** -- Replaced all `xargs` whitespace-trimming calls with `sed` or `tr` across `install.sh` and `brew-autoupdate-viewer.sh`. Eliminates "xargs: unterminated quote" errors caused by apostrophes in piped data (e.g., brew output containing `your system's`).
- **Fix `export '""'` crash in BREW_ENV parsing** -- The `declare` to `printf -v` migration caused literal `""` from defaults to be preserved as a two-character string instead of empty. This made `export '""'` fail with "not a valid identifier". Fixed by removing shell quotes from all hardcoded defaults (using bare `VAR=` instead of `VAR=""`), stripping stray quotes from `BREW_PATH`, and validating `KEY=VALUE` format before exporting `BREW_ENV` pairs.

### Improvements

- **Validate empty `SCHEDULE_HOURS`** -- `generate_plist()` in `install.sh` and `_inline_plist_reload()` in the viewer now fall back to the default schedule (`0,6,12,18`) if `SCHEDULE_HOURS` is empty, preventing generation of invalid plist XML.
- **Bulletproof brew detection** -- `brew-autoupdate.sh` now searches a candidate list of all known Homebrew install locations (`/opt/homebrew`, `/usr/local`, `/home/linuxbrew`) plus `BREW_PATH` from config and `command -v` fallback. PATH is prepended with all standard Homebrew directories before resolution, ensuring brew is found in non-interactive contexts (launchd, `bash` subprocesses, `brew-logs run`). The installer passes `BREW_PREFIX` to the verification subprocess, `brew-logs run` passes Homebrew paths to the spawned subprocess, and the installer auto-sets `BREW_PATH` in config when brew is found at a non-standard location.

### Tests

- Added tests for `CLEANUP_OLDER_THAN_DAYS` passing `--prune=N` to brew cleanup.
- Added tests for `BREW_ENV` environment variable export.
- Added tests for log rotation (old files deleted, recent files preserved).
- Added tests for lock file concurrency (stale lock detection).
- Added tests for viewer `detail last N`, `summary last N`, `list`, and `run` commands.
- Added tests for `config set` with values containing spaces.
- Added tests for notification content via mock osascript log.
- Added tests for command injection prevention in config parser.
- Added test for time validation rejecting hour 25.
- Added test for `_config_write` with values containing spaces.

### Documentation

- Updated config.conf comment syntax documentation to reflect new `#` handling rules.
- Added CHANGELOG.md.
- Updated version to 2.1.0 across all files.

## [2.0.0] - 2026-03-30

### Added

- Terminal dashboard (`brew-logs dashboard`) with run history, statistics, and package frequency charts.
- CLI config editor (`brew-logs config get/set/reset`) for managing settings without editing files.
- Schedule management via config (`SCHEDULE_HOURS`, `SCHEDULE_MINUTE`) with `brew-logs schedule reload`.
- Quiet hours (`QUIET_HOURS_ENABLED`, `QUIET_HOURS_START`, `QUIET_HOURS_END`) to suppress updates during specified time windows.
- Package filtering with `DENY_LIST` and `ALLOW_LIST` for granular upgrade control.
- Pre/post update hooks (`PRE_UPDATE_HOOK`, `POST_UPDATE_HOOK`) for custom shell commands.
- Structured `[STATS]` and `[PKG]` log lines for machine-parseable run metrics.
- Comprehensive regression test suite (130+ test cases across 19 sections).

### Fixed

- Fixed `xargs` unterminated quote error caused by apostrophes in config file comments.
- Fixed greedy cask upgrade flag (`--greedy`) never being passed to `brew upgrade`.

## [1.0.0] - 2026-03-28

### Added

- Initial release.
- Automated Homebrew package maintenance via launchd daemon.
- Two-tier logging system (detail + summary).
- macOS Notification Center alerts.
- `brew-logs` CLI for log viewing and status.
- Configurable via `config.conf`.
