# NFEditor — NiteFlirt Profile & Listing Builder

> A WYSIWYG editor for NiteFlirt **Flirt Profiles** and **Listings**, working inside
> NiteFlirt's constrained, legacy HTML dialect and its destructive sanitizer.

NiteFlirt only accepts a narrow slice of HTML — no CSS classes, no `<style>`, no
JavaScript, no `<iframe>` — and it **silently deletes an emoji and everything after
it** on save. NFEditor lets you build Profiles/Listings visually and emits HTML that
survives NiteFlirt's sanitizer unmutilated.

It's a single-page web app (like the sibling `CalendarMaker/`): hosted on GitHub
Pages, bookmark the link, and it updates on refresh.

## What's in the box

- **Visual editor** (Tiptap/ProseMirror) for the full NiteFlirt vocabulary: `<font>`
  face/size/color, headings, images (with links), the four payment embeds
  (Goody/PTV, Tribute, Flirt-call, Wishlist), sections, image maps, `<video>`,
  `<marquee>`, `<details>`, lists, and dividers.
- **Two output modes from one document:** **Compact** (inline-`style`, fewer
  characters) and **Legacy table** (`<table>`/`<font>`, most consistent on old mobile
  browsers). Toggle freely — content doesn't change.
- **Emoji guard** — blocks emoji as you type, strips them from pastes/imports, and
  refuses to call output "safe" if any slip through. This is the single most important
  safety feature (NiteFlirt's emoji truncation is destructive).
- **Live three-up preview** at NiteFlirt's breakpoints (375 / 800 / 1075px; Listings
  capped at 820px content).
- **Running character counter** (7,000 Profile / 14,000 Listing), measured against the
  active output mode, color-coded as you approach the limit.
- **Round-trip import** — paste an existing listing and it's parsed back into editable
  blocks, with a report of anything NiteFlirt would strip.
- **Starter templates** to skip the blank page.
- **Copy / Download** the HTML to paste into NiteFlirt's HTML box.

## Quick start

```bash
npm install        # first time only
npm run dev        # editor on http://localhost:1540
npm run build      # production build → dist/index.html (single self-contained file)
npm test           # vitest
npm run typecheck  # tsc --noEmit
npm run deploy     # build + publish to the GitHub Pages repo (see below)
```

## How "runs and updates from GitHub" works

`npm run deploy` builds the single-file app and pushes `index.html` + `version.json`
to a **separate public repo** (`bronty13/nfeditor`) that has GitHub Pages enabled. The
source stays here in PhantomLives; only the built artifact is published. On load the
app fetches its own `version.json`; when a newer version is live it shows a one-tap
**Update now** banner. See `scripts/deploy-pages.sh` for the one-time setup.

> NFEditor and CalendarMaker are both served from `bronty13.github.io`, which share one
> localStorage origin (the path isn't part of the origin). NFEditor namespaces every
> storage key with `nf.` so the two apps never collide.

## Stack

React 18 + TypeScript + Tiptap (ProseMirror) + DOMPurify, bundled to a single
self-contained `index.html` via `vite-plugin-singlefile`. Drafts persist in
`localStorage` (in-memory fallback) — NOT IndexedDB, which hangs on `file://`.

## Layout

```
src/
  shared/        # PURE, framework-free, unit-tested
    model.ts            limits, font-size ladder, doc types
    nfAllowlist.json    NiteFlirt's exact tag/attr allowlist (vendored from docs/)
    sanitize.ts         DOMPurify config + strip-diff report
    fontSize.ts         pt ↔ NiteFlirt size (1..7) snapping
    serialize/          doc JSON → HTML (compact + legacy; mark coalescing)
    schema/             Tiptap nodes + marks (the structural allowlist)
    import/             NiteFlirt URL classifiers + import prep
    validate/           emoji detection, char counting
    templates.ts        starter docs
    update/ whatsNew    version compare + release notes
  app/           # React UI (thin — delegates to shared)
    editor/ preview/ panels/ components/ screens/
  storage/db.ts  # localStorage (nf.* keys)
docs/            # the source spec (build plan, allowlist, help-page capture)
scripts/deploy-pages.sh
```

## Output / save location

Use **Copy HTML** and paste into NiteFlirt's HTML box (the primary path). **Download
.html** saves through your browser — set your download folder to
`~/Downloads/NFEditor/` to match the PhantomLives convention.

## Notes for PhantomLives

Pure browser SPA — the macOS `.app` conventions (build-app.sh / install.sh /
auto-backup) do not apply. Release hygiene does: bump `package.json` **and**
`APP_VERSION` in `src/shared/model.ts` together, add a CHANGELOG entry + a What's-New
note, keep `npm test` and `npm run typecheck` green.
