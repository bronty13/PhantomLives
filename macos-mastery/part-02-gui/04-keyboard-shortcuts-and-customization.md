---
title: Keyboard Shortcuts & Customization
part: P02 GUI
est_time: 50 min read + 45 min labs
prerequisites: [00-finder-mastery, 01-window-management]
tags: [macos, keyboard, shortcuts, karabiner, hidutil, productivity, accessibility]
---

# Keyboard Shortcuts & Customization

> **In one sentence:** macOS exposes a layered shortcut system — from symbolic modifier logic and built-in Emacs bindings in every text field, up through per-app menu rebinding in System Settings, and down through kernel-level HID remapping via `hidutil` and Karabiner-Elements — that a power user can fully own.

---

## Why this matters

On Windows, keyboard customization is fragmented: some apps use AutoHotkey, some expose their own rebinding UIs, and system-wide remapping requires third-party drivers with variable reliability. macOS has a coherent layered model: the NSResponder chain handles text editing uniformly across every Cocoa app, the menu system is the single source of truth for app commands, and the HID stack provides a well-documented kernel interface for hardware-level remapping. Once you internalize the model, you can bind, remap, or automate essentially any keyboard action without touching a single app's preferences pane.

For forensics work, this matters differently: understanding what shortcuts exist tells you what *actions were possible*, and the artifacts left by remapping tools (`hidutil` launchd plists, Karabiner's JSON config) can be evidence of deliberate workflow customization — or evasion.

> 🪟 **Windows contrast:** Windows uses `Ctrl` for most app commands; macOS uses `⌘`. This means your muscle memory for `Ctrl-C/V/Z/S/W` must shift to `⌘`. The silver lining: `⌃` (Control) on macOS is largely *unoccupied* by app shortcuts and is instead handed over to the Emacs-style text navigation bindings described below — a far more useful allocation.

---

## Concepts

### The Modifier Hierarchy

macOS assigns each modifier a semantic role. Understanding the *intent* behind each level lets you predict shortcuts you've never seen:

| Modifier | Symbol | Semantic role | Typical use |
|---|---|---|---|
| Command | `⌘` | App-level commands | Cut/Copy/Paste/Save/Quit; most menu items |
| Option | `⌥` | Variant or alternative | `⌥⌘V` = Paste and Match Style; `⌥Delete` = delete word; `⌥↑` = move line up (in editors) |
| Control | `⌃` | Low-level / terminal / Emacs | Text insertion-point movement; terminal signals (`⌃C`, `⌃Z`) |
| Shift | `⇧` | Extend or reverse | Extend selection (`⇧→`); reverse tab order (`⇧⇥`); inverse of an action |
| Fn / Globe | `fn` or `🌐` | Hardware function layer / system | F-keys as true function keys; dictation; emoji picker; `fn-Shift-A` = Apps (Tahoe) |

Modifier stacking is additive: `⌘⌥K` is the Command variant of Option-K. `⇧⌘Z` is the shift (reverse) of `⌘Z` (Undo → Redo). Once you see the pattern, a shortcut you've never encountered is often deducible.

### The Shortcut Resolution Chain

When you press a key combo, AppKit resolves it in order:

1. **System-reserved shortcuts** — hardwired by the OS; some cannot be overridden (e.g., `⌘⌃Space` for emoji, `⌘Space` for Spotlight, `⌃⌘Q` for lock screen).
2. **System Settings overrides** — shortcuts you've customized in System Settings ▸ Keyboard ▸ Keyboard Shortcuts override app defaults.
3. **App menu shortcuts** — declared in the app's menu bar; the NSMenu system dispatches these.
4. **Responder chain key equivalents** — views that handle `keyDown:` directly (games, terminals, some editors).
5. **NSTextInputClient / text editing bindings** — the Emacs layer, active in any `NSTextView`/`NSTextField`.

The key insight: menu-based shortcuts operate at layer 3. Anything in a menu can be rebound at layer 2 via System Settings without touching the app.

### The Globe/Fn Key (macOS Sequoia onward)

The `fn` key on Apple Silicon keyboards doubles as the Globe key (`🌐`). Its roles:

- **Tap once:** Trigger Dictation (if configured)
- **Hold + F-key:** Produce true function key signal (F1–F12)
- **Hold + ↑/↓:** Page Up / Page Down on compact keyboards without those keys
- **`fn-E`:** Open emoji & symbols picker
- **`fn-Shift-A`:** Show/hide Apps (replaces Launchpad in macOS 26 Tahoe)
- **`fn-D`:** Toggle Do Not Disturb
- **`fn-C`:** Toggle Focus mode

The Globe key is configured in **System Settings ▸ Keyboard** under "Press fn key to" — options include Show Emoji & Symbols, Start Dictation, Change Input Source, or Do Nothing.

> 🔬 **Forensics note:** Globe-key Dictation requests are logged. If Dictation is enabled, `~/Library/Logs/DiagnosticReports/` may contain crash reports from the `assistantd` daemon, and `~/Library/Preferences/com.apple.assistant.support.plist` records whether Dictation has been used. The on-device Dictation engine stores no audio, but Enhanced Dictation (cloud) has different privacy implications.

### Essential System-Wide Shortcuts

These work everywhere, regardless of frontmost app:

```
⌘Space             Spotlight search
⌃⌘Space            Emoji & symbols picker (also fn-E)
⌘⇥ / ⌘⇧⇥          App switcher (forward / backward)
⌘`                 Cycle windows within same app
⌘H                 Hide frontmost app
⌘⌥H               Hide all other apps
⌘M                 Minimize to Dock
⌘⌥M               Minimize all windows
⌘W                 Close window
⌘⌥W               Close all windows
⌘Q                 Quit app
⌘⌥Esc             Force Quit dialog
⌃⌘Q               Lock screen immediately
⌃⇧Eject/Power     Sleep display
⌘⇧3               Screenshot full screen to file
⌘⇧4               Screenshot selection to file  
⌘⇧4, then Space    Screenshot window to file
⌘⇧5               Screenshot/screen record control panel
⌘⇧6               Touch Bar screenshot (older Macs)
fn-Shift-A         Show Apps (Tahoe 26+); Launchpad (earlier)
```

### Text Navigation: The Emacs Layer

This is one of the most powerful and least-known macOS features: **every native text field** — Terminal, Safari address bar, Spotlight, Messages, Mail compose, Xcode, VS Code native fields — honors a subset of Emacs movement bindings. These are implemented in `NSTextView` and delegate through `NSStandardKeyBindingResponding`.

```
Movement:
⌃A / ⌃E           Move to beginning / end of line (like Home/End)
⌃F / ⌃B           Move forward / backward one character (like →/←)
⌃N / ⌃P           Move to next / previous line
⌃V                 Page down (in scrollable text)

Deletion:
⌃D                 Delete character to the right (like Fn-Delete / Forward Delete)
⌃H                 Delete character to the left (like Backspace)
⌃K                 Kill (cut) to end of line — text goes to kill ring
⌃Y                 Yank (paste from kill ring — ⌃K victims)

Misc:
⌃T                 Transpose characters around insertion point
⌃O                 Open new line after insertion point (rare but useful)
⌃L                 Center current line in scrollable view
```

For *word-wise* and *document-wise* navigation, macOS uses modifier+arrow:

```
⌥←  / ⌥→          Move word left / right (by word boundary)
⌘←  / ⌘→          Move to beginning / end of line
⌥↑  / ⌥↓          Move to beginning / end of paragraph (most apps)
⌘↑  / ⌘↓          Move to beginning / end of document

Add ⇧ to any of the above to SELECT instead of just move:
⇧⌥→               Select to next word boundary
⇧⌘↑               Select to beginning of document
```

> 🪟 **Windows contrast:** Windows uses `Home`/`End` for line-start/end and `Ctrl+Home`/`Ctrl+End` for document-start/end. On MacBook keyboards without a dedicated `Home`/`End` key, `⌘←`/`⌘→` fills that role. The `⌃A`/`⌃E` bindings are additive — you can use either.

> 🔬 **Forensics note:** `NSTextView` key bindings are configurable via `~/Library/KeyBindings/DefaultKeyBinding.dict` — a plist file that overrides the factory Emacs mappings. Finding a non-default `DefaultKeyBinding.dict` on a suspect machine indicates deliberate keyboard customization.

### Home/End Key Behavior on External Keyboards

External keyboards with physical `Home`/`End` keys behave *differently* from what Windows users expect. By default:

- `Home` / `End` → scroll to top/bottom of document **without moving the insertion point**
- To get insertion-point-moving behavior, use `⌘←` / `⌘→` (line) or `⌘↑` / `⌘↓` (document)

You can override this via `~/Library/KeyBindings/DefaultKeyBinding.dict`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>UF700</key>  <!-- Home -->
  <string>moveToBeginningOfLine:</string>
  <key>UF701</key>  <!-- End -->
  <string>moveToEndOfLine:</string>
  <key>$UF700</key> <!-- Shift-Home -->
  <string>moveToBeginningOfLineAndModifySelection:</string>
  <key>$UF701</key> <!-- Shift-End -->
  <string>moveToEndOfLineAndModifySelection:</string>
</dict>
</plist>
```

Log out and back in for this to take effect. Changes apply to all Cocoa text views.

### System Settings ▸ Keyboard ▸ Keyboard Shortcuts

This pane is the most powerful system-level shortcut tool most users never properly use. It has two critical capabilities:

**1. Disabling or remapping system shortcuts.** Every shortcut group (Mission Control, Screenshots, Spotlight, Accessibility, etc.) is listed with a checkbox. You can disable a conflicting system shortcut so an app's native binding wins, or reassign it to a different combo. The left column shows the current binding; click it once to retype a replacement.

**2. App Shortcuts — binding ANY menu command in ANY app.** This is the killer feature. Navigate to the "App Shortcuts" section:

- Click `+`
- **Application:** choose a specific app, or "All Applications" for universal scope
- **Menu Title:** type the *exact* string shown in the menu, character-for-character, including any trailing ellipsis (`…` — `U+2026`, not three dots), capitalization, and Unicode symbols
- **Keyboard Shortcut:** press the desired combo

The mechanism: at launch, AppKit compares this plist against the app's `NSMenu` tree. If the Menu Title string matches a menu item exactly, the shortcut is injected. If the string doesn't match exactly, nothing happens — silently. This is the #1 failure mode.

```
# Example: find the exact title for Xcode's "Generate Documentation Catalog"
# Open the app, pull down every menu, and copy the exact text.
# "Generate Documentation Catalog" ≠ "Generate documentation catalog"
```

The backing storage is `~/Library/Preferences/com.apple.universalaccess.plist` (for global shortcuts) and per-app entries in `~/Library/Preferences/com.apple.symbolichotkeys.plist`. You can script them, but the Settings UI is more reliable.

> 🔬 **Forensics note:** `com.apple.symbolichotkeys.plist` records every system shortcut state, including ones the user has explicitly disabled. Comparing this file against a factory default reveals exactly which shortcuts a user modified — potentially useful when investigating whether an accidental action was plausibly triggered.

### Services Menu Shortcuts

The **Services menu** (`App Name ▸ Services`) exposes system-wide contextual actions registered by other apps: "Open Terminal Here", "Search with Alfred", "New OmniFocus Task", etc. Each service can have a global keyboard shortcut assigned via **System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services**.

Services are registered as `NSServices` entries in `Info.plist` files inside app bundles. The OS scans all installed apps' Info.plists on login and builds the Services menu dynamically. This means installing an app can silently add new Services entries.

```bash
# List all currently registered services
/System/Library/CoreServices/pbs -dump_pboard
```

### Modifier Key Remapping in System Settings

**System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Modifier Keys** provides per-device remapping of the four modifier keys (Caps Lock, Control, Option, Command, Globe/fn). This is the *system-level*, no-reboot approach for simple swaps.

The most productive remap for power users and developers is **Caps Lock → Control** (or Caps Lock → Escape for Vim users). Rationale: Caps Lock sits at prime real estate on the home row but is rarely needed; Control/Escape is used constantly but lives in an awkward corner.

This remapping writes to `~/Library/Preferences/com.apple.keyboard.plist` and is per-input-device (you can remap a built-in keyboard differently from an external one).

Limitation: System Settings remapping is one-to-one; it cannot make one key behave as two different keys depending on whether it's tapped or held. That requires Karabiner-Elements (see Labs).

### Dictation & Keyboard Layouts

**Dictation** (System Settings ▸ Keyboard ▸ Dictation) puts the microphone at a double-tap of the Globe/fn key by default. On Apple Silicon with on-device models, Dictation is entirely offline — audio never leaves the machine. The transcription engine runs as part of `assistantd`.

**Input Sources** (System Settings ▸ Keyboard ▸ Input Sources) let you switch keyboard layouts (Dvorak, Colemak, international layouts). `⌃Space` or `⌃⌥Space` cycles through them. The Globe key can also be configured to cycle input sources on hold.

> 🔬 **Forensics note:** The most recently used input source is recorded in `~/Library/Preferences/com.apple.HIToolbox.plist` under the `AppleCurrentKeyboardLayoutInputSourceID` key. A non-English layout left active could indicate a user who writes in another language, or a layout used for character-set reasons.

---

## Hands-on (CLI & GUI)

### Inspect Current System Shortcuts

```bash
# Dump the symbolic hotkeys plist to readable XML
defaults read com.apple.symbolichotkeys | head -80

# Check which modifier keys are remapped on connected keyboards
defaults read com.apple.keyboard

# List HID key remappings currently active (empty if none)
hidutil property --get "UserKeyMapping"
```

### Create an App Shortcut via System Settings (GUI)

To bind `⌘⇧B` to "Build" in Xcode (which normally has no default shortcut for some build variants):

1. System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ App Shortcuts
2. `+` → Application: Xcode.app
3. Menu Title: type the exact string from Xcode's Product menu (e.g., `Build For Running`)
4. Shortcut: press `⌘⇧B`

If the binding doesn't fire, open Xcode, navigate Product ▸ your intended item, and verify the exact title including case and punctuation. Then delete and re-add the entry.

### Remap Caps Lock to Control (GUI)

System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Modifier Keys:

- Select the target device from the dropdown (repeat for each keyboard you use)
- Caps Lock Key: `⌃ Control`
- Apply

No reboot required. The change takes effect immediately.

### Remap a Key with hidutil (CLI)

`hidutil` remaps keys at the HID (Human Interface Device) layer — below the OS, above the hardware. Remappings survive sleep but are lost on reboot.

HID usage IDs use the format `0x700000000 | <usageID>`:

| Key | Usage ID | Full hex |
|---|---|---|
| Caps Lock | 0x39 | 0x700000039 |
| Escape | 0x29 | 0x700000029 |
| Left Control | 0xE0 | 0x7000000E0 |
| Left Option | 0xE2 | 0x7000000E2 |
| Left Command | 0xE3 | 0x7000000E3 |
| Tab | 0x2B | 0x70000002B |
| Grave/Backtick | 0x35 | 0x700000035 |

Example — remap Caps Lock to Escape (useful for Vim):

```bash
hidutil property --set '{"UserKeyMapping":[
  {
    "HIDKeyboardModifierMappingSrc": 0x700000039,
    "HIDKeyboardModifierMappingDst": 0x700000029
  }
]}'
```

Clear all remappings:

```bash
hidutil property --set '{"UserKeyMapping":[]}'
```

To make a `hidutil` remap persist across reboots, install it as a launchd agent:

```bash
# Create ~/Library/LaunchAgents/com.local.KeyRemapping.plist
cat > ~/Library/LaunchAgents/com.local.KeyRemapping.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.KeyRemapping</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/hidutil</string>
    <string>property</string>
    <string>--set</string>
    <string>{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x700000029}]}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.local.KeyRemapping.plist
```

> 🔬 **Forensics note:** `~/Library/LaunchAgents/` is a standard persistence location. A `hidutil`-based launchd agent there is a legitimate tool for key remapping, but the same mechanism can be abused for persistence. Always cross-reference the `ProgramArguments` against known-good values. See [[02-launchd-and-login-items]] for the full launchd persistence picture.

### Function Key Behavior

On Apple Silicon MacBooks, the top row defaults to *media/system function keys* (brightness, volume, etc.). To send true F1–F12 signals:

- **Hold fn** and press the key — sends the F-key signal
- **Flip the default** in System Settings ▸ Keyboard: "Use F1, F2, etc. keys as standard function keys" — now bare press sends F-keys; fn+key sends the media action

On external keyboards without an fn key, the behavior depends on the keyboard. Apple's "Use all F1, F2, etc. keys as standard function keys" setting applies globally to software function-key interpretation.

---

## 🧪 Labs

### Lab 1: Bind a Custom Menu Shortcut

**Goal:** Assign `⌘⌥T` to "Open Terminal Here" in Finder (a menu item that may or may not exist depending on your config) OR bind a shortcut to any menu item in an app you regularly use.

**Prerequisites:** Know the exact menu path for your chosen command.

1. Open the target app and carefully note the exact menu item string (copy it if possible).
2. System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ App Shortcuts ▸ `+`
3. Set Application, paste the exact Menu Title, assign shortcut.
4. Bring the app to the foreground and verify the shortcut appears next to the menu item.

**Troubleshooting:** If the shortcut doesn't appear: (a) check for exact-match failure (ellipsis is `…` not `...`); (b) check for conflict with a system shortcut by looking in other sections of the Shortcuts pane; (c) restart the app.

> ⚠️ **ADVANCED:** If you bind a shortcut that conflicts with something the app already uses, the app's native binding silently wins. System Settings overrides work only when the app has no pre-existing binding for that exact key combo. To override an existing app shortcut, you must first disable the original — which often means the app provides no mechanism to do so and you need Keyboard Maestro or a plist edit.

---

### Lab 2: Remap Caps Lock

**Rollback:** System Settings ▸ Keyboard Shortcuts ▸ Modifier Keys → set Caps Lock back to "Caps Lock".

1. System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Modifier Keys
2. Select your primary keyboard from the dropdown
3. Caps Lock Key → `⌃ Control` (or `⎋ Escape` if you use Vim/Neovim)
4. Apply, then open a Terminal and verify: press what was Caps Lock — it should act as Control (test with `⌃C` or `⌃A` in a text field)

For Escape: open a text field, type something, press your new Escape key — the cursor should leave text-entry mode in any app that uses Escape for that. In Vim/Neovim this is the primary use case.

---

### Lab 3: Install Karabiner-Elements for Home-Row Mods

> ⚠️ **ADVANCED / SYSTEM-LEVEL:** Karabiner-Elements installs a kernel-level driver extension (`org.pqrs.driver.KarabinerElements`) and requires granting it explicit permission in System Settings ▸ Privacy & Security. This is a significant trust decision. The source code is open (github.com/pqrs-org/Karabiner-Elements). The developer has confirmed compatibility with macOS 26 Tahoe. Some users report needing to re-grant driver permission after minor OS updates (issue #4314). **To roll back:** uninstall via the Karabiner-Elements app's own uninstaller, then revoke the driver extension in System Settings ▸ Privacy & Security ▸ Driver Extensions.**

**What Karabiner-Elements adds that System Settings cannot:**
- **Dual-role keys:** one key acts as two different things depending on whether it's *tapped* or *held* (e.g., Caps Lock = Escape when tapped, Control when held)
- **Home-row modifiers:** A/S/D/F and J/K/L/; act as ⌘⌥⌃⇧ when *held simultaneously with another key*, but produce their normal letters when tapped — no extra hardware required
- **Complex multi-key rules** with timing, conditions, and variable state
- **Per-application remapping**
- **Device-specific rules** (remap only your external keyboard, not the built-in)

**Installation:**

```bash
# Install via Homebrew (recommended — keeps it updatable)
brew install --cask karabiner-elements
```

After install:
1. Open Karabiner-Elements — it will prompt you to allow the driver extension
2. System Settings ▸ Privacy & Security → scroll to find the "Karabiner-Elements" driver extension → Allow
3. Restart when prompted

**Configuring Caps Lock → Escape (tap) / Control (hold):**

The easiest path is the built-in "Complex Modifications" library:

1. Karabiner-Elements ▸ Complex Modifications ▸ Add rule
2. Click "Find more rules on the Internet" → search "Caps Lock" or "home row"
3. Import the "Change caps_lock to control if pressed with other keys, to escape if pressed alone" rule
4. Enable it

The underlying rule lives at `~/.config/karabiner/karabiner.json`:

```json
{
  "description": "Caps Lock: tap=Escape, hold=Control",
  "manipulators": [
    {
      "from": {
        "key_code": "caps_lock",
        "modifiers": { "optional": ["any"] }
      },
      "to": [{ "key_code": "left_control" }],
      "to_if_alone": [{ "key_code": "escape" }],
      "type": "basic"
    }
  ]
}
```

**Home-row mods setup** (A=⌘, S=⌥, D=⌃, F=⇧ when held; same for J/K/L/;):

Search the Karabiner-Elements complex modifications library for "home row mods". The popular `goku`-style rules are available as importable JSON at `ke-complex-modifications` GitHub repos. The key concept: a `to_if_held_down` + `to_if_alone` manipulator per key, with a `parameters.basic.to_if_held_down_threshold_milliseconds` (typically 200ms) to prevent false triggers during fast typing.

> ⚠️ **ADVANCED:** Home-row mods have a learning curve and a frustration period of ~1-2 weeks where fast typing produces accidental modifier triggers. Tune the threshold upward (250–300ms) if you're getting false positives; tune downward if modifiers feel laggy. The Karabiner EventViewer app (`/Applications/Karabiner-Elements.app/Contents/MacOS/karabiner_observer`) shows raw HID events in real time — invaluable for debugging.

---

### Lab 4: Explore and Extend Emacs Text Bindings

1. Open any native text field (Spotlight, TextEdit, or the address bar in Safari).
2. Type a sentence. Practice: `⌃A` (line start), `⌃E` (line end), `⌃K` (kill to EOL), `⌃Y` (yank back).
3. Try `⌃T` with the cursor between two characters — watch them swap.
4. In Terminal, these same bindings apply to shell readline *unless* the terminal app's own input handling intercepts them. iTerm2 passes most through; Terminal.app honors them in its own text fields but shell readline handles them inside the prompt.

**Optional — customize with DefaultKeyBinding.dict:**

```bash
mkdir -p ~/Library/KeyBindings
# Edit ~/Library/KeyBindings/DefaultKeyBinding.dict
# (see the Home/End example in Concepts above)
# Log out and back in to activate
```

---

## Pitfalls & Gotchas

**The exact-match trap in App Shortcuts.** The most common failure. If your menu item says `Export as PDF…` (with Unicode ellipsis `…`), typing `Export as PDF...` (three periods) silently fails. Copy the menu text from the app if possible; on macOS you can right-click many text elements or use Accessibility Inspector to grab the exact string.

**System shortcut conflicts trump everything.** If a combo is reserved by the system (e.g., `⌘⇧4` for screenshots), no app shortcut assignment for that combo will work until you disable or remap the system one first.

**`hidutil` remaps are session-scoped.** They survive sleep and reboot-less re-logs, but are cleared on restart. Always pair with a LaunchAgent if you want persistence.

**Karabiner and OS updates.** Minor macOS point releases occasionally require the Karabiner driver extension permission to be re-granted. After any OS update, if your remaps stop working: System Settings ▸ Privacy & Security ▸ Driver Extensions → check if Karabiner's extension has been disabled.

**Function-key conflicts in remote sessions.** When using screen sharing or RDP, F-key signals can be intercepted by the remote session rather than the local OS. The fn-hold behavior may not translate correctly across the session boundary.

**Multiple keyboards, multiple remaps.** System Settings modifier-key remapping is per-input-device. If you use both a MacBook keyboard and an external keyboard, set your preferred remap on each device separately — they maintain independent configs.

**DefaultKeyBinding.dict and third-party apps.** The `~/Library/KeyBindings/DefaultKeyBinding.dict` file applies to Cocoa `NSTextView` only. It does not affect Electron apps (VS Code's edit fields), browser content areas, Java apps, or any app that renders its own text input. In practice: it works in Mail, Notes, TextEdit, Xcode, and most native macOS apps.

**Services menu shortcuts require restart.** After modifying a Services shortcut in System Settings, you may need to log out and back in (or at minimum restart the affected app) before the new shortcut fires.

**Conflict between Karabiner and System Settings modifier remapping.** If you've remapped Caps Lock in *both* System Settings (Modifier Keys) and Karabiner, they can interfere. Karabiner operates at a lower HID layer and sees the *pre-System-Settings* key signals. Solution: either remap in Karabiner *only*, or set System Settings to "No Action" for Caps Lock and let Karabiner handle it entirely.

---

## Key Takeaways

- macOS keyboard shortcuts follow a four-modifier hierarchy (`⌘` app, `⌥` variant, `⌃` low-level, `⇧` extend) that is predictive, not arbitrary.
- Every native Cocoa text field implements Emacs-style navigation bindings — `⌃A/E/K/Y/T/D` are available system-wide without any install.
- The **App Shortcuts** pane in System Settings can bind *any* menu command in *any* app to a key combo — exact menu title string match is required.
- Modifier key remapping (Caps Lock → Control/Escape) lives in System Settings ▸ Keyboard Shortcuts ▸ Modifier Keys; it's per-device.
- `hidutil` provides kernel-level HID remapping via command line; pairs with a LaunchAgent for persistence; remaps survive sleep but not reboot if unloaded.
- Karabiner-Elements enables dual-role keys (tap vs. hold), home-row modifiers, and complex conditional remapping — capabilities the system UI cannot provide.
- `DefaultKeyBinding.dict` in `~/Library/KeyBindings/` customizes Cocoa text navigation bindings system-wide without any third-party software.

---

## Terms Introduced

| Term | Meaning |
|---|---|
| NSResponder chain | AppKit's ordered chain of objects that receive key events; shortcuts propagate down this chain until consumed |
| NSMenu / NSMenuItem | Cocoa classes representing the menu bar; menu shortcuts are declared here and can be overridden via System Settings |
| App Shortcuts | System Settings mechanism for injecting key equivalents into any app's NSMenu by exact title match |
| `hidutil` | macOS command-line tool for querying and setting Human Interface Device (HID) properties, including key remapping |
| HID Usage ID | Numeric identifier for a physical key in the USB HID specification; used by `hidutil` remapping |
| LaunchAgent | Per-user launchd job in `~/Library/LaunchAgents/`; can run `hidutil` at login for persistent remaps |
| Karabiner-Elements | Open-source keyboard customizer that installs a kernel driver extension for low-level HID interception |
| Home-row mods | Karabiner technique where home-row keys (ASDF/JKL;) act as modifiers when held but type normally when tapped |
| DefaultKeyBinding.dict | Per-user plist in `~/Library/KeyBindings/` that overrides NSTextView's default Emacs-style key bindings |
| Globe key | The `fn` key on Apple Silicon keyboards; serves dual duty as a system-level function modifier and input source switcher |
| Services menu | Per-app sub-menu exposing system-wide actions registered by installed apps via `NSServices` in their Info.plist |
| Symbolic hotkeys | The internal macOS registry (com.apple.symbolichotkeys.plist) storing all system-level shortcut bindings |

---

## Further Reading

- **Apple Support — Mac keyboard shortcuts:** https://support.apple.com/en-us/102650 (canonical reference for all built-in shortcuts, updated for Tahoe)
- **Apple TN2450 — Remapping Keys in macOS:** https://developer.apple.com/library/archive/technotes/tn2450/_index.html (official `hidutil` hex-code reference)
- **Karabiner-Elements:** https://karabiner-elements.pqrs.org/ (docs, complex-modification library, EventViewer)
- **macOS Apple Support — Create keyboard shortcuts for apps:** https://support.apple.com/guide/mac-help/create-keyboard-shortcuts-for-apps-mchlp2271/mac
- [[00-finder-mastery]] — Finder-specific shortcuts and navigation
- [[01-window-management]] — Mission Control and Space shortcuts
- [[02-launchd-and-login-items]] — LaunchAgents as a persistence mechanism (context for hidutil agent)
