---
title: "Windowing, multitasking & external display"
part: "05 — iPadOS as a Computer"
lesson: 01
est_time: "45 min read + 20 min labs"
prerequisites: [how-ipados-diverges-from-ios]
tags: [ios, ipados, windowing, multitasking, stage-manager, external-display]
last_reviewed: 2026-06-26
---

# Windowing, multitasking & external display

> **In one sentence:** iPadOS 26 grafts a macOS-style free-floating window model — traffic lights, a menu bar, overlapping resizable windows, and an extended-desktop external display — onto the same `SpringBoard`/`FrontBoard`/`BackBoard` scene stack that has always run the iPad, and the *arrangement* of those windows is a forensic record of what the user was actively doing.

## Why this matters

For fifteen years the iPad ran exactly one app's UI at full screen, then bolted on Split View / Slide Over (iOS 9) and Stage Manager (iPadOS 16) as constrained exceptions. iPadOS 26 replaces all of that with a real windowing system that deliberately converges on the Mac. As an engineer you need to know this is *not* a new OS layer — it is the **same scene-graph and render-server machinery** you already know from iOS, re-tuned to keep many scenes live at once. As a forensic examiner you gain something macOS gave you years ago: persisted **window and multitasking state** that answers "what apps were open, arranged how, and which were on screen?" That state lives in `applicationState.db`, in per-scene snapshots, and in the home-screen layout stores — none of which the suspect thinks to clean. This lesson maps the mechanism and the artifacts, and it does so without a physical iPad: the Simulator gives you the on-disk *structure*, and public sample images give you the device-only stores.

## Concepts

### The 2026 model is FOUR coexisting modes, not "Stage Manager vs. Split View"

The single biggest reframe coming from iPadOS 18: stop thinking "Split View *or* Stage Manager." iPadOS 26 has **four window presentation modes that coexist on one device**, and the user (or an app's scene API) moves windows between them fluidly. Internally they are all the same `UIScene`s composited by the same render server — the "mode" is just how `SpringBoard` arranges and clips the scene layers.

| Mode | What it is | macOS analogue | Per-display window count | Availability (iPadOS 26) |
|---|---|---|---|---|
| **Full-Screen** | One scene fills the display; the classic iOS presentation | A maximized/zoomed window | 1 visible | All iPads |
| **Windowed Apps** | Free-floating, overlapping, freely-resizable windows with traffic-light controls + a menu bar | Standard Mac desktop windowing | "Unlimited" up to a RAM-bound active cap (reported ≈12 on M-series) | All iPadOS-26 iPads (active-window cap lower on non-M) |
| **Stage Manager** | Grouped *stages* (sets of windows) with a left-edge strip of recent stages | macOS Stage Manager | Many per stage (4-app cap **lifted** on M1+) | **All** iPadOS-26 iPads (was M-/A12X-class only) |
| **Slide Over** | A single floating, resizable window hovering above whatever is behind it | Floating utility / always-on-top panel | 1 overlay window | Restored in **26.1** |

The mode is a property of the **workspace/display**, not a global switch as it felt in iPadOS 16. You can run Windowed Apps on the built-in display and Stage Manager on an external one; a Slide Over window can float over any of them. This is why the old mental model breaks — there is no single toggle that is "on" or "off."

> 🖥️ **macOS contrast:** You already learned macOS's window model: the `WindowServer` compositor, Mission Control spaces, and Stage Manager grouping. iPadOS 26 is a deliberate convergence — Apple gave the iPad the **traffic lights, a menu bar, and free resize** you know from the Mac. The crucial difference is *who composites*: on macOS it is the standalone `WindowServer` process; on iPadOS the same job is split across `backboardd` (the render server) and `SpringBoard` (the arranger). Same outcome, different process topology.

### The scene/render stack: SpringBoard, FrontBoard, BackBoard — the iPad's "WindowServer"

There is no process literally named `WindowServer` on iOS/iPadOS. The Mac's single compositor is split into a three-layer stack you should be able to name precisely:

```
 ┌──────────────────────────────────────────────────────────────┐
 │  Per-app process (e.g. MobileSafari)                          │
 │    UIKit / SwiftUI  →  UIScene  →  CALayer tree               │
 │    renders into IOSurfaces (shared GPU buffers)              │
 └───────────────┬──────────────────────────────────────────────┘
                 │ Mach IPC (scene lifecycle, layer commits)
 ┌───────────────▼──────────────────────────────────────────────┐
 │  FrontBoard  (frontboardd / linked into SpringBoard)          │
 │    FBSScene / FBSSceneManager — app & SCENE lifecycle,        │
 │    foreground/background, scene state, who is "live"          │
 └───────────────┬──────────────────────────────────────────────┘
 ┌───────────────▼──────────────────────────────────────────────┐
 │  BackBoard  (backboardd)                                      │
 │    the Core Animation RENDER SERVER (compositor) +            │
 │    hardware event dispatch (touch/pencil/keyboard), display   │
 └───────────────┬──────────────────────────────────────────────┘
 ┌───────────────▼──────────────────────────────────────────────┐
 │  SpringBoard  (the system UI: Home Screen, Dock, switcher)    │
 │    ARRANGES scenes into windows/stages; owns the layout       │
 └──────────────────────────────────────────────────────────────┘
```

- **`backboardd`** (BackBoard) is the closest thing to the Mac's `WindowServer`: since iOS 6 it hosts the **Core Animation render server** that composites every process's layer tree, and it owns the hardware-event pipeline (touch, Apple Pencil, trackpad, keyboard) — see [[trackpad-keyboard-and-apple-pencil]].
- **`frontboardd`** / the **FrontBoard** framework manages **scene and application lifecycle** — which app is foreground, which scenes exist, their state. This is the layer iPadOS 26 leans on hardest, because "many windows live at once" is fundamentally a scene-lifecycle problem.
- **`SpringBoard`** is the system UI process (Home Screen + Dock + app switcher + status bar) — functionally the iPad's Finder + Dock + `loginwindow` rolled into one. It *arranges* scenes into the four modes above.

The app side is the **`UIScene`** model (introduced iOS 13 for the first "multiple windows on iPad" support). One app **process** can vend multiple `UIWindowScene`s, each with its own `UISceneSession`. The `UIApplicationDelegate` owns process-level lifecycle; the `UISceneDelegate` owns per-window UI lifecycle. Every window you see in Windowed Apps mode is a `UIWindowScene` backed by a `UISceneSession`. This matters for the dev lessons ([[app-lifecycle-scenes-and-background-execution]]) and for forensics: scene sessions are what get **persisted**.

> 🔬 **Forensics note:** Because one process can own many scenes, "app X was in use" is no longer one-dimensional. A single Safari process can have four `UIWindowScene`s across two displays. Reconstructing activity means reconstructing **scenes**, not just **apps** — and the scene-to-app mapping is exactly what `FrontBoard/applicationState.db` stores (covered below).

### The re-architected windowing engine: live vs. inactive scenes

Apple's own framing is that iPadOS 26 ships a **rebuilt windowing engine** that "optimizes window rendering by analyzing which windows are being actively used." Decode that as an engineer:

- Each open window is a `UIWindowScene`. Keeping a scene **foreground-live** (rendering, receiving events, holding its full layer tree resident) costs memory and GPU. The old 4-app Stage Manager cap was fundamentally a budget on simultaneously-live scenes.
- The new engine distinguishes **actively-used (live) windows** from **inactive** ones. Inactive windows are demoted toward a backgrounded/suspended scene state — their last frame is preserved as a **snapshot** (see artifacts), and they are not fully composited until touched. This is the same jetsam/scene-suspension machinery from [[memory-jetsam-app-lifecycle]], now driving window *visibility* policy rather than just app backgrounding.
- The consequence: window counts are **RAM-bound**, not fixed. Reported ceilings are roughly **12 simultaneously-active windows on M-series / 2024–2025 iPads**, fewer on older hardware. On non-M iPads you can *open* many windows but only ~4 stay live at once; the rest render from their snapshot until activated. *Verify the exact ceiling per device at author time — it is tuning, not contract.*

> 🖥️ **macOS contrast:** On the Mac, every window's backing store stays resident and `WindowServer` composites them all; memory pressure is handled by compression/swap, not by suspending windows. iPadOS instead **suspends inactive scenes** and composites a cached snapshot — the same philosophy as background-app suspension. An iPad "window" is closer to a suspendable app scene than to a Mac window with a permanent backing store.

### The menu bar and traffic lights — the visible convergence

Two macOS borrowings define the look:

- **Traffic-light controls** sit at a window's top-left: **close (red), minimize (yellow), full-screen (green)** — the same glyph order and semantics as macOS. Minimize sends the window's scene to an inactive/stashed state (its snapshot survives); full-screen promotes that scene to Full-Screen mode. Pulling a window's corner resizes it via the geometry APIs below.
- A **menu bar** appears by swiping down from the top edge (or pushing a pointer to the top with a trackpad/mouse — see [[trackpad-keyboard-and-apple-pencil]]). It surfaces the app's commands, which apps populate via the **`UIMenuBuilder`/`UIKeyCommand`** main-menu system that has existed since iPadOS 15 but was rarely seen without a hardware keyboard. When a window goes full-screen, the traffic lights relocate **into** the menu bar, exactly as on macOS.

For developers this is mostly *free* — a well-behaved scene-based app with a populated main menu already works. What changed is enforcement: **resize is now always available.** Where iPadOS 18 let an app opt out of resizing/multitasking with the `UIRequiresFullScreen` Info.plist key, iPadOS 26 **deprecates that key and ignores it** — *"people can always resize your app's scenes if they have enabled multitasking"* — so your app must cope with arbitrary sizes. You constrain via the `UISceneSizeRestrictions` on a `UIWindowScene` (`sizeRestrictions.minimumSize` / `maximumSize`, UIKit) or `.frame(minWidth:minHeight:)` + `.windowResizability(.contentMinSize)` (SwiftUI), and you *request* a size with `UIWindowScene.requestGeometryUpdate(_:errorHandler:)` passing a `UIWindowSceneGeometryPreferencesIOS`. Full treatment is in [[pro-and-developer-workflows-on-ipad]] and the dev module; here the point is that the **geometry contract moved toward the Mac's**.

### Stage Manager 2.0: every iPad, no 4-app cap

Two concrete changes:

1. **It runs on every iPadOS-26 iPad.** In iPadOS 16–18, Stage Manager required an M-series (or A12X/A12Z) iPad Pro/Air. In iPadOS 26 it is available on **all iPads that can run the OS — back to the 8th-gen base iPad (A12)**. The gating moved from "do you have the silicon for Stage Manager?" to "how many windows can your RAM keep live?"
2. **The 4-windows-per-stage cap is lifted on M1+.** A stage used to evict the oldest app when you added a fifth. On M1-and-newer iPads each stage now follows the same live/inactive rules as Windowed Apps mode, so a stage can hold many windows. On non-M iPads the practical limit is the active-scene budget (≈4 live).

The forensic upshot: a **stage is a saved grouping of scenes** ("Writing": Pages + Safari + Notes; "Email": Mail + Calendar). That grouping is user intent, persisted, and recoverable.

### Slide Over and drag-to-tile: a point-release timeline (verify exact builds)

This is the volatile part — the multitasking gestures **shifted across the 26.x cycle**, so pin the version when you cite behavior. iPadOS 26.0 shipped the windowing system but *dropped* the old Split View/Slide Over gestures, which generated enough complaint that Apple restored them incrementally:

| Build | Window/multitasking change | Notes |
|---|---|---|
| **26.0** (2025-09-15) | New windowing system ships; classic Split View & Slide Over **removed**; Liquid Glass design | Year-based versioning begins |
| **26.1** | **Slide Over restored** as a single resizable floating window | Initially you entered it via the traffic-light/window menu, not a drag |
| **26.2** | **Drag-to-tile gestures restored**: drag an app icon from the Dock/Spotlight to a screen edge → half-screen tile (Split-View-style); to the far edge / a chevron → Slide Over; to the center → a floating window. The preview morphs to show the target. | Restores the muscle memory iPadOS 9–18 users had |
| **26.3** | (Apple→Android transfer tool + security/perf fixes — not windowing) | — |
| **26.4** | (Eight new emoji — Apple's `.4` pattern — not windowing) | — |
| **26.5** | Current shipping release as of this writing (≈ May 2026) | Re-verify before publishing |

> ⚠️ **ADVANCED:** Do not write "Slide Over works like X in iPadOS 26" without a point-release qualifier. The same OS major version behaved three different ways between 26.0, 26.1, and 26.2. When you read a forensic artifact that encodes multitasking layout, the *device's exact build* (in `/System/Library/CoreServices/SystemVersion.plist`, or backup `Manifest.plist`) tells you which gesture/layout semantics were even possible.

### External display: from mirroring to a real extended desktop

Pre-26, attaching a display mostly meant **mirroring** (plus a few Stage-Manager-on-external cases on M-series). iPadOS 26 treats an external display as **its own canvas** — an extended desktop where full-size, independent, resizable windows live separately from the built-in screen. The capability tiers by silicon and RAM:

- **M-series iPads:** true extended desktop — independent windows/stages on the external display, distinct from the iPad's own arrangement.
- **iPad mini and non-M iPads:** **mirror only** — they can run multiple windows on the built-in display but cannot drive an independent external canvas.
- **The 8 GB RAM floor:** multitasking *on the external screen* requires ≥ 8 GB RAM; below that you get mirroring even on otherwise-capable models. *Re-verify the exact RAM/model matrix at author time.*

Each display is effectively its own workspace with its own mode, which is why "what mode is the iPad in?" is the wrong question — it is per-display state. Continuity-driven display use (Sidecar/Universal Control with a Mac) is a different path covered in [[continuity-with-the-mac]].

### Window & multitasking state as a forensic artifact

This is the payoff. The arrangement of windows, stages, and scenes — *what the user had open and on screen* — is persisted, and survives reboot. Key stores:

**1. `FrontBoard/applicationState.db`** — the spine.
On device: `/private/var/mobile/Library/FrontBoard/applicationState.db` (SQLite). In an iTunes/Finder-style backup it lands under the `HomeDomain` as `Library/FrontBoard/applicationState.db`. Tables of interest:

| Table | Contents |
|---|---|
| `application_identifier_tab` | Maps each bundle ID ↔ a numeric `application_identifier` used as the FK everywhere else |
| `key_tab` | Maps small integer keys ↔ named state keys (the schema of the kvs blobs) |
| `kvs` | Key/value rows per app: the `value` column is a **binary plist** (often a **bplist-inside-a-bplist**) holding scene state, snapshot relationships, install/uninstall metadata |

The `kvs` blobs are where scene/window state lives — including the **snapshot relationship** that ties an app to its preserved last-frame images, and lifecycle metadata. Documented integer keys (version-sensitive — confirm against your image) include values such as **compatibility info** and an **`_UninstallDate`**, the latter a Mac Absolute Time `NSDate` proving *when* an app was removed even though the app is gone. iLEAPP and the commercial suites parse this; by hand you `plutil`-decode the blob, then decode the inner blob again.

> 🔬 **Forensics note:** `applicationState.db` is a "treasure map." It enumerates every app the system tracks (installed *and* recently uninstalled), the on-disk container GUID for each, and per-app scene/snapshot state. An app the user deleted to hide activity still has a row here with an `_UninstallDate` — and its data-container GUID may still resolve to leftovers elsewhere. Always `cp` the DB before `sqlite3`; even a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`.

**2. Per-scene snapshots (KTX).**
When a scene is backgrounded/minimized/inactivated, the system caches its last frame — the image you see in the app switcher and behind an inactive window. These live under
`/private/var/mobile/Containers/Data/Application/<App-UUID>/Library/Caches/Snapshots/<bundleID>/…`
and `/private/var/mobile/Library/Caches/Snapshots/…`, stored in the GPU-friendly **KTX** texture format. They are a direct **visual record of the last on-screen content** of each window — message threads, documents, banking balances. The relationship from app → its snapshots is recorded in the `applicationState.db` blob. Community tooling: `SnapshotImageFinder.py` / `SnapshotTriage.py` (KTX → PNG + HTML report).

> ⚖️ **Authorization:** Snapshots can expose content from apps the user never granted you (a banking app's balance, a private message). They are **Data-Protection-class** files — fully readable only **after first unlock (AFU)**; in a **before-first-unlock (BFU)** acquisition many are still encrypted. Treat the lock-state at seizure as decisive (see [[bfu-vs-afu-and-data-protection-classes]]), and scope any examination to lawful authority — recoverable on-screen content from third-party apps is exactly the kind of overcollection a warrant's scope limits.

**3. Home-screen + switcher layout.**
`IconState.plist` (SpringBoard) holds the Home Screen / Dock icon layout — page order, folder membership, which apps are docked. Combined with `applicationState.db`, it reconstructs how the device was *organized* and which apps were reachable/offloaded. Magnet's "Home Screen Items" artifact and iLEAPP both parse this.

**4. Cross-corroboration with pattern-of-life stores.**
Window/scene state tells you *what was arranged*; the **`/app/inFocus`** stream in `knowledgeC.db` and the equivalent **Biome/SEGB** app-focus segments tell you *what was actually frontmost and when* — see [[knowledgec-db-deep-dive]] and [[biome-and-segb-streams]]. Correlating an `applicationState.db` scene grouping with a `knowledgeC`/Biome focus interval places a *specific window arrangement* on a *specific timeline*.

> 🔬 **Forensics note:** Multi-window changes the inference. On a phone, foreground = one app. On an iPadOS-26 iPad, several scenes can be foreground at once across a stage or an external display. A focus record for "Messages" plus a live Safari scene in the same stage is *concurrent* activity, not sequential — your timeline must model overlapping scene intervals, not a single active-app track.

## Hands-on

There is no on-device shell, and the Simulator is the only place you can drive iPad windowing and dissect the on-disk stores it produces. The commands below are **Mac-side**. (Fidelity caveats are in the Labs.)

### Boot an iPad simulator and find its data root

```bash
# List available iPad runtimes/devices
xcrun simctl list devices available | grep -i ipad

# Create + boot an iPad Pro (M-class) simulator on the iPadOS 26 runtime
UDID=$(xcrun simctl create "iPad26" \
  "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4" \
  "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
xcrun simctl boot "$UDID"
open -a Simulator

# The simulator's on-disk root (everything below is UNENCRYPTED on your Mac):
ROOT=~/Library/Developer/CoreSimulator/Devices/$UDID/data
ls "$ROOT"
```

### Locate the FrontBoard state DB inside the simulator

The Simulator collapses the device's `/private/var/mobile` into its `data/` root, so do not assume the device path — **find it**:

```bash
find "$ROOT" -iname 'applicationState.db' 2>/dev/null
# e.g. .../data/Library/FrontBoard/applicationState.db   (path may vary by runtime)

DB=$(find "$ROOT" -iname 'applicationState.db' 2>/dev/null | head -1)
cp "$DB" /tmp/appstate_copy.db          # COPY before querying
sqlite3 /tmp/appstate_copy.db '.tables'
sqlite3 /tmp/appstate_copy.db \
  "SELECT * FROM application_identifier_tab LIMIT 20;"
```

### Decode a kvs scene-state blob (bplist-in-bplist)

```bash
# Dump one app's kvs rows; the value column is a binary plist
sqlite3 /tmp/appstate_copy.db \
  "SELECT a.application_identifier, k.key, length(v.value)
   FROM kvs v
   JOIN application_identifier_tab a ON a.id = v.application_identifier
   JOIN key_tab k ON k.id = v.key
   LIMIT 20;"

# Extract one blob to a file and convert it to readable XML
sqlite3 /tmp/appstate_copy.db \
  "SELECT writefile('/tmp/blob.bplist', value) FROM kvs LIMIT 1;"
plutil -convert xml1 -o - /tmp/blob.bplist | head -60
# If the result contains another <data> bplist, write THAT out and re-run plutil.
```

### Find per-scene snapshots

```bash
find "$ROOT" -path '*Caches/Snapshots*' -type f 2>/dev/null | head
# On a real device these are .ktx; the Simulator may store PNG/other — note the difference.
```

### Drive multi-window from the command line

```bash
# Install + launch an app, then a second scene of a multi-window-capable app
xcrun simctl install "$UDID" /path/to/YourApp.app
xcrun simctl launch "$UDID" com.example.YourApp
# Re-launch to spawn additional UIWindowScenes (multi-window apps vend new scenes)
xcrun simctl launch "$UDID" com.example.YourApp
# Then arrange them in the Simulator UI and re-copy applicationState.db to see state grow.
```

## 🧪 Labs

> Substrate legend per lab: **[Simulator]** = unencrypted CoreSimulator container on your Mac — teaches *structure/layout*, **not** encryption/lock-state. The Simulator runs macOS frameworks: **no SEP, no Data Protection, no KTX-on-device snapshot pipeline, and `SpringBoard`/`FrontBoard` scene management differs from a real device.** **[Sample image]** = a public iOS reference image for the device-only stores. **[Walkthrough]** = narrated device-bound steps you cannot run without hardware.

### Lab 1 — Map the four modes to scene state [Simulator]

1. Boot an iPad Simulator on the iPadOS 26 runtime (Hands-on). Open three stock apps.
2. Put one in Full-Screen, two side-by-side (Windowed/Split), and send one to Slide Over (26.1+ behavior). Minimize one with the yellow traffic light.
3. `cp` `applicationState.db` and dump `application_identifier_tab` + the `kvs` row counts per app **before and after** rearranging. Which app's blob changed when you minimized it?
4. Write one sentence per mode mapping the *visible* arrangement to the *scene lifecycle* state you'd expect (live / inactive / suspended).
   *Caveat:* the Simulator's mode set and gesture support lag a real device; treat this as a structure exercise, not a behavior reference.

### Lab 2 — Recover scene/uninstall metadata from a real device store [Sample image]

1. Obtain a public iOS reference image (Josh Hickman / Digital Corpora). Mount it read-only.
2. Copy `HomeDomain` `Library/FrontBoard/applicationState.db` to a scratch dir; `cp` again before querying.
3. Join `kvs` → `application_identifier_tab` → `key_tab`. Extract a `value` blob with `writefile`, `plutil -convert xml1`, and **re-decode the inner bplist**.
4. Find an app row carrying an **`_UninstallDate`**. Convert the Mac Absolute Time (`+ 978307200`, `unixepoch`) to a wall-clock time. You have now proven *when an app was deleted* from a device you never touched.
   *Fidelity:* this is real device data — the genuine bplist-in-bplist nesting, KTX snapshot relationships, and Data-Protection context the Simulator cannot reproduce.

### Lab 3 — Snapshot triage and the AFU/BFU gate [Walkthrough]

> ⚠️ **ADVANCED / device-bound.** You cannot run this without a full-file-system extraction ([[full-file-system-acquisition]]) of a real device; narrate the workflow.

1. From an FFS extraction, enumerate `Library/Caches/Snapshots/` under each app's data container and the system Snapshots path.
2. Run `SnapshotTriage.py` (or equivalent) to convert **KTX** → PNG and build an HTML contact sheet per app.
3. For each recovered snapshot, record the source bundle ID, the file mtime, and the Data-Protection class.
4. State explicitly, for a hypothetical seizure: if the device was acquired **BFU**, which snapshots would still be encrypted and *unrecoverable*? (Answer with the class → lock-state mapping from [[bfu-vs-afu-and-data-protection-classes]].) This is the difference between "we recovered the last screen of their banking app" and "we recovered nothing."

### Lab 4 — Build a concurrent-scene timeline [Sample image]

1. On the same reference image, pull the `/app/inFocus` rows from `knowledgeC.db` (copy-first, `+ 978307200` epoch) — see [[knowledgec-db-deep-dive]].
2. From `applicationState.db`, list the apps that had live scene state.
3. Find a window where two different bundle IDs have overlapping focus/scene intervals. Diagram it as **two parallel tracks**, not one.
4. Write the one-line interpretation: "At HH:MM the user had App A and App B *simultaneously* on screen (a stage / split / external-display arrangement)." This is the inference iPad multi-window forces that a phone never did.

## Pitfalls & gotchas

- **"What mode is the iPad in?" is the wrong question.** Mode is **per-display / per-workspace**, not a global device toggle. An iPad can be Windowed on its own screen and Stage Manager on an external one, with a Slide Over floating over either.
- **One process ≠ one window.** A single app process vends many `UIWindowScene`s. Counting *apps* undercounts activity; reconstruct **scenes**. Foreground is no longer one-dimensional — multiple scenes are concurrent.
- **Don't cite multitasking gestures without a point release.** 26.0 removed Slide Over; 26.1 restored it (menu-driven); 26.2 restored drag-to-tile. Same `26` major, three behaviors. Anchor claims to the device's exact build (`SystemVersion.plist` / backup `Manifest.plist`).
- **Window count is RAM-bound, not fixed.** The "≈12 windows" figure is a tuning ceiling on M-series, lower elsewhere; non-M iPads keep only ~4 scenes *live* and render the rest from snapshots. Don't quote it as a hard spec.
- **Stage Manager availability flipped.** Saying "Stage Manager needs an M-series iPad" is an iPadOS-18 fact. In 26 it runs on every supported iPad (back to A12); only *external-display extended desktop* keeps the M-series + 8 GB floor.
- **Snapshots are Data-Protection-gated.** They are not unconditionally readable. BFU acquisition leaves class-protected snapshots encrypted. Never claim "we'll just pull the app-switcher images" without establishing lock-state at seizure.
- **`applicationState.db` is SQLite — copy before you query.** A bare `sqlite3` `SELECT` write-locks the file and spawns `-wal`/`-shm`, altering evidence. `cp` first, every time.
- **The blob is doubly nested.** A `kvs` `value` decodes to a bplist that frequently *contains another bplist* in a `<data>` field. A single `plutil` pass looks like garbage; decode the inner blob too.
- **Simulator snapshots aren't KTX.** The Simulator does not run the device's GPU snapshot pipeline, so don't generalize its snapshot format/paths to a real device — use a sample image or FFS extraction for snapshot work.

## Key takeaways

- iPadOS 26 multitasking is **four coexisting modes** — Full-Screen, Windowed Apps, Stage Manager, Slide Over — selected **per display**, not one global switch.
- It is the **same scene stack** you know: per-app `UIWindowScene`s composited by `backboardd`'s render server, lifecycle-managed by `FrontBoard`, arranged by `SpringBoard`. `backboardd` is the iPad's `WindowServer`; there is no separate compositor process.
- The "new windowing engine" is **live-vs-inactive scene management**: inactive windows are suspended and rendered from a cached snapshot, so window counts are **RAM-bound** (≈12 active on M-series).
- The visible convergence with macOS — **traffic lights, a menu bar, free resize** — is mostly free for scene-based apps, but **resize is now always available** (the `UIRequiresFullScreen` opt-out is deprecated and ignored; constrain with `sizeRestrictions`/`.frame(minWidth:)`).
- **Stage Manager now runs on every iPadOS-26 iPad** (the 4-app cap is lifted on M1+); **extended-desktop external display** is the M-series + 8 GB RAM tier, everyone else mirrors.
- The Slide Over / drag-to-tile gestures **shifted across 26.0 → 26.1 → 26.2** — always qualify behavior with the exact build.
- Forensically, **window/multitasking state is persisted and recoverable**: `FrontBoard/applicationState.db` (scene state, snapshot links, `_UninstallDate`), KTX per-scene **snapshots** (last on-screen frame, AFU-gated), and `IconState.plist` (layout). It shows **what the user had open and arranged** — and multi-window means modeling **concurrent** scene intervals, not a single active app.

## Terms introduced

| Term | Definition |
|---|---|
| Windowed Apps mode | iPadOS 26 free-floating, overlapping, freely-resizable windows with macOS-style traffic-light controls and a menu bar |
| Stage Manager (iPadOS 26) | Grouped "stages" of windows; in 26 available on all supported iPads with the per-stage 4-app cap lifted on M1+ |
| Slide Over | A single floating, resizable overlay window hovering above the active workspace; removed in 26.0, restored in 26.1 |
| Traffic lights | The red/yellow/green close/minimize/full-screen window controls borrowed from macOS |
| `SpringBoard` | The iOS/iPadOS system-UI process — Home Screen, Dock, app switcher, status bar — that arranges scenes into windows/stages |
| `FrontBoard` / `frontboardd` | Framework/daemon managing application and **scene** lifecycle (foreground/background, scene state) |
| `BackBoard` / `backboardd` | Daemon hosting the Core Animation **render server** (compositor) and the hardware event pipeline — the iPad's `WindowServer` analogue |
| `UIScene` / `UIWindowScene` | UIKit object representing one app window/UI instance; one process can vend many |
| `UISceneSession` | The persistable identity/state of a `UIScene`; what gets saved and restored |
| `applicationState.db` | SQLite store at `FrontBoard/applicationState.db` recording per-app scene state, snapshot relationships, and install/uninstall metadata in nested binary-plist blobs |
| `_UninstallDate` | A keyed value in an `applicationState.db` blob recording when an app was removed (Mac Absolute Time) |
| KTX snapshot | GPU-texture-format image of a scene's last on-screen frame, cached under `Library/Caches/Snapshots/`; powers the app switcher and inactive windows |
| `IconState.plist` | SpringBoard property list recording the Home Screen / Dock icon layout |
| `requestGeometryUpdate(_:errorHandler:)` | `UIWindowScene` API by which an app requests a new window size/geometry on iPadOS |
| Extended desktop | External-display mode where independent full-size windows live separately from the iPad's built-in screen (M-series + ≥8 GB RAM) |

## Further reading

- Apple — *What's new in iPadOS 26* (support.apple.com/guide/ipad) and the iOS & iPadOS 26 Release Notes (developer.apple.com/documentation/ios-ipados-release-notes)
- Apple Developer — `UIWindowScene`, `UISceneSession`, `requestGeometryUpdate(_:errorHandler:)`, `UIWindowSceneGeometryPreferencesIOS`; WWDC19 "Introducing Multiple Windows on iPad" (212) and "Architecting Your App for Multiple Windows" (258); WWDC25 sessions on the iPadOS 26 windowing model
- Jonathan Levin, *MacOS and iOS Internals* (newosxbook.com) — `SpringBoard`/`FrontBoard`/`BackBoard`, the render server, and the scene/`FBSScene` architecture
- Alexis Brignoni — *Identifying installed and uninstalled apps in iOS* (abrignoni.blogspot.com) and **iLEAPP** (`applicationState.db` parser)
- d204n6 (Ian Whiffin) — *Tracking Traces of Deleted Applications* (`applicationState.db`, `_UninstallDate`)
- Magnet Forensics — *Recover iOS App Screen Layouts with the iOS Home Screen Items Artifact*; *Tracking Bundle IDs for Containers, Shared Containers, and Plugins*
- gforce4n6 — *A "Quick Look" into iOS Snapshots* (KTX snapshots, `Library/Caches/Snapshots`, triage tooling)
- RealityNet — *iOS-Forensics-References* (github.com/RealityNet/iOS-Forensics-References)
- `man sqlite3`, `man plutil`, `xcrun simctl help` — exact flag semantics on your toolchain

---
*Related lessons: [[how-ipados-diverges-from-ios]] | [[app-lifecycle-scenes-and-background-execution]] | [[app-sandbox-and-filesystem-layout]] | [[knowledgec-db-deep-dive]] | [[continuity-with-the-mac]] | [[bfu-vs-afu-and-data-protection-classes]]*
