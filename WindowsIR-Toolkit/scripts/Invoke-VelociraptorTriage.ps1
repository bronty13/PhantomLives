<#
.SYNOPSIS  Run a standalone Velociraptor offline-collection over the live endpoint.
.DESCRIPTION
    Velociraptor's single .exe can collect a broad, curated triage set
    (Windows.KapeFiles.Targets, processes, autoruns, EVTX, etc.) into one
    zip with no server. This wrapper invokes the bundled artifact pack with
    sensible defaults. Velociraptor is downloaded by Get-Tools.ps1 into
    ..\tools\Velociraptor\.

    For a FULLY pre-configured offline collector (recommended for repeatable
    field use), build one once via the GUI:
        velociraptor.exe gui   ->  Server Artifacts -> Offline collector
    and carry the generated Collector_*.exe. This script is the quick path.
.PARAMETER Output   Folder for the collection zip (DEFAULT external drive or ..\output).
.PARAMETER Artifact Velociraptor artifact to run (DEFAULT Windows.KapeFiles.Targets w/ _BasicCollection).
.EXAMPLE  .\Invoke-VelociraptorTriage.ps1 -Output E:\Evidence
.NOTES   Run elevated. Apache-2.0, fully redistributable.
#>
[CmdletBinding()] param(
    [string]$Output,
    [string]$Artifact = 'Windows.KapeFiles.Targets'
)
$ErrorActionPreference='Stop'
$vr = Get-ChildItem (Join-Path $PSScriptRoot '..\tools\Velociraptor') -Filter 'velociraptor*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $vr) { throw "Velociraptor not found. Run Get-Tools.ps1 -Only Velociraptor first (https://github.com/Velocidex/velociraptor)." }

if (-not $Output) {
    $rm = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    $Output = if ($rm) { Join-Path $rm.DeviceID 'Evidence' } else { Join-Path $PSScriptRoot '..\output' }
}
$null = New-Item -ItemType Directory -Force -Path $Output
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
$zip = Join-Path $Output ("{0}_velociraptor_{1}.zip" -f $env:COMPUTERNAME,$stamp)

Write-Host "[*] Velociraptor collecting artifact '$Artifact' -> $zip" -ForegroundColor Cyan
# 'collect' runs artifacts without a server. _BasicCollection target group keeps it fast.
& $vr.FullName artifacts collect $Artifact `
    --args "Device=C:" `
    --args "VSSAnalysisAge=0" `
    --output $zip
if (Test-Path $zip) {
    $h = (Get-FileHash -Algorithm SHA256 $zip).Hash
    "$h  $(Split-Path $zip -Leaf)" | Set-Content "$zip.sha256"
    Write-Host "[+] Collection: $zip  (SHA256 $h)" -ForegroundColor Green
} else { Write-Host "[!] No zip produced -- check artifact name with: velociraptor artifacts list" -ForegroundColor Yellow }
Write-Host "[!] Tip: build a reusable offline collector via 'velociraptor.exe gui' for field kits." -ForegroundColor Yellow
