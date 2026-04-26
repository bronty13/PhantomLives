# Music Journal — Developer Handoff Document

**Version:** 1.0.0  
**Date:** 2026-04-26  
**Status:** Feature-complete v1; working, manually tested, no automated tests  

---

## What this app is

Music Journal is a native macOS SwiftUI app (macOS 14+) that:
1. Authenticates with Spotify via OAuth 2.0 PKCE
2. Fetches all of the user's playlists and their tracks from the Spotify Web API
3. Stores everything locally in SQLite (via GRDB.swift)
4. Lets the user annotate playlists and tracks with notes, custom titles, and star ratings
5. Exports data as Markdown, PDF, or JSON

The app is intentionally **local-first**: no cloud backend, no iCloud, no telemetry. The entire database is a single SQLite file.

---

## Repository layout

```
MusicJournal/                        ← Independent git repo (separate from PhantomLives outer repo)
├── Sources/MusicJournal/
│   ├── App/
│   │   ├── MusicJournalApp.swift    ← @main entry point, menu commands
│   │   ├── AppState.swift           ← Observable store; owns sync lifecycle
│   │   ├── Version.swift            ← AppVersion enum; update + Info.plist together
│   │   └── Info.plist               ← Bundle version (1.0.0), URL scheme registration
│   ├── Models/
│   │   ├── Playlist.swift           ← GRDB model; user-owned fields: userNotes, userTitle
│   │   ├── Track.swift              ← GRDB model; user-owned fields: userNotes, userRating
│   │   └── PlaylistTrack.swift      ← Join table model + PlaylistTrackWithTrack helper
│   ├── Services/
│   │   ├── DatabaseService.swift    ← Singleton; SQLite via GRDB; migration history
│   │   ├── SpotifyAPIService.swift  ← REST client; Spotify JSON decode; rate-limit handling
│   │   ├── SpotifyAuthService.swift ← OAuth PKCE; ASWebAuthenticationSession; Keychain
│   │   └── ExportService.swift      ← Markdown/PDF/JSON export; PDF uses CoreText
│   ├── Views/
│   │   ├── ContentView.swift        ← Root view; auth gate; sync banner
│   │   ├── SidebarView.swift        ← Playlist list; search; PlaylistRowView
│   │   ├── PlaylistDetailView.swift ← Header + TrackListView + PlaylistNotesSheet
│   │   ├── TrackDetailView.swift    ← Side panel; StarRatingView; notes editor
│   │   ├── WelcomeView.swift        ← Onboarding / login screen
│   │   ├── SettingsView.swift       ← ⌘, window; Spotify + Data tabs
│   │   ├── ExportSheet.swift        ← Per-playlist export modal
│   │   └── ExportMenuCommands.swift ← File menu export commands
│   └── Resources/
│       └── Assets.xcassets/AppIcon.appiconset/  ← Generated PNGs (16–1024px)
├── project.yml                      ← XcodeGen config; add new sources here
├── make_icon.py                     ← Pillow script that generated the app icon PNGs
├── README.md
├── INSTALL.md
├── USER_MANUAL.md
└── HANDOFF.md                       ← This file
```

---

## Architecture

### Data flow

```
SpotifyAuthService  ─── OAuth PKCE ──►  Spotify Accounts API
                         tokens in Keychain
                              │
                              ▼
SpotifyAPIService  ─── Bearer token ──►  Spotify Web API
                                              │ JSON
                                              ▼
AppState.sync()   ──── upsert ────►  DatabaseService (GRDB SQLite)
                                              │
                                              ▼
                                      @Published playlists[]
                                              │
                                              ▼
                                      SwiftUI Views
```

### Threading model

- All UI and `AppState` work runs on `@MainActor`.
- `SpotifyAuthService` is also `@MainActor` (required for `ASWebAuthenticationPresentationContextProviding`).
- `DatabaseService` is not actor-annotated; GRDB's `DatabaseQueue` serialises writes internally. Called from `@MainActor` context via `try db.*()`.
- `AppState.sync()` is `async` and called with `Task { await appState.sync() }` from SwiftUI button actions.

### State management

`AppState` is the single source of truth, injected as `@EnvironmentObject` at the root. Views do not write to the DB directly — they call `AppState` or `DatabaseService` methods, then call `appState.loadFromDatabase()` to refresh the published state.

---

## Critical implementation details

### Spotify JSON decoding — the "item" vs "track" quirk

The Spotify playlist endpoint `GET /playlists/{id}` returns track items under the key **`"item"` (singular)**, not `"track"`. This is different from how the key reads conceptually and tripped up the app during development.

`SpotifyTrackItem.CodingKeys`:
```swift
enum CodingKeys: String, CodingKey {
    case track = "item"   // ← singular "item", not "track"
    case addedAt, addedBy
}
```

### Spotify JSON decoding — CodingKeys bypasses convertFromSnakeCase

`SpotifyAPIService` sets `.convertFromSnakeCase` on its `JSONDecoder`. However, **any struct that defines its own `CodingKeys` enum must map every key explicitly** — the strategy is bypassed for that struct. This caused `snapshotId` and `tracks` to silently decode as `nil` until explicit mappings were added:

```swift
// SpotifyPlaylistItem
enum CodingKeys: String, CodingKey {
    case tracks = "items"           // count object is under "items" in the list endpoint
    case snapshotId = "snapshot_id" // must map manually; convertFromSnakeCase won't apply
    ...
}
```

### Track count in playlists table

Spotify's playlist-list endpoint returns an estimated track count that is frequently `0` for development-mode apps. After each successful `fetchTracks` call, `AppState.sync()` calls:

```swift
try db.updatePlaylistTrackCount(spotifyId: playlist.spotifyId, count: tracks.count)
```

This overwrites the Spotify estimate with the actual fetched count.

### Sync preserves user data

`DatabaseService.upsertPlaylists` and `upsertTracks` update only the Spotify-owned fields. `userNotes`, `userTitle`, and `userRating` are never touched during sync. This is enforced by the upsert logic which fetches the existing row and copies only specific fields before calling `update(db)`.

### Track order

The entire `playlist_tracks` join table for a playlist is deleted and re-inserted on every sync:

```swift
try db.execute(sql: "DELETE FROM playlist_tracks WHERE playlistSpotifyId = ?", arguments: [playlistId])
```

This ensures position order always matches Spotify and handles removed tracks correctly.

### Sidebar insets

`NavigationSplitView` on macOS applies no default leading inset to `List` rows, causing thumbnails to render flush with the window edge. Fixed with:

```swift
.listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 8))
```

### Rate limiting

Spotify imposes rate limits particularly aggressively on development-mode apps. Two delays are in place:
- **1 second** between each playlist in `AppState.sync()`
- **500 ms** between paginated track-page requests in `SpotifyAPIService.fetchTracks()`

If a 429 occurs, `SpotifyAPIService.get()` throws `SpotifyError.rateLimited(retryAfter:)`. At the playlist level this is caught and the playlist is skipped (`continue`). At the top level it surfaces as a user-visible error with the `Retry-After` value.

---

## Database schema

```sql
-- playlists
id INTEGER PRIMARY KEY AUTOINCREMENT,
spotifyId TEXT NOT NULL UNIQUE,
name TEXT NOT NULL,
description TEXT NOT NULL DEFAULT '',
ownerName TEXT NOT NULL,
ownerSpotifyId TEXT NOT NULL,
imageURL TEXT,
trackCount INTEGER NOT NULL DEFAULT 0,
isPublic BOOLEAN NOT NULL DEFAULT 0,
isCollaborative BOOLEAN NOT NULL DEFAULT 0,
snapshotId TEXT NOT NULL DEFAULT '',
userNotes TEXT NOT NULL DEFAULT '',   -- user-owned; never overwritten by sync
userTitle TEXT NOT NULL DEFAULT '',   -- user-owned; never overwritten by sync
syncedAt DATETIME NOT NULL

-- tracks
id INTEGER PRIMARY KEY AUTOINCREMENT,
spotifyId TEXT NOT NULL UNIQUE,
name TEXT NOT NULL,
artistNames TEXT NOT NULL,            -- comma-separated
albumName TEXT NOT NULL,
albumSpotifyId TEXT NOT NULL,
albumImageURL TEXT,
durationMs INTEGER NOT NULL,
trackNumber INTEGER NOT NULL,
discNumber INTEGER NOT NULL,
isExplicit BOOLEAN NOT NULL DEFAULT 0,
isLocal BOOLEAN NOT NULL DEFAULT 0,
popularity INTEGER,
previewURL TEXT,
spotifyURL TEXT NOT NULL,
userNotes TEXT NOT NULL DEFAULT '',   -- user-owned; never overwritten by sync
userRating INTEGER,                   -- 1–5 or NULL; user-owned
syncedAt DATETIME NOT NULL

-- playlist_tracks  (composite PK)
playlistSpotifyId TEXT NOT NULL REFERENCES playlists(spotifyId) ON DELETE CASCADE,
trackSpotifyId TEXT NOT NULL REFERENCES tracks(spotifyId) ON DELETE CASCADE,
position INTEGER NOT NULL,
addedAt DATETIME,
addedBySpotifyId TEXT,
PRIMARY KEY (playlistSpotifyId, trackSpotifyId)
```

Migrations are managed by GRDB's `DatabaseMigrator`. To add columns: register a new `migrator.registerMigration("v2_...")` block in `DatabaseService.migrate()` — never edit `v1_initial`.

---

## Spotify app configuration

- **Client ID:** `8c6eafa2c28d4493b47b9b95178ec52b` (hardcoded in `SpotifyAuthService.swift:17`)
- **Redirect URI:** `musicjournal://callback` (registered in Info.plist and Spotify Dashboard)
- **Scopes:** `playlist-read-private playlist-read-collaborative user-read-private user-read-email`
- **Mode:** Development (restricted to registered test users; max 25 users; no external playlist track access)

To change the Client ID: update `SpotifyAuthService.swift` line 17 only. The client secret is not used (PKCE flow requires no secret).

---

## Build system

The project uses **XcodeGen** (`project.yml`) rather than a committed `.xcodeproj`. This keeps git diffs clean and makes adding files straightforward.

```bash
# Regenerate after adding/removing source files or changing project.yml
xcodegen generate
```

Dependencies are resolved via Swift Package Manager (SPM) embedded in Xcode:
- **GRDB.swift 6.x** — `https://github.com/groue/GRDB.swift`

The `.xcodeproj` and `xcuserdata` are committed for convenience but should be treated as regeneratable.

---

## Known issues and limitations (v1.0.0)

| Issue | Impact | Notes |
|---|---|---|
| Development-mode Spotify API | Playlists owned by other users return no tracks | Expected; would require Quota Extension to fix |
| No automated tests | Changes require manual testing | No XCTest targets configured in project.yml |
| PDF renderer is basic | Block quotes, bold/italic inline markup, and lists are not styled | CoreText renderer is line-by-line; a more robust approach would use NSAttributedString with a real Markdown parser |
| ExportMenuCommands.exportAll ignores errors silently | User sees nothing if an export fails from the menu | Should surface an error alert |
| No iCloud or device sync | Data lives only on one Mac | SQLite file could be moved to a CloudKit or iCloud Drive URL in a future version |
| make_icon.py requires Pillow | Icon regeneration needs Python + Pillow | `pip install pillow` |
| Rate limiter is per-request only | Burst syncs can still 429 | Could add exponential backoff on retry |

---

## How to extend

### Adding a new field to Playlist or Track

1. Add the Swift property to the model struct.
2. Add a `CodingKeys` entry.
3. Register a new GRDB migration (`"v2_..."`) in `DatabaseService.migrate()` with `db.alter(table:)`.
4. Update `upsertPlaylists` / `upsertTracks` if the field should be synced from Spotify (do not touch user-owned fields).

### Adding a new Spotify endpoint

1. Add response structs in `SpotifyAPIService.swift` under `// MARK: - Spotify API Response Types`.
2. Add a `func fetch*(...)` method using the existing `get<T>()` helper.
3. Call from `AppState.sync()` or a new AppState method.

### Adding a new export format

1. Add a method to `ExportService`.
2. Add an `ExportButton` in `ExportSheet.body`.
3. Add a menu item in `ExportMenuCommands.body` if appropriate.

### Upgrading from development to extended quota

1. Submit a quota extension request in the Spotify Developer Dashboard.
2. No code changes required — the API restrictions are server-side.

---

## Testing checklist (manual, pre-release)

- [ ] Fresh install: Welcome screen appears; Connect Spotify opens browser
- [ ] OAuth callback: browser redirects back; sidebar populates
- [ ] Sync: all playlists appear; track counts update after sync
- [ ] Sidebar search: filters by name and custom title
- [ ] Playlist notes: custom title shows in sidebar and nav title; notes appear in header
- [ ] Track rating: stars persist after reopening the playlist
- [ ] Track notes: green note icon appears in track table after saving
- [ ] Export Markdown: file opens in a text editor and contains expected content
- [ ] Export PDF: file opens in Preview; pagination is correct
- [ ] Export JSON: file is valid JSON with correct structure
- [ ] Import JSON: all playlists/notes/ratings restored correctly
- [ ] Disconnect: Welcome screen appears; reconnect restores data from DB
- [ ] Rate limit handling: app recovers after waiting; no crash
- [ ] Window resize: sidebar and detail columns resize correctly; no clipping

---

## Contact / ownership

Built by **PhantomLives** for personal use.  
Repository: independent git repo within `~/Documents/GitHub/PhantomLives/MusicJournal/`  
(Not part of the outer `bronty13/PhantomLives` monorepo — see `PhantomLives/CLAUDE.md`)
