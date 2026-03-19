#!/bin/bash

# MacSysInfo v3

MODE="full"
OUTPUT_FILE=""
JSON_OUT=""
CSV_OUT=""
BASELINE_SAVE=""
BASELINE_COMPARE=""
REDACT=0
NETWORK_TEST=0
SECTION_FILTERS=()
CHECK_TIMEOUT=8

CHECK_SECTION=()
CHECK_NAME=()
CHECK_STATUS=()
CHECK_DURATION=()
CHECK_SEVERITY=()
CHECK_MESSAGE=()

KV_KEYS=()
KV_VALUES=()

FIND_SEV=()
FIND_MSG=()

report_time="$(date "+%Y-%m-%d %H:%M:%S")"

print_help() {
  cat <<'EOF'
Usage: ./MacSysInfo.sh [options]

Options:
  --quick                  Faster run (skips expensive checks)
  --full                   Full run (default)
  --output <file>          Tee human-readable report to file
  --json <file>            Write structured JSON output
  --csv <file>             Write structured CSV output
  --baseline-save <file>   Save current key-value baseline
  --baseline-compare <file> Compare current values against baseline file
  --redact                 Redact sensitive values in output
  --network-test           Run active network reachability tests
  --section <list>         Comma-separated sections (example: security,network)
  --timeout <seconds>      Timeout per command check (default: 8)
  --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) MODE="quick"; shift ;;
    --full) MODE="full"; shift ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --json) JSON_OUT="$2"; shift 2 ;;
    --csv) CSV_OUT="$2"; shift 2 ;;
    --baseline-save) BASELINE_SAVE="$2"; shift 2 ;;
    --baseline-compare) BASELINE_COMPARE="$2"; shift 2 ;;
    --redact) REDACT=1; shift ;;
    --network-test) NETWORK_TEST=1; shift ;;
    --section)
      IFS=',' read -r -a SECTION_FILTERS <<< "$2"
      shift 2
      ;;
    --timeout)
      CHECK_TIMEOUT="$2"
      shift 2
      ;;
    --help)
      print_help
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "$OUTPUT_FILE" ]]; then
  exec > >(tee -a "$OUTPUT_FILE") 2>&1
fi

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

mask_value() {
  local v="$1"
  local len=${#v}
  if [[ "$len" -le 4 ]]; then
    printf "****"
  else
    printf "%s****%s" "${v:0:2}" "${v: -2}"
  fi
}

redact_value() {
  local key="$1"
  local value="$2"
  if [[ "$REDACT" -eq 0 ]]; then
    printf "%s" "$value"
    return
  fi

  case "$key" in
    *serial*|*ssid*|*hostname*|*user*|*home*|*ip*|*gateway*|*dns*)
      mask_value "$value"
      ;;
    *)
      printf "%s" "$value"
      ;;
  esac
}

add_kv() {
  local key="$1"
  local value="$2"
  KV_KEYS+=("$key")
  KV_VALUES+=("$(redact_value "$key" "$value")")
}

add_finding() {
  local sev="$1"
  local msg="$2"
  FIND_SEV+=("$sev")
  FIND_MSG+=("$msg")
}

record_check() {
  local section="$1"
  local name="$2"
  local status="$3"
  local duration="$4"
  local severity="$5"
  local message="$6"
  CHECK_SECTION+=("$section")
  CHECK_NAME+=("$name")
  CHECK_STATUS+=("$status")
  CHECK_DURATION+=("$duration")
  CHECK_SEVERITY+=("$severity")
  CHECK_MESSAGE+=("$message")
}

section_allowed() {
  local s="$1"
  if [[ ${#SECTION_FILTERS[@]} -eq 0 ]]; then
    return 0
  fi
  local wanted
  for wanted in "${SECTION_FILTERS[@]}"; do
    if [[ "$wanted" == "$s" ]]; then
      return 0
    fi
  done
  return 1
}

run_with_timeout() {
  local timeout_sec="$1"
  shift
  local cmd="$*"
  if check_cmd gtimeout; then
    gtimeout "$timeout_sec" bash -lc "$cmd"
    return $?
  fi
  if check_cmd perl; then
    perl -e 'alarm shift; exec @ARGV' "$timeout_sec" bash -lc "$cmd"
    return $?
  fi
  bash -lc "$cmd"
}

run_check_capture() {
  local section="$1"
  local name="$2"
  local severity="$3"
  local cmd="$4"
  local start end dur rc out status msg

  start=$(date +%s)
  out="$(run_with_timeout "$CHECK_TIMEOUT" "$cmd" 2>&1)"
  rc=$?
  end=$(date +%s)
  dur=$((end - start))

  if [[ "$rc" -eq 124 || "$rc" -eq 142 ]]; then
    status="TIMEOUT"
    msg="command timed out"
    add_finding "WARN" "$section/$name timed out"
  elif [[ "$rc" -ne 0 ]]; then
    status="FAIL"
    msg="command failed ($rc)"
    if [[ "$severity" == "CRITICAL" ]]; then
      add_finding "CRITICAL" "$section/$name failed"
    else
      add_finding "WARN" "$section/$name failed"
    fi
  else
    status="PASS"
    msg="ok"
  fi

  record_check "$section" "$name" "$status" "$dur" "$severity" "$msg"
  printf "%s" "$out"
}

section_header() {
  local title="$1"
  echo ""
  echo "======================================================================"
  echo "  $title"
  echo "  Timestamp: $(date "+%Y-%m-%d %H:%M:%S")"
  echo "======================================================================"
}

print_toc() {
  echo ""
  echo "Table of Contents"
  echo "  [1]  Hardware Summary (hardware)"
  echo "  [2]  OS & System Information (os)"
  echo "  [3]  Uptime & Boot History (uptime)"
  echo "  [4]  Security Posture (security)"
  echo "  [5]  OS Updates & Patch Status (updates)"
  echo "  [6]  System Users (users)"
  echo "  [7]  Memory Usage (memory)"
  echo "  [8]  Disk Space & Health (disk)"
  echo "  [9]  Network (network)"
  echo "  [10] Process Hotspots (processes)"
  echo "  [11] Developer & Runtime Environment (developer)"
  echo "  [12] Installed Applications (applications)"
  echo "  [13] Startup & Background Services (startup)"
  echo "  [14] MDM & Security Tooling (mdm)"
  echo "  [15] Baseline Diff (diff)"
  echo "  [16] Check Health (health)"
  echo "  [17] Summary & Risk Score (summary)"
}

json_escape() {
  printf '%s' "$1" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r"); print}'
}

csv_escape() {
  local s
  s=$(printf '%s' "$1" | sed 's/"/""/g')
  printf '"%s"' "$s"
}

write_json() {
  local file="$1"
  {
    echo "{"
    echo "  \"generated_at\": \"$(json_escape "$report_time")\"," 
    echo "  \"mode\": \"$(json_escape "$MODE")\"," 
    echo "  \"redacted\": $([[ "$REDACT" -eq 1 ]] && echo true || echo false),"
    echo "  \"key_values\": {"
    local i
    for ((i=0; i<${#KV_KEYS[@]}; i++)); do
      local comma=","
      if [[ "$i" -eq $(( ${#KV_KEYS[@]} - 1 )) ]]; then comma=""; fi
      echo "    \"$(json_escape "${KV_KEYS[$i]}")\": \"$(json_escape "${KV_VALUES[$i]}")\"$comma"
    done
    echo "  },"
    echo "  \"findings\": ["
    for ((i=0; i<${#FIND_SEV[@]}; i++)); do
      local comma=","
      if [[ "$i" -eq $(( ${#FIND_SEV[@]} - 1 )) ]]; then comma=""; fi
      echo "    {\"severity\": \"$(json_escape "${FIND_SEV[$i]}")\", \"message\": \"$(json_escape "${FIND_MSG[$i]}")\"}$comma"
    done
    echo "  ],"
    echo "  \"checks\": ["
    for ((i=0; i<${#CHECK_SECTION[@]}; i++)); do
      local comma=","
      if [[ "$i" -eq $(( ${#CHECK_SECTION[@]} - 1 )) ]]; then comma=""; fi
      echo "    {\"section\": \"$(json_escape "${CHECK_SECTION[$i]}")\", \"name\": \"$(json_escape "${CHECK_NAME[$i]}")\", \"status\": \"$(json_escape "${CHECK_STATUS[$i]}")\", \"duration_seconds\": ${CHECK_DURATION[$i]}, \"severity\": \"$(json_escape "${CHECK_SEVERITY[$i]}")\", \"message\": \"$(json_escape "${CHECK_MESSAGE[$i]}")\"}$comma"
    done
    echo "  ]"
    echo "}"
  } > "$file"
}

write_csv() {
  local file="$1"
  {
    echo "type,section,name,key,value,status,severity,message,duration_seconds"
    local i
    for ((i=0; i<${#KV_KEYS[@]}; i++)); do
      echo "kv,,,$(csv_escape "${KV_KEYS[$i]}"),$(csv_escape "${KV_VALUES[$i]}"),,,,"
    done
    for ((i=0; i<${#FIND_SEV[@]}; i++)); do
      echo "finding,,,,,,$(csv_escape "${FIND_SEV[$i]}"),$(csv_escape "${FIND_MSG[$i]}"),"
    done
    for ((i=0; i<${#CHECK_SECTION[@]}; i++)); do
      echo "check,$(csv_escape "${CHECK_SECTION[$i]}"),$(csv_escape "${CHECK_NAME[$i]}"),,,$(csv_escape "${CHECK_STATUS[$i]}"),$(csv_escape "${CHECK_SEVERITY[$i]}"),$(csv_escape "${CHECK_MESSAGE[$i]}"),$(csv_escape "${CHECK_DURATION[$i]}")"
    done
  } > "$file"
}

save_baseline() {
  local file="$1"
  local i
  : > "$file"
  for ((i=0; i<${#KV_KEYS[@]}; i++)); do
    printf "%s\t%s\n" "${KV_KEYS[$i]}" "${KV_VALUES[$i]}" >> "$file"
  done
}

compare_baseline() {
  local baseline="$1"
  if [[ ! -f "$baseline" ]]; then
    add_finding "WARN" "Baseline file not found: $baseline"
    echo "  Baseline file not found: $baseline"
    return
  fi

  local current
  current="$(mktemp)"
  save_baseline "$current"

  local changed=0
  local key oldv newv
  echo "  Changes from baseline:"

  while IFS=$'\t' read -r key oldv; do
    newv=$(awk -F'\t' -v k="$key" '$1==k {print substr($0,index($0,$2)); exit}' "$current")
    if [[ -z "$newv" ]]; then
      echo "    - REMOVED: $key"
      add_finding "WARN" "Baseline key removed: $key"
      changed=$((changed+1))
    elif [[ "$newv" != "$oldv" ]]; then
      echo "    - CHANGED: $key"
      echo "      old=$oldv"
      echo "      new=$newv"
      add_finding "WARN" "Baseline drift: $key"
      changed=$((changed+1))
    fi
  done < "$baseline"

  while IFS=$'\t' read -r key _; do
    if ! awk -F'\t' -v k="$key" '$1==k {found=1} END{exit !found}' "$baseline"; then
      echo "    - ADDED: $key"
      add_finding "INFO" "New baseline key: $key"
      changed=$((changed+1))
    fi
  done < "$current"

  if [[ "$changed" -eq 0 ]]; then
    echo "    No differences found."
  fi

  rm -f "$current"
}

echo ""
echo "======================================================================"
echo "  macOS System Information Report (v3)"
echo "  Generated: $report_time"
echo "  Mode: $MODE | Redact: $REDACT | Timeout: ${CHECK_TIMEOUT}s"
echo "======================================================================"

print_toc

if section_allowed "hardware"; then
  section_header "Hardware Summary"
  hw_out="$(run_check_capture "hardware" "hardware_profile" "INFO" "system_profiler SPHardwareDataType")"
  model=$(echo "$hw_out" | awk -F': ' '/Model Name/{print $2; exit}')
  model_id=$(echo "$hw_out" | awk -F': ' '/Model Identifier/{print $2; exit}')
  serial=$(echo "$hw_out" | awk -F': ' '/Serial Number/{print $2; exit}')
  cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  [[ -z "$cpu" ]] && cpu=$(echo "$hw_out" | awk -F': ' '/Chip/{print $2; exit}')
  cores=$(sysctl -n hw.physicalcpu 2>/dev/null)
  threads=$(sysctl -n hw.logicalcpu 2>/dev/null)
  arch=$(uname -m)

  echo "  Model: ${model:-N/A}"
  echo "  Model ID: ${model_id:-N/A}"
  echo "  CPU: ${cpu:-N/A}"
  echo "  Cores: ${cores:-N/A} physical, ${threads:-N/A} logical"
  echo "  Architecture: $arch"
  echo "  Serial: $(redact_value hardware.serial "${serial:-N/A}")"

  add_kv "hardware.model" "${model:-N/A}"
  add_kv "hardware.model_id" "${model_id:-N/A}"
  add_kv "hardware.cpu" "${cpu:-N/A}"
  add_kv "hardware.cores_physical" "${cores:-N/A}"
  add_kv "hardware.cores_logical" "${threads:-N/A}"
  add_kv "hardware.arch" "$arch"
  add_kv "hardware.serial" "${serial:-N/A}"
fi

if section_allowed "os"; then
  section_header "OS & System Information"
  os_out="$(run_check_capture "os" "software_profile" "INFO" "system_profiler SPSoftwareDataType")"
  system_version=$(echo "$os_out" | awk -F': ' '/System Version/{print $2; exit}')
  kernel_version=$(echo "$os_out" | awk -F': ' '/Kernel Version/{print $2; exit}')
  boot_volume=$(echo "$os_out" | awk -F': ' '/Boot Volume/{print $2; exit}')
  uptime_sys=$(echo "$os_out" | awk -F': ' '/Time since boot/{print $2; exit}')
  host_name=$(scutil --get ComputerName 2>/dev/null || hostname)

  echo "  Hostname: $(redact_value os.hostname "$host_name")"
  echo "  System Version: ${system_version:-N/A}"
  echo "  Kernel Version: ${kernel_version:-N/A}"
  echo "  Boot Volume: ${boot_volume:-N/A}"
  echo "  Time Since Boot: ${uptime_sys:-N/A}"

  add_kv "os.hostname" "$host_name"
  add_kv "os.system_version" "${system_version:-N/A}"
  add_kv "os.kernel_version" "${kernel_version:-N/A}"
  add_kv "os.boot_volume" "${boot_volume:-N/A}"
  add_kv "os.time_since_boot" "${uptime_sys:-N/A}"
fi

if section_allowed "uptime"; then
  section_header "Uptime & Boot History"
  uptime_str=$(uptime 2>/dev/null)
  boot_epoch=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[={ ,}]' '{for(i=1;i<=NF;i++) if($i=="sec") {print $(i+1); exit}}')
  boot_human=$([[ -n "$boot_epoch" ]] && date -r "$boot_epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")
  echo "  Current Uptime: ${uptime_str:-N/A}"
  echo "  Last Boot: $boot_human"
  echo ""
  echo "  Recent Logins (last 10):"
  run_check_capture "uptime" "recent_logins" "INFO" "last | head -10" | awk '{print "    "$0}'
  add_kv "uptime.current" "${uptime_str:-N/A}"
  add_kv "uptime.last_boot" "$boot_human"
fi

if section_allowed "security"; then
  section_header "Security Posture"
  fv=$(run_check_capture "security" "filevault_status" "CRITICAL" "fdesetup status" | head -1)
  fw=$(run_check_capture "security" "firewall_status" "WARN" "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate" | head -1)
  sip=$(run_check_capture "security" "sip_status" "CRITICAL" "csrutil status" | head -1)
  gk=$(run_check_capture "security" "gatekeeper_status" "WARN" "spctl --status" | head -1)

  echo "  FileVault: ${fv:-N/A}"
  echo "  Firewall: ${fw:-N/A}"
  echo "  SIP: ${sip:-N/A}"
  echo "  Gatekeeper: ${gk:-N/A}"

  [[ "$fv" != *"On"* ]] && add_finding "CRITICAL" "FileVault is not enabled"
  [[ "$fw" != *"enabled"* ]] && add_finding "WARN" "Application Firewall is not enabled"
  [[ "$sip" != *"enabled"* ]] && add_finding "CRITICAL" "SIP appears disabled"
  [[ "$gk" != *"enabled"* ]] && add_finding "WARN" "Gatekeeper appears disabled"

  add_kv "security.filevault" "${fv:-N/A}"
  add_kv "security.firewall" "${fw:-N/A}"
  add_kv "security.sip" "${sip:-N/A}"
  add_kv "security.gatekeeper" "${gk:-N/A}"

  echo ""
  echo "  Secure Token Status:"
  dscl . -list /Users UniqueID 2>/dev/null | awk '$2>=500{print $1}' | while read -r u; do
    tok=$(sysadminctl -secureTokenStatus "$u" 2>&1 | awk '/ENABLED/{print "ENABLED"} /DISABLED/{print "DISABLED"}' | head -1)
    printf "    %-20s %s\n" "$(redact_value security.user "$u")" "${tok:-N/A}"
  done

  root_auth=$(dscl . -read /Users/root AuthenticationAuthority 2>/dev/null)
  if [[ -n "$root_auth" ]]; then
    echo "  Root Account: Active"
    add_finding "WARN" "Root account appears active"
    add_kv "security.root_account" "active"
  else
    echo "  Root Account: Disabled"
    add_kv "security.root_account" "disabled"
  fi

  echo ""
  echo "  Accounts with UID 0:"
  uid0=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2==0{print $1}')
  if [[ -n "$uid0" ]]; then
    echo "$uid0" | awk '{print "    "$0}'
  else
    echo "    None"
  fi

  if [[ "$MODE" == "full" ]]; then
    echo ""
    echo "  Launch Item Signature Review (first 50):"
    count=0
    suspicious=0
    for p in "$HOME"/Library/LaunchAgents/*.plist /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist; do
      [[ -f "$p" ]] || continue
      count=$((count+1))
      [[ "$count" -gt 50 ]] && break

      prog=$(/usr/libexec/PlistBuddy -c 'Print :Program' "$p" 2>/dev/null)
      if [[ -z "$prog" ]]; then
        prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" 2>/dev/null)
      fi
      [[ -n "$prog" && -e "$prog" ]] || continue

      sig=$(codesign -dv --verbose=4 "$prog" 2>&1)
      if [[ $? -ne 0 ]]; then
        echo "    UNSIGNED: $p -> $prog"
        add_finding "WARN" "Unsigned launch executable: $prog"
        suspicious=$((suspicious+1))
        continue
      fi

      auth=$(echo "$sig" | awk -F= '/^Authority=/{print $2; exit}')
      if [[ -z "$auth" ]]; then
        echo "    AD-HOC:   $p -> $prog"
        add_finding "WARN" "Ad-hoc signed launch executable: $prog"
        suspicious=$((suspicious+1))
      elif ! echo "$auth" | grep -Eq 'Apple|Developer ID|Mac Developer|3rd Party'; then
        echo "    UNKNOWN:  $p -> $prog (Authority=$auth)"
        add_finding "WARN" "Unknown publisher launch executable: $prog"
        suspicious=$((suspicious+1))
      fi
    done
    [[ "$suspicious" -eq 0 ]] && echo "    No suspicious launch executable signatures found."
    add_kv "security.launch_signature_suspicious_count" "$suspicious"
  else
    record_check "security" "launch_signature_review" "SKIPPED" "0" "INFO" "skipped in quick mode"
  fi
fi

if section_allowed "updates"; then
  section_header "OS Updates & Patch Status"
  xcode_clt=$(pkgutil --pkg-info com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/version/{print $2; exit}')
  echo "  Xcode CLT: ${xcode_clt:-Not installed}"
  add_kv "updates.xcode_clt" "${xcode_clt:-Not installed}"

  if [[ "$MODE" == "full" ]]; then
    echo ""
    echo "  Available software updates:"
    upd=$(run_check_capture "updates" "softwareupdate_list" "WARN" "softwareupdate -l")
    if echo "$upd" | grep -qi "No new software available"; then
      echo "    No updates available."
      add_kv "updates.available" "none"
    else
      echo "$upd" | grep -E '^\*|Label:|Title:|Version:|Recommended' | head -30 | awk '{print "    "$0}'
      add_finding "WARN" "Software updates are available"
      add_kv "updates.available" "yes"
    fi
  else
    echo "  Update scan skipped in quick mode."
    record_check "updates" "softwareupdate_list" "SKIPPED" "0" "INFO" "skipped in quick mode"
  fi
fi

if section_allowed "users"; then
  section_header "System Users"
  printf "%-20s %-6s %-8s %-18s %-18s %-22s %s\n" "Username" "UID" "Admin" "Last Login" "Shell" "Home" "Real Name"
  printf '%0.s-' {1..115}; echo ""

  users_count=0
  admin_count=0
  while IFS=$'\t' read -r _ user_name user_uid user_admin user_shell user_home user_real; do
    last_login=$(last -1 "$user_name" 2>/dev/null | awk 'NR==1 && /[A-Z][a-z][a-z]/{print $4,$5,$6}')
    printf "%-20s %-6s %-8s %-18s %-18s %-22s %s\n" \
      "$(redact_value users.username "$user_name")" "${user_uid:-N/A}" "${user_admin:-No}" "${last_login:-Never}" \
      "${user_shell:-N/A}" "$(redact_value users.home "${user_home:-N/A}")" "${user_real:-N/A}"
    users_count=$((users_count+1))
    [[ "$user_admin" == "Yes" ]] && admin_count=$((admin_count+1))
  done < <(
    dscl . -list /Users UniqueID 2>/dev/null |
    awk '$2 >= 500 {print $1 "\t" $2}' |
    while IFS=$'\t' read -r user_name user_uid; do
      user_shell=$(dscl . -read "/Users/$user_name" UserShell 2>/dev/null | awk '{print $2}')
      user_home=$(dscl . -read "/Users/$user_name" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
      user_real=$(dscl . -read "/Users/$user_name" RealName 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//' | paste -sd ' ' -)
      if dsmemberutil checkmembership -U "$user_name" -G admin 2>/dev/null | grep -q "is a member"; then
        user_admin="Yes"; sort_key=0
      else
        user_admin="No"; sort_key=1
      fi
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$sort_key" "$user_name" "$user_uid" "$user_admin" "${user_shell:-N/A}" "${user_home:-N/A}" "${user_real:-N/A}"
    done | sort -t $'\t' -k1,1n -k2,2f
  )

  add_kv "users.count" "$users_count"
  add_kv "users.admin_count" "$admin_count"
fi

if section_allowed "memory"; then
  section_header "Memory Usage"
  total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
  vm_out="$(run_check_capture "memory" "vm_stat" "INFO" "vm_stat")"
  page_size=$(echo "$vm_out" | awk '/page size of/{gsub(/\./,"",$8); print $8; exit}')
  free_pages=$(echo "$vm_out" | awk '/Pages free/{gsub(/\./,"",$3); print $3; exit}')
  inactive_pages=$(echo "$vm_out" | awk '/Pages inactive/{gsub(/\./,"",$3); print $3; exit}')
  speculative_pages=$(echo "$vm_out" | awk '/Pages speculative/{gsub(/\./,"",$3); print $3; exit}')
  wired_pages=$(echo "$vm_out" | awk '/Pages wired/{gsub(/\./,"",$4); print $4; exit}')

  free_bytes=$(( (free_pages + inactive_pages + speculative_pages) * page_size ))
  used_bytes=$(( total_bytes - free_bytes ))
  wired_bytes=$(( wired_pages * page_size ))
  swap_line=$(sysctl vm.swapusage 2>/dev/null)

  echo "  Used: $(echo "$used_bytes" | awk '{printf "%.2f Gi", $1/1073741824}'), Free: $(echo "$free_bytes" | awk '{printf "%.2f Gi", $1/1073741824}'), Total: $(echo "$total_bytes" | awk '{printf "%.2f Gi", $1/1073741824}')"
  echo "  Wired: $(echo "$wired_bytes" | awk '{printf "%.2f Gi", $1/1073741824}')"
  echo "  Swap: ${swap_line:-N/A}"

  add_kv "memory.used_gib" "$(echo "$used_bytes" | awk '{printf "%.2f", $1/1073741824}')"
  add_kv "memory.free_gib" "$(echo "$free_bytes" | awk '{printf "%.2f", $1/1073741824}')"
  add_kv "memory.total_gib" "$(echo "$total_bytes" | awk '{printf "%.2f", $1/1073741824}')"
fi

if section_allowed "disk"; then
  section_header "Disk Space & Health"
  echo "  Volume Usage:"
  df -h 2>/dev/null | awk 'NR==1 || /^\/dev/{printf "    %-38s %-8s %-8s %-8s %s\n", $1, $2, $3, $4, $5}'

  echo ""
  echo "  APFS Volumes (summary):"
  run_check_capture "disk" "apfs_list" "INFO" "diskutil apfs list" | grep -E 'Container|Name:|Capacity' | head -30 | awk '{print "    "$0}'

  echo ""
  echo "  SMART Status:"
  diskutil list 2>/dev/null | awk '/^\/dev\/disk[0-9]+ \(/{print $1}' | while read -r d; do
    smart=$(diskutil info "$d" 2>/dev/null | awk -F': ' '/SMART Status/{print $2; exit}')
    printf "    %-16s %s\n" "$d" "${smart:-N/A}"
  done

  if [[ "$MODE" == "full" ]]; then
    echo ""
    echo "  Largest Home Directories:"
    run_check_capture "disk" "home_du" "INFO" "du -sh ~/*/ 2>/dev/null | sort -rh | head -10" | awk '{print "    "$0}'
  else
    record_check "disk" "home_du" "SKIPPED" "0" "INFO" "skipped in quick mode"
  fi

  root_df=$(df -h / 2>/dev/null | awk 'NR==2{print $5}')
  add_kv "disk.root_used_percent" "${root_df:-N/A}"
fi

if section_allowed "network"; then
  section_header "Network"
  echo "  Active Interfaces & IPs:"
  ifconfig 2>/dev/null | awk '/^[a-z][a-z0-9]+:/{iface=$1} /inet /{printf "    %-14s %s\n", iface, $2}' | grep -v "127.0.0.1"

  echo ""
  echo "  DNS Servers:"
  dns_servers=$(scutil --dns 2>/dev/null | awk '/nameserver\[[0-9]+\]/{print $3}' | sort -u)
  [[ -n "$dns_servers" ]] && echo "$dns_servers" | awk '{print "    "$0}' || echo "    N/A"

  echo ""
  gateway=$(netstat -nr 2>/dev/null | awk '/^default/{print $2; exit}')
  echo "  Default Gateway: $(redact_value network.gateway "${gateway:-N/A}")"

  wifi_iface=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{f=1} f&&/Device:/{print $2; exit}')
  if [[ -n "$wifi_iface" ]]; then
    ssid=$(networksetup -getairportnetwork "$wifi_iface" 2>/dev/null | awk -F': ' '{print $2}')
    signal=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/agrCtlRSSI/{print $2; exit}')
    echo "  Wi-Fi SSID: $(redact_value network.ssid "${ssid:-Not connected}")"
    echo "  Wi-Fi Signal: ${signal:-N/A} dBm"
  else
    echo "  Wi-Fi: interface not found"
  fi

  echo ""
  echo "  VPN Connections:"
  vpn=$(scutil --nc list 2>/dev/null | grep -v '^$')
  [[ -n "$vpn" ]] && echo "$vpn" | head -10 | awk '{print "    "$0}' || echo "    None configured"

  add_kv "network.gateway" "${gateway:-N/A}"
  add_kv "network.dns" "$(echo "$dns_servers" | tr '\n' ',' | sed 's/,$//')"
  add_kv "network.ssid" "${ssid:-N/A}"

  if [[ "$NETWORK_TEST" -eq 1 ]]; then
    echo ""
    echo "  Active Network Tests:"
    if [[ -n "$gateway" ]] && run_with_timeout "$CHECK_TIMEOUT" "ping -c 1 -t 1 $gateway >/dev/null 2>&1"; then
      echo "    Gateway Ping: PASS"
      record_check "network" "gateway_ping" "PASS" "0" "INFO" "ok"
    else
      echo "    Gateway Ping: FAIL"
      record_check "network" "gateway_ping" "FAIL" "0" "WARN" "cannot reach gateway"
      add_finding "WARN" "Gateway ping failed"
    fi

    if run_with_timeout "$CHECK_TIMEOUT" "dscacheutil -q host -a name apple.com >/dev/null 2>&1"; then
      echo "    DNS Resolve (apple.com): PASS"
      record_check "network" "dns_resolve" "PASS" "0" "INFO" "ok"
    else
      echo "    DNS Resolve (apple.com): FAIL"
      record_check "network" "dns_resolve" "FAIL" "0" "WARN" "dns lookup failed"
      add_finding "WARN" "DNS lookup test failed"
    fi

    if run_with_timeout "$CHECK_TIMEOUT" "curl -I --max-time 5 https://www.apple.com >/dev/null 2>&1"; then
      echo "    HTTPS Reachability: PASS"
      record_check "network" "https_reachability" "PASS" "0" "INFO" "ok"
    else
      echo "    HTTPS Reachability: FAIL"
      record_check "network" "https_reachability" "FAIL" "0" "WARN" "https request failed"
      add_finding "WARN" "HTTPS reachability test failed"
    fi
  else
    record_check "network" "active_tests" "SKIPPED" "0" "INFO" "use --network-test to enable"
  fi
fi

if section_allowed "processes"; then
  section_header "Process Hotspots"
  echo "  Top 10 by CPU:"
  printf "    %-12s %-8s %-8s %s\n" "USER" "CPU%" "MEM%" "COMMAND"
  ps aux 2>/dev/null | sort -rk3 | awk 'NR>=2 && NR<=11{printf "    %-12s %-8s %-8s %s\n", $1, $3, $4, $11}'
  echo ""
  echo "  Top 10 by Memory:"
  printf "    %-12s %-8s %-8s %s\n" "USER" "CPU%" "MEM%" "COMMAND"
  ps aux 2>/dev/null | sort -rk4 | awk 'NR>=2 && NR<=11{printf "    %-12s %-8s %-8s %s\n", $1, $3, $4, $11}'
fi

if section_allowed "developer"; then
  section_header "Developer & Runtime Environment"

  print_ver() {
    local label="$1"
    local cmd="$2"
    if check_cmd "$cmd"; then
      ver=$($cmd --version 2>&1 | head -1)
      echo "  $label: ${ver:-unknown}"
      add_kv "runtime.${cmd}" "${ver:-unknown}"
    else
      echo "  $label: Not installed"
      add_kv "runtime.${cmd}" "not_installed"
    fi
  }

  print_ver "Git" git
  print_ver "Python3" python3
  print_ver "Node.js" node
  print_ver "Go" go
  print_ver "Docker" docker
  print_ver "Ruby" ruby
  print_ver "Rust" rustc

  if check_cmd java; then
    jv=$(java -version 2>&1 | head -1)
    echo "  Java: ${jv:-unknown}"
    add_kv "runtime.java" "${jv:-unknown}"
  else
    echo "  Java: Not installed"
    add_kv "runtime.java" "not_installed"
  fi

  rosetta=$(arch -arch x86_64 uname -m 2>/dev/null)
  if [[ "$rosetta" == "x86_64" ]]; then
    echo "  Rosetta 2: Installed"
    add_kv "runtime.rosetta2" "installed"
  else
    echo "  Rosetta 2: Not installed / N/A"
    add_kv "runtime.rosetta2" "not_installed_or_na"
  fi

  echo ""
  echo "  Package Managers:"
  if check_cmd brew; then
    formula_count=$(brew list --formula 2>/dev/null | wc -l | awk '{print $1}')
    cask_count=$(brew list --cask 2>/dev/null | wc -l | awk '{print $1}')
    echo "    Homebrew Formulae: $formula_count"
    echo "    Homebrew Casks: $cask_count"
    add_kv "pkg.brew_formula_count" "$formula_count"
    add_kv "pkg.brew_cask_count" "$cask_count"
    echo "    Homebrew Doctor (first 10 lines):"
    brew doctor 2>&1 | head -10 | awk '{print "      "$0}'
  else
    echo "    Homebrew: Not installed"
    add_kv "pkg.brew" "not_installed"
  fi

  if check_cmd mas; then
    mas_count=$(mas list 2>/dev/null | wc -l | awk '{print $1}')
    echo "    Mac App Store Apps: $mas_count"
    add_kv "pkg.mas_count" "$mas_count"
  else
    echo "    mas: Not installed"
    add_kv "pkg.mas" "not_installed"
  fi

  if check_cmd pipx; then
    pipx_count=$(pipx list 2>/dev/null | grep -c '^package ')
    echo "    pipx packages: $pipx_count"
    add_kv "pkg.pipx_count" "$pipx_count"
  else
    echo "    pipx: Not installed"
    add_kv "pkg.pipx" "not_installed"
  fi
fi

if section_allowed "applications"; then
  section_header "Installed Applications"
  ls /Applications 2>/dev/null | awk '{print "  "$0}'
  app_count=$(ls /Applications 2>/dev/null | wc -l | awk '{print $1}')
  add_kv "applications.count" "$app_count"
fi

if section_allowed "startup"; then
  section_header "Startup & Background Services"
  echo "  Login Items (current user):"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | sed 's/^[[:space:]]*/    /' || echo "    None"
  echo ""
  echo "  User LaunchAgents (~ /Library/LaunchAgents):"
  ls "$HOME"/Library/LaunchAgents/ 2>/dev/null | head -20 | awk '{print "    "$0}'
  echo ""
  echo "  System LaunchAgents (/Library/LaunchAgents):"
  ls /Library/LaunchAgents/ 2>/dev/null | head -20 | awk '{print "    "$0}'
  echo ""
  echo "  System LaunchDaemons (/Library/LaunchDaemons):"
  ls /Library/LaunchDaemons/ 2>/dev/null | head -20 | awk '{print "    "$0}'
fi

if section_allowed "mdm"; then
  section_header "MDM & Security Tooling"

  enrollment=$(profiles status -type enrollment 2>/dev/null)
  if [[ -n "$enrollment" ]]; then
    echo "  MDM Enrollment Status:"
    echo "$enrollment" | awk '{print "    "$0}'
    add_kv "mdm.enrollment" "present"
  else
    echo "  MDM Enrollment Status: unavailable"
    add_kv "mdm.enrollment" "unavailable"
  fi

  echo ""
  echo "  Configuration Profiles (first 20 lines):"
  profiles show -type configuration 2>/dev/null | head -20 | awk '{print "    "$0}'

  echo ""
  echo "  Security Tooling Detection:"
  launch_snapshot=$(launchctl list 2>/dev/null)
  tools="SentinelOne:sentinel CrowdStrike:falcon Defender:defender Sophos:sophos Jamf:jamf CarbonBlack:cbsensor Netskope:netskope"
  for t in $tools; do
    name=${t%%:*}
    pattern=${t##*:}
    if echo "$launch_snapshot" | grep -iq "$pattern" || pgrep -if "$pattern" >/dev/null 2>&1; then
      echo "    $name: detected"
      add_kv "security_tool.$name" "detected"
    else
      echo "    $name: not detected"
      add_kv "security_tool.$name" "not_detected"
    fi
  done
fi

if section_allowed "diff" && [[ -n "$BASELINE_COMPARE" ]]; then
  section_header "Baseline Diff"
  compare_baseline "$BASELINE_COMPARE"
fi

if section_allowed "health"; then
  section_header "Check Health"
  printf "  %-12s %-28s %-10s %-8s %-10s %s\n" "Section" "Check" "Status" "Time(s)" "Severity" "Message"
  printf '  %0.s-' {1..96}; echo ""
  for ((i=0; i<${#CHECK_SECTION[@]}; i++)); do
    printf "  %-12s %-28s %-10s %-8s %-10s %s\n" \
      "${CHECK_SECTION[$i]}" "${CHECK_NAME[$i]}" "${CHECK_STATUS[$i]}" "${CHECK_DURATION[$i]}" "${CHECK_SEVERITY[$i]}" "${CHECK_MESSAGE[$i]}"
  done
fi

if section_allowed "summary"; then
  section_header "Summary & Risk Score"

  warn_count=0
  crit_count=0
  info_count=0
  for ((i=0; i<${#FIND_SEV[@]}; i++)); do
    case "${FIND_SEV[$i]}" in
      WARN) warn_count=$((warn_count+1)) ;;
      CRITICAL) crit_count=$((crit_count+1)) ;;
      INFO) info_count=$((info_count+1)) ;;
    esac
  done

  score=$((100 - (warn_count * 8) - (crit_count * 20)))
  [[ "$score" -lt 0 ]] && score=0

  if [[ "$score" -ge 80 ]]; then
    risk="LOW"
  elif [[ "$score" -ge 50 ]]; then
    risk="MEDIUM"
  else
    risk="HIGH"
  fi

  echo "  Generated: $report_time"
  echo "  Mode: $MODE"
  echo "  Redacted: $REDACT"
  [[ -n "$OUTPUT_FILE" ]] && echo "  Report file: $OUTPUT_FILE"
  [[ -n "$JSON_OUT" ]] && echo "  JSON file: $JSON_OUT"
  [[ -n "$CSV_OUT" ]] && echo "  CSV file: $CSV_OUT"

  echo ""
  echo "  Risk Score: $score/100 ($risk)"
  echo "  Findings: CRITICAL=$crit_count WARN=$warn_count INFO=$info_count"

  if [[ ${#FIND_MSG[@]} -eq 0 ]]; then
    echo "  No findings."
  else
    echo ""
    echo "  Top Findings (up to 5):"
    shown=0
    for ((i=0; i<${#FIND_MSG[@]}; i++)); do
      echo "    [${FIND_SEV[$i]}] ${FIND_MSG[$i]}"
      shown=$((shown+1))
      [[ "$shown" -ge 5 ]] && break
    done
  fi

  add_kv "summary.risk_score" "$score"
  add_kv "summary.risk_level" "$risk"
  add_kv "summary.findings_critical" "$crit_count"
  add_kv "summary.findings_warn" "$warn_count"
  add_kv "summary.findings_info" "$info_count"
fi

if [[ -n "$BASELINE_SAVE" ]]; then
  save_baseline "$BASELINE_SAVE"
  echo ""
  echo "Baseline saved to: $BASELINE_SAVE"
fi

if [[ -n "$JSON_OUT" ]]; then
  write_json "$JSON_OUT"
  echo "JSON written to: $JSON_OUT"
fi

if [[ -n "$CSV_OUT" ]]; then
  write_csv "$CSV_OUT"
  echo "CSV written to: $CSV_OUT"
fi

echo ""
echo "======================================================================"
echo "  End of Report"
echo "======================================================================"
echo ""
