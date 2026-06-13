---
title: Darwin & the XNU Kernel (Mach + BSD)
part: P01 Architecture
est_time: 60 min read + 45 min labs
prerequisites: [none]
tags: [macos, xnu, kernel, darwin, mach, bsd, iokit, kext, driverkit, forensics, architecture]
---

# Darwin & the XNU Kernel (Mach + BSD)

> **In one sentence:** macOS is a POSIX-conformant Unix built on Darwin — an open-source OS whose heart is XNU, a hybrid kernel fusing Carnegie Mellon's Mach microkernel with a FreeBSD-derived BSD layer and Apple's C++ IOKit driver runtime, all running on top of Apple Silicon hardware that enforces kernel integrity at the silicon level.

---

## Why This Matters

Every investigation, every privilege-escalation chain, every mysterious hang or panic trace leads back here. When you ask "what process spawned this binary?" you are querying the BSD layer's `proc` table. When you ask "how did that rootkit hook the network stack?" you are asking whether it used a kext, a Network Extension System Extension, or a deeper Mach port interposition. When you ask "why won't this Windows driver SDK compile?" you are colliding with the Mach VM model and IOKit's C++ runtime.

Understanding XNU's architecture is not academic. It determines:

- Where forensic artifacts live and what the kernel's own data structures look like on disk and in memory.
- Why the macOS security model is fundamentally different from Windows NT's monolithic driver model.
- Which third-party kernel code is *legitimately* present on a machine (and therefore what is *anomalous*).
- How to read a kernel panic log, a crash report, or a `dtrace` probe address.

---

## Concepts

### 1. Darwin: The Open-Source Foundation

**Darwin** is the open-source operating system that forms macOS's foundation. It consists of:

| Component | Description |
|---|---|
| **XNU** | The kernel itself |
| **BSD userland** | Core Unix utilities (`ls`, `ps`, `dyld`, shells) largely from FreeBSD |
| **launchd** | PID 1 — replaces init, inetd, crond, and rc in a single daemon; manages the entire service and socket-activation graph |
| **libSystem** | The system library (`/usr/lib/libSystem.B.dylib`) that wraps all syscalls into a unified C interface |

Darwin source is published under the Apple Public Source License (APSL 2.0) at [github.com/apple-oss-distributions/xnu](https://github.com/apple-oss-distributions/xnu). The published source lags commercial releases by one to several versions, so current builds are not always public — but the architecture is.

> 🪟 **Windows contrast:** The equivalent of Darwin would be if Microsoft open-sourced the NT kernel, HAL, and Winsrv — which they have not. Windows Driver Kit (WDK) is public; the kernel source itself is not. Darwin's open-source nature is a significant forensic advantage: you can read the actual data structure definitions for task_t, proc_t, vnode_t, etc.

### 2. XNU: "X is Not Unix" — The Hybrid Kernel

"XNU" is recursive: **X is Not Unix**. It is a hybrid kernel — not a pure microkernel, not a monolithic kernel, but a deliberate fusion. The name reflects that it offers Unix POSIX compatibility while its core is Mach.

XNU's source tree has four primary subdirectories that map directly to its architecture:

```
xnu/
├── osfmk/      ← Mach kernel (OS Foundation Micro-Kernel)
├── bsd/        ← BSD subsystems (POSIX, VFS, network stack, signals)
├── iokit/      ← IOKit driver runtime
├── libkern/    ← C++ runtime for kexts and IOKit
├── libsyscall/ ← Userspace syscall stubs
├── security/   ← MAC (Mandatory Access Control) policy interfaces
└── pexpert/    ← Platform Expert (hardware-specific initialization)
```

All four layers execute in the same address space — this is what makes it a hybrid rather than a true microkernel. Mach's design philosophy is present, but IPC between kernel components is direct function calls, not inter-process message passing.

---

### 3. The Mach Layer (`osfmk/`)

Mach was developed at Carnegie Mellon University in the 1980s as a research microkernel. Apple licensed it from CMU via NeXT. The Mach component provides XNU's lowest-level primitives:

#### Tasks and Threads

- A **Mach task** is a container of resources: a virtual address space (`vm_map_t`), a set of ports, and one or more threads. It has no concept of a PID — that is a BSD overlay.
- A **Mach thread** is the unit of execution. Each thread has a register state, a stack, and an exception port.
- A **BSD process** (`proc_t`) wraps a Mach task. The BSD layer adds PID, UID/GID, file descriptors, signals, and the POSIX process model on top of the Mach task primitives.

This dual-personality design means every macOS process has *two* identities simultaneously:
- A BSD PID you see in `ps` and `Activity Monitor`
- A Mach task port that kernel subsystems use for IPC and VM operations

#### Mach Ports and IPC

**Mach ports** are the kernel's fundamental IPC mechanism. A port is a kernel-managed, capability-named, unidirectional message queue:

- Every kernel object (task, thread, VM region, IOKit service) has a **port**.
- A process holds *port rights* (send, receive, send-once) — not direct object references.
- The kernel mediates all communication. A process that holds a task's *send right* can inject threads, read/write VM, and alter exception handling.

```
User Process A                     Kernel                     User Process B
  [send right] ──→ Mach msg ──→ [port queue] ──→ Mach msg ──→ [recv right]
```

This is why Mach port analysis is central to macOS privilege escalation research: acquiring a **task port** for a privileged process is equivalent to owning that process.

#### Virtual Memory (`osfmk/vm/`)

Mach's VM subsystem provides:

- **`vm_map_t`** — per-task virtual address space descriptor
- **Memory objects** — abstract backing stores (files, anonymous memory, shared memory)
- **VM regions** — mapped segments with permissions; `vmmap -v <pid>` exposes the full region list
- **Shared Memory Cache** — the **dyld shared cache** (`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/`) is a Mach VM construct: a pre-linked image of all system frameworks mapped copy-on-write into every process

#### Mach Scheduler

XNU uses a **multi-level feedback queue** scheduler with Quality of Service (QoS) classes layered over it. The QoS classes (`QOS_CLASS_USER_INTERACTIVE` down to `QOS_CLASS_BACKGROUND`) are Mach-level concepts that translate into thread priority bands.

---

### 4. The BSD Layer (`bsd/`)

The BSD layer is XNU's POSIX personality, derived substantially from **FreeBSD** (not Linux, not macOS's own invention). It provides:

| Subsystem | What it provides |
|---|---|
| **Process model** | `fork()`, `exec()`, `wait()`, `exit()`, PIDs, process groups, sessions |
| **File system (VFS)** | The Virtual File System switch — a unified inode/vnode abstraction over APFS, HFS+, NFS, SMB, devfs, and more |
| **Network stack** | BSD socket API, TCP/IP (derived from BSD Net/3), `kqueue` event notification |
| **Signals** | POSIX signals layered over Mach exceptions |
| **Users & Groups** | UID/GID, file permissions, setuid/setgid |
| **sysctl** | The kernel's self-reporting interface — tunable and readable kernel state |
| **Audit** | BSM (Basic Security Module) audit trail — `/var/audit/` |

> 🪟 **Windows contrast:** The Windows NT kernel has no true BSD or POSIX layer — WSL2 is a Linux VM, not kernel integration. The NT Executive has an I/O Manager and Object Manager in place of VFS+vnodes. Signals don't exist in NT; Windows uses structured exception handling (SEH) and asynchronous procedure calls (APCs) instead.

> 🔬 **Forensics note:** The BSD `sysctl` interface is a goldmine. `sysctl -a` dumps thousands of kernel state variables — kernel version, memory stats, process ancestry, security policy flags, network interface counters — all without elevated privileges. Many post-exploitation tools enumerate `sysctl` values to fingerprint the OS and detect sandboxes.

---

### 5. IOKit and the Driver Runtime (`iokit/`, `libkern/`)

**IOKit** is XNU's object-oriented driver framework. It is written in a restricted subset of C++ called **libkern C++** (no exceptions, no RTTI, explicit reference counting via `OSObject`). Every hardware device visible to macOS is represented as an **IOKit object** in the **IORegistry** — a live, queryable tree.

```
IORegistryEntry (root)
  └── IOPlatformExpertDevice (the machine itself)
        ├── AppleARMIODevice (ARM peripherals)
        │     ├── AppleM1CPU
        │     └── AppleSMC
        └── IOPCIBridge
              └── AppleEthernetController
```

Access this tree live:

```bash
ioreg -l                          # full tree, verbose
ioreg -rc IOUSBDevice             # all USB devices
ioreg -n AppleSmartBattery -rd 1  # battery details
```

**Kernel Extensions (kexts)** historically lived in this model: a kext is a Mach-O bundle (`.kext`) containing an Info.plist and a kernel binary that gets loaded directly into the kernel's address space. A kext crash panics the machine. A kext security vulnerability gives an attacker ring 0 (EL1 on Apple Silicon).

---

### 6. Kexts vs. System Extensions: The Architecture Shift

Apple began deprecating third-party kexts in earnest starting with **macOS Catalina (10.15, 2019)**. The migration has proceeded in stages:

| macOS Version | Change |
|---|---|
| **Catalina (10.15)** | System Extensions + DriverKit introduced; kext KPIs officially deprecated; user warned at load |
| **Big Sur (11)** | Third-party kexts using deprecated KPIs blocked by default on Apple Silicon under Full Security; user approval required |
| **Monterey 12.3** | Audio, Bluetooth, and SCSI kexts must migrate to DriverKit families |
| **Sequoia (15)** | Legacy networking and USB KPIs removed entirely; FSKit ships for user-space file system implementations |
| **Tahoe (26)** | DriverKit ecosystem mature; APFS driver itself substantially updated (2811.x build in 26.4); most remaining third-party kexts from security vendors now use Endpoint Security or Network Extensions |

#### The Replacement Stack

Instead of kexts loading into the kernel, Apple now runs driver and security code in **user space** under tight sandboxes:

```
                        ┌─────────────────────────┐
   User Space (EL0)     │  Your App / CLI Tool     │
                        ├─────────────────────────┤
                        │  System Extension        │  ← replaces kext
                        │  (sandboxed process)     │
                        │  ┌─────────────────────┐ │
                        │  │ DriverKit dext      │ │  ← device driver in userspace
                        │  │ Network Extension   │ │  ← VPN, DNS proxy
                        │  │ Endpoint Security   │ │  ← AV, EDR, MDM events
                        │  └─────────────────────┘ │
                        └───────────┬─────────────┘
   Kernel Space (EL1)               │  (thin bridge kext / ES framework)
                        ┌───────────▼─────────────┐
                        │        XNU kernel        │
                        └─────────────────────────┘
```

**System Extension types** (registered under `com.apple.system_extension.*`):

- `endpoint-security` — EDR/AV event stream (process execs, file opens, network connections)
- `network-extension` — VPN tunnels, transparent proxies, DNS resolvers, content filters
- `driver-extension` (DriverKit `.dext`) — user-space device drivers for USB, audio, SCSI, PCI, networking

**Endpoint Security (ES)** specifically: a subscription-based event model where an ES client calls `es_new_client()` and subscribes to event types (`ES_EVENT_TYPE_NOTIFY_EXEC`, `ES_EVENT_TYPE_AUTH_OPEN`, etc.). The ES framework is backed by a kernel-resident kext (`com.apple.driver.EndpointSecurity`) that bridges events into user space. This is what CrowdStrike Falcon, SentinelOne, Carbon Black, and similar EDR products use on modern macOS.

> 🔬 **Forensics note:** If you find an `endpoint-security` System Extension active on a machine, you are looking at installed EDR/AV software. If you find a `network-extension`, you are looking at VPN, proxy, or firewall software. These are *high-value artifacts* during incident response — they indicate what monitoring was present (or wasn't) and what security controls could be evaded or subverted.

> 🪟 **Windows contrast:** Windows uses WDM/WDF drivers in kernel mode (similar to old kexts) plus user-mode drivers via UMDF. The Kernel Patch Protection (PatchGuard) on 64-bit Windows blocks unsigned kernel patches but does not prevent all unsigned driver loading (hence vulnerable driver abuse). Apple Silicon's Full Security mode is architecturally stricter: the Secure Enclave co-signs the boot policy and the kernel will not load unsigned kexts regardless of OS-level bypass attempts.

---

### 7. Apple Silicon Security Integration

On **M-series Macs**, the kext/sysext architecture is enforced at the hardware level through the **Secure Enclave Processor (SEP)** and the startup security policy stored in LocalPolicy:

- **Full Security** (default): Only Apple-signed kexts load. Third-party kexts require downgrade to Reduced Security + explicit user approval through `systempreferences://` → Privacy & Security, *and* a reboot into recoveryOS to authorize.
- **Reduced Security**: Signed third-party kexts allowed with user approval.
- **Permissive Security**: Unsigned kexts allowed; CSR (SIP) can be disabled.

Changing security level requires **booting recoveryOS with the machine powered off** then selecting Options → Startup Security Utility. There is no runtime OS command that can downgrade security level unilaterally — the LocalPolicy update requires the SEP to sign the new policy.

> 🔬 **Forensics note:** On Apple Silicon, a machine with legacy third-party kexts loaded *must* be running in Reduced or Permissive Security. This is itself a forensic signal — it means either the machine is legitimately running old security software (check `kextstat`/`kmutil`), or security was intentionally downgraded. You can read the current security policy state from `bputil -d` or from the recovery-logged boot policy in `/var/db/APFS/`.

---

### 8. The Darwin Version ↔ macOS Version Mapping

The **Darwin version** is not the macOS marketing version. XNU reports a Darwin version via `uname -r`:

| macOS Version | Darwin Kernel | XNU Build (approx) |
|---|---|---|
| macOS 12 Monterey | 21.x | xnu-8019.x |
| macOS 13 Ventura | 22.x | xnu-8792.x |
| macOS 14 Sonoma | 23.x | xnu-10002.x |
| macOS 15 Sequoia | 24.x | xnu-11215.x |
| macOS 26 Tahoe | 25.x | xnu-12377.x |

In Tahoe (macOS 26), the Darwin kernel version is **25.x** — the Darwin version lags the macOS marketing number by one, a quirk of the historical numbering that predates year-based OS names. XNU 12377.121.x is current as of Tahoe 26.5.1 (June 2026).

> 🔬 **Forensics note:** Kernel panic logs, crash reports, system logs, and even `.ips` crash files embed the Darwin kernel version string. A string like `Darwin Kernel Version 25.5.0: Thu Mar 20 20:18:00 PDT 2026; root:xnu-12377.120.72.0.4~13/RELEASE_ARM64_T8132` gives you the exact build date, the XNU build tag, the release variant (RELEASE vs DEVELOPMENT vs DEBUG), and the platform identifier (`T8132` = M4 Pro/Max SoC). This string is a reliable timeline anchor in forensic analysis.

---

## Hands-on (CLI & GUI)

### Identify Your Kernel

```bash
# Full kernel version string
uname -a
# Darwin Bronty-MacBook.local 25.5.0 Darwin Kernel Version 25.5.0: ...

# Just Darwin version number
uname -r
# 25.5.0

# Machine hardware and OS type
uname -m    # arm64  (or x86_64 on Intel)
uname -s    # Darwin

# The verbose sysctl version — same info, different path
sysctl kern.version
# kern.version: Darwin Kernel Version 25.5.0: ...

sysctl kern.osversion        # Build number, e.g. 25F5206g
sysctl kern.osproductversion # Marketing version: 26.5
sysctl kern.ostype           # Darwin
sysctl hw.machine            # arm64
sysctl hw.model              # Mac14,3 (maps to specific hardware SKU)
sysctl hw.ncpu               # logical CPU count
sysctl hw.physicalcpu        # physical core count
sysctl hw.memsize            # RAM in bytes
```

### Inspect Kernel Extensions

```bash
# Modern tool (macOS 12+): kmutil
kmutil showloaded                            # all loaded kexts
kmutil showloaded --show-property BundleID   # just bundle IDs
kmutil showloaded | grep -v com.apple        # non-Apple kexts only

# Legacy command (still works, deprecated)
kextstat
kextstat | grep -v com.apple.             # non-Apple kexts — the interesting ones

# Find kexts on disk
# Modern location (Apple Silicon + Big Sur+):
ls /System/Library/Extensions/            # Apple kexts (SIP-protected)
ls /Library/Extensions/                   # Third-party kexts (user-installed)

# The SIP-sealed system volume also contains kexts inside Cryptexes:
ls /System/Volumes/Preboot/Cryptexes/OS/System/Library/Extensions/
# This is the real Apple kext location on sealed volumes
```

> ⚠️ **Note on `/System/Library/Extensions/` visibility:** On macOS Big Sur and later with a sealed system volume, `/System/Library/Extensions/` is a *firmlink* that points into the Cryptex-backed sealed snapshot. What you see may not reflect what is loaded if the sealed system volume has been modified or if you are analyzing an offline disk image. Always cross-reference `kmutil showloaded` (live) against disk paths (offline).

### Inspect System Extensions

```bash
# List all installed System Extensions
systemextensionsctl list

# Expected output columns:
# enabled  active  teamID  bundleID  (version)  name
# ---      ---     ---     ---       ---         ---
# *        *       ABCD1234  com.crowdstrike.falcon.Agent (7.15.0)  Falcon

# What categories mean:
# endpoint-security: EDR/AV
# network-extension: VPN, proxy, DNS
# driver-extension: DriverKit hardware driver
```

### Inspect the IORegistry

```bash
# Full IOKit device tree (verbose — pipe to less)
ioreg -l | less

# Find USB devices
ioreg -rc IOUSBDevice -d 3

# Find audio devices
ioreg -rc IOAudioDevice

# Find PCI devices
ioreg -rc IOPCIDevice -d 2

# Read specific property of a named entry
ioreg -n IOPlatformExpertDevice -d 1 | grep -E "board-id|product-name|IOPlatformSerialNumber"

# GUI equivalent
/System/Applications/Utilities/System\ Information.app
# → Hardware tree on the left, registry details on the right
```

### Inspect Mach Tasks and Ports (Advanced)

```bash
# Map virtual memory regions of a process
vmmap -v <pid>
vmmap -v $(pgrep -x Finder) | head -60

# Show Mach port summary for a process (requires entitlement or root)
lsmp -p <pid>

# Show task/thread info
sudo dtrace -n 'BEGIN { printf("task=%p\n", (uintptr_t)curthread->t_task); exit(0); }'

# Process info including Mach task port
proc_info() { python3 -c "import ctypes, ctypes.util; ..."  }
# Easier: use the 'lsmp' tool from Apple's developer tools
xcode-select --install  # installs lsmp, heap, leaks, malloc_history
```

### sysctl Deep Dive

```bash
# Dump all sysctl variables (thousands)
sysctl -a 2>/dev/null | wc -l          # count
sysctl -a 2>/dev/null | grep kern.     # kernel variables
sysctl -a 2>/dev/null | grep hw.       # hardware variables
sysctl -a 2>/dev/null | grep net.      # network tuning
sysctl -a 2>/dev/null | grep vm.       # VM tuning
sysctl -a 2>/dev/null | grep security. # SIP/security flags

# SIP status via sysctl
sysctl -n security.mac.amfi.hsp_enable    # AMFI (Apple Mobile File Integrity) enforcement
csrutil status                             # SIP on/off (requires SIP to be partially off to even query from some contexts)

# Security-relevant kernel flags
sysctl kern.bootargs          # kernel boot arguments (often restricted under SIP)
sysctl kern.securelevel       # BSD securelevel (usually -1 on modern macOS)
```

---

## 🧪 Labs

### Lab 1: Map Your Kernel's Version to the Source Tree

> ⚠️ **ADVANCED:** Read-only; no risk. No rollback needed.

1. Run `uname -a` and record the XNU build string (e.g., `xnu-12377.121.6~2`).
2. Go to [github.com/apple-oss-distributions/xnu/tags](https://github.com/apple-oss-distributions/xnu/tags) and find the matching tag.
3. Browse `osfmk/kern/task.c` — find the `task_create_internal()` function. This is how every process on your machine is born.
4. Browse `bsd/kern/kern_exec.c` — find `__mac_execve()`. This is what runs when any binary launches.
5. Cross-reference what you see with `dtrace -n 'proc:::exec-success { printf("%s\n", execname); }'` running live.

**Expected insight:** You can trace every exec on your live machine to the exact kernel source line it flows through.

---

### Lab 2: Enumerate Non-Apple Kernel Code

> ⚠️ **ADVANCED:** Read-only enumeration. No modifications, no rollback needed.

```bash
echo "=== Loaded third-party kexts ==="
kmutil showloaded | grep -v com.apple | grep -v "BUNDLE ID"

echo ""
echo "=== Installed third-party kexts on disk ==="
ls -la /Library/Extensions/ 2>/dev/null
ls -la ~/Library/Extensions/ 2>/dev/null   # rarely populated

echo ""
echo "=== System Extensions ==="
systemextensionsctl list

echo ""
echo "=== Correlating sysexts with running processes ==="
# System Extensions run as processes under their bundle ID
ps aux | grep -E "\.agent|\.extension|\.helper" | grep -v grep
```

For each non-Apple entity you find:
- Identify the vendor from the bundle ID reverse-domain.
- Classify it: EDR? VPN? Audio driver? Backup software?
- Note whether it appears in *both* `kmutil` (kernel-space kext) *and* `systemextensionsctl` (user-space replacement) — overlap indicates a vendor in mid-migration.

> 🔬 **Forensics note:** In an incident response context, this lab is your "what security tools were present?" enumeration. Document every non-Apple kext and sysext. If the machine has no EDR sysext and no endpoint-security registration, that is a significant gap. If there is an unfamiliar bundle ID (e.g., `io.malicious.kext`), that warrants deep analysis.

---

### Lab 3: Read a Kernel Panic Log

> ⚠️ **ADVANCED:** Read-only. No rollback needed. If you have no panic logs, the commands will return nothing — that's fine.

```bash
# Panic logs live here
ls /Library/Logs/DiagnosticReports/ | grep panic
ls ~/Library/Logs/DiagnosticReports/ | grep panic

# Read the most recent one
PANIC=$(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1)
if [[ -n "$PANIC" ]]; then
    # Extract key fields
    grep -E "Darwin Kernel Version|xnu-|Panicked task|Backtrace|Thread" "$PANIC" | head -30
fi
```

In a real panic log, identify:
1. The XNU build string (first line — gives you exact kernel version and build date)
2. The `Panicked task` line — which process triggered the panic
3. The backtrace symbol that preceded `panic()` — often implicates a kext by bundle ID
4. The `Loaded kexts` section at the bottom — full inventory of what was loaded at panic time

> 🔬 **Forensics note:** A panic log is the kernel's own death record. For investigators, the `Loaded kexts` list in a panic log is forensically significant even if the panic itself is unrelated to the kexts — it is a point-in-time snapshot of what kernel code was running on this machine at this moment.

---

### Lab 4: Explore the IORegistry for Hardware Fingerprinting

> ⚠️ **ADVANCED:** Read-only. No rollback needed.

```bash
# Extract the hardware serial number (useful for asset tracking / chain of custody)
ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}'

# Extract the machine model identifier
sysctl -n hw.model    # e.g., Mac14,3

# Cross-reference model ID to human name
curl -s "https://support.apple.com/en-us/111893" | \
  grep -A2 "$(sysctl -n hw.model)" | head -5
# Or: system_profiler SPHardwareDataType

# Enumerate every USB device by name and vendor ID — useful for peripheral inventory
ioreg -rc IOUSBDevice -d 3 | grep -E '"USB Product Name"|"idVendor"|"idProduct"' | \
  paste - - - | column -t

# Find the Secure Enclave Processor entry
ioreg -rc AppleKeyStore | grep -A5 "class AppleKeyStore"
```

> 🔬 **Forensics note:** `IOPlatformSerialNumber` from `ioreg` is the ground-truth hardware serial — it comes directly from the Secure Enclave/T2, not from software configuration. If a macOS installation has been cloned or imaged, `sw_vers` might lie about the build, but `ioreg` doesn't — it reads from immutable hardware registers. Use this for chain-of-custody documentation on seized Apple Silicon hardware.

---

## Pitfalls & Gotchas

**Darwin version ≠ macOS version.** `uname -r` on Tahoe 26.x returns `25.x.x` — the Darwin version is always one less than the macOS marketing major. Searching for "Darwin 26" will find nothing useful; search for "Darwin 25" or "xnu-12377".

**`kextstat` is deprecated but not removed.** It still works in Tahoe 26 but reports via a compatibility shim. Prefer `kmutil showloaded`. `kextstat` also shows kext index numbers that `kmutil` does not — useful when cross-referencing panic backtraces.

**`/System/Library/Extensions/` is not the real Apple kext location.** Under the sealed system volume model, Apple kexts live inside a Cryptex (a signed, mounted disk image) at `/System/Volumes/Preboot/Cryptexes/OS/`. The `/System/Library/Extensions/` path is a firmlink into the sealed snapshot. When analyzing an offline disk image in a forensic tool, look for the Cryptex mount points or the preboot volume.

**System Extension activation is non-trivial.** Installing an app that contains a System Extension does not activate it — the app must call `OSSystemExtensionRequest.activationRequest()`, and the user must approve in System Settings → Privacy & Security. A vendor's app present on disk does not mean its System Extension is active. Check `systemextensionsctl list` for `enabled` and `active` status separately.

**Mach port attacks are silent.** Unlike traditional syscall-based exploits, Mach port operations don't go through the BSD audit subsystem. They are not in `/var/audit/`. Detecting task-port-based privilege escalation requires Endpoint Security event subscription to `ES_EVENT_TYPE_NOTIFY_MACH_LOOKUP` or custom kernel instrumentation — not `/var/log/system.log`.

**Apple Silicon vs Intel for kext loading.** On Intel Macs without a T2 chip, you can load unsigned kexts with SIP disabled and a reboot — no SEP policy update required. On Apple Silicon (and T2 Intel Macs), you must boot recoveryOS to change the security policy. The attack surface for unsigned kernel code is substantially smaller on Apple Silicon.

**`dtrace` requires SIP modification.** DTrace probes on macOS require `csrutil enable --without dtrace` (from recoveryOS) on Apple Silicon with SIP enabled. Many kernel-level DTrace probes are simply unavailable under Full Security — this is by design.

---

## Key Takeaways

1. **Darwin = XNU kernel + FreeBSD userland + launchd.** Not Linux. Not Windows. The BSD lineage means POSIX compliance but the Mach core means fundamentally different IPC, VM, and process semantics.

2. **XNU is a hybrid kernel.** Mach provides tasks, threads, ports, IPC, and VM. BSD provides POSIX, VFS, sockets, and signals. IOKit provides device drivers. All three execute in the same address space — it is hybrid in philosophy, not in address space separation.

3. **Mach ports are the kernel's nervous system.** Every kernel object is reachable via a port right. Owning a task's send right means owning the process. Most macOS local privilege escalation research targets Mach port manipulation.

4. **Kexts are deprecated and restricted on Apple Silicon.** The modern stack is System Extensions (user-space processes) backed by thin Apple bridge kexts. For forensics: non-Apple kexts still loaded are either legacy software or security tools that haven't migrated.

5. **`systemextensionsctl list` tells you what security software is present.** `endpoint-security` entries = EDR/AV. `network-extension` entries = VPN/proxy. This is the first command to run in security posture assessment.

6. **Darwin version = macOS marketing major − 1.** Tahoe 26 → Darwin 25 → XNU 12377.x.

7. **The XNU build string is a forensic timestamp.** Embedded in crash logs, panic logs, and `.ips` files, it pinpoints exact kernel version, build date, and hardware platform.

8. **`sysctl` is the kernel's reporting API.** No root required for most reads. Use it to enumerate hardware, OS version, security policy flags, and VM parameters in any investigation.

---

## Terms Introduced

| Term | Definition |
|---|---|
| **Darwin** | The open-source OS foundation of macOS: XNU + BSD userland + launchd |
| **XNU** | "X is Not Unix" — the hybrid kernel combining Mach + BSD + IOKit |
| **Mach task** | Kernel resource container (VM map + ports + threads); the substrate under a BSD process |
| **Mach thread** | The unit of execution within a task; has register state + stack |
| **Mach port** | Kernel-managed IPC capability — a named, unidirectional message queue; the universal kernel object handle |
| **Port right** | A capability token granting send, receive, or send-once access to a Mach port |
| **vm_map_t** | The Mach data structure representing a task's virtual address space |
| **IOKit** | Apple's C++ driver framework embedded in XNU; exposes hardware via the IORegistry tree |
| **IORegistry** | The live tree of all hardware and driver objects managed by IOKit |
| **kext** | Kernel Extension — a Mach-O bundle loaded into the kernel address space (deprecated for third parties) |
| **System Extension** | A user-space replacement for kexts: sandboxed process registered via `systemextensionsctl` |
| **DriverKit (.dext)** | User-space device driver runtime; a System Extension subtype replacing IOKit kexts |
| **Endpoint Security** | Apple framework for subscribing to security-relevant kernel events from user space (the modern AV/EDR interface) |
| **Network Extension** | System Extension subtype providing VPN tunnels, DNS proxies, content filters |
| **Cryptex** | A cryptographically sealed, signed disk image containing Apple OS components; mounts at boot to form the sealed system volume |
| **sysctl** | BSD kernel interface for reading and (with root) writing kernel state variables |
| **dyld shared cache** | Pre-linked image of all system frameworks; a Mach VM construct mapped COW into every process |
| **LocalPolicy** | Apple Silicon per-machine boot policy document signed by the Secure Enclave; controls kext/SIP authorization |
| **KPI** | Kernel Programming Interface — the set of kernel functions and data structures available to kext developers |
| **FreeBSD** | The BSD Unix variant whose userland and network stack form Darwin's POSIX personality |
| **launchd** | PID 1 on macOS; replaces init, inetd, crond; manages the entire service, agent, and socket-activation graph |

---

## Further Reading

- **Apple Platform Security Guide** — [support.apple.com/guide/security](https://support.apple.com/guide/security/welcome/web) — definitive source on Secure Enclave, LocalPolicy, and the kernel trust chain
- **XNU Source** — [github.com/apple-oss-distributions/xnu](https://github.com/apple-oss-distributions/xnu) — `osfmk/kern/task.c`, `bsd/kern/kern_exec.c`, `iokit/Kernel/IOService.cpp`
- **Howard Oakley / Eclectic Light Company** — [eclecticlight.co](https://eclecticlight.co) — best practical writing on macOS internals changes per release; especially kext/sysext migration series
- **"Mac OS X and iOS Internals"** — Jonathan Levin (Technologeeks) — the deepest publicly available treatment of XNU internals; companion `jtool2` is invaluable
- **HackTricks macOS** — [hacktricks.wiki/en/macos-hardening](https://hacktricks.wiki/en/macos-hardening/) — attacker-perspective enumeration; read it to understand what adversaries enumerate
- **Apple Developer: System Extensions** — [developer.apple.com/system-extensions/](https://developer.apple.com/system-extensions/) — official migration guide from kexts
- **Endpoint Security Framework** — [developer.apple.com/documentation/endpointsecurity](https://developer.apple.com/documentation/endpointsecurity) — event types, client API, entitlement requirements
- **Red Canary Mac Monitor** — [github.com/redcanaryco/mac-monitor](https://github.com/redcanaryco/mac-monitor) — GUI ES event viewer; excellent for learning what kernel events look like in practice

**Next lesson:** [[01-boot-process]] — from power button to your first shell prompt: iBoot, Secure Enclave, UEFI remnants, boot policy, and the launchd service graph.
