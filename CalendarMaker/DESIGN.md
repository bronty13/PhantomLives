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
