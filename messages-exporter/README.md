# messages-exporter

**Current release: 1.7.1**

Export iMessage conversations from the Mac Messages app by contact name and
date range. Two output modes:

- **Sanitized** (default) — each photo/video/file lands in a single
  `attachments/` folder and is auto-renamed from the text message that
  follows it, so you can scan a folder like a storyboard. EXIF/GPS is
  stripped; HEIC is converted to JPG.
- **Raw / forensic** (`--raw`) — byte-identical copies of every attachment
  with original filenames, flat directory laid out in chronological sort
  order, **MD5 + SHA-1 + SHA-256** + extracted EXIF in `metadata.json`,
  and an append-only `chain_of_custody.log` recording every action with
  all three hashes per artifact.

## Quick Start

```bash
# One-time install (from the repo root)
cd messages-exporter
./install.sh                       # installs to ~/.local/bin, no sudo
# or:
./install.sh --system              # installs to /usr/local/bin (sudo)

# Grant Full Disk Access to your Terminal app, then:
export_messages "Jane Doe" --start "2026-04-01" --end "2026-04-30 23:59:59"
```

## Permanent archive mode (`archive_messages.py`)

`export_messages.py` is a **one-shot, per-contact** export. Its companion
`archive_messages.py` is the opposite: a **permanent, append-only archive of
EVERY conversation**, built to run **incrementally** (a big initial backfill,
then small repeated runs) so nothing is ever lost — even after the source device
deletes a thread.

```bash
archive_messages.py --db <chat.db> --archive <dir> \
                    [--addressbook-dir <Sources>] [--full]
```

- **All chats, not one contact** — enumerates every conversation in the `chat.db`.
- **Incremental + idempotent** — a `state.json` watermark on `message.date` plus
  GUID-dedup means re-runs append nothing. No watermark (or `--full`) ⇒ full backfill.
- **Source of truth (append-only, never rewritten):** `manifest.jsonl` (one JSON
  line per message GUID — the "nothing ever lost" record) + the raw
  `attachments/` byte-store (mirrored separately, e.g. `rsync` of
  `~/Library/Messages/Attachments/`).
- **Human-browsable views (regenerated from the manifest each run):**
  - `conversations/<Name>/transcript.txt` — readable, header + **contact names**.
  - `conversations/<Name>/index.html` — Messages-style bubbles + inline media.
  - `conversations/<Name>/media/` — that thread's media as **real copies**,
    date-prefixed (`YYYYMMDD_HHMMSS_origname`).
  - `_index.csv` — name / folder / #messages / date-range / #media.
  - `contacts.html` / `contacts.json` — **all** AddressBook fields per contact
    (name parts, org/title, birthday + dates, phones/emails/addresses/URLs/
    social/IM/related — each labelled, plus notes), exported **contact photos**
    (`contacts/photos/`), searchable, with a **"→ conversation"** link.
- **Contact names** via `--addressbook-dir` (a pulled AddressBook `Sources` dir):
  folders + senders become real names; unknown handles stay raw. **iMessage + SMS
  with the same person merge into one folder**; group chats stay separate.
- **Standard library only** — no Pillow/ffmpeg/exiftool; runs against a *pulled*
  `chat.db` snapshot on any Mac. (Reuses `export_messages`' `get_body`
  attributedBody decode + `mts`/`knd`/`san`/`slug`/`norm` by import.)

This is the engine for a **PurpleAttic-style pull archive**: snapshot a remote
Mac's `chat.db` (`sqlite3 .backup`) + `rsync` its `Attachments/` to a host, then
run `archive_messages.py` there — the Messages analogue of the photo archive.
Tested in `test_archive_messages.py`.

## Features

- **Contact lookup** — fuzzy match against AddressBook (phones + emails)
- **Local-time date filters** — `--start` / `--end` in your local timezone
- **Caption-based naming** — each media file is named `[seq]_[next message text].ext`
- **HEIC → JPG** — automatic conversion; `.jpeg` normalized to `.jpg`
- **Sanitization** — strips EXIF/GPS from images (exiftool/PIL) and metadata from
  videos (ffmpeg `-map_metadata -1 -c copy`, no re-encoding)
- **Emoji modes** — `strip`, `word` (🔥 → `(fire)`, default), or `keep` (literal)
- **Raw / forensic mode** (`--raw`) — flat directory, original filenames,
  byte-identical copies, MD5 + SHA-1 + SHA-256 + EXIF in
  `metadata.json`, and an append-only `chain_of_custody.log` with all
  three hashes per action
- **Optional Whisper transcription** (`--transcribe`) — post-processes
  audio/video attachments through the sibling `transcribe/` project
  (Apple-MLX Whisper, Metal-accelerated, fully local). Writes
  `<attachment>.transcript.json` + `<attachment>.transcript.txt`
  next to each AV attachment. Hashed and logged to
  `chain_of_custody.log` in raw mode. Failures don't stop the export.
- **Self-contained venv** — shebang points at the venv, so you just run the command
- **Graceful degradation** — missing dependencies are noted at startup and the
  best available fallback is used

## Requirements

Installed automatically by `install.sh`:

| Source  | Package                             | Purpose                           |
|---------|-------------------------------------|-----------------------------------|
| Homebrew| `exiftool`                          | Lossless image metadata stripping |
| Homebrew| `ffmpeg`                            | Lossless video metadata stripping |
| Pip     | `Pillow`                            | Image re-save, HEIC conversion    |
| Pip     | `pillow-heif`                       | HEIC → JPG via PIL                |
| Pip     | `emoji`                             | `(name)` filenames for emoji      |

You also need **Full Disk Access** for the terminal app you'll run the command
from, because `~/Library/Messages/chat.db` is sandboxed by macOS:

> System Settings → Privacy & Security → Full Disk Access → add your terminal
> app (Terminal.app, Warp, iTerm2, etc.), then quit and relaunch it.

## Usage

```
export_messages [<contact>] [--handle ID[,ID...]]
                [--start DATE] [--end DATE] [--output DIR]
                [--emoji {strip,word,keep}] [--raw]
                [--transcribe [--transcribe-model MODEL]]
                [--debug] [--version]
```

### Arguments

- `contact` — substring of a contact name (matched against first, last, full,
  and nickname in AddressBook). Optional when `--handle` is set; then used
  only as a label for the output folder and metadata.
- `--handle` — comma-separated chat.db handle ids (phone numbers or emails)
  to query directly, e.g. `--handle "+15551234567,alice@example.com"`. Skips
  AddressBook fuzzy matching — use this when you want the exact handle, no
  resolution step. Each value must match `chat.db.handle.id` verbatim;
  unknown ids are reported and skipped. Designed for the GUI's sender
  picker (which enumerates handles directly from chat.db) but works
  standalone too.
- `--start` / `--end` — `YYYY-MM-DD [HH:MM[:SS]]` in **local time**. Omit for
  open-ended range.
- `--output` — parent directory for the run folder (default: `messages_export`).
  The run folder is `<output>/<Contact>_<YYYYMMDD_HHMMSS>/`.
- `--emoji` — filename handling:
  - `strip` — drop emoji entirely
  - `word` — replace with `(name)`, e.g. 🔥 → `(fire)` **(default)**
  - `keep` — retain the emoji character in the filename
- `--raw` — forensic raw export. Flat directory, original filenames
  preserved (prefixed with `[seq]_[YYYYMMDDTHHMMSS]_[sender]_` for
  chronological sort), no HEIC→JPG, no EXIF strip. Writes
  `metadata.json` (per-attachment `hashes={md5,sha1,sha256}` +
  extracted EXIF + filesystem timestamps) and `chain_of_custody.log`
  (append-only line per action with all three hashes).
  `--emoji` is silently ignored when `--raw` is set.
- `--transcribe` — opt-in Whisper transcription of audio/video
  attachments via the sibling `transcribe/` subproject. Writes
  `<attachment>.transcript.json` (segments) and
  `<attachment>.transcript.txt` (segment text joined by newlines,
  synthesized locally from the JSON) next to each AV attachment.
  Runs out-of-process (sees `transcribe.py` via `TRANSCRIBE_SCRIPT`
  env override or the default
  `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py`).
  Failures are non-fatal — the export continues and a structured
  error message is recorded per-attachment.
- `--transcribe-model {tiny,base,small,medium,large,turbo}` —
  Whisper model (default `turbo`). `turbo` is near-large quality at
  ~8× throughput. Larger models give better quality at the cost of
  more RAM and time.
- `--debug` — verbose mode. Shows full tqdm/pip output from the
  transcription subprocess (HuggingFace file-fetch bars, model-load
  progress, pip "Requirement already satisfied" lines). Default: off —
  progress noise is suppressed via `TQDM_DISABLE=1` /
  `HF_HUB_DISABLE_PROGRESS_BARS=1` in the child environment.

### Examples

```bash
# Full April
export_messages "Jane" --start "2026-04-01" --end "2026-04-30 23:59:59"

# Specific time window
export_messages "Jane" \
  --start "2026-04-23 10:21:00" \
  --end   "2026-04-23 11:58:00" \
  --output ~/Downloads/messages_export

# Keep literal emoji in filenames
export_messages "Jane" --emoji keep --start "2026-04-01"

# Strip emoji entirely
export_messages "Jane" --emoji strip --start "2026-04-01"

# Forensic raw export (no sanitization, sha256 + EXIF metadata)
export_messages "Jane" --raw --start "2026-04-01" --end "2026-04-30 23:59:59"

# With Whisper transcription of audio/video attachments
export_messages "Jane" --raw --transcribe --start "2026-04-01"

# Larger Whisper model
export_messages "Jane" --transcribe --transcribe-model large --start "2026-04-01"
```

## Output layout — sanitized (default)

```
<output>/<Contact>_<YYYYMMDD_HHMMSS>/
├── attachments/
│   ├── 00001_[caption text].jpg
│   ├── 00002_[caption text]_(fire).mov       ← emoji in word mode
│   ├── 00003_[caption text]_2.jpg            ← _2 suffix on name collisions
│   └── ...
├── transcript.txt       Chronological human-readable transcript
├── manifest.json        Structured export (per-message, per-attachment)
└── summary.txt          Run statistics and settings used
```

## Output layout — raw / forensic (`--raw`)

```
<output>/<Contact>_<YYYYMMDD_HHMMSS>_raw/
├── 00001_20260426T155500_Me.txt              ← message body (when present)
├── 00001_20260426T155500_Me_IMG_5523.HEIC    ← attachment, byte-identical
├── 00002_20260426T155510_+15551234567_video.MOV
├── 00002_20260426T155510_+15551234567.txt
├── ...
├── transcript.txt          Human-readable chronological transcript with sha256 prefixes
├── manifest.json           Compact per-message + saved-name + sha256
├── metadata.json           Full per-attachment metadata: orig path, mime,
│                           size, hashes={md5,sha1,sha256}, fs timestamps,
│                           extracted EXIF
├── chain_of_custody.log    Append-only line per action (START, COPY,
│                           WRITE_BODY, MISSING_SOURCE, COPY_FAILED, END)
│                           with timestamps and md5+sha1+sha256 hashes
└── summary.txt             Run statistics
```

In raw mode every attachment is written byte-for-byte from the source —
no HEIC→JPG conversion, no EXIF/GPS strip, no extension normalization.
Filenames keep the original stem (prefixed for sort order). EXIF is
extracted as data into `metadata.json` rather than removed from the file.

Three hash algorithms (MD5, SHA-1, SHA-256) are computed in a single
streaming pass over each artifact and recorded both in `metadata.json`
(per-attachment under `hashes`, per-message body under `body_hashes`)
and in `chain_of_custody.log` (on the COPY and WRITE_BODY records).
SHA-256 is the modern integrity primitive; MD5 and SHA-1 are still
expected by older forensic tooling and historical chain-of-custody
reports.

## Whisper transcription (optional)

When `--transcribe` is set, every audio/video attachment is fed to
[`PhantomLives/transcribe/`](../transcribe/) — an Apple-MLX wrapper
around OpenAI Whisper that runs entirely on-device using Metal. **No
servers, no Ollama, no internet.** Pass `--transcribe-model large` if
you want higher quality at the cost of speed.

Two sidecar files land next to each AV attachment:

- `<attachment>.transcript.json` — full Whisper output (segments with
  start/end timestamps, language detection, etc.).
- `<attachment>.transcript.txt` — plain text, segment lines joined.
  Synthesized locally from the JSON to avoid running Whisper twice.

In raw mode both sidecars are hashed (md5/sha1/sha256). Each successful
transcription emits a `TRANSCRIBE` line in `chain_of_custody.log`
carrying both files' sizes, all three hashes, the model used, and the
wall-clock duration. Failures emit a `TRANSCRIBE_FAILED` line with the
mapped reason — the export keeps going.

First run for a given model auto-bootstraps the `transcribe/` project's
`.venv` and downloads the Whisper weights from HuggingFace (one-time,
~150 MB for `tiny` up to ~3 GB for `large`). Subsequent runs are fast.
Requires Apple Silicon and `ffmpeg` (the `transcribe/` installer
handles it).

### Filename rules

- Media files: `[seq]_[next message text].[ext]`
- Media with no following text message: `[seq]_NO_TEXT.[ext]`
- Non-media files keep their original stem: `[seq]_[original_name].[ext]`
- `[seq]` is the 1-based message index within the export
- On collision (multiple attachments in the same message), `_2`, `_3`, ... are appended

## Sanitize capabilities

The startup banner tells you which sanitize path is being used:

```
Version    : 1.0.0
Python     : /Users/you/.venvs/messages-exporter/bin/python3
Sanitize:
  HEIC->JPG  : PIL+pillow_heif       ← preferred; sips is the fallback
  Image EXIF : exiftool              ← preferred; PIL re-save is the fallback
  Video meta : ffmpeg                ← preferred
  Emoji lib  : installed
```

If any row reads `NONE`, the corresponding feature is skipped and the script
prints a `Missing: pip install ... ; brew install ...` hint so you know what
to install.

## Uninstall

```bash
./install.sh --uninstall
```

Removes the script from `~/.local/bin` (and `/usr/local/bin` if installed
there) and deletes the venv at `~/.venvs/messages-exporter`. Homebrew
packages are left in place — uninstall with `brew uninstall exiftool ffmpeg`
if you no longer want them.

## Tests

```bash
# Run from the messages-exporter/ directory
~/.venvs/messages-exporter/bin/python3 test_export_messages.py
```

The test suite covers pure-function behavior (slug modes, caption extraction
from synthetic `attributedBody` blobs, date parsing, phone normalization,
MIME/extension classification, filename collision dedup). It does not read
`chat.db` — integration testing against a live database requires Full Disk
Access and real conversation data.

## Troubleshooting

**`authorization denied` on chat.db** — your terminal app lacks Full Disk
Access. Grant it in System Settings and restart the terminal.

**`--emoji word` but no emoji words appear** — you're running the script via
a different Python that doesn't have the `emoji` package installed. The
script prints a large warning in this case; either run `export_messages`
directly (so the baked-in venv shebang is used) or install `emoji` into
whichever Python you're invoking.

**Some filenames end mid-word** — slugs are capped at 120 chars; long
captions plus long emoji names (`(face_with_hand_over_mouth)`) can hit the
limit. Raise the cap in `slug()` if you need longer.

**Attachment shows as MISSING in transcript** — the original file on disk
was deleted or moved outside of `~/Library/Messages/Attachments/`. chat.db
retains the reference but the blob is gone.

## License

MIT
