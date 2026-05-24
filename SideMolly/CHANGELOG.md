# Changelog

All notable changes to SideMolly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and SideMolly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
