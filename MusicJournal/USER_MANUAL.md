# Music Journal — User Manual

**Version 1.0.0**

---

## Overview

Music Journal is a macOS app that syncs your Spotify playlists to your Mac and lets you annotate them privately — write notes, set custom titles, and rate individual tracks. Everything is stored locally; nothing is sent back to Spotify or any server.

---

## Main window

The window is divided into three areas:

```
┌─────────────────────────────────────────────────────┐
│  Toolbar: ↻ Sync   Synced 3:45 PM   ⊘ Disconnect   │
├───────────────┬────────────────────┬─────────────────┤
│               │  Playlist Header   │                 │
│  Sidebar      │  (art + metadata)  │  Track Detail   │
│  (playlist    │──────────────────  │  (right panel,  │
│   list)       │  Track Table       │   when track    │
│               │  (#, title, artist,│   is selected)  │
│               │   album, ★, time)  │                 │
└───────────────┴────────────────────┴─────────────────┘
│  [Syncing 12 of 48: My Playlist…  ●●●●●             │  ← sync banner
└─────────────────────────────────────────────────────┘
```

---

## Connecting Spotify

1. Launch the app. The **Welcome** screen appears.
2. Click **Connect Spotify**.
3. Log in in the browser sheet that appears.
4. Click **Agree** to grant read-only playlist access.
5. The app redirects back and loads your playlists.

You only need to connect once. The app stores your tokens securely in the macOS Keychain and refreshes them automatically.

---

## Syncing playlists

Sync is **manual** — it never runs in the background.

**To sync:**
- Click the **↻** button in the toolbar, or
- Press **⌘⇧R**, or
- Go to **Settings → Spotify → Sync Now**.

**What happens during sync:**
1. Your full playlist list is fetched from Spotify.
2. For each playlist, tracks are fetched with a 1-second pause between requests.
3. A progress banner at the bottom of the window shows "Syncing X of Y: playlist name".
4. When complete, the "Synced HH:MM" label in the toolbar updates.

**Duration:** Syncing a large library (50+ playlists) can take 1–3 minutes. You can use the app normally while a sync is in progress.

> **Note:** Playlists owned by other users may show 0 tracks. This is a Spotify development-mode restriction and is expected.

---

## Searching playlists

Click in the **Search playlists** field at the top of the sidebar and type to filter. The search matches both the Spotify playlist name and any custom title you have set.

---

## Viewing a playlist

Click a playlist in the sidebar to open it in the detail view. The header shows:

- Cover art
- Description (from Spotify)
- Track count and owner name
- Your notes (if any)

The track table below lists all tracks in their Spotify order. Click any column header to sort.

---

## Annotating a playlist

1. Select a playlist.
2. Click **Edit Notes** in the toolbar.
3. In the sheet that appears:
   - **Custom Title** — replaces the Spotify name in the sidebar and window title. Leave blank to use the Spotify name.
   - **My Notes** — free-form text. Shown in the playlist header and included in all exports.
4. Click **Save**.

Your notes are never overwritten by subsequent syncs.

---

## Rating and annotating a track

1. Select a playlist.
2. Click a track row in the table. A detail panel slides in on the right.
3. In the detail panel:
   - **My Rating** — click a star to set 1–5. Click the current star again to clear.
   - **My Notes** — type anything about this track.
4. Click **Save Notes** (appears when you've made changes).

Track notes and ratings appear in all exports and are preserved across syncs.

---

## Exporting

### From the toolbar

1. Select a playlist.
2. Click **Export** in the toolbar.
3. Choose a format:
   - **Markdown (.md)** — plain text, works in Obsidian, Notion, Bear, etc.
   - **PDF (.pdf)** — formatted document ready to share or print.
   - **JSON Database (.json)** — full export of this playlist's data.

### From the menu bar

Use **File → Export All as Markdown…** (⌘⇧E) or **File → Export All as PDF…** to export your entire library in one file.

### What's included in exports

- Playlist name / custom title
- Description and owner
- Your notes
- All tracks with artist, album, duration, your rating, and your track notes
- Export timestamp and app version

---

## Backing up and restoring

### Backup

1. Go to **Settings → Data** (⌘,).
2. Click **Export Full Database (JSON)**.
3. Save the file somewhere safe (iCloud Drive, external drive, etc.).

This JSON file contains all your playlists, tracks, notes, and ratings.

### Restore

1. Go to **Settings → Data** (⌘,).
2. Click **Import Database from JSON…**.
3. Choose your backup file.

> **Warning:** Import replaces all existing local data. Always export a fresh backup before importing.

---

## Settings

Open with **⌘,** or **MusicJournal → Settings**.

| Tab | Option | Description |
|---|---|---|
| Spotify | Account | Shows connected display name; click Disconnect to log out |
| Spotify | Last Sync | Date and time of the most recent successful sync |
| Spotify | Sync Now | Triggers a full sync |
| Data | Export Full Database | Saves a JSON snapshot of all data |
| Data | Import Database | Replaces all data from a JSON backup |

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧R | Sync with Spotify |
| ⌘⇧E | Export all playlists as Markdown |
| ⌘, | Open Settings |

---

## Disconnecting Spotify

Click the **⊘** (person with X) button in the toolbar, or go to **Settings → Spotify → Disconnect**. This clears your tokens from the Keychain. Your local database (playlists, tracks, notes, ratings) is **not** deleted — only the Spotify session is ended.

To reconnect, click **Connect Spotify** on the Welcome screen or go to **Settings → Spotify → Connect Spotify**.

---

## Troubleshooting

**Playlists show 0 tracks after sync**  
This is expected for playlists owned by other users under Spotify's development-mode restrictions. Playlists you own should always show their full track count after sync.

**"Rate limited" error**  
You've hit Spotify's API limit. Wait 1–2 minutes and try syncing again. If this happens repeatedly, your Spotify Client ID may have been flagged — consider registering a new app in the Spotify Developer Dashboard.

**"Not authenticated" error / kicked to Welcome screen**  
Your Spotify token has expired or been revoked. Reconnect from the Welcome screen.

**Track count in sidebar is wrong**  
The sidebar shows the count written to the database after the last sync. If it's out of date, run a sync (⌘⇧R) to refresh.

**App won't open / crashes at launch**  
Delete the database and try again:
```bash
rm ~/Library/Application\ Support/MusicJournal/journal.sqlite
```
This removes all local data. Reconnect Spotify and sync to repopulate.
