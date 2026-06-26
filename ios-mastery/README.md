---
title: iOS & iPadOS Mastery
type: course-home
audience: forensics professional + software builder (macOS power user, no physical iOS test device)
target_platform: iOS / iPadOS 26.x era (2026), Apple Silicon
status: living document
last_reviewed: 2026-06-26
---

# iOS & iPadOS Mastery — engineering · forensics · development

A complete, self-paced curriculum for **deeply** understanding iPhone and iPad — not at
the "how do I AirDrop" level, but at the level a **mobile-forensics examiner and serious
app builder** needs: *how the system actually works under the hood*, **what it leaves on
disk and how to recover it**, and **how to build, sign, ship, and reverse-engineer the
apps that run on it**.

This is the iOS sibling of the repo's [`macos-mastery`](../macos-mastery/README.md) course,
built to the same conventions and the same engineering depth — and it assumes you've done
that one (every lesson maps iOS subsystems back to the macOS analogues you already know via
🖥️ **macOS contrast** callouts).

This was built for someone who:

- has a **computer-forensics background** and wants the engineering details — the boot
  chain, the Secure Enclave, Data Protection, **on-disk artifacts and acquisition**;
- wants both **development** (Xcode, Swift/SwiftUI, signing, distribution) **and
  reverse-engineering** (Mach-O, Frida, the jailbreak landscape, OWASP MASTG);
- works on a **Mac with no spare/jailbroken iOS device**, so every lab runs on the
  **Xcode Simulator**, **public sample forensic images**, and **read-only walkthroughs**;
- wants to end up in the **top 1%** — curated from Apple's own security guides, the DFIR
  community (Sarah Edwards, Alexis Brignoni), Jonathan Levin's *OS Internals, Project Zero,
  theapplewiki, and OWASP, not just one vendor's marketing.

> **Platform note.** Everything targets **modern iOS/iPadOS (the 26.x year-based-naming
> era, 2026) on Apple Silicon** (A-series iPhone, M-series iPad). Older devices and OS
> versions are called out where they still matter — especially in forensics, where the
> **checkm8** boundary (A8–A11) and per-version artifact changes are load-bearing facts.

---

## How to use this course

1. **Read [How to Use This Course](part-00-orientation/00-how-to-use-this-course.md) first.**
   It explains the lesson format, the five callout types, the **no-physical-device lab
   doctrine**, and the ⚖️ chain-of-custody discipline.
2. **Follow the path in [CURRICULUM.md](CURRICULUM.md).** Parts build on each other; the
   Part 00–03 foundation (orientation, hardware, internals, security) gives every later
   module its vocabulary.
3. **Do the labs.** Reading about `Manifest.db` teaches you nothing; populating a Simulator's
   Messages app and then querying the real `sms.db` in its on-disk container teaches you
   everything. Each lab names its **substrate** (Simulator / sample image / walkthrough) and
   where the Simulator is *not* a faithful analogue.
4. **Track your progress in [PROGRESS.md](PROGRESS.md).**
5. **Keep the [reference/](reference/) spines open in a second pane** — the acronym list
   (iOS is acronym-dense), the Mac-side toolkit cheat-sheet, the forensic-artifacts index,
   and the acquisition-methods matrix are meant to be consulted constantly.

### Suggested pacing

| Pace | Plan |
|---|---|
| **Sprint** (3–4 wks) | 1 lesson/day + its labs. Drill the Internals, Security, and Forensics parts. |
| **Steady** (10–14 wks) | 2–3 lessons/week with labs. The default. |
| **Mastery** (ongoing) | One lesson per sitting, do *every* lab, write your own notes back into Obsidian. |

---

## The twelve parts

| Part | Theme | Why it matters |
|---|---|---|
| **00 — Orientation** | The macOS→iOS mental reset; platform history; the workstation setup | Stops you fighting a shell-less, sandbox-everywhere OS |
| **01 — Hardware & Silicon** | A/M-series SoC, the Secure Enclave, baseband, radios, biometrics | The silicon root of trust everything rests on |
| **02 — System Architecture & Internals** | XNU on mobile, the boot chain, IMG4/SHSH, APFS, launchd, dyld cache | The forensics-grade "how it actually works" core |
| **03 — Security Architecture** | SEP/SEPOS, Data Protection & keybags, BFU/AFU, code signing, PAC/PPL/SPTM/MIE | The model that decides what you can and can't acquire |
| **04 — Networking & Connectivity** | The stack, NetworkExtension/VPN, TLS interception, AWDL→Wi-Fi Aware, Find My, baseband | The connectivity layer, end to end |
| **05 — iPadOS as a Computer** | The 26 windowing system, Files, Pencil, Continuity, on-iPad dev | Where iPadOS diverges from iOS |
| **06 — Automation & Operations** | Shortcuts, Screen Time, MDM/supervision/DDM, config profiles, backup/restore | Management, supervision, and their forensic footprint |
| **07 — Forensic Acquisition & Imaging** | The acquisition taxonomy, backups, libimobiledevice, FFS, iCloud, decryption | Getting the data out, defensibly |
| **08 — Forensic Artifacts & Pattern of Life** | knowledgeC, Biome/SEGB, PowerLog, messages, photos, location, app stores | Your home turf — the on-disk evidence, made iOS-specific |
| **09 — Timeline, Analysis & Anti-Forensics** | The timestamp zoo, unified timelines, correlation, anti-forensics | Turning artifacts into a defensible narrative |
| **10 — iOS App Engineering** | Xcode, Swift/SwiftUI/UIKit, the app bundle, signing, distribution, the Simulator | Build, sign, and ship — and know every byte of the result |
| **11 — Reverse Engineering & App Security** | Mach-O ARM64, the dyld cache, FairPlay, Frida, Theos, the jailbreak landscape, MASTG | The same knowledge run backwards |

Plus **[reference/](reference/)**: glossary · **acronyms** · macOS→iOS translation · Mac-side
toolkit cheat-sheet · iPadOS keyboard shortcuts · forensics-and-dev toolkit · further reading.

And seven **derived study aids** (auto-built by combing every lesson): a **Study Guide**, a
**Tooling Index** (open-source + commercial), a **Forensic Artifacts Index**, an
**Acquisition-Methods Matrix**, a **SQL-Queries Index**, a **Timestamps & Epochs** reference,
and an **Entitlements Index**.

---

## This folder syncs to Obsidian automatically

This curriculum lives in the PhantomLives repo as plain Markdown. The repo's
`sync-md-to-obsidian.sh` mirrors every **git-tracked** `.md` file into your Obsidian vault
(`<vault>/PhantomLives/ios-mastery/…`), so once these lessons are committed they appear in
Obsidian with working `[[wikilinks]]` and frontmatter. Read in Obsidian, but **author/edit
in the repo** — the mirror is one-way. To force a sync now: `./sync-md-to-obsidian.sh` from
the repo root.

---

## Conventions used throughout

- **🖥️ macOS contrast** callouts map an iOS concept back to its macOS equivalent (you just
  finished that course).
- **🔬 Forensics note** callouts flag on-disk artifacts, databases, logs, and investigative
  angles — the workhorse callout of this course.
- **⚖️ Authorization** callouts gate anything touching someone's device or data:
  chain-of-custody, legal authority, scope. Landmark forensics lessons open with a bold
  **AUTHORIZED USE ONLY** block.
- **⚠️ ADVANCED / DESTRUCTIVE** callouts precede operations that can damage data, brick a
  device, or weaken security — with how to avoid the footgun.
- **🧪 Lab** sections are hands-on, and on this course they are **device-free**: Xcode
  Simulator, public sample images, and Mac-side tooling. Do them.
- **`$`** prefixes a normal-user shell command on your **Mac** (there is no on-device shell);
  **`#`** or `sudo` prefixes a root command. Modifier glyphs: **`⌘`** Command · **`⌥`** Option ·
  **`⌃`** Control · **`⇧`** Shift.
