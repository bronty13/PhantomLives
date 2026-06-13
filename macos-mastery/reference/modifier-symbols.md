---
title: Modifier-symbol legend
part: Reference
tags: [macos, keyboard, reference, symbols, modifiers, switcher]
---

# Modifier-symbol legend

> **In one sentence:** macOS menus, documentation, and community posts are written in a compact glyph shorthand — this page is your Rosetta Stone.

---

## The modifiers at a glance

| Glyph | Name | Key label(s) | Unicode | Windows nearest equiv |
|-------|------|-------------|---------|----------------------|
| `⌘` | **Command** | `⌘` or `cmd` | U+2318 | `Ctrl` (for app shortcuts) |
| `⌥` | **Option** | `⌥` or `alt` | U+2325 | `Alt` |
| `⌃` | **Control** | `ctrl` or `^` | U+2303 | `Ctrl` (low-level sense) |
| `⇧` | **Shift** | `shift` or `⇧` | U+21E7 | `Shift` |
| `⇪` | **Caps Lock** | `caps lock` | U+21EA | `Caps Lock` |
| `fn` / `🌐` | **Function / Globe** | `fn` or globe icon | — | `Fn` (though Globe is unique to Apple) |
| `⏏` | **Eject** | Eject (external keyboards) | U+23CF | (no direct equiv; CD drives gone) |

> 🪟 **Windows contrast:** The single most confusing mapping for switchers: on macOS, `⌘` (Command) does what `Ctrl` does on Windows for *application-level shortcuts* — Copy, Paste, Save, Undo. But macOS *also* has `⌃` (Control), which is largely reserved for low-level terminal signals and Emacs-style text-cursor movement. The Windows `Ctrl` is thus *split* onto two different keys. Meanwhile, `⌥` (Option) does what `Alt` does on Windows, and `⌘` has no Windows-key equivalent on a Mac. See [[windows-to-macos]] for the full translation table.

---

## Non-modifier key glyphs

These appear in menu shortcut annotations and in documentation:

| Glyph | Key | Notes |
|-------|-----|-------|
| `↩` | **Return** | The large return key; sends carriage return / newline |
| `⌤` | **Enter** | Numeric-keypad Enter; used as a distinct key in some apps (e.g., rename in Finder) |
| `⌫` | **Delete** (Backspace) | Deletes *backward* — what Windows calls Backspace |
| `⌦` | **Forward Delete** | Deletes *forward* — what Windows calls Delete; absent on compact keyboards |
| `⇥` | **Tab** | Forward tab |
| `⇤` | **Backtab** | Reverse tab; typically triggered with `⇧⇥` |
| `⎋` | **Escape** | Cancel / dismiss |
| `↑↓←→` | **Arrow keys** | Navigation; combine with modifiers for selection / word-jump |
| `⇞` | **Page Up** | On compact keyboards: `fn ↑` |
| `⇟` | **Page Down** | On compact keyboards: `fn ↓` |
| `↖` | **Home** | Jump to start of document/line; on compact: `fn ←` |
| `↘` | **End** | Jump to end of document/line; on compact: `fn →` |
| `⌧` | **Clear** | Numeric keypad clear; rare in modern use |
| `⏿` | **Power** | Appears in deep docs; on modern Macs = Touch ID button |
| `␣` or `Space` | **Space** | Written out in shortcut lists |

> 🔬 **Forensics note:** The distinction between Return (`↩`, U+000D) and Enter (`⌤`, U+0003) matters when reading key-event logs from tools like `ioreg`, `hidutil monitor`, or third-party keylogger forensics artifacts. They are different HID usages (0x28 vs. 0x58) and different NSEvent `keyCode` values (36 vs. 76). A suspicious macro or automation tool that remaps Enter→Return (or vice versa) will leave a trace in Karabiner-Elements' JSON config or in a `hidutil` launchd plist under `/Library/LaunchDaemons/` or `~/Library/LaunchAgents/`.

---

## The ⌘ Command glyph — origin and Unicode

The cloverleaf `⌘` (U+2318) is called the **"place of interest sign"** or **"loop square"** in Unicode. It originally appeared on Scandinavian road signs marking tourist attractions, and was adopted by Susan Kare for the original Mac keyboard in 1984 to avoid overloading the Apple logo in menus. It appears on Apple keyboard keycaps and in every macOS menu bar.

The Apple logo `` (U+F8FF, in the Private Use Area) is *not* in standard Unicode and will not render on non-Apple systems without the correct font. To type it: **`⌥ Shift 2`** on a US keyboard layout.

---

## The fn / Globe key in depth

On all Apple Silicon MacBooks and the Magic Keyboard with Touch ID (2021+), the `fn` key is simultaneously the **Globe key** (`🌐`). A physical globe icon is printed on the key itself. Its behaviors:

| Action | Result | Configurable? |
|--------|--------|---------------|
| **Tap once** | Dictation OR emoji picker OR change input source (system choice) | Yes — System Settings ▸ Keyboard ▸ "Press fn key to" |
| **Hold + F1–F12** | Send true F-key signal (bypasses brightness/volume/etc.) | Toggled globally by "Use F1, F2, etc. as standard function keys" |
| **`fn ↑`** | Page Up | No (hardware) |
| **`fn ↓`** | Page Down | No (hardware) |
| **`fn ←`** | Home | No (hardware) |
| **`fn →`** | End | No (hardware) |
| **`fn E`** | Open Emoji & Symbols picker | No |
| **`fn D`** | Toggle Do Not Disturb | No |
| **`fn C`** | Toggle Focus mode | No |
| **`fn ⇧ A`** | Show/hide Apps (macOS 26 Tahoe; replaces Launchpad gesture) | No |
| **`fn ⌃ F`** (some configs) | Toggle full screen | System Settings variant |

The system setting lives at **System Settings ▸ Keyboard ▸ Keyboard** under "Press fn (🌐) key to" with choices: Do Nothing, Change Input Source, Show Emoji & Symbols, Start Dictation, or Show/Hide Cursor.

On an external full-size keyboard without a Globe key, `fn` is absent entirely; true F-key behavior is controlled by the "Use F1, F2… as standard function keys" toggle, and emoji is accessed via `⌃⌘Space`.

---

## The Mac ↔ Windows modifier mapping, in full

This is the source of most switcher confusion. The concepts map, but not one-to-one:

| Intent | Windows | macOS | Notes |
|--------|---------|-------|-------|
| App commands (Copy, Paste, Save…) | `Ctrl` | `⌘` (Command) | The big one. Every `Ctrl+X` muscle reflex must become `⌘X`. |
| Alternate / variant | `Alt` | `⌥` (Option) | Mostly 1-to-1. `⌥` also produces special characters when combined with letter keys — `⌥G` = `©`, `⌥R` = `®`, etc. |
| Low-level / terminal / Emacs | `Ctrl` (in terminal) | `⌃` (Control) | On macOS, `⌃` is mostly *not used* for app shortcuts and is instead given to: terminal signals (`⌃C` = SIGINT, `⌃Z` = SIGTSTP), Emacs text movement (`⌃A` = line start, `⌃E` = line end, `⌃K` = kill to EOL) in every text field, and a handful of system shortcuts. |
| Extend selection | `Shift` | `⇧` (Shift) | 1-to-1. |
| Context menu | Right-click or `⇧F10` | Right-click or `⌃-click` | `⌃-click` = right-click in macOS, not just terminal. |
| Windows / Super key | `⊞ Win` | *(none)* | macOS has no equivalent; Spotlight (`⌘Space`) is the nearest functional substitute. |
| Toggle F-key layer | `Fn` (laptops) | `fn` / 🌐 | On macOS, holding `fn` converts media keys to true F-keys. |

> 🪟 **Windows contrast:** On Windows, `Ctrl+Alt+Delete` is a hard-wired security attention sequence handled by the kernel (the Secure Attention Sequence). macOS has no exact equivalent — `⌘⌥⎋` opens Force Quit (the nearest analog to `Ctrl+Alt+Delete` for killing a frozen app), and `⌃⌥⌘ Power` forces an immediate system shutdown with no dialog.

---

## How menus display shortcuts

In every macOS menu bar item, the right side of a menu entry shows its shortcut in modifier-glyph notation, right-to-left: modifiers first (in order ⌃⌥⇧⌘), then the key. Examples:

```
Save           ⌘S
Save As…       ⇧⌘S
Undo           ⌘Z
Redo           ⇧⌘Z
Force Quit     ⌥⌘⎋
Quit All       ⌥⌘Q
Paste and Match Style  ⌥⇧⌘V
```

The standard modifier display order in Apple's Human Interface Guidelines is: `⌃ ⌥ ⇧ ⌘`. So a shortcut involving all four reads `⌃⌥⇧⌘K`. In practice, most shortcuts use only one or two modifiers.

### Decoding a shortcut notation step-by-step: `⌥⌘⎋`

1. `⌥` — hold Option
2. `⌘` — hold Command (still holding Option)
3. `⎋` — press Escape (while holding both)
4. Result: **Force Quit Applications** dialog opens

This is macOS's equivalent of Windows' `Ctrl+Alt+Delete` → Task Manager.

---

## Typing special characters with Option

`⌥` (Option) is the Mac's "compose key" for special characters. On a US layout, common ones worth memorizing:

| Shortcut | Character | Name |
|----------|-----------|------|
| `⌥-` | `–` | En dash |
| `⌥⇧-` | `—` | Em dash |
| `⌥8` | `•` | Bullet |
| `⌥G` | `©` | Copyright |
| `⌥R` | `®` | Registered trademark |
| `⌥2` | `™` | Trademark |
| `⌥⇧2` | `€` | Euro |
| `⌥3` | `£` | Pound |
| `⌥\`` + vowel | `à è ì ò ù` | Grave accent (dead key) |
| `⌥E` + vowel | `á é í ó ú` | Acute accent (dead key) |
| `⌥U` + vowel | `ä ë ï ö ü` | Umlaut (dead key) |
| `⌥I` + vowel | `â ê î ô û` | Circumflex (dead key) |
| `⌥N` + vowel | `ã ñ õ` | Tilde (dead key) |
| `⌥⇧K` | `` | Apple logo (renders only on Apple platforms) |

> 🔬 **Forensics note:** The `⌥⇧K` Apple logo (U+F8FF) appearing in a document is a reliable platform indicator — it only renders correctly on macOS/iOS with the system font. Its presence in a recovered file proves the file was authored or edited on an Apple device with the relevant keyboard layout active.

---

## Typing the modifier symbols themselves

To insert a `⌘` or `⌥` glyph in a document or message:

- **Emoji & Symbols picker** (`fn E` or `⌃⌘Space`), search "command" or "option" — they appear under Technical Symbols.
- **Character Viewer:** In any text field with the picker open, click the grid icon (top right) to expand to full Character Viewer. Search by Unicode name: "PLACE OF INTEREST SIGN" (⌘), "OPTION KEY" (⌥), "UP ARROWHEAD" (⌃), "UPWARDS WHITE ARROW" (⇧).
- **Direct Unicode input:** Hold `⌃⌘Space` to open the picker, or use a text expander snippet.

---

## Quick-reference table: all glyphs at a glance

```
MODIFIERS
⌘   Command     — app commands; ≈ Ctrl on Windows
⌥   Option      — variants; ≈ Alt on Windows  
⌃   Control     — terminal/Emacs; ≈ low-level Ctrl
⇧   Shift       — extend/reverse
⇪   Caps Lock   — (rarely used in shortcuts)
fn  Globe / Fn  — function-key layer; emoji; dictation

KEYS
↩   Return          ⌤  Enter (numpad)
⌫   Delete (back)   ⌦  Forward Delete
⇥   Tab             ⇤  Backtab (⇧⇥)
⎋   Escape          ␣  Space
↑↓←→ Arrow keys
⇞   Page Up  (fn ↑) ⇟  Page Down (fn ↓)
↖   Home     (fn ←) ↘  End       (fn →)
⏏   Eject

COMMON COMPOUND SHORTCUTS
⌘Z        Undo          ⇧⌘Z     Redo
⌘X/C/V    Cut/Copy/Paste
⌥⌘V       Paste and Match Style
⌘Q        Quit          ⌥⌘Q     Quit All
⌘W        Close window  ⌥⌘W     Close all windows
⌘H        Hide          ⌥⌘H     Hide others
⌘M        Minimize
⌘⇥        App switcher  ⌘⇧⇥     Reverse app switcher
⌘`        Next window (same app)
⌘Space    Spotlight
⌃⌘Space   Emoji picker  fn E    Emoji picker (Globe)
⌥⌘⎋      Force Quit
⌃⌥⌘⏏    Shutdown immediately (no dialog)
⌘,        App Preferences / Settings
⌘.        Cancel (= Escape in dialogs)
⌘⌥D      Toggle Dock auto-hide
⌃⌘Q      Lock screen immediately
```

---

## Related references

- [[keyboard-shortcuts]] — System-wide and per-app shortcut master sheet
- [[windows-to-macos]] — Complete concept-to-concept translation table
- [[04-keyboard-shortcuts-and-customization]] — Full lesson on the modifier hierarchy, Emacs bindings, hidutil remapping, and Karabiner-Elements
- [[05-text-editing-and-services]] — How Option + arrow/delete shortcuts work in every text field
