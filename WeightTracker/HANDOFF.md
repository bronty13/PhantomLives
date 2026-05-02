# WeightTracker — Architecture Handoff

## Quick Mental Model

- **`AppState`** (`@MainActor ObservableObject`) — single source of truth. Holds `[WeightEntry]`, `WeightStats?`, and owns `SettingsStore`. All mutations go through AppState methods.
- **`DatabaseService`** (singleton) — GRDB `DatabasePool` wrapper. Migrations registered at init. Never called from views directly — always via AppState.
- **`SettingsStore`** — reads/writes `AppSettings` (Codable struct) to `settings.json` via JSON. Owned by AppState; views mutate via `appState.settings = newValue` which triggers `settingsStore.save()`.
- **Views** receive `@EnvironmentObject var appState: AppState`. No view owns persistent state independently; local `@State` is only used for ephemeral UI state (e.g. `chartStyle` picker to avoid computed-property reactivity gaps).

## Directory Layout

```
Sources/WeightTracker/
├── App/
│   ├── WeightTrackerApp.swift   # @main, WindowGroup + Settings scene + AppMenuCommands
│   ├── AppState.swift           # Central @MainActor store
│   ├── Version.swift            # AppVersion constants (auto-updated by build-app.sh)
│   ├── Info.plist
│   └── WeightTracker.entitlements
├── Models/
│   ├── WeightEntry.swift        # GRDB model + WeightUnit enum + displayWeight(unit:)
│   ├── AppSettings.swift        # Codable settings + SettingsStore + ChartStyle enum
│   └── Theme.swift              # Theme struct, 6 presets, Color(hex:) extension
├── Services/
│   ├── DatabaseService.swift    # DatabasePool, append-only migrations, CRUD
│   ├── ImportService.swift      # Smart text parser → [ParsedEntry]
│   ├── ExportService.swift      # CSV, MD, XLSX, DOCX, PDF; fmt/fmtChange helpers
│   ├── BackupService.swift      # /usr/bin/zip backup + retention trimming
│   └── StatisticsService.swift  # Regression, moving averages, BMI, forecast
└── Views/
    ├── ContentView.swift         # NavigationSplitView root, SidebarItem enum,
    │                             #   export notification handler (exportRequested)
    ├── Sidebar/SidebarView.swift
    ├── Dashboard/{DashboardView, ProgressCardView}.swift
    ├── Entries/{EntryListView, EntryDetailView, AddEntryView}.swift
    ├── Charts/{ChartsView, LineChartView, BarChartView, ScatterChartView}.swift
    │         # ScatterChartView.swift also contains AreaChartView + MovingAverageChartView
    ├── Statistics/StatisticsView.swift
    ├── Reports/ReportsView.swift # Export hub: PDF/print + CSV/MD/XLSX/DOCX cards
    ├── Import/ImportWizardView.swift
    ├── Settings/SettingsView.swift
    └── Shared/{MarkdownEditor, PhotoPickerView}.swift
```

## Data Flow

```
User action → View calls appState.xxx() → AppState mutates DB → appState.loadFromDatabase()
           → @Published entries/stats update → all views re-render
```

Settings changes: `appState.settings = newValue` → `settingsStore.save()` → `appState.recomputeStats()`

Export from menu bar: `AppMenuCommands` posts `Notification.Name.exportRequested` with format string → `ContentView.onReceive` opens `NSSavePanel` and writes file directly.

Export from Reports view: `ReportsView` has its own `NSSavePanel` handlers; defaults `directoryURL` to `~/Downloads/WeightTracker/`.

## Notification Names (WeightTrackerApp.swift)

| Name | Posted by | Observed by |
|------|-----------|-------------|
| `addEntryRequested` | ⌘N menu command, toolbar | ContentView (shows AddEntryView sheet) |
| `navigateToReports` | Export menu "Open Reports" | ContentView (switches sidebar selection) |
| `exportRequested` | Export menu items | ContentView (opens NSSavePanel) |

## Database Schema

```sql
-- v1_initial
CREATE TABLE weight_entries (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    date       TEXT    NOT NULL UNIQUE,   -- "YYYY-MM-DD"
    weightLbs  REAL    NOT NULL,
    notesMd    TEXT    NOT NULL DEFAULT '',
    createdAt  TEXT    NOT NULL,
    updatedAt  TEXT    NOT NULL
);

-- v2_photos
ALTER TABLE weight_entries ADD COLUMN photoBlob     BLOB;
ALTER TABLE weight_entries ADD COLUMN photoFilename TEXT;
ALTER TABLE weight_entries ADD COLUMN photoExt      TEXT;
```

DB location: `~/Library/Application Support/WeightTracker/weighttracker.sqlite`

### Adding a New Migration

In `DatabaseService.swift`, append after existing registrations:
```swift
migrator.registerMigration("v3_my_change") { db in
    try db.alter(table: "weight_entries") { t in
        t.add(column: "myNewField", .text).defaults(to: "")
    }
}
```
Add the field to `WeightEntry` with a default value so existing records decode correctly.

## WeightEntry Identifiable Contract

`WeightEntry.id` is `String { date }` — the ISO-8601 date string is the stable SwiftUI identity. The GRDB row ID is stored as `rowId: Int64?` (mapped to DB column `"id"` via `CodingKeys`). `deleteEntries(ids:)` takes `[Int64]` (rowId values).

## Export Implementation Notes

| Format | Implementation |
|--------|---------------|
| CSV | Plain text, RFC 4180 |
| Markdown | Summary table + entry table |
| XLSX | Manual OOXML: `/usr/bin/zip` of 5 XML files written to a temp dir |
| DOCX | Manual OOXML: `/usr/bin/zip` of 3 XML files written to a temp dir |
| PDF | `CGContext(consumer:mediaBox:)` PDF context; `NSGraphicsContext.current` set per page so `NSAttributedString.draw(at:)` renders into the PDF. Coordinates in standard PDF origin (bottom-left). |

No external dependencies for any export format.

## Backup

`BackupService.performBackup(to:)` spawns `/usr/bin/zip -rqX` on the WeightTracker support directory. Called from `AppState.init()` if `settings.autoBackupEnabled`. Output: `WeightTracker-YYYY-MM-dd-HHmmss.zip`. Retention managed by `trimOldBackups(in:retentionDays:)`.

## Build System

`project.yml` → XcodeGen → `WeightTracker.xcodeproj`

```bash
xcodegen generate   # regenerate after adding/removing source files
./build-app.sh      # full release build + code signing
```

`build-app.sh` derives `SHORT_VERSION` from `git rev-list --count HEAD` and patches `Info.plist` + `Version.swift` at build time.

## App Icon

Generated by `Scripts/generate-icon.swift` (plain Swift script, no build step needed):

```bash
swift Scripts/generate-icon.swift /tmp/WeightTracker.iconset
iconutil -c icns /tmp/WeightTracker.iconset -o /tmp/WeightTracker.icns
cp /tmp/WeightTracker.iconset/*.png Sources/WeightTracker/Resources/Assets.xcassets/AppIcon.appiconset/
xcodegen generate
```

The script draws into `CGBitmapContext` at exact pixel dimensions (bypasses Retina scale inflation from `NSImage.lockFocus`). Design: blue-to-indigo gradient, white `scalemass.fill` SF Symbol (via CGContext compositing to tint), mint green trend line with data-point dots.

## Known Constraints

- **One entry per day** — `date` is `UNIQUE`. Add/edit forms enforce this and surface an error on collision.
- **Weight stored in lbs** — `weightLbs` is the canonical storage field. All display conversions happen at the view layer via `displayWeight(unit:)`.
- **Photos as BLOBs** — large photos inflate the SQLite file. No size limit is enforced.
- **Sandbox** — app is sandboxed. Backup/export default to `~/Downloads/WeightTracker/` (Downloads entitlement). Custom paths require user selection via `NSOpenPanel` (user-selected read-write entitlement).
- **macOS 14+** — NavigationSplitView, Swift Charts, and `ImageRenderer` all require Sonoma.
- **Chart style reactivity** — `ChartsView` uses local `@State private var chartStyle` (not `appState.settings.chartStyle` directly) to avoid the computed-property `objectWillChange` gap. `onAppear` syncs the local state from settings.
