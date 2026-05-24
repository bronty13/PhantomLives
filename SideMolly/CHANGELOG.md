# Changelog

All notable changes to SideMolly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and SideMolly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
