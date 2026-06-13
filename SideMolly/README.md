# SideMolly

> The outbound counterpart to Molly's bundler. Ingests a Molly bundle ZIP,
> verifies it, decomposes the media, helps Robert push each item through
> **edit · process · post**, and finally sends a structured post-bundle
> back to Molly to close the loop.

**Status: shipping (v0.27.5).** All 13 planned phases are live — bundle ingest
(watched folder + drag-drop + verify), per-bundle edit/process (rotate,
watermark, strip, rename), the Auto-Assembly pipeline (title card → xfades →
master cut), transcription, Dropbox copy, the three Post Runners
(🎬 Content / 🎁 Custom / 📅 FanSite), and the post-bundle return-trip — plus
the post-plan additions below.

For the design rationale, decision log, and full phase breakdown read
[`PLAN.md`](PLAN.md); per-release detail is in [`CHANGELOG.md`](CHANGELOG.md)
and the architecture snapshot is [`HANDOFF.md`](HANDOFF.md).

## Stack

- Frontend: React 19 + TypeScript + Vite 6 + Tailwind 3
- Backend: Rust + Tauri 2 + SQLite (`tauri-plugin-sql`)
- Same shape as Molly so backup, migrations, signed installers, and
  camelCase serde all port over.

## Default file locations

| What | Mac | Windows |
|---|---|---|
| App data (DB + settings) | `~/Library/Application Support/com.phantomlives.sidemolly/` | `%APPDATA%\com.phantomlives.sidemolly\` |
| Auto-backups | `~/Downloads/SideMolly backup/` | `%USERPROFILE%\Downloads\SideMolly backup\` |
| Outputs (work dir) | `~/Downloads/SideMolly/` | `%USERPROFILE%\Downloads\SideMolly\` |
| Watched bundles | `~/Downloads/Molly bundles/` (Molly's drop location) | same |

## Dev workflow

```sh
# One-time: ensure Rust + pnpm are installed.
brew install rust pnpm

cd SideMolly
pnpm install
pnpm tauri:dev                # hot-reload dev server (port 1421)
./build-app.sh                # build + install to /Applications/ + relaunch
./build-app.sh --no-open      # build + install, no focus steal
./build-app.sh --no-install   # build only
./run-tests.sh                # cargo + vitest
```

To cut a signed release: `git tag -a sidemolly-vX.Y.Z -m "…" && git push origin sidemolly-vX.Y.Z`.
CI ([`.github/workflows/release-sidemolly.yml`](../.github/workflows/release-sidemolly.yml))
builds + signs both platforms and drops a draft GitHub release with
`sidemolly-latest.json` for the auto-updater.

## Repo layout

The frontend is `src/` (React + TS; Inbox / Bundle tabs / 11 Settings panes /
Jobs / Manual). The Rust backend is `src-tauri/src/` — 23 modules with `lib.rs`
wiring the Tauri builder, ~90 commands, and the 23 hash-guarded migrations.
See [`HANDOFF.md`](HANDOFF.md) for the annotated module tree and command
surface; the release workflow lives at the repo root
(`.github/workflows/release-sidemolly.yml`).

## Phase plan (all shipped — full version in [PLAN.md](PLAN.md) §11)

| Phase | Scope |
|---|---|
| 0 | App shell + sidebar + Settings + backup-on-launch + CI |
| 1 | Bundle ingest (watched folder + drag-drop + verify + extract + Inbox) |
| 2 | Molly PR: add `manifest.json` to bundle output |
| 3 | Per-bundle file workspace + image ops (watermark / strip / rename) |
| 4 | Video ops (trim / transcode / watermark / thumbnail via FFmpeg) |
| 4.5 | Auto-Assembly pipeline (title + xfades + voice-isolated `<Title>.mp4`, 16:9 or 9:16 per-bundle) |
| 5 | Transcription (MLX → whisper.cpp) with diarization |
| 6 | Dropbox local-folder copy (assembled `<Title>.mp4` only) |
| 7 | Posting primitives |
| 8 | 🎬 Content Post Runner |
| 9 | 🎁 Custom Post Runner |
| 10 | 📅 FanSite Post Runner |
| 11 | 📤 Post-bundle composition + Molly ingest (joint release) |
| 12 | 🛠 Jobs panel |
| 13 | 📅 FanSite multi-site workflow (per-persona roster, per-day media staging, posting log) |

### Beyond the phase plan

- **SideMolly Summary** — a per-bundle PDF (metadata, incl. assembled-file
  filename / size / length / SHA-256; a grid of rotation-corrected frames
  sampled across the bundle's videos; cleaned transcripts; processing log),
  generated from the Distribute tab and copied to Dropbox alongside the master
  cut. Frame count is configurable in **Settings → Summary** (default 30). PDF
  via `genpdf` + bundled Liberation Sans (`src-tauri/src/summary.rs`,
  `frames.rs`).
- **Edit defaults** — global (not per-persona) starting toggle states for the
  Edit tab's image/video ops (Settings → Edit defaults; Rename defaults on).
- **Inbox completion lifecycle** — mark bundles complete/active, filter, and
  delete from the Inbox toolbar.
