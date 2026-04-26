# Installing messages-exporter-gui

The GUI is a thin wrapper around the [`messages-exporter`](../messages-exporter/) CLI. Installing is three steps:

1. Install the CLI (so the GUI has something to call)
2. Build the `.app`
3. Grant **Full Disk Access** to the `.app`

If you skip step 1, the app will offer to run the CLI installer for you on the first export attempt — you can use that path instead and skip down to step 3.

## Prerequisites

- macOS 14 (Sonoma) or later — both the CLI installer and the SwiftUI app target macOS 14+.
- Apple Command Line Tools or full Xcode (`xcode-select --install` if missing).
- Homebrew, only required by the CLI installer (it pulls `exiftool` and `ffmpeg`).

## 1. Install the CLI

```bash
cd PhantomLives/messages-exporter
./install.sh                 # installs ~/.local/bin/export_messages and a venv at ~/.venvs/messages-exporter
```

`./install.sh --system` puts it in `/usr/local/bin` instead (requires sudo). Either location works for the GUI.

Verify:

```bash
~/.local/bin/export_messages --version
# messages-exporter 1.0.1
```

## 2. Build the GUI

```bash
cd PhantomLives/messages-exporter-gui
./run-tests.sh               # 7 tests, ~5 seconds
./build-app.sh               # ~30 seconds first time; produces MessagesExporterGUI.app
open MessagesExporterGUI.app
```

`build-app.sh` derives the version from git (`CFBundleShortVersionString = 1.0.<commit-count>`). Override with `SHORT_VERSION=...` if you need a specific value. The `.app` is ad-hoc signed so macOS will launch it without a dev cert.

## 3. Grant Full Disk Access (required)

The CLI reads `~/Library/Messages/chat.db`, which lives behind macOS's sandboxed Privacy framework. The GUI spawns the CLI as a child process, and **child processes inherit TCC (Privacy) entitlements from their parent**. So even if you've previously granted Full Disk Access to your Terminal, the GUI app itself needs it too.

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Click **+** and pick `MessagesExporterGUI.app` (typically `PhantomLives/messages-exporter-gui/MessagesExporterGUI.app`).
3. Toggle the switch on.
4. **Quit and relaunch** the app — TCC permission changes don't apply to a running process.

If you skip this, the first export will fail with:

```
Full Disk Access denied. Open System Settings → Privacy & Security → Full Disk Access, add MessagesExporterGUI.app, then quit and relaunch it.
```

## 4. (Optional) Grant Contacts permission

On first launch the app asks for Contacts access. This is purely for autocomplete in the contact field. Denying it doesn't break exports — the underlying CLI walks AddressBook on its own — you just don't get suggestions while typing.

## Updating

```bash
cd PhantomLives                      # outer repo
git pull
cd messages-exporter && ./install.sh # if the CLI changed
cd ../messages-exporter-gui
./build-app.sh                       # rebuild the .app
```

The GUI checks for the CLI on every export, so just rebuilding the app picks up any new CLI install.

## Uninstalling

```bash
# Remove the .app
rm -rf PhantomLives/messages-exporter-gui/MessagesExporterGUI.app

# Remove the CLI (and its venv)
PhantomLives/messages-exporter/install.sh --uninstall

# Forget the user defaults
defaults delete com.example.MessagesExporterGUI 2>/dev/null || true
```

Then remove the FDA / Contacts entries from System Settings if you want.
