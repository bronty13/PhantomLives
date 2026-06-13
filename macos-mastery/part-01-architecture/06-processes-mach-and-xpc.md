---
title: Processes, Mach & XPC
part: P01 Architecture
est_time: 60 min read + 45 min labs
prerequisites: [00-darwin-and-xnu-kernel, 05-launchd-and-the-launch-system]
tags: [macos, processes, mach, xpc, ipc, gcd, forensics, debugging]
---

# Processes, Mach & XPC

> **In one sentence:** Every macOS process carries a dual Mach/BSD identity, communicates through kernel-managed capability objects called ports, and modern Apple software decomposes itself into sandboxed XPC helper processes that talk over those same ports — understanding this stack is the key to both power-user process inspection and forensic investigation.

---

## Why this matters

Windows developers and forensic analysts think of processes as rows in Task Manager: a PID, an EXE path, some CPU/RAM numbers. macOS forces you to hold a richer model. The "process" you see in Activity Monitor is actually a *Mach task* (virtual address space + port rights namespace) fused with a *BSD process* (PID, UID/GID, signals, file descriptors). These two planes are distinct kernel objects that share a lifetime but expose different syscall interfaces.

On top of that, most privileged operations in Apple's own software never happen inside the main app process at all — they happen in a fleet of sandboxed XPC helper processes that the kernel spins up and tears down on demand. Knowing this:

- Lets you correctly attribute CPU/memory cost to the right component.
- Lets you enumerate all processes a piece of malware has spawned or hijacked.
- Lets you validate the code signatures of every binary participating in an app's execution.
- Lets you debug a hung or leaking process without fumbling in the dark.

---

## Concepts

### The dual identity: Mach task + BSD process

XNU is a hybrid kernel. When a process is born, XNU creates two linked objects:

```
┌─────────────────────────────────────────────────────────┐
│  Mach task                                              │
│  ─────────                                              │
│  • Virtual address space (pmap)                         │
│  • IPC port rights namespace (ipc_space_t)              │
│  • mach_task_self() → send right to own task port       │
│  • TASK_BOOTSTRAP_PORT → send right to launchd          │
│  • Mach threads (each also a kernel object)             │
└───────────────────┬─────────────────────────────────────┘
                    │ 1-to-1 binding
┌───────────────────▼─────────────────────────────────────┐
│  BSD proc                                               │
│  ────────                                               │
│  • PID / PPID / PGID / SID                              │
│  • UID, GID, supplementary groups                       │
│  • Open file descriptors (fd table)                     │
│  • Signal disposition table                             │
│  • Argv, envp, working directory                        │
│  • Resource limits (getrlimit/setrlimit)                │
└─────────────────────────────────────────────────────────┘
```

System calls in the POSIX/BSD family (`fork`, `open`, `kill`, `getpid`) talk to the BSD plane. Mach traps (`mach_msg`, `task_for_pid`, `vm_allocate`) talk to the Mach plane. The C library and libSystem bridge between them.

> 🪟 **Windows contrast:** Windows has a single object model: a `HANDLE` is a `HANDLE`. macOS has two orthogonal namespaces — a Mach port name and a BSD file descriptor — that can refer to completely different kernel entities, and neither subsumes the other.

### Mach ports: capability-based IPC

A **Mach port** is a kernel-owned, bounded message queue. Processes do not hold pointers to ports; they hold **port rights** — unforgeable integer indices into their task's IPC table (the `ipc_space`). Three right types matter:

| Right | What it lets you do |
|---|---|
| **SEND** | Enqueue a message onto the port; copyable |
| **RECEIVE** | Dequeue messages; exactly one holder; non-transferable except by explicit grant |
| **SEND_ONCE** | Send exactly one message, then the right vaporizes; used for reply ports |

The IPC table maps a **port name** (a 32-bit integer) to an `ipc_entry` containing:
- `ie_object`: pointer to the kernel `ipc_port_t`
- `ie_bits`: right type flags + generation number (prevents use-after-free and name-guessing attacks)

When a process receives a Mach message containing a port right, the kernel intercepts the transfer and inserts a new entry into the receiver's IPC table — the right crosses the process boundary inside the kernel, never as a raw pointer that user space can forge or intercept.

**Key special ports** every task is born with:

| Port | Access | Significance |
|---|---|---|
| `mach_task_self()` | SEND to own task port | Allows another process with this right to inject threads/memory |
| `TASK_BOOTSTRAP_PORT` | SEND to launchd | The root of service discovery |
| Host port | SEND to host | System-wide info; elevated host-priv port for admin ops |

> 🔬 **Forensics note:** Possessing SEND rights to another process's task port is equivalent to owning that process. `task_for_pid(0)` returns the kernel task port — full kernel read/write. `taskgated` (a daemon running as root) gates access: only processes with the `com.apple.security.get-task-allow` entitlement, or that are running as root with SIP disabled, can call `task_for_pid` on arbitrary targets.

### The bootstrap server (launchd as port broker)

Every process inherits `TASK_BOOTSTRAP_PORT` from its parent. On macOS, this always resolves to **launchd** — the root process (PID 1) that is the ultimate ancestor of every user process.

launchd acts as a **name server** for Mach ports:

```
1. Service (e.g. com.apple.lsd) calls bootstrap_register("com.apple.lsd")
   → launchd stores the RECEIVE right under that name

2. Client calls bootstrap_look_up("com.apple.lsd")
   → launchd synthesizes a SEND right and returns it to the client

3. Client now has a SEND right; it can send Mach messages directly to the
   service without launchd further in the path
```

You can browse registered Mach services from the command line:

```bash
# List all Mach services registered with launchd in the current bootstrap context
launchctl print-disabled system/
launchctl print gui/$(id -u)

# The low-level bootstrap name-server lookup tool (still works, deprecated API)
/usr/libexec/PlistBuddy -c print /Library/Preferences/com.apple.LaunchDaemon.plist

# Better: use lsmp (third-party, from the 'darwin-tools' or old DTK) or:
sudo launchctl dumpstate | grep -A3 "mach-services"
```

> 🔬 **Forensics note:** Any process that registers an unexpected Mach service name under a legitimate-looking reverse-DNS identifier (e.g., `com.apple.security.policynotification` lookalike) before the real daemon does will intercept all clients that request that name. This is the **bootstrap name squatting** attack. SIP and code-signature validation at connection time mitigate it, but earlier macOS versions were vulnerable.

### XPC: Mach ports with structure + policy

XPC is the modern high-level IPC framework, introduced in macOS 10.7. It layers on top of Mach ports and adds:

1. **Structured serialization** — messages are `xpc_object_t` dictionaries/arrays, not raw Mach message bytes. Type-safe across architectures.
2. **Service lifecycle management** — launchd starts XPC services on-demand when a connection is requested, and can terminate them when idle.
3. **Mandatory sandboxing** — each XPC service runs in its own sandbox profile, independent of the parent app.
4. **Code-signature and entitlement validation** — the service can (and should) call `xpc_connection_get_audit_token` and validate the connecting process's Team ID, bundle ID, or entitlements before acting on any message.

**Two deployment patterns:**

| Pattern | Where it lives | Who manages lifecycle |
|---|---|---|
| **XPC Service** (in-bundle) | `MyApp.app/Contents/XPCServices/MyHelper.xpc` | launchd, on behalf of the app |
| **Launch Daemon/Agent with `MachServices` key** | `/Library/LaunchDaemons/com.example.helper.plist` | launchd at boot / login |

For in-bundle XPC services, the `.xpc` bundle looks like a mini-app:
```
MyHelper.xpc/
  Contents/
    Info.plist          ← CFBundleIdentifier, XPCServiceType
    MacOS/
      MyHelper          ← the actual Mach-O binary
    _CodeSignature/
```

**Connection and message flow:**

```
App process                              XPC Service process
──────────                               ──────────────────
xpc_connection_create("com.example.h")  ← launchd spawns via xpcproxy
         │                                      │
         │  Mach message (xpc bootstrap port)   │
         └──────────────────────────────────────►│
                                                │ xpc_connection_set_event_handler()
                                                │ xpc_connection_resume()
         │◄─────────────────────────────────────│
         │  reply dictionary                    │
```

`xpcproxy` is the bootstrap trampoline: launchd starts `xpcproxy`, which uses `posix_spawn()` with `POSIX_SPAWN_SETEXEC` to exec the XPC helper binary *over itself*, preserving the PID. This means **the PID you see in `ps` for an XPC helper is the same PID xpcproxy had** — the exec-over trick makes the helper appear to have a clean process ancestry through launchd.

> 🔬 **Forensics note:** Because `xpcproxy` execs over itself, all `execve`/`posix_spawn` on macOS flow through launchd and xpcproxy — these are the *only* processes that should ever call those syscalls at the BSD layer (under normal operation). Endpoint security frameworks and EDR tools watch for any process other than launchd/xpcproxy executing a new binary as a strong anomaly signal.

### Grand Central Dispatch (GCD) and thread mapping

GCD (`libdispatch`) sits in user space. Its model: you submit work items (blocks/closures) to **dispatch queues**; the GCD runtime decides which OS thread runs them and when. You never directly create `pthread_t` for most application work.

Key mappings to OS threads:

```
Dispatch queue types:
  serial queue    → at most 1 thread at a time; items run in FIFO order
  concurrent queue → multiple worker threads; ordering not guaranteed

Thread pool: GCD maintains a pool; on Apple Silicon, the scheduler routes
             QoS-tagged queues to the right core cluster:
  .userInteractive  → P-cores (performance)
  .userInitiated    → P-cores
  .default          → P-cores
  .utility          → E-cores (efficiency)
  .background       → E-cores, throttled

Workloop queues (newer): eliminate the liveliness overhead of thread
                         pool management; preferred in libdispatch internals
```

GCD queues are **not 1:1 with threads**. A process with 200 pending queue items may run on 4–8 actual pthreads. `vmmap` will show you the thread stacks; `sample` and `spindump` will show you the call graph at each thread.

> 🪟 **Windows contrast:** Windows has `ThreadPool` and `QueueUserWorkItem`, but the equivalent of QoS-to-core-cluster routing (P vs E cores) is a newer addition (Windows 11 thread director). GCD has had this mapping since Apple Silicon launch and it's deeply baked into the scheduler.

### Signals

macOS inherits POSIX signals but they interact with Mach in non-obvious ways. Signals are delivered via the BSD plane: the kernel converts a signal into a Mach exception for the target task's exception port handler first, then falls back to BSD signal disposition if no Mach exception handler claims it.

Practical implications:

- A debugger (lldb) registers a Mach exception port. When you `SIGSTOP` a debugged process, lldb actually intercepts the EXC_SOFT_SIGNAL Mach exception before the BSD signal is delivered.
- `kill -9` sends SIGKILL via BSD; the kernel forces task termination at the Mach level — no signal handler, no Mach exception port, no cleanup.
- RunningBoard (the macOS process supervisor since Catalina) uses `SIGTERM` + a grace period + `SIGKILL` sequence to clean up unresponsive processes, not `exit()`.

### Responsibility and launch context

macOS tracks **process responsibility** (who "owns" a user interaction) separately from process ancestry. The `com.apple.runningboard` daemon and `NSRunningApplication` surface this. A process launched by launchd as a daemon is not responsible for any GUI interaction; an app launched by the user in Finder is responsible.

The **launch context** determines which security policies apply:

| Context | Typical processes | Mach bootstrap namespace |
|---|---|---|
| System | Root daemons (PID 1 children) | `/system` bootstrap |
| Login session | User daemons, Launch Agents | `gui/<uid>` bootstrap |
| App | GUI apps, XPC services | Inherits from login session |

`launchctl print system` and `launchctl print gui/$(id -u)` dump these namespaces.

---

## Hands-on (CLI & GUI)

### Process inspection with `ps` and `top`

```bash
# Full UNIX process listing with threads and Mach info
ps auxww

# Show process tree — hierarchy is crucial for forensics
ps auxww --forest       # GNU ps (Homebrew)
pstree -p               # Homebrew: brew install pstree

# ps with specific columns for forensics
ps -eo pid,ppid,pgid,sess,uid,gid,comm,args | head -40

# Show all threads for a specific PID
ps -M -p <PID>          # -M lists each thread as a row
```

In **Activity Monitor** (open it): View → All Processes, with Windowed. Click View → Columns to add "Parent PID" and "Responsible" columns. The "Responsible" column shows the app that "owns" the interaction even if a helper process is doing the work.

### Virtual memory map: `vmmap`

```bash
# Full VM map of a process (run as the process owner, or sudo)
vmmap <PID>

# Compact summary: regions only
vmmap --summary <PID>

# Look for mapped files and dylibs
vmmap <PID> | grep -E '(__TEXT|__DATA|mapped file)'

# Expected output includes regions like:
# REGION TYPE                      START - END     [ VSIZE] PRT/MAX SHRMOD  REGION DETAIL
# __TEXT                 000000010001c000-000000010004c000 [  192K] r-x/r-x SM=COW  /usr/bin/ssh
# Stack                  000070007ffd4000-000070007ffdc000 [   32K] r-w/rwx SM=PRV  thread 0
```

`vmmap` reads `/proc`-equivalent Mach VM interfaces (`mach_vm_region_recurse`). The `SM=` column tells you the sharing mode: `COW` (copy-on-write shared), `PRV` (private), `SHM` (System V shared memory), `NUL` (reserved but uncommitted).

> 🔬 **Forensics note:** `vmmap` output shows every mapped dylib. A process that has loaded an unexpected `.dylib` from `/tmp` or a user-writable path is a strong indicator of dylib injection. Cross-reference with `codesign -dv --entitlements :- <pid>`.

### Sampling call stacks: `sample` and `spindump`

```bash
# Sample a process for 5 seconds at 1ms intervals, write report to stdout
sample <PID> 5 -mayDie

# Spindump: system-wide hang report (requires sudo for other users' processes)
sudo spindump <PID> 10 10 -o /tmp/spindump.txt

# Spindump of a specific app by name
sudo spindump Safari 10 10
```

`sample` calls `task_threads` and `thread_get_state` on each thread every interval, building a call-graph histogram. The output shows the most-sampled call stacks, which reveals where CPU time actually goes (not just aggregate %).

> 🔬 **Forensics note:** `spindump` and `sample` artifacts (saved to `/Library/Logs/DiagnosticReports/` or `~/Library/Logs/DiagnosticReports/`) contain full process ancestry, binary paths, and load addresses. On a suspect machine, these files are first-class forensic artifacts — they can reveal processes that have since exited.

### Code signature inspection

```bash
# Inspect code signature of a running process's binary
codesign -dv --verbose=4 /path/to/binary

# From a PID — first find the binary path
ps -p <PID> -o args=
codesign -dv --verbose=4 $(ps -p <PID> -o args= | awk '{print $1}')

# Check entitlements (crucial for XPC and TCC understanding)
codesign -d --entitlements :- <PID_or_path>    # :- means stdout as plist
codesign -d --entitlements - --xml <path>      # raw XML

# Verify signature is intact (returns 0 if valid)
codesign --verify --deep --strict <path>

# Inspect a running process's signature directly via pid
codesign -dv --pid <PID>   # macOS 13+

# Example output for a system binary:
# Identifier=com.apple.Safari
# Format=Mach-O universal (x86_64 arm64)
# CodeDirectory v=20400 size=... flags=0x10000(runtime) hashes=...
# Signature size=...
# Authority=Software Signing
# Authority=Apple Root CA
# TeamIdentifier=not set (Apple)
# Sealed Resources version=2 rules=13 files=...
```

The **TeamIdentifier** field is the most forensically useful: third-party software always has a 10-character alphanumeric team ID; Apple's own signed software shows "not set" or "Apple". A binary claiming to be `com.apple.Safari` with a third-party team ID is an impersonator.

### Enumerating XPC helpers

```bash
# Find all XPC service bundles in a running app
find /Applications/Safari.app -name "*.xpc" 2>/dev/null

# Or for any app
find /Applications -name "*.xpc" -maxdepth 6 | head -30

# List XPC services registered in the current user's bootstrap namespace
launchctl print gui/$(id -u) | grep -E 'xpc|service'

# Find XPC helpers as running processes (they appear as direct children of launchd)
ps axo pid,ppid,comm | awk '$2 == 1' | grep -v '^\s*$'

# Inspect the Info.plist of an XPC bundle to see its service type and identifier
/usr/libexec/PlistBuddy -c "print :CFBundleIdentifier" \
  "/Applications/Safari.app/Contents/XPCServices/com.apple.Safari.SandboxBroker.xpc/Contents/Info.plist"

# Find all XPC helpers for a given process by looking at its children
pgrep -P <PID>                  # direct children
# Then walk the tree
ps axo pid,ppid,comm | awk -v ppid=<PID> '$2==ppid {print}'
```

A fully decomposed modern app (Safari, Xcode, Final Cut Pro) can have 20–40 XPC helper processes. Each runs in its own sandbox, with only the entitlements it needs for its specific function.

### DTrace and dtruss caveats under SIP

```bash
# dtruss is a DTrace-based strace equivalent
# Under SIP (which you should leave enabled), it CANNOT trace system processes
# It CAN trace your own processes if you have the com.apple.security.get-task-allow
# entitlement (development builds only) or if the binary is not SIP-protected

# To trace your own process (development binary):
sudo dtruss -p <PID>

# Common dtrace probes (if SIP permits):
sudo dtrace -n 'syscall::open*:entry { printf("%s %s\n", execname, copyinstr(arg0)); }'

# On Apple Silicon, DTrace is further restricted compared to Intel.
# Use 'Instruments' (Xcode) for production-level tracing — it uses
# kdebug kernel tracing which IS permitted under SIP
```

> ⚠️ **ADVANCED:** Disabling SIP to run unrestricted DTrace exposes the kernel task port and allows any root process to modify the kernel. Never disable SIP on a machine you care about without a clear, bounded reason. Use Instruments' "System Trace" template instead — it captures the same kdebug events via an approved channel.

### lldb process attachment

```bash
# Attach to a running process (requires entitlement or sudo + no SIP for system procs)
lldb -p <PID>

# Inside lldb:
(lldb) bt all        # backtrace all threads
(lldb) thread list   # list threads with their state
(lldb) po [NSRunLoop mainRunLoop]   # send ObjC message in app context
(lldb) memory read --size 8 --format x 0x<address>
(lldb) image list   # all loaded dylibs with load addresses
(lldb) detach       # detach without killing

# For XPC services, attaching requires the parent app to have
# com.apple.security.get-task-allow in its debug entitlements
```

---

## Labs

### Lab 1 — Explore your process tree

> ⚠️ **Read-only lab; no destructive operations. No backup needed.**

```bash
# 1. Install pstree if not present
brew install pstree

# 2. Print full process tree rooted at PID 1
pstree -p 1 | head -80

# 3. Find all launchd-direct children (the ones without a real parent app)
ps axo pid,ppid,uid,comm | awk '$2==1 {printf "pid=%-6s uid=%-6s %s\n",$1,$3,$4}'

# 4. Pick a browser (e.g. Safari PID) and find its XPC helpers
SAFARI_PID=$(pgrep -x Safari | head -1)
echo "Safari PID: $SAFARI_PID"
ps axo pid,ppid,comm | awk -v p=$SAFARI_PID '$2==p'

# 5. Find how many total XPC service bundles Safari ships
find /Applications/Safari.app -name "*.xpc" | wc -l
```

What to observe: launchd (PID 1) has many direct children that are daemons; your GUI app is a child of `loginwindow`, which is a child of launchd. XPC helpers appear as *direct children of launchd*, not of the app — the bootstrap architecture means launchd is the process parent even though the app logically "owns" the helper.

### Lab 2 — Mach port rights inspection

> ⚠️ **Requires root / sudo. Read-only. The `lsmp` tool is from Apple's open-source tools release.**

```bash
# Install lsmp (from Apple's open-source releases or Homebrew's macos-tools)
# If unavailable, use the vmmap approach below

# Option A: lsmp (if available)
sudo lsmp -p <PID>
# Output shows each port name, right type, send count, and the receiver if known

# Option B: Inspect via vmmap for mapped memory including port-backed objects
sudo vmmap <PID> | grep -i "mach"

# Option C: Check what ports a specific running app holds via proc_info
# The 'heap' tool shows Mach port allocations in the heap (development builds)

# Practical: inspect your own process's bootstrap port
python3 -c "
import ctypes, ctypes.util
lib = ctypes.CDLL(ctypes.util.find_library('System'))
print('My task port:', lib.mach_task_self())
print('My PID:', lib.getpid())
"
```

### Lab 3 — Sample a real process and read the call graph

> ⚠️ **Read-only. Output goes to stdout only.**

```bash
# 1. Open Safari and navigate to a page
open -a Safari https://developer.apple.com

# 2. Find Safari's main renderer PID
ps axo pid,ppid,comm | grep -i safari

# 3. Sample the Web Content process (not the main Safari process)
WC_PID=$(ps axo pid,ppid,comm | grep 'com.apple.WebKit' | awk '{print $1}' | head -1)
sample $WC_PID 5 -mayDie | head -60

# Expected: a call graph showing WebKit's event loop, IPC dispatching,
# JavaScript JIT compilation, and GCD worker threads
```

### Lab 4 — XPC helper code signature forensics

> ⚠️ **Read-only. No destructive operations.**

```bash
# 1. Pick any macOS app with XPC services
APP="/Applications/Safari.app"
XPC_DIR="$APP/Contents/XPCServices"

# 2. List all XPC helpers and their code-signing identities
for xpc in "$XPC_DIR"/*.xpc; do
  echo "=== $(basename $xpc) ==="
  BINARY="$xpc/Contents/MacOS/$(defaults read "$xpc/Contents/Info" CFBundleExecutable)"
  codesign -dv "$BINARY" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority|flags'
  echo
done

# 3. Extract entitlements for each helper
for xpc in "$XPC_DIR"/*.xpc; do
  echo "=== $(basename $xpc) entitlements ==="
  BINARY="$xpc/Contents/MacOS/$(defaults read "$xpc/Contents/Info" CFBundleExecutable)"
  codesign -d --entitlements :- "$BINARY" 2>/dev/null | \
    plutil -convert json -o - - | python3 -m json.tool 2>/dev/null | head -20
  echo
done
```

What to observe: WebKit's Web Content process has heavy sandboxing entitlements; the GPU process has a different set; the Networking process has entitlements to open network sockets but not file system access beyond `/tmp`. This is privilege separation in action.

### Lab 5 — Reconstruct a process's full ancestry chain

> ⚠️ **Read-only. Requires understanding `ps` PPID output.**

```bash
# Given any PID, walk up to PID 1 printing the ancestry
walk_ancestry() {
  local pid=$1
  while [ "$pid" != "0" ]; do
    local info=$(ps -p $pid -o pid=,ppid=,comm= 2>/dev/null)
    echo "$info"
    local ppid=$(echo $info | awk '{print $2}')
    [ "$ppid" = "$pid" ] && break
    pid=$ppid
  done
}

# Usage: find the ancestry of your current shell
walk_ancestry $$

# Usage: find the ancestry of an XPC helper
XPC_PID=$(ps axo pid,comm | grep 'SafariWebContent\|com.apple.Web' | awk '{print $1}' | head -1)
[ -n "$XPC_PID" ] && walk_ancestry $XPC_PID
```

---

## Pitfalls & gotchas

**"My process shows PID 1 as parent, but it's an XPC helper."**
Correct — `xpcproxy` execs over itself with `POSIX_SPAWN_SETEXEC`, so the XPC helper's PPID is launchd (1). The logical parent is the app that connected, but the OS-level PPID is 1. Use `launchctl print gui/$(id -u)` to find the requesting app via the MachService connection, or correlate via Unified Log (`log show --predicate 'subsystem == "com.apple.xpc"'`).

**"DTrace/dtruss just errors with 'dtrace: failed to grab pid'"**
SIP blocks DTrace from tracing processes it doesn't own. Use Instruments "System Trace" / "Time Profiler" for the same data through an approved channel, or `sample`/`spindump` for call-graph sampling.

**"codesign reports the PID but shows 'no valid signature'"**
The binary may be an ad-hoc signed development build (flags contain `0x2` = adhoc). Ad-hoc signing means the hash of the binary is the identity — valid for local development, not for App Store or notarization. Any modification breaks the signature.

**"vmmap says a process has 50 GB of virtual memory"**
Virtual memory maps include uncommitted (reserved) regions, memory-mapped files, and the 64-bit address space is enormous. Resident Set Size (RSS) or the "Physical Memory" column in Activity Monitor reflects actually paged-in pages. The "real" RAM cost of a process is its *compressed* footprint, visible as "Memory" in Activity Monitor (which combines RSS + IOKit-mapped pages + GPU memory).

**"task_for_pid fails even as root"**
`taskgated` controls `task_for_pid`. With SIP enabled, even root cannot obtain task ports for system-signed processes unless the target has `com.apple.security.get-task-allow`. Attach with `lldb` instead (lldb uses a private Mach interface that SIP permits for debugging).

**Mach port name collision across bootstrap contexts**
Login windows and fast-user-switching create distinct `gui/<uid>` bootstrap namespaces. A Mach service name can be registered in each namespace independently. Two users running the same helper daemon get separate port endpoints. Never assume a Mach service name is global; it's per-bootstrap-context.

---

## Key takeaways

- A macOS process is simultaneously a **Mach task** (address space + port rights) and a **BSD process** (PID + signals + FDs). Different syscall families operate on each plane.
- **Mach ports** are kernel-managed capability objects. You cannot forge a port right. The IPC table uses generation numbers to prevent name reuse attacks.
- **launchd** is the bootstrap server: all Mach service registration and lookup flow through it. Every process on the system is a descendant of PID 1 and inherits the bootstrap port.
- **XPC** wraps Mach ports in structured serialization, adds per-service sandboxing, and lets launchd manage service lifetimes on demand. Modern Apple apps decompose into 10–40 XPC helper processes.
- **xpcproxy** execs over itself to launch XPC helpers — helpers appear as children of launchd (PID 1), not of the requesting app.
- **GCD** submits work to a thread pool and routes QoS-tagged queues to P-cores vs E-cores on Apple Silicon. You almost never create pthreads directly.
- For forensics: always verify **code signatures + Team IDs** of running process binaries, trace **process ancestry** up to PID 1, and enumerate **XPC helpers** (they reveal the true attack surface of an app).
- **SIP blocks DTrace** from inspecting system processes. Use `sample`, `spindump`, and Instruments System Trace for legitimate profiling/forensics.

---

## Terms introduced

| Term | Definition |
|---|---|
| Mach task | Kernel abstraction for an address space + port-rights namespace; paired 1-to-1 with a BSD process |
| Mach port | Kernel-owned message queue; referenced through port rights, never raw pointers |
| Port right | SEND, RECEIVE, or SEND_ONCE capability to a Mach port, held in a task's IPC table |
| ipc_space | Per-task table mapping port names (integers) to `ipc_entry` structures |
| bootstrap port | Every task's send right to the bootstrap server (launchd), inherited from parent |
| bootstrap namespace | Per-context registry of named Mach services; system, gui/<uid>, and app contexts exist |
| XPC | Cross-Process Communication; Apple's structured IPC layer on top of Mach ports |
| XPC Service | A sandboxed helper process bundle (`.xpc`) managed by launchd on behalf of an app |
| xpcproxy | launchd helper that spawns XPC services by exec-over (POSIX_SPAWN_SETEXEC) |
| GCD (Grand Central Dispatch) | User-space work-queue system that maps queue work items to OS threads with QoS-aware scheduling |
| dispatch queue | FIFO or concurrent queue for GCD work items; not 1:1 with threads |
| process responsibility | macOS attribution of user interaction to the "owning" app, tracked by RunningBoard |
| launch context | Bootstrap namespace context (system / login session / app) determining security policy |
| taskgated | Daemon that controls access to `task_for_pid`; blocks unauthorized task-port acquisition |
| spindump | Apple tool that captures system-wide call-graph samples; output archived in DiagnosticReports |
| vmmap | Tool that dumps a process's virtual memory map including all mapped files and regions |

---

## Further reading

- **Apple Platform Security guide** (developer.apple.com/documentation/security) — Mach IPC, task ports, SIP, and taskgated are covered in the OS Integrity sections.
- **"*OS Internals" Vol. 1 & 3 by Jonathan Levin** (`newosxbook.com`) — the definitive deep dive into launchd, Mach IPC, XPC, and the bootstrap mechanism. Chapter 7 (launchd) is freely available as a PDF.
- **Howard Oakley, The Eclectic Light Company** (`eclecticlight.co/2026/02/07/explainer-xpc/`) — accessible explainer on XPC from a macOS-first perspective, including macOS 15+ behavior.
- **Karol Mazurek, "Mach IPC Security on macOS"** (`karol-mazurek.medium.com`) — practical security analysis of port rights, the IPC table structure, and privilege escalation vectors via task ports.
- **HackTricks macOS XPC** (`hacktricks.wiki`) — attacker-oriented enumeration and exploitation techniques; invaluable for understanding what to look for forensically.
- **MITRE ATT&CK T1559.003** — XPC Services sub-technique, with detection guidance.
- **`man 3 xpc`**, **`man 3 dispatch`**, **`man 1 sample`**, **`man 1 spindump`**, **`man 1 vmmap`** — all ship with macOS; read them in Terminal.

---

*Related lessons: [[00-darwin-and-xnu-kernel]] · [[05-launchd-and-the-launch-system]] · [[08-security-architecture]] · [[07-memory-virtual-memory-and-swap]] · [[10-unified-logging-and-diagnostics]]*
