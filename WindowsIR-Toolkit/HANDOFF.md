# WindowsIR-Toolkit — HANDOFF

Maintainer-facing state snapshot. Read this before changing the toolkit.
Last updated: **2026-06-23**.

## What this is

A self-contained, mostly-dependency-free **Windows incident-response triage kit**
(PowerShell + a few downloaded open-source tools). One orchestrator
(`Run-Triage.ps1`) chains four stages in order of volatility:

1. **MEMORY**  → `scripts\Invoke-MemoryCapture.ps1` (arch-aware RAM capture)
2. **COLLECT** → `Collect-Triage.ps1` (volatile + persistence + artifact copies, dependency-free)
3. **HUNT**    → `scripts\Run-Hayabusa.ps1` (Sigma/EVTX) + `scripts\Scan-Yara.ps1` (+ optional Velociraptor)
4. **SUMMARY** → `TRIAGE_SUMMARY.txt` + case-wide SHA-256 manifest

See `README.md` for the full file map and quick-start.

## The three copies (this caused real confusion — understand it)

There are **three** physical copies of this toolkit. Keep them straight:

| Copy | Path | Role |
|------|------|------|
| **GitHub** | `bronty13/PhantomLives` → `WindowsIR-Toolkit/` | **Source of truth.** Edit here / commit here. |
| **IR USB** | `/Volumes/IR/WindowsIR-Toolkit` (on the Mac) | Deployment staging. Mirror of source **minus** `tools/` and `output/`. |
| **Windows runtime** | `C:\rto\WindowsIR-Toolkit` (on BRONTYC464) | Where triage actually RUNS. |

**Propagation:** edit on the Mac → `rsync` to the IR USB (or edit the USB directly)
→ commit/push to GitHub → on Windows, **manually copy** the USB into `C:\rto`
(there is no PowerShell/scripted access to the USB from the Windows host, so it's a
drag-drop or robocopy by hand). The recurring early failure in this project was
editing one copy while running another — **always confirm the fix landed on
`C:\rto` before re-running.** A good tell: a stage that was failing now succeeds.

Re-copy command (run on Windows, adjust the USB drive letter):

```powershell
robocopy E:\WindowsIR-Toolkit C:\rto\WindowsIR-Toolkit /E /XD tools output /XF "._*" ".DS_Store"
Get-ChildItem -Recurse C:\rto\WindowsIR-Toolkit -Filter *.ps1 | Unblock-File
```

`tools/` (downloaded binaries, ~3.6 GB) and `output/` (case data) are **git-ignored**
and **rsync/robocopy-excluded** — only source is tracked/synced.

## Current status (verified on BRONTYC464, an ARM64 Copilot+ PC)

| Stage | Status | Notes |
|-------|--------|-------|
| Hayabusa | ✅ OK | 1,537 detections over 23 channels; the `--no-wizard` duplicate-flag bug is fixed. |
| YARA | ✅ OK | Runs; 0 matches with the starter ruleset (expected — replace with YARA-Forge). |
| Collect | ✅ OK | `process_tree.txt` no longer crashes (cycle-safe rewrite). |
| Memory | ⚠️ Fails **by design** on ARM64 until DumpIt is installed | See below. |

## Bugs fixed this session (all on `main`)

- **Hayabusa `--no-wizard` duplicate** (`Run-Hayabusa.ps1`): `-w` is the short alias
  for `--no-wizard`; passing both made clap abort. Dropped the redundant `-w`.
- **Admin-check string bug** (`Invoke-MemoryCapture.ps1` **and** `Scan-Yara.ps1`):
  `.IsInRole('Administrator')` matches the built-in *user*, not the Administrators
  *group*, so it returned `$false` even when elevated. Both switched to the
  `[WindowsBuiltInRole]::Administrator` enum overload. (This was the real cause of
  the original "Memory FAIL" despite `Elevated: True`.)
- **Architecture-aware memory** (`Invoke-MemoryCapture.ps1`): prefer **Magnet DumpIt**
  (x86/x64/ARM64, signed driver, `.dmp` crash dump) → fall back to **WinPmem**
  (x86/x64 only) → on ARM64 with no DumpIt, **fail fast with install instructions**
  instead of loading an x64 driver that can't load on the ARM64 kernel. Switched
  WinPmem fetch to the `go-winpmem` signed build (legacy `winpmem_mini_x64_rc2`
  writes a 0-byte image on modern Windows, Velocidex issue #55). Rejects
  truncated/0-byte images. `Run-Triage.ps1` now detects either acquirer and accepts
  `.dmp` or `.raw`.
- **`process_tree.txt` "call depth overflow"** (`Collect-Triage.ps1`): root cause was
  a **PID-reuse cycle** (A→B→A) followed forever by the recursive walker, not real
  depth. Rewrote as an iterative DFS with a visited-set; verified against mock data
  containing a cycle (terminates, every process printed once).
- **`processes.csv` perf** (`Collect-Triage.ps1`): cache SHA-256 by exe path so a
  binary backing many processes is hashed once, not once per process.
- **DumpIt registered** as a registration-gated tool (`tools.manifest.json` +
  `Get-Tools.ps1`).
- **README**: added an "Enabling PowerShell script execution" section (per-process
  `Bypass` preferred on a suspect host).

## To capture memory on this (ARM64) host

WinPmem has **no ARM64 driver** — DumpIt is the only free option. On Windows:

1. `.\Get-Tools.ps1 -Only DumpIt -IncludeManualRegistration` (opens the Magnet page),
   or download from <https://www.magnetforensics.com/resources/magnet-dumpit-for-windows/>.
2. Register, download **Magnet DumpIt for Windows**, use the **ARM64 build**.
3. Place it at `C:\rto\WindowsIR-Toolkit\tools\DumpIt\ARM64\DumpIt.exe`
   (a single `tools\DumpIt\DumpIt.exe` also works — the wrapper auto-finds it).
4. Re-run `.\Run-Triage.ps1`; memory → `<host>_memory_<stamp>.dmp`.

On x86/x64 hosts, WinPmem (`Get-Tools.ps1 -Only WinPmem`) is sufficient and needs no registration.

## Open / not-yet-done (flagged, intentionally not changed blind)

- **Velociraptor args** (`Invoke-VelociraptorTriage.ps1`): passes
  `--args "VSSAnalysisAge=0"` to `Windows.KapeFiles.Targets`. Verify that parameter
  name against the installed artifact (`velociraptor artifacts show Windows.KapeFiles.Targets`)
  before relying on it — not validated on a Windows box.
- **Hayabusa rule parse errors** (`Rule parsing errors: 4948`): version skew between
  the bundled `hayabusa 3.9.0` binary and the freshly-updated rule set. Cosmetic —
  it still loaded 4,627 rules and scanned fine. To silence: pin the rules to the
  binary's release, or update the binary.
- **YARA stdout parsing** (`Scan-Yara.ps1`): best-effort regex over `-s` output; can
  produce noisy match rows. Won't crash; fine for triage.
- **No `$MFT` from the native collector**: `Collect-Triage.ps1` doesn't copy `$MFT`,
  so `Parse-Artifacts.ps1`'s MFTECmd step only fires on KAPE/Velociraptor output. By design.

## Conventions

- Release hygiene: bump/log/doc changes per the PhantomLives `.github/copilot-instructions.md`.
- Validate PowerShell edits headlessly on the Mac with
  `[System.Management.Automation.Language.Parser]::ParseFile(...)` via `pwsh` before committing.
- This kit is **not** a PhantomLives `.app` subproject — there is no `build-app.sh`;
  the "build + verify" step is the parser check + (where possible) a real run on the Windows host.
