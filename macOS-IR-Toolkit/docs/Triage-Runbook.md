# macOS Triage Runbook

The operational sequence. Do these in order; log every step in
`Chain-of-Custody-template.md`.

## 0. Before you touch the keyboard
- Confirm **authorization** in writing.
- Photograph the screen; note what's running/visible.
- Decide containment timing — **collect volatile state BEFORE pulling network/power.**

## 1. Prepare
- Plug in **removable evidence media** (point all output there, not the suspect disk).
- Grant your terminal **Full Disk Access** (System Settings → Privacy & Security → Full
  Disk Access). Without it, TCC-protected artifacts are missed.

## 2. One-shot triage (recommended)
```bash
sudo ./run-triage.sh -o /Volumes/Evidence
```
Runs: sysdiagnose → dependency-free collect → YARA hunt → summary + manifest. Add
`--include-aftermath` for Jamf Aftermath deep collection, `--pid <N>` to core a suspect
process.

## 3. Or stage-by-stage
```bash
sudo ./scripts/capture-memory.sh -o /Volumes/Evidence            # 1. volatile (sysdiagnose)
sudo ./collect-triage.sh -o /Volumes/Evidence                    # 2. collect
./scripts/run-yara.sh -p /Users -p /Applications -p /tmp          # 3. hunt
sudo ./scripts/run-aftermath.sh -o /Volumes/Evidence             # 3b. deep (optional)
```

## 4. First-pass analysis (what to read first)
1. `<evidence>/REPORT.html` — chain of custody + pointers.
2. `01_volatile/net_connections.txt` — unexpected outbound? Map PID → binary.
3. `01_volatile/process_tree.txt` — odd parentage (e.g. a shell under a browser).
4. `02_persistence/launchd_*.txt` — **non-Apple** agents/daemons, odd paths.
5. `02_persistence/login_items_btm.txt` — background items you don't recognize.
6. `02_persistence/config_profiles.txt` + `tcc_access.txt` — rogue profile / TCC grants.
7. `hunt/yara_matches.csv` — triage every hit.
8. `03_artifacts/` quarantine + browser/shell history — how did it get in?

## 5. Deeper
- Expand the unified log archive: `log show --archive <…>.logarchive --predicate '…'`.
- Parse quarantine + browser SQLite DBs (see `Artifact-Reference.md`).
- If you cored a PID: `lldb -c proc_<pid>.core` or `strings` it.

## 6. Contain & document
- Only after volatile capture: isolate network, disable the persistence, preserve.
- Record every action + finding in the chain-of-custody log. Verify
  `CASE_SHA256_MANIFEST.csv`. Store evidence on write-protected media.
