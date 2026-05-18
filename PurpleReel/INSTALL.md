# Install & Setup — PurpleReel

This is the first-run + prerequisites + troubleshooting reference.
For the high-level feature tour see [`README.md`](README.md); for
the test plan see [`INTEGRATION_TEST_PLAN.md`](INTEGRATION_TEST_PLAN.md).

In-app: **Help → Install & Setup** opens this file.

---

## 1. System requirements

| Need | Version |
|---|---|
| macOS | **14.4 (Sonoma)** or newer |
| CPU | Apple Silicon recommended (hardware HEVC, MLX Whisper). Intel works, slower. |
| RAM | 8 GB minimum, 16+ GB for 4K transcode + AI |
| Disk | ~150 MB for the app; transcode + backup output goes to `~/Downloads/PurpleReel/` |
| Xcode | **16+** (only for building from source) |
| `xcodegen` | `brew install xcodegen` (only for building from source) |

---

## 2. Install

There are two paths. Pick whichever matches what you have.

### 2.a — From a built `.app` (recipient install)

1. Move `PurpleReel.app` into `/Applications/`. Drag-drop in Finder is
   fine; the app is Developer-ID signed, not sandboxed.
2. First launch will go through Gatekeeper — see §3 below.

### 2.b — From source (developer install)

```sh
cd PurpleReel/
./build-app.sh && ./install.sh
```

What each step does:

- **`build-app.sh`** — regenerates AppIcon assets, regenerates
  `SHORTCUTS.md` from `Sources/PurpleReel/Help/Shortcuts.swift`,
  regenerates the Xcode project via xcodegen, compiles Release,
  signs (Developer ID if a cert exists in your Keychain, ad-hoc
  fallback otherwise).
- **`install.sh`** — quits the running copy of PurpleReel, deletes
  `/Applications/PurpleReel.app`, ditto-copies the freshly built
  bundle in, relaunches. Using `/Applications/` (vs running directly
  from the source tree) keeps TCC permissions stable across rebuilds
  — see §3.b.

To skip the relaunch (e.g. for CI / scripted use):
```sh
./install.sh --no-open
```

---

## 3. First launch

### 3.a — Gatekeeper

If you got the `.app` over the network (rather than building it from
source on this Mac), macOS will quarantine it. On first launch you
may see:

> "PurpleReel" cannot be opened because the developer cannot be
> verified.

To bypass:

1. **Finder** → right-click `PurpleReel.app` → **Open**. (NOT
   double-click — that doesn't expose the bypass.)
2. Click **Open** in the dialog. macOS remembers the choice; future
   launches work normally.

Or via Terminal:
```sh
xattr -dr com.apple.quarantine /Applications/PurpleReel.app
```

### 3.b — TCC (Files & Folders) permission

The first time PurpleReel scans a folder outside `~/Movies` or
`~/Pictures`, macOS will prompt for **Files & Folders** access.
Click **OK**.

If the workspace root is `~/Documents`, `~/Desktop`, `~/Downloads`,
the prompt names the specific folder. If you click **Don't Allow**
by accident, fix it under:

**System Settings → Privacy & Security → Files and Folders → PurpleReel** → tick the folder(s).

For unrestricted access (every folder, including external drives
without a per-folder prompt), grant **Full Disk Access** instead:

**System Settings → Privacy & Security → Full Disk Access → +** →
add `/Applications/PurpleReel.app`.

> **Why we recommend `/Applications/`**: macOS TCC binds permission
> grants to the `(team ID, bundle ID, cdhash)` tuple. Running from
> the source tree means every rebuild rotates the cdhash and forces
> you to re-grant. `/Applications/` is stable across rebuilds; the
> `install.sh` flow uses `ditto --noextattr` so the bundle's hash
> stays valid.

### 3.c — Auto-backup on launch

PurpleReel runs an automatic backup of its catalog DB on every launch
(after a 5-min debounce). On the very first run you should see, in
`~/Downloads/PurpleReel backup/`:

```
PurpleReel-2026-05-17-160712.zip
```

Configure or disable in **Settings → Backup**. Retention defaults to
14 days; `0` = keep forever. See the test plan's Scenario 14 for the
full verify / restore round-trip.

---

## 4. Optional dependencies

Each one unlocks a specific feature; missing ones produce graceful
in-app errors with a pointer to this section.

### 4.a — `ffmpeg` (DNxHR / Cineform / MXF presets)

```sh
brew install ffmpeg
```

Required only for the Convert → DNxHR / Distribution presets.
PurpleReel auto-detects ffmpeg at:
- `/opt/homebrew/bin/ffmpeg` (Apple Silicon Homebrew default)
- `/usr/local/bin/ffmpeg` (Intel Homebrew default)
- `/usr/bin/ffmpeg` (Xcode CLT)

Verify:
```sh
which ffmpeg && ffmpeg -version | head -1
```

### 4.b — Whisper transcription

Requires the sibling `transcribe/` directory from the PhantomLives
monorepo (auto-bootstraps its own venv on first run).

```sh
# from PhantomLives root
cd transcribe
python3 transcribe.py --help    # triggers venv install
```

PurpleReel finds `transcribe.py` at `../transcribe/transcribe.py`
relative to its working directory by default. Override the script
path under **Settings → AI**.

Model choices: `turbo` (default — fastest), `large-v3` (highest
quality, slower).

### 4.c — Ollama (auto-describe LLM)

```sh
brew install ollama
ollama pull llama3.2:1b
```

Auto-describe sends a short prompt (filename + transcript snippet)
to a local LLM via the Ollama HTTP API at `localhost:11434`. The
default model is `llama3.2:1b`; override under **Settings → AI**.

### 4.d — `sshpass` (SFTP password auth)

Only needed if you deliver to an SFTP server that requires
password authentication. Key-based auth works without sshpass.

```sh
brew install hudochenkov/sshpass/sshpass
```

PurpleReel prefers an SSH key in Keychain; password is the fallback.

---

## 5. Troubleshooting

### "executable missing" on first launch from `/Applications/`

The `.app` bundle is structurally correct but `Contents/MacOS/PurpleReel`
is missing. Two causes:

- The build silently failed but `build-app.sh` reported success
  because `xcodebuild`'s stderr was filtered through grep. Re-run
  with full output:
  ```sh
  xcodebuild -project PurpleReel.xcodeproj -scheme PurpleReel \
      -configuration Release build 2>&1 | grep -E " error:"
  ```
- The bundle was copied between machines with iCloud File Provider
  on `~/Documents`, which can strip extended attributes. Always use
  `install.sh` (which uses `ditto --noextattr`) rather than `cp -r`.

### "Files & Folders" prompt never appears

macOS only prompts the first time a binary tries to access a
restricted location. If you clicked **Don't Allow** previously, the
prompt won't reappear — fix the entry under System Settings
manually (§3.b).

### Window opens too narrow / sidebar mis-sized

PurpleReel ships a `WindowStateGuard` preflight that wipes corrupted
saved window state on every launch. If it ever fails, use **Window →
Reset Window State…** in the menu bar. Restart to apply.

### Backup folder fills up / takes too much disk

Lower the retention in **Settings → Backup → Retention days**, or
change the path to an external volume. Verify a backup is sound
before lowering retention (Settings → Backup → Recent backups →
Test).

### "ffmpeg not found" when picking a DNxHR / Cineform preset

Install ffmpeg per §4.a. PurpleReel checks the three standard
Homebrew/CLT paths; if yours lives elsewhere, symlink it:
```sh
sudo ln -s /your/path/ffmpeg /usr/local/bin/ffmpeg
```

### Whisper transcription fails immediately

The `transcribe/` venv hasn't been bootstrapped yet. Run
`python3 transcribe.py --help` from `transcribe/` once to trigger
the install. If it still fails, check **Settings → AI → Whisper
script path** points at the real `transcribe.py`.

### Ollama "connection refused"

`ollama serve` isn't running. Install via `brew install ollama` and
enable as a launchd service:
```sh
brew services start ollama
```
Or launch ad-hoc: `ollama serve` in a Terminal window.

### `transcribe` / `Whisper` / `Ollama` work fine in CLI but fail in PurpleReel

PurpleReel inherits the user's PATH from `launchd`'s plist
environment, not from `~/.zshrc`. If your binaries live in
`/opt/homebrew/bin` (Apple Silicon Homebrew default), launchd
already has them. Otherwise either:
- Symlink into a launchd-visible path (`/usr/local/bin/`), or
- Set the explicit absolute path in **Settings → AI**.

### Reset everything (factory state)

```sh
osascript -e 'tell application "PurpleReel" to quit' 2>/dev/null
rm -rf ~/Library/Application\ Support/PurpleReel/
defaults delete com.bronty13.PurpleReel
```

Re-launches will run the v1 + v2 migrations from scratch. **Make a
backup first** (Settings → Backup → Run Backup Now).

---

## 6. Where things live

| What | Where |
|---|---|
| App bundle | `/Applications/PurpleReel.app/` |
| Catalog DB | `~/Library/Application Support/PurpleReel/purplereel.sqlite` |
| Settings | Same dir; plus `defaults` under `com.bronty13.PurpleReel` |
| Thumbnail cache | `~/Library/Application Support/PurpleReel/thumbnails/` |
| Default output (transcode) | `~/Downloads/PurpleReel/transcoded/` |
| FCPXML export | `~/Downloads/PurpleReel/exports/` |
| Auto-backups | `~/Downloads/PurpleReel backup/` |
| Whisper script | sibling `transcribe/transcribe.py` (overridable) |
| Crash logs | `~/Library/Logs/DiagnosticReports/PurpleReel-*` |
| NSLog output | Console.app — filter by process `PurpleReel` |

---

## 7. Uninstall

Quit PurpleReel, then:

```sh
rm -rf /Applications/PurpleReel.app
rm -rf ~/Library/Application\ Support/PurpleReel/
defaults delete com.bronty13.PurpleReel
```

Backups in `~/Downloads/PurpleReel backup/` and transcoded output in
`~/Downloads/PurpleReel/` are left alone — remove those manually if
you want a clean wipe.
