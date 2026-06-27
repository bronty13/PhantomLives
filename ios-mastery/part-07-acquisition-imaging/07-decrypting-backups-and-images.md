---
title: "Decrypting backups & images"
part: "07 — Forensic Acquisition & Imaging"
lesson: 07
est_time: "45 min read + 20 min labs"
prerequisites: [the-itunes-finder-backup-format, data-protection-and-keybags]
tags: [ios, forensics, decryption, hashcat, keybag, dfir]
last_reviewed: 2026-06-26
---

# Decrypting backups & images

> **In one sentence:** the ciphertext you recovered is only evidence once it is unwrapped, and on iOS exactly one of the two unwrap problems is tractable off-device — a user-chosen **backup password** that gates a portable `BackupKeyBag` and is often weak enough for a GPU to brute-force, versus the **device passcode** that is entangled with the SEP-fused UID and therefore impossible to attack anywhere but on that one phone, at ~80 ms a guess, behind a wipe counter.

## Why this matters

You already know from [[02-data-protection-and-keybags]] that an iOS file is sealed by a per-file key, wrapped by a class key, wrapped by a keybag, rooted in `passcode ⊗ UID`. That lesson ended at "and exactly which class keys were resident at capture decides what you can read." This lesson is the *next* step: you are holding wrapped bytes — an encrypted iTunes/Finder backup, or a full-file-system image whose class keys you have not yet unwrapped — and you need readable evidence out of it. The single most important judgement you will make is **which of the two unwrap problems you are even looking at**, because they have opposite difficulty.

Get this wrong and you waste a GPU cluster running a passcode wordlist that *cannot* succeed off-device, or you tell a court a backup was "unbreakable" when its owner used `1234` as the backup password and a laptop would have cracked it over lunch. The crackable surface on iOS is narrow and specific — the **user-chosen backup password**, which protects a re-wrapped, *portable* keybag and is therefore brute-forceable on hardware you control. Everything else (the device passcode, hence an unkeyed BFU image) is bound to silicon you don't have. Knowing precisely where that line sits — and being able to state it defensibly in a report — is the deliverable.

## Concepts

### Two unwrap problems, one of which is solvable

Stop and separate them, because every later decision branches here:

| | **Encrypted backup password** | **Device passcode** |
|---|---|---|
| What it gates | The `BackupKeyBag` (a **portable** re-wrapped keybag) | The user/device keybag bound to the SEP UID |
| KDF | **PBKDF2** (double, on iOS 10.2+), runs anywhere | `passcode ⊗ UID` entanglement, **on-SEP only** |
| Cost per guess | GPU-parallel; iterations are the only brake | **~80 ms**, serialized, SEP-throttled |
| Where it can run | **Any machine** — the salts + iterations + wrapped keys are all in the backup files | **Only on that exact device** (UID never leaves the SEP) |
| Brute-force ceiling | Limited by password entropy + iteration count | Hard wall: escalating delays + optional **10-try wipe** |
| Forensic verdict | **Crackable when the password is weak** | **Off-device: impossible. On-device: SEP-rate-limited, no public bypass on A14+** |

This asymmetry is the whole lesson. The backup password is a *human-chosen string* whose entire defensive value is the PBKDF2 iteration count — and humans pick weak strings. The device passcode's defensive value is **hardware**: the UID is fused into the SEP and never software-readable, so the KDF *physically cannot run* on your GPU. That is why backup-password cracking is a productive line of work and device-passcode cracking off-device is a category error.

> 🖥️ **macOS contrast:** On macOS you decrypt a FileVault volume with one of several *equivalent unwrap paths* for the single Volume Encryption Key — the login password, a **personal recovery key**, or an **institutional/FileVault master key** escrowed by MDM. Any one of them unwraps the VEK and the whole volume goes transparent. The iOS encrypted **backup** is the closest analogue: the backup password is its one unwrap path, and like a lost FileVault recovery key with no other escrow, a forgotten backup password with no GPU win means the data is gone. But the iOS **device passcode** has *no* off-device recovery-key analogue at all — there is no escrowed master key you can subpoena that unwraps a local BFU image, because the root of trust is the non-exportable UID, not a key Apple or an admin ever held. macOS gives you alternative doors; the iOS device gives you exactly one, and it only opens from inside the SEP.

### The encrypted-backup key hierarchy, top to bottom

When a user ticks "Encrypt local backup," the device does **not** hand the host its device keybag. It mints a fresh **`BackupKeyBag`** (keybag `TYPE = 1`) containing a *new* set of class keys, and re-wraps every migratory item's per-file key to those new class keys. The whole bag is then protected by the **backup password** through PBKDF2. The result is portable — it can be restored onto a different device — and it is the thing you attack.

The chain from a typed password to a plaintext file:

```
backup password
   │  double-PBKDF2  (SHA-256 × DPIC  then  SHA-1 × ITER, salts from the keybag)
   ▼
keybag-unwrapping key
   │  RFC 3394 AES-KW unwrap of each BackupKeyBag class key (per CLAS / WRAP entry)
   ▼
backup CLASS keys   (A / C / D … re-minted for this backup)
   │  Manifest.plist : ManifestKey = [4-byte LE class#] ‖ [wrapped key]
   │  unwrap ManifestKey with class[that#]   (RFC 3394)
   ▼
ManifestKey
   │  AES-CBC decrypt  Manifest.db   (IV = sixteen 0x00 bytes)
   ▼
Manifest.db (SQLite)  ──►  Files table
   │  each Files.file = NSKeyedArchiver bplist of an MBFile:
   │      { ProtectionClass, EncryptionKey = wrapped per-file key, Size, LastModified, … }
   │  unwrap EncryptionKey with class[ProtectionClass]   (RFC 3394)
   ▼
per-file key
   │  AES-CBC decrypt the on-disk blob at  <backup>/<fileID[0:2]>/<fileID>
   ▼
PLAINTEXT FILE  ──►  Manifest.db maps fileID→domain/relativePath  ──►  iLEAPP / mvt / sqlite3
```

Five things to lock in from that diagram:

1. **The password never touches a file key directly.** It derives a key that unwraps *class keys*; class keys unwrap the `ManifestKey` and the per-file keys. Same RFC 3394 wrapping you saw on-device — just re-rooted to a password instead of `passcode ⊗ UID`.
2. **`Manifest.plist` is plaintext and tells you the posture before you crack anything.** `IsEncrypted`, the base64 `BackupKeyBag` (TLV — same `VERS`/`TYPE`/`SALT`/`ITER`/`DPIC`/`DPSL`/per-`CLAS` `WPKY` layout from [[02-data-protection-and-keybags]]), and `ManifestKey`. You read the salts and iteration counts straight out of it.
3. **`Manifest.db` is itself encrypted as a whole** (iOS 10.2+) under the `ManifestKey`. Until you unwrap it you cannot even see the file *index* — domains, paths, sizes. This is why "I can see the backup folder but every file is a 2-hex-named blob of noise" is the normal encrypted-backup state, not a corruption.
4. **Each backed-up file is stored by hash, not by name.** `fileID = SHA-1("<domain>-<relativePath>")`, sharded into a subdirectory named by its first two hex chars. `Manifest.db.Files` is the only map from that hash back to `CameraRollDomain`/`Media/DCIM/...`.
5. **The class number rides with every key.** `ManifestKey` is prefixed with a 4-byte little-endian class number; each `MBFile` carries `ProtectionClass`. That tells you *which* unwrapped class key to apply — and, forensically, the intended protection class of every file even before you decrypt it.

> 🔬 **Forensics note:** The keychain rides along too. The `BackupKeyBag` re-wraps the **keychain** class keys, and the backup contains the keychain database (`KeychainDomain`, the `keychain-backup.plist`/`backup_keychain` payload depending on era). Once you have the backup password you recover **saved passwords, tokens, and Wi-Fi keys** for every migratory (`WhenUnlocked`/`AfterFirstUnlock`, *not* `ThisDeviceOnly`) item — frequently the highest-value evidence in the whole extraction. `mvt-ios` and `dunhamsteve/ios` both surface it. The `ThisDeviceOnly` items (`pdmn` = `aku`/`cku`/`dku`/`akpu`) are UID-bound and were *never* re-wrapped into the backup, so their absence is expected, not a tool failure.

### Inside the `BackupKeyBag`: the TLV fields and the `WRAP` flag that decides portability

The base64 `BackupKeyBag` decodes to the same **Type-Length-Value** grammar as the on-device keybags ([[02-data-protection-and-keybags]]): a 4-byte ASCII **tag**, a 4-byte big-endian **length**, then the value. It splits into a **header** followed by one **per-class block** repeated for every protection class:

```
HEADER
  VERS  <int>    keybag format version (4 on modern iOS)
  TYPE  <int>    1 = backup   (0 = system, 2 = escrow, 3 = OTA/iCloud)
  UUID  <16 B>   keybag UUID
  HMCK  <40 B>   wrapped HMAC key (bag integrity)
  WRAP  <int>    default wrap policy for the bag
  SALT  <20 B>   PBKDF2-SHA1 salt           ┐ inner / legacy round
  ITER  <int>    PBKDF2-SHA1 iterations      ┘ (default 10,000)
  DPSL  <20 B>   PBKDF2-SHA256 salt          ┐ outer / heavy round
  DPIC  <int>    PBKDF2-SHA256 iterations     ┘ (default 10,000,000, iOS 10.2+)

PER PROTECTION CLASS (repeats)
  UUID  <16 B>   class-key UUID
  CLAS  <int>    protection class 1..11 (A/B/C/D + keychain classes)
  WRAP  <int>    wrap flags for THIS key    ← the field that decides portability
  KTYP  <int>    0 = AES (symmetric), 1 = Curve25519 (asymmetric, class B)
  WPKY  <40 B>   Wrapped Per-class KeY (RFC 3394 of a 32-byte key)
  PBKY  <var>    public key (asymmetric classes only)
```

The `WRAP` flag on each class key is the **mechanical** reason a backup is portable-and-crackable while the device's own keybag is neither:

| `WRAP` | Class key wrapped with | Seen on |
|---|---|---|
| `1` | device **UID-derived** key only | on-device `NSFileProtectionNone` (Class D) |
| `2` | **passcode/password-derived** key only | **every `BackupKeyBag` class key** |
| `3` | **both** UID **and** passcode | on-device protected classes (A / B / C) |

Draw the crux out: the on-device system keybag wraps its protected class keys with `WRAP = 3` (UID **and** passcode), so even a *correct* passcode guess is inert without the SEP that holds the UID. The `BackupKeyBag` deliberately re-wraps the *same* logical class keys with `WRAP = 2` — **password only, no UID** — because a backup must be restorable onto a *different* phone. That one flag is what moves the secret from hardware-bound to software-bound, and it is precisely why the backup is the surface a GPU can attack.

> 🔬 **Forensics note:** Decode the keybag and read `TYPE`, `DPIC`, and the per-class `WRAP` *before* you launch hashcat. `TYPE = 1` confirms a backup keybag; `DPIC ≈ 10,000,000` confirms the strong iOS 10.2+ KDF (mode `-m 14800`); `WRAP = 2` on every class key confirms the bag is password-only and therefore offline-attackable. Thirty seconds of TLV parsing tells you the job is "wordlist a likely-weak password," not "brute a hardware-bound passcode" — the single most consequential triage call in this lesson.

### The double-PBKDF2 — why the iteration count is the entire game

Pre-iOS-10 backups derived the keybag-unwrap key with **PBKDF2-HMAC-SHA1, 10,000 iterations**. That is cheap on a modern GPU. Apple's iOS 10.0/10.1 release infamously *regressed* — ElcomSoft showed in 2016 it had dropped to effectively a single fast SHA-256, crackable **~2,500× faster** than the old scheme. **iOS 10.2** fixed it by stacking a heavy outer round on top, and that two-layer construction is what every backup since (through iOS/iPadOS 26) uses:

```
key = PBKDF2-HMAC-SHA1(
          PBKDF2-HMAC-SHA256( password, DPSL, DPIC=10_000_000, dkLen=32 ),   ← the expensive layer
          SALT, ITER=10_000, dkLen=32 )                                       ← legacy layer kept for compat
```

- **`DPIC` (Data Protection Iteration Count) = 10,000,000** SHA-256 rounds is the brake. **`DPSL`** is its salt. The inner result is then run through the legacy SHA-1 × **`ITER` (10,000)** with **`SALT`**. All four values are in the plaintext `Manifest.plist`/`BackupKeyBag`, so the attacker has everything except the password.
- Ten million SHA-256 iterations means roughly **~180 guesses/second on a single NVIDIA RTX 4060** for an iOS 10.2–26 backup — versus **~233,000 guesses/second** for the pre-10 SHA-1 × 10,000 scheme on the same card. Re-verify exact throughput for your GPU and `hashcat` build; the *ratio* (three to four orders of magnitude slower) is the durable point.

The practical consequence: a high-entropy backup password (long, random) is **infeasible** at 180 H/s — a 10-character random alnum password is ~10^18 candidates, heat-death territory. But a backup password that is a dictionary word, a name+year, a reused login password, or left at a short PIN falls to a wordlist + rules run in minutes to hours. **You are not attacking the algorithm; you are attacking the human's password choice.** That is exactly why this surface is fruitful and the SEP-bound passcode is not.

Make the math concrete — wall-clock to *exhaust* each shape at ~180 H/s against an iOS 10.2+ backup (real cracks usually hit far sooner, since the right candidate rarely sits at the end of the keyspace):

| Backup password shape | Candidate space | Exhaust @ ~180 H/s |
|---|---|---|
| 4-digit PIN (`1234`) | 10⁴ | **< 1 minute** |
| 6-digit PIN | 10⁶ | **~1.5 hours** |
| dictionary word + year (`Summer2019`) | in a good wordlist + rules | **minutes–hours** |
| `rockyou` + `best64` (≈10⁹ effective) | ~10⁹ | ~2 months (but a hit lands early if present) |
| 8-char random alnum | 62⁸ ≈ 2×10¹⁴ | **~38,000 years** |
| 10-char random alnum | 62¹⁰ ≈ 8×10¹⁷ | heat-death |

The cliff between the shaded-feasible rows and the geologic ones is *entirely* password entropy — the KDF cost is identical across every row. Your job is to drag the subject's actual password up into the feasible band with targeted wordlists (their other recovered credentials, breach corpora, names, dates) before resorting to masks.

### Off-device backup-password attack: extract → hashcat

You don't feed `hashcat` a whole backup. You extract the salts, iteration counts, and the wrapped key from `Manifest.plist` into hashcat's hash string, then run a mode-specific kernel:

| hashcat mode | Target | KDF in the kernel |
|---|---|---|
| **`-m 14700`** | **iTunes Backup < 10.0** | PBKDF2-HMAC-SHA1 × 10,000 |
| **`-m 14800`** | **iTunes Backup ≥ 10.0** (incl. the iOS 10.2+ double-PBKDF2; `DPIC`/`DPSL` ride in the hash) | double PBKDF2 (SHA-256 × `DPIC` → SHA-1 × `ITER`) |

> ⚠️ **Common miscite — do not use `-m 14900` for backups.** hashcat **`-m 14900` is Skip32**, an unrelated block-cipher mode that has nothing to do with iTunes backups; feeding it a backup hash silently "works" and never cracks. The pair you want is **`14700` (pre-10)** and **`14800` (10.0+, the modern one for any iOS 26 backup)**. If a guide or an older note tells you 14900, it is wrong.

The `-m 14800` hash string is `$itunes_backup$*<version>*<WPKY>*<ITER>*<SALT>*<DPIC>*<DPSL>` (fields asterisk-delimited). The leading **`<version>`** field is the format tag, not the iOS version: **`10`** is the ≥10.0 format (the `-m 14800` one), **`9`** is the <10.0 format (the `-m 14700` one). Within the `version 10` format, `DPIC`/`DPSL` are populated for iOS 10.2+ backups and left empty (`*…*10000*<SALT>**`) for the iOS 10.0–10.1 era that predates the double-PBKDF2. `philsmd/itunes_backup2hashcat` parses `Manifest.plist` and emits exactly this.

> 🔬 **Forensics note:** Because the iteration counts are *embedded in the hash*, the same `-m 14800` run transparently handles both a strong iOS 10.2+ backup (`DPIC = 10,000,000`, ~180 H/s) and a weak iOS 10.0/10.1-era backup (low `DPIC`, fast). Always read `DPIC` out of the extracted hash *before* you commit GPU-hours — it is your up-front estimate of feasibility. A `DPIC` near ten million tells you only a wordlist attack on a likely-weak password is worth it; full brute force is hopeless.

### The on-device passcode wall — the sharp contrast

Now the problem you *cannot* take off-device. The device passcode is not hashed with a portable salt; it is **entangled with the SEP's fused UID** inside the Secure Enclave, through a KDF Apple calibrated so one guess costs **~80 ms** of real SEP time. Three facts make off-device attack a non-starter and on-device attack a tarpit:

1. **The UID never leaves the SEP.** It is fused at manufacture and is not software-readable — not by the kernel, not by a `checkm8`/`usbliter8` BootROM exploit, not by anything. So the KDF input you'd need to run PBKDF2-style on a GPU literally does not exist outside that one chip. There is no salt-plus-iterations you can lift from an image. Off-device passcode brute force is **impossible**, full stop.
2. **On-device guessing is serialized and throttled.** Even *with* AP code execution below the OS, every attempt must round-trip through the SEP at ~80 ms, and the SEP enforces **escalating delays** and, if the user enabled it, **Erase Data after 10 failed attempts** — a crypto-shred of Effaceable Storage. A 6-digit passcode is 10^6 candidates; at 80 ms serialized that is ~22 hours *if there were no throttle*, and the throttle plus wipe counter is exactly what removes "if."
3. **A BootROM exploit is code-exec, not a key.** `checkm8` (A8–A11) and `usbliter8` (A12–A13, public 2026-06-18) get you running below signature checks, but they do **not** defeat the SEP throttle or hand you the UID. On **A14+ there is no public BootROM exploit at all**. The GrayKey/Cellebrite-class on-device passcode attack is a separate, SEP-side problem with no public solution on modern silicon.

> ⚠️ **ADVANCED — on-device passcode guessing is irreversible-risk.** Every guess in an on-device passcode attack increments the SEP's failed-attempt counter on the *original* evidence, and if the owner enabled "Erase Data" the 10th miss crypto-shreds Effaceable Storage — the data you were authorized to examine is gone, unrecoverably. There is no "undo," no offline retry, and no way to clone the SEP state first. Never improvise this against an original device: capture an image/backup, work the *backup password* offline, and only run a passcode attack under a documented methodology that explicitly accepts the wipe risk in scope.

So the contrast is total. The backup password protects a keybag whose *every input* (salts, iteration counts, wrapped keys) is sitting in files you copied — pure offline math, bounded only by password entropy. The device passcode protects a keybag whose *root input* is welded into hardware you don't possess, behind a rate limiter you can't outrun. **One is arithmetic; the other is physics.**

> ⚖️ **Authorization:** Cracking a *backup password* on lawfully-acquired backup files (under a warrant or consent that covers the data) is offline analysis of evidence in your possession. Attempting to brute the *device passcode* engages the SEP try-counter on original evidence and can trigger the user's 10-try wipe — destroying the very data you're authorized to examine. Never run a passcode attack against an original device; the authorized path is to capture an image/backup first and attack *that* offline, and to document that any on-device acquisition was performed within the scope and methodology your authority defines.

### Decrypt-then-parse — the backup workflow

Decryption gets you readable bytes; it does **not** get you findings. The pipeline is two distinct stages, and conflating them is how people "decrypt a backup" and then stare at a folder of hashes:

```
STAGE 1 — decrypt              STAGE 2 — parse
─────────────────              ────────────────
crack/known password  ─┐
encrypted backup dir  ─┼─► decrypted backup  ─► Manifest.db is plaintext
Manifest.plist keybag ─┘   (hash-named blobs       │
                            now plaintext;         ├─► iLEAPP -t itunes → HTML/CSV artifact report
                            Manifest.db maps       ├─► mvt-ios          → STIX2 / IOC check, JSON
                            them to domains)       └─► sqlite3          → targeted queries (sms.db, …)
```

- **Stage 1 (decrypt).** Given the password, a tool unwraps the `BackupKeyBag`, decrypts `Manifest.db`, then per file unwraps the per-file key and decrypts the blob. `mvt-ios decrypt-backup` is the standard — but note it writes the decrypted files back under the *same* hash-named, 2-char-sharded layout (`<dest>/<fileID[0:2]>/<fileID>`), now plaintext, alongside a decrypted `Manifest.db` that is the `fileID`→domain/relativePath map; it does **not** rebuild a human-readable domain tree. Tools that additionally *reconstruct* a `HomeDomain/Library/...` tree do it as a separate extract step — `iphone_backup_decrypt`'s `--extract`, `idevicebackup2 unback`, or `iOSbackup`'s `getFileDecryptedCopy()`; Elcomsoft Phone Breaker is the commercial equivalent.
- **Stage 2 (parse).** Now `Manifest.db` is readable and the blobs are real bytes. Point **iLEAPP** (Brignoni) at the decrypted backup with **`-t itunes`** (the mode that reads `Manifest.db` to resolve the hash names — `-t fs` is for a real-path filesystem tree and will find nothing in a hash-named backup), or run **mvt-ios** over it, or query individual databases with `sqlite3` (copy-before-query still applies — a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`).

> 🔬 **Forensics note:** `Manifest.db.Files` is itself a powerful triage index *after* decryption — it lists every file's `domain`, `relativePath`, and (inside the `MBFile` bplist) `Size`, `LastModified`/`Birth` (Unix epoch), `Mode`, and `ProtectionClass` — *before* you open a single artifact database. A `SELECT domain, count(*), sum(...) GROUP BY domain` tells you instantly whether a target app, the camera roll, or a messaging container is even present in this backup, and how big. Selective backups, app-uninstalls, and "Optimize Storage" all show up here as missing or truncated domains.

### Decrypting a full-file-system image with recovered class keys

A backup is the *easy* decrypt because the password is your way in. A **full-file-system (FFS) image** — the kind a `checkm8`/`usbliter8` or agent-based AFU acquisition produces — is different: there is no backup password, and the encryption is the *device's* Data Protection, rooted in `passcode ⊗ UID`. You can only decrypt an FFS image's protected files if the acquisition **captured the class keys** while they were resident (AFU) or recovered them via the passcode on-device. The image alone, with no keys, is a **BFU** problem: you get Class D and structure, nothing else (see [[02-bfu-vs-afu-and-data-protection-classes]]).

So the FFS decrypt path assumes the keys came *with* the image:

```
FFS image (APFS)            keybag + unwrapped class keys
   │  per-file wrapped key      (captured AFU, or passcode supplied on-device)
   │  in j_crypto_val_t /            │
   │  wrapped_crypto_state_t         │
   ▼                                 ▼
read persistent_class       commercial FFS suite / DP-aware script
(libfsapfs, NO key)    ── unwrap per-file key with class[persistent_class] ──► plaintext extent
   triage only
```

Two different tools sit on those two arrows, and conflating them is the trap. **`libfsapfs` reads every file's `persistent_class` straight out of the `wrapped_crypto_state_t` with no key at all**, so you can triage what *would* be recoverable — that is its job here. But its `fsapfsinfo`/`fsapfsmount` `-p`/`-r` flags take an APFS-volume *passphrase* (and unlock **FileVault/volume-level** APFS encryption, password → volume key); libfsapfs exposes **no CLI option to inject captured iOS class keys**, and lists T2/hardware encryption as unsupported (verify against your libyal release). The actual iOS per-file decrypt — unwrap each per-file key with `class[persistent_class]`, then AES-decrypt the extent — is what the **commercial FFS tools** (Cellebrite, GrayKey, Elcomsoft iOS Forensic Toolkit) implement: their agent or BootROM workflow extracts the keybag and resident class keys at acquisition time, then decrypts the image with them. **The keys are the artifact**; the ciphertext image without them is a BFU image no matter how it was obtained.

> 🔬 **Forensics note:** This is the cleanest way to state the difference in a report. *A decrypted backup proves you had the backup password.* *A decrypted FFS image proves the acquisition captured the device's class keys — which proves the device was AFU (or the passcode was known/supplied) at acquisition.* The decryptability of each artifact is itself evidence of the lock-state and authority under which it was obtained.

### What is crackable vs what is not — the bottom line

Burn this hierarchy in, because it is what you put in front of a court:

| Artifact | Crackable off-device? | Why |
|---|---|---|
| Encrypted backup, **weak** password | **Yes** — wordlist/rules, minutes–hours | PBKDF2 runs on your GPU; entropy is the only brake, and it's low |
| Encrypted backup, **strong** password | **No** (practically) | 10M-iter PBKDF2 × high entropy = infeasible |
| Unencrypted backup | **Trivially** (nothing to crack) | No backup keybag; per-file keys aren't password-wrapped |
| **AFU** FFS image with captured keys | Already decryptable | Class keys came with the image |
| **BFU** FFS image, no keys | **No** | Rooted in `passcode ⊗ UID`; passcode is SEP-bound |
| **Device passcode** itself | **No** off-device; SEP-throttled on-device | UID never leaves the SEP; ~80 ms + wipe counter |

The one green cell that pays the rent is the weak backup password. Everything else is either already-solved (you had the key) or hardware-bound (you never will, off-device).

## Hands-on

There is no on-device shell and the Simulator makes no real encrypted backups, so everything here runs **on the Mac** against a **public sample encrypted backup** (e.g. an mvt/iLEAPP test backup, or a backup you generate from a sample image with a *known* password) or against `Manifest.plist` directly. Nothing here attacks a device you don't have keys for.

### 1. Read the backup's posture without cracking anything

```bash
# Is it even encrypted? (true → the BackupKeyBag + ManifestKey are in play)
plutil -extract IsEncrypted xml1 -o - "$BK/Manifest.plist"          # → true / false

# Pull the iteration counts straight out of the plaintext plist:
plutil -p "$BK/Manifest.plist" | grep -iE 'ManifestKey|BackupKeyBag|IsEncrypted'
# The BackupKeyBag is base64 TLV; ITER/DPIC live inside it (and in the hashcat hash below).
```

Expected: `IsEncrypted => 1`, a long base64 `BackupKeyBag`, and a `ManifestKey` blob. That `true` is your signal that Stage 1 needs a password.

Decode the `BackupKeyBag` TLV yourself to read `TYPE` / `DPIC` / per-class `WRAP` straight from the bytes — no cracking, no tool, just the plaintext header:

```bash
python3 - "$BK/Manifest.plist" <<'PY'
import sys, plistlib, struct
bag = plistlib.load(open(sys.argv[1], 'rb'))['BackupKeyBag']
i = 0
while i + 8 <= len(bag):
    tag = bag[i:i+4].decode('ascii', 'replace')
    ln  = struct.unpack('>I', bag[i+4:i+8])[0]
    val = bag[i+8:i+8+ln]; i += 8 + ln
    if tag in ('VERS', 'TYPE', 'WRAP', 'ITER', 'DPIC', 'CLAS', 'KTYP'):
        print(tag, struct.unpack('>I', val.rjust(4, b'\0')[-4:])[0])
    else:
        print(tag, val.hex())
PY
# TYPE 1  → backup keybag ; DPIC 10000000 → strong (use -m 14800) ;
# WRAP 2 under each CLAS → password-only, offline-attackable
```

### 2. Extract the hashcat hash and read the iteration count *before* spending GPU-hours

```bash
git clone https://github.com/philsmd/itunes_backup2hashcat && cd itunes_backup2hashcat
perl itunes_backup2hashcat.pl "$BK/Manifest.plist"
# → $itunes_backup$*10*<WPKY>*10000*<SALT>*10000000*<DPSL>
#                    ^version 10 = ≥10.0 fmt    ^ITER     ^DPIC=10,000,000  ← the brake
```

Read `DPIC` (here `10000000`): this is a modern, strong-KDF backup — only a *wordlist* on a likely-weak password is worth running; full brute force is hopeless.

### 3. Crack a weak backup password with hashcat (the realistic attack)

```bash
echo '$itunes_backup$*10*<WPKY>*10000*<SALT>*10000000*<DPSL>' > backup.hash

# Wordlist + rules — the only sane strategy at ~180 H/s for a 10M-iteration backup:
hashcat -m 14800 backup.hash rockyou.txt -r rules/best64.rule -O -w 3

# Pre-iOS-10 backup instead? Different mode, ~1000× faster:
hashcat -m 14700 old_backup.hash rockyou.txt -r rules/best64.rule -O -w 3
```

Expected: on a strong password, `Exhausted` after the wordlist (no hit — and that *is* a finding: the password wasn't in your dictionary). On a weak one, the cracked password prints next to the hash, and a `--show` re-reads it from the potfile.

### 4. Stage 1 — decrypt the backup once you have the password

```bash
python3 -m pip install mvt
export MVT_IOS_BACKUP_PASSWORD='the_password'        # avoids password on the command line
mvt-ios decrypt-backup -d /out/decrypted "$BK"       # decrypts blobs in place: same hash-named layout, plaintext Manifest.db

# Equivalent libraries if you prefer:
#   iphone_backup_decrypt  (python)   — programmatic, per-file extraction
#   iOSbackup              (pip)       — exposes Manifest.db + getFileDecryptedCopy()
```

Expected: `/out/decrypted` now contains a plaintext `Manifest.db` plus the per-file blobs decrypted *in place* — still 2-hex-sharded and hash-named (`<fileID[0:2]>/<fileID>`), but now real file content instead of noise. The blobs are **not** renamed to `HomeDomain/...`; the decrypted `Manifest.db` is the map from each hash back to `HomeDomain/...`/`CameraRollDomain/...` (next step), and an extractor (`idevicebackup2 unback`, `iphone_backup_decrypt --extract`) can rebuild the named tree if you want one.

### 5. Stage 1.5 — use the now-plaintext Manifest.db as a triage index

```bash
cp /out/decrypted/Manifest.db /tmp/manifest.db        # copy-before-query
sqlite3 /tmp/manifest.db "
SELECT domain, count(*) AS n
FROM Files
GROUP BY domain
ORDER BY n DESC
LIMIT 15;"
# Locate a specific artifact's backup path by hash:
sqlite3 /tmp/manifest.db "
SELECT fileID, domain, relativePath
FROM Files
WHERE relativePath LIKE '%sms.db%' OR relativePath LIKE '%CallHistory%';"
```

Expected: a histogram of domains (so you know what the backup even contains) and the `fileID`/path of target databases. `fileID` is the `SHA-1("<domain>-<relativePath>")` — the same name the blob sits under at `<backup>/<fileID[0:2]>/<fileID>` in *both* the encrypted and the (mvt-)decrypted tree.

### 6. Stage 2 — parse the decrypted tree into a report

```bash
# iLEAPP — broad artifact extraction. For a (decrypted) backup use -t itunes; a real
# filesystem/FFS tree would use -t fs instead:
pip install ileapp
python3 ileapp.py -t itunes -i /out/decrypted -o /out/ileapp_report   # -t itunes: reads Manifest.db to resolve the hash-named files

# mvt-ios — IOC/compromise check over the (decrypted) backup, plus record extraction:
mvt-ios check-backup --output /out/mvt /out/decrypted
```

Expected: iLEAPP emits a browsable HTML report (and TSV/KML) across hundreds of artifact modules; mvt-ios emits per-artifact JSON and flags any matches against loaded IOCs. Both consume the *output* of decryption — neither defeats Data Protection itself.

### 7. (FFS) Prove you can read class without keys, and decrypt only with them

```bash
# Build libfsapfs (libyal, Joachim Metz) — not in Homebrew:
git clone https://github.com/libyal/libfsapfs && cd libfsapfs
./synclibs.sh && ./autogen.sh && ./configure && make            # sudo make install

# WITHOUT any key: persistent_class is still readable → triage decryptability
fsapfsinfo -f 1 -E all sample_ffs.raw | grep -i 'Protection class'

# fsapfsmount's -p/-r unlock APFS *volume* (FileVault-style) encryption from a
# pass*PHRASE* — NOT iOS per-file Data Protection from a raw class key:
mkdir -p /tmp/ffs && fsapfsmount -X allow_other -p "$VOLUME_PASSPHRASE" sample_ffs.raw /tmp/ffs
# The iOS per-file class-key decrypt (unwrap per-file key with class[persistent_class])
# is done by the commercial FFS suites / a DP-aware script — libfsapfs has no
# raw-class-key CLI flag and marks T2/hardware encryption unsupported.
```

Expected: the `persistent_class` listing appears even on a BFU image (structure is free); decrypting the actual *content* needs the class keys an AFU/keyed acquisition captured. `fsapfsmount -p` only unlocks a FileVault-style passphrase-encrypted APFS volume — iOS per-file content is decrypted by the keyed commercial workflow — but the keyless `fsapfsinfo` read alone already proves, on the command line, the BFU-vs-AFU divide from [[02-bfu-vs-afu-and-data-protection-classes]].

## 🧪 Labs

> Every lab is device-free. The Simulator does **not** produce real encrypted backups (that needs `idevicebackup2`/Finder against a physical device) and has **no SEP/Data-Protection/keybag**, so these labs use a **public sample encrypted backup** (mvt/iLEAPP test data, or a sample-image-derived backup with a *known* password) and **read-only walkthroughs**. The device-only daemons (`knowledged`/Biome, `routined`, `powerd`) don't populate Simulator stores, but backup decryption is filesystem-and-crypto work that runs entirely on the Mac, so the fidelity loss here is small — you are exercising the *real* `BackupKeyBag`/`Manifest.db`/RFC-3394 chain.

### Lab 1 — Read posture and iteration count from `Manifest.plist` *(substrate: public sample encrypted backup; fidelity caveat: the keybag/salts are real backup bytes — only the password is "known" for teaching, which is exactly what you'd recover via Lab 3 on a weak one)*

1. `plutil -extract IsEncrypted xml1 -o - Manifest.plist` — confirm `true`.
2. Run `itunes_backup2hashcat.pl` and read the emitted hash; identify the `version`, `ITER`, `DPIC`, and `DPSL` fields.
3. State, from `DPIC` alone, whether full brute force is feasible and why a wordlist is the only realistic strategy. Compute the rough wall-clock to exhaust a 6-character random-alnum space at ~180 H/s and at ~233,000 H/s — and explain which `version`/mode each number corresponds to.

### Lab 2 — Map the unwrap chain on paper *(substrate: read-only walkthrough; no device or image needed)*

1. From memory, draw the seven-layer chain: backup password → double-PBKDF2 → keybag-unwrap key → class keys → `ManifestKey` → `Manifest.db` → per-file key → file.
2. For each arrow, name the operation (PBKDF2, RFC 3394 unwrap, AES-CBC) and the input it needs.
3. Mark which two inputs are *plaintext in the backup* (the salts/iterations and the wrapped keys) and the one input that is *not* in the backup (the password). Explain in one sentence why that single missing input is the entire defensive value of the scheme — and why the device passcode's missing input (the UID) can't be supplied at all.

### Lab 3 — Crack a deliberately-weak sample backup *(substrate: a sample encrypted backup whose password is a known dictionary word; fidelity caveat: you are attacking a real `-m 14800` hash with the real KDF — the only contrivance is that the password is weak on purpose, modeling the common real-world case)*

1. Extract the hash with `itunes_backup2hashcat.pl`.
2. Run `hashcat -m 14800 backup.hash rockyou.txt -r rules/best64.rule`. Confirm it recovers the password (and note the H/s rate your hardware reports against the 10M-iteration KDF).
3. Re-run with a *removed* dictionary entry so the password is absent; observe `Exhausted`. Write one line on why "Exhausted" is itself a defensible report statement (the password was not in this dictionary at this ruleset), not "uncrackable."
4. Deliberately run `-m 14900` on the same hash. Observe it fail to crack despite the "correct" password being in the wordlist, and record the lesson: 14900 is **Skip32**, not iTunes backup.

### Lab 4 — Decrypt then parse, end to end *(substrate: the Lab-3 sample backup with its now-known password; fidelity caveat: identical to a real workflow — the password just came from Lab 3 instead of a seizure)*

1. `mvt-ios decrypt-backup` the sample into a clean output dir using the recovered password.
2. `cp Manifest.db` out and run the domain histogram + a `relativePath LIKE '%sms.db%'` lookup. Record the `fileID` and confirm it matches `SHA-1("<domain>-<relativePath>")` for that row.
3. Run **iLEAPP** (`-t itunes`, the mode that reads `Manifest.db` to resolve the hash-named blobs — *not* `-t fs`) over the decrypted backup; open the HTML report and locate one artifact (e.g. Safari history or message threads).
4. Run `mvt-ios check-backup` and note what it does *differently* from iLEAPP (IOC matching / compromise triage vs. broad artifact enumeration).

### Lab 5 — BFU-vs-AFU decryptability on an FFS image *(substrate: public sample full-file-system image via `libfsapfs`; fidelity caveat: you can read every file's `persistent_class` without keys; you can only DECRYPT files whose class key is derivable from material in the image — Class D always, everything only if the image was captured AFU/keyed)*

1. `fsapfsinfo -E all` over the sample image; histogram `persistent_class` (1=A, 2=B, 3=C, 4=D).
2. Predict the decryptable yield for a **no-keys (BFU)** scenario vs an **AFU/keyed** one. Read the keyless `fsapfsinfo` output (structure + every `persistent_class` is free); then note what each substrate needs to actually *decrypt* content — a FileVault-style image takes its volume passphrase via `fsapfsmount -p`, whereas an iOS per-file image needs the keyed commercial workflow (libfsapfs has no raw-class-key flag).
3. Pick one Class-C database; confirm the tool exposes `persistent_class = 3` but cannot decrypt it without the resident class-C key.
4. Write the two-sentence report language: what a decrypted *backup* proves about your authority/holdings vs. what a decrypted *FFS image* proves about the device's lock-state at acquisition.

## Pitfalls & gotchas

- **`-m 14900` is not iTunes backup — it is Skip32.** The correct modes are **`14700`** (pre-iOS-10) and **`14800`** (iOS 10.0+, the one for any iOS 26 backup). 14900 will appear to "run" and never crack. This is the single most common backup-cracking miscite; reject any note or guide that says 14900.
- **Attacking the wrong secret.** The crackable string is the **backup password**, not the **device passcode**. Off-device passcode brute force is impossible (UID never leaves the SEP); on-device is SEP-throttled with a wipe counter. Pointing a GPU at a passcode wordlist is a category error that cannot succeed.
- **Reading the `DPIC` after committing GPU-hours.** Read the iteration count *first*. `DPIC ≈ 10,000,000` means full brute force is hopeless and only a wordlist on a weak password is worth running — decide feasibility before you burn the cluster.
- **"Decrypted" ≠ "parsed."** `mvt-ios decrypt-backup` gives you readable bytes and a plaintext `Manifest.db`; it does **not** produce findings. You still have to run iLEAPP/mvt/`sqlite3` over the decrypted tree. People routinely stop at Stage 1 and think they're done.
- **Expecting filenames in a backup — even a decrypted one.** Files are stored by `SHA-1("<domain>-<relativePath>")`, sharded into 2-hex subdirectories. Until `Manifest.db` is decrypted you have no name→hash map, so a folder of hash-named blobs is the *normal* encrypted state, not corruption. **Decryption does not rename them either:** `mvt-ios decrypt-backup` leaves the same hash-named, 2-char-sharded layout in place (just plaintext now) with a decrypted `Manifest.db` as the map. Parse that with iLEAPP **`-t itunes`** (it consults `Manifest.db`), *not* `-t fs` (which expects real paths and will silently find nothing). You only get a `HomeDomain/...` tree by running a separate extract step (`idevicebackup2 unback`, `iphone_backup_decrypt --extract`).
- **`ThisDeviceOnly` keychain items missing from the decrypted backup.** They were UID-bound and never re-wrapped into the `BackupKeyBag`, so they cannot be in the backup. Their absence is by design — don't chase it as a decrypt failure.
- **An *unencrypted* backup is the soft underbelly — and is *less* informative for some items.** No backup keybag means trivially readable files, but Apple deliberately **excludes** some sensitive data (most keychain secrets, health/HomeKit) from *unencrypted* backups and only includes them when encryption is on. An encrypted backup with a known/cracked password can therefore contain *more* than an unencrypted one. Note the encryption flag as evidence of scope.
- **Decrypting an FFS image without the keys.** An FFS image is the device's own Data Protection, not a password scheme. With no captured class keys it is a **BFU** problem — Class D and structure only. The keys must have come *with* the image (AFU/keyed acquisition); you cannot crack them out of the image.
- **WAL/size-mismatch on decrypted SQLite.** Some tools mis-decrypt files whose `Manifest.db`-recorded size disagrees with the on-disk blob (notably `-wal`/`-shm` sidecars), yielding truncated or garbled databases. Verify a decrypted SQLite opens and `PRAGMA integrity_check`s clean; re-extract the specific file if not.
- **Copy-before-query survives decryption.** Once `Manifest.db` and the artifact databases are plaintext, they are ordinary SQLite — a bare `SELECT` still write-locks and spawns `-wal`/`-shm`. Copy each database before querying, exactly as in the macOS artifact lessons.
- **Throughput numbers are perishable.** The ~180 H/s (RTX 4060, iOS 10.2+) and ~233,000 H/s (pre-10) figures and the 2,500× iOS-10-regression ratio are dated benchmarks — re-verify on your hardware and current hashcat. The *durable* fact is the three-to-four-order-of-magnitude gap the 10M-iteration outer round buys.
- **Format stability — verify, don't assume.** The `BackupKeyBag` TLV layout and the double-PBKDF2 (`DPIC = 10,000,000`) have been unchanged from **iOS 10.2 through iPadOS/iOS 26.x**, and `-m 14800` covers all of it. No new KDF parameter has shipped as of 2026-06, but treat that as a *checked* fact, not a permanent one: re-decode a fresh `Manifest.plist`'s keybag and confirm `DPIC`/`VERS` before scripting a job against a new OS release.

## Key takeaways

- **There are two unwrap problems and only one is solvable off-device:** the user-chosen **backup password** (offline-attackable, weak in practice) versus the **device passcode** (`passcode ⊗ UID`, SEP-bound, impossible off-device and rate-limited on-device).
- An encrypted backup re-wraps everything into a **portable `BackupKeyBag` (`TYPE=1`)** protected by the backup password; the chain is **password → double-PBKDF2 → class keys → `ManifestKey` → `Manifest.db` → per-file keys → files**, with every input except the password sitting in plaintext backup files.
- The **double-PBKDF2** (PBKDF2-SHA256 × **`DPIC` 10,000,000**, then PBKDF2-SHA1 × **`ITER` 10,000**) since **iOS 10.2** is the entire defense: ~180 H/s vs ~233,000 H/s pre-10. You attack the human's password choice, not the algorithm.
- hashcat **`-m 14800`** (iOS 10.0+) and **`-m 14700`** (pre-10) are the modes; **`-m 14900` is Skip32 and wrong**. `itunes_backup2hashcat` builds the hash from `Manifest.plist`; read `DPIC` before spending GPU time.
- **Decrypt is Stage 1; parse is Stage 2.** `mvt-ios decrypt-backup` decrypts the blobs *in place* — same hash-named, 2-char-sharded layout, now plaintext, plus a plaintext `Manifest.db` (it does not rebuild a domain tree). Then iLEAPP (`-t itunes`, not `-t fs`) / mvt-ios / `sqlite3` produce findings. `Manifest.db.Files` (`fileID`=SHA-1 of `domain-relativePath`, plus the `MBFile` bplist's `ProtectionClass`/`Size`/`LastModified`) is your post-decrypt triage index.
- An **FFS image** is decrypted with **class keys captured at acquisition** (AFU/keyed), not a password; with no keys it's a **BFU** image (Class D + structure only). The keys are the artifact.
- **macOS muscle memory is half-right:** the backup password is like a FileVault recovery key — one offline unwrap path — but the device passcode has *no* off-device recovery-key analogue, because its root is the non-exportable UID, not an escrowable master key.
- **State the line defensibly:** weak backup password = crackable; strong backup password / BFU image / device passcode = not, off-device. A decrypted backup proves you had the password; a decrypted FFS image proves the device was AFU/keyed at acquisition.

## Terms introduced

| Term | Definition |
|---|---|
| `BackupKeyBag` | The keybag (`TYPE = 1`) minted for an encrypted backup; re-wraps migratory class keys to the backup password; stored base64 in `Manifest.plist` |
| TLV (Type-Length-Value) | The big-endian 4-byte-tag / 4-byte-length / value encoding of an iOS keybag (`VERS`/`TYPE`/`SALT`/`ITER`/`DPSL`/`DPIC` header + per-class `CLAS`/`WRAP`/`KTYP`/`WPKY`) |
| `WRAP` flag | Per-class-key wrap policy: `1` = UID-derived only, `2` = passcode/password-derived only, `3` = both; backups use `2` (portable), on-device protected classes use `3` (hardware-bound) |
| `WPKY` / `KTYP` | Wrapped Per-class KeY (RFC 3394 of a 32-byte key) and its key type (`0` = AES, `1` = Curve25519) |
| Backup password | The user-chosen string that, via PBKDF2, unwraps the `BackupKeyBag`; the only practically-crackable iOS unwrap secret |
| Double-PBKDF2 | iOS 10.2+ backup KDF: `PBKDF2-SHA1(PBKDF2-SHA256(pwd, DPSL, DPIC), SALT, ITER)` |
| `DPIC` / `DPSL` | Data Protection Iteration Count (10,000,000 SHA-256 rounds) and its salt — the expensive outer KDF layer |
| `ITER` / `SALT` | Legacy PBKDF2-SHA1 iteration count (10,000) and salt — the inner/compat layer |
| hashcat `-m 14800` | hashcat mode for iTunes/Finder backups ≥ iOS 10.0 (handles the iOS 10.2+ double-PBKDF2) |
| hashcat `-m 14700` | hashcat mode for iTunes backups < iOS 10.0 (PBKDF2-SHA1 × 10,000) |
| `itunes_backup2hashcat` | philsmd tool that parses `Manifest.plist` into a hashcat-cracking hash string |
| `ManifestKey` | A class-wrapped file key (4-byte LE class# prefix + wrapped key) in `Manifest.plist` that AES-CBC-decrypts `Manifest.db` |
| `Manifest.db` | SQLite index of an iOS backup; encrypted as a whole (iOS 10.2+); its `Files` table maps `fileID` → domain/path + `MBFile` metadata |
| `fileID` | `SHA-1("<domain>-<relativePath>")`; the hash filename a backup file is stored under (sharded by first 2 hex chars) |
| `MBFile` | NSKeyedArchiver bplist in `Files.file` carrying `ProtectionClass`, the wrapped `EncryptionKey`, `Size`, `LastModified`, `Mode`, … |
| `mvt-ios decrypt-backup` | Mobile Verification Toolkit command that performs Stage-1 backup decryption given the password |
| iLEAPP | Brignoni's iOS Logs/Events/Properties Parser; Stage-2 artifact extraction over a decrypted backup or FFS tree |
| FFS image | Full-file-system image; decrypted with device class keys captured at acquisition (AFU/keyed), not a backup password |

## Further reading

- **Apple Platform Security guide** — *Keybags for Data Protection* (the `BackupKeyBag`/escrow taxonomy) and *Encrypted backups* (support.apple.com/guide/security) — read the edition matching your target OS.
- **hashcat** — `man hashcat`, the example-hashes list (modes 14700/14800), and the wiki on backup hash formats (hashcat.net).
- **philsmd, `itunes_backup2hashcat`** (github.com/philsmd/itunes_backup2hashcat) — the `Manifest.plist` → hash extractor and its README's field-by-field hash-format breakdown.
- **ElcomSoft blog** — the iOS 10.0/10.1 backup-encryption regression ("2,500× faster") and the iOS 10.2 double-PBKDF2 fix; Phone Breaker / iOS Forensic Toolkit write-ups on backup and FFS decryption throughput.
- **Rich Infante**, *Reverse Engineering the iOS Backup* (richinfante.com, 2017) — `Manifest.db`/`Manifest.plist`, the `MBFile` keyed-archive, `fileID` derivation, and the class-key unwrap path.
- **dunhamsteve/ios** (github.com/dunhamsteve/ios) — compact, readable backup + keychain extraction implementing the full unwrap chain; good source-of-truth for the RFC-3394 steps.
- **VulBusters**, *iOS Data Protection on Backup* (Medium) — the `ManifestKey`/`ProtectionClass`/per-file-key unwrap sequence with the AES-CBC + RFC-3394 specifics.
- **Mobile Verification Toolkit (mvt)** docs (docs.mvt.re) — `decrypt-backup` / `check-backup`, `MVT_IOS_BACKUP_PASSWORD`, and the records it extracts.
- **Alexis Brignoni**, iLEAPP (github.com/abrignoni/iLEAPP) and the `iOSbackup`/`iphone_backup_decrypt` Python libraries — Stage-2 parsing and programmatic per-file decryption.
- **`libfsapfs`** (Joachim Metz / libyal) — `fsapfsinfo`/`fsapfsmount` for keylessly reading `persistent_class` out of the `wrapped_crypto_state_t`, and for unlocking FileVault/volume-level APFS encryption from a `-p`/`-r` passphrase (it has no raw-class-key flag and marks T2/hardware encryption unsupported).
- **Bédrune & Sigwald**, *iPhone Data Protection in Depth* / `iphone-dataprotection` — the canonical keybag TLV + class-number reference underpinning both device and backup keybags.
- **Satish Bommisetty et al.**, *Practical Mobile Forensics* (4th ed.) — the `Manifest.db` schema and backup-analysis workflow in a forensic frame.

---
*Related lessons: [[03-the-itunes-finder-backup-format]] | [[02-data-protection-and-keybags]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[03-passcode-bfu-afu-and-inactivity]] | [[05-full-file-system-acquisition]] | [[06-icloud-acquisition-and-advanced-data-protection]] | [[04-logical-acquisition-with-libimobiledevice]] | [[08-keychain-on-ios]] | [[08-acquisition-sop-and-chain-of-custody]]*
