---
title: "Data Protection & the keybags"
part: "03 — Security Architecture"
lesson: 02
est_time: "55 min read + 25 min labs"
prerequisites: [sep-sepos-deep-dive, storage-nand-aes-effaceable]
tags: [ios, data-protection, keybag, encryption, forensics, dfir]
last_reviewed: 2026-06-26
---

# Data Protection & the keybags

> **In one sentence:** every file on an iPhone is sealed by its own random AES key, that key is wrapped by a *class* key, the class keys live in a *keybag*, and the keybag's master key is reconstructed only by entangling the user's passcode with a non-extractable hardware UID inside the SEP — so "the volume is unlocked" never means "everything is readable," and exactly *which* class keys are resident in the keystore at acquisition time is what decides what a forensic examiner can and cannot decrypt.

## Why this matters

On macOS your reflex is correct: one FileVault volume key, one unlock, and the whole Data volume is transparently readable until you log out. **That reflex is wrong on iOS, and acting on it will make you draw false conclusions about an extraction.** iOS encrypts at *file* granularity with a four-class lock-state model that the macOS course never had to teach you, because the whole point is that an attacker (or examiner) holding the powered-on-but-locked device can read some files and provably *cannot* read others — even with kernel code execution. The entire BFU-vs-AFU distinction that governs every modern iOS acquisition (Cellebrite, GrayKey, `checkm8`/`usbliter8` workflows, `pymobiledevice3`) is a direct consequence of which class keys are sitting unwrapped in the Secure Enclave's keystore at the moment you seize the phone. If you don't have the class table memorized you will mis-scope an acquisition, misread a "we got the filesystem but the databases are empty/garbage" result as a tooling bug, and misstate in a report what the evidence could possibly contain.

For the builder hat this matters too: when you ship an app and choose (or default into) a Data Protection class, you are deciding when your users' data is readable, when a background task can touch it, and whether it survives onto a backup — and you are deciding what a forensic examiner can recover from a seized device. The two hats see the same mechanism from opposite ends. This lesson is the mechanism end-to-end, and the class table you must know cold.

## Concepts

### The four-layer key hierarchy

Data Protection is a key-wrapping tree. Read it bottom-up — every layer wraps the one below it:

```
passcode  ──entangle w/ SEP UID (on-SEP, ~80ms/try)──▶  passcode key
                                                          │
hardware UID (fused, never leaves SEP) ──────────────────┤
                                                          ▼
                                              ┌──────────────────────┐
                                              │   KEYBAG  (a TLV blob)│
                                              │  holds the CLASS KEYS │
                                              │  A · B · C · D · …    │
                                              └───────────┬──────────┘
                                  class key (A/C/D symmetric, B asymmetric)
                                                          ▼
                              per-file key (random 256-bit, made by SEP at create)
                                  wrapped by class key via AES-KW (RFC 3394)
                                  stored in the file's cprotect record
                                                          ▼
                              file CONTENT on NAND, encrypted AES-XTS-256
                                  by the inline hardware AES engine
```

Four facts make this hierarchy do its job:

1. **Per-file keys.** When a file is created, the SEP generates a fresh random 256-bit key. The storage path's **inline AES engine** (the DMA-path crypto block you met in [[03-storage-nand-aes-effaceable]]) encrypts the file's *content* on the way to NAND with that key — historically AES-CBC with a per-block IV derived from the block offset, AES-XTS-256 on modern hardware (verify the exact mode against the Apple Platform Security edition for your target SoC). The plaintext key never has to touch the Application Processor: for hardware-keyed extents the SEP hands the key straight to the AES engine.
2. **Class keys wrap per-file keys.** The per-file key is itself encrypted ("wrapped") with a **class key** using **NIST AES Key Wrap, RFC 3394** (the `AES.KeyWrap` primitive Apple also exposes in CryptoKit). The wrapped per-file key is stored *next to the file's metadata* (the cprotect record, below). There are a small number of class keys; there is one per-file key per file (or per *extent* — APFS can key sub-ranges of a file independently).
3. **The keybag holds the class keys.** All the class keys live together in a **keybag** — a tagged binary blob. The class keys are themselves wrapped (symmetric classes by the keybag key + passcode key; the asymmetric class differently — see below).
4. **The keybag's keys derive from passcode ⊗ UID.** The master material that unwraps the passcode-protected class keys is the **passcode key**: the user's passcode *entangled* with the device's hardware **UID** inside the SEP, through an iterative KDF calibrated so one guess costs ~80 ms. Because the UID is fused into the SEP and is never software-readable, the entanglement *must* run on that specific device — you cannot lift the keybag onto a GPU cluster and brute-force it offline.

That last point is the whole ballgame. Crack the layering and you understand why a `checkm8`/`usbliter8` BootROM exploit — code execution *below* the signature checks — still does **not** hand you the user's data: it gets you onto the device, but the class keys are gated by the SEP and the passcode, and the SEP enforces the guess-rate and the 10-try-wipe counter. You still need lock state or the passcode.

> 🖥️ **macOS contrast:** FileVault on Apple Silicon is a *single* Volume Encryption Key (VEK) for the whole Data volume, wrapped by a Key Encryption Key derived from your login password and the SEP. One successful unlock at the login window (or a recovery key) and the *entire* volume decrypts transparently for the rest of the session — "unlocked = everything readable" is literally true. iOS replaces that one-key/one-unlock model with per-file keys + four class keys + lock-state gating. The same NSFileProtection machinery technically *exists* on Apple Silicon macOS (apps can set `NSFileProtectionComplete`), but FileVault's volume-key model dominates, so the muscle memory you built in macos-mastery does not transfer. Bring the new model, not the old reflex.

Side by side:

| | macOS (FileVault, Apple Silicon) | iOS (Data Protection) |
|---|---|---|
| Encryption granularity | One **volume** key (VEK) | One key **per file** (or per extent) |
| Number of "classes" | None — one key, one policy | **Four** file classes (A/B/C/D) + keychain classes |
| Unlock event | Login (or recovery key) — once | Boot → first unlock → per-screen-lock transitions |
| After unlock | Whole volume readable until logout | Only the classes whose keys are resident; A goes dark on lock |
| "Locked but powered on" | Volume key resident → readable | Depends on BFU vs AFU and the file's class |
| Where wrapped keys live | VEK record in the volume's crypto state | `wrapped_crypto_state_t` per file + the keybag |
| Reboot effect | Re-prompt for password | AFU→BFU; evicts A/B/C keys |

### The four NSFileProtection classes — and exactly when each key is available

This is the table to memorize. Each *file* is tagged with one **Data Protection class**; the class decides which class key wraps its per-file key, and therefore in which **lock states** the file can be decrypted.

| Class | API constant | Wrapping of the class key | BFU (before 1st unlock) | AFU, currently **locked** | Unlocked | Typical contents |
|---|---|---|---|---|---|---|
| **A** | `NSFileProtectionComplete` | symmetric class-A key; **evicted from the keystore the moment the device locks** | ✗ | ✗ | ✓ | High-sensitivity app data that *should* go dark on lock |
| **B** | `NSFileProtectionCompleteUnlessOpen` | **asymmetric** (Curve25519); per-file key wrapped via ECDH to the class-B **public** key (always available) — needs the class-B **private** key (in keystore only while unlocked) to *read* | ✗ for *new* opens; **already-open handles keep working** | ✗ for new opens; open handles persist | ✓ | Files written by background tasks while locked (e.g. a Mail attachment finishing its download) |
| **C** | `NSFileProtectionCompleteUntilFirstUserAuthentication` **(THE DEFAULT)** | symmetric class-C key; **loaded at first unlock and kept resident until shutdown/reboot** | ✗ | ✓ | ✓ | Almost everything — this is the default for files with no explicit class set |
| **D** | `NSFileProtectionNone` | symmetric class-D key derived from the **UID only — no passcode** | ✓ | ✓ | ✓ | Data that must be reachable with the device merely powered on |

How to read the asymmetry that trips people up:

- **Class A** is the strictest: its key is in the keystore *only while the screen is unlocked*. Lock the device and the class-A key is wiped from SEP memory; class-A files are unreadable a second later, even though the device is still powered on.
- **Class B (`CompleteUnlessOpen`)** is the clever one. Wrapping needs only the **public** key, which is always present — so a background process *can create and append to* a class-B file while the device is locked. Reading needs the **private** key, present only while unlocked. So: a download daemon writes the attachment while you're locked; once the handle closes, no new process can open it until you unlock. (Mechanically: at create, the SEP makes the per-file key, generates an ephemeral Curve25519 keypair, does ECDH between the ephemeral private and the class-B public key to derive a wrapping secret, stores the *ephemeral public* in the cprotect, and discards the ephemeral private. To unwrap later it redoes ECDH with the class-B *private* key.)
- **Class C** is what you will see on the overwhelming majority of files, because it is the **default** when an app doesn't set a class. Its key is unwrapped at the *first* passcode entry after boot and then **stays resident until the device powers off or reboots**. This single fact is why **AFU acquisition gets almost everything** and **BFU gets almost nothing**.
- **Class D** has no passcode dependence at all — its key comes from the UID alone — so class-D files are readable from the moment the device boots, before any unlock. Note the subtlety: class D is *not* "unencrypted." The content is still AES-encrypted under a per-file key wrapped by the class-D key; it's just that the class-D key needs no passcode. A device **wipe** still destroys class-D data instantly, because the *wrapping* of the class-D key (the `DKey` locker) lives in **Effaceable Storage**, and erasing that block is the crypto-shred (see [[03-storage-nand-aes-effaceable]]).

> 🔬 **Forensics note:** The default being **Class C** is the most consequential single fact in iOS forensics. `knowledgeC`/Biome, `sms.db`, `CallHistory.storedata`, the Photos `Photos.sqlite`, most third-party app SQLite — all land in Class C unless the developer opted up to A. So an **AFU** extraction (phone was unlocked at least once since boot, e.g. seized powered-on and unlocked, or kept alive after seizure) decrypts essentially the full user dataset, while a **BFU** extraction (rebooted, or never unlocked since power-on) yields only Class D plus whatever survives unkeyed — the timestamps and a lot of structure but not the message bodies. *Lock state at seizure is an evidence-defining variable; record it like you record a hash.*

> ⚖️ **Authorization:** Lock state is also a chain-of-custody issue, not just a technical one. Keeping a seized device **alive and AFU** (Faraday bag, power, no reboot) versus letting it hit the **72-hour inactivity reboot** (iOS 18.1+) that drops it to **BFU** is a deliberate evidentiary decision with legal weight — and forcing or preventing an unlock may exceed the authority in your warrant. Decide it under counsel, document the device's power/lock state at every transfer, and never present "we couldn't read the messages" as a tool limitation when it was a BFU/AFU handling outcome.

### Keychain Data Protection classes (the parallel set)

The keybag also holds the **keychain** class keys — the same idea applied to Keychain items rather than files. The constants you'll see on items:

| Keychain accessibility | Maps to | Available |
|---|---|---|
| `kSecAttrAccessibleWhenUnlocked` | Class A | only while unlocked |
| `kSecAttrAccessibleAfterFirstUnlock` | Class C | AFU until shutdown |
| `kSecAttrAccessibleAlways` (deprecated) | Class D | always (BFU) |
| `…WhenPasscodeSetThisDeviceOnly` | Class A, **non-migratory** (UID-bound) | unlocked, never leaves device |
| `…ThisDeviceOnly` variants | UID-bound | non-migratory — excluded from backups/restore |

The `ThisDeviceOnly` items are wrapped with the UID so they cannot ride a backup to another device — which is exactly why a restored iPhone re-prompts for Wi-Fi passwords and some tokens. Full keychain mechanics are in [[08-keychain-on-ios]]; here, just know the keybag is the shared vault for *both* file class keys and keychain class keys.

Where keychain items physically live matters for the same BFU/AFU reason files do. The keychain is a single SQLite database at **`/private/var/Keychains/keychain-2.db`** with four item tables — **`genp`** (generic passwords), **`inet`** (internet passwords), **`cert`** (certificates), **`keys`** (keys) — plus access-group tables. In each row the **`data`** BLOB is the item's secret, **wrapped by its keychain class key** (so it's ciphertext at rest exactly like a per-file key); the surrounding metadata columns — `svce`/`acct` (service/account), `agrp` (access group / `keychain-access-groups`), `cdat`/`mdat` (creation/modification dates), and crucially **`pdmn`** (the *protection domain* = the keychain protection class) — are stored in the clear. So a BFU dump of `keychain-2.db` hands you the *structure and metadata* of every credential (which services, which app groups, when created) while the `data` BLOBs for class-A/C items stay sealed until you have the resident class key.

> 🔬 **Forensics note:** Read `pdmn` directly to triage the keychain without any key: `ak`/`ck`/`dk` (and the `*ThisDeviceOnly` variants `aku`/`cku`/`dku` plus the passcode-set `akpu`) encode the protection class — `dk` (class D, `Always`) items are recoverable in **BFU**, `ck` (class C, `AfterFirstUnlock`) items in **AFU**, `ak` (class A, `WhenUnlocked`) only while unlocked. The presence of a high-value credential under `ck` tells you an AFU acquisition will surrender it; under `akpu` (`WhenPasscodeSetThisDeviceOnly`) tells you it will *not* migrate to a backup and is bound to this exact device.

### The cprotect record — where each file's wrapped key lives on disk

On **APFS** (every modern iOS device), a file's wrapped per-file key is not an extended attribute the way it was on legacy HFS+ — it's a first-class filesystem object. The crypto state is a `j_crypto_val_t` record stored in the volume's file-system B-tree under a `j_crypto_key_t` with object type `APFS_TYPE_CRYPTO_STATE`, and the inode/extent point at it:

- **`j_inode_val_t.default_protection_class`** — the class a *new* file inherits from its directory (directories carry a default class; new files born inside inherit it unless the app sets one explicitly).
- **`j_file_extent_val_t.crypto_id`** — each file *extent* references a crypto-state object, which is what lets APFS use **per-extent** keys (different byte ranges of one file under different keys).
- **`j_crypto_val_t`** = `{ refcnt; wrapped_crypto_state_t state; }` — the crypto-state object the above point to.

The payload, `wrapped_crypto_state_t`, is the structure to know cold (field names and types confirmed against Joe Sylve's APFS work and `libfsapfs`):

```c
struct wrapped_crypto_state {
    uint16_t  major_version;     // crypto-state format major
    uint16_t  minor_version;     // crypto-state format minor
    uint32_t  cpflags;           // content-protection flags
    uint32_t  persistent_class;  // ← the Data Protection class (1=A,2=B,3=C,4=D,…)
    uint32_t  key_os_version;    // OS version that wrote the key (provenance!)
    uint16_t  key_revision;      // key rotation/revision counter
    uint16_t  key_len;           // length of persistent_key (bytes)
    uint8_t   persistent_key[];  // ← the RFC 3394 AES-KW-wrapped per-file key
} __attribute__((packed));
```

Two columns are forensic gold even when you *cannot* decrypt:

- **`persistent_class`** tells you the file's Data Protection class directly from the metadata — i.e. it tells you *whether* a given file is even theoretically recoverable in your current lock state, before you've unwrapped a single byte. The canonical numeric mapping is `1=A, 2=B, 3=C (default), 4=D`; the spec also defines `6=F` (`PROTECTION_CLASS_F` — key wrapped but not passcode-gated, for files that must be wiped on erase yet need no unlock) and `14=M` (`PROTECTION_CLASS_M`) on newer systems. **Value `5` is undefined/reserved for a file — it is *not* Class F** (Sylve: "class 5 is undefined"; the Apple File System Reference puts `PROTECTION_CLASS_F` at `6`). Treat `6/F` and `14/M` as *verify-against-`apfs.h`-for-your-target* values.
- **`key_os_version`** records the OS build that generated the key — a provenance breadcrumb that can corroborate when a file was created or last re-keyed.

On legacy **HFS+** iOS (≤ iOS 10.x devices), this same wrapped key was carried in the **`com.apple.system.cprotect`** extended attribute — hence the community name "cprotect," which still gets used generically for "the per-file wrapped-key record" regardless of filesystem. If you ever touch an old HFS+ image you'll see the literal xattr; on APFS you'll see the `j_crypto_val_t` record.

> 🔬 **Forensics note:** `libfsapfs` (`fsapfsinfo`/`fsapfsmount`, Joachim Metz) exposes the `wrapped_crypto_state_t` per file and will decrypt extents when you supply the unwrapped volume/class keys; without keys it still dumps `persistent_class` so you can *triage* which files are Class D (readable in BFU) versus Class A/C (need keys). That triage — running the class histogram across a filesystem image before you ever try to decrypt — tells you immediately whether a BFU image is worth carving or whether you must escalate to an AFU/keyed acquisition.

### The keybag types — and what each re-wraps

A keybag is a TLV (tag-length-value) blob. There are several *types*, and the type determines who can open it and what the class keys are re-wrapped for. Apple's current Platform Security guide uses the names **user, device, backup, escrow, iCloud Backup**; older Apple editions and the classic research literature (Sogeti / `iphone-dataprotection`) used **system, backup, escrow, iCloud, OTA**. They describe the same machinery — here's the reconciled map:

| Keybag (modern Apple name) | Older name | On-disk `TYPE` | What it holds / re-wraps for | Protected by |
|---|---|---|---|---|
| **User** | (part of) System | `0` | The live class keys used in normal operation; unwrapped by the passcode key at unlock | A9+: an **anti-replay locker inside the SEP**; pre-A9: a key in **Effaceable Storage** (`BAG1`) |
| **Device** | (part of) System | `0` | Per-file class keys for *system*/shared data with no per-user crypto separation (file DP uses device-keybag keys; keychain uses user-keybag keys). On Shared iPad it can be unprotected to allow pre-auth access | Same as user keybag on single-user devices |
| **Backup** | Backup | `1` | A **freshly generated** set of class keys, re-wrapping every backed-up item so the backup is portable to another device — *except* `ThisDeviceOnly`/UID-bound items, which stay UID-wrapped and don't migrate | The backup password, run through **PBKDF2 with 10,000,000 iterations** (this is why a strong backup password matters — see [[03-the-itunes-finder-backup-format]]) |
| **Escrow** | Escrow | `2` | The same class keys as the device keybag, so a trusted host can sync/back-up **without re-entering the passcode**; the secret is **split between device and host** | A host-held escrow record; device-side data stored in **Class C** (Protected Until First User Authentication) |
| **iCloud Backup** | iCloud / OTA | `3` | Class keys re-wrapped as **asymmetric Curve25519** keys (same primitive as Class B) so iCloud can ingest backup data without ever holding a symmetric secret | Apple's iCloud key hierarchy; **ADP changes this materially** — see below |

The **escrow keybag** is the mechanism behind "trust this computer": when a passcode-locked device first connects to Finder/iTunes, it mints an escrow keybag containing its class keys, protected by a key handed to the host. That's why a paired host can take a full backup later without the passcode — and why a **lockdown/pairing record** lifted from a trusted Mac is itself an acquisition asset (covered in [[04-logical-acquisition-with-libimobiledevice]] and [[03-the-itunes-finder-backup-format]]).

The **OTA path** (Apple now folds it into the escrow mechanism): when you start an over-the-air update, you're prompted for the passcode *up front* to mint a **one-time unlock token** that re-unlocks the user keybag *after* the reboot, so the update can finish without you standing there to re-enter it. That token is itself protected by SEP anti-replay state (A9+) so it can't be replayed.

> 🖥️ **macOS contrast:** macOS has nothing resembling this keybag taxonomy because it has no per-class key set to re-wrap. The closest analogues are narrow and unrelated: a FileVault **institutional/personal recovery key** and the **iCloud recovery escrow** play the "alternative way to unwrap the volume key" role of an escrow keybag, but there is no macOS "backup keybag" (Time Machine encrypts with its own destination key, not a re-wrapped per-class set) and no "OTA one-time unlock token" (a macOS update re-prompts at the login window). The whole idea of *several* keybags each re-wrapping the *same* class keys for a different consumer is iOS-specific — it exists only because iOS split encryption into classes in the first place.

> 🔬 **Forensics note:** The **iCloud Backup keybag's Curve25519 asymmetry** is precisely why **Advanced Data Protection (ADP)** breaks cloud acquisition. With ADP on, the keys that would let Apple (and therefore a legal-process iCloud return, or Elcomsoft-style cloud extraction) decrypt the backup are moved end-to-end to the user's devices; Apple no longer holds a decryptable copy. Pre-ADP, the iCloud keybag's class keys were recoverable through Apple's hierarchy; with ADP they are not. So "is ADP enabled?" is a yes/no that decides whether iCloud is even a viable acquisition avenue — detail in [[06-icloud-acquisition-and-advanced-data-protection]].

### The keybag TLV format and the WRAP flag (the BFU/AFU encoder on disk)

If you parse a raw keybag (e.g. `/private/var/keybags/systembag.kb` from a full-filesystem image), it's a flat sequence of 4-character tags. The header tags and the per-key records:

| Tag | Meaning |
|---|---|
| `VERS` | keybag format version |
| `TYPE` | keybag type — `0` system/user · `1` backup · `2` escrow · `3` OTA/iCloud |
| `UUID` | keybag UUID |
| `HMCK` | wrapped HMAC key (integrity over the keybag) |
| `SALT` | PBKDF2 salt (passcode-derived keybags) |
| `ITER` | PBKDF2 iteration count (e.g. 10,000,000 for backup) |
| `WRAP` | default wrap policy |
| — per class key, repeating — | |
| `UUID` | this class key's UUID |
| `CLAS` | class number (1–11: file classes 1–4, keychain classes 6–11) |
| `WRAP` | **wrap flags** — `1` = device key (`0x835`/UID) only · `2` = passcode key only · `3` = **both** |
| `KTYP` | key type — `0` = AES symmetric · `1` = Curve25519 (asymmetric, Class B / iCloud) |
| `WPKY` | the wrapped class key |
| `PBKY` | public key (present for asymmetric/Class B entries) |

The single most important field for an examiner is **`WRAP`** per class:

- `WRAP = 1` (device/UID only) → that class key needs **no passcode** → **available in BFU**. This is Class D.
- `WRAP = 2` or `3` (passcode involved) → needs the passcode key → **unavailable until first unlock**. Classes A/B/C.

So the keybag *on disk encodes the BFU/AFU table directly.* Parse the keybag, read each `CLAS`+`WRAP`, and you can state — from the bytes — which classes a powered-on-but-not-yet-unlocked device will surrender. (`0x835` is the historical name for the device key the SEP derives from the UID to wrap the device-only class keys.)

### The AKS / AppleKeyStore unlock flow

The runtime plumbing that turns a typed passcode into resident class keys:

```
SpringBoard / lockscreen
        │  passcode
        ▼
MobileKeyBag.framework (userspace)  ──▶  AppleKeyStore.kext (kernel)
                                                │  mailbox to SEP
                                                ▼
                                  ┌────────────── SEP (sks keystore) ──────────────┐
                                  │ 1. entangle passcode ⊗ UID  (~80ms/try)         │
                                  │    → passcode key   [enforces try-counter,      │
                                  │      escalating delays, 10-try wipe if set]     │
                                  │ 2. passcode key + keybag key  ──unwrap──▶        │
                                  │    Class A / B / C keys                          │
                                  │ 3. load class keys into the keystore;            │
                                  │    AppleKeyStore now reports state = UNLOCKED    │
                                  └─────────────────────────────────────────────────┘
                                                │
   APFS opens a file ──reads wrapped_crypto_state_t──▶ asks AppleKeyStore to unwrap
   the per-file key with persistent_class's key ──▶ SEP returns key to inline AES engine
                                                │
   on LOCK:  SEP evicts Class A key (+ Class B private);  Class C stays until reboot
```

The kernel side is `AppleKeyStore.kext`; userspace talks to it via `MobileKeyBag.framework`/`libMobileKeyBag` (and `keybagd`). Crucially, **the keys are unwrapped and held inside the SEP's keystore, not in AP-accessible kernel memory** for hardware-keyed paths — which is why dumping AP kernel memory does not simply hand you the class keys, and why SEP exploitation (a separate, much harder target than a `checkm8`/`usbliter8` AP BootROM bug) is what real high-end acquisition against locked modern devices actually turns on.

Three lock-state transitions matter, and they are *not* symmetric:

- **Boot → BFU.** After power-on, before any passcode, the keystore holds only the UID-derived material. Class A/B/C keys are wrapped and absent. `AppleKeyStore` reports the device as never-unlocked.
- **First unlock → AFU.** The first correct passcode entry runs the entanglement, unwraps A/B/C, and loads them. Class C is now resident **and stays resident across subsequent screen locks** — that residency is the entire reason AFU acquisition is productive.
- **Lock (while AFU).** Locking the screen evicts the **Class A** key and the **Class B private** key from the keystore. It does **not** evict Class C. So "locked" after first unlock is a *different* security state than "locked" before first unlock (BFU) — same screen, radically different readable set. The only events that drop Class C are **shutdown, reboot, and the inactivity reboot.**

This is why "did the screen lock?" is the wrong question at a scene. The right questions are "has it been unlocked since it last booted?" (BFU vs AFU) and "is it about to reboot from inactivity?" (AFU→BFU countdown). As a state machine:

```
                 power on
                    │
                    ▼
            ┌───────────────┐   first correct passcode   ┌───────────────┐
            │     BFU       │ ─────────────────────────▶ │   AFU/UNLOCKED │
            │ (never        │                            │ A,B,C,D all    │
            │  unlocked)    │                            │ resident       │
            │ only D + UID  │                            └───────┬───────┘
            └───────────────┘                       lock screen  │  ▲ unlock
                    ▲                                            ▼  │
                    │  shutdown / reboot /              ┌────────────────┐
                    │  72h inactivity reboot            │  AFU/LOCKED    │
                    └───────────────────────────────────│ C,D resident;  │
                       (evicts C — drops to BFU)        │ A evicted,     │
                                                        │ B priv evicted │
                                                        └────────────────┘
```

The arrow that ruins acquisitions is the one back to BFU: shutdown, a deliberate reboot, **or** the 72-hour inactivity timer firing on a device you seized AFU and left idle.

### Effaceable storage, the `DKey`, and the wipe path

Data Protection's "instant wipe" is not an overwrite — it's a **crypto-shred**, and it depends on a tiny block of **Effaceable Storage** you met in [[03-storage-nand-aes-effaceable]]. Effaceable Storage is a small region of NAND addressable directly (bypassing the FTL's wear-leveling/remapping) so it can be *actually* erased on command, not just logically unlinked. It holds a handful of named lockers (the classic research names from the `iphone-dataprotection` era):

| Locker | Holds |
|---|---|
| `EMF!` | The volume/filesystem ("media") key that, with the per-file keys, gates the whole encrypted volume |
| `DKey` | The **Class D (`NSFileProtectionNone`) class key** — the always-available, no-passcode key |
| `BAG1` | The keybag key that (pre-A9) wraps the keybag itself |
| `LwVM` | LightweightVM partition-table metadata |

The chain that makes "Erase All Content and Settings" finish in seconds: erasing Effaceable Storage destroys `EMF!`, `DKey`, and `BAG1` → the keybag key is gone (so no class key can ever be unwrapped) → and `DKey` is gone (so even Class D, which needed no passcode, is unrecoverable). Every per-file key on NAND is still there, wrapped, but **nothing can unwrap them ever again**, and the ciphertext is computationally inert. On A9+ the keybag-wrapping role moved into the **SEP's anti-replay locker** rather than `BAG1` in Effaceable Storage, which also closed a forward-secrecy gap on passcode change (old wrappings can't be replayed). The forensic consequence is blunt: a completed wipe is final — there is no carving back from a crypto-shred — and **Class D being "always available" still does not survive a wipe**, because its key lived in the block you just erased.

> 🔬 **Forensics note:** This is also why a **remote wipe** (Find My / MDM `EraseDevice`) is so destructive so fast, and why getting a seized device into a Faraday bag *immediately* matters — a wipe command that reaches the device erases Effaceable Storage before you've imaged anything, and unlike a file deletion there is no residual ciphertext worth recovering afterward. Document radio isolation in your custody log for exactly this reason.

### File content cipher and per-extent keys

The per-file key encrypts *content*, but the cipher and granularity are worth pinning down. Historically iOS used **AES-CBC** with a per-block IV derived from the block's offset (so identical plaintext blocks at different offsets produce different ciphertext); modern hardware uses **AES-XTS-256**, the standard for storage-at-rest, where the block (sector) number feeds the tweak. The exact mode is SoC- and OS-dependent — verify against the Apple Platform Security edition for your target rather than assuming. APFS adds a twist macOS forensics rarely exercises: because each **file extent** (`j_file_extent_val_t`) carries its own `crypto_id`, different byte ranges of a single file can be keyed independently — useful for clone/copy-on-write semantics, and a detail a naïve "one key per file" parser will get wrong on fragmented or cloned files.

### What changed, by iOS version (durable mechanism first, dated facts second)

The *mechanism* above is durable — it has held in shape since iOS 4 introduced Data Protection. The perishable specifics:

| Change | When | Effect |
|---|---|---|
| Data Protection introduced (Class A/D, then C, then B) | iOS 4 → iOS 5 | Class C and Class B (`CompleteUnlessOpen`, Curve25519) added in iOS 5 |
| Class C becomes the de-facto default for app data | iOS 7+ | The "AFU gets almost everything" reality solidifies |
| HFS+ → **APFS** | iOS 10.3 | `com.apple.system.cprotect` xattr → `j_crypto_val_t`/`wrapped_crypto_state_t` filesystem records |
| Keybag wrapping moves Effaceable (`BAG1`) → **SEP anti-replay locker** | A9+ SoCs | Forward secrecy on passcode change; harder to attack the keybag wrapping |
| **Inactivity reboot** (AFU→BFU after idle) | iOS 18.1 (Oct 2024) | A seized AFU device self-reboots to BFU after ~72 h idle; iOS 18.2 reportedly tightened/clarified the timer — **re-verify the exact window for your target build** |
| **Advanced Data Protection (ADP)** end-to-ends iCloud | iOS 16.2 (Dec 2022) | The iCloud Backup keybag's keys go E2E; cloud acquisition of content becomes infeasible |

As of the 2026.x era (iOS/iPadOS 26.5), the four-class file model, the keybag taxonomy, and the SEP-gated unlock are unchanged in shape; what moves underneath is the **mitigation context** around the SEP (PAC → PPL → SPTM/TXM → Exclaves → MIE on A19) that makes *defeating* Data Protection on A14+ a problem with **no public solution** — the data model is the same, the wall just got higher. Flag for re-verification at author time: the exact inactivity-reboot window per build, and whether iOS 27 (WWDC 2026) alters any class semantics.

### Worked example: one Class-C file from birth to read

Trace `sms.db` (default class, so Class C) end-to-end and the whole hierarchy snaps into focus:

1. **Create (device unlocked).** SpringBoard is unlocked; the SMS daemon creates `sms.db`. The SEP mints a random 256-bit **per-file key** `Kf`. The inline AES engine begins encrypting the database's bytes to NAND under `Kf` (AES-XTS-256).
2. **Wrap.** The file inherits Class C from its directory's `default_protection_class`. The SEP wraps `Kf` with the **Class-C class key** `Kc` via AES-KW (RFC 3394) → `wrap(Kc, Kf)`.
3. **Persist the wrapped key.** APFS writes a `j_crypto_val_t` whose `wrapped_crypto_state_t` carries `persistent_class = 3` and `persistent_key = wrap(Kc, Kf)`. The file's extents reference this crypto state by `crypto_id`. **`Kf` in plaintext is never written to disk.**
4. **Lock the screen.** `Kc` *stays* in the keystore (Class C survives lock). Messages can still read/write `sms.db` if it keeps a handle, and a fresh open still succeeds because `Kc` is resident.
5. **Reboot (or 72h inactivity).** Now the device is **BFU**. `Kc` is evicted; it is *not* re-derivable without the passcode. `sms.db`'s extents are intact ciphertext on NAND, the wrapped `Kf` is intact in the crypto-state record — but `wrap(Kc, Kf)` can't be unwrapped because `Kc` is gone. A BFU extraction recovers the file *object* and its `persistent_class=3` and nothing readable inside.
6. **First unlock → read.** Passcode ⊗ UID in the SEP → passcode key → unwrap the user keybag → `Kc` resident again. APFS reads the crypto state, asks AppleKeyStore to unwrap `Kf` with `Kc`, hands `Kf` to the AES engine, and the message bodies decrypt. **An AFU extraction taken at this point gets everything.**

Steps 5 and 6 *are* the BFU/AFU boundary made concrete: same bytes on NAND, same wrapped key in the same record, decryptable or not purely on whether `Kc` is resident.

### How a file actually gets its class

You'll want to predict a file's class without reading its `wrapped_crypto_state_t`, so know the assignment precedence (highest wins):

1. **Explicit per-file API.** A developer sets it directly: `NSData`'s `writeToFile:options:` with `NSDataWritingFileProtectionComplete`, the `NSFileProtectionKey` file attribute, or `open(2)` with the `O_*` content-protection class flags. This overrides everything.
2. **Process default-data-protection entitlement.** An app can raise the default for *everything* it writes via the `com.apple.developer.default-data-protection` entitlement — common in security-conscious apps. The whole container then defaults to Class A instead of C:

```xml
<key>com.apple.developer.default-data-protection</key>
<string>NSFileProtectionComplete</string>
```

   You can read this straight out of a target app's embedded entitlements (`codesign -d --entitlements :- /path/App.app`), which tells you, before you ever image a device, whether that app's files will go dark on lock.
3. **Directory default (inheritance).** New files inherit the directory's `default_protection_class`. This is why most of `/private/var/mobile/...` lands in Class C: the containers default to C.
4. **System default.** Absent all the above, **Class C** (`CompleteUntilFirstUserAuthentication`).

Certain system locations are *deliberately* Class D so the OS can function pre-unlock (BFU): parts of the boot/preferences path, the keybags themselves (the user keybag is stored in the No-Protection class so it's reachable to *attempt* an unlock), and data a daemon must touch before first unlock. Conversely, an app that bumps to Class A trades availability for secrecy — its files go dark the instant the screen locks, which is a deliberate design choice for, e.g., a password manager's vault.

> 🔬 **Forensics note:** This precedence is *itself* evidence. If a normally-Class-C artifact appears as **Class A** in a `persistent_class` dump, the owning app set it deliberately (entitlement or per-file API) — a signal that the developer treated that data as sensitive, and a hint about which apps will go unreadable the moment a seized device locks even while AFU. Conversely, a sensitive-looking file sitting in **Class D** is reachable in *every* state including BFU — note it, because it's the data you can get even from a rebooted device.

> ⚠️ **ADVANCED — device-bound, do not attempt on evidence:** On-device passcode brute force (the GrayKey/Cellebrite Premium model) requires (a) AP code execution below the OS — `checkm8` on A8–A11, `usbliter8` on A12–A13 as of 2026-06-18, *nothing public on A14+* — **and** (b) a way to defeat or out-run the SEP's guess-rate enforcement. The BootROM exploit alone gets you *onto* the device; it does **not** by itself unwrap Data Protection or bypass the SEP try-counter. On A14+ there is no public BootROM exploit at all, so the "wall" the field talks about is now **A13→A14**, not the old A11→A12. Any attempt to brute a passcode counts against the SEP counter and can trigger the 10-try wipe — never run it against original evidence; work from an image and a documented, authorized methodology.

## Hands-on

There is no on-device shell, and the Simulator has no SEP and no Data Protection — so these commands either (a) *prove the absence* of Data Protection on the Simulator (instructive in itself) or (b) parse keybags / `cprotect` records on **public sample full-filesystem images**. Nothing here decrypts a device you don't have keys for.

### 1. Prove the Simulator has no Data Protection (the negative control)

```bash
# Find a booted Simulator's app container root on the Mac
xcrun simctl list devices booted
SIMROOT=~/Library/Developer/CoreSimulator/Devices

# The app's data container is a PLAINTEXT directory on your Mac's APFS volume:
find "$SIMROOT" -path '*/data/Containers/Data/Application/*' -name '*.sqlite' 2>/dev/null | head

# Open one directly — no copy-first dance is needed for *encryption* reasons here
# (it's plaintext), though forensic copy-before-query hygiene still applies:
DB=$(find "$SIMROOT" -name 'NoteStore.sqlite' 2>/dev/null | head -1)
sqlite3 "file:$DB?mode=ro" '.tables'        # opens fine — there is no class key in the way

# There is NO cprotect / wrapped key on these files:
xattr -l "$DB"                              # no com.apple.system.cprotect; on a real device
                                            # the per-file key would be in a j_crypto_val_t record
```

Expected output — the open succeeds and there is no crypto attribute at all:

```
# .tables prints normally:
ZICCLOUDSYNCINGOBJECT   ZICNOTEDATA   Z_METADATA   Z_PRIMARYKEY   ...
# xattr -l prints nothing (or only unrelated attrs like com.apple.quarantine on a download)
```

**That's the lesson** — the Simulator teaches schema and layout, never lock-state behavior. The bytes on a real device sit behind a class key you don't have.

### 2. Dump per-file protection classes from a sample APFS image with `libfsapfs`

```bash
# libfsapfs is NOT in Homebrew — build the libyal tools from source (Joachim Metz, libyal).
# Provides fsapfsinfo / fsapfsmount; needs Xcode CLT + openssl/zlib (FUSE for fsapfsmount):
git clone https://github.com/libyal/libfsapfs && cd libfsapfs
./synclibs.sh && ./autogen.sh && ./configure && make    # then: sudo make install

# Against a DECRYPTED sample full-file-system image (e.g. a research/teaching image),
# enumerate a file's crypto state — persistent_class is visible even pre-decryption:
fsapfsinfo -f 1 -E all sample_ffs.raw            # -f = volume index; lists extended/crypto info

# With the volume/recovery key supplied, fsapfsmount can mount and decrypt:
mkdir -p /tmp/apfs_mnt
fsapfsmount -X allow_other -p "$VOLKEY_HEX" sample_ffs.raw /tmp/apfs_mnt
```

Expected output — the crypto state per file, with the class number front and center:

```
Extended attributes:
    Number of crypto states            : 1
    Crypto state: 0
        Protection class               : 3        ← Class C (default)
        Major version                  : 5
        Wrapped key size               : 40 bytes ← the RFC 3394-wrapped per-file key
```

So: for each file you can read its `persistent_class`; Class D (`4`) entries are decryptable from the UID/effaceable material in the image, while Class A/C entries need the passcode-derived class keys (absent unless the image was captured AFU/keyed). A whole-image histogram of that "Protection class" line is your decryptability triage.

### 3. Parse a keybag's TLV structure from a full-filesystem image

```bash
# The system/user keybag on a full-filesystem image:
ls -l mount/private/var/keybags/systembag.kb

# A minimal TLV walk (the classic iphone-dataprotection format): 4-byte tag,
# 4-byte big-endian length, value. Read TYPE, then each CLAS/WRAP/KTYP record:
python3 - <<'PY'
import struct, sys
blob = open('mount/private/var/keybags/systembag.kb','rb').read()
i = 0
while i + 8 <= len(blob):
    tag = blob[i:i+4].decode('ascii','replace'); ln = struct.unpack('>I', blob[i+4:i+8])[0]
    val = blob[i+8:i+8+ln]; i += 8 + ln
    if tag in ('TYPE','VERS','CLAS','WRAP','KTYP'):
        print(tag, int.from_bytes(val,'big') if ln in (1,2,4) else val.hex())
PY
```

Expected output — the header then the per-class triples:

```
VERS 4
TYPE 0          ← system/user keybag
CLAS 1          ← class A …
WRAP 3          ← … wrapped with BOTH device + passcode key → needs unlock (not BFU)
KTYP 0          ← symmetric
CLAS 2          ← class B …
WRAP 3
KTYP 1          ← Curve25519 (asymmetric)  → has a PBKY record
CLAS 3          ← class C (default) …
WRAP 3          ← needs passcode → AFU-only
CLAS 4          ← class D …
WRAP 1          ← device/UID key ONLY → readable in BFU
KTYP 0
```

Read `WRAP=1` as "BFU-available (device/UID key only)" and `WRAP=3` as "needs passcode." This is the on-disk BFU/AFU table from Concepts, in front of you — class D (`WRAP 1`) is the only one a never-unlocked device will surrender.

### 4. Where the real tools sit

```bash
# Logical/AFU acquisition plumbing (covered in Part 07) — note it cannot conjure keys:
pip install pymobiledevice3                  # backup, lockdown, AFC over USB
# mvt / iLEAPP parse artifacts but DO NOT decrypt Data Protection — they assume you
# already have a decrypted filesystem (AFU extraction or a decrypted backup).
```

Expected mental model: `pymobiledevice3`, `mvt`, `iLEAPP`, `apollo` operate **after** the crypto problem is solved — on a decrypted backup or AFU filesystem. None of them defeat Data Protection; they consume its output.

### 5. Inspect a backup's protection posture (no device needed)

```bash
# A Finder/iTunes backup directory (covered fully in Part 07). The Manifest.plist tells you
# whether the backup is ENCRYPTED — i.e. whether the BACKUP keybag (PBKDF2 x10,000,000) is in play:
plutil -extract IsEncrypted xml1 -o - ~/path/to/backup/Manifest.plist     # true / false

# An encrypted backup's keys are wrapped to the BACKUP password, not the device passcode.
# Tools like mvt-ios / iphone_backup_decrypt unwrap them GIVEN that password:
pip install mvt
mvt-ios decrypt-backup -p 'THE_BACKUP_PASSWORD' -d /out ~/path/to/backup
```

Expected: `IsEncrypted = true` means the backup keybag re-wrapped every migratory item to the backup password (so a strong password is your defense / your obstacle); `false` means the backup is portable with no password — the soft underbelly. Either way the *device's* Data Protection classes were resolved on the device during backup; what you hold now is re-wrapped to the backup keybag, not the device keybag.

## 🧪 Labs

> Every lab is device-free. Labs 1 uses the **Xcode Simulator** (no SEP, no Data Protection, no keybag — it teaches the *negative* and the schema, never lock-state behavior). Labs 2–4 use a **public sample full-filesystem image** or a **read-only walkthrough/table** because keybags, `wrapped_crypto_state_t`, and the SEP keystore **do not exist on the Simulator** and cannot be produced without a physical device.

### Lab 1 — Confirm the Simulator has no per-file encryption *(substrate: Xcode Simulator; fidelity caveat: Simulator runs macOS frameworks — there is NO SEP, NO Data-Protection-at-rest, NO keybag; the host volume's own FileVault is the only at-rest crypto, which is the macOS volume-key model, not iOS Data Protection)*

1. Boot a Simulator, open Notes/Messages in it, add a record.
2. Locate the backing SQLite under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/`.
3. Open it directly with `sqlite3 'file:...?mode=ro'`. It works with no key. `xattr -l` shows no `cprotect`.
4. Write one sentence explaining why this proves the Simulator can teach *schema* but not *Data Protection*, and what would be different on a real device's copy of the same file (a `j_crypto_val_t` record carrying a `wrapped_crypto_state_t` whose `persistent_class` is almost certainly `3`/Class C).

### Lab 2 — Build the class table from first principles *(substrate: read-only walkthrough + the table; no device or image needed)*

1. Reproduce the four-class table from memory: class letter, API constant, BFU?, AFU-locked?, unlocked?.
2. For each of these well-known artifacts, predict its **most likely** class and whether a **BFU** extraction would yield its *contents*: `sms.db`, `knowledgeC.db`/Biome SEGB streams, `Photos.sqlite`, a Mail attachment mid-download, a Wi-Fi password in the keychain.
3. Now predict the same for an **AFU** extraction. Explain in one line why the AFU column is almost all ✓ (default = Class C, key resident until reboot).
4. State what the **72-hour inactivity reboot** does to an idle seized device and why it is an evidence-handling decision, not a tooling step.

### Lab 3 — Read a keybag and predict BFU availability *(substrate: public sample full-filesystem image, e.g. a Hickman/Digital Corpora teaching image; fidelity caveat: the wrapped class keys are real bytes but cannot be UNWRAPPED without the device's passcode-derived key, which is not in the image — you are reading structure, not decrypting)*

1. Locate `private/var/keybags/systembag.kb` in the image.
2. Run the Lab-3 TLV walker from Hands-on. Record the keybag `TYPE`.
3. Enumerate each class entry's `CLAS`, `WRAP`, and `KTYP`. Tabulate which classes are `WRAP=1` (device/UID only → BFU-available) vs `WRAP=2/3` (passcode → AFU-only).
4. Confirm the asymmetric (`KTYP=1`) entry corresponds to Class B / the iCloud path, and explain why a `PBKY` is present for it but not for the symmetric classes.

### Lab 4 — Histogram `persistent_class` across a filesystem image *(substrate: public sample APFS image via `libfsapfs`; fidelity caveat: you can read every file's class without keys; you can only DECRYPT the files whose class key is derivable from material present in the image — typically Class D, plus everything if the image was captured AFU/keyed)*

1. `fsapfsinfo -E all` over the sample image; extract `persistent_class` for every file (script it).
2. Produce a histogram: how many files are Class A vs B vs C vs D.
3. Predict your decryptable yield in a **BFU** scenario (Class D only) vs **AFU** (Class C and below). Compare against the actual files you can open.
4. Pick one Class-C database (e.g. an app's SQLite). Confirm `libfsapfs` exposes its `persistent_class=3` but cannot decrypt it without the resident class-C key — and write down what acquisition posture *would* have captured it.

### Lab 5 — Trace the wipe path on paper *(substrate: read-only walkthrough; no device — Effaceable Storage and SEP lockers do not exist on the Simulator and cannot be safely exercised on real hardware without destroying data)*

1. List the four Effaceable Storage lockers (`EMF!`, `DKey`, `BAG1`, `LwVM`) and what each holds.
2. Walk the "Erase All Content and Settings" chain step by step: which locker is erased, which key dies, and why every per-file key on NAND becomes permanently unwrappable.
3. Explain why **Class D** ("always available, no passcode") still does **not** survive a wipe — name the specific locker whose destruction kills it.
4. State the A9+ change (keybag wrapping moved from `BAG1` in Effaceable Storage into the SEP anti-replay locker) and what forward-secrecy problem it solved on passcode change.
5. Write the one-line custody rule this implies for a powered-on seized device (immediate radio isolation, because a remote wipe crypto-shreds before you can image).

## Pitfalls & gotchas

- **"The volume mounted, so it's all readable" — the macOS reflex that fails on iOS.** A full-filesystem image can mount and you'll see the directory tree and file *names*, while the file *contents* are ciphertext because their class keys were never resident at capture. Mounting ≠ decrypting on iOS.
- **Treating Class D as plaintext.** Class D ("None") is *not* unencrypted — it's encrypted under a UID-derived class key that needs no passcode. It is therefore (a) readable BFU and (b) still crypto-shredded by a wipe, because the `DKey` wrapping lives in Effaceable Storage. Don't tell a court "Class None means it wasn't encrypted."
- **Assuming AFU = unlocked.** AFU means "passcode entered *at least once* since boot," not "currently unlocked." Class C is available AFU even with the screen locked; Class A is *not* — it needs the device currently unlocked. Conflating these mis-predicts what you can read.
- **Forgetting the inactivity reboot.** An idle seized device hits the **72-hour inactivity reboot** (iOS 18.1+) and silently drops AFU→BFU, evicting the Class C key. An extraction that would have worked on day 1 fails on day 4 for a reason that has nothing to do with your tools. Keep AFU devices powered and exercised, or accept BFU.
- **Backup password ≠ passcode, but it gates the backup keybag.** The backup keybag uses **PBKDF2 with 10,000,000 iterations** over the *backup* password. A weak/blank backup password is the soft underbelly of a logical acquisition (the keys re-wrap to it); a strong one makes the backup as hard as the device. Don't confuse it with the device passcode.
- **`persistent_class` numbers beyond 1–4.** You'll meet `6`/Class F and `14`/Class M and possibly directory-default `0` in real `wrapped_crypto_state_t` dumps (value `5` is undefined/reserved for files — don't expect it, and don't mislabel it Class F). Don't force-map every value to A–D; verify the extras against the `apfs.h` for the target OS rather than guessing.
- **HFS+ vs APFS representation.** "cprotect" is two different things by era: the literal `com.apple.system.cprotect` xattr on legacy HFS+ iOS, and the `j_crypto_val_t` filesystem record on APFS. A parser written for one won't find the other.
- **ADP silently invalidates the cloud avenue.** If Advanced Data Protection is on, the iCloud Backup keybag's keys are E2E and Apple holds nothing decryptable — legal process to Apple returns metadata, not content. Check ADP status before you plan a cloud acquisition, not after it comes back empty.
- **The Simulator will lie to you about encryption.** Everything in a Simulator container is plaintext on the Mac. Never reason about lock-state behavior, key availability, or BFU/AFU from Simulator observations — only schema and layout.
- **A paired computer can be worth more than the passcode.** Because the escrow keybag lets a trusted host back up without the passcode, a **lockdown/pairing record** lifted from the suspect's Mac/PC can drive a logical/AFU acquisition of the device with no passcode entry — *if* the device is in AFU and the record is still valid. Seize and preserve paired computers; don't tunnel-vision on the phone. (Pairing records expire and can be invalidated by reboot/`pair` reset — verify validity before relying on one.)
- **Per-extent keys and clones break "one key per file" parsers.** APFS keys per *extent* and uses copy-on-write clones, so a single file can span multiple `crypto_id`s and a "cloned" file may share crypto state with its origin. A parser that assumes exactly one wrapped key per inode will mis-handle fragmented, cloned, or partially-rewritten files — validate your tool against a known multi-extent sample.
- **`persistent_class` is metadata you can trust even when the content lies.** The class number is readable without any key, survives in the filesystem record, and tells you a file's intended protection regardless of whether you can decrypt it — use it as ground truth for triage and for stating, defensibly, what a given lock state could and could not have yielded.

## Key takeaways

- iOS encryption is a **four-layer wrap**: per-file key → class key → keybag → (passcode ⊗ SEP-UID). Each layer wraps the one below; the bottom layer is bound to non-extractable hardware, so the keybag can't be brute-forced off-device.
- There are **four file Data Protection classes** — A (`Complete`, only while unlocked), B (`CompleteUnlessOpen`, asymmetric Curve25519 so it can be *written* locked but only *read* unlocked), **C (`CompleteUntilFirstUserAuthentication`, the DEFAULT, resident from first unlock until reboot)**, D (`None`, UID-only, always). Memorize the availability columns.
- **The default being Class C is why AFU gets almost everything and BFU gets almost nothing.** Lock state at seizure is an evidence-defining variable — record it like a hash.
- Each file's wrapped key + class live in the **`wrapped_crypto_state_t`** (`j_crypto_val_t` on APFS; `com.apple.system.cprotect` xattr on legacy HFS+). `persistent_class` lets you triage decryptability *before* you have a single key.
- **Keybag types** (`TYPE` 0 user/system, 1 backup, 2 escrow, 3 OTA/iCloud) re-wrap the class keys for different purposes; the per-class **`WRAP`** flag encodes BFU availability directly (`1`=device/UID-only=BFU, `2`/`3`=passcode=AFU-only).
- The **backup keybag** uses PBKDF2×10,000,000 over the backup password; the **iCloud Backup keybag** uses **Curve25519 asymmetric** keys — which is exactly why **ADP** breaks cloud acquisition.
- The **AKS/AppleKeyStore → SEP** flow holds unwrapped class keys *inside the SEP keystore*, not AP-accessible memory; this is why a BootROM/AP exploit (`checkm8` A8–A11, `usbliter8` A12–A13, nothing public on A14+) gets you *onto* the device but does **not** by itself defeat Data Protection or the SEP try-counter.
- **macOS muscle memory is wrong here:** FileVault is one volume key and one unlock; iOS is per-file keys and lock-state gating. "Unlocked = everything readable" does not hold.

## Terms introduced

| Term | Definition |
|---|---|
| Data Protection | iOS's per-file encryption system: random per-file key → class key → keybag → passcode⊗UID |
| Per-file key | Random 256-bit AES key generated by the SEP at file creation; encrypts file content via the inline AES engine |
| Class key | A key (symmetric for A/C/D, asymmetric Curve25519 for B) that wraps per-file keys; lives in the keybag |
| NSFileProtectionComplete | Class A — key resident only while the device is unlocked |
| NSFileProtectionCompleteUnlessOpen | Class B — asymmetric; can be created/written while locked, read only while unlocked |
| NSFileProtectionCompleteUntilFirstUserAuthentication | Class C — the **default**; key resident from first unlock until reboot/shutdown |
| NSFileProtectionNone | Class D — UID-derived class key, no passcode; available from boot (BFU) but still crypto-shredded by wipe |
| Keybag | A TLV blob holding the class keys (file + keychain); types: user, device, backup, escrow, iCloud/OTA |
| Escrow keybag | Keybag split between device and trusted host enabling passcode-free backup/sync ("trust this computer") |
| iCloud Backup keybag | Keybag whose class keys are asymmetric (Curve25519); ADP makes its keys E2E, breaking cloud acquisition |
| `wrapped_crypto_state_t` | APFS crypto-state struct carrying `persistent_class` + the RFC 3394-wrapped per-file key |
| cprotect | The per-file wrapped-key record: `j_crypto_val_t` on APFS; `com.apple.system.cprotect` xattr on legacy HFS+ |
| `persistent_class` | Field in `wrapped_crypto_state_t` encoding the Data Protection class (1=A,2=B,3=C,4=D,…) |
| AES Key Wrap (RFC 3394) | NIST AES-KW primitive used to wrap per-file keys with class keys (Apple's `AES.KeyWrap`) |
| Passcode key | Passcode entangled with the SEP-fused UID (~80 ms/try) to unwrap passcode-protected class keys |
| UID | Per-device AES key fused into the SEP, never software-readable; forces brute force to run on-device |
| AppleKeyStore (AKS) | Kernel extension that brokers unlock/unwrap requests to the SEP; reports device lock state |
| MobileKeyBag | Userspace framework/`keybagd` that passes the passcode to AppleKeyStore/SEP |
| BFU / AFU | Before First Unlock / After First Unlock — the lock-state regimes that decide which class keys are resident |
| Inactivity reboot | iOS 18.1+ auto-reboot (~72 h idle) that forces AFU→BFU, evicting the Class C key |
| Effaceable Storage | Small directly-addressable NAND region (bypasses the FTL) holding wipe-critical lockers; erasing it crypto-shreds the device |
| `DKey` / `EMF!` / `BAG1` | Effaceable lockers: the Class-D class key, the volume/media key, and the (pre-A9) keybag-wrapping key |
| `pdmn` | The protection-domain column in `keychain-2.db` encoding a keychain item's class (`ak`/`ck`/`dk`/`*ThisDeviceOnly`) |
| Per-extent key | APFS's ability to key sub-ranges of a file independently via each extent's `crypto_id` |
| AES-XTS-256 | The at-rest content cipher used by the inline AES engine on modern devices (historically AES-CBC) |

## Further reading

- **Apple Platform Security guide** — *Data Protection overview*, *Data Protection classes*, *Keybags for Data Protection*, *Encryption and Data Protection* (support.apple.com/guide/security) — the primary, current source; re-read the edition matching your target OS.
- **Apple Developer** — `NSFileProtectionType` constants; `kSecAttrAccessible*` keychain constants; CryptoKit `AES.KeyWrap`.
- **Joe T. Sylve, Ph.D.** — *APFS Keybags* and *APFS Wrapped Keys* (jtsylve.blog, 2022 APFS Advent series) — the `wrapped_crypto_state_t` / `j_crypto_val_t` field-level reference.
- **`libfsapfs`** (Joachim Metz / libyal) — `fsapfsinfo`, `fsapfsmount`, and the *Apple File System (APFS)* format documentation (github.com/libyal/libfsapfs) — crypto-state structs and decryption with supplied keys.
- **Bédrune & Sigwald**, *iPhone Data Protection in Depth* / the `iphone-dataprotection` project (Sogeti ESEC Lab) — the canonical keybag TLV format, class numbers, `WRAP`/`KTYP`, and effaceable lockers (`EMF!`, `DKey`, `BAG1`).
- **RFC 3394** — *AES Key Wrap Algorithm* (the exact wrap used for per-file keys).
- **Jonathan Levin**, *MacOS and iOS Internals* Vol. III — AppleKeyStore/SEP keystore plumbing and the kernel side of unlock.
- **Sarah Edwards (mac4n6.com)**, **Alexis Brignoni (iLEAPP)**, **SANS FOR585** — applying the BFU/AFU class model to real artifact acquisition and parsing.
- Vendor practitioner write-ups — **Elcomsoft** and **Magnet/GrayKey** blogs on BFU vs AFU yield, the inactivity reboot, and what each lock state surrenders.
- `man` and tool docs: `fsapfsinfo(1)`, `fsapfsmount(1)`; `pymobiledevice3`, `mvt`, `apollo` READMEs.

---
*Related lessons: [[01-sep-sepos-deep-dive]] | [[03-storage-nand-aes-effaceable]] | [[03-passcode-bfu-afu-and-inactivity]] | [[08-keychain-on-ios]] | [[03-apfs-on-ios-volumes]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[07-decrypting-backups-and-images]] | [[06-icloud-acquisition-and-advanced-data-protection]] | [[09-advanced-protections-lockdown-sdp-adp]]*
