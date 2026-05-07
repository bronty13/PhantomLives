# Timeliner — Architecture Handoff

> First read on every new working session. Keep this file current with
> material architecture changes.

## What it is

A native macOS SwiftUI app for organizing case timelines. SwiftPM-backed
(via XcodeGen → Xcode project), GRDB-backed local SQLite, fully offline,
single-user. Modeled after MasterClipper's structure with PurpleIRC's
settings/theming polish layered on top.

## Architecture at a glance

- **`AppState`** (`@MainActor ObservableObject`) — top-level store. Owns
  every `@Published` slice (`cases`, `events`, `tags`, `people`, plus
  per-event join lookup tables `tagsByEvent` / `peopleByEvent`), the
  current section + selection, and the filter state. Owns the
  `SettingsStore`. All views reach it via `@EnvironmentObject`. Mutations
  always go `View → appState.method() → DatabaseService → reload<Slice>()`.
- **`DatabaseService`** (`@MainActor`, `static let shared`) — sole owner
  of the GRDB `DatabasePool` at
  `~/Library/Application Support/Timeliner/timeliner.sqlite`. All
  schema/migration logic lives here under `migrate()`. Migrations are
  append-only, named `v<N>_<description>`. CRUD methods are thin
  wrappers — the join-table writes (`setTags`, `setPeople`) use a
  delete-all-then-reinsert pattern.
- **`SettingsStore`** (`@MainActor ObservableObject`) — JSON-serialized
  `AppSettings` at `settings.json` next to the sqlite. No encryption.
  Resolved-path computed properties handle the
  `~/Downloads/Timeliner [backup]/` defaults.
- **`BackupService`** (`@MainActor` enum) — the PhantomLives auto-backup
  reference implementation. `runOnLaunchIfDue` is called from
  `AppState.init`; it debounces (5-min minimum gap), zips the support
  directory to the configured backup directory, trims by retention.
  `verifyArchive` and `restoreArchive` give the Settings UI test +
  restore flows.
- **`SearchService`** (pure enum, no state) — cross-case ranked search,
  pure function on inputs the caller passes in. Trivially unit-testable.
- **`ExportService`** (`@MainActor` enum) — single-file standalone HTML
  export. Inline CSS + JS, escapes user content, embeds dates. Pure
  `render(...)` entry point used by snapshot-style tests.

## Data model

```
cases ─┬─< events ─┬─< event_tags >─ tags
       │           └─< event_people >─ people
       └─< people
events ─< attachments  (table only; UI in Phase 2)
```

All tables have ON DELETE CASCADE on their parent FK so deleting a case
cleans up all dependent rows. People are case-scoped (deleting a case
deletes its people); tags are global.

## View tree

`NavigationSplitView`:

- **Sidebar** (`SidebarView`) — top-level sections (Dashboard, All Cases,
  People, Tags, Search) plus a per-case sub-list with status badges and
  event counts. Selection is a single `SidebarSelection` enum binding
  that maps both forms onto `AppState.selectedSection` +
  `selectedCaseId`.
- **Detail router** (`DetailRouterView`) — switches on `selectedSection`.
  For `.allCases` it shows `CaseDetailView` if a case is selected,
  otherwise the `CaseGalleryView` grid.
- **Case detail** has a custom four-tab pill bar: **Timeline**, **Events**
  (table), **People**, **Notes** (markdown render of the case's
  description).
- **Settings** — separate scene, seven `TabView` tabs (General,
  Appearance, Themes, Tags, People Roles, Export, Backup).

## Notable conventions

- **Auto-backup-on-launch** is the *first* thing `AppState.init` does,
  before `reloadAll()`. This is intentional: a backup of the prior
  state is written before we open the GRDB pool against the database in
  this run, so even a hypothetical migration error leaves a clean
  archive of yesterday's state behind.
- **Markdown rendering** is intentionally inline-only (`AttributedString
  (markdown:)` with `interpretedSyntax: .inlineOnlyPreservingWhitespace`).
  The HTML export does the same — bold, italic, code, line breaks. Lists
  and headings are escaped and printed literally. Phase 2 may swap in a
  full block-level renderer.
- **Sandbox dropped** — `Timeliner.entitlements` is intentionally empty.
  We use string paths via `FileManager`, not security-scoped URL
  bookmarks, so the file API needs whatever the logged-in user can see.
- **No external network**. Timeliner has no `com.apple.security.network.*`
  entitlement and makes no `URLSession` calls.
- **Pull-based DB refresh** — no `ValueObservation`. After a write,
  the relevant `reload<Slice>()` call re-reads the affected slice. With
  the data scale we expect (low thousands of events), this is fine.
- **Case status, importance, person role** are stored as `String`
  rawValue in SQLite for forward-compat (a future enum case doesn't
  break old DBs); the typed enum properties on the model structs do the
  conversion.

## Phase 2 hooks already in place

- `attachments` table exists in v1_initial — the UI just hasn't landed.
- `AttachmentStore`, attachment chips on event rows, attachment editing
  in `EventEditorSheet` are the next pieces.
- Horizontal pan/zoom timeline is a sibling view to the existing
  `TimelineView` — wire it in as a fifth tab on `CaseDetailView`.
- Custom theme builder reads/writes `UserTheme` records in
  `AppSettings.userThemes`. Field doesn't exist yet — add when needed.

## Reference projects

- `MasterClipper/` — closest structural sibling. Same XcodeGen build,
  same GRDB pattern, same `BackupService` shape (Timeliner's is an
  adapted copy with the launch-time auto-run as the new default).
- `PurpleIRC/` — settings layout, theme system, encryption infrastructure
  (which Timeliner deliberately does *not* adopt — FileVault is the
  trust boundary).
- `WeightTracker/` — `DatabasePool`-backed GRDB sibling, simpler schema.
- `MusicJournal/` — join-table pattern (`PlaylistTrack`) reused for
  Timeliner's `event_tags` / `event_people`.

## Build / test

```sh
./build-app.sh   # produces ./Timeliner.app
./run-tests.sh   # xcodebuild test against TimelinerTests
```

Both auto-fall-back to `/Applications/Xcode.app` if `xcode-select` points
at Command Line Tools.
