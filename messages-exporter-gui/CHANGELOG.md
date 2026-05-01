# Changelog

All notable changes to messages-exporter-gui will be documented in this file.

## [1.0.10] — 2026-05-01

### Changed

- `build-app.sh` signs with a **Developer ID Application** certificate
  when one is in the keychain (env var `DEVELOPER_ID`, default
  `Developer ID Application: Robert Olen (SRKV8T38CD)`), and falls back
  to ad-hoc signing otherwise. Sets `--options runtime` (Hardened
  Runtime, required for future notarization, no-op without it) and
  `--timestamp` (embeds a trusted timestamp so the signature stays
  verifiable past the cert's eventual expiry).
- Verification step uses codesign's exit code directly rather than
  grepping its output — piping into `grep -q` under `set -o pipefail`
  triggered a SIGPIPE-induced false negative.
- Strips `com.apple.FinderInfo` from the bundle root explicitly (in
  addition to the recursive `xattr -cr`); a leftover directory-level
  FinderInfo xattr (added back by iCloud File Provider on `~/Documents/`
  paths after every save) was failing strict signature verification
  even though the embedded signature itself was valid.

### Why this matters for FDA stability

With a Developer ID Application certificate, TCC keys grants on
`(team ID, bundle ID)` rather than the cdhash. So a rebuild now
preserves the user's Full Disk Access permission instead of rotating
the cdhash and creating a fresh "MessagesExporterGUI 2" Privacy entry.
The in-app FDA preflight + reset button is still the right tool when
TCC ends up in a weird state, but it should rarely be necessary on
this build flow.

## [1.0.9] — 2026-05-01

### Fixed

- The persistent FDA banner used to remain visible after dismissing the
  sheet even when the user had granted access in the meantime — the
  status was probed once on launch and never re-checked. Three changes
  fix this:
  1. The view subscribes to `NSApplication.didBecomeActiveNotification`
     and re-probes on every focus return, so granting access in System
     Settings and switching back to the app clears the banner
     automatically.
  2. The sheet's "Continue anyway" button now re-probes before
     dismissing.
  3. New "I've granted access" primary action on the sheet performs an
     explicit re-probe and shows a hint if the result is still denied
     (rare — would indicate the TCC grant didn't apply to the running
     cdhash, which only a relaunch can fix).
- The inline banner gained a **Re-check** button alongside **Resolve…**
  for the same purpose without re-opening the sheet.

## [1.0.8] — 2026-05-01

### Added

- **Full Disk Access preflight on launch.** The app probes
  `~/Library/Messages/chat.db` for readability before the main window
  becomes interactive. If the open() syscall returns EPERM (the FDA-
  denied signal), a modal sheet titled "Full Disk Access required" is
  presented with explanatory copy and four actions: **Open Privacy
  Settings** (deep-links to System Settings → Privacy & Security → Full
  Disk Access), **Reset Privacy entries** (runs `tccutil reset
  SystemPolicyAllFiles com.bronty13.MessagesExporterGUI` to wipe stale
  cdhash-pinned grants — useful after several ad-hoc-signed rebuilds
  accumulate duplicate "MessagesExporterGUI" / "MessagesExporterGUI 2"
  entries), **Quit** (since TCC pins cdhash at spawn, a granted
  permission only takes effect on the next launch), and **Continue
  anyway** (dismisses the sheet but leaves a persistent orange banner
  at the top of the main window so the user doesn't forget).
- Inline orange "Full Disk Access required" banner with a **Resolve…**
  button that re-opens the FDA sheet, displayed whenever
  `runner.fdaStatus == .denied`. Survives across the rest of the
  session (TCC can't transition denied→granted without a relaunch).
- The runtime FDA-denied detection (`authorization denied` / `operation
  not permitted` in CLI stdout) now also flips `fdaStatus` to
  `.denied` so the banner appears even when the launch-time probe
  briefly succeeded but a subsequent export hit the wall.
- `ExportRunner.probeReadable(path:)` — pure helper extracted so the
  new `FullDiskAccessProbeTests` suite can exercise the classification
  logic against a tempdir instead of the live chat.db.

### Changed

- `build-app.sh` now removes `MessagesExporterGUI 2.app`,
  `MessagesExporterGUI 3.app`, etc., on every release build. macOS
  Finder auto-renames `.app` bundles when an old copy is in use, and
  those duplicates would otherwise show up as separate Privacy entries
  with their own (stale) cdhashes — the very TCC noise the new
  preflight sheet exists to clean up.
- README and INSTALL describe the FDA preflight, the duplicate-entry
  reset path, and the underlying cdhash rotation cause.

## [1.0.7] — 2026-05-01

### Added

- **Mode** segmented picker — choose between **Sanitized** (default — the
  existing pipeline: HEIC→JPG, EXIF stripped, caption-derived filenames)
  and **Raw (forensic)** (passes `--raw` to the CLI). In raw mode each
  attachment is copied byte-for-byte with its original filename and a
  sortable `[seq]_[YYYYMMDDTHHMMSS]_[sender]_` prefix; the run folder also
  contains `metadata.json` (sha256 + extracted EXIF + filesystem
  timestamps per attachment) and an append-only `chain_of_custody.log`.
  The Emoji picker is greyed out when raw is selected (the CLI ignores
  `--emoji` in that mode).
- **Metadata** and **Custody log** action-row buttons that open
  `metadata.json` and `chain_of_custody.log` respectively. Both are
  disabled when their file isn't present in the run folder, which is the
  case in sanitized mode.

### CLI dependency

Requires `messages-exporter` 1.1.0 (the version that introduces `--raw`).
Re-run `messages-exporter/install.sh` to upgrade the bundled CLI.

## [1.0.6] — 2026-04-27

### Changed

- Default output folder is now `~/Downloads/messages-exporter-gui/` (previously `~/Downloads/` directly). Per-run subfolders (`<contact>_<YYYYMMDD_HHMMSS>/`) land inside it, so all messages exports collect in one predictable place. The directory is created on demand if missing. Implements the new project-wide convention captured in `PhantomLives/CLAUDE.md`. Existing custom paths in user defaults are preserved — click **Reset** (or **Reset to Downloads** in Settings) to adopt the new default.

## [1.0.5] — 2026-04-26

### Added

- App icon. `Scripts/generate-icon.swift` renders a chat bubble over a download arrow on a teal gradient squircle; `build-app.sh` regenerates the `.iconset` every build and runs `iconutil` to produce `AppIcon.icns`. Mirrors the deterministic-icon approach used by the sibling PurpleIRC subproject.

### Removed

- In-app contact autocomplete via `Contacts.framework`. The Contact field is now a plain text field; the CLI matches the typed substring against AddressBook itself (which it already did — the GUI autocomplete was duplicating the work). Removing it eliminates a whole class of TCC headaches with ad-hoc-signed development builds (cdhash rotation invalidating prior grants, `tccd` silently dropping `requestAccess` for unsigned/untrusted bundles, missing entries in System Settings → Privacy & Security → Contacts).
- `ContactsService`, `ContactPicker`, `NSContactsUsageDescription` from Info.plist, and the 1.0.4 watchdog/fallback-button machinery — all now dead code.

### Changed

- Bundle identifier renamed from `com.example.MessagesExporterGUI` to `com.bronty13.MessagesExporterGUI` (the `com.example.*` prefix triggers extra TCC suspicion on modern macOS). UserDefaults under the old ID are not migrated; if you had a custom output folder set, re-pick it in Settings.

## [1.0.4] — 2026-04-26 (reverted in 1.0.5)

### Fixed

- Contacts permission was permanently stuck at `notDetermined` after rebuilding the app. Watchdog + "Open Privacy Settings" fallback added. Reverted in 1.0.5 by removing the Contacts integration entirely.

## [1.0.3] — 2026-04-26

### Fixed

- UI freeze when typing in the contact field. `ContactsService.suggestions(for:)` is now `nonisolated async` and dispatches the `CNContactStore.unifiedContacts(matching:)` query to a detached Task; previously the synchronous AddressBook query ran on the main thread on every keystroke and could stall the UI for seconds on large books.
- LogPane scroll anchor used an ID that incorporated the line count, which forced SwiftUI to tear down and rebuild the entire log Text view on every appended CLI line. Replaced with a stable zero-height anchor view at the bottom of the scroll content.

### Changed

- Contact field debounces autocomplete queries by 200 ms and cancels in-flight queries when a new keystroke arrives.

## [1.0.2] — 2026-04-26

### Changed

- Replaced the grouped Form layout with a tighter aligned-label grid so all five inputs (Output, Contact, From, To, Emoji) are visible at the default window height without scrolling.
- Run button and progress bar are now on the same row to reclaim more vertical space for the log pane.
- Output folder collapsed to a single line (the explanatory caption moved into a `.help()` tooltip).

### Added

- "Summary" and "Manifest" buttons in the post-run action row, alongside the existing Reveal / Transcript buttons. Each opens the corresponding file in its default app and disables itself if the file isn't present in the run folder.
- Inline `.help()` tooltips on the output path and the run-folder path so the full string is discoverable when truncated.

## [1.0.1] — 2026-04-26

### Added

- Output folder is now its own prominent section at the top of the main form, with Choose / Reset buttons and a "Default" badge when it matches `~/Downloads/`.
- "Copy log" button in the log pane and full drag-select across line boundaries (the pane now renders as a single selectable Text view).
- App version (`CFBundleShortVersionString` / `CFBundleVersion`) shown in a footer beneath the log.

### Changed

- Failed runs that contain `authorization denied` or `operation not permitted` in stdout now surface a clear "Full Disk Access denied — open System Settings → Privacy & Security → Full Disk Access" message instead of just an exit code. The GUI app itself needs FDA — child processes inherit TCC entitlements from their parent, so granting FDA to a Terminal that previously ran the CLI does not transfer.

## [1.0.0] — 2026-04-26

### Added

- Initial release. SwiftUI macOS front end for the `messages-exporter` CLI.
- Contact picker with `Contacts.framework` autocomplete (permission-tolerant — falls back to plain text if denied).
- Native date/time pickers; defaults to today 00:00 → today current time.
- Emoji-mode segmented control (strip / word / keep), default `word`.
- Configurable output folder via Settings scene; defaults to `~/Downloads/`.
- Streaming stdout log pane with scroll-to-bottom.
- 5-stage progress bar driven by the CLI's `[N/5]` markers.
- "Reveal in Finder" / "Open transcript" buttons appear after a successful run.
- Pre-flight check: if `~/.local/bin/export_messages` is missing, offers to run the sibling `install.sh`.
- Swift Testing suite covering argument formatting and stdout parsing.
- `build-app.sh` and `run-tests.sh` mirroring the PurpleIRC subproject's conventions.
