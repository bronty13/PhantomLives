# messages-exporter-gui — User Manual

Day-to-day reference for the SwiftUI front end. For first-time setup see [INSTALL.md](INSTALL.md).

## The main window

The Mission Control redesign (1.0.13+) splits the window into a frosted-glass sidebar and a main pane. The sidebar carries navigation slots (Overview, **New export** — the only currently active destination, Recent runs · *Soon*, Saved presets · *Soon*) and an FDA status pill at the bottom. The main pane runs top-to-bottom: kicker → contact-name h1 → chip buttons → four stat tiles → form card → run strip → live-output card.

```
┌──────────────────┬────────────────────────────────────────────────────────────┐
│ ◾ Overview       │  NEW EXPORT                  [☆ Save preset] [📁 Reveal]   │
│ 📝 New export ●  │  Sallie                                                     │
│ 🕒 Recent  Soon  │  ┌──────────┬──────────────┬──────────┬──────────────────┐ │
│ ★  Presets Soon  │  │ MESSAGES │ ATTACHMENTS  │ SPAN     │ OUTPUT SIZE      │ │
│                  │  │ 4,812    │ 1,206        │ 16d      │ 2.4 GB           │ │
│ Recent           │  │ in range │ 912 photos…  │ Apr 26→  │ on disk          │ │
│ (placeholder)    │  └──────────┴──────────────┴──────────┴──────────────────┘ │
│                  │  ┌──────────────────────────────────────────────────────┐ │
│                  │  │ CONTACT   ┃ [SW] Sallie                  match…      │ │
│                  │  │ FROM      ┃ 2026-04-26 · 00:00                       │ │
│                  │  │ TO        ┃ 2026-05-08 · 14:22                       │ │
│                  │  │ MODE      ┃ [Sanitized] [Raw (forensic)]             │ │
│                  │  │ TRANSCRIBE┃ ☑ Audio & video                  turbo   │ │
│                  │  └──────────────────────────────────────────────────────┘ │
│                  │  ┌──────────────────────────────────────────────────────┐ │
│                  │  │ ▶ Run export ⌘⏎    Stage 0 of 5 · Ready    ░░░░░░░░  │ │
│                  │  └──────────────────────────────────────────────────────┘ │
│                  │  ┌──────────────────────────────────────────────────────┐ │
│                  │  │ ● Live output                  [Copy] [Open log]      │ │
│                  │  │ $ ~/.local/bin/export_messages Sallie --start ...     │ │
│                  │  │ [1/5] Handles for "Sallie"...                         │ │
│                  │  │ ...                                                    │ │
│                  │  │ [📁 Reveal] [📄 Transcript] [📄 Summary] [{} Manifest] │ │
│                  │  └──────────────────────────────────────────────────────┘ │
│ FDA · granted    │                                              v1.0.<count>  │
└──────────────────┴────────────────────────────────────────────────────────────┘
```

## Sidebar

The left sidebar carries three slots:

- **Recent runs** — every successful or failed export is recorded automatically. The five most recent show here with a status dot (green = success, amber = failed/cancelled), the contact-and-span title, and a relative timestamp. **Click a row to apply** that run's contact + range + Mode + Transcribe + Emoji to the form — useful for "do that same export again with a wider date range." Stored at `~/Library/Application Support/MessagesExporterGUI/runs.json` (50-entry rolling cap).
- **Saved presets** — named configurations you save with the **☆ Save preset** chip in the header. Click a preset to apply, right-click to delete. Stored at `~/Library/Application Support/MessagesExporterGUI/presets.json`.
- **FDA pill** at the bottom: green when Full Disk Access is granted, amber + click-to-resolve when denied.

## Inputs

### Output folder

- Defaults to `~/Downloads/messages-exporter-gui/` (created on demand).
- Configure it under **Messages Exporter → Settings… → Default output folder** (⌘,).
- **Choose…** opens a folder picker; pick any directory you have write access to.
- **Reset to Downloads** restores `~/Downloads/messages-exporter-gui/`.
- The path persists across launches (stored in user defaults).
- Each export creates a `<Contact>_<YYYYMMDD_HHMMSS>/` subfolder inside the chosen path — the path itself is the *parent* of every run.
- The header's **Reveal output** chip opens the most recent run folder, or falls back to the parent if no run has finished yet.

### Stat tiles

Below the contact-name heading is a four-tile strip that summarises the active or most-recent run:

- **Messages** — populated mid-run from `[3/5] N messages in range`, refined post-run from `metadata.json`.
- **Attachments** — populated post-run; secondary line shows photo / video / voice breakdown when available.
- **Span** — derived from your **From** / **To** dates; updates live as you change them.
- **Output size** — computed post-run by walking the run folder. Tinted with the accent color since it's the most useful "did the export work" tile.

Tiles render an em-dash (`—`) for any value that hasn't been measured yet — they don't fall back to zero, which would be ambiguous (zero is a valid result of a real export).

### Contact

The contact row is a combobox with two ways in:

- **Browse senders** (the chevron, or just clicking the field) — opens a dropdown of every 1:1 conversation partner enumerated directly from `~/Library/Messages/chat.db`, ranked most-recent-first. Each row shows the resolved display name (cross-referenced from AddressBook), the raw handle (phone/email), the service badge (iMessage/SMS), the total message count, and the last-message date. Click a row to lock that **exact** handle for the export — a small **via --handle** chip appears in the field to indicate the CLI will skip its AddressBook fuzzy match. This is the forensic-cleanest path: no name-collision risk, no missed match.
- **Type free-form** — start typing anything to filter the dropdown by name *or* handle (a partial phone number like `555 1234` works). Typing also clears any previously-locked handle. If you leave the field with no row picked, the typed string is sent as the legacy positional `contact` argument; the CLI does its own AddressBook substring match.

The picker reads chat.db under the same Full Disk Access grant the export already requires, so there is **no extra permission prompt**. If chat.db is missing or unreadable, a small amber diagnostic appears below the field and the typing fallback still works.

**Group chats** are excluded from v1 — only 1:1 senders appear in the dropdown. Group exports still work if you type a group display name (legacy fallback).

### Date range

- Both pickers show date and time (HH:MM) in your local timezone, with a small **seconds** field + stepper to the right of each for sub-minute precision. Defaults: **From** = today 00:00:00; **To** = today, current time with seconds defaulting to `:59` of the picked minute so a minute-precision range covers the whole minute.
- A monospaced **Resolved** caption below the date row shows the exact bounds that will be sent to the CLI (with seconds). Always check this before a forensic export — it's the truth, not the picker.
- **Messages.app rounds its swipe-to-reveal time** to the displayed minute, so a message stored at `10:11:45` can appear as "10:12". If you pick that displayed minute as your start, the actual `message.date` falls before the bound and the message is skipped. The default **Range precision → Expand start by 60 seconds** setting handles this by pulling the resolved start one full minute earlier than your picker — over-inclusive but safe. Turn it off in **Settings → Range precision** when you want the picker treated as strict.
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
- **Failures are non-fatal — and now visible.** If `ffmpeg` can't decode a file, the venv is broken, or any other error occurs, the transcription is skipped *and* the GUI flips a yellow "Last run reported a problem" banner with a one-click **Run preflight** action. The CLI still records the per-attachment error in `metadata.json` / `chain_of_custody.log` (raw) or `manifest.json` (sanitized), and the rest of the export continues.
- **Hashes** of both sidecar files (md5/sha1/sha256) are recorded in **raw** mode for forensic verification.

**Master kill switch.** If you don't need transcription at all, flip **Settings → Transcription → Enable transcription** off. The per-run **Transcribe** toggle becomes disabled, exports never pass `--transcribe`, and the launch-time preflight is skipped.

#### Launch-time preflight

When the master switch is on, the app probes the transcription dependency chain at launch:

| Check                              | What it verifies |
| ---------------------------------- | ---------------- |
| transcribe.py is reachable         | The sibling `transcribe/transcribe.py` is present (or `TRANSCRIBE_SCRIPT` env var points at one). |
| Python 3.10+ is installed          | A 3.10-or-newer Python is on the augmented `PATH`. (CommandLineTools' 3.9 doesn't qualify.) |
| ffmpeg is on PATH                  | `/usr/bin/env ffmpeg -version` succeeds. The app prepends `/opt/homebrew/bin` and `/usr/local/bin` to the child PATH automatically, so a Homebrew install is enough — even when launched from Finder. |
| Transcribe venv exists             | `transcribe/.venv/bin/python` is present and Python 3.10+. |
| mlx-whisper imports cleanly        | `python -c "import mlx_whisper"` inside the venv succeeds. (The single most common breakage after a Python upgrade.) |

If any check fails, a **Transcription preflight** sheet opens automatically. Each row has a **Retry** button; a **Set up transcription** action runs `brew install ffmpeg` (when missing) and `pip install mlx-whisper` inside the venv with live progress. Re-run any time from **Settings → Transcription → Run preflight…**.

#### Why a reboot can break transcription

When `MessagesExporterGUI.app` is launched from Finder, the inherited `PATH` is just `/usr/bin:/bin:/usr/sbin:/sbin` — `/opt/homebrew/bin` is **missing**. Older builds (< 1.0.264) didn't augment the child PATH, so `transcribe.py`'s self-healing call to `brew install ffmpeg` failed with `FileNotFoundError` inside `subprocess._execute_child`, the venv bootstrap died half-done, and every subsequent run reused the broken `.venv`. As of 1.0.264 the GUI auto-prepends the Homebrew prefixes to the child PATH, so this class of failure no longer happens — but if you have a pre-existing broken `.venv` from an older build, the preflight's **Set up transcription** action will repair it.

Choose the Whisper model in **Messages Exporter → Settings… → Transcription** (⌘,):

| Model  | RAM    | Notes                                            |
| ------ | ------ | ------------------------------------------------ |
| tiny   | ~1 GB  | Fastest, lowest quality                          |
| base   | ~1 GB  | Fast, acceptable                                 |
| small  | ~2 GB  | Balanced                                         |
| medium | ~5 GB  | High quality                                     |
| large  | ~10 GB | Best quality, slowest                            |
| turbo  | ~6 GB  | Near-large quality, ~8× faster (**default**)     |

### Emoji handling

Configured under **Messages Exporter → Settings… → Emoji handling** (⌘,). Affects how emoji in message captions are rendered in the saved attachment filenames (Sanitized mode only):

| Mode  | 🔥 in caption becomes…           |
| ----- | -------------------------------- |
| Strip | nothing — emoji dropped          |
| Word  | `(fire)` — default               |
| Keep  | `🔥` — literal emoji in filename |

This only affects filenames, not the transcript or manifest. Ignored in Raw (forensic) mode — original filenames are preserved verbatim there.

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

## Backup

Per the PhantomLives convention, the app runs a **launch-time auto-backup** of the small JSON stores under `~/Library/Application Support/MessagesExporterGUI/` (run history + presets). This is *not* a backup of your exports — those already sit in `~/Downloads/` and are big.

- **Location**: `~/Downloads/MessagesExporterGUI backup/` (sibling of the regular output dir).
- **Filename**: `MessagesExporterGUI-YYYY-MM-DD-HHmmss.zip`.
- **Retention**: 14 days by default. `0` = keep forever. Trim only removes archives that match the `MessagesExporterGUI-` prefix; unrelated files in the folder are left alone.
- **Debounce**: a launch within 5 minutes of the previous successful backup is a no-op. Prevents debugging-session relaunches from filling the folder.
- **Failure mode**: NSLog only — the app must launch even if backup fails (volume unmounted, disk full, etc.).

Override any setting under **Messages Exporter → Settings… → Backup** (⌘,):

- **Auto-backup on launch** toggle (default on).
- **Backup folder** — Choose / Reset to default.
- **Retention** stepper — 0 to 365 days.
- **Run backup now** button — useful before risky operations.
- **Recent backups** list, with three actions per row:
  - **Test** — extracts the archive to a temp directory, counts files, validates `runs.json` / `presets.json` parse cleanly. Non-destructive.
  - **Restore** — replaces the current support directory contents with the unpacked archive. Always preceded by a safety pre-restore backup (so the running state is recoverable). Requires an app relaunch for the in-memory stores to reload.
  - **Reveal** — Finder.

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

- **Range precision → Expand start by 60 seconds** — on by default. Compensates for Messages.app's swipe-time display rounding so the first message of a forensic range isn't silently dropped. Turn off when you want the picker bounds treated as strict (e.g., reproducing a previously-run query exactly).
- **Default output folder** — same control as the inline picker, plus a "Reset to Downloads" shortcut that restores `~/Downloads/messages-exporter-gui/`.
- **Transcription** — **Enable transcription** master switch (default on), Whisper model picker, and a **Run preflight…** button that opens the dependency wizard on demand (see the Transcribe section above).
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

## Version

The bottom-right of the main window shows `v1.0.<count>`. The `<count>` is the outer PhantomLives commit count at build time, so every committed change gets a unique number — include it when reporting a bug. The same number labels the matching CHANGELOG entry (1.0.203 onwards). Pre-2026-05-11 releases used a separate sequential numbering (1.0.0 through 1.0.14); see CHANGELOG for the transition note.
