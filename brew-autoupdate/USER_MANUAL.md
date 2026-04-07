# Homebrew Auto-Update User Manual

**Version 2.2.0**

A complete guide to installing, configuring, and managing the Homebrew Auto-Update system for macOS.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Getting Started](#getting-started)
5. [The Dashboard](#the-dashboard)
6. [Viewing Logs](#viewing-logs)
7. [Configuration](#configuration)
8. [Schedule Management](#schedule-management)
9. [Package Filtering](#package-filtering)
10. [Quiet Hours](#quiet-hours)
11. [Hooks](#hooks)
12. [Notifications](#notifications)
13. [Log Level](#log-level)
14. [Config Export / Import](#config-export--import)
15. [Daemon Management](#daemon-management)
16. [Uninstalling](#uninstalling)
17. [Troubleshooting](#troubleshooting)
18. [Architecture Reference](#architecture-reference)
19. [Command Reference](#command-reference)
20. [Configuration Reference](#configuration-reference)
21. [Appendix: Alphabetical Command Index](#appendix-alphabetical-command-index)

---

## Introduction

Homebrew Auto-Update is a background daemon for macOS that automatically keeps your Homebrew packages up to date. It runs silently via macOS's native `launchd` scheduler, performing a full maintenance cycle on a configurable schedule.

Each run executes the following steps:

1. **`brew update`** -- Fetch the latest formulae and cask definitions
2. **`brew outdated`** -- Identify which packages need updating
3. **`brew upgrade`** -- Install newer versions (respecting allow/deny filters)
4. **`brew cleanup`** -- Remove old versions and stale downloads
5. **`brew autoremove`** -- Remove orphaned dependencies
6. **`brew doctor`** -- Run diagnostic health checks
7. **Log rotation** -- Prune logs that exceed the configured retention period

Each step is independently error-handled. A failure in one step does not prevent subsequent steps from running.

All interaction is through the `brew-logs` command, which is installed into your PATH during setup.

---

## Requirements

- **macOS 10.15+** (tested on macOS 13 and later)
- **Homebrew** -- install from [https://brew.sh](https://brew.sh) if you haven't already
- **bash 3.2+** -- ships with macOS by default
- Your user account must be **logged in** for the daemon to run (it's a per-user `launchd` agent, not a system-wide daemon)

---

## Installation

### Standard Install

```bash
cd brew-autoupdate
bash install.sh
```

The installer will:

1. Verify that macOS and Homebrew are present
2. Create the configuration directory at `~/.config/brew-autoupdate/`
3. Copy scripts, the installer, and the default configuration file
4. Generate a `launchd` plist from the schedule settings in `config.conf`
5. Set proper file permissions
6. Create a `brew-logs` symlink in Homebrew's `bin/` directory
7. Create log directories under `~/Library/Logs/brew-autoupdate/`
8. Load the `launchd` daemon to begin scheduled operation
9. Offer to run a verification test immediately

The installer is **idempotent** -- running it again is safe. An existing `config.conf` is preserved so your customizations are not overwritten. A `config.conf.new` file is saved alongside it for reference.

### Reinstall (Fresh Config)

If you want to start over with a clean configuration:

```bash
bash install.sh --reinstall
```

This performs a full uninstall followed by a fresh install.

### Upgrading

To apply script updates without losing your configuration, re-run the standard install:

```bash
cd brew-autoupdate
bash install.sh
```

Your `config.conf` is preserved automatically.

---

## Getting Started

After installation, verify everything is working:

```bash
# Check that the daemon is loaded
brew-logs status

# View the dashboard for a full overview
brew-logs dashboard

# Trigger a manual run to see it in action
brew-logs run

# View the results
brew-logs detail
```

### Recommended First Steps

1. **Leave notifications on.** The default `NOTIFY_ON_EVERY_RUN=true` sends a macOS notification after every run. Keep this on for the first few days to confirm the daemon is working as expected.

2. **Review the schedule.** The default schedule runs 4 times daily at 12:00 AM, 6:00 AM, 12:00 PM, and 6:00 PM. Adjust it if this doesn't suit your workflow (see [Schedule Management](#schedule-management)).

3. **Check the dashboard.** Run `brew-logs dashboard` to see a graphical overview of daemon status, recent runs, cumulative statistics, and your most frequently updated packages.

4. **Once satisfied, reduce notification noise.** After a few days of confirmed operation:
   ```bash
   brew-logs config set NOTIFY_ON_EVERY_RUN false
   ```
   Keep `NOTIFY_ON_ERROR=true` permanently so you're alerted to problems.

---

## The Dashboard

The dashboard provides a full-terminal graphical overview of your auto-update system.

```bash
brew-logs dashboard
# or
brew-logs dash
```

The dashboard displays:

- **Daemon Status** -- Whether the daemon is active or not loaded, last run time and result, duration
- **Schedule** -- Current run times, next scheduled run with countdown, quiet hours status
- **Recent Runs** -- A table of the last 8 runs with timestamp, duration, status, and upgrade count
- **Cumulative Statistics** -- Total runs, success rate, error count, average duration, total upgrades, unique packages
- **Top Packages** -- A bar chart of your most frequently updated packages
- **Configuration** -- Current settings at a glance (upgrade/cleanup/cask flags, deny/allow lists, notifications)

The dashboard adapts to your terminal width (minimum 72 columns).

---

## Viewing Logs

The logging system uses two tiers to balance troubleshooting capability with long-term history.

### Detail Logs

One file per run, containing full `brew` command output, configuration dumps, and diagnostics. Stored in `~/Library/Logs/brew-autoupdate/detail/`.

```bash
# View the latest detail log
brew-logs detail
# or simply
brew-logs

# View the 5 most recent detail logs
brew-logs detail last 5
```

### Summary Logs

One file per day, containing high-level milestones: start/stop times, what was outdated, what changed, and any errors. Stored in `~/Library/Logs/brew-autoupdate/summary/`.

```bash
# View the latest summary
brew-logs summary

# View today's summary
brew-logs summary today

# View the last 7 days of summaries
brew-logs summary last 7

# View all summaries for a specific month
brew-logs summary 2026-03
```

### Error Search

Quickly find errors and warnings across all detail logs:

```bash
brew-logs errors
```

### Live Tail

Follow the latest detail log in real time (useful during a manual run):

```bash
brew-logs tail
```

Press `Ctrl+C` to stop.

### Listing Log Files

```bash
# List all log files with sizes and dates
brew-logs list

# List only detail logs
brew-logs list detail

# List only summary logs
brew-logs list summary
```

### Log Retention

Logs are automatically pruned at the end of each update cycle. The default retention periods are:

- **Detail logs:** 90 days (~360 files at 4 runs/day)
- **Summary logs:** 365 days (~365 files)

To change retention:

```bash
brew-logs config set DETAIL_LOG_RETENTION_DAYS 30
brew-logs config set SUMMARY_LOG_RETENTION_DAYS 180
```

### Console.app

Because logs are stored under `~/Library/Logs/`, they are also browsable in macOS Console.app under "Log Reports."

---

## Configuration

All settings live in a single file: `~/.config/brew-autoupdate/config.conf`. Changes take effect on the next run -- no daemon restart is needed (except for schedule changes, which require a reload).

### Viewing Configuration

```bash
# Show all settings with types and current values
brew-logs config

# Show a specific setting
brew-logs config get UPGRADE_CASKS
```

The config display shows each key's name, current value, data type, and marks values that differ from the factory default with a `*`.

### Changing Settings

```bash
brew-logs config set KEY VALUE
```

Values are validated by type before being written:

| Type | Validation | Examples |
|------|-----------|----------|
| `bool` | Must be `true` or `false` | `AUTO_UPGRADE`, `NOTIFY_ON_ERROR` |
| `int` | Must be a non-negative integer | `DETAIL_LOG_RETENTION_DAYS`, `SCHEDULE_MINUTE` |
| `time` | Must be `HH:MM` format (24-hour) | `QUIET_HOURS_START`, `QUIET_HOURS_END` |
| `loglevel` | Must be `DEBUG`, `INFO`, `WARN`, `ERROR`, or `CRITICAL` | `LOG_LEVEL` |
| `string` | Any value accepted | `DENY_LIST`, `BREW_PATH`, `PRE_UPDATE_HOOK` |

Examples:

```bash
brew-logs config set AUTO_UPGRADE false
brew-logs config set CLEANUP_OLDER_THAN_DAYS 60
brew-logs config set QUIET_HOURS_START 08:30
brew-logs config set DENY_LIST "node python@3.11 postgresql"
```

### Resetting to Defaults

```bash
# Reset a single key to its factory default
brew-logs config reset UPGRADE_CASKS_GREEDY

# Check what the default is
brew-logs config get UPGRADE_CASKS_GREEDY
```

### Editing the File Directly

You can also edit the config file directly in any text editor:

```bash
open ~/.config/brew-autoupdate/config.conf
# or
nano ~/.config/brew-autoupdate/config.conf
```

The file format is `KEY=value` with blank lines and comments supported. Comment rules:

- Lines starting with `#` are full-line comments
- Inline comments are supported when preceded by a space: `KEY=value #comment`
- A `#` within a value with no leading space is preserved: `KEY=https://example.com/path#fragment`

---

## Schedule Management

### Viewing the Schedule

```bash
brew-logs schedule
```

This shows the currently configured run times and when the next run will occur.

### Changing the Schedule

Edit the schedule settings, then reload:

```bash
# Set to run 3 times daily at 7 AM, 1 PM, and 9 PM
brew-logs config set SCHEDULE_HOURS "7,13,21"

# Optionally change the minute (default is :00)
brew-logs config set SCHEDULE_MINUTE 15

# Apply the changes (regenerates the launchd plist and reloads the daemon)
brew-logs schedule reload
```

Schedule changes are the **only** settings that require a reload. All other settings take effect automatically on the next run.

### Common Schedule Presets

| Schedule | `SCHEDULE_HOURS` value |
|----------|----------------------|
| Once daily at 3 AM | `3` |
| Twice daily (3 AM and 3 PM) | `3,15` |
| Four times daily (default) | `0,6,12,18` |
| Every 3 hours | `0,3,6,9,12,15,18,21` |
| Every 2 hours | `0,2,4,6,8,10,12,14,16,18,20,22` |

### Sleep/Wake Behavior

macOS `StartCalendarInterval` jobs that are missed during sleep will run once the system wakes. If multiple scheduled times passed while asleep, only one run executes (the lock file prevents concurrent runs).

---

## Package Filtering

Control which packages are eligible for automatic upgrades using deny lists and allow lists.

### Deny List (Blacklist)

Packages in the deny list are **never** auto-upgraded. They stay at their current version until you manually run `brew upgrade <package>`. This is useful for pinning critical or potentially breaking packages.

```bash
brew-logs config set DENY_LIST "node python@3.11 postgresql"
```

### Allow List (Whitelist)

When set, **only** packages in the allow list are auto-upgraded. Everything else is skipped. Leave empty (default) to upgrade all eligible packages.

```bash
brew-logs config set ALLOW_LIST "git wget curl openssl"
```

### Filtering Rules

- Names must exactly match the Homebrew formula or cask name
- The deny list takes priority: a package in both lists is always skipped
- Filtering only applies when `AUTO_UPGRADE=true`
- Filtering is logged in detail logs (look for `DENY_LIST: skipping` or `ALLOW_LIST: skipping`)

### Clearing Filters

```bash
brew-logs config set DENY_LIST ""
brew-logs config set ALLOW_LIST ""
```

---

## Quiet Hours

Suppress automatic updates during specified hours. This is useful if you don't want background upgrades during work hours or while running presentations.

### Enabling Quiet Hours

```bash
brew-logs config set QUIET_HOURS_ENABLED true
brew-logs config set QUIET_HOURS_START 09:00
brew-logs config set QUIET_HOURS_END 18:00
```

When a scheduled run fires during the quiet window, it is silently skipped and logged as `SKIP: Quiet hours active`.

### Overnight Ranges

Overnight ranges work correctly. For example, to suppress updates from 10 PM to 7 AM:

```bash
brew-logs config set QUIET_HOURS_START 22:00
brew-logs config set QUIET_HOURS_END 07:00
```

### Manual Runs

Manual runs (`brew-logs run`) are **never** affected by quiet hours. They always execute regardless of the current time.

### Disabling Quiet Hours

```bash
brew-logs config set QUIET_HOURS_ENABLED false
```

---

## Hooks

Run custom shell commands before and/or after each update cycle.

### Pre-Update Hook

Runs before any `brew` operations begin:

```bash
brew-logs config set PRE_UPDATE_HOOK "echo 'Starting update' >> ~/brew-hook.log"
```

### Post-Update Hook

Runs after all `brew` operations complete (including on errors):

```bash
brew-logs config set POST_UPDATE_HOOK "/Users/me/scripts/notify-slack.sh"
```

### How Hooks Work

- Commands are executed via `bash -c`, so any valid shell syntax works
- A non-zero exit code from a hook is logged as a warning but does **not** abort the update cycle
- Hook output is captured in the detail log
- The post-update hook runs even if earlier steps encountered errors

### Use Cases

- **Health check pings:** `POST_UPDATE_HOOK=curl -fsS https://hc-ping.com/YOUR-UUID > /dev/null`
- **Custom logging:** `PRE_UPDATE_HOOK=date >> ~/brew-update-log.txt`
- **Slack/webhook notifications:** `POST_UPDATE_HOOK=/path/to/your/script.sh`
- **Time Machine snapshot:** `PRE_UPDATE_HOOK=tmutil localsnapshot`

### Clearing Hooks

```bash
brew-logs config set PRE_UPDATE_HOOK ""
brew-logs config set POST_UPDATE_HOOK ""
```

---

## Notifications

macOS Notification Center alerts keep you informed about update activity.

### Notification Types

| Setting | Default | Purpose |
|---------|---------|---------|
| `NOTIFY_ON_EVERY_RUN` | `true` | Shows a notification after every run (success or no updates) |
| `NOTIFY_ON_ERROR` | `true` | Shows a notification when errors occur |

Error notifications include the error details and a pointer to the detail log.

Success notifications report the duration and number of packages upgraded.

### Configuring Notifications

```bash
# Turn off every-run notifications (recommended after initial verification)
brew-logs config set NOTIFY_ON_EVERY_RUN false

# Keep error notifications on (recommended permanently)
brew-logs config set NOTIFY_ON_ERROR true
```

### Notifications Not Appearing?

1. Check **System Settings > Notifications > Script Editor** -- ensure notifications are allowed
2. Verify the setting is enabled: `brew-logs config get NOTIFY_ON_EVERY_RUN`
3. Check that **Focus / Do Not Disturb** mode isn't blocking them
4. Run `brew-logs run` to trigger a test notification

---

## Log Level

Control the verbosity of log output with the `LOG_LEVEL` setting. This determines the minimum severity of messages written to both detail and summary logs.

### Severity Levels

| Level | Numeric | What Gets Logged |
|-------|---------|------------------|
| `DEBUG` | 0 | Everything: config dumps, brew command output, filtering decisions, rotation details |
| `INFO` | 1 | Normal operation: start/stop, completions, what changed, outdated packages |
| `WARN` | 2 | Warnings: non-fatal errors, hook failures, upgrade issues, stale locks |
| `ERROR` | 3 | Errors: step failures that affect the update cycle |
| `CRITICAL` | 4 | Critical errors only (e.g., Homebrew not found) |

### Setting the Log Level

```bash
# Default: INFO (recommended for normal use)
brew-logs config set LOG_LEVEL INFO

# Maximum verbosity for troubleshooting
brew-logs config set LOG_LEVEL DEBUG

# Quiet: only warnings and errors
brew-logs config set LOG_LEVEL WARN

# Minimal: only errors
brew-logs config set LOG_LEVEL ERROR
```

### Important Notes

- **Structured data is always written.** The `[STATS]` and `[PKG]` lines used by the dashboard are always appended to summary logs regardless of `LOG_LEVEL`. This ensures dashboard statistics are always available even at `ERROR` or `CRITICAL` level.
- **Recommended workflow:** Use `INFO` for normal operation, switch to `DEBUG` temporarily when troubleshooting issues.
- Log entries include the severity tag in the format: `[2026-04-07 12:00:01] [INFO] message`

---

## Config Export / Import

Transfer your configuration between systems or create backups using export and import.

### Exporting Configuration

```bash
# Export to default location (~/brew-autoupdate-config-export.conf)
brew-logs config export

# Export to a specific file
brew-logs config export ~/Desktop/my-brew-config.conf
```

The export file includes:
- A metadata header with the export timestamp, hostname, macOS version, architecture, and tool version
- All current configuration key/value pairs

### Importing Configuration

```bash
# Import from a file
brew-logs config import ~/Desktop/my-brew-config.conf

# Import from an export created on another machine
brew-logs config import /Volumes/USB/brew-config.conf
```

During import:
- Each key is validated before being written
- Unknown keys are skipped with a warning
- Invalid values are reported as errors
- A summary shows how many settings were applied, skipped, and errored
- Schedule changes still require `brew-logs schedule reload` after import

### Multi-System Workflow

```bash
# On your primary Mac:
brew-logs config export ~/Dropbox/brew-autoupdate.conf

# On a new Mac (after installing brew-autoupdate):
brew-logs config import ~/Dropbox/brew-autoupdate.conf
brew-logs schedule reload   # if schedule was customized
```

---

## Daemon Management

The auto-update system runs as a per-user `launchd` agent. It starts automatically when you log in and persists across reboots.

### Checking Status

```bash
# Recommended: shows daemon status, log counts, disk usage, and last run time
brew-logs status

# Direct launchd query
launchctl list com.user.brew-autoupdate
```

### Stopping the Daemon

```bash
launchctl unload ~/Library/LaunchAgents/com.user.brew-autoupdate.plist
```

This persists across reboots -- the daemon stays stopped until you start it again.

### Starting the Daemon

```bash
launchctl load -w ~/Library/LaunchAgents/com.user.brew-autoupdate.plist
```

### Triggering a Manual Run

Run an update cycle immediately (in addition to the scheduled runs):

```bash
brew-logs run
```

This runs in the foreground so you can see the output. Manual runs are not affected by quiet hours.

---

## Uninstalling

### Remove All Components (Preserve Logs)

```bash
cd brew-autoupdate
bash install.sh --uninstall
```

This removes scripts, configuration, the daemon plist, and the `brew-logs` command. Log files are preserved in case they contain useful history.

### Also Remove Logs

```bash
rm -rf ~/Library/Logs/brew-autoupdate
```

---

## Troubleshooting

### The daemon isn't running

```bash
# Check daemon status
brew-logs status

# Check for launchd-level errors
cat ~/Library/Logs/brew-autoupdate/launchd-stderr.log

# Reload the daemon
launchctl unload ~/Library/LaunchAgents/com.user.brew-autoupdate.plist
launchctl load -w ~/Library/LaunchAgents/com.user.brew-autoupdate.plist
```

### Brew commands are failing

```bash
# Check recent errors across all logs
brew-logs errors

# View the full detail log for the most recent run
brew-logs detail

# Run Homebrew's own diagnostics
brew doctor
```

### Stale lock file

If the script was killed mid-run, a stale lock file may remain. The script automatically detects and cleans stale locks on the next run, but you can also remove it manually:

```bash
rm -f /tmp/brew-autoupdate.lock
```

### Disk usage is growing

```bash
# Check current disk usage
brew-logs status

# Check current retention settings
brew-logs config get DETAIL_LOG_RETENTION_DAYS
brew-logs config get SUMMARY_LOG_RETENTION_DAYS

# Lower retention if needed
brew-logs config set DETAIL_LOG_RETENTION_DAYS 30
```

### Updates seem to be skipped

If updates aren't running when expected:

1. **Quiet hours:** Check if quiet hours are enabled and overlapping your schedule.
   ```bash
   brew-logs config get QUIET_HOURS_ENABLED
   brew-logs config get QUIET_HOURS_START
   brew-logs config get QUIET_HOURS_END
   ```

2. **Auto-upgrade disabled:** Check that upgrades are enabled.
   ```bash
   brew-logs config get AUTO_UPGRADE
   ```

3. **Package filtering:** Check if deny/allow lists are filtering out everything.
   ```bash
   brew-logs config get DENY_LIST
   brew-logs config get ALLOW_LIST
   ```

4. **Mac was asleep:** If your Mac was asleep during all scheduled times, updates run on wake. Check the latest log timestamp.

### Schedule changes aren't taking effect

Schedule changes require a reload after updating the config:

```bash
brew-logs schedule reload
```

Other settings take effect automatically on the next run.

---

## Architecture Reference

### Installed Files

```
~/.config/brew-autoupdate/
  brew-autoupdate.sh            Main update engine
  brew-autoupdate-viewer.sh     Log viewer CLI (symlinked as brew-logs)
  install.sh                    Installer (also used by schedule reload)
  config.conf                   All configuration settings

~/Library/LaunchAgents/
  com.user.brew-autoupdate.plist   launchd daemon definition

~/Library/Logs/brew-autoupdate/
  detail/                       Verbose per-run logs (one file per run)
    2026-04-06_00-00-01.log
    2026-04-06_06-00-01.log
    2026-04-06_12-00-01.log
    2026-04-06_18-00-01.log
  summary/                      Concise per-day logs (one file per day)
    2026-04-06.log
  launchd-stdout.log            launchd-captured stdout
  launchd-stderr.log            launchd-captured stderr

$(brew --prefix)/bin/
  brew-logs                     Symlink to brew-autoupdate-viewer.sh
```

### How the Daemon Works

The system uses macOS `launchd` (not `cron`) for scheduling. The plist file at `~/Library/LaunchAgents/com.user.brew-autoupdate.plist` defines:

- **Label:** `com.user.brew-autoupdate` (unique identifier)
- **Schedule:** `StartCalendarInterval` entries generated from `SCHEDULE_HOURS` and `SCHEDULE_MINUTE`
- **Priority:** Low I/O priority, nice value 10, `ProcessType: Background`
- **Environment:** Explicit `PATH` covering both Apple Silicon (`/opt/homebrew/`) and Intel (`/usr/local/`) Homebrew installations

The daemon runs as a user agent in your GUI session (not system-wide), so it only operates when you are logged in.

### Concurrency Safety

A lock file at `/tmp/brew-autoupdate.lock` is acquired atomically to prevent overlapping runs. On each start:

1. The script attempts an atomic lock-file create (no check-then-write race)
2. If the lock already exists and PID is alive, the run is skipped (`SKIP: Another instance ... is already running`)
3. If the PID is dead, the stale lock is removed and lock acquisition is retried
4. The lock is cleaned up automatically via a `trap` handler on exit

### Summary Log Structured Data

Summary logs include machine-parseable lines used by the dashboard:

- **`[STATS]`** lines: `duration=47 status=SUCCESS upgrades=3` -- per-run metrics
- **`[PKG]`** lines: `[PKG] wget` -- individual package upgrade records for frequency tracking

---

## Command Reference

All commands are invoked as `brew-logs <command>`. Running `brew-logs` with no arguments defaults to showing the latest detail log.

| Command | Alias | Description |
|---------|-------|-------------|
| `dashboard` | `dash` | Full graphical status and statistics dashboard |
| `detail [latest\|last N]` | `d` | Show detail log(s) |
| `summary [latest\|today\|last N\|DATE]` | `s` | Show summary log(s) |
| `errors` | `e` | Search for errors/warnings across all detail logs |
| `tail` | `t` | Live-follow the latest detail log |
| `status` | `st` | Show daemon status, log counts, disk usage |
| `list [detail\|summary]` | `ls` | List all log files with sizes and dates |
| `config` | `c` | Show all configuration values with types |
| `config get KEY` | | Show the current value and type for a key |
| `config set KEY VALUE` | | Set a configuration value (validated) |
| `config reset KEY` | | Reset a key to its factory default |
| `config export [FILE]` | | Export config to file for backup or transfer |
| `config import FILE` | | Import config from an export file |
| `schedule [show]` | `sched` | Show current schedule and next run time |
| `schedule reload` | | Regenerate plist and reload daemon with new schedule |
| `run` | `r` | Trigger a manual update cycle (foreground) |
| `help` | `h` | Show built-in help text |

---

## Configuration Reference

Complete list of all settings, their types, default values, and descriptions.

### Log Level

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `LOG_LEVEL` | loglevel | `INFO` | Minimum log severity: `DEBUG`, `INFO`, `WARN`, `ERROR`, `CRITICAL` |

### Log Retention

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `DETAIL_LOG_RETENTION_DAYS` | int | `90` | Days to keep verbose detail logs |
| `SUMMARY_LOG_RETENTION_DAYS` | int | `365` | Days to keep summary update logs |

### Notifications

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `NOTIFY_ON_EVERY_RUN` | bool | `true` | macOS notification after each run |
| `NOTIFY_ON_ERROR` | bool | `true` | macOS notification when errors occur |

### Update Behavior

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `AUTO_UPGRADE` | bool | `true` | Run `brew upgrade` to install newer versions |
| `AUTO_CLEANUP` | bool | `true` | Run `brew cleanup` to remove old versions |
| `CLEANUP_OLDER_THAN_DAYS` | int | `0` | Cache cleanup threshold in days (0 = brew default of 120 days) |
| `AUTO_REMOVE` | bool | `true` | Run `brew autoremove` to remove orphaned deps |
| `UPGRADE_CASKS` | bool | `true` | Include GUI application (cask) upgrades |
| `UPGRADE_CASKS_GREEDY` | bool | `false` | Also upgrade self-updating casks (Chrome, Firefox, etc.) |

### Package Filtering

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `DENY_LIST` | string | *(empty)* | Space-separated packages to never auto-upgrade |
| `ALLOW_LIST` | string | *(empty)* | If set, only these packages are upgraded |

### Hooks

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `PRE_UPDATE_HOOK` | string | *(empty)* | Shell command to run before each update cycle |
| `POST_UPDATE_HOOK` | string | *(empty)* | Shell command to run after each update cycle |

### Quiet Hours

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `QUIET_HOURS_ENABLED` | bool | `false` | Skip scheduled updates during the quiet window |
| `QUIET_HOURS_START` | time | `09:00` | Start of quiet window (24-hour HH:MM) |
| `QUIET_HOURS_END` | time | `18:00` | End of quiet window (supports overnight ranges) |

### Schedule

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `SCHEDULE_HOURS` | string | `0,6,12,18` | Comma-separated hours (0-23) to run updates |
| `SCHEDULE_MINUTE` | int | `0` | Minute within each scheduled hour (0-59) |

### Advanced

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `BREW_PATH` | string | *(empty)* | Override path to brew binary (auto-detected if empty) |
| `BREW_ENV` | string | *(empty)* | Extra env vars for brew, e.g. `HOMEBREW_NO_ANALYTICS=1` |

---

## Appendix: Alphabetical Command Index

A flat, alphabetical list of every `brew-logs` command and subcommand for quick lookup.

| Command | Alias | Description |
|---------|-------|-------------|
| `brew-logs` | | Show the latest detail log (same as `brew-logs detail`) |
| `brew-logs config` | `brew-logs c` | Show all configuration values with types and defaults |
| `brew-logs config export [FILE]` | | Export all configuration to a file (default: `~/brew-autoupdate-config-export.conf`) |
| `brew-logs config get KEY` | | Show the current value, type, and default for a single key |
| `brew-logs config import FILE` | | Import configuration from an export file (validates each key) |
| `brew-logs config reset KEY` | | Reset a key to its factory default value |
| `brew-logs config set KEY VALUE` | | Set a configuration value (validated by type before writing) |
| `brew-logs dashboard` | `brew-logs dash` | Full-terminal graphical dashboard with status, stats, and charts |
| `brew-logs detail` | `brew-logs d` | Show the latest detail log |
| `brew-logs detail last N` | `brew-logs d last N` | Show the N most recent detail logs |
| `brew-logs errors` | `brew-logs e` | Search for errors and warnings across all detail logs |
| `brew-logs help` | `brew-logs h` | Show built-in help text with all commands and examples |
| `brew-logs list` | `brew-logs ls` | List all log files (detail and summary) with sizes and dates |
| `brew-logs list detail` | `brew-logs ls detail` | List only detail log files |
| `brew-logs list summary` | `brew-logs ls summary` | List only summary log files |
| `brew-logs run` | `brew-logs r` | Trigger a manual update cycle in the foreground |
| `brew-logs schedule` | `brew-logs sched` | Show current schedule, run times, and next run countdown |
| `brew-logs schedule reload` | `brew-logs sched reload` | Regenerate launchd plist from config and reload daemon |
| `brew-logs status` | `brew-logs st` | Show daemon status, log counts, disk usage, and last run time |
| `brew-logs summary` | `brew-logs s` | Show the latest summary log |
| `brew-logs summary DATE` | `brew-logs s DATE` | Show summaries matching a date pattern (e.g., `2026-03`) |
| `brew-logs summary last N` | `brew-logs s last N` | Show the N most recent summary logs |
| `brew-logs summary today` | `brew-logs s today` | Show today's summary log |
| `brew-logs tail` | `brew-logs t` | Live-follow the latest detail log (Ctrl+C to stop) |
