# PurpleLife — HANDOFF

The durable log of decisions and design-handoff deviations for PurpleLife. Append-only; do not rewrite history. Newest entries at the top.

## How to use this file

- **Decisions**: every locked decision that overrides or amends `PLAN.md` is recorded here with a date and one-line rationale.
- **Design deviations**: any deliberate divergence from `~/Downloads/PurpleLife-handoff.zip` (the visual design source of truth) is recorded here with a one-line reason, per the process in `PLAN.md` § Design source of truth.
- **Format**: `### YYYY-MM-DD — Title` heading, then a short paragraph or bullet list. Reference the relevant section of `PLAN.md` when applicable.

---

## Decisions

### 2026-05-10 — CloudKit spike scaffolded; run pending user setup

The spike app lives at `Spike/CloudKit/`. It compiles clean against Xcode 26.4.1 (verified). The actual `encryptedValues` round-trip run requires:

- iCloud signed in on the build Mac.
- The container `iCloud.com.bronty13.PurpleLife` provisioned at <https://developer.apple.com/account>.
- The team set in Xcode Signing & Capabilities on the generated project.

Procedure and PASS/FAIL criteria are in `Spike/CloudKit/SPIKE.md`. The spike PASS is the gate that locks the encryption decision before Phase 4 (CloudKit sync). It does **not** gate Phase 1 (Foundation), since Phase 1 only touches the local GRDB layer; on-disk encryption is FileVault's job per `PLAN.md` § Locked decisions. Phase 1 scaffolding therefore proceeds in parallel.

If the spike comes back FAIL, the encryption row in `PLAN.md` § Locked decisions reopens and we revisit before Phase 4 begins.

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
