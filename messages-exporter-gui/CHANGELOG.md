# Changelog

All notable changes to messages-exporter-gui will be documented in this file.

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
