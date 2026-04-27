# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

PhantomLives is a polyglot monorepo of **independent personal/utility projects**, not a single application. Each top-level directory is its own self-contained project with its own README, CHANGELOG, install script, tests, and version number. There is no top-level build, lint, or test command — work always happens inside one subproject at a time.

Stacks in use across subprojects: Bash, Python (with self-bootstrapping `.venv`s), Swift (SwiftPM + SwiftUI macOS apps).

### Nested git repositories

One subdirectory is a **separate git repo**, not part of PhantomLives. Run `git` inside its directory; commits made from the repo root will not include it, and pushing the outer repo will not push it:

- `video-analyzer/` — fork of `byjlw/video-analyzer` (different `origin`)

Everything else (including `MusicJournal/`, `fsearch/`, `PurpleIRC/`, `messages-exporter/`, etc.) lives in the outer `bronty13/PhantomLives` repo. (`MusicJournal/` was briefly an independent repo before being imported into PhantomLives at commit `58f3d35`.)

## Release-hygiene rules (from `.github/copilot-instructions.md`)

These apply to **every** code, config, script, test, or doc change. Do not skip them — most subprojects already follow them rigorously:

1. Bump the version number consistently across script, docs, and any version output the tool prints.
2. Add a CHANGELOG entry describing what changed and why.
3. Update affected docs (`README.md`, and `USER_MANUAL.md` where one exists).
4. Update in-code version constants and any comments that describe behavior you changed.
5. Add or update tests for bug fixes, regressions, and new behavior.
6. Update operational files (config defaults, installers, helper scripts, command help text) when relevant.
7. If a hygiene item genuinely doesn't apply, explicitly say why in the commit/PR notes.

## Default output location

Every PhantomLives tool that writes user-visible output (exports, transcripts, reports, generated files, baselines, etc.) **must** default its output path to:

```
~/Downloads/<project-or-app-name>/
```

The folder name matches the subproject directory or the app's display name (e.g. `~/Downloads/messages-exporter-gui/`, `~/Downloads/transcribe/`, `~/Downloads/MacSysInfo/`). Tools that further organize each run into a timestamped subfolder do so *inside* this directory (e.g. `~/Downloads/messages-exporter-gui/<contact>_<YYYYMMDD_HHMMSS>/`).

Rules:

- The default must be created on demand — don't fail if `~/Downloads/<name>/` doesn't exist yet; `mkdir -p` it.
- Users can override (CLI flag, Settings pane, env var) but the override must persist (UserDefaults / config file) so it sticks across runs.
- Document the default in `README.md` and `USER_MANUAL.md`.
- Internal caches, logs, and config still live under `~/Library/Application Support/<name>/` or `~/.config/<name>/` — this rule is only for things the user is meant to find and open.

## Per-subproject commands

| Subproject | Build / Run | Tests |
|---|---|---|
| `PurpleIRC/` (Swift, SwiftUI macOS app) | `./build-app.sh` → `PurpleIRC.app` (or `swift build`; `CONFIG=debug` for debug). UI only activates from the `.app` bundle. | `./run-tests.sh` — wrapper that adds `Testing.framework` rpath for Command Line Tools setups; plain `swift test` works with full Xcode. |
| `MusicJournal/` (Swift, SwiftUI macOS app) | XcodeGen project (`project.yml`); regenerate with `xcodegen generate`, build via `MusicJournal.xcodeproj`. Depends on GRDB. | `xcodebuild test` (no test targets currently configured in `project.yml`). |
| `messages-exporter/` (Python) | `./install.sh` (user) or `./install.sh --system` (sudo). Then `export_messages "<contact>" --start ... --end ...`. Requires Full Disk Access for the terminal. | `python3 test_export_messages.py` |
| `fsearch/` (Bash) | `./install.sh` (user) or `./install.sh --system`. Run as `fsearch ...`. | `./test_fsearch.sh` (also `fsearch-test` smoke script) |
| `brew-autoupdate/` (Bash + launchd) | `bash install.sh` — installs to `~/.config/brew-autoupdate/`, sets up launchd, creates the `brew-logs` viewer. | `bash test_brew_autoupdate.sh` |
| `transcribe/` (Python, Apple MLX) | `python3 transcribe.py -i <file>` — auto-creates `.venv`, installs deps (mlx, mlx-whisper, mlx-lm), and re-execs itself inside it on first run. Apple Silicon only. | No test suite. |
| `tictactoe/` (Python) | `python3 tictactoe.py` | `python3 test_tictactoe.py` |
| `diskspace/` (Python, single-file) | `python3 diskspace.py` | No test suite. |
| `macsysinfo/` (Bash) | `./MacSysInfo.sh` (supports `--json`, `--csv`, baseline save/compare, section filters). | No test suite. |
| `video-analyzer/` (Python, separate repo) | `pip install -e .` then `video-analyzer ...`. See its own `readme.md`. | `python3 test_prompt_loading.py` |
| `claude-servicenow-integration/` | Documentation only — no code. |
| `assessment/` | Empty data/log/session scaffolding; no code. |

When a subproject's Python code uses a self-bootstrapping `.venv` (e.g. `transcribe`, `messages-exporter` after install), do **not** create your own venv on top — the script's shebang or first-run logic handles it.

## PurpleIRC architecture (the largest subproject)

`PurpleIRC/HANDOFF.md` is the canonical architecture snapshot — read it before non-trivial changes. Quick mental model:

- **`ChatModel`** (`@MainActor`) — top-level store; holds the connection list and shared services (`WatchlistService`, `SettingsStore`, `LogStore`, `BotHost`, `BotEngine`, `KeyStore`, `DCCService`, `SessionHistoryStore`).
- **`IRCConnection`** — one per network. Owns an `IRCClient`, buffers, reconnect state, and a per-connection event subject.
- **`IRCClient`** — RFC 1459 parsing + `NWConnection` transport; SASL (PLAIN/EXTERNAL) and IRCv3 CAP negotiation live here. `ProxyFramer` plugs in at the bottom of the protocol stack.
- **Event fan-out** — every line / state change flows through the `Sendable` `IRCConnectionEvent` enum. `ChatModel.events` merges all connections (UUID-tagged) and is what bots, watchlist, and the assistant subscribe to.
- **Persistence** — `EncryptedJSON` + `KeyStore` wrap a passphrase-derived KEK around a per-install DEK; AES-256-GCM seals every persistence file. Settings live at `~/Library/Application Support/PurpleIRC/`.
- **`build-app.sh`** derives `CFBundleShortVersionString` from git (`1.0.<commit-count>`) and `CFBundleVersion` from `<count>.<short-sha>`. Version-bump rule #1 above is satisfied automatically by committing — no manual edit needed for the bundle version.

The app **must** be launched from the `.app` bundle for SwiftUI's `WindowGroup`, `UNUserNotificationCenter` authorization, and the AppleScript dictionary to work; `swift run` alone won't fully activate the UI.
