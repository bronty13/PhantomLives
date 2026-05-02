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
# messages-exporter 1.3.0
```

### Optional: Whisper transcription (`transcribe/` subproject)

The GUI's **Transcribe** checkbox is opt-in and shells out to the sibling [`transcribe/`](../transcribe/) project. Nothing extra to install up front — `transcribe.py` self-bootstraps the first time it runs (creates `.venv/`, installs `mlx-whisper` + `mlx-lm`, installs `ffmpeg` via Homebrew if missing, downloads the chosen Whisper model from HuggingFace). Apple Silicon required.

The CLI looks for the script at `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` by default; override with the `TRANSCRIBE_SCRIPT` env var if you keep it elsewhere. **No Ollama or other server is required** — Whisper runs in-process via Apple's MLX framework, locally and on-device.

## 2. Build the GUI

```bash
cd PhantomLives/messages-exporter-gui
./run-tests.sh               # 18 tests, ~5 seconds
./build-app.sh               # ~30 seconds first time; produces MessagesExporterGUI.app
open MessagesExporterGUI.app
```

`build-app.sh` derives the version from git (`CFBundleShortVersionString = 1.0.<commit-count>`). Override with `SHORT_VERSION=...` if you need a specific value.

### Code signing

`build-app.sh` signs the bundle with a **Developer ID Application** certificate when one is in the keychain (Hardened Runtime + trusted timestamp), and falls back to ad-hoc signing otherwise. The fallback works for fresh checkouts that don't have the maintainer's cert installed.

```bash
# Use the maintainer's cert (the script's default):
./build-app.sh

# Override with your own Developer ID:
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./build-app.sh

# Force ad-hoc (matches the legacy behavior; Privacy entries will rotate
# on every rebuild):
DEVELOPER_ID=- ./build-app.sh
```

Why it matters: with a real Developer ID signature, TCC keys Full Disk Access grants on `(team ID, bundle ID)` rather than the per-build cdhash, so rebuilds preserve the user's grant instead of accumulating duplicate "MessagesExporterGUI 2 / 3 / …" entries in System Settings. Ad-hoc rebuilds rotate the cdhash and require a re-grant each time.

## 3. Grant Full Disk Access (required)

The CLI reads `~/Library/Messages/chat.db`, which lives behind macOS's sandboxed Privacy framework. The GUI spawns the CLI as a child process, and **child processes inherit TCC (Privacy) entitlements from their parent**. So even if you've previously granted Full Disk Access to your Terminal, the GUI app itself needs it too.

The app preflights this on launch: if `chat.db` isn't readable, you'll see a sheet titled **"Full Disk Access required"** with one-click buttons to open the right Privacy pane and to reset stale entries (see below). You can also just follow these steps manually:

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Click **+** and pick `MessagesExporterGUI.app` (typically `PhantomLives/messages-exporter-gui/MessagesExporterGUI.app`).
3. Toggle the switch on.
4. **Quit and relaunch** the app — TCC permission changes don't apply to a running process.

If you skip this, exports fail with:

```
Full Disk Access denied. Open System Settings → Privacy & Security → Full Disk Access, add MessagesExporterGUI.app, then quit and relaunch it.
```

### Duplicate "MessagesExporterGUI" / "MessagesExporterGUI 2" entries

Because the `.app` is **ad-hoc code-signed**, every rebuild produces a fresh
code-signature hash (`cdhash`). TCC keys its grants on `(bundle ID, cdhash)`,
so a TCC entry created against last week's build no longer matches today's
binary — and macOS may add a new entry rather than reusing the old one. Over
many rebuilds this accumulates as multiple "MessagesExporterGUI" rows in the
Privacy list, often disambiguated as "MessagesExporterGUI 2", "… 3", etc.

The in-app FDA sheet has a **Reset Privacy entries** button that wipes them
all in one shot, so the next grant produces a single clean row. Or run the
equivalent from a terminal:

```bash
tccutil reset SystemPolicyAllFiles com.bronty13.MessagesExporterGUI
```

After the reset, quit the app, re-grant Full Disk Access in System Settings,
and relaunch.

`build-app.sh` also wipes any `MessagesExporterGUI 2.app` / `MessagesExporterGUI 3.app` Finder copies it finds in the project directory before each release build, which prevents the duplicates from accumulating in the first place.

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
defaults delete com.bronty13.MessagesExporterGUI 2>/dev/null || true
```

Then remove the Full Disk Access entry from System Settings if you want.
