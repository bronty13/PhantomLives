---
title: "Launchers: Raycast & Alfred"
part: P06 Automation
est_time: 50 min read + 45 min labs
prerequisites: [03-spotlight-search, 01-shell-basics]
tags: [macos, automation, raycast, alfred, launcher, clipboard, productivity]
---

# Launchers: Raycast & Alfred

> **In one sentence:** Raycast and Alfred transform Cmd-Space from a search box into a command center — routing every repetitive desktop action through a single, scriptable keystroke.

## Why this matters

Spotlight is a file indexer with a launcher stapled on. It finds your apps and does unit conversions; it does not automate anything. The launcher category Raycast and Alfred occupy is a different creature: they intercept keypresses, accept arbitrary input, execute scripts, manage clipboard state, expand text, drive window layouts, and expose REST APIs as first-class commands. For a forensics professional or builder whose workflow spans the terminal, browser, mail, Slack, and a dozen bespoke scripts, collapsing all of that into a memorized keystroke vocabulary is a 10× multiplier.

> 🪟 **Windows contrast:** PowerToys Run (open source, built into PowerToys v0.6x+) covers basic app/file launch with some plugin extensibility. Listary (commercial) adds folder navigation and inline search. Neither reaches the workflow-automation depth of Alfred's Powerpack or Raycast's script command + extension ecosystem. The closest Windows parallel is AutoHotkey + a custom launcher, which requires considerably more wiring.

## Concepts

### The Launcher Architecture on macOS

Both apps are Accessibility clients: they register a global hotkey via `CGEventTapCreate` (a Carbon-era API still used today) and draw their UI outside the normal responder chain. When you press Cmd-Space (or your configured key), the OS delivers the keydown event to the app's event tap before any foreground app sees it. The launcher presents its window via a borderless, non-activating `NSPanel`, queries its own index, and dispatches actions — which may be in-process Swift/Objective-C, shell subprocesses, or AppleScript OSA scripts.

Because both apps use `kCGEventTapOptionDefault` (a "listener" tap, not an "interceptor" tap by default for the hotkey registration), they depend on Accessibility permissions. You will see them in **System Settings → Privacy & Security → Accessibility**. Removing that permission silences the hotkey entirely.

### Raycast: The Modern Default

Raycast (free tier; Raycast Pro adds AI features and advanced window management) launched in 2020 and reached critical mass around 2022-2023. By 2026 it is the de facto first install for macOS power users.

**Architecture:** Raycast itself is a native Swift/AppKit application. Extensions are TypeScript/React components that Raycast's renderer converts to native AppKit views — you never see a WebView. This gives extensions native feel while letting the community ship them without Xcode or Swift knowledge.

**Core feature set:**

| Category | What it does | Mechanism |
|---|---|---|
| App launch | Fuzzy-match running + installed apps | Scans `/Applications`, Dock, recent usage |
| Calculator / units | Inline arithmetic, currency, unit conversions | Built-in evaluator; shows result in real time as you type |
| Clipboard History | Stores every text/image/file copy, searchable | SQLite in `~/Library/Application Support/com.raycast.macos/` |
| Snippets | Type an abbreviation → expands to full text | Accessibility keystroke injection |
| Window Management | Thirds, halves, quarters, custom grids — no extra app | AppKit `setFrame:display:` with optional animation |
| Script Commands | Any executable (bash/python/ruby/node/swift) surfaced as a Raycast command | `posix_spawn`, output captured and rendered per mode |
| Extensions | TypeScript packages from the Store or local dev | Node.js subprocess; IPC to Raycast renderer |
| Quicklinks | URL templates with `{query}` placeholder → open in browser | `NSWorkspace openURL:` |
| Floating Notes | Persistent scratchpad, hotkey-summoned | In-memory + SQLite, appears as HUD over other apps |
| AI (Pro) | Inline AI completions, chat window, command generation | Calls Raycast's backend; model-agnostic via their API |

**The Extension Store (`raycast.com/store`):** As of mid-2026, over 1,500 extensions exist covering GitHub, Linear, Jira, Notion, 1Password, Homebrew, Docker, AWS, Vercel, and hundreds more. Installation is one click from within Raycast itself (`Extensions → Store`). Extensions run as Node.js child processes; they cannot access the network without explicit permission declared in their manifest, and they cannot access the filesystem beyond their own data directory without a user-granted path. Extension code is open-source on GitHub (`github.com/raycast/extensions`).

**Quicklinks** are underrated: `Title: "Ghidra Docs", URL: https://ghidra.re/ghidra_docs/api/?search={query}` gives you a hotkey to search Ghidra's API docs directly. Combine with aliases for instant muscle memory.

**Floating Notes** is a distraction-free scratchpad that hovers over every Space. Hit your hotkey to summon/dismiss. Content persists across reboots. There is no sync in the free tier; Pro syncs via iCloud.

### Alfred: The Veteran

Alfred (free tier; £34 one-time "Powerpack" for the workflow engine — single license, lifetime updates for major version) has been on macOS since 2011. Alfred 5 (current major version as of 2026) is mature, opinionated, and has a workflow ecosystem built over a decade.

**Architecture:** Alfred is a pure Objective-C/AppKit application. Its "results list" is fast and deterministic — no extension runtime overhead. Workflows run as subprocesses (bash, Python, Ruby, osascript, PHP, Perl, or pre-compiled binaries).

**Powerpack-only features — the serious ones:**

**Workflows (the Visual Automation Graph)**

The Workflow Editor presents a canvas of typed nodes connected by arrows. Node types include:

- *Triggers:* Keyword input, hotkey, remote trigger, scheduled trigger, clipboard change, File Action invoked on a selection, Contact Action
- *Inputs:* Script Filter (runs a script, returns JSON results list), File Filter, Dynamic File Search
- *Actions:* Run Script, Open File/URL, Launch App, System Command, Copy to Clipboard, Write Text File, Notification, Call External Trigger
- *Utilities:* Conditional branch (If/Else), Replace/Transform text, Delay, Junction (fan-in/fan-out), Debug

The **Script Filter** is Alfred's most powerful primitive. It accepts a query string from the user and must return JSON within a timeout:

```json
{
  "items": [
    {
      "title": "Incident 2024-42",
      "subtitle": "P1 — Authentication bypass in prod API",
      "arg": "https://jira.example.com/INC-42",
      "icon": { "path": "icons/incident.png" },
      "quicklookurl": "https://jira.example.com/INC-42",
      "mods": {
        "cmd": { "subtitle": "Copy URL", "arg": "copy:https://..." }
      }
    }
  ]
}
```

Alfred re-runs your script with each keystroke (debounced); the user sees live results from your data source, local SQLite, or REST API. This is how community workflows expose GitHub repo search, 1Password vault lookup, and custom internal tooling.

**Automation Tasks** (Alfred 5): Pre-built no-code action blocks (resize image, get Safari tab, toggle Dark Mode, move file to folder, etc.) that slot into workflows without a script node. Think of them as Alfred's equivalent of Shortcuts actions.

**File Navigation and Buffer:** Alfred's default search isn't just app launch. Prefix with a space to enter File Browser mode — navigate the filesystem without Finder, preview with Quick Look, and invoke File Actions (move, copy, email, custom workflow trigger) directly. The **File Buffer** lets you accumulate multiple files with `⌥↑`, then act on all of them at once — a pattern with no Raycast equivalent.

**Alfred Remote** (iOS companion app): Trigger any Alfred workflow from your iPhone. Niche, but useful for one-button deploys or home-lab controls.

**Alfred's clipboard** stores SQLite at `~/Library/Application Support/Alfred/Databases/clipboard.alfdb`. Entries survive across reboots, searchable by content and date, with configurable retention (1 day to forever).

> 🔬 **Forensics note:** Both apps write clipboard history to SQLite databases on disk. In an investigation, these databases reveal everything the user copied during the retention window — credentials, file paths, messages, code — even content the user never intentionally saved. `~/Library/Application Support/com.raycast.macos/` for Raycast, `~/Library/Application Support/Alfred/Databases/clipboard.alfdb` for Alfred. Both are unencrypted by default (Alfred stores content as plaintext in `dataHash`/`dataValue` columns; Raycast uses SQLite WAL mode). On a FileVault-encrypted volume, these are protected at rest, but live on any unlocked machine.

### How to Pick

| Need | Raycast (free) | Alfred (Powerpack) |
|---|---|---|
| Zero cost, batteries included | Yes | Free tier only; Powerpack £34 |
| Extension ecosystem (modern apps) | Huge (1500+), growing fast | Smaller, but mature (Packal archive) |
| Visual workflow graph | No (script commands only) | Yes — the Workflow Editor canvas |
| Script Filter (live-query results) | Via extension API (TypeScript) | Native workflow node (any language) |
| Window management built in | Yes | No (needs separate extension) |
| File buffer / bulk file actions | No | Yes |
| AI integration | Yes (Pro tier) | Limited (ChatGPT via workflow, no native) |
| Multi-language script commands | Yes (any shebang) | Yes (any shebang) |
| Data portability | Good (JSON export for snippets) | Good (workflow export as `.alfredworkflow`) |
| macOS version floor | macOS 12+ | macOS 12+ |

**Decision heuristic:** Start with Raycast. If you find yourself needing complex multi-step conditional logic, a visual graph, or the file buffer, add Alfred (you can run both simultaneously on different hotkeys). Most power users eventually land on one primary launcher and keep the other for its unique features.

### Privacy Architecture of Clipboard Managers

Both tools detect "concealed" clipboard content — the `NSPasteboard` type `com.apple.is-password` — which password managers like 1Password, Bitwarden, and Keychain Access are supposed to set when copying a password. When this flag is present, both Raycast and Alfred skip recording that copy.

**The caveat:** Not all password managers set this flag, and browser extension copy buttons sometimes bypass it (the copy originates from a Web Content process with a different context). This has caused real credential leaks into clipboard history for users relying on the automatic exclusion.

**Defense in depth:**
1. In Raycast: **Settings → Extensions → Clipboard History → Ignored Applications** — add your password manager's app bundle.
2. In Alfred: **Preferences → Features → Clipboard → Ignore Apps** — drag your password manager into the list.
3. Consider turning clipboard history retention to a short window (24 hours) if the machine is shared or in a sensitive environment.
4. For forensics work, be aware that clipboard history persists even after the application "clears" the system clipboard — it was already captured.

---

## Hands-on (CLI & GUI)

### Installing and Swapping Cmd-Space

**Raycast:**
```bash
brew install --cask raycast
open -a Raycast
```

On first launch, Raycast offers to disable Spotlight's Cmd-Space binding and take it over. If you skip that, do it manually:

1. **System Settings → Keyboard → Keyboard Shortcuts → Spotlight** → uncheck "Show Spotlight search" (Cmd-Space).
2. In Raycast Preferences → General → Raycast Hotkey → set to `⌘ Space`.

**Alfred:**
```bash
brew install --cask alfred
```

Same Spotlight-disable step, then Alfred Preferences → General → Alfred Hotkey → `⌘ Space`.

Verify the hotkey swap took:
```bash
# Confirm Spotlight shortcut is cleared (returns empty or no-match):
defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys | grep -A5 '"64"'
# Key 64 is Spotlight. enabled = 0 means disabled.
```

### Raycast Script Commands

Script commands live in any directory you register with Raycast. Create one:

```bash
mkdir -p ~/raycast-scripts
```

Create `~/raycast-scripts/show-ip.sh`:

```bash
#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Show IP Addresses
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🌐
# @raycast.description Show all non-loopback IP addresses
# @raycast.packageName Network

echo "=== Network Interfaces ==="
ifconfig | awk '/^[a-z]/{iface=$1} /inet /{print iface, $2}' | grep -v '127.0.0.1'
```

```bash
chmod +x ~/raycast-scripts/show-ip.sh
```

In Raycast: **Preferences → Extensions → Script Commands → Add Directories** → pick `~/raycast-scripts`. The command "Show IP Addresses" now appears instantly.

**Mode options:**

| Mode | Behavior |
|---|---|
| `silent` | Runs without showing output; use for side-effect scripts (open URLs, move files) |
| `compact` | Single-line HUD notification at top of screen |
| `fullOutput` | Full terminal-like scrollable output panel |
| `inline` | Output appears inline in the results list (good for one-line values) |

**A script command with user input** — query passed as `$1`:

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Whois
# @raycast.mode fullOutput
# @raycast.icon 🔍
# @raycast.argument1 { "type": "text", "placeholder": "domain or IP" }
# @raycast.description WHOIS lookup from Raycast

whois "$1" | head -40
```

Raycast renders a text field when you select this command; the value goes to `$1`. For Python scripts, use `sys.argv[1]`.

### Alfred Script Filter (Powerpack)

Open Alfred Preferences → Workflows → `+` → Blank Workflow. Name it "Jira Quick Search".

1. Add **Input → Script Filter**:
   - Language: `/bin/bash`
   - Script: (call a real script file for maintainability)
   ```bash
   python3 /path/to/jira-search.py "{query}"
   ```

2. `jira-search.py` returns Alfred JSON to stdout:
   ```python
   #!/usr/bin/env python3
   import sys, json, subprocess

   query = sys.argv[1] if len(sys.argv) > 1 else ""
   # Replace with your actual data source:
   results = [
       {"title": f"INC-{i}", "subtitle": f"Result for '{query}'", "arg": f"INC-{i}"}
       for i in range(1, 6)
   ]
   print(json.dumps({"items": results}))
   ```

3. Add **Actions → Open URL**: `https://jira.example.com/browse/{query}` — Alfred passes `arg` from the selected item as `{query}`.

4. Assign keyword `jira` → type `jira INC-42` in Alfred → open directly.

### Setting Up Clipboard History (Raycast)

Raycast Preferences → Extensions → Clipboard History → Enable. Default retention: 3 months. Hotkey suggestion: `⌘ ⇧ V`.

From the terminal, inspect what Raycast knows about your clipboard:
```bash
# Database location:
ls ~/Library/Application\ Support/com.raycast.macos/*.db 2>/dev/null || \
  find ~/Library/Application\ Support/com.raycast.macos/ -name "*.sqlite" 2>/dev/null
```

### Snippet Expansion

In Raycast: **Preferences → Extensions → Snippets → Create Snippet**:

| Name | Keyword | Text |
|---|---|---|
| SHA256 command | `;sha` | `shasum -a 256 ` |
| Email signature | `;sig` | `Robert Olen\nDigital Forensics` |
| ISO timestamp | `;ts` | (use dynamic snippet if supported, else a fixed string) |

Raycast injects snippets via Accessibility, which requires the Accessibility permission. Test:
```bash
# Verify accessibility permission is granted:
sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client,auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%raycast%';" 2>/dev/null
# auth_value 2 = granted
```

---

## Labs

### Lab 1 — Swap Cmd-Space to Raycast

**Goal:** Raycast owns Cmd-Space; Spotlight accessible via Cmd-Option-Space.

> ⚠️ **Before proceeding:** Note your current Spotlight shortcut in case you want to revert. Screenshot `System Settings → Keyboard → Keyboard Shortcuts → Spotlight`. Rollback: re-enable the checkbox and remove Raycast's hotkey assignment.

1. Install Raycast if not present: `brew install --cask raycast`
2. Disable Spotlight's Cmd-Space: System Settings → Keyboard → Keyboard Shortcuts → Spotlight → uncheck **Show Spotlight search**.
3. Optional: Set Spotlight to Cmd-Option-Space in the same pane.
4. Open Raycast → Preferences → General → Raycast Hotkey → `⌘ Space`.
5. Press Cmd-Space. Verify Raycast window appears, not Spotlight.
6. Type `calc 2^32` — Raycast should show `4294967296` inline.
7. Type your most-used app's first three letters and press Return. Confirm it launches.

**Verification:**
```bash
defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys | python3 -c "
import sys, ast
data = ast.literal_eval(sys.stdin.read())
spotlight = data.get('64', {})
print('Spotlight Cmd-Space enabled:', spotlight.get('enabled', 'unknown'))
"
```

---

### Lab 2 — Build a Forensics Script Command

**Goal:** A Raycast command that takes a file path argument and returns SHA-256 + file type + size.

> ⚠️ **No destructive operations in this lab.** Script is read-only. No rollback needed.

```bash
cat > ~/raycast-scripts/file-info.sh << 'EOF'
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title File Info
# @raycast.mode fullOutput
# @raycast.icon 🔬
# @raycast.description SHA-256, type, and size for a file
# @raycast.packageName Forensics
# @raycast.argument1 { "type": "text", "placeholder": "file path or drag here" }

FILE="$1"

if [[ ! -f "$FILE" ]]; then
  echo "Not a regular file: $FILE"
  exit 1
fi

echo "=== File Info ==="
echo "Path:    $FILE"
echo "Size:    $(du -sh "$FILE" | cut -f1)"
echo "Type:    $(file -b "$FILE")"
echo "SHA-256: $(shasum -a 256 "$FILE" | awk '{print $1}')"
echo "MD5:     $(md5 -q "$FILE")"
echo "Modified:$(stat -f '%Sm' "$FILE")"
echo "Born:    $(stat -f '%SB' "$FILE")"
echo ""
echo "=== Extended Attributes ==="
xattr -l "$FILE" 2>/dev/null || echo "(none)"
EOF
chmod +x ~/raycast-scripts/file-info.sh
```

In Raycast, refresh Script Commands (Cmd-R in the Script Commands extension). Type "File Info", press Return, enter a file path like `/etc/hosts`. Expect full output with all fields.

**Push it further:** Change `@raycast.mode` to `compact` — you'll get a single-line HUD. Change to `inline` and the output appears as a subtext row in the results list.

---

### Lab 3 — Clipboard History and Snippets

**Goal:** Enable clipboard history, verify it records, exclude a sensitive app, and create a useful snippet.

> ⚠️ **Privacy implication:** After enabling clipboard history, everything you copy is stored on disk in plaintext (within the app's SQLite). Review the Ignored Applications list and set a retention window appropriate to your threat model before storing sensitive material.

**Enable clipboard history:**
1. Raycast Preferences → Extensions → Clipboard History → toggle on.
2. Set Hotkey to `⌘ ⇧ V`.
3. Set retention to 7 days (shorter is safer on a forensics workstation).
4. Add any password manager to Ignored Applications (drag the `.app` from `/Applications/`).

**Test it:**
```bash
# Copy something:
echo "test-clipboard-$(date +%s)" | pbcopy
# Then press your clipboard history hotkey — the string should appear at the top.
```

**Verify database is being written:**
```bash
DB=$(find ~/Library/Application\ Support/com.raycast.macos -name "*.sqlite" 2>/dev/null | head -1)
if [[ -n "$DB" ]]; then
  sqlite3 "$DB" ".tables" 2>/dev/null && echo "DB at: $DB"
else
  echo "DB not found — Raycast may use a different path on this version"
fi
```

**Create a snippet:**
1. Raycast Preferences → Extensions → Snippets → `+`.
2. Name: "Hex dump command", Keyword: `;hx`, Text: `xxd -l 256 `.
3. In any text field, type `;hx` — it should expand. If not, verify Raycast has Accessibility permission.

---

### Lab 4 — Window Management with Raycast (No Extra App)

**Goal:** Replace Rectangle/Magnet with Raycast's built-in window management.

> ⚠️ **If you use Rectangle or Magnet:** You can run them alongside Raycast but their hotkeys may conflict. Disable conflicting shortcuts in whichever app you want to yield. Rollback: re-enable Rectangle/Magnet.

1. Raycast → Preferences → Extensions → Window Management → Enable.
2. Search Raycast for "Left Half" — press Return. Your frontmost window moves to the left half.
3. Search "Right Third" — window snaps to right third.
4. Assign hotkeys: Raycast results list → Right-click "Left Half" → Assign Hotkey → `⌃ ⌥ ←`.
5. Assign "Right Half" → `⌃ ⌥ →`. These are muscle-memory friendly and don't collide with Cmd-Arrow (word/line navigation) or Ctrl-Arrow (Mission Control).

Verify:
```bash
# Check Raycast window management permission (Accessibility):
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT client, auth_value FROM access WHERE service='kTCCServiceAccessibility';" 2>/dev/null \
  | grep -i raycast
```

---

## Pitfalls & Gotchas

**Accessibility permission not granted silently breaks everything.** The hotkey tap, snippet expansion, and window management all require Accessibility. Raycast prompts on first use, but if the permission was granted and then revoked (or a system update wiped it), everything fails with no obvious error. Check System Settings → Privacy & Security → Accessibility.

**Raycast extension updates are automatic.** If an extension breaks your workflow overnight, check the Raycast changelog or the extension's GitHub issues. You can pin a specific extension version by disabling auto-update in Preferences → Advanced.

**Alfred workflows are not portable between Alfred versions without migration.** Alfred 4 → Alfred 5 workflows generally work, but actions using deprecated nodes may silently fail. Test workflows after any Alfred major-version update.

**Clipboard history and sudo.** Text you type into a `sudo` password prompt is NOT copied to the clipboard. But text pasted FROM clipboard history into a terminal is just a paste — the terminal process sees it. If you paste credentials from clipboard history, they appear in shell history (`~/.zsh_history`) if you aren't careful. Use `read -s VAR` for credential input in scripts.

**Snippet expansion fails in some sandboxed apps.** Sandboxed Mac App Store apps (like Notes.app) may reject Accessibility-injected keystrokes. Use Raycast's clipboard-paste fallback mode (Preferences → Extensions → Snippets → Paste as Plain Text) which pastes via `pbpaste` instead of key injection — more reliable across sandboxed apps.

**Conflict: both launchers registering the same hotkey.** If you install both, be explicit: run Raycast on Cmd-Space and Alfred on a different key (e.g., `⌥ Space`). Running both on the same hotkey results in unpredictable behavior — whoever registered first wins, and the other silently gets nothing.

**Raycast's SQLite databases are not encrypted.** On a locked machine (FileVault active, screen locked), data is protected. On a live machine with an unlocked user session, any process running as that user can read the clipboard history, preferences, and snippet databases directly. Same applies to Alfred. Do not store secrets in snippets.

**"Show Recents" in Alfred and Raycast.** Both apps cache recent file opens. On a forensics machine imaging someone else's system, be aware this cache populates with files you open during examination — it can later appear to mix examiner activity with subject activity in timeline analysis if the wrong user profile is used.

---

## Key Takeaways

- Raycast is the modern default: free, batteries-included (clipboard, snippets, window management, extensions, AI), native Swift rendering, enormous extension ecosystem. Start here.
- Alfred's superpower is the Workflow Editor's visual graph + Script Filter — arbitrary language scripts returning live JSON results, chainable with conditionals. Buy the Powerpack if you need that.
- Both apps are Accessibility clients; losing that permission silently breaks all hotkey/injection features.
- Clipboard history databases are unencrypted SQLite on disk — rich forensic artifacts, and a privacy risk if not configured carefully. Always configure app exclusions and set a retention window.
- Script commands (Raycast) and Script Filters (Alfred) are the bridge between the launcher and your own tooling. Any executable becomes a searchable, hotkey-accessible command in under five minutes.
- Migrating Cmd-Space requires explicitly disabling Spotlight's shortcut in System Settings → Keyboard Shortcuts; the app cannot do this for you without your confirmation.

---

## Terms Introduced

| Term | Definition |
|---|---|
| CGEventTap | Carbon-era macOS API for intercepting system-wide keyboard/mouse events; how launchers register global hotkeys |
| NSPanel | A borderless, non-activating window subclass; how launcher UIs appear over other apps without stealing focus |
| Script Filter | Alfred workflow node that runs a script per-keystroke and renders its JSON output as a live results list |
| Script Command | Raycast's term for an executable file with `@raycast.*` metadata comments that makes it available as a command |
| Powerpack | Alfred's paid license tier unlocking workflows, clipboard history, snippets, remote triggers, and advanced search |
| `com.apple.is-password` | NSPasteboard type flag password managers set to signal that copied content should be excluded from clipboard history |
| Quicklink | Raycast feature: a named URL template (`{query}` placeholder) triggered as a Raycast command, opens in browser |
| File Buffer | Alfred feature: accumulate multiple selected files with `⌥↑`, then act on all at once |
| Automation Task | Alfred 5 pre-built no-code workflow action (resize image, toggle Dark Mode, etc.) |

---

## Further Reading

- [Raycast Manual — Script Commands](https://manual.raycast.com/script-commands) — complete metadata reference
- [raycast/script-commands on GitHub](https://github.com/raycast/script-commands) — community script library to mine for examples
- [Alfred Workflows — Script Filter JSON format](https://www.alfredapp.com/help/workflows/inputs/script-filter/json/) — full JSON schema for Script Filter output
- [Alfred Forum (alfredforum.com)](https://www.alfredforum.com) — workflow community; thousands of workflows with source
- [Packal.org archive](http://www.packal.org) — historical Alfred workflow repository (Alfred 2/3 era; workflows often still work)
- [[03-spotlight-search]] — what you're replacing: Spotlight's index, metadata queries, and `mdfind`
- [[01-shell-basics]] — script commands are just shell scripts; fluency there unlocks this feature entirely
- [[07-shortcuts-automator]] — Apple's own automation layer; complementary to launcher scripts for GUI-heavy tasks
