# Memory Forensics on macOS — the honest version

**Read this before promising anyone a "RAM dump" of a Mac.**

## The hard truth

Full **physical memory acquisition is effectively unavailable on Apple Silicon** with
free (or even most commercial) tooling:

- **SIP** (System Integrity Protection, since 10.11) blocks loading the unsigned kernel
  driver a memory imager needs to read physical RAM — even as root.
- **Apple Silicon** removed the classic escape hatches: no FireWire/Thunderbolt DMA path
  to RAM, no boot-to-second-OS trick, and unified memory with no exposed `/dev/mem`.
- The old tools are dead: `osxpmem`/`pmem` (kext-based) won't load; `Mac Memory Reader`
  is abandoned. There is **no WinPmem / DumpIt equivalent** that works on an M-series Mac.

So this toolkit does **not** pretend to image RAM. It captures the realistic, useful
volatile state instead.

## What we capture instead (`scripts/capture-memory.sh`)

1. **`sysdiagnose`** — Apple's own broad volatile-state snapshot: full process list, open
   files, spindumps, power/네트워크 state, recent logs, loaded extensions, and much more.
   It is the single highest-value "what was happening right now" capture available without
   special tooling. Run as root: `sudo sysdiagnose -u -b -f <dir>` (`-u` = no UI prompt).

2. **Per-process cores via `lldb`** (optional, `--pid N`): for a *specific* suspicious
   process, `lldb -o "process save-core -s full <file>"` dumps that process's full mapped
   memory. **Caveat:** hardened-runtime / Apple-platform binaries refuse attachment even as
   root (no `get-task-allow` entitlement), so many PIDs will fail — that's expected.

## If you genuinely need full physical memory

- It generally requires **commercial tooling with Apple's cooperation** and/or a modified
  boot policy (Reduced Security), and even then Apple Silicon support is limited and
  version-fragile. Treat it as a specialist engagement, not a field-triage step.
- On **Intel** Macs with SIP disabled you have more options, but that is an increasingly
  rare population and disabling SIP changes the evidence.

## Analysis

- `sysdiagnose` output is a tarball of plain files — expand and grep; start with
  `ps.txt`, `lsof.txt`, `netstat.txt`, `spindump-nosymbols.txt`, and the logs.
- **Volatility 3** has macOS plugins but symbol coverage lags badly and you need a raw
  image it can parse — rarely applicable on modern Macs. Don't count on it.
- Process cores (`*.core`) open in `lldb` (`target create -c file.core`) or with
  `otool`/`nm`/`strings` for quick triage.

## Bottom line

Set expectations up front: **on a modern Mac, "memory forensics" means volatile-state
capture + targeted process cores, not a physical RAM image.** The endpoint's on-disk
artifacts (unified log, persistence, quarantine, FSEvents) carry most of the investigative
weight — see `Artifact-Reference.md`.
