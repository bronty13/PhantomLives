# MasterClipper

A native macOS SwiftUI app for tracking video clip metadata through Production → Post-Production → Delivery. Personal-use, fully local (no cloud), with hand-rolled XLSX import / export, local-LLM description refinement via Ollama, calendar generation, posting workflow, and rich exports.

## Features

- **Workflow pipeline** — auto-derived status: `new` → `editing` → `to_post` → `posting` → `production`. Transitions happen automatically when editing fields are filled or postings are toggled.
- **Editing Queue** — focused master/detail view of clips not yet posted. Per-row indicators for FCP project folder / production folder / length progress.
- **Smart Import wizard** — XLSX / CSV / TSV / pasted text. Auto-routes sheets, fuzzy-matches column headers, cleans voice-transcribed categories, normalises personas, supports a "Treat as historical" toggle that bulk-marks every persona-scope site as posted.
- **Ollama refinement** — strict word-for-word proofreading prompt (spelling / punctuation / grammar only) at temperature 0. Streamed into the refined description field. Auto-detects the installed model on launch.
- **Site × persona posting batches** — Clips4Sale [CoC] and Clips4Sale [PoA] run as separate batches with their own login flows. Each clip opens a focused window with per-field copy buttons.
- **Calendar** — Year / Quarter / Month / Week / Day. Auto-populates from clip `goLiveDate`s (no manual link step), generates blank slots from per-persona × weekday rules.
- **Persona-coloured everything** — gradient pills with heart icons "light up" each clip's persona across the list, sidebar, calendar dots, and editor sticky header. Colours are user-editable via `ColorPicker`.
- **Capture history** — every field-level change to a clip lands in `clip_history`. Browse from the clip editor.
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
- No other external Swift packages — XLSX reading and OOXML writing are hand-rolled over `/usr/bin/unzip` / `/usr/bin/zip`, PDF via `CGContext(consumer:)`
- Ollama (local LLM) for description refinement — auto-detected at `/opt/homebrew/bin/ollama` etc.

## Documentation

- `USER_MANUAL.md` — feature tour with the full UI surface
- `INSTALL.md` — build / install / first-run
- `HANDOFF.md` — architecture handoff for future maintainers
- `CHANGELOG.md` — per-feature change log

## Status

Production. The clip pipeline, posting workflow, calendar, exports, backup / restore, and import wizard are all live. Tested end-to-end against a real 851-clip historical import and a 26-clip new-work import.
