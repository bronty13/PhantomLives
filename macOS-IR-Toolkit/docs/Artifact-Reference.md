# macOS Artifact Reference

What each collected artifact is, what it proves, and how to parse it. Maps to the
`01_volatile/`, `02_persistence/`, `03_artifacts/` layout the collector produces.

## Execution / program activity

| Artifact | Location | What it proves | Parse with |
|---|---|---|---|
| **Unified log** | `/var/db/diagnostics` (raw); `log collect` → `.logarchive` | process exec, network, auth, TCC prompts, much more | `log show --archive X.logarchive --predicate '...'` |
| **Quarantine events** | `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` | what was downloaded, by which app, from which URL | `sqlite3` (table `LSQuarantineEvent`) |
| **Install history** | `/Library/Receipts/InstallHistory.plist`, `/var/log/install.log` | pkg installs, OS updates | `plutil -p`, grep |
| **knowledgeC** | `~/Library/Application Support/Knowledge/knowledgeC.db` | app focus/usage timeline | `sqlite3` (needs FDA) |
| **Spotlight / `mdls`** | per-file metadata | `kMDItemWhereFroms` (download origin), timestamps | `mdls <file>` |
| **FSEvents** | `/.fseventsd` | file create/rename/delete history (no content) | `FSEventsParser` (Obsidian/dfir tools) |

## Persistence — see `Persistence-Locations.md`.

## Network

| Artifact | Source | Notes |
|---|---|---|
| Live connections | `lsof -i`, `netstat -an` | process↔socket mapping (lsof) |
| Listening services | `lsof -nP -iTCP -sTCP:LISTEN` | unexpected listeners = backdoor |
| DNS / resolvers | `scutil --dns` | rogue resolver / DoH config |
| Interfaces | `ifconfig`, `networksetup` | promiscuous mode, rogue VPN |

## Accounts & auth

- `dscl . -list /Users`, `dscl . -read /Users/<u>` — local users, shells, UIDs (UID 0 ≠ root name = bad).
- `/etc/sudoers`, `/etc/sudoers.d/*` — privilege grants.
- Unified log auth events; `last` — login history.

## User activity

- **Shell history**: `~/.zsh_history` (default since Catalina), `~/.bash_history`.
- **Browsers**: Safari `~/Library/Safari/History.db` (FDA), Chrome
  `~/Library/Application Support/Google/Chrome/Default/History`, Firefox `places.sqlite`.
  All are SQLite — `sqlite3 ... 'select datetime(visit_time...), url ...'`.
- **TCC grants**: who got Accessibility/Screen-Recording/FDA (`TCC.db`).

## Timestamps & the MACB caveat

macOS HFS+/APFS tracks created/modified/accessed/changed. `stat -f` shows them; but
`SetFile`/`touch` and copies alter them. Cross-reference with the unified log and
FSEvents rather than trusting filesystem times alone. Spotlight's `kMDItemDateAdded` and
quarantine timestamps are often more reliable for "when did this land."

## Quick parse recipes

```bash
# Downloads with their source URL + timestamp:
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
  'select datetime(LSQuarantineTimeStamp+978307200,"unixepoch"), LSQuarantineAgentName, LSQuarantineDataURLString from LSQuarantineEvent order by 1 desc;'

# Process exec events from a collected log archive:
log show --archive 03_artifacts/unified_last7d.logarchive \
  --predicate 'eventMessage CONTAINS "exec"' --style syslog | head

# A file's download origin:
mdls -name kMDItemWhereFroms /path/to/suspect
```
