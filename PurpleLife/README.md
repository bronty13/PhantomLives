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
| 4 — CloudKit E2E sync | **Acceptance gate met** — push on mutation, real-time `CKDatabaseSubscription` silent-push wakeups, 5 min recovery poll, LWW reconciliation, sidebar status footer. **<5 s Mac→Mac latency verified PASS 2026-05-10** (changes were near-instant in both directions during the trial; see [HANDOFF.md](HANDOFF.md)). |
| 5 — First real use cases | **Starter shipped** — real attachments, gallery loads images, WeightTracker CSV import. Daily-use 2-week trial pending. |

See [PLAN.md](PLAN.md) for the build plan, [HANDOFF.md](HANDOFF.md) for the decision log, and [USER_MANUAL.md](USER_MANUAL.md) for what each screen does.

## Build

```sh
./build-app.sh        # produces ./PurpleLife.app, Apple-Development-signed with iCloud entitlement
./run-tests.sh        # runs the PurpleLifeTests bundle (88 tests, ~17 s end-to-end)
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
| `~/Downloads/PurpleLife/` | Per-type exports — CSV / Markdown / HTML / PDF (default; user-overridable in Settings → Export) |

## Follow-up work

_All queued follow-ups are closed as of 2026-05-11._ See HANDOFF.md for per-item rationale and what was skipped on purpose (XLSX/DOCX exports, additional chart styles, CloudKit-synced theme preferences).

Recently closed:

- ~~**Appearance theming · slice 3**~~ — JSON theme import/export (`.purplelifetheme.json` files via NSSavePanel/NSOpenPanel; right-click Export on every theme card, Import in the Custom themes section, Export in the builder footer). Shipped 2026-05-11.
- ~~**Appearance theming · slice 2**~~ — WYSIWYG theme builder (Light/Dark ColorPickers side-by-side per slot, live preview pane with its own appearance toggle, Save / Save As / Delete with `basedOn` fallback when deleting an active theme). Shipped 2026-05-11.
- ~~**Appearance theming · slice 1**~~ — 5 purple-rooted built-in themes (Royal Purple default, Lavender, Plum, Heather, High Contrast) + Light/Dark/Auto appearance picker. Reverses the prior "themes deferred" decision on accessibility grounds; see HANDOFF entry from 2026-05-11.
- ~~**WeightTracker subsumption**~~ — 5 slices shipped 2026-05-10. PurpleLife now covers Weight tracking end-to-end: rail sparkline matching the prototype, dedicated Charts view kind with Trend/7d-avg/Goal overlays, full Statistics panel (BMI / regression / forecast / days-to-goal), Smart Import wizard (free-form text parser), and the existing CSV importer + multi-format export. WeightTracker can be retired.
- ~~**First-launch sync bootstrap UX**~~ — bootstrap sub-states surfaced in the sync footer 2026-05-10 (commit `8c2adb8`). The footer now reads "Checking iCloud account…" / "Setting up CloudKit zone…" / "Registering for push notifications…" / "Pulling existing data…" / "Pushing local changes…" / "Synced" so a user can tell which step is in flight.
- ~~**Deeper "client went away" investigation**~~ — App Nap is the most likely root cause (the symptoms match exactly). `CloudKitSyncService.start` now holds a `ProcessInfo.beginActivity` assertion for the lifetime of the service. If "client went away" still surfaces over real use, longer-lived `CKDatabase` references / less Task hopping in the subscription handler / a custom operation queue are the next investigation rungs.
