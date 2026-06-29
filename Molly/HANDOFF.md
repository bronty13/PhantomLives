# Molly — Architecture Handoff

> Snapshot for any future developer (or future-you) coming back to Molly cold. Walk top-to-bottom and you'll know where everything lives by the bottom.

## 30-second mental model

Molly is a single-user **Tauri 2** desktop app — Rust backend + React 19 / TypeScript / Tailwind frontend, SQLite database via `tauri-plugin-sql`, built into a `~10 MB` signed installer for macOS and Windows. There is no server, no hosting, no auth. One creator uses it on one machine; the developer (Robert) occasionally receives a `Molly-export-…zip` to analyze usage and ship updates.

Every persistent entity gets a **persona** binding (`CoC` / `PoA` / `Sa` or unassigned). The top-of-window persona switcher is a global filter; the whole UI recolors via CSS custom properties bound to the active persona's palette.

## Repo layout

```
Molly/
├── src/                                  # React frontend
│   ├── App.tsx                           # Top-level routing (switch on ViewKey)
│   ├── main.tsx                          # Vite entry, mounts <App/>
│   ├── components/
│   │   ├── Sidebar.tsx                   # Fixed-width nav with persona-tinted rows
│   │   ├── PersonaSwitcher.tsx           # Top-bar CoC / PoA / Sa / ★All chips
│   │   ├── SayingsBanner.tsx             # Cute rotating sayings (hero + compact)
│   │   ├── RichTextNotes.tsx             # Tiptap wrapper
│   │   ├── ColorPicker.tsx               # color input + swatch row
│   │   ├── ChipMultiSelect.tsx           # multi-select chip group (products, interests)
│   │   ├── KinkChipPicker.tsx            # MasterClipper-style picker for the 349-row kink catalog
│   │   ├── StaleBanner.tsx               # (in views/C4S/) tiered cute "X days old" banner for C4S snapshot freshness
│   │   ├── MoneyInput.tsx                # uncontrolled-display $ input (used by Adhoc, Expenses, Site Wizard)
│   │   ├── ConfirmButton.tsx             # two-tap delete guard
│   │   ├── CheckOffBurst.tsx             # CSS confetti for reminders
│   │   └── AttachmentField.tsx           # File picker + Tauri-backed copy
│   ├── state/
│   │   ├── personas.ts                   # usePersonas hook (active persona + list)
│   │   ├── theme.ts                      # useApplyPersonaTheme (CSS variable swap)
│   │   └── uiTheme.ts                    # light/dark/system + OS media-query subscribe (Phase 15)
│   ├── data/                             # Per-entity SQL wrappers (CRUD + helpers)
│   │   ├── db.ts                         # Shared Database singleton
│   │   ├── personas.ts
│   │   ├── sites.ts
│   │   ├── taxonomy.ts                   # products (+ price/unit) + interests + kinks
│   │   ├── customers.ts                  # VIP, primary_email_index, address, phones, etc.
│   │   ├── customerHistory.ts            # per-customer journal log (BLOB attachments)
│   │   ├── customerSales.ts              # per-customer sale rows (full CRUD)
│   │   ├── clips.ts
│   │   ├── schedules.ts
│   │   ├── occurrences.ts                # + materializer + listOccurrencesInRange (calendar)
│   │   ├── income.ts                     # adhoc + site + listAdhocUnified (customer sales merge)
│   │   ├── expenses.ts                   # one-off + recurring + materializer
│   │   ├── socialPlatforms.ts
│   │   ├── socialPromos.ts
│   │   ├── mollysLog.ts                  # global creator journal (BLOB attachments)
│   │   ├── c4sClips.ts                   # C4S snapshot — list / aggregates / last-imports + invoke wrappers
│   │   ├── holidays.ts                   # Phase 14 — holidays (fixed + nth-weekday)
│   │   ├── contentTags.ts                # Phase 14 — global tag taxonomy + per-bundle/per-fan-day/per-clip links + date-range queries for Calendar overlays
│   │   ├── reddit.ts                     # Phase 15 — subreddits + posts + captions (persona-scoped)
│   │   ├── hours.ts                      # Phase 15 — clock sessions + totals + reward milestones
│   │   ├── dailyTasks.ts                 # Phase 15 — daily to-do (keyed by for_date + persona)
│   │   └── sayings.ts                    # 1000 strings, generated from sayings.md
│   ├── lib/
│   │   ├── csv.ts                        # RFC 4180 parser (60 lines, no papaparse)
│   │   ├── csvPipe.ts                    # Pipe-delimited variant for C4S exports (multi-line quoted descriptions)
│   │   ├── c4sClassify.ts                # Performers → persona-code helper for import-wizard auto-detect
│   │   ├── markdownLite.ts               # Block + inline parser for USER_MANUAL.md (port of PurpleLife SecurityDocView.swift)
│   │   ├── salesReport.ts                # generic sales-report parser
│   │   ├── cadence.ts                    # 6 cadence kinds + nextOccurrencesAfter
│   │   ├── money.ts                      # fmtMoney / parseMoney / month helpers
│   │   ├── uid.ts                        # nextCustomerUid (YYYY-MM-DD-#####)
│   │   ├── holidayResolver.ts            # Phase 14 — fixed + nth-weekday → ISO date, monthly map for Calendar
│   │   ├── hoursFmt.ts                   # Phase 15 — HH:MM:SS + "Xh Ym" formatters (extracted for vitest)
│   │   └── useAsyncRefresh.ts            # Race-safe data-loading hook
│   └── views/
│       ├── Home/                         # Dashboard
│       ├── MollysLog/                    # 📔 Captain's-log-style personal journal (1.7.0+)
│       ├── Reminders/                    # Today / Upcoming / Overdue + Schedules tab
│       ├── Calendar/                     # Month grid (clips + 🔔 reminders) + Clip detail modal
│       ├── Clips/                        # Imported clip list (sort dir + status filter + regex search)
│       ├── C4S/                          # 🛍️ Read-only C4S catalog snapshot (Dashboard / Grid / Detail / Import wizard / StaleBanner)
│       ├── Manual/                       # 💌 In-app USER_MANUAL.md viewer (markdownLite parser + persona-tinted blocks + right-rail TOC)
│       ├── Customers/                    # CRM — editor + history+sales timeline
│       ├── MollyHelper/                  # Site launcher
│       ├── Promos/                       # Social promo tracker
│       ├── Income/                       # Adhoc (now unifies customer sales) / Site wizard / Sales report
│       ├── Expenses/                     # List / Recurring
│       ├── Reports/                      # MTD / YTD / Promos
│       ├── Import/                       # MasterClipper CSV importer
│       ├── Reddit/                       # Phase 15 — 🔴 daily ops hub: Today / Subreddits / Post log / Captions / Hours
│       └── Settings/                     # Personas / Appearance / Sites / Platforms / Products / Interests / Kinks / C4S / Bundler / ContentTags / Notes / Holidays / Rewards / Security / ATW / Data / Updates / Backup
├── src-tauri/                            # Rust backend
│   ├── src/
│   │   ├── main.rs                       # Windows-subsystem shim, calls run()
│   │   ├── lib.rs                        # Tauri Builder, plugin wiring, migrations, command list, camelCase contract tests
│   │   ├── backup.rs                     # Auto-backup-on-launch + Test / Restore
│   │   ├── export.rs                     # Full-data zip export + dev-only import
│   │   ├── attachments.rs                # Receipt file save / reveal / open
│   │   ├── history.rs                    # add_history_entry_with_attachment + download_history_attachment (rusqlite BLOB I/O)
│   │   ├── log.rs                        # add_log_entry_with_attachment + download_log_attachment (Molly's Log)
│   │   ├── c4s.rs                        # replace_c4s_clips (atomic overlay) + delete_all_c4s_data + count-verify
│   │   ├── masterclipper.rs              # MasterClipper external-DB read helpers (clip dedup feed)
│   │   ├── bundles.rs                    # Content / YouTube / Custom / Fan-Site bundle CRUD + validation engine + publish
│   │   ├── bundle_zip.rs                 # ZIP composition for published bundles (Video/, Photos/, FanSite/, info.md, Molly.log)
│   │   ├── crypto/                       # Phase 10 keystore: passphrase-derived KEK wrapping per-install DEK
│   │   │   ├── mod.rs / wrap.rs          # AES-256-GCM wrap/unwrap helpers + roundtrip tests
│   │   │   └── keystore.rs               # init / unlock / change_passphrase / wipe + rate-limited unlock
│   │   ├── site_credentials.rs           # Phase 11 primary + sub-credentials per site, encrypted via Phase 10 keystore
│   │   ├── atw.rs                        # ATW Repost runner + log + status; spawns Sallie's bot binary
│   │   ├── atw_setup.rs                  # ATW credential capture + tester (idempotent)
│   │   ├── atw_settings.rs               # ATW preferences (cadence, pause, log path)
│   │   ├── background_jobs.rs            # Phase 12 generic scheduler (jobs, run-log, next_run_at), powers ATW
│   │   ├── notes.rs                      # Phase 13 Notes: folders, notes, tags, attachments, search + find, exports
│   │   ├── holidays.rs                   # Phase 14 — fixed + nth-weekday holidays, US default reset
│   │   ├── content_tags.rs               # Phase 14 — content_tags_def CRUD + bundle/fan-day/clip link tables + Calendar-range queries
│   │   ├── reddit.rs                     # Phase 15 — subreddits + post log + captions (persona-scoped)
│   │   ├── hours.rs                      # Phase 15 — clock sessions + totals (today/week/month/all) + reward milestones (global)
│   │   ├── daily_tasks.rs                # Phase 15 — daily to-do list (keyed by for_date + persona)
│   │   └── fsutil.rs                     # ~/Downloads/<sub> resolution + Finder reveal
│   ├── migrations/                       # 38 migrations (run automatically on launch)
│   │   ├── 001_init.sql                  # personas + app_settings
│   │   ├── 002_sites.sql                 # site entries, preloaded
│   │   ├── 003_taxonomy.sql              # products + interests
│   │   ├── 004_customers.sql             # customers + many-to-many joins (products, interests, kinks)
│   │   ├── 005_clips.sql                 # imported clip rows + import audit
│   │   ├── 006_schedules.sql             # schedules + occurrences
│   │   ├── 007_income.sql                # income_adhoc + income_site
│   │   ├── 008_expenses.sql              # expenses + expenses_recurring
│   │   ├── 009_social.sql                # platforms + promos
│   │   ├── 010_kinks.sql                 # kinks (third taxonomy) + customer_kinks join
│   │   ├── 011_kinks_preload.sql         # description col + customer_kinks.position + 349 default kinks
│   │   ├── 012_products_and_customer_fields.sql  # products: price_cents+unit; customers: VIP, primary_email_index, address, phones
│   │   ├── 013_customer_history.sql      # customer_history (append-only) + BLOB attachment column
│   │   ├── 014_customer_sales.sql        # customer_sales (editable) — product_id RESTRICT, customer_uid CASCADE
│   │   ├── 015_mollys_log.sql            # mollys_log (global journal) + BLOB attachment column
│   │   ├── 016_c4s_clips.sql             # c4s_clips snapshot + c4s_imports audit; persona_code CHECK-locked to CoC|PoA
│   │   ├── 017_bundles.sql               # bundles, bundle_files, bundle_fan_days, bundle_archives, bundle_categories, bundler_settings, bundle_prohibited_words
│   │   ├── 018_crypto_keystore.sql       # keystore (wrapped DEK + KDF params + version + failed-unlock counter)
│   │   ├── 019_site_credentials.sql      # site_credentials (primary + sub) + last_rotated + encrypted password blob
│   │   ├── 020_background_jobs.sql       # jobs + job_runs + next_run_at index
│   │   ├── 021_keystore_stay_unlocked.sql # session "stay unlocked" flag for trusted desktops
│   │   ├── 022_job_run_log_path.sql      # job_runs.log_path (per-run captured stdout/stderr file)
│   │   ├── 023_notes.sql                 # note_folders, notes, note_tags_def (6 built-in), note_tag_links, note_attachments
│   │   ├── 024_note_font_size.sql        # notes.font_size_pt (user-adjustable per-note + per-app default)
│   │   ├── 025_holidays.sql              # Phase 14 — holidays (fixed + nth-weekday) + 18 US defaults + calendar.holidaysEnabled
│   │   ├── 026_content_tags.sql          # Phase 14 — content_tags_def + bundle_tag_links + 8 builtin tags
│   │   ├── 027_fanday_tags.sql           # Phase 14 PR3 — bundle_tag_links recreated with nullable fan_day_id (partial unique indexes)
│   │   ├── 028_clip_tags.sql             # Phase 14 PR4 — clip_tag_links (clips only — c4s_clips excluded)
│   │   ├── 029_subreddits.sql            # Phase 15 — content_tags_def +5 builtins, subreddits / subreddit_posts / captions, 33 CoC seed
│   │   ├── 030_hours.sql                 # Phase 15 — clock_sessions (NULL duration_ms = open) + reward_milestones (global)
│   │   ├── 031_daily_tasks.sql           # Phase 15 — daily_tasks keyed by for_date + persona
│   │   ├── 032_drop_content_release_defaults.sql # Phase 15 — DELETE the seeded weekly 'CoC/PoA content release' rows by name+persona
│   │   ├── 033_ui_theme.sql              # Phase 15 — app_settings ('ui.theme', 'light') seed
│   │   ├── 034_return_file_import.sql    # v1.20.0 — bundles.completed_at/delete_after + bundle_postings + bundle_posting_files + return_file_imports
│   │   ├── 035_social_drops.sql          # v1.21.0 — Social hub daily piggy-bank (social_platforms.daily_goal + social_drops)
│   │   ├── 036_youtube_bundle.sql        # v1.23.0 — bundles.bundle_kind discriminator (safe ALTER; escapes the bundle_type CHECK trap)
│   │   ├── 037_social_followers.sql      # v1.25.0 — daily follower-count snapshots + per-platform goal
│   │   └── 038_bundle_preview_assets.sql # v1.26.0 — optional thumbnail + teaser GIF columns on bundles (single-slot, like audio)
│   ├── icons/                            # Generated icon set (from molly.svg)
│   ├── capabilities/default.json         # Tauri ACL — which plugin commands the frontend can invoke
│   ├── tauri.conf.json
│   └── Cargo.toml
├── public/molly.svg                       # In-window favicon
├── install.sh                             # Mac: copy .app to /Applications + relaunch
├── build-app.sh                           # Mac: pnpm tauri build → install.sh
├── run-tests.sh                           # cargo test wrapper
├── .github/workflows/release-molly.yml   # Repo-root workflow → signed .dmg + .exe on molly-v* tag
├── README.md
├── USER_MANUAL.md
├── HANDOFF.md                             # this file
├── DESIGN.md                              # theming + UX choices
├── INSTALL.md                             # Sallie-friendly install + export instructions
├── PHASE_8_PARSERS.md                     # deferred per-site parser plan
├── ROADMAP.md                             # living brainstorm of next ideas + opinionated slates
├── OUT_OF_SCOPE.md                        # what we won't build
└── CHANGELOG.md
```

## Data flow

1. **Migrations** run on app launch via `tauri-plugin-sql::Builder::add_migrations`. New schema = new file in `migrations/` + entry in `lib.rs::run()`.
2. **DB writes** go through `data/<entity>.ts` typed wrappers, never raw SQL in views.
3. **DB reads** also through `data/<entity>.ts` — most expose a `list*` function and a few `count*` / aggregate helpers for dashboards.
4. **List views** consume `useAsyncRefresh` (race-safe loading + alive guards). Editors call back via `refresh()` returned from the hook.
5. **Persona filter**: every entity that has a `persona_code` accepts an `active.code` argument in its list query; views read the active persona from `usePersonas()`.

## Tauri command surface

All cross-boundary types use `#[serde(rename_all = "camelCase")]` — enforced by the `camel_case_contract` cargo tests. Commands by area:

| Module | Commands |
|---|---|
| backup | `run_backup_now`, `list_backups`, `test_backup`, `restore_backup`, `reveal_backup_dir`, `reveal_path`, `get_backup_settings`, `set_backup_settings` |
| attachments | `save_attachment`, `delete_attachment`, `reveal_attachment`, `open_attachment` |
| export | `export_full_data`, `reveal_export_dir`, `import_full_export` |
| history | `add_history_entry_with_attachment`, `download_history_attachment` (rusqlite BLOB I/O — bytes never cross IPC) |
| log | `add_log_entry_with_attachment`, `download_log_attachment` (rusqlite BLOB I/O for Molly's Log) |
| c4s | `replace_c4s_clips` (atomic overlay-replace + count-verify), `delete_all_c4s_data` |
| bundles | `create_bundle`, `update_bundle_fields`, `save_bundle_file`, `save_bundle_gif`, `save_bundle_frame`, `file_size`, `write_bytes_to_path`, `delete_bundle_file`, `reorder_bundle_files`, `set_bundle_categories`, `list_bundles`, `get_bundle`, `delete_bundle_draft`, `publish_bundle`, `delete_published_bundle`, `list_bundle_archives`, `reveal_bundles_dir`, `open_bundle_archive`, `auto_purge_old_bundles`, `get_bundler_settings`, `set_bundler_settings`, `list_prohibited_words`, `add_prohibited_word`, `remove_prohibited_word`, `create_fan_day`, `update_fan_day_message`, `delete_fan_day` |
| keystore (crypto) | `keystore_status`, `keystore_init`, `keystore_unlock`, `keystore_lock`, `keystore_change_passphrase`, `keystore_wipe`, `keystore_set_stay_unlocked` — passphrase-derived KEK wrapping a per-install DEK, rate-limited unlock counter. |
| site_credentials | `list_site_credentials`, `create_site_credential`, `update_site_credential`, `set_site_credential_password`, `clear_site_credential_password`, `set_site_credential_primary`, `delete_site_credential` — primary + sub credentials per site, encrypted via the Phase 10 keystore. |
| background_jobs | `list_jobs`, `get_job`, `update_job_cadence`, `set_job_paused`, `run_job_now`, `list_job_runs`, `read_job_run_log`. Scheduler ticks in `App.tsx` on launch + every 30 minutes, dispatched into `atw.rs`. |
| atw | `atw_run_now`, `atw_status`, `atw_capture_credentials`, `atw_test_credentials`, `get_atw_settings`, `set_atw_settings` — wraps Sallie's external `atw-repost-bot` binary; creds come from the keystore. |
| masterclipper | `read_masterclipper_clips` — dedupes against MasterClipper's external SQLite (used by the import wizard). |
| notes | 28 commands across folders / notes / tags / attachments / search / find / export. Key ones: `list_folders`, `create_folder`, `rename_folder`, `move_folder`, `delete_folder`; `list_notes`, `get_note`, `create_note`, `update_note`, `delete_note`, `copy_note`; `list_tags`, `create_tag`, `update_tag`, `delete_tag`, `set_note_tags`; `add_note_attachment`, `download_note_attachment`, `delete_note_attachment`; `search_titles`, `find_in_bodies`; `export_note_md`, `export_note_docx`, `export_note_pdf`, `reveal_notes_export_dir`; `get_notes_defaults`, `set_notes_defaults`. |
| holidays (Phase 14) | `list_holidays`, `create_holiday`, `update_holiday`, `set_holiday_enabled`, `delete_holiday`, `reset_holidays_to_us_defaults` — fixed-date + nth-weekday rules with primary + secondary + text colors; reset preserves `source='custom'` rows. |
| content_tags (Phase 14) | `list_content_tags`, `create_content_tag`, `update_content_tag`, `delete_content_tag`; `list_bundle_tags`, `set_bundle_tags`; `list_fan_day_tags`, `set_fan_day_tags`, `list_fansite_day_tags_in_range`; `list_clip_tags`, `set_clip_tags`, `list_clip_tags_in_range`. Bundle-level tags use `fan_day_id IS NULL` so FanSite per-day tags can coexist on the same bundle; both range queries power Calendar overlays. |
| reddit (Phase 15) | `list_subreddits`, `create_subreddit`, `update_subreddit`, `set_subreddit_starred`, `set_subreddit_verified`, `delete_subreddit`, `mark_subreddit_posted` (flips rotation→'wait' + stamps + creates post log row); `list_subreddit_posts_in_range`, `create_subreddit_post`, `delete_subreddit_post`; `list_captions`, `create_caption`, `update_caption`, `delete_caption`. |
| hours (Phase 15) | `hours_start_session` (auto-closes previous open session), `hours_stop_session`, `hours_list_sessions`, `hours_delete_session`, `hours_totals` (today/week/month/all-time + open-session live portion, tz_offset_min anchors the local-day windows); `list_reward_milestones`, `create_reward_milestone`, `update_reward_milestone`, `delete_reward_milestone` (global, multiple goals). |
| daily_tasks (Phase 15) | `list_daily_tasks` (filtered by `for_date`), `create_daily_task`, `complete_daily_task`, `undo_daily_task`, `delete_daily_task`. |

ACL is in `src-tauri/capabilities/default.json`; this is the file that bit us in v0.6.0 (SQL `execute` was missing from the allowlist and writes failed silently).

## Background work

Two recurring jobs run in `App.tsx` on launch + every 30 minutes:

1. `materializeOccurrences()` — walk active schedules and INSERT OR IGNORE the next 60 days of `occurrences`.
2. `materializeRecurringExpenses()` — walk active `expenses_recurring` from each row's `last_material` to today, INSERT OR IGNORE materialized expense rows.

Both are idempotent (UNIQUE indexes on the target tables) so re-runs are no-ops.

Backup also runs on launch via `setup` in `lib.rs::run()`, deduped to once-per-5-min.

Bundle **auto-purge** also runs on launch (Phase 9). `bundles::auto_purge_on_launch` is spawned alongside the backup task, debounced to once-per-day. Reads `BundlerSettings`; if `auto_purge_enabled && purge_threshold_days > 0`, deletes the on-disk ZIP for any published bundle older than the threshold and flips its `state` to `purged`. Fail-quietly contract: logs via `eprintln!`, never panics. Bundle row is kept for history; only the ZIP goes.

## Build / install / release

- **Dev**: `pnpm tauri dev` (hot-reload Vite + Tauri).
- **Mac local install**: `./build-app.sh` → builds + chains into `install.sh` → app lands in `/Applications/Molly.app`.
- **Signed release**: push a `molly-vX.Y.Z` git tag. `.github/workflows/release-molly.yml` builds + signs both platforms, uploads to a draft release, then `publish-feed` composes and uploads `latest.json`.

Updater is wired against `https://github.com/bronty13/PhantomLives/releases/download/molly-updater-feed/latest.json` (a dedicated Molly-scoped prerelease, so a SideMolly release becoming GitHub's "latest" can't 404 the feed) using a minisign public key in `tauri.conf.json`. The private key lives at `~/.config/molly-secrets/updater.key` (gitignored) and as the GitHub secret `TAURI_SIGNING_PRIVATE_KEY`. **Windows uses the raw NSIS `setup.exe`** as the updater artifact (signed directly via `tauri signer sign`); `latest.json`'s `windows-x86_64.url` points at the `.exe`, never a `.nsis.zip` — the zip path tripped `tauri-plugin-updater`'s `zip` reader ("Compression method not supported"). macOS uses the `.app.tar.gz`.

## Sharp edges worth remembering

- **camelCase serde** — every boundary struct needs `#[serde(rename_all = "camelCase")]`. See `lib.rs::camel_case_contract`.
- **pnpm-workspace.yaml needs `packages: []`** even though Molly is single-package — pnpm parses any workspace file as a workspace declaration.
- **CI Node + pnpm in lockstep** — pnpm 11 requires Node 22.13+, otherwise `node:sqlite` blows up.
- **tauri-action's matrix updater story is broken** — we bypass it and call `tauri build` + `tauri signer sign` + `gh release upload` ourselves. See `release-molly.yml`. Mac: re-codesign the `.app`, re-tar to `.app.tar.gz`, sign. Windows: sign the raw `setup.exe` directly — **do NOT `Compress-Archive` it into a `.nsis.zip`**; that archive's compression is rejected by the installed updater's `zip` reader at install time (`unsupported Zip archive: Compression method not supported`). The v2 Windows updater runs the raw signed `.exe`.
- **`refresh()` race protection** — anything that fires on persona change should use `useAsyncRefresh` to avoid stale-data clobber.
- **App data location**: `~/Library/Application Support/com.phantomlives.molly/` (Mac), `%APPDATA%\com.phantomlives.molly\` (Windows). Everything Molly knows lives there.
- **Never edit a shipped migration's bytes** — `tauri-plugin-sql` SHA-hashes every migration on first apply and refuses to open the DB if a previously-applied migration's content ever changes (`migration N was previously applied but has been modified`). To remove or rename seed data, **write a new migration** that does the DELETE / UPDATE. Cost us v1.17.0 → had to ship a hotfix v1.17.1 that restored 006_schedules.sql to its byte-exact original and leaned on migration 032 to do the actual deletion. Lesson re-pinned here on purpose.
- **Can't widen a CHECK constraint in a migration — use a new unconstrained column instead.** `bundles.bundle_type` has `CHECK (bundle_type IN ('content','custom','fansite'))`. Relaxing a CHECK requires rebuilding the table, but `bundles` is the parent of six `ON DELETE CASCADE` children. Inside a `tauri-plugin-sql` migration `foreign_keys` is forced ON (sqlx default) and the script runs in a transaction where `PRAGMA foreign_keys` / `legacy_alter_table` / `defer_foreign_keys` are **all no-ops** (verified empirically — the rebuild silently cascade-deletes the children). v1.23.0's YouTube type therefore added `bundle_kind` via a plain `ALTER TABLE ADD COLUMN` (migration 036) and made it the authoritative discriminator: Rust reads `COALESCE(bundle_kind, bundle_type) AS bundle_type` everywhere, YouTube rows store `bundle_type='content'` + `bundle_kind='youtube'`. **Any future bundle type goes in `bundle_kind` — never touch the `bundle_type` CHECK.** `BundleType::YouTube` shares Content's ZIP layout (Video/ + Audio/) minus categories.
- **GIF Studio = native ffmpeg, not the WebView** (1.29.0+; see the section below). All decode/encode is the bundled ffmpeg in `src-tauri/src/media/` — the WebView only previews/scrubs. Don't reintroduce canvas-based encoding (Windows WebView2 can't decode HEVC; ffmpeg-WASM is too slow). When editing the engine, the dev Mac's Homebrew ffmpeg may lack zimg (no `zscale`) so the HDR tone-map silently degrades locally — the bundled CI build always has zimg (guardrail). The real HDR/Windows test is the shipped build on Sallie's iPhone footage.
- **Every ffmpeg/ffprobe spawn MUST go through `media::no_window(&mut cmd)`** (1.29.3+). The bundled binaries are console-subsystem `.exe`s; spawned bare from the GUI process they flash a black console window over the UI on Windows for the whole render. `no_window` sets `CREATE_NO_WINDOW` on Windows, no-op elsewhere. There are three spawn sites (`engine.rs`, `probe.rs`, `ffmpeg_path.rs`) — any new one needs the same call. **Encode speed**: teaser MP4 uses x264 `-preset veryfast` (not `medium`) — CRF 20 fixes the quality so the faster preset just trades a bit of size (within the 100 MB maxrate budget) for a big speedup. `-hwaccel` decode is the next lever but is HDR-risky; verify on Windows before enabling.
- **Calendar overlay query date format** — Rust `printf('%04d-%02d-%02d', year, month, day)` matches the JS `isoDateKey()` zero-pad shape. If you tweak either side, the other has to keep up — there's a test in `content_tags::tests::range_query_resolves_dates_and_filters_by_persona` that pins this.

## GIF Studio / teaser pipeline (1.27–1.29) — Windows codec realities

`src/views/GifStudio/` turns a source video into a teaser **GIF** (`encodeGif.ts`,
`gifenc`), an **MP4** clip (`recordMp4.ts`), or a single **thumbnail** frame
(`FrameGrabber.tsx`). All three share one pipeline: load the source into a
`<video>`, draw frames (trim + crop + caption) onto a 2D `<canvas>`, then read
pixels off that canvas. Entry points: `GifCreator.tsx`, `FrameGrabber.tsx`,
embedded from `ContentBundleForm.tsx` (which passes `bundleVideos` filtered to
`kind === 'video'`). `sourceUrl.ts` loads the source; `read_file_bytes`
(bundles.rs) streams the bytes over the raw binary IPC channel.

This area is a minefield because **macOS WebKit and Windows WebView2 (Chromium)
differ on exactly the two things it depends on**: canvas origin-clean rules and
video codec support. The maintainer is on macOS; the only user (Sallie) is on
Windows and shoots **everything on an iPhone**. So "works on my Mac" means
almost nothing here — every change in this folder needs a Windows test.

The 1.28.x journey (read before touching this code):

1. **Corrupt MP4 on Windows (1.28.0).** MP4 came from the browser's
   `MediaRecorder`, which on WebView2 writes the `moov`/duration atom at the
   *end* in a streaming layout — Windows' native players reject it. Fixed by
   encoding H.264 with **WebCodecs** + muxing a fast-start MP4 with
   **`mp4-muxer`** (`fastStart: 'in-memory'`, `firstTimestampBehavior: 'offset'`).
2. **Tainted-canvas `SecurityError` (1.28.0→1.28.2).** The source `<video>` was
   loaded via `convertFileSrc` (Tauri asset protocol) — a **cross-origin**
   source with no CORS header (tauri-apps/tauri#12999). Drawing it taints the
   canvas, and on Windows a tainted canvas blocks *every* pixel op
   (`getImageData` → GIF, `VideoFrame`/`captureStream` → MP4, `toBlob` →
   thumbnail). Fixed by loading the source from a **same-origin `blob:` URL**
   (`loadVideoObjectUrl` → `read_file_bytes` → `Blob`). `crossOrigin="anonymous"`
   is NOT an option (Tauri can't send the matching ACAO header).
3. **`.mov` MIME regression (1.28.3).** Labelling the blob `video/quicktime`
   makes Chromium refuse it; only set explicit types for `mp4`/`webm` and leave
   the rest blank so the engine sniffs the bytes.

### Resolution: native ffmpeg media engine (1.29.0, shipped)

Sallie's iPhone footage is **HEVC / H.265** (Apple "High Efficiency"; often
Dolby Vision HDR), whether the container is `.mov` or `.mp4`. **WebView2 has no
HEVC decoder**, so the WebView pipeline was a dead end; **ffmpeg-WASM was too
slow** (minutes on an M5 Max — single-threaded software HEVC decode). The
1.28.x WebView fixes (WebCodecs mux, same-origin blob, `.mov` MIME) and the
brief ffmpeg-WASM attempt were all removed.

**Now: a bundled native ffmpeg engine in `src-tauri/src/media/`** does all
decode/encode. Layers: `filters.rs` (pure argv/filtergraph builders, fully
unit-tested), `probe.rs` (ffprobe → dims/duration/HDR/audio), `engine.rs`
(spawn + `-progress` parse + timeout + stderr tail), `ffmpeg_path.rs`
(bundled → Settings override → PATH discovery + `supports_zscale`), `temp.rs`
(job dirs + proxy cache), `commands.rs` (`probe_video`, `make_preview_proxy`,
`generate_gif`, `generate_teaser_mp4`, `grab_frame`, `shrink_video`). It input-seeks the
original (`-ss` before `-i`), tone-maps HDR→SDR via zscale **only when HDR is
detected** (degrades if the ffmpeg lacks zimg), and renders the caption as a
transparent PNG composited via `overlay` (no libfreetype needed — the failure
SideMolly hit). The preview `<video>` is scrub-only (never canvassed), so it
uses `convertFileSrc`; undecodable sources get a low-res H.264 proxy
(`make_preview_proxy`) while output is rendered from the original.

The **🫧 Squish** tab (`src/views/Squish/`, 1.34.0+) shrinks a *whole* video
under a byte budget (Slack's 1 GB) via the same engine. Two design notes set it
apart from the GIF/teaser commands: (1) `shrink_video` **writes straight to a
file** in `~/Downloads/Molly/` and returns only metadata — it must NOT return
the (up to ~1 GB) bytes over IPC like the teaser does; (2) it computes the
budget-derived `-maxrate` in Rust (`filters::size_budget_video_kbps`, the
generalized form of `teaser_video_max_kbps`) and fits a `shrink_box` Full-HD box
with `force_original_aspect_ratio=decrease` so a rotation-flagged portrait clip
never distorts.

ffmpeg/ffprobe are **GPL static builds**, CI-downloaded (BtbN win64 / OSXExperts
arm64), verified (arch + zscale + libx264), shipped via `bundle.resources`
(`resources/ffmpeg/*`, gitignored, ~+80–100 MB/installer) — sealed by the
existing ad-hoc `codesign --deep` (no notarization to trip on). See
`THIRD_PARTY_LICENSES.md`. The engine/filters/probe layers are intentionally
Tauri-light so they can lift into a shared `phantomlives-media` crate when
**SideMolly merges into Molly** (SideMolly already has a system-ffmpeg pipeline
in `video.rs`/`thumbnails.rs`; this is the bundled superset).

## Tests

`./run-tests.sh` runs **Rust + frontend** end-to-end (`cargo test --lib` then `pnpm test`). **214 Rust + 166 frontend = 380 tests total** as of 1.17.1. In non-TTY environments, prefix with `CI=true` so pnpm's modules-purge prompt is skipped.

**Rust (214)**:
- `backup.rs::tests` (7) — debounce, retention prefix guard, listing order, verify-missing-DB, auto-create target dir.
- `lib.rs::camel_case_contract` — every boundary struct serializes camelCase (Settings / BackupRow / VerifyResult / AttachmentInfo / ExportResult / HistoryEntryRef / LogEntryRef / BundleRef / FanDayRef / JobRow / JobRunRow / NoteRef / NoteFolderRef / NoteTagRef / NoteAttachmentRef / etc.). Every PR adds a contract test for any new return type — see PR-policy in `OUT_OF_SCOPE.md`.
- `lib.rs::migration_smoke::all_migrations_apply_cleanly` — applies every shipped migration to a fresh in-memory SQLite, asserts anchor tables exist, asserts migration 011 preloaded ≥349 kinks.
- `history.rs::tests` (3) — BLOB round-trips byte-for-byte; missing-id errors out; FK enforcement rejects orphan rows. Pure helpers (`insert_history_row`, `read_history_blob`) are extracted from the Tauri commands so they're testable without `AppHandle`.
- `log.rs::tests` (3) — same shape: round-trip + missing-id + empty-body/zero-byte BLOB edge case.
- `c4s.rs::tests` (3) — atomic replace, per-persona overlay isolation, empty-rows-clears semantics.
- `bundles.rs::tests` — Content/Custom/FanSite validation + `days_in_month` + custom-delivery mutex + fan_day CRUD/cascade.
- `bundle_zip.rs::tests` — bundle ZIP layout + path-renaming + safe-name fallback.
- `masterclipper.rs::tests` (2) — missing-DB returns empty, fixture reads back uppercased + dedup-sorted.
- `crypto::wrap::tests` — AES-256-GCM roundtrip incl. large blob.
- `crypto::keystore::tests` (6) — init / unlock happy path, init-twice rejected, wipe → uninitialized, change-passphrase preserves DEK, import rotates + bumps version, wrong-passphrase rate-limited.
- `site_credentials.rs::tests` (8) — create+list, cannot-delete-last-credential, backfill primary-per-site, cascade on site delete, set-primary clears others + mirrors username, set/clear password, update-primary syncs sites.username, update-secondary doesn't.
- `background_jobs.rs::tests` — create / list / mark-ran advances `next_run_at`, delete cascades runs, run-log path round-trips.
- `notes.rs::tests` (22) — six built-in tags seeded, user-tag deletable but built-in not; folder create+list+rename, folder move-into-self rejected, delete-folder cascades notes; note create/update/get round-trip, note copy carries tags; per-note style overrides persist, defaults seeded from migration + save/load round-trip; search titles plain substring + regex; find-in-bodies returns line numbers, caps at 5 per note.
- `fsutil::tests` (1) — `downloads_subdir` resolution contract.
- `holidays::tests` (7) — seed loads ≥17 US defaults, create round-trip, validator rejects bad inputs, update preserves source, set-enabled flips, delete works, reset preserves custom rows + reverts edits.
- `content_tags::tests` (16) — 8 builtins seeded, create validates, builtin undeletable but renameable, set_bundle_tags round-trip, FK cascades on bundle delete + on tag delete; per-day FanSite tags: bundle-level set doesn't touch day-level, day-level set replaces only that day, deleting a fan_day cascades day tags, range query resolves dates + filters by persona; clip tags: set/list round-trip, deleting a clip cascades, mirror_bundle_tags_to_clip copies only bundle-level (not day-level), clip range query resolves YYYY-MM-DD slice + filters by persona.
- `reddit::tests` (10) — seed loads 33 CoC subs, list filters by persona, `r/` prefix stripped on create, blank/bad-rotation rejected, unique per persona but cross-persona dup OK, star+verify toggle, mark_posted flips rotation + creates post row, bad date / missing sub errors, future+past dates supported, deleting a sub keeps post history via SET NULL, caption CRUD with trim + empty rejection.
- `hours::tests` (8) — start/stop round-trip, stop-without-open errors, start-when-open auto-closes previous, delete session, totals window math (today/week/month/all-time), open-session running portion included in totals, milestone CRUD + validation, list ordered by ascending hours.
- `daily_tasks::tests` (5) — create/list round-trip, previous-day tasks filtered out of today, complete/undo/delete cycle, input validation (text/date/category), unfinished-first ordering.

**Frontend (166, vitest)** — 12 test files in `src/lib/*.test.ts`:
- `money.test.ts` (10) — `parseMoney` / `fmtMoney` incl. the trailing-decimal-point case the MoneyInput pattern depends on.
- `phone.test.ts` (14) — `formatUSPhone` partials + canonical + extension; `isValidUSPhone` + `usPhoneDigits` covering the +1 strip.
- `cadence.test.ts` (17) — `nextOccurrencesAfter` across all six cadence kinds (daily, weekly, biweekly w/ anchor, monthly_dom w/ clamp, monthly_days_before_next, monthly_days_after_eom, every_n_days) + the date helpers.
- `uid.test.ts` (3) — `formatDateKey` Y-M-D shape + zero-pad.
- `csvPipe.test.ts` (13) — generic CSV pipe parsing used by the sales-report importer.
- `c4sClassify.test.ts` (6) — C4S category classification rules.
- `reorderHelpers.test.ts` (7) — array-reorder math used by drag-handles + kinks editor.
- `bundleValidation.test.ts` (32) — mirror of Phase 9 Rust rules end-to-end (Content / Custom / Fan-Site).
- `bundleUid.test.ts` (5) — bundle UID generation contract.
- `markdownLite.test.ts` (12) — markdown-lite renderer used by Notes export to MD + the bundle `info.md` composer.
- `holidayResolver.test.ts` (20) — isoDateKey + daysInMonth + nth-weekday math (MLK, Memorial Day, Thanksgiving, Mother's Day, Labor Day) + resolveHolidayForMonth (month-mismatch, disabled, clamping, fixed, nth_weekday) + resolveHolidaysForMonth grouping/filtering/empty.
- `hoursFmt.test.ts` (10) — `fmtClock` zero-pad + multi-hour + negative-clamp; `fmtHM` boundary (60 min → "1h 0m") + floor-don't-round (59m 59.999s stays "59m") + negative-clamp.

**Still untested** (deliberate per `OUT_OF_SCOPE.md`):
- `attachments.rs` file save / reveal / open.
- `export.rs` zip composition + dev-only import.
- React component rendering / state transitions (e.g. `CustomerEditor`, `MollysLogView`, `AdhocIncomeView`).

## Reference patterns from elsewhere in PhantomLives

- `BackupService` (Mac) → ported to Rust in `src-tauri/src/backup.rs`. Same retention / debounce / verify rules.
- `Cadence` (PurpleTracker) → ported to TS in `src/lib/cadence.ts` with the same six kinds.
- `IDGeneratorService` (MasterClipper) → `nextCustomerUid` in `src/lib/uid.ts`.
- `Theme` (Timeliner) → CSS variable approach in `src/state/theme.ts`.
- `PurpleImport` (PurpleLife) → not yet ported. See `PHASE_8_PARSERS.md`.

## Where to start a 1.0.x bug fix

1. Reproduce on dev: `pnpm tauri dev`.
2. Find the relevant view in `src/views/`.
3. If it's a data issue, check the SQL in `data/` and any migration that defines the schema.
4. If it's an "undefined / NaN" bug, the suspect is almost always a missing `#[serde(rename_all = "camelCase")]` on a Rust struct. Add it. Add a test in `camel_case_contract`.
5. Bump patch version, update CHANGELOG, build, install, ping Sallie.
