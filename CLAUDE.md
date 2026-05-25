# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Research Before Guessing

- For third-party APIs/schemas (Slack manifests, CloudKit, Tauri ACL, electron-builder, GitHub Actions workflows), research official docs FIRST before attempting code. Do not paste-and-retry.
- When debugging environment issues (Finder-launched apps, signing, permissions), check PATH/entitlements/capabilities before blaming the tool.

## Cross-Mac dev setup

**This repo must live at `~/dev/PhantomLives/`. It must NOT live anywhere under `~/Documents/` or `~/Desktop/`.** The maintainer works across two Macs with different usernames; `~/dev/` is consistent on both and stays out of iCloud's reach.

### Why `~/Documents/` is broken for dev work

macOS's "Desktop & Documents Folders" iCloud sync (System Settings → Apple ID → iCloud Drive → Options) makes `~/Documents/` an iCloud-managed location. The iCloud File Provider (`bird` + `fileproviderd`) intercepts every filesystem syscall on iCloud-managed paths. For a polyglot monorepo like this one the consequences are catastrophic:

- **Build artifacts get duplicated and corrupted across machines.** SwiftPM's `.build/`, Cargo's `target/`, Electron's `dist/`, npm's `node_modules/`, Xcode's `DerivedData/` all sync to iCloud whether you want them to or not — `.gitignore` is irrelevant because iCloud doesn't read it. When Mac A's artifacts collide with Mac B's, iCloud renames the conflict with a ` 2` suffix: `Sparkle 2/`, `GRDB 2.swift/`, `RootView 2.swift`, `dist 2/`, `PurpleIRC 2.app/`, `WHATS_NEW_1.13 2.md`. The build manifest still references the unsuffixed name, so SwiftPM fails with `the package manifest at … cannot be accessed`, npm fails with `MODULE_NOT_FOUND`, etc.
- **`mv` is no longer atomic.** Trying to move a tree out of `~/Documents/` (even to another local path) is intercepted by `fileproviderd` and routed through a per-file async copy that pegs CPU at 100 % and crawls. `ditto` and `cp -a` are throttled the same way. A 12 GB move that should be a metadata rename takes 10+ hours and may hang.
- **Per-file syscalls are slow.** Every `stat`, `open`, `write` on a path under `~/Documents/` may have to consult `fileproviderd` first. Builds with thousands of files take measurably longer than at `~/dev/`.

### Migrating an existing checkout out of `~/Documents/`

If you find yourself with a repo at `~/Documents/GitHub/PhantomLives/`, do **NOT** try to `mv`, `cp`, `ditto`, or `rsync` it to `~/dev/`. iCloud will block or wreck the operation. The reliable path:

1. `cd ~/Documents/GitHub/PhantomLives && git status` — note uncommitted modifications and untracked source files you care about.
2. `git diff > /tmp/dirty.patch` — capture all working-tree modifications in one file.
3. `git clone https://github.com/<owner>/PhantomLives.git ~/dev/PhantomLives` — fresh clone from origin bypasses iCloud entirely. Takes seconds.
4. `cd ~/dev/PhantomLives && git apply /tmp/dirty.patch` — restore modifications.
5. `rsync -a` the untracked source files you want to keep. Skip anything with a ` 2` in the name — those are iCloud corruption, not real source.
6. Copy `.claude/settings.local.json` and rewrite any hardcoded `/Users/<name>/Documents/GitHub/PhantomLives/…` paths to `~/dev/PhantomLives/…`.
7. Verify with a representative build (`PurpleDedup/build-app.sh`, `Molly/build-app.sh`, etc.) before deleting OLD.
8. `rm -rf ~/Documents/GitHub/PhantomLives`. iCloud will be slow but eventually clears, and the deletion will sync to other Macs — make sure they're ready or have already been migrated.

Clean clone is ~141 MB. OLD was 12 GB because of accumulated build caches. None of that needs to move.

### Per-Mac setup checklist (do once per machine)

The repo content is shared via git, but these pieces live in macOS Keychain / system settings and have to be set up on each machine independently — do not try to sync them via iCloud or Dropbox:

1. **Full Xcode selected:** `sudo xcode-select -s /Applications/Xcode.app`. Required for any subproject using SwiftUI `#Preview {}` macros (the `PreviewsMacros` plugin only ships with full Xcode, not Command Line Tools).
2. **Apple Developer ID signing identity** in the login Keychain. `security find-identity -v -p codesigning` should list `Developer ID Application: <Name> (TEAMID)`. Subprojects' `build-app.sh` auto-detects this; without it, the script falls back to ad-hoc signing (works locally, breaks notarization).
3. **Sparkle EdDSA private key** in the login Keychain for Sparkle-using apps (currently PurpleDedup). The public half goes into `~/.zshrc` as `SPARKLE_PUBLIC_KEY`. See `## Swift app build prerequisites` section 2 below for details.
4. **Notarytool keychain profile** for release builds: `xcrun notarytool store-credentials "<App>-Notary" --apple-id <id> --team-id <id>`. Per-subproject; only needed when cutting a release from this Mac.
5. **Homebrew prereqs** vary per subproject — see each subproject's README. Common: `rust`, `pnpm`, `librsvg`, `imagemagick`, `slackdump`.
6. **Git hooks** are NOT carried by `git clone` — re-run any subproject's hook installer after cloning. Currently: `PurplePDF/scripts/install-git-hooks.sh` (installs the pre-commit hook that auto-bumps PurplePDF's patch version + prepends a CHANGELOG entry on commits touching `PurplePDF/**`; no-ops for other subprojects). Without it, PurplePDF version bumps must be done by hand.

## Repository shape

PhantomLives is a polyglot monorepo of **independent personal/utility projects**, not a single application. Each top-level directory is its own self-contained project with its own README, CHANGELOG, install script, tests, and version number. There is no top-level build, lint, or test command — work always happens inside one subproject at a time.

Stacks in use across subprojects: Bash, Python (with self-bootstrapping `.venv`s), Swift (SwiftPM + SwiftUI macOS apps).

### Nested git repositories

Two subdirectories are **separate git repos**, not part of PhantomLives. Run `git` inside their directory; commits made from the repo root will not include them, and pushing the outer repo will not push them. They surface as untracked entries in the outer repo's `git status` — leave them alone (don't `git add` them):

- `video-analyzer/` — fork of `byjlw/video-analyzer` (different `origin`)
- `ClipperInfo/` — `bronty13/ClipperInfo` (a standalone info/landing page; `index.html`)

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

## SQL migrations are immutable

Once a migration file has been added to a release (committed to `main` AND/OR applied to any developer's local database), **never edit it**. `tauri-plugin-sql` and similar runtime migrators hash the migration file at every launch and refuse to start when the hash doesn't match the stored value — that's the "migration N was previously applied but has been modified" crash.

To change schema or data already covered by a shipped migration:

- **Add a new migration** (e.g. `017_xxx.sql`) that applies the change via `ALTER TABLE`, `UPDATE`, or a table-rebuild dance.
- A new install runs both the original migration and the follow-up in sequence, landing at the same end state as an existing install that only runs the follow-up.

This applies even to comment-only edits — the file's bytes are what get hashed.

**Guardrail** (SideMolly reference): `cargo test migration_immutability` re-hashes every shipped migration at compile time and asserts against a frozen `EXPECTED_MIGRATION_HASHES` constant. Adding a new migration produces a clear "append `(N, "<hash>"),` to the constant" message; editing an existing one fails with "migration N has been modified post-ship — revert and add a new migration instead." See `SideMolly/src-tauri/src/lib.rs::migration_immutability` for the pattern; lift verbatim into any other PhantomLives subproject that uses migration files.

Incident reference: SideMolly v0.13.1 (2026-05-24) — edited migration 013 in place to change a `DEFAULT` value, broke launch for every install that had run v0.13.0. Fixed by reverting 013 to its v0.13.0 bytes; migration 014 already covered the data update.

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
| `PurplePDF/` (TypeScript, Electron 31 + React 18 + Vite, cross-platform macOS/Windows PDF reader & editor) | `./build-app.sh` → `Purple PDF.app` in `/Applications/` (host-arch, adhoc-signed, build + install + relaunch in one shot; `--no-install` / `--no-open` / `BUILD_ONLY=1` opt-outs). `npm install` runs automatically on first invocation. Universal2 release DMG via `scripts/build-app.sh` or `npm run dist:mac` (needs Apple Developer ID + notarization env). | `npm test` — vitest, 22 tests across `projectOrder`, `autosave`, `images-to-pdf`, `bump-and-log`, and a smoke test. `npm run typecheck` for `tsc --noEmit` against `tsconfig.node.json` + `tsconfig.web.json`. |
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

## Git Workflow

- **Before starting work on a subproject, run a quick `git pull --rebase` from the repo root.** The maintainer works across two Macs and pushes directly to `main`, so the remote routinely advances between sessions. Rebasing up front keeps history linear and avoids the stash → rebase → resolve-conflict dance that a stale local `main` forces at push time. If the working tree is dirty, `git stash` first, rebase, then `git stash pop`.
- Always verify the current working directory (cwd) matches the intended project before running git init, commit, or push.
- After committing, always push to remote unless explicitly told otherwise — downstream tools (e.g., /ultraplan) require pushed commits.
- Never sweep unrelated changes into commits; run `git status` and `git diff --staged` before committing.
- Use feature branches and PRs when direct push to main is blocked.

## Build & Verify

- **End-of-task default: build + install + launch — every time, no asking.**
  For any subproject that ships a `build-app.sh` (i.e. has a `.app` bundle
  — Molly, SideMolly, PurpleIRC, MusicJournal, Timeliner, SlackSucker,
  PurplePDF, PurpleLife, MasterClipper, PurpleReel, PurpleDedup,
  PurpleTracker, and any future siblings), finish every code-touching
  task by running `./build-app.sh` from the subproject root. That script
  builds the `.app`, replaces `/Applications/<App>.app` via
  `install.sh`, and relaunches the app — one command, three actions,
  every time. Treat this as the default state of "done": **not run = not
  done**. Opt-out cases (must be stated in the response):
  - Doc-only change with no runtime impact (README typo fix, comment
    cleanup) — note explicitly that the build was skipped and why.
  - Tests are failing — fix them first, then build.
  - User explicitly said don't build / don't install in this turn.
- After UI/icon changes on macOS, always force-clear icon caches (`touch app bundle`, `killall Finder Dock`) and rebuild — visible icon updates often need a second cache-bust pass.
- After any build, launch the app and confirm the change is visible before declaring done.
- Run the full test suite before committing; report pass/fail count (e.g., '455/455 passing').

### Icon / UI change verification sequence

After any icon or UI change:
1. Rebuild.
2. `touch /Applications/<App>.app`
3. `killall Finder Dock`
4. Relaunch the app.
5. Report what you **visually see**, not just that the build succeeded.

## Swift app build prerequisites (read before invoking `build-app.sh`)

These two environment requirements bite hard if missed — diagnostics are misleading. Check both before running any subproject's `build-app.sh` and before assuming a tool bug.

### 1. Full Xcode toolchain required for `#Preview` macros

SwiftPM packages that contain `#Preview { … }` blocks compile via the `PreviewsMacros` plugin, which **only ships with full Xcode** — not with Command Line Tools. If `xcode-select -p` returns `/Library/Developer/CommandLineTools`, the build fails partway through compilation with:

```
error: external macro implementation type 'PreviewsMacros.SwiftUIView'
       could not be found for macro 'Preview(_:body:)';
       plugin for module 'PreviewsMacros' not found
```

This is misleading — it looks like a missing dependency. It's a toolchain mismatch.

**Fix without sudo (one-off):** prefix the invocation:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build-app.sh
```

**Fix system-wide (recommended for dev machines):**
```sh
sudo xcode-select -s /Applications/Xcode.app
```

Subprojects currently known to contain `#Preview` blocks: **none** — PurpleDedup carried the last one until it was removed (commit `3b26576`, 2026-05-24), so every SwiftUI subproject now builds under Command Line Tools. Any new SwiftUI subproject is likely to reintroduce them, at which point this requirement applies again; grep for `#Preview` if a build dies with `PreviewsMacros … not found`.

### 2. Sparkle apps need `SPARKLE_PUBLIC_KEY` in the environment

Subprojects that integrate Sparkle (PurpleDedup, and any future app that wants in-app auto-update) read `SPARKLE_PUBLIC_KEY` from the environment at build time and bake it into the bundle's `Info.plist` as `SUPublicEDKey`. If the variable is unset, `build-app.sh` falls back to the literal placeholder `PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY`. Sparkle refuses to initialize with that value and the running app emits:

```
(Sparkle) The provided EdDSA key could not be decoded.
(Sparkle) Fatal updater error (1): The EdDSA public key is not valid for <App>.
```

The user sees "updater failed to start" or the Check for Updates… menu does nothing.

**Recovery options, in priority order:**

1. **Use the existing production keypair.** On the machine where the keypair was originally generated, run `~/.../.build/artifacts/sparkle/Sparkle/bin/generate_keys -p` to print the public half (the private key lives in that Mac's login Keychain). Copy the base64 string to the dev machine and add `export SPARKLE_PUBLIC_KEY="…"` to `~/.zshrc`, then `source ~/.zshrc` and rebuild.
2. **Generate a fresh dev keypair on the current Mac** if the prod key is unreachable. Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys` once — it mints a keypair, stores the private key in Keychain, and prints the public key. Persist via `~/.zshrc` as above. Trade-off: locally-built bundles will not verify updates signed by the prod private key (fine for dev iteration; not fine for release).
3. **Strip `SUPublicEDKey` entirely** (last-resort) by setting it to empty in the bundle. Sparkle then never initializes; the Updates menu items go dead but everything else works. Use only for one-off testing.

Subprojects currently known to embed Sparkle: **PurpleDedup**.

### 3. ` 2`-suffixed dupes in `.build/` are iCloud corruption, not SwiftPM bugs

If `.build/checkouts/` contains sibling ` 2`-suffixed copies (`Sparkle 2/`, `GRDB 2.swift/`, etc.) and the build fails with `the package manifest at … cannot be accessed`, the cause is almost always iCloud Drive syncing `.build/` between machines and renaming conflicts. See `## Cross-Mac dev setup` at the top of this file — the repo must live outside `~/Documents/`. Recovery is `rm -rf .build` and rebuild, but the underlying problem will reappear if the repo is still inside an iCloud-managed path.

Other causes of the same symptom (rarer):

- **Interrupted SwiftPM mid-fetch.** `pkill swift-build` or Ctrl-C during dependency resolution can also leave `.build/checkouts/` half-baked. Same fix.
- **Renamed user account.** `.build/` caches absolute paths referencing `/Users/<old>/...`; rename invalidates them. Same fix.

## File Hygiene

- Watch for and remove duplicate/stray files (e.g., 'RootView 2.swift', duplicate headings in markdown) — they break builds silently.
- Never clobber existing documentation sections; read before overwriting.
