---
title: "Biometrics security architecture"
part: "03 — Security Architecture"
lesson: 07
est_time: "45 min read + 15 min labs"
prerequisites: [biometrics-hardware-faceid-touchid, data-protection-and-keybags]
tags: [ios, biometrics, faceid, touchid, security, forensics]
last_reviewed: 2026-06-26
---

# Biometrics security architecture

> **In one sentence:** Face ID and Touch ID are not a way *around* Data Protection — they are an *unlock method* whose only privilege is to hand the Secure Enclave the authority to unwrap class keys it is already holding in escrow, while the passcode remains the cryptographic root, and the precise list of conditions that revoke that escrow (BFU, 48 h, 6.5 days, five failed matches, the SOS squeeze, a remote lock) are exactly the operational levers that decide what an examiner can read at seizure.

## Why this matters

[Part 01](soc-lineup-and-device-matrix) covered the *hardware*: the TrueDepth dot projector, the flood illuminator, the Touch ID capacitive array, the Secure Neural Engine inside the SEP. This lesson is about what that hardware is *trusted to do* — enrollment, matching, and the one thing a successful match is permitted to release. The distinction matters in two directions at once. As a builder, you need to know that `LAContext.evaluatePolicy` does not "return the password"; it gates a SEP-held key, and the difference between `.deviceOwnerAuthenticationWithBiometrics` and a keychain ACL of `kSecAccessControlBiometryCurrentSet` is the difference between a UI gesture and a cryptographic binding. As a forensic examiner, the six conditions that force the passcode are the entire game at seizure: a phone in After-First-Unlock (AFU) state with biometrics live is a phone whose class keys are sitting in SEP memory; let one condition trip and those keys are gone, dropping you toward Before-First-Unlock (BFU) where a full-filesystem image is mostly ciphertext. The "panic" squeeze your suspect just did on the way out the door is not paranoia theater — it is a one-gesture, hardware-backed anti-forensic countermeasure, and knowing *exactly* what it did to the keybag is the difference between a productive acquisition and a brick.

## Concepts

### The one-sentence security model: biometrics gate a key, the passcode *is* the key

Burn this in before anything else, because every other fact in the lesson is a corollary:

```
passcode  ─┬─► entangled with SEP hardware UID ──► passcode key
           │
           ▼
        unwraps the class keys in the keybag  ◄── the ROOT secret
           │
           ▼   (after first unlock, with biometrics enabled)
        class keys are RE-wrapped with a key the SEP hands to the
        Face ID / Touch ID subsystem  ──►  held in escrow ≤ 48 h
           │
           ▼
   biometric MATCH  ──►  SEP releases that escrow key  ──►  unwraps class keys  ──►  unlocked
```

A biometric match never reconstructs the passcode and never derives a class key on its own. Its sole power is to authorize the Secure Enclave to *use a key the SEP already holds*. That escrowed key only exists because the passcode put it there at the last passcode unlock. Pull the passcode out of the chain — by any of the six conditions below — and the escrow is discarded; the next unlock *must* re-derive from the passcode, and no face or finger will do.

This is the same model you already met on the Mac, and it is worth anchoring there.

> 🖥️ **macOS contrast:** On a Touch ID Mac (T2 or Apple silicon), the fingerprint template is sealed in the SEP exactly as on iPhone, and a match doesn't "type your password" — it releases the SEP-wrapped secret that unwraps your **login keychain** and, at the login window, the wrapper for the **FileVault volume key**. The reflexes transfer cleanly. Two things are iOS-only: (1) **Face ID gaze/attention detection** has no Mac analogue (the Mac never needs to know you're *looking* at it), and (2) the Mac has nothing like the **seizure-relevant biometric-lockout ladder** — a Mac asks for the password after a cold boot for FileVault, but it has no 48-hour escrow timer, no "five failed matches" biometric disable, and no SOS squeeze that demotes the volume key. Those iOS conditions exist because a phone is the thing that gets grabbed out of your hand.

### Face ID vs. Touch ID: security properties side by side

Same SEP-sealed-template architecture, materially different security surfaces:

| Property | Face ID | Touch ID |
|---|---|---|
| Sensor | TrueDepth: IR camera, flood illuminator, dot projector (3D depth) | Capacitive ridge array (2D subdermal) |
| Template engine | Secure Neural Engine **in the SEP** | SEP matcher |
| Documented FAR (single enrollment) | ~1 in 1,000,000 | ~1 in 50,000 |
| **Liveness / attention** | **Yes** — gaze (Require Attention) + depth + IR | **No** structural liveness (a good fake finger is the PAD challenge) |
| Sleeping/unconscious-subject resistance | **High** (closed/averted eyes fail) | Low (a finger can be applied) |
| Canonical historical spoof | Composite mask (Bkav, 2017) — high cost | Lifted-latent fake finger (CCC, 2013) — low cost |
| Multiple identities | Primary + one **alternate appearance** | Up to **5 fingers** |
| Hands-free | Yes | No (requires a touch) |

The asymmetry that matters most for security: **only Face ID has attention/liveness as a first-class gate.** That single property is why Face ID resists the "apply it while they sleep / hold it to their face" attack that Touch ID structurally cannot, and it is the reason Apple can quote a 20× lower FAR.

### Enrollment: the template is computed and sealed inside the SEP, and never leaves

When you enroll a face or a finger, the raw sensor data is captured outside the SEP (the TrueDepth camera / the capacitive array), but it is piped to the SEP over a session-encrypted channel and the *template* — the mathematical representation that the device will match against forever after — is computed **inside** the Secure Enclave and stored only there:

- **Face ID.** The TrueDepth system captures a sequence of 2D infrared images and a depth map (the dot-projector pattern). A portion of the **Secure Neural Engine**, which lives inside the SEP, transforms these into a mathematical representation of your face. Apple's documented guarantee: *"This data never leaves the device. It's not sent to Apple, nor is it included in device backups."* The representation is encrypted with a key available **only** to the Secure Enclave.
- **Touch ID.** The capacitive sensor reads the ridge map; the SEP converts it into a template (vector data, not an image — there is no reconstructable fingerprint image stored). Same sealing, same no-export, same exclusion from backups and iCloud.
- **Optic ID** (Apple Vision Pro) is the third member of the family and shares this exact architecture: the iris representation is computed and sealed in the SEP, never leaves the device, and gates the same key-release path. Everything in this lesson about sealing, escrow, and disable conditions generalizes to it; the only difference is the sensor (IR iris imaging vs. depth/capacitance). Apple groups all three under "Optic ID, Face ID, Touch ID" in the security guide for this reason.

Two engineering consequences fall out of "the template never leaves the SEP":

1. **You cannot extract, image, or transplant a biometric template.** It is not a file in a container, not a keychain item, not a blob in a backup. A full-filesystem acquisition of an unlocked device does not contain it. This is by design — the template is bound to *this* SEP's hardware keys (PKA-resident, invisible even to sepOS).
2. **`BiometryCurrentSet` is enforceable because the SEP knows when the set changed.** When you add or remove a face/finger, the enrolled *set* changes, and the SEP can refuse to honor keychain items that were bound to the previous set (more below). That is only possible because the SEP — not the app processor — owns enrollment.

The enrollment and match flows, as a sequence:

```
ENROLLMENT (once per face/finger)
  sensor capture ─encrypted session─► SEP
                                       │  Secure Neural Engine (Face ID) /
                                       │  matcher (Touch ID) builds template
                                       ▼
                       template encrypted w/ SEP-only key, stored IN SEP
                       (not a file • not in backups • not in iCloud)

MATCH (every unlock)
  fresh capture ─encrypted session─► SEP
                                      │  compare vs sealed template (gaze check too)
                                      ▼
                            decision ∈ {match, no-match}
                                      │ on match:
                                      ▼
                       SEP releases escrow key ─► unwraps Complete-class keys ─► UNLOCKED
                       (AP never sees template, comparison, or key)
```

### The SEP↔sensor pairing: why a swapped sensor kills biometrics

The "template never leaves the SEP" guarantee is only half the binding; the *sensor* is bound to the SEP too. At manufacture, each Touch ID/Face ID sensor is **cryptographically paired** to its specific Secure Enclave — they share a session key established during factory provisioning, and all sensor↔SEP traffic is encrypted and authenticated over that channel. The SEP refuses to trust raw captures from a sensor it hasn't paired with. This is a deliberate anti-tamper measure: you cannot splice a malicious sensor (or a recording/replay device) between the camera/array and the SEP and feed it forged biometric data, because the SEP authenticates the source.

The famous consequence was **"Error 53"** (2016): an iPhone whose Touch ID sensor (or its cable) was replaced by a third party — so the new sensor was *not* paired to that SEP — had Touch ID disabled, and at one point the device bricked on update. Apple later softened the failure mode (Touch ID is disabled rather than the phone bricked), but the *security* behavior is unchanged and correct: **an unpaired sensor is an untrusted sensor, and the SEP will not match against it.** The same pairing logic governs Face ID after a TrueDepth-module repair.

> 🔬 **Forensics note:** Sensor pairing is why **hardware-replacement attacks on the biometric path don't work**, and it's a fact about provenance: a device with a *disabled* Face ID/Touch ID and unified-log/`biometrickitd` evidence of a pairing failure may have had its sensor module replaced — relevant to tamper assessment and to ruling out "the owner just disabled it." It also means you cannot graft a cooperating subject's enrolled SEP+sensor onto another handset.

> 🔬 **Forensics note:** Because the template lives only in the SEP and is excluded from backups and iCloud, **there is no biometric artifact to recover** — no template file, no enrollment image, no "Face ID data" in an iTunes/Finder backup or in iCloud. What *is* recoverable is *metadata about biometric policy and events*: whether a passcode/biometrics are configured, lock-state transitions, and (in unified logs / `biometrickitd` and `coreauthd` subsystem messages on a live or logically-acquired AFU device) timestamps of match attempts and the *reasons* the passcode was demanded. You will never recover the face; you can sometimes recover *that a match failed five times at 14:07*.

### Matching and key release: the SEP is the only judge

The match happens entirely inside the SEP. The sensor delivers a fresh capture; the Secure Neural Engine (Face ID) or the SEP's matching logic (Touch ID) compares it to the sealed template; the SEP returns a binary decision and, on success, releases the escrowed unwrap key. The app processor — even a fully kernel-compromised one — never sees the template, never sees the comparison, and cannot forge the "yes." That is the whole point of putting matching below the AP: a jailbroken kernel can *ask* for an unlock, but it cannot *be* the biometric subsystem.

Tie this back to [data-protection-and-keybags](data-protection-and-keybags). After the device's first passcode unlock since boot (the AFU transition), the keys for the `NSFileProtectionComplete` (Class A) Data Protection class are not simply discarded when the screen locks — *if biometrics are enabled*, they are re-wrapped with a key the SEP hands to the biometric subsystem and **held in escrow for at most 48 hours**. A biometric match provides the key that unwraps them; the device returns to unlocked without the passcode. When any disable condition fires, the SEP throws that escrow key away, the Class A keys go truly cold, and only the passcode (which re-entangles with the hardware UID to re-derive everything) can bring them back.

So the precise, mechanism-level definition you want is:

> **The "biometric-disable conditions" are exactly the conditions under which the Secure Enclave evicts the biometric-held wrapper of the Complete-class keys, forcing passcode re-derivation.**

#### Where the escrow lives: the SEP's protected key store

The biometric-held wrapper is not a file on the data volume and not in the System Keybag's on-disk form — it lives in the SEP's own **protected key store** (sometimes surfaced as the `sks`/Secure Key Store subsystem), in memory the application processor cannot read. Connect this to [data-protection-and-keybags](data-protection-and-keybags): the on-disk **System Keybag** holds the class keys *wrapped* by the passcode-derived key; at first unlock the SEP unwraps them and keeps the live class keys (and, with biometrics on, the biometric-subsystem wrapper) in its protected memory. The **Effaceable Storage** that the passcode/key hierarchy ultimately roots into is what a remote wipe shreds — but biometrics never touch it. The clean mental separation:

```
on disk (data volume)   :  System Keybag  →  class keys wrapped by passcode key
in SEP protected memory :  live class keys (post-AFU)  +  biometric escrow wrapper (≤48h)
in SEP fused silicon    :  hardware UID  +  template encryption key  (never readable)
```

A biometric match operates purely in the middle layer — it asks the SEP to use the escrow wrapper to keep/restore the live class keys. It cannot reach the bottom layer (the UID/template key are fused and invisible even to sepOS) and it does not re-read the top layer (that's the passcode's job). This is why "more biometrics" never weakens the at-rest cryptography: the at-rest keys are still wrapped by the passcode key on disk; biometrics only manage the *runtime availability* of the already-unwrapped copies.

### Template adaptation: the enrollment isn't frozen

A subtlety with both security and forensic weight: the stored template **adapts over time**. Face ID augments its mathematical representation as it successfully matches you in new conditions (glasses, a hat, a beard, makeup, aging); Touch ID likewise refines its model from partial reads on each touch. A *successful* match can append data to the representation; a match that initially fails and is then immediately followed by the **passcode** is taken as a strong signal that the just-seen biometric was genuinely the owner, and the SEP updates the template accordingly. This is why Face ID "gets better at recognizing you" and why entering the passcode right after a Face ID miss makes the next attempt more likely to succeed.

Two consequences:
- **Security:** adaptation slightly widens the accepted surface over time, which is part of why Apple's FAR is a *single-appearance* baseline rather than a lifetime constant.
- **The adaptation update is itself an enrollment-state change** in spirit, though Apple's `domainState` invalidation is keyed to *adding/removing* identities, not routine adaptation. Don't assume "the template today is byte-identical to enrollment day."

> 🔬 **Forensics note:** Adaptation is why the passcode-after-a-miss pattern is normal and benign, *not* an indicator of an impostor — the system is designed to learn from exactly that sequence. Conversely, a *brand-new* enrollment (vs. adaptation) is a discrete, loggable event; if you're reasoning about whether someone *re-enrolled* a different face/finger, that is the `domainState`-changing event to look for, not day-to-day drift.

### Beyond unlock: what else a successful match authorizes

Unlock is the headline use, but a match is a reusable *authorization primitive*, and the SEP gates several distinct authorities off the same matching path:

- **Apple Pay / Wallet.** A payment requires a biometric match (or passcode) *plus* an explicit **intent** gesture — **double-clicking the side button** — so the authorization can't be silently triggered. The match releases the payment authorization to the SEP-resident payment applet; the double-click is the user's deliberate "yes, this transaction."
- **Password AutoFill / Passwords app.** Filling a saved credential or viewing the Passwords app is gated by a match (`.userPresence`-class behavior) so a borrowed-unlocked phone still can't dump stored logins without a fresh biometric.
- **App Store / in-app purchases** and **per-app biometric locks** (Settings → an app → "Require Face ID") use the same gate.
- **App-defined flows** via `LocalAuthentication` and `.biometryCurrentSet` keychain items (the builder's view below).

The architectural point: a match is not a global "device is now open forever" toggle — it is a **per-authorization release** the SEP can demand again and again, with optional intent capture (the double-click) for high-stakes actions.

> 🖥️ **macOS contrast:** This maps almost one-to-one to the Mac you know — Touch ID on the Mac authorizes Apple Pay, `sudo` (with `pam_tid`), app installs, unlocking specific Notes/keychain items, and password autofill, each as a *fresh* SEP-gated release rather than a one-time unlock. The iOS additions are the **double-click-to-confirm intent** for Apple Pay (the Mac's analogue is the Touch ID prompt itself) and the **per-app "Require Face ID" lock**, which has no built-in Mac equivalent.

### `Require Attention`: gaze detection as a presentation-attack and coercion defense

Face ID adds a property Touch ID structurally cannot have: **attention**. With **Require Attention for Face ID** enabled (the default), the TrueDepth system must detect that your **eyes are open and directed at the device** before a match counts. The neural networks that do this are trained specifically to resist spoofing with photos, video, masks, and other 2D/3D media; gaze is one signal among several (liveness from the IR/depth stream, micro-movement) but it is the one with direct security and forensic weight:

- **Anti-presentation-attack.** A printed photo, a screen, or a sleeping/unconscious person's closed-eyed face will not satisfy gaze. This is why "hold the phone up to the owner's face" fails if their eyes are shut or averted.
- **Attention-aware features** (a related but distinct setting) also use gaze to keep the screen lit while you read, lower notification-alert volume when you're looking, etc. — but the security-relevant lever is the *unlock* gate.
- **Accessibility carve-out.** Users who cannot reliably direct their gaze can disable Require Attention (Settings → Accessibility), which *lowers* the bar — relevant if you're reasoning about how a specific device was configured.

> ⚖️ **Authorization:** Require Attention is a real obstacle to *non-consensual* biometric unlock. Compelling a subject to look at their phone with open eyes is a more invasive act than pressing a finger to a sensor, and several courts have treated the *act of unlocking* — biometric or not — as potentially testimonial (see the Fifth-Amendment split below). Do not engineer around attention detection (forcing eyes open, etc.) without explicit, documented legal authority; the gesture is exactly the kind of compelled communicative act courts are scrutinizing.

### Presentation attacks and the liveness response

The FAR (below) is a *random-stranger* number; the *adversarial* threat is a **presentation attack** — a deliberate artifact (photo, video, mask, fake finger) presented to the sensor. The architecture answers this on a different axis from matching:

- **Touch ID** was defeated within days of the iPhone 5s launch by the Chaos Computer Club (2013) using a high-resolution photograph of a latent print lifted from glass, printed and cast into a thin-film "fake finger." Apple's response has been incremental sensor improvements (subdermal/capacitive ridge sensing, larger sample area) rather than a liveness silver bullet; a *good* fabricated finger remains the canonical Touch ID PAD (presentation-attack detection) challenge.
- **Face ID** was designed with PAD as a first-class requirement, because a face is photographed constantly. Defenses: the **depth map** (a 2D photo has no depth), **IR imaging** (defeats screens/most prints), **randomized dot projection**, neural networks **specifically trained on real-world masks and media to detect spoofing**, and **attention/gaze** (defeats sleeping/unconscious subjects and most static media). Researchers (notably Bkav, 2017) built elaborate composite masks that fooled early Face ID under controlled conditions, but the cost/precision required is far beyond opportunistic attack — which is the point of a consumer biometric: raise the bar above the threat model (a stranger or thief), not above a nation-state.

> 🔬 **Forensics note:** Presentation attacks matter to *investigators* in two ways. Offensively, they are almost never a practical acquisition path on modern hardware — far easier to pursue passcode (consent/compulsion) or an AFU full-filesystem extraction. Defensively/analytically, an *allegation* that "someone spoofed my Face ID" is testable: enrollment configuration, the difficulty of the specific attack, and the absence of liveness-bypass artifacts all bear on plausibility. Don't let a courtroom claim of a movie-plot mask attack go unexamined.

### Exactly when biometrics are force-disabled and the passcode is required

This is the heart of the lesson for both builders and examiners. Apple documents a fixed list; on iOS/iPadOS 26 it is these six conditions (the SEP demands the passcode and biometrics will not unlock until it is entered):

| # | Condition | Plain meaning | Forensic relevance |
|---|---|---|---|
| 1 | The device has just been turned on or restarted | **BFU** — before first unlock since boot | Hard floor: in BFU almost everything is cold; biometrics are *never* available until first passcode entry |
| 2 | The device hasn't been unlocked for more than **48 hours** | Escrow-key max lifetime elapsed | Don't let a seized AFU device idle past 48 h or you lose Class A data on next interaction |
| 3 | The passcode hasn't unlocked the device in the last **6.5 days (156 h)** *and* a biometric hasn't unlocked it in the last **4 hours** | The "you've coasted on your face/finger too long" rule | Periodic forced passcode even on a device in daily use |
| 4 | The device received a **remote lock** command | e.g. Find My "Mark As Lost" / remote lock | Why you **network-isolate at seizure** — a remote lock (or wipe) reaches over any live radio |
| 5 | After **five unsuccessful** match attempts | Biometric lockout | Why you never "just try it a few times"; five misses demotes to passcode and burns the AFU escrow path |
| 6 | After initiating **power off / Emergency SOS** (press and hold a volume button + the side button ~2 s) | The "panic squeeze" | A one-gesture, intentional anti-forensic disable — covered below |

A seventh, related mechanism is **not** on Apple's "passcode required" list but is the one that actually destroys evidence over time:

- **Inactivity reboot** (introduced iOS 18.1, present on 26.x). An idle, *locked* device that has not been unlocked for a sustained window (Apple's implementation uses a SEP-side timer in the **~72-hour** range; the exact threshold has shifted across point releases — **verify the current value for the OS build you're examining**) will **reboot itself**, which transitions the device from AFU all the way to **BFU**. Conditions 2 and 3 only *demote AFU to "passcode-required-but-still-AFU"* (Class A cold, Class C still warm); the inactivity reboot goes further and resets the *entire* keybag to cold. For an examiner holding a seized phone, this is the doomsday clock — it actively converts a partially-readable device into a fully-encrypted one while it sits in the evidence locker.

> 🔬 **Forensics note:** Map every row above to an operational lever the moment a device is seized and *powered on and in AFU*:
> - Keep it **powered and charged** (never let the battery die → BFU).
> - Keep it **network-isolated** (Faraday bag / airplane-mode-then-RF-shield) to defeat condition 4 (remote lock) **and** remote wipe.
> - Get it to the lab and into acquisition **inside the 48-hour window** (condition 2) and *well* inside the inactivity-reboot window (the ~72 h reboot is the harder deadline).
> - **Never** attempt biometric unlock speculatively — condition 5 (five fails) burns it; and never hand the device back to the subject (condition 6, the squeeze).
> - If the subject is cooperative/compelled with authority, a *single* correct biometric or passcode entry is worth more than any number of guesses.

### Condition 6 in depth: the "panic" squeeze as a designed countermeasure

Holding the **side button and either volume button** for about two seconds raises the power-off / Medical-ID / Emergency-SOS slider screen. The instant that screen appears, iOS **disables biometrics and arms the passcode requirement** — even if you cancel and don't actually power off or place an SOS call. Apple ships this *on purpose*: it is the documented way for a user under duress to instantly demote their phone to passcode-only (which, being something you *know* rather than something you *are*, enjoys stronger Fifth-Amendment protection in US courts). The same effect is reachable by simply powering off (→ BFU) or by the older "press the side button five times" SOS trigger on some models.

> 🔬 **Forensics note:** This is the single most common **anti-forensic action a subject takes between probable cause and seizure**, and it takes under two seconds in a pocket. Treat any seized phone as potentially already squeezed: it may *look* AFU (recent activity) yet demand a passcode on the next unlock attempt. The squeeze does **not** by itself drop you below AFU — Class C / "Complete Until First User Authentication" data stays decryptable on an AFU device — but it removes the biometric on-ramp, so your remaining paths are the passcode (consent/compulsion) or what an AFU full-filesystem extraction can reach without it.

### Two different lockout counters: biometric vs. passcode

Don't conflate the two failure counters — they escalate on entirely separate ladders, and only one can destroy data:

| Counter | Trips after | Consequence | Recoverable? |
|---|---|---|---|
| **Biometric** | **5** consecutive non-matches | Biometrics disabled; **passcode required** | Yes — enter the passcode and biometrics work again |
| **Passcode** | Escalating **time delays** after ~5–6 wrong passcodes (1 min → 5 → 15 → 60…) | Progressively longer lockouts | Yes — wait out the delay |
| **Passcode + "Erase Data"** | **10** wrong passcodes *if the user enabled* Settings → Face ID & Passcode → **Erase Data** | Device **wipes** (Effaceable Storage shredded → keys gone) | **No** |

The biometric counter is *cheap*: five misses just demote you to passcode-required (still AFU). The passcode counter is *dangerous*: with **Erase Data** on, the 10th wrong passcode triggers a cryptographic wipe by shredding the Effaceable Storage key material — irreversible. This is exactly why **you never speculatively guess a passcode on a seized device** and why a brute-force path must go *under* the OS counter (a BootROM-level acquisition, available only on A8–A13 per the [grounded baseline](forensics-and-dev-workstation-setup); A14+ has no public BootROM exploit). Biometrics, by contrast, have *no* erase-on-failure path — the worst a wrong face does is cost you one of five tries.

> 🔬 **Forensics note:** Before *any* unlock attempt, establish whether **Erase Data** is enabled (it is off by default but commonly turned on by privacy-conscious or high-risk subjects). If it is on and you don't have the passcode through consent/compulsion, on-device passcode guessing is off the table entirely — the device must be acquired through a method that doesn't increment the OS passcode counter, or not at all.

### The false-accept rates Apple publishes (and the asterisks)

Apple's documented **false-accept rates** (the probability a *random* person could unlock your device), single enrolled identity:

| Modality | Documented FAR (random person, single enrolled appearance/finger) |
|---|---|
| **Face ID** | ~**1 in 1,000,000** |
| **Touch ID** | ~**1 in 50,000** |

The asterisks matter and are themselves documented by Apple:

- The Face ID figure is for a **single enrolled appearance**. Enrolling an **alternate appearance** raises the aggregate probability of a random match (more enrolled reference data → a looser overall acceptance surface). Apple's own support documentation states the probability rises to **up to 1 in 500,000 with two appearances** enrolled. Treat "1 in 1,000,000" as the *single-appearance* best case, not a constant.
- FAR is a **statistical population claim about random strangers**, *not* an adversarial bound. It says nothing about a determined attacker with a fabricated mask or a high-fidelity 3D model — that's the **presentation-attack** threat the liveness/attention networks address, on a different axis entirely.
- Apple explicitly notes the probability is **higher for identical twins and siblings who look like you, and for children under 13** (whose facial features may not be sufficiently developed). Touch ID's figure similarly degrades for closely related ridge patterns and is per-enrolled-finger — Apple documents the aggregate rising to **~1 in 10,000 with five fingerprints** enrolled (more fingers → higher aggregate FAR).
- These are **false-*accept*** rates. The **false-*reject*** rate (you, denied) is much higher and is the everyday "it asked for my passcode" annoyance — and the deliberate behavior in all six conditions above.

> 🔬 **Forensics note:** The FAR is occasionally raised as an argument that a *stranger's* face/finger could have unlocked a device. For single-enrollment Face ID at 1-in-a-million it is not a credible defense; but if the device had **multiple appearances enrolled** or **multiple fingers**, or the subjects are **close relatives / a parent and minor child**, the aggregate probability is materially higher and the enrollment configuration becomes a fact worth establishing.

### Stolen Device Protection: biometrics with *no passcode fallback*

iOS 17.3+ (present on 26.x) adds **Stolen Device Protection (SDP)**. When enabled and the device is **away from familiar locations**, certain sensitive actions (viewing saved passwords, turning off Lost Mode, erasing the device, changing the Apple Account password, *disabling SDP itself*, etc.) require a **biometric match with no passcode fallback**, and the most sensitive ones add a **one-hour Security Delay** followed by a *second* biometric. This inverts the usual "passcode is the escape hatch" model specifically to defeat a thief who has shoulder-surfed the passcode. It is a security-architecture fact about biometrics worth holding alongside the disable conditions; the full treatment is in [advanced-protections-lockdown-sdp-adp](advanced-protections-lockdown-sdp-adp).

> 🔬 **Forensics note:** With SDP on and the lab being an "unfamiliar location," even a *known* passcode will not let you perform the high-risk operations — they demand a live biometric you may not be able to compel, and impose the Security Delay. SDP state is therefore something to determine early; it changes what's possible even when you "have the passcode."

### The compelled-biometrics vs. passcode legal split (US)

This is where the architecture collides with constitutional law, and the split is squarely about the very distinction this lesson draws — *something you know* (the passcode) vs. *something you are* (your face/finger):

- **The passcode is firmly Fifth-Amendment protected.** Compelling a person to *disclose* a passcode is **testimonial** — it reveals the contents of the mind — so it triggers the privilege against self-incrimination. (State supreme courts, e.g. **Utah** in *State v. Valdez*, **2023**, have gone further and held that even *adverse comment* on a refusal to give a passcode violates the privilege.) The government's escape hatch is the narrow **"foregone conclusion"** doctrine, which courts apply inconsistently to passcodes.
- **Biometrics are a genuine circuit split.** The argument *against* protection: pressing a finger or showing a face is a **physical act**, like giving a blood sample or a key — not a communication, "no cognitive exertion." The **Ninth Circuit in *United States v. Payne* (2024)** took this view: compelled fingerprint unlock was **not testimonial**. The argument *for* protection: the act of unlocking implicitly asserts *"this is my phone, I know how to open it, this print is the password to this device"* — which is communicative. The **D.C. Circuit in *United States v. Brown* (Jan. 2025)** took *that* view: compelled thumbprint unlock **was testimonial** and violated the Fifth Amendment. The Brown court's reasoning extends naturally to Face ID. The Supreme Court has not yet resolved it.
- **Practical upshot for an examiner.** The legal route available to you depends on jurisdiction *and* on whether you're seeking the passcode (broadly protected) or a biometric (split). This is precisely why **the suspect's two-second SOS squeeze — converting the phone to passcode-only — is a deliberate legal-posture move, not just a technical one**: it pushes the device from the contested-biometric column into the better-protected passcode column.

> ⚖️ **Authorization:** None of this is a workaround you decide unilaterally. *Whether* you may compel a biometric, *whether* you may compel a passcode, and *what* a warrant authorizes are determined by the warrant's scope and controlling precedent in your circuit — and the law is actively shifting (a live circuit split with no Supreme Court resolution as of 2026). Get specific legal authority for the *specific* act, document it, and preserve the device state (network-isolated, powered, AFU) while that authority is obtained — because every disable condition above is also a clock running against your legal process.

### Where the API surface meets the architecture (builder's view)

Two developer entry points, two different trust levels:

- **`LocalAuthentication` / `LAContext.evaluatePolicy(...)`** — `.deviceOwnerAuthenticationWithBiometrics` (biometrics only) or `.deviceOwnerAuthentication` (biometrics **or** passcode fallback). This is a **policy gate**: a `true`/`false` from the SEP-mediated subsystem. It does **not** bind any data; an app that merely branches on the boolean can be bypassed by a runtime hook (`evaluatePolicy` is a classic Frida swizzle target — see [objection-swizzling-and-runtime-exploration](objection-swizzling-and-runtime-exploration)). Use it for UX gating, never as your only line of defense.
- **Keychain access control** — `SecAccessControlCreateWithFlags(..., .biometryCurrentSet | .biometryAny | .userPresence, ...)` on a keychain item. This is a **cryptographic binding**: the item's key is held by the SEP and is released *only* on a live biometric match. `.biometryCurrentSet` additionally **invalidates the item if the enrolled set changes** (a finger/face added or removed) — because, as established, the SEP owns enrollment and notices. This is the path that actually resists a hooked app: the secret never materializes without the SEP's say-so.

The keychain item's **protection class** (the *accessibility* attribute) is orthogonal to the biometric flag and equally load-bearing for what survives a lock or an acquisition:

| Accessibility attribute | Decryptable when… | Acquisition exposure |
|---|---|---|
| `kSecAttrAccessibleAlways` *(deprecated)* | Always, even BFU | Worst case — readable in a BFU dump |
| `kSecAttrAccessibleAfterFirstUnlock` | After first unlock (AFU) until reboot | Readable in an **AFU** extraction |
| `kSecAttrAccessibleWhenUnlocked` | Only while unlocked | Not in a locked-state dump |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | Only with a passcode set; never leaves device/backup | The recommended base for biometric-gated secrets |

Pair the strongest accessibility class (`WhenPasscodeSetThisDeviceOnly`) with a `.biometryCurrentSet` access control to get a secret that is *both* unavailable at rest without unlock *and* SEP-gated on a live, current-enrollment match. There is also a separate API signal builders use to *detect enrollment changes*: `LAContext.evaluatedPolicyDomainState` — an opaque blob that **changes whenever the enrolled biometric set changes**. Re-authenticating high-value flows when `domainState` differs from the last-seen value is the supported way to notice "a new finger/face was added since I last trusted this device."

The `LAError` codes a flow returns are themselves a readable state machine — useful to builders for branching and to examiners as a signal of *why* a gate refused:

| `LAError` | Meaning |
|---|---|
| `.biometryNotAvailable` | No biometric hardware, or app denied biometric permission |
| `.biometryNotEnrolled` | Hardware present but no face/finger enrolled |
| `.biometryLockout` | Five failed matches (condition 5) — passcode required to re-enable |
| `.passcodeNotSet` | No device passcode → no Data Protection root → biometrics unavailable |
| `.userFallback` | User tapped "Enter Passcode" instead of presenting biometrics |
| `.userCancel` / `.systemCancel` / `.appCancel` | Cancelled by user / OS (e.g. app backgrounded) / app |

> 🔬 **Forensics note:** The distinction is also an *artifact* distinction. A `.biometryCurrentSet`-protected keychain item is **unrecoverable** without a live match on the original SEP — even a full keychain extraction yields a blob the SEP won't unwrap elsewhere. An app that "protected" a secret with only `evaluatePolicy` and then stored the secret in plaintext (or with default `kSecAttrAccessibleWhenUnlocked`) leaks it to an AFU extraction. When triaging a third-party app's security (Part 08 / Part 11), check *which* mechanism it used — the difference is recoverable-vs-not. Note too that `.passcodeNotSet` is the architectural tell that **biometrics without a passcode is impossible by design**: with no passcode there is no key-hierarchy root for a match to gate.

## Hands-on

There is **no on-device shell** and you have no physical device. Everything below runs on the Mac and exercises the *parsing/policy/API* surface; none of it can reproduce a real SEP match or real key release (the Simulator has no SEP).

**Switch to full Xcode first** (the SDK ships `simctl`; Command Line Tools alone does not):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcrun simctl help | grep -iE 'boot|ui|keychain'   # confirm simctl resolves
```

**Boot a Simulator and locate its (unencrypted) keychain + containers:**

```bash
# Create + boot a device, then find its data root
UDID=$(xcrun simctl create "biolab" "iPhone 16 Pro")
xcrun simctl boot "$UDID"
DEV=~/Library/Developer/CoreSimulator/Devices/$UDID/data

# The Simulator's keychain is a plain SQLite file on your Mac (no SEP, no encryption)
ls -l "$DEV/Library/Keychains/keychain-2.db"
```

**Inspect a keychain item's access-control intent (copy before query — the [forensic-artifacts](app-sandbox-and-filesystem-layout) discipline applies even in the Simulator):**

```bash
cp "$DEV/Library/Keychains/keychain-2.db" /tmp/kc_sim.db
sqlite3 /tmp/kc_sim.db ".tables"          # genp, inet, cert, keys, ...
# The access-control blob lives in the 'genp'/'inet' tables; in the Simulator it
# is recorded but NOT enforced by an SEP — it documents *intent*, not protection.
```

**Drive Face ID in the Simulator UI** (the only way to "match" — there is no `simctl` biometric verb): Simulator menu → **Features → Face ID → Enrolled**, then **Features → Face ID → Matching Face** / **Non-matching Face** to feed a canned success/failure into `LAContext`. (Touch ID Simulators expose the parallel **Features → Touch ID** menu.)

**Reset Simulator keychain state between runs** (so a stale ACL'd item doesn't confound a lab — there is a `simctl keychain` verb on recent SDKs):

```bash
xcrun simctl keychain "$UDID" reset      # wipes the Simulator device's keychain
# Re-create your test item afterward; confirm domainState before/after enrollment toggles.
```

**Confirm the policy/biometry availability from outside the app** is *not* directly exposed by `simctl`; availability is an in-process `LAContext` property (`biometryType`, `canEvaluatePolicy`). The Mac-side observable is the unified-log stream above — on a real device the richer signal lives in the `com.apple.biometrickitd` / `com.apple.coreauthd` subsystems, which the Simulator does not run.

**Watch the authentication subsystem in unified logs on your Mac** (the *same* `os_log` plumbing the device uses, minus the device-only daemons):

```bash
# On a real device this surfaces coreauthd/biometrickitd; on the Mac/Simulator it
# shows the LocalAuthentication client path. Mechanism is identical; SEP is not.
log stream --predicate 'subsystem CONTAINS "com.apple.LocalAuthentication"' --info
```

**Minimal LocalAuthentication probe** (drop into a Simulator app to see the *policy* path, not key release):

```swift
import LocalAuthentication
let ctx = LAContext()
var err: NSError?
if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
    print("biometryType:", ctx.biometryType.rawValue)   // .faceID / .touchID / .opticID / .none
    // domainState changes whenever the ENROLLED SET changes — the supported way to
    // detect "a face/finger was added or removed since I last trusted this device":
    print("domainState:", ctx.evaluatedPolicyDomainState?.base64EncodedString() ?? "nil")
    ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                       localizedReason: "Unlock the vault") { ok, e in
        print("policy result:", ok, e ?? "")            // a BOOLEAN — binds nothing
    }
}
```

> ⚠️ **ADVANCED (device-only):** The bypass below and the `biometrickitd`/`coreauthd` log inspection in Lab 2 require a **physical, jailbroken device** and on-device `frida-server` — none of it is reproducible in the Simulator, and running it weakens the target's runtime integrity. It is narrated here as a read-only walkthrough; do **not** treat it as a step to perform. The Simulator stand-ins teach the same downstream skill (which guard protects a secret) without touching device security.

**Demonstrate why `evaluatePolicy` is not security (described — needs a device + jailbreak; see [dynamic-analysis-with-frida](dynamic-analysis-with-frida)).** On a real device, the canonical bypass is a one-line Frida hook that forces the completion handler's success branch — e.g. intercepting `-[LAContext evaluatePolicy:localizedReason:reply:]` and invoking `reply` with `(YES, nil)`, or replacing `evaluatePolicy(_:error:)` to return `true`. It works precisely because the app *trusted a boolean it computed in its own address space*. The same hook does **nothing** against a `.biometryCurrentSet` keychain item: the secret is in the SEP, the hook never sees it, and no forged boolean makes the SEP unwrap. This is the architecture's whole payoff — and the reason an app-security review (Part 11 / OWASP MASTG) must establish *which* mechanism guards a secret before calling it protected.

## 🧪 Labs

> **Substrate note for all labs:** these run on the **Xcode Simulator** and **read-only walkthroughs**. The Simulator runs macOS frameworks and has **no SEP, no Data-Protection-at-rest, no biometric template, and no key release** — `LAContext` returns a *simulated* boolean and keychain ACLs are *recorded but not cryptographically enforced*. The device-only auth daemons (`biometrickitd`, `coreauthd`, `sks`/Secure Key Store) do **not** populate Simulator stores. These labs teach the *API surface, the policy semantics, and the seizure decision logic* — the real cryptography is taught from the mechanism above and from sample images in Part 07/08.

### Lab 1 — Policy gate vs. cryptographic binding (Simulator)

**Goal:** feel the difference between `evaluatePolicy` (a boolean) and a keychain item bound to `.biometryCurrentSet` (a key the SEP gates).

1. Boot a Simulator; **Features → Face ID → Enrolled**.
2. In a scratch app, call `evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`; trigger **Matching Face** then **Non-matching Face** and observe the boolean flip. Note: nothing was encrypted.
3. Now store a secret with `SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error)` and read it back with **Matching Face**.
4. **Fidelity caveat:** on a *device*, step 3's secret would be SEP-held and unrecoverable without a live match on that SEP; here it is just a row in `/tmp/kc_sim.db`. Dump the table to *see the recorded ACL intent*, and write one sentence on why an attacker who can hook `evaluatePolicy` (step 2) cannot get the step-3 secret on real hardware.

### Lab 2 — Read the "passcode required" reasons from the auth subsystem (Simulator + walkthrough)

**Goal:** connect the six conditions to observable log/`LAContext` signals.

1. With a Simulator booted, run `log stream --predicate 'subsystem CONTAINS "com.apple.LocalAuthentication"' --info` while you toggle **Enrolled** off/on and feed match/non-match. Watch the policy-evaluation lines.
2. In the scratch app, after **five** consecutive **Non-matching Face** events, inspect `LAContext().evaluatePolicy` error codes — you should be able to reach `LAError.biometryLockout` (the Simulator models condition 5's lockout semantics even without a real SEP).
3. **Walkthrough (device-only, narrate — do not perform):** on a real seized phone you'd instead read `biometrickitd`/`coreauthd` subsystem messages and the unlock-source from a logical/AFU acquisition to infer *which* of the six conditions demanded the passcode. **Fidelity caveat:** those daemons and the real lockout timer do not exist in the Simulator; you are learning the *signal shape*, not capturing the device event.

### Lab 3 — Seizure-state preservation decision tree (read-only tabletop)

**Goal:** internalize the operational levers as a checklist you could run cold.

1. Draw the state machine: `BFU → (passcode) → AFU-biometrics-live → (any disable condition) → AFU-passcode-required → (inactivity reboot / power loss) → BFU`.
2. For each of the six disable conditions **plus** the inactivity reboot, write the **one action** that prevents it from firing on a seized, powered, AFU device (power, charge, network-isolate, don't-touch-biometrics, don't-return-to-subject, beat-the-48 h-and-~72 h-clocks).
3. Cross-check against [bfu-vs-afu-and-data-protection-classes](bfu-vs-afu-and-data-protection-classes): for BFU, AFU-passcode-required, and AFU-biometrics-live, list which Data Protection classes are readable in each. **Fidelity caveat:** validate your class-readability table against a Josh Hickman reference image's documented lock-state in Part 07 — do not assert it from memory.

### Lab 4 — Detect an enrollment change with `domainState` (Simulator)

**Goal:** see the SEP-owned-enrollment fact surface in the API as a change-detection signal.

1. With a Simulator booted and **Face ID → Enrolled**, run the Hands-on Swift probe and record the `domainState` base64 blob.
2. Toggle **Features → Face ID → Enrolled** off, then on again (a fresh enrollment). Re-run the probe.
3. Observe that `domainState` **changed** — this is exactly the signal `.biometryCurrentSet` uses internally to invalidate bound keychain items. Write one sentence connecting "domainState changed" → "a `.biometryCurrentSet` secret would now be unreadable."
4. **Fidelity caveat:** the Simulator models the *domainState-changes-on-enrollment* contract but performs no real key invalidation (no SEP). On a device, step 2 would render any `.biometryCurrentSet`-bound secret permanently unrecoverable.

## Pitfalls & gotchas

- **"Biometrics bypass Data Protection" — no.** The single most common conceptual error. Biometrics *gate* a SEP-held key; the passcode *is* the root. A phone with biometrics enabled is no less encrypted; it just has a faster on-ramp that the SEP can revoke.
- **`evaluatePolicy` is not security by itself.** Branching on its boolean protects nothing cryptographically and is a textbook Frida/`objection` bypass. The cryptographic version is a keychain ACL (`.biometryCurrentSet` / `.userPresence`). Audit which one an app used before trusting it.
- **The 48-hour timer and the ~72-hour inactivity reboot are different deadlines.** 48 h (condition 2) demotes AFU to passcode-required *without rebooting* (Class C still warm). The inactivity reboot actually *reboots to BFU*. Examiners must beat the **shorter-impact 48 h** for biometrics and the **harder ~72 h** for staying out of BFU. **Verify the current inactivity-reboot threshold for the exact iOS build** — it has moved across point releases.
- **"Just try the face a few times" destroys the on-ramp.** Five non-matches (condition 5) trips biometric lockout. There is no free retry budget at seizure.
- **A device that looks AFU may already be passcode-locked.** The two-second SOS squeeze (condition 6) leaves recent activity intact but disables biometrics silently. Never infer "biometrics will work" from "the phone was clearly in use."
- **Network is a remote-lock/wipe vector, not just exfil.** Condition 4 (remote lock) and remote *erase* reach over any live radio. Faraday-isolate *before* powering the screen, not after.
- **FAR is a population statistic, not an adversarial bound, and not a constant.** 1-in-1,000,000 is single-appearance Face ID; alternate appearances, multiple fingers, twins/close relatives, and under-13s all change the number. Don't quote the best case as if it were universal.
- **Simulator fidelity is zero for the cryptography.** No SEP, no template, no key release. The Simulator teaches the API and the policy semantics; lock-state/encryption behavior must come from sample images.
- **`.biometryAny` vs `.biometryCurrentSet`.** `.biometryAny` survives enrollment changes (convenient, weaker); `.biometryCurrentSet` invalidates on any add/remove of a face/finger (stronger, the SEP-noticed binding). Know which a given item used — it changes both security and recoverability.
- **`.deviceOwnerAuthentication` silently allows passcode fallback.** Builders who want *biometrics only* must use `.deviceOwnerAuthenticationWithBiometrics`; the plain `.deviceOwnerAuthentication` policy succeeds on the passcode too. Mixing them up is a common bug that quietly downgrades a "Face-ID-gated" flow to "anyone with the passcode," and an examiner who knows the difference can sometimes exercise the fallback you assumed was closed.
- **The biometric counter and the passcode-Erase-Data counter are unrelated.** Five wrong faces only demote to passcode (harmless, recoverable); ten wrong passcodes *with Erase Data on* wipes the device irreversibly. Never let a "just try it" instinct cross from the safe counter into the dangerous one.
- **Enrollment can be changed by anyone holding the passcode.** Adding a face/finger requires only the passcode, not an existing biometric — so a coerced or shoulder-surfed passcode lets an attacker *enroll their own* biometric. `.biometryCurrentSet` items defend against this (they invalidate), but unlock and most flows do not.

## Key takeaways

- Biometrics are an **unlock method**, not a Data-Protection bypass: a match only authorizes the SEP to use a key it already holds in escrow; the **passcode is the cryptographic root**.
- The **template is computed and sealed inside the SEP at enrollment**, never leaves the device, is excluded from backups/iCloud, and is therefore **not a recoverable artifact** — only policy/event *metadata* is.
- After first unlock, with biometrics on, the **Complete-class keys are re-wrapped and held by the biometric subsystem for ≤ 48 h**; the six disable conditions are exactly the events that make the SEP **discard that wrapper**.
- The six conditions — **BFU, 48 h idle, 6.5-day/4-hour rule, remote lock, five failed matches, the SOS squeeze** — are the examiner's whole game at seizure; plus the **~72 h inactivity reboot** that silently demotes AFU→BFU in the evidence locker (verify the exact threshold per build).
- **Require Attention (gaze)** is an iOS-only liveness/coercion defense Touch ID can't have; the **SOS squeeze** is a deliberately-shipped one-gesture anti-forensic countermeasure.
- Apple's documented **FAR is ~1-in-1,000,000 (Face ID, single appearance) and ~1-in-50,000 (Touch ID, single finger)** — a random-stranger statistic that worsens with more enrollments, twins/relatives, and young children; it is **not** an adversarial bound.
- For builders: `evaluatePolicy` is a **bypassable UI gate**; a keychain **`.biometryCurrentSet` ACL** is the cryptographic binding that resists hooks and invalidates on enrollment change.
- **Stolen Device Protection** inverts the model — biometrics with **no passcode fallback** plus a Security Delay for sensitive actions away from familiar locations.

## Terms introduced

| Term | Definition |
|---|---|
| Secure Neural Engine | The neural-engine block *inside* the SEP that converts TrueDepth captures into the Face ID mathematical representation and performs matching; never exposes data to the app processor |
| Biometric template | The sealed mathematical representation of a face/finger/iris, computed and stored only in the SEP; not an image, not exportable, excluded from backups/iCloud |
| Optic ID | Apple Vision Pro's iris biometric; shares the SEP-sealed-template + match-releases-keys architecture with Face ID/Touch ID (sensor differs) |
| Sensor pairing | Factory cryptographic binding of a Touch ID/Face ID sensor to its specific SEP; an unpaired (e.g. replaced) sensor is untrusted and biometrics are disabled (the "Error 53" behavior) |
| Presentation attack (PAD) | An adversarial spoof (photo, video, mask, fake finger) presented to the sensor; countered by depth/IR/liveness/attention rather than by the matching threshold |
| `evaluatedPolicyDomainState` | Opaque `LAContext` blob that changes whenever the enrolled biometric set changes; the supported signal for detecting enrollment changes |
| Secure Key Store (`sks`) | The SEP's protected in-memory key store holding live class keys and the biometric escrow wrapper after first unlock; unreadable by the application processor |
| Escrowed class-key wrapper | The biometric-subsystem-held key (lifetime ≤ 48 h) that re-wraps the Complete-class keys after first unlock so a match can unwrap them without the passcode |
| AFU / BFU | After-First-Unlock / Before-First-Unlock — the lock states that decide which Data Protection classes are decryptable; biometrics are unavailable in BFU |
| Require Attention (gaze detection) | Face ID setting requiring open eyes directed at the device before a match counts; a liveness and anti-coercion control with no Touch ID/Mac analogue |
| Biometric lockout | The state after five consecutive failed matches (condition 5) in which biometrics are disabled until the passcode is entered (`LAError.biometryLockout`) |
| SOS squeeze | Holding side + a volume button (~2 s) to raise the power-off/SOS screen, which immediately disables biometrics and requires the passcode — a designed duress/anti-forensic control |
| Inactivity reboot | The SEP-timer (introduced iOS 18.1, ~72 h range; verify per build) that auto-reboots an idle locked device, demoting AFU→BFU |
| False Accept Rate (FAR) | Probability a random person could match; ~1/1,000,000 Face ID (single appearance), ~1/50,000 Touch ID (single finger); degrades with more enrollments, twins/relatives, under-13s |
| `LAContext.evaluatePolicy` | LocalAuthentication call returning a SEP-mediated boolean; a UI **policy gate** that binds no data and is a common runtime-hook bypass target |
| `kSecAccessControlBiometryCurrentSet` | Keychain access-control flag binding an item's key to the SEP and the *current* enrolled set; invalidates the item if a face/finger is added or removed |
| Stolen Device Protection (SDP) | iOS 17.3+ feature requiring biometrics with no passcode fallback (plus a Security Delay) for sensitive actions away from familiar locations |

## Further reading

- **Apple Platform Security Guide** (help.apple.com/pdf/security, March 2026 edition) — "Face ID, Touch ID, and Optic ID security," "Facial matching security," "Secure Enclave," and the Data Protection key-hierarchy sections (the canonical source for the escrow/key-release mechanism and the FAR figures).
- **Apple Support** — "Optic ID, Face ID, Touch ID, passcodes, and passwords" (`sec9479035f1`, the authoritative six-condition list); "About Face ID advanced technology" (HT102381); "Biometric security" (`sec067eb0c9e`).
- **Apple Developer** — `LocalAuthentication` framework reference; `SecAccessControlCreateWithFlags` / `LAPolicy` docs; Stolen Device Protection support notes.
- **Legal (US)** — Center for Democracy & Technology, "Circuit Court Split … on Biometric Cell Phone Unlocking"; Arnold & Porter, *U.S. v. Brown* (D.C. Cir. 2025, compelled thumbprint held testimonial) vs. *U.S. v. Payne* (9th Cir. 2024, held non-testimonial); ABA, "Compelled Biometrics and Fifth Amendment Rights."
- **Forensics** — Sarah Edwards (mac4n6.com) and Alexis Brignoni (iLEAPP) on lock-state/biometric-event artifacts; SANS FOR585 on AFU/BFU acquisition strategy; Elcomsoft / Magnet (GrayKey) blogs on seizure-state preservation and the inactivity-reboot deadline; Josh Hickman reference images for validating lock-state class readability.
- **Presentation-attack research** — Chaos Computer Club, "Chaos Computer Club breaks Apple TouchID" (2013); Bkav, "Bkav's new mask beats Face ID" (2017) — the canonical spoof writeups behind the liveness discussion (read as adversarial *context*, not as a practical acquisition path).
- **man pages / tools** — `xcrun simctl` (the `keychain`, `boot`, `create` verbs), `log`, `security`; Frida + `objection` for demonstrating the `evaluatePolicy` bypass (see Part 11).

---
*Related lessons: [[06-biometrics-hardware-faceid-touchid]] | [[02-data-protection-and-keybags]] | [[03-passcode-bfu-afu-and-inactivity]] | [[01-sep-sepos-deep-dive]] | [[08-keychain-on-ios]] | [[09-advanced-protections-lockdown-sdp-adp]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[06-objection-swizzling-and-runtime-exploration]]*
