# MasterClipper

A native macOS SwiftUI app for tracking video clip metadata through Production → Post-Production → Delivery. Personal-use, fully local (no cloud), with hand-rolled XLSX import / export, local-LLM description refinement via Ollama, calendar generation, posting workflow, and rich exports.

## Features

- **Workflow pipeline** — auto-derived status: `new` → `editing` → `to_post` → `posting` → `production`. Transitions happen automatically when editing fields are filled or postings are toggled.
- **New Clip workflow** — single sheet (⌘N) captures identity (persona / title / content date — *all three required to save*), optional metadata (description, ordered categories, go-live date, notes), and the source folder in one pass. The folder picker enumerates every `.mov` with microsecond-precision creation timestamps, flags files whose name doesn't match its 1-based chronological position, and offers a one-click **Fix order** rename that renumbers them 1.mov / 2.mov / … via a collision-free two-phase rename. Save & Close auto-hashes every `.mov` (MD5 / SHA-1 / SHA-256, streamed in one pass) and persists per-segment metadata as `clip_segments` rows the editor can browse, refresh, and recapture later. **Copy Status to Clipboard** button drops a `<id> - <title> [<persona>] / Description / Categories / Go-live date` block ready to paste anywhere.
- **Editing workflow** — chained from the new-clip sheet's **Save & Continue to Editing →** button (also reachable for any clip from the Clips toolbar). Read-only file-audit summary at the top, with a one-click hand-off to the full audit sheet for the action pills, and an editing-notes textarea below that appends to `clip.notes` as `[Editing YYYY-MM-DD] <text>`. The notes timeline reads as one chronology across creation (`[New clip …]`), editing (`[Editing …]`), and posting (`[Posted <site> …]`) — no separate audit-log table.
- **Editing Queue + Posting Queue** — paired master/detail views. Editing Queue focuses on `new / editing / to_post`, Posting Queue on `to_post / posting`. Per-clip progress indicators, persona filter, every column sortable, count badges in the sidebar.
- **Verify files** — per-clip 9-point file audit (FCP folder, Production folder, Main MP4, Reduced MP4, Thumbnail frames, FCP bundle, Description, Video transcription, File hashes). Inline action pills on each row to fix problems in place: Choose folder, rename closest match, push from FCP, reduce, capture, generate transcript, pick thumbnail, compute hashes. The **Production folder** row gets a one-click *Create + copy from FCP* pill that mkdir-p's `<base>/<contentDate>/`, copies the best-match MP4 from FCP into it as `Title.<ext>`, and stamps `clip.productionFolder` + `clip.clipFilename` in one save. Bulk **Stamp N missing production folders** action in the file-verification workflow does it across the whole queue.
- **Bulk file-verification workflow** — toolbar button on either queue walks every visible clip through the audit one at a time. Toggle between *all clips* and *only with issues*; Skip / Previous / Next; summary at the end with click-through to clips still needing work.
- **Local AV pipeline** — `AVAssetExportSession` for re-encoding over-threshold MP4s into `<Title>_reduced.mp4` (HEVC at source res, falls back through 1080p / 720p / 540p H.264). `AVAssetImageGenerator` for capturing N thumbnail frames. Visual frame picker — clicking a tile promotes it to canonical `<Title>.png` and remembers the choice.
- **Whisper transcription** via the sibling `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` (MLX). Stored on the clip as a single continuous paragraph; editable; persisted on save.
- **File-integrity hashes** — MD5 / SHA-1 / SHA-256 streamed in 4 MB chunks for both the main and reduced MP4. Surfaced in the editor's Integrity section (click-to-copy) and as an audit row.
- **Smart Import wizard** — XLSX / CSV / TSV / pasted text. Auto-routes sheets, fuzzy-matches column headers, cleans voice-transcribed categories, normalises personas, supports a "Treat as historical" toggle that bulk-marks every persona-scope site as posted.
- **Ollama refinement** — strict word-for-word proofreading prompt (spelling / punctuation / grammar only) at temperature 0. Streamed into the refined description field. Auto-detects the installed model on launch.
- **Site × persona posting batches** — Clips4Sale [CoC] and Clips4Sale [PoA] run as separate batches with their own login flows. Each clip opens a focused, persona-coloured window with title / production path / hashes pinned at the top, editable price + categories, **Skip for now**, **Show queue list** (bulk-upload helper), and Mark posted gated on the price being set. Posting notes mirror back into `clip.notes` so the editor surfaces every posting context together.
- **Single-clip posting** — the same focused posting window is reachable without the batch wizard: **POST** in the top-right action bar (Clips / Editing / Posting Queue), the per-row **Post…** button in the clip editor's Posting status section (skips the picker — pre-targets that site), or right-click → **Post this clip…** in any of the three tables. Picks a scoped site first, then cycles through the clip's remaining un-posted sites on **Posted & next**.
- **Per-clip "do not post" flag** — mark any clip as excluded from posting, with a reason picked from a configurable dropdown (Settings → Posting). Excluded clips auto-promote to `production` (no point in any other status when there's nothing to post) and are filtered out of every posting batch and the Posting Queue.
- **Click-to-copy clip IDs** everywhere they're shown — Clips list, Editing / Posting Queues, posting batch rows, editor sticky header, posting window header, audit clip banner.
- **C4S Historical snapshot** — separate sidebar section + `c4s_historical` table that holds the most recent on-demand Clips4Sale storefront export per store (CoC + PoA). Importer accepts both the `.xlsx` and the pipe-delimited `.csv` export, auto-pre-selects the store from filename prefixes, and replaces all rows for the chosen store inside one transaction. Browse with a sortable table + per-row detail panel; search across title / description / keywords / categories / clip-id / performers.
- **Calendar** — Year / Quarter / Month / Week / Day. Auto-populates from clip `goLiveDate`s (no manual link step), generates blank slots from per-persona × weekday rules.
- **Persona-coloured everything** — gradient pills with heart icons "light up" each clip's persona across the list, sidebar, calendar dots, and editor sticky header. Colours are user-editable via `ColorPicker`.
- **Capture history** — every field-level change to a clip lands in `clip_history`. Browse from the clip editor.
- **Clip audit** — seven-point metadata checklist (ID / persona / title / refined description / categories / content date / go-live date). Live banner in the clip editor; bulk report under Reports.
- **Reports with per-report exports** — Full Clip / Weekly / Posting Status / Category Usage / Calendar Rollup / Clip Audit / **Information Needed** each get their own MD / PDF / CSV export menu with auto-reveal in Finder. *Information Needed* lists every `new` / `editing` clip missing description / categories / go-live, with a one-click **Copy for creator** payload prefixed with "Please confirm/provide the following:".
- **Historical-clip category backfill** — once a C4S Historical snapshot is imported, a planner sheet matches production clips that have no categories against the snapshot by title (with `FuzzyMatch.normalize` so apostrophe / comma drift counts as exact). Per-row checkboxes across exact / strong-fuzzy / maybe-fuzzy / cannot-match buckets; commit applies the matched C4S row's `categories + keywords` (in that order, deduped, position-preserved) inside one transaction.
- **Category cleanup** — *Settings → Categories → Archive unused (N)…* archives every category not currently attached to a clip. Reversible — `ensureCategory` un-archives on re-use, so future imports / backfills automatically reactivate any category that gets re-attached.
- **Path defaults + one-shot backfill** — Settings → File Locations configures Production base + pattern (`~/Dropbox/Sallie Content/Clips`, `{date} {title}`) and FCP base + pattern (`/Volumes/PRO-G40/`, `Content Working/{date} Session/{title}`). Backfill populates path columns for all Production-status clips on first launch.
- **Backup + restore** — auto-zip on launch, retention trimming, Test (extract + verify migrations + row counts), Restore (safety backup → unzip → reopen pool → reload).
- **Auto-save** — pending clip edits flush on view disappear (selection change, sidebar nav, window close).
- **Light / Dark / System** appearance toggle.
- **Exports** — CSV / Markdown / XLSX / DOCX / PDF / mobile-friendly HTML. Per-clip plain-text / Markdown / PDF for sharing.
- **iOS companion app** (universal iPhone + iPad) — browse, search (FTS5), filter, and view clip detail on your phone. Mac publishes a read-only SQLite snapshot + thumbnails + manifest into iCloud Drive on a 30s-debounced timer after each change; iOS reads from that snapshot, never from your live database. Light edits (mark posted / unmark / add note / set status / toggle exclusion) flow back to the Mac as JSON intent envelopes in iCloud. Background refresh keeps the cache warm so the next launch is instant.
- **Time-limited external shares (CloudKit)** — bundle a chosen subset of clips into a CKShare with View-only or View+edit permission and an expiry (24h / 7d / 30d / custom). Recipient accepts the participation URL on their own Apple ID + the MasterClipper iOS app; they see the clips in a Shared tab without ever touching your iCloud Drive. Auto-revoke at expiry; read-write recipients' edits sync back through the same `apply(intent:)` path the personal iOS app uses.

## Quickstart

```bash
cd ~/Documents/GitHub/PhantomLives/MasterClipper
xcodegen generate     # one-time when project.yml changes
./build-app.sh        # produces MasterClipper.app, signs with Developer ID if available
open MasterClipper.app
```

`build-app.sh` will fall back to ad-hoc signing if no Developer ID is available, and uses `/Applications/Xcode.app/Contents/Developer` automatically if `xcode-select` points at Command Line Tools.

## Default file locations

| What | Where |
|---|---|
| SQLite database | `~/Library/Application Support/MasterClipper/masterclipper.sqlite` |
| Settings | `~/Library/Application Support/MasterClipper/settings.json` |
| Auto-backups | `~/Downloads/MasterClipper backup/MasterClipper-YYYY-MM-dd-HHmmss.zip` |
| Exports | `~/Downloads/MasterClipper/` |

All paths are user-overridable in **Settings → Backup** and **Settings → Import / Export**.

## Stack

- Swift 5.10, SwiftUI, macOS 14+, iOS 17+
- XcodeGen → `MasterClipper.xcodeproj` (two targets: `MasterClipper` macOS app, `MasterClipperiOS` universal iOS app)
- `MasterClipperCore` SPM package shared between both targets — models, search, query helpers, intent envelope, CK share schema
- GRDB.swift 6 (SQLite, append-only `DatabaseMigrator`, FTS5 on the iOS snapshot)
- CloudKit for time-limited external shares (private DB zones + CKShare anchored on a metadata record; `CKFetchRecordZoneChangesOperation` for enumeration, no CKQuery)
- iCloud Documents for the personal Mac↔iOS snapshot transport (`NSFileCoordinator` + `NSMetadataQuery`)
- No other external Swift packages — XLSX reading and OOXML writing are hand-rolled over `/usr/bin/unzip` / `/usr/bin/zip`, PDF via `CGContext(consumer:)`, MP4 re-encode via `AVAssetExportSession`, frame capture via `AVAssetImageGenerator`, file hashes via `CryptoKit`
- Ollama (local LLM) for description refinement — auto-detected at `/opt/homebrew/bin/ollama` etc.
- Sibling `~/Documents/GitHub/PhantomLives/transcribe/` (MLX Whisper) used for video transcripts via `Process` + stdout capture. Optional — the **Generate transcript** button is disabled with a hint when the script isn't installed.

## Companion apps

The same Xcode project ships a universal **iPhone / iPad** app via the `MasterClipperiOS` scheme. Sign with your Apple Developer team, pair an iPhone/iPad signed into the same iCloud account, and Run. The iOS app gets the same icon as the Mac app.

| Concern | macOS | iOS |
|---|---|---|
| Source of truth | live SQLite at `~/Library/Application Support/MasterClipper/` | read-only snapshot copied from iCloud into the app sandbox |
| When to enable | always on | turn on **Settings → Sync → Publish snapshot to iCloud** on the Mac |
| Search | in-memory + click filters | FTS5 (BM25-ranked, prefix-matched) baked into the snapshot |
| Edits | direct | sent as JSON intent envelopes in `iCloud/Documents/intents/pending/`; Mac polls and applies via `DatabaseService.apply(intent:)` |
| Background sync | n/a | `BGAppRefreshTask` keeps the cache warm |

External sharing flow: **Settings → Sync → External shares → Create share…**. Pick clips, permission, expiry, optional label. Send the participation URL to a recipient. Their iOS app gets a Shared tab; auto-revoke fires at the expiration time.

## Documentation

- `USER_MANUAL.md` — feature tour with the full UI surface
- `INSTALL.md` — build / install / first-run
- `HANDOFF.md` — architecture handoff for future maintainers
- `CHANGELOG.md` — per-feature change log

## Status

Production. The clip pipeline, posting workflow, calendar, exports, backup / restore, and import wizard are all live. Tested end-to-end against a real 851-clip historical import and a 26-clip new-work import.
