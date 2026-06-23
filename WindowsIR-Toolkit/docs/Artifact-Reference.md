# Windows Forensic Artifact Reference

What each artifact is, where it lives, what question it answers, and how to parse
it. Grouped by the investigative question. Paths assume `C:` system drive.

> **Execution** = "did this run?"  **Persistence** = "how does it survive reboot?"
> **Files** = "what touched the disk & when?"  **Accounts/Logons** = "who, from where?"

---

## EXECUTION — "what programs ran on this host?"

| Artifact | Location | Proves | Parse with |
|---|---|---|---|
| **Prefetch** | `C:\Windows\Prefetch\*.pf` | program ran; first/last run times, run count, files/dirs it referenced | `PECmd.exe` |
| **Amcache** | `C:\Windows\AppCompat\Programs\Amcache.hve` | program *present/executed*; **SHA1 of the binary**, path, compile time | `AmcacheParser.exe -i` |
| **ShimCache (AppCompatCache)** | `SYSTEM` hive → `...\ControlSet\Control\Session Manager\AppCompatCache` | path + last-modified of executables the OS saw; **order = rough exec order** (presence ≠ definitive execution) | `AppCompatCacheParser.exe` |
| **UserAssist** | `NTUSER.DAT` → `...\Explorer\UserAssist` | GUI program launches per user + run count + last run (ROT13 names) | `RECmd` / RegRipper |
| **BAM/DAM** | `SYSTEM` → `...\Services\bam\State\UserSettings\<SID>` | last execution time of programs per user | `RECmd` |
| **Process creation events** | Security.evtx **4688**, Sysmon **1** | exact process, command line (if auditing on), parent | `EvtxECmd` / Hayabusa |
| **PowerShell** | `Microsoft-Windows-PowerShell/Operational.evtx` (4103/4104), `ConsoleHost_history.txt` | script-block & command history (deobfuscated) | EvtxECmd; read history file directly |

> **Note:** Win10/11 truncated/disabled some Amcache fields and Prefetch on
> servers may be off — corroborate execution across *several* of these.

---

## PERSISTENCE — see **Persistence-Locations.md** for the full ASEP list

Quick hits: Run/RunOnce keys, Startup folders, Scheduled Tasks
(`C:\Windows\System32\Tasks\*` XML), Services (`SYSTEM`→`Services`), WMI event
subscriptions (`root\subscription`), Winlogon (Shell/Userinit), Image File
Execution Options (debugger hijack), AppInit_DLLs, LSA packages, BITS jobs.

---

## FILE / FOLDER ACTIVITY — "what files existed, when?"

| Artifact | Location | Proves | Parse with |
|---|---|---|---|
| **$MFT** | volume root `$MFT` | every file's MACB timestamps, size, resident data; **timestomping** (compare `$STANDARD_INFORMATION` vs `$FILE_NAME`) | `MFTECmd.exe` |
| **$UsnJrnl:$J** | volume `$Extend\$UsnJrnl` | file create/rename/delete history (great for deleted malware) | `MFTECmd.exe` |
| **$LogFile** | volume root | NTFS transaction detail | `MFTECmd` / LogFileParser |
| **LNK files** | `...\Recent\*.lnk` | files opened, their original path, volume serial, MAC times | `LECmd.exe` |
| **JumpLists** | `...\Recent\AutomaticDestinations` | app-specific recent files | `JLECmd.exe` |
| **Recycle Bin** | `C:\$Recycle.Bin\<SID>\$I*` | deleted file original name/path/size/time | `RBCmd.exe` |
| **Shellbags** | `UsrClass.dat`/`NTUSER.DAT` | folders the user browsed (even now-deleted) | `SBECmd.exe` |

---

## ACCOUNTS, LOGONS, LATERAL MOVEMENT

| Artifact | Location | Proves | Parse |
|---|---|---|---|
| **Security.evtx** | `winevt\Logs\Security.evtx` | logons (**4624**/4625), logon type, source IP/host; account create (**4720**), group add (**4732/4728**); RDP, scheduled task create (**4698**) | `EvtxECmd` / Hayabusa |
| **SAM hive** | `C:\Windows\System32\config\SAM` | local accounts, RIDs, last logon, group membership | `RECmd` / RegRipper |
| **RDP** | `Microsoft-Windows-TerminalServices-*` logs, `bcache*`/`Default.rdp` | inbound/outbound RDP, cached destination thumbnails | EvtxECmd |
| **NTLM/Kerberos** | Security.evtx 4768/4769/4776 | auth requests (lateral movement, pass-the-hash patterns) | Hayabusa |

**Logon types** (event 4624 `LogonType`): 2=interactive, 3=network (SMB/file
share), 4=batch, 5=service, 7=unlock, 8=cleartext, 9=new-creds (runas /netonly,
seen with pass-the-hash), 10=RemoteInteractive (RDP), 11=cached.

---

## NETWORK & USAGE

| Artifact | Location | Proves | Parse |
|---|---|---|---|
| **SRUM** | `C:\Windows\System32\SRU\SRUDB.dat` | per-app bytes sent/received (**exfil**!), app & network usage over ~30–60 days | `SrumECmd.exe` |
| **DNS cache** | volatile | recently resolved domains | `Collect-Triage.ps1` §01 |
| **hosts file** | `...\drivers\etc\hosts` | redirected/blocked domains (malware tampering) | read directly |
| **Firewall log** | `...\LogFiles\Firewall\pfirewall.log` (if enabled) | allowed/blocked connections | text |

---

## BROWSER & USER ARTIFACTS

| Artifact | Location | Notes |
|---|---|---|
| Chrome/Edge | `...\User Data\Default\History`, `Cookies`, `Login Data` (SQLite) | open with DB Browser for SQLite; download history shows fetched malware |
| Firefox | `...\Mozilla\Firefox\Profiles\*\places.sqlite` | history + downloads |
| IE/Edge legacy | `...\WebCache\WebCacheV01.dat` (ESE) | use ESEDatabaseView / `ECmd` |
| Outlook | `.ost`/`.pst` | phishing attachment origin |

---

## REGISTRY HIVE MAP (where the hives are)

| Hive | On disk | Loaded as |
|---|---|---|
| SYSTEM | `C:\Windows\System32\config\SYSTEM` | `HKLM\SYSTEM` |
| SOFTWARE | `...\config\SOFTWARE` | `HKLM\SOFTWARE` |
| SAM | `...\config\SAM` | `HKLM\SAM` |
| SECURITY | `...\config\SECURITY` | `HKLM\SECURITY` |
| NTUSER.DAT | `C:\Users\<u>\NTUSER.DAT` | `HKU\<SID>` / `HKCU` |
| UsrClass.dat | `C:\Users\<u>\AppData\Local\Microsoft\Windows\UsrClass.dat` | `HKCU\Software\Classes` |
| Amcache | `C:\Windows\AppCompat\Programs\Amcache.hve` | (loaded on demand) |

> **Transaction logs** (`*.LOG1/.LOG2`) sit next to each hive — copy them too;
> EZ tools replay them for a consistent view. `Collect-Triage.ps1` copies the
> base hives; for full fidelity also grab the `.LOG*` siblings (KAPE/Velociraptor do).

---

## Quick "is this binary bad?" checklist

1. **Hash it** (`Get-FileHash`) → check VirusTotal / your TI.
2. **Signature** — unsigned or invalid in a system-looking path = suspicious.
3. **Path** — legit system binaries don't live in `%TEMP%`, `%APPDATA%`,
   `%PUBLIC%`, `C:\ProgramData\<random>`, `C:\Users\Public`.
4. **Strings** (`strings.exe`) → URLs, IPs, suspicious API names, base64.
5. **Compile time** (Amcache) vs file-create time vs incident time.
6. **Parent/child** — what launched it, what did it launch.
