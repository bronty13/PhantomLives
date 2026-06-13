---
title: The Shortcuts App & `shortcuts` CLI
part: P06 Automation
est_time: 50 min read + 45 min labs
prerequisites: [p05-scripting/01-shell-fundamentals, p05-scripting/02-applescript-deep-dive]
tags: [macos, shortcuts, automation, cli, launchd, workflow, cross-platform]
---

# The Shortcuts App & `shortcuts` CLI

> **In one sentence:** Shortcuts is Apple's cross-device visual automation framework — an action pipeline interpreter backed by a CoreServices daemon, bridgeable to shell, AppleScript, and JavaScript, now with native time-based triggers on macOS Tahoe 26.

---

## Why this matters

AppleScript is still the right tool for deep GUI scripting of scriptable apps. Automator still exists (barely). But for anything that needs to run on Mac *and* iPhone *and* iPad, that publishes a share-sheet extension, that lives inside the system notification pipeline, or that a non-coder on your team needs to audit — Shortcuts is the modern choice.

macOS Tahoe 26 closed the most embarrassing gap in the Mac Shortcuts story: **native time-based automation triggers**. Combined with the `shortcuts` CLI that shipped in macOS 12, you now have a framework that can be driven from cron-style launchd jobs, CI pipelines, and Spotlight — while still showing up in the share sheet on someone's iPhone.

> 🪟 **Windows contrast:** Power Automate Desktop is the rough equivalent — a visual flow builder that can run attended or unattended. The key difference is scope: Power Automate requires a cloud backend for most triggers, executes in a sandboxed COM bridge for desktop actions, and licences per-user per-month for advanced connectors. Shortcuts is 100% local-first, ships free with the OS, and uses a Unix daemon for execution. The tradeoff: Shortcuts' GUI automation of arbitrary apps is shallow compared to PAD's recorder + UIAutomation bridge.

> 🔬 **Forensics note:** Every shortcut the user runs is a `.shortcut` bundle (a property-list binary) stored in `~/Library/Shortcuts/`. The `ShortcutsEvents` database at `~/Library/Application Support/com.apple.shortcuts/` is an SQLite file that records run history including timestamps, shortcut UUIDs, and exit status — a useful artifact when reconstructing timeline activity.

---

## Concepts

### 1. The action model

A Shortcut is a **named, ordered list of actions**. Think of it as a typed Unix pipeline where every step receives input, does something, and emits output downstream. The runtime is `ShortcutsEvents.app` (`/System/Applications/Shortcuts.app` + its helper `ShortcutsEvents.app` inside its bundle), an XPC service that hosts actions contributed both by Apple frameworks and by third-party apps via `NSExtension` / `App Intents`.

```
Input (Share Sheet / CLI / Automation trigger)
  │
  ▼
Action 1 ── emits typed value ──▶ Action 2 ── emits ──▶ Action N
                                                             │
                                                             ▼
                                                    Output (clipboard / file / return value)
```

Every action carries a **type signature**: Text, File, Image, URL, Contact, etc. When types mismatch between steps, Shortcuts silently coerces (a URL becomes Text; a File becomes its path string). Understanding coercion saves debugging time.

### 2. Variables and Magic Variables

Two variable flavors exist:

- **Named variables** (`Set Variable` / `Get Variable` actions): explicit storage slots you name and retrieve by name. Useful when you need a value across many non-sequential steps.
- **Magic Variables**: every action's most recent output is automatically available as a context-clickable token *inline* in any downstream action's field. Click the variable-input field in any action, tap the magic wand icon, and you see the full upstream output chain. This is Shortcuts' answer to shell variable capture — no name required, just point at the prior step.

Magic Variables carry full type metadata, so downstream actions show only type-appropriate suggestions.

### 3. Control flow

| Construct | Action name | Notes |
|---|---|---|
| Conditional | **If** / Otherwise / End If | Condition tests: is/is not/contains/begins with, numeric comparisons, file exists, etc. |
| For-each loop | **Repeat with Each Item in [list]** | Loop variable exposed as Magic Variable `Repeat Item`; index via `Repeat Index` |
| Fixed count loop | **Repeat** | Simple N-times counter |
| User prompt | **Choose from Menu** | Presents a button sheet; branches on selection — the interactive `select` statement |
| Break | **Exit Shortcut** | Early return, optionally with output |
| Output | **Stop and Output** | Terminates and returns a value to the caller (CLI, share sheet, or Automation) |

### 4. The power-bridge actions

These three actions are where Shortcuts transcends its "beginner" reputation:

#### `Run Shell Script`

```
Shell: /bin/zsh          ← or /bin/bash, /usr/bin/python3, etc.
Input: Shortcut Input    ← the typed pipeline value, delivered via…
  Pass input as: stdin   ← or "as arguments"
Output: Text / JSON      ← stdout captured, becomes next action's input
```

The shell script runs under your user account in a sandboxed helper — full access to your files, your `$PATH` (inherited from the login environment), and your Keychain. `stderr` is swallowed unless you redirect it. Exit code non-zero surfaces as a Shortcuts error.

> 🔬 **Forensics note:** Shell scripts in Shortcuts run as child processes of `ShortcutsEvents`. You can see them in `ps aux | grep ShortcutsEvents` or `Activity Monitor → All Processes`. The script text itself is embedded in the `.shortcut` plist — it is plaintext-recoverable from the artifact.

#### `Run AppleScript`

Executes a literal AppleScript block inside an `osascript` interpreter child. The Shortcut's input is accessible as `input` (coerced to the nearest AppleScript type). Returns the `result` value. Combine when you need UI-scripting depth (clicking specific menu items, reading window positions) that Shortcuts' own actions can't reach.

#### `Run JavaScript on Webpage` (Safari-only)

Runs a JS snippet inside an active Safari tab via the Safari Web Extension mechanism. Receives and returns values. Useful for page scraping and form manipulation. Not available in other browsers.

### 5. Input and output surface area

Shortcuts exposes itself to the rest of the system at five integration points:

| Surface | How it's activated | Mechanism |
|---|---|---|
| **Share Sheet** | "Share" button in any app | `NSExtensionRequestHandling` / App Intents |
| **Quick Actions (Finder)** | Right-click file/folder in Finder → Quick Actions | Services menu + `NSSharingService` |
| **Services menu** | App menu → Services | `NSServices` plist registration |
| **Menu bar / Dock** | Shortcuts settings: "Pin in menu bar" or "Add to Dock" | `LSUIElement` helper app |
| **Spotlight** | Search shortcut name, then run | New in macOS Tahoe 26; accepts selected-text as input |
| **CLI** | `shortcuts run "Name"` | `ShortcutsEvents` XPC |
| **Automation** | Event trigger fires | `ShortcutsEvents` daemon |
| **URL scheme** | `shortcuts://run-shortcut?name=...` | Handled by `Shortcuts.app` |

**Share Sheet input** is the most powerful: a shortcut that accepts share-sheet input receives the typed object (file, URL, text, image) directly, runs to completion, and returns output back to the originating app.

To make a shortcut appear in Finder's Quick Actions panel:
1. Open the shortcut in the editor.
2. Shortcut Settings (top right) → **Use as Quick Action** → check **Finder**.
3. In Finder → Settings → Extensions → Finder Extensions, verify it is enabled.

### 6. Automation triggers (macOS Tahoe 26)

macOS Tahoe 26 finally ships **personal automations** on the Mac, parity with iOS 13+ behavior. The Automation section lives in the Shortcuts sidebar.

Available trigger categories on Mac as of macOS 26:

| Category | Triggers |
|---|---|
| **Time & Schedule** | Time of Day (specific time / sunrise / sunset; daily/weekly/monthly), Alarm (fired/snoozed/stopped) |
| **App lifecycle** | App Opened, App Closed |
| **Connectivity** | Wi-Fi (connected/disconnected), Bluetooth device, External Drive (mount/eject), Display (connected/disconnected) |
| **Device state** | Battery Level (above/below %), Charger (connected/disconnected — MacBook only), Focus mode (on/off), Stage Manager (on/off) |
| **Content** | Files added to Folder, Email received (from/containing), Message received |

Each automation has a **run mode**: immediately (background, no prompt) or "Run After Confirmation" (delivers a notification; user taps Run to proceed — safer for destructive actions).

> ⚠️ **Note:** The workaround that was needed before Tahoe 26 — a launchd calendar job calling `shortcuts run "Name"` — is still the right approach when you need sub-minute scheduling, server-side headless execution, or CI/CD integration. Native automations require the GUI session. See the lab section.

### 7. iCloud sync

Shortcuts sync via iCloud (CloudKit, not iCloud Drive files). The sync unit is the individual shortcut, keyed by UUID. Deletion on one device propagates within seconds if both are online. **The `.shortcut` export format** (`File → Export`) is a portable binary plist you can check into git, send to colleagues, or import on any Apple device — it includes the full action graph, icon, color, and metadata.

Import by double-clicking a `.shortcut` file or via the `shortcuts` CLI `sign` subcommand (for enterprise distribution).

### 8. Permissions model

A shortcut requesting sensitive resources triggers a TCC prompt the first time it runs — same framework as native apps. Common permission gates:

- Contacts, Calendar, Reminders, Photos → standard TCC
- Files in `~/Documents`, `~/Desktop`, `~/Downloads` → user-selected via `NSOpenPanel` on first access (not a blanket grant)
- Network requests (`Get Contents of URL`) → no TCC, but outbound firewall rules apply
- Running shell scripts → no special permission beyond the shortcut's own sandbox
- Controlling apps via AppleScript → App-level Automation permission under Privacy & Security → Automation

Shortcuts run from the CLI inherit TCC grants already stored for `ShortcutsEvents.app`.

### 9. When Shortcuts beats AppleScript — and when it doesn't

| Task | Use Shortcuts | Use AppleScript |
|---|---|---|
| Process a file and return it to the share sheet | ✅ Native share-sheet integration | ❌ No share-sheet mechanism |
| Run across iPhone + iPad + Mac with same code | ✅ Cross-device sync | ❌ Mac-only |
| Script a legacy scriptable app (InDesign, BBEdit, Finder AppleScript dictionary) | ❌ Limited action surface | ✅ Full dictionary access |
| GUI click-automation of arbitrary apps | ❌ Not possible | ✅ `System Events` UI scripting |
| Heavy text/data processing (regexes, parsing) | ⚠️ Possible via Run Shell Script | ⚠️ Possible but verbose |
| Trigger from a calendar job / CI | ✅ via `shortcuts` CLI | ✅ via `osascript` CLI |
| Cross-device focus / stage manager integration | ✅ Automation triggers | ❌ |
| Readable by a non-coder | ✅ Visual editor | ❌ English-like but still code |

---

## Hands-on (CLI & GUI)

### The `shortcuts` command

```zsh
# List all shortcuts (name, UUID, type)
shortcuts list

# Run by name (blocking; exits 0 on success, 1 on error)
shortcuts run "My Shortcut"

# Run with a file as input
shortcuts run "Compress Images" --input-path ~/Desktop/photo.png

# Run with multiple files (space-delimited or glob)
shortcuts run "Compress Images" \
  --input-path ~/Desktop/a.png ~/Desktop/b.png

# Capture output to a file
shortcuts run "Extract Text from PDF" \
  --input-path ~/Downloads/report.pdf \
  --output-path ~/Desktop/extracted.txt

# Force output to a specific UTI (e.g., plain text)
shortcuts run "Process Data" \
  --output-path ~/Desktop/result.txt \
  --output-type public.plain-text

# Open a shortcut in the editor without running it
shortcuts view "My Shortcut"

# Pipe text via stdin (treated as a file path in --input-path mode;
# for true text piping, use a temp file or the Run Shell Script action bridge)
echo "Hello world" > /tmp/input.txt
shortcuts run "Summarize Text" --input-path /tmp/input.txt
```

> ⚠️ **Pipe limitation:** `shortcuts run` does not read from Unix stdin directly. The CLI's `--input-path` flag expects a filesystem path; piped stdin is treated as a literal path string, not file content. The clean workaround: write to a temp file, pass that path, then delete it. Alternatively, build the shortcut so its first action is `Run Shell Script` reading `/dev/stdin`, and call it from a shell script wrapper.

```zsh
# Practical stdin bridge pattern
process_with_shortcut() {
  local tmpfile
  tmpfile=$(mktemp /tmp/sc_input_XXXXXX)
  cat > "$tmpfile"          # drain stdin into temp file
  shortcuts run "My Shortcut" --input-path "$tmpfile"
  local rc=$?
  rm -f "$tmpfile"
  return $rc
}
# Usage:
cat ~/some_data.json | process_with_shortcut
```

### Exploring the on-disk format

```zsh
# List your shortcuts directory
ls ~/Library/Shortcuts/

# A .shortcut is a binary plist — decode it
plutil -convert xml1 ~/Library/Shortcuts/MyShortcut.shortcut -o -

# Or use Python for programmatic inspection
python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    data = plistlib.load(f)
# Top-level keys: WFWorkflowActions, WFWorkflowName, WFWorkflowIcon, etc.
print(list(data.keys()))
" ~/Library/Shortcuts/MyShortcut.shortcut
```

> 🔬 **Forensics note:** The plist's `WFWorkflowActions` array is the full action graph in execution order. Each action dict has a `WFWorkflowActionIdentifier` (reverse-DNS action ID) and `WFWorkflowActionParameters`. `Run Shell Script` actions store the literal script text in `WFShellScriptActionScript`. This is a high-value artifact — scripts that exfiltrate data, encode payloads, or call out to remote hosts are recoverable verbatim even if the user deleted the shortcut from the GUI (iCloud sync graveyard in `~/Library/Application Support/com.apple.shortcuts/`).

### Shortcut run history (SQLite)

```zsh
# Run history database (copy first — live DB may be locked)
cp ~/Library/Application\ Support/com.apple.shortcuts/ShortcutsDatabaseSQL.db /tmp/sc.db
sqlite3 /tmp/sc.db ".tables"
# Typical tables: ZSHORTCUT, ZSHORTCUTRUNHISTORY, ZSHORTCUTCATEGORY

sqlite3 /tmp/sc.db \
  "SELECT ZNAME, datetime(ZSTARTDATE + 978307200, 'unixepoch', 'localtime') as ran_at, ZRESULT
   FROM ZSHORTCUTRUNHISTORY
   JOIN ZSHORTCUT ON ZSHORTCUTRUNHISTORY.ZSHORTCUT = ZSHORTCUT.Z_PK
   ORDER BY ZSTARTDATE DESC LIMIT 20;"
```

(Core Data timestamps use the Mac absolute reference date: seconds since 2001-01-01. Add `978307200` to convert to Unix epoch.)

---

## Labs

### Lab 1: Build a share-sheet shortcut that processes text

**Goal:** Create a shortcut that accepts text from the share sheet, counts words, and copies the count to the clipboard.

1. Open **Shortcuts.app → New Shortcut**.
2. In Shortcut Settings (top-right ⓘ), set **Receives** = Text, enable **Use as Quick Action → Services Menu**.
3. Add action: **Count** → **Count** (from the utility actions; or use `Run Shell Script`):

   ```
   Action: Run Shell Script
   Shell: /bin/zsh
   Pass Input as: stdin
   Script:
     wc -w | tr -d ' '
   ```

4. Add action: **Copy to Clipboard**.
5. Add action: **Show Notification** → "Word count: [Magic Variable: Shell Script Result]".
6. Name it "Word Count".
7. Test: select text in Safari, Share → Word Count.

**Verify from CLI:**

```zsh
echo "The quick brown fox jumps over the lazy dog" \
  > /tmp/wc_test.txt
shortcuts run "Word Count" --input-path /tmp/wc_test.txt
# clipboard should now contain "9"
pbpaste
```

---

### Lab 2: Run a shortcut from a launchd calendar job

**Goal:** Run "Word Count" (or any shortcut) on a schedule without Tahoe 26's native triggers (useful for headless/server scenarios, sub-minute intervals, or pre-Tahoe compatibility).

> ⚠️ **Prerequisites:** The shortcut must not require a GUI interaction (no `Choose from Menu`, no `Show Notification` that blocks). Test it headless first with `shortcuts run`.

**Step 1 — Write the wrapper script:**

```zsh
cat > ~/Library/Scripts/run_daily_shortcut.sh << 'EOF'
#!/bin/zsh
# Ensure GUI session environment for ShortcutsEvents
export HOME=/Users/YOUR_USERNAME
export USER=YOUR_USERNAME
export LOGNAME=YOUR_USERNAME

# Log output
LOGFILE="$HOME/Library/Logs/shortcuts_daily.log"
echo "=== $(date) ===" >> "$LOGFILE"
/usr/bin/shortcuts run "Daily Summary" >> "$LOGFILE" 2>&1
echo "Exit: $?" >> "$LOGFILE"
EOF
chmod +x ~/Library/Scripts/run_daily_shortcut.sh
```

Replace `YOUR_USERNAME` with your actual username (`whoami`).

**Step 2 — Write the launchd plist:**

```zsh
cat > ~/Library/LaunchAgents/com.me.shortcuts.daily.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.me.shortcuts.daily</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>/Users/YOUR_USERNAME/Library/Scripts/run_daily_shortcut.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>8</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>/Users/YOUR_USERNAME/Library/Logs/shortcuts_launchd.out</string>
  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USERNAME/Library/Logs/shortcuts_launchd.err</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
EOF
```

**Step 3 — Load and verify:**

```zsh
launchctl load ~/Library/LaunchAgents/com.me.shortcuts.daily.plist

# Verify it is loaded
launchctl list | grep com.me.shortcuts.daily
# Output: <PID or ->    <last exit code>    com.me.shortcuts.daily

# Fire it immediately to test (don't wait for 8 AM)
launchctl kickstart -k gui/$(id -u)/com.me.shortcuts.daily

# Watch the log
tail -f ~/Library/Logs/shortcuts_daily.log
```

> ⚠️ **Rollback:** `launchctl unload ~/Library/LaunchAgents/com.me.shortcuts.daily.plist && rm ~/Library/LaunchAgents/com.me.shortcuts.daily.plist`

> 🔬 **Forensics note:** The `launchctl list` output PID column will be `-` when the job is not running; the exit code column shows the last run's exit status. `launchd` records are auditable via `log show --predicate 'subsystem == "com.apple.launchd"' --last 1h`.

---

### Lab 3: Native macOS Tahoe 26 time-based automation

> **Requires macOS 26 Tahoe.** Skip this lab on Sequoia — use Lab 2 instead.

1. Open **Shortcuts → Automation** (sidebar) → **+**.
2. Select trigger: **Time of Day** → set 07:30 AM, repeat **Daily**, weekdays only (uncheck Sat/Sun using the day selectors).
3. Add shortcut to run: search for and select your existing shortcut, or add actions inline.
4. Set run mode: **Run Immediately** (no confirmation) or **Run After Confirmation** for a notification-gated run.
5. Click Done.

**Verify it's registered:**

```zsh
# Automations are stored alongside shortcuts — list all
shortcuts list
# Automation-backed shortcuts show a clock icon in the GUI
# On-disk they appear in ~/Library/Shortcuts/ as normal .shortcut files
# with WFWorkflowAutomationSchedule metadata in the plist
```

**Force-fire to test without waiting:**

```zsh
shortcuts run "Your Automation Shortcut Name"
```

---

### Lab 4: Combining Shortcuts with Focus modes and Stage Manager

Shortcuts can both **read** and **set** Focus modes and Stage Manager state via native actions:

- `Set Focus` action: Enable/disable Do Not Disturb, Work, Personal, etc.
- `Get Current Focus` → returns active focus name (use in an If branch)
- `Set Multitasking Mode` (macOS 26 new action): enable/disable Stage Manager, Mission Control, etc.

**Example shortcut — "Deep Work Mode":**

```
1. Set Focus: Work Focus → On
2. Set Multitasking Mode: Stage Manager → On
3. Open App: your focus music app
4. Run Shell Script: /usr/bin/osascript -e 'tell application "Slack" to quit'
5. Show Notification: "Deep work mode active."
```

Wire this to an Automation trigger: **Wi-Fi Connected → YourOfficeNetwork** → Run Immediately.

---

## Pitfalls & gotchas

**1. `ShortcutsEvents` is a GUI-session process.**
Running `shortcuts run` from a non-GUI SSH session (e.g., a pure launchd `Daemon` in `/Library/LaunchDaemons/`) will silently fail or hang. Use `LaunchAgents` (per-user, GUI session) as shown in Lab 2. Confirm with `launchctl list` in a logged-in Terminal — not over SSH when the GUI is not running.

**2. Path resolution in `Run Shell Script` uses the shortcut's login PATH, not your `.zshrc` one.**
Homebrew binaries at `/opt/homebrew/bin` are not on the default PATH available to shortcut shell scripts. Hardcode full paths (`/opt/homebrew/bin/ffmpeg`) or add `export PATH="/opt/homebrew/bin:$PATH"` at the top of your shell script action.

**3. Variables don't span across shortcut calls.**
Calling a sub-shortcut with `Run Shortcut` passes only the single typed input/output; named variables from the parent do not bleed into child shortcuts. Pass structured data (JSON text) if you need to communicate a record.

**4. iCloud sync can cause version conflicts.**
If you edit the same shortcut on two devices offline, iCloud picks one winner — no merge. The loser's edits disappear silently. For anything non-trivial, export to `.shortcut` and commit to git before major edits.

**5. The `shortcuts run` CLI is blocking by default.**
Long-running shortcuts will block the calling process. Wrap in `timeout 120 shortcuts run "..."` or background it with `&` if appropriate.

**6. Automation triggers on Mac require the user to be logged in.**
A macOS 26 time-based automation will not fire if the display is locked *and* there is no active GUI session. For headless reliability, use the launchd approach (Lab 2) — launchd fires regardless of login state (LaunchAgents fire on login; use `SessionCreate` for SSH-less scenarios; see [[p06-automation/03-launchd-deep-dive]]).

**7. TCC prompts block headless runs.**
If a shortcut has never been granted permission for Contacts, Photos, etc. in a GUI context, a headless `shortcuts run` will hang waiting for the TCC prompt that can never appear. Pre-authorize by running the shortcut manually in the GUI first.

**8. Magic Variables break silently when you reorder actions.**
A Magic Variable pointing to "Action 3's output" re-binds by reference, not by position — but if you *delete* the source action, the Magic Variable becomes an empty placeholder with no warning at edit time. Always test after structural edits.

---

## Key takeaways

- Shortcuts is a **typed pipeline interpreter** backed by the `ShortcutsEvents` XPC daemon; every shortcut is a binary plist in `~/Library/Shortcuts/`.
- **Magic Variables** capture any action's output inline; named variables store reusable values explicitly.
- The `Run Shell Script`, `Run AppleScript`, and `Run JavaScript on Webpage` actions are the escape hatches to full system power.
- **macOS Tahoe 26** finally ships native personal automation triggers on Mac (time-based, app lifecycle, device connectivity, folder changes) — previously iOS/iPadOS-only.
- The **`shortcuts` CLI** (`list`, `run`, `view`, `sign`) enables scripting shortcuts from launchd, CI, or shell pipelines; use `--input-path` for file input and `--output-path` to capture results.
- For headless/scheduled execution, prefer **launchd `StartCalendarInterval`** LaunchAgents over native automations — they fire without a GUI session.
- Shortcuts beats AppleScript at **cross-device portability, share-sheet integration, and modern app/system triggers**; AppleScript wins for **deep GUI scripting of scriptable apps**.
- The SQLite run history and plist action graphs are **rich forensic artifacts** — shortcut UUIDs, run timestamps, and embedded shell scripts are recoverable from the local database even after GUI deletion.

---

## Terms introduced

| Term | Meaning |
|---|---|
| **Magic Variable** | Auto-generated variable referencing the most recent output of any upstream action |
| **Quick Action** | A shortcut exposed in Finder's right-click menu or the Services menu |
| **`ShortcutsEvents`** | The XPC helper process that actually executes shortcut action graphs |
| **`.shortcut` bundle** | Portable binary plist export format for a single shortcut |
| **WFWorkflowActionIdentifier** | Reverse-DNS string identifying each action type in the plist schema |
| **App Intents** | Swift framework third-party apps implement to donate actions to Shortcuts |
| **Automation** | Shortcuts with an event trigger rather than manual invocation |
| **`StartCalendarInterval`** | launchd plist key for cron-style calendar scheduling |
| **UTI (Uniform Type Identifier)** | Apple's type system for data (e.g., `public.plain-text`, `public.jpeg`) used in `--output-type` |

---

## Further reading

- **Apple Shortcuts User Guide for Mac** — `support.apple.com/guide/shortcuts-mac` — canonical action reference
- **What's new in Shortcuts (macOS 26)** — `support.apple.com/en-us/125148` — Tahoe trigger and action additions
- **App Intents framework docs** — `developer.apple.com/documentation/appintents` — how apps donate Shortcuts actions
- **Howard Oakley, Eclectic Light Company** — "Shortcuts: under the hood" series — best third-party deep-dive on the plist format and XPC architecture
- **launchd.plist(5)** man page — `man launchd.plist` — authoritative reference for `StartCalendarInterval` and all scheduling keys
- **`shortcuts` man page** — `man shortcuts` — flag reference for the CLI (installed with macOS 12+)

---

*Related lessons: [[p05-scripting/02-applescript-deep-dive]] · [[p06-automation/02-automator-legacy]] · [[p06-automation/03-launchd-deep-dive]] · [[p06-automation/04-focus-modes-and-scripting]]*
