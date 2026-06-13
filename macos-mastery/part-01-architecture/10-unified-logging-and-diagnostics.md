---
title: Unified logging & diagnostics
part: P01 Architecture
est_time: 50 min read + 40 min labs
prerequisites: [05-launchd-and-the-launch-system, 04-filesystem-layout-and-domains]
tags: [macos, logging, diagnostics, forensics, os_log, crash-reports, sysdiagnose]
---

# Unified Logging & Diagnostics

> **In one sentence:** macOS's Apple Unified Logging system (AUL) replaces every legacy log sink with a single high-throughput, privacy-aware, binary ring buffer managed by `logd`, queryable via the `log` CLI or Console.app, and preserved across reboots in compressed `.tracev3` files that forensic tools can parse offline.

---

## Why this matters

The old way — `syslog`, ASL, flat `/var/log/system.log`, scattered app-specific log files — scattered evidence and imposed a context-switch every time you hunted a problem. Modern macOS routes almost everything through a single structured bus at 2+ million entries per second. That means:

- A single predicate can correlate a user action with a kernel event that fired 80 ms later.
- Thirty days of system history survive reboots without you doing anything.
- Log format is identical on every Mac, every version since macOS 10.12 Sierra — forensic tooling is portable.
- Privacy redaction is enforced *at write time* in the kernel path, not post-hoc, so a compromised userspace tool cannot un-redact what was never written in cleartext.

For a forensics practitioner this is the best news on the platform. You are not recovering scattered plaintext; you are querying a structured database with 30–50 million records.

> 🪟 **Windows contrast:** Windows Event Log is structurally similar (binary, ring-buffered, provider-stamped), but fragmented across dozens of named channels. On macOS everything — kernel, daemons, apps — lands in one queryable namespace, and the command-line tooling is orders of magnitude more ergonomic than `wevtutil` or PowerShell's `Get-WinEvent`.

---

## Concepts

### 1. From ASL/syslog to AUL

Before Sierra (10.12), macOS used:

- **Apple System Log (ASL)** — a BSD-derived structured log stored in `/var/log/asl/` as binary `.asl` files, queried with `syslog(1)`.
- **`/var/log/system.log`** — plaintext syslog format; still exists but is now a thin relay for legacy callers.
- **Per-daemon logs** — crashreporter, CrashPlan, many third parties wrote free-form files anywhere under `/var/log/`, `/Library/Logs/`, `~/Library/Logs/`.

AUL replaced the first two and absorbed most of the third. The API is `os_log` (C/Obj-C/Swift), or `OSLog` (modern Swift). Legacy `NSLog` and POSIX `syslog()` are bridged in — they still work but lose structured metadata, and as of macOS 26 Tahoe all `NSLog` message content is replaced with `<private>` in the on-disk store.

### 2. The `logd` daemon — architecture

```
┌─────────────────────────────────────────────────────────┐
│  Process (app, daemon, kernel)                          │
│  os_log("msg")  →  libsystem_trace.dylib                │
│        │                                               │
│        ▼                                               │
│  Kernel log buffer  (in-memory ring, ~4 MB)            │
│        │  (IPC/Mach message)                           │
│        ▼                                               │
│  logd  (userspace, pid ≈ 200)                          │
│        │                                               │
│   ┌────┴────┐                                          │
│   │         │                                          │
│ memory    disk                                         │
│ ring buf  ┌──────────────────────────────────────┐     │
│ (~5 min)  │ /var/db/diagnostics/                 │     │
│           │   Persist/   *.tracev3   (~530 MB)   │     │
│           │   Special/   *.tracev3   (~2 MB each)│     │
│           │   Signpost/  *.tracev3               │     │
│           └──────────────────────────────────────┘     │
│                     + /var/db/uuidtext/                │
└─────────────────────────────────────────────────────────┘
```

`logd` is a persistent daemon (launchd label `com.apple.logd`). It:

1. Receives compressed log chunks from `libsystem_trace` via a Mach port.
2. Maintains a short-lived **in-memory ring** (roughly 5 minutes of typical load).
3. Flushes entries to **tracev3 files** on disk — the durable store.
4. Enforces total disk budget by deleting time-expired entries; the `Persist/` folder caps at roughly 530 MB across 50+ files (~10.4 MB each).

`/var/db/uuidtext/` holds the **UUID → binary image path** mapping. Without it, log messages decode as raw format strings with no symbol names. A forensic image without both `/var/db/diagnostics/` and `/var/db/uuidtext/` will show substantial `<private>` and `???` placeholders.

### 3. The Preboot harvesting trick (Apple Silicon + FileVault)

The Data volume is encrypted by FileVault and unavailable until after authentication. So early-boot log entries — bootloader, `launchd`, kernel extensions — would be lost. macOS solves this with a two-stage write:

1. Before the Data volume unlocks, `logd` writes temporary `.tracev3` files to the **Preboot volume** at:
   ```
   /System/Volumes/Preboot/<UUID>/PreLoginData/
   ```
2. After login, `logd_helper` **harvests** these into permanent locations under `/private/var/db/diagnostics/`. Tens of thousands of early-boot kernel entries survive through this handoff.

> 🔬 **Forensics note:** If you acquire only the Data volume (a common partial image), you miss pre-login entries entirely. Full-disk acquisition must include the Preboot volume to capture boot-time events. Look for the `logd_helper` entries in the log itself to confirm harvesting ran.

### 4. Log levels

| Level | API call | Persisted? | Default visibility | Use |
|---|---|---|---|---|
| **Default** | `os_log()` | Yes | Always | General operational events |
| **Info** | `os_log_info()` | Conditionally | Requires `--info` flag | Verbose operational state |
| **Debug** | `os_log_debug()` | No (memory only) | Requires `--debug` flag | High-frequency trace; lost on exit |
| **Error** | `os_log_error()` | Yes | Always | Recoverable errors |
| **Fault** | `os_log_fault()` | Yes | Always | Unrecoverable; triggers backtrace capture |

Default and Error/Fault are always written to disk. Info is written only when the subsystem's logging configuration (`/Library/Preferences/Logging/Subsystems/<bundle-id>.plist`) enables it, or when a `log config` override is active. Debug is **in-memory only** — it is never flushed to `.tracev3` under normal conditions, so you must catch it live with `log stream --debug`.

### 5. The `.tracev3` binary format

`.tracev3` is a proprietary binary format, largely (but unofficially) reverse-engineered. Key properties:

- **Compressed chunks** — each file is a series of `lz4`-compressed chunks.
- **Chunkset format** — each chunk contains log records, catalog pages, and references back to `uuidtext/` for format strings.
- **Not human-readable** — you cannot `strings` or `grep` a `.tracev3` file meaningfully; you need the `log` CLI or a dedicated parser.
- **Format strings are separated from values** — similar to printf: the binary stores the format specifier separately from the argument values, which is why privacy redaction can be enforced without storing the value at all.

The separation between format and value is the architectural key to privacy. When you write:

```swift
os_log(.default, "User logged in as %{private}s", username)
```

The format string `"User logged in as %{private}s"` is stored in the binary (in the `uuidtext` entry for that image). The *value* of `username` is **never written to disk** at the `<private>` annotation — the on-disk record literally contains a token that says "redacted." No post-hoc scrubbing needed; it was never stored.

> 🔬 **Forensics note:** The `<private>` marker is a deliberate non-artifact. On a production system you will see large volumes of `<private>` placeholders for things like file paths, user names, and bundle IDs. Apple Developer-mode can disable redaction globally (`log config --mode private_data:on` while in a diagnostics profile), but this requires SIP configuration on a development machine — you will never find it enabled on an end-user system. Work with what the level reveals; correlate timing with other artifact classes (FSEvents, TCC.db, KnowledgeC, etc.) — see [[03-forensic-artifacts]].

### 6. Subsystem and category

Every `os_log` call is tagged with a **subsystem** (typically the bundle ID: `com.apple.backupd`) and a **category** within it (e.g., `backup`, `network`). This is the filtering atom — most productive queries start here, not on message content.

```
┌──────────────────────────┬────────────────────────────┐
│ subsystem                │ category                   │
│ com.apple.WindowServer   │ Display                    │
│ com.apple.security.sos   │ circle                     │
│ com.apple.xpc            │ connection                 │
└──────────────────────────┴────────────────────────────┘
```

---

## Hands-on (CLI & GUI)

### `log stream` — live tail

`log stream` is the real-time feed from the in-memory ring buffer. It connects to `logd`'s streaming endpoint and prints entries as they arrive.

```bash
# Bare stream — overwhelming volume, mostly Default level
log stream

# Filter to one subsystem (TCC permission events)
log stream --predicate 'subsystem == "com.apple.TCC"'

# SSH events, including info level
log stream --info --predicate 'process == "sshd"'

# Anything mentioning "denied" (case-insensitive), debug included
log stream --debug --predicate 'eventMessage contains[cd] "denied"'

# Kernel subsystem, show process and category columns
log stream --style syslog --predicate 'subsystem == "com.apple.kernel"'
```

Output format (default style):
```
2026-06-13 09:14:22.391491-0700  0x23e      Default     0x0                  342    0    kernel: (AppleMobileFileIntegrity) AMFI: ...
```
Fields: timestamp, thread-id, level, activity-id, PID, TID, process/subsystem, message.

### `log show` — query the archive

`log show` reads `.tracev3` files from disk (or a `.logarchive`). It is the primary offline/historical query tool.

```bash
# Last 1 hour, default level only
log show --last 1h

# Last 24 hours, include info, filter by subsystem
log show --last 24h --info \
  --predicate 'subsystem == "com.apple.backupd"'

# Specific time window (forensic pivot: event happened at 14:30)
log show \
  --start "2026-06-13 14:20:00" \
  --end   "2026-06-13 14:45:00" \
  --info \
  --predicate 'eventMessage contains[cd] "mount"'

# Faults and errors across the entire retained window
log show --last 30d \
  --predicate 'messageType == "fault" OR messageType == "error"'

# Query a collected archive on another machine
log show /path/to/system-logs.logarchive \
  --predicate 'process == "tccd"' --info
```

> **Tip:** `log show` without `--info` or `--debug` silently drops those levels even if they exist in the archive. When hunting for something and finding nothing, add `--info` first.

### Predicate syntax

The predicate follows `NSPredicate` rules (the same grammar as Spotlight, Core Data, and `mdfind` — see [[09-spotlight-metadata-and-xattrs]]). Key operators and fields:

| Field | Type | Example |
|---|---|---|
| `subsystem` | string | `subsystem == "com.apple.TCC"` |
| `category` | string | `category == "BackgroundTaskManagement"` |
| `process` | string | `process == "sudo"` |
| `processID` | int | `processID == 412` |
| `eventMessage` | string | `eventMessage contains[cd] "fail"` |
| `messageType` | string | `messageType == "error"` |
| `senderImagePath` | string | `senderImagePath contains "IOKit"` |
| `processImagePath` | string | `processImagePath endswith "hidd"` |

**String operators:**
- `==`, `!=` — exact match
- `contains`, `beginswith`, `endswith`
- Append `[c]` for case-insensitive, `[d]` for diacritic-insensitive, `[cd]` for both
- `LIKE` for glob: `process LIKE "Purple*"`

**Combining:**
```bash
--predicate '(subsystem == "com.apple.xpc" OR subsystem == "com.apple.launchd") AND eventMessage contains[cd] "crash"'
```

> 🔬 **Forensics note — high-value predicates:**
> ```bash
> # Privilege escalation via sudo
> process == "sudo"
>
> # TCC permission grants/denials
> subsystem == "com.apple.TCC"
>
> # Login / auth events
> process == "loginwindow" OR process == "logind"
>
> # SSH connections
> process == "sshd"
>
> # Screen sharing auth
> process == "screensharingd"
>
> # LaunchDaemon load (persistence mechanism)
> subsystem == "com.apple.launchd" AND eventMessage contains[cd] "load"
>
> # Gatekeeper / quarantine
> process == "syspolicyd"
>
> # SIP violations
> subsystem == "com.apple.kernel.kext" AND eventMessage contains[cd] "SIP"
> ```

### `log collect` — snapshot an archive

`log collect` packages `/var/db/diagnostics/` and `/var/db/uuidtext/` into a portable `.logarchive` bundle.

```bash
# Collect last 3 days to the Desktop
sudo log collect --last 3d --output ~/Desktop/system-logs.logarchive

# Collect a specific window
sudo log collect \
  --start "2026-06-10 00:00:00" \
  --end   "2026-06-13 23:59:59" \
  --output ~/Desktop/incident-logs.logarchive
```

The resulting `.logarchive` is a directory bundle (open in Console.app or pass to `log show`). It is **self-contained** — it embeds the `uuidtext` mappings, so format strings resolve correctly even without the source binary.

> ⚠️ **ADVANCED:** `sudo` is required because `/var/db/diagnostics/` is root-owned. The archive includes all log levels including potentially sensitive info-level entries. Treat the `.logarchive` as a sensitive artifact; encrypt it in transit.

### `log config` — change runtime verbosity

```bash
# Enable info + debug for a subsystem (survives until reboot or until reset)
sudo log config --subsystem com.apple.backupd --mode level:debug

# Reset to default
sudo log config --subsystem com.apple.backupd --mode level:default

# Show current config
log config --status
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `log config --reset` clears all overrides. Do not run on a production system mid-investigation without recording the existing config first.

### Console.app

Console.app is `log stream` with a GUI. Open it from `/Applications/Utilities/Console.app`.

Key GUI workflows:
- **Devices sidebar** — connect a second Mac or iPhone via USB; Console streams its log in real time (invaluable for iOS forensics without jailbreak).
- **Search bar** — becomes a predicate builder; type `process:sshd` and it translates to `process == "sshd"`.
- **Errors and Faults** filter — top toolbar button; equivalent to `--predicate 'messageType == "error" OR messageType == "fault"'`.
- **Crashes** pane — surfaces `DiagnosticReports` entries inline.
- **Include Info/Debug messages** — checkboxes in Action menu; off by default.

The "Any" search field in Console maps to `eventMessage contains[cd]`, but you can click the field label to switch to `subsystem`, `category`, `process`, etc.

---

## Crash Reports, Spindumps & Diagnostic Reports

### `.ips` — the crash report format

Crash reports since macOS 12 Monterey are stored in **JSON-backed `.ips` files** (Incident Progress System, an Apple internal format).

Locations:
```
~/Library/Logs/DiagnosticReports/    (user-space crashes, per-user)
/Library/Logs/DiagnosticReports/     (system-level crashes, root-owned)
/private/var/db/diagnostics/         (system internal; overlaps with logd storage)
```

An `.ips` file has two sections:
1. **Header** — JSON metadata: `bug_type`, `timestamp`, `os_version`, `reason`, `pid`, `coalitionName`, exception type and codes.
2. **Incident report** — a second JSON object embedded as a string, containing the full thread backtraces, binary images list, register state, and dyld state.

```bash
# Inspect a crash report as JSON
python3 -m json.tool ~/Library/Logs/DiagnosticReports/MyApp-2026-06-13.ips | less

# Extract just the exception info
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    header = json.loads(f.readline())
print('Exception:', header.get('exception', {}).get('type'))
print('Signal:', header.get('exception', {}).get('signal'))
print('Reason:', header.get('termination', {}).get('description'))
" ~/Library/Logs/DiagnosticReports/SomeApp-2026-06-13.ips
```

Key `.ips` fields for forensics:

| Field | Meaning |
|---|---|
| `bug_type` | `109` = crash, `110` = trace fault, `210` = watchdog, `109` variations |
| `exception.type` | `EXC_BAD_ACCESS`, `EXC_CRASH`, `EXC_RESOURCE`, etc. |
| `termination.code` | signal number (11 = SIGSEGV, 9 = SIGKILL) |
| `termination.namespace` | `DYLD`, `JETSAM`, `SPRINGBOARD`, `OS` |
| `procRole` | `Foreground`, `Background`, `Unspecified` |
| `coalitionName` | The process coalition (app group) that crashed |
| `binaryImages` | Array of loaded dylibs + UUIDs — allows symbol matching |

> 🔬 **Forensics note:** The `binaryImages` array in a crash report is a **snapshot of the process's dyld image list at crash time**. Combined with `/var/db/uuidtext/`, you can reconstruct exactly which version of every framework was loaded. This is how you determine if a crash was caused by an OS update introducing a new dylib version. UUIDs are immutable per-build — a matching UUID means the same exact binary.

### Spindumps

A **spindump** is a stackshot — a sampling of all thread stacks for a process or the whole system, taken when an app becomes unresponsive (spinning beach ball) or on demand.

```bash
# On-demand spindump of a specific PID (requires sudo for other users' processes)
sudo spindump <pid> 10 10 -file /tmp/myapp.spindump

# Spindump the entire system for 5 seconds at 10 ms intervals
sudo spindump 5 10 -file /tmp/system.spindump

# Read an existing spindump from DiagnosticReports
# (these are auto-generated by ReportCrash when the beach ball fires)
ls ~/Library/Logs/DiagnosticReports/*.spindump
```

Spindumps are text files (not JSON). They show symbolized backtraces grouped by thread. The on-disk format differs from `.ips` — no JSON wrapper. Automatic spindumps are triggered by `ReportCrash` after ~2 seconds of spinning and written to `DiagnosticReports/`.

> 🔬 **Forensics note:** Auto-generated spindumps record the **timestamp**, **responsible process** (the app that held focus when spinning occurred), and often the **display name of the document** in the thread title. A spindump file proves a user was interacting with a specific document at a specific time.

### `sysdiagnose` — the full-system snapshot

`sysdiagnose` is a shell script that orchestrates ~40 diagnostic tools into a single tarball. It's what Apple Support asks for and what contains the full unified log archive.

```bash
# Trigger from command line (takes 2–5 minutes; writes to /private/var/tmp/)
sudo sysdiagnose -f ~/Desktop/

# Or trigger with a keyboard shortcut (works even during crashes):
# Ctrl + Option + Cmd + Shift + . (period)
# → System generates the archive asynchronously; notification when done
```

**Contents of a `sysdiagnose_<hostname>_<timestamp>.tar.gz`:**

| Item | Contents |
|---|---|
| `system_logs.logarchive` | Full `log collect` output (the AUL archive) |
| `spindump.txt` | Multi-second system-wide stackshot at time of capture |
| `ps.txt`, `top.txt` | Process snapshot |
| `fs_usage.txt` | File system calls during capture window |
| `ioreg.txt` | IOKit registry dump |
| `nvram.txt` | NVRAM variables (boot args, SIP status, etc.) |
| `sw_vers.txt`, `system_profiler` | OS version, hardware identifiers |
| `DiagnosticReports/` | All crash/spin reports from both locations |
| `network/` | `ifconfig`, `netstat`, `arp`, routing table, DNS |
| `launchd/` | All loaded plists (`launchctl list`) |
| `kernel/` | Loaded KEXTs, panic logs |
| `caches/` | App launch times, dyld cache info |
| `preferences/` | Selected system preference plists |

> 🔬 **Forensics note:** `sysdiagnose` is the single most information-dense artifact you can collect from a live Mac. The `system_logs.logarchive` inside it carries 28–30 days of structured log history. The `launchd/` section lists every running daemon and agent — an instant persistence-mechanism inventory. NVRAM output exposes `boot-args` modifications (SIP bypass attempts set `boot-args="-x amfi_get_out_of_my_way=1"`).

---

## Offline Forensic Analysis (Dead-Box)

### What survives reboot

| Artifact | Survives? | Notes |
|---|---|---|
| `Persist/*.tracev3` | Yes (~30 days) | The durable log store |
| `Special/*.tracev3` | Partially | Short-lived; entries expire faster |
| In-memory ring buffer | No | Lost on shutdown |
| Debug-level entries | No | Never flushed to disk |
| `uuidtext/` | Yes | Required to decode format strings |
| Crash reports (`.ips`) | Yes | No retention policy; accumulate |
| Spindumps | Yes | No retention policy |
| Preboot harvest logs | Yes | In Preboot volume after first login |

### Reconstructing a `.logarchive` from an image

```bash
# On the forensic workstation (macOS), mount the acquired image
# then manually create a logarchive bundle:

mkdir /tmp/evidence.logarchive
cp -r /Volumes/AcquiredData/private/var/db/diagnostics/ \
      /tmp/evidence.logarchive/
cp -r /Volumes/AcquiredData/private/var/db/uuidtext/ \
      /tmp/evidence.logarchive/

# Now query it
log show /tmp/evidence.logarchive \
  --predicate 'process == "sudo"' \
  --info \
  --start "2026-06-01 00:00:00"
```

The `.logarchive` format is just a directory bundle with a known layout. `log show` accepts a path to it directly — no wrapping needed.

### Third-party parsing tools

When the `log` CLI is unavailable (Linux forensic workstation, Windows SIFT) or you need bulk CSV/JSON output:

| Tool | Language | Notes |
|---|---|---|
| **UnifiedLogReader** (Yogesh Khatri) | Python | Open-source; outputs CSV/TSV; the go-to DFIR tool for offline analysis |
| **mac_apt** | Python | Full DFIR framework with unified log as one of many plugins; processes disk images |
| **macos-unifiedlogs** (Mandiant/Google) | Rust | Fast binary; JSON output; cross-platform |
| **Blacklight** (BlackBag/Cellebrite) | Commercial | GUI; handles `.logarchive` and raw `diagnostics/` directories |

```bash
# UnifiedLogReader — install
pip3 install UnifiedLogReader

# Parse a logarchive to CSV
python3 -m UnifiedLogReader \
  -l /tmp/evidence.logarchive \
  -o /tmp/parsed_logs/ \
  --csv
```

> ⚠️ **ADVANCED:** UnifiedLogReader requires both the `diagnostics/` and `uuidtext/` paths. Without `uuidtext/`, format strings resolve to `???` — you see timestamps and levels but no message text. Always acquire both directories together.

---

## 🧪 Labs

### Lab 1 — Live stream with a real filter

Watch TCC (privacy permission) events in real time while triggering a permission prompt.

```bash
log stream --info \
  --predicate 'subsystem == "com.apple.TCC"' \
  --style compact
```

In another terminal or Finder, try to access a protected location (Photos, Contacts). Watch the TCC entries fire. Note the `service`, `client`, and `allowed`/`denied` fields in the message.

### Lab 2 — Predicate triage of last 24 hours

```bash
# Find every sudo invocation in the last 24 hours
log show --last 24h \
  --predicate 'process == "sudo"' \
  --style compact

# Find everything that was killed or crashed
log show --last 24h \
  --predicate 'eventMessage contains[cd] "killed" OR messageType == "fault"' \
  --info
```

Compare the output volume. Note how `--info` dramatically expands results.

### Lab 3 — Inspect your own crash reports

```bash
# List all crash reports for your account (newest first)
ls -lt ~/Library/Logs/DiagnosticReports/ | head -20

# Pretty-print the header section of the most recent .ips
LATEST=$(ls -t ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -1)
[ -n "$LATEST" ] && python3 -m json.tool <(head -1 "$LATEST")
```

Identify: the crashing process, exception type, OS version at crash time, and the `coalitionName` (which app group owned the crashed process).

### Lab 4 — Collect and query a local archive

⚠️ **Requires sudo. Creates a ~500 MB file. To roll back: `rm ~/Desktop/lab-logs.logarchive`.**

```bash
# Collect last 4 hours
sudo log collect --last 4h --output ~/Desktop/lab-logs.logarchive

# Query it — look for launchd activity
log show ~/Desktop/lab-logs.logarchive \
  --predicate 'process == "launchd"' \
  --info \
  --style compact | head -50

# Count entries by type
log show ~/Desktop/lab-logs.logarchive --info | \
  grep -oE '\s(Default|Info|Debug|Error|Fault)\s' | \
  sort | uniq -c | sort -rn
```

### Lab 5 — Read NVRAM and correlate with boot logs

```bash
# Check current NVRAM (look for boot-args — SIP bypass leaves traces here)
nvram -p | grep -E 'boot-args|csr-active-config'

# Find the last boot's early kernel messages
log show --last 24h \
  --predicate 'subsystem == "com.apple.kernel" AND category == "boot"' \
  --info \
  --start "$(date -v-24H '+%Y-%m-%d %H:%M:%S')" | head -40
```

### Lab 6 — Trigger and read a spindump

⚠️ **Reads process state. No system changes. Roll back: nothing to undo.**

```bash
# Spindump the WindowServer for 3 seconds at 10 ms intervals
sudo spindump WindowServer 3 10 -file /tmp/ws-spindump.txt
head -80 /tmp/ws-spindump.txt
```

Identify: the thread responsible for the most samples, the top frames in that thread's call stack, and whether any thread is blocking on a lock (`__psynch_mutexwait`, `semaphore_wait_trap`).

---

## Pitfalls & Gotchas

**1. Debug level is never on disk.**
The most common trap: you look for a debug-level message in `log show`, find nothing, assume it wasn't logged. Run `log stream --debug` live and you'll see it. Debug entries exist only in the in-memory ring.

**2. `--info` is opt-in every time.**
`log show` and `log stream` both default to Default+Error+Fault only. You must add `--info` explicitly, every invocation, or info-level messages are silently absent. There is no persistent setting.

**3. `<private>` values cannot be recovered on a normal Mac.**
Even with root. The private value was never written. You can enable private data logging with a profile on a development machine — but on a live end-user investigation target, the data is gone. Plan around this: use timing correlation, TCC.db, FSEvents, and `kMDItemLastUsedDate` (see [[09-spotlight-metadata-and-xattrs]]) to reconstruct what you can't read.

**4. `uuidtext/` is not optional for offline analysis.**
A `logarchive` or `log show` run against `diagnostics/` alone will show binary format strings and `???` where process names and symbols should appear. Always image both directories together.

**5. `NSLog` messages are `<private>` in macOS 26.**
Third-party apps that still use `NSLog` (Obj-C legacy, some Python/Ruby bridges) will have their message bodies redacted on macOS 26 Tahoe. This is a behavior change from earlier releases where `NSLog` output was visible in the log stream without redaction. If you're debugging third-party software and see only `<private>`, this is likely the cause.

**6. Sysdiagnose time is not event time.**
`sysdiagnose` captures the *current* state. The `system_logs.logarchive` inside it goes back ~30 days, but the spindump, `ps.txt`, `fs_usage.txt`, and network state are point-in-time at collection. Don't confuse sysdiagnose's generation time with when an incident occurred.

**7. The `log` CLI requires the local system's SIP-protected frameworks.**
On a forensic workstation running a different macOS version, `log show` *may* misparse entries from a different OS version due to schema changes in `.tracev3`. For cross-version analysis, prefer UnifiedLogReader or macos-unifiedlogs which implement the format in pure code.

---

## Key Takeaways

- `logd` is the single ingestion point for all macOS log traffic; `.tracev3` files in `/var/db/diagnostics/` are the durable on-disk artifact, supplemented by `/var/db/uuidtext/` for symbol resolution.
- Privacy redaction (`<private>`) is enforced at write time in the kernel path — values are never stored, not redacted after the fact.
- Log levels: Default and Error/Fault always persist; Info persists conditionally; Debug is memory-only.
- `log stream` for live capture; `log show` for historical queries; `log collect` for portable archive creation; Console.app for GUI with device-streaming capability.
- NSPredicate syntax with `subsystem`, `process`, `category`, and `eventMessage` covers 95% of triage needs.
- Crash reports are JSON `.ips` files; spindumps are text stackshots; both accumulate without retention policy in `DiagnosticReports/`.
- `sysdiagnose` is the gold-standard evidence package: logarchive + crash reports + launchd state + NVRAM + network state in one tarball.
- Offline forensics requires both `diagnostics/` and `uuidtext/`; reconstruct a `.logarchive` bundle manually from a disk image, then query with `log show` or UnifiedLogReader.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **AUL** | Apple Unified Logging — the logging subsystem introduced in macOS Sierra replacing ASL/syslog |
| **`logd`** | The user-space daemon that manages the in-memory ring buffer and flushes to `.tracev3` files |
| **`logd_helper`** | Child process that harvests pre-login log entries from the Preboot volume after user authentication |
| **`.tracev3`** | Proprietary compressed binary log file format; stored in `/var/db/diagnostics/` |
| **`uuidtext`** | Directory of UUID-keyed files mapping binary image UUIDs to format strings; required for log decoding |
| **Subsystem** | Bundle-ID-style namespace (e.g., `com.apple.TCC`) labeling a log producer |
| **Category** | A subdivision of a subsystem (e.g., `kCFStreamSocketSecurityLevel`) |
| **Log level** | Default / Info / Debug / Error / Fault — determines persistence and visibility |
| **`<private>`** | Privacy redaction token; value was never written to disk |
| **`.logarchive`** | Directory bundle containing `diagnostics/` + `uuidtext/`; queryable by `log show` and Console.app |
| **`.ips`** | Incident Progress System — JSON-based crash report format used since macOS 12 |
| **Spindump** | A stackshot of thread call stacks; generated automatically on spinning-beachball events |
| **Sysdiagnose** | System-wide diagnostic snapshot script; output contains logarchive + ~40 other diagnostic artifacts |
| **NSPredicate** | Apple's query expression language used for log filtering, Core Data queries, and Spotlight |
| **Harvesting** | The `logd_helper` process of merging Preboot-volume pre-login logs into the live Data-volume store |

---

## Further Reading

- **Apple Platform Security guide** (developer.apple.com/documentation/security) — covers the kernel-enforced privacy model
- **`man log`** — the authoritative flag reference; especially the `--predicate` and `--style` sections
- **Howard Oakley, "Inside the Unified Log" series** (eclecticlight.co, 2025–2026) — the deepest publicly available architecture writeup
- **Howard Oakley, "How does macOS keep its log?"** (eclecticlight.co, February 2026) — covers Preboot harvesting and macOS 26 NSLog changes
- **UnifiedLogReader** (github.com/ydkhatri/UnifiedLogReader) — primary DFIR parsing tool; the README documents field names and output format
- **macos-unifiedlogs** (Mandiant/Google, GitHub) — Rust-based parser, JSON output, cross-platform
- **mac_apt** (github.com/pythonmandev/mac_apt) — full macOS DFIR framework; unified log is one plugin among many
- **CrowdStrike: "How to Leverage Apple Unified Log for IR"** — practitioner-focused predicate cookbook
- **dtformats Apple Unified Logging and Activity Tracing** (github.com/libyal/dtformats) — the reverse-engineering documentation of the `.tracev3` binary format
- **`man spindump`**, **`man sysdiagnose`** — full flag references for both tools
- Related lessons: [[05-launchd-and-the-launch-system]] · [[08-security-architecture]] · [[03-forensic-artifacts]] · [[09-spotlight-metadata-and-xattrs]] · [[06-troubleshooting-methodology]]
