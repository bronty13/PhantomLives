---
title: "Kernel hardening: PAC, PPL, SPTM/TXM, MIE"
part: "03 — Security Architecture"
lesson: 06
est_time: "55 min read + 20 min labs"
prerequisites: [cpu-gpu-npu-microarchitecture, the-ios-security-model]
tags: [ios, kernel-hardening, pac, ppl, sptm, txm, mie, mitigations]
last_reviewed: 2026-06-26
---

# Kernel hardening: PAC, PPL, SPTM/TXM, MIE

> **In one sentence:** Apple turned the iPhone kernel from a single soft target into a layered fortress by stacking hardware-backed mitigations — KASLR, KTRR, PAC, PPL, then SPTM/TXM, Exclaves, and MIE — so that each rung retired a whole exploitation technique and "kernel read/write" stopped being game over.

## Why this matters

If you came from `macos-mastery`, you already met PAC and the SPTM/TXM monitor pair on Apple Silicon — but iOS is where every one of these defenses was *pioneered*, shipped first, and is enforced most aggressively (no SIP-disable escape hatch, no "developer mode" that turns off AMFI). For a forensics professional the practical payoff is brutal and direct: **this ladder is the reason full-file-system acquisition by exploitation died on modern devices.** The A11→A12 wall and then the A13→A14 wall in your acquisition matrix are not arbitrary — they are exactly the device generations where KTRR, then PAC, then PPL/SPTM landed. For a builder and reverse-engineer, understanding which rung blocks which primitive tells you why a given jailbreak only reaches iOS 18.7 on A11, why TrollStore froze at iOS 17.0, and why "I have a kernel memory-write" no longer implies "I own the device." This lesson is the defensive map: each mitigation, the bug class it closed, the silicon generation that gates it, and the on-disk and crash-log fingerprints it leaves.

## Concepts

### The threat model these rungs attack

Memory-corruption exploitation on iOS historically followed a pipeline:

```
  bug (heap overflow / UAF / type confusion)
      │  corrupt an object
      ▼
  arbitrary read  ──►  defeat KASLR (leak a kernel pointer)
      │
      ▼
  arbitrary write ──►  patch a function pointer / page table / syscall handler
      │
      ▼
  PC control      ──►  ROP/JOP chain → set TF, map RWX, install payload
      │
      ▼
  "kernel R/W"    ──►  game over: disable AMFI, sandbox, code signing
```

Every rung below severs one of these arrows. Read the ladder as a sequence of "this arrow no longer works" statements, not as a pile of unrelated features.

| Rung | Mitigation | First gated on | Attacks the step… | Kills / raises cost of |
|---|---|---|---|---|
| 0 | **KASLR** | iOS 6 (software) | leak/locate | hardcoded kernel addresses |
| 1 | **KPP** (Kernel Patch Protection) | A8–A9 (software, EL3) | arbitrary write to kernel text | static kernel patching — *TOCTOU-bypassable* |
| 2 | **KTRR / CTRR** | A10+ (hardware) | arbitrary write to kernel text | all kernel-text modification |
| 3 | **PAC** (Pointer Authentication) | A12+ (arm64e) | PC control / pointer corruption | ROP/JOP, function-pointer hijack |
| 4 | **PPL** (Page Protection Layer) | A12–A14 (APRR/GXF) | page-table writes from kernel | RWX mappings, code-signing bypass |
| 5 | **SPTM + TXM** | A15+/M2+ (GXF) | *everything above, from a monitor* | page-table forgery even with kernel R/W |
| 6 | **Secure Exclaves** | iOS 17+ / A18·M4 source | reaching isolated state | secrets/biometrics readable by a pwned XNU |
| 7 | **MIE / EMTE** | A19 / M5 | the bug itself | the heap overflow / UAF / type confusion |

> 🖥️ **macOS contrast:** This is the *same* lineage you touched on Apple Silicon Macs — arm64e PAC, and SPTM+TXM on A15-class/M2+ silicon — because both OSes run XNU on the same SoC families. The differences are scope and escape hatches: **PPL was iOS/iPadOS/watchOS/visionOS only and never shipped on macOS** (Apple's *Operating system integrity* doc says so explicitly); Apple Silicon Macs jumped straight to SPTM/TXM. And on macOS you can still `csrutil disable` SIP and lower some protections in 1-True-Recovery; on iOS there is no equivalent toggle — the ladder is load-bearing and always on.

---

### Rung 0 — KASLR: randomize the target

**KASLR** (Kernel Address Space Layout Randomization) slides the kernelcache's base load address by a random per-boot offset (the *kernel slide*), so an attacker can't hardcode `0xFFFFFFF0xxxxxxxx` gadget addresses. iOS computes the slide in iBoot during the boot chain (see [[01-boot-chain-securerom-iboot]]) and the kernelcache is loaded at base + slide.

KASLR alone is weak — a single pointer leak (an `arbitrary read`) recovers the slide and the whole layout falls. Its real job is to *force* the attacker to find and chain an info-leak before anything else, raising the bug-count of a working chain. Every later rung assumes KASLR has already been defeated and defends anyway.

> 🔬 **Forensics note:** The kernel slide is per-boot. When you correlate a kernel panic log (on iOS the `panic-full-*.ips` reports live under `/private/var/mobile/Library/Logs/CrashReporter/`, surfaced in *Settings ▸ Privacy ▸ Analytics* and in sysdiagnose; `/private/var/db/PanicReporter/` is the **macOS** staging path, not iOS's) against symbolized addresses, you must first recover the slide from the panic header's `kernel slide` / `kernel text base` field — otherwise every faulting address is meaningless. The same slide governs how an exploit's leaked pointers map back to symbols when you reverse a captured chain.

---

### Rung 1 — KPP: software integrity polling, and why it lost

**KPP** ("Kernel Patch Protection," nicknamed *watchtower*) shipped on A8–A9 as a software monitor running in **EL3**, the ARM secure monitor — the most privileged level then in use. Periodically (and on certain transitions) it re-hashed the kernel's read-only regions (`__TEXT`, `__DATA.const`, page tables) and panicked if they had changed. It was the first attempt to make "I wrote to kernel text" not equal "I win."

It lost because polling is a **TOCTOU** (time-of-check/time-of-use) race: a jailbreak could patch the kernel, do its work, and restore the original bytes before KPP next looked — or simply avoid the regions KPP hashed and instead patch *data* pointers it never checked. KPP was repeatedly bypassed (Pangu, Luca Todesco's work). The lesson Apple drew: **don't poll integrity in software — enforce it in hardware so the write never lands.**

---

### Rung 2 — KTRR / CTRR: hardware-locked kernel text

**KTRR** (Kernel Text Read-only Region), introduced on **A10**, replaced KPP with memory-controller enforcement. At the end of early boot, iBoot/the kernel programs lock registers in the **AMCC** (Apple Memory Cache Controller / the memory fabric) that define a physical address range — the kernel's `__TEXT` and read-only data — and mark it **immutable**: writes to that range are rejected *by the hardware*, and the lock registers themselves become write-once until reset. There is no polling window because there is no successful write to race. On later silicon this generalized into **CTRR** (Configurable Text Read-only Region), covering more regions.

KTRR is the umbrella **KIP** (Kernel Integrity Protection) that Apple's docs cite from A10 onward. Its limitation is scope: it freezes kernel *code*, but page tables and many writable kernel structures remain mutable from EL1 — so an attacker who can't patch code anymore pivots to **patching page tables** to map their own code as executable. That pivot is exactly what Rung 4 (PPL) closes.

> 🖥️ **macOS contrast:** The macOS analogue is the same KTRR/CTRR hardware on Apple Silicon plus the **Signed System Volume (SSV)** sealing the on-disk system, which you met in `macos-mastery`. KTRR protects the in-memory kernel text; SSV protects the on-disk system image. iOS has had a sealed system volume and immutable kernel text far longer and without an opt-out.

---

### Rung 3 — PAC: signing pointers so corrupted ones fault

**PAC** (Pointer Authentication), shipped with the **arm64e** ABI on **A12** (2018), is the rung that broke classic ROP/JOP. ARMv8.3-A's Pointer Authentication uses the fact that a 64-bit pointer doesn't need all 64 bits for a virtual address — the unused high bits (above the ~39–47-bit VA, under Top-Byte-Ignore) are free. PAC stuffs a cryptographic **Pointer Authentication Code** into those bits.

Mechanics:

- **Sign**: `PACIA x0, x1` computes a MAC over the pointer in `x0` using a 64-bit **context/modifier** (`x1` — often the stack pointer, a type discriminator, or a hardcoded constant) and writes the truncated MAC into the pointer's high bits.
- **Authenticate**: `AUTIA x0, x1` recomputes the MAC; if it matches, it strips the PAC and yields the real pointer; if it *doesn't*, it sets the high bits to a non-canonical value so the very next dereference **faults** (a translation fault).
- Combined forms — `RETAB` (authenticated return), `BLRAA`/`BRAA` (authenticated indirect call/branch) — make return addresses and function pointers self-verifying.

Five keys live in registers the kernel manages and userspace can't read: **IA, IB** (instruction/code pointers), **DA, DB** (data pointers), and **GA** (generic, for `PACGA` over arbitrary data). The cryptographic primitive is **implementation-defined**: Arm's reference design specifies a QARMA-family cipher (QARMA-64), but **Apple's own cores compute PACs with a proprietary, undocumented algorithm** — which is why you can't simply reimplement QARMA in userspace to forge a PAC (Project Zero's iPhone XS analysis showed the per-boot, EL-dependent keying defeats that). Crucially the keys differ per privilege level and (for processes) are per-process, so a signed pointer from one context can't be forged or replayed into another.

Why this guts ROP/JOP: an attacker who corrupts a return address or vtable pointer no longer controls a *valid* pointer — they control bits that will fail `AUTIA` and fault on use. To redirect control flow they now need a **signing oracle** (some code path that signs an attacker-influenced pointer with the right key+context) or a genuine signed gadget, which is dramatically scarcer than "any executable address."

PAC is hardening, not a wall. Known pressure points: **signing oracles**, reuse of pointers signed with a constant/guessable context, and the speculative **PACMAN** attack (MIT, Ravichandran et al., 2022) that turns the CPU's speculation into a PAC-verification oracle to brute-force a forgery without crashing. Apple treats PAC as raising cost, and stacks the page-table and tagging rungs on top precisely because PAC isn't absolute.

> 🔬 **Forensics note:** A PAC authentication failure produces a very recognizable crash: an `EXC_BAD_ACCESS` whose faulting address has a non-canonical, high-bit-set pattern (e.g. an address like `0x004000…` smeared into the top bits) rather than a clean small offset. In a crash report under `/private/var/mobile/Library/Logs/CrashReporter/` (pulled via sysdiagnose — see [[12-unified-logs-sysdiagnose-crash-network]]), a cluster of these on a sensitive process is a fingerprint of an *attempted* control-flow-hijack exploit that PAC defeated. Spyware-triage tools (mvt) lean on exactly these crash signatures.

> 🖥️ **macOS contrast:** Your Apple Silicon Mac runs arm64e for the kernel and system libraries too — the same five hardware keys, the same Apple PAC cipher (not stock QARMA), the same `PACIA`/`AUTIA`. The visible gap is **third-party userland**: on macOS many apps still ship plain `arm64` slices, and on iOS the third-party user-mode PAC ABI was long a "preview." System binaries and the kernel are arm64e on both. You can disassemble your Mac's own `/usr/lib/dyld` right now and watch PAC at work (Lab 1).

---

### Rung 4 — PPL: taking the page tables away from the kernel

KTRR froze code; attackers pivoted to forging **page tables** to mint new executable mappings. **PPL** (Page Protection Layer), introduced on the A12–A14 generation (iOS 14 era), closed that pivot by making the page tables writable *only* from a tiny, separate code domain — even the EL1 kernel can't write a PTE directly.

The hardware trick is Apple-proprietary and was reverse-engineered publicly (Sven Peter, Asahi Linux; Project Zero's Brandon Azad):

- **APRR** (Access Permission Restriction/Remapping Register, A12–A13) and later **SPRR** (Shadow Permission Remapping Register) let the SoC *reinterpret* the meaning of a page's permission bits depending on a mode bit — so the same page is read-only to "normal kernel" and read-write only inside "PPL mode."
- **GXF** (Guarded eXecution Feature) adds **lateral guarded levels** reachable only via the proprietary `GENTER` instruction (and left via `GEXIT`). PPL's page-table code lives in a guarded context; the kernel must `GENTER` into a validated PPL entry point and *ask* PPL to make a mapping change, which PPL validates against its rules.

Net effect: with full EL1 kernel R/W, an attacker still **cannot** flip a page to RWX or remap code, because the only code that can touch a PTE is the PPL handler, entered through a narrow, checked gate. This is the conceptual inversion that SPTM later generalized: *privilege is no longer monotonic with EL1.*

---

### Rung 5 — SPTM + TXM: the monitor layer (A15+/M2+)

On **A15/M2 and later**, Apple replaced PPL with two cooperating monitors, **SPTM** (Secure Page Table Monitor) and **TXM** (Trusted Execution Monitor). Apple's *Operating system integrity* documentation states it plainly: *"SPTM (in combination with TXM) replaces the PPL, providing a smaller attack surface that doesn't rely on trust of the kernel."* The definitive public analysis is Steffin & Classen, **arXiv 2510.09272**, *"Modern iOS Security Features — A Deep Dive into SPTM, TXM, and Exclaves"* (Oct 2025), built on the XNU source Apple released for A18/M4.

The architecture uses **GXF guarded levels (GL0/GL1/GL2)** that run *laterally* to the normal ARM exception levels (EL0/EL1/EL2), entered via `GENTER` / left via `GEXIT`:

```
        normal world (ELx)              guarded world (GLx)
  ┌───────────────────────────┐   ┌──────────────────────────────┐
  EL0  user apps               │   │ GL0  TXM + unprivileged       │
  EL1  XNU kernel  ───GENTER──►│   │      exclave components       │
       (full R/W of its own    │   │ GL1  Secure Kernel (exclaves) │
        memory, but NOT page    │   │ GL2  SPTM ◄── sole page-table │
        tables)                 │   │           authority           │
  └───────────────────────────┘   └──────────────────────────────┘
        kernel compromise here  ──►  cannot forge entry into / write GLx
```

> ⚠️ **The exact GLx-to-component index shifted as Exclaves were added and the sources disagree on edge details (whether XNU is described at EL1 vs EL2, and TXM at GL0 vs GL1). Trust arXiv 2510.09272 for the precise mapping on a given build; the durable facts are: SPTM is the highest-privileged monitor at GL2, TXM and the exclave kernel sit in guarded levels the EL1 kernel cannot write, and the kernel reaches them only through `GENTER`.**

**SPTM** is the *sole authority over page tables and physical-frame typing.* It maintains a global **frame table** assigning every physical frame a **type** — e.g. `XNU_DEFAULT`, `TXM_RW`, `SK_SHARED_RO`, page-table frames, code frames. A frame can only be **retyped** by its owning domain, and only along transitions allowed by a hardcoded rule bitmask, validated by SPTM at GL2. The kernel never writes a PTE; it calls SPTM, which checks the source and destination frame types before performing the write. So even an attacker with arbitrary EL1 kernel write **cannot** mark a data page executable, cannot map kernel text writable, and cannot point a translation-table base register at attacker-controlled tables — those operations route through SPTM and violate the typing rules.

**TXM** owns **code-signing and entitlement verification** — it's the policy brain that used to live inside AMFI in the kernel (see [[04-code-signing-amfi-entitlements]] and [[07-dyld-shared-cache-and-amfi]]). By hoisting "is this code allowed to execute / does this process hold this entitlement?" into a guarded monitor the kernel can't tamper with, a kernel compromise can no longer simply flip the `cs_flags` or stuff a fake entitlement into a process to defeat code signing. The `GENTER` opcode itself is fixed (`0x00201420`); the monitors expose narrow, validated call interfaces, not a general write primitive.

> 🔬 **Forensics note:** This is *why the post-A14 acquisition cliff exists.* Commercial full-file-system tools historically relied on a kernel-R/W jailbreak to disable AMFI/sandbox and dump the encrypted filesystem after unlocking the keybag. With SPTM/TXM, kernel R/W alone no longer disables code signing or remaps code — so on A15+ there is **no public exploitation path to FFS**, and acquisition collapses back to AFU/BFU logical, backup, and (for A12–A13) the `usbliter8` BootROM lane. See [[01-the-acquisition-taxonomy]] and [[05-full-file-system-acquisition]].

---

### Rung 6 — Secure Exclaves: domains XNU can't see

The frame-typing machinery SPTM introduced is the substrate for **Secure Exclaves**, surfaced from iOS 17 and made legible in the A18/M4 XNU source. An **exclave** is a resource — memory, a service, a sensor pipeline — that is **isolated from XNU and remains protected even if the kernel is fully compromised.** Where SPTM/TXM protect the kernel *from corruption of its own code/tables*, exclaves protect *secrets and sensitive functions from the kernel itself.*

Mechanically: a **Secure Kernel (SK)** runs at a guarded level (GL1) and manages "conclaves" of isolated user workloads; SPTM frame types (`SK_SHARED_RO`, etc.) wall their memory off from `XNU_DEFAULT` frames. XNU communicates with this world only through a **secure-world request handler, `xnuproxy`**, with the **Tightbeam** IPC framework layered on top to provide structured, typed messages and endpoint abstraction — a deliberately small, schema'd interface rather than shared writable memory. Use cases include hardening sensitive media/sensor paths (e.g. the camera indicator privacy guarantee) and isolating cryptographic material so that "I have kernel R/W" does not imply "I can read that secret."

> 🖥️ **macOS contrast:** Exclaves are part of the same XNU you run on Apple Silicon Macs and appear in the shared XNU source — but the architecture's *forensic* consequence is most acute on iOS, where you can't disable the surrounding protections to reach the isolated state.

---

### Rung 7 — MIE / EMTE: kill the bug, not just the technique

Rungs 0–6 all assume the memory-corruption bug *fires* and then make exploiting it expensive. **MIE** (Memory Integrity Enforcement), shipped on **A19 / A19 Pro** (iPhone 17 line, Sept 2025) and the **M5** generation, attacks the bug itself. It is the most significant consumer memory-safety advance Apple has shipped, documented in the Apple Security Research blog *"Memory Integrity Enforcement: A complete vision for memory safety"* and in Apple's *Operating system integrity* guide.

MIE is three things working together:

1. **EMTE — Enhanced Memory Tagging Extension.** ARM's **MTE** (Memory Tagging Extension, 2019 spec) assigns a **4-bit tag** to every 16-byte memory **granule** and stores a matching 4-bit tag in the unused top byte of every pointer (Top-Byte-Ignore real estate). On access, hardware checks pointer-tag == memory-tag; mismatch → fault. Apple found weaknesses in the baseline and, with Arm, drove the **2022 EMTE** refinement (Arm's `FEAT_MTE4`), which it implements. The allocator tags each allocation with a **secret** tag and **re-tags on free**, so:
   - **Linear heap overflow** → spills into an adjacent allocation with a *different* tag → fault.
   - **Use-after-free** → the freed chunk was re-tagged, the stale pointer carries the old tag → fault.
   - **Type confusion** → segregated, differently-tagged allocations don't match → fault.
2. **Synchronous mode, always on.** MTE has an *async* mode (report later, cheap, leaves an exploitation window) and a *sync* mode (fault immediately). Apple committed silicon to run **synchronous enforcement always-on**, so a tag mismatch terminates the offending process *at the instruction*, closing the timing windows async leaves open. This is the expensive choice MIE's silicon budget pays for.
3. **Tag Confidentiality Enforcement.** Tags are only as good as their secrecy. Apple added defenses against side-channel and speculative leakage of tag values — hardened tag-checking instructions, frequent re-seeding of the tag PRNG, and Spectre-V1 mitigations (Apple's analysis: an attacker would need **25+ V1 sequences** to clear a 95% tag-recovery rate).

MIE leans on Apple's **typed secure allocators** — `kalloc_type` (kernel), `xzone malloc` (userland), and WebKit's `libpas` — which already group allocations by type so tagging cleanly separates them. Coverage spans the **kernel plus 70+ userland processes** and is available to third-party apps. The residue Apple acknowledges: pure *intra-allocation* overflows (corrupting within one tagged buffer) survive, but Apple characterizes these as rare, and notes that because memory-corruption bugs are normally interchangeable in a chain, MIE's breadth means an attacker can't just swap in a different bug to rebuild a broken chain.

> 🔬 **Forensics note:** MIE converts *silent* corruption into a *loud, logged crash.* An EMTE tag-check fault terminates the process and writes a crash report — so on A19/M5 devices a memory-safety exploitation attempt now leaves an artifact where before it might have succeeded quietly. Expect MTE-fault crash signatures (a sync tag-check exception, often surfaced as `EXC_BAD_ACCESS` with MTE fault metadata / `KERN_PROTECTION_FAILURE`-class info) to become a primary spyware-triage indicator alongside the PAC-fault pattern. This is the same mvt/crash-log triage angle as Rung 3, now firing on the *bug* instead of the technique.

> 🖥️ **macOS contrast:** MTE/EMTE rides the same SoC family, so **M5-class Macs gain MIE-equivalent tagging** (`FEAT_MTE: 1`, `FEAT_MTE4: 1` — EMTE — with `FEAT_MTE_ASYNC: 0`, i.e. always-synchronous), while older Apple Silicon Macs (M1–M4) report `FEAT_MTE: 0` or omit the key entirely — exactly mirroring the A19 gate on iPhone. You can prove your own Mac's MTE status from `sysctl` (Lab 2): a `0` dates the host as pre-M5, a `1` as M5-or-later — either way the value *is* the teachable result.

---

### The privilege inversion: why "kernel R/W" stopped being game over

Put the rungs together and the classic exploitation pipeline is severed at every arrow:

```
  bug ───────────────► MIE/EMTE faults at the corruption (A19/M5)
  arbitrary read ─────► KASLR forces a leak first (always)
  PC control ─────────► PAC faults on a corrupted pointer (A12+)
  map RWX / patch PTE ► SPTM owns page tables; kernel can't (A15+/M2+)
  disable AMFI ───────► TXM owns code signing, outside XNU (A15+/M2+)
  read secrets ───────► Exclaves isolate them from XNU (iOS 17+)
```

The single most important shift is the move from a **monotonic** privilege model (EL0 < EL1 = total power) to one where the **most security-critical operations re-validate above the kernel.** Pre-A12, kernel R/W *was* the win condition. From A15+, an attacker holding arbitrary EL1 read/write still cannot: write a page-table entry, mark memory executable, forge a code signature or entitlement, or read an exclave secret — because each of those routes through a guarded monitor that checks the operation regardless of how privileged the *caller* is. **The kernel is no longer the top of the trust hierarchy.**

> 🔬 **Forensics note:** This is the structural reason the BootROM-exploit boundary (`checkm8` A8–A11, `usbliter8` A12–A13) matters so much: a BootROM exploit gives code-exec *below* the signature checks at DFU time, but it still doesn't hand you SPTM/TXM authority or the Data-Protection keys on a locked device. And on **A14+** there's no public BootROM exploit *and* no public A12+ kernel jailbreak on iOS 18/26 — so the mitigation ladder, not any single bug, is why modern-device acquisition regressed to logical/backup/AFU. The "wall" your acquisition matrix records at A13→A14 is this ladder reaching critical mass. See [[07-the-jailbreak-landscape-2026]].

## Hands-on

There is no on-device shell, and none of this needs one — you can observe PAC, the arm64e ABI, the CPU feature gates, and the SPTM/TXM firmware images entirely from your Mac and from public IPSWs. Fidelity caveat up front: your Mac *enforces* these as macOS, not iOS, but the ISA, the instructions, and the firmware layout are the same XNU/Apple-Silicon substrate.

**Confirm a binary is arm64e and watch PAC in the disassembly:**

```bash
# Which slices does dyld ship? On current macOS it's universal; the
# arm64e slice is the PAC-enabled one (most system *.dylib files no longer
# exist on disk — they live only in the dyld shared cache — but the linker
# /usr/lib/dyld and on-disk executables like /bin/ls are real arm64e files):
lipo -archs /usr/lib/dyld
# x86_64 arm64e

# The Mach-O header marks arm64e via the 'E' cpusubtype:
otool -hv /usr/lib/dyld | sed -n '1,4p'
#       magic  cputype cpusubtype  caps    filetype  ...
# MH_MAGIC_64    ARM64          E USR00    DYLINKER ...   <- 'E' = arm64e (PAC ABI)

# Find PAC instructions in real code:
otool -tV /usr/lib/dyld 2>/dev/null \
  | grep -Eo '\b(pacia|pacib|pacda|autia|autib|autda|retab|braa|brab|blraa|blrab)\b' \
  | sort | uniq -c | sort -rn | head
#   1497 retab          <- authenticated returns dominate
#    571 blraa
#    556 pacia
#    ...                <- exact counts vary by build; every authenticated
#                          return and indirect call shows up here
```

**Read the hardware feature gates the rungs depend on:**

```bash
# PAC present on every Apple Silicon Mac (A12-era ISA and up).
# Mind the casing — the oid is FEAT_PAuth, NOT FEAT_PAUTH (an all-caps
# query just returns "unknown oid"):
sysctl hw.optional.arm.FEAT_PAuth
# hw.optional.arm.FEAT_PAuth: 1

# MTE/EMTE — the MIE gate. EMTE is Arm's 2022 spec, surfaced as FEAT_MTE4.
sysctl hw.optional.arm.FEAT_MTE hw.optional.arm.FEAT_MTE4 hw.optional.arm.FEAT_MTE_ASYNC 2>/dev/null
# On M1–M4: hw.optional.arm.FEAT_MTE: 0  (or the key is absent) — no MTE silicon.
# On M5-class Macs: FEAT_MTE: 1 and FEAT_MTE4: 1 (EMTE), with
# FEAT_MTE_ASYNC: 0 — because Apple runs MTE always-synchronous, never async.
# Either value dates your Mac's silicon against the A19/M5 gate.

# Dump the whole ARM feature vector to see the ladder's hardware basis:
sysctl -a | grep -i 'hw.optional.arm.FEAT_' | sort
```

**Pull a real kernelcache and find the SPTM/TXM firmware images (read-only, static):**

```bash
brew install blacktop/tap/ipsw          # the iOS firmware Swiss-army knife

# Download an iOS 26.x IPSW for a modern device, then list its firmware images.
# iPhone18,1 = iPhone 17 Pro (A19 Pro) — a current A19/MIE device that also
# carries SPTM/TXM. (iPhone17,1 is the iPhone 16 Pro / A18 Pro — SPTM/TXM but
# no MIE.) Re-verify the current device id + OS at author time:
ipsw download ipsw --device iPhone18,1 --version 26.5
ipsw extract --kbag --files iPhone18,1_26.5_*.ipsw         # inspect Img4 payloads

# The kernelcache, SPTM and TXM ship as SEPARATE signed Mach-O images now —
# look for the 'sptm' and 'txm' firmware entries alongside 'kernelcache':
ipsw img4 extract --help
ipsw macho info <extracted-kernelcache> | grep -iE 'arm64e|segname|__TEXT_EXEC'
#   ... CPU = AARCH64 (E)  PAC ...     <- the kernel is arm64e
```

`ipsw` (blacktop) and `jtool2`/`ipsw kernel` let you confirm, without any device, that on a modern build the kernel is arm64e and that **SPTM and TXM are distinct firmware payloads** loaded by iBoot — the physical evidence that page-table and code-signing authority moved out of the monolithic kernel image.

## 🧪 Labs

> ⚠️ **Substrate reality:** Every lab below runs on your **Mac host** (its own arm64e userland), on a **public IPSW**, or as a **read-only walkthrough** of described device output. The **Simulator is the wrong tool here and the labs deliberately avoid it**: CoreSimulator runs your apps as plain `arm64` macOS processes with **no arm64e PAC enforcement, no SPTM/TXM, no MTE, no AMFI/sandbox** — it teaches container *layout*, not kernel hardening. There is no A19/M5 device available, so MIE/EMTE behavior is narrated, not executed.

### Lab 1 — See PAC in your Mac's own arm64e userland (Substrate: Mac host)

*Fidelity caveat: this is macOS arm64e — identical ISA and PAC mechanism to iOS, but the keys/enforcement context are macOS's, not a locked iPhone's.*

1. Confirm the dynamic linker is arm64e: `lipo -archs /usr/lib/dyld` lists `arm64e` (alongside `x86_64` on a universal build). **Note:** most system dylibs (`libsystem_c.dylib`, `libSystem.B.dylib`, the Foundation binary, …) **no longer exist as standalone files** — they live only inside the dyld shared cache, so `lipo`/`otool` on those `/usr/lib/*.dylib` paths errors with *No such file or directory*. Use `/usr/lib/dyld` or an on-disk executable like `/bin/ls` as your arm64e target.
2. Disassemble it and count authenticated returns vs. plain returns:
   ```bash
   otool -tV /usr/lib/dyld 2>/dev/null \
     | grep -Eo '\b(ret|retab)\b' | sort | uniq -c
   ```
   Note how `retab` (authenticated) dominates over bare `ret`. Explain to yourself why a stack-smash that overwrites a saved LR can no longer redirect a `retab`.
3. Find an indirect call site (`blraa`) and identify which register supplies the **modifier/context**. That context is what makes a stolen, signed pointer non-replayable into a different call site.

### Lab 2 — Map the hardware gate to the mitigation ladder (Substrate: Mac host)

1. Run `sysctl -a | grep -i 'hw.optional.arm.FEAT_' | sort` and locate `FEAT_PAuth`, `FEAT_MTE`, `FEAT_MTE4`, `FEAT_BTI` (mind the casing — the oid is `FEAT_PAuth`, not `FEAT_PAUTH`, which errors as *unknown oid*).
2. Record which are `1` and which are `0` on your Mac. On **M1–M4** `FEAT_MTE` reads `0` (or is absent) — no MTE silicon; on an **M5-class** Mac it reads `1`, with `FEAT_MTE4: 1` (EMTE) and `FEAT_MTE_ASYNC: 0` (Apple runs MTE always-synchronous).
3. Write one sentence each mapping a present/absent feature to a rung: `FEAT_PAuth=1` ⇒ Rung 3 (PAC) active; `FEAT_MTE` (`0` on M1–M4, `1` on M5) ⇒ Rung 7 (MIE/EMTE) is **silicon-gated** to A19/M5 and *cannot* be back-ported in software — the value you read literally dates your Mac's silicon against the gate. This is the concrete proof of the "hardware-backed" claim.

### Lab 3 — Find SPTM/TXM in a real firmware image (Substrate: public IPSW, read-only)

*Fidelity caveat: static inspection only — you can see the images and the arm64e kernel, but you cannot run or instrument them without a device.*

1. `brew install blacktop/tap/ipsw`.
2. Download an iOS 26.x IPSW for an A15+/A17/A19 device and an old iOS for an A11 device (e.g. iPhone 8) for contrast.
3. List firmware payloads in each. Confirm the modern image carries **separate `sptm` and `txm`** images while the A11 image does **not** (PPL/SPTM didn't exist there). This is the on-disk evidence of Rung 5.
4. `ipsw macho info` the kernelcache from each: the modern one is `arm64e (… PAC)`; confirm the A11 kernel is plain `arm64`. You've just dated the PAC boundary by inspecting two firmwares.

### Lab 4 — Read a mitigation-fault crash signature (Substrate: read-only walkthrough / sample crash log)

*Fidelity caveat: no A19 device, so the MIE/EMTE fault is described; the PAC-fault pattern you can reproduce conceptually from any crash report.*

1. In a sample iOS crash report (iLEAPP/mvt test data, or any `*.ips` from a sysdiagnose) under the CrashReporter path, locate `Exception Type` and the faulting address.
2. Identify the two mitigation fingerprints to triage for:
   - **PAC fault** — `EXC_BAD_ACCESS` with a faulting address whose *high* bits are set (a stripped/garbled authenticated pointer), not a small near-null offset.
   - **MTE/EMTE fault (A19/M5)** — a synchronous tag-check exception terminating the process at the access; MIE makes this the *expected* outcome of a heap overflow/UAF instead of silent success.
3. Write the triage rule: a *cluster* of these faults on a sensitive, network-facing process (e.g. a messaging or media daemon) is an exploitation-attempt indicator — the same logic mvt uses for spyware triage. Cross-reference [[12-unified-logs-sysdiagnose-crash-network]].

## Pitfalls & gotchas

- **"arm64e" ≠ "PAC protects this app."** System binaries and the kernel are arm64e; much third-party userland historically shipped plain `arm64`, and the third-party user-mode PAC ABI was a long-running "preview." Don't assume an App Store binary is PAC-hardened just because the device supports it — check the slice (`lipo -archs`) and the Mach-O PtrAuth flag.
- **PAC is cost, not a wall.** Signing oracles, constant/guessable contexts, and the speculative **PACMAN** attack mean PAC can be bypassed under the right primitive. Treat "PAC defeats ROP" as "PAC makes ROP need extra bugs," not "ROP is impossible."
- **KPP vs KTRR confusion.** KPP was *software*, *polling*, in EL3, and TOCTOU-bypassable (A8–A9). KTRR/CTRR is *hardware*, *enforced at the memory controller*, with no race (A10+). Conflating them mis-dates the boundary.
- **PPL was never on macOS.** Apple's own integrity doc scopes PPL to iOS/iPadOS/watchOS/visionOS; Apple Silicon Macs went straight to SPTM/TXM. If you're reasoning about a Mac, skip Rung 4 and go to Rung 5.
- **Don't conflate these AP-side rungs with the SEP.** Everything here runs on the **Application Processor**. The **Secure Enclave** is a *separate coprocessor* with its own ROM, kernel, and keys — passcode brute-force throttling and Data-Protection key release live there, not in SPTM/TXM. A kernel/SPTM compromise is not a SEP compromise. See [[01-sep-sepos-deep-dive]] and [[02-secure-enclave-hardware]].
- **MIE is silicon-gated and not back-portable.** EMTE needs A19/M5 hardware. iOS 26 on an A17 device does **not** get MIE; there is no software fallback. Don't claim "iOS 26 has MIE" — claim "A19/M5 running iOS 26 has MIE."
- **The mitigation ladder is *why* acquisition regressed — don't blame the tool.** If a commercial extraction tool only offers logical/AFU on an A16 device, that's the SPTM/TXM wall, not a tool defect. The honest report is "no public FFS path exists on A15+," per [[01-the-acquisition-taxonomy]].
- **Crash logs are the artifact, but they expire and are sampled.** Mitigation-fault crash reports rotate out and may be uploaded/cleared. Pull sysdiagnose/crash logs *early* in triage; absence of a crash isn't proof of absence of an attempt.

## Key takeaways

- The hardening ladder is a **sequence of severed exploitation arrows**: KASLR (locate) → KPP/KTRR (patch kernel text) → PAC (PC control) → PPL/SPTM (page tables) → TXM (code signing) → Exclaves (read secrets) → MIE (the bug itself).
- **PAC** (A12+, arm64e) signs return addresses and pointers with keyed MACs (Apple's proprietary PAC cipher, not stock QARMA) in a pointer's unused high bits, so a corrupted pointer faults on use — gutting classic ROP/JOP, though signing oracles and PACMAN keep it from being absolute.
- **PPL → SPTM/TXM** (A15+/M2+) performed a **privilege inversion**: the most critical operations (page-table writes, code-signing decisions) now execute in **guarded levels above the kernel**, reached only via `GENTER`, so **kernel R/W is no longer game over**.
- **SPTM** is the sole page-table/frame-typing authority; **TXM** owns code signing and entitlements outside XNU; **Secure Exclaves** (iOS 17+) isolate secrets even from a fully compromised kernel — see arXiv 2510.09272.
- **MIE/EMTE** (A19/M5) attacks the bug, not the technique: always-on synchronous 4-bit memory tagging faults on heap overflows, use-after-free, and type confusion, with Tag Confidentiality Enforcement against side channels.
- macOS on Apple Silicon shares this exact lineage (arm64e PAC, SPTM/TXM, M5 MTE) — but **iOS pioneered and enforces it without an opt-out**, which is why it's the reference platform for these defenses.
- **Forensic bottom line:** this ladder, not any single missing exploit, is why modern-device (A14+) exploitation-based acquisition is dead, and why PAC- and MTE-fault crash signatures are now primary spyware-triage indicators.

## Terms introduced

| Term | Definition |
|---|---|
| KASLR | Kernel Address Space Layout Randomization — per-boot random slide of the kernelcache base to defeat hardcoded addresses |
| kernel slide | The random offset added to the kernelcache load address each boot; must be recovered to symbolize panics/exploits |
| KPP | Kernel Patch Protection ("watchtower") — software, EL3, polling kernel-integrity monitor (A8–A9); TOCTOU-bypassable |
| KTRR / CTRR | Kernel Text Read-only Region / Configurable TRR — hardware-enforced immutability of kernel text via memory-controller lock registers (A10+) |
| KIP | Kernel Integrity Protection — Apple's umbrella term for KTRR/CTRR-style kernel-code protection (A10+) |
| AMCC | Apple Memory Cache Controller / memory fabric that enforces the KTRR read-only physical range |
| PAC | Pointer Authentication — ARMv8.3 feature signing pointers with a keyed MAC in their unused high bits (arm64e, A12+) |
| arm64e | Apple's ABI/CPU subtype that enables Pointer Authentication; distinct from plain `arm64` |
| QARMA | The tweakable block cipher Arm's reference design specifies for Pointer Authentication Codes; **Apple's own cores use a proprietary implementation-defined cipher instead**, not stock QARMA |
| PAC keys (IA/IB/DA/DB/GA) | The five per-context Pointer Authentication keys: instruction, data, and generic |
| PACMAN | MIT (2022) speculative-execution attack that turns the CPU into a PAC-verification oracle to forge signatures |
| PPL | Page Protection Layer — A12–A14 mechanism (APRR/SPRR + GXF) restricting page-table writes to a guarded code domain |
| APRR / SPRR | (Access / Shadow) Permission Remapping Register — Apple silicon feature that reinterprets page permission bits by mode |
| GXF | Guarded eXecution Feature — Apple-proprietary lateral guarded levels (GL0–GL2) entered via `GENTER`, left via `GEXIT` |
| GENTER / GEXIT | Apple-proprietary instructions (opcode `0x00201420`) that atomically switch into/out of a guarded level |
| SPTM | Secure Page Table Monitor — GL2 monitor that is the sole authority over page tables and physical-frame typing (A15+/M2+) |
| frame retyping | SPTM's mechanism: every physical frame has a type (e.g. `XNU_DEFAULT`, `TXM_RW`), retypable only by its owner along allowed transitions |
| TXM | Trusted Execution Monitor — guarded monitor owning code-signing and entitlement verification, outside XNU (A15+/M2+) |
| Secure Exclaves | XNU-isolated resources/services protected even under full kernel compromise (iOS 17+; A18/M4 source) |
| Secure Kernel (SK) | The GL1 microkernel managing exclave/conclave workloads |
| xnuproxy / Tightbeam | The secure-world request handler and the typed IPC framework XNU uses to talk to exclaves |
| MIE | Memory Integrity Enforcement — Apple's A19/M5 memory-safety system combining EMTE, secure allocators, and tag confidentiality |
| MTE / EMTE | (Enhanced) Memory Tagging Extension — 4-bit per-16-byte-granule tags checked against pointer tags; **EMTE = Arm's 2022 spec, surfaced as `FEAT_MTE4`**; Apple's EMTE runs always-on synchronous |
| Tag Confidentiality Enforcement | MIE protections (hardened tag checks, PRNG re-seeding, Spectre-V1 mitigation) against side-channel leakage of tags |
| kalloc_type / xzone malloc / libpas | Apple's type-segregated secure allocators (kernel / userland / WebKit) that make memory tagging effective |
| privilege inversion | The shift from monotonic EL0<EL1 power to a model where critical operations re-validate in monitors above the kernel |

## Further reading

- Apple Platform Security — **"Operating system integrity"** (support.apple.com/guide/security/sec8b776536b) — KIP/KTRR, PAC, PPL, and the statement that SPTM+TXM **replace** PPL; per-chip gating (A10/A12/A15·M2/A19·M5).
- Apple Security Research — **"Memory Integrity Enforcement: A complete vision for memory safety in Apple devices"** (security.apple.com/blog/memory-integrity-enforcement/) — EMTE, synchronous mode, Tag Confidentiality Enforcement, allocator design.
- **Steffin & Classen, arXiv 2510.09272**, *"Modern iOS Security Features — A Deep Dive into SPTM, TXM, and Exclaves"* (2025) — the definitive public analysis of GXF/GL levels, frame retyping, `xnuproxy`/Tightbeam.
- **Sven Peter**, "Apple Silicon Hardware Secrets: SPRR and Guarded Exception Levels (GXF)" (blog.svenpeter.dev) and the **Asahi Linux** SPRR/GXF docs — the reverse-engineered hardware basis.
- **Project Zero** — Brandon Azad, *"Examining Pointer Authentication on the iPhone XS"* and the PPL writeups; the PAC threat-model canon.
- **PACMAN** — Ravichandran et al., MIT CSAIL (ISCA 2022) — speculative PAC-forgery oracle.
- **Jonathan Levin**, *MacOS and iOS Internals* Vol. III + newosxbook.com / `jtool2`; the "Make XNU Great Again" OBTS talk on the SPTM/exclave evolution.
- **Dataflow Forensics** (df-f.com) "SPTM — The Last Bits" series; **8ksec.io** "MIE Deep Dive: Kernel" — practitioner-level walkthroughs.
- `man sysctl`; **blacktop/ipsw** (github.com/blacktop/ipsw) for firmware/kernelcache dissection; `otool`/`lipo` man pages for arm64e inspection.

---
*Related lessons: [[01-cpu-gpu-npu-microarchitecture]] | [[00-the-ios-security-model]] | [[01-sep-sepos-deep-dive]] | [[04-code-signing-amfi-entitlements]] | [[05-the-sandbox-and-tcc]] | [[07-the-jailbreak-landscape-2026]] | [[01-the-acquisition-taxonomy]] | [[12-unified-logs-sysdiagnose-crash-network]]*
