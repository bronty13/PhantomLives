# Changelog

All notable changes to Molly are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Molly uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
