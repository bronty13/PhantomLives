# RachelUGC — Changelog

## v0.5.0 — 2026-05-25

- **Monthly summary PDF**. New toolbar button "📊 Month summary PDF" generates
  a one-page branded PDF for the currently-active month chip (falls back to
  the current calendar month when "All" is selected).
- Layout: same Bodoni wordmark + pink hero blob + daisy cluster letterhead
  as the per-deal invoices, then a stats row (Contracted / Paid / Outstanding
  / Completed / Gifted), an itemized table sorted by amount desc (Brand /
  Deliverables / Status / Paid / Amount with zebra striping and gifted-row
  italics in dusty rose), a pink-highlighted total row, and a footer.
- Page-break safe — rare for a single month, but doesn't crash for a 50-row
  outlier.
- Filename pattern: `rachelugc-summary-<YYYY>-<MMM>.pdf`.

## v0.4.0 — 2026-05-25

- **Optional due date** on every deal (date picker in the add/edit modal).
  Stored on the deal as `dueDate` (ISO `YYYY-MM-DD`); persists through
  edits + localStorage and survives spreadsheet re-imports.
- **Overdue badges & callouts**:
  - Status-board cards show a 🔥 due-line in red when overdue, ⏰ in pink
    when due within 3 days, 📅 in muted grey when further out. An
    `overdue` pill appears next to the brand name on overdue cards.
  - All-deals table gains a Due column and renders the same pill next to
    the status pill for overdue rows.
- **Overdue KPI** added to the at-a-glance strip — count of past-due
  deliverables, with a "N due soon" sub-line when there are any due in
  the next 3 days.
- Due-date logic ignores Completed and Cancelled deals, so the overdue
  count is always "deliverables I actually still owe."

## v0.3.0 — 2026-05-25

- **Payment chase email composer** on every Outstanding row alongside
  "Mark paid". Click "✉︎ Compose chase" → modal pre-fills a draft email
  customized to the deal (brand, deliverables, amount, invoice number if
  one was generated, completion-on-time mention if status is Completed).
- Three tones via chips: **Friendly nudge** (default), **Standard
  follow-up**, **Firm reminder** — switch between them and the subject +
  body regenerate.
- Recipient address, subject, and body are all editable in the modal.
- Two ship paths: **📋 Copy body** writes to clipboard, **✉︎ Open in Mail**
  fires a `mailto:` so Apple Mail / Gmail / whatever Rachel's default
  client is picks it up with the draft ready to send.

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
