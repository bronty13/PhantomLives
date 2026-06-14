# CalendarMaker — Design

See **HANDOFF.md** for the full architecture (module map, build, the overflow
invariant, conventions). This file captures the design intent in brief.

## Goal

Replace a fiddly Excel monthly calendar with an offline, single-file SPA that
produces **print-ready PDFs** and **never lets the user create a visual mess**.

## Key decisions

- **Single-file, offline, ZIP-distributed** (Quizzer pattern): all code, the full
  NASB Bible, sayings, and fonts are inlined into one `index.html` (browsers block
  `fetch()` from `file://`, so inlining is mandatory).
- **Vector jsPDF, not html2canvas**: crisp print, embeddable fonts, and — the
  deciding factor — exact, synchronous text metrics so overflow can be detected
  at data-entry time. The on-screen preview shares the same geometry constants and
  font metrics, so it is genuinely WYSIWYG.
- **Embedded OFL TTFs (Latin subset)**: the same base64 bytes drive the preview's
  `@font-face` and jsPDF embedding, guaranteeing the PDF matches the design on any
  machine.
- **Overflow is a first-class, pure, tested subsystem** (`calendar/fit.ts`): the
  renderer only draws certified-to-fit items; a cell cannot overflow. Anything
  that doesn't fit is preserved in the Detail view and clearly marked.
- **Rule-based holidays** (fixed / nth-weekday / Easter-offset) resolve correctly
  for any chosen year.

## Distribution & updates (v0.3.5+)

The primary user (Jan) is non-technical and low-vision, so distribution optimizes
for *zero user effort* and *no data loss*:

- **Hosted at a stable URL (GitHub Pages), not handed a file.** `localStorage` is
  keyed to the page **origin**; a `file://` origin is path-dependent, so replacing
  the file can orphan every saved calendar. A fixed `https://` origin keeps data
  across updates and turns "update" into "refresh". The host is a dedicated
  **public** repo (`bronty13/calendarmaker`) separate from this private monorepo;
  the page carries `noindex` because it embeds the copyrighted NASB. (The
  single-file build still works offline from `file://` as a fallback.)
- **Static update signal.** A `version.json` is deployed next to the app; on load
  the app fetches it and shows a large "update available" banner if it advertises a
  newer version than the baked `APP_VERSION`. No server, no service worker.
- **In-app release notes + help.** A version-aware **What's New** popup
  (large-print) and **Help → User Manual** are baked into the build. The manual is
  the committed `USER_MANUAL.md` inlined via `?raw` and rendered by a tiny in-house
  Markdown component — **one source of truth** for both the repo doc and the in-app
  help.
- **Accessibility first.** Help / What's New / update banner all use large type and
  high contrast; the manual has an A−/A+ size control; copy says "click" (mouse)
  and targets Windows.
- **Human follow-through is part of the release.** Every release also sends Jan a
  plain-language email (what's new, what to try) — see `docs/release-email.md`.

→ Full mechanics: `docs/distribution.md`. Email pattern: `docs/release-email.md`.
