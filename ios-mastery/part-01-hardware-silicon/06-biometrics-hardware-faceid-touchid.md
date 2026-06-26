---
title: "Biometrics hardware: Face ID & Touch ID"
part: "01 — Hardware & Silicon"
lesson: 06
est_time: "40 min read + 15 min labs"
prerequisites: [secure-enclave-hardware]
tags: [ios, hardware, biometrics, faceid, touchid, sep]
last_reviewed: 2026-06-26
---

# Biometrics hardware: Face ID & Touch ID

> **In one sentence:** Face ID and Touch ID are not "a camera" or "a fingerprint reader" plus software — they are dedicated optical/capacitive sensor arrays wired over a **factory-paired, AES-encrypted channel** into a Secure Neural Engine that lives behind the Secure Enclave boundary, such that no raw biometric image ever crosses into the Application Processor and an untrusted sensor is cryptographically refused.

## Why this matters

You are about to spend Parts 03 and 07 reasoning about *when* biometrics unlock the device, when they get force-disabled into a passcode-only (AFU→BFU) state, and what that means for whether a seized phone is even decryptable. None of that reasoning is sound unless you first understand the **hardware trust boundary**: where the sensor ends, where the SEP begins, what travels on the wire between them, and why a third-party screen swap silently kills Face ID. The match decision and the key-release path are Part 03 ([[biometrics-security-architecture]]); the legal compelled-biometrics-vs-passcode line is Part 03/07. This lesson stays on the **silicon and the sensors** — the substrate every later claim rests on. Get the boundary wrong and you will misread an artifact, mis-scope a repair, or make a false statement about what a passcode protects that biometrics do not. It also pays off on the *builder* side: when you call `LocalAuthentication` / `LAContext` in Part 10, knowing that your app only ever receives a verdict (never the biometric) tells you exactly what your code can and cannot trust, and why "store the fingerprint" is a question with no valid answer.

## Concepts

### Two sensors, one destination

Face ID (TrueDepth, every iPhone since iPhone X and the Pro/Air iPads) and Touch ID (the capacitive ring on the home button, the side button on Touch-ID iPhones/iPads, and — the analogue you already know — the Mac power button and the Magic Keyboard) are radically different at the front end and **identical at the back end**. Both terminate in the same place: a portion of the **Secure Neural Engine**, gated by the **Secure Enclave (SEP)**, reached over a **dedicated, encrypted, factory-paired link** that the Application Processor (AP) cannot read.

That shared destination is the whole architecture. Memorize this invariant before anything else:

```
  ┌─────────────┐   factory-paired, AES-encrypted, authenticated channel
  │   SENSOR    │ ─────────────────────────────────────────────────────┐
  │ (TrueDepth  │   (raw frames NEVER traverse the AP / iOS / app)      │
  │ or Touch ID)│                                                        ▼
  └─────────────┘                                          ┌──────────────────────────┐
        ▲                                                  │   Secure Enclave (SEP)   │
        │  controlled by sepOS, not iOS                    │   ─ sepOS kernel         │
        │                                                  │   ─ biometric app        │
  ┌─────────────┐    BiometricKit / LocalAuthentication    │   ─ template store (enc) │
  │ App / iOS /  │ ◄── match? yes/no ───────────────────── │   ─ Secure Neural Engine │
  │     AP       │    (one bit + key release; never data)  │     (secure mode)        │
  └─────────────┘                                          └──────────────────────────┘
```

The AP — and therefore iOS, your app, an attacker who owns the kernel — gets exactly **one bit back** ("matched / did not match"), plus, on a match, the SEP's *release* of class keys. It never gets the depth map, the IR image, the fingerprint raster, or the stored template. That is the entire design intent, and it is enforced in hardware, not policy.

> 🖥️ **macOS contrast:** You met Touch ID on the Mac — the power-button sensor on Apple-silicon MacBooks and the **Magic Keyboard with Touch ID**. The back-end story is the *same*: the Mac's Secure Enclave (in the M-series SoC, or the T2 on the last Intel Macs) holds the templates; the sensor is factory-paired to that specific SEP. What the Mac **lacks** is the front end of Face ID — there is no TrueDepth array on any Mac. The dot-projector/IR-camera depth subsystem is an iPhone/iPad-distinctive piece of silicon. (Apple Vision Pro adds a *third* modality, Optic ID / iris, on the same SEP-backed pattern; out of scope here, but note the architecture generalizes.)

### Face ID front end: the TrueDepth camera array

The TrueDepth module sits in the top bezel (the "notch" through iPhone 13, the Dynamic Island cutout from iPhone 14 Pro onward — but the *sensors* are the same family). It is not one camera; it is a coordinated array of discrete dies packed across that cutout:

```
   ┌──────────────────── top bezel / Dynamic Island ────────────────────┐
   │  [IR cam]  [flood illum.]  [prox.]  [amb. light]  [front cam]  [dot proj.] │
   │     ▲            ▲                                      ▲            │ │
   │     │            │ even IR fill                         │ visible    │ │ ~30k IR dots
   │  reads depth+IR  └──────────────┐               (NOT used to match)  ◄─┘ │
   └────────────────────────────────┼──────────────────────────────────────┘
                                     ▼
                       depth map + 2-D IR image  ──signed──▶  SEP / Secure Neural Engine
```


| Component | What it is | What it produces |
|---|---|---|
| **Dot projector** | A VCSEL laser + diffractive optics that fan one beam into **>30,000** discrete near-IR dots | A structured-light pattern thrown onto the face; its deformation encodes 3-D depth |
| **Flood illuminator** | A diffuse near-IR LED | Even IR illumination so the IR camera sees the face in total darkness / any ambient light |
| **Infrared (IR) camera** | A near-IR-sensitive imager | (a) the **2-D IR image** of the face under flood light; (b) the **depth map** read from the dot pattern |
| **Proximity / ambient sensors** | Standard front-sensor cluster | Wake/attention gating, exposure |
| **Front RGB ("selfie") camera** | The visible-light camera | *Not* part of the match — Face ID never uses the color image to authenticate |

The capture sequence is a tight hardware pipeline, not a single snapshot:

1. **Wake / presence.** The proximity sensor (and a raise/tap) wakes the cluster; the **flood illuminator** bathes the scene in diffuse near-IR so the **IR camera** can confirm a face is actually present before the laser fires.
2. **Project.** The **dot projector** throws its ~**30,000**-dot structured-light grid onto the face.
3. **Read depth + IR.** The IR camera reads how the dots **shift and warp** across the face's contours — closer surfaces shift the dots more — and from that disparity reconstructs a **depth map**; in the same burst it captures the flat **2-D IR image** under flood light.
4. **Hand off.** The **depth map + IR image** pair (the raw biometric) is signed and pushed over the protected channel into the SEP/Secure Neural Engine. *Nothing here touches the RGB camera or iOS image stack.*

Near-IR (~940 nm) is invisible, works in total darkness, and sees through most eyeglasses; the VCSEL dot projector is an **eye-safe Class 1 laser** under normal operation (this is why the array self-disables and triggers a "TrueDepth camera" alert if the optics are cracked or tampered — a safety interlock that doubles as a tamper signal). The **3-D depth** is the whole point: it defeats a flat photograph, which is exactly why Apple moved off the 2-D-only face unlock everyone else shipped.

**Face ID is *structured light*, not LiDAR — don't conflate them.** The rear **LiDAR Scanner** (iPhone 12 Pro and later Pro models, Pro iPads) is a *separate* sensor: a direct-time-of-flight (dToF) emitter on the back, used for AR depth, focus, and photography — it has **nothing to do with authentication** and never feeds the SEP. Face ID's front depth comes from **structured light** (measuring dot-pattern deformation), a different physical principle living in a different module facing the other way. A surprising number of write-ups get this wrong; in a forensic report, calling Face ID "LiDAR" is a tell that the author doesn't understand the hardware.

Two anti-spoofing properties are baked into the **hardware path**, not bolted on in software:

- **Per-device random dot pattern.** The projected pattern is a device-specific random pattern, and the sensor randomizes the *sequence* of 2-D-image and depth-map captures. A replayed/forged capture can't be precomputed because the challenge differs per device and per attempt.
- **Liveness via depth + (in Part 03) the neural-net attention/anti-spoof models.** Depth alone kills photos; the on-SEP networks (enrollment/matching detail is Part 03) handle masks and "attention" (eyes open, looking at the device).

> 🔬 **Forensics note (physical exam):** In a teardown the TrueDepth components sit as discrete dies across the top bezel/Dynamic Island — flood illuminator and dot projector flanking the IR camera and front camera, with the proximity and ambient sensors. For a hardware examiner this matters two ways. First, any of these is a single point of failure: damage or replace one and biometrics fail (see the pairing section). Second, the cluster's flex routes through the **display assembly**, which is why a *screen* swap — not just a camera swap — can break Face ID. Photograph the bezel under magnification before any disassembly; a reworked/reballed module or a mismatched flex is visible evidence of prior tampering.

> 🔬 **Forensics note:** None of the TrueDepth raw data is recoverable from a disk image — there is no `FaceID.depthmap` file, by design (see "what the hardware refuses to do" below). What you *can* recover on a real device is **operational telemetry**: unified-log entries from `biometrickitd` and the SEP's biometric subsystem record match/no-match **events and timestamps** (not the biometric content). In a timeline ([[building-a-unified-timeline]]) those events corroborate *attended* unlocks — a successful Face ID match at 02:14 is strong evidence a face was in front of the device at 02:14 — without ever exposing the face itself. Capture them with a sysdiagnose ([[unified-logs-sysdiagnose-crash-network]]); they are absent from a Simulator (the Simulator has no `biometrickitd` match pipeline — see Labs).

**The TrueDepth array is not only an unlock sensor.** The same depth + IR hardware drives **Animoji/Memoji** tracking, **attention awareness** (the screen dims and notifications stay hidden when you're *not* looking; volume lowers when you are), Portrait-mode selfie depth segmentation, and front-camera autofocus assist. That has a security consequence and a forensic one. Security: only the **Face ID match path** runs inside the SEP; the Animoji/attention consumers receive *derived, non-identifying* face geometry (a generic mesh / gaze vector) through the normal `ARKit`/`AVFoundation` stack — Apple's boundary is that the **biometric template** never leaves the SEP even though *generic* face data is exposed to entitled apps. Forensic: because the IR camera and attention pipeline run far more often than unlocks, attention telemetry can place a *gaze at the screen* at times when no unlock happened — useful, but don't overclaim it as an "unlock."

**Face ID hardware has iterated; the architecture has not.** First shipped on iPhone X (2017); iPad Pro (2018+) added a **landscape/any-orientation** variant (multiple capture geometries); iPhone 13 sped matching and shrank the notch; through the **2026 fleet (iPhone 17 / Air / 17 Pro on A19/A19 Pro)** it is still the same TrueDepth depth-plus-IR design behind the Dynamic Island — **under-display Face ID has been rumored for years but has not shipped as of iOS 26.5.** Every generation feeds the same SEP/SNE/factory-paired back end; treat "which Face ID generation" as a *front-end packaging* question, never a security-model one.

### Touch ID front end: the capacitive RF fingerprint sensor

Touch ID is a **capacitive** sensor, not optical. The historically published parameters (original Touch ID generation; later sensors iterate on the same principle): an **88×88-pixel array at 500 ppi**, ~170 µm thick, ringed by a **stainless-steel detection ring** that wakes the sensor the instant skin contact closes the capacitive loop. It does not photograph the finger. It reads the **subdermal ridge-flow** — the live tissue layer beneath the surface skin — by sensing the capacitance difference between ridges (close to the array, higher capacitance) and valleys (farther, lower) across the raster.

Crucially, the on-sensor analysis is **lossy by design**: it maps ridge-flow *angles* and discards the minutiae (the ridge-ending/bifurcation points) that a forensic latent-print examiner would need to reconstruct an actual fingerprint. The stored template is a directional ridge-flow representation, not a recoverable print. So even with full SEP compromise (which does not exist publicly), you do not get back an AFIS-comparable fingerprint.

Touch ID has shipped in three physical packages — same capacitive principle, same SEP back end, different placement (which changes only the teardown and pairing-scope picture, never the security model):

| Form factor | Where | Devices (examples) |
|---|---|---|
| **Home-button** (sapphire-covered ring) | Front, below the screen | iPhone 5s → 8/SE-gen; older iPads |
| **Side-button** (capacitive, smaller die in the power button) | Top/side edge | iPad Air (4th+), iPad mini (6th+), iPad (10th gen) |
| **Detachable peripheral** | Mac power button / **Magic Keyboard** | Apple-silicon Macs |

(Touch ID "2nd gen," from iPhone 6s, is the same sensor type, roughly 2× faster matching — a throughput change, not an architecture change. Under-display optical/ultrasonic fingerprint readers — the Android approach — Apple has researched but never shipped; every Apple Touch ID to date is capacitive.)

Put the two modalities side by side on the dimensions that actually matter to you:

| Dimension | Face ID (TrueDepth) | Touch ID (capacitive) |
|---|---|---|
| Sensing physics | Near-IR structured-light depth + IR image | Capacitive subdermal ridge-flow |
| Raw biometric | Depth map + 2-D IR image | ~88×88 @ 500 ppi ridge-flow raster |
| Liveness | 3-D depth + attention/anti-spoof nets | Live subdermal tissue (capacitance) |
| Sensor location | Top bezel / Dynamic Island (in display assembly) | Home/side button, or Mac keyboard |
| Apple FMR claim (random person) | ~1 in 1,000,000 | ~1 in 50,000 |
| Back end | **Identical** — Secure Neural Engine, SEP, factory-paired AES channel, on-SEP template | **Identical** |

The false-match-rate figures are Apple's published single-enrolled-identity numbers (they degrade with close relatives / twins for Face ID and are not the point here); note they are *policy/quality* properties of the matcher, which is Part 03 — listed only to anchor that the two front ends feed the same trust boundary at different raw fidelities.

> 🖥️ **macOS contrast:** This is byte-for-byte the same sensor philosophy as the Mac's Touch ID. The difference that bites forensically is *placement and pairing scope*: on a Mac with a Magic Keyboard, the sensor is in a **detachable peripheral** that is securely paired to that Mac's Secure Enclave — re-pairing happens at first use over a Bluetooth/USB association the SEP authenticates. On iPhone/iPad the sensor is soldered and paired at the factory. Same cryptographic contract, different physical packaging.

### The back end: the Secure Neural Engine inside the SEP boundary

Both sensors hand their raw capture to the **Secure Neural Engine (SNE)** — the matrix-math accelerator that turns a depth-map-plus-IR-image (Face ID) or a ridge-flow raster (Touch ID) into a **mathematical representation** (template), and compares a live capture against the enrolled template. The SNE is part of the SEP's trust domain, and *how* it is built changed across generations — a detail that matters because it tells you exactly where the isolation is enforced:

| SoC generation | Secure Neural Engine implementation | Isolation mechanism |
|---|---|---|
| **A11 – A13** (e.g. iPhone X–11) | A **dedicated** neural engine **integrated into the Secure Enclave**, using DMA for throughput | An **IOMMU under the sepOS kernel's control** confines its DMA to authorized memory regions |
| **A14 / M1 and later** (incl. **A19/A19 Pro**, M5 — the 2026 fleet) | Implemented as a **secure mode in the Application Processor's main Neural Engine** (the big ANE is *shared*, time-sliced) | A **dedicated hardware security controller** switches the ANE between AP tasks and SEP tasks and **resets Neural Engine state on every transition**; a separate engine applies **memory encryption, authentication, and access control** with a **separate cryptographic key and memory range** so the secure mode can only touch authorized memory |

The A14+ design is the subtle one: the *same* physical Neural Engine that runs your app's Core ML model also runs the Face ID match — but a hardware controller flips it into a secure mode, hands it SEP-owned encrypted memory under a key the AP never sees, runs the match, then **scrubs all Neural Engine state** before handing the silicon back to iOS. So even though the accelerator is shared for area/efficiency, there is no residue: the AP cannot observe intermediate activations, and a malicious app's ANE workload cannot read the prior face-match tensors. On the 2026 A19/A19 Pro this rides on the broader SPTM/TXM/MIE hardening stack ([[kernel-hardening-pac-sptm-txm-mie]]) — but the biometric isolation is its *own* controller, older than and independent of that ladder.

```
   AP timeline on the shared Neural Engine (A14+ … A19):

   ── app Core ML ──▶│ [HW security controller: switch + STATE RESET]
                     │   secure mode: SEP-owned encrypted memory, SEP key
                     │   ── Face ID / Touch ID match ──▶ result bit
                     │ [STATE RESET + switch back]
                     ▼
   ── app Core ML ──◀ (no residue of the biometric tensors remains)
```

What the SNE actually *emits* is the **mathematical representation** Apple's docs keep referring to: not an image, but a compact, fixed-shape **feature vector** (a neural-network embedding) derived from the depth map + IR image, or from the ridge-flow raster. Matching is a distance/similarity test between the live vector and the enrolled one — which is why it tolerates day-to-day variation (glasses, beard growth, a slightly different finger angle) yet still rejects strangers. The exact embedding, the enrollment refinement, and the match threshold are the matcher's *algorithm* (Part 03); the hardware fact to carry forward is that the on-disk-equivalent of your biometric is a **one-way embedding sealed inside the SEP**, not a stored picture — there is no inverse function that turns it back into a face or a print.

> 🖥️ **macOS contrast:** The macOS course taught you the Secure Enclave as the keeper of FileVault's volume keys and the place `keychain-2.db` secrets get unwrapped. Same SEP, same sepOS, same "AP asks, SEP answers, secrets never cross." Biometrics is just another consumer of that boundary: the SEP that unwraps your Mac's FileVault key on a Touch ID match is doing on iPhone exactly what it does on your Mac, with a fancier front-end sensor.

### The match decision — and the throttling — live in the SEP, not iOS

This is a hardware-trust point even though the *policy* numbers are Part 03. When the SNE compares a live capture to the enrolled template, the **comparison and its yes/no verdict happen inside the SEP's trust domain**. iOS does not see the template, does not run the matcher, and does not get to *decide* the answer — it gets handed a verdict. The mechanism that releases keys on success is the same one the macOS course taught you for FileVault: the SEP holds the wrapped class keys / keybag, and a successful biometric verdict authorizes the SEP to **unwrap and release** the relevant keys to the AP for use. The AP never holds the long-term key material in a form it can exfiltrate for the protected classes; it gets *use* of the key, mediated by the SEP. (The full keybag/class-key choreography is [[data-protection-and-keybags]]; the unlock-state transitions are [[passcode-bfu-afu-and-inactivity]].)

Critically, the **anti-hammering counter is SEP-enforced**, not an iOS preference an attacker can patch out. The SEP maintains the count of consecutive failed biometric attempts and **demotes to passcode-only after the limit** (and applies escalating passcode delays from there). Because that counter and its limits live behind the SEP boundary, jailbreaking iOS or owning the kernel does **not** let you brute-force biometrics — there is nothing in AP-visible memory to flip. This is the hardware reason "just keep presenting faces/fingers" is not an acquisition strategy. The exact thresholds (5 attempts, 48 h, 72 h inactivity reboot) are Part 03; what you own *here* is the fact that the **silicon, not the OS, is the enforcer**.

### The factory-paired encrypted channel — and why a swap kills it

Here is the load-bearing security claim of the whole subsystem, and the one with the most field consequences. The link between the **sensor** and the **Secure Enclave** is not a dumb ribbon cable carrying plaintext frames. It is an **encrypted, authenticated session**:

- A **shared key is provisioned at the factory** for **each individual sensor and its corresponding Secure Enclave**. For Touch ID, Apple states it plainly: the channel is "encrypted and authenticated with a session key that's negotiated using a shared key provisioned for each Touch ID sensor and its corresponding Secure Enclave **at the factory**," and "for every Touch ID sensor, the shared key is **strong, random, and different**." The session uses **AES-CCM** for authentication and confidentiality. Face ID's TrueDepth data is likewise **digitally signed** and delivered to the Secure Enclave over a protected path.
- The pairing is **1:1 and immutable in the field.** This *specific* sensor is married to *this* SEP. The SEP will only accept biometric frames from a sensor that proves possession of the shared key.

The consequence is the thing you keep reading about in repair forums: **swap the front sensor assembly (TrueDepth array) or, on many models, the display flex that carries it — or the Touch ID button — and Face ID / Touch ID stops working entirely.** Not "degrades," not "needs recalibration" in the cosmetic sense — the SEP sees a sensor that cannot prove the shared key and **refuses to trust it**. The biometric simply becomes unavailable; the device falls back to passcode. Genuine Apple repair flows re-run a **pairing/calibration** step (Apple's tooling, and the on-device "parts and service" pairing on modern iOS) that re-establishes trust for an authentic part; an unauthorized swap cannot. This is *security working as designed* — it is precisely what stops an attacker from soldering in a malicious sensor that injects a forged "match" — even though it is also what frustrates third-party screen repairs.

> 🔬 **Forensics note:** This pairing has a direct investigative read. If you receive a device and Face ID/Touch ID is **disabled despite an obviously intact-looking front**, that is evidence of a **prior sensor/display swap or tamper** — note it, photograph it, and treat the front assembly as possibly not original. Modern iOS surfaces unauthorized/used parts in **Settings → General → About → Parts and Service History**; a genuine-but-unpaired or non-genuine part shows there. (Don't *toggle* anything — observe.) Separately: because biometrics being unavailable forces **passcode-only** entry, a swapped-and-broken Face ID can be the reason a phone is sitting in a harder-to-acquire state than its model would suggest ([[bfu-vs-afu-and-data-protection-classes]]).

### What the hardware deliberately does *not* do

State these as hard guarantees, because half of misinformed biometrics claims are violations of one of them:

1. **No raw biometric image ever leaves the SEP.** The depth map, IR image, and fingerprint raster are processed inside the SEP/SNE trust domain and discarded. They are **not** written to disk, **not** in a backup, **not** synced to iCloud, **not** sent to Apple.
2. **Only a protected mathematical *template* is stored — inside the SEP.** It is held "in an encrypted format that can be read only by the Secure Enclave" and **never leaves the device**. There is no file you can carve, no SQLite row, no plist. (Contrast the wealth of *other* artifacts you carve elsewhere — biometrics is the deliberate void.)
3. **The template is not reversible to a face or a fingerprint.** Touch ID's analysis discards minutiae; Face ID stores a mathematical representation, not a picture. Even granting (impossible, today) a full SEP read, you do not reconstruct the person's biometric.
4. **The AP gets one bit + key release, never data.** iOS, your app via `LocalAuthentication`, and any kernel-level attacker can learn *whether* a presented biometric matched and can be *handed* an unwrapped key on success — they cannot learn *what* was presented.

> ⚖️ **Authorization:** The hardware boundary you just learned has a sharp legal edge you will drill in Part 03/07. In US case law a **passcode** is frequently treated as *testimonial* (protected by the Fifth Amendment — compelling it can be compelled-speech), while a **biometric** (a face, a fingerprint) is more often treated as *non-testimonial* (like a key or a blood draw) and **can be compelled**. That asymmetry is exactly why the hardware also lets a user **instantly demote to passcode-only** — the same hardware fallback a sensor swap forces — and why an arriving examiner's first move may be to *prevent* further biometric attempts and force a BFU/passcode state. The mechanism (5 failed tries, 48 h, the inactivity-reboot 72 h → AFU→BFU, "Emergency SOS" disabling biometrics) is [[passcode-bfu-afu-and-inactivity]]; the chain-of-custody handling is [[ios-forensics-landscape-and-authorization]]. Know now that the *hardware* makes "decline biometrics, demand passcode" a first-class, instant operation — that is not an accident.

> ⚠️ **ADVANCED (device handling):** The flip side of "biometrics can be compelled" is that a **seized, still-unlockable device must be protected from *accidental* biometric input and from the clock**. Pointing the front of a live AFU iPhone at a person's face, or leaving a finger near the home button, can unlock it (or burn one of the limited attempts toward the demote-to-passcode threshold). And the **72 h inactivity-reboot → AFU→BFU** transition runs on a hardware timer you cannot pause — every hour a seized device sits powered-on idle is a step toward a harder-to-acquire BFU state. On-scene practice (Faraday isolation, keep-powered-and-charged vs. deliberate state decisions, never presenting a biometric without authority) is [[ios-forensics-landscape-and-authorization]] and [[the-acquisition-taxonomy]]; the point *here* is that all of it is forced by **hardware behavior**, not software settings you can change.

## Hands-on

There is **no on-device shell**, and — critically for this topic — **the Simulator has no SEP, no Secure Neural Engine, and no real biometric sensor**. Everything below runs on your Mac. The Simulator commands exercise the *API surface and app behavior*; the Mac-hardware commands let you inspect a **real** Secure Enclave (your Mac's own), which is the closest faithful analogue you have without a phone.

### Drive the Simulator's (faked) biometrics

```bash
# Boot a Face ID device and an app that uses LocalAuthentication
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator

# Enrollment + match are GUI toggles: Simulator menu →
#   Features → Face ID → Enrolled        (toggle enrollment on)
#   Features → Face ID → Matching Face    (the next LAContext eval "succeeds")
#   Features → Face ID → Non-matching Face (the next eval "fails")
# Touch ID devices show Features → Touch ID with the same options.
```

There is no real SEP behind that toggle — the "match" is a host-side switch the Simulator feeds to `LocalAuthentication`. It validates **your app's enrollment/match/fallback code paths**, nothing about the silicon.

### Probe a *real* Secure Enclave — your Mac's

```bash
# Which biometry does THIS machine expose? (run as a tiny Swift script)
cat > /tmp/biom.swift <<'EOF'
import LocalAuthentication
let c = LAContext()
var e: NSError?
let ok = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
print("canEvaluate:", ok, "biometryType:", c.biometryType.rawValue, "(0=none 1=TouchID 2=FaceID 4=OpticID)")
if let e { print("error:", e.localizedDescription) }
EOF
swift /tmp/biom.swift
# e.g. → canEvaluate: true biometryType: 1 (0=none 1=TouchID 2=FaceID 4=OpticID)
#   biometryType 1 = Touch ID  → your Mac has the power-button/keyboard sensor.

# Identify the Secure Enclave / Secure Storage component on this Mac
system_profiler SPiBridgeDataType        # Intel+T2: names the "Apple T2 Security Chip"
system_profiler SPHardwareDataType | grep -i chip   # Apple silicon: the M-series SoC hosts the SEP

# The biometric daemon exists on macOS too — watch its (content-free) events
log show --last 1h --predicate 'process == "biometrickitd"' --style syslog | tail -40
# You'll see enroll/match *events* and result codes — never a fingerprint.

# Surface the SEP manager / biometric sensor nub in the IORegistry (names vary
# by Mac model/OS — grep broadly, don't assume a fixed class name):
ioreg -l | grep -iE 'biometric|enclave|AppleSEP' | head
# A Touch-ID Mac shows an SEP manager and a biometric sensor entry; a Mac
# without Touch ID shows the SEP but no biometric sensor nub.
```

`biometryType` returning `.touchID`/`.faceID`/`.opticID`/`.none` is the *same* `LAContext` API an iOS app calls — you are exercising the real framework against a real SEP, just on Mac hardware. The values are the actual enum raw values you'll parse in iOS app code later ([[the-ios-security-model]]).

### What a connected real device would expose (walkthrough — no device here)

```bash
# With a trusted, unlocked iPhone attached, libimobiledevice reads hardware facts
# (NOT the template — there is no key for that):
ideviceinfo            # full property dump
ideviceinfo -k PasswordProtected      # true/false
# Biometric *capability/enrollment-state* keys live under the
# com.apple.mobile.* and biometric domains; values reflect "is Touch/Face ID
# set up", never the biometric data. Pair + Trust are prerequisites
# (see [[logical-acquisition-with-libimobiledevice]]).
```

## 🧪 Labs

> Each lab names its substrate and its fidelity caveat. None requires a physical iOS device; none can faithfully reproduce the SEP/Secure-Neural-Engine path (the Simulator has no SEP, no Data-Protection, and no real sensor), so the labs target the **API surface, the host SEP, and read-only evidence reasoning** instead.

### Lab 1 — Simulator: enrollment/match/fallback in an app (Simulator; **no real SEP**)

1. `xcrun simctl boot "iPhone 17 Pro"`; `open -a Simulator`.
2. In Xcode, make a one-screen app whose button calls
   `LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock")`.
3. Toggle **Features → Face ID → Enrolled**, run, and tap the button. Use **Matching Face** then **Non-matching Face** and observe the success/failure callbacks. Now toggle Enrolled **off** and read the `LAError` you get back.
4. Switch the policy to `.deviceOwnerAuthentication` (biometrics-OR-passcode) and watch the fallback path engage.

**Fidelity caveat:** the "match" is a host menu switch, not a Secure Neural Engine evaluation; there is **no template, no factory-paired channel, no key release**. This proves *your code* handles enroll/match/fallback — it proves **nothing** about the hardware boundary.

### Lab 2 — Your Mac: interrogate a real Secure Enclave (host Mac; real SEP, *Mac* sensor)

1. Run the `biom.swift` probe above; record your Mac's `biometryType`. (Touch-ID Mac → `1`; a Mac without Touch ID → `0`.)
2. `system_profiler SPiBridgeDataType` (Intel+T2) or `SPHardwareDataType` (Apple silicon) — locate the silicon that *hosts* your SEP.
3. `log show --last 2h --predicate 'process == "biometrickitd"' --style syslog` — find a real match event from when you last unlocked with Touch ID. Confirm you see an **event + result**, and that **no fingerprint data** appears anywhere.

**Fidelity caveat:** this is genuine SEP-backed biometrics, but it is **Mac Touch ID**, not iPhone Face ID — there is no TrueDepth array to inspect. It teaches the *back end* (the part iPhone and Mac share) with full fidelity and tells you nothing about the *front-end* depth optics.

### Lab 3 — Read-only walkthrough: reason about a swapped/unpaired sensor (no device)

1. From the Concepts section, write the exact failure chain for "third-party display swap → Face ID gone": which key is missing, who refuses whom, what the user-visible result is, and what fallback state the device lands in.
2. State precisely where you would look on a real device to *confirm* a prior swap (**Settings → General → About → Parts and Service History**) and what a non-genuine/unpaired part shows there.
3. Connect it to acquisition: if biometrics are unavailable, what authentication remains, and why does that make the device's data-protection state ([[bfu-vs-afu-and-data-protection-classes]]) *harder*, not easier, to defeat?

**Fidelity caveat:** pure reasoning + (on a real case) on-device observation; nothing here is reproducible on the Simulator because the failure is a property of the **factory pairing**, which the Simulator does not model at all.

### Lab 4 — Sample image / sysdiagnose: find biometric *events* without biometric *data* (public sample image; device-only stores)

1. Mount a public iOS reference image (Josh Hickman / Digital Corpora) or an extracted sysdiagnose. Search the unified logs ([[unified-logs-sysdiagnose-crash-network]]) for `biometrickitd` and the SEP biometric subsystem.
2. Locate a successful **match event** and its timestamp. Confirm you can read *that a match occurred and when* — and that **nowhere** in the store is there a depth map, IR image, fingerprint raster, or template.
3. Write the one-line forensic claim such an event supports ("an enrolled face/finger was presented and matched at T") and, just as important, the claim it does **not** support ("*whose* face" — it doesn't say). Cross-check against the lock/unlock state in the same window.

**Fidelity caveat:** this is real device-derived evidence (the Simulator produces no `biometrickitd` match pipeline and no such events), but it is *log telemetry*, not the biometric — which is exactly the lesson: biometrics is an **event source, never an artifact source**.

## Pitfalls & gotchas

- **"Face ID is just a fancy front camera."** No. The match never uses the visible-light RGB camera; it uses the **IR camera + depth map** from the dot projector. A perfect photo on the RGB sensor is irrelevant to authentication.
- **Assuming the Simulator's biometrics tell you anything about security.** The Simulator has **no SEP, no SNE, no sensor, no factory pairing** — its "match" is a menu toggle. Never reason about template storage, the encrypted channel, or spoof resistance from Simulator behavior. Use it only for app-side enroll/match/fallback flow.
- **Believing a template can be exported, carved, or reversed.** There is no on-disk biometric artifact by design. If a tool or vendor claims to "extract the Face ID template," they are wrong or selling the *enrollment-exists flag*, not the biometric.
- **Conflating "biometrics disabled" with "user did it."** A disabled Face ID/Touch ID can mean: a deliberate demote-to-passcode, the 48 h/5-tries/Emergency-SOS rules ([[passcode-bfu-afu-and-inactivity]]) — **or a hardware sensor/display swap that broke the pairing.** Check Parts & Service History before attributing intent.
- **Treating Touch ID's read as a fingerprint image.** It's a lossy subdermal **ridge-flow** map with minutiae discarded — not an AFIS-usable print. Don't promise a latent-print comparison from a Touch ID template.
- **Thinking the shared Neural Engine on A14+ weakens isolation.** The big ANE is shared for efficiency, but a dedicated hardware controller **resets its state** on every AP↔SEP transition and confines its secure mode to a separate key + memory range. Sharing the silicon does **not** mean sharing the secrets.
- **Expecting Face ID hardware on a Mac.** No Mac has TrueDepth. The Mac analogue is **Touch ID only** (power button / Magic Keyboard). Don't write "Mac Face ID."
- **Assuming jailbreak/kernel-compromise lets you brute-force biometrics.** The attempt counter and the demote-to-passcode limit are **SEP-enforced**, not an AP-visible preference. Owning iOS does not get you unlimited tries — there is nothing in AP memory to flip.
- **Confusing "generic face geometry" with "the biometric."** Apps using `ARKit` attention/Animoji get a non-identifying mesh/gaze vector — that is *not* the Face ID template and proves nothing about identity. Don't conflate the two when assessing what an app can access.
- **Reading a `biometrickitd`/attention event as proof of *who*.** A match event proves an *enrolled* face/finger was presented and matched at time T — never *whose*. State the claim the artifact supports, not the one you wish it did.

## Key takeaways

- Face ID (TrueDepth: dot projector ~**30,000** IR dots + flood illuminator + IR camera → **depth map + IR image**) and Touch ID (capacitive **88×88 @ 500 ppi** subdermal ridge-flow sensor) differ entirely at the front end and are **identical at the back end**.
- Both terminate in a **portion of the Secure Neural Engine inside the Secure Enclave's trust domain**; the AP receives **one bit + key release**, never biometric data.
- The sensor↔SEP link is a **factory-paired, AES-CCM-encrypted, authenticated channel** keyed per individual sensor+SEP — strong, random, and different for every unit.
- That pairing is why an **unauthorized sensor/display swap disables Face ID/Touch ID**: the SEP refuses a sensor that can't prove the shared key. It's the same mechanism that blocks a malicious injected sensor — security working as designed.
- **No raw biometric ever leaves the SEP**; only an **encrypted, irreversible mathematical template** is stored, **inside** the SEP — never on disk, never in a backup, never to Apple/iCloud.
- On **A11–A13** the SNE is a dedicated unit *in* the SEP (IOMMU-confined DMA); on **A14/M1+** (incl. the 2026 **A19/A19 Pro**) it's a **secure mode of the shared Application-Processor Neural Engine**, isolated by a hardware controller that **resets state** every transition and uses a separate key + memory range.
- The hardware makes **"decline biometrics, fall back to passcode"** a first-class, instant operation — directly relevant to the compelled-biometric-vs-passcode legal line you'll drill in Part 03/07.
- Forensically, biometrics is a deliberate **artifact void** (nothing to carve) but a useful **event source**: `biometrickitd`/SEP match events timestamp *attended* unlocks, and **Parts & Service History** flags a prior sensor swap.

## Terms introduced

| Term | Definition |
|---|---|
| TrueDepth camera | Face ID's front-end sensor array: dot projector, flood illuminator, IR camera, and supporting sensors that produce a depth map + IR image |
| Dot projector | VCSEL-laser-plus-diffractive-optics module projecting **>30,000** near-IR dots for structured-light depth sensing |
| Flood illuminator | Diffuse near-IR emitter providing even IR illumination so the IR camera works in any/zero ambient light |
| Structured-light depth | Depth recovered from how a known projected dot pattern deforms over a 3-D surface |
| Touch ID | Capacitive fingerprint sensor (~**88×88 @ 500 ppi**) reading subdermal ridge-flow; also on Mac power button / Magic Keyboard |
| Subdermal ridge-flow | The live-tissue ridge orientation Touch ID maps; minutiae are discarded, making the template non-reversible to a print |
| Secure Neural Engine (SNE) | The matrix-math accelerator, gated by the SEP, that builds and compares biometric templates |
| Secure mode (shared ANE) | On A14/M1+ the SNE is a secure mode of the AP's Neural Engine, isolated by a hardware controller with per-transition state reset + separate key/memory |
| Factory-paired channel | The per-sensor, AES-CCM-encrypted, authenticated link whose shared key is provisioned at the factory between a specific sensor and its specific Secure Enclave |
| Biometric template | The encrypted mathematical representation of the enrolled biometric, readable only by the SEP, that never leaves the device |
| `biometrickitd` | The BiometricKit daemon (macOS and iOS) that brokers biometric requests; its logs hold match *events*, never biometric content |
| Parts and Service History | iOS Settings panel that flags non-genuine or unpaired components (incl. a swapped TrueDepth/Touch ID/display) |
| VCSEL | Vertical-Cavity Surface-Emitting Laser — the eye-safe (Class 1) near-IR laser source feeding the dot projector |
| Anti-hammering counter | The SEP-enforced count of consecutive failed biometric attempts; on reaching the limit the SEP demotes to passcode-only (it is not an OS-patchable preference) |
| Attention awareness | Face ID's gaze-detection feature (and the IR/depth telemetry behind it) that runs far more often than unlock matches |
| `LAContext` / `biometryType` | The LocalAuthentication API surface apps use; `biometryType` reports `none`/`touchID`/`faceID`/`opticID` (raw 0/1/2/4) |

## Further reading

- **Apple Platform Security** (current edition, ~March 2026) → "Face ID, Touch ID, and passcodes," "Biometric security," "Facial matching security," and "The Secure Enclave" (Secure Neural Engine A11–A13 vs A14/M1+). The authoritative source for the encrypted-channel and template-storage wording quoted here.
- Apple Support — "About Face ID advanced technology" (support.apple.com/102381) and "The Secure Enclave" (the SNE secure-mode + state-reset description).
- Jonathan Levin, *MacOS and iOS Internals* vol. III (security) + newosxbook.com — the SEP boundary and sepOS from the reverse-engineer's side.
- iFixit — Face ID / TrueDepth and Touch ID teardowns and the "screen swap disables Face ID" repair guides (the field-observable end of the pairing story).
- Eclectic Light Co. (eclecticlight.co) — "A brief history of the Secure Enclave" for the generational SEP/SNE evolution.
- `man log` and `log show --predicate 'process == "biometrickitd"'` — read the daemon's own event vocabulary on your Mac.
- Cross-references: [[secure-enclave-hardware]] (the SEP this all rides on), [[biometrics-security-architecture]] (enrollment + match→key-release, Part 03), [[passcode-bfu-afu-and-inactivity]] (when biometrics force-disable), [[kernel-hardening-pac-sptm-txm-mie]] (the A19 hardening stack the 2026 SNE rides on).

---
*Related lessons: [[secure-enclave-hardware]] | [[biometrics-security-architecture]] | [[passcode-bfu-afu-and-inactivity]] | [[bfu-vs-afu-and-data-protection-classes]] | [[the-ios-security-model]] | [[ios-forensics-landscape-and-authorization]]*
