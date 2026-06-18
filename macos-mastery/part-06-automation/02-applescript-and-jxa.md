---
title: AppleScript & JXA
part: P06 Automation
est_time: 60 min read + 45 min labs
prerequisites: [01-shortcuts-and-automator]
tags: [macos, automation, applescript, jxa, apple-events, system-events, osascript, tcc]
---

# AppleScript & JXA

> **In one sentence:** Apple Events is a 35-year-old IPC protocol that lets any process issue high-level commands to any scriptable app — AppleScript and JXA are two languages riding that same wire, giving you GUI-deep automation that nothing else on macOS can replicate.

## Why this matters

Shortcuts replaced Automator and can chain many system actions. But Shortcuts cannot open a specific Finder window and move the selected files, drive Mail to compose a message with computed headers, set a playlist repeat mode in Music, or interact with a button inside a third-party app that has no Shortcuts actions. Apple Events, surfaced as AppleScript or JXA, still is the only general-purpose automation layer that reaches inside running applications at the object level. If you are doing forensic triage, incident response, or simply managing a fleet of Macs as a power user, you will eventually need to script the Finder, the shell, System Events, or a domain-specific app like BBEdit or OmniFocus. This lesson gives you the engineering foundation, not just the syntax.

> 🪟 **Windows contrast:** The Windows equivalent is COM Automation (IDispatch) called from VBScript, VBA, or PowerShell via `New-Object -ComObject`. COM objects expose typed interfaces via a type library (`.tlb`); Apple Events expose a scripting dictionary (`.sdef`). Both allow driving GUI apps at the object model level. Windows UI Automation (UIA), the accessibility-tree approach, maps to macOS's GUI Scripting via System Events + the Accessibility framework. JXA's Objective-C bridge has no clean Windows equivalent — the closest is PowerShell's `[System.Windows.Forms.*]` reflection or Python's `win32com`.

---

## Concepts

### Apple Events: the wire under the hood

An **Apple Event** is a high-level IPC message defined in the Core Suite (1989, System 7). Every Apple Event has four-character codes identifying its **event class** and **event ID** (e.g., `core / getd` = `Get Data`, `aevt / quit` = Quit Application). The sending process packages the event as an `AEDesc` (Apple Event Descriptor) tree, serializes it via Mach messaging or BSD sockets, and delivers it to the target process. The target's `NSApplication` receives it, dispatches through `NSAppleEventManager`, and returns a reply `AEDesc`.

```
Script / Shell
   │
   │  osascript / AppleScript.framework
   ▼
AEDesc packed (four-char codes + typed values)
   │
   │  Mach port (launchd-brokered) or BSD socket
   ▼
Target app's run loop (NSAppleEventManager)
   │
   ▼
Handler → object specifier resolution → return AEDesc
```

This is **not** a screen-scrape. When you `tell application "Music" to get name of current track`, Music evaluates the object specifier `current track → name` against its live in-memory object graph and returns the string directly. No pixels involved.

**Object specifiers** are the key abstraction. They are lazy references — `every track of playlist "Jazz"` is a description, not a snapshot. The target app resolves them at execution time. You can compose them: `first track of (tracks of playlist "Jazz" whose duration > 300)`.

#### On-disk artifacts (forensics)

> 🔬 **Forensics note:** Apple Events leave two categories of on-disk artifacts:
> - **TCC database** (`~/Library/Application Support/com.apple.TCC/TCC.db` and `/Library/Application Support/com.apple.TCC/TCC.db`) — every Automation permission grant is recorded here with the client bundle ID, the target bundle ID, and the decision. `sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT client,service,auth_value,last_modified FROM access WHERE service='kTCCServiceAppleEvents';"` reveals which apps have been granted Apple Events access to which targets.
> - **Script files** — `.scpt` (compiled AppleScript, binary format), `.applescript` (source text), `.scptd` (script bundle, a directory with an `Info.plist`). Malware frequently ships `.scpt` files embedded in email attachments or app bundles. Use `osadecompile` to recover source from a compiled `.scpt`.

### The Scripting Definition (.sdef)

An app documents its Apple Events vocabulary in a **Scripting Definition** file, an XML document embedded in the app bundle at `Contents/Resources/<AppName>.sdef` (or sometimes merged from a framework). The `.sdef` specifies:

- **Suites** — groupings of related functionality (Standard Suite, Text Suite, app-specific suites)
- **Classes** — object types the app exposes (document, track, message, window)
- **Properties** — typed attributes on a class (name, id, duration, bounds)
- **Elements** — containment relationships (a playlist *contains* tracks)
- **Commands** — verbs the app responds to (play, make, move, delete)
- **Enumerations** — named constant lists (shuffle mode: songs / albums / groupings)

Open a dictionary in **Script Editor**: File ▸ Open Dictionary (⇧⌘O) — paste any running app name or drag its bundle in. You can also `sdef /Applications/Music.app` from the shell to dump the raw XML.

```bash
# Inspect Music's dictionary; grep for what's scriptable
sdef /Applications/Music.app | grep -E '<(class|command|property) name'
```

### AppleScript language essentials

#### Tell blocks and object model navigation

```applescript
tell application "Music"
    set currentTrack to current track
    set trackName to name of currentTrack
    set trackDuration to duration of currentTrack -- seconds, real
    
    -- Nested tell: temporally narrow scope
    tell current track
        set t to name
        set a to artist
        set l to album
    end tell
    
    -- Object specifiers with filters
    set longTracks to (every track of playlist "Library" whose duration > 300)
    return count of longTracks
end tell
```

Every name inside a `tell application` block is resolved against that app's object model. You can also use fully-qualified specifiers anywhere:

```applescript
name of current track of application "Music"
```

#### Properties, lists, and records

```applescript
-- List (zero-based? NO — AppleScript lists are 1-based)
set myList to {"alpha", "beta", "gamma"}
set firstItem to item 1 of myList        -- "alpha"
set myList to myList & {"delta"}         -- concatenate

-- Record (like a JS object / Python dict with fixed keys)
set fileInfo to {name:"report.pdf", size:42000, modified:current date}
set n to name of fileInfo

-- Coerce types
set numStr to "42" as integer            -- 42
set dateStr to current date as string
```

#### Handlers (subroutines)

```applescript
on run
    set result to padLeft("7", 3, "0")   -- "007"
    display dialog result
end run

on padLeft(str, targetLen, padChar)
    set s to str as string
    repeat while (length of s) < targetLen
        set s to padChar & s
    end repeat
    return s
end padLeft

-- Handlers with labeled parameters (AppleScript idiom)
on renameFile(theFile, withSuffix:sfx)
    -- ...
end renameFile
-- Call: renameFile(f, withSuffix: "_bak")
```

#### Error handling

```applescript
try
    tell application "Finder"
        move file "/tmp/ghost.txt" to trash
    end tell
on error errMsg number errNum
    log "Error " & errNum & ": " & errMsg
    -- errNum -128 = user cancelled, -1700 = coercion failed, -1728 = object not found
end try
```

Key error numbers: `-128` user cancelled, `-1728` can't get object (object not found), `-600` app not running (with `activate` this is usually recoverable), `-1700` can't coerce type, `-50` bad parameter.

#### Useful standard idioms

```applescript
-- Current date arithmetic
set deadline to (current date) + (7 * days)

-- POSIX path ↔ HFS path (file package coercions)
set posixPath to POSIX path of (path to desktop)   -- "/Users/you/Desktop/"
set hfsPath to POSIX file "/tmp/test.txt" as alias -- HFS alias

-- Run shell command and capture output
set output to do shell script "ls -la ~/Downloads | wc -l"
```

### System Events: two distinct powers

`System Events.app` (`/System/Library/CoreServices/System Events.app`) is a permanently-running faceless background app with two distinct scripting personalities:

#### 1. File / Property List / Disk scripting

System Events implements a broad Standard Suite extension covering:

- **File / folder operations** — not as rich as Finder, but works in sandboxed contexts
- **Property lists** — read and write `.plist` files directly as AppleScript records
- **Login items** — enumerate and add/remove items in Login Items
- **Disk operations** — enumerate volumes

```applescript
-- Read a plist value
tell application "System Events"
    tell property list file (POSIX file "/Users/me/Library/Preferences/com.example.app.plist")
        set apiKey to value of property list item "APIKey"
    end tell
end tell
```

#### 2. GUI scripting (UI Automation via Accessibility)

When you `tell process "AppName"` inside System Events, you are navigating the **Accessibility object tree** — the same tree VoiceOver reads. Every UI element is an `AXUIElement` with a role (`AXButton`, `AXTextField`, `AXMenuBar`), a title, and a position.

```applescript
tell application "System Events"
    tell process "Safari"
        -- Navigate the menu bar
        click menu item "Reload Page" of menu "View" of menu bar 1
        
        -- Click a named button
        tell window 1
            click button "Done"
        end tell
        
        -- Type into a text field
        tell text field 1 of group 1 of window 1
            set value to "https://example.com"
        end tell
        
        -- Send a keystroke
        keystroke "l" using command down  -- ⌘L = focus address bar in browsers
        keystroke return
    end tell
end tell
```

**Requirement:** The script's parent process (Script Editor, Terminal, osascript, your app) must have **Accessibility** permission granted in System Preferences ▸ Privacy & Security ▸ Accessibility. This is stored as `kTCCServiceAccessibility` in the TCC database. Unlike Automation permissions, Accessibility is coarser — granting Terminal grants ALL scripts run from Terminal.

**Fragility:** GUI scripting relies on element titles and roles remaining stable across app versions. A UI rearrangement by the app developer silently breaks your script. Use it for apps with no scripting dictionary or when the dictionary doesn't expose the control you need.

> 🔬 **Forensics note:** GUI scripting abuse is a known malware vector. A malicious `.app` with Accessibility permission can click UI elements in other apps — including Security preference dialogs. Any app on an investigation target that has `kTCCServiceAccessibility` should be scrutinized. Check the TCC db and cross-reference against the app's code-signing identity.

---

### TCC and Automation permissions

Since macOS Mojave (10.14), **every Apple Events send to a different app requires user consent** the first time. The TCC service is `kTCCServiceAppleEvents`. The prompt reads: _"Do you want to allow [Script Editor] to control [Music]?"_

Entitlement mechanics:
- **Unsigned scripts / `osascript`**: The granting client is the *parent process* (Terminal, Script Editor). Granting Terminal → all scripts from Terminal get the same bundle of permissions.
- **Signed app bundles wrapping AppleScript**: Each bundle ID gets its own TCC entry. Sandboxed App Store apps additionally need the `com.apple.security.automation.apple-events` entitlement and must list target bundle IDs in `com.apple.security.scripting-targets`.
- **`tccutil reset AppleEvents`** resets all Apple Events grants, forcing fresh prompts. Useful during testing; destructive in production.
- **MDM/configuration profile**: Enterprises can pre-approve TCC entries via a `com.apple.TCC.configuration-profile-policy` payload, allowing silent automation in managed environments.

**Prompt once, deliberately — don't let a stray `tell` block raise the dialog.** Pre-flight with `AEDeterminePermissionToAutomateTarget`: call it with `askUserIfNeeded = false` to read the current status silently (`noErr` = authorized, `-1744` = not yet asked, `-1743` = the user denied — stop re-firing and degrade gracefully, `-600` = target not running), then call it again with `askUserIfNeeded = true` at a moment that makes sense to the user. This times the single prompt and lets you detect denial instead of looping into errors.

**If you ship an *app* that automates another app and it re-prompts on every launch, that's an identity-stability bug, not a TCC quirk** — almost always ad-hoc signing (cdhash changes each build) or App Translocation (a quarantined app run from a DMG/Downloads gets a randomized path each launch). The full decision tree, the `AEDeterminePermissionToAutomateTarget` codes, and the "design so you never need the prompt" pattern (embed-then-import) are in [[02-tcc-and-privacy]] → *The Builder's View: Why a Grant Persists — or Re-Prompts Every Launch*. The cheapest automation prompt is the one you architect away: if the target app will ingest the right input on its own (e.g. metadata embedded in a file it imports), you may not need Apple Events — or its entitlement — at all.

> ⚠️ **macOS 26 Tahoe note:** Forum reports (macscripter.net, 2026) indicate intermittent application-hang issues with AppleScript on Tahoe, particularly when targeting apps like Music and Numbers. Recompiling and re-saving scripts in Script Editor resolves most cases — this is a bytecode-compatibility issue between the `.scpt` compiled under Sequoia and Tahoe's AppleScript runtime. If you see spinning pinwheels when running scripts that worked on Sequoia, open in Script Editor and resave.

---

### JXA: JavaScript for Automation

Introduced in OS X Yosemite (10.10), JXA is a **second language binding over the same Apple Events bridge**. The runtime is `OSAKit` / `JavaScriptCore`; the language is ES2015+ JavaScript. Everything you can do in AppleScript you can do in JXA — and vice versa — because both sides compile to the same `NSAppleEventDescriptor` messages at the bottom.

#### Application() and the object model

```javascript
// Run with: osascript -l JavaScript script.js

const Music = Application("Music")
Music.activate()

const track = Music.currentTrack()
console.log(track.name())        // getter is a function call in JXA
console.log(track.duration())

// Element collections — use .() to materialize
const playlists = Music.playlists()
playlists.forEach(pl => console.log(pl.name()))

// Object specifiers (lazy, not materialized until called)
const jazzTracks = Music.playlists.byName("Jazz").tracks.whose({duration: {'>': 300}})
console.log(jazzTracks.length)
```

Key JXA idiom: **properties are functions** — `track.name()` not `track.name`. Collections use `.()` to unpack or iteration methods. This trips up every AppleScript veteran.

#### currentApplication() — self-referential scripts

```javascript
const app = Application.currentApplication()
app.includeStandardAdditions = true
const choice = app.chooseFromList(["Red", "Green", "Blue"], {
    withPrompt: "Pick a color:",
    defaultItems: ["Red"]
})
console.log(choice[0])
```

`includeStandardAdditions = true` pulls in the Standard Additions scripting bundle (same as AppleScript's `use scripting additions`), adding `chooseFile`, `chooseFromList`, `displayDialog`, `doShellScript`, etc.

#### The Objective-C bridge

JXA has a unique superpower: direct access to macOS Foundation and AppKit via the ObjC bridge. Import with `ObjC.import('Foundation')` (or other frameworks).

```javascript
ObjC.import('Foundation')
ObjC.import('AppKit')

// NSBeep
$.NSBeep()

// Read a file via NSString
const path = $.NSString.stringWithString("/etc/hosts")
const content = $.NSString.stringWithContentsOfFileEncodingError(
    path, $.NSUTF8StringEncoding, null
)
console.log(ObjC.unwrap(content))

// NSUserDefaults — read a preference
ObjC.import('Foundation')
const defaults = $.NSUserDefaults.alloc.init
const val = defaults.stringForKey("NSNavLastRootDirectory")
console.log(ObjC.unwrap(val))

// Enumerate files in a directory
const fm = $.NSFileManager.defaultManager
const dirURL = $.NSURL.fileURLWithPath($($.NSHomeDirectory()).stringByAppendingPathComponent("Downloads"))
const items = fm.contentsOfDirectoryAtURLIncludingPropertiesForKeysOptionsError(
    dirURL, $([]), $.NSDirectoryEnumerationSkipsHiddenFiles, null
)
const count = items.count
for (let i = 0; i < count; i++) {
    console.log(ObjC.unwrap(items.objectAtIndex(i).lastPathComponent))
}
```

`$()` converts a JS value to an ObjC object; `ObjC.unwrap()` converts back. `$.SomeClass.method` uses dot notation; long selector names concatenate with camelCase (`contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:` → `contentsOfDirectoryAtURLIncludingPropertiesForKeysOptionsError`).

> 🪟 **Windows contrast:** JXA's ObjC bridge is conceptually similar to PowerShell's `[System.Reflection.Assembly]::LoadWithPartialName()` + `[SomeNamespace.SomeClass]::Method()` pattern, or to Python's `ctypes` / `win32com`. The difference is that Apple ships the bridge in the OS itself with stable documentation, while the Windows equivalents are more ad hoc.

#### When to use JXA vs. AppleScript

| Situation | Prefer |
|---|---|
| Driving well-documented scriptable app (Mail, Finder, Music) | AppleScript — dictionaries are written with it in mind; community examples are plentiful |
| Integrating with JSON APIs, doing string manipulation, array transforms | JXA — real `.map()`, `.filter()`, `JSON.parse()` |
| Calling Foundation/AppKit directly without Xcode | JXA ObjC bridge |
| Quick one-liner from shell | Either (`osascript -e` vs `osascript -l JavaScript -e`) |
| Sharing with non-engineers on a team | AppleScript — readable prose syntax |
| Embedding in a Swift/ObjC app | Use `OSAScript` / `NSAppleScript` — same underlying engine |

---

## Hands-on (CLI & GUI)

### Script Editor

Script Editor (`/System/Applications/Utilities/Script Editor.app`) is the IDE:

- **Compile** (⌘K): syntax-checks and bytecode-compiles
- **Run** (⌘R): compile + execute
- **Open Dictionary** (⇧⌘O): browse any app's `.sdef` vocabulary with search
- **Event Log**: shows every Apple Event sent, invaluable for debugging
- **Result pane**: shows the return value of the last expression

Compiled scripts save as `.scpt` (binary) by default; choose File ▸ Save → Format: Script to get `.applescript` (plain text, version-controllable).

### Running from the shell

```bash
# Inline AppleScript
osascript -e 'tell application "Finder" to get name of front window'

# Inline JXA
osascript -l JavaScript -e 'Application("Finder").windows[0].name()'

# From a file
osascript my_script.scpt
osascript -l JavaScript my_script.js

# Compile to .scpt without running
osacompile -o output.scpt source.applescript

# Decompile a .scpt back to source
osadecompile compiled.scpt

# Pass arguments (available as argv in AS, as $argv in JXA)
osascript script.scpt "arg1" "arg2"
# In AppleScript: on run argv → item 1 of argv
# In JXA: function run(argv) { return argv[0] }
```

### The Script Menu

Enable **Script Menu** in Script Editor ▸ Preferences ▸ General ▸ Show Script menu in menu bar. This adds a tray icon with access to scripts in:
- `~/Library/Scripts/` — user scripts
- `/Library/Scripts/` — system-wide scripts
- `~/Library/Scripts/Applications/<AppName>/` — scripts that appear only when that app is frontmost

---

## Real recipes

### Recipe 1: Rename Finder selection with a numeric prefix

```applescript
-- Adds a zero-padded sequence number to each selected file in Finder
-- e.g., "photo.jpg" → "001_photo.jpg"

tell application "Finder"
    set selectedItems to selection as list
    if (count of selectedItems) is 0 then
        display dialog "No files selected." buttons {"OK"} default button 1
        return
    end if
    
    set counter to 1
    repeat with theItem in selectedItems
        set oldName to name of theItem
        set ext to name extension of theItem
        set baseName to text 1 thru ((length of oldName) - (length of ext) - 1) of oldName
        
        -- Zero-pad counter to 3 digits
        set paddedNum to text -3 thru -1 of ("00" & counter)
        set newName to paddedNum & "_" & oldName
        set name of theItem to newName
        set counter to counter + 1
    end repeat
end tell
```

### Recipe 2: Drive Mail to batch-send from a CSV via shell + AppleScript

```bash
#!/bin/bash
# Usage: ./mailmerge.sh contacts.csv
while IFS=, read -r name email subject; do
    osascript <<EOF
tell application "Mail"
    set msg to make new outgoing message with properties ¬
        {subject:"$subject", content:"Hi $name,\n\nThis is your report.\n\nRegards", visible:false}
    tell msg
        make new to recipient at end of to recipients ¬
            with properties {name:"$name", address:"$email"}
    end tell
    send msg
end tell
EOF
done < "$1"
```

### Recipe 3: Safari URL harvester (JXA)

```javascript
// Collect URLs from all open Safari tabs into a JSON file
// osascript -l JavaScript safari_urls.js

ObjC.import('Foundation')

const Safari = Application("Safari")
const windows = Safari.windows()
const result = []

windows.forEach(win => {
    try {
        win.tabs().forEach(tab => {
            result.push({ title: tab.name(), url: tab.url() })
        })
    } catch(e) {}
})

const json = JSON.stringify(result, null, 2)
const outPath = $.NSHomeDirectory().stringByAppendingPathComponent("Downloads/safari_urls.json")
$(json).writeToFileAtomicallyEncodingError(
    ObjC.unwrap(outPath), true, $.NSUTF8StringEncoding, null
)
console.log(`Saved ${result.length} URLs to ~/Downloads/safari_urls.json`)
```

### Recipe 4: GUI scripting an app with no dictionary

```applescript
-- Force-quit a hung app via its Force Quit menu entry
-- (for apps that don't respond to Apple Events)

tell application "System Events"
    -- Bring up Force Quit Applications dialog
    keystroke escape using {command down, option down}
    delay 0.5
    
    -- Alternatively, target a process directly via UI tree
    tell process "TextEdit"
        -- Click the close button of the front window
        click button 1 of window 1  -- button 1 is typically the red close dot
    end tell
end tell
```

### Recipe 5: JXA ObjC — read unified log entries

```javascript
// Pull last 50 lines from the system log for a subsystem
ObjC.import('Foundation')

const task = $.NSTask.alloc.init
task.launchPath = "/usr/bin/log"
task.arguments = $([
    "show", "--last", "5m",
    "--predicate", "subsystem == 'com.apple.securityd'",
    "--style", "compact"
])

const pipe = $.NSPipe.pipe
task.standardOutput = pipe
task.launch
task.waitUntilExit

const data = pipe.fileHandleForReading.readDataToEndOfFile
const output = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)
console.log(ObjC.unwrap(output))
```

---

## 🧪 Labs

### Lab 1: AppleScript via scripting dictionary

**Goal:** Write an AppleScript that queries Music's library, finds the 5 longest tracks, and displays them in a dialog.

**Setup:** Have some tracks in Music. Script Editor open.

```applescript
-- Save as: longest_tracks.applescript
tell application "Music"
    set allTracks to every track of playlist 1
    
    -- Build a list of {duration, name} records
    set trackData to {}
    repeat with t in allTracks
        set end of trackData to {dur:duration of t, tname:name of t, tartist:artist of t}
    end repeat
    
    -- Simple bubble sort (small lists only — for demo)
    set n to count of trackData
    repeat with i from 1 to n - 1
        repeat with j from 1 to n - i
            if dur of item j of trackData < dur of item (j + 1) of trackData then
                set temp to item j of trackData
                set item j of trackData to item (j + 1) of trackData
                set item (j + 1) of trackData to temp
            end if
        end repeat
    end repeat
    
    -- Build display string from top 5
    set resultText to "Top 5 Longest Tracks:" & return
    repeat with i from 1 to (minimum value of {5, n})
        set td to item i of trackData
        set mins to (dur of td) div 60
        set secs to (dur of td) mod 60
        set timeStr to mins & ":" & text -2 thru -1 of ("0" & secs)
        set resultText to resultText & i & ". " & tname of td & " — " & tartist of td & " (" & timeStr & ")" & return
    end repeat
    
    display dialog resultText buttons {"OK"} default button 1
end tell
```

> ⚠️ Modifies nothing; read-only. No backup required.

**Expected output:** A dialog box listing the 5 longest tracks with artist and duration.

---

### Lab 2: GUI scripting via System Events (Accessibility)

**Goal:** Script the Calculator app (no AppleScript dictionary) to compute a value via UI scripting.

> ⚠️ **Requires Accessibility permission for Script Editor or Terminal.** Grant it in System Settings ▸ Privacy & Security ▸ Accessibility. To roll back: remove the entry. No data is modified.

```applescript
-- Open Calculator and compute 137 * 42 via GUI scripting
tell application "Calculator" to activate
delay 0.5

tell application "System Events"
    tell process "Calculator"
        -- Press: 1, 3, 7, *, 4, 2, =
        repeat with ch in {"1", "3", "7", "*", "4", "2", "="}
            keystroke (item 1 of ch)
            delay 0.05
        end repeat
        
        -- Read the result from the display
        set displayValue to value of static text 1 of group 1 of window 1
        display dialog "137 × 42 = " & displayValue buttons {"OK"} default button 1
    end tell
end tell
```

To discover UI element roles: add a step before the computation:

```applescript
tell application "System Events"
    tell process "Calculator"
        -- Dump top-level UI elements
        set uiItems to entire contents of window 1
        -- Check Event Log for AXRole and AXTitle of each element
    end tell
end tell
```

The **Accessibility Inspector** app (`/Applications/Xcode.app/Contents/Applications/Accessibility Inspector.app`, part of Xcode) is the gold standard for navigating the live AX tree without guessing.

---

### Lab 3: The same task in JXA

**Goal:** Port the Music track-lister (Lab 1) to JXA, and add JSON output.

```javascript
// Save as: longest_tracks.js
// Run: osascript -l JavaScript longest_tracks.js

ObjC.import('Foundation')
const app = Application.currentApplication()
app.includeStandardAdditions = true

const Music = Application("Music")
const tracks = Music.playlists[0].tracks()

const sorted = tracks.map(t => ({
    name: t.name(),
    artist: t.artist(),
    duration: t.duration()
})).sort((a, b) => b.duration - a.duration).slice(0, 5)

// Pretty-print to console
sorted.forEach((t, i) => {
    const m = Math.floor(t.duration / 60)
    const s = Math.floor(t.duration % 60).toString().padStart(2, '0')
    console.log(`${i+1}. ${t.name} — ${t.artist} (${m}:${s})`)
})

// Write JSON to ~/Downloads
const json = JSON.stringify(sorted, null, 2)
const outPath = $.NSString.stringWithString(`${$.NSHomeDirectory()}/Downloads/top_tracks.json`)
$(json).writeToFileAtomicallyEncodingError(
    ObjC.unwrap(outPath), true, $.NSUTF8StringEncoding, null
)
console.log("Written to ~/Downloads/top_tracks.json")
```

Compare: JXA's `.map()`, `.sort()`, `.slice()`, and `padStart()` replace AppleScript's verbose `repeat` loops and manual string padding. The ObjC bridge adds file output without needing `do shell script`.

---

### Lab 4: Forensic audit — who has Apple Events permission?

> 🔬 **Forensics note:** Run this on a suspect machine to see all granted Apple Events automation permissions.

```bash
# Requires: copy the user TCC db first (it's locked while in use by tccd)
sudo cp /Library/Application\ Support/com.apple.TCC/TCC.db /tmp/system_tcc.db
cp ~/Library/Application\ Support/com.apple.TCC/TCC.db /tmp/user_tcc.db

# Query Apple Events grants
sqlite3 /tmp/user_tcc.db <<'SQL'
SELECT
    client,
    indirect_object_identifier AS target_app,
    auth_value,  -- 2 = allowed, 0 = denied
    datetime(last_modified, 'unixepoch') AS last_modified
FROM access
WHERE service = 'kTCCServiceAppleEvents'
ORDER BY last_modified DESC;
SQL

sqlite3 /tmp/system_tcc.db <<'SQL'
SELECT client, indirect_object_identifier, auth_value,
       datetime(last_modified, 'unixepoch') AS when
FROM access WHERE service = 'kTCCServiceAppleEvents';
SQL
```

> ⚠️ `sudo cp` of the system TCC.db requires SIP to be partially disabled or FDA granted to Terminal. On a forensic image mounted read-only, query the `.db` directly with `sqlite3`.

---

## Pitfalls & gotchas

**1. JXA property access is always a function call.**
`track.name` returns an object specifier. `track.name()` returns the string. Forgetting `()` is the #1 JXA bug.

**2. AppleScript list indices start at 1.**
`item 1 of myList` is the first element. `item 0` causes an error. Coercing to array for heavy manipulation is better done in JXA.

**3. `activate` before sending events.**
Some apps respond poorly to Apple Events while in the background or before their first window is ready. A brief `delay 0.3` after `activate` is often needed for GUI-scripting scripts. Avoid hard `delay` in production; instead loop-wait for `exists window 1`.

**4. Compiled `.scpt` files are not source.**
They contain bytecode. Always keep the `.applescript` source in version control. Use `osadecompile` to recover source when you only have the `.scpt`.

**5. GUI scripting breaks on app updates.**
Button titles change; element hierarchies shift. Anchor UI scripts on `AXIdentifier` (an accessibility identifier set by the developer) rather than `title` or index when possible — identifiers are more stable. In Accessibility Inspector, look for the "Identifier" field.

**6. `osascript` in sandboxed environments.**
If your script is launched from a sandboxed app or via launchd without the right entitlements, Apple Events to other apps will be silently denied (no prompt, just an error `-1743: Not authorized to send Apple events to...`). The entitlement `com.apple.security.automation.apple-events` must be present in the caller's entitlements, with a `com.apple.security.scripting-targets` dict listing allowed target bundle IDs.

**7. Tahoe `.scpt` recompile requirement.**
As noted in macOS 26 compatibility reports: scripts compiled on Sequoia that drive Music, Numbers, or QuickTime may spin indefinitely on Tahoe. Open in Script Editor, compile (⌘K), and resave. Keep `.applescript` source so recompilation is always possible.

**8. `do shell script` vs. `NSTask`.**
`do shell script` in AppleScript runs through `/bin/sh -c` as the current user, inherits a minimal environment (notably, `/usr/local/bin` and Homebrew paths may be missing). Either set `PATH` explicitly or use JXA's `NSTask` for reliable PATH control.

**9. The ObjC bridge's selector camelCasing.**
`writeToFile:atomically:encoding:error:` becomes `writeToFileAtomicallyEncodingError`. Each colon becomes a capital letter on the next word. Get this wrong and the method silently fails with `undefined` — add `try/catch` around ObjC bridge calls while debugging.

---

## Key takeaways

- Apple Events is a **typed IPC protocol** — not a screen-scrape. Scriptable apps expose a dictionary (`.sdef`) of classes, properties, and commands; scripts send `AEDesc` messages resolved against the app's live object graph.
- **AppleScript** and **JXA** ride the same wire. Choose based on ergonomics: AppleScript for dictionary-heavy app driving and team readability; JXA when you need real JS data structures, `JSON.parse`, or Foundation access via the ObjC bridge.
- **System Events** does double duty: `property list file` scripting for plist R/W, and `tell process` GUI scripting via the Accessibility tree for apps with no dictionary.
- **TCC** (`kTCCServiceAppleEvents`, `kTCCServiceAccessibility`) gates all automation. Every permission grant is recorded in two SQLite databases — a goldmine for forensic audit.
- `osascript -l JavaScript` makes JXA a first-class shell scripting tool. Combine with `ObjC.import('Foundation')` for file I/O, `NSTask` for subprocesses, and `NSUserDefaults` for pref inspection.
- macOS 26 Tahoe: if existing `.scpt` files hang on app interaction, **recompile in Script Editor** — this is a known bytecode-compatibility issue, not a conceptual failure of the automation layer.

---

## Terms introduced

| Term | Definition |
|---|---|
| Apple Event | A typed IPC message with four-char class+ID codes, encoding commands and object specifiers between processes |
| AEDesc / AEDescriptor | The fundamental data container in the Apple Event protocol; a typed tree node (NSAppleEventDescriptor in Cocoa) |
| Object specifier | A lazy reference to objects in an app's model, resolved at dispatch time (e.g., `name of current track of application "Music"`) |
| `.sdef` | XML Scripting Definition file declaring an app's scriptable vocabulary; embedded in the app bundle |
| tell block | AppleScript construct that scopes commands to a target application or object |
| System Events | macOS daemon app (`com.apple.systemevents`) that provides file/plist scripting and GUI scripting via the Accessibility API |
| GUI scripting | Driving an app's UI through the Accessibility object tree (AXUIElement) instead of Apple Events — fragile but universal |
| JXA | JavaScript for Automation — OSAKit language binding that delivers the same Apple Events bridge in ES2015+ JavaScript |
| ObjC bridge | JXA capability to call Foundation/AppKit APIs directly using `ObjC.import()`, `$()`, and `ObjC.unwrap()` |
| kTCCServiceAppleEvents | TCC service name governing inter-app Apple Events permission; recorded in TCC.db |
| kTCCServiceAccessibility | TCC service name governing Accessibility/GUI scripting permission |
| osascript | CLI tool (`/usr/bin/osascript`) to run AppleScript and JXA from the shell; supports `-e` inline and `-l JavaScript` flag |
| osacompile | CLI tool to compile AppleScript source to `.scpt` bytecode |
| osadecompile | CLI tool to decompile `.scpt` binary back to source |
| Standard Additions | Scripting bundle providing `display dialog`, `choose file`, `do shell script`, and other utilities to both AppleScript and JXA |

---

## Further reading

- **Apple Scripting & Automation forums**: developer.apple.com/forums/topics/app-and-system-services/automation-and-scripting
- **Apple: Scriptable Applications (archived)**: developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptX/Concepts/scriptable_apps.html
- **JXA Cookbook** (community-maintained): github.com/JXA-Cookbook/JXA-Cookbook/wiki — comprehensive recipes including the ObjC bridge
- **josh- / automating-macOS-with-JXA-presentation**: github.com/josh-/automating-macOS-with-JXA-presentation — slides + examples covering the full JXA surface
- **Apple Developer: Sandboxing and Automation (QA1888)**: developer.apple.com/library/archive/qa/qa1888 — entitlement requirements for sandboxed apps sending Apple Events
- **NSAppleEventDescriptor reference**: developer.apple.com/documentation/foundation/nsappleeventdescriptor
- **macscripter.net** — the longest-running AppleScript community; threads on macOS 26 Tahoe compatibility issues
- **SwiftAutomation** (hhas.bitbucket.io) — a Swift library for Apple Events that illuminates the underlying protocol more clearly than any scripting doc
- Related lessons: [[01-shortcuts-and-automator]], [[03-shell-scripting-bash-zsh]], [[05-tcc-and-privacy-permissions]]
