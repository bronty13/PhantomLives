# Kyno Parity Roadmap

Living checklist of Kyno-visible features that PurpleReel doesn't yet
match. Built from user-supplied Kyno screenshots + the Kyno
[keyboard shortcuts](https://support.lesspain.software/support/solutions/articles/12000010141-keyboard-shortcuts)
reference. Order within each section is roughly by user-impact and
implementation cost.

Legend: ✅ done · 🟡 partial · ⬜ open · ❌ explicitly skipped

---

## Browser toolbar

| Status | Feature | Notes |
|---|---|---|
| ✅ | Drilldown toggle | Toolbar pill |
| ✅ | Type filter chips (All / Video / Audio / Images) | Capsule buttons |
| ✅ | Sort dropdown (Name / Date / Size / Duration / FPS) | `@AppStorage` |
| ✅ | Name filter (search field) | |
| ✅ | View mode toggle (Grid / List / Detail) | 3-icon segmented control bound to ⌘1/⌘2/⌘3 |
| ✅ | **Time** filter (Any / Last Hour / 24h / 7d / 30d / 3mo / 6mo / Last Year) | Date predicate on `modifiedAt` |
| 🟡 | **Filter** advanced dropdown (Size / Date / Folder / Rating / Tag / Duration / Audio codec / Video codec / Resolution / Frame rate / Spanning / FCP X) | Multi-criteria predicate builder shipped: Rating / Tag / Video Codec / Audio Codec / Resolution / Frame Rate / Size / Duration / Date Modified / Date Recorded / In Folder. Pills bar + UserDefaults persistence. **TODO (out of scope for PurpleReel's data model)**: Spanning (multi-file clip detection), FCP X library predicate. |
| ✅ | Back / Forward navigation arrows + ⌘[/⌘] | History stack of folder selections; History menu |
| ✅ | Drilldown as button (not toggle) — toggles drilldown for the *currently-selected folder* only | Per-folder set in AppState; toolbar button acts on selection |
| ✅ | Sort direction triangle | Asc/Desc toggle in sort menu, persisted via `sortAscending` |

---

## Browser views

| Status | View | Notes |
|---|---|---|
| ✅ | List view (table with thumbnail / name / codec / res / fps / duration / size) | |
| ✅ | Thumbnail (grid) view | LazyVGrid tiles with selection ring + transcode-progress overlay; toolbar tile-size slider (Grid-only, 100…320 pt, persisted via `@AppStorage("gridTileSize")`) |
| ✅ | Single-clip Detail view | `ClipDetailInline` — player + metadata pane; ⌘1/⌘2/⌘3 switches mode |
| 🟡 | Extra columns: Date Modified, Date Created, Date Recorded, Display size, Aspect ratio, Rating, Frame rate (visible), Title, Description, Reel/Scene/Shot/Take/Angle, Camera | Rating / Date Modified / Title / Description / Reel/Scene/Shot/Take/Angle/Camera done via `ListColumn` toolbar menu (Table cap = 3 optional at a time). Date Recorded + Audio Codec now in the schema (v3 migration) — surface as List columns in a follow-up. **TODO**: Date Created, Display size, Aspect ratio. |

---

## Detail right pane (currently Content / Tracks / Log)

| Status | Tab | Notes |
|---|---|---|
| ✅ | Content | Metadata block + 30-frame grid |
| ✅ | Tracks | Per-track technical breakdown |
| 🟡 | Log → Markers / Subclips / Tags / Rating | Functional; should split into separate tabs like Kyno (Metadata / Subclips). |
| ✅ | **Metadata** dedicated tab with: Title, Description, Rating, Reel, Scene, Shot, Take, Angle, Camera, Tags, Markers | `MetadataPaneView`; v2 migration shipped as separate `clip_metadata` table. Markers section appears at the bottom when the pane is hosted next to a player (BrowserView inspector + Detail-mode right pane). |
| ✅ | Subclips as own tab with Start / End / Title columns | New `.subclips` `DetailTab` between Tracks and Log; Log still owns Markers + Tags + Rating |

---

## Player

| Status | Feature | Notes |
|---|---|---|
| ✅ | Play / pause | Space |
| ✅ | Frame step ←/→ | |
| ✅ | Multi-rate J/L shuttle | NB: Kyno uses J/L as 5-second jumps instead (different convention). Worth offering both as a setting. |
| ✅ | I / O mark in/out | |
| ✅ | M add marker | |
| ✅ | S save subclip from I/O | |
| ✅ | View menu (Rotate 0/90/180/270, Flip H/V) | |
| ✅ | LUT loader | |
| ✅ | Audio waveform overlay | |
| ✅ | Multi-rate shuttle | |
| ✅ | **5-second jumps**: Shift+Arrow or alternate J/L mode | Shift+← / Shift+→ shipped; alternate J/L mode via Playback → "J / L Behaviour" submenu, sticky in @AppStorage("playerJLMode") |
| ✅ | **Up/Down arrows** = jump to next/previous marker or in/out | `PlayerController.seekToAnchor(direction:markerTimes:)` — union of markers + I/O |
| ✅ | **Alt+Space** = play in→out | Wired via menu + PlayerCommand.playInToOut |
| ✅ | **Cmd+L** = toggle loop mode | `PlayerController.loopMode` + didPlayToEnd observer |
| ✅ | **Cmd+F** = full-screen toggle | `NSWindow.toggleFullScreen` |
| ✅ | **Cmd+Shift+E** = export current frame | `PlayerController.exportCurrentFrame()` w/ save panel |
| ✅ | **Cmd+R / Cmd+Alt+R** = rotate right/left | `PlayerController.rotateBy(±90)`; menu items in Playback |
| ✅ | **Alt+M** / **Alt+S** = remove marker / subclip | ⌥M nearest-marker-to-playhead, ⌥S removes most-recent subclip |
| ⬜ | **Zebra filter** (Ctrl+Alt+E) | Metal/CIFilter: highlight pixels > threshold |
| ⬜ | **Widescreen mattes** (Ctrl+Alt+W) | Black bars at 2.39:1 or 1.85:1 |
| ⬜ | Aspect-fit / actual-size / fit-window zoom controls | "Fit: 52%" stepper in Kyno's toolbar |
| ✅ | Loop-mode UI | Orange `repeat.circle.fill` button in transport bar |

---

## Sidebar (left)

| Status | Feature | Notes |
|---|---|---|
| ✅ | Folder tree with drilldown | |
| ✅ | **Workspace section** (multiple rooted folders) | "Add Folder to Workspace…" (⌘I) / "Clear Workspace…" gear menu, per-root context menu |
| ✅ | **Devices section** | Enumerates `/Volumes/*`; boot-volume firmlink resolved to `/` so its prefix matches catalogued paths |
| ✅ | Sidebar collapsible sections (Workspace / Devices / Stats) | Disclosure chevron on each section header; per-section `@AppStorage` so the collapse state persists across launches |
| ✅ | Sidebar settings gear menu (workspace mgmt) | Top-right gear in Workspace header |

---

## Metadata schema

Schema migration `v2_clip_metadata` — **shipped** as a separate
`clip_metadata` table (1:1 with `asset`, FK cascade) so the
scanner-owned `asset` table stays tightly scoped to technical
columns. Edits commit on Return / focus loss from the Metadata pane.

| Status | Column | Type |
|---|---|---|
| ✅ | `title` | text |
| ✅ | `reel` | text |
| ✅ | `scene` | text |
| ✅ | `shot` | text |
| ✅ | `take` | text |
| ✅ | `angle` | text |
| ✅ | `camera` | text |
| ✅ | `description` | text (its own column in `clip_metadata`) |
| ✅ | `colorLabel` | text (on `rating` table) |

These flow through to FCPXML as `<metadata>` entries with `<md
key="Title" value="…"/>` style children, omitted entirely when no
field is populated.

---

## Preferences (currently: Backup / AI / About — Kyno has 6 panes)

| Status | Pane | Notes |
|---|---|---|
| ✅ | Backup | Already have |
| ✅ | AI | transcribe.py path, Whisper model, Ollama model |
| ✅ | About | |
| ✅ | **General** — LUTs folder + Choose/Open, Import LUTs from FCP/Resolve (flags), Apply detected LUTs to thumbnails (flag), Clear Thumbnail Cache button | Auto-import from FCP/Resolve libraries is the larger Phase-2 piece; flags persist meanwhile. |
| ✅ | **Tags** — user-defined tag library with Add / Remove / Import / Export | JSON Import/Export (accepts `["a","b"]` or `{"tags":[…]}`), additive union on import |
| ✅ | **Conversion** — Max parallel conversions (consumed by TranscodeQueue), user-defined transcode presets stub, **Clear Conversion History** (wired to `transcodeQueue.clearDone()`) | Custom-preset Import/Export deferred; built-in preset catalogue covers Kyno's defaults |
| ✅ | **Devices** — Select device on connect, Auto-drilldown for camera media, Show DMG in devices, React-to-changes (local/removable/network) toggles | All toggles persist; consumers (volume-change watcher) are future-hook |
| ✅ | **Transfer** — pointer to SFTP delivery sheet (endpoints managed there), Slack notification web-hook URL, Sidecar file extension picker | Slack post is a future feature; URL persists today |
| ✅ | **Advanced** — Thumbnail loading performance, **Ignored files/folders glob** (consumed by MediaScanner), Use drop-frame timecode (consumed by Timecode formatter), Use zero-based timecode, Confirm copy/move, Debug mode, Metadata storage choice, **Reset All Preferences** | Ignored-globs uses tiny `fnmatch` impl supporting `*`/`?`; SMPTE-12M drop-frame implemented for 29.97 / 59.94 |

---

## Keyboard shortcuts (cross-cut)

| Status | Combo | Action |
|---|---|---|
| ✅ | Space | Play/pause |
| ✅ | ←/→ | Step 1 frame |
| ✅ | I/O | Mark in/out |
| ✅ | M | Add marker |
| ✅ | S | Save subclip |
| ✅ | J/K/L | Shuttle (PurpleReel convention; Kyno uses J/L for 5-sec jumps) |
| ✅ | ⌃⌘S | Toggle sidebar |
| ✅ | ⌘1/⌘2/⌘3 | Switch to Grid / List / Detail view |
| ✅ | ⌘← / ⌘→ | Prev/next clip in detail view |
| ✅ | ⌘[ / ⌘] | History back/forward |
| ✅ | ⌘I | Add folder to workspace |
| ✅ | Shift+← / Shift+→ | 5-second jump |
| ✅ | ↑ / ↓ | Jump to next/prev marker (or in/out) |
| ✅ | ⌥Space | Play in→out |
| ✅ | ⌘L | Toggle loop |
| ✅ | ⌘F / ESC | Full-screen toggle |
| ✅ | ⌘⇧E | Export current frame |
| ✅ | ⌘R / ⌘⌥R | Rotate preview right / left |
| ✅ | ⌥M / ⌥S | Remove marker (nearest playhead) / most-recent subclip |
| ⬜ | ⌃⌥E / ⌃⌥W | Zebra / widescreen filter |
| ✅ | ⌘⇧M | Batch metadata edit — per-field opt-in apply across multi-selection |
| ⬜ | ⌘⇧T | Batch tag edit |
| ✅ | ⌘E | Convert with most-recent preset |
| ✅ | Cmd-click / Shift-click | Multi-select in grid + list |

---

## Documentation (backlog)

External docs that ship alongside the app — every item should also be
reachable from the in-app Help menu so users don't have to leave the
window to find them.

| Status | Doc | Notes |
|---|---|---|
| ✅ | `USER_MANUAL.md` — full task-oriented user manual | **Shipped.** End-to-end coverage: quick start → Workspace + Devices sidebar (incl. drilldown) → browser (Grid/List/Detail, multi-select, advanced Filter, columns, sort) → player (transport, scrub, loop, fullscreen, frame export, LUT) → logging (Metadata + Content + Tracks + Log tabs) → Convert workflow (categorized presets + dialog + per-asset progress) → verified backup + MHL → SFTP delivery → Send to FCP → AI (Whisper / Ollama / Similar Takes) → batch rename → Settings panes → recovery → file-system layout. Cross-links INSTALL.md + SHORTCUTS.md. **Backlog**: screenshots. |
| ✅ | `INSTALL.md` — install manual | **Shipped.** System requirements / two install paths (`.app` and source) / Gatekeeper bypass / TCC (Files & Folders / Full Disk Access) / auto-backup-on-launch / optional deps (ffmpeg / Whisper / Ollama / sshpass) / troubleshooting / file-system layout / uninstall. Opened via Help → Install & Setup. |
| ✅ | `SHORTCUTS.md` — keyboard shortcut cross-reference | **Generated** from `Sources/PurpleReel/Help/Shortcuts.swift` by `Scripts/generate-shortcuts-md.swift` (auto-run from `build-app.sh`). Single source-of-truth shared with the in-app cheat sheet — they can't drift. |
| ✅ | In-app **Help → User Manual** menu | Opens USER_MANUAL.md via `HelpDocs.open(.userManual)` (bundle → sibling-of-binary → repo path). |
| ✅ | In-app **Help → Keyboard Shortcuts** menu | `ShortcutsCheatSheet` sheet (⌘?). Searchable, grouped, reads `Shortcuts.all`. |
| ✅ | In-app **Help → Install & Setup** menu | Wired to open `INSTALL.md`; alerts politely until the doc itself ships. |
| ✅ | Bundle docs into the `.app` | **Shipped.** `build-app.sh` stages USER_MANUAL.md / INSTALL.md / SHORTCUTS.md / KYNO_PARITY_ROADMAP.md into `Sources/PurpleReel/Resources/Help/` before xcodegen runs; xcodegen bundles them under `Contents/Resources/`. `HelpDocs.locate()` checks bundled paths first (with and without the `Help` subdir for xcodegen-flattening tolerance), falls back to sibling-of-binary + repo-path for dev builds. Staged copies gitignored — single source of truth is the repo-root *.md. |
| ✅ | Help search-bar entries | **Shipped.** Apple Help Book bundle (`PurpleReel.help`) generated at build time from the four `.md` docs by `Scripts/generate-help-book.swift` (minimal Markdown→HTML — headings / paragraphs / fenced code / inline code / lists / pipe tables / links / bold / italic / horizontal rules). `hiutil` builds the `.helpindex`. `CFBundleHelpBookFolder` + `CFBundleHelpBookName` registered in `Info.plist`. xcodegen `type: folder` preserves the bundle directory tree. macOS Help menu's search field finds matching topics across every doc. |

Implementation order suggestion:
1. **`SHORTCUTS.md`** first (smallest, derives directly from the
   roadmap's existing table) + ship a Help menu entry that opens it.
2. **`INSTALL.md`** second (also small; mostly already-known
   prerequisites).
3. **`USER_MANUAL.md`** expansion last — biggest single doc, benefits
   from referencing the other two.

Single-source-of-truth idea: keep the shortcut definitions in a Swift
file (`Help/Shortcuts.swift`) and *generate* both `SHORTCUTS.md` and
the in-app cheat-sheet from it at build time. Stops the doc / menu /
code drift problem that hits every keyboard-heavy app.

---

## Effort-buckets for the **remaining** open items

**Small** (1-2 hours each):
- (small bucket fully drained — see open items in the larger feature
  tables above)

**Medium** (half-day each):
- Zebra + widescreen filter (CIFilter chain on the player)
- Aspect-fit / actual-size / fit-window zoom controls
- In-app Markdown renderer (currently Help → User Manual opens
  bundled .md via NSWorkspace which defers to the user's default
  Markdown viewer)
- Custom transcode presets — Import/Export user-defined presets
  alongside the built-in catalogue
- Volume-change watcher consuming the Devices-pane "React to
  changes on …" toggles

**Large** (1+ day):
- LUT auto-detect from FCP / Resolve libraries
- USER_MANUAL.md full task-oriented rewrite with screenshots
- Shortcuts single-source-of-truth file + build-time generator (Swift
  → `SHORTCUTS.md` + in-app cheat-sheet)

**Explicitly skipped** (out of FCP-only scope):
- Avid Op-Atom MXF, RED R3D, P2, DNxHD non-rewrap — already declined in original build plan
- "Final Cut Pro X" advanced filter criterion — would require parsing FCP library state
