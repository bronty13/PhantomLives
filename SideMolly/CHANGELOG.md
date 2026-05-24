# Changelog

All notable changes to SideMolly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and SideMolly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0] — 2026-05-24

### Added — Phase 5: Transcription

Per-video transcripts via the PhantomLives `transcribe/` CLI (MLX-
accelerated Whisper on Apple Silicon). New `transcribe_video` job
kind goes through the existing queue and writes three sidecars per
video to `work/<uid>/transcripts/<stem>.{txt,srt,json}`:

- **.json** — full whisper output (segments, timings, language probe)
- **.txt** — flat text (joined segment text)
- **.srt** — subtitle format (numbered segments + timecodes)

`transcribe.py` only emits one `-f <format>` per invocation, so to
avoid running Whisper 3× per video the dispatcher calls it once with
`-f json` and **derives the .txt + .srt locally** by parsing the
JSON. Saves ~2× the wall clock on a 30-min batch.

**Engine resolver** (priority order):
1. `transcribe` shim on PATH (`/opt/homebrew/bin`, `/usr/local/bin`,
   `/usr/bin`, then `which`).
2. Direct script invocation via `python3` at
   `~/dev/PhantomLives/transcribe/transcribe.py` (the most likely
   path on Robert's box).
3. `PHANTOMLIVES_HOME` env-var override.

Cached via `OnceLock`. Returns `TranscribeEngine { command,
leading_args, description }` so dispatch can spawn uniformly whether
we found a shim or have to go through python.

**Edit tab Step 4 — Transcripts** (videos only). Shows install
status pill (`✓ ready · transcribe 1.4.4` or `⚠ not detected`),
"📝 Transcribe all videos" button (disabled when engine missing),
per-video status row (`✓ done` / `… pending`), text preview when
available, and a LiveQueue widget showing each `transcribe_video`
job. Reveal-in-Finder button on done rows.

**Settings status** lives inline in the EditTab — no separate
Settings panel for this phase. Future iterations can add a model
selector + advanced flags.

**Whisper-JSON → .srt** parsing tested with realistic timestamps
(`srt_timestamp_format` test covers hour/minute/second/millisecond
formatting including the comma decimal-marker SRT requires).

### Deferred to Phase 5.1

Diarization (speaker turns) per spec §11 risk note — typically needs
a pyannote-style component that's a separate model + a non-trivial
dependency. Robert can hand-edit speaker tags into the .srt for now;
we'll ship a proper pipeline once the diarization model story is
clear.

### Tests

110 passing. New camelCase contracts for `TranscribeStatus`,
`TranscribeVideoParams`, `EnqueueTranscriptsResult`, `TranscriptRow`.
Round-trip + SRT timestamp + segment-text rendering tests in
`transcribe.rs`.

## [0.10.0] — 2026-05-24

### Added — Phase 4.5b: DeepFilterNet voice isolation

Optional voice-isolation pre-pass in the auto-assemble pipeline. When
enabled (Settings → Auto-Assembly) the per-clip normalize step extracts
the source audio to a PCM WAV, runs it through DeepFilterNet, and uses
the cleaned audio as a second ffmpeg input to the main encode. The
existing ffmpeg audio chain (loudnorm + acompressor + EQ) still runs
on top, so the audio path becomes:

```
source audio → DeepFilterNet (denoise + voice isolation)
            → loudnorm -16 LUFS + acompressor + 200Hz/3kHz EQ
            → AAC 192k / 48k stereo
```

**Why DeepFilterNet over a pure-ffmpeg approach** (e.g. arnndn): better
quality on modern voice scenarios and the spec called for it. The
cost is an external dependency we don't bundle — `deep-filter` is a
~75MB binary with embedded ONNX weights, too large to ship inside the
.app.

**Binary detection** lives in `thumbnails::deep_filter_bin()`,
following the same Finder-launched-PATH-stripped probe pattern we
use for ffmpeg/ffprobe: checks `/opt/homebrew/bin`, `/usr/local/bin`,
`~/.cargo/bin`, then falls back to `which`. Cached via `OnceLock`.

**Settings → Auto-Assembly** panel shows live install status under the
checkbox:

- Installed: `✓ installed · deep-filter <version> · /path/to/binary`
- Not installed: `⚠ deep-filter binary not found` plus copy-pasteable
  install command:
  ```
  cargo install --git https://github.com/Rikorose/DeepFilterNet --bin deep-filter
  ```
  and a link to the GitHub Releases page for pre-built binaries.

The checkbox itself is disabled until the binary is detected, so the
user can't enable a toggle that would silently no-op.

**Enqueue-time validation**: if `deepfilternet_enabled` is on but the
binary disappeared between Settings save and Auto-assemble click, the
enqueue command errors before queuing any jobs — better than shipping
N silently-noisier clips through the worker.

**New backend command**: `get_deepfilternet_status` returns
`{ installed, binPath, version }` for the Settings UI.

**Filter-graph rewiring**: `dispatch_normalize_video` now tracks input
indices dynamically. When DeepFilterNet is on, the cleaned-audio WAV
is input 1 (source video stays input 0); the watermark PNG (if any)
shifts to input 2. Audio chain reads from `[1:a]` instead of `[0:a]`.

**Intermediate files** live next to the per-clip output:
`v01.df-raw.wav` (extracted PCM, deleted on success) and
`v01.df-clean.wav` (DeepFilterNet output, consumed by the main encode).
The CLI writes its output as `*_DeepFilterNet*.wav` with a version
suffix that drifts between releases, so we use `--output-dir` + a
scan rather than hardcoding the filename.

### Tests

101 passing. New camelCase contracts for `DeepFilterNetStatus`,
extended `NormalizeVideoParams` to cover `deepfilternet_enabled`.

## [0.9.0] — 2026-05-24

### Edit tab redesign + title-card fix

Robert ran a bundle end-to-end through the 0.8.0 Edit tab and the
flow was awful — Process buttons sat above the rotation grid so the
natural reading order made you process before rotating; every
rotation click re-fetched the whole bundle and snapped the page;
once anything was running the only way to see progress was the
separate Jobs tab; switching back lost context entirely. This
release is a focused UX rewrite, not a feature add.

**Sticky bundle chrome** at the top of every workspace tab. Always
shows persona chip, title, UID, verify status, image/video counts,
workspace path (one click reveals it in Finder), and a
**status pill** that's always visible:

- `✓ idle` — no jobs for this bundle yet
- `⚙️ N active · M/T done` — something running, with progress
- `✓ N done` — all complete
- `⚠ N failed` — surfaced loud

Driven by a new `useBundleJobs(uid)` hook that subscribes to the
`job-updated` event bus + 3s safety poll, filters server-wide jobs
to this bundle's UID, and exposes pending/running/done/failed
counts to anyone who needs them.

**Edit tab is now a 4-step linear flow** with numbered cards (large
indigo circle + clear hierarchy):

1. **Review & rotate** — was buried at the bottom in 0.8.0. Now
   first, because it has to happen before processing. Mixed grid
   (images + videos in bundle order) with click-to-cycle rotation
   tiles. Rotation click is **optimistic local state** now —
   the DB write fires in the background but the UI updates
   instantly with no re-fetch (fixes the scroll-snap that plagued
   30+ clicks in a row). Footer shows `N rotated · M untouched` +
   "Reset all to 0°" affordance.

2. **Process media** — images and videos in one card with their own
   toggle rows + Process buttons. Inline progress banner for sync
   image work (existing per-image counter + bar) **plus** a new
   `LiveQueue` widget below that lists every `process_video` job
   for this bundle with status pills, the source path, and a
   running aggregate (`N/M done · ⚙️ 1 running · ⏳ K pending`).
   No more tab-switching.

3. **Auto-assemble master cut** — same `LiveQueue` widget filtered
   to the title + normalize + assemble pipeline. The user can see
   every sub-job's status without leaving Edit. Master cut card
   (✓ ready / pending placeholder) is inside this step now,
   right where it belongs.

4. **Processed outputs** — moved here from its previous mid-flow
   position. Same per-row Reveal/copy/src controls.

**Live queue widgets** (`LiveQueue` component) render inline in
both processing steps and update on every `job-updated` event.
Footer shows aggregate counts; per-row pills show status + the
file the job is operating on. Failed jobs surface their last
error as a `⚠` tooltip on the row.

**Title card render-via-PNG fix** — 0.8.0 used ffmpeg's `drawtext`
filter on the title card, but Homebrew's stock ffmpeg ships without
libfreetype (same workaround we shipped for video watermarks in
Phase 4 — I forgot to apply it here). Every `render_title` job
was failing with `No such filter: 'drawtext'`, blocking every
`assemble_master` job downstream. New `images::render_title_card_png`
rasterises the full 1920×1080 title card via imageproc; ffmpeg
loops the still and applies fade-in/out via the `fade` filter
(works on any ffmpeg build).

### What didn't change

- Sidebar (Inbox / Jobs / Settings / Manual).
- Inbox layout.
- Overview tab.
- Jobs tab still exists as a global queue view — useful when you
  want to see all bundles' jobs at once, just not the *primary*
  way to track a bundle you're actively working on.
- Settings tabs.

### Files

New: `src/lib/useBundleJobs.ts` (data hook), `src/views/Bundle/EditTab.tsx`
rewritten in place (was 631 lines, now ~720 with the 4-step structure).
`BundleWorkspace.tsx` restructured for sticky chrome.

100 tests still passing.

## [0.8.0] — 2026-05-24

### Added — Phase 4.5a: Auto-Assembly pipeline

One-click "make me the master cut" on the Bundle workspace Edit tab.
Compiles every video in a bundle into a single landscape 16:9 MP4 with
title card, cross-dissolves between every clip, watermark, audio
enhancement, and fade-to-black at the end. The mechanic that closes
the loop on the editing tab — what watermarks + rotation + per-clip
processing were all building toward.

```
┌── 10s title ──┐ xfade ┌── v₁ ──┐ xfade ┌── v₂ ──┐ xfade … ┌── v_N ──┐ → fade-to-black
│ bundle title  │   1s  │ + WM    │   1s  │ + WM    │         │ + WM    │
│ + persona     │       │ + audio │       │ + audio │         │ + audio │
└───────────────┘       └─────────┘       └─────────┘         └─────────┘
```

**Three new job kinds** route through the existing Phase 4 jobs queue
(sequential worker, atomic claim, per-attempt audit):

- `render_title` — 10s `lavfi` color source + drawtext title (8% of
  height) + persona watermark below (5% of height, 85% opacity).
  Silent stereo AAC track so the title's stream layout matches the
  normalize_video output for the xfade graph.
- `normalize_video` — one ffmpeg invocation per source video:
  - Rotation via transpose (uses per-file rotation_degrees from
    Phase 4.x).
  - Scale-to-fit + letterbox pad to 1920×1080 (or user setting),
    `force_original_aspect_ratio=decrease` so nothing crops.
  - 30fps resample, setsar=1.
  - Watermark PNG overlay (reuses the Phase 4 cached PNG render
    keyed by persona profile, with the same 1.25× alpha boost).
  - Audio: `loudnorm=I=-16:TP=-1.5:LRA=11` + acompressor +
    200Hz/3kHz EQ (toggle in Settings).
  - Container: H.264 yuv420p / AAC 48kHz stereo / 192k / faststart.
- `assemble_master` — xfade chain across every input. Per-clip
  duration probed via ffprobe so xfade offsets line up. Final
  `fade=t=out` 1.0s tail. Re-encodes once at CRF 21 (master quality).

**Defaults seeded in `auto_assembly_settings`** (one-row table,
migration 011): 1920×1080 @ 30fps, 1.0s xfade, 10s title, audio
enhance on, DeepFilterNet off (Phase 4.5b).

**Trigger surfaces**:

- Edit tab → **🎞 Auto-assemble master** button (only shown when the
  bundle has videos). Single Tauri command `enqueue_auto_assemble`
  enqueues title + N normalize + assemble jobs in that order; the
  queue's `created_at ASC` ordering means they run sequentially with
  no extra dependency tracking. Failure of any prereq → the assemble
  step fails loudly (input missing); user re-clicks to retry.
- Settings → **🎞 Auto-Assembly** panel with sliders for every default
  + DeepFilterNet toggle (disabled, marked Phase 4.5b).

**Master output**: `~/Library/Application Support/com.phantomlives.sidemolly/work/<uid>/auto/master.mp4`.
Title + intermediate clips remain in `/auto/` for inspection /
manual re-use.

**Persona watermark text on title card**: uses the persona's
`watermark_profiles.text` (or PhantomLives defaults — CoC →
CurseOfCurves, PoA → PrincessOfAddiction, Sa → SheerAttraction)
even if the per-video watermark is disabled in Settings → Watermark.
The title card brand surface is intentionally always on.

### Migrations

- **010**: widen `jobs.kind` CHECK from `('process_video')` to no
  CHECK. Rebuilds the table SQLite-style. Validation lives in the
  Rust dispatcher (`jobs::dispatch`).
- **011**: new `auto_assembly_settings` table, seeded with defaults.

### Deferred to Phase 4.5b

- **DeepFilterNet voice isolation** — ONNX-based pre-filter before
  the FFmpeg audio chain. Needs ONNX runtime crate + the
  DeepFilterNet model file (~10MB) bundled into resources/, plus
  cross-platform packaging (macOS arm64+x86_64 / Windows x86_64).
  Schema column reserved; UI toggle disabled with explanatory label.
- Per-platform master variants (vertical 9:16 / square 1:1).
- Auto-assemble-on-ingest toggle.
- Incremental re-assemble (skip steps whose inputs unchanged).

### Tests

100 passing. New camelCase contracts for `AutoAssemblySettings`,
`RenderTitleParams`, `NormalizeVideoParams`, `AssembleMasterParams`,
`EnqueueAutoAssembleResult`. Migration smoke applies 010/011 and
checks `auto_assembly_settings` table exists. Per-kind params JSON
round-trip tests in `auto_assemble.rs` (escape semantics for
drawtext + serde renames).

## [0.7.0] — 2026-05-24

### Added — Phase 4.x: per-file rotation, per-media watermark toggles, live progress

Iteration on Phase 4. Driven entirely by user feedback running the
first real bundle through Edit/process and finding rough edges.

**Per-file rotation** (migration 009 + new `RotationGrid` in EditTab).
A bundle commonly mixes correctly-oriented files with sideways /
upside-down ones — iPhone clips, scanned photos, etc. Each `bundle_file`
now carries a `rotation_degrees` override (0/90/180/270), surfaced as
a thumbnail grid in the Edit tab. Click a thumbnail to cycle the
rotation; the preview rotates immediately via CSS `transform` so the
user sees the chosen orientation before processing. New
`set_bundle_file_rotation` command (validates degrees, scopes by
bundle_uid + in_zip_path). Applied during processing:

- Images: `DynamicImage::rotate90/180/270` before watermark, so the
  watermark lands in the bottom-right of the *corrected* frame.
- Videos: ffmpeg `transpose` filter prepended to the filter graph,
  same reasoning.

The per-batch rotation dropdown shipped in 0.6.0 is gone — fully
replaced by per-file controls.

**Per-media watermark toggles** (migration 008). The single `enabled`
column on `watermark_profiles` splits into `image_enabled` (default
**off**) and `video_enabled` (default **on**). PhantomLives photos
typically get hand-edited downstream so the watermark is wasted; videos
go to platforms direct and need provenance burn-in. Settings →
Watermark now shows two checkboxes per persona. Existing rows: old
`enabled` carries forward into `video_enabled`; `image_enabled` resets
to 0 per the new default policy.

**Video watermark visibility fixes** — the 0.6.0 watermark looked
washed out at the user's nominal 20% opacity, in two flavours:

- *Chroma loss*: ffmpeg's `overlay` filter defaults to `format=yuv420`,
  which subsamples chroma during compositing and attenuates pure-white
  text edges. Switched to `format=rgb` so the composite happens in
  full RGB; the final `-pix_fmt yuv420p` still converts for x264.
- *Size mismatch*: 0.6.0 rendered the overlay PNG against a hardcoded
  1080-px reference, then ffmpeg layered it on the actual frame
  unscaled. iPhone photos at 4032-tall got 4% text = 121 px; 720p
  videos got 4% of 1080 = 43 px overlaid on a 720-tall frame —
  visually much smaller. Now: ffprobe each video, render the PNG at
  `max(actual_height, 1440) * font_size_pct%` capped at 8% of actual
  frame height (handles anything from 240p webcam clips up through
  8K source). Margin always scales against the real frame so it
  stays proportional.
- *Perceptual nudge*: 1.25× alpha boost just for video PNGs. Video
  motion makes a static white watermark feel lighter than the same
  alpha on a still photo; 20% UI → 25% PNG alpha closes the gap.
  Image side untouched.

**Live image-processing progress** (`image-progress` event channel).
Bundle of 42 images was previously 60-90 seconds with a static "⏳
Working…" banner — looked frozen. Rust now emits one event per file
with `done`/`total`/`currentInZipPath` plus a final tick; EditTab
shows a fat progress bar with `X of N done`, %, and the current file
name. 500ms heartbeat ticks independently so the banner shows life
even between events. Command is now `async` + `spawn_blocking` so the
emit channel reliably flushes to the renderer mid-run instead of
queueing until return.

### Edit tab UX

- **`📁 Reveal`** button on every done `process_video` job (Jobs view)
  and every row in `Processed outputs` — surfaces the output `.mp4`
  in Finder. Backend command is scoped by job id / (uid, in_zip_path,
  op_kind), so we don't expose a generic "reveal arbitrary path".
- Each Processed outputs row also gets **`⧉ copy`** (copies the full
  output path to clipboard) and the resolved path is now rendered
  truncated under the filename — was invisible before.
- **`📁 Open bundle workspace`** button at the Processed outputs
  header reveals `~/Library/Application Support/com.phantomlives.sidemolly/work/<UID>/`
  so the user can browse the whole tree (the path is in `Library` and
  Finder won't open it from clicked text alone).
- Video thumbnails now appear in `Processed outputs` (was the 🖼
  placeholder before). `get_processed_previews` falls back to the
  source video's `bundle_files.thumbnail_path` for `kind='video'`
  rows — base64-embedding a raw `.mp4` as `data:image/jpeg` gave
  the browser garbage.
- Per-batch rotation dropdown removed (see per-file above).

### Other fixes

- **Migration 007** — widen `processed_files.op_kind` CHECK from the
  image-only list (`watermark`, `strip_exif`, etc.) to no CHECK at
  all, so Phase 4 video op kinds (`video_watermark_strip`,
  `video_clean`, etc.) can land. Validation moves to Rust (where
  new op kinds get added anyway).
- **`format=rgb` + overlay-with-PNG** for video watermarks (see
  visibility fixes above) instead of the original 0.6.0 `drawtext`
  filter — Homebrew's stock ffmpeg ships without libfreetype so
  `drawtext` was unavailable and every video job in 0.6.0 actually
  failed at the ffmpeg layer.
- **`build-app.sh` now wipes `dist/` + `tsconfig.tsbuildinfo*`** on
  every run. `tsc -b` is incremental and silently kept stale .d.ts/
  emit when source-only TSX changed, so the .app shipped without the
  newest React code twice in a row. Cheap to clean (~10s extra).

### Tests

91 passing. New + adjusted:
- Migration smoke now applies 007/008/009.
- `WatermarkProfileRow` camelCase contract covers `imageEnabled` +
  `videoEnabled`.
- `ImageProgressEvent` camelCase contract.
- `BundleFileRow` covers `rotationDegrees`.
- `process_video_params_round_trips_via_json` covers the new
  `rotation` field.
- `render_watermark_png_produces_valid_rgba_png` updated for the new
  `font_size_px`-direct signature.

## [0.6.0] — 2026-05-24

### Added — Phase 4: video ops via ffmpeg + background jobs queue

Video transcode + watermark + metadata-strip via a new background
worker. Bundle workspace Edit tab now has parity with the image side
(Phase 3) — but videos take minutes per clip, so they're processed
asynchronously through the new `jobs` queue rather than blocking the
UI.

**Background jobs queue** (`jobs.rs` + migration 006). One sequential
worker thread spawned from `lib.rs::setup`, polls the `jobs` table
every 2s, claims the oldest pending row via atomic UPDATE, dispatches
by kind, writes back `done` or `failed` + `last_error`. Per-attempt
audit trail in `job_runs`. Emits `job-updated` Tauri events the
frontend listens to.

**Video pipeline** (`video.rs`). One ffmpeg invocation per video:

```
ffmpeg -y -i <src>
  -map_metadata -1                       # strip global metadata
  [-vf drawtext=fontfile='...':text='...':fontcolor=white@N:
     fontsize=h*N:x=...:y=...]           # when watermark on
  -c:v libx264 -crf 23 -preset medium    # H.264 transcode
  -pix_fmt yuv420p
  -c:a aac -b:a 128k                     # AAC audio
  -movflags +faststart                   # web-streaming friendly
  <dst.mp4>
```

Atomic via `.sm-tmp.mp4` + rename. 30-min wall-clock timeout per job.
Stderr captured + surfaced through `jobs.last_error`. `ffmpeg_bin()`
probes `/opt/homebrew/bin/ffmpeg` → `/usr/local/bin/ffmpeg` → bare
`ffmpeg` (cached in `OnceLock`), so Finder-launched apps work without
shell PATH inheritance.

**Watermark drawtext expressions** — 9-grid position mapping uses
ffmpeg's per-frame variables (`w`, `h`, `tw`, `th`) so the same
profile that styled images in Phase 3 renders identically on video.
Reuses the per-persona `watermark_profiles` table.

### Bundle workspace Edit tab

Now has two sections:

- **Image ops** (synchronous, runs in the foreground)
- **Video ops** (asynchronous, queues into 🛠 Jobs)

Each with three op checkboxes (watermark / strip metadata / rename)
plus a "Process N" button. Status pane below shows the latest action's
outcome with expandable per-file error details.

### Sidebar 🛠 Jobs entry

New view between Inbox and Settings. Filter pills for all / pending /
running / done / failed with live counts. Per-row pill with status
glyph + colour + expandable error block when a job fails. Updates
automatically on every `job-updated` Tauri event — no polling on the
frontend.

### Schema (migration 006)

- `jobs` — id PK, kind CHECK (currently just `process_video`),
  params_json, bundle_uid FK CASCADE nullable, source_in_zip_path
  nullable, status CHECK (pending/running/done/failed), attempts,
  last_error, timestamps. Indexed on `(status, created_at)` for the
  worker's claim query.
- `job_runs` — id PK, job_id FK CASCADE, started_at, finished_at,
  exit_code, log_path. Append-only per attempt.

### New Tauri commands

- `enqueue_bundle_video_ops(uid, ops)` → `EnqueueVideoOpsResult` —
  fans out one job per video in the bundle.
- `list_jobs(statusFilter)` → `Vec<JobRow>` — filtered by status, 200-row cap.
- `list_job_runs(jobId)` → per-attempt audit trail.

### Tests

**90 cargo tests** (was 74 in v0.5.0) + 1 vitest:

- `jobs::tests` (6) — enqueue→claim transitions running + increments
  attempts; claim returns None on empty queue; claim doesn't re-claim
  a running row; mark_done clears last_error; claim orders by
  created_at ASC; list filters by status; record_run persists per-attempt.
- `video::tests` (5) — bottom-right drawtext expression uses
  `w-tw-h*N` / `h-th-h*N`; middle-center uses centered formulas;
  escape_filter_value handles quotes + backslashes; opacity > 100
  clamps to white@1.00; top-left uses margin for both axes.
- `camel_case_contract` (+4) — `VideoOpsInput`, `EnqueueVideoOpsResult`,
  `JobRow`, `JobRunRow`.
- `migration_smoke` extended for 006; asserts `jobs` + `job_runs`
  tables exist.

### Deferred to later sub-phases

- **Trim** — needs a time-range selector UI (Phase 4.1).
- **Multi-preset library** — Phase 4.5 (Auto-Assembly) covers a
  master-output preset; per-platform variants in Phase 7+.
- **Job cancel + retry** — Phase 12 (Jobs panel polish).
- **Live progress streaming** — current implementation only surfaces
  final status; mid-transcode percentage is a Phase 12 add.

### Internal

- `bundles::paper_daisy_path(handle)` factored out from
  `paper_daisy_bytes` so `video.rs` can hand a path to ffmpeg's
  `drawtext` filter (it needs a file, not bytes).
- `thumbnails::ffmpeg_bin` made `pub` so `video.rs` shares the
  Homebrew-path probe + `OnceLock` cache.

## [0.5.0] — 2026-05-24

### Added — Phase 3: image ops + per-persona watermark + Bundle Edit tab

First phase where SideMolly **transforms** bundle content rather than
just reading it. Three primitives:

**Watermark stamping.** Paper Daisy text overlay rendered with
`ab_glyph` + `imageproc::drawing::draw_text_mut`. Per-persona profile
(text, opacity 0-100, 9-position grid, font-size %, margin %) stored
in the new `watermark_profiles` table. Defaults seeded per PLAN.md
§12 #24: CoC → `CurseOfCurves`, PoA → `PrincessOfAddiction`, Sa →
`SheerAttraction`. 20% opacity, bottom-right, 4% font size, 2.5%
margin. The `''` row catches null-persona bundles + serves as the
editable default.

**EXIF strip.** Re-encoding via the `image` crate's JPEG encoder
naturally drops EXIF/XMP/IPTC/ICC — anything that isn't pixel data
goes. Output is a fresh quality-92 JPEG, on average smaller than the
RAW/PNG source.

**Rename (output only).** Template applied to the output filename
only — sources are never touched. Current template:
`{date}_{persona}_{NN}.jpg` (omits the persona segment when null).
More templates land alongside Dropbox copy in Phase 6.

### Bundle workspace · new Edit tab

Replaces the disabled placeholder from Phase 1c. Per-bundle UI:

- Three op-checkboxes (Watermark / Strip EXIF / Rename). Default:
  Watermark + Strip EXIF on, Rename off.
- "Process N images" button — invokes `process_bundle_images`, which
  loads the bundle's persona-bound watermark profile, walks every
  image-kind row, and writes processed outputs to
  `work/<UID>/processed/<basename>__<op>.jpg` with atomic
  `.sm-tmp.jpg` + rename.
- Results list with persisted history (`processed_files` table) —
  shows source path, op_kind, created_at, and a 64-px preview via
  the same data-URL pattern used for thumbnails.
- Errors surface inline per source file with the failure reason.

### Settings · new Watermark tab

One card per persona profile (sorted with `''` default first).
Editor controls:

- Text input (blank disables watermark for that persona)
- Opacity slider (0-100 with live readout)
- 9-position picker (3×3 grid of arrow glyphs ↖ ↑ ↗ ← • → ↙ ↓ ↘)
- Font-size % and margin % numeric inputs
- Enabled toggle
- Per-row Save button

### Schema (migration 005)

- `watermark_profiles` — `persona_code PK, text, opacity_percent
  CHECK 0..100, position CHECK 9-grid, font_size_pct, margin_pct,
  enabled, timestamps`. Seeded with 4 rows (`''`, CoC, PoA, Sa).
- `processed_files` — `id PK, bundle_file_id FK CASCADE, op_kind
  CHECK, output_path, output_sha256, params_json, created_at,
  UNIQUE(bundle_file_id, op_kind)`. UPSERT on re-run.

### New Tauri commands

- `get_watermark_profiles()` → `Vec<WatermarkProfileRow>`
- `set_watermark_profile(profile)` — UPSERT
- `process_bundle_images(uid, ops)` — apply ops to every image in the
  bundle, returns `ProcessImagesResult { processed, skipped, errors }`
- `list_processed_files(uid)` — audit trail per bundle
- `get_processed_previews(uid)` — `Map<inZipPath, dataUrl>` for the
  most-recent processed output per source (same pattern as
  `get_bundle_thumbnails` from v0.4.0)

### Tests

**74 cargo tests** (was 62 in v0.4.0) + 1 vitest:

- `images::tests` (8) — strip-EXIF round-trip preserves dimensions;
  watermark modifies bottom-right pixels at 100% opacity;
  TopLeft position paints top-left; 0% opacity is a no-op;
  output_path layout is stable; rename template covers persona +
  no-persona; op_kind combination maps correctly; all 9 positions
  parse round-trip.
- `camel_case_contract` (+4) — `WatermarkProfileRow`, `ImageOpsInput`,
  `ProcessedFileRow`, `ProcessImagesResult`.
- `migration_smoke` extended for 005; asserts `watermark_profiles`
  and `processed_files` tables exist post-migration.

### Implementation notes

- `paper_daisy_bytes(handle)` resolves the bundled
  `resources/fonts/PaperDaisy.ttf` via Tauri's `resolve_resource`
  for release builds, falls back to `CARGO_MANIFEST_DIR` in tests.
- Watermark profile lookup falls through to the `''` default when
  the bundle's persona is unknown or its profile is disabled / has
  empty text.
- Sources are read-only — every transformation writes a sibling to
  `processed/` keyed on the op combination, never overwriting the
  extracted file.

## [0.4.0] — 2026-05-24

### Added — Phase 1c: thumbnails + DocDrawer + grouped Files view

**Per-file thumbnails.** Every image and video in the bundle gets a
256-px JPEG thumbnail at ingest time, stored under
`work/<UID>/.thumbs/<sha8>.jpg`. Image thumbs use the `image` crate
(JPEG/PNG/GIF/WebP); video thumbs spawn `ffmpeg -ss 1 -frames:v 1
-vf scale=256:-1` against the system `ffmpeg` if present, with a
10-second kill timer and a graceful fall back to the kind glyph if
ffmpeg is missing. Thumbnails are idempotent — repeat ingests skip
files that already have a non-empty thumb at the deterministic
sha-keyed path.

**Export thumbnails.** Per-bundle, SideMolly picks 10 random
thumbnails (deterministically seeded on bundle UID via xorshift64*) and
stores them in a new `bundle_export_thumbs` table. Phase 11 will pack
these into `artifacts/thumbnails/` of the post-bundle ZIP returned to
Molly. Selection is replaced (DELETE+INSERT) on every re-ingest so
the picks track the current file set.

**Bundle workspace reorganized:**

- New `TopTrio` row above the Files list — three pill buttons for
  **Manifest**, **Molly.log**, **info.md**. Click pops out a right-side
  `DocDrawer`. Manifest renders the parsed `BundleManifest` as a
  pretty key/value layout (no Finder hop); Molly.log renders as
  monospace text; info.md renders via a hand-rolled `markdownLite`
  parser supporting H1-H3 / lists / blockquote / code blocks / inline
  code / bold / italic / links / rules. Each drawer has a Reveal button
  if Robert wants the underlying file in Finder.

- **Files list grouped:**
  - **FanSite bundles:** sections per day (`FAN-SITE DAY 01 / 02 …`)
    with the day's message inline and per-row `D01/01` prefix.
  - **Content / Custom bundles:** grouped by kind (`VIDEO / IMAGE /
    AUDIO`) with `#00001` position prefix where applicable.

- **Thumbnails in rows:** each file row shows its actual thumbnail
  rendered inline as a `data:image/jpeg;base64,…` URL. The Bundle
  workspace fetches all of a bundle's thumbs in a single
  `get_bundle_thumbnails` IPC call on mount and keys them by
  `inZipPath`. Rows without a thumb (videos that ffmpeg couldn't
  process, HEIC images, info/log/manifest kinds) fall through to the
  kind glyph.

  *Implementation note.* The first attempt used Tauri's
  `convertFileSrc` → `asset://localhost/<encoded-path>` — but WKWebView
  on macOS 15 silently rejected those URLs even with
  `assetProtocol.scope: ["**"]` + permissive CSP + no sandbox
  entitlements. Diagnostic captured 2026-05-24: img onError fired
  immediately. Data URLs sidestep the asset-protocol handshake entirely
  and render anywhere; cost is ~13KB of base64 per 10KB JPEG (one-time
  per bundle workspace open, all local IPC).

- **Size control** — three-state S/M/L (48 / 96 / 192 px) above the
  Files list, persisted to `localStorage` under
  `sidemolly.thumbSize`. Default M.

### Schema

- **Migration 004 — `bundle_export_thumbs`** — `id PK,
  bundle_uid FK CASCADE, bundle_file_id FK CASCADE, position CHECK
  1..10, thumbnail_path` with `UNIQUE(bundle_uid, position)` and
  `UNIQUE(bundle_uid, bundle_file_id)`.

- **`bundle_files`** rows now also expose `working_path` +
  `thumbnail_path` over the IPC boundary (already in the schema,
  un-exposed before).

### New Tauri commands

- `read_doc_text(uid, in_zip_path)` — reads a workspace text file
  (Molly.log / info.md / manifest.json) with a 256 KB safety cap.
- `get_export_thumbnails(uid)` — returns the 10 picks joined with
  their source file's in-zip path.
- `get_bundle_thumbnails(uid)` — returns `Map<inZipPath, dataUrl>`
  for every file that has a thumbnail; base64-encodes the JPEGs
  server-side so the webview can render them via `<img src="data:…">`
  without depending on the asset protocol.

### Tests

**62 cargo tests** (was 55 in v0.3.0) + 1 vitest:

- `thumbnails::tests` (6) — image thumb writes a smaller JPEG; idempotent
  skip when thumb exists (proven by deleting the source between calls);
  corrupt image returns Ok(None) not Err; non-media kinds return None;
  ffmpeg-missing path returns None gracefully; sha-keyed filename is
  stable + 16 hex chars.
- `camel_case_contract` (+1) — `ExportThumb`. Updated `IngestResult`
  and `BundleFileRow` contracts for new fields.
- `migration_smoke` extended for 004; asserts `bundle_export_thumbs`
  table exists post-migration.
- `bundles::tests::fresh_db` extended to apply migration 004.

### Internal

- `bundles::ingest_bundle_inner` now does a per-file thumbnail pass +
  export-thumb selection after extract. Stale picks from a previous
  ingest get DELETE'd before the new ones land.
- `thumbnails::ffmpeg_bin()` probes `/opt/homebrew/bin/ffmpeg` →
  `/usr/local/bin/ffmpeg` → `/usr/bin/ffmpeg` → bare `ffmpeg` (cached
  in a `OnceLock`). Required because Finder-launched macOS apps
  inherit a minimal PATH that excludes Homebrew prefixes.
- ffmpeg invocation captures stderr and emits diagnostic lines on
  non-zero exit / timeout — surfaced the "Unable to choose an output
  format for `.jpg.sm-tmp`" muxer error that gated the original video
  thumbnail attempts. Fix: tmp file extension is now `.sm-tmp.jpg`
  (final extension `.jpg`) so ffmpeg can sniff the image2/mjpeg muxer.
- `watch::already_ingested` extended for the v0.3.0 → v0.4.0 +
  ffmpeg-fix upgrade case: also returns `false` when the bundle has
  video files but zero of them have a `thumbnail_path`, so the launch
  scan force-re-ingests automatically (no manual "Scan now" needed).
- `DocDrawer` info-md rendering: hoisted the markdown-parse `useMemo`
  to top-level of the component. The first attempt called it inside a
  JSX ternary, violating Rules of Hooks — different hook count
  between renders → React aborted the tree → blank screen requiring
  app restart. Caught by Robert on first click.

## [0.3.0] — 2026-05-24

### Added — Phase 1b: watched folder + inner-zip extract

Closes out Phase 1's full scope (PLAN.md §11). Two additions:

**Watched folder.** A background thread watches the configured bundle
folder (default `~/Downloads/Molly bundles/`, configurable in Settings →
Watched folder) and auto-ingests anything Molly drops. On launch:
scan the dir and ingest any `.zip` not already in the DB. Ongoing: a
`notify` recommended_watcher (FSEvents on macOS, ReadDirectoryChangesW
on Windows, inotify on Linux) fires for new/changed `.zip` files, the
watcher debounces 1s for file-flush, then re-scans force-ingesting.
Re-ingest is safe — the UPSERT path from v0.2.0 handles it. Frontend
listens to `bundle-ingested` Tauri events and refreshes the Inbox the
moment a bundle lands.

**Inner-zip extraction.** Every successful ingest now also extracts the
inner zip to
`~/Library/Application Support/com.phantomlives.sidemolly/work/<UID>/`
with the layout Molly emits (`Audio/`, `Video/00001_…`,
`Photos/00001_…`, `FanSite/DD_NN_…`, `info.md`, `Molly.log`). Each
`bundle_files` row's `working_path` is stamped so Phase 3+ image/video
ops can locate files by SQL without re-extracting on demand.
Extraction is idempotent — re-ingest only writes files whose size
differs from disk; identical re-runs are no-ops. Atomic write via
`.sm-tmp` + rename so a crash mid-extract leaves any previous file
intact.

**Settings → Watched folder** pane (new): resolved path readout
(monospaced), "Choose folder…" picker, "Use default" reset,
"Reveal in Finder", "Scan now" button (manual force-rescan that
returns considered / ingested / skipped / failed counts + per-file
error details).

**Bundle workspace Overview Files pane** gains a "📁 Reveal folder"
button for the whole bundle workspace + a small "📁" per file row to
reveal that specific extracted file in Finder.

### Changed

- `ingest_bundle` now also returns `workspacePath` + `extractedCount`
  in `IngestResult`, alongside the existing fields.
- `ValidatedBundle::inner_zip_bytes` newly populated by
  `bundle_io::verify_outer_zip` so `extract::extract_inner_zip` doesn't
  re-open the outer file from disk.

### Tests

**55 cargo tests** (was 44 in v0.2.0) + 1 vitest:

- `extract::tests` (6) — fresh extract writes everything, re-extract
  is idempotent no-op, partial-state resume only writes missing files,
  size mismatch triggers rewrite, nested dir layout preserved,
  workspace dir resolution.
- `watch::tests` (3) — is_bundle_zip filter (dir / non-zip excluded),
  case-insensitive `.ZIP` extension, default-watch-dir contract.
- `camel_case_contract` (+2 new) — `WatchSettings`, `ScanResult`.
- `bundles::tests` updated for the `inner_zip_bytes` field on
  `ValidatedBundle`.

### Internal

- New `notify = "6"` + `tokio` deps in Cargo.toml. tokio default
  features stay off; only `time / rt / sync / macros` enabled.
- New `bundles::ingest_bundle_inner(&handle, &path)` — borrow-flavoured
  ingest the watcher thread uses so it doesn't clone `AppHandle` per
  scan. The `#[tauri::command] ingest_bundle` just forwards.

## [0.2.0] — 2026-05-24

### Added — Phase 1: bundle ingest + Inbox + Bundle workspace Overview

The first real feature. Drop a Molly bundle ZIP anywhere on the SideMolly
window — the OS-level drag-drop routes via Tauri 2's `onDragDropEvent`,
each `.zip` runs through full hash verification, the manifest is parsed,
the bundle (and every entry it carries) lands in SQLite, and the workspace
opens on the Overview tab.

**Pipeline.**

1. `bundle_io::verify_outer_zip` — open outer ZIP, parse `hashes.json`,
   re-hash the inner ZIP bytes (asserted == `innerZip.sha256`), then
   re-hash every entry inside the inner ZIP (asserted == `files[].sha256`).
   Returns `ValidatedBundle` with the parsed hashes doc + extracted
   `info.md` / `Molly.log` / optional `manifest.json` bytes + per-entry
   sizes.
2. `manifest::parse_manifest_json` (preferred, Phase 2+) or
   `manifest::parse_molly_log` (fallback, today's bundles). Both
   normalize to a single `BundleManifest` struct so downstream code
   never branches on source. The Molly.log parser handles
   Content / Custom / FanSite bundle types, multi-line `Description
   text:` and `Special instructions:` continuations (`  | …` rows),
   `Categories (N):` numbered lists, and FanSite `Day NN (M file/files):
   message` rows (singular and plural).
3. `bundles::ingest_bundle` — opens a rusqlite connection at the same
   `sidemolly.db` tauri-plugin-sql owns, runs a single transaction:
   `INSERT … ON CONFLICT(uid) DO UPDATE` on `bundles`, then `DELETE +
   bulk INSERT` on `bundle_files`. Re-ingesting the same UID UPSERTs in
   place; user-side state on sibling tables (Phase 7+ postings) is
   keyed on uid and never gets clobbered.

**Schema** (migrations 002 + 003).

- `bundles` — uid PK, bundle_type CHECK (content / custom / fansite),
  persona_code, title, source_zip_path, source_zip_sha256, ingested_at,
  verify_status CHECK (pending / verified / failed), verify_error,
  manifest_source CHECK (manifest_json / molly_log), manifest_json TEXT,
  bundle_state CHECK (new / in_progress / shipped / archived),
  created_at, updated_at.
- `bundle_files` — bundle_uid FK CASCADE, in_zip_path,
  original_name, kind CHECK (video / image / audio / info / log /
  manifest / other), position, fansite_day_of_month, sha256, size_bytes,
  working_path (Phase 3+ extract output), thumbnail_path (Phase 3+),
  UNIQUE(bundle_uid, in_zip_path).

**Frontend.**

- `src/data/bundles.ts` — typed wrappers (`ingestBundle`, `listBundles`,
  `getBundle`), shared presentation helpers (`personaChipColor`,
  `bundleTypeEmoji`, `verifyStatusBadge`, `fmtPrice`, `fmtSize`).
- `src/views/Inbox/InboxView.tsx` — populated list, click → workspace.
- `src/views/Bundle/BundleWorkspace.tsx` — per-bundle header, tab strip
  (Overview wired; Files / Edit / Distribute / Post stubbed for later
  phases), back-to-Inbox control.
- `src/views/Bundle/OverviewTab.tsx` — manifest pane (with
  bundle-type-specific fields), FanSite day list with messages, file
  list grouped by stats with kind glyph + size + sha.
- `App.tsx` — Tauri 2 `onDragDropEvent` listener, hover outline on the
  window during drag, ingest-status banner (busy/ok/error with auto-
  dismiss control), workspace overlay when a bundle is open.

**Tests added.**

- `bundle_io::tests` (7): happy path, mismatched inner hash, mismatched
  file hash, malformed hashes.json, missing hashes.json, kind classifier,
  in-zip prefix parsers (Content + FanSite).
- `manifest::tests` (9): real FanSite log fixture from
  `2026-05-22-0002.zip`, Content log, Custom log, Custom
  handled-in-platform, Custom URL delivery, missing-required-field
  guards, manifest.json v1 (Content + FanSite), malformed JSON.
- `bundles::tests` (5): persist inserts both tables, re-ingest idempotent
  UPSERT preserves UID-keyed rows + replaces file list, FanSite file
  rows capture day + position + parsed original name, CASCADE wipes
  files when bundle is deleted, CHECK rejects invalid bundle_type.
- `lib.rs::camel_case_contract` (+8 new boundary structs): `IngestResult`,
  `BundleSummary`, `BundleFileRow`, `BundleDetail`, `BundleManifest`,
  `FanDay`, `HashesDoc`, `HashesInnerZip`, `HashesFile`.
- `lib.rs::migration_smoke`: extended for 002 + 003; asserts CHECK
  constraints reject invalid bundle_type + invalid kind.

**44 cargo tests + 1 vitest** (was 13 in Phase 0).

**Pre-existing punch-list items (still open).** Per-bundle file extraction
to `app_data/work/<UID>/`, watched-folder ingest, and Files / Edit /
Distribute / Post sub-tabs land in Phase 1b → Phase 3+. Placeholder icons
+ updater pubkey placeholder still flagged from v0.1.0.

## [0.1.0] — 2026-05-23

### Added — Phase 0: app scaffold

The empty installable app. Sidebar shell (Inbox / Settings / Manual),
Settings → Backup pane with the full CLAUDE.md-required UI surface
(toggle / retention stepper / Run Backup Now / Reveal / Recent list with
Test / Restore / Reveal / last-backup readout / status line), and
auto-backup-on-launch with 5-minute debounce + 14-day retention default.

CI release pipeline at `.github/workflows/release-sidemolly.yml`,
triggered by `sidemolly-v*` tags, signs builds for macOS arm64 and
Windows x64 with a SideMolly-scoped minisign keypair and publishes
`sidemolly-latest.json` for the auto-updater.

`build-app.sh` chains into `install.sh` (per the PhantomLives install.sh
standard) so `./build-app.sh` does build + install to `/Applications/` +
relaunch in one shot. `--no-install` and `--no-open` opt-outs supported.

Paper Daisy `PaperDaisy.ttf` bundled in `src-tauri/resources/fonts/` and
ready for the Phase 4.5 Auto-Assembly burn-in. Commercial license shared
with Molly v1.14.1 — purchased 2026-05-23 from maja.mint.

### Tracking surface

- Frontend: 1 vitest smoke test passing (more land in Phase 1).
- Rust: backup tests (debounce / retention prefix guard / list ordering
  / target-dir auto-create / verify-missing-DB / debounce constant +
  fsutil contract test + camelCase contract for Settings/BackupRow/
  VerifyResult + migration smoke. ~10 tests as of v0.1.0.

### Open items pre-Phase 1

- `src-tauri/icons/` is **placeholder** — copied from Molly so the build
  succeeds. Replace with SideMolly's own design before the first signed
  release. See `src-tauri/icons/PLACEHOLDER.md` for the workflow.
- `tauri.conf.json::plugins.updater.pubkey` is a placeholder. Generate a
  SideMolly-scoped minisign keypair via
  `pnpm tauri signer generate -p '' -w ~/.config/sidemolly-secrets/updater.key`
  and paste the public half before cutting the first signed release.
  The private half also lands as the `SIDEMOLLY_TAURI_SIGNING_PRIVATE_KEY`
  GitHub secret.
