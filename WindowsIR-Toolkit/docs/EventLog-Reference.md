# Windows Event Log Reference (IR-relevant IDs)

The event IDs that matter for triage, the log they live in, and what they tell
you. Logs are under `C:\Windows\System32\winevt\Logs\*.evtx`. Hunt them with
`scripts\Run-Hayabusa.ps1` (Sigma) or parse with `EvtxECmd`.

> **Caveat:** most high-value events require auditing/Sysmon to have been enabled
> *before* the incident. Absence of an event ≠ absence of activity. Check audit
> policy (`auditpol /get /category:*`) and whether Sysmon was installed.

---

## Security.evtx — authentication & account activity

| ID | Meaning | IR use |
|----|---------|--------|
| **4624** | Successful logon | who/when/where; **LogonType** + Source IP = lateral movement |
| **4625** | Failed logon | brute force, password spray, bad lateral attempts |
| 4634 / 4647 | Logoff | session bounding |
| 4648 | Logon with explicit creds (runas) | credential use, lateral movement |
| **4672** | Special privileges assigned (admin logon) | privileged session start |
| **4688** | **Process creation** (+ cmdline if enabled) | execution, parent/child — enable cmdline auditing! |
| 4689 | Process exit | process lifetime |
| **4720** | User account **created** | rogue account |
| 4722/4725/4726 | Account enabled/disabled/deleted | account tampering |
| 4723/4724 | Password change/reset | account takeover |
| **4728/4732/4756** | Member added to (global/local/universal) **admin** group | privilege escalation |
| 4738 | User account changed | account tampering |
| **4698 / 4699** | Scheduled task created / deleted | persistence |
| 4697 | Service installed (Security log variant) | persistence |
| **4768 / 4769** | Kerberos TGT / service ticket requested | lateral movement, Kerberoasting (4769 w/ RC4) |
| 4776 | NTLM authentication | pass-the-hash patterns |
| 4720+4732 pair | created account *and* added to admins | strong compromise signal |
| 1102 | **Security log cleared** | anti-forensics — investigate hard |

## System.evtx

| ID | Meaning | IR use |
|----|---------|--------|
| **7045** | New service installed | classic persistence / lateral (PsExec installs a service) |
| 7034/7031/7036 | Service crashed/stopped/state change | defense tampering (AV stopped) |
| 7040 | Service start type changed | persistence enable |
| 104 | Event log cleared (System) | anti-forensics |
| 1074 | Shutdown/restart initiated (who/why) | timeline |
| 6005/6006/6008 | Event log start / clean stop / **dirty shutdown** | uptime, crashes |
| 219 | Driver load failure | malicious/unsigned driver attempts |

## Application.evtx
| ID | Meaning |
|----|---------|
| 1000/1001 | App crash / WER | exploited process, crashing malware |
| 1033/11707/1034 | MSI install/uninstall | software dropped |

---

## PowerShell — `Microsoft-Windows-PowerShell/Operational.evtx`

| ID | Meaning | IR use |
|----|---------|--------|
| **4104** | **Script block logging** | the actual (deobfuscated) script that ran — gold |
| 4103 | Module/pipeline logging | command invocation detail |
| 400/403 | Engine start/stop (`Windows PowerShell.evtx`) | version (v2 downgrade = evasion), host |
| 600 | Provider start | |

Also: `PSReadLine\ConsoleHost_history.txt` per user = raw interactive history.

## WMI — `Microsoft-Windows-WMI-Activity/Operational.evtx`
| ID | Meaning |
|----|---------|
| 5857–5861 | WMI provider / **permanent event consumer** activity — fileless persistence |

## Sysmon — `Microsoft-Windows-Sysmon/Operational.evtx` (if deployed)

| ID | Meaning | IR use |
|----|---------|--------|
| **1** | Process create (+ hashes, cmdline, parent) | richest execution evidence |
| **3** | Network connection | C2, lateral |
| 7 | Image/DLL loaded | DLL sideloading, unsigned modules |
| **8** | CreateRemoteThread | code injection |
| **10** | ProcessAccess | **LSASS access** = credential dumping |
| 11 | File create | dropped files |
| **12/13/14** | Registry add/set/rename | persistence, config |
| 15 | FileCreateStreamHash | ADS / mark-of-the-web |
| 17/18 | Named pipe create/connect | Cobalt Strike, PsExec |
| 19/20/21 | WMI filter/consumer/binding | WMI persistence |
| 22 | DNS query | C2 domains |
| 23/26 | File delete | anti-forensics |
| 25 | Process tampering (hollowing) | injection |

> Not deployed? Install Sysmon now (`scripts`→ download via Get-Tools) with a
> curated config for forward telemetry — it won't recover the past but improves
> every step from here.

---

## Remote / lateral-movement logs worth grabbing

```
Microsoft-Windows-TerminalServices-LocalSessionManager/Operational   (RDP 21/22/25)
Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational (RDP 1149)
Microsoft-Windows-WinRM/Operational                                  (PS remoting)
Microsoft-Windows-SmbClient/Security  &  SMBServer                    (share access)
Microsoft-Windows-Windows Defender/Operational  (1116/1117 detections, 5001 disabled)
Microsoft-Windows-Bits-Client/Operational        (download persistence/exfil)
```

---

## Fast hunting commands

```powershell
# New services (persistence / PsExec)
Get-WinEvent -FilterHashtable @{LogName='System';Id=7045} |
  Select TimeCreated,@{n='Msg';e={$_.Message}}

# Remote (type 3/10) logons with source
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624} |
  % { $x=[xml]$_.ToXml(); [pscustomobject]@{
        Time=$_.TimeCreated
        Type=($x.Event.EventData.Data|?{$_.Name -eq 'LogonType'}).'#text'
        User=($x.Event.EventData.Data|?{$_.Name -eq 'TargetUserName'}).'#text'
        Src =($x.Event.EventData.Data|?{$_.Name -eq 'IpAddress'}).'#text' } } |
  ? { $_.Type -in 3,10 } | Format-Table

# Log clears — anti-forensics
Get-WinEvent -FilterHashtable @{LogName='Security';Id=1102}
Get-WinEvent -FilterHashtable @{LogName='System';Id=104}

# Or just let Sigma do it:
#   ..\scripts\Run-Hayabusa.ps1 -Live
```
