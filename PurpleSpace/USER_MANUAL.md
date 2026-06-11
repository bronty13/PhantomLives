# Purple Space — User Manual

Purple Space is your personal Notion: pages, a block editor, and database
tables, all stored locally on this Mac. This manual covers everything in
v1.0.0.

## Getting around

The window has two parts: the **sidebar** (your page tree) and the **page**
you're reading. Drag the divider to resize the sidebar; press `⌘\` to hide
it entirely.

- **Search / Quick switcher** — press `⌘P` (or `⌘K`, or click *Search*).
  Before you type it lists your most recently edited pages; type to match
  titles (fuzzy matching works: "ppx" finds "Project Phoenix"). `↑`/`↓` then
  `Enter` to jump.
- **Favorites** — star any page (the ☆ in the top-right, or right-click →
  *Add to Favorites*) and it appears in a Favorites section at the top of
  the sidebar.
- **Breadcrumbs** — the path at the top of the window; click any ancestor to
  jump up.

## Pages

Press `⌘N` (or *+ New page*) — the caret lands in the title; type and press
`Enter` to drop into the body.

- **Nesting**: hover a sidebar row and click `+` to create a page inside it.
  There's no depth limit.
- **Reorganizing**: drag a row and drop it *above*/*below* a sibling (a
  purple line shows the spot) or *onto* a page (purple outline) to nest it
  inside. You can't drop a page into its own subtree.
- **Right-click** a row for Rename, Duplicate, Favorite, Add page inside,
  and Move to Trash.
- **Icon & cover**: hover above the title and click *Add icon* (emoji
  picker) or *Add cover* (eight gradients, or upload your own image; hover
  the cover for Change/Remove).

## Writing

Click anywhere in the body and write. The editor is a full block editor:

- Type **`/`** for the block menu: headings, lists, to-dos, toggles, quote,
  code, table, image, video, audio, file, divider…
- **Markdown shortcuts** convert as you type: `#`/`##`/`###` + space for
  headings, `-` for bullets, `1.` for numbered lists, `[]` for to-dos, `>`
  for quotes, three backticks for code, `---` for a divider, `**bold**`,
  `*italic*`, `` `code` ``.
- **Hover a block** for the left-gutter handles: `+` inserts below, the
  six-dot handle drags the block (or click it for block actions).
- **Select text** for the floating toolbar: bold, italic, underline,
  strikethrough, code, link, colors, turn-into.
- **Images** — drag & drop, paste, or `/image`. Files are stored inside your
  workspace (Convex file storage), not linked to their original location.
- Everything **saves automatically** as you type.

## Databases

Press `⌘⇧N` (or *New database*) for a table.

- **Rows are pages.** Click a row's name to rename it; click **⤢ Open** to
  open the row as a full page — its properties appear above the body, and
  you can write notes, add an icon or cover, just like any page.
- **Properties**: click a column header to rename it, change its type
  (text, number, select, multi-select, date, checkbox, URL), sort by it, or
  delete it. The `+` at the right end of the header row adds a property.
- **Tags**: in select/multi-select cells, click and type — *Create* makes a
  new tag with the next palette color.
- **Filter** and **Sort** live in the toolbar above the table. Filters
  stack (each must match); the active sort and filters are shown as chips.
  A count under the table shows "n of m rows" while filtered.
- **New rows**: the *New row* button, or the *+ New row* line at the bottom.
- Deleting a row (the small trash icon at the row's right edge) moves it to
  the Trash like any page.

## Trash

*Trash* in the sidebar footer lists everything you've deleted, with
per-page **Restore** and **Delete forever**, plus **Empty Trash**.
Trashing a page takes its sub-pages with it; restoring brings them back
(to the workspace root if the original parent is itself still trashed).

## Export

`⌘E` (or the `⋯` menu → *Export as Markdown*) writes the current page to
`~/Downloads/PurpleSpace/<title>.md`. Documents export as Markdown;
databases export as a Markdown table honoring the current filters/sort.

## Appearance

`⌘⇧L` toggles light/dark. Settings (`⌘,`) → Appearance also offers
*System*, which follows macOS.

## Backups

Purple Space backs itself up **automatically on every launch** (at most
once per 5 minutes): a zip of your entire workspace — pages, images, and
settings — written to `~/Downloads/Purple Space backup/`, kept for 14 days
by default.

Settings (`⌘,`) → Backup lets you:

- toggle the launch backup, change the folder, or change retention
  (7/14/30 days or Forever),
- **Back Up Now** — immediate backup,
- **Test Latest** (or *Test* on any archive) — verifies the zip opens and
  contains your settings,
- **Restore…** — pick an archive; the current state is safety-backed-up
  first, then the app restarts into the restored workspace.

## Where your data lives

Everything is local: `~/Library/Application Support/Purple Space/` holds
the database (`convex/convex_local_backend.sqlite3`), uploaded files
(`convex/convex_local_storage/`), and preferences. No account, no cloud, no
network access required.

## Shortcuts at a glance

| Keys | Action |
|---|---|
| `⌘N` | New page |
| `⌘⇧N` | New database |
| `⌘P` / `⌘K` | Quick switcher |
| `⌘E` | Export page as Markdown |
| `⌘⇧L` | Toggle dark mode |
| `⌘\` | Toggle sidebar |
| `⌘,` | Settings |
| `/` | Block menu (in the editor) |
| `Enter` in title | Jump into the body |

## Troubleshooting

- **"Opening your workspace…" never finishes** — the embedded backend
  failed to start. Check
  `~/Library/Application Support/Purple Space/logs/convex-backend.log`,
  then rebuild with `./build-app.sh`.
- **Functions out of date after pulling new code** — run
  `npm run deploy-functions` (or `./build-app.sh`, which always deploys).
