# Changelog

All notable changes to SideMolly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and SideMolly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.27.1] — 2026-06-02

### Added — Assembled-file details on the summary

The SideMolly Summary now lists the assembled master cut right after **Date
Processed**: its **filename**, **file size** (MB), **length** (MM:SS), and
**SHA-256** for verification — computed from the master cut at generation time
(the same value that's recorded when it's copied to Dropbox, so a recipient can
hash the `.mp4` and compare). Omitted when the bundle hasn't been assembled yet.

## [0.27.0] — 2026-06-02

### Changed — "SideMolly Summary" + sampled, rotation-corrected frames

- Renamed the feature to **SideMolly Summary** (the PDF title, heading, and UI
  labels now carry the space).
- The summary's image grid now shows **frames sampled from the bundle's
  videos** instead of one thumbnail per file: a total of N frames (the
  configurable count, default 30) distributed evenly across the videos
  (3 videos → 10 each), each evenly spaced across its own timeline. Frames are
  **rotation-corrected** (ffmpeg `transpose`, matching auto-assembly) so they
  display upright. Bundles with no video fall back to rotation-corrected
  per-file image thumbnails. New `frames.rs`; `thumbnails::probe_video_duration`
  + `rotated_jpeg_bytes`.
- **Processed-output previews** (Edit tab) now show the **rotated** video
  thumbnail so it's upright, matching the processed image previews.

### Added — Global Edit defaults (Settings → Edit defaults)

The Edit tab's image/video op toggles (Watermark, Strip EXIF/metadata, Rename)
are now seeded from a **global** (not per-persona) settings pane instead of
being hard-coded. **Rename now defaults ON** for both images and videos. New
`edit_defaults` singleton (migration `023`) + `get_edit_defaults` /
`set_edit_defaults`.

## [0.26.0] — 2026-06-02

### Added — SideMollySummary PDF

Each bundle can now produce a **SideMollySummary** — a one-document PDF that
gathers, in order: the applicable metadata (varying by bundle type), a grid of
medium thumbnails, a cleaned-up concatenation of every video transcript, and the
full processing log. Generate it from a bundle's **Distribute** tab; it's also
regenerated automatically and copied to Dropbox alongside the assembled master
cut.

- **Metadata** is built per bundle type and is expandable for new types: Title,
  Working title (only when overridden), Description (typed text, or — for an
  audio description — the transcribed audio), Categories, Go-Live Date, Date
  Processed (the master-cut assembly time), and for **custom** bundles Site/URL,
  Deliver-to, and Price (or "Handled in platform").
- **Transcript** section concatenates every video's `.txt` and cleans it: blank
  lines and stray whitespace removed, sentences capitalized and terminated with
  a period followed by two spaces.
- Rendered with `genpdf` (automatic wrapping + pagination + JPEG embedding);
  body font is bundled Liberation Sans (OFL).
- New module `summary.rs`; commands `generate_bundle_summary`,
  `reveal_bundle_summary`. New `transcribe::transcribe_audio_to_text` for the
  on-demand audio-description transcript.

### Changed — Configurable thumbnail count (default 30)

The export-thumbnail selection is no longer hard-capped at 10. A new
**Settings → Summary → Thumbnail count** (default 30) drives **both** the summary
PDF grid and the thumbnails included in the post-bundle returned to Molly.

- Migration `022`: widens the `bundle_export_thumbs` position CHECK
  (`position >= 1`) via table rebuild, and adds the `summary_settings` singleton.
- `bundles::reselect_export_thumbs` rebuilds the (deterministic, UID-seeded)
  selection to the configured count; it's re-run before composing a summary or a
  post-bundle. Commands `get_summary_settings` / `set_summary_settings`.
- The post-bundle's `artifacts/thumbnails/` now carries this curated selection
  rather than every per-file thumbnail.

## [0.25.0] — 2026-06-02

### Added — Inbox completion lifecycle & filtering

The Inbox no longer shows every bundle forever. Each row now has a **✓ Complete**
button that tucks the bundle out of the default **Active** view; a segmented
**Active | Completed | All** toggle switches between them. Completed bundles can
be **↩ Reactivated** or **🗑 Deleted** (two-step inline confirm). After a
successful **Send to Molly**, the header offers to mark the bundle complete in
one click.

The Inbox also gains a filter toolbar: **type** chips (🎬 content / 🎁 custom /
📅 fansite / ▶️ youtube), **persona** chips (CoC / PoA / Sa), **newest/oldest**
sort, an ingested-**date** range, **text search** over title + UID, and an
`n of N` count readout.

- New nullable `bundles.completed_at` column (migration `021`, plain
  `ALTER TABLE … ADD COLUMN`). `completed_at IS NULL` ⇔ Active; a timestamp ⇔
  Completed. Orthogonal to the unused `bundle_state` workflow enum.
- Commands `set_bundle_completed(uid, completed)` (logs the flip to the
  processing log) and `delete_bundle(uid)`. **Delete scope:** removes the DB row
  (FK-cascades all child tables) and the `~/Downloads/SideMolly/work/<UID>/`
  workspace; **keeps** the sent `Molly post-bundles/<UID>-post.zip` and the
  original incoming source zip. Workspace removal is best-effort (a missing dir
  is not an error).
- `list_bundles` / `get_bundle` now surface `completedAt`. Filtering/sorting is
  client-side (`applyInboxFilters`), with vitest coverage of every dimension.

## [0.24.1] — 2026-06-01

### Fixed — Clearer rotation-selection controls

The single Select-all/Deselect-all toggle was awkward with a partial
selection (it read "Select all", so clearing a few ticked clips meant
select-all-then-deselect). Replaced it with explicit **Select all** and
**Clear selection** buttons plus an "n of N selected" readout.

## [0.24.0] — 2026-06-01

### Added — Multi-select rotation (Edit → Step 1)

Rotation is no longer one clip at a time. Tick a checkbox on any clips and use
**Rotate selected** (or **Rotate all**) to turn them 90° CW per press — each clip
rotates from its own current angle, so a mixed selection stays independent.
Single-tile click still cycles 0→90→180→270 as before. New batch command
`rotate_bundle_files(uid, in_zip_paths, delta_degrees)` does the wrap-around
update atomically and returns the new angles so the grid updates instantly.

### Added — Editable working title (all bundle types)

The Edit tab now has a **Working title** editor. Molly's original title is always
preserved; the override drives the **effective title** used everywhere —
master-cut filename, title card, Dropbox `{title}` folder, posting `{title}` URL,
and all display (Inbox, header). The original shows as an "edited from…" hint and
**Reset to original** clears it.

- New `title_override` column (migration 020, plain `ALTER TABLE … ADD COLUMN`).
  Effective title = `COALESCE(NULLIF(title_override,''), title)`, applied in
  `fetch_bundle_title`, auto-assembly, Dropbox, posting, and `list/get_bundle`.
- Command `set_bundle_title_override(uid, title)` ("" clears); the change is
  written to the processing log.
- **Post-bundle logs it**: `report.json` gains `originalTitle` + `workingTitle`,
  and `notes.md` (previously empty) records `Title changed for processing:
  "<original>" → "<working>".` when they differ.

## [0.23.0] — 2026-06-01

### Added — Per-persona intro / outro for YouTube masters

YouTube bundles can now be bookended with a persona-specific intro and outro
clip. The assembled master becomes `intro → clip1 ⤫ clip2 ⤫ … ⤫ clip[n] →
outro` (⤫ = cross-dissolve between every segment), and for YouTube the intro
**replaces** the generated title card (no title card). Both are off by default
until a clip is uploaded and enabled; the same clip is reused for every bundle
of that persona until changed.

- **Settings → Intro / Outro** — a new per-persona pane (modeled on the
  Watermark pane) to upload, enable/disable, and remove an intro and an outro
  per persona. Only affects ▶️ YouTube bundles.
- New `persona_clips` table (migration 019, keyed by `(persona_code, role)`),
  storing the clip path + enabled flag. Uploaded videos are copied to
  `~/Downloads/SideMolly/persona-clips/`. Commands: `list_persona_clips`,
  `upload_persona_clip`, `set_persona_clip_enabled`, `clear_persona_clip`.
- Assembly: `enqueue_auto_assemble` now branches on `bundle_type == "youtube"`,
  skipping the title card and prepending/appending normalized intro/outro
  segments to the xfade chain. Intro/outro get the same sizing, persona
  watermark, and audio polish as content clips, so the cross-dissolves join
  seamlessly. `dispatch_assemble_master` is unchanged.

### Fixed — Silent source clips no longer break normalize/assembly

`normalize_video` assumed every source had an audio stream; a silent clip (e.g.
a music-less bumper) would fail the `[0:a]` map and the downstream
`acrossfade`. It now probes for audio and synthesizes a silent stereo track
(trimmed to video length) when none is present.

## [0.22.0] — 2026-06-01

### Added — Accept Molly's `youtube` bundle type

Molly began emitting bundles with `bundleType: "youtube"`; SideMolly's
`bundles.bundle_type` CHECK (migration 002) only allowed
`('content','custom','fansite')`, so those bundles failed ingest with
`CHECK constraint failed` and never appeared in the Inbox. Migration
`018_bundle_type_widen.sql` rebuilds the table to add `'youtube'` (the
007/010/016 table-rebuild recipe). Frontend: `bundleType` union widened,
`bundleTypeEmoji` gains a ▶️ case **and a `📦` default** (it previously
returned `undefined` for any unknown type), and `youtube` is added to the
posting `kind` options. Unknown/`youtube` types route to the existing
`GenericRunner` Post tab.

### Fixed — Watched folder flashing (duplicate-uid ping-pong)

Two zips in the watch folder sharing the same `bundleUid` (e.g. a real
bundle and a leftover test export) caused a perpetual re-ingest loop:
`bundles` is keyed by `uid` but `already_ingested` keyed on
`source_zip_path`, so the row's path matched only one zip and the other
re-ingested every scan — flipping `source_zip_path`, re-emitting
`bundle-ingested` (Inbox flash), bumping `ingested_at`, and clobbering the
shared `work/<uid>/` workspace. `ingest_bundle_inner` now refuses a zip
whose uid is already owned by a different, still-present zip
(`BundleError::DuplicateUid`), before extraction; the watcher logs it as a
skip with a one-line warning. First zip ingested for a uid wins.

### Fixed — Stray folder events no longer re-ingest everything

FS events used to force a full-directory re-ingest (`force_reingest=true`),
re-emitting `bundle-ingested` for *every* bundle on any folder activity
(Finder/Dropbox touch, a large file still settling). The watcher now
re-ingests **only the specific zip(s)** named in the event.

### Fixed — `ingested_at` no longer changes on re-ingest

Re-ingesting a bundle overwrote `ingested_at` with the current time, which
re-sorted the Inbox and (since the Dropbox folder uses `{date}`) drifted
the export folder's date to "today". The UPSERT now preserves the original
`ingested_at` on conflict, matching how `created_at` is already handled.

## [0.21.1] — 2026-06-01

### Fixed — Dropbox destination folder no longer carries a timestamp

The Copy-to-Dropbox folder name came out as `2026-06-01T09-15-22 Title`
instead of the intended `2026-06-01 Title`. `extract_date` stripped the
time by splitting `ingested_at` on a space, but re-ingest now stores the
timestamp ISO-8601 style with a `T` separator (`2026-06-01T09:15:22`), so
the whole timestamp survived and `sanitize_filename` turned its colons
into dashes. `extract_date` now splits on either ` ` or `T`, yielding the
bare `YYYY-MM-DD`. Regression test added.

This also un-stuck **Copy to Dropbox appearing to "do nothing"**: with the
folder name corrected, an already-copied bundle's destination path differs
from the stale timestamped one on record, so its assembled file shows as
`new` and the button re-enables. (When the assembled file genuinely is
already at the correct path with matching contents, the button stays
disabled — that's the intended "already in sync" state.)

> Note: the previously-created timestamped folders
> (`…T09-15-22 Title`) are now orphaned in Dropbox — safe to delete.

## [0.21.0] — 2026-06-01

### Added — Per-bundle output format (16:9 horizontal / 9:16 vertical)

Auto-assembly no longer assumes every bundle is landscape. Edit → Step 3
now carries a **Format** choice (🖥 16:9 Horizontal / 📱 9:16 Vertical);
the selection is remembered per-bundle (localStorage keyed by uid) and
passed to `enqueue_auto_assemble`.

- New `enqueue_auto_assemble(uid, format)` parameter. The backend reuses
  the configured Settings → Auto-Assembly resolution and swaps the
  long/short edge to match the orientation (e.g. 1920×1080 ↔ 1080×1920)
  via the new `target_dims` helper — the title card, per-clip normalize,
  and watermark sizing all follow the chosen dimensions.
- **`✨ Auto` is the default and detects orientation from the clips.**
  When the format is `auto` (or unset), the backend probes every clip
  (`thumbnails::probe_video_dimensions`, folding in each file's
  `rotation_degrees`) and picks the majority orientation
  (`detect_orientation`); ties / un-probeable bundles default to
  landscape. The new `detect_bundle_format` command feeds the Edit tab so
  the Auto radio shows what it resolved to, e.g. `✨ Auto (9:16)`.

### Added — 🧹 Clear processing (testing reset)

Edit tab gained a **Clear processing** control (and `clear_bundle_processing`
command) that wipes a bundle's regenerable outputs — the `auto/`,
`processed/`, and `transcripts/` workspace folders plus the
`processed_files`, `jobs` (FK-cascades to `job_runs`), and
`processing_log` rows — so you can re-run the whole Edit pipeline from
scratch. Imported source/working clips and the bundle row are left
untouched, so no re-ingest is needed.

### Changed — Consolidated cut is named `<Title>.mp4`, not `master.mp4`

The assembled output now takes the bundle title as its filename
(`<Title>.mp4`) so the delivered file is self-describing. Title is
sanitized for the filesystem (`master_cut_basename`) and falls back to
`master` when empty.

- All reader sites resolve the file via the new
  `bundles::resolve_master_cut_path`, which prefers the title-named file
  and **falls back to a legacy `master.mp4`** for cuts assembled before
  this release — `get/reveal/open_master_cut`, the Content/Custom runner
  asset list (`list_bundle_assets`), and the Dropbox export
  (`enumerate_artifacts`) all stay working for old and new bundles.

### Fixed — Persona on the title card now reads with spaces

The 10s title card spells the persona out ("Curse Of Curves") via the
new `humanize_persona` CamelCase splitter, while the bottom-right video
**watermark keeps the compact brand form** ("CurseOfCurves"). The split
is idempotent on text that already has spaces.

### Fixed — Watermark is actually visible now

The per-clip (and per-image) watermark gained a dark contrast outline
(`draw_text_with_outline`). A plain white watermark — thin PaperDaisy
strokes at the default 20–25% opacity — washed out over bright video and
pale photos, so it "couldn't be seen". Every glyph now carries an
8-direction dark halo whose alpha is derived from (but floored above) the
user's configured opacity, so the mark reads on any background without
changing how subtle the user asked it to be. The render-PNG padding grew
to keep the outline in-frame.

### Fixed — Transcription no longer crashes hunting for ffmpeg

Per-video transcription failed with `ffmpeg not found — installing via
Homebrew ...` followed by a `brew`-not-found traceback. SideMolly runs
from `/Applications`, so it inherits the stripped Finder `PATH`
(`/usr/bin:/bin:/usr/sbin:/sbin`) that omits `/opt/homebrew/bin`. The
spawned `transcribe.py` couldn't see the installed ffmpeg, fell into its
`brew install ffmpeg` bootstrap branch, and then crashed because `brew`
wasn't on `PATH` either. `dispatch_transcribe_video` now injects an
augmented `PATH` (new `augmented_path` helper prepends the Homebrew bin
dirs) into the child process, so ffmpeg resolves and the install branch
is never reached.

### Changed — Copy to Dropbox ships only the assembled file

Distribute → Copy to Dropbox (and its dry-run preview) now copies **only
the assembled master cut** — not the redundant per-clip processed videos
(already folded into the master), the processed images, or the transcript
sidecars. Those still live in the bundle workspace; they're simply no
longer pushed to Dropbox. `enumerate_artifacts` was trimmed to return just
the master cut.

## [0.20.1] — 2026-05-27

### Fixed — Post-bundle layout reverted to flat, Molly-compatible structure

An audit of the return-zip process found that 0.20.0's single-folder
wrapper (`<uid>-post/` + `<uid>-post-inner/`), added to dodge macOS
Archive Utility's 0700-wrapper quirk, **broke the bundle format
contract**: SideMolly's own `verify_outer_zip` (the exact contract a
Molly post-ingest mirrors) looks up `hashes.json` and the inner zip by
literal top-level name, so the wrapped layout failed with
MissingHashes / MissingInnerZip. Molly's own bundles are flat
multi-root, so the wrapper diverged from the convention.

- **Reverted to the flat layout** — `hashes.json` + `<uid>-post-inner.zip`
  at the outer top level; `report.json` / `notes.md` /
  `posting-log.json` / `processing.log` / `artifacts/` flat inside the
  inner zip; `hashes.json` paths are the bare entry names. Now byte-for-
  byte compatible with the shared verifier.
- **Finder access kept** via a **sidecar folder**: compose now also
  writes a plain `~/Downloads/Molly post-bundles/<uid>-post/` directory
  (normal perms, real dates, rebuilt each run) holding the same inner
  payload. Open it to browse artifacts without extracting — the zip
  stays the untouched Molly deliverable. Sidecar failure is non-fatal
  (logged; the zip already shipped).
- **`posting-log.json` is now hash-covered** in `hashes.json` (it was
  the one inner file left out), matching Molly's "hash every inner
  file" convention.
- **Entry dates stay at the MS-DOS epoch (1980-01-01)** — intentional
  and identical to Molly's `bundle_zip.rs` for byte-deterministic
  output. The `.zip` file itself carries a real modification time; only
  the entries inside read 1980. Not a bug.
- Zip building refactored into a DB-independent `assemble_post_zip`
  core. New regression guard `post_bundle_round_trips_through_shared_verifier`
  composes a post-bundle and asserts `verify_outer_zip` accepts it —
  the check that would have caught the 0.20.0 wrapper regression. Also
  `inner_zip_is_flat_and_matches_molly_layout`, `post_zip_is_byte_deterministic`,
  `sidecar_folder_is_a_plain_browsable_copy`.

## [0.20.0] — 2026-05-26

### Changed — All bundle processing moved to `~/Downloads/SideMolly/`

The per-bundle workspace (extracted media, processed variants,
thumbnails) used to live inside Application Support
(`~/Library/Application Support/com.phantomlives.sidemolly/work/`).
That had two problems: the media wasn't reachable from a browser's
upload dialog (macOS hides `~/Library`), and the launch backup — which
zips Application Support — was dragging hundreds of MB of bundle media
into every archive.

The workspace now lives at `~/Downloads/SideMolly/work/<uid>/`,
alongside the FanSite day folders at `~/Downloads/SideMolly/FanSite/`.
Application Support keeps only what belongs there: the database
(`sidemolly.db`) and settings. As a direct result, launch backups are
now small and fast.

- **One-time launch migration** (`migrate_workspace_to_downloads`):
  on first run of this version, every existing per-bundle directory is
  moved (atomic rename — same volume) from the old root to the new one,
  and the absolute paths the DB stored against the old root are
  rewritten (`bundle_files.working_path` / `.thumbnail_path`,
  `processed_files.output_path`, `bundle_export_thumbs.thumbnail_path`,
  `dropbox_copies.source_path`). Idempotent, and never blocks launch on
  failure (logs and continues). The emptied old `work/` dir is removed.
- `work_root` now resolves to `~/Downloads/SideMolly/work/`; the
  watched-folder scanner routes through it instead of its own
  app_data_dir join (the two had to agree).
- Test: `workspace_path_rewrite_swaps_prefix_only` (prefix-only swap;
  paths outside the old root untouched).

### Fixed — Extracted post-bundle folders now open in Finder

Double-clicking a post-bundle and drilling into `artifacts/` produced
*"you don't have permission to see its contents."* The cause wasn't the
folder being extracted — it was the folder macOS **Archive Utility
synthesizes**: when an archive has more than one item at its top level,
Archive Utility invents an enclosing folder and creates it `drwx------`
(0700). The post-bundle's outer zip (`hashes.json` + inner zip) and
inner zip (`report.json` + `notes.md` + `posting-log.json` +
`artifacts/`) were both multi-root, so each spawned a 0700 wrapper.
(Reproduced with a plain `zip`-made archive too — it's universal
Archive Utility behavior, not a flaw in our zips.)

Both zips now wrap their contents in a **single top-level directory**
(`<uid>-post/` and `<uid>-post-inner/`) carried as an explicit `0o755`
entry. Archive Utility extracts that folder directly with its stored,
traversable mode and never synthesizes a 0700 wrapper.

- Zip writing extracted into testable `build_inner_zip` /
  `build_outer_zip` helpers; `hashes.json` entry paths now carry the
  `<uid>-post-inner/` prefix so they match the inner zip's entry names
  exactly. Determinism (MS-DOS-epoch mtimes, fixed entry order) is
  preserved.
- Tests: `inner_zip_wraps_everything_in_one_traversable_folder`,
  `outer_zip_wraps_everything_in_one_traversable_folder`,
  `inner_zip_is_byte_deterministic`.
- Note for the future: Molly does not ingest post-bundles yet, so the
  layout change has no consumer to break today — it sets the contract
  for when post-ingest is built.

### Fixed — FanSite day media now lands somewhere a browser can reach it

The per-day "infallible media" folder was staged inside the app's
Application Support workspace
(`~/Library/Application Support/com.phantomlives.sidemolly/work/<uid>/fansite-staging/Day NN/`).
That path is unusable when posting: macOS hides `~/Library`, and a
site's browser upload dialog can't navigate there or accept a pasted
`~/Library/...` path.

Day folders now stage to a browsable location under
`~/Downloads/SideMolly/FanSite/<persona> <YYYY-MM> <title> [uid]/Day NN/`
— present in every macOS open-panel sidebar, and aligned with the
PhantomLives default-output-location rule. The day card now also spells
out how to use it: pick **Downloads → SideMolly → FanSite** in the
upload dialog, or press **⌘⇧G** and paste the copied path.

- New `fansite_day_folder` resolves the readable, per-bundle Downloads
  path; `prepare_fansite_day` and `reveal_fansite_day` both use it, so
  Copy-path / Reveal / Re-stage all agree.
- Folder name is sanitized (path separators and control chars stripped)
  and suffixed with a short uid so distinct bundles can't collide.
- Tests: `bundle_folder_name_is_readable_and_unique`,
  `day_folder_is_browsable_and_zero_padded`.

## [0.19.0] — 2026-05-26

### Added — Appearance setting (Dark / Light / Auto)

New **Settings → 🎨 Appearance** tab to choose the theme:

- **Dark** — the default (the app shipped dark-only styling but never
  actually applied the `dark` class, so it had been rendering light;
  it now defaults to dark as intended).
- **Light**.
- **Auto** — follows the macOS Light/Dark setting and updates live as
  the system appearance flips.

The choice persists in `localStorage` (`sm-theme`) and is applied by
toggling `html.dark`, which the surface CSS vars already key off. An
inline bootstrap in `index.html` applies the stored theme before React
mounts, so there's no light-mode flash on launch. Theme logic lives in
`src/lib/theme.ts` with unit tests for `normalizeTheme` / `resolveDark`.

### Added — in-app Manual is now wired

The **Manual** sidebar tab renders `USER_MANUAL.md` live (bundled at
build time) instead of a "not wired yet" placeholder, with a sticky
right-rail table of contents that anchor-scrolls to each section. The
markdownLite renderer that previously lived inside `DocDrawer` is
extracted to a shared `src/components/Markdown.tsx` (used by both the
Manual and the bundle info.md preview). The manual content was rewritten
to drop the stale "Phase 0" framing and use lists instead of tables
(markdownLite renders lists, not tables).

## [0.18.2] — 2026-05-26

### Fixed — "Open site" was blocked by the opener ACL

Clicking **🚀 Open {site}** failed with "Not allowed to open url …".
`opener:default` ships no URL scope, so every `open_url` was denied.
Added an explicit `opener:allow-open-url` scope for `http://*` +
`https://*` to the capability. Also normalize the typed site URL
before opening — lowercase the scheme (the scope glob is
case-sensitive, so a stored `Https://…` was rejected) and prepend
`https://` when no scheme is present.

## [0.18.1] — 2026-05-26

### Changed — FanSite day card simplified to a posted checkbox

FanSite posting is binary, so the day card drops the four-state
dropdown (pending/scheduled/posted/skipped) for a single **posted**
checkbox — check to mark posted, uncheck to undo a mistaken check.
The **Posted URL** field is removed entirely (the fan-sites don't
surface a post URL to record). **✓ Mark posted & advance** stays as
the fast path for walking a site day-by-day. The calendar and site-tab
progress still read from the same `posted` state, and the posting log
still records each posted/unposted/reset flip.

## [0.18.0] — 2026-05-26

### Added — Phase 13: FanSite multi-site posting workflow

The 📅 FanSite runner is rebuilt around how fan-sites actually get
posted: before the start of each month, to a **fixed roster of sites
per persona**, walking one site fully before moving to the next.

**Per-persona site roster + one-click seed.** CoC posts to OnlyFans /
ManyVids / Niteflirt; PoA posts to OnlyFans / Niteflirt / LoyalFans;
Sheer (Sa) has no fan-sites and is excluded. `seed_fansite_targets`
creates the canonical roster (idempotent — never clobbers your
Settings → Platforms edits), reachable from the runner's empty state
and a new **📅 Seed fan-sites** button in Settings → Platforms. Names
use bracket notation (`OnlyFans [CoC]`) so the same site can exist
under two personas despite the `UNIQUE(name)` constraint.

**Multi-site calendar.** `get_fansite_plan` now returns *every*
fan-site target for the persona (the old Phase-10 `list_fansite_plan`
resolved only one). The runner shows **site tabs** with per-site
progress (`✓ posted / total`); pick a site, walk the month, switch to
the next. State is keyed `(bundle, target, day)` so stopping and
resuming auto-focuses the next pending day for the active site.

**Infallible per-day media.** `prepare_fansite_day` stages exactly one
day's files into a dedicated folder (`fansite-staging/Day NN/`),
applying the abbreviated fan-site processing — **rotate + strip EXIF,
no watermark** (the sites watermark automatically; doubling looks
bad). The day card shows thumbnails, a **📋 Copy folder path** button,
**Reveal folder**, and per-file copy-path — so the upload dialog can
only ever see the right files.

**Prominent persona color** banner (CoC pink / PoA crimson) and
**copy chips** for Persona · Date · Title · Message on every day.

**Reset / unwind.** "Reset this site" and "Reset all sites"
(confirm-gated) clear posting state to start fresh; the audit log
keeps the history.

**Posting log (carried back to Molly).** New append-only `posting_log`
table (migration `017`) records every posted / unposted / reset action
with a timestamp, persona, site, day, title, and URL. Viewable inline
in the runner and written to `posting-log.json` inside the post-bundle
ZIP so Molly can reconcile what actually went live.

### Migrations

- `017_posting_log.sql` — append-only `posting_log` audit table.

## [0.17.0] — 2026-05-24

### Added — Phase 12: Jobs panel polish

The 🛠 Jobs view (cross-bundle queue inspector) gets the operational
controls PLAN.md called for: pause, retry, cancel, bulk clear.
Closes out the original 13-phase plan.

**Worker pause toggle** — `app_settings.jobs_paused` flag. Worker
poll loop reads it on every tick (cheap indexed SELECT) and skips
job-claiming when set, so the currently-running job finishes
cleanly but the queue holds. UI button flips between
`⏸ Pause worker` and `▶ Resume worker` (gold highlight when
paused) + the header subtitle shows "· ⏸ paused".

**Retry failed jobs** — `retry_job(id)` flips `status: failed →
pending` and clears `last_error`. The worker picks it up on the
next poll cycle. Per-row 🔄 Retry button on failed rows (gold).
`attempts` counter survives, so the row preserves its history.

**Cancel pending jobs** — `cancel_pending_job(id)` deletes a
pending row before the worker claims it. Per-row ✕ button on
pending rows (red border). Confirms before deletion. Running
jobs aren't cancellable today (ffmpeg / whisper subprocesses
lack a graceful-stop API) — UI says so via tooltip.

**Bulk clear** — `clear_jobs_by_status(['done'|'failed'])`.
`🗑 Clear done (N)` / `🗑 Clear failed (N)` buttons in the toolbar
with row counts. Confirms before bulk delete.

**Kind filter** — dropdown alongside the existing status filter
pills. Defaults to "all"; lists every kind currently present in
the queue (process_video / render_title / normalize_video /
assemble_master / transcribe_video) so users can drill into one
type at a time.

**Per-job expand** — click the ▸ to expand a row into a
two-column drawer:
- **Params**: pretty-printed JSON (params_json from the queue row).
- **Log entries**: filtered to `job_id` from `processing_log`, with
  timestamp + level + message. Final error tail appended at the
  bottom in red for failed rows.
- Footer: `id #N · K attempts · created at …`.

**Live updates** — JobsView subscribes to `job-updated` on the
Tauri event bus. Every status transition, retry, cancel, or clear
fires the event → list refreshes. No manual refresh needed.

### Tests

145 passing (unchanged). The new ops commands don't add boundary
types so no new camelCase contracts; their UI behavior is verified
by hand.

### Closes the original 13-phase plan

| Phase | Ships |
|---|---|
| 0  | Tauri scaffold + sidebar + backup-on-launch (v0.1.0) |
| 1  | Bundle ingest (v0.2.0) |
| 2  | Molly's manifest.json (v0.3.0) |
| 3  | Image ops + watermark (v0.5.0) |
| 4  | Video ops via FFmpeg (v0.6.0) |
| 4.5a | Auto-Assembly pipeline (v0.8.0) |
| 4.5b | DeepFilterNet voice isolation (v0.10.0) |
| 5  | Transcription via MLX (v0.11.0) |
| 6  | Dropbox local-folder copy (v0.13.0) |
| 7  | Posting primitives (v0.14.0) |
| 8 / 9 / 10 | Content / Custom / FanSite runners (v0.15.0) |
| 11 | Post-bundle return trip (v0.16.0) |
| 12 | 🛠 Jobs panel polish (v0.17.0) — **this release** |

Follow-ups that remain (none blocking the roadmap):
- Auto-compose-on-shipped + undo banner (Phase 11 follow-up).
- DeepFilterNet binary auto-install.
- Diarization (Phase 5.1) — speaker turns for transcripts.
- Molly-side post-bundle ingest PR (separate from SideMolly).

## [0.16.0] — 2026-05-24

### Added — Phase 11: post-bundle return trip back to Molly

SideMolly composes a deterministic `<UID>-post.zip` containing a
structured outcomes report + supporting artifacts, ready for Molly
to ingest. Manual trigger from a **📤 Send to Molly** button in the
sticky bundle header; auto-on-shipped + the 5-second undo banner
are deferred to v0.16.x (need the lifecycle hook + UX work).

**Output layout** (mirrors PLAN.md §9.1, byte-identical to Molly's
outbound bundle pattern):

```
<UID>-post.zip                            (outer)
├── <UID>-post-inner.zip                  (inner — MS-DOS epoch)
│   ├── report.json                       (per §9.2 schema)
│   ├── notes.md                          (empty MVP; UI editing later)
│   ├── processing.log                    (when bundle workspace has one)
│   └── artifacts/
│       ├── transcripts/<stem>.txt + .srt (Phase 5 sidecars)
│       └── thumbnails/<stem>.jpg         (per-file thumbs)
└── hashes.json                           (same shape as inbound)
```

**Determinism**: every zip entry's mtime is set to MS-DOS epoch
(1980-01-01 00:00:00). Inner-zip entries sorted by name via
`BTreeMap`. Re-runs against the same source data produce
byte-identical outputs — so the post-bundle is bit-stable and the
sha256 we record in `hashes.json` is reproducible.

**Drop location**: `~/Downloads/Molly post-bundles/` (sibling to the
inbound watched folder). Created on demand.

**`report.json` v1** schema (matches §9.2):

```json
{
  "reportVersion": 1,
  "bundleUid": "...",
  "bundleType": "content",
  "personaCode": "CoC",
  "reportComposedAt": "2026-05-25T18:42:00Z",
  "bundleState": "shipped",
  "targets": [{
    "targetId": "...",
    "targetName": "...",
    "state": "posted",
    "postedAt": "...",
    "postedUrl": "...",
    "bodyOverride": "...",
    "filesUsed": ["..."],
    "notes": "...",
    "fansiteDay": 7
  }]
}
```

`filesUsed` derives from `bundle_postings.selected_assets_json` (the
Phase 8 per-platform asset picker). `fansiteDay` is omitted from
non-FanSite targets (camelCase serde + nullable Option).

**Idempotency**: re-running `📤 Send to Molly` for the same UID
overwrites `<UID>-post.zip` atomically (`.tmp` + rename). Molly's
ingest will be idempotent on `bundleUid` (separate Molly-side PR,
not in this commit).

**Sticky header surface**:
- First send: `📤 Send to Molly` button.
- After at least one send: `📁 ✓ Sent · 142 KB` (reveals the file
  in Finder on click) + `🔄 Re-send to Molly` button next to it.
- Disabled while any job for the bundle is in flight — don't
  snapshot a report mid-process. Tooltip explains why.

**Logging**: every compose hits `processing_log` under kind=
`post_bundle` with `(N targets, M artifacts, B bytes)` summary.

**Tests**: 145 passing. Round-trip serialization test for the
`Report` shape covers every camelCase field + `fansiteDay` rename.
DOS-epoch helper test. SHA256 hex format test. Migration immutability
guardrail unchanged (no new migrations in this phase).

### Deferred from Phase 11

- Auto-compose on `bundle_state = 'shipped'` transition.
- 5-second undo banner UX.
- Molly-side ingest (separate Molly PR per §9.5).
- `bundleLevelNotes` editor (currently always `null` in the report).
- Per-bundle `notes.md` content (currently always empty).

## [0.15.0] — 2026-05-24

### Added — Phases 8 / 9 / 10: Content, Custom, FanSite Post Runners

Three flavor-specific post runners on top of the Phase-7 primitives.
Bundle workspace **Post** tab now routes by `bundle.bundleType`:

```
  content  → 🎬 ContentRunner  (Phase 8)  multi-platform fan-out grid
  custom   → 🎁 CustomRunner   (Phase 9)  single delivery card
  fansite  → 📅 FanSiteRunner  (Phase 10) day-by-day calendar walk
  other    → 📋 GenericRunner  (Phase 7 fallback)
```

**Migration 016** extends `bundle_postings` with two columns:

- `selected_assets_json` (TEXT, default `'[]'`) — per-platform asset
  selection for the Content runner.
- `fansite_day` (INTEGER, nullable) — day-of-month for FanSite
  postings. NULL for Content/Custom.

The UNIQUE key changes from `(bundle_uid, target_id)` to
`(bundle_uid, target_id, fansite_day)` so a FanSite bundle can have
N rows for the same target — one per day.

**New backend bits**:
- `list_bundle_assets(uid)` returns every artifact the user can
  attach to a post: processed images + videos (from
  `processed_files`), master.mp4 from auto-assembly, transcript
  `.txt`/`.srt` sidecars.
- `list_fansite_plan(uid)` joins `manifest.fan_days[]` with the
  per-day `bundle_postings` rows. Resolves the FanSite target
  (first enabled `kind='fansite'` posting target for the bundle's
  persona). Returns `{year, month, target, days[]}` for the
  calendar UI.
- `upsert_bundle_posting` + `mark_posted` updated to take an
  optional `fansite_day` so the FanSite runner can address rows
  by day. Composite uniqueness drives the lookup/upsert.

**🎬 ContentRunner** (multi-platform fan-out).

- Header band: bundle title + manifest description (whitespace-
  preserved) + categories chips (each clickable to copy, plus
  📋 all).
- Card grid (one per applicable target) reuses the Phase-7
  PlatformCard shape with three additions:
  - **📁 Assets (N)** button toggles an asset-picker panel with
    grouped checkboxes (Images / Videos / Master / Transcripts).
    Selection persists into `selected_assets_json`.
  - **📋 Body** button copies the current per-platform body
    (seeded from `manifest.descriptionText`).
  - Body textarea seeded from manifest description; per-platform
    edits persist into `body_override` on blur.

**🎁 CustomRunner** (one-to-one delivery).

- Recipient + delivery details band, pulled from
  `manifest.deliveryRecipient` / `deliverySiteName` / `deliveryUrl`
  / `priceCents` / `handledInPlatform`. Each surfaces a 📋 Copy
  affordance.
- Special-instructions read-out from the manifest.
- Files-for-delivery list (every asset listed; reveal-workspace
  shortcut) so the user can drag into the delivery platform.
- Single delivery card with auto-composed message
  (`Hi <recipient>, Your custom is ready…`) editable per-platform.
- Payment-received-via radio (in-platform / tip / other) stored
  in `notes` as a `[received_via=…]` tag prefix — keeps schema
  unchanged while persisting the choice.

**📅 FanSiteRunner** (day-by-day calendar).

- Mon-Sun calendar grid laid out by `manifest.fansiteYear` +
  `fansiteMonth` (correct first-of-month dow offset).
- Each cell shows day number, abbreviated message, state glyph
  (✓ posted / 🗓 scheduled / · pending / — skipped), file count.
- Click a day → focused DayCard with the full message readout +
  🚀 Open fan-site + 📋 Copy message + state dropdown + posted
  URL field + **✓ Mark posted & advance** (auto-jumps to next
  pending day, matching PLAN.md §8.3 "advance-on-post").
- Counts in the header: ✓ / N · ⏳ / · — skipped.
- Auto-focus next pending day on first load.

### Tests

139 passing. New camelCase contracts for `BundleAsset`,
`FanSiteDayPosting`, `FanSitePlan` + the extended `BundlePosting`
shape (with `selectedAssetsJson` + `fansiteDay`). Migration smoke
covers 016 and the rebuilt `bundle_postings` table layout.

### What's next (not in this commit)

Phase 11 — return-bundle composition: SideMolly writes a
`<UID>-post.zip` back to Molly with `report.json` listing what was
actually posted to which platform when. Auto on `shipped` state with
undo, plus a manual button.

## [0.14.0] — 2026-05-24

### Added — Phase 7: Posting primitives

The infrastructure underneath the three flavor-specific post runners
that land in Phases 8-10. Bundle workspace **Post** tab (previously a
disabled placeholder) lights up as a generic per-platform checklist;
Settings → **🚀 Platforms** gets a CRUD editor for the user's own
platform list (independent of Molly's — locked-in decision #12).

**Migration 015**: two new tables.

- `posting_targets` — name, url_template, persona_code (nullable),
  color, icon, position, kind (`content`/`custom`/`fansite`/`any`),
  enabled. No seed rows; the user adds platforms via Settings →
  Platforms.
- `bundle_postings` — one row per (bundle_uid, target_id) pair,
  tracking state (`pending`/`scheduled`/`posted`/`skipped`),
  posted_at, posted_url, body_override, notes. UPSERT on the
  composite key.

**`posting.rs` module**: types + Tauri commands.

- CRUD: `list_posting_targets`, `create_posting_target`,
  `update_posting_target`, `delete_posting_target`.
- Per-bundle: `list_bundle_postings(uid)` returns a Vec<PostingCard>
  pre-resolving the URL template against the bundle's title / uid /
  persona / date. Filters server-side by kind (`any` OR match) and
  persona (target NULL = "any persona").
- State writes: `upsert_bundle_posting(input)` for full upsert,
  `mark_posted(uid, targetId, postedUrl?)` for the common one-click
  case.
- `resolve_url_template` replaces `{uid}` / `{title}` / `{persona}`
  / `{date}` with URL-encoded values (minimal in-crate encoder; no
  new dep for token-replacement on user-set URLs).

**Settings → 🚀 Platforms** — CRUD UI. Each row shows name +
icon + kind chip + persona scope + enable toggle + Edit/Delete.
Inline draft editor for "➕ Add platform" + per-row edit; includes
URL template, color picker, kind dropdown (`any` / `content` /
`custom` / `fansite`), persona scope, sort position.

**Bundle workspace → 🚀 Post tab** — generic per-platform card
grid. Each card:

- Header: icon + name + kind/persona scope chip + state badge
  (⏳ pending / 🗓 scheduled / ✓ posted / — skipped).
- Action row: `🚀 Open` (launches resolved URL via
  `tauri-plugin-opener`), `📋 Title` (clipboard), state dropdown,
  `▸ More` toggle.
- Expanded body: resolved URL preview, body override textarea
  (defaults to bundle title), posted URL field, `✓ Mark posted`
  button (timestamps + state transition in one click), notes
  textarea, last-posted timestamp readout.
- Cards filtered server-side to applicable platforms only —
  bundle of kind `content` sees `kind='content'` + `kind='any'`
  platforms; persona-scoped platforms only show on matching-
  persona bundles.

Flavor-specific runners coming next: Phase 8 (🎬 Content multi-
platform fan-out grid + per-platform body overrides + file
selection), Phase 9 (🎁 Custom one-shot delivery + payment
surface), Phase 10 (📅 FanSite day-by-day calendar walk).

### Tests

136 passing. New camelCase contracts for `PostingTarget`,
`PostingTargetInput`, `BundlePosting`, `PostingCard`,
`UpsertBundlePostingInput`. URL-template resolver unit tests cover
every variable, the no-vars passthrough case, the URL-encoder
edge cases, and the kind-validator.

## [0.13.1] — 2026-05-24

### Changed — Dropbox folder template default

Drop the brackets + the literal `" - "` separator from the default
Dropbox-folder template. Was `[{date}] - {title}` → now `{date} {title}`,
so a bundle titled "Mary Poppins" ingested on 2025-12-31 lands at:

```
<root>/2025-12-31 Mary Poppins/
```

Sorts the same in Finder but reads cleanly without bracket noise —
matches how Robert actually names his project folders elsewhere.

Migration 014 updates any `dropbox_settings` row still on the old
default; user-customized templates are untouched. The Reset button in
Settings → Dropbox now restores `{date} {title}`.

## [0.13.0] — 2026-05-24

### Added — Phase 6: Dropbox local-folder copy

The bundle workspace **Distribute** tab — previously a disabled
placeholder — lights up. One-click ships every processed artifact
into the user's local Dropbox sync folder. SideMolly never touches
the Dropbox HTTP API; files land on disk and the Dropbox app does
the rest.

**Destination layout** (per Robert's direction 2026-05-24):

```
<dropbox-root>/
  [2026-05-22] - and before too soon it was JUNE/
    01_01_xxx__watermark_strip.jpg
    02_01_xxx__watermark_strip.jpg
    …
    30_01_xxx__video_watermark_strip.mp4
    master.mp4
    30_01_xxx.txt
    30_01_xxx.srt
    30_01_xxx.json
```

Flat per bundle (no per-kind subfolders); folder name follows the
template `[{date}] - {title}` by default (supersedes the original
PLAN.md decision #21 `{uid}_{persona}_{title}` — date form is what
Robert actually browses by). Template variables: `{date}`
(YYYY-MM-DD from `bundles.ingested_at`), `{title}`, `{uid}`,
`{persona}`. Filesystem-hostile chars get rewritten to `-`.

**What gets shipped**:
- Every row in `processed_files` (images + videos + auto-assemble
  normalized clips and any individual processed video the user ran
  via Edit Step 2).
- `master.mp4` from `auto/` (Phase 4.5 output) when present.
- Transcript sidecars (`.txt` + `.srt` + `.json`) when present.

**Idempotent copy**:

- New `dropbox_copies` table (migration 013) tracks every
  (bundle_uid, source_path, dropbox_path) tuple with the source's
  sha256 at copy time.
- Re-running Copy is a no-op when the source's sha hasn't changed
  AND the destination file still exists — only the modified /
  never-shipped artifacts get re-copied.
- Atomic write (`.sm-dropbox-tmp` + rename) so Dropbox never
  observes a half-written file.
- Verify-on-write: re-hash the destination after copy and flag
  mismatches in the result. Per-row `verified` bool persisted.

**Distribute tab UI**:
- Header card shows resolved destination path + template + Refresh
  / Copy / Reveal buttons.
- Preview table lists every artifact with status pill (`✨ new` /
  `✎ changed` / `✓ skip` / `⚠ missing`), kind tag (image / video /
  master / transcript-{txt,srt,json}), filename, full destination
  path, file size.
- Copy button label shows pending count (`Copy to Dropbox (12)`)
  and disables when nothing's pending.
- Post-copy summary banner with copied / skipped / failed totals
  and the per-row results inline.

**Settings → Dropbox**:
- Root path input with native folder picker (📁 Browse…) for the
  Dropbox folder.
- Template input + Reset button. Inline help shows the variable
  list.
- Auto-detect default: when the row is unset, `get_dropbox_settings`
  returns `~/Dropbox/` (or `~/Library/CloudStorage/Dropbox/`) if it
  exists on the user's machine so they can usually click Save
  without picking.

**Logging**: every copy + every verify result hits `processing_log`
under kind=`dropbox_copy`. Mismatched verifies log as `warn`.

### Tests

126 passing. New camelCase contracts for `DropboxSettings`,
`DryRunRow`, `DryRunSummary`, `CopyResultRow`, `CopyResultSummary`.
Migration smoke covers 013 + the two new tables. Template
resolution unit tests cover the default layout + all variables +
filesystem-hostile char sanitization + the `nopersona` fallback for
null personas.

## [0.12.0] — 2026-05-24

### Added — smart re-transcribe + bundle activity log

**Smart re-transcribe**. The original "📝 Transcribe all videos"
button queued every video unconditionally, which after a partial run
re-ran whisper on clips that already had clean transcripts. Replaced
with two buttons:

- **📝 Transcribe missing (N)** — default action. Skips videos whose
  `.txt` sidecar exists; queues only the failed and never-started
  ones. Most-common case after a flaky batch.
- **🔄 Re-transcribe all** — secondary action. Queues every video
  regardless of existing transcript. Use when the whisper model /
  language setting changes and you want a clean redo.

`enqueue_bundle_transcripts` gains a `force_all` param (defaults
`false`). Returns a new `skipped` count so the result pill shows
e.g. `9 queued · 4 skipped (already done)`.

**Bundle activity log** (migration 012, new `processing_log` module).
Every job lifecycle event lands in a SQLite table scoped by
`bundle_uid` + `job_id`:

```
info  process_video    01_01_xxx.mov  started
info  process_video    01_01_xxx.mov  done in 32.1s
error transcribe_video 13_01_xxx.MP4  failed
                                       | transcribe exit Some(1): ...
```

The worker in `jobs.rs::run_worker` writes started/done/failed
entries with elapsed time; dispatchers can append ad-hoc info/warn
events. Failed jobs include the stderr tail in `details`.

**Edit tab Step 6 — Activity log** surfaces the per-bundle log
newest-first with three buttons:

- **💾 Export processing.log** — writes a tab-separated text file
  to `…/work/<uid>/processing.log` (auto-reveals in Finder). This
  file is what we'll fold into the Phase 11 return-bundle ZIP back
  to Molly so she gets a record of what SideMolly did to the bundle.
- **🗑 Clear** — wipes the log for this bundle (with confirm).
- The log renders inline in monospace with timestamp, level, kind,
  subject (filename), and message; failure details show truncated
  on the row with full text in the hover tooltip.

**New Tauri commands**:
- `list_log_entries(bundleUid, limit)` — filtered + capped.
- `export_bundle_log(uid)` — write text file, returns path + row count.
- `clear_bundle_log(uid)` — DELETE WHERE bundle_uid = ?
- `reveal_bundle_log(uid)` — Finder-reveals the exported text file.

116 tests passing. New camelCase contracts for `LogRow`,
`ExportLogResult`. Migration smoke applies 012 and verifies
`processing_log` exists. `level` CHECK constraint test ensures
invalid levels are rejected at the DB layer.

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
