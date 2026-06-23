# macOS IR Tool Cheatsheet

Built-in commands and the optional tools, with the flags that matter.

## Acquisition / volatile
```bash
sudo sysdiagnose -u -b -f /Volumes/Evidence        # broad volatile snapshot (-u no prompt)
lldb -x -b -o "process attach -p <pid>" \
     -o "process save-core -s full out.core" -o detach -o quit   # per-process core
```

## Live state
```bash
ps -axww -o pid,ppid,user,lstart,command           # processes + parentage
lsof -nP -i                                         # network connections (PID-mapped)
lsof -nP -iTCP -sTCP:LISTEN                         # listeners
netstat -an ; netstat -rn ; arp -an ; scutil --dns # sockets / routes / arp / dns
kmutil showloaded | grep -v com.apple              # third-party kexts
systemextensionsctl list                           # system extensions
launchctl list                                     # loaded launchd jobs (user domain)
```

## Persistence
```bash
sudo sfltool dumpbtm                               # login items / BTM (authoritative)
ls -la ~/Library/LaunchAgents /Library/Launch*     # launchd plists
plutil -p <file>.plist                             # print a plist readably
sudo profiles show -all                            # configuration profiles
crontab -l ; cat /etc/crontab                      # cron
defaults read com.apple.loginwindow LoginHook      # legacy hooks
```

## Signing / reputation (fast triage of a binary)
```bash
codesign -dv --verbose=4 /path/app.app             # signing identity / team id
spctl -a -vv /path/app.app                         # Gatekeeper assessment
xattr -p com.apple.quarantine /path/file           # quarantine flag (download origin)
mdls -name kMDItemWhereFroms /path/file            # where it came from
```

## Artifacts (SQLite)
```bash
sqlite3 ~/Library/Safari/History.db 'select datetime(visit_time+978307200,"unixepoch"),url from history_visits join history_items on history_item=id order by 1 desc limit 50;'
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 'select * from LSQuarantineEvent;'
log show --archive X.logarchive --predicate 'process == "sshd"' --style syslog
```

## Optional tools
```bash
yara -r -w -N -f rules.yar /Users                  # file scan (this toolkit's run-yara.sh)
sudo aftermath -o /Volumes/Evidence                # Jamf deep collection
sudo aftermath --analyze <archive>.zip             # parse an Aftermath archive
osqueryi "select name,path from launchd where program like '%/tmp/%';"   # live SQL
```

## Security posture (one-liners)
```bash
csrutil status        # SIP
spctl --status        # Gatekeeper
fdesetup status       # FileVault
```
