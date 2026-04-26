# messages-exporter-gui

**Current release: 1.0.5**

Native macOS SwiftUI front end for the [`messages-exporter`](../messages-exporter/) CLI. Provides a contact text field, native date/time pickers, a streamed copyable log of the export run, and one-click buttons to open the resulting transcript / summary / manifest or reveal the output folder.

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

- **Output folder**: `~/Downloads/` (each run creates `<contact>_<YYYYMMDD_HHMMSS>/` inside). Change inline in the main window or in **Messages Exporter → Settings…**.
- **Start date/time**: today, 00:00 local
- **End date/time**: today, current local time
- **Emoji handling**: `word` (e.g., 🔥 → `(fire)` in filenames)

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
├── App.swift                    @main, WindowGroup + Settings scene
├── RootView.swift               Form, run controls, settings, install sheet
├── Model/
│   ├── ExportRequest.swift      Argv builder
│   └── ExportRunner.swift       Process spawn + stdout streaming
└── Views/
    ├── ProgressBar.swift        5-stage indicator
    └── LogPane.swift            Scrolling stdout + Reveal/Transcript/Summary/Manifest buttons
```

See [HANDOFF.md](HANDOFF.md) for a deeper architecture snapshot.

## Troubleshooting

**Export finishes with "Full Disk Access denied"** — the GUI lacks FDA. Open System Settings → Privacy & Security → Full Disk Access, add `MessagesExporterGUI.app`, then quit and relaunch the app (TCC changes don't take effect for a running process).

**Export finishes with "no output folder"** — the contact name didn't match anyone in AddressBook, or no messages exist in the selected date range. Try widening the range or simplifying the name.

**App launches but Run does nothing** — check the log pane. If it says `export_messages CLI is not installed`, click Run again to trigger the install sheet, or run `messages-exporter/install.sh` manually.

## License

MIT
