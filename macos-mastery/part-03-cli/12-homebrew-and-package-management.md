---
title: Homebrew & package management
part: P03 CLI
est_time: 50 min read + 40 min labs
prerequisites: [00-terminal-and-shells, 01-zsh-deep-dive, 04-filesystem-layout-and-domains, 05-launchd-and-the-launch-system]
tags: [macos, homebrew, package-management, macports, nix, mas, cli]
---

# Homebrew & package management

> **In one sentence:** Homebrew is the de-facto package manager for macOS — understand its architecture (Cellar, taps, formulae vs. casks, bottles, services) to install, audit, and reproduce your environment with precision, then know when MacPorts, nix, or `mas` is the right tool instead.

## Why this matters

macOS ships without a package manager. Apple provides a rich framework layer but deliberately excludes the Unix userland toolchain (gcc, wget, ffmpeg, PostgreSQL, ripgrep…) from the base OS. Every macOS developer and power user ends up solving this the same way: Homebrew.

For a forensic investigator or software builder, Homebrew is not just convenience — it is **infrastructure state**. A Brewfile is a deterministic machine specification. `brew doctor` reveals mismatched SDKs, stale symlinks, and permission landmines that explain otherwise-mysterious build failures. `brew services` is a thin launchd shim you will use constantly. And knowing the Cellar layout means you can pinpoint exactly which binary version is active, or trace an artifact back to its package.

> 🪟 **Windows contrast:** Windows has `winget` (built-in since Windows 11), `Chocolatey`, and `Scoop`. All three use `%ProgramData%` or user-scope install roots. None has Homebrew's depth of integration with macOS conventions (bottles, taps, cask quarantine, launchd service wrappers). `winget` is closest in philosophy: official, built-in, Microsoft-backed. `Scoop` is closest to Homebrew's "installs into a prefix, no sudo" model.

---

## Concepts

### 1. The Homebrew prefix: Apple Silicon vs Intel

| Architecture | Prefix | Why |
|---|---|---|
| Apple Silicon (M-series) | `/opt/homebrew` | `/opt` is SIP-protected at root but the `/opt/homebrew` subtree is not system-owned; keeps the arm64 userland cleanly separate from Rosetta paths |
| Intel (x86_64) | `/usr/local` | Historical convention; BSD systems traditionally used `/usr/local` for admin-installed software |
| Rosetta 2 emulated Homebrew | `/usr/local` | You *can* run an Intel Homebrew under Rosetta for packages not yet ported to arm64, but this is now rare |

On Apple Silicon, `/opt/homebrew/bin` is **not in the default PATH** for any shell — not in `/etc/paths`, not in the default `zsh` environment. The Homebrew installer adds this line to `~/.zprofile`:

```zsh
eval "$(/opt/homebrew/bin/brew shellenv)"
```

`brew shellenv` emits `export` statements for `PATH`, `MANPATH`, `INFOPATH`, `HOMEBREW_PREFIX`, `HOMEBREW_CELLAR`, `HOMEBREW_REPOSITORY`, and `HOMEBREW_SHELLENV_PREFIX`. Sourcing it at login-shell time (`.zprofile`) rather than every interactive shell (`.zshrc`) is intentional — login shells run for GUI apps launched from Spotlight/Dock, SSH sessions, and `su -`. See [[01-zsh-deep-dive]] for the startup-file execution order.

```zsh
# Verify your active prefix
brew --prefix          # /opt/homebrew  (Apple Silicon)
brew --cellar          # /opt/homebrew/Cellar
brew --repository      # /opt/homebrew  (same on AS; differs on old Intel setups)
```

> 🔬 **Forensics note:** The prefix tells you which architecture of Homebrew is active. A machine with *both* `/opt/homebrew` and `/usr/local` prefixes populated has two separate Homebrew installations — common on machines migrated from Intel or developers running fat CI environments. Each prefix has its own `Cellar`, `Caskroom`, and tap checkout.

### 2. Directory anatomy

```
/opt/homebrew/
├── bin/              → symlinks to installed formula binaries
├── lib/              → symlinks to installed libraries
├── include/          → symlinks to headers
├── Cellar/           ← ACTUAL install location for formulae
│   ├── ripgrep/
│   │   └── 14.1.1/
│   │       ├── bin/rg
│   │       └── share/man/man1/rg.1
│   └── openssl@3/
│       └── 3.4.1/
│           ├── bin/
│           ├── lib/
│           └── include/
├── Caskroom/         ← installed casks (GUI apps, fonts, etc.)
│   ├── firefox/
│   │   └── 126.0/
│   │       └── Firefox.app   (or a stager receipt for installer-casks)
│   └── font-jetbrains-mono/
│       └── 2.304/
├── Frameworks/
├── Library/
│   ├── Homebrew/     ← Homebrew Ruby source
│   ├── Taps/         ← git checkouts of taps
│   │   ├── homebrew/
│   │   │   ├── homebrew-core/   ← the main formula database
│   │   │   ├── homebrew-cask/   ← the main cask database
│   │   │   └── homebrew-services/
│   │   └── <user>/<tap-name>/
│   └── Locks/
└── var/
    └── homebrew/
        └── linked/   ← records of keg-linked packages
```

**Key insight:** Homebrew never actually installs anything *into* `/opt/homebrew/bin` — it installs into the versioned Cellar keg and symlinks into the bin/lib/include tree. Running `ls -l /opt/homebrew/bin/rg` shows the symlink chain: `bin/rg → ../Cellar/ripgrep/14.1.1/bin/rg`.

> 🔬 **Forensics note:** The Cellar preserves **multiple versions** simultaneously. Only one is *linked* (symlinked into the bin tree) at a time. `brew switch <formula> <version>` (now `brew link --overwrite <formula>@<version>`) changes which is active without installing anything new. An investigator can determine exact past versions by listing Cellar subdirectories.

### 3. Formulae vs. Casks

| Dimension | Formula | Cask |
|---|---|---|
| What it installs | CLI tool, library, or daemon | GUI `.app`, font, driver, browser plugin, system extension |
| Mechanism | Downloads source or pre-compiled bottle; links into `/opt/homebrew` | Downloads `.dmg`, `.pkg`, `.zip`, or `.app`; uses cask stager to install |
| Binary format | arm64 native bottles from Homebrew's bottle servers | Whatever the upstream vendor ships |
| Install location | `/opt/homebrew/Cellar/<name>/<version>/` | `/Applications/` or `~/Applications/`; metadata in `/opt/homebrew/Caskroom/<name>/<version>/` |
| Dependency resolution | Full recursive resolution | Minimal (can depend on formulae) |
| Flag to force | `--formula` | `--cask` |

Casks that install `.pkg`-based tools (e.g., printer drivers, kernel extensions) can trigger admin prompts. The cask itself runs a `postflight` or `pkg` artifact installer via Homebrew's Ruby stager, which calls `installer -pkg` under the hood.

**Quarantine:** Homebrew automatically removes the `com.apple.quarantine` extended attribute from cask `.app` bundles after download, which is why apps installed via Homebrew launch without the "downloaded from the internet" Gatekeeper prompt. (See [[08-security-architecture]] for the full quarantine/Gatekeeper flow.)

### 4. Taps

A **tap** is a git repository containing additional formulae and/or casks beyond `homebrew/core` and `homebrew/cask`. The naming convention is `<github-user>/<repo>` where the repo is named `homebrew-<tapname>`, so `brew tap homebrew/services` clones `github.com/Homebrew/homebrew-services`.

```zsh
brew tap                          # list active taps
brew tap <user>/<repo>            # add a tap
brew tap <user>/<repo> <url>      # add from non-GitHub URL
brew untap <user>/<repo>          # remove a tap
```

Common taps:
- `homebrew/core` — built-in, ~7,000 formulae
- `homebrew/cask` — built-in, ~5,000 casks
- `homebrew/cask-fonts` — ~1,500 Nerd Fonts, developer fonts
- `homebrew/cask-versions` — alternate versions (firefox@esr, java@17, etc.)
- `homebrew/services` — the `brew services` subcommand
- `nicoverbruggen/homebrew-cask` — tools that can't be in the official cask repo

### 5. Bottles

A **bottle** is a pre-compiled binary tarball hosted on GitHub Packages / ghcr.io. When you `brew install ripgrep`, Homebrew fetches the arm64 bottle rather than compiling from source. Bottles are tagged by macOS version and architecture.

Force a source build: `brew install --build-from-source <formula>`

Why you might do this: applying a patch, enabling compile-time options the bottle doesn't include, or building a formula whose bottle isn't available for your OS version yet.

### 6. Services (the launchd wrapper)

`brew services` is Homebrew's wrapper around `launchctl`/launchd. It manages formulae that ship a launchd plist (stored at `<formula-prefix>/homebrew.mxcl.<name>.plist` or in `Library/LaunchAgents/`).

```zsh
brew services list                # show all registered services + status
brew services start postgresql@16 # load & enable at login (user domain)
brew services stop postgresql@16
brew services restart nginx
brew services run nginx           # start once without enabling at login
brew services info nginx          # show plist path + status
```

`brew services start` copies or symlinks the plist into `~/Library/LaunchAgents/` and calls `launchctl bootstrap gui/$(id -u) <plist>`. This is a **user-scoped** service — it runs as your user, not root, and starts when you log in. To run as root (system-wide), prefix with `sudo`:

```zsh
sudo brew services start nginx    # → /Library/LaunchDaemons/ → root-owned daemon
```

> 🔬 **Forensics note:** `brew services list` is a quick triage tool when investigating persistent processes. Any entry with status `started` has a corresponding plist in `~/Library/LaunchAgents/` or `/Library/LaunchDaemons/`. Cross-reference against `launchctl list | grep homebrew` for the ground truth. Malware sometimes disguises itself with `.mxcl`-style plist names. See [[05-launchd-and-the-launch-system]] for the full launch system anatomy.

### 7. Analytics opt-out

Homebrew collects installation analytics by default (formula names, OS version, CPU type) and sends them to a Google Analytics endpoint. To opt out:

```zsh
brew analytics off
# Or set in environment:
export HOMEBREW_NO_ANALYTICS=1   # add to .zshrc or .zprofile
```

The analytics state is stored in `~/.homebrew/analytics/` (or `$(brew --repository)/.git/COMMIT_EDITMSG` metadata). Verify with `brew analytics`.

> 🔬 **Forensics note:** The analytics mechanism sends the Homebrew prefix path and install events. On a forensic image, the presence of Homebrew and which formulae were installed most recently can be inferred from the Cellar mtime tree and the `~/.homebrew/analytics/` timestamp files.

### 8. The "don't sudo brew" rule

```
Error: Running Homebrew as root is extremely dangerous and no longer supported.
```

Homebrew runs as your user by design. It installs into `/opt/homebrew` which is owned by your user (or the `admin` group on multi-user machines). Never `sudo brew install`. If you hit permission errors, the fix is: `sudo chown -R $(whoami) $(brew --prefix)` (or chown to the admin group).

The practical implication: Homebrew-installed services that need to bind to port <1024 or need root access must use `sudo brew services start` to install as a LaunchDaemon, not to run `brew install` as root.

---

## Core commands — the working vocabulary

### Install, info, search

```zsh
# Install a formula
brew install ripgrep

# Install a cask
brew install --cask firefox

# Search across formulae and casks
brew search ripgrep
brew search --formula ripgrep   # formulae only
brew search --cask firefox      # casks only

# Show info (version, deps, options, caveats)
brew info ripgrep
brew info --cask firefox

# Check what's installed, what's outdated
brew list                       # all installed (formulae + casks)
brew list --formula             # formulae only
brew list --cask                # casks only
brew outdated                   # formulae with newer versions available
brew outdated --cask            # casks with newer versions
brew outdated --greedy          # include auto-update casks (browsers, etc.)
```

### Update & upgrade

```zsh
brew update                     # git pull the formula/cask databases (homebrew-core, homebrew-cask, taps)
brew upgrade                    # upgrade all non-pinned outdated formulae
brew upgrade ripgrep            # upgrade one formula
brew upgrade --cask             # upgrade all outdated casks
brew upgrade --cask firefox     # upgrade one cask
```

**Update vs. upgrade:** `update` refreshes the formula *database* (no actual software changes). `upgrade` actually downloads and installs new versions. Common mistake: running `upgrade` without first running `update` and then wondering why it fetched an old version.

### Dependency inspection

```zsh
brew deps ripgrep               # direct dependencies
brew deps --tree ripgrep        # full dependency tree
brew deps --include-build ripgrep   # include build-time deps
brew uses openssl@3             # what formulae depend on openssl@3
brew uses --installed openssl@3 # only among currently installed formulae
brew leaves                     # installed formulae with no dependents (your "root" installs)
```

`brew leaves` is the tool for understanding your "deliberate" installs vs. dependencies that just accumulated. Combine with `brew autoremove` to clean up orphaned deps:

```zsh
brew autoremove                 # uninstall formulae that were installed as dependencies
                                # but are no longer needed by anything
brew autoremove --dry-run       # preview what would be removed
```

### Pin & unpin

Pinning prevents a formula from being upgraded during `brew upgrade`:

```zsh
brew pin openssl@3              # don't upgrade this
brew unpin openssl@3
brew list --pinned              # show pinned formulae
```

Useful when you need a specific version for a project and can't tolerate a silent upgrade breaking an ABI.

### Cleanup & doctor

```zsh
brew cleanup                    # remove old versions from Cellar, stale downloads
brew cleanup --dry-run          # preview what would be removed
brew cleanup -s                 # also remove downloads for current versions (aggressive)

brew doctor                     # system health check: PATH, permissions, stale links, SDK issues
brew missing                    # check for missing formula dependencies
```

`brew doctor` is the first thing to run when a formula build fails inexplicably. Common findings: stale `.plist` files in `/Library/LaunchDaemons/`, Python framework conflicts, wrong Xcode Command Line Tools, broken symlinks.

---

## Brewfile: reproducible environment specification

A `Brewfile` is Homebrew's `requirements.txt` or `package.json` — a declarative list of everything you want installed. Bundle is now built into Homebrew core (no separate tap needed).

### Generating a Brewfile from your current state

```zsh
brew bundle dump                           # write Brewfile to ./Brewfile
brew bundle dump --file=~/dotfiles/Brewfile  # write to specific path
brew bundle dump --force                   # overwrite existing Brewfile
```

### Brewfile syntax

```ruby
# Taps
tap "homebrew/cask-fonts"
tap "homebrew/cask-versions"

# Formulae
brew "git"
brew "ripgrep"
brew "jq"
brew "postgresql@16", restart_service: :changed  # (re)start service when formula changes
brew "nginx", restart_service: true              # always restart on bundle install

# Casks
cask "firefox"
cask "font-jetbrains-mono-nerd-font"
cask "visual-studio-code"

# Mac App Store apps (requires mas)
mas "Tailscale", id: 1475387142
mas "Amphetamine", id: 937984704

# VS Code extensions (if you have it installed)
vscode "ms-python.python"
vscode "eamodio.gitlens"
```

The `id:` field for `mas` entries is the numeric App Store ID — visible in the App Store URL or via `mas search <term>`.

### Installing from a Brewfile

```zsh
brew bundle                                # install from ./Brewfile
brew bundle --file=~/dotfiles/Brewfile     # from specific path
brew bundle --no-upgrade                   # install missing; skip upgrades
brew bundle check                          # verify all deps satisfied (exit 0/1)
brew bundle list                           # list what would be installed
brew bundle cleanup                        # uninstall things NOT in the Brewfile (destructive!)
brew bundle cleanup --force                # actually run the uninstall
```

`brew bundle cleanup` is the diff-from-desired-state operation. It tells you everything currently installed that is *not* in your Brewfile. Useful when auditing a machine that has accumulated cruft. `--force` actually removes it.

> 🪟 **Windows contrast:** The closest Windows analog is `winget import` with a JSON export file (`winget export -o packages.json`). PowerShell DSC covers broader state. Chocolatey has a `config install` workflow. None of these integrate launchd service state the way Brewfile does.

---

## `mas` — Mac App Store from the command line

`mas` (Mac App Store CLI) bridges the gap between Homebrew and apps that only exist in the App Store, require a signed purchase, or need App Store receipt validation for licensing.

```zsh
brew install mas           # install mas itself

mas search "1Password"     # find apps and their numeric IDs
mas list                   # list installed App Store apps with version
mas outdated               # list App Store apps with available updates
mas upgrade                # upgrade all outdated App Store apps
mas upgrade 1475387142     # upgrade one app by ID
mas install 1475387142     # install Tailscale
mas info 1475387142        # show version, price, developer
mas lucky "Amphetamine"    # install the first search result
```

`mas` requires you to be signed into the App Store. It calls the Spotlight Metadata Service (MDS) for installed-app data rather than the App Store API, which means `mas list` is fast but may miss apps installed outside of the App Store daemon's normal path.

**Limitation:** `mas` cannot install apps you have never purchased. It can re-install or update apps already in your purchase history. The purchase must be on the Apple ID currently signed into the App Store.

> 🔬 **Forensics note:** The App Store receipt for each purchased/installed app lives at `/Applications/<App>.app/Contents/_MASReceipt/receipt` (signed by Apple). `mas list` reads MDS metadata that references `~/Library/Application Support/App Store/`. These artifacts are stable forensic indicators of which Apple ID was used to install an app and when.

---

## MacPorts — the alternative ecosystem

MacPorts (`/opt/local`) takes the opposite philosophy from Homebrew:

| Dimension | Homebrew | MacPorts |
|---|---|---|
| Philosophy | Use Apple's system libs where possible | Build & own every dependency from source |
| Install prefix | `/opt/homebrew` | `/opt/local` |
| Build approach | Pre-compiled bottles first, source fallback | Builds from source by default (portfiles) |
| Package count | ~7,000 formulae + ~5,000 casks | 20,000+ ports |
| Speed | Fast (bottles download in seconds) | Slow first install (compile each dep) |
| Isolation | Partial (links to system Python, etc.) | Near-complete (its own gcc, Python, OpenSSL) |
| sudo required | Never | `sudo port install` (writes to `/opt/local/`) |

**When MacPorts wins:**
- You need a port not in Homebrew (obscure Unix tools, research software, legacy libs)
- You need compile-time variants (`+ssl`, `+python39`, `+universal`)
- You need reproducible, fully-isolated builds for CI
- You're doing forensic work on a dedicated analysis VM and want zero contamination from Apple's system libs

```zsh
# MacPorts basic commands (after installing from macports.org)
sudo port selfupdate             # update ports tree
sudo port install wireshark +no_x11  # install with variant
sudo port installed              # list installed ports
sudo port outdated               # list outdated
sudo port upgrade outdated       # upgrade everything
sudo port uninstall <port>
sudo port deps <port>
```

> ⚠️ **ADVANCED:** Running both Homebrew and MacPorts on the same machine is possible but requires discipline. They must not cross-contaminate PATH. Keep MacPorts in a separate shell profile or use direnv to activate per-project. `/opt/local/bin` and `/opt/homebrew/bin` should not both be at the front of PATH simultaneously.

---

## nix — the power option

nix takes package management further: it is a **purely functional** package manager where every package is built in isolation in `/nix/store/<hash>-<name>-<version>/` and no package can have side effects on another. On macOS, nix is typically used via `nix-darwin` (for system-level config) or `home-manager` (for per-user dotfiles + packages).

**Why a power user cares:**
- Atomic, rollback-able system configuration (`darwin-rebuild switch` and you can `darwin-rebuild --rollback`)
- Multiple versions of the same tool active simultaneously, activated per-shell via `nix-shell` or `devShell`
- Perfect reproducibility across machines (same `flake.lock` → byte-identical builds)
- `nix-shell -p python310 openssl ripgrep` → throwaway shell with exact tool versions, gone when you exit

**The trade-off:** steep learning curve (the Nix expression language, flakes, `nix.conf`), a large `/nix/store` that requires a daemon (`nix-daemon`), and community tooling that is powerful but fragmented.

Homebrew and nix can coexist. Many macOS power users use nix for per-project reproducible dev environments and Homebrew for day-to-day GUI apps and convenience.

> 🔬 **Forensics note:** `/nix/store/` is a flat directory of content-addressed packages. On an investigated machine, it reveals every tool version ever installed via nix, even if currently unused. The nix daemon runs as a background service, visible via `launchctl list | grep nix`.

---

## Hands-on (CLI & GUI)

### Check your Homebrew health

```zsh
# See where your brew is
which brew
brew --version           # e.g., Homebrew 4.4.x
brew --prefix

# Full system check
brew doctor
# Expected: "Your system is ready to brew."
# Common warnings: stale .plist files, PATH ordering issues
```

### Inspect an installed formula in depth

```zsh
brew info ripgrep
# Shows: version, bottle availability, installed size,
#        dependencies, caveats, linked keg path

brew deps --tree bat    # bat depends on: libgit2 → ...

# Follow the symlink chain manually
ls -la $(brew --prefix)/bin/rg
# → ../Cellar/ripgrep/14.1.1/bin/rg

# See all files installed by a formula
brew list ripgrep       # every file in the keg
```

### Manage outdated packages

```zsh
brew update && brew outdated
# Shows each formula: <current> → <available>

brew outdated --json | jq '.formulae[] | {name: .name, current: .installed_versions[0], latest: .current_version}'
# Machine-readable audit
```

### Check leaves vs. explicit installs

```zsh
brew leaves             # what you actually installed (no dependents)
brew deps --installed --for-each $(brew leaves) | sort
# Full dep tree rooted at your deliberate installs
```

---

## 🧪 Labs

### Lab 1: Install a formula and trace its anatomy

```zsh
brew install bat        # a better 'cat' with syntax highlighting
which bat               # → /opt/homebrew/bin/bat
ls -la $(which bat)     # see the Cellar symlink
bat --version
brew info bat           # check version, size, options
brew list bat           # every file installed
ls /opt/homebrew/Cellar/bat/   # see the versioned keg
```

### Lab 2: Install a cask and inspect the quarantine behavior

```zsh
# Before: check quarantine on a manually-downloaded app
xattr -l /Applications/SomeApp.app | grep quarantine

# Install via Homebrew cask
brew install --cask rectangle   # window management utility

# After: Homebrew removes quarantine automatically
xattr -l /Applications/Rectangle.app | grep quarantine
# Should show nothing — Homebrew ran: xattr -dr com.apple.quarantine ...

ls /opt/homebrew/Caskroom/rectangle/   # version receipt lives here
```

> ⚠️ **ADVANCED:** Some casks install `.pkg` bundles that modify system paths or install kernel extensions. Always run `brew info --cask <name>` first and read the "Artifacts" section in the cask definition: `brew cat --cask <name>` shows the raw Ruby cask spec.

### Lab 3: Write and use a Brewfile

```zsh
# Dump your current state
brew bundle dump --file=~/Brewfile.backup

# Create a minimal project Brewfile
cat > ~/Downloads/test-Brewfile << 'EOF'
brew "jq"
brew "ripgrep"
brew "fd"
cask "rectangle"
EOF

# Check what's already satisfied
brew bundle check --file=~/Downloads/test-Brewfile

# Install what's missing
brew bundle install --file=~/Downloads/test-Brewfile

# See what's on your machine NOT in this file
brew bundle cleanup --file=~/Downloads/test-Brewfile
# (don't run --force unless you want to remove things)
```

### Lab 4: Run a service and inspect the launchd integration

> ⚠️ **ADVANCED:** This installs PostgreSQL as a user launch agent. To undo: `brew services stop postgresql@16 && brew uninstall postgresql@16`. The plist will be removed automatically.

```zsh
brew install postgresql@16

brew services list | grep postgresql
# Status: none (not started yet)

brew services start postgresql@16
# Output: ==> Successfully started `postgresql@16` (label: homebrew.mxcl.postgresql@16)

brew services list | grep postgresql
# Status: started

# Inspect the plist that was installed into LaunchAgents
ls ~/Library/LaunchAgents/ | grep postgresql
cat ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist
# KeepAlive = true, RunAtLoad = true

# Verify launchd knows about it
launchctl list | grep postgresql

# Stop and verify
brew services stop postgresql@16
launchctl list | grep postgresql    # should be gone
ls ~/Library/LaunchAgents/ | grep postgresql  # plist removed
```

### Lab 5: Housekeeping audit

```zsh
# See how much Cellar space is used
du -sh $(brew --cellar)   # e.g., 4.2G

# Preview cleanup (old versions, stale downloads)
brew cleanup --dry-run

# Run it
brew cleanup

# Autoremove orphaned deps
brew autoremove --dry-run
brew autoremove

# Full before-after comparison
brew doctor
```

### Lab 6: Pin and unpin for version control

```zsh
brew info python@3.12   # note current version
brew pin python@3.12
brew list --pinned       # confirm

brew upgrade             # runs; python@3.12 is skipped
brew unpin python@3.12
```

---

## Pitfalls & gotchas

**PATH ordering with multiple package managers.** If MacPorts is also installed, `/opt/local/bin` and `/opt/homebrew/bin` ordering in PATH determines which `python`, `openssl`, `git` you get. Use `which -a git` to see all candidates in order. Use explicit paths in scripts.

**Cask "auto_updates" and `brew outdated --greedy`.** Casks for apps like Chrome, Firefox, VS Code manage their own update mechanisms. By default, `brew outdated` skips them (they're marked `auto_updates: true` in the cask). To include them: `brew outdated --greedy` and `brew upgrade --greedy`. Mixing Homebrew upgrades with the app's self-updater can cause version confusion.

**`brew update` rate-limiting.** Homebrew uses `git pull` on the formula databases. GitHub's raw API rate-limits unauthenticated pulls at 60/hour. If you see "Your homebrew-core is outdated" errors with network failures, set `HOMEBREW_GITHUB_API_TOKEN` to a personal access token.

**Don't `brew install` Python and then pip-install globally.** Homebrew's Python is for Homebrew's own use. Use `pipx` for user-facing Python CLI tools, `pyenv` or virtual environments for project Python. `brew install pipx && pipx ensurepath` is the right pattern.

**Cellar keg-only formulae don't link.** Some formulae (e.g., `openssl@3`) are installed as "keg-only" — not symlinked into `/opt/homebrew/bin` — to avoid conflicting with macOS's own version. Caveats printed during install tell you to set `PKG_CONFIG_PATH`, `LDFLAGS`, `CPPFLAGS` explicitly. `brew info openssl@3` shows the exact export statements to add.

**After a major macOS upgrade, run `brew upgrade --fetch-HEAD && brew doctor`.** Xcode Command Line Tools update alongside macOS; the SDK path changes. Homebrew may have bottles compiled against the old SDK. `brew doctor` catches most of these.

**Sudo and permissions after migration.** Migration Assistant sometimes preserves directory ownership that doesn't match your new username or UID. If Homebrew complains about permissions: `sudo chown -R $(whoami):admin $(brew --prefix)`.

> 🔬 **Forensics note:** The `~/.homebrew/` directory, `$(brew --prefix)/var/log/`, and Cellar mtime trees are useful artifacts. The Cellar mtime for a version directory tells you roughly when that formula was installed or upgraded. `brew bundle dump` at forensic time gives you the current package state; compare against a known-good Brewfile to spot unexpected tools.

---

## Key takeaways

- Homebrew lives in `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel); activate with `eval "$(brew shellenv)"` in `~/.zprofile`.
- Formulae (CLI/libs) install into `Cellar/`; casks (GUI apps) stage into `Caskroom/` and install to `/Applications/`. Both symlink into the prefix bin/lib tree.
- `brew services` is a launchd shim — `start` installs a plist into `~/Library/LaunchAgents/` and bootstraps it; `stop` reverses both.
- A Brewfile is machine-state-as-code: `brew bundle dump` captures; `brew bundle install` reproduces; `brew bundle cleanup --force` enforces.
- `brew leaves` + `brew autoremove` keeps your environment tidy; `brew doctor` + `brew cleanup` are the maintenance pair.
- `mas` bridges Homebrew and the Mac App Store; pin sensitive formulae with `brew pin`.
- MacPorts wins when you need isolation, build variants, or packages not in Homebrew; nix wins when you need per-project reproducibility and rollback.

---

## Terms introduced

| Term | Definition |
|---|---|
| **formula** | A Ruby script that defines how to build/install a CLI tool or library |
| **cask** | A Ruby script that defines how to download and install a GUI app or font |
| **bottle** | Pre-compiled binary tarball for a formula, hosted on ghcr.io |
| **Cellar** | `/opt/homebrew/Cellar/` — versioned install root for formulae |
| **Caskroom** | `/opt/homebrew/Caskroom/` — version receipt directory for casks |
| **tap** | A git repository of additional formulae/casks beyond homebrew-core/homebrew-cask |
| **keg** | A specific installed version of a formula (`Cellar/<name>/<version>/`) |
| **keg-only** | Formula installed but not linked into the prefix bin/lib; avoids system conflicts |
| **leaf** | An installed formula with no other installed formulae depending on it |
| **Brewfile** | Declarative list of desired packages for `brew bundle` |
| **brew shellenv** | Command that emits shell exports for Homebrew's PATH/MANPATH/INFOPATH |
| **mas** | Mac App Store CLI — installs/updates App Store apps by numeric ID |
| **port** | MacPorts equivalent of a Homebrew formula |
| **nix store** | `/nix/store/` — content-addressed immutable package tree used by nix |

---

## Further reading

- [Homebrew Documentation](https://docs.brew.sh) — authoritative reference; especially the Manpage and Brew-Bundle-and-Brewfile pages
- [mas-cli on GitHub](https://github.com/mas-cli/mas) — source, issue tracker, and README
- [MacPorts Guide](https://guide.macports.org) — comprehensive reference for ports, variants, and the portfile format
- [nix-darwin](https://github.com/LnL7/nix-darwin) — declarative macOS configuration with nix
- [[05-launchd-and-the-launch-system]] — deep dive into launchd, plists, and `launchctl`
- [[08-security-architecture]] — Gatekeeper, quarantine xattrs, and why cask apps skip the "downloaded from internet" prompt
- [[04-filesystem-layout-and-domains]] — understanding `/opt`, `/usr/local`, `/Library`, and domain hierarchy
- [[01-zsh-deep-dive]] — `.zprofile` vs `.zshrc`, login vs interactive shells, why `brew shellenv` goes in `.zprofile`
