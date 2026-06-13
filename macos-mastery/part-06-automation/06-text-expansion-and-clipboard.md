---
title: Text expansion & clipboard managers
part: P06 Automation & Productivity
est_time: 40 min read + 40 min labs
prerequisites: [02-applescript-and-jxa, 05-launchers-raycast-alfred]
tags: [macos, automation, productivity, text-expansion, clipboard, espanso, raycast, maccy]
---

# Text expansion & clipboard managers

> **In one sentence:** Two of the highest-ROI productivity investments on macOS are a text expander (turn short triggers into long, dynamic text) and a clipboard manager (turn your clipboard from a single-slot buffer into a searchable, persistent library) — understanding the mechanism behind each lets you choose the right tool and avoid the security traps that catch people off-guard.

## Why this matters

Every time you type your email address, paste a boilerplate contract clause, re-enter a support ticket template, or lose a copied URL because you copied something else, you are paying an invisible tax in keystrokes and cognitive context-switching. A forensics professional running investigations has an additional dimension: reproducing exact command strings, case numbers, chain-of-custody boilerplate, and standardized report headers dozens of times per day with zero transcription error.

Text expansion addresses the authoring problem. Clipboard management addresses the retrieval problem. Together they compound: your expanded snippets can reference clipboard contents, and your clipboard manager can store snippet output for later reuse.

Neither tool is glamorous, but a day-one investment in getting them right produces compounding returns for the lifetime of the machine.

---

## Concepts

### 1. The macOS built-in: Text Replacements

**Where it lives:** System Settings → Keyboard → Text Replacements (macOS 13+). Internally, these are stored as an array of `{phrase, shortcut}` dicts in `~/Library/KeyboardServices/TextReplacements.db` (SQLite, introduced Ventura) and synced via iCloud Drive.

**The mechanism:** `KeyboardServices` (a system daemon, part of the Input Methods stack) intercepts keystrokes at the CGEvent level and watches for trigger matches. When it sees a trigger string followed by a word-boundary character (space, return, punctuation), it synthesises a sequence of backspace events followed by the expansion text. This happens below the app — no app cooperation is required.

**What works:** Any Cocoa `NSTextView`-backed field — Mail, Notes, Pages, Safari URL bar, Finder rename, most native Mac apps. Text Replacements also propagate to iPhone/iPad automatically when iCloud Drive is on and the same Apple ID is signed in.

**What does not work:**
- Non-Cocoa text fields: Electron apps (VS Code, Slack, Discord) use their own input stack and frequently ignore system-level text substitution.
- Many web forms (Chrome, Firefox, Chromium-based browsers) — the CGEvent injection does not land in the browser renderer process.
- Terminal emulators — raw TTY input bypasses all Input Method infrastructure.
- No support for dynamic content (today's date, cursor positioning, clipboard contents, fill-in fields, or scripts).

**Export/backup:** System Settings has no native export button. Use `defaults export com.apple.TextReplacementService ~/Desktop/text-replacements.plist` to dump the UserDefaults layer, but the canonical store is the SQLite DB. For a scriptable backup:

```bash
# Exports the current replacement list in readable form
sqlite3 ~/Library/KeyboardServices/TextReplacements.db \
  "SELECT shortcut, phrase FROM TSReplacementEntry ORDER BY shortcut;" \
  | column -t -s '|'
```

> 🪟 **Windows contrast:** Windows has no built-in text expansion at all (the autocomplete in Office is app-specific, not system-wide). Windows power users reach for PhraseExpress (commercial, very full-featured, macro scripting) or the free AutoHotkey text replacement mode. Win+V provides clipboard history, but it is OS-level only and has no ecosystem integration or programmatic exclusions.

> 🔬 **Forensics note:** `TextReplacements.db` is a legitimate persistence artifact. Malware has been observed adding trigger→payload expansions here to silently alter text typed in sensitive fields (e.g., replacing a crypto wallet address abbreviation with an attacker-controlled address). Baseline the DB hash during incident response, and check `TSReplacementEntry` for unexpected entries. On an imaged drive, look at `Users/<user>/Library/KeyboardServices/TextReplacements.db`.

---

### 2. Espanso — the open-source text expander

Espanso is a cross-platform, open-source text expander written in Rust. It supports macOS (Apple Silicon native via Universal binary), Windows, and Linux, and stores all configuration in plain YAML — diffs cleanly in git, deploys identically on every machine.

**Architecture on macOS:** Espanso runs as a menu bar background process. It injects text using one of two backends:
- **Injection backend (default):** synthesises `CGEventPost` key events — faster, but blocked in secure text fields (password prompts) and some Electron apps.
- **Clipboard backend (configurable per-match):** writes the expansion to the system clipboard, then synthesises Cmd+V — bypasses injection restrictions, works in most apps, but briefly clobbers clipboard contents (Espanso restores the previous clipboard after ~300 ms).

Espanso intercepts keystrokes via the macOS `CGEventTap` API (requires Accessibility permission, granted once in System Settings → Privacy & Security → Accessibility).

**Config directory:**
```
~/Library/Application Support/espanso/
├── config/
│   └── default.yml       # global settings (backend, exclude_apps, …)
└── match/
    └── base.yml           # your snippet matches (and any extra *.yml files)
```

Run `espanso path` to confirm the exact path on your install.

**Match anatomy:**

```yaml
# match/base.yml
matches:
  # Simple replacement
  - trigger: ";em"
    replace: "robert.olen@gmail.com"

  # Multiline (| preserves newlines)
  - trigger: ";sig"
    replace: |
      Robert Olen
      Senior Forensic Analyst
      robert.olen@gmail.com

  # Dynamic date (strftime format)
  - trigger: ";date"
    replace: "{{today}}"
    vars:
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"

  # Date math — report date + 30 days
  - trigger: ";due30"
    replace: "{{due}}"
    vars:
      - name: due
        type: date
        params:
          format: "%Y-%m-%d"
          offset: 2592000   # seconds; 30 days = 30*24*3600

  # Cursor positioning after expansion
  - trigger: ";todo"
    replace: "TODO($|$): fix before release"
    # $|$ places the cursor at that position after expansion

  # Clipboard injection — paste current clipboard into template
  - trigger: ";bug"
    replace: "Bug reference: {{clipboard}}\nReproduction steps:\n1. "
    vars:
      - name: clipboard
        type: clipboard

  # Shell script output
  - trigger: ";uuid"
    replace: "{{uuid}}"
    vars:
      - name: uuid
        type: shell
        params:
          cmd: "uuidgen | tr -d '\n'"

  # Form — interactive fill-in dialog
  - trigger: ";ticket"
    replace: "Case: {{case_number}} | Analyst: {{analyst}} | Date: {{today}}"
    vars:
      - name: case_number
        type: form
        params:
          layout: "Case number: {{case_number}}"
      - name: analyst
        type: form
        params:
          layout: "Analyst name: {{analyst}}"
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"
```

**Per-app config:** Create `config/slack.yml` with `filter_title: "Slack"` (or `filter_class`, `filter_exec`) to activate a different match set only in Slack. This lets you have app-scoped snippets — e.g., Jira formatting in Jira, Markdown in your text editor.

**Regex triggers:**
```yaml
- regex: ";upper(?P<word>.+)"
  replace: "{{word_upper}}"
  vars:
    - name: word_upper
      type: shell
      params:
        cmd: "echo '{{word}}' | tr '[:lower:]' '[:upper:]'"
```

**Secure input caveat:** macOS blocks all `CGEventTap` listeners (including Espanso) while Secure Keyboard Entry is active (any password prompt, 1Password, some banking sites). This is intentional OS behaviour, not a bug. Espanso shows a lock icon in the menu bar when blocked. Switch to the clipboard backend for those contexts if needed.

---

### 3. Commercial and launcher-bundled alternatives

| Tool | Pricing | Snippet model | Dynamic content | Team sync |
|---|---|---|---|---|
| **TextExpander** | $4.16/mo (personal) | .textexpander bundles, GUI editor | Date math, fill-ins, optional snippets, AppleScript, shell | Shared group libraries — the main enterprise sell |
| **Keyboard Maestro** | $36 one-time | Macro actions, typed-string trigger | Full scripting, clipboard, prompt dialogs, AppleScript | No native team sync |
| **Alfred** (Powerpack) | £34 one-time | Plain text or rich text snippets | Date tokens only, no scripting in snippets | iCloud sync between your own Macs |
| **Raycast** (free tier) | Free | Plain/rich text snippets, Markdown | Date tokens | iCloud sync, team sharing on Teams plan ($10/mo) |
| **Espanso** | Free / open-source | YAML matches | Shell, date, form, clipboard, regex | Git-tracked YAML — sync however you like |

**Raycast snippets (free):** Raycast → Snippets → + New Snippet. Triggered either by a keyword typed anywhere (if the background listener is enabled) or via the Raycast window itself. Expansion has ~50–100 ms more latency than native tools because it routes through the Raycast process. Sufficient for boilerplate; not ideal for high-frequency rapid typing.

**TextExpander** wins for team/enterprise scenarios: a shared library admin can update a snippet (e.g., a legal disclaimer that changes) and every team member's client pulls the update automatically. The `.textexpander` bundle format is just a JSON-wrapped ZIP.

**Keyboard Maestro** is worth mentioning because many heavy Mac users already have it for other automation; its "Insert Text by Typing" and "Insert Text by Pasting" actions are extremely powerful as part of larger macros (e.g., "when I press ⌃⌥T: activate Terminal, `cd ~/investigations`, paste today's ISO date as dir name, press Return").

---

### 4. Dynamic snippet patterns worth knowing

**Date arithmetic** is the most-requested feature not in the built-in system. Espanso handles it natively; TextExpander has a date math editor. In a pinch, a Keyboard Maestro shell action or Alfred workflow can do the same.

**Clipboard-as-variable** lets you write a template that slots in whatever you last copied. Useful for forensics: copy a file hash from a tool, trigger `;sha256line` to wrap it in a standardised evidence note.

**Cursor placement** (`$|$` in Espanso) saves a keystroke-and-click navigation after every expansion. For a snippet that ends with `grep -r "" /path/to/evidence`, placing the cursor inside the quotes is the difference between the snippet feeling seamless vs. requiring manual repositioning.

**Nested snippets / chained variables:** Espanso evaluates `vars` top-to-bottom, so you can reference an earlier variable in a later one. TextExpander has nested snippet calls. Both let you build compound outputs from simpler atoms.

**Shell-powered snippets** are where Espanso diverges sharply from the system built-in. Any CLI tool becomes a snippet: `mdls -n kMDItemLastUsedDate "$file"`, `git log --oneline -1`, `osascript -e 'return (POSIX path of (path to frontmost application))'`. These run synchronously at expansion time; keep them fast (sub-100 ms) or the keystroke-to-text lag becomes noticeable.

---

### 5. Clipboard managers — why one slot is not enough

The system clipboard is a single named pasteboard (`NSGeneralPasteboard`) with multiple concurrent representations (plain text, rich text, HTML, TIFF, custom UTIs) for a single logical "item." When you copy something new, the previous content is gone with no recovery mechanism.

A clipboard manager installs an `NSPasteboard` change-count watcher (polling every ~250 ms, or using `NSPasteboardDidChangeNotification` where available) and snapshots each new clipboard item to a local store. This store becomes searchable, pinnable, and navigable.

**Key features to evaluate:**

| Feature | Why it matters |
|---|---|
| History size | 100 items is not enough for a heavy day; 500–unlimited is better |
| Fuzzy search | Recall a clip you only partially remember |
| Plain-text paste | Strip rich formatting before pasting |
| Pin / favorite | Permanent clips that survive history rotation |
| Sync | Cross-device (iCloud or cloud) vs. local-only |
| Exclusion rules | Security (see below) |
| Image & file support | Copy a screenshot or file path — some tools store these too |
| Merge clips | Combine multiple clips into one paste |

**Major options:**

- **Maccy** (free, open-source, MIT, v2.6.1 as of late 2025): `brew install maccy`. Minimal, keyboard-first, fast. Menu bar popup via configurable hotkey (default `⌘⇧V`). Fuzzy search. Pins. Plain-text-only paste. Stores locally in `~/Library/Application Support/Maccy/Storage.sqlite`. No iCloud sync in the free build, no image-to-image paste (images stored as thumbnails). Requires macOS 14+.

- **Raycast Clipboard History** (free, built into Raycast): Activated via `⌘⇧V` (configurable) inside Raycast or the dedicated hotkey. Includes images, files, links. Fuzzy search with type filters. No inter-device sync on free plan. If you already run Raycast, this eliminates the need for a separate app.

- **Paste** ($3.99/mo or $24.99/yr): iCloud-synced across Macs and iPhones/iPads. Strong visual browser, drag-to-reorder, "Pinboards" for permanent collections, smart categories. The most polished option; the subscription price reflects it.

- **Alfred Clipboard History** (Powerpack): Integrates with Alfred workflows, supports Snippets in the same interface, text transform actions. Local-only unless you sync `Alfred.alfredpreferences` via Dropbox/iCloud.

- **Pastebot**: $10 one-time (Mac App Store). Filters (auto-transform, delete patterns), iCloud sync, plain-text conversion, strong keyboard workflow.

---

### 6. The security model: concealed clipboard & exclusion lists

This is the most important section in the lesson if you handle credentials, evidence, or PII.

**The concealed clipboard flag (`org.nspasteboard.ConcealedType`):** This is a pasteboard type declaration convention, not a kernel-enforced restriction. When a password manager (1Password, Bitwarden, Apple Passwords, KeePass, KeeWeb) copies a password to the clipboard, it simultaneously places a `ConcealedType` representation on the pasteboard alongside the actual credential. Clipboard managers that respect the convention check for this type and silently skip storing the item.

Maccy respects this flag natively — it also ignores `org.nspasteboard.TransientType` (e.g., drag-and-drop transient data) and `org.nspasteboard.AutoGeneratedType`. Most reputable clipboard managers (Paste, Pastebot, Alfred, Raycast) do the same.

**App-level block lists:** Maccy: Preferences → Ignore → Add apps whose clipboard output you never want stored. Add your password manager as a belt-and-suspenders measure, even though the pasteboard type should handle it. Add apps that frequently put sensitive tokens in the clipboard (VPN clients, MFA apps, SSH tools).

**What clipboard managers cannot protect against:** They are monitoring the pasteboard — they see whatever the pasteboard exposes. If an app puts a secret on the pasteboard *without* the `ConcealedType` marker, it will be stored. Some older or non-standard apps do not set the flag. When in doubt, configure the app block list and audit your history store periodically.

> 🔬 **Forensics note:** A clipboard history database is a goldmine during an investigation. Maccy's `Storage.sqlite` contains the full plaintext of every captured clipboard item, timestamped, with source app. On a suspect machine, `strings` or direct SQLite queries against this file can surface passwords, API tokens, URLs, document fragments, and communications that never made it to any other artefact. Also check Raycast's local store (`~/Library/Application Support/com.raycast.macos/databases/`). Clipboard manager databases are frequently overlooked in macOS forensic checklists.

> ⚠️ **ADVANCED:** Clipboard databases accumulate indefinitely if retention is not configured. On a machine used for security testing, the database can contain exploit payloads, private keys, and staged credentials. Maccy: Preferences → Storage → Clear history automatically after N days. Raycast: Settings → Clipboard History → Keep clipboard history for N days. Set this to a value aligned with your data-retention policy.

---

### 7. Plain-text paste without a clipboard manager

Every macOS Cocoa text field supports "Paste and Match Style" which strips formatting and pastes plain text. The shortcut is `⌘⌥⇧V` system-wide (Edit menu → Paste and Match Style). In terminal emulators and plain text editors, regular `⌘V` already pastes as plain text because there is no rich text to inherit.

You can remap this to something shorter. In System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts, add a shortcut with menu title "Paste and Match Style" and assign `⌘⇧V`. This overrides the shortcut in any Cocoa app without installing any software.

A clipboard manager typically adds its own plain-text paste option (Maccy: hold `⌥` while selecting a clip; Raycast: `⌘↵` to paste as plain text), which is more granular and often more convenient.

---

## Hands-on (CLI & GUI)

### Verifying Text Replacement sync state

```bash
# Check the sync DB directly
sqlite3 ~/Library/KeyboardServices/TextReplacements.db \
  ".tables"
# Expected: TSReplacementEntry  TSReplacementTable  …

# List your current replacements
sqlite3 ~/Library/KeyboardServices/TextReplacements.db \
  "SELECT shortcut, phrase FROM TSReplacementEntry ORDER BY shortcut;"

# Force a sync restart if replacements have stopped working
killall -9 KeyboardServices
# (The daemon auto-restarts; give it ~5 seconds)
```

### Espanso quick-reference

```bash
# Install (Homebrew is the cleanest path)
brew install espanso

# Grant Accessibility permission when prompted, then:
espanso start

# Open config directory in Finder
open "$(espanso path config)"

# Test that espanso is running
espanso status
# Expected: espanso is running

# Reload config after editing YAML
espanso restart

# Check for config parse errors
espanso edit    # opens match/base.yml in $EDITOR

# Add a package from the Espanso Hub
espanso install basic-emojis   # example: adds emoji shortcuts

# Log / debug output
espanso log

# Where your config actually lives
espanso path
```

### Maccy quick-reference

```bash
# Install
brew install maccy

# Or App Store: search "Maccy" (same codebase, signed by developer)
# Launch; it appears in the menu bar

# Open history (default hotkey ⌘⇧V, change in Preferences)
# Preferences → General:
#   - History size: 500+ recommended
#   - Show in menu bar: yes
#   - Launch at login: yes
#   - Clear history: set a retention window
#
# Preferences → Ignore:
#   - Add 1Password, Bitwarden, Keychain Access, your VPN client

# Check Maccy's SQLite store
sqlite3 ~/Library/Application\ Support/Maccy/Storage.sqlite \
  "SELECT datetime(createdAt,'unixepoch','localtime'), value \
   FROM Item ORDER BY createdAt DESC LIMIT 20;"
# (Column names may vary by version; use .schema Item to inspect)
```

### Raycast clipboard history

```bash
# If Raycast is installed:
# Settings → Extensions → Clipboard History → Enable
# Set hotkey (default ⌘⇧V) — may conflict with Maccy if both installed
# Settings → Clipboard History → Keep clipboard history for: 90 days (adjust)
# Settings → Clipboard History → Exclude apps → add password manager

# Raycast database path (for forensics reference):
ls ~/Library/Application\ Support/com.raycast.macos/databases/
```

### Plain-text paste shortcut (no extra software)

```
System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → +
Application: All Applications
Menu Title: Paste and Match Style
Keyboard Shortcut: ⌘⇧V
```

This maps `⌘⇧V` to plain-text paste in every Cocoa app. Note: if Maccy or Raycast also use `⌘⇧V` for their history window, one will win — assign them to different shortcuts.

---

## Labs

### Lab 1 — Built-in Text Replacements

**Goal:** Add three practical replacements and verify sync.

1. Open System Settings → Keyboard → Text Replacements → click **+**.
2. Add these three entries (Replacement / Shortcut):
   - Your full email address / `;em`
   - A multiline postal address / `;addr`
   - A standard evidence chain-of-custody header you use frequently / `;coc`
3. Open TextEdit (or Mail compose), type `;em` followed by a space. Confirm expansion.
4. On your iPhone/iPad (same Apple ID, iCloud Drive on), open Notes, type `;em` + space. Confirm the replacement synced.
5. Dump the DB to confirm the entries are present:

```bash
sqlite3 ~/Library/KeyboardServices/TextReplacements.db \
  "SELECT shortcut, phrase FROM TSReplacementEntry WHERE shortcut LIKE ';%';"
```

**Expected output:** Three rows, your shortcuts and expansions.

---

### Lab 2 — Espanso: date + form snippet for forensics

> ⚠️ **Preparation:** This lab installs Espanso and grants it Accessibility access. To roll back: `espanso stop && brew uninstall espanso`, then revoke Accessibility in System Settings → Privacy & Security → Accessibility.

```bash
brew install espanso
espanso start
# Follow the on-screen prompt to grant Accessibility permission in System Settings
```

Edit your match file:

```bash
open "$(espanso path config)"
# opens ~/Library/Application Support/espanso in Finder
# open match/base.yml in your editor
```

Paste the following into `match/base.yml` (replace existing content or append to `matches:`):

```yaml
matches:
  # ISO date for filenames and notes
  - trigger: ";date"
    replace: "{{today}}"
    vars:
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"

  # DateTime for log entries
  - trigger: ";dt"
    replace: "{{now}}"
    vars:
      - name: now
        type: date
        params:
          format: "%Y-%m-%dT%H:%M:%S"

  # Case intake header with form inputs
  - trigger: ";intake"
    replace: |
      === CASE INTAKE ===
      Date:     {{today}}
      Case #:   {{case_id}}
      Examiner: {{examiner}}
      Subject:  {{subject}}
      ==================
    vars:
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"
      - name: case_id
        type: form
        params:
          layout: "Case ID: {{case_id}}"
      - name: examiner
        type: form
        params:
          layout: "Examiner: {{examiner}}"
      - name: subject
        type: form
        params:
          layout: "Subject: {{subject}}"

  # SHA-256 evidence line — wraps clipboard content
  - trigger: ";sha256"
    replace: "SHA-256: {{clipboard}}  [verified {{today}}]"
    vars:
      - name: clipboard
        type: clipboard
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"

  # Fresh UUID
  - trigger: ";uuid"
    replace: "{{uuid}}"
    vars:
      - name: uuid
        type: shell
        params:
          cmd: "uuidgen | tr -d '\n'"
```

Reload:
```bash
espanso restart
```

**Test sequence:**
1. Open TextEdit or any text editor.
2. Type `;date` + space → should expand to today's ISO date.
3. Type `;dt` + space → should expand to current date + time.
4. Copy any SHA-256 hash string to your clipboard. Type `;sha256` + space → confirm it wraps the hash.
5. Type `;intake` + space → a form dialog appears; fill in case ID, examiner, subject → confirm the formatted header inserts.
6. Type `;uuid` + space → a fresh UUID appears.

---

### Lab 3 — Maccy clipboard manager with password exclusion

> ⚠️ **Preparation:** Maccy stores clipboard history locally. If you handle truly sensitive data on this machine, configure exclusions *before* using it in a work session. To roll back: `brew uninstall maccy`, then delete `~/Library/Application Support/Maccy/`.

```bash
brew install maccy
open /Applications/Maccy.app
```

1. Maccy appears in the menu bar (clipboard icon). Click it → Preferences.
2. **General tab:**
   - History size: 500
   - Show in menu bar: checked
   - Launch at login: checked
3. **Ignore tab:** Click **+** and add:
   - 1Password 8 (or whichever password manager you use)
   - Bitwarden (if applicable)
   - Keychain Access
   - Any VPN or MFA app that puts tokens in the clipboard
4. **Storage tab:** Set "Clear history automatically" to 30 days (or match your policy).
5. Configure hotkey: General → Hotkey → assign `⌘⇧C` (leaves `⌘⇧V` for plain-text paste if you remapped it earlier, or use whatever doesn't conflict with your setup).

**Verification sequence:**
1. Copy three different things in quick succession: a URL, a paragraph of text, a command.
2. Open Maccy (`⌘⇧C` or click menu bar icon). Confirm all three appear in history.
3. In a text editor, use arrow keys + Return to paste an item from history without touching the mouse.
4. Open 1Password; copy a password. Open Maccy — confirm the password does **not** appear in history (the `ConcealedType` flag is working).
5. Type a few characters in Maccy's search box; confirm fuzzy matching narrows the list.
6. Hold `⌥` while selecting a clip → confirm it pastes as plain text (no rich formatting).

**Inspect the database (forensics perspective):**
```bash
# Identify the correct table name first
sqlite3 ~/Library/Application\ Support/Maccy/Storage.sqlite ".tables"

# Then query recent items (column names depend on Maccy version)
sqlite3 ~/Library/Application\ Support/Maccy/Storage.sqlite \
  "SELECT * FROM ZITEM ORDER BY ZCREATEDAT DESC LIMIT 5;"
```

---

## Pitfalls & gotchas

**Text Replacements silent failures in Electron apps:** If a replacement you know works in TextEdit does nothing in VS Code, Slack, or any Electron-based app, this is by design — Electron renders its own input stack via Chromium and does not participate in macOS Input Method events. Solution: switch to Espanso (clipboard backend mode works in Electron) or manually maintain a second tool for those apps.

**Espanso and Secure Input:** Anytime you see the Espanso menu bar icon show a lock, Secure Keyboard Entry is active somewhere. This is correct and intentional. Do not attempt to work around it by disabling Secure Input system-wide — that weakens your security posture.

**Espanso trigger collisions with your shell:** If you use `;date` in Bash/zsh in a Terminal window, that trigger fires. Either exclude Terminal in Espanso's `config/default.yml`:
```yaml
exclude_apps:
  - exec: Terminal
  - exec: iTerm2
  - exec: WarpTerminal
```
Or choose triggers that are not valid shell tokens (e.g., `;;date`).

**Clipboard manager and password manager interaction:** The `ConcealedType` convention is not enforced by the kernel — it is a voluntary developer agreement. If you install an obscure or old password manager that does not set the flag, its credentials **will** be stored in clipboard history. Audit your Maccy history after using any new password tool.

**iCloud sync latency for Text Replacements:** Sync between devices is not instantaneous. It can take minutes or require an iCloud "nudge" (open System Settings → Apple ID to trigger a sync check). If replacements disappear after an OS update, the culprit is typically a CloudKit sync conflict; the fix is to export your DB, delete all replacements, wait for sync, then re-import. See the TidBITS article linked below.

**Espanso "injection" vs. "clipboard" backend per match:** Some apps (notably remote desktop clients, browser extensions in certain modes) block all synthetic key injection. For those, override backend at the match level:
```yaml
- trigger: ";em"
  replace: "robert.olen@gmail.com"
  force_clipboard: true
```
This uses the clipboard paste path for that specific match only.

**Raycast + Maccy conflict on `⌘⇧V`:** Both default to `⌘⇧V` for clipboard history. Assign one of them a different hotkey before both are active, or disable one's clipboard history feature entirely.

**History database size:** Maccy and similar tools can accumulate hundreds of MB of clipboard content (especially if you copy large images or file paths). Set automatic retention limits and check database size periodically: `du -sh ~/Library/Application\ Support/Maccy/`.

---

## Key takeaways

- The built-in macOS Text Replacements work well for simple static strings in native Cocoa apps, sync via iCloud to iPhone/iPad, and require zero additional software — start there for trivial cases.
- For dynamic content (dates, scripts, forms, cursor positioning), cross-app reliability (Electron), or cross-platform use, Espanso is the highest-value free alternative: YAML config is version-controllable, the shell variable type makes any CLI tool available as a snippet, and the form type creates interactive fill-in dialogs.
- Clipboard managers turn the single-slot clipboard into a searchable history. Maccy is the minimum viable free option; Raycast (if already installed) provides the same at no additional cost. Paste and Pastebot add sync and polish at subscription/one-time prices.
- The `ConcealedType` pasteboard convention is the critical security mechanism — understand it, verify your tools respect it, and configure app-level block lists as a belt-and-suspenders measure.
- Clipboard history databases are high-value forensic artefacts: plaintext, timestamped, and often overlooked. Know where they live on any machine you examine.
- Plain-text paste (`⌘⌥⇧V`, or remapped to `⌘⇧V`) is a zero-install solution for stripping formatting — use it freely in any Cocoa app.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Text expansion** | Replacing a short trigger string with a longer expansion, optionally including dynamic content |
| **Text Replacements** | macOS built-in System Settings feature; stores abbreviation→phrase pairs, iCloud-synced |
| **Espanso** | Open-source, cross-platform text expander; YAML-configured; runs as a `CGEventTap` listener |
| **CGEventTap** | macOS API for intercepting and injecting system-level keyboard/mouse events |
| **Secure Keyboard Entry** | macOS mode that blocks `CGEventTap` access to protect password input |
| **Clipboard manager** | App that snapshots each clipboard change into a persistent searchable history |
| **NSGeneralPasteboard** | The system-wide general-purpose pasteboard object in the AppKit/NSPasteboard framework |
| **ConcealedType** (`org.nspasteboard.ConcealedType`) | Voluntary pasteboard convention signalling that a clipboard item contains sensitive data and should not be saved by clipboard managers |
| **TransientType** (`org.nspasteboard.TransientType`) | Pasteboard convention for ephemeral data (e.g., drag-and-drop) that should not persist in history |
| **Clipboard backend** | Espanso expansion mode that writes to the clipboard and pastes, bypassing key-injection restrictions |
| **Injection backend** | Espanso expansion mode that synthesises keystrokes directly via `CGEventPost` |
| **Plain-text paste** | Pasting clipboard contents as unstyled text, stripping rich formatting; "Paste and Match Style" in macOS menus |
| **Pinboard / Favorite clip** | A clipboard item marked to persist permanently, not rotated out by history limits |
| **Dynamic snippet** | A snippet whose expansion content is computed at trigger time (date, script output, clipboard content, form input) |
| **Trigger** | The short string you type to invoke a text expansion rule |
| **Fuzzy search** | Search that matches non-contiguous substrings, used in clipboard history search UIs |

---

## Further reading

- [Espanso official docs — Getting Started](https://espanso.org/docs/get-started/) — installation, match syntax, vars, forms
- [Espanso Configuration Basics](https://espanso.org/docs/configuration/basics/) — config directory structure, per-app config, backends
- [Maccy on GitHub](https://github.com/p0deje/Maccy) — source, `ConcealedType` implementation, issue tracker
- [TidBITS: Bring macOS Text Replacements Back to Life (2025)](https://tidbits.com/2025/02/10/tipbits-bring-macos-text-replacements-back-to-life/) — how to recover from the iCloud sync bug that blanks replacements after updates
- [Apple Support: Back up and share text replacements on Mac](https://support.apple.com/guide/mac-help/back-up-and-share-text-replacements-on-mac-mchl2a7bd795/mac)
- [Raycast Clipboard History](https://www.raycast.com/core-features/clipboard-history) — feature overview and keyboard reference
- [Raycast Snippets](https://www.raycast.com/core-features/snippets) — how Raycast's built-in snippet expansion works
- [NSPasteboard Conventions (Apple Developer Docs)](https://developer.apple.com/documentation/appkit/nspasteboard) — the `org.nspasteboard.*` type convention is documented in the AppKit pasteboard headers

**Related lessons in this curriculum:**
- [[04-hazel-and-keyboard-maestro]] — Keyboard Maestro's "Insert Text by Typing/Pasting" action and how it integrates with macros that dwarf what pure text expanders can do
- [[05-launchers-raycast-alfred]] — Raycast and Alfred overview; snippets live there too and share the same hotkey ecosystem
- [[02-applescript-and-jxa]] — when a snippet needs to drive an app rather than just insert text, AppleScript/JXA is the next step up
- [[02-tcc-and-privacy]] — the TCC framework that governs Accessibility permission, which Espanso requires; understanding approval, revocation, and audit
