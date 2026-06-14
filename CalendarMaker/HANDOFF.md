# CalendarMaker — Architecture Handoff

Read this before non-trivial changes. CalendarMaker is a self-contained, offline
SPA (editor **and** PDF exporter in one file), modeled on the Quizzer pattern but
with no "player" artifact and no committed-stub mechanism.

## Stack & build

- React 18 + TypeScript + Vite + `vite-plugin-singlefile`. `base: './'` +
  inline-everything → `dist/index.html` runs from `file://`. **Browsers block
  `fetch()` of sibling files from `file://`**, so all data/fonts are inlined.
- `npm run build` = `vite build` + `scripts/make-zip.mjs` (→ `CalendarMaker-app.zip`).
- **Storage = `localStorage`** (with in-memory fallback), NOT IndexedDB:
  Chromium **hangs `indexedDB.open` on `file://` opaque origins**, which is exactly
  how this app ships — that bug stuck the app on the loading screen (v0.2.0). All
  stored data is small (calendars/themes/settings/sayings); the big Bible/fonts are
  compiled-in constants, so localStorage is plenty. The `storage/db.ts` API stays
  async so callers are unaffected. The load effect in `App.tsx` is wrapped in
  try/catch/finally (never hangs), and `ErrorBoundary` catches render errors — so
  the app can't blank out. jsPDF for PDF, JSZip for the app zip, nanoid for ids,
  react-colorful for the theme editor.

## Generated, committed data (don't hand-edit)

- `src/data/bible-data.ts` — full NASB tree `{book → chapters[] → verses[]}`,
  from `scripts/ingest-content.mjs` (source `~/Downloads/nasb.txt`). ~3.9 MB.
- `src/data/sayings-data.ts` — `FillerEntry[]`, from `tlc_quotes_seed.json`.
- `src/data/fonts-data.ts` + `fonts-registry.ts` — Latin-subset OFL TTFs as
  base64, from `scripts/embed-fonts.mjs` (needs `.fontvenv` with fonttools;
  source TTFs from `@expo-google-fonts/*` devDeps).

Regenerate only when sources/font set change; otherwise plain `build` is enough.

## Module map

- `src/model/` — `types.ts` (all interfaces + `SCHEMA_VERSION`/`APP_VERSION`),
  `factory.ts` (constructors), `seedThemes.ts` (the 10 built-ins).
- `src/data/` — generated data + hand-written helpers (`bible.ts`, `sayings.ts`,
  `holidays.ts` catalog, `fonts.ts` registry/@font-face/jsPDF registration,
  `whatsNew.ts` friendly release notes, `manual.ts` = `USER_MANUAL.md` inlined via
  `?raw`).
- `src/update/` — `version.ts` (numeric semver-ish compare for the What's-New +
  update-banner logic).
- `src/calendar/` — **pure** logic (vitest target): `dateUtil`, `grid`
  (`computeWeeks`, `largestBlankRun`), `holidayResolver` (rules + Easter
  computus), `measure` (singleton headless jsPDF metrics), `fit` (the overflow
  engine), `detail` (`buildDetailSections`).
- `src/pdf/` — `geometry` (shared point constants — **the WYSIWYG contract**),
  `monthPdf`, `detailPdf`, `versePdf` (the separate "Scripture & Sayings" page),
  `exportPdf` (orchestrates month/verse/detail), `holidayNames`,
  `util` (hex/color/ellipsize).
- `src/storage/` — `db.ts` (idb + first-run theme seeding), `bundleIO.ts`
  (`.cmcal.json` export/parse + schema guard).
- `src/app/` — React UI: `App.tsx` (state/router), `CalendarPreview.tsx` (the
  WYSIWYG HTML grid that mirrors the PDF), `screens/*`, `components/*`
  (incl. `UpdateBanner`, `WhatsNew`, `UserManual`, `Markdown` — the tiny in-house
  Markdown renderer for the in-app manual).

## The overflow guarantee (the core invariant)

`calendar/fit.ts` is the make-or-break module. Both the editor and the PDF use
the **same jsPDF text metrics** (`calendar/measure.ts`) and the **same geometry
constants** (`pdf/geometry.ts`), so what the editor warns about, the preview
shows, and the PDF prints all agree. `classifyDay` partitions a day's items into
`monthItems` (drawn on the grid) and `detailOnly` (⊘-marked, detail view only),
honoring `pinned` first then `order`, capped by measured fit AND
`settings.maxItemsPerMonthCell`. The renderer **only ever draws `monthItems`**, so
a cell physically cannot overflow. `tests/fit.test.ts` asserts the height
invariant; never weaken it.

Sizes are fixed for grid chips (theme controls font *family* + *color*, not size)
— deliberate, so one long item can't blow out a cell.

## Bible verses & sayings (v0.3.0)

`bibleVerse` and `saying` are first-class `ItemType`s (with an optional
`Item.reference`). `CalendarBundle.verseMode` (`'separate'` default | `'force'`)
controls rendering, threaded through `classifyDay(day, ctx, holidayLines,
verseMode)`, which now also returns `forceItems` (the verse/saying subset, always
kept in `monthItems`, never demoted):

- **separate** — month grid *excludes* verse/saying items (monthPdf/CalendarPreview
  filter them out); they print on a dedicated landscape page via `versePdf.ts`
  (`renderVerseCalendar`), inserted by `exportPdf` when the bundle has such items
  and the month is shown. `ExportOptions.verseOrder` picks before/after detail.
- **force** — `classifyDay` reserves up to 50% of cell height for the force block
  (shrink-to-fit, drawn by `drawShrinkText`), packs other items into what's left,
  and suppresses the colored bullet dots.

`buildDetailSections` treats verse/saying items as **never** ⊘ detail-only —
they're always placed intentionally (forced into cells or on the Scripture page).
Note: embedded fonts ship only normal/bold, so verse *italic* is a preview-only
cue; the PDF renders normal weight.

## Conventions / gotchas

- Detail-only marker is drawn as a **vector** circle-with-slash (`drawNoSymbol`),
  not a glyph — the Latin font subset has no ⊘.
- Per-page orientation: month = Letter landscape, detail = Letter portrait;
  "both" puts them in one doc. Detail page numbers are added by `exportPdf`
  (not `renderDetail`) so they don't clobber the month page.
- This subproject is pure SPA → **exempt** from `build-app.sh`/`install.sh`.
- Release hygiene each release: bump `version` in `package.json` **and**
  `APP_VERSION` in `src/model/types.ts` (keep equal); add a top entry to
  `src/data/whatsNew.ts` (friendly) **and** `CHANGELOG.md` (technical); update
  `USER_MANUAL.md` (it *is* the in-app Help) + README; add/adjust tests; then
  `npm run deploy` and **send Jan the release email** (`docs/release-email.md`).

## Distribution & in-app updates (the user-facing release path)

The app is hosted on GitHub Pages (`bronty13/calendarmaker`, public, `noindex`)
so the user keeps one bookmark and refreshes to update — a stable origin keeps her
`localStorage` calendars intact (a `file://` origin would orphan them).

- `npm run deploy` (`scripts/deploy-pages.sh`) builds, writes `version.json`, and
  pushes `index.html` to the Pages repo (cloned into gitignored `.pages-deploy/`).
- `UpdateBanner` fetches `version.json` next to the app and prompts when newer.
- `WhatsNew` shows `unseenNotes(cm.lastSeenVersion)` once per new version (first
  install is silent). `UserManual` renders `USER_MANUAL.md` (single source).
- Full guide: `docs/distribution.md`. Email pattern: `docs/release-email.md`.
  Both are required reading before shipping (see repo `CLAUDE.md`).
