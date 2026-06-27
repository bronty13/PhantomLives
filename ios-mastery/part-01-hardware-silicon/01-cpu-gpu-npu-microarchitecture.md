---
title: "CPU, GPU, NPU & the microarchitecture"
part: "01 — Hardware & Silicon"
lesson: 01
est_time: "40 min read + 15 min labs"
prerequisites: [soc-lineup-and-device-matrix]
tags: [ios, hardware, cpu, gpu, neural-engine, pac]
last_reviewed: 2026-06-26
---

# CPU, GPU, NPU & the microarchitecture

> **In one sentence:** the iPhone's application processor is the *same* Apple Silicon family as your M-series Mac — a heterogeneous SoC of asymmetric P/E CPU clusters, a tile-based Apple GPU, a 16-core Neural Engine, AMX/SME matrix units, and a unified-memory fabric — but it runs **arm64e with Pointer Authentication wired into the silicon**, which is the single fact that reshapes how you reverse-engineer iOS binaries and reason about its memory-safety story.

## Why this matters

You finished `macos-mastery` knowing Apple Silicon as a Mac: performance and efficiency cores, one coherent pool of unified memory, a Neural Engine, the AMX matrix coprocessor, PAC since the M1. **The iPhone's SoC is the same lineage** — designed by the same team, fabbed on the same TSMC node family, sharing the same ISA generation — so most of that knowledge transfers verbatim. That recognition is the productive half of this lesson: you already understand the *shape*.

The other half is the deltas that matter to a forensics-and-RE practitioner. Three of them carry the whole lesson. First, **every Apple-shipped binary on an iPhone is `arm64e`** and its pointers are cryptographically signed — so when you open a system framework or the kernelcache in Hopper/IDA you are staring at `pacibsp`/`retab` prologues and address bits you have to strip before they mean anything (Part 11). Second, the **Neural Engine is not a benchmark trophy; it is an evidence generator** — `mediaanalysisd` runs Vision and ML models on the ANE and writes the results (detected faces, scene labels, OCR'd text inside images) into the Photos database, where they become some of the richest searchable artifacts on the device (Part 08). Third, the **A19's silicon memory-safety stack (MIE/EMTE)** is the hardware end of the mitigation ladder that decides whether a given exploit class still works in 2026 — the difference between "there is a jailbreak for this device" and "there isn't."

So this is not a spec-sheet recital. It is: what each compute block actually *is*, how it differs from the Mac you know, and where each one leaves fingerprints you can read or barriers you have to defeat.

## Concepts

### The SoC is a system, not a CPU

"Application processor" is a misnomer inherited from the feature-phone era. The A-series die is a **system-on-chip**: a dozen heterogeneous compute and fixed-function blocks sharing one memory fabric. Holding this whole-system picture is the prerequisite for everything below — the CPU is just one tenant.

```
        Apple A19 Pro — block view (durable shape; counts are 2026-era)
 ┌──────────────────────────────────────────────────────────────────────┐
 │  CPU                                                                   │
 │   ┌─────────────────────────┐     ┌──────────────────────────────┐    │
 │   │ Performance cluster (2P)│     │  Efficiency cluster (4E)     │    │
 │   │  P  P  + shared L2      │     │  E E E E + shared L2         │    │
 │   │  + AMX/SME block        │     │  + AMX/SME block             │    │
 │   └─────────────────────────┘     └──────────────────────────────┘    │
 │                                                                        │
 │  GPU (Apple, TBDR)            Neural Engine (16-core ANE)              │
 │   N GPU cores, each with       fixed-function NN accelerator          │
 │   a per-core Neural             (convolution / matmul)                │
 │   Accelerator (A19+)                                                   │
 │                                                                        │
 │  Secure Enclave (SEP)   ISP   Media (video) engines   Always-On proc. │
 │  Storage/NAND ctrl + AES engine    Display   Sensors/AOP   baseband*  │
 └───────────────────────────┬──────────────────────────────────────────┘
                  System-Level Cache (SLC)  ── coherent fabric ──
                             │
                   ┌─────────┴──────────┐
                   │  Unified memory     │  LPDDR5X, on-package, one
                   │  (LPDDR5X, UMA)     │  physical pool + one address
                   └────────────────────┘  space for CPU/GPU/ANE/AMX
       (* baseband is a separate Qualcomm/Apple modem die or package, not a CPU cluster)
```

Every shaded block is a *separate clock and power domain* gated independently by the SoC power manager, and every one of them — CPU, GPU, ANE, the matrix units — reads and writes the **same physical DRAM** through the System-Level Cache and the coherent fabric. There is no PCIe, no discrete VRAM, no "upload to the GPU." That single design choice (unified memory) is why an iPhone can run a multi-billion-parameter model the GPU and ANE both touch without copying it. We come back to it; first the CPU.

### CPU topology: 2P + 4E, clusters, clock domains, the closed-loop scheduler

The A19 / A19 Pro application CPU is **6 cores: two performance ("P") cores + four efficiency ("E") cores**, exactly the asymmetric big.LITTLE-style arrangement you know from M-series Macs — only the *ratio* differs (a Mac leans P-heavy, e.g. M-series Pro chips ship many more P cores; a phone leans E-heavy because most of its life is background and idle). The cores are grouped into **two clusters**, and the cluster — not the individual core — is the unit of frequency and voltage scaling:

| | Performance cluster | Efficiency cluster |
|---|---|---|
| Cores (A19/A19 Pro) | 2 | 4 |
| Microarchitecture | wide out-of-order, deep ROB, aggressive prefetch | narrower, in-order-ish, optimized for perf/watt |
| Peak clock (2026, **perishable**) | up to ~4.26 GHz | up to ~2.6 GHz |
| Shared per cluster | L2 cache, one AMX/SME matrix block | L2 cache, one AMX/SME matrix block |
| Role | bursty foreground work, single-thread latency | the default home for almost everything |

What makes an Apple **P-core** fast is not clock — at ~4 GHz it is *slower*-clocked than competing Arm and x86 cores — but **width and depth**. Apple's performance core is one of the **widest out-of-order machines in the industry**: an extremely wide decode/rename front end (on the order of 8+ instructions per cycle), a very large reorder buffer and physical register file (many hundreds of in-flight instructions), deep load/store queues, and large private L1/L2 caches. It extracts instruction-level parallelism aggressively rather than racing the clock — the design philosophy that lets a phone match a laptop on single-thread work inside a few watts. The **E-core** is a deliberately narrower, shallower machine tuned for performance-per-watt, which is why CLPC parks everything it can there. *(The exact decode width, ROB size, and cache sizes per generation are well-characterized by independent analysis but are perishable per-µarch details — cite the generation when you state a number.)*

Two more durable points behind the numbers:

- **Clock domains are per-cluster.** All P cores share one DVFS (dynamic voltage/frequency scaling) domain; all E cores share another. You cannot run one P core at 4 GHz while its sibling idles at 1 GHz — they move together. The GPU, the ANE, and the fabric/SLC are *additional* independent domains. Power management is the act of gating and scaling these domains thousands of times a second. A phone's tiny thermal mass (no fan, a passive aluminum/glass chassis) forces a **sprint-and-idle** duty cycle: the P cluster boosts to peak for a burst, then the thermal governor throttles it down — so peak clock is a *transient*, and sustained throughput is set by the package's thermal headroom, not the headline GHz. This is far more aggressive than on a fan-cooled Mac.
- **Placement is decided by the kernel's closed-loop performance controller (CLPC), not by core count.** XNU does not just round-robin threads onto cores. Each thread carries a **QoS class** (`USER_INTERACTIVE`, `UTILITY`, `BACKGROUND`, …) and belongs to a **thread group**; CLPC continuously samples each cluster's utilization and "recommends" which cluster a thread group should run on, migrating background/low-QoS work onto the E cluster and waking the P cluster only when foreground latency demands it. This is the same CLPC you met on macOS — and on iOS it is *more* aggressive, because battery and thermals are tighter and because the OS is willing to kill (jetsam) memory hogs rather than swap. → [[00-xnu-on-mobile]], [[06-memory-jetsam-app-lifecycle]].

> 🖥️ **macOS contrast:** identical mechanism, different tuning. On the Mac you watch P/E placement live with `powermetrics --samplers cpu_power` and Activity Monitor's "Energy" tab; the same CLPC + QoS + thread-group machinery runs on iOS, but you have **no on-device tool** to observe it (no shell, no `powermetrics`). On iOS you infer CPU behavior off-device — from the **PowerLog**/CoreDuet energy accounting that `powerlogHelperd` writes (Part 08) — rather than watching it in real time. The scheduler is the same; the *observability* collapsed.

> 🔬 **Forensics note:** the P/E split is invisible in artifacts, but its accounting is not. The device continuously attributes energy and CPU time per app/per process into the **PowerLog** (`CurrentPowerlog.PLSQL`) and the aggregate dictionary; those stores let you reconstruct which apps were *actually executing* (not merely installed) and roughly when, which is a pattern-of-life signal that survives even when an app left no content artifacts. → [[03-powerlog-and-aggregate-dictionary]].

### Apple's GPU: tile-based deferred rendering + the A19 neural accelerators

The GPU is **Apple's own design** (since the A11 Bionic dropped Imagination's IP), and its defining architectural trait is **TBDR — Tile-Based Deferred Rendering**. Where a desktop "immediate-mode" GPU shades fragments as triangles arrive (and pays for overdraw), a TBDR GPU bins geometry into small on-chip tiles, resolves visibility *first*, and shades only the pixels that survive — a bandwidth- and power-optimized strategy that fits a phone's thermal envelope. This is the **same Apple GPU architecture as the M-series Mac**; the iPhone just ships fewer GPU cores (A19 Pro: 5- or 6-core depending on SKU; an M5 has far more).

Two recent durable additions sit underneath the marketing. **Dynamic Caching** (introduced with the A17 Pro / M3 GPU generation) allocates on-chip memory — registers, threadgroup memory, cache — to shaders *at runtime* based on what each shader actually needs, instead of reserving worst-case capacity at compile time; the effect is much higher occupancy and utilization. And **hardware-accelerated ray tracing** (also A17 Pro+) puts ray/triangle-intersection and bounding-volume traversal in dedicated GPU silicon rather than emulating it in shaders. Both are the *same* features as the contemporary M-series Mac GPU — they are architecture-level, not iPhone-specific.

The headline 2026 change is at the GPU-core level. The **A19 generation adds per-GPU-core "Neural Accelerators"** — matrix/tensor ALUs embedded *inside each GPU core's* shader pipeline, alongside a doubling of FP16 throughput. Practically this means heavy matmul/tensor work (the math of neural networks) can now run on the GPU's own datapath at high throughput, rather than only on the dedicated Neural Engine. Apple's framing is a large multiplier on peak GPU compute and a system that spreads ML across **three** engines now — CPU (via AMX/SME), the Neural Engine, and the GPU's neural accelerators — with the OS/Core ML runtime choosing the placement. *(The exact "up to N×" and TOPS figures are perishable marketing numbers — verify against the current A19 spec; the durable fact is "matrix units moved into the GPU cores.")*

> 🖥️ **macOS contrast:** you already know Apple's TBDR GPU and Metal from the Mac; on iOS it is the same GPU family and the same Metal API, so a Metal shader you understand on the Mac maps directly. The new wrinkle — GPU-resident neural accelerators — debuted in this A19 generation and propagates up the M-series too, so it is a *whole-platform* shift, not an iPhone-only one. Where the Mac gives you Instruments' Metal System Trace and `Metal HUD` to watch the GPU, iOS again gives you no on-device probe — GPU debugging is driven from a tethered Mac through Xcode's GPU frame capture (Part 10).

### The Neural Engine (ANE): 16 cores of fixed-function ML

The **Apple Neural Engine** is a dedicated, fixed-function accelerator for neural-network inference — convolutions, matrix multiplies, activations — built to run those operations at a fraction of the energy the CPU or GPU would burn. It has been a **16-core** design since the A14 / M1 generation (the A11's was 2-core; the count has been flat at 16 for the application processors through A19), so "16-core" is not what changed in 2026 — what changed is **memory bandwidth to the ANE** and the *option* to offload the same work to the new GPU neural accelerators. *(Per-engine TOPS — historically ~35 TOPS for the 16-core ANE on the A17/A18 generation, higher when the system aggregates ANE + GPU — is a perishable figure to re-verify.)*

As of the A19 generation there are **three** places ML math can run, and Core ML's runtime — not your code — schedules across them:

| Engine | Best at | How you reach it | Power profile |
|---|---|---|---|
| **CPU + AMX/SME** | small models, control-heavy code, fallback | Accelerate (AMX) / SME intrinsics; automatic Core ML fallback | highest energy/op |
| **Neural Engine (ANE)** | sustained, fixed-shape inference (vision, on-device LLM) | Core ML picks it for supported ops | lowest energy/op |
| **GPU + neural accelerators (A19+)** | large matmul, mixed graphics+ML, flexible shapes | Metal Performance Shaders / Core ML GPU path | middle, high throughput |

What matters far more than the TOPS number is **what the ANE is used for**, because that is what produces evidence. Third-party developers reach it only indirectly: you hand **Core ML** a model and a set of allowed compute units (`MLComputeUnits.all` lets the runtime pick CPU/GPU/ANE), and the runtime — not your code — decides what lands on the ANE. The OS itself is the ANE's heaviest user:

- **Photos analysis.** The `mediaanalysisd` / `photoanalysisd` daemons run Vision and ML models on the ANE over your library: **face detection and face clustering** (the "People" album), **scene/object classification** ("beach", "dog", "receipt"), and **Live Text OCR** (recognizing text *inside* images). The results are written into the Photos SQLite store as structured, queryable metadata.
- **Apple Intelligence (2026).** The on-device foundation model(s) behind Writing Tools, summarization, Genmoji, and Siri's on-device path run primarily on the ANE (with GPU spillover via the new neural accelerators). *(Exact model sizes, daemons, and on-disk artifact paths for the 2026 Apple-Intelligence stack are flagged "verify at author time" in the course baseline.)*
- **Face ID.** The neural network that matches the dot-projector depth map against the enrolled template runs in the **Secure Enclave's** ML path, not the general ANE — a deliberate separation, because the faceprint must never leave the SEP. → [[06-biometrics-hardware-faceid-touchid]], [[02-secure-enclave-hardware]].

> 🔬 **Forensics note (workhorse):** the ANE turns a phone into a self-indexing evidence machine. Inside the Photos store (`Photos.sqlite`, plus the analysis sidecar databases) you can recover **machine-generated labels nobody typed**: the scene/object classifications, the detected-face bounding boxes and cluster identities, and the **OCR text Live Text extracted from photos and screenshots** — meaning you can keyword-search the *contents of images*, not just filenames. This is ANE output persisted to disk. It is also why these stores are large and why analysis runs (and re-runs after an OS update) show up as battery/CPU activity in PowerLog. → [[06-photos-and-the-camera-roll]], [[12-unified-logs-sysdiagnose-crash-network]].

> ⚖️ **Authorization:** ANE-derived metadata is *machine inference*, not ground truth. A scene label of "weapon" or a face cluster the algorithm merged are probabilistic outputs of a model — useful as **investigative leads and for search**, but you must not present an on-device classification as a fact the user asserted. Distinguish "the device's ML labeled this image X" from "the user labeled/knew this image was X" in any report. → [[00-ios-forensics-landscape-and-authorization]].

### AMX and SME: the matrix and vector units

Sitting next to (and shared by) each CPU cluster is a **matrix coprocessor**. Its history is a two-act story you should know precisely, because it determines what you can and cannot target in code:

- **AMX (Apple Matrix eXtension)** — Apple's **proprietary, undocumented** matrix instruction set, present since roughly the A13 / M1 era. It is implemented as a dedicated block, **one per CPU cluster** (shared by all cores in that cluster), and is driven by AMX instructions the CPU issues — encodings *outside* the standard Arm ISA that Apple never published. You do not write AMX directly; you call **Accelerate.framework** (BNNS, vDSP, BLAS/LAPACK) and the library issues the AMX instructions for you. This is why high-performance linear algebra on Apple Silicon is fast "for free" but only through Apple's libraries.
- **SME (Scalable Matrix Extension)** — Arm's **standard, architectural** matrix extension (part of Armv9.2-A). Apple's **M4 (2024) was the first publicly shipping chip to expose SME**, and it propagated to the contemporaneous and later A-series. SME is a streaming-mode vector/matrix unit with a 512-bit vector length on Apple's implementation (64-byte vectors; a 4 KB `ZA` tile), again **one block per cluster**. Unlike AMX, SME is *documented Arm architecture* — third-party code can target it via intrinsics or assembly, and the OS exposes its presence as a CPU feature flag. *(Exactly which A-series generations expose architectural SME/SME2 is worth confirming against `sysctl hw.optional.arm.FEAT_SME` on a current device-class chip — see Hands-on.)*

The forensic/RE relevance is modest but real: a binary that issues raw AMX encodings is doing Apple-private matrix math (and will confuse a disassembler that doesn't know the encodings); SME shows up as recognizable `SMSTART`/`SMSTOP` streaming-mode transitions and `ZA`-tile ops.

> 🖥️ **macOS contrast:** this is the same coprocessor lineage as your Mac — AMX behind Accelerate since the M1, SME first exposed on the **M4**. On the Mac you can actually probe and even hand-write SME (the M4 made it a public target); the iPhone shares the silicon capability but, lacking any on-device compiler or shell, you only ever *observe* it from binaries, never experiment on the device.

### Performance counters: the PMU, and why iOS welds it shut

Every Apple core has a **PMU — Performance Monitoring Unit** — a bank of hardware counters that tally micro-architectural events (cycles, instructions retired, branch mispredicts, L1/L2/TLB misses, etc.). This is the substrate under all profiling: Instruments' CPU Counters and "Time Profiler," `xctrace`, and the low-level `kperf` / `kpc` kernel interfaces all read the PMU. On the Mac you can drive it from userspace with root.

On **iOS the PMU is locked away from you**, and the reason is the same trust model that runs the whole platform. The `kperf`/`kpc` sampling path and the deeper counter access are gated behind **private entitlements** (e.g. `com.apple.private.kernel.kpc`, the kpc counter gate — the alternative to running as root) that no third-party app is granted, so there is no on-device profiler app and no way to read raw counters from your own process on a stock device. Developer-side performance work is therefore done **off-device** through a tethered Mac: Xcode/Instruments talks to the on-device profiling agent over the (iOS 17+) RemoteXPC tunnel and pulls samples back to the Mac. A jailbroken device, having defeated the entitlement gate, *can* expose the PMU — which is exactly how independent researchers characterize Apple cores (decode width, ROB size) and how some micro-architectural side-channel work (PACMAN, Augury, the GoFetch DMP study) reached the counters in the first place.

> 🔬 **Forensics note:** you will not pull PMU traces in an investigation, but the *consequence* matters: because raw counters are entitlement-gated, the energy/CPU accounting you **can** recover forensically is the cooked, daemon-written summary in **PowerLog**/the aggregate dictionary, not live hardware counters. Know the difference between "the OS's bookkeeping of how much CPU an app used" (recoverable) and "hardware event counters" (device-only, root/entitlement-gated, gone). → [[03-powerlog-and-aggregate-dictionary]].

### arm64e and Pointer Authentication at the silicon level

This is the section that changes how you do Part 11. Since the **A12 (Armv8.3-A)**, Apple's application processors implement **Pointer Authentication (PAC)**, and Apple ships its own code in the **`arm64e`** ABI variant that uses it. PAC is a hardware mitigation against pointer-corruption exploits (ROP/JOP): selected pointers carry a cryptographic **signature in their unused high bits**, and the CPU verifies that signature before trusting the pointer.

How the silicon does it:

- The CPU holds **five 128-bit signing keys in hardware** registers that are **never readable by software** and are randomized per-boot (and per-process for some): `APIAKey` / `APIBKey` (for instruction pointers), `APDAKey` / `APDBKey` (for data pointers), and `APGAKey` (the "generic" key for `pacga`). They live in system registers managed below the kernel; even kernel code signs/authenticates *through* the instructions rather than reading the key.
- A **`PAC*` instruction** (`pacia`, `pacib`, `pacda`, `pacdb`, `pacga`, and the `…sp` shortcuts like `pacibsp`) computes a keyed MAC — Apple uses a **QARMA**-family block cipher — over the pointer value **plus a 64-bit context/salt** (often the stack pointer or a per-object discriminator) and packs the truncated result into the pointer's top bits.
- An **`AUT*` instruction** (`autia`, `autib`, `autda`, …, `autibsp`) recomputes and checks the signature on use. On a **mismatch** the pointer is poisoned (and, with `FEAT_FPAC`, the CPU **faults immediately** rather than later) — turning a corrupted return address into a crash instead of a hijack.
- **`XPAC*`** (`xpaci`, `xpacd`) strips the signature bits to recover the raw address. **You will type `xpaci` constantly in a debugger.**

The signature lives in the bits a 64-bit pointer doesn't use to address a (much smaller) virtual address space — so a "signed" pointer is just an ordinary pointer with a MAC stuffed into the top:

```
 64-bit pointer, arm64e:
 ┌───────────────── PAC field ─────────────────┬──┬──────── effective virtual address ────────┐
 │  keyed MAC (QARMA over addr + 64-bit salt)  │T │  the bits that actually index memory       │
 └─────────────────────────────────────────────┴──┴────────────────────────────────────────────┘
    63 ............................. (top bits)   55  (T = address-tag bit)   ... 0
   AUT* recomputes the MAC and compares; mismatch ⇒ poison (or FAULT with FEAT_FPAC).
   XPAC* just clears the PAC field to hand you back the raw address.
 (Exact field width depends on the VA size and TBI/MTE config — verify per target; the shape is durable.)
```

A canonical signed-return prologue/epilogue looks like this in a disassembler:

```
   ; function entry
   pacibsp                 ; sign LR with key B, salt = SP
   stp  x29, x30, [sp,#-16]!
   ...
   ; function exit
   ldp  x29, x30, [sp],#16
   retab                   ; authenticate LR (key B) and return in one op
```

The crucial nuance for an examiner/reverser: **arm64e is, in 2026, still effectively an Apple-platform-only ABI.** Apple's own binaries — the kernelcache, dyld, every system framework in the shared cache, the system daemons — are **arm64e and PAC-protected**. **Third-party App Store apps are still shipped as plain `arm64`** (the arm64e *user* ABI is officially "preview / not yet stable"), and XNU **disables the PAC keys when control returns to a non-arm64e process**, so the `PAC`/`AUT` instructions degrade to no-ops there. So:

| You're looking at… | Architecture | PAC active? | What you do |
|---|---|---|---|
| Kernelcache, dyld shared cache, system frameworks | `arm64e` | **Yes** | strip with `xpaci`; expect `pacibsp`/`retab`; gadget-hunting is hard |
| A normal third-party App Store `.app` binary | `arm64` | No (keys off in that process) | read addresses raw; classic ROP reasoning applies |
| A Simulator build of any app | `arm64` (or `x86_64`) macOS | No | **wrong artifact for ABI/PAC study** |

> 🖥️ **macOS contrast:** PAC is the *same* feature you met on Apple-Silicon Macs (M1+), with the same five keys and the same `arm64e` system binaries — and the same caveat that third-party Mac apps are typically plain `arm64`. The mechanism transfers one-to-one; what's iOS-specific is only that on a phone you study these binaries pulled off-device (from an IPSW's kernelcache or an extracted shared cache), never compiled or run locally. → [[00-mach-o-arm64-deep-dive]], [[01-the-code-signature-blob-and-entitlements-on-ios]].

> 🔬 **Forensics note:** PAC is why naive disassembly of iOS system code looks "off" — addresses with garbage high bits, returns via `retab` instead of `ret`, indirect calls via `braa`/`blraa`. A loader that doesn't model PAC (or doesn't `xpac` the cache's signed pointers) will produce wrong call graphs. Modern shared-cache loaders (Ghidra/IDA/Hopper plugins, blacktop's `ipsw`) handle the **chained-fixups / signed-pointer** format; an older tool will silently mis-resolve. Always confirm your tool understands arm64e before trusting its xrefs. → [[04-static-analysis-class-dump-and-disassemblers]], [[02-the-dyld-shared-cache]].

> ⚠️ **ADVANCED (RE tooling):** dynamic instrumentation must *respect* PAC on arm64e targets. When Frida/`Interceptor` hooks an arm64e function it has to **re-sign** the trampoline/return pointers with the right key+salt or the next `AUT*` faults; injecting into PAC-protected processes is part of why on-device RE leans on a jailbreak that already neutralizes these checks. Patching a return address by hand in LLDB means signing it (`ptrauth_sign_unauthenticated`) or the `retab` will kill the process. Don't `xpaci` a pointer and then store it back expecting the program to keep running. → [[05-dynamic-analysis-with-frida]], [[07-the-jailbreak-landscape-2026]].

### Unified memory architecture

Like every Apple Silicon chip, the iPhone SoC uses **Unified Memory Architecture (UMA)**: a single pool of **on-package LPDDR5X**, one physical address space, shared coherently by the CPU clusters, the GPU, the Neural Engine, the AMX/SME blocks, the ISP, and the media engines through the System-Level Cache and fabric. There is no discrete VRAM and no copy step between engines — the GPU and ANE operate on the *same buffers* the CPU wrote, which is exactly what makes whole-system ML (a model the CPU prepares, the ANE runs, the GPU post-processes) cheap. *(Capacity is perishable: phones in this era ship roughly 8 GB on standard models and ~12 GB on the Pro/A19-Pro tier — verify per SKU.)*

Physically, the DRAM is **on-package** — the LPDDR5X dies sit on the same substrate as the SoC, wired to an on-die memory controller over a wide internal bus (the unusually high bandwidth of Apple Silicon comes from bus *width*, not exotic DRAM). There is **no socketed RAM and no exposed memory bus**, which is not just a packaging choice — it is a security property: an attacker cannot tap the DRAM traces, cannot swap the module, and (because the controller and the SEP gate access) cannot perform a classic **cold-boot RAM attack** to read keys out of chilled memory the way you might against a desktop. The volatile state of an iPhone — including the resident Data-Protection class keys of an AFU device — lives in DRAM and the SEP that no external probe can reach.

The mobile-specific consequence is **memory pressure as a first-class OS concern**. A phone has far less RAM than a Mac and **no swap to disk worth the NAND wear**, so iOS does not page out under pressure — it **terminates apps (jetsam)** by priority band. UMA means the GPU/ANE compete for the *same* pool as the CPU, so a heavy ML or graphics workload directly raises memory pressure and the jetsam risk. This is why background apps get killed and re-launched, and why "app lifecycle" on iOS is a memory-management story, not just a UI one. → [[06-memory-jetsam-app-lifecycle]].

> 🖥️ **macOS contrast:** same UMA, same coherent fabric, same "no upload to the GPU" — but the Mac *has* compressed memory and disk swap, so it degrades gracefully under pressure where the phone kills. The reflex "it'll just swap" is a macOS habit; on iOS, exceeding the pressure thresholds means a process *dies*. → [[02-macos-to-ios-mental-model-reset]].

> 🔬 **Forensics note:** UMA + on-package DRAM is why **volatile-memory acquisition barely exists in iOS forensics**. There is no JTAG-to-RAM, no cold-boot dump, no DMA-over-Thunderbolt path to the pool the way there can be on a PC — the only route to live memory is *code execution on the device* (a jailbreak / exploit), and even then the SEP's secrets are off-limits. This is the deep reason iOS forensics is dominated by **dead-box-style logical/file-system acquisition gated by BFU/AFU**, not live RAM capture: the keys you would want are in a pool you cannot physically reach. → [[01-the-acquisition-taxonomy]], [[03-passcode-bfu-afu-and-inactivity]].

### From PAC to MIE: the silicon memory-safety ladder

PAC is the *first* rung of a hardware-rooted memory-safety progression that this course traces in detail in Part 03; meet the rungs here because they are silicon features of the chips in this module:

```
 PAC (A12+)        sign/auth pointers — defeats ROP/JOP via corrupted pointers
   │
 PPL (A12+)        Page Protection Layer — protects page tables from a compromised kernel
   │
 SPTM / TXM        Secure Page Table Monitor / Trusted Execution Monitor (A15+/M2+) —
   │               splits PPL's job into tiny monitors below the kernel
   │
 Exclaves          isolated secure domains carved out under the kernel
   │
 MIE / EMTE (A19)  Memory Integrity Enforcement: Arm Enhanced Memory Tagging in
                   *synchronous* mode + secure allocators (kalloc_type, xzone malloc,
                   libpas) + Tag Confidentiality Enforcement — tags memory so a
                   use-after-free / out-of-bounds access faults at the moment it happens
```

The capstone in this lesson's silicon is **MIE on the A19 / A19 Pro**: Apple spent unusual amounts of die area, clock, and DRAM (for tag storage) to run **EMTE — Enhanced Memory Tagging Extension — in synchronous mode** by default, so that the two dominant exploitation primitives (use-after-free and buffer overflow) are caught *deterministically at access time* rather than probabilistically. Combined with the secure heap allocators, this is the hardware reason the spyware-grade exploit chains that worked on prior silicon are far harder on A19. You don't need the internals yet — just register that **the chip you're studying carries a memory-safety capability that directly governs the 2026 jailbreak/exploit landscape**. → [[06-kernel-hardening-pac-sptm-txm-mie]], [[00-the-ios-security-model]].

### iPhone SoC vs the M-series Mac, at a glance

| Block | iPhone (A19 / A19 Pro, 2026) | M-series Mac (the one you studied) | Same? |
|---|---|---|---|
| CPU clusters | 2P + 4E (phone-tuned ratio) | P-heavy (e.g. many P + few E on Pro/Max) | same µarch family, different ratio |
| Scheduler | XNU CLPC + QoS + thread groups | XNU CLPC + QoS + thread groups | **identical** |
| GPU | Apple TBDR, 5–6 cores, **per-core neural accel (A19+)** | Apple TBDR, many cores, neural accel too | same arch, fewer cores |
| Neural Engine | 16-core ANE | 16-core ANE | **identical design** |
| Matrix units | AMX (private) + SME (Armv9.2) | AMX + SME (SME public since M4) | same lineage |
| Memory | UMA, on-package LPDDR5X, ~8–12 GB | UMA, on-package, much larger | same model, more capacity |
| Pointer auth | arm64e + PAC (A12+) | arm64e + PAC (M1+) | **identical** |
| Memory tagging | **MIE: EMTE synchronous, on by default (A19)** | `FEAT_MTE` present on recent gens, not in MIE posture | iPhone leads on *posture* in 2026 |
| Under-pressure behavior | jetsam (kill), no swap | compressed memory + swap | **diverges** |
| Your access to it | binaries pulled off-device only | local shell, `sysctl`, `powermetrics`, compilers | **diverges hard** |

## Hands-on

There is **no on-device shell** and you have **no physical device** — so every command here runs on your **Apple-Silicon Mac**, which is a faithful proxy for the *microarchitecture* (same P/E clusters, same arm64e/PAC, same UMA, same AMX/SME lineage) while being explicitly *not* the A-series part (different core ratio; MTE/EMTE/MIE may be absent; device-only blocks like the baseband and the production ANE workloads don't exist here).

### Read the cluster topology of the silicon family

```bash
# Cluster layout the kernel sees (your Mac is the proxy for the iPhone's 2P+4E shape)
sysctl hw.nperflevels                 # number of performance tiers → 2
sysctl hw.perflevel0.name             # top tier's Apple label (varies: "Performance"/"Super"…)
sysctl hw.perflevel0.physicalcpu      # top-tier core count
sysctl hw.perflevel1.name             # next tier ("Efficiency", etc.)
sysctl hw.perflevel1.physicalcpu      # core count
sysctl machdep.cpu.brand_string       # → e.g. "Apple M5 Max"
```

`hw.perflevel0` is always the **highest-performance** cluster and the highest index the most efficient — the exact split the CLPC schedules across. The `.name` strings are Apple's own tier labels and have varied across chips (classically `Performance`/`Efficiency`), so key off the *index and count*, not the name. On an **iPhone A19** this reports the **2 / 4** P/E split; on a workstation Mac it reports its own (P-heavy) ratio. The *mechanism* is what transfers.

### Inspect the unified-memory + cache hierarchy

```bash
# The one coherent pool + the per-tier cache sizes (Apple Silicon uses a large page)
sysctl hw.memsize                     # total unified memory in bytes (one pool for CPU/GPU/ANE)
sysctl hw.pagesize                    # → 16384  (16 KB pages on Apple Silicon, not 4 KB)
sysctl hw.l1icachesize hw.l1dcachesize        # per-core L1 (notably large on Apple cores)
sysctl hw.perflevel0.l2cachesize              # P-cluster shared L2 (e.g. 16 MB)
sysctl hw.perflevel1.l2cachesize              # E-cluster shared L2
sysctl hw.cachelinesize               # → 128  (128-byte lines)
```

Two transfers to the phone: Apple Silicon uses a **16 KB page** (`hw.pagesize: 16384`) everywhere including iOS — a fact that matters for memory forensics and mmap reasoning — and the **L2 is shared per cluster** (the `perflevel*.l2cachesize` split), the same topology the iPhone's two clusters use. `hw.memsize` is the whole UMA pool; there is no separate "VRAM" key because there is no separate VRAM.

### See the integrated GPU and prove there's no VRAM (UMA)

```bash
system_profiler SPDisplaysDataType | grep -Ei 'Chipset|Type|Bus|Number of Cores|Metal|VRAM|Vendor'
#   Chipset Model: Apple M5 Max
#   Type: GPU
#   Bus: Built-In                  ← integrated; on the SoC die, not a card
#   Total Number of Cores: 40      ← (an iPhone reports far fewer: ~5–6)
#   Vendor: Apple (0x106b)
#   Metal Support: Metal 4
#   (no "VRAM" line at all)        ← because the GPU shares the UMA pool
```

The absent VRAM line is the whole UMA story in one negative space: a discrete GPU would report dedicated VRAM here; Apple's reports `Bus: Built-In` and no VRAM because it reads the *same* `hw.memsize` pool as the CPU and ANE. The iPhone's GPU is the same family and the same Metal API — just fewer cores. → [[00-ios-xcode-and-the-build-system]].

### Enumerate the ARM feature flags (PAC, SME, MTE…)

```bash
# Which architectural features the silicon advertises — these mirror the A-series ISA gen
sysctl hw.optional.arm | grep -Ei 'PAuth|FPAC|SME|MTE|BTI'
#   hw.optional.arm.FEAT_PAuth: 1        ← Pointer Authentication present (the arm64e story)
#   hw.optional.arm.FEAT_PAuth2: 1
#   hw.optional.arm.FEAT_FPAC: 1         ← faulting PAC (immediate trap on auth fail)
#   hw.optional.arm.FEAT_BTI: 1          ← Branch Target Identification
#   hw.optional.arm.FEAT_SME: 1          ← Scalable Matrix Extension
#   hw.optional.arm.FEAT_SME2: 1
#   hw.optional.arm.FEAT_MTE: 1          ← Memory Tagging (present on recent M5/A19-era silicon)
#   hw.optional.arm.sme_max_svl_b: 64    ← SME streaming vector length = 64 bytes = 512-bit
```

`FEAT_PAuth=1` is the whole arm64e story in one line, and `sme_max_svl_b: 64` confirms Apple's **512-bit** SME vector length. Note that on **2026-era** silicon `FEAT_MTE*` is present on the Mac too — the iOS-specific distinction is not "does the chip *have* tagging" but that the A19 runs **EMTE in synchronous mode by default with Tag Confidentiality Enforcement** (= MIE), which a Mac does not. Read the flag, then ask *how it's configured*.

### See arm64e + PAC in a real binary, and contrast with a Simulator binary

```bash
# A platform binary's arm64e slice has PAC active. dyld is the cleanest example —
# note it's a UNIVERSAL binary on Apple Silicon (x86_64 for Rosetta + arm64e):
lipo -archs /usr/lib/dyld                       # → x86_64 arm64e
file /usr/lib/dyld                              # → universal; the arm64e slice is the one you want

# Spot the PAC prologue/epilogue in a system framework:
otool -tv /usr/lib/dyld 2>/dev/null | grep -E 'pac(ia|ib|sp)|aut(ia|ib|sp)|retab|braa|blraa' | head
#   pacibsp
#   retab
#   braa  x16, x17
# (Each 'retab' is an authenticated return; 'braa/blraa' are authenticated indirect branches.)

# Now the contrast: a Simulator app build is plain arm64 macOS, NO PAC, NOT arm64e —
# which is exactly why it's the wrong artifact for ABI/code-signature study.
xcrun simctl get_app_container booted com.apple.MobileSMS app 2>/dev/null
lipo -archs "<that path>/MobileSMS"             # → arm64 (or x86_64) — no 'e', no PAC
```

### Pull the kernelcache / shared cache from an IPSW (the real iOS arm64e)

```bash
# blacktop/ipsw — the standard Mac-side toolkit for iOS firmware internals (no device needed)
brew install blacktop/tap/ipsw

ipsw download ipsw --device iPhone18,1 --version 26.5   # fetch the firmware (large)
ipsw extract --kernel  *.ipsw                           # carve out the kernelcache
ipsw macho info kernelcache.*                           # arch line shows arm64e; lists load cmds
ipsw dyld extract  dyld_shared_cache_arm64e  CoreFoundation   # pull a single framework out

# Confirm the cache is the arm64e (signed-pointer) variant:
ls dyld_shared_cache_arm64e*                            # the file name encodes the arch/PAC ABI
```

This is how you obtain genuine **arm64e, PAC-protected** iOS code to study without ever touching a phone — the substrate for Part 11. The shared cache uses **chained fixups / signed pointers**; let `ipsw` (or a current Ghidra/IDA loader) resolve them rather than reading raw bytes.

## 🧪 Labs

> All labs are **device-free**. Lab 1–2 use your **Apple-Silicon Mac as a microarchitecture proxy** (same P/E/arm64e/PAC/UMA lineage; *not* an A-series part — different core ratio, and even where the Mac exposes the same MTE flag it does not run the A19's synchronous-MIE posture). Lab 3 uses the **Simulator** (no ANE, no PAC, plain arm64 — teaches *absence*) and a **read-only walkthrough**. Nothing here needs a phone.

### Lab 1 — Map the P/E cluster topology and the silicon feature flags (substrate: Mac host as proxy)

**Fidelity caveat:** your Mac's P:E ratio is not the iPhone's 2:4, and a Mac does not enforce the A19's MIE posture even if it advertises `FEAT_MTE`; the *kernel mechanism and feature-flag surface* are the faithful part.

1. Run the `sysctl hw.nperflevels` / `hw.perflevel0.*` / `hw.perflevel1.*` block. Write down your Mac's P:E split and contrast it with the A19's **2P + 4E**. Why does a phone ship E-heavy and a Pro Mac P-heavy? (Answer in terms of CLPC, foreground latency vs. background-dominant duty cycles.)
2. Run `sysctl hw.optional.arm | grep -Ei 'PAuth|FPAC|SME|SME2|MTE|BTI'`. For each `=1`, name the mitigation it represents and one exploit class it blunts. Confirm `sme_max_svl_b` (= 64 → 512-bit SME). If your Mac reports `FEAT_MTE: 1`, articulate the precise distinction from the A19: *having* memory tagging ≠ running **EMTE in synchronous mode by default with Tag Confidentiality Enforcement** (that configured posture is MIE, and it's the iOS-A19 difference).
3. Conclude: which of these flags would be **identical** on the iPhone SoC, and which differ? (PAC/BTI/SME identical or near; the MIE *posture* — not the bare MTE flag — is the frontier delta.)

### Lab 2 — Find PAC in platform code; prove the Simulator binary has none (substrate: Mac binary + Simulator)

**Fidelity caveat:** the *device* shared cache is the canonical arm64e target (Lab via `ipsw` if you fetched one); your Mac's `/usr/lib/dyld` is the same arm64e ABI and a perfect local stand-in.

1. `lipo -archs /usr/lib/dyld` → confirm `arm64e`. Then `otool -tv /usr/lib/dyld | grep -E 'pacibsp|retab|braa|blraa'` and read three of the hits. Identify one **signed prologue** (`pacibsp`) and one **authenticated return** (`retab`). State what salt `pacibsp` uses (the stack pointer).
2. Boot a Simulator, install/run any app, resolve its bundle binary with `simctl get_app_container … app`, and run `lipo -archs` on the Mach-O. Confirm it is **plain `arm64`** with **no** PAC instructions in its prologues. Write the one-sentence rule this proves: *the Simulator is the wrong artifact for studying arm64e/PAC/code-signing because it is a macOS arm64 build.*
3. (Optional, if you ran the `ipsw` Hands-on step.) `ipsw macho info` the extracted **kernelcache** and confirm its arch is `arm64e`. Note that **third-party App Store** apps are *still* plain `arm64` — so PAC reasoning applies to *Apple* code, not to most apps you'll reverse. Record which targets in Part 11 are PAC-protected and which are not.

### Lab 3 — The Neural Engine's absence, and the artifacts it would produce (substrate: Simulator + read-only walkthrough)

**Fidelity caveat:** the Simulator has **no ANE** — Core ML falls back to CPU/GPU, and the device-only `mediaanalysisd`/`photoanalysisd` daemons and their Photos ML metadata **do not populate**. This lab teaches the artifact *by its shape*, since you can't generate it without a device.

1. **Reasoning (Simulator):** a Core ML request configured with `MLComputeUnits.all` will, on a device, prefer the ANE; in the Simulator it runs on CPU/GPU. State why this means you can validate Core ML *plumbing* in the Simulator but never the ANE's *forensic output*.
2. **Walkthrough (sample image / Part 08 forward-link):** enumerate the categories of ANE-produced metadata you'd expect to recover from `Photos.sqlite` on a real device — (a) face detection/clustering, (b) scene/object classification labels, (c) **Live Text OCR** of text inside images. For each, write one sentence on its investigative value (e.g. OCR makes image *contents* keyword-searchable).
3. State the **authorization caveat** in your own words: why an ANE scene-classification label is an investigative *lead*, not a fact the user asserted. → tie back to the ⚖️ callout and [[06-photos-and-the-camera-roll]].

### Lab 4 — Reason out the "is this target PAC-protected?" matrix (paper exercise, no substrate)

**Substrate:** none — a pencil-and-paper check that you've internalized the arm64e/PAC boundary before you open a disassembler in Part 11. Nothing to run; the point is to answer *instantly* in the field.

For each target, state **arm64e + PAC active** or **plain arm64, no PAC**, and one sentence on what that means for your workflow:

| Target you're about to reverse | arm64e + PAC? | Implication |
|---|---|---|
| `kernelcache` from an IPSW | ? | ? |
| `CoreFoundation` pulled from the dyld shared cache | ? | ? |
| A third-party game's main Mach-O from a decrypted `.ipa` | ? | ? |
| The same app built and run in the **Simulator** | ? | ? |
| A system daemon (e.g. `mediaanalysisd`) | ? | ? |

Then answer: (a) For a PAC target, what do you do to a pointer before you trust its value (`xpaci`) — and what must you *not* do with the stripped value if the process is live? (b) Why does Frida injecting into a PAC-protected process need to *re-sign* return pointers? (c) If your call graph in an arm64e cache looks scrambled, what is the first tool-config thing to check (chained-fixups / signed-pointer support)? (Check yourself against the arm64e section and its ⚠️ callout.)

## Pitfalls & gotchas

- **Assuming third-party apps are arm64e.** They are not (in 2026). Only **Apple platform binaries** (kernelcache, dyld, system frameworks, daemons) are arm64e/PAC; normal App Store apps are plain `arm64`, and XNU disables the PAC keys in those processes. Don't go hunting for `pacibsp` in a game binary and conclude the tooling is broken.
- **Reading PAC'd pointers raw.** A pointer off the arm64e kernelcache or shared cache has signature bits in its top byte(s); treat it as an address without `xpaci`-ing it and your offsets are garbage. Equally: **don't store an `xpac`'d pointer back** into a running process — it'll fail the next `AUT*`.
- **Using an arm64e-blind loader on the shared cache.** Old Hopper/IDA/Ghidra versions (or ones without the iOS16+ chained-fixups/signed-pointer support) mis-resolve the cache's pointers and produce wrong call graphs. Verify your loader models arm64e + chained fixups before trusting xrefs.
- **Studying the Simulator binary for ABI/PAC/FairPlay.** A Simulator build is **macOS arm64 (or x86_64)**, not arm64e, not FairPlay-encrypted, ad-hoc signed. It's great for SQLite-schema/layout work and useless for code-signature, PAC, or encryption study. Use a device-class `.ipa` or an IPSW. → [[03-fairplay-encryption-and-decrypting-app-store-apps]].
- **Expecting on-device performance tools.** There is no `powermetrics`, no `sysctl`, no shell on the phone. CPU/GPU/ANE behavior is observed **off-device** — via Xcode Instruments over a tether (dev) or PowerLog/aggregate-dictionary artifacts (forensics) — never live on the box.
- **Treating ANE labels as ground truth.** Scene tags, face clusters, and OCR are *model inferences*. They're investigative gold for search and leads, but a classification is not a user assertion; say which it is in your report.
- **Conflating AMX and SME.** AMX is Apple-private and undocumented (reached only via Accelerate); SME is standard Arm (public on M4+, targetable directly). A disassembler that flags "unknown instruction" in matrix-heavy code is likely choking on AMX encodings, not corrupt bytes.
- **Generalizing the M-series core ratio to the phone.** The microarchitecture transfers; the **2P + 4E** ratio, the ~8–12 GB memory tiers, and the GPU core counts are phone-specific and perishable — re-verify per SoC/SKU (Lesson 00's device matrix). → [[00-soc-lineup-and-device-matrix]].
- **Forgetting jetsam vs. swap.** The Mac swaps; the phone kills. UMA means GPU/ANE workloads raise the *same* memory pressure that triggers jetsam, so "it'll page out" is a macOS reflex that doesn't fire on iOS.

## Key takeaways

- The iPhone SoC is the **same Apple Silicon family** as your M-series Mac — asymmetric P/E clusters scheduled by XNU's **CLPC**, an Apple **TBDR GPU**, a **16-core Neural Engine**, **AMX/SME** matrix units, and **unified memory** — so most of your Mac knowledge transfers; the deltas are what to study.
- **Topology:** A19/A19 Pro = **2 P-cores + 4 E-cores** in two clusters, each cluster a **clock/voltage domain** with its own shared AMX/SME block; placement is QoS/thread-group-driven, not round-robin.
- **The A19 GPU added per-core Neural Accelerators**, spreading ML across three engines (CPU/AMX-SME, ANE, GPU). The Core ML runtime — not your code — chooses the engine.
- **The Neural Engine is an evidence generator:** `mediaanalysisd` runs Vision/ML on the ANE and persists **face clusters, scene/object labels, and Live Text OCR** into the Photos store — machine-generated, keyword-searchable artifacts (treat as leads, not facts).
- **arm64e + PAC is the RE-defining fact:** since A12, **five hardware signing keys** authenticate pointers (`pacibsp`/`retab`/`braa`); **Apple's binaries are arm64e/PAC, most third-party apps are plain arm64**, and you `xpaci` to read addresses. PAC is identical to the Mac's M1+ implementation.
- **Unified memory** means CPU/GPU/ANE share one LPDDR5X pool with no copies — and the phone responds to pressure by **jetsam (killing apps)**, not swap.
- The **silicon memory-safety ladder PAC → PPL → SPTM/TXM → Exclaves → MIE/EMTE (A19)** is a hardware property of these chips that directly governs the 2026 exploit/jailbreak landscape.
- **You have no on-device shell and no device:** study the silicon via your **Mac as a microarchitecture proxy** (`sysctl hw.perflevel*`, `hw.optional.arm.*`), via **Simulator** (for layout/absence), and via **IPSW kernelcache/shared-cache extraction** (`ipsw`) for genuine arm64e code.

## Terms introduced

| Term | Definition |
|---|---|
| SoC | System-on-Chip — the single die integrating CPU clusters, GPU, Neural Engine, SEP, ISP, memory controller, and fixed-function engines. |
| P-core / E-core | Performance / Efficiency CPU cores; the iPhone A19 ships **2P + 4E** in two clusters. |
| Cluster | A group of cores sharing an L2 cache, a matrix (AMX/SME) block, and **one DVFS (voltage/frequency) domain**. |
| DVFS | Dynamic Voltage and Frequency Scaling — per-cluster/per-domain clock+voltage adjustment for power management. |
| CLPC | Closed-Loop Performance Controller — XNU's scheduler component that places thread groups on P vs. E clusters by QoS and measured utilization. |
| PMU / `kperf` / `kpc` | Performance Monitoring Unit (hardware event counters) and the kernel interfaces that read it; entitlement-gated and inaccessible to apps on stock iOS. |
| Dynamic Caching | A17 Pro/M3-era GPU feature allocating on-chip memory to shaders at runtime by actual need, raising occupancy. |
| Hardware ray tracing | A17 Pro+ dedicated GPU silicon for ray/triangle intersection and BVH traversal (vs. shader emulation). |
| Sprint-and-idle | The bursty P-cluster duty cycle a fanless phone is forced into: boost to peak, then thermally throttle; peak GHz is transient. |
| Cold-boot attack | Reading secrets from chilled DRAM after power-off — **not feasible on iOS**: on-package memory, no exposed bus, SEP-gated. |
| Universal binary | A Mach-O packing multiple arch slices (e.g. `x86_64 arm64e` for `/usr/lib/dyld` on Apple Silicon); read the relevant slice with `lipo`. |
| 16 KB page | Apple Silicon's base page size (`hw.pagesize: 16384`) on macOS and iOS alike — relevant to mmap and memory-forensic reasoning. |
| Thread group / QoS class | XNU scheduling abstractions (`USER_INTERACTIVE`…`BACKGROUND`) CLPC uses to decide core placement. |
| TBDR | Tile-Based Deferred Rendering — Apple's GPU architecture; bins geometry into on-chip tiles and shades only visible pixels. |
| Neural Accelerator (GPU) | Per-GPU-core matrix/tensor ALUs added in the **A19** generation, running NN math on the GPU datapath. |
| ANE (Neural Engine) | Apple's fixed-function 16-core NN inference accelerator; the OS reaches it via Core ML. |
| `mediaanalysisd` / `photoanalysisd` | Device daemons that run Vision/ML on the ANE over the photo library, persisting faces/scenes/OCR into the Photos store. |
| Live Text OCR | On-device recognition of text *inside* images (ANE-produced), making image contents keyword-searchable. |
| AMX | Apple Matrix eXtension — Apple's **proprietary, undocumented** per-cluster matrix coprocessor; reached only via Accelerate.framework. |
| SME / SME2 | Arm Scalable Matrix Extension (Armv9.2-A) — the **standard** matrix/streaming-vector unit; first public on Apple's **M4** (2024). |
| UMA | Unified Memory Architecture — one on-package LPDDR5X pool, one address space, shared coherently by CPU/GPU/ANE/AMX. |
| SLC | System-Level Cache — large last-level cache on the SoC fabric shared across compute blocks. |
| jetsam | iOS memory-pressure mechanism that **terminates** apps by priority band (no disk swap). |
| arm64e | The Apple ABI variant that uses Pointer Authentication; the architecture of all Apple **platform** binaries (A12+/M1+). |
| PAC | Pointer Authentication Code — a keyed signature placed in a pointer's high bits to defeat pointer-corruption (ROP/JOP) exploits. |
| PAC keys (APIA/APIB/APDA/APDB/APGA) | The **five hardware** signing keys (instruction A/B, data A/B, generic) — never software-readable, randomized per boot/process. |
| `pacibsp` / `retab` / `xpaci` | Sign LR with key B (salt=SP) / authenticate-and-return / strip PAC bits to recover the raw address. |
| `braa` / `blraa` | Authenticated indirect branch / branch-with-link (PAC-checked function pointers). |
| FEAT_FPAC | The CPU feature where a failed `AUT*` **faults immediately** rather than poisoning the pointer for a later crash. |
| MIE / EMTE | Memory Integrity Enforcement / Enhanced Memory Tagging Extension — A19 hardware memory-tagging (synchronous mode) + secure allocators that fault UAF/OOB at access time. |
| Chained fixups / signed pointers | The dyld-shared-cache rebase format whose pointers carry PAC signatures; loaders must model it to resolve xrefs correctly. |

## Further reading

- **Apple Platform Security guide** (security.apple.com, current edition) — Pointer Authentication, Memory Integrity Enforcement / EMTE, the Secure Enclave's role in Face ID and key handling.
- **Apple Security Research**, "Memory Integrity Enforcement: A complete vision for memory safety in Apple devices" (security.apple.com/blog/memory-integrity-enforcement/) — the A19 MIE/EMTE design, secure allocators, Tag Confidentiality Enforcement.
- **Apple Developer** — *Preparing your app to work with pointer authentication* (the arm64e ABI, why it's "preview" for third parties); *Core ML* `MLComputeUnits` (how the runtime chooses CPU/GPU/ANE); **Accelerate / BNNS** (the AMX path).
- **Arm Architecture Reference Manual** — FEAT_PAuth/PAuth2/FPAC (Pointer Authentication) and FEAT_SME/SME2 (Scalable Matrix Extension) — the authoritative instruction semantics.
- **Jonathan Levin**, *MacOS and iOS Internals* + newosxbook.com / `jtool2` — arm64e in XNU, PAC key management, the kernelcache, and `pac.md`-style write-ups of ARMv8.3 PAuth in XNU.
- **tzakharko/m4-sme-exploration** (GitHub) — empirical reverse-engineering of Apple's SME implementation (512-bit vectors, per-cluster blocks, ZA tile).
- **blacktop/ipsw** (github.com/blacktop/ipsw) — extract/inspect the kernelcache and arm64e dyld shared cache from an IPSW with no device; the Mac-side substrate for Part 11.
- **Project Zero** & **arXiv 2510.09272** (SPTM/TXM/Exclaves) — the kernel-hardening rungs above PAC.
- **Howard Oakley, Eclectic Light Co.** (eclecticlight.co) — accessible deep dives on Apple Silicon co-processors (AMX/SME), the P/E scheduler, and the memory fabric, from the Mac side you already know.
- **Independent µarch analysis** (AnandTech archive, Chips and Cheese, Geekerwan) — the empirical wide-decode / large-ROB / cache-size characterizations of Apple P/E cores; cite the generation and treat exact numbers as perishable.
- **Apple Developer — Metal** (Dynamic Caching, hardware ray tracing, Metal Performance Shaders) and **Core ML** compute-unit selection — how work is actually scheduled across GPU/ANE/CPU.
- `man sysctl` — `hw.perflevel*`, `hw.optional.arm.*`, `machdep.cpu.*` keys for probing the silicon family on your Mac.

---
*Related lessons: [[00-soc-lineup-and-device-matrix]] | [[02-secure-enclave-hardware]] | [[06-kernel-hardening-pac-sptm-txm-mie]] | [[00-mach-o-arm64-deep-dive]] | [[02-the-dyld-shared-cache]] | [[05-dynamic-analysis-with-frida]] | [[06-photos-and-the-camera-roll]] | [[06-memory-jetsam-app-lifecycle]] | [[06-biometrics-hardware-faceid-touchid]]*
