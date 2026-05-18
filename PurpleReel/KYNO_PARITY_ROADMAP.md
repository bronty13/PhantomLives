# Kyno Parity Roadmap

**Status: complete.** Every Kyno-visible feature is either shipped in
PurpleReel or explicitly out of scope. See [`KYNO_RESEARCH.md`](KYNO_RESEARCH.md)
for the canonical per-feature status — 85 rows broken down by
category, source citation, effort estimate, and current state.

---

## Where this document came from

This file used to be a living checklist of Kyno-visible features
PurpleReel didn't yet match, built from user-supplied screenshots and
Kyno's published keyboard-shortcuts reference. It was the working
todo list during Sprint 1 (initial parity push).

During Sprints 2–4 we replaced it with the more rigorous
`KYNO_RESEARCH.md` — every Kyno feature transcribed from primary
sources (release notes, forum threads, third-party reviews) into a
single table with source URLs, effort buckets, and per-row
implementation notes. That research doc is now the source of truth.

## What got shipped

By the end of Sprint 4, 63 of 85 catalogued rows had landed:

- **Small bucket (38 rows): all shipped.** Coming-from-Kyno
  compatibility mode (J/L jumps, X-mute, ⌃⌥E zebra, ⌃⌥W matte,
  ⌥⇧O open-with, ⌘⌥M focus metadata, natural numeric sort, no
  auto-drilldown), Date Recorded / Date Created / Display Size /
  Aspect Ratio columns, paste metadata between clips, play-all
  continuous, incremental transcoding skip, smart proxy scale
  presets, zero-based timecode pref, LUT-on-still-frame default,
  shift-click hard refresh, subclip collision auto-disambiguate,
  audio-channel-name field, transcoder file-timestamp preservation,
  fade-in/out transcoder option, file-count safety limit warning,
  Apple Silicon native badge, …
- **Medium bucket (18 rows shipped, 2 explicitly skipped).** Find
  Lost Metadata, timecode burn-in, LUT auto-detect, folder-tree
  metadata transfer, batch frame export at markers, Excel/CSV report
  with thumbnails, paste-and-rename, boolean AND/OR filter, VFR/CFR
  filter, poster-frame keyboard P, batch tag editor, pitch-preserved
  audio rates, C4 + ASC-MHL v2.0, list-view waveform column, Kyno
  `.LP_Store/` XML import, permissions wizard. Explicitly skipped:
  Resolve FCP7-XML export (row 3), Frame.io upload preset (row 73).
- **Large bucket (7 rows shipped, 1 user-skipped).** FCPXML
  re-import, shared workspace cache for NAS / SAN, combine multiple
  clips, spanned-clip detection, cross-volume offline search,
  workflow chains, drive-disconnect quirk (closed by construction).
  User-skipped: UI localization (row 56) — out of scope.
- **Pre-research rows (10):** features that were already shipped
  before the research doc existed.

## Where to look now

- [`KYNO_RESEARCH.md`](KYNO_RESEARCH.md) — every Kyno feature with
  current state, source citation, and implementation notes. Canonical.
- [`USER_MANUAL.md`](USER_MANUAL.md) — task-oriented user
  documentation. Reflects shipped state.
- [`SHORTCUTS.md`](SHORTCUTS.md) — keyboard-shortcut reference.
- [`CHANGELOG.md`](CHANGELOG.md) — per-sprint feature rollup.

## Items that fell out of scope

- **UI localization** (German / French / Spanish — row 56). Kyno is
  multilingual; PurpleReel ships English-only by choice. Not a
  competitive blocker for our target market.
- **Resolve FCP7-XML export** (row 3). PurpleReel ships FCPXML
  (1.10) which Resolve reads; the legacy FCP7-XML path is a separate
  schema and was deprioritised. Flagged as a v2 candidate.
- **Frame.io upload preset** (row 73). Adobe's acquisition makes the
  API politically fragile, and PurpleReel's existing SFTP delivery
  covers ~80% of the review-with-client workflow. Flagged as a v2
  candidate.
- **Avid Op-Atom MXF / RED R3D / P2 / DNxHD non-rewrap**. Declined in
  the original PurpleReel build plan as outside the FCP-focused
  delivery target.
- **Final Cut Pro X library predicate filter**. Would require parsing
  FCP's library state. Out of scope.

The drive-disconnect-before-XML-import quirk (row 82) never applied
to PurpleReel by construction — our metadata importers don't assume
a particular mount state.
