# Changelog — iOS & iPadOS Mastery

All notable changes to this curriculum. Dates are absolute (this content goes stale, so the
date matters).

## 2026-06-26 — Part 07 (Forensic Acquisition & Imaging) built — 42/105 lessons ✅

The first forensics pillar, leaning directly on the security foundation (BFU/AFU, keybags,
checkm8/usbliter8, the backup format):

- `00-ios-forensics-landscape-and-authorization` (landmark, ⚖️) — the four axioms that
  separate iOS from disk forensics; Riley v. California; CFAA; remote-wipe + the 72h
  inactivity-reboot race.
- `01-the-acquisition-taxonomy` — the five-tier ladder + the decision tree keyed to SoC ×
  build × lock state.
- `02-bfu-vs-afu-and-data-protection-classes` — the full state × class readability matrix +
  the vendor reboot countermeasures (Safeguard Mode / GrayKey Preserve).
- `03-the-itunes-finder-backup-format` — Manifest.db / Manifest.plist / Info / Status, the
  SHA1(domain-relativePath) hashed tree, the encrypted-backup-adds-data paradox.
- `04-logical-acquisition-with-libimobiledevice` — lockdownd/pairing/escrow-bag, idevicebackup2/
  pymobiledevice3/mvt, the reproducible OSS workflow.
- `05-full-file-system-acquisition` — BootROM-exploit (checkm8/usbliter8) vs agent vs commercial;
  the SEP wall; the realistic 2026 matrix.
- `06-icloud-acquisition-and-advanced-data-protection` — backups vs synced data, tokens/anisette,
  the legal-process route, and how ADP forecloses both.
- `07-decrypting-backups-and-images` — the crackable surface (weak backup passwords, hashcat
  -m 14800) vs the uncrackable one (the SEP-bound device passcode).
- `08-acquisition-sop-and-chain-of-custody` (landmark capstone, ⚖️) — isolation → identification
  → method selection → hashing → a defensible chain-of-custody package.
- Built via the **chunked** module-builder (3 lessons/chunk) after the first two attempts hit a
  session-usage limit and then a server burst-throttle; chunking spread the load and made
  partial progress resumable. 0 review problems.

## 2026-06-26 — Part 03 (Security Architecture) built — 33/105 lessons ✅ — FOUNDATION TIER COMPLETE

The security spine: the layered Platform-Security model; the SEP/SEPOS software deep dive (L4
microkernel, the keystore, why SEP is the acquisition wall); Data Protection + the keybags (the
four NSFileProtection classes, the per-file→class-key→keybag wrap chain); passcode + BFU/AFU +
the iOS 18 inactivity reboot (the keystone forensic-state lesson); code signing + AMFI +
entitlements + CoreTrust + trust caches; the sandbox + TCC on iOS; the kernel-hardening ladder
(KASLR→KPP→KTRR→PAC→PPL→SPTM/TXM→Exclaves→MIE); biometrics security (the disable conditions +
the compelled-biometrics legal split); the Keychain (keychain-2.db, kSecAttrAccessible classes);
and Lockdown Mode / Stolen Device Protection / Advanced Data Protection.

- Built 9/10 via the module-builder workflow; **`04-code-signing-amfi-entitlements` was authored
  by hand** because the workflow author tripped a cybersecurity content-filter on the CoreTrust/
  AMFI material (a recurring false-positive on legitimate, Apple-documented security topics — the
  authored lessons are fine; only the fresh-agent meta-prompt phrasing trips it). Notably the
  kernel-hardening lesson (06) came through the workflow cleanly.

With Parts 00–03 done, every vocabulary item the forensics, dev, and RE pillars depend on
(SEP/keybags, BFU/AFU, code-signing/AMFI, the mitigation ladder, the container model) is written
and cross-linkable.

## 2026-06-26 — Part 02 (System Architecture & Internals) built — 23/105 lessons ✅

XNU/Darwin on mobile; the SecureROM→iBoot→kernelcache→launchd boot chain; IMG4/SHSH
personalization; APFS + the sealed System volume; launchd + the system-daemon cast; processes/
Mach/XPC + the restricted debugging surface; memory/jetsam + the app lifecycle; the dyld shared
cache + AMFI/trust-cache; the filesystem/container map; unified logging + sysdiagnose; and the
usbmuxd/lockdownd/AFC/mobilebackup2 device-services stack (+ iOS 17 RemoteXPC). Built in two
passes (server rate-limiting interrupted the first; resumed from cache to fill 4 gap lessons).

**Currency correction (live research caught a stale baseline):** an author agent's web search
surfaced **usbliter8** — a real, verified (The Hacker News / The Register / 9to5Mac /
AppleInsider, 2026-06-18) checkm8-style **unpatchable SecureROM exploit for A12–A13** by
Paradigm Shift. This moves the BootROM-exploit acquisition boundary from **A11→A12** to
**A13→A14** (A8–A11 checkm8 + A12–A13 usbliter8; A14+ has no public BootROM exploit). Since this
is the single most load-bearing fact in mobile forensics, the boundary was reconciled across the
build: the boot-chain lesson covers it natively, and the SoC-matrix, mental-model, platform-
history, DFU, APFS, and device-services lessons (Parts 00–02) plus the HANDOFF grounded baseline
were corrected. Jailbreak/kernel-patching claims were left intact (a BootROM exploit is not a
kernel jailbreak; there is still no public kernel jailbreak for A12+ on iOS 18/26).

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
