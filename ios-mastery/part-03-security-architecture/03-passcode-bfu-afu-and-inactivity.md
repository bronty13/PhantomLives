---
title: "Passcode, BFU/AFU & the inactivity reboot"
part: "03 — Security Architecture"
lesson: 03
est_time: "50 min read + 20 min labs"
prerequisites: [data-protection-and-keybags]
tags: [ios, passcode, bfu, afu, brute-force, inactivity-reboot, forensics]
last_reviewed: 2026-06-26
---

# Passcode, BFU/AFU & the inactivity reboot

> **In one sentence:** The passcode is the root of trust for user data — it is entangled with the Secure Enclave's hardware UID through a deliberately slow key derivation, it gates whether the class keys that decrypt your files are even resident in memory (the BFU vs. AFU distinction), and since iOS 18 the device will reboot *itself* after ~72 hours idle to drag its own keys out of reach — so the single most consequential fact in any iPhone examination is **the lock state of the device at the moment of seizure**, and the inactivity reboot is a clock you are racing.

## Why this matters

On macOS you encrypt a FileVault volume, unlock it once at login, and it stays unlocked for the whole session — there is no notion of the OS spontaneously re-locking or rebooting to protect keys. iOS does the opposite at every turn: it keeps the most sensitive class keys out of memory until you authenticate, evicts the *Complete*-protection key seconds after the screen locks, and as of iOS 18 will power-cycle the device entirely if it sits idle too long. For an examiner this means the device hands you radically different amounts of data depending on a state you do not control and cannot easily reverse: a phone seized **After First Unlock (AFU)** with most user data decryptable is a different evidentiary universe from the same phone three days later in **Before First Unlock (BFU)**, where almost everything is sealed behind a passcode you have to brute-force on the SEP at ~80 ms per guess. Get the state-handling wrong at seizure and no amount of downstream tooling recovers it. This lesson is the mechanism behind that state machine: how the passcode becomes a key, why brute force is hardware-bound, what is resident in each lock state, and how the inactivity reboot shrinks your window.

## Concepts

### From digits to a key: passcode entanglement with the SEP UID

A passcode is not a password that gets compared against a stored hash. It is an *input to key derivation*. The thing that actually unlocks your data is the **passcode-derived key**, and producing it requires two secrets combined:

1. **What you know** — the passcode (4-digit, 6-digit, or alphanumeric).
2. **What the hardware is** — the **UID**, a 256-bit AES key fused into the Secure Enclave at manufacture, never exported, never readable by software (not even by SEP firmware directly — it is wired into the AES engine's key path). See [[secure-enclave-hardware]] and [[storage-nand-aes-effaceable]].

The derivation runs **PBKDF2** where each iteration's AES operation is keyed by the UID, so the work is performed *by the SEP's AES engine on this specific chip*. This is "entanglement": the output depends on both the passcode and a per-device secret that exists nowhere else and cannot be copied. The consequence is the entire security model's load-bearing wall:

> You cannot move the brute force off the device. There is no hash to copy to a GPU cluster. Every guess must execute on **this** SEP, because only this SEP can apply the UID.

Apple deliberately tunes the PBKDF2 iteration count so that **one passcode attempt takes roughly ~80 ms** on the target hardware. That number is a calibration target, not a constant — it is chosen per SoC generation so that the wall-clock cost holds even as the SEP gets faster. The 80 ms is the *floor* an attacker pays even after every software throttle is defeated, because it is the cost of the cryptographic derivation itself.

```
passcode  ─┐
           ├─► PBKDF2 ( many rounds, each round's AES keyed by ─► [ SEP UID, fused ] )
device UID ─┘                                                         │
                                                                      ▼
                                              passcode key  ──►  unwraps the keybag class keys
                                                                      │
                                                                      ▼
                                              class keys  ──►  AES-XTS decrypt of per-file keys
```

What the ~80 ms buys, in keyspace terms:

| Passcode | Combinations | Worst case at 80 ms/try | Practical takeaway |
|---|---|---|---|
| 4-digit numeric | 10,000 | ~13 minutes | Trivially brute-forceable *if* throttle is bypassed |
| 6-digit numeric (default) | 1,000,000 | ~22 hours (~1 day) | Feasible over a day or two |
| 6-char lowercase alnum | ~2.2 billion | ~5.5 years | Effectively out of reach |
| 8-char mixed-case alnum + symbols | ~6 quadrillion | geologic | Out of reach |

This table is *why* the on-screen prompt nags you to use an alphanumeric passcode, and why a forensic examiner's realistic hopes hinge on the suspect having used a 4- or 6-digit code. The numbers assume the software throttle (next section) has already been bypassed; with the throttle intact, even a 4-digit code can take far longer.

> 🖥️ **macOS contrast:** FileVault on Apple Silicon also entangles the volume key with the Secure Enclave, so a FileVault image is likewise not GPU-crackable offline without the recovery key — but macOS has **no passcode-throttle escalation and no BFU/AFU eviction**. Once you log in, the volume key stays live for the entire session; the Mac never spontaneously re-locks the disk or reboots to protect it. The iOS model is far more aggressive about clawing keys back out of memory.

### What the passcode key actually unlocks: the system keybag

The passcode key does **not** decrypt files directly — it unwraps the **system keybag**, the SEP-managed structure holding one wrapped **class key** per Data Protection class. Full treatment is in [[data-protection-and-keybags]]; the part that matters here is the chain of custody from digits to plaintext:

- Each class key in the keybag is wrapped (encrypted) so that unwrapping it requires a specific combination of the **UID-derived key** and, for the passcode-protected classes, the **passcode key**. Class D's key needs only the UID; Class A/B/C additionally need the passcode key.
- At the first correct unlock the SEP applies the passcode key, unwraps the Class A/B/C class keys, and loads them into its protected memory. It then hands the AP wrapped **per-file keys** that feed the inline AES engine decrypting NAND ([[storage-nand-aes-effaceable]]) — the SEP never lets the bulk file keys touch AP-readable memory in the clear.
- The entire keybag is anchored to an **effaceable master secret** in a dedicated NAND region. "Erase Data after 10," a remote wipe, or Erase All Content & Settings destroys *that secret* — which is why a wipe is instant and irreversible: it shreds the keybag's root, not the gigabytes of data, so every class key becomes undecryptable at once.

So "entering the passcode" really means "derive the passcode key → ask the SEP to unwrap the keybag → promote the device to AFU." Every downstream fact — which files decrypt, which keychain items return — is a consequence of *which class keys that one unwrap made resident*.

### The SEP throttle: escalating delays and optional erase

The ~80 ms is the *cryptographic* cost. On top of it, the **Secure Enclave itself** — not the application processor, not SpringBoard, not any software you can patch — enforces an **escalating delay** after consecutive wrong guesses. The main CPU merely *submits* a candidate passcode to the SEP and *receives* a pass/fail; the SEP performs the check and, if there have been too many failures, refuses to perform the next check until a timer elapses.

The classic published escalation ladder:

| Consecutive failed attempts | Delay before next attempt is allowed |
|---|---|
| 1–4 | none |
| 5 | 1 minute |
| 6 | 5 minutes |
| 7 | 15 minutes |
| 8 | 15 minutes |
| 9 | 1 hour |

> 📅 **Dated detail (verify at author time):** ElcomSoft's analysis of recent iOS reports Apple has *extended* this ladder on newer versions with additional **3-hour and 8-hour** tiers beyond the 1-hour step, making sustained brute force even slower. Treat the exact upper tiers as version-specific — the durable fact is "SEP-enforced, monotonically escalating, restart does not clear it."

Two properties make this brutal for an attacker:

- **It is enforced in the SEP, below the OS.** Jailbreaking the application-processor kernel does **not** clear it. A BootROM exploit ([[boot-chain-securerom-iboot]]) gives code execution *below* the AP signature checks but still cannot make the SEP skip its own counter — the SEP is a separate processor with its own secure memory and monotonic counters.
- **Restart re-enforces the delay.** If you reboot the device during a timed delay, the delay is still enforced and **the timer restarts for the current period**. You cannot reboot your way past the wait.

Optionally — and this is a user setting, **off by default** but very common on managed/security-conscious devices — **Erase Data** (Settings → Face ID/Touch ID & Passcode → Erase Data) wipes all content after **10 consecutive failures**. "Wipe" here is the [[storage-nand-aes-effaceable]] trick: the SEP destroys the keybag's master key in the effaceable storage region, rendering every class key — and therefore every file — permanently undecryptable in milliseconds. There is no recovery and no "it was only logically deleted" angle. This is the single most important box to know the state of before you ever touch a seized device.

> ⚖️ **Authorization:** Because Erase-Data-after-10 may be enabled and is invisible from the lock screen, you do **not** guess at passcodes on an evidence device. Live passcode attempts against an unknown configuration risk irreversibly destroying the entire dataset, and an unauthorized guessing attempt can itself exceed the scope of a warrant. Passcode attack happens through validated tooling (GrayKey, Cellebrite Premium) under documented authority, on devices whose acquisition method is known to be safe — never ad hoc.

### BFU vs. AFU: which class keys are resident

This is the concept that decides everything downstream. iOS Data Protection (covered in depth in [[data-protection-and-keybags]]) sorts every file and keychain item into a **protection class**, and each class key lives in the keybag wrapped such that it becomes available only under specific conditions. The lock state controls *which class keys are currently decrypted and sitting in kernel memory*.

The four file Data Protection classes:

| Class | Constant | Key availability |
|---|---|---|
| A | `NSFileProtectionComplete` | Only while **unlocked**; key evicted from memory ~10 s after lock |
| B | `NSFileProtectionCompleteUnlessOpen` | Asymmetric (ECDH) — a file already open stays writable while locked; new files can be created locked |
| C | `NSFileProtectionCompleteUntilFirstUserAuthentication` | Released at the **first unlock after boot**, then stays resident until reboot/power-off — **this is the default class for most app data** |
| D | `NSFileProtectionNone` | Protected only by the UID-derived key (no passcode entanglement) — available **whenever the device is powered on**, including BFU |

Keychain has parallel accessibility classes — `kSecAttrAccessibleWhenUnlocked` (≈ A), `kSecAttrAccessibleAfterFirstUnlock` (≈ C), and the legacy `kSecAttrAccessibleAlways` (≈ D) — plus `…ThisDeviceOnly` variants that are excluded from backups. See [[keychain-on-ios]].

Now overlay the two lock states:

```
┌─────────────────────────── BFU — Before First Unlock ───────────────────────────┐
│  Device powered on, NEVER unlocked since this boot.                              │
│  Resident class keys:  Class D (NSFileProtectionNone) only.                      │
│  Keychain available:   kSecAttrAccessibleAlways (Class D) items only.            │
│  → SEP REFUSES to release the passcode-protected class keys until you            │
│    authenticate. Class A/B/C data is ciphertext you cannot read.                 │
│  Forensic yield:  near nothing of user value. Some system config, a few          │
│    Always-class keychain items (e.g. certain Wi-Fi/VPN creds, push tokens).      │
└─────────────────────────────────────────────────────────────────────────────────┘
                                  │  first correct passcode (or biometric+passcode-derived unlock)
                                  ▼
┌─────────────────────────── AFU — After First Unlock ────────────────────────────┐
│  Device unlocked at least once since boot (even if now showing a locked screen).│
│  Resident class keys:  Class C and "below" (C + D) are decrypted and in memory   │
│    and STAY there until reboot/power-off. Class A is resident only while the     │
│    screen is actually unlocked (evicted ~10 s after lock).                       │
│  Keychain available:   AfterFirstUnlock (Class C) + Always (Class D) items.      │
│  → Because most app data defaults to Class C, the bulk of user data — Messages,  │
│    most app SQLite stores, Photos metadata, call history — is DECRYPTABLE.       │
│  Forensic yield:  large. This is the state you want a device seized in.          │
└─────────────────────────────────────────────────────────────────────────────────┘
```

The single most important operational sentence in iPhone forensics:

> **A locked-but-AFU phone is not "locked" in the way that matters.** The screen lock is a UI gate; the *class keys are already in RAM*. If acquisition tooling can get code execution (e.g. an agent installed before lock, or a checkm8/usbliter8-class device that can be exploited at the BootROM — see [[the-acquisition-taxonomy]]), Class C data is readable **without** the passcode, because the keys are resident. BFU has no such keys to find.

This is why the field-handling rule is: **keep the device in AFU and powered.** Don't let it die, don't reboot it, isolate it from the network (Faraday) so it can't be remote-wiped, and get it to a charger and validated acquisition fast. A reboot — whether by a dead battery, a remote command, or the inactivity timer — silently demotes AFU to BFU and the class keys evaporate.

> 🔬 **Forensics note:** You can often *infer* the lock state of a sample image or an acquired filesystem after the fact. If files protected as Class A/C contain readable plaintext in your extraction, the acquisition happened in AFU (or the keys were recovered). If only `NSFileProtectionNone` paths are populated and everything else is ciphertext, you captured BFU. The **AppleKeyStore** state and the presence/absence of decrypted class keys is also reflected in keybag artifacts and the keychain dump — a BFU keychain dump returns only the Always-class items, an AFU dump returns the AfterFirstUnlock items too. The *delta* between what a tool returns BFU vs. AFU is itself a way to confirm which state the device was in.

### Biometrics don't bypass entanglement — and what forces the passcode back

Face ID and Touch ID feel like a passcode replacement, but cryptographically the **passcode is still the root**. On a successful match the biometric subsystem releases the **passcode key the SEP is already holding** so you don't re-type it — it does **not** re-derive anything from your face or finger, and it cannot reconstruct the passcode key from scratch. (Sensor and template internals are [[biometrics-security-architecture]]; here we care only about lock-state transitions.) The forensically critical knowledge is the set of conditions under which iOS **discards the held passcode key and demands the passcode again** — each is a potential lock-state change an examiner must anticipate:

| Condition | Effect |
|---|---|
| Device just (re)booted | **BFU** — passcode required for first unlock; biometrics disabled until then |
| >48 hours since the device was last unlocked | passcode required (biometric fast-path disabled) |
| Passcode not used to unlock in 6.5 days **and** biometric not used in the last 4 hours | passcode required |
| 5 failed biometric match attempts | passcode required |
| Power + volume hold / "Emergency SOS" invoked | biometrics disabled → passcode required (the deliberate "lock it down" gesture) |
| Remote lock via Find My, or an MDM Lock Device command | passcode required |
| New biometric enrollment, or device just took a software update | passcode required at next unlock |

These thresholds are perishable (re-verify per iOS version), but the durable forensic point is twofold. First, **a subject can force the passcode requirement on demand** — the squeeze-the-buttons gesture is exactly that — which is why arrest/seizure procedure stresses getting a biometric unlock *fast*, before the subject can trigger the lockdown. Second, **biometric lockout ≠ BFU**: after the 5-fail or SOS lockout the class keys are still resident (still AFU) — the device simply won't accept a face/finger until a passcode is entered once. Only a reboot or the inactivity reboot actually evicts the keys to BFU.

### USB Restricted Mode: the sibling clock

The inactivity reboot is not iOS's only time-based key defense — it has an older sibling examiners hit constantly. **USB Restricted Mode** (since iOS 11.4.1; "Allow Access When Locked → USB Accessories" off by default) disables the data lines of the Lightning/USB-C port for anything but charging **one hour after the device was last unlocked** (or last connected to a trusted accessory). After that hour the port still charges but won't talk data to a computer or forensic bridge until the passcode is entered again — defeating the "seize now, plug into the acquisition box later" plan. Like the inactivity reboot, the clock counts from last unlock; unlike it, it locks the *port*, not the keys. The two defenses **stack and run off the same starting gun**: from the last-unlock moment you have roughly **1 hour of data-port access** and **≤72 hours of AFU key residency**, both ticking down. A valid pairing/lockdown record captured while the accessory was still trusted can keep USB alive past the hour — yet another reason the suspect's paired computer is high-value evidence. (Acquisition-method implications in [[the-acquisition-taxonomy]] and [[logical-acquisition-with-libimobiledevice]].)

### The iOS 18 inactivity reboot: AFU has an expiration date

Before iOS 18, an AFU device stayed AFU indefinitely as long as it stayed powered — examiners could (and did) keep a seized phone alive on a charger in a Faraday bag for *weeks* waiting for tooling support, the class keys sitting resident the whole time. iOS 18 closed that window deliberately. The mechanism — reverse-engineered publicly by **Dr.-Ing. Jiska Classen** (Nov 2024) and since corroborated by forensic vendors — is the **inactivity reboot**, and it is engineered to be SEP-anchored so a compromised AP kernel cannot defeat it.

How it works, component by component:

```
   ┌──────────────────────────────────────────────────────────────────────────┐
   │ SEP (Secure Enclave Processor)                                            │
   │   • holds the authoritative "last successful unlock" time on its OWN      │
   │     secure clock (a monotonic counter the AP cannot roll back)            │
   │   • continuously compares (now − last_unlock) against the threshold       │
   └───────────────┬──────────────────────────────────────────────────────────┘
                   │  when (now − last_unlock) > threshold:
                   │  SEP signals the AppleSEPKeyStore kernel extension
                   ▼
   ┌──────────────────────────────────────────────────────────────────────────┐
   │ AppleSEPKeyStore (kernel extension, on the application processor)         │
   │   • receives the SEP's "inactivity exceeded" signal                       │
   │   • informs user space to initiate a graceful reboot                      │
   │   • sets the NVRAM variable  aks-inactivity                               │
   │   • WATCHDOG: if the device is still powered on after it should have      │
   │     rebooted, the kernel PANICS — anti-tamper, so you can't just block    │
   │     the reboot from a jailbroken kernel                                   │
   └───────────────┬──────────────────────────────────────────────────────────┘
                   ▼
   ┌──────────────────────────────────────────────────────────────────────────┐
   │ SpringBoard gracefully terminates user-space processes (avoid data loss) │
   │   → device reboots → comes up in BFU → class keys gone                    │
   └───────────────┬──────────────────────────────────────────────────────────┘
                   ▼
   ┌──────────────────────────────────────────────────────────────────────────┐
   │ keybagd (user-space daemon), on next boot                                 │
   │   • reads the  aks-inactivity  NVRAM flag                                 │
   │   • if set, clears it and emits an analytics event recording how long     │
   │     the device had gone unlocked                                          │
   └──────────────────────────────────────────────────────────────────────────┘
```

The thresholds, by version (a perishable detail — re-verify):

| iOS version | Inactivity threshold | Result |
|---|---|---|
| iOS 18.0 | **7 days (168 h)** | reboot → AFU demoted to BFU |
| iOS 18.1 and later (incl. 26.x) | **~72 hours (3 days)** | reboot → AFU demoted to BFU |

Why the design is hard to beat:

- **The clock lives in the SEP.** The threshold comparison uses the SEP's own time tracking, not an AP-readable timestamp the examiner could freeze. Jailbreaking the main kernel doesn't help because the decision isn't made there.
- **The watchdog panics on tamper.** If an attacker patches the AP kernel to *swallow* the reboot request, the SEP/keystore notices the device is still up past the deadline and forces a kernel panic — which reboots anyway, into BFU. There is no "just don't reboot" option.
- **It is graceful, not a crash.** SpringBoard tears down processes cleanly so the user (and a legitimate device) loses no data — but the *effect* on a seized AFU device is exactly the loss of resident class keys.

> 🔬 **Forensics note:** The `aks-inactivity` NVRAM flag and the keybagd analytics event are themselves artifacts. The analytics/diagnostics submission records the **duration the device went unlocked** before the inactivity reboot fired — visible in `Analytics` / `awd` / diagnostic logs in a full-file-system acquisition ([[unified-logs-sysdiagnose-crash-network]], [[powerlog-and-aggregate-dictionary]]). A device that shows an inactivity-reboot event tells you it sat idle for at least the threshold — useful for establishing that no one touched it during a window, or for explaining *why* a phone you logged in AFU is now in BFU when it reaches the lab.

> 🖥️ **macOS contrast:** There is **no inactivity reboot on macOS**, and no AFU/BFU concept at all. A FileVault Mac, once unlocked at login, keeps its volume key live until you log out, sleep-with-lock, or shut down — and even a locked-but-awake Mac keeps the disk decrypted in RAM. macOS will sit unlocked-and-decrypted for as long as it has power. iOS treats *time itself* as an attacker and re-locks its own keys on a deadline. The closest macOS analogue is the SEP wiping FileVault keys only on full shutdown — there is no automatic shutdown to trigger it.

### Mounting the attack: device class decides feasibility

Given the 80 ms floor and the escalation ladder, here's what a passcode attack actually looks like and why it succeeds or fails by **silicon generation**. Two things must be true to even start: (a) **code execution that can submit guesses to the SEP faster than the UI allows**, and (b) a way to **suppress or sidestep the software throttle**. The cryptographic 80 ms you can never beat — it runs on the SEP — so the entire game is *getting to submit guesses programmatically*. Where that foothold comes from depends on the chip:

| Device class | BootROM exploit | What's feasible |
|---|---|---|
| A8–A11 | **checkm8** (unpatchable SecureROM) | Reliable BFU *and* AFU extraction + on-device brute force for short passcodes — the classic forensic sweet spot |
| A12–A13 (+S4/S5, A12 iPads) | **usbliter8** (unpatchable; public 2026-06-18) | New BootROM foothold → similar AFU extraction + brute-force submission path; the boundary moved here in 2026 |
| A14 and later | **none public** | No BootROM foothold; rely on AFU key residency (if seized unlocked-once) or proprietary vendor chains — BFU yields little |

The nuance examiners get wrong: **a BootROM exploit is not a passcode bypass.** checkm8/usbliter8 give code execution *below* the AP signature checks ([[boot-chain-securerom-iboot]]) — invaluable for loading an acquisition agent and for *submitting guesses to the SEP* — but they do not hand you class keys and cannot make the SEP skip its 80 ms or its escalation. On a BFU device you still must brute-force; on an AFU device you often needn't, because the keys are already resident. That is why the single most valuable property of a seized device is **AFU lock state**, and the second is **being an A8–A13 device** (a BootROM foothold exists at all). An A14+ device seized in BFU with a 6-character alphanumeric passcode is, for practical purposes, not getting opened.

> 🔬 **Forensics note:** "Extraction" and "passcode recovery" are different deliverables, and tools price them separately. A tool may *extract* an AFU device's Class C data with no passcode (keys resident), while *recovering the passcode itself* — needed for BFU data, the keychain's `WhenUnlocked` items, and to decrypt a future encrypted backup — requires the brute-force run and only succeeds for short numeric codes. Always record which you achieved: a full-file-system extraction in AFU is **not** the same as possessing the passcode.

### How the window closed: a short history

Today's lock-state defenses were built up over a decade, each step shrinking what an attacker with physical possession can do. Worth knowing because sample images and casework span these eras:

| Era | Hardware / OS | What changed |
|---|---|---|
| A6 and earlier | no Secure Enclave | Passcode throttle was **software-only** on the AP — bypassable; key derivation was entirely AP-side |
| A7 (iPhone 5s, 2013) | **SEP introduced** | Throttle + key derivation moved into the SEP; brute force becomes hardware-bound at ~80 ms, escalation ladder SEP-enforced |
| iOS 8 (2014) | Data Protection on by default | Most user data defaulted to passcode-protected classes; Apple could no longer extract user data on legal request |
| (ongoing) | effaceable storage | Wipe = destroy the keybag's effaceable root → instant, irreversible erase; the basis of Erase-after-10 |
| (ongoing) | BFU/AFU hardening | Class-key residency tightly tied to lock state; locked-AFU keeps Class C resident, BFU exposes only Class D |
| iOS 11.4.1 (2018) | **USB Restricted Mode** | Data port disabled ~1 h after last unlock — closes the "plug it in later" window |
| iOS 18.0 → 18.1 (2024) | **Inactivity reboot** | AFU now expires: 7 days, then 72 h → device reboots itself to BFU; SEP-anchored, watchdog-panic if suppressed |

The throughline: each generation makes **time and continued possession worth less** to an attacker. The macOS world never went down this path — a FileVault Mac you possess and have unlocked stays open indefinitely. iOS treats continued possession as a *decaying* advantage.

### Putting it together: the state machine you're racing

```
   power on
      │
      ▼
  ┌───────┐  first correct passcode   ┌───────┐
  │  BFU  │ ────────────────────────► │  AFU  │  (class C keys now resident)
  └───────┘                           └───┬───┘
      ▲                                    │
      │   reboot / power-off / battery     │  ~72 h idle (iOS 18.1+)
      │   dead / remote wipe trigger /      │  → inactivity reboot
      └────────────── inactivity reboot ◄───┘
```

Every arrow back to BFU is a catastrophe for an examiner holding an un-passcoded AFU device, and **the inactivity arrow fires on a timer you do not control.** From the moment of seizure you are racing a ≤72-hour clock (less, if the device was already partway through its idle period when seized — the SEP counts from the last *unlock*, not from your seizure). That is the practical heart of this lesson: device state at seizure decides everything, and one of the ways you lose that state is simply by waiting too long.

## Hands-on

There is no on-device shell on a stock iPhone, and you have no physical device — so every command here runs on the **Mac**, against the Simulator, public sample images, or as a pure calculation. The device-bound steps are narrated as read-only walkthroughs.

### Model the brute-force economics (pure calculation — no device)

The keyspace-vs-time math is the most decision-relevant number in any examination, and it is just arithmetic. A tiny Mac-side script makes the trade-offs concrete:

```bash
python3 - <<'PY'
PER_ATTEMPT_S = 0.080  # the ~80 ms SEP-bound derivation floor
def t(n):
    s = n * PER_ATTEMPT_S
    for unit, k in (("years",31557600),("days",86400),("hours",3600),("min",60)):
        if s >= k: return f"{s/k:6.1f} {unit}"
    return f"{s:.1f} s"
cases = {
  "4-digit numeric":            10_000,
  "6-digit numeric (default)":  1_000_000,
  "6-char lowercase alnum":     36**6,
  "6-char mixed-case alnum":    62**6,
  "8-char mixed+symbols(~95^8)":95**8,
}
for name, space in cases.items():
    print(f"{name:30s} {space:>20,d}  worst-case {t(space)}")
PY
```

Expected output (worst-case = exhausting the whole space; expected value is ~half):

```
4-digit numeric                              10,000  worst-case   13.3 min
6-digit numeric (default)                 1,000,000  worst-case   22.2 hours
6-char lowercase alnum                2,176,782,336  worst-case    5.5 years
6-char mixed-case alnum              56,800,235,584  worst-case  144.1 years
8-char mixed+symbols(~95^8)    6,634,204,312,890,625  worst-case (astronomical)
```

This is the conversation you have with an investigator about whether a passcode attack is even worth attempting — and it is why a 6-digit code is the realistic ceiling for a feasible attack.

### Confirm the Simulator has no Data Protection at all (Simulator)

The Simulator is invaluable for *schema* work but is a hard lesson in fidelity here: it runs macOS frameworks with **no SEP, no UID, no class keys, no BFU/AFU**. App containers sit in plaintext on the Mac's APFS:

```bash
xcrun simctl list devices booted
# Pick a booted sim UDID, then:
SIM=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
ls "$HOME/Library/Developer/CoreSimulator/Devices/$SIM/data/Containers/Data/Application/"
# Every app's Documents/Library are readable directly — no decryption, no lock state.
file "$HOME/Library/Developer/CoreSimulator/Devices/$SIM/data/Containers/Data/Application/"*/Documents/* 2>/dev/null
```

The takeaway is the caveat: **anything you learn about encryption, lock state, or key residency must come from sample images, not the Simulator.** The Simulator teaches you *where* a SQLite store lives and *what* its schema is; it cannot teach you *whether* you'd be able to read it on a locked device.

### Read each file's Data Protection class (APFS `cprotect` — walkthrough)

The abstract "class" is a concrete per-file field on disk: every file on an iOS APFS volume carries its Data Protection class in the per-file **`cprotect`** structure (the `cp_key_class` field) — this is *how* the OS decides which class key to apply. On a decrypted full-file-system extraction, forensic tooling surfaces it, so you can see per file which class (and therefore which lock state) governs decryptability:

```
cp_key_class   Data Protection class
     1         A — NSFileProtectionComplete
     2         B — NSFileProtectionCompleteUnlessOpen
     3         C — NSFileProtectionCompleteUntilFirstUserAuthentication  (default)
     4         D — NSFileProtectionNone
     6         F — a further class seen on system/internal files in `cprotect`; its exact semantics are sparsely documented and version-specific (verify)
```

(The numeric mapping is stable but version-check it; the durable fact is *the class is a per-file field in `cprotect`, not a global setting*.) The payoff: you can prove *why* a given file was or wasn't recoverable in a BFU capture — a file tagged `3`/C is readable only AFU, a file tagged `4`/D is readable BFU. The same granularity is how one app keeps its SQLite store as Class C (readable AFU) while its credential cache is Class A (readable only while actually unlocked).

> 🔬 **Forensics note:** When a vendor report says a device was acquired "BFU" yet you see populated app databases, check the `cprotect` class of those files — legitimately BFU-readable content is class `4`/D. App data that defaulted to class `3`/C appearing in a "BFU" extraction is a contradiction worth resolving: either the capture was actually AFU, or the keys were recovered by other means. The per-file class is your ground truth against a tool's lock-state label.

### Inspect lock-state-relevant device info (libimobiledevice — device-required, walkthrough)

With a real device you'd query lock state and pairing posture over USB. Described output (these require a physical device + a valid pairing record, so they are read-only walkthroughs here):

```bash
# Whether the device currently has a passcode set / is paired & trusted:
ideviceinfo -k PasswordProtected        # → true  (a passcode is configured)
idevicepair validate                    # → SUCCESS only if a valid pair record exists

# pymobiledevice3 surfaces richer lock/activation state:
pymobiledevice3 lockdown info | grep -iE 'PasswordProtected|ActivationState'
```

The forensic point of `ideviceinfo -k PasswordProtected` and `idevicepair validate`: a **valid pairing record** (a "lockdown record," stored on a previously-trusted computer at `/var/db/lockdown/` on macOS) is gold — it lets logical acquisition proceed *in AFU without re-entering the passcode*, because the device already trusts that host. Seizing the suspect's paired Mac alongside the phone can be worth more than the phone alone. See [[the-itunes-finder-backup-format]] and [[logical-acquisition-with-libimobiledevice]].

### Read the inactivity-reboot artifact from a full filesystem (walkthrough)

In a full-file-system extraction you can look for evidence the inactivity reboot fired. The flag is in NVRAM and the event is in diagnostics/analytics; on an acquired filesystem you'd grep the analytics submissions and unified-log/`awd` stores:

```bash
# Conceptual — against a mounted FFS extraction, not a live device:
grep -rli 'aks-inactivity\|inactivity' /path/to/ffs/private/var/db/analyticsd/ 2>/dev/null
# And reboot causes generally:
log show --archive /path/to/extracted.logarchive \
  --predicate 'eventMessage CONTAINS "Previous shutdown cause" OR eventMessage CONTAINS "reboot"' \
  --style syslog 2>/dev/null | tail -40
```

A device that logged an inactivity reboot establishes it was idle ≥ the threshold — which both explains a BFU-at-lab phone and can corroborate a "nobody handled it" timeline.

### Compute the inactivity-reboot deadline (pure calculation — supports Lab 4)

The most actionable number at seizure is *when AFU expires*, and it's just a date add — but it counts from **last unlock**, not seizure:

```bash
python3 - <<'PY'
from datetime import datetime, timedelta
last_unlock = datetime(2026, 6, 24, 21, 0, 0)   # SEP counts from LAST UNLOCK
seizure     = datetime(2026, 6, 26,  9, 0, 0)
threshold   = timedelta(hours=72)               # iOS 18.1+ ; was 168 h on 18.0
deadline    = last_unlock + threshold
print(f"last unlock : {last_unlock}")
print(f"seizure     : {seizure}")
print(f"reboot fires: {deadline}")
print(f"window left after seizure: {deadline - seizure}")
PY
```

Expected:

```
last unlock : 2026-06-24 21:00:00
seizure     : 2026-06-26 09:00:00
reboot fires: 2026-06-27 21:00:00
window left after seizure: 1 day, 12:00:00
```

The lesson is in the last line: you have **36 hours**, not 72, because the clock started at the suspect's last unlock — and treat even that as an *upper* bound, since a dead battery or a remote-wipe trigger can end AFU sooner.

## 🧪 Labs

> Every lab below is device-free. The encryption/lock-state behavior at the center of this lesson is exactly what the Simulator **cannot** reproduce (no SEP, no Data-Protection-at-rest, no UID, no class keys, and the device-only daemons `keybagd`/`knowledged`/`biomed`/`routined` do not populate Simulator stores), so the lock-state labs use a **public sample image** or a **read-only walkthrough**, and the Simulator is used only to feel the *contrast* of a world with no Data Protection.

### Lab 1 — The brute-force decision (pure calculation; no substrate)

1. Run the Python keyspace script from Hands-on. Confirm the four headline numbers: 4-digit ≈ 13 min, 6-digit ≈ ~1 day, 6-char lowercase ≈ 5.5 years.
2. Change `PER_ATTEMPT_S` to `0.040` (a hypothetical 2× faster future SEP). Notice the 6-digit case *still* costs ~11 hours — the 80 ms floor is conservative but even halving it doesn't make 6-digit trivial. The defense scales with keyspace, not with the per-attempt cost.
3. Now add a hypothetical software-throttle factor: multiply by the escalation ladder (imagine you only get to attempt 5 codes per hour because of the 1/5/15/60-minute delays). Recompute the 6-digit case. Write one sentence on why bypassing the *throttle* (not the 80 ms) is what acquisition vendors actually compete on.

### Lab 2 — Feel the absence of Data Protection (Simulator)

> **Substrate: Xcode Simulator.** Fidelity caveat: the Simulator has **no encryption and no lock state** — this lab teaches the *contrast*, not iOS behavior. Nothing here decrypts anything because nothing is encrypted.

1. Boot a simulator, open Notes or Messages in it, type a note.
2. Find the backing store on the Mac under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/` and open the SQLite directly with `sqlite3` (copy first, per the artifact-handling discipline). Your note is right there in plaintext.
3. Write down the lesson: on a real A12+ device this same Class-C file would be **ciphertext in BFU and plaintext only in AFU**. The Simulator gives you the schema for free precisely because it throws away the security model. You will return to this file on a real sample image in Part 08 to see what BFU vs. AFU actually changes.

### Lab 3 — BFU vs. AFU on a public sample image (read-only walkthrough)

> **Substrate: public sample forensic image** (e.g. a Josh Hickman iOS reference image from thebinaryhick.blog / Digital Corpora, or an mvt/iLEAPP test dataset). Fidelity caveat: you are reading a *captured* filesystem, so you observe the *result* of a lock state, not the live SEP.

1. Obtain a documented sample image and note from its provenance whether it was captured AFU or BFU.
2. Enumerate which protection classes have populated, readable content. In an AFU capture, Class C stores (most app SQLite DBs, Messages, call history) are readable; in a BFU capture, only `NSFileProtectionNone` paths are.
3. Pull the keychain dump from the extraction. Confirm the rule: an AFU keychain returns `AfterFirstUnlock` items; a BFU keychain returns only `Always` items. The **delta** is your empirical proof of the lock state at acquisition.
4. Write a one-paragraph "state-at-seizure" finding as you would for a report: which state, what that made decryptable, and what was unavailable as a result.

### Lab 4 — Race the inactivity clock (tabletop walkthrough)

> **Substrate: read-only walkthrough + arithmetic.** No device needed.

1. Construct a timeline: a phone's last unlock was **2026-06-24 21:00**. It is seized **2026-06-26 09:00** in AFU. With the iOS 18.1+ 72-hour threshold counting from *last unlock*, compute the exact wall-clock moment the inactivity reboot will fire (answer: 2026-06-27 21:00 — note it is **36 hours after seizure**, not 72, because the SEP counts from the last unlock).
2. List, in order, the field actions that preserve AFU: isolate from the network (Faraday) to prevent remote wipe, keep it powered (charger/battery pack), do **not** reboot or power-cycle, and escalate to validated acquisition immediately.
3. Identify which single action a custodian could take that would *accidentally* demote AFU→BFU (let the battery die; toggle airplane mode incorrectly causing nothing; or, the real one — leave it idle past the SEP's deadline). State why "we'll get to it next week" is, post-iOS-18, a discarded-evidence decision.

### Lab 5 — State-at-seizure decision tree (capstone; no substrate)

> **Substrate: synthesis.** Pull together every mechanism in this lesson into a one-page artifact you could hand to a field officer.

Build a decision tree / SOP that branches on the facts you can observe at seizure and outputs the right handling. At minimum it must encode:

1. **Is the screen unlockable by biometric right now?** If yes and lawful — get a biometric unlock immediately (it's the fastest route to AFU + a chance to disable auto-lock / extend the window), *before* the subject can trigger the Emergency-SOS lockdown.
2. **Lock state branch:** AFU vs. BFU — and the reminder that *locked screen ≠ BFU* (an AFU phone showing a lock screen still has Class C keys resident).
3. **Two clocks, both from last unlock:** ~1 h USB Restricted Mode and ≤72 h inactivity reboot. Note that you usually don't know the last-unlock time, so treat both as already running.
4. **Preservation actions:** Faraday isolation (block remote wipe / remote lock), keep powered, do not reboot, do not enter guesses (Erase-after-10 may be on), seize the suspect's paired computer for its lockdown record.
5. **Device-class note:** record the model/SoC — A8–A13 has a BootROM foothold (checkm8/usbliter8), A14+ does not, which changes whether BFU is even worth pursuing.
6. **Documentation:** photograph the screen state, log seizure time, and note whether you achieved *extraction* vs. *passcode recovery* — they are different deliverables.

Compare your tree against a published vendor field-handling guide (Magnet/Cellebrite/MSAB) and note anything you missed.

## Pitfalls & gotchas

- **"Locked" ≠ "keys gone."** The reflex from passwords is that a locked device is sealed. On an AFU iPhone the screen lock is UI; the Class C keys are in RAM. Conversely a BFU device with the screen "off" is fully sealed. Always reason in BFU/AFU, never in "locked/unlocked-screen."
- **The SEP counts from last *unlock*, not from seizure.** Your 72-hour budget is usually *less* than 72 hours — sometimes much less. A phone last unlocked 2.5 days before you got it gives you ~12 hours, not 3 days. Never assume a full window.
- **A reboot is irreversible for key residency.** There is no "re-enter AFU without the passcode." Once the device reboots — battery death, remote command, inactivity timer, or a careless power-off — you are back to brute-forcing on the SEP. Treat the running AFU device as perishable evidence.
- **Erase-Data-after-10 is invisible and on by default for many.** You cannot tell from the lock screen whether 10 wrong guesses will wipe the device. This is why ad-hoc guessing is forbidden and passcode attack is left to tooling that knows the device class is safe.
- **The 80 ms is a floor, not the whole cost.** Defeating the *software throttle* (the escalation ladder, and the historical exploits against it) still leaves you paying ~80 ms per guess *on that SEP*. Vendors compete on bypassing the throttle and on getting code execution to submit guesses faster — not on beating the cryptographic derivation, which is hardware-bound.
- **BootROM exploit ≠ defeating the passcode.** checkm8 (A8–A11) and usbliter8 (A12–A13) give code execution *below* AP signature checks, which is huge for getting an acquisition agent on-device — but they do **not** hand you the class keys. You still need lock state (AFU) or a successful on-SEP brute force. A14+ has *no* public BootROM exploit at all, so even that foothold is gone on modern devices. See [[the-acquisition-taxonomy]] and [[full-file-system-acquisition]].
- **Don't conflate file Data Protection classes with keychain accessibility classes.** They are parallel systems with similar-sounding names (`NSFileProtection*` vs. `kSecAttrAccessible*`). A file may be Class C while a credential the same app stores is `WhenUnlocked` (≈ Class A) — different residency, different BFU/AFU availability. See [[keychain-on-ios]].
- **Inactivity-reboot thresholds are version-specific and tamper-resistant.** Don't write "7 days" from memory — it's 72 hours since 18.1. And don't plan to "just block the reboot from a jailbreak": the keystore watchdog kernel-panics the device if it's still up past the deadline.
- **The Simulator will lie to you about security.** Everything is plaintext there. Use it for schema and layout only; take *every* claim about encryption/lock-state from sample images.

## Key takeaways

1. The passcode is **key-derivation input, not a comparison secret** — PBKDF2 entangled with the SEP UID means every guess must run on *this* chip at a calibrated ~80 ms floor, so there is no offline GPU attack.
2. The SEP enforces an **escalating delay ladder** (1/5/15/60+ min) below the OS that a jailbreak can't clear and a reboot can't reset, plus an optional **erase-after-10** that destroys the keybag master key irreversibly.
3. **BFU resident keys = Class D only**; **AFU resident keys = Class C and below** — and because Class C is the default, AFU makes the bulk of user data decryptable while BFU yields almost nothing.
4. A **locked-but-AFU** device is the prize: the screen lock is UI, the class keys are already in RAM. Field handling exists to *keep* the device in AFU and powered.
5. The **iOS 18 inactivity reboot** (Jiska Classen, 2024) is SEP-anchored: the SEP tracks last-unlock, signals `AppleSEPKeyStore`, sets the `aks-inactivity` NVRAM flag, SpringBoard gracefully reboots, and `keybagd` logs it — with a watchdog kernel-panic if the reboot is suppressed.
6. The threshold went **7 days (18.0) → ~72 hours (18.1+)**, and it counts **from last unlock**, so your real window after seizure is often well under 72 hours — it's a clock you race.
7. **Device state at seizure decides everything.** Unlike macOS FileVault (unlock once, stays unlocked all session, never reboots to protect keys), iOS actively re-locks and reboots to claw keys out of memory — post-iOS-18, "we'll get to it later" can mean AFU→BFU and a discarded dataset.

## Terms introduced

| Term | Definition |
|---|---|
| Passcode key | The key derived from the passcode via PBKDF2 entangled with the SEP UID; unwraps the keybag class keys |
| UID (Secure Enclave) | A 256-bit AES key fused into the SEP at manufacture, never exported; entangling it with the passcode binds brute force to the specific device |
| System keybag | SEP-managed structure holding one wrapped class key per Data Protection class; the passcode key unwraps it to promote the device to AFU |
| Effaceable master secret | A keybag-anchoring secret in a dedicated NAND region; destroying it (wipe / Erase-after-10) makes every class key undecryptable instantly |
| USB Restricted Mode | Since iOS 11.4.1: disables the USB/Lightning data lines ~1 hour after last unlock, leaving only charging until the passcode is re-entered |
| Biometric lockout | A state (5 failed matches, Emergency-SOS gesture, >48 h, etc.) that forces passcode entry but does **not** evict class keys — still AFU, not BFU |
| ~80 ms calibration | Apple's tuned PBKDF2 iteration count making one passcode attempt cost roughly 80 ms on-device — the hardware-bound brute-force floor |
| Escalating delay ladder | SEP-enforced increasing waits (1/5/15/60+ min) after consecutive failed passcode attempts; survives reboot, not OS-clearable |
| Erase Data (after 10) | Optional setting that destroys the keybag master key after 10 consecutive wrong passcodes, rendering all data permanently undecryptable |
| BFU (Before First Unlock) | State after boot before any successful unlock; only Class D (`NSFileProtectionNone`) keys are resident |
| AFU (After First Unlock) | State after at least one successful unlock since boot; Class C and below keys are resident (and stay resident until reboot) |
| Data Protection class | Per-file/keychain classification (A/B/C/D) controlling under which lock state its class key is available |
| `NSFileProtectionCompleteUntilFirstUserAuthentication` | The default Class C — key released at first unlock, then resident until reboot; the reason AFU yields most user data |
| `NSFileProtectionNone` | Class D — protected only by the UID-derived key, available whenever the device is powered on, including BFU |
| Inactivity reboot | iOS 18 feature: SEP-tracked idle timer (~72 h since 18.1) that reboots the device, demoting AFU→BFU |
| `keybagd` | User-space daemon that, on boot, reads the `aks-inactivity` NVRAM flag and emits an analytics event recording the idle duration |
| `AppleSEPKeyStore` | Kernel extension that receives the SEP's inactivity signal, triggers the reboot, sets `aks-inactivity`, and kernel-panics if the reboot is suppressed |
| `aks-inactivity` | NVRAM flag (`aks` = Apple KeyStore) set on an inactivity reboot; a forensic artifact of how long the device sat idle |
| Lockdown / pairing record | Trust record (e.g. `/var/db/lockdown/`) letting a previously-paired host perform logical acquisition in AFU without re-entering the passcode |

## Further reading

- **Apple Platform Security guide** — "Passcodes and passwords," "Data Protection classes," "Keybags for Data Protection," "Secure Enclave" (support.apple.com/guide/security) — primary source for the escalation table, class-key model, and SEP role.
- **Jiska Classen, "Reverse Engineering iOS 18 Inactivity Reboot"** — naehrdine.blogspot.com (Nov 2024) — the definitive teardown of `keybagd`/`AppleSEPKeyStore`/`aks-inactivity` and the watchdog panic.
- **Magnet Forensics** — "Understanding the security impacts of iOS 18's inactivity reboot"; **Hexordia** — "iOS Inactivity Reboot" — the forensic-practitioner framing (AFU→BFU window, field handling).
- **ElcomSoft blog** — "The Evolution of iOS Passcode Security" (2025) — the extended delay tiers (3 h / 8 h) and the practical brute-force economics on modern devices.
- **mikeash.com**, "Friday Q&A: What Is the Secure Enclave?" — the clearest plain-language account of UID entanglement and the 80 ms calibration.
- **MSAB / SalvationData / DigForCE Lab** glossary + blog posts on **BFU vs. AFU** — concise practitioner definitions and which keychain accessibility classes appear in each state.
- **"Let's Take it Offline: Boosting Brute-Force Attacks on iPhone's User Authentication through SCA"** (research paper) — why moving the brute force off-device is the holy grail and why the UID entanglement blocks it.
- Jonathan Levin, *MacOS and iOS Internals* (newosxbook.com) — SEP architecture, keybag internals, and the AppleKeyStore stack.
- `man 1 sqlite3`, libimobiledevice (`ideviceinfo`, `idevicepair`), pymobiledevice3 docs — the Mac-side toolchain for lock-state and pairing inspection.

---
*Related lessons: [[data-protection-and-keybags]] | [[sep-sepos-deep-dive]] | [[storage-nand-aes-effaceable]] | [[the-acquisition-taxonomy]] | [[bfu-vs-afu-and-data-protection-classes]] | [[full-file-system-acquisition]] | [[acquisition-sop-and-chain-of-custody]] | [[keychain-on-ios]]*
