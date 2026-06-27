---
title: "How to use this course"
part: "00 — Orientation"
lesson: 00
est_time: "20 min read"
prerequisites: []
tags: [ios, orientation, meta]
last_reviewed: 2026-06-26
---

# How to use this course

> **In one sentence:** This is the iOS/iPadOS sibling of `macos-mastery` — same lesson skeleton, same engineering-deep register, same forensic discipline — but with one defining twist that reshapes every lab: you have **no physical iOS device**, so every exercise runs on the Mac against the Xcode Simulator, a public sample image, or a narrated read-only walkthrough.

---

## Why this matters

You just finished `macos-mastery`. You can read a `.tracev3`, mount an APFS snapshot, and reason about TCC by bundle identity. That foundation is *load-bearing* here: iOS is Darwin under glass, and almost every subsystem you're about to study has a macOS ancestor you already understand — XNU, launchd, APFS, the Secure Enclave, the Keychain, code signing, the dyld shared cache. This course's job is to teach you where the iPhone **diverges** — Data Protection at rest, the SEP as a hard boundary, AMFI's mandatory code-signing, the locked-vs-unlocked (BFU/AFU) acquisition reality, and an artifact ecosystem (knowledgeC → Biome/SEGB, PowerLog, routined) that is far richer and far more locked-down than anything on the Mac.

The constraint that makes this course unusual is also what makes it honest: with **no device in hand**, you can't `idevice_id -l` your way to a real extraction. So the curriculum is built around substrates that are *legitimately* device-free, and every lab tells you exactly where its substrate **lies to you** versus a real iPhone. Internalizing that fidelity map now — before you trust a Simulator container to teach you about Data Protection (it can't) — is the difference between mastery and a false sense of it.

---

## Concepts

### What this course is, and who it's for

A self-paced, engineering-deep iPhone/iPad curriculum for **one** learner profile: a computer-forensics professional and software builder who has completed `macos-mastery` and wants top-1% iOS/iPadOS command in three weighted areas — **engineering internals**, **phone forensics & artifacts**, and **development** (app-building *and* reverse-engineering). The target platform is **iOS/iPadOS 26.x on Apple Silicon (2026)**. Older devices and OS versions appear only where they still matter — most sharply the **checkm8** A8–A11 boundary and per-version artifact format changes (e.g. SEGB v1→v2 at iOS 17).

The course does not teach you to *use* an iPhone. It teaches you how the iPhone *works*, where its data lives on disk, what format that data is in, what it proves, and how to build and tear apart the software that runs on it.

### Curriculum architecture: 12 parts + a reference layer

The corpus is **12 parts** (P00–P11) plus two reference tiers. The full lesson list with build status lives in [CURRICULUM.md](../CURRICULUM.md); track *your own* completion in [PROGRESS.md](../PROGRESS.md).

| Part | Theme | What it gives you |
|------|-------|-------------------|
| **00 — Orientation** | Mental-model reset, landscape, this file | The map and the lab doctrine |
| **01 — Hardware & Silicon** | SoC lineup, SEP hardware, NAND/AES/effaceable, baseband, radios, biometrics HW, DFU | The physics under everything else |
| **02 — System Architecture & Internals** | XNU on mobile, boot chain, Image4/SHSH, APFS, launchd, Mach/XPC, jetsam, dyld cache/AMFI, containers, unified logging, device services | The OS internals vocabulary |
| **03 — Security Architecture** | Security model, SEP/SEPOS, Data Protection & keybags, BFU/AFU, code signing/AMFI, sandbox/TCC, PAC/PPL/SPTM/TXM/MIE, biometrics, Keychain, ADP/Lockdown | Why acquisition is hard |
| **04 — Networking & Connectivity** | Networking stack, NetworkExtension/VPN, TLS interception, cert pinning, Wi-Fi/BT/proximity, Find My, cellular/eSIM, Apple Account/iCloud/APNs | The wire and the cloud edge |
| **05 — iPadOS as a Computer** | Divergence from iOS, windowing/external display, Files/document providers, trackpad/Pencil, Continuity, pro workflows | Where iPadOS forks |
| **06 — Automation & Operations** | Shortcuts, Screen Time, MDM/supervision/ABM, DDM, config profiles, backup/restore, Lockdown Mode | The management surface |
| **07 — Forensic Acquisition & Imaging** | Landscape & authorization, the acquisition taxonomy, BFU/AFU & DP classes, the Finder backup format, logical acq, full-file-system, iCloud/ADP, decryption, SOP & chain of custody | How evidence comes off |
| **08 — Forensic Artifacts & Pattern of Life** | Sandbox layout, knowledgeC, Biome/SEGB, PowerLog, comms, calls, photos, location, browsers, Mail/Notes, Health, third-party methodology, logs/sysdiagnose, notifications, deleted recovery | What the evidence *says* |
| **09 — Timeline, Analysis & Anti-Forensics** | The timestamp zoo, building a unified timeline, correlation & anti-forensics | Turning artifacts into narrative |
| **10 — iOS App Engineering** | Xcode/build system, Simulator internals, Swift/SwiftUI/UIKit, lifecycle/scenes, bundle/`.ipa`, sandbox (dev side), signing/provisioning, frameworks/dylibs, extensions/widgets, distribution, DMA sideloading, debugging | Building |
| **11 — Reverse Engineering & App Security** | Mach-O ARM64, the code-signature blob, the dyld shared cache, FairPlay decryption, static analysis, Frida, objection/swizzling, the jailbreak landscape, TrollStore/CoreTrust, Theos, OWASP MASTG, anti-tamper | Tearing apart |

The two reference tiers in [`reference/`](../reference/) are **not lessons** — they are the consult-constantly layer:

- **7 hand-authored spines:** `glossary.md`, `acronyms.md`, `mac-side-toolkit-cheatsheet.md`, `forensics-and-dev-toolkit.md`, `macos-to-ios.md` (the "the X of iOS" translation table), `ipados-keyboard-shortcuts.md`, `further-reading.md`.
- **7 derived indexes** (rebuilt by combing the lesson corpus, not hand-written): `study-guide.md`, `tooling-index.md`, `forensic-artifacts-index.md`, `acquisition-methods-matrix.md`, `sql-queries-index.md`, `timestamps-and-epochs.md`, `entitlements-index.md`.

Parts build on each other: **P00 → P01 → P02 → P03** give every later module its vocabulary. After that the forensics track (07 → 08 → 09) and the dev/RE track (10 → 11) are largely independent, and the platform-usage modules (04 → 05 → 06) can be read à la carte. A forensics engineer who already groks APFS can jump straight to [[00-app-sandbox-and-filesystem-layout]] — but read [[02-macos-to-ios-mental-model-reset]] first; iOS has sharp edges (the SEP boundary, Data Protection classes, the inactivity reboot) that will trip even a seasoned macOS examiner.

### Lesson anatomy: the 10-section skeleton

Every lesson follows an identical skeleton so you never hunt for where a thing lives:

1. **YAML frontmatter** — `title`, `part`, `lesson`, `est_time`, `prerequisites`, `tags` (lead tag always `ios`), and a `last_reviewed` date.
2. **One-sentence thesis** — the lesson's core claim in a single `>` blockquote. If you remember one thing, it's this.
3. **(Landmark lessons only) an Authorization block** — a bold `> ⚖️ **AUTHORIZED USE ONLY.**` banner opens the forensics/acquisition landmark lessons.
4. **Why this matters** — 2–4 sentences tying the topic to a forensics / engineering / dev payoff.
5. **Concepts** — the engineering meat. Mechanism, never a UI tour: the daemon named, the file located, the on-disk format and struct described, the framework and exact path given. Tables and ASCII diagrams where they clarify.
6. **Hands-on** — concrete **Mac-side** commands with described output. (There is no on-device shell — see below.)
7. **🧪 Labs** — numbered and **device-free**. Each lab header names its substrate and its fidelity caveat.
8. **Pitfalls & gotchas** — the macOS-reflex traps, the silent-failure modes, the version-specific footguns.
9. **Key takeaways** — a 5–8 bullet recap.
10. **Terms introduced** (a table) → **Further reading** → a closing italic *Related lessons* footer of `[[wikilinks]]`.

### The five callouts

Callouts are emoji-prefixed blockquotes. Learn to read them at a glance:

> 🖥️ **macOS contrast:** Maps an iOS concept back to the macOS analogue you already know. This is the workhorse of the orientation — replaces `macos-mastery`'s 🪟 Windows-contrast. Example: iOS `launchd` *is* the macOS `launchd` (PID 1, the same property-list job model), but on iOS the job set is locked down and you can't drop a `LaunchAgent` plist into `~/Library/LaunchAgents` — there is no user-writable launchd domain.

> 🔬 **Forensics note:** Flags an on-disk artifact, a database/log location, an epoch, or an investigative angle. This is the single most frequent callout in the forensics-heavy parts. Example: the SMS store is a SQLite DB whose timestamps are Mac Absolute Time (epoch 2001-01-01) — but only on a device, and only when the relevant Data Protection class is unlocked.

> ⚖️ **Authorization:** Chain-of-custody, legal-authority, and scope gating. Landmark forensics/acquisition lessons open with a bold `> ⚖️ **AUTHORIZED USE ONLY.**` banner; inline ⚖️ notes flag the spots where "can you technically do this" and "are you lawfully permitted to do this" diverge.

> ⚠️ **ADVANCED / DESTRUCTIVE:** Precedes anything that can damage data, brick a device, weaken security, or alter evidence. On this course it most often guards the **read-only walkthroughs** of device-bound steps (DFU, checkm8/palera1n, on-device `frida-server`, a FairPlay memory dump) that you are *reading about*, not running.

> 🧪 **Lab:** The hands-on exercises. On this course they are device-free by construction — see the doctrine below.

### The defining constraint: the no-physical-device lab doctrine

`macos-mastery` could tell you to "run this on your own Mac" because you *have* a Mac. Here you have **no iPhone or iPad**. Rather than pretend, the course is built on three honest substrates. **Every lab states which one it uses and where that substrate is not a faithful analogue of a real device.**

| Substrate | What it actually is | Best for | Where it **lies to you** |
|-----------|---------------------|----------|--------------------------|
| **Xcode Simulator / CoreSimulator** | iOS frameworks compiled for the host, running natively on macOS; each simulated device is a directory tree at `~/Library/Developer/CoreSimulator/Devices/<UDID>/` | Real SQLite/plist **schemas** and the app-sandbox **layout**; building, debugging, and reverse-engineering *your own* apps; the dev/RE toolchain | No SEP; **no Data-Protection-at-rest** (containers sit in cleartext on the Mac's disk); no baseband/cellular/SIM; **no AMFI / code-signing / sandbox enforcement**; the device-only pattern-of-life daemons don't run, so their stores are empty or absent |
| **Public sample forensic images** | Full-filesystem extractions of **real** devices, published by researchers: Josh Hickman (thebinaryhick.blog / Digital Corpora), DFRWS, NIST CFReDS, the iLEAPP/mvt test data | The device-only stores the Simulator can't produce — knowledgeC, Biome/SEGB, PowerLog, location, Health — plus realistic at-rest encryption state and version-accurate formats | It's a **frozen snapshot**: you can't change lock state, re-run an acquisition, or watch a daemon behave live; the OS version and artifact set are whatever the researcher captured |
| **Read-only walkthroughs** | A narrated, exact workflow for the irreducibly device-bound steps (checkm8/palera1n, on-device `frida-server`, FairPlay dump, GrayKey/Cellebrite acquisition) under a ⚠️/⚖️ block | Understanding the *procedure* and *tool invocation* you would run with hardware | You don't execute it. It is always paired with a Simulator or sample-image stand-in that exercises the same downstream parsing/analysis skill |

The Simulator's fidelity gaps are worth memorizing as a list, because nearly every "but I tested it and the artifact wasn't there" confusion traces back to one of them:

```
Simulator is NOT a phone — it has:
  ✗ no Secure Enclave (SEP)            → Keychain/Data Protection are host-faked, key hierarchy is fiction
  ✗ no Data-Protection-at-rest         → the whole container tree is plaintext APFS on your Mac
  ✗ no baseband / cellular / SIM       → no CommCenter telephony, no IMSI/ICCID, no call/SMS radio path
  ✗ no AMFI / code-signing enforcement → binaries run unsigned; the on-device sandbox profile isn't applied
  ✗ no device-only daemons populating stores:
        knowledged       → knowledgeC      biomed   → Biome/SEGB
        powerlogHelperd  → PowerLog        routined → location / significant locations
  ✗ host XNU, not a device kernel      → no real jetsam pressure, no device memory limits
```

> 🖥️ **macOS contrast:** In `macos-mastery` your lab substrate **was** the target — your own Mac, protected by a Time Machine backup and an APFS snapshot you took with `tmutil localsnapshot` before any destructive step. Here the substrate is deliberately *not* the target: the Simulator is a structural stand-in, the sample image is a real-but-frozen device, and the rollback discipline shifts from "snapshot the system before you break it" to "**copy the artifact before you read it**" (a `SELECT` write-locks SQLite and spawns `-wal`/`-shm` sidecars — same `cp`-before-`sqlite3` reflex you built on macOS).

> 🔬 **Forensics note:** The Simulator's plaintext containers are a *teaching gift* and a *trap*. Gift: you can dissect the exact `Library/`, `Documents/`, `tmp/`, and shared-app-group schema an app uses, with no decryption in the way. Trap: that very plaintext is the thing a real device does **not** give you — on hardware those files are class-keyed under Data Protection and unreadable in a Before-First-Unlock (BFU) state. Learn the schema on the Simulator; learn the *decryptability* from the sample images and Part 03 / Part 07.

### The authorized-use and chain-of-custody discipline

Even though you start without a device, you rehearse evidence discipline from lesson one, because the habits must be automatic before hardware ever enters the room:

- **Authority before access.** Every acquisition technique in Part 07 is written for lawfully authorized examination only — your own test device, an authorized corporate engagement, or an investigation under proper legal process. Examining another person's device or cloud account without authorization is a crime in essentially every US jurisdiction (CFAA + state law).
- **Image, then examine; work on copies; log every command.** This is identical to the macOS discipline. On iOS it has extra teeth because acquisition is *lossy and lock-state-dependent* — a botched first attempt can push a device from AFU to BFU and lock data away.
- **Copy-before-query.** The macOS reflex carries over verbatim. Never open an artifact database in place.

> ⚖️ **Authorization:** The discipline applies even to **sample images and the Simulator**, where there is no live subject. Treat the rehearsal as the real thing: hash your working copy, note provenance, and keep a command log. The point is that the workflow is already muscle memory the first time you sit in front of a device under a warrant or an engagement letter. Landmark lessons — [[00-ios-forensics-landscape-and-authorization]], [[01-the-acquisition-taxonomy]], and the rest of Part 07 — open with a bold `⚖️ AUTHORIZED USE ONLY` banner; treat it as a gate, not decoration.

> ⚠️ **ADVANCED / DESTRUCTIVE:** Later lessons narrate device-bound, irreversible operations — entering DFU, running `checkm8`/`palera1n`, jailbreaking, side-loading via TrollStore — as read-only walkthroughs. **Never** run them against evidence, against a device you don't own, or without a tested rollback. checkm8 is A8–A11 silicon only; there is no public jailbreak for A12+ on iOS 18/26; TrollStore is frozen at iOS ≤ 17.0 (CoreTrust patched in 17.0.1). Those facts gate what is even *possible* before authorization gates what is *permitted*.

### Durable-first, and the `last_reviewed` freshness contract

iOS is a fast-moving target and this course refuses to age badly by writing version facts as if they were eternal. Two rules govern every lesson:

1. **Durable mechanism first, perishable catalog second.** Lead with the framework/daemon/format that ages slowly (e.g. "Data Protection class-keys files; the keybag is unwrapped by the SEP at unlock"). Put the dated catalog facts — OS version, device lineup, tool-support matrix, exploit coverage, fee rates — **second and clearly marked**, because they're the part that rots.
2. **Every lesson carries a `last_reviewed` date.** That stamp tells you how stale the perishable layer might be. The 2026 baseline this corpus was authored against: **iOS/iPadOS 26.5** current · iPhone **17 / Air / 17 Pro** on **A19/A19 Pro** (MIE/EMTE) · iPad Pro **M5** · **Xcode 26.4 / Swift 6.3** · the mitigation ladder **PAC → PPL → SPTM/TXM → Exclaves → MIE** · the **72 h inactivity reboot** (AFU→BFU) · **ADP** breaking cloud acquisition · **Biome/SEGB** having displaced knowledgeC · **DDM** as the 2026 management standard · **AWDL → Wi-Fi Aware**. Re-verify anything version-specific at the moment you act on it; don't trust a 2026 stamp in 2028.

> 🔬 **Forensics note:** This is also evidentiary hygiene. When you cite "the SMS schema" or "the Biome SEGB v2 layout" in a report, anchor it to the OS version you observed, because Apple changes these between releases — knowledgeC's role shrank as Biome grew; SEGB went v1→v2 at iOS 17; artifact paths for Apple Intelligence / Journal / Genmoji are new in iOS 26 and still being mapped by the community. A claim without a version is a claim a defense expert can break.

### CURRICULUM, PROGRESS, and the reference spines

Three top-level files orchestrate the corpus, plus the reference layer:

- **[CURRICULUM.md](../CURRICULUM.md)** — the authoritative lesson list and **build status** (⬜ planned → 🚧 in progress → ✅ written). It's the map of what exists.
- **[PROGRESS.md](../PROGRESS.md)** — *yours* to edit: a checkbox per lesson (`- [ ]` renders clickable in Obsidian). Track read+labs-done here. Edit it in the **repo**, not in the Obsidian mirror (the mirror is overwritten on sync — see below).
- **[CHANGELOG.md](../CHANGELOG.md)** — dated record of what landed, module by module.
- **The reference layer** (`reference/`) — the 7 hand-authored spines and 7 derived indexes described above. When a lesson introduces a term, tool, command, artifact, query, entitlement, or epoch, it also lands in the matching spine. **Lessons are the learn-once layer; references are the consult-constantly layer.** When you forget which epoch the SMS store uses, you go to `timestamps-and-epochs.md`, not back to the lesson.

### There is no on-device shell — everything runs on the Mac

Internalize this now: unlike `macos-mastery`, where `$` meant a shell on the machine under study, **there is no shell on the iPhone**. Every command in every Hands-on section runs **on your Mac** and reaches iOS through one of: the Simulator control tool (`simctl`), the USB device-services protocol (`libimobiledevice` / `pymobiledevice3`), a firmware tool (`ipsw`), a SQLite/plist parser against an extracted file, or an instrumentation bridge (`frida`, `lldb`). Command-block prompt convention:

- `$` = your Mac shell (your account, no elevation).
- `#` / `sudo` = elevated on your Mac (rare; e.g. mounting an image).
- No prefix = output you should expect to see.

---

## Hands-on

These confirm your Mac is a provisioned iOS forensics + dev workstation. The full build-out is [[03-forensics-and-dev-workstation-setup]]; this is the smoke test.

```bash
# 1) Xcode + the Simulator control plane
$ xcodebuild -version
Xcode 26.4
Build version 17F...

$ xcrun simctl list devices available | head
== Devices ==
-- iOS 26.5 --
    iPhone 17 Pro (A1B2C3D4-...-...) (Shutdown)
    iPhone Air   (E5F6...-...-...)   (Shutdown)
    iPad Pro 13-inch (M5) (...)      (Shutdown)
```

```bash
# 2) Device-services tooling — note the *empty* output: that's the point.
$ idevice_id -l          # libimobiledevice: lists attached devices
                         # (no output — you have no device, as expected)
$ ideviceinfo 2>&1 | head -1
ERROR: No device found.

# With no hardware, this whole class of tool is inert. Part 07 labs run it
# against the Simulator's limited surface and against sample images instead.
```

```bash
# 3) Firmware + parsing + RE toolchain present?
$ ipsw version
3.x.x
$ sqlite3 --version
3.43.2 2023-... 
$ frida --version
17.x.x
$ which jtool2 class-dump   # may be empty until Part 11 setup — that's fine
```

```bash
# 4) Locate a Simulator's UNENCRYPTED data root (the teaching substrate)
$ DEV=$(xcrun simctl list devices available | grep -m1 'iPhone' | grep -o '[0-9A-F-]\{36\}')
$ ls "$HOME/Library/Developer/CoreSimulator/Devices/$DEV/data/Containers/"
Bundle      Data        Shared
# Bundle/Application/<UUID>/  = the installed .app bundles
# Data/Application/<UUID>/    = each app's sandbox (Documents/ Library/ tmp/)
# Shared/AppGroup/<UUID>/     = shared app-group containers
```

Everything under that `data/` tree is plaintext on your Mac's APFS — no Data Protection, no SEP. That is exactly what makes it a schema lab and exactly why it can't teach you about encryption-at-rest.

---

## 🧪 Labs

> 🧪 These four labs orient you to the substrates themselves. None requires a device; none is destructive. They establish the reflexes (substrate awareness, copy-before-query, provenance logging) that every later lab assumes.

### Lab 1 — Inventory your toolchain (substrate: read-only walkthrough; no fidelity caveat)

1. Run the four Hands-on blocks above. For each tool, record present/absent and version.
2. Note which tools returned **empty/error output because you have no device** (`idevice_id`, `ideviceinfo`). That inert set is the cost of being device-free — Part 07 shows what subset still works against the Simulator and sample images.
3. Anything missing → it's installed in [[03-forensics-and-dev-workstation-setup]]. Don't proceed to Part 01 labs until Xcode + `simctl` work.

### Lab 2 — Boot a Simulator and map its on-disk container tree (substrate: Xcode Simulator; fidelity caveat: no SEP, no Data-Protection-at-rest, no baseband, no AMFI; device-only daemons `knowledged`/`biomed`/`powerlogHelperd`/`routined` do **not** populate it)

```bash
$ xcrun simctl list devices available | grep iPhone        # pick a UDID
$ xcrun simctl boot <UDID>                                 # boot it (headless)
$ open -a Simulator                                        # optional: see the UI
$ xcrun simctl launch booted com.apple.mobilesafari        # populate something
```

1. Visit a couple of pages in the booted Simulator's Safari.
2. Find the data root: `ls ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/`.
3. `find` for `*.db`/`*.sqlite`/`*.plist` under that tree. Open one **on a copy** (`cp first`, then `sqlite3`). Confirm you're reading a *real* iOS schema in cleartext.
4. Now confirm the lie: `find` for anything resembling `knowledgeC.db`, a Biome `SEGB` stream, or `CurrentPowerlog.PLSQL`. They're absent — those are the device-only stores. Write down *why* (the daemon that would write them doesn't run here). This single observation prevents a recurring class of confusion.

### Lab 3 — Acquire and verify a public sample image (substrate: public sample forensic image; fidelity caveat: a real device but **frozen** — you can't change lock state or re-acquire; OS version is fixed at capture)

1. Browse Josh Hickman's public images index (thebinaryhick.blog/public_images) or the Digital Corpora cell-phone corpus. Pick an iOS reference image with its documentation.
2. Download it **and its published checksum**. Compute and compare: `shasum -a 256 <image>` against the documented hash. A match is your provenance anchor.
3. Start a command log (a plain text file): source URL, download time, published hash, your computed hash, filename. This *is* the chain-of-custody rehearsal — do it even though there's no legal subject.
4. Do **not** parse it yet — Part 07/08 labs do that with iLEAPP/mvt. For now you've practiced the acquisition-and-verify ritual on a real, device-only artifact set.

### Lab 4 — Wire up your tracking + Obsidian sync (substrate: read-only walkthrough)

1. Open [PROGRESS.md](../PROGRESS.md) in the repo. Check the box for this lesson once you finish it.
2. From the PhantomLives repo root, run `./sync-md-to-obsidian.sh`. Open Obsidian → `PhantomLives/ios-mastery/part-00-orientation/` and confirm this file renders with its frontmatter parsed as properties and a `[[wikilink]]` resolves.
3. Make your own notes in a **separate** `personal-notes/` folder inside the vault (not by editing the synced file — the next sync overwrites it).

---

## Pitfalls & gotchas

**"The Simulator is basically an iPhone."** It is not. It runs iOS *frameworks* on the *macOS kernel* with host crypto and no security enforcement. It teaches structure and layout; it teaches you *nothing reliable* about encryption-at-rest, the SEP, code-signing, the sandbox boundary, or the pattern-of-life daemons. Treat any security/lock-state conclusion drawn from the Simulator as suspect until corroborated by a sample image or Part 03.

**Reaching for `idevice_id` to "just check."** With no device, the entire `libimobiledevice`/`pymobiledevice3` device path is inert. That's expected, not a broken install. Don't burn time debugging an empty `idevice_id -l`.

**Editing a synced lesson inside Obsidian.** The Obsidian mirror is **one-way** from git and **git-tracked-only**. Edits in the vault are overwritten on the next sync; a new lesson won't appear until it's committed. Keep personal annotations in a separate `personal-notes/` directory.

**Trusting a stale version fact.** A `last_reviewed: 2026-06-26` stamp does not certify a fact in 2028. iOS catalog facts (OS version, device lineup, exploit/tool coverage, DMA fee rates) rot fast. Lead with the mechanism; re-verify the perishable layer at the moment you rely on it.

**Skipping straight to Part 08 because "I know SQLite forensics."** You do — but iOS adds the Data Protection class on top of the schema, the BFU/AFU gate on top of the file, and an epoch zoo on top of the timestamps. Read [[02-macos-to-ios-mental-model-reset]] and Part 03 before you trust an artifact reading.

**Reading a database in place.** Same reflex as macOS: a `SELECT` write-locks SQLite and creates `-wal`/`-shm` sidecars, mutating your evidence. Always `cp` first, then query the copy — on the Simulator, on a mounted image, everywhere.

**Mismatched timestamp epochs.** iOS mixes Mac Absolute Time (2001), Unix (1970), Cocoa/Core Data, WebKit (1601), and nanosecond variants across stores. Mixing them yields timestamps decades off. The [[00-the-ios-timestamp-zoo]] lesson and `reference/timestamps-and-epochs.md` exist precisely for this.

---

## Key takeaways

- This is the **iOS sibling of `macos-mastery`**: same 10-section skeleton and engineering-deep register, weighted to internals + forensics + dev/RE, targeting **iOS/iPadOS 26.x on Apple Silicon**.
- **You have no device**, so every lab runs on one of three substrates — the **Xcode Simulator** (schemas/layout, but no SEP / no Data-Protection / no baseband / no AMFI / no device-only daemons), **public sample forensic images** (real-but-frozen device data), or **read-only walkthroughs** (narrated device-bound steps). Every lab names its substrate and its fidelity caveat.
- The **five callouts** have fixed meanings: 🖥️ macOS contrast (the workhorse anchor), 🔬 Forensics note (the most frequent), ⚖️ Authorization (the legal gate), ⚠️ Advanced/Destructive (guards device-bound steps), 🧪 Lab.
- **Authorized-use + chain-of-custody discipline starts at lesson one** — rehearse it on copies and sample images so it's automatic before hardware appears: authority before access, image-then-examine, copy-before-query.
- **Durable mechanism first, perishable catalog second**, with a `last_reviewed` stamp on every lesson — re-verify version-specific facts at the moment you act on them.
- **CURRICULUM** is the map, **PROGRESS** is your tracker, the **reference layer** (7 spines + 7 derived indexes) is the consult-constantly lookup; lessons are learn-once.
- **There is no on-device shell** — every command runs on the Mac via `simctl`, `libimobiledevice`, `ipsw`, `sqlite3`, `frida`, or `lldb`.
- **Obsidian sync is one-way and git-tracked-only** — commit new lessons to make them appear; keep personal notes in a separate folder.

---

## Terms introduced

| Term | Definition |
|------|------------|
| Substrate | The artifact source a lab runs against — Simulator, public sample image, or read-only walkthrough — chosen because the course is device-free |
| CoreSimulator | Xcode's Simulator subsystem; each simulated device is a directory tree at `~/Library/Developer/CoreSimulator/Devices/<UDID>/`, with app data sitting unencrypted under `data/Containers/` |
| Fidelity caveat | The explicit statement, per lab, of where its substrate is *not* a faithful analogue of a real device (e.g. the Simulator has no SEP or Data Protection) |
| BFU / AFU | Before-First-Unlock / After-First-Unlock — a device's data-availability state since boot; governs what Data Protection makes decryptable, and thus what acquisition can recover |
| Data Protection | iOS's class-keyed file/Keychain encryption-at-rest, enforced by the SEP; absent on the Simulator (containers are plaintext) |
| Mac Absolute Time | Timestamp epoch of 2001-01-01 00:00:00 UTC used by most Apple SQLite stores; add 978307200 to convert to Unix epoch |
| `last_reviewed` | Per-lesson frontmatter date marking when the perishable (version-specific) facts were last verified |
| Reference spine | A hand-authored consult-constantly lookup doc (glossary, acronyms, toolkit cheat-sheets, the macOS→iOS table) under `reference/` |
| Derived index | A reference doc rebuilt by combing the lesson corpus (artifacts, tools, queries, timestamps, entitlements, acquisition matrix) rather than hand-written |
| `simctl` | `xcrun simctl` — the Mac-side command-line control plane for booting, launching into, and inspecting Simulator devices |

---

## Further reading

- **The course spine:** [CURRICULUM.md](../CURRICULUM.md) (the map), [PROGRESS.md](../PROGRESS.md) (your tracker), [HANDOFF.md](../HANDOFF.md) (how the corpus is built), [`reference/macos-to-ios.md`](../reference/macos-to-ios.md) (the "the X of iOS" translation table).
- **Its macOS sibling:** `macos-mastery/part-00-orientation/00-how-to-use-this-course.md` — the lesson this one mirrors (same skeleton, different lab doctrine: run-on-your-own-Mac vs. device-free).
- **Apple primary:** [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) (Data Protection, the SEP, the boot chain); [developer.apple.com — Simulator](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) and `man simctl` for the device-control surface.
- **Device-free forensics substrates:** [Josh Hickman — Public Images](https://thebinaryhick.blog/public_images/) and [Digital Corpora — cell phones](https://digitalcorpora.org/corpora/cell-phones/) (sample iOS images + documentation); [NIST CFReDS](https://cfreds.nist.gov/) (reference data sets).
- **The parsing tools you'll meet in Parts 07–09:** [iLEAPP](https://github.com/abrignoni/iLEAPP) (Alexis Brignoni; iOS Logs, Events, And Plist Parser — and the new LAVA viewer), [mvt](https://github.com/mvt-project/mvt) (Mobile Verification Toolkit), [libimobiledevice](https://libimobiledevice.org/), [pymobiledevice3](https://github.com/doronz88/pymobiledevice3), and [blacktop/ipsw](https://github.com/blacktop/ipsw).
- **Named researchers / canon:** Jonathan Levin (*MacOS and iOS Internals*, newosxbook.com); Sarah Edwards (mac4n6.com, APOLLO); Ian Whiffin / cclgroupltd (`ccl-segb`, Biome/SEGB); SANS FOR585; theapplewiki.com (checkm8, SHSH, TrollStore version state).

---
*Related lessons: [[02-macos-to-ios-mental-model-reset]] | [[01-ios-platform-landscape-and-history]] | [[03-forensics-and-dev-workstation-setup]] | [[01-simulator-internals-and-on-disk-filesystem]] | [[00-ios-forensics-landscape-and-authorization]]*
