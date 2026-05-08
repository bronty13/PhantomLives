# messages-exporter-gui

**Current release: 1.0.14**

Native macOS SwiftUI front end for the [`messages-exporter`](../messages-exporter/) CLI. The 1.0.13 *Mission Control* redesign adopts a sidebar + main pane layout with a tinted gradient background, frosted-glass surfaces, and an oklch-derived blue accent. The main pane provides a contact text field, native date/time pickers, a four-tile run summary (Messages · Attachments · Span · Output size), a **Sanitized | Raw (forensic)** mode picker, an opt-in **Whisper transcription** of audio/video attachments via the sibling [`transcribe`](../transcribe/) project, a Full Disk Access preflight that detects missing permission on launch and offers to clean up stale TCC entries, and one-click chip buttons to open the resulting transcript / summary / manifest / metadata / chain-of-custody log or reveal the output folder.

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
- **Start date/time**: today, 00:00 local
- **End date/time**: today, current local time
- **Mode**: `Sanitized` (HEIC→JPG, EXIF stripped, caption-derived filenames). Switch to `Raw (forensic)` for byte-identical attachment copies, original filenames, sha256 + EXIF in `metadata.json`, and an append-only `chain_of_custody.log`. Emoji handling is ignored in raw mode.
- **Transcribe**: off. When on, audio/video attachments are run through the local Whisper model (default `turbo`, configurable in **Messages Exporter → Settings…**). Sidecars `<attachment>.transcript.json` and `<attachment>.transcript.txt` land next to each AV file; raw-mode sidecars are hashed and logged.
- **Emoji handling**: `word` (e.g., 🔥 → `(fire)` in filenames). Configured in **Messages Exporter → Settings… → Emoji handling**.

## Build / test

```bash
./build-app.sh        # produces MessagesExporterGUI.app
./run-tests.sh        # runs the Swift Testing suite
```

`build-app.sh` derives the version from git: `CFBundleShortVersionString = 1.0.<commit-count>`, `CFBundleVersion = <count>.<sha>`. Override with `SHORT_VERSION=` / `BUILD_NUMBER=` env vars.

## Architecture

The GUI is a thin wrapper: it formats arguments, spawns `~/.local/bin/export_messages`, and parses the CLI's well-known `[N/5]` progress markers to drive a progress bar. The CLI remains the single source of truth for AddressBook lookup, chat.db reads, and attachment sanitization.

```
Sources/MessagesExporterGUI/
├── App.swift                    @main, WindowGroup + Settings, hidden title bar,
│                                launch-time auto-backup
├── RootView.swift               Sidebar+main layout, FormCard, FDA banner+sheet,
│                                Install sheet, SettingsView (Appearance,
│                                Output, Emoji, Whisper, Diagnostics, Backup)
├── Theme/
│   └── MissionTheme.swift       Light/dark color tokens, typography helpers,
│                                GlassCard surface, ThemePreference
├── Model/
│   ├── ExportRequest.swift      Argv builder + Codable enums
│   ├── ExportRunner.swift       Process spawn + stdout streaming, history sink
│   └── RunStats.swift           Mid-stream + post-run stat parsing
├── Services/
│   ├── AppSupport.swift         ~/Library/Application Support paths,
│   │                            short relative-time formatter
│   ├── RunHistoryStore.swift    JSON-backed run history (max 50 entries)
│   ├── PresetStore.swift        JSON-backed named presets
│   └── BackupService.swift      Launch-time auto-backup, retention, restore
└── Views/
    ├── Sidebar.swift            Recent runs + Saved presets + FDA pill
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
