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

## Auto-backup-on-launch

Every PhantomLives app that owns persistent user data (a SQLite database, a JSON store, a settings bundle the user can't easily recreate) **must** run an automatic backup on app launch. This is the safety net that lets us ship migrations and destructive features without fear.

Default behavior:

- **Location**: `~/Downloads/<AppName> backup/` (sibling to the regular output dir, with a trailing ` backup`).
- **Filename**: `<AppName>-YYYY-MM-DD-HHmmss.zip`. Recognizable prefix so the trim logic and listing UI can scope to "our" archives without nuking unrelated zips a user dropped in the same folder.
- **Contents**: zip of the entire `~/Library/Application Support/<AppName>/` directory (DB + settings + attachments).
- **Retention**: 14 days by default. `0` means keep forever.
- **Debounce**: skip the launch-time run if the previous successful backup is under 5 minutes old. Prevents debugging-session relaunches from filling the backup folder.
- **Failure mode**: log via `NSLog`, never throw. The app must launch even if backup fails (volume unmounted, disk full, etc.). The error surfaces in Settings → Backup.
- **User overrides** persist in `settings.json`: `autoBackupEnabled`, `backupPath`, `backupRetentionDays`, `lastBackupAt`.

Required UI (Settings → Backup):

- Toggle for `autoBackupEnabled` (default **on**).
- Text field + "Choose…" picker for the backup directory; show the resolved path below in monospaced caption.
- Stepper for retention days.
- "Run backup now" button.
- "Recent backups" list with **Test** (verify archive + count rows non-destructively), **Restore** (with mandatory pre-restore safety backup), and **Reveal in Finder** actions.
- Last-backup timestamp readout.

Required tests:

- **debounce** — second call within 5 min is a no-op
- **retention trim** — only files matching the `<AppName>-` prefix in the backup dir are removed when older than the retention window; unrelated files are left alone
- **target-directory auto-create** — `runBackup` succeeds when the destination directory doesn't exist yet
- **list ordering** — `listBackups` returns newest-first

Reference implementation: `Timeliner/Sources/Timeliner/Services/BackupService.swift` (the launch-time auto-run, debounce, retention trim, verify, and restore pieces). `MasterClipper/Sources/MasterClipper/Services/BackupService.swift` is the older sibling without the launch-time auto-run — when MasterClipper is next touched, fold the launch-time hook in to bring it into compliance.

## `install.sh` standard for `.app` subprojects

PhantomLives macOS apps that get built into a `.app` bundle (PurpleIRC, MasterClipper, Timeliner, SlackSucker, PurpleLife, MusicJournal, …) **should ship an `install.sh`** alongside `build-app.sh` whenever the developer workflow benefits from running the app out of `/Applications/`. That's the case when **any** of these apply:

- The app needs Full Disk Access, Accessibility, Automation, or another TCC entitlement — TCC keys grants on the `(team ID, bundle ID, cdhash)` tuple, and running from a stable `/Applications/` path keeps Launch Services + System Settings → Privacy from spawning duplicate stale entries on every rebuild.
- The app registers a URL scheme, AppleScript dictionary, Shortcuts intents, or Spotlight metadata — same reason: those bind to the resolved bundle path that Launch Services indexes.
- The app needs to be launched from outside the project tree (Spotlight, Dock, Cmd+Tab) for natural day-to-day use.

When it does **not** make sense, skip it: pure CLI tools, Python scripts, dev-only utilities, or sandboxed apps where running from anywhere is fine.

### What `install.sh` does

Three steps, in order:

1. **Quit the running copy** — `osascript -e 'tell application "<AppName>" to quit' >/dev/null 2>&1 || true`. Give Launch Services a moment (`sleep 1`) to release the bundle lock.
2. **Replace `/Applications/<AppName>.app`** — `rm -rf` then `ditto --noextattr <project-dir>/<AppName>.app /Applications/<AppName>.app`. `ditto --noextattr` matters: it strips the iCloud File Provider xattrs that re-attach mid-copy and break `codesign --verify`.
3. **Relaunch** — `open /Applications/<AppName>.app`. Skip with a `--no-open` flag for CI / scripted use.

The script lives at the subproject root (`<SubProject>/install.sh`), is `chmod +x`-ed in git, refuses to run when `<SubProject>/<AppName>.app` doesn't exist yet (run `./build-app.sh` first), and tolerates a missing `/Applications/<AppName>.app` (first install).

Reference implementation: `SlackSucker/install.sh`.

### Developer workflow

```sh
./build-app.sh && ./install.sh
```

One line: build the bundle, replace the `/Applications/` copy, relaunch. Two-step variant (`./install.sh --no-open` then manually open from Spotlight) is useful when iterating on launch-time logic without auto-focus stealing.

### Why `/Applications/`, not the project tree?

- **TCC stability**: macOS Privacy & Security entries follow the cdhash of the *exact path* that was authorised. Running from `~/Documents/GitHub/PhantomLives/<Sub>/<App>.app` and from `/Applications/<App>.app` would each accumulate their own Full Disk Access grant; rebuilds in the project tree rotate the cdhash and force re-granting permissions on every iteration.
- **Launch Services hygiene**: launching the same `.app` from two paths makes Spotlight / Cmd+Tab pick a phantom copy after Finder auto-renames duplicates to ` 2.app` / ` 3.app`. Pinning to `/Applications/` and rebuilding through ditto eliminates the duplicates entirely.
- **No iCloud File Provider interference**: the project tree may be inside `~/Documents/GitHub/…` which is iCloud-synced on many maintainers' machines. The File Provider re-attaches `com.apple.fileprovider.fpfs#P` and `com.apple.FinderInfo` xattrs to `.app` bundles at arbitrary times, which trips `codesign --verify`. `/Applications/` is local-only.

### Per-session Claude permission

The `rm -rf /Applications/<AppName>.app` + `ditto * /Applications/<AppName>.app` operations live behind the auto-mode classifier's "modifying shared infrastructure" gate. To let Claude run `install.sh` end-to-end without prompting, add the matching rules to `.claude/settings.local.json`:

```json
"Bash(rm -rf /Applications/<AppName>.app)",
"Bash(ditto --noextattr * /Applications/<AppName>.app)",
"Bash(osascript -e 'tell application \"<AppName>\" to quit')",
"Bash(open /Applications/<AppName>.app)"
```

Substitute `<AppName>` per subproject. These are scoped per project, so the permissions stay narrow.

## Per-subproject commands

| Subproject | Build / Run | Tests |
|---|---|---|
| `PurpleIRC/` (Swift, SwiftUI macOS app) | `./build-app.sh` → `PurpleIRC.app` (or `swift build`; `CONFIG=debug` for debug). UI only activates from the `.app` bundle. | `./run-tests.sh` — wrapper that adds `Testing.framework` rpath for Command Line Tools setups; plain `swift test` works with full Xcode. |
| `MusicJournal/` (Swift, SwiftUI macOS app) | XcodeGen project (`project.yml`); regenerate with `xcodegen generate`, build via `MusicJournal.xcodeproj`. Depends on GRDB. | `xcodebuild test` (no test targets currently configured in `project.yml`). |
| `Timeliner/` (Swift, SwiftUI macOS app) | `./build-app.sh` → `Timeliner.app` (XcodeGen + GRDB; produces a Developer-ID-signed `.app`). Auto-runs the launch-time backup standard above. | `./run-tests.sh` — XCTest, 18 tests across migration / Codable / search / export / backup. |
| `SlackSucker/` (Swift, SwiftUI macOS app wrapping the `slackdump` CLI) | `./build-app.sh` → `SlackSucker.app` (plain SwiftPM; bundles the slackdump binary from `$SLACKDUMP_BIN` or `which slackdump`; Developer-ID-signed). Then `./install.sh` to deploy to `/Applications/`. Auto-runs the launch-time backup standard. | `./run-tests.sh` — Swift Testing, 41 tests across argv building / line buffer / stdout parsing / channel JSON parser / file organizer / chat exporter / settings round-trip / backup debounce + retention + listing. |
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
