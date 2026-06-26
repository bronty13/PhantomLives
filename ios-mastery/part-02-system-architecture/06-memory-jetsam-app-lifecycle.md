---
title: "Memory, jetsam & the app lifecycle"
part: "02 — System Architecture & Internals"
lesson: 06
est_time: "45 min read + 20 min labs"
prerequisites: [xnu-on-mobile, processes-mach-xpc]
tags: [ios, memory, jetsam, app-lifecycle, vm, forensics]
last_reviewed: 2026-06-26
---

# Memory, jetsam & the app lifecycle

> **In one sentence:** An iPhone has no swap file — XNU compresses inactive pages in RAM and, when that runs out, the in-kernel **memorystatus/jetsam** killer terminates apps by priority band rather than paging them to disk, and every kill it makes leaves a `JetsamEvent-*.ips` JSON report that doubles as a forensic timeline of which processes were resident, how big they were, and whether each was *frontmost* or *suspended* at the moment of death.

## Why this matters

You arrive from macOS with a comfortable mental model: free RAM gets backed by `swapfile`s in `/private/var/vm/`, the compressor smooths over pressure, and processes almost never die just because memory is tight. **None of that holds on an iPhone.** There is no swap. When pages can't be compressed fast enough, the kernel does not page out — it *kills whole processes*, foreground app protected, suspended background apps first. For a builder this is the difference between an app that survives backgrounding and one that gets silently jettisoned and "cold-launches" every time the user returns. For a forensicator it is gold: the kernel writes a structured JSON post-mortem (`bug_type` 298) for every memory-pressure kill, recording a full snapshot of resident processes, their memory footprints, and their **lifecycle state** at that instant. That snapshot tells you which app the user had in the foreground at a precise timestamp, which processes were merely suspended (their dirty pages — decrypted DB pages, draft text, keys — still resident until reclaimed), and it anchors a memory-pressure timeline you can correlate against `knowledgeC`/Biome, powerlog, and the unified log.

Both lenses converge on the same kernel subsystem — **memorystatus** — so this lesson teaches it once and reads it two ways: as the policy a developer must design *around* (footprint budgets, background survival, graceful response to pressure) and as the evidence trail a forensicator can read *off* (who was resident, in what state, and why each victim died). Get the mechanism right and both the engineering and the investigative payoffs follow.

## Concepts

### The XNU VM on a phone: compress, don't swap

iOS inherits the same XNU virtual-memory architecture as macOS — `vm_map`s, `vm_object`s, 16 KB pages on Apple Silicon (`pageSize = 16384`), copy-on-write, the works (see [[xnu-on-mobile]]). What differs is the **backing store of last resort**.

On macOS, when anonymous (non-file-backed) pages go cold, the **compressor** (`vm_compressor`, a WKdm-style in-RAM compressor) squeezes them; if pressure persists, the compressor segments themselves are written out to **swap files** (`/private/var/vm/swapfile0`, `swapfile1`, …) managed by the kernel's compressor-backed swap (the old userspace `dynamic_pager` is gone). RAM is effectively elastic, bounded by free disk.

On an **iPhone there is no swap file at all.** The compressor still runs — inactive anonymous pages are compressed in place into compressor segments — but there is **no second tier**: nothing is ever written to NAND as paging backing store. The reasons are deliberate:

- **Flash wear and latency.** Paging hammers the NAND with small random writes; the wear budget and the AES-XTS effaceable-storage design (see [[storage-nand-aes-effaceable]]) make a swap-on-flash policy unattractive on a pocket device.
- **Data-protection.** A swap file would spill decrypted page contents to disk outside the per-file Data Protection class model — a confidentiality hole the platform refuses to open.
- **Power and determinism.** Killing a backgrounded app is O(free its pages); paging it is sustained I/O. The platform optimizes for the foreground app's responsiveness, not for keeping forty background apps alive.

So the iPhone memory ladder has exactly two rungs: **resident** and **compressed-resident**. When both are exhausted, the only lever left is **eviction by process termination** — jetsam.

```
  macOS pressure ladder            iPhone pressure ladder
  ─────────────────────            ──────────────────────
  resident pages                   resident pages
     ↓ cold                           ↓ cold
  compressor (in RAM)              compressor (in RAM)
     ↓ pressure persists              ↓ pressure persists
  swapfile on disk  ← elastic      ── (no swap) ──
     ↓ extreme                        ↓
  jetsam (rare)                    JETSAM — kill a process  ← routine
```

The machinery that *feeds* that ladder is the same on both platforms: the **pageout scanner** (`vm_pageout`/`vm_pageout_scan` in `osfmk/vm/`) continuously ages pages across the **active → inactive → speculative** queues, looking for cold candidates. On the Mac the scanner's terminal move is "compress, then if needed swap"; on the iPhone the scanner can only compress, and when the inactive queue is drained and the compressor is full, the scanner has nothing left to do — so it wakes `memorystatus_jetsam_thread` and the kernel reclaims a *whole process's* pages in one stroke instead of dribbling individual pages to a backing store. "No swap" is therefore not a missing feature bolted off; it is the deliberate removal of the pageout scanner's second stage, with jetsam wired in as the replacement.

> 🖥️ **macOS contrast:** macOS *has* `memorystatus`/jetsam too — it is the same XNU subsystem — but on the Mac it is a last resort behind elastic swap, and most pressure is absorbed by the compressor + `swapfile`s plus App Nap and Sudden Termination. On iOS, `CONFIG_JETSAM` makes termination the *primary* pressure-relief mechanism, not the fallback. The Mac pages; the phone kills. You can watch the Mac's side directly with the `memory_pressure(1)` tool and `vm_stat`/`vmmap` — there is no `swapfile` to `ls` on an iPhone because the policy guarantees none exists.

#### The one exception: swap on M-series iPads

iPadOS broke the "no swap, ever" rule for one device class. Since **iPadOS 16**, iPads with an **M-series SoC** (M1 and later) and **≥128 GB** of storage enable a bounded **virtual-memory swap** — flash used as paging backing store, capped on the order of a handful of GB per app — specifically to give multi-window **Stage Manager** the address-space headroom desktop-class apps expect (see [[how-ipados-diverges-from-ios]]). The base 64 GB M1 iPad Air notably did *not* get it. This is the clearest signal that "no swap" was always a *product/wear* decision, not a kernel limitation: give the kernel a big SSD and a desktop multitasking model and Apple turns swap back on. An **iPhone 17 Pro never gets swap** regardless of RAM; an **iPad Pro M5** does.

### memorystatus & jetsam: the in-kernel OOM killer

Jetsam lives in the BSD half of XNU as the **`memorystatus`** subsystem (`bsd/kern/kern_memorystatus.c`, header `<sys/kern_memorystatus.h>`). At boot, with `CONFIG_JETSAM` defined, the kernel spins up a dedicated **`memorystatus_jetsam_thread`** that sleeps until woken by the pageout/pressure path and then runs a blocking loop: *while `memorystatus_available_pages <= memorystatus_available_pages_critical`, pick the lowest-value process and kill it.* It keeps killing until the free-page count climbs back above threshold.

"Lowest-value" is decided by **priority bands**, not Linux-style OOM scores. Jetsam-tracked processes are held in an array of buckets — `memstat_bucket`, one linked list per band (currently **21 bands**, indexed 0…20) — and the killer walks from the bottom (`JETSAM_PRIORITY_IDLE`, band 0) upward. Within a band the **least-recently-used** process dies first. The named constants come from `<sys/kern_memorystatus.h>`; the *names* are durable, the exact integers are XNU-version-specific, so treat the numbers below as the representative current ordering, not a contract:

| Band (constant) | ~Index | Who lives here | Jetsam treatment |
|---|---|---|---|
| `JETSAM_PRIORITY_IDLE` | 0 | **Backgrounded/suspended apps** (an app drops here when it leaves the foreground) | Killed **first**, LRU within the band |
| `JETSAM_PRIORITY_AGING_BAND*` | 1–2 | Recently-backgrounded apps "aging" toward idle | Killed early |
| `JETSAM_PRIORITY_BACKGROUND` | ~3 | Background-running tasks (e.g. an active `beginBackgroundTask`) | Killed after idle |
| `JETSAM_PRIORITY_MAIL` / `_PHONE` | ~4–5 | Specific privileged background apps | Protected vs. idle |
| `JETSAM_PRIORITY_FOREGROUND_SUPPORT` | ~9 | Processes serving the foreground app | High protection |
| `JETSAM_PRIORITY_FOREGROUND` | ~10 | **The visible foreground app** | Killed only as a last resort |
| `JETSAM_PRIORITY_AUDIO_AND_ACCESSORY` | ~12 | Now-playing audio, accessory daemons | Very protected |
| `JETSAM_PRIORITY_HOME` | ~16 | SpringBoard / the Home experience | Near-untouchable |
| `JETSAM_PRIORITY_IMPORTANT` / `_CRITICAL` | ~17–19 | Critical system daemons | Effectively never jetsam'd |

The mechanism that protects "the app you're looking at" is therefore not a special case in the killer — it is just **band placement**. The instant an app is foregrounded, SpringBoard/RunningBoard raises its jetsam priority to the foreground band; the instant it is backgrounded and suspended, its priority is dropped to `IDLE` (band 0) and it becomes the *first* candidate the killer reaches. That is the entire reason an iPhone "forgets" your background apps and Safari tabs reload: they were jettisoned out of band 0 to feed whatever you brought to the front.

> 🔬 **Forensics note:** Because band placement *is* the app's lifecycle state, a jetsam snapshot is a labelled record of who was foreground vs. suspended at time T. The per-process `states` array in the report (`frontmost`, `suspended`, `background`, `daemon`, `audio`, `bluetooth`, …) is the band's user-visible name. A `JetsamEvent` that shows app X with `states: ["frontmost"]` is positive evidence that X was the app on screen at that timestamp — independent of, and corroborating, `knowledgeC`/`/app/inFocus` and Biome (see [[knowledgec-db-deep-dive]]).

### The per-process memory limit (`os_proc_available_memory`)

Pressure-driven jetsam (`vm-pageshortage`) is only half the story. Every process *also* carries an individual **memory limit** ("memlimit" / high-water mark). Cross it and you are killed immediately with reason **`per-process-limit`** — even if the *system* has plenty of free RAM. This is why a single leaking app dies on a 12 GB phone that is 80 % idle.

Two limits per process, switched by state:

- an **active** (foreground) limit, and
- an **inactive** (background) limit, which is lower.

The caps scale with device RAM but sit far below total RAM — a foreground app gets a generous fraction (historically reported in the ~1.4 GB range on a 3 GB device, larger on newer hardware; the exact MB-per-device-class figures drift every release, so **read the live value at runtime rather than hardcoding**). App **extensions** (share sheet, widgets, notification-service) get a *much* lower cap than the host app — frequently a small fraction — which is why `per-process-limit` kills disproportionately hit extensions.

The supported, durable way to read your current headroom is the API, not a table:

```c
#include <os/proc.h>
size_t avail = os_proc_available_memory();   // bytes the current app may still allocate
```

Two entitlements raise the ceiling for genuinely memory-hungry apps: **`com.apple.developer.kernel.increased-memory-limit`** (a higher per-process cap on supported devices) and **`com.apple.developer.kernel.extended-virtual-addressing`** (a larger virtual address space). Both are visible in a binary's entitlement blob and are a useful tell during reverse-engineering that an app expects to hold large media/ML working sets (see [[the-code-signature-blob-and-entitlements-on-ios]]).

The caps roughly track physical RAM but never approach it — historically a foreground app on a device got somewhere between a third and a half of total RAM before `per-process-limit`. The figures below are **reported community measurements, not Apple-published constants, and drift every release** — treat them as the *shape* of the policy and read the live value with `os_proc_available_memory()` rather than quoting them as fact:

| Device RAM | ~Foreground app cap (reported) | Notes |
|---|---|---|
| 2 GB | ~1.1–1.4 GB | extensions far lower |
| 3 GB | ~1.4–1.8 GB | |
| 4 GB | ~2.0–2.2 GB | |
| 6 GB | ~2.7–3.5 GB | `increased-memory-limit` pushes higher |
| 8 GB+ (A17/A18/A19, iPhone 15 Pro→17 Pro) | larger still, hardware-dependent | ML/camera apps lean on the entitlements |

The reason a single leak kills an app on a 12 GB phone that is 80 % idle is exactly this: the per-process limit fires on *your* footprint, blind to system-wide headroom.

> 🖥️ **macOS contrast:** A Mac process has effectively no comparable hard footprint cap — it grows until it exhausts address space or the system swaps. The iOS per-process limit is closer in spirit to a cgroup memory limit on Linux than to anything in default macOS. On the Mac you inspect a process's footprint with `footprint(1)` and `vmmap(1)`; on iOS the equivalent introspection is `os_proc_available_memory()` plus Instruments' Allocations/Leaks and `task_info(TASK_VM_INFO)` → `phys_footprint`.

### Coalitions: an app and its helpers are accounted together

A jetsam report's `coalition` field is not decoration — it reflects how XNU *groups* a foreground app with the daemons and extensions doing work on its behalf. A **coalition** is a kernel construct (`task_coalition`) that bundles related tasks for resource accounting and jetsam decisions: your app, the XPC services it launched, the media/`mediaserverd` work it triggered, a running app extension. Memory and CPU charged to those helpers can be attributed back to the host, and jetsam can act on the coalition as a unit so that killing a host app also reaps the helpers it spawned (and, conversely, so a "free" daemon working only for a foreground app inherits some of that app's protection). For a forensicator the `coalition` id is a **join key**: two `processes` entries sharing a coalition number were cooperating — a messaging app and its notification-service extension, a camera app and an encoding daemon — which lets you reconstruct *functional groupings* from a flat process list, and explains why a memory spike attributed to a daemon may really be the foreground app's doing.

### The app lifecycle: who drives the state machine

From the kernel's view an app is just a process, but from the *platform's* view it moves through a state machine that directly controls its jetsam band. The states (UIKit `UIApplication.State` / SwiftUI `ScenePhase`):

```
   ┌─────────────┐   launch    ┌──────────┐  user opens  ┌────────┐
   │ Not running │ ──────────► │ Inactive │ ───────────► │ Active │  ← foreground, band ~10
   └─────────────┘             └──────────┘              └────────┘
         ▲                          ▲ │                      │
         │ jetsam / user-quit       │ │ resign               │ home/switch
         │                          │ ▼                      ▼
   ┌─────────────┐  reclaim   ┌──────────────┐  ~seconds ┌────────────┐
   │ Terminated  │ ◄───────── │  Suspended   │ ◄──────── │ Background │  band ~3
   │ (no memory) │   jetsam   │ (band 0 IDLE,│           │ (running   │
   └─────────────┘            │ dirty pages  │           │  briefly)  │
                              │  resident)   │           └────────────┘
                              └──────────────┘
```

The choreography is done by userspace, not the kernel:

- **SpringBoard** (`backboardd` for events/display, `frontboardd` for foreground app management) decides which app is frontmost and tells the system.
- **RunningBoard** (`runningboardd`, since iOS 13 — it replaced `assertiond`) is the **process-lifecycle authority**: it holds *assertions* about every process (why it's allowed to run, at what priority) and translates foreground/background transitions into the actual **jetsam priority** and CPU/scheduling state. When the last assertion keeping a process awake is released, RunningBoard tells the kernel to **suspend** it (SIGSTOP-like: still in memory, executing no code) and lowers its band to `IDLE`.
- When you background an app, you get a short grace window (`applicationDidEnterBackground` / `scenePhase == .background`) to flush state. Need more than the instant? **`beginBackgroundTask(expirationHandler:)`** buys ~30 seconds at a slightly protected band; overrun the expiration handler without calling `endBackgroundTask` and the **watchdog** kills you with exception code **`0x8badf00d`** ("ate bad food"). Real deferred work uses **`BGTaskScheduler`** (`BGAppRefreshTask` / `BGProcessingTask`), scheduled by the system opportunistically — see [[app-lifecycle-scenes-and-background-execution]].

> 🔬 **Forensics note — evidence freshness by state.** *Which state an app is in determines what evidence still exists.* A **suspended** app keeps **all its dirty memory resident** — decrypted SQLite pages, in-progress message drafts, decrypted media thumbnails, even key material — because suspension is "frozen, not freed." That volatile state is recoverable only by **live/RAM acquisition** while the device is AFU (e.g. a checkm8-class RAM dump on an A8–A11 device). The moment jetsam moves the app to **terminated**, those pages are reclaimed and gone. And after the **72-hour inactivity reboot** drops the device to **BFU**, all such volatile state — plus the Data-Protection class-A/B keys — is evicted from memory entirely (see [[passcode-bfu-afu-and-inactivity]]). So "is the app suspended or terminated, and is the device AFU or BFU?" is the first question that bounds what a live acquisition can even hope to recover.

#### Prewarming and state restoration — why jetsam is invisible to the user

The platform works hard to *hide* termination. Two mechanisms:

- **Prewarming.** The system may execute an app's launch sequence — dyld load, static/`+load` initializers, up to (but *not* including) `main()`'s call to `UIApplicationMain` (on scene-based apps `didFinishLaunching` may also run, though no scene/UI is created) — *before the user taps it*, based on patterns of life (likely the same `routined`/Biome signals that feed Siri suggestions), so the perceived launch is instant. A prewarmed app sits at a low band until actually foregrounded. This is why an app's process can appear in a jetsam snapshot, or in `knowledgeC`, at a time the user did not visibly open it — *launch ≠ user interaction*, a distinction that matters when attributing activity to a person.
- **State restoration.** When jetsam reaps a backgrounded app and the user returns, UIKit/SwiftUI replays a persisted **scene-state archive** so the UI reappears where it was — the user sees "the app was still open," not "the app was killed and cold-launched." That archive (UIKit state-restoration data; SwiftUI `@SceneStorage`/`NSUserActivity`) is written **inside the app's sandbox container** and survives the termination by design.

> 🔬 **Forensics note:** The state-restoration archive is a recoverable artifact of *what the user was last looking at* in an app — the open document, the selected tab, the scroll position, the in-progress compose screen — frozen at the last backgrounding even though the process is long dead. It lives under the app's `Library/` in its data container (verify the exact subpath per app/OS version against your image; see [[app-sandbox-and-filesystem-layout]]). Where the volatile in-memory state died with the jetsam kill, this on-disk shadow of the last UI state often persists.

### Memory-pressure signalling (how an app finds out)

Before jetsam reaches an app, the system *asks nicely*. Three notification paths, all backed by the same kernel `EVFILT_VM` / `NOTE_VM_PRESSURE` knote and the `kern.memorystatus_vm_pressure_level` sysctl (1 = normal, 2 = warn, 4 = critical):

| Path | API | What you do |
|---|---|---|
| UIKit | `applicationDidReceiveMemoryWarning` / `UIApplication.didReceiveMemoryWarningNotification` | Drop caches, free images |
| GCD | `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` dispatch source (`DISPATCH_MEMORYPRESSURE_WARN` / `_CRITICAL`) | Framework-level eviction (the supported low-level hook) |
| sysctl | read `kern.memorystatus_vm_pressure_level` | Poll the current level |

An app that frees enough on `warn` may never be reached by the killer; an app that ignores the warning and keeps growing crosses its per-process limit or feeds a `vm-pageshortage` kill. The `URLCache`, image decoders, and `NSCache` all subscribe to the dispatch source and purge automatically — which is why your own caches should too.

### The `JetsamEvent-*.ips` report — the artifact

Every memory-pressure termination produces a **jetsam event report**: a JSON document, **`bug_type` 298**, named `JetsamEvent-YYYY-MM-DD-HHMMSS.ips` (rotated copies pick up a `.synced` suffix once uploaded to Apple's analytics). It is **not** a crash report — there are no thread backtraces. Instead it is a **whole-system memory snapshot at the instant of the kill**: every resident process, its footprint, its lifecycle state, and — for the one process that was actually jettisoned — *why*.

**Where it lives.** On the device these surface in *Settings → Privacy & Security → Analytics & Improvements → Analytics Data* (scroll to `JetsamEvent-…`). In a full-filesystem extraction or sysdiagnose they are under the CrashReporter log tree, canonically **`/private/var/mobile/Library/Logs/CrashReporter/`** (with rotated/older reports moved into a `Retired/` subfolder, and a `.synced` copy once sent to Apple). The exact rotation subpath shifts between iOS releases — **verify the precise subfolder against your image** rather than assuming. You pull them off a live (AFU, trusted) device over the lockdown **CrashReporter** service with `idevicecrashreport` (libimobiledevice) or `pymobiledevice3 crash pull` — see Hands-on.

**Header / `memoryStatus` fields:**

| Field | Meaning |
|---|---|
| `bug_type` | `298` for a jetsam event (vs `309`/`109` for a crash report, or `142` for a CPU/wakeups resource report) — filter on `bug_type` first |
| `timestamp` / `date` | Wall-clock of the event (mind the timezone offset in the string) |
| `os_version` / `build` / `product` | OS build and hardware model (`iPhone18,1`, …) |
| `pageSize` | Bytes per page — **16384** on Apple Silicon; the multiplier for every `rpages` |
| `largestProcess` | Name of the single biggest memory consumer system-wide at kill time |
| `memoryStatus.compressorSize`, `compressions`, `decompressions` | Compressor activity — how hard the no-swap compressor was working |
| `memoryStatus.memoryPages.{free,active,inactive,wired,anonymous,purgeable,fileBacked,throttled,speculative}` | The system-wide page census at the instant of the kill |
| `genCounter` / `genCount` | Snapshot generation counter |

**Per-process entries** (`processes` array — one object per resident process):

| Field | Meaning |
|---|---|
| `pid`, `name`, `uuid` | Process id, executable name, **binary build UUID** (matches a dSYM / a Mach-O `LC_UUID`) |
| `rpages` | **Resident pages** — `rpages × pageSize` = bytes resident. A `rpages` of 92802 × 16384 ≈ **1.52 GB** |
| `lifetimeMax` | Peak resident pages over the process's lifetime |
| `states` | Lifecycle/band labels: `frontmost`, `suspended`, `background`, `daemon`, `audio`, `bluetooth`, `resume`, … |
| `purgeable` | Purgeable pages it was holding |
| `fds` | Open file descriptors (relevant to `vnode-limit` kills) |
| `coalition` | Coalition id grouping a host app with the daemons working on its behalf |
| `cpuTime`, `age` | CPU seconds consumed and process age |
| `reason` | **Present only on the jettisoned process** — *why it died* |

**`reason` values** (the verdict) — Apple documents these exactly:

| `reason` | What it means |
|---|---|
| `per-process-limit` | Crossed its own resident-memory cap (extensions hit this far sooner than apps) |
| `vm-pageshortage` | System-wide pressure; a background process killed to feed the foreground app |
| `vnode-limit` | System ran out of vnodes (too many open files) — a background app sacrificed to free them |
| `highwater` | A system **daemon** exceeded its high-water-mark footprint |
| `fc-thrashing` | A process was thrashing the file cache with non-sequential mmap'd reads/writes |
| `jettisoned` | Some other jetsam reason |

Reading a report is therefore: (1) header → `pageSize` + `largestProcess`; (2) scan `processes` for the **one** object with a `reason` key — that is the victim, and the reason is the cause of death; (3) for everyone else, read `states` + `rpages` to reconstruct *who else was resident and in what state* at that timestamp.

**A report, end to end.** Stripped to the load-bearing fields, a real event reads like this:

```jsonc
{
  "bug_type"   : "298",
  "timestamp"  : "2026-06-20 09:02:10.42 +0100",   // normalize the +0100 to UTC first
  "os_version" : "iPhone OS 26.5 (23F...)",
  "product"    : "iPhone18,1",                       // iPhone 17 Pro
  "memoryStatus": {
     "pageSize"     : 16384,
     "compressions" : 18244213,                      // compressor working hard — no swap behind it
     "memoryPages"  : { "free": 9211, "active": 220140, "inactive": 71033, "wired": 154002 }
  },
  "largestProcess" : "Photos",                        // biggest ≠ the victim
  "processes": [
     { "name":"SpringBoard", "pid":61,  "states":["daemon"],    "rpages":51200 },
     { "name":"Photos",      "pid":914, "states":["frontmost"], "rpages":92802 },   // on screen now
     { "name":"Signal",      "pid":803, "states":["suspended"], "rpages":40110 },   // dirty pages still resident
     { "name":"mediaserverd","pid":102, "states":["daemon"],    "rpages":33001, "coalition":914 },
     { "name":"WhatsApp",    "pid":771, "states":["suspended"], "rpages":61920,
       "reason":"vm-pageshortage" }                   // ← THE VICTIM: sacrificed to feed Photos
  ]
}
```

Verdict: under system-wide pressure (`vm-pageshortage`, *not* a per-process overrun) the kernel killed the **suspended** background `WhatsApp` (band `IDLE`) to free pages for the **frontmost** `Photos` — even though `Photos` was `largestProcess`. The snapshot simultaneously tells you `Signal` was *suspended but still resident* at 09:02:10 (its decrypted pages were in RAM and would have been recoverable by an AFU live capture), and that `mediaserverd` was in `Photos`'s coalition (914) — i.e. doing media work *for* Photos.

> 🔬 **Forensics note — the jetsam timeline.** A device accrues many `JetsamEvent-*.ips` over its life. Parsed in bulk they become a **memory-pressure timeline**: each file is a timestamped snapshot of the working set. Because each snapshot tags every process with a `states` array, you can answer "what was the user actively doing at 02:01 on the 25th?" — the `frontmost` process names it — and "was a high-value app (an encrypted messenger, a camera/recording app) resident and suspended (so its decrypted pages were still in RAM) at that moment?" These reports are **system-level, not app-controlled**: an app cannot suppress its own appearance in another process's jetsam snapshot, which makes them harder to tamper with than app-private logs. Cross-reference them with the unified log's `Jetsam`/`memorystatus` messages ([[unified-logging-and-sysdiagnose]]), powerlog, and `knowledgeC`/Biome to corroborate foreground attribution.

> 🔬 **Forensics note — know the artifact's limits.** A `JetsamEvent` is **sampled only at a kill**, not continuously: it proves the state of the world at the instants memory pressure forced a termination, and says nothing about the long stretches where memory was comfortable. Quiet periods leave *no* jetsam evidence — absence of a report is not evidence the app was closed. The store is also **prunable**: it rotates (old reports age into `Retired/` and are eventually discarded), the user can delete entries from *Analytics Data*, and a wipe clears it — so a suspiciously empty CrashReporter store on a heavily-used device is itself an indicator. And the timestamps are wall-clock from a clock the user can change; corroborate against monotonic sources (boot session, mach-continuous-time deltas) before relying on a jetsam timeline in a contested matter (see [[the-ios-timestamp-zoo]]).

> ⚖️ **Authorization:** `JetsamEvent` reports and the device's broader CrashReporter store are user/device data. Pull them only under lawful authority and your acquisition SOP — over the CrashReporter lockdown service they require a **trusted (paired, AFU)** device, and the act of pairing/trusting is itself a documented step in the chain of custody (see [[ios-forensics-landscape-and-authorization]]).

### MetricKit & app-exit reasons — the aggregated, modern signal

`JetsamEvent` is the *kernel's* record. **MetricKit** (`MXMetricManager`, the `MetricKit` framework) is the *app-facing* counterpart: once a day the system hands a registered app a payload summarizing the prior 24 h, including an **app-exit census** (`MXAppExitMetric` → `MXBackgroundExitData` / `MXForegroundExitData`) that buckets every way the app terminated. The bucket names map almost one-to-one onto the jetsam world and are durable, documented constants worth knowing:

| MetricKit exit counter | Corresponds to |
|---|---|
| `cumulativeMemoryResourceLimitExitCount` | a `per-process-limit` jetsam kill — the app overran its footprint cap |
| `cumulativeMemoryPressureExitCount` | a `vm-pageshortage` jetsam kill under system pressure |
| `cumulativeBadAccessExitCount` | a real crash (`EXC_BAD_ACCESS`) — *not* a memory-pressure kill |
| `cumulativeAppWatchdogExitCount` | the `0x8badf00d` watchdog (e.g. a blown `beginBackgroundTask` deadline) |
| `cumulativeNormalAppExitCount` | clean, user-initiated termination |

The same data is reachable at runtime without MetricKit through `task_info(TASK_VM_INFO)` and the `ProcessInfo`/exit-reason machinery. For a builder this is the supported way to *quantify* jetsam pain in the field. For a forensic/RE practitioner, MetricKit's persisted diagnostic payloads (and any analytics an app ships from them) are an **app-private** corroborator of the system-level `JetsamEvent` store: when the device-wide CrashReporter store has been cleared, an app's own MetricKit history may still betray a string of memory-pressure exits at a given time.

## Hands-on

> There is **no on-device shell**. Everything below runs on the Mac: against the Simulator, against a sample `.ips` file, against a *trusted* device over USB via the libimobiledevice/pymobiledevice3 family, or against the Mac's own memorystatus as a contrast.

### Drive an app's lifecycle on the Simulator and watch the states

```bash
# Boot a simulator and stream a target app's lifecycle/log
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl launch --console-pty booted com.example.MyApp
# In another shell, watch lifecycle + memory-warning chatter:
xcrun simctl spawn booted log stream --level debug \
  --predicate 'process == "MyApp" AND (eventMessage CONTAINS[c] "memory" OR eventMessage CONTAINS[c] "background")'
```

Background the app (Simulator → press Home, ⇧⌘H) and you'll see the `applicationDidEnterBackground` path fire; foreground it and `applicationDidBecomeActive`. Trigger a low-memory warning from the **Simulator → Device → "Simulate Memory Warning"** menu and watch `didReceiveMemoryWarning` arrive.

### Parse a `JetsamEvent-*.ips` with `jq`

```bash
# Header: page size + biggest process
jq '{model: .product, build: .build, pageSize: .memoryStatus.pageSize, largest: .largestProcess}' JetsamEvent-2026-06-20-090210.ips

# The victim: the ONE process with a reason, plus its footprint in MB
jq '.processes[] | select(.reason != null)
    | {name, reason, states, rpages, MB: (.rpages * 16384 / 1048576 | floor)}' \
   JetsamEvent-2026-06-20-090210.ips

# Everyone resident, sorted by footprint, with their lifecycle state
jq -r '.processes | sort_by(-.rpages)[]
    | "\(.rpages*16384/1048576|floor)MB  \(.states|join(","))  \(.name)"' \
   JetsamEvent-2026-06-20-090210.ips | head -20
```

Expected shape: one line tagged `per-process-limit` or `vm-pageshortage`, and a footprint table where `largestProcess` sits at the top and whichever app shows `frontmost` was on screen.

To turn a directory of reports into a timeline in one pass — deduplicating each report against its `.synced` twin and emitting `timestamp, frontmost, victim, reason` per event:

```bash
for f in JetsamEvent-*.ips; do
  jq -r --arg f "$f" '
    [ $f, .timestamp,
      ( [.processes[] | select(.states|index("frontmost")) | .name][0] // "?" ),
      ( [.processes[] | select(.reason!=null) | "\(.name)/\(.reason)"][0] // "?" )
    ] | @tsv' "$f"
done | sort -t$'\t' -k2 | awk '!seen[$2,$3,$4]++'
```

The trailing `awk` collapses a report and its uploaded `.synced` duplicate (same timestamp/victim) into one row, so the count of *events* isn't inflated by the count of *files*.

### Pull crash & jetsam logs off a *trusted* device (acquisition path)

```bash
# libimobiledevice — copies the CrashReporter store off a paired/trusted device
idevicecrashreport -e -k ./crashlogs_pull/
#   -e  also pull (don't delete) the "extra" / retired reports
#   -k  keep the on-device copies (do NOT clear them — forensic non-destruction)
ls ./crashlogs_pull/ | grep -i Jetsam

# pymobiledevice3 equivalent (richer, scriptable)
pymobiledevice3 crash ls | grep -i Jetsam
pymobiledevice3 crash pull ./crashlogs_pull/
```

> ⚠️ **ADVANCED:** `idevicecrashreport` without `-k` will **clear** the reports from the device after copying — destructive to the original evidence and a chain-of-custody violation. Always pass `-k`, and prefer pulling crash logs as part of a full logical/file-system acquisition (see [[logical-acquisition-with-libimobiledevice]]) so the store is captured *in situ*, not piecemeal.

### macOS contrast: watch memorystatus on the Mac you're sitting at

```bash
# Apply synthetic memory pressure and watch the SAME XNU subsystem respond
sudo memory_pressure -l warn -S       # -l warn|critical; -S = simulate the level (no real alloc), ^C to stop (or add -s N for an N-second hold)
vm_stat 1                              # live page census: free/active/inactive/compressed
footprint -p <pid>                     # phys_footprint of a process (the iOS "rpages" analogue)
vmmap --summary <pid>                  # dirty/swapped/compressed breakdown
log show --last 1h --predicate 'eventMessage CONTAINS "memorystatus" OR eventMessage CONTAINS "jetsam"'
```

On the Mac you'll see the compressor and **swap** absorb the pressure (`sysctl vm.swapusage` shows the swapfile growing); on a phone that swap row would stay empty and a process would die instead.

### Find jetsam evidence inside a sysdiagnose

A device sysdiagnose (triggered on-device, then offloaded to the Mac — see [[unified-logging-and-sysdiagnose]]) bundles the jetsam picture three ways:

```bash
# 1) The raw reports, alongside panics and spins
find sysdiagnose_*/ -path '*crashes_and_spins*' -iname 'JetsamEvent-*.ips'

# 2) The kernel's own narration in the unified log (export the logarchive, then query)
log show --archive sysdiagnose_*/system_logs.logarchive \
  --predicate 'eventMessage CONTAINS "memorystatus" OR eventMessage CONTAINS "jetsam" OR eventMessage CONTAINS "kill"' \
  --info | grep -iE 'jetsam|memorystatus|pageshortage|per-process'

# 3) A live pressure-level read mirrors the device sysctl namespace
#    (on the Mac, the contrast): kern.memorystatus_vm_pressure_level → 1/2/4
sysctl kern.memorystatus_vm_pressure_level
```

The `.ips` files give you the *snapshot at each kill*; the logarchive gives you the *narration between kills* (pressure-level transitions, which process was foregrounded, when the killer woke). Together they reconstruct the memory-pressure story at higher resolution than either alone. Xcode's **Organizer → Reports** surfaces the same jetsam metrics for apps you sign, aggregated from MetricKit — the developer-side view of the same events.

## 🧪 Labs

### Lab 1 — App lifecycle + memory warning (substrate: **Xcode Simulator**)

**Fidelity caveat:** the Simulator runs **macOS** frameworks and **macOS memorystatus** — it does **not** run iOS `CONFIG_JETSAM`. There are **no real per-process limits, no jetsam kills, and no `JetsamEvent-*.ips` is ever produced.** "Simulate Memory Warning" delivers only the `didReceiveMemoryWarning` *callback*; nothing is actually reclaimed and your app cannot be jettisoned. This lab teaches the **lifecycle state machine and notification plumbing**, not the killer.

1. Create a minimal app that logs every lifecycle transition (`scenePhase` changes / `UIApplication` notifications) and prints `os_proc_available_memory()` on each.
2. `xcrun simctl launch --console-pty booted <bundleid>` and exercise: foreground → Home → re-foreground. Capture the transition order.
3. Fire **Device → Simulate Memory Warning** and confirm `didReceiveMemoryWarning` logs.
4. Note the value `os_proc_available_memory()` returns — it reflects the **Mac's** free memory, not a device cap. Write down *why* that number is untrustworthy as a device-limit proxy.

### Lab 2 — Read a real jetsam report (substrate: **public sample `.ips`**)

Grab a real `JetsamEvent-*.ips` from a public iOS reference image (Josh Hickman / Digital Corpora) or a public crash-log repository.

1. With the `jq` recipes above, extract `pageSize`, `largestProcess`, and the single process carrying a `reason`.
2. Compute the victim's footprint (`rpages × pageSize`) in MB and classify the kill (`per-process-limit` = it overran its own cap; `vm-pageshortage` = it was sacrificed for the foreground app).
3. List every process whose `states` includes `frontmost` (usually one) — that names the app the user had on screen at the report's timestamp.
4. Produce a one-row-per-process table sorted by `rpages`. Which processes were merely `suspended` (dirty pages still resident)? Note that those are exactly the processes a live/AFU RAM acquisition could still have recovered decrypted state from.

### Lab 3 — Build a jetsam timeline (substrate: **public sample full-filesystem image**, read-only walkthrough)

Against a public iOS file-system image, locate the CrashReporter tree (`/private/var/mobile/Library/Logs/CrashReporter/`, plus any `Retired/` subfolder — **verify the path on your image**) and enumerate all `JetsamEvent-*.ips`.

1. `find . -iname 'JetsamEvent-*.ips'` and loop the Lab-2 `jq` over each, emitting `timestamp, frontmost_app, victim, victim_reason` per file.
2. Sort by timestamp into a memory-pressure timeline. Where do clusters of events fall (heavy multitasking, a camera/recording session, an OS update)?
3. Cross-reference the `frontmost` attribution against `knowledgeC`/Biome `/app/inFocus` for the same timestamps ([[knowledgec-db-deep-dive]], [[biome-and-segb-streams]]). Do they agree? Disagreements are worth chasing.
4. **Why device-only:** the Simulator never generates these. This is a sample-image-only artifact; an examiner gets it from a real file-system extraction or sysdiagnose, not from CoreSimulator.

### Lab 4 — The macOS mirror (substrate: **your Mac**, contrast)

1. In one terminal: `vm_stat 1` and `watch -n1 'sysctl vm.swapusage'`.
2. In another: `sudo memory_pressure -l critical -S` for ~30 s, then ^C.
3. Watch the **compressed** page count climb and the **swapfile grow** — the exact two-tier behavior an iPhone refuses to do. Articulate, in one paragraph, what the phone would have done instead at the moment your Mac started swapping (answer: terminated the lowest-band process and written a `JetsamEvent`).

## Pitfalls & gotchas

- **"It crashed" ≠ it crashed.** A foreground app jettisoned for memory looks identical to a crash to the user, but there is **no crash report and no backtrace** — only a `JetsamEvent` (`bug_type` 298) where *your* process carries the `reason` key. If you're hunting a "crash" and find no `.ips` crash log but do find a jetsam report naming your app with `per-process-limit`, the bug is memory, not a signal.
- **Don't trust the Simulator for memory behavior.** No jetsam, no real limits, `os_proc_available_memory()` returns Mac numbers. Memory-limit and OOM behavior must be validated on hardware or reasoned from sample images — the Simulator teaches *structure*, not *pressure* (a recurring theme of this course; see [[simulator-internals-and-on-disk-filesystem]]).
- **Extensions die where apps survive.** App extensions run under a **much** lower per-process cap. A photo-editing share extension that loads a full-res `MKMapView` or `SpriteKit` scene will hit `per-process-limit` on inputs the host app handles fine.
- **`beginBackgroundTask` is not "keep running."** It's ~30 s of grace. Forget `endBackgroundTask` and the watchdog kills you `0x8badf00d`; that, too, is a *termination*, distinct from a jetsam memory kill — don't conflate the two when triaging an `.ips`.
- **The timezone is in the string.** `JetsamEvent` `date`/`timestamp` fields carry an explicit UTC offset (e.g. `+0900`). Normalize to UTC before building a timeline, or you'll mis-order events across a DST change or a travelling device (see [[the-ios-timestamp-zoo]]).
- **`.synced` ≠ a second event.** A report and its `.synced` twin are the *same* event; the suffix only means it was uploaded to Apple analytics. Don't double-count.
- **Don't `idevicecrashreport` without `-k`.** The default flushes the on-device store. On evidence, that is destruction. Capture crash logs as part of an in-situ file-system acquisition.
- **`largestProcess` is a hint, not the victim.** The biggest process is often *not* the one killed (the killer protects the foreground band even if it's the largest). The victim is whoever holds the `reason` key — which may be a small suspended background app sacrificed under `vm-pageshortage`.
- **Page size is 16 KB, not 4 KB.** Apple Silicon uses 16384-byte pages. A reflex `rpages × 4096` from x86 muscle memory undercounts every footprint by 4×. Always read `pageSize` from the report header rather than assuming.
- **A jetsam kill is not a panic.** Jetsam terminating one process is normal housekeeping; a *kernel panic* (a separate `.ips`, distinct `bug_type`, with a panic string and backtrace) is a crash of XNU itself. They share the CrashReporter store and the `.ips` extension but answer completely different questions — filter by `bug_type` first.
- **The Simulator can't validate "survives backgrounding."** Because CoreSimulator never jetsams, an app that leaks into the background looks fine in the Simulator and gets reaped on a real phone. State-restoration and background-survival behavior is a hardware-or-sample-image question, never a Simulator one.

## Key takeaways

- **iPhones have no swap file.** XNU compresses inactive pages in RAM; when that's exhausted there is no disk backing store, so the only relief is **terminating processes** — `memorystatus`/jetsam. M-series iPads (≥128 GB, iPadOS 16+) are the one class that re-enables a bounded NAND swap, for Stage Manager.
- **Jetsam kills by priority band, LRU within a band.** Foregrounding raises an app to the foreground band; backgrounding+suspending drops it to `IDLE` (band 0), making it the **first** thing killed under pressure. The foreground app is protected by *band placement*, not a special case.
- **Two kill triggers:** system-wide `vm-pageshortage` (free pages below critical) and per-process `per-process-limit` (an app/extension overran its own footprint cap). Read live headroom with `os_proc_available_memory()`; `increased-memory-limit`/`extended-virtual-addressing` entitlements raise the ceiling.
- **The lifecycle is driven in userspace** by SpringBoard (`backboardd`/`frontboardd`) and **RunningBoard** (`runningboardd`), which translate foreground/background transitions into the kernel's jetsam priority and suspend/resume state.
- **`JetsamEvent-*.ips` (`bug_type` 298) is a whole-system memory snapshot**, not a crash report: `pageSize`, `largestProcess`, a `memoryStatus` page census, and a `processes` array tagging every resident process with `rpages` and a lifecycle `states` array — with a `reason` only on the one jettisoned process.
- **Forensically, the `states` field is foreground attribution** independent of `knowledgeC`/Biome, and the suspended-vs-terminated distinction bounds **evidence freshness**: suspended apps keep decrypted dirty pages resident (recoverable by AFU RAM acquisition) until jetsam or the 72 h BFU reboot reclaims them.
- **Parsed in bulk, jetsam reports are a memory-pressure timeline** — system-generated, app-untamperable, cross-correlatable with the unified log, powerlog, and pattern-of-life stores — but sampled only at kills, prunable, and stamped with a user-settable clock, so corroborate before relying on them.
- **The platform hides termination** with prewarming (launch ≠ user interaction) and on-disk **state restoration** (a recoverable shadow of the last UI), while **MetricKit** keeps an app-private exit census that corroborates the kernel's `JetsamEvent` store.

## Terms introduced

| Term | Definition |
|---|---|
| `memorystatus` | The XNU BSD subsystem that tracks per-process memory and enforces memory policy; home of jetsam (`bsd/kern/kern_memorystatus.c`) |
| jetsam | iOS's in-kernel OOM killer: terminates processes by priority band under memory pressure (`memorystatus_jetsam_thread`) |
| `CONFIG_JETSAM` | XNU build flag that makes termination the primary pressure-relief mechanism (set on iOS; jetsam exists but is a last resort on macOS) |
| priority band | One of ~21 `memstat_bucket` linked lists; jetsam kills from the lowest band (`JETSAM_PRIORITY_IDLE`) upward, LRU within a band |
| `JETSAM_PRIORITY_IDLE` | Band 0, where suspended/background apps land — killed first |
| `JETSAM_PRIORITY_FOREGROUND` | The high band the visible app occupies — killed only as a last resort |
| memory compression | XNU `vm_compressor` squeezing cold anonymous pages in RAM; on iPhone it is the *only* tier (no swap underneath) |
| pageout scanner | `vm_pageout_scan` — ages pages across active/inactive/speculative queues; on iOS its terminal stage is compress-or-jetsam (no swap) |
| coalition | Kernel `task_coalition` grouping a host app with its helper tasks for shared resource accounting and jetsam decisions; the `coalition` id is a forensic join key |
| MetricKit / `MXAppExitMetric` | App-facing daily metrics framework whose exit census (`cumulativeMemoryResourceLimitExitCount`, `cumulativeMemoryPressureExitCount`, `cumulativeAppWatchdogExitCount`, …) is the app-private counterpart to `JetsamEvent` |
| swap (iPadOS) | NAND-backed paging enabled only on M-series iPads (≥128 GB, iPadOS 16+) for Stage Manager headroom; never on iPhone |
| per-process limit | The individual resident-memory cap ("memlimit"/high-water mark); crossing it triggers a `per-process-limit` kill regardless of system free memory |
| `os_proc_available_memory()` | API returning bytes the current app may still allocate before hitting its cap |
| RunningBoard (`runningboardd`) | The process-lifecycle authority (since iOS 13) that holds run assertions and sets jetsam priority + suspend/resume state |
| SpringBoard | The shell (`backboardd`/`frontboardd`) that determines the frontmost app and drives foreground/background transitions |
| suspended | App frozen in memory, executing no code, band `IDLE`; its dirty pages stay resident until reclaimed |
| `beginBackgroundTask` | UIKit call buying ~30 s of background grace; overrunning it triggers the `0x8badf00d` watchdog kill |
| `JetsamEvent-*.ips` | JSON memory-pressure report (`bug_type` 298): system page census + per-process snapshot with `rpages`, `states`, and a `reason` on the victim |
| `rpages` | Resident pages in a jetsam report; `rpages × pageSize` (16384) = bytes resident |
| `reason` (jetsam) | Cause-of-death on the jettisoned process: `per-process-limit`, `vm-pageshortage`, `vnode-limit`, `highwater`, `fc-thrashing`, `jettisoned` |
| `largestProcess` | Report field naming the single biggest memory consumer at kill time (not necessarily the victim) |
| `0x8badf00d` | Watchdog termination exit code ("ate bad food") — e.g. an overrun `beginBackgroundTask` deadline; a kill distinct from a jetsam memory event |
| prewarming | System-initiated early launch of an app (its launch sequence runs up to `main()`'s `UIApplicationMain`, before any user-visible UI) before the user opens it — so process launch ≠ user interaction |
| state restoration | Persisted scene/UI archive (UIKit restoration / SwiftUI `@SceneStorage`) replayed after a jetsam kill so the app reappears where the user left it; a recoverable on-disk artifact |
| `phys_footprint` | The `task_info(TASK_VM_INFO)` counter that backs the per-process memory limit; the introspectable footprint jetsam enforces |

## Further reading

- Apple Developer — *Identifying high-memory use with jetsam event reports* (developer.apple.com/documentation/xcode) — the authoritative field/`reason` reference
- Apple Developer — *Responding to low-memory warnings*, *Reducing your app's memory use*, `os_proc_available_memory` (os/proc.h)
- Apple Developer — *Acquiring crash reports and diagnostic logs*; WWDC "Why your app got killed in the background"
- Jonathan Levin, *MacOS and iOS Internals, Vol. I (User Mode)* + newosxbook.com — "No Pressure, Mon! Handling low-memory conditions" (memorystatus, jetsam threads, priority bands, `kern.memorystatus*` sysctls)
- XNU source — `bsd/kern/kern_memorystatus.c`, `<sys/kern_memorystatus.h>` (band constants, `memstat_bucket`, `memorystatus_control` commands), `osfmk/vm/vm_compressor.c`
- libimobiledevice `idevicecrashreport(1)`; pymobiledevice3 `crash` subcommands — CrashReporter-service extraction
- iLEAPP (Alexis Brignoni) and the SANS FOR585 material — parsing and timelining iOS crash/jetsam artifacts
- Apple Developer — *MetricKit* (`MXMetricManager`, `MXAppExitMetric`) and WWDC "Diagnose performance issues with the Xcode Organizer"
- Apple Developer — *About the app launch sequence* / *Prewarming* and *Preserving your app's UI across launches* (state restoration, `@SceneStorage`, `NSUserActivity`)
- `man memory_pressure`, `man vm_stat`, `man footprint`, `man vmmap` — the macOS-side contrast tooling

---
*Related lessons: [[xnu-on-mobile]] | [[processes-mach-xpc]] | [[passcode-bfu-afu-and-inactivity]] | [[unified-logging-and-sysdiagnose]] | [[knowledgec-db-deep-dive]] | [[app-lifecycle-scenes-and-background-execution]] | [[simulator-internals-and-on-disk-filesystem]]*
