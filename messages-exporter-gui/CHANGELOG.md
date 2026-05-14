# Changelog

All notable changes to messages-exporter-gui will be documented in this file.

## [1.0.269] — 2026-05-14

### Fixed
- **Stopped corrupting our own venv with `pip install --force-reinstall`.**
  1.0.268's setup workflow ran `pip install --upgrade --force-reinstall`
  on top of whatever was already there — a workflow that *removes files
  first, re-extracts wheels after*. When the re-extract step failed for
  any reason (network blip, pip itself becoming a half-installed
  package mid-flight), the venv was left with `__pycache__` dirs and
  `.dist-info` directories but no `.py` files — pip thought packages
  were installed and refused to re-fetch them, mlx_whisper couldn't
  import numpy, transcribe.py's bootstrap fell into the pre-1.4.4
  pip-install-on-top-of-broken-state trap, and the user saw 42 fresh
  CalledProcessErrors across a 42-attachment export. The setup workflow
  was the source of the corruption it was trying to fix.
- New behaviour: every "Set up now" / "Try again" / "Rebuild from
  scratch" click runs the SAME workflow — **nuke .venv → `python -m
  venv` → `pip install`**. No `--force-reinstall`, no `--upgrade`, no
  `ensurepip --upgrade --default-pip` (that step was the no-op on a
  fresh venv, and the wrong recovery tool on a corrupt one). A clean
  slate every time is fast enough (~2 min over a healthy network) that
  there's no benefit to trying to patch in place.

### Added
- **Pre-run transcription health gate.** When the user clicks Run with
  the Transcribe toggle on, the GUI now probes the venv RIGHT BEFORE
  spawning the CLI. If any required module won't import, the warm
  preflight sheet opens — same dialog as the launch-time prompt, with
  `Set up now` / `Disable transcription` / `Not now`. This stops the
  "click Run, watch 42 tracebacks scroll past, then realise transcription
  is broken" scenario; the user gets a single clear decision point
  instead of a mid-batch failure parade.

### Changed
- The failure panel's `Rebuild from scratch` button removed. It did
  exactly what `Try again` does now that both `runSetup` and
  `rebuildVenv` are aliases for the clean-slate workflow.

## [1.0.268] — 2026-05-14

### Fixed
- **Transcription failing intermittently across long exports.** Each
  attachment in an iMessage export spawns a fresh transcribe.py
  invocation. With transcribe 1.4.2's unconditional `pip install`, an
  export with 42 attachments meant 42 sequential PyPI round-trips —
  enough rolls of the dice that intermittent network / rate-limit
  failures guaranteed *some* mid-batch crashes even when the venv was
  fully populated. Fixed by upgrading transcribe to **1.4.3** (skips
  `pip install` when every required module already imports cleanly).
- **GUI setup only installing mlx-whisper + truststore.** transcribe
  1.4.3's REQUIRED_PACKAGES list is `mlx, mlx-whisper, mlx-lm,
  truststore`, but the GUI's setup workflow only installed two of
  those — so transcribe's bootstrap would (correctly) detect mlx-lm
  missing and fall back to its own `pip install`, putting us right
  back into the flakiness window. New `requiredPipPackages` /
  `requiredImports` constants on the service are the single source of
  truth for both install and verification; new tests pin them in 1:1
  sync and lock the list to match transcribe.py's REQUIRED_PACKAGES.
- **Install now uses `--upgrade --force-reinstall` for the package
  list.** The user's venv kept ending up with packages pip "thought"
  were installed but whose files were physically absent — pip's
  dependency resolver warns about this with messages like "torch
  requires networkx, which is not installed" after a successful
  install. Force-reinstall makes the setup idempotent: clicking the
  button a second time after corruption *fixes* the venv instead of
  layering more half-installs on top.

### Changed
- The technical-details checklist's "mlx-whisper imports cleanly" row
  renamed to "Transcription packages import cleanly" and now probes
  all four required modules. Failure detail names exactly which
  module(s) are missing — useful when filing bug reports.

### Added
- 2 new tests:
  - **requiredPipPackages includes transcribe.py's full
    REQUIRED_PACKAGES list** — drift here causes flaky mid-export
    transcription failures.
  - **requiredImports maps 1:1 to requiredPipPackages** — locks the
    invariant that we verify what we install.
  **94/94 pass.**

## [1.0.267] — 2026-05-14

### Fixed
- **`Set up transcription` reported failure when the install actually
  succeeded.** Root cause: the in-flight pip log was being captured by
  a `readabilityHandler` that split each pipe chunk on `\n` and
  appended any partial-line tail as if it were a complete line —
  losing both the final lines of output (`Successfully installed …`,
  `[setup] Done.`) and miscounting structure when a UTF-8 line
  straddled a chunk boundary. Worse, we never drained the pipe after
  process exit, so anything still buffered at the moment pip
  terminated was silently dropped. Replaced with a `Data`-backed
  `PipeLineBuffer` (the same shape `ExportRunner` already uses for the
  CLI stream) that accumulates raw bytes, splits only on real `\n`
  boundaries (and treats `\r\n` as one terminator), and exposes a
  `drainTrailing()` the caller invokes after termination. Result: the
  setup log now shows what actually happened, including the final
  status line.
- **Stopped trusting pip's exit code as the final word.** Pip can
  print `Successfully installed …` and still return non-zero in edge
  cases (deprecation warnings escalating to errors, etc.), and even
  with the log buffer fixed it's still possible to lose the exit
  value to a torrent of output. The setup workflow now always runs a
  final acceptance probe — `python -c "import mlx_whisper"` — and
  declares success or failure from THAT, regardless of what any
  intermediate subprocess returned. If transcription works, we say it
  works, even if pip lied; if it doesn't, we say so even if pip lied
  the other way.

### Changed
- **Setup is one button, not five.** The preflight sheet now opens in
  a warm one-button view by default — a friendly summary of what
  needs to happen and a single primary action (`Set up now`,
  `Try again`, or `Done` depending on state). The previous 5-row
  technical checklist still exists for power users behind a
  collapsible `Show technical details` disclosure, but it never gates
  the primary action. `Set up transcription` and `Rebuild venv…`
  collapsed into one workflow that does the right thing every time:
  probe → rebuild if corrupt → install → verify. The destructive-
  rebuild path is still reachable from the failure panel's
  `Rebuild from scratch` button as a manual escape hatch.
- **Plain-English progress while setup runs.** Replaced the live pip
  log dump in the primary view with named phases above a progress
  bar: `Checking for ffmpeg…` → `Installing ffmpeg…` → `Setting up
  the Python environment…` → `Updating the package installer…` →
  `Downloading the transcription engine (~200 MB)…` → `Verifying…`.
  Pip output is still streamed live into the technical-details
  disclosure for anyone who wants to follow along or grab it for a
  bug report.
- **Warm failure messages with actionable next steps.** When auto-
  repair genuinely can't work, the wizard now classifies the failure
  and shows a plain-English message instead of a traceback. Examples:
  "Transcription needs Homebrew to install ffmpeg. Install Homebrew
  from https://brew.sh, then click Fix transcription again." (with a
  button that opens brew.sh); "Couldn't reach PyPI. Check your
  internet connection and try again." The technical detail remains
  available in the disclosure.

### Added
- 6 new tests pinning the UX-critical pieces in place: PipeLineBuffer
  joining lines across chunk boundaries, CRLF handling, empty-drain
  contract, monotonic progress fractions, terminal-state detection,
  and a regression guard that fails the build if any phase caption
  leaks "pip" or "mlx-whisper" jargon into the primary view.
  **92/92 pass.**

## [1.0.266] — 2026-05-14

### Fixed
- **`Set up transcription` failing with `ImportError: cannot import name
  '_log' from 'pip._internal.utils'`.** The user's venv had a corrupt
  pip — bundled pip's internal module layout drifted out of sync with
  the rest of the wheel, the canonical "Python upgrade left the venv
  half-migrated" symptom. The setup workflow now:
  1. Probes `python -m pip --version` inside the existing venv before
     doing anything else.
  2. If that fails for any reason, nukes the .venv and recreates it
     from scratch (auto-recovery — no user intervention needed).
  3. Runs `python -m ensurepip --upgrade --default-pip` to harden pip
     even on a freshly-created venv (a brand-new venv can still ship a
     stale pip; ensurepip refreshes from the host Python's bundled
     wheel without another full rebuild).
  4. Only then runs `pip install mlx-whisper truststore`.
  Steps 3+4 are shared by the new manual `Rebuild venv…` action.

### Added
- **`Rebuild venv…` button** in the preflight wizard footer. Manual
  escape hatch for the case where auto-detection misses or the user
  wants a clean reset. Gated behind a confirmation dialog because it
  deletes ~/Documents/GitHub/PhantomLives/transcribe/.venv.
- **Copy button on the Setup output log pane** — one-click clipboard
  capture for bug reports. Briefly flashes "Copied" on success.

### Tests
- New test for `TranscriptionPreflightService.venvDir()` /
  `venvPython()` agreement on the canonical layout — both must point
  at `~/Documents/GitHub/PhantomLives/transcribe/.venv` so the
  rebuild-venv path doesn't accidentally `rm -rf` the wrong directory.
  **85/85 pass.**

## [1.0.264] — 2026-05-14

### Fixed
- **Transcription silently failing after a reboot.** Root cause: when
  MessagesExporterGUI.app is launched from Finder / LaunchServices, the
  child processes inherit a minimal `PATH` (`/usr/bin:/bin:/usr/sbin:
  /sbin`) that omits `/opt/homebrew/bin` and `/usr/local/bin`. Inside
  the transcription chain, transcribe.py calls
  `subprocess.run(["brew", "install", "ffmpeg"])` to self-heal a
  missing ffmpeg — but `brew` itself isn't findable either, so the
  bootstrap dies in `_execute_child` with `FileNotFoundError`, leaving
  the .venv created but `mlx-whisper` never installed. Subsequent runs
  reuse the broken venv. Fix: `ExportRunner` now prepends
  `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`,
  `/usr/local/sbin` to the child `PATH` before spawning the CLI — and
  uses the same augmented PATH for all preflight probes so a green
  preflight predicts a green run.
- **"Done" pill claiming success when transcription failed.** The CLI
  intentionally catches per-attachment transcription errors and
  continues (the export itself succeeds; you still get message bodies
  and attachment copies). The GUI now parses `TRANSCRIBE_FAILED`
  markers and the bootstrap-traceback shape out of the CLI stream,
  bumps a counter, and surfaces a yellow `Last run reported a problem`
  banner after the run instead of pretending everything is fine. The
  banner offers a one-click `Run preflight` chip when the failure
  looks like a dependency issue.
- **Header chips compressing on small windows.** "Save preset",
  "Reveal output" and the theme chip could vanish at the minimum
  window height because `LiveOutputCard.frame(maxHeight: .infinity)`
  greedily reclaimed space and SwiftUI compressed the header to make
  room. Added `.fixedSize(horizontal: false, vertical: true)` plus
  `.layoutPriority(1)` to the header so it's the last row to give up
  space, not the first.

### Added
- **Settings → Transcription master switch (hard kill switch).** New
  `transcribeMasterEnabled` flag (default on, `AppStorage`-persisted).
  When off, the per-run **Transcribe** toggle is force-disabled with a
  caption pointing back to Settings, `--transcribe` never reaches the
  CLI, and the launch-time preflight is skipped entirely. Flip this
  off if you never need audio/video transcripts and don't want the
  setup-wizard prompts.
- **TranscriptionPreflightService** with launch-time + on-demand
  probing. Five named steps:
  1. transcribe.py is reachable
  2. Python 3.10+ is installed
  3. ffmpeg is on PATH
  4. Transcribe venv exists
  5. mlx-whisper imports cleanly
  Each step has a Retry button. A `Set up transcription` action runs
  `brew install ffmpeg` (when missing) and `pip install mlx-whisper`
  inside the venv, streaming pip output into a live log pane. The
  sheet auto-opens on launch when any check fails (and only then —
  healthy systems never see it); reachable any time from Settings →
  Transcription → Run preflight.
- **Prominent Reveal-in-Finder button next to Run / Cancel.** Always
  visible regardless of header chip layout; targets the run folder
  after a successful run, falls back to the configured output dir
  otherwise.

### Tests
- 17 new unit tests covering `ExportRunner.augmentedPATH` (homebrew
  injection, ordering vs CommandLineTools Python, idempotency, nil
  input), `TRANSCRIBE_FAILED` / bootstrap-traceback line classifiers,
  per-line counter bumping, `versionMeets` (3.10+ acceptance, 3.9
  rejection, pre-release tolerance), preflight script-candidate
  discovery, and master kill-switch flag propagation. **84/84 pass.**

## [1.0.263] — 2026-05-13

### Fixed
- **Window resize "broken" — actually a too-aggressive minimum on a
  small screen.** The "Known limitations" note in 1.0.262 was wrong:
  resize was always working, but the 920×640 floor was so close to a
  1280×800 laptop's usable area (after menu bar + dock) that the
  practical drag range was a few pixels — visually indistinguishable
  from "won't resize". User identified the root cause in retrospect.
  Floor adjusted by hand to **910×632** — meaningful shrink headroom
  on small laptops while keeping the four stat tiles + form card
  legible. The six fix attempts in 1.0.262 (windowResizability,
  hiddenTitleBar removal, frame variants, NSWindow styleMask bridge,
  root-view restructure, NavigationSplitView refactor) were all
  addressing the wrong question.

### Removed
- The "Window resize is partial" Known-limitation note from the
  1.0.262 CHANGELOG entry is retracted — see Fixed above.

## [1.0.262] — 2026-05-13

### Changed
- **Dropped `.windowStyle(.hiddenTitleBar)`.** That style was leaving
  the macOS traffic lights overlaid on top of the sidebar's first
  items ("Overview", "New export" sitting under the red/yellow/green
  buttons) and producing edge-resize cursor flicker. The regular
  title bar costs ~28pt of top chrome but the layout is clean and the
  traffic-light overlap problems are gone.
- **Sidebar + main pane top padding → 32pt.** Pre-fix the title-bar
  blur zone clipped the kicker / "Overview" item; 32pt gives content
  visible space below the chrome.
- **Root view restructure** from `ZStack { gradient + HStack }` to
  `HStack.background(gradient.ignoresSafeArea())`. Safe-area
  composition is unambiguous in the new form — the old ZStack had
  the gradient and content fighting over the title-bar inset.

### Added
- **`build-app.sh` stale-copy hardening.** Previously, iCloud File
  Provider would spawn `MessagesExporterGUI 2.app` /
  `…3.app` /…`N.app` shadow copies of the freshly-built bundle on
  every rebuild (because the project lives under `~/Documents/`,
  which iCloud Drive syncs). The duplicates accumulated stale
  cdhashes that polluted **System Settings → Privacy & Security →
  Full Disk Access** and occasionally hijacked `open
  MessagesExporterGUI.app` so subsequent test runs were launching a
  phantom, not the fresh build. The script now:
    - Wipes any `MessagesExporterGUI N.app` siblings **before** the
      build (was: only after), closing the brief window between
      `ditto` and `open`.
    - Sets `com.apple.fileprovider.ignore=1` on the freshly-built
      `.app` so iCloud treats it as local-only and stops generating
      duplicates upstream.
    - Strips `com.apple.fileprovider.fpfs#P` and
      `com.apple.FinderInfo` so the next iCloud sync round has
      nothing to reconcile.
    - Calls `lsregister -f` to force Launch Services to re-register
      *this* bundle's cdhash, clearing any stale phantom mapping in
      its database.

### Known limitations
- **Window resize is partial.** Edge-drag and corner-drag are
  inconsistent. Tried six approaches (`windowResizability`,
  `windowStyle` removal, frame variants, `NSWindow.styleMask`
  AppKit bridge, root-view restructure, decorative-surface
  `.allowsHitTesting(false)`, full `NavigationSplitView` refactor)
  — none gave free resize. Likely something specific to the custom
  HStack-sidebar layout's hit-testing on this macOS build; needs an
  Accessibility-Inspector comparison against PurpleIRC (which uses
  `NavigationSplitView` and resizes fine in the same monorepo). Left
  as a deferred follow-up rather than churning further.

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
