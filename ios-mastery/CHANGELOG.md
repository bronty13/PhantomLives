# Changelog — iOS & iPadOS Mastery

All notable changes to this curriculum. Dates are absolute (this content goes stale, so the
date matters).

## 2026-06-26 — Part 00 (Orientation) built — 4/105 lessons ✅

The foundation module, authored + adversarially reviewed by the module-builder workflow
(8 agents, ~922K tokens, live web research per lesson):

- `00-how-to-use-this-course` — the skeleton, the five callouts (🖥️/🔬/⚖️/⚠️/🧪), the
  no-physical-device lab doctrine, the freshness rule, Obsidian sync.
- `01-ios-platform-landscape-and-history` — iPhone OS → iOS → the iPadOS fork; the Darwin
  OS-family tree; SoC→device→era; the year-based naming reset (→26); and how version → SoC →
  acquisition-capability interlock (the examiner's first question).
- `02-macos-to-ios-mental-model-reset` — the keystone reflex-breaker: six hard resets (no
  shell; AMFI signed-code-only; mandatory sandbox; Data Protection ≠ FileVault with the
  BFU/AFU class matrix; the tethered-Mac lockdownd/usbmuxd/AFC stack + iOS 17 RemoteXPC; secure
  boot with the 1TR escape welded shut) and the one principle beneath them.
- `03-forensics-and-dev-workstation-setup` — building the Mac bench (Xcode/Simulator,
  libimobiledevice/pymobiledevice3, iLEAPP/APOLLO/mvt/ccl-segb, ipsw/img4tool/ldid, Frida/
  objection, mitmproxy, cfgutil) with install + verify steps, against public sample images.
- Review pass corrected live facts (iOS 26.5.1; iOS 27 WWDC beta; the `powerd`→
  `powerlogHelperd` daemon name in HANDOFF) and flagged perishable details for re-verify.

## 2026-06-26 — Course scaffolded (Part 00–11, 105 lessons planned)

Initial scaffold of the iOS sibling to `macos-mastery`, weighted to engineering internals,
phone forensics & artifacts, and development (app-building + reverse-engineering).

- **Root files:** `README.md` (course-home), `CURRICULUM.md` (the full 105-lesson manifest
  across 12 parts, all ⬜), `HANDOFF.md` (lesson template + the no-physical-device lab doctrine
  + the source canon + the derived-index pipeline), `PROGRESS.md`, this `CHANGELOG.md`.
- **Conventions:** cloned from `macos-mastery` — the 10-section lesson skeleton, frontmatter,
  reference-spine discipline. Deltas: `🪟 Windows contrast` → **`🖥️ macOS contrast`**; new
  **`⚖️ Authorization`** callout; **`last_reviewed:`** on every page + this CHANGELOG (from
  `ai-training`).
- **Design basis:** a multi-agent design + research pass (4 pillar agents) reconciled the
  module structure and grounded the volatile 2026 facts (iOS/iPadOS 26.5; A19/A19 Pro + MIE;
  checkm8 A8–A11; TrollStore ≤ iOS 17.0; 72 h inactivity reboot AFU→BFU; ADP vs cloud
  acquisition; Biome/SEGB v1→v2; DDM; AWDL→Wi-Fi Aware). The grounded baseline + source canon
  are recorded in `HANDOFF.md`.
- **Build plan:** module-by-module via a research-and-write fan-out with an adversarial
  accuracy/currency review pass, foundation-first (00 → 01 → 02 → 03, then 07–09, 10–11,
  04–06). Lessons authored to the template; each module flips its CURRICULUM rows ⬜→✅ and gets
  a dated entry here.
