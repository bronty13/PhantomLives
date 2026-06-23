# macOS-IR-Toolkit — HANDOFF

Maintainer-facing state snapshot. Read before changing the toolkit.
Last updated: **2026-06-23**.

## What this is

The macOS sibling of `WindowsIR-Toolkit/` — a four-stage live-response triage kit
(MEMORY → COLLECT → HUNT → SUMMARY) built around macOS realities. Orchestrator
`run-triage.sh` chains: `scripts/capture-memory.sh` → `collect-triage.sh` →
`scripts/run-yara.sh` (+ optional `scripts/run-aftermath.sh`) → summary + manifest.
See `README.md` for the file map.

## Verified working (tested live on this machine)

Built and tested on **macOS 26.5.1 / Apple Silicon (arm64)** — the hard case (SIP on):
- `collect-triage.sh` runs clean (40 files, ~29s, no sudo): correct SIP/Gatekeeper/
  FileVault posture, a **cycle-safe** process tree (awk, iterative — no recursion),
  parsed LaunchAgent persistence, valid SHA-256 manifest + HTML report.
- `run-triage.sh --quick --force` orchestrates end-to-end; memory correctly **skips**
  when not root.
- All six scripts pass `bash -n`.

## Design decisions (confirmed with the user)

- **Memory:** full physical RAM is unobtainable on Apple Silicon (SIP + no DMA + unified
  memory). The MEMORY stage captures `sysdiagnose` + optional `lldb` per-PID cores and
  **documents the limit honestly** (`docs/Memory-Forensics.md`). Not a bug — by design.
- **Dependencies:** dependency-free bash core that always runs, PLUS optional tools via
  `get-tools.sh` (YARA, Jamf **Aftermath** = the macOS Velociraptor/KAPE, osquery).

## The two operational gotchas (tell every user)

1. **Full Disk Access is required, separately from root.** macOS TCC blocks even root
   from Safari/Mail/Messages/TCC.db/unified-log without the *terminal* having FDA
   (System Settings → Privacy & Security → Full Disk Access). `run-triage.sh` probes for
   it and warns.
2. **No RAM image on Apple Silicon.** Set expectations; lean on disk artifacts.

## Robustness notes (learned by testing)

- **Per-step timeout is load-bearing.** `sfltool dumpbtm` *hangs indefinitely* without
  root/FDA (observed 7+ min). macOS has no `timeout(1)`, so `collect-triage.sh` wraps
  every `cap` step in a `perl`-based timeout (`run_to`) that **kills the whole process
  subtree** on expiry (default 45s; sfltool 25s). Verified: hung child killed in ~4s,
  zero leftover processes. If you add a new collection step, it inherits the timeout — do
  NOT call tools outside `cap`/`run_to` without one.
- Process tree is iterative + visited-guarded (same lesson as the Windows kit's PID-reuse
  cycle fix) — never reintroduce recursion there.

## Open / future

- `capture-memory.sh` sysdiagnose path is not yet exercised under sudo in CI (it's slow,
  200MB–1GB+); logic is straightforward but validate on a real engagement.
- `run-yara.sh` process-memory scanning is intentionally omitted (SIP/entitlement
  constraints); file scanning only.
- Aftermath/osquery integration is wrapper-level; not run end-to-end here (needs the tools
  installed + root). Verify on a host that has them.
- Could add: `codesign`/`spctl` sweep of `/Applications` + LaunchAgents binaries as a
  built-in "unsigned/adhoc binary" finder.

## Conventions

- Validate every script with `bash -n` before commit; prefer testing live on a Mac
  (read-only, to a temp dir) since this kit runs on the same platform we develop on.
- Default user-visible output goes under `~/Downloads/macOS-IR-Toolkit/` (per repo rule)
  unless an external `/Volumes/*` evidence drive is detected/!-o is given.
- `tools/` (downloads) and `output/`/case data are git-ignored — only source is tracked.
