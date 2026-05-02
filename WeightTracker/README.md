# WeightTracker

A native macOS app for tracking personal weight history with beautiful charts, statistical analysis, trend forecasting, and full data export. All data stays local — no accounts, no cloud.

## Features

- **Track entries** — date, weight (lbs or kg), markdown notes, optional photo per entry
- **Smart Import** — paste any text containing dates + weights; the wizard extracts them automatically, shows a preview, and skips duplicates
- **5 chart styles** — Line, Bar, Area, Scatter, Moving Average; all support time-range filtering (7D / 30D / 90D / 1Y / All)
- **Statistics** — linear regression, R², weekly averages, BMI, days-to-goal forecast
- **6 themes** — Default (light/dark adaptive), Midnight, Ocean, Forest, Sunset, Rose + accent color + font picker
- **Reports & Export** — dedicated sidebar view; CSV, Markdown, XLSX, DOCX, PDF report; Print via Preview; all formats export to `~/Downloads/WeightTracker/` by default
- **Export menu** — top-level macOS menu bar "Export" with keyboard shortcuts available from any view
- **Automatic backup** — compressed ZIP on launch to `~/Downloads/WeightTracker/`; configurable retention

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16 (to build from source)
- XcodeGen: `brew install xcodegen`

## Quick Start

```bash
cd WeightTracker
xcodegen generate
open WeightTracker.xcodeproj
# Build & Run (⌘R)
```

Or use the pre-built `.app` if provided.

## Build

```bash
./build-app.sh          # produces WeightTracker.app in ./
```

## Output Locations

| Type | Location |
|------|----------|
| Database | `~/Library/Application Support/WeightTracker/weighttracker.sqlite` |
| Settings | `~/Library/Application Support/WeightTracker/settings.json` |
| Backups | `~/Downloads/WeightTracker/WeightTracker-YYYY-MM-DD-HHmmss.zip` |
| Exports | `~/Downloads/WeightTracker/` (default; user can choose a different path) |

## Architecture

See [HANDOFF.md](HANDOFF.md) for a full architecture snapshot.

**Stack:** Swift 5.10 · SwiftUI · Swift Charts · GRDB 6 · macOS 14+  
**Build:** XcodeGen → `WeightTracker.xcodeproj`  
**DB migrations:** append-only (v1 entries, v2 photos)  
**No network required**

## Version

`1.0.0` — see [CHANGELOG.md](CHANGELOG.md)
