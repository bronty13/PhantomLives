# Migrating from Kyno to PurpleReel

A practical walkthrough for the doc shooter / post house / AE
workflow that's currently driven by Kyno and considering PurpleReel.

This guide is task-oriented. For per-feature parity status see
[`KYNO_RESEARCH.md`](KYNO_RESEARCH.md); for the marketing pitch see
the README's "Why PurpleReel (vs Kyno)" section.

---

## 1. First launch — set up your workspace

1. **Drop your media folder onto the dock icon** OR
   File → Open Folder… (`⌘O`). PurpleReel walks the tree once,
   probes every clip with AVFoundation, builds the catalog in
   `~/Library/Application Support/PurpleReel/db.sqlite`.
2. PurpleReel's first launch shows a Permissions Wizard. Grant
   **Files & Folders** for `Movies/`, `Downloads/`, and
   `Documents/` (or Full Disk Access if you'd rather hand-wave
   them all at once). Removable Volumes is informational — macOS
   prompts you the first time you scan a card.
3. The browser opens in **List view** by default; switch to Grid
   with `⌘1` or Detail with `⌘3`. Both honor the same selection.

**Key conceptual difference vs Kyno**: PurpleReel's catalog is
*centralized* (one SQLite DB) and *additive* (each scan upserts;
nothing gets dropped without an explicit purge). If a clip moves
off-volume, it stays in the catalog as "offline" — visible but
greyed out. Run **Metadata → Find Lost Metadata** to reconnect by
file fingerprint.

## 2. Bring in your Kyno metadata

PurpleReel reads Kyno's hidden `.LP_Store/` sidecar XML directly.

1. **Metadata → Import from Kyno (.LP_Store)…**
2. Pick the folder root your Kyno catalog was scoped to. PurpleReel
   walks the tree, parses every `.LP_Store/*.xml`, and merges:
   - **Ratings** (1–5★) — never demoted; a local 4★ stays 4★ if
     Kyno had it at 2★.
   - **Tags** (Kyno "keywords") — union with whatever's already in
     PurpleReel.
   - **Markers** (timecode + note) — additive; ±1-frame dedupe by
     `(timecode, note)`.
   - **Log fields** (Title, Description, Reel, Scene, Shot, Take,
     Angle, Camera) — only fill empty slots; never overwrite a
     local edit.
3. The summary alert reports `matched / applied / skipped /
   unmatched`. Unmatched filenames usually mean the source files
   moved since Kyno indexed them — rescan the workspace first, then
   re-run.

**Caveat**: PurpleReel keeps the metadata in its SQLite DB; it
doesn't write back to `.LP_Store/`. Once you've migrated, Kyno
won't see your subsequent edits. The migration is one-way by design.

## 3. Round-trip with Final Cut

PurpleReel speaks FCPXML 1.10 in both directions. The typical
workflow:

1. Log in PurpleReel (markers `M`, tags `T`, subclips `S`, ratings
   `1`–`5`, log fields in the Metadata pane).
2. **File → Export FCPX XML…** (`⌘E`) — pick keywords-from-tags,
   favorites-from-rating, etc. PurpleReel writes the FCPXML and
   hands it to Final Cut.
3. The editor cuts in FCP, adds notes / markers / keywords.
4. **File → Export → XML…** from FCP, save next to the source media.
5. Back in PurpleReel: **Metadata → Import FCPXML…**. The importer
   re-ingests markers, keywords, favorites, and metadata; **it never
   creates assets**, so unmatched references are reported but don't
   pollute the catalog.

Each FCPXML import also records which FCP project(s) referenced each
clip (C25). The inspector's "FCP Projects" section surfaces the
membership when you select a clip.

## 4. Camera-card workflow

PurpleReel ships a **Workflow Chains** feature for the daily DIT
flow — Verified Backup → Transcode → Export Report as one job, with
optional auto-trigger on camera-media mount.

1. **File → Workflow Chains… (`⌘⇧Y`)**.
2. **Add from template…** — the "Camera Card Offload" template gives
   you a single-step Verified Backup chain with auto-mount enabled.
3. Add destinations to the Backup step (1–4 drives in parallel; MHL
   v1.1 or ASC-MHL v2.0 manifest format).
4. Eject and re-mount your card — PurpleReel offers to run the
   chain. Accept and the verify + copy runs in the background.
5. Mid-run cancel works at file boundaries (C37) — your
   half-verified files stay where they were, and the next file
   is marked cancelled rather than failed.

If a chain run is interrupted (force-quit, crash, Mac shutdown), the
**next launch** offers to resume from the first incomplete step
(C34). Persisted state lives in
`~/Library/Application Support/PurpleReel/active-runs/`.

## 5. Keyboard shortcuts: muscle-memory mapping

PurpleReel ships a **Coming from Kyno** first-launch toggle
(Settings → General) that flips a dozen keybindings + labels to match
Kyno's defaults — J/L → 5-second jumps, ⌃⌥E zebra, ⌃⌥W matte, etc.
See [`SHORTCUTS.md`](SHORTCUTS.md) for the full reference.

The most-different defaults from Kyno (before the toggle flips them):

| Action | Kyno | PurpleReel default |
|---|---|---|
| J / L | 5-sec jumps | ¼× → 4× shuttle (multi-rate) |
| ⌘⇧D | Send to Resolve | Toggle drilldown |
| ⌘U | Subclip export | Mark subclip |
| X | Mute audio | Toggle current marker |

Toggling **Settings → General → Coming from Kyno** unifies them.

## 6. Where PurpleReel differs (deliberately)

- **No per-folder sidecar.** PurpleReel stores everything in the
  central SQLite catalog. (Optional: enable **Workspace Cache** in
  Settings → General to drop a hidden `.purplereel/` sidecar next to
  each clip — useful for shared NAS / SAN team setups.)
- **No live waveform analysis on import.** Waveforms generate
  lazily, on first browse, and cache to
  `~/Library/Application Support/PurpleReel/waveforms/` keyed by
  `(path, modtime, bucket-count)`. Subsequent loads are an instant
  JSON read.
- **No "edit in place" mode for FCPXML.** FCPXML is purely
  read-back; PurpleReel never opens FCP's `.fcpbundle` directly
  (CoreData / binary plist — too brittle). Your changes live in
  PurpleReel's catalog OR get re-exported back to FCP via FCPXML.
- **Apple Silicon native by design.** No Rosetta translation; the
  app + every transcode preset runs at the hardware encoder's
  native speed.

## 7. Quick-reference: where things live on disk

| What | Where |
|---|---|
| Catalog database | `~/Library/Application Support/PurpleReel/db.sqlite` |
| Thumbnails | `~/Library/Application Support/PurpleReel/thumbnails/` |
| Waveforms | `~/Library/Application Support/PurpleReel/waveforms/` |
| Settings | `~/Library/Preferences/com.bronty.PurpleReel.plist` |
| Auto-backups (DB + settings) | `~/Downloads/PurpleReel backup/` |
| Workflow-chain run snapshots | `~/Library/Application Support/PurpleReel/active-runs/` |
| Output (transcodes, reports, exports) | `~/Downloads/PurpleReel/<subdir>/` (configurable per dialog) |
| Workspace-cache sidecars (if enabled) | `<source-volume>/<dir>/.purplereel/<file>.json` |

---

If something didn't migrate the way you expected, the most useful
next steps:

1. **Check the Permissions Wizard** — most "I don't see my media"
   issues are Files & Folders / Full Disk Access denials.
2. **Run "Find Lost Metadata"** — files moved or renamed since the
   last scan reconnect via SHA-1 fingerprint.
3. **File an issue** at <https://github.com/bronty13/PhantomLives/issues>
   — PurpleReel's community lives in GitHub Discussions / Issues
   (the original Kyno forums are offline).
