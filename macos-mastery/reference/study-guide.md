---
title: Study Guide
type: reference-derived
description: Module-by-module summary of the most important concepts, with self-test questions, for review
---

# macOS Mastery — Study Guide

**How to use this document:** Read one Part section after you finish the corresponding Part in the curriculum. For each lesson, the bullets here represent the highest-value facts — the things most likely to matter in real troubleshooting, forensics, or system work. If a bullet doesn't click, open the linked lesson (the `[[slug]]` is a wikilink into the course vault). End each Part with the "Check yourself" callout before moving on.

---

## Part 00 — Orientation

**Big picture:** Establishes mental scaffolding — how the course is structured, why macOS is architecturally unlike Windows, and where macOS came from.

### [[00-how-to-use-this-course]] — How to Use This Course

- The curriculum is 11 parts (P00–P10); every lesson has a fixed skeleton (thesis → concepts → labs → pitfalls → takeaways).
- Create `labadmin` (admin) and `labuser` (standard) accounts via `dscl` before Part 01 labs; user records live as binary plists at `/private/var/db/dslocal/nodes/Default/users/<name>.plist`.
- Take a manual APFS snapshot (`tmutil localsnapshot`) before any destructive lab; snapshots are immutable COW views and can be purged automatically under disk pressure — verify with `tmutil listlocalsnapshots /`.

### [[01-windows-to-macos-mental-models]] — Windows to macOS: The Mental-Model Reset

- The global menu bar belongs to the frontmost **application**, not a window — it swaps entirely on focus change.
- ⌘W closes a window; ⌘Q quits the process; ⌘H hides (process stays fully alive) — three orthogonal states with no Windows equivalent for Hide.
- Preferences are per-app plist domains under `~/Library/Preferences/`, read/written through `cfprefsd` (async write buffer) — `defaults read` returns the live cached value, not the raw file.
- The filesystem is one POSIX tree; the System volume is the cryptographically sealed SSV (read-only even as root); `/Users` is a firmlink bridging System and Data volumes. No drive letters.
- SIP restricts `/System`, `/bin`, `/usr` above root level; `~/Library` is the forensic gold mine (prefs, databases, keychains, launch agents, sandboxed containers).

### [[02-apple-ecosystem-and-history]] — The Apple Ecosystem & a History of macOS

- macOS descends directly from NeXTSTEP (Mach 2.5 + BSD 4.3 + Obj-C + AppKit); virtually every deep mechanism traces to NeXT design decisions (1988–1996).
- Darwin version = macOS marketing major − 1 (macOS 26 = Darwin 25); the Darwin version in crash logs is a reliable forensic OS identifier.
- Rosetta 2 AOT cache at `/var/db/oah/<uid>/` persists after the source x86-64 binary is deleted; first-execution timestamps survive removal — high-value malware timeline artifact.
- App distribution is binary: mandatory-sandboxed Mac App Store or notarized Developer ID (no sandbox required but Gatekeeper-enforced).
- `com.apple.quarantine` xattr and `QuarantineEventsV2` SQLite DB record download provenance even after the file is moved, renamed, or the xattr removed.

> **Check yourself:**
> 1. What are the three states a macOS app can be in that have no single Windows equivalent?
> 2. Where do preferences live on disk, and why can't you just edit the plist file directly?
> 3. What is the Darwin version number for macOS 26, and why does it appear in crash logs?
> 4. Why does the Rosetta 2 `/var/db/oah/` cache matter even after an app is deleted?

> [!success]- Answers
> 1. Running (visible), Hidden (`⌘H` — process fully alive, no windows), and Minimized (`⌘M` — window in Dock, process alive but window demoted). Windows has no native equivalent to Hide.
> 2. Preferences live in `~/Library/Preferences/<bundle-id>.plist` (and `ByHost/` for machine-scoped prefs). Direct file edits are ignored because `cfprefsd` caches values in memory and overwrites the file asynchronously — use `defaults write` or `killall cfprefsd` to flush.
> 3. Darwin 25 (macOS marketing major minus 1). It appears in crash logs and `uname -r` output, giving investigators a reliable way to identify the OS version even when `sw_vers` isn't available.
> 4. The `.aot` file's creation timestamp approximates the first execution time of the x86-64 binary. Even after the source app is deleted, this cache entry remains at `/var/db/oah/<uid>/`, providing a high-value malware timeline artifact.

---

## Part 01 — System Architecture & Internals

**Big picture:** The deep substrate — XNU kernel internals, boot chain, Apple Silicon hardware, APFS filesystem, launchd, processes/IPC, memory, security stack, metadata, and logging. This is the foundation every other Part builds on.

### [[00-darwin-and-xnu-kernel]] — Darwin & the XNU Kernel (Mach + BSD)

- XNU is a hybrid kernel: Mach (tasks, ports, VM, IPC) + BSD (POSIX, VFS, signals, sockets) + IOKit — all in the same address space.
- Every process has a dual identity: Mach task (address space + port rights) and BSD process (PID, UID/GID, FDs, signals). Different syscall families operate on each plane.
- Mach ports are unforgeable kernel-managed capability objects; holding SEND rights to another process's task port is equivalent to owning that process — Mach port attacks bypass the BSD audit trail.
- Kexts are deprecated on Apple Silicon; the modern stack is user-space System Extensions (`systemextensionsctl list` is the first security-posture command).
- `sysctl` is the kernel's self-reporting API (no root required); `ioreg -rn IOPlatformExpertDevice` exposes hardware serial via `IOPlatformSerialNumber` (SEP-sourced, cannot be spoofed).

### [[01-boot-process]] — The Boot Process — Apple Silicon & Intel

- Apple Silicon boot chain of trust: Boot ROM → LLB → LocalPolicy → iBoot → SSV root hash + Auxiliary Kernel Collection → XNU → launchd. Each step cryptographically verifies the next.
- LocalPolicy (Image4-signed by the SEP, stored in iSCPreboot) is the authoritative record of security posture (SIP status, kext policy, SSV hash); it cannot be forged and changing it requires physical presence at 1TR.
- NVRAM is **not** the SIP trust boundary on Apple Silicon — SIP lives in LocalPolicy; resetting NVRAM does NOT disable SIP.
- 1TR (long-press power) replaces all Intel startup key combos on Apple Silicon; authentication is mandatory before any policy changes.
- DFU Revive preserves data; DFU Restore erases everything. The SEP prevents any cold-boot path to FileVault keys without credentials.

### [[02-apple-silicon-soc-and-secure-enclave]] — Apple Silicon: the SoC & Secure Enclave

- Apple Silicon is a single-die heterogeneous SoC; CPU, GPU, ANE, and media engines share one unified LPDDR5/5X memory pool — no VRAM copy overhead.
- The Secure Enclave is a separate ARM processor (sepOS / L4 microkernel) with its own Boot ROM; the UID key is fused at manufacturing and never software-readable, even by sepOS itself.
- FileVault on Apple Silicon is SEP-enforced: the volume key is protected by a key derived from login password AND the hardware UID; chip-off and cold-boot attacks are defeated.
- Data Protection classes A–D determine per-file key availability by device lock state; powered-off or pre-first-unlock means only Class D data is accessible.
- Rosetta 2 AOT cache at `/var/db/oah/` persists after the source binary is deleted; creation time ≈ first execution time — high-value forensic artifact.

### [[03-apfs-deep-dive]] — APFS Deep Dive

- An APFS container pools raw blocks; all member volumes share free space dynamically. The Container Superblock (NXSB) is always readable even on encrypted volumes.
- Every on-disk APFS structure is a 4 KB object with a Fletcher-64 checksum and a monotonically increasing transaction ID (xid); writes are always copy-on-write.
- `clonefile(2)` (exposed as `cp -c`) creates O(1) file copies sharing extents — **only within a single volume**; cross-volume copies silently degrade to full data copy.
- The Sealed System Volume applies a SHA-256 Merkle tree over all system files verified at boot and at read time; a broken seal is cryptographic evidence of tampering.
- The volume group (System + Data) is stitched by firmlinks; forensic tools must analyze both volumes to reconstruct the live tree.

### [[04-filesystem-layout-and-domains]] — Filesystem Layout & Domains

- The four domains (System → Local → Network → User) define resource search priority. Malware prefers `~/Library/LaunchAgents/` (no admin) and `/Library/LaunchDaemons/` (admin, system-wide).
- `/etc`, `/var`, `/tmp` are POSIX symlinks into `/private` — always use `realpath` before string comparison.
- `~/Library` is hidden by BSD `chflags hidden`, not a leading dot; `ls -a` alone does **not** reveal it; `ls -lO` shows the flag.
- Sandboxed app preferences live in `~/Library/Containers/<bundle-id>/Data/Library/Preferences/`, **not** `~/Library/Preferences/` — a common forensic miss.
- `~/Library/Mobile Documents/` is iCloud Drive's on-disk root; `.icloud` stubs indicate evicted content; `brctl log` provides live sync events.

### [[05-launchd-and-the-launch-system]] — launchd & the Launch System

- launchd (PID 1) is the sole init, service manager, cron replacement, and XPC namespace broker; every other process descends from it.
- LaunchDaemons run as root, pre-login, no GUI. LaunchAgents run in the user's GUI session — only Agents can display windows or use the pasteboard.
- Five search domains in priority order: `/System/Library/LaunchDaemons` (Apple/SSV-sealed), `/System/Library/LaunchAgents`, `/Library/LaunchDaemons` (admin), `/Library/LaunchAgents` (admin), `~/Library/LaunchAgents` (user, no admin required).
- The override database at `/var/db/com.apple.xpc.launchd/disabled*.plist` persists enabled/disabled state independently of plist files — malware using `launchctl enable` writes here to survive plist deletion.
- Modern `launchctl` syntax: `bootstrap`/`bootout`/`kickstart`/`print` with domain specifiers (`gui/<uid>/`, `system/`); legacy `load`/`unload` is deprecated.

### [[06-processes-mach-and-xpc]] — Processes, Mach & XPC

- XPC wraps Mach ports in structured serialization, adds mandatory per-service sandboxing, and enables launchd to manage service lifetimes on demand; modern Apple apps decompose into 10–40 XPC helper processes each with minimal entitlements.
- `xpcproxy` execs over itself (POSIX_SPAWN_SETEXEC) to launch XPC helpers; all XPC helpers appear as children of launchd (PID 1) — this is normal, not an anomaly.
- For security auditing: verify code signatures and Team IDs of all running binaries; trace process ancestry to PID 1; SIP blocks DTrace from inspecting system processes.
- GCD (libdispatch) routes work items to P-cores vs. E-cores based on QoS class; a process can have 200 pending work items on 4–8 actual pthreads.

### [[07-memory-virtual-memory-and-swap]] — Memory, Virtual Memory & Swap

- Page size is **16 KB** on Apple Silicon vs. 4 KB on Intel — multiply `vm_stat` page counts by 16,384 on Apple Silicon.
- Zero free RAM is normal. Memory pressure color (green/yellow/red), not free RAM, is the meaningful health indicator.
- The kernel compressor (WKdm) runs in-kernel achieving 3–6× ratios before touching swap; swap is a last resort and is hardware-encrypted on Apple Silicon via SEP.
- Swap files live at `/System/Volumes/VM/swapfileN`; on Apple Silicon encrypted with AES Inline Engine keys held by the SEP — offline acquisition yields ciphertext only.
- Jetsam (macOS OOM killer) kills background apps silently; events are logged to `/private/var/db/jetsam/JetsamEvent-*.ips` (JSON).

### [[08-security-architecture]] — Security Architecture: SIP, Gatekeeper, TCC

- Six enforcement layers: silicon (Boot ROM + SEP) → kernel (SIP + SSV + AMFI) → userspace gate (Gatekeeper + notarization + quarantine) → privacy gate (TCC) → process boundary (sandbox + hardened runtime) → data at rest (FileVault + SEP).
- SIP is a kernel MAC policy (AMFI); on Apple Silicon, changing it also requires a LocalPolicy update (physical presence at 1TR). A machine with SIP disabled has effective root over the sealed system volume.
- Gatekeeper vets every downloaded app on first launch via `syspolicyd`; records in `/var/db/SystemPolicy` (SQLite); the quarantine xattr UUID cross-references `QuarantineEventsV2` (persists 90+ days post-deletion).
- TCC (enforced by `tccd`) controls camera, mic, Full Disk Access, screen recording; both SQLite databases are first-class forensic artifacts; system TCC.db is SIP-protected.
- FileVault on Apple Silicon is cryptographically unbreakable without credentials; shift to live acquisition, iCloud recovery key, or MDM escrow.

### [[09-spotlight-metadata-and-xattrs]] — Spotlight, Metadata & Extended Attributes

- Spotlight pipeline: `mds` (supervisor) → `mdworker_shared` (per-file extractor) → `.mdimporter` → `mds_stores` → `.Spotlight-V100` per-volume B-tree index.
- `mdfind` / `mdls` give programmatic access to the same index; `kMDItemWhereFroms`, `kMDItemLastUsedDate`, `kMDItemUseCount` persist in the index after file deletion.
- `com.apple.quarantine` is the most forensically significant xattr: flags + timestamp + source app + UUID; UUID cross-references `QuarantineEventsV2` which persists source URL/referrer for 90+ days.
- `.DS_Store` files prove which directories Finder opened and what files were present (including since-deleted files); they leak directory contents to web servers.
- Third-party Spotlight importers in `~/Library/Spotlight/` are a persistence vector.

### [[10-unified-logging-and-diagnostics]] — Unified Logging & Diagnostics

- `logd` is the single ingestion point; `.tracev3` files in `/var/db/diagnostics/Persist/` are the durable store (~30 days, ~530 MB cap). `/var/db/uuidtext/` is required alongside for format string resolution.
- Privacy redaction (`<private>`) is enforced at write time in the kernel path; the value is **never stored** and cannot be recovered even with root on a production system.
- Log levels: Default and Error/Fault always persist; Info persists conditionally; Debug is in-memory only (never flushed to `.tracev3`).
- `log stream` for live capture; `log show --predicate` for historical NSPredicate queries; `log collect` creates a portable `.logarchive`.
- `sysdiagnose` is the gold-standard evidence package: logarchive + crash reports + launchd state + NVRAM + network state + process snapshot in one tarball.

> **Check yourself:**
> 1. What is the correct APFS page size on Apple Silicon, and why does it matter for interpreting `vm_stat` output?
> 2. Name the five LaunchAgent/Daemon search domains in priority order.
> 3. Why can't you simply edit a live plist file to change a preference, and what must you do instead?
> 4. What does `<private>` in a Unified Log entry mean for a forensic investigator?
> 5. What is the forensic significance of the `QuarantineEventsV2` SQLite database surviving file deletion?

> [!success]- Answers
> 1. 16 KB on Apple Silicon (vs. 4 KB on Intel). `vm_stat` reports counts in pages, so you must multiply by 16,384 — not 4,096 — to get byte values; using the wrong page size produces numbers that are 4× too low.
> 2. In priority order: `/System/Library/LaunchDaemons` → `/System/Library/LaunchAgents` → `/Library/LaunchDaemons` → `/Library/LaunchAgents` → `~/Library/LaunchAgents`.
> 3. `cfprefsd` caches preference domains in memory and flushes writes asynchronously; a direct file edit is silently overwritten by the daemon. Use `defaults write <domain> <key> <value>`, or stop the relevant app/daemon so `cfprefsd` releases the domain first.
> 4. The value was **never stored on disk** — the redaction is enforced at write time in the kernel path. There is no recovery mechanism, even with root access. Investigators must resort to live capture (`log stream`) before the event fires, or accept the redaction as a permanent gap.
> 5. The database records the source URL, referrer, download timestamp, and app used to download — all keyed to the quarantine UUID — and persists for 90+ days after the file is deleted, the xattr is stripped, or Safari history is cleared. It can establish when and from where a file arrived even when the file itself is long gone.

---

## Part 02 — GUI Power User

**Big picture:** Mastering the visual layer — Finder, windows, menus, Spotlight, keyboard, text editing, System Settings, Quick Look, screenshots, Continuity, and accessibility as automation leverage.

### [[00-finder-mastery]] — Finder Mastery

- Column view (`⌘3`) is the fastest navigation mode for deep trees; the rightmost column shows EXIF/color-profile metadata.
- `.DS_Store` files contain filename records persisting after file deletion (historical directory contents); parseable with the `dsstore` Python library.
- `⌘⌥V` is "move paste" (cut equivalent); `⌘⇧G` accepts `~`-prefixed paths with tab completion; `Enter` renames, `⌘↓` opens.
- iCloud Desktop & Documents physically relocates those folders into `~/Library/Mobile Documents/com~apple~CloudDocs/`; Optimize Storage can evict content to 0-byte stubs.
- Smart Folders are saved Spotlight queries (`.savedSearch` XML plists in `~/Library/Saved Searches/`) — not real directories.

### [[01-window-management]] — Window Management: Spaces, Mission Control, Stage Manager

- Spaces are identified by UUID (not number); artifacts in `com.apple.spaces.plist` and `com.apple.dock.plist`.
- Disable "Automatically rearrange Spaces" and enable "Displays have separate Spaces" on multi-monitor setups — the two most impactful Spaces settings.
- Prefer `⌘H` (hide) over `⌘M` (minimize); hidden apps remain accessible via `⌘Tab`; minimized windows become second-class citizens `⌘Tab` won't restore.
- Native tiling (Sequoia+): drag-to-edge, green button menu, or `fn+Control+Arrow`; for thirds/sixths/custom, use Rectangle; yabai is the only true BSP path.
- yabai's `/tmp/yabai_$UID.*.log` and its scripting addition in `/System/Library/ScriptingAdditions/` are forensic indicators of deliberate SIP disable.

### [[02-menubar-control-center-dock]] — Menu Bar, Control Center, Notifications & the Dock

- The left menu bar is a per-focused-app contract; the right side is `NSStatusItem` injected by `SystemUIServer` (Apple) or each app's own process (third-party).
- An unsigned `.menu` bundle in the `com.apple.systemuiserver` plist `menuExtras` key is a persistence red flag.
- The notification database at `~/Library/Application Support/com.apple.notificationcenter/db2/db` is SQLite; add 978,307,200 to `delivered_date` for Unix epoch.
- The entire Dock config is writable via `defaults write com.apple.dock` + `killall Dock`; `com.apple.dock.plist` is the ground-truth artifact.

### [[03-spotlight-as-launcher]] — Spotlight as a Launcher & Everything-Box

- Spotlight indexes at `/.Spotlight-V100/Store-V2/<UUID>/store` — contains metadata for nearly every file including deleted ones.
- `mdutil -a -i off && mdutil -a -i on` is the correct response to post-upgrade index corruption or the Tahoe `mds_stores` memory-leak bug (40–60 GB RAM in early betas).
- The `spotlightknowledged` / `knowledgegraphd` layer sends anonymized query data to Apple unless disabled; disabling also kills stock quotes and currency conversion.
- Privacy exclusions in System Settings → Siri & Spotlight may be silently reset after major OS upgrades — verify after every upgrade with `mdutil -s /`.

### [[04-keyboard-shortcuts-and-customization]] — Keyboard Shortcuts & Customization

- macOS modifier hierarchy: `⌘` = app commands, `⌥` = variant, `⌃` = low-level/Emacs, `⇧` = extend/reverse. Stacking is additive.
- Every native Cocoa text field implements Emacs-style navigation (`⌃A/E/K/Y/T/D`) system-wide — the single most impactful hidden productivity feature.
- App Shortcuts pane can bind any menu command via **exact** title string match (including Unicode ellipsis `…`); silently fails if the string doesn't match.
- `hidutil` provides kernel-level HID key remapping; survives sleep but not reboot — pair with a `~/Library/LaunchAgents/` plist for persistence (also a forensic artifact location).

### [[05-text-editing-and-services]] — Text Editing & System Services

- The Cocoa text engine is universal; ~25 Emacs-style bindings work in every standard text field; VS Code, Electron, and JetBrains apps are notable exceptions.
- Smart quotes/autocorrect silently corrupt `"` characters in Cocoa fields — disable with `defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false`.
- `~/Library/KeyboardServices/TextReplacements.db` (SQLite) and `~/Library/Spelling/LocalDictionary` are forensic goldmines accumulating personal patterns and credential hints over years.
- The kill ring (`⌃K` / `⌃Y`) is separate from the system clipboard (`⌘C` / `⌘V`); `⌃K` in Terminal is intercepted by shell readline — the two systems don't cross-pollinate.

### [[06-system-settings-tour]] — System Settings — Complete Tour

- Search (`⌘F`) is the real navigation; `⌘[`/`⌘]` navigate pane history like a browser.
- Login Items & Extensions is the unified GUI for all LaunchAgents, LaunchDaemons, app extensions, and system extensions; toggling off calls `launchctl disable` — it does **not** delete the plist.
- `defaults read <domain> > before.txt` → change → `defaults read <domain> > after.txt` → `diff` is the canonical reverse-engineering technique for any setting.
- FileVault on Apple Silicon is hardware-fused via SEP; a seized powered-off Mac with FileVault is forensically opaque without credentials or recovery key.

### [[07-quick-look-and-preview]] — Quick Look & Preview

- Quick Look generators are now `.appex` bundles (not `.qlgenerator`) on macOS 15+; `.qlgenerator` bundles are silently ignored on Sequoia/Tahoe.
- The Quick Look thumbnail cache (`$(getconf DARWIN_USER_CACHE_DIR)com.apple.QuickLook.thumbnailcache/index.sqlite`) records previewed file paths with timestamps — persists after deletion or volume ejection.
- `⌘S` in Preview does **not** flatten redactions — use `File → Export as PDF` and verify with `strings` or `pdftotext`.
- `qlmanage -t -s 256 -o /tmp/ suspect-file.docx` generates a thumbnail without launching any app — safe triage for unknown files.

### [[08-screenshots-and-screen-recording]] — Screenshots & Screen Recording

- Adding `⌃` to any screenshot shortcut redirects output to clipboard instead of disk.
- A black image from `screencapture` in automation = missing TCC `kTCCServiceScreenCapture` grant (exit code 0, no error — silent failure mode).
- Screenshots dragged from the floating thumbnail leave no file artifact on disk (Unified Log records the event without a path).
- `/usr/sbin/screencapture` supports window-by-CGWindowID capture (`-l`), video recording (`-v`), and region specification (`-R x,y,w,h`).

### [[09-continuity]] — Continuity: Handoff, AirDrop, Universal Clipboard, Sidecar

- Continuity runs on three transports: BLE (discovery), AWDL (direct Wi-Fi peer sessions for AirDrop/Sidecar), and iCloud relay (Handoff, Universal Clipboard).
- AirDrop bypasses all network infrastructure (AWDL never hits the AP); the Unified Log (`com.apple.sharing`, `AirDrop` category) is the only reliable system record.
- AirDrop "Contacts Only" leaks **truncated SHA-256 hashes** of your Apple ID email/phone in BLE advertisements — reversible with precomputed tables (PrivateDrop vulnerability, unpatched at BLE layer as of 2026).
- Universal Clipboard is E2E encrypted over iCloud relay with a ~2-minute TTL; content is never stored unencrypted on Apple servers.

### [[10-accessibility-as-power-tools]] — Accessibility Features as Power Tools

- `kTCCServiceAccessibility` is the highest-privilege UI permission; unexpected grants (especially path-based non-bundle-ID entries) are tier-one malware indicators.
- Full Keyboard Access (`⌃F1`) + `⌃F2/F3/F4/F8` enables genuine keyboard-first macOS navigation without third-party tools.
- Voice Control custom commands stored as `.voicecontrolcommands` XML plists in `~/Library/Application Support/VoiceControl/Commands/`.
- `Reduce Motion` and `Reduce Transparency` are as much focus/performance preferences as accessibility accommodations — many professionals enable both.

> **Check yourself:**
> 1. What is the forensic significance of `.DS_Store` files?
> 2. Why should you prefer `⌘H` over `⌘M` in a keyboard-driven workflow?
> 3. What Quick Look generator format does macOS 15+ require, and what happens to the old format?
> 4. How do you detect a missing TCC screen-capture grant when `screencapture` returns exit code 0?
> 5. What does AirDrop "Contacts Only" leak in BLE advertisements and why is it significant?

> [!success]- Answers
> 1. `.DS_Store` files contain records of filenames that were present in the directory — including files since deleted — proving which files Finder rendered in that folder. They also leak directory contents to web servers when present in web roots and are parseable with the `dsstore` Python library.
> 2. Hidden apps (`⌘H`) remain fully alive and are reachable via `⌘Tab`; minimized windows (`⌘M`) drop into the Dock's window section and are not restored by `⌘Tab`, making them second-class citizens in a keyboard-driven workflow.
> 3. macOS 15+ requires `.appex` bundle-based Quick Look generators. The legacy `.qlgenerator` format is silently ignored — it produces no error but generates no thumbnail or preview.
> 4. The result is a solid black image — `screencapture` exits 0 with no error message when the `kTCCServiceScreenCapture` TCC grant is missing. You must inspect the output image itself to detect the failure.
> 5. "Contacts Only" leaks truncated SHA-256 hashes of your Apple ID email address and phone number in BLE advertisements. These hashes can be reversed using precomputed rainbow tables (the PrivateDrop vulnerability), allowing a nearby attacker to identify you as an AirDrop target even with the privacy setting enabled.

---

## Part 03 — The Command Line

**Big picture:** The macOS CLI layer — shell internals, Unix commands, macOS-specific tooling, plist manipulation, text processing, permissions, networking, process management, SSH, scripting, and Homebrew.

### [[00-terminal-and-shells]] — Terminal & Shells

- macOS Terminal.app uses the PTY model (kernel pseudoterminal master/slave pair); the shell runs in the slave; PTY line discipline handles echo and cooked-mode processing.
- zsh has been the default shell since Catalina; bash is frozen at 3.2 (GPLv3 licensing) and is **not** updated by Apple.
- `/etc/paths` and `/etc/paths.d/` snippets are processed by `path_helper` on login; files added to `/etc/paths.d/` persist across reboots — a known persistence vector.
- Shell startup order: `.zprofile` (login), `.zshrc` (interactive), `.zshenv` (always, including scripts) — putting `brew shellenv` in `.zshrc` breaks GUI app subshells.

### [[01-zsh-deep-dive]] — Zsh Deep Dive

- `compinit` must be called **after** all `fpath` entries are set; calling it before drops those completions silently.
- Glob qualifiers like `*(om[1])` (newest file) and `**/*(u0WX.)` (world-writable root-owned files) enable powerful one-liners without `find`.
- `EXTENDED_HISTORY` + `SHARE_HISTORY` gives timestamped history shared across all concurrent sessions; `~/.zsh_history` becomes a forensic audit trail.
- `/etc/zshenv` is sourced for every zsh process including non-interactive scripts — a high-value persistence vector.

### [[02-shell-fundamentals]] — Shell Fundamentals: Pipes, Redirection, Jobs

- `2>&1` is evaluated right-to-left, so order matters; `dup2()` before `execve()` is how the shell wires redirections.
- Pipes use kernel ring buffers; a writer blocks when full, a reader blocks when empty — explains deadlocks in bidirectional pipe chains.
- `disown` + `nohup` together survive shell exit and are used to daemonize callbacks.
- `xargs -P N` parallelizes across N workers; combined with `find -print0 | xargs -0` handles filenames with spaces safely.

### [[03-essential-unix-commands]] — Essential Unix Commands

- BSD vs GNU divergence: `grep -P` (PCRE) does not exist on BSD grep; `sed -i` requires an empty string argument (`sed -i ''`) on macOS — the most common cross-platform footgun.
- macOS files have a four-layer metadata stack: POSIX mode bits → BSD file flags → xattrs → POSIX ACLs; `ls -le@O` shows all four.
- `cp -c` uses `clonefile(2)` CoW on APFS — instant, shares blocks until either copy is modified; `du` double-counts clones.
- `ditto` preserves all macOS metadata including resource forks, xattrs, and ACLs; `zip` loses resource forks — always use `ditto` for macOS-to-macOS copies.
- APFS birth time is available via `mdls -name kMDItemFSCreationDate`; `find -newer` uses only mtime.

### [[04-macos-specific-cli-tools]] — macOS-Specific CLI Tools

- `system_profiler SPInstallHistoryDataType` produces the complete software install timeline including OS updates — a critical forensic artifact.
- `defaults` and `plutil` operate on the preferences subsystem; never edit a live plist directly — use `defaults write` or restart the daemon.
- `caffeinate` prevents sleep for the duration of a command; `pmset -g assertions` shows what is currently blocking sleep.
- The macOS security CLI toolbox: Gatekeeper (`spctl`), code signing (`codesign`), SIP (`csrutil`), FileVault (`fdesetup`), LocalPolicy (`bputil`), MDM profiles (`profiles`), NVRAM (`nvram`).

### [[05-defaults-and-plists]] — Defaults & Plists

- Three plist wire formats: XML, binary (`bplist00` magic bytes), JSON; `plutil -convert` moves between them.
- `cfprefsd` caches preferences; writing directly to plist files while the daemon has them cached produces no effect — always use `defaults write` or `killall cfprefsd`.
- `PlistBuddy Set` **silently no-ops** when the key doesn't exist — always use `Set … || Add … string …` to guarantee the key is present.
- ByHost preferences in `~/Library/Preferences/ByHost/` are scoped to the machine UUID — a forensic indicator of which physical machine authored the plist.

### [[06-text-processing]] — Text Processing: grep, sed, awk, jq

- BSD grep lacks PCRE (`-P`); use `grep -E` (ERE) or install ripgrep/Homebrew grep for PCRE.
- `sed -i ''` is the macOS idiom for in-place edit; GNU `sed -i` (no second argument) errors on BSD.
- `jq` is the authoritative JSON pipeline tool: `.[] | select(.x == "y") | .field` chains filters; `@csv` and `--arg` enable structured output.
- `comm -13 <(sort file1) <(sort file2)` produces lines only in file2 — the standard manifest diffing pattern.
- `rg` (ripgrep) is the daily-driver replacement for grep: faster, respects `.gitignore`; `rg --json` enables structured processing.

### [[07-files-permissions-acls-flags]] — Files, Permissions, ACLs & Flags

- VFS evaluation order: root bypass → BSD flags → ACLs → POSIX mode bits; then SIP and TCC operate entirely above VFS.
- BSD file flags (`chflags uchg`) make a file immutable to everyone including root; `schg` (system immutable) requires recovery mode to clear.
- `EPERM` ("Operation not permitted") = flags/SIP/TCC; `EACCES` ("Permission denied") = ACL/POSIX — the errno distinguishes the blocking layer.
- `find . -perm -4000` finds all setuid binaries — mandatory audit after any software installation on a security-conscious system.
- `dscl .` is the authoritative user/group database; `/etc/passwd` is a compatibility shim.

### [[08-networking-cli]] — Networking CLI

- macOS network config lives in SCDynamicStore: `Setup:` (persistent) and `State:` (volatile); `scutil` queries both; `/etc/resolv.conf` is a lie on macOS.
- DNS is served by `mDNSResponder` using SCDynamicStore; `dscacheutil -flushcache` flushes the mDNS cache.
- `airport` was removed in Sonoma 14.4; use `wdutil` for WiFi state/diagnostics.
- `lsof -i TCP -s TCP:LISTEN` is the primary listener inventory; combine with `lsof -p <pid>` to attribute sockets to processes.
- Interface names differ by architecture: `en0` is WiFi on Apple Silicon but Ethernet on Intel; `utun` interfaces are VPN tunnels.

### [[09-process-management-cli]] — Process Management CLI

- BSD `ps` syntax uses no leading dash (`ps aux`, not `ps -aux`).
- `taskpolicy -b` pins a process to E-cores on Apple Silicon; `nice`/`renice` are cosmetic on Apple Silicon — the scheduler ignores them in favor of QoS.
- `fs_usage` is DTrace-backed and requires SIP disabled or proper entitlements; primary tool for diagnosing I/O hangs.
- `footprint` measures what Activity Monitor calls "Memory" (physical footprint); RSS from `ps` overstates by counting shared libraries once per process.
- Before `kill -9` on a KeepAlive launchd service, run `launchctl bootout` first — otherwise launchd immediately respawns.

### [[10-ssh-and-remote-access]] — SSH & Remote Access

- Add `UseKeychain yes` and `AddKeysToAgent yes` to `~/.ssh/config` to persist passphrases in the macOS Keychain across reboots.
- `~/.ssh/known_hosts` records all SSH hosts connected to — a forensic artifact showing the machine's SSH connection history.
- `~/.ssh/authorized_keys` modification timestamp is the primary indicator of when SSH-based persistence was established.
- ProxyJump (`-J`) replaces legacy `ProxyCommand nc %h %p` for bastion-host chaining; `-D 1080` creates a SOCKS5 proxy.

### [[11-scripting]] — Scripting: bash, AppleScript, JXA, Shortcuts CLI

- Always `#!/usr/bin/env bash` with `set -euo pipefail` and `IFS=$'\n\t'`; bash 3.2 (no associative arrays, no `mapfile`, no `${var^^}`).
- AppleScript communicates via Apple Events (Mach IPC); `sdef` extracts an app's scripting dictionary.
- JXA runs in V8 via the OSA subsystem; `ObjC.import('Foundation')` bridges to Cocoa and is a known LOLBin path.
- `osascript` activity appears in the Unified Log under `com.apple.osascript`; `~/Library/Application Scripts/` is both a legitimate and adversarial persistence location.

### [[12-homebrew-and-package-management]] — Homebrew & Package Management

- Apple Silicon Homebrew at `/opt/homebrew`; Intel at `/usr/local`; activate with `eval "$(brew shellenv)"` in `~/.zprofile`.
- `brew services start` copies a launchd plist into `~/Library/LaunchAgents/`; malware sometimes uses `.mxcl`-style naming to blend in.
- A Brewfile is machine-state-as-code: `brew bundle dump` captures; `brew bundle install` reproduces; `brew bundle cleanup --force` enforces.
- `brew leaves` shows deliberate installs; `brew autoremove` prunes orphan dependencies.

> **Check yourself:**
> 1. What is the macOS `sed` in-place edit idiom and why does the GNU form fail?
> 2. What does `EPERM` vs. `EACCES` tell you about which permission layer is blocking an operation?
> 3. Why does `/etc/resolv.conf` not reflect the true DNS configuration on macOS?
> 4. What must you do before `kill -9`ing a KeepAlive launchd service, and why?
> 5. What forensic artifact does `~/.ssh/authorized_keys` modification timestamp reveal?

> [!success]- Answers
> 1. Use `sed -i ''` (empty string as the backup suffix argument). BSD `sed` requires the backup suffix as a separate argument; GNU `sed` treats `-i` as an option that can be attached directly with no argument. On macOS, `sed -i` (GNU form, no argument) is a syntax error.
> 2. `EPERM` ("Operation not permitted") means a BSD flag (`chflags uchg`), SIP, or TCC is blocking the operation — layers above POSIX. `EACCES` ("Permission denied") means an ACL or POSIX mode bit denied access — the standard Unix permission layer.
> 3. DNS on macOS is served by `mDNSResponder` using SCDynamicStore, which supports per-domain resolvers, split DNS, and VPN overrides. `/etc/resolv.conf` is written for legacy compatibility but is not the actual resolver configuration. Use `scutil --dns` or `dscacheutil -q host` for OS ground truth.
> 4. Run `launchctl bootout gui/<uid>/<service-label>` (or `launchctl unload`) first to remove the job from launchd's job table. If you `kill -9` while the job is still registered as KeepAlive, launchd will immediately respawn it — the kill has no lasting effect.
> 5. The modification timestamp of `~/.ssh/authorized_keys` indicates when SSH-based persistence was established on the machine — i.e., when an attacker (or administrator) added a public key to enable password-less SSH access.

---

## Part 04 — Maintenance, Backup & Recovery

**Big picture:** Keeping the system healthy — Time Machine internals, backup strategy, APFS management, recovery modes, Migration Assistant, troubleshooting methodology, performance diagnosis, and update internals.

### [[00-time-machine-internals]] — Time Machine Internals

- Time Machine has two independent tiers: ephemeral APFS local snapshots on the source volume (hourly, ~24h, purgeable) and durable destination backups using APFS clones (direct-attach) or `.sparsebundle` band files (network).
- Local snapshots have zero initial overhead (CoW pins the B-tree root); they appear as purgeable space to `df` and can be reclaimed under pressure.
- Network `.sparsebundle` `Info.plist` records the source Mac's ComputerName and primary Ethernet MAC — a forensic attribution artifact.
- Encrypted TM backup keys live on the destination disk (not the SEP) — transferable and brute-forceable offline if the passphrase is weak. An **unencrypted** TM drive is immediately browseable on any Mac without credentials.
- Thinning policy (hourly 24h → daily 1 month → weekly forever); a destination consistently too small will eventually contain only one backup — a silent failure mode.

### [[01-backup-strategies]] — Backup Strategies & Tools (3-2-1, CCC, SuperDuper, restic)

- The 3-2-1 rule is the floor: 3 copies, 2 media types, 1 offsite. A single TM drive next to the Mac satisfies zero of these for disaster scenarios.
- iCloud Drive, Photos, and Keychain are **sync services**, not backup — deletions and ransomware propagate in near real time; iCloud does not count as the offsite copy.
- CCC on Apple Silicon produces a data clone, not a bootable clone; the SSV seal can only be re-applied by Apple's tools.
- restic: mandatory AES-256 encryption, content-addressed deduplication, multi-backend; `restic check --read-data` is the only way to verify pack-file integrity — must run quarterly.
- Backup drives always mounted are in the same failure domain as the Mac; ransomware can reach them.

### [[02-disk-utility-and-apfs-management]] — Disk Utility & APFS Management

- APFS hierarchy: physical disk → GPT partition → APFS container → APFS volumes; all volumes in a container share free space dynamically — no repartitioning needed.
- Never delete Preboot or Recovery volumes from a startup container.
- Secure erase on SSDs is effectively impossible via software (wear leveling/over-provisioning); correct approach is FileVault-from-day-one + key destruction, or "Erase All Content and Settings" on Apple Silicon.
- `diskutil mount readOnly` sets `MNT_RDONLY` at mount time — the macOS software equivalent of a write-blocker; always mount forensic evidence volumes this way.
- `hdiutil` sparse images with AES-256 encryption are the macOS-native encrypted vault; `hdiutil verify` checks the embedded SHA-256 checksum.

### [[03-recovery-and-reinstall]] — Recovery Mode & Reinstalling macOS

- Apple Silicon has three recovery tiers: Paired Recovery (power-button hold, full features), Fallback Recovery (double-press-hold, factory OS, cannot change LocalPolicy), DFU/Internet (requires second Mac + Apple Configurator 2).
- Startup Security Utility edits the `LocalPolicy` stored in the SEP — requires physical presence; cannot be made remotely.
- Erase All Content & Settings (EACS) destroys the AES volume key in the SEP's effaceable storage in under 2 minutes — correct modern wipe, not Disk Utility + reinstall.
- DFU Revive preserves data; DFU Restore erases everything — always attempt Revive first; use a plain USB-C data cable (not Thunderbolt 3) for DFU.
- Migration Assistant is **not** forensically neutral — it carries LaunchAgents, logs, shell rc files, and metadata from the source.

### [[04-boot-modes]] — Boot Modes: Safe, Recovery, DFU & More

- Apple Silicon Safe Mode: Shift-click in the startup picker (not Shift at power-on); sets `boot-safe=1` to prevent AuxKC from loading.
- Single-user mode (⌘S) does not exist on Apple Silicon; the replacement is Terminal in recoveryOS.
- Target Disk Mode (⌘T) is replaced by Share Disk on Apple Silicon — operates at the SMB filesystem layer, **not** block level; APFS metadata and deleted-file sectors are inaccessible (forensic regression).
- `nvram system-id` persists across OS reinstalls and EACS; reset only by DFU Restore — key artifact distinguishing a reinstall from a full wipe.

### [[05-migration-assistant]] — Migration Assistant — Moving to a New Mac

- Migrate during Setup Assistant (first boot) to avoid the duplicate-account problem; preserves original username, UID (usually 501), and home directory name.
- FileVault is **off** after migration and must be explicitly re-enabled with a new recovery key; `systemmigrationd` writes decrypted data to the destination.
- `/Library/SystemMigration/History/Migration-<UUID>/MigrationAttempt.plist` records `SourceComputerName`, `SourceSystemVersion`, `MigrationStart`/`MigrationEnd` — the definitive forensic provenance artifact.
- `com.apple.quarantine` xattrs on migrated apps carry the **original download timestamp from the source machine** — the hex timestamp requires adding 978,307,200 to convert CFAbsoluteTime to Unix epoch.

### [[06-troubleshooting-methodology]] — Troubleshooting Methodology

- Work the diagnostic ladder in order: Hardware → Firmware → OS/Kernel → System Services → User Account → Application. Stop at the layer isolating the symptom.
- Safe Mode (blocks AuxKC, login items, non-Apple fonts; does **not** repair disk) is the fastest layer 2/3 boundary test; a fresh user account is the fastest layer 4/5 test.
- `cfprefsd` must be killed after manipulating plist files — it will re-write stale data within seconds.
- TCC, not POSIX, is the common permission blocker when a user-owned file is inaccessible to an app; diagnose with `tccutil`, TCC.db SQLite query, and `com.apple.TCC` log predicate.
- Kernel panics are readable forensic documents — the AuxKC kext list in the backtrace usually identifies the responsible third-party component.

### [[07-performance-diagnosis]] — Performance Diagnosis

- Match the instrument to the bottleneck: beachball → `spindump`/`sample`; CPU saturation → `powermetrics`; memory leak → `vm_stat` + `footprint`; disk write storm → `fs_usage` + `iostat`; thermal throttle → `powermetrics --samplers smc`.
- `kernel_task` at high CPU is macOS intentionally consuming cycles to raise chip temperature so firmware can throttle power — root cause is always thermal, not a `kernel_task` bug.
- `powermetrics` is the single most informative tool on Apple Silicon: per-core CPU frequency, power draw in watts, die temperature, per-cluster utilization.
- Auto-generated spindumps in `/Library/Logs/DiagnosticReports/` for processes unresponsive >20 seconds survive reboots — invaluable post-hoc artifacts.

### [[08-software-update-internals]] — Software Update & OS Install Internals

- macOS updates operate on two independent tracks: SSV snapshot updates (full OS, requires reboot through UpdateBrain) and Cryptex replacement (Safari, WebKit, dyld caches — no full reboot required).
- The UpdateBrain — not the running OS — installs the update during a special pre-boot phase; if sealing fails, the prior snapshot is the automatic fallback.
- Background Security Improvements (Tahoe 26.1+) install automatically regardless of MDM deferrals and leave no `(a)` version-string indicator — check `stat /System/Cryptexes/App.dmg` timestamps, not just `sw_vers`.
- macOS is forward-only; the only downgrade path is an IPSW restore via DFU + Apple Configurator 2 (erases everything).
- `softwareupdate --fetch-full-installer` downloads the complete ~13–15 GB installer to `/Applications/`.

> **Check yourself:**
> 1. What is the difference between a Time Machine local snapshot and a destination backup, and where do each live?
> 2. Why is "Erase All Content and Settings" the correct modern wipe on Apple Silicon rather than Disk Utility erase + reinstall?
> 3. How do you match the right diagnosis tool to a beachball vs. a thermal throttle vs. a disk I/O hang?
> 4. What forensic artifact in `/Library/SystemMigration/` proves a machine's history?
> 5. Why may `sw_vers` not accurately reflect the current security posture on macOS 26 Tahoe?

> [!success]- Answers
> 1. Local snapshots are ephemeral APFS CoW snapshots on the source volume itself (hourly, ~24h retention, purgeable under disk pressure). Destination backups are durable copies on a separate drive — either APFS clones (direct-attach) or `.sparsebundle` band files (network). Local snapshots appear as purgeable space in `df`; destination backups persist independently of the source volume's health.
> 2. EACS destroys the AES volume encryption key in the SEP's effaceable storage in under 2 minutes — all NAND blocks become permanently inaccessible without overwriting a single byte. Disk Utility erase + reinstall does not destroy the SEP-held key hierarchy with the same cryptographic guarantees and takes far longer.
> 3. Beachball → `spindump` or `sample` (identifies the stuck thread's call stack). Thermal throttle → `powermetrics --samplers cpu_power,thermal` or `powermetrics --samplers smc` (shows die temperature and frequency). Disk I/O hang → `fs_usage` (DTrace-backed syscall trace) combined with `iostat`.
> 4. `/Library/SystemMigration/History/Migration-<UUID>/MigrationAttempt.plist` records `SourceComputerName`, `SourceSystemVersion`, `MigrationStart`, and `MigrationEnd` — the definitive forensic record of which Mac this data came from and when it was migrated.
> 5. Background Security Improvements (Tahoe 26.1+) install automatically via Cryptex replacement without a full OS reboot and without incrementing the version string shown by `sw_vers`. Check `stat /System/Cryptexes/App.dmg` timestamps — not just `sw_vers` — to determine the actual security content applied.

---

## Part 05 — Security, Privacy & Forensics

**Big picture:** The macOS threat model end-to-end — defense-in-depth architecture, FileVault encryption internals, TCC forensics, the full artifact ecosystem, Keychain secrets, network security, malware persistence, and the hardening playbook.

### [[00-the-security-model]] — The macOS Security Model

- Concentric rings: Boot ROM → SEP/LocalPolicy → SSV → SIP → Code Signing/AMFI → Gatekeeper/Notarization → Sandbox/Entitlements → TCC → XProtect/Remediator → FileVault → Lockdown Mode.
- `QuarantineEventsV2` and both TCC databases are the highest-priority first-response forensic artifacts on any suspect Mac.
- SIP also governs ptrace/dtrace attachment to protected processes, entitlement validation, NVRAM write protection, and KEXT loading policy — not merely path protection.
- XProtect Remediator runs proactive weekly YARA scans independently; its absence from Unified Log for weeks is itself an indicator of daemon tampering.
- Apple Silicon PAC + PPL + CTRR make runtime kernel exploitation significantly more expensive; return addresses are cryptographically signed.

### [[01-filevault-and-encryption]] — FileVault & Encryption Internals

- On Apple Silicon, the Data volume is **always** encrypted at the hardware layer regardless of FileVault state; enabling FileVault changes only the key-release policy (auto-unlock vs. password-gated).
- Key hierarchy: hardware UID → xART anti-replay token → VEK → one or more KEKs. No single secret is sufficient without the specific SoC die.
- Cryptographic erase is instantaneous: the SEP destroys the VEK, rendering all NAND blocks permanently inaccessible with zero overwrite passes.
- Cold acquisition of a powered-off Apple Silicon Mac without the password or PRK yields only ciphertext; live acquisition of a logged-in unlocked machine is the operative forensic path.
- Encrypted DMGs and sparsebundles are software-only constructs (not SEP-backed); a memory dump of a Mac with a mounted encrypted DMG may yield the image encryption key.

### [[02-tcc-and-privacy]] — TCC & Privacy Internals

- TCC is enforced exclusively by `tccd`; both databases are SIP-protected — `tccutil` is the only sanctioned non-GUI mutation path.
- Every access produces a row: service name, client bundle ID, `auth_value` (0=denied, 2=allowed, 3=limited), `auth_reason` (6=MDM/PPPC silent grant), code-signing blob, Unix timestamp.
- `auth_reason=6` on a personally-owned machine means an MDM profile silently granted access — highly suspicious on consumer hardware.
- The `expired` table in TCC.db retains metadata of revoked grants — authorization history frequently overlooked by investigators.
- Screen Recording cannot be pre-granted via MDM PPPC and requires monthly user reconsent in macOS 15+.

### [[03-forensic-artifacts]] — Forensic Artifacts on macOS

- Always copy SQLite databases before querying — SQLite creates WAL sidecar files even on SELECT.
- KnowledgeC.db (`/app/inFocus`, `/device/locked`, `/display/isBacklit` streams) reconstructs minute-by-minute user presence — directly rebuts "I wasn't at my desk" defenses.
- `QuarantineEventsV2` outlives the file: records downloads ~90 days, survives file deletion, xattr stripping, and Safari history clearing.
- Three epoch systems: Unix (1970), Apple Absolute (2001, +978,307,200), WebKit/Chrome (1601, +microseconds) — mixing them produces timestamps 30+ years off.
- FSEvents logs every path touched including files created and deleted in the same session; REMOVE events on inconsistent paths are anti-forensics indicators.

### [[04-keychain-and-secrets]] — Keychain & Secrets Management

- Two Keychain tiers: legacy file-based (`login.keychain-db`, password-derived AES key) and modern Data Protection (`keychain-2.db`, SEP-backed class keys that never leave the SEP offline).
- Item metadata (service name, account, creation/modification dates, ACL trusted-app list) is accessible without the login password — a rich forensic source even on a locked machine.
- The `tombstones` table in `keychain-2.db` retains records of deleted items with timestamps — a credential-activity timeline revealing VPN configs, mail accounts, and browser logins long after removal.
- A path match with a hash mismatch in the ACL trusted-app list = binary was replaced (detectable and distinguishable from a normal app update).
- For CI/CD: always use `security find-generic-password -w` for scripted retrieval; never embed secrets in env exports or command-line arguments.

### [[05-firewall-and-network-security]] — Firewall & Network Security

- macOS ships two separate firewalls: the Application Firewall (inbound only, per-app, code-signature-aware) and pf (stateful packet filter); **neither** handles outbound connections by process identity.
- Outbound per-process control requires a NetworkExtension content filter (LuLu or Little Snitch); LuLu's `rules.json` records every prompted outbound connection with process path, signing ID, remote IP, and timestamp.
- Always modify pf via named anchors appended to `/etc/pf.conf`, never overwriting it.
- Encrypted DNS via `.mobileconfig` is the highest-leverage privacy control; verify by confirming no port-53 traffic with `tcpdump`.
- iCloud Private Relay protects Safari web traffic and system DNS only — CLI tools, curl, and third-party apps bypass it entirely.

### [[06-malware-xprotect-persistence]] — Malware, XProtect & Persistence

- XProtect fires **only at quarantine-check time**; stripping `com.apple.quarantine` with `xattr -d` bypasses both Gatekeeper and XProtect.
- The 2024–2026 dominant threat is infostealers (AMOS/Atomic, Banshee, Poseidon) that execute, exfiltrate Keychain/browser/crypto-wallet data, and exit in under 60 seconds — no persistence left; hunt network connections and Keychain access timestamps instead.
- The persistence taxonomy: LaunchAgents/Daemons (three domains), BTM login items, config profiles, shell configs (`~/.zshrc`/`.zprofile`/`.zshenv`), login/logout hooks, cron jobs, periodic scripts, authorization plugins, dylib hijacking, kernel extensions, browser extensions.
- `sfltool dumpbtm` is the authoritative way to enumerate BTM-registered background items; `notified: 0` entries and URLs under `/tmp/` or `/var/folders/` are red flags.
- Ghost persistence (LaunchAgent plist present, referenced binary deleted) = evidence of partially-cleaned malware.

### [[07-hardening-playbook]] — Privacy & Security Hardening Playbook

- Highest-leverage first controls: FileVault ON, strong password (≥14 chars), separate admin and standard user accounts, Full Security firmware policy, auto-login OFF, outbound firewall (LuLu).
- iCloud Advanced Data Protection (ADP) extends E2E encryption to 25 iCloud categories; without it, a lawful demand or Apple infrastructure compromise can expose iCloud Backup, Photos, Notes, and Drive.
- TCC audit quarterly: query both TCC databases for `kTCCServiceSystemPolicyAllFiles`, `kTCCServiceAccessibility`, and `kTCCServiceScreenCapture` grants; revoke anything unrecognized with `tccutil reset`.
- macOS Security Compliance Project (NIST mSCP, `github.com/usnistgov/macos_security`) generates audit scripts, fix scripts, and MDM profiles aligned to CIS Benchmarks and NIST 800-53.
- A backup continuously writable from the running OS is reachable by ransomware; airgap strategy requires a physically disconnected drive or write-protected versioned cloud backup.

> **Check yourself:**
> 1. What does `auth_reason=6` mean in the TCC database, and why is it suspicious on a consumer Mac?
> 2. Why does stripping `com.apple.quarantine` with `xattr -d` bypass XProtect?
> 3. What is the forensic significance of the `tombstones` table in `keychain-2.db`?
> 4. How do you detect an infostealer that leaves no persistence mechanism?
> 5. Why is encrypting a Time Machine backup not equivalent to using the SEP for key protection?

> [!success]- Answers
> 1. `auth_reason=6` means the TCC grant was made silently via MDM PPPC (Privacy Preferences Policy Control) profile, bypassing the user consent dialog. On a personally-owned consumer Mac with no MDM enrollment, this is highly suspicious and may indicate a rogue MDM profile installed as part of a compromise.
> 2. XProtect fires only at quarantine-check time (when a quarantined file is first launched via Gatekeeper). Removing the `com.apple.quarantine` xattr causes the OS to treat the file as if it was never downloaded — no quarantine check occurs, and XProtect never gets the opportunity to scan it.
> 3. The `tombstones` table retains metadata of deleted Keychain items — service name, account, creation/modification timestamps, and ACL — after the item itself is removed. This creates a credential-activity timeline showing VPN configs, mail accounts, and browser logins that were present and then deleted, which investigators frequently overlook.
> 4. Hunt for network connections (outbound C2 contact) and Keychain access timestamps in the Unified Log (`com.apple.securityd` predicate) rather than for persistent files. The dominant 2024–2026 infostealer pattern (AMOS/Banshee/Poseidon) executes, exfiltrates, and exits in under 60 seconds leaving no LaunchAgent or other persistence artifact.
> 5. Time Machine backup encryption uses a passphrase-derived key stored on the destination disk — it is transferable, brute-forceable offline if the passphrase is weak, and not backed by hardware. The SEP holds keys in an ARM co-processor with its own Boot ROM and UID fused at manufacturing; keys never leave the SEP and cannot be extracted even with physical chip-off access.

---

## Part 06 — Automation & Productivity

**Big picture:** Automating macOS at every layer — Automator workflows, Shortcuts, AppleScript/JXA, launchd personal automation, Hazel/Keyboard Maestro rule engines, Raycast/Alfred launchers, and text expansion/clipboard managers.

### [[00-automator]] — Automator: No-Code Glue Layer

- Eight document types each with a fixed on-disk location and invocation mechanism; knowing the paths is essential for automation audits and forensic persistence checks.
- Every `.workflow` package contains `document.wflow` (binary plist of the action graph) inspectable with `plutil -convert xml1`.
- Shell scripts in Automator run with a stripped PATH (`/usr/bin:/bin:/usr/sbin:/sbin`); always prepend `/opt/homebrew/bin` or use absolute paths for Homebrew tools.
- Quick Actions install to `~/Library/Services/`; Folder Actions persist via `com.apple.FolderActionsDispatcher.plist`.

### [[01-shortcuts-app-and-cli]] — The Shortcuts App & `shortcuts` CLI

- Every shortcut is a binary plist in `~/Library/Shortcuts/` with a `WFWorkflowActions` array — fully recoverable as a forensic artifact even after GUI deletion.
- The `shortcuts` CLI (`list`, `run`, `view`, `sign`) enables automation from launchd or shell; `--input-path` takes a filesystem path (not stdin), so a temp-file bridge pattern is required for piped input.
- `ShortcutsDatabaseSQL.db` records run history with timestamps using Core Data's Mac Absolute epoch (add 978,307,200 for Unix epoch).
- Shortcuts beats AppleScript for cross-device portability; AppleScript wins for deep GUI scripting of scriptable apps with full dictionary access.

### [[02-applescript-and-jxa]] — AppleScript & JXA

- Apple Events is a typed IPC protocol (`AEDesc` messages with four-char class/ID codes); apps resolve object specifiers against their live in-memory object graph at dispatch time.
- Choose AppleScript for dictionary-heavy app driving; choose JXA when you need real JS data structures, Foundation access via `ObjC.import()`, or `NSTask` for subprocess control.
- `System Events` has two personalities: plist/file scripting and GUI scripting (`tell process "AppName"` via the AXUIElement tree) for apps with no scripting dictionary.
- Every permission grant is recorded in TCC databases: `kTCCServiceAppleEvents` for Apple Events, `kTCCServiceAccessibility` for GUI scripting.
- Compiled `.scpt` files are bytecode; always version-control the `.applescript` source; use `osadecompile` to recover source from binaries found during investigations.

### [[03-launchd-personal-automation]] — launchd for Personal Automation

- Personal LaunchAgent plists live in `~/Library/LaunchAgents/`; modern management: `bootstrap`, `bootout`, `kickstart`, `print`.
- `StartCalendarInterval` fires missed ticks after sleep; `StartInterval` does not — always prefer `StartCalendarInterval` for time-sensitive jobs on laptops.
- launchd jobs get a minimal PATH; always set `EnvironmentVariables.PATH` in the plist or hardcode absolute paths — responsible for the majority of "works in terminal, fails in launchd" failures.
- Never use `~` or `$HOME` in plist values — launchd does not invoke a shell to expand them.

### [[04-hazel-and-keyboard-maestro]] — Rule Engines: Hazel & Keyboard Maestro

- Hazel runs as `HazelHelper`, a persistent FSEvents consumer registered via launchd — catches events across sleep cycles.
- Condition evaluation order matters: cheapest conditions first (name, extension) to short-circuit before expensive ones (Spotlight content search); Hazel stops evaluating further rules once a Move action runs.
- Keyboard Maestro Engine intercepts input via `CGEventTap`; requires Accessibility permission — losing it silently breaks all triggers.
- Hazel's `History.db` and KM's `Engine.log` are high-value forensic artifacts showing exactly what automation ran, on what files, with timestamps.

### [[05-launchers-raycast-alfred]] — Launchers: Raycast & Alfred

- Both register global hotkeys via `CGEventTapCreate`; both require Accessibility permission — losing it silently breaks all hotkey and injection features.
- Raycast script commands: any executable with `@raycast.*` metadata comments in a registered directory; `@raycast.mode` controls presentation.
- Alfred Script Filter: workflow node that re-runs a script per keystroke and renders its JSON output as a live results list.
- Both store clipboard history in **unencrypted SQLite databases** — Raycast at `~/Library/Application Support/com.raycast.macos/databases/`; Alfred at `clipboard.alfdb` — high-value forensic artifacts.

### [[06-text-expansion-and-clipboard]] — Text Expansion & Clipboard Managers

- macOS built-in Text Replacements are silently ignored in Electron apps, Chrome/Firefox web forms, and Terminal; for cross-app reliability, use Espanso with the clipboard backend.
- Espanso's shell variable type (`type: shell`) makes any CLI tool available as a snippet at keystroke time; exclude Terminal and iTerm2 via `exclude_apps` to prevent trigger collisions.
- Clipboard history databases (`TextReplacements.db`, `Maccy/Storage.sqlite`, Raycast databases) are plaintext, timestamped, and frequently overlooked in macOS forensic checklists — can surface passwords, API tokens, and staged credentials.
- Plain-text paste (`⌘⌥⇧V` / "Paste and Match Style") is a zero-install solution available in any Cocoa app.

> **Check yourself:**
> 1. Why do shell scripts inside Automator workflows fail to find Homebrew tools, and how do you fix it?
> 2. What is the difference between `StartCalendarInterval` and `StartInterval` in a launchd plist?
> 3. Where does Raycast store its clipboard history, and why does this matter forensically?
> 4. Which TCC permission does Keyboard Maestro Engine require, and what symptom appears silently when it is lost?
> 5. When should you choose JXA over AppleScript for automation?

> [!success]- Answers
> 1. Automator shell scripts run with a stripped PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) that does not include `/opt/homebrew/bin`. Fix by prepending `/opt/homebrew/bin` to the PATH at the top of the script, or by using absolute paths (e.g. `/opt/homebrew/bin/jq`) for any Homebrew-installed tools.
> 2. `StartCalendarInterval` fires at a wall-clock time and catches up missed ticks after the machine wakes from sleep. `StartInterval` fires every N seconds of system uptime and silently skips ticks that occurred while the machine was asleep — making it unreliable for time-sensitive jobs on laptops.
> 3. Raycast stores clipboard history at `~/Library/Application Support/com.raycast.macos/databases/` in an unencrypted SQLite database. This is forensically significant because it may contain passwords, API tokens, credentials, and document fragments the user never intended to persist — and is frequently overlooked in macOS forensic checklists.
> 4. Keyboard Maestro Engine requires `kTCCServiceAccessibility` (Accessibility permission). When this grant is lost, all hotkey triggers and macro injections silently stop working — KM produces no alert or error; triggers simply do nothing.
> 5. Choose JXA when you need real JavaScript data structures, need to use Foundation/Cocoa APIs via `ObjC.import('Foundation')`, need `NSTask` for subprocess control, or want to pipe JSON between automation steps. AppleScript is better for deep dictionary-heavy GUI scripting of scriptable apps via their `sdef` dictionaries.

---

## Part 07 — Development Environment

**Big picture:** Setting up and understanding the macOS developer toolchain — Xcode internals, Command Line Tools vs. full Xcode, the build system, code signing, notarization, command-line development, package managers, dotfiles, containers/VMs, and universal binaries.

### [[00-xcode-demystified]] — Xcode Demystified

- Xcode.app bundles the IDE, clang/swift toolchain, all Apple platform SDKs, Instruments, and Simulator in ~13 GB; the IDE binary is just the tip.
- Every `/usr/bin/clang`, `/usr/bin/swift` etc. is a thin shim; `xcrun` resolves the real binary through the active developer directory; `xcrun --kill-cache` resets stale resolutions.
- DerivedData (`~/Library/Developer/Xcode/DerivedData/`) is fully regeneratable; deleting it fixes a broad class of stale-artifact errors including iCloud ` 2`-duplication module loops.
- `xcodes` (v2.0.1) is the standard multi-version Xcode manager; Archives in `~/Library/Developer/Xcode/Archives/` contain signed binary + dSYM — primary artifact for crash symbolication.

### [[01-command-line-tools-vs-xcode]] — Command Line Tools vs Full Xcode

- The system-wide active developer directory is a symlink at `/var/db/xcode_select_link`; `sudo xcode-select -s` rewires it instantly; `DEVELOPER_DIR` env var overrides per-process.
- CLT lacks: iOS/watchOS/visionOS SDKs, Simulator (`simctl`), Swift Macros (`#Preview`), and full `xcodebuild` multi-platform support.
- CLT is silently broken by macOS upgrades; repair is `softwareupdate --all --install --force`.
- Package receipts at `/var/db/receipts/com.apple.pkg.CLTools_*.plist` contain install date and version — a forensic timeline of developer tool installation.

### [[02-build-system-sdks-simulators]] — The Build System, SDKs & Simulators

- Deployment target (`MACOSX_DEPLOYMENT_TARGET`) = oldest OS supported; SDK version = newest API surface at compile time; `@available` guards weak-linked symbols.
- Universal fat binaries: `ONLY_ACTIVE_ARCH=NO` required for CI universal builds; `lipo -thin` on a signed binary breaks the signature.
- The iOS Simulator is not an emulator — it runs native arm64 code; prune unused runtimes with `xcrun simctl runtime delete --notUsedSinceDays N`.
- `xctrace record` captures Instruments traces headlessly; System Trace template records every syscall — 10 seconds reveals files touched, dylibs loaded, and network connections.

### [[03-code-signing-and-provisioning]] — Code Signing & Provisioning

- A code signature seals code pages (SHA-256 hashed in 4 KB blocks in the CodeDirectory) and resource files (CodeResources plist) in the `LC_CODE_SIGNATURE` Mach-O load command.
- The cdhash (SHA-256 of the CodeDirectory) is the compact, build-unique identity used by the kernel, TCC, and Keychain ACLs.
- Hardened runtime (`--options runtime`) is required for notarization; `codesign -dvvv` shows `flags=0x10000(runtime)` when enabled.
- Sign bundles **inside-out**: deepest nested helpers/frameworks first, outer `.app` last; `codesign --deep` is insufficient for production.

### [[04-notarization-and-distribution]] — Notarization & Distribution

- Notarization: submit to Apple's cloud scanner → receive ticket → staple to artifact; without stapling, Gatekeeper requires a CDN call on first launch.
- The notarization log JSON (`notarytool log <id>`) is the primary diagnostic; each `issues` entry has `path` and `arch` fields pointing to the exact failing binary slice.
- DMGs and PKGs each need separate notarization and stapling from the app bundle inside; PKGs require "Developer ID Installer" certificate (not "Developer ID Application").
- Sparkle 2 uses EdDSA (Ed25519) for auto-update signing; loss of the private key requires users to manually re-install the next version.
- Since macOS Sequoia 15, the Ctrl-click Gatekeeper bypass is gone; properly notarized apps are the only frictionless distribution path.

### [[05-command-line-development]] — Command-Line Development: clang, swift, lldb

- `xcrun` is the correct way to invoke any Apple toolchain binary from scripts — always resolves to the active developer directory.
- System libraries on macOS 12+ live in the dyld shared cache (Cryptex volume), not as individual files; `otool -L` still works but the paths are virtual.
- Every binary built with `-g` has a UUID; `dwarfdump --uuid` confirms the dSYM match; `atos -arch arm64 -o <dSYM> -l <load_addr> <crash_addr>` symbolicates any crash address.
- `DYLD_INSERT_LIBRARIES` and other `DYLD_*` vars are silently stripped from hardened-runtime and SIP-protected processes.

### [[06-dev-package-managers]] — Developer Package Managers

- Never modify `/usr/bin/python3`, `/usr/bin/ruby`, or their site-packages — SIP-protected and frozen to the macOS release.
- mise is the 2025+ unified version manager (replacing nvm + pyenv + rbenv + asdf); a single `.mise.toml` pins all language versions; `eval "$(mise activate zsh)"` must be **last** in `.zshrc`.
- Always use a Python virtual environment per project; `uv` (Rust-based) resolves 10–100× faster than pip and downloads its own CPython (PEP 668 never applies).
- Volta is end-of-life (Nov 2025); migrate Node version management to fnm or mise.

### [[07-terminal-dev-workflow-and-dotfiles]] — Terminal Dev Workflow & Dotfiles

- `git config --global credential.helper osxkeychain` stores HTTPS tokens silently in the macOS Keychain; the Keychain entries for `github.com` are forensically significant.
- SSH commit signing (`gpg.format = ssh`): `ssh-add --apple-use-keychain` persists the key across reboots via launchd; adds verified badges on GitHub.
- chezmoi wins for cross-Mac portability: Go templating handles per-machine differences, encrypted secrets stay out of the repo, `run_once_` bootstrap scripts automate new machine setup.
- Keep dotfiles at `~/dev/dotfiles/` — never under `~/Documents/` or `~/Desktop/` (iCloud-synced paths corrupt `.git` objects with ` 2`-suffixed duplicates).

### [[08-containers-and-vms]] — Containers & VMs on the Mac

- Containers on macOS always go through a Linux VM — there is no native Linux kernel on macOS; runtime quality is determined by VM file I/O efficiency (virtiofs with macOS kernel extensions is fastest: OrbStack first, then Colima `--mount-type virtiofs`).
- arm64 images run at full speed; Rosetta-translated x86 runs ~1.2–1.5×; pure QEMU x86 runs ~4–8× slower.
- GPU/Metal passthrough is not available in any container or Linux VM on Mac; run ML workloads (PyTorch, MLX) directly on the host.
- Docker contexts (`docker context use <name>`) are the correct way to switch between Docker Desktop, OrbStack, and Colima without socket conflicts.

### [[09-universal-binaries-rosetta-arch]] — Universal Binaries, Rosetta & Architecture

- arm64 is standard AArch64; arm64e adds ARMv8.3 PAC + BTI, enforced on Apple Silicon only; third-party code targets arm64; Apple system code uses arm64e.
- A Universal 2 fat Mach-O has magic `0xCAFEBABE`; `lipo -thin` on a signed binary breaks the signature and requires re-signing.
- `/var/db/oah/`: `.aot` timestamp = first execution; two UUIDs for the same binary name = binary was swapped.
- `sysctl -n sysctl.proc_translated` returns 1 inside Rosetta, 0 native; `uname -m` returns `x86_64` under Rosetta but reflects the process, not the host CPU.
- Homebrew has two independent prefixes: `/opt/homebrew` (arm64) and `/usr/local` (x86_64); never mix dylibs across prefixes.

> **Check yourself:**
> 1. What does `xcrun --kill-cache` fix, and when should you reach for it?
> 2. Why must bundles be signed inside-out, and what does `codesign --deep` fail to handle correctly?
> 3. What does `auth_reason` in TCC.db tell you that `sysctl.proc_translated` does not?
> 4. Why is GPU/Metal passthrough unavailable in Linux VMs on Mac, and what is the correct workaround for ML workloads?
> 5. What does a second UUID for the same binary name in `/var/db/oah/` indicate?

> [!success]- Answers
> 1. `xcrun --kill-cache` clears the xcrun resolution cache, which can become stale after switching active developer directories (e.g., between CLT and Xcode, or between two Xcode versions). Reach for it when `xcrun` resolves to the wrong toolchain binary after `sudo xcode-select -s` or an Xcode version switch.
> 2. A code signature seals the CodeResources plist, which records hashes of nested helpers and frameworks. If you sign outer bundles first, the nested items' hashes haven't been computed yet — signing them after changes those hashes and breaks the outer seal. `codesign --deep` signs depth-first but does not correctly handle entitlements or per-slice flags on nested binaries; production builds must sign each target explicitly in dependency order.
> 3. `auth_reason` in TCC.db reveals *how* a TCC grant was made (e.g., 6 = MDM/PPPC silent grant, 7 = user consent). `sysctl.proc_translated` only tells you whether the *current* process is running under Rosetta — it has no bearing on TCC authorization history. The two answer entirely different questions.
> 4. Linux VMs on Mac run in a hypervisor that has no access to Apple's proprietary Metal GPU API — Metal is unavailable outside the macOS host. The correct workaround is to run ML workloads (PyTorch with MPS backend, MLX) directly on the macOS host, where they have full access to the Apple Neural Engine and GPU via Metal.
> 5. Two UUIDs for the same binary name in `/var/db/oah/` means the x86-64 binary was swapped — a new binary replaced the original one. The first UUID's `.aot` creation timestamp marks the first execution of the original binary; the second marks the first execution of the replacement. This is a high-value indicator that a binary was updated or substituted.

---

## Part 08 — Networking & Connectivity

**Big picture:** How macOS manages network state, file/screen sharing, iCloud internals, VPN, Bluetooth, and peripherals — with forensic and operational depth at each layer.

### [[00-networking-stack]] — The macOS Networking Stack

- `configd` (dynamic store) is the single source of truth for all network state; `networksetup` is the correct mutation interface — never edit `preferences.plist` directly.
- DNS goes through `mDNSResponder`, which handles unicast DNS, mDNS/Bonjour, and per-domain resolver routing; standard Unix tools (`dig`, `nslookup`) **bypass** mDNSResponder — use `dscacheutil -q host` or `scutil --dns` for OS ground truth.
- IPv6 privacy addresses rotate every 24h; Wi-Fi MAC randomization is on during scanning — both affect cross-session identity correlation.
- `awdl0` is AirDrop's layer-2 substrate (time-multiplexed ad-hoc Wi-Fi with a randomized MAC per session); AWDL traffic is capturable in monitor mode.

### [[01-file-and-screen-sharing]] — File & Screen Sharing

- Every Sharing pane toggle is `launchctl` load/unload on a named LaunchDaemon; each enabled service automatically receives an Application Firewall exemption that vanishes when disabled.
- macOS 26 Tahoe enforces SMB3 with mandatory packet signing; SMB1 is gone; AFP was removed in macOS 13 Ventura.
- Screen Sharing is a VNC server (RFB protocol, port 5900); the VNC password is a separate credential (max 8 chars) that does not rotate when the user account password changes.
- Internet Sharing creates a `bridge100` interface and assigns `192.168.3.x/24` — accidentally enabling it on a production network introduces a rogue DHCP server.

### [[02-icloud-and-apple-id]] — iCloud & Apple ID Internals

- iCloud is not one thing — it is a collection of discrete sync services each with its own protocol, daemon, and encryption boundary.
- Evicted files leave `.icloud` placeholder stubs with zero local bytes; on a forensic offline image, evicted content is unrecoverable without Apple account credentials.
- Without ADP, Apple can decrypt iCloud Drive, Photos, Notes, Reminders, and iCloud Backup under lawful process. `MobileMeAccounts.plist` records which Apple Account was active and which services were enabled.
- iCloud is sync, not backup — deletions propagate in seconds; Time Machine + offsite backup is still required.

### [[03-vpn-and-secure-connectivity]] — VPN & Secure Connectivity

- macOS 26 Tahoe removed L2TP entirely; minimum safe IKEv2 config is AES-256, SHA-256, DH Group 14+; SHA-1/DES/3DES causes silent death.
- All VPN clients since macOS 11 must be System Extensions (`NETunnelProviderManager`); extension activation state in `/Library/SystemExtensions/db.plist`.
- WireGuard best single-machine choice: ~4,000 line codebase, Curve25519/ChaCha20-Poly1305, sub-100ms handshake, instant roaming.
- Configuration profiles (`.mobileconfig`) are the deployment primitive for VPN, encrypted DNS, Wi-Fi credentials, and CA trust anchors; rogue profiles installing CA trust anchors are an indicator of compromise — audit with `sudo profiles show -type configuration`.

### [[04-bluetooth-peripherals-drivers]] — Bluetooth, Peripherals & Drivers

- Class-compliant USB/Bluetooth devices enumerate immediately via IOKit; devices outside these classes need a DriverKit `.dext` System Extension (user-space, Notarized, one-time user approval + reboot).
- Bluetooth pairing keys are stored in `/Library/Preferences/com.apple.Bluetooth.plist` (system-level, not user Keychain) — high-value forensic artifact for device-proximity timelines.
- CUPS (`cupsd` on TCP 631 loopback) is the macOS print spooler; `/var/log/cups/page_log` records every printed page with username, printer, job ID, date, and filename — a forensic timeline artifact.
- Uninstalling the parent app does not remove a System Extension — it enters zombie `[activated enabled]` state; clean up with `systemextensionsctl uninstall TEAMID <bundle-id>`.

> **Check yourself:**
> 1. Why does `dig` not reflect the actual DNS configuration on macOS, and what tool gives you OS ground truth?
> 2. What does enabling Internet Sharing create on the network, and why is it dangerous?
> 3. What forensic artifact in `/Library/Preferences/com.apple.Bluetooth.plist` proves device proximity?
> 4. What happens to a System Extension when its parent app is deleted?
> 5. How do you verify that encrypted DNS is actually working, not bypassed?

> [!success]- Answers
> 1. `dig` and `nslookup` use their own resolver stacks and bypass `mDNSResponder`, ignoring per-domain resolver routing, VPN split-DNS, and Search Domain settings configured in SCDynamicStore. For OS ground truth use `scutil --dns` (shows all resolver configs) or `dscacheutil -q host -a name <hostname>` (queries through the actual OS resolver).
> 2. Internet Sharing creates a `bridge100` virtual interface and launches a DHCP server assigning `192.168.3.x/24` addresses to clients. On a production network this introduces a rogue DHCP server that can redirect other devices' default gateway and DNS, causing network disruption or interception.
> 3. The Bluetooth pairing keys in `/Library/Preferences/com.apple.Bluetooth.plist` record paired device identifiers and names. Their presence proves that a specific device was within Bluetooth range and paired with this Mac — establishing physical proximity and association timelines between the Mac and those devices.
> 4. The System Extension enters zombie `[activated enabled]` state — it remains loaded and running in the kernel/userspace but has no parent app to manage it. It does not self-uninstall. You must explicitly remove it with `systemextensionsctl uninstall <TEAMID> <bundle-id>`.
> 5. Capture traffic with `tcpdump -i any port 53` while browsing. If encrypted DNS is working, there should be zero port-53 UDP/TCP packets — all DNS goes over DoH/DoT on ports 443/853. Any port-53 traffic means DNS is leaking in plaintext and the encrypted DNS config is not being honored.

---

## Part 09 — Apps & Ecosystem

**Big picture:** The anatomy of a Mac app, distribution channel tradeoffs, the power-user app stack, and media/creative tools — with forensic perspective on each.

### [[anatomy-of-an-app-bundle]] — Anatomy of a Mac App Bundle

- `.app` is a directory Finder presents as a single file; `CFBundleIdentifier` is the OS-level identity used by the sandbox container, Launch Services, Keychain, and code-signing — renaming the `.app` changes nothing the OS sees.
- `Contents/Info.plist` is the definitive manifest; malware often clones a legitimate bundle ID — always cross-check against the actual codesigning Team ID via `codesign -dvvv`.
- `_CodeSignature/CodeResources` is a plist of SHA-256 hashes of every bundle file; any modification breaks the seal.
- Dragging an app to Trash leaves containers, prefs, caches, log files, and LaunchAgent plists entirely intact — orphaned `~/Library/Containers/` entries are strong indicators of prior software presence.

### [[app-distribution-channels]] — App Distribution: App Store vs Direct vs Homebrew

- Four channels: MAS, direct download (Developer ID + notarization), Homebrew Cask, ungated — a spectrum from "Apple controls everything" to "developer controls everything."
- The MAS App Sandbox is the defining constraint: incapable of clipboard monitoring, system extensions, or arbitrary filesystem access — why all serious sysadmin and security tools live outside it.
- Homebrew Cask strips `com.apple.quarantine` after SHA-256 verification; directly downloaded apps carry it until first launch or manual removal — distinguishing forensic signals.
- `spctl --master-disable` is gone on Sequoia/Tahoe; the only supported path for un-notarized trusted software is the per-app "Open Anyway" flow or `xattr -d com.apple.quarantine`.

### [[power-user-app-stack]] — The Power-User App Stack

- `/opt/homebrew/Cellar/` on an examined machine signals deliberate power-user or developer intent.
- The Objective-See suite (LuLu, BlockBlock, OverSight, KnockKnock) is mandatory for a forensic analyst's Mac; BlockBlock's SQLite alert database records what the user was alerted about and whether they allowed or denied it.
- Clipboard managers maintain persistent SQLite history; Maccy's store at `~/Library/Containers/org.p0deje.Maccy/.../Storage.sqlite` may contain passwords, tokens, and document fragments the user never intended to persist.
- Replace three defaults immediately on any fresh Mac: QuickTime → IINA, `ls` → `eza`, built-in screenshots → Shottr.

### [[media-and-creative-tools]] — Media & Creative Tools

- Apple Silicon dedicated media engines handle H.264, HEVC, and ProRes entirely off-CPU; use `-c:v hevc_videotoolbox` in ffmpeg; AV1 hardware decode arrived with M3, encode only on M4 Ultra+.
- `Photos.sqlite` contains full edit history BLOBs, hidden/deleted flags, iCloud state, and face clusters; examine it while Photos is **closed** (WAL file must be merged for current state on a live system).
- HEIC files embed GPS, device model, Live Photo cross-links (`ContentIdentifier` UUID ties still to its `.mov`), and edit history; `exiftool -Apple:all` exposes all.
- `ffmpeg -ss` before `-i` is fast keyframe seek; after `-i` is slow frame-accurate decode — for lossless `-c copy` trims, put `-ss` before `-i`.
- `osxphotos query --screenshot` reveals screen recordings silently deposited in the Photos library — forensically significant screen activity evidence.

> **Check yourself:**
> 1. What does renaming a `.app` bundle change from the OS's perspective?
> 2. Why do the best sysadmin and security tools live outside the Mac App Store?
> 3. What forensic information do orphaned `~/Library/Containers/` entries reveal?
> 4. Why must you examine `Photos.sqlite` while the Photos app is closed (or on a dead image)?
> 5. What distinguishes the quarantine provenance of a Homebrew Cask-installed app from one directly downloaded?

> [!success]- Answers
> 1. Nothing meaningful. The OS-level identity is `CFBundleIdentifier` in `Contents/Info.plist` — used by the sandbox container, Launch Services, Keychain, and code-signing. Renaming the `.app` directory changes only the Finder display name; the bundle ID, Team ID, and container path are unaffected.
> 2. The Mac App Store sandbox prohibits clipboard monitoring, system extensions, and arbitrary filesystem access — exactly the capabilities that security tools (outbound firewalls, EDR, forensic utilities) and sysadmin tools require. These apps must be distributed as Developer ID + notarized outside the MAS.
> 3. Orphaned entries in `~/Library/Containers/<bundle-id>/` (where the corresponding `.app` is gone) are strong indicators that software was previously installed and then removed (or dragged to Trash, which does not purge containers). The container may still hold user data, preferences, cached credentials, and SQLite databases from that app.
> 4. SQLite uses Write-Ahead Logging (WAL); when Photos is open, uncommitted changes sit in the `-wal` sidecar file and have not been merged into the main database. Querying the main database while Photos runs returns a stale view. On a live system the WAL must be checkpointed first; on a forensic dead image, mount read-only and merge the WAL manually before querying.
> 5. Homebrew Cask strips `com.apple.quarantine` after SHA-256 verification of the downloaded archive — installed apps carry no quarantine xattr and no QuarantineEventsV2 record. A directly downloaded app retains the quarantine xattr (with source URL and download timestamp) until first launch, and its provenance persists in `QuarantineEventsV2` for 90+ days — a clear forensic distinction.

---

## Part 10 — Hardware

**Big picture:** The physical Mac — Apple Silicon chip tiers, display pipeline limits, port protocols, and power/thermal management — with operational and forensic implications of each.

### [[apple-silicon-lineup]] — The Apple Silicon Mac Lineup & Specs

- Chip tier (base → Pro → Max → Ultra) is permanent at purchase: CPU cores, GPU cores, memory bandwidth, and maximum unified memory are all soldered-in constants.
- Unified Memory Architecture means CPU, GPU, Neural Engine, and all on-die accelerators share one DRAM pool — no separate VRAM; an LLM consuming 8 GB leaves zero for the OS on a base 8 GB machine.
- `system_profiler SPHardwareDataType` and `sysctl hw.model` give the canonical Model Identifier (e.g., `Mac17,6`) — the forensic key for vulnerability databases and SEP generation lookup.
- MacBook Air is fanless and throttles under sustained load (~70% of peak after 5–10 min); MacBook Pro with active fans sustains 100% indefinitely.

### [[ports-displays-thunderbolt]] — Ports, Displays, Thunderbolt & Docks

- USB-C is a connector shape, not a protocol — ports on the same Mac range from USB 2.0 (480 Mbps) to Thunderbolt 5 (80/120 Gbps); verify with `system_profiler SPThunderboltDataType`.
- The external display count ceiling is determined by hardware display pipelines in the SoC die, not port count — a Thunderbolt dock does not add pipelines. Base M1/M2: 1 display; M4/M5 base: 2; Pro: 3; Max: 4–5; Ultra: 8–10.
- DisplayLink bypasses the pipeline limit via CPU-compressed USB, but imposes 5–15% CPU overhead per display, 1–2 frame latency, no DRM content playback, and requires a Screen Recording permission grant.
- One port on Apple Silicon MacBook Pros is designated the DFU port (typically left rear); it cannot boot external macOS or create a LocalPolicy — use any other port for forensic Target Disk Mode or external boot.

### [[battery-thermal-power]] — Battery, Thermal & Power Management

- Battery health: Cycle Count (design rating ~1000) and Maximum Capacity %; `system_profiler SPPowerDataType` and `ioreg -rn AppleSmartBattery` expose these scriptably.
- `pmset -g assertions` is the primary diagnostic when the Mac refuses to sleep.
- `caffeinate -i` prevents idle sleep during long acquisitions; `-s` prevents system sleep but is silently ignored on battery.
- `powermetrics --samplers cpu_power,thermal` is the authoritative thermal profiler on Apple Silicon; the `smc` sampler is Intel-only and produces no output on M-series — use thermal pressure levels instead.
- `sudo pmset -a powernap 0 tcpkeepalive 0` prevents network activity during evidence sleep; `nvram -p` can reveal non-standard boot flags set by a prior user.

> **Check yourself:**
> 1. Why does adding a Thunderbolt dock not increase the number of external displays a Mac can drive?
> 2. What is the correct tool to check thermal pressure on Apple Silicon and why does the `smc` sampler fail?
> 3. Why is `caffeinate -s` unreliable during a long acquisition run on battery?
> 4. What does `sysctl hw.model` return and why is it valuable for vulnerability database lookups?
> 5. What non-standard evidence does `nvram -p` preserve that survives an OS reinstall?

> [!success]- Answers
> 1. The external display count ceiling is set by the number of hardware display pipelines in the SoC die — a fixed silicon constant. A Thunderbolt dock multiplies port availability but cannot add new display pipelines; connecting more monitors than the chip supports simply doesn't work (or requires CPU-based DisplayLink at a performance cost).
> 2. Use `powermetrics --samplers cpu_power,thermal` (which shows thermal pressure levels and per-cluster data) on Apple Silicon. The `smc` sampler is Intel-only — it reads SMC sensor registers that do not exist on M-series chips and produces no output on Apple Silicon.
> 3. `caffeinate -s` (system sleep prevention) is silently ignored on battery power — it only takes effect when plugged into AC. During a battery-powered acquisition, the system can still sleep, pausing or corrupting the acquisition. Use `caffeinate -i` (idle sleep prevention) instead, which works on both AC and battery.
> 4. `sysctl hw.model` returns the canonical Model Identifier (e.g., `Mac17,6`). This identifier maps to a specific SoC generation and hardware configuration in Apple's security advisories and third-party vulnerability databases (CVE lookups, SEP generation identification), making it the forensic key for assessing applicable vulnerabilities.
> 5. NVRAM persists boot arguments and flags set by tools like `nvram boot-args` — values that survive OS reinstalls and even Erase All Content and Settings (which does not clear NVRAM). `nvram -p` can reveal non-standard boot flags (e.g., `-v`, `kext-dev-mode=1`, SIP-related flags) set by a prior user or attacker, indicating the machine's security posture and any deliberate policy overrides.
