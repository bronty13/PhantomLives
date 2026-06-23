<#
.SYNOPSIS  Run KAPE Targets (collect) then Modules (parse) for a fast triage image.
.DESCRIPTION
    KAPE is free but registration-gated, so Get-Tools.ps1 cannot fetch it
    headlessly -- download it once from Kroll and unzip into ..\tools\KAPE\
    (so that ..\tools\KAPE\kape.exe exists). This wrapper then runs the
    canonical "!SANS_Triage" target set and the EZ-tool module pack.
.PARAMETER Target   KAPE target compound (DEFAULT !SANS_Triage).
.PARAMETER Output   Destination root (DEFAULT external drive or ..\output).
.PARAMETER NoParse  Collect only; skip the Modules (parsing) pass.
.EXAMPLE  .\Invoke-KapeTriage.ps1 -Output E:\Evidence
.NOTES   Run elevated. KAPE uses VSS + raw reads to grab locked artifacts.
#>
[CmdletBinding()] param(
    [string]$Target='!SANS_Triage',
    [string]$Output,
    [switch]$NoParse
)
$ErrorActionPreference='Stop'
$kape = Join-Path $PSScriptRoot '..\tools\KAPE\kape.exe'
if (-not (Test-Path $kape)) {
    Write-Host "[x] KAPE not found at ..\tools\KAPE\kape.exe" -ForegroundColor Red
    Write-Host "    KAPE requires free registration. Download from:" -ForegroundColor Yellow
    Write-Host "    https://www.kroll.com/kape" -ForegroundColor Yellow
    Write-Host "    Unzip so that ..\tools\KAPE\kape.exe exists, then re-run." -ForegroundColor Yellow
    throw "KAPE missing."
}
if (-not $Output) {
    $rm = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    $Output = if ($rm) { Join-Path $rm.DeviceID 'Evidence' } else { Join-Path $PSScriptRoot '..\output' }
}
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
$tdest = Join-Path $Output ("{0}_kape_targets_{1}" -f $env:COMPUTERNAME,$stamp)
$mdest = Join-Path $Output ("{0}_kape_modules_{1}" -f $env:COMPUTERNAME,$stamp)
$null = New-Item -ItemType Directory -Force -Path $tdest

Write-Host "[*] KAPE collecting target '$Target' -> $tdest" -ForegroundColor Cyan
$kargs = @('--tsource','C:','--tdest',$tdest,'--target',$Target,'--vss','--zip',("Triage_{0}" -f $stamp))
if (-not $NoParse) { $kargs += @('--mdest',$mdest,'--module','!EZParser','--mflush') }
& $kape @kargs
Write-Host "[+] KAPE done. Targets: $tdest" -ForegroundColor Green
if (-not $NoParse) { Write-Host "[+] Parsed output (open CSVs in Timeline Explorer): $mdest" -ForegroundColor Green }
