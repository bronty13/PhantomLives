# Quizzer — Design Notes

The *why* behind the architecture. For the *what*, see `HANDOFF.md`.

## Goal & constraints

Build a quiz tool that lets one author hand out a quiz anyone can take in **any
browser, including mobile, with no server and no internet**. That single constraint —
"runs offline from a file" — drives almost every decision below.

## Why a single-file SPA (not a native app, not a hosted web app)

- The deliverable must open with a double-tap on iOS/Android and a desktop browser
  alike. A self-contained `.html` is the only artifact that travels everywhere with
  zero install and zero infrastructure.
- PhantomLives already ships hand-written single-file SPAs (RachelUGC,
  WeightTrackerSPA). Quizzer is far larger (a full authoring app + a player), so it
  uses **Vite + React + TypeScript** for maintainability/testability, then collapses
  to a single file via `vite-plugin-singlefile`. Best of both: components and unit
  tests in dev, one portable file out.

## Why two bundles (creator + player)

The creator runs in a browser with no server, yet "Deploy" must produce a *separate*,
finished player file. The player therefore can't be a route the creator navigates to —
it has to be **data the creator carries**. So we build the player first, embed its
HTML into the creator as a string, and inject the quiz into it at deploy time. The
build ordering this forces (player → embed → creator) is the central piece of
machinery; everything else is ordinary app code.

Trade-off accepted: a committed **stub** template + a "restore before commit" rule, so
the repo never holds the 906 KB generated blob. Considered alternatives (`?raw`
cross-dir import, a virtual-module plugin) were more fragile in dev mode; a generated
`.ts` string is deterministic and unit-testable.

## Why `window.__QUIZ__` and never `fetch`

Under `file://`, `fetch`, cross-file ES-module imports, and service workers are all
blocked by the browser. So the player reads its data from a global set by an inline
(single-file) or classic (zip) `<script>`. Element `src` with relative paths *is*
allowed under `file://`, which is exactly what the zip format leans on for large media.

## One player, two formats

Single-file vs zip differ **only** in how `window.__QUIZ__` is populated and whether
big assets are inlined or externalized. The player branches on `AssetRef` shape
(`inline` vs `file`) via `resolveAsset`, so there is **one** player codebase and the
format choice lives entirely in the deploy writer. This avoids the classic trap of a
diverging "online" and "offline" build.

## Why client-side grading — and the honest security stance

No server means grading happens on the respondent's device, which means the correct
answers must exist inside the deployed file. We **obfuscate** the answer key
(base64 + XOR) so it isn't sitting in plain View-Source, but we deliberately document
it as **deterrence, not security** — anyone determined can recover it. Pretending
otherwise would be dishonest. Quizzer is positioned for training/practice/low-stakes
assessment. (A future "server-graded" mode would break portability and is explicitly
out of scope.)

The answers are still kept out of the *plaintext* quiz: `buildPayload` blanks every
answer field on the serialized quiz and stores the truth only in the obfuscated
`answerKey`, rejoined by question id at runtime.

## Single source of truth for grading

`src/shared/grading.ts` is imported by both the creator's preview and the deployed
player, so "what the author sees" is provably "what the respondent gets". A shared
`normalize()` keeps fill/short matching consistent. Under-specified semantics are
pinned as named constants and covered by tests so they're visible and changeable:
multi = all-or-nothing, fill = proportional, manual short-answer = auto-credit.

## Library choices (all npm-bundled — no CDN, which breaks offline)

- **TipTap** for WYSIWYG (clean HTML out, tree-shakes, no runtime fetch) — creator
  only; the player just renders sanitized stored HTML, keeping the player bundle lean.
- **DOMPurify** sanitizes author HTML on store *and* render (an author could otherwise
  ship a script inside every deployed quiz).
- **jsPDF** for the certificate (already proven in RachelUGC). **JSZip** for the zip
  format (already used elsewhere in PhantomLives). **react-colorful** for color
  picking. All inline cleanly and run under `file://`.

## Fonts

Built-in fonts use curated cross-platform **font stacks** rather than shipping ~10
embedded webfaces in every quiz (weight + licensing). For guaranteed-identical
rendering the author uploads a **TTF**, embedded as base64 `@font-face`. The data
model (`FontChoice`) already distinguishes `builtin` vs `custom`, so swapping built-ins
to embedded base64 later is a drop-in.

## Storage

The creator uses **IndexedDB** (not localStorage) because quizzes can embed base64
images/video that blow past localStorage's ~5 MB cap. Global settings sit in a small
meta store. Per-quiz attempt counts in the deployed player use localStorage with an
in-memory fallback (some mobile browsers restrict storage under `file://`).

## Testing strategy

The risk is in the pure core and the deploy wiring, so that's where the 45 tests
concentrate: every grader + edge cases, obfuscation round-trip, payload strip/restore,
marker injection (incl. `</script>`/`<` escaping), zip assembly + asset externalization,
bundle import/export, certificate generation, sanitization, and a real-template
integration check. UI is verified by building and running the apps.
