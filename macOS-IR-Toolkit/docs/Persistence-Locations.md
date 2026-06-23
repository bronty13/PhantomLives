# macOS Persistence / ASEP Map

Where macOS malware hides to survive reboot/login. The collector captures all of these
(`02_persistence/`). Attacker-writable spots (no SIP protection) are flagged ★.

## launchd — the big one

| Location | Scope | Notes |
|---|---|---|
| ★ `~/Library/LaunchAgents/` | per-user, at login | most common user-level persistence |
| ★ `/Library/LaunchAgents/` | all users, at login | needs admin to write |
| ★ `/Library/LaunchDaemons/` | system, at boot, as root | needs admin; highest value |
| `/System/Library/LaunchAgents,Daemons/` | Apple, SIP-protected | tampering here implies SIP off / very advanced |

Key plist keys: `Program` / `ProgramArguments` (what runs), `RunAtLoad`, `StartInterval`,
`WatchPaths`, `KeepAlive`. Red flags: payload in `/tmp`, `/Users/Shared`, `~/Library/...`,
a hidden dotfile, `bash -c`/`osascript`/`curl|sh`, random-looking Label.

## Login items & Background Task Management (BTM)

- **`sfltool dumpbtm`** (macOS 13+, root) — the authoritative modern view of login items,
  launch agents/daemons, and "allow in background" entries. The collector runs this
  (with a timeout — it can hang).
- Legacy: `~/Library/Application Support/com.apple.backgrounditems.btm` (binary plist).

## Scheduling

- ★ `crontab -l`, `/usr/lib/cron/tabs/<user>`, `/etc/crontab`
- `/etc/periodic/*`, `/etc/periodic.conf`, `/usr/local/etc/periodic` (non-default scripts ★)
- `at` jobs: `/var/at/jobs`

## Login/logout hooks & profiles

- ★ `defaults read com.apple.loginwindow LoginHook / LogoutHook` (legacy but still works)
- **Configuration profiles**: `profiles show -all` (root) / `profiles list` — MDM or rogue
  profiles can install payloads, trust certs, or weaken settings.

## Lower-level / advanced

- ★ Authorization plugins: `/Library/Security/SecurityAgentPlugins/`
- ★ `DYLD_INSERT_LIBRARIES` in a launchd plist's `EnvironmentVariables` (dylib injection)
- Third-party **kexts** (`kmutil showloaded | grep -v com.apple`) and **system extensions**
  (`systemextensionsctl list`) — modern malware uses Endpoint Security sysexts rarely;
  more often it's just a LaunchAgent.
- `emond` (Event Monitor) — **removed in Ventura**; only on ≤ Monterey
  (`/etc/emond.d/`, `/private/var/db/emondClients`).
- ★ `~/.zshrc`, `~/.zprofile`, `~/.bash_profile`, `/etc/zshenv` — shell-init persistence.
- ★ Cron-like `launchd` with `StartInterval` is far more common than real cron on macOS.

## TCC (not persistence, but adjacent)

`TCC.db` grants (user: `~/Library/Application Support/com.apple.TCC/TCC.db`; system:
`/Library/Application Support/com.apple.TCC/TCC.db`) show what apps were granted
Accessibility, Full Disk Access, Screen Recording, etc. Unexpected grants to a random
binary = strong lead. Reading the system DB needs root **and** Full Disk Access.

## Triage tip

Diff against a known-clean baseline where possible. On a single host, focus on:
non-Apple LaunchDaemons/Agents, BTM entries with odd paths, profiles you didn't install,
and TCC grants to anything outside `/Applications` or `/System`.
