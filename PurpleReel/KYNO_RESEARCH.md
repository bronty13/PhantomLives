# Kyno Parity & Competitive Research

External research snapshot compiled **2026-05-18** — input to the
next planning round. This sits next to [`KYNO_PARITY_ROADMAP.md`](KYNO_PARITY_ROADMAP.md)
(the living checklist of feature parity) and exists to capture the
broader picture: not just "what's on Kyno's feature page", but also
behavior differences that create migration friction, competitive
features from adjacent tools, and recurring annoyances that we can
solve to position PurpleReel above the competition.

## Sources surveyed

- Kyno release notes (every version since 1.0)
- Kyno keyboard-shortcut reference + product feature pages + FAQ
- ProVideo Coalition coverage (Scott Simmons — multi-year)
- Richard Lackey, Definition Magazine, Pixel Valley, Newsshooter reviews
- DPReview / forum threads
- "Still Alive, Still Useful" Kyno 1.9 launch article
  (Digital Production, September 2025)
- Competing products: Hedge OffShoot / EditReady, Pomfort Silverstack,
  Imagine ShotPut Pro, Quantum CatDV, Photo Mechanic, Videoloupe,
  Aftershoot

## Categories

- **Parity gap** — feature Kyno has that we don't (includes
  some items we explicitly skipped in the original build plan —
  flagged so we can revisit)
- **Behavior difference** — feature we have but that operates
  differently from Kyno, where alignment would reduce friction for
  converting users
- **Competitive improvement** — feature from an adjacent tool
  (Hedge / Pomfort / CatDV / Photo Mechanic etc.) that would
  leapfrog Kyno
- **Annoyance to solve** — recurring Kyno user complaint we can
  fix to differentiate (or marketing lever vs Kyno's perceived
  abandonment)

## How to read PurpleReel status

| Status | Meaning |
|---|---|
| `Missing` | Not built; on the roadmap |
| `Partial` | Some-but-not-all of Kyno's behavior |
| `Shipped` | Confirmed in PurpleReel today |
| `Different behavior` | Built but operates differently — friction risk |
| `Explicitly skipped` | Out of FCP-only scope per original build plan |

## How to read Effort

Same buckets `KYNO_PARITY_ROADMAP.md` already uses, so a row can
graduate from this doc into the roadmap without re-estimating.

| Bucket | Time | Examples |
|---|---|---|
| **Small** | ≤2 hours | Keybinding, single column add, one-line sort fix, marketing copy, toggle wired to existing service |
| **Medium** | ~½ day | New UI section, schema migration with form, CIFilter chain, format writer, batched action |
| **Large** | 1+ day | Full subsystem, distributed cache, NLE round-trip, query language, localization sweep |
| **Shipped** | — | Already done — marketing / verify only |
| **Skipped** | — | Out of scope per original build plan |

---

## Recommended starting sprint

> **Status (2026-05-18 evening):** Sprint 1 and Sprint 2 both shipped.
> Fade-in/out (the one Sprint 2 item that originally deferred) also
> shipped. Below the two sprint plans, see "Sprint 3+ candidates"
> for the remaining open items.

### Sprint 1 — "Coming from Kyno" Compatibility Mode (≈1 day) — ✅ Shipped

One first-launch sheet ("I'm coming from Kyno") that flips ~12
behavior-difference defaults in a single click. Mid-session
"Restore PurpleReel defaults" button in Settings → General reverses
the choice. Bundles:

| Row | Item |
|---|---|
| 36 | J/L → 5-sec jumps (toggle already exists) |
| 37 | View-mode label "Thumbnail" instead of "Grid" |
| 38 | Cmd-Left/Right = next/previous clip in Detail view |
| 39 | ⌃⌥E = zebra, ⌃⌥W = widescreen matte |
| 40 | X = mute audio |
| 42 | Alt-Shift-O = open with default app |
| 43 | Cmd-Alt-M = focus metadata input |
| 44 | ⌘⇧D = toggle drilldown |
| 45 | Cmd-U = subclip export |
| 47 / 25 | ⌘⇧T = batch tag editor (already-flagged OPEN GAP) |
| 51 | Don't auto-drilldown camera structures (one Settings toggle) |
| 54 | Natural numeric file-name sort (`localizedStandardCompare`) |

Why this is the start: every row is individually Small, but
together they eliminate the dominant keyboard-muscle-memory failure
mode for converting Kyno users. The Top-5 already flags J/L
individually as critical retention — bundling it gives 12× the
friction reduction for ~1.5× the work.

### Sprint 2 — Migration safety net + standalone Smalls (≈2 days) — ✅ Shipped

Sequence:

1. **Find Lost Metadata reconnect** (rows 4 + 31) — **Medium**.
   File-fingerprint reconnect (size + modtime + optional SHA-1)
   keyed against `clip_metadata`. Single highest-anxiety blocker —
   without it the first reorganization wipes a user's tags.
2. **Paste Metadata between clips** (row 6) — Small.
3. **Play-all-selected continuous** (row 9) — Small.
4. **Incremental transcoding** (row 13) — Small.
5. **Smart proxy auto-scale presets** (row 12) — Small.
6. **Date Recorded / Date Created columns** (row 33) — Small.
7. **Display size + Aspect ratio columns** (row 34) — Small.
8. **Zero-based TC preference** (row 22) — Small.
9. **LUT-on-still-frame-export default** (row 55) — Small.
10. **Audio channel names** (row 84) — Small schema add.
11. **Shift-click = hard refresh** (row 50) — Small.
12. **Subclip name-collision auto-disambiguate** (row 83) — Small.
13. **File-count safety-limit warning** (row 78) — Small.
14. **Transcoder file-timestamp preservation toggle** (row 21) — Small.
15. **Fade in/out transcoder option** (row 20) — Small.

Closes 14 friction items + the #1 safety net in ~2 days.

### Sprint 3+ — Multi-day individual items (each its own decision)

Don't bundle. Defer until explicitly directed:

- Row 5 — FCPXML re-import / round-trip — **Large**
- Row 7 — shared `.LP_Store/` cache for NAS — **Large**
- Row 14 — folder-tree metadata transfer — **Medium**
- Row 16 / 24 — Excel/CSV export with embedded thumbnails — **Medium**
- Row 67 — hover-scrub thumbnails in grid — **Medium**
- Row 79 — first-launch permissions wizard — **Medium**
- Row 80 — Kyno `.LP_Store/` XML import — **Medium**

### Free marketing levers (no engineering)

Rows 71, 72, 77, 81 — Signiant abandonment perception, dead Kyno
forum, Apple Silicon native, license-model copy. Half a day of
README + landing-page writing for measurable conversion lift.

---

## Findings

| # | Category | Item | Source type | Source URL | Effort | PurpleReel status | Friction / improvement note |
|---|---|---|---|---|---|---|---|
| 1 | Parity gap | Send-to NLE: Avid Media Composer ALE export + marker copy/paste | Kyno docs | https://lesspain.software/kyno/integrations/ | Large | Explicitly skipped | FCP-only is your scoped choice, but Avid ALE is the single most-cited Premium Kyno integration. Kyno users running multi-NLE shops will balk; consider a one-page "FCP-only by design" doc in onboarding. |
| 2 | Parity gap | Send-to NLE: Premiere Pro with XMP sidecars | Kyno docs | https://lesspain.software/kyno/integrations/ | Large | Explicitly skipped | Same scoping logic; surface as a deliberate skip. Will lose the "occasional Premiere day" editor entirely. |
| 3 | Parity gap | Send-to NLE: DaVinci Resolve via FCP7 XML | Kyno docs | https://lesspain.software/kyno/integrations/ | Medium | Explicitly skipped | Resolve users currently can't bring metadata + markers across. Cheap to enable later via Pipeline Neo's FCP7 path; flag as v2 candidate. |
| 4 | Parity gap | "Find Lost Metadata" / reconnect after move-rename | Forum/Reddit post | https://support.lesspain.software/support/discussions/topics/12000027432 | Medium | Shipped | Metadata → Find Lost Metadata… walks the catalogue, indexes (filename, size) across workspace roots, rewrites paths via `db.updateAssetPath`. Markers/subclips/tags/ratings reconnect via `assetId`. (Sprint 2, `0d09c43`) |
| 5 | Parity gap | Metadata import/merge from FCPX + Premiere XML back into Kyno | Kyno docs | https://lesspain.software/kyno/integrations/ | Large | Missing | Kyno reads what editors added in the NLE and merges it back into the library. PurpleReel exports FCPXML but doesn't appear to ingest. Round-trip is a recurring Kyno selling point. |
| 6 | Parity gap | Paste Metadata between clips (proxy → master, different containers) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | ⌥⌘C copies, ⌥⌘V applies to multi-selection. Tags union additively. Markers/subclips intentionally not copied (timecode-anchored). (Sprint 2) |
| 7 | Parity gap | Shared cache for thumbnails/metadata on NAS/SAN (`.LP_Store/`) | Kyno docs | https://support.lesspain.software/support/solutions/articles/12000075313-volume-settings | Large | Missing | Kyno 1.9 emphasized this for team browsing. Two-person edit shops on shared storage will notice when only the first user benefits from PurpleReel's analysis. |
| 8 | Parity gap | Combine multiple clips into one (assembly-cut without NLE) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Large | Missing | 1.4 feature. Doc shooters and corporate-video people use this to glue 8-minute talking-head pieces together without spinning up FCP. |
| 9 | Parity gap | Play-all-selected continuously | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Playback → Play All Selected; ClipDetailInline subscribes to `AVPlayerItem.didPlayToEndTime` and advances the queue. (Sprint 2) |
| 10 | Parity gap | Timecode burn-in (overlay) during transcoding | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | Convert dialog → "Burn timecode into video". `TranscodeJob.applyComposition` switches to a CIFilter-handler videoComposition that does opacity ramp + per-frame TC overlay in one pass (text rendered into a small CG context per frame, composited bottom-center). Plays nice with fades; AVFoundation-only. (Sprint 3) |
| 11 | Parity gap | Sidecar LUT auto-detection alongside media (Log-C, V-Log, S-Log presets) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | New `LUTLibraryService` walks PurpleReel's own LUT folder, every `*.fcpbundle` under ~/Movies (gated by `importLUTsFromFCP`), and the Resolve / Resolve Studio `LUT/` roots (gated by `importLUTsFromResolve`). Caches per-flag-key; rebuilds on Settings toggle change. `PlayerController.load` calls `LUTLibraryService.suggested(for:)` and auto-applies on filename-keyword match (SLog3 / V-Log / LogC / HLG / etc.). Settings → General → "Auto-apply suggested LUT on clip load" (default on). (Sprint 3) |
| 12 | Parity gap | Smart proxy presets with automatic scaling | Release notes | https://lesspain.software/kyno/pages/news/kyno-1.9-release/ | Small | Shipped | Two new ffmpeg presets — "Smart Proxy 1/2 (ProRes Proxy)" and "Smart Proxy 1/4 (ProRes Proxy)" via `scale='trunc(iw/N/2)*2':-2`. Slotted after index 9 so ⌘1..⌘0 menu shortcuts stay stable. (Sprint 2) |
| 13 | Parity gap | Incremental transcoding (skip what's already done) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | `skipExisting` was already on ConvertSheetState — verified the path; sticky via `convertSkipExisting` AppStorage. (Sprint 2 audit) |
| 14 | Parity gap | Transfer metadata between matching folder structures (copy/paste whole tree) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | File → "Transfer Metadata Between Folders…" sheet (`TransferMetadataSheet`). Match key = filename + sizeBytes; for each pair, copies clip_metadata + rating + tags (additive). Markers/subclips intentionally not copied (timecode-anchored). Preview shows match counts before commit. (Sprint 3) |
| 15 | Parity gap | Export still frame at marker (batch) with LUT baked in | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | Playback → "Export Frames at Markers…" (⌥⌘⇧E). `FrameExportService.exportFramesAtMarkers(...)` iterates `appState.markers`, writes one PNG per marker named `<base>_HHMMSS_FFf_<note-slug>.png`, with the active LUT (last-loaded via `lastLUTPath` AppStorage) baked in when `applyLUTToExportedFrames` is on. Skips collisions, reports written / skipped / failures, and reveals the folder in Finder when anything was written. Single-frame ⌘⇧E export stays as-is. (Sprint 3) |
| 16 | Parity gap | Excel/CSV report with thumbnails + duration + start TC | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | File → Export Report → CSV / HTML. `ReportExporter.writeCSV` writes 22 columns (filename, codec, resolution, display size, aspect ratio, fps, duration, size, dates, rating, log fields, channel names, tags). `ReportExporter.writeHTML` embeds the middle-frame thumbnail per row as base64 PNG — single-file deliverable. (Sprint 3) |
| 17 | Parity gap | Verified copy (offload) to up to 4 destinations simultaneously | Review article | https://www.richardlackey.com/kyno-review-media-management-for-video-creators/ | Small | Partial | PurpleReel has MHL-verified backup + SFTP. Multi-destination simultaneous offload (Hedge/Shotput baseline) is the bar; confirm/expose in Transfer pane. |
| 18 | Parity gap | "Paste & rename" workflow (paste files + apply naming template) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | File → "Paste with Rename…" (⌘⇧V) reads file URLs from NSPasteboard, picks a destination via NSOpenPanel, copies each with `BatchRenameService.expandForPaste` running URL-derived tokens (`{orig}`, `{ext}`, `{date}`, `{counter}`). Auto-skips destination collisions; kicks a workspace rescan so new files appear in the catalogue. (Sprint 3) |
| 19 | Parity gap | XMP write-back for Premiere metadata | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Large | Explicitly skipped | Out of FCP-only scope, but document. |
| 20 | Parity gap | Fade in/out option in transcoder | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Convert dialog "Fades" row (0…10 sec, 0.5-sec step). AVFoundation only via `AVMutableAudioMix` volume ramp + `AVMutableVideoComposition` opacity ramp. ffmpeg presets disabled with inline note. (`091ce79`) |
| 21 | Parity gap | Transcoder file-timestamp preservation toggle | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Settings → Conversion → "Preserve source file timestamps". Off by default; post-encode hook covers both AVFoundation + ffmpeg paths via `preserveTimestampsIfRequested()`. (Sprint 2) |
| 22 | Parity gap | Drop-frame TC: zero-based timecode preference | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | `useZeroBasedTimecode` AppStorage now read in `Timecode.format`. PurpleReel already normalizes from seconds-from-start so the flag is a no-op for the common case but is reserved for any future container-TC paths. (Sprint 2) |
| 23 | Parity gap | DMG display in Devices section (optional) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Missing | Kyno 1.5 feature. Cheap. Mounted DMG often holds delivered dailies. |
| 24 | Parity gap | Image-file Excel export for storyboarding | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | Same export path as row 16 — the HTML report embeds per-row thumbnails, so a workspace filtered to images produces a storyboard-style deliverable. (Sprint 3) |
| 26 | Parity gap | Tag negation in tag filter ("NOT tagged X") | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Partial | PurpleReel's advanced Filter supports many criteria; verify "is not"/negate is exposed on Tag specifically (Kyno added in 1.5.1 for Rating/Audio Codec/Video Codec/Pixel format/Display size/Frame rate). |
| 27 | Parity gap | Boolean expressions in filter queries | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | `filterMatchMode` AppStorage flips between AND ("all") and OR ("any"). Toggle is in Filter menu → "Combine criteria" + an inline "AND/OR" chip on the active-filter pills bar when 2+ criteria are pinned. Full parens/NOT is a follow-up; AND vs OR closes the 80/20. (Sprint 3) |
| 28 | Parity gap | VFR vs CFR filter ("variable frame rate" / "constant") | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | v5 schema adds `asset.isVFR`. MediaScanner detects via `nominalFrameRate` vs `minFrameDuration` (>10% gap = VFR). Filter → Frame Rate → "Constant (CFR) / Variable (VFR) / Unknown". Catches iPhone footage + screen recordings before they hit FCP timeline. (Sprint 3) |
| 29 | Parity gap | Spanned-clip detection (multi-file recordings auto-joined) | Kyno docs | https://lesspain.software/kyno/features/ | Large | Missing | Already on your OPEN list. C300, GH5, sony cards. Without this, drilldown shows broken segments. |
| 30 | Parity gap | Tag import/export JSON across machines | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Shipped | Shipped | Confirmed shipped per cheat sheet. No change. |
| 31 | Parity gap | Recover ratings/tags/markers after files renamed externally | Forum/Reddit post | https://support.lesspain.software/support/discussions/topics/12000027432 | Medium | Shipped | Covered by row 4's reconnect — filename+size index handles rename + move both. (Sprint 2) |
| 32 | Parity gap | Send subclips as duration markers (not just in/out points) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Partial | 1.3 feature. Verify FCPXML export uses range-based keywords vs just in/out. |
| 33 | Parity gap | Date Recorded column + Date Created column | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Both columns now surface via `ListColumn`. v4 migration added `asset.createdAt`; MediaScanner populates from `.creationDateKey`. Recorded was already in v3. (Sprint 2) |
| 34 | Parity gap | Display size + Aspect ratio columns in list view | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Display Size derives from short-edge px (4K / 1080p / 720p / …); Aspect Ratio snaps to canonical (16:9 / 4:3 / 1.85 / 2.35 / 2.39 / 1:1 / 9:16) or falls back to W.WW:1. (Sprint 2) |
| 35 | Parity gap | Correct creation/mod-date utility for files with wrong timestamps | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Missing | 1.5 feature. Niche but loved — fixes camera-clock-wrong-day disasters. |
| 36 | Behavior difference | J/L = 5-sec jumps in Kyno; PurpleReel default is multi-rate shuttle | Kyno docs | https://support.lesspain.software/support/solutions/articles/12000010141-keyboard-shortcuts | Small | Shipped | Flipped by the "Coming from Kyno" first-launch sheet — `playerJLMode` → "jump5s" when Kyno mode on. Restorable via Settings → General. (Sprint 1) |
| 37 | Behavior difference | View-mode wording: Kyno = "Thumbnail/List/Detail"; PurpleReel = "Grid/List/Detail" | Kyno docs | https://support.lesspain.software/support/solutions/articles/12000010141-keyboard-shortcuts | Small | Shipped | `useKynoTerminology` AppStorage controls "Thumbnail" vs "Grid" label in both the menu bar and toolbar segmented control. Flipped by Kyno mode. (Sprint 1) |
| 38 | Behavior difference | Cmd-Left/Right = "go to next/previous file in detail view" (Kyno) vs Back/Forward (PurpleReel ⌘[ ⌘]) | Kyno docs | https://support.lesspain.software/support/solutions/articles/12000010141-keyboard-shortcuts | Small | Shipped | ⌘← / ⌘→ wired to `selectAdjacentAsset(delta:)` in the View menu (already shipped pre-Sprint 1; verified during the Compatibility Mode audit). |
| 39 | Behavior difference | Toggle zebra = Ctrl-Alt-E in Kyno; widescreen bar = Ctrl-Alt-W | Kyno docs | https://support.lesspain.software/support/solutions/articles/12000010141-keyboard-shortcuts | Small | Shipped | Playback menu items "Toggle Zebra" (⌃⌥E) and "Cycle Widescreen Matte" (⌃⌥W). Cycle steps Off → 1.85 → 2.35 → 2.39 → Off. (Sprint 1) |
| 40 | Behavior difference | Audio mute = X key | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | `PlayerController.toggleMute()` + KeyHandler binding for "x" + Playback menu item. Always-on (not gated by Kyno mode). (Sprint 1) |
| 41 | Behavior difference | Poster-frame keyboard shortcut = P | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | v6 schema adds `asset.posterFrameSeconds`. P key (no modifier) in PlayerView captures the playhead via the `onSetPosterFrame` closure; AppState writes via `DatabaseService.setPosterFrame` and patches the in-memory `assets[idx]` + `selectedAsset` so Grid / List cells re-render. `ThumbnailService.posterFrame(for:seconds:)` generates a single frame cached by `(path, modtime, seconds)` and lives alongside the strip cache. Cells consult `asset.posterFrameSeconds` for the at-rest + hover-exit frame; hover-scrub still uses the 12-frame strip. ⇧P clears. Metadata menu surfaces both. (Sprint 3) |
| 42 | Behavior difference | Open with default app = Alt-Shift-O | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | File menu → "Open with Default App" (⌥⇧O) calls `NSWorkspace.open(...)` on the selected asset. (Sprint 1) |
| 43 | Behavior difference | Cmd-Alt-M = focus metadata input | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Metadata menu → "Focus Metadata Input" (⌘⌥M) posts `.focusMetadataInput` notification; MetadataPaneView's `@FocusState` routes to the Title field. (Sprint 1) |
| 44 | Behavior difference | Drilldown = Cmd-Shift-D | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | ⌘⇧D added as a View menu alias for "Drilldown" (Kyno binding); ⌘D stays wired too for PurpleReel-native muscle memory. (Sprint 1) |
| 45 | Behavior difference | Subclip export = Cmd-U | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Playback menu → "Export Subclip from I/O" (⌘U) posts `.saveSubclip`. Aliases the existing S keystroke. (Sprint 1) |
| 46 | Behavior difference | Add folder to workspace = Cmd-I | Kyno docs | https://support.lesspain.software/support/solutions/articles/12000010141-keyboard-shortcuts | Shipped | Shipped | Confirmed shipped per cheat sheet. Good — already matches. |
| 47 | Behavior difference | "Edit Tags" specifically bound to Cmd-Shift-T | Kyno docs | https://support.lesspain.software/support/solutions/articles/12000010141-keyboard-shortcuts | Medium | Shipped | ⌘⇧T opens `BatchTagEditorSheet` — current-tag union across multi-selection (with "partial" badges), autocomplete from `knownTagNames`, additive add / batch remove. Replaces the prior "not implemented" alert. (Sprint 3) |
| 25 | Parity gap | "Type to add tag" autocomplete in batch tag editor (⌘⇧T) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | Same sheet as row 47. Autocomplete pulls from `knownTagNames`; partial-membership badge surfaces which selection rows share a tag. |
| 48 | Behavior difference | Toolbar reorganization 1.9: Drilldown moved to main toolbar | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Shipped | Shipped | Confirmed per cheat sheet (drilldown via toolbar button). Matches Kyno's most-recent layout. |
| 49 | Behavior difference | "Show in Enclosing Folder" context action | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Partial | New in 1.9. Likely there in PurpleReel via macOS conventions; verify exact wording in context menu matches. |
| 50 | Behavior difference | Shift+click refresh = hard refresh | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Toolbar Rescan checks `NSEvent.modifierFlags.contains(.shift)`; shifted = purge every asset row first, then rescan. (Sprint 2) |
| 51 | Behavior difference | Drilldown does NOT walk into camera structures by default (1.8.1 added toggle) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | Settings → Devices → "Automatically turn on drilldown for camera media" toggle already exists; flipped to OFF by Kyno Compatibility Mode preset. (Sprint 1) |
| 52 | Behavior difference | Audio playback rate options include 75% / 125% / 150% | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Shipped | PlayerController sets `item.audioTimePitchAlgorithm = .spectral` on every load, so any rate (J/L shuttle or menu pick) preserves pitch. Playback → Speed sub-menu exposes 0.5× / 0.75× / 1× / 1.25× / 1.5× / 2× via new `PlayerCommand.setRate(Float)` → `controller.setRate(_:)`. (Sprint 3) |
| 53 | Behavior difference | "is not" negation in metadata filter values (UI affordance) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Different behavior | See row 26. Kyno surfaces this as a per-field control, not buried in advanced. Make the UI match. |
| 54 | Behavior difference | Natural file-name sorting (numeric-aware) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | `naturalFileSort` AppStorage flips `displayedAssets` comparator to `localizedStandardCompare` (`clip2` < `clip10`). Flipped on by Kyno mode; off keeps PurpleReel's original lexicographic order. (Sprint 1) |
| 55 | Behavior difference | LUT applied by default to all still-frame exports | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | `exportCurrentFrame()` bakes the active LUT into the PNG by default via a new `applyCurrentLUT(to:)` helper. Toggle in Settings → General → "Apply current LUT to exported frames". (Sprint 2) |
| 56 | Behavior difference | UI language: English, German, French, Spanish | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Large | Missing | Kyno is multilingual. PurpleReel English-only is fine for v1 but is a hidden retention factor for European DIT shops. |
| 57 | Competitive improvement | Centralized cross-volume search (no offline limit) | Review article | https://www.richardlackey.com/kyno-review-media-management-for-video-creators/ | Large | Missing | Lackey called this Kyno's biggest gap: "No offline search, no centralized database." If PurpleReel ships a lightweight library/spotlight index of unmounted volumes, that's a genuine competitive leap over Kyno. |
| 58 | Competitive improvement | AI culling: blur/eye-closure/duplicate grouping (Photo Mechanic gap) | Competitor feature | https://aftershoot.com/blog/aftershoot-vs-photo-mechanic/ | Shipped | Partial | PurpleReel ships PurpleDedup-derived similar-takes picker — already ahead of Photo Mechanic, which "has no AI culling." Market this clearly. |
| 59 | Competitive improvement | Embedded-thumbnail browsing speed (Photo Mechanic gold standard) | Competitor feature | https://shotkit.com/photo-mechanic-review/ | Shipped | Shipped | Per your PurpleDedup memory, you already cap concurrency and use embedded thumbs. Make sure the same is true in PurpleReel browse. |
| 60 | Competitive improvement | Multi-destination simultaneous offload with xxHash + ASC-MHL | Competitor feature | https://docs.hedge.video/offshoot/features/verification | Small | Partial | Hedge OffShoot is the bar. PurpleReel has MHL + verify; surface "Hedge-parity" by adding xxHash and ASC-MHL spec compliance, plus parallel writes to N targets. |
| 61 | Competitive improvement | C4 checksums + ASC-MHL Netflix spec | Competitor feature | https://docs.hedge.video/offshoot/features/verification | Medium | Shipped | `HashAlgorithm.c4` (SHA-512 → base58 with C4 alphabet, `c4`-prefixed, 90-char). New `Base58.c4ID(from:)` does big-endian division-by-58. New `ASCMHLWriter` emits v2.0 namespaced XML (`urn:ASC:MHL:v2.0`) with `<processinfo>`, root-hash rollup, attribute-on-path size + modtime. `BackupJob.mhlFormat: MHLFormat` (legacy `.mhl` v1.1 / `.ascmhl` v2.0) — Verified Backup sheet picks both with auto-flip to ASC-MHL when C4 is chosen (v1.1 has no `<c4>` element). (Sprint 3) |
| 62 | Competitive improvement | EditReady-style "transcode just a portion of a clip" (clip trimming) | Competitor feature | https://hedge.co/products/editready | Small | Partial | PurpleReel has subclips → export. Verify the transcode pipeline supports trimming to in/out by default without re-encoding the whole file. |
| 63 | Competitive improvement | Whisper transcription with searchable per-clip transcripts | Competitor feature | https://hedge.co/products/editready | Shipped | Shipped | Already shipped — push hard in marketing; Kyno doesn't have it. Genuinely category-leading. |
| 64 | Competitive improvement | Ollama local-AI tagging (privacy + no API cost) | Competitor feature | https://www.quantum.com/en/products/asset-management/ | Shipped | Shipped | CatDV's AI tagging needs a cloud service; PurpleReel's Ollama-local is a clear differentiator for editors who can't upload client footage. |
| 65 | Competitive improvement | Pomfort-grade deep camera metadata (ARRI, RED, Sony reels) | Review article | https://definitionmagazine.com/reviews/review-kyno-media-manager/ | Large | Explicitly skipped | Reviewer noted Kyno reads metadata "shallow" vs Silverstack/Resolve. Camera-specific schemas are on your skip list — note as a deliberate FCP-friendly trade-off. |
| 66 | Competitive improvement | Silverstack "workflow chains" (offload → transcode → upload → report as one job) | Competitor feature | https://pomfort.com/silverstackxt/ | Large | Missing | Power-user workflow automation. Even a simple "After offload, run preset X" hook would close this. |
| 67 | Competitive improvement | Hover-preview thumbnail scrubbing in Grid | Competitor feature | https://www.videoloupe.com/ | Medium | Shipped | GridCell now matches ThumbnailCell's list-view scrub: loads 12 frames on appear; `.onContinuousHover` maps cursor X to a frame index; tick-row overlay shows position. Photo Mechanic / Videoloupe parity. Kyno doesn't have this for the grid. |
| 68 | Competitive improvement | Live waveform audio overview in browse (Photo Mechanic for audio) | Kyno docs | https://lesspain.software/kyno/pages/faq/ | Medium | Shipped | New optional list column `ListColumn.waveform`. `WaveformInlineView` renders a `WaveformShape` per row from `WaveformService.cachedOrGenerate(...)` — disk-cached peaks keyed by `(path, modtime, bucketCount)` under `~/Library/Application Support/PurpleReel/waveforms/`. First-time generation is 1-2s per clip on a background `Task.detached`; subsequent renders are an instant JSON read. PurpleReel now leapfrogs Kyno on this — Kyno's FAQ admits they're still working on player-only waveforms. (Sprint 3) |
| 69 | Competitive improvement | Markdown notes per clip (research/journalism workflow) | Competitor feature | https://www.provideocoalition.com/nab-at-home-kyno/ | Shipped | Partial | PurpleReel has Description field and Notes tab. Promote as alternative to Kyno's notes-via-Description hack. |
| 70 | Competitive improvement | FCP X library predicate / saved-search criterion | Kyno docs | https://lesspain.software/kyno/features/ | Large | Explicitly skipped | On your skip list but flagged worth revisiting in OPEN GAPS. Letting users define a smart-filter that surfaces inside FCP would be a unique hook. |
| 71 | Annoyance to solve | Future-uncertain abandonment perception (Signiant acquisition) | Blog/news article | https://www.provideocoalition.com/an-update-on-kyno-and-what-might-be-in-store-for-the-future-of-this-fantastic-piece-of-post-production-software/ | Small | Shipped | Simmons: "I'm worried" Signiant doesn't "screw up" Kyno. PurpleReel can win these users on commitment alone — public roadmap doc + monthly changelog. |
| 72 | Annoyance to solve | Kyno forums taken offline | Blog/news article | https://www.provideocoalition.com/kyno-finally-gets-an-update/ | Small | Shipped | Simmons: "I hate that the Kyno forums were taken offline." Community vacuum — even a low-maintenance GitHub Discussions / Discord captures the orphaned community. |
| 73 | Annoyance to solve | Frame.io integration removed in 1.9 | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Medium | Explicitly skipped | Users who relied on Kyno → Frame.io are now stranded. PurpleReel could win them with SFTP delivery (already shipped) plus a Frame.io upload preset. |
| 74 | Annoyance to solve | Archiware P5 integration removed in 1.9 | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Large | Explicitly skipped | Same as above — archive workflow users orphaned. Likely too niche for PurpleReel; document as not on roadmap. |
| 75 | Annoyance to solve | "Preview window surprisingly slow even on fast SSDs" | Forum/Reddit post | https://www.dpreview.com/forums/thread/4178836 | Small | Shipped | Specific complaint about scrub speed. PurpleReel uses AVFoundation player with embedded thumbs — ensure scrub uses keyframe-only seek by default and document in benchmark. |
| 76 | Annoyance to solve | Thread leak / instability after long usage (macOS) | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Different behavior | Reported pre-1.7.4. Validate PurpleReel doesn't have similar long-session leaks; pair with Backup-on-launch (you already standardize this). |
| 77 | Annoyance to solve | Apple Silicon auto-updater still ships Intel build | Review article | https://digitalproduction.com/2025/09/19/kyno-update-still-alive-still-useful/ | Small | Shipped | Quoted: "auto-updater delivers Intel build only." PurpleReel is Swift/Apple Silicon native by definition — make this a marketing bullet. |
| 78 | Annoyance to solve | "Maximum number of files exceeded" security limit | Kyno docs | https://lesspain.software/kyno/pages/faq/ | Small | Shipped | `fileCountSafetyLimit` AppStorage (default 50,000) drives a soft alert when a rescan crosses the threshold. Catalogue still loads — non-blocking, unlike Kyno. Stepper in Settings → Advanced. (Sprint 2) |
| 79 | Annoyance to solve | macOS permission denials (Removable Volumes, Files & Folders) | Kyno docs | https://lesspain.software/kyno/pages/faq/ | Medium | Shipped | `PermissionsWizardSheet` runs once on first launch (gated `permissionsWizardShown`) and re-opens via Help → "Re-check Privacy & Security…". `PermissionsCheck.run()` probes ~/Movies, ~/Downloads, ~/Documents, and /private/var/db to detect Files-and-Folders / Full Disk Access; rows have "Grant…" buttons that open the right System Settings sub-pane. Removable + Network Volumes get informational rows. (Sprint 3) |
| 80 | Annoyance to solve | Metadata stored as sidecar XML files in hidden dirs (`/.LP_Store/`, `.kyno/`) | Kyno docs | https://lesspain.software/kyno/pages/faq/ | Medium | Shipped | Metadata menu → "Import from Kyno (.LP_Store)…". `KynoImportService.importTree(root:db:)` recursively walks the chosen root for `.LP_Store/` + `.kyno/` XMLs, parses them with a permissive `XMLParserDelegate` (accepts the schema-drift synonyms — `<asset>`/`<clip>`/`<file>`, `<rating>`/`<stars>`, `<tag>`/`<keyword>`, etc.), and merges into clip_metadata + ratings + tags + markers for filename-matched catalogue assets. Reports matched / applied / skipped + unmatched filename samples; tip prompts a rescan when filenames don't resolve. PurpleReel still keeps its centralized SQLite store — this is a one-way migration ingest. (Sprint 3) |
| 81 | Annoyance to solve | License: 2 machines per single user, yearly renewal for updates | Kyno docs | https://lesspain.software/kyno/pages/faq/ | Small | Different behavior | Kyno is €159/yr renewal-for-updates. PurpleReel's licensing model is your competitive lever — if perpetual or one-time, lead with it. |
| 82 | Annoyance to solve | "Disconnect drive before importing metadata XML" workaround | Forum/Reddit post | https://support.lesspain.software/support/discussions/topics/12000027432 | Large | Missing | Bizarre Kyno quirk users had to discover. PurpleReel's metadata import (when built — see row 5) should not require this. |
| 83 | Annoyance to solve | Subclip overwrite collisions on identical names | Release notes | https://support.lesspain.software/support/solutions/articles/12000016005-release-notes-for-kyno | Small | Shipped | `uniqueSubclipName(base:on:)` auto-appends " 2", " 3", … on collision per asset; no silent overwrites. (Sprint 2) |
| 84 | Annoyance to solve | Audio channel names ("boom"/"lav") not preserved | Forum/Reddit post | https://lesspain.software/kyno/features/ | Small | Shipped | `clip_metadata.audioChannelNames` (v4) + Audio Channels field in MetadataPaneView. Comma-separated list ("boom, lav-Alice, lav-Bob"); commits on Return / focus loss. (Sprint 3) |
| 85 | Annoyance to solve | Default list-view columns not configurable as global default | Forum/Reddit post | https://support.lesspain.software/support/discussions/topics/12000026375 | Shipped | Shipped | PurpleReel already exposes column choice. Document "save as default columns" prominently. |

---

## Top 5 highest-impact

1. **Row 4 (Find Lost Metadata) + Row 31 (rename recovery)** — single
   biggest emotional safety net for Kyno migrants; without it they
   will lose tags during their first reorganization and abandon ship.
2. **Row 36 (J/L 5-sec default)** — you have the toggle; a "Coming
   from Kyno" first-launch preset eliminates the most universal
   complaint about converting NLE-shortcut users.
3. **Row 5 + Row 6 (FCPXML re-import + clip-to-clip Paste
   Metadata)** — Kyno's flagship round-trip story. Without it,
   PurpleReel is one-way and editors lose all the logging their AE
   did downstream.
4. **Row 7 (shared cache on NAS/SAN)** — every multi-seat shop hits
   this within a week. Kyno made it the headline of 1.9 specifically
   because team browsing on shared storage is where they were
   losing customers.
5. **Row 71 + 77 (Signiant abandonment perception + Apple Silicon
   native)** — pure marketing lever. PurpleReel can win lapsed Kyno
   users on commitment + native-ARM alone; ship a public roadmap
   and a "why we exist" page that names Kyno directly.

---

## Next steps

- **Triage**: walk the table and decide what goes into the Small /
  Medium / Large effort buckets in
  [`KYNO_PARITY_ROADMAP.md`](KYNO_PARITY_ROADMAP.md).
- **Verify behavior-difference rows**: the "verify in PurpleReel"
  flags (rows 26, 32, 49, 51, 52, 54) need an actual check against
  the running app before they're closed or scheduled.
- **First-launch "Coming from Kyno" preset**: one screen / one
  toggle flips J/L, key bindings, view-mode labels, drilldown
  shortcut, etc. — a near-zero-cost retention multiplier.
