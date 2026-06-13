---
title: How to Use This Course
part: P00 — Orientation
lesson: 00
est_time: 20 min read + 30 min setup labs
prerequisites: []
tags: [macos, orientation, setup, obsidian, apfs, time-machine]
---

# How to Use This Course

> **In one sentence:** Before you open a single lesson, understand the architecture of the curriculum, configure a safe practice environment, and get Obsidian sync running — so that every lab you run is recoverable and every note you take lands in the right place.

---

## Why this matters

This course is opinionated about depth. It will ask you to inspect kernel internals, create APFS snapshots from the command line, poke the Transparency, Consent, and Control database, and forge LaunchAgent plists that run as your login session. Done in your daily production environment without a safety net, even one typo can ruin a workday. Done in a prepared environment — a dedicated test user, a Time Machine disk, and a manual snapshot — the same operations become learning, not gambling.

Spending 30 minutes on setup now saves hours of recovery later and builds muscle memory for the forensics-grade discipline that underpins every lab in this curriculum.

---

## Concepts

### Curriculum architecture

The course is organized into **eleven parts** (P00–P10) plus **reference spines**:

| Part | Theme |
|------|-------|
| **00 — Orientation** | Mental-model reset; ecosystem; this file |
| **01 — Architecture & Internals** | Darwin/XNU, boot, Apple Silicon, APFS, launchd, security model |
| **02 — GUI Power User** | Finder, Spaces, Spotlight, shortcuts, Continuity |
| **03 — The Command Line** | zsh, the macOS-specific toolbox, scripting, Homebrew |
| **04 — Maintenance, Backup & Recovery** | Time Machine, Disk Utility, recovery/DFU modes |
| **05 — Security, Privacy & Forensics** | Security model, FileVault, TCC, on-disk artifacts, malware |
| **06 — Automation & Productivity** | Shortcuts, AppleScript/JXA, launchd, Hazel, Raycast |
| **07 — Development Environment** | Xcode, signing, notarization, toolchain, VMs |
| **08 — Networking & Connectivity** | Networking stack, sharing, iCloud, VPN, Bluetooth |
| **09 — Apps & Ecosystem** | App-bundle anatomy, distribution channels, power-user stack |
| **10 — Hardware** | Apple Silicon lineup, Thunderbolt, battery/thermal |

The **reference spines** in `reference/` are not lessons — they are consult-constantly lookup tables:

- `glossary.md` — every term defined
- `acronyms.md` — APFS, TCC, SIP, XPC, ... decoded
- `keyboard-shortcuts.md` — system-wide and app-specific shortcuts
- `modifier-symbols.md` — the Unicode symbol legend for ⌘⌥⌃⇧ and friends
- `cli-cheatsheet.md` — macOS-specific CLI commands, fast
- `windows-to-macos.md` — "the X of macOS" cross-reference table
- `recommended-software.md` — curated power-user stack with rationale
- `further-reading.md` — books, sites, docs, communities

Parts are ordered to build on each other: P01 (internals) underpins everything in P04 (recovery) and P05 (forensics). That said, every lesson is written to be self-contained enough that a professional with prior context can jump straight to what they need. A forensics engineer who already knows APFS can open [[03-apfs-deep-dive]] without reading P01 lessons 0–2.

### Lesson anatomy

Every lesson follows an identical skeleton so you know where to find things without hunting:

1. **YAML frontmatter** — title, part, estimated time, prerequisites, tags. Obsidian and most Markdown renderers surface these as document metadata.
2. **One-sentence thesis** — the lesson's core claim in a single blockquote. If you remember only one thing, this is it.
3. **Why this matters** — 2–4 sentences tying the topic to real-world payoff (power-user speed, forensics practice, build-system confidence).
4. **Concepts** — the engineering meat. Mechanisms, not UI steps. Daemons named, files located, data formats described.
5. **Hands-on (CLI & GUI)** — concrete commands with real flags and described expected output.
6. **Labs** — full-power numbered exercises. Real operations, including destructive ones.
7. **Pitfalls & gotchas** — the Windows-switcher traps and silent failure modes.
8. **Key takeaways** — 5–8 bullet recap for review.
9. **Terms introduced** — new vocabulary, also cross-listed in the reference glossary.
10. **Further reading** — man pages, Apple docs, Howard Oakley posts, community threads.

### Callout conventions

Four callout types appear throughout. Learn to read them at a glance:

> 🪟 **Windows contrast:** Maps a macOS concept to its Windows equivalent. Designed to short-circuit the cognitive dissonance of a deep Windows background. Example: `launchd` is not `Task Scheduler` in the way you'd expect — it is PID 1, the kernel's first userspace process, and it manages every other daemon and agent.

> 🔬 **Forensics note:** Flags on-disk artifacts, log locations, and investigative angles. Example: the path of a Launch Agent plist, a TCC database entry, or a Unified Log subsystem filter that reveals what really happened.

> ⚠️ **ADVANCED / DESTRUCTIVE:** Precedes any operation that can damage data, break system security, or produce hard-to-reverse changes. Always includes: what to back up first, the exact rollback command, and what failure looks like so you know whether to proceed.

> 🧪 **Lab:** The hands-on sections. Do them. Reading about APFS snapshots teaches you nothing; creating one, verifying it, and rolling back to it teaches you the mechanism.

### Modifier-symbol legend

macOS documentation and UI uses Unicode symbols for keyboard modifiers. You will see these throughout the course and in every keyboard-shortcut reference:

| Symbol | Key | Notes |
|--------|-----|-------|
| ⌘ | Command | The "Apple key" or "Cmd". No Windows direct equivalent — closest is ⊞ Win but the role is very different. |
| ⌥ | Option / Alt | Labeled "alt" on some keyboards. Produces hidden characters and modifier variants. |
| ⌃ | Control | Present on macOS but plays a smaller role than on Windows/Linux; Ctrl-C does *not* interrupt the foreground process from the keyboard in macOS unless you are in a terminal. |
| ⇧ | Shift | Standard. |
| fn | Function | On laptop keyboards; repurposes F-keys. Also the globe key on newer keyboards (access emoji, Dictation, Shortcuts). |
| ↩ | Return | "Enter" on the main keyboard. |
| ⌫ | Delete | What Windows calls Backspace. Mac has no "forward delete" key on compact keyboards — use fn⌫. |
| ⌦ | Forward Delete | fn⌫ on compact keyboards; dedicated key on full-size. |
| ⎋ | Escape | Standard. |
| ⇥ | Tab | Standard. |
| ↑↓←→ | Arrow keys | Standard. |

Full legend with edge cases lives in [[modifier-symbols]] (`reference/modifier-symbols.md`).

### Shell prompt conventions

In command blocks throughout this course:

- `$` prefix = normal user shell (your own account, no elevation)
- `#` prefix = root shell — only when explicitly needed; the safer form is `sudo command`
- No prefix = output you should expect to see

---

## Setting up a safe practice environment

### Why a dedicated test user?

The most dangerous labs in this curriculum involve modifying TCC permissions, tweaking SIP-adjacent settings, installing and uninstalling LaunchAgents, and testing Gatekeeper bypass scenarios. These operations can interfere with your daily workflow if run as your primary account. A throwaway admin account and a throwaway standard account give you a clean slate where irreversible mistakes cost you five minutes to delete and recreate the user — not an afternoon recovering your real profile.

You need **two** test users:
- **A test admin account** (`labadmin` or similar) — for operations that require admin privileges (installing to `/Applications`, modifying system settings, disabling/enabling SIP in specific recovery-mode labs).
- **A test standard account** (`labuser` or similar) — for testing how non-admin users experience macOS, TCC prompts, and Gatekeeper behavior.

**Create both from the command line** (faster than System Settings):

```bash
# Create a test admin user (replace UID 503 with one not already in use)
$ sudo dscl . -create /Users/labadmin
$ sudo dscl . -create /Users/labadmin UserShell /bin/zsh
$ sudo dscl . -create /Users/labadmin RealName "Lab Admin"
$ sudo dscl . -create /Users/labadmin UniqueID 503
$ sudo dscl . -create /Users/labadmin PrimaryGroupID 20
$ sudo dscl . -create /Users/labadmin NFSHomeDirectory /Users/labadmin
$ sudo createhomedir -c -u labadmin
$ sudo dscl . -passwd /Users/labadmin 'yourpassword'
$ sudo dscl . -append /Groups/admin GroupMembership labadmin

# Create a test standard user
$ sudo dscl . -create /Users/labuser
$ sudo dscl . -create /Users/labuser UserShell /bin/zsh
$ sudo dscl . -create /Users/labuser RealName "Lab User"
$ sudo dscl . -create /Users/labuser UniqueID 504
$ sudo dscl . -create /Users/labuser PrimaryGroupID 20
$ sudo dscl . -create /Users/labuser NFSHomeDirectory /Users/labuser
$ sudo createhomedir -c -u labuser
$ sudo dscl . -passwd /Users/labuser 'yourpassword'
# Note: do NOT add labuser to the admin group
```

Verify with:
```bash
$ dscl . -read /Users/labadmin UniqueID RealName
$ id labadmin
```

> 🔬 **Forensics note:** `dscl` is the Directory Service command-line tool. User records are stored in Open Directory, ultimately backed by a SQLite database at `/private/var/db/dslocal/nodes/Default/users/<username>.plist` (a binary property list, readable with `plutil -p`). The `dscacheutil -q user -a name labadmin` command queries the cache layer (similar to Windows' `net user`). These paths are key forensic artifacts for timeline reconstruction.

> 🪟 **Windows contrast:** macOS has no `net user /add` equivalent in a single command — `dscl` is the low-level Directory Services tool, and the higher-level `sysadminctl` (introduced in macOS 10.12) can create users in one line: `sudo sysadminctl -addUser labadmin -password yourpassword -admin`. The `dscl` approach is shown here because it exposes the underlying data model you'll need in Part 05.

To delete a test user when you're done with it:
```bash
$ sudo dscl . -delete /Users/labadmin
$ sudo rm -rf /Users/labadmin
```

### Time Machine — your primary recovery safety net

Before running *any* lab in this curriculum, ensure you have a current Time Machine backup. If you don't have Time Machine configured, configure it now:

1. Connect an external drive (USB, Thunderbolt, or NAS share).
2. **System Settings → General → Time Machine → Add Backup Disk**.
3. Force an immediate backup: `$ tmutil startbackup --auto`
4. Verify it completed: `$ tmutil latestbackup`

Expected output from `tmutil latestbackup`:
```
/Volumes/Backup/Backups.backupdb/MacBookPro/2026-06-13-143022
```

> 🔬 **Forensics note:** Time Machine backups since macOS Big Sur use APFS snapshots on the destination volume rather than the older HFS+ hard-link tree structure. `tmutil listbackups` shows all available restore points. The source volume's snapshots used during backup are visible via `tmutil listlocalsnapshots /`.

### APFS snapshots — surgical per-session safety

Time Machine is your global safety net; APFS local snapshots are surgical, per-session protection. You can create a named snapshot in seconds, run a destructive lab, and roll back to that exact state — all without touching an external drive.

**Create a snapshot before a lab session:**

```bash
$ tmutil localsnapshot
```

This triggers the system to take an APFS snapshot of every mounted local APFS volume. On modern macOS, Time Machine manages local snapshots automatically on a rolling basis, but forcing one before a lab session gives you a guaranteed named restore point.

List existing local snapshots:
```bash
$ tmutil listlocalsnapshots /
com.apple.TimeMachine.2026-06-13-143022
com.apple.TimeMachine.2026-06-13-150001
```

To roll back to a snapshot (⚠️ this requires booting to Recovery):

1. Shut down.
2. Hold the power button until "Loading startup options" appears (Apple Silicon) or hold ⌘R at boot (Intel).
3. Open Terminal from Utilities menu.
4. `$ tmutil restore /Volumes/<snapshot-name> /Volumes/Macintosh\ HD`

For many labs, you won't need a full rollback — the lab itself includes the undo steps. Snapshots are the nuclear option.

**Delete a snapshot when it's no longer needed** (they consume disk space):
```bash
$ tmutil deletelocalsnapshots 2026-06-13-143022
```

> 🔬 **Forensics note:** APFS snapshots are immutable point-in-time views of the volume. From a forensics perspective, a suspect's local snapshots (listed via `tmutil listlocalsnapshots /` or directly via `diskutil apfs listSnapshots disk3s1`) can reveal the state of the filesystem at a past point — including files that were subsequently deleted. See [[03-apfs-deep-dive]] for the COW (copy-on-write) mechanism behind why deleted files persist in snapshots.

> ⚠️ **ADVANCED / DESTRUCTIVE:** `tmutil deletelocalsnapshots` with an old timestamp is safe; `tmutil deletelocalsnapshots /` on a bare volume path deletes *all* snapshots. Don't confuse the two forms. Rolling back to a snapshot replaces the live volume state — anything written after the snapshot was taken is gone. Always note the exact snapshot name before relying on it as a restore point.

---

## How to pace yourself

There is no wrong pace. This is not a course with a clock. Three suggested modes:

| Mode | Target audience | Plan |
|------|----------------|------|
| **Sprint** (2–3 weeks) | You're already technical; this is orientation + gap-filling | One lesson per day including its labs. Skim parts you half-know; drill Architecture and CLI deeply. |
| **Steady** (8–10 weeks) | Default for someone building macOS mastery alongside a day job | Two to three lessons per week with labs done fully. |
| **Mastery** (ongoing, no fixed end) | You want to internalize, not just recognize | One lesson per sitting, every lab completed, notes written back into your Obsidian vault. Circle back to early lessons after finishing later ones — Part 05 forensics lessons will recast Part 01 architecture material in a completely new light. |

A working rule: **if you can't explain the mechanism after the lab, re-read the Concepts section**. The goal is not to have run the commands — it is to understand why they work. Any reference to "run this command" is an invitation to read the man page before running it.

---

## How Obsidian sync works for this folder

The curriculum lives in the PhantomLives git repository at `~/dev/PhantomLives/macos-mastery/`. The repo's `sync-md-to-obsidian.sh` script mirrors every **git-tracked** `.md` file into your Obsidian vault at `<vault>/PhantomLives/macos-mastery/…`, preserving the directory structure.

Key behaviors:

- **One-way**: the script copies from the repo to the vault. Edits you make in Obsidian do not flow back to the repo.
- **Git-tracked only**: files that exist on disk but haven't been `git add`ed won't appear in Obsidian. New lessons must be committed before they sync.
- **Wikilinks work**: the lesson files use `[[slug]]` wikilinks that Obsidian resolves by filename. They also include relative Markdown links so the files are navigable in any Markdown renderer (VS Code, GitHub, etc.).
- **Hourly auto-sync** (optional): the script can install a launchd agent that refreshes the vault hourly — `./sync-md-to-obsidian.sh --install-agent`.

To force a sync now from the repo root:
```bash
$ ./sync-md-to-obsidian.sh
```

If the vault lives under iCloud Drive, the script must run as a user with Full Disk Access (or you'll get a permission error writing to the TCC-protected vault path). The `--install-agent` background agent requires a one-time grant of Full Disk Access to `/bin/bash` in System Settings → Privacy & Security → Full Disk Access. See `docs/obsidian-sync.md` for the full rationale.

> 🔬 **Forensics note:** The fact that iCloud Drive is TCC-protected — even for processes running as the user who owns it — is a direct consequence of the macOS privacy model introduced in Mojave and hardened in Sequoia/Tahoe. TCC (Transparency, Consent, and Control) gates file-system access by *bundle identity*, not just by POSIX uid. A shell script running as `/bin/bash` has a different effective identity than the Finder. You'll examine this mechanism in depth in [[02-tcc-and-privacy]].

### Taking your own notes without breaking the mirror

The safest approach: **add a `personal-notes/` directory inside your Obsidian vault's `PhantomLives/macos-mastery/` folder** and keep your annotations there. The sync script won't touch that directory (it writes from the repo, not from the vault), so your notes are safe from being overwritten.

Do not edit the synced `.md` files directly in Obsidian — the next sync run will overwrite your changes. Instead:

- Use Obsidian's **backlink** feature to create a companion note that links to the lesson (e.g., `personal-notes/01-boot-process-notes.md` with `[[01-boot-process]]` at the top).
- Or use Obsidian **Canvas** to build mind maps connecting lesson concepts to your forensics work.
- Or add a `personal-notes/` git-tracked folder in the repo itself and commit your notes — they'll appear in Obsidian as regular synced files.

---

## 🧪 Labs

### Lab 1 — Create test users

⚠️ **Before starting:** This lab modifies your macOS user database. Have a Time Machine backup current. The rollback is `sudo dscl . -delete /Users/labadmin && sudo rm -rf /Users/labadmin` (and the same for `labuser`). The operation is reversible with no side effects beyond disk space.

1. Open Terminal.
2. Check which UIDs are already in use: `$ dscl . -list /Users UniqueID | sort -k2 -n | tail -10`
3. Choose UIDs for labadmin and labuser that are above 500 and not listed.
4. Run the `dscl` creation commands from the "Create both from the command line" block above, substituting your chosen UIDs.
5. Verify: `$ id labadmin && id labuser`
6. Switch to `labadmin` without logging out: `$ su - labadmin` (enter password). Run `$ whoami`. Type `exit` to return.
7. Inspect the raw user record: `$ sudo plutil -p /var/db/dslocal/nodes/Default/users/labadmin.plist | head -40`

You should see GeneratedUID, ShadowHashData, and home directory entries. These fields are what an incident responder or forensics tool reads when reconstructing account timelines.

### Lab 2 — Manual APFS snapshot before a future lab

⚠️ **This lab is safe — snapshots are read-only and adding one cannot damage data. The only risk is that they consume disk space until deleted.**

1. Verify Time Machine is configured: `$ tmutil destinationinfo`
2. Create a named snapshot: `$ tmutil localsnapshot`
3. List it: `$ tmutil listlocalsnapshots /`
   You should see an entry like `com.apple.TimeMachine.2026-06-13-HHMMSS`.
4. Check the snapshot's size on disk: `$ diskutil apfs listSnapshots disk3s1` (replace `disk3s1` with your main APFS data volume — find it with `$ diskutil list | grep 'APFS Volume'`).
5. Note the name. This is your restore point for any future lab in Part 01.
6. Delete the snapshot now (optional — just practicing the cleanup step):
   `$ tmutil deletelocalsnapshots 2026-06-13-HHMMSS` (use the actual timestamp from step 3).

### Lab 3 — Verify Obsidian sync

1. From the PhantomLives repo root: `$ ./sync-md-to-obsidian.sh`
2. Open Obsidian. Navigate to `PhantomLives/macos-mastery/part-00-orientation/`.
3. Confirm this file (`00-how-to-use-this-course.md`) appears and renders with the frontmatter parsed as document properties.
4. Click a `[[wikilink]]` — it should resolve to the target lesson file.
5. Create `<vault>/PhantomLives/macos-mastery/personal-notes/` manually in Finder or Obsidian. Create a test note inside it. Run the sync script again. Confirm the test note still exists (was not deleted).

---

## Pitfalls & gotchas

**"I want to just start in Part 05 — I already know forensics."**
You can, but read [[01-boot-process]], [[03-apfs-deep-dive]], and [[08-security-architecture]] from Part 01 first. macOS forensics has several sharp edges (Sealed System Volume, APFS snapshot artifacts, Endpoint Security framework) that are Windows-dissimilar enough to trip a seasoned forensics professional. The Part 01 architecture lessons are short — don't skip them.

**The labs feel slow/pedantic.**
Skip the "why" explanations and go straight to the ⚠️ and command blocks. But run the commands. Reading about a kernel mechanism is not the same as observing it.

**Obsidian wikilinks show as broken.**
The wikilink target must be a *committed and synced* file. If you just created a lesson but haven't committed and run `sync-md-to-obsidian.sh`, the target doesn't exist in the vault yet. Commit and sync.

**Test users accumulate over time.**
Delete them when no longer needed (`sudo dscl . -delete /Users/labuser && sudo rm -rf /Users/labuser`). Stale accounts with known passwords are a security liability even on a personal machine — and they're forensic artifacts that can confuse a future investigation.

**"My snapshot is gone."**
macOS will purge old local snapshots automatically when disk space is low. Time Machine also rotates them. Don't rely on a snapshot older than a few hours without having verified it's still listed in `tmutil listlocalsnapshots /`.

**Modifier symbols in keyboard shortcuts look like boxes.**
Your system font doesn't include those Unicode code points, or your Markdown renderer doesn't render them. Use the `reference/modifier-symbols.md` legend and a modern terminal/editor. iTerm2, Ghostty, and the macOS Terminal app all render these correctly.

---

## Key takeaways

- The course is 11 parts + reference spines; Parts 00–01 are the mandatory foundation; the rest can be accessed non-linearly by competent engineers.
- Callouts (🪟 🔬 ⚠️ 🧪) have specific, consistent meanings — learn them so you can skim efficiently.
- Run every lab. Reading the mechanism is 20% of the learning; running the command and seeing the output (or the failure) is the other 80%.
- Set up `labadmin` and `labuser` test accounts before starting Part 01 labs.
- Create a manual APFS snapshot (`tmutil localsnapshot`) before any session with destructive labs.
- Obsidian sync is one-way from the git repo. Keep personal notes in a separate directory within the vault or in a committed `personal-notes/` folder in the repo.
- The modifier symbol legend (⌘⌥⌃⇧fn) lives at [[modifier-symbols]]; refer to it constantly until the symbols are automatic.

---

## Terms introduced

- **APFS snapshot** — an immutable, point-in-time view of an APFS volume created via copy-on-write; no data is duplicated at creation time, only changed blocks are stored incrementally.
- **dscl** — Directory Service command-line utility; the low-level interface to Open Directory (macOS's local user/group/host database).
- **TCC (Transparency, Consent, and Control)** — the macOS privacy subsystem that gates per-app access to protected resources (Desktop, Documents, iCloud, Camera, Microphone, etc.) by bundle identity, not POSIX uid.
- **launchd** — PID 1 on macOS; the unified daemon and agent supervisor that replaces `init`, `cron`, `inetd`, and `rc` scripts from traditional Unix.
- **Time Machine local snapshot** — a Time Machine-managed APFS snapshot of the local volume, distinct from the off-device backup; used as a source for the backup diff and as a local restore point.
- **tmutil** — the command-line interface to Time Machine; supports `startbackup`, `localsnapshot`, `listlocalsnapshots`, `listbackups`, `latestbackup`, and `deletelocalsnapshots`.

---

## Further reading

- `man dscl`, `man tmutil`, `man diskutil` — the man pages are accurate and often more current than online docs.
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — the canonical reference for SIP, Secure Enclave, TCC, and the boot security chain; free PDF from Apple.
- Howard Oakley, *Eclectic Light Company* — [APFS in Detail](https://eclecticlight.co/2021/01/21/apfs-in-detail/) series; the most thorough third-party write-up of APFS internals available.
- [Apple Developer Documentation: File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/Introduction/Introduction.html) — historical but foundational for understanding the domain model.
- r/MacOSBeta and r/macOS on Reddit — community-sourced discovery of behavior changes between macOS releases; useful for finding where documented behavior and actual behavior diverge.
- [Mac-admins.slack.com](https://www.macadmins.org/) — the professional Mac administration community; forensics-adjacent workflows (MDM, endpoint security, log analysis) are discussed regularly.
