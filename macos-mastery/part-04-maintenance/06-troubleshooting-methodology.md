---
title: Troubleshooting methodology
part: P04 Maintenance
est_time: 55 min read + 45 min labs
prerequisites: [01-boot-process, 05-launchd-and-the-launch-system, 08-security-architecture, 10-unified-logging-and-diagnostics]
tags: [macos, troubleshooting, diagnostics, kernel-panic, safe-mode, tcc, sysdiagnose, forensics]
---

# Troubleshooting Methodology

> **In one sentence:** Effective macOS troubleshooting is a disciplined layer-isolation exercise — hardware → firmware → OS kernel → system services → user library → app — not random fix-throwing, and every layer has a specific diagnostic instrument that produces machine-readable evidence.

---

## Why this matters

The classic Windows reflex — reboot, run `sfc /scannow`, reinstall — works poorly on macOS because the layering is fundamentally different. macOS has a hardened read-only system volume (SSV), cryptographically sealed OS files, a strongly opinionated permission model (TCC, SIP, Gatekeeper), and a binary-ring-buffer log that captures everything at microsecond resolution. A random fix attempt that happens to succeed tells you nothing reusable, may corrupt evidence, and frequently makes the next problem harder to diagnose.

This lesson gives you a repeatable decision framework: a diagnostic ladder that narrows the problem space by one layer per step, specific instruments for each layer, and a symptom-to-step dispatch table for the six most common failure modes.

> 🪟 **Windows contrast:** Windows has Event Viewer (fragmented across 1000+ named channels), Reliability Monitor (useful for timeline correlation), `sfc /scannow` (OS file integrity scan), and `perfmon`. macOS's equivalent instruments are `log`, `Console.app`, `sysdiagnose`, `fs_usage`, and `spindump` — all more ergonomic, but you need to know which one to reach for.

---

## Concepts

### The Diagnostic Ladder — Six Layers

Every macOS symptom traces to exactly one root layer. Misidentifying it wastes hours. Work top-down:

```
Layer 0 — HARDWARE          Apple Diagnostics, smartmontools, memtest
Layer 1 — FIRMWARE          NVRAM/SMC (Intel only); Recovery OS checks
Layer 2 — OS / KERNEL       Kernel panics, kext crashes, Safe Mode
Layer 3 — SYSTEM SERVICES   launchd, XPC services, TCC/SIP, Spotlight index
Layer 4 — USER ACCOUNT      ~/Library, login items, user plist corruption
Layer 5 — APPLICATION       App-specific prefs, cache dirs, sandbox containers
```

The diagnostic ladder proceeds downward only when a higher layer is excluded. If Safe Mode (which disables third-party kexts, system extensions, and login items, and clears font caches) eliminates the symptom, you have **narrowed to Layer 3–5** and don't need Apple Diagnostics.

### Layer 0 — Hardware

**Apple Diagnostics** (formerly Apple Hardware Test) runs from firmware, entirely independent of the OS. It tests CPU, memory, storage controller, and thermal sensors.

- **Apple Silicon:** Hold the power button until "Loading startup options" appears → press **Cmd-D** to start Diagnostics. For extended testing, use **Cmd-E** once the Diagnostics Loader appears.
- **Intel:** Hold **D** at boot (from built-in startup disk) or **Option-D** (internet-based version). Release when the progress bar appears.

Diagnostics returns a reference code in the form `PPT001`, `ADP000`, etc. Look up the code on Apple's support pages — each code maps to a specific subsystem. A clean Diagnostics result with a continuing symptom means hardware is provisionally excluded for that subsystem.

> 🔬 **Forensics note:** If you're analyzing a Mac before evidence collection, run Diagnostics *before* booting the main OS. A storage-controller error or memory fault produces dramatically different memory artifacts than software corruption, and distinguishing them early prevents misattribution.

**Storage health** — Diagnostics does not expose SMART data. Use:

```bash
# Built-in (basic SMART pass/fail only)
diskutil info disk0 | grep SMART

# Detailed SMART attributes (requires smartmontools; brew install smartmontools)
sudo smartctl -a /dev/disk0

# NVMe-specific health log
sudo smartctl -l nvme /dev/disk0
```

For Apple Silicon, the internal NVMe is integrated into the SoC; SMART reporting is partial. Key attributes: `Percentage Used`, `Power On Hours`, reallocated/pending sector counts.

### Layer 1 — Firmware (Intel/T2 only, mostly)

**NVRAM** holds per-boot settings: default boot disk, verbose mode flag, kernel boot args, FileVault recovery key hint. On Intel Macs, NVRAM corruption occasionally causes unexpected boot behavior.

```bash
# Inspect all NVRAM variables
nvram -xp

# Reset (Intel only — this is the safe "NVRAM reset")
# ⚠️ This clears boot-disk selection, startup chime setting, and display resolution
sudo nvram -c
```

On **Apple Silicon**, NVRAM still exists but is managed by the Secure Boot process and iBoot. The traditional "NVRAM reset" (Cmd-Opt-P-R at boot) is meaningless — Apple Silicon doesn't have that key combo. Instead, use `nvram -c` from the OS, which only clears user-settable variables.

**SMC** (System Management Controller) — exists on Intel/T2 only; controls fans, power rails, battery, and ambient light sensor. SMC malfunction produces: fans at full speed for no reason, sudden sleep, battery not charging. Reset via the documented key sequence (varies by model; look it up for the specific Intel machine). Apple Silicon replaces SMC with firmware embedded in the SoC — SMC reset is not a concept on M-series Macs.

> 🪟 **Windows contrast:** The Windows equivalent is BIOS/UEFI reset (load defaults) and TPM clear. macOS separates user-accessible NVRAM reset from the secure iBoot domain — you can reset NVRAM without weakening Secure Boot.

### Layer 2 — OS / Kernel: Reading Kernel Panics

A kernel panic is an unrecoverable exception in kernel space or in a kernel extension. The machine restarts and writes a `.panic` file.

**Log location:** `/var/db/PanicReporter/` (primary on modern macOS) and mirrored to `/Library/Logs/DiagnosticReports/`. Files are named `kernel_YYYY-MM-DD-HHMMSS_machinename.panic`.

```bash
# List recent panics
ls -lt /Library/Logs/DiagnosticReports/*.panic | head -10

# Read the most recent panic
open /Library/Logs/DiagnosticReports/$(ls -t /Library/Logs/DiagnosticReports/*.panic | head -1)
```

**Anatomy of a panic log** — read these sections in order:

1. **Panic string** (top of file): the immediate cause. Examples:
   - `"zalloc: zone map exhausted…"` → memory pressure / leak
   - `"Kernel trap at 0x…, type 14=page fault"` → bad memory dereference
   - `"WDT timeout…"` → a thread hung and the watchdog killed it
   - `"a freed object at 0x…"` → use-after-free, usually a kext bug

2. **BSD process name at panic** — which process was running when the panic fired (not necessarily the culprit, but a starting point)

3. **Loaded kexts** — listed by load address at the bottom. Third-party kexts appear in the Auxiliary Kernel Collection (AKC). If a third-party kext appears near the top of the panic backtrace, it is strongly implicated.

4. **Backtrace** — the kernel call stack. Symbols are resolved for Apple-signed code; third-party kexts may appear as hex offsets.

5. **iBoot version and `secure boot?: YES/NO`** — YES means the system is running with a trusted chain; NO (custom kernel flags set, SIP disabled) means you've modified the boot path.

> 🔬 **Forensics note:** The panic log timestamp (filename) is in local time, but the log body uses absolute seconds since boot. Cross-reference with `log show --last 5m` relative to the panic timestamp to see what was happening in userspace in the seconds before the kernel fell over. The unified log survives the reboot in the persistent `.tracev3` store — see [[10-unified-logging-and-diagnostics]].

### Safe Mode — Layer 2/3 Boundary Test

Safe Mode is the single most valuable test in the diagnostic ladder because it cleanly bisects "OS-or-below" from "third-party extensions and user account." On modern macOS (Ventura+), Safe Mode:

- **Blocks** all third-party kernel extensions (KEXTs), all Auxiliary Kernel Collection (AKC) system extensions, all third-party system extensions, all non-Apple login items and launch agents, and non-macOS fonts
- **Clears** the font cache and kernel cache
- **Does NOT clear** Spotlight indexes, QuickLook caches, or user application caches — those require separate steps
- **Does NOT perform meaningful disk repair** — the disk check in Safe Mode is currently identical to a normal boot; use Disk Utility in Recovery for actual fsck

**To enter Safe Mode on Apple Silicon:**
1. Shut down fully (not restart).
2. Press and hold the power button until "Loading startup options" appears.
3. Select your boot disk **while holding Shift**.
4. Click "Continue in Safe Mode."
5. You will be asked to log in **twice** — the first login decrypts the FileVault volume; the second brings you to the desktop. This is expected behavior, not a bug.

If the symptom disappears in Safe Mode, you have isolated to Layer 3–5. Proceed to test a fresh user account to further isolate between system-level customization and user-library corruption.

### Layer 3 — System Services: TCC and Permission Diagnosis

TCC (Transparency, Consent, and Control) is managed by `tccd`, a daemon with two instances: `tccd` (user session) and `tccd` (system, running as root). Grant decisions are stored in two SQLite databases:

- System-level: `/Library/Application Support/com.apple.TCC/TCC.db`
- User-level: `~/Library/Application Support/com.apple.TCC/TCC.db`

TCC permission errors manifest as: app silently doing nothing where a file access, microphone, camera, or accessibility action was expected; "operation not permitted" in stderr; or a missing permission prompt (the prompt itself being suppressed by TCC).

**Diagnosis workflow:**

```bash
# Check what TCC has granted/denied for a specific bundle ID
# (requires Full Disk Access for the terminal, since TCC.db is TCC-protected itself)
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, service, auth_value, auth_reason FROM access ORDER BY last_modified DESC LIMIT 30;"

# auth_value: 0=denied, 1=unknown, 2=allowed
# auth_reason: 1=user-granted, 4=system-granted, 7=MDM

# Reset TCC for a single service (e.g., Accessibility) for one app
tccutil reset Accessibility com.example.myapp

# Reset ALL TCC grants for one app (nuclear; user must re-grant)
tccutil reset All com.example.myapp
```

**Distinguishing TCC from POSIX:** If `ls -la` shows the user owns the file but the app can't read it, TCC (not POSIX) is the blocker. If `ls` itself returns permission denied, check POSIX (`stat`, `ls -le` for ACLs). See [[08-security-architecture]] for the full SIP/TCC/Gatekeeper layering.

**SIP diagnosis:**

```bash
csrutil status
# "System Integrity Protection status: enabled." is the expected safe state
# If disabled, that explains why custom kexts or root-owned overwrites work unexpectedly
```

**Spotlight index problems** — a corrupt or incomplete Spotlight index causes slow or missing search results, `mds` consuming high CPU, and Spotlight returning stale data:

```bash
# Force Spotlight to reindex a specific volume
sudo mdutil -E /

# Check indexing status
mdutil -s /

# Disable and re-enable (the full nuclear rebuild)
sudo mdutil -i off /
sudo mdutil -i on /
```

The index lives in `/.Spotlight-V100/` (hidden at the volume root) and rebuilds over 5–60 minutes depending on disk size. You can watch progress in Console.app by filtering for process `mds` or `mds_stores`.

### Layer 4 — User Account Isolation

The fastest way to test whether a problem is user-specific is to log in as a different user — specifically, a **fresh user account** with no customization, no login items, and a clean `~/Library`. macOS creates clean user libraries on first login.

**Steps:**
1. System Settings → Users & Groups → Add Account → Standard User (a temporary "testuser").
2. Log in as testuser (fast user switching — click the menu bar user icon, or log out and back in).
3. Reproduce the symptom. If it does not appear, the problem is confined to the original user's `~/Library`.

**What to look for when the problem IS user-specific:**

```
~/Library/
  Preferences/         ← plist files, per-app settings
  Application Support/ ← app databases, caches, sync state
  Caches/              ← derivative data; generally safe to delete
  LaunchAgents/        ← user-level daemons (login items implemented as launch agents)
  Containers/          ← sandboxed app data (Mac App Store apps)
  Group Containers/    ← shared containers across app families
```

The correct procedure for plist-driven app corruption:

1. **Quit the app completely** — `osascript -e 'quit app "AppName"'` or Cmd-Q. Do not just close windows.
2. **Move, do not delete** the plist aside:
   ```bash
   mv ~/Library/Preferences/com.vendor.appname.plist \
      ~/Library/Preferences/com.vendor.appname.plist.bak
   ```
3. If the app uses `defaults` caching, also run:
   ```bash
   killall cfprefsd
   ```
   `cfprefsd` is the preference daemon; it caches plist contents in memory and will re-write a stale plist if you delete the file without flushing its cache first. `killall cfprefsd` forces it to restart and release its in-memory state.
4. Relaunch the app. A fresh plist is generated on launch.
5. Test. If the problem is gone, the plist was corrupt. Discard the `.bak` when satisfied.

> 🔬 **Forensics note:** Plist files carry modification timestamps and often embed `NSUserDefaultsDidChangeNotification` transaction records. Moving aside (not deleting) the plist preserves this evidence. The original file's mtime is the last time preferences were written — correlate with the unified log to see what user action triggered the write.

**Caches:** Application caches live in `~/Library/Caches/<bundle-id>/`. These are derivative data — the app regenerates them. Deleting them is safe and often resolves UI corruption, missing thumbnails, and stale state:

```bash
# Delete a specific app's cache
rm -rf ~/Library/Caches/com.vendor.appname

# DO NOT recursively delete all of ~/Library/Caches — some apps (Chrome, Firefox)
# store session state here, and clearing everything is harder to roll back
```

System-level caches (kernel extension cache, dynamic linker cache, fonts):

```bash
# Rebuild the dyld shared cache (normally done automatically on update)
sudo update_dyld_shared_cache -force

# Purge the font cache (same mechanism as Safe Mode's font-cache clear)
sudo atsutil databases -remove
sudo atsutil server -shutdown
```

### Layer 5 — Application: The Standard Repair Sequence

When the problem is app-specific and survives a fresh user account test (meaning it's a genuine app-level issue, not user-library corruption), the sequence is:

1. **Delete derived data and caches** (see above).
2. **Re-sign or re-grant quarantine clearance:**
   ```bash
   # Remove the quarantine flag (for apps that fail to launch after download)
   xattr -d com.apple.quarantine /Applications/AppName.app

   # Check current extended attributes
   xattr -l /Applications/AppName.app
   ```
3. **Re-install the app** — drag to Trash, empty, reinstall. On Apple Silicon, ensure the app is natively compiled (Universal or ARM-native) vs. Rosetta — check via Get Info (`⌘-I` in Finder), "Kind: Application (Universal)" or "Application (Intel)". Rosetta-translated apps have their own translation cache in `/var/db/oah/`.

---

## The Canonical Diagnostic Instrument Stack

| Tool | What it answers | Where to reach it |
|---|---|---|
| `log show --predicate` | What happened, and when, at subsystem resolution | `man log`; see [[10-unified-logging-and-diagnostics]] |
| Console.app | Same as `log`, with GUI timeline, crash viewer | `/System/Applications/Utilities/Console.app` |
| Activity Monitor | Who is consuming CPU/RAM/energy/network right now | `/System/Applications/Utilities/Activity Monitor.app` |
| `spindump` | Thread call stacks when a process is beachballing | `sudo spindump <pid> 10 10 -file /tmp/spin.txt` |
| `sample` | Timed call-stack sample of a running process | `sudo sample <pid> 10 -file /tmp/sample.txt` |
| `fs_usage` | What files/sockets a process is touching | `sudo fs_usage -w -f filesys <pid>` |
| Disk Utility (Recovery) | First Aid; fsck_apfs on unmounted volume | Boot Recovery → Disk Utility |
| Apple Diagnostics | Hardware subsystem health | Hold D / Cmd-D at boot |
| `sysdiagnose` | Collect everything for Apple or forensic analysis | `sudo sysdiagnose -f /tmp/ -A mysys` |

### Reading the Unified Log for a Specific Problem

The `log` command is the single most powerful diagnostic tool on macOS. The key is writing a targeted predicate rather than streaming everything. Examples:

```bash
# All errors and faults from the last 30 minutes (good first-pass)
log show --last 30m --predicate 'messageType == 16 || messageType == 17' --info

# Follow a crashing app in real time (replace bundle ID)
log stream --predicate 'subsystem == "com.apple.launchservices" OR process == "MyApp"' --level debug

# What was happening in the 10 seconds before a kernel panic at 14:32:15
log show --start '2026-06-13 14:32:05' --stop '2026-06-13 14:32:15' \
  --predicate 'process != "logd"' --info

# TCC decision log (who got granted/denied what)
log show --predicate 'subsystem == "com.apple.TCC"' --last 1h --info

# Network extension / VPN misbehaving
log show --predicate 'subsystem BEGINSWITH "com.apple.network"' --last 30m --info

# App crash post-mortem (find the exception type and thread)
log show --predicate 'process == "MyApp" AND messageType >= 16' --last 2h
```

`messageType` values: `16` = error, `17` = fault. Using `--info` exposes info-level messages that are hidden by default (they are not written to the persistent store on disk but are available in the in-memory ring buffer if you act fast enough after the event).

---

## Symptom-to-Step Decision Tree

### Mac Won't Boot

```
Power on → no chime / no Apple logo
  → Hold D: run Apple Diagnostics
    → Hardware fault reported → hardware repair
    → Clean → continue

Apple logo → progress bar stalls/freezes
  → Boot Recovery (Shift-Opt-Cmd-R or hold power → Options)
  → Disk Utility → First Aid on Macintosh HD (Data volume)
    → Errors repaired → try normal boot
    → Persistent → reinstall macOS via Recovery (non-destructive)

Boots to login screen → crashes before desktop
  → Try Safe Mode (hold power, Shift at disk selection)
    → Safe Mode works → third-party login agent or system extension is the culprit
      → Check ~/Library/LaunchAgents/ and /Library/LaunchAgents/
      → Remove candidates one at a time, normal boot test each
    → Safe Mode also crashes → likely kernel or system service
      → Boot Recovery → Terminal → check /Library/Logs/DiagnosticReports/*.panic
```

### Beachball / Spinning Wait Cursor

The "beachball" (NSRunLoop > 4s wait) means the **main thread of one app** is blocked. This is almost never an OS bug — it is almost always the specific application.

```bash
# While it's spinning, capture a spindump
sudo spindump -wait 10 -file /tmp/beach.txt
# Then read it: the blocked thread will show the call stack that's waiting
```

Common causes: synchronous I/O on the main thread (network call, slow disk, NFS mount), deadlock waiting for a semaphore, infinite loop. The spindump call stack will show exactly which function is spinning.

If the **entire system** is sluggish (beachball in every app, Dock, Finder), the problem is resource exhaustion — check Activity Monitor's CPU and Memory tabs. "Memory pressure" in the red means the system is heavily compressing pages and spilling to swap. Sort by CPU% to find the dominant consumer.

### App Crashes on Launch

```
1. Check ~/Library/Logs/DiagnosticReports/<AppName>*.crash
   → Read "Exception Type" and "Termination Reason"
   → EXC_BAD_ACCESS: memory fault (usually a stale plist or corrupt container)
   → SIGABRT: deliberate abort (assertion failure; read "Application Specific Information")
   → EXC_CRASH (SIGKILL): killed by the OS — check for "sandbox violation", "memory limit", or Gatekeeper rejection in the unified log

2. Move aside the plist (~/Library/Preferences/<bundle-id>.plist) + cfprefsd flush
3. Move aside ~/Library/Application Support/<bundle-id>/ (sandbox container)
4. Re-download and reinstall
5. Test in a fresh user account
```

> 🔬 **Forensics note:** Crash reports in `/Library/Logs/DiagnosticReports/` and `~/Library/Logs/DiagnosticReports/` are valuable artifacts. They contain the exact binary UUID (cross-reference the dSYM for symbolication), the OS build number, running threads, and the exception address. The filename timestamps are wall-clock time in local timezone.

### No Network

```
1. System Settings → Network → check interface status
   → Green dot but no connectivity → check default route and DNS
     sudo networksetup -getdnsservers Wi-Fi
     route -n get default
     networkQuality  # built-in macOS Sequoia+ bandwidth/latency test

2. Flush DNS cache
   sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder

3. Check for VPN/proxy hijacking all traffic
   networksetup -getwebproxy Wi-Fi

4. Check if a third-party network extension is filtering packets
   log show --predicate 'subsystem BEGINSWITH "com.apple.network"' --last 10m --info
   systemextensionsctl list  # shows active system extensions

5. Safe Mode: network extensions are unloaded → confirms layer
6. Create new network location: System Settings → Network → "..." → Add Location
```

### Slow (System-Wide)

```
1. Activity Monitor → CPU tab → sort by % CPU
   → Spotlight (mds, mds_stores) → wait; reindexing after update is normal (30–60 min)
   → kernel_task at high CPU → macOS throttling the CPU due to thermal pressure
     Check: sudo powermetrics --samplers thermal -n 1
   → Any other daemon → investigate with fs_usage / sample

2. Activity Monitor → Memory tab
   → Memory Pressure graph in red → swap pressure; consider RAM upgrade
   → "Compressed" very large → legitimate memory exhaustion

3. Activity Monitor → Disk tab
   → Persistent high write by one process → runaway logging, database rebuild

4. mdutil -s / → if Spotlight is indexing, exclude slow-recovery dirs temporarily
```

### Kernel Panic (Recurring)

```
1. ls /Library/Logs/DiagnosticReports/*.panic | wc -l  → how many recent panics?
2. Read the most recent panic (see above anatomy guide)
3. Search the panic string on Apple Developer Forums + support.apple.com
4. If a third-party kext appears in the backtrace:
   → systemextensionsctl list → identify vendor
   → Uninstall that vendor's software; test
5. If panics started after a macOS update:
   → File feedback via Feedback Assistant with sysdiagnose attached
6. If random (different backtraces, no kext implicated):
   → Apple Diagnostics extended memory test (Cmd-E in Diagnostics)
   → If clean → swap out the third-party RAM (Intel Mac) or schedule Apple service
```

---

## sysdiagnose — When to Use It and What It Captures

`sysdiagnose` is a shell script (`/usr/bin/sysdiagnose`) that coordinates capture of: unified log archive (`.logarchive`), spindumps of all processes, network diagnostics, system configuration, kernel state, and crash reports into a single dated `.tar.gz`. It is what Apple Support asks for and what serious forensic analysis starts from.

```bash
# Generate sysdiagnose (takes 1–5 minutes; writes to /var/tmp/ by default)
sudo sysdiagnose

# Specify output directory and archive name
sudo sysdiagnose -f ~/Desktop/ -A incident_2026_06_13

# Keyboard shortcut (works while the symptom is active — best timing)
# Ctrl-Opt-Cmd-Shift-Period — triggers a background sysdiagnose
```

**Use sysdiagnose when:**
- You are about to file a Feedback Assistant report for a reproducible OS-level bug.
- You are handing off evidence to another analyst.
- The symptom is intermittent and you want a comprehensive snapshot captured right at occurrence.

**Do not use sysdiagnose** as your first diagnostic step — it takes minutes to generate and produces gigabytes you then have to search. Use targeted `log show` predicates first, then sysdiagnose to preserve evidence for external analysis.

After capturing: `open /var/tmp/*.tar.gz` to inspect the archive. The unified log portion is the `.logarchive` file inside — open it with Console.app or query it:

```bash
log show --archive /path/to/sysdiagnose.logarchive \
  --predicate 'process == "MyApp"' --last 24h
```

---

## The macOS Virus Prior

macOS malware exists — but the base rate is dramatically lower than Windows, and the most common causes of "acting weird" are: a corrupt plist, a misbehaving login agent, a Spotlight reindex, a memory leak, or a macOS update that reset a permission. Before going down a malware investigation path, exclude all of the above.

When malware IS the hypothesis: look for unexpected `LaunchAgents` (`/Library/LaunchAgents/`, `~/Library/LaunchAgents/`) and `LaunchDaemons` (`/Library/LaunchDaemons/`) with unfamiliar bundle IDs. Check `systemextensionsctl list` for unexpected network or endpoint security extensions. The unified log with a predicate for `subsystem == "com.apple.security.mac"` shows SIP-touching operations.

> 🔬 **Forensics note:** Legitimate macOS malware on Apple Silicon must be signed (or run via SIP-disabling modifications) and must pass Gatekeeper. Persistence almost always runs through `launchd` — `/Library/LaunchDaemons/` (system-persistent) or `~/Library/LaunchAgents/` (user-persistent). Both are excellent first collection points in a triage. See [[08-security-architecture]] and Part 05 Security & Forensics for the full evidence chain.

---

## Hands-on (CLI & GUI)

### Read a Crash Report

```bash
# Find the most recent crash for any process
ls -lt ~/Library/Logs/DiagnosticReports/*.crash 2>/dev/null | head -5

# Open it in a text editor (it's plain text)
cat ~/Library/Logs/DiagnosticReports/<AppName>*.crash | head -80
```

Key fields to read: `Exception Type`, `Termination Reason`, `Crashed Thread` (cross-reference to the thread backtrace below), `Binary Images` (find the app's UUID and load address for symbolication).

### Capture a Beachball in Action

```bash
# While the spinner is visible, in another Terminal window:
sudo spindump -wait 5 -file /tmp/spin_$(date +%s).txt
open /tmp/spin_*.txt
```

The output groups threads by process and shows the call stack. Look for the blocked thread labeled `[main thread]` in the spinning app — it will show the exact function call that is waiting.

### Check What a Process is Actually Doing

```bash
# Which files is Safari touching RIGHT NOW?
sudo fs_usage -w -f filesys $(pgrep -x Safari) 2>/dev/null | head -50

# What system calls is it making?
sudo dtruss -p $(pgrep -x Safari) 2>&1 | head -50
```

### Quick System Health Snapshot

```bash
# CPU, memory, thermal in one shot (requires sudo)
sudo powermetrics --samplers cpu_power,thermal -n 1 -i 1000

# Disk pressure and I/O
iostat -w 2 5

# Top memory consumers (non-interactive, one shot)
ps -Amco pid,rss,vsz,command | sort -k2 -rn | head -20

# All network connections (who is phoning home right now)
sudo lsof -i -n -P | grep ESTABLISHED
```

---

## 🧪 Labs

### Lab 1: Plist Corruption Simulation and Repair

This lab plants a broken preference plist for a real app (TextEdit, which is harmless to break temporarily) and walks through the canonical repair sequence.

> ⚠️ **ADVANCED:** This modifies TextEdit's preferences. **Rollback:** rename `TextEdit.plist.bak` back to `TextEdit.plist` and run `killall cfprefsd`. The app will be fully restored.

```bash
# Step 1: Confirm TextEdit is closed
osascript -e 'tell application "TextEdit" to quit' 2>/dev/null; sleep 1

# Step 2: Plant a corrupt plist (write invalid XML)
cp ~/Library/Preferences/com.apple.TextEdit.plist \
   ~/Library/Preferences/com.apple.TextEdit.plist.bak

printf 'CORRUPT' > ~/Library/Preferences/com.apple.TextEdit.plist

# Step 3: Observe the error — launch TextEdit and watch the log
open -a TextEdit &
log stream --predicate 'process == "TextEdit" OR process == "cfprefsd"' \
  --level default &
LOG_PID=$!
sleep 5
kill $LOG_PID 2>/dev/null

# Step 4: TextEdit likely opened with defaults (macOS auto-regenerates on parse error)
# Now perform the canonical clean repair
osascript -e 'tell application "TextEdit" to quit' 2>/dev/null; sleep 1
killall cfprefsd
sleep 1
open -a TextEdit

# Step 5: Restore original prefs
osascript -e 'tell application "TextEdit" to quit' 2>/dev/null; sleep 1
mv ~/Library/Preferences/com.apple.TextEdit.plist.bak \
   ~/Library/Preferences/com.apple.TextEdit.plist
killall cfprefsd
echo "Restored original TextEdit preferences."
```

**Expected outcome:** In Step 3, the log shows `cfprefsd` emitting an error about the malformed plist, then TextEdit launching with factory defaults. This demonstrates that macOS gracefully handles plist corruption rather than crashing — the symptom in production would be mysteriously reset preferences, not an app crash.

---

### Lab 2: Fresh-User Account Isolation

> ⚠️ **Requires admin access.** Creates a temporary standard user. **Rollback:** Delete the user in System Settings → Users & Groups after the lab.

```bash
# Create a temporary test user (command line)
sudo sysadminctl -addUser tempdiag -password "Temp1234!" -hint "lab" -fullName "Temp Diag"

# Verify it was created
dscl . -read /Users/tempdiag UserShell
```

Then: Fast User Switch to `tempdiag` (menu bar clock → user list), log in, and reproduce whatever symptom you are investigating. If it does NOT reproduce: the problem is isolated to your user account's `~/Library`. Delete `tempdiag` when done.

---

### Lab 3: Read a Kernel Panic Log (Or Simulate One)

```bash
# List any existing panic logs on this machine
ls -lh /Library/Logs/DiagnosticReports/*.panic 2>/dev/null \
  || echo "No panic logs found — machine is healthy."

# If no panic logs, download a sanitized sample from Apple's WWDC sessions
# or use this command to read the log structure if one exists:
if ls /Library/Logs/DiagnosticReports/*.panic &>/dev/null; then
  PANIC=$(ls -t /Library/Logs/DiagnosticReports/*.panic | head -1)
  echo "=== PANIC FILE: $PANIC ==="
  echo "--- Panic string (first meaningful line) ---"
  grep -A3 "^panic" "$PANIC" | head -10
  echo "--- Process at panic ---"
  grep "BSD process name" "$PANIC"
  echo "--- Third-party kexts (AKC) ---"
  grep -A2 "Kernel Extensions in backtrace" "$PANIC" || echo "(none in backtrace)"
  echo "--- iBoot / Secure Boot ---"
  grep -E "iBoot|secure boot" "$PANIC"
fi
```

For each field you extract, ask: Was a third-party kext in the backtrace? What was the BSD process name? What was the exception type? Does the panic string match any known Apple Developer Forums report?

---

### Lab 4: Unified Log Triage on a Real Symptom

Pick any system event that happened in the last hour (a Spotlight reindex, an app update, a login) and trace it in the log:

```bash
# Find the last Spotlight reindex event
log show --last 3h \
  --predicate 'process == "mds" AND eventMessage CONTAINS "index"' \
  --info | tail -20

# Find the last app installation (Installer or softwareupdate)
log show --last 24h \
  --predicate 'process == "Installer" OR process == "softwareupdate"' \
  --info | tail -30

# Find any TCC permission decisions in the last hour
log show --last 1h \
  --predicate 'subsystem == "com.apple.TCC"' --info | tail -20
```

**Goal:** Practice writing predicates narrow enough to return under 100 results but broad enough to capture the relevant event. The discipline of predicate-first querying is the difference between useful log analysis and a firehose you ignore.

---

## Pitfalls & Gotchas

**The cfprefsd flush trap.** Deleting a plist file without killing `cfprefsd` is ineffective — the daemon holds the plist in memory and writes it back within seconds. Always `killall cfprefsd` after moving a plist aside. The daemon restarts automatically.

**Safe Mode does not fix disk problems.** Contrary to popular belief (and older documentation), Safe Mode no longer performs substantive fsck. Actual disk repair requires booting Recovery and running Disk Utility First Aid on the unmounted data volume.

**NVRAM reset is not meaningful on Apple Silicon.** The Cmd-Opt-P-R key combo at boot is Intel-only. On Apple Silicon, `sudo nvram -c` from within the OS clears user-settable NVRAM variables, but iBoot-owned secure variables (Secure Boot policy, boot disk) are only modifiable from Recovery.

**The "permissions repair" myth.** The "Repair Disk Permissions" option in Disk Utility was removed in macOS El Capitan (10.11). There is no equivalent operation in modern macOS — SIP protects system files, and POSIX permissions on user files are not a common corruption vector. If someone advises "repair permissions," they are describing a pre-2015 workflow.

**Activity Monitor's "% CPU" for kernel_task is misleading.** High `kernel_task` CPU is the OS *intentionally consuming CPU time to throttle thermal output* — it is a symptom of thermal pressure, not a bug in `kernel_task`. Check `powermetrics --samplers thermal` to see the actual temperature and throttling state.

**Quarantine != Gatekeeper rejection.** The `com.apple.quarantine` extended attribute just flags the file for Gatekeeper inspection on first launch. Apps that were notarized pass that check. Apps that are NOT notarized will fail with "Apple cannot check it for malicious software" — removing quarantine with `xattr -d com.apple.quarantine` bypasses the check entirely (risky). A better approach is to right-click → Open in Finder, which prompts for explicit user override without removing the attribute.

**Two-login Safe Mode is NOT a bug.** On Apple Silicon, the first Safe Mode login is FileVault unlock (decryption key derivation from your password); the second login is the actual user session. You will see your normal desktop after the second login — this is intended behavior since macOS Ventura.

---

## Key Takeaways

- Work the diagnostic **ladder** — hardware → firmware → kernel → services → user library → app — and stop at the first layer that isolates the symptom. Never skip to app reinstall without excluding upper layers.
- **Safe Mode** is the fastest layer-2/3/4 test: if it eliminates the symptom, third-party extensions or login items or font caches are implicated.
- **Fresh user account** is the fastest layer-4/5 test: if it eliminates the symptom, the problem is in `~/Library`.
- **cfprefsd must be killed** when moving plists aside; otherwise the daemon re-writes from its in-memory cache.
- **Kernel panics are readable documents** — the panic string, BSD process name, and kext list in the backtrace usually identify the responsible component within two minutes of reading.
- **TCC, not POSIX**, is usually the permission blocker when a user-owned file is inaccessible to an app. Diagnose with `tccutil` and the `com.apple.TCC` log subsystem.
- **NVRAM reset and SMC reset** are Intel-era concepts; neither has a meaningful equivalent on Apple Silicon (for NVRAM) or exists at all (for SMC).
- **sysdiagnose** is for "I found the layer, now I need to preserve evidence or file a bug report" — not for initial triage.
- The **`log` command with a targeted predicate** is the single most powerful diagnostic tool available — it correlates any symptom with system-level events at microsecond resolution.

---

## Terms Introduced

| Term | Definition |
|---|---|
| Diagnostic Ladder | The ordered layer model (hardware → firmware → kernel → services → user → app) for systematic fault isolation |
| Apple Diagnostics | Firmware-level hardware test accessed by holding D (Intel) or Cmd-D in startup options (Apple Silicon) at boot |
| Kernel panic | Unrecoverable kernel exception that forces a reboot; logged to `/var/db/PanicReporter/*.panic` |
| Auxiliary Kernel Collection (AKC) | The kext/system extension collection for third-party (non-Apple) code; disabled in Safe Mode |
| Safe Mode | Boot configuration that blocks AKC, non-Apple login items, and third-party fonts; entered by holding Shift at disk selection on Apple Silicon |
| `cfprefsd` | The preference daemon that caches plist data in memory; must be killed when manipulating plist files on disk |
| TCC (`tccd`) | Transparency, Consent, and Control — the two-instance daemon managing privacy permissions (microphone, camera, Accessibility, Full Disk Access, etc.) |
| `tccutil` | CLI tool to reset TCC permission entries by service and/or bundle ID |
| `spindump` | Tool that captures thread call stacks for all running processes; used to diagnose beachball/hang |
| `fs_usage` | Kernel-level syscall tracer for file system and network events, filterable by PID |
| `sysdiagnose` | Script that captures a comprehensive system snapshot (log archive, spindumps, network state) for filing with Apple or forensic handoff |
| sysdiagnose logarchive | The `.logarchive` embedded in a sysdiagnose tarball; queryable offline with `log show --archive` |
| NVRAM | Non-volatile RAM storing firmware boot variables; clearable with `sudo nvram -c` (user-settable only on Apple Silicon) |
| SMC | System Management Controller — Intel/T2 chip managing power, fans, and thermal; replaced by embedded firmware in Apple Silicon |
| `mdutil` | CLI tool to manage Spotlight indexing state per volume (`-E` to erase and rebuild, `-i off/on` to disable/enable, `-s` to check status) |

---

## Further Reading

- **Apple Platform Security Guide** (2024–2025 edition) — covers SIP, TCC, Gatekeeper, Secure Boot in engineering depth: [developer.apple.com/documentation/security](https://developer.apple.com/documentation/security)
- **Eclectic Light Company — How to deal with a kernel panic** (Howard Oakley, 2025): [eclecticlight.co/2025/02/19/how-to-deal-with-a-kernel-panic/](https://eclecticlight.co/2025/02/19/how-to-deal-with-a-kernel-panic/)
- **Eclectic Light Company — When you should use Safe Mode, and what it does** (2025): [eclecticlight.co/2025/03/21/when-you-should-use-safe-mode-and-what-it-does/](https://eclecticlight.co/2025/03/21/when-you-should-use-safe-mode-and-what-it-does/)
- **Der Flounder — Using subsystem and category log predicates on macOS Sequoia** (2025): [derflounder.wordpress.com](https://derflounder.wordpress.com/2025/08/24/using-subsystem-and-category-log-predicates-when-searching-the-unified-system-log-on-macos-sequoia/)
- **ElcomSoft blog — Extracting and Analyzing Apple Unified Logs** (2025): [blog.elcomsoft.com/2025/06/extracting-and-analyzing-apple-unified-logs/](https://blog.elcomsoft.com/2025/06/extracting-and-analyzing-apple-unified-logs/)
- **`man sysdiagnose`**, **`man log`**, **`man spindump`**, **`man fs_usage`**, **`man dtruss`** — all available locally
- **Related lessons in this course:** [[01-boot-process]], [[08-security-architecture]], [[10-unified-logging-and-diagnostics]], [[05-launchd-and-the-launch-system]]
