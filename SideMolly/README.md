# SideMolly

> The outbound counterpart to Molly's bundler. Ingests a Molly bundle ZIP,
> verifies it, decomposes the media, helps Robert push each item through
> **edit · process · post**, and finally sends a structured post-bundle
> back to Molly to close the loop.

**Phase 0** (this commit) ships an installable empty app: sidebar shell,
Settings → Backup pane (per CLAUDE.md), auto-backup-on-launch, CI release
pipeline. No bundle ingest yet — see the plan for what's next.

For the full plan including Auto-Assembly pipeline, three Post Runners
(Content / Custom / FanSite), and the post-bundle return-trip spec, read
[`PLAN.md`](PLAN.md). 26 design decisions, 14 sections, 13 phases (0-12).

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
| Outputs (Phase 1+) | `~/Downloads/SideMolly/` | `%USERPROFILE%\Downloads\SideMolly\` |
| Watched bundles (Phase 1+) | `~/Downloads/Molly bundles/` (Molly's drop location) | same |

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

## Repo layout (Phase 0)

```
SideMolly/
├── src/                                React + TS frontend
│   ├── main.tsx · App.tsx
│   ├── components/Sidebar.tsx          HStack 240px (NEVER NavigationSplitView per CLAUDE.md)
│   ├── views/Inbox/ · Settings/ · Manual/
│   ├── data/db.ts                      shared SQLite handle
│   ├── lib/useAsyncRefresh.ts          race-safe loader
│   └── styles/index.css                Tailwind + Paper Daisy @font-face
├── src-tauri/                          Rust backend
│   ├── src/lib.rs                      Tauri Builder + plugin wiring + migrations
│   ├── src/backup.rs                   auto-backup-on-launch (CLAUDE.md mandate)
│   ├── src/fsutil.rs                   ~/Downloads resolution + Finder reveal
│   ├── migrations/001_init.sql         app_settings
│   ├── capabilities/default.json       Tauri ACL
│   ├── resources/fonts/PaperDaisy.ttf  commercial license (cf. Molly v1.14.1)
│   └── icons/                          PLACEHOLDER — copies of Molly's, see icons/PLACEHOLDER.md
├── build-app.sh                        build → install.sh → relaunch
├── install.sh                          ditto --noextattr → /Applications/SideMolly.app
├── run-tests.sh                        cargo test --lib + vitest
├── PLAN.md                             canonical plan (read this first)
├── README.md  CHANGELOG.md  USER_MANUAL.md  HANDOFF.md
└── .github/workflows/release-sidemolly.yml (lives at repo root, not here)
```

## Phase plan (summary — full version in [PLAN.md](PLAN.md) §11)

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
