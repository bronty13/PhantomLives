# Phase 8 — Per-site Sales Report Parsers (scoped, not built)

> Deferred from v1.0.0. Captured here so future-Robert (or whoever picks this up) has a real plan instead of starting from scratch.

## Why

Phase 6 ships a **generic** sales-report importer at `Income → 📊 Sales report import`. It auto-detects a date column and an amount column, sums by month, and upserts into `income_site`. Works on anything CSV-shaped.

The friction it doesn't solve: every site Sallie uses has a *different* layout. She has to:

1. Pick the site from the dropdown.
2. Verify the auto-detected date + amount columns are the right ones.
3. Click through preview → Run.

That's three decisions a month per site × ~15 sites = ~45 decisions/month, every month. Most of them are the same decision (the c4s CSV always has the date in the same column). A smarter pass would:

- **Remember** the column mapping per site after the first successful import.
- **Auto-detect known site formats** by header signature so the user doesn't even need to pick the site.
- Optionally **deduplicate** within a year so re-importing the same CSV doesn't double-count.

## What to borrow from PurpleLife's `PurpleImport`

PurpleLife ships an import engine at `PurpleLife/Sources/PurpleLife/Services/PurpleImport/`. The shape is exactly what we want:

```
PurpleImport/
├── PurpleImport.swift          # facade — entry points, type re-exports
├── ImportRunner.swift          # orchestration — source → mapping → sink
├── SavedImportMapping.swift    # persisted column mapping per (source kind, target)
└── Protocols/
    ├── PurpleImportSourceReader.swift  # "read this thing, give me rows"
    └── PurpleImportSink.swift          # "take these rows and write them"
```

Three things to lift directly:

1. **`SourceReader` protocol** — given a file (or pasted text), return a stream of normalized rows. Each site format gets its own reader (`Clips4SaleReader`, `IWantClipsReader`, `OnlyFansReader`, …).
2. **`Sink` protocol** — receive normalized rows + write them. We'd have a single `SiteIncomeSink` that bucketizes by month and `upsertSiteIncome`s. Future sinks could feed adhoc income, expenses, etc.
3. **`SavedImportMapping`** — persisted per-source-kind column mapping. PurpleLife stores it as JSON in `~/Library/Application Support/PurpleLife/import-mappings.json`. We'd store it in the SQLite DB (new table `site_import_mappings`).

The `ImportRunner` in PurpleLife is the glue: pick a `SourceReader`, run it, hand each batch to the `Sink`, surface progress + errors to the UI. That whole runner can be reimplemented in TS in `src/lib/importRunner.ts` more or less verbatim.

## Proposed Molly shape

```
src/lib/import/
├── runner.ts                          # ImportRunner — orchestration
├── savedMapping.ts                    # persisted-mapping read/write
└── sources/
    ├── c4s.ts                          # Clips4Sale CSV format detector + reader
    ├── iwc.ts                          # IWantClips
    ├── of.ts                           # OnlyFans (statements API export)
    ├── mv.ts                           # ManyVids
    ├── lf.ts                           # LoyalFans
    └── generic.ts                      # current Phase 6 parser, kept as fallback
```

```sql
-- migration 010_import_mappings.sql
CREATE TABLE site_import_mappings (
    site_id        INTEGER PRIMARY KEY REFERENCES sites(id) ON DELETE CASCADE,
    source_kind    TEXT NOT NULL,           -- 'c4s' | 'iwc' | 'of' | 'mv' | 'lf' | 'generic'
    date_column    TEXT NOT NULL,
    amount_column  TEXT NOT NULL,
    extras_json    TEXT NOT NULL DEFAULT '{}',
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);
```

## Format auto-detection

Each `sources/<site>.ts` exports two things:

```ts
export const c4sParser: SiteParser = {
  kind: 'c4s',
  // Signature match: returns confidence 0-1 that THIS CSV is a c4s export.
  detect(header: string[], firstRow: Record<string, string>): number {
    // c4s CSVs have specific header keywords like "Sale Date", "Buyer Name",
    // "Studio", and "Studio Earnings". Match all three → 1.0; two → 0.6; etc.
  },
  parse(text: string): SalesRow[] { /* … */ },
};
```

The wizard's flow becomes:

1. User uploads file.
2. `detectFormat(text)` runs every site's `detect()` and picks the highest-confidence match.
3. If confidence ≥ 0.7: skip the site picker; use the matched parser. UI confirms "Looks like a Clips4Sale CSV — proceed?"
4. If confidence < 0.7: fall back to the current generic flow with a site dropdown.
5. After a successful import, save the resolved `(site_id, source_kind, date_col, amount_col)` to `site_import_mappings`. Next time, the saved mapping is preferred over re-detection.

## Sample CSVs needed before this can ship

Each site's format needs to be observed once. Sallie would need to send Robert:

- A Clips4Sale monthly sales CSV.
- An IWantClips weekly/monthly payout CSV.
- An OnlyFans statements CSV.
- A ManyVids earnings CSV.
- A LoyalFans payout CSV.

Without samples there's no signature to detect against. Writing parsers blind would produce more bugs than it saves work.

## Deduplication

Open question for v8.1: should re-importing the same CSV detect duplicate rows and skip them?

The Phase 6 importer aggregates by month, so re-running the same file just overwrites that month's `income_site.amount` with the same number — idempotent at the bucket level. But if Sallie ever exports overlapping date ranges (e.g. a Jan-Mar CSV after a Feb-only CSV), the Feb amount gets stomped.

Cleanest fix: store the CSV source + period range in a new `income_site_imports` audit table, and warn the user when their new file overlaps a previously imported period. Defer until we have real-data evidence the issue actually bites.

## Effort estimate

- **Scaffolding** (runner + saved-mapping + 1 placeholder parser): ~3 hours.
- **Per-site parser** (find signature → write detect/parse → 1-row sanity test): ~30 min each with a real CSV in hand.
- **Wizard rewrite** (use detected format, persist mapping, offer override): ~2 hours.
- **Migration + data layer**: ~1 hour.
- **Tests** (one per parser + the runner happy path + 2 fallbacks): ~2 hours.

Realistic total for the first 3 sites: **~9 hours** elapsed. Each additional site after that is ~30 minutes given a sample CSV.

## When to do it

Trigger any of:

- Sallie complains that the monthly site-income flow is too clicky.
- She accidentally imports a CSV against the wrong site.
- She has 3+ months of sales-report habit and the column mapping never changes.

Until then, the generic parser handles it. Move on.
