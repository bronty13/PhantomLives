# CalendarMaker — Architecture Handoff

Read this before non-trivial changes. CalendarMaker is a self-contained, offline
SPA (editor **and** PDF exporter in one file), modeled on the Quizzer pattern but
with no "player" artifact and no committed-stub mechanism.

## Stack & build

- React 18 + TypeScript + Vite + `vite-plugin-singlefile`. `base: './'` +
  inline-everything → `dist/index.html` runs from `file://`. **Browsers block
  `fetch()` of sibling files from `file://`**, so all data/fonts are inlined.
- `npm run build` = `vite build` + `scripts/make-zip.mjs` (→ `CalendarMaker-app.zip`).
- IndexedDB (via `idb`) for saved bundles + user themes + settings. jsPDF for PDF.
  JSZip for the app zip. nanoid for ids. react-colorful for the theme editor.

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
  `holidays.ts` catalog, `fonts.ts` registry/@font-face/jsPDF registration).
- `src/calendar/` — **pure** logic (vitest target): `dateUtil`, `grid`
  (`computeWeeks`, `largestBlankRun`), `holidayResolver` (rules + Easter
  computus), `measure` (singleton headless jsPDF metrics), `fit` (the overflow
  engine), `detail` (`buildDetailSections`).
- `src/pdf/` — `geometry` (shared point constants — **the WYSIWYG contract**),
  `monthPdf`, `detailPdf`, `exportPdf` (orchestrates month/detail/both),
  `holidayNames`, `util` (hex/color/ellipsize).
- `src/storage/` — `db.ts` (idb + first-run theme seeding), `bundleIO.ts`
  (`.cmcal.json` export/parse + schema guard).
- `src/app/` — React UI: `App.tsx` (state/router), `CalendarPreview.tsx` (the
  WYSIWYG HTML grid that mirrors the PDF), `screens/*`, `components/*`.

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

## Conventions / gotchas

- Detail-only marker is drawn as a **vector** circle-with-slash (`drawNoSymbol`),
  not a glyph — the Latin font subset has no ⊘.
- Per-page orientation: month = Letter landscape, detail = Letter portrait;
  "both" puts them in one doc. Detail page numbers are added by `exportPdf`
  (not `renderDetail`) so they don't clobber the month page.
- This subproject is pure SPA → **exempt** from `build-app.sh`/`install.sh`.
- Release hygiene: bump `version` in `package.json` **and** `APP_VERSION` in
  `src/model/types.ts`, update CHANGELOG/README/USER_MANUAL, add/adjust tests.
