---
title: "Debugging, Instruments & lldb for iOS"
part: "10 — iOS App Engineering"
lesson: 11
est_time: "45 min read + 20 min labs"
prerequisites: [simulator-internals-and-on-disk-filesystem, processes-mach-xpc]
tags: [ios, dev, debugging, lldb, instruments, metrickit]
last_reviewed: 2026-06-26
---

# Debugging, Instruments & lldb for iOS

> **In one sentence:** The iOS performance-and-debugging toolchain is the *same* lldb + Instruments + os_log stack you used on macOS — but a `task_for_pid()`/`get-task-allow` permission gate decides which processes you may attach to, which is exactly why you can debug your own dev build and the Simulator freely yet cannot point a debugger at a shipping App Store binary.

## Why this matters

You already know lldb, Instruments, and the unified log from `macos-mastery` — and that knowledge transfers almost verbatim, because the Simulator runs *native* macOS-kernel processes and on-device debugging speaks the same `debugserver`/lldb protocol. What changes on iOS is the **trust boundary**: a process is debuggable only if it carries `get-task-allow`, and only a debugger entitled to `task_for_pid-allow` may attach. That single fact is the hinge between two worlds you care about. As a *builder*, it explains why you must use a development-signed build and why your release build is opaque. As a *reverse-engineer and examiner* (Part 11), it explains why attaching Frida/lldb to an App Store app requires a re-sign or a jailbroken device — and why the artifacts these tools emit (crash `.ips` logs, MetricKit diagnostic payloads, OSLogStore entries) are evidence you read, not just telemetry you write. This lesson maps the whole toolchain, names the daemons and on-disk formats, and tells you what the Simulator can and cannot stand in for.

## Concepts

### The toolchain map: one signal, many readers

Every performance/diagnostic signal on iOS originates from a small number of kernel facilities and is surfaced by a tool. Internalize the source → reader mapping; the rest of the lesson elaborates each row.

```
SIGNAL SOURCE (kernel/runtime)        SURFACED BY                      ARTIFACT / SCOPE
──────────────────────────────────    ─────────────────────────────    ─────────────────────────
Mach task control port (task_for_pid) lldb ⇄ debugserver               live process; needs get-task-allow
kperf / kdebug sampling + Mach time   Time Profiler / xctrace          .trace bundle
libmalloc recording (zone hooks)      Allocations / Leaks / memgraph   .trace / .memgraph
CoreProfile / hardware PMCs (A18/M4)  Processor Trace / CPU Counters   .trace (exact, not sampled)
os_log() ring buffer  →  logd         log / Console / OSLogStore       unified log (.tracev3)
os_signpost() intervals               Instruments points-of-interest   .trace + unified log
ReportCrash / ExceptionHandler        crash report (.ips JSON)         /var/.../CrashReporter
metrickitd aggregation (24h)          MetricKit MX*Payload             on-device → your delegate
CARenderServer layer snapshot         View Hierarchy debugger          in-Xcode (over debugserver)
```

The crucial split: **lldb gives you control** (breakpoints, register/memory read-write, expression evaluation) and is *intrusive*; **Instruments gives you observation** (statistical or exact profiles) and is *low-perturbation*; **os_log / MetricKit / crash reports are persistent records** that outlive the run and become forensic artifacts.

> 🖥️ **macOS contrast:** Binary-for-binary, these are the tools you already ran on macOS — `lldb`, `Instruments.app`, `xctrace`, `log`, `leaks`, `vmmap`, `malloc_history`, `atos`. On macOS, with SIP off (or a properly entitled debugger) you can attach to almost anything you own. iOS keeps the same tools but enforces a hard `get-task-allow` gate even for *your* processes — and adds the Simulator as a fully unrestricted target that behaves like a macOS process because that's literally what it is.

### lldb against the Simulator vs. a device

A Simulator "app" is a normal **native Mach-O process running on the host macOS kernel** (the iOS *frameworks* are recompiled for the host arch; see [[01-simulator-internals-and-on-disk-filesystem]]). There is **no AMFI, no code-signing enforcement, no `get-task-allow` check** — lldb attaches like it would to any Terminal program. This is your unrestricted lab.

```
ATTACH DECISION TREE
─────────────────────
target is a Simulator process?
   └─ yes → attach freely (host macOS, no gate)              ← your lab
   └─ no  → on-device process:
            does the target binary carry get-task-allow = true?
               └─ yes (dev/Debug-signed build) → debugserver attaches  ← your own app
               └─ no  (App Store / TestFlight / Release) → DENIED
                        unless: device is jailbroken AND debugserver
                        is re-signed with task_for_pid-allow            ← Part 11 RE path
```

On a **device**, debugging rides this chain: Xcode's host-side lldb speaks the GDB-remote protocol to **`debugserver`**, a small stub that runs *on the device* and holds the entitlements `get-task-allow` and `task_for_pid-allow`. `debugserver` calls `task_for_pid()` to obtain the target's Mach **task port** — the capability that lets one process read/write another's memory and thread state (the same Mach primitive from [[05-processes-mach-xpc]]). The kernel grants `task_for_pid()` on a target **only if that target was signed with `get-task-allow = true`**. Xcode injects `get-task-allow` into every Debug build automatically via the development provisioning profile; the App Store submission pipeline strips it. Hence: your dev build is debuggable, a downloaded app is not.

Transport has modernized. Pre-iOS 17, `debugserver` shipped inside the mounted **Developer Disk Image (DDI)** and Xcode tunnelled lldb over USB via `usbmuxd`. On **iOS 17+ / Xcode 15+** the stack is **CoreDevice**: the DDI is now **personalized** (Image4-signed to the specific device, like a mini-firmware — see [[02-image4-personalization-shsh]]), mounted via `mobile_image_mounter`, and lldb traffic rides a **RemoteXPC tunnel** brokered by `remotectl`/`devicectl` (you can see and drive devices with `xcrun devicectl device info`, `xcrun devicectl device process launch …`). The lldb command surface is unchanged; only the plumbing moved.

> ⚖️ **Authorization:** `get-task-allow` is the precise line between development and tampering. Attaching a debugger to *your own* dev build is routine engineering. Attaching to *someone else's* shipping app requires defeating that gate (re-sign + sideload, or a jailbroken device with an entitled `debugserver`) — that is a deliberate act with legal weight under the CFAA/DMCA §1201 and your engagement scope. Do it only on binaries you are authorized to analyze. The mechanism is covered as RE in [[05-dynamic-analysis-with-frida]] and [[03-fairplay-encryption-and-decrypting-app-store-apps]].

### lldb commands you will actually use

The command set is identical to macOS lldb; the iOS-specific value is in what you inspect (Objective-C/Swift runtime, the heap, framework internals).

| Command | What it does |
|---|---|
| `process attach --name MyApp` / `--pid N` | Attach to a running (debuggable) process |
| `process attach --waitfor --name MyApp` | Block until the named process launches, then attach (catches launch-time bugs) |
| `image list -o -f` | Loaded Mach-O images with **load address + ASLR slide** + path (essential for static-tool address math) |
| `image lookup -a <addr>` | Resolve an address to symbol/source (manual symbolication) |
| `image lookup -rn <regex>` | Find symbols by regex across loaded images — your map into framework internals |
| `breakpoint set -n "-[NSURLSession dataTaskWithRequest:]"` | Break on an ObjC method by selector |
| `breakpoint set -F 'MyApp.LoginVC.submit()'` | Break on a (demangled) Swift symbol |
| `po obj` / `p expr` | Print object (ObjC description / Swift `debugDescription`) / evaluate expression |
| `expression -l objc -O -- [obj someMethod]` | Inject and run code in the target — read or *mutate* live state |
| `register read x0 x1 x2 sp pc` | arm64 registers (args in `x0–x7`, return in `x0`, `lr`=`x30`) |
| `memory read -fx -c16 $x0` | Hex-dump 16 words from a register-held pointer |
| `thread backtrace all` (`bt all`) | Stacks for every thread — for deadlocks/hangs |
| `command script import lldb.macosx.heap` | Load `malloc_info`/`ptr_refs`/`cstr_refs` heap helpers (needs Malloc Stack Logging) |

For Swift, set the language and watch for mangling: `breakpoint set -n` wants the mangled symbol (`$s5MyApp…`), while `-F` takes the human form. `image lookup -rn` on the shared cache (see [[02-the-dyld-shared-cache]]) is how you locate private framework methods to break on — the same move an RE uses, just on a binary you wrote.

> 🔬 **Forensics note:** `image list -o -f` is the cheapest way to read the **ASLR slide** of every loaded image at runtime. Static disassembly (Part 11) gives file offsets; subtract the on-disk preferred base and add the runtime slide to translate a Ghidra/IDA address to a live address (and vice-versa). Get this backwards and every breakpoint and symbolicated frame lands in the wrong place.

### Instruments and the v26 overhaul

Instruments is a front-end over **DTrace-style probes, `kperf`/`kdebug` sampling, `libmalloc` recording, and (on new silicon) hardware performance counters**, packaging a run as a **`.trace` bundle** (a directory of per-instrument data tables you can export). The classic instruments still anchor the workflow:

- **Time Profiler** — periodic **stack sampling** (default ~1 ms) of on-CPU threads via `kperf`. Statistical, not exact: a function absent from samples isn't proven absent, just rare. Read it as a call tree weighted by sample count; invert it to find leaf hot-spots. This is your first stop for "why is it slow / janky."
- **Allocations** — records every `malloc`/`free` through `libmalloc` zone hooks. Distinguishes **transient** (allocated then freed) from **persistent** (still live) memory and gives per-allocation backtraces ("Record reference counts" adds retain/release history). Use the **Mark Generation** ("generation analysis") button to diff heap growth between two moments — the canonical way to find an accumulating leak that `Leaks` can't see because the objects are still reachable.
- **Leaks** — periodically does a **conservative pointer scan** of the heap and reports blocks with no inbound references (true leaks/abandoned memory). It cannot find *reachable* growth (retain cycles that are still rooted) — that's what generation analysis + the Memory Graph debugger are for.

**The Xcode 26 / Instruments 26 changes (verify at author time):**

- **Processor Trace** — *exact*, non-sampled instruction tracing: it records **every branch decision, cycle count, and timestamp** in user space at ~1% overhead and reconstructs the precise execution path into a flame graph (no sampling bias). Requires hardware PMU support: **iPhone A18+ / iPad Pro & Mac M4+** (introduced Instruments 16.3; carried into 26). On older silicon it simply isn't available — Time Profiler remains the fallback.
- **CPU Counters** — a guided workflow exposing hardware **PMCs** (cache misses, branch mispredictions, memory stalls) so you can attribute a hotspot to a *micro-architectural* cause, not just to wall-clock time.
- **Power Profiler** — system- and app-level power attribution, captured either **tethered** (Instruments connected to the device) or **passively/untethered** (started from the device's Developer settings, run on battery in the field, then imported for analysis) so you can profile real-world power behaviour off the bench. Its companion new **CPU Profiler** samples each core independently *at that core's clock*, fairly weighting work across the **asymmetric P-core/E-core** layout — more accurate than Time Profiler for CPU-vs-power attribution.
- **SwiftUI instrument** — a dedicated template that surfaces view-body re-evaluations, dependency churn, and long updates, complementing **Hangs & Hitches** for UI responsiveness.
- **Compare runs** — `View ▸ Detail Area ▸ Compare With…` diffs a call tree against a previous `.trace`, turning "did my optimization help?" into a side-by-side.

> 🖥️ **macOS contrast:** Same `Instruments.app`, same `.trace` format, same `xctrace`. The only iOS wrinkle is target selection (a device requires a development-signed, `get-task-allow` build or a Simulator), and that **Processor Trace/CPU Counters/Power are hardware-gated** — the Simulator can run Time Profiler/Allocations/Leaks against host-native code, but it has **no device PMUs and no real power model**, so Processor Trace, accurate Power Profiler numbers, and thermal state are device-only.

### os_log / unified logging from the developer side

You already read the unified log as an examiner (`macos-mastery`, and on iOS via [[09-unified-logging-and-sysdiagnose]]). From the *builder* side you **write** it with the **`OSLog`** framework — modern Swift uses the **`Logger`** type:

```swift
import OSLog
let log = Logger(subsystem: "com.example.MyApp", category: "networking")
log.notice("Request to \(url, privacy: .public) status \(code)")
log.error("Decode failed for \(userID, privacy: .private)")   // userID → <private> in the store
```

Mechanism: `Logger`/`os_log()` writes structured records into a **kernel ring buffer**; **`logd`** drains it to compressed **`.tracev3`** files, storing only format-string **UUIDs** and rehydrating human text at read time from the emitting binary's `__TEXT,__os_log` strings. Two consequences that bite:

1. **Levels and persistence differ.** `debug` is memory-only and usually discarded; `info` persists briefly; `notice` (the default), `error`, and `fault` persist to disk. Don't log forensically-important state at `.debug` expecting to read it later.
2. **Privacy redaction is on by default for dynamic data.** Interpolated **strings/objects are redacted to `<private>`** unless you mark `privacy: .public`; scalar numbers default to public. Over-marking `.public` leaks PII into a store an examiner can read; under-marking blinds your own production logs.

Read your own logs **back inside the app** with **`OSLogStore`** (works on device and Simulator since iOS 15, *no entitlement*):

```swift
let store = try OSLogStore(scope: .currentProcessIdentifier)
let since = store.position(date: Date().addingTimeInterval(-3600))
let pred  = NSPredicate(format: "subsystem == %@", "com.example.MyApp")
for case let e as OSLogEntryLog in try store.getEntries(at: since, matching: pred) {
    print(e.date, e.level.rawValue, e.category, e.composedMessage)
}
```

Sandbox caveat: an iOS app may only use **`.currentProcessIdentifier`** scope — `.system` and `OSLogStore.local()` are blocked in the sandbox (they work on macOS). And entries written *before the current launch* are not returned. This is exactly how in-app "export logs" / shake-to-report features are built.

> 🔬 **Forensics note:** `os_signpost()` intervals (`.begin`/`.end`, used to drive Instruments' Points of Interest) also land in the unified log. Developer logging therefore doubles as an artifact: a sysdiagnose captured during an incident contains the app's own `Logger` lines (subsystem-filterable) and signpost timings — frequently the only record of in-app actions that never hit a server. Examiners filter with `log show --predicate 'subsystem == "com.example.MyApp"'` against a collected `.logarchive`.

### os_signpost: instrumenting your own intervals

When the built-in instruments don't measure *your* logical operation (a sync, a render pass, a parse), you emit **signposts** — paired interval markers that Instruments renders as a Points-of-Interest timeline and that `xctrace` can export, while *also* persisting to the unified log:

```swift
import OSLog
let signposter = OSSignposter(subsystem: "com.example.MyApp", category: "sync")
let id = signposter.makeSignpostID()
let state = signposter.beginInterval("FullSync", id: id, "items: \(count)")
// … do the work …
signposter.endInterval("FullSync", state)
signposter.emitEvent("CacheMiss", id: id)   // instantaneous marker
```

Mechanism: signposts use the **same `os_log` ring buffer and `logd` path** as logging, but a distinct record type carrying a stable `OSSignpostID` so begin/end pairs match even when intervals overlap on different threads. Drag a **Points of Interest** (or **os_signpost**) instrument into a trace to see them aligned against Time Profiler/Allocations lanes — this is how you attribute a CPU spike to *your* "FullSync" rather than to an anonymous stack. Signpost data is near-zero-overhead when no tool is recording (the records are dropped early), so you can ship them in release builds.

> 🔬 **Forensics note:** Because signposts persist to the unified log, an examiner can reconstruct an app's internal operation timeline from a sysdiagnose even with no Instruments session — `log show --predicate 'category == "sync"'` against the `.logarchive` recovers the begin/end pairs and their embedded metadata. Apps that signpost their crypto/network/sync stages effectively self-document their behavior into a device-side artifact.

### Crash reports, hangs, and the .ips format

When a process faults, the kernel's exception machinery hands off to **`ReportCrash`** (its on-device crash writer), which serializes a report. Since iOS 15 / macOS 12 the format is **`.ips`**: a JSON file whose **first line is a small header object** and whose remainder is the payload object (so it isn't valid single-document JSON — split the first newline). On device, reports live under **`/private/var/mobile/Library/Logs/CrashReporter/`** (and per-app `DiagnosticReports`); you retrieve them via Xcode *Devices & Simulators ▸ View Device Logs*, a **sysdiagnose**, or `idevicecrashreport` (libimobiledevice).

A raw `.ips` carries addresses + image UUIDs + slides but not your function names. **Symbolication** maps frame addresses back to source using the matching **`.dSYM`** (the external symbol bundle whose UUID must equal the crashing image's UUID — see [[00-ios-xcode-and-the-build-system]]):

```bash
# Symbolicate one address against a dSYM (load-addr + slide come from the report's image map)
atos -arch arm64 -o MyApp.app.dSYM/Contents/Resources/DWARF/MyApp -l 0x1029a4000 0x1029c1d3c
```

**Hangs** (main-thread unresponsive > ~250 ms) are reported by `ReportCrash`'s watchdog path too, and surfaced live by the **Hangs & Hitches** instrument. The *kill* itself comes from two distinct mechanisms — not a single "watchdog daemon": the **launch/responsiveness watchdog enforced by SpringBoard/RunningBoard** terminates an app that takes too long to launch, resume, or service a UI event (the `0x8badf00d` exception code; crash-report namespace `SPRINGBOARD`/`FRONTBOARD`), while the **kernel's jetsam (`memorystatus`) subsystem** evicts an app for exceeding its memory limit or under system memory pressure (see [[06-memory-jetsam-app-lifecycle]]).

> 🔬 **Forensics note:** Crash and jetsam logs are first-class artifacts. The **termination reason** and **exception type/code** distinguish a user-initiated quit from a `0x8badf00d` watchdog kill, an `0xdead10cc` ("deadlock"—a suspend with a held file lock), or a jetsam memory eviction — which can corroborate or refute claims about *when and how* an app stopped. They are in every sysdiagnose; pair them with the unified log for a per-app timeline.

### MetricKit: on-device diagnostics delivered to the developer

`Logger` and crash reports are reactive. **MetricKit** is Apple's framework for **aggregated, privacy-preserving field telemetry** delivered to *your* app from `metrickitd`. You subscribe a singleton subscriber and receive payloads:

```swift
import MetricKit
final class Metrics: NSObject, MXMetricManagerSubscriber {
    override init() { super.init(); MXMetricManager.shared.add(self) }
    func didReceive(_ payloads: [MXMetricPayload])      { /* perf metrics */ }
    func didReceive(_ payloads: [MXDiagnosticPayload])  { /* crashes/hangs/etc. */ }
}
```

- **`MXMetricPayload`** — performance aggregates over the prior 24 h, delivered **at most once per day** on a later launch: `MXCPUMetric`, `MXMemoryMetric`, `MXAppLaunchMetric`, `MXAppResponsivenessMetric`, `MXDiskIOMetric`, `MXAnimationMetric`, `MXNetworkTransferMetric`, `MXGPUMetric`, signpost metrics, and **`MXAppExitMetric`**.
- **`MXDiagnosticPayload`** — actionable diagnostics, delivered more promptly: `crashDiagnostics`, `hangDiagnostics`, `cpuExceptionDiagnostics`, `diskWriteExceptionDiagnostics`, and (iOS 16+) `appLaunchDiagnostics`. Each carries an **`MXCallStackTree`** (`callStackTree.jsonRepresentation()`) plus an `MXMetaData` header (OS/build/device). This is how you get *symbolicate-able crash stacks from the field* without a third-party SDK.

**`MXAppExitMetric`** is the standout for "why did my app die in the field." It splits into `foregroundExitData` (`MXForegroundExitData`) and `backgroundExitData` (`MXBackgroundExitData`), each a histogram of exit causes:

| Property (foreground) | Meaning |
|---|---|
| `cumulativeNormalAppExitCount` | Clean exits (user backgrounded/quit) |
| `cumulativeMemoryResourceLimitExitCount` | Killed for exceeding the memory limit (jetsam) |
| `cumulativeBadAccessExitCount` | `EXC_BAD_ACCESS` (e.g. `SIGSEGV`) |
| `cumulativeAbnormalExitCount` | Other abnormal termination |
| `cumulativeAppWatchdogExitCount` | Watchdog kill (`0x8badf00d`) |
| `cumulativeCPUResourceLimitExitCount` | CPU resource-limit kill |
| `cumulativeIllegalInstructionExitCount` | `EXC_BAD_INSTRUCTION` (often a Swift `fatalError`/trap) |
| `cumulativeMemoryPressureExitCount` | Killed under system memory pressure |

`MXBackgroundExitData` adds `cumulativeSuspendedWithLockedFileExitCount` (`0xdead10cc`) and `cumulativeBackgroundTaskAssertionTimeoutExitCount` — the canonical "your background task ran too long" death.

> 🔬 **Forensics note:** MetricKit payloads are JSON (`payload.jsonRepresentation()`), and apps that subscribe routinely **persist them locally** (App Support / a logs cache) or POST them to a backend. On a triaged device or in an app-data acquisition (Part 08), those stored payloads are a behavioral record: which exits occurred, when, and—via the diagnostic call-stack trees—*where in the binary* the app was crashing. Treat them like any other app-authored log store.

> 🖥️ **macOS contrast:** MetricKit is iOS-first (added iOS 13; macOS support arrived in macOS 12). The closest macOS analogue you used is the **`log` stream + DiagnosticReports + `spindump`** combination — MetricKit bundles the equivalent into a single delegate-delivered, privacy-aggregated payload rather than loose files you scrape.

### The View-hierarchy and Memory-graph debuggers

Two GUI debuggers ride the *same* `debugserver`/lldb connection (so they obey the same `get-task-allow` gate):

- **View Hierarchy** (*Debug ▸ View Debugging ▸ Capture View Hierarchy*) — pauses the app, walks the live `UIView`/`CALayer` tree via runtime introspection, snapshots each layer through the **CARenderServer**, and renders an exploded 3-D view with constraint info. Mechanism, not magic: it's reflection over the same view tree your code built, surfaced over the debug connection — which is why it needs a debuggable build.
- **Memory Graph** (*Debug ▸ Capture Memory Graph*) — captures the object graph + retain edges into a **`.memgraph`** file (a Mach-O *corpse*/snapshot). Its real power is the **CLI you already know**: a `.memgraph` is consumable off-line by `leaks MyApp.memgraph`, `vmmap MyApp.memgraph`, `heap MyApp.memgraph`, and `malloc_history MyApp.memgraph <addr>` — so you can script leak/retain-cycle detection. Enable **Malloc Stack Logging** in the scheme first or the backtraces are empty.

> 🖥️ **macOS contrast:** `.memgraph`, `leaks`, `vmmap`, `malloc_history`, `heap`, and `atos` are the *identical* macOS binaries; an iOS `.memgraph` captured in Xcode analyzes with the same command lines you used on macOS. The capture path differs (over `debugserver` to a debuggable target) but the artifact and its readers do not.

## Hands-on

All commands run **on the Mac** (there is no on-device shell). Device-targeted commands are walkthroughs unless you have hardware.

**Attach lldb to a Simulator process (unrestricted target):**

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl launch --wait-for-debugger booted com.example.MyApp   # suspends at launch
# In another shell, drive lldb directly:
xcrun lldb
(lldb) platform select ios-simulator
(lldb) process attach --name MyApp
(lldb) breakpoint set -n "-[NSURLSession dataTaskWithRequest:completionHandler:]"
(lldb) continue
(lldb) image list -o -f          # load addresses + ASLR slides
(lldb) po $x2                    # inspect an argument register
```

**Record and dissect a trace from the CLI with `xctrace`:**

```bash
xcrun xctrace list templates          # Time Profiler, Allocations, Leaks, SwiftUI, …
xcrun xctrace list devices            # Simulators + (personalized) attached devices

# Launch + profile a Simulator app, 10 s, into a .trace bundle:
xcrun xctrace record --template 'Time Profiler' \
  --device-name 'iPhone 17 Pro' \
  --output /tmp/MyApp.trace \
  --launch -- com.example.MyApp

# Inspect what tables the run holds, then extract raw samples as XML:
xcrun xctrace export --input /tmp/MyApp.trace --toc
xcrun xctrace export --input /tmp/MyApp.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'
xcrun xctrace symbolicate --input /tmp/MyApp.trace   # fold in dSYM symbols
```

**Read your own app's unified-log lines back (Simulator or device, no entitlement):**

```bash
# From the Mac, against a booted Simulator:
xcrun simctl spawn booted log show --predicate 'subsystem == "com.example.MyApp"' \
  --last 30m --style compact
# On a connected device, collect a portable archive for off-line analysis:
log collect --device-name 'My iPhone' --last 1h --output /tmp/device.logarchive
log show --archive /tmp/device.logarchive --predicate 'subsystem == "com.example.MyApp"'
```

**Pull and split a crash `.ips`, then symbolicate:**

```bash
# Device-side retrieval (libimobiledevice) — walkthrough if you have hardware:
idevicecrashreport -e /tmp/crashes
# The .ips header is the first line; payload follows. Pretty-print the payload:
tail -n +2 /tmp/crashes/MyApp-2026-06-26-101500.ips | python3 -m json.tool | head -40
# Symbolicate a frame using the matching dSYM (UUIDs must match):
dwarfdump --uuid MyApp.app.dSYM           # confirm dSYM UUID == report image UUID
atos -arch arm64 -o MyApp.app.dSYM/Contents/Resources/DWARF/MyApp -l <load_addr> <frame_addr>
```

**Analyze a memory graph off-line (the `.memgraph` CLI):**

```bash
leaks /tmp/MyApp.memgraph                       # cycles + abandoned blocks
vmmap --summary /tmp/MyApp.memgraph             # region-by-region footprint
malloc_history /tmp/MyApp.memgraph <address>    # alloc backtrace (needs MSL)
```

**(Walkthrough) attach lldb to a device app you signed:** with the iPhone connected and trusted, `xcrun devicectl device info details` enumerates it; Xcode mounts the **personalized DDI** and launches your `get-task-allow` build under `debugserver`. The lldb prompt is identical to the Simulator session above — the gate, not the commands, is what changed.

## 🧪 Labs

> All labs are **device-free**. **Substrate + fidelity caveat:** Labs 1–3 use the **Xcode Simulator** (a host-native process — `lldb` and Time Profiler/Allocations/Leaks attach with **no `get-task-allow`/AMFI gate**, which is the point of Lab 1, but there is **no device PMU, no real power/thermal model, no SEP/Data-Protection**, so **Processor Trace, CPU Counters, and accurate Power Profiler are unavailable** here). Lab 4 is a **read-only walkthrough** of device-only debugging. Lab 5 reads a **MetricKit JSON payload** generated by Xcode's simulate-payload feature, since `metrickitd` does not run on the Simulator. (All labs need a full **Xcode** install for `simctl`/`xctrace`/`lldb` — Command Line Tools alone won't do.)

### Lab 1 — Prove the `get-task-allow` gate is absent on the Simulator (Simulator)

1. Build any SwiftUI app to a booted Simulator (`xcrun simctl install booted MyApp.app`; `xcrun simctl launch booted com.example.MyApp`).
2. `xcrun lldb` → `process attach --name MyApp`. It succeeds with no entitlement dance.
3. Inspect the bundle's signature: `codesign -d --entitlements - "$(xcrun simctl get_app_container booted com.example.MyApp)"`. Note whether `get-task-allow` is present.
4. Write one sentence on *why* the attach succeeded regardless of that entitlement (the Simulator is a host macOS process; the kernel `task_for_pid()` gate that enforces `get-task-allow` is the **device** kernel's, not in play here). This is the single most important difference between the lab substrate and a real device.

### Lab 2 — Find a hotspot with Time Profiler via `xctrace` (Simulator)

1. Add a deliberately expensive function (e.g. an `O(n²)` string concat in a loop) behind a button.
2. `xcrun xctrace record --template 'Time Profiler' --device-name '<your sim>' --output /tmp/hot.trace --launch -- com.example.MyApp`, exercise the button, stop.
3. `xcrun xctrace export --input /tmp/hot.trace --toc` to list tables; then export the `time-profile` table via XPath and confirm your function dominates the sample counts.
4. Open `/tmp/hot.trace` in Instruments, invert the call tree, and verify the GUI agrees with the CLI export. Note that a function with *zero* samples isn't proven fast — only un-sampled (the statistical-sampling caveat).

### Lab 3 — Catch a retain cycle with the Memory Graph CLI (Simulator)

1. Introduce a classic strong reference cycle (two classes holding each other strongly, or a closure capturing `self` strongly).
2. In Xcode (scheme ▸ Diagnostics) enable **Malloc Stack Logging**, run, trigger the cycle, then *Debug ▸ Capture Memory Graph* and *File ▸ Export Memory Graph* to `/tmp/cycle.memgraph`.
3. Off-line: `leaks /tmp/cycle.memgraph` — confirm it reports the cycle; `malloc_history /tmp/cycle.memgraph <addr>` for an offending object's allocation backtrace.
4. Fix with `weak`/`unowned`, re-capture, and confirm `leaks` is clean. You just used the *same* macOS CLI on an iOS-app artifact.

### Lab 4 — Walkthrough: the device debug + crash-log path (read-only)

1. Read Apple's *Diagnosing issues using crash reports and device logs* and Dev:Debugserver on theapplewiki.com. Write the chain from memory: host lldb → RemoteXPC tunnel (`remotectl`) → personalized DDI mount (`mobile_image_mounter`) → on-device `debugserver` → `task_for_pid()` → target task port.
2. Note the exact entitlement set that lets a **re-signed** `debugserver` attach to an *un*-debuggable app on a jailbroken device (`get-task-allow`, `task_for_pid-allow`, `com.apple.springboard.debugapplications`) — and why that is the RE bridge to [[05-dynamic-analysis-with-frida]].
3. From a public sample sysdiagnose (Josh Hickman / DFRWS), open a `.ips` crash report, split the header line from the payload, and identify `exception` type/code and `termination` reason. Map `0x8badf00d` and `0xdead10cc` to their causes.

### Lab 5 — Decode a MetricKit diagnostic payload (read-only / Simulator JSON)

1. In Xcode, run an app subscribed to `MXMetricManagerSubscriber`, then *Debug ▸ Simulate MetricKit Payloads* (the Simulator has no `metrickitd`, so this is the only way to exercise the path there).
2. In `didReceive(_:[MXDiagnosticPayload])`, write `payload.jsonRepresentation()` to a file; open it.
3. Locate the `crashDiagnostics` array, its `callStackTree`, and the `metaData` (OS/build/device). Map each `MXAppExitMetric` counter you see in a metric payload to its real-world cause from the table above.
4. Write two sentences on why this JSON is *also a forensic artifact*: where a real app would persist/transmit it, and what an examiner learns from a stored payload during an app-data acquisition.

## Pitfalls & gotchas

- **"Could not attach: not allowed to attach to process."** The target lacks `get-task-allow` (a Release/TestFlight/App Store build), or you're pointing lldb at a process you didn't sign. Use a **Debug** build, or the Simulator. This is the gate, not a bug.
- **Treating Time Profiler as exact.** It's **statistical sampling**. Low-frequency-but-expensive work can hide between samples; conversely a function with many samples might be cheap-but-frequent. For exactness use **Processor Trace** — but only on A18+/M4+, never on the Simulator.
- **Expecting Processor Trace / CPU Counters / real Power numbers on the Simulator.** They need device **PMUs**; the Simulator has none. Profile power/thermal/exact-CPU on hardware only.
- **dSYM UUID mismatch.** `atos`/symbolication silently produce useless output if the `.dSYM` UUID ≠ the crashing image UUID. Always `dwarfdump --uuid` both sides. Lost your dSYM (Bitcode-recompiled or `DEBUG_INFORMATION_FORMAT` misset)? The report stays unsymbolicated.
- **`.ips` is not valid single-document JSON.** The **first line is a separate header object**; feed the *remainder* to a JSON parser, or your `json.tool`/`jq` errors out.
- **Over-/under-using `privacy: .public`.** Dynamic strings/objects in `Logger` redact to `<private>` by default; marking everything `.public` spills PII into a store examiners read, marking nothing blinds production. Choose deliberately, field by field.
- **Logging important state at `.debug`.** `debug` is memory-only and routinely dropped; it won't be in the persisted store or a sysdiagnose. Use `.notice`/`.error`/`.fault` for anything you may need to read later.
- **OSLogStore scope on iOS.** A sandboxed app may only read **`.currentProcessIdentifier`**; `.system`/`OSLogStore.local()` work on macOS but are blocked on iOS — and you can't read entries from *before* the current launch.
- **MetricKit is not real-time.** Metric payloads arrive **at most once per 24 h on a later launch** (diagnostics sooner). Don't architect a live dashboard on it; and remember the **Simulator delivers nothing** without *Simulate MetricKit Payloads*.
- **Mistaking a watchdog/jetsam kill for a crash.** `0x8badf00d` (watchdog), `0xdead10cc` (suspended with locked file), and jetsam memory evictions are *terminations*, not classic signals — read the **termination reason**, not just the exception type, before concluding "it crashed."

## Key takeaways

- The iOS debug/profiling toolchain **is** the macOS one (lldb, Instruments, `xctrace`, `log`, `leaks`, `vmmap`, `atos`); the new variable is the **`get-task-allow` / `task_for_pid-allow`** trust gate.
- **The Simulator is your unrestricted target** — host-native processes, no AMFI/`get-task-allow` enforcement — but it has **no PMUs, no power/thermal model, no SEP/Data-Protection**, so Processor Trace, CPU Counters, and accurate Power are device-only.
- On a device, **lldb ⇄ debugserver** over the iOS 17+ **CoreDevice/RemoteXPC** tunnel + **personalized DDI**; the kernel grants the debugger's `task_for_pid()` only against a `get-task-allow` target — which is why you can debug your dev build but not a shipping app.
- **Instruments 26** adds exact **Processor Trace**, guided **CPU Counters**, an untethered **Power Profiler** + per-core **CPU Profiler**, a **SwiftUI** instrument, and call-tree **run comparison**; Time Profiler stays statistical, Allocations/Leaks stay the heap workhorses.
- **`Logger`/os_log** writes structured records via `logd` to `.tracev3`; mind level persistence and default `<private>` redaction. Read your own back with **`OSLogStore`** (`.currentProcessIdentifier` only on iOS).
- **Crash `.ips`, hang reports, and MetricKit payloads** are developer telemetry *and* forensic artifacts — symbolicate with the matching dSYM; `MXAppExitMetric` decodes *why* an app died (watchdog vs. jetsam vs. `EXC_BAD_ACCESS`).
- The **`.memgraph`** captured in Xcode is analyzable with the same `leaks`/`vmmap`/`malloc_history` CLIs you used on macOS — capture path differs, artifact and readers don't.
- The very gate that protects your debugging (`get-task-allow`) is what an RE/examiner must defeat (re-sign or jailbroken `debugserver`) to attach to a third-party app — the bridge into Part 11.

## Terms introduced

| Term | Definition |
|---|---|
| `get-task-allow` | Code-signing entitlement that makes a process debuggable; present in dev/Debug builds, stripped at App Store submission |
| `task_for_pid-allow` | Entitlement letting a debugger call `task_for_pid()` to obtain another process's Mach task port |
| `debugserver` | Apple's on-device GDB-remote stub that lldb drives to control a process; ships in the (personalized) Developer Disk Image |
| CoreDevice / `devicectl` | iOS 17+/Xcode 15+ device-management stack; lldb traffic rides a RemoteXPC tunnel brokered by `remotectl`/`devicectl` |
| Personalized DDI | Developer Disk Image Image4-signed (personalized) to a specific device and mounted via `mobile_image_mounter` |
| `xctrace` | Command-line front-end to Instruments: `record`/`export`/`import`/`symbolicate`/`list` over `.trace` bundles |
| `.trace` bundle | Instruments' output: a directory of per-instrument data tables, exportable via `xctrace export --toc`/XPath |
| Time Profiler | Statistical CPU profiler that periodically samples on-CPU thread stacks via `kperf` |
| Processor Trace | Exact, non-sampled instruction trace (every branch/cycle) at ~1% overhead; needs A18+/M4+ PMU support |
| CPU Counters | Instruments workflow exposing hardware PMCs (cache misses, branch mispredicts, stalls) |
| Allocations / generation analysis | `libmalloc`-recording instrument; "Mark Generation" diffs heap growth between two moments |
| Leaks | Instrument doing a conservative heap pointer-scan to report unreferenced (leaked) blocks |
| `Logger` / OSLog | Swift logging API writing structured records to the unified log via `logd` |
| `OSLogStore` | API to read unified-log entries programmatically; on iOS limited to `.currentProcessIdentifier` scope |
| `os_signpost` / `OSSignposter` | Interval/event marker API driving Instruments Points of Interest; uses a stable `OSSignpostID` to pair begin/end and also lands in the unified log |
| `.ips` (crash report) | Apple's JSON crash format (iOS 15+): a header object on line 1, payload object after |
| MetricKit / `MXMetricManager` | Framework delivering on-device aggregated performance metrics + diagnostics to the app's subscriber |
| `MXAppExitMetric` | MetricKit metric: histogram of foreground/background exit causes (normal, jetsam, watchdog, bad-access, …) |
| `MXDiagnosticPayload` | MetricKit diagnostics (crash/hang/CPU/disk/launch) each carrying an `MXCallStackTree` and `MXMetaData` |
| `.memgraph` | Captured object-graph snapshot (Mach-O corpse) analyzable off-line with `leaks`/`vmmap`/`malloc_history` |
| Malloc Stack Logging (MSL) | Scheme diagnostic that records allocation backtraces, required for `malloc_history`/heap tooling |

## Further reading

- Apple Developer — *Diagnosing issues using crash reports and device logs*; *Analyzing CPU usage with Processor Trace*; *Logging* (OSLog/`Logger`/privacy); **MetricKit** docs (`MXMetricManager`, `MXAppExitMetric`, `MXDiagnosticPayload`, `MXCallStackTree`); *Adding identifiable symbol names to a crash report* (dSYM/`atos`).
- WWDC — *Optimize CPU performance with Instruments* (WWDC25 308, Processor Trace/CPU Counters); *Optimize SwiftUI performance with Instruments* (WWDC25 306); *Profile and optimize power usage in your app* (WWDC25 226, the new Power Profiler + per-core CPU Profiler); the Xcode Organizer (Regressions/Hangs/Crashes/Disk Writes) for field metrics; the MetricKit/`os_signpost` sessions.
- `man` pages — `xctrace(1)`, `lldb(1)`, `log(1)`, `atos(1)`, `leaks(1)`, `vmmap(1)`, `malloc_history(1)`, `heap(1)`, `dwarfdump(1)`, `codesign(1)`, `devicectl`.
- The Apple Wiki — *Dev:Debugserver* (re-signing `debugserver`, the `task_for_pid-allow`/`springboard.debugapplications` entitlement set).
- libimobiledevice — `idevicecrashreport`, `idevicesyslog`; pymobiledevice3 (CoreDevice/RemoteXPC tunnel, `developer dvt` services) for scripted device debugging.
- Jonathan Levin, *MacOS and iOS Internals* — `task_for_pid`/Mach task ports, the exception/crash-report pipeline, `kdebug`/`kperf`; newosxbook.com.
- Researchers/writeups — Testableapple, *Debugging third-party iOS apps with lldb*; Ole Begemann, *OSLogStoreTest*; Ben Romano, *Creating Flame Graphs from Time Profiler Data*; Victor Wynne, *Apple's new Processor Trace instrument*; keith.github.io xcode-man-pages (`xctrace`).
- OWASP **MASTG** — "Dynamic Analysis on iOS" (lldb/`debugserver` setup, attaching to apps) as the RE counterpart to this builder-side lesson.

---
*Related lessons: [[01-simulator-internals-and-on-disk-filesystem]] | [[05-processes-mach-xpc]] | [[00-ios-xcode-and-the-build-system]] | [[05-dynamic-analysis-with-frida]] | [[12-unified-logs-sysdiagnose-crash-network]] | [[06-memory-jetsam-app-lifecycle]] | [[06-code-signing-and-provisioning-in-depth]]*
