# Timeliner — Architecture Handoff

> First read on every new working session. Keep this file current with
> material architecture changes.

## What it is

A native macOS SwiftUI app for organizing case timelines. SwiftPM-backed
(via XcodeGen → Xcode project), GRDB-backed local SQLite, fully offline,
single-user. Modeled after MasterClipper's structure with PurpleIRC's
settings/theming polish layered on top. As of 1.1.x it includes the
Phase 2 features (attachments, horizontal & cross-case timelines, PDF
export, anniversary reminders, theme builder, font slots).

## Architecture at a glance

- **`AppState`** (`@MainActor ObservableObject`) — top-level store. Owns
  every `@Published` slice (`cases`, `events`, `tags`, `people`, the
  per-event join lookup tables `tagsByEvent` / `peopleByEvent`, plus
  `attachmentCounts` for the timeline-row badge), the current section +
  selection, and the filter state. Owns the `SettingsStore`. All views
  reach it via `@EnvironmentObject`. Mutations always go
  `View → appState.method() → DatabaseService → reload<Slice>()`.
- **`DatabaseService`** (`@MainActor`, `static let shared`) — sole owner
  of the GRDB `DatabasePool` at
  `~/Library/Application Support/Timeliner/timeliner.sqlite`. Schema /
  migration logic lives in `static applyMigrations(to:)` so the test
  suite applies the *real* migrator instead of duplicating a fixture.
  Migrations are append-only, named `v<N>_<description>`. CRUD methods
  are thin wrappers — the join-table writes (`setTags`, `setPeople`)
  use a delete-all-then-reinsert pattern.
- **`SettingsStore`** (`@MainActor ObservableObject`) — JSON-serialized
  `AppSettings` at `settings.json` next to the sqlite. No encryption.
  Resolved-path computed properties handle the
  `~/Downloads/Timeliner [backup]/` defaults.
- **`BackupService`** (`@MainActor` enum) — the PhantomLives auto-backup
  reference implementation (other apps point at this file in
  `CLAUDE.md`). `runOnLaunchIfDue` is called from `AppState.init`; it
  debounces (5-min minimum gap), zips the support directory to the
  configured backup directory, trims by retention. `verifyArchive` and
  `restoreArchive` give the Settings UI test + restore flows. Restore
  re-opens the GRDB pool via `DatabaseService.reopenDatabase()`.
- **`SearchService`** (pure enum, no state) — cross-case ranked search,
  pure function on inputs the caller passes in. Trivially unit-testable.
- **`ExportService`** (`@MainActor` enum) — single-file standalone HTML
  export *and* PDF export. Both call the same `render(...)` to build
  the HTML; PDF then loads it into an off-screen `WKWebView` (with a
  `LoadCoordinator` that bridges `didFinish`/`didFail` to async/await)
  and asks WebKit for the data via `WKPDFConfiguration`.
- **`AttachmentService`** (`@MainActor` enum) — file picker + bytes/URL
  → `Attachment` helpers. 25 MB cap; image files auto-thumbnail to a
  256-pt JPEG; `chooseFiles()` and `saveAttachmentToDisk(_:in:)` are
  the UI-side conveniences.
- **`NotificationsService`** (`@MainActor` singleton) — calendar-
  anniversary reminders via `UNUserNotificationCenter`. Identifier
  prefix `timeliner.anniversary.<event-id>` so we wipe-and-replace on
  any data/settings change without disturbing other apps' notifications.
  Authorization is requested only when the user toggles the feature on.
- **`SampleDataService`** (`@MainActor` enum) — installs / restores
  the curated true-crime sample cases shipped as JSON resources under
  `Sources/Timeliner/Resources/SampleData/`. Sample cases use a stable
  `sample-` prefixed `Case.id` so the restore path can detect prior
  installs and replace them without disturbing user-authored cases.
  `installIfFirstRunCompleted` runs from `AppState.init` once per
  install (gated by `AppSettings.sampleDataEverInstalled`); the
  Settings → General **Restore Sample Data…** button is the explicit
  re-add path. The Codable layer accepts multiple shapes seen across
  curated sources (`name`/`title`, `timeline_events`/`events`,
  `people_involved`/`people`, `description`/`notes`, etc.) via
  per-field aliasing so a new sample doesn't usually require a
  conversion step. Currently shipped: Madeline Soto (Florida, plea
  deal, body recovered) and Harmony Montgomery (NH, jury conviction,
  body never recovered, civil + appeal still active).

## Data model

```
cases ─┬─< events ─┬─< event_tags >─ tags
       │           └─< event_people >─ people
       └─< people

attachments  ─→ (parent_type, parent_id) addresses cases / events / people
```

All tables have `ON DELETE CASCADE` on their parent FK so deleting a case
cleans up its events and people (and via the join tables, removes their
tag/person links). People are case-scoped (deleting a case deletes its
people); tags are global.

The `attachments` table is **polymorphic** — a single row addresses any
of the three parent kinds via `(parent_type, parent_id)`. There's no
real FK on that pair (SQLite can't FK to three different tables), so
`AppState.deleteCase` / `deleteEvent` / `deletePerson` manually call
`DatabaseService.deleteAttachments(parentType:parentId:)` before
deleting the parent row.

### Migrations

| Version | Adds |
|---|---|
| `v1_initial` | cases, events, tags, event_tags, people, event_people, plus the original (per-event, on-disk-sha256) attachments table |
| `v2_attachments_blob` | drops + recreates `attachments` as a polymorphic BLOB-backed table. Safe to drop because the v1 attachments UI never shipped — every user's table was empty. |

## View tree

`NavigationSplitView`:

- **Sidebar** (`SidebarView`) — top-level sections (Dashboard, All Cases,
  Cross-case Timeline, People, Tags, Search) plus a per-case sub-list
  with status badges and event counts. Selection is a single
  `SidebarSelection` enum binding that maps both forms onto
  `AppState.selectedSection` + `selectedCaseId`.
- **Detail router** (`DetailRouterView`) — switches on `selectedSection`.
  For `.allCases` it shows `CaseDetailView` if a case is selected,
  otherwise the `CaseGalleryView` grid. `.crossCase` →
  `CrossCaseTimelineView`. `.people` → `GlobalPeopleView` (flat
  cross-case table).
- **Case detail** has a custom four-tab pill bar: **Timeline** (with the
  vertical `TimelineView` and a horizontal-mode toggle that swaps in
  `HorizontalTimelineView`), **Events** (table), **People**, **Notes**
  (markdown render of the case's description).
- **Settings** — separate scene, **nine** `TabView` tabs: General,
  Appearance, Themes, Fonts, Tags, People Roles, Notifications, Export,
  Backup.

## Notable conventions

- **Auto-backup-on-launch** is the *first* thing `AppState.init` does,
  before `reloadAll()`. This is intentional: a backup of the prior
  state is written before we open the GRDB pool against the database in
  this run, so even a hypothetical migration error leaves a clean
  archive of yesterday's state behind.
- **Markdown rendering** is intentionally inline-only (`AttributedString
  (markdown:)` with `interpretedSyntax: .inlineOnlyPreservingWhitespace`).
  The HTML/PDF export does the same — bold, italic, code, line breaks.
  Lists and headings are escaped and printed literally. Phase 3 may
  swap in a full block-level renderer.
- **Sandbox dropped** — `Timeliner.entitlements` is intentionally
  minimal. We use string paths via `FileManager`, not security-scoped
  URL bookmarks, so the file API needs whatever the logged-in user
  can see.
- **No external network**. Timeliner has no
  `com.apple.security.network.*` entitlement and makes no `URLSession`
  calls.
- **Pull-based DB refresh** — no `ValueObservation`. After a write,
  the relevant `reload<Slice>()` call re-reads the affected slice. With
  the data scale we expect (low thousands of events), this is fine.
- **Case status, importance, person role** are stored as `String`
  rawValue in SQLite for forward-compat (a future enum case doesn't
  break old DBs); the typed enum properties on the model structs do the
  conversion.
- **Notifications are scoped by ID prefix.** Every reminder Timeliner
  schedules has identifier `timeliner.anniversary.<event-id>`. Any
  rescheduling pass clears every pending request matching that prefix
  before adding new ones, so we never leave stale reminders behind and
  never touch other apps' notifications.
- **Polymorphic-attachment cascade is manual.** Whenever you wipe a
  case / event / person, you must call
  `DatabaseService.deleteAttachments(parentType:parentId:)` for the
  parent (and for cases, also iterate children) before deleting the
  parent row. See `AppState.deleteCase` / `deleteEvent` /
  `deletePerson` for the pattern.
- **Sample data is one-shot.** First-run install fires only when the
  cases table is empty *and* `AppSettings.sampleDataEverInstalled` is
  false. After running it always sets the flag, so deleting the sample
  doesn't cause a silent re-install on next launch — the user pulls
  it back via **Settings → General → Restore Sample Data…** instead.

## Phase 3 hooks

- iOS companion app via CloudKit sync — schema is forward-compat
  (string-rawValue enums, append-only migrations) but no sync code yet.
- Multi-case index export — `ExportService.render(...)` is pure on its
  inputs, so a new entry point that loops over multiple cases is
  straightforward.
- Case templates — would seed `Case.newDraft` from a JSON template; no
  template store exists yet.
- Full block-level markdown rendering — currently both inline-only.

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
