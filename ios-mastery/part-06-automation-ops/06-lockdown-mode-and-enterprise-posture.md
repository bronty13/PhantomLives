---
title: "Lockdown Mode & enterprise posture"
part: "06 — Automation & Operations"
lesson: 06
est_time: "45 min read + 15 min labs"
prerequisites: [advanced-protections-lockdown-sdp-adp, mdm-supervision-and-abm]
tags: [ios, operations, lockdown-mode, enterprise, hardening]
last_reviewed: 2026-06-26
---

# Lockdown Mode & enterprise posture

> **In one sentence:** This is the operations capstone — taking the *individual* opt-in controls you dissected mechanically in [[advanced-protections-lockdown-sdp-adp]] (Lockdown Mode, Stolen Device Protection, Advanced Data Protection) and combining them with the *fleet* machinery from the rest of Part 06 (supervision, DDM, configuration-profile restrictions) into one coherent, deployable hardening posture for a managed fleet **and** a single high-risk person — and learning to read, at intake, which of those defenses is in force, because each one quietly forecloses a different acquisition avenue.

## Why this matters

You already know the *mechanism* of each defensive feature: [[advanced-protections-lockdown-sdp-adp]] enumerated what Lockdown Mode subtracts, how Stolen Device Protection demotes the passcode, and how Advanced Data Protection deletes Apple's cloud keys. What that lesson deliberately left for here is **operations**: *when* to turn each on, *who* needs them, what they *cost* the user day-to-day, and — the part that ties the whole module together — how to **compose** them with [[mdm-supervision-and-abm]], [[declarative-device-management]], and [[configuration-profiles-and-mobileconfig]] into a single posture you could actually deploy to a journalist, an executive, or ten thousand corporate handsets.

This serves all three of your hats. As an **advisor**, you'll be asked "how do I lock down a phone for someone who's being targeted?" — and the answer is a stack, not a single toggle, with a non-obvious *order of operations*. As a **fleet operator**, the 2026 management story (DDM, the death of legacy software-update commands) changes what "hardened" even means. And as a **forensicator**, every one of these postures reshapes — and usually shrinks — your acquisition surface; a device that arrives at the lab supervised, in Lockdown Mode, with ADP on, and rebooted into BFU is a fundamentally different evidence object than a default phone, and recognizing that *before* you start is what separates a productive intake from a wasted one.

## Concepts

### Two postures, one toolbox

Everything in this lesson draws from a single set of controls, but they assemble into two distinct postures with different threat models:

| | **High-risk individual** | **Managed fleet** |
|---|---|---|
| Who | Journalist, activist, dissident, executive, attorney, anyone "personally targeted" | Corporate/government/edu device estate |
| Primary threat | Mercenary zero-click spyware (Pegasus/Predator-class), targeted physical seizure | Bulk loss/theft, untrusted networks, compliance, supply-chain consistency |
| Authority | The user's own choice (self-applied) | The organization's, via **supervision** + MDM |
| Core levers | **Lockdown Mode**, **ADP**, **SDP**, strong alphanumeric passcode, update discipline | **Supervision** + **DDM** + **restriction profiles** + enforced updates + Activation Lock |
| Key constraint | Usability cost is borne voluntarily | Restrictions must not break productivity; user can't be trusted to self-harden |

The two overlap exactly where it gets interesting — a **high-risk person on a managed fleet** (a newsroom-issued phone, an exec's corporate handset) needs *both* stacks, and they interact in ways with sharp edges (the order-of-operations trap in the playbook below). Keep the columns straight; the rest of the lesson fills them in.

> 🖥️ **macOS contrast:** You hardened macOS in the sibling course with the same individual primitives — **macOS Lockdown Mode** (shipped alongside iOS's, Ventura+), FileVault, and the firmware/Gatekeeper/SIP posture — plus a *config-profile* layer that's largely the same payload format. What iOS/iPadOS adds on top is an entire **fleet** plane that has no real macOS-laptop analogue for *individuals*: **Apple Business/School Manager + Automated Device Enrollment → supervision**, and the **supervised-only restrictions** (like killing host pairing) that simply don't exist for a personally-owned Mac. The individual controls port almost verbatim; the fleet machinery is the genuinely new iOS material. The detection flag is even shared: `LDMGlobalEnabled` in `.GlobalPreferences.plist` reads the same way on both platforms.

### Lockdown Mode in practice: who, when, and the cost

[[advanced-protections-lockdown-sdp-adp]] gave you the enumerated subtraction list (JIT off, attachments/link-previews blocked, unsolicited inbound refused, Shared Albums off, config-profile install blocked, wired data blocked while locked, 2G off). The operational questions it left open:

**Who actually needs it.** Lockdown Mode is *not* general advice. Apple is explicit that it's for "the very few" who are *personally targeted* by state-grade attackers. The honest triage:

- **Yes:** journalists handling sensitive sources, human-rights defenders, dissidents, named targets of an APT, executives/attorneys/diplomats with credible mercenary-spyware exposure, anyone who has *already* shown up in a Citizen Lab / Amnesty notification or received an Apple **threat notification**.
- **No / overkill:** the merely privacy-conscious. Lockdown Mode trades away real functionality for protection against an attacker class most people will never face. Recommending it indiscriminately burns the user's goodwill and they'll turn it off.

**What it costs, concretely.** The subtraction list reads abstract until you live with it. The day-to-day friction:

| You lose | The felt experience |
|---|---|
| WebKit JIT | Heavy web apps (rich editors, some maps, WebGL) are noticeably slower; a few break until you per-site exclude them |
| Non-allowlisted Message attachments + link previews | PDFs/docs/some images don't arrive in iMessage; links show as bare URLs; group threads feel "broken" |
| Unsolicited inbound FaceTime / invites | A new contact can't FaceTime you until *you* call them first; SharePlay/shared-content invites from strangers vanish |
| Shared Albums | Existing shared albums disappear from the device; no new ones |
| Wired data while locked | The phone won't talk to CarPlay-over-cable, a wired-only accessory, or a computer unless you unlock first, every time |
| Config profiles / new MDM | You cannot install a `.mobileconfig` or newly enroll — which **breaks self-onboarding to MDM** (see the order-of-operations trap) |
| 2G | Irrelevant in most of the world; matters only in 2G-only coverage |

**The escape valve.** Lockdown Mode supports **per-site Safari exclusions** (re-enable JIT and full web tech for a trusted domain) and you can exclude specific apps from some restrictions. Teaching a high-risk user to use exclusions *surgically* is what keeps them from rage-quitting the whole mode.

**Apply it everywhere.** Lockdown Mode is per-device. A target's Mac and iPad are part of the same attack surface — enabling it only on the iPhone leaves the laptop as the soft entry point. The advisor's job is to turn it on across the user's **entire Apple ecosystem**, not one device.

> 🔬 **Forensics note — Lockdown Mode is an artifact of *omission*, and now also a managed status item.** Recall from [[advanced-protections-lockdown-sdp-adp]] the two-pronged detection: the **state flag** (`LDMGlobalEnabled = 1` in `/private/var/mobile/Library/Preferences/.GlobalPreferences.plist` / NSGlobalDomain — *verify the exact key against the iOS version you're examining*) and the more robust **negative-space** signature (no link-preview cache, no non-image Messages attachments after enablement, no Shared Albums, FaceTime history only with prior contacts, failed config-profile installs). New from the **WWDC26 (June 2026)** device-management updates: **Lockdown Mode status is becoming a Declarative Device Management *status item*** — a supervised/managed device *reports* its Lockdown-Mode state up the DDM status channel (alongside enrollment type and APNs details; a companion **device-system-health** status item for baseband/camera/Face ID/Touch ID and more lands on **iOS/iPadOS 27**). Rollout spans the 26→27 cycle, so confirm support for the OS you're examining. The payoff: for a *managed* device you may be able to establish the posture from MDM server records, not just the on-disk image.

### When the alarm has already gone off: Apple threat notifications & self-triage

The cleanest answer to "is this person in the *targeted few* who need Lockdown Mode?" is that **Apple already told them.** Since 2021 Apple sends **threat notifications** to accounts it assesses were targeted by **state-sponsored / mercenary spyware** — delivered as a banner at the top of `account.apple.com` (the rebranded `appleid.apple.com`) after sign-in **and** an iMessage + email to the addresses on the Apple Account. Apple deliberately **does not attribute** the actor or reveal its detection signals (revealing them would help attackers evade), and it warns that the notifications could in theory be the bait of a phishing lure — so the verification path is always "sign in to Apple Account directly, don't click through the message."

Receiving one moves the user unambiguously into the Lockdown-Mode-and-ADP column. The operational response — the bit you'll be asked to run:

1. **Don't panic-wipe.** A reflexive erase destroys the very evidence that would confirm and characterize the compromise. Preserve first (an encrypted backup + a `sysdiagnose`), triage, *then* decide on remediation.
2. **Run `mvt` against the preserved data** to match known-campaign **IOCs**. `mvt` is **not** real-time AV — it's indicator matching against curated STIX2 files (Amnesty Security Lab, Citizen Lab et al.) over artifacts like `shutdown.log`, network-usage rows, and WebKit/Safari traces ([[unified-logs-sysdiagnose-crash-network]]). **Absence of detections ≠ clean** (it only knows *known* indicators); a *hit* is high-signal.
3. **Harden + rotate from a clean device.** Enable Lockdown Mode and ADP, update to the latest build (kills the patched delivery chain), and rotate the Apple Account password and critical credentials from a *different, trusted* device.
4. **Escalate to specialists.** Citizen Lab and the **Access Now Digital Security Helpline** / Amnesty Security Lab triage these for at-risk users; for a journalist/activist this is the right referral.

> 🔬 **Forensics note — a threat notification is a starting gun, not a finding.** Treat the notification as *tasking*: it tells you to look, not what you'll find. Build the timeline from the preserved backup/sysdiagnose, run `mvt` for known IOCs, and — because mercenary spyware is increasingly forensically clean — corroborate with the **negative/anomalous** signals (unexplained `shutdown.log` entries, processes/crashes that shouldn't exist, network rows to known C2 infrastructure). The same "evidence from absence" discipline you use to *detect Lockdown Mode* applies to detecting the spyware Lockdown Mode defends against.

### Operating Lockdown Mode: the MDM non-relationship

A point that constantly trips up admins and matters forensically: **Lockdown Mode is not manageable by MDM.** Apple deliberately provides **no** `allowLockdownMode` restriction key — you cannot *force* it on a fleet, and you cannot *forbid* a user from turning it on. It is by design a user-sovereign control for the individually targeted, and Apple has stated it will not build the MDM workflow.

What MDM *does* collide with:

- While Lockdown Mode is **on**, the device **cannot install new configuration profiles** and **cannot newly enroll** in MDM or supervision.
- But a device **already enrolled before** Lockdown Mode is turned on **stays managed** — the existing MDM can still install, update, and remove profiles, and DDM keeps flowing.

That asymmetry is the **order-of-operations trap** for the "high-risk person on a managed fleet" case: you must **enroll/supervise first, then have the user enable Lockdown Mode.** Do it in the other order and the device is stranded — locked-down but unmanageable, and you can't push the corporate restriction profile without the user temporarily disabling Lockdown Mode.

> 🔬 **Forensics note — pairing "lockdown" vs. Lockdown Mode, again.** The single most common terminology crash in iOS forensics (flagged hard in [[advanced-protections-lockdown-sdp-adp]]): **`lockdownd`** + the **pairing/"lockdown records"** in `/var/db/lockdown/` (macOS) / `%ProgramData%\Apple\Lockdown\` (Windows) are the *acquisition gold* you extract from a trusted host to do AFU logical without re-pairing — that subsystem predates the attack-surface **Lockdown *Mode*** by a decade. They pull in *opposite* directions: a pairing record helps you in; Lockdown Mode blocks the wired path that record rides. When any tool or report says "lockdown," resolve which one before you act.

### The seizure-time countermeasure landscape — the defender's view

[[passcode-bfu-afu-and-inactivity]] taught the lock-state machine (BFU/AFU) and the on-device timers as *mechanism*. Here they are as **deployable defenses** — the controls a hardening posture actually leans on at the moment of physical compromise. Two matter most:

**1. Inactivity reboot (the BFU forcing function).** Since iOS 18.1, a **locked** device that sees no unlock for **~72 hours** automatically **reboots itself**, dropping from AFU back to **Before First Unlock**. In BFU the file-protection class keys are evicted from memory and held in the SEP — `NSFileProtectionComplete` data is cryptographically sealed, the keychain is largely inaccessible, and on a modern A14+ device with a strong passcode there is **no public extraction** of meaningful user data. This is the feature that produced the famous "iPhones in the evidence locker mysteriously rebooted" reports. As a defender, it means a seized-and-stashed device **heals itself toward BFU** if the lab can't act within three days.

**2. USB Restricted Mode (the wired-data gate).** The data pins of the Lightning/USB-C port stop carrying data after the device has been **locked ~1 hour**, and **immediately on lock** if no wired data accessory has connected in the past **3 days** (a previously-paired accessory, remembered ~30 days, may still attach inside the 1-hour window). This is what closes the window for a forensic bridge.

**iOS/iPadOS 26 sharpens the wired gate.** The accessory control surfaced as a first-class **"Wired Accessories"** setting (Settings → Privacy & Security), with four levels — **Always Ask**, **Ask for New Accessories**, **Automatically Allow When Unlocked** (the default), **Always Allow** — and an explicit anti-"juice-jacking" framing: even a charger-shaped data attacker now hits a prompt under the stricter settings. For a hardening posture you push the user *off* the default toward **Ask for New Accessories** or **Always Ask**.

| Timer | Trigger | What it costs the user | What it costs the examiner |
|---|---|---|---|
| **Inactivity reboot** | Locked ~72 h with no unlock | One re-unlock after a long idle | AFU→BFU: usually fatal to a no-jailbreak extraction on A14+ |
| **USB Restricted Mode** | Locked ~1 h (or immediately, if 3 d since accessory data) | Re-unlock to use a wired accessory | The ~1 h wired-acquisition window slams shut |
| **Lockdown Mode wired block** | *Any* time locked (no grace) | Unlock every time to connect | Wired window is effectively **zero** |
| **Stolen Device Protection** | Sensitive action away from familiar locations | Biometric (+1 h delay) for re-keying | Passcode alone can't mint a *new* pairing off-site |

The clocks as a timeline, from the moment a default device was last unlocked:

```
  last unlock                +1 h                                      +72 h
      │                        │                                          │
      ▼                        ▼                                          ▼
 ─────●━━━━━━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●──────►
      │   wired window OPEN     │        AFU, wired CLOSED                 │  BFU
      │  (USB Restricted Mode   │   (USB-RM engaged; existing pairing      │  (inactivity
      │   not yet engaged)      │    record still works; SDP may block     │   reboot →
      │                         │    a NEW pairing off-site)               │   class keys
      │                         │                                          │   sealed)
   EXAMINER: pair/acquire here ─┘                                          │
   OWNER:    power OFF anytime  ───────────────────────────────────────►  └─ forced BFU now
             (don't wait for +72 h)
```

> Note: the +1 h USB-RM mark collapses to **0 h (immediate on lock)** if no wired data accessory has connected in the past **3 days**, and to **0 h always** under **Lockdown Mode** (no wired data while locked, ever). The examiner races the left segment; the owner can end the game instantly by forcing BFU.

> 🔬 **Forensics note — read the clocks at intake, they're a depleting asset.** The seizure clocks are the most time-sensitive thing about a live device. If a phone arrives **AFU and unlocked-recently**, you may have a sub-hour USB-RM window and a multi-day inactivity-reboot window — and you spend them in that order. The field doctrine that follows directly from these timers: **keep it powered, keep the screen alive, isolate the radios (Faraday), and get it to the lab fast.** Conversely, a defender who wants the *opposite* outcome (deny the lab) does one thing: **power the device fully off**, forcing immediate BFU — see the vendor-counter-moves section for why "off" beats "wait for the timer."

### The vendor counter-moves: Safeguard Mode & GrayKey Preserve

Apple's seizure-time timers were effective enough that the major extraction vendors shipped **direct responses** in 2026 — and as a defender you should read those products as *intelligence about the offense*:

- **Cellebrite Safeguard Mode** (Spring 2026 release) — designed explicitly to **mitigate the iOS inactivity-reboot timer**: it preserves access to a device and **maintains that access even across a reboot**, letting a team "secure now, extract later" without the AFU state decaying to BFU.
- **Magnet GrayKey Preserve** (announced Feb 2026; with **GrayKey Fastrak** and the consent-based **Verakey/Verakey Fastrak**) — a field capability to **preserve an iOS device's extractable state "indefinitely, in minutes,"** before the device ever reaches the lab, specifically to defeat the inactivity-reboot and other expiration timers. iOS 26 support shipped day-and-date with Apple's release.

What both tools tell you, read as a defender: the offense's answer to the timers is to **freeze the device in AFU** the moment they get it, so that "the timer will save me if the lab is slow" is **no longer a safe assumption** against a well-equipped agency that reaches the device while it's still AFU. The timers protect a device that *lapses* unattended; they do **not** protect a device a capable lab grabs in AFU and immediately preserves.

The robust defender conclusion follows cleanly: **the only state these tools cannot preserve is one that doesn't exist yet — BFU.** A device that is **powered off** (or freshly rebooted) before it falls into adversary hands is in BFU, and a BFU A14+ device with a **strong alphanumeric passcode** has, as of 2026, **no public extraction path** for `Complete`-class data. Hence the at-risk-individual rule that the playbook bakes in: **at any moment of seizure risk — a border crossing, a protest, an arrest — power the phone OFF.** Don't trust the 72-hour timer; create BFU yourself, instantly.

> ⚠️ **ADVANCED / DESTRUCTIVE caveat (device-side):** "Power off to force BFU" is sound *defensive* advice for a device owner protecting their own data, and it is the correct thing to teach a high-risk user. It is the **exact wrong move for an examiner** who has lawfully seized a live AFU device — powering it off *destroys* your AFU advantage and drops you to a BFU you likely cannot beat. Same physical action, opposite parties, opposite outcome. Know which side of the table you're on before anyone touches the power button.

> ⚖️ **Authorization:** The defensive postures here change what a lawful order can *yield*, so they belong in your scoping, not as a surprise at extraction time. A warrant served on Apple for an **ADP** account's Backup/Photos/Drive returns **ciphertext Apple cannot decrypt** (only Mail/Contacts/Calendar remain producible); a **supervised** device with `allowHostPairing = false` cannot be paired to your bridge even with the correct passcode; a **Lockdown Mode** device refuses the wired path while locked. Document the posture you observe — it is the evidentiary basis for *pivoting* (to the device, a local backup, or the counterpart endpoint) and for never representing E2EE cloud data as "available from Apple" in an affidavit. Detecting the posture is part of establishing scope and chain of custody, not an afterthought.

### Patch latency is the real fleet exposure — DDM software-update enforcement

For a managed fleet, the highest-impact "hardening" is the least glamorous: **keeping the OS current.** The mercenary-spyware chains that Lockdown Mode defends individuals against are, for a fleet, mostly a *patch-window* problem — a known CVE on an un-updated handset is the realistic exposure, not a bespoke zero-click. So the operations question is "how fast and how reliably can I force the fleet onto the patched build?" — and in 2026 that machinery changed underneath everyone.

The legacy model was imperative: the MDM server sent `ScheduleOSUpdate`/`AvailableOSUpdates` commands and `OSUpdateStatus` queries, plus a `com.apple.SoftwareUpdate` payload to set deferral and the recommended-cadence. That whole surface is **being removed** — deprecated through the 26.x cycle and **non-functional on the 27.0 releases**. The replacement is **declarative** ([[declarative-device-management]]):

- A **software-update configuration** declaration names a *target OS version* and an **enforced installation deadline** (a wall-clock time after which the device installs and reboots itself, user-deferral exhausted).
- The device **autonomously** downloads, stages, and installs against that declaration — no server polling, no command round-trips.
- The **status channel** reports granular progress (`idle → downloading → staging → installing`, plus failure reasons like *insufficient storage* / *low battery* / *passcode required*) in near-real-time, which is also where the new **Lockdown-Mode status** and **hardware-health** items ride.

The forensic/operational consequence: an admin who has not migrated to declarative software-update enforcement before pushing devices to the 27.0 train **silently loses update control** — the old commands no-op, and the fleet drifts off the patch line exactly when staying current matters most. "Are you on DDM software-update enforcement?" is now a first-order posture question for any fleet you assess.

> 🖥️ **macOS contrast — the management plane converges, but the *update* story differs.** macOS speaks the **same** MDM/DDM protocol, the **same** `.mobileconfig` payload format, and increasingly the **same** declarative software-update enforcement — so the fleet-management muscle you build here transfers to Macs. The divergence is in the substrate: a Mac update is a far heavier operation (a sealed-system-volume swap, often a long install + reboot, on devices users keep awake mid-task), so enforced-deadline updates bite differently than the quick iOS staging cycle; and **supervision** on a Mac is the ADE-derived state too, but the local-admin escape hatches and the `softwareupdate(8)` CLI have no iOS analogue — there is no on-device shell to fall back to on iOS. Same protocol, very different blast radius.

### The travel posture: borders, Faraday, and compelled access

The highest-risk *moment* for a hardened individual is rarely a remote exploit — it's a **physical checkpoint** (a border crossing, a protest stop, a detention) where the device can be seized and the holder can be **compelled or coerced** to unlock it. The operations module's controls compose into a specific travel playbook:

- **Cross borders in BFU.** Before the checkpoint, **power the device fully off** (forcing BFU) — don't rely on the 72-hour inactivity-reboot timer, which won't have fired on a recently-used phone, and don't rely on it being merely locked (AFU is exactly the state preservation tools want). A BFU A14+ device with a strong alphanumeric passcode is the strongest position you can hand a holder.
- **Biometrics are a liability at a checkpoint, not an asset.** Face ID/Touch ID can be applied to a non-consenting person far more easily than a passcode can be extracted from their memory, and in several jurisdictions the legal protection against compelled *biometrics* is weaker than against compelled *passcodes*. The defensive move before a high-risk checkpoint is to put the device in a state that **demands the passcode** — which BFU does automatically, and which the "lockdown" hardware shortcut (squeeze power+volume to force passcode-on-next-unlock) does on the fly.
- **Stolen Device Protection set to "Always"** means even a holder who unlocks under duress cannot be force-walked through re-keying the Apple Account on the spot (the one-hour Security Delay buys the account time).
- **ADP keeps the cloud out of reach** if the *device* is taken but the account isn't — but remember it's a *cloud* control; it does nothing for the device in hand. And re-check ADP availability for the destination jurisdiction.
- **Faraday + power discipline** for anything that must stay on: isolate the radios so a seized-but-on device can't be remotely tracked, wiped, or have its state altered.

> ⚖️ **Authorization:** Border-search authority is a genuinely different legal regime, and you must not flatten it. In the US, the **border-search exception** lets agents conduct a *basic* (manual) device search without a warrant; the case law on *advanced* (forensic/extraction) searches and on **compelling** unlock — and the passcode-vs-biometric distinction (Fifth Amendment "testimonial" arguments) — is unsettled and circuit-dependent, and entirely different abroad. When you advise a traveler, you're advising on **both** a technical posture *and* a legal one you may not be licensed to give — route the legal half to counsel. When you're the *examiner* at a border, the authority you're operating under is narrower and more contested than a warrant; scope and document accordingly.

### The enterprise hardening playbook — tying Part 06 together

Here is the module's payoff: the whole Part-06 toolbox composed into one layered posture. Read it as defense-in-depth — each layer assumes the one below it and closes a different avenue.

```
                THE LAYERED HARDENING STACK (managed fleet | high-risk person)
   ┌──────────────────────────────────────────────────────────────────────────┐
   │ L5  PROCESS / HUMAN     Update discipline · Faraday + power-off at risk ·   │
   │                         periodic mvt self-triage · phishing/social hygiene  │
   ├──────────────────────────────────────────────────────────────────────────┤
   │ L4  CLOUD               Advanced Data Protection (delete Apple's keys) ·    │
   │     (icloud-acq...)     managed Apple Account · Find My / Activation Lock    │
   ├──────────────────────────────────────────────────────────────────────────┤
   │ L3  INDIVIDUAL OPT-IN   Lockdown Mode · Stolen Device Protection (Always) · │
   │     (advanced-prot...)  strong ALPHANUMERIC passcode · Wired-Accessories=Ask │
   ├──────────────────────────────────────────────────────────────────────────┤
   │ L2  POLICY              Configuration-profile RESTRICTIONS                  │
   │     (config-profiles)   com.apple.applicationaccess + passwordpolicy +      │
   │                         DDM software-update enforcement                     │
   ├──────────────────────────────────────────────────────────────────────────┤
   │ L1  MANAGEMENT BASE     Supervision via ABM/ASM + Automated Device Enroll → │
   │     (mdm-superv...)     DDM channel (declarative-device-management)         │
   ├──────────────────────────────────────────────────────────────────────────┤
   │ L0  PLATFORM            SEP · Data Protection · Secure Boot · MIE (A19) ·    │
   │     (security-model)    SPTM/TXM — inherited, not configured                │
   └──────────────────────────────────────────────────────────────────────────┘
```

**For a managed fleet** (the org's authority, applied at L1–L2 + parts of L4):

1. **Supervise via ABM/ASM + ADE.** Supervision is the keystone — it unlocks the restrictions that actually matter (see [[mdm-supervision-and-abm]]). A BYOD/user-enrolled device cannot be hardened to the same degree.
2. **Run it through DDM.** [[declarative-device-management]] is the 2026 standard: declarative configuration + the **status channel** (now including Lockdown-Mode and hardware-health items). It is also **mandatory** for software updates going forward — the legacy MDM software-update commands/queries are being removed (deprecated through 26.x, gone on the 27.0 releases), so **patch latency control = DDM or nothing.** Since unpatched zero-days are the #1 fleet exposure, this is not optional hardening, it's table stakes.
3. **Push the restriction profile** (`com.apple.applicationaccess`, see [[configuration-profiles-and-mobileconfig]]). The high-value supervised keys for a *forensic-resistance* posture:
   - `allowHostPairing = false` — the device pairs **only** with the supervision host. This **kills the forensic-pairing avenue and juice-jacking** in one stroke; arguably the single most consequential anti-acquisition restriction an org can set.
   - Keep `allowUSBRestrictedMode = true` (don't be the admin who *disables* USB Restricted Mode for accessory convenience).
   - `allowEraseContentAndSettings = false` (and `allowDeviceNameModification`, `allowAccountModification`, `allowFindMyDeviceModification = false`) to prevent a thief or coerced user from severing recovery.
   - A strong **passcode policy** via `com.apple.mobiledevice.passwordpolicy` (`minLength`, `requireAlphanumeric`, `maxFailedAttempts`, `maxInactivity`) — *the* lever that makes BFU genuinely safe.
   - `allowESIMOutgoingTransfers = false` to stop identity/number theft via eSIM migration (*verify exact key spelling per OS*).
4. **Enforce Activation Lock org-side** (via ABM-owned Find My) so a lost device is a brick to a thief and re-provisionable to you.
5. **Layer Screen Time / content & privacy** ([[screen-time-and-content-privacy-restrictions]]) where you need user-facing content controls below the MDM line.

**For a high-risk individual** (self-applied, L3–L5 heavy):

1. **Lockdown Mode — ON, across every Apple device.** The highest-leverage single toggle against mercenary spyware; teach surgical per-site/app exclusions so it sticks.
2. **Advanced Data Protection — ON** to close the cloud route ([[icloud-acquisition-and-advanced-data-protection]]) — but **check jurisdiction first** (the UK ADP saga means it may be unavailable there; see [[advanced-protections-lockdown-sdp-adp]]). Set up the Recovery Key and *keep it offline*.
3. **Stolen Device Protection — set to "Always"** (not just "Away from Familiar Locations"), removing the home/work relaxation.
4. **Strong alphanumeric passcode** — the precondition that makes BFU mathematically safe. A 6-digit PIN is brute-forceable in principle against some attacks; a long passphrase is not.
5. **Wired Accessories → "Ask for New Accessories"** (or "Always Ask"); leave USB Restricted Mode engaged.
6. **Update the same day** patches ship — zero-click chains die on patched parsers.
7. **Border/seizure discipline:** **power the device OFF → BFU** before any high-risk checkpoint; Faraday-bag when in doubt.
8. **Periodic self-triage with `mvt`** against a backup/sysdiagnose to catch known spyware IOCs early.

**Ownership model sets the ceiling.** How a device entered management caps how hard you can harden it ([[mdm-supervision-and-abm]]): a **BYOD device under User Enrollment** keeps a cryptographic wall between personal and managed data — the org cannot set the supervised-only restrictions (`allowHostPairing`, `allowEraseContentAndSettings`, etc.) that carry the real anti-acquisition weight. **Device Enrollment** (a personally-owned device manually enrolled) is more managed but still not supervised. Only a **corporate-owned device acquired through ABM/ASM and Automated Device Enrollment** is **supervised** from first boot — and supervision is the gate to the restrictions that matter. So "can I deploy the hardened profile?" is really "is this device supervised?", which is really "did it come through ABM?" The hardening ceiling is set at *procurement*, not at config time.

The two columns **converge** for the high-risk person on a managed fleet — apply both, mind the order-of-operations trap (enroll/supervise → *then* the user enables Lockdown Mode), and accept that some org-side restrictions (host pairing, software-update enforcement) and some user-side controls (ADP, SDP) cover *different* threats and are not redundant.

> 🔬 **Forensics note — the intake triage checklist (read the posture before you touch the wire).** Every layer above forecloses a specific avenue, so determine, at intake, which are in force — it dictates your entire approach:
>
> | Posture | How you detect it | What it forecloses |
> |---|---|---|
> | **Supervised + `allowHostPairing=false`** | Installed-profile inventory; pairing flatly refused even with passcode | New forensic pairing → no AFU logical via a fresh bridge |
> | **Lockdown Mode** | `LDMGlobalEnabled`; negative-space; DDM status item (if managed) | Wired data while locked; the spyware that creates artifacts |
> | **ADP** | Cloud return split (Backup/Photos = ciphertext; Mail/Contacts/Calendar = plaintext) | The warrant-to-Apple cloud route for E2EE categories |
> | **SDP** | Off-site behavior; new-pairing handshake demands biometric, not passcode | Minting a new pairing record off-site with passcode alone |
> | **BFU (post inactivity-reboot or powered off)** | Device boots to passcode-required-before-Touch/Face-ID screen | Essentially everything on A14+ with a strong passcode |
>
> "Is it locked down?" is the wrong question. "**Which of my avenues survives this specific stack?**" is the right one.

## Hands-on

There is no on-device shell — everything runs on your Mac against a Simulator, a public sample image, or a connected (consented/lab) device. Output is described, not pasted live.

### Read the Lockdown Mode flag from a full-file-system image

In a mounted FFS extraction (or a Simulator's data container as a mechanism stand-in), the global-preferences domain carries the flag:

```bash
# Mounted image: the 'mobile' user's global prefs
plutil -extract LDMGlobalEnabled raw \
  /mnt/ffs/private/var/mobile/Library/Preferences/.GlobalPreferences.plist
# -> 1   (Lockdown Mode enabled)   |   error/absent => not enabled / never enabled

# Or dump the whole domain to inspect neighbouring keys
plutil -convert xml1 -o - \
  /mnt/ffs/private/var/mobile/Library/Preferences/.GlobalPreferences.plist | less
```

> Verify the exact key name against the iOS version you're examining; treat the **negative-space** signature (below) as the corroborating evidence, not the flag alone.

### Confirm the negative-space signature

```bash
# After the enablement window you expect: NO non-image Messages attachments,
# NO Shared Albums, FaceTime history only with prior contacts.
# (copy-before-query — even SELECT write-locks SQLite and spawns -wal/-shm)
cp /mnt/ffs/private/var/mobile/Library/SMS/sms.db /tmp/sms.db
sqlite3 /tmp/sms.db "
  SELECT mime_type, COUNT(*) FROM attachment GROUP BY mime_type ORDER BY 2 DESC;"
# A device long in Lockdown Mode shows attachments collapsing to image/video/audio only
```

### Watch USB Restricted Mode / Lockdown Mode block the wired path

With a (lab/consented) device, libimobiledevice surfaces the gate directly:

```bash
idevicepair pair          # On a USB-restricted or LDM-while-locked device:
                          #   -> "Please accept the trust dialog on screen" never appears,
                          #      or pairing fails — the data path is closed until unlock.
ideviceinfo -k ProductVersion   # works only once a data connection is permitted
```

If a **pre-existing** pairing record (lockdown record) is present on the host, an AFU device may still talk to you — contrast that with a freshly-seized device where you have none.

### Inspect / author a restrictions profile

```bash
# Read an existing restrictions payload out of a .mobileconfig
plutil -convert xml1 -o - corporate-restrictions.mobileconfig | \
  grep -A1 -E 'allowHostPairing|allowUSBRestrictedMode|allowEraseContentAndSettings'

# Validate a profile you authored before signing/pushing
plutil -lint hardened.mobileconfig
```

The L2 policy layer in concrete form — the restrictions payload of a hardened supervised profile (the keys that move the *forensic* needle), abridged:

```xml
<dict>
  <key>PayloadType</key>            <string>com.apple.applicationaccess</string>
  <key>PayloadIdentifier</key>      <string>com.example.hardened.restrictions</string>
  <key>PayloadVersion</key>         <integer>1</integer>
  <!-- Supervised-only: device pairs ONLY with the supervision host. -->
  <key>allowHostPairing</key>           <false/>
  <!-- Keep USB Restricted Mode engaged (do NOT set this false). -->
  <key>allowUSBRestrictedMode</key>     <true/>
  <!-- Stop a thief/coerced user from wiping or severing recovery. -->
  <key>allowEraseContentAndSettings</key> <false/>
  <key>allowFindMyDeviceModification</key> <false/>
  <key>allowAccountModification</key>      <false/>
  <!-- Stop identity/number theft via eSIM migration (verify key per OS). -->
  <key>allowESIMOutgoingTransfers</key>    <false/>
</dict>
```

Paired with a passcode-policy payload — the lever that makes BFU actually safe:

```xml
<dict>
  <key>PayloadType</key>          <string>com.apple.mobiledevice.passwordpolicy</string>
  <key>PayloadIdentifier</key>    <string>com.example.hardened.passcode</string>
  <key>PayloadVersion</key>       <integer>1</integer>
  <key>forcePIN</key>             <true/>
  <key>requireAlphanumeric</key>  <true/>      <!-- the difference between safe and theatre -->
  <key>minLength</key>            <integer>8</integer>
  <key>maxFailedAttempts</key>    <integer>10</integer>
  <key>maxInactivity</key>        <integer>5</integer>   <!-- minutes to auto-lock -->
</dict>
```

On a managed device you read the *installed* profile inventory with **Apple Configurator's `cfgutil`** (`cfgutil get installedProfiles`) or your MDM's record; libimobiledevice's `ideviceprovision` lists *provisioning* profiles (developer), which is a different object — don't confuse the two.

### Triage for mercenary spyware with mvt

```bash
# mvt-ios against an encrypted iTunes/Finder backup (the no-jailbreak workhorse)
mvt-ios decrypt-backup -d /tmp/dec  ~/MobileSync/Backup/<UDID>   # prompts for the backup password (or set MVT_IOS_BACKUP_PASSWORD / pass -p <pw>)
mvt-ios check-backup    --iocs ~/iocs/pegasus.stix2  -o /tmp/mvt_out  /tmp/dec
# Or against a sysdiagnose / FFS. Detections land in /tmp/mvt_out as JSON + a timeline.
```

The single highest-signal artifact `mvt` keys on is `shutdown.log` — entries here have repeatedly exposed spyware that lingered through reboots:

```bash
# From an extracted sysdiagnose: clients still holding a SIGTERM at shutdown
grep -nE 'SIGTERM|holding on|signalled' \
  sysdiagnose_*/system_logs.logarchive/../shutdown.log 2>/dev/null | tail -40
# A process that should not exist, repeatedly stalling shutdown, is a classic Pegasus tell.
```

Absence proves nothing (IOC-bound); a hit, or an unexplained process here, is where you pivot to a full timeline (see [[unified-logs-sysdiagnose-crash-network]]).

## 🧪 Labs

> **Substrate note:** Labs 1, 3 are **Simulator / Mac-side authoring** (no SEP, no Data-Protection-at-rest, no AMFI enforcement; the device-only daemons `knowledged`/`biomed`/`powerd`/`routined` do **not** populate Simulator stores, and the Simulator does **not** enforce Lockdown Mode or restrictions — these labs teach *structure and authoring*, not runtime enforcement). Labs 2, 4 are **public-sample-image / read-only walkthroughs** because the lock-state behavior they exercise cannot be reproduced on the Simulator.

### Lab 1 — Author a "high-risk individual" hardening configuration profile (Mac-side authoring)

**Goal:** produce a valid, signable `.mobileconfig` that encodes the L2 policy layer.

1. Write a profile with two payloads: `com.apple.applicationaccess` (set `allowHostPairing = false`, `allowEraseContentAndSettings = false`, `allowUSBRestrictedMode = true`) and `com.apple.mobiledevice.passwordpolicy` (`requireAlphanumeric = true`, `minLength = 8`, `maxFailedAttempts = 10`, `maxInactivity = 5`). Use `plutil`/`PlistBuddy` (full payload structure is in [[configuration-profiles-and-mobileconfig]]).
2. `plutil -lint hardened.mobileconfig` until it's clean.
3. **Reason about it:** which keys are *supervised-only*? (Host pairing, erase, USB-RM are.) Why does that make supervision the keystone of the fleet posture? Write one sentence connecting `allowHostPairing = false` to the forensic-pairing avenue you'd lose at intake.

### Lab 2 — Detect the posture in a sample full-file-system image (public sample image / read-only)

**Goal:** practice the intake triage on a real artifact set.

1. On a Josh Hickman / Digital Corpora iOS reference image (or an iLEAPP test set), locate `.GlobalPreferences.plist` and check for `LDMGlobalEnabled` with `plutil -extract`.
2. Whether or not the flag is set, build the **negative-space** view: count Messages attachment MIME types, check for Shared Albums, and sample FaceTime call history. Decide: is this consistent with Lockdown Mode, or a normal device?
3. Write the two-line intake note you'd put in the case file: posture observed + the acquisition avenue it forecloses.

### Lab 3 — Reproduce the negative-space baseline (Simulator)

**Goal:** see *what artifacts exist on a default device* so you can recognize their absence.

1. Boot a Simulator (`xcrun simctl boot <UDID>`), open Messages and Photos, and create the artifacts Lockdown Mode would suppress: send yourself a link (would-be link-preview), add a non-image "attachment," create a (mock) shared album.
2. Find the on-disk stores under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/` and confirm the rows/files exist.
3. **Caveat to internalize:** the Simulator never *enforced* Lockdown Mode, so these artifacts are present — that's the point. On a *real* LDM device they'd be **absent by prevention, not deletion.** You're calibrating your eye for the negative.

### Lab 4 — Map the seizure clock and pick the SOP (read-only walkthrough)

**Goal:** turn the timer mechanics into an operational decision.

Given: an A16 iPhone seized at **14:00**, last unlocked **13:30**, screen currently on, no Lockdown Mode, default Wired-Accessories setting. Work out:

1. When does **USB Restricted Mode** close the wired window? (≈ last-unlock + 1 h, sooner if no accessory in 3 d.)
2. When does **inactivity reboot** threaten AFU→BFU if the device sits? (≈ 72 h locked.)
3. Write the field SOP in order: keep powered, keep screen alive, Faraday, attempt AFU acquisition / pairing **before** the USB-RM deadline, escalate to a preservation capability (Safeguard/Preserve-class) if the lab can't act in time. Then write the *defender's* opposite move for the device owner (power off → BFU now) and one sentence on why those two SOPs are mirror images.

### Lab 5 — Compose the full posture for one subject (paper synthesis)

**Goal:** prove you can assemble the toolbox, not just recite it.

Pick one subject — *(a)* an investigative journalist on a personally-owned iPhone, or *(b)* an executive on a corporate ABM-supervised iPhone. For your subject, write the **deployment order** as a numbered list, naming each control and the layer it sits at (L0–L5), and for each control state **one threat it closes** and **one acquisition avenue it forecloses for a future examiner**. Then flag every **order-of-operations** or **ownership-ceiling** constraint you hit (e.g. "must supervise before Lockdown Mode"; "BYOD → can't set `allowHostPairing`"). Finish with the **one** control you'd cut first if the user revolts over usability, and defend the choice against the subject's threat model. There's no single right answer — the synthesis is the skill.

## Pitfalls & gotchas

- **Recommending Lockdown Mode to the wrong person.** It's for the *targeted few*. Hand it to a merely-privacy-conscious user and they'll hit the attachment/web friction, turn it off, and trust your advice less. Match the control to the threat model.
- **The order-of-operations trap.** Lockdown Mode blocks *new* enrollment and profile installs. Enroll/supervise **first**, then enable Lockdown Mode — or the device is locked-down-but-unmanaged and you can't push the corporate profile.
- **Assuming MDM can force or forbid Lockdown Mode.** It cannot — there is no `allowLockdownMode` key, by Apple's deliberate design. Don't promise a "force Lockdown Mode" policy you can't deliver; do use the **DDM status item** to *observe* it.
- **Disabling USB Restricted Mode for accessory convenience.** Setting `allowUSBRestrictedMode = false` (or leaving Wired Accessories on "Always Allow") quietly re-opens the wired-extraction window you were trying to close. Hardening means *keeping* it on.
- **Trusting the 72-hour timer as protection against a capable lab.** Safeguard Mode / GrayKey Preserve exist precisely to **freeze AFU before the timer fires.** The timer protects an *unattended* device; it does not protect one a lab grabs in AFU. The owner's real countermeasure is **power off → BFU now**, not "wait."
- **6-digit PIN with everything else hardened.** Lockdown Mode + ADP + SDP all assume the passcode itself isn't the weak link. A short numeric PIN undercuts the entire stack, especially the BFU guarantee. **Alphanumeric or it's theatre.**
- **Forgetting jurisdiction for ADP.** ADP may be **unavailable** in some jurisdictions (the UK saga). A posture that assumes "Photos is E2EE under ADP" is wrong if ADP was never offerable there — and, perversely, that keeps the warrant-to-Apple route open.
- **Conflating "lockdown."** `lockdownd`/pairing records (acquisition *gold*) vs. Lockdown *Mode* (acquisition *obstacle*). They pull opposite directions. Resolve which one any tool/report means before acting.
- **Examiner powering off a live AFU device.** It feels safe; it's catastrophic — you drop to a BFU you likely can't beat. Keep lawfully-seized live devices powered and the screen alive.
- **Reading the legacy software-update playbook in 2026.** The old MDM software-update commands are being removed on the 27.0 releases. If your "patch enforcement" still rides them, your fleet silently stops getting enforced updates — migrate to **DDM software-update enforcement.**
- **Panic-wiping a phone after an Apple threat notification.** The reflex to "just erase it" destroys the triage evidence that would confirm and characterize the compromise. **Preserve (encrypted backup + sysdiagnose) and run `mvt` first**, then remediate.
- **Reading "`mvt` found nothing" as "clean."** `mvt` matches *known* IOCs only; a null result means "no known campaign indicators," not "uncompromised." Corroborate with anomaly analysis, and re-run after IOC updates.
- **Leaving a high-risk traveler's phone merely locked at a border.** Locked ≠ BFU. A recently-used phone crossing a checkpoint is **AFU** — exactly the state preservation tooling wants. Power it **fully off** to force BFU before the checkpoint.

## Key takeaways

- The operations capstone is **composition**: individual opt-ins ([[advanced-protections-lockdown-sdp-adp]]) + fleet machinery ([[mdm-supervision-and-abm]], [[declarative-device-management]], [[configuration-profiles-and-mobileconfig]]) assemble into **two distinct postures** (high-risk person | managed fleet) that converge for the high-risk person *on* a fleet.
- **Lockdown Mode is for the targeted few, costs real usability, and cannot be managed by MDM** — there is no `allowLockdownMode` key; enroll **before** enabling it; observe it via the new **DDM status item** and the `LDMGlobalEnabled` flag + negative-space signature.
- The **seizure-time timers are deployable defenses**: inactivity reboot (~72 h → BFU) and USB Restricted Mode (~1 h, immediate after 3 d) — and iOS 26's **Wired Accessories** setting lets a user tighten the wired gate further.
- **Vendor counter-moves (Cellebrite Safeguard Mode, Magnet GrayKey Preserve) freeze AFU before the timer fires** — so the only robust owner-side countermeasure is to **create BFU yourself by powering off**; a BFU A14+ device with a strong alphanumeric passcode has no public extraction.
- The **fleet keystone is supervision**; the highest-value anti-acquisition restriction is **`allowHostPairing = false`** (kills forensic pairing + juice-jacking); the highest-value *update* control is **DDM enforcement** (legacy commands gone on 27.0).
- A **strong alphanumeric passcode** is the precondition that makes BFU and the whole stack actually safe — short numeric PINs undercut everything above them.
- For an examiner, **each posture forecloses a different avenue** — supervision kills pairing, Lockdown Mode kills the wired-while-locked path, ADP kills the cloud route, BFU kills almost everything — so **triage the posture before you touch the wire**, and document it as the basis for pivoting and for honest legal-process scoping.

## Terms introduced

| Term | Definition |
|---|---|
| Lockdown Mode (LDM) | Apple's opt-in extreme-hardening mode for individually-targeted users; system-wide subtraction of attack surface (JIT off, attachments/link-previews blocked, wired data blocked while locked, etc.) |
| `LDMGlobalEnabled` | Boolean in `.GlobalPreferences.plist` / NSGlobalDomain set to `1` when Lockdown Mode is on; the authoritative on-device state flag (verify exact key per OS) |
| Negative-space detection | Establishing a defensive posture from artifacts that were never *created* (prevented), not deleted — the robust way to detect Lockdown Mode forensically |
| Inactivity reboot | iOS 18.1+ feature that reboots a device locked ~72 h, forcing AFU→BFU and re-sealing class keys in the SEP |
| USB Restricted Mode | Disables the port's data pins after ~1 h locked (immediately if 3 d since an accessory data connection); closes the wired-acquisition window |
| Wired Accessories setting | iOS/iPadOS 26 control (Always Ask / Ask for New Accessories / Automatically Allow When Unlocked / Always Allow) governing accessory data access; anti-juice-jacking |
| Cellebrite Safeguard Mode | Cellebrite Spring-2026 capability that preserves a device's access state across reboot to defeat the inactivity-reboot timer |
| Magnet GrayKey Preserve | Magnet (2026) field capability to preserve an iOS device's extractable state "indefinitely, in minutes," defeating expiration timers |
| Supervision | The elevated management state (via ABM/ASM + Automated Device Enrollment) that unlocks supervised-only restrictions; keystone of the fleet posture |
| `allowHostPairing` | Supervised restriction (`com.apple.applicationaccess`); when `false`, the device pairs only with the supervision host — kills forensic pairing and juice-jacking |
| `allowUSBRestrictedMode` | Supervised restriction; keep `true` to preserve USB Restricted Mode (setting `false` disables it) |
| DDM status item | A value a device reports up the Declarative Device Management status channel; 2026 additions include Lockdown-Mode status and hardware-health items |
| Order-of-operations trap | Lockdown Mode blocks new enrollment/profile installs → a fleet device must be enrolled/supervised **before** the user enables Lockdown Mode |
| DDM software-update enforcement | Declarative target-version + enforced-deadline software updates that replace the legacy MDM update commands (removed on 27.0); the only forward patch-control path |
| Apple threat notification | Apple's alert (Apple Account banner + iMessage/email) to accounts it assesses were targeted by state-sponsored/mercenary spyware; the clearest "you need Lockdown Mode" signal |
| Border-search exception | The legal regime (narrower, more contested than a warrant; jurisdiction-dependent) under which devices may be searched at a border crossing |

## Further reading

- Apple — *About Lockdown Mode* (support.apple.com/105120) and *Lockdown Mode security* (Apple Platform Security guide, March 2026 edition) — re-verify the enumerated subtraction list each release.
- Apple — *Manage accessory access to Apple devices* and *Allow USB and other accessories…* (support.apple.com/111806) — Wired Accessories / USB Restricted Mode behavior on iOS/iPadOS 26.
- Apple — *Device management restrictions for supervised Apple devices*; `apple/device-management` (`mdm/profiles/com.apple.applicationaccess.yaml`) — authoritative restriction-key reference.
- Apple — *WWDC26 device management updates* / *Install and enforce software updates* — DDM status items (incl. Lockdown Mode), the removal of legacy software-update commands.
- Andrea Fortuna — "iOS Lockdown Mode and forensic analysis: a technical perspective" (andreafortuna.org, 2026-03-29) — the negative-space detection methodology.
- Cellebrite — *Spring 2026 Release* (Safeguard Mode); Magnet Forensics — *GrayKey Preserve* / *preserving evidence in the age of inactivity timers* — the vendor counter-moves, read as offense intelligence.
- ElcomSoft blog — "Evidence Preservation: Why iPhone Data Can Expire" (2025) and the USB-Restricted-Mode series — the defender/offense timer interplay.
- EFF Surveillance Self-Defense — *How to Enable Lockdown Mode on iPhone* — the at-risk-user advisory framing.
- Citizen Lab / Amnesty International Security Lab — mercenary-spyware (Pegasus/Predator) threat reports that define *who* Lockdown Mode is for; `mvt-project/mvt` for triage.
- `man plutil`, Apple Configurator `cfgutil(1)`, libimobiledevice `idevicepair`/`ideviceinfo`.

---
*Related lessons: [[advanced-protections-lockdown-sdp-adp]] | [[mdm-supervision-and-abm]] | [[declarative-device-management]] | [[configuration-profiles-and-mobileconfig]] | [[passcode-bfu-afu-and-inactivity]] | [[icloud-acquisition-and-advanced-data-protection]] | [[acquisition-sop-and-chain-of-custody]]*
