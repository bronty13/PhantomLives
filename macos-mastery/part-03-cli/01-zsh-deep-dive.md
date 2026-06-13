---
title: "zsh Deep Dive"
part: "P03 — CLI Mastery"
est_time: "60 min read + 45 min labs"
prerequisites: [02-terminal-emulators, 01-filesystem-hierarchy]
tags: [macos, zsh, shell, cli, completion, globbing, history, prompt, forensics]
---

# zsh Deep Dive

> **In one sentence:** zsh is Apple's default shell since Catalina — a superset of bash with a programmable completion engine, industrial-strength globbing, and a plugin ecosystem that makes it the most productive interactive shell on macOS, once you understand its layered startup sequence and opt-in features.

---

## Why this matters

Every forensic artifact you chase, every admin task you automate, every build pipeline you debug — it runs through this shell. Knowing *why* `compinit` must precede Oh My Zsh, why glob qualifiers obsolete half your `find` invocations, and how history options interact across sessions is the difference between a shell that fights you and one that amplifies every command you type.

> 🪟 **Windows contrast:** PowerShell's profile system (`$PROFILE` — five ordered files per host/user combination) parallels zsh's startup sequence, but PowerShell tab completion is class-based (`IArgumentCompleter`) and compiled. zsh's completion system is interpreted at startup but far more portable and composable. Fish (the other popular alternative) compiles completions from man pages automatically; zsh requires explicit definition but gives finer control.

---

## Concepts

### 1. The Startup Sequence: Which File Does What

zsh loads files in a fixed, well-defined order. Getting this wrong is the cause of 80% of "why isn't my PATH set?" bugs.

```
Login shell                 Interactive shell only
─────────────────           ──────────────────────
/etc/zshenv    ←── always, every shell, every user (set ZDOTDIR here if needed)
~/.zshenv      ←── always (exports that ALL processes need: EDITOR, LANG, ZDOTDIR)
/etc/zprofile
~/.zprofile    ←── login only (brew shellenv, PATH additions for GUI apps)
/etc/zshrc
~/.zshrc       ←── interactive only (prompt, aliases, functions, completions, plugins)
/etc/zlogin
~/.zlogin      ←── login only, after rc (rarely used; leave empty)
─── on logout ────
~/.zlogout
```

**The critical rules:**

- `~/.zshenv` is sourced by *every* zsh process — scripts, `xargs`, subshells. Keep it minimal. Setting a giant `PATH` here taxes every subprocess.
- `~/.zprofile` is where `eval "$(brew shellenv)"` belongs so GUI-launched apps (and login shells opened via Terminal) see Homebrew's `/opt/homebrew/bin`. On Apple Silicon, Homebrew lives at `/opt/homebrew`; on Intel it was `/usr/local`. Using `$(brew --prefix)` is the portable form.
- `~/.zshrc` is where 99% of your customization lives — but only for *interactive* shells. Never `export PATH` here without also doing it in `.zprofile`; scripts that source `.zshrc` are a portability trap.

> 🔬 **Forensics note:** When investigating a compromised account, check all five user-level startup files plus `/etc/zshenv` and `/etc/zshrc`. Attackers insert persistence into `.zshenv` because it fires for every shell invocation (including cron and SSH exec). Look at mtime, compare against known-good baseline, check for base64-encoded payloads or curl-pipe-bash idioms. `/private/var/log/install.log` and Unified Logging (`log show --predicate 'process == "zsh"'`) can correlate shell invocations with suspicious events.

---

### 2. The Prompt: PROMPT, RPROMPT, and Prompt Expansion

zsh uses `PROMPT` (left) and `RPROMPT` (right). Prompt expansion sequences begin with `%`:

| Sequence | Expands to |
|---|---|
| `%n` | username |
| `%m` | hostname (short) |
| `%~` | `$PWD` with `~` substitution |
| `%#` | `#` if root, `%` otherwise |
| `%?` | exit status of last command |
| `%j` | number of background jobs |
| `%D{fmt}` | date/time using `strftime` format |
| `%F{color}…%f` | foreground color |
| `%B…%b` | bold |
| `%K{color}…%k` | background color |

Enable prompt substitution (required for dynamic content like git status):

```zsh
setopt PROMPT_SUBST
```

**Minimal but informative prompt:**

```zsh
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
zstyle ':vcs_info:git:*' formats '%F{yellow}(%b)%f'
zstyle ':vcs_info:*' enable git

PROMPT='%F{cyan}%n@%m%f %F{green}%~%f ${vcs_info_msg_0_} %# '
RPROMPT='%F{red}%?%f %*'
```

`vcs_info` is a built-in zsh module. The `precmd_functions` array runs before each prompt render. `zstyle` sets configuration for the `vcs_info` subsystem — the first argument is a pattern that selects which VCS and context the style applies to.

**Alternative: Starship (cross-shell, Rust-based)**

```zsh
# In .zshrc, after all fpath/compinit work:
eval "$(starship init zsh)"
```

Starship reads `~/.config/starship.toml` and renders in ~1–5ms via a native binary. It handles git, language version, exit status, jobs, duration automatically. The tradeoff: it forks a process per prompt render, which is measurable but usually acceptable on Apple Silicon.

**Alternative: Powerlevel10k**

p10k is the most feature-complete prompt framework. Its "instant prompt" feature caches the prompt to disk so the first frame appears before `.zshrc` finishes loading:

```zsh
# Near the TOP of .zshrc, before any slow setup:
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
```

---

### 3. The Completion System: compinit, fpath, zstyle

zsh's completion system is built around three concepts: the **function path** (`fpath`), the **initialization** (`compinit`), and the **style system** (`zstyle`).

**fpath** is an array of directories zsh searches for autoloaded functions. Completion functions are named `_toolname` and live in these directories. The system ships completion functions in `/usr/share/zsh/$(zsh --version | awk '{print $2}')/functions/`.

```zsh
# Correct fpath setup — must happen BEFORE compinit
fpath=(
  "$(brew --prefix)/share/zsh/site-functions"   # Homebrew completions
  ~/.zsh/completions                              # your own _functions
  $fpath                                          # system default (keep last)
)

autoload -Uz compinit
compinit
```

The `autoload -Uz` flags: `-U` suppresses alias expansion inside the loaded function; `-z` forces zsh-style autoloading regardless of `KSH_AUTOLOAD`.

**Performance optimization** — skip the full security check on most launches:

```zsh
# Only re-check daily; saves ~200ms on every shell open
autoload -Uz compinit
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C   # skip security check, use cache
fi
```

The `(#qN.mh+24)` is a glob qualifier (covered below): `N` = no error if no match, `.` = regular file, `mh+24` = modified more than 24 hours ago.

**zstyle** configures completion behavior:

```zsh
zstyle ':completion:*' menu select              # arrow-key menu navigation
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"  # color file types
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'      # case-insensitive
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:warnings' format 'No completions for: %d'
zstyle ':completion::complete:*' use-cache on
zstyle ':completion::complete:*' cache-path ~/.zcompcache
```

The `:completion:*` pattern hierarchy is `:completion:function:completer:command:argument:tag`. `menu select` enables the interactive menu; press Tab to enter it, then arrow keys to navigate, Enter to accept, Escape to cancel.

**Generating completions for CLI tools:**

Many modern tools emit their own completion functions:

```zsh
# One-time generation — put in fpath directory:
gh completion -s zsh > "$(brew --prefix)/share/zsh/site-functions/_gh"
rustup completions zsh > "$(brew --prefix)/share/zsh/site-functions/_rustup"
uv generate-shell-completion zsh > ~/.zsh/completions/_uv

# After adding any completion file, rebuild the cache:
rm -f ~/.zcompdump* && exec zsh
```

> 🔬 **Forensics note:** The `~/.zcompdump` file lists every completion function zsh found at startup time, along with its fpath source. It's a quick inventory of what tooling is installed and where. If an attacker installed a rogue `_sudo` or `_git` completion to intercept arguments, it would appear in this dump. Check `zstyle ':completion:*' dump-to-file` and diff against baseline.

---

### 4. Globbing: Extended Globbing, Recursive `**`, and Glob Qualifiers

zsh's glob system is Turing-complete enough to replace most simple `find` invocations.

**Enable extended globbing:**

```zsh
setopt EXTENDED_GLOB
```

Without this, `^`, `#`, and `~` have no special meaning in globs.

**Basic glob reminders:**

```zsh
*.txt          # all .txt files
**/*.txt        # recursive .txt (does NOT follow symlinks)
***/*.txt       # recursive .txt (DOES follow symlinks — rarely wanted)
```

**Extended glob operators (require `EXTENDED_GLOB`):**

| Pattern | Meaning |
|---|---|
| `^foo` | anything that does NOT match `foo` |
| `foo~bar` | matches `foo` but not `bar` |
| `foo#` | zero or more `foo` |
| `foo##` | one or more `foo` |
| `(foo|bar)` | alternation |
| `<1-255>` | numeric range |

**Glob qualifiers** — the real power. Added in `()` after the pattern:

```zsh
# File type qualifiers
*(.)       # regular files only (no dirs, no symlinks)
*(/)       # directories only
*(@)       # symlinks only
*(%)       # device files
*(=)       # sockets
*(p)       # named pipes (FIFOs)

# Permission qualifiers
*(r)       # readable by owner
*(w)       # writable by owner
*(x)       # executable by owner
*(R)       # world-readable
*(W)       # world-writable  ← forensics gold
*(X)       # world-executable
*(f755)    # exact permissions 755
*(f-100)   # owner lacks execute bit

# Ownership
*(u0)      # owned by UID 0 (root)
*(u:bronty13:)  # owned by specific user

# Time qualifiers (d=days, h=hours, m=minutes, s=seconds)
*(mh-1)    # modified in the last 1 hour
*(md-7)    # modified in the last 7 days
*(md+30)   # modified MORE than 30 days ago
*(am-1)    # accessed in the last 1 minute
*(c-1)     # inode changed today (ctime)

# Size qualifiers (k=KB, m=MB, g=GB)
*(Lm+100)  # larger than 100 MB
*(Lk-50)   # smaller than 50 KB
*(Le'[[ $REPLY -eq 0 ]]')  # arbitrary test via shell function

# Ordering + slicing
*(om)      # ordered by mtime, newest first
*(om[1])   # the single newest file
*(om[1,5]) # the 5 newest files
*(OL)      # ordered by size, smallest first (O = reverse)
*(om[-1])  # the oldest file

# Combining qualifiers (AND logic by default):
**/*(u0WX.)    # world-executable files owned by root, recursively
**/*(.Lm+10)   # regular files larger than 10 MB, recursively
```

**Practical one-liners:**

```zsh
# Last-modified file in current directory:
ls -la *(om[1])

# All setuid binaries anywhere under /usr/local:
print -l /usr/local/**/*(s.)   # (s) = setuid set; . = regular file

# Empty directories:
print -l **/*(D/^F)    # D = include dotfiles, / = dir, ^F = non-full (empty)

# Files modified in the last 10 minutes, recursive:
print -l **/*(mh-1)    # more precisely: within 60 minutes; use mm-10 for min

# Remove all .DS_Store files without confirmation:
rm -- **/.DS_Store(N.)   # N = nullglob (no error if none found)
```

> 🔬 **Forensics note:** `**/*(u0WX.)` recursively finds world-executable, root-owned regular files — a classic SUID/world-exec audit without `find`. `**/*(c-1.)` catches files with inode changes in the last day (metadata writes like chmod/chown even without content change). These glob expressions run entirely in-process; no `find` fork needed.

---

### 5. History: The Full Configuration

zsh's history is stored in `$HISTFILE` (default: `~/.zsh_history`), written in an extended metafile format (timestamps + durations when `EXTENDED_HISTORY` is set).

```zsh
HISTFILE=~/.zsh_history
HISTSIZE=100000        # entries in memory
SAVEHIST=100000        # entries persisted to HISTFILE

setopt EXTENDED_HISTORY          # store timestamp and duration per entry
setopt HIST_EXPIRE_DUPS_FIRST    # when trimming, remove dups first
setopt HIST_IGNORE_DUPS          # don't record if identical to previous entry
setopt HIST_IGNORE_ALL_DUPS      # remove older dup anywhere in history
setopt HIST_FIND_NO_DUPS         # Ctrl-R skips dups even if stored
setopt HIST_IGNORE_SPACE         # commands prefixed with space are NOT saved
setopt HIST_SAVE_NO_DUPS         # don't write dups to disk
setopt HIST_REDUCE_BLANKS        # trim extra whitespace
setopt SHARE_HISTORY             # all sessions share one live history
# SHARE_HISTORY implies INC_APPEND_HISTORY; don't set both
```

**`SHARE_HISTORY` vs `INC_APPEND_HISTORY`:** `SHARE_HISTORY` writes each command to `$HISTFILE` immediately AND reads new entries from other sessions before each prompt. `INC_APPEND_HISTORY` writes immediately but does NOT read back — other sessions don't see each other's history until they start. Choose `SHARE_HISTORY` for multi-window workflows.

**History expansion in the command line:**

```zsh
!!            # repeat last command
!$            # last argument of previous command
!^            # first argument of previous command
!*            # all arguments of previous command
!foo          # most recent command starting with "foo"
!?foo?        # most recent command containing "foo"
!42           # history entry 42

^old^new      # quick substitution: replace first occurrence
!!:s/old/new/ # same as above (explicit form)
!!:gs/old/new # global substitution (all occurrences)

# ALT-. (option-period on Mac) inserts last argument of previous command
# Ctrl-R: interactive search (enhanced by fzf or atuin)
```

**`fc` — the history editor:**

```zsh
fc            # open last command in $EDITOR for editing, then execute
fc -l         # list last 16 history entries
fc -l 1       # list entire history from entry 1
fc -l -20     # last 20 entries
fc 42         # edit and re-run history entry 42
fc -e cat 1   # print entire history to stdout
```

> 🔬 **Forensics note:** `~/.zsh_history` with `EXTENDED_HISTORY` contains `: 1718123456:12;git push --force origin main` — Unix timestamp, elapsed seconds, then the command. This gives you a forensic audit trail of interactive commands with timing. Combine with `log show --predicate 'process == "Terminal"'` (Unified Log) to correlate. Under Full Disk Access, the history files of other accounts are readable from root — a rich artifact during incident response. zsh's history file is plaintext; no decryption needed.

---

### 6. Aliases vs Functions

**Aliases** are simple token substitution at parse time — no argument processing:

```zsh
alias ll='ls -lAFh'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ga='git add'
alias gcm='git commit -m'
alias gst='git status'
alias dk='docker'

# Global aliases — substituted anywhere in the line, not just at position 0:
alias -g L='| less'
alias -g G='| grep'
alias -g NUL='>/dev/null 2>&1'

# Suffix aliases — invoked when you run a file with that extension:
alias -s md='open -a "Marked 2"'
alias -s pdf='open'
alias -s py='python3'
```

**Functions** get full shell semantics, local variables, `$@`, error handling:

```zsh
# cd and immediately list contents
cdl() { cd "$1" && ls -lAFh }

# mkdir and cd into it
mkcd() { mkdir -p "$1" && cd "$1" }

# Show most-used commands (forensic/curiosity):
topcmds() {
  fc -l 1 | awk '{print $2}' | sort | uniq -c | sort -rn | head "${1:-20}"
}

# Quick HTTP server in current directory
serve() { python3 -m http.server "${1:-8000}" }

# Wrapper that times any command and beeps on failure
timed() {
  local start=$SECONDS
  "$@"
  local rc=$?
  local elapsed=$(( SECONDS - start ))
  (( rc != 0 )) && tput bel
  echo "Exit $rc in ${elapsed}s"
  return $rc
}
```

**The key distinction:** aliases cannot use `$1`, cannot be recursive, cannot `local`-scope variables, and are expanded before function lookup. Functions are first-class; they live in the function table alongside builtins. For anything beyond a word substitution, use a function.

---

### 7. Directory Navigation: Stack, AUTO_CD, cdpath

```zsh
setopt AUTO_CD           # typing a directory name without 'cd' changes to it
setopt AUTO_PUSHD        # every cd pushes to the directory stack
setopt PUSHD_IGNORE_DUPS # don't push same dir twice in a row
setopt PUSHD_SILENT      # don't print stack on every pushd/popd

# cdpath — zsh searches these directories when you cd to a relative path
cdpath=(. ~ ~/dev ~/dev/PhantomLives /opt)
# Now: `cd macos-mastery` from anywhere will find ~/dev/PhantomLives/macos-mastery
```

**Stack navigation:**

```zsh
pushd /tmp       # push /tmp, go there
popd             # return to previous dir
dirs -v          # numbered list of the stack
cd -3            # jump to stack entry 3 (tab-completes from dirs -v)
cd -             # toggle between last two dirs
```

> 🪟 **Windows contrast:** PowerShell has `Push-Location`/`Pop-Location` which map 1:1. The `$env:CDPATH` analogy is setting `$env:PSModulePath` to extend module discovery — similar concept, different namespace. PowerShell's `Set-Location -` also toggles, but the full stack navigation with `cd -N` is zsh-specific.

---

### 8. Key Bindings: bindkey and ZLE

zsh's **Zsh Line Editor (ZLE)** handles all interactive input. It supports two modes: `emacs` (default on macOS) and `vi`.

```zsh
# Select your mode:
bindkey -e    # emacs mode (default)
bindkey -v    # vi mode
```

**Useful emacs-mode bindings (always active):**

| Key | Action |
|---|---|
| Ctrl-A / Ctrl-E | beginning/end of line |
| Ctrl-K | kill to end of line |
| Ctrl-U | kill to beginning of line |
| Ctrl-W | kill previous word |
| ALT-F / ALT-B | forward/back one word |
| Ctrl-R | reverse history search |
| Ctrl-L | clear screen |
| Ctrl-X Ctrl-E | open current line in `$EDITOR` |

**Custom bindings:**

```zsh
# Edit command line in $EDITOR (vi-style; works in emacs mode too):
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# History search that respects what you've already typed:
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search    # up arrow
bindkey '^[[B' down-line-or-beginning-search  # down arrow

# Option-left/right: word navigation (macOS Terminal default keys):
bindkey '^[f' forward-word
bindkey '^[b' backward-word
```

**ZLE widgets** — you can write your own:

```zsh
# Insert today's date at cursor:
insert-date() { LBUFFER+=$(date '+%Y-%m-%d') }
zle -N insert-date
bindkey '^Xd' insert-date
```

`LBUFFER` and `RBUFFER` are the text left/right of the cursor; writing to them is how widgets modify the command line in real time.

---

### 9. The Plugin Ecosystem and the Performance Caveat

**Oh My Zsh (OMZ):** The most popular framework (~170k GitHub stars). Bundles 200+ plugins and themes, auto-calls `compinit`, manages updates. Great starting point. The tradeoff: a naive OMZ config with 10+ plugins routinely hits 1–2 second startup times.

```zsh
# Measure your startup time:
time zsh -i -c exit
# Or for a flamegraph:
zsh --sourcetrace 2>&1 | head -100
```

**zinit:** The performance-first alternative. Key features:
- **Turbo mode:** `zinit ice wait lucid` defers plugin loading until after the first prompt renders. The shell appears instantly; plugins load asynchronously.
- **Ice modifiers:** Fine-grained control over how/when each plugin loads.

```zsh
# Example zinit config (in .zshrc):
source ~/.local/share/zinit/zinit.git/zinit.zsh

# Core interactive plugins — load immediately:
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions

# Git completions — load in background (turbo mode):
zinit ice wait lucid
zinit light zsh-users/zsh-completions
```

**zsh-syntax-highlighting:** Colors the command line as you type — green for valid commands, red for unknown. Catches typos before you hit Enter.

**zsh-autosuggestions:** Suggests completions from history in gray text as you type; press the right arrow or End to accept. The most impactful single plugin for interactive efficiency.

```zsh
# Autosuggestions configuration:
ZSH_AUTOSUGGEST_STRATEGY=(history completion)  # fall back to completion
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20             # don't suggest for long commands
ZSH_AUTOSUGGEST_USE_ASYNC=1                    # non-blocking suggestion lookup
```

**The perf hierarchy (fastest to slowest startup):**

1. Hand-rolled `.zshrc` (no framework) — 50–100ms
2. zinit with turbo mode — perceived <100ms (true ~150ms)
3. zinit without turbo — 150–300ms depending on plugins
4. Oh My Zsh, minimal plugins — 300–600ms
5. Oh My Zsh, 10+ plugins — 800ms–2s+

**setopt cheatsheet** — the options worth knowing:

```zsh
# Navigation
setopt AUTO_CD              # bare dirname changes to it
setopt AUTO_PUSHD           # cd is always pushd
setopt PUSHD_IGNORE_DUPS

# Globbing
setopt EXTENDED_GLOB        # enable ^, ~, # in globs
setopt GLOB_DOTS            # include dotfiles without explicit '.*'
setopt NULL_GLOB            # silently expand empty globs (vs error)
setopt NOMATCH              # error on no match (default; opposite of NULL_GLOB)

# History
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# Correction
setopt CORRECT              # suggest corrections for mistyped commands
setopt CORRECT_ALL          # suggest for all words (overzealous; use with care)

# Misc
setopt NO_BEEP              # silence the terminal bell
setopt INTERACTIVE_COMMENTS # allow # comments in interactive shell
setopt COMBINING_CHARS      # handle Unicode combining characters correctly
setopt RC_QUOTES            # '' inside '' single-quotes = escaped single quote
```

---

## Hands-on (CLI & GUI)

**Inspect the active startup file sequence:**

```zsh
# Which files does your current shell trace through?
zsh --login --interactive -x -c exit 2>&1 | grep 'source\|/etc\|zsh'
```

**Inspect the completion system:**

```zsh
# What completion function handles 'git'?
whence -v _git

# Where are all fpath directories?
print -l $fpath

# What's cached in the dump file?
head -5 ~/.zcompdump

# Force a full re-scan:
rm -f ~/.zcompdump* && exec zsh
```

**Test glob qualifiers:**

```zsh
# In your home directory:
print -l ~/*(/)          # directories only
print -l ~/*(.)          # regular files only
print -l ~/*(.om[1])     # most recently modified regular file
print -l ~/*(Lm+10)      # files > 10 MB
```

**History surgery with fc:**

```zsh
fc -l -10                # last 10 commands with numbers
fc 50 60                 # re-run commands 50-60 in order
fc -e vim                # open last command in vim
```

**Bind a widget and test it:**

```zsh
# Paste this into your terminal (not .zshrc) to test:
autoload -Uz up-line-or-beginning-search
zle -N up-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
# Now type 'git' then press Up — only git history appears
```

---

## 🧪 Labs

### Lab 1: Build a production `.zshrc` from scratch

> ⚠️ **ADVANCED:** You will replace your current `.zshrc`. Back up first:
> ```zsh
> cp ~/.zshrc ~/.zshrc.bak-$(date +%Y%m%d)
> ```
> Rollback: `cp ~/.zshrc.bak-$(date +%Y%m%d) ~/.zshrc && exec zsh`

Create `~/.zshrc` with the following structure (adapt paths for your username):

```zsh
# ─── 0. Performance: instant prompt (if using Powerlevel10k) ────────────────
# [p10k instant prompt block goes here if using p10k]

# ─── 1. fpath — BEFORE compinit ──────────────────────────────────────────────
fpath=(
  "$(brew --prefix)/share/zsh/site-functions"
  ~/.zsh/completions
  $fpath
)

# ─── 2. Completion init ───────────────────────────────────────────────────────
autoload -Uz compinit
# Only re-check daily:
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# ─── 3. Completion styles ─────────────────────────────────────────────────────
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' use-cache on
zstyle ':completion::complete:*' cache-path ~/.zcompcache
zstyle ':completion:*:descriptions' format '%B%U%d%u%b'
zstyle ':completion:*:warnings' format '%B%Fno matches: %d%f%b'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

# ─── 4. History ───────────────────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY SHARE_HISTORY HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS HIST_SAVE_NO_DUPS

# ─── 5. Options ───────────────────────────────────────────────────────────────
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
setopt EXTENDED_GLOB GLOB_DOTS
setopt CORRECT INTERACTIVE_COMMENTS NO_BEEP
setopt PROMPT_SUBST

# ─── 6. Directory shortcuts ───────────────────────────────────────────────────
cdpath=(. ~ ~/dev ~/dev/PhantomLives)

# ─── 7. Prompt (vcs_info variant — no extra tools needed) ────────────────────
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
zstyle ':vcs_info:git:*' formats ' %F{yellow}[%b]%f'
zstyle ':vcs_info:git:*' actionformats ' %F{red}[%b|%a]%f'
zstyle ':vcs_info:*' enable git

PROMPT='%F{cyan}%n@%m%f %F{green}%~%f${vcs_info_msg_0_} %(?.%F{green}.%F{red})%#%f '
RPROMPT='%F{240}%*%f'

# ─── 8. Key bindings ──────────────────────────────────────────────────────────
bindkey -e   # emacs mode
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# ─── 9. Aliases ───────────────────────────────────────────────────────────────
alias ll='ls -lAFhG'
alias la='ls -AFhG'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias df='df -h'
alias du='du -sh'
alias path='print -l $PATH'

# Global aliases:
alias -g L='| less'
alias -g G='| grep'
alias -g NUL='>/dev/null 2>&1'
alias -g SORT='| sort | uniq -c | sort -rn'

# ─── 10. Functions ────────────────────────────────────────────────────────────
mkcd() { mkdir -p "$1" && cd "$1" }
cdl()  { cd "$1" && ll }
serve(){ python3 -m http.server "${1:-8000}" }
topcmds() { fc -l 1 | awk '{print $2}' | sort | uniq -c | sort -rn | head "${1:-20}" }

# ─── 11. Plugins (zsh-users, installed via Homebrew) ─────────────────────────
# brew install zsh-syntax-highlighting zsh-autosuggestions
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=1
source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# ─── 12. Tool integrations ────────────────────────────────────────────────────
# eval "$(starship init zsh)"    # if using Starship instead of vcs_info prompt
# eval "$(atuin init zsh)"       # if using Atuin for enhanced history search
# eval "$(zoxide init zsh)"      # if using zoxide for smart cd
```

After saving, reload:

```zsh
source ~/.zshrc
time zsh -i -c exit   # measure startup time
```

---

### Lab 2: Extended glob qualifier workout

> ⚠️ Work in a scratch directory to avoid accidental deletions:
> ```zsh
> mkdir /tmp/glob-lab && cd /tmp/glob-lab
> touch a.txt b.txt c.log readme.md script.sh
> chmod +x script.sh
> mkdir subdir
> touch subdir/deep.txt
> ```
> Rollback: `rm -rf /tmp/glob-lab`

```zsh
setopt EXTENDED_GLOB

# 1. List only regular files:
print -l *(.)

# 2. List only directories:
print -l *(/)

# 3. List only executable files:
print -l *(x.)

# 4. Most recently modified file:
print -l *(om[1])

# 5. All files NOT ending in .txt:
print -l ^*.txt

# 6. Recursive: all .txt files including subdir:
print -l **/*.txt

# 7. All files modified in the last 60 seconds:
print -l **/*(mh-1)(N.)

# 8. Files sorted by size, largest first:
print -l *(OL.)

# 9. Combine: executable regular files, newest first:
print -l *(x.om)
```

---

### Lab 3: Write a custom ZLE widget

```zsh
# Paste into terminal to test before adding to .zshrc:

# Widget: wrap current command line in 'time ...'
wrap-time() {
  LBUFFER="time ${LBUFFER}"
}
zle -N wrap-time
bindkey '^Xt' wrap-time

# Test: type 'sleep 3', then press Ctrl-X t — it becomes 'time sleep 3'
```

---

## Pitfalls & gotchas

**1. `compinit` called before `fpath` is set up**
Oh My Zsh calls `compinit` when you source `oh-my-zsh.sh`. Any `fpath+=()` after that line is invisible to the completion system. Always extend `fpath` before sourcing your framework.

**2. `SHARE_HISTORY` + `INC_APPEND_HISTORY` together**
`SHARE_HISTORY` implies `INC_APPEND_HISTORY`. Setting both causes a subtle duplication bug on some zsh versions. Use only `SHARE_HISTORY`.

**3. Extended globbing in scripts**
`setopt EXTENDED_GLOB` in `.zshrc` does not affect scripts unless you add it at the top of each script or use `emulate zsh -c 'setopt EXTENDED_GLOB; ...'`. Scripts run in a fresh non-interactive shell.

**4. `NULL_GLOB` vs `NOMATCH`**
These are mutually exclusive. `NOMATCH` (default) throws an error on no match. `NULL_GLOB` silently returns nothing. If you add `(N)` as a glob qualifier on a pattern, it's per-pattern nullglob without changing the global option.

**5. The `PATH` in `.zshrc` trap**
GUI apps launched from Finder or Spotlight do not source `.zshrc`. They source `.zprofile` (login shell) or nothing at all (non-login, non-interactive). PATH additions for GUI use go in `.zprofile`. See [[02-terminal-emulators]] for how Terminal.app opens shells.

**6. Syntax highlighting performance on long lines**
`zsh-syntax-highlighting` re-analyzes the buffer on every keystroke. On very long heredocs or pasted content (>10k chars), it can lag. Mitigation: `ZSH_HIGHLIGHT_MAXLENGTH=512`.

**7. `^` conflicts in URLs**
With `EXTENDED_GLOB`, `^` in a literal URL in the command line will be interpreted as negation. Quote URLs: `curl 'https://example.com/path?a=1^b=2'`.

**8. `.zcompdump` stale after Homebrew upgrade**
After major Homebrew upgrades (especially Python or Ruby bumps), the dump may reference deleted function paths. If completion mysteriously breaks: `rm -f ~/.zcompdump* ~/.zcompcache && exec zsh`.

**9. vi mode cursor shape in Terminal.app**
vi mode (`bindkey -v`) does not change the cursor shape between insert/normal modes in Terminal.app. iTerm2 and Ghostty respect the `\e[5 q` / `\e[1 q` escape sequences. See [[02-terminal-emulators]].

---

## Key takeaways

- zsh's five startup files have strict ordering; `.zshenv` fires for every process, `.zprofile` for login shells, `.zshrc` for interactive shells. Put `brew shellenv` in `.zprofile`, not `.zshrc`.
- The completion system (`compinit`) scans `fpath` once at startup and caches to `~/.zcompdump`. Extend `fpath` before calling `compinit` (or before sourcing OMZ/zinit). Rebuild cache with `rm -f ~/.zcompdump* && exec zsh` after any change.
- Extended glob qualifiers (`*(.)`, `*(om[1])`, `**/*(u0WX.)`) replace most `find` invocations with in-process, readable expressions. Always `setopt EXTENDED_GLOB`.
- History is most powerful with `EXTENDED_HISTORY` (timestamps) + `SHARE_HISTORY` (live cross-session) + `HIST_IGNORE_ALL_DUPS` + `HIST_IGNORE_SPACE`. `fc` is the history editor; `!!`/`!$`/`^foo^bar` are expansion shortcuts.
- ZLE widgets are the building blocks of all interactive editing. `bindkey` maps sequences to widgets; you can write custom ones that manipulate `LBUFFER`/`RBUFFER`.
- Oh My Zsh is a fine starting point; zinit with turbo mode is the performance-first alternative. At minimum, install `zsh-autosuggestions` and `zsh-syntax-highlighting` — they change everyday shell use more than anything else.

---

## Terms introduced

| Term | Definition |
|---|---|
| `HISTFILE` | Path where zsh persists the command history between sessions |
| `SAVEHIST` | Number of history entries written to `HISTFILE` on exit |
| `SHARE_HISTORY` | Option that makes all live zsh sessions share one history file in real time |
| `fpath` | Array of directories searched for autoloaded functions, including completion functions |
| `compinit` | Function that initializes the completion system by scanning `fpath` and writing `~/.zcompdump` |
| `zstyle` | Configuration mechanism for zsh's completion subsystem and other modules; uses pattern-matching keys |
| `~/.zcompdump` | Cached index of completion functions, rebuilt by `compinit`; delete to force a fresh scan |
| ZLE | Zsh Line Editor — the input system that handles all interactive command-line editing |
| Widget | A ZLE function bound to a key sequence; can read/write `LBUFFER`/`RBUFFER` |
| `bindkey` | Builtin that maps key sequences to ZLE widgets |
| Extended glob | glob patterns enabled by `EXTENDED_GLOB`: `^` (negation), `~` (exclusion), `#`/`##` (repetition) |
| Glob qualifier | Parenthesized filter appended to a glob (`*(.)`, `*(om[1])`) that filters by type, permissions, age, size, etc. |
| `vcs_info` | Built-in zsh module that queries the current VCS state for use in prompts |
| Turbo mode | zinit feature that defers plugin loading until after the prompt renders, reducing perceived startup time |
| `precmd_functions` | Array of function names zsh calls before rendering each prompt |
| `PROMPT_SUBST` | Option that enables command substitution and parameter expansion inside `PROMPT` |
| `LBUFFER`/`RBUFFER` | ZLE variables holding the text to the left/right of the cursor; modifiable by widgets |

---

## Further reading

- `man zshall` — the unified zsh manual (all subsections in one page; search with `/` in `less`)
- `man zshexpn` — the glob and expansion chapter specifically
- `man zshzle` — ZLE widget reference
- [zsh sourceforge documentation — Completion System](https://zsh.sourceforge.io/Doc/Release/Completion-System.html)
- [Scripting OS X: Moving to zsh series](https://scriptingosx.com/2019/07/moving-to-zsh-part-5-completions/) — Armin Briegel's definitive macOS-focused walkthrough
- [The Value Able: zsh expansion guide with examples](https://thevaluable.dev/zsh-expansion-guide-example/)
- [Comprehensive zsh completions troubleshooting on macOS (2026)](https://www.kadosh.me/blog/2026-02-04-comprehensive-zsh-completions-troubleshooting)
- [github.com/zsh-users/zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)
- [github.com/zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
- [github.com/zdharma-continuum/zinit](https://github.com/zdharma-continuum/zinit)
- [Starship prompt](https://starship.rs)
- [[02-terminal-emulators]] — how Terminal.app/iTerm2/Ghostty open shells (login vs interactive)
- [[03-environment-variables]] — deep dive on PATH, environment inheritance, and launchd plist injection
- [[05-permissions-and-acls]] — `*(WX.)` glob qualifiers in a security context
