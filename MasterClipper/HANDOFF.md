# MasterClipper — Handoff

> Architecture snapshot. Read this before non-trivial changes. The original implementation plan lives in `~/.claude/plans/i-need-a-new-calm-grove.md`; the iOS-companion plan lives in `~/.claude/plans/i-would-like-to-playful-petal.md`. This doc is the up-to-date "how it actually works".

## Multi-target architecture (added 2026-05-12)

The project has grown from a single macOS app to three Xcode-visible targets:

- **`MasterClipper`** — the macOS app. Same code path as before.
- **`MasterClipperiOS`** — universal iPhone/iPad app, iOS 17+. Lives at `iOS/Sources/MasterClipperiOS/`. Reads a Mac-published snapshot from iCloud Drive; writes light edits back as JSON intent files. Same iCloud container ID as the Mac (`iCloud.com.bronty13.MasterClipper`) and the same `DEVELOPMENT_TEAM` (`SRKV8T38CD`).
- **`MasterClipperCore`** — local SPM package at `Packages/MasterClipperCore/`. Shared models + search + intent envelope + CloudKit share schema. Re-exports GRDB. Both app targets depend on it.

Both app targets are declared in the same `project.yml`; xcodegen produces a single `.xcodeproj` with both schemes. iCloud + CloudKit entitlements + the team ID are all declarative in `project.yml`, so a regen never blanks them.

### Personal sync transport (Mac ↔ your own iPhone/iPad)

- Mac publishes a read-only SQLite snapshot + thumbnails + manifest into `iCloud.com.bronty13.MasterClipper/Documents/snapshot/`. `Services/Sync/SnapshotPublisher.swift` runs `VACUUM INTO` against the live `DatabasePool`, copies thumbnails from each clip's `production_folder`, builds an FTS5 `clips_fts` index inside the snapshot DB, writes `manifest.json` (schema_version, generated_at, clip_count, publisher_device_id), and atomic-swaps the result into place via `NSFileCoordinator`. 30s debounced trigger after any mutation; **Settings → Sync → Publish now** for an immediate publish. Opt-in via `AppSettings.iCloudPublishEnabled`.
- iOS reads the snapshot via `iOS/Sources/MasterClipperiOS/Sync/SnapshotReader.swift`: downloads via `startDownloadingUbiquitousItem`, copies into sandbox `Caches/snapshot.sqlite` (`NSFileCoordinator` read; old `DatabaseQueue` is dropped before the file is replaced to avoid SQLite vnode-unlinked warnings), opens as read-only `DatabaseQueue`. `NSMetadataQuery` reacts to new manifests and triggers a reload. `BGAppRefreshTask` (id `com.bronty13.MasterClipper.refreshSnapshot`) refreshes the cache in the background so the next launch is instant.
- iOS edits flow back as JSON `IntentEnvelope` files in `iCloud.../Documents/intents/pending/<uuid>.json` via `Sync/IntentOutbox.swift`. The Mac's `Services/Sync/IntentInbox.swift` watches that folder with `NSMetadataQuery`, decodes each envelope, calls `DatabaseService.apply(intent:)`, moves the file to `applied/` (or `conflicts/`) on completion. Idempotency via the `applied_intents` SQLite table (migration `v15_intent_idempotency`).

### External-share transport (Mac → someone else's iOS)

- `Services/Sync/ShareManager.swift` creates one CloudKit zone per share, named `share-<uuid>`, in the user's private CK database. Each zone contains: one `SharedClip` CKRecord per shared clip (with thumbnail as `CKAsset`), one singleton `ShareMetadata` record (expiry / permission / label / clipCount), and a `CKShare` anchored on the metadata record as its rootRecord. `createShare(...)` returns the participation URL the user can text/email to a recipient.
- `Services/Sync/ShareExpiryScheduler.swift` arms a one-shot timer at the next-expiring share's `expiresAt` and re-arms on every active-shares list change. Belt-and-suspenders sweep at launch.
- Recipient flow (iOS): `App/AppDelegate.swift` (wired via `UIApplicationDelegateAdaptor`) catches `application(_:userDidAcceptCloudKitShareWith:)` and forwards to `Sync/SharedZoneReader.swift` through `NotificationCenter`. SharedZoneReader accepts via `CKAcceptSharesOperation`, enumerates `sharedCloudDatabase` zones, decodes `SharedShareSession`s. `Views/SharedTabView.swift` surfaces only when at least one share is accepted; `RootView` swaps to a `TabView` in that case.
- Read-write recipients edit through `Views/SharedEditSheet.swift` and `Sync/SharedZoneEditor.swift`. Each edit becomes a `SharedClipEdit` CKRecord wrapping a JSON-encoded `IntentEnvelope`. The Mac's `Services/Sync/SharedZoneSync.swift` polls every 60s (no `aps-environment` entitlement needed; CK push subscriptions are out of scope), decodes each `SharedClipEdit`, hands it to the existing `DatabaseService.apply(intent:)`, deletes the record on success. Reuses the `applied_intents` idempotency table.
- All CK enumeration uses `CKFetchRecordZoneChangesOperation`, not `CKQuery`. Auto-created CK schemas don't mark `recordName` as Queryable, so any `TRUEPREDICATE` `CKQuery` fails with "Field 'recordName' is not marked queryable". Zone-changes walks bypass the problem entirely.

### Repository layout addendum

```
MasterClipper/
├── Packages/MasterClipperCore/                 (new SPM package, both targets depend on it)
│   └── Sources/MasterClipperCore/
│       ├── Models/                             (15 model files, ClipCategory renamed from Category)
│       ├── Database/{Snapshot,ClipQueries}.swift
│       ├── Search/SearchService.swift
│       ├── Util/FuzzyMatch.swift
│       └── Intents/{IntentEnvelope, CKShareSchema, SharedClipRow}.swift
├── Sources/MasterClipper/                       (unchanged)
│   └── Services/Sync/                          (new)
│       ├── SnapshotPublisher.swift
│       ├── IntentInbox.swift
│       ├── ShareManager.swift
│       ├── ShareExpiryScheduler.swift
│       └── SharedZoneSync.swift
└── iOS/                                         (new)
    └── Sources/MasterClipperiOS/
        ├── App/{MasterClipperiOSApp, AppDelegate, Info.plist, .entitlements}
        ├── Resources/Assets.xcassets/AppIcon.appiconset  (1024×1024 source; Xcode generates rest)
        ├── State/iOSAppState.swift
        ├── Sync/{SnapshotReader, IntentOutbox, BackgroundRefresh, SharedZoneReader, SharedZoneEditor}.swift
        └── Views/{ClipListView, ClipDetailView, FilterSheet, SettingsView, EditClipSheet, SharedTabView, SharedClipDetailView, SharedEditSheet}.swift
```

---

## Original handoff continues below


## Mental model

- **`AppState`** (`@MainActor` `ObservableObject`) is the single source of truth surfaced to views. It owns `SettingsStore`, holds `@Published` arrays for clips / personas / sites / categories / calendar rules, and exposes mutation methods that always go through `DatabaseService` and re-read the affected slice.
- **`DatabaseService`** is a singleton owning a GRDB `DatabasePool` at `~/Library/Application Support/MasterClipper/masterclipper.sqlite`. It runs append-only migrations, owns the seed data, and is the only place that talks to SQLite.
- **`SettingsStore`** owns a Codable `AppSettings` value, persists it as JSON at `~/Library/Application Support/MasterClipper/settings.json`, and exposes `resolvedBackupPath` / `resolvedExportDirectory` computed properties that fall back to the `~/Downloads/MasterClipper{,-backup}/` defaults when the user hasn't overridden them.
- **Status is auto-derived, but overridable.** `clip.status` is recomputed by `DatabaseService.computeStatus(for:in:)` on every `insertClip` / `updateClip` / `upsertPosting`. The status badge in `ClipEditView` is a `Menu` — picking a status opens a confirmation alert, then `AppState.setClipStatusOverride` writes a non-null `clips.status_override` (v13). When the override is set, `computeStatus` returns it verbatim and the heuristic is bypassed; the menu's *Clear manual override* item nulls the column to return to auto-derivation.

Mutation flow: View → `appState.someMutation(...)` → `DatabaseService.shared.<method>` (single GRDB transaction) → `appState.reloadX()` → `@Published` slice changes → SwiftUI re-renders.

## Stack

| Layer | Choice |
|---|---|
| App platform | macOS 14+, SwiftUI, Swift 5.10 |
| Project layout | XcodeGen (`project.yml`) → `MasterClipper.xcodeproj` |
| Build / sign | `./build-app.sh` (auto-versioned from `git rev-list --count HEAD`, ad-hoc or Developer ID, builds in `/tmp`) |
| Database | GRDB.swift 6 — `DatabasePool`, `DatabaseMigrator`, append-only (currently at `v10`) |
| LLM | Ollama on `http://localhost:11434`, default model auto-picked from `/api/tags` |
| Speech-to-text | Sibling `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` (MLX Whisper). Shelled out via `Process` with `-o -` to capture stdout. |
| AVFoundation | `AVAssetExportSession` for re-encode (HEVC + H.264 preset tiers); `AVAssetImageGenerator` for frame capture |
| Hashing | `CryptoKit` `Insecure.MD5` / `Insecure.SHA1` / `SHA256`, streamed in 4 MB chunks |
| Backup | `/usr/bin/zip -rqX` of Application Support dir, throttled 60 s, retention-trimmed |
| Import (xlsx) | Manual reader: `/usr/bin/unzip -p` streams `xl/sharedStrings.xml`, `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/worksheets/sheetN.xml`; SAX-parsed by Foundation `XMLParser` |
| Export | OOXML for XLSX/DOCX (manual + `/usr/bin/zip`), `CGContext(consumer:)` for PDF, static HTML pre-rendered server-side for mobile-friendly self-contained reports |

## Source layout

```
Sources/MasterClipper/
├── App/
│   ├── MasterClipperApp.swift            @main, WindowGroup, Settings scene, AppMenuCommands
│   ├── AppState.swift                    @MainActor ObservableObject — single source of truth
│   ├── AppMenuCommands.swift             Menu bar items + Notification.Name extensions (incl. Window → Reset Window State…)
│   ├── Version.swift                     Generated by build-app.sh
│   ├── Info.plist
│   └── MasterClipper.entitlements        sandbox + network.client + downloads.read-write
├── Models/
│   ├── Clip.swift                        + ClipStatus enum (auto-derived pipeline)
│   ├── ClipPosting.swift                 + PostingStatus
│   ├── ClipHistoryEntry.swift            per-field change log
│   ├── Site.swift                        with persona_scope CSV + appliesTo helper
│   ├── Persona.swift
│   ├── Category.swift
│   ├── CalendarEvent.swift
│   ├── CalendarRule.swift
│   ├── ClipSegment.swift                 per-`.mov` row: filename + ctime + size + MD5/SHA-1/SHA-256
│   ├── PriceEntry.swift
│   ├── AppSettings.swift                 + SettingsStore + default refine prompt + legacy prompts
│   ├── Theme.swift                       Default / Midnight / Ocean / Forest / Sunset / Rose
│   ├── ImportModels.swift                ClipFieldKey enum, ParsedClipRow, ImportSession
│   └── PostingFilter.swift               for dashboard ↔ Clips list filter handoff
├── Services/
│   ├── DatabaseService.swift             singleton, owns dbPool, runs migrator + seeds, computeStatus
│   ├── BackupService.swift               run / list / verify / restore
│   ├── XLSXReader.swift                  /usr/bin/unzip -p + XMLParser
│   ├── ImportService.swift               orchestrator + commitClips + commitCalendarEvents + parseCategories
│   ├── ExportService.swift               CSV / MD / XLSX / DOCX / PDF (full + per-clip)
│   ├── HtmlExportService.swift           static-first, mobile-friendly card grid
│   ├── OllamaService.swift               nonisolated static refine(...) — temperature 0
│   │                                     + cleanRefineOutput / stripWrappingQuotes / normalizeParagraphFormat
│   ├── OllamaSetup.swift                 binary detection + auto-start
│   ├── CalendarService.swift             generateYear, eventsByDate, dateRange
│   ├── IDGeneratorService.swift          atomic UPSERT against id_sequences
│   ├── PostingService.swift              clipsNotPosted, markPosted, postedSitesByClip
│   ├── ReportService.swift               postingStatus, categoryUsage, calendarRollup, weeklyRollup
│   ├── ClipAuditService.swift            7-point clip checklist (per-clip + bulk)
│   ├── FileAuditService.swift            9-point file audit + rename suggestions + pushFromFCP + provisionProductionFolder + promoteFrameToThumbnail
│   ├── ClipReduceService.swift           AVAssetExportSession iterative re-encode under threshold
│   ├── ClipSegmentService.swift          enumerate + hash (MD5/SHA-1/SHA-256) + persist clip_segments rows
│   ├── VideoFolderService.swift          enumerate .mov + microsecond-precision ctime + collision-free reorder rename
│   ├── FrameCaptureService.swift         AVAssetImageGenerator → <Title>_frame_NN.png
│   ├── HashService.swift                 CryptoKit MD5 / SHA-1 / SHA-256 streaming
│   ├── TranscriptionService.swift        shells out to sibling transcribe.py
│   ├── PathDefaultsService.swift         compute / backfill production + FCP folder paths
│   ├── SearchService.swift               AND-token LIKE
│   ├── FuzzyMatch.swift                  Levenshtein + alias dict for column auto-mapping
│   ├── C4SHistoricalImportService.swift  XLSX + pipe-CSV parser; ZIP-magic content sniff
│   └── HistoricalCategoryBackfillService.swift  title-match planner — exact / strong / maybe / unmatched buckets
├── Views/
│   ├── ContentView.swift                 VStack { TopTabBarView; DetailRouterView } — Editorial chrome root
│   ├── Sidebar/
│   │   ├── TopTabBarView.swift           Editorial top tab bar (brand mark + 8 tabs + clock + ⌘N pill)
│   │   ├── SidebarView.swift             (legacy NavigationSplitView sidebar — no longer routed; kept for reference)
│   │   └── DashboardView.swift           Editorial dashboard: meta column (eyebrow/headline/deck/personas/pipeline) + content column (number strip + clip×site table + per-target list)
│   ├── Clips/
│   │   ├── ClipListView.swift            master Table; persona/status/posting/archived filters; AND-token search
│   │   ├── ClipDetailView.swift          right pane router
│   │   ├── ClipEditView.swift            sticky header, full form, auto-save on disappear, refine button,
│   │   │                                 transcript section, integrity (hashes) section, file-audit launch
│   │   ├── ClipHistoryView.swift         change log disclosure
│   │   ├── ClipExportSheet.swift         per-clip plain-text / MD / PDF
│   │   ├── NewClipView.swift             sheet
│   │   ├── PostingGrid.swift             site × posted toggle inside the editor
│   │   ├── CategoryChipPicker.swift      + FlowLayout
│   │   ├── LengthField.swift
│   │   ├── ClipWorkflowView.swift        new-clip sheet: identity + metadata + source-folder browser + Copy Status
│   │   ├── FileAuditWorkflow.swift       single source of truth for Verify Files — per-clip from ClipEditView (passes [draft]) and bulk from PostingQueueView / EditingQueueView; All / Issues-only filter; Skip / Previous / Next
│   │   └── ThumbnailFramePicker.swift    LazyVGrid of frame previews, parent-owned `picked` Binding
│   ├── Editing/
│   │   ├── EditingQueueView.swift        new / editing / to_post filter chips, Run File Verification toolbar
│   │   └── EditingWorkflowView.swift     post-new-clip handoff: audit summary + notes textarea → clip.notes
│   ├── Posting/
│   │   ├── PostingQueueView.swift        to_post / posting parallel to Editing Queue, per-site progress pills
│   │   ├── PostingBatchView.swift        drill-down: Sites → Queue → Posting
│   │   ├── PostingTarget.swift           PostingTargets.expanded(appState:)
│   │   └── PostingClipWindow.swift       per-field copy buttons + Mark posted + Posted & next
│   ├── Calendar/
│   │   └── CalendarRootView.swift        Year/Quarter/Month/Week/Day, augments from clip.goLiveDate
│   ├── Import/
│   │   └── ImportWizardView.swift        5-step wizard (Source → Sheets → Mapping → Preview → Done)
│   ├── Reports/
│   │   ├── ReportsRootView.swift         Full clip / Posting status / Category usage / Calendar rollup / Audit / Information needed
│   │   ├── WeeklyReportView.swift        Last / This / Next week + "Not in production" list
│   │   ├── ClipAuditReportView.swift     bulk audit cards, click → clip editor
│   │   ├── InformationNeededReportView.swift  new/editing clips missing desc / cats / go-live + Copy for creator
│   │   └── ReportExportMenu.swift        per-report MD / PDF / CSV menu + auto-reveal + persistent Reveal
│   ├── C4SHistorical/
│   │   ├── C4SHistoricalView.swift       table + detail HSplitView; toolbar Backfill / Import buttons
│   │   ├── C4SHistoricalImportSheet.swift  file picker + store toggle + 3-row preview
│   │   └── HistoricalCategoryBackfillSheet.swift  per-row checkboxes across the four match buckets
│   ├── Settings/
│   │   ├── SettingsView.swift            10-tab TabView
│   │   ├── PersonasSettingsTab.swift     ColorPicker for persona colour
│   │   ├── CategoriesSettingsTab.swift   uppercase-on-input
│   │   ├── SitesSettingsTab.swift        persona-scope checkboxes
│   │   ├── CalendarRulesTab.swift
│   │   ├── PostingSettingsTab.swift      exclusion-reason dropdown CRUD
│   │   ├── OllamaSettingsTab.swift       prompt template editor + Reset to default + Test refine
│   │   ├── ImportExportTab.swift
│   │   ├── FileLocationsTab.swift        path defaults + frame count + threshold + one-shot backfill
│   │   └── BackupSettingsTab.swift       Run / Test / Restore / Reveal / Wipe
│   └── Shared/
│       ├── HexColor.swift                Color(hex:) + Color.toHex()
│       ├── PersonaPill.swift             gradient capsule with heart icon
│       ├── DurationFormatter.swift       mm:ss / hh:mm:ss
│       ├── EditorialTheme.swift          Editorial design system: palette (bone/ink/acid), typography (EdFont serif/sans/mono), reusable views (EdEyebrow/EdHeadline/EdDeck/EdSectionHeading/EdStatusPill/EdSiteCell/EdNumberCell/EdPersonaSwatch/EdHairline/EdPanel/EdPageShell), button styles (EdAcidPillButtonStyle/EdInkPillButtonStyle/EdGhostButtonStyle), `.editorialChrome()` root modifier
│       └── ComingSoonView.swift
└── Resources/
    ├── Assets.xcassets/AppIcon.appiconset/...
    └── Fonts/                             Source Serif 4 (Light/Regular/Semibold/Bold + italics), Inter Tight (variable, regular + italic), JetBrains Mono (Regular/Medium/SemiBold) — auto-registered via ATSApplicationFontsPath = "."
```

## Editorial UI

The whole app uses a custom Editorial design language (bone canvas, ink ruling, single acid-yellow accent, magazine typography). The chrome is a top tab bar — `TopTabBarView` over a flat `DetailRouterView` — *not* a `NavigationSplitView`. Every section view starts with an `EdPageShell` masthead (mono eyebrow → serif headline with optional acid-highlighted em word → italic deck → hairline rule). All shared visual primitives live in `Views/Shared/EditorialTheme.swift`. When you reach for a SwiftUI default (`.background.secondary`, `Capsule()`, `RoundedRectangle`), prefer the Editorial equivalents (`EdColor.bone`, `Rectangle().strokeBorder(EdColor.ink, lineWidth: 1)`, `EdHairline`).

## Database schema

13 tables, thirteen migrations (`v1_initial` … `v13_status_override`). `grdb_migrations` is the GRDB-managed bookkeeping table.

```
personas        (id, code UNIQUE, display_name, color_hex, sort_order, archived)
sites           (id, code UNIQUE, display_name, persona_scope CSV, sort_order, archived)
categories      (id, name UNIQUE, sort_order, archived)
clips           (id PK TEXT "YYYY-MM-DD-#####", external_clip_id, tracking_tag,
                 persona_code, title, description_raw, description_refined,
                 keywords, performers,
                 clip_filename, thumbnail_filename, preview_filename,
                 length_seconds, price_cents, sales_count, income_cents,
                 content_date, go_live_date,
                 fcp_project_folder, production_folder,
                 status, archived, notes,
                 transcript,                                    -- v6 (whisper output)
                 mp4_md5, mp4_sha1, mp4_sha256, mp4_size_bytes, -- v7 (file integrity)
                 reduced_md5, reduced_sha1, reduced_sha256, reduced_size_bytes,
                 hashes_computed_at,
                 posting_excluded, exclusion_reason, exclusion_notes, -- v8 (do-not-post flag)
                 status_override,                                     -- v13 (manual status pin)
                 created_at, updated_at)
clip_categories (clip_id, category_id, position, PK)            -- position added in v5
clip_postings   (clip_id, site_id, posted_date, status, notes, created_at, updated_at, PK)
clip_history    (id, clip_id, field, old_value, new_value, changed_at)
id_sequences    (date_key PK "yyyyMMdd", last_seq)
calendar_events (id, date, persona_code, clip_id, title, notes, created_at, updated_at;
                 UNIQUE INDEX on (date, persona_code))
calendar_rules  (persona_code, weekday 1–7, enabled, PK)
prices          (id, label, price_cents, notes)
exclusion_reasons (id, label UNIQUE, sort_order, archived)      -- v8 (configurable dropdown)
c4s_historical  (id, store, clip_status, clip_id, tracking_tag, -- v11 (C4S storefront snapshot)
                 title, description_text, categories, keywords,
                 clip_filename, thumbnail_filename, preview_filename,
                 performers, price_cents, sales_count, income_cents,
                 imported_at)
clip_segments   (id, clip_id FK→clips ON DELETE CASCADE,        -- v12 (per-`.mov` source-file snapshot)
                 position, filename, creation_date,
                 size_bytes, md5, sha1, sha256, hashed_at,
                 created_at, updated_at;
                 UNIQUE(clip_id, position))
```

Migration log:
- **v1_initial** — base schema + seed data (4 personas, 5 sites, calendar rules).
- **v2_clip_history** — append-only field-change log.
- **v3_editing_pipeline** — `fcp_project_folder` + `production_folder` columns.
- **v4_persona_color_refresh** — replace placeholder persona hexes with real defaults.
- **v5_clip_categories_order** — `position` column on `clip_categories` (per-clip ordered tags).
- **v6_clip_transcript** — `transcript` text column.
- **v7_clip_hashes** — file-integrity hashes + sizes.
- **v8_categories_uppercase_and_exclusions** — uppercase + dedupe existing category names, add `posting_excluded` / `exclusion_reason` / `exclusion_notes` to `clips`, create the `exclusion_reasons` lookup table seeded with three default reasons.
- **v9_recompute_clip_status** — data-only sweep. Earlier `PostingService.markPosted` wrote posting rows directly via `row.save(db)`, bypassing the clip-status recompute that lives inside `upsertPosting`. Walks every active clip and snaps `status` to whatever `computeStatus` says now; writes a `clip_history` row per flip.
- **v10_status_for_excluded_and_no_scope** — second data sweep after `computeStatus` learned two new shortcuts: `postingExcluded == true` → `production`, and "no scoped sites + editing complete" → `production`. Same per-flip history-row pattern.
- **v11_c4s_historical** — `c4s_historical` table (one row per C4S storefront clip per store) plus indexes on `store` and `clip_id`. Driven by `C4SHistoricalImportService` which parses both the `.xlsx` export and the pipe-delimited `.csv` export (C4S misnames it CSV — fields are `|`-separated with quoted multi-line descriptions). `DatabaseService.replaceC4SHistorical(store:with:)` does a single-transaction `DELETE WHERE store = ?` + insert.
- **v12_clip_segments** — `clip_segments` table for per-`.mov` source-file metadata captured at New-Clip workflow time. One row per file (1.mov, 2.mov, …) with microsecond-precision ctime + MD5/SHA-1/SHA-256 + size. FK references `clips(id) ON DELETE CASCADE`; `UNIQUE(clip_id, position)` blocks duplicate positions. Replaced wholesale per clip via `replaceSegments(forClip:with:)` (single transaction, DELETE + INSERT). Computed off the main thread by `ClipSegmentService` via `HashService` streaming.
- **v13_status_override** — nullable `clips.status_override` column. When set, `computeStatus` returns it verbatim and the editing/posting heuristic is bypassed. Written via `setStatusOverride(clipId:override:)` which also stamps a `[Status YYYY-MM-DD: old → new (manual)]` marker into `clip.notes` and records `status` + `status_override` rows in `clip_history`. The editor's status `Menu` exposes the picker with an *Are you sure?* confirmation alert; clearing nulls the column.

Migrations are append-only — never edit a previously-shipped one. To change the schema, register a new `vN_…` migration in `DatabaseService.migrate()` after all the existing ones.

## Key invariants

- **Clip primary key** is `YYYY-MM-DD-#####`, where the date prefix is the clip's `content_date` if known, else today. Allocation runs through `IDGeneratorService.next(forContentDate:)` inside one GRDB transaction against `id_sequences`. The 5-digit suffix expands automatically (no zero-pad) past 99 999.
- **Title rename** auto-appends `[Renamed YYYY-MM-DD: "old" → "new"]` to `notes` inside `DatabaseService.updateClip`. Always in one `dbPool.write { db in ... }`.
- **Auto-derived status.** Set anywhere `clip` is inserted or any `clip_postings` row changes. Never edited directly. The display badge in the editor reflects the recomputed value.
- **Posting** is **track-only**. Sites have no `urlTemplate`; nothing in MasterClipper opens browsers or hits site APIs.
- **Backup scope is metadata only.** The zip contains the SQLite DB + `settings.json`. Referenced video / thumbnail / preview files are not vaulted — only their filenames are stored.
- **Description fields are bifurcated**: `description_raw` is the user's raw transcription; `description_refined` is the LLM-cleaned version. Refine writes to `refined` only; raw is never overwritten. The first time `refined` is set, `[Refined YYYY-MM-DD]` is appended to `notes`. After streaming, `OllamaService.cleanRefineOutput` strips wrapping quotes and normalises paragraph whitespace (single in-paragraph newlines → space; 3+ newlines → 2; multi-space runs → single).
- **Calendar generation** can produce up to one event per (date, persona) — the unique index `idx_cal_unique` enforces this. Two personas active on the same weekday yield two distinct events on that date (intentional). Clips with `goLiveDate` are also surfaced on the calendar at display time without writing to `calendar_events`.
- **`external_clip_id` is *not* the C4S clip ID** in any current install — it's the legacy import sequence number. `c4s_historical.clip_id` (the real C4S ID) cannot be joined against it. Title (post-`FuzzyMatch.normalize`) is the only viable join key between the two tables, used by `HistoricalCategoryBackfillService`.
- **`clip.notes` is the unified context timeline.** Three workflows write tagged markers to the same column rather than maintaining separate audit-log tables — the editor's Notes textarea is the single place to read context across the lifecycle:
  - `[New clip YYYY-MM-DD] <text>` — `ClipWorkflowView.performSave`
  - `[Editing YYYY-MM-DD] <text>` — `EditingWorkflowView.appendNotesAndClose`
  - `[Posted <siteCode> YYYY-MM-DD] <text>` — `PostingClipWindow.postWithNotes` (also writes to `clip_postings.notes`)
  - `[Renamed YYYY-MM-DD: "old" → "new"]` — `DatabaseService.updateClip` (auto, on title change)
  - `[Refined YYYY-MM-DD]` — `ClipEditView.refine` / `FileAuditWorkflow` refine pill (auto, on first refine)
- **`ensureCategory` un-archives on re-use.** The Categories cleanup (`archiveUnusedCategories`) flips `archived = 1` on every category not currently referenced by `clip_categories`. Any subsequent attach (inline picker, import wizard, historical backfill) calls `ensureCategory(named:)`, which un-archives the row in the same write transaction so the cleanup is fully reversible without manual flag-flipping.
- **No `is_historical` flag on clips.** "Historical-import" clips look identical to clips that worked through the pipeline normally (status = `production`, every scoped site marked posted) — `Mark as historical` just calls `markAllScopedSitesPosted`. The category-backfill operational filter (`status = 'production' AND zero clip_categories rows`) is a proxy, not a hard gate.

## Auto-status formula

In `DatabaseService.computeStatus(for:in:)`:

```
if clip.statusOverride is non-nil                                  → statusOverride (v13)
if clip.postingExcluded                                            → "production"  (v10)

let scopedSites = active sites where appliesTo(personaCode)
let postedScoped = clip_postings where status='posted' AND site IN scopedSites
let editingFilled = count of (fcp_project_folder, production_folder, length_seconds) that are non-empty

# No scoped sites at all (Shr / N/A personas without any site assigned) — v10
if scopedSites.isEmpty:
    if editingComplete  → "production"
    elif editingFilled  → "editing"
    else                → "new"

if postedScoped.count == scopedSites.count → "production"
elif postedScoped.count > 0                → "posting"
elif editingComplete                       → "to_post"
elif editingFilled                         → "editing"
else                                       → "new"
```

The recompute fires on every `insertClip`, `updateClip`, and `upsertPosting`. **`PostingService.markPosted` routes through `upsertPosting`** (was a direct `row.save(db)` until v9 — see migration log).

## Auto-save

`ClipEditView` flushes pending edits via `.onDisappear` → `autoSaveIfChanged()`. The SwiftUI view-disappear lifecycle catches:
- Different clip selected (the `.id(clip.id)` modifier on `ClipDetailView` forces a fresh view, which means the old view fires `.onDisappear`)
- Different sidebar section (the section router swaps views)
- Window close
- App quit (best-effort — SwiftUI does fire onDisappear for visible views during normal termination, but a force-kill won't)

`hasUnsavedChanges()` compares `draft != clip` (Clip is `Hashable`, deep-equal) AND `selectedCategoryIds != initialCategoryIds`. Save is no-op when both are unchanged.

## HTML export — why it's static

iOS Files preview / iMessage Quick Look / various in-app webviews all have inconsistent JavaScript execution support. The HTML export pre-renders every clip as a `<article class="card">` block with a `data-search` attribute holding all searchable text lowercased. The optional JS layer just toggles `.hidden` based on filter state — if it doesn't run, every card stays visible and the user falls back to the browser's Find-on-Page.

The data is **never** embedded as an inline JS literal — that route hit too many HTML-parser corner cases (U+2028/U+2029, accidental `</script>` tokens in JS comments, etc).

## Build / verify

```bash
cd ~/Documents/GitHub/PhantomLives/MasterClipper
xcodegen generate
./build-app.sh        # builds + signs MasterClipper.app
./run-tests.sh        # smoke test (regenerates project + builds)
open MasterClipper.app
```

After first launch verify `~/Library/Application Support/MasterClipper/{masterclipper.sqlite,settings.json}` exist and `~/Downloads/MasterClipper backup/MasterClipper-*.zip` is produced.

## Reference apps in the same repo

| Pattern reused | Source |
|---|---|
| GRDB pool + migrator + AppState | `WeightTracker/Sources/WeightTracker/Services/DatabaseService.swift` and `App/AppState.swift` |
| Codable `AppSettings` + JSON SettingsStore | `WeightTracker/Sources/WeightTracker/Models/AppSettings.swift` |
| Theme system (named themes + accent hex) | `WeightTracker/Sources/WeightTracker/Models/Theme.swift` |
| Smart Import (parse → preview → commit) | `WeightTracker/Sources/WeightTracker/Views/Import/ImportWizardView.swift` |
| OOXML XLSX/DOCX + PDF export pipeline | `WeightTracker/Sources/WeightTracker/Services/ExportService.swift` |
| Backup with `/usr/bin/zip` + retention | `PurpleIRC/Sources/PurpleIRC/BackupService.swift` |
| Ollama detection / serve / streaming chat | `SizzleBot/Sources/SizzleBot/Services/{OllamaService,OllamaSetup}.swift` |
