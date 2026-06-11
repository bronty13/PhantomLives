# Purple Space

A Notion-style **personal workspace** for macOS: nested pages, a rich block
editor, and database tables — backed by a fully local, account-free
[Convex](https://convex.dev) backend embedded inside the app.

Version: **1.0.0**

## What it does

- **Pages, infinitely nested.** A sidebar tree with drag & drop reordering
  and re-nesting, favorites, rename/duplicate/trash context menus, and a
  trash with restore / delete-forever / empty.
- **A real block editor** (BlockNote/ProseMirror): type `/` for the block
  menu — headings, bulleted/numbered/check/toggle lists, quotes, code blocks
  with syntax highlighting, tables, images, video, audio, files, dividers.
  Markdown shortcuts as you type (`#`, `-`, `[]`, `>`, ```` ``` ````, `**bold**`…),
  drag handles, a floating format toolbar.
- **Databases, the Notion way.** A database is a page whose rows are pages.
  Table view with custom properties (text, number, select, multi-select,
  date, checkbox, URL), inline cell editing, tag creation in place, single
  and multi filters, sorting, and "Open" on any row for a full page with a
  property strip above its own block content.
- **Page polish.** Emoji icons, cover images (built-in gradients or uploaded
  images), serif display titles, light/dark themes (`⌘⇧L`), quick switcher
  (`⌘P`), per-page Markdown export (`⌘E`).
- **Your data stays on this Mac.** The app bundles the open-source
  `convex-local-backend` (FSL license) and spawns it on launch, bound to
  `127.0.0.1:47800`. No Convex account, no docker, no network. Everything
  lives in `~/Library/Application Support/Purple Space/`.
- **Auto-backup on launch** (PhantomLives standard): a zip of the whole
  workspace — including the Convex SQLite database, taken *before* the
  backend starts so the file is quiescent — to
  `~/Downloads/Purple Space backup/`, 14-day retention, 5-minute debounce,
  plus the full Settings → Backup UI (run now / test / restore / retention).

## Install

```sh
cd PurpleSpace
./build-app.sh        # build + install to /Applications + relaunch
```

`build-app.sh` also:

1. stages the pinned `convex-local-backend` binary into `resources/`
   (sourced from the official `convex` CLI's binary cache; provisioned via
   the CLI's anonymous local-dev mode on first run), and
2. deploys `convex/` functions to the local backend (hot-deploy if the app
   is running, otherwise via a temporary backend against the same data dir).

Flags: `--no-install`, `--no-open`, `BUILD_ONLY=1`.

## Develop

```sh
npm run dev               # electron-vite dev (HMR)
npm test                  # vitest — 37 unit tests
npm run typecheck         # tsc, node + web projects
npm run deploy-functions  # push convex/ to the local backend
npm run icons             # regenerate AppIcon from build/make_icon.py
```

After changing files in `convex/`, run `npm run deploy-functions` (or just
`./build-app.sh`, which always does it).

## Architecture

```
src/main/        Electron main: window, menu, prefs, backup, IPC
  convexBackend.ts   spawns/adopts the embedded backend (port 47800)
src/preload/     contextBridge API (window.purpleSpace)
src/renderer/    React 19 UI (sidebar, editor, database, settings)
src/shared/      pure logic: tree building, db model (sort/filter), types
convex/          Convex schema + functions (pages, documents, files)
```

Data model: **everything is a page.** `type: 'doc'` pages hold BlockNote
content (in the `documents` table, one row per page). `type: 'database'`
pages hold property definitions + view config (`dbPropsJson`); their child
pages are the rows, each carrying `rowValuesJson` — so every row opens as a
full page, exactly like Notion.

Backend lifecycle: launch → backup → spawn `convex-local-backend` (or adopt
an already-listening orphan on the same port/data dir) → renderer connects
`ConvexReactClient` to `http://127.0.0.1:47800` with live reactive queries.
The per-install instance secret + derived admin key live in
`convex-config.json`; `scripts/deploy-functions.sh` reads the same file.

### Pinned backend

The backend release tag is pinned in **two places** that must stay in sync:
`scripts/fetch-backend.sh` and `src/main/convexBackend.ts` (`BACKEND_TAG`).
Upgrades are one-way (the backend migrates its SQLite forward on start), so
bump deliberately and let a fresh backup run first.

## Output locations (PhantomLives standards)

| What | Where |
|---|---|
| Markdown exports | `~/Downloads/PurpleSpace/` |
| Launch backups | `~/Downloads/Purple Space backup/` |
| Workspace data (SQLite + file storage) | `~/Library/Application Support/Purple Space/convex/` |
| Backend log | `~/Library/Application Support/Purple Space/logs/convex-backend.log` |

## Keyboard shortcuts

| Keys | Action |
|---|---|
| `⌘N` / `⌘⇧N` | New page / new database |
| `⌘P` or `⌘K` | Quick switcher |
| `⌘E` | Export page as Markdown |
| `⌘⇧L` | Toggle dark mode |
| `⌘\` | Toggle sidebar |
| `⌘,` | Settings |
| `/` in the editor | Block menu |

See `USER_MANUAL.md` for the full tour.
