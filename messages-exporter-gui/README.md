# messages-exporter-gui

Native macOS SwiftUI front end for the [`messages-exporter`](../messages-exporter/) CLI. The 1.0.13 *Mission Control* redesign adopts a sidebar + main pane layout with a tinted gradient background, frosted-glass surfaces, and an oklch-derived blue accent. The main pane provides a **sender combobox** that enumerates conversation partners directly from `chat.db` (with display names cross-referenced from the AddressBook source files — no `Contacts.framework`, no extra TCC prompt), native date/time pickers with seconds precision, a four-tile run summary (Messages · Attachments · Span · Output size), a **Sanitized | Raw (forensic)** mode picker, an opt-in **Whisper transcription** of audio/video attachments via the sibling [`transcribe`](../transcribe/) project, a Full Disk Access preflight that detects missing permission on launch and offers to clean up stale TCC entries, and one-click chip buttons to open the resulting transcript / summary / manifest / metadata / chain-of-custody log or reveal the output folder.

## Quick start

```bash
# 1. Install the underlying CLI (the GUI shells out to it)
cd ../messages-exporter
./install.sh

# 2. Build the .app
cd ../messages-exporter-gui
./build-app.sh
open MessagesExporterGUI.app
```

If you skip step 1, the app will offer to run `install.sh` for you on first export.

See [INSTALL.md](INSTALL.md) for the full install / Full Disk Access walk-through and [USER_MANUAL.md](USER_MANUAL.md) for the day-to-day workflow.

## Requirements

- macOS 14 (Sonoma) or later
- **Full Disk Access** for `MessagesExporterGUI.app` itself (System Settings → Privacy & Security → Full Disk Access). The CLI reads `~/Library/Messages/chat.db`, which is sandboxed; child processes inherit the parent's TCC entitlements, so granting FDA to a Terminal that previously ran the CLI does not transfer.

## Defaults

- **Output folder**: `~/Downloads/messages-exporter-gui/` (each run creates `<contact>_<YYYYMMDD_HHMMSS>/` inside). Created on demand if it doesn't exist. Change in **Messages Exporter → Settings… → Default output folder**.
- **Start date/time**: today, 00:00:00 local
- **End date/time**: today, current local time (seconds default to `:59` of the picked minute)
- **Range precision**: `HH:MM` picker + a `SS` seconds field next to it. Defaults are `:00` on the From side and `:59` on the To side so a minute-precision range covers the full minute. The form's **Resolved** caption shows the exact bounds about to be sent to the CLI.
- **Expand start by 60 seconds**: on. Messages.app's swipe-to-reveal time rounds to the displayed minute, so a message stored at `10:11:45` can show as "10:12". With this on, the resolved start is pulled one full minute earlier than the picker — over-inclusive but safe for forensic ranges. Toggle in **Messages Exporter → Settings… → Range precision**.
- **Mode**: `Sanitized` (HEIC→JPG, EXIF stripped, caption-derived filenames). Switch to `Raw (forensic)` for byte-identical attachment copies, original filenames, sha256 + EXIF in `metadata.json`, and an append-only `chain_of_custody.log`. Emoji handling is ignored in raw mode.
- **Transcribe**: off. When on, audio/video attachments are run through the local Whisper model (default `turbo`, configurable in **Messages Exporter → Settings…**). Sidecars `<attachment>.transcript.json` and `<attachment>.transcript.txt` land next to each AV file; raw-mode sidecars are hashed and logged. **Master kill switch** at **Settings → Transcription → Enable transcription** — flip it off if you never need transcripts. **Launch-time preflight** probes the dependency chain (transcribe.py, Python 3.10+, ffmpeg, venv, mlx-whisper) and auto-opens a setup wizard on failure with one-click `brew install ffmpeg` + `pip install mlx-whisper`. Per-run failures surface in a yellow "Last run reported a problem" banner instead of hiding inside the live-output pane. `/opt/homebrew/bin` is auto-prepended to the child `PATH` so Finder-launched runs find `brew`/`ffmpeg` the same way Terminal-launched ones do.
- **Emoji handling**: `word` (e.g., 🔥 → `(fire)` in filenames). Configured in **Messages Exporter → Settings… → Emoji handling**.

## Build / test

```bash
./build-app.sh        # produces MessagesExporterGUI.app
./run-tests.sh        # runs the Swift Testing suite
```

`build-app.sh` derives the version from git: `CFBundleShortVersionString = 1.0.<outer-repo-commit-count>`, `CFBundleVersion = <count>.<sha>`. Override with `SHORT_VERSION=` / `BUILD_NUMBER=` env vars.

The `1.0.<count>` short version is the canonical release identifier — every CHANGELOG entry (from 1.0.203 onwards) uses the same number that `build-app.sh` stamps into the bundle, so a user reporting "I'm on 1.0.207" maps directly to a CHANGELOG entry. Pre-2026-05-11 entries (1.0.0–1.0.14) used a separate sequential scheme; see CHANGELOG for the transition note.

## Architecture

The GUI is a thin wrapper: it formats arguments, spawns `~/.local/bin/export_messages`, and parses the CLI's well-known `[N/5]` progress markers to drive a progress bar. The CLI remains the single source of truth for AddressBook lookup, chat.db reads, and attachment sanitization.

```
Sources/MessagesExporterGUI/
├── App.swift                    @main, WindowGroup + Settings, hidden title bar,
│                                launch-time auto-backup
├── RootView.swift               Sidebar+main layout, FormCard, FDA banner+sheet,
│                                Install sheet, SettingsView (Appearance,
│                                Range precision, Output, Emoji, Whisper,
│                                Diagnostics, Backup)
├── Theme/
│   └── MissionTheme.swift       Light/dark color tokens, typography helpers,
│                                GlassCard surface, ThemePreference
├── Model/
│   ├── ExportRequest.swift      Argv builder + Codable enums + RangeResolver
│   ├── ExportRunner.swift       Process spawn + stdout streaming, history sink
│   └── RunStats.swift           Mid-stream + post-run stat parsing
├── Services/
│   ├── AppSupport.swift         ~/Library/Application Support paths,
│   │                            short relative-time formatter
│   ├── SendersService.swift     chat.db enumeration → [Sender] (handle,
│   │                            service, count, last-message date)
│   ├── AddressBookLookup.swift  abcddb walk → [normalized-handle: name]
│   ├── RunHistoryStore.swift    JSON-backed run history (max 50 entries)
│   ├── PresetStore.swift        JSON-backed named presets
│   └── BackupService.swift      Launch-time auto-backup, retention, restore
└── Views/
    ├── Sidebar.swift            Recent runs + Saved presets + FDA pill
    ├── SenderCombobox.swift     Contact-row combobox over SendersService +
    │                            AddressBookLookup, picks an exact --handle
    ├── StatTiles.swift          Messages / Attachments / Span / Output size
    ├── RunStrip.swift           Blue gradient run+progress strip
    ├── LiveOutputCard.swift     Stdout card + ChipButton + FlowChips
    ├── SavePresetSheet.swift    Name + summary, persisted to PresetStore
    └── BackupSettingsView.swift Toggle / path / retention / run-now / list
```

See [HANDOFF.md](HANDOFF.md) for a deeper architecture snapshot.

## Troubleshooting

**FDA sheet on launch / "Full Disk Access required" banner** — the GUI checks `~/Library/Messages/chat.db` on every launch and surfaces this sheet when it can't read the file. Click **Open Privacy Settings**, drag the `.app` into the Full Disk Access list, then **Quit** and relaunch (TCC permission changes don't apply to a running process).

**Duplicate "MessagesExporterGUI" / "MessagesExporterGUI 2" entries in System Settings** — ad-hoc rebuilds rotate the app's `cdhash`, so old TCC entries no longer match the live binary. Use the FDA sheet's **Reset Privacy entries** button (or `tccutil reset SystemPolicyAllFiles com.bronty13.MessagesExporterGUI` from a terminal) to wipe them in one shot, then re-grant.

**Export finishes with "Full Disk Access denied"** — same root cause; the runtime check now also flips the persistent banner on. Re-grant FDA and relaunch.

**Export finishes with "no output folder"** — the contact name didn't match anyone in AddressBook, or no messages exist in the selected date range. Try widening the range or simplifying the name.

**App launches but Run does nothing** — check the log pane. If it says `export_messages CLI is not installed`, click Run again to trigger the install sheet, or run `messages-exporter/install.sh` manually.

## License

MIT
