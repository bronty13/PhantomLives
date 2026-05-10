# PurpleLife — Design Manifest

The visual design ships as `~/Downloads/PurpleLife-handoff.zip`, unpacked into `purplelife/` here. The medium is React/JSX prototypes; recreate the visuals pixel-perfectly in SwiftUI — don't mirror the JSX component structure.

The HTML title is "Personal ERP — Life OS" and the bundle directory is named `purplelife/`. The "Personal ERP" string is a historical artifact from when the design was made (see `HANDOFF.md` for the rename); ignore it everywhere.

## Screen → SwiftUI mapping

Artboard size is 1280 × 800 in the prototype. Each row maps a JSX `Screen*` component to its eventual `Sources/PurpleLife/Views/*.swift` file.

| # | Screen | Mode  | JSX component (`screens-{light,dark}.jsx`) | SwiftUI file (`Views/`)        | Notes |
|---|--------|-------|---------------------------------------------|--------------------------------|-------|
| 1 | Today / Planner            | light | `ScreenToday`     | `Today.swift`               | Central home — timeline + linked-from-today rail. Phase 3 |
| 2 | Sidebar                    | light | `ScreenSidebar`   | `Sidebar.swift`             | Single nav primitive — types, saved views, search, sync. Phase 2 |
| 3 | Type · Table view          | light | `ScreenTable`     | `TableView.swift`           | Generic spreadsheet over any type. Example: Contacts. Phase 2 |
| 4 | Type · Kanban view         | light | `ScreenKanban`    | `KanbanView.swift`          | Group by select field. Example: WoW Characters by status. Phase 2 |
| 5 | Type · Calendar view       | light | `ScreenCalendar`  | `CalendarView.swift`        | Any type with a date field. Example: Photo Shoots. Phase 2 |
| 6 | Type · Gallery view        | dark  | `ScreenGallery`   | `GalleryView.swift`         | Media-heavy types. Example: Photos · Keepers ★★★★+. Phase 2 |
| 7 | Object detail              | dark  | `ScreenDetail`    | `Detail.swift`              | Fields + linked objects + attachments + notes + history. Phase 2 |
| 8 | Schema builder             | dark  | `ScreenSchema`    | `SchemaEditor.swift`        | **Most distinctive screen.** Drag a field type onto a type to extend it. Phase 2 |
| 9 | Quick switcher · ⌘K        | dark  | `ScreenCmdK`      | `QuickSwitcher.swift`       | Global search across every type with create-on-the-fly. Phase 2 |
| 10 | Settings · Sync & Backup  | dark  | `ScreenSettings`  | `Settings/SettingsView.swift` (extend) | Sync, encryption, backup, type management. Phase 2 expansion of Phase 1's Backup tab |

## Implementation rule

Per `PLAN.md` § Design source of truth, every Phase 2 SwiftUI view that maps to a row above must be implemented to match the JSX prototype's visual output. Any deliberate deviation — a layout change, a typography swap, a color override — gets a `### YYYY-MM-DD — <Screen> — <one-line reason>` entry in `HANDOFF.md` § Design deviations.

The Phase 2 acceptance gate explicitly includes a visual review against this manifest, so don't postpone deviation entries.
