# Changelog

All notable changes to MusicJournal are recorded here.

## [1.5.0] — 2026-04-26

### Added
- **`personalNotes` field on `Track`** — the user's private commentary
  about what a song means to them, surfaced in the inspector as the new
  *Personal Notes* section. Migration `v3_personal_notes` adds the column
  with an empty default; existing tracks get an empty Personal Notes
  field automatically.
- **Personal Notes is never touched by the LLM.** Neither the per-track
  nor the playlist-level apply paths reference it: `Track`'s LLM-facing
  decoders (`LLMPromptService.Response`, `PlaylistResponse.TrackUpdate`)
  don't include it, and `DatabaseService.applyTrackUpdates(_:)` never
  writes to it. Only the manual Save button (and JSON import) ever
  populate it.
- **Markdown / PDF / JSON exports include both fields.** Each track's
  export block now emits a `**Song Notes**` section followed by a
  `**Personal Notes**` section when each is non-empty. JSON export
  picks up `personalNotes` automatically through `Track`'s Codable
  conformance.

### Changed
- **"My Notes" is now "Song Notes"** in the inspector — clearer that
  this is the field the LLM may write to (facts/context), in contrast to
  Personal Notes which is yours alone. The underlying field is still
  named `userNotes` in code and the DB column for migration safety.
- Section labels in the inspector now have a small caption explaining
  who writes to each field (LLM-writable vs. user-only).

## [1.4.0] — 2026-04-26

### Added
- **Batched playlist LLM round-trip — picks the next N *unannotated*
  tracks each time.** Chat LLMs cap output at 4–16k tokens, so a single
  prompt over a 400-track playlist comes back with only ~50 entries
  filled. Rather than tracking an indexed cursor, the app now selects up
  to `batchSize` tracks where both `lyricSummary` and `userNotes` are
  empty. Each round-trip naturally picks up where the last one left off,
  and you can interleave manual edits with LLM applies without losing
  state.
- **Visible apply report.** The capsule banner is gone; both Copy Prompt
  and Apply Response now surface their result via an alert listing what
  was applied, what was skipped, and how many tracks still need
  annotation. Won't be missed.
- **`LLM` toolbar menu shows live state**: `LLM (368 unannotated)` →
  `LLM (all 422 annotated)` once you finish. The Copy Prompt item label
  shows the next batch size: `Copy Prompt — Next 50 of 368`.
- **Batch Size setting** (Settings → LLM Prompt → Playlist tab). Default
  50; range 5–500. Bigger if your LLM has high output capacity, smaller
  if it truncates.

### Changed
- **First-batch playlist notes/title are protected.** Subsequent batches
  often re-summarise the playlist as a whole. The app now writes
  `playlistNotes` / `playlistTitle` from a response *only when* the
  existing playlist field is empty — so batch 1's summary survives
  batches 2..N. Reset the playlist note manually if you want to overwrite.
- **Playlist prompt template updated** to mention this is a partial
  batch from a larger playlist, with `{{TOTAL_COUNT}}` and `{{BATCH_COUNT}}`
  placeholders. The old `{{TRACK_COUNT}}` is still supported for
  backwards-compat with custom templates.

## [1.3.1] — 2026-04-26

### Fixed
- **LLM responses with unescaped `"` inside string values now parse.**
  Most chat LLMs respond with patterns like
  `"notes":""American Pie" is one of the longest songs..."` — the inner
  song-title quotes aren't escaped, so strict JSON parsing rejects the
  whole response. `LLMPromptService.repairUnescapedQuotes(_:)` now walks
  the text once, tracks string-vs-structure state, and escapes any
  in-string `"` whose next non-whitespace character isn't a structural
  token (`,`, `:`, `}`, `]`). Both `parseResponse` and
  `parsePlaylistResponse` try strict parsing first, then this repaired
  pass on failure. The previously-rejected response in your clipboard
  applies cleanly after this update.

### Changed
- Both default prompt templates now end with a CRITICAL line instructing
  the LLM to use single quotes — like `'American Pie'` — instead of
  double quotes for any internal quotation, so future responses don't
  need the repair pass at all. (User-edited templates aren't touched —
  add the line yourself in Settings → LLM Prompt if you want it.)

## [1.3.0] — 2026-04-26

### Fixed
- **Year still didn't populate after sync** despite the v1.2.1 refresh
  trigger. Root cause: `Track`'s custom `Equatable` only compared
  `spotifyId`. SwiftUI uses `==` to decide whether a view's input changed,
  so a sync that updated only `songYear` produced a "new" `Track` value
  that compared equal to the old one — `TrackDetailView` was skipped
  during re-render and the v1.2.1 `.onChange(of: trackUserFieldsKey)` was
  never re-evaluated.
  Fix: dropped Track's hand-written `==` / `hash` and let Swift synthesize
  them across all stored properties. SwiftUI now sees real content
  changes and the inspector updates as expected. `Playlist` keeps its
  spotifyId-only `==` because the sidebar's `selection: $selectedPlaylist`
  binding would otherwise lose the highlight on every sync (every sync
  bumps `syncedAt` on every playlist).

### Added
- **Playlist-level LLM round-trip.** `LLMPromptService` now also defines
  a separate, user-customizable playlist template. `renderPlaylist(...)`
  feeds in the playlist metadata plus a list of tracks (each line carries
  the spotifyId so the LLM can echo it back). `parsePlaylistResponse(_:)`
  decodes a `PlaylistResponse` carrying optional `playlistNotes`,
  `playlistTitle`, and a `tracks` array of partial track updates.
- **Toolbar Menu on `PlaylistDetailView`** with two items:
  - *Copy Prompt* — renders the playlist template and copies it.
  - *Apply Response* — parses the clipboard JSON, writes playlist notes /
    title (if provided) and applies a batch of track-field updates via
    `DatabaseService.applyTrackUpdates(_:)` in a single transaction.
    Reports applied / skipped counts in a transient capsule banner.
- `DatabaseService.TrackUpdate` value + `applyTrackUpdates(_:)` writer
  for partial bulk updates: only fields the LLM actually populated are
  written; everything else is preserved.
- **Settings → LLM Prompt** tab now has a Track / Playlist segmented
  picker so both templates are editable side-by-side, each with its own
  Reset to Default and placeholder reference.

## [1.2.1] — 2026-04-26

### Fixed
- **Track inspector did not visually refresh after sync** when only the
  Spotify-derived `songYear` (or other user-owned fields) changed.
  `TrackDetailView` was only resetting its local `@State` on
  `.onChange(of: track.spotifyId)`, so a sync that backfilled the year on
  the *same* selected track left the Year field showing its old empty
  value. Now also reacts to a content-hash key built from the
  user-owned fields, gated on `!isDirty` so the user's unsaved edits are
  never clobbered.

## [1.2.0] — 2026-04-26

### Added
- **Spotify song-year auto-fill.** `SpotifyAlbum` now decodes `release_date`,
  and `Track(from:)` seeds `songYear` from the leading 4 digits. On upsert,
  `DatabaseService` backfills `songYear` only when the existing row's value
  is `nil`, so manual user overrides are preserved across syncs.
- **LLM clipboard round-trip per track.** New `LLMPromptService` provides:
  - A user-customizable prompt template stored in `UserDefaults`
    (`llmPromptTemplate`). Default template asks the LLM to return a strict
    JSON object with `songYear`, `lyricSummary`, `lyrics`, and `notes`.
  - `render(for:)` substitutes track metadata into the template using
    `{{TRACK_NAME}}`, `{{ARTIST}}`, `{{ALBUM}}`, `{{YEAR}}`, `{{DURATION}}`,
    `{{SPOTIFY_URL}}` placeholders.
  - `parseResponse(_:)` decodes the LLM's clipboard text into a `Response`
    struct, tolerating a single pair of leading/trailing markdown code
    fences (most LLMs add them despite instructions).
- **Track detail panel** now has a "LLM Round-Trip" section with two
  buttons:
  - *Copy Prompt* — renders the template against the current track and
    writes it to the system pasteboard.
  - *Apply Response* — reads the pasteboard, parses the JSON, and applies
    the values to the matching fields. Marks the track dirty so the user
    confirms with Save. Errors surface in an alert; per-field application
    is reported in a status line.
- **Settings → LLM Prompt** tab — a Markdown / monospaced editor for the
  prompt template with a *Reset to Default* button. Settings window grew
  to 620×540 to fit the new editor comfortably.

## [1.1.0] — 2026-04-26

### Added
- **Three new track journaling fields** stored alongside existing notes /
  rating, all user-owned and never overwritten by sync:
  - `songYear: Int?` — release year, displayed as a small numeric input.
  - `lyrics: String` — full or partial song lyrics, Markdown.
  - `lyricSummary: String` — interpretation / summary, Markdown.
- **Markdown editor with format toolbar and live preview.**
  New `MarkdownEditor` view (in `Sources/MusicJournal/Views/MarkdownEditor.swift`)
  is now used everywhere the user enters long-form text:
  - Track Notes, Lyrics, Lyric Summary
  - Playlist Notes
  - Toolbar inserts/wraps Markdown for **Bold**, *Italic*, `code`,
    `## Heading`, `- bullet`, `1. numbered`, `> quote`. Heading/list/quote
    buttons act on the line(s) intersecting the current selection; bold /
    italic / code wrap the selection (or place the cursor between the
    markers when no selection).
  - Edit / Preview segmented toggle. Preview renders via `AttributedString`
    Markdown parsing.
  - **Native macOS spellcheck enabled** (`isContinuousSpellCheckingEnabled`
    on the underlying `NSTextView`). Uses the system spell checker — fully
    local, no network.
  - Editor is a `NSViewRepresentable` wrapper around `NSTextView` so the
    toolbar can mutate the live selection (SwiftUI `TextEditor` does not
    expose its selection range).
- **Reorganised `TrackDetailView`** with clear sections: Album art →
  Track info → Metadata badges → Rating → Year → Lyric Summary → Lyrics
  → Notes → Save → Open in Spotify. ⌘S triggers the Save button.

### Schema
- Migration `v2_track_extra_fields` adds:
  - `tracks.songYear INTEGER` (nullable)
  - `tracks.lyrics TEXT NOT NULL DEFAULT ''`
  - `tracks.lyricSummary TEXT NOT NULL DEFAULT ''`
- Existing rows pick up the defaults automatically; no data backfill.

### Database / API
- `DatabaseService.updateTrackNotes(...)` replaced by
  `updateTrackUserFields(spotifyId:notes:rating:songYear:lyrics:lyricSummary:)`
  which writes all user-owned fields in a single statement.
- `Track` Codable adds the three new keys.

### Export
- Markdown export per track now includes Year, Lyric Summary, Lyrics, and
  Notes as separate labelled blocks. PDF inherits via the shared Markdown
  pipeline. JSON export picks up the new fields automatically through
  `Track`'s Codable conformance.

## [1.0.5] — 2026-04-26

### Changed
- **Replaced `NavigationSplitView` with a manual `HStack`-based layout.**
  Three previous attempts (v1.0.2 through v1.0.4) tried to keep
  `NavigationSplitView` and stop the leading-edge sidebar clipping on macOS
  Tahoe by removing chrome modifiers, switching to `.inspector`, and
  inlining the search field. Each got partway but a different repro path
  (track selection, focus change, etc.) reintroduced the clip. With a plain
  `HStack` we own every pixel of the sidebar's frame, no implicit chrome
  exists for the system to mis-position, and the layout is stable under
  any selection or window-resize sequence.
- Sidebar now has a fixed 300 pt width and a `.ultraThinMaterial`
  background to preserve the native macOS sidebar appearance.

### Added
- **Suppress non-user-owned playlists in the sidebar.** Spotify's
  development-mode quota returns zero tracks for playlists owned by other
  users (followed playlists, public picks, etc.), so they're noise in the
  list. The sidebar now shows only playlists where `ownerSpotifyId`
  matches the signed-in user's Spotify ID.
- `SpotifyAuthService` decodes and persists the user's Spotify ID:
  - New `userSpotifyId: String?` published property.
  - Captured from `/me` during initial login and saved to `UserDefaults`.
  - Backfilled in the background on launch for sessions that pre-date this
    change, so existing installs don't need to re-login.
  - Cleared on `logout()`.
- Existing rows in the local DB owned by other users remain (sync no
  longer adds new ones, but they aren't actively pruned). They're hidden
  from the sidebar; a future version could add a one-shot cleanup.

## [1.0.4] — 2026-04-26

### Fixed
- **Playlist note edits not visible until app restart.**
  `PlaylistDetailView` was constructed with `let playlist: Playlist` — a
  value-type snapshot taken at first render. After a save, the DB and
  `AppState.playlists` had fresh values but the detail view kept rendering
  the stale snapshot. Quitting cleared state and re-selection picked up the
  fresh value, hence the "works after restart" symptom.

  Fix: `PlaylistDetailView` now takes only `playlistId: String` and resolves
  the live `Playlist` from `AppState.playlists` on every render. The
  `@Published` array drives re-renders automatically when `saveNotes()`
  finishes its `loadFromDatabase()`. `ContentView` updated to pass the ID.

### Fixed (continued)
- **Sidebar leading-edge clipping** — third pass after v1.0.2 / v1.0.3 didn't
  hold on macOS Tahoe.
  - Replaced `.searchable(placement: .sidebar)` with an inline `TextField`
    in a `VStack` at the top of the sidebar.
  - Removed `.navigationTitle("Music Journal")` and `.navigationSubtitle(...)`
    from the sidebar — the detail column already supplies the window title.
  - The sidebar now installs no implicit chrome modifiers, so there is no
    chrome stack for `NavigationSplitView` to mis-position. The playlist
    count moved to a small footer row inside the same `VStack`.

## [1.0.3] — 2026-04-26

### Fixed
- **Sidebar still clipped after selecting a track** (regression of the
  v1.0.2 fix; only addressed the playlist-selection trigger, not the
  track-selection trigger).
  - `PlaylistDetailView` previously hosted `TrackDetailView` inside an
    `HSplitView`. When a track was selected the HSplitView gained a child,
    forcing the parent `NavigationSplitView` to renegotiate column widths
    mid-flight. On macOS Tahoe this left the sidebar's content frame wider
    than its viewport, hiding the leading ~80 px of every row.
  - Replaced `HSplitView` with the macOS 14+ `.inspector(isPresented:)`
    modifier — the native trailing-panel API. The inspector manages its
    own column independently and does not perturb the parent split view.
  - Track-selection state is bridged to inspector visibility via a
    computed `Binding<Bool>`: opening when a track is picked, clearing the
    selection when the inspector is dismissed by the user.
- Added a defensive `.frame(minWidth: 260)` on the sidebar's `List`
  alongside `navigationSplitViewColumnWidth`, so the column cannot be
  squeezed below content width by any future child reflow.

## [1.0.2] — 2026-04-26

### Fixed
- **Sidebar leading-edge clipping after selecting a playlist.**
  When a playlist was selected on macOS Sonoma+ (most pronounced on Tahoe),
  the sidebar rows shifted left in their column — thumbnails disappeared and
  the first ~80 px of every row's title was cut off. Three contributing
  factors, all addressed:
  - `NavigationSplitView` had no explicit `columnVisibility` binding, so the
    system was free to mutate sidebar visibility on selection. Now bound to
    a `@State NavigationSplitViewVisibility` initialised to `.all`.
  - `navigationSplitViewColumnWidth` only set `min` and `ideal`; without a
    `max` the column could resize wider than the sidebar's effective viewport
    and content reflowed past the visible edge. Now `min: 260, ideal: 300, max: 360`.
  - `SidebarView.toolbar` registered a `Synced X` item already present in
    `ContentView.toolbar`. The duplicate item reserved chrome in the sidebar's
    own toolbar area, contributing to the layout shift. Removed.
- Added `.navigationSplitViewStyle(.balanced)` so column behaviour is
  predictable across macOS versions.

## [1.0.1] — 2026-04-26

### Changed
- **App icon redesigned** for clean readability at every Dock/Finder size.
  - macOS-style squircle with vertical green gradient (forest green → near-black).
  - Faint horizontal "journal lines" suggesting a notebook page.
  - Bold cream-colored eighth note as the centered focal element.
  - Replaces the previous vinyl-record-with-pen design, which became
    unreadable at 16–32 px sizes (pen and label note both shrank to noise).
- `make_icon.py` rewritten to draw the new design and emit all seven
  PNG sizes plus `Contents.json`.

### Fixed
- **Build failure: `Cannot find 'AppVersion' in scope`** in `ExportService.swift`.
  The committed `MusicJournal.xcodeproj` was stale and did not reference
  `Sources/MusicJournal/App/Version.swift`. Regenerated via
  `xcodegen generate` to match `project.yml`. Build now succeeds with
  `xcodebuild -scheme MusicJournal -configuration Debug`.

### Files touched
- `make_icon.py` — new design generator
- `Sources/MusicJournal/Resources/Assets.xcassets/AppIcon.appiconset/*` — regenerated PNGs and Contents.json
- `Sources/MusicJournal/App/Version.swift` — bumped to 1.0.1 / build 2
- `Sources/MusicJournal/App/Info.plist` — bumped CFBundleShortVersionString and CFBundleVersion
- `MusicJournal.xcodeproj/` — regenerated by xcodegen; now includes Version.swift

## [1.0.0] — 2026-04-24

Initial import into PhantomLives. Feature-complete v1, manually tested.

- Spotify OAuth 2.0 PKCE login
- Playlist + track sync from the Spotify Web API
- Local SQLite store via GRDB.swift
- User-owned annotations: per-playlist notes and custom titles, per-track notes and 1–5 star ratings
- Markdown / PDF / JSON export, with JSON re-import
- Settings window (Spotify + Data tabs)
- macOS 14+, SwiftUI, XcodeGen-managed project
