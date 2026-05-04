# MasterClipper

A native macOS SwiftUI app for tracking video clip metadata through Production → Post-Production → Delivery. Personal-use, fully local (no cloud), with hand-rolled XLSX import / export, local-LLM description refinement via Ollama, calendar generation, posting workflow, and rich exports.

## Features

- **Workflow pipeline** — auto-derived status: `new` → `editing` → `to_post` → `posting` → `production`. Transitions happen automatically when editing fields are filled or postings are toggled.
- **Editing Queue + Posting Queue** — paired master/detail views. Editing Queue focuses on `new / editing / to_post`, Posting Queue on `to_post / posting`. Per-clip progress indicators, persona filter, every column sortable, count badges in the sidebar.
- **Verify files** — per-clip 9-point file audit (FCP folder, Production folder, Main MP4, Reduced MP4, Thumbnail frames, FCP bundle, Description, Video transcription, File hashes). Inline action pills on each row to fix problems in place: Choose folder, rename closest match, push from FCP, reduce, capture, generate transcript, pick thumbnail, compute hashes.
- **Bulk file-verification workflow** — toolbar button on either queue walks every visible clip through the audit one at a time. Toggle between *all clips* and *only with issues*; Skip / Previous / Next; summary at the end with click-through to clips still needing work.
- **Local AV pipeline** — `AVAssetExportSession` for re-encoding over-threshold MP4s into `<Title>_reduced.mp4` (HEVC at source res, falls back through 1080p / 720p / 540p H.264). `AVAssetImageGenerator` for capturing N thumbnail frames. Visual frame picker — clicking a tile promotes it to canonical `<Title>.png` and remembers the choice.
- **Whisper transcription** via the sibling `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` (MLX). Stored on the clip as a single continuous paragraph; editable; persisted on save.
- **File-integrity hashes** — MD5 / SHA-1 / SHA-256 streamed in 4 MB chunks for both the main and reduced MP4. Surfaced in the editor's Integrity section (click-to-copy) and as an audit row.
- **Smart Import wizard** — XLSX / CSV / TSV / pasted text. Auto-routes sheets, fuzzy-matches column headers, cleans voice-transcribed categories, normalises personas, supports a "Treat as historical" toggle that bulk-marks every persona-scope site as posted.
- **Ollama refinement** — strict word-for-word proofreading prompt (spelling / punctuation / grammar only) at temperature 0. Streamed into the refined description field. Auto-detects the installed model on launch.
- **Site × persona posting batches** — Clips4Sale [CoC] and Clips4Sale [PoA] run as separate batches with their own login flows. Each clip opens a focused window with per-field copy buttons.
- **Calendar** — Year / Quarter / Month / Week / Day. Auto-populates from clip `goLiveDate`s (no manual link step), generates blank slots from per-persona × weekday rules.
- **Persona-coloured everything** — gradient pills with heart icons "light up" each clip's persona across the list, sidebar, calendar dots, and editor sticky header. Colours are user-editable via `ColorPicker`.
- **Capture history** — every field-level change to a clip lands in `clip_history`. Browse from the clip editor.
- **Clip audit** — seven-point metadata checklist (ID / persona / title / refined description / categories / content date / go-live date). Live banner in the clip editor; bulk report under Reports.
- **Reports with per-report exports** — Full Clip / Weekly / Posting Status / Category Usage / Calendar Rollup / Clip Audit each get their own MD / PDF / CSV export menu with auto-reveal in Finder.
- **Path defaults + one-shot backfill** — Settings → File Locations configures Production base + pattern (`~/Dropbox/Sallie Content/Clips`, `{date} {title}`) and FCP base + pattern (`/Volumes/PRO-G40/`, `Content Working/{date} Session/{title}`). Backfill populates path columns for all Production-status clips on first launch.
- **Backup + restore** — auto-zip on launch, retention trimming, Test (extract + verify migrations + row counts), Restore (safety backup → unzip → reopen pool → reload).
- **Auto-save** — pending clip edits flush on view disappear (selection change, sidebar nav, window close).
- **Light / Dark / System** appearance toggle.
- **Exports** — CSV / Markdown / XLSX / DOCX / PDF / mobile-friendly HTML. Per-clip plain-text / Markdown / PDF for sharing.

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

- Swift 5.10, SwiftUI, macOS 14+
- XcodeGen → `MasterClipper.xcodeproj`
- GRDB.swift 6 (SQLite, append-only `DatabaseMigrator`)
- No other external Swift packages — XLSX reading and OOXML writing are hand-rolled over `/usr/bin/unzip` / `/usr/bin/zip`, PDF via `CGContext(consumer:)`, MP4 re-encode via `AVAssetExportSession`, frame capture via `AVAssetImageGenerator`, file hashes via `CryptoKit`
- Ollama (local LLM) for description refinement — auto-detected at `/opt/homebrew/bin/ollama` etc.
- Sibling `~/Documents/GitHub/PhantomLives/transcribe/` (MLX Whisper) used for video transcripts via `Process` + stdout capture. Optional — the **Generate transcript** button is disabled with a hint when the script isn't installed.

## Documentation

- `USER_MANUAL.md` — feature tour with the full UI surface
- `INSTALL.md` — build / install / first-run
- `HANDOFF.md` — architecture handoff for future maintainers
- `CHANGELOG.md` — per-feature change log

## Status

Production. The clip pipeline, posting workflow, calendar, exports, backup / restore, and import wizard are all live. Tested end-to-end against a real 851-clip historical import and a 26-clip new-work import.
