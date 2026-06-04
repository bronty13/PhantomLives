# PurpleMind 🧠💜

A soft, friendly **cross-platform (macOS + Windows) mindmap studio**. Sketch
ideas on an infinite canvas, connect them into a map, tidy them with one click,
and export to PNG, SVG, PDF, JSON, or a Markdown outline.

PurpleMind is a PhantomLives subproject built "following Molly" — the same
**Tauri 2 + React 19 + TypeScript + Tailwind + SQLite** stack as Molly and
SideMolly, so it inherits the repo-wide standards (launch-time backup, immutable
migrations, the `~/Downloads/<App>/` output convention, and a dual-platform
release pipeline).

## What's in the app

| Area | What it does |
|---|---|
| **Sidebar** | Lists your maps newest-first. New / rename (double-click) / delete. |
| **Editor** | React Flow canvas — add, edit, drag, connect, delete nodes; pan/zoom; minimap. |
| **Tidy** | One-click auto-layout (left-to-right tidy tree). |
| **Colours** | Swatch palette tints selected nodes. |
| **Export / Import** | PNG · SVG · PDF · PurpleMind JSON · Markdown outline (export); JSON + Markdown (import → new map). |
| **Settings → Backup** | Auto-backup-on-launch + full backup management UI. |
| **Settings → Export location** | Override where exports are written. |

## Default file locations

| Purpose | macOS | Windows |
|---|---|---|
| Exports | `~/Downloads/PurpleMind/` | `%USERPROFILE%\Downloads\PurpleMind\` |
| Auto-backups | `~/Downloads/PurpleMind backup/` | `%USERPROFILE%\Downloads\PurpleMind backup\` |
| App data (SQLite `purplemind.db`) | `~/Library/Application Support/com.phantomlives.purplemind/` | `%APPDATA%\com.phantomlives.purplemind\` |

Both `~/Downloads/` paths are created on demand and can be overridden in
Settings (the override persists).

## Quick start (developers)

Prerequisites: `pnpm`, Rust (`cargo`), and Tauri's platform deps. On macOS,
`brew install pnpm rust`.

```sh
# dev (hot-reload webview + Rust):
pnpm install
pnpm tauri:dev

# build + install to /Applications + relaunch (the PhantomLives standard):
./build-app.sh                 # --no-open / --no-install / BUILD_ONLY=1 opt-outs

# tests (Rust + frontend):
./run-tests.sh
```

`./build-app.sh` builds the `.app`, replaces `/Applications/PurpleMind.app` via
`install.sh` (`ditto --noextattr`), and relaunches. Windows builds come from CI.

## Tests

- **Rust** (`cd src-tauri && cargo test --lib`): backup debounce/retention/
  list/verify/auto-create, the `camelCase` IPC boundary contract, the migration
  smoke test, and the `migration_immutability` guardrail.
- **Frontend** (`pnpm test`, Vitest): the pure helpers — `autoLayout`,
  `markdownOutline` round-trip, and `mapSerialize` round-trip.

## Releasing

Bump the version in **all three** of `package.json`, `src-tauri/Cargo.toml`,
and `src-tauri/tauri.conf.json`, add a CHANGELOG entry, then tag:

```sh
git tag -a purplemind-v0.1.0 -m "PurpleMind 0.1.0"
git push origin purplemind-v0.1.0
```

`.github/workflows/release-purplemind.yml` builds the macOS `.dmg` and Windows
`.exe`, composes `purplemind-latest.json` for the updater, and publishes the
release. See **`HANDOFF.md`** for the architecture map and **`USER_MANUAL.md`**
for the end-user guide.
