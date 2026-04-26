# Music Journal — User Manual

**Version 1.5.0**

---

## Overview

Music Journal syncs your Spotify playlists to your Mac and lets you journal about each song — capture facts, lyrics, lyric summaries, and your personal commentary on what the music means to you. Everything is stored locally; nothing is sent back to Spotify or any server.

Optional **LLM round-trip** lets you copy a customizable prompt for any track (or batch of tracks) to your clipboard, paste it into Claude / ChatGPT / Gemini, paste the response back, and have the app apply it.

---

## Main window

```
┌──────────────────────────────────────────────────────────────────┐
│  Toolbar: ↻ Sync   Synced 3:45 PM   Edit Notes   Export   LLM ▾ │
├───────────────┬────────────────────────────┬─────────────────────┤
│               │  Playlist Header           │                     │
│  Sidebar      │  (art + metadata + notes)  │  Track Inspector    │
│  ┌─────────┐  │────────────────────────────│  • Album art        │
│  │ search  │  │  Track Table               │  • Year             │
│  └─────────┘  │  (#, title, artist, album, │  • Rating           │
│  • Playlist 1 │   ★, time)                 │  • Lyric Summary    │
│  • Playlist 2 │                            │  • Lyrics           │
│   …           │                            │  • Song Notes       │
│   N playlists │                            │  • Personal Notes   │
└───────────────┴────────────────────────────┴─────────────────────┘
│  [Syncing 12 of 48: My Playlist…  ●●●●●     ]  ← sync banner
└──────────────────────────────────────────────────────────────────┘
```

The sidebar filters to only the playlists *you* own. Selecting a track opens the inspector on the right.

---

## Connecting Spotify

1. Launch the app. The **Welcome** screen appears.
2. Click **Connect Spotify**.
3. Log in in the browser sheet that appears.
4. Click **Agree** to grant read-only playlist access.
5. The app redirects back and loads your playlists.

You only need to connect once. The app stores your tokens securely in the macOS Keychain and refreshes them automatically. Your Spotify user ID is captured here so the sidebar filter can show only playlists you own.

---

## Syncing playlists

Sync is **manual** — it never runs in the background.

**To sync:**
- Click the **↻** button in the toolbar, or
- Press **⌘⇧R**, or
- Go to **Settings → Spotify → Sync Now**.

**What happens during sync:**
1. Your full playlist list is fetched from Spotify; non-user-owned playlists are skipped.
2. For each playlist, tracks are fetched with a 1-second pause between requests.
3. The album release year for each track is auto-filled into the **Year** field, but only when you haven't manually entered one — your edits win.
4. A progress banner at the bottom of the window shows progress.
5. When complete, the "Synced HH:MM" label updates.

**Duration:** Syncing a large library (50+ playlists) can take 1–3 minutes. You can use the app normally while a sync is in progress.

---

## Searching playlists

Click in the **Search playlists** field at the top of the sidebar and type to filter. The search matches both the Spotify playlist name and any custom title you have set.

---

## Annotating a playlist

1. Select a playlist.
2. Click **Edit Notes** in the toolbar.
3. In the sheet that appears:
   - **Custom Title** — replaces the Spotify name in the sidebar and window title. Leave blank to use the Spotify name.
   - **My Notes** — Markdown-formatted free-form text. Shown in the playlist header and included in all exports.
4. Click **Save**.

Your notes are never overwritten by subsequent syncs.

---

## Annotating a track

Click any track row in the table. The track inspector opens on the right with these fields:

| Field | What it's for | Who writes it |
|---|---|---|
| **My Rating** | 1–5 stars | You |
| **Year** | Song release year. Auto-filled by sync from the album's release date | You / sync (sync only fills empty rows) |
| **Lyric Summary** | 2-3 sentence Markdown summary of themes / mood | You / LLM |
| **Lyrics** | Full or partial song lyrics, Markdown | You / LLM (per-track flow only) |
| **Song Notes** | Facts, context, recording history, cultural impact | You / LLM |
| **Personal Notes** | Your private commentary — what the song means to *you* | **You only** — the LLM never touches this |

All long-form text fields use the Markdown editor (see below). Click **Save** (or press ⌘S) to persist; switching tracks while dirty discards your edits.

> Personal Notes are structurally protected — neither the per-track nor the playlist-level LLM apply paths reference the field.

---

## Markdown editor

Every long-form text field is a Markdown editor backed by macOS's native text view. Features:

- **Format toolbar**: **Bold**, *Italic*, `inline code`, ## Heading, • bullet list, 1. numbered list, > quote. Heading/list/quote prefix the line(s) intersecting the selection; bold/italic/code wrap the selection (or place the cursor between markers when nothing is selected).
- **Edit / Preview toggle** — switch to the eye icon to see the rendered Markdown.
- **Native spellcheck** — underlined misspellings, right-click for corrections. Fully local, no internet.
- **Undo/redo** via ⌘Z / ⌘⇧Z.

Auto-correct, smart quotes, dash substitution, and link detection are intentionally **off** so they don't mangle Markdown syntax.

---

## LLM round-trip

The app can hand off track annotation work to an external LLM (Claude / ChatGPT / Gemini / local Ollama) via the system clipboard. Two flows:

### Per-track

In the track inspector, scroll to **LLM Round-Trip**:

1. **Copy Prompt** — copies a prompt with this track's metadata to the clipboard.
2. Paste into your LLM, copy its JSON reply back to the clipboard.
3. **Apply Response** — the app reads the JSON and populates Year, Lyric Summary, Lyrics, and Song Notes. The track becomes dirty; click **Save** to persist.

### Per-playlist (batched)

In the playlist toolbar, the **LLM ▾** menu has two items. The label shows progress: e.g., `LLM (368 unannotated)`.

1. **Copy Prompt — Next 50 of 368** — picks up to *N* tracks where both Lyric Summary and Song Notes are empty, and copies a prompt for them to the clipboard.
2. Paste into your LLM, copy the JSON reply back.
3. **Apply Response** — applies all received track updates and (on the first batch only) the playlist-level notes/title. An alert summarises what was applied / skipped and how many tracks remain.
4. Repeat until the menu reads `LLM (all N annotated)`.

The batch size is configurable in **Settings → LLM Prompt → Playlist** (default 50).

**Customizing prompts**: open **Settings → LLM Prompt** and edit either the Track or Playlist template. Available placeholders are listed at the bottom of each editor. Templates auto-save on every keystroke; **Reset to Default** restores the bundled prompt.

If the LLM produces JSON with unescaped internal quotes (a common error pattern), the app's parser repairs it automatically before applying.

---

## Exporting

### From the playlist toolbar

1. Select a playlist.
2. Click **Export** in the toolbar.
3. Choose a format:
   - **Markdown (.md)** — works in Obsidian, Notion, Bear, etc.
   - **PDF (.pdf)** — formatted document ready to share or print.
   - **JSON Database (.json)** — full export of this playlist's data.

### From the menu bar

Use **File → Export All as Markdown…** (⌘⇧E) or **File → Export All as PDF…** for the entire library.

### What's included in exports

- Playlist name / custom title and Markdown notes
- Description and owner
- All tracks with: artist, album, duration, year, rating, lyric summary, lyrics, **Song Notes**, and **Personal Notes** (when each is non-empty)
- Export timestamp and app version

JSON export includes every field on every record (full database snapshot suitable for backup/restore).

---

## Backing up and restoring

### Backup

1. Go to **Settings → Data** (⌘,).
2. Click **Export Full Database (JSON)**.
3. Save the file somewhere safe.

This JSON file contains *everything* — playlists, tracks, ratings, year, lyrics, lyric summary, song notes, and personal notes.

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
| LLM Prompt | Track / Playlist toggle | Edit either prompt template; auto-saves |
| LLM Prompt | Reset to Default | Restores the bundled prompt for the selected template |
| LLM Prompt | Tracks per batch | Playlist-only — how many unannotated tracks each round picks (default 50) |
| Data | Export Full Database | Saves a JSON snapshot of all data |
| Data | Import Database | Replaces all data from a JSON backup |

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧R | Sync with Spotify |
| ⌘⇧E | Export all playlists as Markdown |
| ⌘S | Save the open track's edits (when the inspector is focused) |
| ⌘B / ⌘I | Bold / Italic in the Markdown editor (when an editor is focused) |
| ⌘Z / ⌘⇧Z | Undo / Redo in the Markdown editor |
| ⌘, | Open Settings |

---

## Disconnecting Spotify

Click the **⊘** button in the toolbar, or go to **Settings → Spotify → Disconnect**. This clears your tokens and user ID. Your local database (notes, ratings, lyrics, personal notes) is **not** deleted — only the Spotify session ends.

---

## Troubleshooting

**Playlists show 0 tracks after sync**  
Sync now skips non-user-owned playlists, so this should be rare. If it happens for a playlist you own, the playlist may briefly contain unavailable tracks; re-sync.

**"Rate limited" error**  
You've hit Spotify's API limit. Wait 1–2 minutes and re-sync.

**"Not authenticated" error / kicked to Welcome screen**  
Your token has expired or been revoked. Reconnect from the Welcome screen.

**Year doesn't show after sync**  
The sync only auto-fills Year when the existing value is empty (so it never overwrites your manual edits). If a track shows no year, the album's release date may be missing from Spotify's response — enter it manually or use the LLM round-trip.

**LLM response won't apply**  
The repair pass handles unescaped internal quotes. If parsing still fails, the response likely has a structural issue (extra commentary, mid-response truncation). Re-prompt and ensure the LLM returns *only* the JSON object.

**Track inspector seems stuck on stale data**  
Selecting a different track and back forces a full reset. The inspector also auto-refreshes when sync writes new field values, but won't clobber edits in progress.

**App won't open / crashes at launch**  
Delete the database and reconnect:
```bash
rm ~/Library/Application\ Support/MusicJournal/journal.sqlite
```
This removes all local data.
