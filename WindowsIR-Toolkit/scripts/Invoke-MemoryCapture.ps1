<#
.SYNOPSIS  Acquire physical memory (RAM) to external media + hash it, on x86/x64/ARM64.
.DESCRIPTION
    Memory is the MOST volatile evidence -- capture it FIRST, before any other
    triage that spawns processes. This wrapper is ARCHITECTURE-AWARE:

      * Magnet DumpIt for Windows (tools\DumpIt\) -- PREFERRED. The only free tool
        that covers x86, x64 AND ARM64; ships a signed kernel driver per arch and
        writes a Microsoft crash dump (.dmp, WinDbg + Volatility 3 readable).
        Registration-gated download: Get-Tools.ps1 -IncludeManualRegistration.
      * WinPmem (tools\WinPmem\) -- FALLBACK, x86/x64 ONLY. WinPmem has no ARM64
        driver, so it is never used on ARM64. Prefer the Go build
        (go-winpmem_*_signed.exe); the legacy winpmem_mini_x64_rc2.exe writes a
        0-byte image on modern Win10/11 (Velocidex issue #55).

    On an ARM64 host with no DumpIt present, this FAILS FAST with instructions
    rather than letting an x64 WinPmem driver fail to load on the ARM64 kernel.
.PARAMETER Output  Folder for the image (DEFAULT external drive or .\output). Point at REMOVABLE media.
.EXAMPLE  .\Invoke-MemoryCapture.ps1 -Output E:\Evidence
.NOTES   Run elevated. RAM image will be ~= physical RAM size; ensure free space.
#>
[CmdletBinding()] param([string]$Output)

$ErrorActionPreference='Stop'

# ---- Administrator (use the ENUM overload; the string 'Administrator' matches the
# built-in *user*, not the Administrators *group*, and returns $false even when elevated). ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Memory capture requires Administrator." }

# ---- OS architecture (NOT the PowerShell process arch -- an x64 PS can run emulated
# on ARM64; we need the driver target, which is the OS arch). ----
function Get-OSArch {
    $a = $null
    try { $a = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() } catch {}
    if (-not $a) { $a = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }
    switch -Regex ($a) { 'Arm64' {'ARM64';break} 'X64|AMD64' {'X64';break} 'X86' {'X86';break} default { $a.ToUpper() } }
}
$arch = Get-OSArch
Write-Host "[*] Host architecture: $arch" -ForegroundColor Cyan

# ---- Resolve DumpIt for this arch (Magnet ships per-arch binaries, commonly under
# tools\DumpIt\<ARM64|x64|x86>\DumpIt.exe; a single DumpIt.exe also works). ----
$archTokens = switch ($arch) { 'ARM64' {@('arm64','arm')} 'X64' {@('x64','amd64','x86_64')} 'X86' {@('x86')} default {@()} }
$dumpitAll  = Get-ChildItem (Join-Path $PSScriptRoot '..\tools\DumpIt') -Recurse -Filter 'DumpIt.exe' -ErrorAction SilentlyContinue
$dumpit = $null
foreach ($tok in $archTokens) { $dumpit = $dumpitAll | Where-Object { $_.FullName -match [Regex]::Escape($tok) } | Select-Object -First 1; if ($dumpit) { break } }
if (-not $dumpit -and $dumpitAll.Count -eq 1) { $dumpit = $dumpitAll[0] }  # single-binary layout

# ---- Resolve WinPmem (x86/x64 only); prefer the Go build over the broken mini. ----
$pmem     = Get-ChildItem (Join-Path $PSScriptRoot '..\tools\WinPmem') -Filter '*pmem*.exe' -ErrorAction SilentlyContinue
$pmemTool = $pmem | Where-Object { $_.Name -match 'go-winpmem' } | Select-Object -First 1
if (-not $pmemTool) { $pmemTool = $pmem | Select-Object -First 1 }

# ---- Pick an engine. DumpIt wins (all arches); WinPmem only on x86/x64. ----
if     ($dumpit)                                  { $engine='DumpIt';  $tool=$dumpit }
elseif ($arch -in @('X64','X86') -and $pmemTool)  { $engine='WinPmem'; $tool=$pmemTool }
elseif ($arch -eq 'ARM64') {
    throw "ARM64 host and no DumpIt found. WinPmem has NO ARM64 driver, so it cannot capture RAM here. Install Magnet DumpIt for Windows (Get-Tools.ps1 -IncludeManualRegistration) and place the ARM64 build at tools\DumpIt\ARM64\DumpIt.exe."
}
else {
    throw "No memory acquirer found. Install Magnet DumpIt (tools\DumpIt\, all arches) or, on x86/x64, WinPmem (Get-Tools.ps1 -Only WinPmem)."
}
$isGoPmem = ($engine -eq 'WinPmem') -and ($tool.Name -match 'go-winpmem')
if ($engine -eq 'WinPmem' -and -not $isGoPmem) {
    Write-Host "[!] Using legacy winpmem_mini ($($tool.Name)) -- known to emit a 0-byte image on modern Windows (issue #55). Prefer go-winpmem or DumpIt." -ForegroundColor Yellow
}

# ---- Output path. DumpIt writes a Microsoft crash dump (.dmp); WinPmem writes raw (.raw). ----
if (-not $Output) {
    $rm = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    $Output = if ($rm) { Join-Path $rm.DeviceID 'Evidence' } else { Join-Path $PSScriptRoot '..\output' }
}
$null  = New-Item -ItemType Directory -Force -Path $Output
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
$ext   = if ($engine -eq 'DumpIt') { 'dmp' } else { 'raw' }
$img   = Join-Path $Output ("{0}_memory_{1}.{2}" -f $env:COMPUTERNAME,$stamp,$ext)

Write-Host "[*] Capturing RAM with $engine ($($tool.Name)) -> $img" -ForegroundColor Cyan
# Argv per engine:
#   DumpIt   : /O <file> /Q   -> non-interactive Microsoft crash dump
#   go-winpmem: acquire --progress <file>   (subcommand + positional)
#   winpmem_mini: <file>      (bare positional)
$capArgs = switch ($engine) {
    'DumpIt'  { @('/O', $img, '/Q') }
    'WinPmem' { if ($isGoPmem) { @('acquire','--progress',$img) } else { @($img) } }
}
$out  = & $tool.FullName @capArgs 2>&1
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Host "    $_" }

# Native tools don't trip ErrorActionPreference='Stop' on a non-zero exit -- check it.
if ($code -ne 0)            { throw "$engine exited $code. Output:`n$($out -join "`n")" }
if (-not (Test-Path $img))  { throw "$engine produced no image (exit $code)." }
# Reject a 0-byte / truncated image -- otherwise it passes Test-Path and gets hashed as a
# 'successful' empty capture. A real RAM image is at least hundreds of MB.
$len = (Get-Item $img).Length
if ($len -lt 1MB) {
    Remove-Item $img -Force -ErrorAction SilentlyContinue
    $hint = if ($engine -eq 'WinPmem') { " (legacy winpmem_mini RC2 0-byte failure, Velocidex issue #55 -- use go-winpmem or DumpIt)" } else { "" }
    throw "$engine wrote a truncated image ($len bytes)$hint."
}

Write-Host "[*] Hashing image (this takes a while for large RAM)..." -ForegroundColor Cyan
$h = (Get-FileHash -Algorithm SHA256 $img).Hash
"$h  $(Split-Path $img -Leaf)" | Set-Content "$img.sha256"
Write-Host "[+] Memory image: $img  ($([math]::Round($len/1GB,2)) GB)" -ForegroundColor Green
Write-Host "[+] SHA256: $h"
Write-Host "[!] Analyze with Volatility 3:  vol -f `"$img`" windows.pslist / windows.netscan / windows.malfind" -ForegroundColor Yellow
if ($ext -eq 'dmp') { Write-Host "[!] (.dmp is a Microsoft crash dump -- also opens in WinDbg.)" -ForegroundColor Yellow }
