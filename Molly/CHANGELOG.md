# Changelog

All notable changes to Molly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Molly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.8.2] — 2026-05-22

### Fixed — release pipeline (no app code changes)

- **Auto-updater no longer breaks the morning after a release.** Until 1.8.2 the workflow created the GitHub release as a *draft* and required a manual UI publish; v1.8.1 sat as a draft overnight, which broke the updater because `releases/latest/download/latest.json` only resolves against published releases. The workflow now flips draft → published as its final step.
- **Downloaded .dmg no longer reports "Molly is damaged and can't be opened" on macOS Sonoma+.** The Tauri bundler only linker-signs the app; macOS Sonoma+ Gatekeeper rejects linker-signed downloads outright even with right-click → Open. The mac build step now runs `codesign --force --deep --sign - --options runtime` against the bundle before packing the DMG + tarball, then rebuilds the DMG so the downloadable carries the same ad-hoc signature. Gatekeeper now treats it as "unidentified developer" — the documented right-click → Open path works again.
- **Windows updater no longer fails signature verification.** The `latest.json` Windows entry pointed at `Molly_x.x.x_x64-setup.exe` while the minisign signature was generated against the `.nsis.zip`. URL now points at the `.nsis.zip` archive that was actually signed.

### Known limitations (unchanged from 1.8.1)

- DMG remains *unsigned in the Apple-Developer-ID sense* (and unnotarized). First-run on macOS will still show "unidentified developer" — right-click → Open works. If you still see "damaged," strip the quarantine bit: `xattr -dr com.apple.quarantine /Applications/Molly.app`. Real Developer ID + notarization is tracked separately.
- `releases/latest/download/latest.json` is monorepo-shared: if another PhantomLives subproject releases after Molly, Molly's updater endpoint is briefly wrong until the next Molly release. Per-project stable updater URL is tracked separately.

## [1.8.1] — 2026-05-21

### Added

- **Drill-down from the C4S Dashboard.** Each row of "Clips by status," each entry in "Top 10 categories," and each pill in "Top 10 keywords" is now a clickable button that opens the C4S grid pre-filtered to that value. Category + keyword filters match the comma-split list (so drilling "BBW" doesn't surface "BBW STUFFING" rows), and active filters show as removable pills above the grid alongside the existing search / sort / status controls. Stacks naturally with the search box + status dropdown + regex toggle, so a click into "active" can be narrowed further by typing.

### Fixed

- **Import wizard error message now tells you what's actually in the file you picked.** Previously a wrong-format pick gave a generic "doesn't look like a Clips4Sale export — missing columns: …". Now the error shows the columns the parser *did* see (one giant column when the delimiter was comma, or the first 8 column names if they're just unfamiliar), detects ZIP magic bytes for accidental .xlsx picks, calls out comma-delimited files as "look for Export to CSV, not Excel," and prints the filename + byte size so it's obvious whether the right file landed in the picker. Error block now renders multi-line messages (`whitespace-pre-wrap`).
- **`build-app.sh` no longer passes `--no-open` to `tauri build`.** The script consumes `--no-open` and `--no-install` for `install.sh`; both were being forwarded to `tauri build` which rejects them. Filtered out before forwarding. Also wrapped the args-array expansion so `set -u` doesn't blow up when no args were passed.
- **Missing pnpm transitive dep.** Added `postcss-selector-parser` as an explicit dev dep so Vite's PostCSS pipeline can find it under pnpm's strict-hoisted `node_modules` layout (npm's flat layout hid the gap).

## [1.8.0] — 2026-05-21

### Added — 💌 In-app User Manual

- **New sidebar entry** at the bottom of the nav between Settings and footer. Opens `USER_MANUAL.md` rendered in Molly's persona-tinted style — pastel cards, Comfortaa headings, 💕 bullet glyphs, gradient blockquotes, decorative hr dividers. Hand-rolled block parser (`src/lib/markdownLite.ts`) in the spirit of `PurpleLife/Sources/PurpleLife/Views/SecurityDocView.swift` — keeps the bundle library-free (no `react-markdown`) and the styling 100% under our control.
- **Right-rail TOC** auto-extracts H1/H2 headings; click to jump; the active heading highlights as you scroll (IntersectionObserver). Hidden below `lg` breakpoint.
- **SayingsBanner** at the top of the manual view so the page opens with a cute encouragement before getting into the how-to.
- **Cuteness lift on the manual itself.** Rewrote `USER_MANUAL.md` end-to-end with warmer, more Sallie-by-name voice; added section emojis throughout; sprinkled little encouragements between sections; updated the 1.0 intro to reflect 1.8 + C4S Store; closed with a "note from the team". The manual is content, not configuration — the in-app viewer always renders whatever the shipped `USER_MANUAL.md` says.
- **Vitest coverage**: `markdownLite.test.ts` (12) covers the block parser (headings, lists, blockquotes, fenced code with language hint, horizontal rules, paragraph join, list-flushed-by-heading) + the inline tokenizer (code spans, **bold**, *italic*, links, plain text, no-markdown-inside-code).

### Added — 🛍️ C4S Store

New top-level sidebar entry between Clips and Customers for browsing the **Clips4Sale catalog snapshot**. Sallie exports both stores (CoC + PoA) from C4S as pipe-delimited CSVs and Molly overlays each one atomically (delete + bulk insert + count-verify in a single transaction). The data is read-only reference — no editing.

- **Sub-routes**: Dashboard (summary cards + stale-data banner) → Grid (searchable table) → Detail (full-page row inspector with ← Back that preserves search/sort/filter). Honors the top persona switcher; ★All interleaves both stores, Sa shows a friendly empty state.
- **Dashboard cards**: total clips, lifetime sales, 6-month income, per-store split bars (★All only), status breakdown bars, top-10 categories, top-10 keyword chips, price min/mean/max.
- **Stale-data banner**: tiered cute language by age — 🌸 fresh (≤1 day), ✨ still pretty fresh (2–6), 🌷 might be worth a re-import soon (7–29), 🌼 time for a fresh export? (30+), 🌱 nothing on file. Rotates a SayingsBanner-style display font per render. Hideable from Settings.
- **Import wizard**: one ✨ Import C4S CSV button, file picker → auto-detect persona from the `Performers` column (`CoC` → CoC, `PrincessOFAddiction` → PoA) → confirm-and-override → atomic replace → success card with verified row count. Skips parsing-broken rows (missing Clip ID or Title) and surfaces them in an expandable `<details>` so nothing fails silently.
- **Grid**: search w/ regex toggle + "N of M" + amber invalid-regex hint + Clear button + status dropdown filter. 13 columns total; Persona + Title always visible, every other column toggleable in Settings. Click any header to sort (re-click flips direction). Click row to open detail.

### Added — Settings → 🛍️ C4S

- Stale-data banner on/off toggle.
- Per-column on/off toggles. Defaults track the data shape we observed in Sallie's exports: Tracking Tag and Preview Filename default OFF (always empty in current C4S exports); everything else defaults ON.
- ✨ Import C4S CSV button (same wizard as the dashboard).
- Last-imports readout (CoC + PoA, with timestamp and row count).
- 🗑 Delete all C4S data — two-tap `ConfirmButton`. Wipes both stores' clips + audit rows; nothing else is touched.

### Schema

- Migration `016_c4s_clips.sql` adds the `c4s_clips` table (PK `(persona_code, clip_id)`; `persona_code` CHECK-locked to `'CoC' | 'PoA'`) and `c4s_imports` audit table with a persona+time index. No FKs to other Molly tables — this is a reference snapshot, not relational state.

### Tauri command surface

- `c4s::replace_c4s_clips` — atomic `BEGIN → DELETE persona → bulk INSERT → INSERT audit → COMMIT` via `rusqlite`. Returns `ReplaceResult { personaCode, deletedCount, insertedCount, expectedCount, matches, importedAt }` so the UI can warn on count mismatch.
- `c4s::delete_all_c4s_data` — single-transaction wipe of `c4s_clips` + `c4s_imports`. Returns `DeleteAllResult`.
- Both DTOs added to `camel_case_contract`; total now 9.

### Tests

- **Rust (+8)**: `c4s::tests` covers (1) insert-then-count-matches, (2) overlay-only-its-own-persona, (3) empty-rows-clears-persona, (4) `delete_all` wipes both stores + audit, (5) invalid-persona CHECK rejection, (6) ISO timestamp format contract. Plus 2 new `camel_case_contract` entries for `ReplaceResult` + `DeleteAllResult`. `migration_smoke` anchor list extended to `c4s_clips` + `c4s_imports`. Cargo test total: 22 → 30.
- **Frontend (+31)**: `csvPipe.test.ts` (10) covers pipe-delimited parser w/ multi-line quoted descriptions (the C4S edge case), CRLF, BOM, escaped `""`, empty cells, ragged rows. `c4sClassify.test.ts` (9) covers Performers → persona mapping with normalization + `detectPersonaFromRows` walk. `markdownLite.test.ts` (12) covers the in-app manual viewer's block + inline parsers. Vitest total: 44 → 75.
- **Combined: 30 cargo + 75 vitest = 105 tests** (run via `./run-tests.sh` — `CI=true` in non-TTY environments).

### MasterClipper retrofit notes (filed for later, not implemented here)

MasterClipper has a sibling C4S Historical import that's been in production for a while. While building Molly's version we identified seven improvements to backport. Tracked in `MasterClipper/HANDOFF.md` under a new "C4S import — retrofit candidates from Molly" section.

## [1.7.3] — 2026-05-21

### Tests

Closed the two highest-value gaps the 1.7.2 audit identified.

**Rust BLOB round-trip (16 → 22)** — extracted `insert_history_row` / `read_history_blob` (`history.rs`) and `insert_log_row` / `read_log_blob` (`log.rs`) as pure functions of `&Connection`; the Tauri commands are now thin wrappers. Six new tests against in-memory SQLite with migrations 001–015 applied:
- `history::tests::blob_round_trips_exactly` — bytes including nulls + high-bytes survive write→read.
- `history::tests::read_history_blob_returns_error_for_missing_id`.
- `history::tests::insert_with_unknown_customer_uid_fails` — FK enforcement.
- `log::tests::blob_round_trips_exactly` — same for `mollys_log`.
- `log::tests::read_log_blob_returns_error_for_missing_id`.
- `log::tests::empty_body_and_zero_byte_blob_are_allowed` — edge case.

**Frontend pure-function suite (vitest, 0 → 44)** — `OUT_OF_SCOPE.md`'s "frontend tests deferred" stance is partially lifted. Added `vitest@4.1.7` as a dev dep, `vitest.config.ts` (node env, `src/**/*.test.ts` discovery), and `pnpm test` / `pnpm test:watch` scripts. Four test files:
- `src/lib/money.test.ts` (10) — `parseMoney` / `fmtMoney` incl. trailing-decimal handling that the `MoneyInput` pattern depends on.
- `src/lib/phone.test.ts` (12) — `formatUSPhone` partials + canonical + extension; `isValidUSPhone` + `usPhoneDigits` covering the leading-`1` strip.
- `src/lib/cadence.test.ts` (18) — `nextOccurrencesAfter` for all six cadence kinds (daily / weekly + biweekly anchor / monthly_dom + EoM clamp / monthly_days_before_next / monthly_days_after_eom / every_n_days) + every exported date helper.
- `src/lib/uid.test.ts` (3) — `formatDateKey` Y-M-D shape + zero-pad.

**`run-tests.sh`** now chains both: `cargo test --lib` then `pnpm test`. **66 tests total** in well under 5 seconds wall-clock.

Component / rendering tests, `attachments.rs`, and `export.rs` stay untested — see `OUT_OF_SCOPE.md` for the updated rationale.

## [1.7.2] — 2026-05-21

### Tests

- **Migration smoke test.** New `lib.rs::migration_smoke::all_migrations_apply_cleanly` opens an in-memory SQLite with `PRAGMA foreign_keys = ON`, runs every shipped migration (001 → 015) in order via `include_str!`, asserts 23 anchor tables exist, and asserts `kinks` was preloaded with ≥349 rows by migration 011. Catches schema regressions (bad ALTER, missing FK target, SQL syntax errors, accidental `DROP TABLE`, broken preload INSERT) before they touch Sallie's DB.
- **`fsutil::downloads_subdir` contract pinned.** Tiny test asserting the path ends with the requested sub and is absolute (or `.`-rooted fallback). Holds the contract that all the "where do I put this?" code paths depend on.
- Total cargo tests: **16** (7 backup + 7 camelCase contract + 1 migration smoke + 1 fsutil).

### Docs

- **README.md** — updated to reflect 1.7.x reality: new "feature growth since 1.0.0" lede, Molly's Log row de-Trekkified, test count 12 → 16, migration count 9 → 15, source-file list includes `history.rs` + `log.rs`, phases table extended from 1.0 through 1.7.
- **HANDOFF.md** — `src/components/` now lists `KinkChipPicker` + `MoneyInput`; `src/data/` lists `customerHistory`, `customerSales`, `mollysLog`; `src/views/` adds `MollysLog`; Tests section documents the four kinds of cargo tests and notes the known untested surface (history/log/attachments/export Rust I/O, all frontend) with the rationale (deferred per `OUT_OF_SCOPE.md`).

## [1.7.1] — 2026-05-21

### Changed — Molly's Log polish

- **Past entries render in a handwritten font.** Caveat (already loaded via the Google Fonts link for the sayings banner) is now applied to the body of each saved entry at `fontSize: 1.25rem`, `lineHeight: 1.4`. Composer textarea + edit-mode textarea stay in the regular UI font so typing is crisp; only the read-only render gets the journal look.
- **Dropped the Trek references.** Sallie isn't into Star Trek, so:
  - Placeholder is now just **"Note to self…"** (no more "Captain's log…" / "Stardate today…" rotation; removed the `PROMPTS` array entirely).
  - Submit button is **"✨ Log entry"** (no 🖖 Vulcan salute).
  - Page subtitle reads "Your personal journal — notes to self with optional file attachments…" (was "captain's-log style journal").
  - Sidebar hint and USER_MANUAL section updated to match.

## [1.7.0] — 2026-05-21

### Added

- **📔 Molly's Log** — new top-level sidebar entry (right below Home) for a Captain's-log-style personal journal. Compose freeform text entries with an optional inline file attachment; each entry is timestamped and editable / deletable.
  - Mirrors the customer-history pattern: `customer_history` minus the customer FK and persona binding. Inline BLOB attachments via a parallel `src-tauri/src/log.rs` rusqlite module (`add_log_entry_with_attachment`, `download_log_attachment`) so binary bytes never round-trip through JS IPC.
  - Filter input above the list with a **grep** checkbox (regex toggle); substring by default, real `RegExp` when toggled. "N of M" count + Clear button + inline amber warning on invalid regex. Filter searches across body + attachment filename.
  - Editing reveals an inline textarea (Save / Cancel); deletion is two-tap-confirmed via `ConfirmButton` and removes the row + its inline BLOB.
  - Composer placeholder rotates a short list of Trek-flavored openers ("Captain's log…", "Stardate today — note to self…") for vibes; doesn't constrain the actual entry format.

### Schema

- Migration `015_mollys_log.sql` adds the `mollys_log` table (id, ts, body, attachment_filename/mime/size, attachment_data BLOB, updated_at) + index on `ts DESC`.

### Tauri command surface

- `log::add_log_entry_with_attachment` — reads the file, INSERTs the row with the BLOB, returns the new id.
- `log::download_log_attachment` — streams the BLOB by id out to a target path.
- New `LogEntryRef` boundary struct + matching `camel_case_contract` test; total now 14.

## [1.6.2] — 2026-05-21

### Fixed

- **Adhoc Income row layout — Edit/✕ buttons no longer overlap the amount.** The actions cell on adhoc rows was `col-span-1` but had to hold *two* pill buttons (Edit + ConfirmButton), which collectively were wider than 1/12 of the table and overflowed leftward, visually clobbering the amount column (you'd see something like `$66.32` truncated to `$66`). The sale row's tiny "on customer" hint fit fine in 1 col so this only bit adhoc rows. Widened the actions column to `col-span-2` and reclaimed the col from the note. Also added `whitespace-nowrap` to the amount cell so totals like `$1,234.56` can't wrap.

## [1.6.1] — 2026-05-21

### Fixed

- **Money inputs across the app now accept dollars and cents.** Same root cause we hit on Settings → Products in 1.2.1: `<input value={String(amount)} onChange={parseMoney(e.target.value)}>` re-renders on every keystroke, so typing `5.` parses to `5`, strips the trailing dot, and the user can never reach the cents. Refactored into a reusable `src/components/MoneyInput.tsx` that keeps the *display* as a local string buffer while emitting the parsed number to the parent — and uses a ref to ignore re-renders triggered by its own emit so the buffer doesn't get clobbered mid-typing. Re-init only happens when the value changes from outside (caller switched rows).
- **Sites swapped:** Adhoc Income (the user-reported regression), Expenses (amount + partial-exclusion amount), Recurring Expenses, Site Income Wizard. All four were sharing the same broken pattern.

## [1.6.0] — 2026-05-21

### Added

- **Reminders on the calendar.** Pending occurrences from active schedules now render as 🔔 pills on the day grid in `src/views/Calendar/CalendarView.tsx`. New `listOccurrencesInRange(from, to, personaCode)` in `src/data/occurrences.ts` runs alongside the existing `listClips` query (parallel `Promise.all`). Reminder pills use a dashed border in the schedule's persona color (or neutral when no persona is bound) and prefix with 🔔 to distinguish from clip pills (solid borders). Tooltip shows the schedule name. Completed occurrences are excluded by design — the calendar shows what's upcoming.
- **Sort direction + status filter on Clips grid.** Existing sort buttons (go-live / title / status / persona) now toggle direction: click an already-active key to flip between ↑ and ↓. Each key has a sensible default direction on first click (date desc, text asc). New Status dropdown filters to a single distinct value found in the loaded clips. Combined with the existing search, the grid is now actually navigable for a large library.
- **Clips grid search is now as-you-type with a regex toggle.** Matches `CustomerListView` / `CustomerHistoryCard` patterns. Filters client-side over the persona-scoped clip set across id / title / status. Invalid regex shows an inline amber hint; "N of M" count + Clear button when active. No more Enter/blur to trigger refresh.

### Changed

- **Dropped legacy fields from clip import + display.** `external_clip_id`, `keywords`, and `performers` are no longer read from the MasterClipper CSV (new imports write empty strings to those columns) and no longer shown in the Clip Detail modal. The DB columns and `Clip` type are preserved so older imported data isn't lost; you can still see it via direct SQL if needed. The clip-list search dropped the now-empty `keywords LIKE` clause and the import view's expected-columns hint was updated accordingly. Reuse detection on `external_clip_id` continues to fire for legacy rows but will naturally degrade as new imports stop populating it.

## [1.5.1] — 2026-05-21

### Fixed

- **MasterClipper CSV import was unrunnable when any persona was mapped to "skip".** Two stacked bugs in `src/views/Import/MasterClipperImport.tsx`:
  1. The `allMapped` gate guarded `mapping[src] !== ''`, but `''` is the *value of the actual "(skip rows with this persona)" dropdown option*. So picking "skip" on any persona left the Run import button permanently disabled — the symptom Sallie hit. Lifted the `!== ''` check; mapping is always initialized for every distinct source persona on file load, so the only thing the gate needs to guard against is `undefined`.
  2. Even if Run could fire, the loop's `personaCode = mapping[sourcePersona] || null` would have *imported* those rows with `personaCode = null`, not skipped them. Reworked the row resolution: when the source persona is non-empty and explicitly mapped to `''`, the row now increments the `skipped` counter and is left out of the upsert. Empty-persona-in-CSV rows still import with `null` persona (legacy behavior preserved).

### Added

- **Pre-flight import counter.** A small "`N to import · M to skip`" readout next to the Run button on the mapping screen, matching the row resolution above so an all-skips mapping doesn't look broken.

## [1.5.0] — 2026-05-21

### Added

- **Customer sales flow into the Adhoc Income view.** `customer_sales` rows now surface in `src/views/Income/AdhocIncomeView.tsx` alongside typed adhoc entries — same year/month/persona filters, same running total. Sale rows are marked with a 🛒 glyph and show `<customer> — <product>` as the source label and `<quantity> <unit> · <sale notes>` in the note column. Read-only here (no Edit/Delete buttons; the "on customer" hint points back to the customer's history timeline for changes).
- **Implementation is a read-side union, not a copy.** A new `listAdhocUnified(filter)` in `src/data/income.ts` runs both queries with matching year/month/persona predicates, builds a `UnifiedAdhocRow` discriminated union (`source: 'adhoc' | 'sale'`), and sorts by `dateEarned DESC`. Customer sales stay in `customer_sales` as the single source of truth — no schema changes, no duplication, no sync hazard. Editing/deleting a sale on the customer side updates the income view on next render.
- **Reports + Home dashboard totals now include sales.** `totalsForPeriod` adds a `SUM(customer_sales.total_cents)/100` to `adhocTotal` (with the same period + persona filters), so MTD/YTD income figures reflect sales without making them invisible income.

## [1.4.2] — 2026-05-21

### Changed

- **History notes are now editable and deletable** — lifting the audit-only restriction set in 1.3.0 at the user's request. Each note row in the timeline now has **Edit** / **Delete** buttons matching the sale-row UX. Edit reveals an inline textarea (Save / Cancel) bound to the note's body; Delete is two-tap-confirmed via `ConfirmButton` and removes the row along with its inline BLOB attachment. The data layer (`src/data/customerHistory.ts`) gains `updateEntry(id, body)` and `deleteEntry(id)` exports; the module-level comment was rewritten to reflect the new contract. Editing a note touches only the body — attachment metadata and BLOB stay put.

## [1.4.1] — 2026-05-21

### Changed

- **Sale Date is now a date picker** (`<input type="date">`) in `CustomerSaleEditor`. Stitches the picked date with `12:00:00` UTC time so the row sorts cleanly alongside history datetimes and timezone shifts can't bump the displayed day. Sale timeline rows now render date-only (`May 21, 2026`) since the time portion was always meaningless noise; history rows still show full datetime.
- **Customer-list search adds a regex checkbox** and switches to client-side filtering for both substring and regex modes. Filter runs as-you-type now (no more Enter/blur to trigger refresh). Searches across username, real name, UID, and primary email; matches "N of M" count + Clear button + invalid-regex inline amber warning. Persona scoping stays server-side so the fetched dataset stays bounded.

## [1.4.0] — 2026-05-21

Phase 3 of the customer-record expansion: **sales transactions**, interleaved with the history log into one customer timeline. Closes out the three-phase plan started in 1.2.0.

### Added

- **Sales on the customer timeline.** A new **🛒 + Add sale** button on the History card opens an inline composer with: Product (dropdown of unarchived products, shows the default `$X / unit` next to each name), Quantity, Unit price (USD), Total (USD), Date (optional — defaults to now), and a Notes textarea. The three money fields reconcile bidirectionally: edit Quantity or Unit price and Total recalcs; edit Total and Unit price back-solves from `total / quantity` for line-level discounts. Saving lands a row in `customer_sales`.
- **Sales render in the timeline** alongside notes, sorted by date newest-first. Sale rows look like `🛒 Customs · 10 minutes · $50.00` with the customer-supplied notes below. When the user discounted the line, a tiny breadcrumb shows `(($5.00 / minute × 10 = $50.00, adjusted to $40.00))`. **Sales are editable and deletable** (unlike notes, which stay append-only) — Edit pops the inline composer pre-filled, Delete is two-tap-confirmed via the existing `ConfirmButton`.
- **Lifetime sales pill** in the customer editor header (`💖 $X.XX`) shows `SUM(total_cents)` across all sales for the customer; hidden when zero. Refreshes on any add/edit/delete via a parent callback (`onSalesChanged`).
- **Timeline filter** (added per follow-up request): a search input above the timeline filters notes + sale notes + product names. Substring match by default (case-insensitive); a small `regex` checkbox switches to a real `RegExp`. Invalid regex shows an inline amber error; valid filters show "N of M" while active with a Clear button.

### Schema

- New migration `014_customer_sales.sql` adds the `customer_sales` table (id, customer_uid FK CASCADE, product_id FK RESTRICT, sale_date, quantity REAL, unit_price_cents, total_cents, notes, created_at, updated_at) plus an index on `(customer_uid, sale_date DESC)`. `product_id` uses `ON DELETE RESTRICT` so historical sales can never be silently orphaned — archive a product instead of deleting it when it goes out of rotation.

## [1.3.0] — 2026-05-21

Phase 2 of the customer-record expansion: per-customer immutable **history log** with optional inline file attachments. Phase 3 (sales transactions) builds on top of this and lands in 1.4.0.

### Added

- **Customer history card** below the existing Notes section in the customer editor. Composer at the top (textarea + 📎 attach + ➕ Add to history) with a reverse-chronological list of entries below. Each entry shows a timestamp + the body text (newlines preserved) + a clickable 📎 chip for the optional attachment. Footer: *"Audit-only — entries cannot be edited or deleted."*
- **Audit-only by design.** `src/data/customerHistory.ts` deliberately exports only `addEntry`, `addEntryWithAttachment`, `listEntries`, and `downloadAttachment` — no `updateEntry` / `deleteEntry`. The UX contract is enforced at the data layer rather than via UI hiding.
- **Inline BLOB attachments.** Picking a file via the OS dialog stores the bytes directly into `customer_history.attachment_data` as a SQLite BLOB; downloading streams them back out via a save dialog. Files never round-trip through the JS layer — both directions go through new Rust commands (`add_history_entry_with_attachment`, `download_history_attachment`) backed by `rusqlite` for clean BLOB binding. Auto-detected MIME by extension.

### Schema

- New migration `013_customer_history.sql` adds the `customer_history` table (id, customer_uid FK, ts, body, attachment_filename/mime/size, attachment_data BLOB) plus an index on `(customer_uid, ts DESC)`. List queries deliberately exclude the BLOB column to keep page render cheap.

### Tauri command surface

- `history::add_history_entry_with_attachment` — reads the file, inserts the row, returns the new id.
- `history::download_history_attachment` — reads the BLOB by id, writes to a target path.
- 1 new `camel_case_contract` test (`HistoryEntryRef`); total now 13.

### Dependencies

- Added `rusqlite = "0.31"` with the `bundled` SQLite feature. The `tauri-plugin-sql` JSON parameter marshaller doesn't bind raw byte arrays cleanly; rusqlite opens the same `molly.db` file with `busy_timeout(5s)` so writes from both connection paths cooperate via SQLite's WAL.

## [1.2.2] — 2026-05-21

### Added

- **Phone number formatting + validation.** When the customer's country is US, both phone inputs format-as-you-type into the canonical `(XXX) XXX-XXXX` form and tolerate paste of any common variant (`555-123-4567`, `+1 555 123 4567`, `5551234567`, `1-5551234567`, etc. — `formatUSPhone` strips non-digits and drops a leading `1` country code). Numbers with fewer than 10 digits get an amber border and a "10 digits required for a US number." hint below the input. Non-US countries bypass the formatter entirely (free text), since global phone formats vary too widely to coerce reliably. Logic lives in `src/lib/phone.ts`.

## [1.2.1] — 2026-05-21

### Fixed

- **Product price input is now typeable.** Settings → Products price field was `type="number"` + `step="0.01"` + `.toFixed(2)`-on-every-render, which made typing `$20.03` impossible — the buffer got reformatted on every keystroke, and the browser's number-input enforcement only let you increment by penny via the spinner. Switched to uncontrolled `type="text"` with `inputMode="decimal"`, `defaultValue`, on-change parsing into cents, and on-blur normalization back to 2-decimal form. `key={editing.id}` on the row's edit grid ensures defaults pick up the right row when switching.

### Changed

- **State / Province** in the customer's mailing address renders as a dropdown of the 50 US states + DC + 5 USPS state-equivalent territories when `country === 'US'`. For other countries, falls back to the original free-text input.
- **Zip+4** field is hidden when country isn't US (it's a US-specific format). Non-US countries see a single "Postal code" field instead.

## [1.2.0] — 2026-05-21

Phase 1 of a three-phase customer-record expansion. Phase 2 (per-customer immutable history log with file attachments) and Phase 3 (sales transactions backed by the new product pricing) follow.

### Added — Products

- **Per-product price and unit.** Settings → Products gains a Price (USD) input and a Unit field (with a datalist of `minute`, `hour`, `session`, `item`, `set`). The 7 preloaded products get sensible default units on migration (`minute` for Phone/Cam/Customs, `item` for the Physical merch); prices start at $0 — set them in Settings. The product display row now reads e.g. `Customs · $5.00 / minute`.

### Added — Customer record

- **VIP toggle** in the customer editor header. Click the `☆ VIP` pill to mark a customer as VIP; the pill turns gold (⭐ VIP), a matching `⭐ VIP` chip appears next to their persona in the customer list, the editor header gets a ⭐, and the list **sorts VIP customers first**.
- **Primary email selector.** Each of the five email slots gets a radio button. The list-row primary-email picker now follows the user's chosen primary, falling back to the first non-empty slot if the chosen slot is blank.
- **Mailing address.** New card on the customer editor with: Address line 1, Address line 2, City, State / Province, Zip + +4, and a Country dropdown sourced from the full ISO 3166-1 alpha-2 list (US/CA/GB pinned to the top, separator, then alphabetical). Default country is US.
- **Two phone numbers** with per-phone **📱 Mobile** checkbox and a shared "Primary phone" radio.

### Schema

- Migration `012_products_and_customer_fields.sql`: `ALTER TABLE products` adds `price_cents` + `unit`; `ALTER TABLE customers` adds 13 new columns (`vip`, `primary_email_index`, `address1/2`, `city`, `state`, `zip`, `zip4`, `country`, `phone1/2`, `phone1/2_is_mobile`, `primary_phone_index`). Lossless — every column has a default; existing customers come out the other side unchanged.

## [1.1.2] — 2026-05-21

### Fixed

- **Drag-to-reorder kink chips actually works now.** Tauri 2's default window setting `dragDropEnabled: true` was intercepting all HTML5 drag events for native file-drop handling, so chip drag-start never reached the React handlers. Set `dragDropEnabled: false` in `tauri.conf.json`. Also hardened the chip itself: switched the wrapping element from `<span>` to `<div>` (more reliable drag surface), added a visible `⋮⋮` grip handle, gave the chip `userSelect: none`, and set `draggable={false}` plus `onMouseDown` stopPropagation on the × remove button so clicking it doesn't accidentally start a drag.
- **Customer edits no longer vanish when you navigate away.** Two changes:
  - **Debounced auto-save (800ms idle).** Any change to a customer field, chip selection, persona, emails, or notes schedules an auto-save 800ms after you stop interacting. Successive edits collapse into one save.
  - **Save-on-Back.** The ← Back button now flushes any pending changes through `save()` before closing the editor. The explicit **💾 Save now** button is still there for users who want a hard commit; "💾 Saving…" / "✏️ Unsaved — auto-saving…" / "✓ Saved" status reads live next to it.

  Root cause of the data loss: `addCustomer` inserts an empty row into the DB the moment you click "Add customer", and the editor opened on top of that empty row. Without auto-save, typed-but-unsaved fields stayed in component state and were dropped on navigation. Auto-save closes the gap end-to-end.

## [1.1.1] — 2026-05-21

### Added

- **Drag-to-reorder kink chips.** Selected kink chips on the customer editor are now draggable. Grab a chip and drop it onto another to insert before it; the numbered position labels (`1.`, `2.`, …) update live and persist via `customer_kinks.position` on save. Matches MasterClipper's `CategoryChipPicker` reorder UX.
- **Filter input on every Settings taxonomy tab.** Products / Interests / Kinks now have a search box at the top that filters by name *or* description (case-insensitive). Shows "N of M" while filtering; a Clear button resets it. The 349-row Kinks list is now actually navigable.
- **Description preview on Settings rows.** Each row shows its description (when present, currently kinks-only) as a one-line truncated caption below the name.

### Added

- **Customer "Kinks" field.** A third per-customer list alongside Products and Interests, modeled directly on MasterClipper's `CategoryChipPicker` interaction pattern. Molly ships preloaded with 349 curated kinks (Voyeurism, Exhibitionism, Frotteurism, …, through to Dystopian/Fantasy/Supernatural AU), each with a short description shown in the picker dropdown.
- **`KinkChipPicker` component (`src/components/KinkChipPicker.tsx`).** Shows only the *selected* kinks as chips (numbered `1.`, `2.`, … with × remove). A **+ Add kink** button opens a searchable dropdown of the unselected catalog; rows show the name + description, and typing a brand-new name surfaces a sticky "Create kink: '…'" row at the top so you can add on the fly without leaving the editor.
- **Per-customer kink ordering.** `customer_kinks.position` (new column) tracks the order you pick kinks in, mirroring MasterClipper's `clip_categories.position`.
- **Kink count in the customer list row.** The right-side counter cluster now shows "N kinks" alongside the existing product/interest counts.
- **Settings → Kinks.** Reuses the existing `TaxonomySettings` UI; the 349 default rows are immediately editable (rename, recolor, archive, delete) without any one-time import step.

### Schema

- New migration `010_kinks.sql` adds the empty `kinks` (catalog) + `customer_kinks` (join) tables.
- New migration `011_kinks_preload.sql` evolves both: adds `kinks.description`, adds `customer_kinks.position` (with index `customer_kinks_by_pos`), and bulk-inserts the 349 default kinks. Both migrations run automatically on launch; no manual import.

## [1.0.0] — 2026-05-20

### 🎁 First-gift release for Sallie

This is the v1.0.0 milestone — Molly is feature-complete for the use case it was designed for. From here, work is bug-fix + the deferred scope items in `PHASE_8_PARSERS.md`.

### Added

- **Cute sayings banner.** 1000 hand-picked encouragements from `~/Downloads/sayings.md` baked into `src/data/sayings.ts`. Two display variants:
  - **Hero**: gradient card at the top of the Home dashboard with a 💕 emoji + the saying in one of 10 rotating cute display fonts (Pacifico / Caveat / Dancing Script / Sacramento / Indie Flower / Shadows Into Light / Patrick Hand / Kalam / Chewy / Comfortaa) + an `✨ another` button to re-roll.
  - **Compact**: replaces the static "your work, your way 💕" subtitle in the sidebar. Click the saying itself to re-roll.
- **HANDOFF.md** (project architecture map for future developers).
- **DESIGN.md** (UX / theming / persona engine notes).
- **INSTALL.md** (Sallie-friendly Windows install + data-export walkthrough, plus the developer-side dev-import counterpart).
- **PHASE_8_PARSERS.md** (scope doc for the deferred per-site sales-report parsers, modeled on PurpleLife's PurpleImport engine).
- **OUT_OF_SCOPE.md** (Apple Developer ID + Windows EV cert signing intentionally deferred — single-user gift app).

### Changed

- Version bumped to 1.0.0 across `tauri.conf.json`, `Cargo.toml`, `package.json`, and the sidebar footer (which reads from `getVersion()`).
- README, USER_MANUAL refreshed for the 1.0.0 milestone and final feature set.

## [0.7.1] — 2026-05-20

### Added / Changed

- **Race-protected refresh hook + visible loading states.** Extracted `src/lib/useAsyncRefresh.ts` — a small hook that wraps the `useEffect → refresh()` pattern every list view was hand-rolling, adding per-effect-run alive guards (writes from the previous load are suppressed once the user switches persona or deps change) plus a `loading` flag.
- Applied across 14 views: Customers / Clips / Calendar / Promos / AdhocIncome / Expenses / SiteIncomeWizard / Reports / Reminders / MollyHelper / SalesReportImport / RecurringExpenses + the 4 Settings tabs (Personas / Sites / Taxonomy / Platforms / Backup).
- High-traffic list views now show `Loading …` while data is fetching, instead of flashing the misleading "Nothing here yet" empty state.
- `onClose` async refresh handlers (Customers / Clips / Calendar / Promos) now `try/catch` so post-close fetch errors surface instead of being swallowed.

### Quality

- All bugs were from a static code audit, not user-visible incidents — the previous code was technically correct but had latent race windows on persona switch and inconsistent loading vs empty-state UX. Building it into a single hook means future views get the right behavior by default.

## [0.7.0] — 2026-05-20

### Added

- **Phase 7 — Social promotion tracker.**
- Migration `009_social.sql` adds `social_platforms` (Reddit / X / Instagram / TikTok preloaded; editable in Settings → Platforms) and `social_promos` (persona, platform, handle, posted_at, url, title, body, optional clip link, rich-text notes).
- New sidebar entry **📣 Promos** between Molly Helper and Income.
- Promos list with platform / year / month / search filters; click **Open** to launch the post URL via `plugin-opener`.
- Promo editor wizard threading persona → platform → handle → posted-at (datetime-local) → URL → title → body → optional linked clip → Tiptap rich-text notes.
- Settings → Platforms tab with full CRUD (icon emoji + color + short code + sort + archive).
- Reports gains a Promos section: MTD + YTD counts + per-platform bar chart sized by each platform's color.

## [0.6.1] — 2026-05-20

### Fixed

- **Backup Test / size / mtime were all undefined.** The Rust structs returned by `list_backups`, `test_backup`, `export_full_data`, and `save_attachment` were serializing field names as snake_case (`size_bytes`, `has_database`, `modified_at`, `file_count`, `total_bytes`, `relative_path`, …) but the TS callers expected camelCase. That made every Test result claim "no molly.db inside, undefined files, NaN MB unpacked" and every recent-backup row read "· NaN MB". Added `#[serde(rename_all = "camelCase")]` to `BackupRow`, `VerifyResult`, `ExportResult`, and `AttachmentInfo`.
- **Sidebar footer was frozen at "Phase 0 · v0.0.1"** — now pulls the live version from `@tauri-apps/api/app::getVersion()` and reads simply "Molly · v0.6.1".

## [0.6.0] — 2026-05-20

### Added

- **Phase 6 — Sales report importer (v1).** Each site (Clips4Sale, IWantClips, OnlyFans, …) exports a different CSV but they all reduce to "date + amount" rows. Instead of N hard-coded parsers, Molly auto-detects the date and amount columns by header name, allows manual override, totals by month, and upserts into the `income_site` table — same shape the monthly wizard touches.
- **New tab**: Income → **📊 Sales report import**.
- **Generic parser** (`src/lib/salesReport.ts`): header-keyword-based column detection (`date|day|earned|period|sale date|transaction date|earning date` for dates; `payout|net|amount|total|earned|gross|usd|payment` for amounts); robust money parser stripping `$`, commas, and preserving sign; date parser covering ISO, US, EU, `Mon DD YYYY` formats with EOM-safe range checks; per-`(year, month)` aggregation.
- **Wizard UI**: site dropdown → CSV file pick → auto-detected columns (with override) → per-month totals preview showing CSV total vs existing site_income vs what the row will become → **Replace** or **Add** mode → run.
- Unparseable rows are surfaced in an expandable list at the bottom of the preview so the user knows exactly what got skipped and why.

## [0.5.0] — 2026-05-20

### Added

- **Phase 5 — Data round-trip + Auto-update.**
- **Full data export** (`src-tauri/src/export.rs::export_full_data`) zips the entire `app_data_dir` (database + attachments + settings) plus a `manifest.json` (app name, version, exported_at, schema_version, format tag) into `~/Downloads/Molly export/Molly-export-YYYY-MM-DD-HHmmss.zip` (`%USERPROFILE%\Downloads\Molly export\…` on Windows). Re-exporting just makes a new file; old ones are untouched.
- **Settings → Data tab** with **Export everything** button, **Reveal export folder**, last-export readout, **Reveal in Finder**, and a "Sending to Robert? Drop this in our Slack DM" hint card.
- **Dev-only import** (`import_full_export`) reuses `backup::restore_archive`'s safety-pre-import-backup + wipe + unpack flow. Gated by `VITE_MOLLY_DEV=1` at the JS layer so it never appears for the end user.
- **Updater public key generated** — `tauri.conf.json` now ships a real minisign pubkey. Private key lives in `~/.config/molly-secrets/updater.key` (not committed) and is the source for the `TAURI_SIGNING_PRIVATE_KEY` secret CI signs releases with.
- **Settings → Updates tab** with current version (from `@tauri-apps/api/app`), last-checked timestamp, **Check for updates**, **Download v…** action with a progress bar, and an auto-relaunch via `@tauri-apps/plugin-process`. Graceful "couldn't check" panel that points at the GitHub Releases page when no feed is published yet for this version.
- Two new settings tabs (`Data`, `Updates`) — Settings is now Personas / Sites / Products / Interests / **Data** / **Updates** / Backup.

### Changed

- `backup::restore_archive` visibility bumped from `pub(crate)` to `pub` so the export module can reuse it for the dev-import flow.

## [0.4.0] — 2026-05-20

### Added

- **Phase 4 — Income + Expenses + Reports.**
- Migrations `007_income.sql` (`income_adhoc`, `income_site` unique on year+month+site) and `008_expenses.sql` (`expenses`, `expenses_recurring`, unique on `(recurring_id, effective_date)` so materialization is idempotent).
- **Adhoc income** view (`💖 Adhoc income`) with year + month filter, persona scoping, add/edit/delete, total readout. Backfill to any past date for tax prep.
- **Site income wizard** (`🌐 Site income wizard`): pick year + month → wizard walks every site grouped by persona → one dollar field per site → save. Reopenable for any past month. Per-persona subtotals + grand total update live.
- **Expense list + editor** with actual + effective dates, persona, description, note, **receipt attachment** (Tauri-backed copy into `<app_data>/attachments/expenses/<YYYY>/<MM>/<uuid>_<basename>`), and exclude/partial-exclude controls (e.g. "this $100 was $30 personal, $70 business").
- **Attachment field** with Open / Reveal in Finder / Remove via new Rust commands (`save_attachment`, `delete_attachment`, `reveal_attachment`, `open_attachment` in `src-tauri/src/attachments.rs`).
- **Recurring expenses** reusing the Phase 3 Cadence engine: name + amount + persona + anchor + cadence (weekly with day mask / monthly Nth / N days before next month / N days after EOM / every-N-days / daily) + Pause/Resume. Live "Reads as" + next-5-dates preview, just like the schedule wizard.
- **Recurring materializer** runs on launch + every 30 min, walks each active recurring expense from its `last_material` to today, INSERTs into the journal via `INSERT OR IGNORE` (idempotent), then bumps `last_material`.
- **Reports view**: 3 period cards (MTD vs Prior MTD vs YTD) showing income, expenses (net), profit. Income breakdown bars (Adhoc vs Site). Per-site YTD income chart grouped by persona, sized by site color. **Export CSV** button writes a year-stamped report file.
- App.tsx wires `income`, `expenses`, `reports` to real views; placeholder `PlaceholderView` is finally removed.

## [0.3.0] — 2026-05-20

### Added

- **Phase 3 — Scheduling engine + Reminders.**
- Migration `006_schedules.sql` adds `schedules` and `occurrences` tables. Five default schedules pre-seeded per spec: Fan Site Posting CoC/PoA (10 days before next month), Income update (3 days after month end), CoC release (weekly Mon + Thu), PoA release (weekly Wed + Fri).
- **No-cron Cadence engine** (`src/lib/cadence.ts`) modeled after `PurpleTracker/Sources/PurpleTracker/Models/Cadence.swift`. Six cadence kinds — `daily`, `weekly` (with day-of-week mask + everyN for biweekly), `monthly_dom` (clamped to end-of-month), `monthly_days_before_next`, `monthly_days_after_eom`, `every_n_days`. Pure functions: `nextOccurrencesAfter(cadence, from, count)`, `describeCadence(cadence)`, `isCadenceValid(cadence)`.
- **Occurrence materializer** (`src/data/occurrences.ts`) runs on app launch and every 30 minutes, populating occurrences for the next 60 days. Idempotent via `UNIQUE(schedule_id, due_at)` — re-runs no-op.
- **Reminders view** with two tabs: *Reminders* (Overdue / Today / Coming up next 7 days / Recently done) and *Schedules* (list + active toggle + edit + delete).
- **Schedule wizard** with cadence builder, weekday checkbox grid for weekly, three monthly flavors (Nth of month / N days before next month / N days after EOM), and a live "Next 5 dates" preview. No cron strings shown to the user, ever.
- **Satisfying check-off**: tap the circle → persona-tinted confetti burst (`CheckOffBurst` component, CSS-only, no canvas-confetti dep), 10-second **Undo** toast in the bottom-right.
- **Sidebar bell badge** showing combined overdue + today count for the active persona.
- **Home dashboard "today's reminders" widget** at the top, with one-click jump to the Reminders view.

## [0.2.2] — 2026-05-20

### Fixed

- **All database writes were blocked by ACL.** Tauri 2's `sql:default` capability set only grants `load` + `select`; the `execute` permission has to be added explicitly. This silently broke every customer save, site edit, taxonomy add, AND every clip imported via the MasterClipper wizard (which surfaced the error as "Command plugin:sql|execute not allowed by ACL"). Added `sql:allow-load` / `sql:allow-execute` / `sql:allow-select` / `sql:allow-close` to `capabilities/default.json`.

## [0.2.1] — 2026-05-20

### Fixed

- **Importer no longer appears stuck.** Large MasterClipper exports were silently grinding through SELECT+INSERT/UPDATE pairs with no UI feedback, so the screen sat on "⏳ Importing… don't close the app." indefinitely. Now:
  - `upsertClip` does `INSERT OR IGNORE` first and only falls back to a targeted UPDATE if the row already existed (fresh imports cost 1 IPC round-trip instead of 2).
  - The wizard shows a live counter (`Importing… 47 of 543 · 47 added, 0 updated`) plus a progress bar, and yields to the event loop every 25 rows so React can repaint.
  - The post-loop work runs in a `finally` block, so `setStage('done')` always fires — a thrown `logImport` or refresh callback can no longer trap the UI in the "running" state.
  - Per-row errors are captured and shown in an expandable list in the summary (instead of silently inflating the "skipped" count).

## [0.2.0] — 2026-05-20

### Added

- **Phase 2 — Calendar, MasterClipper import, Dashboard.**
- Migration `005_clips.sql` adds `clips` (PK = MasterClipper UID, so re-imports UPSERT cleanly) and a small `clip_imports` audit table for the "recent imports" widget.
- **MasterClipper CSV importer** (`src/views/Import/MasterClipperImport.tsx`): file picker → preview rows → per-source-persona mapping screen → bulk UPSERT → run summary (`{inserted, updated, skipped}`). Reads files via the webview's File API (no Tauri-side fs permission needed). Logs every run to `clip_imports`.
- **RFC 4180 CSV parser** (`src/lib/csv.ts`, ~60 lines) — quoted fields, embedded commas / newlines, CRLF, BOM. Avoids adding papaparse to the bundle.
- **Calendar view** (`src/views/Calendar/CalendarView.tsx`): month grid (6×7) with prev/next/today, persona-colored clip pills per day, click to open `ClipDetail`. Respects the active persona filter.
- **Clip detail modal** (`src/views/Calendar/ClipDetail.tsx`): all imported fields read-only + editable `mollyNotesHtml` (Tiptap) that is preserved across re-imports. Delete is two-tap.
- **Clips list view** with search, sort (`go_live` / `title` / `status` / `persona`), and an inline "📂 Import CSV" button that opens the wizard.
- **Home dashboard** widgets: MTD vs Prior MTD vs YTD vs all-time counts, per-persona breakdown bars, **reuse detection** (same `external_clip_id` OR same title within 14 days), recent-imports log. Filterable by active persona.
- `clipCounts`, `countByPersona`, `detectReuse`, `recentImports` data helpers in `src/data/clips.ts`.

### Changed

- Sidebar `Home` is now the dashboard (replaces the static welcome card).
- App.tsx wires `calendar` / `clips` view keys to real implementations.

## [0.1.0] — 2026-05-20

### Added

- **Phase 1 — Settings, Customers, Molly Helper.** First real feature drop on top of the Phase 0 shell.
- **Settings tabs**: Personas / Sites / Products / Interests / Backup.
- **Personas settings**: rename, redescribe, recolor (5 swatches per persona: primary / secondary / tint / accent / text). Edits live-update the active theme via `onPersonasChanged → refresh`.
- **Sites settings**: full CRUD with per-site color, short code, URL, username, free-form note, sort order, and an optional `loginGroup` flag for shared-login sites (e.g. OnlyFans CoC ↔ PoA). Grouped by persona; respects the active persona filter.
- **Preloaded sites** (per spec): 5 for CoC, 13 for PoA (NiteFlirt has four entries — main + Alice + Taylor + sluttysecrets). OnlyFans rows share `loginGroup = "of-shared"`.
- **Products / Interests settings**: identical CRUD pattern. Defaults preloaded: Phone, Cam, Customs, Physical-Panties/Pantyhose/Shoes Flats/Heels for products; Feet, Pantyhose, Panties, Humiliation for interests.
- **Customer tracker**:
  - UID format `YYYY-MM-DD-#####` (mirrors `MasterClipper/Sources/MasterClipper/Services/IDGeneratorService.swift`, computed in `src/lib/uid.ts`).
  - Fields: username, real name, 5 email slots, persona binding (or unbound for cross-persona contacts), multi-select product chips, multi-select interest chips, **rich-text notes** via Tiptap (StarterKit + Link + Placeholder).
  - List view with search across UID / username / real name and per-persona filter.
  - Detail editor with explicit Save (dirty-tracking) and ConfirmButton-guarded delete.
- **Molly Helper**: persona-grouped grid of clickable site cards. Top border tinted with each site's color; click **Open** to launch via `@tauri-apps/plugin-opener`; **Copy user** copies the saved username to clipboard. Shows `🔗 shared login` hint for sites in a login group.
- **Shared components**: `ColorPicker` (native `<input type="color">` + curated swatch row), `ChipMultiSelect`, `ConfirmButton` (two-tap guard), `RichTextNotes` (Tiptap with persona-themed lite-prose styling).
- **Migrations**: `002_sites.sql`, `003_taxonomy.sql`, `004_customers.sql` wired into the plugin's migration list in `src-tauri/src/lib.rs`.

### Changed

- `state/personas.ts` is now a thin hook over `data/personas.ts` (extracted CRUD), exposing a `refresh()` so persona edits propagate to the switcher immediately.
- App.tsx wires the new SettingsView / CustomerListView / MollyHelper routes; placeholder cards remain for the calendar / clips / income / expenses / reports areas.

## [0.0.1] — 2026-05-20

### Added

- **Phase 0 — Foundation.** Initial scaffold of the Molly app.
- Tauri 2 + React 19 + TypeScript + Tailwind CSS + Vite project layout.
- AI-generated app icon set (`.icns`, `.ico`, full PNG ladder).
- SQLite migration `001_init.sql` with `personas` and `app_settings` tables.
- Three preloaded personas (Curse Of Curves / Princess of Addiction / Sheer Attraction) with primary/secondary/tint/accent/text colors.
- **Persona switcher** in the top bar (`CoC` / `PoA` / `Sa` / `★ All`); the whole UI recolors via CSS custom properties.
- Fixed-width sidebar (240px) with `Ctrl+S` / `⌘+S` toggle. (Avoids `NavigationSplitView` — Tauri uses Flexbox, immune to that AppKit bug, but the convention still matches PhantomLives.)
- **Backup-on-launch service** (Rust port of `Timeliner/Services/BackupService.swift`):
  - Default location `~/Downloads/Molly backup/` (Mac) / `%USERPROFILE%\Downloads\Molly backup\` (Windows).
  - 14-day retention default (0 = keep forever).
  - 5-minute launch debounce.
  - Only trims archives matching `Molly-*.zip`; unrelated files are never touched.
  - **Test** (verify), **Restore** (with mandatory pre-restore safety archive), and **Reveal** actions.
- Settings → Backup UI with toggle, path picker, retention stepper, Run Backup Now, Reveal in Finder/Explorer, recent backups list with per-row Test/Restore/Reveal.
- `install.sh` follows the PhantomLives standard: quit running copy, `ditto --noextattr` to `/Applications/Molly.app`, relaunch (`--no-open` to suppress).
- `build-app.sh` runs `pnpm tauri build` then auto-chains into `install.sh` (`BUILD_ONLY=1` / `--no-install` escape hatches).
- `run-tests.sh` runs `cargo test --lib` against the Rust backend.
- Backup module unit tests: debounce, retention trim (only Molly-prefixed zips), target dir auto-create, listing order, missing database flag.
- GitHub Actions workflow `.github/workflows/release.yml` cross-builds signed `.dmg` and `.exe` on `v*` tag push via `tauri-action`.
- `tauri-plugin-updater` wired to a GitHub Releases `latest.json` endpoint (public key placeholder; replace before signed Phase 5 release).

### Notes

- Out of Phase 0 scope: calendar, MasterClipper import, scheduler/reminders, income, expenses, customers, Molly Helper, reports.
- The updater public key in `tauri.conf.json` is a placeholder — it must be replaced with a real key before publishing a signed update.
