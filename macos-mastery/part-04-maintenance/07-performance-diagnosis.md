---
title: Performance Diagnosis
part: P04 Maintenance
est_time: 60 min read + 45 min labs
prerequisites: [07-memory-virtual-memory-and-swap, 06-processes-mach-and-xpc, 05-launchd-and-the-launch-system, 10-unified-logging-and-diagnostics]
tags: [macos, performance, diagnosis, activity-monitor, powermetrics, memory, thermal, spindump]
---

# Performance Diagnosis

> **In one sentence:** macOS slowness is never one thing — matching the right instrument to each bottleneck layer (CPU, memory, disk I/O, thermal, startup) is the skill, and this lesson gives you that map.

## Why this matters

A forensics professional who can diagnose a slow Mac cold is far more effective than one who cargo-cults "restart and clear caches." macOS exposes genuinely deep instrumentation — most of it inherited from BSD, extended by Apple, and layered under a GUI that hides the best parts. Every byte of that instrumentation leaves artifacts: timestamps, process accounting records, compressed memory statistics, SMC readings. That means performance diagnosis and forensic investigation overlap more than you'd expect.

> 🪟 **Windows contrast:** Windows gives you Task Manager (coarse), Resource Monitor (medium), and Performance Monitor / WPA (deep). macOS has the same three tiers — Activity Monitor, the `top`/`vm_stat`/`iostat` family, and Instruments/`xctrace` — but the low-level layer is POSIX-native and scriptable without COM or WMI. The Unified Log ([[10-unified-logging-and-diagnostics]]) also gives macOS diagnosis a leg up: Windows Event Log is nowhere near as dense or queryable.

---

## Concepts

### The bottleneck taxonomy

Before reaching for any tool, classify the symptom:

| Symptom | Likely bottleneck | First instrument |
|---|---|---|
| Everything sluggish, fans spin up | CPU saturation or thermal throttle | Activity Monitor → CPU / `powermetrics` |
| Spinning beachball on one app | Main-thread block | `sample <pid>` / `spindump` |
| System-wide beachball, hard to click anything | Kernel task or GPU pressure | Activity Monitor → GPU History / `sudo fs_usage` |
| Sluggish after importing files or upgrading | Spotlight re-indexing | Activity Monitor → `mds_stores` CPU / `mdutil -s /` |
| Things get slow after hours of use, not at boot | Memory leak / pressure buildup | Activity Monitor → Memory pressure graph / `footprint` |
| Slow boot or login | Login items / launch agents | System Settings → Login Items / `launchctl list` |
| Sudden throttle under sustained load (MacBook Air) | Thermal throttle | `powermetrics --samplers smc` / `pmset -g thermlog` |
| Disk writes continuous, even at idle | Background indexer or swap storm | `iostat -w 1` / `fs_usage -f filesys` |

Keep this table in your head as a decision tree. Every section below expands one row.

---

### Activity Monitor: the right way to read it

Activity Monitor (`/System/Applications/Utilities/Activity Monitor.app`) has five tabs. Most people only ever see CPU. Here is what each tab actually tells you:

#### CPU tab

- **% CPU** — percentage of one logical core. An 8-core M3 Max can show values up to ~800%. A process at 800% is pegging all performance cores.
- **Avg CPU (Energy column)** — the most honest number for background load. A daemon spinning at 0.1% average CPU for 24 hours costs more than a compressor that hits 40% for 30 seconds. Sort by this column to find chronic offenders, not acute spikes.
- **Kernel task** — `kernel_task` is macOS intentionally consuming CPU to *raise chip temperature* so the actual thermal management firmware can throttle power. If it is at 200%+, you have a thermal problem, not a `kernel_task` bug.

> 🔬 **Forensics note:** The process list in Activity Monitor reflects `proc_listallpids()` — all processes visible to your UID. Root processes and GPU processes are there. The hidden "All Processes, Hierarchically" view (View menu) reveals the full `launchd` process tree, useful for tracing which agent spawned a suspect process.

#### Memory tab

The number that matters is **not** "Free" — it is the **Memory Pressure** graph color.

- **Green**: the unified buffer cache, compressed memory, and wired pages are balancing cleanly. Free memory near zero is *normal and correct* — macOS aggressively caches.
- **Yellow**: compression is active, the system is reclaiming inactive pages. Watch; not yet a problem.
- **Red**: page-outs to the swap file on disk are occurring at a rate that's measurably slowing the system. This is the threshold. On an SSD it's less catastrophic than on spinning rust, but sustained swap degrades everything.

**What the numbers mean:**

- **Wired Memory** — kernel, Kexts (rare on Apple Silicon), graphics buffers, IOKit memory maps. Cannot be compressed or paged.
- **App Memory** — heap + dirty private pages of user processes.
- **Compressed** — pages the Compressor kernel thread has squashed in-RAM (Apple's WKdm algorithm). A healthy system shows several GB compressed without going red.
- **Swap Used** — pages actually written to `/private/var/vm/swapfile*`. Any number here means compression wasn't enough.
- **Cached Files** — clean file-backed pages. macOS will silently evict these as needed; they are the "free memory you can use."

#### Disk tab

Shows aggregate read/write bytes and I/O operations per second across all processes. Sort by "Writes/sec" during a suspected write-storm. The Disk tab does not show *which files* — for that, you need `fs_usage`.

#### Network tab

Per-process bytes sent/received. Useful for identifying which process is hammering iCloud, CloudKit, or a CDN. `cloudd`, `nsurlsessiond`, `apsd` (Apple Push), and `com.apple.WebKit.Networking` are common high-bandwidth background processes.

#### GPU History

Window → GPU History (or Cmd-4 shortcut changed in Tahoe — check View menu). Shows GPU utilization split by renderer and compute workloads. On M-series chips, both the GPU and Neural Engine can appear here depending on what ANE-enabled frameworks are running. High GPU at idle often points to a browser with hardware-accelerated video, a screensaver, or a runaway Metal compute shader.

#### Force Quit

The Force Quit button in Activity Monitor sends `SIGKILL` directly — it does not go through the graceful quit path. Equivalent to `kill -9 <pid>`. Use it freely on hung processes; macOS will clean up their Mach ports, file descriptors, and XPC connections via [[06-processes-mach-and-xpc]].

---

### The beachball: decoding a main-thread block

The "spinning wait cursor" (SPWC, affectionately called the beachball or SBBOD) means exactly one thing: the application's **main run loop** has not returned control to AppKit/UIKit within a deadline (roughly 2–4 seconds depending on the event type). This is a UI-layer mechanism, not a kernel one.

#### Why it happens

- Main thread is doing synchronous I/O (reading from NFS, a spinning drive, or a very slow SSD under heavy I/O pressure)
- Main thread is blocking on a lock held by a background thread
- Main thread is doing heavy CPU work (large JSON parse, regex on a huge string) synchronously
- Deadlock: two threads each hold a lock the other needs

#### `sample` — capture a live process

`sample` attaches via `proc_info`/task_threads and samples the call stacks of all threads at 1 ms intervals for 10 seconds by default.

```bash
# Sample PID 1234 for 10 seconds, 1ms interval
sample 1234 10 1 -file /tmp/sample_1234.txt

# Or use the process name
sample "Safari" 10
```

The output is a call tree showing which function is consuming time. Lines near the top of the tree are hot. When the main thread shows `mach_wait_until`, `pthread_cond_wait`, or `semaphore_wait_trap` at the top, it is blocked — find what holds the lock.

#### `spindump` — capture a hung/unresponsive process

`spindump` is the same mechanism the OS uses to auto-generate crash reports for hung processes. It captures the call stacks of *all threads* of *all processes* at the moment of invocation (a system-wide snapshot), or can target one PID.

```bash
# Targeted: dump a specific PID
sudo spindump 1234 10 10 -file /tmp/spindump_1234.spindump

# System-wide snapshot (no PID) — captures everything
sudo spindump -file /tmp/system_spindump.spindump

# Watch for hung processes continuously
sudo spindump -reveal
```

The output file has `.spindump` extension and opens in the Spindump Viewer (Instruments). The key section is **Binary Images** (tells you load addresses for symbolicating) and the **Thread State** (look for "Thread 0" — the main thread — showing `__CFRunLoopRun` blocked on something).

> 🔬 **Forensics note:** macOS auto-generates spindumps in `/Library/Logs/DiagnosticReports/` for any process that becomes unresponsive for more than ~20 seconds before the user force-quits it. These files are timestamped and persist across reboots. They are gold for incident reconstruction — they capture the exact call stack of a hung process, the thread states, and all loaded dylibs (with UUIDs you can use to symbolicate against dSYMs). See also [[10-unified-logging-and-diagnostics]] for the correlation with `log show`.

---

### CPU deep dive: `top` and `powermetrics`

#### `top`

```bash
# Sort by CPU, refresh every 2 seconds
top -o cpu -s 2

# Show only processes consuming > 5% CPU
top -o cpu -stats pid,command,cpu,rsize,vsize -F
```

Press `?` inside `top` for the interactive key reference. `o cpu` sets sort order; `o rsize` sorts by resident memory.

#### `powermetrics` — the real CPU truth

`powermetrics` reads from the PMU (Power Management Unit) and SMC (System Management Controller) directly. It is the only tool that gives you **per-core CPU utilization, P-state / frequency**, power draw in watts, and die temperature — none of which appear in Activity Monitor.

```bash
# General overview: CPU + GPU + memory + network, every 2 seconds
sudo powermetrics --samplers cpu_power,gpu_power,thermal,smc -i 2000

# Focus on thermal / SMC readings only
sudo powermetrics --samplers smc -i 1000

# Write to file for later analysis
sudo powermetrics --samplers all -i 1000 -n 60 -o /tmp/pm_60samples.txt
```

Key fields to read in the output:

- **CPU Power (W)** — actual watts drawn by the CPU package
- **E-cluster / P-cluster idle %** — how much time efficiency and performance cores spend idle. E-cluster at 0% idle means all efficiency cores are pegged.
- **GPU Power (W)** — integrated GPU draw
- **Die temperature (°C)** — from SMC; the number the throttle firmware watches
- **Frequency (MHz)** — if this is significantly below the chip's boost frequency during a heavy workload, you are being throttled

> 🔬 **Forensics note:** `powermetrics` output is structured text with timestamps. Running it to a log file during an incident (e.g., a performance regression after an update) creates a timeline you can cross-correlate with Unified Log events.

---

### Memory pressure: going deep

#### `vm_stat` — the kernel's page accounting

```bash
vm_stat 2    # refresh every 2 seconds
```

On Apple Silicon, each page is **16,384 bytes (16 KB)**. Multiply page counts by 16384 to get bytes.

Critical fields:

| Field | What it means |
|---|---|
| `Pages active` | In-RAM pages recently referenced |
| `Pages inactive` | Resident but not recently used; evictable |
| `Pages wired down` | Kernel/locked; cannot be evicted |
| `Pages occupied by compressor` | Compressed pages in the Compressor's store |
| `Pageins` / `Pageouts` | Cumulative pages moved in/out of swap |
| `Compressions` / `Decompressions` | Cumulative Compressor operations |

**The diagnostic signal**: if `Pageouts` is nonzero and climbing, you are swapping. If `Compressions` is climbing without Pageouts, the system is handling pressure well in-RAM.

```bash
# One-liner: watch pageouts accumulate
while true; do
  vm_stat | awk '/pageouts/ {print "Pageouts:", $2}'; sleep 2
done
```

#### `memory_pressure` — the simple verdict

```bash
memory_pressure
```

Prints a human-readable verdict: `System-wide memory free percentage: 63%` (or similar) followed by the current memory pressure state. Less informative than `vm_stat` but good for a quick sanity check in a script.

#### Finding the leaker with `footprint`

`footprint` is a developer tool installed with Xcode Command Line Tools that queries `task_info()` to break down a process's memory into categories:

```bash
# Requires target PID; get it from Activity Monitor or pgrep
footprint -pid $(pgrep -x Safari)
```

Output breaks down **Dirty**, **Swapped**, **Resident**, and **Virtual** memory with per-region annotation. This is how you find whether Safari's 4 GB reported in Activity Monitor is actually in RAM or swapped out.

For finding *leaks specifically*:

```bash
leaks <pid>       # prints malloc blocks with no live references
vmmap <pid>       # full VM region map: heap, stacks, dylibs, anonymous
```

`vmmap | grep -E "MALLOC|__DATA"` narrows to heap and writable data segments — useful for finding which dylib or framework is accumulating dirty pages.

> 🪟 **Windows contrast:** The Windows equivalent is Process Explorer's "Private Bytes" vs "Working Set" distinction, plus the RAMMap SysInternals tool. `footprint` is roughly analogous to RAMMap but per-process and scriptable.

---

### Disk I/O thrash

#### `iostat` — block-level throughput

```bash
iostat -w 1        # per-second summary, 1-second interval
iostat -d disk0 1  # target a specific disk
```

Output shows KB/s read/written and transactions per second. A sustained write rate of several hundred MB/s at what should be an idle system is a red flag.

#### `fs_usage` — file-level I/O

`fs_usage` hooks into the kernel's VFS layer and shows every file system call in real time. It is the scalpel to `iostat`'s axe.

```bash
# All FS operations system-wide
sudo fs_usage

# Filter to a specific process
sudo fs_usage -f filesys Safari

# Filter to writes only (grep post-processing)
sudo fs_usage | grep -E "WrData|write"

# Find who is creating or writing specific paths
sudo fs_usage | grep "/private/var/folders"
```

The output columns are: timestamp, syscall, file path, latency (ms), and process name. High latency on `RdData` calls (>50 ms) during normal operation suggests I/O contention or a failing drive.

> 🔬 **Forensics note:** `fs_usage` output is a real-time file access log. From a forensics perspective it is equivalent to Windows file-system auditing (Sysmon Event ID 11) but without requiring pre-configuration — it works on any running system. Capturing `fs_usage` during a suspected data-exfiltration or ransomware-precursor scenario can identify which process is reading sensitive directories.

#### The Spotlight-reindex-after-update gotcha

After every major macOS update (and sometimes after minor point updates), `mds` re-indexes the entire boot volume. This manifests as:

- `mds` / `mds_stores` at 200–400% CPU in Activity Monitor
- Continuous disk writes visible in `iostat`
- Elevated fan speed and battery drain
- The system "feeling slow" for 15–90 minutes

**Diagnosis:**

```bash
# Check indexing status per volume
mdutil -s /
# Output: "Indexing enabled." (normal) or "Indexing and searching enabled." (actively indexing)

# See which files Spotlight is currently touching
sudo fs_usage -f filesys mds_stores | head -50

# Force-check if indexing is complete
sudo mdutil -a -p   # purges and rebuilds index (use with caution)
```

**Mitigation**: wait. The right call 90% of the time after an update is to plug in power and let `mds_stores` finish. If it is still thrashing after 2+ hours, then investigate.

To disable Spotlight indexing on a specific volume (e.g., a large external archive drive you do not need to search):

```bash
# ⚠️ ADVANCED: disables Spotlight on that volume
sudo mdutil -i off /Volumes/MyArchive
```

---

### Thermal throttling on fanless Macs

The MacBook Air (M1/M2/M3/M4) has no fan. Under sustained compute load it will throttle. This is by design — the chip's P-cores drop clock frequency to stay within the thermal envelope.

#### How throttling works on Apple Silicon

The `thermald` daemon reads die temperature via the SMC and publishes thermal pressure levels to the Darwin notification system via `notifyd`. The kernel's `pmset` power management framework responds by reducing the CPU's operating frequency. The relevant SMC keys are `TC0P` (CPU die temperature), `TP0P`, and related fields.

#### Diagnosing throttle

```bash
# SMC thermal readings via powermetrics
sudo powermetrics --samplers smc -i 500 | grep -E "CPU die|Fan|Throttle|Frequency"

# pmset thermal log
pmset -g thermlog
```

**Important caveat for Apple Silicon**: `pmset -g thermlog` may return "No thermal warning level has been recorded" on M-series Macs. Apple moved to a continuous thermal-pressure model (no discrete "warning level" events), so `pmset` is less useful here. Use `powermetrics` instead.

**The clearest signal**: in `powermetrics` output, watch the CPU P-cluster frequency drop from ~3.5 GHz to 1–2 GHz during a heavy sustained workload while die temperature is above ~95°C. That is throttle.

**Third-party tools**: `Hot` (macmade, open-source on GitHub) and `MacThrottle` provide menu-bar thermal pressure indicators that query the same SMC data via `IOKit`. Useful for a persistent visual indicator without running a terminal session.

> 🪟 **Windows contrast:** Windows uses `powercfg /energy` and Event ID 37 (Kernel-Power, "Processor ... thermal throttling") for thermal diagnosis. macOS buries this in `powermetrics` and the SMC. The Apple Silicon thermal management is tighter and more aggressive than most PC laptop implementations — you will see throttle sooner but the chips also recover faster once the load drops.

---

### Login and boot slowness

#### What happens during login (the quick model)

At login, `loginwindow` → `launchd` → user session agent → per-user LaunchAgents from `~/Library/LaunchAgents/` and `/Library/LaunchAgents/` (system-wide). Then `loginwindow` respawns any apps that were open at last logout (if "Reopen windows when logging back in" was checked). Only after all of this does the Dock become interactive.

#### Diagnosis

```bash
# List all running user launch agents
launchctl list | sort -k3

# Find which agents took longest — check their logs
log show --predicate 'process == "launchd"' --last boot | grep "spawning"

# Instruments timeline of launch: use xctrace (see Labs section)
```

In **System Settings → General → Login Items** (macOS 13+), the Login Items panel shows both traditional Login Items and the new `SMAppService`-registered background items (Extensions, Login Items, and Launch Agents registered by apps). Items you do not recognize are worth auditing.

**The "Reopen windows" trap**: if you had 47 browser tabs, two Electron apps, and a video editor open when you last logged out, macOS will attempt to restore all of them in parallel at next login. The state is stored in `~/Library/Saved Application State/`. Clearing this directory removes the restore state:

```bash
# ⚠️ This deletes window-restore state for all apps
rm -rf ~/Library/Saved\ Application\ State/
```

#### Isolating the slow item

The fastest diagnostic is binary elimination: disable half the login items, reboot, measure. Repeat on the slow half. Alternatively, create a new user account and time its login — if it is fast, the issue is in your user's Library, not the system.

> 🔬 **Forensics note:** Login items and launch agents are common persistence vectors for malware. The same `launchctl list` output you use for performance diagnosis is your persistence audit. Items with `com.apple.*` labels are Apple; everything else warrants a `cat` of the plist and a check of the `ProgramArguments`. See [[05-launchd-and-the-launch-system]] for the full agent/daemon taxonomy.

---

### Runaway daemons: the usual suspects

#### `mds` / `mds_stores` (Spotlight)

`mds` is the Spotlight metadata server; `mds_stores` is the per-volume index-writing process. Normal behavior: brief bursts after file changes. Pathological behavior: continuous high CPU for hours.

**Causes and fixes:**

| Cause | Fix |
|---|---|
| Post-update reindex | Wait 30–90 min; plug in power |
| External drive just connected | Wait; optionally `sudo mdutil -i off /Volumes/Drive` if you never need to search it |
| Corrupted index | `sudo mdutil -E /` (erase and rebuild); then wait |
| Loop on malformed metadata | `sudo killall mds`; check Console for `com.apple.metadata.mds` errors |

#### `photoanalysisd` / `mediaanalysisd`

These processes run ML inference (face detection, scene classification, object recognition) on your Photos library. They use the Neural Engine (ANE) on Apple Silicon, so they are fast and battery-efficient — but still visible in Activity Monitor during initial library analysis.

- `photoanalysisd`: Photos ML analysis (faces, memories)
- `mediaanalysisd`: Video and broader media ML (introduced macOS Ventura)

**When to worry**: If either is continuously high (>50% CPU for more than a day) after your library is stable — not after importing thousands of new photos — it may be looping on a corrupt asset. In Photos, find recently imported batches and check for assets that fail to thumbnail.

**To pause** (temporarily): System Settings → Siri & Spotlight → uncheck "Siri & Spotlight Suggestions" and Photo analysis toggles. Or simply close Photos and let the daemon idle.

#### `cloudd` / `bird` / `nsurlsessiond`

iCloud sync daemons. `cloudd` orchestrates CloudKit sync; `bird` handles iCloud Drive file sync; `nsurlsessiond` is the URL session broker for background network tasks.

- Heavy `cloudd` after first login to a new Mac is normal (initial metadata sync)
- Continuous `bird` after file changes is normal (delta sync)
- Runaway `bird` that will not settle: disconnect iCloud Drive temporarily in System Settings → Apple ID → iCloud Drive (toggle off), wait 30 seconds, re-enable

---

### Browser and Electron memory reality

Chromium-based browsers (Chrome, Edge, Arc, Brave) and Electron apps (Slack, VS Code, Discord, Figma) each embed a full Chromium rendering engine. Each tab and frame runs in a separate OS process (`--type=renderer` in their argv). On a system with 20 browser tabs:

- 20+ renderer processes × ~150 MB each = 3+ GB easily consumed
- V8's JIT heap is *dirty private memory* — it cannot be shared or compressed as efficiently as clean file-backed memory
- The browser process itself holds GPU buffers, compositor tiles, and the network cache

**Diagnosis:**

```bash
# See all Chrome/Chromium renderer processes and their memory
ps aux | grep -E "Chrome Helper|Electron" | awk '{print $4, $11, $12}' | sort -rn | head -20

# Or use footprint on the main browser PID
footprint -pid $(pgrep -x "Google Chrome") 2>/dev/null | head -30
```

**Practical guidance**: Activity Monitor's "Memory" column for a browser is the *sum across all helper processes*. A browser showing 4 GB is not a bug — it is the cost of 30 tabs with active web apps. The fix is tab management, not a memory cleaner app.

> 🪟 **Windows contrast:** Same problem, same cause. On Windows, `chrome://task-manager` (Shift+Esc) shows per-tab memory more conveniently than Task Manager. On macOS, the same `chrome://task-manager` page exists in Chrome-based browsers and is the fastest way to identify which specific tab is the pig.

---

### Instruments and `xctrace`

For deep profiling — the kind you need when `powermetrics` and `sample` tell you *that* something is slow but not precisely *where* — use Instruments.

**Instruments** is bundled with Xcode. Launch from `/Applications/Xcode.app/Contents/Applications/Instruments.app` or via `xctrace`.

#### Key Instruments templates

| Template | Use case |
|---|---|
| **Time Profiler** | CPU-level call tree; where cycles go |
| **Allocations** | Heap growth over time; finding leaks |
| **System Trace** | System call latency, thread scheduling, VM faults |
| **Network** | Per-connection latency and data rates |
| **Energy Log** | Battery impact per process over time |
| **Metal System Trace** | GPU command queues, render passes, frame timing |

#### `xctrace` — headless Instruments

```bash
# Record a 30-second Time Profiler trace of a PID
xctrace record --template "Time Profiler" \
               --attach $(pgrep -x Safari) \
               --time-limit 30s \
               --output /tmp/safari_profile.trace

# Open the trace in Instruments
open /tmp/safari_profile.trace
```

`xctrace` works without a GUI, making it CI/automation-friendly. The resulting `.trace` file opens in Instruments for visual analysis.

---

### The clean-account diagnostic

When you cannot isolate the cause, the most powerful move in the playbook is **test in a brand-new user account**:

1. System Settings → Users & Groups → Add User
2. Log out, log into the new account
3. Reproduce the workload

If the new account is fast, the cause is in your user's Library — a bad preference file, a corrupted cache, a launch agent, a sandboxed app's container. If the new account is equally slow, the cause is system-wide (a bad kext, a system launch daemon, hardware).

This divides the problem space perfectly and is faster than an hour of hypothesis-chasing.

> 🔬 **Forensics note:** Creating a test account also gives you a clean baseline process list. `launchctl list` in the new account shows only Apple-default items. Diffing that against your main account's agent list reveals everything your user environment adds.

---

## Hands-on (CLI & GUI)

### Check current memory pressure in one command

```bash
vm_stat | awk '
  /Pages free/      { free=$3 }
  /Pages active/    { active=$3 }
  /Pages inactive/  { inactive=$3 }
  /Pages wired/     { wired=$4 }
  /Pages occupied by compressor/ { compressed=$5 }
  /Pageins/         { pageins=$2 }
  /Pageouts/        { pageouts=$2 }
  END {
    ps = 16384
    printf "Free:       %7.1f MB\n", free*ps/1048576
    printf "Active:     %7.1f MB\n", active*ps/1048576
    printf "Inactive:   %7.1f MB\n", inactive*ps/1048576
    printf "Wired:      %7.1f MB\n", wired*ps/1048576
    printf "Compressed: %7.1f MB\n", compressed*ps/1048576
    printf "Pageins:    %d  Pageouts: %d\n", pageins, pageouts
  }
'
```

### Watch CPU top-5 by energy cost

```bash
top -o cpu -stats pid,command,cpu,power,rsize -n 5 -l 5 -s 2
```

(`-l 5` takes 5 log samples, `-n 5` shows 5 processes)

### Find processes with open file descriptors above a threshold

```bash
lsof -n | awk '{print $2}' | sort | uniq -c | sort -rn | head -10
```

A process with thousands of open file descriptors is worth investigating — could be a leaked descriptor bug contributing to I/O overhead.

### Real-time disk write identification

```bash
# Top writers every second
sudo iotop -C -d 1 2>/dev/null || iostat -w 1 5
```

(Note: macOS does not ship `iotop` by default; `brew install iotop` adds it. `iostat` is always available.)

---

## 🧪 Labs

### Lab 1: Capture a spindump of a hung application

**Goal**: Practice generating and reading a spindump before you need it in anger.

**Setup**: You need an app that blocks. Use the built-in TextEdit or any app you are willing to stress-test.

```bash
# Step 1: Open a Finder window, get its PID
FINDER_PID=$(pgrep -x Finder)
echo "Finder PID: $FINDER_PID"

# Step 2: Capture a 10-second spindump with 10ms sample rate
sudo spindump $FINDER_PID 10 10 -file /tmp/finder_spindump.spindump

# Step 3: Examine the output — look for Thread 0 (main thread)
grep -A 30 "Thread 0" /tmp/finder_spindump.spindump | head -40
```

**What you should see**: Thread 0 cycling through `CFRunLoopRunSpecific` → `__CFRunLoopRun` → event handling. This is the *healthy* beachball-free state. The run loop is waiting for events, not blocking.

**Extending the lab**: Use `stress-ng` (`brew install stress-ng`) to generate CPU load on another process, then sample it:

```bash
stress-ng --cpu 1 --timeout 30s &
STRESS_PID=$!
sample $STRESS_PID 5 1 -file /tmp/stress_sample.txt
open /tmp/stress_sample.txt   # opens in default text editor
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** The spindump at `/tmp/*.spindump` contains full stack traces and loaded library paths for every process. On a shared system, this is sensitive data. Delete after the lab: `rm /tmp/finder_spindump.spindump /tmp/stress_sample.txt`.

---

### Lab 2: Hunt the memory hog

**Goal**: Use `vm_stat`, `footprint`, and `vmmap` to identify memory pressure and pinpoint the leaking region.

```bash
# Step 1: Establish baseline
vm_stat > /tmp/vmstat_before.txt
cat /tmp/vmstat_before.txt

# Step 2: Open several Safari tabs with heavy web apps
# (Gmail, Google Docs, YouTube, GitHub) — 5-8 tabs

# Step 3: Take measurements after 2 minutes
vm_stat > /tmp/vmstat_after.txt
diff /tmp/vmstat_before.txt /tmp/vmstat_after.txt

# Step 4: Find the Safari WebContent processes
pgrep -la "com.apple.WebKit" 2>/dev/null || pgrep -la "Safari"

# Step 5: Get footprint of main Safari process
SAFARI_PID=$(pgrep -xo "Safari")
footprint -pid $SAFARI_PID 2>/dev/null || echo "Install Xcode Command Line Tools first"

# Step 6: Check for anonymous dirty regions (often the heap / JIT memory)
vmmap $SAFARI_PID 2>/dev/null | awk '
  /MALLOC|VM_ALLOCATE/ {
    gsub(/K/, "", $3); total += $3
  }
  END { printf "Estimated dirty heap: %.1f MB\n", total/1024 }
'
```

**What to look for**: The `vmmap` output will show large `MALLOC_LARGE` and `VM_ALLOCATE` regions, each tagged with a framework or `[heap]`. The cumulative dirty size across `WebContent` processes is where Safari's tab memory lives.

---

### Lab 3: Identify a background indexer eating CPU and decide what to do

**Goal**: Catch `mds_stores`, `photoanalysisd`, or similar in the act, understand why it is running, and make a principled decision about whether to wait or intervene.

```bash
# Step 1: Find the top CPU consumers right now
top -l 1 -o cpu -n 10 -stats pid,command,cpu | tail -12

# Step 2: If mds_stores appears, check Spotlight index status
mdutil -s /
# "Indexing enabled." with no further message = not actively indexing
# "Indexing and searching enabled." can indicate active indexing

# Step 3: Watch mds_stores disk activity for 15 seconds
sudo fs_usage -f filesys -p $(pgrep mds_stores 2>/dev/null || echo 99999) 2>/dev/null | \
  head -50 || echo "mds_stores not active"

# Step 4: Check photoanalysisd
if pgrep photoanalysisd > /dev/null; then
  echo "photoanalysisd is running at:"
  ps -p $(pgrep photoanalysisd) -o %cpu,rss,etime,command
  echo ""
  echo "Photos library modification time:"
  stat -f "%Sm  %N" ~/Pictures/*.photoslibrary 2>/dev/null
fi

# Step 5: Check cloudd / bird
for daemon in cloudd bird nsurlsessiond; do
  if pgrep -x $daemon > /dev/null; then
    echo -n "$daemon: "; ps -p $(pgrep -x $daemon) -o %cpu=,rss= | awk '{printf "CPU %.1f%%  RAM %.0f MB\n", $1, $2/1024}'
  fi
done
```

**Decision framework**:

| Finding | Decision |
|---|---|
| `mds_stores` high CPU, within 2 hours of an OS update | Wait; plug in power |
| `mds_stores` high CPU, 6+ hours after update, looping | `sudo mdutil -E /` to force-rebuild |
| `photoanalysisd` high CPU, recently imported 1000+ photos | Wait; it finishes in 30-120 min |
| `photoanalysisd` high CPU for 2+ days, Photos library unchanged | Check for corrupt asset; try restarting Photos |
| `cloudd`/`bird` sustained, stable library | Disconnect iCloud Drive toggle, wait 30s, reconnect |
| Unknown daemon consuming >50% for >1 hour | `ps -p <pid> -o pid,ppid,command` → audit the binary |

---

## Pitfalls & gotchas

**Mistaking low free memory for a problem.** macOS intentionally uses all available RAM as a cache. `vm_stat` showing 50 MB free is not alarming if the pressure graph is green and pageouts are near zero. The correct metric is the pressure color, not the free number. Falling for this leads to buying "RAM cleaner" apps that forcibly evict the cache, making the system *slower*.

**Trusting graceful-quit signals when benchmarking.** If you `pkill -TERM` a process to stop a load test and immediately measure, the process may still be running. Always verify with `pgrep` before taking an "after" measurement.

**Misreading kernel_task CPU as a leak.** `kernel_task` at 200–400% CPU is macOS's thermal governor doing its job. It is not consuming those cycles productively — it is blocking them from user processes to reduce die temperature. The root cause is always thermal; the fix is airflow, ambient temperature, or reducing the sustained workload.

**`pmset -g thermlog` returning nothing on Apple Silicon.** This is not a bug. Apple Silicon uses a continuous thermal-pressure model exposed through `notifyd` and `powermetrics`, not the discrete warning-level events that `thermlog` captures. Use `powermetrics --samplers smc` instead.

**`sample` requiring SIP partial exemption for some system processes.** You can sample most user processes without elevated privileges. For system processes owned by root, you need `sudo sample`. For some security-sensitive daemons, sampling is blocked entirely even with `sudo` on a fully SIP-enabled system. This is expected behavior, not a tool failure.

**Spotlight rebuilding silently after Time Machine restores.** Restoring from Time Machine invalidates the Spotlight index on the restored volume. The rebuild is automatic and can take hours on a large volume. `mdutil -s /` will show "Indexing enabled." while it runs.

**Electron app memory double-counting.** If you sort Activity Monitor by memory and add up all the `Electron Helper (Renderer)` processes for one app, you will get a number higher than the main process entry shows. This is correct — the main entry shows the *main process only*; the helpers are separate entries. The true RSS of an Electron app is the sum of all its helper processes plus the main process.

---

## Key takeaways

- **Match tool to bottleneck**: beachball → `spindump`; CPU → `powermetrics`; memory → `vm_stat` + `footprint`; disk → `fs_usage` + `iostat`; thermal → `powermetrics --samplers smc`.
- **Memory pressure color, not free RAM**, is the meaningful metric. Green = healthy regardless of how little free memory shows.
- **`kernel_task` high CPU = thermal event**, not a process bug. Look upstream at what is generating the heat.
- **Background indexers (`mds_stores`, `photoanalysisd`) are usually self-resolving**. Correct diagnosis prevents unnecessary intervention that makes things worse.
- **Spindumps are auto-generated** and persist in `/Library/Logs/DiagnosticReports/` — invaluable for post-hoc analysis of hangs you were not watching.
- **A clean test account** partitions the problem into "user environment" vs. "system" in one reboot cycle.
- **`powermetrics` is the single most informative tool** on Apple Silicon — it surfaces CPU frequency, power, thermal data, and per-cluster utilization that no other CLI tool exposes.
- **Login slowness** usually traces to login items, the "Reopen windows" restore queue, or a slow user `LaunchAgent`. Use `launchctl list` to audit.

---

## Terms introduced

| Term | Definition |
|---|---|
| **SPWC / beachball** | Spinning wait cursor; indicates main thread is not processing events |
| **`sample`** | BSD tool that captures call-stack samples of a running process |
| **`spindump`** | System-level hang-capture tool; produces `.spindump` files with all-thread stack traces |
| **Memory pressure** | Kernel metric combining free pages, compression rate, and swap activity; the real health indicator |
| **Wired memory** | RAM the kernel has locked; cannot be compressed or paged out |
| **Compressor** | In-kernel WKdm-based compression of inactive pages; reduces swap |
| **Pageout** | Writing a memory page to the swap file (`/private/var/vm/swapfile*`) |
| **`powermetrics`** | Apple tool reading PMU/SMC; exposes per-core frequency, power draw, die temperature |
| **SMC** | System Management Controller; manages fans, thermal sensors, power states |
| **thermald** | Daemon that reads SMC temperature and publishes thermal pressure levels to `notifyd` |
| **`mds` / `mds_stores`** | Spotlight metadata server / per-volume index writer |
| **`photoanalysisd`** | Background ML daemon for Photos face/scene/object recognition |
| **`fs_usage`** | VFS-layer filesystem call tracer; shows per-call file paths and latency |
| **`footprint`** | Developer tool reporting per-process memory breakdown (dirty, swapped, resident) |
| **`vmmap`** | Lists all VM regions of a process with size, type, and source library |
| **`leaks`** | Finds malloc-allocated blocks with no live references (classic leak detection) |
| **`xctrace`** | CLI front-end for Instruments; records profiling traces headlessly |
| **Login Items** | User-level programs that launch at login, managed via `SMAppService` / System Settings |
| **SMAppService** | Modern Swift API (macOS 13+) for registering login items and launch agents |
| **Thermal throttle** | CPU/GPU frequency reduction triggered when die temperature exceeds safe threshold |

---

## Further reading

- **`man powermetrics`** — the flags are not well-documented elsewhere; the man page is comprehensive
- **`man spindump`** — describes `.spindump` format and `spindump(8)` options
- **`man fs_usage`** — VFS event type codes (RdData, WrData, open, close, etc.)
- **Apple Platform Security guide** (available at `security.apple.com/documentation`) — the thermal and memory management sections describe the kernel-level mechanisms
- **Eclectic Light Company** (`eclecticlight.co`) — Howard Oakley's deep-dives on macOS diagnostics, particularly the Unified Log + performance intersection; search "performance" and "spindump" on the site
- **Thomas Kaiser's Apple Silicon knowledge base** (`github.com/ThomasKaiser/Knowledge`) — the most rigorous independent analysis of M-series thermal behavior, power states, and `powermetrics` interpretation
- **Instruments documentation** (`developer.apple.com/documentation/instruments`) — template reference and `xctrace` CLI guide
- [[07-memory-virtual-memory-and-swap]] — the kernel-level virtual memory architecture underlying everything in this lesson
- [[06-processes-mach-and-xpc]] — Mach task/thread model; explains what `sample` is actually reading
- [[05-launchd-and-the-launch-system]] — login items, launch agents, daemon taxonomy
- [[10-unified-logging-and-diagnostics]] — correlating performance events with the Unified Log for full-picture diagnosis
- [[09-spotlight-metadata-and-xattrs]] — Spotlight internals; explains why `mds` re-indexes and how to control it
