---
title: Terminal Dev Workflow & Dotfiles
part: P07 Development
est_time: 60 min read + 90 min labs
prerequisites: [03-cli/00-terminal-and-shells, 03-cli/01-zsh-deep-dive, 03-cli/12-homebrew-and-package-management, 03-cli/10-ssh-and-remote-access]
tags: [macos, development, dotfiles, git, terminal, zsh, tmux, neovim, fzf, zoxide, starship, chezmoi, ssh]
---

# Terminal Dev Workflow & Dotfiles

> **In one sentence:** A reproducible, portable terminal environment — modern Rust-era CLI replacements, a dotfiles system that deploys in minutes on a new Mac, and git configured to use the macOS Keychain correctly — is a force-multiplier that pays for the setup time within the first week.

## Why this matters

The default macOS developer terminal is functional but not fast. Apple ships a CLT `git` that lags months behind upstream, `ls` that can't color directories or show git status, `grep` that can't search file contents recursively at any reasonable speed, and no concept of a "smart" `cd`. The gap between a stock setup and a well-tuned one is measurable in keystrokes per hour.

More importantly: **this user works across two Macs**. Everything here is evaluated through the lens of *can this be committed to a git repo and deployed in 10 minutes on the other machine?* That requirement rules out hand-maintained GUI configurations and favors dotfiles-as-code.

> 🪟 **Windows contrast:** On Windows the equivalent effort is Windows Terminal + WSL2 + oh-my-posh for the prompt + winget or scoop for packages. The tooling names are different but the workflow architecture — a shell config file, a package manifest, a multiplexer for persistent sessions — is the same. The key difference is that macOS bash/zsh are first-class, the Keychain replaces Windows Credential Manager for git auth, and the SSH agent is launchd-native rather than requiring an OpenSSH service or PuTTY/Pageant.

> 🔬 **Forensics note:** A developer's dotfiles repo is a gold mine during an investigation. It exposes shell aliases that bypass standard audit paths, SSH config stanzas pointing to private servers, git signing keys, and env vars referencing external APIs. Check `~/.gitconfig`, `~/.ssh/config`, `~/.zshrc`/`~/.zprofile`, `~/.*_history`, and any chezmoi/stow source directory (typically `~/.local/share/chezmoi/` or `~/dotfiles/`).

---

## Concepts

### 1. The CLT git vs Homebrew git

macOS ships two gits. The Apple Command Line Tools version lives at `/Library/Developer/CommandLineTools/usr/bin/git` and is managed by Software Update — it often lags 3-6 months behind upstream and lacks features like `git-credential-manager` plugins. The Homebrew version (`/opt/homebrew/bin/git`) tracks upstream releases within days.

```
$ /usr/bin/git --version       # Apple's shim — identical behavior but dispatches to CLT
$ which git                    # After brew install git: /opt/homebrew/bin/git
$ git --version                # Should show 2.47+ with brew git on PATH first
```

Ensure `/opt/homebrew/bin` precedes `/usr/bin` in `$PATH` (the Homebrew installer does this in `/etc/paths.d/homebrew` on Apple Silicon). Verify with `which -a git`.

**The CLT git is fine for casual use. For a developer setup, install the Homebrew version** to get current features, especially `--column`, `--sort` in various subcommands, and the latest signing support.

### 2. git credential helper: osxkeychain

macOS ships a credential helper that stores git HTTPS passwords/tokens in the macOS Keychain (the same secure store as Safari passwords and app passwords). It is bundled with the CLT and also works with Homebrew git because Homebrew includes the helper binary.

```ini
# ~/.gitconfig (set globally once):
[credential]
    helper = osxkeychain
```

Set it: `git config --global credential.helper osxkeychain`

On first push/pull, git prompts for your GitHub PAT (personal access token — GitHub no longer accepts passwords for HTTPS). The token is stored in Keychain under the internet password entry `github.com`. Subsequent operations are silent.

To inspect the stored credential:
```bash
git credential-osxkeychain get <<EOF
protocol=https
host=github.com
EOF
```

To rotate (delete and re-prompt on next use):
```bash
git credential-osxkeychain erase <<EOF
protocol=https
host=github.com
EOF
```

You can also manage it in Keychain Access.app under "github.com (internet password)".

> 🔬 **Forensics note:** Keychain entries for `github.com`, `gitlab.com`, `bitbucket.org` immediately identify which code forges a user has authenticated to. The entry's "Date Modified" is the last time the credential was refreshed — often correlating to a push event. See [[04-keychain-and-secrets]] for full Keychain forensics.

### 3. Commit signing: SSH vs GPG

GitHub (and most forges) support signing commits with either GPG or SSH keys. In 2026, **SSH signing is the clear choice** for most developers:

- No GPG keyring to manage; uses the same SSH key you already have for push access
- macOS 15+ and macOS 26 natively pass SSH keys through the built-in ssh-agent (launchd-backed), accessible to git without `eval $(ssh-agent)`
- 1Password and similar SSH agent integrations work natively (hardware-backed keys stored in Secure Enclave)

```ini
# ~/.gitconfig
[user]
    name = Your Name
    email = you@example.com
    signingkey = ~/.ssh/id_ed25519.pub   # path to PUBLIC key; git reads private via agent

[gpg]
    format = ssh

[commit]
    gpgsign = true

[gpg "ssh"]
    allowedSignersFile = ~/.config/git/allowed_signers
```

The `allowed_signers` file maps emails to public keys — required for local verification:
```
you@example.com namespaces="git" ssh-ed25519 AAAA...
```

Generate a key (Secure Enclave-backed on Apple Silicon, when using `ssh-keygen -t ecdsa -b 256` or via 1Password):
```bash
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519
```

Tell GitHub about it: `gh ssh-key add ~/.ssh/id_ed25519.pub --type signing`

> ⚠️ **macOS 26 / Tahoe caveat:** macOS 26.3 added post-quantum key exchange warnings when connecting to servers that do not support ML-KEM. You may see:
> ```
> Warning: the remote host does not support post-quantum key exchange
> ```
> This is informational. If you use 1Password as your SSH agent and rotate SSH keys, verify that 1Password's signing key reference is updated — old key references cause `No SSH private key found` failures on `git commit` without touching push auth (two separate agent queries).

### 4. Global git configuration worth setting

```bash
# Identity
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Editor — Neovim if installed, else fallback
git config --global core.editor "nvim"

# Default branch name
git config --global init.defaultBranch main

# Pull strategy
git config --global pull.rebase true

# Diff & merge
git config --global diff.algorithm histogram
git config --global merge.conflictstyle zdiff3   # 3-way with base in conflict markers

# Delta pager (see §Modern CLI stack below)
git config --global core.pager "delta"
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.dark true
git config --global delta.side-by-side true

# Credential helper
git config --global credential.helper osxkeychain

# Commit signing
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

### 5. The global .gitignore

macOS generates `.DS_Store` everywhere. It must be in every repo's `.gitignore` **or** in a global ignore file. The global file is cleaner for cross-project hygiene:

```bash
git config --global core.excludesfile ~/.config/git/ignore
```

```
# ~/.config/git/ignore
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
*.swp
*.swo
*~
.env
.env.local
.venv/
__pycache__/
*.pyc
.idea/
*.xcuserstate
```

> 🔬 **Forensics note:** The absence of `.DS_Store` in a repo's history (because `core.excludesfile` was set globally) does **not** mean `.DS_Store` files never existed in the working tree — they may still exist on disk, outside git's tracking. `.DS_Store` files contain Spotlight metadata, window positions, and sidebar icon arrangement. See [[03-forensic-artifacts]] for parsing them.

### 6. The modern CLI stack

These are not toys — they are the tools a top-1% terminal user installs on day one. Install everything in one shot:

```bash
brew install \
  git \
  starship \
  eza \
  bat \
  ripgrep \
  fd \
  fzf \
  zoxide \
  git-delta \
  jq \
  yq \
  gh \
  tldr \
  btop \
  dust \
  ncdu \
  hyperfine \
  watch \
  neovim
```

**What each one replaces and why:**

| Tool | Replaces | Key capability |
|------|----------|----------------|
| `starship` | raw `$PS1` | Rust prompt; sub-millisecond render; git state, language versions, exit code, command duration shown automatically; single TOML config; works in bash/zsh/fish/nushell |
| `eza` | `ls` | Rust; `--long --git --icons --group-directories-first --color=always`; tree mode (`eza --tree`); shows git status per file |
| `bat` | `cat` | Syntax highlighting, line numbers, git diff decoration; respects `$BAT_THEME`; pipes cleanly (`bat --plain`) |
| `ripgrep` (`rg`) | `grep -r` | Respects `.gitignore`; PCRE2; averages 5-20× faster than GNU grep on large repos; `rg 'TODO' --type ts` for language-filtered search |
| `fd` | `find` | Respects `.gitignore`; sane flag names (`fd -e py` vs `find -name '*.py'`); parallel by default |
| `fzf` | nothing has it on Windows | Fuzzy finder with real-time preview; wires into `Ctrl-R` (history), `Ctrl-T` (file picker), `Alt-C` (cd); most powerful when integrated with ripgrep |
| `zoxide` | `cd` | Frecency-ranked smart jump: `z proj` jumps to the most-visited directory matching "proj"; `zi` for interactive fzf mode |
| `git-delta` (`delta`) | `git diff` builtin pager | Side-by-side diffs, syntax highlighting, merge conflict highlighting, line numbers; configured via `core.pager` |
| `jq` | manual JSON parsing | In-terminal JSON processor; `curl api | jq '.items[].name'` |
| `yq` | — | Same but for YAML/TOML/XML; same flag syntax as jq |
| `gh` | browser for GitHub ops | PRs, issues, runs, gists, SSH keys, releases — all from the terminal; `gh pr create`, `gh run watch`, `gh browse` |
| `tldr` | man pages for quick recall | Community-maintained cheat sheets; `tldr tar` vs reading `man tar` |
| `btop` | `top`/`htop` | Full-color process monitor; shows CPU per-core, memory, disk I/O, network in a single TUI; mouse-driven |
| `dust` | `du -sh *` | Visual disk usage treemap in the terminal; `dust -d 2` for depth control |
| `ncdu` | same | Interactive ncurses disk usage; navigate and delete from within |
| `hyperfine` | manual `time` loops | Statistical benchmarking: `hyperfine 'rg foo' 'grep -r foo'` runs each N times, reports mean/σ/min/max |
| `watch` | polling scripts | `watch -n 1 'ls -la'` re-runs a command every N seconds in-place; brew version supports color |
| `neovim` | `vim` / `nano` | Lua-config Vim successor; pairs with LSP servers and tree-sitter for IDE-grade editing |

**Wire everything into `.zshrc`:**

```zsh
# Homebrew (Apple Silicon path; Intel would be /usr/local)
eval "$(/opt/homebrew/bin/brew shellenv)"

# Starship prompt
eval "$(starship init zsh)"

# zoxide (must come after any cd override)
eval "$(zoxide init zsh)"

# fzf key bindings and completion
source <(fzf --zsh)   # preferred since fzf 0.48+; replaces the old $(brew --prefix)/opt/fzf/share/...

# Aliases — modern replacements
alias ls='eza --icons --group-directories-first --color=always'
alias ll='eza --long --icons --git --group-directories-first --color=always'
alias la='eza --long --icons --git --group-directories-first --color=always --all'
alias tree='eza --tree --icons --color=always'
alias cat='bat --style=plain'          # --style=plain suppresses line numbers in pipes
alias grep='rg'
alias find='fd'
alias cd='z'                           # or keep cd and use z as the smart variant

# fzf + ripgrep integration: Ctrl-T file preview with bat
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :100 {}'"
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# git + fzf: fuzzy-checkout branches
gco() {
  git branch --all | fzf --preview 'git log --oneline --color=always {1}' | \
    sed 's/remotes\/origin\///' | xargs git checkout
}
```

**Starship configuration** lives at `~/.config/starship.toml`. A minimal forensics/dev-friendly config:

```toml
# ~/.config/starship.toml
format = """
$username$hostname$directory$git_branch$git_status$python$node$rust$golang$cmd_duration$line_break$character"""

[directory]
truncation_length = 4
truncate_to_repo = true

[git_branch]
symbol = " "

[git_status]
conflicted = "🚨"
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
untracked = "?"
modified = "!"
staged = "+"

[cmd_duration]
min_time = 2_000
format = "took [$duration](bold yellow) "

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
```

### 7. tmux for persistent sessions

tmux is a terminal multiplexer: it runs on a server (local or remote), manages sessions independently of your terminal, and lets you detach (your terminal closes / SSH drops) and reattach later to find everything still running.

**Why tmux beats just opening multiple terminal tabs:**
- Sessions survive SSH disconnects
- Sessions survive closing Terminal.app or your laptop lid
- A single `tmux attach` from a new terminal (or after reconnecting SSH) drops you right back
- Scriptable layouts: start your project with `tmux new-session -d -s dev \; split-window -h \; send-keys 'nvim .' Enter`

**Essential vocabulary:**
```
Session   — the outermost container; one per project or context
Window    — like a tab within a session (Ctrl-b c = new, Ctrl-b n/p = next/prev)
Pane      — a split within a window (Ctrl-b % = vertical, Ctrl-b " = horizontal)
```

**Minimal `~/.tmux.conf`:**
```bash
# Prefix: change to Ctrl-a (more ergonomic than Ctrl-b)
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Mouse support (resize panes, click to select)
set -g mouse on

# Start windows and panes at 1 (keyboard-natural indexing)
set -g base-index 1
setw -g pane-base-index 1

# Vi-mode copy (press Ctrl-a [, navigate with hjkl, v to select, y to yank)
setw -g mode-keys vi
bind-key -T copy-mode-vi 'v' send -X begin-selection
bind-key -T copy-mode-vi 'y' send -X copy-selection

# 256 color + true color
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Increase scrollback
set -g history-limit 50000

# Status bar
set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
set -g status-right ' #{session_name} | %H:%M '

# Reload config without restarting
bind r source-file ~/.tmux.conf \; display "Config reloaded"

# Pane navigation (vim-style)
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
```

**Daily tmux workflow:**
```bash
# Start a new named session
tmux new -s myproject

# Detach (leave everything running)
# Ctrl-a d

# List sessions
tmux ls

# Reattach
tmux attach -t myproject

# Kill a session
tmux kill-session -t myproject
```

**tmux vs Zellij in 2026:** Zellij has a better out-of-box UX (on-screen key hints, floating panes, better defaults) and is worth trying for local development. For SSH workflows and remote servers — where tmux is likely already installed — tmux remains the standard. The recommendation: **tmux for SSH/remote; either for local**. This guide covers tmux because it is universally available and the existing ecosystem (tmux plugins, status-bar integrations) is mature.

> 🪟 **Windows contrast:** The Windows Terminal introduced pane splitting in 2022, but sessions don't persist. ConPTY + Windows Terminal comes close to tmux for local work; on remote Linux/BSD servers there's no equivalent without installing tmux yourself.

### 8. Neovim + VS Code/Cursor coexistence

**Neovim** (`nvim`) is the terminal editor of choice for editing configs, reviewing git diffs, quick file edits over SSH, and anything where opening a GUI editor is overkill. The ecosystem around it (lazy.nvim plugin manager, LSP via nvim-lspconfig, tree-sitter parsers for syntax, telescope.nvim for fuzzy finding) has matured to IDE-grade capability.

**The coexistence pattern:** Use VS Code or Cursor for large projects with GUI debugging. Use Neovim for:
- Git commit messages (`EDITOR=nvim git commit`)
- Editing dotfiles and configs
- SSH remote editing (`nvim sftp://host/path/to/file` via plugin, or ssh + nvim locally)
- Quick edits from the terminal without focus-switching

The two share nothing by default, but can share some config:
```zsh
export EDITOR="nvim"
export VISUAL="cursor"   # or "code"; used by GUI-aware programs
```

A minimal Neovim kickstart: `git clone https://github.com/nvim-lua/kickstart.nvim ~/.config/nvim`. This bootstraps lazy.nvim, LSP, telescope, and treesitter with sane defaults.

---

## Dotfiles Management

### The problem

A developer's terminal environment is a corpus of ~20-50 files scattered across `~`: `.zshrc`, `.zprofile`, `.gitconfig`, `.tmux.conf`, `~/.config/starship.toml`, `~/.ssh/config` (but NOT private keys), `~/.config/nvim/`, and more. Without version control and an install mechanism, reproducing this environment on a second Mac involves hours of remembering what you did.

### Strategy options

**Three patterns, in order of sophistication:**

#### Option A: Bare git repo (the "bare repo trick")
A git repo with `--bare` initialised into `~/.dotfiles`, using `$HOME` as the working tree. No symlinks. Files live at their real paths; git just knows about them.

```bash
# Initial setup (once)
git init --bare ~/.dotfiles
alias dot='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
dot config status.showUntrackedFiles no

# Track a file
dot add ~/.zshrc
dot commit -m "add zshrc"
dot remote add origin git@github.com:you/dotfiles.git
dot push

# Bootstrap on a new Mac
git clone --bare git@github.com:you/dotfiles.git ~/.dotfiles
alias dot='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
dot checkout   # may need --force if stock files conflict
```

**Pros:** Zero dependencies beyond git. **Cons:** No per-machine templating; secrets management is manual.

#### Option B: GNU Stow + a dotfiles repo
Keep dotfiles in `~/dotfiles/` organized in package subdirectories mirroring the target paths. `stow` creates symlinks from `~/dotfiles/<package>/` into `~`.

```
~/dotfiles/
  zsh/
    .zshrc
    .zprofile
  git/
    .gitconfig
    .config/
      git/
        ignore
  tmux/
    .tmux.conf
  nvim/
    .config/
      nvim/
        init.lua
```

```bash
brew install stow
cd ~/dotfiles
stow zsh git tmux nvim      # creates symlinks in ~
stow -D zsh                 # unlink (delete symlinks for the zsh package)
stow --adopt zsh            # move existing files into the stow tree (use carefully)
```

**Pros:** Simple, reversible, no database. **Cons:** No templating or secrets; cross-machine differences require manual `if [[ "$(hostname)" == ...]` in the files themselves.

#### Option C: chezmoi (recommended for cross-Mac workflows)
chezmoi is a purpose-built dotfiles manager with Go templating, encrypted secrets, `run_once_` scripts, and a source/target model that handles per-machine differences cleanly.

```bash
brew install chezmoi
chezmoi init   # creates ~/.local/share/chezmoi as the source repo
```

**Key concepts:**
- Source tree at `~/.local/share/chezmoi/` (itself a git repo)
- Files prefixed with `dot_` map to `.` files (e.g. `dot_zshrc` → `~/.zshrc`)
- `exact_` prefix: chezmoi enforces directory contents exactly (removes extra files)
- Template files end in `.tmpl` and use Go template syntax for per-machine values
- `run_once_` scripts run exactly once (on first deploy or when their content changes)
- `run_onchange_` scripts re-run whenever the script content changes

**Setup and usage:**

```bash
# Add files to chezmoi management
chezmoi add ~/.zshrc
chezmoi add ~/.gitconfig
chezmoi add ~/.tmux.conf
chezmoi add ~/.config/starship.toml
chezmoi add ~/.config/nvim/

# Edit a managed file (opens in $EDITOR, updates source tree)
chezmoi edit ~/.zshrc

# Preview what chezmoi would change
chezmoi diff

# Apply changes to home directory
chezmoi apply

# Push source tree to GitHub
cd $(chezmoi source-path)
git remote add origin git@github.com:you/dotfiles.git
git push -u origin main

# Bootstrap a new Mac (one command after brew install chezmoi)
chezmoi init --apply git@github.com:you/dotfiles.git
```

**Per-machine templating** (the cross-Mac killer feature):

```
# ~/.local/share/chezmoi/dot_gitconfig.tmpl
[user]
    name = {{ .name }}
    email = {{ .email }}

[core]
    # Work Mac uses a different signing key
    {{- if eq .chezmoi.hostname "work-macbook" }}
    signingkey = ~/.ssh/id_ed25519_work.pub
    {{- else }}
    signingkey = ~/.ssh/id_ed25519.pub
    {{- end }}
```

The `.chezmoi.yaml.tmpl` prompts for values on first run:
```yaml
# ~/.local/share/chezmoi/.chezmoi.yaml.tmpl
data:
    name: {{ promptString "Full name" }}
    email: {{ promptString "Email" }}
```

**Secrets:** chezmoi integrates with the macOS Keychain via `chezmoi secret keychain get-password`. Never commit plaintext secrets. See [[04-keychain-and-secrets]].

> 🔬 **Forensics note:** `~/.local/share/chezmoi/` contains the full history (as a git repo) of every dotfile change ever made on the machine, including timestamps. This is a high-value artifact — it can show when SSH configs, git identities, or proxy settings were added or modified, even if the live `~/.ssh/config` was later overwritten.

### The Brewfile

A `Brewfile` is a dependency manifest for Homebrew. It captures every installed formula, cask, tap, and Mac App Store app (via `mas`). It is the package equivalent of `package.json` for your Mac.

```bash
# Generate from current installs
brew bundle dump --file=~/dotfiles/Brewfile --force

# Install everything from a Brewfile (new Mac bootstrap)
brew bundle install --file=~/dotfiles/Brewfile

# Check what's installed but not in the Brewfile, or missing
brew bundle check --file=~/dotfiles/Brewfile
```

Example `Brewfile`:
```ruby
tap "homebrew/bundle"
tap "homebrew/cask-fonts"

# Dev CLI stack
brew "git"
brew "starship"
brew "eza"
brew "bat"
brew "ripgrep"
brew "fd"
brew "fzf"
brew "zoxide"
brew "git-delta"
brew "jq"
brew "yq"
brew "gh"
brew "tldr"
brew "btop"
brew "dust"
brew "ncdu"
brew "hyperfine"
brew "watch"
brew "neovim"
brew "tmux"
brew "chezmoi"
brew "openssh"       # newer than Apple's bundled ssh
brew "mas"           # Mac App Store CLI

# Casks
cask "ghostty"       # or iTerm2 / Warp
cask "cursor"        # AI-augmented VS Code fork
cask "font-jetbrains-mono-nerd-font"  # for Starship icons

# Mac App Store
mas "Amphetamine", id: 937984704
```

> ⚠️ **iCloud / cross-Mac path caution (this repo's context):** This repo lives at `~/dev/PhantomLives/`. Keep your `~/dotfiles/` repo at `~/dev/dotfiles/` or `~/.local/share/chezmoi/` (chezmoi's default) — **not under `~/Documents/` or `~/Desktop/`**, both of which are iCloud-synced and will corrupt build artifacts with `' 2'`-suffixed duplicates and slow every `mv`/`cp`. See the top-level `CLAUDE.md` for the full rationale. SSH config and private keys must **never** be committed; `~/.ssh/` should be in `.gitignore` or managed via chezmoi's `age`-encrypted secrets.

### What to track / what not to track

**Track (commit to dotfiles repo):**
```
~/.zshrc, ~/.zprofile, ~/.zshenv
~/.gitconfig
~/.config/git/ignore
~/.tmux.conf
~/.config/starship.toml
~/.config/nvim/          (init.lua, lua/ tree)
~/.ssh/config            (host stanzas, NOT keys or known_hosts)
~/dotfiles/Brewfile
~/.config/btop/
~/.config/bat/config
~/.config/delta/         (if separate from gitconfig)
```

**Never track:**
```
~/.ssh/id_*             (private keys — use 1Password or Secure Enclave)
~/.ssh/known_hosts      (machine-specific, noise)
~/.netrc                (credentials)
~/.aws/credentials
~/.env, .env.local
~/Library/              (macOS app data — huge, binary, changes constantly)
~/.config/iterm2/       (use iTerm's own sync to iCloud or a dotfiles script)
~/.DS_Store             (in global gitignore already)
```

---

## Hands-on (CLI & GUI)

### Verify PATH order

```bash
echo $PATH | tr ':' '\n'
# Expected first entries on Apple Silicon:
# /opt/homebrew/bin
# /opt/homebrew/sbin
# Then: /usr/local/bin /usr/bin /bin /usr/sbin /sbin
which git       # Should be /opt/homebrew/bin/git after brew install git
which python3   # Usually /opt/homebrew/bin/python3 if brew python installed
```

### Test the fzf integrations

After wiring `source <(fzf --zsh)` into `.zshrc` and sourcing it:

```bash
# Ctrl-R: fuzzy history search (try it now)
# Ctrl-T: fuzzy file picker, inserts path at cursor
# Alt-C:  fuzzy cd (navigate directories interactively)

# Manual fzf with ripgrep integration: search file contents
rg --line-number '' | fzf --delimiter ':' --preview 'bat --highlight-line {2} {1}' \
   --preview-window 'right:60%:wrap'
```

### Test zoxide

```bash
# zoxide builds its frecency database as you cd
cd ~/dev/PhantomLives
cd ~/Downloads
z phan        # jumps back to ~/dev/PhantomLives (frecency match)
zi            # interactive fzf picker of known directories
```

### Inspect git configuration layers

```bash
git config --list --show-origin --show-scope
# Shows every config key, which file it came from, and its scope (system/global/local)
# Useful for debugging why a setting isn't taking effect
```

### gh CLI essentials

```bash
gh auth login              # authenticate (stores token in Keychain via osxkeychain)
gh repo view               # view current repo
gh pr list                 # list open PRs
gh pr create               # create PR (interactive)
gh run list                # list recent CI runs
gh run watch               # stream a running workflow
gh issue create            # create an issue
gh browse                  # open repo in browser
gh copilot suggest "list all open ports"  # AI assist (if Copilot license)
```

---

## 🧪 Labs

### Lab 1: Install the modern CLI stack and wire it up

> ⚠️ **ADVANCED / DESTRUCTIVE:** This modifies `~/.zshrc` and installs ~15 new binaries. Back up your current zsh config first:
> ```bash
> cp ~/.zshrc ~/.zshrc.backup-$(date +%Y%m%d)
> ```
> To roll back: `cp ~/.zshrc.backup-YYYYMMDD ~/.zshrc && brew uninstall eza bat ripgrep fd fzf zoxide git-delta starship btop dust hyperfine`

```bash
# 1. Install all tools
brew install git starship eza bat ripgrep fd fzf zoxide git-delta jq yq gh tldr btop dust ncdu hyperfine watch neovim tmux

# 2. Add to ~/.zshrc (append these blocks)
cat >> ~/.zshrc << 'ZSHBLOCK'

# ── Modern CLI stack ──────────────────────────────────────────
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
source <(fzf --zsh)

alias ls='eza --icons --group-directories-first --color=always'
alias ll='eza --long --icons --git --group-directories-first --color=always'
alias la='eza --long --icons --git --group-directories-first --color=always --all'
alias tree='eza --tree --icons --color=always'
alias cat='bat --style=plain'

export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :100 {}'"
ZSHBLOCK

# 3. Reload
source ~/.zshrc

# 4. Verify
ll ~/dev          # should show colored long listing with git status
z /              # should work (zoxide primes on cd)
bat ~/.zshrc     # should show syntax-highlighted .zshrc
rg 'alias' ~/.zshrc   # ripgrep search
```

### Lab 2: Configure git completely

> ⚠️ This modifies `~/.gitconfig` and `~/.ssh/`. Back up: `cp ~/.gitconfig ~/.gitconfig.backup`

```bash
# Set global config
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global credential.helper osxkeychain
git config --global core.pager "delta"
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.side-by-side true
git config --global diff.algorithm histogram
git config --global merge.conflictstyle zdiff3

# Set up global .gitignore
mkdir -p ~/.config/git
cat > ~/.config/git/ignore << 'EOF'
.DS_Store
.DS_Store?
._*
*.swp
*~
.env
.env.local
.venv/
__pycache__/
EOF
git config --global core.excludesfile ~/.config/git/ignore

# Generate SSH key (skip if you already have one)
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519

# Add to ssh-agent (launchd-backed; persists across reboots)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Configure SSH commit signing
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global user.signingkey ~/.ssh/id_ed25519.pub

# Set up allowed_signers
mkdir -p ~/.config/git
echo "you@example.com namespaces=\"git\" $(cat ~/.ssh/id_ed25519.pub)" >> ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers

# Add public key to GitHub for signing
gh auth login   # if not already done
gh ssh-key add ~/.ssh/id_ed25519.pub --title "MacBook $(date +%Y%m%d)" --type signing

# Test: make a signed commit
cd /tmp && git init test-signing && cd test-signing
git commit --allow-empty -m "test signed commit"
git log --show-signature -1   # should show "Good \"git\" signature"

# Cleanup
cd /tmp && rm -rf test-signing
```

### Lab 3: Set up dotfiles with chezmoi + Brewfile

> ⚠️ chezmoi will manage files in your home directory. Preview every change with `chezmoi diff` before `chezmoi apply`. To undo adding a file: `chezmoi forget ~/.zshrc` (removes from management but does NOT delete the live file).

```bash
# 1. Install chezmoi
brew install chezmoi

# 2. Initialize (creates ~/.local/share/chezmoi as a git repo)
chezmoi init

# 3. Add your key dotfiles
chezmoi add ~/.zshrc
chezmoi add ~/.gitconfig
chezmoi add ~/.config/git/ignore
chezmoi add ~/.tmux.conf           # if you created one
chezmoi add ~/.config/starship.toml

# 4. Inspect the source tree
ls ~/.local/share/chezmoi/
# You'll see: dot_zshrc  dot_gitconfig  .config/  etc.

# 5. Edit through chezmoi (keeps source + live in sync)
chezmoi edit ~/.zshrc   # opens in $EDITOR; chezmoi apply runs after save

# 6. Push to GitHub
cd ~/.local/share/chezmoi
git init   # already done by chezmoi init
git remote add origin git@github.com:YOU/dotfiles.git
git add .
git commit -m "initial dotfiles"
git push -u origin main

# 7. Generate Brewfile
brew bundle dump --file=~/.local/share/chezmoi/Brewfile --force
chezmoi add ~/.local/share/chezmoi/Brewfile 2>/dev/null || true
# Brewfile already lives in the source dir; commit it
cd ~/.local/share/chezmoi && git add Brewfile && git commit -m "add Brewfile"
git push

# 8. Simulate new Mac bootstrap (read-only test)
chezmoi diff   # shows what would be applied; should be empty if already applied
```

**Bootstrap script for a new Mac** (save as `~/.local/share/chezmoi/run_once_bootstrap.sh.tmpl`):
```bash
#!/bin/bash
set -e
# Runs exactly once on chezmoi init --apply (content-hash tracked by chezmoi)

# Install Homebrew
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install all packages from Brewfile
brew bundle install --file="{{ .chezmoi.sourceDir }}/Brewfile" --no-lock

echo "Bootstrap complete. Open a new shell."
```

### Lab 4: tmux project session

```bash
# Install tmux if not done
brew install tmux

# Apply the .tmux.conf from earlier, then:
tmux new-session -s dev

# Inside tmux:
# Ctrl-a %     split vertically (editor left, terminal right)
# Ctrl-a h/l   switch panes
# In left pane: nvim .
# In right pane: run tests, git ops
# Ctrl-a d     detach (close terminal; session stays alive)
tmux attach -t dev   # reattach from any new terminal window
```

---

## Pitfalls & gotchas

**PATH order breaks after Rosetta or pyenv:** If you install a Rosetta-translated tool, it may inject `/usr/local/bin` before `/opt/homebrew/bin`. Always `which <tool>` after installing something that shadow-replaces a standard binary. Fix: ensure `/opt/homebrew/bin` is first in `/etc/paths.d/homebrew` or early in `.zprofile`.

**`alias cat='bat'` breaks some scripts:** Scripts that call `cat` for non-text output (raw binary streams) will have bat try to syntax-highlight them. Use `alias cat='bat --style=plain'` or add `command cat` in the rare script that needs it. Never alias `cat` in scripts themselves — only in interactive `.zshrc`.

**`alias find='fd'` breaks system scripts:** `fd` is not a drop-in; it ignores the `-exec` syntax and many standard `find` flags. Keep the alias for interactive use but be aware scripts that invoke `find` will use the un-aliased version (aliases don't apply in non-interactive shells by default — which is correct behavior).

**tmux and true color:** If colors look wrong in tmux+neovim, ensure `set -g default-terminal "tmux-256color"` and `set -ga terminal-overrides ",xterm-256color:Tc"` are in `.tmux.conf`. Also set `$TERM` appropriately in `.zshrc` (`export TERM=xterm-256color` when not inside tmux).

**chezmoi and files you don't own:** chezmoi cannot manage files outside `$HOME` (system configs, `/etc/`). Use a `run_once_` script for those, or manage them separately.

**SSH key in macOS Keychain not persisting across reboots:** The correct invocation is `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` (note: `--apple-use-keychain`, not the deprecated `-K`). Also ensure `~/.ssh/config` has:
```
Host *
    UseKeychain yes
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
```

**git delta and $PAGER conflicts:** If you have `$PAGER=less` set and also `core.pager=delta`, git uses delta. But `bat` uses its own pager. They don't conflict but it's worth knowing: `BAT_PAGER=less` controls bat's pager independently.

**iCloud corrupting `~/dotfiles/` if placed under Documents:** `.git` object files get `' 2'`-suffixed duplicates; `git status` becomes permanently confused. Keep dotfiles repos under `~/dev/` which is outside iCloud reach. The same rule that protects this PhantomLives repo protects your dotfiles.

---

## Key takeaways

1. **Install Homebrew's git immediately** — the CLT version lags too far behind for modern signing features and pager integration.
2. **osxkeychain + SSH signing is the correct 2026 credential stack** — one `ssh-add --apple-use-keychain` command and git operations become silent forever; signed commits add verified badges on GitHub with no extra overhead.
3. **The modern Rust CLI stack** (eza, bat, ripgrep, fd, fzf, zoxide, delta, starship) is not optional polish — each tool is meaningfully faster or more capable than the POSIX ancestor it replaces, and all install in under two minutes.
4. **chezmoi wins for cross-Mac portability** because it handles per-machine templating, encrypted secrets, and bootstrap scripts — things bare-repo and stow cannot. The source tree is a plain git repo you push to GitHub.
5. **The Brewfile is the `package.json` of your Mac** — commit it to your dotfiles, and a new machine goes from bare to fully-equipped with `brew bundle install`.
6. **tmux is non-negotiable for SSH work** — sessions survive disconnects; script your project startup layouts rather than recreating them manually.
7. **Never commit secrets** — SSH private keys, `.env` files, and API tokens stay in the macOS Keychain or an encrypted secrets manager; chezmoi supports `age`-encrypted files for the subset of secrets that must travel with dotfiles.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| **CLT** | Command Line Tools — Apple's developer toolchain, separate from Xcode; ships its own older git |
| **osxkeychain** | git credential helper that stores HTTPS tokens in the macOS Keychain |
| **SSH commit signing** | Using an SSH key (via `gpg.format = ssh`) to cryptographically sign git commits instead of GPG |
| **starship** | Cross-shell prompt renderer written in Rust; configured via TOML |
| **eza** | Modern `ls` replacement in Rust with git awareness, icons, and tree mode |
| **bat** | `cat` replacement with syntax highlighting and git decorations |
| **ripgrep** (`rg`) | Fast, `.gitignore`-aware recursive file content searcher |
| **fd** | Fast, ergonomic `find` replacement |
| **fzf** | General-purpose fuzzy finder; integrates with shell history, file selection, git |
| **zoxide** | Frecency-ranked smart `cd`; learns from your navigation patterns |
| **git-delta** | Pager/formatter for `git diff` and `git show` with syntax highlighting |
| **tmux** | Terminal multiplexer; manages persistent sessions independent of the connected terminal |
| **chezmoi** | Dotfiles manager with Go templating, encrypted secrets, and bootstrap scripts |
| **GNU Stow** | Symlink farm manager for dotfiles; simpler but no templating |
| **Brewfile** | Declarative Homebrew package manifest (`brew bundle`) |
| **bare git repo** | A git repository with no working tree (`git init --bare`); used in the dotfiles-as-bare-repo pattern |
| **allowed_signers** | File mapping email addresses to SSH public keys for commit signature verification |

---

## Further reading

- [chezmoi documentation](https://www.chezmoi.io/) — especially "daily operations" and "templating"
- [GNU Stow manual](https://www.gnu.org/software/stow/manual/) — the canonical reference for the symlink-farm approach
- [GitHub Docs: Signing commits with SSH](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- [Howard Oakley — macOS SSH and Secure Enclave keys](https://eclecticlight.co/) — search "SSH" for deep dives into macOS keychain + SSH agent interaction
- [dotfiles.github.io](https://dotfiles.github.io/utilities/) — curated list of dotfile managers and community resources
- [Modern Unix](https://github.com/ibraheemdev/modern-unix) — comprehensive catalogue of modern CLI replacements
- [tmux Plugin Manager (TPM)](https://github.com/tmux-plugins/tpm) — extends tmux with tmux-resurrect (session persistence across reboots), tmux-continuum, and others
- [[03-cli/12-homebrew-and-package-management]] — Homebrew internals, taps, casks, and the `brew` command in depth
- [[03-cli/10-ssh-and-remote-access]] — SSH config, key types, ProxyJump, and SSH tunnels
- [[05-security-forensics/04-keychain-and-secrets]] — Keychain internals, `security` CLI, and forensic extraction of stored credentials
