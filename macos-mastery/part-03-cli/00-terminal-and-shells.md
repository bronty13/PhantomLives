---
title: Terminal & Shells Overview
part: P03 CLI
est_time: 50 min read + 40 min labs
prerequisites: [02-filesystem-and-paths, 01-boot-process]
tags: [macos, terminal, zsh, bash, shell, cli, iterm2, ghostty, warp]
---

# Terminal & Shells Overview

> **In one sentence:** macOS ships zsh as its POSIX-compliant default login shell inside Terminal.app — but the full story is a layered system of startup files, path construction, login vs. interactive distinctions, and a rich ecosystem of third-party terminals that replace or augment the built-in app.

---

## Why this matters

Every forensic investigation, every build pipeline, every automation script depends on a shell that loads the right environment — and the right environment depends entirely on which startup files ran in which order. Misunderstanding that order causes PATH corruption, wrong tool versions, credentials that don't load, and scripts that work interactively but fail in CI. If you're coming from Windows where PowerShell and `cmd.exe` have comparatively simple startup semantics, this layered model will feel verbose at first. It's worth learning precisely.

> 🪟 **Windows contrast:** `cmd.exe` reads `AUTOEXEC.BAT` (legacy) and per-user registry entries. PowerShell loads `$PROFILE` in four flavors (AllUsersAllHosts, AllUsersCurrentHost, CurrentUserAllHosts, CurrentUserCurrentHost) — conceptually similar to zsh's `/etc/` vs. `~/` split but without the login/interactive distinction. Windows Terminal (WT) is the closest analog to iTerm2: GPU-rendered, tabbed, configurable JSON profiles. The macOS model is meaningfully deeper because the shell startup order interacts with the OS's path-builder daemon.

---

## Concepts

### 1. Terminal.app — the built-in host

Terminal.app is a PTY (pseudo-terminal) host: it allocates a master/slave PTY pair, spawns your login shell as a child process attached to the slave end, and renders its output. It is NOT the shell. This distinction matters forensically — a shell process can outlive its Terminal window if detached (via `nohup`, `disown`, or a multiplexer).

**macOS Tahoe (26) redesign.** After roughly two decades of minimal change, Terminal.app received its first notable visual overhaul in macOS 26. The redesign adopts the Liquid Glass aesthetic, adds official 24-bit (true color) support, and ships Powerline font rendering natively — eliminating the need to manually install patched fonts for Powerline/Nerd Font prompt glyphs. Previous versions required you to install a Nerd Font and configure the profile font manually to avoid broken powerline arrows in prompts like Starship or Powerlevel10k.

**Profiles and themes.** Terminal.app ships several built-in profiles — *Basic*, *Homebrew* (green-on-black, the classic hacker aesthetic), *Ocean*, *Pro* (gray-on-black), *Novel*, *Grass*, *Man Page*, *Red Sands*, *Silver Aerogel*, *Solid Colors*. Each profile is an independent set of settings: font, color scheme (background, text, bold, ANSI palette), cursor style, scrollback limit, bell behavior. Profiles are stored in `~/Library/Preferences/com.apple.Terminal.plist` as serialized NSData blobs. You can export/import profiles via `File › Export Settings…` → `.terminal` files, which are XML property lists — useful for committing to dotfiles repos.

```
# Inspect the raw profile store:
defaults read com.apple.Terminal "Window Settings" | head -40
# or export cleanly:
plutil -convert xml1 ~/Library/Preferences/com.apple.Terminal.plist -o /tmp/term-prefs.xml
```

**Windows, tabs, and panes.** Terminal.app supports:
- **Windows** — independent processes, separate menu-bar focus.
- **Tabs** — `⌘T` opens a new tab in the same window; each tab is a separate PTY/shell session.
- **Shell Integration splits** — Terminal.app itself has no native split-pane view. For horizontal/vertical splits you use `tmux` within the session, or switch to iTerm2/Ghostty/Warp.

**Marks and bookmarks.** When Shell Integration is active (install via `Terminal › Install Shell Integration`), Terminal.app injects escape sequences at each prompt so it can track command boundaries. This enables:
- `⌘↑` / `⌘↓` — jump between prompt marks (previous/next command)
- `⌘⇧A` — select output of the previous command
- `Edit › Marks › Mark as Bookmark` — name a location for later `⌘⌥↑/↓` navigation
- "Clear to Previous Mark" — erases screen back to the last prompt without losing scrollback

These marks are emitted as `ESC]133;` (FinalTerm / Shell Integration protocol) sequences and are visible as invisible bytes in raw terminal recordings — a useful forensic detail when analyzing iTerm2 or Terminal captures.

**Secure Keyboard Entry.** `Terminal › Secure Keyboard Entry` (or `⌘⇧S`) tells the OS to route keyboard events through a secure input path that bypasses the CGEvent tap mechanism. With it disabled, any app with Accessibility access — keyloggers, automation scripts, or malware — can read your terminal keystrokes. With it enabled, only the active Terminal.app window receives the events, but the trade-off is that clipboard managers and some hotkey utilities stop working within the terminal window.

> 🔬 **Forensics note:** Secure Keyboard Entry state is persisted in `com.apple.Terminal.plist` under the key `SecureKeyboardEntry` (boolean). Investigators checking whether a suspect had keylogging protection enabled can read this file — or check `defaults read com.apple.Terminal SecureKeyboardEntry`.

**"New Command" and "New Remote Connection."** Under `Shell › New Command…` you can launch a specific command directly into a new terminal window without going through a login shell — useful for running a one-shot script in a clean environment. `Shell › New Remote Connection…` is a built-in SSH session manager that stores host/user pairs and opens an `ssh` session in a new window; it's basic compared to iTerm2's profile-based SSH integration but functional for quick remote access without a third-party tool.

**⌘-click on paths and URLs.** If Shell Integration is enabled, Terminal.app recognizes file paths and URLs in output and makes them ⌘-clickable — paths open in Finder, URLs open in the browser. The path detection uses heuristic regex matching; absolute paths starting with `/` or `~` are most reliably detected.

---

### 2. The shell layer — zsh, bash, and why they diverged

**Why zsh is the default (since Catalina, 10.15, 2019).** Apple's hand was forced by licensing. The version of bash that ships with macOS (`/bin/bash`) is **version 3.2.57**, frozen because bash 4.x and later switched from GPLv2 to **GPLv3**, which Apple's legal team refused to accept for a system binary (GPLv3's anti-tivoization clause conflicts with Secure Boot and signed-system-volume requirements). zsh uses an MIT-style license. So in Catalina, Apple promoted `/bin/zsh` to the default and left bash frozen as a compatibility shim. In macOS 26, `/bin/bash --version` still prints `3.2.57(1)` — over 18 years old.

```bash
# Confirm both are present and their versions:
/bin/bash --version    # GNU bash, version 3.2.57(1)-release
/bin/zsh  --version    # zsh 5.9 (arm-apple-darwin24.0)
which zsh              # /bin/zsh
```

**Getting modern bash.** Install via Homebrew:

```bash
brew install bash
# Now you have /opt/homebrew/bin/bash (bash 5.2.x)
# To use it as your login shell, it must be in /etc/shells:
echo '/opt/homebrew/bin/bash' | sudo tee -a /etc/shells
chsh -s /opt/homebrew/bin/bash    # or use System Settings
```

> ⚠️ **ADVANCED:** Changing your login shell affects every new terminal session. If the new shell is misconfigured, you can get locked into a broken environment. Before `chsh`, verify the shell starts cleanly: `/opt/homebrew/bin/bash -l -c "echo ok"`. If something breaks, boot to Recovery OS (`⌘R` / hold Power) and use `Terminal › Run as Administrator` to `chsh -s /bin/zsh` back.

---

### 3. Shell startup file execution order

This is the most misunderstood part of macOS shell configuration. The key axes are:

| Axis | Meaning |
|---|---|
| **Login shell** | Started with `-l` flag, or as the first shell in a PTY (Terminal.app, SSH). Reads login files. |
| **Interactive shell** | Has a terminal attached; reads interactive files. |
| **Non-interactive shell** | Scripting; most login files skipped. |
| **Non-login shell** | Opened inside an existing session (e.g., `bash` from within zsh, a subshell, VS Code terminal). Skips login files. |

Terminal.app and SSH both start **login + interactive** shells. A shell spawned by a script or `system()` call is typically **non-login + non-interactive**.

#### Full zsh startup sequence (login + interactive)

```
/etc/zshenv          ← always, for every zsh invocation
~/.zshenv            ← always (ZDOTDIR overrides ~/.zshenv location)

/etc/zprofile        ← login shell only  ← path_helper runs here!
~/.zprofile          ← login shell only

/etc/zshrc           ← interactive shell only
~/.zshrc             ← interactive shell only

/etc/zlogin          ← login shell only (after .zshrc)
~/.zlogin            ← login shell only (after .zshrc)

# On logout:
~/.zlogout
/etc/zlogout
```

**What goes where — the canonical rules:**

- **`.zshenv`** — environment variables that must be available to *every* process: `EDITOR`, `LANG`, `GOPATH`. Keep it minimal; sourced inside scripts and cron jobs. Do NOT set `PATH` here if you want Homebrew to win (see path_helper below).
- **`.zprofile`** — login-only setup: Homebrew's `eval "$(/opt/homebrew/bin/brew shellenv)"`, `ssh-add`, Node version manager init.
- **`.zshrc`** — interactive config: aliases, functions, prompt (`PS1`/Starship/p10k), completions (`compinit`), history settings, `zstyle`, key bindings. This is the file most people edit.
- **`.zlogin`** — rarely needed; runs after `.zshrc`. Some use it for `fortune` or login banners.

#### The `path_helper` mechanism — macOS-specific

macOS injects its own PATH builder at `/etc/zprofile`. Read it:

```bash
cat /etc/zprofile
# output:
# if [ -x /usr/libexec/path_helper ]; then
#     eval $(/usr/libexec/path_helper -s)
# fi
```

`/usr/libexec/path_helper` reads two sources:

1. `/etc/paths` — colon-separated base paths (contains `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`)
2. `/etc/paths.d/` — drop-in files, one path per line, added by package installers

```bash
cat /etc/paths
ls /etc/paths.d/
# typical contents after Homebrew + Xcode install:
# /etc/paths.d/10-cryptex
# /etc/paths.d/Xcode
# /etc/paths.d/homebrew
cat /etc/paths.d/homebrew    # /opt/homebrew/bin\n/opt/homebrew/sbin
```

**The path_helper trap.** If you `export PATH="/my/tool:$PATH"` in `~/.zshenv`, path_helper runs afterward (in `/etc/zprofile`) and *re-sorts* your PATH — placing `/etc/paths` entries first. Your `/my/tool` ends up at the end, not the front. The fix: put PATH mutations in `~/.zprofile` (after path_helper) or `~/.zshrc`.

> 🔬 **Forensics note:** `/etc/paths.d/` is a common persistence location. Malware can drop a file here to prepend a malicious binary directory to every user's PATH, causing trojanized tools to shadow system binaries. Audit this directory during any compromise investigation: `ls -la /etc/paths.d/ && cat /etc/paths.d/*`.

```
ASCII: macOS zsh startup flow for a new Terminal.app tab

Terminal.app (PTY host)
    │
    └─ spawns: /bin/zsh --login --interactive
                    │
                    ├── /etc/zshenv
                    ├── ~/.zshenv
                    ├── /etc/zprofile   ← path_helper rebuilds PATH
                    ├── ~/.zprofile     ← brew shellenv, nvm init
                    ├── /etc/zshrc
                    ├── ~/.zshrc        ← aliases, prompt, completions
                    └── [shell ready]
```

---

### 4. Changing the login shell

```bash
# List valid shells (must be in /etc/shells to be selectable):
cat /etc/shells

# Change via chsh (takes effect at next login):
chsh -s /bin/zsh             # back to zsh
chsh -s /opt/homebrew/bin/bash  # Homebrew bash (must be in /etc/shells first)
chsh -s /opt/homebrew/bin/fish  # Fish shell

# Verify what your account's shell is:
dscl . -read /Users/$USER UserShell
# or:
finger $USER | grep Shell
```

You can also change it via **System Settings → General → Login Items & Extensions → (bottom) Shell** (macOS 13+). Under the hood both methods write to the DirectoryServices database via `dscl`.

---

### 5. Third-party terminal emulators — the ecosystem

All of these replace Terminal.app as the PTY host but still spawn the same shell startup sequence. Choosing a terminal emulator is independent of choosing a shell.

#### iTerm2
- **What it is:** The longstanding macOS power-user standard. Electron-free; native Objective-C/Swift.
- **Key differentiators:** Native split panes (`⌘D` vertical, `⌘⇧D` horizontal); hotkey window (a terminal that slides over any app via a global shortcut); tmux integration (`tmux -CC` mode — each tmux window becomes a native iTerm2 tab/pane, surviving SSH disconnects); Shell Integration with richer command history and output selection; Triggers (regex on output → action); coprocess (pipe output to a second process); open quickly (`⌘⇧O`); Python scripting API for automation.
- **tmux `-CC` mode** is iTerm2's killer feature for remote work: `ssh host -t tmux -CC new` — you get native tabs that persist when you reconnect, with full scrollback.
- Download: [iterm2.com](https://iterm2.com)

#### Ghostty
- **What it is:** Mitchell Hashimoto's (Terraform founder) terminal, written in Zig with Metal rendering on macOS and OpenGL on Linux.
- **Key differentiators:** Fastest renderer available — consistent 120 fps on ProMotion displays; ~1.2 ms input latency; ~45 MB RAM; sub-70 ms cold start. Native AppKit/SwiftUI (no Electron, no web renderer). Correct VT semantics, Kitty Graphics Protocol support. Config is a plain text file (`~/.config/ghostty/config`), not a GUI — version-controlled friendly.
- **macOS integration:** Native tabs, native fullscreen, Cmd-click URLs, proper macOS accessibility.
- Ghostty fills the gap between "correct but slow" and "fast but alien-feeling" — it feels like a system app that happens to be extremely fast.
- Download: [ghostty.org](https://ghostty.org)

#### Warp
- **What it is:** An Electron-based terminal that reimagines the shell interaction model as "blocks" — each command + its output is a discrete, selectable, shareable unit.
- **Key differentiators:** AI command search (natural language → shell command); Agents 3.0 for multi-step autonomous tasks; AI-driven error explanation; collaborative sharing of command blocks; built-in command palette; persistent workflows (save multi-step procedures as named actions).
- **Tradeoff:** Electron stack means higher RAM (~200 MB idle); the block model can feel constraining for raw scrollback work. Requires a Warp account. Some forensic/audit tools that parse raw PTY output behave unexpectedly inside Warp's block renderer.
- Best for: developers who lean on AI suggestions and want drag-and-drop command sharing.

#### kitty
- **What it is:** GPU-accelerated (Metal on macOS), highly extensible terminal written in Python + C, authored by Kovid Goyal.
- **Key differentiators:** Kitty Graphics Protocol (renders inline images natively — `timg`, `viu`, `chafa`); kittens (small terminal programs composable inside kitty: `kitten diff`, `kitten ssh`, `kitten icat`); ligature support; tiling layouts without tmux; remote control via socket.
- Config: `~/.config/kitty/kitty.conf` — all plain text.
- `kitten ssh` auto-copies kitty's terminfo to the remote host, fixing the dreaded `$TERM` incompatibility that plagues `xterm-kitty` on servers.

#### Alacritty
- **What it is:** Originally billed as "the fastest terminal" — a pure Rust, OpenGL-rendered terminal. Minimal by design.
- **Key differentiators:** No tabs, no splits (intentional — use tmux). Tiny binary, minimal dependencies. Cross-platform (macOS/Linux/Windows). YAML/TOML config.
- Best for: tmux-first workflows where you want the terminal to do nothing except render fast. Ghostty has largely superseded it for raw speed on Apple Silicon.

#### WezTerm
- **What it is:** Cross-platform Rust terminal by Wez Furlong, with Lua scripting.
- **Key differentiators:** Lua config API for full programmability; built-in multiplexer (tabs/splits/panes without tmux); SSH multiplexer (native domain support — connect to a remote WezTerm server without a full tmux session); image protocol support; good Windows/macOS/Linux parity.
- Best for: polyglot engineers who want one terminal config across all platforms.

#### Quick comparison

| Terminal | Renderer | Native tabs/splits | tmux integration | AI | Config format |
|---|---|---|---|---|---|
| Terminal.app | CoreText/CoreGraphics | Tabs only | No | No | GUI + .plist |
| iTerm2 | Metal | Yes | `-CC` native | No | GUI + .itermprofile |
| Ghostty | Metal (Zig) | Yes | Standard | No | Plain text |
| Warp | Electron | Yes | Basic | Yes | GUI + account |
| kitty | Metal (C/Python) | Yes (layouts) | No (kittens instead) | No | Plain text |
| Alacritty | Metal (Rust) | No (by design) | No | No | TOML |
| WezTerm | Wgpu (Rust) | Yes | SSH domain | No | Lua |

---

## Hands-on (CLI & GUI)

### Inspect your current shell environment

```bash
# What shell am I in right now?
echo $SHELL          # login shell setting
echo $0              # current shell process name
ps -p $$             # same, more detail

# What startup files exist?
ls -la ~/.zshenv ~/.zprofile ~/.zshrc ~/.zlogin ~/.zlogout 2>/dev/null

# Trace the full startup sequence (dry run — shows which files would load):
zsh -o sourcetrace -i -l 2>&1 | head -30
# Alternatively, add ZDOTDIR tracing:
zsh -x -c "exit" 2>&1 | grep source | head -20

# What's in each paths.d file?
cat /etc/paths
ls /etc/paths.d/ && for f in /etc/paths.d/*; do echo "=== $f ==="; cat "$f"; done

# What does path_helper produce on its own?
/usr/libexec/path_helper -s
```

### Customize a Terminal.app profile

```bash
# Export current Terminal settings for backup:
cp ~/Library/Preferences/com.apple.Terminal.plist ~/Desktop/Terminal-backup.plist

# Via defaults: change the default window title to show process name:
defaults write com.apple.Terminal "Default Window Settings" -string "Pro"
defaults write com.apple.Terminal "Startup Window Settings" -string "Pro"

# After editing in Terminal's GUI, inspect what changed:
plutil -convert xml1 ~/Library/Preferences/com.apple.Terminal.plist -o - | grep -A5 "Pro"
```

### Install Shell Integration in Terminal.app

```
Terminal menu → Shell → Install Shell Integration
```

This writes a source line into `~/.zshrc` and installs `~/.iterm2_shell_integration.zsh` (the file is shared even for Terminal.app). After reinstalling, test marks:

```bash
echo "line 1" && echo "line 2"
# Press ⌘↑ — cursor jumps to the previous prompt mark
```

### Enable Secure Keyboard Entry programmatically

```bash
# Check current state:
defaults read com.apple.Terminal SecureKeyboardEntry
# 0 = disabled, 1 = enabled

# Enable:
defaults write com.apple.Terminal SecureKeyboardEntry -bool true
# Disable:
defaults write com.apple.Terminal SecureKeyboardEntry -bool false
# (Requires Terminal restart to take effect)
```

### Add a path to /etc/paths.d (system-wide)

```bash
# Example: add a custom toolchain to all users' PATH
echo '/opt/mytool/bin' | sudo tee /etc/paths.d/mytool
# Verify path_helper picks it up:
/usr/libexec/path_helper -s | grep mytool
# Open a new terminal and confirm:
echo $PATH | tr ':' '\n' | grep mytool
```

---

## Labs

### Lab 1: Profile crafting and export

**Goal:** Create a custom Terminal profile and commit it to a dotfiles repo.

1. Open Terminal.app → `Preferences → Profiles → ⊕` — duplicate "Pro".
2. Set font to your Nerd Font of choice (or "SF Mono" at 14pt), background color to `#1e1e2e` (Catppuccin Mocha base), text to `#cdd6f4`.
3. Enable "Antialias text", set cursor to Block.
4. Set the title to show "Shell Command Name".

```bash
# Export to dotfiles:
mkdir -p ~/dotfiles/terminal
# Terminal → File › Export Settings... → save as ~/dotfiles/terminal/MyTheme.terminal

# Verify it's XML (portable):
file ~/dotfiles/terminal/MyTheme.terminal
# output: ~/dotfiles/terminal/MyTheme.terminal: XML 1.0 document text

# Inspect the color values:
plutil -convert xml1 ~/dotfiles/terminal/MyTheme.terminal -o - | grep -A2 "BackgroundColor"
```

**Rollback:** Delete the profile in Terminal.app Preferences, or restore from the backup plist you made above.

---

### Lab 2: Startup file audit and PATH surgery

> ⚠️ **ADVANCED:** Editing startup files can break your shell environment. Back up before making changes: `cp ~/.zshrc ~/.zshrc.bak && cp ~/.zprofile ~/.zprofile.bak`

**Goal:** Understand the full load order and see path_helper in action.

```bash
# Step 1: Add logging to each startup file temporarily
echo 'echo "[zshenv] loaded"' >> ~/.zshenv
echo 'echo "[zprofile] loaded"' >> ~/.zprofile
echo 'echo "[zshrc] loaded"' >> ~/.zshrc

# Step 2: Open a new Terminal window and observe the output order:
# [zshenv] loaded
# [zprofile] loaded
# [zshrc] loaded

# Step 3: Demonstrate the path_helper reorder trap
# Add a dummy path in .zshenv:
echo 'export PATH="/tmp/mytools:$PATH"' >> ~/.zshenv
# Open a new terminal and check where /tmp/mytools landed:
echo $PATH | tr ':' '\n' | grep -n mytools
# It will be somewhere near the end — after path_helper reshuffled things.

# Step 4: Fix it — move to .zprofile (after path_helper):
# Remove from .zshenv, add to .zprofile:
grep -v '/tmp/mytools' ~/.zshenv > /tmp/zshenv.new && mv /tmp/zshenv.new ~/.zshenv
echo 'export PATH="/tmp/mytools:$PATH"' >> ~/.zprofile
# New terminal: /tmp/mytools now appears at the front
echo $PATH | tr ':' '\n' | head -5

# Step 5: Clean up logging lines:
grep -v 'echo "\[zsh' ~/.zshenv > /tmp/e.tmp && mv /tmp/e.tmp ~/.zshenv
grep -v 'echo "\[zsh' ~/.zprofile > /tmp/p.tmp && mv /tmp/p.tmp ~/.zprofile
grep -v 'echo "\[zsh' ~/.zshrc > /tmp/r.tmp && mv /tmp/r.tmp ~/.zshrc
grep -v '/tmp/mytools' ~/.zprofile > /tmp/pp.tmp && mv /tmp/pp.tmp ~/.zprofile
```

---

### Lab 3: Install and configure Ghostty

> ⚠️ **PREREQUISITE:** Requires macOS 12+ (Monterey) and Apple Silicon or Intel with Metal support.

```bash
# Install via Homebrew cask:
brew install --cask ghostty

# Create config:
mkdir -p ~/.config/ghostty
cat > ~/.config/ghostty/config << 'EOF'
font-family = "MesloLGS NF"
font-size = 14
theme = "catppuccin-mocha"
window-padding-x = 12
window-padding-y = 8
mouse-hide-while-typing = true
macos-option-as-alt = true
EOF

# Launch Ghostty:
open /Applications/Ghostty.app

# Verify it picked up your config (Ghostty → Settings → Reload Config):
# Or check from within Ghostty:
ghostty +list-themes | grep catppuccin
```

---

### Lab 4: Non-login shell behavior (VS Code terminal)

**Goal:** Understand why VS Code's integrated terminal often misses Homebrew tools.

VS Code spawns a non-login interactive shell. `/etc/zprofile` does NOT run, so `path_helper` never builds your PATH, and your Homebrew `eval` line in `~/.zprofile` never runs.

```bash
# Simulate a non-login shell:
zsh -i -c 'echo $PATH' | tr ':' '\n'
# vs. a login shell:
zsh -l -i -c 'echo $PATH' | tr ':' '\n'
# Compare: the login shell has /opt/homebrew/bin; the non-login shell may not.

# Fix for VS Code: add to ~/.zshrc (not just .zprofile):
# eval "$(/opt/homebrew/bin/brew shellenv)"
# This ensures Homebrew is in PATH even in non-login shells.
```

> 🔬 **Forensics note:** When a process launches via `launchd` (Launch Agents/Daemons), it gets a minimal environment with no shell startup files at all — only what's specified in the plist's `EnvironmentVariables` key or inherited from launchd's bootstrap. This is why scripts that work in Terminal fail as launchd agents: `$PATH` is typically just `/usr/bin:/bin:/usr/sbin:/sbin`. See [[06-launchd-and-launch-agents]] for the full treatment.

---

## Pitfalls & gotchas

**1. The "bash" on your PATH might not be bash.** After `brew install bash`, `which bash` returns `/opt/homebrew/bin/bash` if Homebrew is first in PATH — but scripts with `#!/bin/bash` still get the frozen 3.2 version. Use `#!/usr/bin/env bash` and ensure `/opt/homebrew/bin` precedes `/bin` in PATH.

**2. `.bash_profile` vs. `.bashrc` confusion.** If you ever switch to bash, remember macOS Terminal starts login shells: `.bash_profile` loads (not `.bashrc`). The common fix is to `source ~/.bashrc` from `.bash_profile`. zsh avoids this confusion by having `.zprofile` + `.zshrc` with clear semantics.

**3. `compinit` called twice degrades startup time.** If you use Oh My Zsh or Prezto AND manually call `compinit` in `.zshrc`, completions rebuild twice. Symptom: slow shell startup. Fix: let the framework call `compinit` once, or add `-C` flag to skip the security check on subsequent calls: `autoload -Uz compinit && compinit -C`.

**4. Secure Keyboard Entry breaks clipboard managers.** Alfred, Raycast, and Pasteapp all lose access to clipboard content typed in Terminal when SKE is enabled. If you paste secrets from a password manager into Terminal and use a clipboard manager, disable SKE only during that operation, or use `pbpaste` programmatically.

**5. iTerm2 tmux `-CC` mode requires `tmux` 3.2+ on the remote.** Older Linux servers ship tmux 2.x; the `-CC` control mode protocol changed. Symptoms: garbled output, immediate disconnect. Fix: `brew install tmux` on the remote (or `conda install tmux`).

**6. `$TERM` incompatibilities with SSH.** Ghostty's default `TERM=xterm-ghostty` and kitty's `TERM=xterm-kitty` have no terminfo entries on most Linux servers. Remote `vim` or `less` breaks. Fix: `kitten ssh` (auto-copies terminfo), or set `TERM=xterm-256color` in your remote SSH config: add `SetEnv TERM=xterm-256color` to `~/.ssh/config` for specific hosts.

**7. `/etc/zshenv` runs inside `sudo`.** When you run `sudo zsh -c "..."`, `/etc/zshenv` and `~/.zshenv` (if the user's home is accessible) still load. Malware that achieves `sudo` execution and writes to `/etc/zshenv` gets code execution in every subsequent `sudo zsh` call. Audit `/etc/zshenv` during incident response.

**8. macOS Tahoe Terminal's Liquid Glass redesign.** The new visual chrome is beautiful but some third-party color profiles exported from pre-Tahoe Terminal versions import with degraded colors because the ANSI palette serialization format changed slightly in the new profile schema. If an imported `.terminal` file looks washed out, re-export from Tahoe after opening and saving in Preferences.

---

## Key takeaways

- Terminal.app is a PTY host; the shell is a separate process. The Tahoe redesign adds true-color and Powerline font support natively for the first time.
- `zsh` is the default because GPLv3 blocked `bash` 4+; `/bin/bash` is frozen at 3.2.57. Get modern bash via `brew install bash`.
- The startup file order is: `zshenv` (always) → `zprofile` (login) → `zshrc` (interactive) → `zlogin` (login, post-zshrc). `/etc/zprofile` is where `path_helper` runs — do not set PATH in `.zshenv` if you want it to survive.
- `/etc/paths` and `/etc/paths.d/` feed `path_helper`; `/etc/paths.d/` is a persistence vector worth auditing in compromises.
- Ghostty is currently the fastest native macOS terminal (Metal/Zig, ~1.2 ms latency); iTerm2 is the most feature-rich for remote work (tmux `-CC`); Warp adds AI; WezTerm excels cross-platform with Lua scripting.
- Secure Keyboard Entry routes keyboard events through a protected path, visible as `SecureKeyboardEntry` in `com.apple.Terminal.plist`.
- Non-login shells (VS Code terminal, scripts, `launchd` jobs) skip `/etc/zprofile` — PATH is NOT built by `path_helper` in these contexts.

---

## Terms introduced

| Term | Definition |
|---|---|
| **PTY (pseudo-terminal)** | A kernel-level device pair (master/slave) that allows a terminal emulator to communicate with a shell process as if it were a real serial terminal |
| **Login shell** | A shell invoked as the first process in a session (Terminal.app new window, SSH login); reads login startup files |
| **Interactive shell** | A shell attached to a terminal that accepts user input; reads interactive startup files |
| **`path_helper`** | `/usr/libexec/path_helper` — macOS-specific utility that builds `$PATH` from `/etc/paths` and `/etc/paths.d/*.conf` files, invoked from `/etc/zprofile` |
| **Shell Integration** | Escape sequences (FinalTerm/`ESC]133;` protocol) injected by a shell hook to let the terminal track command boundaries, enabling marks, output selection, and ⌘-click paths |
| **Secure Keyboard Entry** | macOS API mode that routes keyboard events through a protected path, blocking CGEvent taps from intercepting terminal keystrokes |
| **Marks & bookmarks** | Terminal.app navigation anchors inserted at command boundaries by Shell Integration; navigated with ⌘↑/↓ |
| **`chsh`** | Change shell — modifies the DirectoryServices database entry for a user's login shell |
| **`tmux -CC`** | iTerm2-specific tmux control mode where tmux windows/panes render as native iTerm2 UI elements |
| **`ZDOTDIR`** | zsh variable that overrides the location of `~` for dotfile loading — set in `/etc/zshenv` to support per-project shell environments |
| **GPLv3 anti-tivoization** | GPLv3 clause that prohibits restricting users from running modified versions on hardware they own — incompatible with Apple's Secure Boot/signed-system-volume requirements |

---

## Further reading

- `man zsh` → "STARTUP/SHUTDOWN FILES" section — authoritative source for file load order
- `man path_helper` — sparse but official; read alongside `/etc/zprofile` source
- Apple Platform Security Guide — "System Integrity Protection" chapter (explains why bash can't be updated)
- [Howard Oakley — Eclectic Light Company: "What runs at login"](https://eclecticlight.co) — deep dives on macOS-specific startup behavior
- [Ghostty docs: Features](https://ghostty.org/docs/features)
- `man 1 login`, `man 1 chsh`, `man 5 passwd` — foundational Unix shell-account model
- [[06-launchd-and-launch-agents]] — how `launchd` spawns daemons and agents with minimal PATH
- [[02-filesystem-and-paths]] — where config files live in the macOS directory hierarchy
- [[10-security-and-tcc]] — TCC and why Secure Keyboard Entry matters in a permission model context
