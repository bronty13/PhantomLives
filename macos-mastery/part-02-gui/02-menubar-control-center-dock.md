---
title: Menu bar, Control Center, Notifications & the Dock
part: P02 — GUI Power User
lesson: 02
est_time: 50 min read + 40 min labs
prerequisites: [00-finder-mastery, 01-window-management]
tags: [macos, menu-bar, control-center, dock, notifications, focus, spotlight, liquid-glass, tahoe]
---

# Menu bar, Control Center, Notifications & the Dock

> **In one sentence:** The menu bar is a focused-app contract, not a persistent toolbar — once you internalize that distinction (and learn to tame the right-side status-item sprawl), together with a tuned Dock and surgical Focus mode configuration, you control the entire surface of macOS without touching a trackpad.

---

## Why this matters

Windows draws a sharp line between the taskbar (running apps + system tray) and the title bar (app menus per window). macOS collapses both into the menu bar, ties it to the *focused application* rather than a window, and adds a status-item zone on the right that can grow out of control fast. If you are coming from Windows and keep hunting for an app's menu inside its window, you are wasting seconds on every interaction. If you have 20 status icons crammed into the right side of a notched MacBook Pro, half of them are hidden behind the camera cutout and you do not know what you are missing.

Beyond the daily annoyance, the menu bar, Dock, and notification infrastructure each leave forensically rich artifacts: preference plists, launch-time events in the Unified Log, and TCC records that are invaluable during incident response. Learning to configure these surfaces well is the same skill set as learning to read them during an investigation.

---

## Concepts

### The menu bar as a focused-app contract

The menu bar has two distinct zones:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Apple  │  App name  │  File  │  Edit  │  View  … │   [STATUS ITEMS]   │
│  menu   │  menu      │ App-specific menus ────────→│ ←── right side ──  │
└──────────────────────────────────────────────────────────────────────────┘
         ↑                                           ↑
    Always present                         Belongs to the OS / agents
    Reflects focused app                   Not tied to any single app
```

**Left side — app menus.** These belong to whichever application owns focus. Click a different app and every menu item changes. The first menu after the Apple menu is always the *application menu* (named after the app), and it always contains Preferences/Settings, Hide, Hide Others, Quit, and About. This is a macOS HIG contract, not a convention.

**Right side — status items.** These are small UI elements injected by background agents (`NSStatusItem` API), the OS itself (clock, Spotlight, Siri, Control Center, Wi-Fi, Bluetooth, etc.), and third-party apps. Each status item runs in its parent process — there is no "system tray host" process. If you kill `SystemUIServer`, you kill all the OS-owned status items and the system restarts that process immediately.

> 🪟 **Windows contrast:** The Windows taskbar conflates running apps (left/center) with the system tray (right), both visible all the time regardless of which app is focused. macOS has no persistent "running app" list in the menu bar — that lives in the Dock. The menu bar's left side is *strictly* the focused app's menus; its right side is strictly ambient/status content.

#### SystemUIServer and the status-item host

`SystemUIServer` (located at `/System/Library/CoreServices/SystemUIServer.app`) is the process that hosts Apple's own status items: clock, Spotlight, Control Center, Siri, Wi-Fi, Bluetooth, Volume, and more. You can observe it in Activity Monitor or with `ps aux | grep SystemUIServer`.

```bash
# See everything SystemUIServer loads as menubar extras
defaults read com.apple.systemuiserver menuExtras
```

Output is an array of bundle paths like `/System/Library/CoreServices/Menu Extras/Bluetooth.menu`, `/System/Library/CoreServices/Menu Extras/Clock.menu`, etc. These `.menu` bundles are loadable bundles (not apps) injected into `SystemUIServer`'s process space.

> 🔬 **Forensics note:** The `com.apple.systemuiserver` plist at `~/Library/Preferences/com.apple.systemuiserver.plist` records which menu extras are active and in what order. On a compromised machine, an unusual or unsigned `.menu` bundle appearing in this array or in the `menuExtras` key is a red flag — it is an effective persistence mechanism that survives most remediation steps short of a wipe. Cross-reference against a known-good baseline.

### Managing menu bar real estate

**Reordering and removing OS-owned items.** Hold `⌘` and drag any status item left or right to reorder it. Drag it *off* the menu bar while holding `⌘` to remove it (it disappears with a puff animation). This works for Apple's own items. Not all third-party status items support `⌘`-drag — it depends on whether the developer set the `NSStatusItem` to movable.

**The notch problem.** The 14" and 16" MacBook Pro (M1 Pro/Max onward), the M3 MacBook Air (2024+), and the M4 MacBook Air all have a camera notch at the top center of the display. The OS renders the menu bar in two "wings" that flank the notch. Status items are right-justified, so when enough icons accumulate, they slide *under* the notch and vanish — silently, with no warning. You cannot click them. This is distinct from macOS hiding them; they are simply outside the clickable regions.

**Third-party menu bar managers** address this problem plus general clutter:

| Tool | Model | Notch handling | macOS 26 status |
|------|-------|---------------|-----------------|
| **Bartender 6** | Paid (~$18 one-time) | Yes — dedicated hidden bar beneath menu bar | Fully compatible with Tahoe/Liquid Glass |
| **Ice** | Free, open source | Yes | Active development; handles notch well |
| **Thaw** | Free, open source (Ice fork) | Yes — "Thaw Bar" for notch machines | Tahoe-focused fork, stable |
| **Barbee** | Free tier + paid | Yes | Supports auto-show rules |
| **Hidden Bar** | Free | Partial — icons can still slide behind notch | Lacks notch-awareness |

Ice (GitHub: `jordanbaird/Ice`) is the current community-recommended free option. It supports three sections: **visible**, **hidden** (reveal by clicking Ice's own icon or a hotkey), and **always-hidden** (never surfaced). Thaw is the stable fork if Ice development goes quiet again.

### macOS 26 Tahoe: Control Center redesign

In macOS 26, Control Center received a substantial redesign under the **Liquid Glass** aesthetic — translucent, refractile surfaces that reveal background content. The menu bar itself is now translucent by default ("Show menu bar background" is off). If you find it visually noisy, enable the background: **System Settings → Appearance → Menu Bar → Show menu bar background**.

**Opening Control Center.** Click the two-toggle icon in the menu bar (or press the dedicated key on recent Apple keyboards). In Tahoe it slides out as a floating panel with Liquid Glass rendering.

**Editing the layout.** Click **Edit Controls** at the bottom of Control Center. You can:

- Drag items from the sidebar into Control Center to add them.
- Drag items within Control Center to reorder.
- Right-click (Control-click) any item → **Small / Medium / Large** to resize it.
- Drag items to the menu bar strip to "pin" them as permanent status items — they then appear in both places.

Default Control Center modules (Tahoe):

| Module | What it controls |
|--------|-----------------|
| Wi-Fi | Network selection + status |
| Bluetooth | Device pairing + on/off |
| AirDrop | Receiver mode |
| Focus | Active mode + quick-switch |
| Stage Manager | Toggle |
| Screen Mirroring | AirPlay targets |
| Display | Brightness, Night Shift, True Tone |
| Sound | Volume + output selection |
| Now Playing | Transport controls for audio |
| Keyboard Brightness | Backlit keyboard level |
| Accessibility Shortcuts | Configured shortcuts |
| Battery | Level + low-power mode |
| Fast User Switching | Switch without logout |
| Screen Lock | Immediate lock |
| Hearing | Headphone accommodations |

You can also add **Shortcuts** triggers to Control Center — useful for one-tap automation that used to require Raycast or Alfred.

**Pinning items to the menu bar** is distinct from keeping them in Control Center. To pin: open Control Center, drag a module toward the menu bar strip, and drop it there. It will display as a persistent icon. To unpin: `⌘`-drag it off.

> 🪟 **Windows contrast:** Windows 11's Quick Settings panel (Win+A) is conceptually equivalent to Control Center — a slide-in panel of toggles. The key difference is that macOS modules can be individually sized and re-ordered within the panel, and specific items can be "promoted" to always-visible status bar icons. Windows Quick Settings has a fixed layout.

### Notification Center and widgets

Swipe two fingers left from the right edge of the trackpad, or click the clock in the menu bar, to open Notification Center. It consists of two sections: **Widgets** (top) and **Notifications** (below).

**Notification grouping.** Notifications are grouped by app and then by *thread* (if the app supports notification thread identifiers via `UNNotificationRequest.threadIdentifier`). You can expand a group by clicking the chevron, clear a group with the X button, or dismiss the entire stack.

**Notification delivery mechanics.** Delivery goes through `UserNotificationsServer` (part of the `usernoted` daemon chain). The daemon persists notification state in:

```
~/Library/Application Support/com.apple.notificationcenter/
```

Inside you will find SQLite databases — notably `db2/db` — containing notification history, app records, and delivery timestamps. This is forensically significant: even *dismissed* notifications may remain in the database.

> 🔬 **Forensics note:** The notification database at `~/Library/Application Support/com.apple.notificationcenter/db2/db` is a SQLite file. Query it (copy it first — it may be locked) to see what apps have fired notifications and when. Table `record` has `delivered_date` (CoreData timestamp: seconds since 2001-01-01), `app_id`, and `data` (a bplist blob containing the notification payload). This can reconstruct timeline activity even after a user has cleared Notification Center.

```bash
# Copy first, then query
cp ~/Library/Application\ Support/com.apple.notificationcenter/db2/db /tmp/nc.db
sqlite3 /tmp/nc.db "SELECT app_id, datetime(delivered_date + 978307200, 'unixepoch', 'localtime') as ts FROM record ORDER BY delivered_date DESC LIMIT 20;"
```

**Widgets.** Widgets in Notification Center use the same WidgetKit framework as iPhone Lock Screen widgets and the Desktop widgets introduced in Sonoma/Tahoe. They update on a background schedule (not real-time) defined by the widget's `TimelineProvider`. To add widgets: scroll to the bottom of Notification Center → **Edit Widgets** → drag from the picker. You can also place widgets directly on the desktop (Sonoma+) by right-clicking the desktop → **Edit Widgets**.

### Focus modes

Focus is macOS's structured interruption-management system, more powerful than the old Do Not Disturb. Each Focus mode is a named profile with:

- **Allowed notifications** (specific people and apps can always break through)
- **Notification filters** (suppress others)
- **Focus filters** per app (e.g., restrict Mail to show only a specific mailbox, Safari to a specific Tab Group)
- **Home Screen / Lock Screen customization** (syncs to iPhone/iPad via iCloud)

Built-in modes: Do Not Disturb, Personal, Work, Sleep, Driving. You can create custom modes.

**Automation triggers** (the powerful part):

- Time-based: "Work" enables Mon–Fri 09:00–18:00.
- Location-based: "Work" enables when at a GPS coordinates region.
- App-based: "Driving" enables when CarPlay connects.
- Smart Activation: iOS/macOS infers intent from context signals (calendar events, location, app usage). Leave this off if you want deterministic behavior.

**Focus filters** are set per-app inside System Settings → Focus → (select a mode) → Add Filter. Safari, Mail, Messages, and Calendar have native filter support. Third-party apps must adopt the `AppIntents`/`FocusFilter` protocol to participate.

**Command-line introspection:**

```bash
# Current active Focus (if any)
defaults read ~/Library/Preferences/com.apple.ncprefs.plist enabled_modes 2>/dev/null
# Or via the Focus domain
defaults read com.apple.focus.modes
```

> 🔬 **Forensics note:** Focus mode state is written to `~/Library/Preferences/com.apple.focus.modes.plist` and synced to CloudKit under the `com.apple.private.CloudKit.focuses` CKRecordType when iCloud is active. If you are investigating whether a subject was in a call-silencing mode at a specific time, the Unified Log under subsystem `com.apple.focus` records mode transitions with timestamps.

```bash
log show --predicate 'subsystem == "com.apple.focus"' --last 7d --style compact | grep -i "mode"
```

### The clock and date format

The menu bar clock is controlled by `SystemUIServer`. To configure: System Settings → Control Center → Clock Options. You can set:

- 12-hour vs. 24-hour
- Show seconds
- Show date (always / when space allows / never)
- Flash time separators
- Use analog clock face

From the command line:

```bash
# Show seconds in the clock
defaults write com.apple.menuextra.clock ShowSeconds -bool true

# 24-hour time
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true

# Restart SystemUIServer to pick up changes
killall SystemUIServer
```

### Spotlight and Siri in the menu bar

**Spotlight** appears as a magnifying glass icon. Invoking it (⌘Space by default) launches `Spotlight.app` (actually a process of `corespotlightd` + the UI). The menu bar icon is purely a click target — you can hide it in System Settings → Siri & Spotlight → Spotlight (toggle off the menu bar icon). The ⌘Space hotkey works whether or not the icon is visible. See [[03-spotlight-as-launcher]] for the deep dive on Spotlight indexing internals.

**Siri** has its own status item. You can hide it (System Settings → Siri & Spotlight → Ask Siri → uncheck Show Siri in menu bar) and still invoke it with the configured keyboard shortcut. Siri requests in the menu bar context spawn `SiriNCService` and route through Apple's servers unless you have enabled On-Device Siri (available on M-series chips with macOS 15+/26). On-device requests stay local; cloud requests log to Apple's servers under your Apple ID.

### Menu bar real estate on notched displays

When your menu bar items overflow, the OS uses a priority ordering to decide what to sacrifice:

1. App menus on the left are shortened or truncated first (deep menu hierarchies push items off-screen).
2. Status items on the right slide left — eventually behind the notch, where they become unreachable.

The safe zone depends on the display model. On a 14" MacBook Pro (M4), the notch is approximately 225 pt wide. The OS allocates ~80 pt on each side of the notch as a dead zone. With large text (e.g., accessibility scaling), the dead zone widens further.

Use a menu bar manager to define a hard cutoff and move overflow items to a secondary panel — this is more reliable than trying to keep icons under a pixel count.

---

## The Dock

The Dock is managed by the `Dock.app` process (`/System/Library/CoreServices/Dock.app`). Despite being called "Dock.app," it is a background process that also hosts Mission Control, Exposé, and the Launchpad grid. Killing it restarts it immediately:

```bash
killall Dock   # restarts Dock instantly; no data lost
```

### Anatomy

```
┌──────────────────────────────────────────────────────────┐
│  [ Persistent app icons ]  │  [ running-only ]  │  [▸]  │
│  (user-pinned)             │  (no pin; dot below)│Trash  │
└──────────────────────────────────────────────────────────┘
                            ↑
                        Divider line
                      (drag to resize
                       persistent zone)
```

- **Left of divider** — persistent items (pinned apps, folders/stacks). Appear regardless of whether the app is running.
- **Right of divider** — running-only apps without a pin. Disappear when the app quits.
- **Far right** — Downloads stack (default), Trash.

**Running indicator dots.** A small dot beneath an icon means the app is running (has at least one process in the foreground or background). Absence of a dot means the app is not running. This is purely cosmetic — the Dock queries the kernel process list to paint these.

> 🪟 **Windows contrast:** The Windows taskbar conflates pinned shortcuts and running app buttons in one flat list, often with window thumbnails on hover. macOS separates pinned (persistent) from running (ephemeral) at the divider. Windows has no direct equivalent of the Dock's "running dot" — instead Windows highlights or underlines a taskbar button when it's running. The Dock also never shows window thumbnails natively (that's Mission Control/Exposé territory).

### Position, size, magnification

- **Position:** Bottom (default), left, or right. System Settings → Desktop & Dock → Position on screen. Or: right-click the divider → Position on Screen.
- **Size:** Drag the divider up/down, or System Settings → Desktop & Dock → Size slider.
- **Magnification:** Enables icon zoom on hover. System Settings → Desktop & Dock → Magnification checkbox + size slider.
- **Auto-hide:** Dock hides until cursor touches the screen edge. System Settings → Desktop & Dock → Automatically hide and show the Dock.

All of these are `defaults write com.apple.dock` keys under the hood:

```bash
# Position: left / bottom / right
defaults write com.apple.dock orientation -string bottom

# Icon size in points
defaults write com.apple.dock tilesize -int 48

# Enable magnification
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock largesize -int 80

# Autohide
defaults write com.apple.dock autohide -bool true

# Remove autohide animation delay (snap instantly)
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.4

# Apply all changes
killall Dock
```

> 🔬 **Forensics note:** The Dock's persistent state — every pinned app, its order, folder stacks, and recent apps — lives in `~/Library/Preferences/com.apple.dock.plist`. This plist is a binary property list. Read it with `plutil -p ~/Library/Preferences/com.apple.dock.plist` or `defaults read com.apple.dock`. On a forensic image you can parse it with any plist parser (macOS `plutil`, Python `plistlib`, or `plutil` from `libimobiledevice`). The `persistent-apps` and `recent-apps` arrays tell you what the user had pinned and what they used recently, which is useful for behavioral reconstruction.

### Minimize behavior

By default, windows minimize using the Genie animation into the right side of the Dock (left of Trash). You can:

- Change animation: System Settings → Desktop & Dock → Minimize windows using → **Genie** or **Scale**. Scale is faster.
- **Minimize into app icon:** System Settings → Desktop & Dock → "Minimize windows into application icon" — toggles whether minimized windows collapse into the app's Dock tile instead of creating a separate miniaturized window icon. Power users generally prefer this on; it reduces Dock clutter. The window is still accessible via the app's Dock icon → right-click → window list, or by clicking the app icon.

```bash
# Enable minimize-into-app-icon
defaults write com.apple.dock minimize-to-application -bool true
killall Dock
```

### Adding, removing, and rearranging apps

- **Add to Dock:** Drag an app from Finder into the persistent zone. Or open the app → right-click Dock icon → Options → Keep in Dock.
- **Remove from Dock:** Drag the icon out of the Dock until "Remove" appears, then release. (App is not deleted — only the Dock pin is removed.)
- **Rearrange:** Drag icons left/right within the persistent zone.
- **Open with Dock:** Drag a file onto a Dock app icon to open that file in the app. Works even for apps not normally associated with the file type — the app receives the file path via the `application:openFile:` delegate or Apple Events.

### Stacks and folder viewing

Any folder in the Dock right-click offers **View content as** (Fan, Grid, List, Automatic) and **Sort by** (Name, Date Added, Date Modified, Date Created, Kind). Automatic chooses Fan (small count) or Grid (larger count).

**Downloads stack behavior** is worth understanding: it is not a "smart folder" — it monitors the actual `~/Downloads/` directory and reflects its current contents live. There is no indexing delay.

```bash
# Add an arbitrary folder as a Dock stack
defaults write com.apple.dock persistent-others -array-add \
  '<dict>
    <key>tile-data</key>
    <dict>
      <key>file-data</key>
      <dict>
        <key>_CFURLString</key>
        <string>file:///Users/YOURNAME/Projects/</string>
        <key>_CFURLStringType</key>
        <integer>15</integer>
      </dict>
      <key>showas</key>
      <integer>2</integer>  <!-- 1=Fan 2=Grid 3=List 0=Auto -->
      <key>arrangement</key>
      <integer>1</integer>  <!-- 1=Name 2=DateAdded 3=DateModified 4=DateCreated 5=Kind -->
    </dict>
    <key>tile-type</key>
    <string>directory-tile</string>
  </dict>'
killall Dock
```

Replace `YOURNAME` and the path. `showas` and `arrangement` integers correspond to the GUI options above.

### Recent apps section

System Settings → Desktop & Dock → "Show suggested and recent apps in Dock" controls whether a third, floating section appears at the right end of the persistent zone, populated by apps you used recently but do not have pinned. Forensically, this list reflects recent usage and is persisted in `com.apple.dock.plist` → `recent-apps`.

---

## Hands-on (CLI & GUI)

### Inspect the current Dock configuration

```bash
# Human-readable dump of the entire Dock plist
defaults read com.apple.dock

# Just the persistent apps (what's pinned)
defaults read com.apple.dock persistent-apps | grep 'file-label' | sed 's/.*= "\(.*\)";/\1/'

# Just the recent apps
defaults read com.apple.dock recent-apps | grep 'file-label' | sed 's/.*= "\(.*\)";/\1/'
```

### Read the notification database

```bash
# Copy to avoid locking issues
cp ~/Library/Application\ Support/com.apple.notificationcenter/db2/db /tmp/nc.db

# Schema
sqlite3 /tmp/nc.db ".schema"

# Recent delivered notifications
sqlite3 /tmp/nc.db \
  "SELECT app_id, datetime(delivered_date + 978307200, 'unixepoch', 'localtime') as ts, note
   FROM record
   ORDER BY delivered_date DESC
   LIMIT 30;"
```

The `note` column is a binary plist blob. Extract it per-row to read the notification title and body:

```bash
sqlite3 /tmp/nc.db "SELECT note FROM record WHERE app_id='com.apple.mail' LIMIT 1;" \
  | xxd | head   # raw hex; use Python's plistlib to deserialize properly
```

### Check Focus mode state

```bash
# See configured Focus modes
plutil -p ~/Library/Preferences/com.apple.focus.modes.plist

# Log Focus transitions for the past 48h
log show \
  --predicate 'subsystem == "com.apple.focus" AND category == "FocusManager"' \
  --last 48h \
  --style compact
```

### Inspect SystemUIServer menu extras

```bash
# List loaded menu extras
defaults read com.apple.systemuiserver menuExtras

# Show all user-set SystemUIServer prefs
defaults read com.apple.systemuiserver
```

---

## Labs

### Lab 1: Tame the menu bar

> ⚠️ **ADVANCED:** Removing or rearranging status items is non-destructive — you can restore any Apple-owned item through System Settings → Control Center. Third-party items can be restored from the app's own preferences. No backup required, but note your current layout before starting.

1. Inventory your current status items. Count everything visible in the menu bar.
2. `⌘`-drag every Apple status item you use daily to the left (closer to Control Center). `⌘`-drag rarely-used items off the bar entirely.
3. Open Control Center (click the two-toggle icon), then click **Edit Controls**. Pin at minimum: Wi-Fi, Bluetooth, Sound, Focus, Battery (if laptop). Unpin anything you access less than once a day.
4. If you have a notched MacBook: install Ice (`brew install --cask jordanbaird-ice`). Launch it, open Preferences, and set your hidden-section hotkey (recommend `⌥` + click the Ice icon). Move seldom-used items into the hidden section.
5. Set the clock to 24-hour with seconds:
   ```bash
   defaults write com.apple.menuextra.clock ShowSeconds -bool true
   defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
   killall SystemUIServer
   ```
6. Verify: the menu bar now shows only items you use, arranged left-to-right in priority order.

### Lab 2: Configure Focus modes for a forensics/dev workflow

> ⚠️ **NOTE:** Focus mode changes take effect immediately and sync to all devices signed into the same Apple ID via iCloud. If you use your iPhone or iPad for work, changes here ripple out. To roll back: System Settings → Focus → delete any Focus you create in this lab.

1. Create a custom Focus mode: System Settings → Focus → + → Custom → name it "Deep Work".
2. Add **Allowed Notifications** → People: only the contacts you'd interrupt an investigation for. Apps: none except perhaps a crash alerting app.
3. Add **Focus Filters**: Safari → assign a Safari Tab Group named "Research". Calendar → show only your work calendar.
4. Add an **Automation**: + → Add Schedule → Weekdays, 09:00–12:00.
5. Test it: enable Deep Work manually. Verify Safari switches Tab Groups. Send yourself a test notification from an excluded app — confirm it is silenced.
6. Observe the Unified Log transition:
   ```bash
   log show --predicate 'subsystem == "com.apple.focus"' --last 5m --style compact
   ```

### Lab 3: Power-configure the Dock

> ⚠️ **NOTE:** All `defaults write com.apple.dock` changes are immediately reversible by deleting the key or setting the opposite value + `killall Dock`. The Dock plist is at `~/Library/Preferences/com.apple.dock.plist`. Back it up first if you want a clean rollback:
> ```bash
> cp ~/Library/Preferences/com.apple.dock.plist ~/Desktop/dock-backup.plist
> ```
> **Rollback:** `cp ~/Desktop/dock-backup.plist ~/Library/Preferences/com.apple.dock.plist && killall Dock`

1. Set position, size, and instant autohide:
   ```bash
   defaults write com.apple.dock orientation -string bottom
   defaults write com.apple.dock tilesize -int 52
   defaults write com.apple.dock autohide -bool true
   defaults write com.apple.dock autohide-delay -float 0
   defaults write com.apple.dock autohide-time-modifier -float 0.3
   defaults write com.apple.dock minimize-to-application -bool true
   defaults write com.apple.dock magnification -bool true
   defaults write com.apple.dock largesize -int 80
   killall Dock
   ```
2. Add a Projects stack (replace path with your own):
   ```bash
   defaults write com.apple.dock persistent-others -array-add \
     '<dict><key>tile-data</key><dict>
       <key>file-data</key><dict>
         <key>_CFURLString</key><string>file:///Users/'"$USER"'/Documents/</string>
         <key>_CFURLStringType</key><integer>15</integer>
       </dict>
       <key>showas</key><integer>2</integer>
       <key>arrangement</key><integer>2</integer>
     </dict>
     <key>tile-type</key><string>directory-tile</string></dict>'
   killall Dock
   ```
3. Drag a test file onto Terminal in the Dock to verify drag-to-open works.
4. Open three apps, minimize one with Genie, verify it disappears into the app icon (not as a separate stack item).
5. Dump the current plist to confirm your changes persisted:
   ```bash
   defaults read com.apple.dock | grep -E 'tilesize|autohide|orientation|magnification'
   ```

### Lab 4: Forensic notification timeline reconstruction

> ⚠️ **NOTE:** Read-only; no system state is modified. The database is copied to `/tmp` before querying.

1. Copy and open the notification database:
   ```bash
   cp ~/Library/Application\ Support/com.apple.notificationcenter/db2/db /tmp/nc.db
   sqlite3 /tmp/nc.db ".tables"
   ```
2. Query the last 50 delivered notifications with human-readable timestamps:
   ```bash
   sqlite3 -column -header /tmp/nc.db \
     "SELECT app_id,
             datetime(delivered_date + 978307200, 'unixepoch', 'localtime') AS ts,
             encoded_data IS NOT NULL AS has_payload
      FROM record
      ORDER BY delivered_date DESC
      LIMIT 50;"
   ```
3. Find the app that notified most frequently:
   ```bash
   sqlite3 -column -header /tmp/nc.db \
     "SELECT app_id, count(*) as count
      FROM record
      GROUP BY app_id
      ORDER BY count DESC
      LIMIT 10;"
   ```
4. Note any `app_id` values you do not recognize — these warrant investigation via `codesign -dv --deep /Applications/<App>.app` and a check of its TCC entitlements.

---

## Pitfalls & gotchas

**"My app's menu items are grayed out or missing."** You are probably focused on the wrong app. The menu bar always reflects the *foreground* app, not the frontmost window. Click the app's window directly, or check the app name in the menu bar's second position.

**Status item disappears after reboot.** Third-party status items only appear if the app is running. Most background-agent apps install a LaunchAgent to auto-start at login (`~/Library/LaunchAgents/`). If an icon disappears after reboot, check `launchctl list | grep <appname>` and whether the Login Item survived in System Settings → General → Login Items.

**⌘-drag removes an item I didn't intend to remove.** Apple's own items can be restored: System Settings → Control Center → find the item → turn "Show in Menu Bar" back on. For third-party items: reopen the app and check its own preferences for a "Show in menu bar" toggle.

**Autohide Dock keeps reappearing while typing.** The Dock autohide trigger fires on cursor position, not intent. If you are typing near the screen edge on an external monitor, cursor drifts can trigger it. Increase the `autohide-delay` slightly (`-float 0.3`) to add hysteresis.

**Notification Center database is locked.** If `sqlite3` reports a locking error, the `usernoted` daemon holds a write lock. Always copy the database to `/tmp` before querying. On a forensic image this is a non-issue since the daemon is not running.

**Focus "Smart Activation" turns Focus on by itself.** If a Focus mode activates unexpectedly, check System Settings → Focus → (mode) → Smart Activation. Disable it for deterministic behavior.

**Liquid Glass and accessibility.** The translucent Liquid Glass menu bar and Dock reduce contrast for users with certain visual conditions. If you find it harder to read status icons: System Settings → Accessibility → Display → Increase Contrast overrides the transparency entirely and restores a solid opaque menu bar. This also suppresses the Liquid Glass effect in the Dock.

**Dock's `defaults write` changes silently ignored.** Some Dock keys are only read at launch. If `killall Dock` doesn't apply a change, log out and back in. Additionally, some keys are MDM-restricted in managed enterprise environments — `defaults write` succeeds but the preference domain is overridden at read time by a configuration profile.

---

## Key takeaways

- The menu bar left side is a **per-focused-app menu** — not a toolbar. Click the correct app first.
- Status items on the right are `NSStatusItem` instances injected into `SystemUIServer` (Apple items) or their own process (third-party). The `menuExtras` plist key is a forensic artifact.
- On notched MacBook Pros, overflow status items vanish silently behind the camera. Use Ice, Bartender, or Thaw to manage real estate explicitly.
- macOS 26 Tahoe's Control Center is fully customizable: drag modules in/out, resize them, and pin any module directly to the menu bar.
- Focus modes are the structured replacement for Do Not Disturb — they scope notifications, per-app content, and appearance, and they log transitions to the Unified Log.
- The notification database (`~/Library/Application Support/com.apple.notificationcenter/db2/db`) is a SQLite artifact that survives user-visible dismissal and carries timestamps in CoreData epoch (add 978307200 to convert to Unix time).
- The Dock's entire configuration lives in `com.apple.dock.plist` — persistent apps, stacks, icon size, recent apps — all readable and writable via `defaults write com.apple.dock` + `killall Dock`.
- Minimize-into-app-icon is the power-user default: it eliminates separate miniaturized window icons in the Dock.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| **NSStatusItem** | AppKit API that lets an app or agent insert an icon+popover into the menu bar's right side |
| **SystemUIServer** | macOS process hosting Apple's own status items (clock, Control Center icon, Wi-Fi, etc.) |
| **Menu Extra** (`.menu` bundle) | A loadable bundle injected into SystemUIServer to provide a status item; persistence tracked in `com.apple.systemuiserver` plist |
| **Control Center** | A slide-out panel aggregating system toggle modules, configurable per macOS 26 |
| **Liquid Glass** | Apple's translucent refractile design language introduced in macOS 26 Tahoe; affects menu bar, Dock, sidebars |
| **Focus mode** | A named notification and content filter profile (Work, Personal, custom) that throttles interruptions and scopes per-app content |
| **Focus filter** | A per-app configuration inside a Focus mode that constrains what content the app shows (e.g., Mail mailbox, Safari Tab Group) |
| **Notification Center** | The right-side slide-in panel surfacing grouped notifications and widgets |
| **usernoted** | The daemon chain (`usernoted`, `UserNotificationsServer`) that delivers and persists notifications |
| **CoreData epoch** | Apple's reference date of 2001-01-01 00:00:00 UTC; add 978307200 to convert to Unix epoch |
| **Dock.app** | The system process that renders the Dock, Mission Control, Exposé, and Launchpad |
| **Stack** | A Dock item representing a folder; views its contents as Fan, Grid, or List on click |
| **Persistent zone** | Left side of the Dock divider — user-pinned icons that appear whether or not the app is running |
| **Recent apps** | Auto-populated Dock section of recently used but unpinned apps; stored in `com.apple.dock.plist` → `recent-apps` |
| **Minimize into app icon** | Dock behavior where minimized windows collapse into the app's Dock tile rather than creating a separate thumbnail |
| **Notch dead zone** | The approximately ±80 pt region flanking the camera cutout on notched MacBook displays, where menu bar items become unclickable |

---

## Further reading

- [Apple Human Interface Guidelines — Menu Bars](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) — the authoritative HIG spec for what goes in the app menu, the menu bar, and the status area
- [Apple HIG — The Dock](https://developer.apple.com/design/human-interface-guidelines/the-dock) — Dock tile types, badge conventions, drag-and-drop contract
- [Howard Oakley / Eclectic Light Company — Appearance in Tahoe 26.1](https://eclecticlight.co/2025/11/05/appearance-revisited-get-tahoe-26-1-looking-in-better-shape/) — practical breakdown of Liquid Glass appearance settings and combinations to avoid
- [macos-defaults.com — Dock](https://macos-defaults.com/dock/) — curated, tested `defaults write` keys with screenshots
- [Ice (GitHub: jordanbaird/Ice)](https://github.com/jordanbaird/Ice) — open-source menu bar manager, actively maintained
- [Bartender 6](https://www.macbartender.com/) — commercial menu bar manager with notch support and Tahoe compatibility
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — Focus / Screen Time / TCC interactions
- [UNUserNotificationCenter documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) — the API behind notification delivery, thread identifiers, and filtering
- [[03-spotlight-as-launcher]] — deep dive on Spotlight indexing, the `corespotlightd` daemon, and MDQuery
- [[01-window-management]] — Mission Control, Spaces, and Stage Manager (also hosted by Dock.app)
- [[06-system-settings-tour]] — System Settings navigation, including the full Focus and Notifications panes
- [[10-unified-logging-and-diagnostics]] — how to query the Unified Log for Focus transitions, SystemUIServer events, and notification delivery records
