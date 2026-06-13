---
title: Developer package managers (SPM, npm, pyenv, mise, …)
part: P07 Development
est_time: 60 min read + 45 min labs
prerequisites: [05-homebrew, 02-shell-and-terminal, 03-filesystem-hierarchy]
tags: [macos, development, package-managers, swift, python, node, ruby, rust, go, java, mise, homebrew]
---

# Developer package managers (SPM, npm, pyenv, mise, …)

> **In one sentence:** Every language ecosystem ships its own version manager, package index, and virtual-env story — learn the macOS-specific ground rules and one unifying meta-tool so you never fight the OS again.

---

## Why this matters

macOS ships with a frozen snapshot of several language runtimes — Python 3, Ruby, and Perl — because the OS itself depends on them. The moment you `pip install` into Apple's Python or `gem install` into Apple's Ruby you are modifying a system component Apple considers sacred. One bad install, one major-version upgrade, one accidental `sudo pip install -U pip` and you can destabilize SIP-protected daemons, corrupt Xcode tooling, or force a full OS reinstall to recover.

The professional answer is a layered isolation model:

1. **System runtimes** — never touched, barely acknowledged.
2. **Homebrew-managed runtimes** — still global, but under your control and upgradeable.
3. **Version managers** (pyenv, nvm, rbenv, rustup, mise) — per-machine, shim-based, can coexist N versions.
4. **Per-project isolation** (venv, node_modules, Cargo.lock) — the real unit of reproducibility.

This lesson walks all four layers for every common ecosystem, then shows the modern unifier — **mise** — that lets a single `.mise.toml` in a project root replace most of the others.

> 🪟 **Windows contrast:** Windows has package managers (winget, Chocolatey, Scoop) but no system-runtime entanglement problem — Python and Ruby aren't part of Windows itself. On the other hand, PATH management on Windows is registry-based and global, whereas macOS/zsh lets each shell process inherit a freshly composed PATH, making per-directory activation trivial.

---

## Concepts

### 1. The golden rule: never rely on the system stubs

```
$ which python3
/usr/bin/python3       # ← Apple's stub launcher
$ python3 --version
Python 3.13.x          # whatever shipped with macOS 26 Tahoe
$ which ruby
/usr/bin/ruby          # ← Apple's Ruby, also a stub
```

These stubs actually live in `/Library/Developer/CommandLineTools/usr/bin/` (or inside Xcode). They are:
- **Read-only under SIP** — you cannot `sudo pip install` into their site-packages without disabling System Integrity Protection (which you should not do for this).
- **Frozen to the OS release** — you get the version Apple chose, not the version your project needs.
- **Potentially absent** — a fresh machine with no CLT/Xcode installed shows a "xcrun: error: invalid active developer path" error when you first invoke `python3` or `git`, because the stub triggers an install prompt.

> 🔬 **Forensics note:** When examining a suspect Mac, `/usr/bin/python3` being a stub means any Python malware must have installed a *real* interpreter elsewhere — look in `/opt/homebrew/`, `~/.pyenv/`, `/usr/local/`, `~/Library/Python/`, and `~/.local/`. The presence of a non-stub Python at `/usr/local/bin/python3` (Intel homebrew location) vs `/opt/homebrew/bin/python3` (Apple Silicon) immediately tells you what package manager was used.

### 2. Homebrew as the meta-installer

Homebrew (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel) is the foundation. Install it once:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After install, the activation line it prints (`eval "$(/opt/homebrew/bin/brew shellenv)"`) must be in `~/.zprofile` — that's a login-shell file, so it runs before `~/.zshrc`. This ensures `/opt/homebrew/bin` heads the PATH before the system stubs.

Homebrew manages:
- Compiled binaries ("formulae"): `brew install mise pyenv rbenv`
- macOS app bundles ("casks"): `brew install --cask temurin` (the JDK)
- Version pinning at the formula level: `brew install python@3.12` to keep an older slot

Homebrew is **not** designed for per-project version switching. That's what the version managers are for.

---

### 3. Swift Package Manager

SPM is Apple's first-party dependency + build system, embedded in the `swift` toolchain. Unlike every other ecosystem here, it has no version-manager story — you manage it by managing your Xcode/swift toolchain version.

**Key files:**

| File / Dir | Role |
|---|---|
| `Package.swift` | Manifest: targets, products, dependencies (URL + version range or exact) |
| `Package.resolved` | Lock file — commit this; exact versions resolved for reproducibility |
| `.build/` | Derived data; **never commit**; platform-local `.build/arm64-apple-macosx/debug/` |
| `Sources/<Target>/` | Source tree per target |
| `Tests/<Target>Tests/` | Test target sources |

**Core commands:**

```bash
swift build                          # debug build → .build/debug/
swift build -c release               # release build (optimised, -O)
swift run MyTool                     # build + run a single executable product
swift test                           # run all test targets
swift package resolve                # fetch/update deps to satisfy Package.resolved
swift package update                 # bump all deps to latest matching semver
swift package show-dependencies      # dependency tree, text form
swift package clean                  # rm -rf .build (rarely needed)
```

**Dependency model:** dependencies are declared by URL + version requirement. `swift package resolve` fetches the exact commits into `~/.swiftpm/checkouts/` (global cache shared across projects) and writes `Package.resolved`. The `checkouts` directory is a content-addressable cache — you can `rm -rf ~/.swiftpm/checkouts` and re-resolve to rebuild from scratch.

**Local package overrides:** indispensable during development of a library alongside its consumer:

```swift
// Package.swift consumer
.package(path: "../MyLocalLib")
```

This makes SPM use the on-disk version without a URL/tag. Remove it before tagging a release.

**Binary targets:** SPM can vend pre-built `XCFramework` blobs — useful for closed-source SDKs or build-time tools (formatters, code generators):

```swift
.binaryTarget(
    name: "SomeSDK",
    url: "https://example.com/SomeSDK-1.2.0.zip",
    checksum: "abc123..."   // SHA-256 of the zip
)
// OR from a local path (useful for CI caching)
.binaryTarget(name: "SomeSDK", path: "Frameworks/SomeSDK.xcframework")
```

> 🔬 **Forensics note:** The global SPM checkout cache at `~/.swiftpm/checkouts/` is **not** project-local. An adversarial package in that cache could affect any Swift project on the machine. Inspect `Package.resolved` first on any suspect Mac — it names exact git SHAs, making dependency pinning auditable without running the code.

**Legacy alternatives (know them; avoid starting new projects on them):**

- **CocoaPods** — Ruby gem (`gem install cocoapods`). Modifies the Xcode project, generates a `Pods/` directory, requires `pod install` after every dep change, produces a `.xcworkspace` that must be opened instead of `.xcodeproj`. Legacy for most new projects but still dominant in large ObjC codebases. `Podfile.lock` is the lock file; commit it.
- **Carthage** — decentralised: fetches and builds frameworks to `Carthage/Build/`, no Xcode project modification. Requires manual framework linking. Mostly superseded by SPM but still seen in enterprise codebases.

---

### 4. Node.js

**Do not use the system Node or a bare Homebrew Node for development.** The system node doesn't exist by default; `brew install node` gives you one global version with no switching. Neither is right when different projects pin different Node majors.

**The version manager landscape (2026):**

| Tool | Language | Speed | .nvmrc support | Multi-lang | Notes |
|---|---|---|---|---|---|
| **nvm** | Bash | Slow shell init | Yes | No | The canonical reference; every tutorial assumes it |
| **fnm** | Rust | Fast | Yes | No | Drop-in nvm replacement; `brew install fnm` |
| ~~Volta~~ | Rust | Fast | Partial | No | **End-of-life Nov 2025** — migrate away |
| **mise** | Rust | Fast | Yes (reads `.nvmrc`) | **Yes** | The modern unifier; see §8 |

**Recommended:** mise for multi-language projects, fnm if you only care about Node.

**npm, pnpm, yarn, Corepack:**

```bash
# Corepack ships with Node >= 16.9 and manages yarn/pnpm versions
corepack enable                 # symlinks yarn/pnpm shims into PATH
corepack prepare pnpm@latest --activate   # install + activate a pnpm version

npm install -g <pkg>            # global install → <node-prefix>/lib/node_modules/
npm install <pkg>               # project-local → node_modules/
```

**PATH trap:** `npm install -g` writes into the active Node version's prefix. If you switch Node version with nvm/fnm/mise, the global packages from the old version **are no longer on PATH**. The fix: use `npx` for one-off tools, or reinstall globals after a version switch. mise and fnm both expose the node prefix through `$(mise where node)` or `$(fnm current)` so you can script re-installation.

> 🪟 **Windows contrast:** nvm-windows is a separate project (not the same codebase); the `.nvmrc` behaviour differs subtly. fnm and mise both work natively on Windows and are better cross-platform choices for teams spanning both OSes.

---

### 5. Python

This is the most treacherous ecosystem on macOS. Three different Pythons can silently coexist:

```
/usr/bin/python3              # Apple stub — do not touch
/opt/homebrew/bin/python3     # Homebrew Python — global, upgradeable
/Users/you/.pyenv/shims/python3   # pyenv shim — project-aware
```

**PEP 668 — "externally managed environment":** Python 3.12+ lets a distribution mark itself as externally managed, meaning `pip install` into its global site-packages is blocked:

```
error: externally-managed-environment

× This environment is externally managed
╰─> To install Python packages system-wide, see /opt/homebrew/share/doc/...
```

You will hit this with Homebrew Python. It is **correct behaviour** — the fix is to use a virtual environment, not `--break-system-packages`.

**Option A — uv (recommended for new projects, 2025+):**

```bash
brew install uv

# uv manages Python versions + venvs + packages in one tool
uv python install 3.13          # downloads a standalone CPython build
uv init myproject               # creates pyproject.toml, .python-version
cd myproject
uv add requests                 # resolves + installs into auto-created .venv
uv run python script.py         # runs inside the project's venv, no activation needed
uv tool install ruff            # global CLI tools into ~/.local/bin/ (like pipx)
```

`uv` is written in Rust, resolves 10-100x faster than pip, and never touches the system or Homebrew Python. Because it downloads its own CPython builds (into `~/.local/share/uv/python/`), PEP 668 doesn't apply.

**Option B — pyenv (mature, explicit version control):**

```bash
brew install pyenv
# Add to ~/.zshrc:
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"

pyenv install 3.13.0            # installs to ~/.pyenv/versions/3.13.0/
pyenv global 3.13.0             # default for new shells
pyenv local 3.11.9              # writes .python-version in cwd → auto-activates
python3 -m venv .venv           # always create a project venv
source .venv/bin/activate
pip install -r requirements.txt
```

**Always use a virtual environment per project.** No exceptions. Common convention: `.venv/` in project root, gitignored.

**pipx — for CLI tools that happen to be Python:**

```bash
brew install pipx
pipx install black ruff mypy    # each tool gets its own isolated venv
# tools land in ~/.local/bin/ (make sure that's on PATH)
```

pipx is the right answer for `awscli`, `httpie`, `tldr`, `yt-dlp`, etc. — Python packages that you want on PATH globally without them contaminating any project's site-packages.

**conda / miniforge — for data science and ML on Apple Silicon:**

For NumPy, PyTorch, TensorFlow, JAX: use [Miniforge](https://github.com/conda-forge/miniforge) (the ARM64 conda-forge distribution), not Anaconda. Anaconda's macOS installer historically targeted Intel; Miniforge builds natively for `arm64`.

```bash
brew install --cask miniforge
conda init zsh
conda create -n mlenv python=3.12
conda activate mlenv
conda install pytorch torchvision -c pytorch
```

> 🔬 **Forensics note:** Python venvs leave a clear artifact trail. `pyvenv.cfg` at `<venv>/pyvenv.cfg` names the base Python interpreter with a full path. On a suspect machine, read that file to trace which interpreter seeded the venv — could be system, Homebrew, pyenv, or a user-installed binary in a non-standard location.

---

### 6. Ruby

System Ruby (`/usr/bin/ruby`) is used by Homebrew internals and macOS scripts. Its site-packages are read-only without root, and even with root you risk breaking `gem`-dependent macOS tools (like `softwareupdate` workflows that invoke Ruby). **Never `sudo gem install` into it.**

```bash
brew install rbenv ruby-build   # ruby-build provides the ruby versions
# Add to ~/.zshrc:
eval "$(rbenv init -)"

rbenv install 3.3.6             # installs to ~/.rbenv/versions/3.3.6/
rbenv global 3.3.6
rbenv local 3.2.0               # project-level .ruby-version file

# In a project:
gem install bundler             # scoped to current rbenv version
bundle install                  # reads Gemfile, installs to vendor/bundle or ~/.rbenv/
```

Bundler (`bundle exec <cmd>`) ensures commands use gems from the `Gemfile.lock`, not whatever happens to be on PATH.

**chruby** is a lighter alternative to rbenv — no shims, just path manipulation. Either works; rbenv is more common.

---

### 7. Rust, Go, Java

**Rust — rustup:**

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# Installs to ~/.rustup/ (toolchains) and ~/.cargo/ (bin + registry)
# Adds ~/.cargo/bin to PATH in ~/.zshenv

rustup toolchain install stable
rustup toolchain install nightly
rustup override set nightly     # project-local toolchain (writes rust-toolchain.toml)
cargo build                     # fetches crates from ~/.cargo/registry/
cargo test
```

Rust does not rely on Homebrew or system libs (static linking by default). The `.cargo/registry/` cache is global and shared — first build downloads source archives; subsequent projects re-use compiled crates from `.cargo/registry/cache/`. `~/.cargo/bin` should appear early in PATH but after your project's `.venv/bin` or `node_modules/.bin`.

**Go:**

```bash
brew install go
# or download the .pkg from go.dev/dl/ — both install to /usr/local/go
```

Go workspaces are module-based (`go.mod` + `go.sum`). The module cache lives at `$GOPATH/pkg/mod` (default `~/go/pkg/mod`). Modules are content-addressed and read-only after download — you can safely `rm -rf ~/go/pkg/mod` and rebuild.

```bash
go env GOPATH           # shows ~/go
go mod init example.com/myapp
go get github.com/some/dep@v1.2.3
go build ./...
go test ./...
```

Multiple Go versions: either `go install golang.org/dl/go1.22@latest` (installs `go1.22` binary) or use mise.

**Java — JDK management:**

Apple removed the bundled JRE in macOS 10.14. The cleanest modern path:

```bash
brew install --cask temurin      # Eclipse Temurin (OpenJDK); also temurin@17, temurin@21
# Installs to /Library/Java/JavaVirtualMachines/temurin-21.jdk/
```

macOS ships a helper that lets tools discover the installed JDK:

```bash
/usr/libexec/java_home -V               # list all installed JDKs
/usr/libexec/java_home -v 17            # print path for JDK 17
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
```

**jenv** (analogous to rbenv) manages `JAVA_HOME` on a per-project basis:

```bash
brew install jenv
eval "$(jenv init -)"
jenv add $(/usr/libexec/java_home)      # register the installed JDK
jenv global 21
jenv local 17                           # writes .java-version
```

---

### 8. mise — the universal version manager

mise ("mise-en-place", pronounced *meez*) is a Rust-based tool that replaces nvm, pyenv, rbenv, asdf, and direnv in one binary. Install once, configure per project:

```bash
brew install mise
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc
```

Activation inserts mise's shim directory at the front of PATH and sets up directory-change hooks that apply tool versions when you `cd` into a project.

**Configuration: `mise.toml` or `.tool-versions`:**

```toml
# .mise.toml (project root — commit this)
[tools]
python = "3.13.0"
node = "22.3.0"
go = "1.22.4"
rust = "stable"

[env]
DATABASE_URL = "postgres://localhost/myapp_dev"
```

`.tool-versions` (asdf-compatible format) is also read:

```
python 3.13.0
node 22.3.0
```

**Workflow:**

```bash
mise install            # installs all versions listed in mise.toml
mise use python@3.12    # adds python = "3.12" to .mise.toml + installs
mise use -g node@22     # sets global default
mise ls                 # list installed tools and versions
mise exec -- python3 script.py   # run with mise env without activating shell
mise which python3      # show exact binary path
mise current            # show active versions in cwd
```

> ⚠️ **mise vs direnv:** mise has built-in `[env]` block support that handles most direnv use-cases. The projects can coexist for simple env-var-only direnv configs, but anything involving PATH — which is most of what people use direnv for — creates ordering conflicts. Prefer `mise.toml [env]` blocks; only reach for direnv for features mise doesn't cover (like `.envrc` shell code execution or per-directory `KUBECONFIG` manipulation).

**PATH ordering diagram:**

```
Shell startup order (zsh)
──────────────────────────
~/.zprofile   → eval "$(brew shellenv)"      → /opt/homebrew/bin first
~/.zshrc      → eval "$(mise activate zsh)"  → mise shims prepend THAT

Final PATH (simplified):
  ~/.local/share/mise/shims/     ← mise-managed tools (python, node, go…)
  /opt/homebrew/bin/             ← brew formulae (brew itself, git, curl…)
  /usr/local/bin/                ← Intel compat, manual installs
  /usr/bin/                      ← Apple stubs (python3, ruby — shadow-blocked by above)
  /bin/                          ← POSIX essentials (sh, ls, cp…)
```

Because mise shims come first, `python3` resolves to mise's shim, which in turn delegates to the version pinned in the nearest `mise.toml` (walking up from cwd). The Apple stub is never reached for managed tools.

---

## Hands-on (CLI & GUI)

### Inspect the current PATH chaos on a fresh machine

```bash
# Where does each tool actually resolve?
for t in python3 ruby node npm go cargo java; do
  echo "$t → $(type -a $t 2>/dev/null | head -1)"
done

# Check if you're accidentally in a system Python
python3 -c "import sys; print(sys.executable, sys.version)"

# See all Python 3 binaries on PATH
type -a python3
```

### Check whether a runtime is "owned" by the system

```bash
ls -la /usr/bin/python3         # if it's a symlink to xcrun or CLT it's a stub
file /usr/bin/python3           # "Mach-O universal binary" = it's a real binary = Apple's
otool -L /usr/bin/python3       # which dylibs it links → system frameworks only
```

### Swift package inspection

```bash
cd /some/swift/project
cat Package.resolved            # audit exact dependency SHAs
swift package show-dependencies # dependency tree
swift package describe          # list targets, products, dependencies
ls -la .build/arm64-apple-macosx/debug/   # compiled artifacts
```

### Trace a Python package's install location

```bash
python3 -c "import requests; print(requests.__file__)"
# /Users/you/.pyenv/versions/3.13.0/lib/python3.13/site-packages/requests/__init__.py
# vs the bad outcome:
# /Library/Python/3.x/site-packages/requests/__init__.py  ← system contamination
```

---

## 🧪 Labs

### Lab 1: Install mise and pin per-project toolchains

> ⚠️ **ADVANCED:** This modifies your `~/.zshrc`. Back it up first: `cp ~/.zshrc ~/.zshrc.bak`. Rollback: `cp ~/.zshrc.bak ~/.zshrc && brew uninstall mise`.

```bash
# 1. Install
brew install mise

# 2. Activate — add to ~/.zshrc and source immediately
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc

# 3. Verify activation
mise --version                  # e.g. 2025.x.x
which python3                   # should show ~/.local/share/mise/shims/python3

# 4. Create a scratch project with tool pins
mkdir ~/scratch/mise-test && cd ~/scratch/mise-test
mise use python@3.13            # installs python 3.13, writes .mise.toml
mise use node@22                # installs node 22, appends to .mise.toml
cat .mise.toml                  # verify entries

# 5. Confirm versions in project dir
mise current
python3 --version               # should be 3.13.x
node --version                  # should be 22.x.x

# 6. cd out — versions should revert to globals (or show nothing if no global)
cd ~
python3 --version               # global or system fallback
```

### Lab 2: Create a project-local Python venv and lock dependencies

```bash
mkdir ~/scratch/py-test && cd ~/scratch/py-test

# Option A: classic venv (requires mise python from Lab 1)
python3 -m venv .venv
source .venv/bin/activate
pip install httpx rich
pip freeze > requirements.txt   # lock deps
python3 -c "import httpx; print(httpx.__version__)"
deactivate

# Option B: uv (faster, no activation required)
brew install uv
uv init                         # creates pyproject.toml
uv add httpx rich               # auto-creates .venv, installs, writes uv.lock
uv run python -c "import httpx; print(httpx.__version__)"

# Audit where packages landed
ls .venv/lib/python3.13/site-packages/ | head -20
# They must NOT appear in any system-level path
python3 -c "import sys; print('\n'.join(sys.path))"
```

### Lab 3: Pin a Node version per project and use corepack

```bash
mkdir ~/scratch/node-test && cd ~/scratch/node-test

# Write an .nvmrc (mise also reads this)
echo "22" > .nvmrc
mise install                    # mise picks up .nvmrc
node --version                  # 22.x.x

# Initialise a project and enable pnpm via corepack
npm init -y
corepack enable
corepack prepare pnpm@latest --activate
pnpm --version                  # confirms corepack-managed pnpm

# Install a dep and inspect the lockfile
pnpm add zod
ls -la                          # node_modules/ + pnpm-lock.yaml
```

### Lab 4: Resolve a SwiftPM dependency and audit the lock file

> ⚠️ Requires Xcode or Command Line Tools installed (`xcode-select --install`).

```bash
mkdir ~/scratch/spm-test && cd ~/scratch/spm-test
swift package init --type executable   # creates Package.swift + Sources/

# Edit Package.swift to add a real dependency
cat > Package.swift << 'EOF'
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "spm-test",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "spm-test",
            dependencies: [
                .product(name: "ArgumentParser", from: "swift-argument-parser"),
            ]
        ),
    ]
)
EOF

# Resolve (downloads to ~/.swiftpm/checkouts/)
swift package resolve
cat Package.resolved            # shows pinned SHA + version

# Show dependency tree
swift package show-dependencies

# Build + run
swift run spm-test --help

# Inspect the build dir — note platform triple in path
ls .build/arm64-apple-macosx/debug/

# Clean up derived data but keep the lock
swift package clean             # rm -rf .build only
ls                              # Package.resolved still present
```

---

## Pitfalls & gotchas

### The "which python3 lies to you" trap
`which python3` shows the shim path (e.g. `~/.local/share/mise/shims/python3`), not the actual interpreter. Use `python3 --version` and `python3 -c "import sys; print(sys.executable)"` to see the real binary. A shim that points at an uninstalled version silently fails; `mise install` fixes it.

### Homebrew Python major-version upgrades
`brew upgrade python` can jump from 3.12 to 3.13. Any globally installed packages (`pip install --user`, which Homebrew now blocks via PEP 668 anyway) become orphaned. Virtual environments that hardcode the interpreter path with `/opt/homebrew/bin/python3.12` break immediately. Always use version-pinned venvs (`python3.12 -m venv .venv`) or mise/pyenv/uv to isolate from Homebrew upgrades.

### Two Homebrews on the same machine (the Intel-migration edge case)
On an Apple Silicon Mac that was migrated from an Intel Mac, you may have BOTH `/usr/local/` (Intel Homebrew, via Rosetta 2) and `/opt/homebrew/` (native ARM Homebrew). Running `brew install mise` in Rosetta terminal installs the x86_64 version; running it in native zsh installs ARM64. Confirm:
```bash
file $(which brew)              # should say "arm64" on native terminal
brew config | grep -E "Arch|CPU"
```

### SPM `.build` directory ownership
`.build/` is created by whichever user ran `swift build`. If you alternate between root and a normal user (e.g. during CI), you'll get permission errors. Solution: always build as the same user; in CI, run as the CI agent user consistently. Unlike CocoaPods, SPM has no lockdown mechanism — the build dir is just a directory.

### npm global packages disappear after Node version switch
After `mise use node@22` in a project that was pinned to `node@20`, `npm install -g` packages from the v20 prefix vanish from PATH. npm globals are stored at `$(npm root -g)` which is version-scoped. Either: (a) reinstall globals explicitly, (b) use `npx` for one-off tools, or (c) use mise's `[tools]` block to pin globals at the mise level (`mise plugins install node && mise use -g node@22 && npm install -g ...`).

### `eval "$(mise activate zsh)"` must be last in `.zshrc`
mise activation rewrites PATH. If `brew shellenv`, `rbenv init`, or `nvm.sh` source lines appear *after* the mise activation, they prepend their own bin dirs and shadow mise's shims. Keep the mise activation line last in `.zshrc` (or at minimum after all other PATH-modifying evals). Check with `echo $PATH | tr ':' '\n' | head -5`.

### Rust: `cargo install` vs `brew install`
`cargo install` compiles from source into `~/.cargo/bin/`. This means build toolchain matters — a Rust tool compiled against an older stdlib may not run after a `rustup update`. Prefer `brew install` for stable CLI tools (ripgrep, bat, fd, etc.) since Homebrew packages pre-built binaries and handles upgrades cleanly. Use `cargo install` only when the latest unreleased version is required.

---

## Key takeaways

1. **Never touch `/usr/bin/python3`, `/usr/bin/ruby`, or their site-packages.** Treat them as read-only OS components.
2. **mise is the 2025+ answer** for multi-language version management on macOS — one tool, one config file per project, replaces nvm + pyenv + rbenv + asdf.
3. **Always use a virtual environment** for Python — either a classic `.venv` or uv's automatic `.venv`; the era of `pip install` into a global interpreter is over (PEP 668 enforces this).
4. **SPM is first-class for Swift/Apple development.** CocoaPods is legacy; Carthage is niche. Commit `Package.resolved` for reproducibility; audit it for forensic SHAs.
5. **Volta is dead (EOL Nov 2025).** Migrate Node version management to fnm or mise.
6. **PATH ordering is security-relevant.** Shims that come earlier in PATH than system binaries are the mechanism that makes version management work — and the vector an attacker uses to hijack toolchain execution. Audit `echo $PATH | tr ':' '\n'` on any suspect machine.
7. **pipx is the right tool for Python-based CLI utilities.** It gives each tool an isolated venv without polluting any project's environment.

---

## Terms introduced

| Term | Definition |
|---|---|
| **shim** | A thin wrapper binary that intercepts a command, reads version config (`.mise.toml`, `.python-version`, `.nvmrc`), then exec()s the correct real binary |
| **PEP 668** | Python Enhancement Proposal marking a Python install as "externally managed" — blocks `pip install` into its site-packages |
| **mise.toml** | mise's per-project configuration: tool versions + environment variables + task definitions |
| **Package.resolved** | SPM's lock file: exact git SHAs for every resolved dependency |
| **XCFramework** | Apple's multi-arch binary framework format, used by SPM `binaryTarget` |
| **venv / virtualenv** | Python's per-project isolated interpreter + site-packages directory |
| **pipx** | Tool for installing Python CLI applications each into their own isolated venv |
| **uv** | Astral's Rust-written all-in-one Python package + project + version manager |
| **Corepack** | Node.js built-in shim manager for yarn and pnpm version pinning |
| **GOPATH** | Go's workspace root (`~/go` by default); `pkg/mod` is the module cache |
| **rustup** | Rust's official toolchain installer and manager; stores toolchains in `~/.rustup/` |
| **jenv** | Ruby-env-style wrapper for `JAVA_HOME` management across multiple JDK installs |
| **`/usr/libexec/java_home`** | macOS helper binary that discovers and ranks installed JDK versions |
| **Miniforge** | ARM64-native conda distribution from conda-forge; the correct conda for Apple Silicon |
| **direnv** | Shell extension that loads/unloads env variables on directory change (via `.envrc`) |
| **asdf** | The predecessor multi-language version manager to mise; uses `.tool-versions` files |

---

## Further reading

- [mise documentation](https://mise.jdx.dev/) — especially the `mise.toml` reference and backends list
- [Swift Package Manager docs](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) — official `Package.swift` API reference
- [PEP 668 — Marking Python base environments as externally managed](https://peps.python.org/pep-0668/)
- [uv documentation](https://docs.astral.sh/uv/) — covers Python version management, projects, tools, and scripts
- [pyenv README](https://github.com/pyenv/pyenv) — build dependencies and version install mechanics
- [Homebrew formula vs cask distinction](https://docs.brew.sh/Formula-Cookbook) — when to use which
- [[05-homebrew]] — Homebrew deep-dive: taps, formulae, casks, pinning
- [[02-shell-and-terminal]] — PATH, environment variables, shell startup order
- [[03-filesystem-hierarchy]] — where each tool's files actually live on macOS
- [[07-signing-and-notarization]] — code-signing implications for Swift packages and Xcode toolchains
