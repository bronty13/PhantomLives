# Changelog

All notable changes to PII Redactor are documented here.

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
