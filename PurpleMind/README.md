# PurpleMind 🧠💜

A soft, friendly **cross-platform (macOS + Windows) mindmap studio** with the
classic radial, MindNode-style look. Sketch ideas on an infinite canvas, watch
them fan out from a central topic in colour-coded branches, and export the map
as an image, a PDF, JSON, or a **Mermaid diagram that renders as a mindmap**.

PurpleMind is a PhantomLives subproject built "following Molly" — the same
**Tauri 2 + React 19 + TypeScript + Tailwind + SQLite** stack as Molly and
SideMolly, so it inherits the repo-wide standards (launch-time backup, immutable
migrations, the `~/Downloads/<App>/` output convention, and a dual-platform,
auto-updating release pipeline).

## What's in the app

| Area | What it does |
|---|---|
| **Sidebar** | Lists your maps newest-first. New / rename (double-click) / delete. Reopens your last map on launch. |
| **Editor** | React Flow canvas — add, edit, drag, connect, delete nodes; pan/zoom; minimap. **Drag a node onto another to re-parent it.** |
| **Mindmap styling** | A central **root**, colour-coded **branches** (each branch + its descendants share a hue), text **items** on coloured underlines, and tapered branch connectors. |
| **Bilateral Tidy** | One-click auto-layout (⌘/Ctrl+Shift+L) fans branches out to *both* sides of the root, balanced by size. |
| **Items** | Per-node emoji icons, checkboxes (✓, exports as `- [x]`), and notes. |
| **Keyboard** | Tab = child · Enter = sibling · Space = edit · arrows = navigate. |
| **Search** | ⌘/Ctrl+F highlights matches and dims the rest; Enter cycles through them. |
| **Export / Import** | Export PNG · SVG · PDF · PurpleMind JSON · **Mermaid mindmap (.md)** · Markdown outline. Copy a Mermaid mindmap or outline to the clipboard. Import JSON or a Markdown outline → new map. |
| **Settings → Backup** | Auto-backup-on-launch + full backup management UI. |
| **Settings → Export location** | Override where exports are written. |
| **Updates** | Signed updater feed (Settings → Updates); auto-update on macOS + Windows. |

## Install

Grab the latest macOS `.dmg` or Windows `.exe` from the
[**Releases**](https://github.com/bronty13/PhantomLives/releases?q=purplemind)
page. The builds are not yet code-signed, so on first launch:

- **macOS** — right-click the app → **Open** (Gatekeeper).
- **Windows** — **More info → Run anyway** (SmartScreen).

Once installed, future versions arrive automatically via the in-app updater.

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

`./run-tests.sh` runs both suites:

- **Rust** (`cd src-tauri && cargo test --lib`): backup debounce/retention/
  list/verify/auto-create, the `camelCase` IPC boundary contract, the migration
  smoke test, and the `migration_immutability` guardrail.
- **Frontend** (`pnpm test`, Vitest): pure helpers (`autoLayout` + bilateral,
  `markdownOutline`, `mapSerialize`, `branchStyle`, `visibility`, `ribbon`,
  `mermaid`) and component DOM tests (`Sidebar`, `ExportMenu`, via
  `@testing-library/react` + jsdom).

## Releasing

Bump the version in **all three** of `package.json`, `src-tauri/Cargo.toml`,
and `src-tauri/tauri.conf.json`, add a CHANGELOG entry, then tag:

```sh
git tag -a purplemind-v<x.y.z> -m "PurpleMind <x.y.z>"
git push origin purplemind-v<x.y.z>
```

`.github/workflows/release-purplemind.yml` builds the macOS `.dmg` and Windows
`.exe`, signs the updater bundles (via the `PURPLEMIND_TAURI_SIGNING_*` repo
secrets), composes `purplemind-latest.json` for the updater, and publishes the
release.

**Updater key:** the minisign public key lives in `tauri.conf.json`; the private
key + password are GitHub Actions secrets (`PURPLEMIND_TAURI_SIGNING_PRIVATE_KEY`
/ `…_PASSWORD`). Keep a backup of the private key — it can't be recovered from
the secret, and losing it means re-keying every install.

**Not yet wired:** Apple Developer ID code-signing + notarization (macOS) and
Windows code-signing — until then, released binaries trigger first-launch
Gatekeeper / SmartScreen warnings.

See **`HANDOFF.md`** for the architecture map and **`USER_MANUAL.md`** for the
end-user guide.
