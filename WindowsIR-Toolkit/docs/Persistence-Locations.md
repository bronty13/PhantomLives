# Windows Persistence (ASEP) Locations

Auto-Start Extensibility Points malware uses to survive reboot, mapped to
**MITRE ATT&CK T1547 / T1053 / T1543 / T1546 / T1037**. `Collect-Triage.ps1`
§02 dumps most of these; **Sysinternals Autoruns** (`autorunsc.exe -a * -h -c`)
is the gold-standard one-shot enumerator. Hunt for entries pointing at
user-writable paths, unsigned binaries, scripts, or encoded commands.

---

## Registry Run keys (T1547.001)
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce
HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run    (32-bit on 64-bit)
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
HKCU\...\RunOnce
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServices[Once]
```

## Startup folders (T1547.001)
```
%AppData%\Microsoft\Windows\Start Menu\Programs\Startup          (per-user)
%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup      (all users)
```

## Scheduled Tasks (T1053.005)
```
C:\Windows\System32\Tasks\                 (XML, one file per task — copy whole tree)
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks
Event: Microsoft-Windows-TaskScheduler/Operational  + Security 4698 (task created)
```
Enumerate: `schtasks /query /fo LIST /v` or `Get-ScheduledTask`.

## Services (T1543.003)
```
HKLM\SYSTEM\CurrentControlSet\Services\<name>   (ImagePath, Start, ServiceDll)
Event: System 7045 (new service installed)  ← classic persistence indicator
```
Watch `ServiceDll` under `...\Parameters` (svchost-hosted service hijack) and
`ImagePath` pointing outside `\Windows\`.

## Winlogon (T1547.004)
```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon
   Shell      (should be exactly: explorer.exe)
   Userinit   (should be: C:\Windows\system32\userinit.exe,)
   Notify
```
Extra entries appended to Shell/Userinit = persistence.

## Image File Execution Options — debugger hijack (T1546.012)
```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\<exe>
   Debugger = <malware>      ← launches malware whenever <exe> starts
   GlobalFlag / SilentProcessExit  (also abused)
```
Classic: `sethc.exe`/`utilman.exe` Debugger = `cmd.exe` (sticky-keys backdoor).

## AppInit / AppCert DLLs (T1546.010 / T1546.009)
```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\AppInit_DLLs
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\AppCertDLLs
```

## LSA — auth/security packages, SSP (T1547.005 / T1556)
```
HKLM\SYSTEM\CurrentControlSet\Control\Lsa
   Authentication Packages / Security Packages / Notification Packages
```
Rogue DLL here = credential theft persistence (e.g. mimilib/SSP).

## WMI permanent event subscription (T1546.003)
```
root\subscription : __EventFilter  +  __EventConsumer (CommandLineEventConsumer /
ActiveScriptEventConsumer)  +  __FilterToConsumerBinding
```
Fileless, survives reboot, no registry Run key. **Any** CommandLine/ActiveScript
consumer deserves scrutiny. Enumerate with the collector or:
`Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding`.

## COM hijacking (T1546.015)
```
HKCU\Software\Classes\CLSID\<guid>\InprocServer32   (shadows HKLM; per-user, stealthy)
```

## Browser Helper Objects / Office add-ins (T1176 / T1137)
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects
Office: ...\Office\<ver>\<app>\Addins ; Word\STARTUP ; Outlook VbaProject.OTM ; templates (normal.dotm)
```

## Logon scripts / GPO (T1037)
```
HKCU\Environment\UserInitMprLogonScript
Group Policy logon/startup scripts (SYSVOL on DC)
```

## Boot / driver-level (T1547.006, deeper)
```
HKLM\SYSTEM\CurrentControlSet\Services\<driver>  (Type=1 kernel driver, Start=0/1)
BCD, bootkit territory — escalate to specialist tooling if suspected.
```

## Accessibility & misc backdoors
```
Sticky Keys / Utilman / Magnifier / Narrator / Display Switch / App Switcher
  (sethc.exe, utilman.exe, osk.exe, Magnify.exe, Narrator.exe, DisplaySwitch.exe, AtBroker.exe)
  via IFEO Debugger or binary replacement
```

---

## Fast triage commands

```powershell
# Sysinternals Autoruns — everything, with hashes, as CSV (best single view)
.\tools\Sysinternals\autorunsc.exe -accepteula -a * -h -s -c -nobanner > autoruns.csv

# New-service / new-task events
Get-WinEvent -FilterHashtable @{LogName='System';Id=7045} | Format-List TimeCreated,Message
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4698} | Format-List TimeCreated,Message

# WMI subscriptions
Get-WmiObject -Namespace root\subscription -Class __EventConsumer

# Scheduled tasks pointing outside Windows
Get-ScheduledTask | % { $_.Actions } | ? Execute -notmatch '\\Windows\\'
```

**Triage rule of thumb:** an autostart entry that is *unsigned*, lives in a
*user-writable path*, was *created near the incident time*, or runs a *script /
encoded command* is guilty until proven innocent.
