---
title: "Rule engines: Hazel & Keyboard Maestro"
part: P06 Automation
est_time: 60 min read + 45 min labs
prerequisites: [03-shortcuts-and-automator, 02-launchd-and-cron]
tags: [macos, automation, hazel, keyboard-maestro, file-management, macros, productivity]
---

# Rule engines: Hazel & Keyboard Maestro

> **In one sentence:** Hazel is a persistent folder-watching rule engine that acts on files the moment they arrive; Keyboard Maestro is a macro runtime that reacts to anything — keystrokes, typed strings, app focus, USB events, time — and executes arbitrarily complex action sequences, giving you a two-layer automation stack that covers virtually every repetitive task macOS throws at you.

---

## Why this matters

Shortcuts and Automator handle things you deliberately kick off. launchd handles timed or boot-triggered jobs. But neither answers the question "what happens automatically when *things land on my machine*?" — a PDF in Downloads, a screenshot on the Desktop, a new email attachment, an app you just dragged to the Trash.

Hazel fills the file-event gap as a user-space file-system watcher. Keyboard Maestro fills the human-interaction gap as an always-on macro engine that intercepts input events before (and after) the target application even sees them. Together they eliminate the entire category of "things I keep doing manually." Power users who learn both tools typically shave 30–90 minutes a day off rote work within a week.

> 🪟 **Windows contrast:** The closest Windows analogues are **DropIt** (folder watcher, free, XML rules) for Hazel's role and **AutoHotkey** (v2 scripting language, hotkeys, GUI automation) for Keyboard Maestro's role. AutoHotkey is more capable for low-level Win32 automation; Keyboard Maestro's action library is broader and GUI-configurable. DropIt is free but lacks Hazel's content-aware PDF matching, token-based renaming, Spotlight attribute conditions, and App Sweep integration. Neither Windows tool is a fair substitute for the depth these two macOS apps provide.

---

## Concepts

### Hazel: the folder-watching rule engine

Hazel is a System Preferences pane / menu bar daemon — **`HazelHelper`** runs as a persistent agent in your user session, registered via launchd (see `~/Library/LaunchAgents/com.noodlesoft.HazelHelper.plist`). It subscribes to `FSEvents` notifications for every folder you've added to its watch list. When the kernel reports a change to a watched path, Hazel evaluates each rule in order against every file or subfolder that changed; matching rules fire their action chains.

The event source is **FSEvents** (not kqueue), which means Hazel catches events even if the machine was asleep when a file was copied in — FSEvents persists its event stream to disk and replays it on wake.

#### The condition system

Rules are built from one or more **attribute conditions** combined with AND/ANY/NONE logic:

| Attribute category | Example conditions |
|---|---|
| **Name / extension** | name matches regex, extension is `pdf`, name starts with `IMG_` |
| **Date** | date added is before (today − 30 days), date last modified is in last week |
| **Kind** | kind is Image, kind is Application, kind is Folder |
| **Size** | size is greater than 50 MB |
| **Tags** | tags contain `to-process`, tags do not contain `filed` |
| **Contents / text** | contents contain "Invoice", contents match pattern `INV-\d{4}` |
| **Spotlight attributes** | `kMDItemCreator` is "Adobe Acrobat", `kMDItemAlbum` is not empty |
| **Color label** | color label is Orange |
| **Subfolder membership** | sub-folder depth is 0 (only act on top-level items) |
| **Custom metadata** | Hazel's own "Date Added to folder" attribute, independent of Finder metadata |

The **Contents** condition runs a full text extraction via PDFKit / Spotlight importers — you can match on text buried inside a PDF without a separate OCR step (though quality depends on the file being text-based, not scanned). For scanned PDFs use an OCR pre-pass (e.g., [[06-ocr-and-pdf-tools]] via ABBYY FineReader, Adobe Acrobat, or a "Run Shell Script" action that pipes through `tesseract`).

> 🔬 **Forensics note:** Hazel's condition evaluation order matters for triage. The cheapest conditions (name, extension) short-circuit early; contents matching is expensive and runs last. In forensic workflows, pre-filter by extension and date before running content matching to avoid unnecessary reads across large evidence folders.

#### The action system

Actions form a sequential chain; they execute in order and can be conditional. Core actions:

- **Move / Copy** — to a folder, optionally creating a subfolder hierarchy on the fly
- **Rename** — token-based (see below)
- **Add / Remove Tags**
- **Set Color Label**
- **Run Shell Script** — arbitrary Bash with `$1` = the file path; runs as your user; full PATH inherited from your shell
- **Run AppleScript / JavaScript for Automation** — `theFile` is passed as a POSIX path
- **Run Automator Workflow** — wraps an `.automatorworkflow` bundle
- **Run Shortcut** — Hazel 6 can hand off to a named Shortcut
- **Import into Photos / Music**
- **Upload** — SFTP, WebDAV, specific cloud services via plug-in
- **Sort into Subfolder** — the killer action: creates nested date, alpha, or pattern-based subfolders automatically
- **Notify** — sends a macOS notification
- **Reveal in Finder / Open**
- **Delete** / **Move to Trash**
- **Pass to Hazel Rule** — evaluate another rule's action chain directly (enables subroutine-style factoring)

#### Token-based renaming

The Rename action is where Hazel earns its keep on incoming documents. Tokens available:

```
{date added}          → 2026-06-13
{date created}        → varies; use for documents, not downloads
{date last modified}
{sequence}            → auto-incrementing counter per-folder
{extension}           → original extension, no dot
{file name}           → original base name
{custom text}         → literal string you type
{Spotlight attribute} → any kMDItem* you can name
```

You chain tokens with literal text: `{date added:YYYY-MM-DD}_{file name}.{extension}` turns `report.pdf` (added today) into `2026-06-13_report.pdf`. The date format string uses the same Unicode date format characters as `NSDateFormatter` / `strftime`-ish syntax — `YYYY` = 4-digit year, `MM` = zero-padded month, `dd` = zero-padded day, `HH:mm` = 24-hour time.

#### "Run rules on" scope and nested rules

At the top of each folder entry in Hazel's panel is the **"Run rules on"** dropdown — usually set to **"files and folders"** but can be scoped to just files or just immediate subfolders. This controls what kind of filesystem entry gets evaluated, not what actions touch.

**Nested conditions** let you nest condition groups with independent AND/ANY/NONE logic — useful when you need "extension is PDF AND (content contains 'Invoice' OR content contains 'Receipt')".

**Subfolder processing**: The "Process subfolders" action recursively descends into matched folders, applying the current ruleset to their children. This is how you build recursive filing pipelines: watch `~/Downloads/`, match `kind is folder`, then "Process subfolders" to catch files nested inside ZIP-extracted directories.

#### App Sweep (the uninstaller)

App Sweep is Hazel's built-in housekeeping feature, enabled in the **Trash** tab of Hazel preferences. When you move an application bundle to the Trash, Hazel scans for all related files — `~/Library/Application Support/<App>/`, `~/Library/Preferences/com.developer.AppName.plist`, `~/Library/Caches/com.developer.AppName/`, launch agents, container directories under `~/Library/Containers/` — and presents a dialog asking whether to sweep them too.

Under the hood it uses the `kMDItemCFBundleIdentifier` Spotlight attribute and the application's bundle ID to enumerate related files across the standard Library locations. It does **not** know about files an app stored outside Library conventions (e.g., `~/Documents/AppName/`); for those you need a manual check.

> 🔬 **Forensics note:** App Sweep's candidate list is a useful artifact inventory — it shows every Library location an app touched. Before accepting the sweep on a machine you're analyzing, capture the list (screenshot or copy to clipboard) — it maps the application's persistent footprint without you having to enumerate it manually.

---

### Keyboard Maestro: the macro runtime

Keyboard Maestro consists of two processes: **Keyboard Maestro** (the editor, a standard app at `/Applications/Keyboard Maestro.app`) and **Keyboard Maestro Engine** (`/Applications/Keyboard Maestro.app/Contents/MacOS/Keyboard Maestro Engine`), which runs as a login item and intercepts system-wide events.

The Engine registers event taps via the macOS Accessibility API and `CGEventTap` for hotkeys and typed-string triggers. It has NSWorkspace observers for app-lifecycle events, `FSEvents` subscriptions for folder triggers, and private APIs for USB device enumeration and network change notifications.

Macros live on disk at `~/Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.kmsync` — a SQLite-based binary bundle (since KM 11; older versions used an XML plist). **Crucially, `kmsync` is designed for iCloud Drive sync across machines**, unlike most application databases.

#### Triggers

A macro fires when any one of its triggers matches. The full trigger taxonomy:

| Trigger | Mechanism | Notes |
|---|---|---|
| **Hot Key** | `CGEventTap` | Can require modifier chord; distinguishes left/right modifiers |
| **Typed String** | `CGEventTap` key sequence matching | Type "@@email" → expands; case-sensitive or insensitive |
| **Application** | NSWorkspace notifications | Launch, quit, activate, deactivate, hide, unhide |
| **Time of Day / Cron** | launchd-derived scheduling | Fires at specific time, or on a cron-like interval |
| **System** | `IOKit` / NSWorkspace | Login, logout, wake, sleep, idle, screen lock/unlock |
| **USB Device** | `IOKit` `IOUSBDevice` enumeration | Specific vendor/product ID or name pattern |
| **Wireless Network** | `SCDynamicStore` network changes | Join / leave a named SSID |
| **File / Folder** | `FSEvents` | File appears, changes, or is deleted in a watched path |
| **Clipboard Changed** | Pasteboard observation | Fires whenever the clipboard contents change |
| **Window / Application Focus** | Accessibility API | Specific window title matches, focused app changes |
| **Remote Web Trigger** | HTTP endpoint at `http://localhost:4490/` | Allows remote machines, scripts, or webhooks to fire macros |
| **MIDI Note / Device** | `CoreMIDI` | Fire on any MIDI event — useful for macro pedals |
| **Dragged File** | Palette drop target | Drag a file onto a palette icon to process it |
| **Periodic** | Background timer | Every N minutes/hours — for polling or cleanup |

#### Actions

KM's action library has 300+ items across categories:

**Text & clipboard:**
- Insert text by typing / pasting / inserting (three distinct mechanisms; "type" goes through the CGEvent queue and respects the app's text engine; "paste" writes to clipboard and triggers Cmd-V; "insert" uses the Accessibility API's `AXValue` — fastest, but app must support it)
- Filter clipboard (uppercase, title case, strip HTML, JSON encode, URL encode, 30+ filters)
- Named clipboards — 25 named slots, each with full clipboard history
- Clipboard history switcher — built-in multi-clipboard viewer; default 200-entry history

**Application control:**
- Activate, quit, hide, launch, toggle application
- Set frontmost app's window bounds, full-screen toggle

**Window management:**
- Move / resize window to coordinates or screen percentage
- Move to next/previous display
- Tile: left half, right half, top-left quarter, etc. (KM's own tiling, independent of Stage Manager)

**Conditional & loop logic:**
- If/Then/Else (on variable, app, window title, clipboard, file existence, etc.)
- While / Until loops with iteration limit
- For Each (over lines in a variable, items in a KM dictionary, files from a glob)
- Try/Catch for error handling

**Script execution:**
- Execute Shell Script — runs `/bin/bash -l` or any specified shell; return value available as `%LastAction%` or a named variable
- Execute AppleScript / JavaScript for Automation
- Execute JavaScript in Browser (Chrome, Safari, Firefox) via browser extension
- Execute Swift / Python / Ruby / Perl script

**Variables:**
KM has three variable scopes: **global** (persist across macro runs), **instance** (scoped to a single macro invocation), and **local** (scoped to a called subroutine). Variable names are free-form text; access them with `%Variable%Name%` syntax inside any text field. There are also built-in computed variables: `%TriggerValue%`, `%CurrentApplication%`, `%CurrentClipboard%`, `%ICUDateTime%` (current date/time in ICU format).

**Dictionaries:** KM 11 added first-class dictionary support — JSON-compatible key/value maps that can be serialized, passed between macros, and iterated with For Each. This makes KM viable for light data-processing tasks that previously required a shell script.

#### Macro groups and per-app scoping

Macros are organized into **Macro Groups**, which act as namespaces with activation policies:

- **Global** — always active, all apps
- **Application-specific** — active only when listed apps are frontmost; macros in these groups shadow or supplement global macros for that app
- **Exclusive application** — active ONLY in listed apps, replacing global groups for those apps
- **Palette** — always displayed as a floating clickable palette (good for rarely-typed actions)
- **Activated for one action** — hotkey shows the group's macros; one keypress fires one macro; palette dismisses

Groups can be toggled with their own hotkey or via a status menu item. This lets you build context-aware automation layers: one group for Finder, another for your editor, another for your terminal emulator.

#### The Conflict Palette

When multiple macros share the same trigger (e.g., both "Process file" and "Archive file" are bound to `⌃⌥⌘P`), KM intercepts the event and shows the **Conflict Palette** — a floating popup listing all matching macros. Press the highlighted letter or number to select. You can filter the list by typing partial macro names. This is the intended design pattern for "disambiguation menus" — deliberately bind a family of related macros to one chord, then let the Conflict Palette be your menu.

> 🔬 **Forensics note:** KM Engine's activity is logged to `~/Library/Logs/Keyboard Maestro/`. Each macro execution generates a timestamped log line with macro name and trigger. This log is invaluable when auditing what automation ran on a machine — if a macro was used to automate data exfiltration (e.g., moving files to an external drive on USB-device trigger), the log captures it.

#### Comparing the tool stack

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer          │ Tool                │ Trigger source               │
├────────────────┼─────────────────────┼──────────────────────────────┤
│ File events    │ Hazel               │ FSEvents on watched folders  │
│ Input / macros │ Keyboard Maestro    │ CGEventTap, NSWorkspace, etc │
│ Human-crafted  │ Shortcuts           │ Manual, Siri, Action button  │
│ Timed jobs     │ launchd             │ Calendar, boot, interval     │
│ App scripting  │ Automator           │ Manual / folder action hook  │
│ Gesture layer  │ BetterTouchTool     │ Trackpad gestures, haptics   │
└────────────────┴─────────────────────┴──────────────────────────────┘
```

**Hazel vs. Shortcuts for files:** Shortcuts can process files, but it requires you to kick it off. Hazel is reactive — rules fire the moment a file appears, without human involvement, even when your machine is headless. Use Shortcuts for deliberate, interactive workflows; use Hazel for "always-on" filing.

**KM vs. Shortcuts for macros:** Shortcuts has tighter system integration (Focus filters, AirDrop, iOS/iPadOS cross-device), but KM's trigger types, conditional logic, and browser JavaScript execution are deeper. KM is the right choice for anything that requires: typed string expansion, per-app macro scoping, clipboard history, complex branching, or running scripts and using their output in subsequent actions.

**KM + Hazel together:** They combine elegantly. A Hazel rule can "Run Shell Script" that pipes a file path to a KM remote trigger URL (`curl -s http://localhost:4490/action.html?macro=Process+PDF+File&value=/path/to/file`), invoking a KM macro that performs UI automation Hazel cannot (e.g., opening the file in a specific app window, running a menu command, then saving to a different location).

**BetterTouchTool:** The complementary third tool. BTT owns the gesture layer — trackpad gestures, Magic Mouse swipes, Force Touch, touch bar, window snapping with pixel-precise zones, and a floating HUD. It overlaps KM on hotkeys and typed strings, but its depth is in input devices. The typical power-user stack is all three: Hazel for files, KM for macros and text, BTT for gestures and windows.

---

## Hands-on (CLI & GUI)

### Hazel: inspecting the watch list and rules from the command line

Hazel's rules are stored in `~/Library/Application Support/Hazel/Rules/` as per-folder plist bundles:

```bash
# List all folders Hazel is watching
ls -1 ~/Library/Application\ Support/Hazel/Rules/

# Read the rules for a specific folder (UUID-named bundle)
# First find which UUID maps to Downloads:
plutil -p ~/Library/Application\ Support/Hazel/Rules/*/Info.plist 2>/dev/null | grep -A1 Downloads

# Dump all rules in that bundle:
plutil -p ~/Library/Application\ Support/Hazel/Rules/<UUID>/Rules.plist
```

Hazel's helper process:

```bash
# See the running helper
pgrep -lf HazelHelper

# Restart Hazel (flushes FSEvents backlog, re-evaluates all rules):
launchctl bootout gui/$(id -u) com.noodlesoft.HazelHelper \
  && launchctl bootstrap gui/$(id -u) \
       ~/Library/LaunchAgents/com.noodlesoft.HazelHelper.plist
```

### Keyboard Maestro: CLI interaction

The KM Engine exposes an `osascript`-accessible interface and a local HTTP API:

```bash
# Fire a named macro from the command line:
osascript -e 'tell application "Keyboard Maestro Engine" to do script "My Macro Name"'

# Fire via HTTP remote trigger (macro must have "Remote Trigger" trigger enabled):
curl -s "http://localhost:4490/action.html?macro=My+Macro+Name&value=SomePayload"

# Read a KM global variable:
osascript -e 'tell application "Keyboard Maestro Engine" to get value of variable "MyVariable"'

# Set a KM global variable from a shell script (useful inside Hazel rules):
osascript -e 'tell application "Keyboard Maestro Engine" to setvariable "LastProcessedFile" to "/path/to/file.pdf"'
```

List macros with their UUIDs (useful for scripting):

```bash
plutil -p ~/Library/Application\ Support/Keyboard\ Maestro/Keyboard\ Maestro\ Macros.kmsync \
  | grep -E '"name"|"uuid"' | head -40
```

Export a specific macro group as an importable `.kmmacros` archive via the editor: right-click the group → Export. The format is a gzipped plist — inspect it with `plutil -p <file>.kmmacros`.

---

## Labs

### Lab 1 — Hazel: auto-sort Downloads by type

**Goal:** Files landing in `~/Downloads` are automatically sorted into type-based subfolders (`PDFs/`, `Images/`, `Archives/`, `Apps/`, `Docs/`). After 60 days, anything not yet sorted (matched no rule) gets tagged "stale" and moved to `~/Downloads/Old/`.

> ⚠️ **Before starting:** Open Terminal and run:
> ```bash
> cp -R ~/Downloads ~/Downloads.backup.$(date +%Y%m%d)
> ```
> To roll back: `rm -rf ~/Downloads && mv ~/Downloads.backup.<date> ~/Downloads`.

**Steps:**

1. Open **System Settings → Hazel** (or click the Hazel menu bar icon → Open Hazel).
2. Click **+** in the folder list → add `~/Downloads`.
3. Click **+** below the rules list to create the first rule. Name it `Sort PDFs`.
4. Set conditions: **Extension** | **is** | `pdf`
5. Set action: **Move** → `~/Downloads/PDFs/` (check "Create folder if it doesn't exist")
6. Add a second action: **Add Tags** → `filed`
7. Click **OK**. Repeat for:

| Rule name | Condition | Destination |
|---|---|---|
| Sort Images | Kind | is | Image | `~/Downloads/Images/` |
| Sort Archives | Extension | is one of | zip, tar, gz, 7z, rar | `~/Downloads/Archives/` |
| Sort Apps | Kind | is | Application | `~/Downloads/Apps/` |
| Sort Office Docs | Extension | is one of | docx, xlsx, pptx, pages, numbers | `~/Downloads/Docs/` |

8. Create a final rule `Stale Cleanup`:
   - Condition 1: **Date Added to Folder** | **is before** | `60 days ago`
   - Condition 2: **Tags** | **do not contain** | `filed`
   - Action 1: **Add Tags** → `stale`
   - Action 2: **Move** → `~/Downloads/Old/`

9. Verify: drop a PDF into `~/Downloads`. Within a few seconds Hazel should move it to `~/Downloads/PDFs/` and tag it `filed`. Check with:
   ```bash
   ls ~/Downloads/PDFs/
   mdls -name kMDItemUserTags ~/Downloads/PDFs/*.pdf | head
   ```

**How it works under the hood:** HazelHelper received an FSEvents notification for `~/Downloads`, evaluated each rule top-to-bottom against the new file, hit the `Sort PDFs` condition match, executed the Move + Tag action chain, and stopped (Hazel does not continue evaluating further rules on a file once a Move action runs, because the file is now in a different folder and no longer in scope).

---

### Lab 2 — Hazel: smart screenshot archiver with rename

**Goal:** Every screenshot macOS saves to `~/Desktop` gets renamed to `screenshot-YYYY-MM-DD-HH-mm.png`, tagged `screenshot`, and moved to `~/Pictures/Screenshots/`.

macOS names screenshots `Screenshot YYYY-MM-DD at HH.MM.SS.png` — Hazel conditions:
- **Name** | **starts with** | `Screenshot `
- **Extension** | **is** | `png`
- **Date Added** | **is in the last** | `1 minute` (prevent re-processing if the rule is re-evaluated)

Actions:
1. **Rename** with pattern: `screenshot-{date added:yyyy-MM-dd-HH-mm}.{extension}`
2. **Add Tags** → `screenshot`
3. **Move** → `~/Pictures/Screenshots/`

Take a screenshot (`⇧⌘3`) and watch the Desktop — the file should vanish and reappear in `~/Pictures/Screenshots/` with the new name.

---

### Lab 3 — Keyboard Maestro: multi-step "paste as plain text + reformat" macro

**Goal:** A single hotkey strips all formatting from the clipboard, title-cases the text, and types it into the frontmost field. This replaces the inconsistent "Paste and Match Style" behavior across apps.

> ⚠️ This macro writes to your clipboard. Your current clipboard content will be overwritten. If you care, copy it elsewhere first.

1. Open **Keyboard Maestro** → click **+** to create a new macro. Name it `Paste Plain Title Case`.
2. Add a **Hot Key trigger**: `⌃⌥⌘V` (Control-Option-Command-V, unlikely to conflict).
3. Add action **Filter Clipboard** → choose **Paste from Clipboard → Strip Style** (this removes RTF/HTML formatting and leaves plain text).
4. Add action **Filter Clipboard** → **Title Case** (KM has a built-in title case filter).
5. Add action **Type a Keystroke** → `⌘V` (paste the filtered clipboard).
6. Click **Enable Macro**.

Test: Copy some bold/colored text from a webpage, focus a TextEdit document, press `⌃⌥⌘V`. The text should paste as plain unstyled title-cased text.

---

### Lab 4 — Keyboard Maestro: per-app macro group for Finder

**Goal:** In Finder only, `⌃⌥C` copies the full POSIX path of the selected file to the clipboard.

1. Create a new **Macro Group** (click the **+** at the bottom of the group list). Name it `Finder Extras`.
2. Set activation: **Available in these applications** → add **Finder**.
3. Inside the group, create a macro `Copy Path`.
4. **Hot Key trigger**: `⌃⌥C`.
5. **Action — Execute Shell Script**:
   ```bash
   osascript -e 'tell application "Finder" to get POSIX path of (target of front Finder window as alias)' | tr -d '\n'
   ```
   Set **Save to** → **Clipboard**.
6. **Action — Display Brief Notification**: "Path copied to clipboard".
7. Enable the macro.

In Finder, navigate to any folder, press `⌃⌥C`, then paste elsewhere — you get the full path like `/Users/bronty13/Downloads/report.pdf`.

> 🪟 **Windows contrast:** AutoHotkey achieves this with `WinActive("ahk_class CabinetWClass")` to scope the hotkey to Explorer windows, then `Clipboard := RegExReplace(...)` to set the clipboard. The KM approach is more GUI-configurable but AutoHotkey's conditional scoping via `#IfWinActive` is more precise when multiple window classes share a process.

---

### Lab 5 — Hazel + KM cross-invocation

**Goal:** When a PDF arrives in `~/Downloads/Invoices/`, Hazel fires a KM macro that opens it in Preview, waits 2 seconds, and uses the Accessibility API to trigger File → Print → Save as PDF to a filing location.

Hazel rule on `~/Downloads/Invoices/`:
- Condition: **Extension** is `pdf`
- Action: **Run Shell Script**:
  ```bash
  curl -s "http://localhost:4490/action.html?macro=Process+Invoice+PDF&value=$1"
  ```

In KM, create macro `Process Invoice PDF` with a **Remote Web Trigger**. Actions:
1. **Set Variable** `InvoicePath` to `%TriggerValue%`
2. **Execute Shell Script**: `open -a Preview "%Variable%InvoicePath%"`
3. **Pause** 2 seconds
4. **Activate application**: Preview
5. **Select Menu Item**: File → Print (`⌘P`)
6. (Additional actions for PDF dialog as needed)

This pattern — Hazel detects file, KM performs UI automation — handles cases where pure shell scripting cannot interact with graphical dialogs.

---

## Pitfalls & gotchas

**Hazel rule ordering is first-match-wins for Move actions.** Once a Move runs, the file is no longer in the watched folder; subsequent rules in the same folder never see it. Order your rules from most-specific to most-general.

**Hazel's "Date Added to Folder" attribute is not `kMDItemDateAdded`.** It's a Hazel-internal timestamp set when the file first appears in the watched folder — it does NOT update if you copy the file from another Hazel-watched folder. This is a frequent source of "why did this rule not fire?" confusion.

**Hazel does not evaluate rules retroactively on existing files unless you right-click a folder → "Run rules now".** New rules only fire on new events. If you add a rule and expect it to process thousands of existing files, use "Run rules now" — but test on a small sample first with "Do not move originals" or a dry-run Copy action.

**Keyboard Maestro Engine must have Accessibility permission.** System Settings → Privacy & Security → Accessibility → Keyboard Maestro Engine must be listed and enabled. Without it, hotkey triggers that require CGEventTap may fire intermittently or not at all. After a macOS upgrade, re-check this.

**Typed string triggers have a cooldown.** If you type a string trigger accidentally inside another application, KM fires and may corrupt a document. Set typed string triggers to require a specific delimiter (e.g., `;` prefix: `;@@addr`) or use the "only in these applications" scoping to prevent misfires.

**KM macros that use AppleScript or the Accessibility API can break after macOS updates** because app bundle structures, menu item names, and AX element hierarchies change. If a macro silently stops working after an update, open the KM action log (`~/Library/Logs/Keyboard Maestro/Engine.log`) to see what error the AppleScript or AX action returned.

**Conflict Palette UX:** If you deliberately build conflict-palette disambiguation menus, the palette position defaults to under the cursor, which can be surprising. Set the palette to appear at a fixed screen position in KM preferences if you prefer predictability.

**Hazel + iCloud Drive folders:** Watching `~/Library/Mobile Documents/` (where iCloud Drive files actually live) with Hazel is supported but be aware that iCloud can briefly make files unavailable (evicted to the cloud) — a rule that runs a shell script on an evicted file may fail because the file handle is not locally present. Add a condition **Contents** → **is available** (Hazel 6 attribute) or pre-empt with a `brctl download "$1"` shell action.

> 🔬 **Forensics note:** Hazel's action history is available in its UI (Hazel menu bar → Show History) and as a SQLite database at `~/Library/Application Support/Hazel/History.db`. Tables: `movedItems`, `renamedItems`, `deletedItems`, each with timestamps and source/destination paths. This is a gold mine on a machine under investigation — it shows every file Hazel moved, renamed, or deleted, with timestamps and destination paths, even if the files are now gone.

---

## Key takeaways

- Hazel is a **persistent FSEvents consumer** operating in user space; it watches folders and fires rule chains on file events, even across sleep cycles.
- Conditions cascade from cheap (name/extension) to expensive (contents search); order them to short-circuit early.
- Token-based rename + "Sort into Subfolder" + shell script actions cover the vast majority of filing automation; the Hazel + KM HTTP trigger bridge extends coverage to GUI automation.
- App Sweep uses bundle IDs and standard Library paths to enumerate an application's full on-disk footprint — a useful uninstall or forensic inventory tool.
- Keyboard Maestro's Engine intercepts input events via `CGEventTap` before applications see them; its 30+ trigger types cover virtually every system event.
- Macro Groups provide per-app scoping; the Conflict Palette turns intentional trigger collisions into disambiguation menus.
- KM's clipboard history, named clipboards, and Filter Clipboard actions form a complete multi-clipboard workflow that replaces third-party clipboard managers.
- The full power-user automation stack is layered: **Hazel** (files) + **Keyboard Maestro** (macros/input) + **BetterTouchTool** (gestures/windows) + **Shortcuts** (system integration/Siri/cross-device).

---

## Terms introduced

| Term | Definition |
|---|---|
| FSEvents | macOS kernel facility that notifies user-space processes of filesystem changes; persists to disk across sleep |
| HazelHelper | The persistent launchd-registered user agent that evaluates Hazel rules on FSEvents notifications |
| Attribute condition | A Hazel rule clause that tests a file's metadata property (name, date, Spotlight attribute, etc.) |
| Token | A placeholder in a Hazel rename pattern (e.g., `{date added}`) that expands to a file's metadata value |
| App Sweep | Hazel's bundled uninstaller feature that enumerates and optionally removes application support files when an app is trashed |
| CGEventTap | macOS API that allows a process to intercept and optionally modify input events before they reach the target application |
| Macro Group | A KM container that defines when and where its member macros are active (global, per-app, palette) |
| Conflict Palette | KM popup when multiple macros share a trigger; lets the user select which one to fire |
| Remote Trigger | KM's local HTTP endpoint (`localhost:4490`) that allows external scripts and tools to fire macros |
| Named Clipboard | One of KM's 25 persistent named clipboard slots, each with its own history independent of the system clipboard |
| kmsync | Keyboard Maestro's SQLite-based macro storage format (introduced KM 11), designed for iCloud Drive sync |

---

## Further reading

- [Noodlesoft Hazel manual](https://www.noodlesoft.com/manual/hazel/) — official docs covering all conditions, actions, tokens, and advanced topics
- [Keyboard Maestro Wiki](https://wiki.keyboardmaestro.com/) — full action reference, trigger documentation, and macro examples
- [Keyboard Maestro 11 PDF manual](https://files.stairways.com/manual/11/keyboardmaestro.pdf) — downloadable offline reference
- [Asian Efficiency's KM guide](https://www.asianefficiency.com/technology/keyboard-maestro/) — opinionated workflow patterns from heavy users
- [ThoughtAsylum: KM Macro Groups deep dive](https://www.thoughtasylum.com/2026/03/31/keyboard-maestro-macro-groups/) — scoping nuances and activation patterns
- [[02-launchd-and-cron]] — launchd internals that underpin Hazel's scheduling model
- [[03-shortcuts-and-automator]] — where Shortcuts fits relative to Hazel and KM
- [[06-ocr-and-pdf-tools]] — OCR pre-processing to feed Hazel's content-matching conditions
- Howard Oakley's Eclectic Light Company articles on FSEvents — deep kernel-level background on the event infrastructure Hazel depends on
