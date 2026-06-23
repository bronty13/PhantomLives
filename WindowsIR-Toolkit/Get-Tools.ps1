<#
.SYNOPSIS
    Bootstraps the Windows IR Toolkit by downloading each tool from its OFFICIAL
    upstream source into .\tools\<ToolName>\. Records SHA-256 hashes for every
    file fetched into .\tools\_manifest_downloaded.json (provenance for the case).

.DESCRIPTION
    Several excellent IR tools are free but their licenses FORBID redistribution
    (Sysinternals, KAPE, FTK Imager). This toolkit therefore never bundles
    binaries; it pulls current versions from the vendor at run time on the
    analyst's own (clean) workstation -- NOT on the suspect endpoint.

    Run this on your analysis workstation with internet access, then copy the
    populated toolkit to read-only/removable media for field use.

.PARAMETER Only
    Comma-separated tool names to fetch (default: all redistributable + direct
    -downloadable ones). Names match tools.manifest.json.

.PARAMETER IncludeManualRegistration
    Also attempt the tools that require a registration/EULA click; for those the
    script just opens the vendor page and prints instructions (no silent fetch).

.EXAMPLE
    .\Get-Tools.ps1
.EXAMPLE
    .\Get-Tools.ps1 -Only Velociraptor,WinPmem,Hayabusa
.NOTES
    DO NOT run the downloader on the evidence machine. Acquire on a clean host.
#>
[CmdletBinding()]
param(
    [string[]]$Only,
    [switch]$IncludeManualRegistration
)

$ErrorActionPreference = 'Stop'
$root      = $PSScriptRoot
$toolsDir  = Join-Path $root 'tools'
$manifest  = Join-Path $root 'tools.manifest.json'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path $manifest)) { throw "tools.manifest.json not found next to this script." }
$null = New-Item -ItemType Directory -Force -Path $toolsDir
$spec = Get-Content $manifest -Raw | ConvertFrom-Json

function Write-Step($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok  ($m){ Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err ($m){ Write-Host "[x] $m" -ForegroundColor Red }

# Resolve the newest matching asset from a GitHub 'releases/latest' page via API.
function Get-GitHubLatestAsset {
    param([string]$RepoUrl,[string]$Pattern)
    if ($RepoUrl -notmatch 'github\.com/([^/]+)/([^/]+)') { return $null }
    $api = "https://api.github.com/repos/$($Matches[1])/$($Matches[2])/releases/latest"
    $hdr = @{ 'User-Agent' = 'WindowsIR-Toolkit'; 'Accept' = 'application/vnd.github+json' }
    $rel = Invoke-RestMethod -Uri $api -Headers $hdr
    if (-not $Pattern) { return $null }
    $rx  = '^' + [Regex]::Escape($Pattern).Replace('\*','.*') + '$'
    $asset = $rel.assets | Where-Object { $_.name -match $rx } | Select-Object -First 1
    if ($asset) { return [pscustomobject]@{ Url=$asset.browser_download_url; Name=$asset.name; Tag=$rel.tag_name } }
    return $null
}

function Save-File {
    param([string]$Url,[string]$OutFile)
    $hdr = @{ 'User-Agent' = 'WindowsIR-Toolkit' }
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers $hdr -UseBasicParsing
    return (Get-FileHash -Algorithm SHA256 -Path $OutFile).Hash
}

$provenance = @()
$selected = if ($Only) { $spec.tools | Where-Object { $Only -contains $_.name } } else { $spec.tools }

foreach ($t in $selected) {
    Write-Host ""
    Write-Step "$($t.name)  [$($t.category)]  license: $($t.license)"
    $dest = Join-Path $toolsDir $t.name
    $null = New-Item -ItemType Directory -Force -Path $dest

    # Tools that cannot be fetched without a EULA/registration click.
    $needsRegistration = $t.name -in @('KAPE','FTKImager','DumpIt')
    if ($needsRegistration -and -not $IncludeManualRegistration) {
        Write-Warn2 "Manual download required (registration/EULA). Skipping; re-run with -IncludeManualRegistration to open the page."
        Write-Host  "    $($t.url)"
        continue
    }
    if ($needsRegistration) {
        Write-Warn2 "Opening vendor page -- complete the registration, then unzip into: $dest"
        try { Start-Process $t.url } catch {}
        Set-Content -Path (Join-Path $dest 'DOWNLOAD_HERE.txt') -Value "Place the downloaded files here.`r`nSource: $($t.url)`r`n$($t.notes)"
        continue
    }

    try {
        $url = $t.url; $fileName = $null
        if ($t.asset_pattern) {
            $a = Get-GitHubLatestAsset -RepoUrl $t.url -Pattern $t.asset_pattern
            if ($a) { $url = $a.Url; $fileName = $a.Name; Write-Host "    release: $($a.Tag)" }
        }
        if (-not $fileName) { $fileName = Split-Path ($url -split '\?')[0] -Leaf }
        if (-not $fileName) { $fileName = "$($t.name).bin" }
        $out = Join-Path $dest $fileName

        Write-Host "    GET $url"
        $hash = Save-File -Url $url -OutFile $out
        Write-Ok "saved $fileName  (SHA256 $hash)"

        if ($out -match '\.zip$') {
            try { Expand-Archive -Path $out -DestinationPath $dest -Force; Write-Host "    extracted." } catch { Write-Warn2 "extract failed: $_" }
        }
        $provenance += [pscustomobject]@{
            tool=$t.name; file=$fileName; url=$url; sha256=$hash
            license=$t.license; downloaded_utc=(Get-Date).ToUniversalTime().ToString('o')
        }
    } catch {
        Write-Err "FAILED $($t.name): $($_.Exception.Message)"
        Write-Host "    Get it manually from: $($t.url)"
    }
}

# EZ tools have their own self-updater; pull it down if selected.
if (-not $Only -or $Only -contains 'EricZimmermanTools') {
    Write-Host ""
    Write-Step "Eric Zimmerman tools self-updater"
    $ezDir = Join-Path $toolsDir 'EricZimmermanTools'
    $null = New-Item -ItemType Directory -Force -Path $ezDir
    try {
        $zip = Join-Path $ezDir 'Get-ZimmermanTools.zip'
        $h = Save-File -Url 'https://download.ericzimmermantools.com/Get-ZimmermanTools.zip' -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $ezDir -Force
        Write-Ok "Get-ZimmermanTools fetched (SHA256 $h). Run: .\tools\EricZimmermanTools\Get-ZimmermanTools.ps1 -Dest .\tools\EricZimmermanTools"
    } catch { Write-Err "EZ updater failed: $_  -> get it from https://ericzimmerman.github.io/" }
}

$provFile = Join-Path $toolsDir '_manifest_downloaded.json'
$provenance | ConvertTo-Json -Depth 5 | Set-Content -Path $provFile -Encoding UTF8
Write-Host ""
Write-Ok "Provenance (hashes) written: $provFile"
Write-Warn2 "Reminder: verify vendor signatures/hashes before evidentiary use. Run tools from READ-ONLY media on the endpoint."
