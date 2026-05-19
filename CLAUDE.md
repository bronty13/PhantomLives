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

**Required UI (Settings → Backup) — non-negotiable** for any app
with persistent user data. Missing controls = ship blocker.

- Toggle for `autoBackupEnabled` (default **on**).
- Text field + "Choose…" picker for the backup directory; show the
  resolved path below in monospaced caption. "Default" button restores
  the convention path.
- Stepper for retention days (0…365; `0` = keep forever).
- **Run Backup Now** button — calls `BackupService.runBackup()`
  unconditionally (ignores the 5-min launch debounce).
- **Reveal in Finder** button for the backup directory.
- **Recent backups** list with per-row actions:
  - **Test** — verify the archive (extract to tempdir, confirm
    payload + DB presence, count rows non-destructively).
  - **Restore** — replace live Application Support directory with the
    archive. ALWAYS create a `<AppName>-pre-restore-…zip` safety
    backup first.
  - **Reveal in Finder**.
- Last-backup timestamp readout.
- Status line showing the most recent operation result or failure
  reason.

Required tests:

- **debounce** — second call within 5 min is a no-op
- **retention trim** — only files matching the `<AppName>-` prefix in the backup dir are removed when older than the retention window; unrelated files are left alone
- **target-directory auto-create** — `runBackup` succeeds when the destination directory doesn't exist yet
- **list ordering** — `listBackups` returns newest-first

Reference implementation: `Timeliner/Sources/Timeliner/Services/BackupService.swift` (the launch-time auto-run, debounce, retention trim, verify, and restore pieces). `MasterClipper/Sources/MasterClipper/Services/BackupService.swift` is the older sibling without the launch-time auto-run — when MasterClipper is next touched, fold the launch-time hook in to bring it into compliance.

## Sidebar layout: avoid `NavigationSplitView`

**For new macOS apps: do NOT use `NavigationSplitView` for the top-level
sidebar. Use a manual `HStack` with a fixed-width sidebar.** This is the
empirically-verified pattern after this codebase has burned through
three+ fix attempts.

### The bug

`NavigationSplitView` on macOS 14+ (Sonoma / Sequoia / Tahoe) does not
reliably honor `.navigationSplitViewColumnWidth(min:ideal:max:)` at
runtime — even when the persisted state is **within** the declared
range, the sidebar can render narrower than its `min`. Apple
FB10749141 was partially fixed on iPadOS 18 but not on macOS. The
problem compounds because AppKit persists split-view divider positions
in **two** places — `UserDefaults` (`"NSSplitView Subview Frames *"`)
and `~/Library/Saved Application State/<bundleId>.savedState/` — and
restores from either. Wiping `UserDefaults` alone is not enough, and
even with both stores in a valid state the runtime layout still
mis-renders.

### The canonical fix: MusicJournal pattern

A plain `HStack` with explicit sidebar `.frame(width:)`. With manual
layout we own every pixel; AppKit's window-restoration machinery has
no split-view divider to mis-restore.

```swift
struct ContentView: View {
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true
    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: 240)
                    .background(.ultraThinMaterial)
                Divider()
            }
            DetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
                } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }
    }
}
```

Resizability is a nice-to-have and re-opens the persistence-corruption
door — defer until explicitly requested.

### Defense in depth: `WindowStateGuard`

For nested `HSplitView` / `VSplitView` inside the detail tree (e.g.
PurpleReel splits the asset table above the player), still ship
`Services/WindowStateGuard.swift` and wire it from
`AppDelegate.applicationWillFinishLaunching`:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let windowResetVersion = 1
    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(appName: "<AppName>",
                                        resetVersion: Self.windowResetVersion)
    }
}
```

The guard does two things on each launch:

1. **Preflight purge**: strips `"NSSplitView Subview Frames *"` keys
   from `UserDefaults` AND wipes the bundle's `.savedState/` directory
   whenever a stale frame key was found. Idempotent, runs every launch.
2. **Versioned one-shot reset**: when source-declared
   `windowResetVersion` exceeds the user's stored version, wipes the
   entire window-state surface (NSWindow frames, sidebar separation,
   `.savedState`). Bump in source to invalidate every install.

Also expose a `Window → Reset Window State…` menu item calling
`WindowStateGuard.forceReset(...)` for user-visible recovery.

### Reference implementation

- `PurpleReel/Sources/PurpleReel/Views/ContentView.swift` — HStack
  layout (copy verbatim into new apps).
- `PurpleReel/Sources/PurpleReel/Services/WindowStateGuard.swift` —
  guard helper (copy verbatim).
- `PurpleReel/Sources/PurpleReel/App/AppDelegate.swift` — minimal
  delegate wired via `@NSApplicationDelegateAdaptor`.
- `MusicJournal/Sources/MusicJournal/Views/ContentView.swift` —
  original incident report and HStack template.

### Apps still on `NavigationSplitView` (retrofit on next touch)

PurpleLife, PurpleTracker, PurpleIRC, PurpleDedup, Timeliner,
MasterClipper. All have been bitten by this bug in some form. None
are crash-broken today (their `WindowStateGuard`-style hacks cover
the worst cases) but the only durable fix is to drop
`NavigationSplitView` for the manual HStack pattern.

## `install.sh` standard for `.app` subprojects

**Every PhantomLives macOS-app subproject (anything with a `build-app.sh` that produces a `.app` bundle) ships an `install.sh`, and `build-app.sh` auto-chains into it.** Building defaults to *build + install + relaunch* — one command does everything. This rule was made unconditional in 2026-05-19 because the conditional gating below was producing accidentally-divergent dev workflows across subprojects.

The conditional rationale still applies (the *why* below is still load-bearing), it's just now applied universally:

- TCC entitlements (Full Disk Access, Accessibility, Automation) key grants on the `(team ID, bundle ID, cdhash)` tuple — running from `/Applications/<App>.app` keeps Launch Services + System Settings → Privacy from spawning duplicate stale entries on every rebuild.
- URL schemes, AppleScript dictionaries, Shortcuts intents, Spotlight metadata — all bind to the resolved bundle path that Launch Services indexes.
- Daily-use launching from Spotlight / Dock / Cmd+Tab needs a stable bundle path.

Pure CLI tools, Python scripts, and dev-only utilities are still exempt — they don't have `build-app.sh` to begin with.

### What `install.sh` does

Three steps, in order:

1. **Quit the running copy** — `osascript -e 'tell application "<AppName>" to quit' >/dev/null 2>&1 || true`. Give Launch Services a moment (`sleep 1`) to release the bundle lock.
2. **Replace `/Applications/<AppName>.app`** — `rm -rf` then `ditto --noextattr <project-dir>/<AppName>.app /Applications/<AppName>.app`. `ditto --noextattr` matters: it strips the iCloud File Provider xattrs that re-attach mid-copy and break `codesign --verify`.
3. **Relaunch** — `open /Applications/<AppName>.app`. Skip with a `--no-open` flag for CI / scripted use.

The script lives at the subproject root (`<SubProject>/install.sh`), is `chmod +x`-ed in git, refuses to run when the local `<App>.app` doesn't exist yet (run `./build-app.sh` first), and tolerates a missing `/Applications/<AppName>.app` (first install).

Reference implementation: `SlackSucker/install.sh`.

### `build-app.sh` chain

Every `build-app.sh` ends with this canonical block after the build succeeds:

```bash
# Auto-install: replace /Applications/<App>.app and relaunch. Opt out
# with `--no-install` (CI builds, signature inspection) or `--no-open`
# (install without focus-stealing relaunch). Per the install.sh standard.
if [ "${BUILD_ONLY:-0}" != "1" ] && [[ ! " $* " =~ " --no-install " ]]; then
    INSTALL_FLAGS=""
    if [[ " $* " =~ " --no-open " ]]; then INSTALL_FLAGS="--no-open"; fi
    if [ -x "$(dirname "$0")/install.sh" ]; then
        "$(dirname "$0")/install.sh" $INSTALL_FLAGS
    fi
fi
```

The `BUILD_ONLY=1` env-var override is for one-off invocations from scripts that genuinely want only the .app bundle (PR previews, signature checks). The `--no-install` flag is the same idea on the command line.

### Developer workflow

```sh
./build-app.sh                       # build + install + relaunch
./build-app.sh --no-open             # build + install, no focus steal
./build-app.sh --no-install          # build only (legacy behavior)
BUILD_ONLY=1 ./build-app.sh          # same, via env
./install.sh                          # re-install last-built bundle
./install.sh --no-open               # re-install without launching
```

The pre-2026-05-19 two-line idiom (`./build-app.sh && ./install.sh`) still works (install.sh is idempotent — running it twice just does the kill-replace-relaunch cycle twice), but it's redundant now.

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
