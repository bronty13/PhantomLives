---
title: "Scripting: bash, AppleScript, JXA, Shortcuts CLI"
part: P03 CLI
est_time: 60 min read + 45 min labs
prerequisites: [00-terminal-and-shells, 01-zsh-deep-dive, 02-shell-fundamentals]
tags: [macos, scripting, bash, zsh, applescript, jxa, shortcuts, automation, apple-events]
---

# Scripting: bash, AppleScript, JXA, Shortcuts CLI

> **In one sentence:** macOS exposes four complementary scripting surfaces — shell scripts, AppleScript, JavaScript for Automation, and the Shortcuts CLI — and the real power comes from knowing which to reach for and how to wire them together.

## Why this matters

Every macOS power user eventually hits the wall where pointing and clicking stops scaling. The difference between a top-1% operator and everyone else is that they automate at the right layer: shell for file and process work, AppleScript or JXA when they need to drive an application's own internal object model, and Shortcuts when they want a reusable action that integrates with the OS and can be triggered from anywhere — keyboard, menu bar, Siri, or back from the shell.

For forensic work, these surfaces matter in two directions: as investigative levers (automating log collection, driving Script Editor to query running apps, exfiltrating app data via Apple Events) and as artifacts (osascript activity in Unified Log, `~/Library/Application Scripts/`, `.scpt` caches, Shortcuts bundles in `~/Library/Shortcuts/`).

> 🪟 **Windows contrast:** The Windows analog is a three-layer stack: batch (`.bat`) for legacy one-liners, PowerShell for serious scripting (rich objects, .NET access, remoting), and COM/OLE automation for driving GUI apps like Word or Excel programmatically. The macOS layers map loosely: shell → PowerShell, AppleScript/JXA → COM automation, Shortcuts → Power Automate Desktop. The critical difference is that Apple Events are a network-transparent IPC mechanism baked into the OS, whereas COM is a local in-process/out-of-process model. Apple Events can (in theory) cross the network; COM mostly doesn't.

---

## Concepts

### Layer 1 — Shell Scripts (sh / bash / zsh)

#### The bash 3.2 situation

macOS ships `/bin/bash` at version **3.2.57** (GPL v2; Apple cannot ship GPL v3 without license implications). This is the version from 2007. It lacks associative arrays, improved `[[ ]]` behavior, `mapfile`/`readarray`, and many pattern features that bash 4+ or 5+ users take for granted.

```
$ /bin/bash --version
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin24)
```

Meanwhile, `/bin/zsh` (the default interactive shell since Catalina) is version 5.9+, and Homebrew can give you `/opt/homebrew/bin/bash` at 5.x if you need modern bash.

**Shebang decision tree:**

```
Need to run on a vanilla Mac with no Homebrew?  →  #!/bin/sh  (POSIX only)
Broad macOS compatibility, mild features?       →  #!/bin/bash  (3.2 subset)
Modern bash features (assoc arrays, etc.)?      →  #!/usr/bin/env bash  (picks Homebrew bash first)
zsh-native features (zmv, zparseopts, etc.)?   →  #!/bin/zsh
```

Use `/usr/bin/env <shell>` when portability across machines with different install paths matters. Use an absolute path (`#!/opt/homebrew/bin/bash`) only when you control the machine and need to guarantee a specific version.

#### set -euo pipefail — the safety header

Every non-trivial shell script should open with:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

- `set -e` — exit immediately on any non-zero exit status (with caveats: doesn't trigger inside `if` conditions or `||`/`&&` chains).
- `set -u` — treat unset variables as errors. Catches `rm -rf $TMPDIR/` where `$TMPDIR` was never set.
- `set -o pipefail` — a pipeline fails if *any* component fails, not just the last one. Without this, `broken_command | tee log.txt` exits 0.
- `IFS=$'\n\t'` — strips the space from the Internal Field Separator, preventing word-splitting bugs on filenames with spaces.

> 🔬 **Forensics note:** Post-incident, grep `/private/var/log/` or Unified Log for `bash` invocations. When `set -e` is absent, a script that partially executes (deleting files, writing configs) before hitting an error leaves a partially-mutated system. Always check whether the attacker's scripts had error guards.

#### The bash 3.2 trap

Features you **cannot** use in `/bin/bash` on a stock Mac (3.2 limitation):

```bash
# BROKEN on /bin/bash (macOS stock):
declare -A mymap        # associative arrays — bash 4+
mapfile -t lines < file # read array from file — bash 4+
${var^^}                # uppercase expansion — bash 4+
printf '%q'             # safe quoting — actually works in 3.2 ✓ (exception)
```

When you need associative arrays on stock macOS: use `zsh` or Python (one-liner via `python3 -c`), or restructure to parallel indexed arrays.

#### When to write zsh instead

Reach for `#!/bin/zsh` when:
- You need `zmv` (mass-rename with patterns), `zargs`, or `zparseopts`.
- The script is for personal use on your own Mac and you don't care about portability.
- You're manipulating arrays heavily — zsh arrays are 1-indexed, have cleaner syntax, and support associative arrays natively.
- You want glob qualifiers (`**/*.log(m-7)` — files modified in the last 7 days) without `find`.

Avoid zsh scripts that you plan to distribute — not everyone has zsh on PATH on Linux CI runners, and `/bin/zsh` behavior differs subtly from Homebrew zsh.

---

### Layer 2 — AppleScript

#### What it actually is

AppleScript is a high-level scripting language that communicates with applications via **Apple Events** — a structured IPC mechanism in the macOS kernel (descended from the Macintosh Toolbox, formalized under System 7). When you `tell application "Safari"` to do something, Script Editor compiles your English-like source into Apple Event descriptor records and dispatches them via Mach messaging to the Safari process.

This means AppleScript can control *only* apps that:
1. Declare a scripting dictionary (a `.sdef` file describing their scriptable objects and commands), and
2. Respond to Apple Events.

Apps without a dictionary are opaque to AppleScript's object model — but System Events can still drive them via UI scripting (see below).

#### Anatomy of an AppleScript

```applescript
-- tell block: target the application
tell application "Finder"
    -- access properties of the frontmost window
    set win to front window
    set fp to POSIX path of (target of win as alias)
    return fp
end tell
```

Key constructs:
- `tell application "Name"` — opens an Apple Event session to that app.
- `set x to ...` — assignment. No `$`, no `=`.
- `POSIX path of` — coerce an HFS `alias` to a Unix path string.
- `return` — returns a value (to Script Editor's result pane, or to the caller when run via `osascript`).

#### Reading the dictionary

In **Script Editor** (`/Applications/Utilities/Script Editor.app`): File → Open Dictionary (⇧⌘O), then pick any running or installed app. The dictionary browser shows every scriptable class (like `document`, `window`, `track`) and every command (`make`, `delete`, `duplicate`). This is your API reference.

```
Dictionary hierarchy for Finder:
  Finder Basics Suite
    └── Finder item (abstract parent)
          ├── file
          ├── folder
          └── disk
  Standard Suite (inherited by all apps)
    └── open, close, save, quit, ...
```

You can also dump a dictionary to XML from the command line:
```bash
sdef /Applications/Safari.app | less
```

#### System Events and UI scripting

When an app has no dictionary, `System Events` provides a UI-scripting backdoor via the Accessibility API: it can read and click arbitrary UI elements by their AXRole/AXDescription attributes.

```applescript
tell application "System Events"
    tell process "SomeApp"
        set allWindows to every window
        click button "OK" of front window
        keystroke "v" using {command down}   -- paste
    end tell
end tell
```

**Accessibility permission:** The app running the script (Terminal, Script Editor, your `.app`, or `osascript`) must be granted Accessibility access in:
`System Settings → Privacy & Security → Accessibility`

If the permission is absent, System Events silently fails or throws "not authorized." Programmatically, apps check `AXIsProcessTrusted()` from the `ApplicationServices` framework. On macOS Tahoe this TCC domain is `kTCCServiceAccessibility`.

> 🔬 **Forensics note:** Malware that uses `osascript` for UI scripting leaves artifacts in the Unified Log under the `com.apple.accessibility.AX` subsystem. Also check `~/Library/Application Scripts/<bundle-id>/` — the sandbox-friendly drop location for scripts that sandboxed apps are allowed to execute. CVE-2025-31250 demonstrated a TCC bypass where a malformed permission dialog could trick users into granting Accessibility without realizing it.

#### .scpt vs .applescript

| Format | Extension | Binary? | Use case |
|---|---|---|---|
| Compiled script | `.scpt` | Yes (OSA bytecode) | Fast loading, slightly obfuscated |
| Script bundle | `.scptd` | Directory | Can embed resources |
| Text source | `.applescript` | No (plain UTF-8) | Version control, readable |
| Application | `.app` (stay-open) | Bundle | Standalone automations, droplets |

Store automation scripts in `.applescript` (text) in version control. `.scpt` in `~/Library/Scripts/` is what the Script Menu picks up.

#### Running AppleScript from the shell

```bash
# Inline, single expression:
osascript -e 'tell application "Finder" to get name of front window'

# Multi-line heredoc:
osascript <<'APPLE'
tell application "System Events"
    display notification "Build done" with title "CI" subtitle "Tests passed"
end tell
APPLE

# Run a saved .scpt or .applescript file:
osascript ~/Scripts/my_automation.applescript

# Capture return value in bash:
result=$(osascript -e 'tell application "Finder" to return POSIX path of (target of front window as alias)')
echo "Finder is at: $result"
```

The exit code is `0` on success, non-zero on error. Errors print to stderr.

---

### Layer 3 — JavaScript for Automation (JXA)

#### The same Apple Event bridge in JavaScript

JXA, introduced in OS X Yosemite (2014), exposes the exact same Apple Event object model as AppleScript but through a V8-based JavaScript runtime embedded in the OSA (Open Scripting Architecture) pipeline. Same IPC, different syntax.

```javascript
// JXA equivalent of the Finder example above
const finder = Application('Finder');
const win = finder.finderWindows[0];
win.target().posixPath();
```

#### Running JXA

```bash
# Inline:
osascript -l JavaScript -e 'Application("Finder").finderWindows[0].target().posixPath()'

# From a file (.js extension works, or any extension):
osascript -l JavaScript ~/Scripts/my_jxa.js

# Shebang in the file itself:
#!/usr/bin/env osascript -l JavaScript
```

JXA files conventionally use `.jxa` or `.js` — the OSA layer doesn't care about extension, only the `-l JavaScript` flag.

#### Key JXA idioms

```javascript
// Activate an app (bring to front):
const safari = Application('Safari');
safari.activate();

// Work with the Standard Additions (dialogs, clipboard, notifications):
const app = Application.currentApplication();
app.includeStandardAdditions = true;
app.displayNotification('Hello from JXA', {
    withTitle: 'My Script',
    subtitle: 'Step 1 complete'
});

// Read clipboard:
app.theClipboard();

// Get return value — wrap in run() for osascript to capture it:
function run() {
    const finder = Application('Finder');
    return finder.finderWindows[0].target().posixPath();
}
```

#### The ObjC bridge — JXA's killer feature

JXA exposes Objective-C frameworks directly via `ObjC.import()`. This lets a plain `.js` script call into Foundation, AppKit, or any system framework without compiling Swift or Obj-C:

```javascript
ObjC.import('Foundation');
ObjC.import('AppKit');

// Read a file using NSString:
const path = $(process.env.HOME + '/Desktop/notes.txt');
const content = ObjC.unwrap(
    $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null)
);

// List running applications:
const ws = $.NSWorkspace.sharedWorkspace;
const apps = ObjC.deepUnwrap(ws.runningApplications);
apps.forEach(a => console.log(ObjC.unwrap(a.localizedName)));
```

`$` is a convenience alias for `ObjC.wrap()` / the global ObjC namespace. `ObjC.unwrap()` converts an NSObject back to a plain JS value. This bridge is genuinely powerful — you can parse plists, query the pasteboard, interact with NSUserDefaults, and even create NSWindows from a script.

> 🔬 **Forensics note:** JXA is a well-documented malware persistence mechanism. `osascript -l JavaScript` with a LOLBin payload (payload fetched via `$.NSData.dataWithContentsOfURL`) leaves the same Unified Log entries as AppleScript. Look for `OSAScriptTask` and `com.apple.osascript` in `log stream --predicate 'subsystem == "com.apple.osascript"'`. JXA's ObjC bridge can bypass some sandbox restrictions that pure AppleScript cannot, because the permissions check is against the *calling process* (usually Terminal), not the script itself.

#### AppleScript vs JXA — when to choose

| Criterion | AppleScript | JXA |
|---|---|---|
| Community examples / StackOverflow | Vastly more | Sparse |
| IDE support (Script Editor dict browser) | Full | Partial |
| Readable by non-programmers | Yes | No |
| ObjC/Cocoa framework access | Via `use framework` + ASObjC | Via `ObjC.import()` — cleaner |
| String manipulation | Painful | Native JS |
| Loop/array logic | Painful (`repeat with`) | Natural JS |
| Active Apple development | Stagnant (3.0 since 2011) | Also stagnant but JS is learnable |
| macOS Tahoe compatibility | Full (no dict changes in 26.x) | Full |

The pragmatic answer: use **AppleScript** when you're copying from the dictionary or an online example that already exists in AS; use **JXA** when you need to write new logic from scratch, process data, or call Cocoa APIs.

---

### Layer 4 — The Shortcuts CLI

#### What it is

`shortcuts` is a command-line interface that invokes the Shortcuts framework — the same engine that runs your GUI Shortcuts. It ships with macOS 12 Monterey and later at `/usr/bin/shortcuts`.

```
$ shortcuts --help
USAGE: shortcuts <subcommand>

SUBCOMMANDS:
  run     Run a shortcut
  list    List shortcuts
  view    Open a shortcut in Shortcuts
  sign    Sign a shortcut file
```

#### shortcuts run — the key subcommand

```bash
# Basic run:
shortcuts run "My Shortcut"

# Pass a file as input (treated as file path, not text):
shortcuts run "Resize Images" -i ~/Desktop/photo.jpg

# Multiple files via wildcard:
shortcuts run "Compress PDFs" -i ~/Desktop/*.pdf

# Write output to a file (extension determines format):
shortcuts run "Generate Report" -o ~/Desktop/report.txt

# Pipe output to another command:
shortcuts run "Get Current Song" | pbcopy

# Force a specific output UTI:
shortcuts run "Export Data" --output-type public.json -o ~/Desktop/data.json
```

**Input via stdin pipe:** When you pipe text into `shortcuts run`, the shortcut receives it as plain text — but *only* if the shortcut is designed to accept input at the top (uses "Shortcut Input" as the first action's source). The CLI treats piped data as text, never as a file path.

```bash
# Works if the Shortcut begins with "Get Shortcut Input" and processes text:
echo "Hello world" | shortcuts run "Process Text"

# More reliable: use -i for file paths:
shortcuts run "OCR Image" -i /tmp/screenshot.png
```

#### shortcuts list and view

```bash
# List all shortcuts:
shortcuts list

# List shortcuts in a specific folder:
shortcuts list -f "Work Automations"

# List all custom folders:
shortcuts list --folders

# Open for editing in the GUI:
shortcuts view "My Shortcut"
```

#### Exit codes and automation

`shortcuts run` returns `0` on success, `1` on error. Errors print to stderr. This means you can use it in bash pipelines with `set -e` or explicit `||` error handling:

```bash
if ! shortcuts run "Nightly Backup"; then
    osascript -e 'display notification "Backup failed!" with title "Alert"'
fi
```

#### Limitations

- Shortcuts with interactive prompts ("Ask Each Time") will block the terminal waiting for user input — or silently hang. Design shortcuts for CLI use to accept specific input types rather than prompting.
- The CLI cannot create or modify Shortcuts programmatically — only run, list, and view existing ones.
- iCloud-synced Shortcuts must be available locally (downloaded) to run from CLI.

---

### How the Layers Interoperate

The real power is composing these surfaces. Here is the full interop graph:

```
Shell script
  ├── calls osascript (AppleScript or JXA)
  │     └── AppleScript/JXA drives GUI apps via Apple Events
  │           └── or calls shortcuts run via do shell script
  ├── calls shortcuts run directly
  │     └── Shortcut receives piped data or -i file paths
  │           └── Shortcut can run a Shell Script action internally
  └── calls any binary (python3, swift, etc.)
```

A concrete interop example: a shell cron job calls `osascript` to check if a GUI app is in a specific state, then calls `shortcuts run` to post results to Slack via a Shortcut action, and the Shortcut's final action pipes output back to the shell for logging.

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Use JXA to get the current Safari URL
current_url=$(osascript -l JavaScript \
  -e 'Application("Safari").windows[0].currentTab().url()')

# 2. Run a Shortcut that processes the URL (e.g., saves to Reading List DB)
echo "$current_url" | shortcuts run "Archive URL"

# 3. Notify via AppleScript
osascript -e "display notification \"Archived: $current_url\" with title \"Done\""
```

---

## Hands-on (CLI & GUI)

### Exploring app dictionaries

```bash
# Dump the Safari scripting dictionary to XML:
sdef /Applications/Safari.app | xmllint --format - | less

# Decompile a compiled .scpt back to text:
osadecompile ~/Library/Scripts/my_script.scpt

# List all OSA language plugins installed:
ls /System/Library/ScriptingAdditions/
ls ~/Library/ScriptingAdditions/       # user-installed additions
```

### Testing AppleScript interactively

Script Editor supports REPL-style execution: paste a snippet and press ⌘R. The Result pane shows the return value. Errors show with a line number and the offending token highlighted.

For quick testing from the shell without opening Script Editor:

```bash
# Run and print return value:
osascript -e 'tell application "Finder" to count every file of desktop'

# Run multiple -e expressions (executed in sequence):
osascript \
  -e 'tell application "Finder"' \
  -e '  set x to name of every disk' \
  -e 'end tell' \
  -e 'return x'
```

### Checking Accessibility permissions programmatically

```bash
# Which apps have Accessibility permission (TCC database — requires FDA):
sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, allowed FROM access WHERE service='kTCCServiceAccessibility';"

# Real-time: check if Terminal itself is trusted:
osascript -e 'tell application "System Events" to get name of every process' \
  && echo "Accessibility: granted" || echo "Accessibility: DENIED"
```

### Listing and running Shortcuts from the terminal

```bash
# See all shortcuts and their folders:
shortcuts list

# Time a shortcut run:
time shortcuts run "Morning Digest"

# Run and capture text output:
digest=$(shortcuts run "Morning Digest")
echo "$digest" | mail -s "Morning digest" me@example.com
```

---

## 🧪 Labs

### Lab 1 — Shell script with osascript notification

Build a script that wraps a long-running operation and fires a macOS notification on completion, including success/failure status.

```bash
#!/usr/bin/env bash
# notify-wrap.sh — run a command and notify when done
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command> [args...]" >&2
    exit 1
fi

notify() {
    local title="$1" subtitle="$2" message="$3"
    osascript -e "display notification \"$message\" \
        with title \"$title\" subtitle \"$subtitle\""
}

start=$(date +%s)
if "$@"; then
    elapsed=$(( $(date +%s) - start ))
    notify "Done ✓" "$*" "Completed in ${elapsed}s"
else
    exit_code=$?
    notify "Failed ✗" "$*" "Exit code: $exit_code"
    exit $exit_code
fi
```

Usage:
```bash
chmod +x notify-wrap.sh
./notify-wrap.sh sleep 3
./notify-wrap.sh make -C /some/project
```

Expected: a macOS banner notification appears after the command finishes, showing elapsed time and success/failure.

> ⚠️ **Note:** `display notification` requires no special permissions on modern macOS (unlike UI scripting). However, if Notification Center is set to "Do Not Disturb" / "Focus", notifications may be silently suppressed. Check `System Settings → Notifications` if nothing appears.

### Lab 2 — JXA snippet to drive an application

This JXA script queries all open Safari tabs across all windows and dumps their URLs to stdout — useful for session snapshots.

> ⚠️ **Requirements:** Safari must be open. The script accesses Safari's document data via Apple Events, which needs "Automation" permission for Terminal (`System Settings → Privacy & Security → Automation → Terminal → Safari`). The first run will prompt for permission.

```javascript
#!/usr/bin/env osascript -l JavaScript
// dump-safari-tabs.jxa
// Run: osascript -l JavaScript dump-safari-tabs.jxa

function run() {
    const safari = Application('Safari');
    const results = [];

    safari.windows().forEach((win, wi) => {
        win.tabs().forEach((tab, ti) => {
            results.push(`[W${wi+1}T${ti+1}] ${tab.name()} — ${tab.url()}`);
        });
    });

    return results.join('\n');
}
```

```bash
# Save and run:
osascript -l JavaScript dump-safari-tabs.jxa

# Or run inline (first tab URL only):
osascript -l JavaScript \
  -e 'Application("Safari").windows[0].tabs[0].url()'
```

**Using the ObjC bridge to read a plist:**

```javascript
#!/usr/bin/env osascript -l JavaScript
ObjC.import('Foundation');

function run() {
    const prefsPath = $(process.env.HOME + '/Library/Preferences/com.apple.dock.plist');
    const dict = $.NSDictionary.dictionaryWithContentsOfFile(prefsPath);
    // Extract tile-size (Dock icon size):
    const tileSize = ObjC.unwrap(dict.objectForKey('tilesize'));
    return `Dock tile size: ${tileSize}`;
}
```

```bash
osascript -l JavaScript read-dock-pref.jxa
# → Dock tile size: 64
```

> 🔬 **Forensics note:** The ObjC bridge can read any plist the calling process has permission to access. This is how forensic JXA tools enumerate `NSUserDefaults`, login items, browser history metadata, and recently accessed files — all without touching the filesystem directly through shell commands.

### Lab 3 — Run a Shortcut from the CLI with piped input

First, create a simple Shortcut in the Shortcuts app:
1. Open Shortcuts → New Shortcut.
2. Name it "Uppercase Text".
3. Add action: **Text** → set to `Shortcut Input`.
4. Add action: **Change Case** → set to Uppercase, input from previous step.
5. Add action: **Stop and Output** → output from previous step.
6. Save.

Now run it from the CLI:

```bash
# Pipe text input:
echo "hello world" | shortcuts run "Uppercase Text"
# → HELLO WORLD

# Capture output:
result=$(echo "forensic analysis complete" | shortcuts run "Uppercase Text")
echo "Result: $result"
# → Result: FORENSIC ANALYSIS COMPLETE

# Check what shortcuts you have:
shortcuts list | grep -i text
```

**End-to-end interop pipeline:**

```bash
#!/usr/bin/env bash
# full-interop-demo.sh — shell → JXA → Shortcuts → shell
set -euo pipefail

# Step 1: JXA gets the frontmost app name
frontmost=$(osascript -l JavaScript \
  -e 'Application("System Events").frontmostApplication().name()')

echo "Frontmost app: $frontmost"

# Step 2: Transform via Shortcut (uppercase the name)
upper=$(echo "$frontmost" | shortcuts run "Uppercase Text")

# Step 3: Notify via AppleScript
osascript -e "display notification \"$upper\" with title \"Active App\""

echo "Pipeline complete: $upper"
```

### Lab 4 — Forensics: audit osascript activity in Unified Log

> ⚠️ **Requires admin privileges for some log queries. Read-only — no system changes.**

```bash
# Stream live osascript activity:
log stream --predicate 'process == "osascript"' --info

# Query recent osascript executions (last hour):
log show --last 1h \
  --predicate 'process == "osascript" OR subsystem == "com.apple.osascript"' \
  --info | grep -v "^Fil"

# Find Apple Event dispatches (verbose — high volume):
log show --last 30m \
  --predicate 'subsystem == "com.apple.appleevents"' \
  --debug | head -100

# Check for Accessibility API usage:
log show --last 1h \
  --predicate 'subsystem == "com.apple.accessibility.AX"' \
  --info | grep -i "script\|osascript\|automation"
```

> 🔬 **Forensics note:** On a compromised machine, look for `osascript` spawned by unusual parents (`launchd` → `bash` → `osascript` via a LaunchAgent plist is a classic persistence pattern). Also check `~/Library/LaunchAgents/` for plists with `ProgramArguments` containing `osascript`. The `shortcuts` binary itself is rarely abused for persistence but can be used for lateral movement if a malicious Shortcut is installed.

---

## Pitfalls & gotchas

**AppleScript string quoting hell.** Embedding a variable in an `osascript -e` call from bash is a double-quoting minefield. Use heredocs or write to a temp `.applescript` file instead:

```bash
# FRAGILE (breaks on filenames with quotes):
osascript -e "tell app \"Finder\" to open POSIX file \"$path\""

# ROBUST:
osascript <<APPLE
tell application "Finder" to open POSIX file "$path"
APPLE

# MOST ROBUST (arbitrary data):
printf 'tell application "Finder" to open POSIX file "%s"\n' "$path" | osascript
```

**JXA `.jxa` vs `.js` in Script Editor.** Script Editor opens `.js` files in the text editor but won't syntax-highlight them as JXA. Use `.jxa` if you want the Script Editor experience; use `.js` if you want editor support in VS Code.

**`shortcuts run` hangs on interactive Shortcuts.** If a Shortcut contains any "Ask Each Time" inputs or "Choose from Menu" actions, `shortcuts run` will wait indefinitely for input that never comes (no TTY). Test Shortcuts in the GUI first and ensure they accept fully-specified input when called from CLI.

**osascript exit codes are unreliable for some errors.** Some AppleScript errors (like a permission denial from TCC) return exit code `0` with an error string on stderr rather than a non-zero exit. Always capture both stdout and stderr when scripting `osascript` in CI:

```bash
output=$(osascript my_script.applescript 2>&1) || true
if echo "$output" | grep -q "not authorized\|1743\|errAEEventNotPermitted"; then
    echo "TCC permission error" >&2
    exit 1
fi
```

**bash 3.2 `local` scoping quirk.** In `/bin/bash` 3.2, `local` can mask the exit status of a command:

```bash
# BUG: exit code of $(myfunc) is lost:
local result=$(myfunc_that_fails)
echo $?   # prints 0 on bash 3.2!

# FIX: declare first, assign separately:
local result
result=$(myfunc_that_fails)
echo $?   # now correctly non-zero
```

**JXA `.activate()` is not always required.** Many JXA examples call `.activate()` before driving an app. This raises the app to the front, which may be unwanted in background automations. You can send Apple Events to apps without activating them — only UI scripting (via System Events) requires the app to be frontmost for some interactions.

**Shortcuts CLI only sees locally available Shortcuts.** If a Shortcut is iCloud-synced but not yet downloaded to the current machine, `shortcuts run "Name"` fails with "not found." Run `shortcuts list` to verify availability before scripting against a name.

**macOS Tahoe `iTunes` alias removed.** In macOS 26.x, `tell application "iTunes"` no longer works as a legacy alias — it was dropped. Use `tell application "Music"`. The aliases `"System Preferences"`, `"iCal"`, and `"Address Book"` still resolve to their modern counterparts.

---

## Key takeaways

1. **Layer by capability, not preference.** Shell for process/file work. AppleScript/JXA when you need an app's internal object model (via its sdef dictionary). System Events + Accessibility when the app has no dictionary. Shortcuts when you want a portable action that runs from GUI, CLI, Siri, or keyboard shortcut.

2. **`set -euo pipefail` is non-negotiable** in any bash script that touches real data. The bash 3.2 limitation on macOS means avoiding associative arrays and `mapfile` in scripts targeting stock installs.

3. **osascript is your Apple Events gateway from the shell.** `-e` for inline, `-l JavaScript` for JXA, heredoc for multi-line. Capture stdout for return values; watch stderr for TCC errors.

4. **JXA's ObjC bridge** (`ObjC.import('Foundation')`) turns a plain `.js` file into a first-class macOS citizen that can call any system framework — and it's the same power that makes JXA interesting for forensic tooling and malware persistence.

5. **`shortcuts run` is the CLI entry point into Shortcuts automation.** Pipe text in; capture text out. Use `-i` for file paths. Design Shortcuts to accept explicit input rather than prompting, or they'll hang.

6. **Interop is the superpower.** A shell script calling `osascript` calling `do shell script` calling `shortcuts run` and piping back is not unusual. Know the seams.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Apple Events** | Mach-based IPC mechanism for structured inter-application communication; the transport layer under both AppleScript and JXA |
| **OSA** | Open Scripting Architecture — the macOS plugin system that hosts AppleScript, JXA, and third-party script languages |
| **sdef** | Scripting Definition file (XML); declares an app's scriptable object model |
| **tell block** | AppleScript construct that targets a specific application for subsequent commands |
| **UI scripting** | Driving app GUIs via the Accessibility API through System Events, rather than through a scripting dictionary |
| **TCC** | Transparency, Consent, and Control — macOS permission framework governing Accessibility, Automation, Full Disk Access, etc. |
| **JXA** | JavaScript for Automation — V8-based OSA runtime introduced in OS X Yosemite |
| **ObjC bridge** | JXA feature (`ObjC.import()`) for calling Objective-C frameworks directly from JavaScript |
| **osascript** | CLI tool at `/usr/bin/osascript` that executes AppleScript or JXA (and any OSA language) |
| **Shortcut Input** | The Shortcuts action that receives data passed via CLI (`-i` flag or stdin pipe) |
| **set -euo pipefail** | Bash safety header: exit on error, undefined variables are errors, pipeline errors propagate |
| **shebang** | First line of a script (`#!/usr/bin/env bash`) that tells the kernel which interpreter to invoke |
| **`.scpt`** | Compiled AppleScript bytecode (OSA binary format) |
| **`do shell script`** | AppleScript command that runs a shell command and returns its stdout as a string |

---

## Further reading

- [Apple: Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac) — official shortcuts CLI reference
- [Scripting OS X (Armin Briegel)](https://scriptingosx.com) — the definitive blog for macOS shell scripting; covers bash 3.2 traps in depth
- [JXA Cookbook (GitHub)](https://github.com/JXA-Cookbook/JXA-Cookbook/wiki) — community-maintained JXA recipes including ObjC bridge patterns
- [Apple Developer: AppleScript Language Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/) — reference for language syntax and Standard Additions
- [MacScripter Forums](https://www.macscripter.net) — active community for AppleScript/JXA questions; Tahoe compatibility thread linked above
- [osascript LOLBins](https://loobins.io/binaries/osascript/) — forensic perspective on `osascript` abuse patterns
- [Howard Oakley: Explainer on Apple Events & Security](https://eclecticlight.co/2021/10/26/how-macos-controls-access-to-system-events/) — deep dive on TCC and Apple Events permissions evolution

---

*Related lessons: [[00-terminal-and-shells]] · [[01-zsh-deep-dive]] · [[02-shell-fundamentals]] · [[03-essential-unix-commands]] · [[06-text-processing]]*
