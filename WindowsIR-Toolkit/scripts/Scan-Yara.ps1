<#
.SYNOPSIS  YARA-scan a path (or running processes) against rules in ..\iocs\yara.
.DESCRIPTION
    Recursively scans a directory tree -- or, with -Processes, every running
    process's memory -- against compiled/loose YARA rules. Findings -> CSV/console.
    YARA is downloaded by Get-Tools.ps1 into ..\tools\YARA\; drop .yar rules into
    ..\iocs\yara\ (the toolkit ships a starter set + a README on sourcing more).
.PARAMETER Path       Directory to scan (DEFAULT C:\Users + C:\ProgramData + %TEMP%).
.PARAMETER RulesDir   Folder of .yar/.yara rules (DEFAULT ..\iocs\yara).
.PARAMETER Processes  Scan live process memory instead of files.
.PARAMETER Output     CSV path for matches.
.EXAMPLE  .\Scan-Yara.ps1 -Path C:\Users\victim\Downloads
.EXAMPLE  .\Scan-Yara.ps1 -Processes
.NOTES   Process memory scan needs Administrator. Large trees are slow; scope tightly.
#>
[CmdletBinding()] param(
    [string[]]$Path,
    [string]$RulesDir,
    [switch]$Processes,
    [string]$Output
)
$ErrorActionPreference='Stop'
$yara = Get-ChildItem (Join-Path $PSScriptRoot '..\tools\YARA') -Recurse -Filter 'yara*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'yarac' } | Select-Object -First 1
if (-not $yara) { throw "YARA not found. Run Get-Tools.ps1 -Only YARA first (https://github.com/VirusTotal/yara)." }
if (-not $RulesDir) { $RulesDir = Join-Path $PSScriptRoot '..\iocs\yara' }
$rules = Get-ChildItem $RulesDir -Recurse -Include '*.yar','*.yara' -ErrorAction SilentlyContinue
if (-not $rules) { throw "No .yar rules in $RulesDir. See iocs\yara\README.md for where to get curated rule sets." }

$stamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
if (-not $Output) { $Output = Join-Path $PSScriptRoot ("..\output\yara_{0}.csv" -f $stamp) }
$null = New-Item -ItemType Directory -Force -Path (Split-Path $Output)
$results = New-Object System.Collections.Generic.List[object]

# Build a single combined rule via includes (yara accepts multiple -? Just iterate).
function Invoke-Yara([string]$target,[switch]$isPid) {
    foreach ($r in $rules) {
        $yargs = @('-r','-w','-s')
        if ($isPid) { $yargs = @('-w','-s') }   # -r meaningless for a pid
        $out = & $yara.FullName @yargs $r.FullName $target 2>$null
        foreach ($line in $out) {
            if ($line -match '^\s*[\w\.]+\s+\S') {
                $results.Add([pscustomobject]@{ Rule=($line -split '\s+')[0]; RuleFile=$r.Name; Target=$target; Match=$line })
            }
        }
    }
}

if ($Processes) {
    # Enum overload -- the string 'Administrator' matches the built-in user, not the
    # Administrators group, and returns $false even when elevated.
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Process scan needs Administrator." }
    Write-Host "[*] YARA-scanning live process memory..." -ForegroundColor Cyan
    foreach ($p in Get-Process) {
        Write-Progress -Activity 'YARA process scan' -Status "$($p.Name) ($($p.Id))"
        Invoke-Yara $p.Id -isPid
    }
} else {
    if (-not $Path) { $Path = @("C:\Users","C:\ProgramData",$env:TEMP) | Where-Object { Test-Path $_ } }
    foreach ($p in $Path) { Write-Host "[*] YARA-scanning files under $p ..." -ForegroundColor Cyan; Invoke-Yara $p }
}

$results | Export-Csv -NoTypeInformation -Path $Output -Encoding UTF8
if ($results.Count) { Write-Host "[+] $($results.Count) match line(s) -> $Output" -ForegroundColor Green; $results | Format-Table Rule,Target -Auto }
else { Write-Host "[+] No YARA matches. ($Output written, empty)" -ForegroundColor Green }
