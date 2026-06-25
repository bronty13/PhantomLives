# PII Redactor

A single-purpose, **fully offline** tool that ingests a document and scrubs its
personally identifiable information (PII), presented as an elegant HTML SPA in
the defisolutions.com brand style — with a matching command-line interface for
batch use.

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
- **Redacts** in one of three runtime-selectable styles — **labeled** (`[NAME]`),
  **numbered pseudonym** (`[NAME_1]`, same value reuses its token), or **full
  mask** (`████`).
- **Copy** or **Download** the scrubbed output.
- Ships an **in-app User Manual** (the *Manual* button) with a table of contents
  and full-text search.
- Exposes the same engine as a **CLI** (`cli.mjs`) for automation.

## Supported inputs (app)

- **Any UTF-8 text**: `.txt .csv .tsv .log .md .json .xml .yaml .html` …
- **PDF** — text extracted via a bundled, offline pdf.js.
- **Word `.docx`** — text extracted via a bundled, offline mammoth.js.
- Legacy binary **`.doc` is not supported** (save as `.docx` or paste the text).

> Output for PDF/DOCX inputs is **scrubbed plain text** (`<name>.redacted.txt`).
> Text inputs keep their original extension (`report.csv` → `report.redacted.csv`).

## Build

```sh
python3 build.py
```

Reads `src/template.html`, replaces each `INLINE` marker with the corresponding
payload (engine, redactor, markdown renderer, reference data, the user manual,
vendor libraries, base64 fonts, version), and writes `dist/pii-redactor.html`. No
network access required.

## Command line

The same detection engine, available for batch/automation use (text input only —
PDF/DOCX are GUI-only):

```sh
node cli.mjs report.txt > report.redacted.txt
node cli.mjs --style numbered --types Name,Email,SSN report.txt
node cli.mjs --json report.txt           # detections as JSON
cat notes.txt | node cli.mjs --stats     # read stdin, print per-type counts
node cli.mjs --list-types                # list every detectable type
node cli.mjs --help
```

## Test

```sh
./run-tests.sh          # node --test tests/*.test.mjs  (37 tests)
```

Covers the detection engine, the redactor (token styles + numbered consistency),
the markdown renderer, the CLI (spawned end-to-end), the committed sample files,
and a build-integration check that rebuilds `dist/` and asserts every payload was
inlined.

## Test data

Small example inputs live in `samples/` (`.txt .csv .json .log .md`), each rich
with a mix of PII including the keyword-gated types. Generate larger files for
scalability testing (gitignored):

```sh
python3 scripts/generate-samples.py --large 5 --large 50    # 5 MB, 50 MB
python3 scripts/generate-samples.py --rows 100000 --format csv
python3 scripts/generate-samples.py                         # regenerate the small set
```

All generated PII is synthetic; credit cards are Luhn-valid and routing numbers
pass the ABA checksum.

## Documentation

| File | Audience |
| --- | --- |
| `USER_MANUAL.md` | End users (also the in-app *Manual*) |
| `DESIGN.md` | Why it's built this way — architecture & rationale |
| `HANDOFF.md` | How to work on it — build/test/CLI, adding detectors |
| `CHANGELOG.md` | What changed and when |

## Project layout

```
pii-redactor/
  src/template.html   UI + CSS, with INLINE markers
  src/engine.js       detection engine (ESM, shared)
  src/redact.js       tokenizer + type metadata (ESM, shared)
  src/markdown.js     manual renderer (ESM, shared)
  src/data-node.mjs   Node loader for the reference data
  data/               reference data (first/last names, US places)
  vendor/             pdf.js, mammoth.js, Inter woff2 (offline)
  build.py            inlines everything → dist/pii-redactor.html
  cli.mjs             command-line interface
  dist/pii-redactor.html  ← the self-contained deliverable
  tests/*.test.mjs    node:test suite
  samples/            example inputs (+ generator in scripts/)
```

## Detection notes & limitations

The engine favors **precision** over exhaustive recall — appropriate for
loan/servicing documents where dates and 9-digit numbers are everywhere:

- **Names** require both tokens in the U.S. Census lists, Title/UPPER case, and
  not common English words.
- **Credit cards** must pass Luhn *and* match a known brand; **routing** numbers
  must pass the ABA checksum.
- **DOB, driver's license, passport, routing** are **keyword-gated** — only
  flagged when an appropriate label sits nearby. Treat these as helpful guidance,
  **not** a guarantee of complete coverage. Review the output.
- **ZIP vs. Account:** a bare 5-digit number near a city/state is labeled
  `[ZIP]`; a genuine 5-digit account would read the same way (real accounts are
  longer). Either way the value is redacted.
- **Name adjacency:** a capitalized word immediately before a full name can cause
  that occurrence to be missed (see `DESIGN.md`).

## Architecture (one paragraph)

Detection runs in a **Web Worker** that owns the ~2 MB reference data, so the UI
thread never holds it or blocks on a scan. The engine, redactor, and markdown
renderer are **ES modules** shared verbatim by the browser (inlined by `build.py`,
which strips `export`), the CLI, and the tests — one source of truth. Reference
data stays **in-memory `Set`/`Map`** (exact-membership lookups are already O(1); a
database would only add weight). The offline guarantee is **structural** via CSP.
See `DESIGN.md` for the full rationale.

## Default output location

This is a browser SPA, so downloads go to **the browser's download folder**
(typically `~/Downloads/`) — a sandboxed `file://` page cannot choose a custom
subdirectory. This is the one place the repo-wide `~/Downloads/<app-name>/`
convention doesn't apply; the browser's Save dialog is the override mechanism. The
CLI writes wherever you redirect it (`-o` or shell redirection).
