---
title: "XNU on mobile"
part: "02 — System Architecture & Internals"
lesson: 00
est_time: "50 min read + 20 min labs"
prerequisites: [soc-lineup-and-device-matrix]
tags: [ios, kernel, xnu, darwin, mach, bsd]
last_reviewed: 2026-06-26
---

# XNU on mobile

> **In one sentence:** iOS and macOS run the *same* XNU source tree — Mach + BSD + IOKit — but mobile ships it as a single prelinked, signed `MH_FILESET` kernelcache with loadable kexts, DTrace, arbitrary `fork`/`exec`, and almost all task-port debugging surgically removed or compiled out, which is exactly why the kernelcache extracted from an IPSW is the substrate for all iOS kernel reverse engineering.

## Why this matters

You already know XNU from `macos-mastery` — Mach for tasks/threads/ports/VM, BSD for processes/sockets/VFS, IOKit for drivers, all bootable as a kernel that loads `.kext` bundles at runtime and that you can poke at with `dtrace`, `lldb`, and `task_for_pid`. On iOS, the *kernel is the same code* but the *posture is the opposite*: nothing loads at runtime, nothing is debuggable from userland, and every executable page must trace back to a signature the kernel trusts. For a forensic examiner that posture is the whole ballgame — it determines what you can acquire, what a jailbreak has to defeat, and how you prove a kernel was tampered with. For a reverse engineer, the kernelcache is the *only* artifact you get: there is no `/System/Library/Kernels/kernel` you can pull off a running phone, no symbols, no kexts on disk. You download an IPSW, unwrap an Image4 payload, decompress it, and walk a `MH_FILESET` Mach-O. This lesson is the on-disk anatomy of that artifact and the mechanics of getting it.

## Concepts

### One source tree, two postures

Apple builds macOS and iOS from a single XNU source tree. The public mirror is [`github.com/apple-oss-distributions/xnu`](https://github.com/apple-oss-distributions/xnu) (the old `apple/darwin-xnu` is a legacy mirror). The top-level layout is identical to what you studied on the desktop:

| Component | Directory | Responsibility |
|---|---|---|
| **Mach** | `osfmk/` | Tasks, threads, ports, IPC, VM, scheduler, timers. The microkernel core (CMU Mach 2.5/3.0 lineage). |
| **BSD** | `bsd/` | Processes (PIDs), signals, the syscall table, sockets, VFS, `kauth`/MACF policy hooks. FreeBSD-derived. |
| **IOKit** | `iokit/` | The C++ driver runtime — `IORegistry`, `IOService` matching, driver personalities. |
| **libkern** | `libkern/` | The restricted C++ runtime kexts are written against; OSObject, `OSKext`, libkmod. |
| **Pexpert** | `pexpert/` | Platform expert — early board bring-up, the device tree, boot-args parsing. |
| **libsa / libsyscall / security** | `libsa/`, `libsyscall/`, `security/` | Early-boot kext linker, the userland syscall stubs, the MACF (`mac_*`) framework. |

The "hybrid kernel" layering is identical to the desktop — a Mach core with a BSD personality bolted on in the *same address space*, plus IOKit for drivers:

```
        ┌───────────────────────────────────────────────────────┐
  user  │  apps / daemons (XPC over Mach) · libsyscall stubs     │
        └───────────────────────────────────────────────────────┘
        ════════ svc #0x80 (x16 = call number) ════════════════════
        ┌───────────────────────────────────────────────────────┐
        │  BSD  (bsd/)   processes, signals, VFS, sockets, MACF  │
        │  ───────────────────────────────────────────────────  │
 kernel │  IOKit (iokit/) + libkern  ── C++ drivers / kexts      │
        │  ───────────────────────────────────────────────────  │
        │  Mach (osfmk/)  tasks · threads · ports/IPC · VM · sched│
        └───────────────────────────────────────────────────────┘
        ┌───────────────────────────────────────────────────────┐
        │  Pexpert (pexpert/)  device tree · board bring-up      │
        └───────────────────────────────────────────────────────┘
   A15+/M2+ only:  Mach VM/pmap calls out to ↓ (separate binaries, NOT in kernelcache)
        ┌───────────────────────────────────────────────────────┐
        │  SPTM / TXM monitors  (page-table & code-signing gate) │
        └───────────────────────────────────────────────────────┘
```

The ARM64 port lives under `osfmk/arm64/` (and, on A15/M2 and later, `osfmk/arm64/sptm/` — the XNU-side glue that hands control to the **SPTM/TXM** monitors; the monitor binaries themselves are *not* in the XNU tree and *not* in the kernelcache). So when you read `osfmk/arm/pmap/pmap.c` (the classic/PPL pmap; the SPTM-era page-table code lives under `osfmk/arm64/sptm/pmap/`) you are reading the literal code that manages page tables on the iPhone in your evidence bag. The version string baked into a release kernel looks like:

```
Darwin Kernel Version 25.5.0: <date>; root:xnu-12377.121.x/RELEASE_ARM64_T8150
```

— `xnu-NNNNN.x` is the source tag, `RELEASE_ARM64_T<chip>` names the build variant and SoC (`T8150` ≈ A19-class; exact chip→Txxxx mapping is in [[soc-lineup-and-device-matrix]]). iOS 26 is the **Darwin 25** generation, the same major Darwin version as macOS 26 "Tahoe" — the two kernels have re-converged tightly.

> ⚠️ **Verify at author time:** the exact `xnu-` source tag and `Darwin Kernel Version 25.x.0` for a specific iOS 26.x point release change every cycle. Darwin 25 (iOS 26 / macOS 26 "Tahoe") is the **`xnu-12377`** family — e.g. macOS 26.5 is `Darwin Kernel Version 25.5.0 … root:xnu-12377.121.x` — but the trailing build component (and any small iOS↔macOS suffix delta) you read out of the *actual* kernelcache (`ipsw kernel version …`, shown below), never from memory. The durable facts are the *format* of the string, the `xnu-12377` base for this generation, and the Darwin-25 ≈ iOS-26 mapping.

> 🖥️ **macOS contrast:** In `macos-mastery` you treated the kernel as a thing you could rebuild from source (`make`), boot with `kcgen`/`kmutil`, attach to over a KDK, and instrument with DTrace. Same source, same `uname -a` shape — but on macOS the kernel is *one posture of a debuggable workstation OS*, and on iOS it's a *sealed appliance*. Nearly everything below is a list of affordances Apple kept on the Mac and removed on the phone.

### What mobile removes or locks down

The differences are not forks of the code — they are configuration, compiled-out subsystems, entitlement gates, and a hardened build. The big five:

```
                 macOS (Tahoe)                    iOS / iPadOS 26
                 ─────────────                    ───────────────
KEXTs        →   loadable at boot via kmutil;     static kernel collection only;
                 user/aux kext collection;        NO runtime/aux load; NO 3rd-party
                 kextload (with SIP off)           kexts AT ALL

DTrace       →   /dev/dtrace, fbt/sdt/pid          dtrace.kext absent; providers
                 providers, `dtrace -n …`          compiled out — no kernel tracing

task ports   →   task_for_pid(pid) with            task_for_pid gated to self / a
                 taskgated + entitlement;          handful of Apple daemons; no
                 processor_set_tasks debug         arbitrary-process task port → no
                                                   userland kernel debugger

exec model   →   fork()+exec() any binary you      posix_spawn only of *already-
                 can read; /bin/sh; JIT freely     signed, on-system* binaries; no
                                                   user shell; no unsigned exec pages

code sign    →   AMFI present but advisory for     AMFI + CoreTrust MANDATORY; every
                 many paths; SIP-gated;            executable page must validate to a
                 unsigned binaries run             trusted signature or trust cache
```

**1. No loadable third-party kexts.** Modern macOS already moved away from on-the-fly `kextload`: drivers ship as DriverKit system extensions in userspace, and the few remaining true kexts are linked into a *boot kernel collection* by `kmutil create` and require a reboot plus reduced security. iOS takes this to the limit: there is exactly **one** kernel collection, the boot one, built at Apple, and **no auxiliary collection and no runtime load path exists at all**. Every driver the device will ever run is prelinked into the kernelcache before it ships. This is *the* structural fact that produces the kernelcache format (next section).

**2. No DTrace.** `dtrace.kext` is not in the iOS kernelcache and the FBT/SDT/syscall providers are compiled out. There is no `/dev/dtrace`, no `dtrace(1)`, no `dtruss`. Whole categories of macOS dynamic analysis simply do not exist on-device; you replace them with Frida against userland (covered in Part 11) or with static analysis of the kernelcache.

**3. Severely restricted task ports.** `task_for_pid()` is the Mach call that hands you a send right to another process's task port — the key that unlocks `vm_read`/`vm_write` and therefore every userland debugger and memory dumper. On iOS the kernel/AMFI policy denies it for arbitrary targets: a process can get its *own* task port, a small set of Apple daemons (e.g. the crash reporter) are allowed by entitlement, and `task_for_pid(0)` (the kernel task) is unavailable to userland entirely. `processor_set_tasks()`, the old "enumerate every task" debugging backdoor, is likewise locked down. No arbitrary task port ⇒ no on-device kernel debugger ⇒ jailbreaks must obtain kernel read/write through a *bug*, not an API.

**4. No `fork`+`exec` of arbitrary binaries.** The classic Unix "write a binary, mark it executable, run it" loop is dead on iOS. `posix_spawn`/`execve` still exist in BSD, but AMFI refuses to map an executable region unless its pages validate against a code signature the kernel trusts. You cannot drop a Mach-O into a writable directory and run it — there is no user shell to try, and even if there were, the exec would be killed at `mmap(PROT_EXEC)` time. (The narrow exceptions — `get-task-allow`/`dynamic-codesigning` JIT entitlements, the `CS_DEBUGGED` path — are the foundation of debugging and are covered in [[code-signing-amfi-entitlements]].)

**5. Mandatory code signing, compiled into the kernel.** On the Mac, AMFI exists but many code paths are advisory and SIP-gated; you can run unsigned binaries. On iOS, **AppleMobileFileIntegrity (`AMFI.kext`) plus the lower-level `CoreTrust` validator are mandatory and non-optional**. Enforcement flags (`CS_ENFORCEMENT`, `CS_KILL`, `CS_HARD`) are set on essentially every process; a code-signing violation kills the process. The set of "trusted without an on-line check" hashes lives in **trust caches**: a *static trust cache* baked into the kernelcache itself (covering the platform binaries) plus loadable trust caches for the dyld shared cache and engineering builds. We unpack AMFI/CoreTrust/trust-caches properly in [[code-signing-amfi-entitlements]]; here the point is just that signing is *in the kernel image*, which is one more reason the kernelcache is the artifact you reverse.

> 🔬 **Forensics note:** Several "is this device clean?" questions reduce to *kernel integrity*. A stock iOS kernelcache is signed by Apple and byte-reproducible from the IPSW for that build. A `palera1n`/checkm8-class jailbreak patches the *running* kernel (e.g. neuters AMFI signature checks, opens an unsigned-exec hole) — it does not re-sign Apple's image. So comparing a recovered/running kernel against the known-good kernelcache for the matching build, or observing AMFI enforcement disabled, is a tamper indicator. Note the boundary from [[soc-lineup-and-device-matrix]]: **checkm8 only reaches A8–A11**; A12+ on iOS 18/26 has no public kernel-patching jailbreak, so on a modern handset a *patched* kernel is itself an anomaly worth explaining.

> 🖥️ **macOS contrast:** On macOS you weaken these one knob at a time — `csrutil disable` for SIP, `spctl --master-disable`, boot into reduced security in `bputil`/Recovery to allow third-party kexts. On iOS there are **no equivalent knobs**: there is no Recovery toggle that lets a third-party kext load or that makes `task_for_pid` work for arbitrary PIDs. The policy is the product.

### How user code enters the kernel (unchanged from macOS — and that's the point)

The *mechanism* by which userland reaches the kernel is identical to the Mac, which is why your macOS instincts transfer cleanly to reading an iOS kernelcache. On ARM64 there is a single trap instruction — **`svc #0x80`** — and register **`x16`** carries the call number:

```
x16 > 0   →  BSD/Unix syscall   → dispatched through the `sysent[]` table (bsd/kern/syscalls.master)
x16 < 0   →  Mach trap          → dispatched through `mach_trap_table[]` (osfmk/kern/syscall_sw.c)
x16 = 0   →  indirect syscall    (real number in x0)
```

So `open`, `read`, `mmap` are *positive* BSD syscalls; `mach_msg2_trap`, `task_self_trap`, `thread_get_special_reply_port` are *negative* Mach traps. Above this sits the **Mach IPC fabric**: almost everything interesting on iOS — `launchd` service lookups, **XPC**, sandbox checks, IOKit user-clients — is Mach messages flowing over ports. iOS leans on this *harder* than macOS: the whole daemon ecosystem ([[launchd-and-system-daemons]], [[processes-mach-xpc]]) is XPC-over-Mach. A read-only **comm page** (kernel-published timebase, CPU capabilities) is mapped into every process exactly as on the Mac.

The forensic and RE relevance: when you `ipsw kernel syscall <cache>`, you are dumping `sysent[]` *out of the static kernelcache* — the same table the chip dispatches through at runtime. Mapping a Mach trap or a syscall to its handler address in the cache is step one of understanding any kernel attack surface.

> 🖥️ **macOS contrast:** `bsd/kern/syscalls.master` and `osfmk/kern/syscall_sw.c` are the same files you read in `macos-mastery`; the generated `sysent[]`/`mach_trap_table[]` have the same shape. The difference is purely reachability — on macOS you can `dtrace -n 'syscall:::entry'` to watch the table live; on iOS you can only read it statically from the cache.

### Memory without a pager: jetsam, not swap

XNU's VM (`osfmk/vm/`) is the same code, but iOS configures it with a fundamentally different end-game under memory pressure. macOS pages anonymous memory out to a **swap file** (`/private/var/vm/swapfile*`) and only kills processes as a last resort. Classic iOS has **no swap file**: instead it relies on the **VM compressor** (compresses cold pages in RAM) plus **jetsam** — the `memorystatus` subsystem in `bsd/kern/kern_memorystatus*.c` that *terminates* processes by priority band when free memory crosses thresholds. Foreground apps sit in protected bands; suspended background apps are the first to be jetsammed (you see this as "the app reloaded when I switched back"). iPadOS on Apple-silicon iPads *can* use an on-disk swap file for heavy multitasking, narrowing the gap, but the priority-band-kill model still governs.

This is an *architecture* fact with downstream consequences across the course: jetsam events are logged (a pattern-of-life and crash-triage signal — [[memory-jetsam-app-lifecycle]], [[unified-logs-sysdiagnose-crash-network]]), and the absence of a swap file is one reason iOS has historically resisted certain cold-memory acquisition techniques.

> 🔬 **Forensics note:** Because classic iPhones don't write a swap file, you won't recover a `swapfile` artifact the way you might on macOS. Jetsam *terminations*, by contrast, **are** recorded — `JetsamEvent-*.ips` reports under the device's analytics/diagnostics tree capture per-process memory footprints and the kill reason at the moment of pressure, a useful (and easy to overlook) execution/timeline artifact. (Acquisition and parsing of `.ips` reports: [[unified-logs-sysdiagnose-crash-network]].)

### IOKit on mobile: the kernel's userland attack surface

IOKit is shared verbatim with macOS — the same C++ `IOService` matching, the same `IORegistry`, the same driver personalities — but on iOS it carries outsized RE weight because, with arbitrary syscalls locked behind the sandbox, **IOKit user-clients are the widest reachable kernel attack surface**. A sandboxed app reaches a driver by opening an `IOUserClient` (`IOServiceOpen`) and invoking numbered **external methods** (`IOConnectCallMethod` → the driver's `externalMethod`/`sMethods` dispatch table). Each method is a hand-written kernel routine taking attacker-influenced input — historically a rich seam of memory-corruption bugs (the lineage behind many public iOS kernel exploits and the `AppleAVE`/`IOMobileFrameBuffer`/`AGX` class of CVEs).

For the reverse engineer this is concrete guidance on *what to look at first* in the kernelcache: extract the driver kext, find its `externalMethod` dispatch, and enumerate the `IOExternalMethodDispatch` array — that's the reachable-from-userland boundary. The sandbox profile ([[the-sandbox-and-tcc]]) decides *which* user-clients a given app can even open, which is why sandbox-op enumeration (`ipsw kernel sbopts`) and IOKit method analysis go together.

> 🖥️ **macOS contrast:** Same IOKit, but on macOS many drivers are reachable from a normal process and you can introspect the live registry with `ioreg`/`IORegistryExplorer`. On iOS the registry is the same shape, but reachability is gated by the sandbox and you do the enumeration *statically* against the extracted kext — there's no on-device `ioreg`.

### The kernelcache: a prelinked `MH_FILESET`

Because nothing loads at runtime, iOS ships the kernel and every kext **fused into one Mach-O image**, fully linked, at build time. Its evolution:

- **Pre-iOS 12:** a "prelinked kernel" — the base kernel Mach-O with kexts appended into `__PRELINK_TEXT` / `__PRELINK_INFO` segments, symbols mostly present.
- **iOS 12+ (the format you'll meet today):** a **`MH_FILESET`** Mach-O (`filetype == 0xC`, `MH_FILESET`). This is a *container* Mach-O whose load commands include one **`LC_FILESET_ENTRY`** per member (the base kernel, named `com.apple.kernel`, plus every `com.apple.driver.*` / `com.apple.iokit.*` / `com.apple.security.*` kext). Each entry has its own embedded Mach-O header at a recorded `vmaddr`/`fileoff`. `__TEXT`, `__LINKEDIT`, and the prelink metadata are consolidated at the collection level. Modern release kernelcaches are **fully symbol-stripped**. (This is the very same `MH_FILESET` form `kmutil create` produces for the macOS boot kernel collection — convergence again.)

On disk inside an IPSW, the kernelcache is **wrapped in Image4** and **compressed**:

```
IPSW (.zip)
└── kernelcache.release.iPhone18,1        ← Image4 payload (.im4p)
    │
    ├─ ASN.1/DER Image4 envelope
    │    type tag  = "krnl"               ← 4CC marks it as the kernel payload
    │    (peers:  "ibot"=iBoot, "rkrn"=restore kernel, "rdsk"=ramdisk …)
    │
    └─ payload bytes (compressed):
         older builds:  "complzss"  header  → LZSS
         iOS 14+      :  "bvx2"/"bvxn" blocks → LZFSE
              │
              └─ decompress ──▶  MH_FILESET Mach-O (the kernelcache proper)
                                  ├ LC_FILESET_ENTRY com.apple.kernel
                                  ├ LC_FILESET_ENTRY com.apple.driver.AppleA7IOP
                                  ├ LC_FILESET_ENTRY com.apple.security.sandbox
                                  ├ … (hundreds of kexts)
                                  ├ __PRELINK_INFO  (plist: kext list, bundle IDs, UUIDs)
                                  └ embedded static trust cache
```

Two layers to peel, in order: **Image4 → decompress → Mach-O**. Image4 (`IMG4`) is Apple's ASN.1/DER secure-boot container; the kernelcache file in the IPSW is specifically an **`IM4P`** (Image4 *payload*) with the 4-character type **`krnl`**. (The matching **`IM4M`** manifest and **`IM4R`** restore-info — the personalized SHSH side — are covered in [[image4-personalization-shsh]]; for reverse engineering you only need the `IM4P`.) Concretely, an `IM4P` is a DER `SEQUENCE`:

```
IM4P ::= SEQUENCE {
  "IM4P"            IA5String      -- magic
  type              IA5String      -- "krnl"  (the 4CC; "ibot"/"rdsk"/… for peers)
  description       IA5String      -- e.g. "kernelcache"
  payload           OCTET STRING   -- the COMPRESSED Mach-O bytes
  (optional kbag)   OCTET STRING   -- keybag / compression hints
}
```

On a *production* kernelcache the payload `OCTET STRING` is **compressed but not encrypted** (Apple stopped encrypting the kernelcache years ago — the keybag is a remnant; iBoot still verifies it against the `IM4M` manifest's measurements at boot). The compression inside is **LZSS** with a `complzss` header on older builds, **LZFSE** (the `bvx2`/`bvxn`/`bvx-`/`bvx$` block magics) on modern ones — Apple moved the kernelcache to LZFSE across the **iOS 12–13 era** (the exact crossover varies by device line; e.g. some older models stayed LZSS into iOS 12.4.x), so treat **every iOS 14+ build as LZFSE**. `ipsw` (and `img4tool`/`jtool2`) handle both transparently — `ipsw kernel dec` does the DER parse *and* the decompress in one step.

> 🔬 **Forensics note:** The decompressed kernelcache carries the full **`Darwin Kernel Version …root:xnu-NNNN…/RELEASE_ARM64_T<chip>`** string in `__TEXT,__const`. That single string fingerprints **exact build + SoC** of a recovered cache — invaluable when you find a kernelcache on a backup/restore volume or in firmware and need to tie it to a device generation and an iOS build. The `__PRELINK_INFO` plist additionally enumerates every prelinked kext with bundle ID and UUID, a clean inventory of the trusted driver set for that build.

### Why the kernelcache is the RE substrate

There is no other kernel artifact you can get without already owning the device's secrets:

- **You cannot read the live kernel from userland** (no `task_for_pid(0)`), so there is no "dump the running kernel" path on a stock phone.
- **The on-device file is never plaintext on storage** in a way you can grab — it lives Image4-wrapped, and at runtime is loaded by iBoot into protected memory.
- **The IPSW is public.** Apple serves full IPSW/OTA firmware bundles for every shipping build, unauthenticated. That is the legitimate, repeatable source: download the IPSW, extract the `krnl` `IM4P`, decompress, and you hold a byte-for-byte copy of the kernel that runs on the target device — same SoC variant, same build.

So the entire iOS kernel-RE workflow — finding the syscall table, locating AMFI's signature-check routine, mapping the sandbox profile evaluator, diffing two builds to spot a silently-patched vulnerability — operates on the *extracted kernelcache*, statically, on your Mac. The rest of this lesson is how to get that artifact and crack it open; the disassembly itself is Part 11 ([[the-dyld-shared-cache]], [[static-analysis-class-dump-and-disassemblers]] and the kernel-specific follow-ons).

> 🖥️ **macOS contrast:** On Apple Silicon Macs the *same* `MH_FILESET` boot kernel collection lives at `/System/Volumes/Preboot/<UUID>/boot/<…>/System/Library/Caches/com.apple.kext.caches/Startup/` — you can copy it straight off the running Mac's filesystem. On iOS the only supply line is the IPSW, because the device filesystem is encrypted and the kernel is never sitting in the clear where you can `cp` it.

### Where it's built and how it boots

The collection is produced by Apple's build of **`kmutil create`** (the **KernelManagement** subsystem, `kernelmanagerd`/`kmutil` — the successor to the old `kextcache`/`kcgen`) — the *same* tool you can run on a Mac to make a boot kernel collection. On iOS, Apple builds it once per release; the device never relinks. At boot the chain is roughly:

```
SecureROM  →  iBoot  →  (A15+/M2+: SPTM/TXM monitors)  →  XNU kernelcache  →  launchd (PID 1)
                 │
                 └─ iBoot reads the IM4M manifest, checks the kernelcache's measurement
                    matches what's signed for THIS SoC/board (ECID-personalized), applies a
                    KASLR slide, then jumps in. AMFI's static trust cache (baked into the
                    cache) is now live and gates every userland exec.
```

Two consequences you'll feel constantly in RE: the **KASLR slide** means file offsets in your extracted cache are *not* the runtime virtual addresses (a single random slide is applied to the whole image at boot), and the **`IM4M` personalization** ([[image4-personalization-shsh]]) is why you can't just take a kernelcache from one build and boot it on a device running another — the manifest won't match. Full detail of the chain is [[boot-chain-securerom-iboot]]; for this lesson the takeaway is that the artifact you extract is the *input* to that chain, byte-identical to what iBoot maps.

> 🔬 **Forensics note:** Kernel **panic logs** (`panic-full-*.ips` in the device's analytics tree, recoverable via sysdiagnose or logical acquisition) record the panicking address, the loaded kernelcache UUID, and the **KASLR slide** in effect. With the slide you can subtract back to file offsets and **symbolicate against the matching extracted kernelcache** — turning a bare address into "panicked in `AppleAVE` external method N." This is how you reconstruct what a crashing/exploited driver was doing; it only works if you have the *exact* kernelcache for the build, which is the practical reason to archive every cache you extract. (Crash-report acquisition: [[unified-logs-sysdiagnose-crash-network]].)

## Hands-on

All commands run **on your Mac** — there is no on-device shell. The workhorse is **`ipsw`** (blacktop) — `brew install blacktop/tap/ipsw`. Levin's **`jtool2`** (newosxbook.com) and the LLVM **`otool`/`llvm-otool`** are useful cross-checks.

> ⚖️ **Authorization:** Downloading and analyzing IPSW firmware is *not* a forensic acquisition — it's public, Apple-served, device-independent data that touches no subject's device, so no warrant or consent is implicated. The legal/chain-of-custody line is crossed only when you go to the *device*: extracting the live kernel, imaging storage, or running a jailbreak are subject-device actions that require proper authorization and documentation ([[ios-forensics-landscape-and-authorization]]). Keep your kernelcache RE corpus (a research artifact) cleanly separated from case evidence.

```bash
# 0. (Optional) download the IPSW for a device straight from Apple's signing server.
#    Pick a device identifier from `ipsw device-list`.
ipsw download ipsw --device iPhone18,1 --latest --confirm
#   → iPhone18,1_26.x_<build>_Restore.ipsw   (multi-GB; legal, public firmware)

# 1. Pull JUST the kernelcache out of the IPSW (no full unzip needed).
ipsw extract --kernel iPhone18,1_26.x_<build>_Restore.ipsw
#   → 26.x_<build>__iPhone18,1/kernelcache.release.iPhone18,1   (an Image4 .im4p)

# 2. Read its version WITHOUT fully decompressing to a file.
ipsw kernel version kernelcache.release.iPhone18,1
#   Darwin Kernel Version 25.5.0: …; root:xnu-12377.121.x/RELEASE_ARM64_T8150
#   (also prints the detected compression: lzfse)

# 3. Decompress the Image4 payload → a raw MH_FILESET Mach-O.
ipsw kernel dec kernelcache.release.iPhone18,1
#   → kernelcache.release.iPhone18,1.decompressed

# 4. Confirm the Mach-O type — note MH_FILESET.
otool -h kernelcache.release.iPhone18,1.decompressed
#   magic=MH_MAGIC_64  cputype ARM64  filetype 12 (MH_FILESET)   …
#   (filetype 12 == 0xC == MH_FILESET)

# 5. Enumerate every prelinked kext (the fileset entries / __PRELINK_INFO inventory).
ipsw kernel kexts kernelcache.release.iPhone18,1.decompressed | head
#   com.apple.kernel
#   com.apple.driver.AppleA7IOP
#   com.apple.security.sandbox
#   com.apple.driver.AppleMobileFileIntegrity
#   …  (hundreds)

# 6. Carve ONE kext out as a standalone, loadable Mach-O (loads cleanly in IDA/Ghidra).
ipsw kernel extract kernelcache.release.iPhone18,1.decompressed com.apple.security.sandbox -o /tmp/KEXTs
#   → /tmp/KEXTs/com.apple.security.sandbox     (+ --imports to resolve cross-fileset symbols)

# 7. Kernel-specific dumps that save hours of manual mapping:
ipsw kernel syscall  kernelcache.release.iPhone18,1.decompressed   # BSD syscall table → names+addrs
ipsw kernel sbopts   kernelcache.release.iPhone18,1.decompressed   # Sandbox operation names

# 8. Cross-version DIFF — what changed between two builds (the bug-hunter's first move).
ipsw kernel kexts --diff <oldBuild>/kernelcache <newBuild>/kernelcache
```

The version string isn't magic — you can pull it with the same low-level tools you'd use on the Mac, which proves there's no proprietary parsing involved once the cache is decompressed:

```bash
# The Darwin/xnu fingerprint lives as a plain C string in __TEXT,__const.
strings -a kernelcache.release.iPhone18,1.decompressed | grep -m1 'Darwin Kernel Version'
#   Darwin Kernel Version 25.5.0: <date>; root:xnu-12377.121.x/RELEASE_ARM64_T8150

# Inspect a single extracted kext like any other Mach-O.
ipsw macho info /tmp/KEXTs/com.apple.security.sandbox        # segments, sections, UUID, code-sig
otool -l /tmp/KEXTs/com.apple.security.sandbox | grep -A4 LC_UUID
```

Levin's `jtool2` is the second opinion — it knows the kernelcache layout and can list kexts and locate Mach traps / syscalls on a decompressed cache:

```bash
jtool2 -l kernelcache.release.iPhone18,1.decompressed   # load commands incl. LC_FILESET_ENTRY
jtool2 --kc kernelcache.release.iPhone18,1.decompressed  # kernelcache-aware mode
```

> 🔬 **Forensics note:** `ipsw kernel kexts --diff` between the build on a suspect device and the prior build is the same primitive an examiner uses to spot a security fix Apple shipped silently — and, inverted, a way to notice a kext that *shouldn't* be there. Keep the per-build kernelcaches you extract; they are small after `--xz` and become your symbolication/diff corpus.

## 🧪 Labs

> All labs are **device-free**. Substrates: a **public IPSW** (Apple's unauthenticated signing server) for everything kernel-real, and the **Xcode Simulator** for the one lab that demonstrates *why the Simulator can't stand in for the kernel*. Fidelity caveat up front: **the Simulator does not run iOS XNU at all** — it runs your Mac's host kernel and host-arch system frameworks, so it has no kernelcache, no AMFI/CoreTrust enforcement, no SEP, and none of the device-only daemons. The kernelcache labs therefore *must* use an IPSW, not the Simulator.

### Lab 1 — Acquire and crack open a real iOS kernelcache (substrate: public IPSW)

1. `ipsw device-list | grep iPhone18` to pick an identifier, then `ipsw download ipsw --device iPhone18,1 --latest --confirm`. (`iPhone18,1` = iPhone 17 Pro, A19 Pro / `t8150`; any modern device works — substitute what's currently signed.)
2. `ipsw extract --kernel <ipsw>` to carve out the `kernelcache.release.*` `IM4P` without unzipping the whole multi-GB firmware.
3. `ipsw kernel version <im4p>` — record the `xnu-…` tag, the `Darwin Kernel Version`, the `RELEASE_ARM64_T<chip>` variant, and the reported **compression** (expect `lzfse`). You have just fingerprinted the exact build + SoC from the binary itself.
4. `ipsw kernel dec <im4p>` then `otool -h <…>.decompressed`. Confirm **`filetype 12 (MH_FILESET)`**. Note: this is the *same* container form as a macOS boot kernel collection.

### Lab 2 — Inventory the prelinked driver set + extract a kext (substrate: public IPSW)

1. `ipsw kernel kexts <decompressed> | wc -l` — count the prelinked kexts. There is no runtime-load path on iOS, so **this list is the complete set of kernel code the device will ever run**.
2. Grep that list for the security-relevant members: `com.apple.security.sandbox`, `com.apple.driver.AppleMobileFileIntegrity`, `com.apple.driver.AppleSEPManager`. These are the kernel halves of the sandbox, AMFI, and SEP plumbing you'll meet across Part 03.
3. `ipsw kernel extract <decompressed> com.apple.security.sandbox --imports -o /tmp/KEXTs`. Open the result in your disassembler (Ghidra/IDA/Hopper). Confirm it loads as a normal ARM64 Mach-O with sane segments — that's the payoff of the `--imports` cross-fileset symbol resolution.
4. `ipsw kernel sbopts <decompressed>` — list the sandbox operation names. Keep this; it's the vocabulary the sandbox-profile lessons ([[the-sandbox-and-tcc]]) build on.

### Lab 3 — Diff two builds (substrate: public IPSW ×2)

1. Extract kernelcaches from two adjacent iOS builds (e.g. a `.x` and the prior `.x-1`).
2. `ipsw kernel kexts --diff <oldBuild>/kernelcache <newBuild>/kernelcache` — note added/removed/changed kexts.
3. Pick one kext present in both, extract from each, and load both into your disassembler. Even a coarse function-count or string diff hints at where Apple touched code between builds — the first move in 1-day vulnerability research.

### Lab 4 — Prove the Simulator is NOT iOS XNU (substrate: Xcode Simulator)

This lab exists to inoculate you against the most common beginner error: treating the Simulator as a tiny iPhone.

1. Boot a simulator: `xcrun simctl boot "iPhone 17 Pro"` (or pick from `xcrun simctl list devices`).
2. From the **Mac**, compare kernels: `uname -a` on your Mac prints `Darwin … 25.x.0 … RELEASE_ARM64_T6xxx` (your Mac's SoC). The Simulator has **no separate kernel** — simulated processes are ordinary macOS processes running on that *same host kernel*. There is no `kernelcache` anywhere under `~/Library/Developer/CoreSimulator/`.
3. Drop a tiny C program that calls `task_for_pid` on another PID into a simulator-targeted run and observe it *succeed* in ways it never would on-device — because AMFI/the iOS task-port policy is simply not present. Internalize the caveat: the Simulator teaches **userland structure and on-disk layout**, never kernel posture, signing, or lock-state. Anything in this lesson about `MH_FILESET`, AMFI, trust caches, or task-port lockdown can only be observed against the **IPSW** (static) or a sample image — never the Simulator.

### Lab 5 — Feel the removed affordances on your Mac (substrate: read-only walkthrough on macOS)

The fastest way to internalize "what mobile removes" is to use those affordances on the Mac and note that none of them exist on the phone.

1. **DTrace:** run `sudo dtrace -ln 'syscall:::entry'` on your Mac — hundreds of probes enumerate. On iOS there is no `dtrace`, no `/dev/dtrace`, and no provider list; the subsystem is compiled out. (On a modern Mac you may need to lower SIP's DTrace restriction — itself a reminder that DTrace is a *debug* affordance the appliance OS drops entirely.)
2. **Task ports:** `sudo /usr/bin/lldb -p $(pgrep -n Finder)` attaches on the Mac because `lldb` can obtain Finder's task port. The iOS equivalent — attaching to an arbitrary app's task — is denied by the kernel/AMFI task-port policy; on-device debugging only works for processes you build with `get-task-allow` and a development signature ([[code-signing-amfi-entitlements]]).
3. **Arbitrary exec:** `clang -o /tmp/hi hi.c && /tmp/hi` runs an unsigned binary on the Mac. The same drop-and-run is impossible on iOS — there's no user shell and AMFI would refuse the exec. Map each of these back to the five-knob table: same XNU, opposite posture.

> ⚠️ **ADVANCED (read-only walkthrough — do not attempt without a sacrificial, lawfully-owned device):** Obtaining the *running* kernel from a live device is a different game from extracting the IPSW copy. On checkm8-eligible hardware (**A8–A11 only**), a `palera1n` BootROM exploit can patch the in-memory kernel (disable AMFI enforcement, open an unsigned-exec hole) and a tool like `kpf`/`fugu` can dump it; on A12+ there is no public path on iOS 18/26. None of this is needed for kernel RE — the IPSW kernelcache is byte-identical to what runs — and patching a device's kernel is destructive to evidentiary state. We narrate it only so you recognize a patched-kernel device when you see one.

## Pitfalls & gotchas

- **You must unwrap two layers, in order.** A `kernelcache.release.*` straight out of an IPSW is an **Image4 `IM4P`**, and its payload is **compressed**. `file` on it says "data"; `otool -h` fails. Run `ipsw kernel dec` (Image4 + decompress) *first*, then treat the result as a Mach-O. Skipping the decompress is the #1 "why won't my disassembler open this" mistake.
- **Two compression schemes by era.** Older caches use **LZSS** (`complzss` header); modern caches use **LZFSE** (`bvx2`/`bvxn` blocks) — the switch landed gradually across the iOS 12–13 era (build- and device-dependent), so treat anything iOS 14+ as LZFSE. `ipsw kernel version`/`dec` auto-detect; hand-rolled scripts that assume one format silently produce garbage on the other.
- **It's a `MH_FILESET`, not a flat Mach-O.** Tools that predate iOS 12 (or that only understand `MH_EXECUTE`) see one opaque blob. Use `ipsw kernel extract … --imports` (or `jtool2 --kc`) to get a *single* kext as a standalone, symbol-resolved Mach-O before you disassemble — otherwise cross-kext calls dangle.
- **Release kernelcaches are fully stripped.** No symbol table to lean on. You recover names via the syscall/Mach-trap tables (`ipsw kernel syscall`), string/xref analysis, the `__PRELINK_INFO` plist, and a **KDK** (Kernel Development Kit) for the *macOS* sibling build to seed symbol guesses. Expect to do real RE, not `nm`.
- **`release` vs `development`/`research` variants matter.** Production IPSWs ship `kernelcache.release.<device>` — assertions compiled out, fully optimized, stripped. Internal/older firmwares (and macOS KDKs) sometimes carry a `kernelcache.development` (`DEVELOPMENT_ARM64` — `panic`/`assert` strings intact, far more readable) or a research/`KASAN` build. When you can get the *development* variant for the same logic, RE is dramatically easier because the assertion strings name functions and invariants the release build erased; just remember offsets and exact codegen differ from `release`.
- **The cache is per-device-class and per-build.** `kernelcache.release.iPhone18,1` is not interchangeable with another SoC's cache, and KASLR means runtime addresses are slid — static offsets from the file are *file* offsets, not live addresses. Always pull the cache that matches the exact build (and SoC) you're investigating.
- **The Simulator has no kernel of its own.** Re-stating Lab 4 because it bites people repeatedly: there is no `task_for_pid` restriction, no AMFI, no SEP, no kernelcache in CoreSimulator. Never validate a *kernel-posture* claim on the Simulator. (See [[simulator-internals-and-on-disk-filesystem]].)
- **`apple/darwin-xnu` is the old mirror.** Read source from `apple-oss-distributions/xnu`, and remember the open tree includes the **XNU-side** SPTM/TXM glue but **not** the SPTM/TXM monitor binaries (those are separate Image4 payloads, not part of the kernelcache). Don't go looking for the monitor inside the kernel collection.

## Key takeaways

- iOS and macOS are **the same XNU source tree** — Mach (`osfmk`) + BSD (`bsd`) + IOKit (`iokit`) + libkern + Pexpert — built for ARM64; iOS 26 is the Darwin 25 generation, re-converged with macOS 26.
- Mobile **removes or locks down** the open affordances: no runtime/third-party kexts, no DTrace, `task_for_pid` gated to self + a few Apple daemons, no `fork`+`exec` of arbitrary binaries, and **mandatory** AMFI/CoreTrust signing enforced *in the kernel* via trust caches.
- Because nothing loads at runtime, the kernel ships as a single **prelinked `MH_FILESET` kernelcache** (`filetype 0xC`) with every kext fused in via `LC_FILESET_ENTRY`, fully linked and symbol-stripped.
- On disk in an IPSW the kernelcache is an **Image4 `IM4P` (type `krnl`)** whose payload is **LZSS (`complzss`, older builds)** or **LZFSE (`bvx2`, modern builds / all iOS 14+)** — unwrap and decompress before it's a Mach-O.
- The **IPSW is the legitimate, public, repeatable source**: `ipsw extract --kernel` → `ipsw kernel dec` → `ipsw kernel kexts`/`extract` gives you a byte-identical copy of the running kernel and standalone kexts for disassembly.
- The kernelcache is therefore the **substrate for all iOS kernel RE** — syscall/sandbox mapping, AMFI analysis, and cross-build diffing all happen statically on the Mac.
- **Forensically:** the embedded `Darwin Kernel Version …xnu-…/RELEASE_ARM64_T<chip>` string fingerprints exact build + SoC; a kernel that diverges from the signed Apple kernelcache for its build (AMFI disabled, patched) is a tamper/jailbreak indicator — keep in mind only A8–A11 (checkm8) has a public kernel-patch path on current iOS.
- The **Simulator is not iOS XNU** — it runs your Mac's host kernel, so it can teach userland structure but never kernel posture, signing, or lock-state.

## Terms introduced

| Term | Definition |
|---|---|
| XNU | "X is Not Unix" — Apple's hybrid kernel: Mach microkernel core + BSD subsystem + IOKit driver runtime; shared by macOS and iOS. |
| Mach (`osfmk`) | The microkernel layer: tasks, threads, ports/IPC, virtual memory, scheduler. CMU Mach lineage. |
| BSD (`bsd`) | The Unix personality: processes/PIDs, signals, the syscall table, sockets, VFS, MACF hooks. FreeBSD-derived. |
| IOKit | XNU's C++ driver runtime (`IORegistry`, `IOService` matching); kexts are written against libkern's restricted C++. |
| kext | Kernel extension — a driver/module. On iOS all kexts are prelinked into the kernelcache at build time; none load at runtime. |
| kernelcache | The single prelinked, signed kernel image iOS boots: the base kernel + every kext fused into one Mach-O. |
| `MH_FILESET` | Mach-O `filetype 0xC` — a container Mach-O bundling multiple member Mach-Os (kernel + kexts) via `LC_FILESET_ENTRY`; the modern (iOS 12+) kernelcache form. |
| `LC_FILESET_ENTRY` | Load command naming one member of a `MH_FILESET` (e.g. `com.apple.security.sandbox`) and its embedded Mach-O offset. |
| Image4 / `IM4P` | Apple's ASN.1/DER secure-boot container; the kernelcache file in an IPSW is an Image4 *payload* (`IM4P`) with 4CC type `krnl`. |
| `complzss` / LZFSE | Kernelcache payload compression: LZSS (`complzss` header, older builds) vs. LZFSE (`bvx2`/`bvxn` blocks, modern builds; all iOS 14+). |
| trust cache | Kernel-held set of code-directory hashes trusted without an online check; a *static* one is baked into the kernelcache. |
| AMFI | AppleMobileFileIntegrity — the kernel extension enforcing mandatory code signing on iOS (with the CoreTrust validator). |
| `task_for_pid` | Mach call returning another process's task port (the key to `vm_read`/`vm_write`); restricted to self + a few Apple daemons on iOS. |
| Mach trap vs BSD syscall | Kernel entry on ARM64 via `svc #0x80` with the call number in `x16`: negative = Mach trap (`mach_trap_table[]`), positive = BSD syscall (`sysent[]`). |
| jetsam / `memorystatus` | iOS's memory-pressure handler — *terminates* processes by priority band instead of paging to swap; classic iPhones have no swap file. |
| `kmutil` / KernelManagement | Apple's tool/subsystem that builds the boot kernel collection (`MH_FILESET`); successor to `kextcache`/`kcgen`. |
| KASLR slide | Random base offset applied to the whole kernelcache at boot; file offsets in the extracted cache are *not* runtime virtual addresses. |
| DTrace | Dynamic tracing framework present on macOS; **absent/compiled out** on iOS. |
| `ipsw` | blacktop's CLI for downloading IPSWs and extracting/decompressing/parsing kernelcaches and Mach-Os. |
| KDK | Kernel Development Kit — Apple's per-build kernel + symbols (macOS); used to seed symbolication of stripped kernelcaches. |

## Further reading

- **Jonathan Levin**, *MacOS and iOS Internals, Vol. II (Kernel Mode)* and newosxbook.com — the canonical XNU-on-mobile reference; `jtool2` and `joker` tool docs (newosxbook.com/tools/joker.html).
- **Apple** — XNU source: [`github.com/apple-oss-distributions/xnu`](https://github.com/apple-oss-distributions/xnu) (build/README, `osfmk`/`bsd`/`iokit` layout); Apple Platform Security Guide (code signing, trust caches, kernel integrity); `man kmutil`, `man kernelmanagerd`.
- **blacktop/ipsw** — [`blacktop.github.io/ipsw/docs/guides/kernel/`](https://blacktop.github.io/ipsw/docs/guides/kernel/) (`kernel dec`/`kexts`/`extract`/`syscall`/`sbopts`, MH_FILESET handling) and the `img4` guide.
- **The Apple Wiki** — *Kernelcache*, *Image4*, *SHSH* pages (theapplewiki.com) for the Image4 4CC tags and per-version format history.
- **8kSec** — "ipsw Walkthrough Part 2" (8ksec.io) — worked `ipsw kernel` examples.
- **arXiv 2510.09272** — SPTM/TXM/Exclaves architecture (for the A15+/M2+ monitor layer the kernelcache hands off to).
- `man otool`, `man nm`, `man size` — Mach-O inspection; `llvm-otool -h` for the `MH_FILESET` filetype.

---
*Related lessons: [[soc-lineup-and-device-matrix]] | [[dyld-shared-cache-and-amfi]] | [[code-signing-amfi-entitlements]] | [[boot-chain-securerom-iboot]] | [[image4-personalization-shsh]] | [[simulator-internals-and-on-disk-filesystem]] | [[mach-o-arm64-deep-dive]]*
