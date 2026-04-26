# Music Journal

**Version 1.5.0** — macOS 14+ (Sonoma and later)

Music Journal is a native macOS app that syncs your Spotify playlists and tracks to a local SQLite database, then lets you journal about each song — facts, lyrics, your personal commentary on what the music means to you. Optional LLM round-trip lets you bulk-fill song facts and lyric summaries via your Claude / ChatGPT / Gemini subscription, all stored privately on your Mac.

---

## Features

- **Spotify sync** — fetches all your playlists and every track via the Spotify Web API (OAuth 2.0 PKCE, no password stored). Auto-fills song release year from the album.
- **Local-first storage** — all data lives in `~/Library/Application Support/MusicJournal/journal.sqlite`; no cloud, no subscription.
- **Sidebar filter** — only shows playlists *you* own (development-mode-friendly).
- **Per-track journaling fields**:
  - **Year** — auto-filled from Spotify, editable.
  - **Star rating** — 1–5.
  - **Lyric Summary** — short Markdown synopsis of themes / mood.
  - **Lyrics** — full or partial song text in Markdown.
  - **Song Notes** — facts, context, cultural impact (LLM may write here).
  - **Personal Notes** — your private commentary on what the song means to you (LLM **never** touches this).
- **Markdown editor** — every long-form text field uses a custom Markdown editor with format toolbar (Bold, Italic, code, headings, bullet/numbered lists, quote), Edit/Preview toggle, and **native macOS spellcheck** (fully local, no internet).
- **LLM round-trip** — copy a customizable prompt for a track or playlist to your clipboard, paste into the LLM of your choice, paste the JSON response back, and the app applies it. Works per-track or in playlist-wide batches that auto-pick the next N unannotated tracks.
- **Search** — live sidebar search filters playlists by name or custom title.
- **Export** — save any playlist (or your entire library) as Markdown, PDF, or a full JSON database backup. All journaling fields included.
- **Import / restore** — re-import a JSON backup to restore all your annotations.

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 14.0 Sonoma or later |
| Xcode | 15 or later (16 recommended) |
| Spotify account | Free or Premium |
| Spotify app registered | Developer Dashboard |
| LLM access | Optional — anything that returns JSON (Claude, ChatGPT, Gemini, local Ollama, …) |

---

## Quick start

See [INSTALL.md](INSTALL.md) for full setup instructions.

```
xcodegen generate            # only if you've added/removed source files
open MusicJournal.xcodeproj
# Build & Run (⌘R)
```

---

## Project layout

```
MusicJournal/
├── Sources/MusicJournal/
│   ├── App/                  # Entry point, AppState, Version, Info.plist
│   ├── Models/               # Playlist, Track, PlaylistTrack (GRDB)
│   ├── Services/             # DatabaseService, SpotifyAPIService,
│   │                         #   SpotifyAuthService, ExportService,
│   │                         #   LLMPromptService
│   ├── Views/                # All SwiftUI views; MarkdownEditor wraps NSTextView
│   └── Resources/            # Assets, app icon
├── project.yml               # XcodeGen project definition
├── make_icon.py              # Icon generation script (Pillow)
├── README.md
├── INSTALL.md
├── USER_MANUAL.md
├── CHANGELOG.md
└── HANDOFF.md
```

---

## Architecture

```
MusicJournalApp
  └── AppState (@StateObject, @MainActor)
        ├── SpotifyAuthService   ← OAuth PKCE, Keychain token storage
        ├── SpotifyAPIService    ← REST calls, JSON decode, rate-limit handling
        ├── DatabaseService      ← GRDB SQLite singleton (migrations v1–v3)
        │     tables: playlists · tracks · playlist_tracks
        ├── ExportService        ← Markdown / PDF / JSON
        └── LLMPromptService     ← per-track + playlist clipboard round-trip
```

The root view is a manual `HStack` (sidebar | divider | detail). Track detail rides on `.inspector(...)` so opening a track never reflows the sidebar. The Markdown editor is an `NSViewRepresentable` wrapper around `NSTextView` so toolbar actions can act on the live selection and the system spellchecker is enabled by default.

---

## Known limitations

- **Spotify development mode** — restricts playlist track fetching to playlists *you own*. The sidebar filter (added in v1.0.5) hides everything else by default. To remove this restriction you would need Extended Quota — not required for personal use.
- **LLM output is capped** — chat LLMs typically truncate output around 4–16k tokens, which fits ~50–80 detailed track entries. The playlist round-trip handles this by picking up to *N* unannotated tracks per round (default 50, configurable in Settings → LLM Prompt → Playlist).
- **Manual sync** — there is no background sync; tap the sync button or press ⌘⇧R.
- **No iCloud sync** — the database is local to one Mac.
- **Rate limits** — Spotify imposes them on dev apps. A 1 s delay between playlists and 500 ms between track-page requests are baked in. If you still hit 429s, wait a few minutes and re-sync.

---

## License

Personal/private use. © 2026.
