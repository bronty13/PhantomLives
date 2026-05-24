# Changelog

All notable changes to SideMolly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and SideMolly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
