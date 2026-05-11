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
./run-tests.sh        # runs the PurpleLifeTests bundle (59 tests, ~17 s end-to-end)
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

In rough priority order:

1. **First-launch sync bootstrap UX** — Mac B's first sign-in hung at "Setting up sync…" for ~5 min silently before resolving (during the 2026-05-10 verification trial). Either add per-step timeout-and-retry with surfaced progress, or break out the status badge sub-states ("Checking iCloud…" / "Creating zone…" / "Pulling…") so a user can tell whether to wait or kill it.
2. **Deeper "client went away" investigation** — soft-recovery patch (commit `68b1bba`) treats the symptom by re-creating the `CKContainer` on the specific error string. The root cause (cloudd dropping our process binding after a successful subscription delivery + fetch round-trip) is unsolved. If the soft recovery proves insufficient over real use, longer-lived `CKDatabase` references / less Task hopping in the subscription handler / a custom operation queue are worth investigating.
3. **WeightTracker subsumption (deferred)** — explicit decision 2026-05-10. WeightTracker still works as a standalone app; subsumption is additive polish. When picked up, the natural first slice is the right-rail weight sparkline + a basic line chart for the Weight type. See [HANDOFF.md](HANDOFF.md) for the full reasoning.
