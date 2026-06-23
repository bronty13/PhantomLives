#!/bin/bash
# macOS IR Toolkit -- YARA-scan files against rules in ../iocs/yara, results -> CSV.
#
# Finds the yara binary in ../tools/YARA (from get-tools.sh) or on PATH
# (e.g. `brew install yara`). Drop .yar/.yara rules into ../iocs/yara/ (a starter
# set ships; iocs/README.md lists curated sources like YARAify / Neo23x0).
#
# Usage:  ./run-yara.sh [-o out.csv] [-p <path>]... [--rules <dir>]
# Default paths: /Users  /tmp  /var/tmp  /Library/LaunchAgents  /Library/LaunchDaemons
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
OUTPUT=""; RULESDIR="$HERE/../iocs/yara"; PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) OUTPUT="${2:-}"; shift 2;;
    -p|--path)   PATHS+=("${2:-}"); shift 2;;
    --rules)     RULESDIR="${2:-}"; shift 2;;
    -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "[!] unknown arg: $1" >&2; shift;;
  esac
done

# Locate yara: bundled first, then PATH.
YARA="$(find "$HERE/../tools/YARA" -name 'yara' -type f 2>/dev/null | head -1)"
[ -z "$YARA" ] && YARA="$(command -v yara 2>/dev/null)"
[ -z "$YARA" ] && { echo "[x] yara not found. Run ./get-tools.sh (or: brew install yara)."; exit 1; }

# Gather rule files.
RULES=()
while IFS= read -r r; do RULES+=("$r"); done < <(find "$RULESDIR" \( -name '*.yar' -o -name '*.yara' \) -type f 2>/dev/null)
[ "${#RULES[@]}" -eq 0 ] && { echo "[x] no .yar rules in $RULESDIR -- see iocs/README.md."; exit 1; }

[ "${#PATHS[@]}" -eq 0 ] && PATHS=(/Users /tmp /var/tmp /Library/LaunchAgents /Library/LaunchDaemons)
STAMP="$(date -u +%Y%m%d_%H%M%S)"
[ -z "$OUTPUT" ] && OUTPUT="$HOME/Downloads/macOS-IR-Toolkit/yara_${STAMP}.csv"
mkdir -p "$(dirname "$OUTPUT")"

echo "rule,rule_file,target" > "$OUTPUT"
echo "[*] yara: $YARA"
echo "[*] ${#RULES[@]} rule file(s); scanning: ${PATHS[*]}"
count=0
for rf in "${RULES[@]}"; do
  for tgt in "${PATHS[@]}"; do
    [ -e "$tgt" ] || continue
    # -r recurse, -w no warnings, -N no follow symlinks (avoid loops), -f fast.
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      rule="${line%% *}"; file="${line#* }"
      printf '%s,%s,"%s"\n' "$rule" "$(basename "$rf")" "$file" >> "$OUTPUT"
      count=$((count+1))
    done < <("$YARA" -r -w -N -f "$rf" "$tgt" 2>/dev/null)
  done
done

if [ "$count" -gt 0 ]; then
  echo "[+] $count match line(s) -> $OUTPUT"
else
  echo "[+] No YARA matches. ($OUTPUT written, header only)"
fi
exit 0
