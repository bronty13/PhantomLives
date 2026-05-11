# HANDOFF — PurpleTracker

This document is a quick orientation for anyone (human or agent) picking up
PurpleTracker maintenance.

## What it is

A native macOS SwiftUI app that assigns a Matter ID
(`YYYY-MM-DD-#####`) to every unit of work and tracks type, status, time,
attachments (with hashes), notes, file-store paths, external refs, exports,
and runs an auto-backup on every launch. Built on Swift 5.10 + SwiftUI +
GRDB 6 + XcodeGen, targets macOS 14, modeled directly on the sibling
`Timeliner/` subproject.

## Repository layout

```
PurpleTracker/
  project.yml                     # XcodeGen — single source of truth for the project
  build-app.sh  run-tests.sh      # bash wrappers around xcodebuild
  Vendor/GRDB/                    # vendored GRDB 6.29.3 (see "Why vendored" below)
  Sources/PurpleTracker/
    App/                          # @main, AppState, Info.plist, entitlements, Version
    Models/                       # Matter, MatterType, MatterStatus, Attachment,
                                  # TimeEntry, Note, Cadence, AppSettings, ColorHex
    Services/                     # Database, MatterID, Backup, Attachment,
                                  # FileStore, Timer, Cadence, Export
    Views/
      Sidebar/  MatterList/  MatterDetail/  Time/  Settings/  Shared/  Dashboards/
    Resources/Assets.xcassets/    # AppIcon + AccentColor
  Tests/PurpleTrackerTests/       # 9 XCTest classes, 50 tests
  README.md  USER_MANUAL.md  INSTALL.md  CHANGELOG.md  HANDOFF.md
```

## Build & test

```sh
xcodegen generate
./run-tests.sh        # 50 tests, ~1 s
./build-app.sh        # produces ./PurpleTracker.app
open ./PurpleTracker.app
```

The app is ad-hoc signed unless a Developer ID is present in the keychain.

## Key invariants

1. **Matter ID allocation is transactional.** `MatterIDService.allocateAndInsert`
   runs the counter advance and the matter insert inside the same GRDB write
   transaction. A failed insert releases the sequence — there are no gaps
   within a day. Tested in `MatterIDServiceTests.swift`
   (`testRollbackReleasesSequence`).

2. **Status auto-bump keys off lifecycle position, not name.**
   `AppState.bumpToInProgressIfNew` checks `statusValues[0].name` for the
   matter's current status and advances to `statusValues[1].name`. Renaming
   "New" → "Open" or "In-Progress" → "Active" is safe.

3. **Cadence terminal trigger keys off the last lifecycle value.**
   `AppState.updateMatterStatus` calls `CadenceService.spawnNext` when the
   new status equals `statusValues.last?.name`. Renaming "Closed" is safe.

4. **Attachment integrity uses SHA1.** MD5/SHA1/SHA256 are all stored at
   ingest, but `AttachmentService.verify(_:)` only recomputes SHA1 (per the
   user spec). Mismatch sets `last_verify_ok = false` and the row shows red.

5. **Auto-backup runs on launch, debounced to 5 minutes.** `BackupService`
   honours the PhantomLives standard from `../CLAUDE.md`. Default retention
   is **30 days** (overrides the standard's 14 per user spec); `0` = forever.

6. **CSV parser iterates `Unicode.Scalar`, not `Character`.** Swift collapses
   `\r\n` into one grapheme cluster — a `Character` equal to neither `"\r"`
   nor `"\n"`. Iterating by scalar is the only way to detect CRLF
   line endings reliably. `PeopleService.parseCSV` also strips a leading BOM
   and tolerates lone-`\r` (classic Mac) endings. Regression-tested in
   `PeopleImportRealFileTests`.

7. **People auto-import dedupes by filename, not contents.** The ADP feed
   rotates by date in the filename, so storing
   `lastImportedAdpFilename` in settings is sufficient and avoids re-hashing
   a multi-MB CSV every launch. Manual imports also update the marker.

8. **Priority is a fixed enum, not a configurable list.** The five levels
   (`P1 Critical` … `P5 Tech Debt`) are deliberately not user-renamable so
   cross-Matter reports stay comparable. `MatterPriority.parse(_:)` falls
   back to the default (`P3 Medium`) if a stored raw value doesn't match
   any case — defensive against legacy data and forward migrations.

9. **Initiatives & Goals are many-to-many via join tables.** Both join
   tables (`matter_initiative`, `matter_goal`) cascade-delete from both
   sides, so deleting an Initiative or Goal also untags it from every
   Matter — no orphan rows. Updating a Matter's tag set is a single
   transaction (delete-all + insert-set) so a failed mid-write can't leave
   a half-tagged row.

10. **Soft-delete invariant (1.3.0).** All Matter list reads filter
    `deleted_at IS NULL`. `AppState.deleteMatter` is now a soft-delete that
    sets `deleted_at`; `purgeMatter` is the only hard delete.
    `purgeExpiredTrash(olderThanDays: 30)` runs once on launch right after
    `BackupService`. The Trash sidebar section is the **only** place
    trashed Matters surface.

11. **Audit log is append-only.** `AppState.updateMatter` diffs the prior
    in-memory copy and emits an `AuditEvent` for every change to status,
    priority, type, or title. `created`, `deleted`, and `restored` are
    also recorded. Never `UPDATE` or `DELETE` from `audit_event`; cascade
    on Matter purge is the only removal path.

12. **Saved searches store JSON.** `saved_search.query_json` holds a
    `SearchCriteria` Codable struct (text/types/priorities/statuses/
    initiatives/goals/requestor/openOnly). `AppState.applySavedSearch`
    ANDs every populated field; `openOnly` defaults to true.

13. **Single global TimerService.** `TimerService.shared` is the only
    place a running timer lives. The menu-bar item, the running-timer
    banner, and ⌘⇧Space all subscribe to it via Combine. Don't
    instantiate a second TimerService anywhere.

14. **TimeByTagReport even-split.** A TimeEntry's seconds are split
    **evenly** across all tagged Initiatives (or Goals) on the parent
    Matter — documented in `TimeByTagReport.swift`. If you change to a
    weighted split, also update `USER_MANUAL.md`.

15. **Third Parties — effective actual rule (1.4.0).**
    `vendor_year_amount.actual_cents` is `Int64?` (nullable).
    `VendorInvoiceService.effectiveActuals` returns
    `override ?? SUM(vendor_invoice.amount_cents) for the year`. An
    *explicit zero override* therefore wins over a non-zero invoice
    sum — clearing the override (setting it back to NULL) is the only
    way to fall back to the rollup. Tested in `VendorInvoiceRollupTests`.

16. **Third Parties — invoice year is mirrored from date.**
    `VendorInvoiceService.insert/update` recomputes
    `vendor_invoice.year` from `invoice_date` on every write so that
    callers can backdate an invoice and it lands in the correct yearly
    bucket without extra ceremony. Tested:
    `testBackdatedInvoiceLandsInCorrectYear`.

17. **Third Parties — year range is a single global setting.**
    `AppSettings.thirdPartyYearStart` / `thirdPartyYearEnd` (defaults
    2026 / 2035) drive every Budget & Actuals matrix and every report
    column header. Per-vendor year ranges are deliberately *not* a
    thing — keeping reports comparable across vendors is the reason.
    Configurable under Settings → Third Parties.

18. **Third Parties — vendor attachments are a separate table.**
    `vendor_attachment` (BLOB, SHA1) is parallel to `attachment` but
    has a `kind` column (`contract` / `invoice` / `note` / `other`) and
    a nullable `parent_id` discriminator (vendor_invoice.id for invoice
    files, vendor_note.id for note files). The existing `attachment`
    table's `matter_id NOT NULL` made reuse impossible.

19. **Third Parties — vendor hard-delete is safe for matters.**
    `matter.vendor_id` was added with `ON DELETE SET NULL` in migration
    `v6_third_parties`, so purging a vendor unlinks every matter
    instead of cascade-deleting them. Tested:
    `testHardDeletingVendorSetsMatterVendorIdNull`. Note that the
    application currently exposes only soft-delete for vendors via
    `VendorService.softDelete`.

## Important files (where to look first)

| Concern                       | File                                                    |
|-------------------------------|---------------------------------------------------------|
| Schema & migrations           | `Sources/PurpleTracker/Services/DatabaseService.swift`  |
| Matter ID allocator           | `Sources/PurpleTracker/Services/MatterIDService.swift`  |
| App-state root + auto-backup + people auto-import + audit emit + soft-delete + trash purge | `Sources/PurpleTracker/App/AppState.swift`              |
| Type/status seeds             | `DatabaseService.seedDefaults`                          |
| Backup format & retention     | `Sources/PurpleTracker/Services/BackupService.swift`    |
| Cadence factory               | `Sources/PurpleTracker/Services/CadenceService.swift`   |
| Spell-checked editor          | `Sources/PurpleTracker/Views/Shared/SpellCheckTextEditor.swift` |
| DOCX/PDF/MD export            | `Sources/PurpleTracker/Services/ExportService.swift`    |
| Matter ID badge (large + copy)| `Sources/PurpleTracker/Views/MatterDetail/Components/MatterIDBadge.swift` |
| People CSV parser & importer  | `Sources/PurpleTracker/Services/PeopleService.swift`    |
| People-roster picker (one component drives Requestor + 5 IPs) | `Sources/PurpleTracker/Views/MatterDetail/Components/RequestorPicker.swift` |
| Priority enum + colors        | `Sources/PurpleTracker/Models/MatterPriority.swift`     |
| Initiative / Goal records     | `Sources/PurpleTracker/Models/Initiative.swift`, `Goal.swift` |
| Initiative / Goal settings UI | `Sources/PurpleTracker/Views/Settings/InitiativesSettingsView.swift`, `GoalsSettingsView.swift` |
| Tag chip flow layout          | `Sources/PurpleTracker/Views/Shared/FlowLayout.swift`   |
| App icon generator (Pillow)   | `Resources/make_icon.py`                                |
| Subtask / link / audit / saved-search models | `Sources/PurpleTracker/Models/Subtask.swift`, `MatterLink.swift`, `AuditEvent.swift`, `SavedSearch.swift` |
| Menu-bar timer item           | `Sources/PurpleTracker/App/AppDelegate.swift`           |
| Command Palette (⌘K)          | `Sources/PurpleTracker/Views/CommandPaletteView.swift`  |
| Dashboards                    | `Sources/PurpleTracker/Views/Dashboards/*.swift`        |
| URL autofill / .ics / email / integrity / time-by-tag / file-store status | `Sources/PurpleTracker/Services/URLAutofillService.swift`, `ICSExporter.swift`, `EmailParser.swift`, `IntegrityCheckService.swift`, `TimeByTagReport.swift`, `FileStoreStatusService.swift` |

## Test suite

Tests are XCTest, all `@MainActor` (services that touch `AppSettings`/UI
state are `@MainActor`-isolated). 50 tests across 9 files:

| File                          | What it covers                                           |
|-------------------------------|----------------------------------------------------------|
| `MigrationTests`              | v1–v5 create all tables; idempotency; new-column presence |
| `MatterIDServiceTests`        | padding, sequential, daily reset, rollback releases seq  |
| `AttachmentHashTests`         | RFC vectors for MD5/SHA1/SHA256 (empty + "abc"); verify mismatch |
| `CadenceServiceTests`         | each cadence kind + custom; copy/reset rules; IP + priority carry-forward |
| `BackupServiceTests`          | dir auto-create, retention trim, retention=0, list newest-first |
| `FileStoreServiceTests`       | template render, sanitisation                             |
| `ExportServiceTests`          | md/pdf/docx/clipboard smoke + brief format + IP rendering + priority/initiatives/goals |
| `StatusLifecycleTests`        | first time entry on "New" → "In-Progress"                |
| `PeopleServiceTests`          | parser quoting, escapes, display-name title-casing       |
| `PeopleImportRealFileTests`   | CRLF parser regression (real file + synthetic CRLF/BOM)  |
| `NewServicesTests`            | URL autofill (SNOW INC/REQ/RITM/CHG/TASK + ADO), `.eml` parser, ICS round-trip, time-by-tag MD |

## Why GRDB is vendored

The local Xcode toolchain forces `safe.bareRepository=explicit` on its child
`git` invocations (visible via `xcrun git config --list --show-origin`),
which makes SPM's bare-repo cache unusable on this machine. The workaround
is a shallow clone of GRDB at `Vendor/GRDB` referenced via a `path:` package
in `project.yml`. To bump the version: replace `Vendor/GRDB` with a fresh
shallow clone at the desired tag and re-run `xcodegen generate`.

## Known follow-ups & non-goals

- **Icon** — a generated purple "PT" squircle ships in
  `Sources/PurpleTracker/Resources/Assets.xcassets/AppIcon.appiconset`. Run
  `python3 Resources/make_icon.py` to regenerate or edit the generator to
  swap glyphs/colours. To use a designed icon, replace the PNGs in the
  appiconset and rerun `./build-app.sh`.
- **Notarisation** — out of scope for current releases (ad-hoc signed). To
  notarise, set up a Developer ID in the keychain; `build-app.sh` will pick
  it up.
- **iCloud/sync** — not implemented; everything lives in the local SQLite.
  Backups go to `~/Downloads/` so they're naturally swept up by Time Machine.
- **Attachment streaming** — attachments are read fully into memory for
  hashing and BLOB storage. Acceptable for the typical office-document use
  case; a streaming hasher would be needed for very large attachments.

## Releasing

The PhantomLives release-hygiene checklist applies:

1. Bump `Version.swift` to `1.0.x`.
2. Update `CHANGELOG.md`.
3. `./run-tests.sh` must pass.
4. `./build-app.sh` must succeed and the produced `.app` must launch.
5. Commit from the PhantomLives outer repo as a single subproject add.
