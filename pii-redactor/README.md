# PII Redactor

A single-purpose, **fully offline** tool that ingests a document and scrubs its
personally identifiable information (PII), presented as an elegant HTML SPA in
the defisolutions.com brand style.

The deliverable is **one self-contained `.html` file** (`dist/pii-redactor.html`,
~4 MB) with all libraries, fonts, and reference data inlined. Double-click it to
open in any modern browser — no install, no server, no network.

> **100% local.** A strict Content-Security-Policy (`connect-src 'none'`) makes
> the offline guarantee *structural*: the page cannot open a network connection
> even if something tried. Nothing you load ever leaves your machine.

## What it does

- **Detects** names, emails, phones, SSNs, addresses, cities/states/ZIPs, VINs,
  credit cards & account numbers, plus **dates of birth, ABA bank routing
  numbers, IP addresses, driver's-license and passport numbers**.
- **Highlights** every match inline, colored by type, with a live per-type count
  panel you can toggle to include/exclude categories.
- **Redacts** in one of three runtime-selectable styles:
  - **Labeled** — `[NAME]`, `[EMAIL]`, …
  - **Numbered pseudonym** — `[NAME_1]`, `[NAME_2]`, … (the same value reuses its
    token, so relationships in the text are preserved while identity is removed)
  - **Full mask** — `████`
- **Copy** or **Download** the scrubbed output.

## Supported inputs

- **Any UTF-8 text**: `.txt .csv .tsv .log .md .json .xml .yaml .html` … (anything
  read as text).
- **PDF** — text extracted via a bundled, offline pdf.js.
- **Word `.docx`** — text extracted via a bundled, offline mammoth.js.
- Legacy binary **`.doc` is not supported** (save as `.docx` or paste the text).

> Output for PDF/DOCX inputs is **scrubbed plain text** (`<name>.redacted.txt`),
> not a rebuilt PDF/Word file. Text inputs keep their original extension
> (`report.csv` → `report.redacted.csv`).

## Detection notes & limitations

The engine favors **precision** (few false positives) over exhaustive recall —
appropriate for loan/servicing documents where dates and 9-digit numbers are
everywhere:

- **Names** require both tokens to be in the U.S. Census first/last-name lists,
  be Title-Case or UPPERCASE, and not be common English words.
- **Credit cards** must pass the Luhn checksum *and* match a known brand prefix.
- **ABA routing** numbers must pass the routing checksum *and* have a
  `routing`/`aba`/`rtn`/`transit` keyword nearby.
- **DOB, driver's license, passport** are **keyword-gated** — a bare date or
  alphanumeric token is only flagged when an appropriate label sits next to it.
  This is conservative by design: treat DL/passport/routing/DOB detection as
  helpful guidance, **not** a guarantee of complete coverage. Review the output.
- **ZIP vs. Account heuristic:** a bare 5-digit number adjacent to a city/state
  is labeled `[ZIP]` (ZIP outranks a generic account run). A genuine 5-digit
  *account* number would therefore read as `[ZIP]` — real account numbers are
  almost always longer, so this trade-off favors the common case. Either way the
  value is redacted.

## Project layout

```
pii-redactor/
  src/template.html      UI + engine, with INLINE markers
  data/                  reference data (first/last names, US places)
  vendor/                pdf.js, mammoth.js, Inter woff2 (fetched once, offline after)
  build.py               inlines everything → dist/pii-redactor.html
  dist/pii-redactor.html ← the self-contained deliverable
  tests/engine.test.mjs  headless detection test
  VERSION CHANGELOG.md README.md
```

## Build

```sh
python3 build.py
```

Reads `src/template.html`, replaces each `INLINE` marker with the corresponding
payload (reference data, vendor libraries, base64 fonts, version), and writes
`dist/pii-redactor.html`. No network access required.

### Refreshing the vendor libraries

The vendor libs are pinned and committed, so the build is reproducible offline.
To update them, re-fetch into `vendor/` (pdf.js **v3 legacy UMD build** — not v4,
which is ESM-only and won't inline as a classic script), `mammoth.browser.min.js`,
and the Inter `400`/`600` woff2 subsets.

## Test

```sh
node tests/engine.test.mjs
```

Extracts the detection engine from the **built** `dist/` file, runs it against a
sample in a sandbox, and asserts that all PII types are detected, that the
reference data inlined, that keyword gates suppress ungated dates/numbers, and
that the ABA checksum rejects invalid routing numbers.

## Architecture notes

- **Detection runs in a Web Worker** that owns the ~2 MB reference data. The
  main/UI thread never holds the data and never blocks on a scan, so the UI stays
  responsive on large inputs. The worker is built from an inlined source string
  via a Blob URL (kept single-file and offline).
- **City detection is a hash lookup**, not a 21k-branch megaregex: the engine
  scans Title-Case word sequences and probes the places map in O(1). This is both
  faster and more precise than the original case-insensitive alternation.
- **Reference data stays in-memory `Set`/`Map`** — not a database. The lookups
  are exact-membership, which a hash already serves in O(1); a WASM SQLite layer
  would add ~1 MB and async overhead to do the same thing slower. (See the
  CHANGELOG / design discussion.)
- **Large-file handling:** detection always runs; the live inline highlight is
  disabled above ~600 KB of text or ~6,000 matches (a notice explains this), but
  the detected-PII list and the redacted output — both cheap string operations —
  stay fully active.

## Default output location

This is a browser SPA, so downloads go to **the browser's download folder**
(typically `~/Downloads/`) — a sandboxed `file://` page cannot choose a custom
subdirectory. This is the one place the repo-wide
`~/Downloads/<app-name>/` convention doesn't apply (no app process controls the
write); the browser's Save dialog is the override mechanism.
