# RachelUGC — Changelog

## v0.2.0 — 2026-05-25

- New **Brands & repeat customers** panel between Outstanding and All Deals.
  Aggregates every deal by case-insensitive brand name and shows: deal count,
  paid $, outstanding $, contracted $, gifted count, platforms used, last
  deal's month, latest status. Repeat customers (2+ deals) get a pink
  `×N repeat` badge so they pop visually.
- Panel header summary: `N unique brands · M repeat customers · $X total paid`.
- Sortable by every column. Default sort: paid $ desc — biggest customers
  on top. Tiebreaker: paid $ desc then name asc.
- Respects the existing month + category filter chips at the top of the page.

## v0.1.0 — 2026-05-25

First cut: Phase 1 single-file SPA mockup for Rachel Rogalsky's UGC business.

- `scripts/extract.py` (self-bootstrapping `.venv` + openpyxl) parses
  `~/Downloads/Rachel/UGC Tracker.xlsx` into `data.json` + `data.js`. Handles
  labeled monthly subtotal rows (`MARCH TOTAL CONTRACTED: $243`) and the
  trailing bare-amount subtotal that closes the current month.
- `index.html` is a single self-contained SPA loading `data.js` via
  `<script src>` (works on `file://` — no web server required). Chart.js
  and jsPDF load from CDN.
- Soft baby-pink + dusty-rose palette sampled from Rachel's Canva portfolio.
  Bodoni Moda headlines, DM Sans body. SVG daisy clusters in the hero.
- KPI strip, stacked monthly-earnings bar chart, category-mix doughnut,
  drag-and-drop status board (HTML5 native), outstanding payments with
  one-click "Mark paid", sortable all-deals table, add/edit/delete modal.
- Per-deal PDF invoice generation via jsPDF — branded letterhead, pink hero
  blob, daisy cluster, itemized table, total in pink-highlighted row.
  Invoice sequence persisted to `localStorage`; once invoiced, the row
  records the invoice number and date.
- localStorage persistence with baseline-change detection: re-running
  `extract.py` after in-browser edits prompts the user to keep edits or
  discard.
- JSON + CSV export.
- Verified against 54-deal dataset (Feb–May 2026, YTD $3,874).
