# Triage Runbook — step-by-step

Concrete command sequence for triaging one Windows host with this toolkit.
Run an **elevated** PowerShell. Prefer running scripts from **read-only media**
and writing output to **separate removable media** (`-Output E:\Evidence`).

If scripts are blocked, prefix with:
`powershell -ExecutionPolicy Bypass -File <script.ps1> <args>`

---

## 0. One-time prep (on a CLEAN internet-connected workstation)

```powershell
# Fetch the open-source tools (NOT on the evidence host)
.\Get-Tools.ps1

# EZ tools self-update
.\tools\EricZimmermanTools\Get-ZimmermanTools.ps1 -Dest .\tools\EricZimmermanTools

# KAPE + FTK Imager are registration-gated — see docs/Tool-Cheatsheet.md to place them.
```
Copy the populated `WindowsIR-Toolkit\` to removable media for field use.

---

## ⚡ Fastest path — the one-shot orchestrator

`Run-Triage.ps1` chains stages 1a–1d below into a single case folder, in the
right order of volatility, skipping any stage whose tool isn't downloaded:

```powershell
.\Run-Triage.ps1 -Output E:\Evidence            # memory → collect → hunt → summary
.\Run-Triage.ps1 -Quick -Force                  # fast volatile-only, no prompts
.\Run-Triage.ps1 -Output E:\Evidence -IncludeVelociraptor
```
Output: `E:\Evidence\<HOST>_TRIAGE_<stamp>\` containing the evidence dir, a
`hunt\` folder (Hayabusa timeline + YARA matches), `TRIAGE_SUMMARY.txt`,
`CASE_SHA256_MANIFEST.csv`, and `run-triage.log`. Switches: `-SkipMemory`,
`-SkipHunt`, `-YaraPath <dir>`, `-Force`.

The stages below are what it runs — use them directly for finer control.

---

## 1. LIVE RESPONSE (host is powered on)

### 1a. Capture memory FIRST
```powershell
.\scripts\Invoke-MemoryCapture.ps1 -Output E:\Evidence
```
Produces `HOST_memory_<stamp>.raw` + `.sha256`. (Skip only if RAM is irrelevant.)

### 1b. Native volatile + persistence + artifact collection
```powershell
.\Collect-Triage.ps1 -Output E:\Evidence
```
Creates `E:\Evidence\HOST_<stamp>\` with `01_volatile`, `02_persistence`,
`03_artifacts`, `REPORT.html`, `SHA256_MANIFEST.csv`.

> Quicker, volatile-only pass (no large artifact copy):
> `.\Collect-Triage.ps1 -SkipArtifactCopy`

### 1c. (Optional) broader curated collection
```powershell
.\scripts\Invoke-VelociraptorTriage.ps1 -Output E:\Evidence   # open-source, no server
# or, if KAPE is staged:
.\scripts\Invoke-KapeTriage.ps1 -Output E:\Evidence           # !SANS_Triage + !EZParser
```

### 1d. Live detections + IOC scan
```powershell
.\scripts\Run-Hayabusa.ps1 -Live                              # Sigma over live EVTX
.\scripts\Scan-Yara.ps1 -Path C:\Users -Output E:\Evidence\yara_users.csv
.\scripts\Scan-Yara.ps1 -Processes                            # scan process memory (admin)
```

---

## 2. FIRST-LOOK ANALYSIS (5–10 minutes, on the collection)

Open the evidence folder and skim, in this order:

| Look at | For |
|---|---|
| `REPORT.html` | system context, where to start |
| `01_volatile\processes.csv` | unsigned exes, `Signature` not Valid, parent oddities (e.g. `winword.exe`→`powershell.exe`), paths in `\Temp\`,`\AppData\`,`\ProgramData\`, random names |
| `01_volatile\process_tree.txt` | living-off-the-land chains; office→script→lolbin |
| `01_volatile\netstat_connections.csv` | ESTABLISHED to unknown public IPs; rare ports; process owning it |
| `02_persistence\run_keys.txt` | autorun values pointing at user-writable paths / scripts |
| `02_persistence\scheduled_tasks.csv` | tasks running scripts, `RunAs=SYSTEM`, odd authors |
| `02_persistence\services_unsigned_nonstd.txt` | services outside `\Windows\` |
| `02_persistence\wmi_event_subscriptions.txt` | **any** CommandLine/ActiveScript consumer = high-suspicion persistence |
| `02_persistence\local_users_groups.txt` | new accounts, unexpected Administrators members |

**Red-flag heuristics** (any of these warrants a pivot):
- Executable that is **unsigned** *and* lives outside `C:\Windows` / `C:\Program Files`.
- `powershell.exe`/`cmd.exe`/`wscript.exe`/`mshta.exe`/`rundll32.exe`/`regsvr32.exe`
  with a long, **base64/`-enc`/`IEX`/`DownloadString`** command line.
- Process whose **parent is `services.exe` but isn't a known service**, or whose
  parent already exited (orphaned).
- Outbound connection from `svchost.exe`/`lsass.exe` to a public IP.
- Scheduled task or service created **near the suspected incident time**.

---

## 3. DEAD-DISK / DEEP PARSE (on analysis workstation)

```powershell
# Parse collected artifacts to CSV with Eric Zimmerman tools
.\scripts\Parse-Artifacts.ps1 -ArtifactDir E:\Evidence\HOST_<stamp>\03_artifacts

# Sigma detections over the collected EVTX
.\scripts\Run-Hayabusa.ps1 -LogDir E:\Evidence\HOST_<stamp>\03_artifacts\EventLogs `
                           -Output E:\Evidence\hayabusa.csv
```
Open the resulting CSVs in **Timeline Explorer** (EZ tools). Key views:

| Parsed artifact | Answers |
|---|---|
| `Amcache` / `Shimcache` | *what executables existed/ran* (+ SHA1 in Amcache) |
| `Prefetch` | *what ran, when, how many times, from where* |
| `EVTX events.csv` (EvtxECmd) | logons, process creation, service installs, PS logging |
| `$MFT` (mft.csv) | file creation/timestamps; timestomping (compare $SI vs $FN) |
| `SRUM` | per-app network bytes sent/received (exfil), app usage |
| `Registry RECmd` | UserAssist, RunMRU, typed paths, USB, autoruns |

---

## 4. MEMORY ANALYSIS (Volatility 3, on the workstation)

```bash
vol -f HOST_memory_<stamp>.raw windows.info            # validate image/profile
vol -f HOST_memory_<stamp>.raw windows.pstree          # process tree
vol -f HOST_memory_<stamp>.raw windows.netscan         # connections in RAM
vol -f HOST_memory_<stamp>.raw windows.malfind         # injected/hidden code
vol -f HOST_memory_<stamp>.raw windows.cmdline         # full command lines
vol -f HOST_memory_<stamp>.raw windows.dlllist         # loaded DLLs (suspicious paths)
vol -f HOST_memory_<stamp>.raw windows.svcscan         # services from kernel
```
See **Memory-Forensics.md** for the full plugin playbook.

---

## 5. BUILD THE TIMELINE & WRITE IT UP

1. Merge key timestamped CSVs (EVTX, Prefetch, MFT, Amcache) by time.
2. Mark: initial access → execution → persistence → priv-esc → lateral → impact.
3. Extract **IOCs** (hashes, IPs, domains, filenames, mutexes) → `iocs\` for
   fleet-wide hunting and detection engineering.
4. Record findings + every analyst action with timestamps. Use
   **Chain-of-Custody-template.md**.

---

## Containment actions (only after capture, and log each one)

```powershell
# Isolate from network (keep host on for memory/live evidence)
Disable-NetAdapter -Name * -Confirm:$false           # blunt; or block at switch/FW

# Kill a confirmed-malicious process (note PID + hash first!)
Stop-Process -Id <PID> -Force

# Disable (don't yet delete) a persistence item
Disable-ScheduledTask -TaskName "<name>"
Set-Service "<name>" -StartupType Disabled
```
> Deleting persistence/malware **destroys evidence** — disable + preserve a copy
> first unless eradication is explicitly authorized.
