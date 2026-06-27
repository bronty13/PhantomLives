---
title: "The boot chain: SecureROM → iBoot"
part: "02 — System Architecture & Internals"
lesson: 01
est_time: "45 min read + 20 min labs"
prerequisites: [xnu-on-mobile, secure-enclave-hardware]
tags: [ios, boot, securerom, iboot, secure-boot]
last_reviewed: 2026-06-26
---

# The boot chain: SecureROM → iBoot

> **In one sentence:** every iPhone and iPad boots through an unbroken cryptographic relay — an immutable mask-ROM (`SecureROM`) verifies the bootloader (`LLB`/`iBoot`), which verifies the `kernelcache`, which runs `launchd` — where each stage refuses to execute the next unless its **Image4** signature chains back to Apple's hardware-fused root key, and unlike the Apple-Silicon Mac there is **no policy you can lower** to break the chain.

## Why this matters

The boot chain is the foundation every other security control in this course stands on. Data Protection, code signing, the Secure Enclave's key release, the sandbox — all of them assume the kernel that enforces them is *the* kernel Apple signed, loaded by a bootloader Apple signed, started by a ROM Apple burned into silicon. Break any link and everything above it is theater.

For a forensic examiner this is not academic. **Where in the chain you can interpose is exactly what acquisition method is available to you.** A `SecureROM` bug (checkm8 on A8–A11, and as of June 2026 `usbliter8` on A12–A13) gives you code execution *below* the signature checks and is the only known path to a full-filesystem image of those devices without the passcode. On A14 and later there is no such hole, the chain holds, and you are confined to what a logical/AFU acquisition can reach. And the device's **boot state** — BFU vs. AFU, whether the inactivity reboot has fired — is decided the moment this chain runs, before you ever plug in a cable. You cannot reason about iOS evidence without knowing how the device got from power-on to a running OS.

## Concepts

### The chain of trust, in one diagram

The shape is identical to the Apple-Silicon Mac chain you studied in `macos-mastery` — only the *policy layer* is missing (covered below). Each box verifies the **Image4** signature of the next before transferring control:

```
 power-on
    │
    ▼
┌─────────────┐   immutable mask ROM, fused into the SoC at fab.
│  SecureROM  │   Holds the Apple Root CA public key (the hardware
│  (BootROM)  │   root of trust). Cannot be patched — ever.
└─────┬───────┘
      │  verifies Image4 sig of next stage against Apple Root CA
      ▼
┌─────────────┐   LLB (older SoCs) → iBoot, OR iBoot directly (A10+).
│ LLB / iBoot │   The bootloader. Initializes clocks/PMU/display,
│             │   runs Recovery UI, owns the USB restore stack.
└─────┬───────┘
      │  verifies Image4 sig of the kernelcache (tag "krnl")
      ▼
┌─────────────┐   XNU + statically-linked boot kexts, Image4-wrapped.
│ kernelcache │   Brings up VM, AMFI, the sandbox, AppleSEPManager.
└─────┬───────┘
      │  execs PID 1
      ▼
┌─────────────┐   First userspace process. Mounts the (sealed) system
│   launchd   │   volume, starts every daemon. Userspace begins.
└─────────────┘

   ── in parallel, on its own silicon ──
┌─────────────┐   The Secure Enclave's own immutable boot ROM, its own
│   SEPROM    │   chain of trust, loading sepOS from an Image4 "sepi"
│   → sepOS   │   payload. Independent of the AP chain above.
└─────────────┘
```

Two properties make this a *chain* and not a checklist: **transitivity** (the ROM only vouches for the bootloader; everything downstream is vouched for by the stage above, so the whole edifice rests on the one fused key) and **monotonic narrowing** (each stage can only ever load something *more* constrained — a production iBoot will not load a development kernelcache, and nothing reintroduces trust the ROM didn't grant).

> 🖥️ **macOS contrast:** the Apple-Silicon Mac runs the *same four boxes* — `Boot ROM → LLB → iBoot → kernel` — and the same Image4 format. The difference is one extra object the Mac has and iOS does not: **LocalPolicy** (see "What iOS removes" below). On the Mac, iBoot consults a per-volume, owner-signed policy that can be set to *Reduced* or *Permissive* security to boot custom kernels and third-party kexts. On iOS there is no policy object to consult and no UI to lower it. Same chain, no lever.

### Stage 0 — SecureROM: the hardware root of trust

`SecureROM` (Apple's name; the community also calls it the **BootROM**) is read-only memory **mask-programmed into the SoC die during fabrication**. It is the first code the Application Processor executes out of reset, it runs from on-die memory before external DRAM is even trained, and — the defining property — **it is physically immutable**. There is no flash to reflash, no eFuse to rewrite the code, no update mechanism. A bug in SecureROM is a bug for the silicon's entire service life; the only "fix" is a new chip revision. That immutability is exactly why a SecureROM exploit (checkm8, usbliter8) is *unpatchable* and so forensically valuable.

What SecureROM contains and does:

- The **Apple Root CA public key**, fused/baked in. This anchors all signature verification. Everything Apple-signed chains to this one key.
- Access to the SoC's fused secrets — the per-device **UID** key and the per-model **GID** key — living in the AES engine, used to decrypt personalized firmware payloads.
- A **minimal hardware bring-up**: enough to initialize the AES engine, the boot media controller, and (critically) the **USB stack** used for DFU.
- The logic to locate, decrypt, **verify the Image4 signature of**, and jump to the next stage (`LLB`/`iBoot`), or — if boot media is unavailable or a button combo requests it — to enter **DFU mode** and wait for a host to push a stage over USB.

The USB DFU stack is the soft underbelly. Both checkm8 (Synopsys DesignWare USB controller, A5–A11) and usbliter8 (a DMA underflow with the USB DART/IOMMU in bypass mode, A12–A13) are **memory-corruption bugs in SecureROM's USB code reachable only in DFU mode**. They run before any signature is checked, which is the whole point — they let you execute unsigned code at the very root of trust.

This is a recurring pattern, not a one-off. The same DFU surface has yielded a *lineage* of BootROM exploits, each unpatchable for the silicon it targets, because there is no other layer below them to fix:

| Exploit | SoC range | Mechanism (all in the DFU USB path) |
|---|---|---|
| `limera1n` (2010) | A4 | Heap overflow in the USB DFU handler. |
| `alloc8` (2017) | A5 | Use-after-free in the USB allocator. |
| **`checkm8`** (2019) | A5–A11 | UAF in the DesignWare USB stack; the modern boundary is **A8–A11**. |
| **`usbliter8`** (2026) | A12–A13 (+S4/S5) | DMA underflow with the USB **DART** in bypass mode → arbitrary SRAM overwrite. |

The throughline: every one is a memory bug in code that runs *before* the first signature check, in a stage Apple cannot reflash. Each was eventually killed only by a **new silicon revision** that hardened that specific path — A11 already neutralizes the usbliter8 bug class (its USB driver resets the DMA address per packet), and A14+ both fixes the DART configuration and has no public hole at all. For the RE deep-dive on what each gives you and where it stops, see [[07-the-jailbreak-landscape-2026]].

> 🔬 **Forensics note:** the SecureROM revision is itself an artifact. The CPID (chip ID) returned by a device in DFU/Recovery (`irecovery -q`) tells you the SoC generation, which tells you *which acquisition primitives even exist* for that device. CPID `0x8015` = A11, the last checkm8-vulnerable application processor; `0x8020`/`0x8030` = A12/A13, the usbliter8 range; `0x8101`+ (A14/A15…) have no public SecureROM exploit. Triaging a seized device starts here, before you decide on a tool.

### Image4: the signed container every stage speaks

Every verifiable object in the chain — bootloaders, kernelcache, device tree, boot logo, SEP firmware, ramdisk — is wrapped in an **Image4** (`IMG4`) container. Image4 is a **DER-encoded ASN.1** structure (the replacement for the older IMG3 format, used on every A7-and-later SoC). Understanding its three parts is understanding how verification actually happens:

| Part | Magic | Contents |
|---|---|---|
| **Payload** | `IM4P` | The actual firmware blob: a 4-character-code **tag** identifying what it is (e.g. `ibot`, `krnl`), a version string, and the payload octet-string — usually **LZFSE/LZSS-compressed** and, on production devices, **encrypted** (key wrapped to the device UID/GID, delivered via the `KBAG`). |
| **Manifest** | `IM4M` | The signed authorization. An ASN.1 structure carrying Apple's signature + cert chain to the Apple Root CA, the per-image **digests** (`DGST`), the security domain (`SDOM`), production/security flags (`CPRO`/`CSEC`), the **boot-nonce hash** (`BNCH`), and the device-binding **`ECID`**. This is the SHSH "blob." |
| **Restore Info** | `IM4R` | Boot-time-only data the ROM/SEPROM needs: the **raw boot nonce** (`BNCN`) whose hash appears as `BNCH` in the manifest, plus newer `ucon`/`ucer` properties `LLB`/`iBSS` consume. |

Verification at each stage is: parse the `IM4P`, hash its payload, look up that 4CC's expected `DGST` in the `IM4M`, confirm the hashes match, confirm the `IM4M`'s signature chains to the Apple Root CA, and confirm the manifest's `ECID`/`BNCH` bind it to *this* device and *this* boot. Only then is the payload decrypted and executed. The manifest names the image set by 4CC tag — a partial catalog you will meet constantly:

| 4CC | Image |
|---|---|
| `illb` | Low-Level Bootloader (LLB) |
| `ibot` | iBoot |
| `ibss` / `ibec` | iBSS / iBEC — the stage-2 restore bootloaders loaded over DFU |
| `krnl` / `rkrn` | kernelcache / restore kernelcache |
| `sepi` / `rsep` | SEP firmware / restore SEP firmware |
| `dtre` / `rdtr` | device tree / restore device tree |
| `rdsk` | restore ramdisk |
| `logo` | boot/recovery logo |

> 🖥️ **macOS contrast:** Image4 is *the same format* the Apple-Silicon Mac uses for `iBoot`, the kernelcache, and even the `boot.efi`-replacement objects, and the same `img4`/`pyimg4`/`ipsw` tooling parses both. The Mac's per-machine `LocalPolicy` is itself an Image4 manifest (`IM4M`) signed by the SEP on the owner's behalf. iOS uses the identical container; it just never produces an owner-signed policy manifest — only Apple-signed ones.

### Stage 1 — LLB / iBoot: the bootloader

On older SoCs the bootloader is two stages: **LLB** (Low-Level Bootloader, 4CC `illb`) does the most minimal possible job and then verifies-and-loads **iBoot** (`ibot`). On **A10 and later** (and Apple-Silicon Macs) the SecureROM loads `iBoot` essentially directly in a NOR-less flow, with the LLB role folded in. (The *exact* generation where stages collapse is a detail worth confirming against theapplewiki.com per device, but the principle is stable: the bootloader stage is one-or-two links that the ROM vouches for.)

iBoot is a substantial piece of firmware — effectively a tiny OS. Its jobs:

- **Hardware bring-up the ROM skipped**: train and initialize DRAM, the PMU, clocks, and (for an interactive boot) the display panel — which is why the Apple logo appears here.
- **Find, verify, and load the kernelcache** (`krnl`), the device tree, and boot args, then jump to the kernel. This is the security-critical handoff: iBoot will not jump to a kernelcache whose `DGST` isn't in a manifest that signs to Apple's root for this device.
- **Recovery Mode**: when entered, iBoot shows the "connect to computer" screen and exposes a USB command interface (the `irecovery` protocol) used to push a freshly-signed firmware during a restore/update.
- **Boot-nonce management**: read/generate the boot nonce and expose `com.apple.System.boot-nonce` in NVRAM (the lever behind blob-based downgrades).

So **Recovery Mode is "iBoot is running."** That is the single most useful fact for distinguishing it from DFU.

### Stage 2 — the kernelcache

The kernelcache is **XNU plus its statically-linked boot kexts**, prelinked into one Mach-O and wrapped as an Image4 `krnl` payload. iBoot verifies it, decompresses it, and jumps in. XNU then brings up virtual memory, the scheduler, the I/O Kit registry, and — load-bearing for everything in Part 03 — **AMFI** (AppleMobileFileIntegrity) and the sandbox, plus `AppleSEPManager`, which opens the mailbox to the already-running Secure Enclave. By the time the kernel is up, the *enforcement* machinery for code signing and Data Protection exists; it just hasn't met any userspace yet.

> 🔬 **Forensics note:** because the kernelcache is a single signed, immutable blob, you cannot "patch the running kernel" on a stock device — there is no on-disk kernel file to modify and no unsigned kext load path. A jailbreak's kernel read/write primitive is obtained *at runtime* by exploiting the loaded kernel, never by tampering with the boot artifact. On A12+/iOS 18–26 no such public chain exists, which is why those devices are forensically "closed" above the (non-existent) SecureROM hole.

### Stage 3 — launchd and the handoff to userspace

XNU `exec`s **`launchd` as PID 1** — the first userspace process and the ancestor of every daemon. launchd mounts the cryptographically **sealed system volume** (the iOS analogue of the Mac's Signed System Volume), reads its job plists, and brings up the userspace world: `securityd`, `keybagd`, `springboard`, the lot. Userland code-signing enforcement (AMFI verifying each binary's embedded signature) now applies to everything launchd starts. This is where Part 02's later lessons pick up — see [[04-launchd-and-system-daemons]].

### The Secure Enclave boots in parallel

The Secure Enclave is not a step in the AP chain — it is **its own computer with its own root of trust**. `SEPROM` (the SEP's immutable boot ROM) verifies and loads **sepOS** from an Image4 `sepi` payload, on its own core, with its own memory. The AP and SEP each anchor to the same Apple Root CA but run independent chains; the AP cannot forge SEP firmware and vice-versa. checkm8/usbliter8 are **AP-side** SecureROM bugs — they do *not* break SEPROM, which is why even a checkm8'd A11 still cannot brute-force a passcode faster than the SEP allows. Full treatment in [[01-sep-sepos-deep-dive]] and [[02-secure-enclave-hardware]].

### The boot nonce and anti-replay

Apple's signing is **personalized and replay-resistant**, and the boot nonce is the mechanism. A **nonce** ("number used once") randomizes each signature so a manifest signed today can't be re-used to authorize a boot tomorrow:

- iBoot/SEPROM generate a random **boot nonce** at restore time (the `APNonce` for the AP, `SEPNonce` for the SEP).
- During a restore the host's request to Apple's **TSS** (Tatsu Signing Server) includes the device **ECID** and the current nonce; Apple returns an **SHSH blob** (the `IM4M`) whose `BNCH` is the **hash** of that nonce and whose binding is to that ECID. The raw nonce travels in `IM4R` as `BNCN`.
- At boot, the loader hashes the device's current boot nonce and compares to the manifest's `BNCH`. **No match → refuse to boot.** A captured blob can't be replayed once the nonce rolls.

This is also the entire basis of **downgrade protection**: even though SHSH blobs are device-specific, you could in principle save a blob for a still-signed firmware and replay it later — *if* you could force the device to regenerate the matching nonce. Setting `com.apple.System.boot-nonce` in NVRAM (the "nonce generator") is how the jailbreak community did exactly that on older devices. Apple's countermeasure, **nonce entangling**, shipped on the **A13/T8020 generation and newer**: the boot nonce is additionally encrypted with the device **UID** key before hashing, so a host can no longer freely predict or pin the resulting `BNCH` — closing the saved-blob downgrade path on modern hardware. The deeper mechanics live in [[02-image4-personalization-shsh]].

> 🔬 **Forensics note:** the nonce/ECID binding is why you cannot take a full-filesystem image off device A and "restore" it onto device B, and why downgrading a seized A12+ device to a more-exploitable OS is generally impossible (no signing window + nonce entangling). It also means the device's *current signing state* is part of its evidentiary fingerprint — `ECID`, `ApNonce`, and board/chip IDs uniquely identify the unit.

### DFU vs. Recovery mode

Both are "the device isn't running iOS, it's waiting on a cable," and examiners conflate them constantly. The distinction is **which stage of the chain is running**, and it dictates what you can do:

| | **Recovery Mode** | **DFU Mode** |
|---|---|---|
| What's running | **iBoot** (stage-1 bootloader) | **SecureROM only** (stage 0) — iBoot/OS not loaded |
| Screen | "Connect to computer" graphic | **Black, blank** (no display init) |
| Entered by | iBoot on boot failure, or `idevicerestore`/Finder triggering it | A precise button/timing combo at power-on, before iBoot |
| Talks to | `irecovery` / restore protocol over USB | SecureROM's raw **USB DFU** endpoint |
| Loads next | A signed iBoot/iOS (push `iBEC`, then ramdisk) | A signed `iBSS`/`iBEC` stage-2 bootloader |
| Signature checks | Enforced by iBoot | Enforced by SecureROM **— unless a SecureROM bug bypasses them** |
| Restore reach | Update or restore to the **currently-signed** firmware | Same, plus the **only** entry point for low-level (checkm8/usbliter8) exploitation |

A normal **restore** flow: host puts the device in DFU (or Recovery), pushes the Apple-signed `iBSS`/`iBEC` over USB, those bring up enough hardware to accept a **restore ramdisk** (an `asr`-driven re-imager) and the new firmware, every object Image4-verified against a fresh TSS-issued manifest. **DFU is "below" Recovery** precisely because it predates iBoot — it is the lowest-level USB door into the device, which is exactly why every BootROM exploit lives there. On a stock device DFU still verifies signatures; the exploits matter because they *break that verification at its root*.

> 🖥️ **macOS contrast:** the Apple-Silicon Mac has the same two-tier idea — **Recovery** (recoveryOS, the rough peer of iBoot's recovery) and a **DFU/revive** mode reached by a fixed key-hold at power-on, restored with **Apple Configurator** ("Revive" keeps data, "Restore" erases). On the Mac, DFU/Configurator is also where you'd *raise* security back to Full after experimenting. On iOS there is nothing to raise or lower — DFU restore only ever lands you on a current-signed, Full-Security OS.

### The restore flow, end to end

A "restore" is the chain run *backwards from a host*: instead of booting the firmware on NAND, the host streams a fresh, signed, personalized firmware over USB and writes it. Tracing the actual sequence makes both the trust model and the exploit surface concrete:

```
HOST (idevicerestore)                         DEVICE
 │ 1. put device in DFU (or Recovery)   ───▶  SecureROM USB DFU endpoint
 │ 2. fetch ECID + current ApNonce      ◀───  (from irecovery -q)
 │ 3. request signing: ECID + nonce     ───▶  Apple TSS  ──┐
 │    ◀── personalized IM4M (SHSH) ─────────────────────────┘
 │ 4. upload iBSS (Image4-verified)     ───▶  SecureROM verifies sig → runs iBSS
 │ 5. upload iBEC                        ───▶  iBSS verifies sig → runs iBEC
 │ 6. iBEC trains DRAM, opens restore USB
 │ 7. upload device tree + RESTORE       ───▶  iBEC verifies each → boots
 │    kernelcache + restore ramdisk            the throwaway "restore OS"
 │ 8. restore ramdisk runs `asr`         ◀──▶  re-images NAND: writes LLB,
 │    + restored daemon, streams the           iBoot, kernelcache, SEP fw,
 │    new OS image                              filesystem — all Image4-bound
 │ 9. set boot partition, reboot         ───▶  normal chain runs the new OS
```

Every numbered upload is an Image4 object the receiving stage verifies before executing — `iBSS` is checked by SecureROM, `iBEC` by `iBSS`, the restore kernelcache by `iBEC`. The **restore ramdisk** boots a minimal, RAM-only "restore OS" (this is why the BuildManifest carries a separate `RestoreKernelCache`/`RestoreSEP`: the re-imager must run without depending on the possibly-broken OS it is about to overwrite), and the `restored`/`asr` pair does the actual NAND re-image.

This is also exactly the rail a **checkm8/usbliter8 acquisition** rides. The exploit fires at step 1 (in DFU, pre-verification), so at step 4 the host can upload a **patched `iBSS`** with the signature check NOP'd; from there it boots a *custom* ramdisk instead of Apple's restore OS — one that mounts the user filesystem and streams it back to the host **instead of overwriting it**. Same plumbing as a restore, inverted into a read. That is "full-filesystem acquisition via BootROM exploit" in one sentence, and it is why DFU — not Recovery — is the forensically interesting door.

> ⚖️ **Authorization:** the restore rail is **destructive by default** — steps 8–9 erase NAND. The *only* non-destructive use of this path is a validated BootROM-exploit acquisition that boots a read-only ramdisk and never reaches the re-image step. Pointing `idevicerestore` at a case device, or fumbling a DFU procedure into a normal restore, **wipes the evidence**. Treat any DFU/restore action on seized hardware as a documented, authorized, tool-validated step — never an improvisation.

### What iOS removes: there is no policy to lower

This is the crux of the macOS→iOS reset for this subsystem. On the Apple-Silicon Mac, the owner is a trusted party in the boot chain. iBoot reads a **LocalPolicy** — a per-volume Image4 manifest, signed by the **SEP** using the owner's authenticated credential, stored in the volume's Preboot/`owner` space — that records the chosen **security level**:

- **Full Security** — only the latest signed OS, like iOS.
- **Reduced Security** — boot older signed OSes, run user-built kernels, load third-party kexts; set in **1 True Recovery (1TR)**, the recoveryOS reached by holding the power button from a full shutdown.
- **Permissive Security** — Reduced *plus* the developer hooks (`csrutil`/`bputil`) needed to run fully custom kernels.

iOS has **none of this**. There is no LocalPolicy object, no `bputil`, no 1TR, no setting, hidden or otherwise, that an owner (or examiner) can flip to make iBoot accept a non-current or non-Apple kernel. The chain is fixed at the equivalent of Full Security for the device's whole life. **That is the single biggest structural difference from the Mac boot chain you learned, and it is why iOS acquisition is so much harder:** on a Mac you can (with the owner's credential) lawfully drop to Reduced Security and boot your own tooling; on iOS the only sub-signature interposition that exists is a SecureROM *bug*.

> 🔬 **Forensics note — boot state is decided here.** The first time the chain runs after power-loss, the device comes up **Before First Unlock (BFU)**: the Data Protection class keys that protect most user data are still sealed in the SEP, and the file system is largely opaque. The first correct passcode transitions to **After First Unlock (AFU)**, releasing those keys into memory, where they stay until reboot. iOS's **inactivity reboot** (introduced iOS 18.0 at 7 days, **shortened to 72 hours in iOS 18.1** and retained through iOS 26) deliberately re-runs this chain: the SEP tracks last-unlock, the `AppleSEPKeyStore` kext flips an `aks-inactivity` flag that `keybagd` reads, and SpringBoard triggers a clean reboot (an attempt to *cancel* it forces a kernel panic, which reboots anyway). The effect: a seized phone left unattended for three days **falls from AFU back to BFU on its own**, evaporating your acquisition window. Know whether the chain has re-run since seizure — it changes what is decryptable. See [[03-passcode-bfu-afu-and-inactivity]].

### Boot state is the first triage decision

Everything above converges on one operational question an examiner answers *before choosing a tool*: given this exact device, in this exact state, what is even reachable? The boot chain decides the answer, and it reduces to two axes — **what SoC** (does a sub-signature interposition exist at all?) and **what lock state** (are the keys in memory?):

```
                         ┌─ A8–A11 ──▶ checkm8 path: BootROM exploit →
                         │             custom ramdisk → full filesystem,
   what SoC?  ───────────┤             passcode often still required for
   (irecovery -q CPID)   │             keybag, but FS is reachable.
                         │
                         ├─ A12–A13 ─▶ usbliter8 path (2026, maturing):
                         │             same shape; verify tooling/OS support.
                         │
                         └─ A14+ ────▶ NO sub-signature hole. Confined to
                                       what lock state + commercial tools allow.

   what lock state? ─────┬─ AFU ─────▶ class keys in RAM: logical / agent /
   (since last reboot)   │             commercial AFU extraction reach most data.
                         │
                         └─ BFU ─────▶ keys sealed in SEP: only BFU-class data;
                                       inactivity reboot may have forced this.
```

The two axes are independent and multiplicative. An A11 in AFU is the easy case (BootROM hole *and* keys live). An A16 in BFU is the hard wall (no hole, keys sealed). The most time-sensitive scenario is an **A12–A13/A14+ device currently in AFU**: there may be no BootROM exploit, so your only leverage is the live keys — and the **72-hour inactivity reboot is a clock running against you**. This is why seizure procedure (keep it powered, keep it from locking out, isolate radios) is downstream of understanding the boot chain, not a separate topic. The full decision matrix lives in [[01-the-acquisition-taxonomy]] and [[02-bfu-vs-afu-and-data-protection-classes]]; the point here is that **the chain you just traced is what populates that matrix.**

## Hands-on

Everything here runs **on the Mac** — there is no on-device shell. You are inspecting firmware artifacts and (in walkthroughs) narrating what a host tool does to a device over USB. Install the toolkit:

```bash
brew install libimobiledevice          # ideviceinfo, idevicerestore, irecovery
pipx install pyimg4                     # precise Image4 parser (m1stadev)
brew install blacktop/tap/ipsw         # IPSW/Image4 swiss-army knife
# img4tool (tihmstar) and gaster/ipwndfu are built from source when needed
```

### Identify a device's chip generation (Recovery/DFU, read-only)

```bash
# A device sitting in Recovery or DFU answers irecovery without booting iOS.
irecovery -q
# => CPID: 0x8015        (the SoC / chip ID — here, A11)
#    CPRV: 0x01
#    CPFM: 0x03
#    ECID: 0x000ABC...   (the per-unit ID baked into silicon)
#    IBFL: 0x3C
#    SRTG: iBoot-XXXX.X.X.X.X   (DFU shows a SecureROM tag instead)
#    MODE: Recovery       (vs. "DFU")
```

`CPID` answers "is this checkm8/usbliter8 territory?"; `ECID` is the device's signing fingerprint; `MODE` tells you which door you're at. (No device on this workstation — read this as the shape of the output you must be able to interpret.)

### Download and crack open a real firmware image (no device needed)

```bash
# Pull a signed IPSW (it is just a zip of Image4 objects + a BuildManifest).
ipsw download ipsw --device iPhone16,1 --version 26.5      # or --latest
unzip -l iPhone16,1_26.5_*.ipsw | grep -Ei 'kernelcache|iBoot|sep|BuildManifest'

# Inspect the kernelcache's Image4 payload header.
pyimg4 im4p info -i kernelcache.release.iphone16
# => Tag: krnl   Compression: LZFSE   (encrypted payloads also show a KBAG)

# Extract + decompress the raw kernel Mach-O (for shipping IPSWs the
# kernelcache is unencrypted; iBoot/SEP payloads carry a KBAG and are not).
pyimg4 im4p extract -i kernelcache.release.iphone16 -o kernel.raw
file kernel.raw
# => kernel.raw: Mach-O 64-bit executable arm64e
```

> Exact `ipsw img4 …` subcommand names drift between blacktop/ipsw releases; `pyimg4` and `img4tool` are the stable, mechanism-level interfaces. Lead with what the bytes *are* (DER ASN.1 `IM4P`/`IM4M`/`IM4R`), not a memorized flag.

### Read the manifest of a saved SHSH blob

```bash
# An SHSH blob IS an IM4M. Inspect the device binding + per-image digests.
pyimg4 im4m info -i shsh/0x000ABC_iPhone16,1_26.5.shsh2
# => ECID: 0x000ABC...        ApNonce/BNCH: <hash>
#    ChipID / BoardID, CertEpoch (CEPO), SecurityDomain (SDOM)
#    Manifest body: ibot, krnl, sepi, dtre, ... each with its DGST
```

### See the raw DER — the structure under the convenience tools

`pyimg4`/`img4tool` are pretty-printers over a plain DER ASN.1 object. Looking at the bytes themselves demystifies it and is the skill you'll need when a tool *doesn't* parse a malformed or attacker-supplied manifest:

```bash
# An IM4M (or whole IMG4) is DER — openssl walks it with no Apple-specific code.
openssl asn1parse -inform DER -in shsh/0x000ABC_iPhone16,1_26.5.shsh2 | head -40
# => SEQUENCE
#      IA5STRING  :IM4M            <- the magic
#      INTEGER    :00              <- version
#      SET { SEQUENCE { ... } }    <- the MANB ("manifest body") dict
#        ... per-property SEQUENCEs keyed by 4CC: BORD, CHIP, ECID, CPRO,
#            CSEC, CEPO, SDOM, and BNCH (the boot-nonce hash) ...
#        ... per-image SEQUENCEs keyed by 4CC: ibot, krnl, sepi ... each
#            carrying DGST (the SHA digest), EPRO, ESEC ...
#      OCTET STRING               <- Apple's RSA/ECDSA signature over MANB
#      SEQUENCE                   <- the X.509 cert chain to the Apple Root CA
```

The `4CC`-keyed properties (`BORD`, `CHIP`, `ECID`) are the device binding; the per-image `DGST` values are what each boot stage compares its loaded payload against; the trailing `OCTET STRING` + cert `SEQUENCE` are what chains it all to the fused root key. That is the entire verification model, visible in one `asn1parse`.

### Walk the BuildManifest (the restore recipe)

```bash
# Which Image4 objects make up a restore, and their tags/paths.
ipsw info iPhone16,1_26.5_*.ipsw
# or, raw:
unzip -p iPhone16,1_26.5_*.ipsw BuildManifest.plist | plutil -p - | less
# Look for BuildIdentities[].Manifest{ LLB, iBEC, iBSS, KernelCache,
#   RestoreSEP, RestoreRamDisk, ... } — each an Image4 with an Info{Path}.
```

> ⚠️ **ADVANCED — device-side, not run here.** `idevicerestore -l` will fetch the latest signed IPSW **and re-image a connected device, erasing it**. Never aim it at evidence. checkm8/usbliter8 tooling (`gaster pwn`, `ipwndfu -p`) requires a device in DFU; both are read in this lesson as walkthroughs, not commands to run against a case device.

## 🧪 Labs

> Every lab below uses a **public IPSW / SHSH artifact on the Mac** or a **read-only walkthrough**. None require a device, and none can run on the **iOS Simulator**: the Simulator is a userspace running on macOS frameworks — it has **no SecureROM, no iBoot, no kernelcache, no SEP, no Image4 verification at all**. The boot chain is exactly the layer the Simulator omits, so it is studied here from *firmware artifacts*, not a simulated boot.

### Lab 1 — Dissect an Image4 payload (substrate: public IPSW on the Mac)

1. `ipsw download ipsw --device <model> --version 26.5` (any model you like; pick one whose IPSW is small).
2. Unzip and locate `kernelcache.*` and an `iBoot`/`iBEC` object.
3. `pyimg4 im4p info -i kernelcache.*` and note the **tag** (`krnl`) and **compression** (`LZFSE`).
4. `pyimg4 im4p info -i iBEC.*` and note that it instead reports a **KBAG** — its payload is **encrypted** (key wrapped to the device UID), which is why you can disassemble the kernel from a shipping IPSW but not iBoot. Articulate *why* Apple encrypts the bootloader but not the kernelcache.
   *Fidelity caveat:* a public IPSW is the generic, un-personalized firmware — it has the `IM4P` payloads but no device-bound `IM4M`. You are seeing structure, not a completed authorization.

### Lab 2 — Map the restore recipe (substrate: public IPSW BuildManifest)

1. `unzip -p <ipsw> BuildManifest.plist | plutil -p - > manifest.txt`.
2. In one `BuildIdentity`, list every key under `Manifest{}` and match each to a 4CC from the table above (`LLB`→`illb`, `iBEC`→`ibec`, `KernelCache`→`krnl`, `RestoreSEP`→`rsep`, …).
3. Order them by where they run in the chain. Which objects are loaded **over USB in DFU** during a restore (the `iBSS`/`iBEC` stage-2 pair) versus written to NAND for normal boots (`LLB`/`iBoot`/`kernelcache`)?
4. Note that **two** kernelcaches and **two** SEP firmwares exist (`KernelCache`+`RestoreKernelCache`, `SEP`+`RestoreSEP`). Explain why a restore needs a throwaway "restore" OS distinct from the one it installs.

### Lab 3 — checkm8 / usbliter8, narrated (read-only walkthrough)

> ⚠️ **ADVANCED / DESTRUCTIVE on real hardware.** This is the workflow, not a command set to run on a case device. Entering DFU and running BootROM exploit tooling is a documented, reproducible step on a *test* device under authority; against evidence it is done only by trained examiners with a validated tool, fully logged.

Trace the path on paper, stage by stage, and name where the trust is broken:

1. **DFU entry.** Power+button combo at boot → SecureROM's USB DFU endpoint, **before iBoot**. (`irecovery -q` would show `MODE: DFU`.)
2. **Exploit.** `gaster pwn` (checkm8, A8–A11) or the `usbliter8` PoC (A12–A13) sends a crafted USB transfer that corrupts SecureROM memory — checkm8 via the DesignWare controller, usbliter8 via a DMA underflow with the USB DART in **bypass mode** overwriting SRAM — yielding **code execution before any signature check**.
3. **Patched stage-2.** The host now uploads an `iBSS`/`iBEC` with the signature checks neutralized, then a custom ramdisk.
4. **Outcome.** Tethered, unsigned-code-capable boot → on supported OS versions, a full-filesystem image of an otherwise-closed device.

Now state precisely *why this is impossible on an iPhone 17 (A19)*: there is **no SecureROM bug** (A14+ configures DART correctly; usbliter8's authors confirm newer silicon is unexploitable), and **no LocalPolicy** to lower as a fallback. Contrast with how, on the Apple-Silicon Mac, the *owner* can lawfully drop to **Reduced Security** in 1TR and boot custom code — a lever iOS simply does not expose. Pair this walkthrough with Lab 1's artifact work so the downstream skill (reading the firmware you'd image) is exercised device-free.

### Lab 4 — Boot-nonce and replay reasoning (substrate: a saved SHSH blob, or paper)

1. If you have any saved `.shsh2` blob, `pyimg4 im4m info` it and find the **`BNCH`** (boot-nonce hash) and **`ECID`**.
2. Write the boot-time check in pseudocode: *device generates boot nonce → hash it → compare to manifest `BNCH` → boot iff equal AND signature chains to Apple Root CA AND `ECID` matches.*
3. Explain, using that check, why a blob saved for device A cannot boot device B, and why **nonce entangling** (A13+) — encrypting the nonce under the per-device UID before hashing — defeats the old "set the nonce generator in NVRAM, replay an old signed blob" downgrade trick.
4. Connect to forensics: why downgrading a seized A12+ device to a checkm8-able OS is generally a dead end (no signing window + entangled nonce), and why the device's `ECID`/`ApNonce` belong in your case notes.

### Lab 5 — Diff the manifest across two OS versions (substrate: two public IPSWs)

1. Download two IPSWs for the **same device model** at different OS versions (e.g. 26.4 and 26.5), and `unzip -p <ipsw> BuildManifest.plist | plutil -p -` each.
2. Compare the `ApBoardID`/`ApChipID` (constant — the silicon doesn't change) against the per-image **build identifiers and digests** (which change every build). Confirm that the device-binding properties are stable while the per-image `DGST`s rotate.
3. Note which image set is identical between the two (rare) and which always differs. Reason about why a manifest is therefore **only valid for one specific build on one specific device** — the intersection of stable device identity and per-build digests.
4. Tie it back: this is *why* an examiner cannot mix-and-match a signed component from an old, exploitable build into a current restore — the manifest that authorizes the old component won't authorize the rest of the current OS, and you cannot get a fresh signature for the old build once its window closes.
   *Fidelity caveat:* you are reasoning over the public, generic manifests; a real restore uses a TSS-personalized `IM4M` for the specific `ECID`, which you can only obtain live from a device + Apple's signing server within the signing window.

## Pitfalls & gotchas

- **DFU is not Recovery.** A blank black screen that answers `irecovery -q` with `MODE: DFU` is SecureROM; the "connect to iTunes/computer" graphic is iBoot (Recovery). Reporting the wrong one misstates how deep an examiner reached and what was even possible.
- **"Unpatchable BootROM exploit" ≠ "jailbroken modern iPhone."** checkm8/usbliter8 are *SecureROM code execution* on **A8–A11 / A12–A13** respectively. They say nothing about A14+ devices and do **not** themselves defeat the SEP, Data Protection, or the passcode. A SecureROM exec primitive is a *starting* point that still needs a kernel chain to become a usable jailbreak, and on iOS 18/26 there is **no public jailbreak for A12+**.
- **usbliter8 is brand-new (public June 18, 2026) and still maturing.** Treat its exact device/OS coverage, tool stability, and downstream tooling as **volatile — verify against the PoC repo and theapplewiki.com at author time** before relying on it operationally. The durable fact (a SecureROM DMA/DART bug exists for A12–A13, none for A14+) is what to internalize; the catalog details will move.
- **A public IPSW has no `IM4M` for your device.** It ships generic `IM4P` payloads; the device-binding manifest is issued per-restore by TSS. Don't expect to find a personalized blob inside a downloaded IPSW.
- **Encrypted vs. plaintext payloads.** Shipping kernelcaches are typically un-encrypted (you can disassemble them straight from the IPSW); `iBoot`/`iBSS`/`iBEC`/SEP payloads carry a `KBAG` and are encrypted to the device — historically the community published decryption keys for *older* SoCs, but on modern silicon those bootloaders stay opaque without the device.
- **The inactivity reboot silently re-runs the chain.** A device that was AFU at seizure can be BFU 72 hours later with no one touching it. If your timeline assumes continuous AFU, you may chase keys that are already re-sealed. Record seizure time, power state, and whether the device has rebooted since.
- **Don't reach for Mac muscle memory.** There is no `bputil`, no `csrutil`, no 1TR, no Reduced Security on iOS. Any plan that assumes an owner-settable security downgrade is importing a macOS-ism that does not exist here.
- **Stage boundaries shift by SoC.** Whether LLB is a distinct stage or folded into iBoot, and the precise CPID→exploit mapping, are **per-generation details to confirm** (theapplewiki.com is the live reference), not constants to memorize.

## Key takeaways

- iOS boots an **unbroken Image4-verified relay**: `SecureROM → LLB/iBoot → kernelcache → launchd`, each link refusing to run the next unless its signature chains to the **Apple Root CA** fused into the ROM.
- **SecureROM is immutable mask-ROM** — the hardware root of trust and the only stage Apple can never patch, which is exactly why a SecureROM bug is unpatchable and forensically decisive.
- **checkm8 (A8–A11)** and the new **usbliter8 (A12–A13, public 2026-06-18)** are memory-corruption bugs in SecureROM's **USB/DFU** code that run *before* signature checks; **A14+ has no public SecureROM hole**, closing low-level acquisition on modern devices.
- **Image4 = `IM4P` (payload) + `IM4M` (signed manifest/SHSH) + `IM4R` (restore info/boot nonce)**, DER-encoded ASN.1; verification is hash-the-payload, match the manifest `DGST`, check the chain-to-root and the `ECID`/`BNCH` device+boot binding.
- **Recovery = iBoot is running; DFU = SecureROM only.** DFU is the lower, pre-iBoot USB door and the home of every BootROM exploit.
- The **boot nonce + ECID** make signing personalized and replay-resistant; **nonce entangling (A13+)** kills the old saved-blob downgrade, which is why you generally can't downgrade a seized modern device into an exploitable OS.
- The defining macOS contrast: iOS has **no LocalPolicy** — no owner-settable Reduced/Permissive security, no 1TR, no lever. The chain is fixed; the only sub-signature interposition is a *bug*.
- **Boot state (BFU/AFU) is set by this chain**, and the **inactivity reboot** (72 h since iOS 18.1) re-runs it on its own — silently dropping a seized AFU device back to BFU.

## Terms introduced

| Term | Definition |
|---|---|
| SecureROM (BootROM) | Immutable mask-ROM fused into the SoC; the hardware root of trust holding the Apple Root CA public key and the first code the AP runs. |
| LLB | Low-Level Bootloader (Image4 tag `illb`); the minimal first bootloader stage on older SoCs, folded into iBoot's load on A10+. |
| iBoot | The main bootloader (tag `ibot`); inits hardware, runs Recovery Mode, verifies and loads the kernelcache. |
| kernelcache | XNU + statically-linked boot kexts, prelinked and Image4-wrapped (tag `krnl`); verified and run by iBoot. |
| Image4 (IMG4) | DER-encoded ASN.1 container for every verifiable firmware object; parts `IM4P`/`IM4M`/`IM4R`. |
| IM4P | Image4 Payload: a 4CC tag + version + the (usually compressed/encrypted) firmware blob. |
| IM4M | Image4 Manifest: Apple-signed authorization with per-image digests (`DGST`), `ECID`, `BNCH`, security domain — the SHSH "blob." |
| IM4R | Image4 Restore Info: boot-time data including the raw boot nonce (`BNCN`). |
| SHSH blob | A device-personalized `IM4M` issued by Apple's TSS for a specific ECID + nonce; authorizes one firmware on one device. |
| ECID | The unique, immutable per-device chip identifier used to bind firmware personalization. |
| Boot nonce / APNonce | A per-restore random number; its hash (`BNCH`) in the manifest makes signatures replay-resistant. |
| Nonce entangling | A13/T8020+ countermeasure encrypting the boot nonce under the device UID key, defeating saved-blob downgrades. |
| DFU mode | Device Firmware Update: SecureROM-only USB state below iBoot; the entry point for BootROM exploits. |
| Recovery Mode | iBoot running its restore UI/USB interface; "above" DFU, used for normal restores/updates. |
| checkm8 | Unpatchable SecureROM USB/DFU exploit (CVE-2019-8900) covering A5–A11 (the modern boundary being A8–A11). |
| usbliter8 | 2026 SecureROM DMA/DART exploit for A12–A13 (and S4/S5); public 2026-06-18; A14+ unaffected. |
| SEPROM | The Secure Enclave's own immutable boot ROM; loads sepOS (`sepi`) on an independent chain of trust. |
| LocalPolicy | The Apple-Silicon **Mac**'s owner-signed boot security policy (Full/Reduced/Permissive); **has no iOS equivalent**. |
| BFU / AFU | Before/After First Unlock — the boot-state distinction governing which Data Protection keys are available. |
| Inactivity reboot | iOS feature (7 d in 18.0, **72 h since 18.1**) that auto-reboots an idle locked device, dropping it from AFU to BFU. |

## Further reading

- Apple — *Boot process for iPad and iPhone devices* and *Secure Enclave*, Apple Platform Security guide (support.apple.com/guide/security).
- The Apple Wiki — *IMG4 File Format*, *DFU Mode*, *Nonce*, *checkm8 Exploit* (theapplewiki.com) — the live reference for per-device CPIDs, 4CC tags, and exploit/version state.
- Jonathan Levin — *MacOS and iOS Internals* Vol. III (security/boot), newosxbook.com; `iBoot.pdf` bonus chapter.
- amarioguy — "An analysis of iBoot's Image4 parser" (amarioguy.github.io, 2025) — how the validators actually differ per stage.
- Paradigm Shift — `usbliter8` write-up + PoC (github.com/prdgmshift/usbliter8); coverage at The Hacker News / The Register (2026-06).
- Alfie CG — "A comprehensive write-up of the checkm8 BootROM exploit" (alfiecg.uk, 2023).
- Tooling: `pyimg4` (m1stadev), `img4tool` (tihmstar), `blacktop/ipsw`, `libimobiledevice` (`irecovery`, `idevicerestore`), `gaster`/`ipwndfu`.
- Magnet Forensics / Hexordia — "iOS 18 inactivity reboot" analyses (boot-state forensic impact).
- `man irecovery`, `man idevicerestore`.

---
*Related lessons: [[02-secure-enclave-hardware]] | [[02-image4-personalization-shsh]] | [[00-xnu-on-mobile]] | [[03-passcode-bfu-afu-and-inactivity]] | [[07-the-jailbreak-landscape-2026]] | [[04-launchd-and-system-daemons]]*
