# PurpleReel Changelog

PurpleReel uses a build-number-as-version scheme — every commit
bumps the bundle version (`0.1.<git-commit-count>`) via
`build-app.sh`. There are no tagged releases yet, so each section
below is a "milestone" rather than a version. The current build
number is stamped into the app at `About → Version`.

Newest first.

---

## Sprint 10 (in progress) — Convert dialog + right-click reshape

Multi-commit restructure to match Kyno's Convert / Combine / Export
Subclips UX (per user screenshots showing ~120 presets across 8
buckets + per-channel Copy/Re-encode controls + tabbed Settings…
editor for Encoding / Filters / LUTs / Overlays / Container).

### C7 — Right-click polish (Rejected / Send to Resolve / Pre-analyze / richer Open With)

Closes 4 of 5 Kyno-parity gaps surfaced by the right-click screenshots
(Images #94-#102). Camera/Creative LUT split deferred to a follow-up
because it needs a real `clip_metadata` schema migration.

**Rejected rating state** (Image #98). Sentinel `stars = -1` rather
than a schema migration — the `rating` table's `stars: Int` column
already accepts any value, so the existing row layout carries it
straight through.

- `AssetContextMenu.metadataSection` Rating submenu adds a
  Rejected entry alongside the 5 stars + Unrated.
- `PurpleReelApp.swift` Metadata → Rating menu mirrors the new shape.
- `BrowserView.ratingDots(_:)` renders rejected clips as a single
  red `xmark.circle.fill` instead of a star row.
- `ReportExporter.csvRow` / `htmlRow` emit the literal `Rejected`
  string when stars < 0, preventing
  `String(repeating: "★", count: -1)` crashes.
- `≥ N stars` filters naturally exclude rejected clips because any
  positive threshold rejects -1.
- 3 new tests (`RejectedRatingTests`) covering label rendering,
  Codable round-trip with negative stars, and filter exclusion.

**Send To → DaVinci Resolve** (Image #100). New entry in the right-
click Send To submenu. Looks up the Resolve bundle ID
(`com.blackmagic-design.DaVinciResolve` or `.DaVinciResolveStudio`)
via `NSWorkspace.urlForApplication(withBundleIdentifier:)` and hides
the entry when neither is installed. Multi-selection lands as a
single `open` call so Resolve imports them as one batch into the
Media Pool.

Ships menu-only (no shortcut). Kyno binds ⌘⇧D to this but
PurpleReel's Sprint-1 Kyno-compat alias already wires ⌘⇧D to the
drilldown toggle — pinning the same combo here would silently break
one of the two.

**Pre-analyze** (Image #97). New menu item under the AI section in
the right-click menu (mirrors Kyno's bottom-of-menu placement).
Walks the multi-selection (or the single active clip), re-runs
`MediaScanner.loadAVTech` for each, applies the refreshed
duration / codec / dims / fps / audio codec / recordedAt / isVFR
fields, and writes the updated rows back to the DB. Useful after the
user has fixed source-file metadata out-of-band (corrected the
camera clock, repaired a partial container, etc.) without doing a
full workspace rescan.

`MediaScanner.loadAVTech` / `applyAVTech` / `AVTech` struct dropped
their `fileprivate` keywords so `AppState.preAnalyzeSelected()` can
call into them without duplicating probe logic.

**Richer Open With** (Image #99). The 8-handler cap was clipping
common video apps (Compressor, Pixelmator Pro, VLC) when a user had
a dozen+ installed. Bumped to 20 — NSWorkspace already sorts by
relevance, so the most likely-useful apps still appear first.

**Camera LUT + Creative LUT split** — *deferred*. The dual-slot UI
already lives in C5's VideoSettingsSheet LUTs tab, but persisting
per-clip Camera vs Creative selections needs a `clip_metadata`
schema migration (two new columns) plus repath through the player /
transcode pipelines. Tracked as the C7 follow-up; right-click
Camera LUT / Creative LUT submenus will ship alongside it.

3 new tests (RejectedRatingTests); full suite green.

---

### C6 — Non-modal Transcode Queue window

Original complaint that kicked off this whole reshape (Image #77 →
#78): the Transcode Queue was a `.sheet` on the main window, which
blocked all other interaction while jobs ran. C6 promotes it to a
stand-alone `Window` scene that floats independently.

**Window scene** added in `PurpleReelApp.swift`:

    Window("Transcode Queue", id: "transcode-queue") {
        TranscodeQueueView(queue: appState.transcodeQueue)
            …
    }
    .defaultSize(width: 640, height: 480)
    .commandsRemoved()

`.commandsRemoved()` keeps a "New Transcode Queue" entry out of the
File menu (we never want a second one).

**Trigger mechanics** — the existing
`@Published var transcodeSheetVisible` boolean is now treated as an
"open me" *pulse*: when it flips to true, ContentView's `.onChange`
handler calls `openWindow(id: "transcode-queue")` and immediately
resets the flag so the next enqueue (or the next manual menu click)
can re-fire. Idempotent — `openWindow` brings an existing window to
front rather than spawning duplicates.

**Status indicator chip** in the main window's toolbar
(`.placement(.status)`): a small Capsule with the spin-icon + "N
jobs" label, only renders when `running + pending > 0`. Clicking it
brings the floating Queue window back to the front. Live-updates as
the queue's @Published lists change.

**Queue view** updates:
- `@Environment(\.dismissWindow)` instead of `\.dismiss` so the
  Close button targets the right window.
- Existing "Show Queue…" menu item still functions — it just
  triggers the same boolean pulse the auto-open does.

Net result: queue lives in its own window. App stays usable.
Multiple transcodes can run in the background while you keep
browsing, logging, even queueing more jobs.

---

### C5 — Per-channel composable editing (Settings… tabbed editor)

Convert dialog's per-channel rows are now **functional**:
File format / Video / Audio / Trimming dropdowns edit the live
`TranscodeOptions`, and the Settings… buttons open three new sheets
that bind through the same state. When the user diverges from the
preset's defaults the job runs through C3's composable runtime
instead of the legacy preset path.

**New file** `Sources/PurpleReel/Models/TranscodePreset+Options.swift`
materializes a starting `TranscodeOptions` from any existing preset's
`avPresetName` / `ffmpegArgs`:

- AVAssetExportSession constants → matching VideoCodec + size
  (pass-through → copy/copy; size-keyed presets pick the right
  `.fixed(W, H)`; ProRes 422 / 4444 constants map to their codecs)
- ffmpeg recipes → sniff `-c:v <codec>` + `-profile:v` + `-b:v` /
  `-crf` out of the argv. `dnxhd` with `dnxhr_*` profile maps to
  `.dnxhr`; bare `dnxhd` stays `.dnxhd`. Bitrate parser handles
  `220M` / `192k` / plain integers.
- Audio extracted from `-c:a <codec>` + `-b:a <kbps>`. Audio-only
  recipes (`-vn` present) collapse video channel to `.disabled` and
  container to `.audioOnly`.

**New sheets**:

- `Views/ContainerSettingsSheet.swift` — File & Container Settings
  flyout (Image #85). Streamability, keep-source-timestamps,
  timecode source (fromSource / zeroBased / custom), embed XMP.
- `Views/AudioSettingsSheet.swift` — Audio codec picker, sample
  rate (44.1 / 48 / 96 kHz), bitrate (128 / 192 / 256 / 320 kbit/s).
  Renders a "switch the channel to Re-Encode first" message when the
  audio channel is `.copy` or `.disabled`.
- `Views/VideoSettingsSheet.swift` — Tabbed editor matching Kyno's
  Video Settings flyout (Images #80-#84, #86):
  - **Encoding**: Codec, Frame rate (Like Source + standard cinema
    rates), Size (Like Source + standard ladder + Half/Quarter),
    Quality (Codec Default / Bitrate / CRF — the latter two with
    inline editors).
  - **Filters**: Denoise, Sharpen/Blur (luma+chroma radius +
    strength sliders), Add noise (luma+chroma), Fade in/out
    steppers.
  - **LUTs**: Camera LUT + Creative LUT selection (None /
    Automatic / Sidecar / As Defined in Player). Custom-file
    selection wires in via a follow-up.
  - **Overlays**: Timecode toggle, size (small / regular / large),
    9-position grid picker, opacity slider.

**ConvertSheet plumbing**:

- New `@State editableOptions: TranscodeOptions` seeded on first
  render from `state.preset.defaultOptions()`.
- New `@State optionsBaseline: TranscodeOptions` snapshot of the
  same seed, so `isEdited` is "diff vs baseline" instead of "diff
  vs `TranscodeOptions()`".
- Per-channel `Picker` bindings (Copy / Re-Encode / Off) for video
  and audio; switching to Re-Encode restores the baseline's encoding
  shape if it had one, else defaults to H.264 / AAC.
- Container Picker (MOV / MP4 / MKV / MXF / Audio Only) wired.
- Trimming Picker (None / In - Out) wired.
- "(edited)" indicator + new "Reset" button that snaps everything
  back to the baseline.

**AppState routing** — `confirmConvert(_:editedOptions:)` now takes
an optional `TranscodeOptions`. When non-nil the job runs through
`TranscodeJob(source:options:outputURL:displayName:fadeInSeconds:
fadeOutSeconds:tcBurnIn:)` (C3); when nil the legacy
`TranscodeJob(source:preset:...)` path runs. ConvertSheet's Start
button passes `editableOptions` when it differs from baseline.

11 new tests (`PresetDefaultOptionsTests`) covering Apple-native
preset → options mapping (H.264 / HEVC / ProRes 422 / passthrough),
ffmpeg preset → options mapping (DNxHR / DNxHD with bitrate
extraction / Cineform / ProRes Proxy via `-profile:v 0`), audio-only
preset mapping (Wav → pcm16 + audioOnly + video disabled; M4A →
aac + carries bitrate), plus a coverage probe that asserts every
non-passthrough non-rewrap preset maps to a non-default options
shape (catches future codec gaps).

---

### C4 — Convert dialog UI restructure (Kyno-shaped layout)

ConvertSheet rebuilt to match Kyno's compact layout per the user's
reference screenshots. The runner stays on the legacy preset path;
the new composable execution path (C3) wires in during C5 alongside
the per-channel Settings… tabbed editor.

**Destination section** stays at top, plus:

- **File name pattern** Picker — `Original name + Suffix` (legacy
  default, sticks for upgrade compat), `Original name + Transcoding
  Preset` (Kyno default, e.g. `clip-H2641080p.mp4`), `Original name`.
  Persisted under `UserDefaults["convertFilenamePattern"]`.
- **Example** preview — live filename for the first asset under the
  current pattern + preset (`stem(from:preset:pattern:)` runs the
  same logic the actual job runner does, with no disk dependency).
- **Collision warning row** — counts how many output paths already
  exist on disk and surfaces `"N warnings: Would overwrite existing
  file"` in orange with a triangle icon. When `skipExisting` is on,
  appends `(will be skipped)` so the user knows nothing destructive
  is queued.
- **More Options** disclosure — collapses fades + TC burn-in by
  default so the main dialog footprint matches Kyno's; expanding
  reveals the same controls PurpleReel has always shipped.

**Conversion Preset section** rebuilt with:

- Header: `Conversion Preset: <name>` + `(edited)` indicator (today
  fires when filename pattern diverges from the legacy default — the
  C5 full options editor will pipe more deltas through it) + gear
  icon with help tooltip (preset Save As / Reset land in C5).
- Per-channel grid rows: **File format / Video / Audio / Trimming**
  each showing the preset's effective value + a short descriptor
  (`Streamable, Source Timecode` / `Do not re-encode` / `H.264 1080p,
  Size Like Source` etc.) + a `Settings…` button that's disabled
  with a tooltip flagging C5.

**TranscodeService changes**:

- New `stem(from:preset:pattern:) -> String` pulled out so the
  Convert dialog's Example preview can render filenames without
  hitting the filesystem.
- New `outputURL(for:preset:in:pattern:)` overload routes the
  pattern through to the actual collision-resolving URL builder.
  Legacy `outputURL(for:preset:in:)` delegates with
  `.originalPlusSuffix` so existing callers see no change.
- `confirmConvert(_:)` and `openConvertDialog(preset:)` thread the
  sticky pattern through.

9 new tests (`FilenamePatternTests`) covering stem construction for
each pattern, slug stripping (parens / dots / spaces / slashes),
default = `.originalPlusSuffix`, rawValue round-trip for the sticky
persistence, and `outputURL` collision-counter behavior.

USER_MANUAL update deferred to C5 (when the full options-edit story
is in place — current dialog is a UI restructure, not new user-facing
capability beyond the filename pattern picker).

---

### C3 — Composable runtime (TranscodeOptions → executable backend)

Bridge between the new composable spec (C1 / `TranscodeOptions`) and
the existing `TranscodeJob` runner. The smallest possible change:

- **New file** `Sources/PurpleReel/Services/TranscodeOptionsResolver.swift`
  ships a `TranscodeOptions.resolveBackend() -> ResolvedBackend` that
  picks the right executor.
- **`ResolvedBackend` enum** matches the two paths `TranscodeJob` already
  handles: `.avAssetExport(presetName, ext, alwaysAvailable)` or
  `.ffmpeg(args, ext)`.

Routing strategy:

1. **video = .copy + audio = .copy** → `AVAssetExportPresetPassthrough`
   (container rewrap; always available).
2. **container = .audioOnly OR video = .disabled** → ffmpeg with `-vn`
   + audio codec args. Extension follows the codec (Wav, AIFF, M4A,
   MP3, MP2 → wav / aiff / m4a / mp3 / mp2).
3. **video = .reencode(VideoEncoding) + codec.isAppleNative**:
   - H.264 → size-keyed `AVAssetExportPreset…` (likeSource →
     HighestQuality; 1280×720 → 1280x720; 1920×1080 → 1920x1080;
     3840×2160 → 3840x2160; sub-720 → 640x480)
   - HEVC → likeSource → HEVCHighestQuality; 4K → HEVC3840x2160;
     else HEVC1920x1080
   - ProRes 422 / 4444 → the matching `AppleProRes…LPCM` constant
   - ProRes 422 HQ / LT / Proxy → **fall through** to ffmpeg
     (`prores_ks` profile 3/1/0); no Apple constants on macOS
4. **video = .reencode** otherwise → ffmpeg with codec-specific recipe.
   DNxHR → `-c:v dnxhd -profile:v dnxhr_*` + `yuv422p` (HQ) or
   `yuv422p10le` (HQX) or `yuv444p10le` (444). VP8/VP9 → `libvpx` /
   `libvpx-vp9` → `webm`. FLV → `flv`. WMV → `wmv2`.
5. **video = .copy + audio = .reencode** → ffmpeg with `-c:v copy` +
   audio recipe.

Filter chain limited for now to `-vf scale=…` when size is fixed or
fractional. Denoise / sharpen / fade-in-out / TC overlay all stay on
the AVFoundation composition path (`TranscodeJob.applyComposition`)
and are NOT yet baked into the ffmpeg argv. C5 will add the full
`-vf` chain.

**New `TranscodeJob` convenience init** accepts `TranscodeOptions`
directly:

    TranscodeJob(source: url, options: opts, outputURL: out,
                 displayName: "DNxHR HQ 23.98")

Builds a synthetic single-use `TranscodePreset` wrapping the
resolved backend, then defers to the existing designated initializer.
Synthetic preset is never persisted — it's a one-shot adapter so the
AVAssetExportSession branch / ffmpeg branch / progress polling /
cancellation flow downstream unchanged.

14 new tests (`TranscodeOptionsResolverTests`):
- Pass-through routing for copy/copy in MOV + MP4
- H.264 size routing (1080p → 1920x1080 preset; 4K → 3840x2160;
  likeSource → HighestQuality)
- HEVC 4K routing → HEVC3840x2160
- ProRes 422 → AppleProRes422LPCM (alwaysAvailable = true)
- ProRes 422 HQ falls through to ffmpeg `prores_ks` profile 3
- DNxHR routes to ffmpeg `dnxhd` encoder with `dnxhr_hq` profile +
  `yuv422p`
- VP9 routes to `libvpx-vp9` with webm extension + carries -b:v
- Audio-only PCM 16-bit routes to ffmpeg with `-vn` + `pcm_s16le` +
  wav extension
- Audio-only MP3 routes to `libmp3lame` + carries bitrate + mp3
  extension
- Fixed size emits `-vf scale=W:H`
- Half-scale emits `-vf scale='trunc(iw/2.0/2)*2':-2` (even-rounding)

Foundation for C4 (new Convert dialog) and C5 (tabbed Settings…
editor). No user-visible behavior change in this commit — the new
init is dormant until C4 surfaces it.

---

### C2 — Extended preset catalog (~50 new presets)

`Sources/PurpleReel/Models/PresetCatalog.swift` ships a curated
extended catalog wired into `TranscodePreset.combined()` so the
right-click Convert / Combine / Export Subclips menus immediately
gain Kyno-shaped coverage across all 8 categories:

- **Audio (10)**: Wav 16/24/32, AIFF 16/32, M4A 128/192/256,
  MP3 128/256. All ffmpeg-routed with `-vn` so no video stream
  leaks into the audio container.
- **Distribution extras (6)**: H.264 480p, HEVC 4K UHD, Flash
  Video (FLV), WMV HQ, WebM VP8/Vorbis, WebM VP9/Vorbis.
- **DNxHD (10)**: bitrate ladder × framerates DITs actually
  deliver (23.98 / 25 / 29.97 / 50 / 59.94 fps at 115-440 Mbps).
- **DNxHR (9)**: HQ + HQX + 444 across UHD and 4K at 23.98 /
  29.97 / 50 fps. ffmpeg's `dnxhr_*` profiles are resolution-
  independent; the menu name carries the resolution for legibility.
- **Editing extras (6)**: ProRes 422 HQ / LT / Proxy / 4444
  (via ffmpeg `prores_ks` profile 0-4; AVAssetExportSession
  doesn't expose these as preset constants on macOS), Photo
  JPEG, V210 Uncompressed.
- **Proxies (7)**: H.264 Web Proxy 1080/720/540 × LQ/HQ,
  ProRes Editing Proxy 1080/720. Augments the existing
  smart-proxy half/quarter.
- **Web extras (2)**: HEVC 8K UHD (via Highest Quality preset),
  HEVC 720p.
- **Rewrap variants (2)**: Rewrap to MOV, Rewrap to MXF.

Every preset is executable today — Apple-native codecs (H.264 /
HEVC) use AVAssetExportSession preset names; everything else
uses ffmpeg with the same `{IN}` / `{OUT}` placeholder
substitution the existing built-ins use.

Curated, not exhaustive. Kyno ships ~28 DNxHD and ~30 DNxHR
variants; the long-tail entries are 1-2-per-decade deliveries
that we can surface via "Save as Preset…" once C4 lands.

9 new tests (`PresetCatalogTests`):
- Catalog ships non-empty
- IDs disjoint from legacy `TranscodePreset.all`
- IDs unique within catalog
- Every TranscodeCategory has ≥1 preset (so no submenu collapses)
- `combined()` is a strict superset of `all` + extended
- Every preset is executable (has avPresetName OR ffmpegArgs)
- All ffmpeg recipes carry `{IN}` / `{OUT}` placeholders
- Audio presets all include `-vn` (no video stream)
- Extended catalog reports `isCustom = true` (since IDs aren't
  in `builtInIDs` — pinned behavior for this commit)

No menu code changed — `AssetContextMenu.convertSubmenuContents`
already iterates `TranscodeCategory.allCases` and calls
`TranscodePreset.byCategory(_:)`, which routes through
`combined()`. So the new presets auto-surface in the right
submenus. Right-click any clip → Convert / Combine / Export
Subclips submenus now show the full Kyno-style tree.

C3 next: rebuild TranscodeJob to read TranscodeOptions directly
so per-channel Copy/Re-encode + filter chain + per-channel
settings dialogs can drive the runtime.

---

### C1 — TranscodeOptions composable model

New `Sources/PurpleReel/Models/TranscodeOptions.swift` introduces the
foundation value type that the new Convert dialog will edit
field-by-field and the new job runner will execute against:

- **ContainerFormat** — MOV / MP4 / MKV / MXF / audioOnly.
- **VideoChannel** — Copy / Disabled / Reencode(VideoEncoding) where
  VideoEncoding carries codec + profile + frame rate + size + display
  AR + rotation + field type + quality (codecDefault / bitrate(kbps) /
  crf(value)).
- **VideoCodec** — H.264, HEVC, the ProRes family, DNxHD/HR, Cineform,
  MPEG-4, Photo JPEG, V210, VP8 / VP9, Flash Video, WMV. Each carries
  `displayName` + `isAppleNative` so the C3 job-runner can route to
  AVAssetExportSession vs AVAssetWriter vs ffmpeg.
- **AudioChannel** + **AudioEncoding** — Copy / Disabled / Reencode
  with codec (AAC, ALAC, PCM 16/24/32, MP3, MP2, Vorbis) + sample
  rate + bitrate.
- **FilterChain** — Denoise, SharpenBlur (luma+chroma radius+strength),
  AddNoise (luma+chroma), fade in / out seconds.
- **LUTSelection** — none / automatic / sidecarIfPresent /
  asDefinedInPlayer / file(path). Stored separately for Camera LUT
  (input correction) and Creative LUT (look) per Kyno's split.
- **OverlaySettings** — TC overlay enable + size + 9-position grid +
  opacity.
- **ContainerSettings** — streamable, keep source timestamps,
  timecode source (fromSourceIfAvailable / zeroBased / custom), embed
  XMP metadata.
- **Trimming** — none / inToOut.

Everything is Codable + Equatable + Hashable so the model can carry
custom-preset persistence and live edit state without manual
serialization plumbing. 9 tests covering defaults, equality, full
JSON round-trip with every nested type populated, default bitrate /
codec values, Apple-native routing classification, and the 9-cell
overlay grid coverage.

This commit ships the foundation only — no UI changes, no
TranscodePreset migration yet. Existing transcode behavior unchanged.
Next commit (C2) will migrate TranscodePreset to embed
TranscodeOptions and add the ~100 missing preset entries.

---

## Sprint 9 — Excel (XLSX) report with embedded thumbnails

File → Export Report → **Excel (XLSX, with thumbnails)…** —
producer / AE deliverable with one row per clip and a JPEG
thumbnail anchored over the first column. Closes Kyno-parity
rows 16/24 (Excel report with thumbnails was the single most
common producer ask in the Kyno feature surveys).

- New `Services/XLSXReportWriter.swift` builds the OOXML structure
  (the 8 XML parts + `xl/media/imageN.jpeg`) into a temp directory
  and shells out to `/usr/bin/zip -r -X -q` to seal the `.xlsx`.
  Pure Swift otherwise — no XLSX library dependency.
- Cell strings inlined via `<c t="inlineStr">` so there's no
  `sharedStrings.xml` to maintain.
- Image anchors via `<xdr:oneCellAnchor>` in `drawing1.xml` —
  each thumbnail pinned to its asset's row at the top-left, sized
  in EMU (9525 EMU per pixel at 96dpi). 120px-wide thumbnails;
  height computed from the asset's actual pixel aspect ratio
  (falls back to 16:9). Row heights bumped to ~51pt so the image
  doesn't crowd the gridlines.
- Filenames XML-escaped (`&`, `<`, `>`, `"`, `'`) so a clip named
  `weird<&>name.mov` produces valid XML, not garbage.
- 5 new tests (`XLSXReportWriterTests`) covering: empty-list valid
  workbook, content-types declares spreadsheetml MIME, sheet
  contains header + asset filenames, special characters escape
  correctly, no drawing reference when there are no thumbs.
- File menu → Export Report submenu now lists three formats:
  CSV, HTML (with thumbnails), Excel (XLSX, with thumbnails).
- USER_MANUAL gets a new "## Reports — Producer / AE
  deliverables" section documenting all three formats and the
  23-column schema.

---

## Sprint 8 — Hover-scrub polish (more frames + SMPTE TC tooltip)

Hover-scrub thumbnails (Kyno-parity row 67) were already shipped in
both List view (`ThumbnailCell`) and Grid view (`GridCell`). This pass
polishes them.

- **Strip granularity 12 → 20 frames.** `ThumbnailService.defaultFrameCount`
  bumped so scrubbing a long clip is noticeably finer. Cache key encodes
  the count, so old 12-frame strips stay on disk as orphans and the
  next hover regenerates a 20-frame strip. `ClipDetailInline.GridCell`
  switched from a hard-coded `count: 12` to the default so all hover
  surfaces share the same granularity.
- **SMPTE timecode tooltip during hover.** Both cells now show the
  clip-time at the cursor position (e.g. `00:01:23:15`) as a small
  monospaced overlay near the top of the cell. Uses
  `Timecode.format(seconds: dur * frac, fps: ...)` with the asset's
  duration + frame rate (defaults fps to 30 when missing).
- **Tick-row cleanup.** `ThumbnailCell` previously inferred the active
  frame index by round-tripping `loadedImage.tiffRepresentation`
  against every URL in the strip (O(N) heavy comparison per render).
  Replaced with a state-tracked `activeIdx` mutated in `loadFrame(at:)`.

---

## Sprint 7 — Dark mode (Settings → Appearance)

User-facing appearance picker in Settings → General → Appearance:
**Match System / Light / Dark** (segmented Picker). The pick lives
in UserDefaults under the `appearance` key.

Applied on two layers so the entire window stays consistent —
SwiftUI's `.preferredColorScheme(...)` only retints SwiftUI surfaces;
title bars, NSOpenPanel, NSSavePanel, NSAlert, and any AppKit chrome
keep following `NSApp.appearance`.

- **SwiftUI**: `.preferredColorScheme(preferredColorScheme)` applied
  to the WindowGroup root AND the Settings scene root. The shared
  helper maps `"light" → .light`, `"dark" → .dark`, `"system" → nil`.
- **AppKit**: `AppDelegate.applyAppearance()` mirrors the same pick
  onto `NSApp.appearance` (`.aqua` / `.darkAqua` / `nil`). Observes
  `UserDefaults.didChangeNotification` and re-applies on every flip,
  gated on a value-changed check so unrelated defaults writes don't
  thrash the appearance.

USER_MANUAL: documented under Settings → General → Appearance.

---

## Sprint 6 — Sprint 2 verification + zero-based TC honesty

Sweep of the 15 items in `KYNO_RESEARCH.md`'s Sprint-2 ("Migration
safety net + standalone Smalls") block. Reconnaissance confirmed
all 15 are already wired in trunk:

- Find Lost Metadata, Paste Metadata, Play-All-Selected, Incremental
  transcoding (`AppState.confirmConvert` skip-existing check), shift-
  click hard refresh (`ContentView.swift` modifier detect), smart
  proxy auto-scale presets, Date Recorded/Created columns, Display
  size + Aspect ratio columns, LUT-on-frame-export default, audio
  channel names field, subclip name-collision auto-disambiguate,
  file-count safety-limit warning, transcoder file-timestamp
  preservation, fade in/out.

Only honesty gap was the Settings → Advanced → "Use zero-based
timecode" toggle, which read its UserDefaults key into `_`
(literally discarded the result) in `Timecode.format(seconds:fps:)`.
Today every clip already starts at 00:00:00:00 because the formatter
gets seconds-from-start as input — so the toggle had no observable
effect. Surprises users who flip it expecting a behavior change.

- **Timecode.swift**: removed the dead `_ = UserDefaults...` placeholder
  read; trimmed the surrounding comment to clarify that
  `useZeroBasedTimecode` is reserved for a future container-TC build.
- **SettingsView (Advanced → Timecode)**: added a caption under the
  toggle telling users it's reserved for container-embedded source TC
  surfacing, so they don't think it's broken.

---

## Sprint 5 — Coming-from-Kyno polish

Verification + final polish on the Kyno compatibility bundle that
shipped across Sprints 1-4. Confirmed all 12 keyboard / sort / label
items in `KYNO_RESEARCH.md`'s "Recommended starting sprint" are now
wired end-to-end (preset, first-launch sheet, Settings toggle, menu
bindings, shortcuts catalogue).

- **Detail-view clip stepper visible affordance.** `ClipDetailInline`
  header now shows ◀ / ▶ chevron buttons next to the filename,
  disabled at the ends of the displayed list. The ⌘← / ⌘→ keybindings
  remained as before (wired in `PurpleReelApp.swift`'s View menu) — the
  chevrons just make the feature discoverable for users who didn't
  read the Kyno-compat sheet.
- **Shortcuts catalogue + cheat-sheet.** Added the previously-missing
  ⌘← / ⌘→ "Previous / Next clip" entries to `Help/Shortcuts.swift`
  under the Browser group; cheat-sheet and `SHORTCUTS.md` now show
  them.
- **First-launch sheet copy.** `ComingFromKynoSheet`'s "regardless of
  your choice" paragraph now lists ⌘← / ⌘→ alongside the rest of the
  Kyno-familiar bindings.

---

## Sprint 3-4 — Kyno parity closeout (Medium + Large rows)

A run through every remaining Kyno parity item in `KYNO_RESEARCH.md`.
Builds 327 → 348. Canonical status: `KYNO_RESEARCH.md` (per-row), this
section is the user-facing rollup.

### Medium bucket (rows 10, 11, 14, 15, 18, 27, 28, 41, 47, 52, 61,
68, 80)

- **Timecode burn-in during transcode** (row 10). Convert dialog →
  "Burn timecode into video". `TranscodeJob.applyComposition` switches
  to a CIFilter-handler videoComposition that runs the opacity ramp +
  per-frame TC overlay in one pass.
- **LUT auto-detection** (row 11). `LUTLibraryService` walks PurpleReel
  + FCP `*.fcpbundle` + Resolve LUT roots; `PlayerController.load`
  matches filename keywords (`SLog3` / `V-Log` / `LogC` / `HLG` etc.)
  and auto-applies. Settings → General → "Auto-apply suggested LUT".
- **Folder-tree metadata transfer** (row 14). File → "Transfer Metadata
  Between Folders…" copies clip_metadata + rating + tags across two
  folders matched by filename + size.
- **Batch export frames at every marker, with LUT baked in** (row 15).
  Playback → "Export Frames at Markers…" (⌥⌘⇧E). One PNG per marker,
  filename embeds `HHMMSS_FFf_<note-slug>`.
- **Excel/CSV report with thumbnails** (row 16). File → Export Report
  → CSV / HTML. HTML embeds the middle-frame thumbnail per row as
  base64 PNG; CSV writes 22 columns with RFC 4180 escaping.
- **Paste & rename** (row 18). File → "Paste with Rename…" (⌘⇧V) reads
  file URLs from NSPasteboard, applies a `{date}_{orig}{ext}` template,
  copies into a chosen folder.
- **AND / OR filter combine mode** (row 27). `filterMatchMode` AppStorage
  flips active-filter set between AND and OR. Pills bar exposes the
  chip.
- **VFR vs CFR filter** (row 28). v5 schema adds `asset.isVFR`.
  MediaScanner detects via `nominalFrameRate` vs `minFrameDuration`
  (>10% gap = VFR). Filter → Frame Rate → CFR / VFR / Unknown.
- **Poster-frame keyboard P** (row 41). v6 schema adds
  `asset.posterFrameSeconds`. P key captures the playhead; ⇧P clears.
  `ThumbnailService.posterFrame(for:seconds:)` caches one frame per
  (path, modtime, seconds). Grid + List cells render the poster as the
  at-rest frame; hover-scrub still uses the 12-frame strip.
- **Edit Tags ⌘⇧T + autocomplete** (rows 25, 47). `BatchTagEditorSheet`
  shows union-of-selection tags with "partial" badges, autocomplete
  from known tag names, additive add / batch remove.
- **Pitch-preserved playback at 0.5/0.75/1.25/1.5/2×** (row 52).
  `item.audioTimePitchAlgorithm = .spectral`. Playback → Speed
  sub-menu.
- **C4 IDs + ASC-MHL v2.0** (row 61). `HashAlgorithm.c4` = SHA-512
  base58-with-c4-prefix. New `ASCMHLWriter` emits the Netflix-required
  v2.0 schema. `BackupJob.mhlFormat` picks legacy vs ASC-MHL.
- **Live waveform column in the list view** (row 68). Optional
  `ListColumn.waveform`. `WaveformService.cachedOrGenerate` caches
  peaks as JSON keyed by (path, modtime, bucketCount).
- **Kyno `.LP_Store/` XML import** (row 80). Metadata → "Import from
  Kyno (.LP_Store)…" recursively walks the chosen root and parses
  sidecar XMLs with a permissive XMLParserDelegate (accepts
  schema-drift synonyms — `<asset>`/`<clip>`/`<file>`,
  `<rating>`/`<stars>`, `<tag>`/`<keyword>`).

### Large bucket (rows 5, 7, 8, 29, 57, 66)

- **FCPXML re-import / round-trip** (row 5). Metadata → "Import
  FCPXML…". `FCPXMLImportService.importXML(at:db:)` parses 1.8-1.11
  with a permissive XMLParserDelegate. Match strategy: full URL-decoded
  path → filename fallback. Merge is additive — markers de-duped by
  ±1/fps + note, keywords union as tags, FCP `favorite` raises rating
  to 5★ but never demotes, `<metadata><md/>` fills empty log fields
  only.
- **Combine multiple clips** (row 8). Convert → "Combine Clips…" (⌘⇧J).
  `CombineClipsJob.run()` builds an `AVMutableComposition`, inserts
  video + audio at a running CMTime cursor, copies the first clip's
  `preferredTransform` + `naturalSize` so portrait phone footage stays
  upright, exports via AVAssetExportSession.
- **Shared workspace cache for NAS / SAN** (row 7). Off by default.
  Settings → General → "Write shared metadata cache next to media".
  `<dir>/.purplereel/<filename>.json` per clip carries technical + user
  metadata. MediaScanner's read path checks `loadIfFresh(for:)` first
  and skips AVAsset probes on hit. After scan, `hydrateUserMetadataFromCache`
  runs the user portion through additive merge.
- **Spanned-clip detection** (row 29). `SpanDetectionService.detect(in:)`
  pure-Swift heuristic: same-dir + same-ext + matching tech specs +
  sequential trailing digits (MVI_0001/MVI_0002, C0001/C0002,
  00000/00001) + modtime within 120s. New "Spanned Clips" sidebar
  section; right-click → "Combine Segments…" opens the row-8 sheet
  pre-populated.
- **Centralized cross-volume offline search** (row 57). v7 schema adds
  `asset.volumeUUID` (indexed) + `asset.volumeLabel`. Catalogue persists
  across unmounts; cells fade-overlay + cloud-slash badge offline
  assets. Filter → "Volume / Online status" → Online / Offline.
  `VolumeWatcher.handleMounted` calls `AppState.reconnectVolume(...)`
  to re-anchor paths after a remount renames the volume.
- **Workflow chains** (row 66). `WorkflowChain` model + `WorkflowChainsStore`
  (JSON in UserDefaults). Three step kinds: Verified Backup, Transcode,
  Export Report. `WorkflowChainRun` drives sequential execution with
  per-step state. File → "Workflow Chains…" (⌘⇧Y) does CRUD + run.
  `runOnCameraMediaMount` flag auto-offers the chain when a camera
  card mounts.

### Polish & UX

- **Detail-view tabbed right pane** (Kyno-style). Segmented control
  toggles Metadata / Content / Subclips / Tracks. New `ClipFramesGrid`
  extracted from `ClipContentView`'s frames block. Active tab sticky
  via `clipDetailInspectorTab` AppStorage.
- **Sidebar snap-back from Detail to List**. Clicking a sidebar folder
  while in single-clip Detail used to leave the previous clip stuck
  on screen. `AppState.navigate(to:)` flips `viewMode` to "list" so
  the user lands somewhere browse-able.
- **Right-click menu wired to shipped features**. Five items used to
  fire an "On the Kyno-parity roadmap" alert despite the underlying
  features shipping — Export Markers as Stills, Import Metadata,
  Tags, Edit Multiple, Export Markers as Stills (in Edit menu).
  All now invoke the real methods. Dropped dead-end items (Batch
  Image Transform, per-clip LUT picker).
- **App version**: bumped through builds 327→356 during this run.

---

## Kyno-parity Round 2 — Workspace + history + full menu bar

- **Workspace = multiple roots** (was: single rootFolder). `Open
  Folder…` replaces the workspace; new **Add Folder to Workspace…**
  (⌘I) extends it. Sidebar renders one folder tree per root with
  a context menu (Remove from Workspace / Reveal in Finder), a
  Workspace header gear-menu (Add Folder / Clear Workspace), and
  persists across launches.
- **Bug fix**: opening a different folder no longer leaves the
  previous folder's clips visible. `displayedAssets` now always
  filters by either the explicitly-selected folder or — when no
  folder is selected — the union of all workspace roots.
- **History navigation**: ⌘[/⌘] back/forward through folder
  selections, with a History menu plus back/forward arrow buttons
  in the browser toolbar. The History → Clear History menu wipes
  the stack but keeps the current location.
- **Comprehensive Kyno-style menu bar**: File / Edit / Playback /
  Metadata / Convert / View / History / Window / Help, mirroring
  the reference screenshots. Wires every action that already
  exists (Open, Add Folder, Reveal, Rename, Export Subclips/
  Metadata, Copy and Verify [opens Verified Backup], Playback
  shortcuts, Rating ⌘0…⌘5, Transcribe / Auto-Describe / Similar
  Takes, every Transcode preset including ffmpeg, Previous/Next
  Clip ⌘←/⌘→, Drilldown ⌘D, Back/Forward ⌘[/⌘], Reset Window
  State, Keyboard Shortcut Reference). Menu items routed to the
  player (loop, in/out, markers, export frame, in-to-out) post
  `Notification.Name.playerCommand` so the menu drives the same
  pipeline as the existing keyboard handler.
- **Previous/Next Clip** (⌘← / ⌘→) — moves the asset selection up
  or down one row within the current displayed list. Wraps to
  start/end at boundaries.
- New `KYNO_PARITY_ROADMAP.md` tracks the complete gap from Kyno
  with ✅ / 🟡 / ⬜ status per item.

## Kyno-parity round 1 (Content/Tracks tabs, folder tree, browser controls)

User-driven; replicating the parts of Kyno's UX that close the most
visible gaps. Working from Kyno reference screenshots + the support
keyboard-shortcuts reference page.

- **Content tab** (`ClipContentView`): file metadata block (filename,
  path, size, modification/recording date, container, codec, fps,
  bitrate, audio codec/rate/channels) stacked above a 5×6 = 30-frame
  grid. Each tile shows the seconds offset overlay and is clickable
  to seek the player. `ClipDetailsService` pulls the extended
  metadata from `AVURLAsset` on demand.
- **Tracks tab** (`ClipTracksView`): per-stream technical breakdown
  matching Kyno's Tracks view — Track #1 (video) with codec / fps /
  resolution / aspect / bitrate / duration; Track #2 (audio) with
  codec / sample rate / channel layout / bitrate. Loads lazily on
  appear.
- **`ThumbnailService` parameterized**: accepts a frame count;
  hover-scrub cell still uses 12, the Content grid uses 30. Cache
  dir hash now includes the count so different counts cohabit.
- **Player View menu**: Rotate (0/90/180/270) + Flip H/V applied as
  a `CALayer.setAffineTransform` on `AVPlayerLayer`. Preview-only —
  the underlying file and any transcode are untouched.
- **Folder tree sidebar + drilldown**: recursive `FolderNode` tree
  built from the asset list's paths; expandable rows with disclosure
  triangles, recursive asset count badges. Selection drives a
  `displayedAssets` filter on AppState. Drilldown toggle in the
  browser toolbar controls whether subfolder contents are included.
- **Type filter chips**: All / Video / Audio / Images, capsule
  buttons in the browser toolbar.
- **Sort dropdown**: Name / Date / Size / Duration / FPS, persisted
  in `@AppStorage`. Drives the `displayedAssets` sort order.

## Round 2 follow-ups (thumbnails, SFTP pwd, BK-tree)

- **Thumbnail strip with hover-scrub** in the browser:
  `ThumbnailService` generates 12 evenly-spaced JPEGs per video
  (spread over the middle 90% to skip slates/leader), JPEG-encoded
  at 240px max, cached under
  `~/Library/Application Support/PurpleReel/thumbnails/<hash>/`.
  Cache key includes file modification time so touching the source
  invalidates. `ThumbnailCell` is the SwiftUI view: lazy-loads the
  middle frame on appear, cycles frames based on cursor X under
  `onContinuousHover`, falls back to a film icon when frame
  extraction fails. Added as the leftmost (90px) column of the
  asset table.
- **SFTP password auth** via `sshpass` + Keychain:
  `KeychainService` wraps `SecItem*` for per-destination password
  storage keyed by the destination's UUID. `SFTPService` detects
  `sshpass` (Homebrew or system path); when a password is stored
  for the active destination, sftp is launched as
  `sshpass -e /usr/bin/sftp …` with the password injected via the
  `SSHPASS` env var (safer than `-p` which would expose it in
  `ps`). UI gets a SecureField + a green/orange status line
  indicating whether sshpass is installed.
- **BK-tree similar-takes clustering**: replaces the previous
  O(n²) pairwise loop. `BKTree.swift` is the Burkhard-Keller tree
  with triangle-inequality pruning at each level. Scales us up to
  tens of thousands of clips without changing the
  `SimilarTakesService.findClusters` API. Verified against
  brute-force on 500 synthetic UInt64 hashes at four thresholds
  (2, 8, 20, 64) — results agree exactly.
- **Tests**: +4 BK-tree tests (exact match, within-threshold
  set membership, brute-force agreement, insertion count). All
  28 tests still green.

## Post-MVP follow-ups

- **XCTest suite** (24 tests across 6 files, `./run-tests.sh`):
  BatchRenameService token expansion, HashingService SHA-1/MD5/SHA-256
  against canonical FIPS vectors + chunked-matches-single-shot,
  MHLWriter XML well-formedness + escape, FCPXMLWriter
  well-formedness + special-chars escape, WhisperService.parseSRT
  shape coverage, WindowStateGuard preflight semantics.
- **FCPXMLWriter bug fix** caught by the new tests: `file://` URLs
  with `&` in the path were emitted unescaped, breaking XML parse.
  `fileURL()` now percent-encodes and XML-escapes.
- **Settings → AI pane** (`AISettingsView`): override `transcribe.py`
  path, pick Whisper model (turbo/tiny/base/small/medium/large-v3),
  pick Ollama model from live `/api/tags` query with reachability +
  script-presence indicators. Persisted via `@AppStorage`.
- **AI service overrides plumbed** through `transcribeSelected` and
  `autoDescribeSelected` — settings take effect immediately.
- **Per-byte SFTP progress**: streaming stdout parser hops on the
  main actor as sftp emits `Uploading <path> to <name>` / `100% …`
  lines, updating `SFTPFileItem.state` live. Raw log accumulates in
  real time too instead of all-at-end.
- **Parallel multi-destination backup**: when ≥2 destinations are
  configured, copy + verify happen concurrently via `TaskGroup`.
  Source hash still computed once per file. Wall time ~= slowest
  destination (was: sum across destinations).
- **Phase-2 codecs via ffmpeg** (4 new presets): DNxHR SQ, DNxHR HQ,
  Cineform, and ProRes-in-MXF rewrap. `TranscodeJob.runFFmpeg`
  shells out to `ffmpeg`, parses `time=HH:MM:SS.xx` from stderr to
  drive the progress bar, surfaces a clear error if ffmpeg isn't
  installed.

## Phase 11-12: polish + docs

- **Audio waveform overlay**: `WaveformService` runs an AVAssetReader
  pass over the first audio track at file-load time, bucketing
  16-bit PCM into 800 peak amplitudes (Accelerate-friendly inner
  loop, sqrt curve so dialog stays visible against transients).
  Renders behind the scrubber playhead via a custom `WaveformShape`.
- **Multi-rate J/K/L shuttle**: J/L step through ±¼× / ±½× / ±1× /
  ±2× / ±4×. Direction-reverse resets to 1× in the new direction
  (FCP/Premiere semantics). K stops.
- **Batch rename** with token template (`{orig}` `{ext}` `{date[:fmt]}`
  `{counter[:width]}` `{codec}` `{fps}` `{w}` `{h}` `{size_mb}`),
  live preview with red-flag conflict detection, on-disk move +
  catalog DB path update + auto-rescan.
- **USER_MANUAL.md**: full feature reference — install, keyboard,
  toolbar, logging, LUT, transcode, backup+MHL, SFTP, FCPXML, all
  three AI flows, batch rename, output paths, recovery.

## Phase 9-10: AI augmentation

All three differentiators that make this not-a-Kyno-clone, fully local
(nothing leaves the machine):

**Whisper transcription** (`WhisperService`):
- Bridges the sibling `transcribe/` MLX-Whisper project via Process.
- Probes for Homebrew Python (3.10+) first, falls back to `/usr/bin/python3`.
- Runs `transcribe.py -i <file> -o <tmp> -f srt --quiet -m turbo`,
  parses the produced SRT into `[TranscriptSegment]` (verified parser
  against synthetic SRT).
- Persists `TranscriptDocument` JSON in the existing `transcript`
  table; surfaces a segment-by-segment reader in the AI sheet.
- "Transcribe + Create Markers" option auto-emits one marker per
  segment with the transcribed text as the marker note.

**Ollama auto-description** (`OllamaService`):
- HTTP POST to `localhost:11434/api/generate` with `stream:false`.
- Round-trip verified live against `dolphin-mistral:latest`.
- Reachability probe (`/api/tags`, 1s timeout) — fast fail when
  Ollama isn't running.
- Prompt assembled from filename + (if present) transcript snippet;
  result lands in the asset's description field.

**Similar takes** (`SimilarTakesService`):
- 64-bit dHash (8×9 luminance grid, adjacent-pixel comparison) of
  each video's middle frame — deterministic, verified across repeated
  runs.
- Naive O(n²) pair-wise Hamming clustering with union-find at
  threshold 10/64 bits. Adequate for hundreds of clips; BK-tree port
  is a Phase-2 optimization.
- Per-cluster "best" pick: highest rating → longest duration →
  filename tiebreak. Surfaces in the AI sheet with a rationale.

**UI:**
- New "AI" sparkles menu in the toolbar (Transcribe / Auto-Describe /
  Find Similar Takes).
- Unified `AISheetView` sheet handles all three flows via an
  `AISheetState` enum (progress / ready / error).

## Phase 8: SFTP delivery

- `SFTPDestination` model + `SFTPDestinationStore` (JSON-backed
  UserDefaults persistence). Multiple named destinations.
- `SFTPService` shells out to `/usr/bin/sftp` with a generated batch
  script (`-mkdir` + `cd` + `put` per file + `bye`); captures stdout
  + stderr, parses per-file success/failure into `SFTPFileItem` state.
  Command construction dry-run-verified against expected CLI form.
- `SFTPDeliveryView` sheet: 220px destinations list (add / duplicate /
  delete), grouped editor form (host / port / user / remote path /
  identity-file / accept-new-host-keys), file picker (add from disk
  or "all catalogued"), per-file progress, raw `sftp` log disclosure.
- Auth model: SSH key only for MVP (use ssh-agent / `~/.ssh/config`,
  or an explicit identity-file path). Password auth deferred —
  requires `sshpass` and Keychain integration.
- `com.apple.security.network.client` added to entitlements
  (defensive; sandbox is off so not strictly required).

## Phase 8: FCPXML export

- `FCPXMLWriter`: emits well-formed FCPXML v1.10 (validates with
  `xmllint`). Per-asset `<asset>` + `<format>` dedup, rational-time
  math snapped to the asset's frame grid (uses canonical NTSC
  timescales 24000/30000/60000 for 23.98/29.97/59.94 and 100-based
  for 24/25/30/50/60). Logged markers, subclips, tags, and 4–5 star
  ratings cross over to the FCP timeline as `<marker>`, `<asset-clip>`
  with explicit `start`/`duration`, `<keyword>` (tags joined), and
  `<rating name="Favorite">`.
- Send-to-FCP toolbar menu: send selected clip, send entire library,
  with/without auto-launch of `/Applications/Final Cut Pro.app`.
  Falls back to Finder reveal when FCP isn't installed.
- Output lands in `~/Downloads/PurpleReel/exports/`.

## Phase 7: verified backup + MHL

- Chunked streaming hasher (`HashingService`): CryptoKit-backed SHA-1,
  MD5, SHA-256. 4 MB chunks. Cross-validated bit-for-bit against
  system `shasum`.
- Industry-standard ASC Media Hash List v1.1 writer (`MHLWriter`):
  `<hashlist>` with `<creatorinfo>` + per-file `<hash>` records,
  ISO-8601 timestamps, well-formed XML (validates with `xmllint`).
- `VerifiedBackupService`: walks source tree, hash → copy →
  re-hash → compare for each destination, emits one `.mhl` manifest
  per destination on completion. Mismatches fail the file
  individually (others continue).
- BackupView sheet: source + up to 4 destination pickers, hash algo
  segmented control (SHA-1 default per MHL convention), live per-file
  progress with state icons (queued/hashing/copying/verifying/done/
  failed), reveal-in-finder for each written `.mhl`.
- Toolbar action: "Verified Backup" (next to Transcode).

## Sidebar layout: HStack pattern adopted

- Replaced `NavigationSplitView` in `ContentView` with manual `HStack` +
  fixed 240px sidebar (MusicJournal-proven pattern). Rationale:
  `NavigationSplitView` on macOS 14+ does not reliably honor
  `.navigationSplitViewColumnWidth(min:)` at runtime layout — persisted
  state inside the declared range still mis-rendered the sidebar
  narrower than min, even after `.savedState` wipe.
- Added `⌃⌘S` Toggle Sidebar via `@AppStorage("sidebarVisible")`.
- `WindowStateGuard` retained for nested `VSplitView`/`HSplitView`
  inside the detail tree (browser table / player split).
- Documented as canonical PhantomLives pattern in
  `~/Documents/GitHub/PhantomLives/CLAUDE.md` and memory rule
  `feedback_split_view_state_guard`.

## Phase 6: transcode

- Six built-in transcode presets: H.264 1080p/720p, HEVC 1080p,
  ProRes Proxy, ProRes 422, and pass-through rewrap.
- `TranscodeService` wraps `AVAssetExportSession` with progress
  polling, output naming with collision suffix, and codec
  compatibility gating (H.264/HEVC require asset compatibility check;
  ProRes / pass-through always available).
- `TranscodeQueue` (@MainActor): single-worker serial drain — keeps
  the hardware HEVC encoder unsaturated and progress predictable.
- Transcode menu in toolbar (enabled when a clip is selected); queue
  sheet with per-job progress, cancel, and "Reveal in Finder" on
  completion.
- Default output: `~/Downloads/PurpleReel/transcoded/`.

## Phase 5: LUT preview

- Adobe `.cube` LUT parser (3D LUTs native; 1D LUTs synthesized into
  a 33³ cube by per-channel curve sampling).
- LUTs applied in real time via `AVVideoComposition` with a
  `CIColorCubeWithColorSpace` filter; rebuild on LUT change or asset
  load.
- LUT bar under the transport: load `.cube`, show name + cube size,
  clear, persist last-used path via UserDefaults.

## Phase 2: player + logging

- AVPlayer-based detail pane with custom transport (play/pause, 1-frame
  step, J/K/L shuttle rates, I/O markers, click-to-seek scrubber).
- Frame-accurate SMPTE timecode (HH:MM:SS:FF, non-drop) display.
- Marker creation at playhead (M); markers list with inline note
  editing and timecode-jump-to-marker.
- Subclip creation from I/O range (S); subclips list with jump-to-in
  and jump-to-out.
- Tag chips with add (Return) and remove (× click).
- 1–5 star rating + free-form description per asset.
- All detail state persists through GRDB CRUD on `marker`, `subclip`,
  `tag` / `asset_tag`, `rating` tables.

## Phase 1 skeleton

- Scaffolded XcodeGen project, GRDB dependency, asset catalog with
  programmatic film-reel `AppIcon`.
- Catalog schema (assets, tags, markers, subclips, ratings, transcripts,
  FTS5 search table).
- Finder-rooted recursive `MediaScanner` with AVFoundation-derived
  video metadata (codec, resolution, fps, duration).
- Browser view: filterable table of catalog contents.
- Auto-backup-on-launch (zip of `~/Library/Application Support/PurpleReel/`)
  per PhantomLives convention.
- Build/install scripts mirroring `PurpleTracker` conventions.
