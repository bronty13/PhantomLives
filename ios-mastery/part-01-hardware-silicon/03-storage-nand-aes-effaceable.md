---
title: "Storage: NAND, the AES engine & effaceable storage"
part: "01 — Hardware & Silicon"
lesson: 03
est_time: "45 min read + 20 min labs"
prerequisites: [secure-enclave-hardware]
tags: [ios, hardware, storage, nand, aes, effaceable, forensics]
last_reviewed: 2026-06-26
---

# Storage: NAND, the AES engine & effaceable storage

> **In one sentence:** Every byte that lands on an iPhone's NAND is already AES ciphertext — encrypted in-line by a hardware engine wedged into the DMA path and keyed only by material the Secure Enclave releases — so the data at rest is unreadable without the device, and "wiping" the phone means destroying a few hundred bytes of key material in a dedicated *effaceable* region rather than overwriting the disk.

## Why this matters

On a Mac you can pull the SSD, attach it to a write-blocker, and (FileVault aside) carve a forensic image at the physical layer — the classic dead-box workflow you carried over from `macos-mastery`. On a modern iPhone that workflow is **dead three times over**, and understanding *why* is the foundation of every iOS acquisition decision you'll make in Part 07. The NAND is raw flash behind a proprietary controller (you can't address it like a disk), everything on it is inline-AES ciphertext (so even a perfect chip-off yields noise), and the flash translation layer plus TRIM mean the physical-page recovery you rely on elsewhere is unreliable even *before* encryption. Meanwhile the same architecture gives Apple an instant, irreversible "erase the whole phone in milliseconds" capability — **crypto-shred** — that replaces overwriting entirely. This lesson is the hardware substrate under Data Protection, BFU/AFU, and the "what can I even decrypt?" question.

It also flips an instinct you've spent a career building. In disk forensics, *the medium is the evidence* — you image it, hash it, and carve it, and "deleted" rarely means gone. On iOS the medium is a sealed box of ciphertext, and the evidence only exists as plaintext *while the live device decrypts it for you*. Get this hardware model wrong and you will either over-promise recovery you can't deliver or, worse, let a remote-wipe destroy a case while you reach for the wrong tool. Get it right and the rest of Part 07 is just choosing which cooperative-device path yields the most.

## Concepts

### The storage topology: NAND, the ANS controller, and where plaintext lives

An iPhone has no SSD in the PC sense. It has raw **NAND flash** packages soldered to (or, on recent models, mounted on a stubby module that *looks* like an M.2 SSD but carries no controller of its own) the logic board, driven by a storage controller that lives **inside the SoC**. That controller — Apple's **ANS** ("Apple NAND Storage") co-processor, an NVMe-class block device running its own firmware and flash-translation layer — is what XNU talks to over a private NVMe-ish interface. There is no off-the-shelf NVMe drive to image; the "drive" is silicon inside the A-series chip plus dumb NAND.

The single most important structural fact is **where in this path the data becomes ciphertext**:

```
   Application Processor (CPU)               Secure Enclave (SEP)
        │  sees PLAINTEXT in RAM                  │ holds/derives/unwraps class keys
        │  never sees the keys ───────────────────┤ never exposes keys to the AP
        ▼                                         │
  ┌───────────────┐    dedicated keying channel   │
  │  System DRAM  │◄──────────────────────────────┘
  └───────┬───────┘     (per-file key material only)
          │ DMA  (plaintext still here)
          ▼
  ┌──────────────────────────────────────┐
  │   Inline AES-256 XTS engine          │  ◄── sits ON the DMA path,
  │   (keyed per-file by the SEP)        │      between memory and storage
  └───────┬──────────────────────────────┘
          │  CIPHERTEXT from here outward
          ▼
  ┌──────────────────────────────────────┐
  │  ANS storage controller (NVMe-class) │  runs firmware + flash-translation layer (FTL)
  └───────┬──────────────────────────────┘
          │  isolated flash bus (A9 and later)
          ▼
  ┌──────────────────────────────────────┐
  │      Raw NAND flash packages         │  ◄── everything here is ciphertext
  │  [ effaceable region ] [ APFS … ]    │
  └──────────────────────────────────────┘
```

Plaintext exists only in the AP and in DRAM. The moment a write crosses the AES engine it is ciphertext, and it stays ciphertext through the controller, across the bus, and onto the NAND. Reads are the mirror image: the engine decrypts as data streams *in* from flash. The keys themselves are handed to the engine over a **dedicated channel from the Secure Enclave** that the application processor — and therefore the OS, and therefore any exploit running in the kernel — never sees. From A9 onward the flash subsystem rides an **isolated bus** that is granted DMA access only to the memory regions holding user data, which is why a compromised app processor can't simply reprogram the controller to exfiltrate keys.

> 🖥️ **macOS contrast:** FileVault on Apple Silicon and the T2 also puts an AES engine in the storage data path and binds the volume key to the Secure Enclave — so far, identical. The difference is *granularity and statefulness*. FileVault is essentially **one volume key** (a VEK wrapped by a KEK derived from your login password plus the SEP); the whole Data volume lives or dies on that single key. iOS layers a **per-file key** under a small set of **class keys** under the file-system key, and ties each class key's availability to the device's lock state. The Mac has no concept of "this file is readable now because the screen is unlocked but that file isn't" — iOS does, and it's enforced in this hardware path. There is also no clean Mac analogue to the dedicated effaceable region (next section): the Mac crypto-erases by having the SEP forget the volume key, not by wiping a named NAND locker.

### The ANS controller is itself a co-processor

It's tempting to picture the storage controller as a dumb bridge. It isn't. **ANS is a full co-processor** with its own CPU core, its own firmware, and its own private memory, sitting between XNU and the NAND much as the SEP sits beside the application processor. XNU drives it through an **NVMe-family IOKit driver** (the `IONVMe*`/`AppleANS*` controller stack), submitting commands to NVMe-style submission/completion queues in shared memory — the same queue-pair model you know from PC NVMe, but the "device" is silicon inside the SoC.

The ANS **firmware is a personalized Image4 payload**, signed and version-locked exactly like iBoot and the kernelcache: it is delivered in the IPSW, gets a tag/component slot in the boot manifest, and is loaded and verified as part of the secure boot chain (see [[01-boot-chain-securerom-iboot]] and [[02-image4-personalization-shsh]]). Two consequences fall out of this:

- The flash-translation layer, wear-leveling, GC, and bad-block logic all run **inside that signed firmware**, not in XNU — which is why the host genuinely cannot see or address physical NAND geometry. The mapping table never leaves the controller.
- Because the firmware is personalized to the device's ECID, you can't lift a NAND-plus-controller pair onto a bench and expect a different host to drive it. The Elcomsoft 2026 teardown of Apple's raw-NAND modules makes the practical point: the module is *just NAND* — pop it into a third-party NVMe reader and nothing answers, because the controller that gives it an NVMe personality lives in the phone you no longer have.

> 🔬 **Forensics note:** "The FTL lives in signed firmware inside the SoC" is why you will never produce a coherent physical image of an iOS NAND, encryption aside. There is no host-reachable command that returns "the raw chip in physical-page order with the slack" — the only entity that knows the logical→physical map is the ANS firmware, and it only ever speaks the abstracted, host-visible block address space. This is a *structural* barrier independent of the AES barrier; both would have to fall for physical carving to work, and only one of them is even theoretically attackable.

### Inline AES-XTS and the per-file key

The engine is **AES in XTS mode** — the tweakable, storage-oriented mode (the same family FileVault 2 uses), chosen because it encrypts each disk sector independently without a per-sector IV table and resists the copy-and-paste/ciphertext-stealing attacks that plain CBC invites on block storage. Apple keys it **per file**, not per volume:

- When Data Protection creates a file on the Data volume it generates a fresh **256-bit per-file key** and hands it to the AES engine, which encrypts the file's contents as they stream to flash.
- That per-file key is **wrapped with a class key** (which class depends on the file's Data Protection class — see below) and the wrapped key is stored **in the file's metadata**.
- The metadata, in turn, is encrypted with the **file-system key** (sometimes called the metadata key).
- On open, the wrapped per-file key is **unwrapped with the class key** (only if that class key is currently available, i.e. the device is in the right lock state) and supplied to the engine, which decrypts the contents on read.

The exact cipher width tracks the SoC generation:

| SoC generation | Storage cipher | Key derivation |
|---|---|---|
| A9 – A13 | **AES-128 XTS** | the 256-bit per-file key is *split* into a 128-bit cipher key + 128-bit tweak value |
| A14 – A18, M1+ (and the A19/A19 Pro that follow them) | **AES-256 XTS** | the 256-bit per-file key is run through a **NIST SP 800-108 KDF** to derive a 256-bit cipher key + a 256-bit tweak value |

(The published *Apple Platform Security* edition enumerates A14–A18; the A19 generation in the iPhone 17 line inherits the AES-256-XTS path. Re-verify the exact device enumeration against the current guide edition.)

**Why XTS and not CBC.** Block storage has a hard constraint plain CBC can't meet: the cipher must be *seekable and rewritable in place* without a per-sector IV table, and it must not leak structure when an attacker can see many sectors and watch them change. XTS solves this with a **tweak** derived from the sector position — the second of the two keys above is the *tweak key*, and the per-file key feeds a KDF that yields both halves. Identical plaintext in two different sectors encrypts to different ciphertext (the tweak differs), so the copy-and-paste and watermarking attacks that dog CBC-on-disk don't apply. The cost XTS accepts is that it provides confidentiality, not integrity — it will happily decrypt tampered ciphertext into garbage — which is fine here because file *integrity* on the System volume comes from the SSV seal, not the cipher.

**Per-extent keys and the APFS clone subtlety.** APFS stores file data in **extents**, and Data Protection can key **per-extent**, not merely per-file — Apple's own wording is "per-file (or per-extent) keys." This matters for copy-on-write: when APFS **clones** a file (a `clonefile(2)`-style instant copy, ubiquitous on iOS for Photos edits, Messages attachments, and app caches), the clone *shares the original's extents and therefore their keys* until a write forces a divergent extent. Forensically, two logically distinct files can be backed by the *same* ciphertext on NAND, and an edited photo's "original" may be nothing more than a shared extent the editor never rewrote.

> 🔬 **Forensics note:** "Per-file key wrapped by a class key" is the entire reason **BFU vs. AFU** matters. The ciphertext on the NAND never changes with lock state — what changes is whether the **class key needed to unwrap a given file's key is resident in the SEP**. At Before-First-Unlock the class keys for Complete/Complete-Unless-Open/Complete-Until-First-Auth (classes A/B/C) are not derivable without the passcode, so even with full possession of the device the corresponding files are AES-XTS noise. This is why a BFU full-file-system extraction returns mostly garbage and an AFU one is rich. We trace the class machinery in [[02-data-protection-and-keybags]] and the lock-state timeline in [[03-passcode-bfu-afu-and-inactivity]].

### Two crypto engines, not one

A persistent source of confusion: the **inline storage AES engine** in this lesson is **not** the SEP's own internal crypto. There are (at least) two distinct AES units in play, and conflating them produces wrong mental models of where keys live:

| Engine | Where it sits | What it does |
|---|---|---|
| **Inline storage AES-XTS engine** | on the DMA path, AP side of the SoC | bulk-encrypts/decrypts **file contents** at line speed as they stream to/from NAND; fed per-file keys by the SEP over a dedicated channel |
| **SEP internal crypto (AES + PKA)** | inside the Secure Enclave | wraps/unwraps **key material** — class keys, the keybag, keychain items, the media key; performs the passcode entanglement and the UID operations |

The division of labor is the whole security argument: the **bulk** engine is fast but never *holds* a key it can leak (keys arrive over the SEP channel and are loaded into write-only key registers); the **SEP** holds and manipulates keys but never touches gigabytes of file data. A kernel exploit on the application processor can drive the storage engine to read files *that are currently unlocked*, but it cannot read the key registers, cannot reach into the SEP, and cannot extract a class key to take offline. That boundary is why "we rooted the kernel" still doesn't mean "we have the keys."

> 🔬 **Forensics note:** This is also why an AFU file-system extraction yields plaintext but not *keys*: the exploit reads files the live SEP is willing to unlock, but you never come away with the class keys or the UID to decrypt a separate image later. There is no "extract the keys, then decrypt the chip at our leisure" — the keys stay in the SEP, and decryption is always a live-device service.

### The Data Protection classes (the hardware's view)

Four classes, each backed by a class key with a different availability rule. You'll meet them constantly; here they are at the hardware layer:

| Class | Constant | Key available… | Typical contents |
|---|---|---|---|
| **A** | `NSFileProtectionComplete` | only while unlocked; evicted on lock | Mail bodies, most Apple-app data when locked |
| **B** | `NSFileProtectionCompleteUnlessOpen` | new files writable while locked (public-key), readable only when unlocked | downloads-in-progress |
| **C** | `NSFileProtectionCompleteUntilFirstUserAuthentication` | from first unlock after boot until shutdown (the **AFU** window) | the **default** for most third-party app data |
| **D** | `NSFileProtectionNone` | always — derived from the device UID only, never the passcode | files that must be readable at BFU |

Class **D** is the special case that connects directly to the next section: its master key is the **`Dkey`**, and it lives in effaceable storage precisely because it must be available *before* anyone enters a passcode, yet must still be destroyable on wipe.

**The Dkey is what lets a locked phone function at all.** At **BFU** — fresh boot, never unlocked since — the class A/B/C keys cannot be derived (no passcode entanglement yet), so the only readable data is class D, unwrapped with the `Dkey` straight from effaceable storage. That tiny window of always-available storage is exactly enough for the device to boot, show the lock screen, run the baseband, ring on an incoming call, and honor a `Find My`/remote-wipe command — all without exposing user data. Everything class-C-and-up sits as ciphertext until the first unlock pulls the passcode-derived keys into the SEP and the device transitions to **AFU**, where it stays until shutdown or the **72-hour inactivity reboot** drops it back to BFU.

> 🔬 **Forensics note:** This is the storage-layer reason a BFU acquisition is so thin. With full physical possession of a powered-but-never-unlocked iPhone, only class-D data is decryptable — which by design is almost nothing the user cares about (the defaults push app data to class C). It's also why examiners race the **inactivity-reboot clock**: a seized AFU device left too long quietly re-locks itself into BFU and the high-value classes go dark. The timer and lock-state mechanics are [[03-passcode-bfu-afu-and-inactivity]].

### Effaceable Storage: the hardware kill switch

The flash-wear problem makes "secure delete by overwriting" a lie on any modern storage. The FTL inside the ANS controller **remaps every logical write to a different physical page** for wear-leveling, so when you "overwrite" a file you usually write to a *new* page and leave the old ciphertext sitting in a now-unmapped physical block. You cannot reliably scrub a specific physical location from the host side. Apple's answer is to **never rely on overwriting** and instead make destruction a key-management operation against a tiny region that genuinely *can* be wiped reliably.

That region is **Effaceable Storage**: a small, dedicated area of NAND that is addressed directly and can be securely, atomically erased — historically **block 0 of the raw NAND**, holding roughly **960 bytes** organized as a handful of named **lockers**. The classic three (the foundational iPhone-OS/iOS-4 layout, and still the canonical mental model):

| Locker | Contents |
|---|---|
| **`BAG1`** | the payload key + IV that encrypt the **system keybag** (the keybag holds the class keys) |
| **`Dkey`** | the **class D** (`NSFileProtectionNone`) master key — *not* entangled with the passcode |
| **`EMF!`** | the **file-system / EMF master key** that protects the volume's metadata |

Notice what `BAG1` actually protects: not files, but the **system keybag** — the on-device structure (a binary-plist/protobuf blob) that holds the class keys A/B/C themselves. The class keys are wrapped inside the keybag; the keybag is encrypted under the `BAG1` payload key; and `BAG1` lives in effaceable storage. So a single effaceable locker stands above the entire class-key set, which is exactly why destroying it destroys access to every passcode-protected file at once. (iOS maintains several keybags — system, backup, escrow, OTA-update, iCloud — but only the **system keybag** is the live, on-device one gating Data Protection; the others exist to move keys across trust boundaries and are dissected in [[02-data-protection-and-keybags]].)

The key hierarchy, top to bottom, is what makes the wipe instantaneous:

```
 Hardware UID (fused into SEP/AES engine, never readable, per-device)
        │  entangled with passcode (SEP-tuned KDF, ~80 ms/guess)
        ▼
 Passcode-derived key ── unwraps ──► Class keys A / B / C   (in the system keybag)
                                     Class key D = Dkey      (UID-only, in Effaceable Storage)
        │
        ▼
 Per-file keys ── wrapped by a class key ──► stored in each file's metadata
        │
        ▼
 File-system (metadata) key ── wrapped by the EFFACEABLE key / media key
        │                          (Effaceable Storage  OR  SEP anti-replay media key)
        ▼
 Inline AES-XTS over file contents on NAND
```

Apple's current guidance states it precisely: *"the encrypted file system key is additionally wrapped by an effaceable key stored in Effaceable Storage or using a media key-wrapping key, protected by Secure Enclave anti-replay mechanism."* On newer devices the literal block-0 locker is supplemented (or replaced) by a **media key held in the SEP's anti-replay storage** (the encrypted, monotonic-counter-backed region often called **xART**), which closes a physical-attack avenue against the NAND block — but the *principle* is unchanged: a few hundred bytes gate the entire volume.

**Why anti-replay matters here.** A NAND block can be *snapshotted and restored* by a physical attacker — copy block 0 before a wipe, let the wipe happen, write the old bytes back, and naively you'd resurrect the destroyed key. That's a **replay/rollback** attack, and it's exactly what Skorobogatov's 5C mirroring exploited against the attempt counter. The SEP anti-replay mechanism defeats it by binding the media key (and the SEP's other persistent state) to a **monotonic counter** the SEP controls and that physical NAND restoration can't roll back: replay an old block and the counter no longer matches, so the SEP refuses to unwrap. This is the structural upgrade that turned "destroy a NAND locker" (rollback-able) into "destroy a key the SEP will never re-honor" (not rollback-able) — and it's why post-5s devices closed the mirroring avenue.

### The UID, the GID, and why keys never leave the device

The root of the whole tree is the **hardware UID** — a 256-bit key **fused into the SEP and the AES engine at manufacture**, unique per device, and *never software-readable*. You cannot dump it, image it, or extract it; you can only ask the engine to encrypt or decrypt *with* it. Because the passcode-derived keys are **entangled with the UID** inside the SEP, brute-forcing a passcode is only possible **on the original device** — there's no offline attack against a NAND image, because the UID needed to complete the derivation exists only in that one chip's fuses. The SEP also enforces the **escalating attempt delays** and the wipe-after-N-failures policy, so the brute force is throttled to the SEP's clock (~80 ms minimum per guess, climbing) rather than your cluster's.

The **GID** is the sibling: a key shared across a *class* of devices (all units of a given SoC), used to decrypt firmware images, not user data. The split — per-device UID for user data, per-SoC GID for firmware — is what lets Apple ship one signed firmware to millions of phones while keeping every phone's data keyed to itself. For acquisition this is the bedrock fact: **decryption is a service only the live SEP can perform**, which is why every iOS acquisition method ultimately needs the device powered, the SEP cooperating, and (for class A/B/C) at least one unlock since boot.

> 🖥️ **macOS contrast:** Apple Silicon Macs have a UID too, and FileVault is likewise UID-entangled — but the Mac hands you an escape hatch iOS withholds: a **FileVault recovery key** (or institutional/iCloud key) that can unwrap the volume key without the original SEP, so a properly-escrowed Mac volume *can* be decrypted off-box. iOS has no user-facing recovery key for the data volume; the only "escrow" is iCloud Backup / the iCloud Keychain escrow path, which is an account-level cloud artifact, not a key you type into an offline image. Lose the device's cooperation and the data is gone — that asymmetry drives the whole "must be alive and unlocked-once" envelope.

### Crypto-shred: how "Erase All Content and Settings" finishes before you put the phone down

When the user taps **Erase All Content and Settings** (EACS), or an MDM / Exchange ActiveSync / Find My **remote wipe** command arrives, the device does **not** overwrite the user partition. It **destroys the effaceable key** (and regenerates a new file-system key). The moment that key is gone, the file-system key can no longer be unwrapped, every per-file key under it is unrecoverable, and **every file on the volume is simultaneously, permanently AES ciphertext with no surviving key** — *cryptographically inaccessible*, in Apple's words. Hundreds of gigabytes become noise by erasing a few hundred bytes. That's why an iPhone "erase" completes in seconds where a Mac secure-erase of a spinning disk took hours.

> ⚖️ **Authorization:** The crypto-shred model is the operational reason **seized iOS devices go into a Faraday bag immediately and a remote-wipe is assumed to be inbound at all times.** A wipe you can't see coming will not grind for an hour leaving a recoverable window — it lands in milliseconds and is irreversible. There is no "we pulled the plug mid-erase and carved the remainder." Document radio-isolation (airplane mode is insufficient — Find My can ride any path) as a chain-of-custody step, because the same hardware feature that protects the owner also lets a remote party destroy your evidence between seizure and acquisition.

> 🔬 **Forensics note:** Crypto-shred also reframes "deleted data recovery." The classic carve-unallocated-NAND-for-deleted-files technique is **triply defeated** on iOS: (1) the physical pages are AES-XTS ciphertext you have no key for; (2) the ANS FTL hides the logical→physical mapping, so you can't even address "the slack" coherently; (3) APFS issues **TRIM** on delete and the controller's garbage collection may have already erased the freed pages. Recovery therefore moves **up the stack** to the application/database layer — SQLite freelist pages, un-`VACUUM`ed records, `-wal` journals, and APFS snapshots — covered in [[14-deleted-data-recovery]]. Physical NAND carving is not where iOS evidence lives.

**Erase vs. restore vs. wipe — three different key events.** Investigators conflate these constantly; they touch different keys and leave different traces:

| Operation | What happens to keys | Speed | What survives |
|---|---|---|---|
| **Erase All Content and Settings (EACS)** | effaceable/media key destroyed; new file-system key generated; SEP attempt-counter reset | seconds | nothing decryptable; device boots to setup |
| **Remote wipe** (Find My / MDM / ActiveSync) | same as EACS, triggered over the network | seconds, once it reaches the device | same — hence Faraday-bag-on-seizure |
| **DFU restore** | reflashes firmware + re-creates volumes; effectively re-keys via the same effaceable destruction | minutes (re-image) | nothing decryptable; also rewrites the OS |
| **"Delete" of a file/app** | per-file/class keys untouched; APFS marks blocks free → TRIM | instant | the *ciphertext* may linger in unmapped pages, but unreadable; SQLite/journal traces may persist (see [[14-deleted-data-recovery]]) |

The first three are crypto-shred at the volume level; the fourth is an ordinary unlink that leaves the cryptosystem intact and merely orphans ciphertext. Only the fourth is something a forensic examiner can sometimes claw back, and only at the database/journal layer — never the NAND.

**Forward security is the deeper property.** Apple's guide frames effaceable keys as providing not just fast wipe but **forward security**: once an effaceable key is destroyed, *no future compromise of the device recovers the data it protected*. This is the same idea as forward secrecy in transport crypto, applied to storage. It shows up in more places than EACS — for example, Data Protection rolls key material on certain lock/unlock and re-protection events so that data sealed under an old class-key state can't be retroactively unwrapped after the key is rotated out. For the examiner, the consequence is blunt: **timing is everything.** The same file is recoverable or not depending on whether the key protecting it has been effaced or rolled since it was written — which is why "acquire as soon as lawfully possible, in the state you found it" is not bureaucratic caution but a cryptographic deadline.

> 🔬 **Forensics note:** Forward security is why you cannot "undo" a wipe, a passcode change that re-keys, or even a long power-off that drops class keys to BFU and trust them to come back. There is no key-escrow you forgot to check; the key is gone by design. Treat every key-affecting event (wipe, restore, passcode reset, prolonged BFU) as a one-way door and record exactly when it happened relative to seizure.

### Why physical (chip-off / NAND-mirroring) acquisition is dead on modern devices

Sergei Skorobogatov's **iPhone 5C NAND mirroring** work (2016) is the historical high-water mark of physical attacks: he desoldered the NAND, cloned it, and replayed it to defeat the passcode-attempt counter. It worked because the 5C had **no Secure Enclave** — the counter and key entanglement weren't hardware-isolated. On any device with an SEP (iPhone 5s and later), the same physical clone gets you a faithful copy of **ciphertext you cannot decrypt**: the keys are inside the SEP, entangled with the per-device UID, gated by an SEP-enforced attempt counter and escalating delays. Desolder the NAND on an iPhone 17 and you have a perfect image of AES-256-XTS noise.

The practical consequences for Part 07:

- **Bit-for-bit physical imaging is obsolete** as an evidence source on SEP devices. Acquisition is now *logical* (backup-style), *file-system* (an agent decrypts in place using SEP-released keys at AFU), or *cloud*. See [[01-the-acquisition-taxonomy]] and [[05-full-file-system-acquisition]].
- The exploit chain (checkm8 on A8–A11, or a software chain on newer SoCs) buys you **code execution that can ask the SEP to unwrap keys while the device is unlocked** — it does *not* let you read plaintext off the NAND. The value is "decrypt in place," not "image the chip."
- A8–A11 (checkm8-vulnerable) devices still allow a bootrom-level attack, but even there the SEP holds the keys; checkm8 enables *brute-forcing the passcode* and then SEP-assisted decryption, not raw plaintext recovery.

> 🖥️ **macOS contrast:** The same death of physical imaging hit the Mac at the T2 / Apple Silicon transition — pull the soldered NAND off an M-series Mac and you get ciphertext too. But Mac forensics retained a fallback iOS never had: with the user's password or a FileVault recovery key you can mount and image the decrypted volume over the wire, and Target Disk Mode / DFU-restore-and-image workflows exist. iOS has **no Target Disk Mode, no recovery key you can type to decrypt an image offline**; decryption only ever happens *on the live device* with the SEP participating, which is exactly why "the device must be alive, unlocked-at-least-once, and cooperative" defines the entire iOS acquisition envelope.

### What a file-system acquisition actually reads (the storage view)

If you can't image the chip, what *does* a modern "full file system" extraction read? Plaintext — produced **on the live device** by the very engine in this lesson. The mechanism, at the storage layer:

```
  [device unlocked at least once → class C key resident in SEP]
        │
   acquisition agent runs on-device (via exploit, agent, or developer/MDM path)
        │  open()s each file
        ▼
   class key unwraps the per-file key (SEP) ──► AES engine decrypts on read
        │
        ▼
   PLAINTEXT in the agent's address space ──► streamed over USB/Wi-Fi to the Mac
```

The agent never touches NAND ciphertext or keys directly; it asks the OS to open files, and the **hardware decrypts them in place** exactly as it would for any app — the agent's privilege just lets it open *everything*. This is why the result is a tree of decrypted files, why it only works at AFU (class A files locked since the last lock won't open), and why the deliverable is "what the live device could read," not "what's on the chip." The taxonomy of agents/exploits that get you there is [[05-full-file-system-acquisition]] and [[07-decrypting-backups-and-images]].

> 🔬 **Forensics note:** This reframes evidentiary integrity. A file-system extraction is **not** a bit-for-bit forensic image of the storage medium — it is a *logical, point-in-time decryption* performed by the subject device. Your hash covers the extracted file set, not the NAND. Document it as such: the medium was never imaged; the device decrypted its own data under your authority at a recorded lock state. Defense experts know the difference, and so should your report.

### The partition / volume picture (briefly)

The NAND, above the firmware and effaceable regions, holds a single **APFS container** with multiple volumes (a sealed read-only **System** volume — the SSV — plus the **Data** volume that holds everything user-generated, plus Preboot/VM/etc.). The split that matters for storage encryption: the **System volume is signed and sealed** (its integrity comes from the SSV hash tree, not from secrecy), while the **Data volume is the one under Data Protection** with the per-file keys above. Older iOS (pre-10.3) used HFS+ with two GPT partitions (a read-only OS partition and a read-write data partition); the migration to APFS in iOS 10.3 brought native per-file encryption integration. The full volume/snapshot/firmlink mechanics are their own lesson — see [[03-apfs-on-ios-volumes]].

> 🔬 **Forensics note:** Over-provisioning and the FTL matter for one more reason: the NAND has **7–28% spare area** the host can never address (reserved for wear-leveling, GC, and bad-block management). Even if encryption *weren't* in the way, a logical image can never reach that spare area — only a controller-level or chip-off read could, and on iOS that read is ciphertext. There is no host-side tool that "sees the whole chip."

### TRIM and GC timing: the window that doesn't help you

When APFS unlinks a file it eventually issues a **TRIM** (NVMe deallocate) telling the controller those logical blocks are free; the controller's **garbage collector** later erases the underlying physical pages so they can be re-programmed (NAND must erase a whole block before rewriting any page in it). Both steps are **asynchronous** — there is a real window after a delete in which the freed ciphertext still physically exists, sometimes in the high-speed **SLC write cache** before it's folded into denser TLC/QLC storage. In ordinary disk forensics that window is your friend; here it is useless three ways: you can't address the freed physical pages (FTL), the bytes are ciphertext (AES), and the moment TRIM/GC completes even the ciphertext is gone. The only thing the timing changes is how long the *database/journal* layer above it keeps recoverable structure — which is where you actually work (see [[14-deleted-data-recovery]]).

### The low NAND: SysCfg, NVRAM, and what survives a wipe

Not all of the NAND is the encrypted APFS container. Lower regions, managed below the filesystem, hold device-provisioning data that is **not** part of the data volume and therefore **survives EACS**:

- **SysCfg** — a factory-written region holding immutable identity: serial number, model/region code, and the **Wi-Fi/Bluetooth MAC addresses**, among other provisioning fields.
- **NVRAM** — the boot environment: `boot-args`, `auto-boot`, the **boot nonce** used in Image4 personalization (see [[02-image4-personalization-shsh]]), and recovery/DFU state.
- The **firmware/boot regions** — LLB/iBoot and the personalized component slots (including the **ANS firmware**), verified by the secure boot chain.

> 🔬 **Forensics note:** A crypto-shred is a *data-volume* event, not a NAND erase. A factory-reset, "empty" iPhone still surfaces its **serial, model, region, and MAC addresses** the instant it boots — readable over USB with `ideviceinfo` the moment it trusts a host, and recoverable from SysCfg even before that. So "the device was wiped" never means "the device is anonymous": identity, IMEI/eSIM provisioning, and activation lineage persist below the encryption boundary. That distinction has closed cases where a wiped device was still tied to an account via its serial.

### A short history (so you can date what you're looking at)

The architecture wasn't always this airtight, and a forensicator dealing with legacy devices needs the timeline — what protection was even *present* changes what's recoverable:

| Era | Storage-crypto state |
|---|---|
| iPhone OS 3 (3GS) | Hardware AES present, but used only for **fast-wipe** (effaceable key) — content was *not* meaningfully protected per-file; physical extraction was productive. |
| iOS 4 | **Data Protection introduced**: per-file keys, class keys, the system keybag, the `BAG1`/`Dkey`/`EMF!` lockers. Protection was opt-in and sparse, so most data was still class-D-ish in practice. |
| iOS 8 | Apple makes **passcode-derived protection the default** for most user data — the "we can't unlock it" turning point (and the FBI/5C dispute). |
| iPhone 5s / iOS 7–8 | **Secure Enclave** arrives: key entanglement, attempt throttling, and the wipe counter move into isolated hardware → NAND mirroring stops working. |
| iOS 10.3 | Filesystem migrates **HFS+ → APFS**, with native per-file (per-extent) encryption integration. |
| A14 / iOS 14+ era | Storage cipher moves to **AES-256-XTS**; the **media key / SEP anti-replay (xART)** supplements the block-0 effaceable locker. |
| A19 / iOS 26 (2026) | Same crypto model; broader memory-integrity hardening (MIE/EMTE) around it. Physical acquisition remains dead; AFU file-system extraction is the high-yield path. |

> 🔬 **Forensics note:** "Which iOS introduced X" is not trivia — it's triage. Faced with a seized device you immediately ask: SoC generation (checkm8-eligible A8–A11 vs. not), iOS version (default-protection era), and lock state (BFU/AFU). Those three answer "what can I even get?" before you touch a tool. The hardware in this lesson sets the ceiling; [[01-the-acquisition-taxonomy]] picks the method under it.

### The barrier stack, in order

Pulling the lesson together: between you and a deleted iOS file sit five independent barriers, and physical acquisition would have to defeat *all* of them. Only the bottom one is even theoretically attackable on modern silicon:

| Barrier | What it blocks | Theoretically attackable? |
|---|---|---|
| **Inline AES-XTS** | NAND contents are ciphertext | No — keys are SEP-held, UID-entangled |
| **FTL abstraction** | host can't address physical pages / slack / spare area | No — mapping lives in signed controller firmware |
| **TRIM + GC** | freed pages erased asynchronously | No — by the time you look they're gone or unreadable |
| **Effaceable crypto-shred / forward security** | wipe/rotation destroys keys irreversibly | No — that's the point of effaceability |
| **SEP key custody + attempt throttling** | no offline brute force; live device required | **Marginally** — only on legacy SoCs (checkm8 A8–A11), and even then it buys SEP-assisted on-device brute force, not raw plaintext |

The practical reading: aim *up* the stack, not at it. The only productive path is to make the **live device decrypt for you** (logical, file-system, or cloud) under proper authority and a recorded lock state — everything in Part 07 is a variation on that single move.

## Hands-on

There is no on-device shell and no way to read the AES engine, the effaceable region, or raw NAND from a Mac — those live behind the SEP and the controller. So the Mac-side work here is in two registers: (1) prove to yourself, on the **Simulator**, that iOS app data is plaintext-on-Mac *because the Simulator has none of this hardware*, and (2) reproduce the **inline-AES + crypto-erase mechanism** with a Mac-side encrypted disk image so the model is concrete. Device-only steps are flagged as walkthroughs.

### Locate a Simulator app's (unencrypted) container

```bash
# Boot a simulator and find an installed app's DATA container on the Mac filesystem
xcrun simctl list devices booted
xcrun simctl get_app_container booted com.apple.mobilesafari data
# → /Users/you/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<APP-UUID>

# Everything under there is plain bytes — no AES engine, no class keys, no effaceable storage.
APP=$(xcrun simctl get_app_container booted com.apple.mobilesafari data)
find "$APP" -name '*.db' -o -name '*.sqlite*' | head
file "$APP"/Library/Safari/*    # plain SQLite, readable directly
```

The contrast is the whole point: on a **real** device those same files are AES-XTS ciphertext keyed by a class key gated on lock state; on the Simulator they're macOS files on your APFS volume.

### Reproduce inline-AES + crypto-erase with an encrypted image

```bash
# Create an AES-256 encrypted APFS image (the Mac's inline-AES analogue of the iOS data volume)
hdiutil create -size 64m -encryption AES-256 -stdinpass \
  -fs APFS -volname CryptoShredDemo /tmp/shred.dmg <<< 'correct horse battery staple'

# Attach, write data, detach
hdiutil attach -stdinpass /tmp/shred.dmg <<< 'correct horse battery staple'
echo "evidence" > /Volumes/CryptoShredDemo/secret.txt
hdiutil detach /Volumes/CryptoShredDemo

# Confirm the image really is encrypted, then prove the ciphertext reveals nothing:
hdiutil isencrypted /tmp/shred.dmg            # → encrypted: YES ... AES-256
strings /tmp/shred.dmg | grep -i evidence     # → no output

# "Crypto-shred": destroy the key wrapper, not the data. Deleting the image (or, on a real
# volume, having the SEP forget the wrapping key) renders every block permanently unreadable
# even though the ciphertext bytes still physically exist until reused.
```

This is a faithful *model* of effaceable crypto-erase, with two honest caveats: a `.dmg` has **one** volume key (no per-file Data Protection classes, no class-key/lock-state coupling), and there is no dedicated hardware effaceable region — the Mac's SEP holds the wrapper for FileVault, and `hdiutil` holds it in the keychain/passphrase here.

### See the ANS firmware as a signed boot component (substrate: an IPSW)

```bash
# The storage controller's firmware ships inside the IPSW and is personalized like any boot image.
# blacktop/ipsw can enumerate the firmware components and the boot manifest (BuildManifest.plist).
ipsw download ipsw --device iPhone18,1 --latest        # iPhone 17 Pro (A19 Pro); or point at an IPSW you already have
ipsw info  iPhone18,1_*.ipsw                            # device, build, board, component list
ipsw fw    iPhone18,1_*.ipsw --list 2>/dev/null | grep -i -E 'ans|nvme|firmware'
# Inspect the personalization manifest to see each component's signed digest:
unzip -p iPhone18,1_*.ipsw BuildManifest.plist | plutil -p - | grep -i -A2 -E 'ANS|StorageBootstrap'
```

You won't decrypt anything here — the point is to *see* that storage firmware is a first-class, signed, version-locked member of the secure boot chain, which is why the host can't substitute its own controller logic.

### Inspect the Data-Protection class hierarchy on a sample image (read-only walkthrough)

```bash
# Against a public iOS reference image (e.g. a Josh Hickman / Digital Corpora full-file-system
# image), forensic tools surface each file's protection class. iLEAPP and commercial suites read
# the class from the wrapped-key metadata. There is no Mac command that decrypts a device image
# offline — decryption happened on the source device at acquisition time; the image you parse is
# already-decrypted output.
```

> ⚠️ **ADVANCED (device-only walkthrough — do not run blind):** On a *cooperative, unlocked* device, `pymobiledevice3` can read NVMe/NAND health and disk-usage diagnostics (e.g. `pymobiledevice3 diagnostics ioregistry` / the `IORegistry` storage nodes, and `ideviceinfo -q com.apple.disk_usage`). These report controller-level health and capacity — **not** keys or plaintext. They are situational-awareness, not acquisition. Running diagnostics against a seized device alters live state; only do so under documented authority with the device already radio-isolated.

## 🧪 Labs

> All labs are device-free. Labs 1–2 use your Mac (Simulator + `hdiutil`); Lab 3 uses a public sample image or a read-only walkthrough. **Fidelity caveat for everything Simulator-based:** the iOS Simulator runs macOS frameworks on your Mac's CPU — there is **no SEP, no inline AES engine, no Data-Protection-at-rest, no effaceable storage, and no ANS controller.** It teaches *structure and the absence of encryption*, never the crypto itself; the crypto is taught from the model in Lab 2 and from sample images in Lab 3.

### Lab 1 — Prove the Simulator has no Data Protection (substrate: CoreSimulator)

1. Boot a Simulator (`xcrun simctl boot "iPhone 17 Pro"` or use one already running) and open Safari/Notes inside it; create a note or visit a page so there's data.
2. Resolve the data container with `xcrun simctl get_app_container booted <bundle-id> data`.
3. Open a SQLite store there directly with `sqlite3` (copy first out of forensic habit) and read a row. It worked with **no key, no unlock, no passcode** — articulate, in one sentence, exactly which four device hardware mechanisms had to be absent for that to be possible.
4. Now state what each of those four would have changed on an A19 device at (a) BFU and (b) AFU.

### Lab 2 — Build and crypto-shred an encrypted volume (substrate: Mac `hdiutil`/`diskutil`)

1. Create the AES-256 encrypted image from the Hands-on section, write a recognizable string into it, detach.
2. Confirm `strings`/`grep` over the raw `.dmg` cannot find your string — you're looking at the Mac analogue of NAND ciphertext.
3. Re-attach with the passphrase, confirm the string is readable, detach again.
4. "Crypto-shred" by discarding the passphrase (or `rm` the image). Write a short paragraph mapping each step to its iOS counterpart: passphrase ↔ effaceable/media key, the `.dmg` ↔ Data volume, "forgot the passphrase" ↔ EACS destroying the effaceable key. Then list the **two ways this model is *less* faithful than the real thing** (single volume key vs. per-file/class keys; software keystore vs. hardware effaceable region + SEP anti-replay).

### Lab 3 — Map the key hierarchy against an acquisition (substrate: read-only walkthrough + sample image)

1. From a public iOS full-file-system reference image, pick any user file (e.g. a Photos asset, an SMS row's attachment).
2. On paper, trace it **bottom-up** through the hierarchy diagram: file contents → per-file key → class key (which class? what lock state would make it available?) → keybag (`BAG1`) → file-system key (`EMF!`) → effaceable/media key.
3. For the same file, answer: would a **BFU** image have yielded it? An **AFU** file-system extraction? A **logical/backup** acquisition? Justify each from the class you assigned in step 2. (Cross-check your reasoning against [[02-bfu-vs-afu-and-data-protection-classes]] and [[05-full-file-system-acquisition]].)
4. State precisely why no chip-off of this device's NAND would have helped, in terms of which key the chip-off does and does not contain.

### Lab 4 — Find the storage firmware in the boot chain (substrate: an IPSW; no device)

1. Acquire an IPSW for any modern device (`ipsw download ipsw --device iPhone18,1 --latest` — iPhone 17 Pro; or use one on disk) and run `ipsw info` on it.
2. Enumerate the firmware components and locate the storage-controller (ANS / NVMe) firmware and its entry in `BuildManifest.plist`.
3. Note that it carries a **signed digest** and a component slot just like iBoot and the kernelcache — write one sentence on why that signing is what prevents a host from loading hostile controller firmware to exfiltrate keys.
4. Bonus: confirm the manifest is **board/ECID-personalizable** (the manifest references the components by digest; personalization binds them per device at install). Tie this back to why a NAND-plus-controller pair can't be driven on a bench. (Full personalization mechanics: [[02-image4-personalization-shsh]].)

### Lab 5 — Model "keys that never leave hardware" (substrate: Mac Secure Enclave via `security`)

The Mac's own SEP gives you a faithful, device-free analogue of the "the key exists only in hardware" property at the heart of this lesson.

1. On your Mac, create a Secure-Enclave-backed key pair (a key whose private half is generated *inside* the SEP and is non-exportable). In code or via the `security` framework, this is a key with `kSecAttrTokenID = kSecAttrTokenIDSecureEnclave`. Generate one, then attempt to export the private key.
2. Observe that export **fails** — the API can sign/decrypt *with* the key but cannot hand you its bytes. Write one sentence mapping this to the iPhone's hardware UID and class keys: you can ask the engine to operate with the key, never to reveal it.
3. Now contrast with a software keychain item (no SEP token): you *can* extract its secret with the right entitlement/unlock. Articulate why the iOS data-volume keys behave like (1), not (3), and what that means for "extract the keys then decrypt offline."
4. Fidelity caveat: the Mac SEP models *non-exportability and on-hardware operation* faithfully, but not the per-file/class-key/effaceable hierarchy — those are iOS Data Protection constructs with no Mac equivalent.

## Pitfalls & gotchas

- **"Encrypted at rest" ≠ "encrypted right now."** The NAND is always ciphertext, but at AFU the class C key is resident in the SEP and the live OS can read class-C files transparently — which is why an AFU file-system extraction returns plaintext. Don't conflate *ciphertext on the chip* with *inaccessible to a live, unlocked device.* The acquisition envelope is defined by lock state, not by "is it encrypted."
- **Effaceable Storage is not "free space" and not carve-able.** It's a controller-managed special region of a few hundred bytes, not part of the addressable APFS container. You will never see `BAG1`/`Dkey`/`EMF!` in a logical or even file-system image — they're below that layer, inside the SEP/controller domain.
- **Don't promise physical recovery of deleted iOS files.** The instinct from disk forensics — "deleted ≠ gone, carve the unallocated" — is wrong here three times (encryption, FTL remapping, TRIM/GC). Set expectations at the SQLite/snapshot layer instead, or you'll over-promise in a report.
- **EACS and remote wipe are instantaneous and irreversible.** There's no mid-erase window to interrupt. Treat any networked, un-isolated seized device as one remote-wipe command away from a destroyed case. Airplane mode is *not* isolation — Faraday it.
- **The per-SoC cipher table changes.** AES-128-XTS on A9–A13, AES-256-XTS on A14+. Don't state a width without checking the device generation, and re-verify the device enumeration against the current *Apple Platform Security* edition (A19 follows the A14+ path, but the guide's printed list lags new silicon).
- **The Simulator will lie to you about security by omission.** Because Simulator data is plaintext-on-Mac, it's perfect for schema/layout work and useless — actively misleading — for any claim about encryption, lock state, or effaceability. Never demonstrate a "Data Protection" behavior on the Simulator; it has none.
- **"NVMe" labels mislead.** Recent Apple storage modules look like M.2 NVMe SSDs but are **raw NAND with no onboard controller** — the controller is the SoC's ANS. You can't drop one into a PC NVMe reader; commercial tooling that claims to has been wrong (see Elcomsoft's 2026 teardown).
- **A wipe is not anonymization.** EACS/remote-wipe destroys the *data volume's* key but leaves SysCfg/NVRAM intact. A "blank" device still yields serial, model, region, MAC addresses, and activation lineage — don't record a seized wiped phone as identity-less.
- **Rooting the kernel ≠ having the keys.** A kernel-level exploit can read *currently-unlocked* files via the storage engine, but the class keys and UID stay in the SEP. There is no "dump the keys, decrypt the image later" on SEP devices; plan acquisitions around live, unlocked decryption, not offline key recovery.

## Key takeaways

- iOS storage encryption is **inline hardware AES-XTS on the DMA path** between the ANS controller and main memory; data on NAND is **always ciphertext**, and the keys are released only by the **Secure Enclave** over a channel the application processor never sees.
- Apple keys it **per file** (256-bit per-file key) under a small set of **class keys** under the **file-system/metadata key** — a hierarchy whose availability is gated by **lock state**, which is the hardware root of BFU vs. AFU.
- The cipher is **AES-128-XTS on A9–A13** and **AES-256-XTS on A14+** (A19 included); the per-file key is split (older) or KDF-derived (SP 800-108, newer) into the cipher key + XTS tweak.
- **Effaceable Storage** is a tiny dedicated NAND region (historically block 0, ~960 bytes, lockers `BAG1`/`Dkey`/`EMF!`) holding the wrapping keys; newer devices also/instead use a **SEP anti-replay media key (xART)**.
- **Erase All Content and Settings / remote wipe = crypto-shred**: destroy a few hundred bytes of effaceable key and the entire volume is instantly, irreversibly ciphertext — no overwriting, milliseconds not hours.
- Crypto-shred exists *because* flash **wear-leveling makes overwrite-based secure-delete impossible**; the FTL remaps writes, so you destroy the key, not the data.
- **Physical (chip-off / NAND-mirroring) acquisition is dead on SEP devices** (5s+): a perfect NAND clone is AES ciphertext with no key. The 5C mirroring attack worked only because it had no SEP. Modern acquisition is logical / file-system / cloud, never bit-for-bit physical.
- **Deleted-data recovery moves up the stack** to SQLite/journal/snapshot artifacts; physical-page carving on iOS NAND is defeated by encryption + FTL + TRIM together.

## Terms introduced

| Term | Definition |
|---|---|
| NAND flash | The raw non-volatile storage medium in an iPhone; soldered/raw packages with no onboard controller, driven by the SoC's ANS. |
| ANS (Apple NAND Storage) | Apple's in-SoC, NVMe-class storage controller running its own firmware and flash-translation layer; the "drive" XNU talks to. |
| Inline AES engine | The hardware AES-XTS block on the DMA path between the storage controller and main memory; encrypts/decrypts at line speed, keyed only by the SEP. |
| AES-XTS | Tweakable, storage-oriented AES mode used for both iOS file content and macOS FileVault; encrypts each sector independently. |
| Per-file key | A fresh 256-bit key generated per file, used by the AES engine and wrapped by a class key stored in the file's metadata. |
| Class key | One of the Data Protection class keys (A/B/C/D) that wraps per-file keys; availability is gated by device lock state. |
| File-system key / EMF key | The metadata (volume) key encrypting file metadata; itself wrapped by the effaceable/media key. Regenerated on EACS. |
| Effaceable Storage | A small dedicated NAND region (historically block 0, ~960 bytes) holding directly-addressable, securely-erasable key lockers. |
| `BAG1` / `Dkey` / `EMF!` | The three canonical effaceable lockers: system-keybag wrapping key+IV; class-D (`NSFileProtectionNone`) master key; file-system master key. |
| Media key / xART | The SEP-anti-replay-protected key that wraps the file-system key on newer devices, supplementing/replacing the block-0 effaceable locker. |
| Crypto-shred (EACS) | Instant, irreversible wipe achieved by destroying the effaceable/media key so all data becomes undecryptable ciphertext; "Erase All Content and Settings." |
| FTL (flash-translation layer) | Controller firmware that remaps logical blocks to physical NAND pages for wear-leveling, GC, and bad-block management; hides physical layout from the host. |
| Over-provisioning | Hidden spare NAND capacity (≈7–28%) reserved for the FTL; never host-addressable. |
| TRIM | The hint APFS sends the controller marking blocks free, enabling GC to erase them — defeating physical deleted-file carving. |
| Chip-off / NAND mirroring | Desoldering and cloning the NAND for physical acquisition; on SEP devices it yields only AES ciphertext (Skorobogatov's iPhone 5C work is the canonical case). |
| Hardware UID | A 256-bit per-device key fused into the SEP/AES engine at manufacture, never software-readable; entangled with the passcode so brute force is only possible on the original device. |
| Hardware GID | A key shared across all devices of a given SoC, used to decrypt firmware (not user data); the per-SoC counterpart to the per-device UID. |
| XTS tweak | The position-derived second key in AES-XTS; makes identical plaintext in different sectors encrypt differently, defeating copy-and-paste/watermark attacks on block storage. |
| Per-extent key | A Data Protection key scoped to an APFS extent rather than a whole file; cloned (copy-on-write) files share extents and thus keys until a write diverges. |
| ANS firmware | The storage controller's firmware, shipped as a signed, personalized Image4 component in the IPSW and verified in the secure boot chain; runs the FTL inside the controller. |
| SysCfg | A factory-provisioned NAND region holding immutable device identity (serial, model/region, Wi-Fi/BT MAC addresses); below the data volume, so it survives EACS. |
| NVRAM | The boot environment region (`boot-args`, `auto-boot`, the boot nonce, DFU/recovery state); persists across a data-volume wipe. |
| SLC cache | A fast single-level-cell write buffer the controller folds into denser TLC/QLC storage later; part of why freed ciphertext lingers briefly post-delete. |
| Crypto-shred window | The asynchronous gap after delete (TRIM/GC pending) in which freed ciphertext physically persists but remains unaddressable and undecryptable. |

## Further reading

- **Apple** — *Apple Platform Security* guide (current edition): "Encryption and Data Protection," "Data Protection," "Data Protection classes," and "The Secure Enclave" sections — the AES-engine/DMA-path, per-file-key, effaceable-storage, and media-key language quoted here.
- **theapplewiki.com / theiphonewiki.com** — "File System Crypto": the `BAG1`/`Dkey`/`EMF!` lockers, block-0 effaceable storage, and the keybag/class-key hierarchy.
- **Jonathan Levin**, *MacOS and iOS Internals* (newosxbook.com) — ANS, the storage stack, and the SEP key channel at the implementation level.
- **Andrey Belenko & Dmitry Sklyarov** — "Evolution of iOS Data Protection and iPhone Forensics" (Black Hat) — the foundational dissection of the effaceable lockers and class-key hierarchy.
- **Sergei Skorobogatov** — "The bumpy road towards iPhone 5C NAND mirroring" (arXiv 1609.04327) — why physical attacks worked pre-SEP and don't after.
- **Elcomsoft blog** — "Perfect Acquisition" series and the 2026 "Looks Can Lie: Is That Really an NVMe Drive?" teardown of Apple's raw-NAND modules.
- **OWASP MASTG** — iOS data-storage / cryptography test cases, for the developer-side view of Data Protection classes.
- **"SoK: Untangling File-based Encryption on Mobile Devices"** (arXiv 2111.12456) — a rigorous comparison of iOS Data Protection and Android FBE; good for placing Apple's design against the field.
- **Alexis Brignoni**, iLEAPP (github.com/abrignoni/iLEAPP) — how a parser surfaces per-file protection classes and acquisition output; the practitioner counterpart to this hardware view.
- **Elcomsoft** — "Perfect Acquisition" series and iOS Forensic Toolkit docs — the commercial-acquisition view of AFU file-system extraction and what the SEP will and won't release.
- `man hdiutil`, `man diskutil`, `xcrun simctl help` — the Mac-side commands used in the labs.

---
*Related lessons: [[02-secure-enclave-hardware]] | [[01-sep-sepos-deep-dive]] | [[02-data-protection-and-keybags]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[05-full-file-system-acquisition]] | [[14-deleted-data-recovery]]*
