---
title: "Image4, personalization & SHSH"
part: "02 — System Architecture & Internals"
lesson: 02
est_time: "45 min read + 20 min labs"
prerequisites: [boot-chain-securerom-iboot]
tags: [ios, img4, image4, shsh, personalization, firmware]
last_reviewed: 2026-06-26
---

# Image4, personalization & SHSH

> **In one sentence:** Every signed firmware component on a modern Apple device is an **Image4 (IMG4)** container whose payload (IM4P) is gated by a manifest (IM4M) of approved hashes that Apple's **Tatsu Signing Server** signs *on demand, per restore*, cryptographically welding the install to one chip's **ECID** and one boot's **nonce** — which is exactly why you cannot downgrade once Apple stops signing, and why a saved **SHSH** blob is both a downgrade key and a device fingerprint.

## Why this matters

The previous lesson ([[boot-chain-securerom-iboot]]) showed the boot chain as a sequence of stages, each verifying the next. This lesson is the *format and protocol* underneath that chain — the on-disk container Apple uses for everything from SecureROM's first load through the kernelcache and SEP firmware, and the online ceremony that decides whether a given OS is even installable on a given device *right now*.

For a forensic examiner this is not trivia. The personalization gate is the single mechanism that decides whether you can roll a seized A12+ device back to an older, exploitable iOS to make acquisition easier (you almost always can't), whether a "saved blob" found on a suspect's laptop ties hardware to a person (it carries the device ECID), and how to fingerprint an unknown firmware component recovered from disk or memory. For a builder/RE, IMG4 is the wrapper you'll meet the instant you open an IPSW, unpack a kernelcache, or try to understand why your hacked-up boot image won't load. Master the container and the signing ceremony once; the boot chain, jailbreak landscape, and acquisition taxonomy all reference it.

There's a deeper reason to learn this precisely rather than by analogy: almost every "can I do X to this iPhone?" question in forensics and RE ultimately reduces to **"is there a validly-signed Image4 manifest for the state I want, on this exact chip, right now?"** Downgrade, custom-boot, jailbreak-via-restore, even loading a patched ramdisk for acquisition — all of them die or live on that one question. Knowing the format and the signing model lets you answer it from first principles instead of cargo-culting forum threads.

## Concepts

### The container: DER-encoded ASN.1

Apple replaced the old IMG3 format with **Image4** on the first 64-bit SoC (A7, 2013). Every Image4 object is a **DER-encoded ASN.1** structure — the same encoding X.509 certificates use — which is why you can walk one with `openssl asn1parse` or `der2ascii` and why the parser in SecureROM/iBoot is a hardened ASN.1 reader (a juicy attack surface; see the further-reading link on iBoot's Image4 validator).

There are three top-level object types, each tagged with a four-byte magic that is literally the ASN.1 first element (an `IA5String`):

| Object | Magic | Role |
|---|---|---|
| **IM4P** | `IM4P` | *Payload* — one firmware component (kernelcache, iBoot, SEP, logo, ramdisk…), optionally encrypted |
| **IM4M** | `IM4M` | *Manifest* — the signed list of approved component hashes + device binding. **This is the "APTicket" / SHSH.** |
| **IM4R** | `IM4R` | *Restore info* — small dictionary carrying the **boot nonce** for the restore |

A fully assembled, bootable `.img4` file is a `SEQUENCE` that bundles an IM4P **and** its IM4M (and sometimes an IM4R). On disk inside an IPSW, the components ship as bare `.im4p` files and the manifest is fetched live (more below). The conceptual shape:

```
IMG4  (SEQUENCE)
├── "IMG4"                      (IA5String magic)
├── IM4P  ── payload            (the component bytes, maybe encrypted)
├── IM4M  ── manifest           (Apple's signature over approved hashes)
└── IM4R  ── restore info        (optional; boot nonce)
```

> 🖥️ **macOS contrast:** You already met this on Apple Silicon Macs in the boot-process lesson. The Mac uses the **identical IMG4 container and the same TSS personalization concept** — `boot.efi`/iBoot, the kernel collection, and the per-Mac **LocalPolicy** are all IMG4 objects, and the LocalPolicy is sent to Apple as a ~3 KB IMG4 component during restore. The difference is *policy*, not *format*: a Mac exposes **Reduced Security** (the `smb0` flag in LocalPolicy, flipped with `bputil`/Startup Security Utility) that lets the next stage accept a **globally** signed manifest instead of a device-personalized one. iOS has no such escape hatch — it is full security, always. Same lock, the iPhone just threw away the key.

### IM4P — the payload

An IM4P wraps exactly one firmware component. Its ASN.1 sequence carries, in order:

1. The `IM4P` magic.
2. A **four-character type tag** identifying the component (`krnl` = kernelcache, `ibot` = iBoot, `illb` = LLB, `ibss`/`ibec` = restore bootloaders, `sepi` = SEP firmware, `logo`, `dtre` = device tree, `rdsk` = restore ramdisk, and dozens more — the full catalog lives on The Apple Wiki).
3. A human-readable description string (e.g. `"KernelCache"`).
4. The **payload octet string** — the actual bytes, usually **compressed** (`lzss` for legacy kernelcaches, `lzfse`/`lzfse_iboot` for newer components, or `none`).
5. An optional **KBAG** octet string, present only when the payload is **encrypted**.
6. Optional trailing compression/extra-data metadata.

**KBAG (Keybag).** When a component is encrypted, the IM4P carries a KBAG holding (typically) two keybag entries — one for **production**, one for **development** — each an `{ type, IV (16 bytes), wrapped-key (32 bytes, AES-256) }` tuple. The IV and key are themselves **wrapped by the SoC's GID key**, a per-SoC-model AES key fused into the silicon and usable only by the hardware AES engine, never readable by software. To decrypt a component you must run the wrapped IV+key through the AES engine on a device of that SoC — which historically meant a **checkm8**-class SecureROM exploit (A8–A11) to drive the engine outside of a signed boot. That's why community key databases (and `ipsw`'s `--lookup`) only have decryption keys for checkm8-era devices (plus a handful of older, separately-exploited A-series): on A12+ there is no public way to exercise the GID key.

Note that Apple stopped encrypting many components years ago — the **kernelcache has been plaintext since iOS 10**, so you can unpack it from any IPSW with no key at all. SEP firmware and some bootloaders still carry a KBAG.

Walked with a generic ASN.1 reader, a kernelcache IM4P looks like this — note the `IM4P` magic, the `krnl` type, the description string, and the giant payload `OCTET STRING`:

```
$ openssl asn1parse -inform DER -in kernelcache.release.iphone16 | head
    0:d=0  hl=4 l=...   cons: SEQUENCE
    7:d=1  hl=2 l=  4   prim:  IA5STRING        :IM4P
   13:d=1  hl=2 l=  4   prim:  IA5STRING        :krnl
   19:d=1  hl=2 l= 11   prim:  IA5STRING        :KernelCache
   32:d=1  hl=4 l=...   prim:  OCTET STRING      [HEX DUMP]:62767832...   ← lzfse payload
  ...:d=1  hl=4 l=...   cons:  SEQUENCE          ← optional compression/extra-data info
```

If the component were encrypted you'd also see a trailing `OCTET STRING` holding the KBAG — a nested `SEQUENCE` of `{ type, IV, key }` tuples. The same five-element shape holds for every component type; only the 4CC type tag and whether a KBAG is present change.

The components you'll meet most often (the full set is large; this is the high-value subset):

| 4CC | Component | Stage |
|---|---|---|
| `illb` | LLB (Low-Level Bootloader) | first iBoot stage from flash |
| `ibot` | iBoot | second-stage boot loader |
| `ibss` / `ibec` | iBSS / iBEC | restore-mode boot loaders (DFU path) |
| `krnl` | KernelCache | the XNU kernel collection |
| `rkrn` | RestoreKernelCache | kernel used during restore |
| `sepi` / `rsep` | SEP firmware / Restore SEP | Secure Enclave OS image |
| `rdsk` | RestoreRamDisk | the restore environment's root |
| `dtre` / `rdtr` | DeviceTree / Restore DeviceTree | hardware description blob |
| `logo` | AppleLogo | boot logo image |
| `rtsc`/`ltrs` | Restore / loadable trust cache | hashes of ad-hoc-signed binaries allowed to run (during restore / loaded at runtime) |

> 🔬 **Forensics note:** An IM4P found on disk or carved from memory is self-identifying. The 4CC **type tag** (`krnl`, `sepi`, …) plus the description string tells you *what* it is; cross-referencing the payload hash against the `BuildManifest.plist` of candidate IPSWs (`ipsw` can do this) tells you the **exact OS build and device model** it came from. A stray `kernelcache` IM4P in a backup or a suspect's download folder is a firmware-version fingerprint, not random binary noise.

### IM4M — the manifest (the APTicket / SHSH)

The IM4M is the heart of the system: **Apple's signature over the set of component hashes a device is allowed to boot, bound to that specific device.** Long-time jailbreakers call it the **APTicket**; the saved-to-disk form is the **SHSH blob** (`.shsh`/`.shsh2`). Same object, three names.

Structurally an IM4M is a `SEQUENCE` of:

1. The `IM4M` magic + a version integer.
2. **MANB** — the *manifest body*, a `SET` containing:
   - **MANP** — *manifest properties*: the device-binding values (table below).
   - One sub-dictionary **per approved component**, each keyed by the component 4CC and containing a **`DGST`** (the SHA-384 digest of that component's IM4P payload) plus per-component flags.
3. An **RSA/ECDSA signature** over MANB.
4. The **X.509 certificate chain** rooting up to **Apple's Secure Boot CA** — this is what SecureROM/iBoot pins.

The MANP device-binding properties (four-character tags) are the crux of personalization:

| Tag | Meaning | Binds to |
|---|---|---|
| `ECID` | Exclusive Chip ID — the per-die serial | **one physical device** |
| `BNCH` | Boot nonce (the expected `ApNonce`) | **one restore session** |
| `snon` | SEP nonce | one SEP restore session |
| `CHIP` | ApChipID — SoC model (e.g. `0x8130`) | a chip family |
| `BORD` | ApBoardID — board revision | a board |
| `SDOM` | ApSecurityDomain | security domain |
| `CPRO` | ApProductionMode (production vs. dev fused) | prod/dev silicon |
| `CSEC` | ApSecurityMode | security mode |
| `CEPO` | Certificate Epoch — the minimum cert epoch the ROM accepts | anti-rollback of the **signing certs themselves** |

Per-component sub-dictionaries also carry **`EPRO`** (effective production status) and **`ESEC`** (effective security mode) flags, so a single manifest can describe whether each component is loaded in production or demoted-security context.

The boot loader's verification is then mechanical. For each stage it is about to load, the validator (in SecureROM, then iBoot, then iBoot's loaders) runs roughly:

1. **Parse** the IM4M's DER and pull the **certificate chain**; verify it chains up to the **Apple Secure Boot CA** whose root is fused into / pinned by SecureROM. Reject if the chain is broken or the cert **epoch** is below `CEPO`.
2. **Verify the signature** over `MANB` with the leaf cert's key. Reject on mismatch — this is what makes the manifest unforgeable.
3. **Match the device**: confirm `ECID`, `CHIP`, `BORD`, `CPRO`, `CSEC` in `MANP` equal *this* silicon's fused values, and that `BNCH` equals the `ApNonce` derived from the current NVRAM generator (and `snon` equals the live SEPNonce). Reject if any differ — this is the anti-replay.
4. **Match the component**: SHA-384 the IM4P payload it's about to load, and confirm that digest equals the `DGST` under that component's 4CC in the manifest. Reject if absent or different.

Only when all four pass does the stage load. Any failure halts the boot (Recovery/DFU). Because steps 2–3 are inseparable — the *signature* covers the *device-binding values* — you cannot edit an ECID or nonce into a manifest without invalidating Apple's signature, and you cannot re-sign without TSS.

> 🔬 **Forensics note:** A saved SHSH/`.shsh2` blob is **personally identifying hardware evidence**. Its MANP carries the device **ECID** in cleartext (`ipsw img4 im4m info` prints it). Finding `blobs/` or `*.shsh2` files on a suspect's computer ties that computer to a *specific* iPhone by chip serial, dates the activity to the OS build the blob was signed for, and — because TSS only signs while a version is current — proves the blob was obtained *during that version's signing window*. Treat a blob trove like a list of device serial numbers with timestamps.

### IM4R — restore info & the boot nonce

The IM4R is the smallest of the three: a `SET` whose principal element is **`BNCN`**, the **boot nonce (the "generator")** used for this restore. During a restore the host (idevicerestore/Finder) writes the generator into device NVRAM as `com.apple.System.boot-nonce`; the device then derives the `ApNonce` from it (see below) and that `ApNonce` is what TSS signs into the manifest's `BNCH`. The IM4R is how the generator is conveyed alongside the personalized image.

In a *stock* restore the IM4R is generated fresh and the generator is random — so each restore is uncacheable. In a *downgrade with a saved blob* (checkm8 hardware only), futurerestore does the opposite: it reads the generator embedded in your saved `.shsh2`, builds an IM4R that pins **that** generator, and writes it into NVRAM so the device re-derives the exact `ApNonce` the old manifest's `BNCH` expects. The IM4R is thus the small but load-bearing piece that makes a blob redeemable — and the reason a blob is worthless if you didn't record its generator.

### Personalization: welding an install to one device

Here is the full ceremony. The goal is anti-replay: a manifest must be valid for **exactly one device and exactly one restore**, so that it can never be cached and reused to install an old OS later.

```
            ┌─────────────────────────── one restore ───────────────────────────┐
 device     host (idevicerestore/Finder)         Apple TSS (gs.apple.com)
 ──────     ────────────────────────────         ───────────────────────────────
 ECID  ───────────►  build TSS request plist  ─────►  validate: is this build
 ApNonce ─────────►  { ApECID, ApNonce,                still being signed?
 SEPNonce ────────►    ApChipID, ApBoardID,            does ApNonce match a
 (chip fused        ApProductionMode, CEPO,            legal generator?
  CHIP/BORD/        + per-component Digests
  CPRO/CSEC)          from BuildManifest }     ◄─────  sign MANB → return IM4M
                            │                          (the APTicket / SHSH)
                            ▼
                   personalize each IM4P, boot/flash with the IM4M
```

Two nonces do the welding:

- **ApNonce** — the AP (application processor) boot nonce. The device does **not** sign a raw random value; it stores an 8-byte **generator** in NVRAM and derives `ApNonce = truncate(SHA-384(generator))` on modern SoCs (older A-series used SHA-1). The generator is the seed; the `ApNonce` is what ends up in `BNCH`.
- **SEPNonce** — the Secure Enclave's own nonce, signed into `snon`, so the SEP firmware install is independently anti-replayed.

Because `ApNonce` (via the generator) and `ECID` are both inside the **signed** manifest, a captured IM4M is useless on any other device (wrong ECID) and useless on the same device after the nonce rolls (wrong `ApNonce`) — **unless** you can force the device to present the *same* `ApNonce` again by re-writing the generator. On A12+ with no jailbreak, you can't write NVRAM, so that door is shut. On checkm8 devices (A8–A11) you *can* set the generator from a SecureROM exploit, which is exactly why blob-based downgrades remain alive only on that hardware ([[the-jailbreak-landscape-2026]]).

> 🔬 **Forensics note:** The **ECID is a stable, device-unique correlation key** that surfaces in more places than the SHSH blob: it appears in the manifest of any saved blob, in `idevicerestore`/Finder restore logs, in `ideviceinfo`'s `UniqueChipID`, and in sysdiagnose/`os_log` lines around restores and updates. If you can tie an ECID seen in one artifact (say, a blob on a laptop) to the same ECID reported by a seized handset (`ideviceinfo -k UniqueChipID`), you've cryptographically linked the computer's owner to *that physical phone* — far stronger than a serial number a user can read off the box.

### Beyond the AP: the SEP and baseband tickets

Personalization is not a single ticket — it's a family. The same TSS round-trip that returns the AP manifest (`@ApImg4Ticket`) can also return a **baseband ticket** (`@BBTicket`) for devices with a cellular modem. The baseband is its own processor with its own anti-replay identity, so its request carries modem-specific fields — `BbNonce`, `BbChipID`, `BbSNUM` (the modem serial), and `BbGoldCertId` — and the returned signature binds the baseband firmware to *that modem*, separately from the AP binding. The SEP, as covered above, is gated by its own `SepNonce`/`snon`. So a full restore of a cellular iPhone is really three interlocking personalizations — **AP, SEP, baseband** — each with an independent nonce, any one of which can refuse and halt the restore.

This matters for both downgrades and forensics: a saved AP blob alone is insufficient to fully restore a cellular device, because the baseband ticket (which you generally cannot save the way you save an AP blob) must also validate. It's another reason "I have blobs" is weaker than it sounds.

### TSS — the Tatsu Signing Server

The signing oracle is **TSS (Tatsu Signing Server)**, reached at `http://gs.apple.com/TSS/controller?action=2`. (`action=0` is a health check that returns the famous `"Server not ready"` HTML.) A signing request is a **single XML property list** describing the target build, the device identity (`ApECID`, `ApNonce`, `ApChipID`, `ApBoardID`, `ApProductionMode`, `ApSecurityDomain`, `UniqueBuildID`…), and a **per-component dictionary of digests** copied out of the IPSW's `BuildManifest.plist`. Skeleton of the POST body:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>@ApImg4Ticket</key>          <true/>   <!-- "give me an Image4 manifest" -->
    <key>ApECID</key>                 <integer>0x000123456789ABCD</integer>
    <key>ApNonce</key>                <data>…20–32-byte ApNonce (from generator)…</data>
    <key>ApProductionMode</key>       <true/>
    <key>ApSecurityDomain</key>       <integer>1</integer>
    <key>ApChipID</key>               <integer>0x8130</integer>
    <key>ApBoardID</key>              <integer>0x04</integer>
    <key>SepNonce</key>               <data>…SEP nonce…</data>
    <key>UniqueBuildID</key>          <data>…from BuildManifest…</data>
    <key>KernelCache</key>  <dict><key>Digest</key><data>…</data> … </dict>
    <key>iBEC</key>         <dict><key>Digest</key><data>…</data> … </dict>
    <!-- … one dict per component, digests lifted from BuildManifest.plist … -->
</dict>
</plist>
```

If — and only if — Apple is **currently signing** that build for that device, TSS replies with a plist containing `ApImg4Ticket`: the freshly minted **IM4M**. Otherwise it returns a non-zero `MESSAGE`/`STATUS` (e.g. *"This device isn't eligible for the requested build"*) and no ticket.

The critical property: **TSS signs on demand and statelessly.** Apple holds no per-device archive of old tickets; the signature is computed live each time, against a server-side allowlist of *currently-signed* builds. The instant Apple removes a build from that allowlist (typically days to a couple of weeks after the next release ships), TSS returns an error for it forever after — **no signature, no install.** This is the entire downgrade-prevention model: there is no signature check you can bypass offline because the signature for the version you want **was never issued to you and now never will be.**

> ⚖️ **Authorization:** The signing window is why "just downgrade the seized phone to a jailbreakable iOS" is usually a dead end on modern hardware, and why examiners must document the device's *current* OS build at seizure — it bounds which acquisition methods are even possible. Don't attempt restores, downgrades, or DFU operations on evidence devices outside a documented, authorized SOP; a restore **destroys** user data and re-personalizes the device. See [[acquisition-sop-and-chain-of-custody]].

### SHSH blob saving — what it does and doesn't enable

"Saving your blobs" means: while a version is still being signed, ask TSS for *your* device's IM4M for that build and save the response to disk. Tools: **tsschecker** (CLI, by tihmstar) and **blobsaver** (cross-platform GUI front-end that drives tsschecker / TSSSaver).

The non-obvious part is the **generator**. A saved `.shsh2` blob embeds one specific `ApNonce`, which means it's only usable later if your device can be made to present that *same* `ApNonce`. So blob savers don't let the device pick a random generator — they pin it to a known constant (canonically `0x1111111111111111`) and record it. To use the blob later you set that same generator back into NVRAM so the derived `ApNonce` matches `BNCH`.

What a saved blob **does** buy you:

- It is a *capability token* to re-sign a now-unsigned build **for that one device** — i.e. a future-proofed downgrade key, redeemable only with a tool that can replay the nonce.

What it **does not** buy you:

- **Nothing on its own.** A blob is inert without a way to (a) write the matching generator into NVRAM and (b) get the device to accept the restore — both of which require an exploit. On **A12+ / iOS 18/26 there is no public way to do either**, so blobs for current devices are, today, collectors' items. On **checkm8 A8–A11** the SecureROM exploit supplies both, and tools like futurerestore can drive an actual downgrade.
- It is **not** a decryption key, **not** a passcode bypass, and **not** transferable to another device.

> 🖥️ **macOS contrast:** Apple Silicon Macs add a wrinkle iOS lacks — because a Mac can run at **Reduced Security**, its LocalPolicy nonce (`lpnh`, a SHA-384 hash held in the Secure Storage Component and visible only to sepOS) and the `smb0` "accept global signing" flag give the *owner* a sanctioned way to relax the manifest requirement. There is no `bputil`, no Reduced Security, and no owner-controlled boot policy on an iPhone: the personalization gate is absolute.

### Why the gate breaks only on checkm8 (A8–A11)

It's worth being precise about *where* the model fails, because it's the boundary that defines the whole downgrade/jailbreak landscape. The personalization chain assumes the **AP cannot be coerced into presenting an attacker-chosen nonce** and **cannot run unsigned code before the manifest check**. **checkm8** (an unpatchable SecureROM use-after-free on A8–A11) breaks both assumptions: it executes before any signature check, so a host can (a) **set the generator** in NVRAM so the device re-derives a *known, previously-signed* `ApNonce`, and (b) load a tethered, exploit-patched chain that honours a saved (now-unsigned) IM4M. With a matching saved blob, futurerestore can then walk the device through a real downgrade. On **A12+**, where SecureROM is patched and PAC/SPTM/TXM harden everything above it, neither primitive exists publicly — so the gate holds and saved blobs stay theoretical. This is the exact technical reason the [[the-jailbreak-landscape-2026]] splits cleanly at the A11/A12 line.

## Hands-on

All commands run **on the Mac** — there is no on-device shell, and none is needed: IMG4 is a file format you parse off a downloaded IPSW. Primary tool is **`ipsw`** (blacktop), with **`img4tool`** (tihmstar) and **`pyimg4`** (m1stadev) as alternates.

```bash
brew install blacktop/tap/ipsw          # the swiss-army IPSW/IMG4 tool
brew install tsschecker img4tool 2>/dev/null  # tihmstar tools (or build from source)
pipx install pyimg4                     # pure-python IMG4 lib + CLI
```

### Pull an IPSW and look inside

```bash
# Download the current signed IPSW for a device (no Apple ID needed; Apple CDN)
ipsw download ipsw --device iPhone16,1 --version 26.5

# An IPSW is just a zip. The components are .im4p; the recipe is BuildManifest.plist
unzip -l iPhone16,1_26.5_*.ipsw | grep -Ei 'im4p|BuildManifest'
#   kernelcache.release.iphone16    (an IM4P)
#   Firmware/all_flash/iBoot.*.im4p
#   Firmware/all_flash/sep-firmware.*.im4p
#   BuildManifest.plist
```

### Inspect an IM4P (payload)

```bash
# What is this component? type tag, compression, encryption status
ipsw img4 im4p info kernelcache.release.iphone16
#   Type:        krnl
#   Description: KernelCache
#   Compression: lzfse
#   Encrypted:   false

# Extract (auto-decompresses) → a raw Mach-O kernelcache you can feed to ipsw/Ghidra
ipsw img4 im4p extract --output kernelcache.bin kernelcache.release.iphone16

# For an ENCRYPTED component, dump its keybag as JSON
ipsw img4 im4p extract --kbag sep-firmware.d8x.im4p | jq .
#   [{ "type": "PRODUCTION", "iv": "…", "key": "…(wrapped by GID)…" }, … ]

# Auto-lookup community keys (checkm8 devices only) and decrypt in one shot
ipsw img4 im4p extract --lookup --lookup-device iPhone10,3 --lookup-build 20H71 \
    sep-firmware.d10.im4p
```

### Inspect an IM4M (manifest / SHSH)

```bash
# Read a saved .shsh2 blob's manifest: ECID, chip, nonces, per-component digests
ipsw img4 im4m info my_device.shsh2
#   ECID:    0x000123456789ABCD       ← the device serial; cleartext
#   ChipID:  0x8130
#   BoardID: 0x04
#   ApNonce / BNCH: …
#   SepNonce / snon: …
#   Components: krnl, ibot, sepi, … each with a DGST

# Pull the bare IM4M out of an .shsh2 wrapper
ipsw img4 im4m extract --output device.im4m my_device.shsh2

# Verify a manifest's component digests against an IPSW's BuildManifest
ipsw img4 im4m verify --build-manifest BuildManifest.plist device.im4m
```

### Read an IM4R / forge a boot nonce (for understanding, not flashing)

```bash
# Construct an IM4R carrying a specific boot-nonce generator
ipsw img4 im4r create --boot-nonce 1111111111111111 --output restore.im4r
ipsw img4 im4r info restore.im4r        #   BootNonce: 1111111111111111
```

### Check the signing window with tsschecker

```bash
# Is iOS 26.5 still being signed for this device right now?
tsschecker -d iPhone16,1 -i 26.5 -B D83AP
#   [TSSC] iOS 26.5 for device iPhone16,1 IS being signed!

# Save YOUR blobs (needs the real ECID; generator pinned for future replay)
tsschecker -d iPhone16,1 -i 26.5 -e 0x123456789ABCD --generator 0x1111111111111111 -s
#   writes iPhone16,1_…_26.5-….shsh2 to cwd
```

### Cross-tool sanity check

```bash
# img4tool prints the manifest body and cert chain in a different layout
img4tool -e -s my_device.shsh2 -m device.im4m     # extract IM4M from SHSH
img4tool --print-all device.im4m | less

# pyimg4 for scripting / pulling apart in Python
pyimg4 im4p info -i kernelcache.release.iphone16
pyimg4 manifest info -i device.im4m
```

### Identify an unknown firmware component

This is the everyday forensic/RE workflow: you have a loose `.im4p` (carved from a backup, a download cache, or memory) and need to name it.

```bash
# 1) What kind of component is it?  (type tag is self-describing)
ipsw img4 im4p info unknown.im4p
#   Type: rkrn   Description: RestoreKernelCache   Compression: lzfse

# 2) Hash the payload and match it against candidate IPSWs' BuildManifests.
#    'ipsw' can scan a folder of IPSWs and tell you which build a component belongs to:
ipsw img4 im4m verify --build-manifest BuildManifest.plist suspect.im4m
#    …or diff two builds' digests to see which components actually changed:
ipsw diff <old>.ipsw <new>.ipsw       # shows per-component digest deltas
```

Matching the payload's SHA-384 to a `BuildManifest.plist` `Digest` pins the component to an **exact build + board**, which (via Apple's build/version tables) gives you the **OS version and device model** the firmware came from.

> 🔬 **Forensics note:** This digest-matching is the same move that dates a firmware artifact for you. A loose component that matches *only* builds Apple has already stopped signing tells you the artifact predates that window's close; a component matching the current build is consistent with a recent update. Combine that with the ECID correlation above and a blob/firmware trove becomes a small timeline of when a specific device was provisioned or downgraded — without ever touching the device.

## 🧪 Labs

> **Substrate for every lab below:** a **publicly downloaded IPSW** from Apple's CDN (parsed read-only on your Mac with `ipsw`) plus, where a manifest is needed, a **public sample `.shsh2` blob** (community blob repos, or a tsschecker run with a throwaway ECID). **Fidelity caveat:** an IPSW ships **un-personalized** components and the *generic* `BuildManifest.plist` — it does **not** contain a real IM4M, because the manifest is minted live by TSS at restore time. To see a true device-bound IM4M you need a saved blob. None of these labs touch a device, attempt a restore, or require SEP/Data-Protection — they exercise the *container format and signing protocol*, which are fully observable Mac-side. (The Xcode Simulator is irrelevant here: it has no firmware, no IMG4, and no boot chain.)

### Lab 1 — Dissect a real kernelcache out of an IPSW (downloaded IPSW)

1. `ipsw download ipsw --device iPhone16,1 --version 26.5` (or any device/version still on Apple's CDN).
2. Unzip and locate `kernelcache.release.*`. Run `ipsw img4 im4p info` on it — record the **type tag** (`krnl`), the **compression** (`lzfse`), and confirm **Encrypted: false**.
3. `ipsw img4 im4p extract --output kc.bin` it, then `ipsw macho info kc.bin` (or `file kc.bin`) — confirm you now hold a raw arm64e Mach-O kernel collection.
4. Repeat `im4p info` on `sep-firmware.*.im4p`. Note that **this** component reports a **KBAG** / Encrypted: true. Dump it with `--kbag` and observe the GID-wrapped key you *can't* unwrap without checkm8-era key data.

### Lab 2 — Walk the ASN.1 by hand (downloaded IPSW)

1. Pick any `.im4p` and run `openssl asn1parse -inform DER -in iBoot.*.im4p | head -40`.
2. Identify the leading `IA5String` = `IM4P`, the four-char **type tag**, the **description string**, and the large `OCTET STRING` payload. You're now reading the same bytes SecureROM's parser reads.
3. Note how little structure protects a huge attack surface — this is why the iBoot Image4 validator is a recurring target (see further reading).

### Lab 3 — Map the BuildManifest to the boot chain (downloaded IPSW)

1. `plutil -p BuildManifest.plist | less`. Find `BuildIdentities` → the entry matching your board.
2. Under `Manifest`, list the component 4CCs (`LLB`, `iBoot`, `KernelCache`, `RestoreSEP`, `RestoreRamDisk`, `OS`, …) and their `Digest` values and paths.
3. These digests are **exactly** what the host copies into the TSS request and what come back signed inside the IM4M's per-component `DGST` entries. You've just traced the data path from IPSW → TSS request → manifest.

### Lab 4 — Inspect a manifest and find the ECID (sample SHSH blob)

1. Obtain a sample `.shsh2` (a community blob, or `tsschecker -d <dev> -i <ver> -e 0xDEADBEEF -s` with a throwaway ECID against a **currently-signed** version).
2. `ipsw img4 im4m info sample.shsh2`. Locate `ECID`, `ChipID`, `BNCH`/ApNonce, `snon`/SepNonce.
3. Articulate, in one sentence, what this single file proves about the device it came from (chip serial) and the time it was obtained (within that build's signing window). This is the forensic crux.

### Lab 5 — Observe the signing window (read-only TSS query)

1. `tsschecker -d iPhone16,1 -i 26.5` — confirm a **currently** signed version reports *IS being signed*.
2. Run it again for a clearly **old** version (e.g. an iOS 18.x build for the same device): observe *NOT being signed*.
3. You've now seen the entire downgrade-prevention model with a single network round-trip: the older signature simply **cannot be obtained**, no matter what's on disk.

### Lab 6 — Diff two builds and watch the digests move (two downloaded IPSWs)

1. Download two adjacent builds for the same device (e.g. 26.4 and 26.5).
2. `ipsw diff iPhone16,1_26.4_*.ipsw iPhone16,1_26.5_*.ipsw` and scan the per-component output.
3. Confirm that the `Digest` for components that changed (kernelcache, iBoot, SEP) is different between builds, while unchanged components keep the same digest. This is *why* a manifest is build-specific: a 26.4 manifest's `DGST` values won't match 26.5's payloads, so a 26.4 IM4M cannot validate a 26.5 install even on the right device — independent of the signing window.

## Pitfalls & gotchas

- **An IPSW does not contain your SHSH.** Newcomers grep an IPSW for the manifest and find only `BuildManifest.plist` (the *recipe* of digests) and bare `.im4p` files. The real IM4M is **fetched live from TSS** per device, per restore. There is nothing device-specific in a stock IPSW.
- **"I saved my blobs, so I can downgrade anytime" — false on A12+.** A blob is inert without (a) writing the matching generator into NVRAM and (b) an exploit that lets the device accept an unsigned-by-current-TSS restore. With no public A12+ jailbreak, current-device blobs are unusable today. They're a *bet* on a future exploit, not a present capability.
- **The kernelcache is not encrypted (since iOS 10).** Don't waste time hunting for a kernelcache KBAG or key — there isn't one. SEP firmware and some bootloaders still are encrypted; their GID-wrapped keys are only recoverable on checkm8 hardware.
- **Generator vs. ApNonce confusion.** The 8-byte value you set in NVRAM (and see in tools) is the **generator**; the value that lands in the manifest's `BNCH` is `truncate(SHA-384(generator))`, the **ApNonce**. They are not the same number. A blob "matches" your device only when the *derived* ApNonce equals `BNCH`.
- **Two nonces, two anti-replays.** Forgetting the **SEPNonce** (`snon`) is a classic futurerestore-era failure: the AP side personalizes fine but the SEP refuses because its nonce doesn't match. The SEP is independently gated.
- **CEPO / certificate epoch is a second rollback fence.** Even setting aside the signing window, Apple bumps the **certificate epoch** so older SecureROM cert chains stop validating — an anti-rollback on the *signing infrastructure itself*, separate from per-build signing.
- **Restoring an evidence device is destructive and irreversible.** A restore wipes user data, re-personalizes against current TSS, and rolls the nonce. There is no "undo." Never treat DFU/restore as a casual diagnostic on evidence — see [[acquisition-sop-and-chain-of-custody]].
- **`ipsw` vs `img4tool` vs `pyimg4` disagree on labels.** They print the same DER with different field names (`BNCH` vs "ApNonce", `DGST` vs "Digest"). Cross-check with `openssl asn1parse` when a field name is ambiguous; the ASN.1 tags are the ground truth.
- **A manifest is build-specific *and* device-specific — both gates are independent.** Even if Apple were still signing an old build, a 26.4 IM4M still can't validate 26.5 components because the `DGST` values differ (Lab 6). Conversely, a correctly-digested manifest still fails on the wrong device because `ECID` won't match. Don't conflate "is it signed?" with "does it match my hardware/version?".
- **Beta and IPSW "OTA" personalization differ.** OTA update manifests and full-restore IPSW manifests are requested from TSS with different per-component sets; a blob saved for the full IPSW build is not interchangeable with the OTA's update ramdisk path. When archiving blobs, save the full-IPSW build.
- **`generator` lives in NVRAM and is wiped by a restore.** If you set a custom generator to match a saved blob, a subsequent normal restore re-randomizes it. The generator is per-NVRAM-state, not permanent — record it alongside the blob or the blob is orphaned.
- **The `OS` component is the whole root filesystem, not a small binary.** In a BuildManifest the `OS` entry's IM4P payload is the APFS system image (multi-GB) — don't expect to `openssl asn1parse` it casually the way you would a logo or device tree. Its digest is still just one `DGST` line in the manifest like everything else.
- **The IMG4 ASN.1 parser is itself an attack surface.** SecureROM/iBoot must parse attacker-influenced DER *before* the signature is fully trusted; malformed-length and nesting bugs in Image4 validators have been a recurring research target (see the iBoot validator writeup in further reading). When fuzzing or auditing, the container parser — not just the crypto — is in scope.

## Key takeaways

- **Image4 (IMG4)** is Apple's universal signed-firmware container — DER-encoded ASN.1, three object types: **IM4P** (payload), **IM4M** (manifest/APTicket/SHSH), **IM4R** (restore info / boot nonce).
- The **IM4M manifest** is Apple's signature over a set of component **SHA-384 digests (`DGST`)** plus device-binding properties (**`ECID`**, **`BNCH`**/ApNonce, **`snon`**/SepNonce, `CHIP`, `BORD`, `CEPO`…). The boot chain refuses any component whose hash isn't in a validly-signed manifest for *this* chip and *this* boot.
- **Personalization** welds an install to **one device (ECID)** and **one restore (nonce)** so manifests can't be cached and replayed. **TSS (gs.apple.com)** signs them **on demand and statelessly**; nothing is archived.
- **Downgrade prevention is the absence of a signature, not a check you can bypass:** once Apple drops a build from TSS's allowlist, the manifest for it can never be issued. There's no offline workaround on modern hardware.
- A saved **SHSH blob** is a *future-proofed, device-specific* re-signing token — but **inert without an exploit** to replay the nonce and accept the restore. Usable for real downgrades only on **checkm8 A8–A11**; collectors' items on A12+/iOS 18/26.
- **Forensically**, an IM4P fingerprints a firmware build/device, and a saved `.shsh2` is **device-serial evidence** (cleartext ECID) timestamped to a signing window. The signing gate also bounds which OS — and thus which acquisition exploits — a seized device can be put into.
- **Apple Silicon Macs share the exact format and TSS concept** but expose owner-controlled **Reduced Security / LocalPolicy**; iOS has no such escape hatch — full security, always.

## Terms introduced

| Term | Definition |
|---|---|
| **Image4 / IMG4** | Apple's DER-encoded ASN.1 container for signed firmware on A7+/Apple Silicon; supersedes IMG3. |
| **IM4P** | Image4 *payload* — one firmware component (type tag like `krnl`, `ibot`, `sepi`), optionally compressed and KBAG-encrypted. |
| **IM4M** | Image4 *manifest* — Apple's signature over approved component digests + device binding. The **APTicket / SHSH blob**. |
| **IM4R** | Image4 *restore info* — carries the boot-nonce generator (`BNCN`) for a restore. |
| **KBAG (Keybag)** | The `{type, IV, wrapped-key}` set inside an encrypted IM4P; IV+key are wrapped by the SoC **GID key**. |
| **GID key** | Per-SoC-model AES key fused into silicon, usable only by the hardware AES engine; needed to decrypt KBAGs. |
| **APTicket** | Jailbreaker name for the IM4M — the personalized boot manifest. |
| **SHSH / SHSH2 blob** | The IM4M saved to disk (`.shsh`/`.shsh2`); a device-specific re-signing token carrying the ECID in cleartext. |
| **MANB / MANP** | Manifest *body* / manifest *properties* sub-structures inside an IM4M. |
| **DGST** | The SHA-384 **digest** of a component's IM4P payload, stored per-component in the manifest. |
| **ECID** | Exclusive Chip ID — the unique per-die serial; the manifest property that binds a restore to one device. |
| **ApNonce / `BNCH`** | The AP boot nonce signed into the manifest; derived as `truncate(SHA-384(generator))`. |
| **Generator** | The 8-byte seed (`com.apple.System.boot-nonce` in NVRAM) from which the ApNonce is derived. |
| **SEPNonce / `snon`** | The Secure Enclave's independent boot nonce, separately anti-replayed. |
| **BBTicket** | The baseband personalization ticket (`@BBTicket`); binds modem firmware to the modem via `BbNonce`/`BbChipID`/`BbSNUM`. |
| **EPRO / ESEC** | Per-component effective-production / effective-security flags inside the manifest. |
| **CEPO** | Certificate Epoch — the minimum signing-cert epoch the ROM accepts; an anti-rollback on the signing certs. |
| **Personalization** | The ceremony binding an install to one ECID + one nonce so manifests can't be cached/replayed. |
| **TSS (Tatsu Signing Server)** | Apple's online signer at `gs.apple.com/TSS/controller`; mints IM4Ms on demand for currently-signed builds only. |
| **Signing window** | The period Apple keeps a build on TSS's allowlist; once closed, that build can never be (re-)signed. |
| **BuildManifest.plist** | The plist inside an IPSW listing each component's path and `Digest`; the recipe a TSS request is built from. |

## Further reading

- **The Apple Wiki** — [IMG4 File Format](https://theapplewiki.com/wiki/IMG4_File_Format), [SHSH Protocol](https://theapplewiki.com/wiki/SHSH_Protocol), [Tatsu Signing Server](https://www.theiphonewiki.com/wiki/Tatsu_Signing_Server) — authoritative field-by-field references for the ASN.1 tags, 4CC catalog, and TSS request/response.
- **Apple Platform Security Guide** — Secure Boot, "Boot process for a Mac with Apple silicon," and "Contents of a LocalPolicy file" (support.apple.com) — the macOS-side personalization and Reduced Security model.
- **blacktop/ipsw** — [Parse Img4 guide](https://blacktop.github.io/ipsw/docs/guides/img4/) and the `ipsw img4` CLI docs — the toolchain used in this lesson.
- **tihmstar** — [`img4tool`](https://github.com/tihmstar/img4tool), `tsschecker`, futurerestore; **m1stadev** — [`PyIMG4`](https://github.com/m1stadev/PyIMG4); **airsquared/blobsaver** — the GUI blob saver.
- **amarioguy** — ["An analysis of iBoot's Image4 parser"](https://amarioguy.github.io/2025/10/20/iboot_image4_validator.html) — the validator as an attack surface.
- **Jonathan Levin**, *MacOS and iOS Internals* Vol. III (newosxbook.com) — Image4, the boot chain, and SecureROM internals.
- **Jay Freeman (saurik)** — ["Where did my iOS 6 TSS data go?"](https://www.saurik.com/apticket.html) — the historical origin of nonce entanglement and uncacheable tickets.
- **libimobiledevice/idevicerestore** — the open-source restore client that builds TSS requests and personalizes IMG4 components; reading its source is the clearest way to see the ceremony end to end.
- **futurerestore** (m1stadev/marijuanARM fork) — the tool that consumes a saved blob + custom IM4R to drive a checkm8-era downgrade; its README documents the generator/nonce requirements concretely.
- `man` pages / `--help` for `ipsw img4`, `tsschecker`, `img4tool`; **ios.cfw.guide** "Saving Blobs" for the practical blob/generator workflow.

---
*Related lessons: [[boot-chain-securerom-iboot]] | [[the-jailbreak-landscape-2026]] | [[acquisition-sop-and-chain-of-custody]] | [[secure-enclave-hardware]] | [[code-signing-amfi-entitlements]] | [[xnu-on-mobile]]*
