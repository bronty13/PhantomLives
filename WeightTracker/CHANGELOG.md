# Changelog

All notable changes to WeightTracker are documented here.

## [1.0.0] — 2026-05-02

### Added

- Initial release. Native SwiftUI macOS app for tracking personal weight history.
- **Entry management** — add, edit, and delete weight entries with date, weight (lbs or kg), markdown notes, and optional photo (stored as BLOB in SQLite).
- **Smart Import Wizard** — paste any free-form text containing dates and weights; regex parser handles ISO-8601, MM/DD/YYYY, MM-DD-YYYY, and month-name formats. Preview table with per-row toggle and duplicate detection before committing.
- **Dashboard** — at-a-glance summary cards (current weight, total change, weekly average, goal progress), mini trend chart, recent entries list, and empty-state onboarding.
- **Entry list** — sortable, searchable list with multi-select and bulk delete with confirmation dialog.
- **5 chart styles** via Swift Charts: Line (+ trend/goal/7-day-avg overlays), Bar (weekly or monthly averages with min–max range bars), Area gradient, Scatter (+ regression + forecast extension), Moving Average (7-day and 30-day). All styles support time-range filtering (7D / 30D / 90D / 1Y / All).
- **Statistics** — total change, last-entry delta, 4-week rolling average, best/worst week, linear regression (slope + R²), forecast at 7/14/30/60/90 days, days-to-goal estimate, BMI (current/start/goal with category label).
- **Reports & Export view** — dedicated sidebar section with prominent cards for every export format and print action. Exports default to `~/Downloads/WeightTracker/`.
- **Export menu** — top-level macOS menu bar "Export" with keyboard shortcuts: ⌥⌘E (CSV), ⇧⌘P (PDF Report). Works from any view.
- **Export formats** — CSV (RFC 4180), Markdown (summary + table), XLSX (manual OOXML writer, no external dep), DOCX (manual OOXML writer), PDF report (CoreText via `CGContext`).
- **Print Report** — generates PDF and opens in Preview for full system print controls.
- **Settings** — profile name, weight unit, goal weight, starting weight override, height (BMI), forecast horizon, chart style default, trend/goal line toggles, accent color picker, font family and size, theme.
- **6 themes** — Default (adaptive light/dark), Midnight, Ocean, Forest, Sunset, Rose; each with gradient background, accent color, chart palette, and sidebar background.
- **Automatic backup** — optional on-launch backup of `weighttracker.sqlite` + `settings.json` to `~/Downloads/WeightTracker/` via `/usr/bin/zip`; configurable retention (default 30 days).
- **Database** — GRDB 6-backed SQLite at `~/Library/Application Support/WeightTracker/`; append-only migrations (v1 entries, v2 photos).
- **Photo support** — optional per-entry photos stored as BLOBs; export filenames follow `YYYY-MM-DD-NNN_NN-GUID.ext` convention.
- **App icon** — custom generated icon: blue-to-indigo gradient with white scale symbol and mint green trend line with data points.

### Fixed

- **Dark mode** — default theme now uses adaptive `NSColor.windowBackgroundColor`-based colors instead of hardcoded light values; readable in both light and dark mode.
- **Import weight extraction** — regex pattern `\d{2,3}` matched digits inside year values (e.g. `202` from `2024`). Fixed with lookahead/lookbehind `(?<!\d)…(?!\d)` to exclude digits adjacent to longer numbers.
- **Chart style picker** — picker wrote to `appState.settings.chartStyle` via a computed property chain that never fired `objectWillChange`. Fixed by using local `@State private var chartStyle` in `ChartsView` and syncing on `.onAppear`.
- **PDF report blank output** — `NSAttributedString.draw(at:)` requires `NSGraphicsContext.current` to point to the PDF `CGContext`. The original code never set it; all text drew to nowhere. Fixed by setting `NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)` at the start of each page and computing all y-coordinates in standard PDF coordinates.
