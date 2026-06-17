# PurplePeek — Design notes

The *why* behind PurplePeek's non-obvious decisions. For the module map and "read this before
changing things" architecture snapshot, see `HANDOFF.md`; for usage, `USER_MANUAL.md`.

## The core idea: decisions are data, files are not

PurplePeek is a **triage layer over files you already own**. It never moves or rewrites your
originals during triage — it records *decisions about* them in its own SQLite database, keyed
by absolute **file path**. Everything else follows from that:

- **Re-scanning is safe and idempotent.** The `media_files` table has a UNIQUE constraint on
  `file_path`; a re-scan upserts on that key, so revisiting a folder refreshes on-disk metadata
  (size, modified date, name) while preserving the row's `id` and every decision. This is what
  lets you triage a huge folder across many sessions.
- **Forgetting a scan root never touches disk.** Deleting a root cascades away its decision
  rows only. The user's media is sacrosanct until they explicitly use the Delete tools.

## "Mirror Photos": only offer what Photos can hold

PurplePeek deliberately exposes **exactly** the metadata macOS Photos can store — title,
caption, keywords, favorite, album, hidden — and nothing else. Photos has no star rating, so
PurplePeek has none either. The triage UI is a faithful preview of what the asset will look
like once imported, with no decisions that would be silently dropped at the Photos boundary.

## Three metadata paths (an Apple constraint, not a choice)

PhotoKit can only *write* four asset properties: `creationDate`, `location`, `isFavorite`,
`isHidden`. So title/caption/keywords need other routes, and PurplePeek uses three paths by
necessity:

1. **PhotoKit** — favorite, hidden, album membership (the four it can write).
2. **`exiftool` pre-embedding** — for **photos**, title/caption/keywords are baked into a
   *staged copy* before import, so Photos ingests them natively. The original is untouched; the
   staged copy is deleted after import.
3. **Photos automation (AppleScript)** — for **videos** (and any photo whose embedding was
   skipped), metadata is set on the created asset after import. Run in-process so the macOS
   automation consent is attributed to PurplePeek. This is why video metadata depends on the
   "control Photos" prompt.

`exiftool` and `osxphotos` are **optional**: their absence degrades a specific feature
(photo embedding; keyword import) with clear in-app guidance, never blocks the app.

## Tri-state decisions

`keep` is a SQLite tri-state integer — `NULL` = undecided, `1` = keep, `0` = skip — bridged to
Swift `Bool?` via `MediaFile.keepDecision`. Undecided is a first-class state (it's the default
Preview queue and a Show-filter option), not "false". The `DecisionFilter` enum is the single
lens that turns this tri-state into the grid/Preview filters.

## Missing vs deleted: reconciling disk on re-scan

A re-scan must notice files that **left disk** without conflating them with files the user
**deliberately deleted** in-app:

- **`deleted_at`** — set when the user deletes a file through the Clean Up tools. Terminal.
- **`missing_at`** — set by a re-scan when a previously-discovered, non-deleted file is no
  longer found. Reversible: it clears automatically if the file reappears (the upsert's
  `ON CONFLICT … missing_at = NULL`), because a moved/renamed file often comes back.

Detection uses an **`updated_at` watermark**, not an in-memory path set: every file *seen* in a
scan is stamped with that scan's single timestamp, so any surviving, non-deleted row left with
an older `updated_at` is exactly the set that disappeared. One `UPDATE … WHERE updated_at < ?`
reconciles a 65k-item library with O(1) memory. (See `DatabaseService.markMissingFiles`.)

## Two refresh triggers, one scan path

Both **manual Refresh** (⌘R / toolbar) and **auto-watch** (FSEvents) funnel into the same
`scanFolder` → `persistScan` path, so reconciliation behaves identically however it's
triggered. Auto-watch uses **FSEvents** (not a `DispatchSource` vnode source, which only
watches a single file descriptor) so it sees changes anywhere in the subtree; FSEvents' own
`latency` window coalesces save-storms, making the debounce free. The watcher is only live
while the setting is on *and* a root is selected.

## Space to peek

Quick Look is the macOS-native "show me this bigger" gesture, and Finder already trains users
that **Space = peek**. Browse mode installs a local `NSEvent` key monitor that toggles the
shared `QuickLookCoordinator` for the selected item. A local monitor intercepts the key before
the responder chain, so it must explicitly *not* consume Space when a text field is focused —
otherwise you couldn't type a space into a caption. Both Browse and Preview drive the **same**
single Quick Look coordinator, so there's never more than one peek panel.

## Sidebar organization: DB-backed groups + ordering

Scan roots can be drag-reordered and filed into user-defined sections. Two design choices:

- **It lives in the DB, not `UserDefaults`.** Sections (`sidebar_sections`) and per-root
  placement (`scan_roots.section_id` + `sort_order`) sit next to the roots themselves, so the
  organization is captured by the launch backup and travels with the decision database.
- **The default group is implicit.** A root with `section_id = NULL` belongs to the built-in
  "Folders" group — there's no row to create or accidentally delete, so "everything in one
  group" is the zero-config default. Deleting a custom section just nulls its roots'
  `section_id` (no DB-level FK; handled in `deleteSection`), so folders are never lost with the
  section.
- **A `List`, not the top-level split.** The sidebar renders its rows in a styled `List` so
  `Section` headers come for free. This doesn't conflict with the monorepo's
  no-`NavigationSplitView` rule — that rule is about the top-level split view, which is still a
  manual fixed-width `HStack`. The active root's folder tree is a manual recursive outline (so
  expansion state is ours) rendered inside the root's row.
- **Drag-and-drop via `.onDrag`/`.onDrop`, not `.onMove` (or `.draggable`).** `.onMove` only
  reorders within a single `ForEach`, so it can't move a root across a `Section`. The modern
  `.draggable`/`.dropDestination` pair proved unreliable inside a macOS `List`, so we use the
  older NSItemProvider-based `.onDrag`/`.onDrop` (payload = the folder path as `NSString`).
  Each row is draggable and a drop target ("insert before me, in my group"); section headers
  are drop targets too ("append to this group"). **The row must be a plain tappable view, not a
  `Button`** — a `Button` swallows the press-drag gesture so the drag never starts (selection is
  an `.onTapGesture`). `AppState.moveRoot` resolves a drop by setting the root's `section_id`
  then renumbering the target group's `sort_order`. The right-click "Move to Section" menu
  stays as a non-drag alternative.

## Performance: cache the derived views

For a 65k-item root, recomputing the filtered grid, the Preview queue, and the folder tree on
every SwiftUI `body` evaluation was the main source of lag. So `AppState` keeps **cached
derived collections** (`visibleMediaFiles`, `previewQueue`, `folderTree`, plus cheap toolbar
enable-flags) and recomputes them only when an *input* changes (the file set, folder selection,
or a decision) via a single O(n) `recomputeDerived()` pass. Single-item edits use `patchLocal`
(O(1) via an `id → index` map) to mutate in place rather than refetch — which also avoids
disturbing a focused text field mid-edit.

## State ownership

`AppState` (`@MainActor`, `ObservableObject`) is the **single source of truth**. Views never
touch `DatabaseService` directly; every mutation funnels through an `AppState` method that
persists and then republishes the affected slice. Discovery runs off the main actor (a detached
task) and hands back pure `Sendable` `ScannedFile` values; persistence happens back on the main
actor in 500-row batches so the UI stays responsive during a large scan.

## Conventions inherited from the monorepo

- **Migrations are immutable once shipped.** New schema = a new migration
  (`v4_add_sidebar_sections` is the latest); a frozen-ledger test
  (`testMigrationLedgerIsFrozen`) fails if a shipped one is edited. See the repo `CLAUDE.md`.
- **Auto-backup-on-launch** of the decision database (zip, 14-day retention) + full Settings →
  Backup UI — the PhantomLives standard for apps that own user data.
- **Default output under `~/Downloads/PurplePeek/`**; caches/db under
  `~/Library/Application Support/PurplePeek/`.
- **Manual `HStack` sidebar**, not `NavigationSplitView` (the monorepo's documented macOS
  sidebar rule).
- **Code-generated app icon** (`Scripts/generate-icon.swift` → `iconutil`), no binary icon
  source committed.
