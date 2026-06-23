<#
.SYNOPSIS  Offline-parse a collected artifact folder with Eric Zimmerman tools -> CSV.
.DESCRIPTION
    Drives the EZ tool suite over an evidence folder (e.g. the 03_artifacts tree
    from Collect-Triage.ps1, or a KAPE/Velociraptor collection) and writes parsed
    CSVs you can sort in Timeline Explorer. Handles: $MFT, Prefetch, Amcache,
    AppCompatCache (Shimcache), SRUM, registry hives (RECmd), EVTX (EvtxECmd),
    LNK/JumpLists. EZ tools come from Get-Tools.ps1 (run its self-updater first):
        .\tools\EricZimmermanTools\Get-ZimmermanTools.ps1 -Dest .\tools\EricZimmermanTools
.PARAMETER ArtifactDir  Root of collected artifacts (searched recursively).
.PARAMETER Output       CSV output root (DEFAULT ..\output\parsed_<stamp>).
.EXAMPLE  .\Parse-Artifacts.ps1 -ArtifactDir E:\Evidence\HOST_..\03_artifacts
.NOTES   This is the DEAD-DISK / offline analysis path. No endpoint access needed.
#>
[CmdletBinding()] param(
    [Parameter(Mandatory)][string]$ArtifactDir,
    [string]$Output
)
$ErrorActionPreference='Continue'
$ez = Join-Path $PSScriptRoot '..\tools\EricZimmermanTools'
function Find-EZ($name){ Get-ChildItem $ez -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1 }

$stamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
if (-not $Output) { $Output = Join-Path $PSScriptRoot ("..\output\parsed_{0}" -f $stamp) }
$null = New-Item -ItemType Directory -Force -Path $Output
function OutDir($n){ $p=Join-Path $Output $n; $null=New-Item -ItemType Directory -Force -Path $p; $p }

$jobs = @(
  @{ Tool='MFTECmd.exe';            Find='$MFT';          Args={param($f,$o) @('-f',$f,'--csv',$o,'--csvf','mft.csv')} ; Label='$MFT' },
  @{ Tool='PECmd.exe';              Find='*.pf';          Dir=$true; Args={param($d,$o) @('-d',$d,'--csv',$o)} ; Label='Prefetch' },
  @{ Tool='AmcacheParser.exe';      Find='Amcache.hve';   Args={param($f,$o) @('-f',$f,'--csv',$o,'-i')} ; Label='Amcache' },
  @{ Tool='AppCompatCacheParser.exe';Find='SYSTEM';       Args={param($f,$o) @('-f',$f,'--csv',$o,'--csvf','shimcache.csv')} ; Label='Shimcache(SYSTEM)' },
  @{ Tool='SrumECmd.exe';           Find='SRUDB.dat';     Args={param($f,$o) @('-f',$f,'--csv',$o)} ; Label='SRUM' },
  @{ Tool='EvtxECmd.exe';           Find='*.evtx';        Dir=$true; Args={param($d,$o) @('-d',$d,'--csv',$o,'--csvf','events.csv')} ; Label='EVTX' }
)

foreach ($j in $jobs) {
    $tool = Find-EZ $j.Tool
    if (-not $tool) { Write-Host "[!] $($j.Tool) not present -- skipping $($j.Label). (run Get-ZimmermanTools.ps1)" -ForegroundColor Yellow; continue }
    $od = OutDir ($j.Label -replace '[^\w]','_')
    if ($j.Dir) {
        $src = Get-ChildItem $ArtifactDir -Recurse -Filter $j.Find -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName
        if (-not $src) { Write-Host "[!] No $($j.Find) under $ArtifactDir -- skip $($j.Label)." -ForegroundColor Yellow; continue }
        Write-Host "[*] $($j.Label): $($tool.Name) on $src" -ForegroundColor Cyan
        & $tool.FullName @(& $j.Args $src $od)
    } else {
        $src = Get-ChildItem $ArtifactDir -Recurse -Filter $j.Find -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $src) { Write-Host "[!] No $($j.Find) under $ArtifactDir -- skip $($j.Label)." -ForegroundColor Yellow; continue }
        Write-Host "[*] $($j.Label): $($tool.Name) on $($src.FullName)" -ForegroundColor Cyan
        & $tool.FullName @(& $j.Args $src.FullName $od)
    }
}

# RECmd batch over hives (uses the BatchExamples that ship with RECmd)
$recmd = Find-EZ 'RECmd.exe'
$hive  = Get-ChildItem $ArtifactDir -Recurse -Filter 'NTUSER.DAT' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($recmd -and $hive) {
    $batch = Get-ChildItem (Split-Path $recmd.FullName) -Recurse -Filter 'Kroll_Batch.reb' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($batch) {
        $od = OutDir 'Registry_RECmd'
        Write-Host "[*] RECmd Kroll_Batch over hives under $ArtifactDir" -ForegroundColor Cyan
        & $recmd.FullName --bn $batch.FullName -d (Split-Path $hive.FullName) --csv $od
    }
}
Write-Host "[+] Parsed CSVs under: $Output" -ForegroundColor Green
Write-Host "[!] Open the folder in Timeline Explorer (EZ tools) for fast filtering/sorting." -ForegroundColor Yellow
