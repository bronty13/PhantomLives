#requires -Version 5
# Build Purple PDF on Windows (NSIS .exe).
$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "==> Regenerating icons"
python build/make_icon.py

Write-Host "==> Installing dependencies"
npm install --silent

Write-Host "==> Building (windows)"
npm run dist:win

Write-Host "==> Done. Artifacts in ./dist"
Get-ChildItem dist | Format-Table
