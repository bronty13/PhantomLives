---
title: "The iOS/iPadOS platform landscape & history"
part: "00 — Orientation"
lesson: 01
est_time: "40 min read + 20 min labs"
prerequisites: [how-to-use-this-course]
tags: [ios, ipados, history, platform, soc]
last_reviewed: 2026-06-26
---

# The iOS/iPadOS platform landscape & history

> **In one sentence:** iOS, iPadOS, watchOS, tvOS, visionOS, and bridgeOS are all the *same* Darwin/XNU core wearing different framework-and-UI shells under a non-negotiable signed-code regime — and on iPhone/iPad that core is fused to a specific Apple SoC whose silicon generation, not the marketing OS number, is what actually decides whether and how you can acquire the device.

## Why this matters

You arrive from `macos-mastery` already fluent in XNU, launchd, dyld, APFS, the Secure Enclave, and the Intel→Apple-Silicon transition. iOS is not a different operating system — it is the same Darwin you already know, hardened into a closed appliance and welded to custom silicon. The single most consequential thing this lesson teaches is the **interlock**: on a Mac you ask "which macOS?"; on iPhone the *first* question of any examination is **"which device, running which iOS?"** — because the answer to *that* pair, routed through the SoC generation, determines your entire acquisition path before you touch a cable. Get the lineage and the silicon ladder into muscle memory now and every later module — security model, acquisition taxonomy, jailbreak landscape, RE — snaps onto a frame you already hold.

There's a second reason to start here: **the platform's history is a map of its attack surface.** Each era — the 2008 App Store, the 2014 default encryption, the 2017 SecureROM hardening at A12, the 2019 iPadOS split, the 2023 Biome/SEGB schema change, the 2025 MIE on A19 — left a sediment layer you will dig through as artifacts, mitigations, and acquisition boundaries. Knowing *when* a capability appeared tells you whether it can exist on the device in front of you. A "history" lesson, for a forensics engineer, is really a lesson in what evidence and what defenses to expect from a given vintage of glass and silicon.

## Concepts

### From "iPhone runs OS X" to a Darwin sibling

When Steve Jobs introduced the first iPhone on 2007-01-09 (shipped 2007-06-29) he said only that "iPhone runs OS X." There was no public OS name. The SDK era began calling it **iPhone OS**; with the 2010 arrival of the iPad and the release of **iOS 4** (2010-06-21, alongside iPhone 4), Apple renamed the platform **iOS** to reflect that it now ran on more than the phone. The lineage in one line:

```
iPhone OS 1 (2007) → iPhone OS 2/3 → iOS 4 (2010, rename) → … → iOS 18 (2024) → iOS 26 (2025) → iOS 27 (2026, in beta)
                                              └ iPad runs the same iOS until 2019 ┘
                                                        ↓
                                              iPadOS 13 forks off (2019)
```

What matters for you is not the trivia but the **shape**: from day one this was a Unix — a Darwin userland on an XNU kernel — deliberately stripped of the general-purpose escape hatches macOS keeps. No user shell, no Terminal, no arbitrary binary execution, no writable system volume, every executable page signature-checked at fault time. The "appliance" feel is policy layered on a kernel you already understand, not a foreign architecture.

Hold onto that framing, because it is the central *reset* this course asks of you (developed in full in [[macos-to-ios-mental-model-reset]]): everything you can do casually on a Mac — drop into a shell, run an unsigned binary, read another process's memory, mount the system volume read-write — is either absent or a privilege you must *earn through an exploit* on iOS. Same kernel, same daemons, same on-disk formats; radically different *reachability*. Most of the friction newcomers feel with iOS is them reaching for a macOS affordance that was deliberately removed, not a feature they failed to find.

The other thread running the whole length of that timeline is the **jailbreak cat-and-mouse**, and it is forensic history, not hobbyist trivia. The first iPhone was jailbroken within weeks of its 2007 launch; the original App Store didn't exist yet, so jailbreaking *was* the only way to run third-party code. Every era since has been a cycle: a researcher finds a BootROM, kernel, or sandbox-escape bug; a public jailbreak ships; Apple patches it and raises the hardware bar (PAC, PPL, SPTM/TXM, MIE). That arms race is *why* the SoC ladder below is the decisive axis — each generation of mitigation closed off a class of foothold, until the post-A11 wall left commercial vendors and a handful of private chains as the only reliable way in. You'll trace the full arc in [[the-jailbreak-landscape-2026]]; for now just absorb that "can I get code execution on this device?" has a different answer for nearly every (SoC, iOS) pair, and that answer *is* the device's history.

> 🖥️ **macOS contrast:** macOS was *born on Intel* (well, on PowerPC, then Intel) and had to be *carried* to Apple Silicon in the 2020 M1 transition you studied — Rosetta 2, universal binaries, the whole two-architecture dance. iOS had the opposite history: it was **ARM from its first breath** (the original iPhone ran a Samsung ARM11; Apple's own silicon began with the A4 in 2010) and has never run anything else. There was no transition because there was never a second architecture. When you reason about iOS you can drop the x86 half of your macOS mental model entirely — it was never there.

### The Darwin family tree: one XNU, many faces

Every shipping Apple OS is a **Darwin** distribution over the **XNU** kernel (Mach IPC + a BSD personality + the IOKit driver runtime). They diverge in their framework stack and UI shell, not their core:

```
                         ┌──────────────────────────────────────┐
                         │   XNU kernel  (Mach + BSD + IOKit)    │
                         │   Darwin userland (launchd, dyld,     │
                         │   libSystem, APFS, the daemons)       │
                         └──────────────────┬───────────────────┘
              ┌──────────────┬──────────────┼───────────────┬───────────────┬──────────────┐
           macOS           iOS           iPadOS          watchOS          tvOS         visionOS
        (AppKit +        (UIKit +       (UIKit +        (WatchKit/       (TVUIKit)     (RealityKit +
        SwiftUI;          SwiftUI;       SwiftUI +       SwiftUI)                        ARKit;
        general-          locked         multitasking                                    spatial)
        purpose)          appliance)     shell)
                                                                              ┌──────────────┐
                                                                              │   bridgeOS   │
                                                                              │ (T2 / Apple- │
                                                                              │  Silicon aux │
                                                                              │  processor;  │
                                                                              │  runs the    │
                                                                              │  SMC/SEP-    │
                                                                              │  adjacent    │
                                                                              │  management) │
                                                                              └──────────────┘
```

`bridgeOS` is the odd sibling worth knowing: it's the Darwin variant that runs on the Mac's T2 / Apple-Silicon auxiliary-management domain — itself essentially an embedded "iOS for the Mac's secure subsystem." (`audioOS` / "HomePod Software" is another low-profile member.) The practical payoff: **a skill learned against one family member often transfers.** The same `os_log`/`logd` unified-logging machinery, the same `launchd` plist model, the same dyld **shared cache**, the same APFS container layout, the same code-signing blob format all recur across the family. What changes per OS is the framework surface (UIKit vs AppKit vs WatchKit) and the **security posture dial** — turned to maximum on iOS/iPadOS.

| OS | Primary UI framework | Hardware | What's distinctive for an examiner |
|---|---|---|---|
| macOS | AppKit + SwiftUI | Mac (Apple Silicon / late Intel) | General-purpose; writable user volume, live `log show`, Terminal |
| iOS | UIKit + SwiftUI | iPhone (A-series) | Locked appliance; artifacts via backup/FFS, not a live shell |
| iPadOS | UIKit + SwiftUI | iPad (A-series / M-series Pro) | iOS + windowing/files/pointer ⇒ extra UI-state & document artifacts |
| watchOS | WatchKit / SwiftUI | Apple Watch (S-series) | Companion-paired; health/motion stores; rarely acquired directly |
| tvOS | TVUIKit | Apple TV (A-series) | Few user secrets; account + app-usage artifacts |
| visionOS | RealityKit + ARKit | Vision Pro (M + R1) | Spatial/sensor data; nascent artifact research |
| bridgeOS | (headless) | Mac T2 / Apple-Silicon aux | The Mac's own embedded secure-management Darwin |

The non-iPhone members are not academic to an examiner. An **Apple Watch** is frequently the *only* device that captured a heart-rate or motion trace at a moment of interest, and it pairs to (and syncs through) the iPhone — so the phone's backup often holds the watch's data even when the watch itself is never acquired. **tvOS/HomePod** devices carry account linkages and app-usage that corroborate household presence. **visionOS** is early but spatially rich. The unifying point: because they all sit on the same Darwin core and sync through the same Apple-account fabric, evidence from one family member routinely surfaces in another's stores — which is exactly why understanding the family tree, not just iOS in isolation, pays off.

> 🔬 **Forensics note:** Because the family shares a kernel and a logging stack, your macOS artifact instincts port — *with relocation*. Unified Logs exist on iOS (you'll see `.tracev3` inside a `sysdiagnose`, not via a live `log show` on-device); the dyld shared cache exists (one giant pre-linked blob you'll dissect in [[the-dyld-shared-cache]]); SQLite-everywhere is still the rule for user data. The store *names and paths* move (e.g. macOS `knowledgeC.db` → iOS Biome/SEGB streams, covered in [[biome-and-segb-streams]]), but the *formats and the copy-before-query discipline* are identical. Don't re-learn forensics; re-map it.

### The iPadOS fork (2019): shared core, divergent shell

From 2010 to 2019 the iPad simply ran iOS. The iPad-specific features piled up — Split View and Slide Over and Picture-in-Picture (iOS 9, 2015), drag-and-drop and the macOS-like Dock (iOS 11, 2017) — until at WWDC 2019 Apple **rebranded the iPad's build of iOS as iPadOS**, debuting as **iPadOS 13.1** on 2019-09-24.

Be precise about what the "fork" is and isn't. **It is a marketing and framework divergence, not a kernel fork.** iPadOS and iOS ship from the same source train, the same XNU, the same Darwin userland; they advance in lockstep version numbers (iPadOS 26 ↔ iOS 26). What differs is the **windowing/multitasking layer**, external-display and pointer support, the Files app's document-provider surface, Apple Pencil and trackpad input, and on M-series iPads the desktop-class memory and (since iPadOS 26) far more capable concurrent-app windowing. For your purposes the divergences that *matter* are the ones that change the artifact and acquisition surface — multiple foreground apps, external-storage providers, Stage Manager window state — and those get their own module ([[how-ipados-diverges-from-ios]]). Everywhere else, treat an iPad as an iPhone with a bigger framework allowance and (on Pro) an M-class SoC.

> 🔬 **Forensics note:** The iPadOS divergences are *additive* to the artifact surface, not subtractive. Multiple concurrently-foreground apps mean the "what was the user doing?" question has several answers at one instant (relevant when you reconstruct activity from app-focus/usage streams). **Document-provider and external-storage** plumbing (USB-C drives, the Files app, third-party providers) leaves bookmark/access records the iPhone rarely produces ([[files-external-storage-and-document-providers]]). And **Apple Pencil/handwriting** introduces stores — Scribble, PencilKit drawings — with no iPhone analogue. Treat an iPad as an iPhone's superset of evidence, never a subset.

> 🖥️ **macOS contrast:** The iPadOS split is the inverse of the macOS story you know. macOS spent a decade *absorbing* iOS ideas (the App Store, Gatekeeper, sandboxing, then literally running iOS apps on Apple Silicon). iPadOS is iOS reaching *up* toward the Mac — toward windows, files, and pointers — while keeping iOS's locked core. They are converging from opposite ends onto the same Apple-Silicon, signed-code middle. iPadOS is "how much Mac can you bolt onto an iPhone kernel without opening the appliance."

### The SoC ladder: silicon is the real version axis

Here is the thesis of the lesson made concrete. On iPhone and iPad the **System-on-Chip generation is a harder, more decisive version axis than the OS number**, because the SoC bakes in — permanently, at fabrication — the BootROM (SecureROM), the Secure Enclave generation, and the kernel-hardening primitives. An OS update can patch software; it cannot change the silicon a device shipped with. Every acquisition decision ultimately resolves to "what chip is this, and is its immutable boot code exploitable?"

| SoC | Lead device (year) | Process | Silicon / security milestone | Forensic & jailbreak relevance |
|---|---|---|---|---|
| A4 | iPhone 4 (2010) | 45 nm | First Apple-designed iPhone SoC; 32-bit ARMv7 | Era of `limera1n`/legacy BootROM exploits |
| A7 | iPhone 5s (2013) | 28 nm | **First 64-bit (ARMv8); first Secure Enclave + Touch ID** | SEP era begins — key material leaves the AP |
| A8 | iPhone 6 (2014) | 20 nm | — | **`checkm8` lower bound** |
| A9–A10 | iPhone 6s / 7 (2015–16) | 16/14 nm | A10 first big.LITTLE in iPhone | `checkm8`-class BootROM exploit applies |
| A11 | iPhone 8 / X (2017) | 10 nm | First **Neural Engine**; Face ID debut (iPhone X) | **`checkm8` UPPER bound** — A11 needs passcode disabled for palera1n |
| A12 | iPhone XS/XR (2018) | 7 nm | First **PAC** (Pointer Authentication) | **`usbliter8`** BootROM exploit (A12–A13, June 2026); no public *kernel* jailbreak on modern iOS |
| A13 | iPhone 11 (2019) | 7 nm | — | **`usbliter8`** BootROM upper bound; the wall is now **A13→A14** |
| A14 | iPhone 12 (2020) | 5 nm | — | — |
| A15 | iPhone 13 (2021) | 5 nm | **SPTM/TXM-era hardware threshold (A15+)** | Page-table & trust split moves to hardware-enforced monitors |
| A16 | iPhone 14 Pro (2022) | 4 nm | — | — |
| A17 Pro | iPhone 15 Pro (2023) | **3 nm (N3B)** | First hardware ray tracing; USB-C/USB 3 | — |
| A18 / A18 Pro | iPhone 16 (2024) | 3 nm (N3E) | — | — |
| **A19 / A19 Pro** | **iPhone 17 / Air / 17 Pro (2025)** | **3 nm (N3P)** | **MIE (Memory Integrity Enforcement) / EMTE** | Memory-safety mitigation hardware-enforced at allocation granularity |

And the iPad-Pro M-series, which shares microarchitecture DNA with the Macs you studied:

| SoC | iPad device (year) | Relevance |
|---|---|---|
| M1 | iPad Pro (2021) | Desktop-class SoC arrives on iPad |
| M2 | iPad Pro (2022) | **SPTM/TXM-era threshold (M2+)** |
| M4 | iPad Pro (2024) | Apple skipped M3 on iPad Pro |
| **M5** | **iPad Pro (2025)** | Current Pro silicon |

A note on reading the table: the "lead device" is the *marketing* name, but tooling and signing key off the **`ProductType`** identifier (`iPhone10,3`/`iPhone10,6` = iPhone X; `iPhone11,2` = iPhone XS), and one SoC spans several models. So when you place a device on this ladder you go *marketing name → `ProductType` → board → `CPID`/SoC*, never name-to-SoC directly — the identifier is the join key, and the marketing name is just a label hung on it.

The single most important boundary on this whole ladder is the **unpatchable SecureROM exploit** — a bug in the BootROM mask-programmed into the die, which, living in read-only silicon, no OS update can ever fix. Historically this was **`checkm8`** (**A8–A11** only; A12 closed *it* at fabrication), and as of **June 2026** **`usbliter8`** added the analogous unpatchable foothold on **A12–A13**. So the hardware-foothold wall now falls at the **A13→A14** line — the most consequential single fact in iPhone forensics: at or below it you have a hardware-rooted, OS-version-independent foothold (full-file-system acquisition is on the table); **A14+** has none and is confined to software/agent exploits Apple patches build by build. A BootROM exploit is code-exec, *not* a full jailbreak — there is still **no public *kernel* jailbreak for A12+ on iOS 18/26**. The mitigation hardware only stacks higher as you climb: **PAC** (A12) → **PPL** → **SPTM/TXM** (A15+/M2+) → **Exclaves** → **MIE** (A19), a ladder you'll dissect in [[kernel-hardening-pac-sptm-txm-mie]].

> 🖥️ **macOS contrast:** You met this exact pattern in macOS as the **T2 / Apple-Silicon boot-policy** line — a 2017 Intel Mac with no T2 is a categorically different acquisition target than a T2 or M-series Mac, because the secure boot root moved into dedicated silicon. iPhone is the same idea pushed to its limit and made *the entire* axis: there is no "Intel iPhone," so the device's identity *is* its SoC generation, full stop. "Which chip?" on iPhone carries the weight that "T2 or not?" carried on Mac.

### The OS-version timeline: eras of forensic change

The SoC is the harder axis, but the OS number marks the *software* eras where artifact schemas, data-protection behavior, and the exploit surface shifted. A compressed timeline of the inflection points that actually change your work:

| OS (year) | Lead device | The forensically load-bearing change |
|---|---|---|
| iPhone OS 1 (2007) | iPhone | No SDK, no App Store; the locked-appliance model is set |
| iPhone OS 2 (2008) | iPhone 3G | App Store + third-party signed apps arrive |
| iOS 4 (2010) | iPhone 4 | The "iOS" rename; multitasking; **Data Protection / per-file keys introduced** |
| iOS 7 (2013) | iPhone 5s | Activation Lock; the visual reset Liquid Glass is later compared to |
| iOS 8 (2014) | iPhone 6 | **Default full-device encryption** — Apple can no longer extract by warrant |
| iOS 9–11 (2015–17) | 6s–X | iPad multitasking matures; APFS migration (10.3); USB Restricted Mode (11.4.1) |
| iOS 13 (2019) | iPhone 11 | **iPadOS forks off**; sign-in-with-Apple; Find My offline BLE mesh |
| iOS 14–16 (2020–22) | 12–14 | App privacy reports; Lockdown Mode (16); **knowledgeC displaced by Biome/SEGB** |
| iOS 17 (2023) | iPhone 15 | **Biome/SEGB format v1→v2**; NameDrop; Journal app |
| iOS 18 (2024) | iPhone 16 | Apple Intelligence groundwork; RCS; passcode-reset inactivity tightening |
| **iOS 26 (2025)** | iPhone 17 | **Year-renumber + Liquid Glass**; AI artifact surface broadens; **MIE on A19** |
| iOS 27 (2026, beta) | — | Next-gen Siri/Apple-Intelligence; GA expected ~Sept 2026 |

Two columns to read together: the **OS row** tells you *what artifacts and protections exist*; the **SoC ladder above** tells you *whether you can get at them*. An iOS 17 artifact schema is useless knowledge if the device is an A19 you can't open — and a checkm8 foothold is useless if you don't know the iOS 17 store moved from `knowledgeC` to a SEGB stream. You need both axes, always.

### The 2025 naming reset: iOS 18 → iOS 26, and Liquid Glass

At WWDC on 2025-06-09 Apple **reset every OS to a year-based number**: the version following iOS 18 is **iOS 26** (not 19), matching iPadOS 26, macOS 26 "Tahoe," watchOS 26, tvOS 26, and visionOS 26. The number is the *next* calendar year — iOS 26 ships in fall 2025 but lives most of its life in 2026 — so the whole family now shares one legible number per cycle. There was no "iOS 19–25"; the sequence jumped to align with the year, exactly as the macOS you were running (`macOS 26`) did in the same keynote.

The same release introduced **Liquid Glass**, the largest visual redesign since iOS 7: a translucent, refractive material running across controls, navigation, widgets, and notifications, unified across all six OSes. For a forensics/RE reader this is mostly cosmetic — but flag two engineering consequences. First, "is this a Liquid-Glass build?" is a quick **visual version tell** of "iOS/iPadOS 26 or later" when you only have a photo of a screen. Second, sweeping UI re-architectures shuffle on-disk **UI-state, cache, and snapshot** layouts (window snapshots, widget state, rendering caches), so artifact paths and schemas you memorized on iOS 18 may have moved at the 26 boundary — re-verify, don't assume.

> 🖥️ **macOS contrast:** You lived this reset on the other side. The macOS you studied marched Cheetah → … → Sonoma (14) → Sequoia (15) and then jumped to **macOS 26 "Tahoe"** in the *same* 2025 keynote, by the *same* logic. So the version numbers now line up across your two courses: the Mac on your desk and the iPhone in evidence both say "26," and both got Liquid Glass at once. The renumber is the clearest single signal that Apple treats these as one platform family on one annual train — exactly the thesis of this lesson.

**Dated state to verify at author time (checked 2026-06-26):** the broadly-shipping release is **iOS/iPadOS 26.5** (build `23F77`); a narrow **26.5.1** (2026-06-01) went *only* to the iPhone Air / iPhone 17 line as a wired-charging hotfix, so for most of the fleet "latest" is still 26.5. iOS/iPadOS **26.5 added (initially beta) end-to-end-encrypted RCS**. **iOS/iPadOS 27** was announced at **WWDC 2026 (keynote 2026-06-08)** with developer beta 1 out the same day and public GA expected around mid-September 2026. Treat "27" as not-yet-GA when reasoning about a device you're examining in mid-2026.

### Release cadence and what a build number tells you

Apple's rhythm is predictable enough to *date a device from its build string*: a major version previews at WWDC (June), ships to the public in mid-September, then receives point releases (`.1`, `.2`, …) and security responses across the year, with developer/public betas filling the gaps. The marketing number (`26.5.1`) is for humans; the **build number** is the precise identifier engineering and tooling key on.

The build string has structure — a **major-train number**, a **minor-cycle letter**, and a **build counter**, with betas suffixed:

```
   23 F 77           e.g. 26.5 = build 23F77; the 26.5.x line carries 23F-series builds
   │  │ └── build counter (+ a letter/number suffix on betas)
   │  └──── minor cycle within the train (advances per point release: 23A=26.0, 23B=26.1, … 23F=26.5)
   └─────── major build train  (iOS's own per-cycle number — 23 for the iOS 26 line; NOT the marketing
            version, and NOT the prefix macOS stamps — macOS 26.5 is build 25F71)
```

The major-train number is iOS's *own* per-cycle counter — the iOS 26 line is the **23**-series (so 26.5 = `23F77`) — and two traps live here. It is not the marketing version (23 ≠ 26), and it is **not** the same prefix that year's macOS stamps: macOS 26.5 is `25F71`, running two *ahead* of iOS's `23F77`. What the family genuinely shares is the underlying **Darwin/XNU kernel version** (Darwin 25.x for the 2025–26 cycle — which macOS's build prefix mirrors and iOS's trails by two), the real evidence that iOS and macOS advance off one annual source train. For an examiner the value is concrete: a build string pins the device to a narrow date window and a specific patch level, which in turn pins the **mitigation set** and the **commercial-tool support** that apply. (Resolve the exact letter↔point-release mapping per release rather than memorizing it — the *structure* is stable, the specific letters rotate every cycle.)

One more wrinkle in the cadence to recognize on sight: **Rapid Security Responses (RSR)**, the out-of-band patch mechanism Apple added in the iOS 16.4 era. An RSR-patched device shows a parenthetical letter suffix on its version (e.g. `26.5.1 (a)`) and a corresponding build-string suffix, letting Apple ship a security fix without a full point release. For you that suffix is a *patch-level signal*: it can mean a recently-disclosed exploit chain has already been closed on this specific unit, which directly bears on whether a given commercial or public method will still work against it.

> ⚖️ **Authorization:** The number on the screen is part of the record, not a footnote. When you document a target you capture **ProductVersion *and* the build** (e.g. `26.5.1 (23F...)`), because mitigations, data-protection behavior, and tool support change at *point* releases, not just majors — and because "the device was running build X on date Y" is a chain-of-custody fact a defense expert will check. Never paraphrase a version; record the exact triple (model, version, build).

### Signed distribution as a defining platform trait

A platform's *distribution model* is as much a part of its identity as its kernel. iOS's defining trait — the thing that makes it iOS rather than "macOS for phones" — is that **every executable must be signed by Apple's chain, and the kernel enforces it at runtime, with no first-class user override.** The App Store is the visible front end; the load-bearing mechanism is **AMFI** (the AppleMobileFileIntegrity kernel component) refusing to map any executable page whose code signature doesn't validate, gated by **CDHash** allow-lists and provisioning entitlements. There is no "right-click → Open anyway," no `spctl --master-disable`, no Terminal to `chmod +x` a downloaded binary. This is why **jailbreaks exist at all** (to break this enforcement), why **app sideloading is a regulatory event** (the EU DMA forcing alternative marketplaces, [[eu-dma-sideloading-and-alternative-marketplaces]]), and why **decrypting an App Store app is a step** in RE (FairPlay-encrypted `__TEXT`, [[fairplay-encryption-and-decrypting-app-store-apps]]). The signed-distribution wall is the spine that the entire dev/RE half of this course pushes against.

> 🔬 **Forensics note:** Signed distribution leaves *installation provenance* behind. App Store apps carry an `iTunesMetadata.plist`/receipt inside the bundle recording the purchasing Apple Account, the app's `bundle-id`/`item-id`, and purchase/download dates; the system's installation database tracks what was installed and when. So even before you decrypt or analyze an app, the *fact and origin* of its installation is an artifact — and a sideloaded or enterprise-signed app (no App Store receipt, a different provisioning profile) stands out against that backdrop ([[the-app-bundle-and-ipa-structure]], [[distribution-testflight-appstore-enterprise]]).

> 🖥️ **macOS contrast:** macOS has **Gatekeeper + notarization**, but it is *advisory with an escape hatch*: an admin can run unsigned code, disable SIP, and execute arbitrary binaries — the Mac trusts its owner. iOS inverts the default: the device does **not** trust its owner with code execution. Same conceptual machinery (code signing, entitlements, a security daemon), opposite policy. The gap between "advisory" and "mandatory" is the single biggest behavioral difference between the two platforms, and it's why so much of macOS RE tooling needs a jailbreak or a Simulator to even *run* against iOS. See [[code-signing-amfi-entitlements]].

### Vertical integration as a forensic fact

The reason the interlock below is so tight is that **Apple owns every layer at once** — the silicon (A/M SoC, SecureROM, SEP), the OS (Darwin/XNU + the framework stack), and the distribution channel (the signing chain + App Store). No other consumer platform fuses all three under one vendor. The forensic consequences are direct, not abstract:

- **No layer to play off another.** On a Windows/Android device you can often exploit the gap between hardware vendor, OS vendor, and OEM. On iPhone there is no gap — the BootROM trusts iBoot trusts the kernel trusts AMFI trusts the App Store, one continuous chain of custody Apple controls end to end ([[boot-chain-securerom-iboot]]).
- **The roots of trust are in silicon you can't reflash.** Volume keys, the passcode-entangled keybag, and biometric templates live in the **Secure Enclave**, a separate core with its own SEPOS, not the application processor ([[secure-enclave-hardware]]). There is no cold-boot/key-in-RAM attack the way there was on pre-T2 Macs.
- **"Get the data" almost always reduces to "defeat one of Apple's own layers."** Every acquisition method in Part 07 is, at bottom, either *cooperating* with a layer Apple sanctions (a backup over the lockdown service, an iCloud production request) or *breaking* one Apple built (a BootROM exploit, a kernel jailbreak, a commercial 0-day). There is no neutral, vendor-independent path in — which is precisely why the SoC/OS/lock-state interlock decides everything.

This vertical lock is also *why the course is shaped the way it is*: you must understand the silicon (Part 01), the OS internals (Part 02), and the security model (Part 03) before acquisition (Part 07) makes sense, because each acquisition method is defined by which integrated layer it leverages or breaks.

### The interlock: OS version × SoC × acquisition capability

Now assemble the pieces into the rule that makes "which device, which iOS?" step zero. Three independent facts about a target combine multiplicatively to determine what acquisition is even *possible*:

```
   DEVICE MODEL ──► SoC GENERATION ──► immutable BootROM/SEP foothold?
                                  (checkm8 A8–A11 + usbliter8 A12–A13 = yes; A14+ = no)
                              ×
   iOS VERSION + BUILD ──► software-exploit surface  (palera1n iOS 15.0–18.7.x;
                           + AFU/BFU + data-protection class behavior; ADP on/off)
                              ×
   LOCK STATE (BFU vs AFU) ──► which keys are derivable right now
                              =
   ┌──────────────────────────────────────────────────────────────────────┐
   │  THE ACQUISITION METHOD AVAILABLE TO YOU FOR THIS SPECIFIC TARGET     │
   └──────────────────────────────────────────────────────────────────────┘
```

Worked the way an examiner does:

- **A10 phone, any iOS** → SoC is in the `checkm8` window → a hardware-rooted, OS-independent extraction path exists regardless of version; full-file-system acquisition is on the table (subject to BFU/AFU and passcode).
- **A14+ phone (say iPhone 17, A19), iOS 26.5** → no public BootROM or jailbreak foothold → you are confined to what the OS sanctions: a logical/backup acquisition over the lockdown service (if you can pair), or **commercial exploit tooling** whose support matrix you must check against *this exact build* — and on a freshly-booted device, the **72-hour inactivity reboot** may have already dropped it from AFU to **BFU**, gutting what's decryptable. ADP enabled? Cloud acquisition is off the table too.
- **M-series iPad Pro (say M5), iPadOS 26.5** → an A14+/M-series-class target with SPTM/TXM, so the same "no public foothold" posture as the modern phone — *plus* the iPad's larger evidence surface (external-storage providers, multi-window state). Same interlock math, a different artifact harvest once you're in.

Collapsed to a posture table — the mental lookup an examiner runs in the first sixty seconds:

| SoC era | Public BootROM foothold? | Typical 2026 posture (lawfully authorized) |
|---|---|---|
| A8–A11 | **Yes (`checkm8`, unpatchable)** | Hardware-rooted full-file-system path viable, OS-version-independent (A11 needs passcode off); strongest position |
| A12–A14 | No | Software/commercial exploit *or* logical/backup; version-gated; verify tool support per build |
| A15–A18 (SPTM/TXM) | No | Same as above but mitigation hardware narrows exploit windows; commercial tooling lag is common |
| A19 (MIE) / M2+ iPad | No | Hardest target; expect logical/backup + cloud (if no ADP) as the realistic surface until tooling catches up |

> 🔬 **Forensics note:** Identity travels with the *backup*, too. An iTunes/Finder backup records the device's `ProductType`, `ProductVersion`, `BuildVersion`, serial, and UDID in its top-level **`Info.plist`** (and `Manifest.plist`), so step-zero identification is reproducible from the artifact set alone, not just from the live device — useful when you inherit an extraction you didn't perform. Cross-check those fields against your seizure notes; a mismatch (e.g., the backup's `ProductVersion` newer than the device you logged) is a chain-of-custody red flag.

The takeaway is structural: **you cannot choose a method until you've pinned the model, the SoC, the build, and the lock state.** That is why the very first move in every acquisition SOP is identification, and why the rest of this orientation module and all of Part 07 ([[the-acquisition-taxonomy]], [[bfu-vs-afu-and-data-protection-classes]], [[full-file-system-acquisition]]) hang off this single interlock. Memorize the diagram; everything downstream is a special case of it.

> 🔬 **Forensics note:** **Version + model identification is step zero of any iOS exam** — before parsing a single artifact. The model determines the SoC determines the foothold; the build determines the exploit/tool matrix and the data-protection behavior. Concretely, on a full-file-system image the version lives in `/System/Library/CoreServices/SystemVersion.plist` (`ProductVersion`, `ProductBuildVersion` — the *same* file you read on macOS), and the device model/serial/identifiers live in the **MobileGestalt** cache (a binary plist under `/private/var/.../com.apple.MobileGestalt.plist` — exact cache path drifts across iOS versions, so resolve it against the image rather than hard-coding it). On a *live, paired* device you'd read the same facts over the lockdown service via `ideviceinfo -k ProductType / -k ProductVersion / -k BuildVersion / -k HardwareModel` before deciding anything. Record all of it, with hashes, as the opening lines of your exam notes.

### The frame for everything that follows

This lesson is the load-bearing wall of the course, so make the dependency explicit. The interlock decomposes into the modules ahead, each answering one of its terms:

- **SoC generation / BootROM / SEP** → Part 01 (hardware) + Part 02 (XNU, boot chain, Image4/SHSH). *Which silicon, and what's the immutable root of trust?*
- **Data-protection, AFU/BFU, code signing, sandbox** → Part 03 (security model). *Given the silicon, what's encrypted and what's enforced?*
- **The acquisition methods themselves** → Part 07. *Given silicon × version × lock state, what extraction is possible and lawful?*
- **The artifacts you then parse** → Parts 08–09. *Now that you're in, what evidence exists and how do you time-correlate it?*
- **Building and reverse-engineering apps** → Parts 10–11. *The signed-distribution wall, from the developer's and the attacker's side.*

Every later lesson assumes you can answer "which device, which iOS, which lock state?" in your sleep and route it to a method. That reflex — not any single artifact path — is the thing to leave this lesson with.

## Hands-on

There is **no on-device shell** — every command here runs on your Mac. Without a physical device you can still build the entire decision frame from the public catalog and the Simulator.

### Enumerate the device → SoC → board catalog (no device needed)

`blacktop/ipsw` ships an offline device database — the fastest way to turn a `ProductType` into a SoC and board, the lookup the interlock depends on:

```bash
brew install blacktop/tap/ipsw

# Every known device identifier → name, board, CPU/SoC
ipsw device-list | less
# ProductType    Name                 Board       CPID/Platform   ...
# iPhone10,3     iPhone X             d22ap       t8015 (A11)     ...   ← checkm8 upper bound
# iPhone11,2     iPhone XS            d321ap      t8020 (A12)     ...   ← the wall: A12+
# iPhone18,1     iPhone 17 Pro        …           t81xx (A19 Pro) ...   ← MIE-era (board/CPID: resolve live)
```

Reading the `CPID`/platform column (`t8015` = A11, `t8020` = A12, …) against the `checkm8` boundary tells you instantly whether a given model has a hardware foothold. And here the marketing↔identifier off-by-one this lesson keeps warning about is made concrete: the **iPhone 17** family is `iPhone18,x` (17 Pro = `iPhone18,1`, 17 Pro Max = `iPhone18,2`), *not* `iPhone17,x` — which is actually the **iPhone 16** generation. Never infer the identifier from the marketing number; resolve it. (Also confirm the newest board/CPID strings against your installed `ipsw` build or theapplewiki — the latest models are the values most likely to be stale or absent in any given tool snapshot.)

### Inspect the OS-version surface from the SDK (no device needed)

The installed iOS runtimes and their build numbers are right there in Xcode's CoreSimulator:

```bash
xcrun simctl list runtimes
# == Runtimes ==
# iOS 26.5 (26.5 - 23F...) - com.apple.CoreSimulator.SimRuntime.iOS-26-5
# iPadOS 26.5 (26.5 - 23F...) - ...

xcrun simctl list devicetypes | grep -i 'iPhone\|iPad'
# the device *types* the Simulator can instantiate (no SoC — these are host-arch)
```

Each runtime is a real bundle on disk; its `SystemVersion.plist` carries the same `ProductVersion`/`ProductBuildVersion` keys you'd pull from a device or a full-file-system image — the version-identification skill, rehearsed Mac-side.

### Prove the shared Darwin core (no device needed)

Boot a simulated iOS device and spawn a process inside it — the kernel string it prints is a **Darwin/XNU** banner, the same family you read on your Mac with `uname -a`:

```bash
xcrun simctl boot "iPhone 17"            # or any installed device type
xcrun simctl spawn booted uname -a
# Darwin … Version …: … RELEASE_ARM64_… ARM64

# Compare with the host Mac you came from:
uname -a
# Darwin … Version …: … RELEASE_ARM64_… ARM64
```

Both say **Darwin**. (Caveat: the Simulator process actually runs against the *host* macOS kernel, so the banner reflects your Mac's XNU, not a phone's — but the point stands: there is one kernel family, and the iOS userland is a Darwin userland. A real device's kernel string, visible in a `sysdiagnose`, is the same `Darwin … RELEASE_ARM64` shape.) This is the thesis made tangible: you are not learning a new OS, you are learning a differently-dressed Darwin.

### What you'd run *with* a device (walkthrough — requires a paired iPhone)

For completeness, the live-device identification you'll do in the field uses `libimobiledevice` over the lockdown pairing service:

```bash
brew install libimobiledevice
ideviceinfo -k ProductType      # e.g. iPhone18,1  (iPhone 17 Pro — NOT iPhone17,1, which is the iPhone 16 Pro)
ideviceinfo -k ProductVersion   # e.g. 26.5
ideviceinfo -k BuildVersion     # e.g. 23F77
ideviceinfo -k HardwareModel    # board id → cross-check the SoC
```

You have no device, so you'll exercise the *parsing* of these same fields against a public sample image in the labs and revisit the live path in [[logical-acquisition-with-libimobiledevice]].

### Map a firmware to its device/build (no device needed)

The version × model pairing is also written into every **IPSW** (the firmware bundle) and its signing requests. `ipsw` reads the firmware metadata so you can see, offline, exactly which board/build a release targets — the same `BoardConfig`/`ProductBuildVersion` personalization fields that drive Image4/SHSH ([[image4-personalization-shsh]]):

```bash
# Inspect a downloaded IPSW's BuildManifest (board ↔ build ↔ restore images)
ipsw info iPhone_…_26.5_…_Restore.ipsw
# Version       = 26.5
# BuildVersion  = 23F77
# Devices       = iPhone18,1, iPhone18,2, …   (iPhone 17 Pro / Pro Max)
# and per-device BoardConfig (e.g. d8?ap) used for personalization

# List what Apple is currently signing for a model (controls downgrade feasibility)
ipsw download tss --device iPhone18,1 --signed
```

What's signed *right now* matters forensically: a device can usually only be restored/downgraded to a build Apple still signs, which constrains both an examiner's options and a suspect's. This is the seam between "what version is it?" and "what version can it be made into?" — and it's pure firmware-metadata work you can do entirely Mac-side.

## 🧪 Labs

> All three labs are **device-free**. Lab 1 uses the **public `ipsw` catalog** (a static database, no hardware). Lab 2 uses the **Xcode Simulator** — fidelity caveat: the Simulator runs **macOS frameworks on host silicon**; it has **no real SoC, no SEP, no checkm8 surface, no Data-Protection**, so it teaches *version/identifier parsing*, never the silicon facts. Lab 3 is a **read-only walkthrough** against a public sample image; you don't need to download it to do the reasoning, but the paths are the real ones you'll meet in Part 07/08.

### Lab 1 — Build the checkm8 decision table from the public catalog

*Substrate: `ipsw device-list` (static offline database; no device).*

1. `ipsw device-list > /tmp/devices.txt` and open it.
2. Pull the `CPID`/platform column for these rows: iPhone 6 (A8), iPhone X (A11), iPhone XS (A12), iPhone 17 (A19). Write each device's SoC next to it.
3. For each, answer the only question that matters: **is the SoC in A8–A11?** Mark "checkm8 foothold: yes/no."
4. State the rule in one sentence and predict, for a hypothetical seized iPhone X vs. iPhone 15, which gets a hardware-rooted full-file-system path and which is confined to software/commercial methods. (Answer the lesson gave you: X = yes, 15 = no.)

### Lab 2 — Read a runtime's version identity the way you'd read a device's

*Substrate: Xcode Simulator runtime bundle on disk. Fidelity caveat: this is host-arch macOS frameworks — the `ProductVersion` is real, but there is no SoC/SEP/Data-Protection behind it.*

1. `xcrun simctl list runtimes` and note the path/identifier of an installed iOS runtime.
2. Locate that runtime's `SystemVersion.plist` (inside the runtime bundle under `~/Library/Developer/CoreSimulator/` or the Xcode-provided runtime location) and `plutil -p` it. Confirm the `ProductVersion` and `ProductBuildVersion` keys — the *same* keys, in the *same* file format, you'll parse from a full-file-system image.
3. Boot a simulated device (`xcrun simctl boot "iPhone …"`), then `xcrun simctl getenv booted SIMULATOR_RUNTIME_VERSION` (or inspect the device's `device.plist`). Note how the Simulator exposes the **OS version** but nothing about a SoC — *because there isn't one*. Write one sentence on why this substrate can teach version-ID but can never teach the silicon half of the interlock.

### Lab 3 — Step-zero identification on a public sample image (read-only walkthrough)

*Substrate: a public iOS reference image (e.g. a Josh Hickman / Digital Corpora full-file-system set). Read-only; reasoning works even without downloading.*

1. Name the two files that establish the target's identity before any artifact parsing: **`/System/Library/CoreServices/SystemVersion.plist`** (version + build) and the **MobileGestalt** cache plist (model, serial, identifiers — resolve its exact path against the image, since it drifts by iOS version).
2. From the SoC implied by the model, place the device on the checkm8 ladder from Lab 1 and state the acquisition posture you'd *expect* for that image's era.
3. Write the opening three lines of an exam note: **(model, version+build, SoC + foothold yes/no)** — the header every later artifact lesson assumes you've already produced. This is the deliverable; everything in Parts 08–09 hangs off it.

### Lab 4 — See that iOS and macOS are one Darwin family

*Substrate: Xcode Simulator + your Mac. Fidelity caveat: the Simulator borrows the host kernel, so this demonstrates the shared *family*, not a phone's actual kernel binary.*

1. `xcrun simctl boot "iPhone 17"` (or any installed type), then `xcrun simctl spawn booted uname -s` and `... uname -m`. Note `Darwin` and `arm64`.
2. Run the same `uname -s` on your Mac. Confirm both report `Darwin`.
3. List a few daemons the iOS userland shares with macOS: inspect the runtime bundle and find `launchd`, `logd`, `dyld`, `libSystem.B.dylib`. Write one sentence on what this means for porting your macOS forensic instincts — and one sentence on the *one* thing the Simulator can never show you (the SEP/Data-Protection/baseband layer that only exists on real silicon).

### Lab 5 — Date a device from its build string and place it on both axes

*Substrate: the OS-version timeline table + `ipsw` catalog (no device). Pure reasoning.*

1. Take a build string in the `23F…` family (the 26.5.x line). Using the cadence/structure rules, state: which major version, roughly which point release, and the approximate calendar window it could have been installed.
2. Pair it with a model — say `iPhone18,1` (iPhone 17 Pro, A19 Pro; note it is `iPhone18,x`, *not* `iPhone17,x` — that's the iPhone 16 line). Cross the **OS row** (what artifacts/protections exist at iOS 26: Biome/SEGB v2, MIE, AI stores) with the **SoC ladder** (A19 ⇒ no public foothold).
3. Write the two-line conclusion an examiner would record: *"Build dates the device to era X with protection set Y; SoC places it above the checkm8 wall, so posture is Z."* Notice you reached an acquisition posture using **only** a model string and a build number — no device, no cable. That is the interlock doing its job.

## Pitfalls & gotchas

- **Treating the OS number as the version axis.** The marketing OS number is the *least* decisive of the three interlock facts. "iOS 26" tells you almost nothing about acquisition; "A11 vs A12" tells you almost everything. Lead with the SoC.
- **Reading "iOS 18 → iOS 26" as skipped versions.** Nothing was skipped — it's a one-time renumber to the calendar year, family-wide, identical to `macOS 26`. There is no iOS 19–25 to hunt for.
- **Assuming iPadOS is a different OS.** It's the same XNU/Darwin train as iOS at a lockstep version number; the fork is framework/UI (windowing, files, pointer), not kernel. Don't expect a separate security model — expect iOS's model with a larger framework allowance.
- **Forgetting the point-release matters.** Mitigations, data-protection behavior, and exploit/tool support change at `.x.y` releases. "iOS 26" is not a sufficient record; capture `26.5.1 (build)`.
- **Carrying macOS's "I can always run unsigned code" reflex onto iOS.** There is no `spctl --master-disable`, no "Open anyway," no Terminal. AMFI enforcement is mandatory and kernel-level; the *only* ways around it are an exploit chain or the Simulator. Plan tooling accordingly.
- **Hard-coding the newest device's identifiers/board strings from memory.** A19/iPhone-17-class identifiers, board IDs, and `CPID`s are exactly the values most likely to be stale or absent in a given tool snapshot — resolve them live (`ipsw device-list`, theapplewiki) rather than asserting them.
- **Mistaking the Simulator for a device.** The Simulator has the right *version identifiers and on-disk schemas* but **no SoC, SEP, baseband, or Data-Protection** — it can never teach you the silicon half of the interlock, and device-only daemons (`knowledged`/Biome, `routined`, `powerd`/PowerLog, `biomed`) don't populate its stores.
- **Equating "iPad" with "iPhone, bigger."** Same kernel and security model — but the iPad is an evidence *superset* (multiple foreground apps, external-storage providers, Pencil/handwriting stores). Don't skip iPad-only artifact classes because "it's basically iOS."
- **Confusing the marketing name with the `ProductType`.** "iPhone 17 Pro" is not an identifier; `iPhone18,1` is (and `iPhone18,2` = 17 Pro Max). The numbers don't even line up — `iPhone17,x` is the **iPhone 16** generation, not the 17 — which is exactly why you never infer SoC from the marketing number. Tools, signing, and the device database key off the `ProductType`/board, and several marketing names can map to one identifier (and vice versa). Always resolve to the identifier.
- **Forgetting that "what version can it become" matters as much as "what version is it."** Apple's current signing window constrains restore/downgrade; a device's *reachable* states are part of its forensic profile, not just its present one.

## Key takeaways

- iOS, iPadOS, watchOS, tvOS, visionOS, and bridgeOS are one **Darwin/XNU** core in different framework/UI shells — you already know the core from `macos-mastery`; only the shell and the (maximal) security posture change.
- iPhone was **ARM/Apple-silicon from birth** with no architecture transition — drop the x86 half of your macOS model entirely.
- **iPadOS (2019) is a framework/UI fork, not a kernel fork**; it advances in lockstep with iOS and shares its security model.
- The **SoC generation is the real version axis**: it permanently bakes in the BootROM, SEP, and mitigation hardware that an OS update can never alter.
- **`checkm8` (A8–A11) vs A12+** is the single most consequential boundary in iPhone forensics — hardware-rooted foothold below, software-only-and-patched above (no public A12+ jailbreak on iOS 18/26 as of 2026).
- The **2025 year-based renumber** made iOS 18's successor **iOS 26** (with Liquid Glass), family-wide and mirroring `macOS 26`; **iOS 27** was announced at WWDC 2026 and is in beta.
- **Mandatory, kernel-enforced code signing** (AMFI + signed distribution, no user override) is the defining platform trait and the wall that jailbreaks, EU-DMA sideloading, and app-decryption RE all push against.
- The **build number is structured and datable** (major train + minor letter + counter); it pins the patch level, mitigation set, and tool-support window more precisely than the marketing version — and you can reason all the way to an acquisition posture from a model string + build alone, no device required.
- **Step zero of every exam** is pinning **(model, iOS version + build, lock state)** → SoC → acquisition method. The whole acquisition course is special cases of that interlock.

## Terms introduced

| Term | Definition |
|---|---|
| Darwin | Apple's open-source Unix-like OS foundation (XNU kernel + BSD userland) underlying macOS, iOS, iPadOS, watchOS, tvOS, visionOS, and bridgeOS |
| XNU | "X is Not Unix" — Apple's hybrid kernel (Mach IPC + BSD personality + IOKit) shared across the whole OS family |
| bridgeOS | The Darwin variant running on a Mac's T2 / Apple-Silicon auxiliary-management domain |
| iPhone OS | The platform's original (2007–2010) name before the 2010 rename to iOS |
| iPadOS | The iPad-specific framework/UI fork of iOS, branched at iPadOS 13 (2019); same kernel, divergent shell |
| SoC | System-on-Chip — Apple's A-series (iPhone) / M-series (iPad Pro) silicon; the decisive iOS "version" axis |
| SecureROM / BootROM | Mask-programmed, read-only first-stage boot code fused into the SoC die; unpatchable after fabrication |
| `checkm8` | Unpatchable SecureROM vulnerability present only in A8–A11 SoCs; the hardware foothold boundary |
| PAC | Pointer Authentication Codes — pointer-integrity mitigation introduced with the A12 |
| MIE / EMTE | Memory Integrity Enforcement / Enhanced Memory Tagging — A19-era hardware memory-safety mitigation |
| AMFI | AppleMobileFileIntegrity — the kernel component that enforces mandatory code-signing at page-fault time |
| Liquid Glass | The translucent UI redesign introduced across all Apple OSes at WWDC 2025 (iOS 26 era) |
| Year-based naming | The 2025 OS renumber to the calendar year (iOS 18 → iOS 26), unified family-wide |
| ProductType / ProductVersion / BuildVersion | The lockdown/`SystemVersion.plist` identity triple (model, OS version, exact build) that opens every exam record |
| MobileGestalt | iOS device-identity cache (model, serial, identifiers) read as a binary plist; counterpart to `SystemVersion.plist` |
| Build number | Structured identifier (major train + minor letter + counter, e.g. `23F77` = iOS 26.5) that precisely pins a release; the major train is iOS's own per-cycle number (23 for the iOS 26 line), *distinct* from macOS's prefix (25) — only the underlying Darwin/XNU kernel version is shared family-wide |
| IPSW | Apple's firmware bundle for a device/build; its `BuildManifest` carries the board/build personalization fields used by Image4/SHSH |
| AFU / BFU | After-First-Unlock vs Before-First-Unlock — the lock state that determines which Data-Protection keys are currently derivable |
| Inactivity reboot | The ~72-hour idle timer that reboots an iPhone from AFU back to BFU, shrinking what's decryptable |
| SEP / SEPOS | Secure Enclave and its dedicated OS — the separate core holding keybag, volume keys, and biometric templates |
| FairPlay | Apple's DRM that encrypts App Store binaries' `__TEXT`, a step RE must defeat to analyze a downloaded app |
| Rapid Security Response (RSR) | Out-of-band security patch (iOS 16.4+) shown as a parenthetical version suffix, e.g. `26.5.1 (a)`; a patch-level signal |
| The interlock | The rule that acquisition method = f(device model → SoC → BootROM foothold) × (iOS version/build) × (BFU/AFU lock state) |

## Further reading

- **Apple** — *Apple Platform Security* guide (security.apple.com) for the SoC/SEP/secure-boot framing; developer.apple.com WWDC 2025/2026 "what's new" sessions for the naming reset and Liquid Glass.
- **Jonathan Levin**, *MacOS and iOS Internals* (vols I–III) + newosxbook.com — the canonical Darwin/XNU family and SoC-boot deep dive.
- **theapplewiki.com** — authoritative device-identifier ↔ board ↔ `CPID`/SoC tables, IMG4/SHSH, and `checkm8`/jailbreak version state; the lookup table behind the interlock.
- **Wikipedia** — *iOS version history*, *iPadOS version history*, *Apple A19*, *Darwin (operating system)*, *XNU* — for the dated lineage and SoC specs (cross-check the live edition).
- **`blacktop/ipsw`** (github.com/blacktop/ipsw) — `ipsw device-list` and the offline device database used in Lab 1.
- **`libimobiledevice`** (`man ideviceinfo`) — the live-device identity path you'll use once you have hardware; see also `pymobiledevice3` for the modern Python re-implementation.
- **Josh Hickman** (thebinaryhick.blog) / **Digital Corpora** — public iOS reference images for Lab 3's step-zero identification.
- **iosref.com** — quick device ↔ supported-OS-version lookup tables, useful for sanity-checking "could this model even run that build?"
- **`man simctl`** / `xcrun simctl help` — the full Simulator control surface used in the device-free labs.
- **SANS FOR585 (Smartphone Forensic Analysis In-Depth)** — the practitioner course whose first move is exactly this device+version identification step.
- **theiphonewiki.com — "Kernel"** and the firmware-keys pages — Darwin/XNU kernel build strings per release and the per-build personalization values.
- **Apple newsroom (apple.com/newsroom)** — primary, dated source for OS announcements and ship dates (WWDC 2025 iOS 26, WWDC 2026 iOS 27); cite it for the volatile calendar facts in this lesson.
- **Apple Platform Deployment guide (support.apple.com)** — how releases, RSRs, and supervised/managed devices interact; the operational counterpart to the security guide.

---
*Related lessons: [[macos-to-ios-mental-model-reset]] | [[soc-lineup-and-device-matrix]] | [[xnu-on-mobile]] | [[the-jailbreak-landscape-2026]] | [[the-acquisition-taxonomy]]*
