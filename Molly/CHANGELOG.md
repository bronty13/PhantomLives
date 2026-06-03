# Changelog

All notable changes to Molly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Molly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.29.0] — 2026-06-03

### Changed — GIF Studio now runs on a bundled native ffmpeg (any iPhone format works)

Replaced the entire WebView-based media pipeline (canvas + gifenc + WebCodecs/
mp4-muxer, with an ffmpeg-WASM fallback) with a **bundled native ffmpeg engine**
driven from Rust. The WebView could not decode iPhone **HEVC/H.265** on Windows
(WebView2 has no HEVC decoder), and ffmpeg-WASM was unusably slow (minutes on an
M5 Max — single-threaded software HEVC decode). Now Molly decodes/encodes
**any current iPhone/Windows format** — HEVC, H.264, **Dolby Vision HDR**,
ProRes — for GIFs, teaser MP4s, and frame thumbnails.

- **New Rust media engine** (`src-tauri/src/media/`): `probe_video`,
  `make_preview_proxy`, `generate_gif`, `generate_teaser_mp4`, `grab_frame`.
  Input-seeks the original file (`-ss` before `-i`) so only the trimmed segment
  is processed — fast even for long 4K sources. Output bytes returned over the
  binary IPC channel; progress streamed via a per-call `Channel`.
- **GIF** via palettegen/paletteuse (quality → 256/128/64 colors); **MP4** via
  libx264 + AAC + faststart (yuv420p, ≤60 s, 100 MB backstop); **frame** via a
  single `-frames:v 1`. Crop/scale from the frontend's `computeOutputSize`
  pixels; caption rendered to a transparent PNG (the existing `drawCaption`
  look) and composited via `overlay`.
- **HDR → SDR tone-mapping** (zscale + `tonemap=hable`) applied only when the
  source is HDR (ffprobe `color_transfer`), so iPhone Dolby Vision clips don't
  come out washed-out. iPhone DV Profile 8.4 has an HLG-compatible base layer,
  so this works without libplacebo. Degrades gracefully (skips tone-map) if the
  resolved ffmpeg lacks zimg.
- **Preview**: the source `<video>` is now scrub-only (never drawn to a canvas),
  so `convertFileSrc` is used directly — no more canvas-taint workarounds.
  Undecodable sources get a fast low-res H.264 **proxy** for scrubbing while the
  real output is rendered from the original at full quality.
- **Bundling**: ffmpeg/ffprobe GPL static builds are CI-downloaded
  (BtbN win64-gpl / OSXExperts arm64), verified (arch + zscale + libx264), and
  shipped via `bundle.resources` (~+80–100 MB/installer). Discovery prefers the
  bundled binary, then a Settings override, then PATH (dev Macs / SideMolly).
  See `THIRD_PARTY_LICENSES.md` (GPL). Aligns with SideMolly's ffmpeg pipeline
  for a future merge.
- **Removed**: `gifenc`, `mp4-muxer`, `@ffmpeg/ffmpeg`, `@ffmpeg/core`,
  `@ffmpeg/util`; `recordMp4.ts`, `transcode.ts`, canvas encoders in
  `encodeGif.ts`. Net frontend bundle shrinks (no 32 MB WASM).
- Tests: 22 new Rust tests (filtergraph/crop/HDR/probe builders); the exact
  filtergraphs were smoke-tested against real ffmpeg.

> This supersedes the 1.28.x stopgaps (WebCodecs MP4 mux, same-origin blob,
> `.mov` MIME, ffmpeg-WASM). Those are gone — the native engine subsumes them.

## [1.28.3] — 2026-06-03

### Fixed — .mov sources no longer rejected by a wrong blob MIME; clearer codec guidance

Two follow-ups to the 1.28.2 blob-source change:

- **`.mov` MIME regression.** 1.28.2 labelled the source blob by extension,
  tagging `.mov` as `video/quicktime` — a type Chromium/WebView2 does **not**
  advertise support for, so the `<video>` element refused the file even when
  the H.264 inside was perfectly decodable. Now we only set explicit,
  known-good types for `mp4`/`webm` and leave `mov`/`mkv`/`avi` blank so the
  engine sniffs the bytes (the same way `convertFileSrc` used to).
- **Honest, helpful decode error.** The old message said "On a Mac, .mov
  files sometimes won't decode" — backwards and confusing on Windows. When the
  WebView genuinely can't decode a video's frames (`videoWidth === 0`), Molly
  now explains it's usually an **iPhone HEVC/H.265 .mov** (Chromium/WebView2
  has no HEVC decoder; Safari/WKWebView on macOS does — hence "works on my
  Mac"), and points to an **H.264 .mp4** or Microsoft's free **"HEVC Video
  Extensions"**. It's surfaced on load (not just at export) across GIF export,
  MP4 export, and the Frame Grabber.

> Known limitation: Molly still can't *decode* HEVC itself on Windows — it
> relies on the WebView. iPhone HEVC clips need either the HEVC Video
> Extensions installed or conversion to H.264. Auto-transcoding is a possible
> future addition.

## [1.28.2] — 2026-06-03

### Fixed — the *real* Windows fix: source video loads same-origin so the canvas isn't tainted

This is the root cause behind both 1.28.0 (corrupt MP4) and 1.28.1 (it threw
instead). The source `<video>` was loaded with `convertFileSrc`, i.e. Tauri's
asset protocol — a **cross-origin** source with no CORS header. On Windows
(WebView2) drawing that video onto a canvas **taints** the canvas, and a
tainted canvas blocks *every* pixel operation the studio relies on:

- `getImageData` → **GIF export** (so the GIF wizard was silently broken on
  Windows too — same root cause, just never reported),
- `new VideoFrame()` / `captureStream()` → **MP4 export** (the 1.28.0 / 1.28.1
  errors), and
- `toBlob` / `toDataURL` → **Frame Grabber** thumbnails.

Fix: load the source from a **same-origin `blob:` URL** built from the file's
bytes (new `read_file_bytes` command transfers them over the raw binary IPC
channel; `loadVideoObjectUrl` wraps them in a `Blob`). A `blob:` URL is
same-origin, so the canvas stays origin-clean and GIF, MP4, and Frame Grabber
all work on Windows. Seeking stays instant (the whole file is in the blob),
which the trim sliders depend on.

- Both GIF Creator and Frame Grabber switched off `convertFileSrc`; export
  buttons disable while the source loads, with a "loading video…" hint.
- `crossOrigin="anonymous"` was not an option: Tauri's asset protocol can't
  supply the matching `Access-Control-Allow-Origin` header
  (tauri-apps/tauri#12999), so it would only break loading.
- Trade-off: the source file is read fully into memory. Fine for typical
  teaser sources; revisit with a CORS-enabled custom protocol if huge sources
  become a problem.

### Changed — updater feed decoupled from the repo-wide "latest" release

Molly's updater endpoint pointed at
`releases/latest/download/latest.json`. In this monorepo `releases/latest`
is repo-wide, so a SideMolly release becomes GitHub's "latest" — and that
release carries `sidemolly-latest.json`, not `latest.json`, so Molly's
updater would **404 and silently stop finding updates** whenever SideMolly
shipped more recently than Molly.

- Endpoint now points at a stable, Molly-scoped prerelease:
  `releases/download/molly-updater-feed/latest.json`.
- `release-molly.yml` gained a step that creates (once) and re-uploads
  `latest.json` to the `molly-updater-feed` prerelease on every Molly
  release. Install URLs inside the manifest are absolute (versioned tag),
  so they resolve regardless of where the manifest is hosted.
- Ships with the next tagged release; takes effect for that build onward.
- Note: this is independent of the Windows updater "unsupported Zip archive"
  error (a `zip`-reader issue in the *installed* plugin-updater), which is
  still under investigation.

## [1.28.1] — 2026-06-03

### Fixed — WebCodecs MP4 export no longer fails with a tainted-canvas SecurityError

1.28.0's WebCodecs encoder built frames with `new VideoFrame(canvas, …)`. On
Windows (WebView2) the source `<video>` is loaded via Tauri's asset protocol
(`convertFileSrc`), which is a cross-origin source with no
`Access-Control-Allow-Origin` header (Tauri doesn't expose one — see
tauri-apps/tauri#12999). The `VideoFrame` *constructor* enforces a strict
origin-clean check and threw:

> `SecurityError: Failed to construct 'VideoFrame': VideoFrames can't be
> created from tainted sources.`

…so MP4 export was completely broken on Windows in 1.28.0 (worse than 1.27.4,
which at least produced a file).

Fix: feed the encoder from the canvas's **`captureStream()` → `MediaStreamTrackProcessor`**
instead of constructing `VideoFrame`s ourselves. That's the exact capture
route the previous MediaRecorder path used (which worked), and frames
delivered by the stream pipeline aren't subject to the constructor's
tainted-source check. `crossOrigin="anonymous"` was rejected as a fix because
Tauri's asset protocol can't supply the matching CORS header, which would just
break video loading instead.

- The on-screen preview, GIF export, and trim/crop/caption are all unchanged.
- Keyframe cadence (start + every ~2s) and the `'offset'` muxer timestamp
  rebasing are preserved; the captureStream supplies frame timestamps.

> ⚠️ Like the 1.28.0 encoder, this path only runs under WebCodecs/WebView2
> (Windows) and can't be exercised on the maintainer's macOS WebKit (which
> falls back to MediaRecorder/`.webm`). Needs a Windows smoke test.

## [1.28.0] — 2026-06-03

### Fixed — teaser MP4s now play on Windows (real, seekable MP4 via WebCodecs)

Teaser clips exported on Windows came out corrupt/unplayable in Windows'
own players (Movies & TV, Media Player) and most upload targets, even
though no error was thrown and the same clip played fine on macOS.

Root cause: the clip recorder used the browser engine's `MediaRecorder`.
On Windows (WebView2/Chromium) that produced a `video/mp4` whose
index/duration metadata (`moov`) was written at the **end** of the file in
a streaming layout — Chromium and VLC tolerate it, but Windows' native
players reject it (duration reads 0, no seek table up front). macOS WebKit
can't `MediaRecorder` MP4 at all, so it silently fell back to `.webm`,
which played — hence "works on Mac, broken on Windows."

Fix: when WebCodecs is available (WebView2 on Windows), Molly now encodes
H.264 itself (canvas → `VideoEncoder`) plus AAC audio (source track →
`AudioEncoder`) and muxes a **progressive MP4 with `moov` at the front and
a real duration** via `mp4-muxer` (`fastStart: 'in-memory'`). The result
is a standard, seekable `.mp4` that plays in Windows players and uploads
cleanly. The draw pipeline is unchanged, so trim + crop + caption still
match the GIF exactly.

- Falls back gracefully: engines without WebCodecs/`MediaStreamTrackProcessor`
  (e.g. the maintainer's macOS WebKit) keep the existing MediaRecorder path
  and still emit `.webm` for local testing.
- If a system has WebCodecs but no AAC encoder, the clip ships as a clean
  **silent** MP4 rather than a corrupt one.
- H.264 profile is negotiated most-compatible-first (Baseline 3.0 → Main 4.0
  → High 4.0); a keyframe is forced at the start and every ~2s for seekability;
  output dimensions are forced even (H.264 requirement).
- New dependency: `mp4-muxer`. New tests cover codec-candidate ordering and
  engine selection; the 100 MB bitrate-budget tests still apply (the WebCodecs
  path reuses `clipVideoBitrate`).

## [1.27.4] — 2026-06-03

### Fixed — crop overlay now matches the actual video box

The crop overlay was sized to a wrapper that could be wider than the
rendered video (the video sat left-aligned in a wider container), so
dragging across the visible frame only reached part-way and "select
whole frame" couldn't cover it — in both 16:9 and 9:16. The overlay is
now measured to the `<video>` element's real on-screen box
(`useVideoStage`, via a ResizeObserver), so a corner-to-corner drag and
"select whole frame" both map to the entire frame regardless of aspect.

## [1.27.3] — 2026-06-03

### Changed — clearer teaser label + "whole frame" crop

- **Relabeled** the bundle teaser action and wizard title from "Make a GIF
  from a video" to **"Make Teaser Video/GIF"**, since it now produces both.
- **Crop tool now has a "select whole frame" button** in both the GIF/Video
  wizard and the Frame Grabber, and clarifies that cropping is optional
  (no crop = the full frame). Makes it easy to keep the entire 16:9 frame.

## [1.27.2] — 2026-06-03

### Changed — exports default to Downloads + `_tease`; bundle wizard attaches instead of downloading

- **Save dialogs default to the OS Downloads folder** (Windows + macOS) via
  `downloadDir()`, instead of an unanchored path.
- **Teaser exports are pre-named `<source>_tease.<ext>`** (GIF + MP4).
- **From a Content bundle, the wizard no longer prompts to download.** It
  attaches its output to the bundle: GIF → **Use as Teaser GIF**, captured
  frame → **Use as Thumbnail**, and the **MP4 → Add to bundle** (saved as a
  bundle video file via the new `save_bundle_clip` command). The Download
  buttons now appear only in the standalone **GIF Studio**.

## [1.27.1] — 2026-06-03

### Fixed — 🎬 MP4 length cap + preview sizing

- **MP4 could exceed the 60s cap.** If playback didn't begin exactly at the
  trim's start (a missed/slow seek), the recorder stopped at the absolute
  end-time and overran. Added a **hard wall-clock backstop** — a recording
  can never run longer than the clamped duration (≤60s) — and made the
  start-seek reliable (begin immediately when already at the start point).
  The trim UI now also warns when the selection exceeds 60s.
- **MP4 preview rendered small at the bottom.** The result `<video>` now
  fills the width (`w-full`, up to 55vh, on a black backing) so the clip is
  easy to see and scrub.

## [1.27.0] — 2026-06-03

### Added — 🎬 MP4 export from the GIF wizard + thumbnail spec guards

- **MP4 export**: the GIF Studio / "Make a GIF from a video" wizard now has
  an **🎬 Export MP4 clip** button beside Generate GIF. It records the
  **same trim + crop + caption** as the GIF, **with audio**, capped at
  **60s / 100 MB**. Recording is **in-app via MediaRecorder** (canvas video
  track + the source's audio track) — no ffmpeg, so it works on Windows
  (WebView2 → real `.mp4`) and macOS (WebKit; falls back to `.webm` if the
  engine can't emit MP4, with a visible note). A bitrate budget keeps the
  file under 100 MB; the wizard warns if a clip still comes out over.
- **Thumbnail spec enforced**: the Content-bundle **Thumbnail Image** slot
  now accepts **JPG/PNG only** (dropped WebP) and **rejects files over
  5 MB** before import (new `file_size` command). The **Frame Grabber**'s
  captured JPEG steps its quality down automatically to stay under 5 MB.

### Notes

- MP4 recording is real-time, so it takes about as long as the clip length.
- `clipVideoBitrate` (pure, unit-tested) computes the size-safe bitrate.

## [1.26.0] — 2026-06-02

### Added — 🖼️ Content-bundle preview assets + 🎞️ GIF Studio

Two related features. A **Content bundle** can now carry two optional
preview assets, and a new in-app **GIF Studio** can make a teaser GIF
without leaving Molly.

- **Preview assets on Content bundles**: optional **Thumbnail Image**
  (jpg/png/webp) and **Teaser GIF** (.gif). Both follow the same pattern
  as the audio description — stored on the `bundles` row (not
  `bundle_files`), hashed at upload, and composed into the published ZIP
  under a `Preview/` folder (`Preview/thumbnail_*`, `Preview/teaser_*`).
  They appear in the Publish review screen, in `info.md` / `Molly.log`,
  and in a new optional `preview` object in `manifest.json` (additive;
  `manifestVersion` stays `1`, so existing SideMolly consumers are
  unaffected). Migration `038_bundle_preview_assets.sql` adds the four
  nullable columns.
- **GIF Studio**: a new sidebar tool (🎞️) and a "✨ Make a GIF from a
  video" button on the Teaser GIF slot. Pick a video (from the bundle or
  from disk), trim start/end, set frame rate, output width, and quality,
  drag to crop, and add a caption — then preview, download, or drop it
  straight into the teaser slot. Encoding is **100% client-side**
  (canvas frame capture + `gifenc`), so it needs no ffmpeg and behaves
  identically on Windows. Clips are capped at 15s / 25fps / 640px wide.
- **Frame Grabber**: a "✨ Grab a frame from a video" button on the
  Thumbnail Image slot. Same source picker + crop + caption as the GIF
  wizard, but scrubs to a single key frame and captures it as a JPEG —
  preview, then use it as the thumbnail or download it. Also client-side.
- New Tauri commands `save_bundle_gif` / `save_bundle_frame` (persist
  encoded bytes / captured frames as a bundle file) and
  `write_bytes_to_path` (backs the Download action, defaulting to
  `~/Downloads/Molly GIF/`).

### Notes

- `gifenc` added as a frontend dependency (tiny, MIT, no transitive deps).
- On macOS, some `.mov`/HEVC sources won't decode in the WebView; the GIF
  Studio surfaces a hint to try an `.mp4`. Windows (WebView2) decodes both.

## [1.25.0] — 2026-06-01

### Added — 📈 Daily follower-count tracking (Social → Growth)

A new **📈 Growth** tab in the Social hub. Sallie logs each platform's
follower count daily; Molly shows the trend and projects where she's
headed. Sibling to the piggy-bank, but with **snapshot** semantics
(one absolute number per persona/platform/day, UPSERT — latest wins),
deliberately *not* the increment model of `social_post_drops`.

- **Overview**: per-platform row with today's entry input (pre-filled
  from the latest known count), latest value, Δ vs the previous logged
  day with ▲/▼ trend arrow, and a hand-rolled SVG **sparkline**. A
  gentle nudge card lists platforms not yet logged today; a ● dot rides
  the Social sidebar item until today's counts are in (per-persona;
  suppressed on ALL).
- **Drill-down**: a hand-rolled SVG **line chart** (history + dashed
  green goal line + dashed forecast tail to the goal, with hover
  tooltips), a **forecast card**, a stats strip (latest, this-week Δ,
  avg/day, goal %), an **editable history** with backfill/edit/delete of
  any past date, and a per-platform **follower goal** editor.
- **Forecast** (`src/lib/followerForecast.ts`, pure + unit-tested):
  least-squares regression over the last 14 logged points → followers/day
  and an ETA to the goal. Sparse-data-safe (skipped days weighted by
  real day-gaps), and always *kind* — a decline never shows a sad sound,
  a red number, or a negative/∞ ETA; far-off goals don't print a date
  decades out.
- **Per-persona** with an **ALL = combined** view: each persona's latest
  snapshot is summed (carry-forward, since personas log on different
  days) with an honest "from N personas' latest entry" footnote and a
  per-persona breakdown on drill-down.
- **Delight**: logging fires the existing Web-Audio chime + a green
  floating "+Δ 🎉" pill + a tiered encouragement; crossing the follower
  goal throws the full milestone fanfare + screen flash. Backfilling a
  past date saves quietly.

Schema: migration `037_social_followers.sql` adds `social_follower_counts`
and a `follower_goal` column on `social_platforms` (mirroring how 035
added `daily_goal`). Rust module `social_followers.rs` is a thin store
(validate + upsert + read); all trend/forecast math lives in the
testable TS lib. The new coin→pig nav fix from 1.24.0 is unaffected.

## [1.24.0] — 2026-06-01

### Fixed — 🐷 Social icon was invisible on Windows

The Social nav item (and the Social header, the "Piggy bank" tab, the
Settings daily-goal label, and two encouragement strings) used the coin
emoji **🪙 (U+1FA99)**, which was added in Unicode 14.0. Windows' default
emoji font (Segoe UI Emoji) only ships glyphs through Unicode 13.0, so the
coin rendered as an invisible/tofu box on Windows — it looked fine on macOS
because Apple Color Emoji has it. No amount of cache-clearing fixes a
missing glyph. Swapped all seven coin uses to **🐷 pig face** (Unicode 6.0),
which is on-theme for the piggy-bank motif and renders on every platform.

### Fixed — 📌 Subreddit rotation now actually resets

`rotation` was a frozen flag: marking a sub posted flipped it to "Resting"
and **nothing ever moved it back**, so a sub stayed "Resting" forever unless
you hand-edited it. Rotation is now configurable in the Subreddit tracker:

- **Auto (default, 2-day rest):** the badge is derived from the last-posted
  date and walks **Resting → Tomorrow → Ready** as the rest window elapses.
  The rest length is an editable number of days (0–30). At 2 days: posted
  today = Resting, yesterday = Tomorrow, 2+ days ago (or never) = Ready.
- **Manual:** keeps the old hand-set flag and adds a **↺ Reset to Ready**
  button on each resting sub, plus the Rotation dropdown in the editor.

In Auto mode the editor's Rotation field shows a read-only "set by
last-posted date" note. The mode + rest-days preference persists in
`app_settings` (keys `reddit.rotation.mode` / `reddit.rotation.restDays`);
no migration. The derivation rule (`src/lib/rotationRule.ts`) is pure and
unit-tested.

## [1.23.0] — 2026-05-29

### Added — ▶️ YouTube bundle type

A fourth bundle flavor sits alongside Content / Custom / Fan Site. A
**YouTube bundle** collects: **title**, **persona**, a **description**
(text *or* audio — same one-or-the-other rule as Content), **one or
more video clips** (video-only; the picker is locked to video
extensions), a **go-live date** (the existing date popover that
dismisses on click-off), and optional **special instructions**. It's
the Content bundle minus categories, with the file list restricted to
video. Publishing composes the same deterministic two-layer ZIP
(`Video/` + optional `Audio/` for an audio description) and, like
Content, upserts a Clips row with status `Bundled` and mirrors the
bundle-level content tags onto it.

#### Why a new `bundle_kind` column instead of a 4th `bundle_type` value

`bundles.bundle_type` carries a SQL `CHECK (bundle_type IN
('content','custom','fansite'))`. SQLite can't alter a CHECK without
rebuilding the table — and `bundles` is the parent of **six**
`ON DELETE CASCADE` children (`bundle_fan_days`, `bundle_files`,
`bundle_categories`, `bundle_tag_links`, `bundle_postings`,
`return_file_imports`). Inside a `tauri-plugin-sql` migration
`foreign_keys` is forced ON (sqlx default — verified in the crate
source) and the script runs in a transaction where `PRAGMA
foreign_keys`, `legacy_alter_table` and `defer_foreign_keys` are all
no-ops (verified empirically against a throwaway DB). So `DROP TABLE
bundles` would cascade-delete every child row, and a full-cluster
rebuild on Sallie's live DB is unacceptably risky.

Migration `036_youtube_bundle.sql` instead adds an **unconstrained**
discriminator column via a plain, never-cascading `ALTER TABLE ... ADD
COLUMN bundle_kind TEXT` (the same safe move 034 used) and backfills it
from `bundle_type`. `bundle_kind` is now the authoritative type the app
reads — Rust selects `COALESCE(bundle_kind, bundle_type) AS
bundle_type`, so the frontend is unaware of the dual column. YouTube
rows store `bundle_type='content'` (keeps the legacy CHECK satisfied) +
`bundle_kind='youtube'`. This also permanently escapes the CHECK trap:
any future bundle type is now a zero-risk migration.

### Tests

- Rust: `youtube_create_stores_content_storage_type_but_reads_back_as_youtube`
  (storage columns + COALESCE read + list view), plus YouTube validation
  cases (passes with video+description, requires a video, rejects
  non-video files, requires a description).
- Frontend: `validateYouTubeFiles` + `validateYouTubeBundle` describe
  blocks in `bundleValidation.test.ts`.
- `migration_smoke` + the bundles-test `fresh_db()` both apply migration
  036.

## [1.22.0] — 2026-05-29

### Added

**Editable per-platform daily goal in Settings → Platforms.** The
`social_platforms.daily_goal` column has driven the piggy bank since
1.21.0 (coin slots, `count/goal`, the ✓ DONE state, and both streak
calculations all key off it), but the platform editor never exposed
it — every new platform was silently pinned to a goal of `1` and the
only way to change it was direct SQL. Added a **Daily goal** number
field to the add/edit form and a `🪙 N/day` badge to each platform
row so the current goal is visible at a glance.

The field allows `0`, which is the documented "paused/retired" state:
`pure_overall_streak` already drops goal-0 platforms
(`social_drops.rs:305`) and `pure_platform_streak` early-returns for
them (`:359`), so a paused platform is skipped by the streak instead
of breaking it. Rows with a `0` goal show `⏸️ paused` instead of the
coin badge.

No schema or Rust changes — `createPlatform` / `updatePlatform`
already round-tripped `daily_goal`; this only wires up the missing UI.

## [1.21.1] — 2026-05-29

### Docs

Rewrote the **🪙 Social** section of `USER_MANUAL.md` in the 200% cute
voice the rest of the manual is written in (the 1.21.0 version was
technically correct but read like a spec sheet, which doesn't match
the cozy-coffee-chat tone of the rest of the manual). Also re-cuted
the **🔗 URL link** paragraph under Creating a Custom Bundle to call
out the five-step "busy mom morning" flow more warmly.

No code changes — pure doc release so Sallie's in-app manual matches
the rest of her book.

Added a release-process rule to top-level `CLAUDE.md`: USER_MANUAL.md
(and any Sallie-facing doc) must be updated in 200%-cute voice *before*
every release commit; a stale or textbook-voice manual is a release
blocker. Dev-facing docs (README, CHANGELOG, HANDOFF, code comments)
keep their normal voice but must also be current at release time.

## [1.21.0] — 2026-05-29

### Added — 🪙 Social hub with daily piggy-bank tracker

The Reddit page has been promoted into a broader **🪙 Social** hub
that tracks daily posting cadence across every platform. Sallie's
problem: posting *consistently* on TikTok / Instagram / Twitter is
ultimately the bottleneck for monetising the foundation she's
already built, and "did I post today?" is hard to feel good about
while wrangling kids in summer.

Solution — a piggy bank. Every time she posts, she taps **+1 Post**
on that platform's row; a coin slot fills, a soft **"ching"** plays,
and the row turns green when the daily goal is hit. Hit every
platform's goal in a day and the **🔥 day-streak** ticks up.

#### Default goals (editable per-platform)

- 🐶 **Reddit** — 10/day
- ✖️ **X** — 3/day
- 📸 **Instagram** — 2/day
- 🎵 **TikTok** — 2/day

#### Tabs inside Social

- **🪙 Piggy bank** — all-platforms-today overview. Coin slots,
  progress bar, +1 button, undo arrow, sound mute toggle. The
  big number at the top is the all-platforms-hit streak.
- **One tab per platform** (X / Instagram / TikTok) — focused
  view with the +1 button, a 5-week history grid color-coded by
  goal-met / partial / 0, per-platform streak, and a goal editor.
- **🔴 Reddit** — the existing Reddit deep tools (Today /
  Subreddits / Post log / Captions / Hours) preserved verbatim
  as a nested tab. Reddit's piggy-bank count auto-merges generic
  +1 drops *and* the existing "mark subreddit posted" rows, so
  Sallie can use whichever tool fits the moment without
  double-counting.

#### Data model

- New SQL migration **035** adds `social_platforms.daily_goal`
  (default 1, backfilled with Sallie's preferred cadence) and
  the append-only `social_post_drops` table (one row per coin
  drop, persona-scoped, indexed by `(persona_code, posted_date)`
  and `(platform_id, posted_date)`).
- Existing `social_promos` and `subreddit_posts` tables are
  untouched. Promos remains the place for "I posted *this
  specific URL/body* on Reddit" detail rows; the piggy bank is
  the lightweight "I did the thing, +1" companion.

#### Streak rules

- **Overall streak**: walks back from today, counts consecutive
  days where *every* non-archived platform met its goal for the
  active persona. First miss breaks the streak. Today only counts
  once it's complete.
- **Per-platform streak**: same idea, but only one platform.
- Platforms with `daily_goal = 0` are skipped — set a goal to 0
  to retire a platform from the streak math without archiving it.

#### Persona scoping

Matches the rest of Molly. Each persona (Curves / Princess) has
its own count and its own streak per platform. The **ALL**
switcher disables the +1 buttons (with an explanatory banner) so
Sallie doesn't accidentally drop a coin against the wrong
persona — pick one, tap, done.

#### Sound

Tiny Web Audio API tones (no external asset). Two flavours: a
single sparkle for every coin, an ascending major arpeggio when
a daily goal flips from missed to met. Muteable per-device via
the 🔔/🔇 toggle on the piggy-bank header; preference persists
in localStorage.

#### Tests

- **Rust** — 10 new tests in `social_drops` covering: zero-count
  initial state, just-hit threshold semantics, persona isolation,
  Reddit's subreddit_posts merge, undo only touching generic drops
  (never subreddit_posts), overall-streak break-on-miss, per-
  platform streak independence, history ordering, goal validation,
  bad-date rejection.

## [1.20.2] — 2026-05-29

### Fixed — 🔗 URL-link customs now skip recipient + price too

Follow-up to 1.20.1. When Sallie picks **🔗 URL link** for delivery,
the form is "pick the option and you're done" — Robert fills in the
URL *and* the recipient *and* the price when he records the return
file. So the Custom Bundle form now hides the Recipient and Price
fields entirely while URL link is selected, and validation skips
both checks. Site-kind submissions are unchanged.

In the publish review, the Delivery section collapses the recipient
and price rows into a single "filled in on return" line for URL-kind.

## [1.20.1] — 2026-05-29

### Fixed — 🐛 Custom-bundle submission was blocked when delivery was URL link

Sallie couldn't publish a Custom bundle with **🔗 URL link** as the
delivery method. The form required her to paste a `http(s)://` URL up
front, but the URL is the *work product* — it's the link Robert sends
back via the SideMolly return-file flow once he's posted the bundle.
Validation refused to accept "URL link" without a URL string, blocking
publish.

**New behaviour** — the **Delivery method** field (renamed from
"Delivery platform") is now just a choice:

- **🌐 Site** → pick a site from Settings → Sites (for the bundle's
  persona). Site id required; behaves exactly as before.
- **🔗 URL link** → click and you're done. No URL input. A pink
  helper note replaces the old text field: *"Robert will fill in the
  URL on return. Nothing else to enter here."* The URL itself lands
  on the bundle row when Sallie imports the SideMolly return file.

Validation rule, both client + server (`validate_custom_delivery`):

- `delivery_kind` must be set (Site or URL link).
- If `'site'` → `delivery_site_id` required.
- If `'url'` → no further input required.
- Removed the http(s) URL-format check (URL is no longer collected here).
- Recipient + price rules unchanged.

Pre-publish review row was also tweaked: URL-kind deliveries now read
"🔗 URL link *(filled in on return)*" instead of the misleading "(no URL)".

### Fixed — 📅 Go-live date popover wouldn't dismiss after picking a date

WKWebView's native date popover ignored the synchronous `blur()` call
that was supposed to dismiss it after Sallie picked a date — the
controlled-value React onChange + async DB commit kept the input
focused, so the popover hung around obscuring the rest of the Custom
Bundle form. Deferred the dismiss to the next animation frame (plus a
50 ms belt-and-braces follow-up) so the popover closes immediately
after Sallie picks a date.

### Changed

- `bundle.delivery_url` is now optional even for URL-kind deliveries.
  Existing rows where Sallie *had* pasted a URL under the old flow
  continue to render fine in the publish review; no migration needed.

## [1.20.0] — 2026-05-27

### Added — 📥 Import the return file from SideMolly

Closes the Molly ↔ SideMolly round-trip. After Robert post-produces a
published bundle and SideMolly composes a `<UID>-post.zip` "return file"
at `~/Downloads/Molly post-bundles/`, Sallie can pull that file back
into Molly with a single click on the Bundles page.

#### Flow

A new **📥 Import Return File** button on the Bundles page opens a
side-panel wizard. On open, Molly scans `~/Downloads/Molly post-bundles/`
and lists every `*-post.zip` it finds (newest first), annotated with
the bundle UID, type, compose timestamp, file size, and whether it's
already been imported. A **📂 Pick from disk…** escape hatch covers
files received via other channels.

On import (transactional):

- For each posting target SideMolly recorded, a row lands in the new
  `bundle_postings` table — target name, state (posted/scheduled/
  pending/skipped), posted-at, posted URL, body override, notes,
  optional fansite day. Upserted on `(bundle_uid, target_id,
  fansite_day)` so re-importing a corrected return file merges rather
  than duplicates.
- For **Content** and **Custom** bundles, each `filesUsed` entry is
  resolved against `bundle_files.relpath`, the original filename's
  stem is matched against `clips.id` / `clips.external_clip_id` /
  `clips.title` (case-insensitive), and the writeback lands in
  `bundle_posting_files` with the matched `clip_id` (or NULL if no
  match). Matched + posted targets also append a row to
  `social_promos` when a matching `social_platforms` row exists, so
  the per-clip posting audit-trail stays consistent.
- For **FanSite** bundles, files are recorded but `clip_id` is always
  NULL (FanSite days aren't clips). Postings are logged for review
  but never written to the Clips list.
- The bundle row is stamped with `completed_at = datetime('now')` and
  `delete_after = datetime('now', '+3 days')` (skipped when the bundle
  is already purged). A green **✓ Imported · cleanup `MM-DD`** badge
  appears on the row in the Bundles list.
- A one-line entry lands in `mollys_log` ("Imported return file for
  bundle <UID> · M/N targets posted · X/Y files linked to clips ·
  cleanup `YYYY-MM-DD`") so the import is visible in Molly's Log.
- The source ZIP's SHA-256 is recorded in the new `return_file_imports`
  table; re-importing the same bytes short-circuits with a
  `wasDuplicate=true` result modal and zero DB writes.

The result modal surfaces every target (name, state pill, posted URL,
fansite day, body override, per-target notes), a per-file clip-match
summary ("5 of 5 matched"), and the cleanup date.

#### Auto-purge integration

`pure_auto_purge` (called once per day at launch) now picks up bundles
whose `delete_after` has passed in addition to the existing 60-day
published-threshold rule. The `delete_after` rule fires even when the
generic threshold is disabled (`purge_threshold_days = 0`), so closing
out a bundle via return-file import always honors the 3-day cleanup
regardless of the global retention setting.

#### Backend

- New migration `034_return_file_import.sql`:
  - Adds `completed_at` + `delete_after` to `bundles`.
  - New tables: `bundle_postings`, `bundle_posting_files`,
    `return_file_imports`.
- New module `return_file.rs` exposing four Tauri commands:
  `list_return_file_candidates`, `import_return_file`,
  `get_bundle_postings`, `reveal_post_bundles_dir`.
- The `Report` / `ReportTarget` Rust structs mirror SideMolly's
  `post_bundle.rs` exactly so a small schema bump there is a one-line
  update here.
- Outer + inner ZIP layout handles the new SideMolly v0.16 wrapping
  directories (`<UID>-post/` and `<UID>-post-inner/`) plus the legacy
  bare-entry shape.

#### Frontend

- New `ImportReturnFileWizard.tsx` with picking → importing → done →
  error stages (mirrors `PublishWizard.tsx`).
- `BundleSummary` TS type extended with `completedAt` + `deleteAfter`.
- Bundles list row shows a `✓ Imported · cleanup MM-DD` badge when
  imported, or `· already cleaned up` when the source ZIP was already
  purged before import.

### Tests

11 new Rust tests across `return_file::tests`:
- `filename_stem_strips_extension_and_position_prefix`
- `resolve_clip_matches_id_then_external_id_then_title`
- `import_records_posting_and_links_matched_clip`
- `import_unmatched_file_records_null_clip_id`
- `import_is_idempotent_by_source_sha`
- `import_fansite_does_not_write_to_clips`
- `import_rejects_unknown_bundle_uid`
- `import_rejects_type_mismatch`
- `import_on_purged_bundle_skips_delete_after`

`migration_smoke` covers `034`; `camel_case_contract` covers the four
new boundary structs (`ReturnFileCandidate`, `PostingFileOutcome`,
`BundlePostingDto`, `ReturnFileImportResult`).

242/242 passing.

---

## [1.19.0] — 2026-05-26

### Added — 💎 Adhoc-income monthly goals + escalating celebrations

Two-part feature: configurable monthly income targets, plus a much
more expressive celebration system that scales with sale size.

#### Settings → 💎 Goals

New Settings tab with 12 month fields (`<MoneyInput />` each). Stores
per-month adhoc-income goals as integer cents in `app_settings` under
keys `goals.adhocMonthly.01` … `.12`. No migration — rows are created
lazily on first save. Defaults: **$1,000** for Jan–Oct (steady months)
and **$2,000** for Nov–Dec (holiday season). A "↺ Reset to defaults"
button restores the canonical split.

Goals are **global** (one number per month covering all personas
combined) and the goal counts the Adhoc tab's unified total — typed-in
adhocs plus customer sales — matching what
`totalsForPeriod(...).adhocTotal` already returns.

#### Goal progress card on the Adhoc Income tab

Pretty card at the top of the Adhoc Income view shows the current
month's running total in Caveat (e.g. `$842 of $1,000`), a soft-pink
animated progress bar (480ms cubic-bezier on `width` so it visibly
slides forward when new income lands), and inline emoji milestone
markers at 25% 🌸 / 50% 🌷 / 75% 🌟 / 100% 🎉 (markers fade in once
the percent crosses each threshold).

When `actual > goal`, a "🚀 +$420 over goal!" pill appears. Card
auto-hides for any past-month view so historical browsing for tax
prep stays clean.

#### Five-tier celebrations when income is logged

Sale size determines the tier — a $5 tip and a $1,500 custom no
longer feel the same.

| Tier | Amount | Sound | Encouragement bank | Visual |
|---|---|---|---|---|
| 1 | < $10 | soft A5 ting (200ms) | `tiny` (~10 lines, "Every dollar counts! 🌸") | small +$X pill |
| 2 | $10–$49 | classic `playCashRegister()` | `small` (original 30 sayings) | +$X + 1 emoji |
| 3 | $50–$199 | brighter ka-ching (4-partial bell w/ E8 sparkle) | `medium` (14 lines, more enthusiastic) | +$X + 3-emoji burst |
| 4 | $200–$999 | layered double cha-ching (two bells 180ms apart) | `big` (12 lines, big-girl-bag energy) | larger +$X + 6-emoji burst |
| 5 | $1000+ | mega fanfare (drawer + C-major arpeggio cascade + high C8) | `whale` (11 lines, full queen energy) | huge +$X + 10-emoji burst + screen flash |

Encouragement banks restructured from the flat 30-saying constant
into per-tier readonly arrays. Recent-avoidance window (last 8
strings) is shared across all banks so back-to-back saves never
repeat the same line regardless of tier.

#### Milestone fanfare layered on top

When `totalAfter` crosses a monthly goal milestone the current save
didn't start on (25 / 50 / 75 / 100 / 150 / 200%), a separate
fanfare fires ~500ms after the tier sound starts and a dedicated
milestone toast pops ~600ms behind the regular tier toast:

- 25% → C+G perfect-fifth ping + "🌸 25% in! Quarter of the way! 🌸"
- 50% → E→G major-third ascent + "💖 Halfway! Halfway there! 💖"
- 75% → G→B→D rising notes + "🌟 75% there!"
- 100% → full C-major triad with C7 echo + "🎉 GOAL HIT!"
- 150% → "💎 150% there!"
- 200% → double ascending arpeggio + "🚀 DOUBLE goal!!"

When a single huge sale crosses multiple milestones in one shot
(e.g. $0 → $1000 on a $1000 goal), the highest milestone is fired so
the moment matches the magnitude.

#### Files

**New:**
- `src/state/incomeGoals.ts` — load/save/hook for the 12-month map
  (mirrors `state/featureFlags.ts`).
- `src/views/Settings/IncomeGoalsSettings.tsx` — Settings → Goals tab.
- `src/views/Income/GoalProgress.tsx` — progress card.
- `src/lib/celebration.ts` — `celebrateIncome()` orchestrator,
  `tierForAmount`, `milestoneCrossed`.
- `src/lib/floatingNumber.ts` — imperative DOM +$X pill + emoji
  burst + tier-5 screen flash.
- `src/lib/celebration.test.ts` — 9 new cases (tier mapping +
  milestone crossing detection including multi-milestone single
  saves + boundary inclusivity).

**Modified:**
- `src/lib/encouragements.ts` — restructured into 5 tier banks +
  milestone bank; `pickEncouragement(tier)` signature change.
- `src/lib/encouragements.test.ts` — extended to assert per-tier
  variety and shared-window avoidance.
- `src/lib/encouragementToast.ts` — `showEncouragement()` now
  accepts optional explicit text (defaults to the small bank).
- `src/lib/soundFx.ts` — added `playCashRegisterTiny / Medium / Big
  / Mega` and `playMilestoneFanfare(percent)` built on the existing
  `playBellTone` primitive.
- `src/views/Settings/SettingsView.tsx` — registers the new `goals`
  tab between `features` and `sites`.
- `src/views/Income/AdhocIncomeView.tsx` — adds `<GoalProgress />`,
  captures before/after current-month totals around the insert, and
  fires `celebrateIncome(...)` in place of the old single-tier pair.
  Saves into the current calendar month always use today's goal,
  even when the view is filtered to a different month (Sallie
  backfilling May from June still progresses June's goal).
- `src/views/Customers/CustomerSaleEditor.tsx` — same celebration
  swap, calling `loadMonthlyGoals()` inline since the editor doesn't
  live under a goals provider.
- `src/views/Income/SiteIncomeWizard.tsx` — kept on the original
  single-tier celebration (site income isn't in the adhoc-goal
  scope), updated to the new `pickEncouragement('small')` signature.

Tests: **190/190 JS pass** (up from 180), 229/229 Rust pass.

## [1.18.6] — 2026-05-26

### Added — ⏱ Home page timers (2 countdowns + stopwatch) with arrival chimes

The Hi, I'm Molly card had a lot of empty space; it now hosts a row
of three pretty timers under the live clock. All state persists
across app launches.

#### Countdown #1 — 🎂 default "Birthday" / Dec 6

Big handwritten-Caveat day count + the chosen date underneath ("194
days · Dec 6, 2026"). Both the label and the date are editable via
the ✏️ button — change "Birthday" to a friend's name, change the
date to any day, click Save.

Default date picks the next future Dec 6 (rolls to next year if Dec
6 has already passed this year). State persists in `localStorage`
under `molly:timer:countdown1`.

On the arrival day (`remaining === 0`), plays an ascending C6 → E6
→ G6 major-chord arpeggio — the celebratory "birthday chime."
Fires at most once per calendar day per timer (tracked under
`molly:timer:countdown1:lastFired`) so app re-opens later in the
day stay silent.

#### Countdown #2 — 🏠 default "Rent Due" / next 1st of the month

Identical card with a different default. Default date is the 1st of
the *next* calendar month from today; Sallie can pin it to any day.
Plays a different chime on arrival: A5 → E5 perfect-fourth descent
("ding-dong"), heavier than the birthday flourish so the two are
audibly distinct.

#### Stopwatch — ⏱ HH:MM:SS.cc count-up

Monospaced display with centisecond precision. Start / Stop / Reset
buttons. Hundredths-of-a-second updates run via `requestAnimationFrame`
direct to the DOM (no React re-renders 30× a second) and only run
while the timer is active.

State persists across app launches *including the running state* —
if Sallie hits Start and quits Molly, the timer keeps counting in
the background and resumes from the correct elapsed time on next
launch. Internal model is `{ running, startedAt, accumulatedMs }`
so resume is just `accumulatedMs + (now − startedAt)`.

On Stop (only — Start is silent), plays a soft A4+A5 bell pair as a
gentle "session complete" cue. Reset zeroes everything; the button
is disabled while running or already at zero.

#### Files

- `src/views/Home/TimersPanel.tsx` — new component owning all three
  timer cards plus the date math (`daysUntil`, `formatStopwatch`,
  `stopwatchElapsedMs`) and localStorage helpers.
- `src/views/Home/TimersPanel.test.ts` — 11 new vitest cases
  (date math, formatting padding, hour roll-over, negative clamp,
  running-vs-stopped elapsed calculation).
- `src/lib/soundFx.ts` — three new exported chimes
  (`playBirthdayChime`, `playRentDueChime`, `playStopwatchChime`)
  built on a shared `playBellTone` sine-decay primitive.
- `src/views/Home/HomeDashboard.tsx` — drops `<TimersPanel />` in
  under the existing `<PrettyClock />`.

Tests: 180/180 JS pass (up from 169 — the 11 timer tests are the
additions), 229/229 Rust pass.

## [1.18.5] — 2026-05-26

### Added — 💰 Cash-register cha-ching + encouragement toast on money entries

When Sallie logs money, Molly now reacts.

#### Cha-CHING! (every income + expense create)

A synthesized cash-register sound plays whenever a new row is created
in any of these places:

- **Income** — adhoc income create (`AdhocIncomeView`)
- **Income** — per-site monthly upsert with at least one brand-new
  positive entry (`SiteIncomeWizard`)
- **Income** — customer sale create (`CustomerSaleEditor`, per the
  user's explicit ask to cover "those done from customers" too)
- **Expenses** — one-off expense create (`ExpenseListView`)
- **Expenses** — new recurring expense template (`RecurringExpensesView`)

The sound is synthesized live via Web Audio (no bundled audio
asset — keeps Molly offline-first and licensing-clean):

- A low-passed noise burst → the cash drawer thudding open ("cha").
- A band-passed noise transient → the bell hammer striking.
- Three sine partials at E6 / E7 / G#7 with 5ms attack and 600ms
  exponential decay → the unmistakable "ching!" sparkle.

Total duration ~700ms. Fires only on creates — edits are silent so
fixing a typo doesn't trigger a celebration. Bulk imports (sales
report CSV import) also stay silent on purpose. Sound construction
is wrapped in `try/catch` and gracefully no-ops if AudioContext is
unavailable (degraded WebView, vitest/jsdom, etc.) so a missing
ka-ching never breaks the underlying save.

#### Encouragement toast (income only)

Logging income — adhoc, per-site, or customer sale — also pops a
soft-pink floating banner at the top of the viewport with one of 30
encouraging one-liners in the handwritten Caveat font ("Way to go,
girl! 💕", "Cha-ching, queen! 👑", "Sallie season! 🎀", …).

The toast picks a saying biased away from the last 8 picks so Sallie
doesn't see "Money queen!" twice in a row. The full pool of 30 sayings
is exercised across ~200 picks (asserted by test). Animation: 260ms
scale-up entrance from the top, 2.4s hold, 360ms scale-down exit.

Expenses deliberately do NOT trigger the encouragement — spending
money isn't the moment Sallie needs to be cheered on.

#### Files

- `src/lib/soundFx.ts` — lazy AudioContext + `playCashRegister()`.
- `src/lib/encouragements.ts` — saying bank + `pickEncouragement()`
  with recent-avoidance.
- `src/lib/encouragements.test.ts` — 3 new vitest cases (always in
  bank, never repeats within recent window, full coverage at 200
  picks).
- `src/lib/encouragementToast.ts` — imperative DOM toast renderer.
- Wired into all 5 money-create call sites listed above.

Tests: 169/169 JS pass (up from 166 — the 3 encouragement tests are
the additions), 229/229 Rust pass, no migration needed.

## [1.18.4] — 2026-05-26

### Added — 🚩 Feature flags (Settings → Features) with Promos toggle

New **Settings → Features** tab houses on/off toggles for parts of
Molly that not every install needs. The first flag is **Promos**, off
by default — when off, the 📣 Promos entry disappears from the
sidebar entirely and the page is unreachable. Sallie can flip it on
in Settings any time and it comes right back.

Behavior:

- Default is **off** on first launch. Users who flip it on (or off
  again) persist their choice in `app_settings` under the key
  `feature.promosEnabled` (value `'1'` / `'0'`), so the choice
  survives app restarts.
- Toggling off while sitting on the Promos page bounces the user to
  Home — they're never stranded on an invisible page.
- The Promos data itself (`promos` table) is left untouched when the
  flag flips off; nothing is dropped or migrated. Flipping the flag
  on later restores the page with everything intact.
- The `null` render in `App.tsx` covers the single render-cycle gap
  between the redirect effect firing and `view` updating, so the
  hidden page never briefly flashes its contents.

Implementation:

- `src/state/featureFlags.ts` — new module mirroring the pattern in
  `state/uiTheme.ts`. Exports `loadPromosEnabled`, `savePromosEnabled`,
  and the `usePromosEnabled()` hook (which returns `{ enabled,
  setEnabled, loaded }` — `loaded` lets the sidebar skip the
  default-on flicker on the first frame).
- `src/views/Settings/FeaturesSettings.tsx` — new tab pane with a
  pretty-toggle row component. Toggle is disabled while the flag is
  still loading to prevent racing the initial fetch.
- `src/views/Settings/SettingsView.tsx` — registers the new
  `features` tab between Appearance and Sites.
- `src/components/Sidebar.tsx` — accepts a `promosEnabled` prop and
  filters the `promos` nav entry out when false.
- `src/App.tsx` — wires `usePromosEnabled()`, passes the value to the
  Sidebar, gates the `promos` switch case, and bounces stranded users
  to Home via a `useEffect`.

All 166 JS tests + 229 Rust tests continue to pass; no migration
needed since `app_settings` already exists and the flag row is
created lazily on first save.

## [1.18.3] — 2026-05-26

### Added — 🏠 Home page reorder + pretty live clock

Two changes to the Home dashboard, both motivated by Sallie's daily use:
she wants the cards she cares about most at the top, and she wants the
time-of-day visible without having to glance at the menu bar.

#### Drag-to-reorder dashboard cards

Five Home sections are now reorderable by drag-and-drop:

1. ⏰ Overdue / Due today reminders
2. Stats row (This month / YTD / All time)
3. Clips per persona
4. Reuse detection
5. Recent imports

The Saying banner and the **Hi, I'm Molly** welcome card stay locked at
the top (the welcome card now owns the clock — see below), and the
error card stays at the bottom when present. Each reorderable card
shows a small `⋮⋮` drag affordance in the top-right; drop targets
outline in the persona accent color while a card is being dragged.

Order is persisted to `localStorage` under `molly:home:order` so it
survives app launches. Saved orders are validated on load — unknown
section IDs are dropped, and any sections newly added in future
releases are appended to the bottom so Sallie's customizations never
hide a brand-new section completely.

Reorderable sections that have nothing to show right now (e.g. no
overdue items, no imports yet) render an invisible placeholder so the
slot's position is preserved — when content arrives, it appears in
the chosen position, not appended at the bottom.

#### Pretty live clock in the welcome card

The **Hi, I'm Molly** card now hosts a soft-pink gradient panel with:

- The current time in the Caveat handwritten font at 3.25rem, in the
  persona accent color, lowercased am/pm (`3:42 pm`).
- The day of the week in Comfortaa display font (`Tuesday`).
- The full date with an ordinal day (`May 26th, 2026`).

The clock re-renders once per minute — the first tick is aligned to
the next `:00` boundary so the visible minute flips exactly on time
instead of drifting up to a minute behind. Seconds are intentionally
not shown (avoids a re-render every second on an otherwise-static
dashboard).

Touched files:

- `src/views/Home/HomeDashboard.tsx` — full refactor: each section
  extracted into its own component, sections rendered via the
  persisted `order` array, drag-and-drop wired in the same pattern as
  `TodaySection.tsx` (Reddit tab), new `WelcomeCard` and
  `PrettyClock` components.

All 166 JS tests + 229 Rust tests continue to pass.

## [1.18.2] — 2026-05-26

### Changed — 🎁 Bundle ZIP filenames include the title

Published bundles now write to `~/Downloads/Molly bundles/` as
`<UID> <title>.zip` (e.g. `2026-05-26-0001 May Custom for @username.zip`)
instead of just `<UID>.zip`. The change applies to all three bundle
types — Content, Custom, and FanSite — because they share the same
publish path (`bundle_zip::compose_bundle`).

Motivation: Sallie has trouble recognizing bundles in Finder when
they're named only by date+counter. The title was already stored in
the DB and rendered in the Bundle list inside the app; this just
surfaces it in the filename too so the on-disk view matches.

Details:

- New helper `bundle_zip::bundle_archive_filename(uid, title)` builds
  the filename. Sanitization replaces filesystem-forbidden characters
  (`/ \ : * ? " < > |` and control chars) with spaces, collapses
  whitespace runs, and strips leading/trailing dots. Titles are capped
  at 100 chars so the total filename stays well under APFS's 255-byte
  limit and remains readable.
- Empty / whitespace-only / fully-sanitized-to-empty titles fall back
  to the old `<UID>.zip` form so an untitled draft still publishes
  cleanly.
- Existing bundles already on disk under the old name are left alone;
  they keep working because the DB row's `bundle_path` is the source
  of truth for "Open ZIP", unpublish, and auto-purge.
- `list_bundle_archives` was updated to extract the UID from either
  filename form by validating the leading 15 chars against the
  `YYYY-MM-DD-NNNN` shape via a new `is_bundle_uid` helper. This
  preserves the existing guard that ignores unrelated zips a user
  may have dropped into the bundles folder.

Test coverage (8 new tests, 437/437 total passing):
- `bundle_archive_filename_*` × 6: title appended, empty-title
  fallback, forbidden-char sanitization, length cap, leading/trailing
  dot stripping, all-forbidden-chars fallback.
- `is_bundle_uid_*` × 2: accepts the valid shape, rejects wrong-length
  / wrong-separator / non-digit / unrelated-filename inputs.

## [1.18.1] — 2026-05-24

### Added — 🔴 Reddit tab UX polish

Two small but daily-touch enhancements on the Reddit tab.

#### ✅ Today → drag-and-drop reordering

Open to-do items can be reordered freely with drag-and-drop. Tasks
keep a stable `sort_order` column (already in 031_daily_tasks.sql);
the new `reorder_daily_tasks(orderedIds)` Tauri command renumbers
them 1..N inside a transaction so failed reorders roll back cleanly
and new INSERTs keep landing at the bottom (`MAX(sort_order)+1`).

- Tiny ⋮⋮ drag affordance on the left of each task; existing
  per-task buttons (`✓ Done`, `✕`) are marked `draggable={false}`
  so a click on either still hits the right handler.
- Drop target outlines in the persona accent color; drag source
  fades to 45% opacity.
- Optimistic local reorder for snappy feel; refresh re-fetches from
  Rust to confirm; error rolls back via refresh.
- Completed tasks stay in their "Completed today" section — they
  always sort to the bottom by `done_at IS NOT NULL` in the list
  query, so only the open list is draggable (intended).

Reuses the `reorderBeforeTarget` helper already used by
`OrderedFileList` for bundle file reordering — same pattern, no new
drag-drop library.

#### 📌 Subreddits → inline-edit Category

The Category cell in the subreddit tracker table is now a
click-to-edit pill backed by a native `<select>`. Pick any tag from
the existing **Content tags** taxonomy (or "— no category —" to
clear). Saves immediately via `update_subreddit` with the rest of the
row's fields preserved.

- Chip background is the tag color (or muted neutral when unset);
  caret tint adapts to the chip foreground via a tiny inline-SVG so
  it reads on both dark and pastel chips.
- Optimistic local update so the chip re-colors instantly; refresh
  re-fetches from Rust to confirm.
- Click on the chip is `stopPropagation`'d so it doesn't bubble into
  any future row-click handler.
- Native `<select>` chosen over a custom popup for accessibility +
  zero-dependency keyboard support (Sallie can tab through cells +
  use arrow keys to pick).

#### Tests

**221 Rust** (+2) + **166 frontend** = **387 total**:

- `daily_tasks::tests::reorder_renumbers_and_persists` — three tasks
  shuffled, sort_order densely renumbered 1..3, a fourth INSERT lands
  at 4 (so the `MAX+1` invariant for new tasks survives).
- `daily_tasks::tests::reorder_rejects_unknown_id_and_rolls_back` —
  mixing a real id with a fake one errors with `NotFound` AND leaves
  the real row's sort_order untouched (transaction rolled back).

The frontend changes are pure UI wiring — no new test surface
worth adding (drag events on jsdom are notoriously flaky and the
underlying `reorderBeforeTarget` helper already has coverage in
`reorderHelpers.test.ts`).

## [1.18.0] — 2026-05-24

### Added — Phase 2 (SideMolly contract): `manifest.json` in bundle output

Every published bundle ZIP now carries a structured `manifest.json`
alongside `hashes.json` at the top level of the outer ZIP. SideMolly's
ingest pipeline (which already supports both paths — see
`SideMolly/src-tauri/src/manifest.rs`) prefers this contract over its
prior `Molly.log` line-based fallback parse.

**Outer ZIP layout (v1.18.0+).**

```
<UID>.zip                              (outer)
├── <UID>-inner.zip                    (unchanged — same SHA-256 as v1.17.x)
├── manifest.json                      NEW
└── hashes.json                        (unchanged schema; sits at index 2 not 1 now)
```

**`manifest.json` schema** (`manifestVersion: 1`):

```json
{
  "manifestVersion": 1,
  "bundleUid": "2026-05-22-0001",
  "bundleType": "content|custom|fansite",
  "personaCode": "CoC",
  "title": "...",
  "contentDate": "2026-05-22",
  "goLiveDate": "2026-05-29",
  "specialInstructions": "...",
  "description": { "mode": "text|audio|none", "text": "...", "audioPath": "Audio/..." },
  "categories": ["..."],
  "tags": ["..."],
  "delivery": { "kind": "site|url|null", "siteName": "...", "url": "...", "recipient": "...", "priceCents": 4900, "handledInPlatform": false },
  "fanSite": { "year": 2026, "month": 6, "days": [{ "day": 1, "message": "...", "tags": ["..."], "files": [{"path": "FanSite/01_01_a.jpg", "position": 1}] }] },
  "files": [{ "kind": "video|image|audio", "originalName": "...", "inZipPath": "Video/00001_...mp4", "position": 1, "fansiteDayOfMonth": null, "sha256": "..." }],
  "publishedAt": "2026-05-22T03:00:00Z"
}
```

**Determinism.** Composed from the immutable `BundleSnapshot` via
`serde_json::to_vec_pretty` (insertion-order preserving) and written
with `zip::DateTime::default()` (MS-DOS epoch). Same snapshot composes
byte-identical manifest.json across runs — locked in by
`manifest_json_is_deterministic` test.

**Backward compatibility.** The inner ZIP is unchanged (same files,
same order, same SHA-256). The outer SHA-256 *does* change (one more
entry); this is fine because consumers find entries by name, not
index. Older SideMolly versions that only parse `Molly.log` still work
— manifest.json is an additive sibling, not a replacement.

### Tests

5 new tests in `bundle_zip::tests` (+ 2 updated for the new outer
layout): `manifest_json_is_deterministic`,
`manifest_json_round_trips_{content,custom,fansite}_bundle`,
`manifest_json_audio_description_mode`.

**219 Rust + 166 frontend = 385 tests passing** (was 380 in v1.17.1).

### Implementation

- New `render_manifest_json(snapshot: &BundleSnapshot) -> Vec<u8>` in
  `src-tauri/src/bundle_zip.rs`, paired with a helper
  `in_zip_path_for(snapshot, file)` that constructs the same paths as
  the inner-zip media loop (deliberately not factored back into
  compose_bundle to keep the existing byte stream identical).
- `compose_bundle` writes the manifest between `<UID>-inner.zip` and
  `hashes.json` in the outer ZIP.

## [1.17.1] — 2026-05-23

### Fixed — 🚨 Migration hash crash on launch

v1.17.0 edited `006_schedules.sql` in place to drop the seeded
'CoC content release' + 'PoA content release' rows. tauri-plugin-sql
SHA-hashes every migration on first apply and refuses to open the DB
if the bytes ever change later, so existing installs hit
`migration 6 was previously applied but has been modified` and
couldn't launch.

Fix: `006_schedules.sql` is now byte-exact restored to its original
v1.0 content (re-includes the two INSERT rows). Migration 032 still
runs and deletes the same two rows — so the end-state is identical:
fresh installs seed 5 → 032 deletes 2 → 3 left; existing installs
simply have 032 run for the first time (it couldn't before because
006's hash check was blocking it) → 2 rows deleted → same 3 left.

Lesson re-pinned in the head: **never edit a migration's bytes after
it ships**. The right shape is always "new migration that fixes the
data" — which is what 032 already was.

## [1.17.0] — 2026-05-23

### Added — 🔴 Reddit ops hub + 🎨 Dark mode (Phase 15)

A new sidebar tab and a UI-theme toggle, plus the removal of two
unwanted default reminders.

#### 🔴 Reddit (new sidebar tab)

Five sections under a single internal section bar, all persona-scoped
via the existing Molly persona switcher:

- **✅ Today** — daily to-do list with 11 quick-add chips (Reddit posts,
  YouTube, content, admin), 5 color-coded category pills, hero stats
  (to-do / done / %), per-task complete + undo + delete. Tasks belong
  to a `for_date` so previous-day entries stay as history but don't
  pollute today's view (frontend filters by today's local date).
- **📌 Subreddit tracker** — table with star, name, category (pulled
  from the existing **content tags** taxonomy), verified ✓/✗, karma
  req, rotation (Ready / Tomorrow / Resting), last-posted date, notes.
  Sort by starred + A-Z / category / last-posted / rotation. Filter by
  search, category, rotation. "Mark posted today" flips rotation to
  Resting + stamps last-posted + creates a Post log entry.
- **📅 Post log** — chronological log bucketed by Future / Tomorrow /
  Today / Yesterday / Earlier. Logging a post accepts any date
  (yesterday, today, scheduled). Auto-completes subreddit name from
  the tracker; future entries render with dashed borders + italic.
- **💬 Captions** — light-touch caption stash with copy-to-clipboard,
  optional content-tag category, search + filter. No "mark used"
  flow — Sallie said "doesn't have to be that serious."
- **⏱ Hours** — big clock with Log In / Log Out, live HH:MM:SS counter
  while running, today / week / month rollups, session log,
  ✨ **Reward milestones** with progress bars (configurable in
  Settings → Rewards, global scope, multiple goals).

Five new HTML reference categories seeded into `content_tags_def`:
bbw, hairy, fetish, redhead, general curvy (all `is_builtin=1`).
33 default subreddits seeded for CoC (curated from the HTML reference,
"Curse of Curves" maps directly). PoA + Sa start empty.

#### 🗓️ 3rd Calendar overlay: 🔴 Reddit posts

Per-persona toggle (persisted to localStorage same pattern as the
FanSite + Clip overlays) that shows scheduled + logged subreddit posts
on their `posted_date`. Past posts render solid, future posts render
dashed + italic. Up to 3 chips per day with a `+N more` collapse.

#### 🎨 Dark mode (Settings → Appearance)

Three-way toggle: **Light** (default) / **Dark** / **System**.
- Stored in `app_settings.ui.theme` (seeded via migration 033).
- Persona accent colors stay the same — only page / cards / inputs
  flip darker. Tailwind config gains `darkMode: 'class'`; theme
  class applied to `<html>` by `useUiTheme()` on App mount.
- **System** mode subscribes to the OS `prefers-color-scheme` media
  query and re-applies live when the OS flips.
- New CSS surface tokens (`--surface-card`, `--surface-page`,
  `--surface-input`, `--surface-text`, `--surface-border`) replace
  hard-coded white backgrounds in `.pretty-card` and `.pretty-input`.

#### 🧹 Removed defaults

Migrations **032** drops the seeded weekly schedules **'CoC content
release'** and **'PoA content release'** per Sallie's ask. New installs
skip the seed (006_schedules.sql updated); existing DBs purge them by
name+persona (safe to run twice). Renamed copies survive.

#### Schema

- Migration **029_subreddits.sql** — content_tags_def +5 new builtins,
  subreddits / subreddit_posts / captions tables, 33 CoC sub seed.
- Migration **030_hours.sql** — clock_sessions (one-at-a-time
  semantics: `duration_ms IS NULL` ⇒ open) + reward_milestones (global).
- Migration **031_daily_tasks.sql** — daily_tasks keyed by for_date +
  persona.
- Migration **032_drop_content_release_defaults.sql** — DELETE by
  name+persona.
- Migration **033_ui_theme.sql** — `app_settings ('ui.theme', 'light')`.

#### Tauri command surface (35 new)

- Reddit (14): `list_subreddits` / `create_subreddit` / `update_subreddit`
  / `set_subreddit_starred` / `set_subreddit_verified` / `delete_subreddit`
  / `mark_subreddit_posted` / `list_subreddit_posts_in_range` /
  `create_subreddit_post` / `delete_subreddit_post` / `list_captions` /
  `create_caption` / `update_caption` / `delete_caption`.
- Hours (9): `hours_start_session` / `hours_stop_session` /
  `hours_list_sessions` / `hours_delete_session` / `hours_totals` /
  `list_reward_milestones` / `create_reward_milestone` /
  `update_reward_milestone` / `delete_reward_milestone`.
- Daily tasks (5): `list_daily_tasks` / `create_daily_task` /
  `complete_daily_task` / `undo_daily_task` / `delete_daily_task`.

All new boundary structs pinned by `camel_case_contract`.

#### Tests

**214 Rust** (+33) + **156 frontend** = **370 total**:
- `reddit::tests` (10): seed loads 33 CoC, list filters by persona,
  `r/` prefix stripped on create, blank-name / bad-rotation rejected,
  unique-per-persona but cross-persona dup OK, star+verify toggle,
  `mark_posted` flips rotation + creates post log row, bad date /
  missing sub errors, future + past dates supported, deleting a sub
  preserves post history via FK ON DELETE SET NULL, caption CRUD with
  text-trim + empty rejection.
- `hours::tests` (8): start/stop round-trip, stop-without-open errors,
  start-when-open auto-closes previous, delete session, totals window
  math (today / week / month / all-time), open-session running portion
  included in totals, milestone CRUD + validation, list ordered by
  ascending hours.
- `daily_tasks::tests` (5): create/list round-trip, previous-day tasks
  filtered out of today, complete/undo/delete cycle, input validation
  (empty text / bad date / bad category), unfinished-first ordering.
- `camel_case_contract` (+7): `Subreddit`, `SubredditPost`, `Caption`,
  `ClockSession`, `HoursTotals`, `RewardMilestone`, `DailyTask`.
- `migration_smoke` anchors `subreddits` / `subreddit_posts` /
  `captions` / `clock_sessions` / `reward_milestones` / `daily_tasks`.

## [1.16.1] — 2026-05-23

### Added — 🏷️ Content tags in published bundle ZIP

The content tags collected in each bundle workflow are now written to
the bundle's downstream artifacts so Robert sees them when he opens the
ZIP without needing the Molly DB:

- **info.md** — Content + Custom bundles gain a `## Content tags`
  section with a comma-joined list of tag names. FanSite bundles get
  a `**Tags:** …` line under each day block, only when that day has
  tags attached.
- **Molly.log** (build log) — adds a `Content tags (N):` block to the
  inputs section for Content + Custom; per-day tags appear as a
  `    tags: …` line under each day entry.

Tag names are resolved at snapshot-build time from `content_tags_def`
sorted by `sort_order, name COLLATE NOCASE` (same order as the picker
UI), inside the publish transaction. Empty tag sets render either
`_(none)_` (info.md) or `(none)` (Molly.log).

`BundleSnapshot` gains `tags: Vec<String>` (bundle-level) and
`FanDay.tag_names: Vec<String>` (per-day). `build_snapshot` reads from
`bundle_tag_links` JOIN `content_tags_def` — two prepared statements,
one for bundle-level (`fan_day_id IS NULL`) and one for FanSite per-day
(`fan_day_id IS NOT NULL`), bucketed by `fan_day_id` for cheap per-day
lookup in the FanDay loop.

#### Tests

**183 Rust** (+2):
- `info_md_includes_all_fields`: extended to assert the `## Content tags`
  heading + comma-joined names appear for Content bundles.
- `molly_log_includes_bundle_level_tags`: new — `Content tags (N):`
  block lists each tag with its position.
- `info_md_renders_per_day_tags_for_fansite`: new — `**Tags:** …` lines
  appear only on days that have tags; days with no tags emit no Tags
  line at all (counted `matches("**Tags:**")` to pin the negative case).

## [1.16.0] — 2026-05-23

### Changed — 🏷️ Per-day FanSite tags + Clip tags + Calendar overlays

Three follow-on enhancements to the Content tags system shipped in v1.15.0.

#### Per-day tags for FanSite bundles

FanSite bundles previously had a single bundle-wide tag set, but a 30-day
batch wants per-day themes ("flats Mon, heels Wed"). v1.16.0 splits the
join:

- Migration **027** recreates `bundle_tag_links` with a nullable
  `fan_day_id` column. `NULL` keeps the old Content/Custom semantics;
  not-`NULL` attaches the tag to one FanSite day.
- The FanSite bundle form no longer shows the bundle-level picker — each
  day's `FanDayModal` carries its own `ContentTagPicker` instead.
- Existing bundle-level tags on Content/Custom bundles are untouched
  (the migration copies them forward as `fan_day_id=NULL` rows).
- Partial unique indexes enforce one (bundle, tag) row at bundle level
  and one (day, tag) row at day level without forbidding both shapes
  on the same bundle.

#### Tags on clips

- Migration **028** adds `clip_tag_links` joining the regular `clips`
  table to the same `content_tags_def` taxonomy (the read-only
  `c4s_clips` snapshot is deliberately excluded).
- `ClipDetail` modal (opened from both the Clips list and the Calendar
  clip cells) gains a `ContentTagPicker`. Edits save immediately —
  no separate "save tags" button.
- `ClipsListView` rows show the selected tags as colored pills under
  the title so Sallie can scan tag coverage without opening each clip.
- Publishing a **Content bundle** now mirrors its bundle-level tags onto
  the resulting clip row (FanSite per-day tags are NOT copied — they
  belong to days, not clips). Idempotent: re-publish re-syncs.

#### Calendar overlays (per persona, per kind)

Two new checkboxes on the Calendar:

- **🏷️ FanSite day tags** — colored pills (matching the tag's color)
  for any FanSite day whose resolved date falls in the visible month.
- **🎬 Clip tags** — dashed-outline pills (so they don't visually
  collide with the solid FanSite ones) for any clip whose go-live
  date falls in the visible month.

Each toggle is persisted to `localStorage` keyed by
`(active persona, overlay kind)` — Sallie can have FanSite tags on for
CoC and Clip tags only for PoA. Hovering a chip surfaces the persona +
tag name; both queries respect the active persona filter (or return
everything when ALL is selected).

#### Tauri command surface (new)

- Tags: `list_fan_day_tags`, `set_fan_day_tags`,
  `list_fansite_day_tags_in_range`, `list_clip_tags`, `set_clip_tags`,
  `list_clip_tags_in_range`.
- `set_bundle_tags` semantics changed: now scoped to
  `fan_day_id IS NULL` so it can't wipe out per-day links on a FanSite
  bundle.
- `BundleFanDay.tagIds` added to the boundary struct (camelCase contract
  test updated).

#### Tests

**181 Rust (+10) + 156 frontend** = **337 total**:

- `content_tags::tests` (10 new):
  - `bundle_level_set_does_not_touch_day_level`
  - `day_level_set_replaces_only_that_day`
  - `deleting_fan_day_cascades_day_tags`
  - `range_query_resolves_dates_and_filters_by_persona` (FanSite)
  - `set_clip_tags_round_trips`
  - `deleting_clip_cascades_clip_tags`
  - `mirror_bundle_tags_to_clip_copies_only_bundle_level`
  - `clip_range_query_resolves_dates_and_filters_by_persona`
- `camel_case_contract` (+2): `FanSiteDayTag`, `ClipTagInDate`.
- `migration_smoke`: anchors `clip_tag_links`.

#### Known limitations

- Calendar overlay queries assume Rust's
  `printf('%04d-%02d-%02d', year, month, day)` matches the JS-side
  ISO date keys. A short test in `range_query_resolves_dates_and_filters_by_persona` pins this.
- Clip-tag mirroring on bundle publish happens inside the same
  transaction as the clip upsert, so a content-tag-DB failure rolls
  back the whole publish. Intentional — if the mirror would fail
  silently, future reports would lie.

## [1.15.1] — 2026-05-23

### Changed — 🌼 Licensed Paper Daisy font

Replaced the personal-use demo version of Paper Daisy that shipped in
v1.14.0 with the full licensed release (v1.2, Dec 2017 — purchased
from maja.mint / Jana Matthaeus in May 2026). Full glyph set, same
font-family name so existing notes pick it up automatically. License
note updated in `src/assets/fonts/LICENSES.md`.

## [1.15.0] — 2026-05-23

### Added — 🎁 Bundle previews · 🎉 Holidays · 🏷️ Content tags (Phase 14)

A grab-bag of three Sallie-requested enhancements that ship together.

#### 🎁 Real previews on the Bundle review screen

The Publish wizard now actually previews every file before approval:

- **Images** render as a 12-rem thumb, click for a full-screen lightbox.
- **Videos** render with inline `<video controls>` + a strip of 5 sample
  frames extracted client-side via a hidden `<video>` + canvas at evenly
  spaced times. Click a frame to enlarge it; clicking also seeks the
  player to that timestamp so Sallie can re-watch from there.
- For containers the WebView can't decode (e.g. some `.mov` variants
  on Windows), a polite "the file is still saved" banner appears.

Same enhanced layout is used for Fan-Site day groups (per-day file
collapsing kept). Editor-side `OrderedFileList` image thumbs also work
now — the asset protocol scope is wired up properly so file URLs
resolve, not just silently 404.

Under the hood: `tauri.conf.json` enables `assetProtocol` with `["**"]`
scope (Molly is single-user local-only), `BundleFileInfo` gains an
`absolutePath` field resolved against app_data_dir at read time, the
`tauri/protocol-asset` feature is enabled, and a new
`src/views/Bundles/components/BundleFilePreview.tsx` component handles
all the player + frame-strip mechanics.

#### 🎉 Holidays on the Calendar

New 🎉 **Holidays** tab in Settings + a holiday overlay on the Calendar:

- Fixed-date holidays (Christmas, July 4, Valentine's, etc.) and
  Nth-weekday holidays (3rd Monday MLK, last Monday Memorial Day,
  4th Thursday Thanksgiving, etc.) — both kinds resolve per-year via
  `lib/holidayResolver.ts`.
- 18 US extended defaults preloaded, each with hand-picked color
  pairings (red/blue for patriotic holidays, red/green for Christmas,
  orange/black for Halloween, etc.). Two-color holidays render as a
  diagonal split-tone pill on the calendar.
- Per-holiday edit: name, kind, month, day/weekday/nth, primary +
  secondary + text color, emoji, enabled toggle.
- "Reset to US defaults" wipes only `source='us_default'` rows and
  re-seeds them — custom-added holidays survive.

Calendar's day-cell shows up to 4 entries total, holidays first
(least-actionable context), then reminders 🔔, then clips. Hidden
overflow collapses to a "+N more" line as before.

#### 🏷️ Content tags on bundles

New 🏷️ **Content tags** tab in Settings + a tag picker on every bundle
form (Content / Custom / Fan-Site):

- Eight cute, color-coded default tags: tits, pantyhose, panties, face,
  ass, feet, flats, heels.
- Built-in tags can be renamed and recoloured but not deleted; custom
  user tags can be deleted any time.
- Per-bundle multi-select chip picker — pick 0 or many tags. Selection
  shows up on the bundle list rows + in the Publish review screen.
- Picker chip styling auto-derives a readable text color from the
  swatch luminance, so even hot-pink and butter-yellow tags stay
  legible without per-tag text-color config.

#### Schema

- Migration **025_holidays.sql** — `holidays` table (kind, month, day,
  weekday, nth, colors, emoji, enabled, source) + 18 US defaults +
  `calendar.holidaysEnabled` setting.
- Migration **026_content_tags.sql** — `content_tags_def` +
  `bundle_tag_links` (CASCADE on both bundle delete + tag delete) +
  8 built-in tags.
- `BundleSummary` + `BundleFileInfo` + `Bundle` boundary structs gain
  `tag_ids` / `absolute_path` / `description_audio_absolute_path`.

#### Tests

**171 Rust (+15) + 156 frontend (+20) = 327 total**:
- `holidays::tests` (7): seed loads, create round-trip, validator rejects
  bad inputs, update preserves source, set-enabled flips, delete works,
  reset preserves custom rows + reverts edits.
- `content_tags::tests` (6): 8 built-ins seeded, create validates inputs,
  built-in undeletable but renameable, set_bundle_tags round-trips, FK
  cascades on bundle delete + on tag delete.
- `holidayResolver.test.ts` (20): isoDateKey + daysInMonth + nth-weekday
  for MLK, Memorial Day, Thanksgiving, Mother's Day, Labor Day +
  resolveHolidayForMonth (month-mismatch, disabled, clamping, fixed,
  nth_weekday) + resolveHolidaysForMonth (grouping, filtering, empty).
- `camel_case_contract` (+2): `Holiday`, `ContentTag`.
- `migration_smoke`: anchors `holidays`, `content_tags_def`,
  `bundle_tag_links` tables.

#### Known limitations / NOT in this release

- **Frame extraction is best-effort** — Mac-only codecs (e.g. some HEVC
  variants in `.mov`) may not decode in the WebView; the banner shows
  and the player + frame strip are skipped.
- **Holidays are global** — no per-persona holiday sets in v1. Add one
  globally and Sallie sees it across all persona filters.
- **Tag search / filter not surfaced yet** — tags persist + show on
  rows + review, but the bundle list doesn't have a "filter by tag"
  picker. Easy add later.

## [1.14.0] — 2026-05-22

### Added — 📝 Notes (Phase 13)

A full Apple-Notes-style organiser with unlimited-depth folders, tagged
notes, WYSIWYG editor, attachments, search + body-find with regex,
export to MD/DOCX/PDF, and per-note font + paper colour overrides on
top of app-wide defaults.

Sidebar entry 📝 Notes (between Molly's Log and Reminders), three-pane
layout (folder tree | notes list | editor), autosave, click-to-jump
Find highlighting, six built-in tags (#ideas #plans #roadmap #promo
#content #bettereveryday) with user-editable colours, eleven vendored
fonts (Paper Daisy default + 10 SIL OFL Google Fonts), ten Apple-Notes
paper colour tints + custom hex, attachments (Open / Download / Delete)
under app_data/note_attachments/, export to Markdown via turndown,
Word via html-to-docx, PDF via jsPDF + html2canvas-pro.

Migrations **023 + 024** — 023 adds note_folders, notes, note_tags_def,
note_tag_links, note_attachments; 024 adds notes.font_size_pt for the
user-adjustable size slider. 28 new Tauri commands. **156 Rust + 136
frontend = 292 tests** still passing (+22 Rust in the notes module).

Late polish during Sallie's testing: replaced window.prompt /
window.confirm (silently broken in Tauri 2) with in-app NamePromptModal
+ ConfirmModal; added .molly-note-editor CSS to restore H1/H2/H3 + list
visuals stripped by Tailwind's preflight; per-font baseline scale so a
single integer size slider feels the same across all 11 fonts (Caveat,
Patrick Hand, Indie Flower, etc. all visually match at the same number).

## [1.13.0] — 2026-05-22

### Added — 🌀 Background jobs + ATW Repost automation (Phase 12, PR3 of 3)

Phase 10/11/12 trilogy complete. Molly now runs Sallie's existing `atw-repost-bot` on a schedule (default every 4h), with encrypted credentials from PR1's keystore, and full run-history monitoring.

#### What's new

- **New sidebar entry: 🌀 Jobs** — lists registered background jobs + recent run history per job, with status pills (running / success / failed), expandable log excerpts, **▶️ Run now** and **⏸ Disable** controls.
- **New Settings tab: 🌀 ATW Repost** with:
  - 🩺 **Health check** block — auto-detects Node.js, a Chromium-based browser (preference order: Chromium / ungoogled-chromium → Brave → Edge → Chrome as last resort), the bot's directory, `repost.js` presence, `node_modules` install. Each row shows ✓ or ✗ with what's missing. The "no browser found" row links to ungoogled-chromium + Brave (not Google Chrome).
  - 🔑 **Credentials** — email + password (encrypted via PR1's keystore on save). Password field gated by keystore unlock state.
  - 📂 **Bot installation** — picker for the user's existing `atw-repost-bot` directory. v1 doesn't ship the bot; v2 will vendor it.
  - Advanced: override browser binary path (for non-standard installs of Chromium / Brave / Edge).
  - ⏱ **Schedule + behavior** — cadence (1h / 2h / **4h default** / 6h / 12h / 24h), repost spread days (1-7), waking-hour window (start / end), UTC offset, delay between submissions (1-60s), headless toggle.
  - ▶️ **Run now** button — fires the bot on demand, surface status when done.
- **Background runner** spawned in `lib.rs::setup` alongside backup + bundle-purge + keystore-idle: polls every 60s, fires jobs whose `next_run_at` has passed, writes run-history rows. Individual job failures are recorded as `status='failed'` rows without breaking the loop.

#### Architecture — why no chromiumoxide port

The original plan called for porting `repost.js` (419 lines of Playwright + playwright-extra stealth) to Rust via `chromiumoxide`. Pragmatic decision: that's a multi-week project on its own with real regression risk (stealth fingerprinting, two-step login, CSS selector drift), and the existing Node bot is **already battle-tested and passing ATW's bot detection**.

v1 takes a different approach: **Molly orchestrates the existing Node bot as a subprocess**. The Rust side:
- Reads ATW credentials from the keystore-encrypted JSON blob (decrypt happens in Rust, plaintext goes straight into the subprocess env)
- Discovers Node + Chrome at standard paths (settings can override either)
- Spawns `node repost.js` from the user's `bot_dir` with all config passed via env vars (`ATW_EMAIL`, `ATW_PASSWORD`, `REPOST_DAYS`, etc.) — overrides whatever's in their `.env`
- Captures stdout + stderr line-by-line into a 200-line ring buffer
- Detects the bot's own `Run #N ended (...)` marker → kills the subprocess (the bot loops forever by default; we drive scheduling from Molly)
- Parses known stdout markers ("Login verification got HTTP", "Run complete — submitted N of M", "Nothing to repost") into a friendly summary
- Persists status + summary + log_excerpt into `background_job_runs`

Trade-off: user must have Node 18+ installed + their existing `atw-repost-bot` directory accessible. Future versions can vendor the bot files inside Molly's bundle and ship the Rust port if AllThingsWorn's DOM stabilises.

#### Tauri command surface (PR3)

- ATW: `get_atw_settings`, `set_atw_settings`, `atw_health_check`, `atw_run_now`
- Background jobs: `list_background_jobs`, `list_job_runs`, `upsert_atw_job`, `set_job_enabled`, `set_job_cadence`, `run_job_now`

All response structs `#[serde(rename_all = "camelCase")]` + contract-asserted.

#### Schema

- Migration `020_background_jobs.sql` adds:
  - `background_jobs` (id, kind, name, enabled, cadence_seconds, params_json, last_run_at, next_run_at, timestamps) + `(enabled, next_run_at)` index for the runner's SELECT
  - `background_job_runs` (id, job_id FK CASCADE, started_at, finished_at, status CHECK, summary, log_excerpt) + `(job_id, started_at DESC)` index
- ATW credentials live in `app_data/atw-settings.json` (parallel to bundler-settings.json / backup-settings.json) — single-row config so no SQLite schema needed.

#### Tests

273 → **295 tests passing** (132 Rust + 163 frontend; +22 Rust):
- `atw::tests` (7): summarize covers all the known stdout markers (login failure wins over run-end, run complete = success, nothing-to-repost, config error, hung subprocess, plus best-effort discover_node / discover_chrome / health_check defaults).
- `atw_settings::tests` (3): defaults match the existing `.env.example`, round-trip via disk, missing file yields defaults.
- `background_jobs::tests` (5): upsert creates then updates same row, due_jobs filters correctly, disabled jobs never due, begin → finish run round-trip, mark_job_ran advances next_run_at, deleting job cascades runs.
- `camel_case_contract` (+5): `AtwSettingsDto`, `AtwHealthCheck`, `RunOutcome`, `BackgroundJob`, `BackgroundJobRun`.
- `migration_smoke`: `background_jobs` + `background_job_runs` anchor tables.

#### Manual testing required

The ATW bot itself can't be tested in CI — it talks to a real third-party site behind real credentials. Sallie needs to manually verify:
1. Settings → 🌀 ATW: all 5 health-check rows show ✓
2. Set ATW email + password (keystore unlocked)
3. ▶️ Run ATW Repost now → status flips to "Running" → 5-15 min later shows success summary
4. 🌀 Jobs sidebar: ATW Repost row appears with the run history; click a row to expand the log excerpt
5. Cadence change: drop to 1h, wait 1 hour with Molly open, verify it fires automatically (or use SQL to set `next_run_at` to 1s ago and wait <60s for the runner tick to pick it up)

#### Known limitations / NOT in this release

- **Bot files not vendored** — user must have an existing `atw-repost-bot/` directory. Vendoring + first-run `npm install` is a v2 feature.
- **No system tray** — jobs only fire while Molly is open. A tray icon for true background operation is on the roadmap.
- **No retry-on-failure** — failed runs just sit as `failed` rows until the next scheduled tick.
- **Single job kind in v1** — only `atw_repost`. The runner is generic enough to add more (OnlyFans repost, email summaries, etc.) by adding a `match` arm.

## [1.12.0] — 2026-05-22

### Added — 🔑 Site password manager + sub-credentials per site (Phase 10, PR2 of 3)

The keystore from v1.11.0 now actually holds data. Sallie can store encrypted passwords for any site, reveal them for 10 seconds, or copy them to clipboard (auto-clears after 30s). Each site can hold **multiple credentials** — a CoC store + a PoA store on the same C4S, or alt accounts on OnlyFans, etc. (pulled forward from the deferred list per user ask).

#### What's new

- **Settings → Sites → site editor** gains a **Credentials** section:
  - Lists all credentials for the site (label + username + password)
  - **Set as primary** radio per row (exactly-one-primary invariant enforced via single transaction)
  - **+ Add credential** button to create a new login (label e.g. "CoC store", "backup")
  - Inline edit for label and username (commit on blur)
  - Password field gated by keystore unlock state — three states: not-set-up (link to Security setup), locked (🔒 + Unlock hint), unlocked (standard input with show/hide toggle)
  - Reveal (10s auto-hide), Clear (removes stored password), and Delete (cannot delete the last credential — keeps `sites.username` legacy-compat row intact)
- **Molly Helper** site cards gain per-credential **👁 Reveal** and **📋 Copy password** buttons:
  - Single-credential sites (the common case) render compactly with one row per password
  - Multi-credential sites label each row with its credential name
  - 🔒 placeholder shown when keystore is locked
  - Top "Keystore is locked — Unlock now" banner appears when any visible site has a password and the keystore is locked; inline passphrase entry without leaving the view
- **Clipboard auto-clear** 30s after Copy password (best-effort; clipboard managers like Alfred may retain history — documented limitation).

#### UX improvements to keystore recovery (Phase 10 follow-up)

After user feedback that typing 24 BIP-39 words into a single textarea was painful (especially trying to remember whitespace and reading back the numbered list), the Settings → 🔐 Security pane gets a **dedicated 24-cell grid input**:

- 6 columns × 4 rows; each cell labeled `1.` through `24.` in monospace
- Type a word + press **space or Enter** → focus jumps to the next cell
- **Backspace on empty cell** → jumps back
- **Arrow keys** at cell edge → navigate between cells
- Paste a single word into a cell → fills that cell; paste multiple words → spreads across subsequent cells
- 📋 **Paste from clipboard** button fills all 24 in one click
- **Tolerates "1. word" numbered list paste-back** — leading `N.` or `N)` prefixes are stripped per token
- Live `X/24 filled` counter; Import button only enables at 24/24
- The Reveal side (when you export your mnemonic) uses the same grid layout (read-only) so the visual rhythm matches exactly. Plus a "📝 Copy numbered list" button alongside the existing "Copy all (one line)" so you can paste back in either format.

#### Architecture

- **No new crypto code** — PR2 uses the v1.11.0 keystore as-is. Field encryption/decryption happen in Rust (`site_credentials::set_credential_password`, `reveal_credential_password`); the frontend never holds the wrapped DEK.
- **Cross-DEK-version detection**: if a stored ciphertext was written under a previous DEK generation (e.g. after `import_keystore_from_mnemonic` bumped the version), reveal returns `DecryptionFailed` so the UI can prompt "re-enter this password." Stored rows include `password_dek_version` so future re-key migrations can identify stale rows.

#### Tauri command surface (PR2)

`list_site_credentials`, `create_site_credential`, `update_credential_username`, `update_credential_label`, `set_credential_password`, `clear_credential_password`, `reveal_credential_password`, `set_credential_primary`, `delete_site_credential`. All response structs `#[serde(rename_all = "camelCase")]` + contract-asserted.

#### Schema

- Migration `019_site_credentials.sql` adds the `site_credentials` child table:
  - `(id, site_id, label, username, password_encrypted, password_dek_version, password_updated_at, is_primary, sort_order, created_at, updated_at)`
  - FK to `sites(id) ON DELETE CASCADE`; deleting a site removes its credentials
  - `is_primary` boolean: exactly one per site (enforced by data layer transactions)
  - `sort_order` int for user-controlled ordering
- **Backfill**: every existing site row gets a primary credential row carrying the legacy `sites.username`. New sites created post-019 also get a primary credential automatically via the data-layer INSERT wrapper.
- `sites.username` stays in the schema for backwards-compat with existing read paths (Molly Helper's "Copy user" button). Changes to the primary credential's username are mirrored back to `sites.username` by the data layer so legacy paths stay correct. Deprecating the column is a follow-up.

#### Tests

252 → **273 tests passing** (110 Rust + 163 frontend, +21 PR2):
- `site_credentials::tests` (9): backfill creates one primary per site, create_then_list, set_password_then_clear, set_primary_clears_others_and_mirrors_username, update_primary_username_syncs_sites_username, update_secondary_username_does_not_touch_sites_username, cannot_delete_last_credential, delete_works_when_more_than_one_exists, deleting_site_cascades_credentials.
- `camel_case_contract` (+1): `SiteCredential`.
- `migration_smoke`: site_credentials table + credential-count-equals-site-count backfill assertion.

#### Known limitations / NOT in this release

- ATW automation still missing (PR3 — background jobs + chromiumoxide port).
- No "import from 1Password / Bitwarden" yet.
- macOS Keychain integration still deferred — passphrase required on every Molly launch.

## [1.11.0] — 2026-05-22

### Added — 🔐 Keystore infrastructure (Phase 10, PR1 of 3)

Foundation for encrypted credentials. **No user data is encrypted yet** — that lands in PR2 (site passwords + sub-credentials per site) and PR3 (ATW automation + background jobs). This release ships only the crypto subsystem and the Security settings pane so the keystore can be exercised in isolation before any production data touches it.

#### What's new

- **New Settings → 🔐 Security tab** with: status block, create keystore, change passphrase, reveal 24-word recovery mnemonic with copy-all + warning banner + "I've saved these" gate, restore from mnemonic with destructive-action confirm, wipe.
- **Lock / unlock UX**: keystore is always locked on app launch; unlocks for the session; auto-locks after 8 hours of inactivity; manual **Lock now** button.
- **Background idle-checker** spawned alongside backup + bundle-purge in `lib.rs::setup`. Polls every 60s; clears cached DEK on idle; emits `keystore-locked` event.

#### Crypto design (ported from PurpleIRC's KeyStore + EncryptedJSON)

- **KEK derivation**: PBKDF2-HMAC-SHA256, 300k iterations, random 16-byte salt per passphrase change.
- **DEK**: 256-bit random, generated once on `init_keystore`. Never re-derived; passphrase changes re-wrap.
- **Wrap format**: AES-GCM combined (12-byte nonce || ciphertext || 16-byte tag).
- **Field encrypt format**: 1-byte version (0x01) || 12-byte nonce || ciphertext || 16-byte tag, base64-encoded.
- **Mnemonic format v1**: 24 BIP-39 English words encoding the 32-byte DEK with checksum.
- **Wrong-passphrase rate limit**: 500ms `tokio::sleep` floor on AEAD tag failure. No counter / lockout.
- **In-memory hygiene**: `Dek` newtype with `Drop`-time `zeroize`; Debug-format never prints key bytes.
- **Error messages** intentionally generic — never leak whether a passphrase was "close."

#### Tauri command surface (PR1)

`keystore_status`, `init_keystore`, `unlock_keystore`, `lock_keystore`, `change_passphrase`, `encrypt_field`, `decrypt_field`, `export_keystore_mnemonic`, `import_keystore_from_mnemonic`, `wipe_keystore`. All response structs camelCase + contract-test asserted.

#### Schema

- Migration `018_crypto_keystore.sql` adds the singleton `crypto_keystore` table with salt + KDF params + wrapped DEK. Storing in SQLite (not a sidecar) means Molly's existing backup ZIPs automatically capture the keystore.
- Migration smoke test extended: anchor-table list + singleton-row assertion.

#### Tests

207 → **243 tests passing** (100 Rust + 143 frontend; +23 Rust from crypto, frontend tests carry over):
- `crypto::wrap` (10) — round-trip ASCII / UTF-8+emoji / 1MB, fresh-nonce guarantee, tampered tag/nonce/body rejected, wrong-key rejected, unknown-version + truncated + bad-base64 rejected.
- `crypto::keystore` (8) — init+unlock happy path, wrong-passphrase rate-limited (≥500ms), init-twice rejected, passphrase-too-short rejected, change-passphrase preserves DEK, import rotates + bumps version, wipe returns to uninitialized, Debug doesn't leak bytes.
- `crypto::mnemonic` (5) — round-trip identity, round-trip 32 random DEKs, wrong-length / unknown-word (with index) / bad-checksum rejected, case+whitespace insensitive.
- `camel_case_contract` (+3) — `KeystoreStatus`, `EncryptedField`, `MnemonicWords`.
- `migration_smoke` — `crypto_keystore` table + singleton-row assertion.

#### Known limitations / NOT in this release

- No site passwords are encrypted yet — Molly Helper and the Sites editor are unchanged.
- No ATW automation yet (PR3).
- No macOS Keychain integration — by design, keystore is always re-prompted on app launch.

## [1.10.0] — 2026-05-22

### Added — 🎁 Content Bundler (Phase 9, part 2 of 2)

Completes the Content Bundler. The two remaining bundle types now publish end-to-end:

- **Custom Bundle** — for delivering a custom video to a specific buyer / platform / price.
  - Fields: persona, title, go-live date (defaults to tomorrow), 1+ videos/images (drag-reorder), **delivery platform** (site picker OR free-text URL; exactly-one rule), recipient, price (or "handled in delivery platform" checkbox).
  - URL validator requires `http://` or `https://`. Site picker filters to the bundle's persona using the existing `sites` table.
  - Bundle layout matches Content (`Video/00001_…`, `Photos/00001_…`); `info.md` and `Molly.log` include a `Delivery` section listing recipient / platform / price.
- **Fan Site Bundle** — a whole month of fan-site posts on a calendar.
  - Field: persona, title, year + month, per-day message + files.
  - Renders a 7-column month grid with Sun-Sat labels. Each day cell color-codes:
    grey (out of month) → empty → amber (partial — message OR file) → persona-accent (complete — both).
  - Click a day → modal with short-message textarea + per-day file picker. Days are created idempotently on first open. The whole `bundle_fan_days` row + cascaded files can be deleted from the modal.
  - Live "completion bar" under the calendar: `X/N complete · M partial` with a fill-up progress.
  - Files in the ZIP are renamed `FanSite/DD_NN_<orig>` where `DD` is calendar day and `NN` is within-day position — order preserved across the whole month.
- **Validation engine** extended (server + client) with `validate_custom_delivery`, `validate_custom_bundle`, `validate_fansite_completion`, `validate_fansite_bundle`, and the shared `days_in_month` helper (mirrored in TS as `daysInMonth`).
- **Publish wizard** review pane gets per-type sections — Custom shows recipient + platform + price; Fan Site shows a sorted day-by-day list with message + file counts.

### Schema

No new migration. The `017_bundles.sql` migration shipped in 1.9.0 already declared every Custom + FanSite column; PR2 fills them in with form wiring + Tauri commands.

### Tauri command surface (additions)

- `create_fan_day(bundleUid, dayOfMonth)` — idempotent create-or-return; rejects out-of-1..31 days.
- `update_fan_day_message(fanDayId, message)` — also bumps parent `bundles.updated_at`.
- `delete_fan_day(fanDayId)` — cascades to `bundle_files` (DB FK), returns the deleted relpaths so the Tauri layer can unlink the actual files on disk.

### Tests

185 (PR1) → **207 tests passing** (71 Rust + 136 frontend, +22 PR2 coverage):

- `bundles.rs` (+9): `days_in_month` (28/29/30/31 + invalid), custom delivery mutex / URL shape / recipient required / price-required-unless-handled, FanSite completion lists missing days + differentiates message-vs-file, FanSite needs year+month, fan_day CRUD round-trip + cascade.
- `lib/bundleValidation.test.ts` (+13): mirror of all the new Rust rules end-to-end.

### Known limitations (carried forward from 1.9.0)

- DMG remains unsigned in the Apple-Developer-ID sense.
- `releases/latest/download/latest.json` is monorepo-shared.

## [1.9.0] — 2026-05-22

### Added — 🎁 Content Bundler (Phase 9, part 1 of 2)

New top-level **Bundles** sidebar entry. Sallie composes a **Content
Bundle** — title, persona, description (text or audio), 3+ categories
(drag-reorder), one or more videos/images (drag-reorder), go-live date,
optional special instructions — then publishes it as a deterministic,
SHA-256-hashed two-layer ZIP at `~/Downloads/Molly bundles/<UID>.zip`
ready to drop into Slack for Robert.

PR1 ships the **Content** bundle type end-to-end. The **Custom** and
**Fan Site** bundle types appear in a follow-on release (drafts can be
created today; the form/publish wiring lands in 1.10.0).

#### What gets bundled

```
<UID>.zip                          ← outer (signed deliverable)
├── <UID>-inner.zip                ← inner
│   ├── info.md                    ← human-readable wizard summary (markdown)
│   ├── Molly.log                  ← technical build log: every input + per-file SHA + verify
│   ├── Audio/<file>               ← audio description if present
│   ├── Video/00001_<orig>.mp4     ← 5-digit order prefix
│   └── Photos/00001_<orig>.jpg
└── hashes.json                    ← SHA-256 of inner ZIP + every file inside
```

**Note on `Molly.log` naming**: this is the bundle's build log, **not**
the personal-journal "Molly's Log" feature in the sidebar. The two share
a name by accident of history; the in-zip file contains a step-by-step
audit of THIS bundle's composition (inputs, per-file hashes, verify
matches), nothing from the journal table.

Files are re-hashed at compose time and asserted against the upload-time
hash; if you've modified a file on disk between upload and publish, the
publish refuses with `attachment changed since upload` so you can re-upload.

#### Validation engine (`src/lib/bundleValidation.ts` + `bundles.rs::validate_*`)

Per-field validators with stable DOM ids; the publish wizard's
`ValidationChecklist` lets Sallie click each issue to scroll-and-focus
the offending field. Rules for the Content type:

- **Title**: non-empty, two+ words, not in `{none, blank, custom}`.
- **Persona**: required (one of CoC / PoA / Sa).
- **Description**: exactly one of text or audio. Text is scanned for
  prohibited substrings (defaults: `blackmail / mommy / addiction /
  addicted`; editable in Settings → Bundler).
- **Categories**: ≥3 (uppercase, deduped, drag-reorder). The picker's
  suggestion list merges (a) categories Sallie has used on previous
  bundles, recency-ordered, with (b) every non-archived category from
  MasterClipper's own SQLite (read-only, fail-quiet — empty list if MC
  isn't installed or the DB is locked).
- **Go-live date**: required, ≥ today; warns ("Are you allowing enough
  time for editing?") if within today+5d.
- **Files**: ≥1 video or image. Drag-reorder. Each file re-numbered
  `00001_…` in the bundle.

The TypeScript validator runs live in the form for friction-free
feedback; the Rust validator (`bundles.rs::validate_for_publish`) is
authoritative on publish and re-checks everything inside the publish
transaction.

#### Publish flow

Wizard (`PublishWizard.tsx`) walks every field read-only — including
audio playback and image thumbnails — runs both validators, surfaces
any issues with click-to-jump, and on Approve calls `publish_bundle`.
The Rust side composes the ZIP, hashes both layers, atomically renames
to the output dir, stamps the bundle row, and (for Content type only)
**upserts a row into the existing `clips` table** with `status='Bundled'`
so the go-live date surfaces on Molly's Calendar alongside everything
else. `molly_notes_html` is preserved across re-publishes — delete-the-
bundle-then-republish keeps Sallie's editable clip notes intact.

#### Settings → 🎁 Bundler

- **Output folder** — default `~/Downloads/Molly bundles/`; override + Reveal.
- **Warn threshold** (days) for aging drafts (default 30).
- **Auto-purge threshold** (days) for old published bundles (default 60).
  Launch-time hook runs at most once per day; **Run purge now** button bypasses
  the debounce.
- **Prohibited words** — chip CRUD against `bundle_prohibited_words`
  (seeded with the four defaults on install).

#### Schema

- Migration `017_bundles.sql` adds `bundles` (parent table with type
  discriminator + null-where-unused columns), `bundle_files` (ordered
  media; `position` 1..N within bundle or within fansite day),
  `bundle_categories` (UPPERCASE + position), `bundle_fan_days`
  (reserved for PR2), and `bundle_prohibited_words` (seeded with
  `blackmail`, `mommy`, `addiction`, `addicted`).
- Migration smoke test extended: 5 new anchor tables + seed-count
  assertion on `bundle_prohibited_words`.

#### Tests

105 → **185 tests passing** (62 Rust + 123 frontend):
- `bundle_zip.rs::tests` (7) — determinism, layout, hash-vs-payload,
  mutation detection, FanSite naming, info.md content, name sanitization.
- `bundles.rs::tests` (10) — UID monotonicity per day, prohibited-word
  seeding + CRUD, all validators, set_categories normalization,
  clip-upsert preserving `molly_notes_html`, auto-purge threshold +
  state guards, draft delete returns relpaths, aging-flag buckets.
- `camel_case_contract` (11) — every new boundary struct (BundleSummary,
  BundleFileInfo, BundleCategory, BundleFanDay, Bundle, BundlePublishResult,
  PurgeResult, BundleArchiveRow, BundlerSettings, ValidationIssue,
  full bundle aggregate) serializes camelCase.
- `lib/bundleUid.test.ts` (5) — format + parse + today.
- `lib/bundleValidation.test.ts` (~25) — every per-field rule.
- `lib/reorderHelpers.test.ts` (7) — drag-reorder splice math.

#### Files added / touched

New Rust: `src-tauri/src/bundle_zip.rs`, `src-tauri/src/bundles.rs`,
`src-tauri/migrations/017_bundles.sql`. `sha2 = "0.10"` added to
`Cargo.toml`. `lib.rs` wires the modules, registers ~20 new commands,
appends the migration + smoke-test entry, and spawns the auto-purge
launch hook next to the existing backup hook.

New frontend: `src/data/bundles.ts`, `src/lib/bundleUid.ts`,
`src/lib/bundleValidation.ts`, `src/lib/reorderHelpers.ts`,
`src/views/Bundles/` (BundlesListView, BundleDraftView via the list,
ContentBundleForm, PublishWizard, plus 7 shared components under
`components/`), `src/views/Settings/BundlerSettings.tsx`. Sidebar +
App.tsx + SettingsView.tsx route the new view.

#### Known limitations

- Custom and Fan Site bundle drafts can be created but the forms are
  the next release's job.
- The bundle output folder must be writable by Molly; no fallback
  prompt yet if the override dir disappears.

## [1.8.2] — 2026-05-22

### Fixed — release pipeline (no app code changes)

- **Auto-updater no longer breaks the morning after a release.** Until 1.8.2 the workflow created the GitHub release as a *draft* and required a manual UI publish; v1.8.1 sat as a draft overnight, which broke the updater because `releases/latest/download/latest.json` only resolves against published releases. The workflow now flips draft → published as its final step.
- **Downloaded .dmg no longer reports "Molly is damaged and can't be opened" on macOS Sonoma+.** The Tauri bundler only linker-signs the app; macOS Sonoma+ Gatekeeper rejects linker-signed downloads outright even with right-click → Open. The mac build step now runs `codesign --force --deep --sign - --options runtime` against the bundle before packing the DMG + tarball, then rebuilds the DMG so the downloadable carries the same ad-hoc signature. Gatekeeper now treats it as "unidentified developer" — the documented right-click → Open path works again.
- **Windows updater no longer fails signature verification.** The `latest.json` Windows entry pointed at `Molly_x.x.x_x64-setup.exe` while the minisign signature was generated against the `.nsis.zip`. URL now points at the `.nsis.zip` archive that was actually signed.

### Known limitations (unchanged from 1.8.1)

- DMG remains *unsigned in the Apple-Developer-ID sense* (and unnotarized). First-run on macOS will still show "unidentified developer" — right-click → Open works. If you still see "damaged," strip the quarantine bit: `xattr -dr com.apple.quarantine /Applications/Molly.app`. Real Developer ID + notarization is tracked separately.
- `releases/latest/download/latest.json` is monorepo-shared: if another PhantomLives subproject releases after Molly, Molly's updater endpoint is briefly wrong until the next Molly release. Per-project stable updater URL is tracked separately.

## [1.8.1] — 2026-05-21

### Added

- **Drill-down from the C4S Dashboard.** Each row of "Clips by status," each entry in "Top 10 categories," and each pill in "Top 10 keywords" is now a clickable button that opens the C4S grid pre-filtered to that value. Category + keyword filters match the comma-split list (so drilling "BBW" doesn't surface "BBW STUFFING" rows), and active filters show as removable pills above the grid alongside the existing search / sort / status controls. Stacks naturally with the search box + status dropdown + regex toggle, so a click into "active" can be narrowed further by typing.

### Fixed

- **Import wizard error message now tells you what's actually in the file you picked.** Previously a wrong-format pick gave a generic "doesn't look like a Clips4Sale export — missing columns: …". Now the error shows the columns the parser *did* see (one giant column when the delimiter was comma, or the first 8 column names if they're just unfamiliar), detects ZIP magic bytes for accidental .xlsx picks, calls out comma-delimited files as "look for Export to CSV, not Excel," and prints the filename + byte size so it's obvious whether the right file landed in the picker. Error block now renders multi-line messages (`whitespace-pre-wrap`).
- **`build-app.sh` no longer passes `--no-open` to `tauri build`.** The script consumes `--no-open` and `--no-install` for `install.sh`; both were being forwarded to `tauri build` which rejects them. Filtered out before forwarding. Also wrapped the args-array expansion so `set -u` doesn't blow up when no args were passed.
- **Missing pnpm transitive dep.** Added `postcss-selector-parser` as an explicit dev dep so Vite's PostCSS pipeline can find it under pnpm's strict-hoisted `node_modules` layout (npm's flat layout hid the gap).

## [1.8.0] — 2026-05-21

### Added — 💌 In-app User Manual

- **New sidebar entry** at the bottom of the nav between Settings and footer. Opens `USER_MANUAL.md` rendered in Molly's persona-tinted style — pastel cards, Comfortaa headings, 💕 bullet glyphs, gradient blockquotes, decorative hr dividers. Hand-rolled block parser (`src/lib/markdownLite.ts`) in the spirit of `PurpleLife/Sources/PurpleLife/Views/SecurityDocView.swift` — keeps the bundle library-free (no `react-markdown`) and the styling 100% under our control.
- **Right-rail TOC** auto-extracts H1/H2 headings; click to jump; the active heading highlights as you scroll (IntersectionObserver). Hidden below `lg` breakpoint.
- **SayingsBanner** at the top of the manual view so the page opens with a cute encouragement before getting into the how-to.
- **Cuteness lift on the manual itself.** Rewrote `USER_MANUAL.md` end-to-end with warmer, more Sallie-by-name voice; added section emojis throughout; sprinkled little encouragements between sections; updated the 1.0 intro to reflect 1.8 + C4S Store; closed with a "note from the team". The manual is content, not configuration — the in-app viewer always renders whatever the shipped `USER_MANUAL.md` says.
- **Vitest coverage**: `markdownLite.test.ts` (12) covers the block parser (headings, lists, blockquotes, fenced code with language hint, horizontal rules, paragraph join, list-flushed-by-heading) + the inline tokenizer (code spans, **bold**, *italic*, links, plain text, no-markdown-inside-code).

### Added — 🛍️ C4S Store

New top-level sidebar entry between Clips and Customers for browsing the **Clips4Sale catalog snapshot**. Sallie exports both stores (CoC + PoA) from C4S as pipe-delimited CSVs and Molly overlays each one atomically (delete + bulk insert + count-verify in a single transaction). The data is read-only reference — no editing.

- **Sub-routes**: Dashboard (summary cards + stale-data banner) → Grid (searchable table) → Detail (full-page row inspector with ← Back that preserves search/sort/filter). Honors the top persona switcher; ★All interleaves both stores, Sa shows a friendly empty state.
- **Dashboard cards**: total clips, lifetime sales, 6-month income, per-store split bars (★All only), status breakdown bars, top-10 categories, top-10 keyword chips, price min/mean/max.
- **Stale-data banner**: tiered cute language by age — 🌸 fresh (≤1 day), ✨ still pretty fresh (2–6), 🌷 might be worth a re-import soon (7–29), 🌼 time for a fresh export? (30+), 🌱 nothing on file. Rotates a SayingsBanner-style display font per render. Hideable from Settings.
- **Import wizard**: one ✨ Import C4S CSV button, file picker → auto-detect persona from the `Performers` column (`CoC` → CoC, `PrincessOFAddiction` → PoA) → confirm-and-override → atomic replace → success card with verified row count. Skips parsing-broken rows (missing Clip ID or Title) and surfaces them in an expandable `<details>` so nothing fails silently.
- **Grid**: search w/ regex toggle + "N of M" + amber invalid-regex hint + Clear button + status dropdown filter. 13 columns total; Persona + Title always visible, every other column toggleable in Settings. Click any header to sort (re-click flips direction). Click row to open detail.

### Added — Settings → 🛍️ C4S

- Stale-data banner on/off toggle.
- Per-column on/off toggles. Defaults track the data shape we observed in Sallie's exports: Tracking Tag and Preview Filename default OFF (always empty in current C4S exports); everything else defaults ON.
- ✨ Import C4S CSV button (same wizard as the dashboard).
- Last-imports readout (CoC + PoA, with timestamp and row count).
- 🗑 Delete all C4S data — two-tap `ConfirmButton`. Wipes both stores' clips + audit rows; nothing else is touched.

### Schema

- Migration `016_c4s_clips.sql` adds the `c4s_clips` table (PK `(persona_code, clip_id)`; `persona_code` CHECK-locked to `'CoC' | 'PoA'`) and `c4s_imports` audit table with a persona+time index. No FKs to other Molly tables — this is a reference snapshot, not relational state.

### Tauri command surface

- `c4s::replace_c4s_clips` — atomic `BEGIN → DELETE persona → bulk INSERT → INSERT audit → COMMIT` via `rusqlite`. Returns `ReplaceResult { personaCode, deletedCount, insertedCount, expectedCount, matches, importedAt }` so the UI can warn on count mismatch.
- `c4s::delete_all_c4s_data` — single-transaction wipe of `c4s_clips` + `c4s_imports`. Returns `DeleteAllResult`.
- Both DTOs added to `camel_case_contract`; total now 9.

### Tests

- **Rust (+8)**: `c4s::tests` covers (1) insert-then-count-matches, (2) overlay-only-its-own-persona, (3) empty-rows-clears-persona, (4) `delete_all` wipes both stores + audit, (5) invalid-persona CHECK rejection, (6) ISO timestamp format contract. Plus 2 new `camel_case_contract` entries for `ReplaceResult` + `DeleteAllResult`. `migration_smoke` anchor list extended to `c4s_clips` + `c4s_imports`. Cargo test total: 22 → 30.
- **Frontend (+31)**: `csvPipe.test.ts` (10) covers pipe-delimited parser w/ multi-line quoted descriptions (the C4S edge case), CRLF, BOM, escaped `""`, empty cells, ragged rows. `c4sClassify.test.ts` (9) covers Performers → persona mapping with normalization + `detectPersonaFromRows` walk. `markdownLite.test.ts` (12) covers the in-app manual viewer's block + inline parsers. Vitest total: 44 → 75.
- **Combined: 30 cargo + 75 vitest = 105 tests** (run via `./run-tests.sh` — `CI=true` in non-TTY environments).

### MasterClipper retrofit notes (filed for later, not implemented here)

MasterClipper has a sibling C4S Historical import that's been in production for a while. While building Molly's version we identified seven improvements to backport. Tracked in `MasterClipper/HANDOFF.md` under a new "C4S import — retrofit candidates from Molly" section.

## [1.7.3] — 2026-05-21

### Tests

Closed the two highest-value gaps the 1.7.2 audit identified.

**Rust BLOB round-trip (16 → 22)** — extracted `insert_history_row` / `read_history_blob` (`history.rs`) and `insert_log_row` / `read_log_blob` (`log.rs`) as pure functions of `&Connection`; the Tauri commands are now thin wrappers. Six new tests against in-memory SQLite with migrations 001–015 applied:
- `history::tests::blob_round_trips_exactly` — bytes including nulls + high-bytes survive write→read.
- `history::tests::read_history_blob_returns_error_for_missing_id`.
- `history::tests::insert_with_unknown_customer_uid_fails` — FK enforcement.
- `log::tests::blob_round_trips_exactly` — same for `mollys_log`.
- `log::tests::read_log_blob_returns_error_for_missing_id`.
- `log::tests::empty_body_and_zero_byte_blob_are_allowed` — edge case.

**Frontend pure-function suite (vitest, 0 → 44)** — `OUT_OF_SCOPE.md`'s "frontend tests deferred" stance is partially lifted. Added `vitest@4.1.7` as a dev dep, `vitest.config.ts` (node env, `src/**/*.test.ts` discovery), and `pnpm test` / `pnpm test:watch` scripts. Four test files:
- `src/lib/money.test.ts` (10) — `parseMoney` / `fmtMoney` incl. trailing-decimal handling that the `MoneyInput` pattern depends on.
- `src/lib/phone.test.ts` (12) — `formatUSPhone` partials + canonical + extension; `isValidUSPhone` + `usPhoneDigits` covering the leading-`1` strip.
- `src/lib/cadence.test.ts` (18) — `nextOccurrencesAfter` for all six cadence kinds (daily / weekly + biweekly anchor / monthly_dom + EoM clamp / monthly_days_before_next / monthly_days_after_eom / every_n_days) + every exported date helper.
- `src/lib/uid.test.ts` (3) — `formatDateKey` Y-M-D shape + zero-pad.

**`run-tests.sh`** now chains both: `cargo test --lib` then `pnpm test`. **66 tests total** in well under 5 seconds wall-clock.

Component / rendering tests, `attachments.rs`, and `export.rs` stay untested — see `OUT_OF_SCOPE.md` for the updated rationale.

## [1.7.2] — 2026-05-21

### Tests

- **Migration smoke test.** New `lib.rs::migration_smoke::all_migrations_apply_cleanly` opens an in-memory SQLite with `PRAGMA foreign_keys = ON`, runs every shipped migration (001 → 015) in order via `include_str!`, asserts 23 anchor tables exist, and asserts `kinks` was preloaded with ≥349 rows by migration 011. Catches schema regressions (bad ALTER, missing FK target, SQL syntax errors, accidental `DROP TABLE`, broken preload INSERT) before they touch Sallie's DB.
- **`fsutil::downloads_subdir` contract pinned.** Tiny test asserting the path ends with the requested sub and is absolute (or `.`-rooted fallback). Holds the contract that all the "where do I put this?" code paths depend on.
- Total cargo tests: **16** (7 backup + 7 camelCase contract + 1 migration smoke + 1 fsutil).

### Docs

- **README.md** — updated to reflect 1.7.x reality: new "feature growth since 1.0.0" lede, Molly's Log row de-Trekkified, test count 12 → 16, migration count 9 → 15, source-file list includes `history.rs` + `log.rs`, phases table extended from 1.0 through 1.7.
- **HANDOFF.md** — `src/components/` now lists `KinkChipPicker` + `MoneyInput`; `src/data/` lists `customerHistory`, `customerSales`, `mollysLog`; `src/views/` adds `MollysLog`; Tests section documents the four kinds of cargo tests and notes the known untested surface (history/log/attachments/export Rust I/O, all frontend) with the rationale (deferred per `OUT_OF_SCOPE.md`).

## [1.7.1] — 2026-05-21

### Changed — Molly's Log polish

- **Past entries render in a handwritten font.** Caveat (already loaded via the Google Fonts link for the sayings banner) is now applied to the body of each saved entry at `fontSize: 1.25rem`, `lineHeight: 1.4`. Composer textarea + edit-mode textarea stay in the regular UI font so typing is crisp; only the read-only render gets the journal look.
- **Dropped the Trek references.** Sallie isn't into Star Trek, so:
  - Placeholder is now just **"Note to self…"** (no more "Captain's log…" / "Stardate today…" rotation; removed the `PROMPTS` array entirely).
  - Submit button is **"✨ Log entry"** (no 🖖 Vulcan salute).
  - Page subtitle reads "Your personal journal — notes to self with optional file attachments…" (was "captain's-log style journal").
  - Sidebar hint and USER_MANUAL section updated to match.

## [1.7.0] — 2026-05-21

### Added

- **📔 Molly's Log** — new top-level sidebar entry (right below Home) for a Captain's-log-style personal journal. Compose freeform text entries with an optional inline file attachment; each entry is timestamped and editable / deletable.
  - Mirrors the customer-history pattern: `customer_history` minus the customer FK and persona binding. Inline BLOB attachments via a parallel `src-tauri/src/log.rs` rusqlite module (`add_log_entry_with_attachment`, `download_log_attachment`) so binary bytes never round-trip through JS IPC.
  - Filter input above the list with a **grep** checkbox (regex toggle); substring by default, real `RegExp` when toggled. "N of M" count + Clear button + inline amber warning on invalid regex. Filter searches across body + attachment filename.
  - Editing reveals an inline textarea (Save / Cancel); deletion is two-tap-confirmed via `ConfirmButton` and removes the row + its inline BLOB.
  - Composer placeholder rotates a short list of Trek-flavored openers ("Captain's log…", "Stardate today — note to self…") for vibes; doesn't constrain the actual entry format.

### Schema

- Migration `015_mollys_log.sql` adds the `mollys_log` table (id, ts, body, attachment_filename/mime/size, attachment_data BLOB, updated_at) + index on `ts DESC`.

### Tauri command surface

- `log::add_log_entry_with_attachment` — reads the file, INSERTs the row with the BLOB, returns the new id.
- `log::download_log_attachment` — streams the BLOB by id out to a target path.
- New `LogEntryRef` boundary struct + matching `camel_case_contract` test; total now 14.

## [1.6.2] — 2026-05-21

### Fixed

- **Adhoc Income row layout — Edit/✕ buttons no longer overlap the amount.** The actions cell on adhoc rows was `col-span-1` but had to hold *two* pill buttons (Edit + ConfirmButton), which collectively were wider than 1/12 of the table and overflowed leftward, visually clobbering the amount column (you'd see something like `$66.32` truncated to `$66`). The sale row's tiny "on customer" hint fit fine in 1 col so this only bit adhoc rows. Widened the actions column to `col-span-2` and reclaimed the col from the note. Also added `whitespace-nowrap` to the amount cell so totals like `$1,234.56` can't wrap.

## [1.6.1] — 2026-05-21

### Fixed

- **Money inputs across the app now accept dollars and cents.** Same root cause we hit on Settings → Products in 1.2.1: `<input value={String(amount)} onChange={parseMoney(e.target.value)}>` re-renders on every keystroke, so typing `5.` parses to `5`, strips the trailing dot, and the user can never reach the cents. Refactored into a reusable `src/components/MoneyInput.tsx` that keeps the *display* as a local string buffer while emitting the parsed number to the parent — and uses a ref to ignore re-renders triggered by its own emit so the buffer doesn't get clobbered mid-typing. Re-init only happens when the value changes from outside (caller switched rows).
- **Sites swapped:** Adhoc Income (the user-reported regression), Expenses (amount + partial-exclusion amount), Recurring Expenses, Site Income Wizard. All four were sharing the same broken pattern.

## [1.6.0] — 2026-05-21

### Added

- **Reminders on the calendar.** Pending occurrences from active schedules now render as 🔔 pills on the day grid in `src/views/Calendar/CalendarView.tsx`. New `listOccurrencesInRange(from, to, personaCode)` in `src/data/occurrences.ts` runs alongside the existing `listClips` query (parallel `Promise.all`). Reminder pills use a dashed border in the schedule's persona color (or neutral when no persona is bound) and prefix with 🔔 to distinguish from clip pills (solid borders). Tooltip shows the schedule name. Completed occurrences are excluded by design — the calendar shows what's upcoming.
- **Sort direction + status filter on Clips grid.** Existing sort buttons (go-live / title / status / persona) now toggle direction: click an already-active key to flip between ↑ and ↓. Each key has a sensible default direction on first click (date desc, text asc). New Status dropdown filters to a single distinct value found in the loaded clips. Combined with the existing search, the grid is now actually navigable for a large library.
- **Clips grid search is now as-you-type with a regex toggle.** Matches `CustomerListView` / `CustomerHistoryCard` patterns. Filters client-side over the persona-scoped clip set across id / title / status. Invalid regex shows an inline amber hint; "N of M" count + Clear button when active. No more Enter/blur to trigger refresh.

### Changed

- **Dropped legacy fields from clip import + display.** `external_clip_id`, `keywords`, and `performers` are no longer read from the MasterClipper CSV (new imports write empty strings to those columns) and no longer shown in the Clip Detail modal. The DB columns and `Clip` type are preserved so older imported data isn't lost; you can still see it via direct SQL if needed. The clip-list search dropped the now-empty `keywords LIKE` clause and the import view's expected-columns hint was updated accordingly. Reuse detection on `external_clip_id` continues to fire for legacy rows but will naturally degrade as new imports stop populating it.

## [1.5.1] — 2026-05-21

### Fixed

- **MasterClipper CSV import was unrunnable when any persona was mapped to "skip".** Two stacked bugs in `src/views/Import/MasterClipperImport.tsx`:
  1. The `allMapped` gate guarded `mapping[src] !== ''`, but `''` is the *value of the actual "(skip rows with this persona)" dropdown option*. So picking "skip" on any persona left the Run import button permanently disabled — the symptom Sallie hit. Lifted the `!== ''` check; mapping is always initialized for every distinct source persona on file load, so the only thing the gate needs to guard against is `undefined`.
  2. Even if Run could fire, the loop's `personaCode = mapping[sourcePersona] || null` would have *imported* those rows with `personaCode = null`, not skipped them. Reworked the row resolution: when the source persona is non-empty and explicitly mapped to `''`, the row now increments the `skipped` counter and is left out of the upsert. Empty-persona-in-CSV rows still import with `null` persona (legacy behavior preserved).

### Added

- **Pre-flight import counter.** A small "`N to import · M to skip`" readout next to the Run button on the mapping screen, matching the row resolution above so an all-skips mapping doesn't look broken.

## [1.5.0] — 2026-05-21

### Added

- **Customer sales flow into the Adhoc Income view.** `customer_sales` rows now surface in `src/views/Income/AdhocIncomeView.tsx` alongside typed adhoc entries — same year/month/persona filters, same running total. Sale rows are marked with a 🛒 glyph and show `<customer> — <product>` as the source label and `<quantity> <unit> · <sale notes>` in the note column. Read-only here (no Edit/Delete buttons; the "on customer" hint points back to the customer's history timeline for changes).
- **Implementation is a read-side union, not a copy.** A new `listAdhocUnified(filter)` in `src/data/income.ts` runs both queries with matching year/month/persona predicates, builds a `UnifiedAdhocRow` discriminated union (`source: 'adhoc' | 'sale'`), and sorts by `dateEarned DESC`. Customer sales stay in `customer_sales` as the single source of truth — no schema changes, no duplication, no sync hazard. Editing/deleting a sale on the customer side updates the income view on next render.
- **Reports + Home dashboard totals now include sales.** `totalsForPeriod` adds a `SUM(customer_sales.total_cents)/100` to `adhocTotal` (with the same period + persona filters), so MTD/YTD income figures reflect sales without making them invisible income.

## [1.4.2] — 2026-05-21

### Changed

- **History notes are now editable and deletable** — lifting the audit-only restriction set in 1.3.0 at the user's request. Each note row in the timeline now has **Edit** / **Delete** buttons matching the sale-row UX. Edit reveals an inline textarea (Save / Cancel) bound to the note's body; Delete is two-tap-confirmed via `ConfirmButton` and removes the row along with its inline BLOB attachment. The data layer (`src/data/customerHistory.ts`) gains `updateEntry(id, body)` and `deleteEntry(id)` exports; the module-level comment was rewritten to reflect the new contract. Editing a note touches only the body — attachment metadata and BLOB stay put.

## [1.4.1] — 2026-05-21

### Changed

- **Sale Date is now a date picker** (`<input type="date">`) in `CustomerSaleEditor`. Stitches the picked date with `12:00:00` UTC time so the row sorts cleanly alongside history datetimes and timezone shifts can't bump the displayed day. Sale timeline rows now render date-only (`May 21, 2026`) since the time portion was always meaningless noise; history rows still show full datetime.
- **Customer-list search adds a regex checkbox** and switches to client-side filtering for both substring and regex modes. Filter runs as-you-type now (no more Enter/blur to trigger refresh). Searches across username, real name, UID, and primary email; matches "N of M" count + Clear button + invalid-regex inline amber warning. Persona scoping stays server-side so the fetched dataset stays bounded.

## [1.4.0] — 2026-05-21

Phase 3 of the customer-record expansion: **sales transactions**, interleaved with the history log into one customer timeline. Closes out the three-phase plan started in 1.2.0.

### Added

- **Sales on the customer timeline.** A new **🛒 + Add sale** button on the History card opens an inline composer with: Product (dropdown of unarchived products, shows the default `$X / unit` next to each name), Quantity, Unit price (USD), Total (USD), Date (optional — defaults to now), and a Notes textarea. The three money fields reconcile bidirectionally: edit Quantity or Unit price and Total recalcs; edit Total and Unit price back-solves from `total / quantity` for line-level discounts. Saving lands a row in `customer_sales`.
- **Sales render in the timeline** alongside notes, sorted by date newest-first. Sale rows look like `🛒 Customs · 10 minutes · $50.00` with the customer-supplied notes below. When the user discounted the line, a tiny breadcrumb shows `(($5.00 / minute × 10 = $50.00, adjusted to $40.00))`. **Sales are editable and deletable** (unlike notes, which stay append-only) — Edit pops the inline composer pre-filled, Delete is two-tap-confirmed via the existing `ConfirmButton`.
- **Lifetime sales pill** in the customer editor header (`💖 $X.XX`) shows `SUM(total_cents)` across all sales for the customer; hidden when zero. Refreshes on any add/edit/delete via a parent callback (`onSalesChanged`).
- **Timeline filter** (added per follow-up request): a search input above the timeline filters notes + sale notes + product names. Substring match by default (case-insensitive); a small `regex` checkbox switches to a real `RegExp`. Invalid regex shows an inline amber error; valid filters show "N of M" while active with a Clear button.

### Schema

- New migration `014_customer_sales.sql` adds the `customer_sales` table (id, customer_uid FK CASCADE, product_id FK RESTRICT, sale_date, quantity REAL, unit_price_cents, total_cents, notes, created_at, updated_at) plus an index on `(customer_uid, sale_date DESC)`. `product_id` uses `ON DELETE RESTRICT` so historical sales can never be silently orphaned — archive a product instead of deleting it when it goes out of rotation.

## [1.3.0] — 2026-05-21

Phase 2 of the customer-record expansion: per-customer immutable **history log** with optional inline file attachments. Phase 3 (sales transactions) builds on top of this and lands in 1.4.0.

### Added

- **Customer history card** below the existing Notes section in the customer editor. Composer at the top (textarea + 📎 attach + ➕ Add to history) with a reverse-chronological list of entries below. Each entry shows a timestamp + the body text (newlines preserved) + a clickable 📎 chip for the optional attachment. Footer: *"Audit-only — entries cannot be edited or deleted."*
- **Audit-only by design.** `src/data/customerHistory.ts` deliberately exports only `addEntry`, `addEntryWithAttachment`, `listEntries`, and `downloadAttachment` — no `updateEntry` / `deleteEntry`. The UX contract is enforced at the data layer rather than via UI hiding.
- **Inline BLOB attachments.** Picking a file via the OS dialog stores the bytes directly into `customer_history.attachment_data` as a SQLite BLOB; downloading streams them back out via a save dialog. Files never round-trip through the JS layer — both directions go through new Rust commands (`add_history_entry_with_attachment`, `download_history_attachment`) backed by `rusqlite` for clean BLOB binding. Auto-detected MIME by extension.

### Schema

- New migration `013_customer_history.sql` adds the `customer_history` table (id, customer_uid FK, ts, body, attachment_filename/mime/size, attachment_data BLOB) plus an index on `(customer_uid, ts DESC)`. List queries deliberately exclude the BLOB column to keep page render cheap.

### Tauri command surface

- `history::add_history_entry_with_attachment` — reads the file, inserts the row, returns the new id.
- `history::download_history_attachment` — reads the BLOB by id, writes to a target path.
- 1 new `camel_case_contract` test (`HistoryEntryRef`); total now 13.

### Dependencies

- Added `rusqlite = "0.31"` with the `bundled` SQLite feature. The `tauri-plugin-sql` JSON parameter marshaller doesn't bind raw byte arrays cleanly; rusqlite opens the same `molly.db` file with `busy_timeout(5s)` so writes from both connection paths cooperate via SQLite's WAL.

## [1.2.2] — 2026-05-21

### Added

- **Phone number formatting + validation.** When the customer's country is US, both phone inputs format-as-you-type into the canonical `(XXX) XXX-XXXX` form and tolerate paste of any common variant (`555-123-4567`, `+1 555 123 4567`, `5551234567`, `1-5551234567`, etc. — `formatUSPhone` strips non-digits and drops a leading `1` country code). Numbers with fewer than 10 digits get an amber border and a "10 digits required for a US number." hint below the input. Non-US countries bypass the formatter entirely (free text), since global phone formats vary too widely to coerce reliably. Logic lives in `src/lib/phone.ts`.

## [1.2.1] — 2026-05-21

### Fixed

- **Product price input is now typeable.** Settings → Products price field was `type="number"` + `step="0.01"` + `.toFixed(2)`-on-every-render, which made typing `$20.03` impossible — the buffer got reformatted on every keystroke, and the browser's number-input enforcement only let you increment by penny via the spinner. Switched to uncontrolled `type="text"` with `inputMode="decimal"`, `defaultValue`, on-change parsing into cents, and on-blur normalization back to 2-decimal form. `key={editing.id}` on the row's edit grid ensures defaults pick up the right row when switching.

### Changed

- **State / Province** in the customer's mailing address renders as a dropdown of the 50 US states + DC + 5 USPS state-equivalent territories when `country === 'US'`. For other countries, falls back to the original free-text input.
- **Zip+4** field is hidden when country isn't US (it's a US-specific format). Non-US countries see a single "Postal code" field instead.

## [1.2.0] — 2026-05-21

Phase 1 of a three-phase customer-record expansion. Phase 2 (per-customer immutable history log with file attachments) and Phase 3 (sales transactions backed by the new product pricing) follow.

### Added — Products

- **Per-product price and unit.** Settings → Products gains a Price (USD) input and a Unit field (with a datalist of `minute`, `hour`, `session`, `item`, `set`). The 7 preloaded products get sensible default units on migration (`minute` for Phone/Cam/Customs, `item` for the Physical merch); prices start at $0 — set them in Settings. The product display row now reads e.g. `Customs · $5.00 / minute`.

### Added — Customer record

- **VIP toggle** in the customer editor header. Click the `☆ VIP` pill to mark a customer as VIP; the pill turns gold (⭐ VIP), a matching `⭐ VIP` chip appears next to their persona in the customer list, the editor header gets a ⭐, and the list **sorts VIP customers first**.
- **Primary email selector.** Each of the five email slots gets a radio button. The list-row primary-email picker now follows the user's chosen primary, falling back to the first non-empty slot if the chosen slot is blank.
- **Mailing address.** New card on the customer editor with: Address line 1, Address line 2, City, State / Province, Zip + +4, and a Country dropdown sourced from the full ISO 3166-1 alpha-2 list (US/CA/GB pinned to the top, separator, then alphabetical). Default country is US.
- **Two phone numbers** with per-phone **📱 Mobile** checkbox and a shared "Primary phone" radio.

### Schema

- Migration `012_products_and_customer_fields.sql`: `ALTER TABLE products` adds `price_cents` + `unit`; `ALTER TABLE customers` adds 13 new columns (`vip`, `primary_email_index`, `address1/2`, `city`, `state`, `zip`, `zip4`, `country`, `phone1/2`, `phone1/2_is_mobile`, `primary_phone_index`). Lossless — every column has a default; existing customers come out the other side unchanged.

## [1.1.2] — 2026-05-21

### Fixed

- **Drag-to-reorder kink chips actually works now.** Tauri 2's default window setting `dragDropEnabled: true` was intercepting all HTML5 drag events for native file-drop handling, so chip drag-start never reached the React handlers. Set `dragDropEnabled: false` in `tauri.conf.json`. Also hardened the chip itself: switched the wrapping element from `<span>` to `<div>` (more reliable drag surface), added a visible `⋮⋮` grip handle, gave the chip `userSelect: none`, and set `draggable={false}` plus `onMouseDown` stopPropagation on the × remove button so clicking it doesn't accidentally start a drag.
- **Customer edits no longer vanish when you navigate away.** Two changes:
  - **Debounced auto-save (800ms idle).** Any change to a customer field, chip selection, persona, emails, or notes schedules an auto-save 800ms after you stop interacting. Successive edits collapse into one save.
  - **Save-on-Back.** The ← Back button now flushes any pending changes through `save()` before closing the editor. The explicit **💾 Save now** button is still there for users who want a hard commit; "💾 Saving…" / "✏️ Unsaved — auto-saving…" / "✓ Saved" status reads live next to it.

  Root cause of the data loss: `addCustomer` inserts an empty row into the DB the moment you click "Add customer", and the editor opened on top of that empty row. Without auto-save, typed-but-unsaved fields stayed in component state and were dropped on navigation. Auto-save closes the gap end-to-end.

## [1.1.1] — 2026-05-21

### Added

- **Drag-to-reorder kink chips.** Selected kink chips on the customer editor are now draggable. Grab a chip and drop it onto another to insert before it; the numbered position labels (`1.`, `2.`, …) update live and persist via `customer_kinks.position` on save. Matches MasterClipper's `CategoryChipPicker` reorder UX.
- **Filter input on every Settings taxonomy tab.** Products / Interests / Kinks now have a search box at the top that filters by name *or* description (case-insensitive). Shows "N of M" while filtering; a Clear button resets it. The 349-row Kinks list is now actually navigable.
- **Description preview on Settings rows.** Each row shows its description (when present, currently kinks-only) as a one-line truncated caption below the name.

### Added

- **Customer "Kinks" field.** A third per-customer list alongside Products and Interests, modeled directly on MasterClipper's `CategoryChipPicker` interaction pattern. Molly ships preloaded with 349 curated kinks (Voyeurism, Exhibitionism, Frotteurism, …, through to Dystopian/Fantasy/Supernatural AU), each with a short description shown in the picker dropdown.
- **`KinkChipPicker` component (`src/components/KinkChipPicker.tsx`).** Shows only the *selected* kinks as chips (numbered `1.`, `2.`, … with × remove). A **+ Add kink** button opens a searchable dropdown of the unselected catalog; rows show the name + description, and typing a brand-new name surfaces a sticky "Create kink: '…'" row at the top so you can add on the fly without leaving the editor.
- **Per-customer kink ordering.** `customer_kinks.position` (new column) tracks the order you pick kinks in, mirroring MasterClipper's `clip_categories.position`.
- **Kink count in the customer list row.** The right-side counter cluster now shows "N kinks" alongside the existing product/interest counts.
- **Settings → Kinks.** Reuses the existing `TaxonomySettings` UI; the 349 default rows are immediately editable (rename, recolor, archive, delete) without any one-time import step.

### Schema

- New migration `010_kinks.sql` adds the empty `kinks` (catalog) + `customer_kinks` (join) tables.
- New migration `011_kinks_preload.sql` evolves both: adds `kinks.description`, adds `customer_kinks.position` (with index `customer_kinks_by_pos`), and bulk-inserts the 349 default kinks. Both migrations run automatically on launch; no manual import.

## [1.0.0] — 2026-05-20

### 🎁 First-gift release for Sallie

This is the v1.0.0 milestone — Molly is feature-complete for the use case it was designed for. From here, work is bug-fix + the deferred scope items in `PHASE_8_PARSERS.md`.

### Added

- **Cute sayings banner.** 1000 hand-picked encouragements from `~/Downloads/sayings.md` baked into `src/data/sayings.ts`. Two display variants:
  - **Hero**: gradient card at the top of the Home dashboard with a 💕 emoji + the saying in one of 10 rotating cute display fonts (Pacifico / Caveat / Dancing Script / Sacramento / Indie Flower / Shadows Into Light / Patrick Hand / Kalam / Chewy / Comfortaa) + an `✨ another` button to re-roll.
  - **Compact**: replaces the static "your work, your way 💕" subtitle in the sidebar. Click the saying itself to re-roll.
- **HANDOFF.md** (project architecture map for future developers).
- **DESIGN.md** (UX / theming / persona engine notes).
- **INSTALL.md** (Sallie-friendly Windows install + data-export walkthrough, plus the developer-side dev-import counterpart).
- **PHASE_8_PARSERS.md** (scope doc for the deferred per-site sales-report parsers, modeled on PurpleLife's PurpleImport engine).
- **OUT_OF_SCOPE.md** (Apple Developer ID + Windows EV cert signing intentionally deferred — single-user gift app).

### Changed

- Version bumped to 1.0.0 across `tauri.conf.json`, `Cargo.toml`, `package.json`, and the sidebar footer (which reads from `getVersion()`).
- README, USER_MANUAL refreshed for the 1.0.0 milestone and final feature set.

## [0.7.1] — 2026-05-20

### Added / Changed

- **Race-protected refresh hook + visible loading states.** Extracted `src/lib/useAsyncRefresh.ts` — a small hook that wraps the `useEffect → refresh()` pattern every list view was hand-rolling, adding per-effect-run alive guards (writes from the previous load are suppressed once the user switches persona or deps change) plus a `loading` flag.
- Applied across 14 views: Customers / Clips / Calendar / Promos / AdhocIncome / Expenses / SiteIncomeWizard / Reports / Reminders / MollyHelper / SalesReportImport / RecurringExpenses + the 4 Settings tabs (Personas / Sites / Taxonomy / Platforms / Backup).
- High-traffic list views now show `Loading …` while data is fetching, instead of flashing the misleading "Nothing here yet" empty state.
- `onClose` async refresh handlers (Customers / Clips / Calendar / Promos) now `try/catch` so post-close fetch errors surface instead of being swallowed.

### Quality

- All bugs were from a static code audit, not user-visible incidents — the previous code was technically correct but had latent race windows on persona switch and inconsistent loading vs empty-state UX. Building it into a single hook means future views get the right behavior by default.

## [0.7.0] — 2026-05-20

### Added

- **Phase 7 — Social promotion tracker.**
- Migration `009_social.sql` adds `social_platforms` (Reddit / X / Instagram / TikTok preloaded; editable in Settings → Platforms) and `social_promos` (persona, platform, handle, posted_at, url, title, body, optional clip link, rich-text notes).
- New sidebar entry **📣 Promos** between Molly Helper and Income.
- Promos list with platform / year / month / search filters; click **Open** to launch the post URL via `plugin-opener`.
- Promo editor wizard threading persona → platform → handle → posted-at (datetime-local) → URL → title → body → optional linked clip → Tiptap rich-text notes.
- Settings → Platforms tab with full CRUD (icon emoji + color + short code + sort + archive).
- Reports gains a Promos section: MTD + YTD counts + per-platform bar chart sized by each platform's color.

## [0.6.1] — 2026-05-20

### Fixed

- **Backup Test / size / mtime were all undefined.** The Rust structs returned by `list_backups`, `test_backup`, `export_full_data`, and `save_attachment` were serializing field names as snake_case (`size_bytes`, `has_database`, `modified_at`, `file_count`, `total_bytes`, `relative_path`, …) but the TS callers expected camelCase. That made every Test result claim "no molly.db inside, undefined files, NaN MB unpacked" and every recent-backup row read "· NaN MB". Added `#[serde(rename_all = "camelCase")]` to `BackupRow`, `VerifyResult`, `ExportResult`, and `AttachmentInfo`.
- **Sidebar footer was frozen at "Phase 0 · v0.0.1"** — now pulls the live version from `@tauri-apps/api/app::getVersion()` and reads simply "Molly · v0.6.1".

## [0.6.0] — 2026-05-20

### Added

- **Phase 6 — Sales report importer (v1).** Each site (Clips4Sale, IWantClips, OnlyFans, …) exports a different CSV but they all reduce to "date + amount" rows. Instead of N hard-coded parsers, Molly auto-detects the date and amount columns by header name, allows manual override, totals by month, and upserts into the `income_site` table — same shape the monthly wizard touches.
- **New tab**: Income → **📊 Sales report import**.
- **Generic parser** (`src/lib/salesReport.ts`): header-keyword-based column detection (`date|day|earned|period|sale date|transaction date|earning date` for dates; `payout|net|amount|total|earned|gross|usd|payment` for amounts); robust money parser stripping `$`, commas, and preserving sign; date parser covering ISO, US, EU, `Mon DD YYYY` formats with EOM-safe range checks; per-`(year, month)` aggregation.
- **Wizard UI**: site dropdown → CSV file pick → auto-detected columns (with override) → per-month totals preview showing CSV total vs existing site_income vs what the row will become → **Replace** or **Add** mode → run.
- Unparseable rows are surfaced in an expandable list at the bottom of the preview so the user knows exactly what got skipped and why.

## [0.5.0] — 2026-05-20

### Added

- **Phase 5 — Data round-trip + Auto-update.**
- **Full data export** (`src-tauri/src/export.rs::export_full_data`) zips the entire `app_data_dir` (database + attachments + settings) plus a `manifest.json` (app name, version, exported_at, schema_version, format tag) into `~/Downloads/Molly export/Molly-export-YYYY-MM-DD-HHmmss.zip` (`%USERPROFILE%\Downloads\Molly export\…` on Windows). Re-exporting just makes a new file; old ones are untouched.
- **Settings → Data tab** with **Export everything** button, **Reveal export folder**, last-export readout, **Reveal in Finder**, and a "Sending to Robert? Drop this in our Slack DM" hint card.
- **Dev-only import** (`import_full_export`) reuses `backup::restore_archive`'s safety-pre-import-backup + wipe + unpack flow. Gated by `VITE_MOLLY_DEV=1` at the JS layer so it never appears for the end user.
- **Updater public key generated** — `tauri.conf.json` now ships a real minisign pubkey. Private key lives in `~/.config/molly-secrets/updater.key` (not committed) and is the source for the `TAURI_SIGNING_PRIVATE_KEY` secret CI signs releases with.
- **Settings → Updates tab** with current version (from `@tauri-apps/api/app`), last-checked timestamp, **Check for updates**, **Download v…** action with a progress bar, and an auto-relaunch via `@tauri-apps/plugin-process`. Graceful "couldn't check" panel that points at the GitHub Releases page when no feed is published yet for this version.
- Two new settings tabs (`Data`, `Updates`) — Settings is now Personas / Sites / Products / Interests / **Data** / **Updates** / Backup.

### Changed

- `backup::restore_archive` visibility bumped from `pub(crate)` to `pub` so the export module can reuse it for the dev-import flow.

## [0.4.0] — 2026-05-20

### Added

- **Phase 4 — Income + Expenses + Reports.**
- Migrations `007_income.sql` (`income_adhoc`, `income_site` unique on year+month+site) and `008_expenses.sql` (`expenses`, `expenses_recurring`, unique on `(recurring_id, effective_date)` so materialization is idempotent).
- **Adhoc income** view (`💖 Adhoc income`) with year + month filter, persona scoping, add/edit/delete, total readout. Backfill to any past date for tax prep.
- **Site income wizard** (`🌐 Site income wizard`): pick year + month → wizard walks every site grouped by persona → one dollar field per site → save. Reopenable for any past month. Per-persona subtotals + grand total update live.
- **Expense list + editor** with actual + effective dates, persona, description, note, **receipt attachment** (Tauri-backed copy into `<app_data>/attachments/expenses/<YYYY>/<MM>/<uuid>_<basename>`), and exclude/partial-exclude controls (e.g. "this $100 was $30 personal, $70 business").
- **Attachment field** with Open / Reveal in Finder / Remove via new Rust commands (`save_attachment`, `delete_attachment`, `reveal_attachment`, `open_attachment` in `src-tauri/src/attachments.rs`).
- **Recurring expenses** reusing the Phase 3 Cadence engine: name + amount + persona + anchor + cadence (weekly with day mask / monthly Nth / N days before next month / N days after EOM / every-N-days / daily) + Pause/Resume. Live "Reads as" + next-5-dates preview, just like the schedule wizard.
- **Recurring materializer** runs on launch + every 30 min, walks each active recurring expense from its `last_material` to today, INSERTs into the journal via `INSERT OR IGNORE` (idempotent), then bumps `last_material`.
- **Reports view**: 3 period cards (MTD vs Prior MTD vs YTD) showing income, expenses (net), profit. Income breakdown bars (Adhoc vs Site). Per-site YTD income chart grouped by persona, sized by site color. **Export CSV** button writes a year-stamped report file.
- App.tsx wires `income`, `expenses`, `reports` to real views; placeholder `PlaceholderView` is finally removed.

## [0.3.0] — 2026-05-20

### Added

- **Phase 3 — Scheduling engine + Reminders.**
- Migration `006_schedules.sql` adds `schedules` and `occurrences` tables. Five default schedules pre-seeded per spec: Fan Site Posting CoC/PoA (10 days before next month), Income update (3 days after month end), CoC release (weekly Mon + Thu), PoA release (weekly Wed + Fri).
- **No-cron Cadence engine** (`src/lib/cadence.ts`) modeled after `PurpleTracker/Sources/PurpleTracker/Models/Cadence.swift`. Six cadence kinds — `daily`, `weekly` (with day-of-week mask + everyN for biweekly), `monthly_dom` (clamped to end-of-month), `monthly_days_before_next`, `monthly_days_after_eom`, `every_n_days`. Pure functions: `nextOccurrencesAfter(cadence, from, count)`, `describeCadence(cadence)`, `isCadenceValid(cadence)`.
- **Occurrence materializer** (`src/data/occurrences.ts`) runs on app launch and every 30 minutes, populating occurrences for the next 60 days. Idempotent via `UNIQUE(schedule_id, due_at)` — re-runs no-op.
- **Reminders view** with two tabs: *Reminders* (Overdue / Today / Coming up next 7 days / Recently done) and *Schedules* (list + active toggle + edit + delete).
- **Schedule wizard** with cadence builder, weekday checkbox grid for weekly, three monthly flavors (Nth of month / N days before next month / N days after EOM), and a live "Next 5 dates" preview. No cron strings shown to the user, ever.
- **Satisfying check-off**: tap the circle → persona-tinted confetti burst (`CheckOffBurst` component, CSS-only, no canvas-confetti dep), 10-second **Undo** toast in the bottom-right.
- **Sidebar bell badge** showing combined overdue + today count for the active persona.
- **Home dashboard "today's reminders" widget** at the top, with one-click jump to the Reminders view.

## [0.2.2] — 2026-05-20

### Fixed

- **All database writes were blocked by ACL.** Tauri 2's `sql:default` capability set only grants `load` + `select`; the `execute` permission has to be added explicitly. This silently broke every customer save, site edit, taxonomy add, AND every clip imported via the MasterClipper wizard (which surfaced the error as "Command plugin:sql|execute not allowed by ACL"). Added `sql:allow-load` / `sql:allow-execute` / `sql:allow-select` / `sql:allow-close` to `capabilities/default.json`.

## [0.2.1] — 2026-05-20

### Fixed

- **Importer no longer appears stuck.** Large MasterClipper exports were silently grinding through SELECT+INSERT/UPDATE pairs with no UI feedback, so the screen sat on "⏳ Importing… don't close the app." indefinitely. Now:
  - `upsertClip` does `INSERT OR IGNORE` first and only falls back to a targeted UPDATE if the row already existed (fresh imports cost 1 IPC round-trip instead of 2).
  - The wizard shows a live counter (`Importing… 47 of 543 · 47 added, 0 updated`) plus a progress bar, and yields to the event loop every 25 rows so React can repaint.
  - The post-loop work runs in a `finally` block, so `setStage('done')` always fires — a thrown `logImport` or refresh callback can no longer trap the UI in the "running" state.
  - Per-row errors are captured and shown in an expandable list in the summary (instead of silently inflating the "skipped" count).

## [0.2.0] — 2026-05-20

### Added

- **Phase 2 — Calendar, MasterClipper import, Dashboard.**
- Migration `005_clips.sql` adds `clips` (PK = MasterClipper UID, so re-imports UPSERT cleanly) and a small `clip_imports` audit table for the "recent imports" widget.
- **MasterClipper CSV importer** (`src/views/Import/MasterClipperImport.tsx`): file picker → preview rows → per-source-persona mapping screen → bulk UPSERT → run summary (`{inserted, updated, skipped}`). Reads files via the webview's File API (no Tauri-side fs permission needed). Logs every run to `clip_imports`.
- **RFC 4180 CSV parser** (`src/lib/csv.ts`, ~60 lines) — quoted fields, embedded commas / newlines, CRLF, BOM. Avoids adding papaparse to the bundle.
- **Calendar view** (`src/views/Calendar/CalendarView.tsx`): month grid (6×7) with prev/next/today, persona-colored clip pills per day, click to open `ClipDetail`. Respects the active persona filter.
- **Clip detail modal** (`src/views/Calendar/ClipDetail.tsx`): all imported fields read-only + editable `mollyNotesHtml` (Tiptap) that is preserved across re-imports. Delete is two-tap.
- **Clips list view** with search, sort (`go_live` / `title` / `status` / `persona`), and an inline "📂 Import CSV" button that opens the wizard.
- **Home dashboard** widgets: MTD vs Prior MTD vs YTD vs all-time counts, per-persona breakdown bars, **reuse detection** (same `external_clip_id` OR same title within 14 days), recent-imports log. Filterable by active persona.
- `clipCounts`, `countByPersona`, `detectReuse`, `recentImports` data helpers in `src/data/clips.ts`.

### Changed

- Sidebar `Home` is now the dashboard (replaces the static welcome card).
- App.tsx wires `calendar` / `clips` view keys to real implementations.

## [0.1.0] — 2026-05-20

### Added

- **Phase 1 — Settings, Customers, Molly Helper.** First real feature drop on top of the Phase 0 shell.
- **Settings tabs**: Personas / Sites / Products / Interests / Backup.
- **Personas settings**: rename, redescribe, recolor (5 swatches per persona: primary / secondary / tint / accent / text). Edits live-update the active theme via `onPersonasChanged → refresh`.
- **Sites settings**: full CRUD with per-site color, short code, URL, username, free-form note, sort order, and an optional `loginGroup` flag for shared-login sites (e.g. OnlyFans CoC ↔ PoA). Grouped by persona; respects the active persona filter.
- **Preloaded sites** (per spec): 5 for CoC, 13 for PoA (NiteFlirt has four entries — main + Alice + Taylor + sluttysecrets). OnlyFans rows share `loginGroup = "of-shared"`.
- **Products / Interests settings**: identical CRUD pattern. Defaults preloaded: Phone, Cam, Customs, Physical-Panties/Pantyhose/Shoes Flats/Heels for products; Feet, Pantyhose, Panties, Humiliation for interests.
- **Customer tracker**:
  - UID format `YYYY-MM-DD-#####` (mirrors `MasterClipper/Sources/MasterClipper/Services/IDGeneratorService.swift`, computed in `src/lib/uid.ts`).
  - Fields: username, real name, 5 email slots, persona binding (or unbound for cross-persona contacts), multi-select product chips, multi-select interest chips, **rich-text notes** via Tiptap (StarterKit + Link + Placeholder).
  - List view with search across UID / username / real name and per-persona filter.
  - Detail editor with explicit Save (dirty-tracking) and ConfirmButton-guarded delete.
- **Molly Helper**: persona-grouped grid of clickable site cards. Top border tinted with each site's color; click **Open** to launch via `@tauri-apps/plugin-opener`; **Copy user** copies the saved username to clipboard. Shows `🔗 shared login` hint for sites in a login group.
- **Shared components**: `ColorPicker` (native `<input type="color">` + curated swatch row), `ChipMultiSelect`, `ConfirmButton` (two-tap guard), `RichTextNotes` (Tiptap with persona-themed lite-prose styling).
- **Migrations**: `002_sites.sql`, `003_taxonomy.sql`, `004_customers.sql` wired into the plugin's migration list in `src-tauri/src/lib.rs`.

### Changed

- `state/personas.ts` is now a thin hook over `data/personas.ts` (extracted CRUD), exposing a `refresh()` so persona edits propagate to the switcher immediately.
- App.tsx wires the new SettingsView / CustomerListView / MollyHelper routes; placeholder cards remain for the calendar / clips / income / expenses / reports areas.

## [0.0.1] — 2026-05-20

### Added

- **Phase 0 — Foundation.** Initial scaffold of the Molly app.
- Tauri 2 + React 19 + TypeScript + Tailwind CSS + Vite project layout.
- AI-generated app icon set (`.icns`, `.ico`, full PNG ladder).
- SQLite migration `001_init.sql` with `personas` and `app_settings` tables.
- Three preloaded personas (Curse Of Curves / Princess of Addiction / Sheer Attraction) with primary/secondary/tint/accent/text colors.
- **Persona switcher** in the top bar (`CoC` / `PoA` / `Sa` / `★ All`); the whole UI recolors via CSS custom properties.
- Fixed-width sidebar (240px) with `Ctrl+S` / `⌘+S` toggle. (Avoids `NavigationSplitView` — Tauri uses Flexbox, immune to that AppKit bug, but the convention still matches PhantomLives.)
- **Backup-on-launch service** (Rust port of `Timeliner/Services/BackupService.swift`):
  - Default location `~/Downloads/Molly backup/` (Mac) / `%USERPROFILE%\Downloads\Molly backup\` (Windows).
  - 14-day retention default (0 = keep forever).
  - 5-minute launch debounce.
  - Only trims archives matching `Molly-*.zip`; unrelated files are never touched.
  - **Test** (verify), **Restore** (with mandatory pre-restore safety archive), and **Reveal** actions.
- Settings → Backup UI with toggle, path picker, retention stepper, Run Backup Now, Reveal in Finder/Explorer, recent backups list with per-row Test/Restore/Reveal.
- `install.sh` follows the PhantomLives standard: quit running copy, `ditto --noextattr` to `/Applications/Molly.app`, relaunch (`--no-open` to suppress).
- `build-app.sh` runs `pnpm tauri build` then auto-chains into `install.sh` (`BUILD_ONLY=1` / `--no-install` escape hatches).
- `run-tests.sh` runs `cargo test --lib` against the Rust backend.
- Backup module unit tests: debounce, retention trim (only Molly-prefixed zips), target dir auto-create, listing order, missing database flag.
- GitHub Actions workflow `.github/workflows/release.yml` cross-builds signed `.dmg` and `.exe` on `v*` tag push via `tauri-action`.
- `tauri-plugin-updater` wired to a GitHub Releases `latest.json` endpoint (public key placeholder; replace before signed Phase 5 release).

### Notes

- Out of Phase 0 scope: calendar, MasterClipper import, scheduler/reminders, income, expenses, customers, Molly Helper, reports.
- The updater public key in `tauri.conf.json` is a placeholder — it must be replaced with a real key before publishing a signed update.
