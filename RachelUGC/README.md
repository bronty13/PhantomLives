# RachelUGC

A single-page dashboard for Rachel Rogalsky's UGC creator business — replaces
the flat `UGC Tracker.xlsx` with a soft-pink CRM mockup that loads the same
data and adds KPIs, charts, a drag-and-drop status board, outstanding-payment
tracking, and per-deal PDF invoice generation.

This is **Phase 1**: a self-contained SPA. Open `index.html` and Rachel sees
her own deals, in her own brand palette, with everything she'd want at a
glance. Phase 2 layers on real workflows (payment chase, monthly summaries,
brand CRM). Phase 3 ports to a real app with durable persistence.

## Quick start

```sh
cd ~/dev/PhantomLives/RachelUGC

# 1. Refresh the data from Rachel's spreadsheet.
python3 scripts/extract.py
# → writes data.json and data.js, summarises months and totals.

# 2. Open the dashboard.
open index.html
```

Double-clicking `index.html` from Finder works the same way. No web server
needed.

## What's in here

| File | What it does |
|---|---|
| `index.html` | The whole SPA — palette, charts, status board, table, modal, jsPDF invoices. Single file, inline CSS + JS, Chart.js and jsPDF loaded from CDN. |
| `data.js` | Auto-generated `window.BOOTSTRAP_DATA = {...}` payload that the SPA loads on first launch. **Don't edit by hand** — re-run `extract.py`. |
| `data.json` | The same payload as JSON for human inspection / external use. |
| `scripts/extract.py` | Reads `~/Downloads/Rachel/UGC Tracker.xlsx`, parses the deal rows + monthly subtotals, and writes both `data.js` and `data.json`. Self-bootstraps a `.venv` with openpyxl. |
| `CHANGELOG.md` | Release notes per the PhantomLives release-hygiene rule. |

## Updating the data

Rachel updates her spreadsheet → re-run `python3 scripts/extract.py` → reload
the page in the browser. The SPA detects that the baseline changed and asks
whether to keep your in-browser edits or discard them in favour of the fresh
spreadsheet.

By default the script reads `~/Downloads/Rachel/UGC Tracker.xlsx`. Override
the path with `-i`:

```sh
python3 scripts/extract.py -i /path/to/some-other.xlsx
```

## What the dashboard shows

- **Hero** — "Real with Rach UGC" wordmark, daisy clusters, soft pink blob
- **Filter chips** — by month and by category, top of the page
- **KPI strip** — contracted $, paid $, outstanding $, completed count, gifted
  count, average paid deal
- **Charts** — stacked monthly earnings bar (paid + pending; gifted count
  shown in tooltip) and a category-mix doughnut
- **Status board** — kanban with five columns (Need to Film → Awaiting
  Delivery → Need to Edit → Pending Approval → Completed). Drag a card
  between columns to update its status. Cancelled deals collapsed into a
  footer for the sake of vibes.
- **Outstanding payments** — every `Paid = Pending` deal, biggest first,
  with one-click "Mark paid"
- **Brands & repeat customers** — every deal aggregated by brand name, with
  paid / outstanding / contracted totals, platforms used, last-deal month,
  latest status. Repeat customers (2+ deals) get a pink badge. Sortable.
- **All deals table** — sortable, click a row to edit, every row has
  per-deal "📄 Invoice" and "Edit" buttons
- **Toolbar** — Add Deal, Export JSON, Export CSV, Reset to spreadsheet

### Editing in the browser

The SPA persists every edit to `localStorage` under the `rachelugc:*` keys.
Your spreadsheet is never touched. Use **Reset to spreadsheet** in the
toolbar to wipe your in-browser edits and re-load fresh from `data.js`.

### PDF invoices

Each deal with a non-zero amount can generate a branded PDF invoice from the
row's 📄 button or the edit modal. Invoices are saved to your browser's
**Downloads** folder (browser-controlled location; the PhantomLives default
is `~/Downloads/`) with the filename `invoice-RWR-<year>-<seq>-<brand>.pdf`.

Once a deal has been invoiced, the row shows the invoice number; regenerating
keeps the same number rather than burning a fresh sequence.

## Brand

Sampled from Rachel's Canva portfolio (`realwithrachugc.my.canva.site/rwrugc`).

- Palette: `#FFFFFF` white, `#F4BFD0` blob, `#D9899B` dusty rose accent,
  `#B85A6B` deeper rose for emphasis, `#1A1A1A` near-black text, daisy-cluster
  motifs in pink + grey
- Fonts: **Bodoni Moda** for headlines, **DM Sans** for body — both from
  Google Fonts
- Photo / card frames echo the portfolio's 3px black border style

## Roadmap

- **Phase 1 (this)** — read-only dashboard + in-browser CRUD + invoices.
  ✅ shipped.
- **Phase 2** — payment-chase email drafts, brand contact CRM, monthly
  summary PDFs, cashflow forecast, tax-prep exports
- **Phase 3** — port to a real desktop app (Electron or Swift) with durable
  persistence beyond `localStorage`
