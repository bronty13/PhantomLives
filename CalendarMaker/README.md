# CalendarMaker

A self-contained, **offline** single-page app for making visually stunning,
print-ready **monthly calendars** — a friendly replacement for the fiddly Excel
calendar. Build named calendar "bundles," add events and holidays, decorate with
sayings and Bible verses, pick a theme, and export to **PDF**.

Everything (app code, ~31k-verse NASB Bible, sayings, fonts) is inlined into a
single `index.html`. Unzip, double-click, done — no server, no internet.

## Features

- **Named bundles** — create, save, open, delete, and import/export calendars.
  Each new calendar asks for a **title** (the save name) and a **month/year**
  (defaults to *next month*; pick any past or future month).
- **Day events** — click any day to add items. Six styled types: **Prayer,
  Praise, Birthday, Life Event, Church Event, Reminder** (each gets a font +
  color from the active theme).
- **No visual mess, ever** — the month grid can't overflow. If an item won't fit
  a day cell you're told immediately; it's still saved and printed in the
  **Detail view**, marked with a ⊘ (circle-with-slash) in a distinct color. You
  choose which competing items take the limited month-grid slots ("Pin to
  month").
- **US holidays** — federal + common observances + Christian liturgical days
  (Easter-derived dates computed for any year). Toggle each one on per calendar.
- **Bible verses & sayings on any day** — click a day and add a **Bible Verse**
  (Book → Chapter → Verse picker over the full embedded NASB) or a **Saying**
  (searchable list of built-in + your custom sayings). Two display modes, toggled
  per calendar:
  - **Separate Calendar** (default) — verses/sayings stay off the main grid and
    print on their own landscape **"Scripture & Sayings"** calendar page. In
    *Both* export you choose the page order (Scripture before or after Detail).
  - **Force in Cells** — verses/sayings are plastered at the top of each day cell,
    with the list dots suppressed for a clean look; other items still show if they
    fit (the overflow guarantee holds).
- **Sayings & verses (whole-month filler)** — fill the calendar's free space
  (footer band or empty grid cells) with a curated saying (random) or a Bible
  verse (random **or** a book/chapter/verse picker).
- **Home screen delight** — a personalized, time-of-day greeting (set your name in
  Settings, default *Jan*), plus a random verse and a random saying, each in its
  own pretty font/color (toggle either off in Settings).
- **Custom sayings** — add your own sayings in Settings; they join the seeded pool
  used by the home card and the Sayings & Verses picker.
- **10 built-in themes** — plus create / duplicate / edit / delete your own
  (per-item-type fonts & colors, full calendar palette). Real OFL fonts are
  **embedded** so the printed PDF matches the screen on any machine.
- **PDF export** — **Month view** (landscape grid), **Detail view** (portrait,
  date-ordered list), or **Both** in one document.

## Build / run

```bash
npm install
npm run ingest:content   # parse ~/Downloads/nasb.txt + tlc_quotes_seed.json → src/data/*-data.ts
npm run embed:fonts      # subset OFL fonts to Latin → src/data/fonts-data.ts (needs the build venv, see below)
npm run build            # → dist/index.html (single file) + dist/CalendarMaker-app.zip
npm run dev              # local dev server (Vite, port 1530)
npm test                 # vitest
npm run typecheck        # tsc --noEmit
```

The committed generated data (`src/data/bible-data.ts`, `sayings-data.ts`,
`fonts-data.ts`, `fonts-registry.ts`) means a normal `npm run build` works
without re-running ingest/embed — only re-run those when the source content or
font set changes.

### Font build venv (only needed for `npm run embed:fonts`)

```bash
python3 -m venv .fontvenv && ./.fontvenv/bin/pip install fonttools brotli
```

Source TTFs come from the `@expo-google-fonts/*` devDependencies (OFL-licensed);
`embed-fonts.mjs` subsets each to Latin and base64-encodes them.

## Distribution

Ship `dist/CalendarMaker-app.zip`. The user unzips and opens `index.html`
directly (runs from `file://`, fully offline).

## Output location

PDF and `.cmcal.json` exports download via the browser. To match the PhantomLives
convention, set your browser's download folder to **`~/Downloads/CalendarMaker/`**.
PDFs are named `CalendarMaker_<Month>-<Year>_<mode>_<timestamp>.pdf`.

## Notes

- Data persists in your browser's **IndexedDB** (per browser/profile). Use
  **Export bundle (.cmcal.json)** to back up or move a calendar to another
  machine/browser.
- The NASB text is the user-provided `~/Downloads/nasb.txt`; sayings come from
  `~/Downloads/tlc_quotes_seed.json`.
