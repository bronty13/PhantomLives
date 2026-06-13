---
title: "launchd for Personal Automation"
part: "P06 Automation"
est_time: "55 min read + 45 min labs"
prerequisites: ["05-launchd-and-the-launch-system", "03-essential-unix-commands", "11-scripting"]
tags: [macos, launchd, launchctl, automation, scheduling, plists, LaunchAgent]
---

# launchd for Personal Automation

> **In one sentence:** launchd is the single scheduler/process supervisor that replaced cron, inetd, and rc on macOS — and once you understand its plist grammar and the modern `launchctl` domain model, you can wire up reliable, headless automation that cron never could.

---

## Why this matters

Every macOS power user eventually reaches for `crontab`. It works — until it doesn't: the job silently skips because the machine was asleep, the environment is wrong so your script can't find `python3`, there's no easy log, and there's no way to react to filesystem events without a polling loop. launchd solves all of these.

The same init/supervisor that boots your machine, keeps `Spotlight` alive, and restarts `bluetoothd` after a crash is available to you as an unprivileged user. Your personal jobs live in `~/Library/LaunchAgents/` and run as your UID — no `sudo`, no root, no crontab. The trigger vocabulary is richer than Task Scheduler's: timed intervals, calendar-based schedules (with missed-run recovery after sleep), filesystem-event watchers, mount-triggered jobs, network-state gates, and keep-alive supervision.

This lesson is the applied companion to [[05-launchd-and-the-launch-system]], which covers the architectural view (bootstrap tokens, the service manager framework, XPC). Here we focus on writing and operating personal jobs end-to-end.

> 🪟 **Windows contrast:** Windows Task Scheduler uses XML-based task definitions with COM-style trigger objects. It has a GUI but its CLI (`schtasks`, `Register-ScheduledTask` in PowerShell) is verbose. launchd is CLI-only and plist-driven, with no GUI — but `launchctl print` gives real-time status and log integration is tighter via `log stream`.

---

## Concepts

### The domain model

launchd organizes jobs into *domains*. You need to know two:

| Domain | Target | Who can write there |
|--------|--------|---------------------|
| `gui/<UID>` | User session (LaunchAgent) | You (your UID) |
| `system` | Root/machine-wide (LaunchDaemon) | root only |

Personal automation always uses `gui/<UID>`. Your UID: `id -u`. Your domain target: `gui/$(id -u)`.

Plists in `~/Library/LaunchAgents/` are loaded into the `gui/<UID>` domain at login. Jobs in `/Library/LaunchAgents/` run for every user but still in their per-user `gui` domain. Jobs in `/Library/LaunchDaemons/` and `/System/Library/LaunchDaemons/` run in the `system` domain as root. For personal automation, stay in `~/Library/LaunchAgents/`.

### Anatomy of a LaunchAgent plist

A minimal job:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.backup.nightly</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/backup.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>   <integer>2</integer>
    <key>Minute</key> <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>/tmp/backup.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/backup.err.log</string>
</dict>
</plist>
```

**Label** is the job's unique identifier. Convention is reverse-DNS: `local.<yourname>.<jobname>` for personal jobs, `com.<company>.<app>` for software. The label is what launchd calls the service; you'll use it in every `launchctl` command.

**ProgramArguments** is an array where index 0 is the executable and the rest are arguments. Do not use `Program` (a single string) unless you have no arguments — `ProgramArguments` is always clearer. **The executable must be a full absolute path and must have its execute bit set** — this is responsible for roughly 40% of all "why won't my job run" failures.

### Trigger keys

#### `StartInterval` — run every N seconds

```xml
<key>StartInterval</key>
<integer>3600</integer>  <!-- every hour -->
```

Simple timer. If the system is asleep when the interval fires, the job runs the next time the machine wakes. There is no missed-run recovery — if your machine sleeps for six hours, you get one run on wake, not six. Use `StartCalendarInterval` if you need "run at least once after a missed window."

#### `StartCalendarInterval` — cron-like, with sleep recovery

```xml
<key>StartCalendarInterval</key>
<dict>
  <key>Hour</key>   <integer>2</integer>
  <key>Minute</key> <integer>30</integer>
</dict>
```

Fields: `Minute` (0–59), `Hour` (0–23), `Day` (1–31), `Weekday` (0–7, 0 and 7 both = Sunday), `Month` (1–12). Omitted fields are wildcards. This matches how cron works — but the crucial difference is **launchd fires missed `StartCalendarInterval` jobs when the machine wakes from sleep**, making it far more reliable than cron on laptops.

**Multiple times via array of dicts:**

```xml
<key>StartCalendarInterval</key>
<array>
  <dict>
    <key>Hour</key>   <integer>9</integer>
    <key>Minute</key> <integer>0</integer>
  </dict>
  <dict>
    <key>Hour</key>   <integer>17</integer>
    <key>Minute</key> <integer>0</integer>
  </dict>
</array>
```

This runs the job at 09:00 and 17:00 every day. You can mix different Weekday values in the array to produce "weekdays only at 09:00" patterns:

```xml
<array>
  <!-- Mon–Fri at 09:00 -->
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer><key>Weekday</key><integer>1</integer></dict>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer><key>Weekday</key><integer>2</integer></dict>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer><key>Weekday</key><integer>3</integer></dict>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer><key>Weekday</key><integer>4</integer></dict>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer><key>Weekday</key><integer>5</integer></dict>
</array>
```

> 🔬 **Forensics note:** The file `/var/db/com.apple.xpc.launchd/disabled.plist` (macOS 10.10+) is a binary plist tracking which services are explicitly disabled via `launchctl disable`. If a job mysteriously never runs after a reboot, check whether the label appears in this file: `plutil -p /var/db/com.apple.xpc.launchd/disabled.plist | grep "local\."`. A stale `true` entry here overrides the plist on disk.

#### `RunAtLoad`

```xml
<key>RunAtLoad</key>
<true/>
```

Fires the job immediately when the plist is bootstrapped (login for agents). Combined with `StartCalendarInterval`, this ensures the job runs on login *and* then on schedule. Use it for "run once now, then on schedule" patterns.

#### `WatchPaths` — filesystem event watcher

```xml
<key>WatchPaths</key>
<array>
  <string>/Users/you/Desktop/Inbox</string>
  <string>/Users/you/Downloads/to-process.flag</string>
</array>
```

launchd uses FSEvents under the hood to monitor the listed paths. When any path is created, deleted, or written to, the job fires. **Important caveat: changes inside subdirectories are NOT detected** — only changes directly to the listed path itself trigger the job. If you need recursive watching, list a specific file or use a helper that creates/touches a sentinel file in the watched directory.

You can watch a directory (change to its direct contents) or a specific file (write, creation, deletion). A common pattern is an "inbox" folder that triggers a processing script.

#### `QueueDirectories` — drain-the-queue watcher

```xml
<key>QueueDirectories</key>
<array>
  <string>/Users/you/Desktop/ProcessQueue</string>
</array>
```

Similar to `WatchPaths`, but launchd only fires the job when the directory is **non-empty**, and it re-fires after `ThrottleInterval` seconds if the directory is still non-empty. The job is responsible for removing each file it processes — fail to do so and launchd will hammer your script in a restart loop every `ThrottleInterval` (default: 10 seconds). This makes `QueueDirectories` a natural "work queue" pattern where your script processes one item, removes it, and exits.

#### `StartOnMount`

```xml
<key>StartOnMount</key>
<true/>
```

Fires the job whenever a new volume is mounted. Useful for "process this SD card on insert" or "auto-backup when backup drive appears" workflows. The job runs once per mount event and must check itself which volume appeared (inspect `/Volumes/` or `diskutil list`).

### KeepAlive — supervision modes

`KeepAlive` turns launchd into a process supervisor (like `systemd` unit `Restart=`). There are two forms:

**Boolean (always restart):**
```xml
<key>KeepAlive</key>
<true/>
```
launchd restarts the job every time it exits, for any reason. Use this for daemons that must always be running (a local server, a background sync agent).

**Dictionary (conditional restart):**
```xml
<key>KeepAlive</key>
<dict>
  <!-- Restart only if the job crashed (non-zero exit from signal) -->
  <key>Crashed</key>
  <true/>

  <!-- Restart only while this path exists -->
  <key>PathState</key>
  <dict>
    <string>/Users/you/.enable-myagent</string>
    <true/>
  </dict>

  <!-- Restart only while network is up -->
  <key>NetworkState</key>
  <true/>

  <!-- Restart only if job exited non-zero (i.e., keep trying until success) -->
  <key>SuccessfulExit</key>
  <false/>
</dict>
```

Key sub-keys:

| Sub-key | Type | Behavior |
|---------|------|----------|
| `SuccessfulExit: true` | bool | Restart unless job exits 0 (keep re-running until it succeeds) |
| `SuccessfulExit: false` | bool | Restart only if job exits non-zero (crash-only supervision) |
| `Crashed: true` | bool | Restart after signal-based exit (crash), not clean exit |
| `NetworkState: true` | bool | Run only when any network interface is up |
| `PathState: {"/path": true}` | dict | Run only while path exists |
| `OtherJobEnabled: {"label": true}` | dict | Run while another service is loaded |

> ⚠️ **ADVANCED:** `KeepAlive: true` with a job that exits immediately creates a tight restart loop. launchd applies a `ThrottleInterval` (default 10 s) but a job that crashes 100 times/minute will still burn CPU and fill logs. Always add proper exit-code logic to scripts supervised this way.

### Capturing output

launchd jobs have no terminal. Without explicit output redirection, stdout and stderr go to `/dev/null` — silently swallowed. Always set:

```xml
<key>StandardOutPath</key>
<string>/Users/you/Library/Logs/myjob.out.log</string>
<key>StandardErrorPath</key>
<string>/Users/you/Library/Logs/myjob.err.log</string>
```

`~/Library/Logs/` is the right place for per-user logs — it appears in Console.app under User Reports. You can also point these to `/tmp/` for ephemeral debugging. Logs are **appended** across runs; rotate them yourself with `logrotate` or a truncation step in your script, or use the Unified Log instead (see [[10-unified-logging-and-diagnostics]]).

### The PATH gotcha — the single biggest source of launchd failures

When you run a script in your shell, `$PATH` might include `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin:/bin:/usr/sbin:/sbin`, and more — inherited from your shell profile. launchd jobs run in a **minimal, clean environment** with a stripped-down PATH:

```
/usr/bin:/bin:/usr/sbin:/sbin
```

That's it. `brew`-installed tools (`rsync` from Homebrew, `python3` from Homebrew, `node`, `git`) are invisible. Your script that works fine in the terminal silently fails because `command not found`.

**Fix: always set `EnvironmentVariables` explicitly:**

```xml
<key>EnvironmentVariables</key>
<dict>
  <key>PATH</key>
  <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  <key>HOME</key>
  <string>/Users/you</string>
  <key>LANG</key>
  <string>en_US.UTF-8</string>
</dict>
```

Or, inside the script itself, source a minimal path setup at the top:

```bash
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
```

The script-level approach is more portable but the plist approach is better for jobs that exec a binary directly (no shell wrapper). Note: `EnvironmentVariables` does **not** support shell globbing or variable expansion — `$HOME` inside the string is a literal `$HOME`, not your home directory.

### WorkingDirectory

```xml
<key>WorkingDirectory</key>
<string>/Users/you/Projects/myproject</string>
```

Sets the CWD for the launched process. Without this, launchd defaults to `/`. Any relative path the script accesses will fail if CWD is `/`, which is why "works in terminal, fails in launchd" is so common.

### ThrottleInterval

```xml
<key>ThrottleInterval</key>
<integer>30</integer>
```

Minimum seconds between job invocations. If the job exits and launchd would immediately re-run it (due to `KeepAlive` or `QueueDirectories`), it waits `ThrottleInterval` seconds first. Default is 10 seconds. Set higher for jobs that should not hammer the system.

---

## The modern `launchctl` workflow

### Legacy vs. modern commands

The old `launchctl load` / `launchctl unload` commands still work but are **deprecated** since macOS 10.10. They don't properly integrate with the service management framework, produce cryptic errors, and can leave jobs in inconsistent states. Use the modern domain-aware commands:

| Old (deprecated) | Modern equivalent |
|-----------------|-------------------|
| `launchctl load ~/Library/LaunchAgents/foo.plist` | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/foo.plist` |
| `launchctl unload ~/Library/LaunchAgents/foo.plist` | `launchctl bootout gui/$(id -u)/com.example.foo` |
| `launchctl start com.example.foo` | `launchctl kickstart gui/$(id -u)/com.example.foo` |
| `launchctl stop com.example.foo` | `launchctl kill SIGTERM gui/$(id -u)/com.example.foo` |

### Full personal automation workflow

**Step 1: Write and validate the plist**

```bash
# Save as ~/Library/LaunchAgents/local.backup.nightly.plist
plutil -lint ~/Library/LaunchAgents/local.backup.nightly.plist
# Expected: ~/Library/LaunchAgents/local.backup.nightly.plist: OK
```

`plutil -lint` catches XML malformation and plist type errors. A clean `OK` means the plist is valid XML; it does not validate that your label, path, or keys make semantic sense.

**Step 2: Bootstrap (load) the job**

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.backup.nightly.plist
```

No output = success. This registers the job in the `gui/<UID>` domain. The job will survive across logouts and logins because launchd re-reads `~/Library/LaunchAgents/` at each login.

**Step 3: Verify it loaded**

```bash
launchctl print gui/$(id -u)/local.backup.nightly
```

Expected output (abbreviated):
```
{
	active count = 1
	path = /Users/you/Library/LaunchAgents/local.backup.nightly.plist
	state = waiting
	label = local.backup.nightly
	type = agent
	pid = -
	last exit code = (never ran)
	run at load = false
	...
}
```

Key fields: `state` (`waiting`, `running`, `throttled`), `last exit code` (0 = success, negative = signal), `pid`.

**Step 4: Force-run immediately (kickstart)**

```bash
launchctl kickstart gui/$(id -u)/local.backup.nightly
```

Runs the job now, regardless of schedule. Output: `Service spawned with PID: 12345`.

**Force-restart a running job:**

```bash
launchctl kickstart -k gui/$(id -u)/local.backup.nightly
```

The `-k` flag kills any running instance before spawning a new one. As of macOS 14.4, `-k` is **blocked for system-level daemons** but remains fully functional for your personal LaunchAgents in `gui/<UID>`.

**Step 5: Tail the log**

```bash
tail -f /Users/you/Library/Logs/myjob.err.log
```

Or via the Unified Log (picks up `os_log` output and launchd events):

```bash
log stream --predicate 'subsystem == "com.apple.launchd" OR processImagePath CONTAINS "backup"' --info
```

**Step 6: Make changes → reload**

You cannot edit a plist and have changes take effect automatically. You must bootout and re-bootstrap:

```bash
# Edit the plist...
launchctl bootout gui/$(id -u)/local.backup.nightly
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.backup.nightly.plist
```

Or, since the plist already exists in `~/Library/LaunchAgents/`, a logout/login cycle will re-bootstrap it. For development iteration, `bootout` + `bootstrap` is faster.

**Step 7: Remove a job permanently**

```bash
launchctl bootout gui/$(id -u)/local.backup.nightly
rm ~/Library/LaunchAgents/local.backup.nightly.plist
```

`bootout` unregisters from the running domain; removing the plist prevents it from loading at next login.

### enable / disable

`launchctl disable` writes a `true` entry to `/var/db/com.apple.xpc.launchd/disabled.plist`, which overrides the plist on disk and prevents the service from bootstrapping at login:

```bash
launchctl disable gui/$(id -u)/local.backup.nightly   # prevent auto-load
launchctl enable  gui/$(id -u)/local.backup.nightly   # allow auto-load again
```

You need `enable` before `bootstrap` if the service was previously disabled.

---

## Worked examples

### Example 1: Nightly backup script

**The script** (`~/bin/nightly-backup.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SRC="$HOME/Documents"
DEST="/Volumes/BackupDrive/DocumentsBackup"
LOG="$HOME/Library/Logs/nightly-backup.log"

echo "[$(date '+%F %T')] Starting backup" >> "$LOG"

if [[ ! -d "$DEST" ]]; then
  echo "[$(date '+%F %T')] ERROR: backup volume not mounted" >> "$LOG"
  exit 1
fi

rsync -av --delete --exclude='.DS_Store' "$SRC/" "$DEST/" >> "$LOG" 2>&1
echo "[$(date '+%F %T')] Backup complete" >> "$LOG"
```

```bash
chmod +x ~/bin/nightly-backup.sh
```

**The plist** (`~/Library/LaunchAgents/local.myname.nightly-backup.plist`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.myname.nightly-backup</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/you/bin/nightly-backup.sh</string>
  </array>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>   <integer>2</integer>
    <key>Minute</key> <integer>30</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>/Users/you/Library/Logs/nightly-backup.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/you/Library/Logs/nightly-backup.err.log</string>

  <key>WorkingDirectory</key>
  <string>/Users/you</string>
</dict>
</plist>
```

> 🔬 **Forensics note:** rsync writes a delta summary to the log with file counts and byte sizes. For chain-of-custody purposes, add `--checksum` and pipe `md5sum` or `shasum -a 256` across the destination tree post-sync. The timestamps in the log correlate to filesystem event records in `fseventsd` stream — see [[09-spotlight-metadata-and-xattrs]].

### Example 2: WatchPaths inbox processor

**Scenario:** Drop files into `~/Desktop/Inbox/` and have them automatically moved to `~/Processed/<date>/`.

**The script** (`~/bin/process-inbox.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

INBOX="$HOME/Desktop/Inbox"
PROCESSED="$HOME/Processed/$(date '+%F')"

# WatchPaths fires on any change to Inbox (even empty dir ops), so guard:
shopt -s nullglob
files=("$INBOX"/*)
[[ ${#files[@]} -eq 0 ]] && exit 0

mkdir -p "$PROCESSED"
for f in "${files[@]}"; do
  mv "$f" "$PROCESSED/"
  echo "[$(date '+%F %T')] Moved: $(basename "$f") -> $PROCESSED/" \
    >> "$HOME/Library/Logs/inbox-watcher.log"
done
```

**The plist:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.myname.inbox-watcher</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/you/bin/process-inbox.sh</string>
  </array>

  <key>WatchPaths</key>
  <array>
    <string>/Users/you/Desktop/Inbox</string>
  </array>

  <key>StandardOutPath</key>
  <string>/Users/you/Library/Logs/inbox-watcher.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/you/Library/Logs/inbox-watcher.err.log</string>
</dict>
</plist>
```

Note the empty-check in the script — `WatchPaths` fires on *any* FS event to the directory, including `ls`, `.DS_Store` writes by Finder, and attribute changes. Your script must be idempotent and handle the "nothing to do" case gracefully.

### Example 3: Keep-alive helper process

**Scenario:** A local HTTP server that must always be running.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.myname.devserver</string>

  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/python3</string>
    <string>-m</string>
    <string>http.server</string>
    <string>8080</string>
  </array>

  <key>WorkingDirectory</key>
  <string>/Users/you/Projects/site</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>

  <key>KeepAlive</key>
  <dict>
    <key>Crashed</key>
    <true/>
    <key>SuccessfulExit</key>
    <false/>
  </dict>

  <key>ThrottleInterval</key>
  <integer>5</integer>

  <key>StandardOutPath</key>
  <string>/Users/you/Library/Logs/devserver.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/you/Library/Logs/devserver.err.log</string>

  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
```

`KeepAlive.Crashed: true` — restart after crash. `KeepAlive.SuccessfulExit: false` — restart only if the exit was non-zero (i.e., crashed/failed). Together: restart on crash, don't restart on clean exit (Ctrl-C or `kill SIGTERM`). `ThrottleInterval: 5` prevents a fast crash loop. `RunAtLoad: true` starts it immediately on login.

---

## Hands-on (CLI & GUI)

### Validating plists before loading

```bash
# Lint XML/plist syntax:
plutil -lint ~/Library/LaunchAgents/local.myname.myjob.plist

# View as human-readable JSON (good for spotting type errors):
plutil -convert json -o - ~/Library/LaunchAgents/local.myname.myjob.plist | python3 -m json.tool

# Or read as key=value (requires Xcode CLI tools):
defaults read ~/Library/LaunchAgents/local.myname.myjob.plist
```

### Listing all your loaded agents

```bash
launchctl list | grep local\\.
# Format: PID  LastExitStatus  Label
# PID of "-" means not currently running
# LastExitStatus of 0 = last run succeeded; non-zero = check the log
```

### Inspecting a specific job in detail

```bash
launchctl print gui/$(id -u)/local.myname.myjob
```

Fields of interest:
- `state` — `waiting` (scheduled, not currently running), `running`, `throttled`
- `last exit code` — `0` success, positive = script `exit N`, negative = killed by signal `-N` (e.g., `-15` = SIGTERM)
- `pid` — current PID if running
- `runs` — cumulative run count

### Sending signals to a running job

```bash
# SIGTERM (ask nicely):
launchctl kill SIGTERM gui/$(id -u)/local.myname.myjob

# SIGKILL (force):
launchctl kill SIGKILL gui/$(id -u)/local.myname.myjob
```

### Checking the Unified Log for launchd events

```bash
# Show all launchd activity for your user agents in the last 5 minutes:
log show --last 5m --predicate 'subsystem == "com.apple.launchd"' --info | grep local\.

# Stream in real-time:
log stream --predicate 'processImagePath CONTAINS "myjob" OR subsystem == "com.apple.launchd"' --info
```

---

## Labs

### Lab 1: Schedule a job with `StartCalendarInterval`

**Objective:** Write a job that appends a timestamp to a file every minute, load it, verify it fires, then tear it down.

> ⚠️ **Lab setup:** This job will write to `/tmp/heartbeat.log`. It is safe and fully reversible — `bootout` stops it, `rm` removes the plist.

**Step 1: Create the plist**

```bash
cat > ~/Library/LaunchAgents/local.lab.heartbeat.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.lab.heartbeat</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>date '+%F %T heartbeat' >> /tmp/heartbeat.log</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>/tmp/heartbeat.err.log</string>
</dict>
</plist>
PLIST
```

**Step 2: Validate and load**

```bash
plutil -lint ~/Library/LaunchAgents/local.lab.heartbeat.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.lab.heartbeat.plist
```

**Step 3: Confirm it's registered and ran at load**

```bash
launchctl print gui/$(id -u)/local.lab.heartbeat
cat /tmp/heartbeat.log   # should show a timestamp from ~now
```

**Step 4: Force a manual run**

```bash
launchctl kickstart gui/$(id -u)/local.lab.heartbeat
sleep 1
cat /tmp/heartbeat.log   # should now show two lines
```

**Step 5: Tear down**

```bash
launchctl bootout gui/$(id -u)/local.lab.heartbeat
rm ~/Library/LaunchAgents/local.lab.heartbeat.plist
rm -f /tmp/heartbeat.log /tmp/heartbeat.err.log
```

---

### Lab 2: WatchPaths watcher

**Objective:** Build an inbox watcher that fires when you add a file to a folder.

> ⚠️ **Lab setup:** Creates `~/Desktop/LabInbox/`. Fully reversible — `bootout`, remove plist, `rm -rf ~/Desktop/LabInbox`.

**Step 1: Create the inbox directory**

```bash
mkdir -p ~/Desktop/LabInbox
```

**Step 2: Create the watcher script**

```bash
cat > /tmp/lab-inbox-watcher.sh << 'SCRIPT'
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
echo "[$(date '+%F %T')] WatchPaths fired. Contents:" >> /tmp/inbox-watcher.log
ls -la "$HOME/Desktop/LabInbox/" >> /tmp/inbox-watcher.log 2>&1
SCRIPT
chmod +x /tmp/lab-inbox-watcher.sh
```

**Step 3: Create the plist**

```bash
cat > ~/Library/LaunchAgents/local.lab.inboxwatcher.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.lab.inboxwatcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/tmp/lab-inbox-watcher.sh</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>/Users/$(whoami)/Desktop/LabInbox</string>
  </array>
  <key>StandardOutPath</key>
  <string>/tmp/inbox-watcher.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/inbox-watcher.err.log</string>
</dict>
</plist>
PLIST
```

> ⚠️ Note: The heredoc above will expand `$(whoami)` at write time. Verify the path in the plist is correct with `plutil -lint`.

**Step 4: Load and test**

```bash
plutil -lint ~/Library/LaunchAgents/local.lab.inboxwatcher.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.lab.inboxwatcher.plist

# Trigger it by dropping a file:
touch ~/Desktop/LabInbox/testfile.txt
sleep 2
cat /tmp/inbox-watcher.log   # should show the event and ls output

# Trigger again:
touch ~/Desktop/LabInbox/anotherfile.txt
sleep 2
cat /tmp/inbox-watcher.log
```

**Step 5: Tear down**

```bash
launchctl bootout gui/$(id -u)/local.lab.inboxwatcher
rm ~/Library/LaunchAgents/local.lab.inboxwatcher.plist
rm -rf ~/Desktop/LabInbox
rm -f /tmp/inbox-watcher*.log /tmp/lab-inbox-watcher.sh
```

---

### Lab 3: Debug a deliberately broken job

**Objective:** Diagnose a job that silently fails, using the exact workflow you'd use in real troubleshooting.

> ⚠️ **Lab setup:** This job intentionally fails. Fully reversible — `bootout` + remove plist.

**Step 1: Create a broken plist (wrong path, no exec bit)**

```bash
cat > ~/Library/LaunchAgents/local.lab.broken.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.lab.broken</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/nobody/nonexistent-script.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/broken-job.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/broken-job.err.log</string>
</dict>
</plist>
PLIST
```

**Step 2: Load and observe failure**

```bash
plutil -lint ~/Library/LaunchAgents/local.lab.broken.plist  # passes — syntax is valid
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.lab.broken.plist
sleep 2
launchctl print gui/$(id -u)/local.lab.broken
```

Expected output shows `last exit code = 78` or `state = waiting`. Exit code `78` (`EX_CONFIG`) means launchd couldn't exec the binary — the path doesn't exist or isn't executable. Exit code `2` often means the script exited with `exit 2`. Negative exit codes (e.g., `-9`) mean the process was killed by signal 9 (SIGKILL).

**Step 3: Check the error log**

```bash
cat /tmp/broken-job.err.log  # likely empty — launchd couldn't even exec to write to it
```

**Step 4: Check the Unified Log**

```bash
log show --last 2m --predicate 'subsystem == "com.apple.launchd"' --info | grep -i broken
```

Look for `posix_spawn` failure messages or `path does not exist`.

**Step 5: Apply the diagnostic checklist**

```bash
# 1. Check the plist label matches the filename:
grep '<string>' ~/Library/LaunchAgents/local.lab.broken.plist | head -1
# Should match the plist filename slug

# 2. Check the executable path exists:
ls -la /Users/nobody/nonexistent-script.sh  # will show "No such file"

# 3. Check exec bit on a real script:
ls -la /bin/bash   # should show -rwxr-xr-x

# 4. Check for label typos in launchctl:
launchctl list | grep local\.lab
```

**Step 6: Fix and reload**

Edit the plist to use `/bin/date` as a known-working command, then reload:

```bash
# Replace the broken ProgramArguments:
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /bin/date" \
  ~/Library/LaunchAgents/local.lab.broken.plist

launchctl bootout gui/$(id -u)/local.lab.broken
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.lab.broken.plist
launchctl kickstart gui/$(id -u)/local.lab.broken
sleep 1
launchctl print gui/$(id -u)/local.lab.broken
# last exit code should now be 0
```

**Step 7: Tear down**

```bash
launchctl bootout gui/$(id -u)/local.lab.broken
rm ~/Library/LaunchAgents/local.lab.broken.plist
rm -f /tmp/broken-job*.log
```

---

## Pitfalls & gotchas

**1. The PATH trap (most common failure)**
launchd gives your job `/usr/bin:/bin:/usr/sbin:/sbin`. Homebrew lives at `/opt/homebrew/bin`. Always set `EnvironmentVariables.PATH` or hardcode absolute paths for every external binary.

**2. Label must be unique and match the plist**
If you copy a plist and forget to change the `Label` key, bootstrapping the second one will either fail or silently overwrite the first. The Label is the primary key — launchd doesn't care about filename beyond convention.

**3. exec bit required**
`chmod +x` your script. launchd calls `execve(2)` directly — there's no shell to interpret a missing shebang or forgive a non-executable file. Exit code 78 from launchd = "could not exec."

**4. launchd does not expand `~` or `$HOME`**
Write full absolute paths: `/Users/yourname/...`. `~` is a shell shorthand; launchd never invokes a shell to expand it. The same applies to `EnvironmentVariables` values.

**5. WatchPaths is not recursive**
Only direct changes to the listed path trigger the job. Changes inside subdirectories do not. If you need recursive watching, use a sentinel file pattern or the `fswatch` Homebrew tool and call launchd externally.

**6. Editing a plist on disk doesn't reload it**
You must `bootout` and `bootstrap` to apply changes. Common mistake after editing: the job keeps running its old definition.

**7. The disabled.plist override**
If a job was previously disabled with `launchctl disable`, it won't load at login even if the plist is in `~/Library/LaunchAgents/`. Use `launchctl enable gui/$(id -u)/label` before bootstrapping.

**8. Sleep and `StartInterval`**
`StartInterval` does not fire missed ticks after sleep. `StartCalendarInterval` does. For laptop users, prefer `StartCalendarInterval` for anything time-sensitive.

**9. QueueDirectories restart loop**
If your job doesn't delete the files it processes, launchd will re-fire it every `ThrottleInterval` seconds forever (or until the directory empties). Design your script to always remove the files it handles.

**10. crontab still works but is deprecated**
`crontab -e` still functions on macOS 26 but Apple officially deprecated it. cron has no sleep recovery, no filesystem triggers, no keep-alive, and no structured logging. Use launchd for new automation. Forensically, `/var/at/tabs/<username>` holds the crontab file — still worth checking in investigations.

> 🔬 **Forensics note:** Active LaunchAgent plists are a rich forensic artifact. Persistence mechanisms (malware, adware, browser hijackers) almost universally abuse `~/Library/LaunchAgents/` and `/Library/LaunchAgents/`. When investigating a Mac, enumerate all three agent locations plus `/Library/LaunchDaemons/` and compare against a known-good baseline. Key indicators of malicious plists: labels that don't match reverse-DNS convention, `ProgramArguments` pointing into `~/Library/Application Support/` or `/tmp/`, `KeepAlive: true`, and absence of `StandardOutPath` (covering tracks). Tools: `KnockKnock` (Objective-See) and `BlockBlock` detect and alert on LaunchAgent installation in real time.

---

## Why this beats crontab and Shortcuts for headless jobs

| Feature | crontab | Shortcuts | launchd |
|---------|---------|-----------|---------|
| Runs while machine is asleep | No | No | Fires on wake (StartCalendarInterval) |
| Filesystem event triggers | No | Limited (folder actions) | Yes (WatchPaths, QueueDirectories) |
| Keep-alive supervision | No | No | Yes (KeepAlive dict) |
| Structured output/logging | Manual | None | StandardOutPath, Unified Log |
| Headless (no GUI) | Yes | Often needs GUI | Yes |
| Network-state conditions | No | No | Yes (KeepAlive.NetworkState) |
| Volume-mount triggers | No | Partial | Yes (StartOnMount) |
| Environment control | Minimal | None | Full (EnvironmentVariables) |
| macOS status | Deprecated | Not intended for this | First-class |

Shortcuts is excellent for interactive, GUI-triggered automation. Folder Actions (a legacy mechanism backed by `com.apple.automator.folder-action-dispatcher`) works but is less reliable than a `WatchPaths` LaunchAgent. For anything headless, scheduled, or that must survive reboots, launchd is the right tool.

---

## Key takeaways

- Personal LaunchAgent plists live in `~/Library/LaunchAgents/`; they run in the `gui/<UID>` domain as your user.
- The modern workflow is `bootstrap` / `bootout` / `kickstart` / `print` — not `load`/`unload`.
- `StartCalendarInterval` fires missed ticks after sleep; `StartInterval` does not.
- `WatchPaths` fires on direct changes to the listed path only; not recursive.
- `QueueDirectories` re-fires until the directory is empty — your script must delete what it processes.
- `KeepAlive` as a boolean = always restart; as a dict = conditional supervision.
- launchd jobs get a minimal PATH — always set `EnvironmentVariables.PATH` explicitly.
- Never use `~` or `$HOME` in plist values — use full absolute paths.
- `plutil -lint` + `launchctl print` + the Unified Log form the complete debugging toolkit.
- `launchctl list | grep local\.` gives you at-a-glance PID and exit code for all your agents.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| **LaunchAgent** | A launchd job that runs in the user's GUI session (gui/<UID> domain) |
| **LaunchDaemon** | A launchd job that runs in the system domain as root, no GUI session |
| **domain target** | launchd addressing scheme: `gui/<UID>`, `system`, `user/<UID>` |
| **bootstrap** | Load a plist into a domain; the modern replacement for `launchctl load` |
| **bootout** | Unload a service from a domain; the modern replacement for `launchctl unload` |
| **kickstart** | Immediately run a loaded service; `-k` kills the running instance first |
| **ThrottleInterval** | Minimum seconds between launchd-initiated job invocations |
| **WatchPaths** | Plist key: fire job when a listed filesystem path changes (non-recursive) |
| **QueueDirectories** | Plist key: fire job repeatedly while a directory is non-empty |
| **StartCalendarInterval** | Plist key: cron-like scheduling with sleep-recovery semantics |
| **KeepAlive** | Plist key: supervision — restart the job on exit, conditionally or always |
| **disabled.plist** | `/var/db/com.apple.xpc.launchd/disabled.plist` — override DB that prevents loading when set true |

---

## Further reading

- `man launchd.plist` — the authoritative reference for every plist key; read this before trusting any third-party doc
- `man launchctl` — covers all subcommands including undocumented ones; `launchctl help` in the terminal
- [launchd.info](https://launchd.info/) — concise community reference for plist keys with behavioral notes
- [Howard Oakley — Tackling the launchd tutorial](https://eclecticlight.co/2021/09/20/tackling-the-launchd-tutorial/) — Eclectic Light Co. for macOS-specific behavioral nuances
- [[05-launchd-and-the-launch-system]] — the architectural deep dive: XPC domains, bootstrap tokens, the service management framework
- [[10-unified-logging-and-diagnostics]] — `log stream` and `log show` for surfacing launchd job events
- [[11-scripting]] — writing robust Bash scripts worthy of running unattended under launchd
- [[03-essential-unix-commands]] — `plutil`, `PlistBuddy`, `defaults` for plist manipulation
