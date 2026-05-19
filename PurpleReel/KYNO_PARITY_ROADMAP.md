# Kyno Parity Roadmap

**Status: complete.** Every Kyno-visible feature is either shipped in
PurpleReel or explicitly out of scope. See [`KYNO_RESEARCH.md`](KYNO_RESEARCH.md)
for the canonical per-feature status — 85 rows broken down by
category, source citation, effort estimate, and current state.

---

## Where this document came from

This file used to be a living checklist of Kyno-visible features
PurpleReel didn't yet match, built from user-supplied screenshots and
Kyno's published keyboard-shortcuts reference. It was the working
todo list during Sprint 1 (initial parity push).

During Sprints 2–4 we replaced it with the more rigorous
`KYNO_RESEARCH.md` — every Kyno feature transcribed from primary
sources (release notes, forum threads, third-party reviews) into a
single table with source URLs, effort buckets, and per-row
implementation notes. That research doc is now the source of truth.

## What got shipped

By the end of Sprint 4, 63 of 85 catalogued rows had landed:

- **Small bucket (38 rows): all shipped.** Coming-from-Kyno
  compatibility mode (J/L jumps, X-mute, ⌃⌥E zebra, ⌃⌥W matte,
  ⌥⇧O open-with, ⌘⌥M focus metadata, natural numeric sort, no
  auto-drilldown), Date Recorded / Date Created / Display Size /
  Aspect Ratio columns, paste metadata between clips, play-all
  continuous, incremental transcoding skip, smart proxy scale
  presets, zero-based timecode pref, LUT-on-still-frame default,
  shift-click hard refresh, subclip collision auto-disambiguate,
  audio-channel-name field, transcoder file-timestamp preservation,
  fade-in/out transcoder option, file-count safety limit warning,
  Apple Silicon native badge, …
- **Medium bucket (18 rows shipped, 2 explicitly skipped).** Find
  Lost Metadata, timecode burn-in, LUT auto-detect, folder-tree
  metadata transfer, batch frame export at markers, Excel/CSV report
  with thumbnails, paste-and-rename, boolean AND/OR filter, VFR/CFR
  filter, poster-frame keyboard P, batch tag editor, pitch-preserved
  audio rates, C4 + ASC-MHL v2.0, list-view waveform column, Kyno
  `.LP_Store/` XML import, permissions wizard. Explicitly skipped:
  Resolve FCP7-XML export (row 3), Frame.io upload preset (row 73).
- **Large bucket (7 rows shipped, 1 user-skipped).** FCPXML
  re-import, shared workspace cache for NAS / SAN, combine multiple
  clips, spanned-clip detection, cross-volume offline search,
  workflow chains, drive-disconnect quirk (closed by construction).
  User-skipped: UI localization (row 56) — out of scope.
- **Pre-research rows (10):** features that were already shipped
  before the research doc existed.

## Where to look now

- [`KYNO_RESEARCH.md`](KYNO_RESEARCH.md) — every Kyno feature with
  current state, source citation, and implementation notes. Canonical.
- [`USER_MANUAL.md`](USER_MANUAL.md) — task-oriented user
  documentation. Reflects shipped state.
- [`SHORTCUTS.md`](SHORTCUTS.md) — keyboard-shortcut reference.
- [`CHANGELOG.md`](CHANGELOG.md) — per-sprint feature rollup.

## Items that fell out of scope

- **UI localization** (German / French / Spanish — row 56). Kyno is
  multilingual; PurpleReel ships English-only by choice. Not a
  competitive blocker for our target market.
- **Resolve FCP7-XML export** (row 3). PurpleReel ships FCPXML
  (1.10) which Resolve reads; the legacy FCP7-XML path is a separate
  schema and was deprioritised. Flagged as a v2 candidate.
- **Frame.io upload preset** (row 73). Partially addressed in C38 —
  PurpleReel now ships a "Frame.io Review (H.264 1080p MP4)"
  transcode preset that produces Frame.io's recommended ingest
  format. Real OAuth + REST auto-upload is still deferred (Adobe's
  acquisition makes the API politically fragile, and the existing
  SFTP delivery covers ~80% of the review-with-client workflow).
- **Avid Op-Atom MXF / RED R3D / P2 / DNxHD non-rewrap**. Declined in
  the original PurpleReel build plan as outside the FCP-focused
  delivery target.
- **Final Cut Pro X library predicate filter**. Would require parsing
  FCP's library state. Out of scope.

The drive-disconnect-before-XML-import quirk (row 82) never applied
to PurpleReel by construction — our metadata importers don't assume
a particular mount state.

## Post-parity polish (C21–C38)

After parity was declared complete, PurpleReel kept shipping —
discoverability prompts, deferred follow-ups, and Beyond-Kyno
features. Highlights, with CHANGELOG references:

- **Combine Clips matured into a real editor** (C16–C20, C23, C24,
  C27, C36): per-clip in/out trim, drag-reorder, marker preservation,
  audio-only output, dimension-match override, cross-fades (global +
  per-pair durations), fade-from/to-black, non-linear easing curves
  (global + per-pair).
- **Discoverability sweep** (C21, C29, C31): drilldown hint banner,
  no-results banner explaining active filters, offline-workspace-root
  + permission-denied + stale-catalogue banners, multi-root summary
  in the toolbar.
- **Workflow chain follow-ups** (C32–C34, C37): per-step cancel for
  transcode + report (and now backup via C37), drag-reorder steps,
  continueOnFailure flag, built-in chain templates, run resumption
  across app launches via on-disk snapshots.
- **Workspace cache follow-ups** (C32, C35, C36): orphan prune,
  schema-version rejection guard, multi-root path-math coverage,
  age-based eviction, auto-prune-on-launch.
- **Per-clip Camera + Creative LUT pinning** (C30, C36): schema
  migration v9 carries the paths; the Convert dialog auto-defaults
  the LUT pickers from the pin when a single clip is selected.
- **Smaller deferred items**: recent destinations (C22, C38),
  custom-file LUT picker (C22), `${markerTitle}` token (C22), XLSX
  section-toggle column dropping (C26), FCPXML project-membership
  tracking (C25), Frame.io review preset (C38).

`CHANGELOG.md` is the canonical log; this section is just a hook
for users browsing the parity doc.

---

## Post-v1.0 candidate work (C41+)

A May 2026 audit of `/Applications/Kyno.app` (Java app, 219 jars,
bundled JRE, 15 native helper modules) surfaced three real gaps
behind the parity wall. Scopes captured here so the work is
inventoried before it's picked up. None are committed to ship — this
is the scoping outcome, not a sprint plan.

### C41 — ffmpeg fallback decode for AVF-unsupported codecs

**Problem.** PurpleReel uses `AVURLAsset` at 12 sites (player,
scanner, thumbnailer, transcode-input-probe, similar-takes,
waveform, frame-export, …). When AVFoundation can't decode a
container (DNxHR/DNxHD in MXF Op-Atom or Op-1a, Cineform-in-MOV,
legacy MPEG-2 XDCAM HD422, some VP9-in-WebM), the file appears in
the browser but yields no thumbnail, no codec name, no duration,
and a blank player. Migration blocker for broadcast / Avid shops.

**Existing infrastructure.** ffmpeg shell-out already in production
for transcode export (`TranscodeService.swift:451-538`,
`findFFmpegExecutable()` looks at `/opt/homebrew/bin/ffmpeg`,
`/usr/local/bin/ffmpeg`, `/usr/bin/ffmpeg`). `README.md` already
documents ffmpeg as a soft-required dep. Kyno bundles its own
ffmpeg dylibs (~21MB) in `native/org.ffmpeg/lib/`; we shell out.

**Approach — three-tier ladder.**

- **Tier 1 (C41a/b — ~4 days):** `FFmpegProbeService` runs
  `ffprobe -show_streams -show_format -of json` when AVFoundation
  yields empty tracks; populate codec / resolution / fps / duration
  / timecode. `FFmpegThumbnailService` runs
  `ffmpeg -ss <mid> -i <f> -frames:v 1 -f image2pipe pipe:1` for
  thumbnails. Browser + inspector + reports now reflect the real
  file. Player still placeholders for unplayable codecs.
- **Tier 2 (C42 candidate, v1.2 — ~5-7 days):** on-demand ProRes
  Proxy generation via existing TranscodeService. User clicks
  unplayable clip → prompt → ffmpeg-transcode into workspace cache
  → schema v10 `clip_metadata.proxy_url` → player transparently
  loads proxy.
- **Tier 3 (v2-or-never):** real-time ffmpeg playback via custom
  `CMSampleBufferDisplayLayer` + `VTDecompressionSession` pump.
  Duplicates AVPlayer for a few codecs; recommend deferring
  indefinitely unless Tier-2 proves too slow.

**Bundling decision.** Status quo: shell out to user-installed
ffmpeg (matches transcode path; `brew install ffmpeg` already in
README requirements). Revisit bundling if telemetry shows
ffmpeg-missing failures clear a threshold.

**Out of scope.** `Tier 3` realtime ffmpeg playback. BRAW / RED
native decoders (already on the "next-macOS-major" deferral list).

### C42 — Audio-only player surface

**Problem.** `mp3 / wav / aif / aiff / flac / m4a / caf / ogg`
assets already route to `PlayerView` (`MediaKind.audio` →
`ClipDetailInline.previewArea` at `:147-166`). AVPlayer plays them
fine, transport + J/L + X-mute all work. But `AVPlayerLayer` with
no video tracks renders a black rectangle — no waveform, no
playhead, no BWF/ID3 metadata strip, no album art. Sound-design and
dialogue-edit workflows fall off a UX cliff. The agent's earlier
"audio-only is skipped" claim was wrong; the gap is the visual
surface, not the engine.

**Existing infrastructure.** `WaveformService` already generates
peak data for any asset (already used in the metadata pane's
waveform tab); `WaveformInlineView` already renders it.

**Approach.** Branch on `MediaKind` inside `PlayerView`'s surface:
when `.audio`, swap `PlayerSurface` for a new `AudioPlayerSurface`
rendering a large centered waveform with a playhead overlay bound
to `playerController.currentTime`; click-to-seek translates x →
CMTime via `player.seek`. Surface ID3 / BWF / iXML metadata
(artist, album, scene, take, BWF description, BWF origination time)
via `AVAsset.metadata` with `commonMetadata + id3Metadata +
quickTimeUserDataMetadata`. Optional cover art if found.
Frame-export operations no-op for audio.

**Effort.** ~3-4 days. Net new: `Views/AudioPlayerSurface.swift`
(~150 lines), `Views/AudioWaveformPlayheadView.swift` (~80 lines).
Refactor `PlayerView` surface switch (~30 lines). Extend
`MetadataPaneView` BWF/ID3 fields. Tests for ID3 parsing + waveform
click-to-time math.

**Risk.** Low. AVPlayer audio path is mature; the work is SwiftUI
composition over existing services.

### C43 — Customizable report columns

**Problem.** `ReportDefinition.swift:9-38` exposes report column
control as a 5-bit `ReportSections` OptionSet (`fileSize`,
`fileType`, `duration`, `formatDetails`, `descriptiveMetadata`);
column **order** is hard-coded in three writers
(`XLSXReportWriter.swift:206-232`, `ReportExporter.csvHeader` /
`htmlHeader`). User can drop a whole section but can't reorder
columns, toggle individual columns within a section, save column
profiles, or sort by a column.

**Existing infrastructure.** C26 already solved OOXML
column-letter realignment when a section drops — column letters are
position-derived (`XLSXReportWriter.swift:328`). The math is in
place; we just need to drive it from an ordered column list
instead of a section bitmask.

**Approach — Flavor A (Recommended for C43).** Replace
`ReportSections` with `Models/ReportColumn.swift` — one enum case
per actual column (~24 cases). `ReportDefinition` becomes
`{ orderedColumns: [ReportColumn], sortBy: ReportColumn?,
sortDescending: Bool }`. Single shared
`renderRow(asset:, appState:, columns:) -> [String]` helper drives
all three writers. UI in `ReportDefinitionSheet`: drag-reorder list
with per-row eye-toggle, sort-key picker. Migration:
`ReportSections` values → default column orders.

**Approach — Flavor B (Deferred to C44).** Flavor A plus 4 built-in
profiles (Producer / Editor / QC / Delivery), user-saved profiles
in `~/Library/Application Support/PurpleReel/report-profiles.json`,
XLSX frozen header row.

**Effort.** Flavor A: ~5-7 days. Flavor B: +3 days.

**Risk.** Medium. Three writers must stay aligned on the column
model — mandatory shared `renderRow` helper + property test
asserting `csvHeader.count == csvRow.cells.count ==
xlsxHeader.count` for arbitrary column-orders.

---

### C44 — AWS S3 upload destination

**Problem.** PurpleReel ships SFTP delivery (`Models/SFTPDestination.swift`,
`Views/SFTPDeliveryView.swift`) — fine for VPN-attached production
servers, but shops archiving dailies to S3 / Backblaze B2 / R2 /
MinIO have no first-class option. Kyno bundles 8 AWS SDK JARs
(`Java/s3-2.31.6.jar`, `Java/aws-crt-0.34.1.jar` @ 18MB) and treats
S3 as a peer destination type alongside SFTP.

**Existing infrastructure.** SFTPDestination is the template:
`Codable` struct → JSON in UserDefaults → in-app picker → delivery
view. We mirror that shape for S3.

**Approach.** Add `aws-sdk-swift` SwiftPM dep (modular — pull only
`AWSS3`, ~10-15MB). New `Models/S3Destination.swift` with `endpoint`
(supports any S3-compatible: AWS, B2, R2, MinIO, Wasabi), `region`,
`bucket`, `prefix`, `accessKeyID`, `secretAccessKey` (stored in
Keychain, not JSON). Upload via `S3Client.putObject` from
URLSession-backed streaming uploader; multipart for >100MB.
`Views/S3DeliveryView.swift` mirrors SFTPDeliveryView with the same
job model + progress observation.

**Effort.** M (5-7 days). Net new: `S3Destination`, `S3Service`,
`S3DeliveryView`, Keychain wrapper for credential storage. Tests:
endpoint URL building, multipart-threshold math, mock-server upload
round-trip via `LocalstackTests` harness.

**Risk.** Medium. `aws-sdk-swift` is well-maintained but heavy;
modular import keeps surface area sane. Code signing must include
the new bundled libs.

**Out of scope.** STS / SSO auth flows (v2). IAM role assumption.
Object-lock + versioning configuration UI.

### C45 — DPX / EXR scan + thumbnail support

**Problem.** PurpleReel's image-extension allowlists
(`MediaScanner.swift:9`, `Asset.swift:93`,
`ImagePreviewView.swift:53`, `ThumbnailService.swift:190,235`) do
**not** include `dpx` or `exr`. These files don't even appear in
the browser. VFX shops with DPX plate sequences or EXR renders see
folders as empty.

**Existing infrastructure.** TIFF already supported through the
image path (`Asset.swift:93`); ffmpeg already a soft dep
(`README.md`, `TranscodeService.swift:531`).

**Approach.** Three-line scan fix + a thumbnail handler:

1. Add `dpx`, `exr` to `imageExtensions` in MediaScanner,
   ImagePreviewView, ClipDetailSheet, ThumbnailService.
2. New `ThumbnailService.thumbnailViaFFmpeg(url:size:)` that
   shells out to `ffmpeg -i <file> -frames:v 1 -vf "scale=W:-1" -f
   image2pipe png pipe:1` and returns a CGImage. Routes by
   extension when the file lands in `ThumbnailService`.
3. ImagePreviewView falls back to the ffmpeg-rendered PNG for DPX /
   EXR previews.

**Effort.** S (2-3 days). Net new: ffmpeg thumbnail helper, image
ext additions, ImagePreview routing. Tests: round-trip a sample
DPX and EXR through the helper, verify ffmpeg-missing fails
gracefully.

**Risk.** Low. ffmpeg DPX/EXR support is mature.

**Out of scope.** DPX / EXR transcode presets (separate ask).
Wide-gamut color management for EXR (lives behind the C41 HDR
deferral). Native libOpenImageIO bundling (declined — keeps
bundle small).

### C46 — DMG mount display in Devices sidebar

**Problem.** `DevicesSection` (`Views/DevicesSidebar.swift:8`)
enumerates `/Volumes/*` and renders every mount with the same
`internaldrive` SF Symbol. DMG-mounted dailies (common on-set
delivery) look identical to USB drives; user can't tell at a
glance. `VolumeWatcher.classify` already buckets local / removable
/ network but doesn't separate disk images.

**Existing infrastructure.** `VolumeWatcher.classify(_:)` returns
`VolumeKind` (local / removable / network / unknown).

**Approach.** Cheapest reliable DMG detection is `diskutil info
-plist /Volumes/Foo` parsing — DMG mounts carry `Image: yes` and a
`DeviceIdentifier` like `diskNs2` where the parent `diskN` has
type `disk_image`. Add `case diskImage` to `VolumeKind`. In
`DevicesSection.refresh`, partition `/Volumes/` listing into "Disk
Images" subsection (icon `opticaldiscdrive.fill`) and regular
volumes. Add eject affordance (we already have everything Finder
needs — `NSWorkspace.unmountAndEjectDevice`).

**Effort.** XS (1 day). Net new: DMG classification helper, DMG
subsection in DevicesSection, eject action. Tests: classifier
against a known DMG mount path (test harness mounts a temp .dmg
via hdiutil).

**Risk.** Low. `diskutil` is stable.

### C47 — VFR motion-analysis enhancement

**Problem.** Current VFR detection (`MediaScanner.swift:230-235`)
compares `nominalFrameRate` against `minFrameDuration`; flags VFR
when `(1/nominalFrameRate - minFrameDuration) / (1/nominalFrameRate)
> 0.10`. Catches the obvious cases (iPhone, screen recording) but
misses subtle drift (mid-clip stutters, audio-video clock skew, per-
segment VFR).

**Approach.** Read every video frame's PTS via
`AVAssetReaderTrackOutput` (sample-buffer enumeration with
`copyNextSampleBuffer` → `presentationTimeStamp`); compute the
gap distribution; flag when σ/μ > threshold. Run as a re-analysis
pass under `AnalysisScope.technicalMetadata` (already gated by an
opt-in checkbox so it doesn't auto-cost every scan).

**Effort.** S (3-4 days). Net new: `MediaScanner.computeFrameRateDrift`,
new `Asset.frameRateDriftScore: Double?` column (schema v10), filter
rule for "VFR (suspected — drift)". Tests with a synthesized VFR clip.

**Risk.** Medium. Reading every PTS adds seconds per file; only
do it under explicit re-analyze.

**Recommendation.** **Defer to v2.** Current heuristic is good
enough in practice; ROI is low until user reports prove otherwise.

### C48 — Multi-format waveform rendering — already shipped

**Verification result.** `WaveformService.generateAsync`
(`Services/WaveformService.swift:70-78`) opens the file via
`AVURLAsset` and reads PCM via `AVAssetReader` with linear-PCM
output settings. AVFoundation does the format conversion
internally — MP3, AAC (m4a), FLAC (macOS 14.4+), WAV, AIFF,
Ogg-in-WebM all work transparently.

**Action.** **No code change.** Confirms the audit was directionally
wrong on this row. The only formats this won't waveform-render are
the same codecs C41 covers (Cineform audio, certain MXF audio
wraps) — which become free when C41 ships.

### C49 — Per-subclip poster frames

**Problem.** `Asset.posterFrameSeconds: Double?` (`Asset.swift:50`)
stores one poster offset per asset. Subclips (`Marker.swift:19-32`)
have no poster-frame column, so the subclip list shows the parent
asset's poster — not the subclip's distinctive moment. Markers are
point-in-time so don't need this (the marker IS the poster moment);
subclips have duration and need their own poster.

**Approach.** Schema v10 migration adds `subclip.posterFrameSeconds:
Double?`. `ThumbnailService.posterFrame(for: subclip:)` overload
honors it. Subclip-list rows render the per-subclip poster. Right-
click on a subclip → "Set poster frame at playhead" (extends the
existing P-key handler to be context-aware about whether a subclip
is selected).

**Effort.** S (2 days). Net new: schema v10 migration, DB query
update, thumbnail-service overload, context-menu wiring. Tests:
schema migration upgrades v9 → v10 cleanly, posterFrameSeconds round-
trips through Codable.

**Risk.** Low. Mirrors the v9 schema migration that landed C30.

### MXF Op-Atom — covered by C41

**Verification result.** `MediaScanner.imageExtensions` includes
`mxf`. AVFoundation can play Op-1a MXF (XDCAM HD422) on macOS 14+
but does not reliably play Op-Atom MXF (Avid DNxHR/DNxHD wraps).
Currently those files appear in the browser as ghost rows. C41a/b
(ffprobe metadata + ffmpeg thumbnails) bring them to full
discoverable parity; C41c (proxy generation) makes them playable.
**No separate scope needed** — C41 is the right home.

---

## Consolidated effort + sequencing

| Item | Effort | Risk | Impact | Sprint |
|---|---|---|---|---|
| C46 DMG display | XS (1d) | low | medium | **v1.1** |
| C49 per-subclip poster | S (2d) | low | medium | **v1.1** |
| C42 audio surface | S (3-4d) | low | medium | **v1.1** |
| C41a ffprobe metadata | S (3d) | low | high | **v1.2** |
| C41b ffmpeg thumbnail | XS (1d) | low | high | **v1.2** |
| C41c schema-v10 groundwork | XS (½d) | low | preps Tier 2 | **v1.2** |
| C45 DPX/EXR support | S (2-3d) | low | medium | **v1.3** |
| C43a column reorder (Flavor A) | M (5-7d) | medium | medium | **v1.3** |
| C44 S3 upload | M (5-7d) | medium | high | **v1.4** |
| C43b column profiles (Flavor B) | S (3d) | low | low | **v2** |
| C47 VFR motion analysis | S (3-4d) | medium | low | **v2** |
| C48 multi-format waveform | — | — | — | **already shipped** |
| C50 (placeholder) | | | | reserved |

**Realistic ceiling: ~25-30 days across four focused sprints
(v1.1-v1.4) to reach the practical-blocker-free state.** v2 work is
polish that depends on user demand.

**Sprint v1.1 (~6-7 days):** C46 + C49 + C42 — three small features
touching different files (Devices sidebar, schema/subclip, player
surface). High parallelism, low risk, visible polish.

**Sprint v1.2 (~5 days):** C41a + C41b + C41c — the ffmpeg fallback
ladder. Single biggest migration-blocker unlock.

**Sprint v1.3 (~8-10 days):** C45 + C43a — DPX/EXR scan-and-show, plus
the report-column rewrite. Different subsystems = parallelizable.

**Sprint v1.4 (~5-7 days):** C44 — S3 destination on its own; AWS SDK
Swift integration is the unknown so it gets its own dedicated cycle.

Bundling decisions locked in this scoping pass:
- ffmpeg stays as a shell-out (`brew install ffmpeg`), no bundle.
- AWS SDK for Swift bundled (modular `AWSS3` only, ~10-15MB).
- DPX/EXR thumbnails routed through ffmpeg, not via bundled OIIO.
- ffmpeg-missing failure modes mirror the existing transcode
  behavior — graceful error message pointing at `brew install ffmpeg`.

These scopes were captured from May 2026 Kyno-bundle audit findings;
see commit history around `1e81f73` for the originating discussion.
