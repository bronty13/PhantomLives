# PurpleReel User Manual

Media management for Final Cut Pro, with on-device AI augmentation
(Whisper transcripts, Ollama auto-descriptions, perceptual best-takes).
All processing is local; nothing leaves your machine.

---

## Install

```sh
cd ~/Documents/GitHub/PhantomLives/PurpleReel
./build-app.sh && ./install.sh
```

`build-app.sh` regenerates the icon, runs xcodegen, compiles Release,
and Developer-ID-signs (ad-hoc if no cert). `install.sh` quits any
running copy and dittos into `/Applications/` so TCC grants stick.

Launch from Spotlight or `/Applications/PurpleReel.app`.

---

## First-run walkthrough

1. **Open Folder…** (toolbar `📁+`, or ⌘O) — point at a folder of
   `.mov` / `.mp4` / `.m4v` source media. PurpleReel recursively
   scans and reads codec / resolution / fps / duration via
   AVFoundation.
2. **Click a clip** in the asset table — the bottom split appears:
   AVPlayer on the left, log panes on the right.
3. **Play / scrub** — the scrubber shows the audio waveform and the
   playhead. Click anywhere to seek.

---

## Keyboard

### Player transport
- **Space** — play / pause
- **J** — shuttle reverse (press repeatedly: −1× → −2× → −4×)
- **K** — stop
- **L** — shuttle forward (press repeatedly: +1× → +2× → +4×)
- **←** / **→** — step 1 frame
- **I** / **O** — mark in / mark out
- **M** — add marker at playhead
- **S** — save subclip from current I/O range

### Window
- **⌃⌘S** — toggle sidebar
- **⌘O** — Open Folder…

---

## Toolbar actions

| Icon | Action |
|---|---|
| `sidebar.left` | Toggle sidebar |
| `folder.badge.plus` | Open root folder |
| `arrow.clockwise` | Rescan current folder |
| `sparkles` (AI) | Transcribe, Auto-Describe, Find Similar Takes |
| `character.cursor.ibeam` | Batch Rename |
| `network` | SFTP Delivery |
| `externaldrive.badge.checkmark` | Verified Backup |
| `wand.and.stars` | Transcode selected (H.264 / HEVC / ProRes / pass-through) |
| `arrow.up.forward.app` | Send to FCP (selected clip / library) |

---

## Logging a clip

The right pane of the detail view has four sections:

- **Markers** — tap timecode to jump; edit notes inline; `−` removes
- **Subclips** — same; created via `S` after I/O markers are set
- **Tags** — type and press Return; `×` removes
- **Rating + Description** — five stars; description is a free-form
  text area, fillable manually or via **Auto-Describe**

---

## LUT preview

Below the transport bar:

- **Load LUT…** — pick an Adobe `.cube` file (1D or 3D)
- Active LUT is applied in real time via `AVVideoComposition` +
  `CIColorCubeWithColorSpace`. 1D LUTs are synthesized into a 33³
  cube via per-channel curve sampling.
- Last-used LUT path is restored across launches.

---

## Transcode

Toolbar → **Transcode** → choose a preset:

- **H.264 1080p / 720p** (`.mp4`)
- **HEVC 1080p** (`.mp4`, hardware-accelerated on Apple Silicon)
- **ProRes Proxy / 422** (`.mov`)
- **Pass-through (rewrap)** — no re-encode
- **DNxHR SQ / HQ** (`.mov`) — requires `brew install ffmpeg`
- **Cineform** (`.mov`) — requires ffmpeg
- **ProRes in MXF** — broadcast/archive rewrap, requires ffmpeg

Output lands in `~/Downloads/PurpleReel/transcoded/`.

The queue sheet shows per-job progress; cancel a running job or
**Reveal** a finished file in Finder.

---

## Verified backup + MHL

Toolbar → **Verified Backup**:

1. Pick a **source** folder.
2. Add **1–4 destinations**.
3. Pick a hash algorithm (**SHA-1** is the MHL default).
4. **Start Backup**.

For each file: source is hashed → copied to each destination →
destination is re-hashed → compared. Mismatches fail that file
individually; the rest continue. On completion, an industry-standard
ASC Media Hash List v1.1 `.mhl` is written into each destination
listing every verified file.

---

## SFTP delivery

Toolbar → **SFTP Delivery**:

- **Destinations sidebar**: New / duplicate / delete; saved in
  `UserDefaults`.
- **Editor form**: host, port, user, remote path, identity-file
  (optional — leave empty to use ssh-agent / `~/.ssh/config`),
  "accept new host keys" toggle.
- **Files to upload**: Add Files… from disk, or **All catalogued**
  to fill from the current library.
- **Start Upload** — shells out to `/usr/bin/sftp` with a batch
  script (`mkdir` + `cd` + `put` per file + `bye`). Per-file
  state and raw `sftp` log surface in the sheet.

**Auth note:** SSH key only in this MVP. Set up either ssh-agent
or `~/.ssh/config` with the right HostName/User/IdentityFile, or
provide an identity-file path explicitly in the destination editor.

---

## Send to Final Cut Pro (FCPXML)

Toolbar → **Send to FCP** menu:

- **Selected Clip to Final Cut Pro** — auto-launches FCP if
  installed at `/Applications/Final Cut Pro.app`.
- **Entire Library to Final Cut Pro** — same, but every catalogued
  clip.
- **— Save .fcpxml Only** variants skip the auto-open.

Output: `~/Downloads/PurpleReel/exports/PurpleReel_<timestamp>.fcpxml`.

The generated XML carries:
- One `<asset>` per source file (deduped across the export set)
- Per-clip `<asset-clip>` with NTSC-correct frame rate
- Logged `<marker>`s (with notes) and `<asset-clip>`s for subclips
- `<keyword>` joining all tags
- `<rating name="Favorite">` for 4–5 star clips

---

## AI features (all local, no internet)

### Whisper transcription

Toolbar → **AI** → **Transcribe Selected (Whisper)** or
**Transcribe + Create Markers**.

Bridges the sibling `transcribe/` MLX-Whisper project. Spawns
`python3 transcribe.py -i <clip> -o <tmp> -f srt -m turbo --quiet`,
parses the SRT, persists the full transcript in the catalog DB,
and (for the second variant) creates one marker per segment with
the transcribed text as the marker note.

**Prereqs**:
- `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` must
  exist (sibling subproject).
- Python 3.10+ on PATH (Homebrew Python is checked first; the
  Apple `/usr/bin/python3` on macOS Sonoma is too old).
- First run will pull MLX Whisper packages into the transcribe venv;
  subsequent runs reuse it.

### Auto-Describe (Ollama)

Toolbar → **AI** → **Auto-Describe (Ollama)**.

Posts a prompt to `localhost:11434/api/generate` combining the
filename + (if present) a transcript snippet. The model's reply
fills the clip's description field.

**Prereqs**:
- Ollama running locally (`ollama serve` started, or the menu-bar
  app installed).
- At least one model pulled (`ollama pull llama3.2:1b` is a good
  small default; the service uses whichever model name you pass).

### Similar takes

Toolbar → **AI** → **Find Similar Takes**.

For every video, samples the middle frame and computes a 64-bit
dHash. Pairs with Hamming distance ≤ 10/64 bits are grouped into
clusters. Inside each cluster, the highest-rated → longest-duration
clip surfaces as the "best take" with a rationale.

---

## Batch rename

Toolbar → **Batch Rename**.

Template tokens:

| Token | Example |
|---|---|
| `{orig}` | `IMG_4501` |
| `{ext}` | `.mov` |
| `{date}` | `2026-05-17` |
| `{date:yyyyMMdd}` | `20260517` |
| `{counter}` / `{counter:04}` | `7` / `0007` |
| `{codec}` | `hvc1` |
| `{fps}` | `29.97` |
| `{w}` / `{h}` | `1920` / `1080` |
| `{size_mb}` | `218` |

Preview row turns **red** for conflicts (destination exists or
collides with another batch entry). Apply renames the files on
disk and updates the catalog DB.

---

## Settings → AI pane

Open **Settings** (⌘,) and the **AI** tab to configure:

- **transcribe.py path** — leave blank to use the sibling project
  default, or pick an alternate script. A green ✓ confirms the
  file is present.
- **Whisper model** — turbo (default, fastest), tiny / base / small /
  medium / large-v3 (slower, higher quality).
- **Ollama model** — populated live from `localhost:11434/api/tags`.
  If Ollama isn't running you'll see a red status line and can type
  a model name manually for when it comes up.

## Tests

```sh
./run-tests.sh
```

24 unit tests covering the writers, services, and the
`WindowStateGuard` semantics. Adds ~2 seconds to a full CI loop.

## Where things land

- **Catalog DB**: `~/Library/Application Support/PurpleReel/purplereel.sqlite`
- **Auto-backups**: `~/Downloads/PurpleReel backup/PurpleReel-YYYY-MM-DD-HHmmss.zip`
- **Transcodes**: `~/Downloads/PurpleReel/transcoded/`
- **FCPXML exports**: `~/Downloads/PurpleReel/exports/`
- **MHL manifests**: alongside the backed-up files in each destination

---

## Recovery

If anything window-related looks broken (sidebar collapsed past
minimum, window off-screen): **Window → Reset Window State…**.
This wipes persisted `NSWindow` / `NSSplitView` keys + the bundle's
`Saved Application State` directory, then restores the defaults
on next launch.

If the catalog DB ever gets into a state that confuses you, you
can quit PurpleReel, delete `~/Library/Application Support/PurpleReel/`,
and relaunch — the auto-backup zip in `~/Downloads/PurpleReel backup/`
holds the most recent good copy.
