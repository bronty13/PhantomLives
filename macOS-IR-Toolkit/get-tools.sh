#!/bin/bash
# macOS IR Toolkit -- fetch the optional external tools from official sources.
# Run this on a CLEAN, internet-connected analysis Mac, then copy the toolkit to
# removable/read-only media for field use. The dependency-free collector
# (collect-triage.sh) needs NONE of these; they enrich the HUNT / deep-collection.
#
#   YARA       -- file scanning            (Homebrew, or github.com/VirusTotal/yara)
#   Aftermath  -- Jamf heavy IR collector  (github.com/jamf/aftermath, MIT, signed)
#   osquery    -- live SQL over the host    (Homebrew cask, or osquery.io)
#
# Usage:  ./get-tools.sh [yara|aftermath|osquery]...   (no args = all)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$HERE/tools"; mkdir -p "$TOOLS"
PROV="$TOOLS/_provenance.txt"
WANT="${*:-yara aftermath osquery}"
have_brew(){ command -v brew >/dev/null 2>&1; }
note(){ printf '%s\n' "$*" | tee -a "$PROV"; }

echo "[*] Fetching: $WANT"
echo "# macOS IR Toolkit tool provenance -- $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PROV"

for t in $WANT; do
  case "$t" in
    yara)
      echo ""; echo "== YARA =="
      if have_brew; then brew install yara && note "yara: brew $(brew list --versions yara 2>/dev/null)"
      else echo "[!] Homebrew not found. Install from https://github.com/VirusTotal/yara/releases or 'brew install yara'."; fi
      ;;
    osquery)
      echo ""; echo "== osquery =="
      if have_brew; then brew install --cask osquery && note "osquery: brew cask $(brew list --cask --versions osquery 2>/dev/null)"
      else echo "[!] Homebrew not found. Get the signed pkg from https://www.osquery.io/downloads"; fi
      ;;
    aftermath)
      echo ""; echo "== Aftermath (Jamf) =="
      dest="$TOOLS/Aftermath"; mkdir -p "$dest"
      api="https://api.github.com/repos/jamf/aftermath/releases/latest"
      url="$(curl -fsSL "$api" 2>/dev/null | awk -F'"' '/browser_download_url/ && /\.zip"/{print $4; exit}')"
      if [ -n "$url" ]; then
        echo "[*] GET $url"
        if curl -fsSL "$url" -o "$dest/aftermath.zip"; then
          ( cd "$dest" && unzip -o -q aftermath.zip 2>/dev/null )
          h=$(shasum -a 256 "$dest/aftermath.zip" | awk '{print $1}')
          note "aftermath: $url  sha256=$h"
          echo "[+] Aftermath in $dest (verify Jamf's published signature before evidentiary use)."
        else echo "[!] download failed -- get it from https://github.com/jamf/aftermath/releases"; fi
      else
        echo "[!] Could not resolve latest Aftermath release via GitHub API."
        echo "    Download manually: https://github.com/jamf/aftermath/releases -> place 'aftermath' in $dest/"
      fi
      ;;
    *) echo "[!] unknown tool: $t";;
  esac
done

echo ""
echo "[+] Provenance: $PROV"
echo "[!] Verify each tool's vendor signature/hash before evidentiary use; run from read-only media on the endpoint."
