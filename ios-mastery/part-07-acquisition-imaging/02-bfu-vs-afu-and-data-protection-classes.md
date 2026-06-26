---
title: "BFU vs AFU & Data Protection classes"
part: "07 — Forensic Acquisition & Imaging"
lesson: 02
est_time: "45 min read + 20 min labs"
prerequisites: [data-protection-and-keybags, the-acquisition-taxonomy]
tags: [ios, forensics, bfu, afu, data-protection, dfir]
last_reviewed: 2026-06-26
---

# BFU vs AFU & Data Protection classes

> **In one sentence:** On iOS the volume is *always* "mounted," so the only thing that decides what you can read is the cross-product of **device lock state** (BFU / AFU-locked / AFU-unlocked) and **Data Protection class** (A/B/C/D) per file — and a 72-hour inactivity-reboot clock plus a ~1-hour USB clock are silently shrinking that readable set from the moment of seizure.

## Why this matters

On the learner's Mac, FileVault is a binary: the volume is either locked (you have ciphertext and a recovery-key problem) or unlocked (you have everything). iOS does not work like that, and assuming it does is the single most expensive mistake in mobile acquisition. An iPhone that is sitting on your bench with the lock screen showing has *most* of its keys resident in RAM — it is nothing like a locked FileVault volume — but a different iPhone that rebooted forty minutes ago and is showing the identical lock screen has almost *no* user keys resident. Same UI, same "mounted" filesystem, wildly different evidentiary value.

This lesson turns [[passcode-bfu-afu-and-inactivity]] from a security-model fact into an operational decision procedure. By the end you will be able to look at a seized device, classify its state, predict exactly which artifacts will decrypt, and read the two countdown clocks that are racing to take that data away from you. Getting this wrong means waiting three days for a tool update and watching the device crypto-shred itself back to BFU; getting it right means you isolate, power, and preserve correctly in the first ten minutes.

## Concepts

### The macOS reflex that will burn you

> 🖥️ **macOS contrast:** FileVault on Apple Silicon is one lock for the whole **Data** volume. The volume encryption key (the VEK/"media key") is either wrapped-and-absent (pre-boot, you see the unlock screen) or unwrapped-and-resident (you typed the password, the SEP released it, every file is plaintext). There is exactly one bit of state and it applies to *all* user data uniformly. iOS inverts this: the filesystem is *always mounted and "decrypted enough to boot"* even at the lock screen, and encryption is **per-file** with **four different key-availability policies**. "The volume is mounted" tells you almost nothing on iOS — you have to ask, per file, *which class key protects it and is that class key currently in memory?*

### Per-file keys and the wrapping chain

Every file on the iOS Data volume gets its own random **per-file key** (AES-256) at creation. That key encrypts the file's contents. The per-file key is then **wrapped** (key-encrypted) by one of four **class keys** and the wrapped blob is stored in the file's metadata — the `cprotect` attribute carried in the APFS extended-attribute/inode metadata. The file *metadata itself* is encrypted with a volume-wide **metadata key** that lives in **Effaceable Storage** (a small, securely-eraseable NAND region — see [[storage-nand-aes-effaceable]]); wiping that one key is what makes "Erase All Content and Settings" instantaneous (crypto-shred).

```
File contents
  └─ AES-256 (XEX/XTS) under  →  PER-FILE KEY
        └─ AES key-wrap under  →  CLASS KEY  (A, B, C, or D)   ── stored in file `cprotect`
              (the cprotect metadata is itself encrypted by the
               volume METADATA KEY held in Effaceable Storage — the crypto-erase target)

  CLASS KEYS live in the SYSTEM KEYBAG (see [[data-protection-and-keybags]]):
     Class D key   ── wrapped by:  UID-derived key  ONLY            → available at BFU
     Class A/B/C   ── wrapped by:  passcode ⊗ UID  (SEP-entangled)  → available only after 1st unlock
```

The whole game is in that last block. The class keys are stored in the **system keybag**, and *how each class key is wrapped* is what makes BFU and AFU different states:

- **Class D key** is wrapped using only a key derived from the hardware **UID** (fused into the SoC/SEP, never extractable). The SEP can unwrap it the instant the device powers on, with **no passcode**. So Class D data is readable in *every* state, including a freshly-booted, never-unlocked device.
- **Class A / B / C keys** are wrapped using a key the SEP derives by **entangling the passcode with the UID**. The SEP will only produce that key after the user (or you) has entered the correct passcode at least once since boot. Until then those three class keys are mathematically unavailable — the SEP literally cannot compute them, and it rate-limits guessing (escalating delays enforced inside the SEP; see [[sep-sepos-deep-dive]]).

So **BFU vs AFU is not a UI state — it is "has the SEP unwrapped the A/B/C class keys since the last boot?"** First correct passcode entry flips that bit. A reboot (or inactivity reboot, or kernel panic, or power loss) clears it.

### The four Data Protection classes

| Class | API name (`NSFileProtection…`) | Key available when | Typical use |
|---|---|---|---|
| **A** | `Complete` | Only while **unlocked**; key **evicted shortly after lock** | Highest-sensitivity data that should be sealed the moment the screen locks (Apple uses it for some Mail/Health data) |
| **B** | `CompleteUnlessOpen` | Can **create/write while locked** (public key resident); cannot **reopen a closed file while locked** (private key evicted at lock) | Background downloads: a mail attachment that arrives while the phone is in your pocket |
| **C** | `CompleteUntilFirstUserAuthentication` | Key resident **from first unlock until reboot** (survives subsequent locks) | **The default** for third-party app data since iOS 7 — and therefore most of what you want |
| **D** | `None` | **Always** (key wrapped by UID only) | Data that must work before first unlock: bits of system state, some caches |

Class B uses an elliptic-curve (Curve25519) construction: the per-file key is wrapped to the class's **public** key via an ephemeral ECDH, so anything can *create* a Class B file even while locked, but *decrypting* a closed one needs the class **private** key, which is treated like a Class A key and discarded at lock.

> 🔬 **Forensics note:** **Class C is the default, and Class C is the whole reason AFU acquisition is so productive.** Almost all third-party app databases, caches, and containers are Class C. The Class C key is loaded at first unlock and **stays in RAM until the next reboot** — it does *not* get evicted when the screen locks. That is why a seized phone that is merely "locked but was unlocked since boot" still gives up the overwhelming majority of user data, and why forcing a reboot (or letting the inactivity timer fire) is catastrophic for the examiner: it doesn't just lock the screen, it **flushes the Class C key**, turning all that app data back into ciphertext.

> 🔬 **Forensics note:** Do not assume an app's data is Class C — apps can opt files up to Class A or B per the `NSFileProtectionKey` they set, and Apple promotes certain built-in stores (Health, parts of Mail) to higher classes. The *exact* class of a given artifact is itself a finding: a Messages thumbnail that survives in BFU vs. the message body that doesn't tells you their classes differ. Verify per iOS version rather than memorizing a table; classes have shifted across releases.

### The three device states, precisely

```
                  power-on / reboot / INACTIVITY REBOOT / panic / battery-dead
                                          │
                                          ▼
                                     ┌─────────┐
                                     │   BFU   │   Before First Unlock
                                     │ class D │   A/B/C class keys NOT derivable
                                     │  only   │   (SEP has never seen the passcode this boot)
                                     └────┬────┘
              first correct passcode ─────┘
              (SEP entangles passcode⊗UID,
               unwraps A,B,C class keys)
                                          ▼
                                  ┌───────────────┐
              unlock screen ─────▶│  AFU-unlocked │   A,B,C,D all resident → ~everything readable
              (Face ID / passcode)│  A B C D live │
                                  └──────┬────────┘
                                         │ screen locks (auto-lock, side button)
                                         ▼
                              ┌────────────────────────┐
                              │   AFU-screen-locked    │   C,D live
                              │ A evicted (~after lock)│   B: can write, can't reopen closed files
                              │ B private key evicted  │   ← MOST seized devices arrive here
                              └────────────────────────┘
                                         │
                                         │  72h locked with no unlock
                                         ▼
                                 (inactivity reboot → back to BFU)
```

Three states, not two. The middle column of every acquisition decision is whether you are in **AFU-unlocked** (you, or the suspect, just unlocked it — grab everything *now*), **AFU-screen-locked** (the common seizure state — Class A is already gone but Class C is still live, so most data is reachable *if your tooling can talk to the device before USB shuts*), or **BFU** (the device rebooted at some point — assume only Class D, plus a few scraps).

### The readability matrix

This is the table to internalize. For each device state × class, what do you get?

| Class \ State | **BFU** (never unlocked this boot) | **AFU — screen-locked** | **AFU — unlocked** |
|---|---|---|---|
| **A** `Complete` | **Ciphertext** (class key not derivable) | **Ciphertext** (key evicted at lock) | **Readable** |
| **B** `CompleteUnlessOpen` | **Ciphertext** | **Ciphertext** for already-closed files (can still *create* new ones) | **Readable** |
| **C** `CompleteUntilFirstUserAuthentication` *(default)* | **Ciphertext** | **Readable** (key resident until reboot) | **Readable** |
| **D** `None` | **Readable** (UID-wrapped) | **Readable** | **Readable** |

Read it as three columns of decreasing pain:

- **BFU** — only the **Class D** row is green. In practice that is system plumbing and a thin slice of caches: enough to boot, place an emergency call, show some lock-screen affordances. The user's messages, photos, app databases (overwhelmingly Class C) are **ciphertext**. The well-known exception researchers point to is a handful of **`.ktx` SpringBoard snapshot thumbnails** (app-switcher previews, which can include a glimpse of message text or a photo) that sometimes survive at a lower class — a marginal, not-to-be-relied-on leak. BFU acquisition is mostly *device/system* data, not *user* data.
- **AFU — screen-locked** — the **C and D** rows are green. Because Class C is the default, this is *most user data*: app containers, Messages, Photos' database, Safari history, location stores. Class A/B (sealed-at-lock secrets — some Health, some Mail, certain Keychain items) stay ciphertext. **This is the state that makes or breaks a case**, and it is the state most devices are in when they hit the lab.
- **AFU — unlocked** — every row is green. If a device is handed to you unlocked, or you have the passcode and lawful authority to enter it, this is the jackpot: full-file-system extraction yields essentially the complete plaintext set.

> 🖥️ **macOS contrast:** There is no macOS analogue to the *middle* column. FileVault has no "screen-locked but keys still resident per-class" state — once you're past the pre-boot unlock the whole volume is open and a screen lock is purely a UI gate over an already-decrypted disk. iOS's AFU-screen-locked is the genuinely novel idea: the disk is *partially* decryptable, on a per-file-class basis, and which parts depend on a key-eviction policy that fires on lock for some classes (A/B) but not others (C/D).

### Why this dominates *every* acquisition decision

Everything downstream — which method ([[the-acquisition-taxonomy]]), whether a backup is worth taking ([[the-itunes-finder-backup-format]]), whether a full-file-system pull will even decrypt ([[full-file-system-acquisition]]) — is gated by the cell you land in.

- **A logical/backup acquisition needs AFU.** A `mobilebackup2` backup (and `libimobiledevice` logical pulls — [[logical-acquisition-with-libimobiledevice]]) require the device to be **unlocked and paired/trusted**; in BFU the device refuses to start the backup service and the pairing record won't validate. You cannot back up a BFU phone.
- **A full-file-system extraction in BFU returns mostly Class D.** Even if your exploit gives you root and a raw image, the **bytes you read are still wrapped by class keys the SEP won't release**. Root does not equal plaintext on iOS — the crypto is below you. (A BootROM exploit like checkm8/usbliter8 gives code-exec *below signature checks*, but **does not defeat Data Protection** — you still need lock state + the SEP to release keys. See the sibling lesson [[full-file-system-acquisition]].)
- **The keychain has its own class system** mirroring file classes (`kSecAttrAccessibleWhenUnlocked` ≈ A, `…AfterFirstUnlock` ≈ C, `…Always`/deprecated ≈ D, plus `…ThisDeviceOnly` variants that block migration). Same matrix logic applies: in BFU you get only the `Always`/`ThisDeviceOnly`-`AfterFirstUnlock`-but-already-resident items — most credentials are sealed. See [[keychain-on-ios]].

The operational corollary: **device state at the moment of seizure is your single most valuable, most perishable fact.** Record it before you do anything else, and treat it as evidence.

### The two clocks racing against you

Seizing an AFU device does not freeze it in AFU. Two independent countdowns start working to demote it, and they run *whether or not the device is in airplane mode, in a Faraday bag, or sitting in an evidence locker.*

#### Clock 1 — USB Restricted Mode (~1 hour)

Since iOS 11.4.1, if the device has been **locked for ~1 hour** with no USB data accessory connected, iOS disables the **data** pins on the Lightning/USB-C port (charging continues). After that, a forensic bridge can power the phone but cannot speak the USB protocols an acquisition tool needs. The setting is *Settings → Face ID & Passcode → Allow Access When Locked → Accessories*; **Lockdown Mode** ([[advanced-protections-lockdown-sdp-adp]]) hardens it further by disabling wired data while locked outright.

The mechanism has had bypasses — most recently **CVE-2025-24200**, an Accessibility-framework flaw that let a physical attacker disable USB Restricted Mode, **patched in iOS 18.3.1 (Feb 2025)**. Assume on a current (≥18.3.1, 26.x) device the ~1-hour clock holds.

> 🔬 **Forensics note:** USB Restricted Mode does **not** change the *crypto* state — the Class C key is still in RAM — it changes your *transport*. A device can be a perfect AFU target whose data is fully resident and still be unreachable because the port stopped talking 20 minutes ago. This is why the first physical action on a seized, powered, possibly-AFU phone is to connect it to power *and* a known-trusted data accessory (or a preservation appliance, below) **immediately**, before the hour elapses, to keep the data channel alive.

#### Clock 2 — Inactivity reboot (~72 hours → AFU collapses to BFU)

Introduced in **iOS 18.0** (September 2024) at a ~7-day interval and quietly **tightened to 72 hours in iOS 18.1** (October 2024, no public announcement), the **inactivity reboot** counts time since the last unlock and, at 72 hours locked, **reboots the device** — silently, no prompt, no way to cancel. Mechanically: the **SEP** tracks the elapsed-since-unlock interval and, past the threshold, signals the kernel; SpringBoard is killed to reboot cleanly, and if anything blocks the clean path a **kernel panic** forces the reboot anyway. Because the timer lives in the SEP, you cannot reach in and stop it from software.

The reboot's purpose is precisely to **demote AFU → BFU**: it flushes the Class A/B/C keys from RAM, collapsing your readable set from "almost everything" (the AFU column) to "almost nothing" (the BFU column).

The two clocks compound. A device seized AFU-screen-locked is on **both** countdowns at once: the ~1-hour USB clock (already ticking, possibly already expired) decides whether you can *connect*, and the ≤72-hour inactivity clock decides whether the data is even still *resident* to extract. And — the cruel part — **if the device was already locked when you seized it, you cannot tell how much of either clock is left.** You don't know when it was last unlocked, so you must assume the worst: minutes, not hours.

> ⚖️ **Authorization:** Keeping a device powered, networked-isolated, and out of its inactivity reboot is **evidence preservation**, and the lawful basis for it (warrant, consent, exigent circumstances) must already be in place — powering and connecting a seized phone is a search. Document the device state at seizure (screen on/off, locked/unlocked, battery %, time on screen), the time you connected power, and every tool you attached, in the chain-of-custody log ([[acquisition-sop-and-chain-of-custody]]). The two clocks are exactly why "we'll image it next week" is sometimes legally and technically indefensible.

### Vendor countermeasures: fighting the reboot clock

Because the 72-hour clock can quietly destroy an AFU device's value before tooling is even ready, the commercial vendors built features whose entire job is to **keep a seized device from rebooting, sleeping, or going idle** — buying time in AFU.

| Capability | Vendor / product | What it does (mechanism, at a high level) |
|---|---|---|
| **Safeguard Mode** | **Cellebrite** (Spring 2026 release) | Preserves access to a seized device and **maintains it across the inactivity reboot**, so teams can secure devices in the field first and extract later without losing the AFU window. |
| **GrayKey Preserve** | **Magnet Forensics / GrayKey** | A preservation step applied **before the device reaches the lab** that keeps iOS data preserved "indefinitely in minutes," defeating the iOS 18 reboot-timer curveball while keeping the device acquirable. |

The shared idea: get the device onto a controlled appliance **while it is still AFU and still inside the USB window**, then hold it there — powered, prevented from idling into the reboot, network-isolated so it can't be remotely wiped (Find My / `Erase iPhone`), and kept warm so the Class C key never leaves RAM. These are not passcode bypasses — they do not get you *into* a BFU device — they **stop a good AFU device from going bad.** (The BFU→data problem still needs the SEP to release keys, which still needs the passcode.)

> ⚠️ **ADVANCED:** Anything that keeps a seized, possibly-network-reachable phone powered risks a **remote wipe** if isolation fails (Find My erase, MDM remote wipe, or a dead-man Shortcut). The standard mitigation is a **Faraday environment** (bag/box/room) with pass-through power, or pulling the SIM/eSIM profile and disabling radios — but a Faraday bag with a dying battery defeats itself the instant the phone powers off (→ BFU on next boot). Power **and** isolation, together, or you lose either to the wipe or to the clock.

> 🔬 **Forensics note:** The countermeasure war is version-locked and perishable — "Safeguard Mode," "GrayKey Preserve," and the exact iOS versions each supports are *catalog facts*, not durable mechanism. Re-verify the vendor support matrix and your firmware target at the time of the exam; the matrix in this lesson reflects mid-2026. The *durable* takeaway is the principle: **AFU is a wasting asset on two clocks, and your job in the first hour is to stop the bleed.**

## Hands-on

There is no on-device shell, and the Simulator has no Data Protection at all (that is itself the first lab). These Mac-side commands inspect device state, the *absence* of the crypto layer in the Simulator, and the protection-class metadata you would read on a real decrypted image.

### Query a connected device's lock state (mechanism, not bypass)

`pymobiledevice3` exposes the lockdown state without unlocking anything. On a real attached device you can distinguish "passcode required" (BFU-ish / locked) from a usable trusted-pair session:

```bash
# Install once (Mac side): pipx install pymobiledevice3
pymobiledevice3 lockdown info | grep -iE 'PasswordProtected|ProductVersion|UniqueDeviceID'
# PasswordProtected: true
# ProductVersion: 26.5
# UniqueDeviceID: 00008140-001A2B3C...

# Whether a trusted pairing exists at all (BFU refuses new pairings):
pymobiledevice3 lockdown pair        # in BFU this fails: device must be unlocked to trust a host
```

`ideviceinfo -k PasswordProtected` (libimobiledevice) returns the same boolean. Neither tells you *which* of the three states you're in directly — `PasswordProtected: true` is shown for both BFU and AFU-locked — so you infer state from **boot evidence**: an uptime/last-boot newer than the last user activity implies a reboot happened (→ BFU).

### Read the protection-class metadata on a (decrypted) sample image

On a decrypted full-file-system extraction the per-file `cprotect` record carries the protection class as an integer (Apple's internal numbering: A=1, B=2, C=3, D=4 — tools usually relabel them A–D). There is **no single off-the-shelf one-liner** that prints it: the field lives inside the APFS crypto-state record (`j_crypto_val_t` → `wrapped_crypto_state_t.protection_class`) and is surfaced by an APFS-aware parser (iLEAPP's report, `blacktop/ipsw`'s APFS parser, `apfs-fuse`, or a vendor suite). The pipeline below is **schematic** — it shows the *shape* of the question ("what class is this file?") that the matrix answers, not a runnable command:

```bash
# SCHEMATIC — substitute whatever APFS/cprotect parser you have emitting {path, class}.
# The point is the tally, not the exact tool. e.g. iLEAPP surfaces per-artifact class;
# an APFS parser can dump the cprotect protection_class per inode.
<apfs-cprotect-parser> /path/to/decrypted_ffs \
  | awk '{print $1}' | sort | uniq -c | sort -rn | head     # class is column 1
#  18422  C    /private/var/mobile/Containers/Data/Application/...
#   1190  D    /private/var/...
#     47  A    /private/var/mobile/Library/Health/...
```

The lopsided count — overwhelmingly **C** — is the whole story: that's why AFU yields so much and BFU so little.

### Prove the Simulator has no Data Protection layer

Real iOS files carry a `com.apple.system.cprotect` (or APFS-internal cprotect) metadata attribute. Simulator files do not — they live on your Mac's APFS under FileVault, with no class keys, no keybag, no SEP:

```bash
# Find a Simulator app container
xcrun simctl list devices booted
APP=$(find ~/Library/Developer/CoreSimulator/Devices -path '*/Data/Containers/Data/Application/*' -type d | head -1)

# Look for any data-protection xattr — there are none on the Simulator
xattr -l "$APP"/Documents/* 2>/dev/null | grep -i cprotect || echo "no cprotect — Simulator has no Data Protection"
# no cprotect — Simulator has no Data Protection
```

## 🧪 Labs

> Each lab names its substrate and its fidelity caveat. The recurring caveat: **the Simulator has no SEP, no keybag, no Data-Protection-at-rest, and no BFU/AFU concept at all** — it can only prove the *negative* (the layer is absent). The lock-state behavior itself is learned from sample images and reasoning, never reproduced on the Mac.

### Lab 1 — Confirm the absence: the Simulator has no class keys *(substrate: Xcode Simulator)*

**Goal:** internalize that the Simulator can never demonstrate BFU/AFU — and why.

1. Boot a Simulator and a stock app: `xcrun simctl boot "iPhone 17 Pro"` then open Notes/Messages in it and add content.
2. Locate the container under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/`.
3. Open the app's SQLite store directly with `sqlite3` — it opens with **no decryption step**. There is no lock state to honor.
4. Run the `xattr … grep cprotect` check from Hands-on; confirm **no** protection-class attribute exists.

**Fidelity caveat:** This is the *point*, not a limitation to work around. The Simulator runs macOS frameworks on macOS APFS; there is no per-file class key, no system keybag, no SEP entanglement. It teaches *schema and layout* (which you'll reuse in Part 08), and it proves that "the file is readable" on the Simulator says **nothing** about whether it would be readable on a device — on a device that same file is Class C ciphertext until first unlock.

### Lab 2 — Read the class distribution on a real extraction *(substrate: public sample image / read-only walkthrough)*

**Goal:** see why "AFU ≈ everything" empirically.

1. Obtain a public iOS reference image (Josh Hickman / thebinaryhick.blog; or the iLEAPP test data). These are **already-decrypted AFU full-file-system extractions** — the plaintext you'd get *if* you held the AFU keys.
2. Enumerate protection classes across the tree (the schematic `cprotect` tally in Hands-on, or let iLEAPP's report surface per-artifact classes).
3. Tally the classes. Confirm the overwhelming majority are **C**, a minority **D**, a thin sliver **A/B**.
4. For three high-value artifacts — Messages `sms.db`, Photos `Photos.sqlite`, Safari `History.db` — note their class and reason: *in BFU, would this have decrypted?* (Class C → **no**.)

**Fidelity caveat:** The public image is a *decrypted AFU* snapshot, so it can show you the *contents* of each class but **cannot itself show you ciphertext** — it can't reproduce the BFU column. You're reading the class labels and reasoning about the matrix, not watching encryption happen.

### Lab 3 — Tabletop: classify the state, predict the yield *(substrate: read-only reasoning)*

**Goal:** make the matrix a reflex. For each scenario, state (a) the device state, (b) which classes decrypt, (c) the single most urgent action.

| # | Scenario | State? | Classes readable? | Most urgent action? |
|---|---|---|---|---|
| 1 | Phone seized **unlocked**, screen on, suspect was using it | ? | ? | ? |
| 2 | Phone seized **locked**, warm, on a call 2 min ago | ? | ? | ? |
| 3 | Phone found **powered off**, you power it on | ? | ? | ? |
| 4 | Phone in evidence 4 days, **never connected to power**, now dead | ? | ? | ? |
| 5 | Phone seized locked **40 min ago**, you only now reach for a cable | ? | ? | ? |

Work them, then check: (1) AFU-unlocked → A,B,C,D → keep it awake/unlocked, image now. (2) AFU-screen-locked → C,D → connect power+data **now** (USB clock), preserve against the 72h clock. (3) BFU (a cold boot is BFU) → D only → don't expect user data; logical/backup will fail. (4) BFU when it died and again on next boot → D only, and you blew the 72h clock by not powering it — a preservation failure to write up. (5) Possibly past USB Restricted Mode already → you may be unable to *connect* even though Class C is still resident — a transport loss, not a crypto loss.

**Fidelity caveat:** Pure reasoning; no device. This is the skill the no-device constraint actually sharpens — the decision, not the button-press.

### Lab 4 — Build the dual-clock window calculator *(substrate: Mac-side script, device-free)*

**Goal:** compute, from seizure facts, when each clock expires.

```bash
cat > /tmp/window.py <<'PY'
import sys, datetime as dt
# args: last_unlock_iso  seized_iso   (use seized for both if unlock time unknown → worst case)
last_unlock = dt.datetime.fromisoformat(sys.argv[1])
seized      = dt.datetime.fromisoformat(sys.argv[2])
usb_deadline      = last_unlock + dt.timedelta(hours=1)    # USB Restricted Mode
reboot_deadline   = last_unlock + dt.timedelta(hours=72)   # inactivity reboot (iOS 18.1+)
now = dt.datetime.now()
print(f"USB data port closes ~  {usb_deadline}  ({'EXPIRED' if now>usb_deadline else (usb_deadline-now)} left)")
print(f"AFU→BFU reboot      ~  {reboot_deadline}  ({'EXPIRED' if now>reboot_deadline else (reboot_deadline-now)} left)")
if last_unlock == seized:
    print("WARNING: last-unlock unknown → assuming = seizure time; real deadlines may be SOONER.")
PY
# Known unlock time:
python3 /tmp/window.py 2026-06-26T09:15:00 2026-06-26T09:40:00
# Unknown unlock time (worst case — pass seizure time twice):
python3 /tmp/window.py 2026-06-26T09:40:00 2026-06-26T09:40:00
```

Run both forms. The second — the realistic "we don't know when it was last unlocked" case — is the one that should make you connect power *first* and ask questions later.

**Fidelity caveat:** Arithmetic only; the 1h/72h constants are the current (iOS 18.1+/26.x) values and are themselves perishable — re-confirm the inactivity threshold for the firmware in front of you before relying on the number.

## Pitfalls & gotchas

- **"The phone is unlocked in my hand, so it's like an unlocked FileVault Mac" — no.** An *unlocked* phone is AFU-unlocked (great), but the moment auto-lock fires you drop to AFU-screen-locked and **Class A/B data you hadn't yet read is gone**. Disable auto-lock / keep it awake (or keep tapping) while you work, within authorization.
- **Rebooting to "get a clean state" is a crypto-shred of your evidence.** Any reboot — including the one a clumsy tool or a low battery triggers — flushes Class A/B/C and drops you to BFU. Treat "don't let it reboot" as a prime directive.
- **Root ≠ plaintext.** A BootROM exploit or kernel R/W gives you the *bytes*, but in BFU those bytes are still wrapped by class keys the SEP won't release. People conflate "I have a full-file-system image" with "I have the data"; in BFU you mostly have Class D.
- **You cannot read the clocks on a device that was already locked at seizure.** Last-unlock time is unknown, so both countdowns may be nearly expired. Plan for the worst case, not the average.
- **A Faraday bag without power is a timer to BFU.** Isolation stops remote wipe but a flat battery powers the phone off → next boot is BFU. You need isolation **and** pass-through power.
- **USB Restricted Mode is a transport loss, not a crypto loss — and vice versa.** Don't confuse them: past the 1h USB window the Class C key may still be perfectly resident; you just can't reach it. Past the 72h reboot the port may work fine but there's nothing left to decrypt.
- **Class membership shifts across iOS versions and per app.** Don't hard-code "Messages is Class C." Verify against the firmware and the app; promotion of stores to Class A/B is a real and moving target.
- **Lockdown Mode and ADP change the calculus entirely.** Lockdown Mode disables wired data when locked (no USB acquisition path at all in that state); ADP removes the iCloud fallback ([[icloud-acquisition-and-advanced-data-protection]]). The matrix still holds, but several columns of your *options* vanish.

## Key takeaways

- **iOS has no single "locked/unlocked" bit.** Readability is the cross-product of **device state** (BFU / AFU-locked / AFU-unlocked) and **per-file Data Protection class** (A/B/C/D) — the volume being "mounted" is nearly meaningless.
- **BFU vs AFU = "has the SEP unwrapped the A/B/C class keys since boot?"** Class D is UID-wrapped (always available); A/B/C are passcode⊗UID-entangled (available only after first unlock; flushed by any reboot).
- **Class C is the default and the prize.** Its key persists from first unlock *until reboot* (not evicted at lock), so AFU-screen-locked — the common seizure state — yields most user data; BFU yields mostly system data.
- **The readability matrix is the lesson:** BFU = D only; AFU-locked = C+D; AFU-unlocked = A+B+C+D. Memorize it; it gates method, backup viability, and FFS payoff.
- **Two clocks shrink your window from seizure:** USB Restricted Mode (~1h, transport) and the iOS 18.1 inactivity reboot (~72h, crypto — AFU→BFU). If the device was locked at seizure you can't read either clock — assume minutes.
- **Vendor countermeasures (Cellebrite Safeguard Mode, Magnet GrayKey Preserve) preserve an AFU device against the reboot clock** — they do *not* break into BFU. Keep a good device good; you still can't conjure keys the SEP won't release.
- **Device state at seizure is your most valuable, most perishable fact** — record it first, power+isolate immediately, and document every connection for chain of custody.

## Terms introduced

| Term | Definition |
|---|---|
| BFU (Before First Unlock) | Post-boot state in which the passcode has not been entered, so the SEP cannot derive the Class A/B/C keys; only Class D data is readable. |
| AFU (After First Unlock) | State after at least one correct passcode entry since boot; the A/B/C class keys have been unwrapped into memory. Subdivides into AFU-unlocked and AFU-screen-locked. |
| Data Protection class | Per-file policy (A/B/C/D) that selects which class key wraps a file's per-file key, and thus when the file is decryptable. |
| Class A (`NSFileProtectionComplete`) | Key available only while unlocked; evicted shortly after the screen locks. |
| Class B (`NSFileProtectionCompleteUnlessOpen`) | Curve25519-based; a file can be *created* while locked but a *closed* file cannot be reopened until unlock. |
| Class C (`NSFileProtectionCompleteUntilFirstUserAuthentication`) | Default class; key resident from first unlock until the next reboot (survives screen lock). |
| Class D (`NSFileProtectionNone`) | Key wrapped by the hardware UID only; data readable in every state, including BFU. |
| Per-file key | Random AES-256 key encrypting one file's contents, itself wrapped by a class key and stored in the file's `cprotect` metadata. |
| `cprotect` | The per-file metadata attribute holding the wrapped per-file key and the file's protection-class number. |
| System keybag | The on-device store of wrapped class keys; A/B/C wrapped by passcode⊗UID, D by UID alone. |
| Inactivity reboot | iOS 18.1+ feature that reboots the device after ~72h locked, flushing A/B/C keys and demoting AFU→BFU. |
| USB Restricted Mode | iOS 11.4.1+ feature disabling the USB *data* lines ~1h after lock (charging continues), blocking forensic transport. |
| Safeguard Mode | Cellebrite (Spring 2026) capability that preserves a seized device's AFU access across the inactivity reboot. |
| GrayKey Preserve | Magnet/GrayKey feature that preserves iOS device data before lab intake, defeating the iOS 18 reboot-timer window loss. |
| Crypto-erase | Instant wipe by destroying the volume metadata key in Effaceable Storage, rendering all file metadata (and thus all per-file keys) unrecoverable. |

## Further reading

- **Apple Platform Security Guide** — "Data Protection classes," "Keybags for Data Protection," "Encryption and Data Protection overview" (support.apple.com / security.apple.com) — the primary source for class semantics and key wrapping.
- **Magnet Forensics** — "Understanding the security impacts of iOS 18's inactivity reboot" and "The importance of preservation for iOS devices" (GrayKey Preserve) — magnetforensics.com.
- **Cellebrite** — Spring 2026 release notes (Safeguard Mode); "AFU vs. BFU: Understanding Device States in Cellebrite Inseyets" (James Henning, Medium).
- **Hexordia** — "iOS Inactivity Reboot" technical analysis (hexordia.com); **DigForCE Lab** (DSU) iOS 18 reboot writeup.
- **ElcomSoft blog** — long-running coverage of USB Restricted Mode, BFU/AFU extraction, and keychain class behavior (blog.elcomsoft.com).
- **Jonathan Levin**, *MacOS and iOS Internals* — keybag/AKS and SEP key-management internals; newosxbook.com.
- **Apple** — `CVE-2025-24200` advisory (USB Restricted Mode bypass, fixed iOS 18.3.1); Apple security release notes.
- iLEAPP / mvt test data and **Josh Hickman** reference images (thebinaryhick.blog) for protection-class enumeration on real extractions.
- `man` / docs: `pymobiledevice3 lockdown`, `ideviceinfo` (libimobiledevice), `xcrun simctl`.

---
*Related lessons: [[passcode-bfu-afu-and-inactivity]] | [[data-protection-and-keybags]] | [[the-acquisition-taxonomy]] | [[full-file-system-acquisition]] | [[sep-sepos-deep-dive]] | [[keychain-on-ios]] | [[storage-nand-aes-effaceable]] | [[acquisition-sop-and-chain-of-custody]] | [[advanced-protections-lockdown-sdp-adp]]*
