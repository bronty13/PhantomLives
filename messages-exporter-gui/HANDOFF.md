# messages-exporter-gui — Handoff

Snapshot of where the project stands so a future session (human or AI) can pick up without re-deriving everything from the commit history.
Last updated: 2026-04-26.

## What it is

A small SwiftUI macOS front end for the sibling `messages-exporter` Python CLI. Wraps the CLI's stdout into a progress bar + copyable log, and adds one-click buttons to reveal the run folder and open the transcript / summary / manifest.

```
swift build                        # debug build
./build-app.sh                     # release build → MessagesExporterGUI.app
./run-tests.sh                     # 7 tests via swift-testing
open MessagesExporterGUI.app
```

Requires macOS 14+, Swift 5.9+. Tests run via Command Line Tools' bundled `Testing.framework`; the wrapper script handles the rpath dance the same way `PurpleIRC/run-tests.sh` does.

## Architecture at a glance

The app does three things and nothing else: format the CLI invocation, spawn it as a child process, and parse its stdout. There is **no chat.db reader, no AddressBook walker, no media handler in Swift** — those all live in the CLI and stay there.

- `App.swift` — `@main`. WindowGroup + Settings scene. Owns one `ExportRunner` injected via `environmentObject`.
- `RootView.swift` — top-level form (Output / Contact / From / To / Emoji), Run row + ProgressBar, LogPane, version footer. Aligned-label custom layout (`LabeledRow`), not a Form, so all five inputs fit above the fold. Also defines `OutputFolderRow`, `VersionFooter`, the `InstallSheet`, and the `SettingsView` scene. The Contact field is a plain `TextField` — the CLI does its own AddressBook substring matching, so the GUI deliberately does not touch `Contacts.framework` (see "Why no Contacts.framework" below).
- `Model/ExportRequest.swift` — pure value type. Builds the argv passed to the CLI with the date format the CLI's argparse expects (`yyyy-MM-dd HH:mm`, local TZ, `en_US_POSIX` locale).
- `Model/ExportRunner.swift` — `@MainActor ObservableObject`. Spawns `Process`, streams stdout via `Pipe.readabilityHandler`, parses `[N/5]` markers and the `[4/5] Writing to ...` line. Pre-flights `~/.local/bin/export_messages` existence and offers to run sibling `install.sh` if missing. Also detects `authorization denied` / `operation not permitted` in stdout and surfaces a Full Disk Access message.
- `Views/ProgressBar.swift` — 5-segment bar that fills as `runner.stage` advances.
- `Views/LogPane.swift` — single selectable Text inside a ScrollView for cross-line copy, Copy-log button, and the post-run Reveal / Transcript / Summary / Manifest action row. Each open button is disabled when its file isn't present.

### Contract with the CLI

The runner depends on three things being stable in the CLI's stdout:

1. **Stage markers** — lines beginning with `[N/5]` for `N` in 1...5. Parser at `ExportRunner.stageNumber(in:)`.
2. **Run folder line** — `[4/5] Writing to <path>`. Parser at `ExportRunner.runFolderPath(in:)`.
3. **Exit code semantics** — exit 0 with no run-folder line means "no contact match or empty range" (not failure). Exit non-zero means real failure.

If the CLI's stdout format ever changes, those parsers and the unit tests around them are the only thing to update on the GUI side.

### Subprocess plumbing notes

- `ExportRunner.runProcessStreaming` pipes stdout and stderr into the same `Pipe`, with `PYTHONUNBUFFERED=1` injected into the child env so the `[N/5]` lines arrive in real time rather than at process exit.
- `LineBuffer` (private to ExportRunner) is a small `@unchecked Sendable` reference type with an `NSLock` — it exists solely to satisfy Swift's strict-concurrency checks while accumulating partial-line bytes from `readabilityHandler` (which runs serially per file handle but isn't typed as such).
- `nonisolated static` on `stageNumber(in:)` and `runFolderPath(in:)` is what lets the test suite call them off the main actor. They're pure functions of their input string.

## Build / release

`build-app.sh` derives the version from git: `CFBundleShortVersionString = 1.0.<commit-count>`, `CFBundleVersion = <count>.<short-sha>`. So every commit is uniquely identifiable in the running app's `Bundle.main.infoDictionary`. Override with `SHORT_VERSION=` / `BUILD_NUMBER=` env vars if needed.

The `Info.plist` is generated inline in the build script. Notable keys:

- `LSMinimumSystemVersion` = 14.0 — matches the SwiftUI deployment target in `Package.swift`.
- `CFBundleIdentifier` = `com.bronty13.MessagesExporterGUI`. Avoid `com.example.*` — modern macOS treats it with extra TCC suspicion; we hit this in 1.0.4 troubleshooting.

Ad-hoc codesigned (`codesign --force --sign -`) so it launches without a dev cert. There is no app icon yet — add one mirroring `PurpleIRC/Scripts/generate-icon.swift` when needed.

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

If we ever want autocomplete back, the lighter-weight option is shelling out to `osascript` (uses Script Editor's existing TCC grants) rather than reintroducing a direct `Contacts.framework` dependency.

## Known limitations

- No way to cancel a running export from the UI. The underlying `Process` is held by the runner; adding a `terminate()` button is straightforward but not currently exposed.
- The install-sheet path search (`installScriptCandidates`) is hard-coded to look next to the `.app` or under `~/Documents/GitHub/PhantomLives/messages-exporter/`. Move the `.app` to a non-standard location and the sheet's "Install now" will fail to find the script — user must run `install.sh` manually.
- No "recent runs" history. Each launch starts fresh.
