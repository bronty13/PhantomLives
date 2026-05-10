# PurpleLife Changelog

Newest at the top. Follows the PhantomLives convention: every behavior-changing commit lands an entry here, USER_MANUAL.md updates if user-visible, and the version bumps automatically via `build-app.sh` + git commit count.

## Unreleased — Phase 2 starter (0.1.x)

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
