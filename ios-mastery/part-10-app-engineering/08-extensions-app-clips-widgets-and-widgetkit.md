---
title: "Extensions, App Clips, widgets & WidgetKit"
part: "10 — iOS App Engineering"
lesson: 08
est_time: "45 min read + 20 min labs"
prerequisites: [the-app-sandbox-from-the-developer-side]
tags: [ios, dev, extensions, app-clips, widgets, widgetkit]
last_reviewed: 2026-06-26
---

# Extensions, App Clips, widgets & WidgetKit

> **In one sentence:** an iOS "app" is rarely one process — it is a *constellation* of independently-signed, independently-sandboxed `.appex` bundles (share sheets, keyboards, notification handlers, widgets, Live Activities) plus an optional ephemeral App Clip, each a **separate executable in its own Data container with its own entitlements**, so to a builder this is the IPC-and-capability map you must wire by hand, and to a reverse engineer or examiner it is a *fan-out of distinct evidence sources* you enumerate one `Info.plist` and one `codesign -d` at a time.

## Why this matters

In [[04-the-app-bundle-and-ipa-structure]] you saw that `PlugIns/` inside a `.app` holds `.appex` bundles, and in [[05-the-app-sandbox-from-the-developer-side]] you learned the single most important sentence about them: **an app extension is a separate process in a separate bundle with its own sandbox and its own entitlements — not part of the host app.** This lesson is that sentence, fully unpacked.

For *you* specifically it pays off three ways:

1. **As a builder**, the extension model is where the iOS sandbox stops being abstract: your widget cannot just call into your app's memory to get the latest data — it is a different process, so you must design an explicit channel (an App Group container, a shared keychain group, a Darwin notification, an XPC call). Almost every "my widget shows stale data" / "my Share extension can't see the login token" bug is a missing or mis-scoped shared channel.
2. **As a reverse engineer**, every `.appex` is a second (third, fourth…) binary to triage. The host app's entitlements are *not* the extension's entitlements. A benign-looking app can ship a custom keyboard with **Allow Full Access** (network + shared container) or a Notification Service Extension that decrypts and caches message bodies — and those capabilities live in the *extension's* signature, not the app's.
3. **As a forensic examiner**, this is a **multiplier on your evidence inventory**. One installed product can present a half-dozen separate Data containers plus a shared App Group container plus a widget snapshot cache plus an ephemeral App Clip container — and if you only carve the main app's `Data/Application/<UUID>` you miss most of it. The extension list *is* the list of places to look.

The unifying idea, true for builder and examiner alike: **process boundaries are evidence boundaries.** Every place the system spins up a separate process to do a job — render a widget, mutate a push, host a keyboard, run a clip — it also mints a separate container, a separate signature, and a separate shared channel. Learn to see those boundaries and you can both *wire* the product and *take it apart*.

## Concepts

### The `.appex`: a separate process, bundle, sandbox, and container

An app extension is **not a library the host loads**. It is a full bundle — its own Mach-O, its own `Info.plist`, its own `_CodeSignature/`, its own code-signed entitlement set — that the *system* launches as a distinct process when some host (the share sheet, the keyboard subsystem, `chronod`, a push arriving) decides it's needed. The host app and the extension never share an address space. The extension bundle is suffixed `.appex` and lives at `MyApp.app/PlugIns/MyExtension.appex/`.

```
MyApp.app/
├── MyApp                         ← host Mach-O
├── Info.plist
├── PlugIns/                      ← every app extension ships here
│   ├── ShareExt.appex/
│   │   ├── ShareExt              ← the extension's OWN Mach-O
│   │   ├── Info.plist            ← contains the NSExtension dict
│   │   └── _CodeSignature/       ← its OWN signature + entitlements
│   ├── MyWidget.appex/           ← WidgetKit widget (+ Live Activity)
│   ├── NotifyService.appex/      ← Notification Service Extension
│   └── Keyboard.appex/           ← Custom Keyboard
└── AppClips/                     ← App Clip(s), if any (a nested .app, not an .appex)
    └── MyClip.app/
```

On device, each running extension gets confined to **its own Data container** under `/private/var/mobile/Containers/Data/PluginKitPlugin/<UUID>/` (extensions are "PluginKit plugins" to the OS — note the *different* container subtree from the app's `Data/Application/<UUID>`), with the same UUID→identifier mapping inside `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier`) you met in [[00-app-sandbox-and-filesystem-layout]]. The extension's bundle id is the host's id plus a suffix (`com.acme.notes.ShareExt`).

> 🖥️ **macOS contrast:** You met app extensions on macOS too — Share, Action, Finder Sync, the (now-deprecated) Today widget, Safari extensions — registered the same way and listed with `pluginkit -mv`. But iOS has a **far richer and more heavily used** extension ecosystem: custom keyboards, Notification Service/Content extensions, Message Filter, Call Directory, AutoFill Credential Provider, iMessage apps, and App Clips have no everyday macOS equivalent. And the container naming diverges exactly as it did for App Groups: a macOS extension's container is the human-readable `~/Library/Containers/<ext-bundle-id>/`, while iOS hides it under an opaque `…/Data/PluginKitPlugin/<UUID>/` you must resolve through `MCMMetadataIdentifier`.

> 🔬 **Forensics note:** The first move on any installed app in a full-file-system image is `ls PlugIns/` inside its bundle, then `codesign -d --entitlements :-` (or the equivalent in iLEAPP's output) on **each** `.appex`. You are building an inventory: every extension is a separate process that may have written to its **own** `Data/PluginKitPlugin/<UUID>` container *and* to the family's `Shared/AppGroup/<UUID>` container. Skipping the `PlugIns/` walk is the single most common way examiners under-count an app's data footprint.

### The `NSExtension` dictionary and the extension *point*

What makes a bundle an extension — and *which kind* — is the `NSExtension` dictionary in its `Info.plist`. Two keys do the heavy lifting:

- **`NSExtensionPointIdentifier`** — the reverse-DNS string naming the **extension point** this plugs into. This single value decides *what the extension is*. The share sheet only ever loads `com.apple.share-services` extensions; the keyboard subsystem only loads `com.apple.keyboard-service`; `chronod` only loads `com.apple.widgetkit-extension`.
- **`NSExtensionPrincipalClass`** (code extensions) **or `NSExtensionMainStoryboard`** (UI extensions) — the entry point the system instantiates. WidgetKit/SwiftUI extensions instead declare an `NSExtensionPrincipalClass` of a `@main` widget bundle, or omit it in favour of the SwiftUI `WidgetBundle` lifecycle.

A third key, **`NSExtensionAttributes`**, carries point-specific config — most importantly **`NSExtensionActivationRule`**, the predicate that decides *when this extension appears* (e.g. "show this Share extension only when the shared item is ≥1 image": `NSExtensionActivationSupportsImageWithMaxCount`). For Action/Safari extensions, `NSExtensionJavaScriptPreprocessingFile` names a JS file run against the page.

The extension points you will actually meet (the live reference is Apple's *NSExtensionPointIdentifier* page — the archived "App Extension Keys" doc predates push, widget, and credential extensions):

| `NSExtensionPointIdentifier` | Extension type | What it can do / why it matters |
|---|---|---|
| `com.apple.share-services` | **Share** | Receives content from the share sheet (URLs, images, text). Inbound-data sink. |
| `com.apple.ui-services` | **Action** | Transforms content in place (markup, translate); can run JS on a web page. |
| `com.apple.keyboard-service` | **Custom Keyboard** | Replaces the system keyboard *system-wide*; with Full Access, sees network + shared container. |
| `com.apple.usernotifications.service` | **Notification Service** | Mutates an incoming push **before display** — decrypts/downloads rich payloads. |
| `com.apple.usernotifications.content-extension` | **Notification Content** | Custom UI for an expanded notification. |
| `com.apple.widgetkit-extension` | **WidgetKit widget** (+ Live Activity + Controls) | Renders Home/Lock-Screen widgets, Live Activities, Control Center controls. |
| `com.apple.widget-extension` | **Today widget** (legacy) | The old Notification-Center widget; deprecated since iOS 14 — its presence dates an old app. |
| `com.apple.fileprovider-nonui` | **File Provider** | Backs a cloud store inside Files.app; streams/materializes documents. |
| `com.apple.fileprovider-actionsui` | **File Provider Actions** | Custom actions on provided files. |
| `com.apple.photo-editing` | **Photo Editing** | Edits a `PHAsset` from within Photos; round-trips adjustment data. |
| `com.apple.identitylookup.message-filter` | **Message Filter** | Classifies unknown-sender SMS (junk/transaction); can query a server. |
| `com.apple.callkit.call-directory` | **Call Directory** | Supplies caller-ID labels and blocked-number lists. |
| `com.apple.authentication-services-credential-provider-ui` | **AutoFill Credential Provider** | A password manager's hook into the system AutoFill UI. |
| `com.apple.message-payload-provider` | **iMessage app** | Stickers / interactive iMessage content. |
| `com.apple.Safari.web-extension` / `…content-blocker` | **Safari Web Extension / Content Blocker** | Web-extension APIs / declarative blocking rules. |
| `com.apple.intents-service` / `…intents-ui-service` | **SiriKit Intents / UI** | The pre-App-Intents Siri/Shortcuts hook (still present in older apps). |
| `com.apple.networkextension.*` | **Network Extension providers** | `packet-tunnel`, `app-proxy`, `filter-data`, `dns-proxy` — see [[01-networkextension-and-vpn]]. |
| `com.apple.spotlight.index` | **Spotlight Index** | Indexes app content into on-device Spotlight (`CSSearchableIndex`). |

> ⚠️ The newer **App Intents Extension** (iOS 18+) runs an app's App Intents *out of process*; its extension-point identifier is **`com.apple.appintents-extension`** (App Intents is evolving fast — re-verify against the current SDK). App Intents themselves (the Swift `AppIntent` protocol surfaced to Siri/Spotlight/Shortcuts/widgets) mostly run *in-process* in the app; the dedicated extension is the opt-in for heavyweight or background intent execution. See [[00-shortcuts-and-the-automation-surface]].

> 🔬 **Forensics note:** `NSExtensionPointIdentifier` is a one-line behavioral declaration. `com.apple.usernotifications.service` says *this app processes pushes before you see them* (look for decrypted payload caches in the App Group). `com.apple.keyboard-service` says *this app can observe keystrokes system-wide* (check for Full Access and a learned-text store). `com.apple.identitylookup.message-filter` says *this app sees unknown-sender SMS* and may forward metadata to a server. `com.apple.networkextension.*` says *this app can tunnel or inspect other apps' traffic* ([[02-traffic-interception-and-tls]]). You can triage an app's *capability surface* from its extensions' point identifiers before reading a single line of disassembly.

### Discovery & lifecycle: `pkd`/PlugInKit, activation rules, XPC hosting

Extensions are not launched by the host app. The **PlugInKit** subsystem — daemon **`pkd`**, framework `PlugInKit`, CLI `pluginkit` — discovers every `.appex` at install time, records its extension point and activation rule, and hands matches to whichever host requests that point. When you tap Share, the share sheet asks PlugInKit for all `com.apple.share-services` extensions whose `NSExtensionActivationRule` matches the items you're sharing; PlugInKit launches the chosen one as a new process and brokers the connection.

That brokered connection is **XPC** under the hood ([[05-processes-mach-xpc]]). For request/response extensions (Share, Action, Photo Editing), the framework wraps it in **`NSExtensionContext`**: the host's input arrives as `context.inputItems` (an array of `NSExtensionItem`/`NSItemProvider`), and the extension returns results — or just signals completion — with `context.completeRequest(returningItems:completionHandler:)` or `context.cancelRequest(withError:)`. You rarely touch the raw XPC; you handle `inputItems` and call `completeRequest`.

```
   Host app / system UI                 PlugInKit (pkd)              The .appex (new process)
   ─────────────────────                ──────────────              ───────────────────────
   "share these 2 images"  ──query──▶   match point + rule  ──launch──▶  ShareViewController
                                                                          reads context.inputItems
   result / dismissal      ◀──XPC────   broker NSExtensionContext ◀────   context.completeRequest()
```

Two lifecycle facts that bite builders: an extension is **short-lived and memory-constrained** — the system kills it aggressively when the user dismisses the host UI or when it idles, and extensions get a *much* tighter memory budget than a foreground app (historically tens of MB; an NSE in particular is killed fast). And an extension **cannot launch its containing app** with `UIApplication.shared.open(_:)` in general — the process boundary is real ([[03-app-lifecycle-scenes-and-background-execution]]).

> 🔬 **Forensics note:** On macOS, `pluginkit -mv` enumerates every registered extension with its point identifier and the bundle that provides it — a clean inventory. There is no on-device shell on iOS, but the *same registry* exists, and PlugInKit's bookkeeping (plus the per-extension containers and the `PlugIns/` listing) is what iLEAPP/commercial tools reconstruct from a full-file-system image.

### Host ↔ extension communication: there is no shared memory

Because the host and each extension are separate sandboxed processes, every byte they share crosses a deliberate channel. Know all five:

| Channel | Mechanism | Use / forensic residue |
|---|---|---|
| **App Group container** | `containerURL(forSecurityApplicationGroupIdentifier:)` — a shared directory; loose files, a shared SQLite/Core Data/SwiftData store | The big one. Widget reads the app's latest state here; NSE caches decrypted payloads here. **Persists on disk.** |
| **Shared `UserDefaults`** | `UserDefaults(suiteName: "group.…")` — a plist *inside* the App Group container | Small key/values shared app↔extension. Persists as a plist. |
| **Shared keychain group** | `kSecAttrAccessGroup` on a `keychain-access-groups` / App-Group group | Tokens/creds shared with the extension ([[08-keychain-on-ios]]). |
| **`NSExtensionContext`** | The XPC request/response of the invocation itself | Ephemeral — the items handed to a Share/Action extension; not persisted unless the extension writes them. |
| **Darwin notifications** | `CFNotificationCenterGetDarwinNotifyCenter` — a name-only system-wide signal (no payload) | "Data changed, reload" pings between processes. Leaves no payload artifact. |

WidgetKit adds one more, one-directional: the app calls `WidgetCenter.shared.reloadTimelines(ofKind:)` (or `reloadAllTimelines()`) to tell `chronod` "re-ask my widget for a fresh timeline" — but the widget still *reads its data* from the App Group, because the reload call carries no payload.

One subtlety with sharp forensic teeth: extensions frequently run **while the device is locked**. An NSE fires on an incoming push, a widget refreshes, a Live Activity updates — all potentially with the screen locked. So when an extension writes to the App Group, the **data-protection class** of that write decides whether the *extension itself* can even read it back later (and whether you can recover it from a given lock state). An NSE that must write a decrypted payload while locked has to use a class that's available then — `…CompleteUntilFirstUserAuthentication` (Class C, AFU) or `…CompleteUnlessOpen` (Class B) — not `.complete` (Class A), which is unreadable while locked. That choice, made by the developer, is precisely the [[05-the-app-sandbox-from-the-developer-side]] reachability map: an examiner recovers the NSE's cached message bodies from an **AFU** acquisition exactly *because* the developer had to drop the class to Class C to write them while locked.

> 🖥️ **macOS contrast:** The channel menu is the same on macOS (App Groups, shared `UserDefaults` suites, keychain groups, `NSExtensionContext`, Darwin notifications), but on macOS the App Group container is the human-named `~/Library/Group Containers/<group-id>/` you can `ls` directly. On iOS it is `…/Shared/AppGroup/<UUID>/`, resolved through `MCMMetadataIdentifier`. The *engineering* transfers; the *forensic path resolution* does not — see [[05-the-app-sandbox-from-the-developer-side]].

### Custom keyboards & "Allow Full Access" — the privacy hotspot

A custom keyboard (`com.apple.keyboard-service`) replaces the system keyboard **across every app**. By default it runs in a *hardened* sandbox: **no network, no shared container, no open access** — it can only return key taps. The developer opts into more with **`RequestsOpenAccess = true`** in the extension's `NSExtensionAttributes`, which surfaces the user-facing **"Allow Full Access"** toggle. With Full Access granted, the keyboard gains network access, the App Group container, and more — which is exactly what a keyboard needs for cloud sync or swipe-typing models, and exactly what makes a malicious keyboard a system-wide keylogger.

> 🔬 **Forensics note:** When triaging a third-party keyboard, two questions: (1) does its `Info.plist` declare `RequestsOpenAccess`? and (2) is Full Access actually granted? The grant state and the keyboard's learned-text / autocorrection store are device artifacts covered in [[13-notifications-keyboard-and-misc-stores]]. A keyboard with Full Access + network is, by capability, able to exfiltrate everything typed in every app — flag it and check its App Group and its server endpoints. Note that secure-text fields (`isSecureTextEntry`, i.e. password fields) fall back to the system keyboard, so a third-party keyboard does *not* see password entry — a useful scoping fact.

### File Provider & Document Provider — the cloud-storage surface

A **File Provider** extension (`com.apple.fileprovider-nonui`, framework **FileProvider**) is how a third-party cloud store (Dropbox, OneDrive, a corporate DMS) appears as a first-class location *inside Files.app* and the system document pickers. It is the modern replacement for the old `UIDocumentPickerViewController` "Document Provider" model. The extension's job is to enumerate a remote namespace and **materialize** files on demand: the system shows placeholder items, and when the user (or any app) opens one, it calls into the provider to fetch the bytes. State is coordinated through `NSFileProviderManager` and a system-managed **domain** directory.

For an examiner this is a rich and easily-missed surface. The provider keeps a **local working set / materialized cache** of files the user has actually opened, plus a database of the remote namespace (names, sizes, modification dates, dataless placeholders) for items they *haven't* downloaded. So a File Provider container can prove a file *existed in the user's cloud account and was browsed or opened on this device* — even when the bytes were never persisted — and the materialized cache is a copy of what they actually viewed. The provider's own entitlements (`com.apple.developer.fileprovider.testing-mode`, App Groups) and its `NSExtensionFileProviderDocumentGroup` tie it to the host app's data.

> 🔬 **Forensics note:** Files.app is a *front end*; the evidence is in each provider's extension container + App Group. Enumerate the File Provider extensions (`com.apple.fileprovider-nonui`) across installed apps, then mine each provider's materialized cache and namespace DB. The list of *placeholder* (dataless) items is itself evidence: it enumerates the suspect's cloud contents as seen by this device, independent of whether anything was downloaded. Cross-reference with [[11-third-party-app-methodology]] and the iCloud Drive provider for the Apple-native case.

### App Clips — a lightweight, ephemeral `.app`-within

An **App Clip** is a tiny, instantly-launchable slice of an app — scan a code at a parking meter, pay, leave, never visiting the App Store. Mechanically it is **a separate `.app` bundle embedded in the full app at `MyApp.app/AppClips/MyClip.app`** (note: an `.app`, *not* an `.appex`), with its own bundle id that **must be prefixed by the full app's bundle id**. When invoked, the system downloads and runs *just the clip*, ephemerally.

Defining constraints — these are the design pressure and the forensic shape:

- **Size budget.** The clip's **uncompressed, thinned** main bundle must stay under a *deployment-target-dependent* cap: **10 MB** before iOS 16, **15 MB** at an iOS 16+ minimum, and — newer — **up to 100 MB** at an iOS 17+ minimum, *but only for a clip that forgoes physical invocations* (App Clip Codes, QR, NFC) and launches digitally (website/Spotlight) over a reliable connection. The small-cap tiers force a stripped-down build — minimal frameworks, few assets — which is itself an RE tell (a clip is a small, focused binary). (Confirm the current numbers in App Store Connect → *Maximum build file sizes*.)
- **Invocation.** A clip launches from an **App Clip Code** (Apple's combined visual + **NFC** code), a plain QR/NFC tag, a Safari **App Clip card**, Maps, Messages, or a location suggestion. The invocation URL arrives as an `NSUserActivity` of type `NSUserActivityTypeBrowsingWeb` (the `webpageURL`); the developer maps URL → screen. The `appclips:` value in the parent app's **`com.apple.developer.associated-domains`** entitlement, plus the server's `apple-app-site-association` (AASA) file, authorize which URLs invoke the clip.
- **Ephemeral data + reduced entitlements.** A clip runs with a **restricted capability set**: no HealthKit, limited background execution, no persistent local-notification scheduling beyond an **8-hour ephemeral notification permission** per launch, and limited access to sensitive APIs. Its data lives in its **own** container and the system **deletes the clip and its data after a period of disuse**. To survive, the clip writes into the **shared App Group container**, which the full app reads *the moment it is installed* — at which point all future invocations route to the full app, not the clip.

Which URL invokes which clip is configured in **App Store Connect** as App Clip *experiences*: a single **default experience** (the one a generic App Clip Code or AASA match resolves to) plus optional **advanced experiences** keyed to specific URLs (per-location, per-merchant). An App Clip Code itself comes in two flavours — **scan-only** (visual) and **scan-or-tap** (visual **+ embedded NFC**) — and the URL it carries is what arrives in the launch `NSUserActivity`.

> ⚖️ **Authorization:** An App Clip's data is **ephemeral by design** — the system reaps it after disuse, so the evidentiary window is short and your acquisition timing matters. Conversely, anything the clip migrated into the **shared App Group container** persists under the *full* app's data footprint, possibly created by a component (the clip) that is no longer installed. Document that provenance: data attributed to "the app" may have originated in a since-deleted App Clip, and confirm your authority covers it.

> 🔬 **Forensics note:** A clip's invocation URL is rich context — it often encodes a location, merchant, table number, or transaction id (the parking-meter zone, the restaurant table). Whether the *clip* container still exists depends on disuse timing, but the migrated state in the App Group, the AASA-authorized `appclips:` domains in the parent's entitlements, and any push/notification residue may survive. The exact on-disk container path for an installed clip is device-specific — **resolve it via `MCMMetadataIdentifier`, don't assume a fixed path.**

### WidgetKit — declarative, out-of-process, snapshot-driven

A WidgetKit widget (`com.apple.widgetkit-extension`) is **not a live mini-app**. It is a **SwiftUI-only** view that the widget daemon **`chronod`** renders *out of process*, on its own schedule, from a **timeline** your extension supplies. The contract:

- Your `TimelineProvider` (or `AppIntentTimelineProvider`) returns a **`Timeline`** of dated `TimelineEntry` values plus a **reload policy** (`.atEnd`, `.after(date)`, `.never`). `chronod` asks for the timeline, renders each entry's SwiftUI to a static snapshot, and displays the right one at the right time — your code is **not running** while the widget sits on the Home Screen.
- The widget reads its *data* from the shared **App Group** container (there's no live link to the app). The app nudges refresh with `WidgetCenter.shared.reloadTimelines(...)`.
- **Interactive widgets (iOS 17+):** a widget may contain a SwiftUI `Button`/`Toggle` whose action is an **`AppIntent`** — the only way to make a widget *do* something. The tap runs the intent (often in the app's process), which updates the App Group and reloads the timeline. There is no arbitrary code execution on tap; it is App-Intent-mediated.
- **Controls (iOS 18+):** the same extension can vend **`ControlWidget`s** — Control Center, Lock Screen, and Action-Button controls — also backed by App Intents. (Controls reached macOS Tahoe and watchOS 26 in the 26 cycle.)
- **Reach (2026):** widgets now render on iPhone, iPad, Mac, the Lock Screen, StandBy, **CarPlay**, **watchOS Smart Stack**, and **visionOS** rooms/surfaces — the *same* WidgetKit code, more hosts.

> 🖥️ **macOS contrast:** WidgetKit is the *same* framework you met on macOS (widgets in Notification Center / on the desktop since Big Sur, and **Controls** in the Control Center since macOS Tahoe), and `chronod` is the widget daemon on **both** platforms. The structural difference is reach and integration: on iOS the *identical* widget code also renders in StandBy, on the Lock Screen, on the Watch Smart Stack, on the CarPlay dashboard, and (26-era) on visionOS surfaces — and Live Activities have no macOS analogue at all. So the WidgetKit engineering transfers directly; what changes is the multiplicity of *hosts* and therefore of snapshot caches an examiner might find.

> 🔬 **Forensics note:** Because `chronod` renders and **caches widget snapshots**, the last-rendered state of a widget can survive in the system's widget/snapshot store even after the user clears the app's own data — a widget may betray the last balance, last message, or last location it displayed. The widget's data source in the **App Group** is the richer artifact, but the rendered-snapshot cache (managed by `chronod`) is a secondary one. Treat the widget extension's App Group reads as a window into "what the app's state was at last refresh." Exact snapshot-cache paths are device- and version-specific — verify against the current image rather than hardcoding.

### Live Activities & ActivityKit — push-driven, time-boxed

A **Live Activity** (iOS 16.1+) is the glanceable, *updating* surface on the Lock Screen and in the Dynamic Island — the food-delivery tracker, the sports score, the boarding-pass timer. It is built with **ActivityKit** and lives in the **same widget extension** as your widgets (an `ActivityConfiguration` alongside your `Widget`s). Its data model is two halves:

- **`ActivityAttributes`** — the *static* configuration set once at start (the flight number, the restaurant).
- **`ContentState`** (nested) — the *dynamic* state pushed repeatedly (the current gate, the delivery ETA).

Update paths:

1. **Local:** the app calls `Activity.update(...)` while running.
2. **Remote (the important one):** an **APNs push with `apns-push-type: liveactivity`** carries a new `ContentState`, addressed to the token from `activity.pushToken`. This updates the activity **even when the app isn't running** ([[07-apple-account-icloud-and-apns]]).
3. **Push-to-start (iOS 17.2+):** a push to the app's `Activity.pushToStartToken` can *start* a Live Activity with the app never having run in the foreground.

Live Activities are **time-boxed**: an activity can stay *active/updating* for up to **8 hours** unless ended sooner, then lingers on the Lock Screen for up to **4 more hours** (≈12 hours total on-screen) before the system removes it. The surface has expanded across releases, *not* all in one cycle: Live Activities flow automatically into the **Apple Watch Smart Stack** since **iOS 18 / watchOS 11** (a custom Watch layout via `supplementalActivityFamilies`), and in the **iOS 26** cycle onto the **CarPlay dashboard** (the same small `supplementalActivityFamilies` size class drives both, so a Watch-ready activity is CarPlay-ready) — iOS 26 also opened a Live Activity **scheduling API** to all apps. (Landscape Dynamic Island layouts are an iOS 27 design concern — verify against the current SDK.)

> 🔬 **Forensics note:** Live Activities are interesting because they are **push-reachable without the app running** — the `liveactivity` and push-to-start tokens, plus the most recent `ContentState`, are state an examiner may recover from the app/extension's App Group or the system's activity store, and they prove the app received server-driven updates during a window. The exact ActivityKit on-disk store is device/version-specific — **describe the mechanism and verify the path**, don't assert a fixed artifact location.

### App Intents & Spotlight indexing — the Siri/search evidence surface

Two more "extension-shaped" surfaces round out the ecosystem, and both leak state into *system* stores rather than the app's own container — which is exactly why they matter forensically.

- **App Intents** (the Swift `AppIntent` protocol) is the modern Siri/Shortcuts/Spotlight/widget action layer that largely replaces SiriKit's `intents-service` extensions. Most intents run **in-process** in the app; the optional **App Intents Extension** (iOS 18+) hosts heavyweight or background intents out of process. Crucially, an app *donates* intents and `AppShortcut`s to the system, which surfaces them in Spotlight, Siri, and the Shortcuts app — so the **set of actions an app exposes**, and *which the user invoked*, becomes recoverable from the system Shortcuts/Siri stores, not just the app. See [[00-shortcuts-and-the-automation-surface]].
- **Spotlight indexing** (`com.apple.spotlight.index`, framework Core Spotlight): an app or its index extension pushes `CSSearchableItem`s into the on-device index so its content shows up in system search. That index is a system store that can retain an app's **content metadata** (titles, snippets, identifiers) even after the in-app item is gone.

> 🔬 **Forensics note:** App Intents and Core Spotlight invert the usual "evidence lives in the app's container" assumption — they deliberately copy app content/actions into *system* stores. Donated `AppShortcut`s enumerate what an app can be told to do; the Spotlight index can hold content an app no longer shows; and Siri/Shortcuts execution leaves its own trail. When an app's own container looks scrubbed, these system-side surfaces are a second place the same facts may survive. Treat them as part of the app's evidence fan-out even though they are not in `PlugIns/`.

### Synthesis: the extension fan-out as an evidence map

Put it together and one "app" presents this topology — the thing you wire as a builder and enumerate as an examiner:

```
        ┌───────────────────────────────────────────────────────────────┐
        │  com.acme.notes  (the product)                                  │
        ├───────────────────────────────────────────────────────────────┤
        │  Host app        Data/Application/<U0>   entitlements: E0        │
        │  ShareExt        Data/PluginKitPlugin/<U1>   entitlements: E1    │
        │  Keyboard        Data/PluginKitPlugin/<U2>   entitlements: E2    │  ← Full Access?
        │  NotifyService   Data/PluginKitPlugin/<U3>   entitlements: E3    │  ← caches payloads
        │  Widget+Live Act Data/PluginKitPlugin/<U4>   entitlements: E4    │  ← snapshots via chronod
        │  App Clip        (own .app, own ephemeral container)             │  ← reaped on disuse
        └──────────────┬───────────────────────────────┬────────────────┘
                       │  the ONLY shared filesystem     │  the ONLY shared secrets
                       ▼                                 ▼
        ┌───────────────────────────────┐   ┌──────────────────────────────┐
        │ Shared/AppGroup/<UUID>          │   │ keychain group A1B2…com.acme  │
        │  shared.sqlite · cached pushes  │   │  tokens shared app↔extensions │
        │  widget data · migrated clip    │   └──────────────────────────────┘
        └───────────────────────────────┘
```

Each box is a separate process with a separate signature. The examiner's job is to acquire **every** box's container plus the shared App Group plus the shared keychain group — and the map of which boxes even exist is one `ls PlugIns/` and one `codesign -d` per `.appex` away.

Here is the triage card — extension type → where its residue lives → the question it answers:

| Extension type | On-disk residue to pull | Investigative question it answers |
|---|---|---|
| Notification Service | Decrypted/downloaded push payloads cached in the **App Group** | What message previews / pushes arrived (even before the app ran)? |
| Custom Keyboard (Full Access) | Learned-text / autocorrect store; App Group; network endpoints | Could typed input be observed/exfiltrated? (Not password fields.) |
| WidgetKit widget | Its App-Group data source; `chronod` snapshot cache | What state did the app last display (balance, location, message)? |
| Live Activity (ActivityKit) | Last `ContentState`; push / push-to-start tokens | Did the app receive server-driven updates during a window? |
| Share / Action | Usually transient (`NSExtensionContext`); anything it persisted to its own container/App Group | What content was handed *into* this app from elsewhere? |
| File Provider | Materialized cache + namespace/placeholder DB | What cloud files existed, were browsed, or were opened on this device? |
| Message Filter | Its container; any server-classification cache | What unknown-sender SMS did it see / forward metadata about? |
| Call Directory | Its blocked/identification data store | What numbers were labeled or blocked by this app? |
| AutoFill Credential Provider | Its container + shared keychain group | Which credentials could this manager surface into other apps? |
| App Clip | Own ephemeral container (may be reaped); migrated state in App Group; invocation URL | Was a clip invoked, from where, and what did it leave behind? |

## Hands-on

There is no shell on the phone. Everything below runs on the **Mac** — against a Simulator app, an `.app`/`.ipa` you possess, or a public sample image. The pattern is always the same: enumerate `PlugIns/`, classify each `.appex` by its point identifier, dump its entitlements, then follow the App Group to the shared data.

### Enumerate every extension in a bundle and dump each one's entitlements

```bash
APP=/path/to/MyApp.app          # or unzip an .ipa: Payload/<App>.app

# 1) What extensions ship?
ls -1 "$APP/PlugIns"            # ShareExt.appex  MyWidget.appex  NotifyService.appex …
ls -1 "$APP/AppClips" 2>/dev/null   # App Clip(s), if present

# 2) For EACH .appex: what kind is it, and what can it do?
for ext in "$APP"/PlugIns/*.appex; do
  echo "=== $(basename "$ext") ==="
  plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$ext/Info.plist"
  codesign -d --entitlements :- "$ext" 2>/dev/null | plutil -p -
done
```

Expected shape — the point identifier classifies the extension, the entitlements scope it:

```
=== NotifyService.appex ===
com.apple.usernotifications.service
{ "application-identifier" => "A1B2C3D4E5.com.acme.notes.NotifyService"
  "com.apple.security.application-groups" => [ "group.com.acme.shared" ] }
=== Keyboard.appex ===
com.apple.keyboard-service
{ "application-identifier" => "A1B2C3D4E5.com.acme.notes.Keyboard"
  "com.apple.security.application-groups" => [ "group.com.acme.shared" ] }
```

### Read an extension's activation rule and Full-Access flag

```bash
# When does this Share/Action extension appear? (the predicate or attribute dict)
plutil -extract NSExtension.NSExtensionAttributes xml1 -o - "$APP/PlugIns/ShareExt.appex/Info.plist" | plutil -p -

# Does a custom keyboard request Full Access?
plutil -extract NSExtension.NSExtensionAttributes.RequestsOpenAccess raw -o - \
  "$APP/PlugIns/Keyboard.appex/Info.plist"   # 1 == requests Allow Full Access
```

### Inspect an App Clip's embedding and authorized domains

```bash
CLIP="$APP/AppClips"/*.app
plutil -extract CFBundleIdentifier raw -o - "$CLIP/Info.plist"        # must be PREFIXED by parent id
# appclips:/applinks: domains live in the PARENT app's entitlements:
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - | grep -A6 associated-domains
```

### Resolve a Simulator app's extension/group containers

```bash
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)

# The app's own data container + every App Group it declares
xcrun simctl get_app_container "$DEV" com.acme.notes data
xcrun simctl get_app_container "$DEV" com.acme.notes groups

# Then ls / sqlite3 / plutil those Mac paths directly (see simulator-internals lesson).
```

(`simctl get_app_container … data` gives the *app's* container; extension containers are best located by walking the Simulator's `data/Containers/Data/PluginKitPlugin/` and matching `MCMMetadataIdentifier`.)

### Read the shared App Group store a widget/NSE actually uses

Once you have the App Group path (from `simctl get_app_container … groups` on the Mac, or by resolving a `Shared/AppGroup/<UUID>` on an image), the channel between app and extension is just files you can read:

```bash
GRP=$(xcrun simctl get_app_container "$DEV" com.acme.notes group.com.acme.shared)

# The shared UserDefaults suite the widget reads (a plist inside the group)
plutil -p "$GRP/Library/Preferences/group.com.acme.shared.plist"

# A shared SQLite the NSE/widget writes — COPY before querying (WAL side-effects)
cp "$GRP/shared.sqlite" /tmp/grp.sqlite
sqlite3 /tmp/grp.sqlite ".tables"
```

The copy-before-query discipline ([[04-the-app-bundle-and-ipa-structure]] forensic hygiene) applies to App Group databases exactly as to the app's own — a bare `SELECT` opens a write lock and spawns `-wal`/`-shm`.

## 🧪 Labs

> ⚠️ **All labs are device-free.** The **Simulator** runs macOS frameworks: there is **no AMFI, no real sandbox enforcement, no SEP, no Data-Protection-at-rest**, and device-only daemons (`chronod`'s on-device snapshot cache, `pkd`'s real activation, ActivityKit push delivery) do **not** behave as on hardware. The Simulator teaches *structure, the `NSExtension` plumbing, App-Group wiring, and entitlement layout*; push-driven Live Activity updates, the keyboard Full-Access grant, and ephemeral App-Clip reaping are taught from **sample images** and **read-only walkthroughs**.

### Lab 1 — Build a widget + App Group and watch the shared channel appear (Simulator)

**Substrate:** Xcode Simulator. **Caveat:** structure/plumbing only — `chronod`'s real out-of-process render cache and on-device refresh budgets don't apply.

1. Add a **Widget Extension** target to a trivial app. Note Xcode creates a new `.appex` with its own `Info.plist` carrying `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
2. Add the **App Groups** capability to **both** the app and the widget target with the same `group.…` id. Confirm `com.apple.security.application-groups` lands in *both* `.entitlements` files.
3. From the app, write a value to `UserDefaults(suiteName: "group.…")`; from the widget's `TimelineProvider`, read it. Run both. Confirm the widget shows the app's value — the only link is the App Group.
4. Run `codesign -d --entitlements :-` on the built `.appex` and confirm the group is sealed into its (ad-hoc) signature. **This is the exact dump you'll run on a real `.ipa`.**

### Lab 2 — Classify every extension in a real `.ipa` (read-only walkthrough)

**Substrate:** any `.ipa`/`.app` you possess (a TestFlight/Ad-Hoc build, or a macOS app for the *form* of `pluginkit`). **Caveat:** Simulator builds are ad-hoc-signed; the profile half needs a device build.

1. `unzip` the `.ipa`; `ls Payload/*.app/PlugIns/`. For **each** `.appex`, print its `NSExtensionPointIdentifier` and dump its entitlements with the `for` loop from Hands-on.
2. Write one sentence per extension: *"this is a `<type>`; it can `<capability>`."* That is your capability inventory for the *whole product*, not just the app.
3. Flag the loud ones: a `keyboard-service` with `RequestsOpenAccess`, a `usernotifications.service`, a `networkextension.*`, an `identitylookup.message-filter`.
4. On macOS, run `pluginkit -mv` and find the same kinds of extensions registered system-wide — the macOS analogue of the registry iLEAPP rebuilds from an iOS image.

### Lab 3 — Notification Service Extension cache hunt (public sample image, read-only)

**Substrate:** a public iOS reference image (Josh Hickman / Digital Corpora) parsed with iLEAPP or browsed directly. **Caveat:** device-only — this is the real `Shared/AppGroup` + `PluginKitPlugin` layout the Simulator can't produce.

1. Pick a messaging app. From its bundle's `PlugIns/`, find the `com.apple.usernotifications.service` extension and read its `application-groups` entitlement.
2. Resolve the matching `Shared/AppGroup/<UUID>` via `MCMMetadataIdentifier`. Hunt for cached/decrypted push payloads the NSE wrote there *before the main app ever ran* — message previews, downloaded media.
3. Cross-reference the recovered content with the app's own message store ([[04-communications-imessage-and-sms]]). Note evidence present in the App Group that is **absent** from the app's `Data/Application/<UUID>`.

### Lab 4 — Map the extension fan-out of one product (public sample image, read-only)

**Substrate:** public reference image. **Caveat:** device-only container subtrees.

1. Choose one installed app and enumerate **every** evidence source it owns: its `Data/Application/<UUID>`, each extension's `Data/PluginKitPlugin/<UUID>`, the shared `Shared/AppGroup/<UUID>`, and (from `keychain-access-groups`) its keychain group.
2. For each container, `plutil -p .com.apple.mobile_container_manager.metadata.plist` to label the UUID.
3. Draw the fan-out diagram (like the Synthesis box) for this real product. Count how many distinct containers one "app" touches. **This count is exactly what you'd under-report if you only carved the main app container.**

### Lab 5 — App Clip anatomy (read-only walkthrough + Simulator)

**Substrate:** an app with an App Clip target in Xcode (sample), or a possessed `.ipa` that embeds one. **Caveat:** ephemeral reaping and real invocation are device behaviors — conceptual here.

1. In the bundle, locate `AppClips/<Clip>.app`. Confirm its `CFBundleIdentifier` is **prefixed by the parent app's id**.
2. From the **parent** app's entitlements, read the `associated-domains` and find the `appclips:` host(s) — the URLs authorized to invoke the clip.
3. In the Simulator, run the App Clip target with the scheme's `_XCAppClipURL` environment variable set to a test invocation URL; observe the `NSUserActivity` (`webpageURL`) your code receives. Reason about what an invocation URL would encode in the field (merchant, location, table/transaction id) — that's the forensic context a real code/QR/NFC invocation carries.

### Lab 6 — Live Activity & Controls anatomy (Simulator + read-only walkthrough)

**Substrate:** Simulator (build) + read-only reasoning for the push path. **Caveat:** the Simulator renders a Live Activity locally but does **not** receive real APNs `liveactivity` pushes or push-to-start — remote updates and the time-box reaping are device behaviors.

1. Add an `ActivityConfiguration` to the widget extension from Lab 1 (an `ActivityAttributes` with a small `ContentState`). Start it with `Activity.request(...)` and confirm it renders on the Simulator's Lock Screen / Dynamic Island.
2. Call `Activity.update(...)` and watch the `ContentState` change — this is the *local* path. Then read off `activity.pushToken` and reason: a server holding this token can update the activity via `apns-push-type: liveactivity` **with the app suspended**.
3. Add a `ControlWidget` (`ControlWidgetButton` bound to a trivial `AppIntent`). Confirm it appears in the Simulator's Control Center gallery. Note that the *only* way the control "does" anything is by running its App Intent — there is no free-form code on tap.
4. Write the forensic one-liner: *"This product's `widgetkit-extension` carries widgets + a Live Activity + a Control; its server can drive Lock-Screen state via APNs without the app foregrounded, and the last `ContentState` is recoverable state."*

## Pitfalls & gotchas

- **"My widget/extension shows stale data."** The extension is a *different process* — it does not see the app's in-memory state or its private container. Data must travel through the **App Group** (or shared keychain), and the app must call `WidgetCenter.reloadTimelines(...)` after writing. `containerURL(forSecurityApplicationGroupIdentifier:)` returning `nil` (a missing/mismatched group entitlement on *one* of the two targets) is the #1 silent cause.
- **The extension's entitlements ≠ the host's.** Each `.appex` is signed separately with its own entitlement set and (on device) its own profile authorization. As a builder you must add the capability to **every** target that needs it; as an RE you must dump **every** `.appex`, not just the app — the dangerous capability is often *only* in the extension.
- **Extensions die fast and have a tiny memory budget.** A Notification Service Extension that downloads a large attachment can be killed mid-flight (call `serviceExtensionTimeWillExpire()` and deliver *something*). Don't architect an extension as if it were a foreground app.
- **`com.apple.widget-extension` vs `com.apple.widgetkit-extension` are different things.** The first is the **legacy Today** widget (deprecated iOS 14); the second is **WidgetKit**. Seeing the old identifier dates an app and means a `NCWidgetProviding`/storyboard widget, not SwiftUI/WidgetKit.
- **Widgets run no code at display time.** A widget is rendered from a pre-computed **timeline** by `chronod`; you cannot do live work in `body`. Interactivity is **App-Intent-only** (`Button`/`Toggle` → `AppIntent`); there is no `URLSession` call "when the widget is tapped" outside an intent.
- **App Clip size is a *thinned-uncompressed* cap, and it's brutal.** It's measured after app thinning, not the download size; pulling in a heavy framework silently blows the budget. The cap is deployment-target-dependent — **10 MB** (pre-iOS 16), **15 MB** (iOS 16+), or **up to 100 MB** (iOS 17+) *but only for a clip that drops physical invocations* (App Clip Codes/QR/NFC) and launches digitally. Confirm current numbers in App Store Connect → *Maximum build file sizes*.
- **App Clip data is ephemeral.** Anything not migrated to the shared App Group is reaped after disuse. Builders must migrate deliberately; examiners must acquire promptly and treat App-Group-resident data as the durable copy.
- **Custom keyboards don't see secure fields.** Password (`isSecureTextEntry`) fields fall back to the system keyboard — relevant both for builders (your keyboard won't be invoked there) and examiners (a third-party keyboard's typed-text store won't contain password entries).
- **Live Activities are time-boxed and push-typed.** Use `apns-push-type: liveactivity` (not `alert`), respect the ~8h active / ~12h on-screen budgets, and remember push-to-start needs the *separate* `pushToStartToken`. A Live Activity isn't a way to keep code running indefinitely.
- **`NSExtensionActivationRule` is why your Share extension doesn't appear.** A too-narrow rule (or a wrong `NSExtensionActivationSupports…` count) hides the extension from the share sheet entirely — and as an examiner, the rule tells you *what item types* an extension was built to ingest.
- **An NSE writing `.complete` (Class A) data while locked can't read it back.** Pushes arrive at any lock state; a Notification Service Extension that stamps its cache `.complete` will find the class key gone the next time it runs locked. The working choice is Class C/B — which is *also* why that cache is recoverable in an AFU acquisition. Don't assume "Complete Protection everywhere" is free for code that runs in the background.
- **Extension and host can install/uninstall independently in the bundle, but share a version.** A re-signed or tampered build can ship an `.appex` whose entitlements *exceed* what the host's profile would justify — diff each extension's signed entitlements against the embedded profile ([[01-the-code-signature-blob-and-entitlements-on-ios]]); a `com.apple.private.*` key on a "normal" extension is a tamper/sideload indicator just as it is on the app.
- **Don't forget the system-side surfaces.** App Intents donations, the Core Spotlight index, and the Shortcuts/Siri stores hold app-derived state *outside* the app's container and `PlugIns/`. An investigation scoped only to the bundle and its containers misses them — and they are precisely where data survives a tidy in-app deletion.
- **App Group identifiers must match byte-for-byte across every target.** A widget reading `nil` from `containerURL(forSecurityApplicationGroupIdentifier:)` is almost always a one-character group-id typo or a capability added to the app but not the extension. There is no error — just silent `nil` and a stale widget.

## Key takeaways

- An iOS product is a **constellation of separate processes**: the host app plus N `.appex` extensions (in `PlugIns/`) plus an optional App Clip (a nested `.app` in `AppClips/`). Each has its **own bundle, Mach-O, signature, entitlements, and Data container**.
- `NSExtensionPointIdentifier` in each extension's `Info.plist` **is its type and its capability declaration** — `usernotifications.service`, `keyboard-service`, `widgetkit-extension`, `networkextension.*`, etc. — readable before any disassembly.
- Extensions are discovered and brokered by **PlugInKit (`pkd`)** and hosted over **XPC** (wrapped as `NSExtensionContext`); they are short-lived, memory-constrained, and **share no memory** with the app.
- The **only** host↔extension channels are the **App Group container**, shared **`UserDefaults` suite**, shared **keychain group**, the invocation's **`NSExtensionContext`**, and payload-less **Darwin notifications** — every one a deliberate, often on-disk, artifact.
- **Custom keyboards** with **Full Access** (`RequestsOpenAccess`) are a system-wide privacy hotspot (network + shared container = potential keylogger), but they never see secure/password fields.
- **App Clips** are tiny (≤15 MB thinned for code/NFC/QR-invocable clips; up to 100 MB for iOS 17+ *digital-only* clips), invoked via App Clip Codes/NFC/QR/Safari, carry **reduced entitlements** and **ephemeral data**, and persist meaningfully only via the **shared App Group** the full app inherits.
- **WidgetKit** widgets are **out-of-process, snapshot-rendered by `chronod`** from a `TimelineProvider`; interactivity is **App-Intent-mediated** (iOS 17), Controls extend the same model (iOS 18). **Live Activities/ActivityKit** are **push-driven** (`apns-push-type: liveactivity`, push-to-start) and **time-boxed** (≈8 h active, ≈12 h on-screen), reaching the **Apple Watch Smart Stack** in iOS 18 and the **CarPlay dashboard** in iOS 26.
- For RE/forensics, the extension list is an **evidence multiplier**: `ls PlugIns/` + one `codesign -d` per `.appex` maps every separate container and capability — and skipping it is the standard way to under-count an app's data footprint.

## Terms introduced

| Term | Definition |
|---|---|
| `.appex` | An app extension bundle (own Mach-O, `Info.plist`, signature, entitlements); ships in the host's `PlugIns/`. |
| Extension point | The host slot an extension plugs into, named by `NSExtensionPointIdentifier`; determines the extension's type. |
| `NSExtension` (dict) | The `Info.plist` dictionary marking a bundle as an extension: `NSExtensionPointIdentifier`, `NSExtensionPrincipalClass`/`NSExtensionMainStoryboard`, `NSExtensionAttributes`. |
| `NSExtensionActivationRule` | Predicate/attributes in `NSExtensionAttributes` deciding when an extension appears (e.g. which item types). |
| `NSExtensionContext` | The object bridging an extension to its host (`inputItems`, `completeRequest`/`cancelRequest`) over XPC. |
| PlugInKit / `pkd` | The subsystem (daemon `pkd`, CLI `pluginkit`) that discovers, registers, and brokers app extensions. |
| `PluginKitPlugin` container | The `…/Data/PluginKitPlugin/<UUID>/` subtree holding each extension's own Data container. |
| Notification Service Extension | `com.apple.usernotifications.service` — mutates an incoming push before display; often decrypts/caches payloads. |
| Custom Keyboard / `RequestsOpenAccess` | `com.apple.keyboard-service`; `RequestsOpenAccess` surfaces "Allow Full Access" (network + shared container). |
| File Provider | `com.apple.fileprovider-nonui` (framework FileProvider) — backs a cloud store in Files.app; keeps a materialized cache + namespace/placeholder DB. |
| App Intents / App Intents Extension | The Swift `AppIntent` Siri/Shortcuts/Spotlight action layer (mostly in-process); the iOS 18+ extension hosts heavyweight intents out of process. |
| Core Spotlight index | `com.apple.spotlight.index` / `CSSearchableIndex` — pushes app content into the system search index (a system-side evidence store). |
| App Clip | A thinned nested `.app` in `AppClips/` (≤15 MB; up to 100 MB for an iOS 17+ digital-only clip); instantly invoked, reduced entitlements, ephemeral data. |
| App Clip Code | Apple's combined visual + NFC code that invokes an App Clip. |
| `appclips:` (associated domain) | The parent app's `associated-domains` value (+ AASA) authorizing URLs to invoke its App Clip. |
| WidgetKit / `chronod` | SwiftUI widget framework; `chronod` is the daemon that hosts widget extensions and renders/caches snapshots. |
| `com.apple.widgetkit-extension` | The extension-point identifier for WidgetKit widgets, Live Activities, and Controls. |
| `TimelineProvider` / `Timeline` / `TimelineEntry` | The contract supplying dated entries + a reload policy that `chronod` renders. |
| `ControlWidget` | iOS 18+ Control Center / Lock Screen / Action-Button control, backed by an `AppIntent`. |
| ActivityKit / Live Activity | Framework + surface for glanceable, updating Lock-Screen/Dynamic-Island content. |
| `ActivityAttributes` / `ContentState` | A Live Activity's static config and its dynamically-updated state. |
| `apns-push-type: liveactivity` / push-to-start | The APNs push type that updates a Live Activity (and the separate token that *starts* one) without the app running. |

## Further reading

- Apple — *App Extension Programming Guide*; *Information Property List → `NSExtension` / `NSExtensionPointIdentifier`* (the **live** reference; the archived "App Extension Keys" doc predates push/widget/credential points).
- Apple — *WidgetKit* (Creating a widget extension; Developing a WidgetKit strategy; interactive widgets; Controls); *ActivityKit* (Displaying live data with Live Activities; *Live Activities essentials*, WWDC26 #223); *What's new in widgets*, WWDC25 #278.
- Apple — *App Clips* (Creating an App Clip with Xcode; App Clip size limits in App Store Connect → *Maximum build file sizes*); *Configuring App Clip experiences* and associated domains.
- Apple — *Sharing data with your containing app* (App Groups); *Custom Keyboard* / *Configuring Open Access*; *Modifying content in newly delivered notifications* (UNNotificationServiceExtension).
- Jonathan Levin, *MacOS and iOS Internals* Vol. III — `pkd`/PlugInKit, `chronod`, extension hosting over XPC, the `PluginKitPlugin` container subtree; newosxbook.com, `jtool2`.
- Howard Oakley, Eclectic Light Company — "An overview of app extensions and plugins" (the `pluginkit -mv` registry view, macOS side).
- OWASP MASTG — *MASTG-KNOW-0082: App Extensions* and app-extension IPC testing; HackTricks — *iOS App Extensions*.
- Alexis Brignoni — iLEAPP (App Group / extension container parsing); Josh Hickman / Digital Corpora iOS reference images for the device-only layouts.
- Apple — *App Intents* (Adopting App Intents; *Donating shortcuts* / `AppShortcutsProvider`) and *Core Spotlight* (`CSSearchableIndex`, `CSSearchableItem`) for the system-side evidence surfaces.
- Apple — WWDC App Clips sessions (*Configure and link your App Clips*; *Create App Clip Codes*) and *Get started with App Intents* / *Bring your app to Siri*.
- Sarah Edwards (mac4n6.com) — research on iOS notification, keyboard, and App-Group artifacts; APOLLO modules for pattern-of-life correlation.
- `man pluginkit`, `man codesign`, `plutil(1)`, `xcrun simctl get_app_container`.

---
*Related lessons: [[05-the-app-sandbox-from-the-developer-side]] | [[04-the-app-bundle-and-ipa-structure]] | [[03-app-lifecycle-scenes-and-background-execution]] | [[05-processes-mach-xpc]] | [[00-app-sandbox-and-filesystem-layout]] | [[04-communications-imessage-and-sms]] | [[13-notifications-keyboard-and-misc-stores]] | [[07-apple-account-icloud-and-apns]] | [[01-networkextension-and-vpn]] | [[00-shortcuts-and-the-automation-surface]] | [[11-third-party-app-methodology]]*
