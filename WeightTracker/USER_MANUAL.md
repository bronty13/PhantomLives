# WeightTracker — User Manual

## Getting Started

1. Launch WeightTracker.app
2. Press **⌘N** (or the **+ Add Entry** toolbar button) to log your first weight
3. Enter the date and weight — notes and photo are optional
4. The **Dashboard** shows your progress immediately

---

## Adding Entries

- **⌘N** or the **+** button in the Entries toolbar
- Enter date (defaults to today), weight in your chosen unit, optional notes (Markdown supported), optional photo
- One entry per calendar day — editing an existing day's entry opens Edit mode

## Editing & Deleting Entries

- In **Entries** view, double-click a row to edit
- Select one or more rows → click **Delete (N)** for bulk removal
- Confirmation dialog shown before any delete

## Smart Import

1. Go to **Import** in the sidebar
2. Paste any text that contains dates and weights — examples:
   - `2024-01-15, 185.5`
   - `January 2, 2024  184.0 lbs`
   - Spreadsheet copy-paste (TSV/CSV)
   - Plain sentences: `On 3/5/2024 I weighed 182 pounds`
3. Click **Parse Data** — the wizard shows a preview table with a row per detected entry
4. Deselect any rows you don't want (duplicates are pre-deselected)
5. Click **Import N entries**

Supported date formats: `YYYY-MM-DD`, `MM/DD/YYYY`, `MM-DD-YYYY`, month-name variants (`Jan 15, 2024`, `January 15 2024`).

## Charts

Open **Charts** in the sidebar. Use the time-range picker (7D / 30D / 90D / 1Y / All) and style picker to explore your data.

| Style | Best for |
|-------|----------|
| **Line** | Day-by-day trend with overlays |
| **Bar** | Weekly or monthly averages |
| **Area** | Visual emphasis on total change |
| **Scatter** | Raw data with regression + forecast extension |
| **Moving Avg** | Smoothed 7-day and 30-day trend lines |

On the **Line** chart, toggle overlays: **Trend line**, **7-day avg**, and **Goal line**. The stats strip below the chart shows start, end, change, low, high, and days for the selected range.

## Statistics

Open **Statistics** in the sidebar for four sections:

- **Overview** — starting/current/goal weight, total change, progress bar toward goal
- **Trend Analysis** — weekly rate, regression slope (lbs/day), R² consistency score, best/worst week
- **BMI** — current/starting/goal BMI with category labels (requires height set in Settings)
- **Forecast** — projected weight at 7, 14, 30, 60, 90 days; estimated days to reach goal

## Reports & Exporting Data

Open **Reports** in the sidebar for the full export hub:

### Print Report
Click **Print Report** — the app generates a PDF and opens it in Preview, where you can print to any printer or save as PDF using the system dialog.

### Save PDF
Click **Save PDF** — opens a save dialog defaulting to `~/Downloads/WeightTracker/`. The PDF includes your stats summary and a full entry table.

### Export Formats

| Format | Contents |
|--------|---------|
| CSV | All entries: date, weight, notes |
| Markdown | Summary block + full entry table |
| XLSX | Spreadsheet compatible with Excel and Numbers |
| DOCX | Word-compatible document with summary and table |
| PDF Report | Formatted report with stats summary and entry table |

All formats default to saving in `~/Downloads/WeightTracker/`.

### Export Menu (Menu Bar)

The **Export** menu in the menu bar is available from any view:

| Menu item | Shortcut |
|-----------|---------|
| Export CSV… | ⌥⌘E |
| Export Markdown… | — |
| Export XLSX… | — |
| Export DOCX… | — |
| PDF Report… | ⇧⌘P |
| Open Reports | — |

## Backup

WeightTracker automatically creates a compressed backup (`WeightTracker-YYYY-MM-DD-HHmmss.zip`) on every launch and saves it to `~/Downloads/WeightTracker/`. Backups older than 30 days are deleted automatically.

Configure in **Settings → Backup**: toggle on/off, change retention days, choose a custom folder, or trigger an immediate backup.

---

## Settings Reference

### Profile
- **Display Name** — shown on the Dashboard and in exports
- **Weight Unit** — lbs or kg (applies everywhere; internally stored in lbs)
- **Goal Weight** — target weight; shown as a red dashed line on charts
- **Starting Weight** — override the first-entry weight for progress calculations
- **Height** — in inches; enables BMI calculations
- **Forecast Days** — how far ahead to project the trend line on Scatter chart

### Appearance
- **Theme** — 6 built-in presets: Default, Midnight, Ocean, Forest, Sunset, Rose
- **Accent Color** — overrides the theme accent for buttons, highlights, and the chart primary series
- **Font** — family name (empty = system font) and size slider (10–20 pt)

### Charts
- **Default Style** — which chart style to show when you first open Charts
- **Show Trend Line / Goal Line** — default state for those toggles

### Backup
- **Enable automatic backup** — toggle on/off
- **Retention** — days to keep backups (1–365, default 30)
- **Backup Path** — custom folder (default: `~/Downloads/WeightTracker/`)
- **Backup Now** — trigger an immediate backup

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | Add new weight entry |
| ⌘, | Open Settings |
| ⌥⌘E | Export CSV (from menu bar) |
| ⇧⌘P | Export PDF Report (from menu bar) |

---

## Data Locations

| File | Location |
|------|----------|
| Database | `~/Library/Application Support/WeightTracker/weighttracker.sqlite` |
| Settings | `~/Library/Application Support/WeightTracker/settings.json` |
| Backups & Exports | `~/Downloads/WeightTracker/` (default) |
