#!/bin/bash
# macOS IR Toolkit -- wrapper for Jamf's Aftermath (the macOS heavy collector,
# analogous to Velociraptor/KAPE on Windows). Aftermath is a Swift, open-source
# (MIT) IR framework that deep-collects + parses host artifacts into an archive.
#
# Get it via get-tools.sh, or download a signed release from
#   https://github.com/jamf/aftermath/releases   (place at ../tools/Aftermath/aftermath)
# Aftermath must run as ROOT and is itself code-signed; on a managed Mac you may also
# need to allow it in Privacy & Security.
#
# Usage:  sudo ./run-aftermath.sh [-o <outdir>] [--analyze <archive>]
#   (default collect)        deep-collect this host -> <outdir>/<...>.zip
#   --analyze <archive.zip>  re-parse a previously collected archive
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
OUTPUT=""; ANALYZE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)  OUTPUT="${2:-}"; shift 2;;
    --analyze)    ANALYZE="${2:-}"; shift 2;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "[!] unknown arg: $1" >&2; shift;;
  esac
done

AM="$(find "$HERE/../tools/Aftermath" -name 'aftermath' -type f 2>/dev/null | head -1)"
[ -z "$AM" ] && AM="$(command -v aftermath 2>/dev/null)"
[ -z "$AM" ] && {
  echo "[x] aftermath not found."
  echo "    Download a signed release from https://github.com/jamf/aftermath/releases"
  echo "    and place it at ../tools/Aftermath/aftermath, or run ./get-tools.sh."
  exit 1; }

[ "$(id -u)" -eq 0 ] || { echo "[x] Aftermath must run as root. Re-run with sudo."; exit 1; }

if [ -n "$ANALYZE" ]; then
  echo "[*] Aftermath analyze: $ANALYZE"
  "$AM" --analyze "$ANALYZE" ${OUTPUT:+-o "$OUTPUT"}
  exit $?
fi

[ -z "$OUTPUT" ] && OUTPUT="$HOME/Downloads/macOS-IR-Toolkit"
mkdir -p "$OUTPUT"
echo "[*] Aftermath deep-collecting this host -> $OUTPUT"
"$AM" -o "$OUTPUT"
rc=$?

# Aftermath writes a zip into the output dir; hash the newest one.
arc=$(find "$OUTPUT" -maxdepth 1 -name '*.zip' -newermt '-5 minutes' 2>/dev/null | head -1)
[ -z "$arc" ] && arc=$(ls -t "$OUTPUT"/*.zip 2>/dev/null | head -1)
if [ -n "$arc" ] && [ -e "$arc" ]; then
  h=$(shasum -a 256 "$arc" | awk '{print $1}')
  printf '%s  %s\n' "$h" "$(basename "$arc")" > "$arc.sha256"
  echo "[+] Aftermath archive: $arc  (sha256 $h)"
else
  echo "[!] No Aftermath archive found in $OUTPUT (rc=$rc) -- check Aftermath output above."
fi
exit "$rc"
