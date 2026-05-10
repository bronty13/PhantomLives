# PurpleLife — HANDOFF

The durable log of decisions and design-handoff deviations for PurpleLife. Append-only; do not rewrite history. Newest entries at the top.

## How to use this file

- **Decisions**: every locked decision that overrides or amends `PLAN.md` is recorded here with a date and one-line rationale.
- **Design deviations**: any deliberate divergence from `~/Downloads/PurpleLife-handoff.zip` (the visual design source of truth) is recorded here with a one-line reason, per the process in `PLAN.md` § Design source of truth.
- **Format**: `### YYYY-MM-DD — Title` heading, then a short paragraph or bullet list. Reference the relevant section of `PLAN.md` when applicable.

---

## Decisions

### 2026-05-10 — Attachments storage: content-addressed files in Application Support; CloudKit sync deferred to Phase 4

`PLAN.md` § Open questions calls for the attachments decision before Phase 2. Decided.

- **Phase 2** stores attachments as files at `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`. `fields_json` references them by sha256. Files travel inside backup zips automatically because they're under the Application Support tree the auto-backup already captures.
- **Phase 4** mirrors attachments to CloudKit as `CKAsset` (the only realistic shape for >50 KB binary data over CloudKit). `CKAsset`s are not E2E encrypted by `encryptedValues` — Apple has the keys for assets even though they don't for the JSON `fields` blob. That's a known and accepted trade-off: file content has lower confidentiality requirements than the structured fields, and the alternative (chunking + client-side encryption of media) costs weeks for a personal-scale app.
- **What's rejected**: BLOBs in SQLite (Timeliner's pattern) — fine for the small case-file attachments Timeliner deals with, but a Life OS will have photo libraries in the hundreds of MB and SQLite-as-a-blob-store stops being the right shape there. CKAsset-only with no local copy — defeats backups, breaks offline use.
- **Schema implication**: a single `attachments` table created in Phase 2 with `id`, `parent_object_id`, `sha256`, `filename`, `mime_type`, `size_bytes`, `created_at`. The on-disk file is the source of truth for content; the row is metadata only. Cascade deletes when the parent object is deleted.

### 2026-05-10 — CloudKit spike PASS; encryption decision locked

The spike `Spike/CloudKit/CloudKitSpike.app` ran successfully against the production Apple Developer setup:

- Container `iCloud.com.bronty13.PurpleLife` provisioned.
- App ID `com.bronty13.PurpleLife.CloudKitSpike` created with iCloud capability + container attached.
- Mac registered as a development device on team `SRKV8T38CD`.
- `build-spike.sh` updated with `-allowProvisioningUpdates` and `DEVELOPMENT_TEAM=SRKV8T38CD` baked into `Spike/CloudKit/project.yml` so future runs are turnkey.

**Result**: PASS — bytes-out matched bytes-in (sha256 `822b5b86…`), plaintext columns round-tripped, 4.2 s end-to-end on a brand-new container's first write. Full log + decision in `Spike/CloudKit/SPIKE.md` § Run log / Decision.

**Effect on plan**: the encryption row in `PLAN.md` § Locked decisions stands as written. `CKRecord.encryptedValues` is confirmed as the layer Phase 4 will mirror through. No follow-up spike needed before Phase 4 starts.

**Gotcha for future reference**: a fresh App ID's iCloud row on developer.apple.com requires a separate "Configure → check container → Save" step *after* registration to actually attach the container — the Capability Requests during initial registration only enable the capability, not the container assignment. Skip this and CloudKit returns `CKError.code = 5 (badContainer)` even though everything else looks correct.

### 2026-05-10 — Phase 0 (Tap Forms trial) skipped; decision: build

The plan reserves Phase 0 as a one-week Tap Forms trial against ≥3 real use cases, with a "build or stop" gate at the end. That gate is now closed without running the trial.

- **Decision**: build PurpleLife. Skip Phase 0.
- **Rationale**:
  - The user has already evaluated the off-the-shelf options surveyed in `PLAN-original.md` (Tap Forms, Ninox, Trilium, Anytype) and concluded the gap on the planner side and on configurable cross-type relations would not be closed by any of them.
  - The PhantomLives family (`Timeliner`, `PurpleTracker`, `WeightTracker`, `PurpleIRC`, `PurpleDedup`) provides nearly every system service PurpleLife needs as copy-then-adapt source material; the build cost is meaningfully lower than the plan's original estimate assumes.
  - End-to-end encryption with keys the user controls is a hard requirement that no off-the-shelf candidate satisfies in the way `CKRecord.encryptedValues` does. Even a successful Tap Forms trial would not have changed this.
- **Effect on plan**:
  - `PLAN.md` § Build phases shows P0 as skipped, dashed-line, with the rationale pointer to this file.
  - `PLAN.md` § Phase acceptance tests row for Phase 0 reads "Skipped" with the same pointer.
  - The CloudKit spike is moved ahead of Phase 1 (rather than running parallel with Phase 2 as the original plan suggested), to surface any `encryptedValues` blockers before the Foundation phase commits to the storage shape.

### 2026-05-10 — Project name locked: PurpleLife

The project is named **PurpleLife**, matching the directory and the Purple* family naming convention (PurpleIRC, PurpleDedup, PurpleTracker). Any references to the prior working title ("Personal ERP") are removed from active documentation. `PLAN-original.md` retains the prior name in its content as a historical record only and is annotated accordingly at the top of the file.

---

## Design deviations from `~/Downloads/PurpleLife-handoff.zip`

_None yet._ Phase 2 has not begun. Add entries here as `### YYYY-MM-DD — <Screen> — <one-line reason>` as deviations are made.
