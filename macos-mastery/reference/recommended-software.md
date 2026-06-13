---
title: Recommended Software
part: Reference
est_time: 20 min scan + ongoing reference
prerequisites: [part-03-cli/12-homebrew-and-package-management, part-09-apps/01-app-distribution-channels]
tags: [macos, software, homebrew, utilities, security, development, productivity]
---

# Recommended Software

> **In one sentence:** A curated, opinionated master list of the tools that transform a stock macOS install into a power-user workstation — organized by category, with install paths, pricing, and honest trade-off notes.

---

> **How to read this list:** Stars (★) mark **install-first essentials** — the 20% that deliver 80% of the value. Everything else is best-in-class for its niche; install what fits your workflow. The [Starter Brewfile](#starter-brewfile) at the bottom wires the stars together into a single paste-and-go script.

---

## Window Management

macOS ships with a surprisingly anemic window manager. Snap-to-half requires dragging all the way to the screen edge in macOS 26, and there is no built-in grid system at all.

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Raycast Window Management** | Free (built into Raycast) | via Raycast | Keyboard-driven halves/thirds/quarters/sixths; zero config if you already use Raycast |
| ★ **Rectangle Pro** | Free (Rectangle) / $9.99 one-time (Pro) | `brew install --cask rectangle-pro` | The gold standard; 200+ keyboard shortcuts, custom sizes, drag-to-snap zones, multi-display muscle memory, spectacle import |
| **Moom** | $9.99 one-time (MAS) | MAS or `brew install --cask moom` | Hover-snap with a visual grid; better for trackpad-first workflows |
| **Magnet** | $9.99 (MAS) | MAS | Simpler than Rectangle, popular with switchers; Rectangle Free is strictly better |
| **Amethyst** | Free / open-source | `brew install --cask amethyst` | Automatic tiling (i3/dwm-style); opinionated but powerful for keyboard-only dev work |
| **Yabai + skhd** | Free / open-source | `brew install koekeishiya/formulae/yabai skhd` | Full binary-space-partitioning tiling WM; requires disabling SIP for some features — serious power, serious commitment |

> 🪟 **Windows contrast:** Windows 11 Snap Layouts are built-in and well-integrated. On macOS you're buying this feature from a third party. Rectangle Free closes most of the gap for free.

---

## Launchers

Spotlight is the floor, not the ceiling. A real launcher rewires how you navigate the OS.

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Raycast** | Free (core) / $10/mo (Pro AI) | `brew install --cask raycast` | Replaces Spotlight + Alfred + clipboard manager + snippet expander + window manager in one extensible platform; plugin ecosystem is enormous; the default answer in 2026 |
| **Alfred 5** | Free (core) / £34 Powerpack one-time | `brew install --cask alfred` | Older, more mature workflow ecosystem; Powerpack unlocks file actions, clipboard history, snippets; preferred by those who've built complex Alfred workflows over years |
| **Spotlight** | Free (built-in) | built-in | Adequate for casual search; weak at app-specific actions and lacks clipboard history |

> 🔬 **Forensics note:** Spotlight's index lives at `/.Spotlight-V100/` (volume root) and `~/Library/Metadata/CoreSpotlight/`. Alfred and Raycast write history to `~/Library/Application Support/{Alfred,Raycast}/`. These can surface recently opened files and typed queries during an investigation.

---

## Clipboard Managers

The macOS clipboard holds exactly one item. This is the single biggest productivity hole in the default setup.

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Raycast Clipboard History** | Free (built-in to Raycast) | via Raycast | Searchable history, pinned clips, image clips, `Cmd+Shift+V` by default; good enough for most |
| **Pasta** | $4.99 (MAS) | MAS | Beautiful iOS-style stack UI; stacks clips in a visible column |
| **CopyClip 2** | $7.99 (MAS) | MAS | Lightweight pure clipboard history; menu-bar only; extremely low RAM footprint |
| **Klokki / Pasty** | Various | MAS | Niche alternatives; Raycast covers the use case unless you want a dedicated UI |

---

## Menu-Bar Managers

Apple's menu bar overflows on MacBooks with notches. You need a manager.

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Ice** (jordanbaird) | Free / open-source | `brew install --cask jordanbaird-ice` | Best free option; hide/show sections, drag-to-reorder, notch-aware "always visible" section, tint/border/shadow theming; GPL-3.0; macOS 14+ |
| **Bartender 5** | $16 one-time | `brew install --cask bartender` | The long-time standard; richer trigger rules (hide when condition), search, trigger on click; paid but polished; had a controversial ownership change in 2024 — audit before trusting |
| **Hidden Bar** | Free / open-source | `brew install --cask hiddenbar` | Minimalist — one divider, everything left of it hides; zero config; no macOS-version shenanigans |

> ⚠️ **Bartender ownership note:** Bartender 4 was sold to a new owner (Applause) in 2024 without public disclosure; scrutiny around the change led many users to switch to Ice. Ice is the safer open-source default.

---

## Automation & Macros

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Raycast** | Free | `brew install --cask raycast` | Snippets, clipboard actions, and custom scripts cover 70% of macro use cases |
| ★ **Karabiner-Elements** | Free / open-source | `brew install --cask karabiner-elements` | The deepest keyboard remapper on macOS — remap any key, create complex modifications (caps-lock → hyper key, dual-role keys), per-app rules; see [[part-02-gui]] for the kernel extension model |
| **Keyboard Maestro** | $36 one-time | `brew install --cask keyboard-maestro` | The automation powerhouse: GUI macros, clipboard transforms, web scraping, image recognition triggers, AppleScript/shell integration; for when Raycast scripts aren't enough |
| **BetterTouchTool** | $22 one-time (2-yr) / $12 upgrade | `brew install --cask bettertouchtool` | Trackpad gestures, Magic Mouse customization, window snapping, Touch Bar programming, custom keyboard shortcuts per-app; pairs well with Karabiner |
| **Shortcuts** | Free (built-in) | built-in | Apple's visual automation tool; good macOS 26 integration, siri integration, menu-bar shortcuts; limited compared to KM for complex flows but zero install friction |
| **Automator** | Free (built-in) | built-in | Legacy; use Shortcuts unless you need Watch Me Do or have existing Automator workflows |
| **Hammerspoon** | Free / open-source | `brew install --cask hammerspoon` | Lua-scriptable macOS automation bridge; can do everything BTT does, plus arbitrary Lua logic; steep learning curve, infinite power |

---

## Terminals

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Ghostty** | Free / open-source | `brew install --cask ghostty` | Native GPU-accelerated terminal written in Zig by Mitchell Hashimoto; fastest text rendering on Apple Silicon, native macOS feel, splits, tabs, configuration in `~/.config/ghostty/config`; the 2025–2026 default recommendation |
| **iTerm2** | Free / open-source | `brew install --cask iterm2` | Long-time gold standard; tmux integration, profiles, semantic history, shell integration scripts; slightly more feature-mature than Ghostty for edge cases |
| **Warp** | Free (core) / paid (AI features) | `brew install --cask warp` | Block-based terminal with AI command completion; requires account (privacy trade-off); polarizing but fast for AI-assisted workflows |
| **Terminal.app** | Free (built-in) | built-in | Reliable fallback; lacks splits, poor GPU rendering; sufficient for occasional use |
| **Alacritty** | Free / open-source | `brew install --cask alacritty` | Minimal GPU-accelerated; no tabs/splits natively (pairs with tmux); blazing fast |

> 🔬 **Forensics note:** iTerm2 and Terminal both write shell history to `~/.zsh_history` (or `~/.bash_history`); iTerm2 additionally stores command history per-profile in `~/Library/Application Support/iTerm2/`. Warp history is cloud-synced — a forensic distinction worth noting.

---

## Shells & Modern CLI Tools

The entire modern CLI stack belongs in `PATH`. These are the tools that make terminal work feel 10× faster. See [[part-03-cli/12-homebrew-and-package-management]] and [[part-03-cli/00-terminal-and-shells]] for deeper context.

### Shell

| Tool | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **zsh** | Free (built-in, macOS default) | built-in | Default since macOS 10.15; pairs with the tools below |
| **fish** | Free / open-source | `brew install fish` | Autosuggestions, syntax highlighting, and sensible defaults out of the box; non-POSIX — scripts won't be portable |

### Shell Enhancement

| Tool | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **Starship** | Free / open-source | `brew install starship` | Cross-shell prompt with git status, language versions, k8s context, AWS profile — zero-config baseline is excellent; `eval "$(starship init zsh)"` |
| ★ **zoxide** | Free / open-source | `brew install zoxide` | Smart `cd` replacement — learns your most-visited dirs; `z foo` jumps to the most frecent match; `zi` for interactive picker |
| **oh-my-zsh / Prezto** | Free | installer script | Plugin/theme frameworks; useful but can add 200–400ms startup; benchmark with `time zsh -i -c exit` |

### Replacement Core Utils

| Tool | Replaces | Install | Why you want it |
|------|----------|---------|-----------------|
| ★ **eza** | `ls` | `brew install eza` | Color-coded ls with git status, icons (`--icons`), tree mode (`--tree`), human sizes by default; `alias ls='eza --icons'` |
| ★ **bat** | `cat` | `brew install bat` | Syntax-highlighted file viewer with line numbers, git diff markers, pager integration; `alias cat='bat'` |
| ★ **ripgrep (`rg`)** | `grep` | `brew install ripgrep` | 3–10× faster than grep on real codebases; respects `.gitignore`; searches recursively by default; `rg 'pattern' path/` |
| ★ **fd** | `find` | `brew install fd` | Faster, friendlier `find`; `.gitignore`-aware; `fd pattern [dir]`; supports `-e` for extension filter |
| ★ **fzf** | (fuzzy finder) | `brew install fzf && $(brew --prefix)/opt/fzf/install` | Fuzzy-search anything piped to it; `Ctrl-R` history, `Ctrl-T` file picker, `Alt-C` dir jump; the glue that connects all the other tools |
| **delta** | `diff` / `git diff` pager | `brew install git-delta` | Side-by-side or unified diff with syntax highlighting and line numbers; set as `core.pager` in `.gitconfig` |
| **duf** | `df` | `brew install duf` | Human-readable disk usage with colorized table and mount-type grouping; `duf` |
| **dust** | `du` | `brew install dust` | Visual disk usage tree; `dust -d 3 ~` |
| **procs** | `ps` | `brew install procs` | Color-coded process list with tree view; `procs` |
| **bottom (`btm`)** | `top` / `htop` | `brew install bottom` | GPU/CPU/memory/disk/network monitor in one TUI; cross-platform; `btm` |
| **btop** | `top` | `brew install btop` | Beautiful resource monitor; simpler config than bottom; `btop` |
| **jq** | (JSON processor) | `brew install jq` | The essential JSON filter/transform tool; `curl -s url | jq '.items[].name'` |
| **yq** | (YAML/JSON processor) | `brew install yq` | jq but for YAML, TOML, XML; essential for k8s/CI config work |
| **httpie / xh** | `curl` (HTTP) | `brew install httpie` or `brew install xh` | Human-friendly HTTP client; `http GET api.example.com/users`; xh is a faster Rust rewrite |
| **tldr** | `man` (quick ref) | `brew install tldr` | Community-maintained practical examples for common commands; `tldr tar` beats `man tar` for 90% of lookups |
| **hyperfine** | (benchmarking) | `brew install hyperfine` | CLI benchmarking tool; `hyperfine 'rg pattern' 'grep -r pattern'` |
| **watchman** | `fsevents` polling | `brew install watchman` | Facebook's file-watching service; required by some React Native/Metro tooling |

### Git Tools

| Tool | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **gh** | Free / open-source | `brew install gh` | Official GitHub CLI — PRs, issues, actions, releases, gist, copilot from the terminal |
| **lazygit** | Free / open-source | `brew install lazygit` | TUI git client; stage hunks, squash commits, cherry-pick — all with keyboard |
| **git-lfs** | Free | `brew install git-lfs` | Large file storage extension; required for media-heavy repos |

---

## Editors & IDEs

| App | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **VS Code** | Free / open-source | `brew install --cask visual-studio-code` | Dominant general-purpose editor; best extension ecosystem; remote-SSH/container editing; pairs with Copilot |
| **Cursor** | Free (core) / $20/mo (Pro) | `brew install --cask cursor` | VS Code fork with AI pair programmer baked in; Claude + GPT-4o; if you're doing heavy AI-assisted coding this is the current default |
| **Zed** | Free / open-source | `brew install --cask zed` | Rust-written GPU-accelerated editor; native macOS, fast, collaborative editing; growing extension ecosystem |
| **Xcode** | Free (MAS) | MAS (large download; `xcode-select --install` for CLT only) | Required for Swift/ObjC/iOS/macOS native development; see [[part-07-development/00-xcode-demystified]] |
| **JetBrains IDEs** | $249/yr (all products) | `brew install --cask jetbrains-toolbox` | IntelliJ/PyCharm/GoLand/WebStorm — best-in-class for their languages; heavy RAM footprint |
| **Nova** | $99/yr | `brew install --cask nova` | Native macOS editor from Panic; beautiful, Swift-fast, good for web dev; underrated |
| **BBEdit** | Free (core) / $49.99 one-time | `brew install --cask bbedit` | Old-school macOS text editor; unmatched regex, grep-in-files, text transforms; indispensable for forensic text work |
| **Neovim** | Free / open-source | `brew install neovim` | Modal editor; steep curve, extreme power; pairs with LazyVim or Kickstart for sane defaults |
| **Helix** | Free / open-source | `brew install helix` | Modern modal editor written in Rust; LSP and tree-sitter built-in; alternative to Neovim for those who don't want Lua config |

---

## Git Clients (GUI)

| App | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| **Fork** | Free (trial) / $59.99 one-time | `brew install --cask fork` | Fast, well-designed native macOS git client; interactive rebase, blame, stash management |
| **Tower** | $79/yr | `brew install --cask tower` | The polished enterprise favorite; strong conflict resolution UX; good for onboarding teams |
| **Sourcetree** | Free | `brew install --cask sourcetree` | Atlassian's GUI client; free; good for Bitbucket shops; heavier than Fork |
| **GitHub Desktop** | Free / open-source | `brew install --cask github-desktop` | Simplified client; good for GitHub-only workflows; limited branching controls |

---

## Development Utilities

### Version Managers

| Tool | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **mise** (mise-en-place) | Free / open-source | `brew install mise` | Single tool to manage Node, Python, Ruby, Go, Java, Rust, and 100+ more runtimes; per-project `.mise.toml`; replaces nvm + pyenv + rbenv + asdf; 7× faster than asdf; `mise doctor` verifies setup |
| **pyenv** | Free / open-source | `brew install pyenv` | Python-only; still useful if you prefer dedicated tools; `pyenv install 3.12.3` |
| **nvm** | Free / open-source | `brew install nvm` | Node-only; slows shell startup unless lazy-loaded; mise is the better default |

### Containers & VMs

| App | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **OrbStack** | Free (personal) / $8/mo (Pro) | `brew install --cask orbstack` | Replaces Docker Desktop — lighter, faster, native Apple Silicon support; also runs Linux VMs (Ubuntu, etc.); `orb` CLI; integrates with Docker socket transparently |
| **Docker Desktop** | Free (personal) / paid (enterprise) | `brew install --cask docker` | The incumbent; heavier VM layer; OrbStack is strictly better on Apple Silicon |
| **UTM** | Free / open-source ($9.99 MAS convenience) | `brew install --cask utm` | QEMU frontend for macOS; run Windows ARM, Linux, ancient x86; the go-to for forensic VM work |
| **Parallels Desktop** | $99.99/yr | `brew install --cask parallels` | Best Windows ARM performance; instant resume; expensive; justified for heavy Windows-in-macOS workflows |

### Database Clients

| App | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **TablePlus** | Free (limited) / $89 one-time | `brew install --cask tableplus` | Native macOS feel; supports SQLite, PostgreSQL, MySQL, Redis, DynamoDB, and more; the default recommendation |
| **DBngin** | Free | `brew install --cask dbgenie` | One-click local PostgreSQL/MySQL/Redis without Docker; pairs beautifully with TablePlus |
| **Sequel Pro / Sequel Ace** | Free / open-source | `brew install --cask sequel-ace` | MySQL-focused; the maintained fork of the classic Sequel Pro |
| **DBeaver** | Free / open-source | `brew install --cask dbeaver-community` | Cross-platform; best for enterprise DBs (Oracle, MSSQL, Snowflake); heavy Java UI |

### API & Network Proxy Tools

| App | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **Bruno** | Free / open-source | `brew install --cask bruno` | Local-first API client (stores collections as plain files in git); replaces Postman without the cloud lock-in |
| **Proxyman** | Free (core) / $89 one-time | `brew install --cask proxyman` | macOS-native HTTP proxy/sniffer; intercept and edit traffic from apps and simulators; essential for iOS/macOS app dev and security testing |
| **Paw / RapidAPI** | $19.99/mo | `brew install --cask rapidapi` | Polished Mac-native API client; supports GraphQL, gRPC; good for design-first workflows |
| **mitmproxy** | Free / open-source | `brew install mitmproxy` | CLI+web-UI HTTP(S) proxy; scriptable with Python; essential forensics/security tool; see [[part-05-security-forensics/05-firewall-and-network-security]] |

---

## Notes & Knowledge Management

| App | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| ★ **Obsidian** | Free (personal) / $50/yr (commercial) | `brew install --cask obsidian` | Local-first Markdown knowledge base; backlinks, graph view, canvas, plugins; this curriculum was built to sync into it |
| **Key Obsidian Plugins** | Free (community) | via Obsidian plugin browser | See table below |
| **Notion** | Free / $10/mo+ | browser or `brew install --cask notion` | Online-first; better for shared team wikis; weaker for personal local knowledge |
| **Bear** | Free (core) / $2.99/mo | MAS | Beautiful native Markdown notes; iCloud sync; good for quick capture; weak linking |
| **Craft** | Free (core) / $5/mo | `brew install --cask craft` | Block-based, iCloud-native; great design; less powerful than Obsidian for networked thought |

### Essential Obsidian Plugins

| Plugin | Why |
|--------|-----|
| **Dataview** | Query your vault as a database — `TABLE`, `LIST`, `TASK` queries over frontmatter |
| **Templater** | Powerful template engine (variables, date functions, scripts) — replaces core Templates |
| **Calendar** | Daily-note calendar sidebar |
| **Tasks** | Cross-vault task tracking with due dates, recurrence, filters |
| **QuickAdd** | Fast note creation from predefined templates; pairs with Templater |
| **Git** | Auto-commit vault to a git repo on a schedule |
| **Excalidraw** | Infinite canvas whiteboard inside Obsidian |
| **Advanced Tables** | Live Markdown table editing with tab-navigation |
| **Omnisearch** | Full-text search with fuzzy matching across the vault |

---

## Browsers & Extensions

| App | Pricing | Install | Why you want it |
|------|---------|---------|-----------------|
| **Safari** | Free (built-in) | built-in | Best Apple Silicon performance, lowest battery drain; WebKit; good privacy defaults; limited extension ecosystem |
| ★ **Arc** | Free | `brew install --cask arc` | Chromium-based; spaces, sidebar tabs, command bar; the productivity-focused default for many power users; made by The Browser Company |
| **Zen Browser** | Free / open-source | `brew install --cask zen-browser` | Firefox-based; privacy-first; vertical tabs; Firefox extension ecosystem |
| **Firefox** | Free / open-source | `brew install --cask firefox` | Best extension ecosystem for privacy tools; essential for web dev cross-browser testing |
| **Chrome** | Free | `brew install --cask google-chrome` | Required for DevTools work that targets Chrome; avoid as daily driver for privacy reasons |

### Essential Extensions (Chrome/Firefox/Arc)

| Extension | Why |
|-----------|-----|
| ★ **uBlock Origin** | Best-in-class ad/tracker blocker; filter list driven; lightweight; use the Firefox version — Chrome's Manifest V3 neutered its capabilities |
| **1Password** | Browser integration for the password manager |
| **Bitwarden** | Open-source password manager browser integration |
| **Vimium / Vimium-C** | Vim keybindings for browser navigation; zero mouse browsing |
| **Dark Reader** | System-wide dark mode for any website |
| **SponsorBlock** | Skip sponsor segments in YouTube videos |
| **Privacy Badger** | EFF's tracker blocker; learning-based; complements uBlock |

---

## Security & Privacy

See [[part-05-security-forensics/00-the-security-model]] and [[part-05-security-forensics/07-hardening-playbook]] for the full threat model context.

### Firewall & Network Monitoring

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Little Snitch 6** | €59 one-time | `brew install --cask little-snitch` | The definitive macOS egress firewall; per-process, per-host, per-port rules; network map; connection history; essential for detecting unexpected call-home behavior. Different from Objective-See — this is Objective Development Software GmbH |
| **LuLu** (Objective-See) | Free / open-source | `brew install --cask lulu` | Free outbound-only firewall; simpler than Little Snitch; good default for users who don't need per-host granularity |
| **mitmproxy** | Free / open-source | `brew install mitmproxy` | CLI HTTP/S intercepting proxy; script with Python; indispensable for app traffic analysis |

### Objective-See Suite

Patrick Wardle's free security tools — essential for any forensics-minded user. All free, open-source.

| Tool | Install | What it does |
|------|---------|--------------|
| ★ **KnockKnock** | [objective-see.org](https://objective-see.org/tools.html) | Scans for persistently installed software — launch agents/daemons, login items, browser extensions, kexts; flags unknowns |
| ★ **BlockBlock** | objective-see.org | Real-time monitor — alerts whenever anything attempts to install a persistent component |
| **RansomWhere?** | objective-see.org | Detects ransomware-like behavior (mass file encryption by untrusted processes) |
| **TaskExplorer** | objective-see.org | Visual process explorer with VirusTotal integration; deeper than Activity Monitor |
| **ProcessMonitor** | objective-see.org | Real-time process event monitor; logs fork/exec/exit; pairs with FileMonitor |
| **FileMonitor** | objective-see.org | Real-time file system event monitor; catch what's touching what |
| **DoNotDisturb** | objective-see.org | Detects physical access (Evil Maid) by alerting on lid-open events when screen is locked |
| **Netiquette** | objective-see.org | Network connections viewer with process attribution; lightweight LittleSnitch complement |

> 🔬 **Forensics note:** KnockKnock and BlockBlock between them cover the persistence mechanisms described in [[part-05-security-forensics/06-malware-xprotect-persistence]]. Running KnockKnock on an acquired volume (with `-path /Volumes/target`) produces an artifact inventory without modifying the target.

### Password Managers

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **1Password 8** | $3/mo (individual) | `brew install --cask 1password` | The gold standard; native macOS app; SSH agent integration (`1Password SSH Agent`), CLI (`op`), developer secrets management; see [[part-05-security-forensics/04-keychain-and-secrets]] |
| **Bitwarden** | Free (core) / $10/yr (Premium) | `brew install --cask bitwarden` | Open-source; self-hostable; best free option; browser extensions excellent |
| **KeePassXC** | Free / open-source | `brew install --cask keepassxc` | Fully local; `.kdbx` format; no cloud; for air-gapped or ultra-paranoid setups |

### Encryption & Privacy

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Cryptomator** | Free / open-source ($14.99 MAS convenience) | `brew install --cask cryptomator` | Client-side AES-256 encryption for cloud storage vaults; transparent virtual drive; see [[part-05-security-forensics/01-filevault-and-encryption]] |
| **GPG Suite** | Free (core) / $49 (Support Plan) | `brew install --cask gpg-suite` | GPG key management, macOS Mail integration, `gpg` CLI; required for signed git commits and encrypted email |
| **Tailscale** | Free (personal) / paid (teams) | `brew install --cask tailscale` | Zero-config WireGuard mesh VPN; connect your devices securely without port-forwarding; the modern alternative to traditional VPNs |
| **Mullvad VPN** | ~$5.50/mo | `brew install --cask mullvad-vpn` | Privacy-first VPN; no-logs, WireGuard; accepts cash/Monero; audited |
| **ProtonVPN** | Free (limited) / $10/mo | `brew install --cask protonvpn` | Open-source apps, audited, Swiss jurisdiction; good free tier |

---

## Backup

Three copies, two media, one off-site. See [[part-04-maintenance]] for the full backup strategy.

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Time Machine** | Free (built-in) | built-in | The mandatory baseline; hourly snapshots to external drive or NAS; APFS snapshots; zero excuse not to run it |
| ★ **Carbon Copy Cloner (CCC)** | $49.99 one-time | `brew install --cask carbon-copy-cloner` | Bootable clone maker; scheduled smart updates; SafetyNet recycle bin; better than SuperDuper for power users; macOS 26 compatible |
| **SuperDuper!** | Free (basic) / $35 one-time | `brew install --cask superduper` | Simpler than CCC; reliable bootable clone alternative |
| ★ **Backblaze** | $9/mo (Personal) / $9/mo (B2) | `brew install --cask backblaze` | Unlimited continuous cloud backup of your entire drive; set-and-forget; the off-site copy; alternatively use B2 with restic for CLI control |
| **Arq 7** | $49.99 one-time | `brew install --cask arq` | Backs up to your own cloud storage (S3, B2, Google Drive, local); encrypted; versioned; you own the destination |
| **restic** | Free / open-source | `brew install restic` | CLI backup tool; deduplicating, encrypted, fast; backs up to S3/B2/SFTP/local; scriptable; the forensics-friendly option — you control every byte |
| **Borg / borgmatic** | Free / open-source | `brew install borgbackup borgmatic` | Deduplicating encrypted backup; `borgmatic` adds config-driven scheduling; more mature than restic for some workflows |

> 🪟 **Windows contrast:** Windows has File History + Backup and Restore but nothing as integrated as Time Machine's APFS snapshotting. Backblaze and restic work on both platforms — a cross-platform backup strategy is portable.

---

## Disk & Cleanup

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **DaisyDisk** | $9.99 (MAS) | MAS or `brew install --cask daisydisk` | Sunburst visualization of disk usage; fast scan; drag files to a collector and delete in one action; the most pleasant large-file hunter |
| **GrandPerspective** | Free / open-source ($2.99 MAS convenience) | `brew install --cask grandperspective` | Treemap visualization; faster than DaisyDisk on huge volumes; free; less polished |
| ★ **Pearcleaner** | Free / open-source | `brew install --cask pearcleaner` | App uninstaller; finds all associated files (caches, preferences, containers, support files); Homebrew integration; 11k stars; Swift/SwiftUI; **strictly better than AppCleaner** in 2026 |
| **AppCleaner** | Free | `brew install --cask appcleaner` | Older drag-to-uninstall tool; still works; Pearcleaner covers more surface area |
| **OmniDiskSweeper** | Free | direct download | Bare-bones size-sorted file tree; useful for quick CLI-like disk archaeology |

> ⚠️ **Avoid CleanMyMac X and similar "Mac cleaner" products.** They are marketed aggressively, expensive, often include unnecessary real-time scanning that adds overhead, and historically have included adware-style components. The FOSS tools above (Pearcleaner, GrandPerspective) handle every legitimate use case for free. "Safe cleaner" snake oil preys on Windows-switcher anxiety about "cleaning" an OS that doesn't need it.

> 🔬 **Forensics note:** DaisyDisk and GrandPerspective scan file sizes but don't delete metadata trails. Use `mdimport -L` to check what Spotlight has indexed about a file after deletion. Deleted app containers may linger under `~/Library/Containers/` with the bundle ID as the folder name even after the app is gone.

---

## Media & Creative

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **IINA** | Free / open-source | `brew install --cask iina` | Native macOS media player built on mpv; supports every format; picture-in-picture; online subtitles; the correct media player for macOS |
| **VLC** | Free / open-source | `brew install --cask vlc` | The universal fallback; uglier than IINA; handles more edge-case codecs; good for forensic playback of unusual media formats |
| ★ **HandBrake** | Free / open-source | `brew install --cask handbrake` | Video transcoder; H.265/HEVC, AV1, HLS; VideoToolbox hardware encoding on Apple Silicon; batch mode |
| ★ **ffmpeg** | Free / open-source | `brew install ffmpeg` | The universal audio/video Swiss Army knife; `ffmpeg -i in.mov -c:v libx264 out.mp4`; used by HandBrake, yt-dlp, everything else |
| ★ **exiftool** | Free / open-source | `brew install exiftool` | Read/write/strip metadata from photos, videos, PDFs, Office docs; `exiftool -all= file.jpg` strips all EXIF; essential for forensics and OPSEC |
| ★ **yt-dlp** | Free / open-source | `brew install yt-dlp` | Download video/audio from YouTube, Vimeo, Twitter, 1000+ sites; `yt-dlp -f 'bestvideo+bestaudio' URL`; replaces deprecated youtube-dl |
| **ImageMagick** | Free / open-source | `brew install imagemagick` | CLI image conversion, resize, composite, annotate; `convert in.png -resize 50% out.png` |
| **Affinity Photo 2** | $69.99 one-time | MAS | Photoshop alternative; native Apple Silicon; one-time purchase (no subscription); layer-based, RAW editing, 32-bit |
| **Affinity Designer 2** | $69.99 one-time | MAS | Illustrator alternative; vector + raster; one-time purchase; best value in professional creative tools |
| **Pixelmator Pro** | $49.99 one-time | MAS | Native macOS image editor; ML-powered tools; excellent for photo editing without the Affinity suite complexity |
| **Permute 3** | $14.99 (MAS) | MAS | Dead-simple drag-and-drop media converter; non-technical users; under the hood calls ffmpeg |

---

## Screenshots & Screen Recording

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **CleanShot X** | $29 one-time / included in Setapp | `brew install --cask cleanshot` | All-in-one screenshot + screen recording + GIF + OCR + scrolling capture + annotation + cloud share; the professional default; `Cmd+Shift+2` workflow is polished |
| **Shottr** | $12 one-time (30-day free trial) | `brew install --cask shottr` | Lightweight, fast; pixel-level measurement tools (ruler, spacing, color picker), OCR; wins for developers who measure UI; lacks screen recording |
| **macOS native** | Free (built-in) | `Cmd+Shift+3/4/5` | Adequate for basic captures; `Cmd+Shift+5` added screen recording in 10.15; no annotation, no cloud |

> **Recommendation:** CleanShot X if you want one tool for everything. Shottr if you're a developer who needs pixel measurements and doesn't need recording.

---

## System Monitoring

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Stats** | Free / open-source | `brew install --cask stats` | Menu-bar system monitor — CPU, GPU, RAM, disk, network, battery, temperatures; highly configurable; the free default |
| **iStatMenus** | $11.99/yr (or one-time) | `brew install --cask istatmenus` | The polished paid alternative to Stats; richer historical graphs; notification triggers; weather; slightly more reliable temperature readings |
| **Activity Monitor** | Free (built-in) | built-in | The built-in truth; when something is slow, `Activity Monitor → Energy` is ground truth; `btop`/`btm` in terminal for deeper analysis |

---

## Display & Battery Management

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **MonitorControl** | Free / open-source | `brew install --cask monitorcontrol` | Control external monitor brightness and volume via DDC/CI from your keyboard; 29k+ stars; essential for anyone with an external display |
| ★ **AlDente** | Free (core) / $25 one-time (Pro) | `brew install --cask aldente` | Set a charging ceiling (e.g. 80%) to reduce lithium battery degradation; prevents the battery staying at 100% while plugged in; the correct tool for laptop longevity |
| **Lunar** | Free (core) / $23 one-time | `brew install --cask lunar` | Advanced display brightness control with DDC, location-adaptive dimming, and "faux HDR" mode; more features than MonitorControl at the cost of complexity |

> 🔬 **Forensics note:** Battery cycle count and manufacture date are readable via `ioreg -rn AppleSmartBattery | grep -E 'CycleCount|ManufactureDate'`. AlDente's charging log is at `~/Library/Application Support/AlDente/logs/`.

---

## Archives & Compression

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| ★ **Keka** | Free (direct) / $4.99 (MAS) | `brew install --cask keka` | Native macOS archive manager; 7z, RAR, ZIP, tar, brotli, zstd, ISO; the recommended default |
| **The Unarchiver** | Free (MAS) | MAS | Simple extraction-only tool; handles almost any format; no compression; set as default for double-click extraction |
| **BetterZip 5** | $24.95 one-time | `brew install --cask betterzip` | Preview archive contents before extracting; niche but useful |
| **p7zip / 7zz** | Free / open-source | `brew install sevenzip` | CLI 7-Zip; `7zz a archive.7z folder/`; maximum compression ratios; `7zz l archive.rar` lists RAR contents without GUI |

---

## Productivity & Planning

| App | Pricing | Install | Why you want it |
|-----|---------|---------|-----------------|
| **Fantastical** | $4.75/mo | `brew install --cask fantastical` | The best calendar app for macOS; natural language input ("Lunch with Bob Friday at noon"), menu-bar mini-calendar, tasks + reminders + events unified |
| **Mimestream** | $4.99/mo | `brew install --cask mimestream` | Native Gmail client for macOS; not an IMAP wrapper — uses Gmail API directly; much faster than Gmail in a browser |
| **Spark** | Free (core) / $7.99/mo (Pro) | `brew install --cask spark-desktop` | Email client with smart inbox, team collaboration, email scheduling |
| **Things 3** | $49.99 one-time (MAS) | MAS | The cleanest GTD task manager for Apple platforms; beautiful; opinionated structure (Areas → Projects → Tasks → Checklists) |
| **OmniFocus 4** | $49.99/yr | `brew install --cask omnifocus` | The power-user GTD system; custom perspectives, forecast, Shortcuts integration; more complex than Things |
| **Lungo** | $4.99 (MAS) | MAS | Keep your Mac awake (blocks sleep); simpler than `caffeinate`; menu-bar toggle |

---

## Starter Brewfile

Drop this in `~/Brewfile` and run `brew bundle` to install the essentials in one shot. Customise freely — comment out anything you don't want.

```ruby
# ~/Brewfile  —  macOS Power User Starter Kit
# Usage: brew bundle  (installs everything below)
# Update: brew bundle --cleanup  (also removes unlisted packages)

tap "homebrew/cask-fonts"
tap "koekeishiya/formulae"           # yabai / skhd if you want tiling

# ── Homebrew formulae (CLI tools) ─────────────────────────────────────────────

# Shell & prompt
brew "zoxide"
brew "starship"
brew "fzf"                           # run: $(brew --prefix)/opt/fzf/install

# Modern core utils
brew "eza"
brew "bat"
brew "ripgrep"
brew "fd"
brew "git-delta"
brew "duf"
brew "dust"
brew "bottom"
brew "btop"

# Data & network
brew "jq"
brew "yq"
brew "xh"                            # fast httpie alternative
brew "tldr"
brew "hyperfine"

# Git & GitHub
brew "gh"
brew "lazygit"
brew "git-lfs"

# Development toolchain
brew "mise"
brew "ffmpeg"
brew "exiftool"
brew "yt-dlp"
brew "imagemagick"
brew "mitmproxy"
brew "restic"
brew "gpg"
brew "sevenzip"                      # 7zz CLI

# Security / forensics
brew "nmap"
brew "tcpdump"

# ── Homebrew casks (GUI apps) ─────────────────────────────────────────────────

# Terminal & editors
cask "ghostty"                       # or iterm2
cask "visual-studio-code"

# Launcher & clipboard
cask "raycast"

# Window management
cask "rectangle-pro"                 # or just "rectangle" for free tier

# Menu bar
cask "jordanbaird-ice"

# Keyboard
cask "karabiner-elements"

# Containers & VMs
cask "orbstack"
cask "utm"                           # for forensic VMs

# Database
cask "tableplus"
cask "dbgenie"                       # local Postgres/MySQL/Redis

# API tools
cask "bruno"                         # local-first API client
cask "proxyman"                      # HTTP proxy/sniffer

# Backup
cask "carbon-copy-cloner"

# Disk tools
cask "daisydisk"
cask "pearcleaner"

# Media
cask "iina"
cask "vlc"
cask "handbrake"

# Screenshots
cask "cleanshot"                     # or "shottr"

# System monitoring
cask "stats"

# Display & battery
cask "monitorcontrol"
cask "aldente"

# Archives
cask "keka"
cask "the-unarchiver"

# Notes
cask "obsidian"

# Security
cask "lulu"                          # upgrade: little-snitch
cask "cryptomator"
cask "tailscale"

# Password manager
cask "1password"                     # or "bitwarden"

# Git GUI
cask "fork"

# Fonts (optional but nice in terminal)
cask "font-jetbrains-mono-nerd-font" # for starship + eza --icons

# ── Mac App Store (requires `brew install mas`) ───────────────────────────────

brew "mas"

# mas "Fantastical", id: 975937182
# mas "Things 3",    id: 904280696
# mas "Mimestream",  id: 1494392782   # check current MAS ID before using
# mas "Lungo",       id: 1263070803
```

**After `brew bundle`:**

```zsh
# Activate fzf shell integration
$(brew --prefix)/opt/fzf/install --all

# Activate mise (add to ~/.zshrc)
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc

# Activate zoxide (add to ~/.zshrc)
echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc

# Activate starship (add to ~/.zshrc)
echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# Useful aliases to add to ~/.zshrc
echo "alias ls='eza --icons --group-directories-first'" >> ~/.zshrc
echo "alias ll='eza --icons -la --group-directories-first'" >> ~/.zshrc
echo "alias cat='bat'" >> ~/.zshrc
echo "alias find='fd'" >> ~/.zshrc
echo "alias grep='rg'" >> ~/.zshrc

source ~/.zshrc
```

---

## Quick-Reference: Install-First Essentials

If you're setting up a new machine and have ten minutes, install these first:

| Priority | App | Command |
|----------|-----|---------|
| 1 | Homebrew | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| 2 | Raycast | `brew install --cask raycast` |
| 3 | Modern CLI stack | `brew install eza bat ripgrep fd fzf zoxide starship git-delta` |
| 4 | Rectangle Pro / Ice | `brew install --cask rectangle-pro jordanbaird-ice` |
| 5 | Ghostty | `brew install --cask ghostty` |
| 6 | 1Password | `brew install --cask 1password` |
| 7 | LuLu or Little Snitch | `brew install --cask lulu` |
| 8 | Karabiner-Elements | `brew install --cask karabiner-elements` |
| 9 | AlDente | `brew install --cask aldente` (laptops only) |
| 10 | Pearcleaner + DaisyDisk | `brew install --cask pearcleaner daisydisk` |

---

## Further Reading

- [[part-03-cli/12-homebrew-and-package-management]] — deep dive into Homebrew internals, taps, cask mechanics
- [[part-03-cli/00-terminal-and-shells]] — shell setup and configuration
- [[part-05-security-forensics/07-hardening-playbook]] — applying the security tools above systematically
- [[part-07-development/06-dev-package-managers]] — mise, pyenv, nvm, and version manager theory
- [[part-07-development/08-containers-and-vms]] — OrbStack and UTM deep dive
- [[part-09-apps/01-app-distribution-channels]] — App Store vs Homebrew vs direct: signing, trust, and update channels
- [Objective-See Tools](https://objective-see.org/tools.html) — Patrick Wardle's full suite
- [Homebrew Bundle docs](https://github.com/Homebrew/homebrew-bundle) — `brew bundle` options, `--force`, `--no-upgrade`
- [mise documentation](https://mise.jdx.dev/) — polyglot version manager reference
- [Howard Oakley's Eclectic Light Company](https://eclecticlight.co) — deep macOS internals; essential for understanding what these tools touch at the OS level
