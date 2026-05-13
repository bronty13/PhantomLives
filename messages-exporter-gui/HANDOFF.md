# messages-exporter-gui — Handoff

Snapshot of where the project stands so a future session (human or AI) can pick up without re-deriving everything from the commit history.
Last updated: 2026-05-12. Sender picker landed: the Contact row is now a combobox that enumerates conversation partners directly from `~/Library/Messages/chat.db` via two new pure-SQLite services (`SendersService`, `AddressBookLookup`) and pipes the picked handle through to the CLI's new `--handle` flag for an exact, fuzzy-match-free query. Also: the precursor range-precision fix from earlier today (HH:MM:SS, seconds field, +60s start buffer) — see `RangeResolver` in `Model/ExportRequest.swift`. For a per-feature timeline read CHANGELOG; this file does not pin a version because the bundle version increments on every commit.

## What it is

A small SwiftUI macOS front end for the sibling `messages-exporter` Python CLI. Wraps the CLI's stdout into a progress bar + copyable log, and adds one-click buttons to reveal the run folder and open the transcript / summary / manifest.

```
swift build                        # debug build
./build-app.sh                     # release build → MessagesExporterGUI.app
./run-tests.sh                     # 50 tests in 8 suites via swift-testing
open MessagesExporterGUI.app
```

Requires macOS 14+, Swift 5.9+. Tests run via Command Line Tools' bundled `Testing.framework`; the wrapper script handles the rpath dance the same way `PurpleIRC/run-tests.sh` does.

## Architecture at a glance

The app does three things and nothing else: format the CLI invocation, spawn it as a child process, and parse its stdout. There is **no chat.db reader, no AddressBook walker, no media handler in Swift** — those all live in the CLI and stay there.

The 1.0.13 *Mission Control* redesign reorganises the view layer into a sidebar + main pane and introduces a small theme/component library, but does not change the app's responsibilities or the CLI contract. The same `ExportRunner` is shared with new view siblings.

- `App.swift` — `@main`. `WindowGroup` (`.hiddenTitleBar` style, min 920×640, ideal 1100×780) + Settings scene. Owns one `ExportRunner` injected via `environmentObject`.
- `RootView.swift` — top-level layout. Wraps everything in `MissionThemeReader` so descendants can `@Environment(\.missionTheme)`. Lays out the `Sidebar` and a vertical main pane: `FDABanner` (when denied) → header (kicker + h1 + chip buttons) → `StatTiles` → `FormCard` → `RunStrip` → `LiveOutputCard` → `VersionFooter`. The Contact field is a plain `TextField` — the CLI does its own AddressBook substring matching, so the GUI deliberately does not touch `Contacts.framework` (see "Why no Contacts.framework" below). The Mode picker selects between `Sanitized` (default) and `Raw (forensic)`; the CLI ignores `--emoji` in raw mode, but the redesign keeps the Emoji setting in Settings rather than greying it on the main form. `RootView.swift` also defines `FormCard`, `VersionFooter`, `FDABanner`, `FullDiskAccessSheet`, the `InstallSheet`, and the `SettingsView` scene (Output / Emoji / Whisper / Diagnostics).
- `Theme/MissionTheme.swift` — `MissionTheme` struct with light/dark token pairs (background gradient, inks, rules, accent, run-strip gradient, status colors), `MissionFont` typography helpers, and a reusable `GlassCard` surface. Resolved by `MissionThemeReader` and exposed via `EnvironmentValues.missionTheme`.
- `Model/ExportRequest.swift` — pure value type. Builds the argv passed to the CLI with the date format the CLI's argparse expects (`yyyy-MM-dd HH:mm:ss`, local TZ, `en_US_POSIX` locale — seconds are always emitted so the GUI never silently truncates a forensic range). Carries `mode: ExportMode` (appends `--raw` when `.raw`), `transcribe: Bool` + `transcribeModel: WhisperModel` (appends `--transcribe --transcribe-model <model>` when `transcribe` is on), `debug: Bool` (appends `--debug` when true), and `handles: [String]` — when populated, appends `--handle h1,h2,...` for the CLI's exact-handle path (skips fuzzy AddressBook matching). The `WhisperModel` enum mirrors the CLI's `WHISPER_MODELS` list — a unit test asserts the rawValues match exactly. The same file hosts `RangeResolver`: pure helpers (`setSeconds`, `resolvedStart`, `resolvedEnd`) that translate the form's HH:MM picker + SS stepper + `expandStartByOneMinute` toggle into the concrete `Date` pair handed to the request. Pulled out as free functions so the test suite can pin the resolution math without instantiating a view.
- `Model/ExportRunner.swift` — `@MainActor ObservableObject`. Spawns `Process`, streams stdout via `Pipe.readabilityHandler`, parses `[N/5]` markers and the `[4/5] Writing to ...` line. Also publishes `runStats: RunStats` — populated mid-stream from `[3/5] N messages in range` and finalised after a successful run by reading `metadata.json` from the run folder + walking it for an output-byte total. Pre-flights `~/.local/bin/export_messages` existence and offers to run sibling `install.sh` if missing. Pre-flights Full Disk Access via `probeReadable(path:)` against `~/Library/Messages/chat.db` and exposes the result as `@Published fdaStatus: FullDiskAccessStatus` so the main view can show a sheet on launch and the sidebar can show the FDA pill. Provides `resetTCCEntries()` (shells out to `/usr/bin/tccutil reset SystemPolicyAllFiles <bundle-id>` to wipe stale cdhash-pinned entries) and `openPrivacySettings()` (deep-links to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`). The runtime detection of `authorization denied` / `operation not permitted` in CLI stdout also flips `fdaStatus` to `.denied` so the banner appears post-failure. Exposes `isCancelling: Bool` and `cancel()` — `cancel()` sends SIGTERM to the child process and sets `isCancelling`; the run loop checks `isCancelling` after termination and records `[export] Cancelled.` rather than treating a status-15 exit as an error.
- `Model/RunStats.swift` — pure value + helpers for the four stat tiles. `messageCount(in:)` parses the stage-3 line; `decodeMetadata(at:)` reads the CLI's `metadata.json`; `computeOutputBytes(folder:)` walks the run folder summing `totalFileAllocatedSize`. Formatters render nil values as em-dashes so a fresh tile and a zero-result tile are visually distinguishable. All pure-function — covered by 11 tests in the `RunStats parsers` suite.
- `Views/Sidebar.swift` — frosted-glass sidebar (220 px, `.thinMaterial`). Single-state today: `New export` is the only active nav item; `Recent runs` and `Saved presets` are slotted as disabled "Soon" items pending a history store and preset store respectively. Bottom slot is `FDAPill` (green/granted, amber/click-to-resolve when denied).
- `Views/StatTiles.swift` — four `GlassCard` tiles (Messages · Attachments · Span · Output size). Reads `runner.runStats`; takes pendingStart/End so the Span tile updates live as the user picks dates before any run.
- `Views/RunStrip.swift` — blue-gradient run strip with inline white Run/Cancel button, stage caption, kbd hint (⌘⏎), and `ContinuousProgressBar` (smooth fill driven by `stage / 5`, with an indeterminate shimmer for stage 0). Replaces the old 5-segment `ProgressBar`.
- `Views/LiveOutputCard.swift` — frosted card containing the stdout log + post-run actions. `ChipButton` is the reusable pill button used across the redesign (header chips, Copy/Open log, Reveal/Transcript/etc.). `FlowChips`/`FlowLayout` line-break the action row when the card is narrower than the chip total. Replaces the old `LogPane`.
- `Services/AppSupport.swift` — single source of truth for `~/Library/Application Support/MessagesExporterGUI/` paths (`directory`, `runHistoryURL`, `presetsURL`); created on demand. Also `RelativeTime.short(_:)` for the sidebar's "now / 4h ago / yesterday / Apr 21" rendering.
- `Services/SendersService.swift` — read-only SQLite walker over `~/Library/Messages/chat.db`. `enumerate(chatDB:addressBook:)` returns one `Sender` per 1:1 conversation partner with message count + last-message date, sorted most-recent-first. The 1:1 filter is done via a `NOT EXISTS` probe against `chat_handle_join` (more reliable than `chat.style`, which drifts between macOS releases). `normalize(handle:)` mirrors the Python CLI's `norm()` so the same handle string keys both the chat.db walker and the AddressBook lookup. No SPM deps — uses the system `sqlite3` library with `mode=ro&immutable=1` so a live Messages.app doesn't block the read.
- `Services/AddressBookLookup.swift` — read-only walker over `~/Library/Application Support/AddressBook/Sources/*/AddressBook-v22.abcddb`. `buildLookup(sourcesRoot:)` builds a `[normalized-handle: displayName]` map. Same FDA grant as chat.db; no `Contacts.framework`. First-writer-wins on collisions across sources (iCloud beats local when listed first).
- `Views/SenderCombobox.swift` — TextField + chevron dropdown that replaces the plain contact field. Picking a row latches `pickedHandle`; the runner emits it via `--handle`. Typing clears the latch and falls back to the legacy positional-contact path. Background-loads via `Task.detached` so the chat.db enumeration never blocks the main actor.
- `Services/RunHistoryStore.swift` — `@MainActor` `ObservableObject` over a JSON file. `record(entry)` inserts at index 0 and trims to `maxEntries` (50). The runner appends here on every `run(_:)` regardless of outcome — failures are useful breadcrumbs. Sidebar reads `entries.prefix(5)`.
- `Services/PresetStore.swift` — `@MainActor` `ObservableObject` for named export configurations. `upsert(_:)` replaces in place when a preset with the same id exists (used by `Save preset` re-saves) and appends otherwise. Stored snapshot semantics — applying a preset later restores the dates that were on the form at save time, not a relative range.
- `Services/BackupService.swift` — launch-time auto-backup per `PhantomLives/CLAUDE.md`. `runOnLaunchIfDue()` is called from `MessagesExporterGUIApp.init` before any UI; reads `autoBackupEnabled` / `backupPath` / `backupRetentionDays` / `lastBackupAt` from `UserDefaults`. 5-minute debounce, 14-day retention default, NSLog on failure (never throws). Verify-before-restore is non-destructive: extracts to a temp dir and counts JSON entries before any destructive action. Pre-restore writes a safety backup so the user can always undo.
- `Views/SavePresetSheet.swift` — modal that snapshots the current Contact / range / Mode / Transcribe (+ model) / Emoji and persists to `PresetStore`. Empty/whitespace names are rejected.
- `Views/BackupSettingsView.swift` — `Settings → Backup` content. Toggle + path picker + retention stepper + Run-now button + list of recent archives with Test (verify) / Restore (with safety pre-backup) / Reveal actions. Read-only `lastBackupAt` caption.

### Contract with the CLI

The runner depends on three things being stable in the CLI's stdout:

1. **Stage markers** — lines beginning with `[N/5]` for `N` in 1...5. Parser at `ExportRunner.stageNumber(in:)`.
2. **Run folder line** — `[4/5] Writing to <path>`. Parser at `ExportRunner.runFolderPath(in:)`.
3. **Exit code semantics** — exit 0 with no run-folder line means "no contact match or empty range" (not failure). Exit non-zero means real failure.

If the CLI's stdout format ever changes, those parsers and the unit tests around them are the only thing to update on the GUI side.

### Subprocess plumbing notes

- `ExportRunner.runProcessStreaming` pipes stdout and stderr into the same `Pipe`, with `PYTHONUNBUFFERED=1` injected into the child env so the `[N/5]` lines arrive in real time rather than at process exit.
- `LineBuffer` (private to ExportRunner) is a small `@unchecked Sendable` reference type with an `NSLock` — it exists solely to satisfy Swift's strict-concurrency checks while accumulating partial-line bytes from `readabilityHandler` (which runs serially per file handle but isn't typed as such). `extractLines()` splits on `\n`, `\r\n`, and bare `\r`, and returns `(String, replacesLast: Bool)` pairs — `replacesLast` is true when the previous terminator was a bare `\r`, matching terminal carriage-return overwrite semantics (tqdm progress bars animate in-place rather than producing a new line per tick).
- `nonisolated static` on `stageNumber(in:)` and `runFolderPath(in:)` is what lets the test suite call them off the main actor. They're pure functions of their input string.

## Build / release

### Versioning

`build-app.sh` derives the version from git:

- `CFBundleShortVersionString = 1.0.<outer-repo-commit-count>` — the canonical release identifier.
- `CFBundleVersion = <count>.<short-sha>` — disambiguates rebuilds against the same commit.

Every commit is therefore uniquely identifiable in the running app's `Bundle.main.infoDictionary`, and the user-visible short version maps 1:1 to a CHANGELOG entry (from 1.0.203 onwards — pre-2026-05-11 entries 1.0.0–1.0.14 used a separate sequential scheme and are kept as historical labels). Override with `SHORT_VERSION=` / `BUILD_NUMBER=` env vars if you need to pin a build.

When you write a new CHANGELOG entry, label it with the outer-repo commit count *that the commit introducing the entry will produce*. Concretely: `git rev-list --count HEAD` + 1, assuming you collapse all the work into one commit. PurpleIRC's CHANGELOG follows the same convention.

### Build pipeline

The `Info.plist` is generated inline in the build script. Notable keys:

- `LSMinimumSystemVersion` = 14.0 — matches the SwiftUI deployment target in `Package.swift`.
- `CFBundleIdentifier` = `com.bronty13.MessagesExporterGUI`. Avoid `com.example.*` — modern macOS treats it with extra TCC suspicion; we hit this in early-1.0 troubleshooting.

The bundle is **assembled, signed, and verified inside a `mktemp -d` directory outside iCloud Drive**, then `ditto --noextattr`'d back into the project root as `MessagesExporterGUI.app`. The project lives under `~/Documents`, which is iCloud-synced; the File Provider re-attaches `com.apple.FinderInfo` / `com.apple.fileprovider.fpfs#P` at arbitrary moments, including in the window between `xattr -cr` and `codesign`, which intermittently failed with "resource fork, Finder information, or similar detritus not allowed". Building in /tmp sidesteps the race entirely. Same pattern as `PurpleIRC/build-app.sh`, `PurpleDedup/build-app.sh`, and `PurpleLife/build-app.sh`.

Code-signed with the maintainer's **Developer ID Application** certificate when present in the keychain (env var `DEVELOPER_ID`, default `Developer ID Application: Robert Olen (SRKV8T38CD)`), with `--options runtime` (Hardened Runtime) and `--timestamp` (trusted timestamp). Falls back to ad-hoc (`codesign --sign -`) when the cert isn't installed — the app still launches, but FDA grants rotate on every rebuild because TCC keys ad-hoc grants on cdhash. With Developer ID, TCC keys grants on `(team ID, bundle ID)` — rebuilds preserve the user's FDA grant.

The app icon is regenerated each build via `Scripts/generate-icon.swift` + `iconutil`.

## What the GUI deliberately does not do

- **Read chat.db**. The CLI does it; the CLI is sandboxed by FDA, so this app needs FDA too — but the actual SQLite query lives in Python.
- **Sanitize media**. `exiftool` and `ffmpeg` are CLI-side dependencies installed by `messages-exporter/install.sh`.
- **Track per-attachment progress**. The CLI's stdout doesn't emit it. Adding it would require modifying the CLI to print per-file lines and updating the parser here.
- **Bundle the CLI**. The `.app` requires `~/.local/bin/export_messages` from the sibling subproject; the install sheet offers to run `install.sh` if missing. We do not ship a copy of the Python script or its venv inside `Resources/`.

## Release hygiene

Per `PhantomLives/CLAUDE.md`, every functional change should:

1. Bump the version (auto-derived from git here — committing IS the bump).
2. Add a CHANGELOG entry.
3. Update affected docs (this file, README, USER_MANUAL, INSTALL).
4. Add or update tests (the parsers in `ExportRunner` are the test surface — view code is uncovered).

`./run-tests.sh` is the gate. The Process-spawning paths are integration-only and not covered by the unit tests.

## Why no Contacts.framework

A previous version (1.0.0–1.0.4) used `CNContactStore` for in-GUI autocomplete. It was removed in 1.0.5 because:

- The CLI already does its own AddressBook substring match. The GUI autocomplete was strictly duplicating work — dropping it loses no functionality.
- Ad-hoc signing rotates `cdhash` on every rebuild, and TCC pins grants to `cdhash`. After a rebuild the old TCC row exists but doesn't match the new binary — macOS reports `notDetermined` AND silently refuses to re-prompt.
- For unsigned/untrusted bundles `tccd` doesn't even register the `requestAccess` call — no entry appears in System Settings → Privacy & Security → Contacts, leaving no manual-grant path.
- The `com.example.*` bundle prefix (used originally) makes some macOS frameworks even more suspicious.

**Update (2026-05-12)**: a sender picker came back as `Views/SenderCombobox.swift`, but **without `Contacts.framework`**. The new approach enumerates conversation partners directly from `chat.db` (`SendersService`) and resolves display names by reading `AddressBook-v22.abcddb` files in Swift (`AddressBookLookup`) — both under the FDA grant the app already requires for chat.db itself. No new TCC scope, no `requestAccess` call, no cdhash dance. The `osascript` fallback noted above is no longer needed.

## Known limitations

- The install-sheet path search (`installScriptCandidates`) is hard-coded to look next to the `.app` or under `~/Documents/GitHub/PhantomLives/messages-exporter/`. Move the `.app` to a non-standard location and the sheet's "Install now" will fail to find the script — user must run `install.sh` manually.
- No "recent runs" history. Each launch starts fresh.
