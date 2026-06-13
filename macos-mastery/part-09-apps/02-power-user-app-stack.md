---
title: The power-user app stack
part: P09 Apps
est_time: 60 min read + 45 min labs
prerequisites: [01-app-distribution-channels, 12-homebrew-and-package-management]
tags: [macos, apps, homebrew, productivity, security, development, utilities]
---

# The power-user app stack

> **In one sentence:** The top-1% macOS toolkit — curated by category with the mechanism behind each pick, the free/paid call, and the Homebrew cask name — so you can bootstrap a professional workstation in under an hour.

## Why this matters

A stock macOS installation is remarkable engineering, but it ships conservative defaults optimized for the widest possible audience. Power users — especially engineers and forensic analysts coming from a Windows world where the third-party ecosystem (Sysinternals, AutoHotkey, Everything, PowerToys) is mature and expected — quickly discover that macOS has an equally deep third-party layer. The difference: it's less obvious, and a lot of it is open source.

This lesson maps the entire ecosystem: what to install, why the mechanism makes it worth the bytes, and what the sensible defaults look like on a fresh machine. The [[reference/recommended-software|recommended-software reference spine]] is the companion lookup table; this lesson is the *why* behind each entry.

The lens throughout is a forensic analyst and software builder: we care about resource usage, what artifacts apps leave behind (relevant when you're also investigating machines), whether they require SIP or TCC grants, and whether their business model means they'll exist in three years.

---

## Concepts

### The macOS third-party app taxonomy

Before picking apps, understand the delivery mechanisms (see [[01-app-distribution-channels]]):

| Channel | Sandbox enforced? | Auto-update | Cask name pattern |
|---|---|---|---|
| App Store | Yes (MAS sandbox) | via App Store | `mas` IDs, not casks |
| Direct `.dmg` / Homebrew cask | No | Sparkle / Homebrew `upgrade` | `brew install --cask <name>` |
| Homebrew formula | No | `brew upgrade` | `brew install <name>` |
| Setapp subscription | No | Setapp.app | n/a |

The sandbox has real consequences: App Store apps cannot watch filesystem events outside their container, cannot inject accessibility APIs, and cannot act as system extensions. That's why every serious power tool — window managers, clipboard managers, system monitors — ships outside the App Store. Forensics note: MAS apps write receipts to `/private/var/db/receipts/` and their container lives at `~/Library/Containers/<bundle-id>/`; direct-install apps scatter files across `~/Library/{Application Support,Preferences,Caches}` and `/Library/` — both are significant artifact locations.

> 🔬 **Forensics note:** The presence of a Homebrew `Cellar` at `/opt/homebrew/Cellar/` (Apple Silicon) or `/usr/local/Cellar/` (Intel) on a machine under examination tells you the user has intentional developer/power-user intent. Each keg's `INSTALL_RECEIPT.json` records the install timestamp, source URL, and the installing user's `$HOME`. Look for unexpected system tools (network scanners, password crackers) there.

> 🪟 **Windows contrast:** The closest Windows parallel to `brew install --cask` is `winget install` (built into Windows 11) or `choco install` (Chocolatey). PowerToys ≈ a bundle of several apps on this list combined; Sysinternals ≈ Objective-See + Activity Monitor CLI. Everything ≈ `mdfind`/Spotlight + HoudahSpot. AutoHotkey ≈ Keyboard Maestro + BetterTouchTool.

---

## Category-by-category breakdown

### 1. Window management

macOS 26 (Tahoe) ships native tiling — the Stage Manager evolution now supports a proper tile grid when you hover the green button and drag. For casual users, that's enough. For power users, it's not: no keyboard-first control, no virtual workspaces that are truly independent of Mission Control's limitations, and no scripting API.

#### Manual / floating managers

**Rectangle** (`brew install --cask rectangle`) — Free, open source (MIT). The simplest path to keyboard-driven window snapping. Hooks into the Accessibility API to move/resize windows; no SIP bypass needed. Bindings like ⌃⌥← / ⌃⌥→ snap to halves, ⌃⌥↩ maximizes. Configuration lives in `~/Library/Preferences/com.knollsoft.Rectangle.plist`.

**Moom** (App Store or direct, ~$10) — The paid classic. Popup palette on hover over the green button; save and recall custom layouts ("Snapshots"). Useful when you have precise grid requirements and want a GUI, not a config file.

**BetterTouchTool** — Covered in [[04-hazel-and-keyboard-maestro]] and [[06-text-expansion-and-clipboard]]; it does window snapping too. If you own BTT, you may not need Rectangle.

#### Tiling managers (keyboard-first, i3-style)

**AeroSpace** (`brew install --cask nikitabobko/tap/aerospace`) — The current top pick for developers. An i3-inspired tiling WM that manages virtual workspaces as a pure tree structure *independent* of Mission Control's Spaces. Critically: it does **not** require disabling SIP, because it uses the Accessibility API rather than kernel injection. Config is a TOML file at `~/.aerospace.toml`; workspaces are named `1`–`9` (customizable), moved between with keyboard chords. As of v0.20.x (May 2026, 20,500+ GitHub stars) it's pre-1.0 with rough edges around drag-to-rearrange and native fullscreen interaction. Install via the custom tap: `brew tap nikitabobko/tap && brew install --cask aerospace`.

**yabai + skhd** — The scriptable tiling engine (yabai) paired with a hotkey daemon (skhd). Yabai's full feature set (e.g. border decoration, opacity, inserting/moving in the BSP tree) requires disabling SIP, which is a significant security tradeoff. The partial-SIP mode works without disabling SIP but loses window-manipulation depth. Use yabai if you need scripting hooks; use AeroSpace for a saner config story.

**Amethyst** (`brew install --cask amethyst`) — Free, open source. Automatic tiling without config files; borrows xmonad's layout metaphor. Lower ceiling than yabai/AeroSpace but zero setup cost.

> 🪟 **Windows contrast:** PowerToys FancyZones is the closest equivalent to Rectangle. There's no direct Windows equivalent to AeroSpace/yabai — i3 runs on Linux/Wayland only.

---

### 2. Launchers

See [[05-launchers-raycast-alfred]] for full treatment. Short version:

**Raycast** (`brew install --cask raycast`) — Free tier is excellent. An Electron-less, native Swift app that replaces Spotlight as a launcher, clipboard manager (built-in), window manager (built-in), snippet expander, and extensible platform. The Extension Store covers GitHub, Jira, Linear, Homebrew, etc. If you only install one productivity upgrade on a new Mac, make it Raycast.

**Alfred** (`brew install --cask alfred`) — The veteran (2010). Powerpack (~$35 one-time) unlocks Workflows, which are more powerful than Raycast's extensions for complex local automation. Slightly more robust offline than Raycast. Preference: Alfred for heavy workflow automation, Raycast for daily driver simplicity + team collaboration.

---

### 3. Clipboard managers

The system clipboard is one buffer. Power users need a history.

**Maccy** (`brew install --cask maccy`) — Free, open source (MIT). Lightweight menu-bar clipboard manager. Stores plain-text, rich text, and images. Default ⇧⌘V opens the history picker; fuzzy search narrows instantly. Preferences stored at `~/Library/Preferences/org.p0deje.Maccy.plist`. For a forensic analyst: clipboard history is a goldmine — Maccy's SQLite backing store at `~/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite` will contain copy/paste history if the app is installed.

**Raycast** — If you use Raycast, its built-in Clipboard History extension (free) covers this use case. One fewer app to manage.

**Paste** (Setapp / $2/mo standalone) — The polished, grid-based clipboard manager with iCloud sync across devices. Worth it if you copy between Mac and iPhone frequently.

> 🔬 **Forensics note:** Clipboard managers maintain persistent history that survives reboots. A Maccy or Paste database on an examined machine is a significant artifact — it may contain passwords, tokens, and document fragments that the user never intentionally stored.

---

### 4. Menu-bar management

Apple Silicon Macs with notch displays have a literal gap in the menu bar; older Macs just fill up fast. The category exists to hide, show, and organize menu-bar items.

**Ice** (`brew install --cask jordanbaird-ice`) — Free, open source (MIT, GitHub: `jordanbaird/Ice`). The modern choice. Drag items between Visible / Hidden / Always-Hidden sections. Supports menu-bar tinting, icon spacing, and a click-to-reveal gesture. Requires macOS 14+. Note: as of mid-2026 the original Ice repo had periods of slower maintenance; a fork called **Thaw** emerged for macOS 26 compatibility.

**Bartender 5** (`brew install --cask bartender`) — The paid stalwart (~$16 one-time). More stable on older macOS; has "Bartender 4 mode" for those who prefer the original section design. Acquired by Applause in 2024 — the ownership change caused community concern about privacy, so Ice became the default recommendation.

> 🪟 **Windows contrast:** TaskbarX and similar Windows utilities serve adjacent needs. The macOS menu bar has no direct Windows equivalent — the system tray is the rough analogue.

---

### 5. Automation

See [[04-hazel-and-keyboard-maestro]] for full depth. Headlines:

**Hazel** (`brew install --cask hazel`, ~$42 one-time) — Rule-based file watcher. Hazel attaches an `FSEvents` watcher to folders you designate, then evaluates rules (name, kind, date, tags, contents) and takes actions (move, rename, tag, run script, delete). The automation backbone for keeping `~/Downloads` and `~/Desktop` clean automatically. Config is a proprietary binary plist in `~/Library/Preferences/com.noodlesoft.Hazel.plist`.

**Keyboard Maestro** (`brew install --cask keyboard-maestro`, ~$36 one-time) — Macro engine. Triggers: hotkeys, typed strings, app launch, time, clipboard content. Actions: type text, manipulate apps, run scripts, control mouse. The automation substrate for anything that doesn't have an API. KM stores macros in `~/Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.plist`.

**BetterTouchTool** (`brew install --cask bettertouchtool`, ~$22 one-time) — Input remapper. Trackpad gestures, Magic Mouse, keyboard chords, MIDI, Stream Deck, Touch Bar (Intel). Also does window snapping. The deepest customization layer for hardware input on the Mac.

---

### 6. Text / notes / editors

**Obsidian** (`brew install --cask obsidian`) — Free for personal use. A local-first, Markdown-based knowledge base where every note is a plain `.md` file you own. The vault is a folder; iCloud / git / any sync works. Plugin ecosystem is vast (Dataview, Templater, Excalidraw, etc.). This is the note-taking recommendation for technical users who want durability and scriptability. See the Obsidian wikilink pattern used throughout this curriculum — it's the vault that hosts these lessons.

**iA Writer** (`brew install --cask ia-writer`, ~$50 one-time on App Store) — Distraction-free Markdown editor. Excellent for long-form prose. Its "Focus mode" and typewriter-scroll are genuinely helpful. The App Store version syncs via iCloud; the direct version does not.

**Bear** (App Store, free / $3/mo Pro) — Markdown notes with a gorgeous UI, rich linking, and native iOS/macOS sync. Good for shorter notes and task-adjacent writing. The `.bear2bk` backup is an SQLite database.

**Typora / PurpleMark-style editors** — Typora (`brew install --cask typora`, $15 one-time) renders Markdown inline as you type — the "seamless" editing model. For a live preview + source toggle model, [[PurpleMark]] (this project's own subproject) takes the same approach in a native SwiftUI app.

---

### 7. Terminals

See [[00-terminal-and-shells]] and [[07-terminal-dev-workflow-and-dotfiles]] for shell-level depth.

**Ghostty** (`brew install --cask ghostty`) — The current top pick for 2026. Zig-native, GPU-accelerated, platform-native UI (not Electron, not Qt). Version 1.3.1 (March 2026) added scrollback search, native scrollbars, and clickable shell prompts. Config is a plain text file at `~/.config/ghostty/config`; no GUI settings panel. Tabs, splits, and multiple windows work exactly as macOS conventions dictate. Startup time: sub-100ms. The Homebrew cask is `ghostty`; a `ghostty@tip` cask tracks HEAD builds.

**iTerm2** (`brew install --cask iterm2`) — The long-time power-user standard. Python scripting API, profiles, tmux integration (`tmux -CC`), inline images (imgcat), shell integration (breadcrumbs, command timing, marks). Slower startup than Ghostty, Electron-era UI, but unmatched in automation depth. Use iTerm2 when you need its Python API or tmux native integration; use Ghostty as daily driver.

**Warp** (`brew install --cask warp`) — AI-native terminal with block-based command history, collaborative sessions, and LLM-powered command lookup. Requires an account (cloud-synced); this is a deal-breaker for air-gapped or privacy-sensitive workflows. Worth knowing exists.

---

### 8. Development

#### Editors / IDEs

**VS Code / Cursor** (`brew install --cask visual-studio-code` / `brew install --cask cursor`) — The universal choice. VS Code is the base; Cursor is a fork with integrated Claude/GPT at the cost of sending code to the cloud. Both have the same extension ecosystem. For forensics work: VS Code's SQLite Viewer extension (`alexcvzz.vscode-sqlite`) lets you open and query `.db` files directly.

**Zed** (`brew install --cask zed`) — Native Rust, GPU-rendered editor. The fastest text editor on macOS — measurably. Collaborative editing is built in (not a plugin). Still maturing on extension coverage vs. VS Code but excellent for large codebases.

**Sublime Text** (`brew install --cask sublime-text`, $99 one-time) — Column editing, multi-cursor, the original "speed at scale" editor. Still useful as a viewer for large files (100MB+) where VS Code's language server would choke.

**JetBrains IDEs** (`brew install --cask intellij-idea` / `pycharm` / `webstorm` / etc.) — The gold standard for language-specific deep IDE features (refactoring, inspections, debuggers). Heavier than VS Code but materially smarter for Java/Kotlin/Python at scale.

#### Git clients

**Tower** (`brew install --cask tower`, subscription ~$79/year) — The most powerful Mac-native Git GUI. Interactive rebase, worktrees, conflict resolver, stash management. Worth it for teams not living in the terminal.

**Fork** (`brew install --cask fork`, $60 one-time after trial) — Lighter than Tower. Fast, natively rendered diff viewer. Popular for solo developers.

**GitUp** (`brew install --cask gitup`) — Free, open source. The repository map (a DAG view of history) is unique and genuinely useful for understanding complex branch states.

#### Database clients

**TablePlus** (`brew install --cask tableplus`, free tier / $79 one-time) — The Swiss Army knife of DB clients. Native macOS app, supports PostgreSQL, MySQL, SQLite, Redis, DynamoDB, and more. Connects via SSH tunnel. Crucial for forensic work: open any SQLite artifact (Messages database, TCC.db, clipboard stores) with a GUI instead of raw `sqlite3`.

**DB Browser for SQLite** (`brew install --cask db-browser-for-sqlite`) — Free, open source. Simpler than TablePlus for SQLite-only work. The go-to for quickly inspecting artifact databases.

> 🔬 **Forensics note:** Nearly every macOS system artifact is a SQLite database. `~/Library/Messages/chat.db`, `~/Library/Application Support/com.apple.sharedfilelist/`, `/private/var/db/Accessibility/com.apple.accessibility.db`, TCC databases at `/Library/Application Support/com.apple.TCC/TCC.db` — all queryable directly with TablePlus or sqlite3.

#### Proxy / network inspection

**Proxyman** (`brew install --cask proxyman`, free tier / $89 one-time) — Native Swift HTTP/HTTPS proxy with man-in-the-middle SSL interception. Cleaner than Charles on Apple Silicon; faster startup, better UI. Essential for understanding what apps send over the network. Run as a system proxy; Proxyman installs a root certificate into the system keychain to decrypt TLS. Forensics equivalent: understanding app-level traffic without a Wireshark capture.

**Wireshark** (`brew install --cask wireshark`) — The standard. Full packet capture. Needs ChmodBPF or running as root to capture on network interfaces. Use alongside Proxyman: Wireshark for layer 2–4, Proxyman for layer 7 HTTP.

#### Containers and VMs

**OrbStack** (`brew install --cask orbstack`, free personal / paid commercial) — The recommended Docker Desktop replacement for Apple Silicon in 2026. Boots in ~2 seconds (vs. 30–60s for Docker Desktop), uses 70% less CPU at idle, and delivers 5–10x better filesystem I/O for bind mounts. Runs the same Docker Engine and `docker compose` commands; drop-in replacement. Also runs Linux VMs. The catch: commercial use requires a paid subscription.

**Docker Desktop** (`brew install --cask docker`) — Still the enterprise default where IT governance demands an official Docker, Inc. product. Heavier, slower on Apple Silicon, but universally understood by ops teams.

**UTM** (`brew install --cask utm`) — Free, open source. QEMU-backed VM runner with a native SwiftUI frontend. Run Windows ARM, Linux, older macOS, or x86_64 (via Rosetta-accelerated QEMU) on Apple Silicon. The choice for analysts who need isolated Windows environments for malware analysis without a VMware subscription.

---

### 9. Files, cleanup, and disk space

#### The truth about "cleaner" apps

Skip CleanMyMac and its category. The "GB freed" number is theater — it deletes language packs and cache files that macOS recreates on demand, and you can do the same with `sudo periodic daily weekly monthly` and clearing `~/Library/Caches` manually. The real problems are: (a) finding what's eating disk, and (b) fully removing apps you uninstall.

**DaisyDisk** (`brew install --cask daisydisk`, $10 App Store) — The sunburst map of disk space. Scans the whole volume (with admin grant) and visualizes space as proportional colored wedges. Find the 20GB folder you forgot about in 30 seconds. For forensics: the visual immediately reveals unexpectedly large directories (encrypted container files, log archives, VM images) that a directory listing misses.

**GrandPerspective** (`brew install --cask grandperspective`, free / $3 App Store) — Similar concept, treemap instead of sunburst. Open source underpinnings. Excellent for scripted invocation: `grandperspective ~/` opens the GUI with a pre-scanned view.

> 🪟 **Windows contrast:** WinDirStat (treemap) and SpaceSniffer are the Windows equivalents. TreeSize Professional is the enterprise version. GrandPerspective ≈ WinDirStat on macOS.

#### App uninstallation

**AppCleaner** (`brew install --cask appcleaner`) — Free. Drag an `.app` onto AppCleaner and it finds all associated preference files, caches, launch agents, and support files. Uses the same heuristics as `mdfind`. The simple, reliable choice for occasional uninstalls.

**Pearcleaner** (`brew install --cask pearcleaner`) — Free, open source (Apache 2 + Commons Clause, 11k+ GitHub stars). Surpasses AppCleaner in depth: scans every `Library` location, includes a Finder extension for right-click uninstall, has a built-in Homebrew cask GUI manager, and runs a 2MB background "Sentinel" that auto-prompts when an app moves to Trash. The choice for a developer who also wants to manage Homebrew casks graphically.

> ⚠️ **ADVANCED:** Neither tool can safely remove apps with kernel extensions or system extensions — those require the app's own uninstaller or `systemextensionsctl uninstall`. Check with `systemextensionsctl list` before manually deleting.

#### Archive management

**Keka** (`brew install --cask keka`, free direct / $3 App Store) — Extracts and creates 7z, RAR, tar.gz, zip, and more. Sets itself as the default handler for archive types. The reliable choice; handles password-protected archives and split archives.

**The Unarchiver** (`brew install --cask the-unarchiver`, free App Store) — Simpler; extract-only. Handles almost every format. Install for the coworker who just needs double-click-to-open to work for `.rar` files.

---

### 10. System utilities

#### System monitor

**Stats** (`brew install --cask stats`) — Free, open source. Menu-bar display of CPU, GPU, RAM, disk, network, battery, fan speed, Bluetooth, and more — each as a configurable mini-graph or percentage. The replacement for iStatMenus if you don't want to pay ~$12. Background: reads from `sysctl` and IOKit frameworks; no kernel extension needed.

**iStatMenus** (`brew install --cask istatmenus`, ~$12 one-time) — The polished paid version. Slightly more data density, prettier rendering, historical graphs, notification alerts at thresholds. Worth it if you want alerts when CPU sustains above 90% or NVMe temperature spikes.

#### External display brightness

**MonitorControl** (`brew install --cask monitorcontrol`) — Free, open source. Controls brightness and volume on external displays via DDC/CI protocol over DisplayPort/HDMI — no app required on the display, it's a hardware protocol. Menu-bar sliders; keyboard shortcut support. Essential for anyone with external monitors, where macOS System Settings brightness slider has no effect on non-Apple displays.

#### Keyboard remapping

**Karabiner-Elements** (`brew install --cask karabiner-elements`) — Free, open source. The deepest keyboard remapping tool on macOS. Installs a kernel extension (HID driver) that intercepts keystrokes before the system sees them. Remaps any key to any key, creates complex modifications (e.g., Caps Lock → Hyper key = ⌘⌥⌃⇧ simultaneously), handles device-specific rules. Config in `~/.config/karabiner/karabiner.json`. Cross-ref [[04-keyboard-shortcuts-and-customization]].

> 🔬 **Forensics note:** Karabiner's kernel extension (`org.pqrs.driver.Karabiner-VirtualHIDDevice`) appears in `kextstat` / `systemextensionsctl list`. A Karabiner installation on an examined machine indicates a sophisticated user; examine `karabiner.json` for evidence of macro-style remappings that could be used for unauthorized automation.

#### Battery management

**AlDente** (`brew install --cask aldente`, free basic / ~$25 Pro one-time) — Sets a charging ceiling (e.g., cap at 80%) to reduce lithium-ion degradation. Works by sending an SMC command to hold charge at your target. macOS 26.4+ added a native "Optimized Battery Charging" manual override, but AlDente Pro still provides deeper controls: heat protection (stop charging above 35°C), Sailing mode (run from AC without touching the battery when already above your limit), discharge mode, and automation by schedule or location. The kernel mechanism: AlDente writes to the `BCLM` (Battery Charge Level Max) SMC key via `/usr/bin/smckit` equivalents or direct IOKit access.

#### Screenshot tools

The built-in `screencapture` CLI and ⇧⌘3 / ⇧⌘4 / ⇧⌘5 are capable (see [[08-screenshots-and-screen-recording]]), but lack annotation, cloud upload, and scrolling capture.

**CleanShot X** (direct / Setapp, ~$29 one-time + $19/yr for updates) — The premium choice. Scrolling capture, video → GIF export, annotation tools, numbered step markers, cloud upload to cleanshot.com, and a floating thumbnail that stays on top while you work. The "Capture Scrolling Content" feature uses accessibility APIs to scroll and stitch a full-page screenshot without browser plugins.

**Shottr** (`brew install --cask shottr`, free / $8 one-time) — 2MB, instant startup. Built-in OCR (copy text from a screenshot), QR code reader, screen ruler, color picker. The "smart erase" removes objects and fills background. Better value-to-price ratio than CleanShot X if you don't need scrolling capture or cloud sync.

The practical split: use CleanShot X for tutorial/doc creation (annotations, steps, cloud links); use Shottr as the daily driver for OCR and quick grabs.

#### Media playback

**IINA** (`brew install --cask iina`) — Free, open source (GPLv3). Built on libmpv; plays every container and codec (MKV, HEVC, VP9, AV1, anything) with hardware acceleration on Apple Silicon. Native macOS UI, Picture-in-Picture, Touch Bar support, accurate subtitle rendering with ass/ssa parser, HDMI passthrough for Dolby/DTS. This is the default media player replacement — QuickTime Player can't handle MKV or non-Apple codecs without plugins. IINA's config folder at `~/.config/iina/` stores preferences and watch history.

> 🪟 **Windows contrast:** VLC is the Windows equivalent open-source choice. IINA has better macOS integration (window chrome, PiP, Dark Mode) than VLC on Mac.

#### E-books and torrents

**Calibre** (`brew install --cask calibre`) — Free, open source. E-book library manager, format converter (EPUB ↔ MOBI ↔ PDF ↔ AZW3), metadata editor, OPDS server. The tool for managing a local e-book library without DRM concerns.

**Transmission** (`brew install --cask transmission`) — Free, open source. The lightest BitTorrent client on macOS. Minimal UI, no bloat, supports magnet links, remote RPC interface. Stores state in `~/Library/Application Support/Transmission/`.

---

### 11. Security and privacy

#### Network firewall

**Little Snitch** (`brew install --cask little-snitch`, ~$69 one-time) — The gold standard outbound firewall. Runs a Network Extension (no kernel extension in v5+) to intercept every TCP/UDP connection attempt and prompt for allow/deny. The Rule Groups feature lets you create per-app profiles. Network Monitor mode shows live traffic in a radar-style visualization. For a forensic analyst, Little Snitch is also a malware detection tool: anything that tries to beacon home will trigger an alert.

**LuLu** (`brew install --cask lulu`) — Free, open source (Objective-See). Same capability as Little Snitch at the Network Extension layer. Less polished UI, but zero cost and fully auditable. Mandatory recommendation for privacy-conscious users who won't pay for Little Snitch.

#### Persistence and behavior monitors (Objective-See suite)

Patrick Wardle's [Objective-See](https://objective-see.org/tools.html) suite is the forensic analyst's macOS toolkit:

| Tool | Function | Cask |
|---|---|---|
| **BlockBlock** | Monitors persistence locations (Launch Agents, Login Items, cron, etc.) and alerts on new entries | `brew install --cask blockblock` |
| **KnockKnock** | Point-in-time scan of all persistent software ("AutoRuns for macOS") | `brew install --cask knockknock` |
| **OverSight** | Alerts when mic or camera is activated (even by a legitimate app) | `brew install --cask oversight` |
| **ReiKey** | Detects event taps (keyboard loggers that use the CGEvent API) | `brew install --cask reikey` |
| **ProcessMonitor** | Live log of process creation events | direct download |
| **FileMonitor** | Live log of file system events | direct download |

Install at minimum: LuLu + BlockBlock + OverSight. KnockKnock for periodic scanning. On a machine under investigation, run KnockKnock and ProcessMonitor before pulling artifacts — they surface what's running and persisting.

> 🔬 **Forensics note:** BlockBlock's alert database (an SQLite file in `~/Library/Application Support/BlockBlock/`) records every persistence attempt it saw. On an examined machine, this is evidence of what the user was alerted about — and whether they allowed or denied it.

#### Password management

**1Password** (`brew install --cask 1password`, ~$3/mo) — The most integrated password manager on macOS. Safari extension, native autofill, SSH agent, secret references for CLI via the `op` CLI tool (`brew install 1password-cli`), biometric unlock. Stores vault in 1Password's cloud or a local vault (v7 style, now deprecated) or self-hosted. The `op` CLI can inject secrets into shell scripts: `op run --env-file=.env -- ./script.sh`.

**Bitwarden** (`brew install --cask bitwarden`, free / $10/yr Premium) — Open source, self-hostable (Vaultwarden). The choice for air-gapped or zero-cloud environments. Browser extension and desktop app are feature-complete. Self-host with Vaultwarden on a local VM for full control.

#### Encryption

**Cryptomator** (`brew install --cask cryptomator`, free) — Client-side AES-256 encryption of individual file vaults stored in iCloud, Dropbox, or any cloud. Each file encrypts independently — no single-file container to corrupt. Forensics: a Cryptomator vault directory contains `.c9r` (encrypted file containers) and a `masterkey.cryptomator` (encrypted with your passphrase). The vault is readable without the software given the open spec, but not without the key. See [[01-filevault-and-encryption]] for the contrast with FileVault.

---

## "Install these first" — the Brewfile

The practical upshot. Create `~/.Brewfile` (Homebrew's global Brewfile location) and run `brew bundle install --global`:

```ruby
# ~/.Brewfile  — personal power-user bootstrap
# Run: brew bundle install --global

# Taps
tap "nikitabobko/tap"              # AeroSpace

# Fonts (optional but recommended for terminal)
cask "font-jetbrains-mono-nerd-font"

# === Window management ===
cask "rectangle"                   # Free snap; replace with AeroSpace if you prefer tiling
# cask "nikitabobko/tap/aerospace" # i3-style tiling (mutually exclusive with Rectangle for workflow)

# === Launcher ===
cask "raycast"                     # Replaces Spotlight; clipboard history built in

# === Clipboard ===
# Maccy only needed if NOT using Raycast clipboard history
# cask "maccy"

# === Menu bar ===
cask "jordanbaird-ice"             # Free, open-source Bartender alternative

# === Automation ===
cask "hazel"                       # File rules ($42 license required)
cask "keyboard-maestro"            # Macro engine ($36 license required)
cask "bettertouchtool"             # Input remapping ($22 license required)

# === Notes / text ===
cask "obsidian"                    # Local-first Markdown knowledge base (free)
# cask "ia-writer"                 # Prose writing ($50 one-time, also on App Store)

# === Terminal ===
cask "ghostty"                     # Native GPU-accelerated terminal (free)
# cask "iterm2"                    # Keep for tmux -CC integration if needed

# === Dev: editors ===
cask "visual-studio-code"          # Universal editor (free)
# cask "cursor"                    # VS Code fork with AI (free tier)
cask "zed"                         # Native Rust editor, fastest on large files (free)

# === Dev: git ===
# cask "fork"                      # Git GUI ($60 one-time after trial)
# cask "tower"                     # Heavy-duty Git GUI (subscription)

# === Dev: database ===
cask "tableplus"                   # Multi-DB GUI (free tier sufficient for most)
cask "db-browser-for-sqlite"       # SQLite-specific deep inspection (free)

# === Dev: proxy ===
cask "proxyman"                    # HTTP/S proxy & inspector (free tier)
cask "wireshark"                   # Full packet capture (free)

# === Dev: containers ===
cask "orbstack"                    # Docker Desktop replacement, Apple Silicon-native (free personal)

# === Files & cleanup ===
cask "pearcleaner"                 # App uninstaller + Homebrew GUI (free)
cask "daisydisk"                   # Disk space sunburst (App Store preferred; $10)
cask "keka"                        # Archive (un)packer (free direct)

# === System utilities ===
cask "stats"                       # Menu-bar system monitor (free)
cask "monitorcontrol"              # DDC/CI external display brightness (free)
cask "karabiner-elements"          # Deep keyboard remapping (free)
cask "aldente"                     # Battery charge limiter (free basic / $25 Pro)

# === Screenshots ===
# cask "cleanshot"                 # Premium annotate + scrolling capture ($29+)
cask "shottr"                      # Fast, OCR, color picker (free / $8)

# === Media ===
cask "iina"                        # libmpv-based player; replaces QuickTime (free)
cask "transmission"                # BitTorrent client (free)
# cask "calibre"                   # E-book manager (free)

# === Security ===
cask "lulu"                        # Outbound firewall (free, Objective-See)
# cask "little-snitch"             # Polished outbound firewall ($69)
cask "blockblock"                  # Persistence monitor (free, Objective-See)
cask "oversight"                   # Mic/camera alert (free, Objective-See)
cask "knockknock"                  # Persistence scanner (free, Objective-See)
cask "cryptomator"                 # Per-file cloud encryption (free)
cask "bitwarden"                   # Password manager (free / $10yr Pro)
# cask "1password"                 # Password manager (subscription; installs op CLI separately)

# === Homebrew CLI tools ===
brew "eza"                         # ls replacement with icons + git status
brew "bat"                         # cat replacement with syntax highlighting
brew "fd"                          # find replacement, sane syntax
brew "ripgrep"                     # grep replacement, recursive and fast
brew "fzf"                         # Fuzzy finder
brew "mas"                         # Mac App Store CLI (install App Store apps from CLI)
```

**App Store supplements** (install via `mas install <id>` after `brew install mas`):
- Amphetamine (keep-awake, free, ID `937984704`)
- Lungo alternative if you prefer a GUI toggle
- DaisyDisk (ID `411643860`) — same app, but App Store version can sandbox-scan user home; direct version needs FDA

---

## Hands-on (CLI & GUI)

### Replace three default tools right now

**Replace QuickTime → IINA:**
```bash
brew install --cask iina
# Right-click any video file → Get Info → Open With → IINA → Change All
# Or from CLI to set as default for all video UTIs:
defaults write com.apple.LaunchServices LSHandlers -array-add \
  '{LSHandlerContentType = "public.movie"; LSHandlerRoleAll = "com.colliderli.iina";}'
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain system -domain user
```

**Replace `ls` → `eza`:**
```bash
brew install eza
# Add to ~/.zshrc:
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --git --group-directories-first'
alias tree='eza --tree --icons --level=3'
```
`eza` renders file icons (Nerd Font glyphs), git status in the listing, and respects `.gitignore`. It's the reason to install a Nerd Font cask.

**Replace macOS screenshot → Shottr:**
```bash
brew install --cask shottr
# Open Shottr → Preferences → Hotkeys
# Set Capture Area to ⇧⌘4 (shadow of the system binding — disable system binding in System Settings → Keyboard → Shortcuts → Screenshots first)
# Set OCR to ⌥⇧⌘4
```
The OCR feature (drag to select text in any image/video frame) alone justifies the install.

---

## 🧪 Labs

### Lab 1 — Assemble and bootstrap a personal Brewfile

**Goal:** Customize the starter Brewfile above to your preferences, then do a single-command bootstrap install.

**Setup:** Have Homebrew installed (`brew --version` confirms). A fresh machine is ideal but not required — `brew bundle` skips already-installed items.

**Steps:**

1. Create your Brewfile:
```bash
mkdir -p ~/.config/homebrew
# Or use the global location:
cp ~/path/to/starter-brewfile ~/.Brewfile
```

2. Edit it. Uncomment apps you want; comment out those you don't. Pay attention to the license-required entries (Hazel, KM, BTT) — you'll need to purchase licenses post-install.

3. Do a dry run first:
```bash
brew bundle check --global --verbose
# Lists what's installed vs. missing, without installing
```

4. Install everything:
```bash
brew bundle install --global --verbose 2>&1 | tee ~/brewfile-install.log
```
Expected time on a fast connection: 15–45 minutes depending on selections. Watch for cask install prompts — some apps open macOS installer packages that require manual "Allow" clicks.

5. Verify:
```bash
brew bundle check --global
# Should print: The Brewfile's dependencies are satisfied.
```

6. Freeze the current state (useful after you hand-tweak with `brew install` later):
```bash
brew bundle dump --global --force
# Overwrites ~/.Brewfile with the current exact state
```

> 🔬 **Forensics note:** `~/.Brewfile` and `/opt/homebrew/Library/Taps/` are significant artifacts on an examined machine. The Brewfile reveals intended tooling; tap names reveal specialty tools (e.g., `nikitabobko/tap` → AeroSpace, `homebrew/cask-fonts` → developer aesthetic, a security-tool tap → deliberate security posture).

---

### Lab 2 — Configure AeroSpace for keyboard-driven tiling

> ⚠️ **ADVANCED:** AeroSpace reconfigures how windows appear on screen. Before starting, know how to quit it: `aerospace quit` from terminal, or kill the process. Undo: remove the app from Login Items (System Settings → General → Login Items & Extensions).

**Prerequisite:** `brew tap nikitabobko/tap && brew install --cask nikitabobko/tap/aerospace`

1. Grant Accessibility access (System Settings → Privacy & Security → Accessibility → AeroSpace → toggle on). Without this, AeroSpace cannot move windows.

2. Create the config:
```bash
mkdir -p ~/.config/aerospace
cat > ~/.config/aerospace/aerospace.toml << 'EOF'
# AeroSpace config — minimal but complete
# See: https://nikitabobko.github.io/AeroSpace/guide

[mode.main.binding]
# Application launchers
alt-enter = 'exec-and-forget open -na Ghostty'

# Focus movement (vi-style)
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

# Move windows
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'

# Workspaces 1–9
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'

# Move window to workspace
alt-shift-1 = 'move-node-to-workspace 1'
alt-shift-2 = 'move-node-to-workspace 2'
alt-shift-3 = 'move-node-to-workspace 3'

# Layout toggle
alt-slash = 'layout tiles horizontal vertical'
alt-comma = 'layout accordion horizontal vertical'

# Resize
alt-shift-minus = 'resize smart -50'
alt-shift-equal = 'resize smart +50'

# Float/unfloat toggle
alt-shift-space = 'layout floating tiling'

[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.right = 8
outer.top = 32
outer.bottom = 8

[workspace-to-monitor-force-assignment]
# Uncomment and adjust to pin workspaces to specific monitors
# 1 = 1   # workspace 1 → monitor 1
# 2 = 2   # workspace 2 → monitor 2
EOF
```

3. Launch AeroSpace: `open -a AeroSpace`. Add it to Login Items.

4. Test: open three app windows, then use `⌥H/J/K/L` to focus between them. Use `⌥1` / `⌥2` to jump workspaces. Use `⌥⇧H` to move the focused window left in the layout.

5. Inspect current state: `aerospace list-windows --all` lists every managed window with its workspace.

---

### Lab 3 — Wire up Pearcleaner as the default uninstaller

1. `brew install --cask pearcleaner`

2. Open Pearcleaner → Settings → Finder Extension → Enable. This adds "Uninstall with Pearcleaner" to the right-click context menu for `.app` files.

3. Test: drag any app you want to remove to Trash, then open Pearcleaner. Its Sentinel mode will automatically detect the Trash event and prompt with the full file list.

4. Review the file list before confirming deletion. Note how many files beyond the `.app` bundle it finds — Support files in `~/Library/Application Support/`, preferences in `~/Library/Preferences/`, caches in `~/Library/Caches/`, and any Launch Agents in `~/Library/LaunchAgents/`.

> 🔬 **Forensics note:** The files Pearcleaner finds are the same residual artifacts you'd look for on an examined machine. An app can be "deleted" (moved to Trash and emptied) while leaving `~/Library/Application Support/<AppName>/` fully intact — including databases, logs, and session tokens. Always check Library locations, not just `/Applications/`.

---

## Pitfalls & gotchas

**Accessibility API accumulation.** Every window manager, clipboard manager, and automation tool needs Accessibility access. System Settings → Privacy & Security → Accessibility fills up fast. Periodically audit it; revoke apps you no longer use. Each entry is a potential privilege escalation vector if the app is compromised.

**TCC grant persistence after app deletion.** macOS does not always revoke TCC grants when you delete an app. Manually clean `tccutil reset All com.example.app` or use Pearcleaner, which handles this. See [[02-tcc-and-privacy]].

**Homebrew cask updates don't auto-run.** `brew upgrade --cask` upgrades casks, but it doesn't relaunch apps. Running apps keep the old version until you quit and reopen. Use `brew upgrade --cask --greedy` to include casks that self-update (like Chrome) — normally Homebrew skips those.

**Karabiner on macOS 26 requires a kernel extension.** Karabiner-Elements installs `org.pqrs.driver.Karabiner-VirtualHIDDevice`. On Macs with the new "Reduced Security" required for third-party kexts, you need to allow the kext in System Settings → Privacy & Security → scroll to Security → Allow. Intel Macs in Full Security mode will need to reboot to Recovery to allow it. This is the correct behavior — kexts are high-privilege code.

**AlDente and macOS 26 native charge limiting.** macOS 26.4 added a native 80% charge cap option in System Settings → Battery. AlDente Pro still wins for: sailing mode, temperature-triggered pause, discharge to target level, and automation. Check whether native limits cover your needs before purchasing Pro.

**Ice / Bartender on macOS 26 privacy changes.** macOS 26's new menu-bar privacy restrictions changed the accessibility APIs that menu-bar managers rely on. If Ice or Bartender breaks after an OS update, check the GitHub releases page for a point release before filing a bug — this category of app breaks on every major macOS release and always gets fixed within weeks.

**The CleanMyMac trap.** CleanMyMac's "scan" is marketing. The bytes it "frees" are language resources (`*.lproj` folders) and cache files that will be recreated. Worse, it requires a full-disk-access TCC grant to do this. The risk/benefit ratio is poor. Use DaisyDisk to find real space consumers and AppCleaner/Pearcleaner to uninstall properly.

---

## Key takeaways

- The macOS power-user stack is deep and largely open source. Most of the best tools in this lesson are free or one-time-purchase.
- Every serious power tool lives outside the App Store because the sandbox prevents the Accessibility, kernel, and filesystem access these tools need.
- Homebrew's `brew bundle` with a `~/.Brewfile` is the single command to bootstrap a professional workstation; keep the file in a dotfiles repo.
- The Objective-See suite (LuLu, BlockBlock, OverSight, KnockKnock) is mandatory for a forensic analyst's Mac — both as defensive tools and as sources of investigative artifacts on examined machines.
- Most macOS artifacts (clipboard history, persistence logs, app databases) are SQLite files. TablePlus and DB Browser for SQLite make them accessible without writing queries.
- Replace three defaults immediately: QuickTime → IINA, `ls` → `eza`, built-in screenshots → Shottr.

---

## Terms introduced

**Brewfile** — A plain-text manifest of Homebrew formulae, casks, and taps; `brew bundle` installs everything in it.

**cask** — Homebrew's mechanism for installing macOS GUI apps distributed as `.dmg` or `.pkg` files, as opposed to `formula` (CLI tools compiled from source).

**DDC/CI** — Display Data Channel / Command Interface; a hardware protocol over DisplayPort/HDMI that allows the host to set monitor brightness, contrast, and input without OSD buttons.

**FSEvents** — Apple's kernel-level file system event notification API; used by Hazel, Pearcleaner's Sentinel, and many developer tools to watch directories for changes.

**Network Extension** — The post-kext mechanism for network filtering on macOS; allows apps like LuLu and Little Snitch to intercept connections without a kernel extension.

**SMC key** — System Management Controller register; AlDente writes to `BCLM` to cap battery charge.

**Virtual HID** — A software-emulated Human Interface Device; Karabiner creates a virtual keyboard device to intercept and rewrite keystrokes before the OS sees them.

---

## Further reading

- [Objective-See Tools](https://objective-see.org/tools.html) — full list with descriptions
- [AeroSpace documentation](https://nikitabobko.github.io/AeroSpace/guide) — config reference and i3 comparison
- [Ghostty documentation](https://ghostty.org/docs/install/binary) — install, config, and feature reference
- [Homebrew Bundle documentation](https://github.com/Homebrew/homebrew-bundle) — full Brewfile syntax including `mas`, `whalebrew`, and version pinning
- [Howard Oakley — The Eclectic Light Company](https://eclecticlight.co) — deep macOS internals; especially the security and TCC sections
- [[03-forensic-artifacts]] — where to find system artifacts on macOS; complements the forensics callouts throughout this lesson
- [[05-launchers-raycast-alfred]] — full Raycast and Alfred deep dive
- [[04-hazel-and-keyboard-maestro]] — full automation tools coverage
- [[06-text-expansion-and-clipboard]] — clipboard manager and text expansion depth
- [[02-tcc-and-privacy]] — TCC database internals and grant management
- [[08-screenshots-and-screen-recording]] — built-in screenshot capabilities before reaching for third-party tools
