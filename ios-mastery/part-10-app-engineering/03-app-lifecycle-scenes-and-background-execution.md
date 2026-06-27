---
title: "App lifecycle, scenes & background execution"
part: "10 — iOS App Engineering"
lesson: 03
est_time: "45 min read + 20 min labs"
prerequisites: [memory-jetsam-app-lifecycle]
tags: [ios, dev, app-lifecycle, scenes, background, bgtaskscheduler]
last_reviewed: 2026-06-26
---

# App lifecycle, scenes & background execution

> **In one sentence:** An iOS app does not own its own runtime — the system grants it foreground time, a few seconds of grace on the way out, and a strictly metered set of background opportunities, all enforced by a watchdog that kills slow transitions and a jetsam that kills memory hogs, and every one of those grants and kills leaves an on-disk trace an examiner can read.

## Why this matters

[[06-memory-jetsam-app-lifecycle]] gave you the *system's* view: the `assertiond`/`runningboardd` assertion economy, the jetsam priority bands, and why iOS kills processes that macOS would merely swap. This lesson is the *developer's* view of the same machine — the exact delegate callbacks you implement, the state machine you live inside, the background-execution APIs and their budgets, and what happens at the boundaries where your code is too slow (watchdog) or too fat (jetsam).

For a builder this is the difference between an app that survives a return-from-background and one that flickers, hangs on launch, or silently dies. For a reverse engineer and forensic examiner it is two concrete deliverables: (1) an app's **declared background modes** are a capability manifest — they tell you what the app is *permitted* to do unattended (record audio? track location? wake on silent push?) before you ever run it; and (2) the lifecycle leaves **dated evidence** — backgrounding snapshots, jetsam reports, and watchdog crash logs that prove which app was alive, foregrounded, or killed, and when.

## Concepts

### The two halves: process lifecycle vs. UI (scene) lifecycle

Since iOS 13 the lifecycle is split across **two delegates** with different jobs, and as of iOS 26 the split is no longer optional.

- **`UIApplicationDelegate` (AppDelegate)** — owns *process*-level events: `application(_:didFinishLaunchingWithOptions:)`, APNs registration (`didRegisterForRemoteNotificationsWithDeviceToken`), `BGTaskScheduler` handler registration, and the **scene-session** lifecycle hooks (`configurationForConnecting`, `didDiscardSceneSessions`). One AppDelegate per process.
- **`UISceneDelegate` / `UIWindowSceneDelegate` (SceneDelegate)** — owns *UI*-level events for **one window (scene)**: `scene(_:willConnectTo:options:)`, `sceneDidBecomeActive`, `sceneWillResignActive`, `sceneWillEnterForeground`, `sceneDidEnterBackground`, `sceneDidDisconnect`. **N scenes per process** on iPad (and on iPhone via Stage-Manager-style external displays).

The pre-iOS-13 UI callbacks that lived on `UIApplicationDelegate` — `applicationDidBecomeActive(_:)`, `applicationWillResignActive(_:)`, `applicationDidEnterBackground(_:)`, `applicationWillEnterForeground(_:)` — are **deprecated in iOS 26**. URL/Universal-Link delivery (`application(_:open:options:)`, `continue userActivity`) also moved to the scene delegate. *Dated, verify at author time:* per Apple **TN3187**, an app **built against the iOS 27 SDK** that does not adopt `UIScene` will **fail a launch-time assertion** (hard crash on launch); building against iOS 26 still runs but logs deprecation. This is the same "build-SDK gates behavior, not the running OS" pattern macOS uses.

SwiftUI papers over all of this with the `App`/`Scene` protocol and one observable, `@Environment(\.scenePhase)`, which collapses the scene states to three cases — `.active`, `.inactive`, `.background` — but the underlying UIKit machine is still running beneath it.

> 🖥️ **macOS contrast:** On macOS you knew one delegate — `NSApplicationDelegate` — with `applicationDidBecomeActive(_:)`/`applicationDidResignActive(_:)` and a single implicit "window scene." macOS apps are multi-window by nature and the OS never split the lifecycle into a scene delegate, because macOS never needed to reason about *which window* the system might tear down to reclaim resources. iOS did, because it routinely tears them down. The iPad multi-window model (one `UIScene` per window) is the closest UIKit ever got to the Mac's window model — and notably, **Mac Catalyst and "iPad apps on Apple Silicon Macs" run the UIScene machine on macOS.**

### The state machine

Five states, but your code runs in only three of them — **Inactive**, **Active**, **Background**. The two bookends are code-silent: in **Not running** the process doesn't exist yet (never launched, or already killed), and **Suspended** is the state in which the process is frozen in memory but scheduled no CPU — you cannot observe entering Suspended from inside, because by definition you are not running.

```
            launch                 user taps icon /
   ┌───────────────────────┐       returns to app
   │                       ▼              │
┌──────────┐   willConnect   ┌──────────┐│  sceneDidBecomeActive
│ NOT      │───────────────► │ INACTIVE │◄┘ ┌──────────┐
│ RUNNING  │                 │ (fore-   │──►│  ACTIVE  │
└──────────┘                 │  ground) │◄──│ (fore-   │
   ▲   ▲                     └──────────┘   │  ground) │
   │   │                          ▲ │       └──────────┘
   │   │      sceneWillEnter      │ │ sceneWillResignActive
   │   │       Foreground         │ ▼  (interruption / home swipe)
   │   │                     ┌────────────┐
   │   │  jetsam / user      │ BACKGROUND │  ← you get a FINITE grace window here
   │   └─────swipe-kill──────│ (running,  │     (sceneDidEnterBackground returns ⇒ clock starts)
   │       (no callback)     │  ~seconds) │
   │                         └────────────┘
   │   system freezes you           │ grace expires / nothing keeping you awake
   │   (no callback)                ▼
   │                         ┌────────────┐
   └─────────────────────────│ SUSPENDED  │ ← frozen in RAM, 0 CPU, INVISIBLE to your code
        woken for BG task /  │ (in memory)│    jetsam reclaims from here first
        push / launched anew └────────────┘
```

Two transitions are **silent** — no callback fires:

1. **Suspended → terminated by jetsam** (or by the user swiping the card away in the switcher). Your process is `SIGKILL`ed; you get **no** `applicationWillTerminate`/`sceneDidDisconnect`. (`applicationWillTerminate` fires *only* for a foreground/background termination while still running — almost never in practice.)
2. **Active/background → suspended.** The freeze itself is silent; `sceneDidEnterBackground` is the last code you run before the grace window closes.

This is the single most important mental correction coming from macOS: **you do not get a clean shutdown.** Persist state in `sceneDidEnterBackground`, not in some `willTerminate` you will never see.

> 🖥️ **macOS contrast:** macOS **App Nap** throttles a background app (timer coalescing, lowered QoS, suspended drawing) but the app keeps running and can register an `NSProcessInfo.beginActivity(options:reason:)` assertion to opt out. macOS also offers **Sudden Termination** (`NSSupportsSuddenTermination`) as an *optimization* the app opts into. iOS inverts both defaults: suspension is mandatory and immediate, sudden termination is the norm, and there is no "keep me awake because I feel like it" assertion — you get the metered budgets below or nothing.

### Launch reasons: not every launch is a tap

`not running → inactive` happens for several distinct reasons, and they look different from inside the process — a fact that matters both for correct code and for reading evidence:

| Launch reason | Trigger | What runs | UI? |
|---|---|---|---|
| **Cold (user) launch** | User taps the icon | `didFinishLaunching` → scene `willConnect` → `didBecomeActive` | Yes |
| **Background launch** | `BGTask` fires, silent/VoIP push, background `URLSession` completes, geofence/significant-location event | `didFinishLaunching` runs; *no* scene connects; you do work and re-suspend | No |
| **State-restoration launch** | System relaunches a previously killed app the user returns to | `didFinishLaunching` → `willConnect` with a `stateRestorationActivity` | Yes |
| **Prewarming** | System speculatively starts the process to cut perceived launch time | **`didFinishLaunching` may run with no scene and no user present**; the app may sit partway initialized | No |

**Prewarming** is the trap: since iOS 15 the system may execute your launch sequence *before the user ever taps the icon*, then finish the launch later when they do. Code in `didFinishLaunching` that assumes "a user just opened me" (logging an "app opened" analytics event, starting a timer, prompting for a permission) will misfire. You can detect a prewarm via the `ActivePrewarm` environment variable the system sets, and you should defer user-facing launch logic to the first real scene activation.

> 🔬 **Forensics note:** Background and prewarm launches mean **a process being alive does not imply the user opened the app**. A `JetsamEvent` listing an app, or a launch entry in the unified log, can stem from a push wake or a speculative prewarm rather than user intent. Distinguish "ran" from "was used" by corroborating with knowledgeC `/app/inFocus` (true foreground intervals) before testifying that someone *opened* an app at time T. See [[12-unified-logs-sysdiagnose-crash-network]] for the launch-reason strings RunningBoard logs.

### Multi-scene & the scene session

On iPad, each window is a `UIWindowScene` backed by a persistent `UISceneSession` (with a `persistentIdentifier`). The app declares multi-window support in `Info.plist` under `UIApplicationSceneManifest` → `UIApplicationSupportsMultipleScenes = YES`. The system can **connect**, **disconnect** (to reclaim memory — the session survives, the scene object does not), and later **reconnect** a session, restoring its UI from an `NSUserActivity` you hand back via `scene.userActivity` / `stateRestorationActivity(for:)`.

`application(_:didDiscardSceneSessions:)` is the one place you learn a *user* permanently closed a window (swiped it away in the switcher) versus the *system* merely disconnecting it to save RAM — a distinction with forensic weight (intentional close vs. reclaim).

### SwiftUI's `App` protocol and `scenePhase`

SwiftUI replaces both delegates with declarative `Scene`s and one observable. The whole UIKit machine above still runs underneath, but you observe it through `@Environment(\.scenePhase)`:

```swift
@main
struct AcmeApp: App {
    // Bridge to UIKit when you still need process-level hooks (APNs, BGTask registration):
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {            // each WindowGroup instance ⇒ one UIWindowScene on iPad
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     resumeWork()                 // foreground, receiving events
            case .inactive:   pauseTimersAndAnimations()   // transitional limbo
            case .background: persistState(); scheduleRefresh()  // LAST chance to save
            @unknown default: break
            }
        }
    }
}
```

`@UIApplicationDelegateAdaptor` is the escape hatch: APNs token callbacks, `BGTaskScheduler.register`, and `didDiscardSceneSessions` still need a real `AppDelegate` even in a pure-SwiftUI app — the declarative layer covers UI state, not process events. The `.background` case is where you do everything you would have done in `sceneDidEnterBackground`: this is your reliable save point.

### State restoration & `NSUserActivity`

Because the system disconnects scenes and kills suspended processes freely, iOS expects apps to make restoration *seamless* — the user should not be able to tell a relaunch from a resume. You opt in by returning an `NSUserActivity` from `stateRestorationActivity(for:)` (or setting `scene.userActivity`); the system serializes it and, on reconnect/relaunch, hands it back in `scene(_:willConnectTo:options:)` via `session.stateRestorationActivity`. You rebuild the UI (which document was open, scroll position, selected tab) from that activity's `userInfo` dictionary.

> 🔬 **Forensics note:** That serialized restoration state is written to disk inside the app's data container (historically under `…/Library/Saved Application State/` on the UIKit side, and the scene's activity is also what powers **Handoff** and **Spotlight** continuation). It can preserve *what the user was doing* — the open document path, a search query, an item identifier — across a kill, independent of the app's own databases. Treat `NSUserActivity`-backed restoration archives as a parallel "recently viewed" artifact, and note that the same `NSUserActivity` flowing through Continuity may also surface on a *paired Mac/iPad* (see [[04-continuity-with-the-mac]]).

> 🔬 **Forensics note:** When a scene enters the background the system captures a **switcher snapshot** — a literal screenshot of the app's UI — and writes it inside the app's own data container, historically under `…/Library/Caches/Snapshots/<bundle-id>/` and on modern iOS under `…/Library/SplashBoard/Snapshots/…`, as GPU-compressed **`.ktx`** (Khronos texture) files. These persist across launches and are a goldmine: they capture *whatever was on screen at background time* — a draft message, a banking balance, a photo, an unsent note — even for apps that store nothing else in plaintext. iLEAPP has a dedicated snapshots module. *(Verify the exact subpath per iOS version; the `SplashBoard` location and `.ktx` format are current as of the 26.x line.)*

### Background execution modes and their budgets

An app that is not foreground gets CPU **only** if it has a reason the system recognizes. There are two distinct mechanisms, and they are constantly confused:

**A. Long-running "modes" declared in `Info.plist` → `UIBackgroundModes`.** These keep the process *running* (not suspended) as long as the declared activity is genuinely happening. They require an active, ongoing reason and Apple review scrutiny.

| `UIBackgroundModes` key | What it grants | Backing framework / API |
|---|---|---|
| `audio` | Keep running while playing/recording audio (or AirPlay) | `AVAudioSession` category `.playback`/`.record` |
| `location` | Continuous location updates in background | Core Location (`allowsBackgroundLocationUpdates`) |
| `voip` | Wake for incoming calls | **PushKit** (`PKPushTypeVoIP`) + CallKit |
| `remote-notification` | Wake briefly on a **silent push** (`content-available:1`) | `didReceiveRemoteNotification:fetchCompletionHandler:` |
| `fetch` | Legacy "background fetch" wakeups | superseded by `BGAppRefreshTask` (key still required) |
| `processing` | Run `BGProcessingTask` (long/deferrable work) | `BGTaskScheduler` |
| `bluetooth-central` / `bluetooth-peripheral` | Stay connected to BLE accessories | Core Bluetooth |
| `external-accessory` | MFi/EAAccessory comms | ExternalAccessory |
| `nearby-interaction` | UWB ranging in background | NearbyInteraction (U1/U2) |
| `push-to-talk` | PTT channel audio | PushToTalk framework |

**B. Scheduled, metered tasks via `BGTaskScheduler` (the Background Tasks framework).** These do **not** keep you running; they *wake a suspended app* at a system-chosen time, hand you a bounded slice, and re-suspend you.

| Task class | Use case | Constraints you can set | When/how long the system runs it |
|---|---|---|---|
| `BGAppRefreshTask` | Freshen content before the user opens the app (timeline, feed) | `earliestBeginDate` only | Short (seconds — historically ~30s); cadence **learned** from your launch pattern; discretionary |
| `BGProcessingTask` | Heavy deferrable work: DB compaction, ML, sync, backups | `requiresNetworkConnectivity`, `requiresExternalPower`, `earliestBeginDate` | Longer (minutes), but typically only **while charging + idle, often overnight** |
| `BGContinuedProcessingTask` *(iOS 26+)* | A **user-initiated** job (export, upload, conversion) that must finish after the user backgrounds the app | Submitted with a user-visible **title/subtitle**; `strategy` `.queue` (default) or `.fail` | Runs immediately with a **system-presented progress UI**; you drive its `progress` (a `Progress` — reporting is mandatory and feeds that UI); can request **GPU**/compute via the request's `requiredResources`, gated by what `BGTaskScheduler.supportedResources` reports at runtime (GPU is device-dependent — observed on iPad, not iPhone, on the 26.x line) |

Registration is two-part and both halves are mandatory or the task silently never runs:

```swift
// 1) Info.plist:  BGTaskSchedulerPermittedIdentifiers = [ "com.acme.app.refresh",
//                                                          "com.acme.app.cleanup" ]
//    + UIBackgroundModes contains "fetch" and/or "processing"

// 2) In application(_:didFinishLaunchingWithOptions:) — at launch, ALWAYS:
BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.acme.app.refresh",
                                using: nil) { task in
    self.handleRefresh(task as! BGAppRefreshTask)
}

// 3) Schedule (e.g. from sceneDidEnterBackground):
let req = BGAppRefreshTaskRequest(identifier: "com.acme.app.refresh")
req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)   // "no sooner than"
try? BGTaskScheduler.shared.submit(req)

// 4) In the handler: do the work, set an expiration handler, then ALWAYS:
func handleRefresh(_ task: BGAppRefreshTask) {
    scheduleNextRefresh()                      // re-arm — the system won't re-arm for you
    task.expirationHandler = { /* cancel work NOW */ }
    Task {
        await doShortFetch()
        task.setTaskCompleted(success: true)   // not calling this ⇒ watchdog/penalty
    }
}
```

The cardinal rules: `earliestBeginDate` is a floor, **never a guarantee** — the system decides actual timing from device state, battery, and *how often the user actually opens your app* (an app the user ignores gets starved). You must **re-submit** inside each handler. And you must call `setTaskCompleted` (or hit the `expirationHandler`) promptly — overrunning earns a watchdog kill and a scheduling penalty.

**C. Background `URLSession`** is a third path: a transfer configured with `URLSessionConfiguration.background(withIdentifier:)` is handed to the system `nsurlsessiond` daemon, which performs it **out of process**. The download/upload continues — and can even complete — while your app is suspended or terminated; the system **relaunches** your app in the background and calls `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to let you wrap up. This is how large downloads survive an app the user swiped away.

**D. Push-driven wakes** are the server's lever on a suspended app. A **silent push** (APNs payload with `content-available: 1`, requiring the `remote-notification` background mode) wakes the app for a few seconds via `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` — but the system **rate-limits** silent pushes per app and coalesces or drops them for apps the user rarely opens, so they are best-effort, not a reliable cron. **PushKit** (`voip` mode) is the high-privilege exception: a VoIP push wakes the app *reliably and immediately* to report an incoming call — but iOS 13+ **requires** you to report a CallKit call on every VoIP push or the app is penalized, and a VoIP app that resumes too frequently is killed with the `0xbad22222` code. Silent push is the legitimate channel a server uses to say "there's new data, go fetch it"; abuse of it (or of VoIP push for non-call wakeups) is a classic spyware tell worth flagging.

> 🖥️ **macOS contrast:** macOS has the same `BGTaskScheduler` (since macOS 13) and background `URLSession`, but they matter far less — a macOS app simply *keeps running* in the background by default, so it rarely needs to ask permission to do work later. On iOS these APIs are the *only* sanctioned way to run unattended, which is exactly why their `Info.plist` declarations are such clean forensic signal.

### Jetsam from the developer's side

Jetsam (`memorystatus` in XNU) is the OS killing processes under memory pressure, lowest-priority first. From inside your app, three things matter:

- **There is a hard per-process memory limit**, and it is **device-specific** (scales with physical RAM) and **state-specific** (foreground apps get the most; extensions get drastically less — a widget or notification-service extension may be capped in the tens of MB). Apple does not publish the exact ceilings; you query the live headroom at runtime with **`os_proc_available_memory()`** (returns bytes remaining before *your* limit). Cross the limit and you are `SIGKILL`ed with **no callback** — `applicationDidReceiveMemoryWarning`/`didReceiveMemoryWarning` is a *courtesy* warning that fires *earlier* under pressure, not at the kill.
- **"Memory" means dirty + compressed footprint**, not virtual size. `footprint = dirty pages + compressed pages`. Clean, file-backed pages (your `__TEXT`, mapped read-only resources) don't count against you because the kernel can evict and re-fault them. This is why memory-mapping a large asset read-only is "free" and `malloc`'ing the same bytes is not.
- **You can raise the ceiling with entitlements** — `com.apple.developer.kernel.increased-memory-limit` (modest bump for media apps) and `com.apple.developer.kernel.extended-virtual-addressing` (for >4 GB address space on supported devices). Their presence in a signed app is itself a tell about how memory-hungry the app is designed to be.

> 🖥️ **macOS contrast:** macOS *has* `memorystatus`/jetsam in the same XNU kernel, but on a Mac with swap it almost never fires for normal apps — it kills only in genuine swap-exhaustion. iOS has **no traditional swap** (it has compressed memory and, on newer hardware, swap-to-NAND that is far more conservative), so jetsam is the *primary* memory-reclaim mechanism and fires constantly. A macOS app that leaks slowly just gets slow; the same app on iOS gets killed.

### RunningBoard assertions and the jetsam priority bands

[[06-memory-jetsam-app-lifecycle]] covered `runningboardd` (the daemon, since iOS 13, that brokers process *state* and resource assertions). The developer-facing consequence: your jetsam **priority band** is not something you set directly — it is *derived* from the assertions held on your behalf. Foregrounding raises it; the grace window after backgrounding is a short-lived assertion; a `BGTaskScheduler` wake grants a temporary assertion for the duration of the task; `beginBackgroundTask(withName:expirationHandler:)` is the one *explicit* assertion you can take, buying a finite slice (historically ~30 s, now system-variable) to finish in-flight work after backgrounding. When pressure hits, jetsam walks bands low-to-high:

| Band (low → high survival) | Typical occupant |
|---|---|
| Idle / suspended background apps | Apps the user hasn't touched recently — **killed first** |
| Apps with an active `beginBackgroundTask` assertion | Finishing short work after backgrounding |
| Apps running a `BGProcessingTask`/background `URLSession` | Granted work in progress |
| Apps with a long-running mode (`audio`/`location`/`voip`) | Actively using a declared capability |
| The **foreground** app | **Killed last** (but still killable under extreme pressure) |
| Critical system daemons | Effectively never jettisoned |

The takeaway for a builder: you raise your own survival odds only by *legitimately holding an assertion* (be foreground, be playing audio, be running a granted task) — there is no "please don't kill me" flag. The takeaway for an examiner: a `JetsamEvent` report records each process's band, so the report shows not just *who* was alive but *what priority the system assigned them* — i.e., whether an app was merely suspended or was actively holding a background assertion at kill time.

### Background `URLSession`: surviving your own death

A background-configured session is the only way a transfer outlives the app entirely:

```swift
let cfg = URLSessionConfiguration.background(withIdentifier: "com.acme.app.bgdl")
cfg.isDiscretionary = true              // let the system pick an opportune time
cfg.sessionSendsLaunchEvents = true     // relaunch the app to deliver completion
let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
session.downloadTask(with: bigFileURL).resume()
```

Hand-off to `nsurlsessiond` means the bytes keep flowing through suspension and even termination. On completion the system **relaunches the app in the background** and calls `application(_:handleEventsForBackgroundURLSession:completionHandler:)`; you stash the `completionHandler`, let your `URLSessionDelegate` callbacks fire, then call the handler so the system knows you're done and can re-suspend you. Forgetting to call it leaves the app stuck awake → scheduling penalty.

### The watchdog

A separate enforcer from jetsam: the **watchdog** kills an app that is *too slow at a lifecycle transition* on the **main thread**. Block the main thread during launch, resume, or suspend past the (undisclosed, version-dependent) allowance and the process is `SIGKILL`ed with the signature exception code **`0x8badf00d`** ("ate bad food"). This is distinct from jetsam (out-of-memory) and from these sibling codes you will meet in crash logs:

| Exception / termination code | Meaning |
|---|---|
| `0x8badf00d` | **Watchdog** timeout — main-thread hang during launch/resume/suspend (FrontBoard/SpringBoard namespace) |
| `0xdead10cc` | "Dead lock" — app was **suspended while holding a system resource** (a file lock or SQLite/Core Data lock, often a shared-container DB) |
| `0xc00010ff` | "Cool off" — terminated due to a **thermal** event |
| `0xbaaaaaad` | Not a crash — the **stackshot** marker from a manually triggered sysdiagnose |
| `0xbad22222` | VoIP app killed for **resuming too frequently** |

> 🖥️ **macOS contrast:** macOS has no comparable launch/transition watchdog for ordinary apps — a Mac app that hangs on launch just shows a beachball indefinitely; the user force-quits. iOS *cannot* afford a hung app squatting on the single foreground slot, so it imposes a hard wall-clock budget on every lifecycle transition and kills you for missing it. This is why "do nothing slow on the main thread in `didFinishLaunching`" is a survival rule on iOS, not just a perf nicety.

### Forensic & RE relevance: capability + evidence

Two payoffs, both already foreshadowed:

**1. Declared modes = a capability manifest.** Before running anything, dump an app's `Info.plist` and read `UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers`, and the increased-memory entitlements. An app declaring `audio` + `voip` + `location` *can* record and track unattended — directly relevant when triaging a suspected stalkerware/spyware app, or just scoping what an app could have done while the user wasn't looking. (mvt and the OWASP MASTG checklists both inspect exactly these keys.)

**2. Lifecycle events = dated evidence.** The kills above are not silent on disk — they are written as **`.ips`** reports under the on-device CrashReporter store and surfaced in *Settings → Privacy & Security → Analytics & Improvements → Analytics Data*:

- **`JetsamEvent-YYYY-MM-DD-HHMMSS.ips`** — a JSON report (bug_type `298`) generated **every time jetsam runs**, listing **every live process**, each with its `rpages` (resident pages), `reason`/`killDelta`, jetsam priority band, and the header's `pageSize` (16384 on modern A-series). Multiply `rpages × pageSize` for bytes. This is a **system-wide snapshot of what was alive and how fat at the moment of a memory-pressure event** — it proves an app was running at time T even if the app itself logged nothing.
- **`<App>-YYYY-MM-DD-HHMMSS.ips`** crash reports with `Termination Reason: Namespace … Code 0x8badf00d` (or the human string `…scene-update watchdog transgression: … exhausted real (wall clock) time allowance of NN.NN seconds`) prove the app was launched/resumed at that timestamp and hung.

> 🔬 **Forensics note:** Jetsam and watchdog `.ips` files are first-class timeline anchors and they **survive the app's own data being cleared** — they live in the system CrashReporter store, not the app sandbox. Pulled together with [[01-knowledgec-db-deep-dive]]'s `/app/inFocus` foreground intervals and [[03-powerlog-and-aggregate-dictionary]]'s per-app energy buckets, a jetsam report's process list lets you corroborate "app X was resident at 14:07" from three independent stores — exactly the cross-corroboration that defeats "that app wasn't even running" claims. Every timestamp here is in its own format; reconcile with [[00-the-ios-timestamp-zoo]] before merging timelines.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. The Simulator gives faithful *lifecycle/scene* behavior and on-disk `Info.plist` parsing; it does **not** faithfully reproduce jetsam, real `BGTaskScheduler` timing, watchdog kills, or `.ktx` snapshots (those need a sample image / device walkthrough).

### Read an app's declared background capabilities

```bash
# A built .app (Simulator build, or an unzipped .ipa's Payload/<App>.app)
APP="$HOME/Library/Developer/Xcode/DerivedData/MyApp-xxxx/Build/Products/Debug-iphonesimulator/MyApp.app"

# Background modes + BG task identifiers, straight from the bundle
plutil -extract UIBackgroundModes xml1 -o - "$APP/Info.plist"
plutil -extract BGTaskSchedulerPermittedIdentifiers xml1 -o - "$APP/Info.plist"

# Entitlements baked into the signature (memory-limit bumps live here)
codesign -d --entitlements :- "$APP" 2>/dev/null | \
  grep -iE 'increased-memory|extended-virtual|background'
```

Expected: an XML array of strings (`audio`, `remote-notification`, `processing`, …) and, for a media app, a `com.apple.developer.kernel.increased-memory-limit` boolean.

### Drive the lifecycle on the Simulator and watch the callbacks

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted "$APP"
xcrun simctl launch --console-pty booted com.acme.app    # streams os_log to your terminal

# In another pane, force background/foreground transitions:
xcrun simctl ui booted appearance dark          # benign UI poke
# Background the app by launching another, then re-foreground:
xcrun simctl launch booted com.apple.mobilesafari
xcrun simctl launch booted com.acme.app         # sceneWillEnterForeground fires
xcrun simctl terminate booted com.acme.app      # clean terminate (rare on real devices!)
```

Add `os_log` (or `print`) in each scene/app callback and you will see the exact ordering: `willConnect → didBecomeActive`, then on backgrounding `willResignActive → didEnterBackground`.

### Simulate a BGTask firing without waiting hours (debugger only)

`BGTaskScheduler` will not run your task on demand in normal operation. Attach LLDB and call the private debug entry points (these exist precisely for this and are how Apple documents testing):

```lldb
(lldb) e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.acme.app.refresh"]
# ...let your handler run...
(lldb) e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.acme.app.refresh"]
```

The first jumps straight into your `launchHandler`; the second invokes your `expirationHandler` so you can verify you cancel cleanly. (Both work on Simulator and device; the *real-world scheduling* does not.)

### Parse a JetsamEvent report (sample image / pulled from device)

> ⚖️ **Authorization:** `idevicecrashreport` copies the device's CrashReporter store over USB via the `com.apple.crashreportcopymobile` lockdown service — it requires the device to be **unlocked and paired** (a valid pairing record / trust), which on a modern device means you have lawful access to an unlocked phone or a usable backup. Pulling these reports is an *acquisition* step: do it only under proper authority, against a forensic copy where possible, and log it in your chain of custody. The reports are also surfaced (read-only) in *Settings → Privacy & Security → Analytics & Improvements → Analytics Data*.

```bash
# From a device you are authorized to examine, crash/jetsam .ips pull over USB:
idevicecrashreport -e -k ./crashes/      # libimobiledevice: copies CrashReporter store

# Inspect a jetsam report — it's JSON; jq slices the process list by footprint:
jq '.pageSize as $ps
    | .processes
    | sort_by(.rpages) | reverse
    | .[:10]
    | map({name, pages: .rpages, MB: ((.rpages * $ps)/1048576 | floor), reason})' \
   JetsamEvent-2026-06-20-140711.ips
```

Expected: the top memory consumers at the moment of the pressure event, with the killed process's `reason` (e.g. `per-process-limit` or `vm-pageshortage`). If the format is the older non-JSON variant on a given image, fall back to iLEAPP's jetsam module.

### Triage watchdog vs. jetsam vs. deadlock in a crash report

```bash
grep -iE 'Termination Reason|Exception Type|Exception Codes|watchdog|wall clock' \
     MyApp-2026-06-20-141033.ips
# Termination Reason: Namespace SPRINGBOARD, Code 0x8badf00d
# ...scene-update watchdog transgression... exhausted real (wall clock) time allowance of 9.98 seconds
```

## 🧪 Labs

> ⚠️ Labs are **device-free**. The Simulator faithfully teaches the lifecycle/scene callback ordering, multi-scene behavior, and on-disk `Info.plist` parsing, but the Simulator runs macOS frameworks: **no real jetsam kills, no genuine `BGTaskScheduler` scheduling, no watchdog, no `.ktx` switcher snapshots.** Labs 1–3 use the Simulator; Lab 4 uses a public sample forensic image (Josh Hickman / iLEAPP test data) for the device-only artifacts.

### Lab 1 — Map the state machine (Simulator)

Substrate: Xcode Simulator. Fidelity caveat: callback *ordering* is faithful; "suspended" can't be observed and "terminated by jetsam" never happens here.

1. New SwiftUI app; add a `SceneDelegate` (or use the UIKit "App Delegate" lifecycle template) and `os_log` one line in each of `scene(_:willConnectTo:)`, `sceneDidBecomeActive`, `sceneWillResignActive`, `sceneDidEnterBackground`, `sceneWillEnterForeground`, `sceneDidDisconnect`, plus `application(_:didFinishLaunchingWithOptions:)`.
2. `xcrun simctl launch --console-pty booted <id>`; background and re-foreground via the `simctl launch` trick from Hands-on. Record the exact emitted order.
3. Now also log `@Environment(\.scenePhase)` changes from SwiftUI. Confirm `.inactive` appears *between* `.active` and `.background` in both directions — the brief inactive limbo is where you should pause animations/timers, not tear down state.

### Lab 2 — Background-mode manifest extraction (Simulator build → bundle on disk)

Substrate: a built `.app` in DerivedData (or any unzipped `.ipa`). Fidelity caveat: this reads the *declared* capability — it does not prove the app *used* it.

1. Add `UIBackgroundModes` = `[audio, remote-notification, processing]` and a `BGTaskSchedulerPermittedIdentifiers` array to your app's `Info.plist`; build.
2. From the **Mac**, run the `plutil -extract` and `codesign -d --entitlements` commands from Hands-on against the built bundle.
3. Write a one-line `jq`/`plutil` extractor that, given any `.app`, prints a single "capability line": e.g. `MyApp: audio,remote-notification,processing | bg-ids: com.acme.refresh`. This is the exact triage primitive you'd run across an evidence device's `/var/containers/Bundle/Application/*/`.

### Lab 3 — BGTask round-trip in the debugger (Simulator)

Substrate: Simulator + LLDB. Fidelity caveat: you are *simulating* the launch/expiration; real cadence (learned from usage, battery, charging) does not apply.

1. Register a `BGAppRefreshTask` handler at launch and `submit` a request from `sceneDidEnterBackground`. Inside the handler, log start, do a 2-second async sleep, then `setTaskCompleted(success: true)`.
2. Run, background the app, then in the Xcode debug console fire `_simulateLaunchForTaskWithIdentifier:`. Confirm your handler runs.
3. Re-run and this time fire `_simulateExpirationForTaskWithIdentifier:` *before* the work finishes; confirm your `expirationHandler` runs and you cancel. Note that forgetting `setTaskCompleted` on a real device costs you future scheduling — the Simulator won't punish you, which is itself the lesson.

### Lab 4 — Jetsam + snapshot artifacts (public sample image, read-only)

Substrate: a public iOS reference image (thebinaryhick.blog / iLEAPP test data). Fidelity caveat: these device-only artifacts (`JetsamEvent-*.ips`, `.ktx` switcher snapshots) **cannot** be produced on the Simulator — that's exactly why the lab uses a real image.

1. Locate the CrashReporter / Analytics logs in the image; find one or more `JetsamEvent-*.ips`.
2. Run the `jq` top-10-by-footprint query from Hands-on. Identify the killed process and its `reason`. Convert `rpages × pageSize` to MB for the three fattest processes.
3. Locate switcher snapshots under an app's data container (`…/Library/SplashBoard/Snapshots/…` or `…/Library/Caches/Snapshots/…`); note the `.ktx` extension and that these are *renders of on-screen content at background time*. Describe what evidentiary value a single snapshot of a messaging app's compose screen would carry.
4. Cross-reference one jetsam report's timestamp against the image's `knowledgeC.db` `/app/inFocus` rows (from [[01-knowledgec-db-deep-dive]]) — does an app shown as foregrounded near that time also appear in the jetsam process list?

### Lab 5 — Survive your own termination with a background `URLSession` (Simulator, partial fidelity)

Substrate: Simulator. Fidelity caveat: the Simulator runs `nsurlsessiond` work but does **not** suspend/jetsam your process the way a device does, so you can verify the *delegate plumbing and relaunch hook* but not the true "completes while terminated" behavior — that needs a device walkthrough.

1. Build the background `URLSession` from the Concepts code against a large test download. Implement `urlSession(_:downloadTask:didFinishDownloadingTo:)` and stash the completion handler from `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
2. Start the download, background the app, and confirm via `os_log` that your delegate callbacks still fire and you call the stored completion handler.
3. Read back: on a real device this same code path is what lets a 2 GB download finish after the user swipes the app away — the system relaunches the app *in the background* to deliver completion. Note in writing which step you could *not* faithfully observe in the Simulator and why (no real suspension/termination).

## Pitfalls & gotchas

- **Persisting in `applicationWillTerminate` (or any "will quit" hook).** On iOS that callback almost never fires — the user swipe-kill and jetsam kill are both silent `SIGKILL`. Save in `sceneDidEnterBackground`. (Direct macOS reflex trap: `applicationWillTerminate` *is* reliable on macOS.)
- **Treating `earliestBeginDate` as a schedule.** It's a *floor*, not a timer. An app the user rarely opens may see its `BGAppRefreshTask` deferred indefinitely; `BGProcessingTask` often only runs overnight on a charger. If your feature *requires* timely background work, it probably needs a real long-running mode (`audio`/`location`/`voip`) or a server-driven push — not app refresh.
- **Forgetting to re-submit inside the handler.** `BGTaskScheduler` fires a task **once**; the system does not auto-reschedule. Not calling `submit` again inside `launchHandler` means it never runs a second time.
- **Forgetting `setTaskCompleted` / ignoring the expiration handler.** Overrunning a background slice earns a watchdog termination *and* a scheduling penalty that starves future runs. Always wire `expirationHandler` to cancel.
- **Doing slow work in `didFinishLaunching`.** Synchronous disk/network/keychain on the main thread during launch is the #1 cause of `0x8badf00d`. The watchdog wall-clock budget is small and undisclosed; defer everything you can.
- **Holding a shared-container SQLite/Core Data lock across suspension.** This is `0xdead10cc`. App-extension + host-app sharing a DB in an App Group is the classic trigger — close the connection (or use WAL + finish the transaction) before `sceneDidEnterBackground` returns.
- **Assuming the Simulator tells you about background reality.** It runs no jetsam, no real scheduler, no watchdog. A BGTask that "works in the Simulator" tells you only that your handler logic runs — not that it will ever be *scheduled* on a device.
- **Confusing the two `UIBackgroundModes` for fetch.** The key is still literally `fetch` even though the *API* moved from `performFetchWithCompletionHandler` (deprecated iOS 13) to `BGAppRefreshTask`. Omit the key and registration silently no-ops.
- **Forensic: a present `UIBackgroundMode` is capability, not proof of use.** `location` in the plist means the app *can* track in background — corroborate actual use with `routined`/significant-location artifacts and [[03-powerlog-and-aggregate-dictionary]] before asserting it *did*.
- **Forensic: jetsam `.ips` files rotate.** The on-device store is size-bounded; older reports age out. Pull them early (`idevicecrashreport`) and don't assume a quiet period means the app wasn't killed — it may simply mean the report aged out.
- **Forensic: the `.ips` format changed.** Since iOS 15 most crash `.ips` files are a **two-line** document — a one-line JSON header followed by a JSON body — so a naïve `jq .` over the whole file fails; split on the first newline (or use a parser like iLEAPP/`ips`-aware tooling). `JetsamEvent` reports predate and differ from ordinary crash reports, so don't assume one schema across both.
- **Forensic: a switcher snapshot is point-in-time, not live.** A `.ktx` snapshot reflects the screen at the *last* background transition, which may be hours or days before acquisition and may show stale content (a since-deleted draft). Date it from the file's container metadata, not from "now," and corroborate with the lifecycle `.ips`/knowledgeC timeline before asserting *when* the user saw it.

## Key takeaways

- The lifecycle is split: **`UIApplicationDelegate` owns the process, `UISceneDelegate` owns each window** — and as of iOS 26 the scene model is mandatory (an iOS-27-SDK build crashes on launch without it).
- The state machine is **not running → inactive → active → background → suspended**; your code runs only in the middle three (**inactive/active/background**) — the two bookends are code-silent — and **two transitions (→suspended, →killed) fire no callback.** Save state in `sceneDidEnterBackground`, never in a "will terminate" you won't get.
- Background work comes in three flavors with very different budgets: **long-running `UIBackgroundModes`** (keep running while genuinely active), **`BGTaskScheduler`** (woken briefly/occasionally; `BGContinuedProcessingTask` is the iOS 26 user-initiated, progress-UI addition), and **background `URLSession`** (out-of-process transfers that outlive your app).
- **Jetsam kills the fat, the watchdog kills the slow.** `os_proc_available_memory()` is your live headroom; `footprint = dirty + compressed`; `0x8badf00d` is a main-thread transition hang, distinct from `0xdead10cc` (lock held across suspension) and `0xc00010ff` (thermal).
- iOS is **far stricter than macOS**: macOS App Nap throttles, iOS suspends and jetsams; macOS beachballs, iOS watchdog-kills; macOS swaps, iOS has no traditional swap so jetsam is the primary reclaim.
- **A running process is not a used app.** Background launches (push/`BGTask`/`URLSession`) and **prewarming** start your code with no user present — so "was alive at T" must be separated from "was opened at T" by corroborating with knowledgeC `/app/inFocus`.
- For RE/forensics, **declared modes are a capability manifest** read straight from `Info.plist` (+ memory entitlements from the signature), and **`JetsamEvent-*.ips` / watchdog `.ips`** are dated, sandbox-surviving timeline anchors that cross-corroborate with knowledgeC and PowerLog.

## Terms introduced

| Term | Definition |
|---|---|
| `UISceneDelegate` | Per-window delegate owning UI lifecycle events (`sceneDidBecomeActive`, `sceneDidEnterBackground`, …); mandatory as of iOS 26's successor SDK |
| `UISceneSession` | Persistent identity for a window/scene; survives system disconnect-to-reclaim and can be reconnected with restored state |
| `scenePhase` | SwiftUI environment value collapsing scene state to `.active` / `.inactive` / `.background` |
| Suspended state | Process frozen in RAM with zero CPU; not observable from inside the app; first to be reclaimed by jetsam |
| `NSUserActivity` | Serializable record of "what the user was doing"; powers state restoration, Handoff, and Spotlight continuation |
| Prewarming (`ActivePrewarm`) | System speculatively running an app's launch sequence before the user taps it; detectable via the `ActivePrewarm` env var |
| RunningBoard / `runningboardd` | Daemon brokering process state and resource assertions; derives each process's jetsam priority band |
| `beginBackgroundTask(withName:expirationHandler:)` | The one explicit assertion an app can take to finish in-flight work for a finite slice after backgrounding |
| `UIBackgroundModes` | `Info.plist` array declaring long-running background capabilities (`audio`, `location`, `voip`, `remote-notification`, `processing`, …) |
| `BGTaskScheduler` | Framework that wakes a suspended app for metered background work |
| `BGAppRefreshTask` | Short, discretionary background wake to freshen content; cadence learned from user launch pattern |
| `BGProcessingTask` | Longer deferrable background work (DB/ML/sync), typically run while charging and idle |
| `BGContinuedProcessingTask` | iOS 26+ user-initiated job that finishes after backgrounding, with a system progress UI driven by a mandatory `Progress` (optional GPU/compute via the request's `requiredResources`) |
| Background `URLSession` | Out-of-process transfer (via `nsurlsessiond`) that continues while the app is suspended/terminated and relaunches it to finish |
| Jetsam (`memorystatus`) | XNU mechanism that `SIGKILL`s processes under memory pressure, lowest priority first |
| `os_proc_available_memory()` | Runtime call returning bytes remaining before the current process hits its memory limit |
| Memory footprint | `dirty + compressed` pages — the quantity jetsam meters; clean file-backed pages are excluded |
| Watchdog | Enforcer that `SIGKILL`s an app for a main-thread hang during a lifecycle transition (`0x8badf00d`) |
| `0x8badf00d` / `0xdead10cc` / `0xc00010ff` | Termination codes: watchdog timeout / resource-lock-held-across-suspension / thermal kill |
| `JetsamEvent-*.ips` | Per-event JSON report listing every live process with `rpages`/`pageSize`/`reason` at a memory-pressure event |
| Switcher snapshot (`.ktx`) | GPU-compressed screenshot of a scene captured at background time, stored in the app's container |

## Further reading

- Apple — *Managing your app's life cycle*, *Preparing your UI to run in the background*, *Using background tasks to update your app*, and **TN3187: Migrating to the UIKit scene-based life cycle** (developer.apple.com)
- Apple — *BGTaskScheduler* / *BGAppRefreshTask* / *BGProcessingTask* / *BGContinuedProcessingTask* reference; WWDC25 session **"Finish tasks in the background"** (session 227)
- Apple — *Identifying high-memory use with jetsam event reports* (the `rpages`/`pageSize` math, `reason` strings); *os_proc_available_memory*
- Jonathan Levin — *MacOS and iOS Internals* (XNU `memorystatus`/jetsam, RunningBoard); newosxbook.com "No pressure, Mon!" memory-pressure article
- *iOS Crash Dump Analysis* (faisalmemon.github.io) — the `.ips` exception/termination code catalog
- Alexis Brignoni — **iLEAPP** (github.com/abrignoni/iLEAPP): jetsam and snapshot parser modules; Sarah Edwards — mac4n6.com / APOLLO for knowledgeC cross-correlation
- Apple — *Choosing background strategies for your app*; *About prewarming* / `ActivePrewarm` (developer.apple.com); WWDC sessions on background execution and "Optimize for the App Store launch" prewarming guidance
- OWASP **MASTG** — testing background behavior and inspecting `UIBackgroundModes`/entitlements; **mvt** (mvt-project) for capability triage on suspect apps
- Ian Whiffin (d204n6) & Sarah Edwards (mac4n6.com) — iOS snapshot (`.ktx`) and pattern-of-life artifact research; APOLLO for knowledgeC timeline correlation
- `man codesign`, `plutil`, and libimobiledevice's `idevicecrashreport` / `idevicedebug`

---
*Related lessons: [[06-memory-jetsam-app-lifecycle]] | [[01-knowledgec-db-deep-dive]] | [[12-unified-logs-sysdiagnose-crash-network]] | [[04-the-app-bundle-and-ipa-structure]] | [[01-simulator-internals-and-on-disk-filesystem]]*
