# SideMolly — Architecture Handoff

> **Phase 0 placeholder.** This doc fills in as features ship. For the
> design rationale + open decisions, read [`PLAN.md`](PLAN.md) — it is
> the canonical brief until this handoff catches up.

## 30-second mental model

SideMolly is a Tauri 2 desktop app (Rust backend + React 19 / TS / Tailwind
frontend) that consumes Molly's deterministic bundle ZIPs at
`~/Downloads/Molly bundles/<UID>.zip`, decomposes them, helps Robert push
each piece of content through edit → process → post, and sends a structured
post-bundle ZIP back to Molly at `~/Downloads/Molly post-bundles/<UID>-post.zip`.

**No runtime coupling to Molly.** The two apps share only a file format
on disk; neither opens the other's DB.

## Phase 0 surface

```
SideMolly/
├── src/
│   ├── main.tsx                          Vite entry
│   ├── App.tsx                           ViewKey routing + ⌘S sidebar toggle
│   ├── components/Sidebar.tsx            HStack 240px, never NavigationSplitView
│   ├── views/
│   │   ├── Inbox/InboxView.tsx           Phase 0 placeholder
│   │   ├── Settings/SettingsView.tsx     tabbed shell
│   │   ├── Settings/BackupSettings.tsx   full CLAUDE.md Backup UI
│   │   └── Manual/ManualView.tsx         Phase 0 placeholder
│   ├── data/db.ts                        shared Database singleton
│   ├── lib/useAsyncRefresh.ts            race-safe loader (ported from Molly)
│   ├── lib/smoke.test.ts                 keeps vitest count > 0
│   └── styles/index.css                  Tailwind + Paper Daisy @font-face
├── src-tauri/
│   ├── src/
│   │   ├── main.rs                       Windows-subsystem shim → sidemolly_lib::run()
│   │   ├── lib.rs                        Tauri Builder + plugin wiring + migrations + tests
│   │   ├── backup.rs                     auto-backup-on-launch (port from Molly)
│   │   └── fsutil.rs                     downloads_subdir + reveal
│   ├── migrations/001_init.sql           app_settings
│   ├── capabilities/default.json         Tauri ACL
│   ├── resources/fonts/PaperDaisy.ttf    commercial license (cf. Molly v1.14.1)
│   └── icons/                            PLACEHOLDER — copied from Molly
├── build-app.sh   install.sh   run-tests.sh
├── README.md  CHANGELOG.md  USER_MANUAL.md  HANDOFF.md (this)  PLAN.md
└── package.json  tsconfig.json  vite.config.ts  vitest.config.ts  tailwind.config.js  postcss.config.js
```

## Tauri command surface (Phase 0)

| Module | Commands |
|---|---|
| backup | `run_backup_now`, `list_backups`, `test_backup`, `restore_backup`, `reveal_backup_dir`, `reveal_path`, `get_backup_settings`, `set_backup_settings` |

ACL is in `src-tauri/capabilities/default.json`.

## Cross-cutting standards baked in at Phase 0

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
- **Migration smoke test.** Every migration applies cleanly to a fresh
  in-memory SQLite in source order. New migrations must extend the
  `migration_smoke::all_migrations_apply_cleanly` table.

## Where to start the next phase

Phase 1 (bundle ingest) is the first real feature. The milestone:
**drag a Molly bundle ZIP onto the window and see it parsed + verified.**

Bring-up steps per PLAN.md §11:

1. New Rust module `bundle_io.rs` — open outer ZIP, list entries,
   re-hash against `hashes.json`, return `ValidatedBundle`.
2. New Rust module `manifest.rs` — parse `Molly.log` line-based
   `KEY: VALUE` (Phase 1 fallback path). The structured `manifest.json`
   path lands in Phase 2 alongside the small Molly PR.
3. New frontend module: drag-drop handler at the window level, plus a
   "drop a bundle here" empty-state in `InboxView`.
4. New migration `002_bundles.sql` for the `bundles` table (uid, type,
   persona, title, source_zip_path, ingested_at, manifest_json, state).
5. Wire Tauri commands `ingest_bundle`, `list_bundles`.

Same camelCase contract + migration smoke discipline applies.
