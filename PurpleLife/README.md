# PurpleLife

A native macOS "Life OS" — one app for planner, hobbies (WoW, photography), extended contacts, reading log, and weight, organized as configurable object types with relations. Data lives in CloudKit, end-to-end encrypted with keys the user controls (`CKRecord.encryptedValues`), mirrored across the user's Macs. Daily restorable backups land in `~/Downloads/PurpleLife backup/`.

Part of the **PhantomLives** family of personal macOS apps (Timeliner, PurpleTracker, PurpleIRC, PurpleDedup, WeightTracker).

## Status

Phase 1 (Foundation) — scaffold complete.

| Phase | Status |
|---|---|
| 0 — Tap Forms trial | Skipped 2026-05-10 — see [HANDOFF.md](HANDOFF.md) |
| CloudKit spike | **PASS 2026-05-10** ([Spike/CloudKit/SPIKE.md](Spike/CloudKit/SPIKE.md)) — `encryptedValues` round-trip confirmed against `iCloud.com.bronty13.PurpleLife` |
| 1 — Foundation | Complete — round-trip + 4 backup tests green; Settings → Backup pane wired |
| 2 — Object engine + 4 views | Acceptance gate met — schema registry, four list views (table/kanban/calendar/gallery), schema editor, object detail, FTS5 + ⌘K, cross-type link picker. Visual review against the design handoff is the remaining gate item. |
| 3 — Today / Planner | Acceptance gate met — saved-queries pattern, Today screen, customization UI, Planner Item + Weight built-in types. |
| 4 — CloudKit E2E sync | Not started |
| 5 — First real use cases | Not started |

See [PLAN.md](PLAN.md) for the build plan and [HANDOFF.md](HANDOFF.md) for the decision log.

## Build

```sh
./build-app.sh        # produces ./PurpleLife.app
./run-tests.sh        # runs the PurpleLifeTests bundle
```

Both scripts require **full Xcode** (not just Command Line Tools) and `xcodegen` (`brew install xcodegen`).

## Run the CloudKit spike (separate)

```sh
cd Spike/CloudKit
./build-spike.sh
open CloudKitSpike.app
```

Prerequisites and PASS criteria are in [Spike/CloudKit/SPIKE.md](Spike/CloudKit/SPIKE.md).

## Where things live

| Location | Purpose |
|---|---|
| `~/Library/Application Support/PurpleLife/` | DB (`purplelife.sqlite`), `settings.json`, attachments |
| `~/Downloads/PurpleLife backup/` | Auto-backup zips (default; user-overridable) |
| `~/Downloads/PurpleLife/` | User-visible exports and reports (default; user-overridable) |
