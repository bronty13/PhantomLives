# Music Journal

**Version 1.0.0** — macOS 14+ (Sonoma and later)

Music Journal is a native macOS app that syncs your Spotify playlists and tracks to a local SQLite database, then lets you annotate them with personal notes, custom titles, and 1–5 star ratings — all stored privately on your Mac.

---

## Features

- **Spotify sync** — fetches all your playlists and every track via the Spotify Web API (OAuth 2.0 PKCE, no password stored)
- **Local-first storage** — all data lives in `~/Library/Application Support/MusicJournal/journal.sqlite`; no cloud, no subscription
- **Annotations** — write notes and set a custom display title for any playlist; rate and annotate individual tracks
- **Search** — live sidebar search filters playlists by name or custom title
- **Export** — save any playlist (or your entire library) as Markdown, PDF, or a full JSON database backup
- **Import / restore** — re-import a JSON backup to restore all your annotations

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 14.0 Sonoma or later |
| Xcode | 15 or later (16 recommended) |
| Spotify account | Free or Premium |
| Spotify app registered | Developer Dashboard |

---

## Quick start

See [INSTALL.md](INSTALL.md) for full setup instructions.

```
xcodegen generate
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
│   │                         #   SpotifyAuthService, ExportService
│   ├── Views/                # All SwiftUI views
│   └── Resources/            # Assets, app icon
├── project.yml               # XcodeGen project definition
├── make_icon.py              # Icon generation script (Pillow)
├── README.md
├── INSTALL.md
├── USER_MANUAL.md
└── HANDOFF.md
```

---

## Architecture

```
MusicJournalApp
  └── AppState (@StateObject, @MainActor)
        ├── SpotifyAuthService   ← OAuth PKCE, Keychain token storage
        ├── SpotifyAPIService    ← REST calls, JSON decode, rate-limit handling
        └── DatabaseService      ← GRDB SQLite singleton
              tables: playlists · tracks · playlist_tracks
```

---

## Known limitations (v1.0.0)

- **Development mode only** — the Spotify app is in development mode, which restricts playlist track fetching to playlists you own. Playlists added from other users may show 0 tracks.
- **Manual sync** — there is no background sync; you must tap the sync button (⌘⇧R).
- **No iCloud sync** — the database is local to the Mac where the app is installed.
- **Rate limits** — Spotify imposes rate limits on development apps. A 1 s delay between playlists and a 500 ms delay between track-page requests are baked in. If you still hit 429s, wait a few minutes and re-sync.

---

## License

Personal/private use. © 2026.
