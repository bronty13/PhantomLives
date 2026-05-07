# Timeliner — User Manual

Timeliner is a native macOS app for organizing case timelines. This manual
walks through the features available in the Phase 1 MVP build.

## Getting started

1. Run `./build-app.sh` from the project root. Expect ~30 seconds for the
   first build (Swift Package Manager fetches GRDB).
2. Move `Timeliner.app` to `/Applications/` if you want it permanently.
3. Launch. The window opens with an empty Dashboard. Click **New Case**
   in the toolbar (or press ⌘N) to start.

## The window

```
┌─ Sidebar ──────┬─ Detail ───────────────────────────────────┐
│ Dashboard      │  (case detail / timeline / events / etc.)  │
│ All Cases      │                                            │
│ People         │                                            │
│ Tags           │                                            │
│ Search         │                                            │
│ ─ Cases ─      │                                            │
│ • OJ Trial     │                                            │
│ • Boston…      │                                            │
└────────────────┴────────────────────────────────────────────┘
```

The sidebar has top-level sections at the top (Dashboard, All Cases,
People, Tags, Search) and per-case rows below them. Click any case row to
open it in the detail view.

## Cases

A case has a title, free-form markdown description, status (active / cold
/ closed), pinned flag, and timestamps.

- **Create**: ⌘N or toolbar **New Case** → fill the sheet → **Create**.
- **Edit**: open the case, click **Edit Case** in the case header.
- **Delete**: right-click the case in the sidebar (or hover on a case
  card in the gallery) → **Delete…** → confirm.
- **Pin**: right-click → **Pin**. Pinned cases sort to the top of the
  sidebar list and surface on the Dashboard.

## Events

An event has a date (or date range), title, markdown description, source
URL, importance, tags, and linked people.

- **Create**: open the case, click **New Event** in the case header (⌘E).
- **Edit**: double-click any event row in the timeline, or right-click →
  **Edit Event**.
- **Delete**: right-click → **Delete Event**, or open the editor and use
  the **Delete** button (bottom-left).
- **Filter the timeline**: use the filter bar at the top of the timeline.
  Date range, importance level, tag chips, and a free-text query all
  compose. Click **Clear** to reset.

## Tags

Tags are global (shared across cases). Manage them from the **Tags**
sidebar item or **Settings → Tags**.

- **Create**: type a name + pick a color, click **Add**.
- **Recolor**: change the color picker next to the tag — autosaves.
- **Delete**: trash icon. The tag is removed from every event that
  used it (cascade delete).

## People

People are scoped to a case. From the **People** tab inside a case detail
view, click **Add Person**, fill in name + role + notes.

The default role colors are configurable in **Settings → People Roles**.

## Search

The **Search** sidebar item opens a global search panel. The query
matches case titles, event titles/descriptions, person names, and tag
names. Hits are ranked title-prefix > title-substring > body-substring,
and clicking a hit jumps you to the relevant case (or the Tags pane for
tag hits).

## Export

**Export → Export Case as HTML…** (⌘⇧H) renders the *currently selected*
case as a self-contained `.html` file in `~/Downloads/Timeliner/`. The
file embeds inline CSS and JS — no external dependencies, no fonts to
download. Open it in any browser, attach it to an email, or drop it on a
static host.

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

## Themes & appearance

**Settings → Appearance** controls light/dark mode and the accent color.
**Settings → Themes** picks one of six built-in themes — Default,
Midnight, Ocean, Forest, Sunset, Rose. The custom-theme builder is a
Phase 2 feature.

## Default file locations

| Kind | Location |
|---|---|
| Database | `~/Library/Application Support/Timeliner/timeliner.sqlite` |
| Settings | `~/Library/Application Support/Timeliner/settings.json` |
| Backups | `~/Downloads/Timeliner backup/` |
| HTML exports | `~/Downloads/Timeliner/` |

All output directories are user-overridable in Settings; overrides
persist in `settings.json`.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New Case | ⌘N |
| New Event | ⌘E |
| Find / Search | ⌘F |
| Export Case as HTML | ⌘⇧H |
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
