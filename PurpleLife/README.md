# PurpleLife

A native macOS "Life OS" — one app for planner, hobbies (WoW, photography), extended contacts, reading log, and weight, organized as configurable object types with relations. Data lives in CloudKit, end-to-end encrypted with keys the user controls (`CKRecord.encryptedValues`), mirrored across the user's Macs. Restorable backups land in `~/Downloads/PurpleLife backup/`.

Part of the **PhantomLives** family of personal macOS apps (Timeliner, PurpleTracker, PurpleIRC, PurpleDedup, WeightTracker).

## Status — end of initial build session

All five planned phases shipped through a working state. Real-world daily-use trial (Phase 5) and a couple of follow-up improvements remain.

| Phase | Status |
|---|---|
| 0 — Tap Forms trial | Skipped 2026-05-10 — see [HANDOFF.md](HANDOFF.md) |
| CloudKit spike | **PASS 2026-05-10** ([Spike/CloudKit/SPIKE.md](Spike/CloudKit/SPIKE.md)) — `encryptedValues` round-trip confirmed against `iCloud.com.bronty13.PurpleLife` |
| 1 — Foundation | **Complete** — backup-on-launch + restore round-trip green; Settings → Backup pane wired. |
| 2 — Object engine + 4 views | **Acceptance gate met** — schema registry, table/kanban/calendar/gallery, schema editor, object detail, FTS5 + ⌘K, cross-type link picker. |
| 3 — Today / Planner | **Acceptance gate met** — saved-queries pattern, Today screen, customization UI, Planner Item + Weight built-in types. |
| 4 — CloudKit E2E sync | **Starter shipped** — push on mutation + 30 s poll, LWW reconciliation, sidebar status footer. Real-time silent-push subscriptions queued. |
| 5 — First real use cases | **Starter shipped** — real attachments, gallery loads images, WeightTracker CSV import. Daily-use 2-week trial pending. |

See [PLAN.md](PLAN.md) for the build plan, [HANDOFF.md](HANDOFF.md) for the decision log, and [USER_MANUAL.md](USER_MANUAL.md) for what each screen does.

## Build

```sh
./build-app.sh        # produces ./PurpleLife.app, Apple-Development-signed with iCloud entitlement
./run-tests.sh        # runs the PurpleLifeTests bundle (34 tests, ~19 s end-to-end)
```

Both scripts require **full Xcode** (not just Command Line Tools), `xcodegen` (`brew install xcodegen`), and an Apple Developer account signed in to Xcode. Phase 4's CloudKit entitlement makes Apple Development signing mandatory; the build-script's prior Developer ID Application path was retired.

## Run the CloudKit spike (separate target)

```sh
cd Spike/CloudKit
./build-spike.sh
open CloudKitSpike.app
```

Prerequisites + PASS log are in [Spike/CloudKit/SPIKE.md](Spike/CloudKit/SPIKE.md).

## Where things live

| Location | Purpose |
|---|---|
| `~/Library/Application Support/PurpleLife/` | DB (`purplelife.sqlite`), `settings.json`, `schema.json`, `attachments/` |
| `~/Downloads/PurpleLife backup/` | Auto-backup zips (default; user-overridable) |
| `~/Downloads/PurpleLife/` | User-visible exports and reports (default; user-overridable — exporter queued) |

## Follow-up work

In rough priority order:

1. **Real-time CloudKit subscriptions** — replace the 30 s poll with silent-push wakeups (needs `aps-environment` + an `NSApplicationDelegateAdaptor`). Clears the Phase 4 <5 s gate functionally.
2. **Export pipeline** — copy Timeliner's `ExportService.swift` (CSV / Markdown / PDF / clipboard).
3. **Schema versioning across synced peers** — sketched as a `HANDOFF.md` open item; pre-Phase-4 work that never landed.
4. **Daily-use ergonomics** — quick-capture menu bar item, keyboard shortcuts, undo.
5. **Polish toward the prototype** — Today timeline + linked-from rail, two-pane object detail, drag-and-drop schema editor.
