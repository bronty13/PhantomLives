#!/bin/bash
# macOS IR Toolkit -- dependency-free live-response triage collector.
#
# Pure bash + built-in macOS utilities. NO external binaries required, so it runs
# on a locked-down Mac immediately. Read-only with respect to the endpoint (it only
# reads and copies). Collects, in rough order of volatility:
#   00 context     : OS/hardware, SIP/Gatekeeper/FileVault, time, current users
#   01 volatile    : processes (+tree), network (lsof/netstat/arp/dns), kexts/sysexts,
#                    loaded launchd services, logged-on users, open network files
#   02 persistence : LaunchAgents/Daemons, login items (BTM), cron/periodic/at,
#                    login hooks, config profiles, TCC, sudoers, ssh, kexts
#   03 artifacts   : unified log archive, TCC.db, quarantine events, shell/browser
#                    history, install history, /var/log, FSEvents, knowledgeC
#   + SHA-256 manifest + an HTML report with chain-of-custody metadata.
#
# Output lands in:  <output>/<HOSTNAME>_<UTCYYYYMMDD_HHMMSS>/
#
# IMPORTANT (macOS-specific): run with sudo AND from a terminal that has Full Disk
# Access (System Settings > Privacy & Security > Full Disk Access). On macOS, even
# root cannot read TCC-protected paths (Safari history, Mail, Messages, the TCC
# databases, parts of ~/Library) unless the running process has Full Disk Access.
#
# Usage:  sudo ./collect-triage.sh [-o <outdir>] [--skip-artifacts] [--max-log-days N]
set -u

# ----------------------------- args -----------------------------
OUTPUT=""
SKIP_ARTIFACTS=0
MAX_LOG_DAYS=7
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)       OUTPUT="${2:-}"; shift 2;;
    --skip-artifacts)  SKIP_ARTIFACTS=1; shift;;
    --max-log-days)    MAX_LOG_DAYS="${2:-7}"; shift 2;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "[!] unknown arg: $1" >&2; shift;;
  esac
done

START_EPOCH=$(date +%s)

# ----------------------- privilege / FDA ------------------------
AM_ROOT=0; [ "$(id -u)" -eq 0 ] && AM_ROOT=1
if [ "$AM_ROOT" -ne 1 ]; then
  echo "[!] NOT running as root -- system artifacts (TCC, /var, other users) will be incomplete."
  echo "    Re-run with: sudo $0 $*"
fi

# ----------------------- choose output --------------------------
if [ -z "$OUTPUT" ]; then
  ext=""
  for v in /Volumes/*; do
    [ -d "$v" ] || continue
    # skip the boot/system volume; require >2GB free and writable
    case "$v" in /Volumes/Macintosh*|"/Volumes/Data") continue;; esac
    if [ -w "$v" ]; then
      free=$(df -k "$v" 2>/dev/null | awk 'NR==2{print $4}')
      [ -n "$free" ] && [ "$free" -gt 2097152 ] && { ext="$v"; break; }
    fi
  done
  if [ -n "$ext" ]; then OUTPUT="$ext/Evidence"; else OUTPUT="$HOME/Downloads/macOS-IR-Toolkit"; fi
fi

HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
CASE="$OUTPUT/${HOST}_${STAMP}"
VOL="$CASE/01_volatile"; PERS="$CASE/02_persistence"; ART="$CASE/03_artifacts"
mkdir -p "$VOL" "$PERS" "$ART" || { echo "[x] cannot create $CASE"; exit 1; }
LOG="$CASE/collection.log"

log()     { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }
section() { printf '\n=== %s ===\n' "$*"; log "SECTION $*"; }

CAP_TIMEOUT=45   # default per-step ceiling (seconds)

# run_to <seconds> <command-string>  -- run a shell command with a hard timeout,
# killing the WHOLE process subtree on expiry (some macOS tools, e.g. sfltool
# dumpbtm, can hang indefinitely). macOS has no timeout(1), so use perl (always
# present): the child setpgrp's into its own group and is killed by group on ALRM.
# Returns 124 on timeout. Caller redirects stdout.
run_to() {
  perl -e '
    my ($to,$cmd)=@ARGV;
    my $pid=fork;
    unless ($pid) { setpgrp; exec("/bin/sh","-c",$cmd); die "exec failed\n"; }
    $SIG{ALRM}=sub { kill "TERM",-$pid; sleep 1; kill "KILL",-$pid; exit 124; };
    alarm $to; waitpid($pid,0); alarm 0;
    exit($? >> 8);
  ' "$1" "$2"
}

# cap <dir> <file> '<shell command string>' [timeout]  -- run, capture stdout,
# never abort, never hang. Command strings are author-written literals (no external
# input), so the eval inside run_to is safe.
cap() {
  local dir="$1" file="$2" cmd="$3" to="${4:-$CAP_TIMEOUT}"; local p="$dir/$file"
  run_to "$to" "$cmd" >"$p" 2>/dev/null
  if [ "$?" -eq 124 ]; then echo "[TIMED OUT after ${to}s]" >>"$p"; log "  TO   $file (timeout ${to}s)"; return; fi
  if [ -s "$p" ]; then log "  ok   $file"; else log "  --   $file (empty/unavailable)"; fi
}

# copy <src> <subdir>  -- best-effort recursive copy into 03_artifacts/<subdir>.
copy() {
  local src="$1" sub="$2"; local d="$ART/$sub"
  [ -e "$src" ] || return 0
  mkdir -p "$d"
  if cp -Rp "$src" "$d/" 2>/dev/null; then log "  copied $src"
  else log "  LOCKED $src (permission / TCC / in use)"; fi
}

log "macOS IR Toolkit -- live triage collector"
log "Case dir: $CASE   (root=$AM_ROOT)"

# ====================================================== 00 CONTEXT
section "00 Context"
cap "$CASE" collector_self_hash.txt "shasum -a 256 '$0'"
cap "$CASE" os_version.txt          "sw_vers; echo; uname -a; echo; sysctl -n machdep.cpu.brand_string 2>/dev/null; sysctl -n hw.model"
cap "$CASE" hardware.txt            "system_profiler SPHardwareDataType"
cap "$CASE" security_posture.txt    "echo '== SIP (csrutil) =='; csrutil status; echo; echo '== Gatekeeper (spctl) =='; spctl --status 2>&1; echo; echo '== FileVault =='; fdesetup status 2>&1; echo; echo '== Secure Boot / activation =='; system_profiler SPiBridgeDataType 2>/dev/null"
cap "$CASE" datetime.txt            "echo \"Collected (local): \$(date)\"; echo \"Collected (UTC):   \$(date -u)\"; echo \"Time zone: \$(readlink /etc/localtime 2>/dev/null)\"; echo; uptime"
cap "$CASE" identity.txt            "echo \"whoami: \$(whoami)\"; id; echo; echo '== console / logged-in =='; who; echo; w"
cap "$CASE" local_users.txt         "echo '== dscl users =='; dscl . -list /Users UniqueID 2>/dev/null | sort -k2 -n; echo; echo '== admin group =='; dscl . -read /Groups/admin GroupMembership 2>/dev/null"

# ====================================================== 01 VOLATILE
section "01 Volatile state"
cap "$VOL" processes.txt        "ps aux"
cap "$VOL" processes_full.txt   "ps -axww -o pid,ppid,uid,user,%cpu,%mem,lstart,command"
# Iterative (cycle-safe) process tree from pid/ppid -- no recursion.
cap "$VOL" process_tree.txt '
ps -axwwo pid,ppid,comm | awk '\''
NR>1 { pid=$1; ppid=$2; $1="";$2=""; sub(/^  */,""); name[pid]=$0; parent[pid]=ppid; kids[ppid]=kids[ppid] " " pid }
END {
  # roots: ppid 0/1-less or parent not present; print iteratively with an explicit stack
  for (p in name) if (!(parent[p] in name) || parent[p]==0) roots=roots " " p
  n=split(roots, R, " ")
  for (i=1;i<=n;i++){ if(R[i]=="")continue; stackp=1; stack[1]=R[i]; depth[R[i]]=0
    while(stackp>0){ cur=stack[stackp]; stackp--
      if(seen[cur]++)continue
      pad=""; for(d=0;d<depth[cur];d++) pad=pad "  "
      printf "%s%s (pid %s)\n", pad, name[cur], cur
      m=split(kids[cur], K, " ")
      for(j=m;j>=1;j--){ if(K[j]==""||seen[K[j]])continue; stackp++; stack[stackp]=K[j]; depth[K[j]]=depth[cur]+1 }
    }
  }
  # any process never reached (cycle) -- print flat so nothing is dropped
  for (p in name) if(!seen[p]) printf "%s (pid %s)  [unreached -- cycle?]\n", name[p], p
}'\'''
cap "$VOL" net_connections.txt  "lsof -nP -i 2>/dev/null"
cap "$VOL" net_listening.txt    "echo '== TCP LISTEN =='; lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null; echo; echo '== UDP =='; lsof -nP -iUDP 2>/dev/null"
cap "$VOL" netstat.txt          "netstat -an"
cap "$VOL" routes.txt           "netstat -rn"
cap "$VOL" arp.txt              "arp -an"
cap "$VOL" dns.txt              "scutil --dns"
cap "$VOL" interfaces.txt       "ifconfig -a; echo; networksetup -listallhardwareports 2>/dev/null"
cap "$VOL" kexts.txt            "kmutil showloaded 2>/dev/null || kextstat 2>/dev/null"
cap "$VOL" system_extensions.txt "systemextensionsctl list 2>/dev/null"
cap "$VOL" launchctl_running.txt "echo '== user domain =='; launchctl list 2>/dev/null; echo; echo '== system domain =='; \$( [ $AM_ROOT -eq 1 ] && echo 'launchctl print system' ) 2>/dev/null"
cap "$VOL" logged_on.txt        "who; echo; echo '== last 30 logins =='; last -30 2>/dev/null"
cap "$VOL" mounts.txt           "mount; echo; df -h"
cap "$VOL" env_launchd.txt      "launchctl getenv DYLD_INSERT_LIBRARIES 2>/dev/null; launchctl getenv DYLD_LIBRARY_PATH 2>/dev/null; echo done"

# ====================================================== 02 PERSISTENCE
section "02 Persistence / ASEP"

# LaunchAgents/Daemons -- dump non-Apple ones fully (these are the attacker-writable spots).
dump_launchd() {
  local base="$1"
  [ -d "$base" ] || return 0
  for plist in "$base"/*.plist; do
    [ -e "$plist" ] || continue
    echo "==== $plist ===="
    plutil -p "$plist" 2>/dev/null || cat "$plist" 2>/dev/null
    echo
  done
}
cap "$PERS" launchd_user_agents.txt   "for u in /Users/*; do [ -d \"\$u/Library/LaunchAgents\" ] && { echo \"#### \$u ####\"; dump_launchd \"\$u/Library/LaunchAgents\"; }; done"
cap "$PERS" launchd_library.txt        "echo '######## /Library/LaunchAgents ########'; dump_launchd /Library/LaunchAgents; echo '######## /Library/LaunchDaemons ########'; dump_launchd /Library/LaunchDaemons"
cap "$PERS" launchd_system_listing.txt "echo '(System launchd items are Apple-signed/SIP-protected; listing names only)'; ls -la /System/Library/LaunchAgents /System/Library/LaunchDaemons 2>/dev/null"
cap "$PERS" login_items_btm.txt        "echo '== Background Task Management (sfltool dumpbtm; needs root, macOS 13+) =='; sfltool dumpbtm 2>/dev/null || echo '(unavailable -- need root / older macOS)'" 25
cap "$PERS" login_items_legacy.txt     "for u in /Users/*; do f=\"\$u/Library/Application Support/com.apple.backgrounditems.btm\"; [ -e \"\$f\" ] && { echo \"## \$(basename \"\$u\"): \$f ##\"; plutil -p \"\$f\" 2>/dev/null; }; done; echo '(authoritative login-item/persistence source is sfltool dumpbtm -- see login_items_btm.txt)'"
cap "$PERS" cron.txt                   "echo '== current-user crontab =='; crontab -l 2>/dev/null; echo; echo '== /usr/lib/cron/tabs =='; ls -la /usr/lib/cron/tabs 2>/dev/null; \$( [ $AM_ROOT -eq 1 ] && echo 'cat /usr/lib/cron/tabs/* 2>/dev/null' ); echo; echo '== /etc/crontab =='; cat /etc/crontab 2>/dev/null"
cap "$PERS" periodic.txt               "echo '== /etc/periodic.conf =='; cat /etc/periodic.conf 2>/dev/null; echo; echo '== /etc/periodic /usr/local/etc/periodic (non-default scripts) =='; find /etc/periodic /usr/local/etc/periodic -type f 2>/dev/null | xargs ls -la 2>/dev/null"
cap "$PERS" at_jobs.txt                "ls -la /var/at/jobs 2>/dev/null"
cap "$PERS" login_hooks.txt            "echo '== com.apple.loginwindow Login/LogoutHook =='; defaults read com.apple.loginwindow LoginHook 2>/dev/null; defaults read com.apple.loginwindow LogoutHook 2>/dev/null; echo done"
cap "$PERS" config_profiles.txt        "profiles list 2>/dev/null; echo; \$( [ $AM_ROOT -eq 1 ] && echo 'profiles show -all' ) 2>/dev/null || profiles -P 2>/dev/null"
cap "$PERS" tcc_access.txt             "echo '== user TCC =='; sqlite3 \"\$HOME/Library/Application Support/com.apple.TCC/TCC.db\" 'select client,auth_value,service from access' 2>/dev/null; echo; echo '== system TCC =='; sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' 'select client,auth_value,service from access' 2>/dev/null || echo '(need Full Disk Access + root)'"
cap "$PERS" sudoers.txt                "cat /etc/sudoers 2>/dev/null; echo; echo '== /etc/sudoers.d =='; ls -la /etc/sudoers.d 2>/dev/null; cat /etc/sudoers.d/* 2>/dev/null"
cap "$PERS" ssh_config.txt             "echo '== /etc/ssh/sshd_config =='; grep -vE '^\s*#|^\s*\$' /etc/ssh/sshd_config 2>/dev/null; echo; for u in /Users/*; do [ -f \"\$u/.ssh/authorized_keys\" ] && { echo \"## authorized_keys: \$u ##\"; cat \"\$u/.ssh/authorized_keys\"; }; done"
cap "$PERS" third_party_kexts.txt      "kmutil showloaded 2>/dev/null | grep -iv com.apple || echo '(none non-Apple, or kmutil unavailable)'"
cap "$PERS" emond.txt                  "echo '(emond removed in Ventura+; present only on older macOS)'; ls -la /etc/emond.d /private/var/db/emondClients 2>/dev/null"

# ====================================================== 03 ARTIFACTS
if [ "$SKIP_ARTIFACTS" -ne 1 ]; then
  section "03 Artifact copies"

  # Unified log -- the macOS analogue of the Windows Event Log. Bounded by --max-log-days.
  log "  collecting unified log (last ${MAX_LOG_DAYS}d) -- this can be large/slow..."
  if log collect --output "$ART/unified_last${MAX_LOG_DAYS}d.logarchive" --last "${MAX_LOG_DAYS}d" 2>/dev/null; then
    log "  ok   unified_last${MAX_LOG_DAYS}d.logarchive"
  else
    log "  --   unified log collect failed (need root); falling back to 'log show' text"
    log show --last "${MAX_LOG_DAYS}d" --style syslog >"$ART/unified_log_show.txt" 2>/dev/null || true
  fi

  # TCC databases (user + system), quarantine events, knowledgeC
  for u in /Users/*; do
    un=$(basename "$u"); [ "$un" = "Shared" ] && continue
    copy "$u/Library/Application Support/com.apple.TCC/TCC.db"                         "Users/$un/TCC"
    copy "$u/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"          "Users/$un/Quarantine"
    copy "$u/Library/Application Support/Knowledge/knowledgeC.db"                       "Users/$un/KnowledgeC"
    copy "$u/.zsh_history"                                                              "Users/$un/Shell"
    copy "$u/.bash_history"                                                             "Users/$un/Shell"
    copy "$u/.sh_history"                                                               "Users/$un/Shell"
    copy "$u/Library/Safari/History.db"                                                 "Users/$un/Browser/Safari"
    copy "$u/Library/Application Support/Google/Chrome/Default/History"                 "Users/$un/Browser/Chrome"
    # Firefox places.sqlite (profile dir name varies)
    for ff in "$u"/Library/Application\ Support/Firefox/Profiles/*/places.sqlite; do
      [ -e "$ff" ] && copy "$ff" "Users/$un/Browser/Firefox"
    done
    copy "$u/Library/LaunchAgents"                                                      "Users/$un/LaunchAgents"
  done
  copy "/Library/Application Support/com.apple.TCC/TCC.db"  "System/TCC"
  copy "/Library/LaunchAgents"                              "System/LaunchAgents"
  copy "/Library/LaunchDaemons"                             "System/LaunchDaemons"

  # Install history + system logs
  copy "/Library/Receipts/InstallHistory.plist"  "InstallHistory"
  copy "/var/log/install.log"                    "SystemLogs"
  # NOTE: the raw /var/db/diagnostics tracev3 store is intentionally NOT copied -- the
  # 'log collect' archive above is the analyst-friendly capture of the same data, and
  # the raw store can be multiple GB. Add it back only if you need raw tracev3 for a
  # tool like UnifiedLogReader/mac_apt.
  for l in /var/log/system.log*; do [ -e "$l" ] && copy "$l" "SystemLogs"; done
  copy "/etc/hosts"   "Network"
  copy "/etc/passwd"  "AccountDB"
  copy "/etc/group"   "AccountDB"
  # FSEvents (root-only; can be large)
  copy "/.fseventsd"  "FSEvents"

  log "Artifact copy complete."
else
  section "03 Artifact copies"; log "SKIPPED (--skip-artifacts)"
fi

# ====================================================== MANIFEST + REPORT
section "Manifest + report"
MANIFEST="$CASE/SHA256_MANIFEST.csv"
echo "RelPath,Bytes,SHA256,ModifiedUTC" > "$MANIFEST"
( cd "$CASE" && find . -type f ! -name 'SHA256_MANIFEST.csv' -print0 | while IFS= read -r -d '' f; do
    rel="${f#./}"
    bytes=$(stat -f '%z' "$f" 2>/dev/null)
    mtime=$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$f" 2>/dev/null)
    sha=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'); [ -z "$sha" ] && sha=ERR
    printf '%s,%s,%s,%s\n' "$rel" "$bytes" "$sha" "$mtime"
  done ) >> "$MANIFEST"
log "Wrote $MANIFEST"

DUR=$(( $(date +%s) - START_EPOCH ))
FILES=$(find "$CASE" -type f | wc -l | tr -d ' ')
REPORT="$CASE/REPORT.html"
osver=$(sw_vers -productVersion 2>/dev/null)
model=$(sysctl -n hw.model 2>/dev/null)
{
cat <<HTML
<!doctype html><html><head><meta charset=utf-8><title>macOS IR Triage -- ${HOST}</title>
<style>body{font:14px/1.5 -apple-system,Segoe UI,Arial;margin:2em;color:#222}h1{color:#7a3ea0}
code,pre{background:#f4f4f8;padding:.2em .4em;border-radius:4px}table{border-collapse:collapse}
td,th{border:1px solid #ddd;padding:.3em .6em;text-align:left}.k{color:#666}</style></head><body>
<h1>macOS IR Triage Report</h1>
<p class=k>Generated by collect-triage.sh (macOS IR Toolkit). Automated COLLECTION summary,
not an analysis verdict. Review the per-section files; correlate with docs/Artifact-Reference.md.</p>
<h2>Chain of custody</h2>
<table>
<tr><th>Host</th><td>${HOST}</td></tr>
<tr><th>macOS</th><td>${osver} on ${model}</td></tr>
<tr><th>Collected (UTC)</th><td>${STAMP}</td></tr>
<tr><th>Collector</th><td>$(whoami) (root=${AM_ROOT})</td></tr>
<tr><th>Evidence dir</th><td><code>${CASE}</code></td></tr>
<tr><th>Files collected</th><td>${FILES}</td></tr>
<tr><th>Duration</th><td>${DUR} s</td></tr>
<tr><th>Integrity</th><td>SHA256_MANIFEST.csv (per-file hashes)</td></tr>
</table>
<h2>Where to look next</h2>
<ul>
<li><b>01_volatile/</b> -- net_connections.txt (unexpected outbound?), process_tree.txt, launchctl_running.txt, system_extensions.txt</li>
<li><b>02_persistence/</b> -- launchd_*.txt (non-Apple agents/daemons), login_items_btm.txt, cron.txt, config_profiles.txt, tcc_access.txt</li>
<li><b>03_artifacts/</b> -- unified log archive, quarantine events, browser/shell history (parse offline; see docs/Triage-Runbook.md)</li>
</ul>
<p class=k>Next: run scripts/run-yara.sh over the host and (optional) scripts/run-aftermath.sh for deep collection.</p>
</body></html>
HTML
} > "$REPORT"

echo
echo "[+] DONE."
echo "    Evidence : $CASE"
echo "    Report   : $REPORT"
echo "    Manifest : $MANIFEST"
echo "    Files    : $FILES   Duration: ${DUR}s"
echo
echo "[!] Verify SHA256_MANIFEST.csv and store evidence on write-protected media."
[ "$AM_ROOT" -ne 1 ] && echo "[!] Re-run with sudo + Full Disk Access for system artifacts (TCC, /var, unified log)."
exit 0
