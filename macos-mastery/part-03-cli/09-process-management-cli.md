---
title: Process & resource management from the CLI
part: P03 CLI
est_time: 60 min read + 45 min labs
prerequisites: [00-terminal-and-shells]
tags: [macos, processes, performance, forensics, launchd, signals, memory, power]
---

# Process & resource management from the CLI

> **In one sentence:** macOS exposes a layered stack of process-interrogation tools — from POSIX-portable `ps`/`kill` through Darwin-specific `fs_usage`, `sample`, `footprint`, and `powermetrics` — that together give you full forensic and operational visibility into every running process on the system.

## Why this matters

Windows gives you Task Manager and `Get-Process`. macOS gives you a decade's worth of tools inherited from BSD, augmented by DTrace-era additions, and now Apple Silicon-aware QoS machinery. A forensics professional or power builder who knows only Activity Monitor is leaving 80% of the toolbox on the floor: you can't script Activity Monitor, you can't pipe its output into `awk`, and you can't run it over SSH into a headless server. Everything in this lesson is usable in a terminal, scriptable, and produces structured (or at least greppable) output.

> 🪟 **Windows contrast:** Windows process management splits across `tasklist`, `Get-Process` (PowerShell), `taskmgr.exe`, Process Hacker/System Informer, and Sysinternals Process Monitor. macOS consolidates equivalent functionality into first-party CLI tools — `ps`, `top`, `lsof`, `fs_usage`, `sample`, `spindump`, `footprint`, `vmmap` — all shipping with the OS, no download required. The Sysinternals-equivalent depth is built in.

---

## Concepts

### The macOS process model

Every process on macOS is a Mach task (the kernel's unit of resource ownership) that wraps one or more POSIX threads. The kernel's Mach layer manages virtual address spaces, ports, and scheduling; the BSD layer bolts on the Unix process hierarchy (PID, PPID, UID, signals). User-space processes are descended from `launchd` (PID 1) either directly (daemons, agents) or via `loginwindow` → your shell.

```
kernel (XNU = Mach + BSD)
└── launchd (PID 1)
    ├── system daemons  (com.apple.*)
    ├── loginwindow
    │   └── user launchd (per-session)
    │       ├── Launch Agents
    │       └── your Terminal.app → zsh → child procs
    └── XPC services (on-demand, per-bundle)
```

This matters forensically: every process has a *birth certificate* in launchd's plist database. A process that isn't there — or whose parent is `launchd` but isn't in any plist — warrants scrutiny. See [[01-boot-process]] and [[launchd-agents-daemons]] for the full service hierarchy.

### ps: BSD vs SysV syntax

macOS ships BSD `ps`, not GNU `ps`. The two syntax flavors are NOT interchangeable — BSD flags have no leading dash, SysV flags do. Mixing them silently misbehaves.

**BSD-style (preferred on macOS):**
```bash
ps aux                   # all users, user-oriented format, BSD columns
ps axo pid,ppid,user,%cpu,%mem,vsz,rss,stat,comm
ps axo pid,ppid,user,lstart,comm   # lstart = human-readable start time
```

**SysV-style (POSIX-compatible, also works):**
```bash
ps -ef                   # every process, full format
ps -eo pid,ppid,uid,%cpu,args
```

**Key columns decoded:**

| Column | Meaning |
|--------|---------|
| `STAT` | Process state: `R`=running, `S`=sleeping, `T`=stopped, `Z`=zombie, `+`=foreground, `s`=session leader |
| `VSZ` | Virtual size (KB) — address space including unmapped regions |
| `RSS` | Resident Set Size (KB) — physical RAM currently paged in |
| `%MEM` | RSS as % of physical RAM |
| `NI` | Nice value (priority adjustment) |
| `WCHAN` | Kernel wait channel — what syscall/lock the process is blocked on |

**Custom output columns with `-O`** (append to default):
```bash
ps axO stat,nice,wchan   # default columns PLUS these three
```

**Sort by CPU, grab top 15:**
```bash
ps aux --sort=-%cpu | head -16
# BSD ps on macOS doesn't have --sort; use:
ps aux | sort -k3 -rn | head -16
```

> 🔬 **Forensics note:** `lstart` (long start time) is your friend when building a timeline. Compare against filesystem `mtime`s in `~/Library/Application Support/` or unified log timestamps (`log show --last 1h`). A process that started 30 seconds after an anomalous network event is worth pulling on.

### top: interactive process monitor

macOS `top` diverges significantly from Linux `top` — different flags, different defaults.

```bash
top                       # default: sort by CPU descending
top -o cpu                # explicit: sort by CPU
top -o mem                # sort by memory (RSIZE)
top -o vsize              # sort by virtual size
top -o pid                # sort by PID ascending
top -n 20                 # show only top 20 processes
top -s 2                  # refresh every 2 seconds (default 1)
top -l 5                  # log mode: 5 snapshots then exit (scriptable)
top -l 1 -n 0             # single snapshot, header stats only (fast scripting)
top -stats pid,command,cpu,rsize,vsize,threads,state  # custom column set
```

`top -l 1` is the key for scripting — it runs non-interactively and exits:
```bash
# Grab CPU load averages in a script:
top -l 1 -n 0 | grep "Load Avg"
```

**Interactive keypresses in `top`:**
- `o` — change sort order (type a column name)
- `?` — help
- `q` — quit
- `s` followed by a number — change sample interval

### htop / btop / bottom: when you want color and mouse

The BSD `top` is functional but spartan. Three brew-installable alternatives are universally recommended:

```bash
brew install htop    # Linux-familiar; tree view (F5); per-core bars; mouse support
brew install btop    # btop++ — stunning TUI; GPU panel (M-series); network+disk panels
brew install bottom  # Rust-based `btm`; responsive; configurable; good for scripting
```

`btop` is the current community favorite for Apple Silicon: it surfaces E-core vs P-core distribution and power draw in a single panel that `top` doesn't approach.

> 🪟 **Windows contrast:** This maps to Process Hacker / System Informer on Windows. `btop` gets you closer to System Informer's visual density than any macOS default tool.

### Activity Monitor ↔ CLI mapping

| Activity Monitor column | CLI equivalent |
|------------------------|----------------|
| % CPU | `top -o cpu`, `ps aux` `%CPU` |
| Memory (real) | `footprint <pid>`, `ps` `RSS` |
| Memory (virtual) | `vmmap <pid>`, `ps` `VSZ` |
| Energy Impact | `powermetrics --samplers cpu_power` |
| Disk reads/writes | `iostat -d 1`, `fs_usage -f filesys` |
| Network sent/received | `nettop`, `netstat -ib` |
| Open files | `lsof -p <pid>` |
| Parent process | `ps -o ppid= -p <pid>` |

---

## Signals: `kill`, `killall`, `pkill`

### Signal basics

`kill` sends signals to processes — the name is misleading; most signals are communications, not termination orders.

```bash
kill -l                   # list all signals with numbers
kill -TERM <pid>          # SIGTERM (15): polite shutdown, catchable
kill -KILL <pid>          # SIGKILL (9): unconditional termination, uncatchable
kill -HUP  <pid>          # SIGHUP (1): historically "hangup"; daemons use it to reload config
kill -STOP <pid>          # SIGSTOP (19): pause (like Ctrl-Z); cannot be caught
kill -CONT <pid>          # SIGCONT (18): resume a stopped process
kill -USR1 <pid>          # SIGUSR1 (30): app-defined; often triggers diagnostic dump
kill -INT  <pid>          # SIGINT (2): same as Ctrl-C
```

**Practical escalation sequence:**
```bash
kill -TERM <pid>          # 1. Ask nicely
sleep 5
kill -0 <pid> 2>/dev/null && kill -KILL <pid>  # 2. If still alive, force
```

`kill -0` is a no-op signal used purely to test if a PID exists and you have permission to signal it — essential in scripts.

### killall and pkill

```bash
killall Finder            # signal all processes named "Finder" (exact match)
killall -HUP mDNSResponder   # flush DNS cache (the documented way)
killall -9 "My App"       # spaces in name need quoting
pkill -f "python.*myscript"  # match against full argv, not just process name
pkill -u bronty13 caffeinate  # kill all caffeinate processes owned by that user
```

`pkill` uses regex; `killall` uses exact name match. For anything with a complex command line, `pkill -f` is more precise.

### pgrep: finding processes

```bash
pgrep Safari              # print PIDs of all Safari processes
pgrep -l Safari           # PID + name
pgrep -fl "python"        # full command line match
pgrep -u root             # all processes owned by root
pgrep -P 1                # all direct children of PID 1 (launchd children)
```

> ⚠️ **DESTRUCTIVE:** `pkill -9` cannot be undone. A SIGKILL-ed process drops all unsaved state with no opportunity for cleanup. Always try SIGTERM first. For launchd-managed processes, sending SIGKILL directly means launchd will immediately restart the process (if `KeepAlive` is set) — you'll be playing whack-a-mole. See "launchd-managed services" below.

---

## Priority: nice, renice, taskpolicy, and QoS

### The two priority systems on macOS

macOS has **two** overlapping priority systems that interact non-obviously on Apple Silicon:

1. **Unix nice values** (`-20` = highest priority, `+20` = lowest): legacy POSIX mechanism. On Apple Silicon, `renice` has little to no measurable effect on scheduling — the kernel honors QoS tier over nice value. Retained for POSIX compatibility.

2. **Darwin QoS tiers**: the actual scheduling mechanism. Four user-visible levels:

| QoS class | Integer | Core preference (M-series) | Use case |
|-----------|---------|---------------------------|----------|
| `user-interactive` | 33 | P-cores, highest priority | UI main thread, event handling |
| `user-initiated` | 25 | P-cores preferred | User-triggered operations |
| `utility` | 17 | P-cores or E-cores | Downloads, slow background work |
| `background` | 9 | E-cores only | Time-insensitive maintenance |

On M-series chips, a thread at QoS `background` is **pinned to Efficiency cores** regardless of nice value. This is the mechanism behind App Nap.

### App Nap

App Nap is the automatic throttle macOS applies when an app is invisible (occluded behind other windows, minimized, or on a non-frontmost Space) and is not playing audio or holding a `NSProcessInfo` power assertion. The system drops the app's threads to background QoS + adds timer coalescing. Result: the app's CPU cycles drain from P-cores, wake intervals stretch, and it consumes a fraction of its foreground power.

You can observe App Nap state via:
```bash
# Check if process is App Napped (NSAppSleep assertion absent = napped)
powermetrics --samplers tasks -n 1 2>/dev/null | grep -A2 "<AppName>"
```

### taskpolicy: the right lever on Apple Silicon

```bash
# Run a new process at background (E-cores only, lowest priority):
taskpolicy -b caffeinate -t 3600

# Demote an already-running process to background QoS:
taskpolicy -b -p <pid>

# Un-demote (restore ability to use P-cores; cannot promote above original):
taskpolicy -B -p <pid>

# Run at utility tier:
taskpolicy -c utility ffmpeg -i input.mp4 output.mp4

# Pin to E-cores AND set background I/O:
taskpolicy -b -B -p <pid>
```

> 🔬 **Forensics note:** `taskpolicy -b` is a lever for safely backgrounding a CPU hog on a live system during an investigation without killing it and losing its in-memory state. You keep the process alive and observable while preventing it from impacting collection tools running at normal priority.

### nice/renice (legacy — limited effect on Apple Silicon)

```bash
nice -n 10 make -j8       # start make with +10 niceness
renice +15 -p <pid>       # lower priority of running process (no sudo needed for own procs)
sudo renice -10 -p <pid>  # raise priority requires root (negative values)
```

On Apple Silicon, treat `renice` as a signal to the scheduler that has cosmetic effect at best. Prefer `taskpolicy` for real control.

---

## Resource inspection: memory, files, I/O

### vm_stat: system-wide virtual memory

```bash
vm_stat                   # single snapshot
vm_stat 2                 # refresh every 2 seconds
```

Key lines to read:
- `Pages free` — immediately usable physical pages (4 KB each on arm64)
- `Pages wired down` — kernel-pinned; cannot be paged out
- `Pages occupied by compressor` — pages compressed by the VM compressor (macOS's alternative to swap files that actually writes to disk)
- `Pageins / Pageouts` — cumulative since boot; sustained pageouts mean real memory pressure

```bash
# Convert page counts to MB (page size = 16384 bytes on Apple Silicon):
vm_stat | awk '/free/ {printf "Free: %.1f GB\n", $3 * 16384 / 1024 / 1024 / 1024}'
```

> 🔬 **Forensics note:** On Apple Silicon, macOS uses a **compressed memory** scheme (not a traditional swap file path in the same way). Look at `swapusage` in `top` output and `sysctl vm.swapusage` for the compressor's contribution. Memory artifacts for forensic acquisition on Apple Silicon are significantly harder to capture than on Intel — Volatility 3 does not officially support arm64 macOS as of 2026; commercial tools like Volexity Surge Collect are the current option.

### footprint: physical memory accounting per process

`footprint` is the most accurate single-process memory reporter on macOS — it accounts for shared libraries proportionally, distinguishes dirty from clean pages, and shows the compressor contribution.

```bash
sudo footprint <pid>
sudo footprint -j <pid>   # JSON output (machine-parseable)
sudo footprint Safari     # by name
```

Output includes:
- `Physical footprint` — dirty + compressed pages (what Activity Monitor shows as "Memory")
- `Real private pages` — pages only this process owns
- `Shared clean` — read-only shared memory (dyld cache, mapped frameworks)

### vmmap: process virtual address space

```bash
sudo vmmap <pid>
sudo vmmap -summary <pid>       # region summary (most useful starting point)
sudo vmmap -interleaved <pid>   # address-ordered interleaved dump
```

`vmmap -summary` shows you every mapped region type (STACK, MALLOC_LARGE, mapped files, the dyld shared cache, frameworks) with sizes. Useful for spotting anomalously large anonymous mappings (potential injected code or heap spray).

> 🔬 **Forensics note:** `vmmap` output revealing `mapped file /private/var/tmp/...` or anonymous regions at unexpected sizes is a classic indicator of code injection or unusual memory tricks. The dyld shared cache (`__DATA_DIRTY` in `/private/var/db/dyld/`) normally dominates; anything else large and anonymous is worth noting.

### heap and leaks

```bash
sudo heap <pid>           # summarize heap allocations by class
sudo heap -sumObjectCount <pid>
sudo leaks <pid>          # detect leaked heap blocks (developer tool)
```

### lsof: open files, sockets, and ports

`lsof` (list open files) is foundational — on macOS, every socket, pipe, device node, and directory is a "file".

```bash
lsof -p <pid>             # all file descriptors for one process
lsof -u bronty13          # all open files by a user
lsof -i                   # all network connections/sockets
lsof -i TCP:443           # processes using TCP port 443
lsof -i :8080             # any protocol on port 8080
lsof -i TCP -s TCP:LISTEN # listening TCP sockets only
lsof +D /tmp              # all processes with files open under /tmp
lsof /path/to/file        # which process has this file open
lsof -nP -i TCP           # -n=no hostname resolution, -P=no port name resolution (faster)
```

**Find what's holding a file open (e.g., prevents unmounting a volume):**
```bash
lsof +D /Volumes/MyDrive
```

> 🔬 **Forensics note:** On a live system, `lsof -i` is your first-pass network inventory. Pair with `netstat -anp tcp | grep ESTABLISHED` for a dual-tool cross-check. A process with a TCP ESTABLISHED connection to an unexpected external IP that doesn't appear in `ps aux` output should be flagged immediately (though note: `lsof -i` can briefly miss sockets during rapid cycling).

### iostat: disk I/O

```bash
iostat                    # current I/O stats for all disks
iostat -d disk0 2         # disk0 only, refresh every 2 seconds
iostat -c 5 2             # 5 samples at 2-second intervals
```

Columns: `KB/t` (KB per transfer), `tps` (transfers/sec), `MB/s` read/write.

---

## Process tracing and diagnostics

### fs_usage: file-system activity tracer

`fs_usage` hooks into the kernel via DTrace and reports every filesystem-related syscall in real time. It is the closest macOS equivalent to Sysinternals Process Monitor's file tab.

```bash
sudo fs_usage             # all processes, all fs calls
sudo fs_usage -p <pid>    # one process only
sudo fs_usage -f filesys  # filter: filesystem calls only (no network, no page faults)
sudo fs_usage -f network  # network calls only
sudo fs_usage -f pgin     # page-in events only
sudo fs_usage Safari 2>&1 | grep -v dyld   # filter out dyld noise
```

Output format: `HH:MM:SS.usec  SYSCALL   path   elapsed_time   process`

Common syscalls you'll see:
- `open`, `read`, `write`, `close` — obvious
- `stat64`, `getattrlist` — metadata reads (file existence checks)
- `unlink`, `rename` — deletions and moves
- `flock`, `fcntl` — file locking
- `mmap` — memory-mapped file access

> ⚠️ **ADVANCED:** `fs_usage` can produce enormous output volumes — pipe it to a file immediately and use `grep` or `less` to navigate. On a busy system, it can generate 10,000+ lines per second. Use `-p <pid>` to scope it.

### sample: CPU profiling a running process

`sample` attaches to a process and collects a call-stack sample at 1ms intervals for a specified duration, then produces a human-readable call tree. No recompilation or debug symbols required (though symbols improve readability).

```bash
sample <pid> 10           # sample for 10 seconds
sample Safari 30 -file /tmp/safari-sample.txt   # 30 seconds, save to file
sample -wait MyApp        # wait for the process to start, then sample
```

Output is a flame-tree showing which call stacks consumed the most CPU. Look for deep, narrow chains (CPU-bound hot paths) vs wide, shallow stacks (I/O waiting).

> 🔬 **Forensics note:** `sample` output captures the full symbol chain at each sample point, including framework calls. It can reveal obfuscated activity: a suspicious process showing `libsystem_c.dylib: write` → `Foundation: NSFileHandle` → `AppKit: [NSDocument autosave]` is doing something legible in its call tree even if the binary is stripped of main-module symbols.

### spindump: system-wide or targeted hang analysis

`spindump` is to `sample` what a system-wide core dump is to a single-thread snapshot. It captures call stacks for all (or targeted) processes, with a focus on detecting hangs.

```bash
sudo spindump              # all processes, writes to /tmp/spindump_*.txt
sudo spindump <pid> <duration_sec> <interval_ms>
sudo spindump Safari 10 100    # Safari, 10s, 100ms interval
sudo spindump -noProcessingWhileSampling   # reduce overhead
```

macOS also auto-creates spindumps in `~/Library/Logs/DiagnosticReports/` when the spinning beachball persists — check there before running a fresh one.

### xctrace: the Instruments CLI

Instruments traces via `xctrace` let you record DTrace-powered performance templates non-interactively, then open results in Instruments.app.

```bash
xcrun xctrace list templates       # show available templates
xcrun xctrace record --template "Time Profiler" --duration 10 --output trace.xcresult --target-stdin
xcrun xctrace record --template "Allocations" --duration 15 --output alloc.xcresult --attach <pid>
xcrun xctrace record --template "System Trace" --duration 5 --output sys.xcresult
```

Open the resulting `.xcresult` in Instruments.app for the full visual timeline. `System Trace` is the most forensically rich: it shows every thread's core affiliation, P/E core transitions, QoS promotions, and wake reasons.

---

## Power impact: powermetrics

```bash
sudo powermetrics --samplers cpu_power -n 1 -i 1000
sudo powermetrics --samplers cpu_power,gpu_power,thermal -n 5 -i 2000
sudo powermetrics --samplers tasks -n 1 -i 1000 | head -60   # per-process power
```

`--samplers tasks` gives you per-process CPU + GPU energy in milliwatts — the same data feeding Activity Monitor's Energy tab, but scriptable. Requires root; writes to stdout by default.

On M-series chips, `powermetrics` also reports P-core vs E-core utilization percentages, active residency per cluster, and thermal headroom — none of which `top` exposes.

---

## Code signatures per-process

A running process's binary should be signed. Verify it:

```bash
codesign -dvvv $(which python3)      # verify + verbose details for a CLI tool
codesign -dvvv /Applications/Safari.app   # app bundle
codesign -dv --entitlements - /Applications/Terminal.app  # dump entitlements
spctl -a -vv /Applications/Safari.app    # Gatekeeper assessment (notarized?)
```

For a running process, find its binary path first:
```bash
ps -p <pid> -o comm=          # executable path
codesign -dvvv $(ps -p <pid> -o comm=)
```

> 🔬 **Forensics note:** An unsigned binary running as a user process is immediately suspicious post-macOS 10.15. A process with `ad-hoc` signing (`-` as the authority) is unsigned for distribution purposes — legitimate for developer builds, anomalous for anything else on a non-developer machine. A process presenting an Apple Developer ID that doesn't match the expected signer for that app is a definite red flag. Cross-reference against the Transparency, Consent & Control (TCC) database and the unified log.

---

## launchd-managed services vs raw processes

This is the single most common mistake: killing a launchd-managed daemon with `kill -9` without disabling it first. If the service has `KeepAlive` set, launchd restarts it within seconds.

**The right way to stop a launchd-managed service:**
```bash
# Find the service label:
launchctl list | grep <name>

# Stop AND prevent restart (macOS 10.10+ "bootout" model):
sudo launchctl bootout system/com.apple.service.name   # system daemon
launchctl bootout gui/$(id -u)/com.mycompany.agent    # user agent

# Temporary disable (persists across reboots, until re-bootstrapped):
sudo launchctl disable system/com.apple.service.name

# Re-enable and start:
sudo launchctl enable system/com.apple.service.name
sudo launchctl bootstrap system /Library/LaunchDaemons/com.apple.service.name.plist
```

**Reload config after plist edit** (e.g., you changed an interval):
```bash
launchctl kill HUP system/com.example.service  # sends SIGHUP to the service
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `launchctl bootout system/...` on a core macOS daemon (mDNSResponder, configd, securityd) can destabilize the system and require a reboot. Know what you're stopping before you stop it. If in doubt, `launchctl list | grep <label>` to confirm the exact label, then check `man launchctl` for the service's documented behavior.

> 🔬 **Forensics note:** `launchctl list` output is your inventory of every bootstrapped service in the current session. A service label not matching any plist in `/Library/LaunchDaemons/`, `/Library/LaunchAgents/`, or `~/Library/LaunchAgents/` — but appearing in `launchctl list` — is a persistence mechanism worth investigating. See [[launchd-agents-daemons]] for the complete plist location hierarchy and artifact paths.

---

## Hands-on (CLI & GUI)

### Find the top CPU consumer and profile it

```bash
# 1. Identify:
ps aux | sort -k3 -rn | head -5

# 2. Get its PID:
PID=$(pgrep -n Safari)

# 3. Sample it for 10 seconds:
sample $PID 10 -file /tmp/safari-$(date +%s).txt
open /tmp/safari-*.txt
```

### Trace all file access by a process

```bash
# Watch what files a process reads/writes in real time:
sudo fs_usage -p $(pgrep Terminal) -f filesys 2>&1 | tee /tmp/fs_trace.txt
```

### Port/connection inventory for a process

```bash
PID=$(pgrep -n "mDNSResponder")
lsof -nP -p $PID -i
```

### Full memory accounting

```bash
sudo footprint -j $(pgrep Safari) | python3 -m json.tool | head -40
```

### Check if a process is napping

```bash
sudo powermetrics --samplers tasks -n 1 -i 500 2>/dev/null \
  | grep -A5 "Safari"
```

---

## Labs

### Lab 1: Trace a process's file access with fs_usage

**Setup:** Open TextEdit and create a new document.

**Goal:** Capture every filesystem call TextEdit makes when you save a file.

```bash
# Terminal 1: start the trace BEFORE saving
sudo fs_usage -p $(pgrep TextEdit) -f filesys 2>&1 | tee /tmp/textedit_trace.txt

# Terminal 2 (or just use TextEdit): Save a file (Cmd-S) with any content
# Then Ctrl-C in Terminal 1 to stop the trace

# Analyze:
grep -E "open|write|rename|unlink" /tmp/textedit_trace.txt | head -30
```

**Expected findings:** You'll see TextEdit writing to a `.TextEdit.rtf.lock` file, writing the actual content, then an atomic rename from a temp path to the final path. This is the safe-save pattern macOS apps use — write to temp, then `rename()` which is atomic.

> 🔬 **Forensics note:** Atomic rename means a forensic analyst examining a file's `mtime` sees the *rename* timestamp, not when bytes were first written. The temp file path (usually in the same directory, prefixed with `.`) appears briefly in `fs_usage` and leaves no permanent artifact — but the rename event is logged in the Unified Log.

---

### Lab 2: Find a CPU hog and sample it

> ⚠️ **Controlled stress test — safe but uses 100% of one CPU core temporarily.**
> Rollback: the loop is a child of your shell; `Ctrl-C` in the shell or `kill <pid>` terminates it instantly.

```bash
# 1. Create an artificial CPU hog:
python3 -c "while True: pass" &
HOG_PID=$!
echo "Hog PID: $HOG_PID"

# 2. Verify it shows up:
ps -p $HOG_PID -o pid,%cpu,command

# 3. Check QoS (it starts at default user-initiated):
taskpolicy -p $HOG_PID   # or: ps -O stat -p $HOG_PID

# 4. Sample it:
sample $HOG_PID 5 -file /tmp/hog_sample.txt
cat /tmp/hog_sample.txt

# 5. Demote it to background (E-cores only) and verify CPU impact:
taskpolicy -b -p $HOG_PID
# Watch in top — its %CPU should drop as P-cores are released:
top -l 3 -n 5 -o cpu | grep -E "python|PID"

# 6. Restore and kill cleanly:
taskpolicy -B -p $HOG_PID
kill $HOG_PID
```

**Expected sample output:** A call tree showing `libsystem_c.dylib: _spin_lock` or the Python eval loop at 100% of the samples. After `taskpolicy -b`, you should see CPU drop from ~100% to something lower as the kernel migrates the process to E-cores competing with other background work.

---

### Lab 3: Verify a process's code signature

```bash
# 1. Pick a running process you care about:
PID=$(pgrep -n Safari)
BINARY=$(ps -p $PID -o comm= | head -1)
echo "Binary: $BINARY"

# 2. Full signature info:
codesign -dvvv "$BINARY" 2>&1

# 3. Check entitlements:
codesign -d --entitlements - "$BINARY" 2>&1

# 4. Gatekeeper assessment:
spctl -a -vv "$BINARY"

# 5. Try something suspicious: check a shell script (should be unsigned):
codesign -dv /usr/local/bin/brew 2>&1 || echo "No signature (expected for scripts)"
```

**Expected output for Safari:** `Authority=Apple Root CA`, `TeamIdentifier=APPLED…`, `iCloud` and `com.apple.security.network.client` entitlements visible. **Expected for Homebrew `brew`:** `code object is not signed at all` — shell scripts cannot be signed in the traditional sense (they're interpreted text), and that's normal.

---

### Lab 4: Audit network connections of a suspicious process

```bash
# Replace 'mDNSResponder' with any process you want to audit:
TARGET="mDNSResponder"
PID=$(pgrep -n $TARGET)

echo "=== Open network connections for $TARGET (PID $PID) ==="
lsof -nP -p $PID -i

echo ""
echo "=== All open files ==="
lsof -p $PID | head -30

echo ""
echo "=== Code signature ==="
codesign -dvvv $(ps -p $PID -o comm=) 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"
```

---

## Pitfalls & gotchas

- **BSD `ps` flags have no dash; SysV flags do.** `ps aux` is BSD; `ps -ef` is SysV. `ps -aux` (with dash) prints a deprecation warning and may misparse column headers.

- **`kill` takes a PID, not a name.** `kill Safari` will fail (unless Safari's PID happens to be what you'd expect from the shell expansion). Use `pkill Safari` or `kill $(pgrep Safari)`.

- **Killing a KeepAlive launchd job loops forever.** `kill -9` a job, launchd starts it. Again. Forever. Always `launchctl bootout` first.

- **`nice` and `renice` are effectively no-ops on Apple Silicon for real scheduling.** The QoS class is what drives core assignment and scheduling weight. Use `taskpolicy`.

- **`fs_usage` requires SIP to be set appropriately.** On a stock macOS system, `sudo fs_usage` works for monitoring user-space processes. Monitoring some system processes may require disabling SIP — which you should not do on a production machine.

- **`lsof` output can be stale by the time you read it.** Sockets open and close in microseconds. Use `-r <interval>` for continuous monitoring: `lsof -nP -i -r 2` repeats every 2 seconds.

- **`sample` and `spindump` suspend the process briefly** to capture stacks. On a latency-sensitive production service, this can cause visible pauses. On an investigation machine, usually fine.

- **Activity Monitor's "Memory" column is `footprint`'s "Physical footprint"** — not RSS. RSS undercounts shared libraries; `footprint` accounts for them proportionally. For large processes like browsers, the difference can be 500MB+.

- **`codesign -dvvv` on an app bundle needs the path to the `.app`, not `Contents/MacOS/Binary`.** Signing is applied to the bundle directory, not just the binary; checking the raw Mach-O may miss bundle-level signing attributes.

---

## Key takeaways

1. BSD `ps aux` and SysV `ps -ef` both work on macOS but don't mix their flag syntaxes.
2. `top -l 1` is the scriptable form of `top`; `btop` via Homebrew is the best interactive monitor for Apple Silicon.
3. On Apple Silicon, QoS tier — not `nice` value — determines whether threads run on P-cores or E-cores. `taskpolicy` is the right tool; `renice` is a compatibility no-op.
4. App Nap is the automatic QoS demotion system for backgrounded apps — Energy core pinning, timer coalescing.
5. `fs_usage -p <pid> -f filesys` is your Process Monitor equivalent — real-time filesystem syscall trace.
6. `sample <pid>` captures a call-stack profile without debug symbols or recompilation; `spindump` does the same system-wide.
7. `lsof -nP -p <pid> -i` gives you the per-process network connection inventory.
8. `footprint` and `vmmap -summary` give deeper memory accounting than `ps RSS` or Activity Monitor alone.
9. Never `kill -9` a launchd KeepAlive service; use `launchctl bootout` to stop it cleanly.
10. Always verify code signatures (`codesign -dvvv`, `spctl -a`) as part of any process investigation.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| **Mach task** | Kernel-level unit of resource ownership (virtual address space, ports); wraps POSIX process |
| **BSD `ps`** | Process status tool using BSD flag syntax (no leading dash) |
| **QoS (Quality of Service)** | Darwin scheduling class: background/utility/user-initiated/user-interactive; controls P vs E core assignment |
| **App Nap** | Automatic background throttle: drops occluded, audio-free apps to background QoS + timer coalescing |
| **taskpolicy** | macOS CLI to demote a process to a lower QoS tier or confine it to Efficiency cores |
| **P-core / E-core** | Performance vs Efficiency cores on Apple Silicon; QoS determines assignment |
| **nice value** | POSIX priority hint (-20 to +20); effectively cosmetic on Apple Silicon |
| **KeepAlive** | launchd plist key instructing launchd to restart a service whenever it exits |
| **bootout** | launchctl command to remove a service from the bootstrap context (prevents automatic restart) |
| **fs_usage** | DTrace-backed macOS tool for per-process filesystem syscall tracing in real time |
| **sample** | macOS call-stack profiler: attaches to a running PID, samples at 1ms intervals |
| **spindump** | System-wide hang/backtrace collector; auto-runs on spinning beachball |
| **footprint** | Accurate per-process physical memory accounting (proportional share of shared pages) |
| **vmmap** | Dumps the virtual address space layout of a process |
| **xctrace** | CLI front-end to Instruments; records DTrace-powered performance traces non-interactively |
| **powermetrics** | Apple tool for per-process and per-cluster power/energy reporting; requires root |
| **lsof** | List open files: enumerates file descriptors including sockets, pipes, devices |
| **SIGTERM / SIGKILL** | Termination signals: TERM is catchable (graceful), KILL is unconditional |
| **Physical footprint** | Activity Monitor's "Memory" column: dirty + compressed pages, proportional shared |
| **Atomic rename** | POSIX `rename()` syscall is atomic — used by safe-save; destination is replaced in one op |

---

## Further reading

- `man ps`, `man top`, `man kill`, `man lsof`, `man fs_usage`, `man sample`, `man spindump`, `man footprint`, `man vmmap`, `man taskpolicy`, `man powermetrics`, `man launchctl`
- Howard Oakley, "What is Quality of Service, and how does it matter?" — eclecticlight.co (2025-05-09): deep dive on QoS tiers and E-core pinning on Apple Silicon
- Howard Oakley, "Making the most of Apple silicon power: 5 User control" — eclecticlight.co: `taskpolicy` vs App Tamer
- Howard Oakley, "How you can't promote threads on an M1" — eclecticlight.co: the asymmetry of QoS demotion vs promotion
- Apple Platform Security Guide (APSP), "Secure software installation" — trust chain from notarization to `codesign`
- Apple Developer Documentation: "Viewing Virtual Memory Usage" (developer.apple.com/library/archive) — `vmmap` and `vm_stat` interpretation
- `xcrun xctrace help` and the Instruments documentation for `System Trace` template — the authoritative source for DTrace-backed profiling
- [[01-boot-process]] — XNU, launchd boot sequence, and how processes enter the system
- [[launchd-agents-daemons]] — full plist hierarchy, service labels, and persistence artifact locations
- [[file-system-deep-dive]] — APFS volumes, extended attributes, and the on-disk artifacts `fs_usage` surfaces
- [[networking-cli]] — `netstat`, `nettop`, and packet-level tools that complement `lsof -i`
