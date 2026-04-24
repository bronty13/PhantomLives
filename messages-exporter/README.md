# messages-exporter

**Current release: 1.0.1**

Export iMessage conversations from the Mac Messages app by contact name and
date range. Each photo, video, and file lands in a single `attachments/`
folder and is auto-renamed from the text message that follows it, so you
can scan a folder like a storyboard.

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

## Features

- **Contact lookup** — fuzzy match against AddressBook (phones + emails)
- **Local-time date filters** — `--start` / `--end` in your local timezone
- **Caption-based naming** — each media file is named `[seq]_[next message text].ext`
- **HEIC → JPG** — automatic conversion; `.jpeg` normalized to `.jpg`
- **Sanitization** — strips EXIF/GPS from images (exiftool/PIL) and metadata from
  videos (ffmpeg `-map_metadata -1 -c copy`, no re-encoding)
- **Emoji modes** — `strip`, `word` (🔥 → `(fire)`, default), or `keep` (literal)
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
export_messages <contact> [--start DATE] [--end DATE] [--output DIR]
                          [--emoji {strip,word,keep}] [--version]
```

### Arguments

- `contact` — substring of a contact name (matched against first, last, full,
  and nickname in AddressBook)
- `--start` / `--end` — `YYYY-MM-DD [HH:MM[:SS]]` in **local time**. Omit for
  open-ended range.
- `--output` — parent directory for the run folder (default: `messages_export`).
  The run folder is `<output>/<Contact>_<YYYYMMDD_HHMMSS>/`.
- `--emoji` — filename handling:
  - `strip` — drop emoji entirely
  - `word` — replace with `(name)`, e.g. 🔥 → `(fire)` **(default)**
  - `keep` — retain the emoji character in the filename

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
```

## Output layout

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
