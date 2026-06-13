---
title: Text editing & system services
part: P02 GUI
est_time: 45 min read + 35 min labs
prerequisites: [00-finder-mastery, 01-window-management]
tags: [macos, text, cocoa, services, automator, shortcuts, accessibility, forensics]
---

# Text Editing & System Services

> **In one sentence:** Every standard macOS text field shares a single Cocoa text engine with built-in Emacs bindings, a programmable key-binding layer, system-wide Services, smart substitutions, data detectors, and speech — understanding the stack turns every app into a keyboard-powered editing environment.

---

## Why this matters

On Windows, per-application text editing behaviour is fragmented: each GUI toolkit (Win32, WPF, Qt, Electron) implements its own cursor movement, clipboard, and autocorrect independently. On macOS, nearly every text field — from Safari's URL bar to Xcode's editor to the Spotlight search box — is backed by the same AppKit `NSTextView`/`NSTextField` machinery. That single implementation means one set of keyboard bindings works everywhere, one `~/Library/KeyBindings/DefaultKeyBinding.dict` file reshapes the entire OS, and one Services menu surfaces context-sensitive power actions universally.

For a forensics professional this matters because text-substitution artifacts, clipboard history, spell-check suggestions, and data-detector activations all leave on-disk evidence. For a builder it means you can expose custom text-processing actions to *every* app without writing a plugin for each one.

> 🪟 **Windows contrast:** Windows has no equivalent to the Cocoa text engine. AutoHotkey fills the "global keybinding" niche but requires a persistent user-space process, has no native app-integration path, and must be configured per-machine. The Services mechanism has no Windows analogue at all.

---

## Concepts

### 1. The Cocoa Text Engine

The engine is `NSTextView` (rich text, multi-line) and `NSTextField`/`NSSecureTextField` (single-line). Both inherit from `NSResponder` and participate in the *responder chain*, which means key events flow: focused field → view → window → application → system. Most Cocoa apps get the full engine for free; exceptions are apps that embed their own text renderer (VS Code, Sublime Text, iTerm2, JetBrains IDEs) and therefore miss some or all of the features below.

The engine's on-disk format for persisted text is an `NSAttributedString` archived as `rtfd` or `rtf` in `~/Library/` (for apps like TextEdit). Scratch buffers live only in memory and the undo stack; there is no auto-recovery unless the app explicitly opts into `NSDocument`'s autosave.

#### Where the engine is NOT present

| App | Engine | Missing features |
|-----|--------|-----------------|
| VS Code | Electron (custom) | No system key bindings, no Speak Selection, no Services on selection |
| iTerm2 | Custom | Ctrl-A/E work because iTerm2 emulates them; `⌃K` yank may differ |
| JetBrains (IntelliJ, etc.) | Custom Java/Skiko | All Cocoa features absent; add via IDE plugins |
| Terminal.app | Cocoa host but pty in between | `⌃A/E/K` intercepted by shell readline, not AppKit |
| Safari web content | WebKit renderer | Cocoa bindings apply to the browser chrome, not web page inputs |

> 🔬 **Forensics note:** The presence or absence of Cocoa spell-check artifacts (`NSUserReplacementItems`, `UserDictionary.db`, Apple Spell Server logs) in `~/Library/` can tell you which text editors the user relied on and which they avoided. VS Code leaves no AppKit spellcheck history; TextEdit and Mail leave rich records.

---

### 2. Universal Emacs-Style Key Bindings

The standard AppKit key bindings are defined in:

```
/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict
```

This is a binary plist. The subset that matters daily:

#### Cursor movement

| Binding | Selector | Effect |
|---------|----------|--------|
| `⌃A` | `moveToBeginningOfLine:` | Start of line (like `Home`) |
| `⌃E` | `moveToEndOfLine:` | End of line (like `End`) |
| `⌃F` | `moveForward:` | One character forward |
| `⌃B` | `moveBackward:` | One character back |
| `⌃N` | `moveDown:` | One line down |
| `⌃P` | `moveUp:` | One line up |
| `⌥F` | `moveWordForward:` | One word forward |
| `⌥B` | `moveWordBackward:` | One word back |
| `⌘←` | `moveToLeftEndOfLine:` | Hard line start |
| `⌘→` | `moveToRightEndOfLine:` | Hard line end |
| `⌘↑` | `moveToBeginningOfDocument:` | Document top |
| `⌘↓` | `moveToEndOfDocument:` | Document bottom |

Add `⇧` to any movement binding to extend the selection. `⌥⇧F` selects the next word; `⌘⇧↓` selects to end of document.

#### Kill ring (mini-clipboard)

| Binding | Selector | Effect |
|---------|----------|--------|
| `⌃K` | `deleteToEndOfLine:` / kills into ring | Kill from cursor to line end |
| `⌃Y` | `yank:` | Paste from the kill ring |
| `⌃W` | `deleteWordBackward:` | Kill word backward |

`⌃K` followed by `⌃Y` in the same field is a move, not a copy — the kill ring is separate from the `⌘V` clipboard. This is the Emacs distinction and it trips Windows refugees repeatedly.

#### Transposition and deletion

| Binding | Selector | Effect |
|---------|----------|--------|
| `⌃T` | `transpose:` | Swap character before cursor with character after |
| `⌃D` | `deleteForward:` | Delete character forward (forward-delete) |
| `⌥⌫` | `deleteWordBackward:` | Delete previous word |
| `⌥D` | `deleteWordForward:` | Delete next word |

`⌃T` is underrated. Correct a transposition typo (`teh` → `the`) by placing the cursor between `e` and `h` and pressing `⌃T`.

#### Mark ring

| Binding | Selector | Effect |
|---------|----------|--------|
| `⌃Space` | `setMark:` | Set the mark at current cursor |
| `⌃X ⌃X` | `swapWithMark:` | Swap cursor and mark positions |

The Cocoa mark ring is shallow (one mark only) but sufficient for quick long-range selections.

---

### 3. Customising Bindings: `DefaultKeyBinding.dict`

You can override and extend the built-in bindings system-wide (for your user) by creating:

```
~/Library/KeyBindings/DefaultKeyBinding.dict
```

This is a NeXT-style or XML plist. Changes take effect at next app launch (not system-wide reboot).

**Modifier prefix characters:**

| Char | Modifier |
|------|----------|
| `^`  | Control  |
| `~`  | Option   |
| `@`  | Command  |
| `$`  | Shift    |
| `#`  | Numeric keypad |

**Example: add Emacs `⌃L` (centres insertion point in view) and full-word capitalisation:**

```
{
    /* Centre the insertion point in the visible scroll area */
    "^l" = "centerSelectionInVisibleArea:";

    /* Option-U: uppercase current word (Emacs M-u) */
    "~u" = "uppercaseWord:";

    /* Option-L: lowercase current word */
    "~l" = "lowercaseWord:";

    /* Option-C: capitalise (title-case) word */
    "~c" = "capitalizeWord:";

    /* Ctrl-X prefix (chord): Ctrl-X U = undo */
    "^x" = {
        "u"   = "undo:";
        "^s"  = "save:";
        "k"   = "performClose:";
    };
}
```

**Selector discovery:** Any method on `NSResponder` or `NSTextView` that takes a single `id sender` argument is a valid target. Explore with:

```bash
class-dump /System/Library/Frameworks/AppKit.framework/AppKit 2>/dev/null \
  | grep -E '^\- \(void\).*:\(id\)' | grep -v '[A-Z].*[A-Z].*:' | head -60
```

Or just browse Apple's `NSStandardKeyBindingResponding` protocol in the AppKit headers.

> ⚠️ **ADVANCED:** `DefaultKeyBinding.dict` conflicts with some app-internal bindings (VS Code, JetBrains ignore it entirely; Terminal.app passes through to readline). Test in TextEdit first.

---

### 4. The Services Menu

**Services** are app-provided actions that operate on the current selection (text, files, images, URLs). They appear in:

- `App menu → Services`
- Right-click contextual menu → Services submenu
- The Share button in some apps

The mechanism: when you invoke a Service, the OS sends the current selection (as NSPasteboard data) to the providing app's `NSApplication.serviceProvider`, which processes it and optionally returns replacement text.

#### Architecture

```
User selects text
   │
   ▼
NSPasteboard ("general" pasteboard, type NSPasteboardTypeString)
   │
   ▼
ServicesProvider (the app that registered the Service)
   │  runs in its own process
   ▼
Optional: sends replacement text back → inserted at selection
```

Services are registered in an app's `Info.plist` under `NSServices`. The system scans all installed apps at login and builds a cache in:

```
~/Library/Caches/com.apple.ServicesMenu.Services/
```

Force a rescan (after installing a new Quick Action):

```bash
/System/Library/CoreServices/pbs -flush
```

#### Configuring the Services menu

System Settings → Keyboard → Keyboard Shortcuts → Services

Here you can:
- Enable/disable individual services (most are off by default to keep menus manageable)
- Assign keyboard shortcuts to services you use frequently

> 🔬 **Forensics note:** The Services menu cache at `~/Library/Caches/com.apple.ServicesMenu.Services/` lists every Service-providing app the user has ever installed, even after uninstall if the cache hasn't been purged. Cross-reference with `mdls` on the cache entries to find timestamps.

---

### 5. Building Your Own Service: Quick Actions via Automator / Shortcuts

**Quick Actions** (introduced macOS 10.14) are Automator workflows saved as `.workflow` bundles into:

```
~/Library/Services/
```

They appear in the Services menu and (for file-targeted ones) in Finder's Quick Actions bar and right-click menu.

The hosting infrastructure: when a Quick Action fires, `WorkflowServiceRunner` (part of `com.apple.automator.runner`) receives the NSPasteboard payload, loads the `.workflow`, runs it through the Automator engine, and returns any output.

**Shortcuts integration:** Since macOS 12, Shortcuts can be exposed as Quick Actions. In Shortcuts.app, open a shortcut → Details → check "Use as Quick Action". Shortcuts Quick Actions replace most Automator use cases because they support JavaScript, shell scripts, and the full Shortcuts action library without needing Automator's XML workflow format.

---

### 6. System Dictionary, Look Up, and Data Detectors

#### Dictionary / Look Up

Three invocations:
- **Force Touch** the trackpad while hovering over a word (requires Force Touch hardware)
- **Three-finger tap** on a word (System Settings → Trackpad → Look Up & Data Detectors)
- `⌃⌘D` over a word in any Cocoa text view

This calls `NSSpellChecker.sharedSpellChecker()` to look up the term in the Dictionary framework (`DictionaryServices.framework`). Results draw from installed dictionaries in `/Library/Dictionaries/` and `~/Library/Dictionaries/`. The popover is a `NSPopover` subclass — it is not a new window and leaves no window server artifacts.

> 🪟 **Windows contrast:** Windows has no OS-level dictionary look-up popover. The closest analogue is right-click → Search the Web (added in Windows 11), which is network-dependent.

#### Data Detectors

`NSDataDetector` scans text for structured patterns at display time:

| Pattern | System action |
|---------|---------------|
| Phone numbers | Offer to FaceTime / call via iPhone |
| Addresses | Show in Maps |
| Dates & times | Add to Calendar |
| Email addresses | Compose in Mail |
| Flight numbers | Track in Wallet |
| Package tracking | Show tracking status |
| URLs | Underline and make tappable |

Data detectors run in the rendering pass of `NSTextView`; underlines appear automatically. The detection engine uses CoreFoundation's `CFStringTokenizer` and custom NSRegularExpression patterns maintained by Apple.

**How to interact:** Hover over a detected pattern in Mail, Notes, or Messages — a dotted underline appears. Click/tap to get the action popover. In most text fields you can right-click a detected item to see contextual actions.

**How to suppress:** Data detectors only run in subclasses that enable them (Mail, Messages, Notes, Calendar). Raw `NSTextView` does not enable them unless the developer sets `automaticDataDetectionEnabled = true`. In Terminal.app and code editors they do not activate.

> 🔬 **Forensics note:** Data detector *activations* (tapping a date to add to Calendar, a phone number to call) create artifacts in the target app's database. A Calendar event added this way has `CREATED` and `LAST-MODIFIED` stamps in `~/Library/Calendars/*.calendar/Events/*.ics` that may differ from the source email's timestamp — useful for constructing a timeline.

---

### 7. Smart Quotes, Smart Dashes, and Substitutions

#### The substitution pipeline

Every Cocoa text view passes typed text through `NSTextCheckingTypeCorrection` and `NSTextCheckingTypeQuote` in `NSSpellChecker`. This is what performs:

- `"text"` → `"text"` (smart double quotes)
- `'text'` → `'text'` (smart single quotes)
- `--` → `–` (en dash) / `---` → `—` (em dash)
- `(c)` → `©`, `(r)` → `®`, `(tm)` → `™`
- Autocorrect (red-underline words replaced on space)

The substitution state is **per-app** (stored in the app's NSUserDefaults domain) and can be toggled in `Edit → Substitutions`. System-wide defaults live at:

```bash
defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled
defaults read NSGlobalDomain NSAutomaticDashSubstitutionEnabled
defaults read NSGlobalDomain NSAutomaticSpellingCorrectionEnabled
```

#### The developer footgun

> ⚠️ **ADVANCED / DESTRUCTIVE (data-quality, not system-stability):** Pasting code, command-line arguments, or YAML/JSON into a Cocoa text field with smart quotes enabled silently replaces `"` with `"` and `"`. The resulting string looks identical but breaks every parser. This is the #1 source of "why doesn't my copied command work" on macOS for developers.

Disable globally:

```bash
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
# Also disable text completion
defaults write NSGlobalDomain NSAutomaticTextCompletionEnabled -bool false
```

Log out and back in (or `killall -9 cfprefsd` + relaunch the target app) for changes to propagate. Individual apps can still override via their own domain.

Per-document, the quickest path: `Edit → Substitutions → Smart Quotes` (toggle off for the current document/session).

---

### 8. Text Replacement / Snippets

System Settings → Keyboard → Text Replacements

Text replacements are stored in:

```
~/Library/KeyboardServices/TextReplacements.db   # SQLite, macOS 13+
# or, on older systems:
~/Library/Preferences/com.apple.symbolichotkeys.plist  # not this one
# the actual backing:
~/Library/Preferences/.GlobalPreferences.plist   # NSUserReplacementItems key (legacy)
```

Since macOS 13 (Ventura), replacements migrated to a CoreData / SQLite store under `~/Library/KeyboardServices/`. The iCloud sync mechanism pushes these via `cloudd` and the `NSUserReplacementItems` key in iCloud KV store.

#### Known sync pitfalls (current as of 2026)

- **Import ceiling:** Apple's import (drag a `.plist` to the Text Replacements list) becomes unreliable above ~200 entries. Files with 1000 entries import unpredictably; split into batches of 100 and import separately.
- **Sync stall:** If replacements don't appear on a second Mac, quit and relaunch System Settings to nudge `cloudd`. A full restart is more reliable.
- **Per-app opt-in required:** Apps using custom text views (VS Code, Electron) don't honour system replacements. Cocoa apps must call `NSTextCheckingTypeReplacement` — most do by default, but some (Xcode) deliberately suppress it for code editors.

#### Forensic value of TextReplacements.db

```bash
sqlite3 ~/Library/KeyboardServices/TextReplacements.db \
  "SELECT shortcut, phrase FROM ZREPLACEMENTITEM ORDER BY ZSHORTCUT;"
```

This reveals abbreviations that double as credential hints, personal patterns, or workflow identifiers. The `ZMODIFICATIONDATE` column (Core Data timestamp: seconds since 2001-01-01) records when each entry was last changed.

---

### 9. Spell Check and Grammar

`NSSpellChecker` is the system daemon; the backend runs in `AppleSpell.service`:

```
/System/Library/Services/AppleSpell.service/
```

User-added words live in:

```
~/Library/Spelling/LocalDictionary      # plain text, one word per line
~/Library/Spelling/en                   # learned corrections
```

Grammar checking uses `NSTextCheckingTypeGrammar` and draws on `GrammarService.framework`. Both spell and grammar check run out-of-process via XPC, which is why your app doesn't crash if the checker hangs.

**Useful defaults:**

```bash
# Show spelling and grammar by default in new documents:
defaults write NSGlobalDomain WebContinuousSpellCheckingEnabled -bool true

# Read what words you've added to your personal dictionary:
cat ~/Library/Spelling/LocalDictionary | sort
```

> 🔬 **Forensics note:** `~/Library/Spelling/LocalDictionary` and the per-language learned-word files are goldmines in an investigation. They accumulate every unusual word the user added (names, places, jargon, foreign terms) over years. These files persist through app reinstalls and survive Time Machine restores.

---

### 10. Speech: `say` and Speak Selection

#### `say` — command-line TTS

```bash
say "Hello from the terminal"
say -v "Samantha" "I speak in Samantha's voice"
say -v "?" | column -t          # list all installed voices
say -f /path/to/file.txt -o spoken.aiff   # render to AIFF
say -r 120 "Slower speech at 120 words per minute"
```

Voices are stored in:

```
/System/Library/Speech/Voices/          # system voices (read-only SIP-protected)
~/Library/Speech/Voices/                # user-installed voices
```

High-quality "Enhanced" voices must be downloaded via System Settings → Accessibility → Spoken Content → System Voice → Customize. On Apple Silicon, the `com.apple.voice.compact.*` voices use on-device neural TTS and do not require a network connection. Downloading a voice drops a `*.SpeechVoice` bundle into `/System/Library/Speech/Voices/` (managed by SoftwareUpdate, not writable directly).

```bash
# Check what voices are installed and their identifiers:
say -v "?" 2>/dev/null | awk '{print $1}' | sort -u
```

#### Speak Selection

System Settings → Accessibility → Spoken Content → Speak Selection assigns a keyboard shortcut (default `⌥⎋`) that reads aloud the current text selection in any app. The audio is synthesized by the same `say` backend (`SpeechSynthesisServer`).

**For automation and accessibility testing:**

```bash
# Send a notification and speak it:
osascript -e 'say "Build complete" using "Samantha"'

# Pipe command output to speech:
ping -c 4 8.8.8.8 | tail -1 | say
```

---

### 11. Emoji & Symbols and Accent Popovers

#### Character Viewer (`⌘⌃Space`)

Opens the floating Emoji & Symbols panel (`NSCharacterPickerController`). It is app-agnostic — the panel inserts into whichever text field has focus. Categories are customisable (gear icon → Customise List). Frequently used and recently used sections are stored in:

```
~/Library/Preferences/com.apple.CharacterPaletteIM.plist
```

The full Unicode character catalogue lives in:

```
/System/Library/Input Methods/CharacterPaletteIM.app/Contents/Resources/
```

For power users: the search field in the Character Viewer accepts Unicode names (`SNOWMAN`, `RIGHTWARDS ARROW`), code points (`U+2603`), and partial name fragments. Faster than scrolling emoji categories.

#### Accent popover (press-and-hold)

Hold any letter key in a text field to get a popover of diacritic variants (é, ê, ë, è…). The delay before the popover appears is configurable:

```bash
# Show the popover faster (default is 1500ms, value in ms):
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool true
defaults write NSGlobalDomain InitialKeyRepeat -int 15   # affects key repeat too
```

To disable the accent popover entirely (restores Windows-style key-repeat on held keys — useful for gamers or vim-style navigation in web apps):

```bash
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
```

This is a global setting; log out and back in. Chromium-based apps (Chrome, VS Code, Electron) have a per-app override:

```bash
defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false
```

---

## Hands-on (CLI & GUI)

### Verify your Cocoa key bindings are active

1. Open **TextEdit** (not Terminal — Terminal routes `⌃A/E` to readline).
2. Type a line of text.
3. Press `⌃A` — cursor jumps to start of line.
4. Press `⌃E` — cursor jumps to end.
5. Press `⌃K` — kills text from cursor to end of line.
6. Press `⌃Y` — yanks it back. If this works, the Cocoa engine is active.

### Inspect the Services menu

1. Open **TextEdit**, select a sentence.
2. Open `TextEdit menu → Services`. Note what appears.
3. Open System Settings → Keyboard → Keyboard Shortcuts → Services.
4. Scan through the available services. Enable "Search With Google" under Text. Assign `⌘⌥G`.
5. Return to TextEdit, select text, press `⌘⌥G`.

### Interrogate smart substitution state

```bash
# What's the global state?
defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled
defaults read NSGlobalDomain NSAutomaticDashSubstitutionEnabled
defaults read NSGlobalDomain NSAutomaticSpellingCorrectionEnabled

# Check a specific app's override (e.g. Notes):
defaults read com.apple.Notes NSAutomaticQuoteSubstitutionEnabled 2>/dev/null \
  || echo "No app-level override; using global"
```

### Dump text replacements

```bash
sqlite3 ~/Library/KeyboardServices/TextReplacements.db \
  "SELECT shortcut, phrase, datetime(ZMODIFICATIONDATE + 978307200, 'unixepoch', 'localtime') \
   AS modified FROM ZREPLACEMENTITEM ORDER BY ZSHORTCUT;" 2>/dev/null \
  || echo "DB not found or not readable"
```

(The `+ 978307200` converts Core Data's 2001-01-01 epoch to Unix epoch.)

### Read your personal spelling dictionary

```bash
wc -l ~/Library/Spelling/LocalDictionary
sort ~/Library/Spelling/LocalDictionary | head -30
```

### List installed TTS voices

```bash
say -v "?" | awk '{ printf "%-30s %s\n", $1, $2 }' | sort
```

---

## 🧪 Labs

### Lab 1: Custom `DefaultKeyBinding.dict`

> ⚠️ **ADVANCED:** This modifies system-wide key behaviour for your user. To roll back: `rm ~/Library/KeyBindings/DefaultKeyBinding.dict` and relaunch any open app.

**Goal:** Add word-case selectors (`⌥U` uppercase, `⌥L` lowercase, `⌥C` capitalise) and a `⌃L` centring binding.

```bash
mkdir -p ~/Library/KeyBindings
```

Create `~/Library/KeyBindings/DefaultKeyBinding.dict` with this content (write it, don't paste into a smart-quotes-enabled editor):

```
{
    "~u" = "uppercaseWord:";
    "~l" = "lowercaseWord:";
    "~c" = "capitalizeWord:";
    "^l" = "centerSelectionInVisibleArea:";
}
```

**Verify:** Quit and relaunch TextEdit. Type `hello world`, double-click `hello`, press `⌥U`. It should become `HELLO`.

**Forensics angle:** Run the following to see if a previous user left custom bindings:

```bash
ls -la ~/Library/KeyBindings/ 2>/dev/null
plutil -p ~/Library/KeyBindings/DefaultKeyBinding.dict 2>/dev/null
```

---

### Lab 2: Build a Quick Action that wraps selected text in Markdown code fences

> ⚠️ **ADVANCED:** This creates a Services-menu item visible in every Cocoa app. Rollback: delete `~/Library/Services/Wrap in Code Fence.workflow` and run `/System/Library/CoreServices/pbs -flush`.

**Option A — Automator (XML workflow):**

1. Open **Automator.app** → New Document → Quick Action.
2. "Workflow receives current" → **Text** in **any application**.
3. Add action: **Run Shell Script** (search "shell").
4. Shell: `/bin/zsh`, Pass input: **to stdin**.
5. Script body:
   ```zsh
   echo '```'
   cat
   echo '```'
   ```
6. Check "Output replaces selected text".
7. Save as `Wrap in Code Fence`.

The `.workflow` bundle lands in `~/Library/Services/`. Flush the Services cache:

```bash
/System/Library/CoreServices/pbs -flush
```

**Test:** In TextEdit (plain text mode), select `print("hello")`, right-click → Services → Wrap in Code Fence. The selection should be replaced with the fenced version.

**Option B — Shortcuts (recommended for new workflows):**

1. Open **Shortcuts.app** → New Shortcut → name it `Wrap in Code Fence`.
2. Add action: **Text** → set text to:
   ```
   ```
   [Shortcut Input]
   ```
   ```
   (Use the variable picker to insert "Shortcut Input" between the fences.)
3. Add action: **Copy to Clipboard** or (better) set as the workflow output.
4. Shortcut Details (⌘I) → Use as Quick Action → check Text.

Assign a keyboard shortcut in System Settings → Keyboard → Shortcuts → Services.

---

### Lab 3: Disable smart quotes for development work

> ⚠️ **ADVANCED:** This changes global macOS preferences. Roll back by re-enabling in System Settings → Keyboard → Text Input → Input Sources → Edit, or with `defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool true`.

```bash
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
# Flush preferences daemon:
killall -9 cfprefsd
```

**Verify:** Open TextEdit → Format → Make Plain Text. Type `"hello"`. The quotes should remain straight. Type `--`. It should remain two hyphens.

**Per-document alternative:** `Edit → Substitutions → Smart Quotes` toggles the setting for the current document/session without touching global defaults.

---

### Lab 4: Add and test text replacements

1. System Settings → Keyboard → Text Replacements → `+`.
2. Add: Replace `;;dt` with the literal string `datetime.datetime.now().isoformat()`.
3. In TextEdit (plain text mode), type `;;dt` followed by a space. It should expand.
4. Confirm it's in the database:

```bash
sqlite3 ~/Library/KeyboardServices/TextReplacements.db \
  "SELECT shortcut, phrase FROM ZREPLACEMENTITEM WHERE shortcut=';;dt';"
```

5. Test it does NOT expand in VS Code (expected: no expansion, confirming Electron bypass).

---

### Lab 5: Forensic text-artifact sweep

This lab simulates the artifact collection you'd do on a target Mac in an investigation.

```bash
#!/bin/zsh
TARGET_USER="${1:-$(whoami)}"
BASE="/Users/$TARGET_USER"

echo "=== Personal Dictionary ==="
wc -l "$BASE/Library/Spelling/LocalDictionary" 2>/dev/null
head -20 "$BASE/Library/Spelling/LocalDictionary" 2>/dev/null

echo ""
echo "=== Text Replacements ==="
sqlite3 "$BASE/Library/KeyboardServices/TextReplacements.db" \
  "SELECT shortcut, phrase FROM ZREPLACEMENTITEM ORDER BY ZSHORTCUT;" 2>/dev/null

echo ""
echo "=== Custom Key Bindings ==="
if [[ -f "$BASE/Library/KeyBindings/DefaultKeyBinding.dict" ]]; then
  plutil -p "$BASE/Library/KeyBindings/DefaultKeyBinding.dict"
else
  echo "(none installed)"
fi

echo ""
echo "=== Smart Quote / Autocorrect State ==="
defaults read "$BASE/Library/Preferences/.GlobalPreferences.plist" \
  NSAutomaticQuoteSubstitutionEnabled 2>/dev/null || echo "not set (default on)"
defaults read "$BASE/Library/Preferences/.GlobalPreferences.plist" \
  NSAutomaticSpellingCorrectionEnabled 2>/dev/null || echo "not set (default on)"

echo ""
echo "=== Installed Quick Action Services ==="
ls -la "$BASE/Library/Services/" 2>/dev/null

echo ""
echo "=== Character Picker Recent Emoji ==="
plutil -p "$BASE/Library/Preferences/com.apple.CharacterPaletteIM.plist" 2>/dev/null \
  | grep -A2 'Recent' | head -20
```

Save as `text-artifact-sweep.sh`, `chmod +x`, run. On your own Mac it gives baseline data; on an acquired disk image mounted at a non-standard path, substitute the mount point for `/Users`.

> 🔬 **Forensics note:** `LocalDictionary` and `TextReplacements.db` are not encrypted and survive most user-facing "reset" operations. They are NOT cleared by "Erase All Content and Settings" on macOS (which is primarily targeted at iOS behaviour); on macOS that option is rare anyway. They ARE cleared by a full reinstall or targeted `defaults delete`.

---

## Pitfalls & Gotchas

**1. Smart quotes in config files.** The single most common macOS text gotcha for developers. Any tutorial that says "paste this into Terminal" and involves copied text from a Safari page will silently corrupt `"` characters if you paste into a smart-quote-enabled field first, then copy back. Paste directly from the web page to Terminal, or disable smart quotes globally.

**2. `⌃Space` conflict.** `⌃Space` is both the Cocoa `setMark:` binding *and* the default shortcut for switching input sources (System Settings → Keyboard → Shortcuts → Input Sources). If you have multiple keyboards/input sources enabled, `⌃Space` switches them and the mark never gets set. Remap one or the other.

**3. Services don't appear.** New Quick Actions require a Services cache flush (`/System/Library/CoreServices/pbs -flush`) AND a Finder restart (`killall Finder`). Sometimes also a logout/login. The cache at `~/Library/Caches/com.apple.ServicesMenu.Services/` is not user-editable — don't touch it manually.

**4. Text replacements don't fire in all apps.** VS Code, Electron apps, JetBrains IDEs, iTerm2 — none honour system text replacements. Use the IDE's own snippet system (VS Code snippets, JetBrains Live Templates) in those environments.

**5. `⌃K` in Terminal kills the entire line.** In Terminal.app (or iTerm2) over a pty, `⌃K` is intercepted by the shell's readline (Zsh or Bash) as "kill to end of line into the *readline* kill ring". The Cocoa yank buffer and readline kill ring are separate. `⌃Y` in the terminal yanks from readline's ring, not Cocoa's. Both work, but they don't cross-pollinate.

**6. DefaultKeyBinding.dict is per-user and per-login session.** If you `sudo su` to another user in a terminal, the other user's key bindings apply to their Cocoa apps, not yours.

**7. Force Touch look-up requires Force Touch hardware.** MBP with Touch Bar era Macs that had the butterfly keyboard + flat trackpad may have a non-Force-Touch trackpad in certain configurations. The three-finger tap look-up is the universal fallback.

**8. TTS voices download silently in background.** When you install a new voice in System Settings → Accessibility → Spoken Content, `storeagent` downloads it in the background. `say -v "Newly Installed Voice"` may fail for 30–60 seconds while the download completes.

---

## Key Takeaways

- The Cocoa text engine is universal across nearly all macOS apps; ~25 Emacs-style `⌃`/`⌥`/`⌘` bindings work in every standard text field from the login window to Final Cut's title editor.
- `~/Library/KeyBindings/DefaultKeyBinding.dict` lets you remap or extend any selector system-wide, with chord support and action lists, without a background process.
- The Services menu / Quick Actions mechanism is macOS's answer to AutoHotkey: a declared, sandboxable, app-integrated pipeline that routes selections to arbitrary processing logic and returns replacement text.
- Smart quotes and autocorrect are enabled by default and are a silent data-quality hazard for developers; disable globally or per-document before pasting code anywhere.
- Text substitution artifacts (`TextReplacements.db`, `LocalDictionary`, `CharacterPaletteIM.plist`, `DefaultKeyBinding.dict`) persist across app reinstalls and reveal long-term user habits and terminology patterns.
- `say -v "?" | column -t` + the Accessibility spoken-content pane give you full programmatic access to on-device neural TTS without network dependency on Apple Silicon.

---

## Terms Introduced

| Term | Definition |
|------|------------|
| `NSTextView` | AppKit class implementing the rich-text editing engine; subclasses `NSTextField` and `NSSecureTextField` for single-line use |
| `NSResponder` | Base class for objects that handle events in the Cocoa responder chain |
| Responder chain | Ordered sequence (view → window → app) through which key events propagate until handled |
| `NSSpellChecker` | Singleton that coordinates spell checking, grammar, autocorrect, and smart substitutions |
| `AppleSpell.service` | Out-of-process XPC service providing the actual spell and grammar checking engine |
| Kill ring | Emacs-style clipboard for `⌃K`/`⌃Y` kill-and-yank; separate from the system `⌘C`/`⌘V` clipboard |
| `DefaultKeyBinding.dict` | User-writable plist in `~/Library/KeyBindings/` that overrides or extends the Cocoa key binding table |
| Selector | Objective-C method name (e.g. `moveToBeginningOfLine:`) used as a target in key binding dictionaries |
| Quick Action | Automator workflow or Shortcuts shortcut saved to `~/Library/Services/` and surfaced in the Services menu |
| `NSDataDetector` | Foundation class that recognises phone numbers, addresses, dates, URLs, and other structured patterns in text |
| `WorkflowServiceRunner` | Automator daemon that hosts Quick Action workflows on behalf of the Services infrastructure |
| `pbs` | `pbs` (Pasteboard Server) utility at `/System/Library/CoreServices/pbs`; `-flush` rebuilds the Services cache |
| `TextReplacements.db` | SQLite store in `~/Library/KeyboardServices/` holding system text replacement shortcuts |
| `LocalDictionary` | Plain-text file in `~/Library/Spelling/` containing user-added words for spell check |
| `say` | BSD-layer CLI tool invoking the Speech Synthesis Manager; outputs audio to speaker or AIFF file |
| Data detector | Runtime pattern scanner that annotates recognised text (dates, addresses, etc.) with actionable underlines |
| Smart quotes | Automatic substitution of straight `"` / `'` with typographic `"` `"` / `'` `'` during typing |

---

## Further Reading

- [Apple Developer: Text System Defaults and Key Bindings](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TextDefaultsBindings/TextDefaultsBindings.html) — the canonical reference for `DefaultKeyBinding.dict` format and selector names
- [jrus/cocoa-text-system on GitHub](https://github.com/jrus/cocoa-text-system) — the most thorough community documentation of the Cocoa text system, including the full selector catalogue and `KeyBindings/` examples
- [Howard Oakley — Quick Actions: How they work (Eclectic Light)](https://eclecticlight.co/2019/02/08/quick-actions-4-how-they-work/) — detailed look at the `WorkflowServiceRunner` architecture
- [TidBITS: Bring macOS Text Replacements Back to Life (Feb 2025)](https://tidbits.com/2025/02/10/tipbits-bring-macos-text-replacements-back-to-life/) — practical troubleshooting for sync failures
- [TidBITS: Text Replacement Export/Import (May 2026)](https://tidbits.com/2026/05/04/macos-text-replacement-export-import-works-great-until-it-doesnt/) — the import-ceiling and batch-workaround findings
- [ss64: `say` man page and flags reference](https://ss64.com/mac/say.html) — complete flag reference with examples
- `man NSTextView` is not a man page, but `open x-man-page://NSStandardKeyBindingResponding` works in Terminal to pull the framework header commentary
- [[00-finder-mastery]] — Finder's contextual menu is where file-targeted Quick Actions surface most visibly
- [[01-window-management]] — the Services menu and key bindings layer on top of the window focus model
