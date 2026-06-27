---
title: "Pro & developer workflows on iPad"
part: "05 — iPadOS as a Computer"
lesson: 05
est_time: "40 min read + 15 min labs"
prerequisites: [ios-xcode-and-the-build-system, how-ipados-diverges-from-ios]
tags: [ios, ipados, swift-playgrounds, shortcuts, developer-mode]
last_reviewed: 2026-06-26
---

# Pro & developer workflows on iPad

> **In one sentence:** The iPad is a genuine *creation* machine — you can author a SwiftUI app in Swift Playground and ship it to the App Store without ever touching a Mac, and you can automate the whole device through the App Intents / Shortcuts graph — but it is structurally **not** an *analysis* machine: the JIT/code-signing floor that makes it secure also forbids a full Xcode, an emulator, a general shell, and the entire libimobiledevice / iLEAPP / Frida forensics-and-RE toolchain, all of which still require the Mac.

## Why this matters

You finished `macos-mastery` on a Mac that *is* the forensics and development workstation — full Xcode, a Unix userland, the freedom to run `sqlite3` against any image, attach `lldb` to anything, and host a USB device over libimobiledevice. The natural question after Part 05's "iPad as a computer" framing is: **how far does that go?** Can the iPad replace the Mac for building apps, for automating real work, or — the question a forensicator always asks — for doing case work in the field on a tablet?

The honest answer has two halves, and both matter. As a **builder**, you should know that Apple has shipped a real, sanctioned path to build *and submit* an App Store app entirely on-device — that's a non-trivial capability with its own provenance trail. As a **forensicator**, you should know exactly *why* the iPad can never run your acquisition/analysis stack (it's the same AMFI/JIT mechanism you learned in [[code-signing-amfi-entitlements]], not a missing feature Apple will someday add), so you never waste field time trying — and so you recognize the artifacts an iPad-as-creation-tool leaves behind when one turns up in an investigation as the device that *authored* something.

## Concepts

### The hard floor: why there is no full Xcode on iPad

Start with the mechanism, because every limitation below is downstream of it. On macOS, a compiler is just another program: it writes machine code into a buffer, marks that buffer executable (`mmap` with `PROT_EXEC`), and jumps to it. That is **JIT** (just-in-time) codegen, and it's how a debugger evaluates expressions, how a language runtime tiers up hot code, and how an emulator translates a guest ISA at speed.

On iOS/iPadOS that move is illegal by default. AMFI enforces **W^X** (write-xor-execute): a memory page is either writable or executable, never both, and a page only becomes executable if its contents match a valid code signature checked at fault time (covered in [[code-signing-amfi-entitlements]] and [[dyld-shared-cache-and-amfi]]). The single escape hatch is the **`dynamic-codesigning`** entitlement, which lets a process call `mmap`/`mprotect` with the `MAP_JIT` flag to get a genuinely RWX region whose freshly-written bytes are *not* signature-checked. That entitlement is a **private, Apple-only** grant — in practice it is held by WebKit's `JavaScriptCore` (so Safari's JS engine can JIT) and a tiny set of system processes. A third-party App Store app cannot have it. A sideloaded app cannot have it. (Apple even narrowed the remaining grey-market routes: from iOS/iPadOS 18.4 onward, the debugger-mediated JIT trick that AltJIT/SideJIT/Jitterbug relied on was locked down to a true attached-debugger session.)

```
  macOS toolchain                 iOS/iPadOS app
  ───────────────                 ──────────────
  write code → buf                write code → buf
  mprotect(buf, RWX)   ── OK ──   mprotect(buf, RWX)   ── EXC_BAD_ACCESS / SIGKILL
  jmp buf                         (no dynamic-codesigning ⇒ no MAP_JIT ⇒ W^X kills it)
```

So a hosted, run-arbitrary-code Xcode — compile, JIT-evaluate in the debugger, run an iOS Simulator (itself a JIT-heavy macOS process), profile in Instruments — is not a porting problem Apple is lazy about. It is *structurally incompatible* with the platform's code-integrity model. The same wall is why every "console emulator" on iOS is either an interpreter (slow) or limited to recompilation tricks, and why there is no Python REPL, no `bash`, no `gcc`, no Frida runtime on a stock iPad.

Two corollaries forensicators and builders both get wrong. First, **sideloading does not buy JIT.** An AltStore/EU-marketplace app is still an ordinary sandboxed process; it is signed but it does **not** receive `dynamic-codesigning`, so it hits the same `EXC_BAD_ACCESS` → `SIGKILL` the instant it tries to execute a freshly-written page. Sideloading changes *who signs the app* and *how it's distributed* — not the code-integrity floor it runs under. Second, the historical grey-market routes (AltJIT/SideJIT/Jitterbug, which abused a wired-debugger handshake to flip a process JIT-capable) were narrowed from **iOS/iPadOS 18.4 onward**, where that capability was constrained to a genuine attached-debugger session — so even the tethered tricks now require a host actively debugging, which is itself a developer/Mac workflow, not an on-device one.

> 🖥️ **macOS contrast:** Your Mac is the development *and* forensics machine precisely because it has none of this floor — `clang` JITs freely, the iOS **Simulator runs on the Mac** (not on the iPad), `lldb` evaluates expressions, and Hardened-Runtime apps can still *opt in* to `com.apple.security.cs.allow-jit` for legitimate JIT. The entire toolchain this course teaches — `simctl`, `libimobiledevice`, `ipsw`, `frida`, `sqlite3` against an image — assumes that freedom. The iPad is the constrained complement, not a replacement workstation.

### How Swift Playground gets around the wall (it doesn't JIT)

If JIT is forbidden, how does **Swift Playground** run your code at all? By never JITing. Apple bundles a real **ahead-of-time** Swift toolchain inside the app: it compiles your source to a signed Mach-O *app bundle*, then installs and launches that bundle through the same development-install path Xcode-on-Mac uses — i.e. your code runs as a **normal, properly code-signed installed app**, not as bytes JIT'd inside the Swift Playground process. No `MAP_JIT`, no `dynamic-codesigning`, no W^X violation. The cost of staying inside the rules is exactly the set of features that *require* JIT: you get no general expression-evaluating debugger, no Instruments, no on-device Simulator, no third-party-emulator capability.

Two enabling pieces make this legal:

- **Developer Mode** (iOS/iPadOS 16+). Installing and running a *development-signed* app — one signed with your personal/team development certificate and carrying `get-task-allow=true` so the on-device debug stub can attach — requires the user to flip **Settings → Privacy & Security → Developer Mode**, which forces a reboot and a second on-screen confirmation. It deliberately "reduces device security" (Apple's own wording) by re-enabling developer-only install/debug surfaces. On a clean device this toggle doesn't even appear until a development workflow (Swift Playground building to-device, or a Mac pairing for debug) requests it. The flag is per-device and survives reboot.
- **Development signing via a Personal Team.** Sign into Swift Playground with an Apple Account and it provisions a free **Personal Team** development certificate + a development provisioning profile, the same as a free Apple ID in Xcode. Your built app is signed with that, AMFI accepts it under Developer Mode, and it runs. (See [[code-signing-amfi-entitlements]] for the cert/profile/entitlements chain this rides on.) The free-tier asymmetry is worth knowing: a **free** Personal-Team app's provisioning profile **expires in ~7 days** (you must re-build to keep it running) and you're capped on the number of distinct App IDs; a **paid** Developer Program membership lifts that to a year and unlocks distribution signing for the upload step below.

Mechanically, the on-device compile is the same `swiftc`/SwiftPM build you'd run on a Mac, just hosted inside the app, and the install is brokered by the same on-device `installd`/developer-services machinery a tethered Xcode would drive — the difference is only that the *host doing the signing and installing is the iPad itself*. Because the result is a real installed app, you debug it the way the platform allows (the app carries `get-task-allow=true` so the on-device debug stub can attach for basic step/inspect) — but you do **not** get JIT-backed expression evaluation, time-profiling Instruments, or address sanitizers, because those need the JIT/host tooling the device withholds.

> 🖥️ **macOS contrast:** This is the exact development-signing dance you'd do in Xcode on the Mac — Personal Team, `get-task-allow`, a development provisioning profile — except the *signing and install host is the iPad itself* instead of a tethered Mac. The artifact produced (a development-signed `.app`) is identical in kind; only the toolchain's home changes.

### Swift Playground as the on-device build-and-submit path

As of mid-2026 the current build is **Swift Playground 4.7** (build 2088) — Apple dropped the plural from the product name in early 2025; it was *Swift Playgrounds* through the 4.5.x line — which carries **Swift 6** and the **iOS 26 SDK** and runs on iPadOS 26.x. Since the version-4 line (2022, then still *Swift Playgrounds*), it is the **only Apple-sanctioned way to build *and ship* an App Store app from the device itself** — no Mac in the loop.

The project format is the key technical fact. An "App Playground" is **not** an `.xcodeproj`; it is a **`.swiftpm`** bundle — a Swift Package Manager package whose `Package.swift` declares an **`.iOSApplication`** product (a product type Apple added specifically for app playgrounds):

```swift
// Package.swift  — inside MyApp.swiftpm/
// swift-tools-version: 6.0
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "MyApp",
    platforms: [ .iOS("26.0") ],
    products: [
        .iOSApplication(
            name: "MyApp",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.myapp",
            teamIdentifier: "ABCDE12345",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .magicWand),
            accentColor: .presetColor(.purple),
            supportedDeviceFamilies: [ .pad, .phone ],
            supportedInterfaceOrientations: [ .portrait, .landscapeLeft ]
        )
    ],
    targets: [ .executableTarget(name: "AppModule", path: ".") ]
)
```

The bundle's anatomy:

```
MyApp.swiftpm/                  ← a directory that Finder/Files shows as one "file"
├── Package.swift               ← the .iOSApplication manifest above
├── Package.resolved            ← pinned SPM dependency graph (URLs + commit hashes)
├── MyApp.swift                 ← @main App entry; ContentView.swift; …
├── Assets.xcassets/            ← icon, accent color, images
└── … additional .swift sources, Resources/
```

The on-device flow, end to end, with no Mac:

1. **Author** in Swift Playground — full SwiftUI/UIKit, the App Intents framework, SPM dependencies by Git URL (resolved on-device into `Package.resolved`), live preview, and run-to-device (the AOT compile → sign → install path above, gated by Developer Mode).
2. **Sign in** with the Apple Account tied to a paid **Apple Developer Program** membership ($99/yr) — required for *submission*, not for local run.
3. **Upload to App Store Connect** from the *Build* / *Upload* affordance inside Swift Playground. The app archives, signs for distribution, and uploads directly to App Store Connect — the same destination `xcodebuild -exportArchive` + Transporter/`altool` reach from a Mac.
4. **Finish metadata and submit** in App Store Connect (screenshots, description, review notes) from the browser or the App Store Connect app. Review and release are unchanged from the Mac path.

The two pipelines reach the identical destination; the iPad just collapses several Mac steps into one on-device action:

```
  Mac (Xcode)                              iPad (Swift Playground)
  ───────────                              ────────────────────────
  edit .xcodeproj                          edit .swiftpm
        │                                        │
  xcodebuild archive                       (on-device swiftc AOT build)   ┐
        │                                        │                        │ one
  -exportArchive (distribution sign)       (distribution sign on-device)  │ "Upload"
        │                                        │                        │ action
  altool / Transporter upload              (upload on-device)             ┘
        └──────────────► App Store Connect ◄─────┘
                          (review · release — same for both)
```

What you give up versus Mac Xcode (the practical ceiling for "iPad as dev machine"): no app **extensions** authored in the same project (widgets/share/notification-service targets historically aren't first-class in the `.swiftpm` app product), no custom build phases / run scripts, no Instruments or sanitizers, no XCTest/UI-test targets you can drive, limited and shifting preview reliability across point releases (Swift Playground 4.6.x notably regressed previews and threw "multiple commands produce" SPM errors on projects that built clean in 4.5.1), and no CI/`xcodebuild` automation. It is excellent for a focused single-target SwiftUI app; it is not a substitute for a real Xcode project once you need extensions, tests, or build tooling — for which you move to the Mac (see [[ios-xcode-and-the-build-system]] and [[the-app-bundle-and-ipa-structure]]).

> 🔬 **Forensics note:** A `.swiftpm` is a **user-authored artifact with provenance.** It lives in the Swift Playground app container and, when "Store in iCloud" is on, in iCloud Drive under the app's folder — so it syncs and is recoverable from an iCloud acquisition ([[icloud-acquisition-and-advanced-data-protection]]). The bundle carries authorship signal: `Package.swift` embeds the `bundleIdentifier` and **`teamIdentifier`** (ties the project to a specific developer account), `Package.resolved` pins exact dependency commits (a supply-chain and timeline fingerprint), and source-file `mtime`s plus the bundle's container path place creation on *this* device. Submission leaves a parallel server-side trail in App Store Connect (build upload timestamps, the uploading Apple ID). An iPad used to *create* software is not anonymous.

### Shortcuts: the on-device automation surface

The iPad's scripting layer is **Shortcuts**, and underneath the friendly UI it is a real automation runtime worth understanding mechanistically. A shortcut is an ordered **action graph** executed by the `WorkflowKit` framework (the runtime daemon family behind the Shortcuts app). Each action is a node with an **identifier** and **parameters**; the document model on disk is a property list whose top-level key is **`WFWorkflowActions`** — an array of dictionaries, each carrying `WFWorkflowActionIdentifier` (e.g. `is.workflow.actions.gettext`) and `WFWorkflowActionParameters`.

Where the actions *come from* is the engineering substance: modern actions are **App Intents** (the `AppIntent` protocol, Apple's unified automation/Siri/Spotlight surface; older ones are legacy SiriKit `INIntent`s). Any third-party app can publish App Intents, and those automatically appear as Shortcuts actions and as parameters Siri/Spotlight can fill. A minimal one:

```swift
import AppIntents

struct ExportReport: AppIntent {
    static var title: LocalizedStringResource = "Export Report"
    @Parameter(title: "Case Number") var caseNumber: String
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let path = try ReportStore.export(case: caseNumber)   // runs inside the app's sandbox
        return .result(value: path)
    }
}
```

The instant an app ships that, "Export Report" is a Shortcuts action and a Siri phrase, with `caseNumber` as a fillable parameter. So Shortcuts is not a sandbox-escape — it's a **brokered RPC across app boundaries**, where each app declares (via its compiled App Intents metadata, surfaced through an on-device intent index) what it's willing to expose and the system mediates every call. The action still executes *inside the publishing app's own sandbox*, under that app's entitlements — Shortcuts never grants the *caller* the *callee's* permissions. In iPadOS 26 the Shortcuts app also gained **"intelligent actions"** that invoke Apple's on-device foundation model as a step in a graph.

Automations (the unattended trigger side) are the part that matters most forensically, because they encode *conditions under which the device acts without the user present*:

| Trigger class | Examples | Why it matters |
|---|---|---|
| Temporal | Time of day, alarm, sleep/wake | Scheduled, repeatable action (e.g., nightly cleanup) |
| Location/proximity | Arrive/leave a place, CarPlay, Bluetooth, **NFC tag** tap | Action bound to physical presence or a tag |
| State | Focus change, charger connect, Wi-Fi join, low battery | Action keyed to device context |
| Communication | Email/message received, app opened/closed | Event-driven reaction to inbound data or app use |

Combined with the action library — *Get Contents of URL* (arbitrary HTTP), *Run JavaScript on Web Page* (in Safari), *Run Script over SSH* (to a remote host), *Run Shortcut*, file read/write within granted scopes — Shortcuts is the closest thing iPadOS has to user scripting. It is still a **constrained action graph, not a shell**: no arbitrary process spawning, no native code, no filesystem access outside the document-picker/granted-scope model ([[files-external-storage-and-document-providers]]). For the full automation/threat surface see [[shortcuts-and-the-automation-surface]].

> 🔬 **Forensics note:** Shortcuts and their automations are **first-class user-intent artifacts** — and an under-watched one. The user's shortcuts live in the Shortcuts app's container, CloudKit-synced across the account's devices (so they also surface in an iCloud acquisition); a shared shortcut exports as a **signed `.shortcut` plist** (binary plist with the `WFWorkflowActions` array; signing was added so "Allow Untrusted Shortcuts" can gate imports). Parse the action graph and you read *intent*: a shortcut that POSTs photo-library contents to an attacker URL, deletes files on a schedule, or wipes history on a trigger is an automation-as-anti-forensics or exfil indicator. iLEAPP includes Shortcuts parsing. **Verify the exact on-disk database filename/path on your target image** — it has changed across iOS versions and the App-Intents migration; describe the mechanism, then confirm the path before you cite it in a report.

> ⚖️ **Authorization:** Shortcuts/automation artifacts can establish *premeditation* (a wipe-on-trigger automation authored before an event) and can attribute actions to a person via the authoring device and iCloud account. Treat the action graph as authored evidence: preserve the signed `.shortcut` exports and the on-device store under the same chain-of-custody discipline as any user document, and tie account-level (CloudKit) copies to lawful process for the iCloud account ([[ios-forensics-landscape-and-authorization]]).

### The authoring-evidence trail: an iPad-as-creation-tool is not anonymous

Pulling the forensic threads together: when an iPad is the device that *built* something — an app, an automation — it leaves a layered, cross-corroborating provenance trail, on-device and in the cloud. Where to look:

| Evidence | Location (verify exact path on target) | What it proves |
|---|---|---|
| `.swiftpm` project bundles | Swift Playground app container; iCloud Drive *Playgrounds* folder when iCloud is on | Source authorship; `teamIdentifier`/`bundleIdentifier` tie it to a developer account |
| `Package.resolved` | Inside each `.swiftpm` | Exact dependency commits at build time — a supply-chain + timeline fingerprint |
| Source-file `mtime`s + container path | Per-file metadata in the bundle | Places creation/editing on *this* device and dates it |
| Developer-Mode state | Device config (security policy) | Enabled ⇒ a development/sideloading workflow ran here (a normal user's is off) |
| Development cert + provisioning profile | Keychain / provisioning store ([[code-signing-amfi-entitlements]]) | The Apple Account/Team that signed builds on this device |
| Shortcuts + automations | Shortcuts app container, CloudKit-synced (verify filename) | Authored *intent*, including scheduled/triggered (anti-forensic) actions |
| Shared `.shortcut` exports | Files/Mail/Messages attachments, iCloud | Portable, signed copies of the action graph |
| App Store Connect records (server-side) | Account, via lawful process | Build-upload timestamps + uploading Apple ID — submission provenance |

The point for an examiner: software and automation authored on an iPad are **attributable** — to a device, an Apple Account, a developer team, and a moment in time — through several independent stores that corroborate one another. Treat each under normal chain-of-custody discipline; tie the CloudKit/App Store Connect copies to lawful process for the account ([[ios-forensics-landscape-and-authorization]], [[icloud-acquisition-and-advanced-data-protection]]).

### Pro multitasking: doing real work, not analysis work

iPadOS 26 is the inflection point for "iPad as a computer" ergonomics (the mechanics are in [[windowing-multitasking-and-external-display]]; here's the dev/pro-workflow lens). The base multitasking model became a **full macOS-like windowing system** — free-form, resizable, overlapping windows with a traffic-light close/minimize/tile control — and Apple **removed Slide Over and Split View** as the primary model. **Stage Manager** remains as an opt-in for grouping windows and is still the path to **independent extended-desktop windows on an external display** (M-series, ≥8 GB RAM). A swipe-from-top or cursor-to-top reveals a real, developer-customizable **menu bar**. And, leveraging Apple-silicon headroom, iPadOS 26 added **long-running, computationally-intensive Background Tasks** — the new `BGContinuedProcessingTask` API — surfaced through **Live Activities**: a *user-initiated* (button/gesture) video export or large build-style job runs to completion in the background with a visible, cancellable progress UI (and, on supported hardware, background GPU access), instead of being suspended by jetsam the moment it backgrounds ([[memory-jetsam-app-lifecycle]]).

Add a Magic Keyboard's trackpad + pointer, Apple Pencil, Files with a real list view / resizable columns / folders-in-Dock / per-type default apps, and Continuity (Universal Control, Sidecar, Handoff — see [[continuity-with-the-mac]]), and the iPad is a credible machine for *content* pro work: writing code in a SwiftUI app, design, audio/video editing, document and research work, remote-shelling into a real machine over SSH. What it is **not** is a host for the *systems* work this course is about.

### The escape hatch that *is* real: iPad as a thin client into a host

The honest refinement to "no full dev/forensics on iPad" is that the iPad makes an excellent **terminal into a machine that has none of these limits.** This is how most people who genuinely "develop on iPad" actually work, and it's worth separating cleanly from on-device capability:

- **SSH / mosh into a real host.** Clients like **Blink Shell** give you a persistent `mosh` session into a Mac, a Linux box, or a cloud VM — where the *real* `clang`, `python3`, `frida`, `libimobiledevice`, and `sqlite3` live. The compute happens on the host; the iPad is a keyboard, screen, and network endpoint.
- **Remote desktop into the Mac.** Screen Sharing / VNC / Jump Desktop / Screens, plus Apple's own **Sidecar** and **Universal Control** ([[continuity-with-the-mac]]), let you drive the Mac's full Xcode and forensics GUI from the iPad. You are looking at the Mac; the iPad renders pixels.
- **Browser-based dev.** **GitHub Codespaces** or a self-hosted **code-server** opens a full VS Code in Safari, backed by a container in the cloud. Source editing, terminals, and builds all execute remotely.
- **Sandboxed local interpreters (still inside the sandbox).** Apps like **a-Shell** (Unix commands compiled to WebAssembly/native, run inside the app's own sandbox) and **iSH** (an x86 *interpreter* running Alpine Linux — interpreted precisely *because* JIT is forbidden, hence slow) give a local Unix-ish feel, and **Working Copy** is a capable on-device git client. These are genuinely useful for editing and light scripting — but they run **inside one app's sandbox**, cannot see other apps' data, cannot host USB, and cannot acquire or instrument another device. They are not a forensics platform; they're a sandboxed scratchpad.

The line is crisp: the iPad can be a superb **front-end** to real dev/forensics compute, and it can run **sandboxed, interpreted** local tooling — but the heavy lifting (JIT-speed builds, device acquisition, dynamic instrumentation) always executes somewhere that *isn't* the iPad's app sandbox.

### The candid verdict: creation yes, analysis no

Put plainly, for this learner:

| Capability | iPad (stock, 2026) | Why |
|---|---|---|
| Author + ship a single-target SwiftUI App Store app | ✅ Swift Playground 4.7 → App Store Connect | AOT compile + dev signing, no JIT needed |
| Real Xcode (extensions, tests, Instruments, Simulator) | ❌ | Needs JIT / `dynamic-codesigning` — Apple-only |
| Automate the device / cross-app workflows | ✅ Shortcuts (App Intents graph) | Brokered RPC, not a shell |
| General Unix shell / `python3` / `sqlite3` / `clang` | ❌ | No userland; no JIT; sandboxed apps only |
| Run **libimobiledevice / pymobiledevice3** | ❌ | The iPad is the *target*, not a USB **host**; needs a Mac/PC |
| Run **iLEAPP / mvt / mac_apt** against a device image | ❌ | No Python runtime, no foreign-image mount, no filesystem freedom |
| Run **Frida / objection / lldb** for RE | ❌ | Needs JIT + injection + host tooling — see [[dynamic-analysis-with-frida]] |
| Mount/parse another device's filesystem or a DMG/E01 | ❌ | No block-device access; sandbox |

**The bottom line:** you can build apps and automate on an iPad, and with iPadOS 26 you can do serious *creation* work on it. You **cannot** run the acquisition (libimobiledevice/pymobiledevice3), parsing (iLEAPP/mac_apt/mvt), or reverse-engineering (Frida/objection/lldb/Ghidra) toolchain on the iPad — every one of those needs a Mac (or at least a real general-purpose host), and that's by design, not omission. In a forensics workflow the iPad is a **subject of acquisition**, and as a creation tool a **source of authored artifacts** — never the analysis console. Keep the Mac as the workstation ([[forensics-and-dev-workstation-setup]]).

## Hands-on

There is no on-device shell — everything here runs **on the Mac**, dissecting the *artifacts* an iPad workflow produces and demonstrating the Mac-side equivalents of the on-iPad build/submit path.

### Inspect a `.swiftpm` app-playground bundle

A `.swiftpm` authored on iPad opens identically on macOS (Swift Playground and Xcode both consume it). Treat the bundle as a directory:

```bash
# It's a package directory, not an opaque file
ls -la MyApp.swiftpm/
#   Package.swift  Package.resolved  MyApp.swift  ContentView.swift  Assets.xcassets/

# The manifest reveals bundle id + the team it was provisioned under
grep -E 'bundleIdentifier|teamIdentifier|displayVersion' MyApp.swiftpm/Package.swift

# Package.resolved pins exact dependency commits — a supply-chain + timeline fingerprint
plutil -p MyApp.swiftpm/Package.resolved 2>/dev/null || cat MyApp.swiftpm/Package.resolved

# Build it headless on the Mac to confirm it's a real SPM package
cd MyApp.swiftpm && swift build       # resolves & compiles the AppModule target
```

### The Mac-side equivalent of "Upload" (what Swift Playground automates on-device)

```bash
# On the Mac, the same App Store Connect destination is reached via:
xcodebuild -scheme MyApp -archivePath build/MyApp.xcarchive archive
xcodebuild -exportArchive -archivePath build/MyApp.xcarchive \
           -exportOptionsPlist ExportOptions.plist -exportPath build/export
xcrun altool --upload-app -f build/export/MyApp.ipa \
             -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
# Swift Playground collapses archive→sign-for-distribution→upload into one on-device action.
```

### Read the structure of a shared Shortcut

```bash
# A shared/exported shortcut is a (signed) property list with an action array
plutil -p MyShortcut.shortcut | head -40
# Look for the action graph:
#   WFWorkflowActions => [ { WFWorkflowActionIdentifier => is.workflow.actions.downloadurl,
#                            WFWorkflowActionParameters => { WFURL => https://… } }, … ]

# Pull just the ordered action identifiers (the program, in execution order)
plutil -convert json -o - MyShortcut.shortcut \
  | jq -r '.WFWorkflowActions[].WFWorkflowActionIdentifier'
```

### Confirm the JIT wall from the entitlements side

```bash
# Inspect any installed app's entitlements — third-party apps never carry dynamic-codesigning
codesign -d --entitlements :- /Applications/SomeApp.app 2>/dev/null \
  | plutil -p - | grep -i 'jit\|dynamic-codesigning\|allow-unsigned'
# JavaScriptCore (system) is where the real grant lives; an App Store app shows none.
```

## 🧪 Labs

> These labs are **device-free**. They dissect the *artifacts* iPad workflows leave and demonstrate Mac-side equivalents. The fidelity caveat for this lesson is unusual: the **Simulator cannot exercise the on-device build-and-submit pipeline at all** (Swift Playground's AOT-compile-sign-install path, Developer Mode, the Personal-Team provisioning, and the WorkflowKit/Shortcuts store are device-only and do not exist in the Simulator), so the build/submit and Shortcuts-store steps are **read-only walkthroughs**, paired with Mac-side artifact dissection on real files.

### Lab 1 — Dissect a `.swiftpm` app-playground bundle (substrate: Mac filesystem + a real/sample `.swiftpm`)

1. On the Mac, create one in Xcode (**File ▸ New ▸ Project ▸ App Playground**, or open Swift Playground for Mac) — this produces the *same* `.swiftpm` an iPad would, so the structure is faithful even though authoring host differs.
2. `ls -la MyApp.swiftpm/` and confirm `Package.swift`, `Package.resolved`, and the `.swift` sources sit at the bundle root.
3. `grep -E 'iOSApplication|bundleIdentifier|teamIdentifier' Package.swift`. Identify the `.iOSApplication` product and note the two fields that attribute the project to an account/device.
4. `swift build` it. Confirm it compiles as a plain SPM package — proving the "no special Xcode project, just a package" claim.
5. **Forensic framing:** list what about this bundle would let you (a) attribute it to a developer account, (b) reconstruct its dependency supply chain at a point in time, (c) place its creation on a specific device. (Answers: `teamIdentifier`/`bundleIdentifier`; `Package.resolved` pinned commits; container path + source `mtime`s.)

### Lab 2 — Read-only walkthrough: build + submit an App Store app entirely on iPad

Narrate (no device required) the full pipeline and name each underlying mechanism:

1. **Author** in Swift Playground 4.7 → SwiftUI app, optionally add an SPM dependency by URL (on-device resolution writes `Package.resolved`).
2. **Run to device** → triggers the **AOT compile → development-sign (Personal Team, `get-task-allow=true`) → install** path; first run prompts **Settings → Privacy & Security → Developer Mode** (reboot + confirm). *This is the step the Simulator and a non-developer device cannot reproduce.*
3. **Upload** → with a paid Developer Program account signed in, Swift Playground archives, distribution-signs, and uploads to **App Store Connect** — equivalent to the Mac's `xcodebuild -exportArchive` + `altool`/Transporter (run the Mac equivalent from **Hands-on** to see the parts Swift Playground collapses).
4. **Submit** metadata in App Store Connect. Enumerate the **provenance trail** this leaves both on-device (the `.swiftpm`, Developer-Mode flag, dev cert/profile in the keychain) and server-side (App Store Connect build-upload timestamps + uploading Apple ID).

### Lab 3 — Shortcut action graph as evidence (substrate: Mac + a real exported `.shortcut`; device store = sample image)

1. Export a shortcut (Share ▸ *Copy/Export* on any Apple device, or grab a sample `.shortcut`) to the Mac.
2. `plutil -p file.shortcut | head -60` — locate `WFWorkflowActions` and read the ordered action nodes.
3. `plutil -convert json -o - file.shortcut | jq -r '.WFWorkflowActions[].WFWorkflowActionIdentifier'` — print the "program" as an ordered identifier list. Pick out any `is.workflow.actions.downloadurl` (network), `…runjavascriptonwebpage`, or file/delete actions.
4. **Device store (sample image only):** in a public iOS reference image, locate the Shortcuts app container and the WorkflowKit store; run iLEAPP's Shortcuts module against it. **Confirm the exact store filename/path from the tool output before quoting it** — it is version-dependent. The Simulator will not contain this store; use a sample image.
5. **Forensic framing:** write one sentence each for how a malicious shortcut could (a) exfiltrate data and (b) act as anti-forensics, and what in the graph would prove intent.

### Lab 4 — Prove the JIT wall (substrate: Mac, read-only reasoning + `codesign`)

1. `codesign -d --entitlements :- <any App Store .app>` on the Mac and confirm **no** `dynamic-codesigning` / `com.apple.security.cs.allow-jit` is present on a third-party app.
2. Contrast: explain (from [[code-signing-amfi-entitlements]] / [[dyld-shared-cache-and-amfi]]) why WebKit's `JavaScriptCore` is the canonical holder of the JIT grant and why Safari can therefore JIT JavaScript while a sideloaded emulator cannot.
3. Conclude in your own words why this single mechanism forecloses (a) full Xcode-on-iPad, (b) the iOS Simulator on iPad, and (c) a Frida runtime on iPad — and why Swift Playground is unaffected (it AOT-compiles and installs a signed app; it never JITs).

## Pitfalls & gotchas

- **"I'll just install Xcode on my iPad."** There is no Xcode for iPad and there structurally can't be a full one — it needs JIT (`dynamic-codesigning`) for the debugger, the Simulator, and Instruments. Swift Playground is the on-device dev story; the Mac is the real Xcode.
- **Swift Playground ≠ no Apple Developer Program.** *Local run* is free (Personal Team + Developer Mode). *App Store submission* still requires the paid $99/yr Developer Program account signed in — don't promise "ship from iPad, no cost."
- **`.swiftpm` is not `.xcodeproj`.** It's a Swift package with an `.iOSApplication` product. Reflexively `open`-ing it expecting an Xcode project, or trying to add extension/test targets the format doesn't support, wastes time. Graduate to a real Xcode project on the Mac when you need extensions, XCTest, or build tooling.
- **Point-release fragility.** Swift Playground previews and SPM behavior have regressed across point releases (the 4.6.x "multiple commands produce" / broken-preview episode). It is a moving target; verify the *current* build's behavior, don't assume a feature persists across versions.
- **Developer Mode lowers the device's security posture and is logged.** Don't flip it casually on a sensitive device, and in forensics treat its *enabled* state as a meaningful finding — a normal user's device has it off; an enabled flag (plus a dev cert in the keychain and a `.swiftpm` in the container) signals a development/sideloading workflow.
- **Shortcuts is not a sandbox escape.** It can only call App Intents an app chose to publish and only touch files through granted scopes. Don't model it as a shell; do model the *exposed-intent surface* as the actual attack surface ([[the-sandbox-and-tcc]]).
- **Forensics on an iPad still happens on a Mac.** The iPad is the acquisition *target* (logical/full-file-system via a Mac running libimobiledevice/pymobiledevice3), never the analysis host. Don't plan field work around "analyze it on the tablet."
- **Don't confuse "Simulator" with "on iPad."** The iOS Simulator is a *macOS* process; it never runs on an iPad. On-device app testing happens via Swift Playground's real-install path or via a Mac driving the iPad over USB.

## Key takeaways

- One mechanism explains everything: **AMFI's W^X + the Apple-only `dynamic-codesigning` (MAP_JIT) entitlement** forbid JIT, which forecloses full Xcode, the Simulator, emulators, and a Frida/lldb runtime on iPad. It's structural, not a missing feature.
- **Swift Playground is the sanctioned on-device dev path** and the *only* way to build **and submit** an App Store app without a Mac — it stays legal by **AOT-compiling and installing a signed app, never JITing**.
- Building locally needs only a **free Personal Team + Developer Mode**; **submission needs the paid Developer Program**. The project format is a **`.swiftpm`** package with an **`.iOSApplication`** product, not an `.xcodeproj`.
- **Shortcuts** is the real automation layer — an **App Intents action graph** (`WFWorkflowActions`) executed by **WorkflowKit**, brokered RPC across app boundaries, not a shell.
- **iPadOS 26** makes the iPad a credible *creation* machine (full windowing, menu bar, Apple-silicon Background Tasks via Live Activities, a real Files app) — for content work, not systems work.
- **Verdict:** the iPad **builds and automates**; it **cannot run the acquisition/parsing/RE toolchain** (libimobiledevice, iLEAPP/mvt/mac_apt, Frida/objection/lldb) — all Mac-only. In forensics it's an **acquisition target** and an **authored-artifact source**, never the analysis console.
- **Authoring leaves provenance:** `.swiftpm` bundles (with `teamIdentifier`/`bundleIdentifier`/`Package.resolved`), Developer-Mode state, a dev cert in the keychain, App Store Connect upload records, and Shortcuts action graphs all attribute creation to a device and account.

## Terms introduced

| Term | Definition |
|---|---|
| Swift Playground | Apple's on-device Swift IDE (renamed from the plural *Swift Playgrounds* in early 2025); since v4, the only sanctioned path to build *and submit* an App Store app from the device. Current: 4.7 (build 2088), Swift 6 / iOS 26 SDK |
| `.swiftpm` | App-playground bundle format: a Swift Package Manager package directory whose `Package.swift` declares an app product |
| `.iOSApplication` | The SPM product type (from `AppleProductTypes`) that makes a package build an iOS/iPadOS app; carries bundle id, team id, icon, version |
| JIT (just-in-time) | Generating machine code at runtime and executing it; the basis of debuggers, fast language runtimes, and emulators |
| W^X | Write-xor-execute: a memory page is writable or executable, never both — enforced by AMFI on iOS |
| `dynamic-codesigning` | The private, Apple-only entitlement that permits `MAP_JIT` RWX pages (JIT); held by JavaScriptCore and a few system processes, never by third-party apps |
| `MAP_JIT` | The `mmap`/`mprotect` flag that, with `dynamic-codesigning`, yields a JIT-capable RWX region whose bytes skip signature checks |
| AOT (ahead-of-time) | Compiling to a finished signed binary *before* run; how Swift Playground produces a runnable app without JIT |
| Developer Mode | iOS/iPadOS 16+ per-device toggle (Settings ▸ Privacy & Security) that re-enables development install/debug, lowering security; reboot + confirm required |
| Personal Team | The free development signing team a plain Apple Account provides; enough to run locally, not to submit |
| Shortcuts | The on-device automation app; executes an action graph via the WorkflowKit runtime |
| WorkflowKit | The framework/daemon family that runs Shortcuts action graphs |
| App Intents | The modern framework by which an app exposes actions to Shortcuts, Siri, and Spotlight (the `AppIntent` protocol) |
| `WFWorkflowActions` | The top-level array key in a shortcut's property list — the ordered list of action nodes (its "program") |
| `.shortcut` | The (signed) property-list file a shared/exported shortcut serializes to |
| Background Tasks (iPadOS 26) | Long-running, compute-intensive jobs (the `BGContinuedProcessingTask` API; must be user-initiated) surfaced as Live Activities, exploiting Apple-silicon headroom |

## Further reading

- Apple — *Swift Playground* developer page (developer.apple.com/swift-playground) and *Swift Playground User Guide* (support.apple.com/guide/playgrounds-ipad); *Distributing apps you create with Swift Playground*
- Apple Developer — *Enabling Developer Mode on a device* (developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- Apple Developer — *Allow execution of JIT-compiled code* entitlement (`com.apple.security.cs.allow-jit`) and the App Intents framework documentation; *Upload builds* (App Store Connect Help)
- Apple — iPadOS 26 newsroom + WWDC25 sessions on the windowing model, the menu bar, and Background Tasks (the windowing mechanics are in [[windowing-multitasking-and-external-display]])
- Saagar Jha — *Jailed Just-in-Time Compilation on iOS* (saagarjha.com) — the definitive deep dive on `dynamic-codesigning`, `MAP_JIT`, and JavaScriptCore's JIT grant
- Cephalopod Studio — *Lessons from Developing an App on the iPad in Swift Playgrounds from Start to Finish* — a real submit-from-iPad account and its ceilings
- Alexis Brignoni — **iLEAPP** (github.com/abrignoni/iLEAPP), including its Shortcuts parsing module; Apple Platform Security guide — AMFI / code-signing / Developer Mode
- `man codesign`, `man plutil`, `xcrun altool --help`, `swift build --help` — exact flag semantics on your toolchain

---
*Related lessons: [[ios-xcode-and-the-build-system]] | [[how-ipados-diverges-from-ios]] | [[code-signing-amfi-entitlements]] | [[shortcuts-and-the-automation-surface]] | [[windowing-multitasking-and-external-display]] | [[dynamic-analysis-with-frida]] | [[the-app-bundle-and-ipa-structure]]*
