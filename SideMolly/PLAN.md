# SideMolly — Plan

> The outbound counterpart to Molly's bundler. Molly seals a deterministic ZIP
> of approved content into `~/Downloads/Molly bundles/`; SideMolly picks it up,
> verifies it, decomposes the media, helps Robert push each item through
> **edit · process · post**, and finally sends a structured post-bundle back
> to Molly to close the loop.
>
> Single user: Robert (developer / content-operations side). Workbench feel,
> not bedroom feel. Same Tauri 2 stack as Molly so the launch-backup, signed-
> installer, migration, and serde contracts port over directly.

Captured 2026-05-23. Status: **plan only, no code yet.** Use this doc as the
brief when Phase 0 work starts.

---

## 1. 30-second mental model

```
        Molly (Sallie)                      SideMolly (Robert)                 Molly (Sallie)
        ─────────────                       ──────────────────                 ─────────────
        ┌──────────┐                        ┌───────────────────┐               ┌──────────┐
        │ bundle   │   ~/Downloads/         │  ingest +         │  ~/Downloads/ │ ingest   │
        │ wizard   ├───Molly bundles/────▶  │  verify           │  Molly post-  │ post-    │
        │ +        │   <UID>.zip            │  decompose        │  bundles/     │ bundle   │
        │ publish  │                        │  edit / process   │ <UID>-post.zip│ surface  │
        └──────────┘                        │  post             ├───────────────▶ "Posted  │
                                            │  compose report   │               │ to"      │
                                            └───────────────────┘               └──────────┘
```

SideMolly is **stateless about Molly's data**. It reads only what's inside
the bundle ZIP, and writes back via another deterministic ZIP. No cross-app
SQLite handles, no shared schema, no IPC. The two apps evolve independently
as long as the ZIP contracts hold.

---

## 2. Repo placement & cross-cutting standards

Top-level PhantomLives subproject. Mirrors Molly's layout exactly so the
muscle memory transfers.

```
SideMolly/
├── src/                              # React 19 + TS + Tailwind
├── src-tauri/                        # Rust + Tauri 2 + migrations
├── build-app.sh                      # build → install.sh → relaunch
├── install.sh                        # ditto --noextattr → /Applications/SideMolly.app
├── run-tests.sh                      # cargo + vitest
├── .github/workflows/release-sidemolly.yml
├── README.md  USER_MANUAL.md  HANDOFF.md  DESIGN.md  CHANGELOG.md
└── PLAN.md                           # this file (kept until shipped, then archived)
```

Compliance with `CLAUDE.md`:

- **Default output location:** `~/Downloads/SideMolly/` (created on demand)
- **Auto-backup-on-launch:** `~/Downloads/SideMolly backup/` — 14-day retention,
  5-min debounce, full Settings → Backup UI (toggle, retention stepper, Run
  Backup Now, Reveal, Recent list with Test / Restore / Reveal, last-backup
  readout, status line). Reference: `Timeliner/Sources/Timeliner/Services/BackupService.swift`.
- **Sidebar layout:** plain `HStack` with fixed-width 240px sidebar.
  **Never** `NavigationSplitView` (per the load-bearing CLAUDE.md guidance).
  Toggleable with ⌘+S / Ctrl+S.
- **`install.sh` + `build-app.sh` chain:** `build-app.sh` ends with the
  auto-install block; `install.sh` does quit → ditto-replace → relaunch with
  `--no-open` and `--no-install` opt-outs. Per-session permissions block
  added to `.claude/settings.local.json`.
- **Release-hygiene rules:** every change bumps version (script + docs +
  in-code constant), adds CHANGELOG entry, updates affected docs, updates
  or adds tests.

App data: `~/Library/Application Support/com.phantomlives.sidemolly/` (Mac)
and `%APPDATA%\com.phantomlives.sidemolly\` (Windows).

---

## 3. Architecture

| Layer | Stack |
|---|---|
| Frontend | React 19 + TypeScript + Vite + Tailwind. Reuse Molly patterns: typed `data/<entity>.ts` SQL wrappers; `useAsyncRefresh` race-safe loader; `ConfirmButton` two-tap delete; `markdownLite` for in-app manual; emoji icons (no library). |
| Backend | Rust via Tauri 2. Every cross-boundary struct gets `#[serde(rename_all = "camelCase")]` + a `camel_case_contract` cargo test, exactly like Molly. |
| DB | SQLite via `tauri-plugin-sql`. Own DB at `app_data/sidemolly.db`. No connection to Molly's DB ever. |
| External | Bundled `ffmpeg` (override allowed in Settings); bundled `whisper.cpp` with optional Apple-MLX `transcribe` PATH resolution on Mac; bundled `pyannote`-equivalent diarizer (Phase 5 risk — see §11). |
| Updater | `tauri-plugin-updater` against a `latest.json` on the GitHub releases page, signed with a minisign key. Same pattern as Molly. |

---

## 4. Bundle contract (Molly → SideMolly)

Each published Molly bundle = a deterministic two-layer ZIP at
`~/Downloads/Molly bundles/<UID>.zip`.

```
<UID>.zip                                (outer)
├── <UID>-inner.zip                      (inner — MS-DOS epoch entries)
│   ├── info.md                          (human-readable summary)
│   ├── Molly.log                        (technical build log; KEY: VALUE)
│   ├── Audio/<file>                     (Content + audio description)
│   ├── Video/00001_<orig>.<ext>         (Content/Custom, position-prefixed)
│   ├── Photos/00001_<orig>.<ext>        (Content/Custom, position-prefixed)
│   └── FanSite/DD_NN_<orig>.<ext>       (FanSite, day_NN-position prefix)
├── manifest.json                        (NEW — see §5; Molly PR)
└── hashes.json                          (bundleUid + innerZip{name,sha256,bytes} + files[{path,sha256}])
```

Three flavors:

- **Content** — title + persona + description (text or audio) + categories + media + go-live date
- **Custom** — recipient + delivery platform (site OR URL) + price (or `handledInPlatform`) + media
- **FanSite** — full calendar month, per-day messages + files

SideMolly **always verifies** the bundle on ingest:

1. Open outer ZIP, list entries, read `hashes.json`.
2. Hash inner ZIP bytes → must equal `innerZip.sha256`.
3. For every entry inside the inner ZIP: re-hash → must equal `files[i].sha256`.
4. Surface `verify_status` as `pending` / `verified` / `failed` (with a
   `verify_error` field detailing the divergent path). Failed bundles still
   show in the Inbox; user can re-import after re-publishing from Molly.

---

## 5. New: `manifest.json` (small Molly PR)

The semantic data Molly already has lives in `info.md` (Markdown — brittle to
parse) and `Molly.log` (line-based — parseable but format-coupled). To give
SideMolly a stable contract we add a structured JSON sibling.

**Schema** (camelCase, every key always present even if empty):

```json
{
  "manifestVersion": 1,
  "bundleUid": "2026-05-22-0001",
  "bundleType": "content",
  "personaCode": "CoC",
  "title": "Mid-Month Drop",
  "contentDate": "2026-05-22",
  "goLiveDate": "2026-05-29",
  "specialInstructions": "...",
  "description": {
    "mode": "text",
    "text": "Hello there",
    "audioPath": null
  },
  "categories": ["BBW", "STUFFING", "SOLO"],
  "delivery": {
    "kind": null,
    "siteName": null,
    "url": null,
    "recipient": "",
    "priceCents": null,
    "handledInPlatform": false
  },
  "fanSite": {
    "year": null,
    "month": null,
    "days": []
  },
  "files": [
    { "kind": "image", "originalName": "photo1.jpg", "inZipPath": "Photos/00001_photo1.jpg", "position": 1, "fansiteDayOfMonth": null, "sha256": "..." },
    { "kind": "video", "originalName": "clip.mp4",   "inZipPath": "Video/00001_clip.mp4",    "position": 1, "fansiteDayOfMonth": null, "sha256": "..." }
  ],
  "publishedAt": "2026-05-22T03:00:00Z"
}
```

**Implementation in Molly:**

- New function in `src-tauri/src/bundle_zip.rs`:
  `fn render_manifest_json(s: &BundleSnapshot) -> Result<Vec<u8>, BundleError>`
- Composes from the existing `BundleSnapshot` — no new data; just structured
  re-emission.
- Written into the outer ZIP **after** `<UID>-inner.zip` and **before**
  `hashes.json`, with `last_modified_time(zip::DateTime::default())` so the
  outer SHA stays deterministic.
- `hashes.json` schema unchanged (manifest.json is a top-level outer-ZIP
  entry, not an inner one).
- New test in `bundle_zip.rs::tests`: same-snapshot composes byte-identical
  manifest.json; round-trip parse asserts every field.

**Forward-compat:** SideMolly **prefers** `manifest.json` when present.
For bundles published by pre-PR Molly versions, SideMolly **falls back to
parsing `Molly.log`** (line-based `KEY: VALUE`). Both paths normalize to one
internal `BundleManifest` struct so the rest of SideMolly never branches.

---

## 6. Data model (initial migrations)

Locked-set for migrations `001`–`009`. Add migrations one-per-feature after
that; never edit a shipped migration.

| Migration | Tables / columns |
|---|---|
| 001_init.sql | `app_settings` (key/value), `schema_version` |
| 002_bundles.sql | `bundles` — uid PK, bundle_type, persona_code, title, source_zip_path, ingested_at, verify_status, verify_error, manifest_json (BLOB), bundle_state (`new`/`in_progress`/`shipped`/`archived`) |
| 003_bundle_files.sql | `bundle_files` — bundle_uid FK, in_zip_path, original_name, kind, position, fansite_day_of_month, working_path, sha256, thumbnail_path |
| 004_processed_files.sql | `processed_files` — bundle_file_id FK, op_kind (`trim`/`transcode`/`watermark`/`strip_rename`), output_path, output_sha256, params_json, created_at |
| 005_transcripts.sql | `transcripts` — keyed on source file sha256, language, model, engine, has_diarization, text_path, srt_path, json_path, created_at |
| 006_posting_targets.sql | `posting_targets` — name, url_template, persona_code (nullable), color, icon, position, kind (`content`/`custom`/`fansite`/`any`) |
| 007_bundle_postings.sql | `bundle_postings` — bundle_uid FK, target_id FK, state (`pending`/`scheduled`/`posted`/`skipped`), posted_at, posted_url, body_override, notes |
| 008_dropbox.sql | `dropbox_settings` (root_path, template), `dropbox_copies` (bundle_file_id FK, dropbox_path, copied_at, sha256_verified) |
| 009_jobs.sql | `jobs` (job_kind, payload_json, status, attempts, next_run_at) + `job_runs` (job_id FK, started_at, ended_at, exit_code, log_path) — same shape as Molly's Phase 12 background jobs. |

`watermark_profiles` deferred to Phase 3 (when images land) and shipped as
migration 010.

---

## 7. UI surface

```
📥  Inbox             ← list of bundles, persona chip, verify badge, state pill
🎬  Bundle workspace  ← per-bundle route /bundle/:uid
    ├─ Overview      ← parsed manifest, file tree, source ZIP path
    ├─ Files         ← per-file ops launcher (open external editor, generate thumbnail)
    ├─ Edit          ← video trim/transcode/watermark/transcribe · image watermark/strip/rename
    ├─ Distribute    ← Dropbox copy controls + dry-run preview
    └─ Post          ← runner that matches bundle.bundleType (see §8)
📅  FanSite Runner    ← cross-bundle calendar of all in-progress FanSite months
🛠  Jobs              ← async queue: pending / running / done / failed + logs
⚙️  Settings          ← Watermarks · Dropbox · Platforms · Watched folder · Transcription · FFmpeg · Updates · Backup · Theme (persona-recolor toggle)
💌  Manual            ← in-app USER_MANUAL.md (markdownLite parser, ported from Molly)
```

**Persona theming:** default **quiet** — color chips only on bundle rows /
workspace header. A `Settings → Theme → "Recolor UI per active bundle"`
checkbox flips the full Molly-style recolor on for users who want it.

---

## 8. Three post runners

Routed automatically by `bundle.bundleType` in the workspace **Post** tab.
All three share the same primitives: checklist state in `bundle_postings`,
clipboard, browser launcher, per-target URL templates from `posting_targets`.

### 8.1 🎬 Content Post Runner

Multi-platform fan-out. Grid of per-platform cards; each card stages the
right body/files for that platform and tracks posting state.

```
┌─ 2026-05-22-0001 · CoC · "Mid-Month Drop"  ─────────────────┐
│  Description …  Categories: BBW · STUFFING · SOLO            │
│  1 video · 4 photos · 1 transcript                           │
├─ Per-platform targets ──────────────────────────────────────┤
│  ┌─ C4S Store     ─ pending     ┌─ IWC          ─ pending   │
│  │ 📋 Title        🚀 Open       │ 📋 Title       🚀 Open    │
│  │ 📋 Categories   ✓  Posted     │ 📋 Tags        ✓  Posted  │
│  │ 📁 Files (1v·4p)              │ 📁 Files                  │
│  │ [body override field]         │ [override]                │
│  │ Notes: …                       │ Notes: …                 │
│  └──────────────────────────────└───────────────────────────┘
│  ┌─ OnlyFans      ─ posted      ┌─ ManyVids     ─ skipped   │
│  …                                                           │
└──────────────────────────────────────────────────────────────┘
```

- Per-platform body override surfaces the bundle's title/description but
  lets Robert tailor it (X 280-char limit, Reddit title length, IG caption).
- File set per platform pulls from `processed_files` (e.g. watermarked-1080
  for C4S, watermarked-vertical-9:16 for Reels) with a fallback to the raw
  bundle file.
- "✓ Mark posted" captures the posted URL + timestamp into `bundle_postings`.
- Skipped is a first-class state — not every platform applies to every bundle.

### 8.2 🎁 Custom Post Runner

One-to-one delivery. Single card; no fan-out.

```
┌─ 2026-05-22-0014 · PoA · "@username custom 5min"  ──┐
│  Recipient:  @username                                │
│  Delivery:   C4S Studio messages                      │
│  Price:      $49.00  ◯ handled-in-platform            │
├──────────────────────────────────────────────────────┤
│  📋 Copy recipient handle                              │
│  📋 Copy delivery message                              │
│  📁 Reveal files (processed/watermarked)               │
│  🚀 Open delivery platform                             │
│  ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ─    │
│  Payment received via: ◉ C4S ◯ Tip ◯ Other            │
│  Delivered: ✓ at 2026-05-23 14:22                      │
│  Notes: …                                              │
└──────────────────────────────────────────────────────┘
```

- Payment surface mirrors Molly's Custom-bundle wizard (`handledInPlatform`
  vs `priceCents`) — payment-channel detail is captured here.
- One row in `bundle_postings` (target = the resolved delivery platform).

### 8.3 📅 FanSite Post Runner

Day-by-day calendar walk for FanSite bundles. Essentially Custom Runner × N
days, sequenced by `dayOfMonth`.

```
   May 2026 · Sa · "FanSite May"

   Mon  Tue  Wed  Thu  Fri  Sat  Sun
                   01✓  02✓  03✓  04✓
   05✓  06✓  07✓  08↻  09•  10•  11•
   12•  13•  14•  15•  16•  17•  18•
   ...

  ↻ today    • upcoming    ✓ posted

  ── Day 09 ───────────────────────────────────
  Message:   "let's do something fun today 💕"
  Files (3): photo-01.jpg · photo-02.jpg · clip.mp4
  📋 Copy message    📁 Reveal files    🚀 Open fan site
  ✓ Mark posted     ⏭  Skip day
```

- Today highlighted; advance-on-post jumps to next pending day.
- Cross-bundle 📅 **FanSite Runner** sidebar tab gives an "all months in
  flight" overview when multiple FanSite bundles are open.

### 8.5 🎞 Auto-Assembly pipeline (Phase 4.5)

A one-click action on the Bundle workspace's **Edit** tab that takes every
video in the bundle and produces a single master MP4 with title card,
watermarks, voice-enhanced audio, and cross-dissolves between every clip.

```
┌─ master.mp4 timeline (durations approximate) ─────────────────────────────────┐
│                                                                                │
│ ┌── 10s ──┐ 1s┌── v₁ ──┐ 1s┌── v₂ ──┐ 1s        1s┌── v_N ──┐ 1s              │
│ │ TITLE   │xf│ video 1 │xf│ video 2 │xf  ...    xf│ video N │ → fade-to-black │
│ │ + persona│  │watermark│  │watermark│             │watermark│                  │
│ │ (black) │  │+ voice  │  │+ voice  │             │+ voice  │                  │
│ └─────────┘  └─────────┘  └─────────┘             └─────────┘                  │
│                                                                                │
│  Title card has 1.0s fade-in and 1.0s fade-out bookends (total 10s).          │
│  Every transition is a 1.0s xfade (FFmpeg `xfade=transition=fade:duration=1`).│
│  Master ends with an xfade-to-black so the last clip doesn't hard-cut.        │
└───────────────────────────────────────────────────────────────────────────────┘
```

**Job decomposition.** The pipeline is **not** one giant FFmpeg invocation
— it's a chain of small jobs the existing Jobs queue runs sequentially,
each producing an intermediate file that lands in `processed_files` so
individual steps are retryable and individually inspectable:

```
auto_assemble(bundleUid) {
  Job 1            render_title_card(persona, title)         → app_data/work/<UID>/auto/title.mp4
  Job 2…N+1        process_video_i(source_i, persona)        → app_data/work/<UID>/auto/v{i}.mp4
                     ├─ normalize to 1920×1080 @ 30fps, AAC 48kHz stereo
                     ├─ extract audio → DeepFilterNet voice-isolation
                     ├─ FFmpeg chain: loudnorm + acompressor + equalizer (vocal warmth)
                     └─ stamp watermark: PaperDaisy.ttf, 20% opacity, lower-right,
                        text = persona's `watermarkName` (Settings; default no-spaces full name)
  Job N+2          assemble_master(title.mp4, v1.mp4, …, vN.mp4)
                     → app_data/work/<UID>/auto/master.mp4
                     ├─ FFmpeg xfade chain, transition=fade, duration=1.0s
                     └─ final 1.0s xfade to color=black at end
}
```

**Normalization is mandatory.** FFmpeg's `xfade` requires every input to
match resolution / fps / pixel format / sample rate. Step 2's first sub-op
re-encodes each input to a canonical profile so step N+2's xfade graph
just works:

- Container: MP4 / H.264 high profile / yuv420p / 30 fps / 1920×1080
- Audio: AAC LC / 48 kHz / stereo / 192 kbps
- Source aspect ratio preserved via letterbox (black bars), not cropped.

Configurable in `Settings → Auto-Assembly`: target resolution, fps,
cross-dissolve duration, title duration, audio bitrate, persona
watermark text (default = `watermarkName` field per persona).

**Persona watermark + title text** uses the **`watermarkName`** field on
each persona row in `app_settings.personas` (seeded from the bundle
manifest's `personaCode` via a default mapping):

| `personaCode` | default `watermarkName` |
|---|---|
| CoC | CurseOfCurves |
| PoA | PrincessOfAddiction |
| Sa | SheerAttraction |

Robert can override per persona in Settings. The text is rendered with
the commercial Paper Daisy font shipped in
`src-tauri/resources/fonts/PaperDaisy.ttf` (see §15 for licensing).

**Voice processing chain** runs on each video's audio track before the
clip is reassembled:

```
extract_audio(vᵢ_normalized.mp4)
  → DeepFilterNet ONNX (denoise + voice isolation)
  → ffmpeg -af "loudnorm=I=-16:TP=-1.5:LRA=11,acompressor=threshold=-18dB:ratio=3:attack=5:release=50,equalizer=f=200:t=q:w=1.0:g=2,equalizer=f=3000:t=q:w=1.0:g=2.5"
  → remux into vᵢ_processed.mp4
```

Loudnorm targets podcast-grade -16 LUFS (good baseline for OF / C4S /
fan-site web playback). Compressor + 200Hz and 3kHz EQ bumps add vocal
warmth + presence without sounding processed.

**Watermark filter** (FFmpeg drawtext):

```
drawtext=fontfile='PaperDaisy.ttf':text='CurseOfCurves':
  fontsize=h*0.04:fontcolor=white@0.20:
  x=w-tw-h*0.025:y=h-th-h*0.025
```

20% opacity (`@0.20`), positioned lower-right with a margin of ~2.5% of
frame height. Font size auto-scales to ~4% of frame height so it reads
the same on 720p and 1080p output.

**Title card** is rendered as a 10-second clip:

```
ffmpeg -f lavfi -i color=black:size=1920x1080:rate=30:duration=10 \
       -vf "drawtext=fontfile='PaperDaisy.ttf':text='<title>':
              fontsize=h*0.08:fontcolor=white:x=(w-tw)/2:y=(h/2)-th-h*0.01,
            drawtext=fontfile='PaperDaisy.ttf':text='<personaWatermarkName>':
              fontsize=h*0.05:fontcolor=white@0.85:x=(w-tw)/2:y=(h/2)+h*0.01,
            fade=in:0:30,fade=out:240:30" \
       -c:v libx264 -pix_fmt yuv420p -t 10 title.mp4
```

- Title (8% of frame height) above the vertical center.
- Persona watermark name (5% of frame height, 85% opacity) below.
- 1.0s fade-in (frames 0..30 @ 30fps) and 1.0s fade-out (frames 240..270).
- No audio track on the title card (silent intro).

**Trigger surfaces.**

1. **Bundle workspace → Edit tab → "🎞 Auto-assemble"** button: kicks off
   the full pipeline; progress visible in 🛠 Jobs.
2. **Auto-assemble on ingest** (off by default): Setting toggle that
   queues the pipeline automatically when a bundle finishes verification.
3. **Re-assemble**: re-runs only the steps whose inputs changed (Jobs
   queue tracks input shas in `job_runs.payload_json`).

**Master file destination.** Lives at
`app_data/work/<UID>/auto/master.mp4` until Robert sends it to Dropbox
via Phase 6 (template `{uid}_{persona}_{title}/master.mp4`). Available
as a posting candidate in each runner's "Files used" picker.

**Out of scope for Phase 4.5** (open follow-ups, see §13):

- Per-platform variants of the master (vertical 9:16 for IG Reels, 1:1
  for grid posts) — Phase 4.5 produces one landscape 16:9 master.
- Custom title-card backgrounds or animations beyond fade-in/out.
- Music bed or background-track support.
- Color grading / LUTs.

---

## 9. Post-bundle return trip

SideMolly composes a deterministic ZIP back to Molly when work on a bundle
finalises. Same two-layer pattern as Molly's outbound; Molly auto-watches
the drop folder.

### 9.1 Layout

```
<UID>-post.zip                                    (outer)
├── <UID>-post-inner.zip                          (inner — MS-DOS epoch)
│   ├── report.json                               (structured outcomes)
│   ├── notes.md                                  (Robert's freeform notes)
│   └── artifacts/
│       ├── thumbnails/00001_clip.jpg             (Phase 11 payload — locked in)
│       └── transcripts/00001_clip.srt            (Phase 11 payload — locked in)
│       └── transcripts/00001_clip.txt
└── hashes.json
```

Determinism mirrors Molly's `bundle_zip.rs` exactly: MS-DOS epoch on every
entry, fixed entry order, BTreeMap-equivalent serialization for hashes.

### 9.2 `report.json` schema

```json
{
  "reportVersion": 1,
  "bundleUid": "2026-05-22-0001",
  "bundleType": "content",
  "personaCode": "CoC",
  "reportComposedAt": "2026-05-25T18:42:00Z",
  "bundleState": "shipped",
  "targets": [
    {
      "targetId": "c4s-store",
      "targetName": "Clips4Sale Store",
      "state": "posted",
      "postedAt": "2026-05-23T14:22:00Z",
      "postedUrl": "https://...",
      "bodyOverride": "...",
      "filesUsed": ["Video/00001_clip-1080.mp4", "Photos/00001_thumb.jpg"],
      "notes": "..."
    }
  ],
  "bundleLevelNotes": "..."
}
```

Notes on what is **not** in the report (per locked-in decisions):

- No `production.dropboxPaths` — deferred. SideMolly keeps Dropbox state
  local; Molly doesn't need to know.
- No processed-file SHA list — deferred. Not enough payoff in Molly v1.

### 9.3 Drop location

`~/Downloads/Molly post-bundles/` — sibling to `~/Downloads/Molly bundles/`.
Both apps treat the path as a setting (default convention).

### 9.4 Trigger

**Both auto and manual:**

- **Auto-compose** when every target in `bundle_postings` reaches `posted`
  or `skipped` AND `bundle_state` flips to `shipped`. Compose runs inside a
  job (visible in 🛠 Jobs). UI shows a 5-second undo banner; tapping undo
  reverts the bundle to `in_progress` and deletes the in-flight ZIP.
- **Manual "📤 Send to Molly"** button in the Bundle workspace header,
  always available. Composes a partial-state report (targets pending/
  scheduled allowed). Useful for in-progress check-ins.

Re-composing for the same UID overwrites the previous `<UID>-post.zip`
atomically (`.tmp` + rename). Molly's ingest is idempotent on `bundleUid`.

### 9.5 Molly-side changes

Separate, smaller Molly PR (shipped jointly with SideMolly Phase 11):

- New migration `025_bundle_postings.sql`:
  `bundle_postings(bundle_uid FK, target_name, target_id_external, state,
  posted_at, posted_url, body_override, notes)` +
  `bundle_post_reports(bundle_uid FK, ingested_at, source_zip_sha256,
  raw_report_json BLOB)`.
- New Rust module `src-tauri/src/post_bundle_ingest.rs` — verify hashes,
  parse report.json, upsert postings, optionally flip `bundles.state` to
  `shipped`.
- New launch-time + every-30-min watcher: scan
  `~/Downloads/Molly post-bundles/` for new ZIPs (notify crate, debounced;
  same lifecycle as the existing background-jobs scheduler).
- Bundle detail view gets a **"Posted to"** section: per-target rows with
  URL + timestamp + notes + body-override viewer.
- **Deferred** (separate future Molly phase): auto-derive `promos` from
  Content posts; auto-derive `customer_sales` from Custom deliveries.
  v1 = record outcomes only.

---

## 10. Rust backend modules

| Module | Responsibility |
|---|---|
| `bundle_io.rs` | Open outer ZIP, list entries, re-hash everything, validate against `hashes.json`. Returns `ValidatedBundle { manifest_bytes, files: Vec<InZipFile> }`. |
| `manifest.rs` | Prefer `manifest.json` (Phase 1 — JSON parse). Fall back to parsing `Molly.log` (line-based `KEY: VALUE` reader). Both normalize to one internal `BundleManifest` struct used everywhere else. |
| `extract.rs` | Pull inner ZIP contents to `app_data/work/<UID>/`. Idempotent on re-import (skip if `sha256` matches). |
| `ffmpeg.rs` | Async runner: trim, transcode, watermark, thumbnail. Bundled binary; Settings override for system path. Output progress events to the Jobs panel. |
| `image.rs` | Watermark stamp (`image` + `imageproc` crates), EXIF strip, deterministic rename. |
| `transcribe.rs` | Engine resolver — MLX `transcribe` if Mac + on PATH, else bundled whisper.cpp. Diarization (Phase 5 risk — see §11). Outputs `.txt` + `.srt` + `.json` (word timings). |
| `dropbox.rs` | Local-folder copy with template resolution. Idempotent (skip-if-same-sha + reverify-on-each-copy). Never touches the Dropbox HTTP API. |
| `posting.rs` | CRUD on `bundle_postings`, clipboard, URL open via `tauri-plugin-opener`. |
| `post_bundle.rs` | Compose the post-bundle ZIP. Deterministic build (MS-DOS epoch, fixed entry order, BTreeMap-eq hashes.json). Trigger from auto-finalize or manual button. |
| `watch.rs` | `notify` crate watcher on the configured bundle-watch dir. Debounced; queued through Jobs so a flood of file events doesn't thrash the UI. |
| `backup.rs` | Per CLAUDE.md launch-time backup standard. Required Settings → Backup UI: toggle / retention / Run Now / Reveal / Recent (Test/Restore/Reveal) / last-backup readout / status line. |
| `fsutil.rs` | `~/Downloads/SideMolly/` resolution + Finder/Explorer reveal. |
| `jobs.rs` | Generic async queue (matches Molly's Phase 12 background_jobs pattern). Powers ffmpeg / transcribe / dropbox-copy / watch / post-bundle compose. |

All cross-boundary structs use `#[serde(rename_all = "camelCase")]` and are
covered by a `camel_case_contract` cargo test in `lib.rs`.

---

## 11. Phase plan

| Phase | Scope | Ships |
|---|---|---|
| **0** | Tauri scaffold + app shell + sidebar (HStack 240px) + Settings skeleton + backup-on-launch + CI release pipeline + `build-app.sh` + `install.sh`. | Installable empty app. |
| **1** | Bundle ingest: watched folder + drag-drop + verify against `hashes.json` + extract inner ZIP + Inbox + Overview. **Parse-Molly.log fallback path lands here** so SideMolly works against today's bundles immediately. | Drop a Molly bundle, see it parsed + verified. |
| **2** | **Molly PR:** add `manifest.json` to bundle output. SideMolly prefers it when present. Backward-compat test ensures Molly.log fallback still passes for fixtures without manifest.json. | Forward bundles use the JSON contract. |
| **3** | Per-bundle file workspace + image ops: watermark stamping + EXIF strip + rename. Watermark profile editor in Settings (per-persona). | Image side fully usable. |
| **4** | Video ops via FFmpeg: trim, transcode, watermark, thumbnail. Async via Jobs queue. Built-in preset library (general-purpose; per-platform presets deferred). | Video side fully usable. |
| **4.5** | **Auto-Assembly pipeline** (see §8.5). One-click compile of all bundle videos into a master MP4: 10s title card → 1.0s cross-dissolve → each video (resolution/fps-normalized + watermarked + voice-isolated + vocal-enhanced via DeepFilterNet + FFmpeg chain) chained by 1.0s cross-dissolves → 1.0s fade to black at end. Decomposes into per-step jobs in the Jobs queue. | One-click "make me the master cut." |
| **5** | Transcription: MLX → whisper.cpp engine resolver, **diarization output** (`.txt` + `.srt` + `.json` with word-level timestamps + speaker turns). **Risk:** diarization on bundled whisper.cpp typically needs an extra component (pyannote-style). If cross-platform diarization is too heavy, fall back to flat-transcript + word-timestamps in Phase 5 and ship diarization in 5.1. | Audio + video transcribable. |
| **6** | Dropbox local-folder copy: flat `{uid}_{persona}_{title}/` template default, configurable in Settings. Dry-run preview before push. Idempotent (skip-if-same-sha + verify-on-write). | Production files routed automatically. |
| **7** | Posting primitives: `bundle_postings` CRUD + clipboard + URL launcher + Settings → Platforms editor (own list, not Molly's). | Per-bundle checklist working but no flavor-specific UI yet. |
| **8** | 🎬 **Content Post Runner** — per-platform card grid, body overrides, processed-file selection per platform. | Multi-platform fan-out posting. |
| **9** | 🎁 **Custom Post Runner** — single delivery card, payment-channel detail. | Custom-bundle delivery posting. |
| **10** | 📅 **FanSite Post Runner** — day-by-day calendar + advance-on-post. Cross-bundle sidebar tab. | Fan-site month walk-through. |
| **11** | 📤 **Post-bundle composition + Molly ingest** — joint SideMolly + Molly release. SideMolly writes `<UID>-post.zip`; Molly ingests, surfaces "Posted to" section in Bundle detail. Auto on `shipped` (with undo) + manual button. Thumbnails + transcripts in `artifacts/`. | Round-trip closed. |
| **12** | 🛠 Jobs panel: async queue UI with logs, pause, retry. Surfaces every long-running op from Phase 4–6 and Phase 11 composition. | Long ops observable. |

Each phase: bump version, CHANGELOG entry, README/USER_MANUAL updates,
new cargo+vitest tests, in-code version constant. Same hygiene rules as
Molly.

---

## 12. Locked-in design decisions

Every decision captured during the planning conversation, for the record:

| # | Decision | Choice |
|---|---|---|
| 1 | Name (no collision with Molly's "Molly Helper" tab) | **SideMolly** |
| 2 | Purpose | Extract + process Molly bundles for video edit / image processing / posting |
| 3 | Primary user | Robert (developer / operator) |
| 4 | Platform | macOS + Windows via Tauri 2 (same stack as Molly) |
| 5 | Video work | Built-in lightweight ops (trim/transcode/watermark) + thumbnail generation + extract & hand off to external editor + **transcription** |
| 6 | Image work | Watermark stamping + metadata strip + rename |
| 7 | Posting | Per-bundle checklist + clipboard + browser launcher + FanSite-day calendar runner + Dropbox file copy |
| 8 | Bundle ingest | Watched folder + drag-and-drop (both) |
| 9 | Bundle metadata source | Prefer `manifest.json` (new Molly PR); fall back to `Molly.log` parse |
| 10 | Transcription engine | Use PhantomLives `transcribe/` (MLX) if present; else bundled whisper.cpp |
| 11 | Dropbox approach | Local Dropbox folder (no API) |
| 12 | Posting platform source | SideMolly maintains its own platform list (independent of Molly) |
| 13 | Three flavor-specific post runners | Content + Custom + FanSite, routed by `bundle.bundleType` |
| 14 | Post-bundle return trip | Yes — `<UID>-post.zip` to `~/Downloads/Molly post-bundles/` |
| 15 | Post-bundle trigger | Auto on `shipped` (5s undo banner) **and** manual "📤 Send to Molly" button |
| 16 | Post-bundle artifacts | `report.json` + `notes.md` + `artifacts/thumbnails/` + `artifacts/transcripts/` |
| 17 | Molly's response to post-bundle ingest | v1: record outcomes only (URLs, timestamps, notes). Auto-Promos / Auto-CustomerSales deferred. |
| 18 | Persona theming intensity | Quiet chips by default, with a Settings toggle for full-recolor mode |
| 19 | FFmpeg distribution | Bundle static build per platform, allow Settings override to system install |
| 20 | Transcription scope | Diarization (speaker turns) + word-level timestamps + flat `.txt` + `.srt` |
| 21 | Dropbox path template default | Flat `{uid}_{persona}_{title}/` |
| 22 | Auto-Assembly pipeline | Phase 4.5: title (10s, fade-in/out 1s) → 1s xfade → each video (1920×1080 @ 30fps, watermarked, voice-enhanced) chained by 1s xfades → final xfade to black |
| 23 | Watermark / title font | Commercial **Paper Daisy** (purchased 2026-05-23 from maja.mint). Shipped as `src-tauri/resources/fonts/PaperDaisy.ttf` in SideMolly; replaces the demo TTF in Molly. See §15. |
| 24 | Persona watermark text | Full name with no spaces — `CurseOfCurves`, `PrincessOfAddiction`, `SheerAttraction`. Stored as `personas.watermarkName`; per-persona override in Settings. |
| 25 | Voice processing engine | DeepFilterNet (bundled ONNX, ~30MB) for isolation/denoise → FFmpeg chain (`loudnorm` -16 LUFS + `acompressor` + 200Hz/3kHz `equalizer`) for vocal warmth + level |
| 26 | Cross-dissolve + title fade durations | 1.0s everywhere — fades-in/out on title card, every video-to-video transition, and the final fade-to-black |

---

## 13. Open follow-ups (non-blocking)

Things to revisit during or after implementation:

- **Diarization on Windows.** whisper.cpp's diarization isn't first-class
  cross-platform; if bundling a diarizer adds >100MB or breaks the Windows
  installer, ship Phase 5 as flat-transcript + word-timestamps and add
  diarization in 5.1 with a separate engine choice.
- **Per-platform export presets** for video (C4S / OF / IG Reel / etc.) —
  not in the locked set; Phase 4 ships generic transcoding only. Add as
  Phase 4.1 if usage shows the same five presets emerging by hand.
- **Watermark template variants.** Phase 3 ships one watermark profile per
  persona; multi-profile (e.g. "casual" vs "branded") might surface later.
- **Auto-Promos / Auto-CustomerSales derivation in Molly.** Deferred from
  Phase 11. Revisit once Robert has used the report flow for a month and
  knows which derivations would actually be useful.
- **Bundle archival / cleanup.** Old `work/<UID>/` directories accumulate.
  Match Molly's `auto_purge_old_bundles` pattern — Settings toggle +
  threshold + launch-time sweep.
- **Per-platform master variants.** Phase 4.5 ships one landscape 16:9
  master. Vertical 9:16 for Reels / TikTok, square 1:1 for grid posts,
  and per-platform bitrate/duration trims may be useful later — re-open
  if hand-edits become repetitive.
- **DeepFilterNet model size on Windows installer.** ~30MB ONNX. If the
  Windows code-signed installer crosses an unreasonable size threshold,
  consider downloading the model on first launch instead of bundling.
- **Title card customization.** Black background is the locked default;
  could grow to support a per-persona background color, a still-image
  background, or subtle motion (slow zoom, fade through to a brand mark)
  if Robert wants more polish later.

---

## 14. How to start Phase 0

1. `mkdir -p SideMolly && cd SideMolly`
2. `pnpm create tauri-app@latest .` — React-TS template, name `SideMolly`,
   identifier `com.phantomlives.sidemolly`.
3. Copy `Molly/build-app.sh`, `Molly/install.sh`, `Molly/run-tests.sh` and
   adapt names. Land the `--no-install` / `--no-open` opt-outs and the
   `BUILD_ONLY=1` env override per the CLAUDE.md `install.sh` standard.
4. Port `Molly/src-tauri/src/backup.rs` + the launch-time `setup` hook +
   the Settings → Backup view as the first vertical slice.
5. Port `Molly/src/components/Sidebar.tsx` + the HStack layout pattern.
   **Do not** use `NavigationSplitView`.
6. Add `.claude/settings.local.json` with the per-app install permissions:
   ```json
   "Bash(rm -rf /Applications/SideMolly.app)",
   "Bash(ditto --noextattr * /Applications/SideMolly.app)",
   "Bash(osascript -e 'tell application \"SideMolly\" to quit')",
   "Bash(open /Applications/SideMolly.app)"
   ```
7. Land `release-sidemolly.yml` (clone of `release-molly.yml`) with its
   own tag prefix (`sidemolly-vX.Y.Z`) and own minisign keypair.
8. Cut v0.1.0. Tag, push, watch CI sign + draft a release. Done with Phase 0.

After 0 lands, Phase 1 is the first "real" feature (bundle ingest +
verify + Inbox). The phase-1 milestone is **"drag a Molly bundle ZIP onto
the window and see it parsed."**

---

## 15. Font licensing — Paper Daisy

Paper Daisy is the locked-in choice for SideMolly's on-screen UI
(title-screen wordmark, app accents) **and** for video output burned in
by the Auto-Assembly pipeline (§8.5) — persona watermarks in the lower
right of every video, plus the title + persona text rendered onto the
10-second title card.

**Source.** A proper commercial license was purchased on 2026-05-23
from the foundry **maja.mint** (Jana Matthaeus — `info@majamint.com`).
Receipt files live at:

```
~/Documents/2026/2026-05-23 Paper Daisy Font Purchase/Paper Daisy Font/Paper-Daisy-Font/
├── Fonts/
│   ├── PaperDaisy.ttf          (63592 bytes, version 1.2, Dec 2017)
│   └── PaperDaisy.otf          (63592 bytes — same glyphs, OTF format)
└── Extras/
    ├── PaperDaisy-preview.jpg
    └── PaperDaisy-readme.txt   (foundry contact + copyright notice; license terms live on the purchase invoice)
```

**Bundling in SideMolly.** Copy `PaperDaisy.ttf` (TTF, not OTF —
maximum FFmpeg + libass + Tauri webview compatibility) into:

```
SideMolly/src-tauri/resources/fonts/PaperDaisy.ttf
```

Listed in `src-tauri/tauri.conf.json::bundle.resources` so it ships
inside the `.app` / `.exe`. Resolve at runtime via Tauri's
`resolve_resource` helper so FFmpeg's `drawtext` filter receives an
absolute path that works in dev, in `/Applications/SideMolly.app`, and
on Windows installers.

**Receipt + license documentation.** Add a `SideMolly/LICENSES.md` (new
file in Phase 0) cataloging every third-party asset and license. Paper
Daisy entry references the 2026-05-23 commercial purchase and points
to the receipt folder location above. Do **not** commit the receipt PDF
itself to the repo — keep the in-repo doc as a pointer to the local-disk
receipt.

**Molly side — already shipped.** Molly migrated off `paperdaisy-demo.ttf`
to the licensed `PaperDaisy.ttf` in parallel with this plan being written
(see `Molly/CHANGELOG.md` and `Molly/src/assets/fonts/LICENSES.md` on
`main`). SideMolly inherits the same binary — copy it from
`Molly/src/assets/fonts/PaperDaisy.ttf` into
`SideMolly/src-tauri/resources/fonts/PaperDaisy.ttf` at Phase 0 time.
Both apps then point at byte-identical glyphs, so anything visually QA'd
in Molly reads the same when burned into a video by SideMolly.

This is a **non-distributed** application use (single-user creator-side
desktop apps shared only between Robert and Sallie). The font binary
ships embedded in both apps' bundled binaries; rendered output (UI
screenshots, burned-in video watermarks) goes out as raster-only and
does not include the font file itself.
