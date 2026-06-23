<#
.SYNOPSIS
    Dependency-free live-response triage collector for a running Windows endpoint.
    Pure PowerShell + built-in OS utilities -- NO external binaries required, so it
    runs on a locked-down host before you stage the heavier tools.

.DESCRIPTION
    Collects, in rough order of volatility (RFC 3227):
      1. System / case context + collector self-hash
      2. Volatile state  : processes (hash, cmdline, parent, signer), network
                           connections, listening ports, DNS cache, ARP, routes,
                           sessions, logged-on users, open SMB sessions
      3. Persistence/ASEP: run keys, startup folders, scheduled tasks, services,
                           WMI event subscriptions, drivers, BITS jobs, AppInit,
                           Winlogon, LSA packages, Image File Execution Options
      4. Artifact copies : .evtx event logs, Prefetch, Amcache.hve, SRUM, registry
                           hives, PowerShell console history, hosts file, scheduled
                           task XML  (raw-copied so locked files still come across)
      5. Report          : timestamped, per-file SHA-256 manifest + an HTML summary
                           with chain-of-custody metadata.

    Everything lands in an evidence folder named:
        <Output>\<HOSTNAME>_<UTCYYYYMMDD_HHMMSS>\
    Each item is its own .txt/.csv/.json so nothing is lost if one step errors.
    The collector is read-only with respect to the endpoint (it only reads + copies).

.PARAMETER Output
    Parent folder for the evidence directory. DEFAULT: an external/removable drive if
    detected, else .\output. Point this at your collection media, NOT the suspect disk.

.PARAMETER SkipArtifactCopy
    Skip the (larger, slower) raw artifact copies; collect volatile + persistence only.

.PARAMETER MaxEventLogAgeDays
    Only copy .evtx whose LastWrite is within N days (0 = copy all). DEFAULT 0.

.EXAMPLE
    # Run elevated, from read-only media:
    powershell -ExecutionPolicy Bypass -File .\Collect-Triage.ps1 -Output E:\Evidence

.NOTES
    * Run as Administrator (SYSTEM-level reads need it). Script warns if not elevated.
    * Capture MEMORY FIRST with WinPmem (see scripts\Invoke-MemoryCapture.ps1) if RAM
      matters -- this script does not dump RAM.
    * Designed to be auditable: read it before running it on real evidence.
#>
[CmdletBinding()]
param(
    [string]$Output,
    [switch]$SkipArtifactCopy,
    [int]$MaxEventLogAgeDays = 0
)

$ErrorActionPreference = 'Continue'   # one failing collector must not abort the rest
$swTotal = [Diagnostics.Stopwatch]::StartNew()

# ---------- elevation check ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] NOT running elevated -- many artifacts (hives, SRUM, drivers) will be incomplete." -ForegroundColor Yellow
    Write-Host "    Re-launch an elevated PowerShell and re-run for a complete collection.`n" -ForegroundColor Yellow
}

# ---------- choose output ----------
if (-not $Output) {
    $removable = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
                 Where-Object { $_.DriveType -eq 2 -and $_.FreeSpace -gt 2GB } |
                 Select-Object -First 1
    $Output = if ($removable) { Join-Path $removable.DeviceID 'Evidence' } else { Join-Path $PSScriptRoot 'output' }
}
$utc      = (Get-Date).ToUniversalTime()
$stamp    = $utc.ToString('yyyyMMdd_HHmmss')
$caseDir  = Join-Path $Output ("{0}_{1}" -f $env:COMPUTERNAME, $stamp)
$volDir   = Join-Path $caseDir '01_volatile'
$persDir  = Join-Path $caseDir '02_persistence'
$artDir   = Join-Path $caseDir '03_artifacts'
$null = $volDir,$persDir,$artDir | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ }

$log = Join-Path $caseDir 'collection.log'
function Log($m){ $line="[{0:HH:mm:ss}] $m" -f (Get-Date); Write-Host $line; Add-Content -Path $log -Value $line }
function Section($n){ Write-Host "`n=== $n ===" -ForegroundColor Cyan; Log "SECTION $n" }

# Run a collector step; capture output to a file, never throw.
function Step {
    param([string]$Dir,[string]$File,[scriptblock]$Body,[string]$As='txt')
    $path = Join-Path $Dir $File
    try {
        $r = & $Body
        switch ($As) {
            'csv'  { $r | Export-Csv -NoTypeInformation -Path $path -Encoding UTF8 }
            'json' { $r | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8 }
            default{ $r | Out-String -Width 4096 | Set-Content -Path $path -Encoding UTF8 }
        }
        Log "  ok   $File"
    } catch { Log "  FAIL $File : $($_.Exception.Message)"; Set-Content -Path $path -Value "ERROR: $_" }
}

Log "Windows IR Toolkit -- live triage collector"
Log "Case dir: $caseDir"

# ============================================================ 00 CONTEXT
Section "00 Context"
Step $caseDir 'collector_self_hash.txt' { (Get-FileHash -Algorithm SHA256 $PSCommandPath).Hash + "  $PSCommandPath" }
Step $caseDir 'system_info.json' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    [pscustomobject]@{
        Hostname        = $env:COMPUTERNAME
        Domain          = $cs.Domain
        OS              = $os.Caption
        Version         = $os.Version
        Build           = $os.BuildNumber
        InstallDate     = $os.InstallDate
        LastBoot        = $os.LastBootUpTime
        CollectedUTC    = $utc.ToString('o')
        CollectorUser   = "$env:USERDOMAIN\$env:USERNAME"
        Elevated        = $isAdmin
        TimeZone        = (Get-TimeZone).Id
        UptimeHours     = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours,1)
        Manufacturer    = $cs.Manufacturer
        Model           = $cs.Model
        SerialNumber    = (Get-CimInstance Win32_BIOS).SerialNumber
    }
} json
Step $caseDir 'ipconfig_all.txt'  { ipconfig /all }
Step $caseDir 'whoami_all.txt'    { whoami /all }
Step $caseDir 'patches_qfe.csv'   { Get-CimInstance Win32_QuickFixEngineering | Select-Object HotFixID,Description,InstalledOn } csv

# ============================================================ 01 VOLATILE
Section "01 Volatile state"

Step $volDir 'processes.csv' {
    # Cache hash + signature per unique exe path -- the same binary (svchost, etc.)
    # backs many processes, so hashing once per path instead of once per process is
    # a large speedup on a busy host.
    $signs = @{}; $hashes = @{}
    Get-CimInstance Win32_Process | ForEach-Object {
        $p = $_
        $exe = $p.ExecutablePath
        $hash=$null; $sig=$null
        if ($exe -and (Test-Path $exe)) {
            if (-not $hashes.ContainsKey($exe)) {
                try { $hashes[$exe] = (Get-FileHash -Algorithm SHA256 $exe -ErrorAction Stop).Hash } catch { $hashes[$exe] = $null }
            }
            $hash = $hashes[$exe]
            try {
                if (-not $signs.ContainsKey($exe)) {
                    $s = Get-AuthenticodeSignature $exe -ErrorAction Stop
                    $signs[$exe] = "$($s.Status)/$($s.SignerCertificate.Subject)"
                }
                $sig = $signs[$exe]
            } catch {}
        }
        [pscustomobject]@{
            PID=$p.ProcessId; PPID=$p.ParentProcessId; Name=$p.Name
            CreationDate=$p.CreationDate; Path=$exe; SHA256=$hash; Signature=$sig
            CommandLine=$p.CommandLine
            Owner=$(try{ (Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop).User }catch{$null})
        }
    } | Sort-Object PID
} csv

Step $volDir 'process_tree.txt' {
    $procs    = Get-CimInstance Win32_Process
    $byParent = $procs | Group-Object ParentProcessId -AsHashTable -AsString
    $livePids = @{}; foreach ($p in $procs) { $livePids[[string]$p.ProcessId] = $true }

    # Iterative DFS with a visited-set -- NOT recursion. Windows reuses PIDs, so a
    # child's ParentProcessId can point to a since-recycled PID and form a CYCLE
    # (A->B->A); the old recursive walker followed it forever -> "call depth overflow".
    # $seen breaks cycles; visiting true roots first, then any still-unseen process,
    # guarantees every process prints exactly once even if trapped in a cycle.
    $seen  = @{}
    $out   = New-Object System.Collections.Generic.List[string]
    $order = @($procs | Where-Object { $_.ParentProcessId -eq 0 -or -not $livePids.ContainsKey([string]$_.ParentProcessId) } | Sort-Object ProcessId)
    $order += @($procs | Sort-Object ProcessId)

    foreach ($start in $order) {
        if ($seen.ContainsKey([string]$start.ProcessId)) { continue }
        $stack = New-Object System.Collections.Stack
        $stack.Push(@{ P=$start; D=0 })
        while ($stack.Count) {
            $n = $stack.Pop(); $p = $n.P; $key = [string]$p.ProcessId
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $out.Add(('  ' * $n.D) + ("{0} (PID {1})  {2}" -f $p.Name,$p.ProcessId,$p.CommandLine))
            $kids = $byParent[$key]
            if ($kids) {
                foreach ($c in ($kids | Sort-Object ProcessId -Descending)) {
                    if (-not $seen.ContainsKey([string]$c.ProcessId)) { $stack.Push(@{ P=$c; D=$n.D+1 }) }
                }
            }
        }
    }
    $out
}

Step $volDir 'netstat_connections.csv' {
    Get-NetTCPConnection -ErrorAction SilentlyContinue | ForEach-Object {
        $op = try { (Get-Process -Id $_.OwningProcess -ErrorAction Stop) } catch { $null }
        [pscustomobject]@{
            LocalAddress=$_.LocalAddress; LocalPort=$_.LocalPort
            RemoteAddress=$_.RemoteAddress; RemotePort=$_.RemotePort
            State=$_.State; PID=$_.OwningProcess
            Process=$op.Name; Path=$op.Path
        }
    } | Sort-Object State,RemoteAddress
} csv
Step $volDir 'netstat_raw.txt'      { netstat -anob }
Step $volDir 'listening_ports.csv'  { Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess } csv
Step $volDir 'dns_cache.csv'        { Get-DnsClientCache -ErrorAction SilentlyContinue | Select-Object Entry,Name,Data,Type,TimeToLive } csv
Step $volDir 'arp.txt'              { arp -a }
Step $volDir 'routes.txt'           { route print }
Step $volDir 'smb_sessions.csv'     { Get-SmbSession -ErrorAction SilentlyContinue | Select-Object ClientComputerName,ClientUserName,NumOpens } csv
Step $volDir 'smb_open_files.csv'   { Get-SmbOpenFile -ErrorAction SilentlyContinue | Select-Object ClientComputerName,ClientUserName,Path } csv
Step $volDir 'logged_on_users.txt'  { try { quser } catch { query user } }
Step $volDir 'sessions_logonsessions.csv' { Get-CimInstance Win32_LogonSession | Select-Object LogonId,LogonType,StartTime } csv
Step $volDir 'open_handles_net_use.txt' { net use }
Step $volDir 'shares.csv'           { Get-SmbShare -ErrorAction SilentlyContinue | Select-Object Name,Path,Description } csv
Step $volDir 'clipboard.txt'        { try { Get-Clipboard -Raw } catch { 'n/a' } }

# ============================================================ 02 PERSISTENCE
Section "02 Persistence / ASEP"

$runKeys = @(
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServices',
 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
)
Step $persDir 'run_keys.txt' {
    foreach ($k in $runKeys) {
        "==== $k ===="
        if (Test-Path $k) { (Get-ItemProperty $k -ErrorAction SilentlyContinue | Format-List | Out-String) } else { "(absent)" }
    }
}
Step $persDir 'startup_folders.txt' {
    $paths = @(
      "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
      "$env:AppData\Microsoft\Windows\Start Menu\Programs\Startup"
    )
    foreach ($p in $paths) { "==== $p ===="; if (Test-Path $p) { Get-ChildItem $p -Force | Format-Table -Auto | Out-String } else { "(absent)" } }
    "==== All user startup folders ===="
    Get-ChildItem 'C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\*' -Force -ErrorAction SilentlyContinue |
        Select-Object FullName,Length,LastWriteTime | Format-Table -Auto | Out-String
}
Step $persDir 'scheduled_tasks.csv' {
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $a = $_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }
        [pscustomobject]@{
            TaskName=$_.TaskName; Path=$_.TaskPath; State=$_.State
            Author=$_.Author; RunAs=$_.Principal.UserId
            Action=($a -join ' | ')
        }
    }
} csv
Step $persDir 'scheduled_tasks_detailed.txt' { schtasks /query /fo LIST /v }
Step $persDir 'services.csv' {
    Get-CimInstance Win32_Service | Select-Object Name,DisplayName,State,StartMode,StartName,PathName,Description
} csv
Step $persDir 'services_unsigned_nonstd.txt' {
    Get-CimInstance Win32_Service | Where-Object { $_.PathName -and $_.PathName -notmatch '(?i)\\windows\\' } |
        Select-Object Name,State,StartMode,PathName | Format-Table -Auto | Out-String
}
Step $persDir 'drivers.csv' {
    Get-CimInstance Win32_SystemDriver | Select-Object Name,State,StartMode,PathName | Sort-Object State
} csv
Step $persDir 'wmi_event_subscriptions.txt' {
    "==== __EventFilter ===="
    Get-CimInstance -Namespace root\subscription -Class __EventFilter -ErrorAction SilentlyContinue | Format-List Name,Query | Out-String
    "==== __EventConsumer (CommandLine/ActiveScript) ===="
    Get-CimInstance -Namespace root\subscription -Class __EventConsumer -ErrorAction SilentlyContinue | Format-List * | Out-String
    "==== __FilterToConsumerBinding ===="
    Get-CimInstance -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue | Format-List Filter,Consumer | Out-String
}
Step $persDir 'bits_jobs.txt' { try { Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Format-List * | Out-String } catch { 'n/a' } }
Step $persDir 'asep_misc.txt' {
    $extra = @(
      'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options',
      'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows',  # AppInit_DLLs
      'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa',                   # Security/Authentication packages
      'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Notify',
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects'
    )
    foreach ($k in $extra) { "==== $k ===="; if (Test-Path $k) { Get-ChildItem $k -Recurse -ErrorAction SilentlyContinue | Out-String; Get-ItemProperty $k -ErrorAction SilentlyContinue | Format-List | Out-String } else { "(absent)" } }
}
Step $persDir 'local_users_groups.txt' {
    "==== Local users ===="; Get-LocalUser -ErrorAction SilentlyContinue | Format-Table Name,Enabled,LastLogon,PasswordLastSet -Auto | Out-String
    "==== Administrators group ===="; Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Format-Table Name,PrincipalSource -Auto | Out-String
}

# ============================================================ 03 ARTIFACTS
if (-not $SkipArtifactCopy) {
    Section "03 Artifact copies"
    # Raw copy that can read locked/in-use system files (falls back to Copy-Item).
    function Copy-Raw {
        param([string]$Src,[string]$DstDir)
        try {
            if (-not (Test-Path $Src)) { return }
            $null = New-Item -ItemType Directory -Force -Path $DstDir
            $dst  = Join-Path $DstDir (Split-Path $Src -Leaf)
            $fs = [IO.File]::Open($Src,'Open','Read','ReadWrite')
            try { $out=[IO.File]::Create($dst); try { $fs.CopyTo($out) } finally { $out.Dispose() } }
            finally { $fs.Dispose() }
            Log "  copied $Src"
        } catch {
            try { Copy-Item -Path $Src -Destination $DstDir -Force -ErrorAction Stop; Log "  copied(fallback) $Src" }
            catch { Log "  LOCKED  $Src : $($_.Exception.Message)" }
        }
    }

    # Event logs
    $evtxDst = Join-Path $artDir 'EventLogs'
    $null = New-Item -ItemType Directory -Force -Path $evtxDst
    Get-ChildItem "$env:SystemRoot\System32\winevt\Logs\*.evtx" -ErrorAction SilentlyContinue |
        Where-Object { $MaxEventLogAgeDays -le 0 -or $_.LastWriteTime -ge (Get-Date).AddDays(-$MaxEventLogAgeDays) } |
        ForEach-Object { Copy-Raw $_.FullName $evtxDst }

    # Prefetch
    Get-ChildItem "$env:SystemRoot\Prefetch\*.pf" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Raw $_.FullName (Join-Path $artDir 'Prefetch')
    }

    # Amcache + registry hives + SRUM
    Copy-Raw "$env:SystemRoot\AppCompat\Programs\Amcache.hve" (Join-Path $artDir 'Amcache')
    Copy-Raw "$env:SystemRoot\System32\SRU\SRUDB.dat"         (Join-Path $artDir 'SRUM')
    foreach ($h in 'SYSTEM','SOFTWARE','SAM','SECURITY') { Copy-Raw "$env:SystemRoot\System32\config\$h" (Join-Path $artDir 'Hives') }

    # Per-user NTUSER.DAT, UsrClass.dat, PowerShell console history, recent
    Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $u = $_.Name; $udst = Join-Path $artDir "Users\$u"
        Copy-Raw "$($_.FullName)\NTUSER.DAT" $udst
        Copy-Raw "$($_.FullName)\AppData\Local\Microsoft\Windows\UsrClass.dat" $udst
        Copy-Raw "$($_.FullName)\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" (Join-Path $udst 'PSHistory')
    }

    # Scheduled task XML, hosts file
    Copy-Item "$env:SystemRoot\System32\Tasks" -Destination (Join-Path $artDir 'TasksXML') -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Raw  "$env:SystemRoot\System32\drivers\etc\hosts" (Join-Path $artDir 'Network')

    Log "Artifact copy complete."
} else { Section "03 Artifact copies"; Log "SKIPPED (-SkipArtifactCopy)" }

# ============================================================ MANIFEST + REPORT
Section "Manifest + report"
$manifest = Join-Path $caseDir 'SHA256_MANIFEST.csv'
Get-ChildItem $caseDir -Recurse -File | Where-Object { $_.FullName -ne $manifest } | ForEach-Object {
    [pscustomobject]@{
        RelPath = $_.FullName.Substring($caseDir.Length+1)
        Bytes   = $_.Length
        SHA256  = $(try { (Get-FileHash -Algorithm SHA256 $_.FullName).Hash } catch { 'ERR' })
        ModifiedUTC = $_.LastWriteTimeUtc.ToString('o')
    }
} | Export-Csv -NoTypeInformation -Path $manifest -Encoding UTF8
Log "Wrote $manifest"

$swTotal.Stop()
$fileCount = (Get-ChildItem $caseDir -Recurse -File).Count
$report = Join-Path $caseDir 'REPORT.html'
$sysInfo = Get-Content (Join-Path $caseDir 'system_info.json') -Raw
$sysInfoEnc = $sysInfo -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
@"
<!doctype html><html><head><meta charset=utf-8><title>IR Triage -- $env:COMPUTERNAME</title>
<style>body{font:14px/1.5 -apple-system,Segoe UI,Arial;margin:2em;color:#222}h1{color:#7a3ea0}
code,pre{background:#f4f4f8;padding:.2em .4em;border-radius:4px}table{border-collapse:collapse}
td,th{border:1px solid #ddd;padding:.3em .6em;text-align:left}.k{color:#666}</style></head><body>
<h1>Windows IR Triage Report</h1>
<p class=k>Generated by Collect-Triage.ps1 (Windows IR Toolkit). This is an automated COLLECTION summary,
not an analysis verdict. Review the per-section files; correlate with docs/Artifact-Reference.md.</p>
<h2>Chain of custody</h2>
<table>
<tr><th>Host</th><td>$env:COMPUTERNAME</td></tr>
<tr><th>Collected (UTC)</th><td>$($utc.ToString('o'))</td></tr>
<tr><th>Collector</th><td>$env:USERDOMAIN\$env:USERNAME (elevated=$isAdmin)</td></tr>
<tr><th>Evidence dir</th><td><code>$caseDir</code></td></tr>
<tr><th>Files collected</th><td>$fileCount</td></tr>
<tr><th>Duration</th><td>$([math]::Round($swTotal.Elapsed.TotalSeconds,1)) s</td></tr>
<tr><th>Integrity</th><td>SHA256_MANIFEST.csv (per-file hashes)</td></tr>
</table>
<h2>System</h2><pre>$sysInfoEnc</pre>
<h2>Where to look next</h2>
<ul>
<li><b>01_volatile/</b> -- processes.csv (unsigned/odd parent?), netstat_connections.csv (unexpected C2?), process_tree.txt</li>
<li><b>02_persistence/</b> -- run_keys.txt, scheduled_tasks.csv, services_unsigned_nonstd.txt, wmi_event_subscriptions.txt</li>
<li><b>03_artifacts/</b> -- parse offline with Eric Zimmerman tools / Hayabusa (see docs/Triage-Runbook.md)</li>
</ul>
<p class=k>Next: run scripts\Run-Hayabusa.ps1 against 03_artifacts\EventLogs and scripts\Scan-Yara.ps1 over the host.</p>
</body></html>
"@ | Set-Content -Path $report -Encoding UTF8

Write-Host "`n[+] DONE." -ForegroundColor Green
Write-Host "    Evidence : $caseDir"
Write-Host "    Report   : $report"
Write-Host "    Manifest : $manifest"
Write-Host "    Files    : $fileCount   Duration: $([math]::Round($swTotal.Elapsed.TotalSeconds,1))s"
Write-Host "`n[!] Verify SHA256_MANIFEST.csv and store evidence on write-protected media." -ForegroundColor Yellow
