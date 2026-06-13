---
title: "Window management: Spaces, Mission Control, Stage Manager"
part: P02 GUI
est_time: 50 min read + 40 min labs
prerequisites: [01-boot-process]
tags: [macos, window-management, spaces, mission-control, stage-manager, tiling, gestures, productivity]
---

# Window Management: Spaces, Mission Control, Stage Manager

> **In one sentence:** macOS window management is a layered system — virtual desktops (Spaces), an overview compositor (Mission Control), an experimental focus mode (Stage Manager), and a native tiling engine introduced in Sequoia — and knowing which layer to reach for, and why, separates power users from everyone else.

---

## Why this matters

Coming from Windows, your muscle memory for `Win+D`, `Win+←/→`, and Task View maps to macOS equivalents that work differently at every layer. The macOS model is historically more gesture-first and less keyboard-first than Windows, but macOS 15 Sequoia finally delivered genuine drag-to-edge tiling (something Windows has had since Vista's Aero Snap in 2007). macOS 26 Tahoe builds on that foundation while making Mission Control and Stage Manager accessible from the redesigned Control Center.

For forensics work: window state, Space assignments, and Mission Control layout leave artifacts in `~/Library/Preferences/` and the `WindowServer` subsystem — understanding the machinery tells you where to look.

---

## Concepts

### The window-management stack

```
┌─────────────────────────────────────────────────────┐
│  Stage Manager (optional focus layer, macOS 13+)    │
├─────────────────────────────────────────────────────┤
│  Mission Control  (compositor overview)             │
│    └─ Spaces  (virtual desktops, per display)       │
│         └─ Tiling  (window layout within a Space)   │
├─────────────────────────────────────────────────────┤
│  WindowServer  (Quartz Compositor, SkyLight.framework)│
└─────────────────────────────────────────────────────┘
```

These are not mutually exclusive modes — they are concentric features. You can tile windows inside a Space while Stage Manager is disabled, and enter Mission Control from any of them.

---

### Mission Control

Mission Control is a full-screen overlay rendered by `Dock.app` (the process also manages Spaces). It shows:

- Every open window across all apps, grouped by app (not by Space by default)
- All Spaces in a strip at the top — including fullscreen apps and Split View pairs
- The current display's Space arrangement (with per-display Spaces enabled, each monitor has its own strip)

**How to invoke:**
| Method | Shortcut / gesture |
|---|---|
| Dedicated key | `F3` (Mission Control key on Apple keyboards) |
| Keyboard | `^↑` (Control + Up Arrow) |
| Trackpad | 3-finger swipe up (or 4-finger, depending on System Settings > Trackpad) |
| Magic Mouse | Double-tap with two fingers |
| Hot Corner | Configurable in System Settings > Desktop & Dock > Hot Corners |

**Within Mission Control:**
- Click any thumbnail to jump to that window/Space
- Drag a window thumbnail to a different Space strip slot to reassign it
- Drag to the `+` button (far right of the Space strip) to create a new Space
- Drag two windows onto the same Space strip slot to create a Split View pair

> 🔬 **Forensics note:** `Dock.app` holds the canonical Space-to-window mapping in memory. On disk, `~/Library/Preferences/com.apple.spaces.plist` stores the UUID, display association, and ordering of your Spaces. `~/Library/Preferences/com.apple.dock.plist` stores per-app Space assignments (`SpacesEnabled`, `wsapp-*` keys). `plutil -p` or `defaults read` both work for inspection.

---

### Spaces (virtual desktops)

Each Space is an independent desktop context managed by `Dock.app`. Windows within a Space share a Z-order stack; switching Spaces performs a Core Animation slide transition managed by the WindowServer's Quartz Compositor.

**Key behaviors:**
- Spaces are per-display when **"Displays have separate Spaces"** is enabled (System Settings > Desktop & Dock > Mission Control section). With it ON, each monitor runs an independent Space strip. With it OFF, all displays share one Space and switching slides both monitors in lockstep — useful for presentations, disruptive otherwise.
- Fullscreen apps (green button → "Enter Full Screen") each occupy their own Space. They appear in the Spaces strip as an app-icon thumbnail rather than a window thumbnail. The app is effectively removed from the normal window layer and gains a dedicated GPU plane.
- Split View pairs (two apps side-by-side fullscreen) also live as a single Space.
- Spaces are identified internally by UUID; the human-visible number is positional (Space 1, 2, 3…) and changes as you reorder.

**Space navigation:**
| Action | Shortcut |
|---|---|
| Move to Space N | `^1`, `^2` … `^9` (enable in System Settings > Keyboard > Keyboard Shortcuts > Mission Control) |
| Move left/right one Space | `^←`, `^→` |
| Move to last Space | No default; assign via Keyboard Shortcuts |
| Throw window to next Space | Drag it in Mission Control, or use a third-party tool |

**Assigning apps to Spaces:**
Right-click any app icon in the Dock → Options → **"This Desktop"** / **"All Desktops"** / **"None"**. This writes `com.apple.dock` plist key `wsapp-<bundleID>`. "All Desktops" makes the app appear on every Space — useful for utilities like a menu bar calculator. "This Desktop" pins it to whichever Space was active when you chose it — the assignment follows the Space UUID, not the Space number.

**Adding, removing, reordering Spaces:**
- In Mission Control: `+` button top-right adds a Space; hover a Space and click its `×` to remove.
- Drag Space thumbnails left/right to reorder.
- Command-line: no public API for creating Spaces. Third-party tools like `yabai` can create/destroy Spaces via Dock scripting addition injection.

> 🪟 **Windows contrast:** Windows virtual desktops (Task View, `Win+Tab` + "New desktop") are roughly equivalent but lack persistent per-app Space assignments and don't have a per-monitor-desktop concept that's as deeply integrated. macOS Spaces survive across login sessions; Windows Task View desktops are session-ephemeral unless you pin apps to specific desktops manually each time.

---

### Fullscreen apps as their own Space

When you click the green traffic light → "Enter Full Screen" (or press `^⌘F`), macOS creates a dedicated Space for that window. The transition is handled by the WindowServer: the window grows to fill the display using a Core Animation zoom + crossfade, then a new Space is inserted and the display slides to reveal it.

Implications:
- The app is now isolated from Mission Control's window-grouping view unless you explicitly switch to it.
- `⌘Tab` still brings it to focus; `^←` / `^→` slides to it.
- Split View (drag one fullscreen app's thumbnail onto another in Mission Control, or use the green button → "Tile Window to Left/Right of Screen") creates a pair — both apps share one fullscreen Space. Resize by dragging the central divider.
- Safari and other apps that support multiple windows can have some windows fullscreen and others in regular Spaces simultaneously.

---

### App Exposé

App Exposé shows all windows of the **currently focused app** spread across the screen — not all apps, unlike Mission Control.

**Invoke:**
- Trackpad: swipe down with three (or four) fingers while the app is frontmost
- Keyboard: `^↓` (Control + Down Arrow) — default, may conflict; remappable
- From Mission Control: click the app's group header

App Exposé respects Space scope: with "Group windows by application" ON in Mission Control settings, it shows windows across all Spaces. This is the fastest way to reach a buried Safari tab or a specific Finder window when you have dozens open.

---

### Stage Manager

Introduced in macOS 13 Ventura, Stage Manager is an optional window-management layer that sits between "standard windowing" and "fullscreen." Enable it via:
- Control Center → Stage Manager toggle
- System Settings > Desktop & Dock > Stage Manager

**Mechanism:** When active, `WindowServer` routes window layering through a Stage Manager compositor that:
1. Keeps one "stage" (app group) front-and-center, filling most of the screen
2. Pushes all other recent app groups to a strip on the left edge (the "shelf")
3. Automatically resizes/repositions windows when you switch stages

**When Stage Manager helps:**
- Single large display, many open apps — the shelf gives visual access to recent work without going to Mission Control
- Focus-intensive work where you want all non-active app windows out of view
- iPad-style workflow preferences

**When Stage Manager hurts:**
- Multi-monitor: the shelf only appears on the primary display (as of macOS 26 Tahoe; some improvement in per-display behavior was made in Tahoe but the shelf remains primarily single-display)
- Terminal/IDE workflows where you need overlapping windows from the same app visible simultaneously — Stage Manager's single-stage-per-app model fights this
- Spaces-heavy workflows — Stage Manager and Spaces interact awkwardly; each Space has its own stage, but dragging apps between Spaces via the shelf is non-obvious
- Power users who live in keyboard shortcuts — Stage Manager's shelf is mouse/gesture-first

> **Practical verdict for power users:** Most keyboard-driven users disable Stage Manager and rely on Spaces + Mission Control + tiling. Stage Manager has improved across macOS 13–26 but still has rough edges with Spaces interaction and multi-window pro apps (Xcode, Final Cut, Finder).

> 🔬 **Forensics note:** Stage Manager state is stored in `~/Library/Preferences/com.apple.WindowManager.plist`. Key of interest: `GloballyEnabled` (bool), `AutoHide` (bool, the shelf auto-hide setting). When examining a suspect Mac, the presence and configuration of this file tells you which macOS version the user was on and how their workflow was arranged.

---

### macOS window tiling (Sequoia+, refined in Tahoe 26)

Apple introduced native drag-to-edge tiling in macOS 15 Sequoia. macOS 26 Tahoe extends it. Three trigger methods:

**1. Drag to edge/corner:**
Drag a window by its title bar to a screen edge or corner. A translucent drop zone preview appears. Release to snap. Corners produce quarter tiles; edges produce half tiles. If `"Tile by dragging windows to screen edges"` is disabled in System Settings > Desktop & Dock, this does nothing.

**2. Green button menu:**
Hover (don't click) the green traffic light. A popup appears with layout choices: Left Half, Right Half, Top Half, Bottom Half, Fill, Center, and two-window arrangement options that let you choose a second app for the other pane from a thumbnail picker.

**3. Keyboard shortcuts (fn + Control + Arrow):**

| Shortcut | Effect |
|---|---|
| `fn ^←` | Left half |
| `fn ^→` | Right half |
| `fn ^↑` | Top half |
| `fn ^↓` | Bottom half |
| `fn ^F` | Fill screen (non-fullscreen, just maximizes) |
| `fn ^C` | Center window |
| `fn ^R` | Restore to pre-tile size/position |
| `fn ^⇧←` | Left half + bring another window to right half |
| `fn ^⇧→` | Right half + bring another window to left half |

The `fn ^⇧` variants trigger a window picker UI so you can choose what fills the complementary half — similar to Windows Snap Assist.

**4. Window menu:**
Every app's "Window" menu in macOS Sequoia+ gains a "Move & Resize" submenu with the same tiling operations. This is keyboard-accessible: `⌃F2` → Window → Move & Resize.

> 🪟 **Windows contrast:** Windows has had Aero Snap (drag-to-edge halving) since Windows 7 (2009). Windows 11 added Snap Layouts (hover the maximize button for a grid of multi-window arrangements). FancyZones (PowerToys) adds fully custom grid zones. macOS's native tiling arrived ~15 years later, has no equivalent of FancyZones custom zones, and currently supports halves/quarters only — no thirds, no sixths, no custom pixel grids. The fn+Control shortcuts are less discoverable than Win+Arrow. Third-party tools (Rectangle, Magnet) fill this gap.

---

### Why power users still install Rectangle / Magnet / yabai

**Rectangle** (free, open-source): Adds thirds, sixths, custom fractions, "almost maximize," multi-display throw, and fully configurable keyboard shortcuts. Integrates with macOS 15+ native tiling rather than fighting it. The community standard for users who want *more zones than halves/quarters* without going full tiling WM.

**Magnet** (~$2–5, App Store): Polished paid alternative to Rectangle. Broadly similar feature set. Uses global keyboard shortcuts that don't require `fn`.

**yabai** (open-source, GitHub: `koekeishiya/yabai`): A binary space partitioning (BSP) tiling window manager. Windows are automatically subdivided — add a window, the current Space splits; remove one, the space heals. Pairs with `skhd` for keyboard-driven focus/resize/move. The killer feature is scripting: yabai exposes a Unix socket (`/tmp/yabai-$UID.socket`) you can `curl` or pipe to, enabling fully automated window arrangements from shell scripts, cron jobs, or `karabiner` bindings.

yabai's full feature set (cross-Space window movement, Space creation/destruction, display movement) requires partially disabling SIP and loading a scripting addition into `Dock.app`:
```bash
# Check current SIP status — full output, not just "enabled"
csrutil status

# yabai scripting addition install (after partial SIP disable in recoveryOS)
sudo yabai --install-sa
sudo yabai --load-sa
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** Partially disabling SIP is a significant security reduction. It allows unsigned kernel extensions and scripting additions to run with elevated privileges. Back up via Time Machine and document your SIP status (`csrutil status > ~/sip-before-yabai.txt`) before entering recoveryOS. To re-enable full SIP: boot recoveryOS (`hold power until options screen` on Apple Silicon), Terminal → `csrutil enable`, reboot. See [[10-sip-and-system-integrity]] for full SIP coverage.

yabai without the scripting addition (SIP fully enabled) still provides tiling layout management for windows within a single Space — it just cannot manipulate Spaces or focus across them via scripting.

> 🔬 **Forensics note:** yabai's scripting addition installs a bundle into `/System/Library/ScriptingAdditions/` (even on Apple Silicon, via the partial-SIP bypass). Its presence on a suspect Mac indicates the user deliberately disabled SIP — a notable operational security posture to document.

---

### ⌘Tab and ⌘` — the overlooked nuances

**⌘Tab (app switcher):**
The app switcher is invoked by `Dock.app` — it shows running apps (not windows). Key nuances:

- While holding ⌘ with the switcher open, press `Q` to **quit** the highlighted app without releasing ⌘Tab — you never switch to it.
- Press `H` to **hide** the highlighted app.
- Press `1` to immediately switch to the most recently used window of the highlighted app.
- The switcher does **not** show minimized windows as separate entries — a minimized window's app appears but `Tab`-switching to it does not unminimize the window (it brings the app front but the window stays minimized). Work around: unminimize windows, or use `^↓` (App Exposé) after switching.
- The switcher crosses Space boundaries — selecting an app in another Space teleports you there.

> 🪟 **Windows contrast:** `Alt+Tab` on Windows shows individual windows, not apps. A Chrome with 12 windows gives you 12 Alt+Tab entries. macOS ⌘Tab shows one entry per app; use ⌘\` to cycle windows within the app. This is a fundamental model difference — app-centric vs. window-centric switching. Windows 11 kept the window-centric model; macOS has always been app-centric.

**⌘\` (backtick — cycle windows within an app):**
Cycles forward through all windows of the frontmost application. `⌘⇧\`` cycles backward. This is the fastest way to reach a second Finder window, a background Terminal tab-window, or a second document in Pages without touching the Dock or mouse.

Caveat: this cycles windows within the current Space only — windows of the same app in other Spaces are not reachable via ⌘\`.

---

### Hot Corners

Hot Corners trigger an action when the cursor touches a screen corner. Configure: System Settings > Desktop & Dock > Hot Corners (bottom of page).

Available actions: Mission Control, App Windows (App Exposé), Desktop (hide all windows), Notification Center, Lock Screen, Start/Stop Screen Saver, Quick Note, Launchpad, Sleep Display.

**Modifier-key variants:** Hold `⌥` while configuring a corner to require that key be held when triggering — prevents accidental activation. You can mix: one corner triggers on bare touch, another requires `⌥`.

> 🔬 **Forensics note:** Hot Corner configuration lives in `~/Library/Preferences/com.apple.dock.plist` under keys `wvous-tl-corner`, `wvous-tr-corner`, `wvous-bl-corner`, `wvous-br-corner` (integer action codes) and `wvous-*-modifier` (modifier mask). Corner code 2 = Mission Control, 3 = App Windows, 4 = Desktop, 13 = Lock Screen. Modifier 1048576 = `⌥`.

---

## Hands-on (CLI & GUI)

### Inspect current Space/window state

```bash
# List all spaces and their UUIDs via the defaults domain
defaults read com.apple.spaces

# Mission Control prefs — grouping, auto-rearrange, switch-on-open
defaults read com.apple.dock | grep -E "(expose|mission|spaces|wvous)"

# Hot corner assignments (numeric action codes)
defaults read com.apple.dock | grep wvous

# Stage Manager state
defaults read com.apple.WindowManager 2>/dev/null || echo "Stage Manager plist absent"
```

### Configure per-display Spaces from CLI

```bash
# Enable "Displays have separate Spaces"
defaults write com.apple.spaces spans-displays -bool false
# (counterintuitive: spans-displays false = each display has its own spaces)

# Disable "Automatically rearrange Spaces based on most recent use"
defaults write com.apple.dock mru-spaces -bool false

# Apply — must restart Dock for changes to take effect
killall Dock
```

### Navigate Spaces via keyboard

First, enable the shortcuts in System Settings > Keyboard > Keyboard Shortcuts > Mission Control:
- "Switch to Desktop 1" through "Switch to Desktop 9" — assign `^1` through `^9`
- These can also be set via:

```bash
# Read current Mission Control keyboard shortcut bindings
defaults read com.apple.symbolichotkeys | grep -A 3 '"118"'  # Space 1 = key 118, Space 2 = 119, etc.
```

### Inspect yabai socket (if installed)

```bash
# Query all managed windows
echo '{"action":"query","domain":"windows"}' | nc -U /tmp/yabai-$(id -u).socket | python3 -m json.tool

# Move focused window to Space 3
yabai -m window --space 3

# Create a new Space
yabai -m space --create
```

---

## 🧪 Labs

### Lab 1: Build a purposeful Space layout

> ⚠️ This lab modifies your Space configuration. Existing Spaces are non-destructively rearranged; no data is lost. To undo: open Mission Control and drag Spaces back to desired order, or delete created Spaces via the × in Mission Control.

1. Open Mission Control (`^↑`). Note how many Spaces you currently have.
2. Create three new Spaces by clicking `+`. You should now have at least four.
3. Assign apps to Spaces: right-click Terminal in Dock → Options → "This Desktop" (while Space 1 is active). Repeat for your browser on Space 2, a note-taking app on Space 3.
4. Close Mission Control. Navigate with `^1`, `^2`, `^3` — confirm each Space shows only its assigned apps.
5. In System Settings > Desktop & Dock > Mission Control, **disable** "Automatically rearrange Spaces based on most recent use." Re-confirm Space ordering stays fixed after switching.
6. Enable per-display Spaces if you have a second monitor: toggle "Displays have separate Spaces" and re-enter Mission Control to see independent Space strips per monitor.

---

### Lab 2: Configure Hot Corners for rapid workflow

> ⚠️ Hot Corner changes take effect immediately; no backup needed. To revert, return to System Settings > Desktop & Dock > Hot Corners and set corners back to "—" (disabled).

1. Open System Settings > Desktop & Dock > Hot Corners.
2. Set: top-left = Mission Control, top-right = Application Windows (App Exposé), bottom-left = Lock Screen (with `⌥` modifier to prevent accidental locking), bottom-right = Desktop (hide all windows).
3. Test each corner. Notice that the `⌥`-modified Lock Screen corner only activates when you hold `⌥` while nudging the corner.
4. Open several windows of one app (Finder, Safari). Move cursor to top-right — App Exposé spreads only that app's windows.
5. Verify from CLI: `defaults read com.apple.dock | grep wvous` — note the integer action codes and modifier masks.

---

### Lab 3: Exercise the native tiling engine

1. Open two apps (e.g., Terminal and Safari). Drag Terminal's title bar slowly to the left screen edge until the translucent blue zone appears. Release. It snaps to the left half.
2. With Terminal still snapped, drag Safari toward the right edge — it snaps to the right half. You now have a native Split View without using fullscreen.
3. Test keyboard tiling: click on Terminal, press `fn ^→` — it moves to right half. Press `fn ^←` — left half. Press `fn ^F` — fills screen (note: NOT fullscreen Space, just maximized in current Space). Press `fn ^R` to restore.
4. Hover the green button of any window — explore the multi-window layout picker. Choose a two-pane layout and pick a second app. Note the Snap Assist-style second-window picker.
5. Open Window menu of any standard macOS app → Move & Resize — invoke tiling via the menu. This is keyboard-accessible without memorizing fn shortcuts.

---

### Lab 4: Install and configure Rectangle

> ⚠️ Rectangle adds a menu bar icon and registers global keyboard shortcuts that may conflict with existing bindings. Uninstall by quitting Rectangle and moving `Rectangle.app` to Trash; shortcuts immediately cease.

```bash
# Install via Homebrew
brew install --cask rectangle

open /Applications/Rectangle.app
```

1. Grant accessibility permissions when prompted (System Settings > Privacy & Security > Accessibility).
2. Open Rectangle's preferences. Note shortcuts for thirds (`^⌥D`, `^⌥F`, `^⌥G` for left/center/right thirds by default).
3. Test: `^⌥←` for left half, `^⌥→` for right half, `^⌥↩` for maximize (not fullscreen). These are the defaults.
4. In Rectangle Preferences > Snap Areas, test drag-to-edge snapping — observe how Rectangle's snap behavior layeres with macOS native tiling.
5. Test "Almost Maximize" (usually `^⌥⇧↩`) — resizes the window to ~90% of screen, centered. Useful when you want breathing room.

---

### Lab 5 (optional, advanced): Install yabai in limited mode (SIP enabled)

> ⚠️ This lab installs yabai and `skhd` without disabling SIP. Full scripting addition features are unavailable, but BSP tiling within Spaces works. Uninstall: `brew uninstall yabai skhd; brew services stop yabai skhd`.

```bash
brew install koekeishiya/formulae/yabai
brew install koekeishiya/formulae/skhd

# Start services
brew services start yabai
brew services start skhd
```

Create a minimal `~/.config/yabai/yabairc`:
```bash
#!/usr/bin/env sh
yabai -m config layout bsp
yabai -m config window_gap 8
yabai -m config top_padding 8
yabai -m config bottom_padding 8
yabai -m config left_padding 8
yabai -m config right_padding 8
yabai -m config mouse_follows_focus on
```

Create a minimal `~/.config/skhd/skhdrc`:
```
# Focus window
alt - h : yabai -m window --focus west
alt - l : yabai -m window --focus east
alt - j : yabai -m window --focus south
alt - k : yabai -m window --focus north

# Move window
shift + alt - h : yabai -m window --warp west
shift + alt - l : yabai -m window --warp east

# Toggle float
alt - t : yabai -m window --toggle float
```

Open three windows. Watch yabai BSP-tile them automatically. Use `alt-h/j/k/l` to move focus without touching the mouse. Toggle a window to float with `alt-t` to temporarily break it out of the tiling layout.

> 🔬 **Forensics note:** yabai logs to `/tmp/yabai_$UID.out.log` and `/tmp/yabai_$UID.err.log`. These persist across launches until the OS clears `/tmp` (on reboot). On a suspect Mac, these logs reveal yabai usage history, Space manipulation commands, and scripting activity timestamps.

---

## Pitfalls & gotchas

**Minimized windows are second-class citizens.** `⌘M` minimizes to the Dock. ⌘Tab does not unminimize them. App Exposé does show minimized windows (dimmed, at the bottom), but they require a click — keyboard navigation in Exposé won't bring focus to them directly. Prefer hiding (`⌘H`) over minimizing — hiding keeps windows in the window layer so ⌘Tab, App Exposé, and ⌘\` all work.

**"Automatically rearrange Spaces" will betray your carefully assigned layout.** Leave it OFF (System Settings > Desktop & Dock > Mission Control). With it ON, macOS reorders Spaces by most-recently-used frequency, so your mental map of "Space 2 is always my browser" breaks within a day.

**Ctrl+number shortcuts aren't enabled by default.** Apple ships `^1`–`^9` Space switching shortcuts as *disabled*. You must manually enable each one in System Settings > Keyboard > Keyboard Shortcuts > Mission Control. Alternatively, assign them via `defaults write com.apple.symbolichotkeys`.

**Stage Manager + Spaces = friction.** Each Space maintains its own Stage Manager context, but moving windows between Spaces while Stage Manager is active requires dragging them in Mission Control rather than the shelf — the shelf is Space-scoped, not a global window picker.

**Per-display Spaces and the menu bar.** With per-display Spaces ON (the recommended setting for multi-monitor), the menu bar on each display shows the menu for the frontmost app on *that display*. With it OFF, only the primary display has a menu bar (or both show the same one). This surprises users who expect consistent behavior.

**fn + Control tiling shortcuts conflict with some keyboards.** On non-Apple keyboards or with certain accessibility remaps, `fn` behavior varies. If `fn ^←` doesn't tile, check System Settings > Keyboard > Function Keys and confirm fn key behavior. Also confirm no other app has grabbed these shortcuts.

**yabai and Sequoia/Tahoe native tiling fight each other.** If both are active, you'll get double snap previews and unpredictable behavior. Disable native tiling (System Settings > Desktop & Dock > uncheck "Tile by dragging windows to screen edges") when running yabai.

**Space UUIDs, not numbers, are what macOS stores.** When you delete and recreate Spaces, app assignments (which were stored by UUID) become orphaned. The Dock plist retains stale UUIDs indefinitely. If apps are behaving strangely in new Spaces, `defaults delete com.apple.spaces` (then killall Dock) resets the Space database — but you lose all per-app Space assignments.

---

## Key takeaways

1. **Mission Control is the overview compositor; Spaces are the actual virtual desktops.** They are distinct layers managed by `Dock.app`.
2. **Disable "Automatically rearrange Spaces"** — it destroys the spatial memory that makes Spaces useful.
3. **Enable per-display Spaces** on multi-monitor setups. The per-display independence is the whole point.
4. **Prefer ⌘H (hide) over ⌘M (minimize)** — hidden windows remain fully accessible via ⌘Tab and App Exposé; minimized windows require extra clicks.
5. **Native tiling (Sequoia+)** gives you halves/quarters via drag, green button, or fn+Control+Arrow. For thirds, sixths, or custom layouts, install Rectangle.
6. **yabai** is the only path to a true BSP/grid tiling WM on macOS — at the cost of partial SIP disable for full features.
7. **Stage Manager** works best on single large displays for focus-intensive single-app work. Power users with multi-monitor or complex window arrangements should leave it off.
8. **⌘\`** (backtick) is the underused shortcut for cycling windows within one app — faster than Dock or Mission Control for multi-window apps.
9. **⌘Tab + Q/H** lets you quit or hide an app while in the switcher without ever activating it.
10. Forensically: `com.apple.spaces.plist`, `com.apple.dock.plist`, `com.apple.WindowManager.plist`, and yabai's `/tmp/yabai_$UID.*.log` are your primary window-management artifacts.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Space** | A virtual desktop managed by `Dock.app`; identified internally by UUID |
| **Mission Control** | Full-screen overview compositor showing all windows and Spaces |
| **App Exposé** | Per-app window overview for the frontmost application |
| **Stage Manager** | Focus-mode layer (macOS 13+) that groups apps into a "stage" with a shelf of recents |
| **Split View** | Two apps sharing a single fullscreen Space side-by-side |
| **BSP (Binary Space Partitioning)** | yabai's tiling algorithm — new windows automatically subdivide the available space |
| **Scripting Addition** | A bundle injected into another process (here: Dock.app) to extend its AppleScript/automation capabilities |
| **SIP (System Integrity Protection)** | Kernel-enforced policy preventing modification of system files and process injection; must be partially disabled for yabai's scripting addition |
| **Hot Corner** | Screen corner gesture triggering a configured system action |
| **WindowServer** | The macOS compositor daemon (uses Quartz/SkyLight framework) that owns all window rendering and input routing |

---

## Further reading

- [Apple Support: View open windows and spaces in Mission Control](https://support.apple.com/guide/mac-help/view-open-windows-spaces-mission-control-mh35798/mac)
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — SIP and process isolation, relevant to yabai's scripting addition
- [Rectangle GitHub](https://github.com/rxhanson/Rectangle) — open-source window manager; read the `CHANGELOG.md` for macOS version-specific fixes
- [yabai Wiki](https://github.com/koekeishiya/yabai/wiki) — scripting addition install, SIP partial-disable steps, socket API reference
- [Howard Oakley (Eclectic Light Company) — Mission Control and Spaces deep dives](https://eclecticlight.co) — search "Spaces" and "Mission Control" for low-level WindowServer analysis
- [macOS Sequoia Window Tiling — full shortcut reference](https://www.slashgear.com/1673225/macos-sequoia-window-tiling-shortcuts/)
- [[02-keyboard-shortcuts]] — system-wide shortcut architecture and remapping
- [[10-sip-and-system-integrity]] — full SIP coverage before partially disabling it for yabai
