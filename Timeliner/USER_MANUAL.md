# Timeliner — User Manual

Timeliner is a native macOS app for organizing case timelines. This manual
covers everything currently in the app: the Phase 1 MVP plus the Phase 2
features (attachments, horizontal/cross-case timelines, PDF export,
anniversary reminders, theme builder, font customization).

## Getting started

1. Run `./build-app.sh` from the project root. Expect ~30 seconds for the
   first build (Swift Package Manager fetches GRDB).
2. Move `Timeliner.app` to `/Applications/` if you want it permanently.
3. Launch. The window opens with an empty Dashboard. Click **New Case**
   in the toolbar (or press ⌘N) to start.

## The window

```
┌─ Sidebar ─────────────┬─ Detail ───────────────────────────────────┐
│ Dashboard             │  (case detail / timeline / events / etc.)  │
│ All Cases             │                                            │
│ Cross-case Timeline   │                                            │
│ People                │                                            │
│ Tags                  │                                            │
│ Search                │                                            │
│ ─ Cases ─             │                                            │
│ • OJ Trial            │                                            │
│ • Boston…             │                                            │
└───────────────────────┴────────────────────────────────────────────┘
```

The sidebar has top-level sections at the top (Dashboard, All Cases,
Cross-case Timeline, People, Tags, Search) and per-case rows below them.
Click any case row to open it in the detail view.

## Cases

A case has a title, free-form markdown description, status (active / cold
/ closed), pinned flag, and timestamps.

- **Create**: ⌘N or toolbar **New Case** → fill the sheet → **Create**.
- **Edit**: open the case, click **Edit Case** in the case header.
- **Delete**: right-click the case in the sidebar (or hover on a case
  card in the gallery) → **Delete…** → confirm.
- **Pin**: right-click → **Pin**. Pinned cases sort to the top of the
  sidebar list and surface on the Dashboard.
- **Attachments on a case**: open the case editor sheet — the
  attachment list at the bottom lets you add files that travel with the
  case (e.g. cover photo, master PDF brief).

## Events

An event has a date (or date range), title, markdown description, source
URL, importance, tags, linked people, and attachments.

- **Create**: open the case, click **New Event** in the case header (⌘E).
- **Edit**: double-click any event row in the timeline, or right-click →
  **Edit Event**. Inside the editor you can attach files (images, PDFs,
  arbitrary documents) which then surface as a paperclip badge in
  timeline rows.
- **Delete**: right-click → **Delete Event**, or open the editor and use
  the **Delete** button (bottom-left).
- **Filter the timeline**: use the filter bar at the top of the timeline.
  Date range, importance level, tag chips, and a free-text query all
  compose. Click **Clear** to reset.

## The four case-detail tabs

Inside a case the detail view exposes four tabs:

| Tab | What it shows |
|---|---|
| **Timeline** | Vertical chronological list grouped by year / month, with all filters and per-row chips |
| **Events** | Flat sortable table — useful for bulk edits, exports, and quick scans |
| **People** | Per-case persons of interest, grouped by role with editable colors |
| **Notes** | Markdown-rendered case description (read-only — edit it from **Edit Case**) |

## Horizontal timeline (Phase 2)

A second horizontal-axis timeline view sits behind the same case data.
Find it via the **Timeline** tab's view-mode toggle (or via the
HorizontalTimelineView surface). Drag to pan, scroll / pinch to zoom,
click an event dot to open the editor, double-click empty space to add
a new event at that exact moment in time.

## Cross-case timeline (Phase 2)

Sidebar → **Cross-case Timeline**. Pick any subset of cases from the
toggle list on the left; their events are merged onto one horizontal
axis and color-coded per case so you can compare parallel investigations
at a glance.

## Tags

Tags are global (shared across cases). Manage them from the **Tags**
sidebar item or **Settings → Tags**.

- **Create**: type a name + pick a color, click **Add**.
- **Recolor**: change the color picker next to the tag — autosaves.
- **Delete**: trash icon. The tag is removed from every event that
  used it (cascade delete).

## People

People are scoped to a case. From the **People** tab inside a case detail
view, click **Add Person**, fill in name + role + notes. You can also
attach files to a person (mugshot, statement PDF, etc.).

- **Default role colors** — configurable in **Settings → People Roles**.
- **Global view** — Sidebar → **People** shows every person across every
  case in a single sortable table.

## Attachments (Phase 2)

Attachments are first-class on cases, events, and people. Files are
stored as BLOBs inside the SQLite database, so they're automatically
included in every backup. Limits & behavior:

- 25 MB per file (clear error if you exceed it).
- Images get a 256-pt JPEG thumbnail rendered automatically and shown
  in the inline list.
- PDFs render inline via the built-in PDFKit preview.
- Other types show a generic file chip with size + filename.
- "Save As…" / "Reveal in Finder" lets you extract the original bytes
  back to disk on demand.

## Search

The **Search** sidebar item opens a global search panel. The query
matches case titles, event titles/descriptions, person names, and tag
names. Hits are ranked title-prefix > title-substring > body-substring,
and clicking a hit jumps you to the relevant case (or the Tags pane for
tag hits).

## Export

Two formats, same data shape:

| Format | Shortcut | Output |
|---|---|---|
| HTML | ⌘⇧H | Single self-contained `.html` (inline CSS + JS, no external deps). Open in any browser, attach to email, drop on a static host. |
| PDF  | ⌘⇧P | Same HTML rendered through `WKWebView` and paginated to US-letter portrait. |

Both land in `~/Downloads/Timeliner/<CaseTitle>-<timestamp>.{html,pdf}`
unless you've overridden the export directory in **Settings → Export**.

## Backup

Backups run automatically at every launch. They zip the entire
`~/Library/Application Support/Timeliner/` directory (database, settings,
attachments) into a timestamped archive at `~/Downloads/Timeliner backup/`
and trim anything older than the retention window (default: 14 days).

Manage everything from **Settings → Backup**:

- **Run backup at every launch** — toggle on or off (default on).
- **Backup directory** — defaults to `~/Downloads/Timeliner backup/`.
  Pick anything you like via **Choose…**.
- **Retention** — number of days to keep archives. `0` means keep
  forever.
- **Run backup now** — runs the backup immediately.
- **Recent backups** — table of every archive in the backup directory.
  - **Test** — extract to a temp directory, validate the SQLite file
    opens, count rows. Non-destructive.
  - **Restore** — replaces the running database with the archive's
    contents. A pre-restore safety backup is written first. Requires
    the backup to have a valid `timeliner.sqlite` inside.
  - **Reveal** — opens Finder at the archive.

The **Backup → Run Backup Now** menu item (⌘⇧B) is a shortcut for the
same thing without opening Settings.

## Anniversary reminders (Phase 2)

**Settings → Notifications**. Off by default — Timeliner only requests
notification permission when you toggle the feature on, and surfaces a
helpful pointer to System Settings if permission was previously denied.

When enabled, Timeliner schedules calendar-anniversary reminders for any
event whose importance is at or above the configured floor (default:
Medium), within a configurable lookahead window (default: 30 days),
firing at a configurable hour (default: 9 AM). The reminder content is
the event title, with a "N years ago today" subtitle and the case title
as the body.

A **"Send test notification"** button fires an immediate banner so you
can verify your alert settings end-to-end.

## Themes & appearance

| Pane | What it controls |
|---|---|
| **Settings → Appearance** | Light / dark mode, override accent color |
| **Settings → Themes** | Pick one of six built-in themes (Default, Midnight, Ocean, Forest, Sunset, Rose), or any user-built custom theme. **New Theme…** opens the theme builder. |
| **Settings → Fonts** | Per-slot font family / size / weight overrides for event title, event body, date column, and sidebar |

The theme builder previews changes live: gradient top + bottom, accent
color, card / sidebar / track colors all editable, with a sample card
rendered above so you see the result before saving.

## Default file locations

| Kind | Location |
|---|---|
| Database | `~/Library/Application Support/Timeliner/timeliner.sqlite` |
| Settings | `~/Library/Application Support/Timeliner/settings.json` |
| Attachments | inside `timeliner.sqlite` as BLOBs |
| Backups | `~/Downloads/Timeliner backup/` |
| HTML / PDF exports | `~/Downloads/Timeliner/` |

All output directories are user-overridable in Settings; overrides
persist in `settings.json`.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New Case | ⌘N |
| New Event | ⌘E |
| Find / Search | ⌘F |
| Export Case as HTML | ⌘⇧H |
| Export Case as PDF | ⌘⇧P |
| Run Backup Now | ⌘⇧B |
| Settings | ⌘, |
| Reset Window State | (Window menu, takes effect next launch) |

## Troubleshooting

- **Window opened off-screen** — Window menu → **Reset Window State…**
  → relaunch. Wipes the persisted frame/sidebar layout.
- **Backup failed** — check **Settings → Backup**; the error message
  surfaces inline. Most common cause: the backup directory was a
  removable volume that's no longer mounted.
- **GRDB build fails on first run** — make sure full Xcode is selected
  via `xcode-select`, not just Command Line Tools. The build script
  auto-falls-back to `/Applications/Xcode.app` if it detects CLT.
- **Anniversary reminders don't fire** — confirm authorization in
  **Settings → Notifications** (status line at the top of the tab). If
  it shows "Denied", click **Open System Settings** and re-enable
  notifications for Timeliner there.
- **Attachment too large** — 25 MB hard cap per file. Save the asset
  externally and link to it via the event's `source URL` field instead.
