---
title: iOS & iPadOS Mastery — Build Handoff
type: handoff
audience: a future Claude (or human) continuing this curriculum
last_reviewed: 2026-06-26
---

# Handoff — how to continue building this curriculum

This file is the canonical instruction set for **extending or revising** the iOS & iPadOS
Mastery course. Read it before adding or rewriting lessons. It mirrors the conventions of the
repo's [`macos-mastery`](../macos-mastery/HANDOFF.md) course (the model for this one) and
adopts [`ai-training`](../ai-training/HANDOFF.md)'s two refinements: a `last_reviewed:` date on
every page and a [CHANGELOG.md](CHANGELOG.md).

## What this is

A self-paced, engineering-deep iPhone/iPad curriculum for **one specific learner**: a
computer-forensics professional and software builder who has completed `macos-mastery` and
wants top-1% iOS/iPadOS mastery weighted to **engineering internals, phone forensics &
artifacts, and development (app-building + reverse-engineering)**. Target platform is
**iOS/iPadOS 26.x era (2026) on Apple Silicon**; older devices/OS versions are noted where
they still matter (especially the **checkm8** A8–A11 boundary and per-version artifact
changes). It lives in `~/dev/PhantomLives/ios-mastery/` and is mirrored into Obsidian by the
repo's `sync-md-to-obsidian.sh` (git-tracked `.md` only — so **commit new lessons** or they
won't appear in Obsidian).

## The defining constraint: no physical iOS device

Every lab is **device-free**. Three substrates, and every lab must declare which it uses and
where the substrate is *not* a faithful analogue:

1. **Xcode Simulator / CoreSimulator** — app containers sit **unencrypted** on the Mac at
   `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/`, so you can populate an
   app (Messages, Photos, Safari, Notes) and dissect the **real** SQLite/plist schemas. ⚠️ The
   Simulator runs macOS frameworks: **no SEP, no Data-Protection-at-rest, no baseband, no
   AMFI/sandbox enforcement, and the device-only pattern-of-life daemons (`knowledged`,
   `biomed`, `powerlogHelperd`/PowerLog, `routined`) do not populate device-style stores.** It teaches
   *structure/layout/parsing*; encryption/lock-state behavior is taught from sample images.
2. **Public sample forensic images** — Josh Hickman's iOS reference images (thebinaryhick.blog /
   Digital Corpora), DFRWS, NIST CFReDS, the iLEAPP/mvt test data. Use these for the device-only
   stores the Simulator can't produce.
3. **Read-only walkthroughs** — for the irreducibly device-bound steps (checkm8/palera1n,
   on-device `frida-server`, FairPlay memory-dump, GrayKey/Cellebrite acquisition): narrate the
   exact workflow under a ⚠️/⚖️ block, and pair it with a Simulator/sample-image stand-in that
   exercises the same downstream skill.

## File / naming conventions

- Modules: `part-NN-theme/` (two-digit, zero-padded).
- Lessons: `part-NN-theme/NN-slug.md` (two-digit, zero-padded; numbers restart at `00` per
  module).
- References: `reference/<name>.md`.
- The authoritative lesson list + build status is [CURRICULUM.md](CURRICULUM.md). **Update its
  status column** (⬜→🚧→✅) whenever you touch a lesson.
- Cross-link with Obsidian `[[wikilinks]]` *and* relative Markdown links where a clickable repo
  link helps. Prefer relative Markdown links for navigation tables; use `[[slug]]` inline when
  referencing a concept covered elsewhere.

## Lesson template (follow it for consistency)

```markdown
---
title: <Lesson title>
part: NN — <theme>
lesson: NN
est_time: <e.g. 60 min read + 45 min labs>
prerequisites: [<slugs of prereq lessons>]
tags: [ios, <topic-tags>]            # lead tag always `ios`; add `ipados` / `forensics` / `dfir` etc.
last_reviewed: <YYYY-MM-DD>
---

# <Lesson title>

> **In one sentence:** <the thesis of the lesson>.

<!-- Landmark forensics/acquisition lessons add a bold authorization block here: -->
> ⚖️ **AUTHORIZED USE ONLY.** <chain-of-custody / legal-authority framing>

## Why this matters
<2–4 sentences. Tie to forensics/engineering/dev payoff.>

## Concepts
<The meat. Engineering-deep. Subheadings. Mechanism, not UI steps — name the daemon, the
file, the on-disk format, the struct, the framework, the exact path. Diagrams-as-text and
tables where they clarify.>

> 🖥️ **macOS contrast:** <map the iOS concept back to its macOS analogue the learner knows>

> 🔬 **Forensics note:** <on-disk artifact / database / log / investigative angle>

## Hands-on
<Concrete Mac-side commands with expected output described. Real flags. Remember: there is no
on-device shell — commands run on the Mac (simctl, libimobiledevice, ipsw, frida, sqlite3).>

## 🧪 Labs
<Numbered, device-free (Simulator / sample image / walkthrough). Each lab header states its
substrate + the fidelity caveat. Destructive/device steps get a ⚠️ block.>

## Pitfalls & gotchas
<The macOS-reflex traps, the silent-failure modes, the footguns, the version-specific changes.>

## Key takeaways
<5–8 bullet recap.>

## Terms introduced
| Term | Definition |
|---|---|
<Ensure each also lands in reference/glossary.md (+ acronyms.md / the matching index).>

## Further reading
<Apple docs/guides, the source canon below, GitHub repos, named researchers, man pages.>

---
*Related lessons: [[slug]] | [[slug]] | …*
```

## Callout vocabulary

- **🖥️ macOS contrast** — replaces macOS course's 🪟 Windows-contrast. Anchor every iOS
  subsystem to its macOS analogue (the learner just finished that course).
- **🔬 Forensics note** — the workhorse: artifacts, databases, logs, investigative angles.
- **⚖️ Authorization** — chain-of-custody / legal-authority / scope gate. Landmark forensics
  and acquisition lessons open with a bold `> ⚖️ AUTHORIZED USE ONLY` block.
- **⚠️ ADVANCED / DESTRUCTIVE** — precedes anything that can damage data, brick a device, or
  weaken security.
- **🧪 Lab** — the hands-on sections (device-free on this course).

## Voice & depth rules

- **Assume competence.** The learner is a forensics engineer + builder and a macOS power user.
  No hand-holding; explain the mechanism.
- **Mechanism-first, never a UI tour.** Always answer "how does this actually work?" — the
  daemon, the file, the on-disk format, the struct, the path, the framework.
- **Currency matters; durable first, perishable second.** Lead with the framework/mechanism
  (ages slowly); put dated catalog facts (OS versions, device lineup, tool support, exploit
  coverage) second, clearly marked, and re-verify version-specific claims at author time. Stamp
  every lesson `last_reviewed`. Never write a version-specific claim from stale memory.
- **Forensic discipline in the artifact lessons:** copy-before-query (`cp` then `sqlite3` — even
  a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`), the right epoch for each store, and
  the BFU/AFU lock-state caveat for what's even decryptable.

## The grounded 2026 baseline (verify before re-publishing)

Bake these in; re-check at author time. Current OS **iOS/iPadOS 26.5** (26.6 beta; 27 at WWDC
2026) · iPhone **17 / Air / 17 Pro/Max** on **A19/A19 Pro** (N3P; **MIE/EMTE**) · iPad Pro
**M5** · **Xcode 26.4 / Swift 6.3** (iOS 26 SDK mandatory for submissions since 2026-04-28) ·
**checkm8 = A8–A11 only**; **usbliter8** = unpatchable SecureROM/USB-DMA exploit for **A12–A13**
(+S4/S5/A12 iPads), public **2026-06-18** → the BootROM-exploit acquisition boundary is now
**A8–A13**; **A14+ has no public BootROM exploit** (a BootROM exploit is code-exec, NOT a full
jailbreak, and doesn't defeat SEP/Data Protection) · palera1n **iOS 15.0–18.7.x** (A11 needs
passcode disabled) · **no public kernel jailbreak for A12+ on iOS 18/26** · **TrollStore frozen ≤ iOS 17.0** (CoreTrust patched
17.0.1) · mitigation ladder PAC → PPL → **SPTM/TXM** (A15+/M2+) → **Exclaves** → **MIE** (A19) ·
**inactivity reboot 72 h → AFU→BFU** · **ADP breaks cloud acquisition** · **Biome/SEGB**
displaced knowledgeC (format v1→v2 at iOS 17) · **DDM** the 2026 management standard · **AWDL →
Wi-Fi Aware** · EU DMA **CTF→CTC** mid-transition. Flagged "research at author time": iOS 26
Apple-Intelligence/Journal/Genmoji artifact paths; the exact 2026 commercial-tool iOS-support
matrix; CTC fee rates; whether iOS 27 has shipped.

## The source canon (cite the live edition)

- **Apple primary** — Apple Platform Security Guide; Apple Platform Deployment Guide;
  developer.apple.com (Security/Keychain, NetworkExtension, App Intents, Xcode/Swift, DMA,
  entitlements, TN3125 code-signing); security.apple.com; Apple Legal Process Guidelines (US).
- **Internals** — Jonathan Levin, *MacOS and iOS Internals* vols I–III + newosxbook.com /
  `jtool2`; theapplewiki.com (IMG4, SHSH, checkm8, jailbreak/TrollStore version state); Project
  Zero; arXiv 2510.09272 (SPTM/TXM/Exclaves); Quarkslab / Trail of Bits / Synacktiv / Corellium.
- **Forensics** — Sarah Edwards (mac4n6.com, APOLLO); Alexis Brignoni (iLEAPP/ALEAPP); SANS
  FOR585/FOR518; d204n6 / Ian Whiffin / cclgroupltd `ccl-segb` (Biome/SEGB); Yogesh Khatri
  (mac_apt); libimobiledevice + pymobiledevice3; mvt; blacktop/ipsw; vendor blogs (Elcomsoft,
  Magnet/GrayKey, Cellebrite, Belkasoft, MSAB); Josh Hickman / Digital Corpora sample images.
- **Dev/RE** — OWASP MAS (MASVS/MASTG/MASWE + iGoat/UnCrackable crackmes); Frida + objection +
  frida-ios-dump/bagbak; Theos/ElleKit; TrollStore/Dopamine/palera1n repos; Ghidra/Hopper/IDA/
  Binary Ninja shared-cache loaders; *iOS Application Security* (Thiel).
- **Wireless/Continuity** — owlink.org / SEEMOO (AWDL, PrivateDrop, Find My crypto);
  OpenHaystack; Wi-Fi Aware / NAN.

## Reference spines — keep them in sync

When a lesson introduces a term/acronym/tool/command/artifact/query/entitlement/epoch, make sure
it also lands in the matching reference file (`glossary.md`, `acronyms.md`,
`mac-side-toolkit-cheatsheet.md`, `forensics-and-dev-toolkit.md`). The references are the
consult-constantly layer; lessons are the learn-once layer.

## Derived study aids — how to (re)generate

`reference/study-guide.md`, `tooling-index.md`, `forensic-artifacts-index.md`,
`acquisition-methods-matrix.md`, `sql-queries-index.md`, `timestamps-and-epochs.md`, and
`entitlements-index.md` are **derived** — built by combing the lesson corpus, not hand-authored.
To (re)build (the process used originally):

1. Fan out one extraction agent per `part-NN-*/` folder. Each reads every lesson fully and emits
   tagged one-line items under sections — `ARTIFACTS`, `COMMANDS`, `TAKEAWAYS`, plus the
   iOS-specific `QUERIES`, `TIMESTAMPS`, `ENTITLEMENTS`, `ACQUISITION` — each line tagged with the
   lesson slug, written to `/tmp/ios-extract/part-NN.md`.
2. Concatenate each section across all parts.
3. Run synthesis agents, one per derived doc: dedupe, categorize, and write the polished doc with
   `[[slug]]` cross-links. (Study guide also reads `CURRICULUM.md` for Part grouping.)

Re-run after any substantial lesson edit so the indexes stay accurate.

## Build procedure

1. Pick the next 🚧/⬜ lessons from CURRICULUM.md. Build foundation-first: Parts 00 → 01 → 02 →
   03 give every later module its vocabulary; then 07 → 08 → 09 (forensics), 10 → 11 (dev/RE),
   04 → 05 → 06 (platform usage).
2. Research current behavior (don't write version-specific claims from stale memory).
3. Write to the template. Update CURRICULUM status (⬜→✅).
4. Add new terms to the reference spines.
5. `git add` the new files + commit + push, then `./sync-md-to-obsidian.sh` so Obsidian updates.
6. After each module: add a dated CHANGELOG entry.

## Open ideas / backlog

- A 13th module splitting Part 09 into *Timeline/Analysis* and *Anti-Forensics & Spyware
  (mvt/Pegasus/triage)*.
- Per-part capstone labs (e.g. Part 07 capstone: full acquisition SOP against a sample image).
- A `quizzes/` folder of self-test questions per part.
- Reconcile the auto-generated glossary against terms actually used across lessons.
