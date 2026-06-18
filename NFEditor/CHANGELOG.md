# Changelog

All notable changes to NFEditor. Format: [Keep a Changelog](https://keepachangelog.com/),
[Semantic Versioning](https://semver.org/).

## 0.1.0 — 2026-06-17

### Added

- Initial release. Single-page WYSIWYG editor for NiteFlirt Flirt Profiles and
  Listings, hosted on GitHub Pages with an in-app update banner.
- **Tiptap schema** covering NiteFlirt's full vocabulary: `<font>` face/size/color
  (modeled as one mark), headings with color/align, images (optionally link-wrapped),
  the four payment embeds (Goody/PTV, Tribute, Flirt-call, Wishlist), sections
  (`<div>`/`<table>`), image maps, `<video>`, `<marquee>`, `<details>`, lists, dividers.
- **Dual serializer** over the document JSON (not `getHTML()`): **Compact**
  (inline-`style`) and **Legacy table** (`<table>`/`<font>`), driven by one global
  mode. Adjacent text runs with identical font marks coalesce into a single tag to
  conserve the character budget. Payment buttons serialize byte-identically in both
  modes.
- **Emoji guard** using Unicode property escapes (handles ZWJ sequences, flags,
  keycaps): blocks emoji on typing, strips them from paste/import, and flags any in the
  output — NiteFlirt silently truncates a page at the first emoji on save.
- **DOMPurify sanitizer** built from NiteFlirt's exact allowlist, plus a strip-diff
  report ("`class` will be stripped on save").
- **Round-trip import** of existing listings, with the payment-button-vs-linked-image
  disambiguation keyed on the niteflirt.com host.
- **Live three-up preview** (375/800/1075px; Listings capped at 820px) and a
  mode-aware character counter (7,000 / 14,000).
- **Starter templates**, Copy/Download output, and `localStorage` persistence
  (`nf.`-prefixed keys to avoid colliding with the sibling CalendarMaker on the shared
  github.io origin).
- `scripts/deploy-pages.sh` to publish the single-file build to the `bronty13/nfeditor`
  Pages repo.

### Known follow-ups

- Payment-button URL sub-type heuristics (`src/shared/import/buttonPatterns.ts`) need
  calibration against 2–3 real snippets from NiteFlirt's "Payment Mail Buttons" screen.
  The NF-vs-external discriminator (the correctness gate) is robust; the goody/tribute/
  flirt sub-classification is best-effort.
- The legacy serializer's on-platform fidelity should be confirmed by importing 3–5 real
  listings, exporting, and viewing them live on NiteFlirt.
