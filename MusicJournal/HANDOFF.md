# Music Journal — Developer Handoff Document

**Version:** 1.5.0  
**Date:** 2026-04-26  
**Status:** Working, manually tested, no automated tests.  

---

## What this app is

Music Journal is a native macOS SwiftUI app (macOS 14+) that:
1. Authenticates with Spotify via OAuth 2.0 PKCE.
2. Fetches the user's *own* playlists and their tracks from the Spotify Web API (skipping playlists owned by other users — Spotify dev-mode quotas return zero tracks for them anyway).
3. Stores everything locally in SQLite (via GRDB.swift). Three migrations: `v1_initial`, `v2_track_extra_fields`, `v3_personal_notes`.
4. Lets the user journal each track with: star rating, year, lyric summary, lyrics, **Song Notes** (LLM-writable), and **Personal Notes** (user-only, never touched by the LLM). Playlists also get notes + custom title.
5. Optionally hands off batch annotation work to an external LLM (Claude / ChatGPT / Gemini / local Ollama) via the system clipboard. No per-LLM integration; the user pastes the prompt out and pastes the JSON response back.
6. Exports as Markdown, PDF, or JSON. JSON export round-trips through Import to fully restore state.

The app is intentionally **local-first**: no cloud backend, no iCloud, no telemetry. The entire database is a single SQLite file.

---

## Repository layout

```
MusicJournal/                        ← Lives inside the outer PhantomLives repo
├── Sources/MusicJournal/
│   ├── App/
│   │   ├── MusicJournalApp.swift    ← @main entry point, menu commands
│   │   ├── AppState.swift           ← Observable store; owns sync lifecycle;
│   │   │                              bridges spotifyAuth's @Published userSpotifyId
│   │   ├── Version.swift            ← AppVersion enum; update + Info.plist together
│   │   └── Info.plist               ← Bundle version (1.5.0), URL scheme registration
│   ├── Models/
│   │   ├── Playlist.swift           ← GRDB model; user-owned: userNotes, userTitle.
│   │   │                              Custom == on spotifyId only (preserves sidebar
│   │   │                              selection across syncs that bump syncedAt).
│   │   ├── Track.swift              ← GRDB model; user-owned: userNotes, personalNotes,
│   │   │                              userRating, songYear, lyrics, lyricSummary.
│   │   │                              Synthesised Equatable so SwiftUI sees content
│   │   │                              changes (see "Track equality" below).
│   │   └── PlaylistTrack.swift      ← Join table model + PlaylistTrackWithTrack helper
│   ├── Services/
│   │   ├── DatabaseService.swift    ← Singleton; SQLite via GRDB; migrations v1–v3.
│   │   │                              applyTrackUpdates is the LLM-writable surface;
│   │   │                              it intentionally does NOT touch personalNotes.
│   │   ├── SpotifyAPIService.swift  ← REST client; Spotify JSON decode (incl.
│   │   │                              album.release_date for songYear backfill);
│   │   │                              rate-limit handling.
│   │   ├── SpotifyAuthService.swift ← OAuth PKCE; ASWebAuthenticationSession;
│   │   │                              Keychain tokens; user spotifyId in UserDefaults.
│   │   ├── LLMPromptService.swift   ← Track + Playlist clipboard round-trip;
│   │   │                              JSON repair pass (unescaped internal quotes);
│   │   │                              tracksNeedingAnnotation for batched playlist flow.
│   │   └── ExportService.swift      ← Markdown/PDF/JSON; PDF uses CoreText.
│   ├── Views/
│   │   ├── ContentView.swift        ← Manual HStack(sidebar | divider | detail);
│   │   │                              not NavigationSplitView (see "Sidebar layout").
│   │   ├── SidebarView.swift        ← Inline TextField + List + footer;
│   │   │                              filters to user-owned playlists.
│   │   ├── PlaylistDetailView.swift ← Header + TrackListView; track inspector via
│   │   │                              .inspector(); LLM toolbar Menu (Copy/Apply/state).
│   │   ├── TrackDetailView.swift    ← Inspector panel: art, rating, year, 4 markdown
│   │   │                              editors (Lyric Summary, Lyrics, Song Notes,
│   │   │                              Personal Notes), per-track LLM round-trip.
│   │   ├── MarkdownEditor.swift     ← NSTextView wrapper; format toolbar;
│   │   │                              edit/preview toggle; native spellcheck on.
│   │   ├── WelcomeView.swift        ← Onboarding / login screen
│   │   ├── SettingsView.swift       ← ⌘, window; Spotify + LLM Prompt + Data tabs
│   │   ├── ExportSheet.swift        ← Per-playlist export modal
│   │   └── ExportMenuCommands.swift ← File menu export commands
│   └── Resources/
│       └── Assets.xcassets/AppIcon.appiconset/  ← Generated PNGs (16–1024px)
├── project.yml                      ← XcodeGen config; add new sources here
├── make_icon.py                     ← Pillow script that generated the app icon PNGs
├── README.md
├── INSTALL.md
├── USER_MANUAL.md
├── CHANGELOG.md
└── HANDOFF.md                       ← This file
```

---

## Architecture

### Data flow

```
SpotifyAuthService  ─── OAuth PKCE ──►  Spotify Accounts API
                         tokens in Keychain; user-id in UserDefaults
                              │
                              ▼
SpotifyAPIService  ─── Bearer token ──►  Spotify Web API
                                              │ JSON
                                              ▼
AppState.sync()    ─── filter to ────►  DatabaseService (GRDB SQLite)
                       user-owned          ▲     │
                       playlists           │     │
                                           │     ▼
                                  applyTrackUpdates │ @Published playlists[]
                                  (LLM batch path)  │ + computed userSpotifyId
                                           │     │
                                  ┌────────┘     ▼
                                  │       SwiftUI Views
                                  │             │
                                  │             ▼
                          ┌───────┴────────────────────────────┐
                          │  TrackDetailView / PlaylistDetail  │
                          │     LLM Round-Trip menu/buttons    │
                          │              │                     │
                          │     Render prompt → clipboard      │
                          │     User pastes to LLM, copies     │
                          │     reply to clipboard             │
                          │              │                     │
                          │     LLMPromptService.parseResponse │
                          │     (with JSON repair pass)        │
                          │              │                     │
                          │     applyTrackUpdates (single tx)  │
                          └────────────────────────────────────┘
```

### Track equality (subtle but important)

`Track` uses **synthesised** `Equatable`/`Hashable` (no custom `==`). SwiftUI compares `let track: Track` via `==` to decide whether the track inspector needs to re-render; an earlier custom `==` that compared only `spotifyId` made the v1.2.1 `.onChange(of: trackUserFieldsKey)` trigger unreachable, because the new `Track` value (with a freshly backfilled `songYear`) compared `==` to the stale one. Synthesised equality across all stored properties fixes this.

`Playlist` deliberately keeps a custom `==` that compares only `spotifyId` because the sidebar's `selection: $selectedPlaylist` binding would otherwise lose its highlight on every sync (every sync bumps `syncedAt`, so a fully-synthesised `==` would make the post-sync value `!=` the binding's pre-sync value).

### Sidebar layout — manual HStack, not NavigationSplitView

The root view is a plain `HStack` (sidebar | divider | detail), not `NavigationSplitView`. We tried four iterations of NavigationSplitView fixes (v1.0.2–v1.0.4) before discovering a Tahoe-specific bug where any implicit chrome on the sidebar column (toolbar items, `.searchable`, `.navigationTitle`) caused leading-edge content clipping under various selection / focus paths. Going manual eliminated the entire class of bug. Track-detail rides on `.inspector(...)`, which works at the window level and doesn't perturb sidebar layout.

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

`DatabaseService.upsertPlaylists` and `upsertTracks` update only the Spotify-owned fields. The user-owned fields (`userNotes`, `userTitle` on Playlist; `userNotes`, `personalNotes`, `userRating`, `lyrics`, `lyricSummary` on Track; `songYear` once entered) are never overwritten during sync. This is enforced by the upsert logic, which fetches the existing row and copies only specific Spotify fields onto it before calling `update(db)`.

The one exception: `songYear` is **backfilled** from `album.release_date` if and only if the existing row has `songYear == nil`. So a manually-entered year wins, but a never-touched track gets a year automatically.

### LLM never touches `personalNotes`

The Personal Notes field is structurally protected — not a runtime check. Three independent guarantees:
1. `LLMPromptService.Response` (per-track) and `LLMPromptService.PlaylistResponse.TrackUpdate` have no `personalNotes` key, so even if the LLM emits one, the decoder drops it.
2. `DatabaseService.TrackUpdate` (the bulk-apply struct) has no `personalNotes` field.
3. `applyTrackUpdates(_:)` only writes to the columns named in `TrackUpdate`.

The only paths that ever write `personalNotes` are the Save button in TrackDetailView (manual edit) and `importDatabase` (full JSON restore).

### Track order

The entire `playlist_tracks` join table for a playlist is deleted and re-inserted on every sync:

```swift
try db.execute(sql: "DELETE FROM playlist_tracks WHERE playlistSpotifyId = ?", arguments: [playlistId])
```

This ensures position order always matches Spotify and handles removed tracks correctly.

### Sidebar insets

The sidebar `List` rows still set explicit insets to keep thumbnails off the window edge:

```swift
.listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 8))
```

(This used to also be a NavigationSplitView quirk; with the manual HStack layout it's just standard `List` styling.)

### LLM round-trip mechanics

Two flows, both clipboard-based:

**Per-track** (`TrackDetailView`):
- *Copy Prompt*: renders `LLMPromptService.template` against the current Track (placeholders `{{TRACK_NAME}}`, `{{ARTIST}}`, `{{ALBUM}}`, `{{YEAR}}`, `{{DURATION}}`, `{{SPOTIFY_URL}}`) → `NSPasteboard.general`.
- *Apply Response*: reads pasteboard → `parseResponse` → applies non-empty fields to local `@State`. User confirms with Save.

**Playlist (batched)** (`PlaylistDetailView`):
- *Copy Prompt — Next N of M*: `tracksNeedingAnnotation(_:)` filters tracks where both `lyricSummary` and `userNotes` are empty; takes up to `LLMPromptService.batchSize` (default 50). Renders `playlistTemplate` with the batch and the full playlist's metadata.
- *Apply Response*: parses → `applyTrackUpdates(_:)` runs all field writes in a single transaction. Playlist-level `playlistNotes`/`playlistTitle` are written **only when the existing field is empty**, so batch 1's playlist summary survives batches 2..N.

**JSON repair pass**. Most chat LLMs emit unescaped internal `"` inside string values (e.g. `"notes":""American Pie" is..."`). `LLMPromptService.parseResponse` and `parsePlaylistResponse` first try strict JSON; on failure they call `repairUnescapedQuotes(_:)` which walks the text once, tracks string-vs-structure state, and escapes any in-string `"` whose next non-whitespace character is *not* `,`/`:`/`}`/`]`. Strict + repaired pass handles ~all chat-LLM responses I've seen.

The default templates also instruct the LLM to use *single quotes* (`'American Pie'`) for any internal quotation; this avoids ever hitting the repair path. Custom user templates inherit nothing — if you replace the prompt, copy that line if you want the same protection.

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
userNotes TEXT NOT NULL DEFAULT '',     -- "Song Notes" — user-owned; LLM may write
userRating INTEGER,                     -- 1–5 or NULL; user-owned
songYear INTEGER,                       -- v2; backfilled from album.release_date when nil
lyrics TEXT NOT NULL DEFAULT '',        -- v2; user-owned; LLM may write (per-track flow)
lyricSummary TEXT NOT NULL DEFAULT '',  -- v2; user-owned; LLM may write
personalNotes TEXT NOT NULL DEFAULT '', -- v3; user-only; LLM NEVER writes
syncedAt DATETIME NOT NULL

-- playlist_tracks  (composite PK)
playlistSpotifyId TEXT NOT NULL REFERENCES playlists(spotifyId) ON DELETE CASCADE,
trackSpotifyId TEXT NOT NULL REFERENCES tracks(spotifyId) ON DELETE CASCADE,
position INTEGER NOT NULL,
addedAt DATETIME,
addedBySpotifyId TEXT,
PRIMARY KEY (playlistSpotifyId, trackSpotifyId)
```

Migrations are managed by GRDB's `DatabaseMigrator`. To add columns: register a new `migrator.registerMigration("v4_...")` block in `DatabaseService.migrate()` — never edit existing migration blocks. Migrations applied so far:

| Migration | Adds |
|---|---|
| `v1_initial` | playlists, tracks, playlist_tracks tables |
| `v2_track_extra_fields` | tracks: `songYear`, `lyrics`, `lyricSummary` |
| `v3_personal_notes` | tracks: `personalNotes` |

---

## Spotify app configuration

- **Client ID:** `8c6eafa2c28d4493b47b9b95178ec52b` (hardcoded in `SpotifyAuthService.swift:17`)
- **Redirect URI:** `musicjournal://callback` (registered in Info.plist and Spotify Dashboard)
- **Scopes:** `playlist-read-private playlist-read-collaborative user-read-private user-read-email`
- **Mode:** Development (restricted to registered test users; max 25 users; no external playlist track access)

To change the Client ID: update `SpotifyAuthService.swift` line 17 only. The client secret is not used (PKCE flow requires no secret).

---

## Build system

The project uses **XcodeGen** (`project.yml`). The `.xcodeproj` is committed so contributors can just open it, but the source of truth is `project.yml` — re-run `xcodegen generate` after adding or removing Swift files.

```bash
xcodegen generate
```

Dependencies are resolved via Swift Package Manager (SPM) embedded in Xcode:
- **GRDB.swift 6.x** — `https://github.com/groue/GRDB.swift`

The `.xcodeproj` and `xcuserdata` are committed for convenience but should be treated as regeneratable. (We've gotten bitten once by a stale `.xcodeproj` missing a recently-added file — see CHANGELOG v1.0.1.)

---

## Known issues and limitations (v1.5.0)

| Issue | Impact | Notes |
|---|---|---|
| Development-mode Spotify API | Playlists owned by other users return no tracks | The sidebar filter (v1.0.5) hides them and `AppState.sync()` skips them at write time. Would require Spotify Quota Extension to access them. |
| Apple Music not yet supported | Only Spotify | Future work — would need MusicKit + a paid Apple Developer Program key |
| LLM output is capped | Single round-trip can only annotate ~50 tracks of a large playlist | Mitigated by the unannotated-only batched flow (v1.4.0); user runs Apply repeatedly until done. |
| LLMs sometimes emit malformed JSON | Apply could fail | The repair pass (v1.3.1) handles unescaped internal quotes — the most common error. Other malformations (truncated mid-response, prose around the JSON) still fail. |
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
3. Register a new `migrator.registerMigration("vN_...")` block in `DatabaseService.migrate()` with `db.alter(table:)`. The next free version is documented in the "Database schema" section above. Never edit existing migration blocks.
4. If the field is Spotify-derived: update `upsertPlaylists` / `upsertTracks` to copy it onto the `existing` row. If it's user-owned: do nothing in upsert (it's preserved by being absent from the copy block).
5. If the field should be touched by the LLM: add it to `LLMPromptService.Response` / `PlaylistResponse.TrackUpdate` AND `DatabaseService.TrackUpdate` AND the `applyTrackUpdates(_:)` body. Keeping it absent from any of those three places is sufficient to make it LLM-proof (see "LLM never touches `personalNotes`" above).
6. Add a section to `TrackDetailView` / `PlaylistDetailView`, plumb `@State`, and include it in `resetFields` and `save()`.
7. Update `ExportService.exportPlaylistAsMarkdown(_:)` to include the field in the per-track block.
8. Add a hash term to `trackUserFieldsKey` (or the equivalent for Playlist) so the inspector picks up external writes.

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
- [ ] Sync: all user-owned playlists appear; non-owned ones suppressed; track counts and `songYear` populate
- [ ] Sidebar search: filters by name and custom title
- [ ] Playlist notes: custom title shows in sidebar and nav title; notes appear in header; markdown editor shows preview
- [ ] Track rating: stars persist after reopening the playlist
- [ ] Track Song Notes / Personal Notes / Lyrics / Lyric Summary: persist; green note icon appears in track table
- [ ] Markdown editor: format toolbar wraps selection; preview renders; spellcheck underlines misspellings
- [ ] Per-track LLM: Copy Prompt → paste into LLM → Apply Response populates fields → Save persists
- [ ] Per-playlist LLM: Copy Prompt — Next N picks unannotated tracks; Apply Response shows count alert; advancing decreases unannotated count; eventually shows "all annotated"
- [ ] LLM personalNotes guarantee: even if LLM emits `personalNotes` in response, field is unchanged
- [ ] LLM JSON repair: response with unescaped internal `"` quotes still applies
- [ ] Export Markdown: file opens in a text editor and contains expected content (incl. Song Notes + Personal Notes)
- [ ] Export PDF: file opens in Preview; pagination is correct
- [ ] Export JSON: file is valid JSON with correct structure
- [ ] Import JSON: all playlists/notes/ratings/personalNotes restored correctly
- [ ] Disconnect: Welcome screen appears; reconnect restores data from DB
- [ ] Rate limit handling: app recovers after waiting; no crash
- [ ] Window resize: sidebar and detail columns resize correctly; no clipping under any selection

---

## Contact / ownership

Built by **PhantomLives** for personal use.  
Repository: lives inside the outer `bronty13/PhantomLives` monorepo at `~/Documents/GitHub/PhantomLives/MusicJournal/`. (Earlier docs described this as an independent git repo — that was true briefly before commit `58f3d35`, where MusicJournal was imported into the monorepo. There is no separate `.git` directory inside `MusicJournal/`; all version control happens at the outer repo level.)
