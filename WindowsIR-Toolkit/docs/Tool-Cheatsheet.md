# Tool Cheat Sheet

Every tool in the toolkit: what it does, how to get it, and the commands you'll
actually use. Tools land in `..\tools\<Name>\` via `Get-Tools.ps1`.

> **License key:** ✅ open-source / redistributable · ⚠️ free but **download-only**
> (EULA forbids re-hosting; we never bundle these).

---

## Acquisition

### RAM (architecture-aware) ✅
```powershell
# Preferred — Magnet DumpIt: works on x86, x64 AND ARM64 (Microsoft crash dump):
.\tools\DumpIt\<ARM64|x64|x86>\DumpIt.exe /O E:\Evidence\mem.dmp /Q          # elevated

# Fallback — WinPmem, x86/x64 ONLY (no ARM64 driver):
.\tools\WinPmem\go-winpmem_amd64_*_signed.exe acquire E:\Evidence\mem.raw    # elevated
# (legacy winpmem_mini_x64_rc2.exe writes a 0-byte image on Win10/11 -- issue #55)

# Wrapper auto-picks the right engine for the host arch:
.\scripts\Invoke-MemoryCapture.ps1 -Output E:\Evidence
```

### FTK Imager ⚠️ (disk/logical imaging, E01) — https://www.exterro.com/ftk-imager
Registration required. GUI: *File → Create Disk Image* (Physical/Logical) →
add E01, verify hashes. Also *File → Capture Memory*. Mount images read-only.
Place under `tools\FTKImager\`.

---

## Live triage / collection

### Velociraptor ✅ — https://github.com/Velocidex/velociraptor
```powershell
velociraptor.exe artifacts list                       # browse artifacts
velociraptor.exe artifacts collect Windows.KapeFiles.Targets --args Device=C: --output out.zip
velociraptor.exe gui                                  # build a reusable offline collector
# wrapper: .\scripts\Invoke-VelociraptorTriage.ps1
```

### KAPE ⚠️ — https://www.kroll.com/kape (registration)
```cmd
kape.exe --tsource C: --tdest E:\T --target !SANS_Triage --vss --zip Triage ^
         --mdest E:\M --module !EZParser --mflush
:: wrapper: .\scripts\Invoke-KapeTriage.ps1 -Output E:\Evidence
```
`gkape.exe` is the GUI. Targets = *collect*, Modules = *parse*.

### Sysinternals Suite ⚠️ — https://download.sysinternals.com/files/SysinternalsSuite.zip
```powershell
autorunsc.exe -accepteula -a * -h -s -c -nobanner > autoruns.csv   # ALL ASEPs + hashes
procexp64.exe                  # live process explorer (verify sigs, VT lookup)
procmon64.exe                  # real-time file/registry/process/network tracing
tcpview64.exe                  # live connections
sigcheck.exe -h -vt <file>     # hash + signature + VirusTotal
handle64.exe -a -p <pid>       # open handles
pslist.exe / listdlls.exe / strings.exe
```
Directly downloadable; EULA just forbids re-hosting.

---

## Artifact parsing (offline)

### Eric Zimmerman tools ⚠️(policy) — https://ericzimmerman.github.io
```powershell
.\tools\EricZimmermanTools\Get-ZimmermanTools.ps1 -Dest .\tools\EricZimmermanTools  # update
MFTECmd.exe -f '$MFT' --csv out                         # MFT
PECmd.exe   -d C:\Windows\Prefetch --csv out            # Prefetch
AmcacheParser.exe -f Amcache.hve --csv out -i           # execution + SHA1
AppCompatCacheParser.exe -f SYSTEM --csv out            # Shimcache
SrumECmd.exe -f SRUDB.dat --csv out                     # network/app usage
EvtxECmd.exe -d <evtxdir> --csv out --csvf events.csv   # event logs → CSV
RECmd.exe --bn BatchExamples\Kroll_Batch.reb -d <hives> --csv out   # registry
LECmd.exe / JLECmd.exe / SBECmd.exe / RBCmd.exe         # LNK / jumplist / shellbag / recyclebin
TimelineExplorer.exe                                    # ← open all the CSVs here
# wrapper: .\scripts\Parse-Artifacts.ps1 -ArtifactDir <...>\03_artifacts
```

### RegRipper ✅ — https://github.com/keydet89/RegRipper3.0
```cmd
rip.exe -r NTUSER.DAT -f ntuser > ntuser.txt
rip.exe -r SYSTEM -p compname
```

### Autopsy ✅ — https://www.autopsy.com (Sleuth Kit GUI)
Full dead-disk platform: add an E01/raw image as a data source, run ingest
modules (hash lookup, keyword, web artifacts, timeline). Install on the
workstation, not the endpoint.

---

## Log hunting / detection

### Hayabusa ✅ — https://github.com/Yamato-Security/hayabusa
```powershell
hayabusa.exe update-rules
hayabusa.exe csv-timeline -d <evtxdir> -o out.csv -p verbose
hayabusa.exe csv-timeline -l -o live.csv          # live system
# wrapper: .\scripts\Run-Hayabusa.ps1 [-Live | -LogDir <dir>]
```

### Chainsaw ✅ — https://github.com/WithSecureLabs/chainsaw
```powershell
chainsaw.exe hunt <evtxdir> -s sigma\ --mapping mappings\sigma-event-logs-all.yml -r rules\ --csv -o out
chainsaw.exe search -t 'Event.System.EventID: =4624' <evtxdir>
```

---

## IOC / malware scanning

### YARA ✅ — https://github.com/VirusTotal/yara
```powershell
yara64.exe -r -s rules.yar C:\Users                # recurse files, show strings
yara64.exe rules.yar <pid>                          # scan a process
# wrapper: .\scripts\Scan-Yara.ps1 [-Path <dir> | -Processes]
```

### Loki ✅ — https://github.com/Neo23x0/Loki
```powershell
loki-upgrader.exe                                   # pull current signatures FIRST
loki.exe -p C:\ --intense                           # IOC + YARA scan
```

---

## Utilities

### Volatility 3 ✅ — memory analysis → see **Memory-Forensics.md**
### CyberChef ✅ — open `CyberChef_*.html` offline; decode base64/XOR/encoded PS, "Magic" auto-detect.
### DB Browser for SQLite ✅ — open browser `History`/`Cookies`, app SQLite stores.

---

## Built-in PowerShell / OS commands (no download needed)

```powershell
Get-FileHash -Algorithm SHA256 <file>
Get-AuthenticodeSignature <file> | fl Status,SignerCertificate
Get-CimInstance Win32_Process | select ProcessId,ParentProcessId,Name,CommandLine
Get-NetTCPConnection | ? State -eq Established
Get-ScheduledTask | ? {$_.State -ne 'Disabled'}
Get-CimInstance Win32_Service | ? PathName -notmatch '\\windows\\'
Get-WinEvent -FilterHashtable @{LogName='System';Id=7045}
auditpol /get /category:*           # what auditing is even on
wevtutil epl Security C:\out\Security.evtx     # export an event log
```
