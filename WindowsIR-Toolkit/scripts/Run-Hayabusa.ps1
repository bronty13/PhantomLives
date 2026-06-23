<#
.SYNOPSIS  Run Hayabusa (Sigma-based EVTX hunter) over collected event logs -> CSV timeline.
.DESCRIPTION
    Points Hayabusa at a directory of .evtx files (e.g. an evidence folder's
    03_artifacts\EventLogs, or live C:\Windows\System32\winevt\Logs) and produces
    a deduplicated, severity-ranked detection CSV you can open in Timeline Explorer
    or Excel. Hayabusa is downloaded by Get-Tools.ps1 into ..\tools\Hayabusa\.
.PARAMETER LogDir   Folder containing .evtx (DEFAULT: live winevt\Logs).
.PARAMETER Output   CSV path (DEFAULT: .\output\hayabusa_<stamp>.csv).
.PARAMETER Live     Hunt the live system logs instead of a folder.
.EXAMPLE  .\Run-Hayabusa.ps1 -LogDir E:\Evidence\HOST_..\03_artifacts\EventLogs
.EXAMPLE  .\Run-Hayabusa.ps1 -Live
#>
[CmdletBinding()] param([string]$LogDir,[string]$Output,[switch]$Live)

$ErrorActionPreference='Stop'
$hb = Get-ChildItem (Join-Path $PSScriptRoot '..\tools\Hayabusa') -Recurse -Filter 'hayabusa*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $hb) { throw "Hayabusa not found. Run Get-Tools.ps1 -Only Hayabusa first (https://github.com/Yamato-Security/hayabusa)." }

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
if (-not $Output) { $Output = Join-Path $PSScriptRoot ("..\output\hayabusa_{0}.csv" -f $stamp) }
$null = New-Item -ItemType Directory -Force -Path (Split-Path $Output)

# Refresh bundled Sigma rules (best effort; needs internet)
try { & $hb.FullName update-rules 2>$null } catch {}

$common = @('csv-timeline','-o',$Output,'-p','verbose','--no-wizard','-C')  # --no-wizard = non-interactive (-w is its short alias; don't pass both), -C = clobber/overwrite
if ($Live) {
    Write-Host "[*] Hayabusa hunting LIVE event logs (Administrator recommended)..." -ForegroundColor Cyan
    & $hb.FullName @common '-l'
} else {
    if (-not $LogDir) { $LogDir = "$env:SystemRoot\System32\winevt\Logs" }
    if (-not (Test-Path $LogDir)) { throw "LogDir not found: $LogDir" }
    Write-Host "[*] Hayabusa scanning $LogDir ..." -ForegroundColor Cyan
    & $hb.FullName @common '-d' $LogDir
}
Write-Host "[+] Detection timeline: $Output" -ForegroundColor Green
Write-Host "[!] Open in Timeline Explorer (EZ tools) and sort by Level=critical/high first." -ForegroundColor Yellow
