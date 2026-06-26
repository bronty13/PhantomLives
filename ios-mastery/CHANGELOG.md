# Changelog — iOS & iPadOS Mastery

All notable changes to this curriculum. Dates are absolute (this content goes stale, so the
date matters).

## 2026-06-26 — Part 01 (Hardware & Silicon) built — 12/105 lessons ✅

The silicon substrate (16 agents, ~2.07M tokens, live research per lesson):

- `00-soc-lineup-and-device-matrix` — model → ProductType → CPID/BDID/ECID → SoC → the
  checkm8 (A8–A11) / SPTM (A15+) / MIE (A19) tiers; reading BuildManifest.plist; model+SoC ID
  as forensic step zero.
- `01-cpu-gpu-npu-microarchitecture` — P/E topology, the GPU + neural accelerators, the 16-core
  ANE, arm64e + PAC keys at the silicon level, AMX/SME, unified memory.
- `02-secure-enclave-hardware` — the SEP coprocessor: dedicated core, Memory Protection Engine,
  TRNG/PKA/AES, the off-die Secure Storage Component, the fused UID/GID keys (why off-device
  brute force is impossible).
- `03-storage-nand-aes-effaceable` — NAND + ANS controller, the inline AES-XTS engine,
  effaceable storage (BAG1/Dkey/EMF! lockers) and instant crypto-shred; why physical NAND
  imaging is dead.
- `04-baseband-and-cellular` — the baseband as a separate RTOS computer; Apple C1/C1X vs
  Qualcomm; eUICC/eSIM; IMEI/IMSI/ICCID; the AP↔baseband interface.
- `05-radios-wifi-bt-nfc-uwb` — the N1 chip, the NFC embedded Secure Element, U1/U2 UWB secure
  ranging, and what each radio persists (BT pairing, known-Wi-Fi, Wallet).
- `06-biometrics-hardware-faceid-touchid` — TrueDepth/Touch ID hardware, the Secure Neural
  Engine, the factory-paired sensor↔SEP channel (why swaps disable biometrics).
- `07-connectivity-power-sensors-dfu` — display/AOP, PMU/PowerLog, the sensor suite as evidence,
  USB Restricted Mode, and the DFU/Recovery entry path.

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
