<#
.SYNOPSIS
    One-shot IR triage orchestrator: RAM capture -> live collection -> hunting,
    all into a single timestamped case folder, in the correct order of volatility.

.DESCRIPTION
    Chains the toolkit's pieces so a first responder runs ONE command:

      1. MEMORY   -> scripts\Invoke-MemoryCapture.ps1   (WinPmem, if present)
      2. COLLECT  -> Collect-Triage.ps1                 (volatile + persistence + artifacts)
      3. HUNT     -> scripts\Run-Hayabusa.ps1           (Sigma over collected EVTX)
                     scripts\Scan-Yara.ps1              (YARA over user dirs)
                     scripts\Invoke-VelociraptorTriage  (optional, -IncludeVelociraptor)
      4. SUMMARY  -> TRIAGE_SUMMARY.txt + master SHA-256 manifest of the case root

    Every artifact lands under  <Output>\<HOST>_TRIAGE_<UTCstamp>\ .
    Each stage is independent: a missing tool or a failing stage is logged and the
    run CONTINUES (you still get whatever the other stages produced). Stages that
    need a downloaded tool are skipped with a clear note if that tool is absent --
    the dependency-free COLLECT stage always runs.

.PARAMETER Output
    Parent folder for the case directory. DEFAULT: a removable drive if detected,
    else .\output. Point this at your collection media, NOT the suspect disk.

.PARAMETER SkipMemory     Skip RAM capture (e.g. RAM irrelevant, or no WinPmem).
.PARAMETER SkipHunt       Skip the Hayabusa/YARA hunting stage (collect only).
.PARAMETER IncludeVelociraptor  Also run the broad Velociraptor collection.
.PARAMETER Quick          Fast pass: no memory, COLLECT with -SkipArtifactCopy, no hunt.
.PARAMETER YaraPath       Path(s) for the YARA stage (DEFAULT C:\Users).
.PARAMETER Force          Don't prompt for the authorization confirmation.

.EXAMPLE
    # Full triage to removable media (elevated):
    powershell -ExecutionPolicy Bypass -File .\Run-Triage.ps1 -Output E:\Evidence

.EXAMPLE
    # Fast volatile-only sweep, no prompts:
    .\Run-Triage.ps1 -Quick -Force

.NOTES
    Run as Administrator from read-only media; write output to SEPARATE media.
    This orchestrator only reads/copies from the endpoint (the stages it calls do).
#>
[CmdletBinding()]
param(
    [string]$Output,
    [switch]$SkipMemory,
    [switch]$SkipHunt,
    [switch]$IncludeVelociraptor,
    [switch]$Quick,
    [string[]]$YaraPath,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$here   = $PSScriptRoot
$swAll  = [Diagnostics.Stopwatch]::StartNew()
$utc    = (Get-Date).ToUniversalTime()
$stamp  = $utc.ToString('yyyyMMdd_HHmmss')

# -------- elevation --------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ""
Write-Host "  ===============================================" -ForegroundColor Magenta
Write-Host "   Windows IR Toolkit -- one-shot triage runner"   -ForegroundColor Magenta
Write-Host "  ===============================================" -ForegroundColor Magenta
Write-Host "   Host : $env:COMPUTERNAME    User: $env:USERDOMAIN\$env:USERNAME    Elevated: $isAdmin"
Write-Host ""

if (-not $isAdmin) {
    Write-Host "[!] NOT elevated -- memory capture and several artifacts will be incomplete." -ForegroundColor Yellow
    Write-Host "    Strongly recommend re-launching an elevated PowerShell.`n" -ForegroundColor Yellow
}

# -------- authorization gate --------
if (-not $Force) {
    Write-Host "[?] Confirm you are AUTHORIZED to triage this host and to write evidence to the output media." -ForegroundColor Cyan
    $ans = Read-Host "    Type 'yes' to proceed"
    if ($ans -ne 'yes') { Write-Host "[x] Aborted (no confirmation)." -ForegroundColor Red; return }
}

# -------- output / case dir --------
if (-not $Output) {
    $rm = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
          Where-Object { $_.DriveType -eq 2 -and $_.FreeSpace -gt 2GB } | Select-Object -First 1
    $Output = if ($rm) { Join-Path $rm.DeviceID 'Evidence' } else { Join-Path $here 'output' }
}
$caseRoot = Join-Path $Output ("{0}_TRIAGE_{1}" -f $env:COMPUTERNAME, $stamp)
$null = New-Item -ItemType Directory -Force -Path $caseRoot
$huntDir = Join-Path $caseRoot 'hunt'

$masterLog = Join-Path $caseRoot 'run-triage.log'
function Log($m){ $l = "[{0:HH:mm:ss}] $m" -f (Get-Date); Write-Host $l; Add-Content -Path $masterLog -Value $l }
function Banner($n){ Write-Host "`n----- $n -----" -ForegroundColor Cyan; Log "STAGE $n" }

# Stage results table for the summary
$stages = [System.Collections.Generic.List[object]]::new()
function Record($name,$status,$detail){ $stages.Add([pscustomobject]@{ Stage=$name; Status=$status; Detail=$detail }) }

# Helper: is a downloaded tool present?
function Have-Tool($subdir,$filter){
    Get-ChildItem (Join-Path $here "tools\$subdir") -Recurse -Filter $filter -ErrorAction SilentlyContinue | Select-Object -First 1
}

Log "Case root: $caseRoot"
Log ("Options: SkipMemory=$SkipMemory SkipHunt=$SkipHunt Quick=$Quick Velociraptor=$IncludeVelociraptor")
if ($Quick) { Log "Quick mode -> forcing SkipMemory + SkipHunt + collect -SkipArtifactCopy"; $SkipMemory=$true; $SkipHunt=$true }

# =================================================== STAGE 1: MEMORY
Banner "1/4 MEMORY"
if ($SkipMemory) {
    Log "  skipped (SkipMemory/Quick)"; Record 'Memory' 'SKIPPED' 'by switch'
} elseif (-not $isAdmin) {
    Log "  skipped -- requires Administrator"; Record 'Memory' 'SKIPPED' 'not elevated'
} elseif (-not ((Have-Tool 'DumpIt' 'DumpIt.exe') -or (Have-Tool 'WinPmem' '*pmem*.exe'))) {
    Log "  skipped -- no memory acquirer (install DumpIt for all arches, or WinPmem for x86/x64)"; Record 'Memory' 'SKIPPED' 'no acquirer'
} else {
    $sw=[Diagnostics.Stopwatch]::StartNew()
    try {
        & (Join-Path $here 'scripts\Invoke-MemoryCapture.ps1') -Output $caseRoot
        # DumpIt writes .dmp (crash dump), WinPmem writes .raw -- accept either.
        $img = Get-ChildItem $caseRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '_memory_.*\.(raw|dmp)$' } | Select-Object -First 1
        if ($img) { Log "  OK -> $($img.Name) ($([math]::Round($img.Length/1GB,2)) GB)"; Record 'Memory' 'OK' $img.Name }
        else { Log "  WARN -- no image produced"; Record 'Memory' 'WARN' 'no image' }
    } catch { Log "  FAIL -- $($_.Exception.Message)"; Record 'Memory' 'FAIL' $_.Exception.Message }
    Log ("  ({0}s)" -f [math]::Round($sw.Elapsed.TotalSeconds,1))
}

# =================================================== STAGE 2: COLLECT (always)
Banner "2/4 COLLECT (volatile + persistence + artifacts)"
$evidenceDir = $null
$before = Get-ChildItem $caseRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
$sw=[Diagnostics.Stopwatch]::StartNew()
try {
    $collectArgs = @{ Output = $caseRoot }
    if ($Quick) { $collectArgs['SkipArtifactCopy'] = $true }
    & (Join-Path $here 'Collect-Triage.ps1') @collectArgs
    # The collector creates <HOST>_<stamp>\ under $caseRoot -- find the new one.
    $after = Get-ChildItem $caseRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    $new = $after | Where-Object { $before -notcontains $_ -and (Split-Path $_ -Leaf) -ne 'hunt' }
    $evidenceDir = $new | Sort-Object { (Get-Item $_).LastWriteTime } | Select-Object -Last 1
    if ($evidenceDir) { Log "  OK -> $(Split-Path $evidenceDir -Leaf)"; Record 'Collect' 'OK' (Split-Path $evidenceDir -Leaf) }
    else { Log "  WARN -- could not locate evidence dir"; Record 'Collect' 'WARN' 'no evidence dir found' }
} catch { Log "  FAIL -- $($_.Exception.Message)"; Record 'Collect' 'FAIL' $_.Exception.Message }
Log ("  ({0}s)" -f [math]::Round($sw.Elapsed.TotalSeconds,1))

# =================================================== STAGE 3: HUNT
Banner ("3/4 HUNT (Hayabusa + YARA" + $(if($IncludeVelociraptor){' + Velociraptor'} else {''}) + ")")
if ($SkipHunt) {
    Log "  skipped (SkipHunt/Quick)"; Record 'Hunt' 'SKIPPED' 'by switch'
} else {
    $null = New-Item -ItemType Directory -Force -Path $huntDir

    # --- Hayabusa over collected EVTX ---
    $evtxDir = if ($evidenceDir) { Join-Path $evidenceDir '03_artifacts\EventLogs' } else { $null }
    if (-not (Have-Tool 'Hayabusa' 'hayabusa*.exe')) {
        Log "  Hayabusa: skipped (not downloaded)"; Record 'Hunt:Hayabusa' 'SKIPPED' 'tool absent'
    } elseif (-not ($evtxDir -and (Test-Path $evtxDir))) {
        Log "  Hayabusa: skipped (no collected EventLogs -- try without -Quick)"; Record 'Hunt:Hayabusa' 'SKIPPED' 'no EVTX'
    } else {
        try {
            $hbOut = Join-Path $huntDir 'hayabusa_timeline.csv'
            & (Join-Path $here 'scripts\Run-Hayabusa.ps1') -LogDir $evtxDir -Output $hbOut
            if (Test-Path $hbOut) {
                $n = (Import-Csv $hbOut -ErrorAction SilentlyContinue | Measure-Object).Count
                Log "  Hayabusa: OK -> $n detection rows (hunt\hayabusa_timeline.csv)"; Record 'Hunt:Hayabusa' 'OK' "$n rows"
            } else { Record 'Hunt:Hayabusa' 'WARN' 'no csv' }
        } catch { Log "  Hayabusa: FAIL -- $($_.Exception.Message)"; Record 'Hunt:Hayabusa' 'FAIL' $_.Exception.Message }
    }

    # --- YARA over user dirs ---
    $rules = Get-ChildItem (Join-Path $here 'iocs\yara') -Recurse -Include '*.yar','*.yara' -ErrorAction SilentlyContinue
    if (-not (Have-Tool 'YARA' 'yara*.exe')) {
        Log "  YARA: skipped (not downloaded)"; Record 'Hunt:YARA' 'SKIPPED' 'tool absent'
    } elseif (-not $rules) {
        Log "  YARA: skipped (no rules in iocs\yara)"; Record 'Hunt:YARA' 'SKIPPED' 'no rules'
    } else {
        try {
            if (-not $YaraPath) { $YaraPath = @('C:\Users') }
            $yOut = Join-Path $huntDir 'yara_matches.csv'
            & (Join-Path $here 'scripts\Scan-Yara.ps1') -Path $YaraPath -Output $yOut
            $n = if (Test-Path $yOut) { (Import-Csv $yOut -ErrorAction SilentlyContinue | Measure-Object).Count } else { 0 }
            Log "  YARA: OK -> $n match line(s) (hunt\yara_matches.csv)"; Record 'Hunt:YARA' 'OK' "$n matches"
        } catch { Log "  YARA: FAIL -- $($_.Exception.Message)"; Record 'Hunt:YARA' 'FAIL' $_.Exception.Message }
    }

    # --- Velociraptor (optional) ---
    if ($IncludeVelociraptor) {
        if (-not (Have-Tool 'Velociraptor' 'velociraptor*.exe')) {
            Log "  Velociraptor: skipped (not downloaded)"; Record 'Hunt:Velociraptor' 'SKIPPED' 'tool absent'
        } else {
            try {
                & (Join-Path $here 'scripts\Invoke-VelociraptorTriage.ps1') -Output $caseRoot
                Record 'Hunt:Velociraptor' 'OK' 'collection zip in case root'
            } catch { Log "  Velociraptor: FAIL -- $($_.Exception.Message)"; Record 'Hunt:Velociraptor' 'FAIL' $_.Exception.Message }
        }
    }
}

# =================================================== STAGE 4: SUMMARY + MANIFEST
Banner "4/4 SUMMARY"
$swAll.Stop()

# Master manifest: hash everything under the case root EXCEPT very large images
# (those already carry a .sha256 sidecar from their wrapper) to keep this fast.
$manifest = Join-Path $caseRoot 'CASE_SHA256_MANIFEST.csv'
$rows = [System.Collections.Generic.List[object]]::new()
Get-ChildItem $caseRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -ne $manifest } | ForEach-Object {
    $h = if ($_.Length -gt 1GB) { '(skipped >1GB -- see .sha256 sidecar)' }
         else { try { (Get-FileHash -Algorithm SHA256 $_.FullName).Hash } catch { 'ERR' } }
    $rows.Add([pscustomobject]@{
        RelPath=$_.FullName.Substring($caseRoot.Length+1); Bytes=$_.Length
        SHA256=$h; ModifiedUTC=$_.LastWriteTimeUtc.ToString('o') })
  }
$rows | Export-Csv -NoTypeInformation -Path $manifest -Encoding UTF8

$fileCount = $rows.Count
$summary = Join-Path $caseRoot 'TRIAGE_SUMMARY.txt'
$lines = @()
$lines += "Windows IR Toolkit -- Triage Summary"
$lines += "===================================="
$lines += "Host          : $env:COMPUTERNAME"
$lines += "Collected UTC : $($utc.ToString('o'))"
$lines += "Collector     : $env:USERDOMAIN\$env:USERNAME  (elevated=$isAdmin)"
$lines += "Case root     : $caseRoot"
$lines += "Files in case : $fileCount"
$lines += "Total runtime : $([math]::Round($swAll.Elapsed.TotalMinutes,1)) min"
$lines += ""
$lines += "Stages:"
foreach ($s in $stages) { $lines += ("  {0,-22} {1,-8} {2}" -f $s.Stage, $s.Status, $s.Detail) }
$lines += ""
$lines += "Key outputs:"
if ($evidenceDir) {
    $lines += "  Report      : $(Join-Path (Split-Path $evidenceDir -Leaf) 'REPORT.html')"
    $lines += "  Volatile    : $(Join-Path (Split-Path $evidenceDir -Leaf) '01_volatile')"
    $lines += "  Persistence : $(Join-Path (Split-Path $evidenceDir -Leaf) '02_persistence')"
    $lines += "  Artifacts   : $(Join-Path (Split-Path $evidenceDir -Leaf) '03_artifacts')"
}
if (Test-Path $huntDir) { $lines += "  Hunt        : hunt\  (hayabusa_timeline.csv, yara_matches.csv)" }
$lines += "  Integrity   : CASE_SHA256_MANIFEST.csv  (+ per-stage manifests/sidecars)"
$lines += ""
$lines += "Next steps (see docs\Triage-Runbook.md):"
$lines += "  1. Open REPORT.html; skim 01_volatile\processes.csv + netstat_connections.csv."
$lines += "  2. Review 02_persistence (run_keys, scheduled_tasks, wmi_event_subscriptions)."
$lines += "  3. Sort hunt\hayabusa_timeline.csv by Level (critical/high first)."
$lines += "  4. Deep parse offline: scripts\Parse-Artifacts.ps1 -ArtifactDir <evidence>\03_artifacts."
$lines += "  5. Memory: vol -f <case>\*_memory_*.raw windows.pstree   (docs\Memory-Forensics.md)."
$lines += "  6. Record actions + findings in docs\Chain-of-Custody-template.md."
$lines -join "`r`n" | Set-Content -Path $summary -Encoding UTF8

Write-Host ""
Write-Host "  =================== TRIAGE COMPLETE ===================" -ForegroundColor Green
foreach ($s in $stages) {
    $c = switch ($s.Status) { 'OK' {'Green'} 'SKIPPED' {'DarkGray'} 'WARN' {'Yellow'} default {'Red'} }
    Write-Host ("   {0,-22} {1}" -f $s.Stage, $s.Status) -ForegroundColor $c
}
Write-Host "  ------------------------------------------------------"
Write-Host "   Case root : $caseRoot"
Write-Host "   Summary   : $summary"
Write-Host "   Manifest  : $manifest"
Write-Host "   Runtime   : $([math]::Round($swAll.Elapsed.TotalMinutes,1)) min   Files: $fileCount" -ForegroundColor Green
Write-Host ""
Write-Host "  [!] Store the case folder on write-protected media; verify the manifest." -ForegroundColor Yellow
