# Homebrew Auto-Update

Current release: 2.1.2

Automated Homebrew package maintenance for macOS with two-tier logging, macOS notifications, and a built-in log viewer.

Runs as a background launchd daemon, updating your Homebrew packages 4 times daily with zero manual intervention.

## Features

- **Automatic updates** — Runs `brew update`, `upgrade`, `cleanup`, `autoremove`, and `doctor` on a schedule
- **4x daily execution** — Configurable launchd schedule (default: 12 AM, 6 AM, 12 PM, 6 PM)
- **Two-tier logging** — Verbose detail logs (90 days) + concise summary logs (1 year)
- **macOS notifications** — Alerts on errors; optional alerts on every run for verification
- **Terminal dashboard** — `brew-logs dashboard` for a full graphical status overview with run history, stats, and package charts
- **Log viewer CLI** — `brew-logs` command for quick access to logs, status, and manual runs
- **CLI config editor** — `brew-logs config get/set/reset` to manage settings without editing files
- **Configurable** — Single config file controls all behavior; changes take effect on next run
- **Quiet hours** — Optional time window to suppress scheduled updates (manual runs always execute)
- **Package filtering** — Deny list to pin packages, or allow list to whitelist specific packages
- **Pre/post hooks** — Run custom shell commands before or after each update cycle
- **Low impact** — Runs at low I/O and CPU priority; won't interfere with your work
- **Concurrent-safe** — Atomic lock-file acquisition prevents overlapping runs
- **Self-maintaining** — Automatic log rotation keeps disk usage bounded

## Quick Start

```bash
# Clone or download the files, then:
cd brew-autoupdate
bash install.sh
```

The installer will:
1. Verify prerequisites (macOS + Homebrew)
2. Install scripts to `~/.config/brew-autoupdate/`
3. Set up the launchd daemon
4. Create the `brew-logs` command
5. Optionally run a verification test

## Files Overview

| File | Purpose |
|------|---------|
| `brew-autoupdate.sh` | Main update script — the core engine |
| `brew-autoupdate-viewer.sh` | Log viewer CLI — installed as `brew-logs` |
| `config.conf` | Configuration file — all settings in one place |
| `com.user.brew-autoupdate.plist` | launchd daemon definition — schedule and environment |
| `install.sh` | Installer/uninstaller |
| `README.md` | This documentation |
| `USER_MANUAL.md` | Comprehensive user guide |
| `CHANGELOG.md` | Version history and release notes |

## What Happens Each Run

The update script executes these steps in order. Each step is independently error-handled — a failure in one step does not prevent subsequent steps from running.

| Step | Command | Purpose |
|------|---------|---------|
| 1 | `brew update --verbose` | Fetch latest formulae and cask definitions |
| 2 | `brew outdated --verbose` | Log which packages need updating |
| 3 | `brew upgrade --verbose` | Install newer versions of outdated packages |
| 4 | `brew cleanup --verbose` | Remove old versions and stale downloads |
| 5 | `brew autoremove --verbose` | Remove orphaned dependencies |
| 6 | `brew doctor` | Run diagnostic health check |
| 7 | *(internal)* | Rotate logs exceeding retention thresholds |

## Logging Architecture

### Two-Tier System

The logging system is designed to balance troubleshooting capability with long-term history:

**Detail Logs** — `~/Library/Logs/brew-autoupdate/detail/`
- One file per run, named by timestamp: `2026-03-30_06-00-01.log`
- Contains ALL output: full brew command output, config dumps, diagnostics
- Maximum verbosity for troubleshooting errors
- Default retention: **90 days** (~360 files at 4 runs/day)

**Summary Logs** — `~/Library/Logs/brew-autoupdate/summary/`
- One file per day, named by date: `2026-03-30.log`
- Contains milestones only: start/stop, what was outdated, what changed, errors
- Lightweight record for long-term package update history
- Default retention: **365 days** (~365 files)

### Log Rotation

Logs are automatically pruned at the end of each update cycle. Files older than the configured retention period are deleted. Retention periods are configurable in `config.conf`.

### macOS Console.app

Logs are stored under `~/Library/Logs/`, which means they're also browsable in macOS Console.app under "Log Reports."

## Using `brew-logs`

The `brew-logs` command provides quick access to all logging and status functions.

### Commands

```bash
# Dashboard
brew-logs dashboard                # Full graphical status & stats dashboard

# View logs
brew-logs                          # Show latest detail log (default)
brew-logs detail                   # Same as above
brew-logs detail last 5            # Show the 5 most recent detail logs
brew-logs summary                  # Show latest summary log
brew-logs summary today            # Show today's summary specifically
brew-logs summary last 7           # Show the last 7 days of summaries
brew-logs summary 2026-03          # Show all March 2026 summaries

# Troubleshooting
brew-logs errors                   # Grep errors/warnings across all detail logs
brew-logs tail                     # Live-follow the latest detail log (Ctrl+C to stop)

# Status and management
brew-logs status                   # Daemon status, log counts, disk usage
brew-logs list                     # List all log files with sizes and dates
brew-logs list detail              # List only detail log files
brew-logs list summary             # List only summary log files

# Configuration
brew-logs config                   # Show all configuration values with types
brew-logs config get KEY           # Show current value for a specific key
brew-logs config set KEY VALUE     # Set a configuration value
brew-logs config reset KEY         # Reset a key to its factory default

# Schedule
brew-logs schedule                 # Show current schedule and next run time
brew-logs schedule reload          # Apply schedule changes from config.conf

# Manual trigger
brew-logs run                      # Run an update cycle immediately
```

### Command Aliases

For quick terminal use, all commands have short aliases:

| Full | Alias |
|------|-------|
| `dashboard` | `dash` |
| `detail` | `d` |
| `summary` | `s` |
| `errors` | `e` |
| `tail` | `t` |
| `status` | `st` |
| `list` | `ls` |
| `config` | `c` |
| `schedule` | `sched` |
| `run` | `r` |
| `help` | `h` |

## Configuration

All settings are in `~/.config/brew-autoupdate/config.conf`. Changes take effect on the next run — no daemon restart needed.

Format: `KEY=value`. Inline comments are supported when preceded by a space (`KEY=value #comment`). A `#` within a value with no leading space is preserved (e.g., URLs with fragments).

### Settings Reference

#### Log Retention

| Setting | Default | Description |
|---------|---------|-------------|
| `DETAIL_LOG_RETENTION_DAYS` | `90` | Days to keep verbose detail logs |
| `SUMMARY_LOG_RETENTION_DAYS` | `365` | Days to keep summary update logs |

#### Notifications

| Setting | Default | Description |
|---------|---------|-------------|
| `NOTIFY_ON_EVERY_RUN` | `true` | macOS notification after each run |
| `NOTIFY_ON_ERROR` | `true` | macOS notification when errors occur |

**Recommended workflow:**
1. Leave `NOTIFY_ON_EVERY_RUN=true` for the first few days to verify the daemon runs
2. Once satisfied, set it to `false` to reduce notification noise
3. Keep `NOTIFY_ON_ERROR=true` permanently

#### Update Behavior

| Setting | Default | Description |
|---------|---------|-------------|
| `AUTO_UPGRADE` | `true` | Run `brew upgrade` to install newer versions |
| `AUTO_CLEANUP` | `true` | Run `brew cleanup` to remove old versions |
| `CLEANUP_OLDER_THAN_DAYS` | `0` | Cache cleanup threshold (0 = brew default: 120 days) |
| `AUTO_REMOVE` | `true` | Run `brew autoremove` to remove orphaned deps |
| `UPGRADE_CASKS` | `true` | Include GUI application (cask) upgrades |
| `UPGRADE_CASKS_GREEDY` | `false` | Also upgrade self-updating casks (Chrome, etc.) |

#### Package Filtering

| Setting | Default | Description |
|---------|---------|-------------|
| `DENY_LIST` | *(empty)* | Space-separated packages to never auto-upgrade |
| `ALLOW_LIST` | *(empty)* | If set, only these packages are upgraded (whitelist mode) |

#### Hooks

| Setting | Default | Description |
|---------|---------|-------------|
| `PRE_UPDATE_HOOK` | *(empty)* | Shell command to run before each update cycle |
| `POST_UPDATE_HOOK` | *(empty)* | Shell command to run after each update cycle |

#### Quiet Hours

| Setting | Default | Description |
|---------|---------|-------------|
| `QUIET_HOURS_ENABLED` | `false` | Skip scheduled updates during the quiet window |
| `QUIET_HOURS_START` | `09:00` | Start of quiet window (24-hour HH:MM format) |
| `QUIET_HOURS_END` | `18:00` | End of quiet window (supports overnight ranges) |

#### Schedule

| Setting | Default | Description |
|---------|---------|-------------|
| `SCHEDULE_HOURS` | `0,6,12,18` | Comma-separated hours (0-23) to run updates |
| `SCHEDULE_MINUTE` | `0` | Minute within each scheduled hour (0-59) |

#### Advanced

| Setting | Default | Description |
|---------|---------|-------------|
| `BREW_PATH` | *(empty)* | Override path to brew binary (auto-detected if empty) |
| `BREW_ENV` | *(empty)* | Extra env vars, e.g., `HOMEBREW_NO_ANALYTICS=1` |

### Editing Configuration via CLI

You can manage all settings from the terminal without editing files directly:

```bash
brew-logs config                              # Show all settings with types and defaults
brew-logs config get DENY_LIST                # Get a single value
brew-logs config set AUTO_UPGRADE false       # Set a value (validated by type)
brew-logs config set DENY_LIST "node python"  # Space-separated package list
brew-logs config reset UPGRADE_CASKS_GREEDY   # Reset to factory default
```

Values are validated by type (bool, int, time, string) before being written. A `*` marker in the config display indicates values that differ from their factory default.

## Schedule

The daemon runs at **12:00 AM, 6:00 AM, 12:00 PM, and 6:00 PM** daily by default.

### Changing the Schedule

Edit the schedule settings in `config.conf`, then reload:

```bash
brew-logs config set SCHEDULE_HOURS "7,13,21"   # 3x daily at 7 AM, 1 PM, 9 PM
brew-logs config set SCHEDULE_MINUTE 30          # Run at :30 instead of :00
brew-logs schedule reload                        # Regenerate the plist and reload daemon
```

You can also view the current schedule and next run time:

```bash
brew-logs schedule                               # Show schedule and next run time
```

### Sleep/Wake Behavior

macOS `StartCalendarInterval` jobs that were missed during sleep will run once the system wakes. If multiple scheduled times passed during sleep, only one run will execute (the lock file prevents concurrent runs).

## Daemon Management

```bash
# Check if daemon is running
brew-logs status
# — or —
launchctl list com.user.brew-autoupdate

# Stop the daemon (persists across reboots — stays stopped)
launchctl unload ~/Library/LaunchAgents/com.user.brew-autoupdate.plist

# Start the daemon
launchctl load -w ~/Library/LaunchAgents/com.user.brew-autoupdate.plist

# Trigger an immediate run (in addition to scheduled runs)
brew-logs run
```

## Installation

### Install

```bash
bash install.sh
```

### Uninstall

Removes all components except log files (which may contain useful history):

```bash
bash install.sh --uninstall
```

To also remove logs:

```bash
rm -rf ~/Library/Logs/brew-autoupdate
```

### Reinstall

Full uninstall followed by fresh install (resets config to defaults):

```bash
bash install.sh --reinstall
```

## Troubleshooting

### Daemon isn't running

```bash
# Check status
brew-logs status

# Check launchd errors
cat ~/Library/Logs/brew-autoupdate/launchd-stderr.log

# Reload
launchctl unload ~/Library/LaunchAgents/com.user.brew-autoupdate.plist
launchctl load -w ~/Library/LaunchAgents/com.user.brew-autoupdate.plist
```

### No notifications appearing

1. Check System Settings > Notifications > Script Editor — ensure notifications are enabled
2. Verify `NOTIFY_ON_EVERY_RUN=true` in config: `brew-logs config`
3. Check that Focus/Do Not Disturb mode isn't blocking notifications
4. Run manually to test: `brew-logs run`

### Brew commands failing

```bash
# Check recent errors
brew-logs errors

# View the full detail log for the latest run
brew-logs detail

# Run brew doctor manually for diagnostics
brew doctor
```

### Stale lock file

If the script was killed mid-run, a stale lock file may remain. The script automatically detects and cleans stale locks, but you can also remove it manually:

```bash
rm -f /tmp/brew-autoupdate.lock
```

### Disk usage growing

Check current usage and adjust retention:

```bash
brew-logs status          # Shows disk usage
brew-logs config          # Shows retention settings
```

Edit `~/.config/brew-autoupdate/config.conf` to lower retention days if needed.

## Architecture

```
~/.config/brew-autoupdate/
├── brew-autoupdate.sh          # Main update engine
├── brew-autoupdate-viewer.sh   # Log viewer (symlinked as brew-logs)
└── config.conf                 # All configuration

~/Library/LaunchAgents/
└── com.user.brew-autoupdate.plist   # launchd schedule

~/Library/Logs/brew-autoupdate/
├── detail/                     # Verbose per-run logs (90-day default)
│   ├── 2026-03-30_00-00-01.log
│   ├── 2026-03-30_06-00-01.log
│   ├── 2026-03-30_12-00-01.log
│   └── 2026-03-30_18-00-01.log
├── summary/                    # Concise per-day logs (365-day default)
│   └── 2026-03-30.log
├── launchd-stdout.log          # launchd-captured stdout
└── launchd-stderr.log          # launchd-captured stderr
```

## Requirements

- **macOS** (tested on macOS 13+, should work on 10.15+)
- **Homebrew** (https://brew.sh)
- **bash 3.2+** (ships with macOS)

## License

MIT
