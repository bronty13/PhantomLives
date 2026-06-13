---
title: "launchd & the Launch System"
part: P01 Architecture
est_time: 50 min read + 45 min labs
prerequisites: [01-boot-process, 02-kernel-and-xnu, 04-sip-and-sealed-system-volume]
tags: [macos, launchd, launchctl, launchagents, launchdaemons, xpc, persistence, forensics, init, services]
---

# launchd & the Launch System

> **In one sentence:** launchd is macOS's PID 1 — it replaces init, cron, inetd, and rc scripts in a single daemon that owns the lifecycle of every process on the system.

---

## Why this matters

On Windows, service management is split across the Service Control Manager (SCM), Task Scheduler, and the registry run keys. On macOS, one process — `launchd` — handles all of it: system boot sequencing, per-user session startup, scheduled tasks, socket activation, on-demand XPC services, and graceful shutdown. If you understand launchd, you understand:

- How macOS boots from kernel to usable session (continues from [[01-boot-process]])
- Where every persistent background process originates
- The single most exploited persistence mechanism in macOS malware (MITRE ATT&CK T1543.001 / T1543.004)
- How to build, deploy, and debug your own background services

> 🪟 **Windows contrast:** SCM services (`HKLM\SYSTEM\CurrentControlSet\Services`) are the closest analog to LaunchDaemons. LaunchAgents approximate scheduled tasks or run-key autostart entries, but with far richer scheduling semantics and proper per-user isolation.

---

## Concepts

### launchd as PID 1

When the XNU kernel finishes initializing hardware and the BSD layer, it `exec()`s a single userspace process: `/sbin/launchd`. That process gets PID 1, never exits, and becomes the direct or indirect parent of every other process on the system. There is no `init`, no `systemd`, no `rc.d` — launchd absorbed all of them in macOS 10.4 (2005) and has been the sole init system ever since.

launchd's responsibilities at a high level:

| Role replaced | Old mechanism | launchd equivalent |
|---|---|---|
| System init / sequencing | `/etc/rc`, `init` | System LaunchDaemons, bootstrap ordering |
| Per-user session startup | `loginwindow` + shell profiles | Per-user LaunchAgents |
| Recurring tasks | `cron` | `StartInterval` / `StartCalendarInterval` |
| TCP socket activation (inetd) | `/etc/inetd.conf` | `Sockets` key + on-demand activation |
| XPC service broker | — | `launchd` as XPC namespace registry |

> 🔬 **Forensics note:** Because launchd is PID 1, its process tree IS the system's process tree. A process that re-parents to PID 1 (common in malware daemonization) is re-parenting to launchd. `pstree` or `ps -axo pid,ppid,comm` rooted at PID 1 shows everything.

### Two Job Classes: Daemons vs. Agents

launchd distinguishes two categories of job, and the distinction is architectural, not just semantic:

**LaunchDaemons** run in the system bootstrap context. They start before any user logs in, run as `root` (or a specified system user via the `UserName` key), have no access to the GUI or any per-user session resource (Keychain, pasteboard, window server), and keep running after the user logs out. The canonical examples: `sshd`, `mDNSResponder`, `configd`, `com.apple.security.syspolicyd`.

**LaunchAgents** run in the per-user bootstrap context, inside the user's login session. They have GUI access (can show windows, use the pasteboard, play audio), run as the logged-in user, and are started when that user's session begins. They die when the session ends. The canonical examples: Spotlight's indexer (`mds_stores`), Notification Center, Keychain helpers.

The key architectural rule: **only Agents have access to the GUI / WindowServer**. A daemon that tries to display a window or touch the pasteboard will silently fail or crash.

```
Boot sequence timeline
─────────────────────────────────────────────────────────────────────
Kernel → launchd (PID 1)
             │
             ├── system bootstrap domain
             │     ├── /System/Library/LaunchDaemons/  [Apple]
             │     └── /Library/LaunchDaemons/         [admin]
             │
             └── (user logs in → loginwindow → per-user session)
                   │
                   ├── gui/<uid> bootstrap domain
                   │     ├── /System/Library/LaunchAgents/  [Apple]
                   │     ├── /Library/LaunchAgents/          [admin]
                   │     └── ~/Library/LaunchAgents/         [user]
                   │
                   └── XPC services (on-demand, within app bundles)
```

### The Five Search Domains

launchd scans these directories at bootstrap time, in this priority order (highest to lowest trust):

| Domain | Path | Who installs | Run context |
|---|---|---|---|
| System daemons | `/System/Library/LaunchDaemons/` | Apple only (SSV) | root, pre-login |
| System agents | `/System/Library/LaunchAgents/` | Apple only (SSV) | logged-in user |
| Admin daemons | `/Library/LaunchDaemons/` | admin (requires root) | root, pre-login |
| Admin agents | `/Library/LaunchAgents/` | admin | logged-in user |
| User agents | `~/Library/LaunchAgents/` | user | that user |

As of macOS 11+ (Big Sur) with the Sealed System Volume ([[04-sip-and-sealed-system-volume]]), the `/System/Library/` paths are on the cryptographically sealed read-only volume. You cannot add, remove, or modify jobs there without breaking the seal — this is by design and is a key integrity guarantee.

> 🔬 **Forensics note:** Malware almost never touches `/System/Library/` (SIP blocks it). Focus enumeration on `/Library/LaunchDaemons/`, `/Library/LaunchAgents/`, and `~/Library/LaunchAgents/`. The user-level path requires zero privilege — a sandboxed app or a phishing payload can plant a `.plist` there without prompting the user.

### macOS 26 Tahoe: LaunchAngels (New in Tahoe)

macOS 26 introduces a new category of launch job: **LaunchAngels**, stored in `/System/Library/LaunchAngels/`. These are Apple-only, reside on the SSV, and include RunningBoard lifecycle metadata (`Managed: true`, `Reported: true`) not present in classic plist jobs. Current examples: `AccessibilityUIServer`, `GameOverlayUI`, `PosterBoard`. Third parties cannot use this directory — it is Apple-internal infrastructure. You will see these when enumerating running processes but they are not a persistence vector.

### Plist Job Keys — The Engineering Reference

Every launchd job is defined by a property list (XML or binary). Key keys:

#### Identity

| Key | Type | Purpose |
|---|---|---|
| `Label` | String, **required** | Unique reverse-DNS identifier. Must match the filename (minus `.plist`). |
| `Program` | String | Path to the executable. Use instead of `ProgramArguments` when no args needed. |
| `ProgramArguments` | Array of strings | `argv[0]` is the executable path; remaining elements are arguments. Shell metacharacters are NOT interpreted — this is `execve()`, not `sh -c`. |
| `EnvironmentVariables` | Dictionary | Additional env vars injected into the process environment. |
| `WorkingDirectory` | String | Sets `cwd` before exec. |
| `UserName` | String | Run as this user (daemons only). |
| `GroupName` | String | Run as this group. |

#### Activation & Scheduling

| Key | Type | Purpose |
|---|---|---|
| `RunAtLoad` | Boolean | Start the job immediately when the plist is loaded. |
| `StartInterval` | Integer | Run every N seconds. Timer fires even if the previous run is still going. |
| `StartCalendarInterval` | Dict or Array | cron-style: `Minute`, `Hour`, `Day`, `Month`, `Weekday` keys. Omitted keys are wildcards. |
| `WatchPaths` | Array | Start the job when any listed path is created, deleted, or modified. |
| `QueueDirectories` | Array | Start the job when any listed directory is non-empty; re-run while it stays non-empty. |
| `Sockets` | Dict | Declare TCP/UDP/Unix sockets; launchd holds the socket open and passes the fd to the job on first connection (inetd-style activation). |

#### Lifecycle & Restart

| Key | Type | Purpose |
|---|---|---|
| `KeepAlive` | Boolean or Dict | `true`: respawn unconditionally. Dict form: condition-keyed (`SuccessfulExit`, `Crashed`, `NetworkState`, `PathState`, `OtherJobEnabled`). |
| `ThrottleInterval` | Integer | Minimum seconds between respawns (default: 10). Prevents tight crash loops from pegging CPU. |
| `ExitTimeOut` | Integer | Seconds launchd waits after SIGTERM before sending SIGKILL (default: 20). |
| `AbandonProcessGroup` | Boolean | Don't SIGKILL child processes when the job exits. Rarely needed. |

#### I/O & Logging

| Key | Type | Purpose |
|---|---|---|
| `StandardOutPath` | String | Redirect stdout to this file. File is appended, never rotated by launchd. |
| `StandardErrorPath` | String | Redirect stderr to this file. |
| `StandardInPath` | String | Feed this file as stdin (rarely used). |

#### Security & Sandboxing

| Key | Type | Purpose |
|---|---|---|
| `Umask` | Integer | File creation mask (octal as decimal: 022 = `18`). |
| `RootDirectory` | String | `chroot(2)` jail. |
| `ProcessType` | String | `Background`, `Standard`, `Adaptive`, `Interactive` — affects QoS scheduling. |
| `LowPriorityIO` | Boolean | Throttle disk I/O to avoid competing with interactive work. |
| `Nice` | Integer | `nice(3)` priority, -20 (highest) to 20 (lowest). |

> ⚠️ **Shell gotcha:** `ProgramArguments` is passed directly to `execve()`. Pipes (`|`), redirects (`>`), environment substitution (`$VAR`), and globs (`*.log`) will NOT work. Wrap in `["/bin/sh", "-c", "your shell command"]` if you need shell semantics.

### launchctl — Modern vs. Legacy Syntax

macOS 10.10 (Yosemite, 2014) introduced a completely new `launchctl` subcommand set tied to the XPC domain model. The old `load`/`unload`/`start`/`stop` verbs still work for backward compatibility but are deprecated and may be removed. Always use the modern syntax.

#### Domain Specifiers

The new syntax identifies a service as `<domain-target>/<label>`:

| Domain target | Meaning |
|---|---|
| `system/` | System bootstrap domain (daemons) |
| `gui/<uid>/` | GUI session for this UID (agents running in that user's window server session) |
| `user/<uid>/` | Per-user bootstrap (agents, but without requiring an active GUI session) |
| `login/<asid>/` | A specific login session (audit session ID) |
| `pid/<pid>/` | Scope of a running process |

Get your UID with `id -u`. The `gui/` domain is the right target for interactive LaunchAgents.

#### The Essential Modern Subcommands

```bash
# Load (bootstrap) a plist into a domain — replaces `launchctl load`
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.myjob.plist

# Unload (bootout) a plist — replaces `launchctl unload`
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.example.myjob.plist

# Force-start a loaded job immediately — replaces `launchctl start`
launchctl kickstart -k gui/$(id -u)/com.example.myjob
# -k: kill the running instance first (idempotent restart)
# -p: print the new PID to stdout

# Inspect a domain (list all loaded services)
launchctl print gui/$(id -u)

# Inspect a specific service (state, PID, exit code, properties)
launchctl print gui/$(id -u)/com.example.myjob

# List loaded jobs (compact: PID, last exit, label)
launchctl list
launchctl list | grep com.example

# Show which services are disabled (override database)
launchctl print-disabled gui/$(id -u)    # agents
launchctl print-disabled system/         # daemons (needs sudo)

# Persistently disable a service across reboots
launchctl disable gui/$(id -u)/com.example.myjob

# Re-enable a previously disabled service
launchctl enable gui/$(id -u)/com.example.myjob

# Send a signal (replaces `launchctl stop`)
launchctl kill SIGTERM gui/$(id -u)/com.example.myjob
launchctl kill SIGKILL system/com.apple.something   # needs sudo
```

#### Legacy Syntax (avoid, but know it)

```bash
# These still work but are deprecated as of macOS 10.10
sudo launchctl load -w /Library/LaunchDaemons/com.example.daemon.plist
sudo launchctl unload /Library/LaunchDaemons/com.example.daemon.plist
launchctl start com.example.daemon
launchctl list com.example.daemon
```

The `-w` flag on `load` wrote to the old override database (`/var/db/launchd.db/`), marking the job as enabled regardless of any `Disabled` key in the plist. Modern `enable`/`disable` writes to `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist` (agents) or `/var/db/com.apple.xpc.launchd/disabled.plist` (daemons). These files are the source of truth for the enable/disable state and are readable as forensic artifacts.

### Why cron Is Deprecated

`cron` (`/usr/sbin/cron`, backed by `/etc/crontab` and `~/Library/Preferences/`) still ships on macOS for compatibility, but:

1. cron does not participate in launchd's power management — it wakes the CPU on a hard timer regardless of power state, defeating App Nap and energy optimization.
2. cron entries lack per-job stdout/stderr capture, credential isolation, or `KeepAlive`.
3. `cron` requires Full Disk Access on macOS 10.14+ if the cron job itself needs FDA — users see confusing permission dialogs attributed to `cron`, not their tool.
4. launchd's `StartCalendarInterval` provides a strict superset of cron's scheduling, plus the job context (user, environment, resource limits) is explicit in the plist.

> 🔬 **Forensics note:** Attackers occasionally use `cron` specifically BECAUSE it is less scrutinized than LaunchAgents by endpoint tools. Check `/etc/crontab`, `/etc/cron.d/`, and each user's crontab (`crontab -l -u <user>`) during incident response — do not assume everything lives in plist files.

### XPC Service Activation

XPC (cross-Process Communication, built on Mach IPC) extends the launchd model to application-bundled services. An XPC service lives inside an `.app` bundle at `MyApp.app/Contents/XPCServices/com.example.myapp.helper.xpc/`, with its own `Info.plist` declaring `XPCService` settings and `LSMinimumSystemVersion`.

Activation is **on-demand**: the client calls `xpc_connection_create()` with the service name; launchd receives the Mach message, finds the service's plist in its in-memory cache, forks/execs the service binary, and hands the client connection to it — all without a standing plist in any `LaunchAgents/` directory. The service can be:

- `Singleton`: one instance shared by all clients in the same app
- `Application`: one instance per application
- `None` (default): one instance per connecting process

launchd enforces code-signature validation between client and service: the service's `Info.plist` can declare `JoinExistingSession`, `ServiceType`, and `RunLoopType`. The service exits when it has no active connections (idle timeout), and launchd tracks this — it is the reason "helper processes" appear and disappear in Activity Monitor.

> 🔬 **Forensics note:** XPC services embedded in `.app` bundles do NOT appear in the LaunchAgents/LaunchDaemons directories and are invisible to a simple `launchctl list`. They show up in `ps aux` and Activity Monitor. Malware distributing a privileged XPC helper inside a legitimately-looking app bundle is a real attack pattern — the privileged helper is registered with `SMAppService` (modern) or `SMJobBless` (legacy) and ends up in `/Library/PrivilegedHelperTools/`, with a corresponding plist in `/Library/LaunchDaemons/`.

```
XPC activation flow
──────────────────────────────────────────────────────────────────
App.app
  └─ Contents/XPCServices/com.example.helper.xpc
        └─ Contents/Info.plist  (XPCService dict)

App process                 launchd (PID 1)           helper binary
    │                           │                          │
    │  xpc_connection_create()  │                          │
    │──────────────────────────►│                          │
    │                           │  fork + exec helper      │
    │                           │─────────────────────────►│
    │  Mach port handed back    │                          │
    │◄──────────────────────────│                          │
    │                           │                          │
    │◄─────────── XPC messages ────────────────────────────►│
    │                           │                          │
    │  connection closed        │                          │
    │──────────────────────────►│  idle → SIGTERM helper   │
    │                           │─────────────────────────►│
```

---

## Hands-on (CLI & GUI)

### Inspect the live system

```bash
# How many jobs are loaded in your GUI session?
launchctl list | wc -l

# What's running, with PIDs?
launchctl list | awk '$1 != "-" {print $1, $3}' | sort -n

# Full domain dump (noisy but complete)
launchctl print gui/$(id -u) | head -80

# Deep-dive a specific Apple service
launchctl print gui/$(id -u)/com.apple.Spotlight

# Check the system domain (sudo required for full output)
sudo launchctl print system | grep -E 'label|state|pid' | head -60
```

### Read an Apple plist to understand the format

```bash
# One of the simplest LaunchDaemons — the syslog helper
plutil -p /System/Library/LaunchDaemons/com.apple.syslogd.plist

# A LaunchAgent with scheduling
plutil -p /System/Library/LaunchAgents/com.apple.SafariHistory.plist

# Convert any binary plist to XML for reading
plutil -convert xml1 -o - ~/Library/LaunchAgents/com.someapp.agent.plist
```

### Write and load your own LaunchAgent

```bash
# Step 1: Create a simple script
cat > /tmp/hello-launchd.sh << 'EOF'
#!/bin/bash
echo "$(date): hello from launchd PID $$" >> /tmp/hello-launchd.log
EOF
chmod +x /tmp/hello-launchd.sh

# Step 2: Write the plist
cat > ~/Library/LaunchAgents/com.example.hello.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.hello</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/tmp/hello-launchd.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/hello-launchd.stdout</string>
    <key>StandardErrorPath</key>
    <string>/tmp/hello-launchd.stderr</string>
</dict>
</plist>
EOF

# Step 3: Validate the plist before loading
plutil -lint ~/Library/LaunchAgents/com.example.hello.plist
# Expected: ~/Library/LaunchAgents/com.example.hello.plist: OK

# Step 4: Bootstrap (load) into your GUI session
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.hello.plist

# Step 5: Verify it loaded
launchctl list com.example.hello
# Expected output: PID (if running), last exit (0 = success), label

# Step 6: Check the log
sleep 2
cat /tmp/hello-launchd.log

# Step 7: Force-run it immediately
launchctl kickstart -k gui/$(id -u)/com.example.hello

# Step 8: Inspect state
launchctl print gui/$(id -u)/com.example.hello
```

### Unload and clean up

```bash
launchctl bootout gui/$(id -u)/com.example.hello
rm ~/Library/LaunchAgents/com.example.hello.plist
```

### GUI tool: LaunchControl

[LaunchControl](https://soma-zone.com/LaunchControl/) (soma-zone, paid, ~$12) is the canonical GUI for launchd management — it visualizes all domains, shows last-exit codes, lets you edit plists with key documentation, and supports enable/disable. Worth having for the visual domain map alone.

---

## 🧪 Labs

### Lab 1 — Enumerate all persistence jobs (forensics baseline)

> ⚠️ **Read-only, safe.** No destructive operations. Run as your normal user; some sudo calls for completeness.

```bash
#!/bin/bash
# Full persistence enumeration — output to ~/Desktop/launchd-audit.txt
OUT=~/Desktop/launchd-audit.txt
echo "=== launchd Persistence Audit — $(date) ===" > "$OUT"

echo -e "\n--- ~/Library/LaunchAgents (user-installed) ---" >> "$OUT"
ls -la ~/Library/LaunchAgents/ 2>/dev/null >> "$OUT"
for f in ~/Library/LaunchAgents/*.plist; do
  [[ -f "$f" ]] || continue
  echo -e "\n## $f" >> "$OUT"
  plutil -p "$f" 2>/dev/null >> "$OUT"
done

echo -e "\n--- /Library/LaunchAgents (admin-installed agents) ---" >> "$OUT"
ls -la /Library/LaunchAgents/ 2>/dev/null >> "$OUT"

echo -e "\n--- /Library/LaunchDaemons (admin-installed daemons) ---" >> "$OUT"
ls -la /Library/LaunchDaemons/ 2>/dev/null >> "$OUT"
for f in /Library/LaunchDaemons/*.plist; do
  [[ -f "$f" ]] || continue
  echo -e "\n## $f" >> "$OUT"
  plutil -p "$f" 2>/dev/null >> "$OUT"
done

echo -e "\n--- Privileged helpers (/Library/PrivilegedHelperTools) ---" >> "$OUT"
ls -la /Library/PrivilegedHelperTools/ 2>/dev/null >> "$OUT"

echo -e "\n--- Crontab check ---" >> "$OUT"
crontab -l 2>/dev/null >> "$OUT" || echo "(no crontab for $(whoami))" >> "$OUT"
cat /etc/crontab 2>/dev/null >> "$OUT"

echo -e "\n--- Live session jobs (from launchctl list) ---" >> "$OUT"
launchctl list >> "$OUT"

echo "Audit written to $OUT"
open "$OUT"
```

Look for:
- Plists with `ProgramArguments` pointing outside `/Applications/` or system paths
- Jobs with `KeepAlive: true` and no obvious vendor name
- Jobs where the executable path does not exist (stale or deleted-binary trick)
- Label names that do not match the filename (deliberate misdirection)
- `RunAtLoad: true` combined with a script in `/tmp/` or a user's `Downloads/`

> 🔬 **Forensics note:** Deleted-binary persistence is a real technique: plant the plist, let launchd load it, then delete the binary. The job stays in launchd's table with an error state, but re-dropping the binary at that path relaunches it — even if macOS Gatekeeper has scanned and quarantined the original.

### Lab 2 — Build a WatchPaths agent (file-system trigger)

> ⚠️ **MODERATE / write ops.** Creates files in `~/Library/LaunchAgents` and `/tmp`. Roll back: `launchctl bootout gui/$(id -u)/com.example.watchdog && rm ~/Library/LaunchAgents/com.example.watchdog.plist`.

```bash
# Create the watched directory and handler
mkdir -p /tmp/watchdog-inbox

cat > /tmp/watchdog-handler.sh << 'EOF'
#!/bin/bash
echo "$(date): WatchPaths triggered, inbox contents:" >> /tmp/watchdog.log
ls -la /tmp/watchdog-inbox/ >> /tmp/watchdog.log
EOF
chmod +x /tmp/watchdog-handler.sh

cat > ~/Library/LaunchAgents/com.example.watchdog.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.watchdog</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/tmp/watchdog-handler.sh</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/tmp/watchdog-inbox</string>
    </array>
    <key>StandardErrorPath</key>
    <string>/tmp/watchdog.stderr</string>
</dict>
</plist>
EOF

plutil -lint ~/Library/LaunchAgents/com.example.watchdog.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.watchdog.plist

# Trigger it
touch /tmp/watchdog-inbox/testfile.txt
sleep 1
cat /tmp/watchdog.log
# Expected: timestamp line + ls output showing testfile.txt
```

This pattern is widely used legitimately (Hazel, folder actions, file processors) and by malware (drop a file in a watched path to trigger payload execution). The `QueueDirectories` variant is similar but only fires when the directory is non-empty, making it queue-draining semantics instead of change-detection.

### Lab 3 — Calendar scheduling (StartCalendarInterval)

> ⚠️ **Safe.** Creates a LaunchAgent that fires once per minute. Roll back: bootout + rm.

```bash
cat > ~/Library/LaunchAgents/com.example.minutely.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.minutely</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>date >> /tmp/minutely.log</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Second</key>
        <integer>0</integer>
    </dict>
    <key>StandardErrorPath</key>
    <string>/tmp/minutely.stderr</string>
</dict>
</plist>
EOF

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.minutely.plist
# Wait for the next minute boundary, then:
cat /tmp/minutely.log
```

`StartCalendarInterval` supports `Minute` (0–59), `Hour` (0–23), `Day` (1–31), `Month` (1–12), `Weekday` (0–7, 0 and 7 are Sunday). Omitting a key means "every value" (wildcard). An array of dicts gives multiple fire times: `<array><dict>...<key>Hour</key><integer>9</integer>...</dict><dict>...18...</dict></array>` = 9am and 6pm.

### Lab 4 — Observe exit codes and crash behavior

```bash
# A job that exits non-zero (simulating a crash)
cat > ~/Library/LaunchAgents/com.example.crashy.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.crashy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>exit 42</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
EOF

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.crashy.plist
sleep 2
launchctl list com.example.crashy
# Output: - 42 com.example.crashy  ← the "42" is last exit status; "-" means not running
# KeepAlive means launchd will respawn it every ThrottleInterval seconds

# Observe in Console.app (Filter: "crashy") or:
log show --predicate 'process == "launchd"' --last 30s | grep crashy

# CRITICAL: always clean up KeepAlive jobs
launchctl bootout gui/$(id -u)/com.example.crashy
rm ~/Library/LaunchAgents/com.example.crashy.plist
```

> 🔬 **Forensics note:** A negative exit status in `launchctl list` indicates the process was killed by a signal: status `-11` = SIGSEGV, `-15` = SIGTERM, `-9` = SIGKILL. This is useful when investigating unexplained process terminations — check `launchctl list <label>` immediately after seeing a crash in logs.

### Lab 5 — Read the override (disabled) database

```bash
# Show which user agents are explicitly enabled or disabled
launchctl print-disabled gui/$(id -u)
# Output: com.apple.Spotlight => enabled
#         com.some.thirdparty => disabled
#         ...

# The underlying file (readable directly as binary plist)
ls -la /var/db/com.apple.xpc.launchd/
# disabled.plist         ← system daemon overrides
# disabled.<uid>.plist   ← per-user agent overrides (your UID)

sudo plutil -p /var/db/com.apple.xpc.launchd/disabled.plist | head -30
plutil -p /var/db/com.apple.xpc.launchd/disabled.$(id -u).plist 2>/dev/null | head -30
```

> 🔬 **Forensics note:** The override database persists through reboots and survives the plist being removed from `LaunchAgents/`. A malware sample that calls `launchctl enable` can ensure its agent is marked "enabled" in this database before the plist is quarantined or deleted — making it re-activate the moment the plist is restored or re-dropped.

---

## Pitfalls & gotchas

**The filename must match the Label.** If `~/Library/LaunchAgents/com.foo.bar.plist` contains `<key>Label</key><string>com.foo.baz</string>`, launchd will load it but `launchctl print` and `list` will show `com.foo.baz` while the file is named `com.foo.bar.plist`. Bootout by label (`com.foo.baz`), not filename. This trips everyone up the first time.

**Permissions must be correct.** The plist file must be owned by root (for daemons) or the user (for agents), not writable by group or other (no `g+w` or `o+w`). launchd silently refuses to load plists with overly permissive modes. Canonical: `chmod 644 ~/Library/LaunchAgents/com.example.plist`.

**Changes require a reload.** Editing a plist that is already loaded does nothing until you `bootout` and `bootstrap` again. There is no "reload" shortcut — bootout/bootstrap is the cycle.

**`RunAtLoad` vs. `KeepAlive`.** `RunAtLoad: true` fires once immediately. `KeepAlive: true` fires once and then restarts forever on exit. Combining both with a script that crashes produces a tight respawn loop — `ThrottleInterval` is your safety valve.

**`sudo launchctl` operates on the system domain, not your GUI session.** If you accidentally `sudo launchctl bootstrap` a user agent plist, you bootstrap it into the system domain where it runs as root, has no GUI access, and `bootout` requires sudo. Always match the privilege level of `launchctl` to the target domain.

**Catalina+ read-only system volume.** You cannot place anything in `/System/Library/LaunchDaemons/` or `/System/Library/LaunchAgents/` — not even as root. The SSV cryptographic seal covers those directories. Use `/Library/LaunchDaemons/` for admin-level daemons.

**`StandardOutPath` is append-only, never rotated.** A daemon writing verbose logs to `StandardOutPath` will grow the file unboundedly. Use a `newsyslog` config entry in `/etc/newsyslog.d/` or roll your own rotation in the script.

**Signing and Gatekeeper:** On macOS 15+, third-party LaunchDaemon executables in `/Library/LaunchDaemons/` that are not notarized will generate Gatekeeper warnings or be blocked on first execution. Notarize any daemon binary you intend to distribute.

---

## Key takeaways

- launchd (PID 1) is the sole init system, service manager, cron replacement, and XPC namespace on macOS. Everything else is a client of launchd.
- LaunchDaemons = system scope, root, no GUI, pre-login. LaunchAgents = user scope, GUI access, session lifetime.
- The five search domains are hierarchically trusted: SSV-sealed Apple plists → `/Library/` admin plists → `~/Library/` user plists.
- Modern `launchctl` syntax uses domain specifiers (`gui/<uid>/`, `system/`) with `bootstrap`/`bootout`/`kickstart`/`print` verbs. Legacy `load`/`unload` still works but is deprecated.
- The override database at `/var/db/com.apple.xpc.launchd/disabled*.plist` persists enabled/disabled state independently of the plist files.
- XPC services inside app bundles are launchd-managed but not visible in the LaunchAgents directories — they activate on first client connection.
- LaunchAgents and LaunchDaemons are the dominant macOS persistence mechanism (~80% of persistent macOS malware). Forensic enumeration of all five search domains + `/Library/PrivilegedHelperTools/` + crontabs is mandatory in any IR engagement.
- macOS 26 Tahoe adds LaunchAngels (`/System/Library/LaunchAngels/`) as an Apple-only internal category with RunningBoard lifecycle management — not available to third parties.

---

## Terms introduced

| Term | Definition |
|---|---|
| **launchd** | PID 1 on macOS; sole init, service manager, and XPC namespace daemon |
| **LaunchDaemon** | A launchd job in the system bootstrap context; runs pre-login, as root |
| **LaunchAgent** | A launchd job in a user's GUI session context; runs per-user, with GUI access |
| **bootstrap (domain)** | The namespace / context in which launchd manages jobs; `system/` or `gui/<uid>/` |
| **bootstrap (verb)** | `launchctl bootstrap` — load a plist into a domain |
| **bootout** | `launchctl bootout` — unload a plist from a domain |
| **kickstart** | `launchctl kickstart` — force-start a loaded job, optionally killing a running instance first |
| **RunAtLoad** | Plist key: start the job immediately when the plist is loaded |
| **KeepAlive** | Plist key: respawn the job unconditionally (or conditionally) on exit |
| **StartCalendarInterval** | Plist key: cron-style calendar scheduling |
| **WatchPaths** | Plist key: trigger the job on filesystem changes to listed paths |
| **QueueDirectories** | Plist key: trigger the job while listed directories contain files |
| **ThrottleInterval** | Plist key: minimum seconds between respawns |
| **Override database** | `/var/db/com.apple.xpc.launchd/disabled*.plist` — persists enable/disable state |
| **XPC service** | A launchd-managed on-demand helper bundled inside an `.app`; activates on client connection |
| **SMAppService** | Modern (macOS 13+) Swift/ObjC API to register login items and privileged helpers with launchd |
| **PrivilegedHelperTools** | `/Library/PrivilegedHelperTools/` — standard install location for SMJobBless/SMAppService daemons |
| **LaunchAngels** | macOS 26 Tahoe-only, Apple-internal category of launchd jobs with RunningBoard integration |
| **domain specifier** | launchctl syntax token (`gui/501`, `system/`) that scopes a command to a bootstrap context |

---

## Further reading

- `man launchd`, `man launchd.plist`, `man launchctl` — authoritative; `man launchd.plist` has the full key reference
- [launchd.info](https://launchd.info/) — concise community reference, well-maintained
- [Eclectic Light Company — Welcome to Tahoe's Launch Angels](https://eclecticlight.co/2025/10/03/welcome-to-tahoes-launch-angels/) — macOS 26 changes
- [Eclectic Light Company — Explainer: XPC](https://eclecticlight.co/2026/02/07/explainer-xpc/) — XPC service activation deep-dive
- [MITRE ATT&CK T1543.001 — Launch Agent](https://attack.mitre.org/techniques/T1543/001/) and [T1543.004 — Launch Daemon](https://attack.mitre.org/techniques/T1543/004/) — adversary techniques reference
- [soma-zone LaunchControl](https://soma-zone.com/LaunchControl/) — best GUI for launchd exploration
- [cocomelonc — macOS malware persistence via LaunchAgents](https://cocomelonc.github.io/macos/2026/01/05/malware-mac-persistence-1.html) — C-level example of persistence implant
- Apple Platform Security Guide (download from [apple.com/privacy](https://www.apple.com/privacy/)) — covers SSV, SIP, and their interaction with launchd
- [[01-boot-process]] — how launchd is exec'd from the kernel
- [[04-sip-and-sealed-system-volume]] — why `/System/Library/LaunchDaemons/` is immutable
- [[06-xpc-and-ipc]] — XPC architecture and privilege separation in depth
