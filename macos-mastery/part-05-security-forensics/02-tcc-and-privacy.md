---
title: TCC & Privacy Internals
part: P05 Security/Forensics
est_time: 50 min read + 40 min labs
prerequisites: [01-boot-process, sip-and-system-integrity]
tags: [macos, tcc, privacy, forensics, security, sqlite, mdm, pppc]
---

# TCC & Privacy Internals

> **In one sentence:** Transparency, Consent & Control (TCC) is macOS's privacy gatekeeper — a pair of SIP-protected SQLite databases that record every app's authorization to touch sensitive resources, making them simultaneously the system's most important privacy enforcement mechanism and its richest forensic artifact.

## Why this matters

TCC is the fence between every application and the camera, microphone, screen contents, user files, and system automation surfaces. When you grant Full Disk Access to a terminal emulator, you are handing that process (and anything it spawns) unfettered read-write access to every file on the system, including other users' keychains, mail, and Messages. When you revoke Accessibility from a screen reader, it stops cold. No kernel module, no entitlement waiver — TCC is the control plane.

For forensics, TCC.db is a timestamped authorization ledger: which apps touched what, when they first asked, and whether the user said yes. The presence of a Full Disk Access grant for `com.some.rat` on a machine under investigation is significant. An entry for `kTCCServiceScreenCapture` for an app the user has never heard of is more so.

For builders: every PhantomLives app that needs protected resources must understand the mechanics so it triggers prompts at the right time, from the right process, and degrades gracefully when denied.

## Concepts

### The TCC Architecture

TCC is implemented in the `tccd` daemon (Privacy Daemon), which lives in `/System/Library/PrivateFrameworks/TCC.framework/Support/tccd`. It is always running, and nothing bypasses it without either a SIP violation or an entitlement signed by Apple. Calls flow through the `PrivacyServices` XPC interface; you never talk to `tccd` directly — your process calls a framework API (`AVCaptureDevice.requestAccess(for:)`, `CNContactStore.requestAccess(for:)`, `NSAppleEventDescriptor`, etc.), the framework marshals the request to `tccd`, and `tccd` checks its database.

The daemon manages two databases:

| Database | Path | Who can write |
|---|---|---|
| System | `/Library/Application Support/com.apple.TCC/TCC.db` | `tccd` (root-owned, SIP-locked) |
| User | `~/Library/Application Support/com.apple.TCC/TCC.db` | `tccd` running as that user |

Both are SQLite 3 files. Both are SIP-protected: `ls -lO` shows the `restricted` flag, and even root cannot modify them directly while SIP is enabled. You **can** read them if you have Full Disk Access (FDA) — terminal, your forensic tool, or `sqlite3` — but writes via the filesystem are blocked. The only sanctioned mutation path is `tccd` itself, via `tccutil` or UI approval.

> 🔬 **Forensics note:** SIP protection means an attacker without kernel access cannot silently patch TCC.db. But a compromised `tccd`, a SIP bypass, or an MDM-pushed configuration profile can all alter authorizations without a visible prompt. The `last_modified` timestamp and `auth_reason` column tell you *how* an entry was created — MDM grants look different from user consent.

### Protected Services (the Full List)

TCC service names are string constants prefixed `kTCCService`. These are the ones you encounter in practice:

**Hardware**
- `kTCCServiceCamera` — camera
- `kTCCServiceMicrophone` — microphone
- `kTCCServiceBluetooth` — Bluetooth peripherals (introduced in Catalina)

**Screen & Input**
- `kTCCServiceScreenCapture` — screen recording, screenshots (this is the reconsent one)
- `kTCCServiceListenEvent` — input monitoring (keyboard/mouse listener — keylogger territory)
- `kTCCServicePostEvent` — posting synthetic key/mouse events (Accessibility automation subset)

**Files & Folders**
- `kTCCServiceSystemPolicyAllFiles` — Full Disk Access (FDA): reads every file on every mounted volume, bypasses per-directory checks
- `kTCCServiceSystemPolicyDocumentsFolder` — `~/Documents/`
- `kTCCServiceSystemPolicyDesktopFolder` — `~/Desktop/`
- `kTCCServiceSystemPolicyDownloadsFolder` — `~/Downloads/`
- `kTCCServiceSystemPolicyNetworkVolumes` — network-mounted volumes
- `kTCCServiceSystemPolicyRemovableVolumes` — USB/Thunderbolt drives
- `kTCCServiceFileProviderPresence` — File Provider extensions (iCloud Drive, Dropbox)
- `kTCCServiceFileProviderDomain` — accessing specific File Provider domains

**Identity / Personal Data**
- `kTCCServiceAddressBook` — Contacts
- `kTCCServiceCalendar` — Calendar
- `kTCCServiceReminders` — Reminders
- `kTCCServicePhotos` — Photos library (limited vs. full variants since Big Sur)
- `kTCCServiceLocation` — Location Services (the TCC side; Core Location has its own daemon `locationd`)

**Automation & IPC**
- `kTCCServiceAppleEvents` — sending Apple Events to another app; target is recorded in `indirect_object_identifier`
- `kTCCServiceAutomation` — synonym for certain scripting permissions
- `kTCCServiceAccessibility` — Accessibility API: UI element inspection, synthetic events, window enumeration

**Developer / Admin**
- `kTCCServiceDeveloperTool` — developer tools exception (Xcode, lldb, `swift run`); skips some sandbox checks
- `kTCCServiceSystemPolicySysAdminFiles` — system admin file paths (Safari's cookie store, etc.)

> 🔬 **Forensics note:** `kTCCServiceListenEvent` + `kTCCServicePostEvent` together constitute a software keylogger. `kTCCServiceSystemPolicyAllFiles` is the most dangerous single grant — forensically, its presence for any unexpected app is a red flag.

### The TCC.db Schema

Both databases share the same schema. The investigatively important table is `access`.

```sql
CREATE TABLE access (
    service          TEXT NOT NULL,
    client           TEXT NOT NULL,
    client_type      INTEGER NOT NULL,   -- 0 = bundle ID, 1 = absolute path
    auth_value       INTEGER NOT NULL,   -- 0=denied, 1=unknown, 2=allowed, 3=limited
    auth_reason      INTEGER NOT NULL,   -- see below
    auth_version     INTEGER NOT NULL,   -- schema version, usually 1
    csreq            BLOB,               -- code-signing requirement blob
    policy_id        INTEGER,            -- MDM policy reference (NULL = user consent)
    indirect_object_identifier_type  INTEGER,
    indirect_object_identifier       TEXT,  -- Apple Events target bundle/path
    indirect_object_code_identity    BLOB,
    flags            INTEGER,
    last_modified    INTEGER NOT NULL,   -- Unix epoch (seconds)
    PRIMARY KEY (service, client, client_type, indirect_object_identifier, ...)
);
```

**`auth_value` meanings:**

| Value | Meaning |
|---|---|
| 0 | Denied |
| 1 | Unknown (asked but not answered yet, or reset) |
| 2 | Allowed |
| 3 | Limited (e.g., selected photos only, not full library) |

**`auth_reason` meanings (forensically important):**

| Value | Meaning |
|---|---|
| 1 | Error |
| 2 | User Consent (prompt shown, user clicked Allow) |
| 3 | User Set (user toggled in System Settings) |
| 4 | System Set (Apple-internal policy) |
| 5 | Service Policy |
| 6 | MDM Policy (pushed by PPPC profile — NO user prompt was shown) |
| 7 | Override Policy |
| 8 | Missing Usage String (entitlement granted without `NSUsageDescription`) |
| 9 | Prompt Timeout |
| 10 | Pre-flight Unknown |
| 11 | Entitled |
| 12 | App Type Policy |

> 🔬 **Forensics note:** `auth_reason = 6` means an MDM PPPC profile silently granted access — the user never saw a dialog. This is normal in managed enterprise environments but suspicious on a personally-owned machine. `auth_reason = 2` with `policy_id NULL` is the canonical "user clicked Allow in the prompt."

The `csreq` blob is a binary code-signing requirement. It prevents bundle-ID spoofing: even if an attacker renames their app `com.apple.Safari`, the `csreq` check will fail because it won't match Safari's actual signing identity. You can decode it:

```bash
# Decode a csreq blob to human-readable requirement string
echo "<hex-from-db>" | xxd -r -p | codesign -d --entitlements - /dev/stdin 2>/dev/null
# Or via csreq tool:
csreq -r - -t <<< "$(sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT hex(csreq) FROM access WHERE client='com.example.app' LIMIT 1;")"
```

There are also supporting tables:

- `admin` — stores TCC schema version metadata
- `policies` — MDM/PPPC policy records
- `active_policy` / `active_policy_id` — the currently active MDM policy
- `access_overrides` — temporary overrides (rare; used by some system processes)
- `expired` — past grants that have expired (forensically useful — an entry here means a permission *was* granted then removed)

### Responsible Process Attribution

When an app triggers a TCC prompt, macOS identifies the **responsible process** — not necessarily the calling process. This matters for terminal and scripting:

- You run `python3 camera_test.py` in iTerm2. The prompt says "iTerm" wants camera access if the terminal is the responsible process; if the Python script has its own bundle ID (packaged app), the prompt attributes to the Python app.
- Scripting bridges (`osascript`, `NSAppleScript`) attribute to the *script's host*, not the called app.
- XPC services attribute to the hosting app, not the service bundle. This is why granting access to, say, Homebrew's `ffmpeg` grants it to the invoking terminal emulator's bundle — they share the responsible-process attribution.

The mechanism: `tccd` walks the process tree using `SecCodeCopyGuestWithAttributes` to find the first ancestor with a valid bundle ID and code signature. That ancestor owns the TCC entry.

> 🔬 **Forensics note:** This means a `client` entry in TCC.db for `com.apple.Terminal` doesn't tell you which *script* ran; it just tells you Terminal (or something running under Terminal's attribution) was granted the permission. Attribution laundering — spawning a sensitive operation from a trusted parent — is a known evasion technique.

### The "High-Value" Grants

Three grants are categorically more dangerous than the others and deserve special attention both operationally and forensically:

**Full Disk Access (`kTCCServiceSystemPolicyAllFiles`)**
This bypasses not just per-directory TCC checks but also sandbox restrictions for reading files. An FDA-granted process can read `/private/var/db/`, other users' home directories, Time Machine backups, mail stores, and every credential in every keychain on disk. Only SIP-protected paths (the sealed system volume, `/System/Library/`) remain off-limits. FDA grants are stored in the **system** TCC.db, not the user one — they require admin authentication to grant.

**Accessibility (`kTCCServiceAccessibility`)**
An Accessibility-granted app can enumerate every UI element of every running app, inject synthetic keystrokes, click UI elements, and read on-screen content. This is the permission that makes macro tools (Keyboard Maestro, BetterTouchTool) work — and also what makes remote-access trojans complete. Accessibility grants live in the **system** TCC.db and require admin elevation.

**Screen Recording (`kTCCServiceScreenCapture`)**
Grants pixel-level capture of any window or the full display, plus audio-capture from window content. Since macOS 14 Sonoma and hardened further in macOS 15 Sequoia, this is one of the few TCC resources that **cannot be pre-granted via MDM PPPC** — it always requires explicit user interaction in System Settings > Privacy & Security > Screen & System Audio Recording.

### Sequoia's Monthly Screen Recording Reconsent

macOS 15 Sequoia introduced recurring consent for screen recording, continued and refined in macOS 26 Tahoe. The mechanism:

- Approval timestamps are stored in `~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist`
- The system prompts again approximately monthly (originally weekly in early betas; Apple dialed it back)
- The plist is itself TCC-protected — the system owns it, not the user
- Apps can avoid reconsent by obtaining the `com.apple.developer.persistent-content-capture` entitlement, which Apple grants to VNC-class apps (screen sharing, remote desktop)
- Frequently-used apps get some latitude; infrequently used apps are prompted sooner

This is controversial — it replicates Windows Vista's permission fatigue for legitimate tools like color pickers, screenshot utilities, and accessibility software — but it means screen recording is the hardest TCC grant to automate away on a managed fleet.

> 🔬 **Forensics note:** Examine `ScreenCaptureApprovals.plist` during an investigation. The approval timestamps can corroborate or contradict a user's claim about when they first allowed a screen capture app. A very old approval date on a recently-installed app is anomalous.

### MDM / PPPC: Pre-Granting Permissions at Scale

In managed environments (Jamf, Mosyle, Kandji, Workspace ONE), administrators push **Privacy Preference Policy Control (PPPC)** profiles to pre-approve TCC prompts. These are `com.apple.TCC.configuration-profile-policy` payloads containing:

- `Services` dictionary keyed by service name
- Per-app records with `Identifier` (bundle ID), `IdentifierType`, `CodeRequirement` (the signing requirement string), `Allowed` (bool), and optionally `Authorization` (Allow/Deny/AllowStandardUserToSetSystemService)

PPPC profiles land in the **system** TCC.db as `auth_reason = 6` entries. They can pre-approve most services but **not** Screen Recording (Apple's deliberate carve-out — it cannot be MDM-managed) and not Input Monitoring on some OS versions.

```bash
# Inspect installed configuration profiles (requires admin)
sudo profiles list -verbose

# Show all TCC-related profiles
sudo profiles show -type configuration | grep -A 20 "TCC"
```

> 🔬 **Forensics note:** On a corporate machine, PPPC-granted entries are normal. On a personal machine, a PPPC entry (`auth_reason = 6`, non-null `policy_id`) means an MDM profile was enrolled — either legitimately (corporate ownership) or maliciously (a rogue profile installed by an attacker). Check `sudo profiles list` to see what profiles exist.

### MDMM is Not Magic: When tccutil is Needed

`tccutil` is the command-line interface to `tccd` for resetting permissions. Resets are the only sanctioned non-GUI mutation path for non-MDM machines:

```bash
# Reset ALL grants for a service (will re-prompt next time any app requests it)
tccutil reset Camera

# Reset only one app's grant
tccutil reset Microphone com.zoom.xos

# Reset Full Disk Access for a specific terminal
tccutil reset SystemPolicyAllFiles com.apple.Terminal
```

Service names for `tccutil` are the human-readable portion of `kTCCService*` (drop the prefix, and use the SDK constant name without the prefix for file services):

| tccutil service name | kTCCService constant |
|---|---|
| `Camera` | `kTCCServiceCamera` |
| `Microphone` | `kTCCServiceMicrophone` |
| `ScreenCapture` | `kTCCServiceScreenCapture` |
| `Accessibility` | `kTCCServiceAccessibility` |
| `SystemPolicyAllFiles` | `kTCCServiceSystemPolicyAllFiles` |
| `SystemPolicyDocumentsFolder` | `kTCCServiceSystemPolicyDocumentsFolder` |
| `SystemPolicyDesktopFolder` | `kTCCServiceSystemPolicyDesktopFolder` |
| `SystemPolicyDownloadsFolder` | `kTCCServiceSystemPolicyDownloadsFolder` |
| `AddressBook` | `kTCCServiceAddressBook` |
| `Calendar` | `kTCCServiceCalendar` |
| `Photos` | `kTCCServicePhotos` |
| `AppleEvents` | `kTCCServiceAppleEvents` |
| `ListenEvent` | `kTCCServiceListenEvent` |
| `PostEvent` | `kTCCServicePostEvent` |
| `DeveloperTool` | `kTCCServiceDeveloperTool` |

A full reset (`tccutil reset Camera` with no bundle ID) clears the entire service table — all apps lose camera permission and will re-prompt. This is useful for fleet troubleshooting and for resetting a machine before imaging. It cannot be undone short of re-prompting each app.

> 🪟 **Windows contrast:** Windows has two analogous systems: UAC (User Account Control), which gates privilege elevation rather than resource access, and the UWP/Windows Runtime permission model (similar to TCC for camera/mic/location in Store apps). Classic Win32 apps bypass the UWP permission model entirely — there is no equivalent of TCC for arbitrary Win32 processes touching the filesystem. macOS TCC applies to all processes including CLI tools. On Windows, the closest forensic artifact is the Security event log (Event IDs 4688, 4624) and the `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\` registry hive, which records UWP permission grants.

## Hands-on (CLI & GUI)

### Reading TCC.db (Read-Only Audit)

Your terminal needs FDA to read the user TCC.db. Grant it in System Settings > Privacy & Security > Full Disk Access, toggle on your terminal emulator, then:

```bash
# User database — every grant and denial with timestamps
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, auth_reason, datetime(last_modified,'unixepoch','localtime')
   FROM access ORDER BY last_modified DESC;"
```

```bash
# System database (FDA + sudo) — Accessibility, FDA, Automation grants
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, auth_reason, datetime(last_modified,'unixepoch','localtime')
   FROM access ORDER BY last_modified DESC;"
```

```bash
# All ALLOWED grants across both databases (combined view)
for db in \
  "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "/Library/Application Support/com.apple.TCC/TCC.db"; do
  echo "=== $db ==="
  sudo sqlite3 "$db" \
    "SELECT service, client, datetime(last_modified,'unixepoch','localtime') as granted_at
     FROM access WHERE auth_value = 2
     ORDER BY last_modified DESC;" 2>/dev/null
done
```

Expected output (abbreviated):
```
=== /Users/you/Library/Application Support/com.apple.TCC/TCC.db ===
kTCCServiceCamera|com.zoom.xos|2025-11-14 09:22:41
kTCCServiceMicrophone|com.zoom.xos|2025-11-14 09:22:41
kTCCServiceScreenCapture|com.obsproject.obs-studio|2025-10-03 14:17:09
...
=== /Library/Application Support/com.apple.TCC/TCC.db ===
kTCCServiceAccessibility|com.keyboardmaestro.KeyboardMaestro-Engine|2025-09-01 08:11:23
kTCCServiceSystemPolicyAllFiles|com.apple.Terminal|2025-08-28 16:04:55
```

### Decoding auth_reason

```bash
# Find all MDM-pushed grants (auth_reason = 6)
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, policy_id
   FROM access WHERE auth_reason = 6;"
```

### Finding Denied Requests (Auth Refusals as Evidence)

```bash
# Denials — apps that asked and were refused
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, datetime(last_modified,'unixepoch','localtime')
   FROM access WHERE auth_value = 0;"
```

A denial entry means the app *attempted* to access the resource and was either refused by the user or blocked by policy. It can be as forensically useful as a grant.

### Inspecting the Screen Capture Approvals Plist

```bash
# Read the Sequoia+ monthly-reconsent approval dates
plutil -p ~/Library/Group\ Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist
```

Output shows bundle IDs mapped to NSDate values (seconds since the Mac epoch, 2001-01-01). Convert:

```bash
# Convert a raw seconds-since-2001 value to human date
python3 -c "import datetime; print(datetime.datetime(2001,1,1) + datetime.timedelta(seconds=YOUR_VALUE))"
```

### Resetting a Permission via GUI

System Settings > Privacy & Security > [Service] — toggle off/on, or click the minus button for per-app removal. This writes to TCC.db via `tccd`; the change is immediate.

### Listing All Installed Configuration Profiles

```bash
# Requires admin password
sudo profiles list

# Verbose with payload content
sudo profiles show -type configuration
```

## 🧪 Labs

### Lab 1 — Full TCC Audit (Non-Destructive)

**Goal:** Dump and understand every TCC grant on your machine.

**Prerequisites:** Terminal must have Full Disk Access.

```bash
# 1. Confirm FDA is in effect
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT count(*) FROM access;" 2>&1
# Should print a number, not "unable to open database file"

# 2. Count grants per service across both DBs
for db in \
  "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "/Library/Application Support/com.apple.TCC/TCC.db"; do
  echo "--- $db ---"
  sudo sqlite3 "$db" \
    "SELECT service, count(*) as n, sum(auth_value=2) as allowed, sum(auth_value=0) as denied
     FROM access GROUP BY service ORDER BY n DESC;" 2>/dev/null
done

# 3. Find all apps with camera OR microphone access
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, datetime(last_modified,'unixepoch','localtime')
   FROM access
   WHERE service IN ('kTCCServiceCamera','kTCCServiceMicrophone')
   ORDER BY service, auth_value DESC;"

# 4. Find anything with Full Disk Access
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value, auth_reason, datetime(last_modified,'unixepoch','localtime')
   FROM access WHERE service = 'kTCCServiceSystemPolicyAllFiles';"

# 5. Examine the schema itself
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db ".schema"
```

Analyze what you find: Are there apps with FDA that shouldn't have it? Any `auth_reason=6` entries on a personal machine? Any entries for apps you don't recognize?

---

### Lab 2 — Reset and Re-Prompt a Camera Permission

> ⚠️ **ADVANCED / DESTRUCTIVE:** This resets a real TCC permission. The targeted app will need to re-request camera access on next use. To limit scope: use `tccutil reset Camera com.apple.FaceTime` (FaceTime will re-prompt on next video call). To roll back: grant access again via System Settings > Privacy & Security > Camera, or simply approve the re-prompt when FaceTime asks.

```bash
# Before: see the current state
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value, datetime(last_modified,'unixepoch','localtime')
   FROM access WHERE service='kTCCServiceCamera';"

# Reset FaceTime's camera permission
tccutil reset Camera com.apple.FaceTime

# After: row is gone (or auth_value = 1 for unknown)
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value FROM access
   WHERE service='kTCCServiceCamera' AND client='com.apple.FaceTime';"

# Trigger re-prompt: open FaceTime and start a video call
# Approve the prompt, then verify the entry is back at auth_value = 2
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value, auth_reason FROM access
   WHERE service='kTCCServiceCamera' AND client='com.apple.FaceTime';"
```

Note `auth_reason = 2` (User Consent) after the re-prompt, and a fresh `last_modified` timestamp.

---

### Lab 3 — Forensic Scenario: Unknown App with Screen Recording Access

**Goal:** Practice the investigative workflow when an unfamiliar `client` appears in TCC.db.

```bash
# 1. List all screen recording grants
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, client_type, auth_value, auth_reason,
          datetime(last_modified,'unixepoch','localtime')
   FROM access WHERE service='kTCCServiceScreenCapture';"

# 2. For each client bundle ID, find the installed app
# Replace com.example.app with a bundle ID from your results
mdfind "kMDItemCFBundleIdentifier == 'com.example.app'"

# 3. Check when the app was installed
mdls -name kMDItemDateAdded "$(mdfind "kMDItemCFBundleIdentifier == 'com.example.app'" | head -1)"

# 4. Verify the code signing identity matches what's in TCC.db
codesign -dv --verbose=4 \
  "$(mdfind "kMDItemCFBundleIdentifier == 'com.example.app'" | head -1)" 2>&1 | \
  grep -E "Authority|TeamIdentifier|Identifier"

# 5. Check the ScreenCaptureApprovals plist for this app
plutil -p ~/Library/Group\ Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist \
  | grep -A2 "com.example.app"
```

Compare `last_modified` in TCC.db against the app's install date from `kMDItemDateAdded`. An app granted screen recording permission *before* it appears to have been installed is a strong indicator of a falsified artifact or a different app sharing the bundle ID.

---

### Lab 4 — Inspect the csreq Blob

**Goal:** Confirm that bundle-ID spoofing is prevented by the code-signing requirement stored in TCC.

```bash
# Extract and decode the csreq for your terminal's FDA entry
CSREQ_HEX=$(sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT hex(csreq) FROM access
   WHERE service='kTCCServiceSystemPolicyAllFiles'
   AND client='$(osascript -e 'id of app "Terminal"')' LIMIT 1;")

echo "Raw hex: $CSREQ_HEX"

# Convert hex to binary and decode with csreq
echo "$CSREQ_HEX" | xxd -r -p > /tmp/tcc_csreq.bin
csreq -r /tmp/tcc_csreq.bin -t
rm /tmp/tcc_csreq.bin
```

You'll see output like:
```
identifier "com.apple.Terminal" and anchor apple
```

This means the grant only applies to a binary with that identifier AND signed by Apple. An impostor `Terminal.app` with a different signing identity would fail this check even with the same bundle ID in the database.

## Pitfalls & Gotchas

**You cannot write to TCC.db even as root (with SIP on).** The file has the `com.apple.rootless.protected` extended attribute. `sudo sqlite3` for *reading* works. For writing, `tccd` must do it via `tccutil` or a GUI interaction. Scripts that try `sqlite3 TCC.db "INSERT …"` will get `SQLITE_READONLY` and silently accomplish nothing.

**Resetting without a bundle ID clears all apps for that service.** `tccutil reset Microphone` wipes every microphone grant. Zoom, Teams, Discord, FaceTime, Logic — all of them re-prompt. Do this in a test environment, not mid-meeting.

**`tccutil reset` only affects the user database for most services.** For Accessibility and FDA (system database entries), you need admin auth and the effects land in `/Library/…/TCC.db`, not the user one. The same `tccutil` command works but affects the appropriate database.

**The Screen Recording service is not MDM-grantable.** Even with a PPPC profile, `kTCCServiceScreenCapture` cannot be pre-approved. This catches enterprise IT off guard when deploying screen-sharing tools. The workaround is the `com.apple.developer.persistent-content-capture` entitlement (Apple-issued, not available to arbitrary third parties).

**Killing `tccd` doesn't grant permissions.** Some historical bypasses worked by killing `tccd` to cause a prompt to auto-approve. Apple has hardened this — `tccd` has a launchd guardian, and clients that try to race the restart get denied, not approved.

**Apple Events entries have two clients.** The `access` table row for `kTCCServiceAppleEvents` has both a `client` (the app sending events) and an `indirect_object_identifier` (the target app receiving them). A forensic query that only looks at `client` misses half the picture — always include the target.

```bash
# Correct Apple Events query
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, indirect_object_identifier, auth_value,
          datetime(last_modified,'unixepoch','localtime')
   FROM access WHERE service='kTCCServiceAppleEvents';"
```

**The expired table is often overlooked.** Entries in the `expired` table represent permissions that were once granted and have since been revoked or replaced. This is forensically valuable — it shows an authorization history that no longer exists in `access`.

```bash
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value, datetime(last_modified,'unixepoch','localtime')
   FROM expired ORDER BY last_modified DESC LIMIT 20;"
```

**Location is split.** `kTCCServiceLocation` in TCC.db shows whether an app *may* use location. The actual authorization (Always/While Using/Never) and the location history live in `locationd`'s state under `/var/db/locationd/` (SIP-protected). TCC is the gate; `locationd` is the keeper of the detail.

**Non-sandboxed apps and FDA.** A non-sandboxed app with FDA can read files that a sandboxed app with per-folder grants cannot. But a non-sandboxed app *without* FDA still needs TCC grants for protected paths — the sandbox exemption is separate from the TCC gate. They're orthogonal: sandbox controls what the process *may* do; TCC controls whether *users have consented* to it.

## Key takeaways

- TCC is enforced by `tccd`, which owns two SIP-protected SQLite databases — one per-user, one system-wide. Neither can be directly edited while SIP is on.
- Every protected-resource access results in a database row with a service name, client bundle ID, authorization status, reason code, code-signing blob, and a Unix timestamp. That timestamp is the authorization trail.
- `auth_reason = 6` means MDM/PPPC granted the permission silently; `auth_reason = 2` means a user clicked Allow. On a personal machine, the former is a red flag.
- Full Disk Access, Accessibility, and Screen Recording are the highest-risk grants; each exposes different attack surfaces (file exfiltration, UI automation/keylogging, and visual surveillance respectively).
- Screen Recording cannot be pre-granted by MDM and requires monthly reconsent in macOS 15+. Approval timestamps live in `ScreenCaptureApprovals.plist`.
- `tccutil reset <service> [bundleid]` is the sanctioned reset path; it calls `tccd`, not the filesystem.
- Forensically: read `access` and `expired` from both databases, correlate `last_modified` against install dates and user activity, and decode `csreq` blobs to verify identity integrity.

## Terms introduced

| Term | Definition |
|---|---|
| TCC | Transparency, Consent & Control — Apple's privacy permission framework |
| `tccd` | The TCC daemon; the sole writer of TCC.db |
| TCC.db | The SQLite database storing all TCC authorization decisions |
| PPPC | Privacy Preference Policy Control — MDM profile payload to pre-configure TCC |
| FDA | Full Disk Access — the `kTCCServiceSystemPolicyAllFiles` TCC grant |
| `auth_value` | The authorization state (denied/unknown/allowed/limited) in the TCC access table |
| `auth_reason` | How the authorization was established (user consent, MDM, system policy, etc.) |
| `csreq` | Code-Signing Requirement blob — prevents bundle-ID spoofing in TCC grants |
| responsible process | The process `tccd` attributes a TCC request to (the signed parent in the process tree) |
| `kTCCServiceScreenCapture` | The TCC service for screen recording; cannot be MDM-grantable |
| `kTCCServiceListenEvent` | Input monitoring — keyboard/mouse listener permission |
| `tccutil` | CLI tool for resetting TCC permissions via `tccd` |
| `ScreenCaptureApprovals.plist` | Plist tracking monthly screen-recording reconsent timestamps (macOS 15+) |
| `expired` table | TCC.db table holding historical grants that were subsequently revoked |

## Further reading

- Apple Platform Security Guide (developer.apple.com) — "App access to protected resources" chapter
- `man tccutil` — authoritative flags and service names
- Howard Oakley (Eclectic Light Company) — extensive TCC internals articles, particularly on Sequoia permission changes
- [Rainforest QA: macOS TCC.db Deep Dive](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive) — schema reference with column semantics
- [Michael Tsai: Sequoia Screen Recording Prompts and the Persistent Content Capture Entitlement](https://mjtsai.com/blog/2024/08/08/sequoia-screen-recording-prompts-and-the-persistent-content-capture-entitlement/) — the reconsent mechanism and developer impact
- [HackTricks: macOS TCC](https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-tcc/) — bypass techniques and privilege escalation angles (red-team perspective)
- `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db ".schema"` — read the live schema; it evolves with each macOS release
- [[01-boot-process]] — SIP enforcement starts at boot; understanding the sealed SSV explains why TCC.db is tamper-resistant
