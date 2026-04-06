# Changelog

All notable changes to Homebrew Auto-Update are documented in this file.

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

### Improvements

- **Validate empty `SCHEDULE_HOURS`** -- `generate_plist()` in `install.sh` and `_inline_plist_reload()` in the viewer now fall back to the default schedule (`0,6,12,18`) if `SCHEDULE_HOURS` is empty, preventing generation of invalid plist XML.

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
