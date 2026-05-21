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
│   │   ├── MoneyInput.tsx                # uncontrolled-display $ input (used by Adhoc, Expenses, Site Wizard)
│   │   ├── ConfirmButton.tsx             # two-tap delete guard
│   │   ├── CheckOffBurst.tsx             # CSS confetti for reminders
│   │   └── AttachmentField.tsx           # File picker + Tauri-backed copy
│   ├── state/
│   │   ├── personas.ts                   # usePersonas hook (active persona + list)
│   │   └── theme.ts                      # useApplyPersonaTheme (CSS variable swap)
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
│   │   └── sayings.ts                    # 1000 strings, generated from sayings.md
│   ├── lib/
│   │   ├── csv.ts                        # RFC 4180 parser (60 lines, no papaparse)
│   │   ├── salesReport.ts                # generic sales-report parser
│   │   ├── cadence.ts                    # 6 cadence kinds + nextOccurrencesAfter
│   │   ├── money.ts                      # fmtMoney / parseMoney / month helpers
│   │   ├── uid.ts                        # nextCustomerUid (YYYY-MM-DD-#####)
│   │   └── useAsyncRefresh.ts            # Race-safe data-loading hook
│   └── views/
│       ├── Home/                         # Dashboard
│       ├── MollysLog/                    # 📔 Captain's-log-style personal journal (1.7.0+)
│       ├── Reminders/                    # Today / Upcoming / Overdue + Schedules tab
│       ├── Calendar/                     # Month grid (clips + 🔔 reminders) + Clip detail modal
│       ├── Clips/                        # Imported clip list (sort dir + status filter + regex search)
│       ├── Customers/                    # CRM — editor + history+sales timeline
│       ├── MollyHelper/                  # Site launcher
│       ├── Promos/                       # Social promo tracker
│       ├── Income/                       # Adhoc (now unifies customer sales) / Site wizard / Sales report
│       ├── Expenses/                     # List / Recurring
│       ├── Reports/                      # MTD / YTD / Promos
│       ├── Import/                       # MasterClipper CSV importer
│       └── Settings/                     # Personas / Sites / Platforms / Products / Interests / Kinks / Data / Updates / Backup
├── src-tauri/                            # Rust backend
│   ├── src/
│   │   ├── main.rs                       # Windows-subsystem shim, calls run()
│   │   ├── lib.rs                        # Tauri Builder, plugin wiring, migrations, command list, camelCase contract tests
│   │   ├── backup.rs                     # Auto-backup-on-launch + Test / Restore
│   │   ├── export.rs                     # Full-data zip export + dev-only import
│   │   ├── attachments.rs                # Receipt file save / reveal / open
│   │   ├── history.rs                    # add_history_entry_with_attachment + download_history_attachment (rusqlite BLOB I/O)
│   │   ├── log.rs                        # add_log_entry_with_attachment + download_log_attachment (Molly's Log)
│   │   └── fsutil.rs                     # ~/Downloads/<sub> resolution + Finder reveal
│   ├── migrations/                       # 12 migrations (run automatically on launch)
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
│   │   └── 015_mollys_log.sql            # mollys_log (global journal) + BLOB attachment column
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

ACL is in `src-tauri/capabilities/default.json`; this is the file that bit us in v0.6.0 (SQL `execute` was missing from the allowlist and writes failed silently).

## Background work

Two recurring jobs run in `App.tsx` on launch + every 30 minutes:

1. `materializeOccurrences()` — walk active schedules and INSERT OR IGNORE the next 60 days of `occurrences`.
2. `materializeRecurringExpenses()` — walk active `expenses_recurring` from each row's `last_material` to today, INSERT OR IGNORE materialized expense rows.

Both are idempotent (UNIQUE indexes on the target tables) so re-runs are no-ops.

Backup also runs on launch via `setup` in `lib.rs::run()`, deduped to once-per-5-min.

## Build / install / release

- **Dev**: `pnpm tauri dev` (hot-reload Vite + Tauri).
- **Mac local install**: `./build-app.sh` → builds + chains into `install.sh` → app lands in `/Applications/Molly.app`.
- **Signed release**: push a `molly-vX.Y.Z` git tag. `.github/workflows/release-molly.yml` builds + signs both platforms, uploads to a draft release, then `publish-feed` composes and uploads `latest.json`.

Updater is wired against `https://github.com/bronty13/PhantomLives/releases/latest/download/latest.json` using a minisign public key in `tauri.conf.json`. The private key lives at `~/.config/molly-secrets/updater.key` (gitignored) and as the GitHub secret `TAURI_SIGNING_PRIVATE_KEY`.

## Sharp edges worth remembering

- **camelCase serde** — every boundary struct needs `#[serde(rename_all = "camelCase")]`. See `lib.rs::camel_case_contract`.
- **pnpm-workspace.yaml needs `packages: []`** even though Molly is single-package — pnpm parses any workspace file as a workspace declaration.
- **CI Node + pnpm in lockstep** — pnpm 11 requires Node 22.13+, otherwise `node:sqlite` blows up.
- **tauri-action's matrix updater story is broken** — we bypass it and call `tauri build` + manual tar/zip + `tauri signer sign` + `gh release upload` ourselves. See `release-molly.yml`.
- **`refresh()` race protection** — anything that fires on persona change should use `useAsyncRefresh` to avoid stale-data clobber.
- **App data location**: `~/Library/Application Support/com.phantomlives.molly/` (Mac), `%APPDATA%\com.phantomlives.molly\` (Windows). Everything Molly knows lives there.

## Tests

- **Rust**: `./run-tests.sh` → 16 tests (7 backup + 7 camelCase contract + 1 migration smoke + 1 fsutil).
  - `backup.rs::tests` — debounce, retention prefix guard, listing order, verify-missing-DB, auto-create target dir.
  - `lib.rs::camel_case_contract` — every boundary struct serializes camelCase (Settings / BackupRow / VerifyResult / AttachmentInfo / ExportResult / HistoryEntryRef / LogEntryRef).
  - `lib.rs::migration_smoke::all_migrations_apply_cleanly` — applies every shipped migration to a fresh in-memory SQLite and asserts the expected tables exist. Catches future schema regressions before they touch Sallie's DB.
  - `fsutil::tests::downloads_subdir_resolves_with_sub` — pins the cross-platform `~/Downloads/<sub>` resolution.
- **Known untested surface** (deliberate; see `OUT_OF_SCOPE.md`):
  - `history.rs` / `log.rs` BLOB round-trip behavior (only the return-type contract is tested).
  - `attachments.rs` file save / reveal / open.
  - `export.rs` zip composition + dev-only import.
  - All frontend code — `OUT_OF_SCOPE.md` says deferred to Phase 8.5 hygiene pass.

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
