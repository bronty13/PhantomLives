# PII Redactor — Design

This document explains *why* the tool is built the way it is. For how to work on
it day to day, see `HANDOFF.md`; for how to use it, see `USER_MANUAL.md`.

## Goal

A single-purpose tool that scrubs PII from a document, that:

1. **Never sends data anywhere.** Privacy is the product; it must be provable,
   not promised.
2. **Runs with zero setup.** Double-click one file. No install, no server, no
   account, no network.
3. **Is shareable.** One self-contained `.html` someone can email and open.
4. **Is also scriptable.** The same detection logic available from the CLI for
   batch/automation use.

Every architectural decision below falls out of these four.

## Shape: one built HTML file from a small source project

The deliverable is `dist/pii-redactor.html` (~4.2 MB) with **everything inlined**
— libraries, fonts, ~2 MB of reference data, the engine, and the user manual.
You can't hand-author a 4 MB file, so there's a tiny build step:

```
src/template.html   UI shell with INLINE markers
src/engine.js       detection (ES module)
src/redact.js       tokenizing + type metadata (ES module)
src/markdown.js     manual renderer (ES module)
data/*.js           reference data (assign window.PII_*)
vendor/*            pdf.js, mammoth, Inter woff2
build.py            string-substitutes each marker → dist/pii-redactor.html
```

`build.py` is deliberately dumb: it reads `src/template.html` and replaces each
`<!--INLINE:x-->` / `/*INLINE:x*/` marker with a payload. No bundler, no
transpiler, no dependency graph to reason about. The vendor libraries are fetched
once and committed, so a build is fully offline and reproducible.

## The single most important constraint: offline must be *structural*

A privacy tool that merely *chooses* not to make network calls is one bug or one
dependency away from leaking. So the guarantee is enforced by the platform, not
by our code:

```
Content-Security-Policy: default-src 'none'; connect-src 'none'; ...
```

`connect-src 'none'` means the browser will refuse every `fetch`, `XHR`,
`WebSocket`, `EventSource`, and `sendBeacon` — there is no code path, ours or a
library's, that can open a connection. `default-src 'none'` denies everything not
explicitly re-granted. We re-grant only:

- `script-src 'unsafe-inline' blob:` — inline scripts (single file) + the two
  Web Workers, which are created from Blob URLs.
- `worker-src blob:` — the detection worker and the pdf.js worker.
- `font-src data:` — the base64-inlined Inter fonts.
- `style-src 'unsafe-inline'`, `img-src data:`.

You can verify the result in DevTools → Network: zero requests after load.

## Detection runs in a Web Worker that owns the data

The reference data is ~2 MB (162 k surnames, 21 k places, 5 k first names). If it
lived on the main thread and `detect()` ran there, every scan would jank the UI,
and the data would inflate main-thread memory.

Instead, the **detection worker is the only place the data lives.** The data
files (`window.PII_*`) and the engine are inlined into a `<script
type="text/js-worker">` block; at runtime the main thread turns that block's text
into a Blob URL and spins up a `Worker`. The main thread posts text in and gets
matches back — it never holds the dataset and never blocks on a scan.

The data files assign to `window.*` (so they can also be plain browser
`<script src>`s); inside the worker there is no `window`, so the worker prepends
`var window = self;`.

```
main thread  ──postMessage({text})──▶  worker (data + engine)
main thread  ◀──postMessage({matches})──  worker
```

A request id guards against out-of-order results (a stale scan that finishes late
is ignored), and input is debounced 200 ms.

## One engine, three consumers

The detection logic is needed in three places: the browser worker, the Node CLI,
and the test suite. Duplicated logic drifts, so it lives **once** in
`src/engine.js` as an ES module exporting `makeEngine(data)`.

- **CLI / tests** `import` it directly.
- **Browser** can't use ES modules in an inline single-file script, so `build.py`
  strips the `export` keywords (`export function f` → `function f`) when inlining,
  turning the module into plain globals. `src/redact.js` and `src/markdown.js`
  get the same treatment.

This is why a build is the only thing standing between the module and the page —
no second copy of the engine exists.

## Reference data is in-memory Sets/Maps — deliberately not a database

This was an explicit design question. The data is **2 MB, read-only, and queried
only by exact membership** (`firstNames.has(x)`, `lastNames.has(x)`,
`places[city]`). A JavaScript `Set`/object *is* a hash index: those lookups are
already O(1) in RAM.

A database (e.g. SQLite-WASM) would *add* ~1 MB of WASM, an async query API, and
the awkwardness of inlining a binary `.db` as base64 — all to perform point
lookups **slower** than the `Set` already does. Databases earn their keep when
data outgrows memory, or when you need range/relational/`LIKE` queries, or
persistence/mutation. None of that applies here.

The one place the original prototype *failed* to use its hash index was city
detection — see below.

## City detection: hash probing, not a megaregex

The prototype built a single regular expression by OR-ing all **21,302** place
names into one `\b(?:a|b|c|…)\b` alternation and running it over the text. That's
the slowest detector by far (thousands of branches, backtracking) and it scales
badly with input length.

The rewrite uses the `places` map the way `findNames` already used the name sets:
scan the text for Title-Case word sequences and **probe `places[candidate]` in
O(1)**. This is both faster and *more precise* — requiring Title-Case removes the
old case-insensitive false-positive surface (the megaregex matched city names
anywhere, including lowercase words that happen to be place names).

## Overlap resolution and detector priorities

Detectors run independently and emit `{start, end, type, value, priority}`. A
single value can match several patterns, so a resolver keeps the best:

> Sort by position; on overlap, the higher `priority` wins; ties break toward the
> longer span. Score = `priority × 1000 + span_length`.

The resolver runs in a **single linear pass**. Because matches are start-sorted
and the kept set stays non-overlapping, a new match can only overlap the *last*
kept interval (every earlier one ends before that last one begins, hence before
the new match begins), so it compares against exactly one element. The earlier
implementation scanned the whole kept set per match (O(n²)); on a 5 MB input with
~210k detections that was the difference between **26 s and 0.3 s**.

The priority ladder (high → low):

```
IPAddress 108 · Email 105 · SSN 100 · VIN 90 · Routing 88 · Phone 80 ·
DOB 78 · Passport 76 · DriversLicense 74 · Address1 70 · Address2 60 ·
Zip 58 · Account 55 · State 40/35 · City 30 · Name 20
(CreditCard 95 comes from the numeric scanner)
```

Two priorities are load-bearing:

- **Routing (88) > Account (55).** A 9-digit routing number is also a valid
  "account" numeric run; routing wins *only when its keyword gate fires*,
  otherwise the value stays an account. Conservative by design.
- **Zip (58) > Account (55).** A bare 5-digit ZIP was being relabeled
  `[ACCOUNT]` in the prototype because Account (55) outranked the original Zip
  (50). ZIP is the more specific shape, so it now wins. Trade-off: a genuine
  5-digit *account* reads as `[ZIP]` — real accounts are longer, so this favors
  the common case. Either way the value is redacted.

## Validators, not just regexes

High-value types are checksum- or list-validated, which is what lets them sit at
a sensible priority without flooding false positives:

- **Credit cards** must pass **Luhn** *and* match a known brand prefix/length.
- **Routing** numbers must pass the **ABA checksum**
  `(3·(d1+d4+d7) + 7·(d2+d5+d8) + (d3+d6+d9)) mod 10 == 0`.
- **IPv4** is octet-validated; **IPv6** requires ≥4 groups so it can't swallow
  `HH:MM:SS` times.
- **Names** require both tokens to be in the Census lists, be Title/UPPER case,
  and not be common English words (a 150-word stopword list).

## Keyword gating for noisy types

In loan/servicing documents, dates and 9-digit numbers are everywhere. So
**DOB, Routing, Passport, and Driver's License are only detected near a trigger
word** (`date of birth`/`DOB`/`born`, `routing`/`ABA`/`RTN`/`transit`,
`passport`, `driver's license`/`DL`). Passport and DL use keyword-*anchored*
patterns (the keyword is part of the match and the value is captured after it);
DOB and Routing detect the value first, then check a nearby window. This trades
recall for precision on purpose — the manual says so plainly.

## Redaction styles

The tokenizer (`src/redact.js`) maps a match to a token under three styles:

- **labeled** — `[NAME]`.
- **numbered** — `[NAME_1]`, with a per-type `Map` keyed on the *normalized*
  value (case-folded, whitespace-collapsed) so the same identity reuses its token
  across the document. This preserves relational structure while removing
  identity.
- **mask** — `████`, length-clamped (4–16), hiding even the type.

The same tokenizer drives the live preview, the copy, and the download, and the
CLI — so all four always agree.

## Large-file handling

Detection always runs (in the worker). The expensive part for large inputs is
**not** the regexes — it's building one DOM `<mark>` node per match for the inline
highlight. So above ~600 KB of text or ~6,000 matches the live highlight switches
off (with an on-screen note); the detected-PII list and the redacted output —
both linear string operations — stay fully active. Result correctness is never
sacrificed; only the in-place coloring is.

## The in-app manual

`USER_MANUAL.md` is inlined verbatim and rendered by `src/markdown.js`, a small
dependency-free renderer (markdown-it would violate the no-CDN/offline posture and
add weight). It supports the subset a manual needs (headings with slug ids,
bold/italic/code, fenced code, lists, blockquotes, GFM tables) and returns a TOC
of h2/h3 headings. The modal adds client-side search that highlights matches in
the rendered DOM and dims empty TOC entries. The in-app help and the repo doc are
the same bytes by construction.

## Known limitations

- **Name adjacency quirk (inherited).** The name regex pairs a name's first token
  with the *preceding word*. When a capitalized word precedes a full name
  (`Manager John Smith`), the rejected `Manager John` match consumes `John`,
  stranding `Smith`, so that occurrence is missed. Names preceded by punctuation,
  a line start, or whitespace-only detect cleanly. Acceptable for a first-pass
  tool; revisit if recall on adjacent names matters.
- **CLI is text-only.** PDF/DOCX extraction uses browser builds of pdf.js/mammoth;
  the CLI stays dependency-free and defers binary formats to the app.
- **Detection is precision-biased.** Conservative gating means some PII without
  context is missed. The product is a strong first pass plus human review, not a
  compliance guarantee.
