# PurpleLife Changelog

Newest at the top. Follows the PhantomLives convention: every behavior-changing commit lands an entry here, USER_MANUAL.md updates if user-visible, and the version bumps automatically via `build-app.sh` + git commit count.

## Unreleased — Phase 5 starter (0.1.x)

### 2026-05-10 — Real-time CloudKit sync via silent-push subscriptions

Closes the Phase 4 follow-up "real-time CloudKit subscriptions": Mac→Mac sync no longer waits for the foreground poll, it wakes immediately when another device writes. Demotes the poll to a 5 min recovery sweep.

- **`AppDelegate.swift`** — new minimal `NSApplicationDelegate` attached via `@NSApplicationDelegateAdaptor` in `PurpleLifeApp`. Calls `NSApplication.shared.registerForRemoteNotifications()` on launch, parses incoming `application(_:didReceiveRemoteNotification:)` payloads through `CKNotification(fromRemoteNotificationDictionary:)`, and posts a `NotificationCenter` event so the sync service can react without a direct reference (init-ordering safe).
- **`CloudKitSyncService.ensureSubscription()`** — registers a single `CKDatabaseSubscription` (id `PurpleLife.databaseSubscription`) in `bootstrap()` after `ensureZone()`. `notificationInfo.shouldSendContentAvailable = true` keeps it silent (no UI, no user permission needed). A UserDefaults flag prevents the save round-trip on subsequent launches; `serverRejectedRequest` (already exists) is treated as success and remembered. Failures fall back to the recovery poll without blocking bootstrap.
- **`CloudKitSyncService.handleSubscriptionNotification(userInfo:)`** — observes the AppDelegate's NotificationCenter event, validates the payload is a CK push for our subscription id (defensive guard against unrelated APNS noise lighting up the container), and triggers an immediate `pull()`.
- **Recovery poll bumped from 30 s to 5 min** — subscriptions are the primary trigger now; the poll only catches up if a silent push was dropped (offline, sleep, APNS hiccup). 5 min keeps the worst-case lag bounded without burning cycles when push is doing its job.
- **Entitlements** — `PurpleLife.entitlements` adds `com.apple.developer.aps-environment` = `development`. Note: macOS uses the long key form; the iOS short form `aps-environment` is silently stripped by Xcode's `ProcessProductPackaging` step on macOS targets. The `PurpleLife-NoCloud.entitlements` test override stays empty (tests don't need push).
- **Apple-side setup** required once per developer account: enable Push Notifications capability on App ID `com.bronty13.PurpleLife` at developer.apple.com → Identifiers. Signing fails with a misleading "device isn't registered" error until this is done. Documented in `HANDOFF.md` § "Phase 4 sync: subscriptions landed".
- **2 new `CloudKitSubscriptionTests`** covering the deterministic part of the parser (empty / non-CK payloads are rejected). The positive path — a real APNS push triggers `pull()` — needs a real Mac→Mac round-trip to verify and is part of the Phase 4 acceptance gate. **36/36 tests green**.

### 2026-05-10 — Test infrastructure regression resolved

- `./run-tests.sh` runs end-to-end again. Full bundle (now **34 tests**) green in ~19 s; Timeliner's bundle (26 tests) likewise. No code or script change — the host appears to have recovered between sessions (reboot or Xcode/macOS update).
- The iCloud-entitlement-induces-test-hang workaround in `run-tests.sh` (`CODE_SIGN_ENTITLEMENTS=Sources/PurpleLife/App/PurpleLife-NoCloud.entitlements`) stays in place; whether it's still load-bearing wasn't tested. See `HANDOFF.md` § "Test infrastructure regression: no longer reproduces" for the full note.
- README and HANDOFF updated to drop the "blocked by an environmental hang" caveat next to the test command and close item #2 on the follow-up list.

### 2026-05-10 — Theme + visual pass against the design handoff

- **`Theme.swift`** — palette pulled out of `Design/purplelife/project/chrome.jsx` (`PE_LIGHT` / `PE_DARK`). Surfaces (`bg`, `card`, `sidebarOpaque`), text tiers (`text` / `textDim` / `textFaint`), lines (`cardBorder` 6 % black/white, `hairline` 7 %, `rowHover` 4–5 %), accent (`oklch(0.56 0.14 295)` → sRGB ~#8B65C1 light, brighter in dark). All values are sRGB approximations of the prototype's oklch — SwiftUI's `Color` doesn't take oklch directly.
- **Today panels** now sit on `Theme.card` with a `0.5px Theme.cardBorder` stroke — matches the design's white-card-on-cream / dark-card-on-warm-near-black surfaces. Inner result cards switch from `Color.primary.opacity(0.04)` to `Theme.bg.opacity(0.6)` so they read clearly against the panel.
- **Kanban cards** use the same card chrome.
- **Table view** column headers swap `secondary` for `Theme.textFaint` (no opacity tricks), alternating rows use `Theme.rowHover`, dividers are explicit 0.5 px `Theme.hairline` rectangles instead of system dividers.
- **Schema editor** field-type palette tiles switch to `Theme.card` with `Theme.cardBorder`; field-row separators use `Theme.hairline`; bottom palette tray uses `Theme.bg.opacity(0.6)` so it reads as a distinct surface.

### 2026-05-10 — Real attachments + WeightTracker CSV import

- **`AttachmentService`** — content-addressed local file storage. Adds files from any source URL into `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`. Same content referenced by multiple object/field pairs de-duplicates on disk; deleting a row only prunes the file when the last ref is gone. Cascading FK deletes on the `objects` table drop attachment rows automatically.
- **`AttachmentFieldEditor`** — `Detail.swift` `.attachment` editor is no longer a placeholder. Pick file → file copied into the store, the field's value becomes the sha256, real thumbnail renders inline with dimensions / size / Reveal button.
- **Gallery view** loads real images — `imageOrPlaceholder(for:)` reads the type's `galleryAttachmentKey` field, resolves the sha256 to a file URL via `AttachmentService`, displays the actual image. Falls back to the type-tinted gradient stand-in for records without an attachment (or whose attachment hasn't been downloaded yet — placeholder for the future CKAsset sync).
- **`WeightCSVImporter`** — Settings → Import tab. Parses WeightTracker's CSV export (header autodetects lb vs kg, converts kg → pounds), creates Weight records with `source = Imported`. Quoted fields with embedded commas and doubled-quote escapes parse correctly. Per-row errors are listed in the import report without aborting the run.
- **5 new `AttachmentServiceTests`** + **5 new `WeightCSVImporterTests`** covering hash determinism, dedup on add, ref-counted delete, cascade-on-parent-delete, lb/kg conversion, embedded-comma row parsing, error tolerance.
- Phase 5 acceptance gate ("real workflow migrated for ≥2 weeks") is yours to run — the migration infrastructure (CSV import + working attachments + the full Phase 2/3 UI) is in place. The remaining work is daily use.

## Unreleased — Phase 4 starter (0.1.x)

### 2026-05-10 — CloudKit E2E sync (Mac→Mac via private database)

- **`CloudKitSyncService`** — pushes every `ObjectEngine.create / update / delete` to the user's private CloudKit database in a custom zone (`PurpleLifeZone`). Uses `CKRecord.encryptedValues["fieldsJSON"]` for the JSON blob (the same shape the spike PASSed on 2026-05-10) and plaintext slots for `type_id` / `parent_id` / `created_at` / `updated_at` so server-side comparisons can read them. Conflict resolution is **last-write-wins by `updated_at`** — same-field offline edits on two Macs reconcile deterministically when they reconnect.
- **Initial pull + 30s poll** — on launch, the service checks the iCloud account, ensures the custom zone exists, runs `CKFetchRecordZoneChangesOperation` from the saved server change token (resumes incrementally across launches), pushes any local-only rows whose `updated_at` is ahead of the server. Then a 30 s poll keeps things fresh while the app is in the foreground. Real-time silent-push subscriptions (`CKDatabaseSubscription` + `aps-environment`) are queued for follow-up.
- **Graceful degradation** — if the iCloud account is missing, the entitlement is absent, or the container can't be opened, the service transitions to `.disabled` / `.notSignedIn` and the app stays fully usable as a local-only Life OS. No CloudKit failure can stop launch.
- **Sync status footer** in the sidebar — icon + label live-bound to `CloudKitSyncService.status` (idle / syncing / setting up / error / sign in / off), plus a "Sync now" refresh button. Color cues: green for idle, accent for syncing, red for error.
- **Entitlements** — `Sources/PurpleLife/App/PurpleLife.entitlements` now declares `com.apple.developer.icloud-container-identifiers` + `com.apple.developer.icloud-services` for `iCloud.com.bronty13.PurpleLife` (the same container the spike validated). `project.yml` carries `DEVELOPMENT_TEAM=SRKV8T38CD` so signing is non-interactive.
- **Build script switched to Debug + Apple Development signing** — Phase 4 needs the iCloud entitlement embedded in a development provisioning profile. The previous Developer-ID-Application post-sign step has been removed; xcodebuild now signs the `.app` with the dev profile that carries the iCloud capability + container assignment, fetched via `-allowProvisioningUpdates`. Personal-use multi-Mac install is unchanged; only distribution-style signing is affected (we don't distribute outside the team).
- **Lazy `CKContainer` construction** — the framework traps when constructed without the iCloud entitlement, which made `AppState` crash under any signing config that lacked it (e.g. test runs with the no-iCloud override). Container is now allocated inside `bootstrap()` so the local-only path stays viable.
- **Test entitlements override** — `run-tests.sh` passes `CODE_SIGN_ENTITLEMENTS=Sources/PurpleLife/App/PurpleLife-NoCloud.entitlements` so the host under test doesn't carry the iCloud entitlement. Reason: a host with iCloud entitlement plus the XCTest test runner combination causes the runner IPC to never establish (5-minute timeout, then "test runner hung before establishing connection"). The override is test-only; production builds keep the full entitlement. Note: a separate environmental issue is currently making `xcodebuild test` fail on this Mac for both PurpleLife and Timeliner; investigation queued. The Phase 4 functional code (lazy CKContainer, push/pull, LWW, sync footer) builds and runs correctly via `./build-app.sh`.

## Unreleased — Phase 3 starter (0.1.x)

### 2026-05-10 — Saved-query customization UI + Planner Item / Weight types

- **`Planner Item`** + **`Weight`** added to `SchemaSeed.allTypes` so the Phase 3 acceptance gate (planner items + weight + currently-reading book) has real types to query against. Planner Item: title / date / status (Pending/Doing/Done/Cancelled) / project / notes. Weight: date / pounds / body-fat % / source / notes.
- **`SavedQuerySeed.allDefaults`** updated: "Today's planner" (PlannerItem where Status=Pending, sort by date asc) and "Latest weight" (Weight, sort by date desc, limit 1) added at the top of the Today panel list.
- **`SavedQueriesEditor`** sheet — accessed from the Today toolbar's "Edit panels" button. Lists every panel with reorder (drag handles), inline edit / delete buttons, an Add panel CTA, and a "Restore defaults" button that re-adds any built-in defaults the user has previously deleted (without duplicating ones still present).
- **`SavedQueryEditor`** sheet — schema-aware form: type picker (All / each visible type), filter picker (No filter / Field equals / Updated within N days / Field is set), field pickers scoped to the selected type's fields, sort field + descending toggle, limit stepper (1–100), icon picker from a curated SF Symbols set. Edits are live-validated (field-equals filter without a type warns inline; Save disabled when name is empty).
- **`QueryRunnerTests`** — 5 tests covering type filter + limit, field-equals filter, withinDays cutoff against `updated_at`, sort asc / desc by field, cross-type cross-everything. **24/24 tests green**.

### 2026-05-10 — Today screen + saved-queries pattern

- **`SavedQuery`** model — serializable filter spec (typeId / field-equals / withinDays / nonEmpty / sort / limit). Persisted in `AppSettings.todayQueries`. `todayQueriesSeeded` is a one-shot flag so a deleted default never gets re-added.
- **`QueryRunner`** — single-pass executor. Fetches the candidate set (per-type or across all), filters in Swift, sorts by the requested field key (defaults to `updated_at` desc), trims to the limit. Pairs each row with its resolved `ObjectType` so the renderer doesn't have to look it up.
- **`SavedQuerySeed.allDefaults`** — installed on first launch: "Currently reading" (Book where status=Reading), "Recent people", "Recent across everything" (cross-type), "Updated in the last 7 days" (cross-type, 7-day rolling window).
- **`TodayScreen`** — one generic `QueryPanel` repeated over the saved-query list. Phase 3 acceptance gate satisfied: no hard-coded modules in the view, all panels are data-driven. Each panel header shows the count + a "See all" shortcut to the type's detail pane when scoped. Cards render the type icon/badge, primary title, and up to 2 supporting fields via shared `FieldDisplay` renderers. Double-click opens the detail sheet.
- **Sidebar** — new "Today" section above Types; selecting it routes the detail pane to `TodayScreen`. Default selection on first launch is Today (was the first type).
- Customization UI for saved queries (add / edit / delete / reorder) is the next chunk; the underlying model and persistence are in.

## Unreleased — Phase 2 starter (0.1.x)

### 2026-05-10 — Cross-type link picker + linked-title resolution

- **`LinkFieldEditor`** — popover record picker for `.link` fields. Replaces the plain TextField that the starter shipped. Lists every record across every type, grouped by type with sticky type headers, search-as-you-type filter on title or type name, click to select, "Clear link" footer when a value is set. Keeps the field's stored value as the linked record's id (UUID string), so cross-references survive renames.
- **`ObjectEngine.resolveLinkedTitle(recordId:)`** + **`allWithTypes(schema:)`** helpers used by the picker and the read-only renderers.
- **`FieldDisplay.cell`** for `.link` now resolves the id to the linked record's title with a chain icon. Unresolvable values (legacy free-text or deleted records) render in italic with a fallback `link.badge.questionmark` glyph instead of silently looking like real titles.
- Phase 2 acceptance gate now fully met for cross-type links: a Photo Shoot can pick a Camera; a Photo can pick its Shoot. Both render the linked record's title in the table / kanban / detail views.

### 2026-05-10 — Four list views + FTS5 search + Quick Switcher

- **View-kind picker** in the records-screen toolbar — switches between Table / Kanban / Calendar / Gallery for the selected type. Hidden views auto-omit per-type when the type's schema can't support them (no select field → no Kanban tab; no date field → no Calendar tab; no attachment field → no Gallery tab).
- **Kanban** — columns derived from a select field (defaults to `type.kanbanGroupKey` and falls back to the first select field). Each column is colored by the option's `colorHex`. Cards show the primary field + up to 3 supporting fields. Records whose value isn't one of the defined options collect into an "—" column.
- **Calendar** — month grid with prev/next/today controls; records placed by `type.calendarDateKey` (falls back to the first date / dateTime field). Cells show up to 3 record titles + an overflow count, double-click opens detail.
- **Gallery** — adaptive `LazyVGrid` of cards with a placeholder gradient keyed to the type's accent color (the real attachment loader is queued for the AttachmentService work; the layout is fully exercised). Rating badge overlays when the type has a rating field.
- **`FieldDisplay`** — read-only field renderers extracted out of the table body so kanban / calendar / gallery share them, keeps cell rendering uniform across views.
- **FTS5 search** — `objects_fts` virtual table (porter tokenizer) added in `v3_fts5` migration. `SearchService.reindexAll(schema:)` rebuilds from `objects` on every launch. `ObjectEngine.create / update / delete` keep the index incrementally up to date. Title is the primary field's value; body concatenates all text-bearing field values.
- **⌘K Quick Switcher** — floating window with live FTS5 results across every type. Arrow-key navigation, Enter opens the picked record (sets `selectedTypeId` and routes through the main window's detail sheet via `appState.openRecordRequest`), Esc dismisses.
- 4 new `SearchServiceTests` (cross-type query, reindex from disk, empty query → empty, delete-removes-from-index). Total: **19/19 green**.

### 2026-05-10 — Object detail + schema editor + table polish

- **Object detail sheet** — double-click any row opens a `Form`-style editor with one input per `FieldKind`. `text` / `url` / `email` / `link` use `TextField`; `longText` uses `TextEditor`; `number` is a numeric `TextField`; `date` and `dateTime` are native `DatePicker`s; `boolean` is a `Toggle`; `select` is a `Picker`; `multiSelect` is a wrapping chip cluster (custom `Layout`); `rating` is 5 toggleable stars; `attachment` is a placeholder until `AttachmentService` lands. Saves on Done. Right-click a row gives Open / Delete.
- **Schema editor** (⇧⌘S, also in the Window menu) — split view with a types rail (built-in/custom badge, hidden indicator, hide-from-sidebar / delete-custom-type context menu), the selected type's field list (rename / mark required / delete per field), and a field-type palette at the bottom — click any of the 12 kinds to add a field of that kind to the current type. Auto-renames duplicates (`New text 2`, `New text 3`, …).
- **Table view polish** — table body anchored at the top of its ScrollView (was bottom-pinned because of the missing maxHeight on the inner VStack); empty primary fields render "*Untitled*" in italic tertiary text, all other empty cells render "—" in tertiary text; column headers are uppercased + tracked; alternating row backgrounds at 4% secondary; row dividers bumped from 0.4 → 0.6 opacity; row creation now opens the detail sheet for the new record so the user fills in fields immediately rather than landing on a blank row.

### 2026-05-10 — Phase 2 data layer + sidebar + table

- Design handoff (`~/Downloads/PurpleLife-handoff.zip`) unpacked into `Design/`; `Design/MANIFEST.md` maps the 10 prototype screens to the SwiftUI files that will implement them. The JSX/HTML source is gitignored (large), the manifest is committed.
- Attachments storage decided in `HANDOFF.md`: content-addressed files at `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`, `attachments` table for metadata, CloudKit sync via `CKAsset` deferred to Phase 4.
- Models: `FieldDef` (12 field kinds incl. text, select, link, attachment, rating), `ObjectType` (with primary/kanban/calendar/gallery key hints), `Attachment` row.
- `SchemaSeed`: built-in types Person, Book, Camera, Photo Shoot, WoW Character, Photo. Each carries the example fields shown in the design's table/kanban/calendar/gallery screens.
- `SchemaRegistry` service: persists to `schema.json`, loads on launch, merges in newly-added built-ins on upgrade, supports user-add / user-edit / user-delete + hide-built-in.
- DB migration `v2_attachments`: id / parent_object_id / field_key / sha256 / filename / mime_type / size_bytes / created_at, indexed on parent + sha256.
- Views: replaced the Phase 1 placeholder `ContentView` with a `NavigationSplitView`. New `Sidebar` lists visible types with per-type record counts; new `TableViewScreen` renders any type's records as a horizontally-scrollable column grid (`Table` couldn't take dynamic columns at runtime).
- Tests: 6 new `SchemaRegistryTests` (seed, hide-not-delete-built-ins, refuse-delete-built-ins, upsert, field mutations, reload-from-disk). Total: **15/15 green**.

## Unreleased — Phase 1 scaffold (0.1.x)

### 2026-05-10 — CloudKit spike PASS

- Spike ran successfully against `iCloud.com.bronty13.PurpleLife` after attaching the container to the App ID via Configure (the registration-time iCloud capability tick is not enough — a separate save is needed).
- `Spike/CloudKit/build-spike.sh` now passes `-allowProvisioningUpdates`; `Spike/CloudKit/project.yml` carries `DEVELOPMENT_TEAM=SRKV8T38CD` so subsequent builds are non-interactive.
- `Spike/CloudKit/SPIKE.md` § Run log + Decision filled in; `HANDOFF.md` flipped from "scaffolded, run pending" to PASS; `PLAN.md` § Locked decisions encryption row annotated with the confirmation pointer.

### Added

- Refined `PLAN.md` synced from the planning branch, with Phase 0 marked **skipped** and the CloudKit spike moved ahead of Phase 1.
- `HANDOFF.md` decision log; Phase 0 skip + project-name lock recorded as the first two entries.
- Application icon (`PL•` purple gradient squircle) generated by `Scripts/generate-icon.swift`. Matches the Purple\* family treatment.
- CloudKit spike app (`Spike/CloudKit/`) with `encryptedValues` round-trip — compiles clean against Xcode 26.4.1; running it requires the user's iCloud + container provisioning. See `Spike/CloudKit/SPIKE.md`.
- XcodeGen `project.yml` (single app target + test bundle), `build-app.sh`, `run-tests.sh` cloned from Timeliner.
- Source skeleton: `App/`, `Models/`, `Services/`, `Views/`, `Resources/`.
- `DatabaseService` — GRDB pool + `v1_objects` migration (id, type_id, parent_id, fields_json, created_at, updated_at + indexes on type/parent/updated_at).
- `ObjectRecord` model + `ObjectEngine` thin facade for CRUD over `objects`.
- `BackupService` cloned from Timeliner — auto-backup-on-launch with debounce, retention trim, list ordering, archive verify, and destructive restore. Archive prefix: `PurpleLife-`.
- Phase 1 acceptance test (`BackupRoundtripTests.testRoundtrip100Objects`): seeds 100 objects → archives → wipes the support dir → restores → confirms every id survives.
- Four required backup tests (`debounce`, `retention trim` on `PurpleLife-` prefix, `target-directory auto-create`, `list ordering` newest-first) pass.

- **Settings → Backup pane** wired to the existing service primitives:
  toggle for `autoBackupEnabled`, dir picker with resolved path in
  monospaced caption, retention stepper, "Run backup now" button,
  "Recent backups" list with Test / Restore (with mandatory pre-restore
  safety backup) / Reveal in Finder, last-backup timestamp readout, and
  a "Last test result" section showing object count + migrations from
  the verified archive.
- `AppState.reloadAll()` and a `settings` pass-through binding so views
  can write `appState.settings.foo = …` and persist atomically.

### Known gaps for the rest of Phase 1

- ContentView is a placeholder. The real screens land in Phase 2 from `~/Downloads/PurpleLife-handoff.zip`.
