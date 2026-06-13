---
title: macOS Mastery — Full Curriculum Map
type: course-map
---

# Curriculum map

The complete lesson list, in recommended order. Each row links to the lesson and
shows its build status. Track *your own* completion in [PROGRESS.md](PROGRESS.md).

**Status legend:** ✅ written · 🚧 in progress · ⬜ planned (stub/not yet written)

> **Corpus status:** all 84 lessons + 8 reference spines are written (initial multi-agent build, 2026-06-13). Remaining work is polish/normalization, not authoring — see [HANDOFF.md](HANDOFF.md).

Lesson files are named `NN-slug.md` inside each `part-*` folder. Reference spines
live in [reference/](reference/).

---

## Part 00 — Orientation

| # | Lesson | Status |
|---|---|---|
| 00 | [How to Use This Course](part-00-orientation/00-how-to-use-this-course.md) | ✅ |
| 01 | [Windows → macOS: the mental-model reset](part-00-orientation/01-windows-to-macos-mental-models.md) | ✅ |
| 02 | [The Apple ecosystem & a history of macOS](part-00-orientation/02-apple-ecosystem-and-history.md) | ✅ |

## Part 01 — System Architecture & Internals

| # | Lesson | Status |
|---|---|---|
| 00 | [Darwin & the XNU kernel (Mach + BSD)](part-01-architecture/00-darwin-and-xnu-kernel.md) | ✅ |
| 01 | [The boot process — Apple Silicon & Intel](part-01-architecture/01-boot-process.md) | ✅ |
| 02 | [Apple Silicon: the SoC & Secure Enclave](part-01-architecture/02-apple-silicon-soc-and-secure-enclave.md) | ✅ |
| 03 | [APFS deep dive](part-01-architecture/03-apfs-deep-dive.md) | ✅ |
| 04 | [Filesystem layout & domains](part-01-architecture/04-filesystem-layout-and-domains.md) | ✅ |
| 05 | [launchd & the launch system](part-01-architecture/05-launchd-and-the-launch-system.md) | ✅ |
| 06 | [Processes, Mach & XPC](part-01-architecture/06-processes-mach-and-xpc.md) | ✅ |
| 07 | [Memory, virtual memory & swap](part-01-architecture/07-memory-virtual-memory-and-swap.md) | ✅ |
| 08 | [Security architecture: SIP, Gatekeeper, TCC](part-01-architecture/08-security-architecture.md) | ✅ |
| 09 | [Spotlight, metadata & extended attributes](part-01-architecture/09-spotlight-metadata-and-xattrs.md) | ✅ |
| 10 | [Unified logging & diagnostics](part-01-architecture/10-unified-logging-and-diagnostics.md) | ✅ |

## Part 02 — GUI Power User

| # | Lesson | Status |
|---|---|---|
| 00 | [Finder mastery](part-02-gui/00-finder-mastery.md) | ✅ |
| 01 | [Window management: Spaces, Mission Control, Stage Manager](part-02-gui/01-window-management.md) | ✅ |
| 02 | [Menu bar, Control Center, Notifications & the Dock](part-02-gui/02-menubar-control-center-dock.md) | ✅ |
| 03 | [Spotlight as a launcher & everything-box](part-02-gui/03-spotlight-as-launcher.md) | ✅ |
| 04 | [Keyboard shortcuts & customization](part-02-gui/04-keyboard-shortcuts-and-customization.md) | ✅ |
| 05 | [Text editing & system services](part-02-gui/05-text-editing-and-services.md) | ✅ |
| 06 | [System Settings — complete tour](part-02-gui/06-system-settings-tour.md) | ✅ |
| 07 | [Quick Look & Preview](part-02-gui/07-quick-look-and-preview.md) | ✅ |
| 08 | [Screenshots & screen recording](part-02-gui/08-screenshots-and-screen-recording.md) | ✅ |
| 09 | [Continuity: Handoff, AirDrop, Universal Clipboard, Sidecar](part-02-gui/09-continuity.md) | ✅ |
| 10 | [Accessibility features as power tools](part-02-gui/10-accessibility-as-power-tools.md) | ✅ |

## Part 03 — The Command Line

| # | Lesson | Status |
|---|---|---|
| 00 | [Terminal & shells overview](part-03-cli/00-terminal-and-shells.md) | ✅ |
| 01 | [zsh deep dive](part-03-cli/01-zsh-deep-dive.md) | ✅ |
| 02 | [Shell fundamentals: pipes, redirection, jobs](part-03-cli/02-shell-fundamentals.md) | ✅ |
| 03 | [Essential Unix commands](part-03-cli/03-essential-unix-commands.md) | ✅ |
| 04 | [The macOS-specific CLI toolbox](part-03-cli/04-macos-specific-cli-tools.md) | ✅ |
| 05 | [`defaults` & property lists](part-03-cli/05-defaults-and-plists.md) | ✅ |
| 06 | [Text processing: grep, sed, awk, jq](part-03-cli/06-text-processing.md) | ✅ |
| 07 | [Files, permissions, ACLs & flags](part-03-cli/07-files-permissions-acls-flags.md) | ✅ |
| 08 | [Networking from the command line](part-03-cli/08-networking-cli.md) | ✅ |
| 09 | [Process & resource management from the CLI](part-03-cli/09-process-management-cli.md) | ✅ |
| 10 | [SSH & remote access](part-03-cli/10-ssh-and-remote-access.md) | ✅ |
| 11 | [Scripting: bash, AppleScript, JXA, Shortcuts CLI](part-03-cli/11-scripting.md) | ✅ |
| 12 | [Homebrew & package management](part-03-cli/12-homebrew-and-package-management.md) | ✅ |

## Part 04 — Maintenance, Backup & Recovery

| # | Lesson | Status |
|---|---|---|
| 00 | [Time Machine internals](part-04-maintenance/00-time-machine-internals.md) | ✅ |
| 01 | [Backup strategies & tools (3-2-1, CCC, SuperDuper)](part-04-maintenance/01-backup-strategies.md) | ✅ |
| 02 | [Disk Utility & APFS management](part-04-maintenance/02-disk-utility-and-apfs-management.md) | ✅ |
| 03 | [Recovery mode & reinstalling macOS](part-04-maintenance/03-recovery-and-reinstall.md) | ✅ |
| 04 | [Boot modes: Safe, Recovery, DFU](part-04-maintenance/04-boot-modes.md) | ✅ |
| 05 | [Migration Assistant](part-04-maintenance/05-migration-assistant.md) | ✅ |
| 06 | [Troubleshooting methodology](part-04-maintenance/06-troubleshooting-methodology.md) | ✅ |
| 07 | [Performance diagnosis](part-04-maintenance/07-performance-diagnosis.md) | ✅ |
| 08 | [Software update & OS install internals](part-04-maintenance/08-software-update-internals.md) | ✅ |

## Part 05 — Security, Privacy & Forensics

| # | Lesson | Status |
|---|---|---|
| 00 | [The macOS security model](part-05-security-forensics/00-the-security-model.md) | ✅ |
| 01 | [FileVault & encryption internals](part-05-security-forensics/01-filevault-and-encryption.md) | ✅ |
| 02 | [TCC & privacy internals](part-05-security-forensics/02-tcc-and-privacy.md) | ✅ |
| 03 | [Forensic artifacts on macOS](part-05-security-forensics/03-forensic-artifacts.md) | ✅ |
| 04 | [Keychain & secrets management](part-05-security-forensics/04-keychain-and-secrets.md) | ✅ |
| 05 | [Firewall & network security](part-05-security-forensics/05-firewall-and-network-security.md) | ✅ |
| 06 | [Malware, XProtect & persistence](part-05-security-forensics/06-malware-xprotect-persistence.md) | ✅ |
| 07 | [Privacy & security hardening playbook](part-05-security-forensics/07-hardening-playbook.md) | ✅ |

## Part 06 — Automation & Productivity

| # | Lesson | Status |
|---|---|---|
| 00 | [Automator](part-06-automation/00-automator.md) | ✅ |
| 01 | [The Shortcuts app & `shortcuts` CLI](part-06-automation/01-shortcuts-app-and-cli.md) | ✅ |
| 02 | [AppleScript & JXA](part-06-automation/02-applescript-and-jxa.md) | ✅ |
| 03 | [launchd for personal automation](part-06-automation/03-launchd-personal-automation.md) | ✅ |
| 04 | [Rule engines: Hazel & Keyboard Maestro](part-06-automation/04-hazel-and-keyboard-maestro.md) | ✅ |
| 05 | [Launchers: Raycast & Alfred](part-06-automation/05-launchers-raycast-alfred.md) | ✅ |
| 06 | [Text expansion & clipboard managers](part-06-automation/06-text-expansion-and-clipboard.md) | ✅ |

## Part 07 — Development Environment

| # | Lesson | Status |
|---|---|---|
| 00 | [Xcode demystified](part-07-development/00-xcode-demystified.md) | ✅ |
| 01 | [Command Line Tools vs full Xcode](part-07-development/01-command-line-tools-vs-xcode.md) | ✅ |
| 02 | [The build system, SDKs & simulators](part-07-development/02-build-system-sdks-simulators.md) | ✅ |
| 03 | [Code signing & provisioning](part-07-development/03-code-signing-and-provisioning.md) | ✅ |
| 04 | [Notarization & distribution](part-07-development/04-notarization-and-distribution.md) | ✅ |
| 05 | [Command-line development: clang, swift, lldb](part-07-development/05-command-line-development.md) | ✅ |
| 06 | [Developer package managers (SPM, npm, pyenv, …)](part-07-development/06-dev-package-managers.md) | ✅ |
| 07 | [Terminal dev workflow & dotfiles](part-07-development/07-terminal-dev-workflow-and-dotfiles.md) | ✅ |
| 08 | [Containers & VMs on the Mac](part-07-development/08-containers-and-vms.md) | ✅ |
| 09 | [Universal binaries, Rosetta & architecture](part-07-development/09-universal-binaries-rosetta-arch.md) | ✅ |

## Part 08 — Networking & Connectivity

| # | Lesson | Status |
|---|---|---|
| 00 | [The macOS networking stack](part-08-networking/00-networking-stack.md) | ✅ |
| 01 | [File & screen sharing](part-08-networking/01-file-and-screen-sharing.md) | ✅ |
| 02 | [iCloud & Apple ID internals](part-08-networking/02-icloud-and-apple-id.md) | ✅ |
| 03 | [VPN & secure connectivity](part-08-networking/03-vpn-and-secure-connectivity.md) | ✅ |
| 04 | [Bluetooth, peripherals & drivers](part-08-networking/04-bluetooth-peripherals-drivers.md) | ✅ |

## Part 09 — Apps & Ecosystem

| # | Lesson | Status |
|---|---|---|
| 00 | [Anatomy of a Mac app bundle](part-09-apps/00-anatomy-of-an-app-bundle.md) | ✅ |
| 01 | [App distribution: App Store vs direct vs Homebrew](part-09-apps/01-app-distribution-channels.md) | ✅ |
| 02 | [The power-user app stack](part-09-apps/02-power-user-app-stack.md) | ✅ |
| 03 | [Media & creative tools](part-09-apps/03-media-and-creative-tools.md) | ✅ |

## Part 10 — Hardware

| # | Lesson | Status |
|---|---|---|
| 00 | [The Apple Silicon Mac lineup & specs](part-10-hardware/00-apple-silicon-lineup.md) | ✅ |
| 01 | [Ports, displays, Thunderbolt & docks](part-10-hardware/01-ports-displays-thunderbolt.md) | ✅ |
| 02 | [Battery, thermal & power management](part-10-hardware/02-battery-thermal-power.md) | ✅ |

---

## Reference spines

| Reference | Purpose |
|---|---|
| [Glossary](reference/glossary.md) | Every term, defined |
| [Acronyms](reference/acronyms.md) | APFS, TCC, SIP, XPC, … decoded |
| [Keyboard-shortcut master sheet](reference/keyboard-shortcuts.md) | System-wide & app shortcuts |
| [Modifier-symbol legend](reference/modifier-symbols.md) | ⌘⌥⌃⇧ and friends |
| [CLI cheat-sheet](reference/cli-cheatsheet.md) | macOS-specific commands, fast |
| [Windows → macOS translation](reference/windows-to-macos.md) | "The X of macOS" lookup table |
| [Recommended software](reference/recommended-software.md) | The curated power-user stack |
| [Further reading](reference/further-reading.md) | Books, sites, docs, communities |
