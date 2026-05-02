# messages-exporter-gui — User Manual

Day-to-day reference for the SwiftUI front end. For first-time setup see [INSTALL.md](INSTALL.md).

## The main window

```
┌─────────────────────────────────────────────────────────────────┐
│      Output │  📁 ~/Downloads/messages-exporter-gui  [Default]   │
│     Contact │  Sallie                                             │
│        From │  📅 2026-04-26  🕒 00:00                            │
│          To │  📅 2026-04-26  🕒 17:00                            │
│        Mode │  [Sanitized] [Raw (forensic)]                       │
│       Emoji │  [Strip] [Word] [Keep]                              │
│  Transcribe │  ☐ Audio / video → Whisper (turbo)                  │
│ ─────────────────────────────────────────────────────────────── │
│  ▶ Run export   ░░░░░░░░░░░░░░░░░░░  Stage 0/5 — Idle           │
│                                                                  │
│  Output                                          [Copy log]      │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ $ ~/.local/bin/export_messages Sallie --start ...           │ │
│  │ [1/5] Handles for "Sallie"...                               │ │
│  │ ...                                                          │ │
│  └─────────────────────────────────────────────────────────────┘ │
│  [📁 Reveal] [📄 Transcript] [📄 Summary] [{} Manifest]          │
│                                                       v1.0.83    │
└─────────────────────────────────────────────────────────────────┘
```

## Inputs

### Output folder

- Defaults to `~/Downloads/messages-exporter-gui/` (created on demand). The "Default" badge appears whenever the current path matches this default.
- **Choose…** opens a folder picker; pick any directory you have write access to.
- **Reset** appears when the path is non-default; restores `~/Downloads/messages-exporter-gui/`.
- The path persists across launches (stored in user defaults). The Settings scene (**Messages Exporter → Settings…** or ⌘,) shows the same value.
- Each export creates a `<Contact>_<YYYYMMDD_HHMMSS>/` subfolder inside the chosen path — the path itself is the *parent* of every run.

### Contact

- Type any part of a contact's name (first, last, full, nickname). The CLI matches the string against AddressBook itself — full-name matches are most reliable, but a unique substring works too.
- Misspellings or names with no AddressBook match cause the export to finish with no output folder; check the log if you don't see the post-run buttons.

### Date range

- Both pickers show date and time in your local timezone.
- Defaults: **From** = today 00:00; **To** = today, current time.
- The CLI accepts the range inclusively. To export everything from a date forward, set **To** to a far-future time.

### Mode

| Mode             | What you get                                                                                                                                                                                                                                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sanitized (default) | Existing pipeline. HEIC→JPG conversion, EXIF/GPS stripped, `.jpeg` normalized to `.jpg`, attachments named after the next text message (`[seq]_[caption].ext`), all media dropped into a single `attachments/` folder.                                                                                                  |
| Raw (forensic)   | Byte-identical attachment copies under their **original** filenames (prefixed with `[seq]_[YYYYMMDDTHHMMSS]_[sender]_` for chronological sort). Flat directory layout. Each message's body becomes `[seq]_[YYYYMMDDTHHMMSS]_[sender].txt`. The run folder additionally contains `metadata.json` (sha256 + extracted EXIF + filesystem timestamps per attachment) and `chain_of_custody.log` (append-only line per action). The Emoji control is greyed out — it has no effect in raw mode. |

### Transcribe

Off by default. When checked, every audio/video attachment is run through Apple-MLX Whisper (the sibling [`transcribe/`](../transcribe/) project) after it's copied. Two sidecar files are produced next to each AV attachment:

- `<attachment>.transcript.json` — full Whisper output: language, segments with start/end timestamps, word-level timestamps when enabled.
- `<attachment>.transcript.txt` — plain text, one segment per line. Synthesized locally from the JSON to avoid running Whisper twice.

Behavior:

- **Local only.** No servers, no Ollama, no internet. Apple Silicon Metal-accelerated.
- **First run is slow.** The very first time you transcribe with a given Whisper model, the `transcribe/` project bootstraps a `.venv` and downloads the model from HuggingFace (~150 MB for `tiny` up to ~3 GB for `large`). Subsequent runs reuse the cached model.
- **Failures are non-fatal.** If `ffmpeg` can't decode a file, the file is corrupt, or any other expected error occurs, the transcription is skipped, the per-attachment error is captured in `metadata.json` / `chain_of_custody.log` (raw) or `manifest.json` (sanitized), and the rest of the export continues.
- **Hashes** of both sidecar files (md5/sha1/sha256) are recorded in **raw** mode for forensic verification.

Choose the Whisper model in **Messages Exporter → Settings… → Whisper transcription** (⌘,):

| Model  | RAM    | Notes                                            |
| ------ | ------ | ------------------------------------------------ |
| tiny   | ~1 GB  | Fastest, lowest quality                          |
| base   | ~1 GB  | Fast, acceptable                                 |
| small  | ~2 GB  | Balanced                                         |
| medium | ~5 GB  | High quality                                     |
| large  | ~10 GB | Best quality, slowest                            |
| turbo  | ~6 GB  | Near-large quality, ~8× faster (**default**)     |

### Emoji handling

Affects how emoji in message captions are rendered in the saved attachment filenames (Sanitized mode only):

| Mode  | 🔥 in caption becomes…           |
| ----- | -------------------------------- |
| Strip | nothing — emoji dropped          |
| Word  | `(fire)` — default               |
| Keep  | `🔥` — literal emoji in filename |

This only affects filenames, not the transcript or manifest.

## Running an export

1. Press **Run export** (or ⌘↩).
2. The progress bar advances through five stages as the CLI emits `[N/5]` markers:
   1. Resolve contact (AddressBook lookup)
   2. Find chats (chat.db join)
   3. Read messages (selecting messages in range)
   4. Write attachments (copy + sanitize media)
   5. Done
3. The log pane streams stdout in real time. Drag-select to copy any portion, or click **Copy log** to grab everything in one shot.
4. To stop a run in progress, click **Cancel**. A confirmation sheet ("Cancel export?") appears — choose **Stop export** to send SIGTERM to the child process, or **Keep running** to dismiss. Any attachments already written to the output folder are preserved. The button shows "Cancelling…" while the process exits.
5. When the run finishes successfully, the action row beneath the log pane lights up:

   - **Reveal** — opens Finder selecting the run folder.
   - **Transcript** — opens `transcript.txt` in your default text app.
   - **Summary** — opens `summary.txt` (counts, range, version used).
   - **Manifest** — opens `manifest.json` (per-message structured export).
   - **Metadata** *(raw mode only)* — opens `metadata.json` (per-attachment sha256, EXIF, filesystem timestamps).
   - **Custody log** *(raw mode only)* — opens `chain_of_custody.log` (append-only action log with sha256 hashes).

   Each button is disabled if the corresponding file isn't in the run folder (e.g., `metadata.json` and `chain_of_custody.log` are only written in raw mode, so they stay disabled in sanitized mode).

## What lands in the run folder

### Sanitized mode

```
<output>/<Contact>_<YYYYMMDD_HHMMSS>/
├── attachments/
│   ├── 00001_<caption text>.jpg
│   ├── 00002_<caption text>_(fire).mov
│   └── ...
├── transcript.txt          chronological human-readable transcript
├── summary.txt             counts, range, sanitize tools used, version
└── manifest.json           per-message + per-attachment structured data
```

### Raw (forensic) mode

```
<output>/<Contact>_<YYYYMMDD_HHMMSS>_raw/
├── 00001_20260426T155500_Me.txt                    body of message 1 (if any)
├── 00001_20260426T155500_Me_IMG_5523.HEIC          attachment, byte-identical
├── 00002_20260426T155510_+15551234567_video.MOV
├── 00002_20260426T155510_+15551234567.txt
├── ...
├── transcript.txt          chronological transcript with sha256 prefixes
├── manifest.json           compact per-message + saved-name + sha256
├── metadata.json           full per-attachment metadata (sha256, EXIF,
│                           filesystem timestamps, source path)
├── chain_of_custody.log    append-only line per action with sha256
└── summary.txt             counts, range, mode=raw (forensic), version
```

See `messages-exporter/README.md` for the full filename rules and sanitization details.

## Full Disk Access on launch

The app preflights `~/Library/Messages/chat.db` on every launch. If the file isn't readable you'll see a **"Full Disk Access required"** sheet before the main window is interactive. The sheet offers four actions:

- **Open Privacy Settings** — deep-links to System Settings → Privacy & Security → Full Disk Access. Drag `MessagesExporterGUI.app` into the list (or click +), toggle it on.
- **Reset Privacy entries** — runs `tccutil reset SystemPolicyAllFiles com.bronty13.MessagesExporterGUI` against the running user's TCC database. Use this when you see duplicate "MessagesExporterGUI" / "MessagesExporterGUI 2" entries in System Settings — common after several rebuilds, because each ad-hoc-signed rebuild rotates the `cdhash`. Reset wipes them all so the next grant produces a single clean entry.
- **Quit** — TCC pins the cdhash at process spawn, so a granted permission only takes effect on the *next* launch. Quit explicitly here, grant access, and relaunch.
- **Continue anyway** — dismiss the sheet without resolving. A persistent orange "Full Disk Access required" banner stays at the top of the window so you don't forget; clicking **Resolve…** on that banner re-opens the sheet.

If FDA is fine, none of the above appears — you go straight to the main form.

## Errors you might see

| Banner                                                             | Meaning                                                                                                                      |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| **Full Disk Access required** (orange banner)                      | Preflight detected `chat.db` is unreadable. Click **Resolve…** to re-open the sheet, or grant FDA in System Settings and relaunch. |
| **Full Disk Access denied. Open System Settings…**                 | An export attempt hit the FDA wall mid-run. Same fix as above — add `MessagesExporterGUI.app` in Privacy & Security and relaunch. |
| **Export finished with no output folder**                          | The contact didn't match anyone in AddressBook, or no messages fell in the date range. Try a shorter name or wider range.    |
| **export_messages CLI is not installed**                           | The pre-flight didn't find `~/.local/bin/export_messages`. Click **Run** again to trigger the install sheet.                 |
| **Could not locate messages-exporter/install.sh next to the app.** | The GUI looks for the install script either next to the `.app` or in `~/Documents/GitHub/PhantomLives/messages-exporter/`. Move the `.app` next to its sibling subproject, or run `install.sh` manually. |

## Settings scene

Open with **Messages Exporter → Settings…** (⌘,):

- **Default output folder** — same control as the inline picker, plus a "Reset to Downloads" shortcut that restores `~/Downloads/messages-exporter-gui/`.
- **Whisper transcription** — model picker for `--transcribe` runs (see the Transcribe section above).
- **Diagnostics → Debug Logging** — when on, passes `--debug` to the CLI. This enables full verbose output from the transcription subprocess: HuggingFace file-fetch progress bars, pip install lines, and Whisper model-load bars. Off by default. Enable when a transcription run silently fails or hangs and you need to see what the child process is doing.

Settings persist via `@AppStorage` (UserDefaults). Wipe with `defaults delete com.bronty13.MessagesExporterGUI`.

## Keyboard shortcuts

| Shortcut | Action                |
| -------- | --------------------- |
| ⌘↩      | Run export             |
| ⌘C       | Copy selection in the log pane (⌘A first to select all) |
| ⌘,       | Open Settings          |
| ⌘W       | Close window           |
| ⌘Q       | Quit                   |

## Where things live

- The `.app` lives wherever you built it (typically `PhantomLives/messages-exporter-gui/MessagesExporterGUI.app`).
- The CLI lives at `~/.local/bin/export_messages` (or `/usr/local/bin/` if installed with `--system`).
- The CLI's Python venv lives at `~/.venvs/messages-exporter/`.
- Exports default to `~/Downloads/messages-exporter-gui/` (configurable per the section above).
- User defaults live under bundle ID `com.bronty13.MessagesExporterGUI`.
