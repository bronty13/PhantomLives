---
title: "Processes, Mach & XPC"
part: "02 — System Architecture & Internals"
lesson: 05
est_time: "45 min read + 15 min labs"
prerequisites: [xnu-on-mobile]
tags: [ios, processes, mach, xpc, ipc, springboard]
last_reviewed: 2026-06-26
---

# Processes, Mach & XPC

> **In one sentence:** iOS keeps the exact Mach-task / BSD-proc / launchd / XPC machinery you learned on macOS, but bolts it to a mandatory code-signing gate and a near-total lockdown of task ports — so every process on the device is signed and entitled, almost nothing can debug anything else, and "the running process graph" becomes a forensic and reverse-engineering object in its own right.

## Why this matters

On macOS you could `task_for_pid` your way into another process, attach `lldb` to anything you owned, and `DYLD_INSERT_LIBRARIES` your way into someone else's address space. None of that is true on a stock iPhone, and the reasons are *structural*, not cosmetic: the same primitives are present, but the kernel refuses to hand out the capabilities that make them useful. Understanding precisely **where** that lockdown lives — which entitlement, which syscall, which daemon — is what separates "iOS won't let me" frustration from a working instrumentation strategy. It is also the foundation for everything in Part 11: every frida session, every `lldb` attach, every reason you need a jailbreak or a repackaged app traces back to the task-port and code-signing policy described here. For forensics, the process graph at sysdiagnose time is a real artifact, and the IPC topology tells you which daemon could have touched which store.

## Concepts

### The Mach task / BSD proc duality (unchanged from macOS)

XNU on iOS is the same hybrid kernel you dissected on the Mac: a **Mach** core (tasks, threads, ports, virtual memory, messaging) with a **BSD** personality (processes, signals, file descriptors, sockets, credentials) layered on top. Every running program is simultaneously:

- a **Mach task** — an address space plus a set of capabilities (ports). The task is the unit of resource ownership; it owns the virtual memory map, the port name space, and a set of threads.
- a **BSD process** (`struct proc`) — the POSIX identity: a PID, a parent PID, UID/GID credentials, a file-descriptor table, a signal disposition. `ps`, `kill(2)`, and `getpid(2)` operate on this layer.

The two are bonded one-to-one (`proc->task` and `task->bsd_info`), and the binding is what lets a Mach-level fault deliver a BSD signal (an `EXC_BAD_ACCESS` Mach exception becomes a `SIGSEGV`). This is identical to macOS — **memorize that it is identical**, because nearly everything that follows is about iOS *removing capabilities* from this structure, not changing it.

```
        ┌──────────────────────── one program ────────────────────────┐
        │                                                              │
   BSD  │   struct proc:  pid, ppid, ucred(uid/gid), fd table, signals │
        │        ▲                                                     │
        │        │  proc<->task bonded 1:1                             │
   Mach │        ▼                                                     │
        │   task:  vm_map (address space)                              │
        │          ipc_space (port name space)  ── port rights ──┐     │
        │          threads[] ── each: kernel + user register state│     │
        └─────────────────────────────────────────────────────────────┘
                                                  │
                          ports name kernel objects: tasks, threads,
                          memory entries, and IPC endpoints (services)
```

> 🖥️ **macOS contrast:** This duality is byte-for-byte the macOS model — same `host_t`, `task_t`, `thread_t`, same `mach_port_t`. If you ran `lldb` and `task_for_pid` on macOS, you already understand the *primitives*. The entire iOS difference is **policy on the port-rights layer**: who is allowed to obtain a task's control port. Hold that thought through the whole lesson.

### Mach ports: the capability layer

A **Mach port** is a kernel-managed, unforgeable message queue. What makes Mach a *capability* system is that you never address a port by a global ID; you hold a **port right** — a per-task entry in that task's `ipc_space` that grants you the ability to do something:

| Right | What it grants |
|---|---|
| **receive** | dequeue messages from the port (you are the "server" / owner) |
| **send** | enqueue messages to the port (you are a "client") |
| **send-once** | exactly one message, then the right is consumed (reply ports) |
| **port set** | receive across a group of ports with one `mach_msg` (an event loop) |
| **dead name** | the receiver died; your send right decayed to a tombstone |

Certain ports are *the* security boundary of the system:

- **task control port** (a.k.a. the "task port", `mach_task_self()` for your own): holding a *send* right to another task's control port is total ownership — you can `mach_vm_read`/`mach_vm_write` its memory, `thread_create` new threads in it, set thread state, suspend it. This is the macOS `task_for_pid` prize. **On iOS, the kernel will not give this to you for arbitrary tasks. That single restriction is the spine of iOS process isolation.**
- **bootstrap port**: every task inherits a send right to launchd's bootstrap port. This is how you *find* other services by name (below).
- **host port / host-priv port**: the global host control port; the privileged variant (`host_priv`) is required for kernel-level operations and is unreachable from user space on a non-jailbroken device.
- **thread ports, memory-entry ports, exception ports**: finer-grained capabilities (exception ports are how a debugger receives faults).

Mach split the task port surface into **read / inspect / name / control** flavors (the `mach_task_*` / `task_*_for_pid` family with `TASK_FLAVOR_*`). Even where a *read* or *inspect* port might be obtainable for diagnostics, the **control** flavor — the one that lets you write memory and inject threads — is the tightly guarded one.

### How an app *actually* launches

Here is the part that trips up everyone coming from desktop UNIX. Tapping an icon does **not** `fork()`+`exec()` from SpringBoard, and it cannot run arbitrary code. The real chain (durable mechanism; daemon names current as of iOS/iPadOS 26):

```
  user taps icon
        │
        ▼
  SpringBoard (com.apple.springboard)  ── the home screen + foreground app manager
        │   (uses FrontBoard / FrontBoardServices to broker who is foreground)
        ▼
  lsd (LaunchServices daemon)  ── resolves bundle id → app record in the LaunchServices DB (a com.apple.LaunchServices-*.csstore; installd registers apps with lsd at install time)
        │
        ▼
  runningboardd (RunningBoard)  ── takes a *process assertion*, sets the
        │                          Darwin role + jetsam priority, then asks…
        ▼
  launchd (PID 1)  ── posix_spawn() of  /usr/libexec/xpcproxy  with
        │              POSIX_SPAWN_SETEXEC, the bootstrap port, std FDs…
        ▼
  xpcproxy  ── sets up the XPC/launchd environment, then execs IN PLACE
        │       into the app's Mach-O main executable
        ▼
  ┌──────────────────────── the kernel + AMFI gate ───────────────────────┐
  │  AppleMobileFileIntegrity (AMFI kext) + amfid validate the code        │
  │  signature & embedded entitlements BEFORE the first instruction runs;  │
  │  every executable page is checked against its CDHash at page-in.       │
  │  No valid, trusted signature → the exec fails. Full stop.              │
  └────────────────────────────────────────────────────────────────────────┘
        │
        ▼
  dyld maps the dyld shared cache + the app's dylibs → main() → UIKit
```

Three things to extract from this:

1. **The spawned image must be signed and entitled.** `launchd` doesn't run "the code SpringBoard handed it" — it `posix_spawn`s a *file path*, and the kernel's code-signing enforcement (AMFI + the trust cache for platform binaries, the App Store / developer signature for third-party apps) decides whether that file is even allowed to execute. There is no path by which SpringBoard injects executable bytes into a new process. Contrast the desktop, where `fork`+`exec` of an arbitrary `a.out` Just Works.
2. **`xpcproxy` is the universal stub.** Daemons, XPC services, and apps all come up through `launchd → xpcproxy → exec`. `xpcproxy` is what wires the new process into the launchd job model (its Mach bootstrap, its MachServices, its sandbox profile) before handing control to the real binary.
3. **RunningBoard owns the lifecycle, not SpringBoard.** Since iOS 13 / macOS 10.15, `runningboardd` is the broker that holds **assertions** about every managed process — its Darwin role (foreground-interactive vs. background), its jetsam priority, GPU/CPU permissions. When the user backgrounds the app, RunningBoard flips the assertion, lowers the role, and raises jetsam eligibility. (Memory pressure and the kill path are the subject of [[memory-jetsam-app-lifecycle]].)

The "board" family divides the UI-shell labor and is worth separating in your head, because their logs are separate subsystems: **SpringBoard** is the home screen and the scene/foreground policy; **FrontBoard** (`FrontBoardServices`) is the framework that brokers app foreground/background transitions and scene lifecycle; **BackBoard** (`backboardd`) is the lower-level event router and display/compositor plumbing — roughly the iOS analogue of the macOS WindowServer's HID + display role. FrontBoard also installs a **watchdog** on each app: miss a lifecycle deadline (e.g., take too long to finish launching or to resume) and the watchdog kills the process with a distinctive exception code (`0x8badf00d`, "ate bad food"), which surfaces in the crash log. Recognizing `0x8badf00d` versus a jetsam kill (`per-process-limit` / memory) versus a normal exit is a routine triage step.

> 🖥️ **macOS contrast:** This is the *same* RunningBoard + launchd + xpcproxy pipeline modern macOS uses to launch apps (and to run iOS apps on Apple Silicon). The divergence is the AMFI gate: on macOS, an ad-hoc-signed or unsigned binary can still run (Gatekeeper is a userspace/quarantine policy you can bypass); on iOS, code-signing enforcement is **mandatory and in-kernel** — an unsigned page simply cannot be made executable without a kernel exploit. That is the entire premise of "you need a jailbreak to run unsigned code."

> 🔬 **Forensics note:** On macOS, `~/Library/LaunchAgents` and `/Library/LaunchDaemons` are the first place you look for malware persistence. On stock iOS that avenue is *closed*: launchd reads daemon jobs only from `/System/Library/LaunchDaemons` on the **sealed, read-only system volume** — there is no writable LaunchAgents directory a third-party app or implant can drop a plist into. So a launchd-based persistent process is, by itself, evidence of a jailbreak or a system-volume compromise. This is why spyware-triage (`mvt`) leans instead on the *consequences* a process leaves — anomalous entries in `DataUsage.sqlite`/`netusage.sqlite` (a process that did network I/O), unexpected configuration profiles, crash logs naming odd binaries — rather than expecting a tidy persistence plist.

### No subprocesses: the single-process app

Here is a consequence of the launch model that reshapes how every iOS app is *built*: a third-party app **cannot spawn child processes**. The sandbox denies `fork(2)`, `execve(2)`, `posix_spawn(3)`, and the `system(3)`/`popen(3)`/`NSTask` conveniences to non-platform apps. There is no shelling out to a helper binary, no bundling a CLI tool and exec'ing it, no `ffmpeg` subprocess. An app is **one process**, and any work it can't do in-process it must do by (a) linking a framework/dylib into its own address space, or (b) asking a system daemon over XPC. Even an app's own **extensions** (share sheet, widget, keyboard) are not children it forks — they are *separately launched* by the system through the same `launchd → xpcproxy` path, into their own sandboxes, and the app talks to them over XPC.

This is why so much iOS engineering is "find the framework" or "find the daemon": the desktop reflex of orchestrating a pipeline of small processes is simply unavailable. It also tightens the forensic and RE picture — the only processes on the device are platform daemons (trust-cached) and one-process-per-app sandboxes, so the process table has no "helper tool" noise to hide in.

> 🖥️ **macOS contrast:** On macOS, apps shell out constantly — `NSTask`, `Process`, `system()`, embedded CLIs. That entire pattern is **forbidden** on iOS. A macOS app you're porting that depends on a subprocess must be re-architected around an in-process library or a system XPC service. (Apple's own platform binaries can spawn — this is a third-party-sandbox restriction, not a kernel one.)

### Mach messages: the IPC substrate

Every cross-process call on iOS — XPC, distributed notifications, the entire daemon ecosystem — ultimately rides **`mach_msg()`**, the single syscall that sends and/or receives a message on a port. A Mach message is a header (`mach_msg_header_t`: destination port, reply port, size, msgh_id) optionally followed by typed descriptors that can carry **out-of-line memory** (copied or copy-on-write into the receiver's address space) and, crucially, **port rights** (you can *send a capability* in a message — this is how a service hands a client a send right to a sub-service).

The header is fixed-shape; everything interesting is in the bits:

```c
typedef struct {
    mach_msg_bits_t  msgh_bits;        // disposition of remote/local ports + flags
    mach_msg_size_t  msgh_size;        // total message size
    mach_port_t      msgh_remote_port; // destination (a send right you hold)
    mach_port_t      msgh_local_port;  // reply port (often a send-once right)
    mach_port_name_t msgh_voucher_port;// importance/activity voucher (QoS, importance, os_activity)
    mach_msg_id_t    msgh_id;          // the "selector": which routine/message
} mach_msg_header_t;
```

`msgh_bits` encodes the *port dispositions* — whether the remote and local fields carry a send, send-once, or move-receive right — and a `MACH_MSGH_BITS_COMPLEX` flag that says "typed descriptors follow." Those descriptors are what let one task **move a capability or a memory region to another**: a daemon answering an XPC look-up can put a fresh send right (to a sub-service) right into the reply message. The **voucher** carries cross-process attributes — QoS/"importance" so a high-priority client's request keeps the servicing daemon out of jetsam range while it works. Getting the bits or the descriptor types wrong is the classic Mach bug surface.

You will rarely hand-roll `mach_msg` in 2026; it is the asphalt under three higher layers:

- **MIG** (Mach Interface Generator) — the old RPC compiler that turns `.defs` into client/server stubs. Most kernel and legacy daemon interfaces (e.g., the `task_*`, `thread_*`, `host_*` routines) are MIG subsystems. The `msgh_id` is the routine selector; a MIG `msgh_id` collision, a missing complex-bit check, or descriptor type-confusion has historically been a rich bug class (Project Zero, the `task_for_pid`/`mach_port` exploit lineage).
- **XPC** — the modern, dictionary-typed, ARC-friendly layer (below).
- **libdispatch** — `mach_msg` receive rights are usually serviced by a `dispatch_source` of type `DISPATCH_SOURCE_TYPE_MACH_RECV` on a queue, which is why daemon back-traces are full of `_dispatch_mach_msg_invoke`.

### XPC and the mach-service namespace

XPC is the IPC the learner already met on macOS, and on iOS it is **the** way daemons expose brokered services. The model:

- A daemon declares, in its launchd plist (under `/System/Library/LaunchDaemons/*.plist` on the read-only system volume), a **`MachServices`** dictionary naming the service endpoints it owns, e.g. `com.apple.locationd.registration`. launchd creates a receive right for each name and **registers it in the bootstrap namespace**.
- A client calls `xpc_connection_create_mach_service("com.apple.…", …)`. Under the hood this is a **bootstrap look-up** in the client's bootstrap namespace: launchd resolves the name to a send right.
- If the service isn't running, **launchd demand-launches it** (via `xpcproxy`) on first message — the "launch on demand" model. The client never knows or cares whether the daemon was already alive.
- The service side accepts connections, and every message arrives with the peer's **audit token** (`xpc_connection_get_audit_token` / the private `xpc_dictionary_get_audit_token`), from which the daemon can recover the caller's PID, UID, and **code-signing identity / entitlements** — the basis for "only a process entitled X may call me."

```
                    bootstrap namespace (rooted at launchd / PID 1)
                                     │
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                             │
  com.apple.locationd       com.apple.cloudd            com.apple.tccd
    (receive right             (receive right              (receive right
     held by locationd)         held by cloudd)             held by tccd)
        ▲                            ▲                             ▲
        │ xpc_connection_create_mach_service("com.apple.locationd…")
        │  → bootstrap_look_up → send right
   ┌────┴──────┐
   │  app /    │   message carries the caller's audit token; the daemon
   │  daemon   │   checks the caller's entitlements before answering
   └───────────┘
```

iOS namespaces XPC services more tightly than macOS: there is no per-login-session subtree (there is one user), and a third-party app's sandbox profile restricts **which** `MachServices` names it may even look up. A look-up the sandbox forbids fails at the bootstrap layer — the message never reaches the daemon. (App-to-app XPC over `NSXPCConnection`/`xpc_connection_create` is generally **not** available to third-party apps the way it is on macOS; apps talk to the system, not directly to each other, except through Apple-mediated mechanisms.)

**The authorization pattern you'll reverse repeatedly.** Because the daemon holds the audit token of every caller, the canonical iOS privilege boundary is "check the peer's entitlements in the connection handler." A daemon does roughly:

```c
xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
    // recover the caller's code-signing identity from the audit token
    audit_token_t tok; xpc_connection_get_audit_token(peer, &tok);   // (SPI)
    // SecTask from the token → copy the value of a required entitlement
    //   (e.g. a private "com.apple.private.*" entitlement the daemon demands)
    if (!caller_has_entitlement(&tok, "com.apple.private.allowed-key")) {
        xpc_connection_cancel(peer);   // reject — the look-up succeeded, the call does not
        return;
    }
    // …service the request…
});
```

`NSXPCConnection` (the Objective-C/Swift object layer) sits on top of this. On *macOS* a server can offload the peer check to the framework with `connection.setCodeSigningRequirement(_:)` (macOS 13+) — but that convenience is **macOS-only** (its sole availability badge is `macOS 13.0+`; the API is not exposed on iOS). On iOS the canonical pattern is therefore the hand-rolled check above: recover a `SecTask` from the peer's audit token (`SecTaskCreateWithAuditToken`) and read the required entitlement yourself (`SecTaskCopyValueForEntitlement`). **Either way, for RE the entitlement-check call is the function to find**: it is where "what can call me" is decided, and bypassing or satisfying it (right entitlement on a repackaged binary, or a hook that forces the `true` branch) is often the whole game. For forensics, the *set* of private entitlements a binary carries (read via `codesign -d --entitlements`/`ldid -e`) tells you which daemons it is *allowed* to reach — an over-entitled third-party binary is a red flag.

> 🖥️ **macOS contrast:** Same `libxpc`, same `xpc_dictionary_*` API, same `MachServices` plist key, same bootstrap-look-up demand-launch. The differences are: (1) iOS daemon plists live on the sealed system volume and are immutable; (2) the bootstrap namespace is flatter (no per-session tree); (3) the sandbox, not just entitlements, gates which service names an app can resolve at all; (4) the high-level `NSXPCConnection.setCodeSigningRequirement(_:)` peer-validation shortcut is macOS-only — iOS daemons do the audit-token entitlement check by hand. Your macOS `launchctl print system` mental model transfers directly.

### The locked-down debugging surface

This is the section to tattoo on your forearm. Three knobs decide whether dynamic instrumentation is even possible:

**1. `task_for_pid` is effectively dead for arbitrary processes.** On macOS, root (or a `com.apple.security.cs.debugger`-entitled tool) could `task_for_pid` most processes. On iOS, the policy is far stricter: the kernel hands out a target's **control** port only when the target is itself debuggable, and the only sanctioned consumer is Apple's `debugserver`. There is no general "give me any PID's task port as root" — and on a stock device you aren't root anyway.

**2. `get-task-allow` (on the *target*) is the gate.** The `get-task-allow` entitlement, when `true` on the target binary, tells the kernel "this process consents to having its task control port handed to a debugger." 
- **Development-signed apps** (run from Xcode, signed against a *Development* provisioning profile) carry `get-task-allow = true` — which is exactly why Xcode's `lldb` can attach.
- **App Store / TestFlight / distribution-signed apps** are signed **without** it (the App Store signing strips/forbids it). So `debugserver` — and therefore `lldb` and frida-via-debugserver — **cannot attach to a stock App Store app** on a non-jailbroken device. Not "it's hard"; the kernel refuses the task port.
- `debugserver` itself must carry the `task_for_pid-allow` (and related `com.apple.private.cs.debugger`) entitlement to be *allowed to ask*. Apple's shipped `debugserver` (inside the Developer Disk Image / since iOS 17 the personalized developer image) has it; a copy you sign yourself does not, unless you have the entitlement whitelisted.

**3. `dynamic-codesigning` (JIT) gates runtime code generation.** Creating writable-then-executable memory — the `MAP_JIT` region, the `mmap(PROT_WRITE)` → `mprotect(PROT_EXEC)` move, or Apple-Silicon W^X JIT toggling — requires the `dynamic-codesigning` entitlement. On iOS essentially **only WebKit's JavaScriptCore** gets it. A normal app cannot allocate executable memory and run code it generated at runtime; AMFI's page-in check would reject the unsigned page. This is *why* a frida agent can't simply JIT itself into an unentitled App Store app, and why injection on iOS means either a jailbreak (patch AMFI / amfid), a **repackaged app embedding `frida-gadget`** as a signed dylib, or a development build with the right entitlements.

```
  Want to attach lldb / frida to a process on a stock device?
        │
        ├─ Target signed with get-task-allow=true (dev build)? ── yes ──► debugserver can attach
        │                                                                  (this is the only easy path)
        ├─ Target is an App Store app? ── no get-task-allow ──► kernel REFUSES the task port
        │                                                        → need jailbreak, or repackage
        │                                                          the IPA with frida-gadget + resign
        └─ Want to run code you generated at runtime?
                 └─ need `dynamic-codesigning` (JIT) ──► only JavaScriptCore has it on stock iOS
```

> ⚖️ **Authorization:** Obtaining a task port, attaching a debugger, or injecting a dylib into a process you do not own is exactly the line where casual analysis becomes unauthorized access. In a forensic engagement, dynamic instrumentation of a third-party app on a subject's device is an *invasive* technique that alters the running system — scope it explicitly in your authorization, prefer it on a forensic *copy* or test device, and log it. "I attached frida to the banking app" is a sentence that belongs in your notes with a warrant paragraph behind it, not a shrug.

### How a debugger actually receives faults: exception ports

`get-task-allow` isn't a magic "debuggable" boolean checked by `lldb` in user space — it is the kernel's permission to wire up the **Mach exception model**. When a thread faults (bad access, breakpoint trap, illegal instruction), the kernel doesn't immediately signal the BSD process; it first looks for a registered **exception port** and sends a Mach message describing the exception (`EXC_BAD_ACCESS`, `EXC_BREAKPOINT`, …) to whoever holds the receive right. A debugger works by:

1. obtaining the target's task **control** port (the gated step — needs `get-task-allow` on the target), then
2. calling `task_set_exception_ports()` / `thread_set_exception_ports()` to register *its own* port as the target's exception handler, then
3. servicing the exception messages: on `EXC_BREAKPOINT` it stops the thread, lets you inspect/modify register and memory state (via the same task port: `thread_get_state`, `mach_vm_write`), and replies to continue.

Only *after* a debugger declines (or none is registered) does the exception fall through to the **BSD signal** path (`SIGTRAP`, `SIGSEGV`). This is why the task-port lockdown is so total: with no control port you cannot register as the exception handler, so you cannot single-step, set breakpoints, or read registers — there is no side door. It is also the mechanism crash-reporting uses (`ReportCrash`/`osanalyticshelper` register a corpse/exception handler), which is why crashes still produce `.ips` logs even though *you* can't debug the app.

> 🔬 **Forensics note:** Those crash reports are a durable artifact. iOS writes them as JSON-ish **`.ips`** files (the legacy `.crash` text format was superseded) under `/private/var/mobile/Library/Logs/CrashReporter/` on the device — and they sync into a sysdiagnose and into the **diagnostic logs** an iTunes/Finder backup or a "Share Analytics" pull exposes on the Mac at `~/Library/Logs/CrashReporter/MobileDevice/<DeviceName>/`. Each report names the process, its parent, the responsible binary, loaded images (with their CDHashes/UUIDs), and the termination reason — including watchdog (`0x8badf00d`) and jetsam kills. For spyware triage this is gold: a crash *inside* a victim process, or a crash naming an unexpected binary/library, has repeatedly been the first thread investigators pulled on Pegasus-class implants. The exception-handling machinery you can't use to debug is quietly generating evidence the whole time.

### Anti-debugging from the app side: `ptrace(PT_DENY_ATTACH)`

The lockdown runs both directions: an app can also actively *refuse* to be debugged. The classic iOS move is the BSD call `ptrace(PT_DENY_ATTACH, 0, 0, 0)`, which sets the `P_LNOATTACH` flag on the process — after which any attempt to attach a debugger (acquire the task port for debugging) fails, and the process is killed if a debugger is already attached. Hardened apps call it early in `main`/a constructor, frequently *not* through the libSystem `ptrace` stub but via a raw `syscall(SYS_ptrace, …)` or a direct `svc #0x80` trap to dodge a symbol hook. Adjacent checks you'll meet in Part 11: `sysctl(KERN_PROC, KERN_PROC_PID, …)` reading `kp_proc.p_flag & P_TRACED` to detect an attached tracer, and `getppid() != 1` heuristics. None of this is unbreakable — frida/lldb beat it by hooking or patching the check — but it raises the cost, and recognizing the pattern in a disassembly is a core RE skill.

> 🖥️ **macOS contrast:** `PT_DENY_ATTACH` and the exception-port model are pure-Darwin and behave the same on macOS — you likely met `ptrace(PT_DENY_ATTACH)` in macOS malware/anti-analysis. The difference is leverage: on macOS you can often disable SIP, run as root, or use the `com.apple.security.cs.debugger` entitlement to muscle past it; on a stock iPhone you have none of those, so an app's anti-debug actually *holds* until you bring a jailbreak or a repackaged binary.

### BSD process layer: what you can still enumerate

The POSIX layer survives and is the part you *can* observe without special capabilities. A process still has a PID/PPID, credentials, and an argv/env, reachable through the BSD `sysctl(KERN_PROC*)` / `proc_pidinfo` / `proc_listpids` interfaces — these back `ps` and the `libproc` calls. Enumerating *that* a process exists (PID, name, parent, start time) is a low-privilege operation; *controlling* it (the task port) is the gated one. The asymmetry is deliberate: iOS lets diagnostics see the process table while denying memory access. On a stock device you have no shell to run `ps`, but the **sysdiagnose** capture runs these for you and freezes the result on disk (next section, and the Forensics note).

> 🔬 **Forensics note:** The running process + Mach-service graph is captured in a **sysdiagnose** bundle. Look for `ps.txt` (the full BSD process table with start times), `spindump-nosymbols.txt` / `tailspin-info.txt` (per-thread stacks across all processes — effectively a snapshot of who was doing what), `taskinfo*.txt`, and `launchctl`-style dumps of the launchd job/`MachServices` state. Together these reconstruct, for the instant the capture ran: which daemons and apps were alive, their parentage (everything traces to `launchd` PID 1 via `xpcproxy`), and which XPC services were registered. Treat exact filenames as version-dependent — `find` the bundle, don't assume. (Deep dive in [[unified-logs-sysdiagnose-crash-network]].)

> 🔬 **Forensics note:** Because the AMFI gate means **every executing binary is signed** — Apple platform binaries (in the trust cache) or App-Store/dev-signed third-party apps — the process graph is unusually *clean*. An anomalous process: one with an unexpected name, a launchd parent that isn't the normal path, a binary not backed by a known signature, or weird entitlements, is a strong indicator of compromise. This is precisely the logic [`mvt`](https://github.com/mvt-project/mvt) and spyware-triage workflows apply when hunting Pegasus-class implants in sysdiagnose/backup data: the implant has to *become a process*, and on iOS becoming a process means defeating or abusing code signing, which leaves traces.

### RE relevance: reasoning about the process graph

When you reverse an iOS app or chase an artifact, you are really mapping a graph: the app process, the daemons it talks to over XPC, and the on-disk stores those daemons own. Examples you will lean on constantly:

| The app touches… | …by talking over XPC to… | …which owns the store |
|---|---|---|
| Location | `locationd` | the cache/`.plist` location stores |
| iCloud sync / CloudKit | `cloudd`, `bird` (CloudDocs) | the per-app CloudKit caches |
| iMessage / SMS | `imagent` / `identityservicesd` | `sms.db`, the Messages stores |
| Keychain item | `securityd` / SEP | `keychain-2.db` |
| Push | `apsd` | APNs state |
| Photos | `photoanalysisd`, `photolibraryd` | `Photos.sqlite` |
| TCC permission prompt | `tccd` | `TCC.db` |

Knowing the topology tells you *which daemon's logs and stores to pull* for a given behavior, and — for RE — *which Mach service to hook* if you want to observe a call. It also explains why so much interesting data isn't in the app's own sandbox: the app asked a daemon, and the daemon holds the data. Part 08's artifact lessons are, in effect, a tour of these daemons' stores.

Concretely, when you instrument an app under frida (once you've cleared the get-task-allow/jailbreak hurdle), the highest-value hooks are usually at the **XPC boundary**, not deep in the app's own classes: `xpc_connection_create_mach_service` (which service is it reaching for?), `xpc_connection_send_message_with_reply` (what's the request payload?), and the `NSXPCConnection` `remoteObjectProxy` path reveal the app's entire conversation with the system in clear, *before* any per-app obfuscation. The same boundary is where a hardened app enforces TLS pinning or jailbreak detection by asking a daemon — so it's also where the bypasses in [[certificate-pinning-and-bypass]] and [[anti-tamper-pinning-and-detection-both-sides]] land. Reasoning in terms of the process graph, rather than a single binary, is the mindset shift this lesson exists to install.

## Hands-on

There is **no on-device shell**. Everything below runs on the Mac, against the **Simulator** (which has a real launchd_sim, RunningBoard, and SpringBoard you can poke) or against Mach-O files on disk. Device-only steps are called out as walkthroughs.

**Inspect the Simulator's launchd service graph (the bootstrap namespace):**
```bash
# Boot a simulator (or use an already-booted one)
xcrun simctl boot "iPhone 16 Pro"   # any installed runtime is fine

# Dump launchd's system domain: jobs + their MachServices (the namespace)
xcrun simctl spawn booted launchctl print system | sed -n '1,60p'
# → look for the "services" block: each line is a registered Mach service
#   name and the PID currently holding its receive right (or "-" if on-demand)

# Drill into one job to see its MachServices, state, and spawn type
xcrun simctl spawn booted launchctl print system/com.apple.runningboardd
```

**Watch RunningBoard manage an app launch (assertions in real time):**
```bash
# In one terminal, stream RunningBoard's reasoning
xcrun simctl spawn booted log stream \
  --predicate 'process == "runningboardd"' --style compact

# In another, launch an app through the normal SpringBoard/launchd path
xcrun simctl launch booted com.apple.mobilesafari
# → the log shows RunningBoard acquiring a process assertion, setting the
#   Darwin role to foreground, jetsam priority changes, then the app coming up
```

**See the BSD process table inside the Simulator:**
```bash
xcrun simctl spawn booted ps -axww -o pid,ppid,stat,comm | sed -n '1,40p'
# → note that everything descends from launchd_sim (PID 1) via xpcproxy
```

**Prove the entitlement that gates debugging — read it straight off the Mach-O:**
```bash
# A development build (carries get-task-allow=true → lldb can attach)
codesign -d --entitlements :- /path/to/DevBuild.app 2>/dev/null | \
  plutil -p - | grep -i 'get-task-allow'
# → "get-task-allow" => 1

# An App Store / distribution binary: the key is absent (or false)
codesign -d --entitlements :- /path/to/AppStore.app 2>/dev/null | \
  plutil -p - | grep -i 'get-task-allow'
# → (no output) — the kernel will refuse a task port for this process

# ldid is the jailbreak-world equivalent and reads pseudo-signed binaries too
ldid -e /path/to/Binary
```

**Inspect a daemon's declared Mach services (durable across versions):**
```bash
# On a mounted IPSW root / extracted system, daemon plists declare MachServices
plutil -p /System/Library/LaunchDaemons/com.apple.locationd.plist | \
  grep -A20 -i MachServices
# → the named endpoints locationd registers in the bootstrap namespace
```

**Watch launchd demand-launch a service on first XPC message:**
```bash
# Stream launchd's own subsystem; then trigger an app that uses a daemon
xcrun simctl spawn booted log stream \
  --predicate 'subsystem == "com.apple.xpc" OR process == "launchd"' \
  --style compact &
xcrun simctl launch booted com.apple.mobilesafari
# → you can see the bootstrap look-up resolve and an on-demand job come up via
#   xpcproxy the first time a service name is messaged (the "launch on demand" model)
```

**Recover a process's argv/parentage with libproc-backed tools (BSD layer):**
```bash
# Inside the sim, the BSD process interfaces are live even without root
xcrun simctl spawn booted ps -axww -o pid,ppid,start,command | grep -i springboard
# → SpringBoard's PID/PPID/start time — the same fields a sysdiagnose ps.txt freezes
```

> ⚠️ **ADVANCED — device-only walkthrough (do not expect this on a stock phone):** On iOS 17+, Apple moved the developer services behind a **RemoteXPC tunnel** (RemoteServiceDiscovery / `RSD`). With a *paired, developer-mode-enabled* device you can enumerate the live process list the way Instruments does:
> ```bash
> pip install -U pymobiledevice3
> # iOS 17.4+ takes the fast lockdown path; iOS 17.0–17.3.1 instead needs `remote start-tunnel`
> sudo python3 -m pymobiledevice3 lockdown start-tunnel   # establishes the RSD tunnel; PRINTS an RSD address + port
> # feed that printed RSD address/port to every developer command:
> python3 -m pymobiledevice3 developer dvt proclist --rsd <rsd-addr> <rsd-port>   # live process list via DTServiceHub
> ```
> Attaching a debugger still requires the target to carry `get-task-allow`; `pymobiledevice3 developer debugserver` only reaches debuggable (development-signed) apps. None of this works without the physical device, a trust pairing, and Developer Mode toggled on — hence it lives here as a walkthrough, with the Simulator labs below as the device-free stand-in.

## 🧪 Labs

> Substrate note: Labs 1–3 use the **Xcode Simulator** (CoreSimulator), which has a genuine `launchd_sim`, `runningboardd`, `SpringBoard`, and XPC bootstrap namespace — so the *process/IPC structure* is faithful. **Fidelity caveat:** the Simulator runs macOS-host frameworks, so there is **no AMFI code-signing enforcement, no sandbox enforcement, no SEP, no jetsam-under-real-memory-pressure**, and device-only daemons (`knowledged`, `biomed`, `routined`, `powerlogHelperd`/PowerLog) do not populate device stores. Lab 4 uses **Mach-O files on disk** (any `.app`), which is fully faithful for entitlement inspection. None of these need a device.

### Lab 1 — Map the bootstrap namespace (Simulator)
1. Boot any simulator and run `xcrun simctl spawn booted launchctl print system`.
2. Find the **services** section. Pick three `com.apple.*` service names and identify, for each, whether a PID currently holds it (running) or it shows on-demand. 
3. Run `launchctl print system/<one-service-job>` and locate its `MachServices` and its `state`/`spawn type`. Write one sentence explaining how a client would reach this service (`xpc_connection_create_mach_service` → bootstrap look-up → demand-launch).
4. **Fidelity check:** note that on a real device these plists live read-only on the sealed system volume; here they are mutable host files. Structure is real; immutability is not.

### Lab 2 — Watch the launch chain (Simulator)
1. Start `xcrun simctl spawn booted log stream --predicate 'process == "runningboardd" OR process == "launchd"' --style compact`.
2. In another terminal, `xcrun simctl launch booted com.apple.mobilesafari`, then send it to background by launching another app.
3. In the log, identify: the process assertion RunningBoard takes, the Darwin **role** change foreground→background, and any jetsam-priority adjustment. Map each line to the launch diagram in Concepts.
4. **Fidelity check:** real-device RunningBoard also drives the *actual* jetsam kill path under memory pressure; the Simulator won't kill for memory the way a phone does. You're seeing the bookkeeping, not the consequence — see [[memory-jetsam-app-lifecycle]].

### Lab 3 — Reconstruct parentage (Simulator)
1. `xcrun simctl spawn booted ps -axww -o pid,ppid,stat,lstart,comm`.
2. Pick three app/daemon processes and walk each PPID chain up to PID 1. Confirm that the chain passes through `launchd_sim` and that user apps were brought up via the `xpcproxy` → exec stub (you'll see the app binary as the process, not `xpcproxy`, because the exec replaced it in place — that's the point).
3. Write down what a sysdiagnose's `ps.txt` would let you assert on a real device about "what was running at capture time," and what it *cannot* tell you (memory contents, since you never had the task port).

### Lab 4 — The debugging gate, on real binaries (Mach-O on disk)
1. Take one development-signed `.app` (built and run from Xcode) and one App Store `.app` (e.g., from `~/Library/Developer/Xcode/DerivedData` vs. a `.ipa` you extracted).
2. For each: `codesign -d --entitlements :- <app/binary> | plutil -p -` and grep for `get-task-allow`.
3. Confirm the development build has `get-task-allow => 1` and the distribution build does not. State, in one line, why this single bit decides whether `debugserver`/`lldb`/frida-via-debugserver can attach on a stock device — and what your remaining options are when it's absent (jailbreak, or repackage the IPA with `frida-gadget` and re-sign). This is the bridge to [[dynamic-analysis-with-frida]] and [[the-jailbreak-landscape-2026]].

### Lab 5 — Reconstruct a device process graph from a sysdiagnose (sample capture, read-only walkthrough)
You don't need a phone for this — any sysdiagnose works (generate one on a Mac with `sudo sysdiagnose` for structure practice, or use a public iOS reference capture; the layout is the same).
1. Unpack the bundle and locate the process snapshot: `find <sysdiagnose_dir> -iname 'ps.txt' -o -iname 'spindump-nosymbols.txt' -o -iname 'tailspin-info.txt'`.
2. In `ps.txt`, find three daemons from the RE-relevance table (`locationd`, `cloudd`, `tccd`, `imagent`, …) and confirm each descends from `launchd` (PID 1). Note their start times.
3. In `spindump-nosymbols.txt`, pull the back-trace for one of those daemons and identify the `_dispatch_mach_msg_invoke` / `mach_msg` frames — direct evidence it was sitting in an XPC receive loop at capture time.
4. Write the assertion this snapshot supports ("processes X, Y, Z were alive at <capture time>, parented to launchd") and the one it does **not** ("what each was *doing* with user data" — that needs the daemons' on-disk stores, because you never had their task ports). 
5. **Fidelity check:** this is the *real* device artifact the Simulator can't produce — but it's a single instant, not a timeline. The behavioral timeline lives in the Biome/knowledgeC and unified-log stores ([[knowledgec-db-deep-dive]], [[unified-logs-sysdiagnose-crash-network]]).

## Pitfalls & gotchas

- **"I'm root, so I can `task_for_pid`."** Wrong on two counts: on a stock device you are *not* root (no shell, no `sudo`), and even root does not get arbitrary task control ports on iOS the way it did on macOS. The gate is the target's `get-task-allow`, enforced by the kernel, not a UID check.
- **Expecting `fork`+`exec` of arbitrary code.** SpringBoard cannot inject bytes into a new process; `launchd` `posix_spawn`s a *file path* and AMFI vets its signature before the first instruction. Coming from desktop UNIX, this is the single biggest mental-model reset.
- **Confusing SpringBoard with launchd.** SpringBoard is the home-screen / foreground-app *manager* (the GUI shell, Finder-ish in spirit), but it does not spawn processes. `runningboardd` brokers the lifecycle and `launchd` (PID 1) does the actual spawning. Attributing the spawn to SpringBoard will mislead your log analysis.
- **Assuming macOS XPC app-to-app works.** Two third-party iOS apps generally cannot open a direct `xpc_connection` to each other; the sandbox forbids the bootstrap look-up. Cross-app communication goes through Apple-mediated channels (app extensions, shared App Groups containers, URL schemes, the pasteboard), not raw XPC.
- **Stale `debugserver`/DDI assumptions.** Pre-iOS 17 you mounted a Developer Disk Image to get `debugserver`; iOS 17+ uses a **personalized developer image** and a **RemoteXPC tunnel** (`RSD`). Old `idevicedebugserverproxy`-style recipes silently fail on modern devices — verify the tunnel/`pymobiledevice3` path for the OS version in front of you.
- **The Simulator lies about enforcement.** It will happily let you attach and inject because it runs host frameworks with no AMFI/sandbox/SEP. *Structure* (the namespace, RunningBoard assertions, parentage) is faithful; *security policy* is not. Never conclude "iOS allows X" from "the Simulator allowed X."
- **`dynamic-codesigning` ≠ "developer mode."** JIT entitlement is a separate, rarely granted capability (basically JavaScriptCore). Don't assume a development build can generate-and-run code; it can be *debugged*, but it still can't make arbitrary RWX memory without `dynamic-codesigning`.
- **Reading the audit token isn't authentication of the *human*, only the *binary*.** A daemon's `xpc_connection_get_audit_token` entitlement check proves which signed binary is calling — not that the legitimate user authorized it. When you reverse a privilege boundary, don't over-read an entitlement gate as a user-consent gate; those are different decisions, often made by different daemons (`tccd` is the consent one).
- **Don't read `0x8badf00d` as "a crash bug."** A watchdog termination usually means the main thread was *blocked* (synchronous I/O, a deadlock, an over-long launch) past a deadline — RunningBoard/FrontBoard killed a *healthy-but-unresponsive* process. Triage it as a hang, not a memory-corruption crash; the back-trace points at what the main thread was stuck on, not at a faulting instruction.

## Key takeaways

- iOS keeps the **exact** macOS Mach-task / BSD-proc / launchd / XPC primitives; the difference is **policy on port rights** — who may obtain a task's *control* port.
- Apps launch through **SpringBoard → lsd (LaunchServices) → runningboardd → launchd → posix_spawn(xpcproxy) → exec**, with an **in-kernel AMFI code-signing gate** that means the spawned image must be signed and entitled. There is no fork+exec of arbitrary code.
- **Mach ports are capabilities.** The task *control* port is total ownership of a process; iOS refuses to hand it out for arbitrary tasks, and that single restriction is the backbone of process isolation.
- **XPC over the mach-service namespace** is how daemons expose brokered services: `MachServices` in a launchd plist → bootstrap registration → `xpc_connection_create_mach_service` look-up → demand-launch — identical API to macOS, but flatter namespace and sandbox-gated look-ups.
- The debugging surface is locked by three knobs: **`task_for_pid` is dead for arbitrary PIDs**, **`get-task-allow` on the target** decides whether a debugger can attach (present on dev builds, absent on App Store builds), and **`dynamic-codesigning`** decides whether runtime code generation is even possible (basically WebKit-only).
- **RunningBoard**, not SpringBoard, owns the process lifecycle: assertions, Darwin roles, and jetsam priority — the input to the kill path in [[memory-jetsam-app-lifecycle]].
- For forensics, the **process + Mach-service graph is a real artifact** (frozen in a sysdiagnose's `ps.txt`/`spindump`/launchd dumps), and the AMFI gate makes the process graph clean enough that an anomalous process is a high-value IOC.
- For RE, you reason about the app's **XPC topology**: the data you want often lives in a *daemon's* store, not the app's sandbox — and the debugging gate above dictates whether you can observe the calls live (Part 11).

## Terms introduced

| Term | Definition |
|---|---|
| Mach task | The Mach-level unit of resource ownership: an address space, a port name space, and a set of threads. Bonded 1:1 to a BSD process. |
| BSD proc (`struct proc`) | The POSIX identity layered on a Mach task: PID/PPID, credentials, file descriptors, signals. |
| Mach port | A kernel-managed, unforgeable message queue addressed via per-task *port rights* (receive/send/send-once). |
| Task control port | A send right that grants total control of a task (read/write memory, create threads). The `task_for_pid` prize; withheld on iOS. |
| Bootstrap port / namespace | The launchd-rooted directory of named Mach service endpoints; clients resolve service names here via bootstrap look-up. |
| `mach_msg()` | The single syscall underlying all Mach IPC; carries headers, out-of-line memory, and port rights between tasks. |
| MIG | Mach Interface Generator — RPC stub compiler for Mach message subsystems (e.g., the `task_*`/`host_*` routines). |
| XPC | Apple's high-level IPC over Mach messages; dictionary-typed, demand-launched, carries the caller's audit token. |
| Audit token | A kernel-vouched identity token attached to each XPC peer; yields the caller's PID, UID, and code-signing identity/entitlements, so a daemon can authorize *which signed binary* may call it. |
| `MachServices` (launchd key) | The launchd-plist dictionary by which a daemon declares the Mach service names it registers in the bootstrap namespace. |
| AMFI | AppleMobileFileIntegrity — the kernel extension (+ `amfid`) that enforces mandatory code signing and entitlements at exec/page-in. |
| `xpcproxy` | The launchd stub process that sets up the XPC/launchd environment then execs in place into the real binary (apps and daemons alike). |
| SpringBoard | The iOS home-screen and foreground-app manager (the GUI shell). Brokers foreground state via FrontBoard; does not spawn processes. |
| RunningBoard (`runningboardd`) | The lifecycle broker (iOS 13+): holds process *assertions*, sets Darwin roles and jetsam priority for every managed process. |
| Darwin role | RunningBoard's classification of a process (e.g., foreground-interactive vs. background) that drives scheduling and jetsam eligibility. |
| `get-task-allow` | Target-side entitlement meaning "a debugger may obtain my task control port." Present on dev builds, absent on App Store builds. |
| `task_for_pid-allow` | Debugger-side entitlement (carried by Apple's `debugserver`) permitting it to request task ports for `get-task-allow` targets. |
| `dynamic-codesigning` | Entitlement permitting JIT — creation of writable-then-executable memory. On stock iOS, essentially only JavaScriptCore holds it. |
| Exception port | A Mach port that receives `EXC_*` messages when a thread faults; registering one (needs the task control port) is *how* a debugger sets breakpoints and reads register state. |
| `PT_DENY_ATTACH` | A `ptrace(2)` request that flags a process to refuse debugger attachment (and kill an attached one) — the classic iOS app-side anti-debug. |
| `0x8badf00d` | The watchdog termination exception code ("ate bad food") emitted when an app misses a FrontBoard lifecycle deadline. |
| BackBoard (`backboardd`) | The low-level event-routing and display/compositor daemon — the iOS analogue of the macOS WindowServer's HID + display role. |
| RemoteXPC / RSD | The RemoteServiceDiscovery tunnel (iOS 17+) over which developer services (debugserver, dvt) are now reached from the Mac. |

## Further reading

- **Apple Platform Security Guide** (security.apple.com) — code-signing enforcement, AMFI, the launch/trust model.
- Apple Developer documentation — *XPC* framework (`xpc_connection_create_mach_service`), the `MachServices` launchd key, the `com.apple.security.cs.debugger` / `get-task-allow` entitlements, *Daemons and Services Programming Guide*.
- **Jonathan Levin**, *MacOS and iOS Internals* vols I–III, and newosxbook.com — the canonical treatment of Mach ports, `launchd` (Ch. 7, "The Alpha and the Omega"), MIG, and the task-port lockdown; `jtool2`/`procexp`.
- **Howard Oakley**, Eclectic Light Company (eclecticlight.co) — the RunningBoard series ("What does RunningBoard do?", assertions, Darwin roles) and "How macOS launches an iOS app."
- **Google Project Zero** — Mach message / MIG bug classes and task-port exploitation write-ups.
- `pymobiledevice3` (github.com/doronz88/pymobiledevice3) — RemoteXPC/RSD tunneling, `developer dvt proclist`, debugserver; `frida` + `frida-gadget` (frida.re) for the injection paths.
- `man launchctl`, `man posix_spawn`, `man mach_msg`, `man codesign`, `man ldid` — flag-level reference on the target OS version.
- **mvt** (github.com/mvt-project/mvt) — process/IOC triage against iOS sysdiagnose and backups (the "anomalous process is signal" workflow).

---
*Related lessons: [[xnu-on-mobile]] | [[launchd-and-system-daemons]] | [[memory-jetsam-app-lifecycle]] | [[dyld-shared-cache-and-amfi]] | [[code-signing-amfi-entitlements]] | [[dynamic-analysis-with-frida]] | [[the-jailbreak-landscape-2026]]*
