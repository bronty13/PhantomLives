# Changelog

All notable changes to PII Redactor are documented here.

## [0.2.0] — 2026-06-25

Documentation, an in-app manual, a command-line interface, and a real test
suite — plus a refactor that makes the detection engine a single shared module.

### Added — in-app User Manual
- A **Manual** button opens a modal with the full `USER_MANUAL.md`, rendered by a
  new dependency-free Markdown renderer (`src/markdown.js`) that works under the
  strict CSP (no markdown-it / no CDN).
- **Table of contents** (auto-built from h2/h3 headings) and **full-text search**
  that highlights matches in place and counts them. The in-app help and the repo
  doc are the same bytes (the manual is inlined at build time).

### Added — command-line interface
- `cli.mjs` exposes the same detection engine for batch/automation use: stdin or
  files, `--style labeled|numbered|mask`, `--types`/`--exclude`, `--json`,
  `--stats`, `-o`, `--list-types`. Text input only (PDF/DOCX remain GUI-only so
  the CLI stays dependency-free).

### Added — tests & test data
- Real suite via Node's built-in runner (`./run-tests.sh` → 37 tests): engine
  coverage/gating/checksums, redactor token styles + numbered consistency,
  markdown renderer, CLI (spawned end-to-end), the committed samples, and a
  build-integration check.
- `samples/` — small example inputs of each format (`.txt .csv .json .log .md`),
  plus `scripts/generate-samples.py` to (re)generate them and emit large files
  for scalability testing (gitignored). All synthetic; Luhn-valid cards,
  ABA-valid routing numbers.

### Added — documentation
- `DESIGN.md` (architecture & rationale), `HANDOFF.md` (how to work on it),
  expanded `README.md`, and this changelog.

### Changed — engine extracted to shared ES modules
- The detection engine (`src/engine.js`), redactor (`src/redact.js`), and
  markdown renderer (`src/markdown.js`) are now ES modules with **one source of
  truth**. The browser inlines them (build.py strips `export`); the CLI and tests
  `import` them directly. No more engine copy living only inside the worker.
- `build.py` gained `strip_exports()` and new inline markers (engine, redact,
  markdown, manual).

### Performance
- **Overlap resolver is now O(n) instead of O(n²).** It scanned the whole kept
  set per match; since matches are start-sorted and kept stays non-overlapping, a
  new match can only overlap the *last* kept interval, so one comparison suffices.
  Surfaced by the new large-file test: a 5 MB / ~210k-detection input dropped from
  **26.3 s to 0.31 s** (~85×).

### Notes
- Documented the inherited **name-adjacency quirk** (a capitalized word right
  before a full name can cause that occurrence to be missed) in `DESIGN.md` /
  `HANDOFF.md`.

## [0.1.0] — 2026-06-25

Initial release. A defi-branded, fully-offline PII-scrubbing HTML SPA, rebuilt
from an existing prototype (`pii-redactor.html`).

### Kept from the prototype (engine, ported verbatim)
- Census-backed name detection (first+last list membership + Title/UPPER case +
  stopword gate), `Mr./Dr.`+surname titled-name detection.
- Luhn-validated, brand-matched credit-card detection; long-numeric account
  detection; SSN / phone / ZIP / email / VIN / street-address regexes.
- Priority-based overlap resolver (higher priority wins; ties → longer span).

### Added — new detectors
- **IP addresses** — octet-validated IPv4 + loose IPv6 (≥4 groups, so it does not
  swallow `HH:MM:SS` times). Priority 108.
- **ABA bank routing** — 9-digit candidate passing the routing checksum
  `(3·(d1+d4+d7) + 7·(d2+d5+d8) + (d3+d6+d9)) mod 10 == 0`, gated by a nearby
  `routing|aba|rtn|transit` keyword. Priority 88 (beats a generic account run).
- **Dates of birth** — `MM/DD/YYYY`, `YYYY-MM-DD`, `Month DD, YYYY`, gated by a
  preceding `dob|d.o.b|date of birth|birth date|born` keyword (avoids due-date
  noise). Priority 78.
- **Passport** and **driver's license** — keyword-anchored alphanumeric tokens
  (`passport …`, `driver's license …`/`DL #…`), requiring at least one digit to
  avoid matching prose like "License Agreement". Priority 76 / 74.

### Added — UX & packaging
- Full re-skin to the **defi light brand system** (navy/teal, Inter, soft cards) —
  replacing the prototype's dark/monospace developer look.
- **Runtime redaction-style toggle:** labeled `[NAME]` / numbered pseudonym
  `[NAME_1]` (value→token map, normalized so case/whitespace variants share a
  token) / full mask `████`.
- **Type panel** with per-type color swatch + live count; toggle a type to
  include/exclude it from detection & redaction (filters cached matches, no
  re-scan).
- **Broadened ingestion:** any UTF-8 text, **PDF** (bundled offline pdf.js v3
  legacy), and **Word .docx** (bundled offline mammoth.js). Legacy `.doc`
  reports an unsupported message.
- **Copy** and **Download** scrubbed output; download preserves the original
  base name (text keeps its extension; PDF/DOCX → `.redacted.txt`).
- Self-contained **single-file build** (`build.py` inlines data + libraries +
  base64 fonts into `dist/pii-redactor.html`, ~4.2 MB).

### Hardening
- Strict **Content-Security-Policy**: `default-src 'none'` with `connect-src
  'none'`, so no fetch/XHR/WebSocket/beacon can exfiltrate; `blob:` allowed only
  for the two Web Workers, `data:` only for inlined fonts. No analytics, no
  runtime CDN/network.

### Performance / correctness changes vs. the prototype
- **Detection moved into a Web Worker** that owns the ~2 MB reference data, so
  the UI thread never holds the data and never blocks on a scan.
- **City detection rewritten** from a ~21k-branch case-insensitive alternation
  regex to **O(1) hash lookups** over Title-Case candidate spans — faster and
  more precise (fewer false positives).
- **Reference data kept as in-memory `Set`/`Map`, not a database** — exact
  membership is already O(1); a WASM SQLite layer would only add size and async
  overhead.
- **Large-file degradation:** live inline highlighting disables above ~600 KB /
  ~6,000 matches (with an on-screen notice); detection and redaction stay active.
- **Fixed an inherited bug:** a bare 5-digit ZIP was being relabeled `[ACCOUNT]`
  because `Account` (priority 55) outranked `Zip` (50). `Zip` is now priority 58.

### Tests
- `tests/engine.test.mjs` — headless test of the engine as it ships in the built
  file: all 17 PII types detected on a sample, reference data inlined, keyword
  gates suppress ungated dates/numbers, ABA checksum rejects invalid routing
  numbers.
