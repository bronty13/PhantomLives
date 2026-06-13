---
title: Screenshots & Screen Recording
part: P02 GUI
est_time: 45 min read + 35 min labs
prerequisites: [00-finder-mastery, 01-window-management]
tags: [macos, screenshots, screen-recording, screencapture, automation, forensics, quicktime, accessibility]
---

# Screenshots & Screen Recording

> **In one sentence:** macOS's screenshot stack — four keyboard shortcuts, a rich capture toolbar, the `screencapture` CLI, and a handful of `defaults write` keys — is a precision instrument once you understand what each layer controls and where the artifacts land on disk.

---

## Why this matters

Screenshots are the most common form of visual evidence capture in forensics, UI testing, documentation, and incident response. On macOS the mechanism runs deep: `screencapture` is a CoreGraphics client that calls into `ScreenCaptureKit` (the same framework your screen-recording apps use since macOS 13), writes PNG/JPEG/HEIC metadata-bearing files to a configurable location, and leaves audit-log entries in the unified log. Knowing the full stack means you can script timed captures, pipe results to the clipboard for automation, capture a window by its `CGWindowID` without touching the mouse, or reconstruct exactly when and what a user screenshotted from log forensics.

> 🪟 **Windows contrast:** Windows `PrtScn` copies the full screen to the clipboard (no file); `Win-Shift-S` (Snipping Tool since Windows 10) adds a region selector and floating preview, but defaults to clipboard-only with an opt-in notification-tray save. macOS has saved to a file by default since System 7, clipboard capture is additive (hold `Ctrl`), and the entire subsystem is accessible from a scriptable CLI — none of which has a Windows equivalent.

---

## Concepts

### The Four Keyboard Shortcuts and What Each Triggers

#### `Cmd-Shift-3` — Full-screen capture

Captures every display simultaneously. One PNG per display appears on the Desktop (or your configured save location) named `Screenshot YYYY-MM-DD at HH.MM.SS.png`. Multiple displays produce `Screenshot … 1.png`, `… 2.png`, and so on, numbered left-to-right by horizontal position.

Add `Ctrl` to send to the clipboard instead of writing a file.

#### `Cmd-Shift-4` — Region / crosshair selector

Drops a crosshair cursor. Drag a rectangle to define the capture region. The pixel dimensions update live in the HUD near your cursor.

**Power modifiers while dragging** (all hold during the drag, release to commit):

| Hold key | Effect |
|---|---|
| `Space` after starting drag | Locks the selection size; moves the entire rectangle — your cursor becomes a grab hand |
| `Shift` | Constrains drag to one axis (grow width OR height, not both) |
| `Option` | Expands/contracts the selection symmetrically around its center |
| `Shift + Option` | Constrain axis + symmetric — useful for perfectly centered squares |

**Tap `Space` before dragging** (crosshair → camera mode): hover over any window to highlight it; click to capture that window with its drop shadow. This is distinct from dragging with Space held — the order of operation matters.

**Option modifier in camera mode** (no drag, Space first, then Option while clicking): captures the window *without its drop shadow*. This is often what you want for documentation — the shadow adds 40–60 px of transparent padding around the content, which is invisible in apps but creates blank border space when pasted into a doc.

Add `Ctrl` to either variant to redirect to clipboard.

#### `Cmd-Shift-5` — Capture toolbar

Opens the floating `Screenshot.app` toolbar (introduced macOS Mojave). Five buttons left-to-right:

1. **Capture Entire Screen** — same as `Cmd-Shift-3`
2. **Capture Selected Window** — camera mode; hover-highlight windows
3. **Capture Selected Portion** — crosshair drag; your last region is remembered
4. **Record Entire Screen** — starts a video recording of the full display
5. **Record Selected Portion** — define a rectangle, then click Record

**Options menu** (right side of toolbar, or the `Options` button):

- **Save to** — Desktop, Documents, Clipboard, Mail, Messages, Preview, or other app via share sheet; this sets the default for shortcut captures too
- **Timer** — None, 5 seconds, 10 seconds; the countdown appears in the menu bar
- **Microphone** — None or any audio input device, for screen recordings with narration
- **Show Floating Thumbnail** — toggles the post-capture preview panel (see below)
- **Remember Last Selection** — when checked, re-opens your region crosshair to last position
- **Show Mouse Pointer** — in screen recordings; controls cursor visibility in the video

Press `Esc` to dismiss the toolbar without capturing.

#### `Cmd-Shift-6` — Touch Bar capture (legacy)

Captures the Touch Bar (a ~2170×60 px strip of the OLED Touch Bar on 2016–2021 Intel MacBook Pros). Irrelevant on Apple Silicon machines which have no Touch Bar, and not present in the keyboard shortcut list on those models. Included here because you will encounter it in forensics on older machines.

---

### The Floating Thumbnail (Preview Widget)

After every capture (unless disabled), a small thumbnail slides in from the bottom-right corner and lingers for roughly five seconds. This is not a decoration — it's a live handle:

- **Click it** — opens in Markup for immediate annotation (arrows, text, highlights, redaction boxes, signatures)
- **Drag it** — drops the image directly into a drop target (Messages, Mail, Finder, a code editor) **without saving a file first**; the drag payload is the raw image data
- **Swipe it right** (or wait) — dismisses and saves the file to disk
- **Right-click it** — contextual menu: Open in Preview, Open in Mail, Open in Messages, Save to…, Delete

> ⚠️ **Tahoe-specific bug:** In macOS 26.0 Tahoe, if you begin dragging the thumbnail and then cancel the drag (release without a valid drop target), the screenshot may fail to save to disk entirely. The workaround is to either complete the drag to a valid target, click to open in Markup and save from there, or disable the floating thumbnail and rely on direct-to-disk saves until Apple patches this.

> 🔬 **Forensics note:** A screenshot that was dragged from the thumbnail to another app leaves *no file on disk*. The file-system artifact you'd normally look for (`~/Desktop/Screenshot ….png`) is absent. The capture still shows up in the unified log under the `com.apple.screencapture` subsystem, but without a path. Keep this in mind when trying to establish what a user captured.

**Disabling the thumbnail:**
```bash
defaults write com.apple.screencapture show-thumbnail -bool false
killall SystemUIServer
```

---

### Capture Mechanics: ScreenCaptureKit Under the Hood

Since macOS 13 Ventura, all screen capture — including the keyboard shortcuts and QuickTime's screen recording — routes through `ScreenCaptureKit.framework` (`/System/Library/Frameworks/ScreenCaptureKit.framework`). This replaced the older `CGWindowListCreateImage` approach.

Consequences you need to know:

1. **Privacy permission gate:** The first time any process (including the system `screencapture` tool launched by a keyboard shortcut from a terminal, or a third-party app) tries to capture the screen, macOS prompts for Screen Recording permission under **System Settings → Privacy & Security → Screen Recording**. Permission is per-bundle-ID, stored in the TCC database at `~/Library/Application Support/com.apple.TCC/TCC.db`. Forensically, this table records which apps have ever been granted screen capture access.

2. **Window content redaction:** Apps can opt individual windows into `NSWindowSharingType = NSWindowSharingNone`, which causes their content to appear as a black rectangle in any screen capture. Password managers, banking apps, and DRM video players commonly do this. The window outline and title bar are still visible; only the content area is redacted. `screencapture -l <windowID>` on such a window produces a correctly-sized black image.

3. **ScreenCaptureKit entitlement:** Third-party apps that call ScreenCaptureKit must carry `com.apple.security.screen-capture` in their entitlements. You can verify this: `codesign -d --entitlements :- /Applications/CleanMyMac.app 2>/dev/null | grep screen-capture`.

---

### Default File Format and Location

**Default format:** PNG. PNG is lossless, supports transparency (important for window captures with alpha-channel shadows), and is the right choice for screenshots of text — JPEG's DCT artifacts are visible and degrade readability.

**Default save location:** Desktop (`~/Desktop`). The path expands to `/Users/<username>/Desktop`.

**Filename pattern:** `Screenshot YYYY-MM-DD at HH.MM.SS.png` (e.g., `Screenshot 2026-06-13 at 14.32.07.png`). The timestamp is the local time at capture, not UTC.

All of these are overridable via `defaults write` (see Hands-on section) or via the Cmd-Shift-5 Options menu.

---

### Capturing Menus

Menus dismiss on any keypress, so capturing them requires a specific technique.

**With a timer:** Hit `Cmd-Shift-5`, click Options → Timer → 5 seconds, click "Capture Entire Screen" (or your desired mode), then quickly open the menu you want captured before the timer fires. The countdown tick in the menu bar tells you how long you have.

**With the CLI:** `screencapture -T 5 ~/Desktop/menu-capture.png` — the `-T` flag delays by 5 seconds without you needing to interact with the toolbar.

**With `screencapture -i` in interactive mode after menu is open:** Less reliable — the interactive crosshair is itself a new window/process context and tends to dismiss menus.

> 🔬 **Forensics note:** Menu captures are rare in user evidence trails because the workflow is non-obvious. When you see a screenshot containing an open menu, it's almost certainly a deliberate documentation act, not incidental.

---

### Text Recognition (Live Text) on Screenshots

Since macOS 12 Monterey, every image displayed in Quick Look, Preview, or the floating screenshot thumbnail is run through the Vision framework's text recognizer (same engine as iOS Live Text). You can click-and-drag to select text directly in the thumbnail or in Preview and copy it with `Cmd-C`.

This happens **on-device**, using the Neural Engine on Apple Silicon — no network request. The recognized text is not persisted to the image file's metadata (it won't appear in `exiftool` output); it's recognized on-the-fly from pixel content each time.

**From the command line:** The `screencapture` CLI does not expose text recognition. Use `swift` with the Vision framework or the `mlx-vlm`/`tesseract` tools for scripted OCR pipelines. For one-off forensic text extraction, Quick Look (`ql_file.py` or just `open -f`) is fastest.

---

## Hands-on (CLI & GUI)

### Changing the Save Location Permanently

The Cmd-Shift-5 Options menu sets `NSUserDefaultsCurrentApplication` for `Screenshot.app`, which writes to `~/Library/Preferences/com.apple.screencapture.plist`. You can set it directly:

```bash
# Save to ~/Pictures/Screenshots instead of Desktop
mkdir -p ~/Pictures/Screenshots
defaults write com.apple.screencapture location ~/Pictures/Screenshots
killall SystemUIServer
```

Verify:
```bash
defaults read com.apple.screencapture location
# Output: /Users/bronty13/Pictures/Screenshots
```

> 🪟 **Windows contrast:** Windows screenshots (Win-PrtScn) save to `%USERPROFILE%\Pictures\Screenshots` by default. macOS defaults to Desktop; Windows defaults to Pictures — the inverse of what most people expect given macOS's focus on an uncluttered desktop.

### Changing the File Format

```bash
# Supported types: png, jpg, heic, tiff, pdf, gif, bmp
defaults write com.apple.screencapture type jpg
killall SystemUIServer
```

For HEIC (Apple's HEIF-based format, ~40% smaller than PNG for photos but still lossless option):
```bash
defaults write com.apple.screencapture type heic
```

HEIC screenshots are not universally supported in older tools — `imageio` on macOS reads them natively; `Pillow` (Python) requires `pillow-heif`; on Windows you need the HEVC codec or a converter. For evidence that might be opened on other platforms, stick with PNG.

### Disabling Drop Shadows on Window Captures

```bash
defaults write com.apple.screencapture disable-shadow -bool true
killall SystemUIServer
```

This is a global toggle. You can also hold `Option` at capture time (in Cmd-Shift-4 → Space camera mode) to suppress the shadow for a single capture without changing the default.

### Removing Date/Time from Filenames

```bash
defaults write com.apple.screencapture include-date -bool false
killall SystemUIServer
```

With the date disabled, successive screenshots auto-increment: `Screenshot.png`, `Screenshot 2.png`, etc.

### Changing the Filename Prefix

```bash
defaults write com.apple.screencapture name "Capture"
killall SystemUIServer
# → Produces: "Capture 2026-06-13 at 14.32.07.png"
```

### The `screencapture` CLI: Full Reference

The `/usr/sbin/screencapture` binary is a first-class macOS tool, not a thin wrapper — it has capabilities the GUI doesn't expose.

```
screencapture [flags] [file ...]
```

**Capture modes:**

| Flag | Behavior |
|---|---|
| `-i` | Interactive — same as `Cmd-Shift-4`; crosshair/camera selection |
| `-W` | Interactive, defaulting to window-highlight mode |
| `-w` | Force window-only mode (no crosshair region possible) |
| `-s` | Force region-only mode (no window highlight) |
| `-J selection\|window\|video` | Set the starting capture style when using the toolbar (`-U`) |
| `-U` | Show the interactive toolbar (same as `Cmd-Shift-5`) |
| `-R x,y,w,h` | Capture a specific pixel rectangle non-interactively |
| `-l <windowID>` | Capture the window with this CGWindowID |
| `-D <n>` | Capture display number n (1=main, 2=secondary) |
| `-m` | Capture main display only |
| `-T <seconds>` | Delay before capture; use for menu captures |

**Output modifiers:**

| Flag | Behavior |
|---|---|
| `-c` | Capture to clipboard instead of file |
| `-t png\|jpg\|pdf\|tiff\|heic` | Set output format |
| `-o` | In window mode, omit the drop shadow |
| `-a` | Do not capture windows attached to the target (e.g., sheets) |
| `-S` | In window mode, capture the screen behind the window instead |
| `-C` | Include the cursor in the capture |
| `-x` | Suppress the screenshot sound |
| `-r` | Omit DPI/resolution metadata from the file |
| `-P` | Open the result in Preview (or QuickTime for video) |
| `-M` | Open in a new Mail compose window |

**Video recording:**

| Flag | Behavior |
|---|---|
| `-v` | Record video (interactive region selection if no `-R`); `Ctrl-C` stops |
| `-V <seconds>` | Record video for exactly this many seconds, then stop |
| `-g` | Capture audio from the default input device with the recording |
| `-G <id>` | Capture audio from a specific audio device (use `system_profiler SPAudioDataType` to get IDs) |
| `-k` | Show mouse clicks as a highlight in the video |

**Getting a window's ID for `-l`:**

```bash
# List all on-screen windows with their IDs
osascript -e 'tell application "System Events" to get every window of every process'

# Better: use the CoreGraphics Python binding or swift
swift -e '
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String:Any]]
for w in windows {
  let owner = w["kCGWindowOwnerName"] as? String ?? "?"
  let id = w["kCGWindowNumber"] as? Int ?? -1
  let name = w["kCGWindowName"] as? String ?? ""
  print("\(id)\t\(owner)\t\(name)")
}
'
```

**Example: capture Safari non-interactively to clipboard:**
```bash
# Get Safari's window ID from the list above, e.g. 2304
screencapture -c -l 2304
# Clipboard now holds the window image
```

### Screen Recording via CLI

The `-v` flag turns `screencapture` into a screen recorder:

```bash
# Interactive: select a region, press Return to start, Ctrl-C to stop
screencapture -v ~/Desktop/demo.mov

# Record full screen for exactly 30 seconds with audio and click highlights
screencapture -V 30 -g -k ~/Desktop/demo30.mov

# Record a specific 1280×800 region at origin (0,0)
screencapture -v -R 0,0,1280,800 ~/Desktop/region.mov
```

The output is a `.mov` container with H.264 video. QuickTime Player can trim it; `ffmpeg` can transcode it.

### Screen Recording via QuickTime Player

`File → New Screen Recording` (or `Ctrl-Cmd-N`) opens the same ScreenCaptureKit capture toolbar as `Cmd-Shift-5`. The difference: QuickTime gives you its own editing timeline post-recording, useful for trimming without additional tools. The resulting `.mov` files land in `~/Movies/` by default, not the screenshot save location.

---

## 🧪 Labs

### Lab 1: Change Format and Location via `defaults`

**Goal:** Redirect all captures to a dedicated folder in JPEG format, verify the change, and revert.

**Backup/rollback:** Your current settings are read-only; reverting is `defaults delete`. No files are modified that can't be reset.

```bash
# 1. Record current settings
ORIG_LOC=$(defaults read com.apple.screencapture location 2>/dev/null || echo "NOT SET")
ORIG_TYPE=$(defaults read com.apple.screencapture type 2>/dev/null || echo "NOT SET")
echo "Original: location=$ORIG_LOC type=$ORIG_TYPE"

# 2. Create a capture landing zone
mkdir -p ~/Pictures/lab-captures

# 3. Apply new settings
defaults write com.apple.screencapture location ~/Pictures/lab-captures
defaults write com.apple.screencapture type jpg
defaults write com.apple.screencapture name "Lab"
defaults write com.apple.screencapture include-date -bool true
killall SystemUIServer

# 4. Capture: hit Cmd-Shift-3 to take a full screenshot
echo "Take a screenshot now with Cmd-Shift-3, then press Return..."
read

# 5. Verify the file landed where expected and is JPEG
ls -la ~/Pictures/lab-captures/
file ~/Pictures/lab-captures/Lab\ *.jpg 2>/dev/null || \
  file ~/Pictures/lab-captures/Lab*.jpg

# 6. Revert
defaults delete com.apple.screencapture location 2>/dev/null
defaults delete com.apple.screencapture type 2>/dev/null
defaults delete com.apple.screencapture name 2>/dev/null
killall SystemUIServer
echo "Reverted. Originals were: location=$ORIG_LOC type=$ORIG_TYPE"
```

**Expected output on step 5:** `Lab 2026-06-13 at 14.35.22.jpg: JPEG image data, JFIF standard 1.01…`

---

### Lab 2: Script a Timed Screen Capture

**Goal:** Write a shell one-liner that opens a target app, waits 3 seconds, captures its frontmost window, and copies to clipboard.

```bash
# Open Safari to a target URL
open -a Safari "https://developer.apple.com/documentation/screencapturekit"

# Wait for Safari to fully render (adjust as needed)
sleep 3

# Get Safari's CGWindowID (grab the first window entry)
WIN_ID=$(swift -e '
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String:Any]]
for w in windows {
  guard let owner = w["kCGWindowOwnerName"] as? String,
        owner == "Safari",
        let id = w["kCGWindowNumber"] as? Int
  else { continue }
  print(id)
  exit(0)
}
' 2>/dev/null | head -1)

echo "Safari window ID: $WIN_ID"

# Capture it to clipboard (silently, no sound)
screencapture -c -x -l "$WIN_ID"
echo "Safari window is now in the clipboard. Paste into any app."
```

**Variation — save to file with timestamp:**
```bash
screencapture -x -l "$WIN_ID" ~/Desktop/safari-$(date +%Y%m%d-%H%M%S).png
```

---

### Lab 3: Record a Screen Region for 10 Seconds

**Goal:** Record a 640×480 region at the top-left of the screen for exactly 10 seconds, with click highlights.

⚠️ **ADVANCED:** This starts a video recording process. It will capture whatever is on screen. Do not have sensitive content visible. Output file is `~/Desktop/region-test.mov` — delete after.

```bash
# Record a 640x480 region at top-left for 10 seconds, show clicks
screencapture -V 10 -k -R 0,0,640,480 ~/Desktop/region-test.mov

# After it finishes automatically:
ls -lh ~/Desktop/region-test.mov
# Typical output: ~ 2-8 MB for 10 seconds depending on content motion

# Open in QuickTime to verify
open -a "QuickTime Player" ~/Desktop/region-test.mov
```

**With audio narration (requires microphone permission):**
```bash
screencapture -V 10 -g -k -R 0,0,640,480 ~/Desktop/region-narrated.mov
```

---

### Lab 4: Forensic Artifact Inventory

**Goal:** Understand what evidence a screenshot leaves behind.

```bash
# 1. Take a test screenshot and note the exact filename
screencapture -x ~/Desktop/forensic-test.png

# 2. Check extended attributes (creation tool, metadata)
xattr -l ~/Desktop/forensic-test.png
# You'll typically see: com.apple.quarantine is NOT set (local capture, not download)
# com.apple.metadata:kMDItemWhereFroms is absent

# 3. Check EXIF/metadata
mdls ~/Desktop/forensic-test.png | grep -E 'kMDItem(DisplayName|ContentCreationDate|Kind|PixelWidth|PixelHeight)'

# 4. Check the unified log for screencapture events (last 5 minutes)
log show --predicate 'subsystem == "com.apple.screencapture"' \
  --last 5m --style compact 2>/dev/null | head -40
# Note: may require sudo for full log access

# 5. Check TCC database for screen recording grants
sudo sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value, last_modified FROM access WHERE service='kTCCServiceScreenCapture';" \
  2>/dev/null
# auth_value: 2 = allowed, 0 = denied

# 6. Clean up
rm ~/Desktop/forensic-test.png
```

---

## Pitfalls & Gotchas

**The `defaults write` cycle:** Setting `com.apple.screencapture` preferences via `defaults write` writes to `~/Library/Preferences/com.apple.screencapture.plist`, but the running `SystemUIServer` caches the values. The `killall SystemUIServer` step is mandatory — without it, changes don't take effect until login/logout. macOS 26 Tahoe also caches some preferences in `Screenshot.app`'s own NSUserDefaults domain, so if a setting stubbornly refuses to take, log out and back in.

**`screencapture -l` requires the window to be on-screen:** If the window is minimized to the Dock, its CGWindowID is still valid but the content is the minimization thumbnail, not the live view. Unminimize first.

**Region coordinates are in points, not pixels:** On a Retina display, `screencapture -R 0,0,1280,800` captures a logical 1280×800 point region that corresponds to 2560×1600 physical pixels. The resulting image is 2560×1600 at 144 DPI. Use `-r` to strip the DPI metadata if downstream tools misinterpret the 2x scaling.

**Screen recording permission in automation:** If you run `screencapture` from a terminal that hasn't been granted Screen Recording permission in TCC, the tool silently produces a black (or blank) image with exit code 0. No error, no warning — just a black PNG. Check TCC first when debugging this.

**Clipboard capture replaces the entire pasteboard:** `screencapture -c` writes to `NSPasteboard.general` as `NSImage`/`public.tiff`. Any text or other data previously on the clipboard is replaced. There's no "add to clipboard" mode; it's a full replace.

**HEIC format and compatibility:** HEIC screenshots use the `.heic` extension but the system may still name them `.png` in older macOS builds where format detection was buggy. Verify with `file` not the extension.

**Menu bar captures in window mode:** The menu bar is owned by `WindowServer` and has a CGWindowID, but it's a shared surface and its per-app content isn't separately windowed. Capturing it with `-l` gets the full menu bar strip, not the active menu overlay (which is a separate `NSPanel`-class layer). Use the timer technique instead.

**QuickTime screen recordings vs. `screencapture -v`:** QuickTime adds post-recording editing UI and defaults output to `~/Movies/`. `screencapture -v` is headless and scriptable but provides no in-recording UI feedback. For automation, prefer the CLI; for interactive presentations/demos, QuickTime.

> 🔬 **Forensics note:** macOS does not log screenshot content or produce thumbnails of captures in any user-accessible location (unlike iOS's photo library, which does add screenshots). The unified log records the capture event and output path but not the image content. Screenshots of DRM content (e.g., Apple TV+, Netflix in Safari) produce correct files because ScreenCaptureKit captures the composited framebuffer — DRM apps cannot prevent this on macOS the way they can on iOS. This is a known forensic capability gap from a content-protection standpoint, and a known investigative opportunity from a forensics standpoint.

---

## Key takeaways

- **Four shortcuts, one framework:** `Cmd-Shift-3/4/5/6` all route through `ScreenCaptureKit`; `Cmd-Shift-5` is the entry point to screen recording.
- **`Ctrl` is the clipboard modifier:** add it to any screenshot shortcut to send to clipboard instead of disk.
- **`Option` in Cmd-Shift-4 camera mode** suppresses the drop shadow on window captures.
- **`defaults write com.apple.screencapture`** controls format (`type`), location, filename prefix, date inclusion, shadow suppression, and thumbnail visibility — all take effect after `killall SystemUIServer`.
- **`/usr/sbin/screencapture`** is a full CLI with interactive mode, window-by-ID capture, timed delay, video recording (with audio and click-highlight), clipboard output, and region specification — use it in scripts and automation.
- **ScreenCaptureKit requires TCC permission:** black images from `screencapture` in automation usually mean a missing Screen Recording grant in `~/Library/Application Support/com.apple.TCC/TCC.db`.
- **The floating thumbnail is an interactive handle**, not just a preview — drag it to a drop target to transfer without saving a file, or click to enter Markup for immediate annotation.
- **Forensically:** screen capture events appear in the unified log under `com.apple.screencapture`; TCC grants are in the user-level TCC.db; DRM content is capturable on macOS unlike iOS; thumbnail-drag captures leave no file artifact.

---

## Terms introduced

| Term | Definition |
|---|---|
| `ScreenCaptureKit` | Apple framework (macOS 13+) underlying all screen capture and recording; replaced `CGWindowListCreateImage` |
| `CGWindowID` | Integer identifier for an on-screen window surface, assigned by `WindowServer` and exposed via `CoreGraphics` |
| `SystemUIServer` | System daemon that owns the menu bar UI and caches screenshot preferences; must be restarted after `defaults write` changes |
| TCC (`com.apple.TCC`) | Transparency, Consent, and Control subsystem; its SQLite database records per-app permissions including Screen Recording |
| DPI metadata | Resolution tag embedded in PNG/JPEG (typically 72 or 144 DPI for Retina); affects how apps scale the image at display time |
| Floating thumbnail | Post-capture preview widget introduced macOS Mojave; interactive handle for Markup or drag-to-app transfer |
| `NSPasteboard` | macOS clipboard mechanism; `screencapture -c` writes to `NSPasteboard.general` replacing all prior content |
| `appcast` | (context from Sparkle) — not applicable here; see [[purplemark-release-workflow]] |
| `-T` flag | `screencapture` delay timer flag; enables menu-state capture without the GUI toolbar |

---

## Further reading

- `man screencapture` — the local man page is the authoritative flag reference for your exact macOS version
- [Apple ScreenCaptureKit documentation](https://developer.apple.com/documentation/screencapturekit) — framework internals, entitlement requirements, SCStream API for live capture pipelines
- [Der Flounder: Disabling floating thumbnail in macOS Tahoe](https://derflounder.wordpress.com/2025/11/27/disabling-the-floating-thumbnail-preview-for-screenshots-on-macos-tahoe/) — `defaults` key and Tahoe-specific behavior
- [macos-defaults.com](https://macos-defaults.com/screenshots/) — community-maintained catalog of all `com.apple.screencapture` defaults keys with before/after examples
- Howard Oakley's [Eclectic Light Company](https://eclecticlight.co) — search "screencapture" and "ScreenCaptureKit" for deep dives on privacy changes and DRM interaction
- Related lessons: [[00-finder-mastery]] (xattr metadata on files, `.DS_Store`), [[01-window-management]] (window IDs, WindowServer layer model), [[05-automation-scripting]] (scripting screencapture in Shortcuts/AppleScript), [[05-security-tcc]] (TCC database forensics)
