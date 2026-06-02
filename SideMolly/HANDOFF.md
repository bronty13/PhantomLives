# SideMolly — Architecture Handoff

> **Status: shipping (v0.27.1).** All 13 planned phases (0–13 in
> [`PLAN.md`](PLAN.md) §11) plus several post-plan additions are live. This doc
> is the current architecture snapshot; `PLAN.md` remains the design rationale
> and decision log. `CHANGELOG.md` is the per-release record.

## 30-second mental model

SideMolly is a Tauri 2 desktop app (Rust backend + React 19 / TS / Tailwind
frontend) that consumes Molly's deterministic bundle ZIPs at
`~/Downloads/Molly bundles/<UID>.zip`, decomposes them, helps Robert push
each piece of content through edit → process → post, and sends a structured
post-bundle ZIP back to Molly at `~/Downloads/Molly post-bundles/<UID>-post.zip`.

**No runtime coupling to Molly.** The two apps share only a file format
on disk; neither opens the other's DB. Per-bundle working files live under
`~/Downloads/SideMolly/work/<UID>/` (extracted media, `.thumbs/`, `.frames/`,
`transcripts/`, `auto/<Title>.mp4`).

## Repo surface

```
SideMolly/
├── src/                                   React 19 + TS frontend
│   ├── main.tsx · App.tsx                 Vite entry; ViewKey routing + ⌘S sidebar
│   ├── components/Sidebar.tsx             HStack 240px (never NavigationSplitView)
│   ├── data/bundles.ts                    invoke() wrappers + boundary interfaces
│   ├── data/db.ts                         shared tauri-plugin-sql Database singleton
│   ├── lib/useAsyncRefresh.ts             race-safe loader; lib/inboxFilters.ts (+test)
│   ├── views/Inbox/InboxView.tsx          inbox list + completion/filter toolbar
│   ├── views/Bundle/                      BundleWorkspace + Overview/Edit/Distribute/Post
│   │                                      tabs, Content/Custom/FanSite/Generic runners,
│   │                                      TopTrio, DocDrawer
│   ├── views/Jobs/JobsView.tsx            background-job queue viewer
│   ├── views/Settings/                    11 panes (Appearance, Watched folder, Watermark,
│   │                                      Edit defaults, Auto-Assembly, Intro/Outro, Dropbox,
│   │                                      Summary, Platforms, Backup, About) via SettingsView
│   └── views/Manual/ManualView.tsx
├── src-tauri/src/                         Rust backend (23 modules)
│   ├── lib.rs                             Tauri Builder + plugin wiring + migrations +
│   │                                      ~90 generate_handler! commands + contract/
│   │                                      smoke/immutability tests
│   ├── bundles.rs                         ingest, inbox lifecycle, image ops, thumbnails,
│   │                                      export-thumb selection, summary/edit settings
│   ├── bundle_io.rs · extract.rs · manifest.rs   outer-zip verify → extract → parse manifest
│   ├── thumbnails.rs                      per-file thumbs, ffmpeg/ffprobe helpers, rotation
│   ├── frames.rs                          sampled video frames for the summary grid
│   ├── images.rs · video.rs              media processing (rotate/watermark/strip/rename)
│   ├── auto_assemble.rs                   title card → normalize → xfade → master cut
│   ├── transcribe.rs                      MLX/whisper transcription (+ audio→text helper)
│   ├── jobs.rs                            generic background job queue + sequential worker
│   ├── posting.rs · fansite.rs           posting targets/state + FanSite multi-site runner
│   ├── post_bundle.rs                     compose <UID>-post.zip return trip
│   ├── dropbox.rs                         copy master cut + summary PDF to local Dropbox
│   ├── summary.rs                         SideMolly Summary PDF (genpdf + Liberation Sans)
│   ├── persona_clips.rs · processing_log.rs · backup.rs · watch.rs · fsutil.rs
│   ├── migrations/001..023_*.sql          23 immutable migrations (hash-guarded)
│   ├── capabilities/default.json          Tauri ACL
│   └── resources/fonts/                   PaperDaisy.ttf (display) + LiberationSans-* (PDF body)
├── build-app.sh   install.sh   run-tests.sh
└── README.md  CHANGELOG.md  USER_MANUAL.md  HANDOFF.md (this)  PLAN.md
```

## Tauri command surface

~90 commands are registered in `lib.rs`'s `generate_handler![...]` — that macro
is the source of truth. Notable feature groups beyond the per-phase runners:

| Module | Commands |
|---|---|
| backup | `run_backup_now`, `list_backups`, `test_backup`, `restore_backup`, `reveal_backup_dir`, `reveal_path`, `get_backup_settings`, `set_backup_settings` |
| bundles (lifecycle) | `set_bundle_completed`, `delete_bundle` (+ `list_bundles`/`get_bundle` surface `completedAt`) |
| summary (`summary.rs` + `frames.rs`) | `generate_bundle_summary`, `reveal_bundle_summary`; settings `get_summary_settings`/`set_summary_settings` (`thumbCount`, default 30). PDF via `genpdf` + bundled Liberation Sans. Sections: metadata (incl. assembled-file filename / size MB / length MM:SS / SHA-256, after Date Processed) → frame grid → cleaned transcript → processing log. Grid = N rotation-corrected frames sampled across the bundle's videos (`frames::sample_bundle_frames` + `distribute`), falling back to rotation-corrected image thumbnails. `thumbnails::probe_video_duration` + `rotated_jpeg_bytes`. Post-bundle thumbnails still use the `bundle_export_thumbs` selection. |
| edit defaults | `get_edit_defaults`/`set_edit_defaults` (global singleton, migration 023; Rename defaults ON). EditTab seeds its op toggles from these. |
| fansite (Phase 13) | `get_fansite_plan`, `seed_fansite_targets`, `prepare_fansite_day`, `reveal_fansite_day`, `set_fansite_day`, `reset_fansite_postings`, `list_posting_log` |

ACL is in `src-tauri/capabilities/default.json`.

### FanSite multi-site workflow (Phase 13, `src-tauri/src/fansite.rs`)

The 📅 runner posts a month to a fixed per-persona site roster
(CoC → OnlyFans/ManyVids/Niteflirt; PoA → OnlyFans/Niteflirt/LoyalFans;
Sheer excluded), one site at a time. Key pieces:

- **`get_fansite_plan`** returns *all* enabled `fansite`-kind targets
  for the persona plus a per-day × per-target state grid (keyed
  `(bundle_uid, target_id, fansite_day)` in `bundle_postings`). It
  supersedes the Phase-10 single-target `list_fansite_plan` (removed).
- **`prepare_fansite_day`** wipes + rebuilds
  `<workspace>/fansite-staging/Day NN/` with exactly that day's media,
  applying **rotate + strip-EXIF, no watermark** (images via
  `images::process_image`, videos via `video::process_video`; audio
  copied verbatim). This is the "infallible media" guarantee.
- **`set_fansite_day`** upserts one cell and appends a `posting_log`
  row on flips to/from `posted`. **`reset_fansite_postings`** unwinds a
  site (or all) and logs a `reset`.
- **`posting_log`** (migration `017`, append-only) is the audit trail.
  `read_posting_log(conn, uid, newest_first)` backs both the in-app
  viewer and `post_bundle.rs`'s `posting-log.json` (oldest-first) in
  the return ZIP.
- Seed names use bracket notation (`OnlyFans [CoC]`) to coexist under
  the `posting_targets.name` UNIQUE constraint.

## Cross-cutting standards

- **CLAUDE.md backup standard.** Required UI present; tests cover
  debounce + retention prefix guard + list ordering + verify-missing-DB
  + target-dir auto-create + debounce constant.
- **CLAUDE.md install.sh standard.** `build-app.sh` chains into
  `install.sh`; install does quit → `ditto --noextattr` → relaunch with
  `--no-open` opt-out.
- **CLAUDE.md sidebar pattern.** HStack 240px sidebar, never
  `NavigationSplitView`. ⌘S / Ctrl+S toggles.
- **camelCase serde contract.** Every boundary struct uses
  `#[serde(rename_all = "camelCase")]` + a `camel_case_contract` cargo
  test. New boundary types must add a contract test.
- **Migration discipline.** Migrations are immutable once shipped. A new
  migration must be added in **four** places: the `migrations` vec in
  `lib.rs::run()`, the `migration_smoke::all_migrations_apply_cleanly` table,
  `MIGRATION_FILES`, and `EXPECTED_MIGRATION_HASHES` (the hash the
  `migration_immutability` test prints). The test module also has its own
  `fresh_db()` helper that applies every migration — extend it too. Latest is
  `023_edit_defaults.sql`.
- **Singleton settings tables.** `auto_assembly_settings` (011),
  `summary_settings` (022), `edit_defaults` (023) follow the same
  `id INTEGER PRIMARY KEY CHECK(id = 1)` + `INSERT OR IGNORE` pattern with a
  matching `get_*`/`set_*` command pair.

## Tests + build

- `./run-tests.sh` — `cargo test --lib` (203 Rust tests as of v0.27.1) then
  `pnpm test` (vitest). `pnpm typecheck` for `tsc -b --noEmit`.
- `./build-app.sh` — builds the `.app`, installs to `/Applications/` via
  `install.sh`, and relaunches. The launch-time auto-backup writing a fresh
  zip is a quick signal that migrations applied cleanly.

## Recent additions (post-phase-plan)

- **Inbox completion lifecycle + filtering** (migration 021) — mark bundles
  complete/active, filter by status/type/persona/date/text, delete.
- **SideMolly Summary PDF** (migration 022, `summary.rs`/`frames.rs`) — see the
  command table above.
- **Global Edit defaults** (migration 023) — the Edit tab's op toggles seed from
  a global, not-per-persona, settings pane; Rename defaults ON.
