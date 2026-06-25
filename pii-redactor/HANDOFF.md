# PII Redactor — Handoff

Practical guide for working on this subproject. For *why* it's built this way see
`DESIGN.md`; for end-user docs see `USER_MANUAL.md`.

## TL;DR

```sh
python3 build.py          # assemble dist/pii-redactor.html
./run-tests.sh            # node --test over tests/*.test.mjs (37 tests)
open dist/pii-redactor.html   # the deliverable
node cli.mjs --help       # CLI
```

This is a **standalone HTML SPA, not a macOS .app** — the repo's
`build-app.sh` → `/Applications/` → freshness-proof flow and `/ship` do **not**
apply. "Done" = `python3 build.py` succeeds, `./run-tests.sh` is green, and the
built file opens correctly in a browser.

## Layout

```
pii-redactor/
  src/
    template.html     UI shell + CSS, with INLINE markers
    engine.js         detection engine (ESM) — makeEngine(data) -> { detect }
    redact.js         TYPE_META, tokenFor, redact (ESM)
    markdown.js       renderMarkdown(md) -> { html, toc } (ESM) — in-app manual
    data-node.mjs     Node loader for data/*.js (vm + window shim)
  data/               first-names.js, last-names.js, places.js (assign window.PII_*)
  vendor/             pdf.min.js, pdf.worker.min.js, mammoth.browser.min.js, inter-*.woff2
  build.py            inlines everything -> dist/pii-redactor.html
  cli.mjs             Node CLI (imports src/engine.js + src/redact.js)
  dist/pii-redactor.html   ← the self-contained deliverable
  tests/*.test.mjs    node:test suite
  samples/            small example inputs (committed) + large/ (gitignored)
  scripts/generate-samples.py   sample generator
  VERSION  README.md  CHANGELOG.md  USER_MANUAL.md  DESIGN.md  HANDOFF.md
```

## How the build works

`build.py` replaces markers in `src/template.html`:

| Marker | Payload |
| --- | --- |
| `<!--INLINE:version-->` | `VERSION` file contents |
| `/*INLINE:fontface*/` | `@font-face` rules with base64 Inter woff2 |
| `/*INLINE:engine*/` | `src/engine.js`, `export` stripped |
| `/*INLINE:redact*/` | `src/redact.js`, `export` stripped |
| `/*INLINE:markdown*/` | `src/markdown.js`, `export` stripped |
| `/*INLINE:data*/` | the three `data/*.js` files |
| `/*INLINE:manual*/` | `USER_MANUAL.md` (raw markdown text) |
| `/*INLINE:pdfjs*/` `/*INLINE:mammoth*/` `/*INLINE:pdfworker*/` | vendor libs |

`strip_exports()` turns the ES modules into plain inline globals. `js_safe()`
neutralizes any literal `</script` in inlined payloads so it can't close the host
tag. **Always edit `src/*`, never `dist/`** — `dist/` is generated.

## Common tasks

### Add a new PII detector

1. In `src/engine.js`, add the regex/validator and a `findX(text)` (or a
   keyword-gated variant — copy `findRouting`/`findAnchored`). Push matches with a
   `priority` that slots into the ladder (see `DESIGN.md`).
2. Call it inside `detect()`.
3. In `src/redact.js`, add a `TYPE_META` entry (`label` + `color`). Its position
   in `TYPE_META` sets its order in the type panel / summary.
4. Add a sample + an assertion in `tests/engine.test.mjs`, and (if it's a common
   type) extend `scripts/generate-samples.py`.
5. `python3 build.py && ./run-tests.sh`.

### Edit the user manual

Edit `USER_MANUAL.md` and rebuild — it's inlined verbatim and rendered by the
in-app reader, so the doc and the in-app help can't diverge. Use `##`/`###`
headings (they populate the TOC). Stick to the markdown subset
`src/markdown.js` supports (headings, bold/italic/code, fenced code, lists,
blockquotes, GFM tables).

### Refresh a vendor library

Re-fetch into `vendor/` and commit. Constraints:
- **pdf.js must stay on the v3 legacy UMD build** (`pdf.min.js` +
  `pdf.worker.min.js`). v4+ is ESM-only and won't inline as a classic script.
- mammoth: `mammoth.browser.min.js`.
- Inter: the `400` and `600` **woff2 subsets** (full family is needlessly large).

### Change the brand / theme

Tokens live in the `:root` block of `src/template.html` and mirror the defi
system (navy `#1B2A4A`, teal `#00B4D8`, Inter). Per-type swatch colors live in
`TYPE_META` in `src/redact.js`.

## Testing

`./run-tests.sh` runs `node --test tests/*.test.mjs`:

- `engine.test.mjs` — detection coverage, value correctness, gating, checksums.
- `redact.test.mjs` — token styles, numbered consistency, metadata completeness.
- `markdown.test.mjs` — renderer + TOC + escaping.
- `cli.test.mjs` — spawns the real `cli.mjs`.
- `samples.test.mjs` — runs the engine over the committed sample files.
- `build.test.mjs` — rebuilds `dist/` and asserts everything inlined and sized.

Because `build.test.mjs` rebuilds, running the suite leaves a fresh `dist/`.

## CLI

```
node cli.mjs [options] [file ...]        # or pipe via stdin
  --style labeled|numbered|mask
  --types A,B,C        --exclude A,B,C
  --json              --stats
  -o FILE             -l/--list-types     -h/--help
```

Text input only; PDF/DOCX are GUI-only (the CLI is intentionally
dependency-free). It imports `src/engine.js` + `src/redact.js`, so CLI and app
detect identically.

## Test data

- Small committed examples: `samples/*.{txt,csv,json,log,md}`.
- Generate large files for scalability testing (gitignored):
  ```sh
  python3 scripts/generate-samples.py --large 5 --large 50   # MB
  python3 scripts/generate-samples.py --rows 100000 --format csv
  python3 scripts/generate-samples.py                        # regenerate small set
  ```
  All generated PII is synthetic; cards are Luhn-valid, routing numbers pass the
  ABA checksum.

## Release hygiene

Per the repo rules: bump `VERSION`, add a `CHANGELOG.md` entry, update
`README.md`/`USER_MANUAL.md`/`DESIGN.md` for any behavior change, keep tests
green, and rebuild `dist/` so the committed artifact matches source. There is no
Sparkle/notarization here — the "release" is the committed `dist/pii-redactor.html`.

## Gotchas

- **Global-name collisions when inlining.** All inlined modules share one global
  scope in the browser. `markdown.js`'s escape helper is named `mdEscape` (not
  `escapeHtml`) to avoid colliding with the main script's `escapeHtml`. Watch for
  this if you add top-level names to a shared module.
- **The worker has no `window`.** `src/template.html`'s worker block aliases
  `var window = self;` before the data files run. `engine.js` itself only reads
  the data passed to `makeEngine`, so it's environment-neutral.
- **Name adjacency quirk** (see `DESIGN.md`): a capitalized word immediately
  before a full name can cause that name to be missed. Tests avoid relying on it;
  don't write fixtures that depend on `Word FirstName LastName` detecting.
- **`dist/` is committed** so the file is directly shareable. Rebuild before
  committing so it isn't stale.
