---
title: Media & Creative Tools
part: P09 Apps
est_time: 60 min read + 60 min labs
prerequisites: [part-03-cli/03-essential-unix-commands, part-03-cli/12-homebrew-and-package-management, part-02-gui/07-quick-look-and-preview]
tags: [macos, media, creative, ffmpeg, photos, music, video, audio, codecs, heic, exiftool, osxphotos, imagemagick, sips]
---

# Media & Creative Tools

> **In one sentence:** macOS has been the creative professional's platform for 40 years — this lesson explains why at the engineering level, arms you with CLI power tools that expose capabilities no GUI surfaces, and gives forensics-relevant depth on every artifact the media stack leaves behind.

---

## Why this matters

The Mac's media dominance isn't marketing — it's silicon. Apple Silicon's dedicated media engines offload H.264, HEVC, ProRes, and now AV1 decode entirely from the CPU, delivering real-time 4K/8K transcodes that would throttle a Windows workstation. For forensics work, media files are artifact goldmines: embedded GPS coordinates, creation timestamps, device fingerprints, edit histories, and iCloud sync traces. Understanding the full stack — from the hardware media engine through the codec layer to the app-level databases — makes you dangerous in both directions: you can process enormous media libraries efficiently, and you can reconstruct timelines from artifacts that a subject thought were gone.

---

## Concepts

### The Apple Silicon Media Engine

Every M-series chip ships dedicated, fixed-function **media encode/decode engines** that run independently of the CPU and GPU. These are exposed to software via the **VideoToolbox** framework (low-level) and **AVFoundation** (high-level).

| Chip generation | H.264 | HEVC (H.265) | ProRes | AV1 decode | AV1 encode |
|---|---|---|---|---|---|
| M1 / M1 Pro/Max/Ultra | enc+dec | enc+dec | enc+dec (Pro/Max/Ultra) | — | — |
| M2 family | enc+dec | enc+dec | enc+dec | — | — |
| M3 family | enc+dec | enc+dec | enc+dec | yes | — |
| M4 family | enc+dec | enc+dec | enc+dec | yes | M4 Ultra only |
| M5 family | enc+dec | enc+dec | enc+dec | yes | Pro/Max/Ultra |

> 🔬 **Forensics note:** `mediainfo` or `exiftool` on a ProRes file can expose the exact encoder binary, encoding timestamp, and sometimes the source device UUID in the container metadata. Files transcoded via VideoToolbox leave a distinct codec fingerprint vs. software encoders like libx265 or libvpx.

**VideoToolbox** is a C/Objective-C framework in `/System/Library/Frameworks/VideoToolbox.framework`. It exposes sessions for compression (`VTCompressionSession`) and decompression (`VTDecompressionSession`). When `ffmpeg` uses `-c:v hevc_videotoolbox`, it is calling directly into this framework; the CPU never touches raw pixel data during the encode.

**ProRes** deserves special mention: it is a lossless-quality *mezzanine* codec used in professional post-production. ProRes RAW is Apple's raw-sensor variant. The media engine on M1 Pro/Max and later can encode ProRes in real time from multiple camera streams simultaneously — this is why Final Cut Pro's multicam performance on Apple Silicon looks like sorcery.

---

### The HEIC/HEIF Default and Why It Matters

Since iOS 11 (and macOS High Sierra), Apple devices default to **HEIC** (High Efficiency Image Container), a variant of **HEIF** (High Efficiency Image File Format) using HEVC intra-frame compression. A typical iPhone 16 shot at 48 MP is 8–12 MB as HEIC vs. 25–35 MB as JPEG at equivalent quality.

On-disk facts:
- HEIC is an ISO Base Media File Format (ISOBMFF) container, structurally similar to MP4.
- An HEIC file can embed multiple images (burst sequences, HDR gains maps, Live Photo stills + motion), depth maps, and full EXIF/XMP metadata.
- The `.photoslibrary` package (see below) stores originals in HEIC internally; re-export via `sips` or `osxphotos` converts to JPEG on the fly.

> 🔬 **Forensics note:** HEIC files from iPhones embed GPS, device model, lens data, face detection rectangles, and (if HDR) a gain map as a secondary image item. The `exiftool` field `Apple:HDRImageType` distinguishes the base vs. HDR composite. `MediaGroupUUID` and `ContentIdentifier` cross-link the still and the Live Photo `.mov` — useful for reconstructing complete scene captures.

> 🪟 **Windows contrast:** Windows 10/11 requires a paid codec pack from the Microsoft Store to natively open HEIC files. Many Windows apps still can't read the embedded gain maps, depth maps, or Live Photo motion. On macOS, every framework from QuickLook to NSImage to AVFoundation understands HEIC natively — no codec install needed.

---

### The Photos Library Architecture

Photos stores everything in **`~/Pictures/Photos Library.photoslibrary`** — a macOS package (a directory masquerading as a file). Right-click → Show Package Contents to explore:

```
Photos Library.photoslibrary/
├── database/
│   ├── Photos.sqlite        # The main library DB — SQLite 3
│   ├── Photos.sqlite-wal    # Write-ahead log (may have uncommitted data!)
│   └── Photos.sqlite-shm    # Shared memory file
├── originals/               # Original imports, organized in 16 hex subdirs (0–f)
│   └── A/B/C/...
├── resources/
│   ├── derivatives/         # Cached edits, thumbnails, previews
│   ├── caches/              # Spatial, ML face-detection, search indexes
│   └── media/               # Memories, Highlights media
├── private/
│   └── com.apple.photoanalysisd/  # ML analysis results
└── Metadata/
    └── ...                  # XMP sidecars for imported assets with metadata
```

**`Photos.sqlite`** is the database you actually care about. It uses Apple's proprietary CoreData schema, but the tables are accessible with standard SQLite tools. Key tables:

| Table | Contains |
|---|---|
| `ZASSET` | Every photo/video: UUID, filename, original date, iCloud state, hidden/trashed flag, burst UUID |
| `ZGENERICASSET` | (alias/older schema) — same asset data in some library versions |
| `ZADDITIONASSET` | Import date, batch import UUID |
| `ZASSETDESCRIPTION` | AI-generated captions (macOS 15+) |
| `ZCLOUDMASTER` | iCloud resource pointers, fingerprint hashes |
| `ZPERSON` | Named faces |
| `ZFACE` | Per-face detection: bounding box, quality score, cluster UUID |
| `ZALBUM` | Albums, smart albums, shared albums |
| `ZMEMORY` | Memories events |

> 🔬 **Forensics note:** `ZASSET.ZTRASHEDSTATE` = 1 means the asset is in Recently Deleted (not yet purged). `ZASSET.ZHIDDEN` = 1 means the Hidden album. `ZASSET.ZCLOUDLOCALSTATE` encodes iCloud upload/download status. The `ZADJUSTMENTS` BLOB in `ZASSET` is a binary plist containing every edit operation ever applied — you can extract it with `plutil` to see the full edit history without rendering. The `.photoslibrary` package is TCC-gated under `com.apple.security.personal-information.photos-library`; without that grant, even root cannot open it. See [[02-tcc-and-privacy]].

**The `osxphotos` CLI** (pip-installable, `pipx install osxphotos`) wraps the SQLite database and exposes it as a fully queryable, scriptable export tool. This is the same library underlying PurpleAttic ([[project_purpleattic]]). It bypasses the Photos UI entirely, reading the DB and originals directly.

---

### Music / Apple Music and the iTunes Lineage

The current **Music.app** is the iTunes codebase, split in macOS Catalina (2019) into Music, Podcasts, and TV. The library is:

```
~/Music/Music/Media.localized/
├── Music/                   # Organized by Artist/Album
├── Music Videos/
├── Podcasts/
└── Automatically Add to Music/   # Drop files here; Music imports them
```

The library metadata lives in:
```
~/Music/Music/Music Library.musiclibrary/   # Package (macOS 12+)
    └── Library.musicdb                      # SQLite database
```

Before macOS 12, the library was `iTunes Library.xml` + `iTunes Library.itl` (binary plist). The `.musiclibrary` package format replaced this; the XML sidecar (`iTunes Music Library.xml`) is still written for third-party app compatibility but is not the source of truth.

> 🔬 **Forensics note:** `Library.musicdb` tracks play counts, last-played dates, date added, iCloud Music Library sync state, skip counts, and explicit purchase metadata. Cross-referencing a suspect's play history with timestamps can establish presence/absence or activity patterns. The `ZLOCATION` field in the asset table encodes whether a track is local, iCloud, or Apple Music streaming.

---

### QuickTime Player vs. IINA vs. VLC

**QuickTime Player** (QTP) is the right tool for:
- **Screen recording** — integrates with ReplayKit; see [[08-screenshots-and-screen-recording]]
- **Trimming** — Edit → Trim (`⌘T`) is lossless for H.264/HEVC/AAC
- **iPhone mirroring recording** — works as a camera for connected iDevices

QuickTime Player is the **wrong tool** for playback of anything non-Apple. It cannot decode: AV1 without hardware, VP8/VP9, FLAC, OGG, MKV containers, ASS/SSA subtitles, multi-audio-track switching, or most open codecs.

**IINA** (`brew install --cask iina`) is the macOS-native power player built on **mpv** (libmpv). It uses Metal rendering, native macOS UI patterns, supports hardware decoding via VideoToolbox for all supported codecs, handles every container format mpv can read, and has subtitle, chapter, and multi-track support. This is the recommendation for daily playback.

**VLC** (`brew install --cask vlc`) uses its own codec stack entirely, ships its own FFmpeg-derived libraries, and can play literally anything including badly muxed or corrupt files. Use it when IINA won't open something. VLC's streaming (RTSP, HLS, UDP) and transcoding (`vlc --sout`) features are powerful but clunky.

> 🪟 **Windows contrast:** On Windows, codec fragmentation is a years-long problem — installing K-Lite Codec Pack or MPC-HC with LAV Filters has been the workaround. macOS ships with comprehensive HEIC/HEVC/H.264/AAC native support, and IINA gives you VLC-level format coverage with a native UI feel.

---

### Preview: The Hidden Workhorse

**Preview.app** is far more powerful than most users realize — see [[07-quick-look-and-preview]] for the deep dive. For the media context: it is the system's default PDF renderer, image editor, and annotation engine. It can:

- Batch-convert images via drag-and-drop into File → Export (one at a time) or via File → Export as PDF for multi-image PDFs
- Perform basic color adjustments (Tools → Adjust Color)
- Sign PDFs, annotate, redact (with Markup)
- Read and display HEIC, TIFF, PSD (flattened), SVG, WebP

What it cannot do: non-destructive layered editing, raw processing, color profiles beyond display, or scripting. For those: Pixelmator Pro.

---

### Image Capture: The Underused Import Bridge

**Image Capture.app** (`/System/Applications/Image Capture.app`) is the macOS import agent for cameras, scanners, iPhones treated as cameras, and any PTP/MTP device. The mechanism:

- It speaks **PTP (Picture Transfer Protocol)** and **MTP (Media Transfer Protocol)** via the Image Capture Core framework
- Scanners are addressed via **ICA (Image Capture Architecture)** and optionally **SANE** backends
- When an iPhone is connected and trusted, it appears here as a PTP device even without Photos permission

The hidden batch power: select multiple photos → right-click → "Download All" or set "Connecting this iPhone opens" to "Image Capture" in preferences. You can set the auto-import destination to any folder, including a watched hot folder for automated downstream processing.

> 🔬 **Forensics note:** Image Capture's PTP mode can enumerate device internal structure that the Photos "import" flow hides — including files in DCIM subdirectories that the Photos app would skip (non-standard extensions, already-imported assets). For mobile device evidence, `libimobiledevice` + `ifuse` gives deeper access than Image Capture, but Image Capture is available out of the box with no additional install.

---

### The Free Starter Apps

**GarageBand** and **iMovie** ship free on all Macs from the App Store and are the entry points to Logic Pro and Final Cut Pro respectively. They share project file formats (`.band` / `.iMovieProj`) that are importable directly into their pro siblings — which means a project started on GarageBand can be opened in Logic Pro without conversion.

GarageBand's **`~/Music/GarageBand/`** folder stores project packages; Loop Library lives at `/Library/Audio/Apple Loops/Apple/`. The audio engine underneath both GarageBand and Logic is **CoreAudio**, which runs at the kernel level via `coreaudiod` — a separate daemon that bypasses the usual audio subsystem for ultra-low-latency plugin processing.

---

### Professional Creative Apps

#### Final Cut Pro, Motion, Compressor

Final Cut Pro uses **Background Rendering** — it pre-renders complex timelines in the background, storing render caches in `~/Movies/Final Cut Events/` (older) or `~/Movies/Final Cut Pro/` (FCP X library packages). Libraries are packages:

```
MyProject.fcpbundle/
├── CurrentVersion.fcpevent/
│   ├── Original Media/     # Optional — if you chose "Copy to library"
│   └── Render Files/
└── Settings.plist
```

FCP uses the **XML Interchange Format** for round-tripping to DaVinci Resolve or other tools (`File → Export XML`). The format is documented by Apple and human-readable.

**Compressor** is FCP's batch encode companion — it exposes VideoToolbox hardware acceleration via a GUI queue and supports distributed encoding across multiple Macs on the same network. Under the hood it calls `compressorkit.framework`.

**Motion** is the motion graphics engine; `.motn` projects can be published as FCP generators, transitions, and effects, extending FCP non-destructively.

#### Logic Pro

Logic stores projects as packages (`.logicx`). The audio engine uses **CoreAudio** units — Audio Units (AU) plugins live at:
- `/Library/Audio/Plug-Ins/Components/` (system)
- `~/Library/Audio/Plug-Ins/Components/` (user)

Logic has no subscription model — one purchase, free updates. This is a deliberate Apple competitive stance against Adobe.

#### DaVinci Resolve

**DaVinci Resolve** (free tier, `brew install --cask davinci-resolve`) is the industry-standard color grading and audio post platform. On Apple Silicon it leverages Metal extensively and VideoToolbox for codec acceleration. The free version lacks some collaboration and noise reduction features but is complete for professional editing and grading. Resolve stores projects in a PostgreSQL database (local or shared); you can also use `.drp` project archives for portability.

> 🔬 **Forensics note:** DaVinci Resolve's database can store frame-accurate EDL metadata, markers, and color decisions with timestamps — occasionally relevant when establishing a video's production timeline.

#### Affinity Suite (Photo / Designer / Publisher)

The **Affinity suite** (Serif) is the primary Adobe alternative on macOS. One-time purchase, no subscription. Architecture:

- **Affinity Photo 2**: non-destructive raw processor + compositor; PSD/PSB read/write; native HDR editing
- **Affinity Designer 2**: vector + raster hybrid; AI/EPS/SVG/PDF native; GPU-rendered canvas via Metal
- **Affinity Publisher 2**: desktop layout; live-links to Photo and Designer via "Studio Link" (embed live design/photo documents with full editability)

All three share a single rendering engine and use `.afphoto` / `.afdesign` / `.afpub` formats, which are ZIP-compressed packages. They support Apple Pencil on iPad (same codebase runs iOS).

> 🪟 **Windows contrast:** Adobe CC runs on Windows first — many features arrive on Mac months later. Affinity Suite is truly macOS-first and fully leverages Metal for GPU-accelerated brushes and rasterization. The gap in features vs. Photoshop has narrowed considerably; for most forensic-adjacent work (image analysis, PDF annotation, document production) Affinity Photo is sufficient and faster.

#### Pixelmator Pro and Acorn

**Pixelmator Pro** (Mac App Store) is the deep-integration Apple-ecosystem image editor — it uses CoreML for ML-powered tools (Super Resolution, ML Denoise, Smart Remove), integrates with Photos extension hooks, and uses Metal for rendering. It is excellent for batch automation via **Pixelmator Pro automations** (a custom scripting language similar to AppleScript). If your workflow is heavily Apple-ecosystem, Pixelmator Pro wins on integration.

**Acorn** (Flying Meat Software) is a lighter, faster image editor with genuine scriptability via JavaScript and AppleScript. Its `.acorn` format is a ZIP of layers as PNGs — forensically transparent.

#### Sketch and Figma

**Sketch** (macOS-only, subscription) is the originator of the modern UI design tool category. Files are `.sketch` packages (ZIP of JSON + assets). **Figma** runs in the browser and as an Electron app; it has largely captured the collaborative design market but Sketch retains a following for solo work. Neither is relevant to forensics beyond noting that `.sketch` files from design assets may appear in evidence and are fully readable as ZIP archives.

#### Adobe CC Reality

Adobe Creative Cloud runs on Apple Silicon via native ARM binaries as of 2022 across the suite. Performance is strong, but the subscription model, background daemon (`ACCFinderExtension`, `AdobeGCClient`, `AAMUpdatesNotifier`), and aggressive TCC permission requests make it distinctive on macOS. If you need to analyze a machine with Adobe CC installed, note:

- `~/Library/Application Support/Adobe/` — preferences, project history
- `~/Library/Preferences/com.adobe.*` — app-level plists
- `/Library/Application Support/Adobe/Adobe Desktop App/` — the CC launcher daemon
- `LaunchAgents` installed by Adobe: `com.adobe.GC.*`, `com.adobe.AdobeCreativeCloud*`

> 🔬 **Forensics note:** Adobe's license validation touches network endpoints regularly. Correlating `com.adobe.GCClient.plist` launch agent timestamps with network logs can establish machine activity windows.

#### Blender and Audacity

**Blender** (`brew install --cask blender`) is the full open-source 3D creation suite. On Apple Silicon it uses Metal for viewport rendering and the Cycles renderer has Metal GPU backend support. **Audacity** (`brew install --cask audacity`) is the classic open-source audio editor; it now has Telemetry (opt-out in Preferences) since the 2021 ownership change.

---

### Color Management and Display Calibration

macOS implements color management through **ColorSync** — every image, PDF, and video carries an ICC profile and ColorSync handles conversion at display time. Key facts:

- Displays are profiled at the hardware level; P3 displays on modern Macs can show colors outside sRGB
- The system color profile lives at `/Library/ColorSync/Profiles/` (system) and `~/Library/ColorSync/Profiles/` (user)
- `colorsyncd` is the daemon; it runs per-session
- `sysctl -n hw.model` combined with the display ID tells you the color space
- Calibrate via System Settings → Displays → Color → Calibrate (generates an ICC profile)
- For professional work, hardware calibrators (X-Rite, Datacolor) use vendor-supplied apps that write directly to the ColorSync profile store

> 🔬 **Forensics note:** ICC profiles embedded in images carry the originating display's color profile — sometimes including monitor serial numbers in older profiles. An image that claims to be from an iPhone but has a Dell monitor profile embedded was likely processed on a PC first.

---

## Hands-on (CLI & GUI)

### sips: Scriptable Image Processing System

`sips` is the Swiss Army knife for image manipulation built into every macOS install. Zero dependencies, zero install. Key flags:

```bash
# Convert a single HEIC to JPEG
sips -s format jpeg photo.heic --out photo.jpg

# Batch convert all HEICs in current directory to JPEG (80% quality)
for f in *.heic *.HEIC; do
  [[ -f "$f" ]] || continue
  sips -s format jpeg -s formatOptions 80 "$f" --out "${f%.*}.jpg"
done

# Resize to max 2048px on either dimension (preserves aspect ratio)
sips -Z 2048 photo.jpg

# Get image info
sips -g all photo.heic

# Convert to PNG and resize in one pass
sips -s format png -Z 1920 screenshot.heic --out screenshot.png

# Strip color profile and convert to sRGB
sips -m /System/Library/ColorSync/Profiles/sRGB\ Profile.icc photo.jpg --out srgb-photo.jpg

# Convert entire folder to JPEG preserving originals in ./originals/
mkdir -p originals
for f in *.heic; do
  cp "$f" originals/
  sips -s format jpeg "$f" --out "${f%.heic}.jpg"
done
```

`sips` invokes the same ImageIO framework that all macOS apps use — identical color handling to Preview.

### ImageMagick

`brew install imagemagick` gives you the `magick` (formerly `convert`, `identify`, `mogrify`) command suite — more powerful than `sips` for compositing, channel manipulation, and batch operations with complex transforms:

```bash
# Identify image metadata
magick identify -verbose photo.heic

# Batch resize to 800px wide with quality 85
magick mogrify -resize 800x -quality 85 -format jpg *.heic

# Composite a watermark
magick photo.jpg watermark.png -gravity SouthEast -geometry +10+10 -composite out.jpg

# Create a contact sheet from a folder of images
magick montage *.jpg -tile 4x4 -geometry 200x200+5+5 contactsheet.jpg

# Strip all metadata
magick photo.jpg -strip stripped.jpg
```

### ffmpeg: The Media Swiss Army Knife

Install: `brew install ffmpeg`

The brew formula is compiled with VideoToolbox support. Key encoding recipes:

```bash
# Probe a media file (essential first step)
ffprobe -v quiet -print_format json -show_format -show_streams video.mp4

# Transcode to HEVC using hardware VideoToolbox encoder
ffmpeg -i input.mp4 -c:v hevc_videotoolbox -q:v 65 -c:a aac output_hevc.mp4

# Hardware-accelerated H.264 encode
ffmpeg -i input.mov -c:v h264_videotoolbox -q:v 50 -c:a copy output_h264.mp4

# Trim without re-encoding (lossless, frame-accurate for keyframe-aligned cuts)
ffmpeg -ss 00:01:30 -to 00:04:45 -i input.mp4 -c copy trimmed.mp4

# Trim with re-encode (frame-accurate but slower)
ffmpeg -i input.mp4 -ss 00:01:30 -to 00:04:45 -c:v hevc_videotoolbox -c:a aac trimmed.mp4

# Extract audio only
ffmpeg -i video.mp4 -vn -c:a aac -b:a 192k audio.m4a

# Extract audio as FLAC
ffmpeg -i video.mp4 -vn -c:a flac audio.flac

# Take a screenshot at a specific timestamp
ffmpeg -i video.mp4 -ss 00:05:23.5 -frames:v 1 frame.png

# Extract one frame per second as PNG sequence
ffmpeg -i video.mp4 -vf fps=1 frames/frame_%04d.png

# Concatenate multiple files (same codec, no re-encode)
# First create a list file:
printf "file 'part1.mp4'\nfile 'part2.mp4'\nfile 'part3.mp4'" > concat_list.txt
ffmpeg -f concat -safe 0 -i concat_list.txt -c copy joined.mp4

# Convert an image sequence to video
ffmpeg -framerate 24 -i frames/frame_%04d.png -c:v hevc_videotoolbox -q:v 60 output.mp4

# Scale to 1080p maintaining aspect ratio
ffmpeg -i input.mp4 -c:v hevc_videotoolbox -vf scale=-2:1080 -q:v 65 -c:a copy 1080p.mp4

# Batch transcode a folder
for f in *.mov; do
  ffmpeg -i "$f" -c:v hevc_videotoolbox -q:v 65 -c:a aac "${f%.mov}.mp4"
done

# Show available VideoToolbox encoders
ffmpeg -encoders 2>/dev/null | grep videotoolbox
```

The `-q:v` flag for VideoToolbox encoders is a quality scale from 0–100 (100 = best quality, highest bitrate); it does not map to a fixed bitrate. For target-bitrate encodes, use `-b:v 8000k` instead.

> 🪟 **Windows contrast:** On Windows, ffmpeg uses NVENC (NVIDIA), QSV (Intel Quick Sync), or AMF (AMD) for hardware acceleration — each requiring vendor-specific flags and driver versions. VideoToolbox on macOS is the sole hardware path, unified across all Apple Silicon Macs, with consistent flags and behavior. No driver management.

### yt-dlp: Download from Anywhere

`brew install yt-dlp` — supports 1000+ sites including YouTube, Vimeo, Twitter/X, Instagram, and more.

```bash
# Download best quality video + audio, merged to mp4
yt-dlp -f "bv*+ba" --merge-output-format mp4 "https://youtube.com/watch?v=VIDEO_ID"

# Download as audio only, convert to mp3
yt-dlp -x --audio-format mp3 --audio-quality 0 "URL"

# Download with metadata and thumbnail embedded
yt-dlp --embed-metadata --embed-thumbnail "URL"

# Download a playlist to a numbered folder
yt-dlp -o "%(playlist_index)s-%(title)s.%(ext)s" "PLAYLIST_URL"

# List available formats
yt-dlp -F "URL"
```

### HandBrake CLI

`brew install handbrake` installs both the GUI (`HandBrake.app`) and `HandBrakeCLI`.

```bash
# Rip/transcode with H.265, auto-crop, RF quality 22
HandBrakeCLI -i input.mkv -o output.mp4 -e x265 --quality 22 --aencoder av_aac

# Use VideoToolbox for hardware H.265
HandBrakeCLI -i input.mkv -o output.mp4 -e vt_h265 --quality 65

# Batch transcode all MKVs in a folder
for f in *.mkv; do
  HandBrakeCLI -i "$f" -o "${f%.mkv}.mp4" -e vt_h265 --quality 65 --aencoder av_aac
done
```

HandBrake is the right tool when you need chapter markers, subtitle burning, or DVD/Blu-ray source handling — areas where ffmpeg is functional but requires complex flags.

### exiftool: Metadata Power Tool

`brew install exiftool`

```bash
# Dump all metadata from a file
exiftool photo.heic

# Dump specific tags
exiftool -GPSLatitude -GPSLongitude -DateTimeOriginal -Make -Model photo.heic

# Dump metadata as JSON
exiftool -json photo.heic

# Dump metadata from all images in a folder
exiftool -r -csv ~/Pictures/*.jpg > metadata.csv

# Strip ALL metadata (writes backup as original_exiftool_bak by default)
exiftool -all= photo.jpg

# Strip all metadata, overwrite original (no backup)
exiftool -all= -overwrite_original photo.jpg

# Strip only GPS data, keep everything else
exiftool -gps:all= photo.jpg

# Copy GPS from one file to another
exiftool -TagsFromFile source.jpg -gps:all target.jpg

# Set date/time (useful for fixing wrong timezone metadata)
exiftool -DateTimeOriginal="2025:06:15 14:30:00" photo.jpg

# Batch rename files by DateTimeOriginal
exiftool -d "%Y%m%d_%H%M%S%%-c.%%e" "-filename<DateTimeOriginal" *.jpg

# Find all images with GPS data in a folder
exiftool -if '$GPSLatitude' -filename -GPSLatitude -GPSLongitude -r ~/Downloads/

# Show the full edit history embedded in an Apple Photos export
exiftool -Apple:all photo.heic

# Verify a file's reported date matches filesystem mtime
exiftool -FileModifyDate -DateTimeOriginal -CreateDate photo.jpg
```

> 🔬 **Forensics note:** The `Apple:ContentIdentifier` field in HEIC files from iPhones ties a still image to its Live Photo `.mov` — both share the same UUID. `Apple:ImageUniqueID` is per-image. `Apple:RunTimeValue` / `Apple:RunTimescale` give the burst capture position. `MakerNotes:* ` block is Apple-proprietary and changes between iOS versions — it can help date a photo to an approximate iOS version even when the system date was altered.

### osxphotos: Full Library CLI

Install: `pipx install osxphotos`

```bash
# Show library summary
osxphotos info

# Query photos (no export — just list)
osxphotos query --json | head -50

# Export all photos organized by date
osxphotos export ~/Downloads/PhotosExport/ --export-by-date

# Export only iPhone 15 Pro shots taken in 2024
osxphotos export ~/Downloads/Export2024/ \
  --year 2024 \
  --device-model "iPhone 15 Pro" \
  --export-by-date

# Export with EXIF written from Photos metadata (for photos that have been edited)
osxphotos export ~/Downloads/Export/ --exiftool

# Export originals only (skip edits)
osxphotos export ~/Downloads/OriginalsOnly/ --original-name

# Export HEIC converted to JPEG
osxphotos export ~/Downloads/JPEGExport/ \
  --convert-to-jpeg \
  --jpeg-quality 0.9

# Export from a specific alternate library
osxphotos export ~/Downloads/AltExport/ \
  --library ~/Pictures/Archive.photoslibrary

# Query photos with GPS and dump to CSV
osxphotos query --has-location --csv > located_photos.csv

# Export photos from a named album
osxphotos export ~/Downloads/VacationAlbum/ --album "Vacation 2025"

# Run a report on what would be exported (dry run)
osxphotos export ~/Downloads/Test/ --dry-run --report report.csv
```

> 🔬 **Forensics note:** `osxphotos query --json` dumps the full Photos database record for each asset — including `hidden`, `trashed`, `shared`, `burst`, `live_photo`, `portrait`, `screenshot`, `screen_recording`, `slow_motion`, `time_lapse`, `panorama`, `hdr`, and `favorite` boolean flags. This is the fastest way to enumerate all screen recordings and screenshots in a Photos library, which is forensically significant because macOS screenshot-to-Photos workflows can silently deposit evidence of screen activity.

---

## Labs

### Lab 1: Batch HEIC → JPEG with sips

**Goal:** Convert a folder of HEIC images to JPEG at 85% quality, then resize all to max 2048px, preserving originals.

> ⚠️ **ADVANCED:** This modifies files. Back up your test folder first. Roll back by deleting the `./jpeg_out/` directory.

```bash
# 1. Create a test working directory with sample HEICs
# (Use your own HEICs or grab some from ~/Pictures via osxphotos)
mkdir -p ~/Downloads/heic_lab/jpeg_out

# If you want sample files from Photos (requires FDA grant):
osxphotos export ~/Downloads/heic_lab/originals/ \
  --limit 20 \
  --skip-edited \
  --original-name

# 2. Batch convert: HEIC → JPEG at 85% quality
for f in ~/Downloads/heic_lab/originals/*.heic ~/Downloads/heic_lab/originals/*.HEIC; do
  [[ -f "$f" ]] || continue
  base=$(basename "${f%.*}")
  sips -s format jpeg -s formatOptions 85 "$f" \
    --out ~/Downloads/heic_lab/jpeg_out/"${base}.jpg"
done

# 3. Resize all output JPEGs to max 2048px (in place)
sips -Z 2048 ~/Downloads/heic_lab/jpeg_out/*.jpg

# 4. Verify: check file sizes and dimensions
sips -g pixelWidth -g pixelHeight -g fileSize ~/Downloads/heic_lab/jpeg_out/*.jpg | \
  paste - - - -

# 5. Compare original vs converted file count
echo "Originals: $(ls ~/Downloads/heic_lab/originals/*.heic 2>/dev/null | wc -l)"
echo "JPEGs:     $(ls ~/Downloads/heic_lab/jpeg_out/*.jpg 2>/dev/null | wc -l)"
```

Expected output: `sips -g` reports `pixelWidth` ≤ 2048 and `pixelHeight` ≤ 2048 for all files. File sizes should be roughly 60–75% of the original HEIC sizes despite HEIC being more efficient — JPEG at 85% on already-compressed images is expected to be slightly larger per pixel.

---

### Lab 2: Transcode and Trim Video with ffmpeg + VideoToolbox

**Goal:** Trim a video to a 90-second clip, transcode it to HEVC using the hardware media engine, and verify the encoder used.

> ⚠️ **ADVANCED:** Transcoding is CPU/GPU intensive. On a long 4K source this may take 30+ seconds even with hardware acceleration. Have at least 2 GB free disk space.

```bash
# 0. Install ffmpeg if not present
brew install ffmpeg

# 1. Create a test video (5 seconds of SMPTE color bars, no source file needed)
ffmpeg -f lavfi -i smptebars=size=1920x1080:rate=24 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -t 300 -c:v h264_videotoolbox -q:v 50 -c:a aac \
  ~/Downloads/test_source.mp4

# 2. Probe the source
ffprobe -v quiet -print_format json -show_streams ~/Downloads/test_source.mp4 | \
  python3 -c "import sys,json; d=json.load(sys.stdin); [print(s['codec_name'], s['width'],'x',s.get('height','')) for s in d['streams']]"

# 3. Trim to 90 seconds using hardware HEVC encoder
ffmpeg -i ~/Downloads/test_source.mp4 \
  -ss 00:00:30 -to 00:02:00 \
  -c:v hevc_videotoolbox -q:v 65 \
  -c:a aac -b:a 128k \
  ~/Downloads/test_trimmed_hevc.mp4

# 4. Verify the output codec
ffprobe -v quiet -print_format json -show_streams ~/Downloads/test_trimmed_hevc.mp4 | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print([(s['codec_name'], s.get('codec_long_name','')) for s in d['streams']])"

# 5. Confirm VideoToolbox was used (look for "hevc_videotoolbox" in encoder tag)
exiftool ~/Downloads/test_trimmed_hevc.mp4 | grep -i "encoder\|handler\|codec"

# 6. Extract a frame at the 45-second mark
ffmpeg -i ~/Downloads/test_trimmed_hevc.mp4 \
  -ss 00:00:45 -frames:v 1 \
  ~/Downloads/test_frame.png

# 7. Verify frame dimensions
sips -g pixelWidth -g pixelHeight ~/Downloads/test_frame.png
```

Expected: Step 4 shows `hevc` / `hvc1`; step 5 shows the encoder tag includes `VideoToolbox`. The trimmed file should be roughly 90/300 × (original size) plus re-encode overhead.

---

### Lab 3: Inspect and Strip Metadata with exiftool

**Goal:** Expose all metadata in an image (including GPS, device fingerprint, edit history), then strip privacy-sensitive fields.

> ⚠️ **ADVANCED:** `exiftool -all=` modifies the file in place (with a backup). Use a copy. Roll back with `mv photo.jpg_original photo.jpg`.

```bash
# 0. Install exiftool
brew install exiftool

# 1. Get a test image (use any iPhone photo or the JPEG from Lab 1)
cp ~/Downloads/heic_lab/jpeg_out/$(ls ~/Downloads/heic_lab/jpeg_out/ | head -1) \
  ~/Downloads/exif_test.jpg

# 2. Dump ALL metadata
exiftool ~/Downloads/exif_test.jpg

# 3. Show only the forensically interesting fields
echo "=== Device Identity ==="
exiftool -Make -Model -LensModel -SerialNumber ~/Downloads/exif_test.jpg

echo "=== Location ==="
exiftool -GPSLatitude -GPSLongitude -GPSAltitude -GPSSpeed ~/Downloads/exif_test.jpg

echo "=== Timestamps ==="
exiftool -DateTimeOriginal -CreateDate -ModifyDate -SubSecTimeOriginal \
  -FileModifyDate ~/Downloads/exif_test.jpg

echo "=== Apple-specific ==="
exiftool -Apple:all ~/Downloads/exif_test.jpg 2>/dev/null

# 4. Check if GPS coordinates are present and decode to decimal degrees
exiftool -n -GPSLatitude -GPSLongitude ~/Downloads/exif_test.jpg

# 5. Strip ONLY GPS data (keep device/date metadata)
cp ~/Downloads/exif_test.jpg ~/Downloads/exif_gps_stripped.jpg
exiftool -gps:all= ~/Downloads/exif_gps_stripped.jpg

# 6. Verify GPS is gone
echo "=== GPS after strip ==="
exiftool -GPSLatitude -GPSLongitude ~/Downloads/exif_gps_stripped.jpg

# 7. Strip ALL metadata from a copy (full privacy scrub)
cp ~/Downloads/exif_test.jpg ~/Downloads/exif_fully_stripped.jpg
exiftool -all= -overwrite_original ~/Downloads/exif_fully_stripped.jpg

# 8. Confirm nothing remains
exiftool ~/Downloads/exif_fully_stripped.jpg | wc -l
# Should be ~5 lines (just file-system attributes, no embedded metadata)

# 9. Batch inspect all JPEGs in a folder — GPS coordinates to CSV
exiftool -csv -n -GPSLatitude -GPSLongitude -DateTimeOriginal \
  ~/Downloads/heic_lab/jpeg_out/*.jpg > ~/Downloads/gps_report.csv
cat ~/Downloads/gps_report.csv
```

---

### Lab 4: Export from Photos with osxphotos

**Goal:** Query the Photos library, find recent screenshots, and export them with full metadata.

> ⚠️ **ADVANCED:** Requires Full Disk Access (FDA) granted to Terminal. Without it, osxphotos cannot open the Photos SQLite database. Grant via System Settings → Privacy & Security → Full Disk Access. Roll back: delete `~/Downloads/osxphotos_lab/`.

```bash
# 0. Install osxphotos (pipx recommended to avoid venv conflicts)
pipx install osxphotos   # or: pip3 install osxphotos

# 1. Verify library access
osxphotos info

# 2. List all screenshots (forensically interesting — reveals screen activity)
osxphotos query --screenshot --json | \
  python3 -c "
import sys, json
assets = json.load(sys.stdin)
for a in assets[:10]:
    print(a['filename'], a['date'], a.get('original_filename',''))
"

# 3. Export last 30 days of photos with GPS, organized by date
osxphotos export ~/Downloads/osxphotos_lab/recent_located/ \
  --has-location \
  --from-date "$(date -v-30d +%Y-%m-%d)" \
  --export-by-date \
  --exiftool \
  --verbose

# 4. Export all screenshots (skip if no screenshots in library)
osxphotos export ~/Downloads/osxphotos_lab/screenshots/ \
  --screenshot \
  --original-name \
  --export-by-date

# 5. Generate a CSV report of everything in the library with key fields
osxphotos query --csv \
  --field filename --field date --field latitude --field longitude \
  --field screenshot --field hidden --field favorite \
  > ~/Downloads/osxphotos_lab/library_report.csv

head -5 ~/Downloads/osxphotos_lab/library_report.csv

# 6. Find all hidden photos
osxphotos query --hidden --json | \
  python3 -c "import sys,json; a=json.load(sys.stdin); print(f'{len(a)} hidden assets')"

# 7. Find all trashed (Recently Deleted) photos
osxphotos query --deleted --json | \
  python3 -c "import sys,json; a=json.load(sys.stdin); print(f'{len(a)} in trash')"
```

Expected: `osxphotos info` prints library path, photo count, and version. The CSV in step 5 has one row per asset with the requested fields. Steps 6–7 are the forensics gold: `--hidden` and `--deleted` access assets the Photos UI buries.

---

## Pitfalls & Gotchas

**sips destroys color profiles on some conversions.** When converting HEIC (Display P3) to JPEG, sips can strip or incorrectly embed the color profile. Always pass `-m /System/Library/ColorSync/Profiles/sRGB Profile.icc` if the destination must be sRGB-safe for web use.

**ffmpeg `-ss` before vs. after `-i` changes behavior.** `-ss` BEFORE `-i` seeks the input stream (fast, but may miss a few frames). `-ss` AFTER `-i` decodes from the start (slow, but frame-accurate). For lossless trims with `-c copy`, always put `-ss` before `-i`; for re-encode trims, put it after.

**VideoToolbox quality scale is not CRF.** The `-q:v` flag for `hevc_videotoolbox` is a percentage-like scale (0–100), not the x265 CRF scale (0–51 inverted). A common mistake is using `-q:v 22` expecting CRF 22 quality — this produces very low quality. Use `-q:v 65`–`80` for most work.

**osxphotos requires Full Disk Access, not just Photos access.** The Photos TCC permission (`com.apple.security.personal-information.photos-library`) only grants access to the Photos *framework* — it doesn't let osxphotos open the SQLite database directly. You need FDA on Terminal.

**exiftool creates `_original` backups by default.** Running `exiftool -all=` leaves `photo.jpg_original` alongside `photo.jpg`. Add `-overwrite_original` to suppress this, but only once you're sure. These backup files clutter export directories and confuse downstream tools that glob `*.jpg`.

**HEIC Live Photos are two files.** A Live Photo is a `.heic` still + a `.mov` motion clip, linked by `ContentIdentifier` UUID. Tools that only copy the `.heic` lose the motion component. `osxphotos export --live-photo` exports both linked files correctly.

**The Photos SQLite WAL file matters.** `Photos.sqlite-wal` (Write-Ahead Log) may contain uncommitted data not yet merged into `Photos.sqlite`. If you're forensically examining the database, you must either allow SQLite to merge the WAL naturally (open with the library closed) or manually apply WAL with `sqlite3 Photos.sqlite ".recover"`. Reading `Photos.sqlite` alone with `Photos.app` running gives you stale data.

**HandBrakeCLI `-e vt_h265` availability depends on macOS version.** The VideoToolbox HEVC encoder option in HandBrake requires macOS 10.13+ and hardware that supports it (all Apple Silicon). Older Intel Macs without HEVC hardware may fall back to software x265 silently.

**Screen recording artifacts in osxphotos.** The `--screenshot` filter matches `com.apple.screenshots.*` UTI, but some screen recordings go into the library as `public.mpeg-4` with no screenshot flag — query `--movie` + a filename pattern or date range as a second pass.

---

## Key Takeaways

- Apple Silicon's dedicated media engines make VideoToolbox-accelerated H.264/HEVC/ProRes transcoding essentially free in CPU terms — use `-c:v hevc_videotoolbox` in ffmpeg universally.
- AV1 hardware *decode* arrived with M3; hardware *encode* is only on M4 Ultra and M5 Pro/Max/Ultra.
- The Photos `.photoslibrary` package is a SQLite database with full edit history, hidden/deleted flags, and ML analysis results — a forensic goldmine accessible via osxphotos with Full Disk Access.
- HEIC files from iPhones contain GPS, device fingerprints, Apple-proprietary maker notes, and Live Photo cross-links — exiftool exposes all of it.
- `sips` handles 90% of image conversion needs with zero installation; ImageMagick and ffmpeg cover the rest.
- The Photos SQLite WAL file contains uncommitted writes — never examine `Photos.sqlite` in isolation if accuracy matters.
- osxphotos `--hidden` and `--deleted` flags expose assets the Photos UI actively buries — essential for forensic library examination.

---

## Terms Introduced

| Term | Meaning |
|---|---|
| VideoToolbox | Apple framework providing hardware-accelerated video encode/decode via the media engine |
| HEIC / HEIF | High Efficiency Image Container / Format — Apple's default photo format since 2017 |
| ProRes | Apple's high-quality mezzanine codec for professional video production |
| WAL (Write-Ahead Log) | SQLite journaling mode file (`.sqlite-wal`) that may hold uncommitted transactions |
| PTP (Picture Transfer Protocol) | USB/IP protocol for camera/device media access, used by Image Capture |
| ISOBMFF | ISO Base Media File Format — the container format shared by MP4, HEIC, and HEIF |
| sips | Scriptable Image Processing System — macOS built-in image batch processor |
| ffprobe | ffmpeg companion tool for media file analysis and stream inspection |
| exiftool | Phil Harvey's metadata read/write tool covering 350+ file formats |
| osxphotos | Python CLI tool that queries the Photos SQLite database directly |
| ICC profile | International Color Consortium profile — defines a color space for a device or image |
| ColorSync | macOS color management framework and daemon |
| Au (Audio Unit) | macOS/iOS native audio plugin format (`.component` bundles) |
| Core Audio | macOS low-latency audio subsystem, running via `coreaudiod` |
| ICA (Image Capture Architecture) | macOS framework for scanner and camera device communication |
| RF quality | Constant quality encoding mode in HandBrake's x264/x265 encoders (lower = better) |
| Mezzanine codec | High-quality intermediate codec for editing (ProRes, DNxHD) vs. delivery codecs (H.265) |
| AV1 | Open, royalty-free video codec by the Alliance for Open Media; hardware decode from M3 |

---

## Further Reading

- [Apple VideoToolbox documentation](https://developer.apple.com/documentation/videotoolbox) — VTCompressionSession / VTDecompressionSession API
- [osxphotos documentation](https://rhettbull.github.io/osxphotos/) — full CLI and Python API reference
- [ffmpeg VideoToolbox wiki](https://trac.ffmpeg.org/wiki/HWAccelIntro#VideoToolboxMacOSX) — encoder/decoder flag reference
- [Phil Harvey's exiftool documentation](https://exiftool.org/) — complete tag list including Apple maker notes
- [Howard Oakley — Eclectic Light Company: HEIC internals](https://eclecticlight.co/2018/09/24/heif-heic-and-high-quality-images/) — deep dive into the ISOBMFF container
- Apple Platform Security guide (download from apple.com/privacy/) — TCC architecture, Photos access
- `man sips` — full flag reference including color management options
- [[part-05-security-forensics/03-forensic-artifacts]] — broader artifacts context
- [[part-02-gui/07-quick-look-and-preview]] — Preview.app deep dive
- [[part-02-gui/08-screenshots-and-screen-recording]] — screen recording mechanics
- [[part-05-security-forensics/02-tcc-and-privacy]] — TCC permission gating for Photos/FDA
