# Changelog

All notable changes to messages-exporter-gui will be documented in this file.

## [1.0.261] — 2026-05-12

### Added
- **Sender picker (combobox)** on the Contact row, replacing the plain
  AddressBook-substring TextField. Enumerates conversation partners
  directly from `~/Library/Messages/chat.db` (no `Contacts.framework`,
  no extra TCC prompt — the existing FDA grant covers it) and
  cross-references the abcddb files under
  `~/Library/Application Support/AddressBook/Sources/` for display
  names. Each row shows the resolved name (or raw handle when the
  number/email isn't in AddressBook), service badge (iMessage/SMS),
  message count, and last-message date. Picking a row sends the exact
  handle to the CLI via `--handle`, skipping fuzzy AddressBook
  matching. Typing free-form text still works as the legacy positional
  contact — the combobox is purely additive.
- **`SendersService` + `AddressBookLookup`** (`Services/`). Pure
  read-only SQLite walkers over chat.db and abcddb respectively,
  opened with `mode=ro&immutable=1` so a live Messages.app doesn't
  block the read. Same pattern as `PurpleDedup`'s direct
  `Photos.sqlite` enumeration. No new SPM dependencies — uses the
  system `sqlite3` library.
- **CLI `--handle` flag** in sibling `messages-exporter 1.3.3`. The
  GUI relies on it; the `ExportRequest.handles` field emits it when
  populated, otherwise the legacy positional-contact path runs.
- **7 new tests** — `SendersService` normalize (email lowercase, phone
  last-10-digit, shortcode, missing-DB diagnostic) and `ExportRequest`
  argv branches (handles=[] omits flag, single handle, comma-joined
  multi-handle). 63 tests total in 10 suites, was 56 in 9.

### Changed
- **`Sender` model** (`Services/SendersService.swift`) is the new
  carrier between the chat.db walker and the picker UI; `Sender.id`
  uses the raw handle as its stable identifier.
- **Recent-runs / Saved-presets restore** clears any picked-handle
  latch on apply, so loading a past run drops the user into the
  positional-contact path. Re-pick from the combobox if you want the
  exact-handle form.

### Notes
- Group chats are excluded from v1 — the picker shows 1:1 senders only.
  Group support needs different CLI semantics (multiple handles per
  export, group-name handling) and is a separate follow-up.
- The `1.0.5` "Why no Contacts.framework" rationale in `HANDOFF.md`
  still applies — we didn't reintroduce `CNContactStore`. The new
  picker reads SQLite files directly under FDA, the same way the
  Python CLI has always done.

## [1.0.260] — 2026-05-12

### Fixed
- **Date range silently dropped sub-minute precision.** The GUI's date
  formatter was `yyyy-MM-dd HH:mm`, so the trailing seconds of the
  end-of-range were quietly truncated to `:00` on the way to the CLI —
  any message later than `HH:MM:00` within the picker's chosen minute
  was excluded. The CLI's `parse()` already accepts `HH:MM:SS`; we now
  always emit it.
- **First message of the range could be skipped.** Messages.app's
  swipe-to-reveal time rounds to the displayed minute — a message
  stored at `10:11:45` can display as "10:12". Users picking the
  displayed minute as the start of a forensic range therefore had the
  first message fall a few seconds outside the bound. The new **Range
  precision → Expand start by 60 seconds** setting (default on) pulls
  the resolved start one full minute earlier so the rounded display
  case is always captured. Disable it in **Messages Exporter →
  Settings…** when you want the picker's bound treated as strict.

### Added
- **Seconds field next to each date picker.** The `HH:MM` picker is
  unchanged; a small two-digit text field + stepper to its right is
  the seconds knob, defaulting to `:00` on the From side and `:59` on
  the To side so a minute-precision range naturally covers the whole
  minute. Loading a preset or recent run pulls back the saved second.
- **"Resolved" caption** below the date row showing the exact bounds
  about to be sent to the CLI, including the 60s buffer when on. Pins
  the new behavior to something visible so the buffer is never a
  surprise.
- **New `RangeResolver` helpers** (`Model/ExportRequest.swift`) — pure
  functions for seconds-replace + buffer math, covered by 5 new tests
  in a dedicated `RangeResolver` suite plus one new arg-list assertion
  pinning the `HH:MM:SS` format. 56 tests total in 9 suites, was 50
  in 8.

## [1.0.203] — 2026-05-11

> Numbering note: starting with this entry, CHANGELOG release numbers
> match the bundle version stamped by `build-app.sh`
> (`1.0.<outer-repo-commit-count>`), aligning with the PurpleIRC
> convention. Pre-2026-05-11 entries (1.0.0–1.0.14) used a separate
> sequential scheme; they are kept as-is for historical accuracy.

### Fixed
- **`build-app.sh` codesign race against iCloud File Provider.** The
  bundle was assembled and signed in the project root, which lives
  under `~/Documents` and therefore inside iCloud Drive. The File
  Provider re-attached `com.apple.FinderInfo` /
  `com.apple.fileprovider.fpfs#P` between the `xattr -cr` strip and
  the `codesign` call, which intermittently failed with "resource
  fork, Finder information, or similar detritus not allowed".
  Refactored to assemble + sign + verify in a `mktemp -d` directory
  outside iCloud, then `ditto --noextattr` the signed bundle back
  into the project root — same pattern used by
  `PurpleIRC/build-app.sh`, `PurpleDedup/build-app.sh`, and
  `PurpleLife/build-app.sh`. `codesign --verify` can now use
  `--strict` because the verify runs against the in-/tmp bundle
  before iCloud has any chance to re-stamp it.

### Docs
- Aligned the GUI's release numbering with the auto-derived bundle
  version (see numbering note above) so a user's About-pane version
  string maps directly to a CHANGELOG entry.
- Removed pinned "Current release: ..." from README and the version
  callout from HANDOFF's "Last updated" line — both go stale on every
  commit under the new scheme. CHANGELOG is the source of truth.
- Refreshed test counts in HANDOFF and INSTALL (now 50 tests in 8
  suites, was 24 / 18).
- Clarified in INSTALL that the cdhash-rotation / duplicate-Privacy-
  entry problem only affects ad-hoc builds — Developer-ID-signed
  builds key TCC on `(team ID, bundle ID)` and survive rebuilds.

## [1.0.14] — 2026-05-08

### Added
- **Run history** — every successful or failed export is recorded in
  `~/Library/Application Support/MessagesExporterGUI/runs.json`. The
  sidebar's **Recent runs** list shows the most recent five with a
  status dot (green = success, amber = failed/cancelled), the
  contact-and-span title, and a relative time. Clicking a row applies
  the recorded contact + range + Mode + Transcribe + Emoji onto the
  form. New `RunHistoryStore` (`Services/RunHistoryStore.swift`)
  caps history at 50 entries and trims at write time.
- **Saved presets** — the header **☆ Save preset** chip is now
  functional: it opens a sheet that names the current configuration
  and persists it to `presets.json`. The sidebar's **Saved presets**
  list shows every preset with a one-line summary; click to apply,
  right-click to delete. New `PresetStore`
  (`Services/PresetStore.swift`) and `Views/SavePresetSheet.swift`.
- **Launch-time auto-backup** per `PhantomLives/CLAUDE.md`. New
  `Services/BackupService.swift` zips
  `~/Library/Application Support/MessagesExporterGUI/` to
  `~/Downloads/MessagesExporterGUI backup/MessagesExporterGUI-<stamp>.zip`
  on every launch. 14-day retention default (`0` = keep forever),
  5-minute debounce, NSLog-on-failure (never crashes launch). Override
  any field in **Settings → Backup**.
- **Settings → Backup** section. Toggle, target-folder picker,
  retention stepper, **Run backup now** button, and a recent-backups
  list with **Test** (verify counts), **Restore** (with mandatory
  pre-restore safety backup), and **Reveal** actions per row.
  `Views/BackupSettingsView.swift`.
- **15 new tests** covering the stores and backup service:
  `RunHistoryStore` ordering / trim / persistence / delete / clear,
  `PresetStore` upsert / replace-in-place / rename / persistence,
  and the four CLAUDE.md-mandated backup tests (target auto-create,
  retention prefix-scoping, retention=0 keeps-forever, list ordering,
  debounce). 50 tests total in 8 suites.

### Changed
- **Sidebar reorganised** — drops the "Soon" pills now that Recent
  runs and Saved presets are real. Empty-state hints replace the
  placeholder copy when either list is empty (e.g. fresh install).
- **`ExportRunner.init`** now takes an optional `RunHistoryStore`;
  callers default to a real on-disk store. Each call to `run(_:)`
  appends a `RunHistoryEntry` to the store on completion regardless
  of outcome — the sidebar surfaces failures so you can re-try with
  adjusted settings without re-typing.
- **`ExportMode` / `EmojiMode` / `WhisperModel`** now conform to
  `Codable` so they can round-trip through the JSON stores.

## [1.0.13] — 2026-05-08

### Changed
- **Mission Control redesign.** Complete UI re-skin to the
  Tahoe-glass / oklch direction handed off in
  `Message Exporter UI-handoff.zip`. The single-form RootView is
  replaced with a sidebar + main pane layout.
  - **Sidebar** (220 px, `.thinMaterial`): nav rows for Overview /
    New export (active) / Recent runs (Soon) / Saved presets (Soon),
    a Recent header with a placeholder until the history store
    ships, and an FDA status pill at the bottom (green when granted,
    amber + click-to-resolve when denied).
  - **Main pane**: NEW EXPORT kicker → contact-name h1 → chip
    buttons (Save preset · stub, Reveal output · functional) → four
    glass stat tiles (Messages · Attachments · Span · Output size,
    accent-tinted) → form card (Contact / From / To / Mode /
    Transcribe) → blue-gradient run strip with inline white Run
    button + continuous progress → live-output card with
    Copy / Open log / file chips.
  - **Tinted gradient window background** + `.regularMaterial`
    surfaces approximating the design's frosted-glass aesthetic;
    light/dark themes follow system appearance.
  - **Window chrome**: `.hiddenTitleBar` style, min size 920 × 640,
    ideal 1100 × 780 to match the design's artboard.
- **Output folder + Emoji handling moved to Settings.** Both
  controls were on the main form previously; the redesign trades
  visible chrome for focus, and these are rarely changed once set.
- **Continuous progress bar.** Replaces the 5-segment bar with a
  smooth percentage-fill (still stage-driven; same `[N/5]` parser).
  Stage 0 plays an indeterminate shimmer while waiting for the
  first marker.

### Added
- **Stat tiles populated from the run.** New `RunStats` struct
  parses `[3/5] N messages in range` mid-stream, then refines from
  `metadata.json` after stage 5 (photos / videos / voice counts).
  Output size is computed by walking the run folder. Span is
  derived from the configured From/To dates and shows live as the
  user picks them.
- **`MissionTheme`** environment value with light/dark token
  pairs (background gradient, inks, rules, accent, run-strip
  gradient, status colors). Resolved by a `MissionThemeReader`
  wrapper on the root view.
- **Reusable `GlassCard`, `ChipButton`, `FlowChips`** in
  `Views/LiveOutputCard.swift`, used by tiles, the form card,
  the live-output card, and the post-run action row.
- **Tests for `RunStats`** (11 new): mid-stream message-count
  parser, ByteCountFormatter rendering, span unit selection,
  metadata.json decoding (with + without summary block), output-
  bytes folder walk. 35 tests total in 5 suites.

### Removed
- `Views/ProgressBar.swift` (replaced by `ContinuousProgressBar`
  inside `RunStrip.swift`).
- `Views/LogPane.swift` (replaced by `LiveOutputCard.swift`; same
  data, same actions, new aesthetic).
- The fake macOS title bar from the design mock — real macOS
  provides one, no need to redraw it.

## [1.0.12] — 2026-05-01

### Added
- **Cancel export button.** A destructive "Cancel" button appears in the
  run row while an export is in progress. Clicking it shows a
  `confirmationDialog` ("Cancel export?") to prevent accidental
  termination. Confirming sends `SIGTERM` to the child process and
  shows a "Cancelling…" label with the button disabled until the
  process exits. Any attachments already written to disk are preserved.
- **Debug Logging toggle** in **Settings → Diagnostics**. When on,
  passes `--debug` to the CLI, which enables full tqdm/Whisper/pip
  output from the transcription subprocess. Off by default — normal
  runs show only meaningful progress lines. Persists in UserDefaults
  across launches.
- **Streaming log pane in the Install sheet.** The sheet now shows a
  scrolling log pane (180 px) that streams install output in real time
  so the user can see brew/pip steps rather than just a spinning
  indicator.
- **`\r` (carriage return) line handling in `LineBuffer`.** tqdm
  progress bars overwrite the current terminal line using `\r`; the
  buffer now tracks bare-`\r` vs `\r\n` vs `\n` and sets a
  `replacesLast` flag. `processLine(_:replacesLast:)` replaces the
  last log entry when `replacesLast` is true, so progress bars animate
  in the log pane instead of producing hundreds of duplicate lines.

### Changed
- `ExportRequest` gains a `debug: Bool = false` field. `argumentList()`
  appends `--debug` when true.

### CLI dependency
Requires `messages-exporter` 1.3.2 (the version that introduces
`--debug`). Re-run `messages-exporter/install.sh` to upgrade.

## [1.0.11] — 2026-05-01

### Added

- **Optional Whisper transcription of audio/video attachments.** New
  inline **Transcribe** checkbox alongside the Mode picker. When on,
  passes `--transcribe --transcribe-model <model>` to the CLI; the
  CLI then shells out to the sibling `PhantomLives/transcribe/`
  project (Apple-MLX Whisper, Metal-accelerated, fully local) for
  every audio/video attachment and writes
  `<attachment>.transcript.json` + `<attachment>.transcript.txt`
  next to each AV file. In raw mode both sidecars are hashed
  (md5/sha1/sha256) and recorded in `metadata.json` and
  `chain_of_custody.log`. Failures don't stop the export — the
  per-attachment error is captured in metadata + log.
- **Settings → Whisper transcription**: model picker (tiny / base /
  small / medium / large / **turbo** default) with descriptive
  labels, RAM hints, and a "Reset to turbo" shortcut. The selected
  model persists in `UserDefaults` so it sticks across runs.
- `WhisperModel` Swift enum mirroring the CLI's `WHISPER_MODELS` list
  — a unit test asserts the rawValues match the CLI exactly so a
  rename on either side is caught locally.

### CLI dependency

Requires `messages-exporter` 1.3.0 (the version that introduces
`--transcribe`). Re-run `messages-exporter/install.sh` to upgrade the
bundled CLI. The Whisper transcription itself relies on the sibling
`PhantomLives/transcribe/` subproject existing on disk — the GUI
records a one-line warning in the export log if it can't be found.

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
