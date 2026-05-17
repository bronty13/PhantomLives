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
| ⬜ | View mode toggle (Thumbnail / List / Detail) | 3-icon segmented control; needs Thumbnail (grid) + Detail (single-clip viewer) modes |
| ⬜ | **Time** filter (Any / Last Hour / 24h / 7d / 30d / 3mo / 6mo / Last Year) | Date predicate on `modifiedAt` |
| ⬜ | **Filter** advanced dropdown (Size / Date / Folder / Rating / Tag / Duration / Audio codec / Video codec / Resolution / Frame rate / Spanning / FCP X) | Multi-criteria predicate builder |
| ✅ | Back / Forward navigation arrows + ⌘[/⌘] | History stack of folder selections; History menu |
| ⬜ | Drilldown as button (not toggle) — toggles drilldown for the *currently-selected folder* only | UX detail |
| ⬜ | Sort direction triangle | Asc/Desc toggle on the sort key |

---

## Browser views

| Status | View | Notes |
|---|---|---|
| ✅ | List view (table with thumbnail / name / codec / res / fps / duration / size) | |
| ⬜ | Thumbnail (grid) view | Tile grid like Finder Icon View; size slider |
| ⬜ | Single-clip Detail view | Player + tabs at the top with prev/next clip arrows |
| ⬜ | Extra columns: Date Modified, Date Created, Date Recorded, Display size, Aspect ratio, Rating, Frame rate (visible), Title, Description, Reel/Scene/Shot/Take/Angle, Camera | Add to the Table column set; persist visible-column set |

---

## Detail right pane (currently Content / Tracks / Log)

| Status | Tab | Notes |
|---|---|---|
| ✅ | Content | Metadata block + 30-frame grid |
| ✅ | Tracks | Per-track technical breakdown |
| 🟡 | Log → Markers / Subclips / Tags / Rating | Functional; should split into separate tabs like Kyno (Metadata / Subclips). Kyno's Metadata tab also has Reel / Scene / Shot / Take / Angle / Camera fields and a Description textarea. |
| ⬜ | **Metadata** dedicated tab with: Title, Description, Rating, Reel, Scene, Shot, Take, Angle, Camera, Tags, Markers | Schema additions: reel/scene/shot/take/angle/camera columns on `asset` (migration v2) |
| ⬜ | Subclips as own tab with Start / End / Title columns | Currently lives inside the Log pane |

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
| ⬜ | **5-second jumps**: Shift+Arrow or alternate J/L mode | Kyno's default J/L |
| ⬜ | **Up/Down arrows** = jump to next/previous marker or in/out | |
| ⬜ | **Alt+Space** = play in→out | |
| ⬜ | **Cmd+L** = toggle loop mode | AVPlayer.actionAtItemEnd |
| ⬜ | **Cmd+F** = full-screen toggle | NSWindow.toggleFullScreen + ESC to exit |
| ⬜ | **Cmd+Shift+E** = export current frame | Already have `AVAssetImageGenerator`; needs save panel |
| ⬜ | **Cmd+R / Cmd+Alt+R** = rotate right/left | Already have in View menu; bind as menu shortcuts |
| ⬜ | **Alt+M** / **Alt+S** = remove marker / subclip | |
| ⬜ | **Zebra filter** (Ctrl+Alt+E) | Metal/CIFilter: highlight pixels > threshold |
| ⬜ | **Widescreen mattes** (Ctrl+Alt+W) | Black bars at 2.39:1 or 1.85:1 |
| ⬜ | Aspect-fit / actual-size / fit-window zoom controls | "Fit: 52%" stepper in Kyno's toolbar |
| ⬜ | Loop-mode UI | |

---

## Sidebar (left)

| Status | Feature | Notes |
|---|---|---|
| ✅ | Folder tree with drilldown | |
| ✅ | **Workspace section** (multiple rooted folders) | "Add Folder to Workspace…" (⌘I) / "Clear Workspace…" gear menu, per-root context menu |
| ⬜ | **Devices section** | Enumerate mounted volumes via `FileManager.url(forUbiquityContainerIdentifier:)`/`URL(fileURLWithPath: "/Volumes")` |
| ⬜ | Sidebar collapsible sections (Workspace / Devices) | |
| ⬜ | Sidebar settings gear menu (workspace mgmt) | |

---

## Metadata schema

Schema migration `v2_metadata_fields` to add:

| Status | Column | Type |
|---|---|---|
| ⬜ | `title` | text |
| ⬜ | `reel` | text |
| ⬜ | `scene` | text |
| ⬜ | `shot` | text |
| ⬜ | `take` | text |
| ⬜ | `angle` | text |
| ⬜ | `camera` | text |
| 🟡 | `description` | text (currently inside `rating.description`) — promote to its own column |
| ✅ | `colorLabel` | text |

These should flow through to FCPXML as the corresponding `<metadata>`
entries (FCPXML metadata key/value).

---

## Preferences (currently: Backup / AI / About — Kyno has 6 panes)

| Status | Pane | Notes |
|---|---|---|
| ✅ | Backup | Already have |
| ✅ | AI | transcribe.py path, Whisper model, Ollama model |
| ✅ | About | |
| ⬜ | **General** — language (already comes via macOS), LUTs folder, Import LUTs from FCP, Import LUTs from Resolve, Apply detected LUTs to thumbnails | |
| ⬜ | **Tags** — user-defined tag library with Add / Remove / Import / Export | |
| ⬜ | **Conversion** — Max parallel conversions, user-defined transcode presets (Import / Export), Clear conversion-history | |
| ⬜ | **Devices** — Restore browser UI per device, Select device on connect, Auto-drilldown for camera media, Minimize multi-threaded access, Show DMG in devices, React-to-changes toggles | |
| ⬜ | **Transfer** — Registered SFTP endpoints, Slack notification webhook, Sidecar files config | Some of this already exists in the SFTP sheet |
| ⬜ | **Advanced** — Thumbnail loading performance, Ignored files/folders glob, Use drop-frame timecode, Use zero-based timecode, Shared cache folder, Store metadata in (hidden dirs / sidecar files) | |

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
| ⬜ | ⌘1/⌘2/⌘3 | Switch to Thumbnail/List/Detail view |
| ⬜ | ⌘← / ⌘→ | Prev/next clip in detail view |
| ⬜ | ⌘[ / ⌘] | History back/forward |
| ⬜ | ⌘I | Add folder to workspace |
| ⬜ | Shift+← / Shift+→ | 5-second jump |
| ⬜ | ↑ / ↓ | Jump to next/prev marker |
| ⬜ | ⌥Space | Play in→out |
| ⬜ | ⌘L | Toggle loop |
| ⬜ | ⌘F / ESC | Full-screen toggle |
| ⬜ | ⌘⇧E | Export current frame |
| ⬜ | ⌘R / ⌘⌥R | Rotate right / left |
| ⬜ | ⌥M / ⌥S | Remove marker / subclip |
| ⬜ | ⌃⌥E / ⌃⌥W | Zebra / widescreen filter |
| ⬜ | ⌘⇧M | Batch metadata edit |
| ⬜ | ⌘⇧T | Batch tag edit |

---

## Effort-buckets for the open items

**Small** (1-2 hours each):
- 5-second jump (Shift+Arrow)
- Up/Down marker navigation
- Cmd+L loop
- Cmd+F full-screen
- Cmd+R / Cmd+Alt+R rotate shortcuts
- Alt+M / Alt+S remove
- Time filter dropdown
- Sort direction toggle
- Extra Table columns
- Devices sidebar section
- Subclips own tab

**Medium** (half-day each):
- Cmd+Shift+E export frame
- Cmd+1/2/3 view mode toggle (needs Thumbnail grid view)
- Metadata schema migration v2 + UI fields (Reel/Scene/Shot/Take/Angle/Camera)
- Workspace = multi-root (need to evolve `rootFolder` → `[rootFolder]`)
- History stack (back/forward)
- Filter advanced dropdown (multi-criteria builder)
- Zebra + widescreen filter (CIFilter chain)
- Preferences panes (General, Tags, Conversion, Devices, Transfer, Advanced) — split across several rounds

**Large** (1+ day):
- Single-clip Detail view mode (with prev/next clip nav)
- Thumbnail (grid) view with size slider
- Batch metadata edit sheet (Cmd+Shift+M)
- LUT auto-detect from FCP/Resolve libraries

**Explicitly skipped** (out of FCP-only scope):
- Avid Op-Atom MXF, RED R3D, P2, DNxHD non-rewrap — already declined in original build plan
- "Final Cut Pro X" advanced filter criterion — would require parsing FCP library state
