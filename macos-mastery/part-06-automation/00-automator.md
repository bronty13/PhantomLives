---
title: Automator — No-Code Glue Layer for macOS
part: P06 Automation
est_time: 50 min read + 60 min labs
prerequisites: [03-cli/11-scripting, 03-cli/04-macos-specific-cli-tools]
tags: [macos, automation, automator, quick-action, folder-action, services, shell-script, applescript]
---

# Automator — No-Code Glue Layer for macOS

> **In one sentence:** Automator is macOS's built-in visual automation builder that composes system actions into reusable workflows — spanning eight distinct deployment modes — and serves as the critical bridge between the shell, AppleScript/JavaScript, and the GUI layer, with a still-expanding role as the fallback for Shortcuts gaps.

## Why this matters

Shortcuts is the long-term direction, but Automator is alive and essential today. No single new Automator action has shipped from Apple since 2021, yet the tool remains the *only* first-party way to:

- Inject a custom item into Finder's right-click contextual menu without writing a native plugin
- Attach an automation to a folder that fires when files land in it (the *old* way; Shortcuts in macOS 26 Tahoe now also supports folder triggers, but Automator workflows run more reliably with complex shell pipelines)
- Create a self-contained `.app` droplet that receives dragged files via the Dock or Finder

For a forensics professional and builder, Automator is your glue layer: wrap arbitrary shell commands in a GUI-accessible action, embed them in Finder's context menu, and ship them as standalone apps — all without a developer account or Xcode.

> 🪟 **Windows contrast:** Power Automate Desktop (née WinAutomation) is the closest analog, but it requires a Microsoft 365 subscription for full capability and targets IT-level RPA. Automator ships free in every macOS install, wires into the OS at a kernel-adjacent level (via the Services mechanism and `com.apple.automator.*` CoreServices registrations), and has no "Pro" tier. Task Scheduler covers the cron-like scheduling angle but has no equivalent to folder actions or contextual menu injection without COM scripting.

---

## Concepts

### The eight document types

When you choose **File → New** in Automator, you pick a *document type*. This is not cosmetic; it determines where the workflow is saved, how it is invoked, and what data it receives at runtime.

| Type | On-disk location | Extension | Invocation |
|------|-----------------|-----------|------------|
| **Workflow** | Anywhere you choose | `.workflow` | Open in Automator, click Run; or via `automator` CLI |
| **Application** (Droplet) | Anywhere you deploy it | `.app` | Launch like any app; drag files onto its Dock icon |
| **Quick Action** | `~/Library/Services/` | `.workflow` | Finder right-click → Quick Actions; Services menu; keyboard shortcut |
| **Folder Action** | `~/Library/Workflows/Applications/Folder Actions/` | `.workflow` | Automatically when files are added to the attached folder |
| **Print Plugin** | `~/Library/PDF Services/` | `.workflow` | PDF drop-down in the Print dialog |
| **Calendar Alarm** | `~/Library/Workflows/Applications/Calendar/` | `.workflow` | A Calendar event fires the workflow at a scheduled time |
| **Image Capture Plugin** | `~/Library/Workflows/Applications/Image Capture/` | `.workflow` | In Image Capture when importing from a camera/scanner |
| **Dictation Command** | System managed | — | Voice trigger (deprecated; superseded by Siri Shortcuts) |

The `.workflow` package is a bundle directory: `Contents/document.wflow` holds the action graph as a binary plist; `Contents/Info.plist` declares the type, inputs, and outputs.

```
MyAction.workflow/
└── Contents/
    ├── Info.plist        # AMDocumentType, AMInputTypeList, etc.
    └── document.wflow    # binary plist — the action graph
```

Convert `document.wflow` to human-readable XML with:

```bash
plutil -convert xml1 -o - ~/Library/Services/MyAction.workflow/Contents/document.wflow | less
```

> 🔬 **Forensics note:** Installed Quick Actions and Folder Actions leave persistent artifacts under `~/Library/Services/` and `~/Library/Workflows/`. The `document.wflow` plist names every action in the graph including any embedded shell commands or AppleScript — a productive place to look when investigating automated exfiltration or persistence mechanisms that use Automator as a carrier. Folder Action scripts are also registered in `~/Library/Preferences/com.apple.FolderActionsDispatcher.plist`.

### How the action data pipeline works

Automator workflows are *dataflow pipelines*: each action receives the output of the previous action as its input, transforms it, and passes the result downstream. The data is typed — Files/Folders, Text, Images, Rich Text, URLs, Numbers — and Automator enforces type compatibility (mismatches show a yellow warning connector).

```
[Get Finder Selection]        → Files/Folders
        ↓
[Filter Finder Items]         → Files/Folders (subset)
        ↓
[Scale Images]                → Files/Folders (modified in place)
        ↓
[Copy to Folder]              → Files/Folders (copies)
        ↓
[Reveal in Finder]
```

The pipeline can be broken and rejoined with **control flow actions**: `If → Then`, `Repeat`, `Combine Text`, `Set Value of Variable`, and `Get Value of Variable`. Variables act as named side-channels that hold a snapshot of the pipeline at a point in time, allowing later actions to re-inject it. This matters when a shell script action needs both the current file path *and* a user-configured parameter stored earlier.

### The "Run Shell Script" action — the escape hatch

"Run Shell Script" is the single most important action in Automator. It executes arbitrary shell code using any interpreter available on the system (`/bin/bash`, `/bin/zsh`, `/usr/bin/python3`, `/usr/bin/perl`, `/usr/bin/ruby`).

The **"Pass input" pop-up** controls how the upstream pipeline feeds the script:

| Mode | What the script receives | When to use |
|------|--------------------------|-------------|
| **as arguments** | Each pipeline item becomes `$1`, `$2`, … `$N` (iterate with `for f in "$@"`) | File paths, discrete values — anything where word-splitting matters |
| **to stdin** | All input is written to the script's standard input as a newline-separated stream | Text processing with `awk`, `grep`, `jq`; single concatenated blobs |

Critical behavioral differences:

```bash
# "as arguments" — iterate safely over file paths with spaces:
for f in "$@"; do
    sips --resampleHeightWidthMax 1920 "$f"
done

# "to stdin" — classic piped text processing:
grep -E '^ERROR' | sort | uniq -c | sort -rn
```

The action's **stdout** becomes the pipeline output for the next action. If your script emits newline-separated file paths, the downstream action receives a list of files. If it emits nothing (only side effects), the pipeline stalls — pass `"$@"` through at the end if you want the original files to continue downstream.

Shell scripts in Automator run with a minimal environment: `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`, not your interactive shell's `PATH`. Reference tools by full path or prepend PATH manually:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
```

> 🔬 **Forensics note:** Embedded shell scripts inside `.workflow` files execute with the invoking user's privileges but the restricted PATH. If you find a Folder Action with a `curl` or `osascript` call using full paths, that's intentional evasion of PATH-based detection.

### "Run AppleScript" and "Run JavaScript for Automation" (JXA)

The **Run AppleScript** action exposes the full OSA scripting bridge: UI scripting via `System Events`, application dictionaries, inter-app communication. The `input` variable holds the pipeline data as an AppleScript list:

```applescript
on run {input, parameters}
    set theFiles to input
    repeat with f in theFiles
        set fPath to POSIX path of f
        -- do something with fPath
    end repeat
    return input  -- pass through
end run
```

**Run JavaScript for Automation** (JXA, `com.apple.JavaScriptOSA`) uses the same OSA bridge with JavaScript syntax. It is strictly better for text manipulation and JSON wrangling because you have full ES6+ and `JSON.parse`/`JSON.stringify` available — but application dictionary coverage is thinner than AppleScript for older apps.

```javascript
function run(input, parameters) {
    return input.map(f => {
        let path = f.toString();
        return path.replace(/\.HEIC$/i, '.jpg');
    });
}
```

### Quick Actions — Finder integration

A Quick Action saved to `~/Library/Services/` is registered with the macOS Services architecture (`/System/Library/CoreServices/pbs` — the "paste board server" which doubles as Services broker). Registration happens automatically on save; you can force a refresh:

```bash
/System/Library/CoreServices/pbs -flush
```

Quick Actions appear in three surfaces:

1. **Finder right-click → Quick Actions** (contextual menu at bottom of the list)
2. **Application menu → Services** (in virtually any Cocoa app)
3. **Touch Bar** (on supported hardware, when the "Use in Touch Bar" checkbox is enabled in the workflow's Options pane)

The action's scope is controlled by "Receives current" (Files/Folders, Text, Images, PDFs, etc.) and "in" (Finder, any application). A text-processing Quick Action that declares `Receives: Text` in `any application` appears in the Services menu of TextEdit, Safari, Notes, and your IDE simultaneously.

**Binding a keyboard shortcut:**

System Settings → Keyboard → Keyboard Shortcuts → Services → find your action → double-click in the shortcut column. The binding is stored in `~/Library/Preferences/com.apple.symbolichotkeys.plist` under the key matching the service name.

### Folder Actions — filesystem event triggers

Folder Actions are powered by the `com.apple.FolderActionsDispatcher` daemon, which subscribes to FSEvents (`/dev/fsevents` stream) on the attached directories. When a file is *added* to a watched folder, the dispatcher fires the attached workflows with the list of new items.

Important behavioral facts:
- The trigger is **file addition only** — modification and deletion do not fire the action.
- The daemon runs as the user. It restarts automatically; it is registered in `~/Library/LaunchAgents/com.apple.FolderActionsDispatcher.plist`.
- You can attach *multiple* workflows to a single folder, and one workflow to *multiple* folders.

Manage Folder Actions via:
- **Right-click a folder → Folder Actions Setup…** (GUI)
- **Automator → File → New → Folder Action** (authoring)
- `~/Library/Preferences/com.apple.FolderActionsDispatcher.plist` (inspect the registered mapping)

```bash
# See which folders have actions attached:
defaults read ~/Library/Preferences/com.apple.FolderActionsDispatcher.plist
```

> 🔬 **Forensics note:** Malicious persistence via Folder Action is a known macOS technique (MITRE ATT&CK T1546.013). The dispatcher plist is a reliable artifact. KnockKnock and BlockBlock both flag unusual Folder Action registrations. To enumerate all registered folder actions on a live system:
> ```bash
> osascript -e 'tell application "System Events" to get folder actions'
> ```

### Saving as a Droplet (Application type)

A Droplet is a `.app` bundle that behaves like any macOS application but whose "main" code is the Automator workflow. When you drag files onto its Dock icon or double-click it, it opens and runs. The internal structure is a standard macOS app embedding the workflow:

```
MyDroplet.app/
├── Contents/
│   ├── MacOS/Automator Application Stub  (universal binary loader)
│   ├── Info.plist
│   └── Resources/
│       └── document.wflow               (your workflow)
```

Droplets are ideal for distributing a workflow to a teammate who doesn't know Automator — they just drag files on. You can notarize them with `notarytool` if distribution beyond your own machines is needed.

### Automator and Shortcuts: the migration picture

Apple froze Automator feature development after macOS Monterey. Shortcuts is the stated successor, but the migration is partial:

| Capability | Automator | Shortcuts |
|------------|-----------|-----------|
| Quick Actions / contextual menu | Yes | Yes (macOS 13+) |
| Folder triggers (filesystem events) | Yes | Yes (macOS 26 Tahoe, new) |
| Droplet apps | Yes (`.app`) | No |
| Print Plugin | Yes | No |
| Calendar Alarm | Yes | Partially (run a Shortcut from Calendar) |
| Run arbitrary shell script | Yes — first-class action | Yes — `Run Shell Script` action |
| Run AppleScript / JXA | Yes | Run AppleScript (no JXA) |
| iOS/iPadOS parity | No | Yes |
| Inter-device (Handoff) | No | Yes |

**Importing into Shortcuts:** drag a `.workflow` file into the Shortcuts window, or double-click it and choose Open with Shortcuts. Most action types convert cleanly. Unsupported actions (some Finder-specific and third-party actions) surface an alert listing what was skipped. The conversion is non-destructive — the original `.workflow` is untouched.

**Rule of thumb:** use Shortcuts for new work that needs mobile parity, scheduling, or Focus/Automation triggers. Keep or build in Automator when you need a Droplet, a Print Plugin, complex shell pipeline integration, or when testing confirms the Shortcuts equivalent is flaky.

---

## Hands-on (CLI & GUI)

### The `automator` command-line runner

Automator workflows are first-class CLI citizens:

```bash
# Run a workflow file directly:
automator /path/to/MyWorkflow.workflow

# Pass input (files) to the workflow:
automator -i /path/to/file1.jpg /path/to/file2.jpg /path/to/MyWorkflow.workflow

# Run with verbose output (useful for debugging):
automator -v /path/to/MyWorkflow.workflow

# The exit code is 0 on success, non-zero on any action error
```

This enables you to call Automator workflows from launchd agents, cron jobs, or shell scripts — effectively using the GUI-built workflow as a callable function.

### Inspecting installed workflows

```bash
# List all Quick Actions:
ls ~/Library/Services/*.workflow

# Decode the action graph of a Quick Action:
plutil -convert xml1 -o - \
  ~/Library/Services/MyAction.workflow/Contents/document.wflow \
  | grep -A2 'AMActionClass\|AMShellScript'

# List all Folder Action workflows:
ls "~/Library/Workflows/Applications/Folder Actions/"

# Check which folders have actions registered:
defaults read ~/Library/Preferences/com.apple.FolderActionsDispatcher.plist \
  | grep -E 'path|workflow'
```

### Building a Quick Action (step by step)

1. Open Automator → File → New → **Quick Action**
2. Set "Workflow receives current" to **image files** in **Finder**
3. Add action: **Photos → Scale Images** — set max dimension, e.g. 1920 px
4. (Optional) Add **Files & Folders → Move Finder Items** to copy to a `Resized/` subfolder
5. Check **Options → "Show this action when the workflow runs"** if you want a live parameter dialog
6. File → Save → name it "Resize Images (1920px)" — it lands in `~/Library/Services/`
7. Immediately right-click an image in Finder — it appears under **Quick Actions**

To set a keyboard shortcut: System Settings → Keyboard → Keyboard Shortcuts → Services → scroll to "General" or "Files and Folders" section → find "Resize Images (1920px)" → double-click the shortcut column.

### Folder Action for HEIC → JPEG conversion

The `sips` (Scriptable Image Processing System) command ships with macOS and can transcode HEIC to JPEG without any third-party tool:

```bash
sips -s format jpeg input.HEIC --out output.jpg
```

In Automator:
1. File → New → **Folder Action**
2. In the "Folder Action receives files and folders added to:" drop-down at the top, select your target folder (e.g. `~/Downloads/HEIC-drop/`)
3. Add action: **Utilities → Run Shell Script**
4. Set "Pass input": **as arguments**
5. Paste:

```bash
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

for f in "$@"; do
    # Only process HEIC/HEIF files
    case "${f##*.}" in
        HEIC|heic|HEIF|heif)
            outdir="$(dirname "$f")/converted"
            mkdir -p "$outdir"
            base="$(basename "${f%.*}")"
            sips -s format jpeg "$f" --out "$outdir/${base}.jpg" 2>&1
            ;;
    esac
done
```

6. Save as "HEIC to JPEG"
7. Create `~/Downloads/HEIC-drop/` if it doesn't exist
8. Right-click the folder → **Folder Actions Setup…** → verify the workflow is listed and enabled

Drop an `.HEIC` file in — within a second or two, a `converted/` subfolder appears with the `.jpg` output.

### Building a Droplet that runs a shell script

Use case: a drag-onto-app that extracts EXIF metadata from dropped files and writes a report.

1. File → New → **Application**
2. Add **Utilities → Run Shell Script** — "Pass input: as arguments"
3. Paste:

```bash
export PATH="/usr/bin:/bin:/opt/homebrew/bin"
OUT="$HOME/Downloads/exif-report-$(date +%Y%m%d-%H%M%S).txt"

echo "EXIF Report — $(date)" > "$OUT"
echo "=====================" >> "$OUT"

for f in "$@"; do
    echo "" >> "$OUT"
    echo "--- $f ---" >> "$OUT"
    if command -v exiftool >/dev/null 2>&1; then
        exiftool "$f" >> "$OUT" 2>&1
    else
        mdls "$f" >> "$OUT" 2>&1
    fi
done

open "$OUT"
```

4. File → Save As… → name it "EXIF Extractor.app" — save to `~/Applications/` or your Desktop
5. Drag image files onto it from Finder; the report opens in TextEdit

For production use, expand to use `exiftool` (install via `brew install exiftool`). The fallback to `mdls` ensures the droplet works even without Homebrew.

---

## 🧪 Labs

### Lab 1 — Build and wire a "Resize Images" Quick Action

**Goal:** a right-click action that resizes selected images in-place and reports the count.

**Prerequisites:** Any image files for testing. No admin rights needed.

1. Open Automator → Quick Action. Set input to **image files** in **Finder**.
2. Add **Photos → Scale Images** → 1920 pixels (long edge). Check "Scale down only."
3. Add **Utilities → Run Shell Script** — stdin mode:
   ```bash
   count=$(wc -l < /dev/stdin)
   osascript -e "display notification \"Resized $count image(s)\" with title \"Automator\""
   ```
   Wait — this won't work because stdin at this point is file paths, not a count. Fix it:
   Set "Pass input: as arguments" instead, then:
   ```bash
   count=$#
   osascript -e "display notification \"Resized $count image(s)\" with title \"Resize Images\""
   # Pass files through
   for f in "$@"; do printf '%s\n' "$f"; done
   ```
4. Save as "Resize Images 1920."
5. Test: right-click 2 or 3 JPEG files in Finder → Quick Actions → Resize Images 1920.
6. Verify the notification fires and the image dimensions changed (`sips -g pixelWidth -g pixelHeight yourimage.jpg`).
7. Bind a keyboard shortcut: System Settings → Keyboard → Keyboard Shortcuts → Services.

**Roll back:** Delete `~/Library/Services/Resize Images 1920.workflow`. Images resized in-place are changed permanently — test on copies.

---

### Lab 2 — Folder Action: auto-convert HEIC to JPEG

**Goal:** Drop `.HEIC` files into a watched folder; they auto-convert to `.jpg` in a sibling `converted/` directory.

> ⚠️ **ADVANCED:** This lab creates a persistent system daemon-level hook. To remove it: right-click the folder → Folder Actions Setup → uncheck or delete the action. The daemon runs until removed.

1. Create the watched folder:
   ```bash
   mkdir -p ~/Downloads/HEIC-drop
   ```
2. Build the Folder Action as described in the Hands-on section above. Save it.
3. Right-click `~/Downloads/HEIC-drop` → Services → **Folder Actions Setup…**. Verify "HEIC to JPEG" appears and is checked.
4. Verify the dispatcher is active:
   ```bash
   launchctl list | grep FolderActions
   # Expected: com.apple.FolderActionsDispatcher listed with a PID
   ```
5. Copy a `.HEIC` file (from iPhone AirDrop or `curl` a test image) into the folder.
6. Wait 2–5 seconds; check for `~/Downloads/HEIC-drop/converted/*.jpg`.
7. Inspect the registration artifact:
   ```bash
   defaults read ~/Library/Preferences/com.apple.FolderActionsDispatcher.plist
   ```

> 🔬 **Forensics note:** This lab demonstrates exactly how a persistence mechanism using Folder Actions looks on disk. Note the plist entry that survives reboots. The same technique is used by malware — compare what you see here against a suspect system's `com.apple.FolderActionsDispatcher.plist`.

**Roll back:**
```bash
# Remove the Folder Action registration via GUI: right-click folder → Folder Actions Setup → delete
# Remove the workflow file:
rm ~/Library/Workflows/Applications/Folder\ Actions/HEIC\ to\ JPEG.workflow
# Remove the watched folder if you don't need it:
rm -rf ~/Downloads/HEIC-drop
```

---

### Lab 3 — Build an EXIF Droplet and test drag-and-drop delivery

**Goal:** A standalone `.app` that accepts dragged files and writes an EXIF report.

> ⚠️ **Prerequisites:** `exiftool` is recommended (`brew install exiftool`); the script falls back to `mdls` if absent. No destructive operations.

1. Build the droplet as described in the Hands-on section. Save to `~/Applications/EXIF Extractor.app`.
2. Test via CLI (confirms the shell script is correct before any drag-drop):
   ```bash
   automator -i ~/Pictures/test.jpg ~/Applications/EXIF\ Extractor.app
   ```
3. Test via drag-drop: drag 3–4 images onto the app icon in Finder.
4. Confirm `~/Downloads/exif-report-*.txt` is created and opens automatically.
5. Inspect the droplet's internal structure:
   ```bash
   cat ~/Applications/EXIF\ Extractor.app/Contents/Info.plist
   plutil -convert xml1 -o - \
     ~/Applications/EXIF\ Extractor.app/Contents/Resources/document.wflow \
     | grep -A5 'AMShellScript'
   ```
6. **Bonus:** Import the droplet into Shortcuts by dragging the `.workflow` embedded inside it:
   ```bash
   open ~/Applications/EXIF\ Extractor.app/Contents/Resources/document.wflow
   # macOS should prompt: open with Shortcuts or Automator
   ```

---

### Lab 4 — Forensic enumeration of all installed automations

**Goal:** Produce a comprehensive inventory of every Automator-based automation on the system.

```bash
#!/bin/bash
# automator-inventory.sh — enumerate all Automator hooks

echo "=== Quick Actions (Services) ==="
ls ~/Library/Services/*.workflow 2>/dev/null | while read w; do
    name=$(basename "$w" .workflow)
    type=$(defaults read "$w/Contents/Info" AMDocumentType 2>/dev/null)
    echo "  $name [$type]"
done

echo ""
echo "=== Folder Actions ==="
ls ~/Library/Workflows/Applications/Folder\ Actions/*.workflow 2>/dev/null \
  | xargs -I{} basename {} .workflow

echo ""
echo "=== Folder Action Bindings ==="
defaults read ~/Library/Preferences/com.apple.FolderActionsDispatcher.plist 2>/dev/null \
  | grep -E '"path"|"workflow"' | sed 's/^[ \t]*//'

echo ""
echo "=== Calendar Alarm Workflows ==="
ls ~/Library/Workflows/Applications/Calendar/*.workflow 2>/dev/null \
  | xargs -I{} basename {} .workflow

echo ""
echo "=== PDF Services ==="
ls ~/Library/PDF\ Services/*.workflow 2>/dev/null \
  | xargs -I{} basename {} .workflow

echo ""
echo "=== Embedded Shell Commands in Quick Actions ==="
for w in ~/Library/Services/*.workflow; do
    plutil -convert xml1 -o - "$w/Contents/document.wflow" 2>/dev/null \
      | grep -A1 'AMShellScript' | grep '<string>' \
      | head -3 | sed "s|^|  [$(basename $w .workflow)] |"
done
```

Run this on a suspect system to surface any Automator-based persistence or exfiltration hooks in under 5 seconds.

---

## Pitfalls & gotchas

**PATH is stripped.** The shell in "Run Shell Script" inherits `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. Homebrew tools in `/opt/homebrew/bin` are invisible. Always prepend:
```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
```

**"Pass input as stdin" with file paths breaks on spaces.** If your upstream passes paths containing spaces and you use stdin mode with `read`, you'll split mid-path. Prefer "as arguments" for file processing (`for f in "$@"`).

**Notifications require permission.** `osascript -e 'display notification …'` works silently if Notification Center permission for Script Editor (or the delivering app) is denied. Grant it in System Settings → Notifications → Script Editor / Automator.

**Quick Actions don't appear in Finder after save.** Flush the Services cache:
```bash
/System/Library/CoreServices/pbs -flush
```
Then log out and back in if the flush alone isn't enough.

**Folder Actions fire for ALL new files, including temp files.** `TextEdit` writing a document to a watched folder triggers the action on `.rtfd` temp files. Add a guard:
```bash
case "${f##*.}" in
    HEIC|heic) : ;;  # process
    *) continue ;;   # skip everything else
esac
```

**Droplets appear as generic apps if not notarized.** Gatekeeper will block double-click launch on macOS 26 if the `.app` is quarantined (downloaded from internet or received via AirDrop). For local use: right-click → Open. For sharing: notarize with `notarytool`.

**Automator and Shortcuts Quick Actions can conflict.** Both land in the Services menu simultaneously. If you have a Shortcuts Quick Action and an Automator Quick Action with identical names, both appear — name them distinctly.

**The "Watch Me Do" action is broken in macOS 26 Tahoe.** Apple's screen-recording-based action recorder produces events that don't correctly forward clicks to some apps post-upgrade. Use "Run Shell Script" with `osascript -e 'tell app "X" to …'` instead for UI automation.

---

## Key takeaways

- Automator has **eight document types**, each with distinct on-disk locations and invocation mechanisms. Knowing the paths is essential for forensics and automation audits.
- Every `.workflow` package is a decoded binary plist — fully inspectable with `plutil`.
- "Run Shell Script" with **as arguments** is the correct mode for file-path pipelines; **stdin** is for text streams.
- Quick Actions live in `~/Library/Services/`, are registered via the `pbs` Services broker, and bind to keyboard shortcuts through `com.apple.symbolichotkeys.plist`.
- Folder Actions are driven by `com.apple.FolderActionsDispatcher` (an FSEvents subscriber) and persist via a plist in `~/Library/Preferences/`.
- Automator workflows import into Shortcuts via drag-and-drop conversion — most but not all actions survive.
- Automator remains the only first-party tool for Droplets and Print Plugins; it complements rather than competes with Shortcuts for shell-heavy workflows.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| **Quick Action** | An Automator workflow deployed as a Services item; appears in Finder right-click and the Services menu |
| **Folder Action** | A workflow attached to a directory that fires automatically when files are added |
| **Droplet** | An Automator workflow packaged as a `.app` that processes files dragged onto it |
| **`pbs`** | Paste Board Server — the CoreServices daemon that brokers Services menu registrations |
| **FolderActionsDispatcher** | User-space daemon (`com.apple.FolderActionsDispatcher`) that subscribes to FSEvents and fires attached Automator workflows |
| **`document.wflow`** | Binary plist inside a `.workflow` bundle encoding the action graph |
| **JXA** | JavaScript for Automation — the ES6-based alternative to AppleScript in the Open Scripting Architecture |
| **FSEvents** | Kernel subsystem (`/dev/fsevents`) that notifies userspace of filesystem changes; the backend for Folder Actions and Spotlight indexing |
| **OSA** | Open Scripting Architecture — macOS framework enabling multiple scripting languages (AppleScript, JXA, shell via `osascript`) to control apps via their scripting dictionaries |
| **sips** | Scriptable Image Processing System — Apple's built-in CLI image converter/resizer |

---

## Further reading

- [Apple Automator User Guide](https://support.apple.com/guide/automator/welcome/mac) — canonical reference for all action types
- [Apple: Import Automator Workflows into Shortcuts](https://support.apple.com/guide/automator/import-workflows-into-shortcuts-autc12e3fb97/mac) — the official migration guide
- [Apple Developer: Folder Actions Reference](https://developer.apple.com/library/prerelease/content/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_folder_actions.html) — AppleScript API surface for Folder Actions
- [Six Colors: Folder Automation in macOS Tahoe](https://sixcolors.com/post/2025/08/get-started-with-folder-automation-in-macos-tahoe/) — the Shortcuts vs Automator Folder Action comparison post-Tahoe
- [macosxautomation.com](https://macosxautomation.com/automator/folder-action/index.html) — Sal Soghoian's (Automator's creator) reference site; still the most detailed action-by-action documentation
- [[01-shortcuts]] — the successor system, with iOS parity, scheduling, and Focus triggers
- [[03-cli/11-scripting]] — the shell scripting foundation that makes "Run Shell Script" actions powerful
- [[03-cli/04-macos-specific-cli-tools]] — `sips`, `mdls`, `osascript`, `launchctl` and other CLI tools referenced in this lesson
- [[03-cli/05-defaults-and-plists]] — reading and writing the plist artifacts that Automator and Folder Actions leave behind
