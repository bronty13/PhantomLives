# PurpleReel User Manual

Media management for Final Cut Pro, with on-device AI augmentation
(Whisper transcripts, Ollama auto-descriptions, perceptual best-takes).
**All processing is local; nothing leaves your machine.**

For installation and prerequisites: **Help → Install & Setup** or
[`INSTALL.md`](INSTALL.md).
For a full keyboard reference: **Help → Keyboard Shortcuts… (⌘?)**
or [`SHORTCUTS.md`](SHORTCUTS.md).

---

## Quick start

1. Install per [`INSTALL.md`](INSTALL.md), launch from
   `/Applications/`.
2. Click **Open Folder…** in the toolbar (or press ⌘O) and pick a
   folder of source media. PurpleReel scans recursively, reads
   codec / resolution / fps / duration from every file via
   AVFoundation.
3. The folder appears in the **Workspace** sidebar section. The
   right pane (the browser) fills with the catalogued clips.
4. Click any clip to load it in the player. Double-click to switch
   into Detail view (single-clip with metadata pane).
5. Press ⌘? at any time to see every keyboard shortcut.

---

## The sidebar: Workspace + Devices

The left sidebar has two always-present sections.

### Workspace

User-curated folder roots. Add as many as you like — each one
scans + indexes independently.

- **Add Folder to Workspace…** (⌘I or the gear menu) — appends a
  new root without dropping existing ones.
- **Open Folder…** (⌘O) — replaces the workspace with a single
  folder. Used for fresh-start workflows.
- **Clear Workspace…** — removes all roots; catalogued metadata
  (tags / markers / ratings / log fields) stays in the database.
- Right-click a root for **Remove from Workspace**, **Remove
  Others**, **Reveal in Finder**, **New Folder…**, **Drilldown**
  toggle, **Clear Thumbnail Cache**.

### Devices

Auto-enumerated from `/Volumes/*`. **Macintosh HD** is always
listed; mounted externals appear automatically.

- Devices is read-only from the workspace's perspective — clicking
  a device folder navigates into it without adding it to the
  workspace. Right-click → **Add to Workspace** to promote it.
- The boot volume's firmlink (`/Volumes/Macintosh HD`) is
  canonicalized to `/` internally so its prefix matches your
  catalogued `/Users/…` paths correctly.

### Drilldown

Selecting a folder either shows **direct children only** or
**every file in the subtree** ("drilldown ON"). Drilldown is
per-folder:

- The toolbar's **Drilldown** button toggles it for the currently
  selected folder. Orange when on.
- An orange down-arrow badge appears on a folder's icon in the
  sidebar when drilldown is enabled for that folder.
- Volume roots (Macintosh HD, external drives) auto-drilldown
  because their direct children are typically not catalogued
  media.

---

## The browser

The main area to the right of the sidebar. Three view modes,
toggled with ⌘1 / ⌘2 / ⌘3 or the segmented control in the toolbar.

### Grid view (⌘1)

Thumbnail tiles in a 16:9 ratio. Each tile shows:

- A frame from the middle of the clip (image assets show the
  full image).
- The filename.
- A blue selection ring (thicker for the **primary** selection
  in a multi-selection).
- A transcode-progress overlay when the queue is working on
  that clip — preset name, percentage, orange bar. Finished
  clips get a green ✓ or red ✗ corner badge.

### List view (⌘2)

Sortable table. Default columns: Thumbnail, Name, Codec,
Resolution, FPS, Duration, Size.

**Optional columns** via the **Columns** menu in the toolbar
(up to 3 of 10 visible at once due to SwiftUI's table cap;
toggle one off to surface another):

- Rating
- Date Modified
- Title
- Description
- Reel / Scene / Shot / Take / Angle / Camera (the Kyno log fields)

**Sorting**: the **Sort** menu picks the key; click an already-
selected key to flip direction; the toolbar caret shows current
ascending/descending state.

### Detail view (⌘3)

Single-clip viewer with the player on the left and a Metadata
pane on the right. Use ⌘← / ⌘→ to step through clips in the
current list without leaving Detail view.

**Double-click anywhere on a clip's row** (in Grid or List) to
enter Detail view inline. ⌘1 or ⌘2 returns to the other view.

### Selecting clips

- **Click** — single-select; the clicked clip becomes the
  primary selection and loads in the player.
- **Cmd-click** — toggle a clip in or out of the selection.
- **Shift-click** — range-extend from the primary selection.
- Multi-select drives batch operations: Convert, Send to FCP,
  Move to Trash, Tags, SFTP delivery.

### Filters and search

The browser toolbar has three rows of controls:

**Row 1 — view + drilldown + type chips + filter + columns + sort**

- Type filter chips: **All / Video / Audio / Images**.
- **Time** filter (sort menu) — Any / Last hour / 24h / 2d / 7d /
  30d / 3m / 6m / Year. Predicates on `modifiedAt`.
- **Filter** menu — advanced multi-criteria dropdown (see below).
- **Columns** menu — pick which optional List-view columns to show.
- **Sort** menu — sort key + ascending/descending toggle.

**Row 2 — name filter**

A live text filter on the displayed clip's filename. Combines
with everything else as AND.

**Row 3 — active filter pills** (visible only when criteria are
pinned)

Each advanced criterion appears as a removable orange capsule.
Click the × on a pill to remove it; "Clear All" wipes everything.

### Advanced filter dropdown

The **Filter** toolbar menu opens categorized submenus for
pinning predicates that AND-compose:

- **Rating** — ≥★, ≥★★, … ≥★★★★★
- **Codec** — H264 / HEVC / PRORES / DNXHR / CINEFORM
- **Resolution** — 8K / 4K UHD / 1440p / 1080p / 720p / 480p
  (portrait clips match by `max(width, height)`)
- **Frame Rate** — 23.98 / 24 / 25 / 29.97 / 30 / 50 / 59.94 /
  60 fps (±0.05 tolerance around each target)
- **Size** — ≥100MB / ≥500MB / ≥1GB / ≥5GB / ≤10MB / ≤100MB
- **Duration** — ≥1m / ≥5m / ≥30m / ≤30s / ≤5m
- **Has Tag** — only shown when at least one tag exists in the
  workspace; lists every known tag

Active filters survive across launches (persisted in
UserDefaults).

---

## The player

Loads automatically when you click a clip. The player has a
preview surface on top and a transport bar below.

### Transport

- **Space** — play / pause
- **←** / **→** — step 1 frame (frame-accurate)
- **Shift+←** / **Shift+→** — jump 5 seconds (coarse seek)
- **J** / **K** / **L** — multi-rate shuttle (J reverse, K stop,
  L forward; repeated presses ramp through 1×/2×/4×)
- **I** / **O** — set in / out point
- **⌥X** — clear in/out range
- **⌥Space** — play from in to out
- **↑** / **↓** — jump to previous / next anchor (markers + in +
  out, unioned and sorted, with a ±0.05s epsilon so landing on
  one doesn't immediately re-fire)

### Scrubbing + waveform

- Click anywhere on the scrubber to seek.
- Drag the scrubber for continuous seek.
- Audio waveform is overlaid on the scrubber (downsampled peaks
  generated asynchronously after load).
- The in/out range shows as a translucent overlay; the playhead is
  a vertical line.

### Marker, subclip, frame export

- **M** — add a marker at the playhead. The marker note is editable
  inline in the Log tab.
- **S** — save a subclip from the current I/O range. The name
  defaults to `<filename> [<timecode>]`; editable after save.
- **⌘⇧E** — export the current frame as PNG. Frame-accurate
  (`AVAssetImageGenerator` with zero tolerance), save panel opens,
  Finder reveals the output.

### Loop, fullscreen

- **⌘L** — toggle loop mode. When on, the player auto-seeks back
  to the in marker (or 0:00 if no in marker) and resumes on
  end-of-item. The orange `repeat.circle.fill` button in the
  transport bar reflects the state.
- **⌘F** — toggle macOS fullscreen on the window. Esc exits.

### Rotation + flip

The transport bar's **View** menu has Rotate 0°/90°/180°/270° and
Flip Horizontal / Vertical. These are **preview-only** — the
underlying file is never modified, and transcodes use the source
orientation.

### LUT preview

Below the transport bar:

- **Load LUT…** — pick an Adobe `.cube` file (1D or 3D).
- Applied in real time via `AVVideoComposition` +
  `CIColorCubeWithColorSpace`. 1D LUTs are synthesized into a 33³
  cube via per-channel curve sampling.
- Last-used LUT path is restored across launches.
- The current LUT shows as a pill on the LUT bar; click × to
  clear.

### Image assets

When the selected clip is an image (JPG/PNG/HEIC/TIFF), the
player surface swaps to an `ImagePreviewView`. AVPlayer can't
render still images, so we don't route them through it. The
metadata pane still works identically.

---

## Logging clips: Metadata pane

The right-side inspector has four tabs: **Metadata** (default) /
**Content** / **Tracks** / **Log**.

### Metadata tab — Kyno-style log fields

One row per asset in the `clip_metadata` table. Edit any field
and the change commits on Return or focus loss (no Save button).

Fields:

- **Rating** — 5 stars + a clear button. ★★★★ and ★★★★★ map to
  FCP's "Favorite" rating on export.
- **Title** — free text.
- **Description** — multi-line.
- **Reel** / **Scene** / **Shot** / **Take** / **Angle** /
  **Camera** — single-line per field. These flow through to
  FCPXML as `<md key="…" value="…"/>` entries inside a
  `<metadata>` block (omitted entirely when no field is set).
- **Tags** — removable pill list with inline "Add tag and press
  Return" field. Tags also drive the advanced **Has Tag** filter.

### Content tab

Read-only technical summary plus a 5×6 frame grid (30 thumbnails
spread across the clip's duration). Click any frame to seek the
player to that timecode. Includes: filename, path, size,
modification/creation/recording dates, container format, codec,
fps, bitrate, audio codec/sample rate/channels.

### Tracks tab

Per-stream technical breakdown. Video track: codec, fps,
resolution, aspect, bitrate, duration. Audio track: codec,
sample rate, channel layout, bitrate.

### Log tab

The original logging surface — still functional, still where
markers and subclips live:

- **Markers** — tap a timecode to seek the player; edit notes
  inline; minus icon removes.
- **Subclips** — same; created via `S` after I/O markers are
  set.
- **Tags + Rating** — same data as the Metadata tab; either pane
  edits the other.

---

## Convert workflow

Right-click any clip (or selection) → **Convert** → pick a
preset. The submenu is categorized Kyno-style:

- **Recently Used** — top of the menu; last 6 presets you
  picked. ⌘E re-fires the most recent.
- **Editing** — ProRes 422 (FCP timeline-native)
- **Web** — H.264 1080p / H.264 720p / HEVC 1080p
- **Proxies** — ProRes Proxy
- **Rewrap** — Pass-through (container only, no re-encode)
- **DNxHR** — SQ / HQ (requires `brew install ffmpeg`)
- **Distribution** — Cineform (ffmpeg), ProRes in MXF (ffmpeg)

### The Convert dialog

Every preset pick opens **Convert & Transcode Media**:

- **Directory** — defaults to `~/Downloads/PurpleReel/transcoded/`.
  **Select…** opens an NSOpenPanel; the choice persists across
  launches.
- **Keep folder structure from source** — when on, files land at
  `<destination>/<relative path>/` using the common ancestor of
  all sources as the relative root.
- **Skip items that already exist on target** — when on, sources
  whose target file already exists are silently skipped. Off,
  collisions get numeric suffixes (`_h264_1080p_1.mp4`).
- **Conversion Preset** — read-only summary card showing file
  format, category, engine (AVFoundation vs ffmpeg), suffix.
- **N files will be created in …** — live count with the
  destination path.
- **Start** — enqueues every selected asset through the
  TranscodeQueue (serial drain by default to keep the hardware
  HEVC encoder happy) and opens the queue sheet.

### Per-asset progress in Grid view

Each grid tile self-subscribes to its matching `TranscodeJob`.
While running: dark bottom bar with preset name + percentage +
orange progress bar. Finished: green ✓ corner badge for success,
red ✗ for failure / cancellation. Hover for the failure reason.

### Cancelling

Open the queue sheet (toolbar → Transcode → Show Queue…). Click
**Cancel All** to drop pending jobs and stop the current one. A
running AVAssetExportSession's partial output file is removed on
cancellation; ffmpeg jobs are SIGKILL-ed by `Process.terminate()`.

---

## Verified backup + MHL

Toolbar → **Verified Backup**:

1. Pick a **source** folder.
2. Add **1–4 destinations**.
3. Pick a hash algorithm — **SHA-1** is the ASC MHL default;
   SHA-256 / MD5 / xxHash also supported.
4. **Start Backup**.

For each file: source is hashed → copied to each destination →
destination re-hashed → compared. Mismatches fail that file
individually; the rest continue. On completion an industry-
standard ASC Media Hash List v1.1 `.mhl` lands in every
destination, listing every verified file.

This is separate from the **auto-backup** of the catalog DB,
which runs on every app launch — see Settings → Backup.

---

## SFTP delivery

Toolbar → **SFTP Delivery**:

- **Destinations sidebar**: New / duplicate / delete; saved in
  UserDefaults.
- **Editor form**: host, port, user, remote path, identity-file
  (optional), "accept new host keys" toggle.
- **Files to upload**: Add Files… from disk, or **All
  catalogued** to fill from the current library.
- **Start Upload** — shells out to `/usr/bin/sftp` with a batch
  script (`mkdir` + `cd` + `put` per file + `bye`). Per-file
  state and the raw `sftp` log surface in the sheet.

**Auth options:**

- **SSH key** (preferred): use ssh-agent or `~/.ssh/config` (set
  HostName/User/IdentityFile), or set an explicit identity-file
  in the destination editor.
- **Password**: fill the secure field. Stored in the macOS
  Keychain under service `com.bronty13.PurpleReel.sftp`. The
  non-interactive flow needs `sshpass`
  (`brew install hudochenkov/sshpass/sshpass`); the password is
  fed via `SSHPASS` env var rather than `-p` so it stays out of
  `ps` output.

---

## Send to Final Cut Pro (FCPXML)

Toolbar → **Send to FCP** menu:

- **Selected Clip to Final Cut Pro** — auto-launches FCP if
  installed.
- **Entire Library to Final Cut Pro** — same, but every
  catalogued clip.
- **— Save .fcpxml Only** variants skip the auto-open.

Output: `~/Downloads/PurpleReel/exports/PurpleReel_<timestamp>.fcpxml`.

The generated XML carries:

- One `<asset>` per source file (deduped across the export set)
- Per-clip `<asset-clip>` with NTSC-correct frame-rate rational
  (e.g. `1001/24000s` for 23.976)
- Logged `<marker>`s (with notes) and `<asset-clip>`s for
  subclips
- `<keyword>` joining all tags
- `<rating name="Favorite">` for 4–5 star clips
- `<metadata>` block with `<md key="Title" .../>` etc. for any
  populated log field (Title / Description / Reel / Scene /
  Shot / Take / Angle / Camera)

---

## AI features (all local, no internet)

### Whisper transcription

Toolbar → **AI** → **Transcribe Selected (Whisper)** or
**Transcribe + Create Markers**.

Bridges the sibling `transcribe/` MLX-Whisper project. Spawns
`python3 transcribe.py -i <clip> -o <tmp> -f srt -m <model>
--quiet`, parses the SRT, persists the full transcript in the
catalog DB, and (for the second variant) creates one marker per
SRT segment with the transcribed text as the note.

**Prereqs**: see [`INSTALL.md`](INSTALL.md) §4.b. Override the
script path under **Settings → AI** if your `transcribe/`
project lives elsewhere.

### Auto-Describe (Ollama)

Toolbar → **AI** → **Auto-Describe (Ollama)**.

Posts a prompt to `localhost:11434/api/generate` combining the
filename + (when present) a transcript snippet. The model's
reply fills the clip's Description field in the Metadata pane.

**Prereqs**: Ollama running, at least one model pulled. See
[`INSTALL.md`](INSTALL.md) §4.c.

### Similar takes

Toolbar → **AI** → **Find Similar Takes**.

For every video, samples the middle frame and computes a 64-bit
dHash. Pairs with Hamming distance ≤ 10/64 bits cluster
together. Inside each cluster, the highest-rated → longest-
duration clip surfaces as the "best take" with a rationale.

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

Preview rows turn **red** for conflicts (destination exists, or
collides with another batch entry). Apply renames the files on
disk and updates the catalog DB.

---

## Settings

Open with ⌘, (standard macOS shortcut).

### Backup pane

Non-negotiable per the PhantomLives backup standard.

- **Auto-backup on launch** toggle (default on).
- **Retention** (0…365 days; `0` keeps forever).
- **Backup location** — text field + **Choose…** picker +
  **Default** button. Resolved path shown in monospaced caption.
- **Reveal in Finder** for the backup folder.
- **Run Backup Now** — runs unconditionally (bypasses the 5-min
  launch debounce).
- **Recent Backups** list — per-row **Test** (extracts to tempdir
  and verifies DB presence non-destructively), **Restore**
  (replaces live state with the archive, always creating a
  `PurpleReel-pre-restore-<stamp>.zip` safety backup first), and
  **Reveal in Finder**.
- Last-backup timestamp readout.
- Status line for the most recent operation.

### AI pane

- **transcribe.py path** — leave blank for the sibling-project
  default, or pick an alternate script. ✓ confirms presence.
- **Whisper model** — turbo (default, fastest), tiny / base /
  small / medium / large-v3 (slower, higher quality).
- **Ollama model** — populated live from
  `localhost:11434/api/tags`. Red status when Ollama isn't
  running; you can type a model name manually for when it comes
  up.

### About pane

App version + build (git-derived), build date, sources for
on-device AI models, license note.

---

## Recovery + reset

**Window state broken** (sidebar mis-sized, window off-screen):
**Window → Reset Window State…**. Wipes persisted NSWindow /
NSSplitView keys + the bundle's `Saved Application State`
directory. Restart for full effect.

**Catalog DB confused** (rare):

1. Make a fresh backup: **Settings → Backup → Run Backup Now**.
2. Quit PurpleReel.
3. `rm -rf ~/Library/Application\ Support/PurpleReel/`
4. Relaunch — the v1 + v2 migrations run from scratch.
5. If you need the old data back, **Settings → Backup → Recent
   Backups → Restore** on the archive you just made.

**Full factory reset**: see [`INSTALL.md`](INSTALL.md) §5
"Reset everything".

---

## Where things land

| What | Where |
|---|---|
| Catalog DB | `~/Library/Application Support/PurpleReel/purplereel.sqlite` |
| Thumbnail cache | `~/Library/Application Support/PurpleReel/thumbnails/` |
| Auto-backups | `~/Downloads/PurpleReel backup/` |
| Transcoded output | `~/Downloads/PurpleReel/transcoded/` |
| FCPXML exports | `~/Downloads/PurpleReel/exports/` |
| MHL manifests | Alongside backed-up files in each destination |
| Crash logs | `~/Library/Logs/DiagnosticReports/PurpleReel-*` |
| Console (NSLog) | Console.app, filter by process `PurpleReel` |

---

## Where to go next

- [`SHORTCUTS.md`](SHORTCUTS.md) — full keyboard reference,
  generated from the canonical Swift source.
- [`INTEGRATION_TEST_PLAN.md`](INTEGRATION_TEST_PLAN.md) — 23
  scenarios that exercise the whole surface end-to-end.
- [`KYNO_PARITY_ROADMAP.md`](KYNO_PARITY_ROADMAP.md) — what's
  done, what's next.
- [`README.md`](README.md) — repo overview, build / test
  commands.
