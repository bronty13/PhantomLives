---
title: macOS Mastery
type: course-home
audience: power-user-in-training (forensics background, Windows switcher)
target_platform: macOS 26.x (Tahoe-era), Apple Silicon
status: living document
---

# macOS Mastery — from Windows switcher to top-1% power user

A complete, self-paced curriculum for **deeply** understanding macOS — not at the
"where's the Start menu" level, but at the level a computer-forensics engineer
and serious power user needs: *how the system actually works under the hood*, and
how to bend it to your will from both the GUI and the command line.

This was built for someone who:

- has a **computer-forensics background** and wants the engineering details
  (kernel, filesystem internals, on-disk artifacts, security model);
- **switched from Windows** and keeps getting tripped up by macOS-specific
  idioms;
- builds software (so the **Xcode / signing / toolchain** confusion gets cleared
  up properly);
- wants to end up in the **top 1%** of Mac power users — curated from Apple docs,
  Reddit, GitHub, and the wider community, not just what an Apple employee learns.

> **Platform note.** Everything targets **modern macOS (version 26.x, the
> Tahoe-era year-based naming) on Apple Silicon**, with historical/Intel context
> called out where it still matters (T2 Macs, kexts, SMC/NVRAM resets, etc.).

---

## How to use this course

1. **Read [How to Use This Course](part-00-orientation/00-how-to-use-this-course.md) first.** It explains the lesson format, the lab conventions, and how to pace yourself.
2. **Follow the path in [CURRICULUM.md](CURRICULUM.md).** Parts are ordered to build on each other, but each lesson is self-contained enough to jump around once you have the Part 00–01 foundation.
3. **Do the labs.** Reading about `launchd` teaches you nothing; writing a LaunchAgent and watching it fire teaches you everything. Labs assume competence and use real, sometimes destructive, operations — read the ⚠️ warnings.
4. **Track your progress in [PROGRESS.md](PROGRESS.md).** Check off lessons as you complete them.
5. **Keep the [reference/](reference/) spines open in a second pane** — the glossary, acronym list, keyboard-shortcut master sheet, and CLI cheat-sheet are meant to be consulted constantly, not read front-to-back.

### Suggested pacing

| Pace | Plan |
|---|---|
| **Sprint** (2–3 wks) | 1 lesson/day + its labs. Skim Parts you already half-know, drill the CLI and Architecture parts. |
| **Steady** (8–10 wks) | 2–3 lessons/week with labs. The default. |
| **Mastery** (ongoing) | One lesson per sitting, do *every* lab, and write your own notes back into Obsidian alongside the synced copy. |

---

## The eleven parts

| Part | Theme | Why it matters |
|---|---|---|
| **00 — Orientation** | Mental-model reset for Windows switchers; ecosystem & history | Stops you fighting the OS with Windows reflexes |
| **01 — Architecture & Internals** | Darwin/XNU, boot, Apple Silicon, APFS, launchd, security model | The forensics-grade "how it actually works" core |
| **02 — GUI Power User** | Finder, window management, Spotlight, shortcuts, Settings, Continuity | Daily-driver speed and the hidden GUI features |
| **03 — The Command Line** | Shells, zsh, the macOS-specific CLI toolbox, scripting, Homebrew | Where power users actually live |
| **04 — Maintenance, Backup & Recovery** | Time Machine internals, Disk Utility, recovery/DFU, troubleshooting | Fixing it when it breaks; never losing data |
| **05 — Security, Privacy & Forensics** | Security model, FileVault, TCC, on-disk artifacts, malware, hardening | Your home turf — made macOS-specific |
| **06 — Automation & Productivity** | Shortcuts, AppleScript/JXA, launchd jobs, Hazel/KM, launchers | Make the Mac do your repetitive work |
| **07 — Development Environment** | Xcode demystified, CLT, signing, notarization, toolchain, VMs | Stop being confused by Xcode and code signing |
| **08 — Networking & Connectivity** | Networking stack, sharing, iCloud internals, VPN, Bluetooth | The connectivity layer, end to end |
| **09 — Apps & Ecosystem** | App-bundle anatomy, distribution channels, the power-user app stack | What to install and *why* |
| **10 — Hardware** | Apple Silicon lineup, ports/displays/Thunderbolt, battery/thermal | Knowing your machine |

Plus **[reference/](reference/)**: glossary · acronyms · keyboard-shortcut master sheet · modifier-symbol legend · CLI cheat-sheet · Windows→macOS translation table · recommended-software stack · further reading.

---

## This folder syncs to Obsidian automatically

This curriculum lives in the PhantomLives repo as plain Markdown. The repo's
`sync-md-to-obsidian.sh` mirrors every **git-tracked** `.md` file into your
Obsidian vault (`<vault>/PhantomLives/macos-mastery/…`), so once these lessons
are committed they appear in Obsidian with working `[[wikilinks]]` and
frontmatter. Read in Obsidian, but **author/edit in the repo** — the mirror is
one-way (Obsidian edits don't flow back). See `docs/obsidian-sync.md`.

To force a sync now: `./sync-md-to-obsidian.sh` from the repo root.

---

## Conventions used throughout

- **`⌘`** Command · **`⌥`** Option/Alt · **`⌃`** Control · **`⇧`** Shift · **`fn`** Function · **`↩`** Return · **`⎋`** Escape. (Full legend: [reference/modifier-symbols.md](reference/modifier-symbols.md).)
- **`$`** prefixes a normal-user shell command; **`#`** or `sudo` prefixes a root command.
- **🪟 Windows contrast** callouts map a macOS concept back to its Windows equivalent.
- **🔬 Forensics note** callouts flag on-disk artifacts, logs, and investigative angles.
- **⚠️ ADVANCED / DESTRUCTIVE** callouts precede operations that can damage data or weaken security — they include backup-first and rollback steps.
- **🧪 Lab** sections are hands-on. Do them.
